# ALEX STANDARD LIBRARY — gl.window
#
# Fenêtre native avec un contexte OpenGL 3.3 core accéléré par la carte graphique : Win32 + WGL sous Windows,
# X11 + GLX sous Linux. Écrite en ALEX par ffi (user32 / gdi32 / opengl32, libX11 / libGL). Entrées clavier et
# souris, redimensionnement, plein écran (Windows : fenêtre sans bord), VSync, mesure du temps et des images/s.
#
#   use gl
#   use gl.window as glw
#   w := glw.Window("Démo", 1280, 720, {"vsync": true})
#   print(w.info["renderer"])
#   while w.is_open():
#       for e in w.poll():                 # événements depuis l'image précédente
#           if e["type"] == "key_down" and e["key"] == "escape":
#               w.close()
#       if w.key_down("left"): ...         # état courant du clavier / de la souris
#       gl.glViewport(0, 0, w.width, w.height)
#       gl.glClear(gl.GL_COLOR_BUFFER_BIT)
#       w.swap()                           # présente l'image (attend la synchro verticale si vsync)
#
# ÉVÉNEMENTS (dicts) : {"type": "key_down" | "key_up", "key": nom, "repeat": bool}, {"type": "char", "text": str},
#   {"type": "mouse_down" | "mouse_up", "button": "left" | "right" | "middle", "x", "y"},
#   {"type": "mouse_move", "x", "y", "dx", "dy"}, {"type": "wheel", "delta": +1 / -1}, {"type": "resize", "width",
#   "height"}, {"type": "focus", "focused": bool}, {"type": "close"}.
# NOMS DE TOUCHES : "a".."z", "0".."9", "space", "enter", "escape", "tab", "backspace", "delete", "insert", "home",
#   "end", "page_up", "page_down", "left", "right", "up", "down", "shift", "ctrl", "alt", "f1".."f12".
# OPTIONS : vsync (true), resizable (true), gl_version ([3, 3]), core (true), depth (24), stencil (8),
#   samples (0 ; antialiasing multi-échantillons, Linux), fullscreen (false), x / y (position).
#
# Erreurs : IoError (pas d'affichage, bibliothèque absente), RuntimeError (contexte OpenGL impossible).

from core use len, type
from collections use append
use ffi
use os as _os
use string as _s
use time as _time
use gl

# ---------------------------------------------------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------------------------------------------------

func _opt(opts, key, default):
    if opts != null and key in opts:
        return opts[key]
    return default

# Chaîne UTF-16 terminée par un NUL (Windows), dans un ffi.Buffer.
func _wide(text):
    codes := []
    for ch in text:
        c := _s.ord(ch)
        if c >= 65536:
            c -= 65536
            append(codes, 55296 + (c >> 10))
            append(codes, 56320 + (c & 1023))
        else:
            append(codes, c)
    append(codes, 0)
    b := ffi.Buffer(2 * len(codes))
    b.write_array("u16", codes)
    return b

func _s16(v):
    v = v & 65535
    if v >= 32768:
        return v - 65536
    return v

const _FKEYS := ["f1", "f2", "f3", "f4", "f5", "f6", "f7", "f8", "f9", "f10", "f11", "f12"]

# Touche virtuelle Windows (VK_*) -> nom.
func _vk_name(vk):
    if vk >= 0x41 and vk <= 0x5A:
        return str(_s.chr(vk + 32))
    if vk >= 0x30 and vk <= 0x39:
        return str(_s.chr(vk))
    if vk >= 0x70 and vk <= 0x7B:
        return _FKEYS[vk - 0x70]
    tab := {0x20: "space", 0x0D: "enter", 0x1B: "escape", 0x09: "tab", 0x08: "backspace", 0x2E: "delete",
            0x2D: "insert", 0x24: "home", 0x23: "end", 0x21: "page_up", 0x22: "page_down", 0x25: "left",
            0x26: "up", 0x27: "right", 0x28: "down", 0x10: "shift", 0xA0: "shift", 0xA1: "shift", 0x11: "ctrl",
            0xA2: "ctrl", 0xA3: "ctrl", 0x12: "alt", 0xA4: "alt", 0xA5: "alt"}
    if vk in tab:
        return tab[vk]
    return "vk_" + str(vk)

