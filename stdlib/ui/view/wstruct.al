# ALEX STANDARD LIBRARY — ui.view.wstruct (interne)
#
# Composants de structure : tabs, split, dialog, menu_bar et ses menus (menu_popup, sous-menus).

from core use len, type, to_int
from collections use append, contains_key
use string as _s
use ui.view.util as _u
use ui.view.wbase as _b
use ui.view.node as _n
from ui.view.wbase use Widget, Flex

# ---------------------------------------------------------------- tabs
class Tabs extends Widget:
    func init():
        super.init()
        self.stretch_w = true
        self.stretch_h = true
        self.grow = 1

    func focusable(app, n):
        return len(n.get("titles", [])) > 0

    func _sel(n):
        count := len(n.get("titles", []))
        sel := _b.controlled(n.st, "selected", n.get("selected", 0) if n.get("selected") != null else 0)
        return _u.clamp(sel, 0, _u.imax(0, count - 1))

    # Seule la page choisie fait partie de l'arbre (son état est gardé sous un chemin propre à la page).
    func children(app, n):
        if len(n.children) == 0:
            return []
        sel := self._sel(n)
        c := _n.coerce(n.children[sel])
        if c.id == null:
            c.id = "page" + str(sel)
        return [c]

    func _tab_w(app, n, title):
        return app.s.text_width(title, "bold") + 2 * app.s.tab_px

    func measure(app, n, max_w):
        s := app.s
        hw := 0
        for t in n.get("titles", []):
            hw += self._tab_w(app, n, t)
        w := hw
        h := s.tab_h
        for c in n.flow:
            m := app.measure(c, _u.imax(0, max_w - 2 * s.tab_pad))
            w = _u.imax(w, m[0] + 2 * s.tab_pad)
            h += m[1] + 2 * s.tab_pad
        return [w, h]

    func arrange(app, n):
        s := app.s
        for c in n.flow:
            app.arrange(c, n.x + s.tab_pad, n.y + s.tab_h + s.tab_pad, n.w - 2 * s.tab_pad, n.h - s.tab_h - 2 * s.tab_pad, n.clip)

    func _rects(app, n):
        out := []
        x := n.x
        for t in n.get("titles", []):
            w := self._tab_w(app, n, t)
            append(out, [x, n.y, w, app.s.tab_h - app.s.bw])
            x += w
        return out

    func paint(app, n):
        s := app.s
        sel := self._sel(n)
        focused := app.is_focused(n)
        titles := n.get("titles", [])
        s.fill(n.x, n.y, n.w, s.tab_h, "tabbar")
        i := 0
        for r in self._rects(app, n):
            s.tab(r[0], r[1], r[2], r[3], titles[i], i == sel, focused and i == sel, app.is_hovered(n) and _b.st_get(n.st, "hover_tab", -1) == i)
            i += 1
        s.hline(n.x, n.y + s.tab_h - s.bw, n.w, "border")
        app.paint_children(n)

    func _change(app, n, idx):
        if idx != self._sel(n):
            n.st["selected"] = idx
            app.call(n.get("on_change"), [idx])

    func key(app, n, ev):
        k := _b.key_of(ev)
        count := len(n.get("titles", []))
        sel := self._sel(n)
        if k == "ctrl+page_down" or k == "ctrl+tab":
            self._change(app, n, (sel + 1) % count)
            return true
        if k == "ctrl+page_up" or k == "ctrl+shift+tab":
            self._change(app, n, (sel - 1 + count) % count)
            return true
        if not app.is_focused(n):
            return false
        if k == "right" and sel + 1 < count:
            self._change(app, n, sel + 1)
            return true
        if k == "left" and sel > 0:
            self._change(app, n, sel - 1)
            return true
        if k == "home":
            self._change(app, n, 0)
            return true
        if k == "end":
            self._change(app, n, count - 1)
            return true
        if k == "down":
            app.move_focus(1)
            return true
        return false

    func _tab_at(app, n, x, y):
        i := 0
        for r in self._rects(app, n):
            if x >= r[0] and x < r[0] + r[2] and y >= r[1] and y < r[1] + r[3]:
                return i
            i += 1
        return -1

    func mouse(app, n, ev):
        a := ev["action"]
        i := self._tab_at(app, n, ev["x"], ev["y"])
        if a == "move":
            changed := i != _b.st_get(n.st, "hover_tab", -1)
            n.st["hover_tab"] = i
            return changed and not app.s.cell
        if a != "down" or i < 0:
            return false
        self._change(app, n, i)
        return true

    func text_of(n):
        return _s.join(" ", n.get("titles", []))

