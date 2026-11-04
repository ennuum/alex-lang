

# ---- arguments (messages de ui_native.cpp) ----

func __ui_int(fn: str, v: int, label: str) -> int:
    if not __dyn_is(v, 1):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un int")
    return __dyn_iv(v)

# (int) d'un int64 : 32 bits de poids faible, signés.
func __ui_trunc32(v: int) -> int:
    return ((v & 4294967295) ^ 2147483648) - 2147483648

func __ui_i32(fn: str, v: int, label: str) -> int:
    return __ui_trunc32(__ui_int(fn, v, label))

func __ui_num(fn: str, v: int, label: str) -> float:
    if __dyn_is(v, 1):
        return __i2f(__dyn_iv(v))
    if __dyn_is(v, 2):
        return __dyn_fv(v)
    __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un nombre")
    return 0.0

func __ui_bool(fn: str, v: int, label: str) -> bool:
    if not __dyn_is(v, 3):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un bool")
    return __load64(v + 8) != 0

func __ui_str(fn: str, v: int, label: str) -> str:
    if not __dyn_is_str(v):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être une str")
    return __dyn_sv(v)

func __ui_handle(fn: str, v: int) -> int:
    if not __dyn_is(v, 1) or __dyn_iv(v) <= 0:
        __dyn_err("TypeError", "'" + fn + "' : handle UI invalide")
    return __dyn_iv(v)

# UiError : argument -> ArgumentError, sinon IoError.
func __ui_fail(m: str, arg: bool):
    if arg:
        __dyn_err("ArgumentError", m)
    __dyn_err("IoError", m)

# Arguments d'une native à signature complète : tableau de n valeurs.
func __ui_args(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int, x: int) -> int:
    v := __alloc(8 * n + 8)
    i := 0
    while i < n:
        __store64(v + 8 * i, __dyn_argi(i, a0, a1, a2, a3, a4, a5, a6, a7, x))
        i += 1
    return v

func __ui_at(v: int, i: int) -> int:
    return __load64(v + 8 * i)

func __ui_s(p: int, off: int) -> str:
    return __as_str(__load64(p + off))

func __ui_sets(p: int, off: int, s: str):
    __store64(p + off, __str_addr(s))

func __ui_env_set(name: str) -> bool:
    return __nat_env_find(name) >= 0

# ---- cœur : [0] init tentée [8] backend (1 headless, 2 x11, 3 win32) [16] erreur [24] fenêtres [32] widgets [40] menus
# [48] canvas [56] chemins [64] images [72] prochain id [80] dernière fenêtre [88] presse-papiers [96] présent
# [104] état du backend (dyn_x11 / win32) ----

func __ui_core() -> int:
    ds := __dyn_ds()
    c := __load64(ds + 456)
    if c != 0:
        return c
    c = __alloc(120)
    __ui_sets(c, 16, "")
    __store64(c + 24, __rt_dict_new(8))
    __store64(c + 32, __rt_dict_new(8))
    __store64(c + 40, __rt_dict_new(8))
    __store64(c + 48, __rt_dict_new(8))
    __store64(c + 56, __rt_dict_new(8))
    __store64(c + 64, __rt_dict_new(8))
    __store64(c + 72, 1)
    __ui_sets(c, 88, "")
    __store64(ds + 456, c)
    return c

func __ui_new_id(c: int) -> int:
    id := __load64(c + 72)
    __store64(c + 72, id + 1)
    return id

func __ui_get(d: int, id: int) -> int: # valeur, ou 0
    e := __rt_dict_index(d, id, 0)
    if e < 0:
        return 0
    return __load64(__load64(d + 32) + 8 * e)

func __ui_init(c: int):
    if __load64(c) != 0:
        return
    __store64(c, 1)
    want := "auto"
    if __ui_env_set("ALEX_UI_BACKEND"):
        want = __nat_env_get("ALEX_UI_BACKEND", "")
    want = __nat_case(want, 1)
    if __rt_str_eq(want, "headless"):
        __store64(c + 8, 1)
        return
    if __windows() and (__rt_str_eq(want, "auto") or __nat_blen(want) == 0 or __rt_str_eq(want, "win32")):
        b := __w32_open()
        if b != 0:
            __store64(c + 104, b)
            __store64(c + 8, 3)
            return
        __ui_sets(c, 16, "impossible de créer la classe de fenêtre Win32 — utilisez ALEX_UI_BACKEND=headless pour un rendu hors écran")
        return
    if __rt_str_eq(want, "x11") or __rt_str_eq(want, "auto") or __nat_blen(want) == 0:
        eb := __alloc(16)
        x := __x_open(eb)
        if x != 0:
            __store64(c + 104, x)
            __store64(c + 8, 2)
            return
        err := __ui_s(eb, 0)
        if __rt_str_eq(want, "x11"):
            __ui_sets(c, 16, err)
            return
        __ui_sets(c, 16, err + " — utilisez ALEX_UI_BACKEND=headless pour un rendu hors écran")
        return
    __ui_sets(c, 16, "ALEX_UI_BACKEND='" + want + "' inconnu (valeurs : auto, x11, headless)")

# ---- backend (Backend de backend.hpp) : headless sans effet, x11 (dyn_x11), win32 (__w32_*) ----

func __ui_interactive(c: int) -> bool:
    return __load64(c + 8) >= 2

func __ub_create(c: int, id: int, title: str, w: int, h: int, resizable: bool):
    if __load64(c + 8) == 2:
        __x_create(__load64(c + 104), id, title, w, h, resizable)
    elif __load64(c + 8) == 3:
        __w32_create(__load64(c + 104), id, title, w, h, resizable)

func __ub_destroy(c: int, id: int):
    if __load64(c + 8) == 2:
        __x_destroy(__load64(c + 104), id)
    elif __load64(c + 8) == 3:
        __w32_destroy(__load64(c + 104), id)

func __ub_show(c: int, id: int, on: bool):
    if __load64(c + 8) == 2:
        __x_show(__load64(c + 104), id, on)
    elif __load64(c + 8) == 3:
        __w32_show(__load64(c + 104), id, on)

func __ub_title(c: int, id: int, t: str):
    if __load64(c + 8) == 2:
        __x_title(__load64(c + 104), id, t)
    elif __load64(c + 8) == 3:
        __w32_title(__load64(c + 104), id, t)

func __ub_resize(c: int, id: int, w: int, h: int):
    if __load64(c + 8) == 2:
        __x_resize(__load64(c + 104), id, w, h)
    elif __load64(c + 8) == 3:
        __w32_resize(__load64(c + 104), id, w, h)

func __ub_move(c: int, id: int, x: int, y: int):
    if __load64(c + 8) == 2:
        __x_move(__load64(c + 104), id, x, y)
    elif __load64(c + 8) == 3:
        __w32_move(__load64(c + 104), id, x, y)

func __ub_cursor(c: int, id: int, name: str):
    if __load64(c + 8) == 2:
        __x_cursor(__load64(c + 104), id, name)
    elif __load64(c + 8) == 3:
        __w32_cursor(__load64(c + 104), id, name)

func __ub_present(c: int, id: int, f: int):
    if __load64(c + 8) == 2:
        __x_present(__load64(c + 104), id, f)
    elif __load64(c + 8) == 3:
        __w32_present(__load64(c + 104), id, f)

func __ub_pump(c: int, block: bool):
    if __load64(c + 8) == 2:
        __x_pump(c, __load64(c + 104), block)
    elif __load64(c + 8) == 3:
        __w32_pump(c, __load64(c + 104), block)

func __ub_wait(c: int, ms: int):
    if __load64(c + 8) == 2:
        __x_wait(__load64(c + 104), ms)
    elif __load64(c + 8) == 3:
        __w32_wait(__load64(c + 104), ms)

# Position de la zone cliente sur l'écran dans out ([0] x [8] y) ; false si le backend ne la connaît pas.
func __ub_position(c: int, id: int, out: int) -> bool:
    if __load64(c + 8) == 2:
        return __x_position(__load64(c + 104), id, out)
    if __load64(c + 8) == 3:
        return __w32_position(__load64(c + 104), id, out)
    return false

func __ub_set_state(c: int, id: int, state: str) -> bool:
    if __load64(c + 8) == 2:
        return __x_set_state(__load64(c + 104), id, state)
    if __load64(c + 8) == 3:
        return __w32_set_state(__load64(c + 104), id, state)
    return false

func __ub_hints(c: int, w: int):
    id := __load64(w)
    if __load64(c + 8) == 2:
        __x_hints(__load64(c + 104), id, __load64(w + 240) != 0, __load64(w + 248) != 0, __load64(w + 256) != 0, __uf_get(w, 264), __load64(w + 272), __load64(w + 280), __load64(w + 288), __load64(w + 296), __load64(w + 16), __load64(w + 24) + __load64(w + 88))
    elif __load64(c + 8) == 3:
        __w32_hints(__load64(c + 104), id, __load64(w + 240) != 0, __load64(w + 248) != 0, __load64(w + 256) != 0, __uf_get(w, 264), __load64(w + 272), __load64(w + 280), __load64(w + 288), __load64(w + 296), __load64(w + 16), __load64(w + 24) + __load64(w + 88))

func __ub_focus(c: int, id: int):
    if __load64(c + 8) == 2:
        __x_focus(__load64(c + 104), id)
    elif __load64(c + 8) == 3:
        __w32_focus(__load64(c + 104), id)

# Écran : [0] largeur [8] hauteur [16] largeur utile [24] hauteur utile (headless : 1920 x 1080, 1920 x 1040).
func __ub_screen(c: int) -> int:
    out := __alloc(32)
    __store64(out, 1920)
    __store64(out + 8, 1080)
    __store64(out + 16, 1920)
    __store64(out + 24, 1040)
    if __load64(c + 8) == 2:
        __x_screen(__load64(c + 104), out)
    elif __load64(c + 8) == 3:
        __w32_screen(__load64(c + 104), out)
    return out

func __ub_dpi(c: int) -> int:
    if __load64(c + 8) == 2:
        return __x_dpi(__load64(c + 104))
    if __load64(c + 8) == 3:
        return __w32_dpi(__load64(c + 104))
    return 96

# Affiche les fenêtres modifiées (backends interactifs ; headless : composition paresseuse, à la capture).
func __ui_flush(c: int):
    if not __ui_interactive(c):
        return
    ws := __load64(c + 24)
    ks := __rt_dict_list(ws, 24)
    i := 0
    while i < __load64(ks):
        w := __ui_get(ws, __rt_vec_at(ks, i))
        i += 1
        if w == 0 or __load64(w + 64) == 0 or __load64(w + 40) == 0 or __load64(w + 48) == 0:
            continue
        __ui_compose(c, w)
        __ub_present(c, __load64(w), __load64(w + 160))

func __ui_pump(c: int, block: bool):
    __ub_pump(c, block)
    __ui_flush(c)

func __ui_has_backend(c: int) -> bool:
    __ui_init(c)
    return __load64(c + 8) != 0

func __ui_require_backend(c: int):
    if not __ui_has_backend(c):
        e := __ui_s(c, 16)
        if __nat_blen(e) == 0:
            e = "inconnu"
        __ui_fail("ui : aucun backend graphique utilisable : " + e, false)

# ---- fenêtre : [0] id [8] titre [16] cw [24] ch [32] redimensionnable [40] visible [48] vivante [56] close envoyé
# [64] sale [72] confirmation [80] curseur [88] barH [96] canvas [104] menu [112] focus [120] survol [128] pressé
# [136] widgets [144] événements [152] raccourcis [160] image composée [168] x [176] y [184] position connue
# [192] état [200..224] géométrie sauvée [232] focus fenêtre [240] hints : redimensionnable [248] décorée
# [256] premier plan [264] opacité [272] minW [280] minH [288] maxW [296] maxH [304] tête de la file ----

func __ui_win(c: int, id0: int) -> int:
    id := id0
    if id == 0:
        id = __load64(c + 80)
    w := __ui_get(__load64(c + 24), id)
    if w == 0:
        __ui_fail("ui : fenêtre inconnue", true)
    return w

func __ui_find_win(c: int, id: int) -> int:
    return __ui_get(__load64(c + 24), id)

func __ui_widget(c: int, id: int) -> int:
    d := __ui_get(__load64(c + 32), id)
    if d == 0:
        __ui_fail("ui : widget inconnu", true)
    return d

# ---- événements : [0] type [8] fenêtre [16] widget [24] data [32] position [40] x [48] y [56] dx [64] dy
# [72] touche [80] mods [88] texte ----

func __ue_new(t: str) -> int:
    e := __alloc(96)
    __ui_sets(e, 0, t)
    __ui_sets(e, 24, "")
    __ui_sets(e, 88, "")
    __uf_set(e, 56, 0.0)
    __uf_set(e, 64, 0.0)
    return e

func __ue_count(w: int) -> int:
    return __load64(__load64(w + 144)) - __load64(w + 304)

func __ue_pop(w: int) -> int:
    q := __load64(w + 144)
    h := __load64(w + 304)
    e := __rt_vec_at(q, h)
    __store64(__load64(q + 16) + 8 * h, 0)
    h += 1
    if h == __load64(q):
        __store64(q, 0)
        h = 0
    elif h >= 1024 and h * 2 >= __load64(q):
        n := __load64(q) - h
        d := __load64(q + 16)
        __copy(d, d + 8 * h, 8 * n)
        __store64(q, n)
        h = 0
    __store64(w + 304, h)
    return e

func __ui_push(w: int, e: int):
    __store64(e + 8, __load64(w))
    t := __ui_s(e, 0)
    if not __rt_str_eq(t, "close"):
        __store64(w + 56, 0)
    q := __load64(w + 144)
    if __ue_count(w) > 0:
        last := __rt_vec_at(q, __load64(q) - 1)
        if __rt_str_eq(__ui_s(last, 0), t) and (__rt_str_eq(t, "pointer_move") or __rt_str_eq(t, "resize") or __rt_str_eq(t, "move")):
            __store64(__load64(q + 16) + 8 * (__load64(q) - 1), e)
            return
    if __ue_count(w) >= 4096:
        __ue_pop(w)
    __rt_list_push(q, e)

func __ui_push_simple(w: int, t: str, widget: int, data: str):
    e := __ue_new(t)
    __store64(e + 16, widget)
    __ui_sets(e, 24, data)
    __ui_push(w, e)

# ---- widgets : [0] id [8] fenêtre [16] genre [24] texte [32] indication [40] x [48] y [56] l [64] h [72] visible
# [80] actif [88] coché [96] progression [104] éléments [112] sélection [120] ouvert [128] curseur (octets)
# [136] fond [144] texte (couleur) [152] rayon ----

func __uw_is(d: int, k: str) -> bool:
    return __rt_str_eq(__ui_s(d, 16), k)

func __ui_tt(cy: float, size: float) -> float:
    return cy - 0.72 * size

func __ui_prev_char(s: str, pos0: int) -> int:
    if pos0 == 0:
        return 0
    p := __nat_bp(s)
    pos := pos0 - 1
    while pos > 0 and (__load8(p + pos) & 192) == 128:
        pos -= 1
    return pos