# KeySym X11 -> nom.
func _keysym_name(ks):
    if ks >= 0x61 and ks <= 0x7A:
        return str(_s.chr(ks))
    if ks >= 0x41 and ks <= 0x5A:
        return str(_s.chr(ks + 32))
    if ks >= 0x30 and ks <= 0x39:
        return str(_s.chr(ks))
    if ks >= 0xFFBE and ks <= 0xFFC9:
        return _FKEYS[ks - 0xFFBE]
    tab := {0x20: "space", 0xFF0D: "enter", 0xFF8D: "enter", 0xFF1B: "escape", 0xFF09: "tab", 0xFF08: "backspace",
            0xFFFF: "delete", 0xFF63: "insert", 0xFF50: "home", 0xFF57: "end", 0xFF55: "page_up",
            0xFF56: "page_down", 0xFF51: "left", 0xFF52: "up", 0xFF53: "right", 0xFF54: "down", 0xFFE1: "shift",
            0xFFE2: "shift", 0xFFE3: "ctrl", 0xFFE4: "ctrl", 0xFFE9: "alt", 0xFFEA: "alt", 0xFE03: "alt"}
    if ks in tab:
        return tab[ks]
    return "keysym_" + str(ks)

# ---------------------------------------------------------------------------------------------------------------------
# Fenêtre
# ---------------------------------------------------------------------------------------------------------------------

class Window:
    func init(title="ALEX", width=800, height=600, opts=null):
        self.title = title
        self.width = width
        self.height = height
        self.vsync = _opt(opts, "vsync", true)
        self.resizable = _opt(opts, "resizable", true)
        self.fullscreen = false
        self._open = false
        self._events = []
        self._keys = {}
        self._buttons = {}
        self.mouse_x = 0
        self.mouse_y = 0
        self.focused = true
        self.frame_count = 0
        self.fps = 0.0
        self.dt = 0.0
        self._t0 = _time.monotonic()
        self._last = self._t0
        self._fps_t = self._t0
        self._fps_n = 0
        self.platform = _os.platform()
        if self.platform == "windows":
            self._b = _WinBackend(self, opts)
        else:
            self._b = _X11Backend(self, opts)
        self._open = true
        gl._install(self._b.resolver())
        self.info = gl.info()
        gl.glViewport(0, 0, self.width, self.height)
        if _opt(opts, "fullscreen", false):
            self.set_fullscreen(true)

    func is_open():
        return self._open

    # Événements arrivés depuis l'appel précédent (met aussi à jour l'état du clavier et de la souris).
    func poll():
        self._events = []
        if self._open:
            self._b.pump()
        out := self._events
        self._events = []
        return out

    func _emit(e):
        t := e["type"]
        if t == "key_down":
            self._keys[e["key"]] = true
        elif t == "key_up":
            self._keys[e["key"]] = false
        elif t == "mouse_down":
            self._buttons[e["button"]] = true
        elif t == "mouse_up":
            self._buttons[e["button"]] = false
        elif t == "resize":
            self.width = e["width"]
            self.height = e["height"]
        elif t == "focus":
            self.focused = e["focused"]
            if not e["focused"]:
                self._keys = {}
                self._buttons = {}
        append(self._events, e)

    func key_down(name):
        return name in self._keys and self._keys[name]

    func mouse_down(button="left"):
        return button in self._buttons and self._buttons[button]

    func mouse_position():
        return [self.mouse_x, self.mouse_y]

    func size():
        return [self.width, self.height]

    func aspect():
        if self.height <= 0:
            return 1.0
        return self.width * 1.0 / self.height

    # Temps écoulé depuis la création (s).
    func time():
        return _time.monotonic() - self._t0

    # Présente l'image ; met à jour dt (durée de l'image précédente) et fps (moyenne sur ~0,5 s).
    func swap():
        if not self._open:
            return
        self._b.swap()
        now := _time.monotonic()
        self.dt = now - self._last
        self._last = now
        self.frame_count += 1
        self._fps_n += 1
        if now - self._fps_t >= 0.5:
            self.fps = self._fps_n / (now - self._fps_t)
            self._fps_n = 0
            self._fps_t = now

    func set_title(title):
        self.title = title
        if self._open:
            self._b.set_title(title)

    func set_vsync(on):
        self.vsync = on
        if self._open:
            self._b.set_vsync(on)

    func set_fullscreen(on):
        if self._open and on != self.fullscreen:
            self.fullscreen = on
            self._b.set_fullscreen(on)

    # Pixels de l'image courante (avant swap) : list d'octets RGBA, ligne du BAS en premier (convention OpenGL).
    func read_pixels():
        n := self.width * self.height * 4
        b := ffi.Buffer(n)
        gl.glPixelStorei(gl.GL_PACK_ALIGNMENT, 1)
        gl.glReadPixels(0, 0, self.width, self.height, gl.GL_RGBA, gl.GL_UNSIGNED_BYTE, b.address())
        px := b.read_array("u8", n)
        b.free()
        return px

    func close():
        if self._open:
            self._open = false
            gl._uninstall()
            self._b.destroy()
            append(self._events, {"type": "close"})

