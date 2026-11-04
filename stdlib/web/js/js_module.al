# ALEX STANDARD LIBRARY — web.js.js_module
#
# Modules ECMAScript : module construit (importations, corps, exportations) ou analysé depuis un source, graphe
# de dépendances, et REGROUPEMENT (bundle) de plusieurs modules en un seul script sans outil externe :
# importations et exportations réécrites vers un registre interne (liaisons d'exportation vivantes par
# accesseurs, cycles permis, import() dynamique, modules JSON, dépendances externes vers des globales),
# formats iife / cjs / esm, carte de sources ligne à ligne.
#
#   use web.js.js_module as jm
#   m := jm.Module("main.js")
#   m.import_from("./util.js", null, ["double"])
#   m.add(je.log([je.call("double", [21])]))
#   m.to_js()                                 # import {double} from "./util.js";\nconsole.log(double(21));\n
#   b := jm.Bundle({"main.js": "import {double} from './util.js'\nconsole.log(double(21))",
#                   "util.js": "export const double = (x) => x * 2"}, "main.js")
#   r := b.build()                            # r.code : script autonome ; r.map : carte de sources
#   b.order()                                 # ["util.js", "main.js"]  (dépendances d'abord)
#   jm.graph({"a.js": "import './b.js'", "b.js": ""})   # {"a.js": ["b.js"], "b.js": []}
#
# Erreurs : JsError (module introuvable, entrée absente, format inconnu), JsSyntaxError (source mal formé).

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_expression as _e
use web.js.js_statement as _st
use web.js.js_import as _imp
use web.js.js_export as _exp
use web.js.js_validator as _lex
use web.js.js_source_map as _sm

# ---------------------------------------------------------------- module construit

class Module:
    func init(path="module.js", source=null):
        self.path = path
        self.source = source           # texte d'origine (module analysé) ou null (module construit)
        self.imports = []
        self.body = []
        self.exports = []

    func import_from(source, default_name=null, named=null, namespace=null):
        if namespace != null:
            append(self.imports, _imp.import_namespace(source, namespace, default_name))
        else:
            append(self.imports, _imp.import_decl(source, default_name, named))
        return self

    func add(x):
        append(self.body, _st.stmt(x))
        return self

    # Ajoute une déclaration exportée (VarDecl, Function, Class).
    func export_declaration(decl):
        append(self.body, _exp.export_declaration(decl))
        return self

    func export_names(specifiers, source=null):
        if source != null:
            append(self.exports, _exp.export_from(source, specifiers))
        else:
            append(self.exports, _exp.export_named(specifiers))
        return self

    func export_default(value):
        append(self.exports, _exp.export_default(value))
        return self

    func dependencies():
        if self.source != null:
            return _imp.dependencies(self.source)
        out := []
        for i in self.imports:
            if not (i.source in out):
                append(out, i.source)
        for x in self.exports:
            if x.source != null and not (x.source in out):
                append(out, x.source)
        return out

    func parsed_imports():
        if self.source != null:
            return _imp.parse_imports(self.source)
        return self.imports

    func parsed_exports():
        if self.source != null:
            return _exp.parse_exports(self.source)
        return self.exports

    func exported_names():
        out := []
        for x in self.parsed_exports():
            for n in x.exported():
                if not (n in out):
                    append(out, n)
        return out

    func emit(s, level):
        if self.source != null:
            return self.source
        parts := []
        for i in self.imports:
            append(parts, i.emit(s, level))
        p := _st.Program(self.body)
        body := p.emit(s, level)
        if body != "":
            append(parts, _s.trim(body) if s.compact else body[0:len(body) - 1])
        for x in self.exports:
            append(parts, x.emit(s, level))
        if s.compact:
            return _s.join("", parts)
        return _s.join("\n", parts) + ("\n" if len(parts) > 0 else "")

    func to_js(style=null, level=0):
        return self.emit(_e.style_of(style), level)

func parse(source, path="module.js"):
    return Module(path, source)

# ---------------------------------------------------------------- résolution et graphe

const EXTENSIONS := ["", ".js", ".mjs", ".cjs", ".json", "/index.js", "/index.mjs"]

func _resolve(spec, importer, files, aliases):
    s := spec
    if aliases != null and spec in aliases:
        s = aliases[spec]
    if not _imp.is_relative(s):
        if s in files:
            return s
        return null
    base := _imp.resolve(s, importer)
    if _s.starts_with(base, "/") and not (base in files):
        base = base[1:len(base)]
    for ext in EXTENSIONS:
        if base + ext in files:
            return base + ext
    return null

