# ALEX — resolver
#
# Graphe de modules de la chaîne de compilation écrite en ALEX : portage de src/ModuleGraph.cpp,
# src/ModuleResolver.cpp, include/alex/module/Builtins.hpp et du prélude de `alexc build`. À partir d'un
# fichier d'entrée, résout récursivement les `use` / `from ... use` (stdlib -> projet -> dossier de l'entrée et
# ses parents -> paquets), qualifie chaque module dépendant ($mod + FNV-1a 64 du chemin canonique), injecte
# les builtins implicites dans les modules utilisateur, calcule les signatures des exports, vérifie les types
# (semantic.types), compile chaque module (bytecode.compiler), les fusionne et ajoute la fonction de
# liaison `$link` ; build_program y fusionne en tête les préludes core et collections, comme `alexc build`.
#
#   use resolver as bm
#   g := bm.ModuleGraph(bm.default_roots("prog.al"))
#   m := g.build("prog.al")                      # BcModule du programme et de ses dépendances
#   full := bm.build_program("prog.al")          # + préludes : identique à `alexc build prog.al`
#
# Pas de cache .albc / .meta : tout le graphe est recompilé depuis les sources (un compilateur 100 % ALEX).
# Les diagnostics sémantiques de l'Analyzer C++ (noms non définis...) ne sont pas reproduits ; ceux du
# vérificateur de types le sont.
#
# Erreurs : ModuleNotFoundError, ExportNotFoundError, CyclicImportError, TypeCheckError, CompileError,
#           LexError / ParseError (du front-end).

from core use len, type
from collections use append
use string as _s
use io as _io
use os as _os
use lexer as _lx
use parser as _bp
use ast as _a
use bytecode.compiler as _bc
use semantic.types as _bt
use semantic.analyzer as _ba
use bytecode.format as _bf

const NATIVE_MODULES := {"math": true, "string": true, "collections": true, "io": true, "os": true, "core": true,
    "http": true, "net": true, "crypto": true, "json": true, "time": true, "ui": true, "process": true, "ffi": true,
    "asyncio": true, "_native_core": true, "_native_math": true, "_native_string": true, "_native_collections": true,
    "_native_io": true, "_native_os": true, "_native_ui": true, "_native_process": true, "_native_ffi": true,
    "_native_memory": true, "_native_cli": true, "_native_gc": true, "_native_reflect": true,
    "_native_asyncio": true, "_native_net": true, "_native_tls": true, "_native_thread": true, "_native_fd": true,
    "_native_signal": true, "_native_sync": true, "_native_hwsim": true, "_native_office": true}

const CORE_NAMES := ["len", "type", "hash", "all", "any"]
const BUILTIN_NAMES := ["abs", "min", "max", "sum", "sorted", "reversed", "enumerate", "zip", "map", "filter",
    "range", "round", "divmod", "pow", "chr", "ord", "int", "float", "bool", "list", "tuple", "dict", "set",
    "__make_set"]
const METHOD_NAMES := {"append": true, "extend": true, "insert": true, "pop": true, "remove": true, "index": true,
    "count": true, "sort": true, "reverse": true, "clear": true, "copy": true, "keys": true, "values": true,
    "items": true, "get": true, "set": true, "update": true, "setdefault": true, "upper": true, "lower": true,
    "strip": true, "lstrip": true, "rstrip": true, "split": true, "join": true, "replace": true, "startswith": true,
    "endswith": true, "find": true, "capitalize": true, "title": true, "isdigit": true, "isalpha": true,
    "isspace": true, "zfill": true, "ljust": true, "rjust": true, "center": true}
# Windows : chemins à « \ » (std::filesystem), casse ignorée dans les comparaisons (alex/PathPrefix.hpp).
const _WIN := _os.platform() == "windows"

const TYPE_LIKE := {"int": true, "float": true, "bool": true, "list": true, "tuple": true, "dict": true}

func _merr(code, message):
    raise(code, message)

# ---------------------------------------------------------------------------------------------- chemins
func _join(a, b):
    if a == "":
        return b
    if _s.ends_with(a, "/"):
        return a + b
    return a + "/" + b

