# ALEX STANDARD LIBRARY — ui.view.wextra (interne)
#
# Composants graphiques libres : image (fichier PNG / BMP / PPM) et canvas (dessin par une fonction de
# l'application, souris et clavier en coordonnées locales). Dans le terminal, une image affiche son texte de
# remplacement et un canvas dessine avec les mêmes appels, en cellules.

from core use len, type, to_int, to_float
from collections use append, contains_key, keys
use ui.view.util as _u
use ui.view.wbase as _b
from ui.view.wbase use Widget

# Taille en unités de la surface : pixels dans une fenêtre, cellules dans le terminal.
func _px_size(app, n, w, h):
    s := app.s
    if s.cell:
        return [_u.imax(1, to_int(w / 8)), _u.imax(1, to_int(h / 18))]
    return [to_int(w), to_int(h)]

# ---------------------------------------------------------------- image
class Image extends Widget:
    func init():
        super.init()

    func measure(app, n, max_w):
        sz := _px_size(app, n, n.get("px_width", 64), n.get("px_height", 64))
        if app.s.cell:
            alt := str(n.get("alt", ""))
            return [_u.imin(max_w, _u.imax(len(alt), 1)), 1]
        return [_u.imin(sz[0], max_w), sz[1]]

    func paint(app, n):
        s := app.s
        if s.cell:
            alt := str(n.get("alt", ""))
            if alt != "":
                s.text(n.x, n.y, _u.fit(s, alt, n.w), n.get("role", "accent"))
            return null
        # garder les proportions dans le rectangle attribué
        pw := to_float(n.get("px_width", 64))
        ph := to_float(n.get("px_height", 64))
        k := n.w / pw
        if n.h / ph < k:
            k = n.h / ph
        if k <= 0:
            return null
        w := pw * k
        h := ph * k
        x := n.x + (n.w - w) / 2
        y := n.y + (n.h - h) / 2
        if not s.image(x, y, w, h, n.get("path"), n.get("opacity", 1.0)):
            alt := str(n.get("alt", ""))
            s.stroke(x, y, w, h, "border", 6, 1.0)
            if alt != "":
                s.text(x + 4, y + 4, _u.fit(s, alt, to_int(w) - 8), "muted")

    func text_of(n):
        return n.get("alt", null)

# ---------------------------------------------------------------- canvas
# Pinceau passé à la fonction de dessin : coordonnées LOCALES au composant ; couleurs « #rrggbb » ou rôles du
# thème (« accent », « text », « surface »...).
class Painter:
    func init(app, n):
        self.app = app
        self.s = app.s
        self.ox = n.x
        self.oy = n.y
        self.width = n.w
        self.height = n.h
        self.cell = app.s.cell
        self.now = app.now
        self.focused = app.is_focused(n)

    func fill(x, y, w, h, color, radius=0):
        self.s.fill(self.ox + x, self.oy + y, w, h, color, radius)

    func stroke(x, y, w, h, color, radius=0, width=1.0):
        self.s.stroke(self.ox + x, self.oy + y, w, h, color, radius, width)

    func line(x1, y1, x2, y2, color, width=1.5):
        self.s.line(self.ox + x1, self.oy + y1, self.ox + x2, self.oy + y2, color, width)

    func circle(cx, cy, r, color, filled=true, width=1.5):
        self.s.circle(self.ox + cx, self.oy + cy, r, color, filled, width)

    func text(x, y, t, color="text", font="normal"):
        self.s.text(self.ox + x, self.oy + y, str(t), color, font)

    func text_width(t, font="normal"):
        return self.s.text_width(str(t), font)

    func line_height(font="normal"):
        return self.s.line_height(font)

    func image(x, y, w, h, path, opacity=1.0):
        return self.s.image(self.ox + x, self.oy + y, w, h, path, opacity)

    func gradient(x, y, w, h, color_a, color_b, vertical=false):
        self.s.gradient(self.ox + x, self.oy + y, w, h, color_a, color_b, vertical)

    func shadow(x, y, w, h):
        if not self.cell:
            self.s.shadow(self.ox + x, self.oy + y, w, h)

    func clip(x, y, w, h):
        self.s.push_clip(self.ox + x, self.oy + y, w, h)

    func unclip():
        self.s.pop_clip()

    # Coupe t pour tenir dans w (avec « … »).
    func fit(t, w, font="normal"):
        return _u.fit(self.s, str(t), w)

