# ALEX — native.build
#
# Chaîne du compilateur natif écrit en ALEX (étape C) : chargement des modules comme `alexc build --native`
# (portage du ModuleLoader de src/NativeCodegen.cpp), abaissement vers l'IR (native.lower), intégration des
# petites fonctions (native.inline) et génération de l'exécutable (native.x64).
#
# Les modules de la stdlib sont remplacés par leur version native typée (math, string, io, os, hw, tasks,
# asyncio, posix, wingui) ; un module de la stdlib portant l'en-tête « # alex: native » est compilé depuis son
# fichier ; « # alex: intrinsics » lui donne en plus accès aux intrinsèques du runtime. Les sources du runtime et
# de la stdlib native sont de simples fichiers ALEX sous runtime/alex/ (native/*.al, stdlib/*.al), à côté de
# stdlib/ : la chaîne d'outils ne lit aucun fichier C++.
#
#   use native.build as nn
#   p := nn.lower_program("prog.al")             # IrProgram
#   nn.build("prog.al", "prog")                   # exécutable ELF x86-64 Linux
#   nn.build("prog.al", "prog.exe", null, false, true)   # exécutable Windows x64 (PE32+)
#
# Erreurs : NativeError (hors du sous-ensemble natif), ModuleNotFoundError, CyclicImportError, erreurs du
# front-end (SyntaxError, NameError, TypeCheckError...).

from core use len, type
from collections use append
use string as _s
use io as _io
use os as _os
use lexer as _lx
use parser as _bp
use semantic.analyzer as _ba
use semantic.types as _bt
use bytecode.compiler as _bc
use resolver as _bm
use native.lower as _nl
use native.inline as _ni
use native.codegen_x64 as _cg
use native.codegen_a64 as _a64
use native.ir as _ir
use native.dyn as _nd
use bytecode.format as _bf
use native.vm as _nv

const STDLIB_NATIVE := ["math", "string", "io", "os", "hw", "tasks", "asyncio", "posix", "wingui"]

# ---------------------------------------------------------------------------------------------- sources ALEX
# Fichiers du runtime natif : runtime/alex/<rel>, à côté de stdlib/ (runtime_dir).
func _runtime_file(rt, rel):
    path := rt + "/alex/" + rel
    try:
        return _io.read_file(path)
    catch e:
        raise("ModuleNotFoundError", "source du runtime introuvable : '" + path + "' (le dossier runtime/alex doit se trouver à côté de stdlib)")

const RUNTIME_DYN_PARTS := ["dyn", "dyn_ops", "dyn_nat", "dyn_office", "dyn_ui", "dyn_ui_raster", "dyn_ui_font", "dyn_x11"]

class NativeSources:
    func init(stdlib_root):
        self.rt = _bm.runtime_dir(stdlib_root)
        self.cache = {}

    func runtime(windows, a64):
        src := _runtime_file(self.rt, "native/source.al")
        if windows:
            return src + _runtime_file(self.rt, "native/windows.al")
        if a64:
            return src + _runtime_file(self.rt, "native/a64.al")
        return src

    # Runtime dynamique : sources runtime/alex/native/dyn*.al et trois fonctions générées.
    # vm : runtime de la VM écrite en ALEX (runtime/vm) — script et décalage d'argv lus à l'exécution, pas de
    # compilateur d'origine (ALEX_EXE est celui du pilote alex qui lance la VM).
    func runtime_dyn(script_path, vm=false, windows=false):
        out := []
        for part in RUNTIME_DYN_PARTS:
            append(out, _runtime_file(self.rt, "native/" + part + ".al"))
        # backend graphique Win32 (__wincallback) : exécutables Windows seulement
        append(out, _runtime_file(self.rt, "native/" + ("dyn_w32" if windows else "dyn_w32_none") + ".al"))
        # Compilateur qui produit l'exécutable : ALEX_EXE (fixé par alex pour ses programmes, hérité par un
        # compilateur natif), sinon l'exécutable courant.
        exe := _os.executable()
        if exe == null or exe == "":
            try:
                exe = _os.realpath("/proc/self/exe")
            catch e:
                exe = ""
        info := build_info()
        if vm:
            append(out, "\nfunc __dyn_alex_exe() -> str:\n    return \"\"\n")
            append(out, "\nfunc __dyn_script() -> str:\n    return __vm_script()\n")
        else:
            append(out, "\nfunc __dyn_alex_exe() -> str:\n    return \"" + _cquote(exe) + "\"\n")
            append(out, "\nfunc __dyn_script() -> str:\n    return \"" + _cquote(script_path) + "\"\n")
        append(out, "\nfunc __dyn_build_info() -> str:\n    return \"" + _cquote(info) + "\"\n")
        append(out, "\nfunc __dyn_argv_shift() -> int:\n    return " + ("__vm_argv_shift()" if vm else "0") + "\n")
        return _s.join("", out)

    func stdlib(name):
        if not (name in STDLIB_NATIVE):
            return null
        if not (name in self.cache):
            self.cache[name] = _runtime_file(self.rt, "stdlib/" + name + ".al")
        return self.cache[name]