# Graphe : module -> modules importés (résolus ; les spécificateurs externes sont omis).
func graph(files, aliases=null):
    out := {}
    for path in keys(files):
        deps := []
        if not _s.ends_with(path, ".json"):
            for spec in _imp.dependencies(files[path]):
                r := _resolve(spec, path, files, aliases)
                if r != null and not (r in deps):
                    append(deps, r)
        out[path] = deps
    return out

# ---------------------------------------------------------------- regroupement

class BundleResult:
    func init(code, source_map, modules, externals, warnings):
        self.code = code
        self.map = source_map
        self.modules = modules          # ordre d'inclusion
        self.externals = externals      # spécificateurs externes rencontrés
        self.warnings = warnings

const _RUNTIME := "const __modules = {};\nconst __cache = {};\nfunction __require(id) {\n  const hit = __cache[id];\n  if (hit) return hit.exports;\n  const factory = __modules[id];\n  if (!factory) throw new Error(\"module introuvable : \" + id);\n  const module = { exports: {} };\n  Object.defineProperty(module.exports, Symbol.toStringTag, { value: \"Module\" });\n  __cache[id] = module;\n  factory(module.exports, module);\n  return module.exports;\n}\nfunction __export(target, name, getter) {\n  Object.defineProperty(target, name, { enumerable: true, configurable: true, get: getter });\n}\nfunction __reexport(target, source) {\n  for (const k of Object.keys(source)) {\n    if (k !== \"default\" && !Object.prototype.hasOwnProperty.call(target, k)) __export(target, k, () => source[k]);\n  }\n}\nfunction __default(m) {\n  return m && Object.prototype.hasOwnProperty.call(m, \"default\") ? m.default : m;\n}\n"