# Normalisation lexicale (fs::path::lexically_normal) d'un chemin '/'.
func lexically_normal(p):
    absolute := _s.starts_with(p, "/")
    out := []
    for seg in _s.split(p, "/"):
        if seg == "" or seg == ".":
            continue
        if seg == "..":
            if len(out) > 0 and out[len(out) - 1] != "..":
                out = out[0:len(out) - 1]
                continue
            if absolute:
                continue
        append(out, seg)
    s := _s.join("/", out)
    if absolute:
        return "/" + s
    return s if s != "" else "."

# Clé de comparaison d'un chemin (pathKey du C++) : « / » comme séparateur, minuscules sous Windows, sans « / » final.
func path_key(p):
    k := _s.replace(p, "\\", "/")
    if _WIN:
        k = _s.lower(k)
    while len(k) > 1 and _s.ends_with(k, "/"):
        k = _s.substring(k, 0, len(k) - 1)
    return k

func canonicalize(p):
    try:
        return _os.realpath(p)
    catch e:
        return p

func _absolute(p):
    if _WIN:
        return _os.absolute(p)
    if _s.starts_with(p, "/"):
        return lexically_normal(p)
    return lexically_normal(_join(_os.cwd(), p))

func path_is_under(path, d):
    if d == "":
        return false
    p := path_key(path)
    k := path_key(d)
    if len(p) < len(k) or _s.substring(p, 0, len(k)) != k:
        return false
    return len(p) == len(k) or p[len(k)] == '/' or _s.ends_with(k, "/")

func display_source_path(canonical):
    cwd := _os.cwd()
    if canonical == cwd:
        return "."
    if path_is_under(canonical, cwd):
        n := len(cwd) if _s.ends_with(cwd, "/") or _s.ends_with(cwd, "\\") else len(cwd) + 1
        rel := _s.substring(canonical, n, len(canonical))
        return _s.replace(rel, "\\", "/") if _WIN else rel
    return canonical

func _parent(p):
    i := len(p) - 1
    while i >= 0 and p[i] != '/' and not (_WIN and p[i] == '\\'):
        i -= 1
    if i < 0:
        return ""
    if i == 0:
        return "/"
    if _WIN and i == 2 and p[1] == ':':
        return _s.substring(p, 0, 3)
    return _s.substring(p, 0, i)

func locate_stdlib():
    env := null
    try:
        env = _os.getenv("ALEX_STDLIB")
    catch e:
        env = null
    cands := []
    if env != null and env != "":
        append(cands, env)
    append(cands, "./stdlib")
    # à côté de l'exécutable (distribution portable), puis installation de type Unix (bin/, lib/alex/stdlib)
    exe := ""
    try:
        exe = _os.realpath("/proc/self/exe")
    catch e2:
        exe = ""
    if exe != null and exe != "":
        dir := _parent(exe)
        append(cands, _join(dir, "stdlib"))
        append(cands, _join(_join(_join(dir, ".."), "lib/alex"), "stdlib"))
    for c in cands:
        if _os.isfile(_join(c, "core/core.al")):
            return lexically_normal(c)
    return "stdlib"

class SearchRoots:
    func init(stdlib_root="", project_root=".", entry_root=".", packages_root="./alex_packages"):
        self.stdlib_root = stdlib_root
        self.project_root = project_root
        self.entry_root = entry_root
        self.packages_root = packages_root

func default_roots(entry_path, stdlib_root=null):
    parent := _parent(entry_path)
    r := SearchRoots()
    r.project_root = "."
    r.entry_root = "." if parent == "" else parent
    r.packages_root = "./alex_packages"
    r.stdlib_root = stdlib_root if stdlib_root != null else locate_stdlib()
    return r

