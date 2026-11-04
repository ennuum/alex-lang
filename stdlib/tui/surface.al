# ALEX STANDARD LIBRARY — tui.surface
#
# Surface de rendu de ui.view dans un terminal : les composants y dessinent en cellules (un caractère par
# cellule, deux pour les caractères larges) sur un tui.screen.Buffer, affiché par le terminal (réel ou
# virtuel) en ne réécrivant que les cellules modifiées. Couleurs par rôle (ui.view.theme) ; sans couleurs
# (NO_COLOR, TERM=dumb), la vidéo inverse et le gras marquent sélection et focus.

from core use len, type, to_int
from collections use append, contains_key
use string as _s
use tui.screen as _screen
use tui.style as _st
use tui.width as _tw
use ui.view.theme as _theme

const _GLYPHS := {"check_on": "[x]", "check_off": "[ ]", "radio_on": "(•)", "radio_off": "( )", "arrow_down": "▾", "arrow_up": "▴", "arrow_right": "▸", "arrow_left": "◂", "tri_right": "▸", "tri_down": "▾", "sort_up": "↑", "sort_down": "↓", "knob": "●", "check_mark": "✓"}

# Rôles de fond qui, sans couleurs, s'affichent en vidéo inverse.
const _MONO_REVERSE := ["accent", "selection_focus", "focus_bg", "button_primary", "accent_hover", "accent_pressed"]

