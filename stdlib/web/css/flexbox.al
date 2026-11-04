# ALEX STANDARD LIBRARY — web.css.flexbox
#
# Flexbox : déclarations de conteneur et d'éléments (dicts prêts pour StyleRule) et calcul d'une ligne flexible
# (répartition de l'espace libre par flex-grow / flex-shrink, justify-content, gap) pour tester une mise en page.
#
#   use web.css.flexbox as fx
#   fx.flex("row", "between", "center", true, "1rem")
#   # {"display": "flex", "flex-direction": "row", "flex-wrap": "wrap", "justify-content": "space-between",
#   #  "align-items": "center", "gap": "1rem"}
#   fx.center()                       # display: flex; justify-content: center; align-items: center
#   fx.stack("0.5rem")                # colonne avec espacement
#   fx.item(1, 0, "200px")            # {"flex": "1 0 200px"}
#   fx.layout(600, [fx.Item(100, 1), fx.Item(100, 2), fx.Item(100)], 10, "start")
#   # [(0, 193.333), (203.333, 286.667), (500, 100)]   (position, taille) — reste 280 réparti 1:2
#
# Erreurs : CssValueError (valeur inconnue pour direction / justify / align / wrap).

from core use len, type, to_float, to_int
from collections use append
use string as _s
use web.css.css_errors as _err

const DIRECTIONS := ["row", "row-reverse", "column", "column-reverse"]
const JUSTIFY := ["flex-start", "flex-end", "start", "end", "center", "space-between", "space-around", "space-evenly", "stretch", "normal", "left", "right"]
const ALIGN := ["flex-start", "flex-end", "start", "end", "center", "baseline", "first baseline", "last baseline", "stretch", "normal", "self-start", "self-end", "auto"]
const WRAPS := ["nowrap", "wrap", "wrap-reverse"]
const _ALIASES := {"between": "space-between", "around": "space-around", "evenly": "space-evenly", "top": "flex-start", "bottom": "flex-end"}

func _alias(v):
    t := _s.lower(_s.trim(str(v)))
    if t in _ALIASES:
        return _ALIASES[t]
    return t

func _check(v, allowed, what):
    t := _alias(v)
    if not (t in allowed) and not _s.starts_with(t, "safe ") and not _s.starts_with(t, "unsafe "):
        _err.value_error("flexbox", what + " inconnu « " + str(v) + " »")
    return t

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return str(v) + "px" if v != 0 else "0"
    return str(v)

# Conteneur flexible ; wrap : true / false / "wrap-reverse" ; null (ou false pour direction) : propriété omise.
func flex(direction="row", justify=null, align=null, wrap=null, gap=null, inline=false):
    d := {"display": "inline-flex" if inline else "flex"}
    if direction != null and direction != false:
        d["flex-direction"] = _check(direction, DIRECTIONS, "direction")
    if wrap != null:
        if wrap == true:
            d["flex-wrap"] = "wrap"
        elif wrap == false:
            d["flex-wrap"] = "nowrap"
        else:
            d["flex-wrap"] = _check(wrap, WRAPS, "wrap")
    if justify != null:
        d["justify-content"] = _check(justify, JUSTIFY, "justify-content")
    if align != null:
        d["align-items"] = _check(align, ALIGN, "align-items")
    if gap != null:
        d["gap"] = _len(gap)
    return d

func row(gap=null, align=null):
    return flex("row", null, align, null, gap)

func column(gap=null, align=null):
    return flex("column", null, align, null, gap)

# Pile verticale espacée.
func stack(gap="1rem"):
    return flex("column", null, null, null, gap)

# Rangée qui passe à la ligne (barre d'outils, étiquettes).
func cluster(gap="0.5rem", justify="flex-start"):
    return flex("row", justify, "center", true, gap)

func center(inline=false):
    return flex(false, "center", "center", null, null, inline)

func space_between(align="center"):
    return flex("row", "space-between", align)

# Ligne de contenu (align-content) d'un conteneur multiligne.
func align_content(value):
    return {"align-content": _alias(value)}