class Canvas extends Widget:
    func init():
        super.init()
        self.grow = 0

    # expand : "both" (défaut), "w", "h" ou "none" — étirement en travers du conteneur ; flex : croissance.
    func wants_w(n):
        e := n.get("expand", "both")
        return e == "both" or e == "w"

    func wants_h(n):
        e := n.get("expand", "both")
        return e == "both" or e == "h"

    func focusable(app, n):
        return n.get("focusable", false)

    func measure(app, n, max_w):
        sz := _px_size(app, n, n.get("px_width", 200), n.get("px_height", 120))
        return [_u.imin(sz[0], max_w), sz[1]]

    func paint(app, n):
        app.s.push_clip(n.x, n.y, n.w, n.h)
        try:
            app.call(n.get("paint"), [Painter(app, n)])
        finally:
            app.s.pop_clip()
        if app.is_focused(n) and not app.s.cell and n.get("focus_ring", false):
            app.s.frame(n.x, n.y, n.w, n.h, "accent", 0, true)

    func _local(n, ev):
        out := {}
        for k in keys(ev):
            out[k] = ev[k]
        out["x"] = ev["x"] - n.x
        out["y"] = ev["y"] - n.y
        out["width"] = n.w
        out["height"] = n.h
        return out

    func mouse(app, n, ev):
        f := n.get("on_mouse", null)
        if f == null:
            return false
        if ev["action"] == "move" and not n.get("track_move", false):
            return false
        r := app.call(f, [self._local(n, ev)])
        return r != false

    func wheel(app, n, ev):
        f := n.get("on_wheel", null)
        if f == null:
            return false
        return app.call(f, [self._local(n, ev)]) != false

    func key(app, n, ev):
        f := n.get("on_key", null)
        if f == null:
            return false
        return app.call(f, [_b.key_of(ev), ev]) == true