class Bundle:
    # files : dict chemin -> source ; entry : chemin du module d'entrée ; externals : dict spécificateur ->
    # expression globale (« react » -> « window.React ») ; aliases : dict spécificateur -> chemin.
    func init(files, entry, externals=null, aliases=null, format="iife", global_name=null):
        if not (entry in files):
            _err.js_error("Bundle", "module d'entrée « " + str(entry) + " » absent des fichiers")
        if not (format in ["iife", "cjs", "esm"]):
            _err.js_error("Bundle", "format inconnu « " + str(format) + " » (iife, cjs, esm)")
        self.files = files
        self.entry = entry
        self.externals = externals if externals != null else {}
        self.aliases = aliases
        self.format = format
        self.global_name = global_name
        self.banner = null
        self.strict = true

    # Modules atteints depuis l'entrée, dépendances d'abord (parcours en profondeur, cycles tolérés).
    func order():
        g := graph(self.files, self.aliases)
        out := []
        visiting := []
        self._visit(self.entry, g, out, visiting)
        return out

    func _visit(path, g, out, visiting):
        if path in out or path in visiting:
            return
        append(visiting, path)
        for d in g[path]:
            self._visit(d, g, out, visiting)
        append(out, path)

    func _target(spec, importer, warnings, externals_seen):
        r := _resolve(spec, importer, self.files, self.aliases)
        if r != null:
            return ("__require(" + _t.quote(r) + ")", r)
        if spec in self.externals:
            if not (spec in externals_seen):
                append(externals_seen, spec)
            return ("(" + self.externals[spec] + ")", null)
        if _imp.is_relative(spec):
            _err.js_error("Bundle", "module « " + spec + " » introuvable (importé par " + importer + ")")
        if not (spec in externals_seen):
            append(externals_seen, spec)
            append(warnings, "dépendance externe non fournie : « " + spec + " » (importée par " + importer + ")")
        if self.format == "cjs":
            return ("require(" + _t.quote(spec) + ")", null)
        return ("globalThis[" + _t.quote(spec) + "]", null)

    # Corps réécrit d'un module (même nombre de lignes que l'original, en-tête d'accesseurs mis à part).
    func transform(path, warnings=null, externals_seen=null):
        w := warnings if warnings != null else []
        ext := externals_seen if externals_seen != null else []
        src := self.files[path]
        if _s.ends_with(path, ".json"):
            return ("", "exports.default = " + _s.trim(src) + ";\n")
        edits := []
        header := []
        counter := [0]
        live := {}          # nom local -> accès vivant (« __m1.counter »)
        spans := []
        for d in _imp.parse_imports(src):
            append(spans, (d.start, d.end))
            tgt := self._target(d.source, path, w, ext)
            if d.is_side_effect():
                append(edits, (d.start, d.end, tgt[0] + ";"))
                continue
            counter[0] = counter[0] + 1
            mv := "__m" + str(counter[0])
            parts := ["const " + mv + " = " + tgt[0] + ";"]
            if d.default_name != null:
                append(parts, "const " + d.default_name + " = __default(" + mv + ");")
            if d.namespace != null:
                append(parts, "const " + d.namespace + " = " + mv + ";")
            for nm in d.named:
                live[nm[1]] = mv + _t.property_access(nm[0]) if nm[0] != "default" else "__default(" + mv + ")"
            append(edits, (d.start, d.end, _s.join(" ", parts)))
        if len(live) > 0:
            for e in _live_edits(src, live, spans):
                append(edits, e)
        for x in _exp.parse_exports(src):
            if x.kind == "declaration":
                append(edits, (x.start, x.body_start, ""))
                for nm in x.names:
                    append(header, "__export(exports, " + _t.quote(nm) + ", () => " + nm + ");")
            elif x.kind == "named":
                if x.source != null:
                    tgt := self._target(x.source, path, w, ext)
                    counter[0] = counter[0] + 1
                    mv := "__r" + str(counter[0])
                    append(edits, (x.start, x.end, "const " + mv + " = " + tgt[0] + ";"))
                    for sp in x.specifiers:
                        acc := mv + "[" + _t.quote(sp[0]) + "]" if sp[0] != "default" else "__default(" + mv + ")"
                        append(header, "__export(exports, " + _t.quote(sp[1]) + ", () => " + acc + ");")
                else:
                    append(edits, (x.start, x.end, ""))
                    append(spans, (x.start, x.end))
                    for sp in x.specifiers:
                        acc := live[sp[0]] if sp[0] in live else sp[0]
                        append(header, "__export(exports, " + _t.quote(sp[1]) + ", () => " + acc + ");")
            elif x.kind == "all":
                tgt := self._target(x.source, path, w, ext)
                if x.alias != null:
                    counter[0] = counter[0] + 1
                    mv := "__r" + str(counter[0])
                    append(edits, (x.start, x.end, "const " + mv + " = " + tgt[0] + ";"))
                    append(header, "__export(exports, " + _t.quote(x.alias) + ", () => " + mv + ");")
                else:
                    append(edits, (x.start, x.end, "__reexport(exports, " + tgt[0] + ");"))
            elif x.kind == "default":
                if len(x.names) > 0:
                    append(edits, (x.start, x.body_start, ""))
                    append(header, "__export(exports, \"default\", () => " + x.names[0] + ");")
                else:
                    append(edits, (x.start, x.body_start, "exports.default = "))
        # import("littéral") dynamique
        toks := _lex.significant(_lex.tokenize(src))
        i := 0
        while i + 3 < len(toks):
            t := toks[i]
            if t.is_keyword("import") and toks[i + 1].is_punct("(") and toks[i + 2].kind == _lex.STRING and toks[i + 3].is_punct(")"):
                spec := _imp._string_value(toks[i + 2])
                r := _resolve(spec, path, self.files, self.aliases)
                if r != null:
                    append(edits, (t.start, toks[i + 3].end, "Promise.resolve().then(() => __require(" + _t.quote(r) + "))"))
            i += 1
        body := _apply(src, edits)
        return (_s.join("\n", header), body)

    func build(with_map=true):
        warnings := []
        ext := []
        mods := self.order()
        m := _sm.SourceMap()
        gen_line := [0]
        func_out := []
        if self.banner != null:
            _push(func_out, gen_line, "/*! " + _s.replace(self.banner, "*/", "* /") + " */")
        opener := "(function () {"
        if self.format == "iife" and self.global_name != null:
            opener = "var " + self.global_name + " = (function () {"
        if self.format == "cjs":
            opener = "module.exports = (function () {"
        if self.format == "esm":
            opener = "const __bundle = (function () {"
        _push(func_out, gen_line, opener)
        if self.strict:
            _push(func_out, gen_line, "\"use strict\";")
        for ln in _s.split(_s.trim(_RUNTIME), "\n"):
            _push(func_out, gen_line, ln)
        for path in mods:
            tr := self.transform(path, warnings, ext)
            si := m.add_source(path, self.files[path])
            _push(func_out, gen_line, "__modules[" + _t.quote(path) + "] = function (exports, module) {")
            if tr[0] != "":
                for ln in _s.split(tr[0], "\n"):
                    _push(func_out, gen_line, "  " + ln)
            lines := _s.split(tr[1], "\n")
            k := 0
            while k < len(lines):
                ln := lines[k]
                if k == len(lines) - 1 and ln == "":
                    break
                if _s.trim(ln) != "":
                    m.add(gen_line[0], 0, si, k, 0)
                _push(func_out, gen_line, ("  " + ln) if ln != "" else "")
                k += 1
            _push(func_out, gen_line, "};")
        _push(func_out, gen_line, "return __require(" + _t.quote(self.entry) + ");")
        _push(func_out, gen_line, "})();")
        if self.format == "esm":
            names := Module(self.entry, self.files[self.entry]).exported_names()
            for nm in names:
                if nm == "default":
                    _push(func_out, gen_line, "export default __bundle.default;")
                elif _t.is_identifier(nm):
                    _push(func_out, gen_line, "export const " + nm + " = __bundle." + nm + ";")
        code := _s.join("\n", func_out) + "\n"
        return BundleResult(code, m if with_map else null, mods, ext, warnings)

