# ALEX STANDARD LIBRARY — web.js.js_export
#
# Exportations ECMAScript : construction (« export {a, b as c} », réexportations « from », « export * as ns »,
# « export default », déclarations exportées) et ANALYSE des exportations d'un source avec leurs positions
# (utilisées par le regroupeur web.js.js_module).
#
#   use web.js.js_export as jx
#   jx.export_named(["a", ("b", "c")]).to_js()                 # export {a, b as c};
#   jx.export_from("./x.js", ["y"]).to_js()                    # export {y} from "./x.js";
#   jx.export_all("./x.js", "ns").to_js()                      # export * as ns from "./x.js";
#   jx.export_default(je.ident("App")).to_js()                 # export default App;
#   jx.export_declaration(js.const_decl("PI", 3.14)).to_js()   # export const PI = 3.14;
#   jx.parse_exports("export const a = 1, b = 2; export default function main() {}")
#   jx.exported_names("export {x as y}; export class C {}")    # ["y", "C"]
#
# Erreurs : JsSyntaxError (exportation mal formée), JsError (nom invalide).

from core use len, type
from collections use append
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_value as _jv
use web.js.js_expression as _e
use web.js.js_validator as _lex

class ExportDecl:
    # kind : "named" (specifiers [(local, exporté)], source facultative), "all" (source, alias facultatif),
    # "default" (valeur : Expr ou déclaration), "declaration" (déclaration : VarDecl, Function, Class).
    func init(kind, specifiers=null, source=null, alias=null, value=null):
        self.kind = kind
        self.specifiers = []
        for sp in (specifiers if specifiers != null else []):
            if type(sp) == "tuple" or type(sp) == "list":
                append(self.specifiers, (str(sp[0]), str(sp[1])))
            else:
                append(self.specifiers, (str(sp), str(sp)))
        self.source = source
        self.alias = alias
        self.value = value
        # analyse : positions dans le source, noms déclarés, début de la déclaration après « export [default] »
        self.start = null
        self.end = null
        self.body_start = null
        self.line = null
        self.names = []
        self.declaration_kind = null   # "const", "let", "var", "function", "class", "expression"

    # Noms exportés (vus de l'extérieur).
    func exported():
        if self.kind == "default":
            return ["default"]
        if self.kind == "all":
            return [self.alias] if self.alias != null else []
        if self.kind == "declaration":
            return self.names if len(self.names) > 0 else _decl_names(self.value)
        out := []
        for sp in self.specifiers:
            append(out, sp[1])
        return out

    func emit(s, level):
        semi := ";" if s.semicolons else ""
        q := s.quote
        if self.kind == "all":
            return "export *" + (" as " + self.alias if self.alias != null else "") + " from " + _t.quote(self.source, q) + semi
        if self.kind == "named":
            items := []
            for sp in self.specifiers:
                ex := sp[1] if _t.is_identifier_name(sp[1]) else _t.quote(sp[1], q)
                append(items, sp[0] if sp[0] == sp[1] else sp[0] + " as " + ex)
            out := "export {" + _s.join("," + s.sp(), items) + "}"
            if self.source != null:
                out = out + " from " + _t.quote(self.source, q)
            return out + semi
        if self.kind == "default":
            v := self.value
            if _is_decl(v):
                return "export default " + v.emit(s, level)
            return "export default " + _e._paren(_e.expr(v), s, level, _e.P_ASSIGN) + semi
        return "export " + self.value.emit(s, level)

    func to_js(style=null, level=0):
        return self.emit(_e.style_of(style), level)

    func __str__():
        return self.to_js()

func _is_decl(v):
    try:
        return v.is_declaration == true
    catch e:
        return false

func _decl_names(v):
    out := []
    if v == null:
        return out
    try:
        for d in v.declarators:
            if type(d[0]) == "str":
                append(out, d[0])
        return out
    catch e:
        pass
    try:
        if v.name != null:
            append(out, v.name)
    catch e2:
        pass
    return out

func export_named(specifiers):
    for sp in specifiers:
        local := sp[0] if (type(sp) == "tuple" or type(sp) == "list") else sp
        if not _t.is_identifier_name(str(local)):
            _err.js_error("js_export.export_named", "nom invalide « " + str(local) + " »")
    return ExportDecl("named", specifiers)

