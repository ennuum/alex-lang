# ALEX STANDARD LIBRARY — web.js.js_import
#
# Importations ECMAScript : construction (« import x, {a as b} from "m" », espace de noms, effet de bord,
# attributs « with { type: "json" } », import() dynamique) et ANALYSE des importations d'un source (positions
# comprises), dépendances (statiques, dynamiques littérales, require() CommonJS) et résolution de chemins
# relatifs.
#
#   use web.js.js_import as ji
#   ji.import_decl("./util.js", "util", [("format", "fmt"), "parse"]).to_js()
#   # import util, {format as fmt, parse} from "./util.js";
#   ji.import_namespace("./math.js", "M").to_js()             # import * as M from "./math.js";
#   ji.import_side_effect("./style.css").to_js()              # import "./style.css";
#   ji.import_decl("./data.json", "data", null, {"type": "json"}).to_js()   # … with {type: "json"};
#   ji.dynamic_import("./lazy.js").to_js()                    # import("./lazy.js")
#   ji.parse_imports("import a, * as ns from 'x'\nimport {b as c} from \"y\";")   # [ImportDecl, ImportDecl]
#   ji.dependencies("import a from 'a'; const b = require('b'); import('c')")   # ["a", "b", "c"]
#   ji.resolve("./b.js", "src/lib/a.js")                       # src/lib/b.js
#
# Erreurs : JsSyntaxError (importation mal formée), JsError (nom invalide).

from core use len, type
from collections use append, keys
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_value as _jv
use web.js.js_expression as _e
use web.js.js_validator as _lex
use json as _json

class ImportDecl:
    # named : liste de noms ou de (importé, local) ; attributes : dict (with { … }).
    func init(source, default_name=null, named=null, namespace=null, attributes=null):
        self.kind = "import"
        self.source = str(source)
        self.default_name = default_name
        self.namespace = namespace
        self.named = []
        for n in (named if named != null else []):
            if type(n) == "tuple" or type(n) == "list":
                append(self.named, (str(n[0]), str(n[1])))
            else:
                append(self.named, (str(n), str(n)))
        self.attributes = attributes
        self.start = null           # position dans le source analysé
        self.end = null
        self.line = null
        for local in self.locals():
            if not _t.is_identifier(local):
                _err.js_error("ImportDecl", "nom local invalide « " + local + " »")
        if namespace != null and len(self.named) > 0:
            _err.js_error("ImportDecl", "un espace de noms ne se combine pas avec des noms importés")

    func is_side_effect():
        return self.default_name == null and self.namespace == null and len(self.named) == 0

    # Noms liés localement.
    func locals():
        out := []
        if self.default_name != null:
            append(out, self.default_name)
        if self.namespace != null:
            append(out, self.namespace)
        for n in self.named:
            append(out, n[1])
        return out

    # dict local -> nom importé (« default » et « * » compris).
    func bindings():
        out := {}
        if self.default_name != null:
            out[self.default_name] = "default"
        if self.namespace != null:
            out[self.namespace] = "*"
        for n in self.named:
            out[n[1]] = n[0]
        return out

    func emit(s, level):
        q := s.quote
        src := _t.quote(self.source, q)
        attrs := ""
        if self.attributes != null and len(self.attributes) > 0:
            parts := []
            for k in keys(self.attributes):
                append(parts, _t.property_key(k) + ": " + _t.quote(str(self.attributes[k]), q))
            attrs = " with {" + _s.join(", ", parts) + "}"
        semi := ";" if s.semicolons else ""
        if self.is_side_effect():
            return "import " + src + attrs + semi
        clauses := []
        if self.default_name != null:
            append(clauses, self.default_name)
        if self.namespace != null:
            append(clauses, "* as " + self.namespace)
        if len(self.named) > 0:
            items := []
            for n in self.named:
                imported := n[0] if _t.is_identifier_name(n[0]) else _t.quote(n[0], q)
                append(items, imported if n[0] == n[1] else imported + " as " + n[1])
            append(clauses, "{" + _s.join("," + s.sp(), items) + "}")
        return "import " + _s.join("," + s.sp(), clauses) + " from " + src + attrs + semi

    func to_js(style=null, level=0):
        return self.emit(_e.style_of(style), level)

    func __str__():
        return self.to_js()

