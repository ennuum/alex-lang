# ALEX STANDARD LIBRARY — ui.view.wbase (interne)
#
# Classe de base des composants et aides de dessin communes. Un composant décrit sa taille (measure), place
# ses enfants (arrange), se dessine sur la surface (paint) et réagit au clavier (key), à la souris (mouse)
# et à la molette (wheel). Les coordonnées sont celles de la surface : cellules dans le terminal, pixels dans
# une fenêtre ; les métriques de la surface (s.cw, s.lh, s.ch, s.rh, s.px, s.py...) font le lien.

from core use len, type, to_int
from collections use append, contains_key
use ui.view.util as _u

class Widget:
    func init():
        self.stretch_w = false          # étiré en largeur dans une colonne
        self.stretch_h = false          # étiré en hauteur dans une ligne
        self.grow = 0                   # part de l'espace libre (flex) par défaut
        self.arrows_move_focus = false  # ← → ↑ ↓ passent au composant suivant s'ils ne servent pas

    func focusable(app, n):
        return false

    func wants_w(n):
        return self.stretch_w

    func wants_h(n):
        return self.stretch_h

    func children(app, n):
        return n.children

    # Appelé après prepare (n.st est prêt) : enregistrer raccourcis, barre de menus...
    func prepared(app, n):
        return null

    func measure(app, n, max_w):
        return [0, 0]

    func width_for(app, n, chars):
        return chars * app.s.cw

    func height_for(app, n, lines):
        return lines * app.s.lh

    func arrange(app, n):
        return null

    func paint(app, n):
        return null

    func key(app, n, ev):
        return false

    func mouse(app, n, ev):
        return false

    func wheel(app, n, ev):
        return false

    # Clic sur n qui vient de fermer une de ses superpositions (menu, liste ouverte).
    func after_dismiss(app, n, ev):
        return false

    func text_of(n):
        return null

    # Vrai : reçoit la souris à la place de ses descendants (voir Runtime._mouse).
    func intercepts(n):
        return false

func enabled(n):
    return n.get("enabled", true) != false

func key_of(ev):
    if ev["type"] != "key":
        return ""
    return ev["key"]

# Valeur contrôlée : la propriété du programme fait foi quand elle change ; entre-temps, la valeur
# modifiée par l'utilisateur est gardée dans l'état (programme qui n'écoute pas on_change).
func controlled(st, name, prop_value):
    pk := "__prop_" + name
    if not contains_key(st, pk) or st[pk] != prop_value:
        st[pk] = prop_value
        st[name] = prop_value
    return st[name]

func st_get(st, name, fallback):
    if contains_key(st, name):
        return st[name]
    return fallback

# Cadre d'un champ (input, select, spinbox, listes) : fond, bordure (fenêtre), focus.
func field_box(app, n, focused, role="field"):
    s := app.s
    bg := role
    if focused and s.cell:
        bg = "field_focus"
    if not enabled(n):
        bg = "field_disabled" if s.cell else role
    s.fill(n.x, n.y, n.w, n.h, bg, s.radius)
    if not s.cell:
        s.frame(n.x, n.y, n.w, n.h, "accent" if focused else "border", s.radius, focused)

