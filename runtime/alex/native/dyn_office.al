

# ---- arguments / valeurs ----

func __of_arity(fn: str, n: int, lo: int, hi: int):
    if n < lo or n > hi:
        want := __int_to_str(lo)
        if lo != hi:
            want = want + " à " + __int_to_str(hi)
        __dyn_err("ArgumentError", "'" + fn + "' attend " + want + " argument(s), obtenu " + __int_to_str(n))

func __of_tfail(m: str):
    __dyn_err("TypeError", m)

func __of_vfail(m: str):
    __dyn_err("ValueError", m)

func __of_is_seq(v: int) -> bool:
    return __dyn_is(v, 7) or __dyn_is(v, 8)

func __of_seq_len(v: int) -> int:
    if __dyn_is(v, 7):
        return __dyn_list_len(v)
    return __dyn_tuple_len(v)

func __of_seq_at(v: int, i: int) -> int:
    if __dyn_is(v, 7):
        return __dyn_list_at(v, i)
    return __dyn_tuple_at(v, i)

func __of_str(fn: str, v: int, label: str) -> str:
    if not __dyn_is_str(v):
        __of_tfail("'" + fn + "' : " + label + " doit être une str (obtenu '" + __dyn_type_name(v) + "')")
    return __dyn_sv(v)

func __of_int(fn: str, v: int, label: str) -> int:
    if not __dyn_is(v, 1):
        __of_tfail("'" + fn + "' : " + label + " doit être un int (obtenu '" + __dyn_type_name(v) + "')")
    return __load64(v + 8)

# Liste d'octets (list/tuple d'int 0..255 ou de byte) -> tampon (str d'octets).
func __of_bytes(fn: str, v: int, label: str) -> str:
    if not __of_is_seq(v):
        __of_tfail("'" + fn + "' : " + label + " doit être une liste d'octets (obtenu '" + __dyn_type_name(v) + "')")
    m := __of_seq_len(v)
    r := __rt_str_new(m)
    i := 0
    while i < m:
        b := __of_seq_at(v, i)
        x := -1
        if __dyn_is(b, 1):
            x = __load64(b + 8)
            if x < 0 or x > 255:
                x = -1
        elif __dyn_is(b, 5):
            x = __load64(b + 8)
        if x < 0:
            __of_vfail("'" + fn + "' : octet invalide à l'indice " + __int_to_str(i) + " (entier 0..255 attendu)")
        __store8(r + 8 + i, x)
        i += 1
    return __as_str(r)

# Variante des primitives PDF (messages propres).
func __of_pbytes(fn: str, v: int) -> str:
    if not __of_is_seq(v):
        __of_tfail(fn + " : liste d'octets attendue")
    m := __of_seq_len(v)
    r := __rt_str_new(m)
    i := 0
    while i < m:
        b := __of_seq_at(v, i)
        x := -1
        if __dyn_is(b, 1):
            x = __load64(b + 8)
            if x < 0 or x > 255:
                x = -1
        elif __dyn_is(b, 5):
            x = __load64(b + 8)
        if x < 0:
            __of_vfail(fn + " : octet invalide à l'indice " + __int_to_str(i))
        __store8(r + 8 + i, x)
        i += 1
    return __as_str(r)

func __of_pint(fn: str, v: int) -> int:
    if not __dyn_is(v, 1):
        __of_tfail(fn + " : entier attendu")
    return __load64(v + 8)

func __of_blist(p: int, n: int) -> int:
    out := __dyn_list_new(0)
    i := 0
    while i < n:
        __dyn_list_push(out, __dyn_int(__load8(p + i)))
        i += 1
    return out

func __of_sb_list(sb: int) -> int:
    return __of_blist(__load64(sb + 16), __load64(sb))

func __of_ascii(s: str) -> bool:
    p := __nat_bp(s)
    n := __nat_blen(s)
    i := 0
    while i < n:
        if __load8(p + i) >= 128:
            return false
        i += 1
    return true

# Tableau d'entiers 64 bits mis à zéro.
func __of_arr(n: int) -> int:
    return __alloc(8 * n + 8) # mis à zéro ; parcouru par le GC (certains tableaux contiennent des pointeurs)

func __of_get(a: int, i: int) -> int:
    return __load64(a + 8 * i)

func __of_set(a: int, i: int, v: int):
    __store64(a + 8 * i, v)

func __of_table(s: str) -> int:
    parts := __nat_split_bytes(s, 44)
    a := __of_arr(__load64(parts))
    i := 0
    while i < __load64(parts):
        __of_set(a, i, __rt_str_to_int(__as_str(__rt_vec_at(parts, i))))
        i += 1
    return a

func __of_tabs() -> int:
    ds := __dyn_ds()
    t := __load64(ds + 288)
    if t != 0:
        return t
    t = __alloc(64)
    __store64(t, __of_table("3,4,5,6,7,8,9,10,11,13,15,17,19,23,27,31,35,43,51,59,67,83,99,115,131,163,195,227,258"))
    __store64(t + 8, __of_table("0,0,0,0,0,0,0,0,1,1,1,1,2,2,2,2,3,3,3,3,4,4,4,4,5,5,5,5,0"))
    __store64(t + 16, __of_table("1,2,3,4,5,7,9,13,17,25,33,49,65,97,129,193,257,385,513,769,1025,1537,2049,3073,4097,6145,8193,12289,16385,24577"))
    __store64(t + 24, __of_table("0,0,0,0,1,1,2,2,3,3,4,4,5,5,6,6,7,7,8,8,9,9,10,10,11,11,12,12,13,13"))
    __store64(t + 32, __of_table("16,17,18,0,8,7,9,6,10,5,11,4,12,3,13,2,14,1,15"))
    crc := __of_arr(256)
    i := 0
    while i < 256:
        c := i
        k := 0
        while k < 8:
            if (c & 1) != 0:
                c = 3988292384 ^ (c >> 1)
            else:
                c = c >> 1
            k += 1
        __of_set(crc, i, c)
        i += 1
    __store64(t + 40, crc)
    __store64(ds + 288, t)
    return t

func __of_len_base(i: int) -> int:
    return __of_get(__load64(__of_tabs()), i)

func __of_len_extra(i: int) -> int:
    return __of_get(__load64(__of_tabs() + 8), i)

func __of_dist_base(i: int) -> int:
    return __of_get(__load64(__of_tabs() + 16), i)

func __of_dist_extra(i: int) -> int:
    return __of_get(__load64(__of_tabs() + 24), i)

func __of_cl_order(i: int) -> int:
    return __of_get(__load64(__of_tabs() + 32), i)

# ---- sommes de contrôle ----

func __nat__native_office__crc32(n: int, a: int, b: int) -> int:
    __of_arity("crc32", n, 1, 2)
    data := __of_bytes("crc32", a, "data")
    crc := 0
    if n > 1:
        crc = __of_int("crc32", b, "crc") & 4294967295
    tab := __load64(__of_tabs() + 40)
    crc = crc ^ 4294967295
    p := __nat_bp(data)
    m := __nat_blen(data)
    i := 0
    while i < m:
        crc = __of_get(tab, (crc ^ __load8(p + i)) & 255) ^ (crc >> 8)
        i += 1
    return __dyn_int(crc ^ 4294967295)

func __nat__native_office__adler32(n: int, a: int, b: int) -> int:
    __of_arity("adler32", n, 1, 2)
    data := __of_bytes("adler32", a, "data")
    v := 1
    if n > 1:
        v = __of_int("adler32", b, "value") & 4294967295
    s1 := v & 65535
    s2 := (v >> 16) & 65535
    p := __nat_bp(data)
    m := __nat_blen(data)
    i := 0
    while i < m:
        s1 = (s1 + __load8(p + i)) % 65521
        s2 = (s2 + s1) % 65521
        i += 1
    return __dyn_int((s2 << 16) | s1)

# ---- INFLATE (RFC 1951) ----
# État : [0] entrée [8] taille [16] position [24] tampon de bits [32] nombre de bits [40] sortie (sb) [48] limite (-1)

func __if_fail(m: str):
    __of_vfail("inflate : " + m)

func __if_bits(st: int, need: int) -> int:
    val := __load64(st + 24)
    cnt := __load64(st + 32)
    while cnt < need:
        pos := __load64(st + 16)
        if pos >= __load64(st + 8):
            __if_fail("flux tronqué")
        val = val | (__load8(__load64(st) + pos) << cnt)
        __store64(st + 16, pos + 1)
        cnt += 8
    __store64(st + 24, val >> need)
    __store64(st + 32, cnt - need)
    return val & ((1 << need) - 1)

# Table de Huffman : [0..15] effectifs, [16] symboles (tableau)
func __if_build(h: int, length: int, count: int) -> int:
    k := 0
    while k < 16:
        __of_set(h, k, 0)
        k += 1
    s := 0
    while s < count:
        l := __of_get(length, s)
        __of_set(h, l, __of_get(h, l) + 1)
        s += 1
    sym := __of_arr(count)
    __of_set(h, 16, sym)
    if __of_get(h, 0) == count:
        return 0
    left := 1
    ln := 1
    while ln < 16:
        left = left << 1
        left -= __of_get(h, ln)
        if left < 0:
            return left
        ln += 1
    offs := __of_arr(16)
    ln = 1
    while ln < 15:
        __of_set(offs, ln + 1, __of_get(offs, ln) + __of_get(h, ln))
        ln += 1
    s = 0
    while s < count:
        l := __of_get(length, s)
        if l != 0:
            o := __of_get(offs, l)
            __of_set(sym, o, s)
            __of_set(offs, l, o + 1)
        s += 1
    return left

func __if_decode(st: int, h: int) -> int:
    code := 0
    first := 0
    index := 0
    ln := 1
    while ln < 16:
        code = code | __if_bits(st, 1)
        count := __of_get(h, ln)
        if code - count < first:
            return __of_get(__of_get(h, 16), index + (code - first))
        index += count
        first += count
        first = first << 1
        code = code << 1
        ln += 1
    __if_fail("code de Huffman invalide")
    return 0

func __if_put(st: int, b: int):
    sb := __load64(st + 40)
    lim := __load64(st + 48)
    if lim >= 0 and __load64(sb) >= lim:
        __if_fail("taille décompressée supérieure à la limite (" + __int_to_str(lim) + " octets)")
    __rt_sb_byte(sb, b)

func __if_stored(st: int):
    __store64(st + 24, 0)
    __store64(st + 32, 0)
    inp := __load64(st)
    n := __load64(st + 8)
    pos := __load64(st + 16)
    if pos + 4 > n:
        __if_fail("bloc non compressé tronqué")
    len := __load8(inp + pos) | (__load8(inp + pos + 1) << 8)
    nlen := __load8(inp + pos + 2) | (__load8(inp + pos + 3) << 8)
    pos += 4
    __store64(st + 16, pos)
    if len != ((nlen ^ 65535) & 65535):
        __if_fail("longueur de bloc non compressé incohérente")
    if pos + len > n:
        __if_fail("bloc non compressé tronqué")
    sb := __load64(st + 40)
    lim := __load64(st + 48)
    if lim >= 0 and __load64(sb) + len > lim:
        __if_fail("taille décompressée supérieure à la limite")
    __rt_sb_reserve(sb, len)
    __copy(__load64(sb + 16) + __load64(sb), inp + pos, len)
    __store64(sb, __load64(sb) + len)
    __store64(st + 16, pos + len)

func __if_codes(st: int, lencode: int, distcode: int):
    sb := __load64(st + 40)
    while true:
        sym := __if_decode(st, lencode)
        if sym < 256:
            __if_put(st, sym)
        elif sym == 256:
            return
        else:
            sym -= 257
            if sym >= 29:
                __if_fail("code de longueur invalide")
            len := __of_len_base(sym) + __if_bits(st, __of_len_extra(sym))
            dsym := __if_decode(st, distcode)
            if dsym >= 30:
                __if_fail("code de distance invalide")
            dist := __of_dist_base(dsym) + __if_bits(st, __of_dist_extra(dsym))
            size := __load64(sb)
            if dist > size:
                __if_fail("distance trop grande")
            lim := __load64(st + 48)
            if lim >= 0 and size + len > lim:
                __if_fail("taille décompressée supérieure à la limite")
            __rt_sb_reserve(sb, len)
            d := __load64(sb + 16)
            frm := size - dist
            k := 0
            while k < len:
                __store8(d + size + k, __load8(d + frm + k))
                k += 1
            __store64(sb, size + len)

func __if_fixed(st: int):
    lengths := __of_arr(320)
    s := 0
    while s < 288:
        v := 8
        if s >= 144 and s < 256:
            v = 9
        elif s >= 256 and s < 280:
            v = 7
        __of_set(lengths, s, v)
        s += 1
    lencode := __of_arr(17)
    __if_build(lencode, lengths, 288)
    s = 0
    while s < 30:
        __of_set(lengths, s, 5)
        s += 1
    distcode := __of_arr(17)
    __if_build(distcode, lengths, 30)
    __if_codes(st, lencode, distcode)

func __if_dynamic(st: int):
    lengths := __of_arr(320)
    nlen := __if_bits(st, 5) + 257
    ndist := __if_bits(st, 5) + 1
    ncode := __if_bits(st, 4) + 4
    if nlen > 286 or ndist > 30:
        __if_fail("nombre de codes invalide")
    index := 0
    while index < ncode:
        __of_set(lengths, __of_cl_order(index), __if_bits(st, 3))
        index += 1
    while index < 19:
        __of_set(lengths, __of_cl_order(index), 0)
        index += 1
    lencode := __of_arr(17)
    distcode := __of_arr(17)
    if __if_build(lencode, lengths, 19) != 0:
        __if_fail("table des longueurs de code incomplète")
    index = 0
    while index < nlen + ndist:
        sym := __if_decode(st, lencode)
        if sym < 16:
            __of_set(lengths, index, sym)
            index += 1
        else:
            len := 0
            rep := 0
            if sym == 16:
                if index == 0:
                    __if_fail("répétition sans longueur précédente")
                len = __of_get(lengths, index - 1)
                rep = 3 + __if_bits(st, 2)
            elif sym == 17:
                rep = 3 + __if_bits(st, 3)
            else:
                rep = 11 + __if_bits(st, 7)
            if index + rep > nlen + ndist:
                __if_fail("trop de longueurs")
            while rep > 0:
                __of_set(lengths, index, len)
                index += 1
                rep -= 1
    if __of_get(lengths, 256) == 0:
        __if_fail("code de fin de bloc absent")
    err := __if_build(lencode, lengths, nlen)
    if err < 0 or (err > 0 and nlen - __of_get(lencode, 0) != 1):
        __if_fail("codes littéraux/longueurs incomplets")
    err = __if_build(distcode, lengths + 8 * nlen, ndist)
    if err < 0 or (err > 0 and ndist - __of_get(distcode, 0) != 1):
        __if_fail("codes de distance incomplets")
    __if_codes(st, lencode, distcode)

