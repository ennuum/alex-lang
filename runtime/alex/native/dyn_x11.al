# alex: native
# Backend X11 du module ui (runtime dynamique, VM et exécutables natifs) : client du protocole X11 écrit
# directement sur le socket du serveur (domaine Unix /tmp/.X11-unix/X<n>, nom abstrait ou TCP 6000+n), sans
# Xlib. Même comportement que l'ancien backend C++ (Xlib) : une fenêtre X par fenêtre ui, le framebuffer RGBA
# composé par le cœur (dyn_ui) affiché par PutImage (ZPixmap 32 bits, BGRX), événements bruts traduits vers
# __ui_on_* (souris, clavier façon Win32 VK_*, redimensionnement, fermeture WM_DELETE_WINDOW, focus, état EWMH).
#
# État [c + 104] : [0] fd [8] sortie (raw) [16] longueur [24] capacité [32] entrée (raw) [40] longueur
# [48] capacité [56] numéro de séquence [64] base des identifiants [72] masque [80] prochain identifiant
# [88] racine [96] visuel [104] profondeur [112] largeur écran [120] hauteur [128] largeur mm [136] longueur
# maximale d'une requête (mots) [144] file d'événements (liste de blocs de 32 octets) [152] keycode min
# [160] keycode max [168] symboles par keycode [176] table des symboles (raw, u32) [184] pixel blanc
# [192] WM_PROTOCOLS [200] WM_DELETE_WINDOW [208] _NET_WM_NAME [216] UTF8_STRING [224] _NET_WM_STATE
# [232] fenêtres X -> id ui (dict) [240] id ui -> fenêtre (dict) [248] police « cursor » [256] curseurs (raw, 11)
# [264] tête de la file d'événements
# Fenêtre : [0] identifiant X [8] GC [16] affichée [24] tampon BGRX (raw) [32] taille du tampon

func __x_s16(v: int) -> int:
    v = v & 65535
    if v >= 32768:
        return v - 65536
    return v

func __x_pad(n: int) -> int:
    return (n + 3) & -4

# ---- sortie : requêtes mises en tampon, envoyées par __x_flush ----

func __x_write_all(fd: int, p: int, n: int) -> bool:
    done := 0
    while done < n:
        k := __syscall(1, fd, p + done, n - done)
        if k == -4:
            continue
        if k <= 0:
            return false
        done += k
    return true

func __x_flush(x: int):
    n := __load64(x + 16)
    if n > 0:
        __x_write_all(__load64(x), __load64(x + 8), n)
        __store64(x + 16, 0)

# Requête de `n` octets (multiple de 4) : adresse de son début, mise à zéro. Le numéro de séquence avance.
func __x_req(x: int, op: int, n: int) -> int:
    if __load64(x + 16) + n > __load64(x + 24):
        __x_flush(x)
        if n > __load64(x + 24):
            __store64(x + 8, __alloc_raw(n + 8))
            __store64(x + 24, n)
    p := __load64(x + 8) + __load64(x + 16)
    __zero(p, n)
    __store8(p, op)
    __store16(p + 2, n >> 2)
    __store64(x + 16, __load64(x + 16) + n)
    __store64(x + 56, __load64(x + 56) + 1)
    return p

func __x_id(x: int) -> int:
    i := __load64(x + 80)
    __store64(x + 80, i + 1)
    return __load64(x + 64) | (i & __load64(x + 72))

# ---- entrée : paquets de 32 octets (événements, erreurs) ou réponses (32 + 4 * longueur) ----

# Lit ce qui est disponible (attend jusqu'à ms millisecondes, -1 : indéfiniment). false si la connexion est perdue.
func __x_read(x: int, ms: int) -> bool:
    fd := __load64(x)
    pf := __alloc_raw(8)
    __store32(pf, fd)
    __store32(pf + 4, 1)
    r := __syscall(7, pf, 1, ms)
    if r <= 0:
        return true
    if __load64(x + 40) + 65536 > __load64(x + 48):
        cap := __load64(x + 48) * 2 + 65536
        nb := __alloc_raw(cap + 8)
        __copy(nb, __load64(x + 32), __load64(x + 40))
        __store64(x + 32, nb)
        __store64(x + 48, cap)
    k := __syscall(0, fd, __load64(x + 32) + __load64(x + 40), 65536)
    if k <= 0:
        return k == -4 or k == -11
    __store64(x + 40, __load64(x + 40) + k)
    return true

# Taille du premier paquet complet du tampon d'entrée, ou 0.
func __x_packet(x: int) -> int:
    n := __load64(x + 40)
    if n < 32:
        return 0
    p := __load64(x + 32)
    sz := 32
    if __load8(p) == 1:
        sz = 32 + 4 * __load32(p + 4)
    if n < sz:
        return 0
    return sz

# Retire le premier paquet (taille sz) : copie renvoyée.
func __x_take(x: int, sz: int) -> int:
    p := __load64(x + 32)
    out := __alloc_raw(sz + 8)
    __copy(out, p, sz)
    rest := __load64(x + 40) - sz
    if rest > 0:
        __copy(p, p + sz, rest)
    __store64(x + 40, rest)
    return out

# Range les événements arrivés ; renvoie la réponse (ou l'erreur) au numéro `seq` si elle est arrivée, sinon 0.
func __x_dispatch(x: int, seq: int) -> int:
    while true:
        sz := __x_packet(x)
        if sz == 0:
            return 0
        pk := __x_take(x, sz)
        t := __load8(pk)
        if t == 0 or t == 1:
            if seq >= 0 and __load16(pk + 2) == (seq & 65535):
                return pk
            continue
        __rt_list_push(__load64(x + 144), pk)
    return 0