func import_decl(source, default_name=null, named=null, attributes=null):
    return ImportDecl(source, default_name, named, null, attributes)

func import_namespace(source, name, default_name=null):
    return ImportDecl(source, default_name, null, name)

func import_side_effect(source):
    return ImportDecl(source)

func dynamic_import(source, attributes=null):
    args := [_e.expr(source) if not (type(source) == "str") else _e.lit(source)]
    if attributes != null:
        append(args, _e.expr({"with": attributes}))
    return _e.Call(_e.RawExpr("import"), args)

# ---------------------------------------------------------------- analyse

func _string_value(tok):
    return _jv.from_js(tok.value)

func _fail(msg, t):
    _err.syntax_error("js_import", msg, t.line if t != null else null, t.column if t != null else null)

class _Cursor:
    func init(toks):
        self.toks = toks
        self.i = 0

    func peek(k=0):
        j := self.i + k
        if j < len(self.toks):
            return self.toks[j]
        return null

    func next():
        t := self.peek()
        self.i += 1
        return t

    func expect_punct(v):
        t := self.next()
        if t == null or not t.is_punct(v):
            _fail("« " + v + " » attendu", t)
        return t

func _name_token(t):
    return t != null and (t.kind == _lex.IDENTIFIER or t.kind == _lex.KEYWORD)

# Analyse une importation statique à partir du jeton « import » ; renvoie (ImportDecl, indice suivant).
func _parse_at(toks, idx, source_text):
    c := _Cursor(toks)
    c.i = idx
    first := c.next()
    t := c.peek()
    default_name := null
    namespace := null
    named := []
    if t != null and t.kind == _lex.STRING:
        c.next()
        d := ImportDecl(_string_value(t))
        return _finish(c, d, first, source_text)
    if _name_token(t) and not t.is_punct("{"):
        if t.value != "from" or (c.peek(1) != null and (c.peek(1).is_punct(",") or (c.peek(1).kind == _lex.IDENTIFIER and c.peek(1).value == "from"))):
            default_name = t.value
            c.next()
            if c.peek() != null and c.peek().is_punct(","):
                c.next()
    t = c.peek()
    if t != null and t.is_punct("*"):
        c.next()
        a := c.next()
        if a == null or a.value != "as":
            _fail("« as » attendu après « * »", a)
        nm := c.next()
        if not _name_token(nm):
            _fail("nom d'espace attendu", nm)
        namespace = nm.value
    elif t != null and t.is_punct("{"):
        c.next()
        while true:
            x := c.next()
            if x == null:
                _fail("« } » attendu", first)
            if x.is_punct("}"):
                break
            if x.is_punct(","):
                continue
            imported := x.value if x.kind != _lex.STRING else _string_value(x)
            local := imported
            if c.peek() != null and c.peek().value == "as" and c.peek().kind == _lex.IDENTIFIER:
                c.next()
                l := c.next()
                if not _name_token(l):
                    _fail("nom local attendu après « as »", l)
                local = l.value
            append(named, (imported, local))
    f := c.next()
    if f == null or f.value != "from":
        _fail("« from » attendu", f if f != null else first)
    src := c.next()
    if src == null or src.kind != _lex.STRING:
        _fail("module source (chaîne) attendu", src if src != null else f)
    d := ImportDecl(_string_value(src), default_name, named, namespace)
    return _finish(c, d, first, source_text)

func _finish(c, d, first, source_text):
    t := c.peek()
    if t != null and (t.value == "with" or t.value == "assert") and not t.nl_before:
        c.next()
        c.expect_punct("{")
        attrs := {}
        while true:
            k := c.next()
            if k == null:
                _fail("« } » attendu", first)
            if k.is_punct("}"):
                break
            if k.is_punct(","):
                continue
            c.expect_punct(":")
            v := c.next()
            key := k.value if k.kind != _lex.STRING else _string_value(k)
            attrs[key] = _string_value(v) if v.kind == _lex.STRING else v.value
        d.attributes = attrs
    last := c.toks[c.i - 1]
    if c.peek() != null and c.peek().is_punct(";"):
        last = c.next()
    d.start = first.start
    d.end = last.end
    d.line = first.line
    return (d, c.i)

