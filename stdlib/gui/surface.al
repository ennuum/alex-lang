# ALEX STANDARD LIBRARY — gui.surface
#
# Surface de rendu de ui.view dans une fenêtre : une fenêtre du module ui (Win32, X11 ou hors écran) couverte
# d'un canvas sur lequel les composants dessinent en pixels (formes anticrénelées, texte, ombres). Les
# événements de la fenêtre (touches, texte, souris, molette, taille, fermeture) sont convertis au format
# commun (celui de tui.input).

from core use len, type, to_int, to_float
from collections use append, contains_key
use string as _s
use os as _os
use _native_ui as _ui
use ui.view.theme as _theme

const FONT := 14.0
const TITLE_FONT := 20.0
const MONO_FONT := 14.0

# Taille de la police à chasse fixe (code, consoles), réglable pendant l'exécution (gui.set_code_font_size) ;
# [taille, version] : les surfaces vident leur cache de largeurs quand la version change.
_mono := [MONO_FONT, 0]

func set_mono_size(px):
    p := to_float(px)
    if p < 8.0:
        p = 8.0
    if p > 40.0:
        p = 40.0
    if p != _mono[0]:
        _mono[0] = p
        _mono[1] = _mono[1] + 1

func mono_size():
    return _mono[0]

# Taille de la police de l'interface (menus, libellés, listes, onglets, dialogues), réglable pendant l'exécution
# (gui.set_ui_font_size) ; les hauteurs de ligne, de menu et d'onglet suivent. [taille, version].
_uif := [FONT, 0]

func set_ui_size(px):
    p := to_float(px)
    if p < 10.0:
        p = 10.0
    if p > 32.0:
        p = 32.0
    if p != _uif[0]:
        _uif[0] = p
        _uif[1] = _uif[1] + 1

func ui_size():
    return _uif[0]

const _VK := {8: "backspace", 9: "tab", 13: "enter", 27: "escape", 32: "space", 33: "page_up", 34: "page_down", 35: "end", 36: "home", 37: "left", 38: "up", 39: "right", 40: "down", 45: "insert", 46: "delete", 112: "f1", 113: "f2", 114: "f3", 115: "f4", 116: "f5", 117: "f6", 118: "f7", 119: "f8", 120: "f9", 121: "f10", 122: "f11", 123: "f12", 186: ";", 187: "=", 188: ",", 189: "-", 190: ".", 191: "/", 219: "[", 220: "\\", 221: "]", 222: "'", 106: "*", 107: "+", 109: "-", 111: "/"}

const _GLYPH_W := {"check_on": 18, "check_off": 18, "radio_on": 18, "radio_off": 18, "arrow_down": 12, "arrow_up": 12, "arrow_right": 12, "arrow_left": 12, "tri_right": 14, "tri_down": 14, "sort_up": 12, "sort_down": 12, "knob": 16, "check_mark": 14}

func _hex(c):
    v := 0
    for ch in c:
        d := _s.ord(ch)
        if d >= 48 and d <= 57:
            v = v * 16 + d - 48
        elif d >= 97 and d <= 102:
            v = v * 16 + d - 87
        elif d >= 65 and d <= 70:
            v = v * 16 + d - 55
    return v

func rgb(color):
    if type(color) != "str" or len(color) != 7:
        return [200, 200, 200]
    return [_hex(_s.slice(color, 1, 3)), _hex(_s.slice(color, 3, 5)), _hex(_s.slice(color, 5, 7))]

