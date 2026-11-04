from collections use contains_key
_handlers: dict[int, func()] := {}
_next_id: int := 100
_main: int := 0
_class: int := 0
_font: int := 0
_dpi: int := 96
_hinst: int := 0

func _m32(x: int) -> int:
    return x & 4294967295

func _s32(x: int) -> int:
    x = x & 4294967295
    if x >= 2147483648:
        return x - 4294967296
    return x

# Chaîne UTF-8 -> UTF-16 terminée par un zéro (tas).
func _w(s: str) -> int:
    p := __str_addr(s)
    n := __load64(p)
    c := __alloc_raw(n + 1)
    __copy(c, p + 8, n)
    __store8(c + n, 0)
    k := _m32(__wincall("MultiByteToWideChar", 65001, 0, c, -1, 0, 0))
    w := __alloc_raw(2 * k + 2)
    __wincall("MultiByteToWideChar", 65001, 0, c, -1, w, k)
    return w

func _px(v: int) -> int:
    return v * _dpi // 96

func _init():
    if _class != 0:
        return
    _hinst = __wincall("GetModuleHandleW", 0)
    _dpi = _m32(__wincall("user32.dll!GetDpiForSystem"))
    if _dpi <= 0:
        _dpi = 96
    _class = _w("AlexFenetre")
    wc := __alloc_raw(80)
    __zero(wc, 80)
    __store32(wc, 3)                                                  # CS_HREDRAW | CS_VREDRAW
    __store64(wc + 8, __wincallback("_wndproc"))
    __store64(wc + 24, _hinst)
    __store64(wc + 32, __wincall("user32.dll!LoadIconW", _hinst, 1))  # icône n° 1 de l'exécutable (--icon), sinon 0 : défaut
    __store64(wc + 40, __wincall("user32.dll!LoadCursorW", 0, 32512)) # IDC_ARROW
    __store64(wc + 48, 16)                                            # COLOR_BTNFACE + 1
    __store64(wc + 64, _class)
    if _m32(__wincall("user32.dll!RegisterClassW", wc)) == 0:
        raise("OSError", "wingui : RegisterClassW a échoué")
    _font = font(10)

# Police « Segoe UI » de `size` points (DPI du système), grasse si bold.
func font(size: int, bold: bool = false) -> int:
    weight := 400
    if bold:
        weight = 700
    h := 0 - size * _dpi // 72
    return __wincall("gdi32.dll!CreateFontW", h, 0, 0, 0, weight, 0, 0, 0, 1, 0, 0, 5, 0, _w("Segoe UI"))

func set_font(ctrl: int, f: int):
    __wincall("user32.dll!SendMessageW", ctrl, 48, f, 1)              # WM_SETFONT

# Fenêtre principale de taille intérieure width x height, non redimensionnable ; la première créée termine
# la boucle de messages quand elle est fermée. Créée cachée : show() (ou run() pour la principale) l'affiche
# une fois ses contrôles en place.
func window(title: str, width: int, height: int) -> int:
    _init()
    style := 13238272                                                 # WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX
    r := __alloc_raw(16)
    __zero(r, 16)
    __store32(r + 8, _px(width))
    __store32(r + 12, _px(height))
    __wincall("user32.dll!AdjustWindowRect", r, style, 0)
    ww := _s32(__load32(r + 8)) - _s32(__load32(r))
    wh := _s32(__load32(r + 12)) - _s32(__load32(r + 4))
    hwnd := __wincall("user32.dll!CreateWindowExW", 65536, _class, _w(title), style, 2147483648, 2147483648, ww, wh, 0, 0, _hinst, 0)
    if hwnd == 0:
        raise("OSError", "wingui : CreateWindowExW a échoué")
    if _main == 0:
        _main = hwnd
    return hwnd

func _child(cls: str, text: str, style: int, ex: int, parent: int, x: int, y: int, w: int, h: int) -> int:
    id := _next_id
    _next_id += 1
    c := __wincall("user32.dll!CreateWindowExW", ex, _w(cls), _w(text), 1342177280 | style, _px(x), _px(y), _px(w), _px(h), parent, id, _hinst, 0)
    if c == 0:
        raise("OSError", "wingui : création du contrôle " + cls + " impossible")
    set_font(c, _font)
    return c

# Texte statique (right : aligné à droite).
func label(parent: int, text: str, x: int, y: int, w: int, h: int, right: bool = false) -> int:
    style := 0
    if right:
        style = 2                                                     # SS_RIGHT
    return _child("STATIC", text, style, 0, parent, x, y, w, h)

# Champ de saisie d'une ligne (readonly : lecture seule ; right : aligné à droite).
func edit(parent: int, text: str, x: int, y: int, w: int, h: int, readonly: bool = false, right: bool = false) -> int:
    style := 65664                                                    # WS_TABSTOP | ES_AUTOHSCROLL
    if readonly:
        style = style | 2048
    if right:
        style = style | 2
    return _child("EDIT", text, style, 512, parent, x, y, w, h)       # WS_EX_CLIENTEDGE

# Bouton ; on_click est appelé à chaque clic.
func button(parent: int, text: str, x: int, y: int, w: int, h: int, on_click: func()) -> int:
    b := _child("BUTTON", text, 65536, 0, parent, x, y, w, h)          # WS_TABSTOP | BS_PUSHBUTTON
    _handlers[_m32(__wincall("user32.dll!GetDlgCtrlID", b))] = on_click
    return b