class Surface:
    func init(term, theme="dark", virtual=false):
        self.term = term
        self.theme = _theme.resolve(theme)
        self.depth = term.depth
        self.virtual = virtual
        self.buf = _screen.Buffer(1, 1)
        self.bg = [""]
        self._styles = {}
        # métriques (en cellules)
        self.cell = true
        self.cw = 1
        self.lh = 1
        self.ch = 1
        self.rh = 1
        self.px = 1
        self.py = 0
        self.ux = 1
        self.uy = 1
        self.gx = 1
        self.gy = 0
        self.sbw = 1
        self.radius = 0
        self.bw = 1
        self.sep = 1
        self.pad_x = 1
        self.pad_y = 0
        self.panel_title = 0
        self.lb = 0
        self.hsep = 0
        self.indent = 2
        self.split_w = 1
        self.tab_h = 2
        self.tab_px = 1
        self.tab_pad = 0
        self.menu_h = 1
        self.menu_px = 1
        self.spin_w = 2
        self.dialog_pad_x = 2
        self.dialog_pad_y = 1
        self.dialog_title = 0
        self.dialog_gap = 1

    # ------------------------------------------------------------ styles
    func _color(role):
        return _theme.color(self.theme, role)

    # Style SGR d'un texte de rôle fg sur un fond de rôle bg.
    func style(fg, bg, bold=false):
        key := str(fg) + "|" + str(bg) + "|" + str(bold)
        if contains_key(self._styles, key):
            return self._styles[key]
        sg := ""
        if self.depth == "none":
            rev := bg != null and bg != "" and _index(_MONO_REVERSE, bg) >= 0
            dim := fg == "muted" or fg == "disabled" or fg == "border"
            sg = _st.style(null, null, bold or fg == "accent" or fg == "header_text", dim, false, false, rev)
        else:
            fc := null
            if fg != null:
                fc = self._color(fg)
            bc := null
            if bg != null and bg != "":
                bc = self._color(bg)
            sg = _st.style(fc, bc, bold)
        self._styles[key] = sg
        return sg

    func _bg_at(x, y):
        if x < 0 or y < 0 or x >= self.buf.width or y >= self.buf.height:
            return "bg"
        return self.bg[y * self.buf.width + x]

    # ------------------------------------------------------------ cycle
    func size():
        return self.term.size()

    # Terminal : métriques en cellules, indépendantes de la police de l'interface.
    func refresh_metrics():
        return null

    func start():
        self.term.start()

    func stop():
        self.term.stop()

    func begin():
        size := self.size()
        if self.buf.width != size[0] or self.buf.height != size[1]:
            self.buf = _screen.Buffer(size[0], size[1])
        else:
            self.buf.clear()
        self.bg = ["bg" for i in 0..size[0] * size[1]]
        self.buf.cursor = null
        self.buf._clips = []
        self.buf._clip = [0, 0, size[0], size[1]]

    func end():
        self.term.present(self.buf)

    func next_event(timeout):
        ev := self.term.read(timeout)
        if ev == null and timeout == null and self.virtual:
            return {"type": "eof"}
        return ev

    func clipboard_get():
        return null

    func clipboard_set(text):
        return null

    # ------------------------------------------------------------ mesure
    func text_width(text, font="normal"):
        return _tw.of(text)

    func line_height(font="normal"):
        return 1

    func glyph_width(name):
        if contains_key(_GLYPHS, name):
            return _tw.of(_GLYPHS[name])
        return 1

    # ------------------------------------------------------------ dessin
    func push_clip(x, y, w, h):
        self.buf.push_clip(x, y, w, h)

    func pop_clip():
        self.buf.pop_clip()

    func fill(x, y, w, h, role, radius=0):
        c := self.buf._clip
        x0 := _max(x, c[0])
        y0 := _max(y, c[1])
        x1 := _min(x + w, c[0] + c[2])
        y1 := _min(y + h, c[1] + c[3])
        sg := self.style("text", role)
        bw := self.buf.width
        yy := y0
        while yy < y1:
            xx := x0
            while xx < x1:
                self.buf._put(xx, yy, " ", sg)
                self.bg[yy * bw + xx] = role
                xx += 1
            yy += 1

    func text(x, y, text, role, font="normal"):
        bold := font == "bold" or font == "title"
        self.buf.text(x, y, text, self.style(role, self._bg_at(x, y), bold))

    func frame(x, y, w, h, role, radius=0, thick=false, title=null):
        kind := "heavy" if thick else "round"
        sg := self.style(role, self._bg_at(x + 1, y + 1))
        ts := self.style("text", self._bg_at(x + 1, y + 1), true)
        self.buf.box(x, y, w, h, sg, kind, title, ts)

    func frame_title(x, y, w, title):
        self.text(x, y, _tw.truncate(title, w), "text", "bold")

    func glyph(x, y, name, role):
        g := _GLYPHS[name] if contains_key(_GLYPHS, name) else "?"
        self.text(x, y, g, role)

    func hline(x, y, w, role):
        self.buf.hline(x, y, w, self.style(role, self._bg_at(x, y)), "─")

    func vline(x, y, h, role):
        self.buf.vline(x, y, h, self.style(role, self._bg_at(x, y)), "│")

    func caret(x, y):
        c := self.buf._clip
        if x >= c[0] and y >= c[1] and x < c[0] + c[2] and y < c[1] + c[3]:
            self.buf.cursor = [x, y]

    func focus_ring(x, y, w, h):
        self.fill(x, y, w, h, "focus_bg")

    func scrollbar(x, y, h, start, length):
        if h <= 0:
            return null
        t0 := to_int(start * h)
        t1 := _max(t0 + 1, to_int((start + length) * h + 0.5))
        t1 = _min(t1, h)
        if t0 >= h:
            t0 = h - 1
        i := 0
        while i < h:
            on := i >= t0 and i < t1
            self.buf.set(x, y + i, "█" if on else "│", self.style("muted" if on else "border", self._bg_at(x, y + i)))
            i += 1

    func bar(x, y, w, h, frac):
        if w <= 0:
            return null
        ty := y + (h - 1) // 2
        eighths := to_int(frac * w * 8 + 0.5)
        full := eighths // 8
        part := eighths % 8
        parts := ["", "▏", "▎", "▍", "▌", "▋", "▊", "▉"]
        sg := self.style("accent", self._bg_at(x, ty))
        tr := self.style("track", self._bg_at(x, ty))
        i := 0
        while i < w:
            if i < full:
                self.buf.set(x + i, ty, "█", sg)
            elif i == full and part > 0:
                self.buf.set(x + i, ty, parts[part], sg)
            else:
                self.buf.set(x + i, ty, "░", tr)
            i += 1

    func slider_track(x, y, w, h, frac, focused, enabled):
        ty := y + (h - 1) // 2
        pos := to_int(frac * (w - 1) + 0.5)
        on := "accent" if enabled else "disabled"
        i := 0
        while i < w:
            self.buf.set(x + i, ty, "━" if i < pos else "─", self.style(on if i < pos else "track", self._bg_at(x + i, ty)))
            i += 1
        knob_role := "accent" if focused else ("text" if enabled else "disabled")
        if focused:
            self.buf.set(x + pos, ty, "◉", self.style(knob_role, self._bg_at(x + pos, ty), true))
        else:
            self.buf.set(x + pos, ty, "●", self.style(knob_role, self._bg_at(x + pos, ty)))

    func spin_arrows(x, y, w, h, enabled):
        role := "muted" if enabled else "disabled"
        self.text(x, y, "▴▾", role)

    func spin_hit_up(lx, ly, w, h):
        return lx == 0

    func tab(x, y, w, h, title, selected, focused, hovered):
        if selected:
            bg := "accent" if focused else "selection"
            self.fill(x, y, w, h, bg)
            self.text(x + self.tab_px, y, title, "accent_text" if focused else "selection_text", "bold")
        else:
            self.text(x + self.tab_px, y, title, "muted")

    func splitter(x, y, w, h, vertical, active):
        role := "accent" if active else "border"
        if vertical:
            self.hline(x, y, w, role)
        else:
            self.vline(x, y, h, role)

    # Équivalents des primitives graphiques (canvas, image) : approximations en cellules.
    func line(x1, y1, x2, y2, role, width=1.5):
        if y1 == y2:
            self.hline(x1 if x1 < x2 else x2, y1, (x2 - x1) if x2 > x1 else (x1 - x2), role)

    func circle(cx, cy, r, role, filled=true, width=1.5):
        self.text(cx, cy, "●" if filled else "○", role)

    func stroke(x, y, w, h, role, radius=0, width=1.0):
        self.frame(x, y, w, h, role, radius)

    func image(x, y, w, h, path, opacity=1.0):
        return false

    func gradient(x, y, w, h, role_a, role_b, vertical=false):
        self.fill(x, y, w, h, role_a)

    func shadow(x, y, w, h):
        bw := self.buf.width
        bh := self.buf.height
        sg := self.style("muted", "shadow")
        yy := y + 1
        while yy <= y + h:
            if yy < bh and x + w < bw:
                self._shade(x + w, yy, sg)
            yy += 1
        xx := x + 1
        while xx <= x + w:
            if y + h < bh and xx < bw:
                self._shade(xx, y + h, sg)
            xx += 1

    func _shade(x, y, sg):
        i := y * self.buf.width + x
        self.buf.styles[i] = sg
        self.bg[i] = "shadow"

    func dim():
        n := len(self.buf.styles)
        i := 0
        while i < n:
            sg := self.buf.styles[i]
            self.buf.styles[i] = "2" if sg == "" else sg + ";2"
            i += 1
        self.buf.cursor = null

func _index(items, x):
    i := 0
    for it in items:
        if it == x:
            return i
        i += 1
    return -1

func _min(a, b):
    if a < b:
        return a
    return b

func _max(a, b):
    if a > b:
        return a
    return b
