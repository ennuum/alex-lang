# ALEX STANDARD LIBRARY — web.css.property
#
# Propriétés CSS : table des propriétés connues (héritage, valeur initiale, nature de la valeur), noms
# canoniques (font_size -> font-size), préfixes vendeurs, propriétés personnalisées (--x), et développement des
# raccourcis courants (margin, padding, inset, border, border-radius, gap, flex, overflow, place-*...).
#
#   use web.css.property as p
#   p.is_known("grid-template-columns")       # true
#   p.is_inherited("color")                   # true
#   p.initial_value("display")                # inline
#   p.kind("background-color")                # color
#   p.canonical("fontSize")                   # font-size
#   p.expand("margin", "1px 2px")             # [("margin-top", "1px"), ("margin-right", "2px"), ...]
#   p.expand("flex", "1")                     # flex-grow 1, flex-shrink 1, flex-basis 0%
#   p.unprefixed("-webkit-transition")        # transition
#
# Erreurs : aucune (les fonctions répondent null / false pour l'inconnu).

from core use len, type
from collections use append
use string as _s
use web.css.value as _value

# nom|hérité (1/0)|valeur initiale|nature  (nature : color, length, length-percentage, number, integer, time,
# keyword, url, string, any)
const _TABLE := ["accent-color|1|auto|color", "align-content|0|normal|keyword", "align-items|0|normal|keyword", "align-self|0|auto|keyword", "all|0|initial|keyword", "animation|0|none|any", "animation-delay|0|0s|time", "animation-direction|0|normal|keyword", "animation-duration|0|0s|time", "animation-fill-mode|0|none|keyword", "animation-iteration-count|0|1|any", "animation-name|0|none|any", "animation-play-state|0|running|keyword", "animation-timing-function|0|ease|any", "appearance|0|none|keyword", "aspect-ratio|0|auto|any", "backdrop-filter|0|none|any", "backface-visibility|0|visible|keyword", "background|0|none|any", "background-attachment|0|scroll|keyword", "background-blend-mode|0|normal|keyword", "background-clip|0|border-box|keyword", "background-color|0|transparent|color", "background-image|0|none|any", "background-origin|0|padding-box|keyword", "background-position|0|0% 0%|any", "background-repeat|0|repeat|keyword", "background-size|0|auto|any", "block-size|0|auto|length-percentage", "border|0|none|any", "border-block|0|none|any", "border-bottom|0|none|any", "border-bottom-color|0|currentcolor|color", "border-bottom-left-radius|0|0|length-percentage", "border-bottom-right-radius|0|0|length-percentage", "border-bottom-style|0|none|keyword", "border-bottom-width|0|medium|length", "border-collapse|1|separate|keyword", "border-color|0|currentcolor|any", "border-image|0|none|any", "border-inline|0|none|any", "border-left|0|none|any", "border-left-color|0|currentcolor|color", "border-left-style|0|none|keyword", "border-left-width|0|medium|length", "border-radius|0|0|any", "border-right|0|none|any", "border-right-color|0|currentcolor|color", "border-right-style|0|none|keyword", "border-right-width|0|medium|length", "border-spacing|1|0|any", "border-style|0|none|any", "border-top|0|none|any", "border-top-color|0|currentcolor|color", "border-top-left-radius|0|0|length-percentage", "border-top-right-radius|0|0|length-percentage", "border-top-style|0|none|keyword", "border-top-width|0|medium|length", "border-width|0|medium|any", "bottom|0|auto|length-percentage", "box-decoration-break|0|slice|keyword", "box-shadow|0|none|any", "box-sizing|0|content-box|keyword", "break-after|0|auto|keyword", "break-before|0|auto|keyword", "break-inside|0|auto|keyword", "caption-side|1|top|keyword", "caret-color|1|auto|color", "clear|0|none|keyword", "clip-path|0|none|any", "color|1|canvastext|color", "color-scheme|1|normal|any", "column-count|0|auto|integer", "column-gap|0|normal|length-percentage", "column-rule|0|none|any", "column-span|0|none|keyword", "column-width|0|auto|length", "columns|0|auto|any", "contain|0|none|any", "container|0|none|any", "container-name|0|none|any", "container-type|0|normal|keyword", "content|0|normal|any", "content-visibility|0|visible|keyword", "counter-increment|0|none|any", "counter-reset|0|none|any", "cursor|1|auto|any", "direction|1|ltr|keyword", "display|0|inline|keyword", "empty-cells|1|show|keyword", "fill|1|black|any", "filter|0|none|any", "flex|0|0 1 auto|any", "flex-basis|0|auto|length-percentage", "flex-direction|0|row|keyword", "flex-flow|0|row nowrap|any", "flex-grow|0|0|number", "flex-shrink|0|1|number", "flex-wrap|0|nowrap|keyword", "float|0|none|keyword", "font|1|normal|any", "font-display|0|auto|keyword", "font-family|1|serif|any", "font-feature-settings|1|normal|any", "font-kerning|1|auto|keyword", "font-size|1|medium|length-percentage", "font-size-adjust|1|none|any", "font-stretch|1|normal|any", "font-style|1|normal|keyword", "font-variant|1|normal|any", "font-variant-numeric|1|normal|any", "font-variation-settings|1|normal|any", "font-weight|1|normal|any", "gap|0|normal|any", "grid|0|none|any", "grid-area|0|auto|any", "grid-auto-columns|0|auto|any", "grid-auto-flow|0|row|any", "grid-auto-rows|0|auto|any", "grid-column|0|auto|any", "grid-column-end|0|auto|any", "grid-column-start|0|auto|any", "grid-row|0|auto|any", "grid-row-end|0|auto|any", "grid-row-start|0|auto|any", "grid-template|0|none|any", "grid-template-areas|0|none|any", "grid-template-columns|0|none|any", "grid-template-rows|0|none|any", "height|0|auto|length-percentage", "hyphens|1|manual|keyword", "image-rendering|1|auto|keyword", "inline-size|0|auto|length-percentage", "inset|0|auto|any", "inset-block|0|auto|any", "inset-inline|0|auto|any", "isolation|0|auto|keyword", "justify-content|0|normal|keyword", "justify-items|0|legacy|keyword", "justify-self|0|auto|keyword", "left|0|auto|length-percentage", "letter-spacing|1|normal|length", "line-break|1|auto|keyword", "line-height|1|normal|any", "list-style|1|disc outside none|any", "list-style-image|1|none|any", "list-style-position|1|outside|keyword", "list-style-type|1|disc|any", "margin|0|0|any", "margin-block|0|0|any", "margin-block-end|0|0|length-percentage", "margin-block-start|0|0|length-percentage", "margin-bottom|0|0|length-percentage", "margin-inline|0|0|any", "margin-inline-end|0|0|length-percentage", "margin-inline-start|0|0|length-percentage", "margin-left|0|0|length-percentage", "margin-right|0|0|length-percentage", "margin-top|0|0|length-percentage", "mask|0|none|any", "max-block-size|0|none|length-percentage", "max-height|0|none|length-percentage", "max-inline-size|0|none|length-percentage", "max-width|0|none|length-percentage", "min-block-size|0|auto|length-percentage", "min-height|0|auto|length-percentage", "min-inline-size|0|auto|length-percentage", "min-width|0|auto|length-percentage", "mix-blend-mode|0|normal|keyword", "object-fit|0|fill|keyword", "object-position|0|50% 50%|any", "opacity|0|1|number", "order|0|0|integer", "orphans|1|2|integer", "outline|0|none|any", "outline-color|0|currentcolor|color", "outline-offset|0|0|length", "outline-style|0|none|keyword", "outline-width|0|medium|length", "overflow|0|visible|any", "overflow-anchor|0|auto|keyword", "overflow-wrap|1|normal|keyword", "overflow-x|0|visible|keyword", "overflow-y|0|visible|keyword", "overscroll-behavior|0|auto|any", "padding|0|0|any", "padding-block|0|0|any", "padding-bottom|0|0|length-percentage", "padding-inline|0|0|any", "padding-left|0|0|length-percentage", "padding-right|0|0|length-percentage", "padding-top|0|0|length-percentage", "page-break-after|0|auto|keyword", "page-break-before|0|auto|keyword", "page-break-inside|0|auto|keyword", "perspective|0|none|any", "perspective-origin|0|50% 50%|any", "place-content|0|normal|any", "place-items|0|normal|any", "place-self|0|auto|any", "pointer-events|1|auto|keyword", "position|0|static|keyword", "quotes|1|auto|any", "resize|0|none|keyword", "right|0|auto|length-percentage", "rotate|0|none|any", "row-gap|0|normal|length-percentage", "scale|0|none|any", "scroll-behavior|0|auto|keyword", "scroll-margin|0|0|any", "scroll-padding|0|auto|any", "scroll-snap-align|0|none|any", "scroll-snap-type|0|none|any", "scrollbar-color|1|auto|any", "scrollbar-gutter|0|auto|any", "scrollbar-width|0|auto|keyword", "shape-outside|0|none|any", "stroke|1|none|any", "stroke-width|1|1|any", "tab-size|1|8|any", "table-layout|0|auto|keyword", "text-align|1|start|keyword", "text-align-last|1|auto|keyword", "text-decoration|0|none|any", "text-decoration-color|0|currentcolor|color", "text-decoration-line|0|none|any", "text-decoration-style|0|solid|keyword", "text-decoration-thickness|0|auto|any", "text-indent|1|0|length-percentage", "text-justify|1|auto|keyword", "text-overflow|0|clip|any", "text-rendering|1|auto|keyword", "text-shadow|1|none|any", "text-transform|1|none|keyword", "text-underline-offset|1|auto|any", "text-wrap|1|wrap|keyword", "top|0|auto|length-percentage", "touch-action|0|auto|any", "transform|0|none|any", "transform-box|0|view-box|keyword", "transform-origin|0|50% 50% 0|any", "transform-style|0|flat|keyword", "transition|0|all 0s ease 0s|any", "transition-behavior|0|normal|keyword", "transition-delay|0|0s|time", "transition-duration|0|0s|time", "transition-property|0|all|any", "transition-timing-function|0|ease|any", "translate|0|none|any", "unicode-bidi|0|normal|keyword", "user-select|0|auto|keyword", "vertical-align|0|baseline|any", "view-transition-name|0|none|any", "visibility|1|visible|keyword", "white-space|1|normal|keyword", "widows|1|2|integer", "width|0|auto|length-percentage", "will-change|0|auto|any", "word-break|1|normal|keyword", "word-spacing|1|normal|length", "writing-mode|1|horizontal-tb|keyword", "z-index|0|auto|integer", "zoom|0|1|any"]

