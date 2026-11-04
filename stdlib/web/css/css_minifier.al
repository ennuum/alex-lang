# ALEX STANDARD LIBRARY — web.css.css_minifier
#
# Minification de CSS : commentaires et espaces retirés, couleurs raccourcies (#ffffff -> #fff, rgb() -> hex,
# nom plus court quand il existe), unités des zéros supprimées (0px -> 0, sauf durées et pourcentages), zéros
# de tête (0.5 -> .5), déclarations en double fusionnées, règles vides supprimées, règles voisines de même
# sélecteur fusionnées, @media identiques consécutives regroupées. Les propriétés personnalisées et le contenu
# des chaînes ne sont jamais modifiés.
#
#   use web.css.css_minifier as mini
#   mini.minify("a { color: #FFFFFF; margin: 0px 0.5em; }  /* x */ a { padding: 0 }")
#   # a{color:#fff;margin:0 .5em;padding:0}
#   r := mini.minify_report(texte)
#   r.ratio                      # taille finale / taille d'origine
#   mini.Options(false)          # options : merge (fusions), colors, zeros, keep_important_comments
#   mini.minify_value("color", "rgb(255, 0, 0)")   # red
#
# Erreurs : aucune (le CSS invalide est conservé ou ignoré comme par un navigateur).

from core use len, type, to_float
from collections use append, keys
use string as _s
use web.css.value as _value
use web.css.color as _color
use web.css.units as _units
use web.css.property as _prop
use web.css.declaration as _decl
use web.css.css_rule as _rule
use web.css.css_parser as _parser
use web.css.css_writer as _writer
use web.css.stylesheet as _sheet

class Options:
    func init(merge=true, colors=true, zeros=true, keep_important_comments=true):
        self.merge = merge
        self.colors = colors
        self.zeros = zeros
        self.keep_important_comments = keep_important_comments

class Report:
    func init(css, original_size, issues):
        self.css = css
        self.original_size = original_size
        self.size = len(css)
        self.saved = original_size - self.size
        self.ratio = (self.size / original_size) if original_size > 0 else 1.0
        self.issues = issues

    func __str__():
        return str(self.original_size) + " -> " + str(self.size) + " caractères (" + _units.format_number(self.ratio * 100.0) + " %)"

# ---------------------------------------------------------------- valeurs

const _NO_ZERO_UNIT := ["s", "ms", "deg", "grad", "rad", "turn", "hz", "khz", "dpi", "dpcm", "dppx", "x", "fr"]
const _PRESERVE := ["flex", "flex-basis", "-webkit-flex", "-ms-flex"]

func _short_number(x):
    t := _units.format_number(x)
    if _s.starts_with(t, "0.") and len(t) > 2:
        return t[1:len(t)]
    if _s.starts_with(t, "-0.") and len(t) > 3:
        return "-" + t[2:len(t)]
    return t

# Couleur la plus courte (hex court, hex, ou nom) ; null si le jeton n'est pas une couleur.
func shortest_color(text):
    c := _color.try_parse(text)
    if c == null:
        return null
    if c.a < 1.0:
        return null
    h := c.to_hex(true)
    nm := _color.name_of(c)
    if nm != null and len(nm) < len(h):
        return nm
    return h

func _min_items(items, prop, opts, in_function):
    out := []
    for it in items:
        if isinstance(it, _value.Token):
            k := it.kind
            if k == _value.NUMBER and opts.zeros:
                append(out, _value.Token(_value.DELIM, _short_number(it.value)))
                continue
            if k == _value.DIMENSION and opts.zeros:
                u := _s.lower(it.unit)
                if (it.value == 0 or it.value == 0.0) and not (u in _NO_ZERO_UNIT) and _units.kind_of(u) == "length" and not (prop in _PRESERVE) and not in_function:
                    append(out, _value.Token(_value.DELIM, "0"))
                else:
                    append(out, _value.Token(_value.DELIM, _short_number(it.value) + it.unit))
                continue
            if k == _value.PERCENTAGE and opts.zeros:
                append(out, _value.Token(_value.DELIM, _short_number(it.value) + "%"))
                continue
            if opts.colors and (k == _value.HASH or k == _value.IDENT) and _color_context(prop):
                sc := shortest_color(it.to_css())
                if sc != null and len(sc) <= len(it.to_css()):
                    append(out, _value.Token(_value.DELIM, sc))
                    continue
            append(out, it)
        elif isinstance(it, _value.Function):
            nm := it.lower_name()
            if opts.colors and nm in ["rgb", "rgba", "hsl", "hsla", "hwb"] and _color_context(prop):
                sc := shortest_color(it.to_css())
                if sc != null:
                    append(out, _value.Token(_value.DELIM, sc))
                    continue
            keep_units := nm in ["calc", "min", "max", "clamp"] or in_function
            append(out, _value.Function(it.name, _min_items(it.args, prop, opts, keep_units)))
        elif isinstance(it, _value.Block):
            append(out, _value.Block(it.open, _min_items(it.items, prop, opts, in_function)))
        else:
            append(out, it)
    return out