func __if_run(p: int, n: int, limit: int) -> int:
    st := __alloc(64)
    __store64(st, p)
    __store64(st + 8, n)
    __store64(st + 40, __rt_sb_new())
    __store64(st + 48, limit)
    last := 0
    while last == 0:
        last = __if_bits(st, 1)
        t := __if_bits(st, 2)
        if t == 0:
            __if_stored(st)
        elif t == 1:
            __if_fixed(st)
        elif t == 2:
            __if_dynamic(st)
        else:
            __if_fail("type de bloc invalide")
    return st

func __nat__native_office__inflate(n: int, a: int, b: int) -> int:
    __of_arity("inflate", n, 1, 2)
    data := __of_bytes("inflate", a, "data")
    limit := -1
    if n > 1 and b != 0:
        limit = __of_int("inflate", b, "limit")
    if limit < 0:
        limit = -1
    st := __if_run(__nat_bp(data), __nat_blen(data), limit)
    pair := __dyn_list_new(0)
    __dyn_list_push(pair, __of_sb_list(__load64(st + 40)))
    __dyn_list_push(pair, __dyn_int(__load64(st + 16)))
    return pair

# ---- DEFLATE (compression) ----
# Écriture de bits : [0] sb [8] tampon [16] nombre de bits

func __bw_put(bw: int, value: int, nbits: int):
    buf := __load64(bw + 8) | (value << __load64(bw + 16))
    cnt := __load64(bw + 16) + nbits
    sb := __load64(bw)
    while cnt >= 8:
        __rt_sb_byte(sb, buf & 255)
        buf = (buf >> 8) & 72057594037927935
        cnt -= 8
    __store64(bw + 8, buf)
    __store64(bw + 16, cnt)

func __bw_align(bw: int):
    if __load64(bw + 16) > 0:
        __bw_put(bw, 0, 8 - __load64(bw + 16))

func __df_reverse(code: int, len: int) -> int:
    r := 0
    i := 0
    while i < len:
        r = (r << 1) | (code & 1)
        code = code >> 1
        i += 1
    return r

# Tas min de paires (poids, indice) : tableau [0] taille, puis 2 mots par élément.
func __hp_less(h: int, i: int, j: int) -> bool:
    wi := __of_get(h, 1 + 2 * i)
    wj := __of_get(h, 1 + 2 * j)
    if wi != wj:
        return wi < wj
    return __of_get(h, 2 + 2 * i) < __of_get(h, 2 + 2 * j)

func __hp_swap(h: int, i: int, j: int):
    a := __of_get(h, 1 + 2 * i)
    b := __of_get(h, 2 + 2 * i)
    __of_set(h, 1 + 2 * i, __of_get(h, 1 + 2 * j))
    __of_set(h, 2 + 2 * i, __of_get(h, 2 + 2 * j))
    __of_set(h, 1 + 2 * j, a)
    __of_set(h, 2 + 2 * j, b)

func __hp_push(h: int, w: int, idx: int):
    n := __of_get(h, 0)
    __of_set(h, 1 + 2 * n, w)
    __of_set(h, 2 + 2 * n, idx)
    __of_set(h, 0, n + 1)
    i := n
    while i > 0:
        p := (i - 1) // 2
        if __hp_less(h, i, p):
            __hp_swap(h, i, p)
            i = p
        else:
            break

# Retire le minimum ; ses poids/indice dans h[-2], h[-1] (out).
func __hp_pop(h: int, out: int):
    __of_set(out, 0, __of_get(h, 1))
    __of_set(out, 1, __of_get(h, 2))
    n := __of_get(h, 0) - 1
    __of_set(h, 0, n)
    if n == 0:
        return
    __of_set(h, 1, __of_get(h, 1 + 2 * n))
    __of_set(h, 2, __of_get(h, 2 + 2 * n))
    i := 0
    while true:
        l := 2 * i + 1
        r := l + 1
        m := i
        if l < n and __hp_less(h, l, m):
            m = l
        if r < n and __hp_less(h, r, m):
            m = r
        if m == i:
            break
        __hp_swap(h, i, m)
        i = m

# Longueurs de Huffman limitées à maxBits (fréquences divisées par deux jusqu'à respecter la limite).
func __df_lengths(freq0: int, n: int, maxBits: int) -> int:
    freq := __of_arr(n)
    __copy(freq, freq0, 8 * n)
    lengths := __of_arr(n)
    used := 0
    s := 0
    while s < n:
        if __of_get(freq, s) > 0:
            used += 1
        s += 1
    if used < 2:
        s = 0
        while s < n and used < 2:
            if __of_get(freq, s) == 0:
                __of_set(freq, s, 1)
                used += 1
            s += 1
    # nœuds : poids, gauche, droite (3 mots)
    nodes := __of_arr(3 * (2 * n + 2))
    heap := __of_arr(2 * (2 * n + 2) + 1)
    stack := __of_arr(2 * (2 * n + 2))
    pair := __of_arr(2)
    pair2 := __of_arr(2)
    while true:
        nn := 0
        __of_set(heap, 0, 0)
        s = 0
        while s < n:
            f := __of_get(freq, s)
            if f != 0:
                __of_set(nodes, 3 * nn, f)
                __of_set(nodes, 3 * nn + 1, -1)
                __of_set(nodes, 3 * nn + 2, s)
                __hp_push(heap, f, nn)
                nn += 1
            s += 1
        while __of_get(heap, 0) > 1:
            __hp_pop(heap, pair)
            __hp_pop(heap, pair2)
            w := __of_get(pair, 0) + __of_get(pair2, 0)
            __of_set(nodes, 3 * nn, w)
            __of_set(nodes, 3 * nn + 1, __of_get(pair, 1))
            __of_set(nodes, 3 * nn + 2, __of_get(pair2, 1))
            __hp_push(heap, w, nn)
            nn += 1
        maxLen := 0
        s = 0
        while s < n:
            __of_set(lengths, s, 0)
            s += 1
        sp := 1
        __of_set(stack, 0, __of_get(heap, 2))
        __of_set(stack, 1, 0)
        while sp > 0:
            sp -= 1
            idx := __of_get(stack, 2 * sp)
            depth := __of_get(stack, 2 * sp + 1)
            if __of_get(nodes, 3 * idx + 1) < 0:
                d := depth
                if d < 1:
                    d = 1
                __of_set(lengths, __of_get(nodes, 3 * idx + 2), d)
                if d > maxLen:
                    maxLen = d
            else:
                __of_set(stack, 2 * sp, __of_get(nodes, 3 * idx + 1))
                __of_set(stack, 2 * sp + 1, depth + 1)
                sp += 1
                __of_set(stack, 2 * sp, __of_get(nodes, 3 * idx + 2))
                __of_set(stack, 2 * sp + 1, depth + 1)
                sp += 1
        if maxLen <= maxBits:
            return lengths
        s = 0
        while s < n:
            f := __of_get(freq, s)
            if f != 0:
                f = f >> 1
                if f < 1:
                    f = 1
                __of_set(freq, s, f)
            s += 1
    return lengths

func __df_codes(lengths: int, n: int) -> int:
    blCount := __of_arr(16)
    s := 0
    while s < n:
        l := __of_get(lengths, s)
        __of_set(blCount, l, __of_get(blCount, l) + 1)
        s += 1
    __of_set(blCount, 0, 0)
    nextCode := __of_arr(16)
    code := 0
    b := 1
    while b < 16:
        code = (code + __of_get(blCount, b - 1)) << 1
        __of_set(nextCode, b, code)
        b += 1
    codes := __of_arr(n)
    s = 0
    while s < n:
        l := __of_get(lengths, s)
        if l != 0:
            c := __of_get(nextCode, l)
            __of_set(nextCode, l, c + 1)
            __of_set(codes, s, __df_reverse(c, l))
        s += 1
    return codes

func __df_length_code(len: int) -> int:
    i := 28
    while i >= 0:
        if len >= __of_len_base(i):
            return i
        i -= 1
    return 0

func __df_dist_code(dist: int) -> int:
    i := 29
    while i >= 0:
        if dist >= __of_dist_base(i):
            return i
        i -= 1
    return 0

# Deflater : [0] entrée [8] taille [16] bw [24] symboles (3 mots chacun) [32] nombre de symboles
func __df_stored(df: int, frm: int, to: int, final: bool):
    bw := __load64(df + 16)
    fin := 0
    if final:
        fin = 1
    if frm == to:
        __bw_put(bw, fin, 1)
        __bw_put(bw, 0, 2)
        __bw_align(bw)
        __bw_put(bw, 0, 16)
        __bw_put(bw, 65535, 16)
        return
    inp := __load64(df)
    while frm < to:
        len := to - frm
        if len > 65535:
            len = 65535
        last := 0
        if final and frm + len == to:
            last = 1
        __bw_put(bw, last, 1)
        __bw_put(bw, 0, 2)
        __bw_align(bw)
        __bw_put(bw, len, 16)
        __bw_put(bw, (len ^ 65535) & 65535, 16)
        sb := __load64(bw)
        __rt_sb_reserve(sb, len)
        __copy(__load64(sb + 16) + __load64(sb), inp + frm, len)
        __store64(sb, __load64(sb) + len)
        frm += len

func __df_write_syms(df: int, lc: int, ll: int, dc: int, dl: int):
    bw := __load64(df + 16)
    syms := __load64(df + 24)
    m := __load64(df + 32)
    i := 0
    while i < m:
        lit := __of_get(syms, 3 * i)
        dist := __of_get(syms, 3 * i + 1)
        __bw_put(bw, __of_get(lc, lit), __of_get(ll, lit))
        if dist != 0:
            li := lit - 257
            if __of_len_extra(li) != 0:
                __bw_put(bw, __of_get(syms, 3 * i + 2) - __of_len_base(li), __of_len_extra(li))
            di := __df_dist_code(dist)
            __bw_put(bw, __of_get(dc, di), __of_get(dl, di))
            if __of_dist_extra(di) != 0:
                __bw_put(bw, dist - __of_dist_base(di), __of_dist_extra(di))
        i += 1
    __bw_put(bw, __of_get(lc, 256), __of_get(ll, 256))

func __df_fixed_len(s: int) -> int:
    if s < 144:
        return 8
    if s < 256:
        return 9
    if s < 280:
        return 7
    return 8