# Dossiers de sources du projet qui contient `dir` : clé `sources` de la section [package] du alex.toml le plus
# proche en remontant (`sources = ["src"]` ou `sources = "src"`), en chemins absolus ; [] sans manifeste ni clé.
# Ces dossiers sont des racines de modules pour tout fichier du projet (application, tests, outils).
func project_sources(dir):
    if dir == "":
        return []
    p := _absolute(dir)
    while true:
        m := _join(p, "alex.toml")
        if _os.isfile(m):
            out := []
            for s in _manifest_sources(m):
                append(out, _join(p, s))
            return out
        parent := _parent(p)
        if parent == p or parent == "":
            return []
        p = parent
    return []

func _manifest_sources(path):
    text := ""
    try:
        text = _io.read_file(path)
    catch e:
        return []
    section := ""
    for raw in _s.split(text, "\n"):
        line := _s.trim(raw)
        if _s.starts_with(line, "["):
            section = _s.trim(_s.replace(_s.replace(line, "[", ""), "]", ""))
            continue
        if section != "package" or not _s.starts_with(line, "sources"):
            continue
        eq := _s.find(line, "=")
        if eq < 0 or _s.trim(_s.substring(line, 0, eq)) != "sources":
            continue
        out := []
        for part in _s.split(_s.replace(_s.replace(_s.substring(line, eq + 1, len(line)), "[", ""), "]", ""), ","):
            t := _s.trim(part)
            if len(t) >= 2 and (t[0] == '"' or t[0] == '\''):
                append(out, _s.substring(t, 1, len(t) - 1))
        return out
    return []

func resolve_module_file(module_path, roots):
    if len(module_path) == 0:
        return null
    d := _s.join("/", module_path)
    rels := [d + ".al", d + "/" + module_path[len(module_path) - 1] + ".al", d + "/__init__.al"]
    cands := [roots.stdlib_root, roots.project_root]
    # dossiers de sources du projet (alex.toml : sources), vus depuis le fichier compilé puis le dossier courant
    for src in project_sources(roots.entry_root) + project_sources(roots.project_root):
        if not (src in cands):
            append(cands, src)
    pkgs := []
    if roots.entry_root != "":
        p := _absolute(roots.entry_root)
        while true:
            append(cands, p)
            append(pkgs, _join(p, "alex_packages"))
            parent := _parent(p)
            if parent == p or parent == "":
                break
            p = parent
    append(cands, roots.packages_root)
    for pc in pkgs:
        append(cands, pc)
    for root in cands:
        if root == "":
            continue
        for rel in rels:
            c := _join(root, rel)
            if _os.isfile(c):
                return canonicalize(c)
    return null

func qualifier_of(canonical_path):
    h := 1469598103934665603
    for b in _s.byte_unpack(canonical_path):
        h = h ^ b
        h = h * 1099511628211
    hexd := "0123456789abcdef"
    digits := ""
    i := 15
    while i >= 0:
        digits += str(hexd[(h >> (i * 4)) & 0xF])
        i -= 1
    return "$mod" + digits

# ---------------------------------------------------------------------------------------------- builtins implicites
func _import_node(is_from, path, names, alias):
    n := _a.Node("ImportStmt", 1, 1)
    n.is_from = is_from
    n.module_path = path
    n.names = names
    n.alias = alias
    return n

# Jetons des expressions d'une f-string (f"{max(notes)} ...") : sans eux, une fonction intégrée utilisée seulement
# entre accolades n'était pas importée (NameError « 'max' n'est pas défini »). Récursif pour les f-strings imbriquées ;
# une expression illisible est ignorée ici (le parseur signale l'erreur).
func _fstring_tokens(value):
    out := []
    content := _s.byte_unpack(value)
    m := len(content)
    i := 0
    while i < m:
        if content[i] != 123:
            i += 1
            continue
        j := i + 1
        depth := 1
        while j < m and depth > 0:
            if content[j] == 123:
                depth += 1
            elif content[j] == 125:
                depth -= 1
                if depth == 0:
                    break
            j += 1
        if j > i + 1:
            toks := []
            try:
                toks = _lx.tokenize(content[i + 1:j], "<f-string>")
            catch e:
                toks = []
            for t in toks:
                if t.type == "FSTRING":
                    for u in _fstring_tokens(t.value):
                        append(out, u)
                else:
                    append(out, t)
        i = j + 1
    return out