# Mots-clés valables pour toute propriété.
const CSS_WIDE := ["inherit", "initial", "unset", "revert", "revert-layer"]
const PREFIXES := ["-webkit-", "-moz-", "-ms-", "-o-"]

_info := [null]

func _db():
    if _info[0] == null:
        d := {}
        for line in _TABLE:
            parts := _s.split(line, "|")
            d[parts[0]] = {"inherited": parts[1] == "1", "initial": parts[2], "kind": parts[3]}
        _info[0] = d
    return _info[0]

# Nom canonique : minuscules, « _ » -> « - », camelCase -> kebab-case (les propriétés --x restent telles quelles).
func canonical(name):
    n := str(name)
    if _s.starts_with(n, "--"):
        return n
    out := []
    i := 0
    for c in n:
        if c >= 'A' and c <= 'Z':
            if i > 0:
                append(out, "-")
            append(out, _s.lower(str(c)))
        elif c == '_':
            append(out, "-")
        else:
            append(out, str(c))
        i += 1
    r := _s.join("", out)
    if _s.starts_with(r, "webkit-") or _s.starts_with(r, "moz-") or _s.starts_with(r, "ms-"):
        r = "-" + r
    return r

func is_custom(name):
    return _s.starts_with(str(name), "--") and len(str(name)) > 2