# Réponse à la dernière requête envoyée (0 si le serveur a répondu par une erreur ou si la connexion est perdue).
func __x_reply(x: int) -> int:
    seq := __load64(x + 56)
    __x_flush(x)
    while true:
        pk := __x_dispatch(x, seq)
        if pk != 0:
            if __load8(pk) == 0:
                return 0
            return pk
        before := __load64(x + 40)
        if not __x_read(x, 5000):
            return 0
        if __load64(x + 40) == before and __x_packet(x) == 0:
            # rien en 5 s : serveur muet, on abandonne la requête
            return 0
    return 0

# ---- connexion ----

func __x_connect_unix(path: str, abstract: bool) -> int:
    fd := __syscall(41, 1, 1 | 524288, 0)
    if fd < 0:
        return -1
    sa := __alloc_raw(112)
    __zero(sa, 112)
    __store16(sa, 1)
    n := __nat_blen(path)
    off := 2
    if abstract:
        off = 3
    __copy(sa + off, __nat_bp(path), n)
    r := __syscall(42, fd, sa, off + n)
    if r < 0:
        __syscall(3, fd)
        return -1
    return fd

func __x_connect_tcp(host: str, port: int) -> int:
    ip := 0
    if __nat_blen(host) == 0 or __rt_str_eq(host, "localhost"):
        ip = 16777343                      # 127.0.0.1 (ordre réseau)
    else:
        p := __nat_bp(host)
        n := __nat_blen(host)
        part := 0
        k := 0
        sh := 0
        i := 0
        while i <= n:
            ch := 46
            if i < n:
                ch = __load8(p + i)
            if ch == 46:
                ip = ip | ((part & 255) << sh)
                sh += 8
                part = 0
                k += 1
            elif ch >= 48 and ch <= 57:
                part = part * 10 + ch - 48
            else:
                return -1
            i += 1
        if k != 4:
            return -1
    fd := __syscall(41, 2, 1 | 524288, 0)
    if fd < 0:
        return -1
    sa := __alloc_raw(16)
    __zero(sa, 16)
    __store16(sa, 2)
    __store8(sa + 2, (port >> 8) & 255)
    __store8(sa + 3, port & 255)
    __store32(sa + 4, ip)
    if __syscall(42, fd, sa, 16) < 0:
        __syscall(3, fd)
        return -1
    return fd

func __x_be16(p: int) -> int:
    return (__load8(p) << 8) | __load8(p + 1)

# Cookie MIT-MAGIC-COOKIE-1 du fichier Xauthority pour l'affichage `num` : chaîne (vide si absent).
func __x_cookie(num: str) -> str:
    path := __nat_env_get("XAUTHORITY", "")
    if __nat_blen(path) == 0:
        home := __nat_env_get("HOME", "")
        if __nat_blen(home) == 0:
            return ""
        path = home + "/.Xauthority"
    fd := __syscall(2, __nat_c(path), 0)
    if fd < 0:
        return ""
    data := __nat_read_fd(fd, 1048576)
    __syscall(3, fd)
    p := __nat_bp(data)
    n := __nat_blen(data)
    i := 0
    fallback := ""
    while i + 2 <= n:
        fam := __x_be16(p + i)
        i += 2
        fl := __rt_list_new(0)
        k := 0
        ok := true
        while k < 4:
            if i + 2 > n:
                ok = false
                break
            ln := __x_be16(p + i)
            i += 2
            if i + ln > n:
                ok = false
                break
            __rt_list_push(fl, __str_addr(__nat_make(p + i, ln)))
            i += ln
            k += 1
        if not ok:
            break
        anum := __as_str(__rt_vec_at(fl, 1))
        name := __as_str(__rt_vec_at(fl, 2))
        if not __rt_str_eq(name, "MIT-MAGIC-COOKIE-1"):
            continue
        if __rt_str_eq(anum, num) or __nat_blen(anum) == 0:
            if fam == 256 or fam == 65535 or fam == 0:
                return __as_str(__rt_vec_at(fl, 3))
            if __nat_blen(fallback) == 0:
                fallback = __as_str(__rt_vec_at(fl, 3))
    return fallback