func _with_fstring_tokens(tokens):
    has := false
    for t in tokens:
        if t.type == "FSTRING":
            has = true
            break
    if not has:
        return tokens
    out := []
    for t in tokens:
        append(out, t)
        if t.type == "FSTRING":
            for u in _fstring_tokens(t.value):
                append(out, u)
    return out

func inject_builtins(program, tokens):
    tokens = _with_fstring_tokens(tokens)
    used := {}
    uses_method := false
    if program.uses_set_literal:
        used["__make_set"] = true
    nt := len(tokens)
    i := 0
    while i < nt:
        tk := tokens[i]
        if tk.type != "IDENTIFIER":
            i += 1
            continue
        w := tk.lexeme
        if w in TYPE_LIKE:
            nx := tokens[i + 1].type if i + 1 < nt else "EOF"
            pv := tokens[i - 1].type if i > 0 else "EOF"
            called := nx == "LPAREN"
            as_value := (pv == "LPAREN" or pv == "COMMA") and (nx == "COMMA" or nx == "RPAREN")
            if not called and not as_value:
                i += 1
                continue
        used[w] = true
        if i > 0 and tokens[i - 1].type == "DOT" and (w in METHOD_NAMES):
            uses_method = true
        i += 1
    taken := {}
    for s in program.top_level:
        k := s.kind
        if k == "FunctionDecl":
            if s.extends_type == "":
                taken[s.name] = true
        elif k == "VariableDecl" or k == "ConstDecl" or k == "StructDecl" or k == "ClassDecl" or k == "InterfaceDecl" or k == "EnumDecl":
            taken[s.name] = true
        elif k == "ImportStmt":
            if s.is_from:
                for n in s.names:
                    taken[n] = true
            elif len(s.module_path) > 0:
                taken[s.alias if s.alias != null else s.module_path[len(s.module_path) - 1]] = true
    head := []
    a := [n for n in CORE_NAMES if not (n in taken) and (n in used)]
    if len(a) > 0:
        append(head, _import_node(true, ["core"], a, null))
    b := [n for n in BUILTIN_NAMES if not (n in taken) and (n in used)]
    if len(b) > 0:
        append(head, _import_node(true, ["builtins"], b, null))
    elif uses_method:
        append(head, _import_node(false, ["builtins"], [], "__builtins"))
    if len(head) > 0:
        program.top_level = head + program.top_level

# ---------------------------------------------------------------------------------------------- signatures
func collect_exportable_names(program):
    names := []
    for s in program.top_level:
        k := s.kind
        if k == "FunctionDecl":
            if s.extends_type == "":
                append(names, s.name)
        elif k == "ConstDecl" or k == "VariableDecl" or k == "StructDecl" or k == "EnumDecl" or k == "ClassDecl" or k == "InterfaceDecl":
            append(names, s.name)
    return names

func _params_of(fn):
    out := []
    for p in fn.params:
        t := _bt.type_ref_string(p.type) if p.type != null and not p.is_rest else ""
        append(out, _bc.ParamSig(p.name, p.default_value != null or p.is_rest, t))
    return out

func compute_signatures(program, options=null):
    sigs := _bc.ModuleSignatures()
    types := _bc.TypeIndex(program.top_level)
    for s in program.top_level:
        k := s.kind
        if k == "FunctionDecl":
            if s.extends_type != "":
                continue
            sigs.functions[s.name] = _bc.FunctionSig(_params_of(s), _bt.type_ref_string(s.return_type) if s.return_type != null else "")
        elif k == "StructDecl":
            sig := _bc.StructSig()
            for st in s.body.statements:
                if st.kind == "FunctionDecl" and st.name == "init":
                    sig.has_ctor = true
                    sig.ctor_params = _params_of(st)
            sigs.structs[s.name] = sig
        elif k == "ClassDecl":
            td := types.find(s.name)
            sig := _bc.StructSig()
            sig.is_class = true
            external := null
            if td != null:
                fm := types.find_method(td, "init")
                if fm[0] != null:
                    sig.has_ctor = true
                    sig.ctor_params = _params_of(fm[0])
                external = fm[1]
                sig.has_field_init = types.has_local_field_init(td)
            if external != null and options != null and (external in options.imported_structs):
                ext := options.imported_structs[external]
                if not sig.has_ctor:
                    sig.has_ctor = ext.has_ctor
                    sig.ctor_params = ext.ctor_params
                sig.has_field_init = sig.has_field_init or ext.has_field_init
            sigs.structs[s.name] = sig
        elif k == "InterfaceDecl":
            sigs.interfaces[s.name] = _bc.InterfaceSig([st.name for st in s.body.statements if st.kind == "FunctionDecl"])
        elif k == "EnumDecl":
            sig := _bc.EnumSig()
            for m in s.members:
                sig.variants[m.name] = m.fields
            sigs.enums[s.name] = sig
    return sigs