# Identité du compilateur inscrite dans l'exécutable (os.alex_build()) : ALEX_BUILD_INFO désigne le fichier écrit
# par tools/version.sh gen (une ligne, 13 champs séparés par « | ») ; sans lui, celle du compilateur qui compile.
func build_info():
    f := _os.getenv("ALEX_BUILD_INFO")
    if f != null and f != "" and _os.isfile(f):
        line := _s.trim(_s.split(_io.read_file(f), "\n")[0])
        if len(_s.split(line, "|")) >= 11:
            return line
    b := _os.alex_build()
    extra := ""
    if "compiler" in b:
        extra = "|" + b["compiler"] + "|" + b["host"]
    return b["version"] + "|" + b["full"] + "|" + b["base"] + "|" + str(b["major"]) + "|" + str(b["minor"]) + "|" + str(b["patch"]) + "|" + b["channel"] + "|" + str(b["build"]) + "|" + b["date"] + "|" + b["source_id"] + "|" + b["commit"] + extra

func _cquote(v):
    out := []
    for c in _s.byte_unpack(v):
        if c == 0x22 or c == 0x5c:
            append(out, 0x5c)
        if c == 0x0a:
            continue
        append(out, c)
    return _s.byte_pack(out)

func stdlib_list():
    return _s.join(", ", STDLIB_NATIVE)

# Chemin des traces : relatif au dossier courant s'il s'y trouve (displayPath du C++, sans résoudre les liens).
func display_path(path):
    absn := _bm._absolute(path)
    cwd := _os.cwd()
    if absn == cwd:
        return "."
    if _bm.path_is_under(absn, cwd):
        return _s.substring(absn, len(cwd) + 1, len(absn))
    return absn

func _has_pragma_text(text, pragma):
    lines := _s.split(text, "\n")
    i := 0
    while i < 40 and i < len(lines):
        ln := _s.trim(lines[i])
        if ln == pragma:
            return true
        i += 1
    return false

func _has_pragma(path, pragma):
    lines := []
    try:
        lines = _s.split(_io.read_file(path), "\n")
    catch e:
        return false
    i := 0
    while i < 40 and i < len(lines):
        ln := lines[i]
        while len(ln) > 0 and (ln[len(ln) - 1] == '\r' or ln[len(ln) - 1] == ' '):
            ln = _s.substring(ln, 0, len(ln) - 1)
        if ln == pragma:
            return true
        i += 1
    return false

func _nerr(file, imp, msg):
    raise("NativeError", file + ":" + str(imp.line) + ":" + str(imp.column) + ": " + msg)

class Loaded:
    func init():
        self.program = null
        self.mod = null
        self.sigs = null