# Remplacements des identifiants importés par leur accès vivant (gabarits compris), hors des intervalles exclus.
func _live_edits(src, live, spans):
    toks := _lex.significant(_lex.tokenize(src))
    out := []
    n := len(toks)
    i := 0
    brackets := []
    while i < n:
        t := toks[i]
        if t.is_punct("{") or t.is_punct("(") or t.is_punct("["):
            append(brackets, t.value)
        elif (t.is_punct("}") or t.is_punct(")") or t.is_punct("]")) and len(brackets) > 0:
            brackets = brackets[0:len(brackets) - 1]
        excluded := false
        for sp in spans:
            if t.start >= sp[0] and t.start < sp[1]:
                excluded = true
        if excluded:
            i += 1
            continue
        if t.kind == _lex.TEMPLATE and t.parts != null:
            rebuilt := _rewrite_template(t, live)
            if rebuilt != t.value:
                append(out, (t.start, t.end, rebuilt))
        elif t.kind == _lex.IDENTIFIER and t.value in live:
            prev := toks[i - 1] if i > 0 else null
            nxt := toks[i + 1] if i + 1 < n else null
            after_dot := prev != null and (prev.is_punct(".") or prev.is_punct("?."))
            in_obj := prev != null and (prev.is_punct("{") or prev.is_punct(",")) and len(brackets) > 0 and brackets[len(brackets) - 1] == "{"
            is_key := in_obj and nxt != null and nxt.is_punct(":")
            if not after_dot and not is_key:
                if in_obj and nxt != null and (nxt.is_punct(",") or nxt.is_punct("}")):
                    append(out, (t.start, t.end, t.value + ": " + live[t.value]))
                else:
                    append(out, (t.start, t.end, live[t.value]))
        i += 1
    return out

func _rewrite_template(tok, live):
    pieces := ["`"]
    for p in tok.parts:
        if type(p) == "tuple":
            pieces = pieces + ["${", _apply(p[1], _live_edits(p[1], live, [])), "}"]
        else:
            append(pieces, p)
    append(pieces, "`")
    return _s.join("", pieces)

func _push(lines, counter, text):
    append(lines, text)
    counter[0] = counter[0] + 1

# Applique des remplacements (début, fin, texte) en gardant le nombre de lignes (sauts de ligne recopiés).
func _apply(src, edits):
    ordered := []
    for e in edits:
        append(ordered, e)
    i := 1
    while i < len(ordered):
        cur := ordered[i]
        j := i - 1
        while j >= 0 and ordered[j][0] > cur[0]:
            ordered[j + 1] = ordered[j]
            j -= 1
        ordered[j + 1] = cur
        i += 1
    out := []
    pos := 0
    for e in ordered:
        if e[0] < pos:
            continue
        append(out, src[pos:e[0]])
        replaced := src[e[0]:e[1]]
        nl := _s.count(replaced, "\n")
        append(out, e[2] + _s.repeat("\n", nl))
        pos = e[1]
    append(out, src[pos:len(src)])
    return _s.join("", out)

# Regroupe en une fois (raccourci).
func bundle(files, entry, format="iife", externals=null):
    return Bundle(files, entry, externals, null, format).build()