# ---------------------------------------------------------------------------------------------- graphe
# ---- cache des modules : <module>.albc (bytecode) et <module>.al.meta (signatures, dépendances) --------------------
# Même format que l'alex de référence (metaVersion=6). Valide si : .albc au moins aussi récent que le source, même
# compilateur (version complète), même chemin de source inscrit (relatif au dossier courant), même qualificatif,
# dépendances présentes. Écriture au mieux : un cache non écrit désactive seulement l'accélération.
const META_VERSION := "6"

func _cache_bc_path(src):
    return src[0:len(src) - 3] + ".albc" if _s.ends_with(src, ".al") else src + ".albc"

func _param_text(p):
    return p.name + ":" + ("1" if p.has_default else "0") + ("" if p.type == "" else ":" + p.type)

func _parse_param(text):
    colon := _s.find(text, ":")
    if colon < 0:
        return _bc.ParamSig(text)
    name := _s.substring(text, 0, colon)
    rest := _s.substring(text, colon + 1, len(text))
    has_default := _s.starts_with(rest, "1")
    ty := ""
    if len(rest) > 2 and rest[1] == ':':
        ty = _s.substring(rest, 2, len(rest))
    return _bc.ParamSig(name, has_default, ty)

func _compiler_full():
    return _os.alex_build()["full"]

