# ALEX STANDARD LIBRARY — web.css.grid
#
# CSS Grid : déclarations de grille et de placement (dicts prêts pour StyleRule), fonctions de pistes
# (repeat, minmax, fit-content, auto-fill / auto-fit), zones nommées (construction, analyse et vérification
# des rectangles) et calcul des tailles de pistes (px, %, fr, auto, minmax(), repeat(auto-fill, …)).
#
#   use web.css.grid as g
#   g.grid(g.repeat(3, "1fr"), null, "1rem")      # {"display": "grid", "grid-template-columns": "repeat(3, 1fr)", "gap": "1rem"}
#   g.auto_fill("200px")                          # repeat(auto-fill, minmax(200px, 1fr))
#   g.areas(["tete tete", "menu corps", "pied pied"])   # "tete tete" "menu corps" "pied pied"
#   g.parse_areas("\"a a\" \"b c\"")              # {"a": (1, 1, 2, 3), "b": (2, 1, 3, 2), "c": (2, 2, 3, 3)}
#   g.place("2 / 4", "1")                         # {"grid-column": "2 / 4", "grid-row": "1"}
#   g.span(2)                                     # span 2
#   g.track_sizes("200px 1fr 2fr", 800, 20)      # [200.0, 186.67, 373.33] (2 gouttières de 20)
#   g.track_sizes("repeat(auto-fill, minmax(150px, 1fr))", 700, 10)   # 4 pistes de 167.5
#
# Erreurs : CssValueError (zone non rectangulaire, lignes de longueurs différentes, piste invalide).

from core use len, type, to_float, to_int
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units
use web.css.functions as _fn

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return str(v) + "px" if v != 0 else "0"
    return str(v)

func _tracks(v):
    if type(v) == "list" or type(v) == "tuple":
        parts := []
        for x in v:
            append(parts, _len(x))
        return _s.join(" ", parts)
    if type(v) == "int":
        return repeat(v, "1fr")
    return str(v)

# Conteneur de grille ; columns / rows : texte, liste de pistes ou entier (n colonnes égales).
func grid(columns=null, rows=null, gap=null, areas_value=null, auto_flow=null, inline=false):
    d := {"display": "inline-grid" if inline else "grid"}
    if columns != null:
        d["grid-template-columns"] = _tracks(columns)
    if rows != null:
        d["grid-template-rows"] = _tracks(rows)
    if areas_value != null:
        d["grid-template-areas"] = areas(areas_value) if type(areas_value) == "list" else str(areas_value)
    if auto_flow != null:
        d["grid-auto-flow"] = auto_flow
    if gap != null:
        d["gap"] = _len(gap)
    return d

func columns(n, gap=null):
    return grid(repeat(n, "minmax(0, 1fr)"), null, gap)

# Grille réactive : autant de colonnes de largeur minimale min_width que possible.
func responsive(min_width="16rem", gap="1rem", fit=false):
    return grid(auto_fit(min_width) if fit else auto_fill(min_width), null, gap)

func repeat(count, track):
    return "repeat(" + str(count) + ", " + _tracks(track) + ")"

func minmax(a, b):
    return "minmax(" + _len(a) + ", " + _len(b) + ")"

func fit_content(v):
    return "fit-content(" + _len(v) + ")"

func auto_fill(min_width, max_width="1fr"):
    return "repeat(auto-fill, minmax(" + _len(min_width) + ", " + _len(max_width) + "))"

func auto_fit(min_width, max_width="1fr"):
    return "repeat(auto-fit, minmax(" + _len(min_width) + ", " + _len(max_width) + "))"

func span(n):
    return "span " + str(n)

func line(start, end=null):
    if end == null:
        return str(start)
    return str(start) + " / " + str(end)

# Placement d'un élément (colonnes, lignes).
func place(column=null, row=null):
    d := {}
    if column != null:
        d["grid-column"] = str(column)
    if row != null:
        d["grid-row"] = str(row)
    return d

func area(name):
    return {"grid-area": name}

func gap(row_gap, column_gap=null):
    if column_gap == null:
        return {"gap": _len(row_gap)}
    return {"row-gap": _len(row_gap), "column-gap": _len(column_gap)}

func place_items(align, justify=null):
    return {"place-items": align if justify == null else align + " " + justify}