# Ouvre l'affichage DISPLAY : état (adresse) ou 0, message d'erreur dans err (chaîne rangée en [0]).
func __x_open(err: int) -> int:
    disp := __nat_env_get("DISPLAY", "")
    if __nat_blen(disp) == 0:
        __ui_sets(err, 0, "variable DISPLAY absente (aucun serveur X11 / XWayland détecté)")
        return 0
    p := __nat_bp(disp)
    n := __nat_blen(disp)
    colon := -1
    i := n - 1
    while i >= 0:
        if __load8(p + i) == 58:
            colon = i
            break
        i -= 1
    bad := "impossible d'ouvrir l'affichage X11 '" + disp + "'"
    if colon < 0:
        __ui_sets(err, 0, bad)
        return 0
    host := __nat_sub(disp, 0, colon)
    j := colon + 1
    num := 0
    st := j
    while j < n and __load8(p + j) >= 48 and __load8(p + j) <= 57:
        num = num * 10 + __load8(p + j) - 48
        j += 1
    if j == st:
        __ui_sets(err, 0, bad)
        return 0
    nums := __nat_sub(disp, st, j - st)
    fd := -1
    if __nat_blen(host) == 0 or __rt_str_eq(host, "unix"):
        sock := "/tmp/.X11-unix/X" + nums
        fd = __x_connect_unix(sock, false)
        if fd < 0:
            fd = __x_connect_unix(sock, true)
        if fd < 0 and __nat_blen(host) == 0:
            fd = __x_connect_tcp("", 6000 + num)
    else:
        fd = __x_connect_tcp(host, 6000 + num)
    if fd < 0:
        __ui_sets(err, 0, bad)
        return 0
    cookie := __x_cookie(nums)
    an := "MIT-MAGIC-COOKIE-1"
    if __nat_blen(cookie) == 0:
        an = ""
    nl := __nat_blen(an)
    dl := __nat_blen(cookie)
    sz := 12 + __x_pad(nl) + __x_pad(dl)
    q := __alloc_raw(sz + 8)
    __zero(q, sz)
    __store8(q, 108)                       # 'l' : petit-boutiste
    __store16(q + 2, 11)
    __store16(q + 6, nl)
    __store16(q + 8, dl)
    __copy(q + 12, __nat_bp(an), nl)
    __copy(q + 12 + __x_pad(nl), __nat_bp(cookie), dl)
    __x_write_all(fd, q, sz)
    hd := __alloc_raw(16)
    if not __x_read_exact(fd, hd, 8):
        __syscall(3, fd)
        __ui_sets(err, 0, bad)
        return 0
    more := 4 * __load16(hd + 6)
    s := __alloc_raw(8 + more + 8)
    __copy(s, hd, 8)
    if not __x_read_exact(fd, s + 8, more):
        __syscall(3, fd)
        __ui_sets(err, 0, bad)
        return 0
    if __load8(s) != 1:
        rl := __load8(s + 1)
        why := ""
        if rl > 0 and 8 + rl <= 8 + more:
            why = " : " + __nat_make(s + 8, rl)
        __syscall(3, fd)
        __ui_sets(err, 0, bad + why)
        return 0
    x := __alloc(288)
    __store64(x, fd)
    __store64(x + 8, __alloc_raw(262152))
    __store64(x + 24, 262144)
    __store64(x + 32, __alloc_raw(131080))
    __store64(x + 48, 131072)
    __store64(x + 64, __load32(s + 12))
    __store64(x + 72, __load32(s + 16))
    __store64(x + 80, 1)
    vlen := __load16(s + 24)
    __store64(x + 136, __load16(s + 26))
    nscreens := __load8(s + 28)
    nformats := __load8(s + 29)
    __store64(x + 152, __load8(s + 34))
    __store64(x + 160, __load8(s + 35))
    o := 40 + __x_pad(vlen)
    bpp := 0
    k := 0
    # formats : profondeur, bits par pixel
    while k < nformats:
        if __load8(s + o + 8 * k) == 24 and bpp == 0:
            bpp = __load8(s + o + 8 * k + 1)
        k += 1
    o += 8 * nformats
    if nscreens < 1:
        __syscall(3, fd)
        __ui_sets(err, 0, bad)
        return 0
    scr := s + o
    __store64(x + 88, __load32(scr))
    __store64(x + 184, __load32(scr + 8))
    __store64(x + 112, __load16(scr + 20))
    __store64(x + 120, __load16(scr + 22))
    __store64(x + 128, __load16(scr + 24))
    __store64(x + 96, __load32(scr + 32))
    depth := __load8(scr + 38)
    __store64(x + 104, depth)
    # classe et masques du visuel racine
    nd := __load8(scr + 39)
    dp := scr + 40
    cls := 0
    red := 0
    k = 0
    while k < nd:
        dd := __load8(dp)
        nv := __load16(dp + 2)
        vp := dp + 8
        m := 0
        while m < nv:
            if __load32(vp + 24 * m) == __load64(x + 96) and dd == depth:
                cls = __load8(vp + 24 * m + 4)
                red = __load32(vp + 24 * m + 8)
            m += 1
        dp = dp + 8 + 24 * nv
        k += 1
    if depth < 24 or cls != 4 or red != 16711680 or (bpp != 32 and bpp != 0):
        __syscall(3, fd)
        __ui_sets(err, 0, "visuel X11 non supporté (TrueColor 24/32 bits requis)")
        return 0
    __store64(x + 144, __rt_list_new(0))
    __store64(x + 232, __rt_dict_new(8))
    __store64(x + 240, __rt_dict_new(8))
    cur := __alloc_raw(96)
    __zero(cur, 96)
    __store64(x + 256, cur)
    __store64(x + 192, __x_atom(x, "WM_PROTOCOLS", false))
    __store64(x + 200, __x_atom(x, "WM_DELETE_WINDOW", false))
    __store64(x + 208, __x_atom(x, "_NET_WM_NAME", false))
    __store64(x + 216, __x_atom(x, "UTF8_STRING", false))
    __store64(x + 224, __x_atom(x, "_NET_WM_STATE", false))
    __x_load_keymap(x)
    return x

func __x_read_exact(fd: int, p: int, n: int) -> bool:
    got := 0
    while got < n:
        k := __syscall(0, fd, p + got, n - got)
        if k == -4:
            continue
        if k <= 0:
            return false
        got += k
    return true

# ---- requêtes ----

func __x_atom(x: int, name: str, onlyIfExists: bool) -> int:
    n := __nat_blen(name)
    p := __x_req(x, 16, 8 + __x_pad(n))
    if onlyIfExists:
        __store8(p + 1, 1)
    __store16(p + 4, n)
    __copy(p + 8, __nat_bp(name), n)
    r := __x_reply(x)
    if r == 0:
        return 0
    return __load32(r + 8)

func __x_change_prop(x: int, win: int, prop: int, typ: int, fmt: int, data: int, count: int, mode: int):
    nbytes := count * (fmt >> 3)
    p := __x_req(x, 18, 24 + __x_pad(nbytes))
    __store8(p + 1, mode)
    __store32(p + 4, win)
    __store32(p + 8, prop)
    __store32(p + 12, typ)
    __store8(p + 16, fmt)
    __store32(p + 20, count)
    if nbytes > 0:
        __copy(p + 24, data, nbytes)

func __x_change_str(x: int, win: int, prop: int, typ: int, s: str):
    __x_change_prop(x, win, prop, typ, 8, __nat_bp(s), __nat_blen(s), 0)

