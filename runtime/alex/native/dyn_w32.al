# alex: native
# Backend Win32 du module ui (runtime dynamique des exécutables Windows, dont alexvm.exe) : une fenêtre Win32
# par fenêtre ui, le framebuffer RGBA composé par le cœur (dyn_ui) affiché par SetDIBitsToDevice, messages
# traduits vers __ui_on_* (souris, clavier VK_* + WM_CHAR, taille, position, focus, état, fermeture, dépôt de
# fichiers). Même rôle que backend_x11 sous Linux ; seul ce fichier appelle __wincallback (cible Windows).
#
# État [c + 104] : [0] instance [8] classe (UTF-16) [16] hwnd -> id (dict) [24] id -> fenêtre (dict) [32] MSG
# [40] dernière fenêtre créée (propriétaire du presse-papiers)
# Fenêtre : [0] hwnd [8] tampon BGRX (raw) [16] taille du tampon [24] largeur [32] hauteur [40] style
# [48] curseur [56] plein écran [64] suivi de la sortie du pointeur [72] dernier état [80] style avant plein écran
# [88..112] rectangle avant plein écran [120] minW [128] minH [136] maxW [144] maxH [152] style étendu

func __w32_m32(v: int) -> int:
    return v & 4294967295

func __w32_s32(v: int) -> int:
    v = v & 4294967295
    if v >= 2147483648:
        return v - 4294967296
    return v

func __w32_open() -> int:
    b := __alloc(48)
    hinst := __wincall("GetModuleHandleW", 0)
    __store64(b, hinst)
    cls := __pw_wide("AlexUiPortable")
    __store64(b + 8, cls)
    __store64(b + 16, __rt_dict_new(8))
    __store64(b + 24, __rt_dict_new(8))
    __store64(b + 32, __alloc_raw(56))
    __store64(b + 40, 0)
    wc := __alloc_raw(80)
    __zero(wc, 80)
    __store32(wc, 3)                                              # CS_HREDRAW | CS_VREDRAW
    __store64(wc + 8, __wincallback("__w32_wndproc"))
    __store64(wc + 24, hinst)
    __store64(wc + 32, __wincall("user32.dll!LoadIconW", hinst, 1)) # icône n° 1 de l'exécutable (alexvm.exe : logo d'ALEX), sinon défaut
    __store64(wc + 40, __wincall("user32.dll!LoadCursorW", 0, 32512))
    __store64(wc + 64, cls)
    if __w32_m32(__wincall("user32.dll!RegisterClassW", wc)) == 0:
        return 0
    return b

func __w32_find(b: int, hwnd: int) -> int:
    d := __load64(b + 16)
    e := __rt_dict_index(d, hwnd, 0)
    if e < 0:
        return 0
    return __load64(__load64(d + 32) + 8 * e)

func __w32_win(b: int, id: int) -> int:
    return __ui_get(__load64(b + 24), id)

func __w32_style(resizable: bool, decorated: bool) -> int:
    if not decorated:
        return 2147483648                                         # WS_POPUP
    if resizable:
        return 13565952                                           # WS_OVERLAPPEDWINDOW
    return 13238272                                               # WS_CAPTION | WS_SYSMENU | WS_MINIMIZEBOX

# Taille de la fenêtre (cadre compris) pour une zone cliente w x h : out [0] largeur [8] hauteur [16] dx [24] dy.
func __w32_frame(style: int, ex: int, w: int, h: int, out: int):
    r := __alloc_raw(16)
    __zero(r, 16)
    __store32(r + 8, w)
    __store32(r + 12, h)
    __wincall("user32.dll!AdjustWindowRectEx", r, style, 0, ex)
    __store64(out, __w32_s32(__load32(r + 8)) - __w32_s32(__load32(r)))
    __store64(out + 8, __w32_s32(__load32(r + 12)) - __w32_s32(__load32(r + 4)))
    __store64(out + 16, __w32_s32(__load32(r)))
    __store64(out + 24, __w32_s32(__load32(r + 4)))

