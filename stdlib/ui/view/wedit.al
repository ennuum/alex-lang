# ALEX STANDARD LIBRARY — ui.view.wedit (interne)
#
# Composants de saisie : input, textarea, select (et sa liste ouverte, popup_list), slider, spinbox.

from core use len, type, to_int, to_float
from collections use append, contains_key
use string as _s
use ui.view.util as _u
use ui.view.edit as _e
use ui.view.wbase as _b
use ui.view.node as _n
from ui.view.wbase use Widget

func _sl(t, a, b=null):
    if b == null:
        return _s.slice(t, a)
    return _s.slice(t, a, b)

# Texte affiché : le texte, ou des points pour un mot de passe.
func _shown(n, value):
    if n.get("password", false):
        return _s.repeat("•", len(value))
    return value

# ---------------------------------------------------------------- input
class Input extends Widget:
    func init():
        super.init()
        self.stretch_w = true

    func focusable(app, n):
        return _b.enabled(n)

    func width_for(app, n, chars):
        return chars * app.s.cw + 2 * app.s.px

    func measure(app, n, max_w):
        return [self.width_for(app, n, 20), app.s.ch]

    func _state(n):
        value := _b.controlled(n.st, "value", str(n.get("value", "")))
        if not contains_key(n.st, "cursor") or _b.st_get(n.st, "__cur_for", null) != value:
            if not contains_key(n.st, "cursor") or n.st["cursor"] > len(value):
                n.st["cursor"] = len(value)
            n.st["__cur_for"] = value
        n.st["cursor"] = _u.clamp(n.st["cursor"], 0, len(value))
        return n.st

    # Premier caractère affiché pour que le curseur reste visible dans la largeur w.
    func _left(app, shown, cur, w):
        st_left := 0
        s := app.s
        if cur * s.cw <= w and s.cell:
            return 0
        left := 0
        while left < cur and s.text_width(_sl(shown, left, cur)) > w - s.cw:
            left += 1
        return left

    func paint(app, n):
        s := app.s
        st := self._state(n)
        focused := app.is_focused(n)
        _b.field_box(app, n, focused)
        value := st["value"]
        shown := _shown(n, value)
        x0 := n.x + s.px
        w0 := _u.imax(0, n.w - 2 * s.px)
        ty := _b.text_y(app, n.y, n.h)
        cur := st["cursor"]
        left := _b.st_get(st, "left", 0)
        if cur < left:
            left = cur
        if s.text_width(_sl(shown, left, cur)) > w0 - s.cw:
            left = self._left(app, shown, cur, w0)
        st["left"] = left
        s.push_clip(x0, n.y, w0, n.h)
        if value == "" and n.get("placeholder", "") != "":
            s.text(x0, ty, _u.fit(s, n.get("placeholder"), w0), "muted")
        else:
            visible := _sl(shown, left)
            k := _u.fit_count(s, visible, w0)
            s.text(x0, ty, _sl(visible, 0, k), "text" if _b.enabled(n) else "disabled")
        if focused:
            s.caret(x0 + s.text_width(_sl(shown, left, cur)), ty)
        s.pop_clip()

    func key(app, n, ev):
        if not _b.enabled(n):
            return false
        st := self._state(n)
        k := _b.key_of(ev)
        ok := n.get("on_key")
        if ok != null and app.call(ok, [k]) == true:
            return true
        if k == "enter":
            f := n.get("on_submit")
            if f != null:
                app.call(f, [st["value"]])
                return true
            return false
        if k == "ctrl+c" and not app.s.cell:
            app.clipboard_set(st["value"])
            return true
        clip := null
        if k == "ctrl+v":
            clip = app.clipboard_get()
        r := _e.apply(st["value"], st["cursor"], ev, false, clip)
        if r == null:
            return false
        st["cursor"] = r[1]
        if r[0] != st["value"]:
            st["value"] = r[0]
            st["__cur_for"] = r[0]
            app.call(n.get("on_change"), [r[0]])
        return true

    func mouse(app, n, ev):
        if not _b.enabled(n):
            return false
        a := ev["action"]
        if a != "down" and a != "drag":
            return a == "up"
        s := app.s
        st := self._state(n)
        shown := _shown(n, st["value"])
        left := _b.st_get(st, "left", 0)
        target := ev["x"] - n.x - s.px
        visible := _sl(shown, left)
        k := 0
        while k < len(visible) and s.text_width(_sl(visible, 0, k + 1)) <= target + s.text_width(str(visible[k])) / 2:
            k += 1
        st["cursor"] = left + k
        return true

    func text_of(n):
        v := str(n.get("value", ""))
        if v == "":
            return n.get("placeholder", "")
        return v