func subgrid(columns=true, rows=false):
    d := {"display": "grid"}
    if columns:
        d["grid-template-columns"] = "subgrid"
    if rows:
        d["grid-template-rows"] = "subgrid"
    return d

# Disposition classique en-tête / barre latérale / contenu / pied.
func holy_grail(sidebar="16rem", gap="1rem"):
    return grid([_len(sidebar), "1fr"], ["auto", "1fr", "auto"], gap, ["header header", "sidebar main", "footer footer"])

# ---------------------------------------------------------------- zones

# Valeur de grid-template-areas depuis des lignes (« a a b »).
func areas(rows):
    parts := []
    for r in rows:
        append(parts, "\"" + _s.trim(r) + "\"")
    return _s.join(" ", parts)

func _area_rows(text):
    rows := []
    for t in _value.tokenize(text):
        if t.kind == _value.STRING:
            append(rows, t.value)
    return rows

func _cells(row):
    out := []
    for w in _s.split(_s.trim(row), " "):
        if w != "":
            # « ... » ou une suite de points : cellule vide
            if _s.starts_with(w, ".") and _s.replace(w, ".", "") == "":
                append(out, ".")
            else:
                append(out, w)
    return out

# Zones nommées -> dict nom -> (ligne_début, colonne_début, ligne_fin, colonne_fin) (numéros de lignes de grille).
func parse_areas(text):
    rows := _area_rows(text) if type(text) == "str" else text
    grid_cells := []
    width := -1
    for r in rows:
        cs := _cells(r)
        if width >= 0 and len(cs) != width:
            _err.value_error("grid.parse_areas", "lignes de longueurs différentes dans grid-template-areas")
        width = len(cs)
        append(grid_cells, cs)
    found := {}
    ri := 0
    while ri < len(grid_cells):
        ci := 0
        while ci < width:
            name := grid_cells[ri][ci]
            if name != ".":
                if name in found:
                    b := found[name]
                    found[name] = (b[0] if b[0] < ri + 1 else ri + 1, b[1] if b[1] < ci + 1 else ci + 1, b[2] if b[2] > ri + 2 else ri + 2, b[3] if b[3] > ci + 2 else ci + 2)
                else:
                    found[name] = (ri + 1, ci + 1, ri + 2, ci + 2)
            ci += 1
        ri += 1
    for name in keys(found):
        b := found[name]
        r := b[0]
        while r < b[2]:
            c := b[1]
            while c < b[3]:
                if grid_cells[r - 1][c - 1] != name:
                    _err.value_error("grid.parse_areas", "la zone « " + name + " » n'est pas rectangulaire")
                c += 1
            r += 1
    return found

func is_valid_areas(text):
    try:
        parse_areas(text)
        return true
    catch e:
        return false

# ---------------------------------------------------------------- tailles des pistes

class _Track:
    func init(kind, value, max_kind=null, max_value=null):
        self.kind = kind            # "px", "fr", "auto"
        self.value = value
        self.max_kind = max_kind
        self.max_value = max_value

func _track_from(item, available, ctx):
    if isinstance(item, _value.Function):
        nm := item.lower_name()
        groups := item.arg_groups()
        if nm == "minmax" and len(groups) == 2:
            lo := _track_from(groups[0][0], available, ctx)
            hi := _track_from(groups[1][0], available, ctx)
            return _Track(lo.kind if lo.kind != "fr" else "px", lo.value if lo.kind != "fr" else 0.0, hi.kind, hi.value)
        if nm == "fit-content" and len(groups) == 1:
            hi := _track_from(groups[0][0], available, ctx)
            return _Track("auto", 0.0, "px", hi.value)
        if nm == "calc" or nm == "min" or nm == "max" or nm == "clamp":
            return _Track("px", _fn.evaluate(item.to_css(), ctx))
        _err.value_error("grid.track_sizes", "piste non prise en charge « " + item.to_css() + " »")
    if isinstance(item, _value.Token):
        if item.kind == _value.DIMENSION:
            u := _s.lower(item.unit)
            if u == "fr":
                return _Track("fr", to_float(item.value))
            return _Track("px", _units.to_px(_units.Dimension(item.value, u), ctx))
        if item.kind == _value.PERCENTAGE:
            return _Track("px", to_float(item.value) * available / 100.0)
        if item.kind == _value.NUMBER and to_float(item.value) == 0.0:
            return _Track("px", 0.0)
        if item.kind == _value.IDENT:
            w := _s.lower(item.value)
            if w in ["auto", "min-content", "max-content"]:
                return _Track("auto", 0.0)
    _err.value_error("grid.track_sizes", "piste invalide « " + item.to_css() + " »")