func __w32_create(b: int, id: int, title: str, w: int, h: int, resizable: bool):
    style := __w32_style(resizable, true)
    fr := __alloc(32)
    __w32_frame(style, 0, w, h, fr)
    hwnd := __wincall("user32.dll!CreateWindowExW", 0, __load64(b + 8), __pw_wide(title), style, 2147483648, 2147483648, __load64(fr), __load64(fr + 8), 0, 0, __load64(b), 0)
    if hwnd == 0:
        __ui_fail("ui.window_create() : CreateWindowExW a échoué", false)
    o := __alloc(160)
    __store64(o, hwnd)
    __store64(o + 40, style)
    __store64(o + 48, __wincall("user32.dll!LoadCursorW", 0, 32512))
    __ui_sets(o, 72, "normal")
    __rt_dict_set(__load64(b + 16), hwnd, id, 0)
    __rt_dict_set(__load64(b + 24), id, o, 0)
    __wincall("shell32.dll!DragAcceptFiles", hwnd, 1)
    __store64(b + 40, hwnd)

func __w32_destroy(b: int, id: int):
    o := __w32_win(b, id)
    if o == 0:
        return
    __rt_dict_remove(__load64(b + 16), __load64(o), 0)
    __rt_dict_remove(__load64(b + 24), id, 0)
    if __load64(b + 40) == __load64(o):
        __store64(b + 40, 0)
    __wincall("user32.dll!DestroyWindow", __load64(o))

func __w32_show(b: int, id: int, on: bool):
    o := __w32_win(b, id)
    if o == 0:
        return
    if on:
        __wincall("user32.dll!ShowWindow", __load64(o), 5)      # SW_SHOW
        __wincall("user32.dll!SetForegroundWindow", __load64(o))
    else:
        __wincall("user32.dll!ShowWindow", __load64(o), 0)

func __w32_title(b: int, id: int, t: str):
    o := __w32_win(b, id)
    if o != 0:
        __wincall("user32.dll!SetWindowTextW", __load64(o), __pw_wide(t))

func __w32_exstyle(o: int) -> int:
    return __load64(o + 152)

func __w32_resize(b: int, id: int, w: int, h: int):
    o := __w32_win(b, id)
    if o == 0:
        return
    fr := __alloc(32)
    __w32_frame(__load64(o + 40), __w32_exstyle(o), w, h, fr)
    __wincall("user32.dll!SetWindowPos", __load64(o), 0, 0, 0, __load64(fr), __load64(fr + 8), 22)   # NOMOVE NOZORDER NOACTIVATE

func __w32_move(b: int, id: int, x: int, y: int):
    o := __w32_win(b, id)
    if o == 0:
        return
    fr := __alloc(32)
    __w32_frame(__load64(o + 40), __w32_exstyle(o), 1, 1, fr)
    __wincall("user32.dll!SetWindowPos", __load64(o), 0, (x + __load64(fr + 16)) & 4294967295, (y + __load64(fr + 24)) & 4294967295, 0, 0, 21)

func __w32_cursor_id(name: str) -> int:
    if __rt_str_eq(name, "text"):
        return 32513
    if __rt_str_eq(name, "wait"):
        return 32514
    if __rt_str_eq(name, "crosshair"):
        return 32515
    if __rt_str_eq(name, "resize_h"):
        return 32644
    if __rt_str_eq(name, "resize_v"):
        return 32645
    if __rt_str_eq(name, "move") or __rt_str_eq(name, "grabbing"):
        return 32646
    if __rt_str_eq(name, "not_allowed"):
        return 32648
    if __rt_str_eq(name, "pointer") or __rt_str_eq(name, "grab"):
        return 32649
    return 32512

func __w32_cursor(b: int, id: int, name: str):
    o := __w32_win(b, id)
    if o == 0:
        return
    h := __wincall("user32.dll!LoadCursorW", 0, __w32_cursor_id(name))
    __store64(o + 48, h)
    __wincall("user32.dll!SetCursor", h)

func __w32_blit(o: int, hdc: int):
    w := __load64(o + 24)
    h := __load64(o + 32)
    if w <= 0 or h <= 0 or __load64(o + 8) == 0:
        return
    bmi := __alloc_raw(48)
    __zero(bmi, 44)
    __store32(bmi, 40)
    __store32(bmi + 4, w)
    __store32(bmi + 8, (0 - h) & 4294967295)                      # de haut en bas
    __store16(bmi + 12, 1)
    __store16(bmi + 14, 32)
    __wincall("gdi32.dll!SetDIBitsToDevice", hdc, 0, 0, w, h, 0, 0, 0, h, __load64(o + 8), bmi, 0)