func _color_context(prop):
    k := _prop.kind(prop)
    if k == "color":
        return true
    return prop in ["background", "border", "border-top", "border-right", "border-bottom", "border-left", "outline", "box-shadow", "text-shadow", "border-color", "column-rule", "text-decoration", "fill", "stroke", "background-image", "caret-color", "accent-color", "scrollbar-color"]

# Valeur minifiée d'une propriété (les propriétés personnalisées sont rendues telles quelles).
func minify_value(prop, text, opts=null):
    o := opts if opts != null else Options()
    p := _prop.canonical(prop)
    if _prop.is_custom(p):
        return _s.trim(str(text))
    v := _value.parse(str(text))
    items := _min_items(v.items, p, o, false)
    return _value.serialize(items, true)

# ---------------------------------------------------------------- règles

func _dedupe(decls):
    # garde la dernière déclaration de chaque propriété (une !important l'emporte sur les suivantes normales),
    # sauf les replis volontaires (valeurs différentes avec préfixes ou fonctions récentes) : conservés.
    out := []
    i := 0
    while i < len(decls):
        d := decls[i]
        later := false
        j := i + 1
        while j < len(decls):
            e := decls[j]
            if e.property == d.property and (e.important or not d.important):
                if not _is_fallback_pair(d, e):
                    later = true
                    break
            j += 1
        if not d.important:
            j = 0
            while j < i:
                if decls[j].property == d.property and decls[j].important:
                    later = true
                    break
                j += 1
        if not later:
            append(out, d)
        i += 1
    return out

func _is_fallback_pair(a, b):
    va := _s.lower(a.value)
    vb := _s.lower(b.value)
    if va == vb:
        return false
    for marker in ["-webkit-", "-moz-", "-ms-", "var(", "env(", "clamp(", "min(", "max(", "color-mix(", "oklch(", "oklab(", "lab(", "lch(", "dvh", "svh", "lvh", "subgrid", "fit-content", "image-set("]:
        if _s.contains(vb, marker) and not _s.contains(va, marker):
            return true
    return false

func _min_decls(decls, opts):
    out := []
    for d in decls:
        nd := _decl.Declaration(d.property, minify_value(d.property, d.value, opts), d.important, d.line)
        nd.verbatim = true
        append(out, nd)
    if opts.merge:
        return _dedupe(out)
    return out

func _min_rules(rules, opts):
    out := []
    for r in rules:
        if r.kind == "style":
            nr := _rule.StyleRule(_rule._compact_selector(r.selector), _min_decls(r.declarations, opts), r.line)
            for c in _min_rules(r.children, opts):
                nr.add_child(c)
            if nr.is_empty():
                continue
            if opts.merge and len(out) > 0:
                last := out[len(out) - 1]
                if last.kind == "style" and last.selector == nr.selector and len(last.children) == 0 and len(nr.children) == 0:
                    merged := _rule.StyleRule(last.selector, _dedupe(last.declarations + nr.declarations), last.line)
                    out[len(out) - 1] = merged
                    continue
            append(out, nr)
        elif r.kind == "at":
            a := r.copy()
            a.rules = []
            a.declarations = _min_decls(r.declarations, opts)
            for c in _min_rules(r.rules, opts):
                a.add(c)
            if a.body != "statement" and a.is_empty() and r.name != "layer":
                continue
            if opts.merge and len(out) > 0 and a.name == "media":
                last := out[len(out) - 1]
                if last.kind == "at" and last.name == "media" and last.prelude == a.prelude:
                    for c in a.rules:
                        last.add(c)
                    continue
            append(out, a)
        elif r.kind == "keyframes":
            k := r.copy()
            for f in k.frames:
                f.declarations = _min_decls(f.declarations, opts)
            append(out, k)
        else:
            append(out, r)
    return out

func _important_comments(text):
    out := []
    i := 0
    n := len(text)
    while i < n - 2:
        if text[i] == '/' and text[i + 1] == '*' and text[i + 2] == '!':
            j := _s.find(text[i + 3:n], "*/")
            if j < 0:
                break
            append(out, text[i:i + 3 + j + 2])
            i = i + 3 + j + 2
        else:
            i += 1
    return out

# Texte minifié (str ou Stylesheet).
func minify(css, opts=null):
    return minify_report(css, opts).css

func minify_report(css, opts=null):
    o := opts if opts != null else Options()
    issues := []
    text := ""
    sheet := css
    if isinstance(css, _sheet.Stylesheet):
        text = css.to_css()
    else:
        text = str(css)
        sheet = _parser.parse(text, issues)
    rules := _min_rules(sheet.rules, o)
    out := _writer.Writer(false, "", true).write(rules)
    if o.keep_important_comments:
        keep := _important_comments(text)
        if len(keep) > 0:
            out = _s.join("", keep) + out
    return Report(out, len(text), issues)

# Minifie un attribut style.
func minify_inline(text, opts=null):
    o := opts if opts != null else Options()
    return _decl.to_css(_min_decls(_decl.parse_block(text), o), true)