# ---------------------------------------------------------------- textarea
class TextArea extends Widget:
    func init():
        super.init()
        self.stretch_w = true
        self.stretch_h = true

    func focusable(app, n):
        return _b.enabled(n)

    func width_for(app, n, chars):
        return chars * app.s.cw + 2 * app.s.px + app.s.sbw

    func height_for(app, n, lines):
        return lines * app.s.lh + 2 * app.s.py

    func measure(app, n, max_w):
        return [self.width_for(app, n, 30), self.height_for(app, n, 5)]

    func _state(n):
        value := _b.controlled(n.st, "value", str(n.get("value", "")))
        if not contains_key(n.st, "cursor"):
            n.st["cursor"] = 0
        n.st["cursor"] = _u.clamp(n.st["cursor"], 0, len(value))
        return n.st

    func _rows(app, n):
        return _u.imax(1, (n.h - 2 * app.s.py) // app.s.lh)

    func _fix_scroll(app, n, st):
        lines := _u.split_lines(st["value"])
        lc := _e.line_col(st["value"], st["cursor"])
        rows := self._rows(app, n)
        top := _b.keep_visible(_b.st_get(st, "top", 0), lc[0], rows)
        top = _u.clamp(top, 0, _u.imax(0, len(lines) - 1))
        st["top"] = top
        return [lines, lc, rows, top]

    func paint(app, n):
        s := app.s
        st := self._state(n)
        focused := app.is_focused(n)
        _b.field_box(app, n, focused)
        r := self._fix_scroll(app, n, st)
        lines := r[0]
        lc := r[1]
        rows := r[2]
        top := r[3]
        x0 := n.x + s.px
        y0 := n.y + s.py
        bar := len(lines) > rows
        w0 := _u.imax(0, n.w - 2 * s.px - (s.sbw if bar else 0))
        # défilement horizontal commun (suit le curseur)
        cur_line := lines[lc[0]] if lc[0] < len(lines) else ""
        left := _b.st_get(st, "left", 0)
        if lc[1] < left:
            left = lc[1]
        while left < lc[1] and s.text_width(_sl(cur_line, left, lc[1])) > w0 - s.cw:
            left += 1
        st["left"] = left
        s.push_clip(x0, y0, w0, n.h - 2 * s.py)
        if st["value"] == "" and n.get("placeholder", "") != "":
            s.text(x0, y0, _u.fit(s, n.get("placeholder"), w0), "muted")
        i := 0
        while i < rows and top + i < len(lines):
            line := lines[top + i]
            seg := _sl(line, left) if left < len(line) else ""
            k := _u.fit_count(s, seg, w0)
            s.text(x0, y0 + i * s.lh, _sl(seg, 0, k), "text" if _b.enabled(n) else "disabled")
            i += 1
        if focused and lc[0] >= top and lc[0] < top + rows:
            s.caret(x0 + s.text_width(_sl(cur_line, left, lc[1])), y0 + (lc[0] - top) * s.lh)
        s.pop_clip()
        if bar:
            s.scrollbar(n.x + n.w - s.sbw - (s.bw if not s.cell else 0), y0, n.h - 2 * s.py, top / len(lines), rows / len(lines))

    func key(app, n, ev):
        if not _b.enabled(n):
            return false
        st := self._state(n)
        k := _b.key_of(ev)
        text := st["value"]
        cur := st["cursor"]
        if k == "up" or k == "down" or k == "page_up" or k == "page_down":
            lc := _e.line_col(text, cur)
            step := 1
            if k == "page_up" or k == "page_down":
                step = self._rows(app, n)
            target := lc[0] - step if (k == "up" or k == "page_up") else lc[0] + step
            count := len(_u.split_lines(text))
            target = _u.clamp(target, 0, count - 1)
            goal := _b.st_get(st, "goal", null)
            if goal == null:
                goal = lc[1]
            st["goal"] = goal
            st["cursor"] = _e.index_of(text, target, goal)
            return true
        st["goal"] = null
        if k == "ctrl+home":
            st["cursor"] = 0
            return true
        if k == "ctrl+end":
            st["cursor"] = len(text)
            return true
        if k == "ctrl+c" and not app.s.cell:
            app.clipboard_set(text)
            return true
        if n.get("readonly", false):
            if k == "left" or k == "right" or k == "home" or k == "end" or k == "ctrl+left" or k == "ctrl+right":
                r0 := _e.apply(text, cur, ev, true)
                st["cursor"] = r0[1]
                return true
            return false
        clip := null
        if k == "ctrl+v":
            clip = app.clipboard_get()
        r := _e.apply(text, cur, ev, true, clip)
        if r == null:
            return false
        st["cursor"] = r[1]
        if r[0] != text:
            st["value"] = r[0]
            app.call(n.get("on_change"), [r[0]])
        return true

    func mouse(app, n, ev):
        a := ev["action"]
        if a != "down" and a != "drag":
            return a == "up"
        s := app.s
        st := self._state(n)
        lines := _u.split_lines(st["value"])
        row := _b.st_get(st, "top", 0) + _u.imax(0, (ev["y"] - n.y - s.py) // s.lh)
        row = _u.clamp(row, 0, len(lines) - 1)
        line := lines[row]
        left := _b.st_get(st, "left", 0)
        target := ev["x"] - n.x - s.px
        k := 0
        seg := _sl(line, left) if left < len(line) else ""
        while k < len(seg) and s.text_width(_sl(seg, 0, k + 1)) <= target + s.text_width(str(seg[k])) / 2:
            k += 1
        st["cursor"] = _e.index_of(st["value"], row, left + k)
        st["goal"] = null
        return true

    func wheel(app, n, ev):
        st := self._state(n)
        lines := _u.split_lines(st["value"])
        rows := self._rows(app, n)
        if len(lines) <= rows:
            return false
        lc := _e.line_col(st["value"], st["cursor"])
        # déplacer le curseur avec la vue pour que l'affichage suive
        target := _u.clamp(lc[0] - ev["dy"] * 3, 0, len(lines) - 1)
        st["cursor"] = _e.index_of(st["value"], target, lc[1])
        return true

    func text_of(n):
        return str(n.get("value", ""))

# ---------------------------------------------------------------- select et sa liste ouverte
class Select extends Widget:
    func init():
        super.init()
        self.arrows_move_focus = false

    func focusable(app, n):
        return _b.enabled(n) and len(n.get("options", [])) > 0

    func width_for(app, n, chars):
        s := app.s
        return chars * s.cw + 2 * s.px + s.glyph_width("arrow_down") + s.cw

    func measure(app, n, max_w):
        s := app.s
        w := 0
        for o in n.get("options", []):
            w = _u.imax(w, s.text_width(o))
        return [w + 2 * s.px + s.glyph_width("arrow_down") + s.cw, s.ch]

    func _sel(n):
        return _b.controlled(n.st, "selected", n.get("selected", 0))

    func arrange(app, n):
        if _b.st_get(n.st, "open", false):
            st := n.st
            sel := self._sel(n)
            on_change := n.get("on_change")

            func pick(i):
                st["open"] = false
                if i != st["selected"]:
                    st["selected"] = i
                    _u.call(on_change, [i])

            func close():
                st["open"] = false

            popup := _n.Node("popup_list", {"items": n.get("options", []), "selected": sel, "on_pick": pick, "on_cancel": close})
            app.add_overlay(n, popup, "below", [n.x, n.y, n.w, n.h], false, close, n.path + "/liste", n.w)

    func paint(app, n):
        s := app.s
        focused := app.is_focused(n)
        _b.field_box(app, n, focused or _b.st_get(n.st, "open", false))
        opts := n.get("options", [])
        sel := self._sel(n)
        label := opts[sel] if sel >= 0 and sel < len(opts) else ""
        gw := s.glyph_width("arrow_down")
        ty := _b.text_y(app, n.y, n.h)
        s.text(n.x + s.px, ty, _u.fit(s, label, n.w - 2 * s.px - gw - s.cw), "text" if _b.enabled(n) else "disabled")
        s.glyph(n.x + n.w - s.px - gw, ty, "arrow_down", "muted")

    func _change(app, n, idx):
        if idx != self._sel(n):
            n.st["selected"] = idx
            app.call(n.get("on_change"), [idx])

    func key(app, n, ev):
        if not _b.enabled(n):
            return false
        k := _b.key_of(ev)
        count := len(n.get("options", []))
        if k == "enter" or k == "space" or k == "alt+down" or k == "f4":
            n.st["open"] = true
            return true
        sel := self._sel(n)
        if k == "down" and sel + 1 < count:
            self._change(app, n, sel + 1)
            return true
        if k == "up" and sel > 0:
            self._change(app, n, sel - 1)
            return true
        if k == "home" and count > 0:
            self._change(app, n, 0)
            return true
        if k == "end" and count > 0:
            self._change(app, n, count - 1)
            return true
        return false

    func mouse(app, n, ev):
        if ev["action"] == "down" and _b.enabled(n):
            n.st["open"] = not _b.st_get(n.st, "open", false)
            return true
        return false

    func wheel(app, n, ev):
        if not app.is_focused(n):
            return false
        sel := self._sel(n)
        nxt := _u.clamp(sel - ev["dy"], 0, len(n.get("options", [])) - 1)
        self._change(app, n, nxt)
        return true

    func text_of(n):
        opts := n.get("options", [])
        sel := n.get("selected", 0)
        if sel >= 0 and sel < len(opts):
            return opts[sel]
        return null

const _POPUP_ROWS := 10

class PopupList extends Widget:
    func init():
        super.init()

    func focusable(app, n):
        return true

    func _rows(app, n):
        return _u.imin(len(n.get("items", [])), _POPUP_ROWS)

    func measure(app, n, max_w):
        s := app.s
        w := 0
        for it in n.get("items", []):
            w = _u.imax(w, s.text_width(it))
        extra := s.sbw if len(n.get("items", [])) > _POPUP_ROWS else 0
        return [w + 2 * s.px + extra + 2 * s.bw, self._rows(app, n) * s.rh + 2 * s.bw]

    func _hi(n):
        if not contains_key(n.st, "hi"):
            n.st["hi"] = _u.imax(0, n.get("selected", 0))
        return n.st["hi"]

    func paint(app, n):
        s := app.s
        s.fill(n.x, n.y, n.w, n.h, "surface", s.radius)
        s.frame(n.x, n.y, n.w, n.h, "border", s.radius)
        items := n.get("items", [])
        rows := self._rows(app, n)
        hi := self._hi(n)
        top := _b.keep_visible(_b.st_get(n.st, "top", 0), hi, rows)
        n.st["top"] = top
        bar := len(items) > rows
        iw := n.w - 2 * s.bw - (s.sbw if bar else 0)
        i := 0
        while i < rows and top + i < len(items):
            idx := top + i
            y := n.y + s.bw + i * s.rh
            role := "text"
            if idx == hi:
                s.fill(n.x + s.bw, y, iw, s.rh, "accent")
                role = "accent_text"
            elif idx == n.get("selected"):
                role = "accent"
            s.text(n.x + s.bw + s.px, _b.text_y(app, y, s.rh), _u.fit(s, items[idx], iw - 2 * s.px), role)
            i += 1
        if bar:
            s.scrollbar(n.x + n.w - s.bw - s.sbw, n.y + s.bw, rows * s.rh, top / len(items), rows / len(items))

    func key(app, n, ev):
        k := _b.key_of(ev)
        items := n.get("items", [])
        hi := self._hi(n)
        if k == "enter" or k == "space":
            app.call(n.get("on_pick"), [hi])
            return true
        if k == "escape" or k == "tab" or k == "shift+tab":
            app.call(n.get("on_cancel"), [])
            return k == "escape"
        nxt := _b.list_nav(k, len(items), hi, self._rows(app, n))
        if nxt != null:
            n.st["hi"] = nxt
            return true
        t := ev["text"] if ev["type"] == "key" else null
        if t != null and t != "":
            i := 1
            while i <= len(items):
                idx := (hi + i) % len(items)
                if _s.starts_with(_s.lower(items[idx]), _s.lower(t)):
                    n.st["hi"] = idx
                    return true
                i += 1
        return true

    func _row_at(app, n, y):
        r := (y - n.y - app.s.bw) // app.s.rh
        idx := _b.st_get(n.st, "top", 0) + r
        if r < 0 or idx >= len(n.get("items", [])):
            return -1
        return idx

    func mouse(app, n, ev):
        a := ev["action"]
        idx := self._row_at(app, n, ev["y"])
        if a == "move" or a == "drag":
            if idx >= 0:
                n.st["hi"] = idx
            return true
        if a == "down" or a == "up":
            if idx >= 0 and a == "down":
                app.call(n.get("on_pick"), [idx])
            return true
        return false

    func wheel(app, n, ev):
        items := n.get("items", [])
        n.st["hi"] = _u.clamp(self._hi(n) - ev["dy"], 0, len(items) - 1)
        return true

    func text_of(n):
        return _s.join(" ", n.get("items", []))

# ---------------------------------------------------------------- slider
func _snap(n, v):
    lo := n.get("min", 0)
    hi := n.get("max", 100)
    step := n.get("step", 1)
    if step <= 0:
        step = 1
    k := _u.floor((v - lo) / step + 0.5)
    r := _u.clamp(lo + k * step, lo, hi)
    if type(step) == "int" and type(lo) == "int":
        r = to_int(r)
    return r

class Slider extends Widget:
    func init():
        super.init()
        self.stretch_w = true

    func focusable(app, n):
        return _b.enabled(n)

    func _label(n, v):
        if not n.get("show_value", true):
            return ""
        return _u.show(v)

    func _label_w(app, n):
        if not n.get("show_value", true):
            return 0
        return _u.imax(app.s.text_width(_u.show(n.get("min", 0))), app.s.text_width(_u.show(n.get("max", 100)))) + app.s.gx

    func measure(app, n, max_w):
        return [20 * app.s.cw + self._label_w(app, n), app.s.rh]

    func _track(app, n):
        s := app.s
        kw := s.glyph_width("knob")
        x0 := n.x + kw // 2
        w := _u.imax(1, n.w - self._label_w(app, n) - kw)
        return [x0, w]

    func paint(app, n):
        s := app.s
        lo := n.get("min", 0)
        hi := n.get("max", 100)
        v := _u.clamp(_b.controlled(n.st, "value", n.get("value", 0)), lo, hi)
        frac := 0.0
        if hi > lo:
            frac = _u.clamp((v - lo) / (hi - lo), 0, 1)
        tr := self._track(app, n)
        focused := app.is_focused(n)
        ty := _b.text_y(app, n.y, n.h)
        s.slider_track(tr[0], n.y, tr[1], n.h, frac, focused, _b.enabled(n))
        lab := self._label(n, v)
        if lab != "":
            s.text(n.x + n.w - self._label_w(app, n) + s.gx, ty, lab, "muted")

    func _set(app, n, v):
        nv := _snap(n, v)
        cur := _b.controlled(n.st, "value", n.get("value", 0))
        if nv != cur:
            n.st["value"] = nv
            app.call(n.get("on_change"), [nv])

    func key(app, n, ev):
        if not _b.enabled(n):
            return false
        k := _b.key_of(ev)
        v := _b.controlled(n.st, "value", n.get("value", 0))
        step := n.get("step", 1)
        if k == "right" or k == "up":
            self._set(app, n, v + step)
        elif k == "left" or k == "down":
            self._set(app, n, v - step)
        elif k == "page_up":
            self._set(app, n, v + step * 10)
        elif k == "page_down":
            self._set(app, n, v - step * 10)
        elif k == "home":
            self._set(app, n, n.get("min", 0))
        elif k == "end":
            self._set(app, n, n.get("max", 100))
        else:
            return false
        return true

    func mouse(app, n, ev):
        if not _b.enabled(n):
            return false
        a := ev["action"]
        if a == "down" or a == "drag":
            tr := self._track(app, n)
            frac := _u.clamp((ev["x"] - tr[0]) / tr[1], 0, 1)
            lo := n.get("min", 0)
            hi := n.get("max", 100)
            self._set(app, n, lo + frac * (hi - lo))
            return true
        return a == "up"

    func wheel(app, n, ev):
        if not app.is_focused(n):
            return false
        v := _b.controlled(n.st, "value", n.get("value", 0))
        self._set(app, n, v + ev["dy"] * n.get("step", 1))
        return true

    func text_of(n):
        return _u.show(n.get("value", 0))

# ---------------------------------------------------------------- spinbox
func _parse_number(t):
    t = _s.trim(t)
    if t == "" or t == "-":
        return null
    dot := false
    i := 0
    for c in t:
        if c == '-' and i == 0:
            i += 1
            continue
        if c == '.' or c == ',':
            if dot:
                return null
            dot = true
        elif c < '0' or c > '9':
            return null
        i += 1
    try:
        if dot:
            return to_float(_s.replace(t, ",", "."))
        return to_int(t)
    catch e:
        return null

class Spinbox extends Widget:
    func init():
        super.init()

    func focusable(app, n):
        return _b.enabled(n)

    func width_for(app, n, chars):
        s := app.s
        return chars * s.cw + 2 * s.px + s.spin_w

    func measure(app, n, max_w):
        return [self.width_for(app, n, 8), app.s.ch]

    func _value(n):
        return _b.controlled(n.st, "value", n.get("value", 0))

    func _commit(app, n):
        if not _b.st_get(n.st, "editing", false):
            return null
        n.st["editing"] = false
        v := _parse_number(_b.st_get(n.st, "text", ""))
        if v != null:
            self._set(app, n, v)

    func _set(app, n, v):
        lo := n.get("min", 0)
        hi := n.get("max", 100)
        v = _u.clamp(v, lo, hi)
        if v != self._value(n):
            n.st["value"] = v
            app.call(n.get("on_change"), [v])

    func paint(app, n):
        s := app.s
        focused := app.is_focused(n)
        if not focused:
            self._commit(app, n)
        _b.field_box(app, n, focused)
        editing := _b.st_get(n.st, "editing", false)
        t := _b.st_get(n.st, "text", "") if editing else _u.show(self._value(n))
        ty := _b.text_y(app, n.y, n.h)
        avail := n.w - 2 * s.px - s.spin_w
        shown := _u.fit(s, t, avail)
        tx := n.x + s.px + avail - s.text_width(shown)
        s.text(tx, ty, shown, "text" if _b.enabled(n) else "disabled")
        if focused:
            s.caret(tx + s.text_width(shown), ty)
        s.spin_arrows(n.x + n.w - s.spin_w, n.y, s.spin_w, n.h, _b.enabled(n))

    func key(app, n, ev):
        if not _b.enabled(n):
            return false
        k := _b.key_of(ev)
        step := n.get("step", 1)
        if k == "up" or k == "+" or k == "down" or k == "-" and not _b.st_get(n.st, "editing", false) or k == "page_up" or k == "page_down":
            self._commit(app, n)
            v := self._value(n)
            if k == "up" or k == "+":
                self._set(app, n, v + step)
            elif k == "down" or k == "-":
                self._set(app, n, v - step)
            elif k == "page_up":
                self._set(app, n, v + 10 * step)
            else:
                self._set(app, n, v - 10 * step)
            return true
        if k == "home":
            self._commit(app, n)
            self._set(app, n, n.get("min", 0))
            return true
        if k == "end":
            self._commit(app, n)
            self._set(app, n, n.get("max", 100))
            return true
        if k == "enter":
            self._commit(app, n)
            return true
        if k == "escape" and _b.st_get(n.st, "editing", false):
            n.st["editing"] = false
            return true
        t := ev["text"] if ev["type"] == "key" else null
        if k == "backspace" or (t != null and (t == "-" or t == "." or t == "," or (t >= "0" and t <= "9"))):
            if not _b.st_get(n.st, "editing", false):
                n.st["editing"] = true
                n.st["text"] = "" if k != "backspace" else _u.show(self._value(n))
            cur := n.st["text"]
            if k == "backspace":
                n.st["text"] = _sl(cur, 0, _u.imax(0, len(cur) - 1))
            else:
                n.st["text"] = cur + t
            return true
        return false

    func mouse(app, n, ev):
        if ev["action"] != "down" or not _b.enabled(n):
            return ev["action"] == "up"
        s := app.s
        if ev["x"] >= n.x + n.w - s.spin_w:
            self._commit(app, n)
            up := s.spin_hit_up(ev["x"] - (n.x + n.w - s.spin_w), ev["y"] - n.y, s.spin_w, n.h)
            step := n.get("step", 1)
            self._set(app, n, self._value(n) + (step if up else -step))
        return true

    func wheel(app, n, ev):
        if not app.is_focused(n):
            return false
        self._commit(app, n)
        self._set(app, n, self._value(n) + ev["dy"] * n.get("step", 1))
        return true

    func text_of(n):
        return _u.show(n.get("value", 0))