func prefix_of(name):
    for p in PREFIXES:
        if _s.starts_with(name, p):
            return p
    return null

# Nom sans préfixe vendeur.
func unprefixed(name):
    p := prefix_of(name)
    if p == null:
        return name
    return name[len(p):len(name)]

func is_known(name):
    n := canonical(name)
    return is_custom(n) or unprefixed(n) in _db()

func info(name):
    n := unprefixed(canonical(name))
    d := _db()
    if n in d:
        return d[n]
    return null

func is_inherited(name):
    if is_custom(name):
        return true
    i := info(name)
    return i != null and i["inherited"]

func initial_value(name):
    i := info(name)
    if i == null:
        return null
    return i["initial"]

# Nature de la valeur attendue (color, length, length-percentage, number, integer, time, keyword, any), ou null.
func kind(name):
    i := info(name)
    if i == null:
        return null
    return i["kind"]

func names():
    out := []
    for k in _db():
        append(out, k)
    return out

func is_css_wide(value):
    return _s.lower(_s.trim(str(value))) in CSS_WIDE

# ---------------------------------------------------------------- raccourcis

const _SIDES := ["top", "right", "bottom", "left"]
const _CORNERS := ["top-left", "top-right", "bottom-right", "bottom-left"]
const BORDER_STYLES := ["none", "hidden", "dotted", "dashed", "solid", "double", "groove", "ridge", "inset", "outset"]

