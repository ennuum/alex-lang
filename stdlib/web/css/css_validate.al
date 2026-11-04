# ALEX STANDARD LIBRARY — web.css.css_validate
#
# Validation de CSS : erreurs de syntaxe (web.css.css_parser), propriétés inconnues, valeurs non conformes à
# la nature de la propriété, sélecteurs invalides, requêtes @media / @supports / @container mal formées,
# @keyframes utilisées mais non définies, var() sans définition ni repli, déclarations en double, règles
# vides, !important. Chaque problème est une Issue (niveau error / warning / info, code, message, ligne).
#
#   use web.css.css_validate as cv
#   r := cv.validate("a { colr: red; width: 12; animation: pop 1s }")
#   r.is_valid()                 # false
#   for i in r.issues: print(i)  # warning [unknown-property] … ; error [invalid-value] … ; warning [undefined-keyframes] …
#   r.errors(), r.warnings()
#   cv.validate_declaration("margin", "0 auto")     # [] (aucun problème)
#   cv.Options(false)            # options : strict_properties (inconnues = erreurs), allow_vendor, report_important
#
# Erreurs : CssValidationError (assert_valid sur un CSS invalide).

from core use len, type
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.property as _prop
use web.css.declaration as _decl
use web.css.selector_parser as _sp
use web.css.media_query as _mq
use web.css.supports_query as _sq
use web.css.container_query as _cq
use web.css.variables as _vars
use web.css.css_parser as _parser
use web.css.stylesheet as _sheet

class Options:
    func init(strict_properties=false, allow_vendor=true, report_important=false, report_empty=true):
        self.strict_properties = strict_properties
        self.allow_vendor = allow_vendor
        self.report_important = report_important
        self.report_empty = report_empty

class Report:
    func init(issues):
        self.issues = issues

    func errors():
        out := []
        for i in self.issues:
            if i.level == _err.ERROR:
                append(out, i)
        return out

    func warnings():
        out := []
        for i in self.issues:
            if i.level == _err.WARNING:
                append(out, i)
        return out

    func is_valid():
        return len(self.errors()) == 0

    func codes():
        out := []
        for i in self.issues:
            append(out, i.code)
        return out

    func summary():
        return str(len(self.errors())) + " erreur(s), " + str(len(self.warnings())) + " avertissement(s)"

    func __str__():
        lines := [self.summary()]
        for i in self.issues:
            append(lines, str(i))
        return _s.join("\n", lines)

func _issue(out, level, code, message, where, line):
    append(out, _err.Issue(level, code, message, where, line))

# Problèmes d'une déclaration isolée.
func validate_declaration(name, value, opts=null, where=null, line=null):
    o := opts if opts != null else Options()
    out := []
    n := _prop.canonical(name)
    if not _prop.is_custom(n):
        pre := _prop.prefix_of(n)
        if pre != null and o.allow_vendor:
            if not _prop.is_known(n):
                _issue(out, _err.INFO, "vendor-property", "propriété préfixée « " + n + " » (inconnue sans préfixe)", where, line)
        elif not _prop.is_known(n):
            lvl := _err.ERROR if o.strict_properties else _err.WARNING
            _issue(out, lvl, "unknown-property", "propriété inconnue « " + n + " »" + _suggest(n), where, line)
            return out
    p := _decl.value_problem(n, value)
    if p != null:
        _issue(out, _err.ERROR, "invalid-value", "« " + n + ": " + str(value) + " » : " + p, where, line)
    return out

# Propriété connue la plus proche (distance d'édition ≤ 2), pour « vouliez-vous dire ».
func _suggest(name):
    best := null
    bd := 3
    for k in _prop.names():
        if len(k) < len(name) - 2 or len(k) > len(name) + 2:
            continue
        d := _distance(name, k, bd)
        if d < bd:
            bd = d
            best = k
    if best == null:
        return ""
    return " (vouliez-vous dire « " + best + " » ?)"

func _distance(a, b, limit):
    prev := []
    j := 0
    while j <= len(b):
        append(prev, j)
        j += 1
    i := 1
    while i <= len(a):
        cur := [i]
        row_min := i
        j = 1
        while j <= len(b):
            cost := 0 if a[i - 1] == b[j - 1] else 1
            v := prev[j] + 1
            if cur[j - 1] + 1 < v:
                v = cur[j - 1] + 1
            if prev[j - 1] + cost < v:
                v = prev[j - 1] + cost
            append(cur, v)
            if v < row_min:
                row_min = v
            j += 1
        if row_min >= limit:
            return limit
        prev = cur
        i += 1
    return prev[len(b)]

class _State:
    func init(opts):
        self.opts = opts
        self.issues = []
        self.keyframes = []
        self.used_keyframes = []
        self.custom_defined = []
        self.var_uses = []

func _check_decls(st, decls, where):
    seen := {}
    for d in decls:
        for x in validate_declaration(d.property, d.value, st.opts, where, d.line):
            append(st.issues, x)
        if d.is_custom():
            if not (d.property in st.custom_defined):
                append(st.custom_defined, d.property)
        if _vars.uses_variables(d.value):
            append(st.var_uses, (d.value, where, d.line))
        if st.opts.report_important and d.important:
            _issue(st.issues, _err.INFO, "important", "!important sur « " + d.property + " »", where, d.line)
        if d.property == "animation-name" or d.property == "animation":
            for part in _s.split(d.value, ","):
                for w in _s.split(_s.trim(part), " "):
                    if w != "" and _looks_like_name(w) and not (w in st.used_keyframes):
                        append(st.used_keyframes, (w, where, d.line))
        if d.property in seen:
            prev := seen[d.property]
            if prev.value == d.value:
                _issue(st.issues, _err.WARNING, "duplicate-declaration", "« " + d.property + " » déclarée deux fois avec la même valeur", where, d.line)
            else:
                _issue(st.issues, _err.INFO, "overridden-declaration", "« " + d.property + " » redéfinie (repli ou oubli ?)", where, d.line)
        seen[d.property] = d

