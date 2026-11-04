# ALEX STANDARD LIBRARY — ui.view.wbasic (interne)
#
# Composants de base : text, button, separator, spacer, checkbox, radio, progress, panel, scroll.

from core use len, type, to_int
from collections use append, contains_key
use string as _s
use ui.view.util as _u
use ui.view.wbase as _b
from ui.view.wbase use Widget, Flex

# ---------------------------------------------------------------- text
class Text extends Widget:
    func init():
        super.init()

    func wants_w(n):
        return n.get("wrap", false) or n.get("text_align", "left") != "left"

    func _lines(app, n, w):
        content := n.get("content", "")
        font := _b.text_font(n.get("style"))
        if n.get("wrap", false):
            return _u.wrap(app.s, content, w)
        return _u.split_lines(content)

    func measure(app, n, max_w):
        font := _b.text_font(n.get("style"))
        lines := []
        if n.get("wrap", false):
            lines = _u.wrap(app.s, n.get("content", ""), max_w)
        else:
            lines = _u.split_lines(n.get("content", ""))
        w := 0
        for l in lines:
            w = _u.imax(w, app.s.text_width(l, font))
        return [_u.imin(w, max_w) if n.get("wrap", false) else w, len(lines) * app.s.line_height(font)]

    func paint(app, n):
        s := app.s
        style := n.get("style")
        font := _b.text_font(style)
        role := _b.text_role(style)
        lh := s.line_height(font)
        lines := []
        if n.get("wrap", false):
            lines = _u.wrap(s, n.get("content", ""), n.w)
        else:
            lines = _u.split_lines(n.get("content", ""))
        y := n.y
        align := n.get("text_align", "left")
        for l in lines:
            if y + lh > n.y + n.h:
                break
            shown := _u.fit(s, l, n.w) if s.text_width(l, font) > n.w else l
            tw := s.text_width(shown, font)
            x := n.x
            if align == "center":
                x = n.x + (n.w - tw) // 2
            elif align == "right":
                x = n.x + n.w - tw
            s.text(x, y, shown, role, font)
            y += lh

    func text_of(n):
        return n.get("content", "")