# y du texte centré verticalement dans [y, y + h).
func text_y(app, y, h, font="normal"):
    lh := app.s.line_height(font)
    return y + _u.imax(0, (h - lh) // 2)

# Barre de défilement verticale à droite de n si total > visible (en lignes) ; renvoie la largeur prise.
func vscroll(app, x, y, h, total, visible, top):
    if total <= visible or h <= 0:
        return 0
    app.s.scrollbar(x, y, h, top / total, visible / total)
    return app.s.sbw

# Nouvelle première ligne visible pour un clic à y dans une barre de défilement.
func vscroll_click(y_rel, h, total, visible):
    frac := y_rel / _u.imax(1, h)
    return _u.clamp(to_int(frac * total - visible / 2), 0, _u.imax(0, total - visible))

# Premier indice visible gardant index affiché dans visible lignes.
func keep_visible(top, index, visible):
    if index < top:
        return _u.imax(0, index)
    if index >= top + visible:
        return _u.imax(0, index - visible + 1)
    return top

# Navigation dans une liste de count éléments : nouvel indice, ou null si la touche ne navigue pas.
func list_nav(key, count, cur, page):
    if count <= 0:
        return null
    if cur == null or cur < 0:
        if key == "down" or key == "home" or key == "page_down":
            return 0
        if key == "up" or key == "end" or key == "page_up":
            return count - 1
        return null
    nxt := cur
    if key == "up":
        nxt = cur - 1
    elif key == "down":
        nxt = cur + 1
    elif key == "page_up":
        nxt = cur - page
    elif key == "page_down":
        nxt = cur + page
    elif key == "home":
        nxt = 0
    elif key == "end":
        nxt = count - 1
    else:
        return null
    return _u.clamp(nxt, 0, count - 1)

# Rôles de texte selon le style d'un texte.
func text_role(style):
    if style == "muted":
        return "muted"
    if style == "error":
        return "danger"
    if style == "success":
        return "success"
    if style == "warning":
        return "warning"
    if style == "accent":
        return "accent"
    return "text"

func text_font(style):
    if style == "title":
        return "title"
    if style == "subtitle" or style == "bold":
        return "bold"
    return "normal"

# ---------------------------------------------------------------- conteneurs flex (column, row)
class Flex extends Widget:
    func init(horizontal):
        super.init()
        self.horizontal = horizontal
        self.stretch_w = true
        self.stretch_h = true

    func gap(app, n):
        g := n.get("gap")
        if g == null:
            return app.s.gx if self.horizontal else app.s.gy
        return g * (app.s.ux if self.horizontal else app.s.uy)

    func pad(app, n):
        p := n.get("padding", 0)
        if type(p) == "list":
            if len(p) == 2:
                return [p[0] * app.s.ux, p[1] * app.s.uy, p[0] * app.s.ux, p[1] * app.s.uy]
            return [p[0] * app.s.ux, p[1] * app.s.uy, p[2] * app.s.ux, p[3] * app.s.uy]
        return [p * app.s.ux, p * app.s.uy, p * app.s.ux, p * app.s.uy]

    func measure(app, n, max_w):
        p := self.pad(app, n)
        inner := _u.imax(0, max_w - p[0] - p[2])
        g := self.gap(app, n)
        w := 0
        h := 0
        i := 0
        for c in n.flow:
            if self.horizontal:
                m := app.measure(c, inner)
                w += m[0] + (g if i > 0 else 0)
                h = _u.imax(h, m[1])
            else:
                m := app.measure(c, inner)
                w = _u.imax(w, m[0])
                h += m[1] + (g if i > 0 else 0)
            i += 1
        return [w + p[0] + p[2], h + p[1] + p[3]]

    func arrange(app, n):
        p := self.pad(app, n)
        place_flex(app, n, n.flow, n.x + p[0], n.y + p[1], n.w - p[0] - p[2], n.h - p[1] - p[3], self.horizontal, self.gap(app, n), n.get("cross"), n.get("justify", "start"), n.clip)

    func paint(app, n):
        app.paint_children(n)

# Place kids sur une ligne (horizontal) ou une colonne dans le rectangle donné.
func place_flex(app, n, kids, ix, iy, iw, ih, horizontal, gap, cross, justify, clip):
    count := len(kids)
    if count == 0:
        return null
    main := iw if horizontal else ih
    sizes := []
    total := gap * (count - 1)
    grow_total := 0
    for c in kids:
        sz := c.mw if horizontal else c.mh
        append(sizes, sz)
        total += sz
        grow_total += app.grow(c)
    extra := main - total
    if extra > 0 and grow_total > 0:
        given := 0
        last := -1
        i := 0
        for c in kids:
            g := app.grow(c)
            if g > 0:
                add := to_int(extra * g / grow_total)
                sizes[i] += add
                given += add
                last = i
            i += 1
        if last >= 0:
            sizes[last] += extra - given
        extra = 0
    elif extra < 0:
        # Manque de place : réduire d'abord les éléments extensibles, puis les autres, chacun en proportion
        # de ce qu'il peut céder (jusqu'à une ligne, ou deux caractères).
        need := -extra
        minimum := app.s.cw * 2 if horizontal else app.s.lh
        for pass_no in [0, 1]:
            if need <= 0:
                break
            room := 0
            i := 0
            for c in kids:
                if pass_no == 1 or app.grow(c) > 0:
                    room += _u.imax(0, sizes[i] - minimum)
                i += 1
            if room <= 0:
                continue
            want := _u.imin(need, room)
            taken := 0
            i = 0
            for c in kids:
                if pass_no == 1 or app.grow(c) > 0:
                    can := _u.imax(0, sizes[i] - minimum)
                    if can > 0:
                        take := _u.imin(can, to_int(want * can / room))
                        sizes[i] -= take
                        taken += take
                i += 1
            # reste dû aux arrondis
            i = len(kids) - 1
            while i >= 0 and taken < want:
                c := kids[i]
                if pass_no == 1 or app.grow(c) > 0:
                    can := _u.imax(0, sizes[i] - minimum)
                    take := _u.imin(can, want - taken)
                    sizes[i] -= take
                    taken += take
                i -= 1
            need -= taken
        extra = 0
    pos := 0
    between := 0
    if extra > 0:
        if justify == "center":
            pos = extra // 2
        elif justify == "end":
            pos = extra
        elif justify == "between" and count > 1:
            between = extra // (count - 1)
    i := 0
    for c in kids:
        sz := sizes[i]
        if horizontal:
            ch := ih
            if not app.stretch_h(c, cross):
                ch = _u.imin(c.mh, ih)
            dy := 0
            a := c.get("align", cross)
            if a == null:
                a = "center"            # dans une ligne, centré verticalement par défaut
            if a == "center":
                dy = (ih - ch) // 2
            elif a == "end":
                dy = ih - ch
            app.arrange(c, ix + pos, iy + dy, sz, ch, clip)
        else:
            cw := iw
            if not app.stretch_w(c, cross):
                cw = _u.imin(c.mw, iw)
            dx := 0
            a := c.get("align", cross)
            if a == "center":
                dx = (iw - cw) // 2
            elif a == "end":
                dx = iw - cw
            app.arrange(c, ix + dx, iy + pos, cw, sz, clip)
        pos += sz + gap + between
        i += 1