# Parties d'une valeur séparées par des espaces au premier niveau (les fonctions restent entières).
func split_spaces(text):
    out := []
    for c in _value.parse(text).components:
        append(out, c.to_css())
    return out

# 1 à 4 valeurs -> haut, droite, bas, gauche.
func box(values):
    n := len(values)
    if n == 1:
        return [values[0], values[0], values[0], values[0]]
    if n == 2:
        return [values[0], values[1], values[0], values[1]]
    if n == 3:
        return [values[0], values[1], values[2], values[1]]
    if n == 4:
        return values
    return null

func is_shorthand(name):
    return canonical(name) in ["margin", "padding", "inset", "border-width", "border-style", "border-color", "border-radius", "gap", "overflow", "place-items", "place-content", "place-self", "flex", "flex-flow", "border", "border-top", "border-right", "border-bottom", "border-left", "outline", "margin-inline", "margin-block", "padding-inline", "padding-block", "inset-inline", "inset-block"]

# Développe un raccourci en propriétés longues : liste de (nom, valeur) ; [(nom, valeur)] inchangé sinon (ou si
# la valeur n'est pas décomposable : var(), mots-clés globaux).
func expand(name, value):
    n := canonical(name)
    v := _s.trim(str(value))
    if is_css_wide(v) or _s.contains(v, "var("):
        if not is_shorthand(n):
            return [(n, v)]
        return _same_for_all(n, v)
    parts := split_spaces(v)
    if n == "margin" or n == "padding":
        b := box(parts)
        if b == null:
            return [(n, v)]
        return [(n + "-top", b[0]), (n + "-right", b[1]), (n + "-bottom", b[2]), (n + "-left", b[3])]
    if n == "inset":
        b := box(parts)
        if b == null:
            return [(n, v)]
        return [("top", b[0]), ("right", b[1]), ("bottom", b[2]), ("left", b[3])]
    if n == "border-width" or n == "border-style" or n == "border-color":
        b := box(parts)
        if b == null:
            return [(n, v)]
        suffix := n[6:len(n)]
        return [("border-top" + suffix, b[0]), ("border-right" + suffix, b[1]), ("border-bottom" + suffix, b[2]), ("border-left" + suffix, b[3])]
    if n == "border-radius":
        if _s.contains(v, "/"):
            return [(n, v)]
        b := box(parts)
        if b == null:
            return [(n, v)]
        out := []
        i := 0
        for c in _CORNERS:
            append(out, ("border-" + c + "-radius", b[i]))
            i += 1
        return out
    if n == "margin-inline" or n == "margin-block" or n == "padding-inline" or n == "padding-block" or n == "inset-inline" or n == "inset-block":
        if len(parts) > 2:
            return [(n, v)]
        base := n if not _s.starts_with(n, "inset") else n
        a := parts[0]
        b2 := parts[1] if len(parts) == 2 else parts[0]
        return [(base + "-start", a), (base + "-end", b2)]
    if n == "gap":
        if len(parts) > 2:
            return [(n, v)]
        return [("row-gap", parts[0]), ("column-gap", parts[1] if len(parts) == 2 else parts[0])]
    if n == "overflow":
        if len(parts) > 2:
            return [(n, v)]
        return [("overflow-x", parts[0]), ("overflow-y", parts[1] if len(parts) == 2 else parts[0])]
    if n == "place-items" or n == "place-content" or n == "place-self":
        if len(parts) > 2:
            return [(n, v)]
        what := n[6:len(n)]
        return [("align-" + what, parts[0]), ("justify-" + what, parts[1] if len(parts) == 2 else parts[0])]
    if n == "flex":
        return _expand_flex(parts, v)
    if n == "flex-flow":
        dirs := ["row", "row-reverse", "column", "column-reverse"]
        d := "row"
        w := "nowrap"
        for p in parts:
            if _s.lower(p) in dirs:
                d = p
            else:
                w = p
        return [("flex-direction", d), ("flex-wrap", w)]
    if n == "border" or n == "border-top" or n == "border-right" or n == "border-bottom" or n == "border-left" or n == "outline":
        return _expand_border(n, parts, v)
    return [(n, v)]

