# ALEX STANDARD LIBRARY — compiler.linker
#
# Édition des liens de modules IR (compiler.ir) : table des symboles exportés, résolution des imports
# (use m / from m use a, b), détection des modules absents, des symboles introuvables, des doublons et des
# cycles d'import ; ordre d'initialisation (dépendances d'abord), élimination des fonctions jamais
# référencées, carte d'édition des liens, et paquet unique sérialisable (dict / JSON) exécutable par
# l'interpréteur IR.
#
#   use compiler.linker as ln
#   l := ln.Linker()
#   l.add_source("func double(x) => x * 2\nfunc inutile() => 0\n", "outils.al")
#   l.add_source("from outils use double\nprint(double(21))\n", "main.al")
#   prog := l.link("main")                 # LinkedProgram (LinkError si quelque chose manque)
#   print(prog.order)                      # ["outils", "main"]
#   prog.strip_unused()                    # retire « inutile »
#   print(prog.map_text())                 # carte : modules, fonctions, tailles, exports, imports
#   prog.run()                             # 42
#   paquet := prog.to_dict()               # { "format": "alex-ir-bundle", ... } ; ln.load_bundle(paquet)
#
# Codes de diagnostic : E0502 symbole introuvable, E0503 module en double, E0504 cycle d'import,
# E0505 module introuvable, E0506 point d'entrée absent.
# Erreurs : LinkError (link, quand un diagnostic d'erreur existe), ValueError (paquet invalide).

from core use len, type
from collections use append, pop
use string as _s
use compiler.ir as _ir
use compiler.diagnostics as _dg
use compiler.codegen as _cg

class Symbol:
    func init(module, name, kind, size=0):
        self.module = module
        self.name = name
        self.kind = kind            # func | var
        self.size = size

    func qualified():
        return self.module + "." + self.name

func _imports_of(m):
    out := []
    for ins in m.main.code:
        if ins.op == "IMPORT":
            append(out, [ins.arg[0], null, ins.line])
        elif ins.op == "IMPORT_FROM":
            append(out, [ins.arg[0], ins.arg[1], ins.line])
    for k in m.order:
        for ins in m.functions[k].code:
            if ins.op == "IMPORT":
                append(out, [ins.arg[0], null, ins.line])
            elif ins.op == "IMPORT_FROM":
                append(out, [ins.arg[0], ins.arg[1], ins.line])
    return out

func _exports_of(m):
    out := {}
    i := 0
    code := m.main.code
    while i < len(code):
        ins := code[i]
        if ins.op == "DECLARE" and not _s.starts_with(ins.arg, "$"):
            kind := "var"
            if i > 0 and code[i - 1].op == "MAKE_FUNC":
                kind = "func"
            if ins.arg in m.functions:
                kind = "func"
            size := 0
            if kind == "func" and ins.arg in m.functions:
                size = len(m.functions[ins.arg].code)
            out[ins.arg] = Symbol(m.name, ins.arg, kind, size)
        elif ins.op == "IMPORT_FROM":
            for nm in ins.arg[1]:
                out[nm] = Symbol(m.name, nm, "import", 0)
        i += 1
    return out

class LinkedProgram:
    func init(modules, order, entry, symbols):
        self.modules = modules        # nom -> IrModule
        self.order = order
        self.entry = entry
        self.symbols = symbols        # nom de module -> {nom: Symbol}
        self.removed = []

    func module(name):
        return self.modules[name]

    func run(capture=false, builtins=null):
        vm := _ir.Interpreter(builtins)
        if capture:
            vm.capture()
        for nm in self.order:
            vm.register(self.modules[nm])
        vm.load(self.entry)
        return vm

    func instruction_count():
        n := 0
        for nm in self.order:
            n += self.modules[nm].instruction_count()
        return n

    # Retire les fonctions de haut niveau jamais référencées (hors module d'entrée) ; noms retirés.
    func strip_unused():
        refs := {}
        for nm in self.order:
            m := self.modules[nm]
            codes := [m.main.code] + [m.functions[k].code for k in m.order]
            for k in m.order:
                for d in m.functions[k].defaults:
                    append(codes, m.functions[k].defaults[d])
            for code in codes:
                for ins in code:
                    if ins.op == "LOAD" or ins.op == "LOAD_ATTR":
                        refs[ins.arg] = true
                    elif ins.op == "IMPORT_FROM":
                        for x in ins.arg[1]:
                            refs[x] = true
        out := []
        for nm in self.order:
            if nm == self.entry:
                continue
            m := self.modules[nm]
            code := m.main.code
            keep := []
            i := 0
            while i < len(code):
                ins := code[i]
                if ins.op == "MAKE_FUNC" and i + 1 < len(code) and code[i + 1].op == "DECLARE" and code[i + 1].arg == ins.arg and not (ins.arg in refs):
                    fname := ins.arg
                    append(out, nm + "." + fname)
                    m.functions = _without(m.functions, fname)
                    m.order = [k for k in m.order if k != fname and not _s.starts_with(k, fname + ".")]
                    m.exports = [e for e in m.exports if e != fname]
                    i += 2
                    continue
                append(keep, ins)
                i += 1
            m.main.code = keep
            self.symbols[nm] = _exports_of(m)
        self.removed = self.removed + out
        return out

    func map_text():
        lines := ["; carte d'édition des liens — entrée : " + self.entry, "; ordre d'initialisation : " + _s.join(" -> ", self.order)]
        for nm in self.order:
            m := self.modules[nm]
            append(lines, "")
            append(lines, "module " + nm + " (" + str(m.instruction_count()) + " instructions)")
            imps := _imports_of(m)
            for im in imps:
                if im[1] == null:
                    append(lines, "  import  " + im[0])
                else:
                    append(lines, "  import  " + im[0] + " : " + _s.join(", ", im[1]))
            syms := self.symbols[nm]
            for k in _sorted_keys(syms):
                s := syms[k]
                if s.kind == "func":
                    append(lines, "  func    " + _pad(s.qualified(), 32) + str(s.size) + " instr.")
                elif s.kind == "var":
                    append(lines, "  var     " + s.qualified())
        if len(self.removed) > 0:
            append(lines, "")
            append(lines, "; retirées (jamais référencées) : " + _s.join(", ", self.removed))
        return _s.join("\n", lines)

    func to_dict():
        return {"format": "alex-ir-bundle", "version": 1, "entry": self.entry, "order": self.order,
                "modules": [_ir.to_dict(self.modules[nm]) for nm in self.order]}