# ---------------------------------------------------------------------------------------------------------------------
# Windows : Win32 + WGL
# ---------------------------------------------------------------------------------------------------------------------

const _WS_OVERLAPPEDWINDOW := 0x00CF0000
const _WS_FIXED := 0x00CA0000            # titre, menu système, réduction (pas de bord redimensionnable)
const _WS_POPUP := 0x80000000
const _WS_VISIBLE := 0x10000000
const _CW_USEDEFAULT := 0x80000000

class _WinBackend:
    func init(win, opts):
        self.w = win
        self.u32 = ffi.Library("user32")
        self.g32 = ffi.Library("gdi32")
        self.k32 = ffi.Library("kernel32")
        self.ogl = ffi.Library("opengl32")
        u := self.u32
        self.f = {}
        f := self.f
        f["PeekMessageW"] = u.function("PeekMessageW", ["ptr", "ptr", "u32", "u32", "u32"], "i32")
        f["TranslateMessage"] = u.function("TranslateMessage", ["ptr"], "i32")
        f["DispatchMessageW"] = u.function("DispatchMessageW", ["ptr"], "i64")
        f["IsWindow"] = u.function("IsWindow", ["ptr"], "i32")
        f["GetClientRect"] = u.function("GetClientRect", ["ptr", "ptr"], "i32")
        f["SetWindowTextW"] = u.function("SetWindowTextW", ["ptr", "ptr"], "i32")
        f["DestroyWindow"] = u.function("DestroyWindow", ["ptr"], "i32")
        f["GetForegroundWindow"] = u.function("GetForegroundWindow", [], "ptr")
        f["SetWindowLongPtrW"] = u.function("SetWindowLongPtrW", ["ptr", "i32", "i64"], "i64")
        f["SetWindowPos"] = u.function("SetWindowPos", ["ptr", "ptr", "i32", "i32", "i32", "i32", "u32"], "i32")
        f["GetSystemMetrics"] = u.function("GetSystemMetrics", ["i32"], "i32")
        f["GetWindowRect"] = u.function("GetWindowRect", ["ptr", "ptr"], "i32")
        f["SwapBuffers"] = self.g32.function("SwapBuffers", ["ptr"], "i32")
        f["wglGetProcAddress"] = self.ogl.function("wglGetProcAddress", ["cstr"], "ptr")
        f["wglMakeCurrent"] = self.ogl.function("wglMakeCurrent", ["ptr", "ptr"], "i32")
        f["wglDeleteContext"] = self.ogl.function("wglDeleteContext", ["ptr"], "i32")
        f["ReleaseDC"] = u.function("ReleaseDC", ["ptr", "ptr"], "i32")
        try:
            u.function("SetProcessDPIAware", [], "i32").call0()
        catch e:
            pass
        hinst := self.k32.function("GetModuleHandleW", ["ptr"], "ptr").call1(0)
        # classe de fenêtre : la procédure est DefWindowProcW (les messages utiles passent par la file : PeekMessage)
        self.cls_name = _wide("AlexGLWindow")
        wc := ffi.Buffer(72)
        wc.write("u32", 0x0023, 0)                                   # CS_OWNDC | CS_HREDRAW | CS_VREDRAW
        wc.write("ptr", u.address("DefWindowProcW"), 8)
        wc.write("ptr", hinst, 24)
        wc.write("ptr", u.function("LoadCursorW", ["ptr", "ptr"], "ptr").call2(0, 32512), 40)
        wc.write("ptr", self.cls_name.address(), 64)
        u.function("RegisterClassW", ["ptr"], "u16").call1(wc.address())   # déjà enregistrée : sans effet
        wc.free()
        self.style = _WS_OVERLAPPEDWINDOW if win.resizable else _WS_FIXED
        rect := ffi.Buffer(16)
        rect.write_array("i32", [0, 0, win.width, win.height])
        u.function("AdjustWindowRect", ["ptr", "u32", "i32"], "i32").call([rect.address(), self.style, 0])
        r := rect.read_array("i32", 4)
        rect.free()
        title := _wide(win.title)
        x := _opt(opts, "x", _CW_USEDEFAULT)
        y := _opt(opts, "y", _CW_USEDEFAULT)
        create := u.function("CreateWindowExW", ["u32", "ptr", "ptr", "u32", "i32", "i32", "i32", "i32", "ptr", "ptr", "ptr", "ptr"], "ptr")
        self.hwnd = create.call([0, self.cls_name.address(), title.address(), self.style | _WS_VISIBLE,
                                 x if x != _CW_USEDEFAULT else -2147483648, y if y != _CW_USEDEFAULT else -2147483648,
                                 r[2] - r[0], r[3] - r[1], 0, 0, hinst, 0])
        title.free()
        if self.hwnd == null or self.hwnd == 0:
            raise("IoError", "gl.window : CreateWindowExW a échoué")
        self.hdc = u.function("GetDC", ["ptr"], "ptr").call1(self.hwnd)
        # format de pixel : RGBA 32 bits, double tampon, profondeur et stencil
        pfd := ffi.Buffer(40)
        pfd.write("u16", 40, 0)
        pfd.write("u16", 1, 2)
        pfd.write("u32", 0x25, 4)                                     # DRAW_TO_WINDOW | SUPPORT_OPENGL | DOUBLEBUFFER
        pfd.write("u8", 0, 8)
        pfd.write("u8", 32, 9)
        pfd.write("u8", 8, 16)
        pfd.write("u8", _opt(opts, "depth", 24), 23)
        pfd.write("u8", _opt(opts, "stencil", 8), 24)
        pf := self.g32.function("ChoosePixelFormat", ["ptr", "ptr"], "i32").call2(self.hdc, pfd.address())
        if pf == 0 or self.g32.function("SetPixelFormat", ["ptr", "i32", "ptr"], "i32").call3(self.hdc, pf, pfd.address()) == 0:
            pfd.free()
            raise("RuntimeError", "gl.window : aucun format de pixel OpenGL convenable")
        pfd.free()
        tmp := self.ogl.function("wglCreateContext", ["ptr"], "ptr").call1(self.hdc)
        if tmp == null or tmp == 0:
            raise("RuntimeError", "gl.window : wglCreateContext a échoué (pilote OpenGL absent ?)")
        f["wglMakeCurrent"].call2(self.hdc, tmp)
        self.ctx = tmp
        ver := _opt(opts, "gl_version", [3, 3])
        cca := self._proc("wglCreateContextAttribsARB")
        if cca != 0:
            attrs := ffi.Buffer(64)
            core_bit := 1 if _opt(opts, "core", true) else 2
            attrs.write_array("i32", [0x2091, ver[0], 0x2092, ver[1], 0x9126, core_bit, 0])
            fcca := ffi.function_at(cca, "wglCreateContextAttribsARB", ["ptr", "ptr", "ptr"], "ptr")
            ctx := fcca.call3(self.hdc, 0, attrs.address())
            attrs.free()
            if ctx != null and ctx != 0:
                f["wglMakeCurrent"].call2(self.hdc, ctx)
                f["wglDeleteContext"].call1(tmp)
                self.ctx = ctx
        self.msg = ffi.Buffer(48)
        self.rect = ffi.Buffer(16)
        self.saved = null
        self.set_vsync(win.vsync)

    # Adresse d'une fonction OpenGL : wglGetProcAddress (extensions, GL >= 1.2), sinon opengl32.dll (GL 1.1).
    func _proc(name):
        a := self.f["wglGetProcAddress"].call1(name)
        if a == null:
            a = 0
        if a == 0 or a == 1 or a == 2 or a == 3 or a == -1:
            a = self.ogl.address(name)
        return a

    func resolver():
        return (name) => self._proc(name)

    func set_vsync(on):
        a := self._proc("wglSwapIntervalEXT")
        if a != 0:
            ffi.function_at(a, "wglSwapIntervalEXT", ["i32"], "i32").call1(1 if on else 0)

    func set_title(title):
        t := _wide(title)
        self.f["SetWindowTextW"].call2(self.hwnd, t.address())
        t.free()

    func set_fullscreen(on):
        f := self.f
        if on:
            r := ffi.Buffer(16)
            f["GetWindowRect"].call2(self.hwnd, r.address())
            self.saved = r.read_array("i32", 4)
            r.free()
            sw := f["GetSystemMetrics"].call1(0)
            sh := f["GetSystemMetrics"].call1(1)
            f["SetWindowLongPtrW"].call([self.hwnd, -16, _WS_POPUP | _WS_VISIBLE])
            f["SetWindowPos"].call([self.hwnd, 0, 0, 0, sw, sh, 0x0020 | 0x0040])     # FRAMECHANGED | SHOWWINDOW
        else:
            f["SetWindowLongPtrW"].call([self.hwnd, -16, self.style | _WS_VISIBLE])
            s := self.saved
            if s == null:
                s = [100, 100, 100 + self.w.width, 100 + self.w.height]
            f["SetWindowPos"].call([self.hwnd, 0, s[0], s[1], s[2] - s[0], s[3] - s[1], 0x0020 | 0x0040])

    func pump():
        f := self.f
        w := self.w
        m := self.msg
        while f["PeekMessageW"].call([m.address(), 0, 0, 0, 1]) != 0:
            msg := m.read("u32", 8)
            wp := m.read("i64", 16)
            lp := m.read("i64", 24)
            if msg == 0x0100 or msg == 0x0104:                          # WM_KEYDOWN / WM_SYSKEYDOWN
                w._emit({"type": "key_down", "key": _vk_name(wp & 255), "repeat": ((lp >> 30) & 1) == 1})
            elif msg == 0x0101 or msg == 0x0105:
                w._emit({"type": "key_up", "key": _vk_name(wp & 255), "repeat": false})
            elif msg == 0x0102:                                          # WM_CHAR (UTF-16)
                if wp >= 32 and wp < 55296:
                    w._emit({"type": "char", "text": str(_s.chr(wp))})
            elif msg == 0x0200:                                          # WM_MOUSEMOVE
                x := _s16(lp)
                y := _s16(lp >> 16)
                w._emit({"type": "mouse_move", "x": x, "y": y, "dx": x - w.mouse_x, "dy": y - w.mouse_y})
                w.mouse_x = x
                w.mouse_y = y
            elif msg == 0x0201 or msg == 0x0204 or msg == 0x0207:
                b := "left" if msg == 0x0201 else ("right" if msg == 0x0204 else "middle")
                w._emit({"type": "mouse_down", "button": b, "x": _s16(lp), "y": _s16(lp >> 16)})
            elif msg == 0x0202 or msg == 0x0205 or msg == 0x0208:
                b := "left" if msg == 0x0202 else ("right" if msg == 0x0205 else "middle")
                w._emit({"type": "mouse_up", "button": b, "x": _s16(lp), "y": _s16(lp >> 16)})
            elif msg == 0x020A:                                          # WM_MOUSEWHEEL
                d := _s16(wp >> 16)
                w._emit({"type": "wheel", "delta": 1 if d > 0 else -1})
            f["TranslateMessage"].call1(m.address())
            f["DispatchMessageW"].call1(m.address())
        if f["IsWindow"].call1(self.hwnd) == 0:                         # fermée (croix, Alt+F4 : DefWindowProc)
            w._open = false
            gl._uninstall()
            w._emit({"type": "close"})
            return
        f["GetClientRect"].call2(self.hwnd, self.rect.address())
        r := self.rect.read_array("i32", 4)
        cw := r[2] - r[0]
        ch := r[3] - r[1]
        if (cw != w.width or ch != w.height) and cw > 0 and ch > 0:
            w._emit({"type": "resize", "width": cw, "height": ch})
        fg := f["GetForegroundWindow"].call0() == self.hwnd
        if fg != w.focused:
            w._emit({"type": "focus", "focused": fg})

    func swap():
        self.f["SwapBuffers"].call1(self.hdc)

    func destroy():
        f := self.f
        f["wglMakeCurrent"].call2(0, 0)
        f["wglDeleteContext"].call1(self.ctx)
        f["ReleaseDC"].call2(self.hwnd, self.hdc)
        if f["IsWindow"].call1(self.hwnd) != 0:
            f["DestroyWindow"].call1(self.hwnd)