func _is_static_import(toks, i):
    t := toks[i]
    if not t.is_keyword("import"):
        return false
    nxt := toks[i + 1] if i + 1 < len(toks) else null
    if nxt == null:
        return false
    if nxt.is_punct("(") or nxt.is_punct("."):
        return false
    prev := toks[i - 1] if i > 0 else null
    if prev != null and (prev.is_punct(".") or prev.is_punct("?.")):
        return false
    return true

# Importations statiques d'un source, dans l'ordre (avec start / end / line).
func parse_imports(source):
    toks := _lex.significant(_lex.tokenize(source))
    out := []
    i := 0
    depth := 0
    while i < len(toks):
        t := toks[i]
        if t.is_punct("{") or t.is_punct("(") or t.is_punct("["):
            depth += 1
        elif t.is_punct("}") or t.is_punct(")") or t.is_punct("]"):
            depth -= 1
        if depth == 0 and _is_static_import(toks, i):
            r := _parse_at(toks, i, source)
            append(out, r[0])
            i = r[1]
            continue
        i += 1
    return out

# Modules cités : importations et réexportations statiques, import("littéral"), require("littéral").
func dependencies(source, include_dynamic=true, include_require=true):
    toks := _lex.significant(_lex.tokenize(source))
    out := []
    n := len(toks)
    i := 0
    while i < n:
        t := toks[i]
        spec := null
        if t.is_keyword("import") and i + 2 < n and toks[i + 1].is_punct("(") and toks[i + 2].kind == _lex.STRING:
            if include_dynamic:
                spec = _string_value(toks[i + 2])
        elif t.kind == _lex.IDENTIFIER and t.value == "require" and include_require and i + 2 < n and toks[i + 1].is_punct("(") and toks[i + 2].kind == _lex.STRING and not (i > 0 and toks[i - 1].is_punct(".")):
            spec = _string_value(toks[i + 2])
        elif t.kind == _lex.IDENTIFIER and t.value == "from" and i + 1 < n and toks[i + 1].kind == _lex.STRING:
            spec = _string_value(toks[i + 1])
        elif t.is_keyword("import") and i + 1 < n and toks[i + 1].kind == _lex.STRING:
            spec = _string_value(toks[i + 1])
        if spec != null and not (spec in out):
            append(out, spec)
        i += 1
    return out

func is_relative(specifier):
    return _s.starts_with(specifier, "./") or _s.starts_with(specifier, "../") or _s.starts_with(specifier, "/")

func is_bare(specifier):
    return not is_relative(specifier) and not _s.contains(specifier, "://")

# Chemin d'un spécificateur relatif depuis le fichier importateur (séparateurs « / », « . » et « .. » résolus).
func resolve(specifier, importer):
    if not is_relative(specifier):
        return specifier
    base := []
    if not _s.starts_with(specifier, "/"):
        parts := _s.split(_s.replace(importer, "\\", "/"), "/")
        i := 0
        while i < len(parts) - 1:
            append(base, parts[i])
            i += 1
    for p in _s.split(specifier, "/"):
        if p == "" or p == ".":
            continue
        if p == "..":
            if len(base) > 0 and base[len(base) - 1] != "..":
                base = base[0:len(base) - 1]
            else:
                append(base, "..")
        else:
            append(base, p)
    out := _s.join("/", base)
    if _s.starts_with(specifier, "/"):
        out = "/" + out
    return out

# Carte d'importation (import map) : résout un spécificateur nu (« lodash », « @scope/x/y »).
func resolve_with_map(specifier, imports):
    if specifier in imports:
        return imports[specifier]
    best := null
    for k in keys(imports):
        if _s.ends_with(k, "/") and _s.starts_with(specifier, k):
            if best == null or len(k) > len(best):
                best = k
    if best != null:
        return imports[best] + specifier[len(best):len(specifier)]
    return specifier

# Texte <script type="importmap">.
func import_map_json(imports, scopes=null):
    d := {"imports": imports}
    if scopes != null:
        d["scopes"] = scopes
    return _json.stringify(d, 2, false)