# Propriété (réponse brute : format [1], type [8], nombre d'éléments [16], données [32]) ou 0.
func __x_get_prop(x: int, win: int, prop: int, typ: int, n: int) -> int:
    p := __x_req(x, 20, 24)
    __store32(p + 4, win)
    __store32(p + 8, prop)
    __store32(p + 12, typ)
    __store32(p + 16, 0)
    __store32(p + 20, n)
    r := __x_reply(x)
    if r == 0 or __load32(r + 8) == 0:
        return 0
    return r

func __x_map(x: int, win: int, on: bool):
    op := 10
    if on:
        op = 8
    p := __x_req(x, op, 8)
    __store32(p + 4, win)

# Valeurs dans l'ordre des bits du masque : x 1, y 2, largeur 4, hauteur 8, empilement 64 (Above = 0).
func __x_configure(x: int, win: int, mask: int, a: int, b: int):
    n := 0
    m := mask
    while m != 0:
        n += m & 1
        m = m >> 1
    p := __x_req(x, 12, 12 + 4 * n)
    __store32(p + 4, win)
    __store16(p + 8, mask)
    if n >= 1 and mask != 64:
        __store32(p + 12, a & 4294967295)
    if n >= 2:
        __store32(p + 16, b & 4294967295)

# Événement client (format 32) envoyé à la racine pour le gestionnaire de fenêtres.
func __x_client_msg(x: int, win: int, typ: int, d0: int, d1: int, d2: int, d3: int):
    p := __x_req(x, 25, 44)
    __store32(p + 4, __load64(x + 88))
    __store32(p + 8, 1572864)              # SubstructureRedirect | SubstructureNotify
    e := p + 12
    __store8(e, 33)
    __store8(e + 1, 32)
    __store32(e + 4, win)
    __store32(e + 8, typ)
    __store32(e + 12, d0 & 4294967295)
    __store32(e + 16, d1 & 4294967295)
    __store32(e + 20, d2 & 4294967295)
    __store32(e + 24, d3 & 4294967295)

func __x_translate(x: int, win: int, out: int) -> bool:
    p := __x_req(x, 40, 16)
    __store32(p + 4, win)
    __store32(p + 8, __load64(x + 88))
    r := __x_reply(x)
    if r == 0:
        return false
    __store64(out, __x_s16(__load16(r + 12)))
    __store64(out + 8, __x_s16(__load16(r + 14)))
    return true

func __x_load_keymap(x: int):
    mn := __load64(x + 152)
    mx := __load64(x + 160)
    p := __x_req(x, 101, 8)
    __store8(p + 4, mn)
    __store8(p + 5, mx - mn + 1)
    r := __x_reply(x)
    if r == 0:
        return
    __store64(x + 168, __load8(r + 1))
    __store64(x + 280, r)
    __store64(x + 176, r + 32)

# ---- fenêtres ----

func __x_win(x: int, id: int) -> int:
    return __ui_get(__load64(x + 240), id)

func __x_size_hints(x: int, xw: int, resizable: bool, w: int, h: int, minW: int, minH: int, maxW: int, maxH: int, initial: bool):
    sh := __alloc_raw(80)
    __zero(sh, 72)
    flags := 0
    if initial:
        flags = 12                          # PPosition | PSize
        __store32(sh + 12, w)
        __store32(sh + 16, h)
    if not resizable:
        flags = flags | 48                  # PMinSize | PMaxSize
        __store32(sh + 20, w)
        __store32(sh + 24, h)
        __store32(sh + 28, w)
        __store32(sh + 32, h)
    else:
        if minW > 0 or minH > 0:
            flags = flags | 16
            __store32(sh + 20, minW)
            __store32(sh + 24, minH)
        if maxW > 0 or maxH > 0:
            flags = flags | 32
            mw := maxW
            if mw <= 0:
                mw = 32767
            mh := maxH
            if mh <= 0:
                mh = 32767
            __store32(sh + 28, mw)
            __store32(sh + 32, mh)
    __store32(sh, flags)
    __x_change_prop(x, xw, 40, 41, 32, sh, 18, 0)   # WM_NORMAL_HINTS, WM_SIZE_HINTS

func __x_set_title(x: int, xw: int, title: str):
    __x_change_str(x, xw, 39, 31, title)            # WM_NAME, STRING
    __x_change_str(x, xw, __load64(x + 208), __load64(x + 216), title)

func __x_create(x: int, id: int, title: str, w: int, h: int, resizable: bool):
    xw := __x_id(x)
    p := __x_req(x, 1, 40)
    __store8(p + 1, __load64(x + 104))
    __store32(p + 4, xw)
    __store32(p + 8, __load64(x + 88))
    __store16(p + 16, w)
    __store16(p + 18, h)
    __store16(p + 22, 1)                   # InputOutput
    __store32(p + 24, __load64(x + 96))
    __store32(p + 28, 2050)                # CWBackPixel | CWEventMask
    __store32(p + 32, __load64(x + 184))
    __store32(p + 36, 6455407)             # Exposure KeyPress/Release ButtonPress/Release PointerMotion
                                           # StructureNotify FocusChange LeaveWindow PropertyChange
    a := __alloc_raw(8)
    __store32(a, __load64(x + 200))
    __x_change_prop(x, xw, __load64(x + 192), 4, 32, a, 1, 0)
    __x_set_title(x, xw, title)
    __x_size_hints(x, xw, resizable, w, h, 0, 0, 0, 0, true)
    cls := __alloc_raw(16)
    __copy(cls, __nat_bp("alex"), 4)
    __store8(cls + 4, 0)
    __copy(cls + 5, __nat_bp("Alex"), 4)
    __store8(cls + 9, 0)
    __x_change_prop(x, xw, 67, 31, 8, cls, 10, 0)   # WM_CLASS
    gc := __x_id(x)
    q := __x_req(x, 55, 16)
    __store32(q + 4, gc)
    __store32(q + 8, xw)
    o := __alloc(48)
    __store64(o, xw)
    __store64(o + 8, gc)
    __rt_dict_set(__load64(x + 232), xw, id, 0)
    __rt_dict_set(__load64(x + 240), id, o, 0)
    __x_flush(x)

