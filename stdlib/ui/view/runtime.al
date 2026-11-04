# ALEX STANDARD LIBRARY — ui.view.runtime (interne)
#
# Boucle d'une application ui.view, commune au terminal et à la fenêtre : construit l'arbre (la vue), garde
# l'état de chaque composant sous son chemin, mesure et place (colonnes, lignes, flex), dessine sur la
# surface du rendu, gère le focus, les superpositions (listes déroulantes, menus, dialogues modaux) et
# route le clavier et la souris vers les composants.
#
# La surface (rendu) fournit : des métriques (cw, lh, px, py, gx, gy, sbw, cell...), la mesure du texte,
# des primitives de dessin (fill, frame, text, glyph, hline, vline, caret, clip, shadow, dim) et les
# événements (format de tui.input : key, mouse, paste, resize, close).

from core use len, type, to_int
from collections use append, contains_key, keys
use string as _s
use os as _os
use ui.view.node as _n
use ui.view.util as _u
use ui.view.widgets as _w

_current := [null]

# Application en cours (celle dont run() s'exécute), ou null.
func current():
    return _current[0]

func set_current(a):
    _current[0] = a

class App:
    func init(view, surface, on_key=null, on_tick=null, tick=null, quit_keys=null):
        self.view = view
        self.s = surface
        self.on_key = on_key
        self.on_tick = on_tick
        self.tick = tick
        self.quit_keys = quit_keys
        if quit_keys == null:
            self.quit_keys = ["ctrl+q"]
        self.states = {}
        self.nodes = {}
        self.placed = []
        self.overlays = []
        self.prev_overlay_keys = []
        self.focus_saved = {}
        self.focus = null
        self.focus_request = null
        self.hover = null
        self.capture = null
        self.shortcuts = []
        self.menu_bar = null
        self.root = null
        self.running = false
        self.frames = 0
        self.started = _os.monotonic_time()
        self.now = 0.0
        self.last_click = null
        self.clipboard = ""
        self.result = null
        self.pending = []

    # Touche à envoyer au composant qui a le focus, après l'événement en cours (menus Édition...).
    func post_key(name):
        append(self.pending, {"type": "key", "key": name, "text": name if len(name) == 1 else null, "ctrl": _s.starts_with(name, "ctrl+"), "alt": _s.contains(name, "alt+"), "shift": _s.contains(name, "shift+")})

    func _flush_pending():
        guard := 0
        while len(self.pending) > 0 and guard < 50:
            evs := self.pending
            self.pending = []
            for ev in evs:
                self.handle(ev)
            self.render()
            guard += 1

    func stop(value=null):
        self.running = false
        self.result = value

    # ------------------------------------------------------------ construction
    func widget(n):
        return _w.get(n.kind)

    func render():
        guard := 0
        while true:
            self._build()
            guard += 1
            if not self._ensure_visible() or guard >= 3:
                break
        self._paint()
        self.frames += 1

    func _build():
        self.now = _os.monotonic_time() - self.started
        self.s.refresh_metrics()
        prev_focus := self.focused()
        self.focus_id = prev_focus.id if prev_focus != null else null
        self.nodes = {}
        self.placed = []
        self.overlays = []
        self.shortcuts = []
        self.menu_bar = null
        root := self.view()
        if type(root) == "list":
            root = _n.Node("column", {"padding": 0}, root)
        root = _n.coerce(root)
        self.root = root
        self.prepare(root, "r", null, 0)
        size := self.s.size()
        self.measure(root, size[0])
        self.arrange(root, 0, 0, size[0], size[1], null)
        k := 0
        while k < len(self.overlays):
            self._place_overlay(self.overlays[k], k + 1, size)
            k += 1
        self._sync_focus()

    # Donne à n et à ses enfants actifs chemin, état et parent ; les dialogues deviennent des superpositions.
    func prepare(n, path, parent, layer):
        n.parent = parent
        n.path = path
        n.layer = layer
        if contains_key(self.nodes, path):
            k := 2
            while contains_key(self.nodes, path + "#" + str(k)):
                k += 1
            path = path + "#" + str(k)
            n.path = path
        self.nodes[path] = n
        st := null
        if contains_key(self.states, path):
            st = self.states[path]
            if st["__kind"] != n.kind:
                st = null
        if st == null:
            st = {"__kind": n.kind}
            self.states[path] = st
        n.st = st
        wd := self.widget(n)
        n.flow = []
        i := 0
        for c in _expand(wd.children(self, n), n.kind):
            if c.kind == "dialog":
                seg := c.id if c.id != null else "dialog" + str(i)
                self.add_overlay(null, c, "center", null, true, c.get("on_close"), path + "/" + str(seg))
                i += 1
                continue
            seg := str(c.id) if c.id != null else c.kind + str(i)
            self.prepare(c, path + "/" + seg, n, layer)
            append(n.flow, c)
            i += 1
        wd.prepared(self, n)

    # Superposition : node affiché au-dessus du reste. place : "center", "below" ou "right" (de anchor =
    # [x, y, w, h]). modal : le reste ne reçoit plus d'événements. on_dismiss() : Échap ou clic à côté.
    func add_overlay(owner, node, place, anchor, modal, on_dismiss, key, min_width=0):
        append(self.overlays, {"owner": owner, "node": node, "place": place, "anchor": anchor, "modal": modal, "on_dismiss": on_dismiss, "key": key, "min_width": min_width})

    func _place_overlay(ov, layer, size):
        node := _n.coerce(ov["node"])
        ov["node"] = node
        self.prepare(node, "#" + ov["key"], null, layer)
        sw := size[0]
        shgt := size[1]
        mw := sw
        if ov["place"] == "center":
            mw = _u.imax(1, sw - 2 * self.s.cw)
            if node.get("width") != null:
                mw = _u.imin(mw, node.get("width") * self.s.cw)
        m := self.measure(node, mw)
        w := _u.imin(_u.imax(m[0], ov["min_width"]), sw)
        if ov["place"] == "center" and node.get("width") != null:
            w = mw
            m = self.measure(node, w)
        h := _u.imin(m[1], shgt)
        x := 0
        y := 0
        a := ov["anchor"]
        if ov["place"] == "center":
            x = (sw - w) // 2
            y = (shgt - h) // 2
        elif ov["place"] == "below":
            x = a[0]
            y = a[1] + a[3]
            if y + h > shgt:
                if a[1] - h >= 0:
                    y = a[1] - h
                else:
                    y = _u.imax(0, shgt - h)
        else:
            x = a[0] + a[2]
            y = a[1]
            if x + w > sw:
                x = _u.imax(0, a[0] - w)
            if y + h > shgt:
                y = _u.imax(0, shgt - h)
        x = _u.clamp(x, 0, _u.imax(0, sw - w))
        ov["rect"] = [x, y, w, h]
        self.arrange(node, x, y, w, h, null)
        for c in node.flow:
            self._clip_tree(c, [x, y, w, h])

    # ------------------------------------------------------------ mesure et placement
    # Taille naturelle [largeur, hauteur] de n pour une largeur disponible max_w.
    func measure(n, max_w):
        fw := n.get("width")
        if fw != null:
            max_w = _u.imin(max_w, self.width_of(n, fw))
        size := self.widget(n).measure(self, n, max_w)
        w := size[0]
        h := size[1]
        if fw != null:
            w = self.width_of(n, fw)
        fh := n.get("height")
        if fh != null:
            h = self.height_of(n, fh)
        n.mw = w
        n.mh = h
        return [w, h]

    # Largeur (en unités de la surface) d'une largeur donnée en caractères.
    func width_of(n, chars):
        return self.widget(n).width_for(self, n, chars)

    func height_of(n, lines):
        return self.widget(n).height_for(self, n, lines)

    func arrange(n, x, y, w, h, clip):
        n.x = x
        n.y = y
        n.w = _u.imax(0, w)
        n.h = _u.imax(0, h)
        n.clip = clip
        append(self.placed, n)
        self.widget(n).arrange(self, n)

    func _clip_tree(n, rect):
        if n.clip == null:
            n.clip = rect
        else:
            n.clip = _intersect(n.clip, rect)
        for c in n.flow:
            self._clip_tree(c, rect)

    # Taille d'un enfant dans un conteneur : étiré sur l'axe transversal ou à sa taille naturelle.
    func stretch_w(n, parent_cross):
        a := n.get("align")
        if a != null:
            return a == "stretch"
        if n.get("width") != null:
            return false
        if parent_cross != null:
            return parent_cross == "stretch"
        return self.widget(n).wants_w(n)

    func stretch_h(n, parent_cross):
        a := n.get("align")
        if a != null:
            return a == "stretch"
        if n.get("height") != null:
            return false
        if parent_cross != null:
            return parent_cross == "stretch"
        return self.widget(n).wants_h(n)

    func grow(n):
        f := n.get("flex")
        if f != null and f != 0:
            return f
        if n.parent != null:
            pk := n.parent.kind
            if n.get("height") != null and pk != "row":
                return 0
            if n.get("width") != null and pk == "row":
                return 0
        return self.widget(n).grow

    # ------------------------------------------------------------ focus
    func focusable(n):
        return self.widget(n).focusable(self, n)

    func focus_scope():
        layer := self.active_layer()
        return [n for n in self.placed if n.layer == layer and n.w > 0 and n.h > 0 and self.focusable(n)]

    # Couche qui reçoit le clavier : la dernière superposition, sinon l'interface.
    func active_layer():
        return len(self.overlays)

    func focused():
        if self.focus == null or not contains_key(self.nodes, self.focus):
            return null
        return self.nodes[self.focus]

    func is_focused(n):
        return self.focus == n.path

    func is_hovered(n):
        return self.hover == n.path

    func set_focus(n):
        if n != null:
            self.focus = n.path

    func move_focus(step):
        scope := self.focus_scope()
        if len(scope) == 0:
            return
        idx := -1
        i := 0
        for n in scope:
            if n.path == self.focus:
                idx = i
            i += 1
        if idx < 0:
            self.focus = scope[0].path if step > 0 else scope[len(scope) - 1].path
        else:
            self.focus = scope[(idx + step + len(scope)) % len(scope)].path

    func _sync_focus():
        cur := [ov["key"] for ov in self.overlays]
        # superpositions disparues : rendre le focus d'avant (d'abord, pour qu'un menu remplacé par un autre
        # transmette le focus d'origine au suivant)
        for key in self.prev_overlay_keys:
            if _u.lindex(cur, key) < 0 and contains_key(self.focus_saved, key):
                f := self.focus_saved[key]
                if self.focus == null or not contains_key(self.nodes, self.focus) or _s.starts_with(self.focus, "#" + key):
                    self.focus = f
                self.focus_saved = _without(self.focus_saved, key)
        # superpositions apparues : mémoriser le focus, le donner à la nouvelle
        k := 0
        for ov in self.overlays:
            if _u.lindex(self.prev_overlay_keys, ov["key"]) < 0:
                self.focus_saved[ov["key"]] = self.focus
                first := self._first_focus_in(k + 1, ov)
                if first != null:
                    self.focus = first.path
            k += 1
        self.prev_overlay_keys = cur
        if self.focus_request != null:
            for n in self.placed:
                if n.id == self.focus_request and self.focusable(n):
                    self.focus = n.path
            self.focus_request = null
        scope := self.focus_scope()
        ok := false
        for n in scope:
            if n.path == self.focus:
                ok = true
        if not ok and self.focus_id != null:
            # le composant a changé de place dans l'arbre (nouveau conteneur autour) : le suivre par son id
            for n in scope:
                if n.id == self.focus_id and not ok:
                    self.focus = n.path
                    ok = true
        if not ok:
            self.focus = null
            for n in scope:
                if n.get("autofocus", false) and self.focus == null:
                    self.focus = n.path
            if self.focus == null and len(scope) > 0:
                self.focus = scope[0].path

    func _first_focus_in(layer, ov):
        want := ov["node"].get("focus_path")
        for n in self.placed:
            if n.layer == layer and self.focusable(n):
                if want == null or n.path == want:
                    return n
        for n in self.placed:
            if n.layer == layer and self.focusable(n):
                return n
        return null

    # Fait défiler les zones défilantes pour montrer le composant qui a le focus ; true s'il faut replacer.
    func _ensure_visible():
        n := self.focused()
        if n == null:
            return false
        p := n.parent
        changed := false
        while p != null:
            if p.kind == "scroll":
                if self.widget(p).reveal(self, p, n):
                    changed = true
            p = p.parent
        return changed

    # ------------------------------------------------------------ dessin
    func _paint():
        s := self.s
        s.begin()
        size := s.size()
        s.fill(0, 0, size[0], size[1], "bg")
        self.paint(self.root)
        for ov in self.overlays:
            r := ov["rect"]
            if ov["modal"]:
                s.dim()
            s.shadow(r[0], r[1], r[2], r[3])
            self.paint(ov["node"])
        s.end()

    func paint(n):
        if n.w <= 0 or n.h <= 0:
            return null
        c := n.clip
        if c != null:
            if n.x >= c[0] + c[2] or n.y >= c[1] + c[3] or n.x + n.w <= c[0] or n.y + n.h <= c[1]:
                return null
            if n.x < c[0] or n.y < c[1] or n.x + n.w > c[0] + c[2] or n.y + n.h > c[1] + c[3]:
                self.s.push_clip(c[0], c[1], c[2], c[3])
                self.widget(n).paint(self, n)
                self.s.pop_clip()
                return null
        self.widget(n).paint(self, n)

    func paint_children(n):
        for c in n.flow:
            self.paint(c)

    # ------------------------------------------------------------ événements
    # Traite un événement ; true si l'affichage doit être refait.
    func handle(ev):
        t := ev["type"]
        if t == "resize":
            return true
        if t == "close" or t == "eof":
            self.stop()
            return true
        if t == "key" or t == "paste":
            self._key(ev)
            return true
        if t == "mouse":
            return self._mouse(ev)
        return false

    func _key(ev):
        key := "paste"
        if ev["type"] == "key":
            key = ev["key"]
        n := self.focused()
        p := n
        while p != null:
            if self.widget(p).key(self, p, ev):
                return true
            p = p.parent
        if key == "tab":
            self.move_focus(1)
            return true
        if key == "shift+tab":
            self.move_focus(-1)
            return true
        if key == "escape" and len(self.overlays) > 0:
            self.dismiss_top()
            return true
        modal := false
        for ov in self.overlays:
            if ov["modal"]:
                modal = true
        if modal:
            # un dialogue modal ouvert : ni raccourcis, ni menus, ni on_key
            if _u.lindex(self.quit_keys, key) >= 0:
                self.stop()
                return true
            return false
        for sc in self.shortcuts:
            if sc[0] == key:
                self.call(sc[1], [])
                return true
        if key == "f10" and self.menu_bar != null:
            self.widget(self.menu_bar).open_menu(self, self.menu_bar, 0)
            return true
        if self.on_key != null:
            if self.call(self.on_key, [key, ev]) == true:
                return true
        if n != null and self.widget(n).arrows_move_focus:
            if key == "down" or key == "right":
                self.move_focus(1)
                return true
            if key == "up" or key == "left":
                self.move_focus(-1)
                return true
        if _u.lindex(self.quit_keys, key) >= 0:
            self.stop()
            return true
        return false

    func dismiss_top():
        if len(self.overlays) == 0:
            return null
        ov := self.overlays[len(self.overlays) - 1]
        self.call(ov["on_dismiss"], [])

    # Nœud le plus haut sous (x, y) dans les couches >= min_layer, ou null.
    func hit(x, y, min_layer=0):
        k := len(self.placed) - 1
        best := null
        while k >= 0:
            n := self.placed[k]
            if n.layer >= min_layer and n.contains(x, y):
                if best == null or n.layer > best.layer:
                    best = n
                    if n.layer == len(self.overlays):
                        return n
            k -= 1
        return best

    func _mouse(ev):
        x := ev["x"]
        y := ev["y"]
        action := ev["action"]
        if (action == "drag" or action == "up") and self.capture != null:
            c := self.capture
            if action == "up":
                self.capture = null
            if contains_key(self.nodes, c):
                self.widget(self.nodes[c]).mouse(self, self.nodes[c], ev)
            return true
        target := self.hit(x, y)
        # Un conteneur peut intercepter la souris avant ses enfants (surface du Designer : les composants
        # affichés se sélectionnent au lieu de réagir).
        inter := target
        while inter != null and not self.widget(inter).intercepts(inter):
            inter = inter.parent
        if inter != null and action != "wheel":
            old := self.hover
            self.hover = inter.path
            if action == "down" and self.focusable(inter):
                self.focus = inter.path
            r := self.widget(inter).mouse(self, inter, ev)
            if action == "down" and r:
                self.capture = inter.path
            return r or old != self.hover
        if action == "move" or action == "drag":
            old := self.hover
            self.hover = target.path if target != null else null
            changed := old != self.hover
            p := target
            while p != null:
                if self.widget(p).mouse(self, p, ev):
                    return true
                p = p.parent
            return changed
        if action == "wheel":
            p := target
            while p != null:
                if self.widget(p).wheel(self, p, ev):
                    return true
                p = p.parent
            return false
        if action != "down":
            return false
        top := len(self.overlays)
        if top > 0 and (target == null or target.layer < top):
            ov := self.overlays[top - 1]
            if ov["modal"]:
                return false
            # clic à côté de menus ou d'une liste déroulante : les fermer (jusqu'à la couche cliquée)
            lowest := target.layer if target != null else 0
            owner := null
            k := top - 1
            while k >= lowest:
                o := self.overlays[k]
                if o["modal"]:
                    break
                owner = o["owner"]
                self.call(o["on_dismiss"], [])
                k -= 1
            if target == null:
                return true
            if owner != null and self._is_inside(target, owner):
                # le propriétaire (barre de menus...) peut réagir au clic qui a fermé sa superposition
                self.widget(owner).after_dismiss(self, owner, ev)
                return true
        if target == null:
            return true
        f := target
        while f != null and not self.focusable(f):
            f = f.parent
        if f != null:
            self.focus = f.path
        now := _os.monotonic_time()
        clicks := 1
        lc := self.last_click
        if lc != null and lc[0] == target.path and now - lc[1] < 0.45:
            clicks = lc[2] + 1
        self.last_click = [target.path, now, clicks]
        ev["clicks"] = clicks
        p := target
        while p != null:
            if self.widget(p).mouse(self, p, ev):
                self.capture = p.path
                return true
            p = p.parent
        return true

    func _is_inside(n, ancestor):
        p := n
        while p != null:
            if p.path == ancestor.path:
                return true
            p = p.parent
        return false

    # ------------------------------------------------------------ services pour les composants
    func call(f, args):
        return _u.call(f, args)

    func clipboard_get():
        v := self.s.clipboard_get()
        if v == null:
            return self.clipboard
        return v

    func clipboard_set(text):
        self.clipboard = text
        self.s.clipboard_set(text)

    # Premier composant affiché dont le texte (libellé, contenu, titre) contient text ; null sinon.
    func find(text):
        k := len(self.placed) - 1
        best := null
        for n in self.placed:
            t := self.widget(n).text_of(n)
            if t != null and _s.contains(t, text) and (best == null or n.layer >= best.layer):
                if best == null or n.layer > best.layer:
                    best = n
        return best

    # ------------------------------------------------------------ boucle
    func run():
        self.running = true
        previous := current()
        set_current(self)
        self.s.start()
        try:
            self.render()
            next_tick := null
            if self.tick != null:
                next_tick = _os.monotonic_time() + self.tick
            while self.running:
                wait := null
                if next_tick != null:
                    wait = _u.imax(0, next_tick - _os.monotonic_time())
                ev := self.s.next_event(wait)
                redraw := false
                if ev != null:
                    redraw = self.handle(ev)
                    count := 0
                    while self.running and count < 200:
                        ev2 := self.s.next_event(0)
                        if ev2 == null:
                            break
                        if self.handle(ev2):
                            redraw = true
                        count += 1
                if next_tick != null and _os.monotonic_time() >= next_tick:
                    next_tick = _os.monotonic_time() + self.tick
                    self.now = _os.monotonic_time() - self.started
                    if self.call(self.on_tick, [self.now]) != false:
                        redraw = true
                if redraw and self.running:
                    self.render()
                if self.running and len(self.pending) > 0:
                    self._flush_pending()
        finally:
            self.s.stop()
            set_current(previous)
        return self.result

    # Pour les tests : traite les événements en attente sur la surface et redessine.
    func step():
        set_current(self)
        done := 0
        while done < 10000:
            ev := self.s.next_event(0)
            if ev == null or ev["type"] == "eof":
                break
            self.handle(ev)
            done += 1
        self.render()
        self._flush_pending()
        return done

# Enfants d'un conteneur : les list imbriquées sont aplaties, null et les booléens (cond and v.text(...))
# ignorés, les textes et nombres deviennent des text().
func _expand(children, kind):
    out := []
    _expand_into(children, kind, out)
    return out

func _expand_into(children, kind, out):
    for c in children:
        t := type(c)
        if c == null or t == "bool":
            continue
        if t == "list" or t == "tuple":
            _expand_into(c, kind, out)
            continue
        if t == "str" or t == "int" or t == "float":
            append(out, _n.coerce(c))
            continue
        if t != "instance":
            raise("TypeError", "ui.view : enfant invalide de type '" + t + "' dans " + str(kind) + " (un composant, un texte ou une list est attendu)")
        append(out, c)

func _intersect(a, b):
    x0 := _u.imax(a[0], b[0])
    y0 := _u.imax(a[1], b[1])
    x1 := _u.imin(a[0] + a[2], b[0] + b[2])
    y1 := _u.imin(a[1] + a[3], b[1] + b[3])
    return [x0, y0, _u.imax(0, x1 - x0), _u.imax(0, y1 - y0)]

func _without(d, key):
    out := {}
    for k in keys(d):
        if k != key:
            out[k] = d[k]
    return out