class Surface:
    func init(window, width, height, theme="dark"):
        self.win = window
        self.width = width
        self.height = height
        th := theme
        if th == "terminal":
            th = "dark"
        self.theme = _theme.resolve(th)
        self.canvas = _ui.canvas_create(window)
        self.virtual = false
        self._colors = {}
        self._widths = {}
        self._mono_ver = _mono[1]
        self._clips = []
        self._buttons = 0
        self._queue = []
        self._closed = false
        self._clipboard = null
        self._images = {}
        self.drawn = []               # tests : textes dessinés [texte, x, y, largeur, hauteur]
        # métriques (en pixels)
        self.cell = false
        self.cw = 8
        self.lh = 20
        self.py = 6
        self.ch = self.lh + 2 * self.py
        self.rh = 26
        self._ui_ver = -1
        self.px = 10
        self.ux = 8
        self.uy = 8
        self.gx = 8
        self.gy = 8
        self.sbw = 10
        self.radius = 6
        self.bw = 1
        self.sep = 9
        self.pad_x = 12
        self.pad_y = 10
        self.panel_title = 26
        self.lb = 1
        self.hsep = 1
        self.indent = 18
        self.split_w = 6
        self.tab_h = 36
        self.tab_px = 14
        self.tab_pad = 10
        self.menu_h = 30
        self.menu_px = 12
        self.spin_w = 22
        self.dialog_pad_x = 18
        self.dialog_pad_y = 14
        self.dialog_title = 32
        self.dialog_gap = 12
        self.refresh_metrics()

    # ------------------------------------------------------------ couleurs
    func _rgb(role):
        if contains_key(self._colors, role):
            return self._colors[role]
        c := role if (type(role) == "str" and len(role) == 7 and role[0] == '#') else _theme.color(self.theme, role)
        v := rgb(c) if c != null else [200, 200, 200]
        self._colors[role] = v
        return v

    # ------------------------------------------------------------ cycle
    func size():
        return [self.width, self.height]

    # Métriques dérivées de la taille de la police de l'interface (14 px : valeurs d'origine). Appelée au début
    # de chaque construction de la vue : un changement de taille s'applique sans rouvrir la fenêtre.
    func refresh_metrics():
        if self._ui_ver == _uif[1]:
            return null
        self._ui_ver = _uif[1]
        self._widths = {}
        f := _uif[0]
        k := f / FONT
        self.lh = to_int(f * 10.0 / 7.0 + 0.5)
        self.ch = self.lh + 2 * self.py
        self.rh = self.lh + 6
        self.cw = to_int(8 * k + 0.5)
        self.panel_title = self.lh + 6
        self.tab_h = self.lh + 16
        self.menu_h = self.lh + 10
        self.menu_px = to_int(12 * k + 0.5)
        self.dialog_title = self.lh + 12
        self.indent = to_int(18 * k + 0.5)

    func start():
        _ui.window_show(self.win)

    func stop():
        if not self._closed:
            self._closed = true
            try:
                _ui.canvas_destroy(self.canvas)
                _ui.window_close(self.win)
            catch e:
                return null

    func begin():
        self._clips = []
        self.drawn = []
        _ui.canvas_begin(self.canvas)
        _ui.canvas_reset_clip(self.canvas)
        c := self._rgb("bg")
        _ui.canvas_clear(self.canvas, c[0], c[1], c[2], 255)

    func end():
        _ui.canvas_end(self.canvas)

    # ------------------------------------------------------------ événements
    func _convert(e):
        t := e["type"]
        if t == "text_input":
            # Windows : le texte saisi arrive à part (WM_CHAR), après la touche
            text := e["data"]
            if text == " ":
                return {"type": "key", "key": "space", "text": " ", "ctrl": false, "alt": false, "shift": false}
            if text == "" or _s.ord(text[0]) < 32:
                return null
            return {"type": "key", "key": text, "text": text, "ctrl": false, "alt": false, "shift": false}
        if t == "key_down":
            mods := e["mods"]
            ctrl := (mods & 2) != 0
            alt := (mods & 1) != 0
            shift := (mods & 4) != 0
            text := e["text"] if contains_key(e, "text") else null
            vk := e["key"]
            if not contains_key(e, "text") and not ctrl and not alt and (vk == 32 or (vk >= 48 and vk <= 90) or (vk >= 186 and vk <= 222) or (vk >= 96 and vk <= 111)):
                return null                 # Windows : le caractère suivra dans text_input
            if text != null and text != "" and not ctrl and not alt and _s.ord(text[0]) >= 32 and _s.ord(text[0]) != 127:
                if text == " ":
                    return {"type": "key", "key": "space", "text": " ", "ctrl": false, "alt": false, "shift": shift}
                return {"type": "key", "key": text, "text": text, "ctrl": false, "alt": false, "shift": shift}
            name := null
            if contains_key(_VK, vk):
                name = _VK[vk]
            elif vk >= 65 and vk <= 90:
                name = str(_s.chr(vk + 32))
            elif vk >= 48 and vk <= 57:
                name = str(_s.chr(vk))
            if name == null:
                return null
            if vk == 32 and not ctrl and not alt:
                return {"type": "key", "key": "space", "text": " ", "ctrl": false, "alt": false, "shift": shift}
            full := name
            if shift and (len(name) > 1 or ctrl or alt):
                full = "shift+" + full
            if alt:
                full = "alt+" + full
            if ctrl:
                full = "ctrl+" + full
            return {"type": "key", "key": full, "text": null, "ctrl": ctrl, "alt": alt, "shift": shift}
        if t == "pointer_down" or t == "pointer_up":
            b := e["button"]
            name := "left"
            if b == 2:
                name = "right"
            elif b == 3:
                name = "middle"
            if t == "pointer_down":
                self._buttons += 1
                return {"type": "mouse", "action": "down", "button": name, "x": e["x"], "y": e["y"], "dx": 0, "dy": 0, "ctrl": (e["mods"] & 2) != 0, "alt": false, "shift": (e["mods"] & 4) != 0}
            self._buttons = _max(0, self._buttons - 1)
            return {"type": "mouse", "action": "up", "button": name, "x": e["x"], "y": e["y"], "dx": 0, "dy": 0, "ctrl": false, "alt": false, "shift": false}
        if t == "pointer_move":
            action := "drag" if self._buttons > 0 else "move"
            return {"type": "mouse", "action": action, "button": null, "x": e["x"], "y": e["y"], "dx": 0, "dy": 0, "ctrl": false, "alt": false, "shift": false}
        if t == "pointer_leave":
            return {"type": "mouse", "action": "move", "button": null, "x": -1, "y": -1, "dx": 0, "dy": 0, "ctrl": false, "alt": false, "shift": false}
        if t == "wheel":
            dy := to_int(e["dy"])
            if dy == 0 and e["dy"] != 0:
                dy = 1 if e["dy"] > 0 else -1
            return {"type": "mouse", "action": "wheel", "button": null, "x": e["x"], "y": e["y"], "dx": to_int(e["dx"]), "dy": dy, "ctrl": false, "alt": false, "shift": false}
        if t == "resize":
            self.width = e["x"]
            self.height = e["y"]
            _ui.canvas_resize(self.canvas)
            return {"type": "resize", "width": self.width, "height": self.height}
        if t == "close":
            if self.virtual:
                return null                 # headless : fermeture synthétisée quand la file est vide
            self._closed = true
            return {"type": "close"}
        return null

    func _poll():
        if self._closed:
            return null
        e := _ui.window_poll(self.win)
        while e != null:
            ev := self._convert(e)
            if ev != null:
                return ev
            e = _ui.window_poll(self.win)
        return null

    func next_event(timeout):
        started := _os.monotonic_time()
        if self._closed:
            return {"type": "close"}
        while true:
            ev := self._poll()
            if ev != null:
                return ev
            if timeout != null and _os.monotonic_time() - started >= timeout:
                return null
            if self.virtual:
                return {"type": "eof"} if timeout == null else null
            _os.sleep(0.008)

    func clipboard_get():
        try:
            return _ui.clipboard_get()
        catch e:
            return null

    func clipboard_set(text):
        try:
            _ui.clipboard_set(text)
        catch e:
            return null

    # ------------------------------------------------------------ mesure
    # "mono" : police du code, à la taille réglée ; "mono_ui" : même famille, taille fixe, pour les listes de
    # l'interface à hauteur de ligne fixe (variables, résultats, identifiants).
    func _font(font):
        if font == "title":
            return TITLE_FONT * _uif[0] / FONT
        if font == "mono":
            return _mono[0]
        if font == "mono_ui":
            return _uif[0]
        return _uif[0]

    func _family(font):
        return "mono" if font == "mono" or font == "mono_ui" else ""

    func text_width(text, font="normal"):
        if self._mono_ver != _mono[1]:
            self._mono_ver = _mono[1]
            self._widths = {}
        key := font + "\u0001" + text
        if contains_key(self._widths, key):
            return self._widths[key]
        if text == "":
            return 0
        m := _ui.text_measure(text, self._font(font), self._family(font))
        w := to_int(m["width"] + 0.999)
        if font == "bold" or font == "title":
            w += 1
        if len(self._widths) > 4000:
            self._widths = {}
        self._widths[key] = w
        return w

    func line_height(font="normal"):
        if font == "title":
            return to_int(28 * _uif[0] / FONT + 0.5)
        if font == "mono" and _mono[0] != MONO_FONT:
            # interligne proportionnel à la police du code (20 px pour 14 px)
            return to_int(_mono[0] * 10.0 / 7.0 + 0.5)
        return self.lh

    func glyph_width(name):
        if contains_key(_GLYPH_W, name):
            return _GLYPH_W[name]
        return 12

    # ------------------------------------------------------------ dessin
    func push_clip(x, y, w, h):
        r := [x, y, w, h]
        if len(self._clips) > 0:
            r = _intersect(self._clips[len(self._clips) - 1], r)
        append(self._clips, r)
        _ui.canvas_clip_rect(self.canvas, r[0], r[1], r[2], r[3])

    func pop_clip():
        if len(self._clips) == 0:
            return null
        out := []
        i := 0
        while i < len(self._clips) - 1:
            append(out, self._clips[i])
            i += 1
        self._clips = out
        # clip_rect s'intersecte avec le clip courant : pour revenir au clip parent il faut d'abord tout effacer
        _ui.canvas_reset_clip(self.canvas)
        if len(out) > 0:
            r := out[len(out) - 1]
            _ui.canvas_clip_rect(self.canvas, r[0], r[1], r[2], r[3])

    func _fill(x, y, w, h, c, radius=0, opacity=1.0):
        if w <= 0 or h <= 0:
            return null
        if radius > 0:
            _ui.canvas_round_rect(self.canvas, x, y, w, h, radius, "fill", c[0], c[1], c[2], 255, opacity, 0.0)
        else:
            _ui.canvas_fill_rect(self.canvas, x, y, w, h, "fill", c[0], c[1], c[2], 255, opacity)

    func _stroke(x, y, w, h, c, radius=0, width=1.0, opacity=1.0):
        if w <= 0 or h <= 0:
            return null
        half := width / 2
        _ui.canvas_round_rect(self.canvas, x + half, y + half, w - width, h - width, radius, "stroke", c[0], c[1], c[2], 255, opacity, width)

    func _line(x1, y1, x2, y2, c, width=1.5, opacity=1.0):
        _ui.canvas_line(self.canvas, x1, y1, x2, y2, c[0], c[1], c[2], 255, opacity, width)

    # Trait, cercle, image (fichier PNG / BMP / PPM, mis en cache), dégradé : pour les composants canvas et image.
    func line(x1, y1, x2, y2, role, width=1.5):
        self._line(x1, y1, x2, y2, self._rgb(role), width)

    func circle(cx, cy, r, role, filled=true, width=1.5):
        c := self._rgb(role)
        _ui.canvas_circle(self.canvas, cx, cy, r, "fill" if filled else "stroke", c[0], c[1], c[2], 255, 1.0, width)

    func stroke(x, y, w, h, role, radius=0, width=1.0):
        self._stroke(x, y, w, h, self._rgb(role), radius, width)

    func image(x, y, w, h, path, opacity=1.0):
        if not contains_key(self._images, path):
            try:
                self._images[path] = _ui.image_load(path)
            catch e:
                self._images[path] = null
        img := self._images[path]
        if img == null:
            return false
        _ui.canvas_image(self.canvas, img, x, y, w, h, opacity)
        return true

    func gradient(x, y, w, h, role_a, role_b, vertical=false):
        a := self._rgb(role_a)
        b := self._rgb(role_b)
        x2 := x if vertical else x + w
        y2 := y + h if vertical else y
        _ui.canvas_linear_gradient_rect(self.canvas, x, y, w, h, x, y, x2, y2, a[0], a[1], a[2], 255, b[0], b[1], b[2], 255, 1.0)

    func fill(x, y, w, h, role, radius=0):
        self._fill(x, y, w, h, self._rgb(role), radius)

    func frame(x, y, w, h, role, radius=0, thick=false, title=null):
        self._stroke(x, y, w, h, self._rgb(role), radius, 2.0 if thick else 1.0)

    func frame_title(x, y, w, title):
        self.text(x, y, title, "text", "bold")

    func text(x, y, text, role, font="normal"):
        if text == "":
            return null
        if self.virtual:
            append(self.drawn, [text, x, y, self.text_width(text, font), self.line_height(font)])
        c := self._rgb(role)
        size := self._font(font)
        _ui.canvas_text(self.canvas, text, x, y + (self.line_height(font) - size * 1.18) / 2, c[0], c[1], c[2], 255, 1.0, self._family(font), size)
        if font == "bold" or font == "title":
            _ui.canvas_text(self.canvas, text, x + 0.6, y + (self.line_height(font) - size * 1.18) / 2, c[0], c[1], c[2], 255, 1.0, "", size)

    func glyph(x, y, name, role):
        c := self._rgb(role)
        gw := self.glyph_width(name)
        cy := y + self.lh / 2
        cx := x + gw / 2
        if name == "check_on" or name == "check_off":
            s := 16
            bx := x + 1
            by := cy - s / 2
            if name == "check_on":
                self._fill(bx, by, s, s, c, 4)
                w := self._rgb("accent_text")
                self._line(bx + 4, by + 8.5, bx + 7, by + 11.5, w, 2.0)
                self._line(bx + 7, by + 11.5, bx + 12.5, by + 5, w, 2.0)
            else:
                self._stroke(bx, by, s, s, c, 4, 1.5)
            return null
        if name == "radio_on" or name == "radio_off":
            _ui.canvas_circle(self.canvas, cx, cy, 7.5, "stroke", c[0], c[1], c[2], 255, 1.0, 1.5)
            if name == "radio_on":
                _ui.canvas_circle(self.canvas, cx, cy, 4, "fill", c[0], c[1], c[2], 255, 1.0, 0.0)
            return null
        if name == "knob":
            _ui.canvas_circle(self.canvas, cx, cy, 7, "fill", c[0], c[1], c[2], 255, 1.0, 0.0)
            return null
        if name == "check_mark":
            self._line(x + 2, cy, x + 5.5, cy + 3.5, c, 2.0)
            self._line(x + 5.5, cy + 3.5, x + 12, cy - 4, c, 2.0)
            return null
        d := 3.5
        if name == "arrow_down" or name == "tri_down" or name == "sort_down":
            self._line(cx - d, cy - d / 2, cx, cy + d / 2, c, 1.6)
            self._line(cx, cy + d / 2, cx + d, cy - d / 2, c, 1.6)
        elif name == "arrow_up" or name == "sort_up":
            self._line(cx - d, cy + d / 2, cx, cy - d / 2, c, 1.6)
            self._line(cx, cy - d / 2, cx + d, cy + d / 2, c, 1.6)
        elif name == "arrow_right" or name == "tri_right":
            self._line(cx - d / 2, cy - d, cx + d / 2, cy, c, 1.6)
            self._line(cx + d / 2, cy, cx - d / 2, cy + d, c, 1.6)
        elif name == "arrow_left":
            self._line(cx + d / 2, cy - d, cx - d / 2, cy, c, 1.6)
            self._line(cx - d / 2, cy, cx + d / 2, cy + d, c, 1.6)

    func hline(x, y, w, role):
        self._fill(x, y, w, 1, self._rgb(role))

    func vline(x, y, h, role):
        self._fill(x, y, 1, h, self._rgb(role))

    func caret(x, y):
        self._fill(x, y + 2, 2, self.lh - 4, self._rgb("accent"))

    func focus_ring(x, y, w, h):
        self._stroke(x - 3, y - 3, w + 6, h + 6, self._rgb("accent"), self.radius + 3, 2.0, 0.85)

    func scrollbar(x, y, h, start, length):
        if h <= 0:
            return null
        th := _max(20, length * h)
        ty := y + start * (h - th) / _max(0.0001, 1 - length) if length < 1 else y
        self._fill(x + 2, ty, self.sbw - 4, th, self._rgb("muted"), (self.sbw - 4) / 2, 0.55)

    func bar(x, y, w, h, frac):
        if w <= 0:
            return null
        bh := 8
        by := y + (h - bh) / 2
        self._fill(x, by, w, bh, self._rgb("track"), bh / 2)
        if frac > 0:
            self._fill(x, by, _max(bh, w * frac), bh, self._rgb("accent"), bh / 2)

    func slider_track(x, y, w, h, frac, focused, enabled):
        cy := y + h / 2
        th := 4
        on := self._rgb("accent" if enabled else "disabled")
        self._fill(x, cy - th / 2, w, th, self._rgb("track"), th / 2)
        kx := x + frac * w
        self._fill(x, cy - th / 2, kx - x, th, on, th / 2)
        if focused:
            _ui.canvas_circle(self.canvas, kx, cy, 11, "fill", on[0], on[1], on[2], 255, 0.25, 0.0)
        k := self._rgb("text")
        _ui.canvas_circle(self.canvas, kx, cy, 7.5, "fill", k[0], k[1], k[2], 255, 1.0, 0.0)
        _ui.canvas_circle(self.canvas, kx, cy, 7.5, "stroke", on[0], on[1], on[2], 255, 1.0, 2.0)

    func spin_arrows(x, y, w, h, enabled):
        c := self._rgb("muted" if enabled else "disabled")
        self._fill(x, y + 4, 1, h - 8, self._rgb("border"))
        cx := x + w / 2
        q := h / 4
        d := 3.5
        self._line(cx - d, y + q + d / 2, cx, y + q - d / 2, c, 1.6)
        self._line(cx, y + q - d / 2, cx + d, y + q + d / 2, c, 1.6)
        self._line(cx - d, y + 3 * q - d / 2, cx, y + 3 * q + d / 2, c, 1.6)
        self._line(cx, y + 3 * q + d / 2, cx + d, y + 3 * q - d / 2, c, 1.6)

    func spin_hit_up(lx, ly, w, h):
        return ly < h / 2

    func tab(x, y, w, h, title, selected, focused, hovered):
        if hovered and not selected:
            self._fill(x + 2, y + 4, w - 4, h - 8, self._rgb("hover"), 6)
        role := "text" if selected else "muted"
        self.text(x + self.tab_px, y + (h - self.lh) / 2, title, role, "bold" if selected else "normal")
        if selected:
            self._fill(x + 6, y + h - 3, w - 12, 3, self._rgb("accent"), 1.5)
        if focused:
            self._stroke(x + 2, y + 3, w - 4, h - 6, self._rgb("accent"), 6, 2.0)

    func splitter(x, y, w, h, vertical, active):
        c := self._rgb("accent" if active else "border")
        if vertical:
            self._fill(x, y + h / 2 - (1 if active else 0.5), w, 2 if active else 1, c)
        else:
            self._fill(x + w / 2 - (1 if active else 0.5), y, 2 if active else 1, h, c)

    func shadow(x, y, w, h):
        _ui.canvas_shadow_round_rect(self.canvas, x, y, w, h, self.radius, 0, 0, 0, 0.45, 18.0, 0.0, 6.0, 0, 0, 0, 0, 0.0)

    func dim():
        _ui.canvas_fill_rect(self.canvas, 0, 0, self.width, self.height, "fill", 0, 0, 0, 255, 0.45)

func _intersect(a, b):
    x0 := _max(a[0], b[0])
    y0 := _max(a[1], b[1])
    x1 := _min(a[0] + a[2], b[0] + b[2])
    y1 := _min(a[1] + a[3], b[1] + b[3])
    return [x0, y0, _max(0, x1 - x0), _max(0, y1 - y0)]

func _min(a, b):
    if a < b:
        return a
    return b

func _max(a, b):
    if a > b:
        return a
    return b