func __w32_present(b: int, id: int, f: int):
    o := __w32_win(b, id)
    if o == 0:
        return
    w := __us_w(f)
    h := __us_h(f)
    n := w * h
    if __load64(o + 16) < n * 4:
        __store64(o + 8, __alloc_raw(n * 4 + 8))
        __store64(o + 16, n * 4)
    d := __load64(o + 8)
    s := __us_px(f)
    i := 0
    while i < n:
        px := __load32(s)
        a := px >> 24
        r := px & 255
        g := (px >> 8) & 255
        bl := (px >> 16) & 255
        if a != 255:
            ia := 255 - a
            r = (r * a + 255 * ia) // 255
            g = (g * a + 255 * ia) // 255
            bl = (bl * a + 255 * ia) // 255
        __store32(d, bl | (g << 8) | (r << 16))
        s += 4
        d += 4
        i += 1
    __store64(o + 24, w)
    __store64(o + 32, h)
    hdc := __wincall("user32.dll!GetDC", __load64(o))
    __w32_blit(o, hdc)
    __wincall("user32.dll!ReleaseDC", __load64(o), hdc)

func __w32_dispatch(b: int, msg: int):
    __wincall("user32.dll!TranslateMessage", msg)
    __wincall("user32.dll!DispatchMessageW", msg)

func __w32_pump(c: int, b: int, block: bool):
    msg := __load64(b + 32)
    if block and __w32_m32(__wincall("user32.dll!PeekMessageW", msg, 0, 0, 0, 0)) == 0:
        if __w32_s32(__wincall("user32.dll!GetMessageW", msg, 0, 0, 0)) > 0:
            __w32_dispatch(b, msg)
    while __w32_m32(__wincall("user32.dll!PeekMessageW", msg, 0, 0, 0, 1)) != 0:
        if __load32(msg + 8) == 18:                               # WM_QUIT
            continue
        __w32_dispatch(b, msg)

func __w32_wait(b: int, ms: int):
    if __w32_m32(__wincall("user32.dll!PeekMessageW", __load64(b + 32), 0, 0, 0, 0)) != 0:
        return
    __wincall("user32.dll!MsgWaitForMultipleObjects", 0, 0, 0, ms, 1279)   # QS_ALLINPUT

func __w32_position(b: int, id: int, out: int) -> bool:
    o := __w32_win(b, id)
    if o == 0:
        return false
    pt := __alloc_raw(8)
    __zero(pt, 8)
    if __w32_m32(__wincall("user32.dll!ClientToScreen", __load64(o), pt)) == 0:
        return false
    __store64(out, __w32_s32(__load32(pt)))
    __store64(out + 8, __w32_s32(__load32(pt + 4)))
    return true

func __w32_screen(b: int, out: int):
    __store64(out, __w32_s32(__wincall("user32.dll!GetSystemMetrics", 0)))
    __store64(out + 8, __w32_s32(__wincall("user32.dll!GetSystemMetrics", 1)))
    r := __alloc_raw(16)
    __zero(r, 16)
    if __w32_m32(__wincall("user32.dll!SystemParametersInfoW", 48, 0, r, 0)) != 0:
        __store64(out + 16, __w32_s32(__load32(r + 8)) - __w32_s32(__load32(r)))
        __store64(out + 24, __w32_s32(__load32(r + 12)) - __w32_s32(__load32(r + 4)))
    else:
        __store64(out + 16, __load64(out))
        __store64(out + 24, __load64(out + 8))

func __w32_dpi(b: int) -> int:
    v := __w32_m32(__wincall("user32.dll!GetDpiForSystem"))
    if v < 48 or v > 960:
        return 96
    return v