const _ANIMATION_WORDS := ["none", "infinite", "linear", "ease", "ease-in", "ease-out", "ease-in-out", "step-start", "step-end", "forwards", "backwards", "both", "normal", "reverse", "alternate", "alternate-reverse", "running", "paused", "initial", "inherit", "unset", "revert"]

func _looks_like_name(w):
    lw := _s.lower(w)
    if lw in _ANIMATION_WORDS or _s.contains(lw, "(") or _s.contains(lw, ")"):
        return false
    c := lw[0]
    if (c >= '0' and c <= '9') or c == '.' or c == '-' and len(lw) > 1 and lw[1] >= '0' and lw[1] <= '9':
        return false
    return true

func _walk(st, rules, parent_sel):
    for r in rules:
        if r.kind == "style":
            where := r.selector
            ok := true
            try:
                _sp.parse(r.selector, parent_sel != null)
            catch e:
                ok = false
                _issue(st.issues, _err.ERROR, "invalid-selector", "sélecteur invalide « " + r.selector + " »", where, r.line)
            if st.opts.report_empty and len(r.declarations) == 0 and len(r.children) == 0:
                _issue(st.issues, _err.INFO, "empty-rule", "règle vide « " + where + " »", where, r.line)
            _check_decls(st, r.declarations, where)
            _walk(st, r.children, where)
        elif r.kind == "keyframes":
            append(st.keyframes, r.name)
            for f in r.frames:
                _check_decls(st, f.declarations, "@keyframes " + r.name)
        elif r.kind == "at":
            where := "@" + r.name + ((" " + r.prelude) if r.prelude != "" else "")
            if r.name == "media" and not _mq.is_valid(r.prelude):
                _issue(st.issues, _err.ERROR, "invalid-media-query", "requête média invalide « " + r.prelude + " »", where, r.line)
            elif r.name == "supports" and not _sq.is_valid(r.prelude):
                _issue(st.issues, _err.ERROR, "invalid-supports", "condition @supports invalide « " + r.prelude + " »", where, r.line)
            elif r.name == "container" and not _cq.is_valid(r.prelude):
                _issue(st.issues, _err.ERROR, "invalid-container-query", "requête @container invalide « " + r.prelude + " »", where, r.line)
            if r.name == "font-face":
                names := []
                for d in r.declarations:
                    append(names, d.property)
                if not ("font-family" in names) or not ("src" in names):
                    _issue(st.issues, _err.ERROR, "incomplete-font-face", "@font-face sans font-family ou src", where, r.line)
            elif r.body == "rules" or r.body == "statement":
                if len(r.declarations) > 0 and parent_sel == null:
                    _issue(st.issues, _err.WARNING, "orphan-declarations", "déclarations hors d'une règle dans « " + where + " »", where, r.line)
                _check_decls(st, r.declarations, where)
            _walk(st, r.rules, parent_sel)

# Valide un texte CSS ou une Stylesheet -> Report.
func validate(css, opts=null):
    o := opts if opts != null else Options()
    st := _State(o)
    sheet := css
    if not isinstance(css, _sheet.Stylesheet):
        sheet = _parser.parse(str(css), st.issues)
    _walk(st, sheet.rules, null)
    for u in st.used_keyframes:
        if not (u[0] in st.keyframes):
            _issue(st.issues, _err.WARNING, "undefined-keyframes", "@keyframes « " + u[0] + " » non définie", u[1], u[2])
    for u in st.var_uses:
        for ref in _var_refs(u[0]):
            if not ref[1] and not (ref[0] in st.custom_defined):
                _issue(st.issues, _err.WARNING, "undefined-variable", "var(" + ref[0] + ") sans définition ni repli", u[1], u[2])
    return Report(st.issues)

# (nom, a_un_repli) pour chaque var() du texte.
func _var_refs(text):
    out := []
    t := str(text)
    n := len(t)
    i := 0
    while i < n:
        if t[i:i + 4] == "var(":
            j := i + 4
            while j < n and t[j] == ' ':
                j += 1
            k := j
            while k < n and t[k] != ',' and t[k] != ')' and t[k] != ' ':
                k += 1
            m := k
            while m < n and t[m] == ' ':
                m += 1
            append(out, (t[j:k], m < n and t[m] == ','))
            i = k
            continue
        i += 1
    return out

func is_valid(css, opts=null):
    return validate(css, opts).is_valid()

func assert_valid(css, opts=null):
    r := validate(css, opts)
    if not r.is_valid():
        _err.validation_error("css_validate", str(r.errors()[0]))
    return r

# Style en ligne (attribut style) -> Report.
func validate_inline(text, opts=null):
    st := _State(opts if opts != null else Options())
    _check_decls(st, _parser.parse_declarations(text, st.issues), "style")
    return Report(st.issues)