func _without(d, key):
    out := {}
    for k in d:
        if k != key:
            out[k] = d[k]
    return out

func _pad(s, n):
    out := s
    while len(out) < n:
        out += " "
    return out

func _sorted_keys(d):
    ks := [k for k in d]
    i := 1
    while i < len(ks):
        v := ks[i]
        j := i - 1
        while j >= 0 and ks[j] > v:
            ks[j + 1] = ks[j]
            j -= 1
        ks[j + 1] = v
        i += 1
    return ks

class Linker:
    func init():
        self.modules = {}
        self.names = []
        self.externals = []      # modules fournis à l'exécution (non vérifiés)
        self.diagnostics = _dg.DiagnosticBag("<édition des liens>")

    func add(m):
        if m.name in self.modules:
            self.diagnostics.error("E0503", "module '" + m.name + "' ajouté deux fois", 0, 0, 1, "LinkError")
            return self
        self.modules[m.name] = m
        append(self.names, m.name)
        return self

    # Compile un texte source et ajoute son module (nom tiré du fichier) ; CompileResult.
    func add_source(source, file, opt_level=2):
        r := _cg.compile(source, file, opt_level)
        if not r.ok:
            self.diagnostics.extend(r.diagnostics)
            return r
        self.add(r.ir)
        return r

    func allow_external(name):
        append(self.externals, name)
        return self

    func symbols():
        out := {}
        for nm in self.names:
            out[nm] = _exports_of(self.modules[nm])
        return out

    func resolve():
        syms := self.symbols()
        for nm in self.names:
            for im in _imports_of(self.modules[nm]):
                target := im[0]
                if not (target in self.modules):
                    if not (target in self.externals):
                        self.diagnostics.error("E0505", "module '" + nm + "' : module importé '" + target + "' introuvable", im[2], 0, 1, "LinkError")
                    continue
                if im[1] != null:
                    for s in im[1]:
                        if not (s in syms[target]):
                            self.diagnostics.error("E0502", "module '" + nm + "' : symbole '" + s + "' introuvable dans '" + target + "'", im[2], 0, 1, "LinkError")
        return syms

    func deps(name):
        out := []
        for im in _imports_of(self.modules[name]):
            if im[0] in self.modules and not (im[0] in out):
                append(out, im[0])
        return out

    # Ordre topologique depuis entry ; diagnostic E0504 sur cycle.
    func init_order(entry):
        order := []
        state := {}
        stack := []
        self._visit(entry, state, order, stack)
        return order

    func _visit(nm, state, order, stack):
        if nm in state:
            if state[nm] == 1:
                cyc := []
                started := false
                for s in stack:
                    if s == nm:
                        started = true
                    if started:
                        append(cyc, s)
                append(cyc, nm)
                self.diagnostics.error("E0504", "cycle d'import : " + _s.join(" -> ", cyc), 0, 0, 1, "LinkError")
            return
        state[nm] = 1
        append(stack, nm)
        for d in self.deps(nm):
            self._visit(d, state, order, stack)
        pop(stack)
        state[nm] = 2
        append(order, nm)

    func link(entry="main", strict=true):
        if not (entry in self.modules):
            self.diagnostics.error("E0506", "point d'entrée '" + entry + "' absent (modules : " + _s.join(", ", self.names) + ")", 0, 0, 1, "LinkError")
        syms := {}
        order := []
        if entry in self.modules:
            syms = self.resolve()
            order = self.init_order(entry)
        if strict and self.diagnostics.has_errors():
            raise("LinkError", _s.join(" ; ", [d.message for d in self.diagnostics.errors()]))
        mods := {}
        for nm in order:
            mods[nm] = self.modules[nm]
        return LinkedProgram(mods, order, entry, syms)

func load_bundle(d):
    if type(d) != "dict" or not ("format" in d) or d["format"] != "alex-ir-bundle":
        raise("ValueError", "load_bundle : ce n'est pas un paquet IR ALEX")
    mods := {}
    for md in d["modules"]:
        m := _ir.from_dict(md)
        mods[m.name] = m
    l := Linker()
    for nm in d["order"]:
        l.add(mods[nm])
    return LinkedProgram(mods, d["order"], d["entry"], l.symbols())

func link_sources(pairs, entry="main"):
    l := Linker()
    for p in pairs:
        l.add_source(p[1], p[0])
    return l.link(entry)