func _min_size(t):
    return t.value if t.kind == "px" else 0.0

# Tailles (px) des pistes d'un gabarit pour un espace disponible ; les pistes auto prennent leur part de
# l'espace restant quand il n'y a pas de fr (contenu supposé vide).
func track_sizes(template, available, gap=0, ctx=null):
    c := ctx if ctx != null else _units.Context(16.0, 16.0, 1280.0, 720.0, to_float(available))
    av := to_float(available)
    g := to_float(gap)
    items := _value.parse(str(template)).components
    tracks := []
    for it in items:
        if isinstance(it, _value.Function) and it.lower_name() == "repeat":
            groups := it.arg_groups()
            if len(groups) < 2:
                _err.value_error("grid.track_sizes", "repeat() incomplet")
            count_text := _s.lower(_value.serialize(groups[0]))
            inner := []
            for x in groups[1]:
                if not (isinstance(x, _value.Token) and x.kind == _value.WHITESPACE):
                    append(inner, _track_from(x, av, c))
            n := 0
            if count_text == "auto-fill" or count_text == "auto-fit":
                per := 0.0
                for t in inner:
                    per += _min_size(t) if t.max_kind != "px" or t.kind == "px" else t.max_value
                per_gap := per + g * len(inner)
                n = 1
                if per_gap > 0:
                    n = to_int((av + g) / per_gap)
                if n < 1:
                    n = 1
            else:
                n = to_int(count_text)
            k := 0
            while k < n:
                for t in inner:
                    append(tracks, t)
                k += 1
        else:
            append(tracks, _track_from(it, av, c))
    nt := len(tracks)
    free := av - g * (nt - 1 if nt > 0 else 0)
    sizes := []
    flex := []
    mins := []
    for t in tracks:
        if t.kind == "fr":
            append(flex, t.value)
            append(mins, 0.0)
            append(sizes, 0.0)
        elif t.max_kind == "fr":
            append(flex, t.max_value)
            append(mins, t.value)
            append(sizes, t.value)
        else:
            append(flex, 0.0)
            append(mins, t.value)
            append(sizes, t.value)
            free -= t.value
    frozen := []
    for f in flex:
        append(frozen, f == 0.0)
    has_flex := false
    for f in flex:
        if f > 0:
            has_flex = true
    if has_flex:
        while true:
            rest := free
            weight := 0.0
            i := 0
            while i < nt:
                if flex[i] > 0:
                    if frozen[i]:
                        rest -= sizes[i]
                    else:
                        weight += flex[i]
                i += 1
            if weight == 0:
                break
            unit := rest / weight if rest > 0 else 0.0
            changed := false
            i = 0
            while i < nt:
                if flex[i] > 0 and not frozen[i]:
                    v := unit * flex[i]
                    if v < mins[i]:
                        sizes[i] = mins[i]
                        frozen[i] = true
                        changed = true
                    else:
                        sizes[i] = v
                i += 1
            if not changed:
                break
        return sizes
    autos := 0
    for t in tracks:
        if t.kind == "auto" and t.max_kind == null:
            autos += 1
    if free > 0:
        i := 0
        while i < nt:
            t := tracks[i]
            if t.max_kind == "px" and t.max_value > sizes[i]:
                room := t.max_value - sizes[i]
                add := room if room < free else free
                sizes[i] = sizes[i] + add
                free -= add
            i += 1
        if autos > 0 and free > 0:
            share := free / autos
            i = 0
            while i < nt:
                t := tracks[i]
                if t.kind == "auto" and t.max_kind == null:
                    sizes[i] = sizes[i] + share
                i += 1
    return sizes

# Positions de début (px) des pistes.
func track_positions(sizes, gap=0):
    out := []
    pos := 0.0
    for s in sizes:
        append(out, pos)
        pos += s + to_float(gap)
    return out