func __df_emit(df: int, frm: int, to: int, final: bool):
    bw := __load64(df + 16)
    syms := __load64(df + 24)
    m := __load64(df + 32)
    lf := __of_arr(286)
    dfq := __of_arr(30)
    i := 0
    while i < m:
        lit := __of_get(syms, 3 * i)
        __of_set(lf, lit, __of_get(lf, lit) + 1)
        dist := __of_get(syms, 3 * i + 1)
        if dist != 0:
            dc := __df_dist_code(dist)
            __of_set(dfq, dc, __of_get(dfq, dc) + 1)
        i += 1
    __of_set(lf, 256, 1)
    fixedBits := 3
    s := 0
    while s < 286:
        f := __of_get(lf, s)
        if f != 0:
            fixedBits += f * __df_fixed_len(s)
            if s > 256:
                fixedBits += f * __of_len_extra(s - 257)
        s += 1
    d := 0
    while d < 30:
        fixedBits += __of_get(dfq, d) * (5 + __of_dist_extra(d))
        d += 1
    ll := __df_lengths(lf, 286, 15)
    dl := __df_lengths(dfq, 30, 15)
    hlit := 286
    while hlit > 257 and __of_get(ll, hlit - 1) == 0:
        hlit -= 1
    hdist := 30
    while hdist > 1 and __of_get(dl, hdist - 1) == 0:
        hdist -= 1
    total := hlit + hdist
    all := __of_arr(total)
    __copy(all, ll, 8 * hlit)
    __copy(all + 8 * hlit, dl, 8 * hdist)
    # RLE des longueurs : (symbole, extra, nbits)
    rle := __of_arr(3 * total + 3)
    nr := 0
    i = 0
    while i < total:
        v := __of_get(all, i)
        run := 1
        while i + run < total and __of_get(all, i + run) == v:
            run += 1
        if v == 0 and run >= 3:
            r := run
            if r > 138:
                r = 138
            if r >= 11:
                __of_set(rle, 3 * nr, 18)
                __of_set(rle, 3 * nr + 1, r - 11)
                __of_set(rle, 3 * nr + 2, 7)
            else:
                __of_set(rle, 3 * nr, 17)
                __of_set(rle, 3 * nr + 1, r - 3)
                __of_set(rle, 3 * nr + 2, 3)
            nr += 1
            i += r
        elif v != 0 and run >= 4:
            __of_set(rle, 3 * nr, v)
            __of_set(rle, 3 * nr + 1, 0)
            __of_set(rle, 3 * nr + 2, 0)
            nr += 1
            r := run - 1
            if r > 6:
                r = 6
            __of_set(rle, 3 * nr, 16)
            __of_set(rle, 3 * nr + 1, r - 3)
            __of_set(rle, 3 * nr + 2, 2)
            nr += 1
            i += 1 + r
        else:
            __of_set(rle, 3 * nr, v)
            __of_set(rle, 3 * nr + 1, 0)
            __of_set(rle, 3 * nr + 2, 0)
            nr += 1
            i += 1
    cf := __of_arr(19)
    i = 0
    while i < nr:
        c := __of_get(rle, 3 * i)
        __of_set(cf, c, __of_get(cf, c) + 1)
        i += 1
    cl := __df_lengths(cf, 19, 7)
    hclen := 19
    while hclen > 4 and __of_get(cl, __of_cl_order(hclen - 1)) == 0:
        hclen -= 1
    dynBits := 3 + 5 + 5 + 4 + 3 * hclen
    i = 0
    while i < nr:
        dynBits += __of_get(cl, __of_get(rle, 3 * i)) + __of_get(rle, 3 * i + 2)
        i += 1
    s = 0
    while s < 286:
        f := __of_get(lf, s)
        if f != 0:
            dynBits += f * __of_get(ll, s)
            if s > 256:
                dynBits += f * __of_len_extra(s - 257)
        s += 1
    d = 0
    while d < 30:
        dynBits += __of_get(dfq, d) * (__of_get(dl, d) + __of_dist_extra(d))
        d += 1
    storedBits := (to - frm) * 8 + 40 * (1 + (to - frm) // 65535) + 8
    fin := 0
    if final:
        fin = 1
    if storedBits <= fixedBits and storedBits <= dynBits:
        __df_stored(df, frm, to, final)
    elif fixedBits <= dynBits:
        fll := __of_arr(288)
        s = 0
        while s < 288:
            __of_set(fll, s, __df_fixed_len(s))
            s += 1
        fdl := __of_arr(30)
        s = 0
        while s < 30:
            __of_set(fdl, s, 5)
            s += 1
        __bw_put(bw, fin, 1)
        __bw_put(bw, 1, 2)
        __df_write_syms(df, __df_codes(fll, 288), fll, __df_codes(fdl, 30), fdl)
    else:
        __bw_put(bw, fin, 1)
        __bw_put(bw, 2, 2)
        __bw_put(bw, hlit - 257, 5)
        __bw_put(bw, hdist - 1, 5)
        __bw_put(bw, hclen - 4, 4)
        i = 0
        while i < hclen:
            __bw_put(bw, __of_get(cl, __of_cl_order(i)), 3)
            i += 1
        ccodes := __df_codes(cl, 19)
        i = 0
        while i < nr:
            c := __of_get(rle, 3 * i)
            __bw_put(bw, __of_get(ccodes, c), __of_get(cl, c))
            if __of_get(rle, 3 * i + 2) != 0:
                __bw_put(bw, __of_get(rle, 3 * i + 1), __of_get(rle, 3 * i + 2))
            i += 1
        __df_write_syms(df, __df_codes(ll, 286), ll, __df_codes(dl, 30), dl)

func __df_hash(inp: int, i: int) -> int:
    h := (__load8(inp + i) << 16) | (__load8(inp + i + 1) << 8) | __load8(inp + i + 2)
    return ((h * 2654435761) & 4294967295) >> 17

func __df_insert(inp: int, n: int, head: int, prev: int, i: int):
    if i + 2 >= n:
        return
    h := __df_hash(inp, i)
    __of_set(prev, i, __of_get(head, h))
    __of_set(head, h, i)

# Plus longue correspondance en i ; distance dans res[0] ; 0 si < 3.
func __df_longest(inp: int, n: int, head: int, prev: int, i: int, maxChain: int, nice: int, res: int) -> int:
    best := 0
    if i + 2 >= n:
        return 0
    cand := __of_get(head, __df_hash(inp, i))
    chain := maxChain
    maxLen := n - i
    if maxLen > 258:
        maxLen = 258
    while cand >= 0 and chain > 0:
        chain -= 1
        dist := i - cand
        if dist > 32768:
            break
        if dist > 0 and __load8(inp + cand + best) == __load8(inp + i + best):
            l := 0
            while l < maxLen and __load8(inp + cand + l) == __load8(inp + i + l):
                l += 1
            if l > best:
                best = l
                __of_set(res, 0, dist)
                if best >= nice or l == maxLen:
                    break
        cand = __of_get(prev, cand)
    if best >= 3:
        return best
    return 0

func __df_sym(df: int, lit: int, dist: int, len: int):
    syms := __load64(df + 24)
    k := __load64(df + 32)
    __of_set(syms, 3 * k, lit)
    __of_set(syms, 3 * k + 1, dist)
    __of_set(syms, 3 * k + 2, len)
    __store64(df + 32, k + 1)

func __df_run(inp: int, n: int, level: int) -> int:
    df := __alloc(48)
    __store64(df, inp)
    __store64(df + 8, n)
    bw := __alloc(32)
    __store64(bw, __rt_sb_new())
    __store64(df + 16, bw)
    __store64(df + 24, __of_arr(3 * 16400))
    if level <= 0:
        __df_stored(df, 0, n, true)
        __bw_align(bw)
        return __load64(bw)
    chains := __of_table("0,4,8,16,32,64,128,256,1024,4096")
    nices := __of_table("0,8,16,32,64,128,128,258,258,258")
    lv := level
    if lv > 9:
        lv = 9
    maxChain := __of_get(chains, lv)
    nice := __of_get(nices, lv)
    lazy := level >= 4
    head := __alloc_raw(8 * 32768)
    k := 0
    while k < 32768:
        __of_set(head, k, -1)
        k += 1
    pn := n
    if pn < 1:
        pn = 1
    prev := __alloc_raw(8 * pn)
    k = 0
    while k < pn:
        __of_set(prev, k, -1)
        k += 1
    res := __of_arr(2)
    blockStart := 0
    i := 0
    while i < n:
        __of_set(res, 0, 0)
        len := __df_longest(inp, n, head, prev, i, maxChain, nice, res)
        dist := __of_get(res, 0)
        if len != 0 and lazy and i + 1 < n:
            __df_insert(inp, n, head, prev, i)
            __of_set(res, 0, 0)
            len2 := __df_longest(inp, n, head, prev, i + 1, maxChain, nice, res)
            dist2 := __of_get(res, 0)
            if len2 > len:
                __df_sym(df, __load8(inp + i), 0, 0)
                i += 1
                len = len2
                dist = dist2
            else:
                __df_sym(df, 257 + __df_length_code(len), dist, len)
                k = 1
                while k < len:
                    __df_insert(inp, n, head, prev, i + k)
                    k += 1
                i += len
                if __load64(df + 32) >= 16384:
                    __df_emit(df, blockStart, i, false)
                    __store64(df + 32, 0)
                    blockStart = i
                continue
        if len != 0:
            __df_sym(df, 257 + __df_length_code(len), dist, len)
            k = 0
            while k < len:
                __df_insert(inp, n, head, prev, i + k)
                k += 1
            i += len
        else:
            __df_sym(df, __load8(inp + i), 0, 0)
            __df_insert(inp, n, head, prev, i)
            i += 1
        if __load64(df + 32) >= 16384:
            __df_emit(df, blockStart, i, false)
            __store64(df + 32, 0)
            blockStart = i
    __df_emit(df, blockStart, i, true)
    __store64(df + 32, 0)
    __bw_align(bw)
    return __load64(bw)

func __nat__native_office__deflate(n: int, a: int, b: int) -> int:
    __of_arity("deflate", n, 1, 2)
    data := __of_bytes("deflate", a, "data")
    level := 6
    if n > 1 and b != 0:
        level = __of_int("deflate", b, "level")
    if level < 0 or level > 9:
        __of_vfail("deflate : level doit être compris entre 0 et 9")
    return __of_sb_list(__df_run(__nat_bp(data), __nat_blen(data), level))

# ---- octets ----

func __nat__native_office__bytes_slice(n: int, a: int, b: int, c: int) -> int:
    __of_arity("bytes_slice", n, 2, 3)
    if not __of_is_seq(a):
        __of_tfail("'bytes_slice' : liste attendue")
    m := __of_seq_len(a)
    start := __of_int("bytes_slice", b, "start")
    stop := m
    if n > 2 and c != 0:
        stop = __of_int("bytes_slice", c, "stop")
    if start < 0:
        start += m
    if stop < 0:
        stop += m
    if start < 0:
        start = 0
    if start > m:
        start = m
    if stop < start:
        stop = start
    if stop > m:
        stop = m
    out := __dyn_list_new(0)
    i := start
    while i < stop:
        __dyn_list_push(out, __of_seq_at(a, i))
        i += 1
    return out

func __nat__native_office__bytes_concat(n: int, a: int) -> int:
    __of_arity("bytes_concat", n, 1, 1)
    if not __of_is_seq(a):
        __of_tfail("'bytes_concat' : liste de listes attendue")
    m := __of_seq_len(a)
    i := 0
    while i < m:
        if not __of_is_seq(__of_seq_at(a, i)):
            __of_tfail("'bytes_concat' : chaque élément doit être une liste")
        i += 1
    out := __dyn_list_new(0)
    i = 0
    while i < m:
        p := __of_seq_at(a, i)
        k := 0
        while k < __of_seq_len(p):
            __dyn_list_push(out, __of_seq_at(p, k))
            k += 1
        i += 1
    return out

func __of_as_byte(v: int) -> int:
    if __dyn_is(v, 1) or __dyn_is(v, 5):
        return __load64(v + 8)
    return -1

func __of_byte_vec(v: int) -> int:
    m := __of_seq_len(v)
    a := __of_arr(m)
    i := 0
    while i < m:
        __of_set(a, i, __of_as_byte(__of_seq_at(v, i)))
        i += 1
    return a

func __nat__native_office__bytes_find(n: int, a: int, b: int, c: int) -> int:
    __of_arity("bytes_find", n, 2, 3)
    if not __of_is_seq(a) or not __of_is_seq(b):
        __of_tfail("'bytes_find' : listes d'octets attendues")
    start := 0
    if n > 2:
        start = __of_int("bytes_find", c, "start")
    if start < 0:
        start = 0
    hn := __of_seq_len(a)
    nn := __of_seq_len(b)
    if nn == 0:
        if start < hn:
            return __dyn_int(start)
        return __dyn_int(hn)
    h := __of_byte_vec(a)
    nd := __of_byte_vec(b)
    i := start
    while i + nn <= hn:
        if __of_get(h, i) == __of_get(nd, 0):
            k := 1
            while k < nn and __of_get(h, i + k) == __of_get(nd, k):
                k += 1
            if k == nn:
                return __dyn_int(i)
        i += 1
    return __dyn_int(-1)

func __nat__native_office__bytes_rfind(n: int, a: int, b: int, c: int) -> int:
    __of_arity("bytes_rfind", n, 2, 3)
    if not __of_is_seq(a) or not __of_is_seq(b):
        __of_tfail("'bytes_rfind' : listes d'octets attendues")
    hn := __of_seq_len(a)
    nn := __of_seq_len(b)
    if nn > hn:
        return __dyn_int(-1)
    start := -1
    if n > 2:
        start = __of_int("bytes_rfind", c, "start")
    maxStart := hn - nn
    if start < 0 or start > maxStart:
        start = maxStart
    h := __of_byte_vec(a)
    nd := __of_byte_vec(b)
    i := start
    while i >= 0:
        k := 0
        while k < nn and __of_get(h, i + k) == __of_get(nd, k):
            k += 1
        if k == nn:
            return __dyn_int(i)
        i -= 1
    return __dyn_int(-1)

func __nat__native_office__bytes_fill(n: int, a: int, b: int) -> int:
    __of_arity("bytes_fill", n, 1, 2)
    m := __of_int("bytes_fill", a, "n")
    v := 0
    if n > 1:
        v = __of_int("bytes_fill", b, "value")
    if m < 0 or m > 4294967296:
        __of_vfail("bytes_fill : taille invalide")
    out := __dyn_list_new(0)
    bv := __dyn_int(v)
    i := 0
    while i < m:
        __dyn_list_push(out, bv)
        i += 1
    return out

# ---- texte ----

func __nat__native_office__utf8_encode(n: int, a: int) -> int:
    __of_arity("utf8_encode", n, 1, 1)
    s := __of_str("utf8_encode", a, "s")
    return __of_blist(__nat_bp(s), __nat_blen(s))

func __of_utf8_decode(p: int, n: int, strict: bool) -> str:
    sb := __rt_sb_new()
    i := 0
    while i < n:
        b := __load8(p + i)
        if b < 128:
            __rt_sb_byte(sb, b)
            i += 1
            continue
        need := 0
        cp := 0
        lo := 0
        if b >= 194 and b <= 223:
            need = 1
            cp = b & 31
            lo = 128
        elif b >= 224 and b <= 239:
            need = 2
            cp = b & 15
            lo = 2048
        elif b >= 240 and b <= 244:
            need = 3
            cp = b & 7
            lo = 65536
        else:
            if strict:
                __of_vfail("utf8_decode : octet de début invalide à l'indice " + __int_to_str(i))
            __nat_sb_cp(sb, 65533)
            i += 1
            continue
        ok := i + need < n
        if ok:
            k := 1
            while k <= need:
                c := __load8(p + i + k)
                if (c & 192) != 128:
                    ok = false
                    break
                cp = (cp << 6) | (c & 63)
                k += 1
        if ok and (cp < lo or cp > 1114111 or (cp >= 55296 and cp <= 57343)):
            ok = false
        if not ok:
            if strict:
                __of_vfail("utf8_decode : séquence invalide à l'indice " + __int_to_str(i))
            __nat_sb_cp(sb, 65533)
            i += 1
            continue
        __nat_sb_cp(sb, cp)
        i += need + 1
    return __rt_sb_str(sb)

func __nat__native_office__utf8_decode(n: int, a: int, b: int) -> int:
    __of_arity("utf8_decode", n, 1, 2)
    d := __of_bytes("utf8_decode", a, "data")
    strict := n > 1 and __dyn_truthy(b)
    return __dyn_str(__of_utf8_decode(__nat_bp(d), __nat_blen(d), strict))

func __nat__native_office__latin1_decode(n: int, a: int) -> int:
    __of_arity("latin1_decode", n, 1, 1)
    d := __of_bytes("latin1_decode", a, "data")
    sb := __rt_sb_new()
    i := 0
    while i < __nat_blen(d):
        __nat_sb_cp(sb, __load8(__nat_bp(d) + i))
        i += 1
    return __dyn_str(__rt_sb_str(sb))

func __nat__native_office__latin1_encode(n: int, a: int, b: int) -> int:
    __of_arity("latin1_encode", n, 1, 2)
    s := __of_str("latin1_encode", a, "s")
    repl := -1
    if n > 1 and b != 0:
        repl = __of_int("latin1_encode", b, "replacement")
    cps := __nat_decode(s)
    out := __dyn_list_new(0)
    i := 0
    while i < __load64(cps):
        c := __rt_vec_at(cps, i)
        if c > 255:
            if repl < 0:
                __of_vfail("latin1_encode : caractère U+" + __int_to_str(c) + " hors de Latin-1 à l'indice " + __int_to_str(i))
            c = repl
        __dyn_list_push(out, __dyn_int(c))
        i += 1
    return out

func __nat__native_office__str_find(n: int, a: int, b: int, c: int) -> int:
    __of_arity("str_find", n, 2, 3)
    s := __of_str("str_find", a, "s")
    sub := __of_str("str_find", b, "sub")
    start := 0
    if n > 2:
        start = __of_int("str_find", c, "start")
    if start < 0:
        start = 0
    if __of_ascii(s) and __of_ascii(sub):
        if start > __nat_blen(s):
            return __dyn_int(-1)
        return __dyn_int(__dyn_find_bytes(s, sub, start))
    cs := __nat_decode(s)
    cu := __nat_decode(sub)
    sn := __load64(cs)
    m := __load64(cu)
    if start > sn:
        return __dyn_int(-1)
    if m == 0:
        return __dyn_int(start)
    i := start
    while i + m <= sn:
        if __rt_vec_at(cs, i) == __rt_vec_at(cu, 0):
            k := 1
            while k < m and __rt_vec_at(cs, i + k) == __rt_vec_at(cu, k):
                k += 1
            if k == m:
                return __dyn_int(i)
        i += 1
    return __dyn_int(-1)

func __nat__native_office__str_slice(n: int, a: int, b: int, c: int) -> int:
    __of_arity("str_slice", n, 2, 3)
    s := __of_str("str_slice", a, "s")
    asc := __of_ascii(s)
    cps := 0
    m := __nat_blen(s)
    if not asc:
        cps = __nat_decode(s)
        m = __load64(cps)
    start := 0
    if b != 0:
        start = __of_int("str_slice", b, "start")
    stop := m
    if n > 2 and c != 0:
        stop = __of_int("str_slice", c, "stop")
    if start < 0:
        start += m
    if stop < 0:
        stop += m
    if start < 0:
        start = 0
    if start > m:
        start = m
    if stop < start:
        stop = start
    if stop > m:
        stop = m
    if asc:
        return __dyn_str(__nat_sub(s, start, stop - start))
    return __dyn_str(__nat_encode(cps, start, stop))

# ---- XML ----

func __of_xml_allowed(c: int) -> bool:
    return c == 9 or c == 10 or c == 13 or (c >= 32 and c <= 55295) or (c >= 57344 and c <= 65533) or (c >= 65536 and c <= 1114111)

func __of_xml_escape_into(sb: int, s: str, attr: bool):
    p := __nat_bp(s)
    n := __nat_blen(s)
    i := 0
    while i < n:
        c := __load8(p + i)
        if c < 128:
            if c == 38:
                __rt_sb_add(sb, "&amp;")
            elif c == 60:
                __rt_sb_add(sb, "&lt;")
            elif c == 62:
                __rt_sb_add(sb, "&gt;")
            elif c == 34:
                if attr:
                    __rt_sb_add(sb, "&quot;")
                else:
                    __rt_sb_byte(sb, 34)
            elif c == 10:
                if attr:
                    __rt_sb_add(sb, "&#10;")
                else:
                    __rt_sb_byte(sb, 10)
            elif c == 13:
                __rt_sb_add(sb, "&#13;")
            elif c == 9:
                if attr:
                    __rt_sb_add(sb, "&#9;")
                else:
                    __rt_sb_byte(sb, 9)
            elif c >= 32:
                __rt_sb_byte(sb, c)
            i += 1
            continue
        w := 1
        if (c & 224) == 192:
            w = 2
        elif (c & 240) == 224:
            w = 3
        elif (c & 248) == 240:
            w = 4
        if w == 3 and i + 2 < n and c == 239 and __load8(p + i + 1) == 191 and (__load8(p + i + 2) == 190 or __load8(p + i + 2) == 191):
            i += 3
            continue
        if w == 1:
            i += 1
            continue
        k := w
        if k > n - i:
            k = n - i
        j := 0
        while j < k:
            __rt_sb_byte(sb, __load8(p + i + j))
            j += 1
        i += w

func __nat__native_office__xml_escape(n: int, a: int, b: int) -> int:
    __of_arity("xml_escape", n, 1, 2)
    s := __of_str("xml_escape", a, "s")
    attr := n > 1 and __dyn_truthy(b)
    sb := __rt_sb_new()
    __of_xml_escape_into(sb, s, attr)
    return __dyn_str(__rt_sb_str(sb))

# Analyseur : [0] texte [8] position [16] taille [24] keepWs
func __xp_c(x: int, k: int) -> int:
    return __load8(__nat_bp(__as_str(__load64(x))) + k)

func __xp_fail_at(x: int, msg: str, at: int):
    s := __as_str(__load64(x))
    p := __nat_bp(s)
    n := __nat_blen(s)
    line := 1
    col := 1
    k := 0
    while k < at and k < n:
        c := __load8(p + k)
        if c == 10:
            line += 1
            col = 1
        elif (c & 192) != 128:
            col += 1
        k += 1
    __of_vfail(msg + " (ligne " + __int_to_str(line) + ", colonne " + __int_to_str(col) + ")")

func __xp_fail(x: int, msg: str):
    __xp_fail_at(x, msg, __load64(x + 8))

func __xp_starts(x: int, lit: str) -> bool:
    i := __load64(x + 8)
    m := __nat_blen(lit)
    if i + m > __load64(x + 16):
        return false
    k := 0
    while k < m:
        if __xp_c(x, i + k) != __load8(__nat_bp(lit) + k):
            return false
        k += 1
    return true

func __xp_space(c: int) -> bool:
    return c == 32 or c == 9 or c == 10 or c == 13

func __xp_skip_ws(x: int):
    i := __load64(x + 8)
    while i < __load64(x + 16) and __xp_space(__xp_c(x, i)):
        i += 1
    __store64(x + 8, i)

func __xp_name_stop(c: int) -> bool:
    return __xp_space(c) or c == 47 or c == 62 or c == 61 or c == 60 or c == 34 or c == 39 or c == 63 or c == 33

func __xp_name(x: int) -> str:
    st := __load64(x + 8)
    i := st
    while i < __load64(x + 16) and not __xp_name_stop(__xp_c(x, i)):
        i += 1
    __store64(x + 8, i)
    if i == st:
        __xp_fail(x, "nom attendu")
    c0 := __xp_c(x, st)
    if (c0 >= 48 and c0 <= 57) or c0 == 45 or c0 == 46:
        __xp_fail_at(x, "nom invalide", st)
    return __nat_sub(__as_str(__load64(x)), st, i - st)

func __xp_find(x: int, lit: str, frm: int) -> int:
    return __dyn_find_bytes(__as_str(__load64(x)), lit, frm)

func __xp_skip_until(x: int, end: str, what: str):
    p := __xp_find(x, end, __load64(x + 8))
    if p < 0:
        __xp_fail(x, what + " non terminé")
    __store64(x + 8, p + __nat_blen(end))

func __xp_decode_into(x: int, sb: int, frm: int, to: int, attr: bool):
    s := __as_str(__load64(x))
    k := frm
    while k < to:
        c := __xp_c(x, k)
        if c == 38:
            semi := __xp_find(x, ";", k)
            if semi < 0 or semi >= to or semi - k > 12:
                __xp_fail_at(x, "entité mal formée", k)
            ent := __nat_sub(s, k + 1, semi - k - 1)
            if __rt_str_eq(ent, "lt"):
                __rt_sb_byte(sb, 60)
            elif __rt_str_eq(ent, "gt"):
                __rt_sb_byte(sb, 62)
            elif __rt_str_eq(ent, "amp"):
                __rt_sb_byte(sb, 38)
            elif __rt_str_eq(ent, "quot"):
                __rt_sb_byte(sb, 34)
            elif __rt_str_eq(ent, "apos"):
                __rt_sb_byte(sb, 39)
            elif __nat_blen(ent) > 0 and __load8(__nat_bp(ent)) == 35:
                cp := 0
                el := __nat_blen(ent)
                ep := __nat_bp(ent)
                hex := el > 1 and (__load8(ep + 1) == 120 or __load8(ep + 1) == 88)
                d0 := 1
                if hex:
                    d0 = 2
                if d0 >= el:
                    __xp_fail_at(x, "référence de caractère vide", k)
                d := d0
                while d < el:
                    ch := __load8(ep + d)
                    v := 0
                    if ch >= 48 and ch <= 57:
                        v = ch - 48
                    elif hex and ch >= 97 and ch <= 102:
                        v = ch - 87
                    elif hex and ch >= 65 and ch <= 70:
                        v = ch - 55
                    else:
                        __xp_fail_at(x, "référence de caractère invalide '&" + ent + ";'", k)
                    base := 10
                    if hex:
                        base = 16
                    cp = cp * base + v
                    if cp > 1114111:
                        __xp_fail_at(x, "référence de caractère hors Unicode", k)
                    d += 1
                if not __of_xml_allowed(cp):
                    __xp_fail_at(x, "référence à un caractère interdit en XML", k)
                __nat_sb_cp(sb, cp)
            else:
                __xp_fail_at(x, "entité inconnue '&" + ent + ";'", k)
            k = semi
        elif c == 13:
            if attr:
                __rt_sb_byte(sb, 32)
            else:
                __rt_sb_byte(sb, 10)
            if k + 1 < to and __xp_c(x, k + 1) == 10:
                k += 1
        elif attr and (c == 10 or c == 9):
            __rt_sb_byte(sb, 32)
        elif c == 60 and attr:
            __xp_fail_at(x, "'<' interdit dans une valeur d'attribut", k)
        else:
            __rt_sb_byte(sb, c)
        k += 1

func __xp_skip_misc(x: int) -> bool:
    if __xp_starts(x, "<!--"):
        __store64(x + 8, __load64(x + 8) + 4)
        __xp_skip_until(x, "-->", "commentaire")
        return true
    if __xp_starts(x, "<?"):
        __store64(x + 8, __load64(x + 8) + 2)
        __xp_skip_until(x, "?>", "instruction de traitement")
        return true
    if __xp_starts(x, "<!DOCTYPE"):
        depth := 0
        i := __load64(x + 8)
        while i < __load64(x + 16):
            c := __xp_c(x, i)
            if c == 91:
                depth += 1
            elif c == 93:
                depth -= 1
            elif c == 62 and depth <= 0:
                __store64(x + 8, i + 1)
                return true
            i += 1
        __store64(x + 8, i)
        __xp_fail(x, "DOCTYPE non terminé")
    return false

# Balise ouvrante (position sur '<') : élément ; out[0] = enfants, out[1] = auto-fermante, out[2] = étiquette
func __xp_open(x: int, out: int) -> int:
    at := __load64(x + 8)
    __store64(x + 8, at + 1)
    tag := __xp_name(x)
    el := __dyn_dict_new()
    attrs := __dyn_dict_new()
    children := __dyn_list_new(0)
    __nat_dict_put(el, "tag", __dyn_str(tag))
    __nat_dict_put(el, "attrs", attrs)
    __nat_dict_put(el, "children", children)
    __store64(out, children)
    __store64(out + 16, __str_addr(tag))
    s := __as_str(__load64(x))
    n := __load64(x + 16)
    while true:
        i := __load64(x + 8)
        hadSpace := i < n and __xp_space(__xp_c(x, i))
        __xp_skip_ws(x)
        i = __load64(x + 8)
        if i >= n:
            __xp_fail_at(x, "balise <" + tag + "> non terminée", at)
        c := __xp_c(x, i)
        if c == 62:
            __store64(x + 8, i + 1)
            __store64(out + 8, 0)
            return el
        if c == 47:
            if not __xp_starts(x, "/>"):
                __xp_fail(x, "'/>' attendu")
            __store64(x + 8, i + 2)
            __store64(out + 8, 1)
            return el
        if not hadSpace:
            __xp_fail(x, "espace attendu avant l'attribut")
        an := __xp_name(x)
        __xp_skip_ws(x)
        i = __load64(x + 8)
        if i >= n or __xp_c(x, i) != 61:
            __xp_fail(x, "'=' attendu après l'attribut '" + an + "'")
        __store64(x + 8, i + 1)
        __xp_skip_ws(x)
        i = __load64(x + 8)
        if i >= n or (__xp_c(x, i) != 34 and __xp_c(x, i) != 39):
            __xp_fail(x, "valeur d'attribut entre guillemets attendue")
        q := __xp_c(x, i)
        vs := i + 1
        ve := vs
        while ve < n and __xp_c(x, ve) != q:
            ve += 1
        if ve >= n:
            __xp_fail_at(x, "valeur d'attribut non terminée", vs)
        vb := __rt_sb_new()
        __xp_decode_into(x, vb, vs, ve, true)
        __store64(x + 8, ve + 1)
        key := __dyn_str(an)
        if __dyn_dict_get_raw(attrs, key) != 1:
            __xp_fail_at(x, "attribut dupliqué '" + an + "'", vs)
        __rt_dict_set(__dyn_dv(attrs), key, __dyn_str(__rt_sb_str(vb)), 3)
    return el

func __xp_all_ws(s: str) -> bool:
    i := 0
    while i < __nat_blen(s):
        if not __xp_space(__load8(__nat_bp(s) + i)):
            return false
        i += 1
    return true

# Pile : liste native de triplets [étiquette, enfants, position]
func __xp_flush(x: int, stack: int, text: int, has: int):
    if __load64(has) == 0:
        return
    __store64(has, 0)
    t := __rt_sb_str(text)
    __store64(text, 0)
    if __load64(stack) == 0:
        if not __xp_all_ws(t):
            __xp_fail(x, "texte hors de l'élément racine")
        return
    if __nat_blen(t) > 0 and (__load64(x + 24) != 0 or not __xp_all_ws(t)):
        top := __rt_vec_at(stack, __load64(stack) - 1)
        __dyn_list_push(__load64(top + 8), __dyn_str(t))

func __nat__native_office__xml_parse(n: int, a: int, b: int) -> int:
    __of_arity("xml_parse", n, 1, 2)
    s := __of_str("xml_parse", a, "text")
    keep := n > 1 and __dyn_truthy(b)
    x := __alloc(32)
    __store64(x, __str_addr(s))
    sn := __nat_blen(s)
    __store64(x + 16, sn)
    if keep:
        __store64(x + 24, 1)
    p := __nat_bp(s)
    if sn >= 3 and __load8(p) == 239 and __load8(p + 1) == 187 and __load8(p + 2) == 191:
        __store64(x + 8, 3)
    root := 0
    stack := __rt_list_new(0)
    text := __rt_sb_new()
    has := __alloc_raw(8)
    __store64(has, 0)
    out := __alloc(24)
    while __load64(x + 8) < sn:
        i := __load64(x + 8)
        c := __load8(p + i)
        if c == 60:
            if __xp_starts(x, "<![CDATA["):
                if __load64(stack) == 0:
                    __xp_fail(x, "CDATA hors de l'élément racine")
                st := i + 9
                e := __xp_find(x, "]]>", st)
                if e < 0:
                    __xp_fail(x, "CDATA non terminé")
                __rt_sb_add(text, __nat_sub(s, st, e - st))
                __store64(has, 1)
                __store64(x + 8, e + 3)
                continue
            if __xp_starts(x, "<!--") or __xp_starts(x, "<?") or __xp_starts(x, "<!DOCTYPE"):
                __xp_skip_misc(x)
                continue
            __xp_flush(x, stack, text, has)
            if __xp_starts(x, "</"):
                at := i
                __store64(x + 8, i + 2)
                close := __xp_name(x)
                __xp_skip_ws(x)
                j := __load64(x + 8)
                if j >= sn or __load8(p + j) != 62:
                    __xp_fail(x, "'>' attendu")
                __store64(x + 8, j + 1)
                if __load64(stack) == 0:
                    __xp_fail_at(x, "balise fermante </" + close + "> sans ouvrante", at)
                top := __rt_vec_at(stack, __load64(stack) - 1)
                ttag := __as_str(__load64(top))
                if not __rt_str_eq(ttag, close):
                    __xp_fail_at(x, "</" + close + "> ne correspond pas à <" + ttag + ">", at)
                __store64(stack, __load64(stack) - 1)
                continue
            if __load64(stack) == 0 and root != 0:
                __xp_fail(x, "plusieurs éléments racines")
            at := i
            el := __xp_open(x, out)
            if __load64(stack) == 0:
                root = el
            else:
                top := __rt_vec_at(stack, __load64(stack) - 1)
                __dyn_list_push(__load64(top + 8), el)
            if __load64(out + 8) == 0:
                if __load64(stack) > 100000:
                    __xp_fail(x, "imbrication trop profonde")
                fr := __alloc(24)
                __store64(fr, __load64(out + 16))
                __store64(fr + 8, __load64(out))
                __store64(fr + 16, at)
                __rt_list_push(stack, fr)
            continue
        st := i
        e := __xp_find(x, "<", i)
        if e < 0:
            e = sn
        if __load64(stack) == 0:
            k := st
            while k < e:
                if not __xp_space(__load8(p + k)):
                    __xp_fail_at(x, "texte hors de l'élément racine", k)
                k += 1
        else:
            __xp_decode_into(x, text, st, e, false)
            __store64(has, 1)
        __store64(x + 8, e)
    __xp_flush(x, stack, text, has)
    if __load64(stack) != 0:
        top := __rt_vec_at(stack, __load64(stack) - 1)
        __xp_fail_at(x, "balise <" + __as_str(__load64(top)) + "> non fermée", __load64(top + 16))
    if root == 0:
        __xp_fail(x, "document vide : aucun élément racine")
    return root

# ---- écriture des nombres (printf exact : %.Pg, %.PE, %.Df) ----

# Chiffres décimaux exacts de |x| (x fini non nul) : triplet [chiffres, nombre, exposant du premier]
func __of_digits(x: float) -> int:
    ab := __f2bits(x) & 9223372036854775807
    e := (ab >> 52) & 2047
    m := ab & 4503599627370495
    e2 := e - 1075
    if e == 0:
        e2 = -1074
    else:
        m = m | 4503599627370496
    res := __alloc_raw(24)
    __rt_exact_digits(m, e2, res)
    return res

func __of_sign(x: float) -> str:
    if __f2bits(x) < 0:
        return "-"
    return ""

func __of_exp(sb: int, ex: int, minDigits: int):
    if ex < 0:
        __rt_sb_byte(sb, 45)
        ex = 0 - ex
    else:
        __rt_sb_byte(sb, 43)
    s := __int_to_str(ex)
    k := __nat_blen(s)
    while k < minDigits:
        __rt_sb_byte(sb, 48)
        k += 1
    __rt_sb_add(sb, s)

func __of_strip_zeros(s: str) -> str:
    if __dyn_find_bytes(s, ".", 0) < 0:
        return s
    n := __nat_blen(s)
    while n > 0 and __load8(__nat_bp(s) + n - 1) == 48:
        n -= 1
    if n > 0 and __load8(__nat_bp(s) + n - 1) == 46:
        n -= 1
    return __nat_sub(s, 0, n)

# %.P g (glibc) ; upper : E/INF/NAN
func __of_fmt_g(x: float, prec: int, upper: bool) -> str:
    sign := __of_sign(x)
    if x != x:
        if upper:
            return sign + "NAN"
        return sign + "nan"
    if x == __bits2f(9218868437227405312) or x == __bits2f(-4503599627370496):
        if upper:
            return sign + "INF"
        return sign + "inf"
    P := prec
    if P == 0:
        P = 1
    if x == 0.0:
        return sign + "0"
    r := __of_digits(x)
    t := __rf_round(__load64(r), __load64(r + 8), __load64(r + 16), P)
    X := __load64(t + 16)
    sb := __rt_sb_new()
    __rt_sb_add(sb, sign)
    if X < -4 or X >= P:
        m := __rt_sb_new()
        i := 0
        while i < P:
            if i == 1:
                __rt_sb_byte(m, 46)
            __rt_sb_byte(m, 48 + __rf_digit(t, i))
            i += 1
        __rt_sb_add(sb, __of_strip_zeros(__rt_sb_str(m)))
        if upper:
            __rt_sb_byte(sb, 69)
        else:
            __rt_sb_byte(sb, 101)
        __of_exp(sb, X, 2)
        return __rt_sb_str(sb)
    m := __rt_sb_new()
    if X >= 0:
        i := 0
        while i <= X:
            __rt_sb_byte(m, 48 + __rf_digit(t, i))
            i += 1
        if P - 1 - X > 0:
            __rt_sb_byte(m, 46)
            while i < P:
                __rt_sb_byte(m, 48 + __rf_digit(t, i))
                i += 1
    else:
        __rt_sb_add(m, "0.")
        k := 0
        while k < 0 - X - 1:
            __rt_sb_byte(m, 48)
            k += 1
        i := 0
        while i < P:
            __rt_sb_byte(m, 48 + __rf_digit(t, i))
            i += 1
    __rt_sb_add(sb, __of_strip_zeros(__rt_sb_str(m)))
    return __rt_sb_str(sb)

# %.(P-1)E : P chiffres significatifs (x fini non nul)
func __of_fmt_e(x: float, P: int) -> str:
    r := __of_digits(x)
    t := __rf_round(__load64(r), __load64(r + 8), __load64(r + 16), P)
    sb := __rt_sb_new()
    __rt_sb_add(sb, __of_sign(x))
    i := 0
    while i < P:
        if i == 1:
            __rt_sb_byte(sb, 46)
        __rt_sb_byte(sb, 48 + __rf_digit(t, i))
        i += 1
    __rt_sb_byte(sb, 69)
    __of_exp(sb, __load64(t + 16), 2)
    return __rt_sb_str(sb)

# %.Df (x fini)
func __of_fmt_f(x: float, D: int) -> str:
    sb := __rt_sb_new()
    __rt_sb_add(sb, __of_sign(x))
    t := 0
    fx := -1
    zero := x == 0.0
    if not zero:
        r := __of_digits(x)
        d := __load64(r)
        nd := __load64(r + 8)
        X := __load64(r + 16)
        keep := X + 1 + D
        if keep > 0:
            t = __rf_round(d, nd, X, keep)
            fx = __load64(t + 16)
        elif keep == 0:
            up := false
            f0 := __load8(d)
            if f0 > 5:
                up = true
            elif f0 == 5:
                j := 1
                while j < nd:
                    if __load8(d + j) != 0:
                        up = true
                    j += 1
            if up:
                one := __alloc_raw(8)
                __store8(one, 1)
                t = __alloc(24)
                __store64(t, one)
                __store64(t + 8, 1)
                __store64(t + 16, 0 - D)
                fx = 0 - D
            else:
                zero = true
        else:
            zero = true
    if zero or fx < 0:
        __rt_sb_byte(sb, 48)
    else:
        i := 0
        while i <= fx:
            __rt_sb_byte(sb, 48 + __rf_digit(t, i))
            i += 1
    if D > 0:
        __rt_sb_byte(sb, 46)
        k := 1
        while k <= D:
            idx := fx + k
            if zero or idx < 0:
                __rt_sb_byte(sb, 48)
            else:
                __rt_sb_byte(sb, 48 + __rf_digit(t, idx))
            k += 1
    return __rt_sb_str(sb)

func __of_roundtrips(s: str, x: float) -> bool:
    ok := false
    try:
        ok = __f2bits(__rt_str_to_float(s)) == __f2bits(x)
    catch e:
        ok = false
    return ok

func __of_finite(x: float) -> bool:
    return x == x and x != __bits2f(9218868437227405312) and x != __bits2f(-4503599627370496)

func __of_abs(x: float) -> float:
    if x < 0.0:
        return 0.0 - x
    return x

func __of_format_number(v: int) -> str:
    if __dyn_is(v, 1):
        return __int_to_str(__load64(v + 8))
    x := __dyn_fv(v)
    if x != x:
        return "NaN"
    if not __of_finite(x):
        if x > 0.0:
            return "INF"
        return "-INF"
    if x == 0.0:
        return "0"
    ax := __of_abs(x)
    sci := ax < 0.00001 or ax >= 1000000000000000.0
    r := ""
    prec := 1
    while prec <= 17:
        if sci:
            r = __of_fmt_e(x, prec)
        else:
            r = __of_fmt_g(x, prec, false)
        if __of_roundtrips(r, x):
            break
        prec += 1
    if not sci:
        if __dyn_find_bytes(r, "e", 0) >= 0 or __dyn_find_bytes(r, "E", 0) >= 0:
            dec := 0
            while dec <= 20:
                r = __of_fmt_f(x, dec)
                if __of_roundtrips(r, x):
                    break
                dec += 1
        return r
    e := __dyn_find_bytes(r, "E", 0)
    mant := __nat_sub(r, 0, e)
    ex := __nat_sub(r, e + 1, __nat_blen(r) - e - 1)
    if __dyn_find_bytes(mant, ".", 0) >= 0:
        mant = __of_strip_zeros(mant)
    sg := __nat_sub(ex, 0, 1)
    digits := __nat_sub(ex, 1, __nat_blen(ex) - 1)
    while __nat_blen(digits) > 2 and __load8(__nat_bp(digits)) == 48:
        digits = __nat_sub(digits, 1, __nat_blen(digits) - 1)
    return mant + "E" + sg + digits

func __nat__native_office__num_format(n: int, a: int) -> int:
    __of_arity("num_format", n, 1, 1)
    if not __dyn_is(a, 1) and not __dyn_is(a, 2):
        __of_tfail("num_format : nombre attendu (obtenu '" + __dyn_type_name(a) + "')")
    return __dyn_str(__of_format_number(a))

func __of_digit(c: int) -> bool:
    return c >= 48 and c <= 57

func __nat__native_office__num_parse(n: int, a: int) -> int:
    __of_arity("num_parse", n, 1, 1)
    if not __dyn_is_str(a):
        return 0
    raw := __dyn_sv(a)
    p := __nat_bp(raw)
    b := 0
    e := __nat_blen(raw)
    while b < e and __xp_space(__load8(p + b)):
        b += 1
    while e > b and __xp_space(__load8(p + e - 1)):
        e -= 1
    if b == e:
        return 0
    t := __nat_sub(raw, b, e - b)
    q := __nat_bp(t)
    tn := __nat_blen(t)
    i := 0
    if __load8(q) == 43 or __load8(q) == 45:
        i += 1
    digits := 0
    frac := 0
    isFloat := false
    while i < tn and __of_digit(__load8(q + i)):
        i += 1
        digits += 1
    if i < tn and __load8(q + i) == 46:
        isFloat = true
        i += 1
        while i < tn and __of_digit(__load8(q + i)):
            i += 1
            frac += 1
    if digits + frac == 0:
        return 0
    if i < tn and (__load8(q + i) == 101 or __load8(q + i) == 69):
        isFloat = true
        i += 1
        if i < tn and (__load8(q + i) == 43 or __load8(q + i) == 45):
            i += 1
        ed := 0
        while i < tn and __of_digit(__load8(q + i)):
            i += 1
            ed += 1
        if ed == 0:
            return 0
    if i != tn:
        return 0
    if not isFloat:
        neg := __load8(q) == 45
        s0 := 0
        if __load8(q) == 43 or __load8(q) == 45:
            s0 = 1
        while s0 < tn - 1 and __load8(q + s0) == 48:
            s0 += 1
        body := __nat_sub(t, s0, tn - s0)
        bl := __nat_blen(body)
        fits := bl < 19
        if bl == 19:
            lim := "9223372036854775807"
            if neg:
                lim = "9223372036854775808"
            k := 0
            fits = true
            while k < 19:
                x := __load8(__nat_bp(body) + k)
                y := __load8(__nat_bp(lim) + k)
                if x != y:
                    fits = x < y
                    break
                k += 1
        if fits:
            v := 0
            k := 0
            while k < bl:
                v = v * 10 - (__load8(__nat_bp(body) + k) - 48)
                k += 1
            if not neg:
                v = 0 - v
            return __dyn_int(v)
    d := __rt_str_to_float(t)
    if not __of_finite(d):
        return 0
    return __dyn_float(d)

func __nat__native_office__same(n: int, a: int, b: int) -> int:
    __of_arity("same", n, 2, 2)
    if a != 0 and b != 0 and __dyn_kind(a) >= 6 and __dyn_kind(b) >= 6:
        return __dyn_bool(a == b)
    return __dyn_bool(false)

# ---- sérialisation XML ----

func __of_scalar(sb: int, v: int, where: str):
    if __dyn_is(v, 1):
        __rt_sb_add(sb, __int_to_str(__load64(v + 8)))
        return
    if __dyn_is(v, 3):
        if __dyn_truthy(v):
            __rt_sb_add(sb, "true")
        else:
            __rt_sb_add(sb, "false")
        return
    if __dyn_is(v, 2):
        x := __dyn_fv(v)
        if __of_finite(x) and x == __rt_floor(x) and __of_abs(x) < 1000000000000000.0:
            __rt_sb_add(sb, __of_fmt_f(x, 0))
        else:
            r := __of_fmt_g(x, 15, false)
            if __of_finite(x) and not __of_roundtrips(r, x):
                r = __of_fmt_g(x, 17, false)
            __rt_sb_add(sb, r)
        return
    if __dyn_is_str(v):
        __rt_sb_add(sb, __dyn_sv(v))
        return
    __of_tfail("xml_serialize : " + where + " de type '" + __dyn_type_name(v) + "' non sérialisable")

func __of_key(d: int, k: str) -> int:
    return __dyn_dict_get_raw(d, __dyn_str(k))

func __of_xml_write(sb: int, node: int, depth: int):
    if depth > 4096:
        __of_vfail("xml_serialize : arbre trop profond ou cyclique")
    if __dyn_is_str(node):
        __of_xml_escape_into(sb, __dyn_sv(node), false)
        return
    if __dyn_is(node, 1) or __dyn_is(node, 2) or __dyn_is(node, 3):
        tmp := __rt_sb_new()
        __of_scalar(tmp, node, "texte")
        __of_xml_escape_into(sb, __rt_sb_str(tmp), false)
        return
    if node == 0:
        return
    if not __dyn_is(node, 9):
        __of_tfail("xml_serialize : nœud invalide de type '" + __dyn_type_name(node) + "'")
    raw := __of_key(node, "raw")
    tag := __of_key(node, "tag")
    if raw != 1 and tag == 1:
        if not __dyn_is_str(raw):
            __of_tfail("xml_serialize : 'raw' doit être une str")
        __rt_sb_add(sb, __dyn_sv(raw))
        return
    if tag == 1 or not __dyn_is_str(tag):
        __of_tfail("xml_serialize : élément sans 'tag' (str)")
    t := __dyn_sv(tag)
    __rt_sb_byte(sb, 60)
    __rt_sb_add(sb, t)
    attrs := __of_key(node, "attrs")
    if attrs != 1 and attrs != 0:
        if not __dyn_is(attrs, 9):
            __of_tfail("xml_serialize : 'attrs' doit être un dict")
        d := __dyn_dv(attrs)
        used := __load64(d + 8)
        e := 0
        while e < used:
            if __load64(__load64(d + 40) + 8 * e) >= 0:
                k := __load64(__load64(d + 24) + 8 * e)
                v := __load64(__load64(d + 32) + 8 * e)
                if v != 0:
                    if not __dyn_is_str(k):
                        __of_tfail("xml_serialize : nom d'attribut non str")
                    __rt_sb_byte(sb, 32)
                    __rt_sb_add(sb, __dyn_sv(k))
                    __rt_sb_add(sb, "=\"")
                    tmp := __rt_sb_new()
                    __of_scalar(tmp, v, "valeur d'attribut")
                    __of_xml_escape_into(sb, __rt_sb_str(tmp), true)
                    __rt_sb_byte(sb, 34)
            e += 1
    children := __of_key(node, "children")
    empty := true
    if children != 1 and children != 0:
        if not __of_is_seq(children):
            __of_tfail("xml_serialize : 'children' doit être une liste")
        m := __of_seq_len(children)
        i := 0
        while i < m:
            c := __of_seq_at(children, i)
            if c != 0 and not (__dyn_is_str(c) and __nat_blen(__dyn_sv(c)) == 0):
                empty = false
                break
            i += 1
        if not empty:
            __rt_sb_byte(sb, 62)
            i = 0
            while i < m:
                __of_xml_write(sb, __of_seq_at(children, i), depth + 1)
                i += 1
            __rt_sb_add(sb, "</")
            __rt_sb_add(sb, t)
            __rt_sb_byte(sb, 62)
    if empty:
        __rt_sb_add(sb, "/>")

func __nat__native_office__xml_serialize(n: int, a: int, b: int) -> int:
    __of_arity("xml_serialize", n, 1, 2)
    decl := n > 1 and __dyn_truthy(b)
    sb := __rt_sb_new()
    if decl:
        __rt_sb_add(sb, "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n")
    __of_xml_write(sb, a, 0)
    return __dyn_str(__rt_sb_str(sb))

# ---- base64 / hex ----

func __nat__native_office__base64_encode(n: int, a: int) -> int:
    __of_arity("base64_encode", n, 1, 1)
    d := ""
    if __dyn_is_str(a):
        d = __dyn_sv(a)
    else:
        d = __of_bytes("base64_encode", a, "data")
    al := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
    ap := __nat_bp(al)
    p := __nat_bp(d)
    m := __nat_blen(d)
    sb := __rt_sb_new()
    i := 0
    while i + 2 < m:
        v := (__load8(p + i) << 16) | (__load8(p + i + 1) << 8) | __load8(p + i + 2)
        __rt_sb_byte(sb, __load8(ap + (v >> 18)))
        __rt_sb_byte(sb, __load8(ap + ((v >> 12) & 63)))
        __rt_sb_byte(sb, __load8(ap + ((v >> 6) & 63)))
        __rt_sb_byte(sb, __load8(ap + (v & 63)))
        i += 3
    if i + 1 == m:
        v := __load8(p + i) << 16
        __rt_sb_byte(sb, __load8(ap + (v >> 18)))
        __rt_sb_byte(sb, __load8(ap + ((v >> 12) & 63)))
        __rt_sb_add(sb, "==")
    elif i + 2 == m:
        v := (__load8(p + i) << 16) | (__load8(p + i + 1) << 8)
        __rt_sb_byte(sb, __load8(ap + (v >> 18)))
        __rt_sb_byte(sb, __load8(ap + ((v >> 12) & 63)))
        __rt_sb_byte(sb, __load8(ap + ((v >> 6) & 63)))
        __rt_sb_byte(sb, 61)
    return __dyn_str(__rt_sb_str(sb))

func __nat__native_office__base64_decode(n: int, a: int) -> int:
    __of_arity("base64_decode", n, 1, 1)
    s := __of_str("base64_decode", a, "text")
    p := __nat_bp(s)
    m := __nat_blen(s)
    sb := __rt_sb_new()
    acc := 0
    bits := 0
    pad := false
    i := 0
    while i < m:
        c := __load8(p + i)
        v := -1
        if c >= 65 and c <= 90:
            v = c - 65
        elif c >= 97 and c <= 122:
            v = c - 71
        elif c >= 48 and c <= 57:
            v = c + 4
        elif c == 43 or c == 45:
            v = 62
        elif c == 47 or c == 95:
            v = 63
        elif c == 61:
            pad = true
            i += 1
            continue
        elif c == 32 or c == 10 or c == 13 or c == 9:
            i += 1
            continue
        else:
            __of_vfail("base64_decode : caractère invalide à l'indice " + __int_to_str(i))
        if pad:
            __of_vfail("base64_decode : données après le remplissage '='")
        acc = ((acc << 6) | v) & 4294967295
        bits += 6
        if bits >= 8:
            bits -= 8
            __rt_sb_byte(sb, (acc >> bits) & 255)
        i += 1
    return __of_sb_list(sb)

func __nat__native_office__hex_encode(n: int, a: int, b: int) -> int:
    __of_arity("hex_encode", n, 1, 2)
    d := __of_bytes("hex_encode", a, "data")
    upper := n > 1 and __dyn_truthy(b)
    hx := "0123456789abcdef"
    if upper:
        hx = "0123456789ABCDEF"
    sb := __rt_sb_new()
    i := 0
    while i < __nat_blen(d):
        x := __load8(__nat_bp(d) + i)
        __rt_sb_byte(sb, __load8(__nat_bp(hx) + (x >> 4)))
        __rt_sb_byte(sb, __load8(__nat_bp(hx) + (x & 15)))
        i += 1
    return __dyn_str(__rt_sb_str(sb))

func __nat__native_office__hex_decode(n: int, a: int) -> int:
    __of_arity("hex_decode", n, 1, 1)
    s := __of_str("hex_decode", a, "text")
    p := __nat_bp(s)
    sb := __rt_sb_new()
    hi := -1
    i := 0
    while i < __nat_blen(s):
        c := __load8(p + i)
        v := -1
        if c >= 48 and c <= 57:
            v = c - 48
        elif c >= 97 and c <= 102:
            v = c - 87
        elif c >= 65 and c <= 70:
            v = c - 55
        elif c == 32 or c == 10 or c == 13 or c == 9 or c == 12 or c == 0:
            i += 1
            continue
        else:
            __of_vfail("hex_decode : caractère invalide à l'indice " + __int_to_str(i))
        if hi < 0:
            hi = v
        else:
            __rt_sb_byte(sb, hi * 16 + v)
            hi = -1
        i += 1
    if hi >= 0:
        __rt_sb_byte(sb, hi * 16)
    return __of_sb_list(sb)

# ---- accès XML rapides ----

func __of_tag(v: int) -> int:
    if not __dyn_is(v, 9):
        return 0
    t := __of_key(v, "tag")
    if t == 1 or not __dyn_is_str(t):
        return 0
    return t

func __of_local(s: str) -> str:
    p := __dyn_find_bytes(s, ":", 0)
    if p < 0:
        return s
    return __nat_sub(s, p + 1, __nat_blen(s) - p - 1)

func __of_tag_matches(tag: str, name: int) -> bool:
    if name == 0:
        return true
    nm := __dyn_sv(name)
    if __rt_str_eq(nm, "*") or __rt_str_eq(tag, nm):
        return true
    return __rt_str_eq(__of_local(tag), __of_local(nm))

func __of_children(node: int) -> int:
    if not __dyn_is(node, 9):
        return 0
    c := __of_key(node, "children")
    if c == 1 or not __of_is_seq(c):
        return 0
    return c

func __nat__native_office__xml_children(n: int, a: int, b: int) -> int:
    __of_arity("xml_children", n, 1, 2)
    name := 0
    if n > 1 and b != 0:
        __of_str("xml_children", b, "name")
        name = b
    out := __dyn_list_new(0)
    items := __of_children(a)
    if items == 0:
        return out
    i := 0
    while i < __of_seq_len(items):
        c := __of_seq_at(items, i)
        t := __of_tag(c)
        if t != 0 and __of_tag_matches(__dyn_sv(t), name):
            __dyn_list_push(out, c)
        i += 1
    return out

func __nat__native_office__xml_first(n: int, a: int, b: int) -> int:
    __of_arity("xml_first", n, 2, 2)
    if a == 0:
        return 0
    name := 0
    if b != 0:
        __of_str("xml_first", b, "name")
        name = b
    items := __of_children(a)
    if items == 0:
        return 0
    i := 0
    while i < __of_seq_len(items):
        c := __of_seq_at(items, i)
        t := __of_tag(c)
        if t != 0 and __of_tag_matches(__dyn_sv(t), name):
            return c
        i += 1
    return 0

func __nat__native_office__xml_attr(n: int, a: int, b: int, c: int) -> int:
    __of_arity("xml_attr", n, 2, 3)
    fallback := 0
    if n > 2:
        fallback = c
    if not __dyn_is(a, 9):
        return fallback
    name := __of_str("xml_attr", b, "name")
    attrs := __of_key(a, "attrs")
    if attrs == 1 or not __dyn_is(attrs, 9):
        return fallback
    lp := __of_local(name)
    d := __dyn_dv(attrs)
    used := __load64(d + 8)
    found := 1
    e := 0
    while e < used:
        if __load64(__load64(d + 40) + 8 * e) >= 0:
            k := __load64(__load64(d + 24) + 8 * e)
            if __dyn_is_str(k):
                ks := __dyn_sv(k)
                if __rt_str_eq(ks, name):
                    found = __load64(__load64(d + 32) + 8 * e)
                    break
                xmlns := __nat_blen(ks) >= 5 and __rt_str_eq(__nat_sub(ks, 0, 5), "xmlns")
                if found == 1 and not xmlns:
                    if __rt_str_eq(__of_local(ks), lp):
                        found = __load64(__load64(d + 32) + 8 * e)
        e += 1
    if found == 1 or found == 0:
        return fallback
    return found

func __of_gather(node: int, sb: int, depth: int):
    if depth > 4096:
        __of_vfail("xml_text : arbre trop profond")
    items := __of_children(node)
    if items == 0:
        return
    i := 0
    while i < __of_seq_len(items):
        c := __of_seq_at(items, i)
        if __dyn_is_str(c):
            __rt_sb_add(sb, __dyn_sv(c))
        elif __dyn_is(c, 9):
            __of_gather(c, sb, depth + 1)
        i += 1

func __nat__native_office__xml_text(n: int, a: int) -> int:
    __of_arity("xml_text", n, 1, 1)
    if a == 0:
        return __dyn_str("")
    if __dyn_is_str(a):
        return a
    sb := __rt_sb_new()
    __of_gather(a, sb, 0)
    return __dyn_str(__rt_sb_str(sb))

func __of_collect(node: int, name: int, out: int, firstOnly: bool, depth: int):
    if depth > 4096:
        __of_vfail("xml_find_all : arbre trop profond")
    items := __of_children(node)
    if items == 0:
        return
    i := 0
    while i < __of_seq_len(items):
        c := __of_seq_at(items, i)
        t := __of_tag(c)
        if t != 0:
            if __of_tag_matches(__dyn_sv(t), name):
                __dyn_list_push(out, c)
                if firstOnly:
                    return
            __of_collect(c, name, out, firstOnly, depth + 1)
            if firstOnly and __dyn_list_len(out) > 0:
                return
        i += 1

func __nat__native_office__xml_find_all(n: int, a: int, b: int, c: int) -> int:
    __of_arity("xml_find_all", n, 2, 3)
    out := __dyn_list_new(0)
    if a == 0:
        return out
    name := 0
    if b != 0:
        __of_str("xml_find_all", b, "name")
        name = b
    firstOnly := n > 2 and __dyn_truthy(c)
    __of_collect(a, name, out, firstOnly, 0)
    if firstOnly:
        if __dyn_list_len(out) == 0:
            return 0
        return __dyn_list_at(out, 0)
    return out

func __of_atoll(s: str) -> int:
    p := __nat_bp(s)
    n := __nat_blen(s)
    i := 0
    while i < n and (__xp_space(__load8(p + i)) or __load8(p + i) == 11 or __load8(p + i) == 12):
        i += 1
    neg := false
    if i < n and (__load8(p + i) == 43 or __load8(p + i) == 45):
        neg = __load8(p + i) == 45
        i += 1
    v := 0
    while i < n and __of_digit(__load8(p + i)):
        if v < 922337203685477580:
            v = v * 10 + (__load8(p + i) - 48)
        i += 1
    if neg:
        return 0 - v
    return v

func __of_odf(node: int, sb: int, depth: int):
    if depth > 4096:
        __of_vfail("odf_text : arbre trop profond")
    items := __of_children(node)
    if items == 0:
        return
    i := 0
    while i < __of_seq_len(items):
        c := __of_seq_at(items, i)
        i += 1
        if __dyn_is_str(c):
            t := __dyn_sv(c)
            prevSpace := false
            k := 0
            while k < __nat_blen(t):
                ch := __load8(__nat_bp(t) + k)
                if __xp_space(ch):
                    if not prevSpace:
                        __rt_sb_byte(sb, 32)
                    prevSpace = true
                else:
                    __rt_sb_byte(sb, ch)
                    prevSpace = false
                k += 1
            continue
        tg := __of_tag(c)
        if tg == 0:
            continue
        tag := __dyn_sv(tg)
        q := __dyn_find_bytes(tag, ":", 0)
        pf := ""
        ln := tag
        if q >= 0:
            pf = __nat_sub(tag, 0, q)
            ln = __nat_sub(tag, q + 1, __nat_blen(tag) - q - 1)
        if __rt_str_eq(pf, "text") and __rt_str_eq(ln, "s"):
            cnt := 1
            attrs := __of_key(c, "attrs")
            if attrs != 1 and __dyn_is(attrs, 9):
                cv := __of_key(attrs, "text:c")
                if cv != 1 and __dyn_is_str(cv):
                    cnt = __of_atoll(__dyn_sv(cv))
                    if cnt < 1:
                        cnt = 1
            if cnt > 100000:
                cnt = 100000
            k := 0
            while k < cnt:
                __rt_sb_byte(sb, 32)
                k += 1
        elif __rt_str_eq(ln, "tab"):
            __rt_sb_byte(sb, 9)
        elif __rt_str_eq(ln, "line-break"):
            __rt_sb_byte(sb, 10)
        elif __rt_str_eq(ln, "note") or __rt_str_eq(ln, "annotation") or __rt_str_eq(ln, "bookmark") or __rt_str_eq(ln, "bookmark-start") or __rt_str_eq(ln, "bookmark-end") or __rt_str_eq(ln, "soft-page-break") or __rt_str_eq(ln, "tracked-changes") or __rt_str_eq(ln, "sequence-decls") or __rt_str_eq(pf, "draw") or __rt_str_eq(pf, "svg"):
            continue
        else:
            __of_odf(c, sb, depth + 1)

func __nat__native_office__odf_text(n: int, a: int) -> int:
    __of_arity("odf_text", n, 1, 1)
    sb := __rt_sb_new()
    if a != 0:
        __of_odf(a, sb, 0)
    return __dyn_str(__rt_sb_str(sb))

# ---- PDF : analyse lexicale ----

func __pd_ws(c: int) -> bool:
    return c == 0 or c == 9 or c == 10 or c == 12 or c == 13 or c == 32

func __pd_delim(c: int) -> bool:
    return c == 40 or c == 41 or c == 60 or c == 62 or c == 91 or c == 93 or c == 123 or c == 125 or c == 47 or c == 37

func __pd_xdigit(c: int) -> bool:
    return (c >= 48 and c <= 57) or (c >= 97 and c <= 102) or (c >= 65 and c <= 70)

func __pd_xval(c: int) -> int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    return c - 55

func __pd_valid_utf8(s: str) -> bool:
    p := __nat_bp(s)
    n := __nat_blen(s)
    i := 0
    while i < n:
        c := __load8(p + i)
        k := -1
        if c < 128:
            k = 0
        elif c >= 194 and c <= 223:
            k = 1
        elif c >= 224 and c <= 239:
            k = 2
        elif c >= 240 and c <= 244:
            k = 3
        if k < 0:
            return false
        if k > 0 and i + k >= n:
            return false
        j := 1
        while j <= k:
            if (__load8(p + i + j) & 192) != 128:
                return false
            j += 1
        i += k + 1
    return true

# Lexeur : [0] données [8] i [16] fin [24] base
func __pd_tok(lx: int, kind: str, v: int) -> int:
    t := __dyn_list_new(0)
    __dyn_list_push(t, __dyn_str(kind))
    __dyn_list_push(t, v)
    __dyn_list_push(t, __dyn_int(__load64(lx + 8) + __load64(lx + 24)))
    return t

func __pd_c(lx: int, k: int) -> int:
    return __load8(__load64(lx) + k)

func __pd_skip_ws(lx: int):
    i := __load64(lx + 8)
    e := __load64(lx + 16)
    while i < e:
        c := __pd_c(lx, i)
        if __pd_ws(c):
            i += 1
            continue
        if c == 37:
            while i < e and __pd_c(lx, i) != 10 and __pd_c(lx, i) != 13:
                i += 1
            continue
        break
    __store64(lx + 8, i)

func __pd_number(lx: int, st: int) -> int:
    i := __load64(lx + 8)
    isFloat := false
    k := st
    while k < i:
        if __pd_c(lx, k) == 46:
            isFloat = true
        k += 1
    k = st
    neg := false
    while k < i and (__pd_c(lx, k) == 43 or __pd_c(lx, k) == 45):
        if __pd_c(lx, k) == 45:
            neg = not neg
        k += 1
    body := __rt_sb_new()
    dot := false
    nd := 0
    while k < i:
        c := __pd_c(lx, k)
        if c >= 48 and c <= 57:
            __rt_sb_byte(body, c)
            nd += 1
        elif c == 46 and not dot:
            __rt_sb_byte(body, c)
            dot = true
        else:
            break
        k += 1
    if nd == 0:
        return __dyn_int(0)
    bs := __rt_sb_str(body)
    if not isFloat:
        v := 0
        over := false
        j := 0
        while j < __nat_blen(bs):
            dg := __load8(__nat_bp(bs) + j) - 48
            if v > (9223372036854775807 - dg) // 10:
                over = true
            else:
                v = v * 10 + dg
            j += 1
        if over:
            v = 9223372036854775807
        if neg:
            v = 0 - v
        return __dyn_int(v)
    x := __rt_str_to_float(bs)
    if neg:
        x = 0.0 - x
    return __dyn_float(x)

func __pd_literal(lx: int) -> int:
    sb := __rt_sb_new()
    depth := 1
    i := __load64(lx + 8)
    e := __load64(lx + 16)
    while i < e:
        c := __pd_c(lx, i)
        i += 1
        if c == 92:
            if i >= e:
                break
            x := __pd_c(lx, i)
            i += 1
            if x == 110:
                __rt_sb_byte(sb, 10)
            elif x == 114:
                __rt_sb_byte(sb, 13)
            elif x == 116:
                __rt_sb_byte(sb, 9)
            elif x == 98:
                __rt_sb_byte(sb, 8)
            elif x == 102:
                __rt_sb_byte(sb, 12)
            elif x == 40 or x == 41 or x == 92:
                __rt_sb_byte(sb, x)
            elif x == 13:
                if i < e and __pd_c(lx, i) == 10:
                    i += 1
            elif x == 10:
                i = i
            elif x >= 48 and x <= 55:
                v := x - 48
                k := 0
                while k < 2 and i < e and __pd_c(lx, i) >= 48 and __pd_c(lx, i) <= 55:
                    v = v * 8 + (__pd_c(lx, i) - 48)
                    i += 1
                    k += 1
                __rt_sb_byte(sb, v & 255)
            else:
                __rt_sb_byte(sb, x)
            continue
        if c == 40:
            depth += 1
        elif c == 41:
            depth -= 1
            if depth == 0:
                break
        if c == 13:
            __rt_sb_byte(sb, 10)
            if i < e and __pd_c(lx, i) == 10:
                i += 1
            continue
        __rt_sb_byte(sb, c)
    __store64(lx + 8, i)
    return sb

func __pd_hexstr(lx: int) -> int:
    sb := __rt_sb_new()
    hi := -1
    i := __load64(lx + 8)
    e := __load64(lx + 16)
    while i < e:
        c := __pd_c(lx, i)
        i += 1
        if c == 62:
            break
        if not __pd_xdigit(c):
            continue
        v := __pd_xval(c)
        if hi < 0:
            hi = v
        else:
            __rt_sb_byte(sb, hi * 16 + v)
            hi = -1
    if hi >= 0:
        __rt_sb_byte(sb, hi * 16)
    __store64(lx + 8, i)
    return sb

func __pd_name(lx: int) -> str:
    raw := __rt_sb_new()
    i := __load64(lx + 8)
    e := __load64(lx + 16)
    while i < e and not __pd_ws(__pd_c(lx, i)) and not __pd_delim(__pd_c(lx, i)):
        c := __pd_c(lx, i)
        i += 1
        if c == 35 and i + 1 < e and __pd_xdigit(__pd_c(lx, i)) and __pd_xdigit(__pd_c(lx, i + 1)):
            __rt_sb_byte(raw, __pd_xval(__pd_c(lx, i)) * 16 + __pd_xval(__pd_c(lx, i + 1)))
            i += 2
        else:
            __rt_sb_byte(raw, c)
    __store64(lx + 8, i)
    r := __rt_sb_str(raw)
    if __pd_valid_utf8(r):
        return r
    sb := __rt_sb_new()
    k := 0
    while k < __nat_blen(r):
        __nat_sb_cp(sb, __load8(__nat_bp(r) + k))
        k += 1
    return __rt_sb_str(sb)

func __pd_inline_image(lx: int) -> int:
    i := __load64(lx + 8)
    e := __load64(lx + 16)
    d := __load64(lx)
    if i < e and __pd_ws(__pd_c(lx, i)):
        i += 1
    st := i
    k := i
    while k + 1 < e:
        if __pd_c(lx, k) == 69 and __pd_c(lx, k + 1) == 73 and k > st and __pd_ws(__pd_c(lx, k - 1)) and (k + 2 >= e or __pd_ws(__pd_c(lx, k + 2)) or __pd_delim(__pd_c(lx, k + 2))):
            __store64(lx + 8, k + 2)
            return __of_blist(d + st, k - 1 - st)
        k += 1
    __store64(lx + 8, e)
    return __of_blist(d + st, e - st)

func __nat__native_office__pdf_tokens(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    if n < 1 or n > 5:
        __dyn_err("ArgumentError", "pdf_tokens(data, start, end, stop_obj, max)")
    if not __of_is_seq(a):
        __of_tfail("pdf_tokens : liste d'octets attendue")
    size := __of_seq_len(a)
    start := 0
    if n > 1:
        start = __of_pint("pdf_tokens", b)
    endv := size
    if n > 2 and c != 0:
        endv = __of_pint("pdf_tokens", c)
    stopObj := n > 3 and __dyn_truthy(d)
    maxTok := -1
    if n > 4 and e != 0:
        maxTok = __of_pint("pdf_tokens", e)
    if start < 0:
        start = 0
    if endv > size:
        endv = size
    if endv < start:
        endv = start
    m := endv - start
    buf := __alloc_raw(m + 8)
    k := start
    while k < endv:
        bv := __of_seq_at(a, k)
        x := 0
        if __dyn_is(bv, 1) or __dyn_is(bv, 5):
            x = __load64(bv + 8) & 255
        __store8(buf + k - start, x)
        k += 1
    lx := __alloc(32)
    __store64(lx, buf)
    __store64(lx + 16, m)
    __store64(lx + 24, start)
    out := __dyn_list_new(0)
    count := 0
    while true:
        if maxTok >= 0 and count >= maxTok:
            break
        __pd_skip_ws(lx)
        i := __load64(lx + 8)
        if i >= m:
            break
        st := i
        ch := __pd_c(lx, i)
        if ch == 47:
            __store64(lx + 8, i + 1)
            nm := __pd_name(lx)
            # position relevée avant la lecture du nom (ordre d'évaluation des arguments de la VM)
            after := __load64(lx + 8)
            __store64(lx + 8, i + 1)
            tk := __pd_tok(lx, "/", __dyn_str(nm))
            __store64(lx + 8, after)
            __dyn_list_push(out, tk)
        elif ch == 40:
            __store64(lx + 8, i + 1)
            sb := __pd_literal(lx)
            __dyn_list_push(out, __pd_tok(lx, "s", __of_sb_list(sb)))
        elif ch == 60:
            if i + 1 < m and __pd_c(lx, i + 1) == 60:
                __store64(lx + 8, i + 2)
                __dyn_list_push(out, __pd_tok(lx, "<<", 0))
            else:
                __store64(lx + 8, i + 1)
                sb := __pd_hexstr(lx)
                __dyn_list_push(out, __pd_tok(lx, "x", __of_sb_list(sb)))
        elif ch == 62:
            if i + 1 < m and __pd_c(lx, i + 1) == 62:
                __store64(lx + 8, i + 2)
                __dyn_list_push(out, __pd_tok(lx, ">>", 0))
            else:
                __store64(lx + 8, i + 1)
                continue
        elif ch == 91 or ch == 93 or ch == 123 or ch == 125:
            __store64(lx + 8, i + 1)
            __dyn_list_push(out, __pd_tok(lx, __nat_sub(__nat_make(buf + i, 1), 0, 1), 0))
        elif ch == 41:
            __store64(lx + 8, i + 1)
            continue
        elif (ch >= 48 and ch <= 57) or ch == 43 or ch == 45 or ch == 46:
            j := i
            while j < m and ((__pd_c(lx, j) >= 48 and __pd_c(lx, j) <= 57) or __pd_c(lx, j) == 46 or __pd_c(lx, j) == 45 or __pd_c(lx, j) == 43):
                j += 1
            __store64(lx + 8, j)
            __dyn_list_push(out, __pd_tok(lx, "n", __pd_number(lx, st)))
        else:
            j := i
            while j < m and not __pd_ws(__pd_c(lx, j)) and not __pd_delim(__pd_c(lx, j)):
                j += 1
            if j == st:
                __store64(lx + 8, j + 1)
                continue
            __store64(lx + 8, j)
            kw := __nat_make(buf + st, j - st)
            __dyn_list_push(out, __pd_tok(lx, "k", __dyn_str(kw)))
            count += 1
            if __rt_str_eq(kw, "ID"):
                img := __pd_inline_image(lx)
                __dyn_list_push(out, __pd_tok(lx, "i", img))
            if stopObj and (__rt_str_eq(kw, "endobj") or __rt_str_eq(kw, "stream")):
                break
            continue
        count += 1
    res := __dyn_list_new(0)
    __dyn_list_push(res, out)
    __dyn_list_push(res, __dyn_int(__load64(lx + 8) + start))
    return res

# ---- PDF : LZW, PNG ----

func __nat__native_office__lzw_decode(n: int, a: int, b: int) -> int:
    if n < 1 or n > 2:
        __dyn_err("ArgumentError", "lzw_decode(data, early_change)")
    d := __of_pbytes("lzw_decode", a)
    early := 1
    if n > 1:
        early = __of_pint("lzw_decode", b)
    p := __nat_bp(d)
    m := __nat_blen(d)
    # table : entrées (str d'octets) dans une liste native
    table := __rt_list_new(0)
    k := 0
    while k < 258:
        if k < 256:
            r := __rt_str_new(1)
            __store8(r + 8, k)
            __rt_list_push(table, r)
        else:
            __rt_list_push(table, __rt_str_new(0))
        k += 1
    out := __rt_sb_new()
    codeLen := 9
    buf := 0
    bits := 0
    pos := 0
    prev := -1
    while true:
        while bits < codeLen and pos < m:
            buf = ((buf << 8) | __load8(p + pos)) & 4294967295
            pos += 1
            bits += 8
        if bits < codeLen:
            break
        code := (buf >> (bits - codeLen)) & ((1 << codeLen) - 1)
        bits -= codeLen
        if code == 256:
            __store64(table, 258)
            codeLen = 9
            prev = -1
            continue
        if code == 257:
            break
        entry := 0
        if code < __load64(table):
            entry = __rt_vec_at(table, code)
            if prev >= 0:
                pe := __rt_vec_at(table, prev)
                ne := __rt_str_new(__load64(pe) + 1)
                __copy(ne + 8, pe + 8, __load64(pe))
                __store8(ne + 8 + __load64(pe), __load8(entry + 8))
                __rt_list_push(table, ne)
        elif prev >= 0:
            pe := __rt_vec_at(table, prev)
            ne := __rt_str_new(__load64(pe) + 1)
            __copy(ne + 8, pe + 8, __load64(pe))
            __store8(ne + 8 + __load64(pe), __load8(pe + 8))
            entry = ne
            __rt_list_push(table, ne)
        else:
            break
        __rt_sb_add(out, __as_str(entry))
        prev = code
        sz := __load64(table) + early
        if sz >= 2048:
            codeLen = 12
        elif sz >= 1024:
            codeLen = 11
        elif sz >= 512:
            codeLen = 10
        else:
            codeLen = 9
    return __of_sb_list(out)

func __pg_paeth(a: int, b: int, c: int) -> int:
    p := a + b - c
    pa := p - a
    if pa < 0:
        pa = 0 - pa
    pb := p - b
    if pb < 0:
        pb = 0 - pb
    pc := p - c
    if pc < 0:
        pc = 0 - pc
    if pa <= pb and pa <= pc:
        return a
    if pb <= pc:
        return b
    return c

# Défiltrage : renvoie le tampon des lignes ; used[0] = octets consommés
func __pg_unfilter(src: int, avail: int, used: int, w: int, h: int, bpp: int, bitsPP: int) -> int:
    stride := (w * bitsPP + 7) // 8
    out := __alloc_raw(stride * h + 8)
    __zero(out, stride * h + 8)
    prior := __alloc_raw(stride + 8)
    __zero(prior, stride + 8)
    u := 0
    y := 0
    while y < h:
        if u + 1 + stride > avail:
            __of_vfail("png : données d'image tronquées")
        ft := __load8(src + u)
        u += 1
        row := out + stride * y
        __copy(row, src + u, stride)
        u += stride
        x := 0
        while x < stride:
            a := 0
            c := 0
            if x >= bpp:
                a = __load8(row + x - bpp)
                c = __load8(prior + x - bpp)
            b := __load8(prior + x)
            v := __load8(row + x)
            if ft == 0:
                v = v
            elif ft == 1:
                v += a
            elif ft == 2:
                v += b
            elif ft == 3:
                v += (a + b) // 2
            elif ft == 4:
                v += __pg_paeth(a, b, c)
            else:
                __of_vfail("png : filtre de ligne inconnu")
            __store8(row + x, v & 255)
            x += 1
        __copy(prior, row, stride)
        y += 1
    __store64(used, u)
    return out

func __pg_be32(p: int) -> int:
    return (__load8(p) << 24) | (__load8(p + 1) << 16) | (__load8(p + 2) << 8) | __load8(p + 3)

func __pg_sample(row: int, x: int, s: int, depth: int, samples: int, bitsPP: int) -> int:
    if depth == 8:
        return __load8(row + x * samples + s)
    if depth == 16:
        return __load8(row + (x * samples + s) * 2)
    bitpos := x * bitsPP + s * depth
    return (__load8(row + bitpos // 8) >> (8 - depth - bitpos % 8)) & ((1 << depth) - 1)

func __pg_sample16(row: int, x: int, s: int, depth: int, samples: int, bitsPP: int) -> int:
    if depth == 16:
        return (__load8(row + (x * samples + s) * 2) << 8) | __load8(row + (x * samples + s) * 2 + 1)
    return __pg_sample(row, x, s, depth, samples, bitsPP)

func __nat__native_office__png_decode(n: int, a: int) -> int:
    if n != 1:
        __dyn_err("ArgumentError", "png_decode(data)")
    ds := __of_pbytes("png_decode", a)
    d := __nat_bp(ds)
    dn := __nat_blen(ds)
    if dn < 33 or __load8(d) != 137 or __load8(d + 1) != 80 or __load8(d + 2) != 78 or __load8(d + 3) != 71:
        __of_vfail("png : signature invalide")
    p := 8
    w := 0
    h := 0
    depth := 0
    ctype := 0
    interlace := 0
    idat := __rt_sb_new()
    plte := ""
    trns := ""
    while p + 8 <= dn:
        len := __pg_be32(d + p)
        typ := __nat_make(d + p + 4, 4)
        data := p + 8
        if data + len > dn:
            __of_vfail("png : bloc tronqué")
        if __rt_str_eq(typ, "IHDR"):
            w = __pg_be32(d + data)
            h = __pg_be32(d + data + 4)
            if w >= 2147483648:
                w = w - 4294967296
            if h >= 2147483648:
                h = h - 4294967296
            depth = __load8(d + data + 8)
            ctype = __load8(d + data + 9)
            interlace = __load8(d + data + 12)
        elif __rt_str_eq(typ, "PLTE"):
            plte = __nat_make(d + data, len)
        elif __rt_str_eq(typ, "tRNS"):
            trns = __nat_make(d + data, len)
        elif __rt_str_eq(typ, "IDAT"):
            __rt_sb_add(idat, __nat_make(d + data, len))
        elif __rt_str_eq(typ, "IEND"):
            break
        p = data + len + 4
    if w <= 0 or h <= 0 or w * h > 100000000:
        __of_vfail("png : dimensions invalides")
    samples := 0
    if ctype == 0 or ctype == 3:
        samples = 1
    elif ctype == 2:
        samples = 3
    elif ctype == 4:
        samples = 2
    elif ctype == 6:
        samples = 4
    if samples == 0:
        __of_vfail("png : type de couleur inconnu")
    bitsPP := samples * depth
    bpp := bitsPP // 8
    if bpp < 1:
        bpp = 1
    if __load64(idat) < 2:
        __of_vfail("png : données absentes")
    st := __if_run(__load64(idat + 16) + 2, __load64(idat) - 2, -1)
    rawsb := __load64(st + 40)
    raw := __load64(rawsb + 16)
    rawn := __load64(rawsb)
    stride := (w * bitsPP + 7) // 8
    used := __alloc_raw(8)
    full := 0
    if interlace == 0:
        full = __pg_unfilter(raw, rawn, used, w, h, bpp, bitsPP)
    else:
        full = __alloc_raw(stride * h + 8)
        __zero(full, stride * h + 8)
        sx := __of_table("0,4,0,2,0,1,0")
        sy := __of_table("0,0,4,0,2,0,1")
        dx := __of_table("8,8,4,4,2,2,1")
        dy := __of_table("8,8,8,4,4,2,2")
        off := 0
        ps := 0
        while ps < 7:
            pw := (w - __of_get(sx, ps) + __of_get(dx, ps) - 1) // __of_get(dx, ps)
            ph := (h - __of_get(sy, ps) + __of_get(dy, ps) - 1) // __of_get(dy, ps)
            if pw > 0 and ph > 0:
                sub := __pg_unfilter(raw + off, rawn - off, used, pw, ph, bpp, bitsPP)
                off += __load64(used)
                sstride := (pw * bitsPP + 7) // 8
                y := 0
                while y < ph:
                    x := 0
                    while x < pw:
                        X := __of_get(sx, ps) + x * __of_get(dx, ps)
                        Y := __of_get(sy, ps) + y * __of_get(dy, ps)
                        if bitsPP >= 8:
                            __copy(full + Y * stride + X * bpp, sub + y * sstride + x * bpp, bpp)
                        else:
                            v := (__load8(sub + y * sstride + (x * bitsPP) // 8) >> (8 - bitsPP - (x * bitsPP) % 8)) & ((1 << bitsPP) - 1)
                            q := full + Y * stride + (X * bitsPP) // 8
                            __store8(q, (__load8(q) | (v << (8 - bitsPP - (X * bitsPP) % 8))) & 255)
                        x += 1
                    y += 1
            ps += 1
    tn := __nat_blen(trns)
    tp := __nat_bp(trns)
    hasAlpha := ctype == 4 or ctype == 6 or tn > 0
    outCh := 1
    if ctype == 2 or ctype == 6 or ctype == 3:
        outCh = 3
    color := __alloc_raw(w * h * outCh + 8)
    __zero(color, w * h * outCh + 8)
    alpha := 0
    if hasAlpha:
        alpha = __alloc_raw(w * h + 8)
        __mem_fill(alpha, w * h, 255)
    pn := __nat_blen(plte)
    pp := __nat_bp(plte)
    y := 0
    while y < h:
        row := full + y * stride
        x := 0
        while x < w:
            pix := y * w + x
            if ctype == 3:
                idx := __pg_sample(row, x, 0, depth, samples, bitsPP)
                if idx * 3 + 2 < pn:
                    __store8(color + pix * 3, __load8(pp + idx * 3))
                    __store8(color + pix * 3 + 1, __load8(pp + idx * 3 + 1))
                    __store8(color + pix * 3 + 2, __load8(pp + idx * 3 + 2))
                if hasAlpha:
                    av := 255
                    if idx < tn:
                        av = __load8(tp + idx)
                    __store8(alpha + pix, av)
            elif ctype == 0 or ctype == 4:
                v := __pg_sample(row, x, 0, depth, samples, bitsPP)
                scaled := v
                if depth != 16 and depth != 8:
                    scaled = v * 255 // ((1 << depth) - 1)
                __store8(color + pix, scaled & 255)
                if ctype == 4:
                    __store8(alpha + pix, __pg_sample(row, x, 1, depth, samples, bitsPP) & 255)
                elif tn >= 2:
                    tv := (__load8(tp) << 8) | __load8(tp + 1)
                    if __pg_sample16(row, x, 0, depth, samples, bitsPP) == tv:
                        __store8(alpha + pix, 0)
            else:
                s := 0
                while s < 3:
                    __store8(color + pix * 3 + s, __pg_sample(row, x, s, depth, samples, bitsPP) & 255)
                    s += 1
                if ctype == 6:
                    __store8(alpha + pix, __pg_sample(row, x, 3, depth, samples, bitsPP) & 255)
                elif tn >= 6:
                    r := (__load8(tp) << 8) | __load8(tp + 1)
                    g := (__load8(tp + 2) << 8) | __load8(tp + 3)
                    bl := (__load8(tp + 4) << 8) | __load8(tp + 5)
                    if __pg_sample16(row, x, 0, depth, samples, bitsPP) == r and __pg_sample16(row, x, 1, depth, samples, bitsPP) == g and __pg_sample16(row, x, 2, depth, samples, bitsPP) == bl:
                        __store8(alpha + pix, 0)
            x += 1
        y += 1
    res := __dyn_dict_new()
    __nat_dict_put(res, "width", __dyn_int(w))
    __nat_dict_put(res, "height", __dyn_int(h))
    __nat_dict_put(res, "channels", __dyn_int(outCh))
    __nat_dict_put(res, "bit_depth", __dyn_int(depth))
    __nat_dict_put(res, "color", __of_blist(color, w * h * outCh))
    if hasAlpha:
        __nat_dict_put(res, "alpha", __of_blist(alpha, w * h))
    else:
        __nat_dict_put(res, "alpha", 0)
    return res

# Chiffrement des PDF protégés : non fourni par le compilateur natif.
func __of_crypto_missing(fn: str):
    __dyn_err("NotImplementedError", "office." + fn + " : PDF chiffrés non pris en charge par le compilateur natif (utiliser alexc run)")

func __nat__native_office__rc4(n: int, a: int, b: int) -> int:
    __of_crypto_missing("rc4")
    return 0

# MD5 (identifiant de document des PDF écrits, comme la VM)
func __of_md5(inp: str) -> int:
    K := __of_table("3614090360,3905402710,606105819,3250441966,4118548399,1200080426,2821735955,4249261313,1770035416,2336552879,4294925233,2304563134,1804603682,4254626195,2792965006,1236535329,4129170786,3225465664,643717713,3921069994,3593408605,38016083,3634488961,3889429448,568446438,3275163606,4107603335,1163531501,2850285829,4243563512,1735328473,2368359562,4294588738,2272392833,1839030562,4259657740,2763975236,1272893353,4139469664,3200236656,681279174,3936430074,3572445317,76029189,3654602809,3873151461,530742520,3299628645,4096336452,1126891415,2878612391,4237533241,1700485571,2399980690,4293915773,2240044497,1873313359,4264355552,2734768916,1309151649,4149444226,3174756917,718787259,3951481745")
    R := __of_table("7,12,17,22,7,12,17,22,7,12,17,22,7,12,17,22,5,9,14,20,5,9,14,20,5,9,14,20,5,9,14,20,4,11,16,23,4,11,16,23,4,11,16,23,4,11,16,23,6,10,15,21,6,10,15,21,6,10,15,21,6,10,15,21")
    n := __nat_blen(inp)
    total := (n + 8) // 64 * 64 + 64
    msg := __alloc_raw(total + 8)
    __zero(msg, total + 8)
    __copy(msg, __nat_bp(inp), n)
    __store8(msg + n, 128)
    bits := n * 8
    k := 0
    while k < 8:
        __store8(msg + total - 8 + k, (bits >> (8 * k)) & 255)
        k += 1
    M := 4294967295
    h0 := 1732584193
    h1 := 4023233417
    h2 := 2562383102
    h3 := 271733878
    W := __of_arr(16)
    off := 0
    while off < total:
        k = 0
        while k < 16:
            q := msg + off + 4 * k
            __of_set(W, k, __load8(q) | (__load8(q + 1) << 8) | (__load8(q + 2) << 16) | (__load8(q + 3) << 24))
            k += 1
        A := h0
        B := h1
        C := h2
        D := h3
        k = 0
        while k < 64:
            F := 0
            g := 0
            if k < 16:
                F = (B & C) | ((B ^ M) & D)
                g = k
            elif k < 32:
                F = (D & B) | ((D ^ M) & C)
                g = (5 * k + 1) % 16
            elif k < 48:
                F = B ^ C ^ D
                g = (3 * k + 5) % 16
            else:
                F = C ^ (B | (D ^ M))
                g = (7 * k) % 16
            F = (F + A + __of_get(K, k) + __of_get(W, g)) & M
            A = D
            D = C
            C = B
            r := __of_get(R, k)
            B = (B + (((F << r) | (F >> (32 - r))) & M)) & M
            k += 1
        h0 = (h0 + A) & M
        h1 = (h1 + B) & M
        h2 = (h2 + C) & M
        h3 = (h3 + D) & M
        off += 64
    out := __alloc_raw(24)
    hs := __of_arr(4)
    __of_set(hs, 0, h0)
    __of_set(hs, 1, h1)
    __of_set(hs, 2, h2)
    __of_set(hs, 3, h3)
    k = 0
    while k < 4:
        b := 0
        while b < 4:
            __store8(out + 4 * k + b, (__of_get(hs, k) >> (8 * b)) & 255)
            b += 1
        k += 1
    return __of_blist(out, 16)

func __nat__native_office__md5(n: int, a: int) -> int:
    if n != 1:
        __dyn_err("ArgumentError", "md5(data)")
    return __of_md5(__of_pbytes("md5", a))

func __nat__native_office__aes_cbc_decrypt(n: int, a: int, b: int, c: int) -> int:
    __of_crypto_missing("aes_cbc_decrypt")
    return 0

func __nat__native_office__aes_cbc_encrypt(n: int, a: int, b: int, c: int) -> int:
    __of_crypto_missing("aes_cbc_encrypt")
    return 0

func __nat__native_office__sha2(n: int, a: int, b: int) -> int:
    __of_crypto_missing("sha2")
    return 0
