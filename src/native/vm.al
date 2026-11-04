# ALEX — native.vm
#
# Construction de la machine virtuelle écrite en ALEX (étape D, docs/SELFHOST.md) : runtime natif + runtime du mode
# dynamique + interpréteur runtime/vm/vm.al + table des modules natifs générée ici depuis le registre
# (native.dyn_registry), compilés en un exécutable ELF x86-64 (ou PE32+ avec windows=true).
#
#   use native.vm as nv
#   nv.build_vm("build/alexvm")                    # puis : build/alexvm prog.albc
#   src := nv.module_table_source(texte_du_runtime) # source ALEX de __vm_module / __vm_core_boot
#
# Erreurs : NativeError (runtime incohérent), IoError (fichiers du runtime illisibles).

from core use len
from collections use append
use string as _s
use io as _io
use native.ir as ir
use native.dyn_registry as _reg

const _PARAMS := ["f", "n", "a0", "a1", "a2", "a3", "a4", "a5", "a6", "a7", "x"]

# Fonctions du runtime : nom -> [nombre de paramètres, renvoie une valeur].
func runtime_signatures(text):
    out := {}
    lines := _s.split(text, "\n")
    i := 0
    while i < len(lines):
        line := lines[i]
        i += 1
        if not _s.starts_with(line, "func "):
            continue
        # signature éventuellement sur plusieurs lignes : jusqu'à la parenthèse fermante
        while _s.find(line, ")") < 0 and i < len(lines):
            line = line + " " + _s.trim(lines[i])
            i += 1
        p := _s.find(line, "(")
        q := _s.find(line, ")")
        if p < 0 or q < p:
            continue
        name := _s.substring(line, 5, p)
        inner := _s.trim(_s.substring(line, p + 1, q))
        n := 0 if inner == "" else _s.count(inner, ",") + 1
        out[name] = [n, _s.contains(_s.substring(line, q, len(line)), "->")]
    return out

func _quote(v):
    out := "\""
    for ch in v:
        if ch == '"':
            out += "\\\""
        elif ch == '\\':
            out += "\\\\"
        elif ch == '\n':
            out += "\\n"
        elif ch == '\t':
            out += "\\t"
        else:
            out += str(ch)
    return out + "\""

func _int_lit(v):
    if v == -9223372036854775807 - 1:
        return "(-9223372036854775807 - 1)"
    return str(v)

class _Gen:
    func init(sigs):
        self.sigs = sigs
        self.lines = []
        self.wrappers = {}
        self.nwrap = 0

    func emit(s):
        append(self.lines, s)

    # Code d'une native : la fonction __nat_ elle-même (11 paramètres) ou une enveloppe qui n'en passe qu'une partie.
    func native_code(module, ex):
        impl := "__nat_" + ("_native_core" if module == "core" else module) + "__" + ex[0]
        impl = _s.replace(impl, ".", "_")
        # version propre à la VM (runtime/vm/vm.al : ffi, réflexion...) prioritaire sur celle du mode dynamique
        own := "__vm" + _s.substring(impl, 1, len(impl))
        if own in self.sigs:
            impl = own
        if not (impl in self.sigs):
            return "__dyn_native_missing"
        sg := self.sigs[impl]
        if sg[0] == 11 and sg[1]:
            return impl
        if impl in self.wrappers:
            return self.wrappers[impl]
        w := "__vmw_" + str(self.nwrap)
        self.nwrap += 1
        self.wrappers[impl] = w
        # comme le mode dynamique : la native reçoit (n, a0, a1...), au plus 9 paramètres
        k := sg[0] if sg[0] < 9 else 9
        args := _s.join(", ", [_PARAMS[1 + i] for i in 0..k])
        params := _s.join(", ", [p + ": int" for p in _PARAMS])
        self.emit("func " + w + "(" + params + ") -> int:")
        if sg[1]:
            self.emit("    return " + impl + "(" + args + ")")
        else:
            self.emit("    " + impl + "(" + args + ")")
            self.emit("    return 0")
        self.emit("")
        return w

    # Expression ALEX de la valeur d'un export (export_value de native.dyn).
    func export_value(module, ex):
        ck := ex[4]
        if ck == 1:
            return "0"
        if ck == 2:
            return "__dyn_bool(" + ("true" if ex[5] != 0 else "false") + ")"
        if ck == 3:
            return "__dyn_int(" + _int_lit(ex[5]) + ")"
        if ck == 4:
            return "__dyn_float_bits(" + _int_lit(ex[6]) + ")"
        if ck == 5:
            return "__dyn_str(" + _quote(ex[7]) + ")"
        if ex[1]:
            return "__vm_func_by_id(" + str(ex[2]) + ")"
        return "__dyn_native_new(__fnaddr(\"" + self.native_code(module, ex) + "\"), " + _quote(ex[3]) + ")"

    func instance_func(fname, module, exports):
        body := []
        for ex in exports:
            append(body, "    __dyn_set_member(o, " + _quote(ex[0]) + ", " + self.export_value(module, ex) + ")")
        self.emit("func " + fname + "() -> int:")
        self.emit("    o := __dyn_new_instance(" + _quote(module) + ")")
        for b in body:
            self.emit(b)
        self.emit("    return o")
        self.emit("")

func module_table_source(runtime_text):
    g := _Gen(runtime_signatures(runtime_text))
    k := 0
    names := []
    for mm in _reg.MODULES:
        g.instance_func("__vm_mod_" + str(k), mm[0], mm[1])
        append(names, mm[0])
        k += 1
    g.instance_func("__vm_core_boot", "core", _reg.BOOTSTRAP_CORE)
    collect := "__dyn_native_missing"
    for mm in _reg.MODULES:
        if mm[0] == "_native_gc":
            for ex in mm[1]:
                if ex[0] == "collect":
                    collect = g.native_code(mm[0], ex)
    g.emit("# Code de la native gc.collect (la VM efface la pile avant une collecte explicite).")
    g.emit("func __vm_gc_collect_code() -> int:")
    g.emit("    return __fnaddr(\"" + collect + "\")")
    g.emit("")
    g.emit("# Instance du module natif `name` (nouvelle à chaque import, comme le mode dynamique), 0 si inconnu.")
    g.emit("func __vm_module(name: str) -> int:")
    k = 0
    while k < len(names):
        g.emit("    if name == " + _quote(names[k]) + ":")
        g.emit("        return __vm_mod_" + str(k) + "()")
        k += 1
    g.emit("    return 0")
    g.emit("")
    return "\n# ---- Table des modules natifs (générée par native.vm) ----\n\n" + _s.join("\n", g.lines) + "\n"

# Point d'entrée du programme natif : état de la VM en globale 1, puis __vm_main (appelé avant le code du module vide).
func extend(h):
    g0 := h.new_global()
    g1 := h.new_global()
    if g0 != 0 or g1 != 1:
        raise("RuntimeError", "VM : les globales 0 et 1 doivent être l'état du runtime et celui de la VM")
    cl := ir.Ins(ir.CALL)
    cl.callee = h.runtime_function("__vm_main")
    f0 := h.prog.functions[0]
    f0.runtime = true
    f0.code = [cl] + f0.code