func _same_for_all(n, v):
    out := []
    for p in expand(n, "0 0 0 0"):
        append(out, (p[0], v))
    return out

func _is_number_text(t):
    for c in t:
        if not ((c >= '0' and c <= '9') or c == '.'):
            return false
    return len(t) > 0

func _expand_flex(parts, v):
    if len(parts) == 1:
        p := _s.lower(parts[0])
        if p == "none":
            return [("flex-grow", "0"), ("flex-shrink", "0"), ("flex-basis", "auto")]
        if p == "auto":
            return [("flex-grow", "1"), ("flex-shrink", "1"), ("flex-basis", "auto")]
        if p == "initial":
            return [("flex-grow", "0"), ("flex-shrink", "1"), ("flex-basis", "auto")]
        if _is_number_text(p):
            return [("flex-grow", p), ("flex-shrink", "1"), ("flex-basis", "0%")]
        return [("flex-grow", "1"), ("flex-shrink", "1"), ("flex-basis", parts[0])]
    if len(parts) == 2:
        if _is_number_text(parts[1]):
            return [("flex-grow", parts[0]), ("flex-shrink", parts[1]), ("flex-basis", "0%")]
        return [("flex-grow", parts[0]), ("flex-shrink", "1"), ("flex-basis", parts[1])]
    if len(parts) == 3:
        return [("flex-grow", parts[0]), ("flex-shrink", parts[1]), ("flex-basis", parts[2])]
    return [("flex", v)]

func _expand_border(n, parts, v):
    width := "medium"
    style := "none"
    color := "currentcolor"
    for p in parts:
        lp := _s.lower(p)
        if lp in BORDER_STYLES:
            style = p
        elif lp in ["thin", "medium", "thick"] or (len(p) > 0 and ((p[0] >= '0' and p[0] <= '9') or p[0] == '.')):
            width = p
        else:
            color = p
    if n == "border":
        out := []
        for side in _SIDES:
            append(out, ("border-" + side + "-width", width))
            append(out, ("border-" + side + "-style", style))
            append(out, ("border-" + side + "-color", color))
        return out
    return [(n + "-width", width), (n + "-style", style), (n + "-color", color)]