func try_load_cache(src, qualifier):
    bcp := _cache_bc_path(src)
    meta := src + ".meta"
    lines := []
    try:
        if not _os.isfile(bcp) or not _os.isfile(meta):
            return null
        if _os.mtime(bcp) < _os.mtime(src):
            return null
        lines = _s.split(_io.read_file(meta), "\n")
    catch e:
        return null
    stored_q := null
    exported := []
    deps := []
    sigs := _bc.ModuleSignatures()
    version_ok := false
    compiler_ok := false
    source_ok := false
    for raw in lines:
        line := _s.substring(raw, 0, len(raw) - 1) if _s.ends_with(raw, "\r") else raw
        if _s.starts_with(line, "metaVersion="):
            version_ok = _s.substring(line, 12, len(line)) == META_VERSION
        elif _s.starts_with(line, "compiler="):
            compiler_ok = _s.substring(line, 9, len(line)) == _compiler_full()
        elif _s.starts_with(line, "source="):
            source_ok = _s.substring(line, 7, len(line)) == display_source_path(src)
        elif _s.starts_with(line, "qualifier="):
            stored_q = _s.substring(line, 10, len(line))
        elif _s.starts_with(line, "export="):
            append(exported, _s.substring(line, 7, len(line)))
        elif _s.starts_with(line, "dep="):
            append(deps, _s.substring(line, 4, len(line)))
        elif _s.starts_with(line, "fn="):
            parts := _s.split(_s.substring(line, 3, len(line)), "\t")
            sig := _bc.FunctionSig()
            i := 1
            while i < len(parts):
                if _s.starts_with(parts[i], "->"):
                    sig.ret = _s.substring(parts[i], 2, len(parts[i]))
                else:
                    append(sig.params, _parse_param(parts[i]))
                i += 1
            sigs.functions[parts[0]] = sig
        elif _s.starts_with(line, "struct=") or _s.starts_with(line, "class="):
            is_class := _s.starts_with(line, "class=")
            parts := _s.split(_s.substring(line, 6 if is_class else 7, len(line)), "\t")
            sig := _bc.StructSig()
            sig.is_class = is_class
            sig.has_ctor = len(parts) > 1 and parts[1] == "1"
            first := 2
            if is_class:
                sig.has_field_init = len(parts) > 2 and parts[2] == "1"
                first = 3
            i := first
            while i < len(parts):
                append(sig.ctor_params, _parse_param(parts[i]))
                i += 1
            sigs.structs[parts[0]] = sig
        elif _s.starts_with(line, "iface="):
            parts := _s.split(_s.substring(line, 6, len(line)), "\t")
            sig := _bc.InterfaceSig()
            i := 1
            while i < len(parts):
                append(sig.methods, parts[i])
                i += 1
            sigs.interfaces[parts[0]] = sig
        elif _s.starts_with(line, "enum="):
            parts := _s.split(_s.substring(line, 5, len(line)), "\t")
            sig := _bc.EnumSig()
            i := 1
            while i < len(parts):
                colon := _s.find(parts[i], ":")
                variant := parts[i] if colon < 0 else _s.substring(parts[i], 0, colon)
                rest := "" if colon < 0 else _s.substring(parts[i], colon + 1, len(parts[i]))
                fields := [] if rest == "" else _s.split(rest, ",")
                sig.variants[variant] = fields
                i += 1
            sigs.enums[parts[0]] = sig
    if not version_ok or not compiler_ok or not source_ok or stored_q != qualifier:
        return null
    for d in deps:
        if not _os.isfile(d):
            return null
    r := ResolvedModule()
    try:
        r.bytecode = _bf.read_module(_io.read_bytes(bcp))
    catch e:
        return null    # cache corrompu : recompilation normale
    r.qualifier = qualifier
    r.exported_names = exported
    r.sigs = sigs
    r.direct_deps = deps
    return r

func write_cache(src, r):
    try:
        _io.write_bytes(_cache_bc_path(src), _bf.write_module(r.bytecode))
        out := ["metaVersion=" + META_VERSION, "compiler=" + _compiler_full(), "source=" + display_source_path(src), "qualifier=" + r.qualifier]
        for name in r.exported_names:
            append(out, "export=" + name)
        for name in r.sigs.functions:
            sig := r.sigs.functions[name]
            ln := "fn=" + name
            for p in sig.params:
                ln += "\t" + _param_text(p)
            if sig.ret != "":
                ln += "\t->" + sig.ret
            append(out, ln)
        for name in r.sigs.structs:
            sig := r.sigs.structs[name]
            ln := ""
            if sig.is_class:
                ln = "class=" + name + "\t" + ("1" if sig.has_ctor else "0") + "\t" + ("1" if sig.has_field_init else "0")
            else:
                ln = "struct=" + name + "\t" + ("1" if sig.has_ctor else "0")
            for p in sig.ctor_params:
                ln += "\t" + _param_text(p)
            append(out, ln)
        for name in r.sigs.interfaces:
            ln := "iface=" + name
            for m in r.sigs.interfaces[name].methods:
                ln += "\t" + m
            append(out, ln)
        for name in r.sigs.enums:
            ln := "enum=" + name
            vs := r.sigs.enums[name].variants
            for v in vs:
                ln += "\t" + v + ":" + _s.join(",", vs[v])
            append(out, ln)
        for d in r.direct_deps:
            append(out, "dep=" + d)
        _io.write_file(src + ".meta", _s.join("\n", out) + "\n")
    catch e:
        pass_ := 0

class ResolvedModule:
    func init():
        self.bytecode = null
        self.qualifier = ""
        self.exported_names = []
        self.sigs = null
        self.direct_deps = []

