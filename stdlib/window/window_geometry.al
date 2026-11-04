# ALEX STANDARD LIBRARY — window.window_geometry
#
# Géométrie des fenêtres : rectangles (Rect), points et tailles, avec les opérations de placement courantes —
# intersection, union, marges, centrage, alignement (9 positions), ajustement en gardant les proportions,
# maintien dans une zone (écran), grilles et dispositions (moitiés, quarts, mosaïque), conversion selon la densité
# (DPI) — et lecture / application sur une fenêtre réelle.
#
#   use window.window_geometry as wg
#   r := wg.Rect(100, 50, 800, 600)
#   ecran := wg.Rect(0, 0, 1920, 1040)
#   print(r.right(), r.center(), r.contains(150, 60))       # 900 [500, 350] true
#   print(r.centered_in(ecran))                             # Rect(560, 220, 800, 600)
#   print(r.aligned_in(ecran, "bottom-right", 16))          # coin inférieur droit avec 16 px de marge
#   print(wg.fit(1920, 1080, 800, 800))                     # [800, 450] (proportions conservées)
#   moities := ecran.split_columns(2)                       # [Rect gauche, Rect droite]
#   print(wg.layout(ecran, "right_half"))                   # Rect(960, 0, 960, 1040)
#   wg.apply(fenetre, r.clamped_to(ecran))                  # place la fenêtre (taille et position)
#   print(wg.of(fenetre))                                   # Rect de la fenêtre
#
# Erreurs : GeometryError (dimensions négatives, alignement ou disposition inconnus).

from core use len, type, to_int
from collections use append
use string as _s

const ALIGNMENTS := ["top-left", "top", "top-right", "left", "center", "right", "bottom-left", "bottom", "bottom-right"]
const LAYOUTS := ["left_half", "right_half", "top_half", "bottom_half", "top_left", "top_right", "bottom_left",
                  "bottom_right", "center", "maximize", "left_third", "center_third", "right_third"]

func _int(v):
    if type(v) == "float":
        if v >= 0:
            return to_int(v + 0.5)
        return -to_int(-v + 0.5)
    return v

