# ALEX STANDARD LIBRARY — mouse.pointer
#
# Pointer : suit le pointeur à partir des événements bruts (mouse_event.MouseEvent) et en déduit des gestes de
# haut niveau — clic, double clic, glisser (début / déplacement / fin, avec seuil), vitesse — ainsi que la zone
# survolée parmi des régions nommées.
#
#   use mouse.pointer as pt
#   p := pt.Pointer()
#   p.add_region("bouton_ok", 10, 10, 80, 30)
#   for ev in fenetre.poll_all():
#       for g in p.feed(mouse_event.from_window_event(ev)):     # gestes produits par cet événement
#           if g.kind == "click" and p.region_at(g.x, g.y) == "bouton_ok":
#               valider()
#           if g.kind == "drag":
#               deplacer(g.dx, g.dy)
#   print(p.x, p.y, p.is_down("left"), p.speed())
#
# Réglages : drag_threshold (pixels, 4), double_click_time (secondes, 0,4), double_click_distance (pixels, 4).

from core use len, type
from collections use append, contains_key, keys, remove
use math as _math
use mouse.mouse_event as _me

class Pointer:
    func init(drag_threshold=4, double_click_time=0.4, double_click_distance=4):
        self.x = 0
        self.y = 0
        self.inside = false
        self.drag_threshold = drag_threshold
        self.double_click_time = double_click_time
        self.double_click_distance = double_click_distance
        self._down = {}           # bouton -> [x, y, instant]
        self._dragging = null     # bouton en cours de glisser
        self._last_click = null   # [bouton, x, y, instant, nombre]
        self._samples = []        # [x, y, instant] récents (vitesse)
        self._regions = []        # [nom, x, y, l, h]
        self.events = 0

    func is_down(button="left"):
        return contains_key(self._down, button)

    func buttons():
        return [b for b in keys(self._down)]

    func dragging():
        return self._dragging != null

    # Vitesse instantanée (pixels / seconde) sur les derniers mouvements.
    func speed():
        n := len(self._samples)
        if n < 2:
            return 0.0
        a := self._samples[0]
        b := self._samples[n - 1]
        dt := b[2] - a[2]
        if dt <= 0:
            return 0.0
        return _math.sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1])) / dt

    func add_region(name, x, y, w, h):
        self._regions = [r for r in self._regions if r[0] != name]
        append(self._regions, [name, x, y, w, h])

    func remove_region(name):
        self._regions = [r for r in self._regions if r[0] != name]

    # Région (la dernière ajoutée qui contient le point) ; null si aucune.
    func region_at(x, y):
        k := len(self._regions) - 1
        while k >= 0:
            r := self._regions[k]
            if x >= r[1] and y >= r[2] and x < r[1] + r[3] and y < r[2] + r[4]:
                return r[0]
            k -= 1
        return null

    func hovered():
        if not self.inside:
            return null
        return self.region_at(self.x, self.y)

    func _gesture(kind, e, button, dx=0.0, dy=0.0):
        g := _me.MouseEvent(kind, self.x, self.y, button, e.mods, dx, dy, e.source, e.time)
        g.buttons = self.buttons()
        return g

    # Met à jour l'état ; renvoie la liste des gestes produits (l'événement lui-même en premier, enrichi des
    # boutons enfoncés).
    func feed(e):
        out := []
        if e == null:
            return out
        self.events += 1
        if e.kind == "relative":
            self.x += e.dx
            self.y += e.dy
        elif e.kind != "leave":
            self.x = e.x
            self.y = e.y
        self.inside = e.kind != "leave"
        e.buttons = self.buttons()
        append(out, e)
        if e.kind == "move" or e.kind == "relative":
            append(self._samples, [self.x, self.y, e.time])
            while len(self._samples) > 5:
                self._samples = [self._samples[k] for k in 1..len(self._samples)]
            for b in keys(self._down):
                d := self._down[b]
                if self._dragging == null and _dist(d[0], d[1], self.x, self.y) >= self.drag_threshold:
                    self._dragging = b
                    append(out, self._gesture("drag_start", e, b, self.x - d[0], self.y - d[1]))
            if self._dragging != null:
                d := self._down[self._dragging]
                append(out, self._gesture("drag", e, self._dragging, self.x - d[0], self.y - d[1]))
        elif e.kind == "down" and e.button != null:
            self._down[e.button] = [self.x, self.y, e.time]
            e.buttons = self.buttons()
        elif e.kind == "up" and e.button != null:
            if contains_key(self._down, e.button):
                d := self._down[e.button]
                remove(self._down, e.button)
                if self._dragging == e.button:
                    append(out, self._gesture("drag_end", e, e.button, self.x - d[0], self.y - d[1]))
                    self._dragging = null
                else:
                    count := 1
                    lc := self._last_click
                    if lc != null and lc[0] == e.button and e.time - lc[3] <= self.double_click_time and _dist(lc[1], lc[2], self.x, self.y) <= self.double_click_distance:
                        count = lc[4] + 1
                    self._last_click = [e.button, self.x, self.y, e.time, count]
                    c := self._gesture("click", e, e.button)
                    c.clicks = count
                    append(out, c)
                    if count == 2:
                        d2 := self._gesture("double_click", e, e.button)
                        d2.clicks = 2
                        append(out, d2)
        elif e.kind == "leave":
            if self._dragging != null:
                append(out, self._gesture("drag_end", e, self._dragging))
                self._dragging = null
            self._down = {}
        return out

func _dist(x1, y1, x2, y2):
    return _math.sqrt((x2 - x1) * (x2 - x1) + (y2 - y1) * (y2 - y1))