# ---------------------------------------------------------------- split
class Split extends Widget:
    func init():
        super.init()
        self.stretch_w = true
        self.stretch_h = true
        self.grow = 1

    func _vertical(n):
        return n.get("vertical", false)

    func _ratio(n):
        return _u.clamp(_b.controlled(n.st, "ratio", n.get("ratio", 0.5)), 0.05, 0.95)

    func measure(app, n, max_w):
        s := app.s
        if len(n.flow) < 2:
            return [0, 0]
        if self._vertical(n):
            a := app.measure(n.flow[0], max_w)
            b := app.measure(n.flow[1], max_w)
            return [_u.imax(a[0], b[0]), a[1] + b[1] + s.split_w]
        half := _u.imax(0, (max_w - s.split_w) // 2)
        a := app.measure(n.flow[0], half)
        b := app.measure(n.flow[1], half)
        return [a[0] + b[0] + s.split_w, _u.imax(a[1], b[1])]

    # Rectangle de la barre de séparation.
    func bar(app, n):
        s := app.s
        r := self._ratio(n)
        if self._vertical(n):
            first := to_int((n.h - s.split_w) * r)
            return [n.x, n.y + first, n.w, s.split_w]
        first := to_int((n.w - s.split_w) * r)
        return [n.x + first, n.y, s.split_w, n.h]

    func arrange(app, n):
        if len(n.flow) < 2:
            return null
        b := self.bar(app, n)
        if self._vertical(n):
            app.arrange(n.flow[0], n.x, n.y, n.w, b[1] - n.y, n.clip)
            app.arrange(n.flow[1], n.x, b[1] + b[3], n.w, n.y + n.h - b[1] - b[3], n.clip)
        else:
            app.arrange(n.flow[0], n.x, n.y, b[0] - n.x, n.h, n.clip)
            app.arrange(n.flow[1], b[0] + b[2], n.y, n.x + n.w - b[0] - b[2], n.h, n.clip)

    func paint(app, n):
        app.paint_children(n)
        b := self.bar(app, n)
        app.s.splitter(b[0], b[1], b[2], b[3], self._vertical(n), _b.st_get(n.st, "dragging", false) or app.is_hovered(n))

    func _set_ratio(app, n, r):
        r = _u.clamp(r, 0.05, 0.95)
        n.st["ratio"] = r

    # Ctrl+Maj+flèches (depuis l'une des deux zones) déplacent la séparation.
    func key(app, n, ev):
        k := _b.key_of(ev)
        r := self._ratio(n)
        if self._vertical(n):
            if k == "ctrl+shift+up":
                self._set_ratio(app, n, r - 0.05)
                return true
            if k == "ctrl+shift+down":
                self._set_ratio(app, n, r + 0.05)
                return true
            return false
        if k == "ctrl+shift+left":
            self._set_ratio(app, n, r - 0.05)
            return true
        if k == "ctrl+shift+right":
            self._set_ratio(app, n, r + 0.05)
            return true
        if k == "f6":
            # passer à l'autre zone
            f := app.focused()
            inside_first := f != null and app._is_inside(f, n.flow[0])
            target := n.flow[1] if inside_first else n.flow[0]
            for c in app.focus_scope():
                if app._is_inside(c, target):
                    app.set_focus(c)
                    return true
            return true
        return false

    func mouse(app, n, ev):
        a := ev["action"]
        b := self.bar(app, n)
        x := ev["x"]
        y := ev["y"]
        on_bar := x >= b[0] - 1 and x < b[0] + b[2] + 1 and y >= b[1] - 1 and y < b[1] + b[3] + 1
        if a == "down":
            if not on_bar:
                return false
            n.st["dragging"] = true
            return true
        if a == "drag" and _b.st_get(n.st, "dragging", false):
            s := app.s
            if self._vertical(n):
                self._set_ratio(app, n, (y - n.y - s.split_w / 2) / _u.imax(1, n.h - s.split_w))
            else:
                self._set_ratio(app, n, (x - n.x - s.split_w / 2) / _u.imax(1, n.w - s.split_w))
            return true
        if a == "up":
            n.st["dragging"] = false
            return true
        return false

# ---------------------------------------------------------------- dialog
class Dialog extends Flex:
    func init():
        super.init(false)

    # Contenu, puis la rangée de boutons.
    func children(app, n):
        out := [c for c in n.children]
        buttons := []
        i := 0
        for b in n.get("buttons", []):
            if type(b) == "list" or type(b) == "tuple":
                append(buttons, _n.Node("button", {"label": str(b[0]), "on_click": b[1], "primary": i == 0, "id": "bouton" + str(i)}))
            else:
                append(buttons, b)
            i += 1
        if len(buttons) > 0:
            append(out, _n.Node("row", {"gap": null, "padding": 0, "justify": "end", "id": "boutons", "cross": "center"}, buttons))
        return out

    func pad(app, n):
        s := app.s
        t := s.dialog_title if n.get("title") != null else 0
        return [s.bw + s.dialog_pad_x, s.bw + s.dialog_pad_y + t, s.bw + s.dialog_pad_x, s.bw + s.dialog_pad_y]

    func gap(app, n):
        return app.s.dialog_gap

    func measure(app, n, max_w):
        m := super.measure(app, n, max_w)
        if n.get("title") != null:
            m[0] = _u.imax(m[0], app.s.text_width(n.get("title"), "bold") + 6 * app.s.cw)
        return m

    func paint(app, n):
        s := app.s
        s.fill(n.x, n.y, n.w, n.h, "surface", s.radius)
        s.frame(n.x, n.y, n.w, n.h, "accent" if s.cell else "border", s.radius, false, n.get("title"))
        if n.get("title") != null and not s.cell:
            s.text(n.x + s.dialog_pad_x, n.y + s.dialog_pad_y, _u.fit(s, n.get("title"), n.w - 2 * s.dialog_pad_x), "text", "bold")
        app.paint_children(n)

    func text_of(n):
        return n.get("title")

# ---------------------------------------------------------------- barre de menus
func shortcut_label(sc):
    if sc == null:
        return ""
    parts := _s.split(sc, "+")
    out := []
    for p in parts:
        if len(p) == 1:
            append(out, _s.upper(p))
        elif p == "ctrl":
            append(out, "Ctrl")
        elif p == "alt":
            append(out, "Alt")
        elif p == "shift":
            append(out, "Maj")
        elif _s.starts_with(p, "f") and len(p) <= 3:
            append(out, _s.upper(p))
        else:
            append(out, _s.capitalize(p))
    return _s.join("+", out)

func _collect_shortcuts(app, items):
    for it in items:
        if _b.st_get(it, "items", null) != null:
            _collect_shortcuts(app, it["items"])
        elif _b.st_get(it, "shortcut", null) != null and _b.st_get(it, "enabled", true) != false:
            append(app.shortcuts, [it["shortcut"], it["on_select"]])

class MenuBar extends Widget:
    func init():
        super.init()
        self.stretch_w = true

    func prepared(app, n):
        app.menu_bar = n
        for m in n.get("menus", []):
            _collect_shortcuts(app, m["items"])

    func measure(app, n, max_w):
        s := app.s
        w := 0
        for m in n.get("menus", []):
            w += s.text_width(m["title"]) + 2 * s.menu_px
        return [w, s.menu_h]

    func _rects(app, n):
        s := app.s
        out := []
        x := n.x
        for m in n.get("menus", []):
            w := s.text_width(m["title"]) + 2 * s.menu_px
            append(out, [x, n.y, w, n.h])
            x += w
        return out

    func open_menu(app, n, idx):
        count := len(n.get("menus", []))
        if count == 0:
            return null
        n.st["open"] = (idx + count) % count

    func arrange(app, n):
        st := n.st
        idx := _b.st_get(st, "open", null)
        menus := n.get("menus", [])
        if idx == null or idx >= len(menus):
            return null
        rects := self._rects(app, n)
        count := len(menus)
        func close_all():
            st["closed_from"] = st["open"]
            st["open"] = null

        func nav(delta):
            st["open"] = (st["open"] + delta + count) % count

        popup := _n.Node("menu_popup", {"items": menus[idx]["items"], "level": 0, "on_close_all": close_all, "on_close": close_all, "on_nav": nav})
        app.add_overlay(n, popup, "below", rects[idx], false, close_all, n.path + "/menu" + str(idx))

    func paint(app, n):
        s := app.s
        s.fill(n.x, n.y, n.w, n.h, "menubar")
        open := _b.st_get(n.st, "open", null)
        hover := _b.st_get(n.st, "hover", -1)
        i := 0
        menus := n.get("menus", [])
        for r in self._rects(app, n):
            role := "menubar_text"
            if open == i:
                s.fill(r[0], r[1], r[2], r[3], "accent", 0 if s.cell else 4)
                role = "accent_text"
            elif hover == i and not s.cell and app.is_hovered(n):
                s.fill(r[0], r[1], r[2], r[3], "hover", 4)
            s.text(r[0] + s.menu_px, _b.text_y(app, r[1], r[3]), menus[i]["title"], role)
            i += 1

    func _at(app, n, x, y):
        i := 0
        for r in self._rects(app, n):
            if x >= r[0] and x < r[0] + r[2] and y >= r[1] and y < r[1] + r[3]:
                return i
            i += 1
        return -1

    func mouse(app, n, ev):
        a := ev["action"]
        i := self._at(app, n, ev["x"], ev["y"])
        if a == "move":
            old := _b.st_get(n.st, "hover", -1)
            n.st["hover"] = i
            open := _b.st_get(n.st, "open", null)
            if open != null and i >= 0 and i != open:
                n.st["open"] = i
                return true
            return old != i and not app.s.cell
        if a == "down":
            if i < 0:
                return false
            if _b.st_get(n.st, "open", null) == i:
                n.st["open"] = null
            else:
                n.st["open"] = i
            return true
        return false

    func after_dismiss(app, n, ev):
        i := self._at(app, n, ev["x"], ev["y"])
        if i >= 0 and i != _b.st_get(n.st, "closed_from", null):
            n.st["open"] = i
        return true

    func text_of(n):
        return _s.join(" ", [m["title"] for m in n.get("menus", [])])

# ---------------------------------------------------------------- menu ouvert (et sous-menus)
func _is_sep(it):
    return _b.st_get(it, "separator", false) == true

func _selectable(it):
    return not _is_sep(it) and _b.st_get(it, "enabled", true) != false

class MenuPopup extends Widget:
    func init():
        super.init()

    func focusable(app, n):
        return true

    func _items(n):
        return n.get("items", [])

    func _hi(n):
        items := self._items(n)
        if not contains_key(n.st, "hi"):
            n.st["hi"] = -1
            i := 0
            for it in items:
                if n.st["hi"] < 0 and _selectable(it):
                    n.st["hi"] = i
                i += 1
        return n.st["hi"]

    func _row_h(app, it):
        if _is_sep(it):
            return app.s.sep
        return app.s.rh

    func measure(app, n, max_w):
        s := app.s
        lw := 0
        sw := 0
        h := 0
        for it in self._items(n):
            h += self._row_h(app, it)
            if not _is_sep(it):
                lw = _u.imax(lw, s.text_width(it["label"]))
                sw = _u.imax(sw, s.text_width(shortcut_label(_b.st_get(it, "shortcut", null))))
        gw := s.glyph_width("check_mark")
        aw := s.glyph_width("arrow_right")
        w := s.bw + s.px + gw + s.cw + lw + (2 * s.gx + sw if sw > 0 else 0) + s.cw + aw + s.px + s.bw
        return [w, h + 2 * s.bw]

    func _rows(app, n):
        out := []
        y := n.y + app.s.bw
        for it in self._items(n):
            rh := self._row_h(app, it)
            append(out, [n.x + app.s.bw, y, n.w - 2 * app.s.bw, rh])
            y += rh
        return out

    func arrange(app, n):
        st := n.st
        sub := _b.st_get(st, "sub", null)
        items := self._items(n)
        if sub == null or sub >= len(items) or _b.st_get(items[sub], "items", null) == null:
            return null
        rows := self._rows(app, n)
        close_all := n.get("on_close_all")
        on_nav := n.get("on_nav")
        level := n.get("level", 0)

        func close_sub():
            st["sub"] = null

        popup := _n.Node("menu_popup", {"items": items[sub]["items"], "level": level + 1, "on_close_all": close_all, "on_close": close_sub, "on_nav": on_nav})
        app.add_overlay(n, popup, "right", rows[sub], false, close_sub, n.path + "/sous" + str(sub))

    func paint(app, n):
        s := app.s
        s.fill(n.x, n.y, n.w, n.h, "surface", s.radius)
        s.frame(n.x, n.y, n.w, n.h, "border", s.radius)
        items := self._items(n)
        hi := self._hi(n)
        gw := s.glyph_width("check_mark")
        aw := s.glyph_width("arrow_right")
        i := 0
        for r in self._rows(app, n):
            it := items[i]
            if _is_sep(it):
                s.hline(r[0] + s.px, r[1] + r[3] // 2, r[2] - 2 * s.px, "border")
                i += 1
                continue
            on := _selectable(it)
            role := "text" if on else "disabled"
            muted := "muted" if on else "disabled"
            if i == hi and on:
                s.fill(r[0], r[1], r[2], r[3], "accent", 0 if s.cell else 4)
                role = "accent_text"
                muted = "accent_text"
            ty := _b.text_y(app, r[1], r[3])
            x := r[0] + s.px
            if _b.st_get(it, "checked", null) == true:
                s.glyph(x, ty, "check_mark", role)
            x += gw + s.cw
            s.text(x, ty, _u.fit(s, it["label"], r[0] + r[2] - x - s.px - aw), role)
            if _b.st_get(it, "items", null) != null:
                s.glyph(r[0] + r[2] - s.px - aw, ty, "arrow_right", muted)
            else:
                sc := shortcut_label(_b.st_get(it, "shortcut", null))
                sx := r[0] + r[2] - s.px - aw - s.cw - s.text_width(sc)
                if sc != "" and sx > x + s.text_width(it["label"]) + s.cw:
                    s.text(sx, ty, sc, muted)
            i += 1

    func _move(n, step):
        items := self._items(n)
        count := len(items)
        if count == 0:
            return null
        hi := self._hi(n)
        k := 0
        i := hi
        while k < count:
            i = (i + step + count) % count
            if _selectable(items[i]):
                n.st["hi"] = i
                return null
            k += 1

    func _activate(app, n, i):
        items := self._items(n)
        if i < 0 or i >= len(items) or not _selectable(items[i]):
            return null
        it := items[i]
        if _b.st_get(it, "items", null) != null:
            n.st["sub"] = i
            return null
        app.call(n.get("on_close_all"), [])
        app.call(it["on_select"], [])

    func key(app, n, ev):
        k := _b.key_of(ev)
        items := self._items(n)
        hi := self._hi(n)
        level := n.get("level", 0)
        if k == "down":
            self._move(n, 1)
        elif k == "up":
            self._move(n, -1)
        elif k == "home":
            n.st["hi"] = -1
            self._move(n, 1)
        elif k == "end":
            n.st["hi"] = 0
            self._move(n, -1)
        elif k == "enter" or k == "space":
            self._activate(app, n, hi)
        elif k == "right":
            if hi >= 0 and _b.st_get(items[hi], "items", null) != null:
                n.st["sub"] = hi
            else:
                app.call(n.get("on_nav"), [1])
        elif k == "left":
            if level > 0:
                app.call(n.get("on_close"), [])
            else:
                app.call(n.get("on_nav"), [-1])
        elif k == "escape":
            app.call(n.get("on_close"), [])
        elif k == "tab" or k == "shift+tab" or k == "f10":
            app.call(n.get("on_close_all"), [])
        else:
            t := ev["text"] if ev["type"] == "key" else null
            if t != null and t != "":
                i := 0
                for it in items:
                    if _selectable(it) and _s.starts_with(_s.lower(it["label"]), _s.lower(t)):
                        n.st["hi"] = i
                        self._activate(app, n, i)
                        return true
                    i += 1
        return true

    func _row_at(app, n, y):
        i := 0
        for r in self._rows(app, n):
            if y >= r[1] and y < r[1] + r[3]:
                return i
            i += 1
        return -1

    func mouse(app, n, ev):
        a := ev["action"]
        i := self._row_at(app, n, ev["y"])
        items := self._items(n)
        if a == "move" or a == "drag":
            if i >= 0 and _selectable(items[i]):
                n.st["hi"] = i
                if _b.st_get(items[i], "items", null) != null:
                    n.st["sub"] = i
                else:
                    n.st["sub"] = null
            return true
        if a == "down":
            if i >= 0:
                n.st["hi"] = i
                self._activate(app, n, i)
            return true
        return a == "up"

    func text_of(n):
        return _s.join(" ", [it["label"] for it in self._items(n) if not _is_sep(it)])