class Rect:
    func init(x, y, width, height):
        if width < 0 or height < 0:
            raise("GeometryError", "Rect : largeur et hauteur >= 0 attendues (" + str(width) + "x" + str(height) + ")")
        self.x = _int(x)
        self.y = _int(y)
        self.width = _int(width)
        self.height = _int(height)

    func right():
        return self.x + self.width

    func bottom():
        return self.y + self.height

    func size():
        return [self.width, self.height]

    func position():
        return [self.x, self.y]

    func area():
        return self.width * self.height

    func is_empty():
        return self.width == 0 or self.height == 0

    func center():
        return [self.x + self.width // 2, self.y + self.height // 2]

    func aspect():
        if self.height == 0:
            return null
        return self.width / self.height

    func contains(px, py):
        return px >= self.x and px < self.right() and py >= self.y and py < self.bottom()

    func contains_rect(o):
        return o.x >= self.x and o.y >= self.y and o.right() <= self.right() and o.bottom() <= self.bottom()

    func intersects(o):
        return self.x < o.right() and o.x < self.right() and self.y < o.bottom() and o.y < self.bottom()

    func intersection(o):
        x1 := _max(self.x, o.x)
        y1 := _max(self.y, o.y)
        x2 := _min(self.right(), o.right())
        y2 := _min(self.bottom(), o.bottom())
        if x2 <= x1 or y2 <= y1:
            return null
        return Rect(x1, y1, x2 - x1, y2 - y1)

    func union(o):
        x1 := _min(self.x, o.x)
        y1 := _min(self.y, o.y)
        return Rect(x1, y1, _max(self.right(), o.right()) - x1, _max(self.bottom(), o.bottom()) - y1)

    func moved(dx, dy):
        return Rect(self.x + dx, self.y + dy, self.width, self.height)

    func moved_to(x, y):
        return Rect(x, y, self.width, self.height)

    func resized(w, h):
        return Rect(self.x, self.y, w, h)

    func scaled(f):
        return Rect(self.x * f, self.y * f, self.width * f, self.height * f)

    # Marges intérieures (une valeur, ou [haut, droite, bas, gauche]).
    func inset(m):
        t := m
        r := m
        b := m
        l := m
        if type(m) == "list":
            t = m[0]
            r = m[1]
            b = m[2]
            l = m[3]
        return Rect(self.x + l, self.y + t, _max(0, self.width - l - r), _max(0, self.height - t - b))

    func outset(m):
        return Rect(self.x - m, self.y - m, self.width + 2 * m, self.height + 2 * m)

    func centered_in(area):
        return Rect(area.x + (area.width - self.width) // 2, area.y + (area.height - self.height) // 2, self.width, self.height)

    func aligned_in(area, where="center", margin=0):
        if not (where in ALIGNMENTS):
            raise("GeometryError", "alignement inconnu « " + where + " » (" + _s.join(", ", ALIGNMENTS) + ")")
        x := area.x + (area.width - self.width) // 2
        y := area.y + (area.height - self.height) // 2
        if _s.contains(where, "left"):
            x = area.x + margin
        elif _s.contains(where, "right"):
            x = area.right() - self.width - margin
        if _s.starts_with(where, "top"):
            y = area.y + margin
        elif _s.starts_with(where, "bottom"):
            y = area.bottom() - self.height - margin
        return Rect(x, y, self.width, self.height)

    # Ramené dans area (réduit si trop grand, puis déplacé pour être entièrement visible).
    func clamped_to(area):
        w := _min(self.width, area.width)
        h := _min(self.height, area.height)
        x := _min(_max(self.x, area.x), area.right() - w)
        y := _min(_max(self.y, area.y), area.bottom() - h)
        return Rect(x, y, w, h)

    func split_columns(n, gap=0):
        if n < 1:
            raise("GeometryError", "split_columns : n >= 1 attendu")
        out := []
        w := (self.width - gap * (n - 1)) // n
        i := 0
        while i < n:
            ww := w
            if i == n - 1:
                ww = self.width - (w + gap) * (n - 1)
            append(out, Rect(self.x + i * (w + gap), self.y, ww, self.height))
            i += 1
        return out

    func split_rows(n, gap=0):
        if n < 1:
            raise("GeometryError", "split_rows : n >= 1 attendu")
        out := []
        h := (self.height - gap * (n - 1)) // n
        i := 0
        while i < n:
            hh := h
            if i == n - 1:
                hh = self.height - (h + gap) * (n - 1)
            append(out, Rect(self.x, self.y + i * (h + gap), self.width, hh))
            i += 1
        return out

    # Cellules d'une grille (ligne par ligne).
    func grid(columns, rows, gap=0):
        out := []
        for r in self.split_rows(rows, gap):
            for c in r.split_columns(columns, gap):
                append(out, c)
        return out

    func to_dict():
        return {"x": self.x, "y": self.y, "width": self.width, "height": self.height}

    func __eq__(o):
        if type(o) == "list":
            return [self.x, self.y, self.width, self.height] == o
        if type(o) == "null" or type(o) == "int" or type(o) == "str":
            return false
        return self.x == o.x and self.y == o.y and self.width == o.width and self.height == o.height

    func __str__():
        return "Rect(" + str(self.x) + ", " + str(self.y) + ", " + str(self.width) + ", " + str(self.height) + ")"

func _min(a, b):
    if a < b:
        return a
    return b

func _max(a, b):
    if a > b:
        return a
    return b

func rect(x, y, w, h):
    return Rect(x, y, w, h)

func from_dict(d):
    return Rect(d["x"], d["y"], d["width"], d["height"])

func from_points(x1, y1, x2, y2):
    return Rect(_min(x1, x2), _min(y1, y2), _max(x1, x2) - _min(x1, x2), _max(y1, y2) - _min(y1, y2))

# Taille (w, h) ajustée dans (max_w, max_h) en gardant les proportions de (w, h).
func fit(w, h, max_w, max_h):
    if w <= 0 or h <= 0:
        raise("GeometryError", "fit : dimensions > 0 attendues")
    f := max_w / w
    if max_h / h < f:
        f = max_h / h
    return [_int(w * f), _int(h * f)]

# Taille qui couvre (max_w, max_h) en gardant les proportions (rognage).
func cover(w, h, area_w, area_h):
    f := area_w / w
    if area_h / h > f:
        f = area_h / h
    return [_int(w * f), _int(h * f)]

func layout(area, name, gap=0):
    if not (name in LAYOUTS):
        raise("GeometryError", "disposition inconnue « " + name + " » (" + _s.join(", ", LAYOUTS) + ")")
    if name == "maximize":
        return Rect(area.x, area.y, area.width, area.height)
    if name == "left_half":
        return area.split_columns(2, gap)[0]
    if name == "right_half":
        return area.split_columns(2, gap)[1]
    if name == "top_half":
        return area.split_rows(2, gap)[0]
    if name == "bottom_half":
        return area.split_rows(2, gap)[1]
    if name == "left_third":
        return area.split_columns(3, gap)[0]
    if name == "center_third":
        return area.split_columns(3, gap)[1]
    if name == "right_third":
        return area.split_columns(3, gap)[2]
    if name == "center":
        return Rect(0, 0, area.width * 2 // 3, area.height * 2 // 3).centered_in(area)
    g := area.grid(2, 2, gap)
    if name == "top_left":
        return g[0]
    if name == "top_right":
        return g[1]
    if name == "bottom_left":
        return g[2]
    return g[3]

# Mosaïque de n rectangles (colonnes ≈ racine de n).
func tile(area, n, gap=0):
    if n <= 0:
        return []
    cols := 1
    while cols * cols < n:
        cols += 1
    rows := (n + cols - 1) // cols
    cells := area.grid(cols, rows, gap)
    return cells[:n]

func cascade(area, n, width, height, step=32):
    out := []
    i := 0
    while i < n:
        r := Rect(area.x + i * step, area.y + i * step, width, height)
        append(out, r.clamped_to(area))
        i += 1
    return out

func dp_to_px(dp, dpi=96):
    return _int(dp * dpi / 96)

func px_to_dp(px, dpi=96):
    return px * 96 / dpi

# Rect d'une fenêtre (window.Window).
func of(win):
    p := win.position()
    s := win.size()
    return Rect(p[0], p[1], s[0], s[1])

func apply(win, r):
    win.move(r.x, r.y)
    win.set_size(r.width, r.height)
    return r