func __w32_set_state(b: int, id: int, state: str) -> bool:
    o := __w32_win(b, id)
    if o == 0:
        return false
    hwnd := __load64(o)
    if __load64(o + 56) != 0 and not __rt_str_eq(state, "fullscreen"):
        # sortie du plein écran : style et rectangle d'avant
        __store64(o + 56, 0)
        __store64(o + 40, __load64(o + 80))
        __wincall("user32.dll!SetWindowLongPtrW", hwnd, (0 - 16) & 4294967295, __load64(o + 80) | 268435456)
        __wincall("user32.dll!SetWindowPos", hwnd, 0, __load64(o + 88) & 4294967295, __load64(o + 96) & 4294967295, __load64(o + 104), __load64(o + 112), 36)   # NOZORDER FRAMECHANGED
    __ui_sets(o, 72, state)
    if __rt_str_eq(state, "minimized"):
        __wincall("user32.dll!ShowWindow", hwnd, 6)
    elif __rt_str_eq(state, "maximized"):
        __wincall("user32.dll!ShowWindow", hwnd, 3)
    elif __rt_str_eq(state, "normal"):
        __wincall("user32.dll!ShowWindow", hwnd, 9)
    else:
        r := __alloc_raw(16)
        __wincall("user32.dll!ShowWindow", hwnd, 9)
        __wincall("user32.dll!GetWindowRect", hwnd, r)
        __store64(o + 88, __w32_s32(__load32(r)))
        __store64(o + 96, __w32_s32(__load32(r + 4)))
        __store64(o + 104, __w32_s32(__load32(r + 8)) - __w32_s32(__load32(r)))
        __store64(o + 112, __w32_s32(__load32(r + 12)) - __w32_s32(__load32(r + 4)))
        __store64(o + 80, __load64(o + 40))
        __store64(o + 56, 1)
        __store64(o + 40, 2147483648)
        __wincall("user32.dll!SetWindowLongPtrW", hwnd, (0 - 16) & 4294967295, 2147483648 | 268435456)   # WS_POPUP | WS_VISIBLE
        sw := __w32_s32(__wincall("user32.dll!GetSystemMetrics", 0))
        sh := __w32_s32(__wincall("user32.dll!GetSystemMetrics", 1))
        __wincall("user32.dll!SetWindowPos", hwnd, 0, 0, 0, sw, sh, 100)   # NOZORDER FRAMECHANGED SHOWWINDOW
    return true

func __w32_hints(b: int, id: int, resizable: bool, decorated: bool, topmost: bool, opacity: float, minW: int, minH: int, maxW: int, maxH: int, cw: int, ch: int):
    o := __w32_win(b, id)
    if o == 0:
        return
    hwnd := __load64(o)
    __store64(o + 120, minW)
    __store64(o + 128, minH)
    __store64(o + 136, maxW)
    __store64(o + 144, maxH)
    style := __w32_style(resizable, decorated)
    if __w32_m32(__wincall("user32.dll!IsWindowVisible", hwnd)) != 0:
        style = style | 268435456
    __store64(o + 40, style & 4026531839)
    __wincall("user32.dll!SetWindowLongPtrW", hwnd, (0 - 16) & 4294967295, style)
    ex := 0
    if opacity < 1.0:
        ex = 524288                                              # WS_EX_LAYERED
    __store64(o + 152, ex)
    __wincall("user32.dll!SetWindowLongPtrW", hwnd, (0 - 20) & 4294967295, ex)
    if opacity < 1.0:
        __wincall("user32.dll!SetLayeredWindowAttributes", hwnd, 0, __f2i(opacity * 255.0 + 0.5), 2)
    after := -2                                                  # HWND_NOTOPMOST
    if topmost:
        after = -1                                               # HWND_TOPMOST
    fr := __alloc(32)
    __w32_frame(__load64(o + 40), ex, cw, ch, fr)
    __wincall("user32.dll!SetWindowPos", hwnd, after, 0, 0, __load64(fr), __load64(fr + 8), 50)   # NOMOVE NOACTIVATE FRAMECHANGED

func __w32_focus(b: int, id: int):
    o := __w32_win(b, id)
    if o == 0:
        return
    __wincall("user32.dll!SetForegroundWindow", __load64(o))
    __wincall("user32.dll!SetFocus", __load64(o))