# Élément flexible : « flex: grow shrink basis ».
func item(grow=0, shrink=1, basis="auto"):
    return {"flex": str(grow) + " " + str(shrink) + " " + _len(basis)}

func grow(n=1):
    return {"flex-grow": str(n)}

func shrink(n=1):
    return {"flex-shrink": str(n)}

func basis(v):
    return {"flex-basis": _len(v)}

func fill():
    return {"flex": "1 1 0%"}

func fixed(size):
    return {"flex": "0 0 " + _len(size)}

func order(n):
    return {"order": str(n)}

func align_self(value):
    return {"align-self": _check(value, ALIGN, "align-self")}

# Pousse l'élément au bout de la ligne (margin auto).
func push_end(direction="row"):
    if direction == "column":
        return {"margin-top": "auto"}
    return {"margin-left": "auto"}

# ---------------------------------------------------------------- calcul d'une ligne

# Élément pour layout : taille de base (px), facteurs, bornes min / max (px, null : aucune).
class Item:
    func init(basis=0, grow=0, shrink=1, min_size=0, max_size=null):
        self.basis = to_float(basis)
        self.grow = to_float(grow)
        self.shrink = to_float(shrink)
        self.min_size = to_float(min_size)
        self.max_size = to_float(max_size) if max_size != null else null

func _clamp(item, v):
    x := v
    if item.max_size != null and x > item.max_size:
        x = item.max_size
    if x < item.min_size:
        x = item.min_size
    return x

# Tailles résolues (algorithme flexible de CSS : gel itératif des éléments bornés).
func resolve_sizes(available, items, gap=0):
    n := len(items)
    sizes := []
    frozen := []
    for it in items:
        append(sizes, it.basis)
        append(frozen, false)
    inner := to_float(available) - to_float(gap) * (n - 1 if n > 0 else 0)
    total := 0.0
    for it in items:
        total += it.basis
    growing := total < inner
    rounds := 0
    while rounds < n + 1:
        rounds += 1
        used := 0.0
        weight := 0.0
        i := 0
        while i < n:
            it := items[i]
            if frozen[i]:
                used += sizes[i]
            else:
                used += it.basis
                weight += it.grow if growing else it.shrink * it.basis
            i += 1
        free := inner - used
        if weight == 0:
            break
        violated := false
        i = 0
        while i < n:
            if not frozen[i]:
                it := items[i]
                share := (it.grow / weight) if growing else (it.shrink * it.basis / weight)
                target := it.basis + free * share
                if (growing and it.grow == 0) or (not growing and it.shrink == 0):
                    target = it.basis
                c := _clamp(it, target)
                if c != target:
                    frozen[i] = true
                    violated = true
                sizes[i] = c
            i += 1
        if not violated:
            break
    i := 0
    while i < n:
        sizes[i] = _clamp(items[i], sizes[i])
        i += 1
    return sizes

# Positions et tailles d'une ligne : liste de (position, taille) selon justify-content.
func layout(available, items, gap=0, justify="flex-start"):
    sizes := resolve_sizes(available, items, gap)
    n := len(items)
    used := 0.0
    for s in sizes:
        used += s
    g := to_float(gap)
    free := to_float(available) - used - g * (n - 1 if n > 0 else 0)
    if free < 0:
        free = 0.0
    j := _alias(justify)
    start := 0.0
    between := g
    if j == "flex-end" or j == "end" or j == "right":
        start = free
    elif j == "center":
        start = free / 2
    elif j == "space-between" and n > 1:
        between = g + free / (n - 1)
    elif j == "space-around" and n > 0:
        start = free / n / 2
        between = g + free / n
    elif j == "space-evenly" and n > 0:
        start = free / (n + 1)
        between = g + free / (n + 1)
    out := []
    pos := start
    i := 0
    while i < n:
        append(out, (_round(pos), _round(sizes[i])))
        pos += sizes[i] + between
        i += 1
    return out

func _round(x):
    r := to_float(to_int(x * 1000.0 + (0.5 if x >= 0 else -0.5))) / 1000.0
    if r == to_float(to_int(r)):
        return to_int(r)
    return r