# ---------------------------------------------------------------------------------------------------------------------
# Linux : X11 + GLX
# ---------------------------------------------------------------------------------------------------------------------

class _X11Backend:
    func init(win, opts):
        self.w = win
        try:
            self.x = ffi.Library("libX11.so.6")
        catch e:
            raise("IoError", "gl.window : libX11 introuvable (" + e.message + ")")
        try:
            self.glx = ffi.Library("libGL.so.1")
        catch e:
            raise("IoError", "gl.window : libGL introuvable, installer le pilote OpenGL (" + e.message + ")")
        x := self.x
        g := self.glx
        self.f = {}
        f := self.f
        f["XPending"] = x.function("XPending", ["ptr"], "i32")
        f["XNextEvent"] = x.function("XNextEvent", ["ptr", "ptr"], "i32")
        f["XLookupKeysym"] = x.function("XLookupKeysym", ["ptr", "i32"], "u64")
        f["XLookupString"] = x.function("XLookupString", ["ptr", "ptr", "i32", "ptr", "ptr"], "i32")
        f["XStoreName"] = x.function("XStoreName", ["ptr", "u64", "cstr"], "i32")
        f["XFlush"] = x.function("XFlush", ["ptr"], "i32")
        f["XSendEvent"] = x.function("XSendEvent", ["ptr", "u64", "i32", "i64", "ptr"], "i32")
        f["XInternAtom"] = x.function("XInternAtom", ["ptr", "cstr", "i32"], "u64")
        f["glXSwapBuffers"] = g.function("glXSwapBuffers", ["ptr", "u64"], "void")
        f["glXGetProcAddressARB"] = g.function("glXGetProcAddressARB", ["cstr"], "ptr")
        f["glXMakeCurrent"] = g.function("glXMakeCurrent", ["ptr", "u64", "ptr"], "i32")
        self.dpy = x.function("XOpenDisplay", ["cstr"], "ptr").call1(null)
        if self.dpy == null or self.dpy == 0:
            raise("IoError", "gl.window : aucun affichage X11 (variable DISPLAY ?)")
        dpy := self.dpy
        screen := x.function("XDefaultScreen", ["ptr"], "i32").call1(dpy)
        root := x.function("XRootWindow", ["ptr", "i32"], "u64").call2(dpy, screen)
        # configuration de tampon : RGBA, double tampon, profondeur / stencil, multi-échantillons éventuel
        samples := _opt(opts, "samples", 0)
        attrs := [0x8010, 1, 0x8011, 1, 0x8012, 1, 5, 1, 8, 8, 9, 8, 10, 8, 11, 8,
                  12, _opt(opts, "depth", 24), 13, _opt(opts, "stencil", 8)]
        if samples > 0:
            attrs = attrs + [100000, 1, 100001, samples]
        attrs = attrs + [0]
        ab := ffi.Buffer(4 * len(attrs))
        ab.write_array("i32", attrs)
        nb := ffi.Buffer(4)
        choose := g.function("glXChooseFBConfig", ["ptr", "i32", "ptr", "ptr"], "ptr")
        cfgs := choose.call([dpy, screen, ab.address(), nb.address()])
        if (cfgs == null or nb.read("i32") == 0) and samples > 0:
            ab.write("i32", 0, 4 * (len(attrs) - 5))                 # sans multi-échantillons
            cfgs = choose.call([dpy, screen, ab.address(), nb.address()])
        ab.free()
        if cfgs == null or nb.read("i32") == 0:
            nb.free()
            raise("RuntimeError", "gl.window : aucune configuration GLX convenable")
        nb.free()
        self.fb = ffi.peek(cfgs, "ptr")
        x.function("XFree", ["ptr"], "i32").call1(cfgs)
        vi := g.function("glXGetVisualFromFBConfig", ["ptr", "ptr"], "ptr").call2(dpy, self.fb)
        if vi == null:
            raise("RuntimeError", "gl.window : aucun visuel X11 pour la configuration GLX")
        visual := ffi.peek(vi, "ptr")
        depth := ffi.peek(vi + 20, "i32")
        cmap := x.function("XCreateColormap", ["ptr", "u64", "ptr", "i32"], "u64").call([dpy, root, visual, 0])
        swa := ffi.Buffer(112)
        swa.write("u64", 0, 24)                                       # border_pixel
        mask := 1 | 2 | 4 | 8 | 64 | (1 << 17) | (1 << 21) | (1 << 15)
        swa.write("i64", mask, 72)                                    # event_mask
        swa.write("u64", cmap, 96)                                    # colormap
        create := x.function("XCreateWindow", ["ptr", "u64", "i32", "i32", "u32", "u32", "u32", "i32", "u32", "ptr", "u64", "ptr"], "u64")
        self.win = create.call([dpy, root, _opt(opts, "x", 0), _opt(opts, "y", 0), win.width, win.height, 0, depth, 1,
                                visual, (1 << 3) | (1 << 11) | (1 << 13), swa.address()])
        swa.free()
        x.function("XFree", ["ptr"], "i32").call1(vi)
        if self.win == 0:
            raise("IoError", "gl.window : XCreateWindow a échoué")
        f["XStoreName"].call3(dpy, self.win, win.title)
        if not win.resizable:
            hints := ffi.Buffer(80)                                    # XSizeHints : PMinSize | PMaxSize
            hints.write("i64", (1 << 4) | (1 << 5), 0)
            hints.write_array("i32", [win.width, win.height, win.width, win.height], 40)
            x.function("XSetWMNormalHints", ["ptr", "u64", "ptr"], "void").call3(dpy, self.win, hints.address())
            hints.free()
        self.wm_delete = f["XInternAtom"].call3(dpy, "WM_DELETE_WINDOW", 0)
        ad := ffi.Buffer(8)
        ad.write("u64", self.wm_delete)
        x.function("XSetWMProtocols", ["ptr", "u64", "ptr", "i32"], "i32").call([dpy, self.win, ad.address(), 1])
        ad.free()
        try:
            x.function("XkbSetDetectableAutoRepeat", ["ptr", "i32", "ptr"], "i32").call3(dpy, 1, 0)
        catch e:
            pass
        x.function("XMapWindow", ["ptr", "u64"], "i32").call2(dpy, self.win)
        f["XFlush"].call1(dpy)
        # contexte 3.3 core par glXCreateContextAttribsARB, sinon contexte classique
        ver := _opt(opts, "gl_version", [3, 3])
        self.ctx = 0
        cca := self._proc("glXCreateContextAttribsARB")
        if cca != 0:
            ca := ffi.Buffer(64)
            core_bit := 1 if _opt(opts, "core", true) else 2
            ca.write_array("i32", [0x2091, ver[0], 0x2092, ver[1], 0x9126, core_bit, 0])
            fc := ffi.function_at(cca, "glXCreateContextAttribsARB", ["ptr", "ptr", "ptr", "i32", "ptr"], "ptr")
            c := fc.call([dpy, self.fb, 0, 1, ca.address()])
            ca.free()
            if c != null:
                self.ctx = c
        if self.ctx == 0:
            c := g.function("glXCreateNewContext", ["ptr", "ptr", "i32", "ptr", "i32"], "ptr").call([dpy, self.fb, 0x8014, 0, 1])
            if c != null:
                self.ctx = c
        if self.ctx == 0:
            raise("RuntimeError", "gl.window : création du contexte OpenGL impossible")
        if f["glXMakeCurrent"].call3(dpy, self.win, self.ctx) == 0:
            raise("RuntimeError", "gl.window : glXMakeCurrent a échoué")
        self.ev = ffi.Buffer(192)
        self.kbuf = ffi.Buffer(32)
        self.ksym = ffi.Buffer(8)
        self.set_vsync(win.vsync)

    func _proc(name):
        a := self.f["glXGetProcAddressARB"].call1(name)
        if a == null:
            return 0
        return a

    func resolver():
        return (name) => self._proc(name)

    func set_vsync(on):
        a := self._proc("glXSwapIntervalEXT")
        if a != 0:
            ffi.function_at(a, "glXSwapIntervalEXT", ["ptr", "u64", "i32"], "void").call3(self.dpy, self.win, 1 if on else 0)
            return
        a = self._proc("glXSwapIntervalMESA")
        if a != 0:
            ffi.function_at(a, "glXSwapIntervalMESA", ["u32"], "i32").call1(1 if on else 0)

    func set_title(title):
        self.f["XStoreName"].call3(self.dpy, self.win, title)
        self.f["XFlush"].call1(self.dpy)

    # Plein écran par le gestionnaire de fenêtres (_NET_WM_STATE_FULLSCREEN).
    func set_fullscreen(on):
        f := self.f
        state := f["XInternAtom"].call3(self.dpy, "_NET_WM_STATE", 0)
        full := f["XInternAtom"].call3(self.dpy, "_NET_WM_STATE_FULLSCREEN", 0)
        e := ffi.Buffer(192)
        e.write("i32", 33, 0)                                         # ClientMessage
        e.write("i32", 1, 16)
        e.write("u64", self.win, 32)
        e.write("u64", state, 40)
        e.write("i32", 32, 48)
        e.write("i64", 1 if on else 0, 56)
        e.write("i64", full, 64)
        root := self.x.function("XDefaultRootWindow", ["ptr"], "u64").call1(self.dpy)
        f["XSendEvent"].call([self.dpy, root, 0, (1 << 20) | (1 << 19), e.address()])
        e.free()
        f["XFlush"].call1(self.dpy)

    func pump():
        f := self.f
        w := self.w
        ev := self.ev
        dpy := self.dpy
        while w._open and f["XPending"].call1(dpy) > 0:
            f["XNextEvent"].call2(dpy, ev.address())
            t := ev.read("i32", 0)
            if t == 2 or t == 3:                                      # KeyPress / KeyRelease
                ks := f["XLookupKeysym"].call2(ev.address(), 0)
                name := _keysym_name(ks)
                if t == 2:
                    w._emit({"type": "key_down", "key": name, "repeat": w.key_down(name)})
                    n := f["XLookupString"].call([ev.address(), self.kbuf.address(), 31, self.ksym.address(), 0])
                    if n > 0:
                        txt := self.kbuf.read_bytes(0, n)
                        if _s.byte_len(txt) > 0 and _s.byte_at(txt, 0) >= 32 and _s.byte_at(txt, 0) != 127:
                            w._emit({"type": "char", "text": txt})
                else:
                    w._emit({"type": "key_up", "key": name, "repeat": false})
            elif t == 4 or t == 5:                                    # ButtonPress / ButtonRelease
                b := ev.read("u32", 84)
                bx := ev.read("i32", 64)
                by := ev.read("i32", 68)
                if b == 4 or b == 5:
                    if t == 4:
                        w._emit({"type": "wheel", "delta": 1 if b == 4 else -1})
                else:
                    name := "left" if b == 1 else ("middle" if b == 2 else "right")
                    w._emit({"type": "mouse_down" if t == 4 else "mouse_up", "button": name, "x": bx, "y": by})
            elif t == 6:                                              # MotionNotify
                mx := ev.read("i32", 64)
                my := ev.read("i32", 68)
                w._emit({"type": "mouse_move", "x": mx, "y": my, "dx": mx - w.mouse_x, "dy": my - w.mouse_y})
                w.mouse_x = mx
                w.mouse_y = my
            elif t == 22:                                             # ConfigureNotify
                cw := ev.read("i32", 56)
                ch := ev.read("i32", 60)
                if (cw != w.width or ch != w.height) and cw > 0 and ch > 0:
                    w._emit({"type": "resize", "width": cw, "height": ch})
            elif t == 9 or t == 10:                                   # FocusIn / FocusOut
                w._emit({"type": "focus", "focused": t == 9})
            elif t == 33:                                             # ClientMessage : WM_DELETE_WINDOW
                if ev.read("u64", 56) == self.wm_delete:
                    w._emit({"type": "close"})
                    w.close()

    func swap():
        self.f["glXSwapBuffers"].call2(self.dpy, self.win)

    func destroy():
        x := self.x
        self.f["glXMakeCurrent"].call3(self.dpy, 0, 0)
        self.glx.function("glXDestroyContext", ["ptr", "ptr"], "void").call2(self.dpy, self.ctx)
        x.function("XDestroyWindow", ["ptr", "u64"], "i32").call2(self.dpy, self.win)
        x.function("XCloseDisplay", ["ptr"], "i32").call1(self.dpy)