class ModuleLoader:
    func init(roots, sources, freestanding=false, windows=false):
        self.roots = roots
        self.sources = sources
        self.freestanding = freestanding
        self.windows = windows
        self.order = []
        self.index = {}
        self.stack = []

    func load(key, path, display, source, intrinsics=false):
        if key in self.index:
            return self.index[key]
        for k in self.stack:
            if k == key:
                raise("CyclicImportError", "cycle d'imports détecté : " + _s.join(" -> ", self.stack) + " -> " + key)
        append(self.stack, key)
        l := Loaded()
        l.program = _bp.parse_bytes(_s.byte_unpack(source), path)
        l.mod = _nl.SourceModule(l.program, display)
        l.mod.inline = intrinsics and _has_pragma_text(source, "# alex: inline")
        options := _bc.CompileOptions()
        for st in l.program.top_level:
            if st.kind != "ImportStmt":
                continue
            dep := self.resolve(st, display)
            if dep < 0:
                continue
            l.mod.imports[st.uid] = dep
            d := self.order[dep]
            q := "m" + str(dep)
            if st.is_from:
                for wanted in st.names:
                    options.imported_names[wanted] = q + "::" + wanted
                    if wanted in d.sigs.functions:
                        options.imported_functions[wanted] = d.sigs.functions[wanted]
                    elif wanted in d.sigs.structs:
                        options.imported_structs[wanted] = d.sigs.structs[wanted]
                    elif wanted in d.sigs.enums:
                        options.imported_enums[wanted] = d.sigs.enums[wanted]
                    elif wanted in d.sigs.interfaces:
                        options.imported_interfaces[wanted] = d.sigs.interfaces[wanted]
            else:
                exports := {}
                for x in _bm.collect_exportable_names(d.program):
                    exports[x] = true
                bound := st.alias if st.alias != null else st.module_path[len(st.module_path) - 1]
                options.namespace_imports[bound] = _bc.NamespaceImport(q, exports, d.sigs)
        if not intrinsics and not _s.starts_with(key, "<stdlib natif>"):
            _ba.analyze(l.program, path)
            _bt.TypeChecker(path, options).check_or_throw(l.program)
        l.sigs = _bm.compute_signatures(l.program, options)
        self.stack = self.stack[0:len(self.stack) - 1]
        self.index[key] = len(self.order)
        append(self.order, l)
        return self.index[key]

    func resolve(imp, frm):
        dotted := _s.join(".", imp.module_path)
        if dotted == "core" or dotted == "collections":
            return -1
        if dotted == "hw" and not self.freestanding:
            _nerr(frm, imp, "module '" + dotted + "' : accès matériel réservé à --freestanding")
        if (dotted == "io" or dotted == "os") and self.freestanding:
            _nerr(frm, imp, "module '" + dotted + "' : indisponible avec --freestanding (pas de système d'exploitation)")
        if dotted == "posix" and self.windows:
            _nerr(frm, imp, "module '" + dotted + "' : appels système POSIX : indisponible avec --windows (utiliser io et os)")
        if dotted == "wingui" and not self.windows:
            _nerr(frm, imp, "module '" + dotted + "' : interface graphique Windows : seulement avec --windows")
        file := _bm.resolve_module_file(imp.module_path, self.roots)
        in_stdlib := false
        if file != null and self.roots.stdlib_root != "":
            in_stdlib = _bm.path_is_under(_bm.canonicalize(file), _bm.canonicalize(self.roots.stdlib_root))
        native_src := self.sources.stdlib(dotted)
        if file != null and in_stdlib and native_src == null and _has_pragma(file, "# alex: intrinsics"):
            canon := _bm.canonicalize(file)
            return self.load(canon, canon, "<stdlib natif>/" + dotted + ".al", _io.read_file(canon), true)
        if file != null and in_stdlib and native_src == null and _has_pragma(file, "# alex: native"):
            canon := _bm.canonicalize(file)
            return self.load(canon, canon, display_path(canon), _io.read_file(canon))
        if file == null or in_stdlib:
            if native_src != null:
                name := "<stdlib natif>/" + dotted + ".al"
                return self.load(name, name, name, native_src)
            if in_stdlib:
                _nerr(frm, imp, "non supporté en natif : module '" + dotted + "' de la stdlib (disponibles en natif : core, collections, " + stdlib_list() + ")")
            raise("ModuleNotFoundError", "module '" + dotted + "' introuvable (recherché sous stdlib, projet puis packages) — importé depuis '" + frm + "'")
        canon := _bm.canonicalize(file)
        return self.load(canon, canon, display_path(canon), _io.read_file(canon))