class ModuleGraph:
    func init(roots):
        self.roots = roots
        self.compiled = {}
        self.order = []
        self.on_stack = []
        self.stdlib_canonical = canonicalize(roots.stdlib_root) if roots.stdlib_root != "" else ""
        self.overrides = {}
        self.type_check = true
        # cache des modules (.albc + .meta à côté de chaque module importé) ; ALEX_NO_CACHE=1 le désactive
        nc := _os.getenv("ALEX_NO_CACHE")
        self.use_cache = nc == null or nc == "" or nc == "0"

    func set_source_override(path, source):
        self.overrides[canonicalize(path)] = source

    func is_under_stdlib(p):
        return path_is_under(p, self.stdlib_canonical)

    func resolve_and_compile(canonical_path, is_entry):
        if canonical_path in self.compiled:
            return self.compiled[canonical_path]
        for p in self.on_stack:
            if p == canonical_path:
                _merr("CyclicImportError", "cycle d'imports détecté : " + _s.join(" -> ", self.on_stack) + " -> " + canonical_path)
        append(self.on_stack, canonical_path)
        qualifier := "" if is_entry else qualifier_of(canonical_path)
        if not is_entry and self.use_cache:
            cached := try_load_cache(canonical_path, qualifier)
            if cached != null:
                # les dépendances de ce module (mémorisées dans son cache) sont résolues et liées avant lui
                for dep in cached.direct_deps:
                    self.resolve_and_compile(dep, false)
                self.on_stack = self.on_stack[0:len(self.on_stack) - 1]
                append(self.order, canonical_path)
                self.compiled[canonical_path] = cached
                return cached
        src := null
        if canonical_path in self.overrides:
            src = _s.byte_unpack(self.overrides[canonical_path])
        else:
            if not _os.isfile(canonical_path):
                _merr("ModuleNotFoundError", "impossible de lire '" + canonical_path + "'")
            src = _io.read_bytes(canonical_path)
        tokens := _lx.tokenize(src, canonical_path)
        program := _bp.parse_tokens([t for t in tokens], canonical_path)
        if not self.is_under_stdlib(canonical_path):
            inject_builtins(program, tokens)
        options := _bc.CompileOptions()
        options.self_qualifier = qualifier
        options.source_path = display_source_path(canonical_path)
        direct := []
        for st in program.top_level:
            if st.kind != "ImportStmt" or len(st.module_path) == 0:
                continue
            resolved := resolve_module_file(st.module_path, self.roots)
            if resolved == null:
                if len(st.module_path) == 1 and (st.module_path[0] in NATIVE_MODULES):
                    continue
                _merr("ModuleNotFoundError", "module '" + _s.join(".", st.module_path) + "' introuvable (recherché sous stdlib, projet puis packages) — importé depuis '" + canonical_path + "'")
            dep_path := canonicalize(resolved)
            append(direct, dep_path)
            dep := self.resolve_and_compile(dep_path, false)
            if st.is_from:
                for wanted in st.names:
                    found := false
                    for x in dep.exported_names:
                        if x == wanted:
                            found = true
                            break
                    if not found:
                        _merr("ExportNotFoundError", "'" + wanted + "' n'est pas exporté par le module '" + _s.join(".", st.module_path) + "' (résolu vers '" + dep_path + "')")
                    options.imported_names[wanted] = dep.qualifier + "::" + wanted
                    if wanted in dep.sigs.functions:
                        options.imported_functions[wanted] = dep.sigs.functions[wanted]
                    elif wanted in dep.sigs.structs:
                        options.imported_structs[wanted] = dep.sigs.structs[wanted]
                    elif wanted in dep.sigs.enums:
                        options.imported_enums[wanted] = dep.sigs.enums[wanted]
                    elif wanted in dep.sigs.interfaces:
                        options.imported_interfaces[wanted] = dep.sigs.interfaces[wanted]
            else:
                bound := st.alias if st.alias != null else st.module_path[len(st.module_path) - 1]
                exports := {}
                for x in dep.exported_names:
                    exports[x] = true
                options.namespace_imports[bound] = _bc.NamespaceImport(dep.qualifier, exports, dep.sigs)
        _ba.analyze(program, canonical_path)
        if self.type_check:
            tc := _bt.TypeChecker(canonical_path, options)
            tc.check_or_throw(program)
            options.sized_results = tc.sized_results
        r := ResolvedModule()
        r.bytecode = _bc.compile(program, options)
        r.qualifier = qualifier
        r.exported_names = collect_exportable_names(program)
        r.sigs = compute_signatures(program, options)
        r.direct_deps = direct
        if not is_entry and self.use_cache and not (canonical_path in self.overrides):
            write_cache(canonical_path, r)
        self.on_stack = self.on_stack[0:len(self.on_stack) - 1]
        append(self.order, canonical_path)
        self.compiled[canonical_path] = r
        return r

    func link_top_level_init(merged):
        if len(self.order) <= 1:
            return
        instrs := []
        i := 0
        while i + 1 < len(self.order):
            idx := len(merged.constants)
            append(merged.constants, _bf.const_str(self.compiled[self.order[i]].qualifier + "::$entry"))
            append(instrs, [_bf.LOAD_GLOBAL, idx, 0])
            append(instrs, [_bf.CALL, 0, 0])
            append(instrs, [_bf.POP, 0, 0])
            i += 1
        idx := len(merged.constants)
        append(merged.constants, _bf.const_str("$entry"))
        append(instrs, [_bf.LOAD_GLOBAL, idx, 0])
        append(instrs, [_bf.CALL, 0, 0])
        append(instrs, [_bf.RETURN, 0, 0])
        code := []
        _bf.encode_instructions(instrs, code)
        fid := 0
        for fn in merged.functions:
            if fn.function_id + 1 > fid:
                fid = fn.function_id + 1
        lf := _bf.FunctionEntry(fid, len(merged.constants))
        append(merged.constants, _bf.const_str("$link"))
        lf.code_offset = len(merged.code)
        lf.code_length = len(code)
        for b in code:
            append(merged.code, b)
        append(merged.functions, lf)
        merged.entry_function = fid

    func build(entry_path):
        self.resolve_and_compile(canonicalize(entry_path), true)
        merged := _bf.merge_modules([self.compiled[p].bytecode for p in self.order])[0]
        self.link_top_level_init(merged)
        return merged