func export_from(source, specifiers):
    return ExportDecl("named", specifiers, source)

func export_all(source, alias=null):
    return ExportDecl("all", null, source, alias)

func export_default(value):
    return ExportDecl("default", null, null, null, value)

func export_declaration(declaration):
    return ExportDecl("declaration", null, null, null, declaration)

# ---------------------------------------------------------------- analyse

func _fail(msg, t):
    _err.syntax_error("js_export", msg, t.line if t != null else null, t.column if t != null else null)

func _str(t):
    return _jv.from_js(t.value)

# Fin (indice de jeton exclu) d'une instruction commençant à i : « ; » de profondeur 0, ou fin de ligne quand
# la suite ne peut pas continuer l'expression, ou fin du bloc d'une fonction / classe.
func _statement_end(toks, i):
    depth := 0
    j := i
    n := len(toks)
    while j < n:
        t := toks[j]
        if t.is_punct("(") or t.is_punct("[") or t.is_punct("{"):
            depth += 1
        elif t.is_punct(")") or t.is_punct("]") or t.is_punct("}"):
            depth -= 1
            if depth < 0:
                return j
        elif depth == 0 and t.is_punct(";"):
            return j + 1
        if depth == 0 and j + 1 < n and toks[j + 1].nl_before and not _continues(t, toks[j + 1]):
            return j + 1
        j += 1
    return n

func _continues(t, nxt):
    if t.kind == _lex.PUNCT and not (t.value in [")", "]", "}", "++", "--"]):
        return true
    if t.kind == _lex.KEYWORD and t.value in ["extends", "new", "typeof", "in", "instanceof", "return", "await", "async", "function", "class", "const", "let", "var"]:
        return true
    if nxt.kind == _lex.PUNCT and nxt.value in [".", "?.", ",", "=", "(", "[", "+", "-", "*", "/", "%", "?", ":", "&&", "||", "??", "=>", "==", "===", "!=", "!==", "<", ">", "<=", ">=", "{", "**", "|", "&", "^"]:
        return true
    if nxt.kind == _lex.KEYWORD and nxt.value in ["in", "instanceof", "extends"]:
        return true
    return false

# Fin d'une déclaration function / class : après le bloc de premier niveau.
func _block_end(toks, i):
    j := i
    n := len(toks)
    while j < n and not toks[j].is_punct("{"):
        j += 1
    depth := 0
    while j < n:
        t := toks[j]
        if t.is_punct("{"):
            depth += 1
        elif t.is_punct("}"):
            depth -= 1
            if depth == 0:
                return j + 1
        j += 1
    return n

# Noms déclarés par « const a = 1, {b, c: d} = o, [e] = l » (motifs simples pris en charge).
func _var_names(toks, i, end):
    out := []
    j := i
    depth := 0
    expect_name := true
    while j < end:
        t := toks[j]
        if t.is_punct("(") or t.is_punct("[") or t.is_punct("{"):
            if expect_name and depth == 0 and (t.is_punct("{") or t.is_punct("[")):
                # motif : collecter les identifiants liés
                k := j + 1
                d2 := 1
                while k < end and d2 > 0:
                    x := toks[k]
                    if x.is_punct("{") or x.is_punct("[") or x.is_punct("("):
                        d2 += 1
                    elif x.is_punct("}") or x.is_punct("]") or x.is_punct(")"):
                        d2 -= 1
                    elif x.kind == _lex.IDENTIFIER and d2 == 1:
                        nx := toks[k + 1] if k + 1 < end else null
                        if not (nx != null and nx.is_punct(":")):
                            append(out, x.value)
                    k += 1
                j = k
                expect_name = false
                continue
            depth += 1
        elif t.is_punct(")") or t.is_punct("]") or t.is_punct("}"):
            depth -= 1
        elif depth == 0 and t.is_punct(","):
            expect_name = true
        elif depth == 0 and expect_name and t.kind == _lex.IDENTIFIER:
            append(out, t.value)
            expect_name = false
        elif depth == 0 and t.is_punct("="):
            expect_name = false
        j += 1
    return out