func __w32_mods() -> int:
    m := 0
    if (__wincall("user32.dll!GetKeyState", 18) & 32768) != 0:
        m = m | 1
    if (__wincall("user32.dll!GetKeyState", 17) & 32768) != 0:
        m = m | 2
    if (__wincall("user32.dll!GetKeyState", 16) & 32768) != 0:
        m = m | 4
    if (__wincall("user32.dll!GetKeyState", 91) & 32768) != 0 or (__wincall("user32.dll!GetKeyState", 92) & 32768) != 0:
        m = m | 8
    return m

# Caractères WM_CHAR en attente (après TranslateMessage) : texte UTF-8, vide pour les caractères de contrôle.
func __w32_chars(hwnd: int) -> str:
    msg := __alloc_raw(56)
    sb := __rt_sb_new()
    hi := 0
    while __w32_m32(__wincall("user32.dll!PeekMessageW", msg, hwnd, 258, 258, 1)) != 0:
        u := __load64(msg + 16) & 65535
        if u >= 55296 and u <= 56319:
            hi = u
            continue
        cp := u
        if u >= 56320 and u <= 57343 and hi != 0:
            cp = 65536 + ((hi - 55296) << 10) + (u - 56320)
        hi = 0
        if cp >= 32 and cp != 127:
            __nat_sb_cp(sb, cp)
    return __rt_sb_str(sb)

func __w32_xy(lp: int, out: int):
    __store64(out, __x_s16(lp & 65535))
    __store64(out + 8, __x_s16((lp >> 16) & 65535))