func __x_destroy(x: int, id: int):
    o := __x_win(x, id)
    if o == 0:
        return
    p := __x_req(x, 60, 8)                 # FreeGC
    __store32(p + 4, __load64(o + 8))
    q := __x_req(x, 4, 8)
    __store32(q + 4, __load64(o))
    __rt_dict_remove(__load64(x + 232), __load64(o), 0)
    __rt_dict_remove(__load64(x + 240), id, 0)
    __x_flush(x)

func __x_show(x: int, id: int, on: bool):
    o := __x_win(x, id)
    if o == 0:
        return
    if on:
        __x_configure(x, __load64(o), 64, 0, 0)    # au premier plan (XMapRaised)
    __x_map(x, __load64(o), on)
    v := 0
    if on:
        v = 1
    __store64(o + 16, v)
    __x_flush(x)

func __x_title(x: int, id: int, title: str):
    o := __x_win(x, id)
    if o != 0:
        __x_set_title(x, __load64(o), title)
        __x_flush(x)

func __x_resize(x: int, id: int, w: int, h: int):
    o := __x_win(x, id)
    if o != 0:
        __x_configure(x, __load64(o), 12, w, h)
        __x_flush(x)

func __x_move(x: int, id: int, px: int, py: int):
    o := __x_win(x, id)
    if o != 0:
        __x_configure(x, __load64(o), 3, px, py)
        __x_flush(x)

# Formes de la police « cursor » (X11/cursorfont.h), dans l'ordre des noms de curseurs de ui.
func __x_cursor_shape(name: str) -> int:
    if __rt_str_eq(name, "text"):
        return 152
    if __rt_str_eq(name, "pointer"):
        return 60
    if __rt_str_eq(name, "grab"):
        return 58
    if __rt_str_eq(name, "grabbing") or __rt_str_eq(name, "move"):
        return 52
    if __rt_str_eq(name, "resize_h"):
        return 108
    if __rt_str_eq(name, "resize_v"):
        return 116
    if __rt_str_eq(name, "wait"):
        return 150
    if __rt_str_eq(name, "not_allowed"):
        return 0
    if __rt_str_eq(name, "crosshair"):
        return 34
    return 68

func __x_cursor(x: int, id: int, name: str):
    o := __x_win(x, id)
    if o == 0:
        return
    shape := __x_cursor_shape(name)
    slot := __load64(x + 256) + 8 * ((shape >> 2) % 11)
    if __load64(x + 248) == 0:
        f := __x_id(x)
        p := __x_req(x, 45, 20)            # OpenFont
        __store32(p + 4, f)
        __store16(p + 8, 6)
        __copy(p + 12, __nat_bp("cursor"), 6)
        __store64(x + 248, f)
    cur := 0
    if __load64(slot) != 0 and (__load64(slot) >> 32) == shape + 1:
        cur = __load64(slot) & 4294967295
    else:
        cur = __x_id(x)
        q := __x_req(x, 94, 32)            # CreateGlyphCursor
        __store32(q + 4, cur)
        __store32(q + 8, __load64(x + 248))
        __store32(q + 12, __load64(x + 248))
        __store16(q + 16, shape)
        __store16(q + 18, shape + 1)
        __store16(q + 26, 65535)
        __store16(q + 28, 65535)
        __store16(q + 30, 65535)
        __store64(slot, ((shape + 1) << 32) | cur)
    r := __x_req(x, 2, 16)                 # ChangeWindowAttributes (CWCursor)
    __store32(r + 4, __load64(o))
    __store32(r + 8, 16384)
    __store32(r + 12, cur)
    __x_flush(x)

# Affiche la surface (RGBA, composée sur du blanc si translucide) dans la fenêtre.
func __x_present(x: int, id: int, f: int):
    o := __x_win(x, id)
    if o == 0:
        return
    w := __us_w(f)
    h := __us_h(f)
    n := w * h
    if __load64(o + 32) < n * 4:
        __store64(o + 24, __alloc_raw(n * 4 + 8))
        __store64(o + 32, n * 4)
    d := __load64(o + 24)
    s := __us_px(f)
    i := 0
    while i < n:
        px := __load32(s)
        a := px >> 24
        r := px & 255
        g := (px >> 8) & 255
        b := (px >> 16) & 255
        if a != 255:
            ia := 255 - a
            r = (r * a + 255 * ia) // 255
            g = (g * a + 255 * ia) // 255
            b = (b * a + 255 * ia) // 255
        __store32(d, b | (g << 8) | (r << 16))
        s += 4
        d += 4
        i += 1
    # découpage en bandes : une requête ne dépasse pas la longueur maximale annoncée par le serveur
    maxb := 4 * __load64(x + 136) - 32
    rows := maxb // (4 * w)
    if rows < 1:
        rows = 1
    y := 0
    while y < h:
        k := rows
        if y + k > h:
            k = h - y
        nb := 4 * w * k
        p := __x_req(x, 72, 24 + nb)
        __store8(p + 1, 2)                 # ZPixmap
        __store32(p + 4, __load64(o))
        __store32(p + 8, __load64(o + 8))
        __store16(p + 12, w)
        __store16(p + 14, k)
        __store16(p + 18, y)
        __store8(p + 21, __load64(x + 104))
        __copy(p + 24, __load64(o + 24) + 4 * w * y, nb)
        y += k
    __x_flush(x)