# Programme -> IrProgram (avant l'intégration des petites fonctions), comme buildNative jusqu'à lower().
func lower_program(source_path, stdlib_root=null, freestanding=false, uefi=false, windows=false, a64=false):
    roots := _bm.default_roots(source_path, stdlib_root)
    sources := NativeSources(roots.stdlib_root)
    loader := ModuleLoader(roots, sources, freestanding or uefi, windows)
    canon := _bm.canonicalize(source_path)
    loader.load(canon, source_path, display_path(source_path), _io.read_file(source_path))
    mods := [l.mod for l in loader.order]
    win := windows and not freestanding and not uefi
    a64_linux := a64 and not win and not freestanding and not uefi
    runtime := _bp.parse_bytes(_s.byte_unpack(sources.runtime(win, a64_linux)), _nl.RUNTIME_FILE)
    return _nl.lower(mods, runtime, freestanding, uefi, windows, a64)

# Chaîne complète : source -> exécutable ELF x86-64 Linux (comme `alexc build --native --static`) ; windows :
# exécutable PE32+ Windows x64 (--windows), gui : application graphique sans console (--gui).
# uefi : application UEFI x86-64 (PE32+, sous-système 10), sous-ensemble statique seulement.
# freestanding : image Multiboot sans OS (--freestanding) ; a64 : AArch64 (Linux, ou Windows ARM64 avec windows).
# Icône des exécutables Windows produits ensuite (octets d'un fichier .ico, ou null) : `--icon`, et le logo d'ALEX
# pour la VM et la chaîne d'outils (alex_icon).
_windows_icon := [null]

func set_windows_icon(ico):
    _windows_icon[0] = ico

# Logo d'ALEX en icône Windows (runtime/alex/windows/alex.ico, à côté de stdlib/), ou null s'il manque.
func alex_icon(stdlib_root=null):
    roots := _bm.default_roots("alex.al", stdlib_root)
    path := _bm.runtime_dir(roots.stdlib_root) + "/alex/windows/alex.ico"
    if not _os.isfile(path):
        return null
    return _io.read_bytes(path)

func build(source_path, out_path, stdlib_root=null, emit_map=false, windows=false, gui=false, uefi=false, freestanding=false, a64=false, image_base=0):
    if windows and (uefi or freestanding):
        raise("RuntimeError", "--windows est exclusif de --freestanding et --uefi")
    p := lower_program(source_path, stdlib_root, freestanding, uefi, windows, a64)
    p.windows_gui = windows and gui
    p.windows_icon = _windows_icon[0] if windows else null
    _ir_full(p, "")
    if not _no_inline():
        _ni.inline_small_functions(p)
    _ir_full(p, ".inl")
    _generate(p, out_path, emit_map, image_base)
    return p

# ALEX_IR_FULL=fichier : dump complet de l'IR avant (fichier) et après (fichier.inl) l'intégration des petites
# fonctions ; ALEX_NO_INLINE : pas d'intégration (outils de mise au point du compilateur natif).
func _ir_full(p, suffix):
    f := _os.getenv("ALEX_IR_FULL")
    if f != null and f != "":
        _io.write_file(f + suffix, _ir.dump_full(p))

func _no_inline():
    v := _os.getenv("ALEX_NO_INLINE")
    return v != null and v != ""

func _generate(p, out_path, emit_map, image_base=0):
    if p.a64:
        _a64.generate_a64(p, out_path, emit_map)
    else:
        _cg.generate_x64(p, out_path, emit_map, image_base)