func __w32_wndproc(hwnd: int, msg: int, wp: int, lp: int) -> int:
    m := __w32_m32(msg)
    c := __ui_core()
    b := __load64(c + 104)
    if b == 0 or __load64(c + 8) != 3:
        return __wincall("user32.dll!DefWindowProcW", hwnd, m, wp, lp)
    id := __w32_find(b, hwnd)
    if id == 0:
        return __wincall("user32.dll!DefWindowProcW", hwnd, m, wp, lp)
    o := __w32_win(b, id)
    if m == 16:                                                  # WM_CLOSE
        w := __ui_find_win(c, id)
        if w != 0 and __load64(w + 48) != 0:
            __ui_on_close_request(c, id)
            if __load64(w + 48) == 0:
                __w32_destroy(b, id)
        return 0
    if m == 15:                                                  # WM_PAINT
        ps := __alloc_raw(80)
        hdc := __wincall("user32.dll!BeginPaint", hwnd, ps)
        __w32_blit(o, hdc)
        __wincall("user32.dll!EndPaint", hwnd, ps)
        w := __ui_find_win(c, id)
        if w != 0 and __load64(o + 8) == 0:
            __store64(w + 64, 1)
        return 0
    if m == 20:                                                  # WM_ERASEBKGND
        return 1
    if m == 5:                                                   # WM_SIZE
        cw := lp & 65535
        ch := (lp >> 16) & 65535
        if wp != 1 and cw > 0 and ch > 0:
            __ui_on_resize(c, id, cw, ch)
        if __load64(o + 56) == 0:
            st := "normal"
            if wp == 1:
                st = "minimized"
            elif wp == 2:
                st = "maximized"
            if wp <= 2 and not __rt_str_eq(__ui_s(o, 72), st):
                __ui_sets(o, 72, st)
                __ui_on_state(c, id, st)
        return 0
    if m == 3:                                                   # WM_MOVE (zone cliente, écran)
        pt := __alloc(16)
        __w32_xy(lp, pt)
        __ui_on_move(c, id, __load64(pt), __load64(pt + 8))
        return 0
    if m == 7 or m == 8:                                         # WM_SETFOCUS / WM_KILLFOCUS
        __ui_on_focus(c, id, m == 7)
        return 0
    if m == 36:                                                  # WM_GETMINMAXINFO
        if __load64(o + 120) > 0 or __load64(o + 128) > 0 or __load64(o + 136) > 0 or __load64(o + 144) > 0:
            fr := __alloc(32)
            if __load64(o + 120) > 0 or __load64(o + 128) > 0:
                __w32_frame(__load64(o + 40), __w32_exstyle(o), __load64(o + 120), __load64(o + 128), fr)
                __store32(lp + 24, __load64(fr))
                __store32(lp + 28, __load64(fr + 8))
            if __load64(o + 136) > 0 or __load64(o + 144) > 0:
                mw := __load64(o + 136)
                if mw <= 0:
                    mw = 32767
                mh := __load64(o + 144)
                if mh <= 0:
                    mh = 32767
                __w32_frame(__load64(o + 40), __w32_exstyle(o), mw, mh, fr)
                __store32(lp + 32, __load64(fr))
                __store32(lp + 36, __load64(fr + 8))
        return 0
    if m == 32:                                                  # WM_SETCURSOR
        if (lp & 65535) == 1:
            __wincall("user32.dll!SetCursor", __load64(o + 48))
            return 1
        return __wincall("user32.dll!DefWindowProcW", hwnd, m, wp, lp)
    if m == 512:                                                 # WM_MOUSEMOVE
        if __load64(o + 64) == 0:
            tme := __alloc_raw(24)
            __store32(tme, 24)
            __store32(tme + 4, 2)                                # TME_LEAVE
            __store64(tme + 8, hwnd)
            __store32(tme + 16, 0)
            __wincall("user32.dll!TrackMouseEvent", tme)
            __store64(o + 64, 1)
        pt := __alloc(16)
        __w32_xy(lp, pt)
        __ui_on_mouse(c, id, 0, __load64(pt), __load64(pt + 8), 0, __w32_mods())
        return 0
    if m == 675:                                                 # WM_MOUSELEAVE
        __store64(o + 64, 0)
        __ui_on_mouse(c, id, 5, 0, 0, 0, __w32_mods())
        return 0
    if m == 513 or m == 514 or m == 516 or m == 517 or m == 519 or m == 520:
        pt := __alloc(16)
        __w32_xy(lp, pt)
        bt := 1
        if m == 516 or m == 517:
            bt = 2
        elif m == 519 or m == 520:
            bt = 3
        down := m == 513 or m == 516 or m == 519
        ty := 2
        if down:
            ty = 1
            __wincall("user32.dll!SetCapture", hwnd)
        else:
            __wincall("user32.dll!ReleaseCapture")
        __ui_on_mouse(c, id, ty, __load64(pt), __load64(pt + 8), bt, __w32_mods())
        return 0
    if m == 522 or m == 526:                                     # WM_MOUSEWHEEL / WM_MOUSEHWHEEL (écran)
        pt := __alloc_raw(8)
        __store32(pt, __x_s16(lp & 65535) & 4294967295)
        __store32(pt + 4, __x_s16((lp >> 16) & 65535) & 4294967295)
        __wincall("user32.dll!ScreenToClient", hwnd, pt)
        delta := __x_s16((wp >> 16) & 65535)
        n := delta // 120
        if delta < 0:
            n = 0 - ((0 - delta) // 120)
        if n == 0:
            if delta > 0:
                n = 1
            elif delta < 0:
                n = -1
        ty := 3
        if m == 526:
            ty = 4
        step := 1
        if n < 0:
            step = -1
        k := 0
        while k != n:
            __ui_on_mouse(c, id, ty, __w32_s32(__load32(pt)), __w32_s32(__load32(pt + 4)), step, __w32_mods())
            k += step
        return 0
    if m == 256 or m == 260:                                     # WM_KEYDOWN / WM_SYSKEYDOWN
        vk := wp & 255
        if vk == 16 or vk == 17 or vk == 18 or vk == 91 or vk == 92:
            vk = 0
        __ui_on_key(c, id, vk, __w32_mods(), __w32_chars(hwnd))
        if m == 260:
            return __wincall("user32.dll!DefWindowProcW", hwnd, m, wp, lp)
        return 0
    if m == 258:                                                 # WM_CHAR isolé (méthode de saisie)
        u := wp & 65535
        if u >= 32 and u != 127 and (u < 55296 or u > 57343):
            sb := __rt_sb_new()
            __nat_sb_cp(sb, u)
            __ui_on_key(c, id, 0, __w32_mods(), __rt_sb_str(sb))
        return 0
    if m == 257 or m == 261:                                     # WM_KEYUP / WM_SYSKEYUP
        __ui_on_key_up(c, id, wp & 255, __w32_mods())
        if m == 261:
            return __wincall("user32.dll!DefWindowProcW", hwnd, m, wp, lp)
        return 0
    if m == 563:                                                 # WM_DROPFILES
        nf := __w32_m32(__wincall("shell32.dll!DragQueryFileW", wp, 4294967295, 0, 0))
        i := 0
        while i < nf:
            ln := __w32_m32(__wincall("shell32.dll!DragQueryFileW", wp, i, 0, 0))
            buf := __alloc_raw(2 * ln + 8)
            __wincall("shell32.dll!DragQueryFileW", wp, i, buf, ln + 1)
            w := __ui_find_win(c, id)
            if w != 0:
                __ui_push_simple(w, "drop", 0, __pw_narrow(buf, ln))
            i += 1
        __wincall("shell32.dll!DragFinish", wp)
        return 0
    return __wincall("user32.dll!DefWindowProcW", hwnd, m, wp, lp)

# ---- presse-papiers du système (CF_UNICODETEXT = 13) ----
# Propriétaire : une fenêtre du programme (EmptyClipboard avec une fenêtre nulle fait échouer SetClipboardData).
func __w32_clip_owner(b: int) -> int:
    h := 0
    if b != 0:
        h = __load64(b + 40)
    if h == 0:
        h = __wincall("user32.dll!GetActiveWindow")
    return h

# Un autre programme peut tenir le presse-papiers un court instant : quelques essais.
func __w32_clip_open(b: int) -> bool:
    k := 0
    while k < 10:
        if __w32_m32(__wincall("user32.dll!OpenClipboard", __w32_clip_owner(b))) != 0:
            return true
        __wincall("Sleep", 10)
        k += 1
    return false

# Écrit `text` (UTF-8, fins de ligne converties en CR LF) ; vrai si le presse-papiers a été rempli.
func __w32_clip_set(b: int, text: str) -> bool:
    sb := __rt_sb_new()
    p := __nat_bp(text)
    n := __nat_blen(text)
    prev := 0
    q := 0
    while q < n:
        ch := __load8(p + q)
        if ch == 10 and prev != 13:
            __rt_sb_byte(sb, 13)
        __rt_sb_byte(sb, ch)
        prev = ch
        q += 1
    w := __pw_wide(__rt_sb_str(sb))
    if w == 0:
        return false
    nw := 0
    while __load16(w + 2 * nw) != 0:
        nw += 1
    if not __w32_clip_open(b):
        return false
    ok := false
    __wincall("user32.dll!EmptyClipboard")
    g := __wincall("GlobalAlloc", 2, 2 * nw + 2)                 # GMEM_MOVEABLE
    if g != 0:
        d := __wincall("GlobalLock", g)
        if d != 0:
            i := 0
            while i <= nw:
                __store16(d + 2 * i, __load16(w + 2 * i))
                i += 1
            __wincall("GlobalUnlock", g)
            if __wincall("user32.dll!SetClipboardData", 13, g) != 0:
                ok = true
        if not ok:
            __wincall("GlobalFree", g)
    __wincall("user32.dll!CloseClipboard")
    return ok

# Texte du presse-papiers (adresse de chaîne UTF-8, CR LF -> LF), ou 0 s'il ne contient pas de texte.
func __w32_clip_get(b: int) -> int:
    if __w32_m32(__wincall("user32.dll!IsClipboardFormatAvailable", 13)) == 0:
        return 0
    if not __w32_clip_open(b):
        return 0
    r := 0
    h := __wincall("user32.dll!GetClipboardData", 13)
    if h != 0:
        d := __wincall("GlobalLock", h)
        if d != 0:
            nw := 0
            while __load16(d + 2 * nw) != 0:
                nw += 1
            s := __pw_narrow(d, nw)
            __wincall("GlobalUnlock", h)
            sb := __rt_sb_new()
            sp := __nat_bp(s)
            q := 0
            while q < __nat_blen(s):
                ch := __load8(sp + q)
                if ch != 13 or q + 1 >= __nat_blen(s) or __load8(sp + q + 1) != 10:
                    __rt_sb_byte(sb, ch)
                q += 1
            r = __str_addr(__rt_sb_str(sb))
    __wincall("user32.dll!CloseClipboard")
    return r