# ---- gestion des fenêtres (EWMH) ----

func __x_has_wm(x: int) -> bool:
    a := __x_atom(x, "_NET_SUPPORTING_WM_CHECK", true)
    if a == 0:
        return false
    r := __x_get_prop(x, __load64(x + 88), a, 33, 1)
    return r != 0 and __load32(r + 16) == 1

func __x_read_state(x: int, xw: int) -> str:
    st := "normal"
    mh := false
    mv := false
    r := __x_get_prop(x, xw, __load64(x + 224), 4, 32)
    if r != 0:
        fs := __x_atom(x, "_NET_WM_STATE_FULLSCREEN", false)
        hid := __x_atom(x, "_NET_WM_STATE_HIDDEN", false)
        ah := __x_atom(x, "_NET_WM_STATE_MAXIMIZED_HORZ", false)
        av := __x_atom(x, "_NET_WM_STATE_MAXIMIZED_VERT", false)
        n := __load32(r + 16)
        i := 0
        while i < n:
            v := __load32(r + 32 + 4 * i)
            if v == fs:
                st = "fullscreen"
            elif v == hid and __rt_str_eq(st, "normal"):
                st = "minimized"
            elif v == ah:
                mh = true
            elif v == av:
                mv = true
            i += 1
    if __rt_str_eq(st, "normal") and mh and mv:
        st = "maximized"
    return st

func __x_net_state(x: int, xw: int, action: int, a1: str, a2: str):
    b := 0
    if __nat_blen(a2) > 0:
        b = __x_atom(x, a2, false)
    __x_client_msg(x, xw, __load64(x + 224), action, __x_atom(x, a1, false), b, 1)

func __x_position(x: int, id: int, out: int) -> bool:
    o := __x_win(x, id)
    if o == 0:
        return false
    return __x_translate(x, __load64(o), out)

func __x_set_state(x: int, id: int, state: str) -> bool:
    o := __x_win(x, id)
    if o == 0 or not __x_has_wm(x):
        return false
    xw := __load64(o)
    __x_net_state(x, xw, 0, "_NET_WM_STATE_FULLSCREEN", "")
    __x_net_state(x, xw, 0, "_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ")
    if __rt_str_eq(state, "minimized"):
        __x_client_msg(x, xw, __x_atom(x, "WM_CHANGE_STATE", false), 3, 0, 0, 0)   # IconicState
    else:
        __x_configure(x, xw, 64, 0, 0)
        __x_map(x, xw, true)
        if __rt_str_eq(state, "maximized"):
            __x_net_state(x, xw, 1, "_NET_WM_STATE_MAXIMIZED_VERT", "_NET_WM_STATE_MAXIMIZED_HORZ")
        elif __rt_str_eq(state, "fullscreen"):
            __x_net_state(x, xw, 1, "_NET_WM_STATE_FULLSCREEN", "")
    __x_flush(x)
    return true

func __x_hints(x: int, id: int, resizable: bool, decorated: bool, topmost: bool, opacity: float, minW: int, minH: int, maxW: int, maxH: int, cw: int, ch: int):
    o := __x_win(x, id)
    if o == 0:
        return
    xw := __load64(o)
    __x_size_hints(x, xw, resizable, cw, ch, minW, minH, maxW, maxH, false)
    mo := __alloc_raw(24)
    __zero(mo, 20)
    __store32(mo, 2)                       # MWM_HINTS_DECORATIONS
    if decorated:
        __store32(mo + 8, 1)
    mh := __x_atom(x, "_MOTIF_WM_HINTS", false)
    __x_change_prop(x, xw, mh, mh, 32, mo, 5, 0)
    op := __x_atom(x, "_NET_WM_WINDOW_OPACITY", false)
    if opacity >= 1.0:
        p := __x_req(x, 19, 12)            # DeleteProperty
        __store32(p + 4, xw)
        __store32(p + 8, op)
    else:
        v := __alloc_raw(8)
        __store32(v, __f2i(opacity * 4294967295.0) & 4294967295)
        __x_change_prop(x, xw, op, 6, 32, v, 1, 0)   # CARDINAL
    above := __x_atom(x, "_NET_WM_STATE_ABOVE", false)
    if __load64(o + 16) != 0 and __x_has_wm(x):
        t := 0
        if topmost:
            t = 1
        __x_client_msg(x, xw, __load64(x + 224), t, above, 0, 1)
    elif topmost:
        v := __alloc_raw(8)
        __store32(v, above)
        __x_change_prop(x, xw, __load64(x + 224), 4, 32, v, 1, 2)
    __x_flush(x)

func __x_focus(x: int, id: int):
    o := __x_win(x, id)
    if o == 0:
        return
    xw := __load64(o)
    __x_configure(x, xw, 64, 0, 0)
    if __x_has_wm(x):
        __x_client_msg(x, xw, __x_atom(x, "_NET_ACTIVE_WINDOW", false), 1, 0, 0, 0)
    else:
        p := __x_req(x, 42, 12)
        __store8(p + 1, 2)                 # RevertToParent
        __store32(p + 4, xw)
    __x_flush(x)

# Écran : [0] largeur [8] hauteur [16] largeur utile [24] hauteur utile.
func __x_screen(x: int, out: int):
    __store64(out, __load64(x + 112))
    __store64(out + 8, __load64(x + 120))
    __store64(out + 16, __load64(x + 112))
    __store64(out + 24, __load64(x + 120))
    wa := __x_atom(x, "_NET_WORKAREA", true)
    if wa != 0:
        r := __x_get_prop(x, __load64(x + 88), wa, 6, 4)
        if r != 0 and __load32(r + 8) == 6 and __load8(r + 1) == 32 and __load32(r + 16) >= 4:
            __store64(out + 16, __load32(r + 40))
            __store64(out + 24, __load32(r + 44))