# ---------------------------------------------------------------- button
class Button extends Widget:
    func init():
        super.init()
        self.arrows_move_focus = true

    func focusable(app, n):
        return _b.enabled(n)

    func width_for(app, n, chars):
        return chars * app.s.cw + 2 * app.s.px + (2 if app.s.cell else 0)

    func measure(app, n, max_w):
        s := app.s
        return [s.text_width(n.get("label", ""), "bold") + 2 * s.px + (2 if s.cell else 0), s.ch]

    func paint(app, n):
        s := app.s
        focused := app.is_focused(n)
        on := _b.enabled(n)
        primary := n.get("primary", false)
        pressed := _b.st_get(n.st, "pressed", false)
        label := n.get("label", "")
        fg := "text"
        if s.cell:
            bg := "button_primary" if primary else "button"
            if focused:
                bg = "accent"
                fg = "accent_text"
            elif primary:
                fg = "selection_text"
            if pressed:
                bg = "selection"
                fg = "selection_text"
            if not on:
                bg = "button"
                fg = "disabled"
            s.fill(n.x, n.y, n.w, n.h, bg)
            ty := _b.text_y(app, n.y, n.h)
            s.text(n.x, ty, "[", fg, "bold")
            s.text(n.x + n.w - 1, ty, "]", fg, "bold")
            shown := _u.fit(s, label, n.w - 2 - 2 * s.px)
            s.text(n.x + (n.w - s.text_width(shown, "bold")) // 2, ty, shown, fg, "bold")
            return null
        bg := "button"
        if primary:
            bg = "accent"
            fg = "accent_text"
        if app.is_hovered(n) and on:
            bg = "accent_hover" if primary else "hover"
        if pressed:
            bg = "accent_pressed" if primary else "selection"
        if not on:
            bg = "button"
            fg = "disabled"
        s.fill(n.x, n.y, n.w, n.h, bg, s.radius)
        if focused:
            s.focus_ring(n.x, n.y, n.w, n.h)
        elif not primary:
            s.frame(n.x, n.y, n.w, n.h, "border", s.radius)
        shown := _u.fit(s, label, n.w - 2 * s.px)
        s.text(n.x + (n.w - s.text_width(shown, "bold")) // 2, _b.text_y(app, n.y, n.h, "bold"), shown, fg, "bold")

    func key(app, n, ev):
        k := _b.key_of(ev)
        if (k == "enter" or k == "space") and _b.enabled(n):
            app.call(n.get("on_click"), [])
            return true
        return false

    func mouse(app, n, ev):
        if not _b.enabled(n):
            return false
        a := ev["action"]
        inside := n.contains(ev["x"], ev["y"])
        if a == "down":
            n.st["pressed"] = true
            return true
        if a == "drag":
            n.st["pressed"] = inside
            return true
        if a == "up":
            was := _b.st_get(n.st, "pressed", false)
            n.st["pressed"] = false
            if was and inside:
                app.call(n.get("on_click"), [])
            return true
        return false

    func text_of(n):
        return n.get("label", "")

# ---------------------------------------------------------------- separator, spacer
class Separator extends Widget:
    func init():
        super.init()

    func _vertical(n):
        return n.parent != null and n.parent.kind == "row"

    func wants_w(n):
        return not self._vertical(n)

    func wants_h(n):
        return self._vertical(n)

    func measure(app, n, max_w):
        if self._vertical(n):
            return [app.s.sep, app.s.lh]
        return [app.s.cw, app.s.sep]

    func paint(app, n):
        if self._vertical(n):
            app.s.vline(n.x + n.w // 2, n.y, n.h, "border")
        else:
            app.s.hline(n.x, n.y + n.h // 2, n.w, "border")

class Spacer extends Widget:
    func init():
        super.init()

    func measure(app, n, max_w):
        size := n.get("size", 0)
        if n.parent != null and n.parent.kind == "row":
            return [size * app.s.ux, 0]
        return [0, size * app.s.uy]

# ---------------------------------------------------------------- checkbox
class Checkbox extends Widget:
    func init():
        super.init()
        self.arrows_move_focus = true

    func focusable(app, n):
        return _b.enabled(n)

    func measure(app, n, max_w):
        s := app.s
        return [s.glyph_width("check_on") + s.cw + s.text_width(n.get("label", "")), s.rh]

    func paint(app, n):
        s := app.s
        checked := _b.controlled(n.st, "checked", n.get("checked", false) == true)
        on := _b.enabled(n)
        focused := app.is_focused(n)
        gw := s.glyph_width("check_on")
        ty := _b.text_y(app, n.y, n.h)
        if focused:
            s.focus_ring(n.x, n.y, n.w, n.h)
        role := "accent" if checked else "muted"
        if not on:
            role = "disabled"
        s.glyph(n.x, ty, "check_on" if checked else "check_off", role)
        s.text(n.x + gw + s.cw, ty, _u.fit(s, n.get("label", ""), n.w - gw - s.cw), "text" if on else "disabled")

    func _toggle(app, n):
        checked := _b.controlled(n.st, "checked", n.get("checked", false) == true)
        n.st["checked"] = not checked
        app.call(n.get("on_change"), [not checked])

    func key(app, n, ev):
        k := _b.key_of(ev)
        if (k == "space" or k == "enter") and _b.enabled(n):
            self._toggle(app, n)
            return true
        return false

    func mouse(app, n, ev):
        if ev["action"] == "down" and _b.enabled(n):
            self._toggle(app, n)
            return true
        return false

    func text_of(n):
        return n.get("label", "")

# ---------------------------------------------------------------- radio
class Radio extends Widget:
    func init():
        super.init()

    func focusable(app, n):
        return _b.enabled(n) and len(n.get("options", [])) > 0

    func _item_w(app, n, label):
        s := app.s
        return s.glyph_width("radio_on") + s.cw + s.text_width(label)

    func measure(app, n, max_w):
        s := app.s
        opts := n.get("options", [])
        if n.get("horizontal", false):
            w := 0
            i := 0
            for o in opts:
                w += self._item_w(app, n, o) + (2 * s.gx if i > 0 else 0)
                i += 1
            return [w, s.rh]
        w := 0
        for o in opts:
            w = _u.imax(w, self._item_w(app, n, o))
        return [w, len(opts) * s.rh]

    # Rectangles [x, y, w, h] des options.
    func _rects(app, n):
        s := app.s
        out := []
        x := n.x
        y := n.y
        for o in n.get("options", []):
            w := self._item_w(app, n, o)
            if n.get("horizontal", false):
                append(out, [x, y, w, s.rh])
                x += w + 2 * s.gx
            else:
                append(out, [x, y, _u.imax(w, n.w), s.rh])
                y += s.rh
        return out

    func paint(app, n):
        s := app.s
        sel := _b.controlled(n.st, "selected", n.get("selected", 0))
        focused := app.is_focused(n)
        on := _b.enabled(n)
        opts := n.get("options", [])
        rects := self._rects(app, n)
        i := 0
        for r in rects:
            ty := _b.text_y(app, r[1], r[3])
            if focused and i == sel:
                s.focus_ring(r[0], r[1], r[2], r[3])
            role := "accent" if i == sel else "muted"
            if not on:
                role = "disabled"
            s.glyph(r[0], ty, "radio_on" if i == sel else "radio_off", role)
            gw := s.glyph_width("radio_on")
            s.text(r[0] + gw + s.cw, ty, opts[i], "text" if on else "disabled")
            i += 1

    func _choose(app, n, idx):
        sel := _b.controlled(n.st, "selected", n.get("selected", 0))
        if idx != sel:
            n.st["selected"] = idx
            app.call(n.get("on_change"), [idx])

    func key(app, n, ev):
        if not _b.enabled(n):
            return false
        k := _b.key_of(ev)
        count := len(n.get("options", []))
        sel := _b.controlled(n.st, "selected", n.get("selected", 0))
        horiz := n.get("horizontal", false)
        nxt := null
        if k == "down" or (horiz and k == "right"):
            if not horiz and sel == count - 1:
                return false
            nxt = (sel + 1) % count
        elif k == "up" or (horiz and k == "left"):
            if not horiz and sel <= 0:
                return false
            nxt = (sel - 1 + count) % count
        elif k == "home":
            nxt = 0
        elif k == "end":
            nxt = count - 1
        if nxt == null:
            return false
        self._choose(app, n, nxt)
        return true

    func mouse(app, n, ev):
        if ev["action"] != "down" or not _b.enabled(n):
            return false
        i := 0
        for r in self._rects(app, n):
            if ev["x"] >= r[0] and ev["x"] < r[0] + r[2] and ev["y"] >= r[1] and ev["y"] < r[1] + r[3]:
                self._choose(app, n, i)
            i += 1
        return true

    func text_of(n):
        return _s.join(" ", n.get("options", []))

# ---------------------------------------------------------------- progress
class Progress extends Widget:
    func init():
        super.init()
        self.stretch_w = true

    func _label(n):
        lab := n.get("label")
        if lab != null:
            return str(lab)
        v := _u.clamp(n.get("value", 0), 0, 1)
        return str(to_int(v * 100 + 0.5)) + " %"

    func measure(app, n, max_w):
        s := app.s
        return [20 * s.cw + s.gx + s.text_width(self._label(n)), s.rh]

    func paint(app, n):
        s := app.s
        lab := self._label(n)
        lw := s.text_width(lab)
        bw := _u.imax(0, n.w - lw - s.gx)
        v := _u.clamp(n.get("value", 0), 0, 1)
        s.bar(n.x, n.y, bw, n.h, v)
        s.text(n.x + bw + s.gx, _b.text_y(app, n.y, n.h), lab, "muted")

    func text_of(n):
        return self._label(n)

# ---------------------------------------------------------------- panel
class Panel extends Flex:
    func init():
        super.init(false)

    func pad(app, n):
        s := app.s
        p := n.get("padding")
        ex := s.pad_x
        ey := s.pad_y
        if p != null:
            ex = p * s.ux
            ey = p * s.uy
        border := n.get("border", true)
        b := s.bw if border else 0
        t := 0
        if n.get("title") != null:
            t = s.panel_title if (border or not s.cell) else s.lh
        return [b + ex, b + ey + t, b + ex, b + ey]

    func measure(app, n, max_w):
        m := super.measure(app, n, max_w)
        if n.get("title") != null:
            m[0] = _u.imax(m[0], app.s.text_width(n.get("title"), "bold") + 4 * app.s.cw)
        return m

    func paint(app, n):
        s := app.s
        border := n.get("border", true)
        title := n.get("title")
        if border:
            s.fill(n.x, n.y, n.w, n.h, "surface", s.radius)
            s.frame(n.x, n.y, n.w, n.h, "border", s.radius, false, title)
        if title != null and (not s.cell or not border):
            b := s.bw if border else 0
            px := s.pad_x if n.get("padding") == null else n.get("padding") * s.ux
            py := s.pad_y if n.get("padding") == null else n.get("padding") * s.uy
            s.frame_title(n.x + b + px, n.y + b + py, n.w - 2 * (b + px), title)
        app.paint_children(n)

    func text_of(n):
        return n.get("title")

# ---------------------------------------------------------------- scroll
class Scroll extends Widget:
    func init():
        super.init()
        self.stretch_w = true
        self.stretch_h = true
        self.grow = 1

    func measure(app, n, max_w):
        s := app.s
        inner := _u.imax(0, max_w - s.sbw)
        w := 0
        h := 0
        i := 0
        for c in n.flow:
            m := app.measure(c, inner)
            w = _u.imax(w, m[0])
            h += m[1] + (s.gy if i > 0 else 0)
            i += 1
        n.st["content"] = h
        return [w + s.sbw, h]

    func arrange(app, n):
        s := app.s
        content := _b.st_get(n.st, "content", 0)
        vh := n.h
        off := _u.clamp(_b.st_get(n.st, "offset", 0), 0, _u.imax(0, content - vh))
        n.st["offset"] = off
        n.st["viewport"] = vh
        vw := _u.imax(0, n.w - s.sbw)
        clip := [n.x, n.y, vw, vh]
        if n.clip != null:
            clip = _intersect(n.clip, clip)
        _b.place_flex(app, n, n.flow, n.x, n.y - off, vw, _u.imax(content, vh), false, s.gy, null, "start", clip)

    func paint(app, n):
        s := app.s
        vw := _u.imax(0, n.w - s.sbw)
        s.push_clip(n.x, n.y, vw, n.h)
        app.paint_children(n)
        s.pop_clip()
        content := _b.st_get(n.st, "content", 0)
        if content > n.h:
            s.scrollbar(n.x + n.w - s.sbw, n.y, n.h, _b.st_get(n.st, "offset", 0) / content, n.h / content)

    func _scroll_to(n, off):
        content := _b.st_get(n.st, "content", 0)
        n.st["offset"] = _u.clamp(off, 0, _u.imax(0, content - n.h))

    func reveal(app, n, child):
        off := _b.st_get(n.st, "offset", 0)
        if child.y < n.y:
            self._scroll_to(n, off - (n.y - child.y))
        elif child.y + child.h > n.y + n.h:
            self._scroll_to(n, off + (child.y + child.h - n.y - n.h))
        return _b.st_get(n.st, "offset", 0) != off

    func wheel(app, n, ev):
        dy := ev["dy"]
        if dy == 0:
            return false
        before := _b.st_get(n.st, "offset", 0)
        self._scroll_to(n, before - dy * 3 * app.s.lh)
        return _b.st_get(n.st, "offset", 0) != before

    func key(app, n, ev):
        k := _b.key_of(ev)
        off := _b.st_get(n.st, "offset", 0)
        if k == "page_down":
            self._scroll_to(n, off + n.h - app.s.lh)
        elif k == "page_up":
            self._scroll_to(n, off - n.h + app.s.lh)
        elif k == "ctrl+home":
            self._scroll_to(n, 0)
        elif k == "ctrl+end":
            self._scroll_to(n, 1000000000)
        else:
            return false
        return true

    func mouse(app, n, ev):
        s := app.s
        a := ev["action"]
        content := _b.st_get(n.st, "content", 0)
        if content <= n.h:
            return false
        if a == "down" and ev["x"] < n.x + n.w - s.sbw:
            return false
        if a == "down" or a == "drag":
            frac := (ev["y"] - n.y) / _u.imax(1, n.h)
            self._scroll_to(n, to_int(frac * content - n.h / 2))
            return true
        return a == "up"

func _intersect(a, b):
    x0 := _u.imax(a[0], b[0])
    y0 := _u.imax(a[1], b[1])
    x1 := _u.imin(a[0] + a[2], b[0] + b[2])
    y1 := _u.imin(a[1] + a[3], b[1] + b[3])
    return [x0, y0, _u.imax(0, x1 - x0), _u.imax(0, y1 - y0)]