# ---------------------------------------------------------------------------------------------- préludes
# Source d'un prélude : un fichier ALEX de runtime/alex/prelude/ (pas de C++ dans la chaîne d'outils).
func prelude_source(path):
    # Les préludes sont de vrais fichiers ALEX (runtime/alex/prelude/*.al) : aucune enveloppe C++ à retirer.
    try:
        return _io.read_file(path)
    catch e:
        _merr("ModuleNotFoundError", "prélude introuvable : '" + path + "' (le dossier runtime/alex doit se trouver à côté de stdlib)")

func compile_prelude(source, label):
    program := _bp.parse_bytes(_s.byte_unpack(source), label)
    _ba.analyze(program, label)
    options := _bc.CompileOptions()
    options.source_path = "<" + label + ">"
    return _bc.compile(program, options)

# Dossier des sources du runtime (préludes, runtime natif, stdlib native, VM : tout en ALEX) : à côté de la stdlib.
func runtime_dir(stdlib_root):
    return _join(_parent(canonicalize(stdlib_root)), "runtime")

# Programme complet, préludes compris : équivalent de `alexc build entrée -o sortie.albc`.
# entry_append : texte ajouté à la fin de la source du point d'entrée (épilogue des tests de `alexc test`).
func build_program(entry_path, stdlib_root=null, type_check=true, entry_append=""):
    roots := default_roots(entry_path, stdlib_root)
    g := ModuleGraph(roots)
    g.type_check = type_check
    if entry_append != "":
        g.set_source_override(entry_path, _io.read_file(entry_path) + entry_append)
    module := g.build(entry_path)
    rt := runtime_dir(roots.stdlib_root)
    core := compile_prelude(prelude_source(_join(rt, "alex/prelude/core.al")), "<prelude:core>")
    colls := compile_prelude(prelude_source(_join(rt, "alex/prelude/collections.al")), "<prelude:collections>")
    return _bf.merge_modules([core, colls, module])[0]