func __x_dpi(x: int) -> int:
    r := __x_get_prop(x, __load64(x + 88), 23, 31, 65536)   # RESOURCE_MANAGER, STRING
    if r != 0:
        s := __nat_make(r + 32, __load32(r + 16))
        k := __dyn_find_bytes(s, "Xft.dpi:", 0)
        if k >= 0:
            p := __nat_bp(s) + k + 8
            e := __nat_bp(s) + __nat_blen(s)
            while p < e and (__load8(p) == 32 or __load8(p) == 9):
                p += 1
            v := 0
            while p < e and __load8(p) >= 48 and __load8(p) <= 57:
                v = v * 10 + __load8(p) - 48
                p += 1
            frac := 0
            if p < e and __load8(p) == 46 and p + 1 < e and __load8(p + 1) >= 53 and __load8(p + 1) <= 57:
                frac = 1
            v = v + frac
            if v >= 48 and v <= 960:
                return v
    mm := __load64(x + 128)
    if mm > 0:
        v := (__load64(x + 112) * 254 + mm * 5) // (mm * 10)
        if v >= 48 and v <= 960:
            return v
    return 96

# ---- événements ----

func __x_mods(st: int) -> int:
    m := 0
    if (st & 8) != 0:
        m = m | 1
    if (st & 4) != 0:
        m = m | 2
    if (st & 1) != 0:
        m = m | 4
    if (st & 64) != 0:
        m = m | 8
    return m

func __x_sym(x: int, kc: int, col: int) -> int:
    per := __load64(x + 168)
    if per == 0 or kc < __load64(x + 152) or kc > __load64(x + 160) or col >= per:
        return 0
    return __load32(__load64(x + 176) + 4 * ((kc - __load64(x + 152)) * per + col))

func __x_is_keypad(ks: int) -> bool:
    return (ks >= 65408 and ks <= 65469) or (ks >= 285212672 and ks <= 285278207)

func __x_lower(ks: int) -> int:
    if (ks >= 65 and ks <= 90) or (ks >= 192 and ks <= 222 and ks != 215):
        return ks + 32
    return ks

func __x_upper(ks: int) -> int:
    if (ks >= 97 and ks <= 122) or (ks >= 224 and ks <= 254 and ks != 247):
        return ks - 32
    return ks

# Symbole selon l'état (règles de Xlib, groupe 1 : Maj, Verr. Maj, Verr. Num).
func __x_lookup(x: int, kc: int, st: int) -> int:
    s0 := __x_sym(x, kc, 0)
    s1 := __x_sym(x, kc, 1)
    if s1 == 0:
        s1 = __x_upper(s0)
        s0 = __x_lower(s0)
    shift := (st & 1) != 0
    lock := (st & 2) != 0
    if (st & 16) != 0 and __x_is_keypad(s1):
        if shift:
            return s0
        return s1
    if shift:
        if lock:
            return __x_upper(s1)
        return s1
    if lock:
        return __x_upper(s0)
    return s0

func __x_vk(ks: int) -> int:
    if ks >= 97 and ks <= 122:
        return ks - 32
    if (ks >= 65 and ks <= 90) or (ks >= 48 and ks <= 57):
        return ks
    if ks >= 65470 and ks <= 65481:
        return 112 + ks - 65470
    if ks >= 65456 and ks <= 65465:
        return 96 + ks - 65456
    if ks == 65288:
        return 8
    if ks == 65289 or ks == 65056:
        return 9
    if ks == 65293 or ks == 65421:
        return 13
    if ks == 65307:
        return 27
    if ks == 32:
        return 32
    if ks >= 65365 and ks <= 65367:
        return 33 + ks - 65365            # Prior, Next, End
    if ks == 65360:
        return 36
    if ks >= 65361 and ks <= 65364:
        return 37 + ks - 65361            # Left, Up, Right, Down
    if ks == 65379:
        return 45
    if ks == 65535:
        return 46
    if ks == 59:
        return 186
    if ks == 61:
        return 187
    if ks == 44:
        return 188
    if ks == 45:
        return 189
    if ks == 46:
        return 190
    if ks == 47:
        return 191
    if ks == 96:
        return 192
    if ks == 91:
        return 219
    if ks == 92:
        return 220
    if ks == 93:
        return 221
    if ks == 39:
        return 222
    return 0

# Texte produit par la touche (XLookupString) : vide pour les touches de contrôle.
func __x_text(ks: int, st: int) -> str:
    c := -1
    if (ks >= 32 and ks <= 126) or (ks >= 160 and ks <= 255):
        c = ks
    elif ks >= 16777216 and ks <= 17891327:
        c = ks - 16777216
    elif ks >= 65408 and ks <= 65469:
        c = ks & 127
    elif ks == 8364:
        c = 8364
    if c < 0:
        return ""
    if (st & 4) != 0 and c < 128:
        if (c >= 64 and c < 127) or c == 32:
            c = c & 31
        elif c == 50:
            c = 0
        elif c >= 51 and c <= 55:
            c = c - 24
        elif c == 56:
            c = 127
        elif c == 47:
            c = 31
    if c < 32 or c == 127:
        return ""
    sb := __rt_sb_new()
    __nat_sb_cp(sb, c)
    return __rt_sb_str(sb)

func __x_find(x: int, xw: int) -> int:
    d := __load64(x + 232)
    e := __rt_dict_index(d, xw, 0)
    if e < 0:
        return 0
    return __load64(__load64(d + 32) + 8 * e)