func set_text(ctrl: int, text: str):
    __wincall("user32.dll!SetWindowTextW", ctrl, _w(text))

func get_text(ctrl: int) -> str:
    n := _m32(__wincall("user32.dll!GetWindowTextLengthW", ctrl))
    w := __alloc_raw(2 * n + 2)
    k := _m32(__wincall("user32.dll!GetWindowTextW", ctrl, w, n + 1))
    if k == 0:
        return ""
    m := _m32(__wincall("WideCharToMultiByte", 65001, 0, w, k, 0, 0, 0, 0))
    r := __rt_str_new(m)
    __wincall("WideCharToMultiByte", 65001, 0, w, k, r + 8, m, 0, 0)
    return __as_str(r)

func enable(ctrl: int, on: bool):
    v := 0
    if on:
        v = 1
    __wincall("user32.dll!EnableWindow", ctrl, v)

# Clic sur un bouton comme à la souris (BM_CLICK) : Windows envoie WM_COMMAND à la fenêtre parente.
func click(ctrl: int):
    __wincall("user32.dll!SendMessageW", ctrl, 245, 0, 0)

# Image de la fenêtre (cadre compris), dessinée par Windows (PrintWindow), enregistrée en BMP 32 bits.
func capture(win: int, path: str):
    show(win)
    r := __alloc_raw(16)
    __wincall("user32.dll!GetWindowRect", win, r)
    w := _s32(__load32(r + 8)) - _s32(__load32(r))
    h := _s32(__load32(r + 12)) - _s32(__load32(r + 4))
    screen := __wincall("user32.dll!GetDC", 0)
    dc := __wincall("gdi32.dll!CreateCompatibleDC", screen)
    bm := __wincall("gdi32.dll!CreateCompatibleBitmap", screen, w, h)
    old := __wincall("gdi32.dll!SelectObject", dc, bm)
    __wincall("user32.dll!PrintWindow", win, dc, 2)                   # PW_RENDERFULLCONTENT
    __wincall("gdi32.dll!SelectObject", dc, old)
    size := w * h * 4
    f := __alloc_raw(54 + size)
    __zero(f, 54)
    __store16(f, 19778)                                               # « BM »
    __store32(f + 2, 54 + size)
    __store32(f + 10, 54)
    __store32(f + 14, 40)                                             # BITMAPINFOHEADER
    __store32(f + 18, w)
    __store32(f + 22, 0 - h)                                          # hauteur négative : lignes de haut en bas
    __store16(f + 26, 1)
    __store16(f + 28, 32)
    __store32(f + 34, size)
    n := _m32(__wincall("gdi32.dll!GetDIBits", dc, bm, 0, h, f + 54, f + 14, 0))
    __wincall("gdi32.dll!DeleteObject", bm)
    __wincall("gdi32.dll!DeleteDC", dc)
    __wincall("user32.dll!ReleaseDC", 0, screen)
    if n == 0:
        raise("OSError", "wingui.capture : GetDIBits a échoué")
    fh := __wincall("CreateFileW", _w(path), 1073741824, 0, 0, 2, 128, 0)
    if fh == -1:
        raise("OSError", "wingui.capture : impossible d'écrire '" + path + "'")
    done := __alloc_raw(8)
    __wincall("WriteFile", fh, f, 54 + size, done, 0)
    __wincall("CloseHandle", fh)

# Boîte de message (information) ; attend que l'utilisateur la ferme.
func message(parent: int, title: str, text: str):
    __wincall("user32.dll!MessageBoxW", parent, _w(text), _w(title), 64)

func show(win: int):
    __wincall("user32.dll!ShowWindow", win, 1)                        # SW_SHOWNORMAL
    __wincall("user32.dll!UpdateWindow", win)

func close(win: int):
    __wincall("user32.dll!SendMessageW", win, 16, 0, 0)               # WM_CLOSE

# Boucle de messages : jusqu'à la fermeture de la fenêtre principale ; Tab passe d'un contrôle à l'autre.
func run() -> int:
    if _main != 0 and _m32(__wincall("user32.dll!IsWindow", _main)) != 0:
        show(_main)
    msg := __alloc_raw(48)
    while true:
        r := _m32(__wincall("user32.dll!GetMessageW", msg, 0, 0, 0))
        if r == 0 or r == 4294967295:
            break
        if _main == 0 or _m32(__wincall("user32.dll!IsDialogMessageW", _main, msg)) == 0:
            __wincall("user32.dll!TranslateMessage", msg)
            __wincall("user32.dll!DispatchMessageW", msg)
    return __load64(msg + 16)

# Procédure de fenêtre (appelée par Windows).
func _wndproc(hwnd: int, msg: int, wp: int, lp: int) -> int:
    m := _m32(msg)
    if m == 273:                                                      # WM_COMMAND
        id := wp & 65535
        if ((wp >> 16) & 65535) == 0 and contains_key(_handlers, id): # BN_CLICKED
            f := _handlers[id]
            f()
            return 0
    if m == 2:                                                        # WM_DESTROY
        if hwnd == _main:
            __wincall("user32.dll!PostQuitMessage", 0)
        return 0
    return __wincall("user32.dll!DefWindowProcW", hwnd, m, wp, lp)