# ---------------------------------------------------------------- surface de conception (Designer)
# Affiche son contenu (de vrais composants) dans un cadre de fenêtre de taille form_width x form_height et
# intercepte la souris : survol et clic désignent le composant d'identifiant « dz:<uid> » le plus profond sous
# le pointeur (on_pick(uid)), le coin inférieur droit redimensionne (on_resize(l, h)), Suppr -> on_delete().
class DesignSurface extends Widget:
    func init():
        super.init()
        self.stretch_w = true
        self.stretch_h = true
        self.grow = 1

    func focusable(app, n):
        return true

    func intercepts(n):
        return true

    func measure(app, n, max_w):
        return [_u.imin(max_w, 200), 200]

    func _form(app, n):
        s := app.s
        fw := n.get("form_width", 640)
        fh := n.get("form_height", 420)
        if s.cell:
            fw = _u.imax(10, to_int(fw / 8))
            fh = _u.imax(4, to_int(fh / 18))
        tb := 1 if s.cell else 30
        x0 := n.x + _u.imax(2 if s.cell else 24, (n.w - fw) // 2)
        y0 := n.y + (1 if s.cell else 24) + tb
        return [x0, y0, fw, fh, tb]

    func arrange(app, n):
        f := self._form(app, n)
        for c in n.flow:
            app.measure(c, f[2])
            app.arrange(c, f[0], f[1], f[2], f[3], [f[0], f[1], f[2], f[3]])

    func _rect(app, uid):
        if uid == null:
            return null
        for p in app.placed:
            if p.id == "dz:" + str(uid):
                return [p.x, p.y, p.w, p.h]
        return null

    func _pick(app, n, x, y):
        f := self._form(app, n)
        if x < f[0] or y < f[1] or x >= f[0] + f[2] or y >= f[1] + f[3]:
            return null
        best := null
        aire := 0
        for p in app.placed:
            if p.id != null and type(p.id) == "str" and len(p.id) > 3 and p.id[0] == 'd' and p.id[1] == 'z' and p.id[2] == ':':
                if x >= p.x and y >= p.y and x < p.x + p.w and y < p.y + p.h:
                    a := p.w * p.h
                    if best == null or a <= aire:
                        best = p
                        aire = a
        if best == null:
            return null
        return _slice_id(best.id)

    func paint(app, n):
        s := app.s
        f := self._form(app, n)
        s.fill(n.x, n.y, n.w, n.h, "code_bg")
        if not s.cell:
            # grille
            gx := n.x + 16
            while gx < n.x + n.w:
                s.line(gx, n.y, gx, n.y + n.h, "line_highlight", 1.0)
                gx += 32
            gy := n.y + 16
            while gy < n.y + n.h:
                s.line(n.x, gy, n.x + n.w, gy, "line_highlight", 1.0)
                gy += 32
            s.shadow(f[0], f[1] - f[4], f[2], f[3] + f[4])
        s.fill(f[0], f[1] - f[4], f[2], f[4], "menubar")
        s.fill(f[0], f[1], f[2], f[3], "bg")
        title := str(n.get("form_title", ""))
        if s.cell:
            s.text(f[0] + 1, f[1] - 1, _u.fit(s, title, f[2] - 2), "text")
        else:
            s.circle(f[0] + 16, f[1] - 15, 5, "#ff5f57")
            s.circle(f[0] + 32, f[1] - 15, 5, "#febc2e")
            s.circle(f[0] + 48, f[1] - 15, 5, "#28c840")
            tw := s.text_width(title, "normal")
            s.text(f[0] + (f[2] - tw) / 2, f[1] - f[4] + (f[4] - s.line_height("normal")) / 2, title, "muted")
        s.push_clip(f[0], f[1], f[2], f[3])
        app.paint_children(n)
        s.pop_clip()
        st := n.st
        hov := self._rect(app, _b.st_get(st, "hover", null))
        sel := self._rect(app, n.get("selected", null))
        if hov != null and not s.cell:
            s.stroke(hov[0], hov[1], hov[2], hov[3], "accent2", 0, 1.0)
        if sel != null:
            if s.cell:
                s.frame(sel[0], sel[1], sel[2], sel[3], "accent")
            else:
                s.stroke(sel[0] - 1, sel[1] - 1, sel[2] + 2, sel[3] + 2, "accent", 2, 2.0)
                for c in [[sel[0], sel[1]], [sel[0] + sel[2], sel[1]], [sel[0], sel[1] + sel[3]], [sel[0] + sel[2], sel[1] + sel[3]]]:
                    s.fill(c[0] - 3, c[1] - 3, 6, 6, "accent", 1)
                lab := str(n.get("selected_label", ""))
                if lab != "":
                    lw := s.text_width(lab, "normal") + 12
                    ly := sel[1] - 22 if sel[1] - 22 > f[1] else sel[1] + sel[3] + 2
                    s.fill(sel[0], ly, lw, 20, "accent", 4)
                    s.text(sel[0] + 6, ly + (20 - s.line_height("normal")) / 2, lab, "accent_text")
        # poignée de redimensionnement du formulaire
        if not s.cell:
            hx := f[0] + f[2]
            hy := f[1] + f[3]
            s.fill(hx - 10, hy - 10, 10, 10, "accent", 2)
            dim := str(n.get("form_width", 640)) + " × " + str(n.get("form_height", 420))
            s.text(hx - s.text_width(dim, "normal"), hy + 6, dim, "muted")

    func mouse(app, n, ev):
        st := n.st
        f := self._form(app, n)
        a := ev["action"]
        if a == "down" and not app.s.cell and ev["x"] >= f[0] + f[2] - 12 and ev["x"] <= f[0] + f[2] + 4 and ev["y"] >= f[1] + f[3] - 12 and ev["y"] <= f[1] + f[3] + 4:
            st["resize"] = [ev["x"], ev["y"], n.get("form_width", 640), n.get("form_height", 420)]
            return true
        if a == "drag" and _b.st_get(st, "resize", null) != null:
            r := st["resize"]
            w := _u.imax(160, r[2] + (ev["x"] - r[0]) * 2)
            h := _u.imax(120, r[3] + (ev["y"] - r[1]))
            app.call(n.get("on_resize", null), [to_int(w), to_int(h)])
            return true
        if a == "up":
            st["resize"] = null
            return true
        if a == "move":
            h := self._pick(app, n, ev["x"], ev["y"])
            old := _b.st_get(st, "hover", null)
            st["hover"] = h
            return h != old
        if a == "down":
            app.call(n.get("on_pick", null), [self._pick(app, n, ev["x"], ev["y"])])
            return true
        return false

    func key(app, n, ev):
        k := _b.key_of(ev)
        if k == "delete":
            app.call(n.get("on_delete", null), [])
            return true
        if k == "escape":
            app.call(n.get("on_pick", null), [null])
            return true
        return app.call(n.get("on_key", null), [k]) == true

func _slice_id(t):
    out := ""
    i := 3
    while i < len(t):
        out = out + str(t[i])
        i += 1
    return out