func __x_handle(c: int, x: int, ev: int):
    t := __load8(ev) & 127
    if t == 12:                            # Expose
        id := __x_find(x, __load32(ev + 4))
        if id != 0 and __load16(ev + 16) == 0:
            w := __ui_find_win(c, id)
            if w != 0:
                __store64(w + 64, 1)
    elif t == 22:                          # ConfigureNotify
        id := __x_find(x, __load32(ev + 8))
        if id != 0:
            __ui_on_resize(c, id, __load16(ev + 20), __load16(ev + 22))
            pos := __alloc_raw(16)
            __store64(pos, __x_s16(__load16(ev + 16)))
            __store64(pos + 8, __x_s16(__load16(ev + 18)))
            if (__load8(ev) & 128) == 0:
                __x_translate(x, __load32(ev + 8), pos)
            __ui_on_move(c, id, __load64(pos), __load64(pos + 8))
    elif t == 9 or t == 10:                # FocusIn / FocusOut
        detail := __load8(ev + 1)
        mode := __load8(ev + 8)
        if detail != 5 and mode != 1 and mode != 2:
            id := __x_find(x, __load32(ev + 4))
            if id != 0:
                __ui_on_focus(c, id, t == 9)
    elif t == 28:                          # PropertyNotify
        if __load32(ev + 8) == __load64(x + 224):
            id := __x_find(x, __load32(ev + 4))
            if id != 0:
                __ui_on_state(c, id, __x_read_state(x, __load32(ev + 4)))
    elif t == 3:                           # KeyRelease
        id := __x_find(x, __load32(ev + 12))
        if id == 0:
            return
        # répétition automatique : Release puis Press au même instant, ce Release est ignoré
        __x_read(x, 0)
        __x_dispatch(x, -1)
        q := __load64(x + 144)
        h := __load64(x + 264)
        if __load64(q) > h:
            nx := __rt_vec_at(q, h)
            if (__load8(nx) & 127) == 2 and __load32(nx + 4) == __load32(ev + 4) and __load8(nx + 1) == __load8(ev + 1):
                return
        __ui_on_key_up(c, id, __x_vk(__x_sym(x, __load8(ev + 1), 0)), __x_mods(__load16(ev + 28)))
    elif t == 33:                          # ClientMessage
        if __load32(ev + 8) == __load64(x + 192) and __load32(ev + 12) == __load64(x + 200):
            id := __x_find(x, __load32(ev + 4))
            if id != 0:
                __x_close_request(c, x, id)
    elif t == 6:                           # MotionNotify
        id := __x_find(x, __load32(ev + 12))
        if id != 0:
            __ui_on_mouse(c, id, 0, __x_s16(__load16(ev + 24)), __x_s16(__load16(ev + 26)), 0, __x_mods(__load16(ev + 28)))
    elif t == 8:                           # LeaveNotify
        if __load8(ev + 30) == 0:
            id := __x_find(x, __load32(ev + 12))
            if id != 0:
                __ui_on_mouse(c, id, 5, __x_s16(__load16(ev + 24)), __x_s16(__load16(ev + 26)), 0, __x_mods(__load16(ev + 28)))
    elif t == 4 or t == 5:                 # ButtonPress / ButtonRelease
        id := __x_find(x, __load32(ev + 12))
        if id == 0:
            return
        b := __load8(ev + 1)
        mods := __x_mods(__load16(ev + 28))
        ex := __x_s16(__load16(ev + 24))
        ey := __x_s16(__load16(ev + 26))
        if b >= 4 and b <= 7:
            if t == 4:
                if b <= 5:
                    d := -1
                    if b == 4:
                        d = 1
                    __ui_on_mouse(c, id, 3, ex, ey, d, mods)
                else:
                    d := -1
                    if b == 7:
                        d = 1
                    __ui_on_mouse(c, id, 4, ex, ey, d, mods)
        else:
            ours := 0
            if b == 1:
                ours = 1
            elif b == 3:
                ours = 2
            elif b == 2:
                ours = 3
            if ours != 0:
                ty := 2
                if t == 4:
                    ty = 1
                __ui_on_mouse(c, id, ty, ex, ey, ours, mods)
    elif t == 2:                           # KeyPress
        id := __x_find(x, __load32(ev + 12))
        if id == 0:
            return
        kc := __load8(ev + 1)
        st := __load16(ev + 28)
        ks := __x_lookup(x, kc, st)
        __ui_on_key(c, id, __x_vk(__x_sym(x, kc, 0)), __x_mods(st), __x_text(ks, st))
    elif t == 34:                          # MappingNotify
        __x_load_keymap(x)

func __x_close_request(c: int, x: int, id: int):
    w := __ui_find_win(c, id)
    if w == 0 or __load64(w + 48) == 0:
        return
    __ui_on_close_request(c, id)
    if __load64(w + 48) == 0:
        __x_destroy(x, id)

func __x_pending(x: int) -> bool:
    return __load64(__load64(x + 144)) > __load64(x + 264) or __x_packet(x) != 0

func __x_pop(c: int, x: int) -> bool:
    __x_dispatch(x, -1)
    q := __load64(x + 144)
    h := __load64(x + 264)
    if __load64(q) <= h:
        return false
    ev := __rt_vec_at(q, h)
    h += 1
    if h == __load64(q):
        __store64(q, 0)
        h = 0
    __store64(x + 264, h)
    __x_handle(c, x, ev)
    return true

# Traite les événements en attente (block : attend au moins un événement).
func __x_pump(c: int, x: int, block: bool):
    __x_flush(x)
    if block and not __x_pending(x):
        while not __x_pending(x):
            if not __x_read(x, -1):
                return
            __x_dispatch(x, -1)
    __x_read(x, 0)
    while __x_pop(c, x):
        __x_read(x, 0)

func __x_wait(x: int, ms: int):
    if __x_pending(x):
        return
    __x_flush(x)
    __x_read(x, ms)