func _parse_at(toks, i):
    c := toks[i]
    n := len(toks)
    t := toks[i + 1] if i + 1 < n else null
    if t == null:
        _fail("exportation incomplète", c)
    d := null
    end := i + 1
    if t.is_punct("*"):
        alias := null
        j := i + 2
        if j < n and toks[j].value == "as":
            alias = toks[j + 1].value if toks[j + 1].kind != _lex.STRING else _str(toks[j + 1])
            j += 2
        if j >= n or toks[j].value != "from" or j + 1 >= n or toks[j + 1].kind != _lex.STRING:
            _fail("« from \"module\" » attendu après « export * »", t)
        d = ExportDecl("all", null, _str(toks[j + 1]), alias)
        end = j + 2
        d.body_start = toks[i + 1].start
    elif t.is_punct("{"):
        specs := []
        j := i + 2
        while j < n and not toks[j].is_punct("}"):
            x := toks[j]
            if x.is_punct(","):
                j += 1
                continue
            local := x.value if x.kind != _lex.STRING else _str(x)
            exported := local
            if j + 2 < n and toks[j + 1].value == "as":
                y := toks[j + 2]
                exported = y.value if y.kind != _lex.STRING else _str(y)
                j += 3
            else:
                j += 1
            append(specs, (local, exported))
        if j >= n:
            _fail("« } » attendu", t)
        j += 1
        source := null
        if j < n and toks[j].value == "from" and j + 1 < n and toks[j + 1].kind == _lex.STRING:
            source = _str(toks[j + 1])
            j += 2
        d = ExportDecl("named", specs, source)
        end = j
        d.body_start = t.start
    elif t.is_keyword("default"):
        d = ExportDecl("default")
        b := toks[i + 2] if i + 2 < n else null
        if b == null:
            _fail("valeur attendue après « export default »", t)
        d.body_start = b.start
        is_fn := b.is_keyword("function") or (b.value == "async" and i + 3 < n and toks[i + 3].is_keyword("function"))
        if is_fn or b.is_keyword("class"):
            k := i + 3 if b.value == "async" else i + 2
            nm := toks[k + 1] if k + 1 < n else null
            if nm != null and nm.is_punct("*"):
                nm = toks[k + 2] if k + 2 < n else null
            if nm != null and nm.kind == _lex.IDENTIFIER:
                append(d.names, nm.value)
            d.declaration_kind = "class" if b.is_keyword("class") else "function"
            end = _block_end(toks, i + 2)
        else:
            d.declaration_kind = "expression"
            end = _statement_end(toks, i + 2)
    else:
        d = ExportDecl("declaration")
        d.body_start = t.start
        kw := t.value
        if kw == "async" and i + 2 < n and toks[i + 2].is_keyword("function"):
            kw = "function"
            t2 := toks[i + 3] if i + 3 < n else null
            if t2 != null and t2.is_punct("*"):
                t2 = toks[i + 4]
            append(d.names, t2.value)
            end = _block_end(toks, i + 2)
        elif kw == "function" or kw == "class":
            nm := toks[i + 2] if i + 2 < n else null
            if nm != null and nm.is_punct("*"):
                nm = toks[i + 3]
            if nm == null or nm.kind != _lex.IDENTIFIER:
                _fail("nom attendu après « export " + kw + " »", t)
            append(d.names, nm.value)
            end = _block_end(toks, i + 1)
        elif kw == "const" or kw == "let" or kw == "var":
            end = _statement_end(toks, i + 1)
            d.names = _var_names(toks, i + 2, end)
        else:
            _fail("déclaration attendue après « export »", t)
        d.declaration_kind = kw
    if end < n and toks[end].is_punct(";") and d.kind != "declaration":
        end += 1
    last := toks[end - 1]
    d.start = c.start
    d.end = last.end
    d.line = c.line
    return (d, end)

# Exportations d'un source, dans l'ordre (avec start / end / body_start / names).
func parse_exports(source):
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
        if depth == 0 and t.is_keyword("export") and not (i > 0 and (toks[i - 1].is_punct(".") or toks[i - 1].is_punct("?."))):
            r := _parse_at(toks, i)
            append(out, r[0])
            i = r[1]
            continue
        i += 1
    return out

func exported_names(source):
    out := []
    for d in parse_exports(source):
        for nm in d.exported():
            if not (nm in out):
                append(out, nm)
    return out

func has_default(source):
    return "default" in exported_names(source)