func __ui_next_char(s: str, pos0: int) -> int:
    n := __nat_blen(s)
    if pos0 >= n:
        return n
    p := __nat_bp(s)
    pos := pos0 + 1
    while pos < n and (__load8(p + pos) & 192) == 128:
        pos += 1
    return pos

func __ui_fill(c: int) -> int:
    return __up_new(false, c, 1.0, 1.0)

func __ui_strokep(c: int, w: float) -> int:
    return __up_new(true, c, 1.0, w)

func __ui_hex(v: int) -> int:
    return __uc((v >> 16) & 255, (v >> 8) & 255, v & 255, 255)

func __ui_tw(s: str) -> float:
    return __ua_text_width(s, 14.0, 0)

func __ui_path_new() -> int:
    return __rt_list_new(0)

func __ui_path_cmd(p: int, k: int, v0: float, v1: float, v2: float, v3: float, v4: float, v5: float):
    c := __alloc_raw(56)
    __store64(c, k)
    __uf_set(c, 8, v0)
    __uf_set(c, 16, v1)
    __uf_set(c, 24, v2)
    __uf_set(c, 32, v3)
    __uf_set(c, 40, v4)
    __uf_set(c, 48, v5)
    __rt_list_push(p, c)

func __ui_draw_widget(f: int, w: int, d: int):
    id := __load64(d)
    hov := __load64(w + 120) == id
    prs := __load64(w + 128) == id and hov
    foc := __load64(w + 112) == id
    x := __i2f(__load64(d + 40))
    y := __i2f(__load64(d + 48))
    wd := __i2f(__load64(d + 56))
    h := __i2f(__load64(d + 64))
    enabled := __load64(d + 80) != 0
    dbg := __load64(d + 136)
    dfg := __load64(d + 144)
    txt := __uc(20, 20, 20, 255)
    if not enabled:
        txt = __uc(131, 131, 131, 255)
    elif dfg >= 0:
        txt = __ui_hex(dfg)
    rad := -1.0
    if __uf_get(d, 152) >= 0.0:
        rad = __uf_get(d, 152)
    accent := __uc(0, 120, 215, 255)
    text := __ui_s(d, 24)
    if __uw_is(d, "button"):
        bg := __uc(225, 225, 225, 255)
        if not enabled:
            bg = __uc(230, 230, 230, 255)
        elif prs:
            bg = __uc(204, 228, 247, 255)
        elif hov:
            bg = __uc(229, 241, 251, 255)
        if dbg >= 0 and enabled:
            bg = __ui_hex(dbg)
            if prs:
                bg = __uc(__uc_r(bg) * 80 // 100, __uc_g(bg) * 80 // 100, __uc_b(bg) * 80 // 100, 255)
            elif hov:
                bg = __uc(__ui_min(255, __uc_r(bg) * 112 // 100 + 6), __ui_min(255, __uc_g(bg) * 112 // 100 + 6), __ui_min(255, __uc_b(bg) * 112 // 100 + 6), 255)
        br := 4.0
        if rad >= 0.0:
            br = rad
        bd := __uc(173, 173, 173, 255)
        if not enabled:
            bd = __uc(191, 191, 191, 255)
        elif prs:
            bd = __uc(0, 84, 153, 255)
        elif hov or foc:
            bd = accent
        if dbg != -2:
            __us_round_rect(f, x, y, wd, h, br, __ui_fill(bg))
        sc := bd
        if dbg >= 0:
            sc = bg
        __us_round_rect(f, x + 0.5, y + 0.5, wd - 1.0, h - 1.0, br, __ui_strokep(sc, 1.0))
        tw := __ui_tw(text)
        __us_text(f, text, x + (wd - tw) / 2.0, __ui_tt(y + h / 2.0, 14.0), txt, 1.0, 14.0, 0)
    elif __uw_is(d, "label"):
        if dbg >= 0:
            __us_round_rect(f, x, y, wd, h, __uf_max(0.0, rad), __ui_fill(__ui_hex(dbg)))
        __us_text(f, text, x, __ui_tt(y + h / 2.0, 14.0), txt, 1.0, 14.0, 0)
    elif __uw_is(d, "input") or __uw_is(d, "combo"):
        combo := __uw_is(d, "combo")
        ir := 3.0
        if rad >= 0.0:
            ir = rad
        fc := __uc(240, 240, 240, 255)
        if dbg >= 0:
            fc = __ui_hex(dbg)
        elif enabled:
            fc = __uc(255, 255, 255, 255)
        __us_round_rect(f, x, y, wd, h, ir, __ui_fill(fc))
        sc := __uc(122, 122, 122, 255)
        sw := 1.0
        if foc:
            sc = accent
            sw = 1.5
        __us_round_rect(f, x + 0.5, y + 0.5, wd - 1.0, h - 1.0, ir, __ui_strokep(sc, sw))
        pad := 6.0
        cw := 0.0
        if combo:
            cw = 20.0
        __us_set_clip(f, x + 2.0, y + 2.0, wd - 4.0 - cw, h - 4.0)
        if not combo:
            caretX := __ui_tw(__nat_sub(text, 0, __load64(d + 128)))
            inner := wd - 2.0 * pad
            off := 0.0
            if caretX > inner:
                off = caretX - inner
            ph := __ui_s(d, 32)
            if __nat_blen(text) == 0 and __nat_blen(ph) > 0:
                __us_text(f, ph, x + pad, __ui_tt(y + h / 2.0, 14.0), __uc(140, 140, 140, 255), 1.0, 14.0, 0)
            __us_text(f, text, x + pad - off, __ui_tt(y + h / 2.0, 14.0), txt, 1.0, 14.0, 0)
            if foc and enabled:
                __us_fill_rect(f, x + pad - off + caretX, y + 5.0, 1.2, h - 10.0, __ui_fill(txt))
        else:
            items := __load64(d + 104)
            sel := __load64(d + 112)
            label := text
            if sel >= 0 and sel < __load64(items):
                label = __as_str(__rt_vec_at(items, sel))
            __us_text(f, label, x + pad, __ui_tt(y + h / 2.0, 14.0), txt, 1.0, 14.0, 0)
        __store64(f + 80, 0)
        if combo:
            p := __ui_path_new()
            ax := x + wd - 14.0
            ay := y + h / 2.0 - 2.0
            __ui_path_cmd(p, 0, ax, ay, 0.0, 0.0, 0.0, 0.0)
            __ui_path_cmd(p, 1, ax + 4.0, ay + 4.0, 0.0, 0.0, 0.0, 0.0)
            __ui_path_cmd(p, 1, ax + 8.0, ay, 0.0, 0.0, 0.0, 0.0)
            __us_path(f, p, __ui_strokep(__uc(80, 80, 80, 255), 1.5))
    elif __uw_is(d, "checkbox") or __uw_is(d, "radio"):
        bs := 16.0
        by := y + (h - bs) / 2.0
        checked := __load64(d + 88) != 0
        bd := __uc(122, 122, 122, 255)
        if not enabled:
            bd = __uc(191, 191, 191, 255)
        elif hov or foc:
            bd = accent
        if __uw_is(d, "radio"):
            fc := __uc(240, 240, 240, 255)
            if enabled:
                fc = __uc(255, 255, 255, 255)
            __us_circle(f, x + bs / 2.0, by + bs / 2.0, bs / 2.0, __ui_fill(fc))
            __us_circle(f, x + bs / 2.0, by + bs / 2.0, bs / 2.0 - 0.5, __ui_strokep(bd, 1.2))
            if checked:
                dc := __uc(160, 160, 160, 255)
                if enabled:
                    dc = accent
                __us_circle(f, x + bs / 2.0, by + bs / 2.0, 4.2, __ui_fill(dc))
        else:
            fc := __uc(255, 255, 255, 255)
            if checked:
                fc = __uc(160, 160, 160, 255)
                if enabled:
                    fc = accent
            __us_round_rect(f, x, by, bs, bs, 3.0, __ui_fill(fc))
            sc := bd
            if checked:
                sc = accent
            __us_round_rect(f, x + 0.5, by + 0.5, bs - 1.0, bs - 1.0, 3.0, __ui_strokep(sc, 1.2))
            if checked:
                p := __ui_path_new()
                __ui_path_cmd(p, 0, x + 3.5, by + 8.5, 0.0, 0.0, 0.0, 0.0)
                __ui_path_cmd(p, 1, x + 6.5, by + 11.5, 0.0, 0.0, 0.0, 0.0)
                __ui_path_cmd(p, 1, x + 12.5, by + 4.5, 0.0, 0.0, 0.0, 0.0)
                __us_path(f, p, __ui_strokep(__uc(255, 255, 255, 255), 2.0))
        __us_text(f, text, x + bs + 8.0, __ui_tt(y + h / 2.0, 14.0), txt, 1.0, 14.0, 0)
    elif __uw_is(d, "progress"):
        r3 := __uf_min(3.0, h / 2.0)
        __us_round_rect(f, x, y, wd, h, r3, __ui_fill(__uc(230, 230, 230, 255)))
        pv := __load64(d + 96)
        if pv < 0:
            pv = 0
        if pv > 100:
            pv = 100
        fw := wd * __i2f(pv) / 100.0
        if fw > 0.5:
            __us_round_rect(f, x, y, fw, h, r3, __ui_fill(__uc(6, 176, 37, 255)))
        __us_round_rect(f, x + 0.5, y + 0.5, wd - 1.0, h - 1.0, r3, __ui_strokep(__uc(188, 188, 188, 255), 1.0))
    elif __uw_is(d, "scroll"):
        __us_fill_rect(f, x, y, wd, h, __ui_fill(__uc(255, 255, 255, 255)))
        __us_fill_rect(f, x + wd - 14.0, y, 14.0, h, __ui_fill(__uc(240, 240, 240, 255)))
        __us_fill_rect(f, x + wd - 11.0, y + 4.0, 8.0, __uf_max(10.0, h / 3.0), __ui_fill(__uc(194, 195, 201, 255)))
        __us_round_rect(f, x + 0.5, y + 0.5, wd - 1.0, h - 1.0, 0.0, __ui_strokep(__uc(130, 135, 144, 255), 1.0))

func __ui_menu_item_w(it: int) -> float:
    return __ui_tw(__ui_s(it, 8)) + 24.0

func __ui_compose(c: int, w: int):
    cw := __load64(w + 16)
    barH := __load64(w + 88)
    fh := __load64(w + 24) + barH
    f := __load64(w + 160)
    if f == 0:
        f = __us_new(cw, fh)
        __store64(w + 160, f)
    elif __us_w(f) != cw or __us_h(f) != fh:
        __us_resize(f, cw, fh)
    __us_reset_state(f)
    __us_clear(f, __uc(240, 240, 240, 255))
    cv := __load64(w + 96)
    if cv != 0:
        o := __ui_get(__load64(c + 48), cv)
        if o != 0 and __load64(o + 24) != 0:
            __us_blit(f, __load64(o + 16), 0, barH)
    __uf_set(f, 64, __i2f(barH))
    wl := __load64(w + 136)
    wds := __load64(c + 32)
    i := 0
    while i < __load64(wl):
        d := __ui_get(wds, __rt_vec_at(wl, i))
        if d != 0 and __load64(d + 72) != 0:
            __ui_draw_widget(f, w, d)
        i += 1
    i = 0
    while i < __load64(wl):
        d := __ui_get(wds, __rt_vec_at(wl, i))
        i += 1
        if d == 0 or __load64(d + 72) == 0 or not __uw_is(d, "combo") or __load64(d + 120) == 0:
            continue
        items := __load64(d + 104)
        ni := __load64(items)
        dx := __i2f(__load64(d + 40))
        dw := __i2f(__load64(d + 56))
        ly := __i2f(__load64(d + 48) + __load64(d + 64))
        lh := __i2f(ni * 24)
        __us_fill_rect(f, dx, ly, dw, lh, __ui_fill(__uc(255, 255, 255, 255)))
        k := 0
        while k < ni:
            if k == __load64(d + 112):
                __us_fill_rect(f, dx + 1.0, ly + __i2f(k * 24), dw - 2.0, 24.0, __ui_fill(__uc(204, 228, 247, 255)))
            __us_text(f, __as_str(__rt_vec_at(items, k)), dx + 6.0, __ui_tt(ly + __i2f(k * 24) + 12.0, 14.0), __uc(20, 20, 20, 255), 1.0, 14.0, 0)
            k += 1
        __us_round_rect(f, dx + 0.5, ly + 0.5, dw - 1.0, lh - 1.0, 0.0, __ui_strokep(__uc(122, 122, 122, 255), 1.0))
    __us_identity(f)
    if barH > 0:
        __us_fill_rect(f, 0.0, 0.0, __i2f(cw), __i2f(barH), __ui_fill(__uc(255, 255, 255, 255)))
        __us_fill_rect(f, 0.0, __i2f(barH - 1), __i2f(cw), 1.0, __ui_fill(__uc(218, 218, 218, 255)))
        m := __ui_get(__load64(c + 40), __load64(w + 104))
        if m != 0:
            mx := 0.0
            its := __load64(m + 16)
            k := 0
            while k < __load64(its):
                it := __rt_vec_at(its, k)
                __us_text(f, __ui_s(it, 8), mx + 12.0, __ui_tt(__i2f(barH) / 2.0, 14.0), __uc(20, 20, 20, 255), 1.0, 14.0, 0)
                mx = mx + __ui_menu_item_w(it)
                k += 1
    __store64(w + 64, 0)

# ---- interaction ----

func __ui_hit(c: int, w: int, cx: int, cy: int) -> int:
    wl := __load64(w + 136)
    wds := __load64(c + 32)
    i := __load64(wl) - 1
    while i >= 0:
        d := __ui_get(wds, __rt_vec_at(wl, i))
        if __load64(d + 72) != 0 and __uw_is(d, "combo") and __load64(d + 120) != 0:
            dx := __load64(d + 40)
            dy := __load64(d + 48) + __load64(d + 64)
            if cx >= dx and cx < dx + __load64(d + 56) and cy >= dy and cy < dy + __ui_trunc32(__load64(__load64(d + 104)) * 24):
                return __load64(d)
        i -= 1
    i = __load64(wl) - 1
    while i >= 0:
        d := __ui_get(wds, __rt_vec_at(wl, i))
        i -= 1
        if __load64(d + 72) == 0 or __uw_is(d, "label"):
            continue
        dx := __load64(d + 40)
        dy := __load64(d + 48)
        if cx >= dx and cx < dx + __load64(d + 56) and cy >= dy and cy < dy + __load64(d + 64):
            return __load64(d)
    return 0

func __ui_focusable(d: int) -> bool:
    return __load64(d + 72) != 0 and __load64(d + 80) != 0 and (__uw_is(d, "button") or __uw_is(d, "input") or __uw_is(d, "checkbox") or __uw_is(d, "radio") or __uw_is(d, "combo"))

func __ui_set_focus(c: int, w: int, id: int):
    if __load64(w + 112) == id:
        return
    o := __ui_get(__load64(c + 32), __load64(w + 112))
    if o != 0:
        __store64(o + 120, 0)
    __store64(w + 112, id)
    __store64(w + 64, 1)

func __ui_select_radio(c: int, w: int, d: int):
    wl := __load64(w + 136)
    i := 0
    while i < __load64(wl):
        o := __ui_get(__load64(c + 32), __rt_vec_at(wl, i))
        if __uw_is(o, "radio"):
            if __load64(o) == __load64(d):
                __store64(o + 88, 1)
            else:
                __store64(o + 88, 0)
        i += 1

func __ui_activate(c: int, w: int, d: int):
    if __uw_is(d, "button"):
        __ui_push_simple(w, "button", __load64(d), "")
    elif __uw_is(d, "checkbox"):
        __store64(d + 88, 1 - __load64(d + 88))
        __ui_push_simple(w, "check", __load64(d), "")
    elif __uw_is(d, "radio"):
        __ui_select_radio(c, w, d)
        __ui_push_simple(w, "radio", __load64(d), "")
    __store64(w + 64, 1)

func __ui_caret_from_x(d: int, cx: int) -> int:
    text := __ui_s(d, 24)
    target := __i2f(cx - __load64(d + 40) - 6)
    best := 1e18
    caretX := __ui_tw(__nat_sub(text, 0, __load64(d + 128)))
    inner := __i2f(__load64(d + 56)) - 12.0
    if caretX > inner:
        target = target + (caretX - inner)
    else:
        target = target + 0.0
    bestPos := 0
    pos := 0
    n := __nat_blen(text)
    while true:
        dx := __uf_fabs(__ui_tw(__nat_sub(text, 0, pos)) - target)
        if dx < best:
            best = dx
            bestPos = pos
        if pos >= n:
            break
        pos = __ui_next_char(text, pos)
    return bestPos

func __ui_pe(t: str, cx: int, cy: int, button: int, mods: int) -> int:
    e := __ue_new(t)
    __store64(e + 32, 1)
    __store64(e + 40, cx)
    __store64(e + 48, cy)
    __store64(e + 72, button)
    __store64(e + 80, mods)
    return e

func __ui_on_mouse(c: int, wid: int, typ: int, x: int, y: int, button: int, mods: int):
    w := __ui_find_win(c, wid)
    if w == 0 or __load64(w + 48) == 0:
        return
    if typ == 5:
        if __load64(w + 120) != 0:
            __store64(w + 120, 0)
            __store64(w + 64, 1)
        le := __ue_new("pointer_leave")
        __store64(le + 80, mods)
        __ui_push(w, le)
        return
    barH := __load64(w + 88)
    cx := x
    cy := y - barH
    if barH > 0 and y < barH:
        if typ == 1 and button == 1:
            m := __ui_get(__load64(c + 40), __load64(w + 104))
            if m != 0:
                mx := 0.0
                its := __load64(m + 16)
                k := 0
                while k < __load64(its):
                    it := __rt_vec_at(its, k)
                    wdt := __ui_menu_item_w(it)
                    if __i2f(x) >= mx and __i2f(x) < mx + wdt:
                        __ui_push_simple(w, "command", __load64(it), "")
                        break
                    mx = mx + wdt
                    k += 1
        return
    wds := __load64(c + 32)
    if typ == 0:
        h := __ui_hit(c, w, cx, cy)
        if h != __load64(w + 120):
            __store64(w + 120, h)
            __store64(w + 64, 1)
        __ui_push(w, __ui_pe("pointer_move", cx, cy, button, mods))
    elif typ == 1:
        if button != 1:
            __ui_push(w, __ui_pe("pointer_down", cx, cy, button, mods))
            return
        h := __ui_hit(c, w, cx, cy)
        if h != 0:
            d := __ui_get(wds, h)
            if __uw_is(d, "combo") and __load64(d + 120) != 0 and cy >= __load64(d + 48) + __load64(d + 64):
                idx := (cy - __load64(d + 48) - __load64(d + 64)) // 24
                if idx >= 0 and idx < __load64(__load64(d + 104)):
                    __store64(d + 112, idx)
                    __ui_push_simple(w, "change", __load64(d), "")
                __store64(d + 120, 0)
                __store64(w + 128, 0)
                __store64(w + 64, 1)
                __ui_push(w, __ui_pe("pointer_down", cx, cy, button, mods))
                return
        wl := __load64(w + 136)
        i := 0
        while i < __load64(wl):
            o := __ui_get(wds, __rt_vec_at(wl, i))
            if __uw_is(o, "combo") and __load64(o) != h and __load64(o + 120) != 0:
                __store64(o + 120, 0)
                __store64(w + 64, 1)
            i += 1
        __store64(w + 128, h)
        if h != 0 and __ui_focusable(__ui_get(wds, h)):
            __ui_set_focus(c, w, h)
        elif h == 0:
            __ui_set_focus(c, w, 0)
        if h != 0:
            d := __ui_get(wds, h)
            if __uw_is(d, "input") and __load64(d + 80) != 0:
                __store64(d + 128, __ui_caret_from_x(d, cx))
            if __uw_is(d, "combo") and __load64(d + 80) != 0:
                __store64(d + 120, 1 - __load64(d + 120))
        __store64(w + 64, 1)
        __ui_push(w, __ui_pe("pointer_down", cx, cy, button, mods))
    elif typ == 2:
        h := __ui_hit(c, w, cx, cy)
        pressed := __load64(w + 128)
        if button == 1:
            __store64(w + 128, 0)
        if button == 1 and pressed != 0 and pressed == h:
            d := __ui_get(wds, h)
            if __load64(d + 80) != 0:
                __ui_activate(c, w, d)
        __store64(w + 64, 1)
        __ui_push(w, __ui_pe("pointer_up", cx, cy, button, mods))
    elif typ == 3 or typ == 4:
        pe := __ui_pe("wheel", cx, cy, 0, mods)
        if typ == 3:
            __uf_set(pe, 64, __i2f(button))
            __ui_sets(pe, 24, __int_to_str(button))
        else:
            __uf_set(pe, 56, __i2f(button))
            __ui_sets(pe, 24, "0")
        __ui_push(w, pe)

# Clés triées d'un dict natif à clés entières (ordre de std::map).
func __ui_sorted_keys(d: int) -> int:
    l := __rt_dict_list(d, 24)
    n := __load64(l)
    a := __load64(l + 16)
    i := 1
    while i < n:
        v := __load64(a + 8 * i)
        j := i - 1
        while j >= 0 and __load64(a + 8 * j) > v:
            __store64(a + 8 * (j + 1), __load64(a + 8 * j))
            j -= 1
        __store64(a + 8 * (j + 1), v)
        i += 1
    return l

func __ui_insert(s: str, at: int, t: str) -> str:
    return __nat_sub(s, 0, at) + t + __nat_sub(s, at, __nat_blen(s) - at)

func __ui_erase(s: str, at: int, n: int) -> str:
    return __nat_sub(s, 0, at) + __nat_sub(s, at + n, __nat_blen(s) - at - n)

func __ui_on_key(c: int, wid: int, vk: int, mods: int, text: str):
    w := __ui_find_win(c, wid)
    if w == 0 or __load64(w + 48) == 0:
        return
    scs := __load64(w + 152)
    ks := __ui_sorted_keys(scs)
    i := 0
    while i < __load64(ks):
        sid := __rt_vec_at(ks, i)
        sc := __ui_get(scs, sid)
        if __load64(sc + 8) == vk and __load64(sc) == (mods & 15):
            __ui_push_simple(w, "shortcut", sid, "")
            return
        i += 1
    e := __ue_new("key_down")
    __store64(e + 16, vk)
    __store64(e + 72, vk)
    __store64(e + 80, mods)
    __ui_sets(e, 88, text)
    __ui_push(w, e)
    wds := __load64(c + 32)
    if vk == 9:
        order := __rt_list_new(0)
        wl := __load64(w + 136)
        i = 0
        while i < __load64(wl):
            if __ui_focusable(__ui_get(wds, __rt_vec_at(wl, i))):
                __rt_list_push(order, __rt_vec_at(wl, i))
            i += 1
        n := __load64(order)
        if n > 0:
            k := 0
            found := false
            while k < n:
                if __rt_vec_at(order, k) == __load64(w + 112):
                    found = true
                    break
                k += 1
            j := 0
            if found:
                if (mods & 4) != 0:
                    j = (k + n - 1) % n
                else:
                    j = (k + 1) % n
            __ui_set_focus(c, w, __rt_vec_at(order, j))
        return
    d := __ui_get(wds, __load64(w + 112))
    if d == 0 or __load64(d + 80) == 0:
        return
    __store64(w + 64, 1)
    if __uw_is(d, "input"):
        changed := false
        t := __ui_s(d, 24)
        caret := __load64(d + 128)
        if (mods & 2) != 0 and (vk == 86 or vk == 118):
            clip := __ui_clipboard_get(c)
            if clip != 0:
                cs := __as_str(clip)
                sb := __rt_sb_new()
                cp := __nat_bp(cs)
                q := 0
                while q < __nat_blen(cs):
                    ch := __load8(cp + q)
                    if ch != 10 and ch != 13:
                        __rt_sb_byte(sb, ch)
                    q += 1
                clean := __rt_sb_str(sb)
                __ui_sets(d, 24, __ui_insert(t, caret, clean))
                __store64(d + 128, caret + __nat_blen(clean))
                changed = true
        elif (mods & 2) != 0 and (vk == 67 or vk == 99):
            __ui_clipboard_set(c, t)
        elif vk == 8:
            if caret > 0:
                p := __ui_prev_char(t, caret)
                __ui_sets(d, 24, __ui_erase(t, p, caret - p))
                __store64(d + 128, p)
                changed = true
        elif vk == 46:
            if caret < __nat_blen(t):
                nx := __ui_next_char(t, caret)
                __ui_sets(d, 24, __ui_erase(t, caret, nx - caret))
                changed = true
        elif vk == 37:
            __store64(d + 128, __ui_prev_char(t, caret))
        elif vk == 39:
            __store64(d + 128, __ui_next_char(t, caret))
        elif vk == 36:
            __store64(d + 128, 0)
        elif vk == 35:
            __store64(d + 128, __nat_blen(t))
        elif (mods & 3) == 0 and __nat_blen(text) > 0 and __load8(__nat_bp(text)) >= 32 and __load8(__nat_bp(text)) != 127:
            __ui_sets(d, 24, __ui_insert(t, caret, text))
            __store64(d + 128, caret + __nat_blen(text))
            changed = true
        if changed:
            __ui_push_simple(w, "change", __load64(d), "")
    elif __uw_is(d, "button"):
        if vk == 13 or vk == 32:
            __ui_activate(c, w, d)
    elif __uw_is(d, "checkbox") or __uw_is(d, "radio"):
        if vk == 32:
            __ui_activate(c, w, d)
    elif __uw_is(d, "combo"):
        n := __load64(__load64(d + 104))
        if n != 0 and (vk == 40 or vk == 38):
            delta := -1
            if vk == 40:
                delta = 1
            ns := __load64(d + 112) + delta
            if ns < 0:
                ns = 0
            elif n - 1 < ns:
                ns = n - 1
            if ns != __load64(d + 112):
                __store64(d + 112, ns)
                __ui_push_simple(w, "change", __load64(d), "")
        elif vk == 27:
            __store64(d + 120, 0)

func __ui_on_resize(c: int, wid: int, width: int, height: int):
    w := __ui_find_win(c, wid)
    if w == 0:
        return
    nh := __ui_max(1, height - __load64(w + 88))
    if width == __load64(w + 16) and nh == __load64(w + 24):
        return
    __store64(w + 16, width)
    __store64(w + 24, nh)
    __store64(w + 64, 1)
    e := __ue_new("resize")
    __store64(e + 32, 1)
    __store64(e + 40, width)
    __store64(e + 48, nh)
    __ui_sets(e, 24, __int_to_str(width) + "x" + __int_to_str(nh))
    __ui_push(w, e)

func __ui_on_close_request(c: int, wid: int):
    w := __ui_find_win(c, wid)
    if w == 0 or __load64(w + 48) == 0:
        return
    if __load64(w + 72) != 0:
        __ui_push_simple(w, "close_request", 0, "")
        return
    __store64(w + 48, 0)
    __store64(w + 56, 1)
    __store64(w + 40, 0)
    __ui_push_simple(w, "close", 0, "")

func __ui_on_key_up(c: int, wid: int, vk: int, mods: int):
    w := __ui_find_win(c, wid)
    if w == 0 or __load64(w + 48) == 0:
        return
    e := __ue_new("key_up")
    __store64(e + 16, vk)
    __store64(e + 72, vk)
    __store64(e + 80, mods)
    __ui_push(w, e)

func __ui_on_focus(c: int, wid: int, focused: bool):
    w := __ui_find_win(c, wid)
    fv := 0
    if focused:
        fv = 1
    if w == 0 or __load64(w + 48) == 0 or __load64(w + 232) == fv:
        return
    if focused:
        ws := __load64(c + 24)
        ks := __rt_dict_list(ws, 24)
        i := 0
        while i < __load64(ks):
            id := __rt_vec_at(ks, i)
            o := __ui_get(ws, id)
            if id != wid and __load64(o + 232) != 0:
                __store64(o + 232, 0)
                __ui_push_simple(o, "focus_out", 0, "")
            i += 1
    __store64(w + 232, fv)
    if focused:
        __ui_push_simple(w, "focus_in", 0, "")
    else:
        __ui_push_simple(w, "focus_out", 0, "")

func __ui_on_move(c: int, wid: int, x: int, y: int):
    w := __ui_find_win(c, wid)
    if w == 0 or __load64(w + 48) == 0:
        return
    if __load64(w + 184) != 0 and __load64(w + 168) == x and __load64(w + 176) == y:
        return
    __store64(w + 168, x)
    __store64(w + 176, y)
    __store64(w + 184, 1)
    e := __ue_new("move")
    __store64(e + 32, 1)
    __store64(e + 40, x)
    __store64(e + 48, y)
    __ui_sets(e, 24, __int_to_str(x) + "," + __int_to_str(y))
    __ui_push(w, e)

func __ui_on_state(c: int, wid: int, state: str):
    w := __ui_find_win(c, wid)
    if w == 0 or __load64(w + 48) == 0 or __rt_str_eq(__ui_s(w, 192), state):
        return
    __ui_sets(w, 192, state)
    __ui_push_simple(w, "state", 0, state)

# ---- processus (presse-papiers, notifications) : argv sans shell ----
# Résultat : [0] lancé [8] statut [16] sortie (str)

func __ui_run(prog: str, args: int, input: str, hasInput: bool, wantOut: bool) -> int:
    res := __alloc(24)
    __ui_sets(res, 16, "")
    fds := __alloc_raw(16)
    inR := -2
    inW := -1
    outR := -1
    outW := -2
    if hasInput:
        if __syscall(293, fds, 524288) < 0:
            return res
        inR = __load32(fds)
        inW = __load32(fds + 4)
    if wantOut:
        if __syscall(293, fds, 524288) < 0:
            return res
        outR = __load32(fds)
        outW = __load32(fds + 4)
    pid := __nat_spawn(prog, args, "", 0, inR, outW, -2, false)
    if hasInput:
        __syscall(3, inR)
    if wantOut:
        __syscall(3, outW)
    if pid < 0:
        if hasInput:
            __syscall(3, inW)
        if wantOut:
            __syscall(3, outR)
        return res
    if hasInput:
        old := __nat_sigpipe(true)
        __nat_write_fd(inW, input)
        __nat_sigpipe_restore(old)
        __syscall(3, inW)
    if wantOut:
        __ui_sets(res, 16, __nat_read_fd(outR, -1))
        __syscall(3, outR)
    st := __nat_waitpid(pid, 0)
    __store64(res, 1)
    __store64(res + 8, __load64(st + 8))
    return res

func __ui_argl(a: str, b: str, c: str) -> int:
    l := __rt_list_new(0)
    if __nat_blen(a) > 0:
        __rt_list_push(l, __str_addr(a))
    if __nat_blen(b) > 0:
        __rt_list_push(l, __str_addr(b))
    if __nat_blen(c) > 0:
        __rt_list_push(l, __str_addr(c))
    return l

func __ui_notify(title: str, message: str):
    l := __rt_list_new(0)
    __rt_list_push(l, __str_addr("--app-name=ALEX"))
    __rt_list_push(l, __str_addr(title))
    __rt_list_push(l, __str_addr(message))
    r := __ui_run("notify-send", l, "", false, false)
    if __load64(r) != 0 and __load64(r + 8) == 0:
        return
    __flush()
    __nat_write_fd(2, "[notification] " + title + " : " + message + "\n")

# Outils du presse-papiers : liste de [programme, arguments].
func __ui_clip_tools(set: bool) -> int:
    wl := __ui_env_set("WAYLAND_DISPLAY")
    tools := __rt_list_new(0)
    wlt := __alloc(16)
    xc := __alloc(16)
    xs := __alloc(16)
    if set:
        __ui_sets(wlt, 0, "wl-copy")
        __store64(wlt + 8, __ui_argl("", "", ""))
        __ui_sets(xc, 0, "xclip")
        __store64(xc + 8, __ui_argl("-selection", "clipboard", "-i"))
        __ui_sets(xs, 0, "xsel")
        __store64(xs + 8, __ui_argl("-b", "-i", ""))
    else:
        __ui_sets(wlt, 0, "wl-paste")
        __store64(wlt + 8, __ui_argl("-n", "", ""))
        __ui_sets(xc, 0, "xclip")
        __store64(xc + 8, __ui_argl("-selection", "clipboard", "-o"))
        __ui_sets(xs, 0, "xsel")
        __store64(xs + 8, __ui_argl("-b", "-o", ""))
    if wl:
        __rt_list_push(tools, wlt)
    __rt_list_push(tools, xc)
    __rt_list_push(tools, xs)
    if not wl:
        __rt_list_push(tools, wlt)
    return tools

func __ui_clipboard_set(c: int, text: str):
    __ui_sets(c, 88, text)
    __store64(c + 96, 1)
    if __windows():
        # presse-papiers du système (CF_UNICODETEXT) : xclip / wl-copy n'existent pas sous Windows ; hors écran
        # (tests), seul le presse-papiers interne sert
        if __load64(c + 8) == 3:
            __w32_clip_set(__load64(c + 104), text)
        return
    tools := __ui_clip_tools(true)
    i := 0
    while i < __load64(tools):
        t := __rt_vec_at(tools, i)
        r := __ui_run(__ui_s(t, 0), __load64(t + 8), text, true, false)
        if __load64(r) != 0 and __load64(r + 8) == 0:
            return
        i += 1

# Contenu (adresse de chaîne) ou 0.
func __ui_clipboard_get(c: int) -> int:
    if __windows():
        if __load64(c + 8) == 3:
            r := __w32_clip_get(__load64(c + 104))
            if r != 0:
                return r
        if __load64(c + 96) != 0:
            return __load64(c + 88)
        return 0
    tools := __ui_clip_tools(false)
    i := 0
    while i < __load64(tools):
        t := __rt_vec_at(tools, i)
        r := __ui_run(__ui_s(t, 0), __load64(t + 8), "", false, true)
        if __load64(r) != 0 and __load64(r + 8) == 0:
            return __load64(r + 16)
        i += 1
    if __load64(c + 96) != 0:
        return __load64(c + 88)
    return 0

# ---- API (portable_ui.hpp) ----

func __ui_window_create(c: int, title: str, width: int, height: int, resizable: bool) -> int:
    __ui_require_backend(c)
    if width <= 0 or height <= 0:
        __ui_fail("ui.window_create() : dimensions invalides", true)
    w := __alloc(320)
    id := __ui_new_id(c)
    __store64(w, id)
    __ui_sets(w, 8, title)
    __store64(w + 16, width)
    __store64(w + 24, height)
    if resizable:
        __store64(w + 32, 1)
    __store64(w + 48, 1)
    __store64(w + 64, 1)
    __ui_sets(w, 80, "arrow")
    __store64(w + 136, __rt_list_new(0))
    __store64(w + 144, __rt_list_new(0))
    __store64(w + 152, __rt_dict_new(8))
    __ui_sets(w, 192, "normal")
    __store64(w + 240, 1)
    __store64(w + 248, 1)
    __uf_set(w, 264, 1.0)
    __ub_create(c, id, title, width, height, resizable)
    __rt_dict_set(__load64(c + 24), id, w, 0)
    __store64(c + 80, id)
    return id

func __ui_window_poll(c: int, id: int) -> int:
    w := __ui_win(c, id)
    __ui_pump(c, false)
    if __ue_count(w) == 0 and __ui_interactive(c) and __load64(w + 48) != 0:
        __ub_wait(c, 8)
        __ui_pump(c, false)
    if __ue_count(w) == 0 and not __ui_interactive(c) and __load64(w + 40) != 0 and __load64(w + 48) != 0 and __load64(w + 56) == 0:
        __store64(w + 56, 1)
        __ui_push_simple(w, "close", 0, "")
    if __ue_count(w) == 0:
        return 0
    return __ue_pop(w)

func __ui_cursor_ok(n: str) -> bool:
    return __rt_str_eq(n, "arrow") or __rt_str_eq(n, "text") or __rt_str_eq(n, "pointer") or __rt_str_eq(n, "grab") or __rt_str_eq(n, "grabbing") or __rt_str_eq(n, "move") or __rt_str_eq(n, "resize_h") or __rt_str_eq(n, "resize_v") or __rt_str_eq(n, "wait") or __rt_str_eq(n, "not_allowed") or __rt_str_eq(n, "crosshair")

func __ui_set_state(c: int, w: int, state: str):
    if not (__rt_str_eq(state, "normal") or __rt_str_eq(state, "minimized") or __rt_str_eq(state, "maximized") or __rt_str_eq(state, "fullscreen")):
        __ui_fail("ui.window_set_state() : état inconnu '" + state + "' (normal, minimized, maximized, fullscreen)", true)
    if __load64(w + 48) == 0:
        __ui_fail("ui.window_set_state() : fenêtre fermée", true)
    before := __ui_s(w, 192)
    if __rt_str_eq(before, state):
        return
    id := __load64(w)
    if __ub_set_state(c, id, state):
        __ui_on_state(c, id, state)
        return
    # émulation : géométrie sauvegardée en quittant « normal », rétablie en y revenant
    if __rt_str_eq(before, "normal"):
        __store64(w + 200, __load64(w + 168))
        __store64(w + 208, __load64(w + 176))
        __store64(w + 216, __load64(w + 16))
        __store64(w + 224, __load64(w + 24))
    if __rt_str_eq(state, "maximized") or __rt_str_eq(state, "fullscreen"):
        sc := __ub_screen(c)
        sw := __load64(sc + 16)
        sh := __load64(sc + 24)
        if __rt_str_eq(state, "fullscreen"):
            sw = __load64(sc)
            sh = __load64(sc + 8)
        __ub_move(c, id, 0, 0)
        __ui_on_move(c, id, 0, 0)
        __ub_resize(c, id, sw, sh)
        __ui_on_resize(c, id, sw, sh + __load64(w + 88))
        if __rt_str_eq(before, "minimized"):
            __ub_show(c, id, true)
    elif __rt_str_eq(state, "minimized"):
        __ub_show(c, id, false)
    else:
        if __rt_str_eq(before, "minimized"):
            __ub_show(c, id, true)
        if __load64(w + 216) > 0:
            __ub_move(c, id, __load64(w + 200), __load64(w + 208))
            __ui_on_move(c, id, __load64(w + 200), __load64(w + 208))
            __ub_resize(c, id, __load64(w + 216), __load64(w + 224) + __load64(w + 88))
            __ui_on_resize(c, id, __load64(w + 216), __load64(w + 224) + __load64(w + 88))
    __ui_on_state(c, id, state)

func __ui_set_hints(c: int, w: int, resizable: bool, decorated: bool, topmost: bool, opacity: float, minW: int, minH: int, maxW: int, maxH: int):
    if opacity < 0.0 or opacity > 1.0:
        __ui_fail("ui.window_set_hints() : opacité hors de 0..1", true)
    if minW < 0 or minH < 0 or maxW < 0 or maxH < 0 or (maxW > 0 and maxW < minW) or (maxH > 0 and maxH < minH):
        __ui_fail("ui.window_set_hints() : tailles minimale / maximale invalides", true)
    rv := 0
    if resizable:
        rv = 1
    __store64(w + 240, rv)
    __store64(w + 248, 0)
    if decorated:
        __store64(w + 248, 1)
    __store64(w + 256, 0)
    if topmost:
        __store64(w + 256, 1)
    __uf_set(w, 264, opacity)
    __store64(w + 272, minW)
    __store64(w + 280, minH)
    __store64(w + 288, maxW)
    __store64(w + 296, maxH)
    __store64(w + 32, rv)
    if __load64(w + 48) != 0:
        __ub_hints(c, w)
    nw := __load64(w + 16)
    nh := __load64(w + 24)
    if minW > 0 and nw < minW:
        nw = minW
    if minH > 0 and nh < minH:
        nh = minH
    if maxW > 0 and nw > maxW:
        nw = maxW
    if maxH > 0 and nh > maxH:
        nh = maxH
    if (nw != __load64(w + 16) or nh != __load64(w + 24)) and __load64(w + 48) != 0:
        __ub_resize(c, __load64(w), nw, nh + __load64(w + 88))
        if not __ui_interactive(c):
            __ui_on_resize(c, __load64(w), nw, nh + __load64(w + 88))

func __ui_widget_create(c: int, kind: str, parent: int, text: str, x: int, y: int, w: int, h: int) -> int:
    win := __ui_win(c, parent)
    if w <= 0 or h <= 0:
        __ui_fail("ui." + kind + "_create() : dimensions invalides", true)
    d := __alloc(160)
    id := __ui_new_id(c)
    __store64(d, id)
    __store64(d + 8, __load64(win))
    __ui_sets(d, 16, kind)
    __ui_sets(d, 24, text)
    __ui_sets(d, 32, "")
    __store64(d + 40, x)
    __store64(d + 48, y)
    __store64(d + 56, w)
    __store64(d + 64, h)
    __store64(d + 72, 1)
    __store64(d + 80, 1)
    __store64(d + 104, __rt_list_new(0))
    __store64(d + 112, -1)
    if __rt_str_eq(kind, "input"):
        __store64(d + 128, __nat_blen(text))
    __store64(d + 136, -1)
    __store64(d + 144, -1)
    __uf_set(d, 152, -1.0)
    __rt_dict_set(__load64(c + 32), id, d, 0)
    __rt_list_push(__load64(win + 136), id)
    __store64(win + 64, 1)
    return id

func __ui_dirty(c: int, d: int):
    w := __ui_find_win(c, __load64(d + 8))
    if w != 0:
        __store64(w + 64, 1)

func __ui_inject_mouse(c: int, window: int, kind: str, x: int, y: int, button: int, mods: int):
    w := __ui_win(c, window)
    fy := y + __load64(w + 88)
    id := __load64(w)
    if button < 1 or button > 3:
        __ui_fail("ui.inject_mouse() : button doit valoir 1, 2 ou 3", true)
    if __rt_str_eq(kind, "move"):
        __ui_on_mouse(c, id, 0, x, fy, 0, mods)
    elif __rt_str_eq(kind, "down"):
        __ui_on_mouse(c, id, 1, x, fy, button, mods)
    elif __rt_str_eq(kind, "up"):
        __ui_on_mouse(c, id, 2, x, fy, button, mods)
    elif __rt_str_eq(kind, "click"):
        __ui_on_mouse(c, id, 0, x, fy, 0, mods)
        __ui_on_mouse(c, id, 1, x, fy, button, mods)
        __ui_on_mouse(c, id, 2, x, fy, button, mods)
    elif __rt_str_eq(kind, "leave"):
        __ui_on_mouse(c, id, 5, x, fy, 0, mods)
    else:
        __ui_fail("ui.inject_mouse() : type inconnu '" + kind + "' (move, down, up, click, leave)", true)

func __ui_clampc(v: int) -> int:
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v

func __ui_rgba(r: int, g: int, b: int, a: int) -> int:
    return __uc(__ui_clampc(r), __ui_clampc(g), __ui_clampc(b), __ui_clampc(a))

func __ui_paint(kind: str, r: int, g: int, b: int, a: int, op: float, sw: float) -> int:
    w := 1.0
    if sw > 0.0:
        w = sw
    return __up_new(__rt_str_eq(kind, "stroke"), __ui_rgba(r, g, b, a), op, w)

# Surface du canvas h, ou 0.
func __ui_canvas(h: int) -> int:
    o := __ui_get(__load64(__ui_core() + 48), h)
    if o == 0:
        return 0
    return __load64(o + 16)

func __ui_rb(ok: bool) -> int:
    return __dyn_bool(ok)

# ---- natives ----

func __nat__native_ui__available(n: int) -> int:
    __nat_exact("available", n, 0)
    return __dyn_bool(__ui_has_backend(__ui_core()))

func __nat__native_ui__backend(n: int) -> int:
    __nat_exact("backend", n, 0)
    c := __ui_core()
    if __ui_has_backend(c):
        if __load64(c + 8) == 2:
            return __dyn_str("x11")
        if __load64(c + 8) == 3:
            return __dyn_str("win32")
        return __dyn_str("headless")
    return __dyn_str("unavailable")

func __nat__native_ui__text_measure(n: int, a: int, b: int, c: int) -> int:
    if n < 2 or n > 3:
        __nat_exact("text_measure", n, 2)
    t := __ui_str("text_measure", a, "text")
    size := __ui_num("text_measure", b, "size")
    font := ""
    if n == 3 and c != 0:
        font = __ui_str("text_measure", c, "font")
    if size <= 0.0:
        __ui_fail("ui.text_measure() : size doit être > 0", true)
    f := __ua_font(font)
    d := __dyn_dict_new()
    __nat_dict_put(d, "width", __dyn_float(__ua_text_width(t, size, f)))
    __nat_dict_put(d, "height", __dyn_float(__ua_line_height(size, f)))
    __nat_dict_put(d, "ascent", __dyn_float(__ua_ascent(size, f)))
    return d

func __nat__native_ui__window_create(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("window_create", n, 4)
    title := __ui_str("window_create", a, "title")
    w := __ui_i32("window_create", b, "width")
    h := __ui_i32("window_create", c, "height")
    rs := __ui_bool("window_create", d, "resizable")
    return __dyn_int(__ui_window_create(__ui_core(), title, w, h, rs))

func __nat__native_ui__window_show(n: int, a: int) -> int:
    __nat_exact("window_show", n, 1)
    id := __ui_handle("window_show", a)
    c := __ui_core()
    w := __ui_win(c, id)
    if __load64(w + 48) != 0:
        __store64(w + 40, 1)
        __store64(w + 64, 1)
        __store64(c + 80, __load64(w))
        __ub_show(c, __load64(w), true)
        __ui_flush(c)
    return 0

func __nat__native_ui__window_hide(n: int, a: int) -> int:
    __nat_exact("window_hide", n, 1)
    id := __ui_handle("window_hide", a)
    c := __ui_core()
    w := __ui_win(c, id)
    __store64(w + 40, 0)
    __ub_show(c, __load64(w), false)
    return 0

func __nat__native_ui__window_close(n: int, a: int) -> int:
    __nat_exact("window_close", n, 1)
    id := __ui_handle("window_close", a)
    c := __ui_core()
    w := __ui_find_win(c, id)
    if w == 0:
        __ui_fail("ui : fenêtre inconnue", true)
    if __load64(w + 48) != 0:
        __store64(w + 48, 0)
        __store64(w + 40, 0)
        __ub_destroy(c, __load64(w))
    return 0

func __nat__native_ui__window_set_title(n: int, a: int, b: int) -> int:
    __nat_exact("window_set_title", n, 2)
    id := __ui_handle("window_set_title", a)
    t := __ui_str("window_set_title", b, "title")
    c := __ui_core()
    w := __ui_win(c, id)
    __ui_sets(w, 8, t)
    if __load64(w + 48) != 0:
        __ub_title(c, __load64(w), t)
    return 0

func __nat__native_ui__window_set_size(n: int, a: int, b: int, c0: int) -> int:
    __nat_exact("window_set_size", n, 3)
    id := __ui_handle("window_set_size", a)
    w := __ui_i32("window_set_size", b, "width")
    h := __ui_i32("window_set_size", c0, "height")
    c := __ui_core()
    win := __ui_win(c, id)
    if w <= 0 or h <= 0:
        __ui_fail("ui.window_set_size() : dimensions invalides", true)
    __store64(win + 16, w)
    __store64(win + 24, h)
    __store64(win + 64, 1)
    if __load64(win + 48) != 0:
        __ub_resize(c, __load64(win), w, h + __load64(win + 88))
    return 0

func __nat__native_ui__window_run(n: int, a: int) -> int:
    __nat_exact("window_run", n, 1)
    id := __ui_handle("window_run", a)
    c := __ui_core()
    w := __ui_win(c, id)
    __store64(w + 40, 1)
    __store64(w + 64, 1)
    __ub_show(c, __load64(w), true)
    __ui_flush(c)
    if not __ui_interactive(c):
        return 0
    while __load64(w + 48) != 0:
        __ui_pump(c, true)
    return 0

func __nat__native_ui__window_poll(n: int, a: int) -> int:
    __nat_exact("window_poll", n, 1)
    id := __ui_handle("window_poll", a)
    ev := __ui_window_poll(__ui_core(), id)
    if ev == 0:
        return 0
    t := __ui_s(ev, 0)
    d := __dyn_dict_new()
    __nat_dict_put(d, "type", __dyn_str(t))
    wv := __load64(ev + 8)
    if wv == 0:
        wv = id
    __nat_dict_put(d, "window", __dyn_int(wv))
    __nat_dict_put(d, "widget", __dyn_int(__load64(ev + 16)))
    __nat_dict_put(d, "data", __dyn_str(__ui_s(ev, 24)))
    if __load64(ev + 32) != 0:
        __nat_dict_put(d, "x", __dyn_int(__load64(ev + 40)))
        __nat_dict_put(d, "y", __dyn_int(__load64(ev + 48)))
    if __rt_str_eq(t, "key_down"):
        __nat_dict_put(d, "key", __dyn_int(__load64(ev + 72)))
        __nat_dict_put(d, "mods", __dyn_int(__load64(ev + 80)))
        __nat_dict_put(d, "text", __dyn_str(__ui_s(ev, 88)))
    elif __rt_str_eq(t, "key_up"):
        __nat_dict_put(d, "key", __dyn_int(__load64(ev + 72)))
        __nat_dict_put(d, "mods", __dyn_int(__load64(ev + 80)))
    elif __rt_str_eq(t, "pointer_down") or __rt_str_eq(t, "pointer_up"):
        __nat_dict_put(d, "button", __dyn_int(__load64(ev + 72)))
        __nat_dict_put(d, "mods", __dyn_int(__load64(ev + 80)))
    elif __rt_str_eq(t, "pointer_move") or __rt_str_eq(t, "pointer_leave"):
        __nat_dict_put(d, "mods", __dyn_int(__load64(ev + 80)))
    elif __rt_str_eq(t, "wheel"):
        __nat_dict_put(d, "dx", __dyn_float(__uf_get(ev, 56)))
        __nat_dict_put(d, "dy", __dyn_float(__uf_get(ev, 64)))
        __nat_dict_put(d, "mods", __dyn_int(__load64(ev + 80)))
    return d

func __ui_create_w(fn: str, kind: str, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, hasText: bool) -> int:
    __nat_exact(fn, n, 6)
    p := __ui_handle(fn, a0)
    text := ""
    if hasText:
        text = __ui_str(fn, a1, "text")
    x := __ui_i32(fn, a2, "x")
    y := __ui_i32(fn, a3, "y")
    w := __ui_i32(fn, a4, "width")
    h := __ui_i32(fn, a5, "height")
    return __dyn_int(__ui_widget_create(__ui_core(), kind, p, text, x, y, w, h))

func __nat__native_ui__button_create(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    return __ui_create_w("button_create", "button", n, a, b, c, d, e, f, true)

func __nat__native_ui__label_create(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    return __ui_create_w("label_create", "label", n, a, b, c, d, e, f, true)

func __nat__native_ui__input_create(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    return __ui_create_w("input_create", "input", n, a, b, c, d, e, f, true)

func __nat__native_ui__checkbox_create(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    return __ui_create_w("checkbox_create", "checkbox", n, a, b, c, d, e, f, true)

func __nat__native_ui__radio_create(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    return __ui_create_w("radio_create", "radio", n, a, b, c, d, e, f, true)

func __nat__native_ui__combo_create(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    return __ui_create_w("combo_create", "combo", n, a, b, c, d, e, f, true)

func __nat__native_ui__progress_create(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    return __ui_create_w("progress_create", "progress", n, a, b, c, d, e, f, false)

func __nat__native_ui__scroll_create(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("scroll_create", n, 5)
    p := __ui_handle("scroll_create", a)
    x := __ui_i32("scroll_create", b, "x")
    y := __ui_i32("scroll_create", c, "y")
    w := __ui_i32("scroll_create", d, "width")
    h := __ui_i32("scroll_create", e, "height")
    return __dyn_int(__ui_widget_create(__ui_core(), "scroll", p, "", x, y, w, h))

func __nat__native_ui__combo_add_item(n: int, a: int, b: int) -> int:
    __nat_exact("combo_add_item", n, 2)
    id := __ui_handle("combo_add_item", a)
    t := __ui_str("combo_add_item", b, "text")
    c := __ui_core()
    d := __ui_widget(c, id)
    __rt_list_push(__load64(d + 104), __str_addr(t))
    if __load64(d + 112) < 0:
        __store64(d + 112, 0)
    __ui_dirty(c, d)
    return 0

func __nat__native_ui__widget_get_checked(n: int, a: int) -> int:
    __nat_exact("widget_get_checked", n, 1)
    id := __ui_handle("widget_get_checked", a)
    return __dyn_bool(__load64(__ui_widget(__ui_core(), id) + 88) != 0)

func __nat__native_ui__widget_set_checked(n: int, a: int, b: int) -> int:
    __nat_exact("widget_set_checked", n, 2)
    id := __ui_handle("widget_set_checked", a)
    v := __ui_bool("widget_set_checked", b, "checked")
    c := __ui_core()
    d := __ui_widget(c, id)
    if v:
        __store64(d + 88, 1)
    else:
        __store64(d + 88, 0)
    if v and __uw_is(d, "radio"):
        w := __ui_find_win(c, __load64(d + 8))
        if w != 0:
            __ui_select_radio(c, w, d)
    __ui_dirty(c, d)
    return 0

func __nat__native_ui__progress_set(n: int, a: int, b: int) -> int:
    __nat_exact("progress_set", n, 2)
    id := __ui_handle("progress_set", a)
    v := __ui_i32("progress_set", b, "value")
    c := __ui_core()
    d := __ui_widget(c, id)
    if v < 0:
        v = 0
    if v > 100:
        v = 100
    __store64(d + 96, v)
    __ui_dirty(c, d)
    return 0

func __nat__native_ui__widget_set_text(n: int, a: int, b: int) -> int:
    __nat_exact("widget_set_text", n, 2)
    id := __ui_handle("widget_set_text", a)
    t := __ui_str("widget_set_text", b, "text")
    c := __ui_core()
    d := __ui_widget(c, id)
    __ui_sets(d, 24, t)
    if __uw_is(d, "input"):
        __store64(d + 128, __nat_blen(t))
    __ui_dirty(c, d)
    return 0

func __nat__native_ui__widget_get_text(n: int, a: int) -> int:
    __nat_exact("widget_get_text", n, 1)
    id := __ui_handle("widget_get_text", a)
    d := __ui_widget(__ui_core(), id)
    items := __load64(d + 104)
    sel := __load64(d + 112)
    if __uw_is(d, "combo") and sel >= 0 and sel < __load64(items):
        return __dyn_str(__as_str(__rt_vec_at(items, sel)))
    return __dyn_str(__ui_s(d, 24))

func __ui_set_flag(fn: str, n: int, a: int, b: int, label: str, off: int) -> int:
    __nat_exact(fn, n, 2)
    id := __ui_handle(fn, a)
    v := __ui_bool(fn, b, label)
    c := __ui_core()
    d := __ui_widget(c, id)
    if v:
        __store64(d + off, 1)
    else:
        __store64(d + off, 0)
    __ui_dirty(c, d)
    return 0

func __nat__native_ui__widget_set_visible(n: int, a: int, b: int) -> int:
    return __ui_set_flag("widget_set_visible", n, a, b, "visible", 72)

func __nat__native_ui__widget_set_enabled(n: int, a: int, b: int) -> int:
    return __ui_set_flag("widget_set_enabled", n, a, b, "enabled", 80)

func __ui_set_pair(fn: str, n: int, a: int, b: int, c0: int, l1: str, l2: str, off: int) -> int:
    __nat_exact(fn, n, 3)
    id := __ui_handle(fn, a)
    x := __ui_i32(fn, b, l1)
    y := __ui_i32(fn, c0, l2)
    c := __ui_core()
    d := __ui_widget(c, id)
    __store64(d + off, x)
    __store64(d + off + 8, y)
    __ui_dirty(c, d)
    return 0

func __nat__native_ui__widget_set_position(n: int, a: int, b: int, c: int) -> int:
    return __ui_set_pair("widget_set_position", n, a, b, c, "x", "y", 40)

func __nat__native_ui__widget_set_size(n: int, a: int, b: int, c: int) -> int:
    return __ui_set_pair("widget_set_size", n, a, b, c, "width", "height", 56)

func __nat__native_ui__notify(n: int, a: int, b: int) -> int:
    __nat_exact("notify", n, 2)
    t := __ui_str("notify", a, "title")
    m := __ui_str("notify", b, "message")
    __ui_notify(t, m)
    return 0

func __nat__native_ui__clipboard_set(n: int, a: int) -> int:
    __nat_exact("clipboard_set", n, 1)
    t := __ui_str("clipboard_set", a, "text")
    __ui_clipboard_set(__ui_core(), t)
    return 0

func __nat__native_ui__clipboard_get(n: int) -> int:
    __nat_exact("clipboard_get", n, 0)
    r := __ui_clipboard_get(__ui_core())
    if r == 0:
        return 0
    return __dyn_str(__as_str(r))

func __nat__native_ui__shortcut_register(n: int, a: int, b: int, c0: int, d: int) -> int:
    __nat_exact("shortcut_register", n, 4)
    h := __ui_handle("shortcut_register", a)
    id := __ui_i32("shortcut_register", b, "id")
    mods := __ui_i32("shortcut_register", c0, "modifiers")
    key := __ui_i32("shortcut_register", d, "key")
    w := __ui_win(__ui_core(), h)
    sc := __alloc(16)
    __store64(sc, mods & 15)
    __store64(sc + 8, key)
    __rt_dict_set(__load64(w + 152), id, sc, 0)
    return __dyn_bool(true)

func __nat__native_ui__shortcut_unregister(n: int, a: int, b: int) -> int:
    __nat_exact("shortcut_unregister", n, 2)
    h := __ui_handle("shortcut_unregister", a)
    id := __ui_i32("shortcut_unregister", b, "id")
    scs := __load64(__ui_win(__ui_core(), h) + 152)
    if __rt_dict_index(scs, id, 0) < 0:
        return __dyn_bool(false)
    __rt_dict_remove(scs, id, 0)
    return __dyn_bool(true)

func __nat__native_ui__screen_info(n: int) -> int:
    __nat_exact("screen_info", n, 0)
    c := __ui_core()
    __ui_require_backend(c)
    sc := __ub_screen(c)
    d := __dyn_dict_new()
    __nat_dict_put(d, "width", __dyn_int(__load64(sc)))
    __nat_dict_put(d, "height", __dyn_int(__load64(sc + 8)))
    __nat_dict_put(d, "work_width", __dyn_int(__load64(sc + 16)))
    __nat_dict_put(d, "work_height", __dyn_int(__load64(sc + 24)))
    return d

func __nat__native_ui__dpi(n: int, a: int) -> int:
    __nat_exact("dpi", n, 1)
    id := __ui_handle("dpi", a)
    c := __ui_core()
    __ui_win(c, id)
    return __dyn_int(__ub_dpi(c))

# Filtre Win32 « Description\0*.ext\0... » ; sélecteur zenity, puis kdialog.
func __ui_file_dialog(save: bool, filter: str) -> int:
    parts := __rt_list_new(0)
    p := __nat_bp(filter)
    nb := __nat_blen(filter)
    st := 0
    i := 0
    while i < nb:
        if __load8(p + i) == 0:
            __rt_list_push(parts, __str_addr(__nat_make(p + st, i - st)))
            st = i + 1
        i += 1
    if nb > st:
        __rt_list_push(parts, __str_addr(__nat_make(p + st, nb - st)))
    zen := __rt_list_new(0)
    __rt_list_push(zen, __str_addr("--file-selection"))
    if save:
        __rt_list_push(zen, __str_addr("--save"))
        __rt_list_push(zen, __str_addr("--confirm-overwrite"))
    kfilter := ""
    i = 0
    while i + 1 < __load64(parts):
        desc := __as_str(__rt_vec_at(parts, i))
        pat0 := __as_str(__rt_vec_at(parts, i + 1))
        i += 2
        if __rt_str_eq(pat0, "*.*") or __rt_str_eq(pat0, "*"):
            continue
        sb := __rt_sb_new()
        pp := __nat_bp(pat0)
        k := 0
        while k < __nat_blen(pat0):
            ch := __load8(pp + k)
            if ch == 59:
                ch = 32
            __rt_sb_byte(sb, ch)
            k += 1
        pat := __rt_sb_str(sb)
        __rt_list_push(zen, __str_addr("--file-filter=" + desc + " | " + pat))
        if __nat_blen(kfilter) > 0:
            kfilter = kfilter + "\n"
        kfilter = kfilter + pat + "|" + desc
    r := __ui_run("zenity", zen, "", false, true)
    if __load64(r) == 0:
        kd := __rt_list_new(0)
        if save:
            __rt_list_push(kd, __str_addr("--getsavefilename"))
        else:
            __rt_list_push(kd, __str_addr("--getopenfilename"))
        __rt_list_push(kd, __str_addr("."))
        __rt_list_push(kd, __str_addr(kfilter))
        r = __ui_run("kdialog", kd, "", false, true)
        if __load64(r) == 0:
            __ui_fail("ui.file_dialog() : aucun sélecteur de fichiers trouvé (installez zenity ou kdialog)", false)
    if __load64(r + 8) != 0:
        return 0
    res := __ui_s(r, 16)
    m := __nat_blen(res)
    while m > 0 and (__load8(__nat_bp(res) + m - 1) == 10 or __load8(__nat_bp(res) + m - 1) == 13):
        m -= 1
    if m == 0:
        return 0
    return __dyn_str(__nat_sub(res, 0, m))

func __nat__native_ui__file_open(n: int, a: int) -> int:
    __nat_exact("file_open", n, 1)
    return __ui_file_dialog(false, __ui_str("file_open", a, "filter"))

func __nat__native_ui__file_save(n: int, a: int) -> int:
    __nat_exact("file_save", n, 1)
    return __ui_file_dialog(true, __ui_str("file_save", a, "filter"))

func __nat__native_ui__menu_create(n: int, a: int) -> int:
    __nat_exact("menu_create", n, 1)
    h := __ui_handle("menu_create", a)
    c := __ui_core()
    w := __ui_win(c, h)
    m := __alloc(24)
    id := __ui_new_id(c)
    __store64(m, id)
    __store64(m + 8, __load64(w))
    __store64(m + 16, __rt_list_new(0))
    __rt_dict_set(__load64(c + 40), id, m, 0)
    return __dyn_int(id)

func __nat__native_ui__menu_add_item(n: int, a: int, b: int, c0: int) -> int:
    __nat_exact("menu_add_item", n, 3)
    h := __ui_handle("menu_add_item", a)
    id := __ui_i32("menu_add_item", b, "id")
    t := __ui_str("menu_add_item", c0, "text")
    c := __ui_core()
    m := __ui_get(__load64(c + 40), h)
    if m == 0:
        __ui_fail("ui : menu inconnu", true)
    it := __alloc(16)
    __store64(it, id)
    __ui_sets(it, 8, t)
    __rt_list_push(__load64(m + 16), it)
    w := __ui_find_win(c, __load64(m + 8))
    if w != 0:
        __store64(w + 64, 1)
    return 0

func __nat__native_ui__menu_attach(n: int, a: int, b: int) -> int:
    __nat_exact("menu_attach", n, 2)
    h := __ui_handle("menu_attach", a)
    mh := __ui_handle("menu_attach", b)
    c := __ui_core()
    w := __ui_win(c, h)
    if __ui_get(__load64(c + 40), mh) == 0:
        __ui_fail("ui : menu inconnu", true)
    had := __load64(w + 88) > 0
    __store64(w + 104, mh)
    __store64(w + 88, 26)
    __store64(w + 64, 1)
    if not had and __load64(w + 48) != 0:
        __ub_resize(c, __load64(w), __load64(w + 16), __load64(w + 24) + 26)
    return 0

# strtol(s, &end, 16) sur les 6 caractères d'une couleur « #RRGGBB » : valeur, ou -1 si invalide.
func __ui_hexdig(c: int) -> int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55
    return -1

func __ui_strtol16(p: int, n: int, ok: int) -> int:
    i := 0
    while i < n and (__load8(p + i) == 32 or (__load8(p + i) >= 9 and __load8(p + i) <= 13)):
        i += 1
    neg := false
    if i < n and (__load8(p + i) == 43 or __load8(p + i) == 45):
        neg = __load8(p + i) == 45
        i += 1
    if i + 1 < n and __load8(p + i) == 48 and (__load8(p + i + 1) == 120 or __load8(p + i + 1) == 88) and i + 2 < n and __ui_hexdig(__load8(p + i + 2)) >= 0:
        i += 2
    st := i
    v := 0
    while i < n and __ui_hexdig(__load8(p + i)) >= 0:
        v = v * 16 + __ui_hexdig(__load8(p + i))
        i += 1
    __store64(ok, 0)
    if i == st or i != n:
        return 0
    __store64(ok, 1)
    if neg:
        return 0 - v
    return v

func __ui_dict_get(d: int, key: str) -> int: # valeur, ou 1 si absente
    if not __dyn_is(d, 9):
        return 1
    return __dyn_dict_get_raw(d, __dyn_str(key))

func __ui_parse_color(cv: int) -> int:
    if cv == 1 or not __dyn_is(cv, 9):
        return -1
    ok := __alloc_raw(8)
    k := 0
    while k < 2:
        key := "hex"
        if k == 1:
            key = "value"
        v := __ui_dict_get(cv, key)
        if v != 1 and __dyn_is_str(v):
            s := __dyn_sv(v)
            if __rt_str_eq(s, "transparent"):
                return -2
            if __nat_blen(s) == 7 and __load8(__nat_bp(s)) == 35:
                r := __ui_strtol16(__nat_bp(s) + 1, 6, ok)
                if __load64(ok) != 0:
                    return r
        k += 1
    r := __ui_dict_get(cv, "r")
    g := __ui_dict_get(cv, "g")
    b := __ui_dict_get(cv, "b")
    if r != 1 and g != 1 and b != 1 and __dyn_is(r, 1) and __dyn_is(g, 1) and __dyn_is(b, 1):
        return ((__dyn_iv(r) & 255) << 16) | ((__dyn_iv(g) & 255) << 8) | (__dyn_iv(b) & 255)
    return -1

func __nat__native_ui__widget_set_style(n: int, a: int, b: int) -> int:
    __nat_exact("widget_set_style", n, 2)
    id := __ui_handle("widget_set_style", a)
    if not __dyn_is(b, 9):
        __dyn_err("TypeError", "'widget_set_style' : style doit être un dict")
    bg := __ui_parse_color(__ui_dict_get(b, "background"))
    fg := __ui_parse_color(__ui_dict_get(b, "foreground"))
    radius := -1.0
    rv := __ui_dict_get(b, "radius")
    if rv != 1:
        if __dyn_is(rv, 1):
            radius = __i2f(__dyn_iv(rv))
        elif __dyn_is(rv, 2):
            radius = __dyn_fv(rv)
    c := __ui_core()
    d := __ui_widget(c, id)
    if bg != -1:
        __store64(d + 136, bg)
    if fg != -1:
        __store64(d + 144, fg)
    if radius >= 0.0:
        __uf_set(d, 152, radius)
    __ui_dirty(c, d)
    return 0

func __nat__native_ui__inject_mouse(n: int, a: int, b: int, c0: int, d: int, e: int, f: int) -> int:
    __nat_exact("inject_mouse", n, 6)
    h := __ui_handle("inject_mouse", a)
    k := __ui_str("inject_mouse", b, "kind")
    x := __ui_i32("inject_mouse", c0, "x")
    y := __ui_i32("inject_mouse", d, "y")
    bt := __ui_i32("inject_mouse", e, "button")
    m := __ui_i32("inject_mouse", f, "modifiers")
    __ui_inject_mouse(__ui_core(), h, k, x, y, bt, m)
    return 0

func __nat__native_ui__inject_wheel(n: int, a: int, b: int, c0: int, d: int, e: int, f: int) -> int:
    __nat_exact("inject_wheel", n, 6)
    h := __ui_handle("inject_wheel", a)
    x := __ui_i32("inject_wheel", b, "x")
    y := __ui_i32("inject_wheel", c0, "y")
    dx := __ui_i32("inject_wheel", d, "dx")
    dy := __ui_i32("inject_wheel", e, "dy")
    m := __ui_i32("inject_wheel", f, "modifiers")
    c := __ui_core()
    w := __ui_win(c, h)
    fy := y + __load64(w + 88)
    if dy != 0:
        __ui_on_mouse(c, __load64(w), 3, x, fy, dy, m)
    if dx != 0:
        __ui_on_mouse(c, __load64(w), 4, x, fy, dx, m)
    return 0

func __nat__native_ui__inject_close(n: int, a: int) -> int:
    __nat_exact("inject_close", n, 1)
    h := __ui_handle("inject_close", a)
    c := __ui_core()
    __ui_on_close_request(c, __load64(__ui_win(c, h)))
    return 0

func __nat__native_ui__window_set_confirm_close(n: int, a: int, b: int) -> int:
    __nat_exact("window_set_confirm_close", n, 2)
    h := __ui_handle("window_set_confirm_close", a)
    v := __ui_bool("window_set_confirm_close", b, "enabled")
    w := __ui_win(__ui_core(), h)
    if v:
        __store64(w + 72, 1)
    else:
        __store64(w + 72, 0)
    return 0

func __nat__native_ui__window_set_cursor(n: int, a: int, b: int) -> int:
    __nat_exact("window_set_cursor", n, 2)
    h := __ui_handle("window_set_cursor", a)
    nm := __ui_str("window_set_cursor", b, "name")
    w := __ui_win(__ui_core(), h)
    if not __ui_cursor_ok(nm):
        __ui_fail("ui.window_set_cursor() : curseur inconnu '" + nm + "'", true)
    if __rt_str_eq(__ui_s(w, 80), nm):
        return 0
    __ui_sets(w, 80, nm)
    if __load64(w + 48) != 0:
        __ub_cursor(__ui_core(), __load64(w), nm)
    return 0

func __nat__native_ui__window_get_cursor(n: int, a: int) -> int:
    __nat_exact("window_get_cursor", n, 1)
    h := __ui_handle("window_get_cursor", a)
    return __dyn_str(__ui_s(__ui_win(__ui_core(), h), 80))

func __nat__native_ui__inject_key(n: int, a: int, b: int, c0: int) -> int:
    __nat_exact("inject_key", n, 3)
    h := __ui_handle("inject_key", a)
    vk := __ui_i32("inject_key", b, "key")
    m := __ui_i32("inject_key", c0, "modifiers")
    c := __ui_core()
    __ui_on_key(c, __load64(__ui_win(c, h)), vk, m, "")
    return 0

func __nat__native_ui__inject_text(n: int, a: int, b: int) -> int:
    __nat_exact("inject_text", n, 2)
    h := __ui_handle("inject_text", a)
    t := __ui_str("inject_text", b, "text")
    c := __ui_core()
    id := __load64(__ui_win(c, h))
    cps := __ua_decode(t)
    i := 0
    while i < __load64(cps):
        sb := __rt_sb_new()
        __nat_sb_cp(sb, __rt_vec_at(cps, i))
        __ui_on_key(c, id, 0, 0, __rt_sb_str(sb))
        i += 1
    return 0

func __nat__native_ui__window_screenshot(n: int, a: int, b: int) -> int:
    __nat_exact("window_screenshot", n, 2)
    h := __ui_handle("window_screenshot", a)
    p := __ui_str("window_screenshot", b, "path")
    c := __ui_core()
    w := __ui_win(c, h)
    __ui_compose(c, w)
    return __dyn_bool(__us_save_png(__load64(w + 160), p))

func __nat__native_ui__window_set_position(n: int, a: int, b: int, c0: int) -> int:
    __nat_exact("window_set_position", n, 3)
    h := __ui_handle("window_set_position", a)
    x := __ui_i32("window_set_position", b, "x")
    y := __ui_i32("window_set_position", c0, "y")
    c := __ui_core()
    w := __ui_win(c, h)
    if __load64(w + 48) == 0:
        __ui_fail("ui.window_set_position() : fenêtre fermée", true)
    __ub_move(c, __load64(w), x, y)
    if not __ui_interactive(c):
        __ui_on_move(c, __load64(w), x, y)
    return 0

func __ui_b(p: int, off: int) -> int:
    return __dyn_bool(__load64(p + off) != 0)

func __nat__native_ui__window_info(n: int, a: int) -> int:
    __nat_exact("window_info", n, 1)
    h := __ui_handle("window_info", a)
    c := __ui_core()
    w := __ui_win(c, h)
    pos := __alloc(16)
    if __load64(w + 48) != 0 and __ub_position(c, __load64(w), pos):
        __store64(w + 168, __load64(pos))
        __store64(w + 176, __load64(pos + 8))
        __store64(w + 184, 1)
    d := __dyn_dict_new()
    __nat_dict_put(d, "x", __dyn_int(__load64(w + 168)))
    __nat_dict_put(d, "y", __dyn_int(__load64(w + 176)))
    __nat_dict_put(d, "width", __dyn_int(__load64(w + 16)))
    __nat_dict_put(d, "height", __dyn_int(__load64(w + 24)))
    __nat_dict_put(d, "state", __dyn_str(__ui_s(w, 192)))
    __nat_dict_put(d, "title", __dyn_str(__ui_s(w, 8)))
    __nat_dict_put(d, "visible", __ui_b(w, 40))
    __nat_dict_put(d, "alive", __ui_b(w, 48))
    __nat_dict_put(d, "focused", __ui_b(w, 232))
    __nat_dict_put(d, "resizable", __ui_b(w, 240))
    __nat_dict_put(d, "decorated", __ui_b(w, 248))
    __nat_dict_put(d, "topmost", __ui_b(w, 256))
    __nat_dict_put(d, "opacity", __dyn_float(__uf_get(w, 264)))
    __nat_dict_put(d, "min_width", __dyn_int(__load64(w + 272)))
    __nat_dict_put(d, "min_height", __dyn_int(__load64(w + 280)))
    __nat_dict_put(d, "max_width", __dyn_int(__load64(w + 288)))
    __nat_dict_put(d, "max_height", __dyn_int(__load64(w + 296)))
    return d

func __nat__native_ui__window_set_state(n: int, a: int, b: int) -> int:
    __nat_exact("window_set_state", n, 2)
    h := __ui_handle("window_set_state", a)
    st := __ui_str("window_set_state", b, "state")
    if not (__rt_str_eq(st, "normal") or __rt_str_eq(st, "minimized") or __rt_str_eq(st, "maximized") or __rt_str_eq(st, "fullscreen")):
        __dyn_err("ArgumentError", "ui.window_set_state() : état inconnu '" + st + "' (normal, minimized, maximized, fullscreen)")
    c := __ui_core()
    __ui_set_state(c, __ui_win(c, h), st)
    return 0

func __nat__native_ui__window_set_hints(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                        a7: int, x: int) -> int:
    __nat_exact("window_set_hints", n, 9)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle("window_set_hints", __ui_at(v, 0))
    rs := __ui_bool("window_set_hints", __ui_at(v, 1), "resizable")
    dec := __ui_bool("window_set_hints", __ui_at(v, 2), "decorated")
    top := __ui_bool("window_set_hints", __ui_at(v, 3), "topmost")
    op := __ui_num("window_set_hints", __ui_at(v, 4), "opacity")
    m0 := __ui_i32("window_set_hints", __ui_at(v, 5), "taille")
    m1 := __ui_i32("window_set_hints", __ui_at(v, 6), "taille")
    m2 := __ui_i32("window_set_hints", __ui_at(v, 7), "taille")
    m3 := __ui_i32("window_set_hints", __ui_at(v, 8), "taille")
    c := __ui_core()
    __ui_set_hints(c, __ui_win(c, h), rs, dec, top, op, m0, m1, m2, m3)
    return 0

func __nat__native_ui__window_focus(n: int, a: int) -> int:
    __nat_exact("window_focus", n, 1)
    h := __ui_handle("window_focus", a)
    c := __ui_core()
    w := __ui_win(c, h)
    if __load64(w + 48) == 0:
        __ui_fail("ui.window_focus() : fenêtre fermée", true)
    __ub_focus(c, __load64(w))
    if not __ui_interactive(c):
        __ui_on_focus(c, __load64(w), true)
    return 0

func __nat__native_ui__window_list(n: int) -> int:
    __nat_exact("window_list", n, 0)
    l := __dyn_list_new(0)
    ws := __load64(__ui_core() + 24)
    ks := __rt_dict_list(ws, 24)
    i := 0
    while i < __load64(ks):
        id := __rt_vec_at(ks, i)
        if __load64(__ui_get(ws, id) + 48) != 0:
            __dyn_list_push(l, __dyn_int(id))
        i += 1
    return l

func __nat__native_ui__inject_key_up(n: int, a: int, b: int, c0: int) -> int:
    __nat_exact("inject_key_up", n, 3)
    h := __ui_handle("inject_key_up", a)
    vk := __ui_i32("inject_key_up", b, "key")
    m := __ui_i32("inject_key_up", c0, "mods")
    c := __ui_core()
    __ui_on_key_up(c, __load64(__ui_win(c, h)), vk, m)
    return 0

# ---- canvas ----

func __nat__native_ui__canvas_create(n: int, a: int) -> int:
    __nat_exact("canvas_create", n, 1)
    h := __ui_handle("canvas_create", a)
    c := __ui_core()
    w := __ui_win(c, h)
    o := __alloc(32)
    id := __ui_new_id(c)
    __store64(o, id)
    __store64(o + 8, __load64(w))
    __store64(o + 16, __us_new(__load64(w + 16), __load64(w + 24)))
    __rt_dict_set(__load64(c + 48), id, o, 0)
    __store64(w + 96, id)
    return __dyn_int(id)

func __nat__native_ui__canvas_destroy(n: int, a: int) -> int:
    __nat_exact("canvas_destroy", n, 1)
    h := __ui_handle("canvas_destroy", a)
    c := __ui_core()
    cs := __load64(c + 48)
    o := __ui_get(cs, h)
    if o == 0:
        return __dyn_bool(false)
    w := __ui_find_win(c, __load64(o + 8))
    if w != 0:
        if __load64(w + 96) == h:
            __store64(w + 96, 0)
        __store64(w + 64, 1)
    __rt_dict_remove(cs, h, 0)
    return __dyn_bool(true)

func __nat__native_ui__canvas_resize(n: int, a: int) -> int:
    __nat_exact("canvas_resize", n, 1)
    h := __ui_handle("canvas_resize", a)
    c := __ui_core()
    o := __ui_get(__load64(c + 48), h)
    if o == 0:
        return __dyn_bool(false)
    w := __ui_find_win(c, __load64(o + 8))
    if w == 0:
        return __dyn_bool(false)
    __us_resize(__load64(o + 16), __load64(w + 16), __load64(w + 24))
    __store64(o + 24, 0)
    __store64(w + 64, 1)
    return __dyn_bool(true)

func __nat__native_ui__canvas_begin(n: int, a: int) -> int:
    __nat_exact("canvas_begin", n, 1)
    s := __ui_canvas(__ui_handle("canvas_begin", a))
    if s == 0:
        return __dyn_bool(false)
    __us_reset_state(s)
    return __dyn_bool(true)

func __nat__native_ui__canvas_end(n: int, a: int) -> int:
    __nat_exact("canvas_end", n, 1)
    h := __ui_handle("canvas_end", a)
    c := __ui_core()
    o := __ui_get(__load64(c + 48), h)
    if o == 0:
        return __dyn_bool(false)
    __store64(o + 24, 1)
    w := __ui_find_win(c, __load64(o + 8))
    if w != 0:
        __store64(w + 64, 1)
    return __dyn_bool(true)

func __nat__native_ui__canvas_clear(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("canvas_clear", n, 5)
    h := __ui_handle("canvas_clear", a)
    al := __ui_i32("canvas_clear", e, "a")
    bl := __ui_i32("canvas_clear", d, "b")
    gr := __ui_i32("canvas_clear", c, "g")
    rd := __ui_i32("canvas_clear", b, "r")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_clear(s, __ui_rgba(rd, gr, bl, al))
    return __dyn_bool(true)

# Les arguments des appels C sont évalués de droite à gauche (g++) : même ordre des contrôles.
func __nat__native_ui__canvas_fill_rect(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                        a7: int, x: int) -> int:
    fn := "canvas_fill_rect"
    __nat_exact(fn, n, 11)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    op := __ui_num(fn, __ui_at(v, 10), "opacity")
    al := __ui_i32(fn, __ui_at(v, 9), "a")
    bl := __ui_i32(fn, __ui_at(v, 8), "b")
    gr := __ui_i32(fn, __ui_at(v, 7), "g")
    rd := __ui_i32(fn, __ui_at(v, 6), "r")
    kind := __ui_str(fn, __ui_at(v, 5), "kind")
    hh := __ui_num(fn, __ui_at(v, 4), "h")
    ww := __ui_num(fn, __ui_at(v, 3), "w")
    yy := __ui_num(fn, __ui_at(v, 2), "y")
    xx := __ui_num(fn, __ui_at(v, 1), "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_fill_rect(s, xx, yy, ww, hh, __ui_paint(kind, rd, gr, bl, al, op, 1.0))
    return __dyn_bool(true)

func __nat__native_ui__canvas_stroke_rect(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                          a7: int, x: int) -> int:
    fn := "canvas_stroke_rect"
    __nat_exact(fn, n, 11)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    sw := __ui_num(fn, __ui_at(v, 10), "width")
    op := __ui_num(fn, __ui_at(v, 9), "opacity")
    al := __ui_i32(fn, __ui_at(v, 8), "a")
    bl := __ui_i32(fn, __ui_at(v, 7), "b")
    gr := __ui_i32(fn, __ui_at(v, 6), "g")
    rd := __ui_i32(fn, __ui_at(v, 5), "r")
    hh := __ui_num(fn, __ui_at(v, 4), "h")
    ww := __ui_num(fn, __ui_at(v, 3), "w")
    yy := __ui_num(fn, __ui_at(v, 2), "y")
    xx := __ui_num(fn, __ui_at(v, 1), "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_fill_rect(s, xx, yy, ww, hh, __ui_paint("stroke", rd, gr, bl, al, op, sw))
    return __dyn_bool(true)

func __nat__native_ui__canvas_round_rect(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                         a7: int, x: int) -> int:
    fn := "canvas_round_rect"
    __nat_exact(fn, n, 13)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    sw := __ui_num(fn, __ui_at(v, 12), "width")
    op := __ui_num(fn, __ui_at(v, 11), "opacity")
    al := __ui_i32(fn, __ui_at(v, 10), "a")
    bl := __ui_i32(fn, __ui_at(v, 9), "b")
    gr := __ui_i32(fn, __ui_at(v, 8), "g")
    rd := __ui_i32(fn, __ui_at(v, 7), "r")
    kind := __ui_str(fn, __ui_at(v, 6), "kind")
    rad := __ui_num(fn, __ui_at(v, 5), "radius")
    hh := __ui_num(fn, __ui_at(v, 4), "h")
    ww := __ui_num(fn, __ui_at(v, 3), "w")
    yy := __ui_num(fn, __ui_at(v, 2), "y")
    xx := __ui_num(fn, __ui_at(v, 1), "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_round_rect(s, xx, yy, ww, hh, rad, __ui_paint(kind, rd, gr, bl, al, op, sw))
    return __dyn_bool(true)

func __nat__native_ui__canvas_circle(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                     a7: int, x: int) -> int:
    fn := "canvas_circle"
    __nat_exact(fn, n, 11)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    sw := __ui_num(fn, __ui_at(v, 10), "width")
    op := __ui_num(fn, __ui_at(v, 9), "opacity")
    al := __ui_i32(fn, __ui_at(v, 8), "a")
    bl := __ui_i32(fn, __ui_at(v, 7), "b")
    gr := __ui_i32(fn, __ui_at(v, 6), "g")
    rd := __ui_i32(fn, __ui_at(v, 5), "r")
    kind := __ui_str(fn, __ui_at(v, 4), "kind")
    rad := __ui_num(fn, __ui_at(v, 3), "radius")
    cy := __ui_num(fn, __ui_at(v, 2), "cy")
    cx := __ui_num(fn, __ui_at(v, 1), "cx")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_circle(s, cx, cy, rad, __ui_paint(kind, rd, gr, bl, al, op, sw))
    return __dyn_bool(true)

func __nat__native_ui__canvas_ellipse(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                      a7: int, x: int) -> int:
    fn := "canvas_ellipse"
    __nat_exact(fn, n, 12)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    sw := __ui_num(fn, __ui_at(v, 11), "width")
    op := __ui_num(fn, __ui_at(v, 10), "opacity")
    al := __ui_i32(fn, __ui_at(v, 9), "a")
    bl := __ui_i32(fn, __ui_at(v, 8), "b")
    gr := __ui_i32(fn, __ui_at(v, 7), "g")
    rd := __ui_i32(fn, __ui_at(v, 6), "r")
    kind := __ui_str(fn, __ui_at(v, 5), "kind")
    ry := __ui_num(fn, __ui_at(v, 4), "ry")
    rx := __ui_num(fn, __ui_at(v, 3), "rx")
    cy := __ui_num(fn, __ui_at(v, 2), "cy")
    cx := __ui_num(fn, __ui_at(v, 1), "cx")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_ellipse(s, cx, cy, rx, ry, __ui_paint(kind, rd, gr, bl, al, op, sw))
    return __dyn_bool(true)

func __nat__native_ui__canvas_line(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                   a7: int, x: int) -> int:
    fn := "canvas_line"
    __nat_exact(fn, n, 11)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    sw := __ui_num(fn, __ui_at(v, 10), "width")
    op := __ui_num(fn, __ui_at(v, 9), "opacity")
    al := __ui_i32(fn, __ui_at(v, 8), "a")
    bl := __ui_i32(fn, __ui_at(v, 7), "b")
    gr := __ui_i32(fn, __ui_at(v, 6), "g")
    rd := __ui_i32(fn, __ui_at(v, 5), "r")
    y2 := __ui_num(fn, __ui_at(v, 4), "y2")
    x2 := __ui_num(fn, __ui_at(v, 3), "x2")
    y1 := __ui_num(fn, __ui_at(v, 2), "y1")
    x1 := __ui_num(fn, __ui_at(v, 1), "x1")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_line(s, x1, y1, x2, y2, __ui_paint("stroke", rd, gr, bl, al, op, sw))
    return __dyn_bool(true)

func __nat__native_ui__canvas_path(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                   a7: int, x: int) -> int:
    fn := "canvas_path"
    __nat_exact(fn, n, 9)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    ph := __ui_handle(fn, __ui_at(v, 1))
    sw := __ui_num(fn, __ui_at(v, 8), "width")
    op := __ui_num(fn, __ui_at(v, 7), "opacity")
    al := __ui_i32(fn, __ui_at(v, 6), "a")
    bl := __ui_i32(fn, __ui_at(v, 5), "b")
    gr := __ui_i32(fn, __ui_at(v, 4), "g")
    rd := __ui_i32(fn, __ui_at(v, 3), "r")
    kind := __ui_str(fn, __ui_at(v, 2), "kind")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    p := __ui_get(__load64(__ui_core() + 56), ph)
    if p == 0:
        return __dyn_bool(false)
    __us_path(s, p, __ui_paint(kind, rd, gr, bl, al, op, sw))
    return __dyn_bool(true)

func __nat__native_ui__canvas_text(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                   a7: int, x: int) -> int:
    fn := "canvas_text"
    __nat_exact(fn, n, 11)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    text := __ui_str(fn, __ui_at(v, 1), "text")
    font := __ui_str(fn, __ui_at(v, 9), "font")
    size := __ui_num(fn, __ui_at(v, 10), "size")
    op := __ui_num(fn, __ui_at(v, 8), "opacity")
    al := __ui_i32(fn, __ui_at(v, 7), "a")
    bl := __ui_i32(fn, __ui_at(v, 6), "b")
    gr := __ui_i32(fn, __ui_at(v, 5), "g")
    rd := __ui_i32(fn, __ui_at(v, 4), "r")
    yy := __ui_num(fn, __ui_at(v, 3), "y")
    xx := __ui_num(fn, __ui_at(v, 2), "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_text(s, text, xx, yy, __ui_rgba(rd, gr, bl, al), op, size, __ua_font(font))
    return __dyn_bool(true)

func __nat__native_ui__canvas_image(n: int, a: int, b: int, c0: int, d: int, e: int, f: int, g: int) -> int:
    fn := "canvas_image"
    __nat_exact(fn, n, 7)
    h := __ui_handle(fn, a)
    ih := __ui_handle(fn, b)
    op := __ui_num(fn, g, "opacity")
    hh := __ui_num(fn, f, "h")
    ww := __ui_num(fn, e, "w")
    yy := __ui_num(fn, d, "y")
    xx := __ui_num(fn, c0, "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    img := __ui_get(__load64(__ui_core() + 64), ih)
    if img == 0:
        return __dyn_bool(false)
    __us_image(s, img, xx, yy, ww, hh, op)
    return __dyn_bool(true)

func __nat__native_ui__canvas_clip_rect(n: int, a: int, b: int, c0: int, d: int, e: int) -> int:
    fn := "canvas_clip_rect"
    __nat_exact(fn, n, 5)
    h := __ui_handle(fn, a)
    hh := __ui_num(fn, e, "h")
    ww := __ui_num(fn, d, "w")
    yy := __ui_num(fn, c0, "y")
    xx := __ui_num(fn, b, "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_set_clip(s, xx, yy, ww, hh)
    return __dyn_bool(true)

func __nat__native_ui__canvas_reset_clip(n: int, a: int) -> int:
    __nat_exact("canvas_reset_clip", n, 1)
    s := __ui_canvas(__ui_handle("canvas_reset_clip", a))
    if s == 0:
        return __dyn_bool(false)
    __store64(s + 80, 0)
    return __dyn_bool(true)

func __nat__native_ui__canvas_set_transform(n: int, a: int, b: int, c0: int, d: int, e: int, f: int, g: int) -> int:
    fn := "canvas_set_transform"
    __nat_exact(fn, n, 7)
    h := __ui_handle(fn, a)
    dy := __ui_num(fn, g, "dy")
    dx := __ui_num(fn, f, "dx")
    m22 := __ui_num(fn, e, "m22")
    m21 := __ui_num(fn, d, "m21")
    m12 := __ui_num(fn, c0, "m12")
    m11 := __ui_num(fn, b, "m11")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __uf_set(s, 24, m11)
    __uf_set(s, 32, m12)
    __uf_set(s, 40, m21)
    __uf_set(s, 48, m22)
    __uf_set(s, 56, dx)
    __uf_set(s, 64, dy)
    return __dyn_bool(true)

func __nat__native_ui__canvas_reset_transform(n: int, a: int) -> int:
    __nat_exact("canvas_reset_transform", n, 1)
    s := __ui_canvas(__ui_handle("canvas_reset_transform", a))
    if s == 0:
        return __dyn_bool(false)
    __us_identity(s)
    return __dyn_bool(true)

func __nat__native_ui__canvas_set_opacity(n: int, a: int, b: int) -> int:
    __nat_exact("canvas_set_opacity", n, 2)
    h := __ui_handle("canvas_set_opacity", a)
    op := __ui_num("canvas_set_opacity", b, "opacity")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    if op < 0.0:
        op = 0.0
    elif 1.0 < op:
        op = 1.0
    __uf_set(s, 72, op)
    return __dyn_bool(true)

func __nat__native_ui__canvas_shadow_round_rect(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int,
                                                a6: int, a7: int, x: int) -> int:
    fn := "canvas_shadow_round_rect"
    __nat_exact(fn, n, 18)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    op := __ui_num(fn, __ui_at(v, 17), "opacity")
    al := __ui_i32(fn, __ui_at(v, 16), "a")
    bl := __ui_i32(fn, __ui_at(v, 15), "b")
    gr := __ui_i32(fn, __ui_at(v, 14), "g")
    rd := __ui_i32(fn, __ui_at(v, 13), "r")
    oy := __ui_num(fn, __ui_at(v, 12), "offset_y")
    ox := __ui_num(fn, __ui_at(v, 11), "offset_x")
    blur := __ui_num(fn, __ui_at(v, 10), "blur")
    sop := __ui_num(fn, __ui_at(v, 9), "shadow_opacity")
    sb := __ui_i32(fn, __ui_at(v, 8), "sb")
    sg := __ui_i32(fn, __ui_at(v, 7), "sg")
    sr := __ui_i32(fn, __ui_at(v, 6), "sr")
    rad := __ui_num(fn, __ui_at(v, 5), "radius")
    hh := __ui_num(fn, __ui_at(v, 4), "h")
    ww := __ui_num(fn, __ui_at(v, 3), "w")
    yy := __ui_num(fn, __ui_at(v, 2), "y")
    xx := __ui_num(fn, __ui_at(v, 1), "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_shadow_rrect(s, xx, yy, ww, hh, rad, __ui_rgba(sr, sg, sb, 255), sop, blur, ox, oy, __ui_paint("fill", rd, gr, bl, al, op, 1.0))
    return __dyn_bool(true)

func __nat__native_ui__canvas_linear_gradient_rect(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int,
                                                   a6: int, a7: int, x: int) -> int:
    fn := "canvas_linear_gradient_rect"
    __nat_exact(fn, n, 18)
    v := __ui_args(n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    h := __ui_handle(fn, __ui_at(v, 0))
    op := __ui_num(fn, __ui_at(v, 17), "opacity")
    a2v := __ui_i32(fn, __ui_at(v, 16), "a2")
    b2 := __ui_i32(fn, __ui_at(v, 15), "b2")
    g2 := __ui_i32(fn, __ui_at(v, 14), "g2")
    r2 := __ui_i32(fn, __ui_at(v, 13), "r2")
    a1v := __ui_i32(fn, __ui_at(v, 12), "a1")
    b1 := __ui_i32(fn, __ui_at(v, 11), "b1")
    g1 := __ui_i32(fn, __ui_at(v, 10), "g1")
    r1 := __ui_i32(fn, __ui_at(v, 9), "r1")
    y2 := __ui_num(fn, __ui_at(v, 8), "y2")
    x2 := __ui_num(fn, __ui_at(v, 7), "x2")
    y1 := __ui_num(fn, __ui_at(v, 6), "y1")
    x1 := __ui_num(fn, __ui_at(v, 5), "x1")
    hh := __ui_num(fn, __ui_at(v, 4), "h")
    ww := __ui_num(fn, __ui_at(v, 3), "w")
    yy := __ui_num(fn, __ui_at(v, 2), "y")
    xx := __ui_num(fn, __ui_at(v, 1), "x")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    __us_gradient_rect(s, xx, yy, ww, hh, x1, y1, x2, y2, __ui_rgba(r1, g1, b1, a1v), __ui_rgba(r2, g2, b2, a2v), op)
    return __dyn_bool(true)

func __nat__native_ui__canvas_save_png(n: int, a: int, b: int) -> int:
    __nat_exact("canvas_save_png", n, 2)
    h := __ui_handle("canvas_save_png", a)
    p := __ui_str("canvas_save_png", b, "path")
    s := __ui_canvas(h)
    if s == 0:
        return __dyn_bool(false)
    return __dyn_bool(__us_save_png(s, p))

func __nat__native_ui__canvas_put_pixels(n: int, a: int, b: int, c0: int, d: int, e: int, f: int) -> int:
    fn := "canvas_put_pixels"
    __nat_exact(fn, n, 6)
    h := __ui_handle(fn, a)
    x := __ui_i32(fn, b, "x")
    y := __ui_i32(fn, c0, "y")
    w := __ui_i32(fn, d, "width")
    hh := __ui_i32(fn, e, "height")
    data := __ui_str(fn, f, "pixels")
    if w < 0 or hh < 0 or __nat_blen(data) != w * hh * 4:
        __dyn_err("ArgumentError", "ui.canvas_put_pixels() : largeur x hauteur x 4 octets attendus")
    c := __ui_core()
    o := __ui_get(__load64(c + 48), h)
    if o == 0:
        __dyn_err("ArgumentError", "ui.canvas_put_pixels() : canvas inconnu")
    s := __load64(o + 16)
    sw := __us_w(s)
    sh := __us_h(s)
    px := __us_px(s)
    src := __nat_bp(data)
    j := 0
    while j < hh:
        ty := y + j
        if ty >= 0 and ty < sh:
            i := 0
            while i < w:
                tx := x + i
                if tx >= 0 and tx < sw:
                    __store32(px + (ty * sw + tx) * 4, __load32(src + (j * w + i) * 4))
                i += 1
        j += 1
    win := __ui_find_win(c, __load64(o + 8))
    if win != 0:
        __store64(win + 64, 1)
    return 0

# ---- chemins et images ----

func __nat__native_ui__path_create(n: int) -> int:
    __nat_exact("path_create", n, 0)
    c := __ui_core()
    id := __ui_new_id(c)
    __rt_dict_set(__load64(c + 56), id, __ui_path_new(), 0)
    return __dyn_int(id)

func __ui_path_of(h: int) -> int:
    return __ui_get(__load64(__ui_core() + 56), h)

func __nat__native_ui__path_move_to(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("path_move_to", n, 3)
    h := __ui_handle("path_move_to", a)
    y := __ui_num("path_move_to", c, "y")
    x := __ui_num("path_move_to", b, "x")
    p := __ui_path_of(h)
    if p == 0:
        return __dyn_bool(false)
    __ui_path_cmd(p, 0, x, y, 0.0, 0.0, 0.0, 0.0)
    return __dyn_bool(true)

func __nat__native_ui__path_line_to(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("path_line_to", n, 3)
    h := __ui_handle("path_line_to", a)
    y := __ui_num("path_line_to", c, "y")
    x := __ui_num("path_line_to", b, "x")
    p := __ui_path_of(h)
    if p == 0:
        return __dyn_bool(false)
    __ui_path_cmd(p, 1, x, y, 0.0, 0.0, 0.0, 0.0)
    return __dyn_bool(true)

func __nat__native_ui__path_cubic_to(n: int, a: int, b: int, c: int, d: int, e: int, f: int, g: int) -> int:
    fn := "path_cubic_to"
    __nat_exact(fn, n, 7)
    h := __ui_handle(fn, a)
    y3 := __ui_num(fn, g, "y3")
    x3 := __ui_num(fn, f, "x3")
    y2 := __ui_num(fn, e, "y2")
    x2 := __ui_num(fn, d, "x2")
    y1 := __ui_num(fn, c, "y1")
    x1 := __ui_num(fn, b, "x1")
    p := __ui_path_of(h)
    if p == 0:
        return __dyn_bool(false)
    __ui_path_cmd(p, 2, x1, y1, x2, y2, x3, y3)
    return __dyn_bool(true)

func __nat__native_ui__path_quad_to(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    fn := "path_quad_to"
    __nat_exact(fn, n, 5)
    h := __ui_handle(fn, a)
    y2 := __ui_num(fn, e, "y2")
    x2 := __ui_num(fn, d, "x2")
    y1 := __ui_num(fn, c, "y1")
    x1 := __ui_num(fn, b, "x1")
    p := __ui_path_of(h)
    if p == 0:
        return __dyn_bool(false)
    __ui_path_cmd(p, 3, x1, y1, x2, y2, 0.0, 0.0)
    return __dyn_bool(true)

func __nat__native_ui__path_close(n: int, a: int) -> int:
    __nat_exact("path_close", n, 1)
    p := __ui_path_of(__ui_handle("path_close", a))
    if p == 0:
        return __dyn_bool(false)
    __ui_path_cmd(p, 4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
    return __dyn_bool(true)

func __ui_erase_id(off: int, h: int) -> int:
    d := __load64(__ui_core() + off)
    if __rt_dict_index(d, h, 0) < 0:
        return __dyn_bool(false)
    __rt_dict_remove(d, h, 0)
    return __dyn_bool(true)

func __nat__native_ui__path_destroy(n: int, a: int) -> int:
    __nat_exact("path_destroy", n, 1)
    return __ui_erase_id(56, __ui_handle("path_destroy", a))

func __nat__native_ui__image_load(n: int, a: int) -> int:
    __nat_exact("image_load", n, 1)
    p := __ui_str("image_load", a, "path")
    err := __alloc(8)
    __store64(err, __str_addr(""))
    img := __uimg_load(p, err)
    if img == 0:
        e := __as_str(__load64(err))
        if __nat_blen(e) == 0:
            e = "chargement impossible"
        elif __nat_blen(e) > 255:
            e = __nat_sub(e, 0, __ui_utf8_cut(e, 255))
        __dyn_err("IoError", "ui.image_load() : " + e)
    c := __ui_core()
    id := __ui_new_id(c)
    __rt_dict_set(__load64(c + 64), id, img, 0)
    return __dyn_int(id)

# snprintf dans un tampon de 256 octets : au plus 255 octets (coupure brute).
func __ui_utf8_cut(s: str, n: int) -> int:
    return n

func __ui_img_register(img: int) -> int:
    c := __ui_core()
    id := __ui_new_id(c)
    __rt_dict_set(__load64(c + 64), id, img, 0)
    return __dyn_int(id)

# Copie d'une zone (x, y, l, h) d'une image : nouvelle image (sprites, atlas). Zone bornée à l'image.
func __nat__native_ui__image_crop(n: int, a: int, b: int, c0: int, d: int, e: int) -> int:
    fn := "image_crop"
    __nat_exact(fn, n, 5)
    ih := __ui_handle(fn, a)
    src := __ui_get(__load64(__ui_core() + 64), ih)
    if src == 0:
        __dyn_err("ValueError", "ui.image_crop() : image inconnue")
    sw := __load64(src)
    sh := __load64(src + 8)
    x := __nat_int(fn, b, "x")
    y := __nat_int(fn, c0, "y")
    w := __nat_int(fn, d, "w")
    h := __nat_int(fn, e, "h")
    if x < 0:
        w += x
        x = 0
    if y < 0:
        h += y
        y = 0
    if x + w > sw:
        w = sw - x
    if y + h > sh:
        h = sh - y
    if w <= 0 or h <= 0:
        __dyn_err("ValueError", "ui.image_crop() : zone vide ou hors de l'image")
    img := __uimg_new(w, h)
    ps := __load64(src + 16)
    pd := __load64(img + 16)
    r := 0
    while r < h:
        __copy(pd + r * w * 4, ps + ((y + r) * sw + x) * 4, w * 4)
        r += 1
    return __ui_img_register(img)

# Image depuis des octets RGBA (list d'entiers 0..255, ligne du haut en premier).
func __nat__native_ui__image_create(n: int, a: int, b: int, c0: int) -> int:
    fn := "image_create"
    __nat_exact(fn, n, 3)
    w := __nat_int(fn, a, "w")
    h := __nat_int(fn, b, "h")
    if w <= 0 or h <= 0 or w > 16384 or h > 16384:
        __dyn_err("ValueError", "ui.image_create() : dimensions invalides")
    items := __nat_items(fn, c0, "les pixels", "une list")
    if __load64(items) != w * h * 4:
        __dyn_err("ValueError", "ui.image_create() : l x h x 4 octets attendus")
    img := __uimg_new(w, h)
    pd := __load64(img + 16)
    k := 0
    while k < w * h * 4:
        __store8(pd + k, __nat_int(fn, __rt_vec_at(items, k), "un octet") & 255)
        k += 1
    return __ui_img_register(img)

# [largeur, hauteur] d'une image.
func __nat__native_ui__image_size(n: int, a: int) -> int:
    __nat_exact("image_size", n, 1)
    img := __ui_get(__load64(__ui_core() + 64), __ui_handle("image_size", a))
    if img == 0:
        __dyn_err("ValueError", "ui.image_size() : image inconnue")
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__load64(img)))
    __dyn_list_push(l, __dyn_int(__load64(img + 8)))
    return l

func __nat__native_ui__image_destroy(n: int, a: int) -> int:
    __nat_exact("image_destroy", n, 1)
    return __ui_erase_id(64, __ui_handle("image_destroy", a))