# Mode dynamique : programme fusionné (préludes, bibliothèque, comme `alexc run`) traduit en code machine
# (comme `alexc build --native --dynamic`). Ordre des analyses syntaxiques du compilateur de référence : préludes, graphe, runtime.
func build_dynamic(source_path, out_path, stdlib_root=null, emit_map=false, windows=false, gui=false, a64=false):
    roots := _bm.default_roots(source_path, stdlib_root)
    rtd := _bm.runtime_dir(roots.stdlib_root)
    core := _bm.compile_prelude(_bm.prelude_source(rtd + "/alex/prelude/core.al"), "<prelude:core>")
    colls := _bm.compile_prelude(_bm.prelude_source(rtd + "/alex/prelude/collections.al"), "<prelude:collections>")
    g := _bm.ModuleGraph(roots)
    module := g.build(source_path)
    merged := _bf.merge_modules([core, colls, module])[0]
    sources := NativeSources(roots.stdlib_root)
    runtime := _bp.parse_bytes(_s.byte_unpack(sources.runtime(windows, a64 and not windows) + sources.runtime_dyn(source_path, false, windows)), _nl.RUNTIME_FILE)
    empty := _bp.parse_bytes([], source_path)
    cwd := _os.cwd()
    p := _nl.lower_dynamic(source_path, runtime, empty, (h) => _nd.translate(h, merged, cwd), windows, a64)
    p.windows_gui = windows and gui
    p.windows_icon = _windows_icon[0] if windows else null
    _ir_full(p, "")
    if not _no_inline():
        _ni.inline_small_functions(p)
    _ir_full(p, ".inl")
    _generate(p, out_path, emit_map)
    return p

# `alexc build --native` : sous-ensemble statique si possible, sinon mode dynamique.
func build_auto(source_path, out_path, stdlib_root=null, windows=false, gui=false, uefi=false, freestanding=false, a64=false, emit_map=false):
    if uefi or freestanding:  # sans OS : pas de mode dynamique
        build(source_path, out_path, stdlib_root, emit_map, windows, gui, uefi, freestanding, a64)
        return "statique"
    # Hors du sous-ensemble statique (toute erreur, comme le C++) : mode dynamique. Refusé aussi en dynamique :
    # diagnostic du natif statique s'il lui est propre (NativeError), sinon celui du mode dynamique (de la VM).
    static_err := null
    try:
        build(source_path, out_path, stdlib_root, emit_map, windows, gui, false, false, a64)
        return "statique"
    catch e:
        static_err = e
    try:
        build_dynamic(source_path, out_path, stdlib_root, emit_map, windows, gui, a64)
    catch e2:
        if static_err.type == "NativeError":
            raise(static_err.type, static_err.message)
        raise(e2.type, e2.message)
    return "dynamique"

# Machine virtuelle écrite en ALEX (étape D) : runtime natif + runtime dynamique + runtime/vm/vm.al + table des
# modules natifs, compilés en un exécutable qui exécute les fichiers .albc (`alexvm prog.albc`, comme `alexc run`).
# Cible Alex OS : sortie AEX, aucune bibliothèque partagée (__alexos() vrai dans le runtime et la VM).
func set_alexos(on):
    _cg.set_alexos(on)
    _nl.set_alexos(on)

func build_vm(out_path, stdlib_root=null, windows=false, emit_map=false):
    roots := _bm.default_roots("vm.al", stdlib_root)
    rtd := _bm.runtime_dir(roots.stdlib_root)
    vm_path := rtd + "/vm/vm.al"
    sources := NativeSources(roots.stdlib_root)
    text := sources.runtime(windows, false) + sources.runtime_dyn("", true, windows) + _io.read_file(vm_path)
    text = text + _nv.module_table_source(text)
    runtime := _bp.parse_bytes(_s.byte_unpack(text), _nl.RUNTIME_FILE)
    # nom affiché (traces) indépendant de la machine de construction : la VM n'embarque aucun chemin absolu
    shown := "runtime/vm/vm.al"
    empty := _bp.parse_bytes([], shown)
    p := _nl.lower_dynamic(shown, runtime, empty, (h) => _nv.extend(h), windows)
    p.windows_icon = _windows_icon[0] if windows else null
    _ni.inline_small_functions(p)
    _cg.generate_x64(p, out_path, emit_map)
    return p
