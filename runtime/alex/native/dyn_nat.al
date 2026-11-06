

# ---- Arguments des natives -------------------------------------------------------------------------------------

func __nat_exact(fn: str, n: int, k: int):
    if n != k:
        __dyn_err("ArgumentError", "'" + fn + "' attend exactement " + __int_to_str(k) + " argument(s), obtenu " +
                  __int_to_str(n))

func __nat_between(fn: str, n: int, lo: int, hi: int):
    if n < lo or n > hi:
        __dyn_err("ArgumentError", "'" + fn + "' attend entre " + __int_to_str(lo) + " et " + __int_to_str(hi) +
                  " argument(s), obtenu " + __int_to_str(n))

# « exactement » si lo == hi, « entre » sinon (collections, os).
func __nat_range(fn: str, n: int, lo: int, hi: int):
    if lo == hi:
        __nat_exact(fn, n, lo)
    else:
        __nat_between(fn, n, lo, hi)

func __nat_str(fn: str, v: int, label: str) -> str:
    if not __dyn_is_str(v):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être une str (obtenu '" + __dyn_type_name(v) + "')")
    return __dyn_sv(v)

func __nat_int(fn: str, v: int, label: str) -> int:
    if not __dyn_is(v, 1):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un int (obtenu '" + __dyn_type_name(v) + "')")
    return __dyn_iv(v)

# str sans octet NUL (chemins, noms de variables d'environnement).
func __nat_cstr(fn: str, v: int, label: str) -> str:
    s := __nat_str(fn, v, label)
    p := __str_addr(s)
    n := __load64(p)
    i := 0
    while i < n:
        if __load8(p + 8 + i) == 0:
            __dyn_err("ArgumentError", "'" + fn + "' : " + label + " ne doit pas contenir de caractère NUL")
        i += 1
    return s

func __nat_number(fn: str, v: int, label: str) -> float:
    if __dyn_is(v, 1):
        return __i2f(__dyn_iv(v))
    if __dyn_is(v, 2):
        return __dyn_fv(v)
    __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un nombre (obtenu '" + __dyn_type_name(v) + "')")
    return 0.0

func __nat_blen(s: str) -> int:
    return __load64(__str_addr(s))

func __nat_bp(s: str) -> int:
    return __str_addr(s) + 8

func __nat_make(p: int, n: int) -> str:
    r := __rt_str_new(n)
    __copy(r + 8, p, n)
    return __as_str(r)

func __nat_sub(s: str, a: int, n: int) -> str:
    return __nat_make(__nat_bp(s) + a, n)

func __nat_none() -> int:
    return 0

# Points de code d'une chaîne (liste native) : même décodeur que la VM (octet de tête invalide ou suite
# tronquée -> U+FFFD).
func __nat_decode(s: str) -> int:
    p := __nat_bp(s)
    n := __nat_blen(s)
    out := __rt_list_new(0)
    i := 0
    while i < n:
        b0 := __load8(p + i)
        extra := 0
        cp := b0
        if b0 < 128:
            extra = 0
        elif (b0 & 224) == 192:
            extra = 1
            cp = b0 & 31
        elif (b0 & 240) == 224:
            extra = 2
            cp = b0 & 15
        elif (b0 & 248) == 240:
            extra = 3
            cp = b0 & 7
        else:
            __rt_list_push(out, 65533)
            i += 1
            continue
        i += 1
        ok := true
        k := 0
        while k < extra:
            if i >= n or (__load8(p + i) & 192) != 128:
                ok = false
                break
            cp = (cp << 6) | (__load8(p + i) & 63)
            i += 1
            k += 1
        if ok:
            __rt_list_push(out, cp)
        else:
            __rt_list_push(out, 65533)
    return out

# Nombre de points de code (même décodeur que __nat_decode, sans allocation).
func __nat_cp_count(s: str) -> int:
    p := __nat_bp(s)
    n := __nat_blen(s)
    k := 0
    i := 0
    while i < n:
        b0 := __load8(p + i)
        i += 1
        k += 1
        extra := 0
        if b0 < 128:
            continue
        elif (b0 & 224) == 192:
            extra = 1
        elif (b0 & 240) == 224:
            extra = 2
        elif (b0 & 248) == 240:
            extra = 3
        else:
            continue
        j := 0
        while j < extra and i < n and (__load8(p + i) & 192) == 128:
            i += 1
            j += 1
    return k

func __nat_sb_cp(sb: int, cp: int):
    if cp < 128:
        __rt_sb_byte(sb, cp)
    elif cp < 2048:
        __rt_sb_byte(sb, 192 | (cp >> 6))
        __rt_sb_byte(sb, 128 | (cp & 63))
    elif cp < 65536:
        __rt_sb_byte(sb, 224 | (cp >> 12))
        __rt_sb_byte(sb, 128 | ((cp >> 6) & 63))
        __rt_sb_byte(sb, 128 | (cp & 63))
    else:
        __rt_sb_byte(sb, 240 | (cp >> 18))
        __rt_sb_byte(sb, 128 | ((cp >> 12) & 63))
        __rt_sb_byte(sb, 128 | ((cp >> 6) & 63))
        __rt_sb_byte(sb, 128 | (cp & 63))

# Chaîne des points de code cps[a..b[ (liste native).
func __nat_encode(cps: int, a: int, b: int) -> str:
    sb := __rt_sb_new()
    d := __load64(cps + 16)
    i := a
    while i < b:
        __nat_sb_cp(sb, __load64(d + 8 * i))
        i += 1
    return __rt_sb_str(sb)

func __nat_is_ws(c: int) -> bool:
    return c == 32 or c == 9 or c == 10 or c == 13

func __nat_upper_b(c: int) -> int:
    if c >= 97 and c <= 122:
        return c - 32
    return c

func __nat_lower_b(c: int) -> int:
    if c >= 65 and c <= 90:
        return c + 32
    return c

# Liste de str (liste native de chaînes natives) -> valeur list.
func __nat_str_list(l: int) -> int:
    out := __dyn_list_new(0)
    n := __load64(l)
    d := __load64(l + 16)
    i := 0
    while i < n:
        __dyn_list_push(out, __dyn_str(__as_str(__load64(d + 8 * i))))
        i += 1
    return out

func __nat_dict_put(d: int, k: str, v: int):
    __rt_dict_set(__dyn_dv(d), __dyn_str(k), v, 3)

# ---- _native_core ------------------------------------------------------------------------------------------------

func __nat__native_core__type(n: int, a: int) -> int:
    __nat_exact("type", n, 1)
    return __dyn_str(__dyn_type_name(a))

func __nat__native_core__len(n: int, v: int) -> int:
    __nat_exact("len", n, 1)
    k := __dyn_kind(v)
    if k == 6:
        return __dyn_int(__nat_cp_count(__dyn_sv(v)))
    if k == 7:
        return __dyn_int(__dyn_list_len(v))
    if k == 8:
        return __dyn_int(__load64(v + 8))
    if k == 9:
        return __dyn_int(__dyn_dict_len(v))
    __dyn_err("TypeError", "'" + __dyn_type_name(v) + "' n'a pas de longueur (len() attend str/list/tuple/dict)")
    return 0

# std::hash de libstdc++ (_Hash_bytes, graine 0xc70f6907) : mêmes valeurs que hash() sous la VM.
func __nat_mix(v: int) -> int:
    return v ^ ((v >> 47) & 131071)

func __nat_hash_bytes(p: int, n: int) -> int:
    mul := -4132994306676758123
    h := 3339675911 ^ (n * mul)
    aligned := n - (n & 7)
    i := 0
    while i < aligned:
        d := __nat_mix(__load64(p + i) * mul) * mul
        h = h ^ d
        h = h * mul
        i += 8
    r := n & 7
    if r != 0:
        d := 0
        k := r - 1
        while k >= 0:
            d = (d << 8) + __load8(p + aligned + k)
            k -= 1
        h = h ^ d
        h = h * mul
    h = __nat_mix(h) * mul
    return __nat_mix(h)

func __nat_std_hash(v: int) -> int:
    k := __dyn_kind(v)
    if k == 0:
        return 2654435769
    if k == 1 or k == 3 or k == 4 or k == 5:
        return __load64(v + 8)
    if k == 2:
        x := __dyn_fv(v)
        if x == __rt_floor(x) and x < 9223372036854775808.0 and x > -9223372036854775808.0:
            return __f2i(x)
        buf := __alloc_raw(8)
        __store64(buf, __load64(v + 8))
        return __nat_hash_bytes(buf, 8)
    if k == 6:
        s := __dyn_sv(v)
        return __nat_hash_bytes(__nat_bp(s), __nat_blen(s))
    h := 2685821657736338717
    n := __load64(v + 8)
    i := 0
    while i < n:
        h = h ^ (__nat_std_hash(__load64(v + 16 + 8 * i)) + 2654435769 + (h << 6) + ((h >> 2) & 4611686018427387903))
        i += 1
    return h

func __nat__native_core__hash(n: int, v: int) -> int:
    __nat_exact("hash", n, 1)
    if not __dyn_hashable(v):
        __dyn_err("TypeError", "valeur de type '" + __dyn_type_name(v) +
                  "' non hashable, incompatible comme clé de dictionnaire (Addendum A.8)")
    return __dyn_int(__nat_std_hash(v))

func __nat__native_core__wrap_int(n: int, x: int, b: int, sg: int) -> int:
    __nat_exact("wrap_int", n, 3)
    if not __dyn_is(x, 1) or not __dyn_is(b, 1) or not __dyn_is(sg, 3):
        __dyn_err("TypeError", "wrap_int : (int, int, bool) attendus")
    bits := __dyn_iv(b)
    v := __dyn_iv(x)
    signed := __load64(sg + 8) != 0
    if bits == 64:
        if not signed and v < 0:
            __dyn_err("ValueError", "to_u64 : " + __int_to_str(v) + " n'est pas représentable (u64 limité à 0..2^63-1)")
        return x
    if bits <= 0 or bits > 64:
        __dyn_err("ValueError", "wrap_int : bits invalide")
    mask := (1 << bits) - 1
    r := v & mask
    if signed and ((r >> (bits - 1)) & 1) != 0:
        return __dyn_int(r | (-1 - mask))
    return __dyn_int(r)

func __nat__native_core__to_int(n: int, v: int) -> int:
    __nat_exact("to_int", n, 1)
    k := __dyn_kind(v)
    if k == 1:
        return v
    if k == 2:
        return __dyn_int(__f2i(__dyn_fv(v)))
    if k == 3:
        return __dyn_int(__load64(v + 8))
    if k == 6:
        return __dyn_int(__rt_str_to_int(__dyn_sv(v)))
    __dyn_err("TypeError", "to_int() ne supporte pas le type '" + __dyn_type_name(v) + "'")
    return 0

func __nat__native_core__to_float(n: int, v: int) -> int:
    __nat_exact("to_float", n, 1)
    k := __dyn_kind(v)
    if k == 2:
        return v
    if k == 1:
        return __dyn_float(__i2f(__dyn_iv(v)))
    if k == 3:
        if __load64(v + 8) != 0:
            return __dyn_float(1.0)
        return __dyn_float(0.0)
    if k == 6:
        return __dyn_float(__rt_str_to_float(__dyn_sv(v)))
    __dyn_err("TypeError", "to_float() ne supporte pas le type '" + __dyn_type_name(v) + "'")
    return 0

func __nat__native_core__to_bool(n: int, v: int) -> int:
    __nat_exact("to_bool", n, 1)
    return __dyn_bool(__dyn_truthy(v))

func __nat__native_core__is_null(n: int, v: int) -> int:
    __nat_exact("is_null", n, 1)
    return __dyn_bool(v == 0)

func __nat__native_core__is_int(n: int, v: int) -> int:
    __nat_exact("is_int", n, 1)
    return __dyn_bool(__dyn_is(v, 1))

func __nat__native_core__is_float(n: int, v: int) -> int:
    __nat_exact("is_float", n, 1)
    return __dyn_bool(__dyn_is(v, 2))

func __nat__native_core__is_bool(n: int, v: int) -> int:
    __nat_exact("is_bool", n, 1)
    return __dyn_bool(__dyn_is(v, 3))

func __nat__native_core__is_str(n: int, v: int) -> int:
    __nat_exact("is_str", n, 1)
    return __dyn_bool(__dyn_is(v, 6))

func __nat__native_core__is_list(n: int, v: int) -> int:
    __nat_exact("is_list", n, 1)
    return __dyn_bool(__dyn_is(v, 7))

func __nat__native_core__is_dict(n: int, v: int) -> int:
    __nat_exact("is_dict", n, 1)
    return __dyn_bool(__dyn_is(v, 9))

func __nat__native_core__is_tuple(n: int, v: int) -> int:
    __nat_exact("is_tuple", n, 1)
    return __dyn_bool(__dyn_is(v, 8))

func __nat__native_core__is_function(n: int, v: int) -> int:
    __nat_exact("is_function", n, 1)
    return __dyn_bool(__dyn_is(v, 10) or __dyn_is(v, 11))

func __nat__native_core__arity(n: int, v: int) -> int:
    __nat_exact("arity", n, 1)
    if not __dyn_is(v, 10):
        return 0
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__load64(v + 24)))
    __dyn_list_push(l, __dyn_int(__load64(v + 32)))
    return l

# ---- _native_math ------------------------------------------------------------------------------------------------

func __nat_numeric(fn: str, v: int) -> float:
    if __dyn_is(v, 1):
        return __i2f(__dyn_iv(v))
    if __dyn_is(v, 2):
        return __dyn_fv(v)
    __dyn_err("TypeError", "'" + fn + "' attend un nombre (int/float), obtenu '" + __dyn_type_name(v) + "'")
    return 0.0

# printf("%f") (std::to_string d'un double) : 6 décimales.
func __nat_fmt_f(x: float) -> str:
    bits := __f2bits(x)
    sign := ""
    if bits < 0:
        sign = "-"
        x = 0.0 - x
    if x != x:
        return sign + "nan"
    if x == __bits2f(9218868437227405312):
        return sign + "inf"
    if x < 1000000000000.0:
        iv := __f2i(__rt_floor(x * 1000000.0 + 0.5))
        fp := __int_to_str(iv % 1000000)
        while __nat_blen(fp) < 6:
            fp = "0" + fp
        return sign + __int_to_str(iv // 1000000) + "." + fp
    if x < 9223372036854775808.0:
        return sign + __int_to_str(__f2i(x)) + ".000000"
    return sign + __rt_float_to_str(x)

func __nat__native_math__sqrt(n: int, v: int) -> int:
    __nat_between("sqrt", n, 1, 1)
    x := __nat_numeric("sqrt", v)
    if x < 0.0:
        __dyn_err("TypeError", "sqrt(x) : x doit être >= 0 (obtenu " + __nat_fmt_f(x) + ")")
    return __dyn_float(__fsqrt(x))

# Produit scalaire de tranches de listes de nombres : somme des a[ia + t] * b[ib + t] pour t < k, dans l'ordre
# des indices (mêmes arrondis que la boucle ALEX), en code natif : boucle chaude des filtres RIF (rééchantillonnage,
# effets). IndexError si une tranche sort de sa liste, TypeError pour un élément non numérique.
func __nat__native_math__dot(n: int, a: int, ia: int, b: int, ib: int, kk: int) -> int:
    __nat_exact("dot", n, 5)
    if not __dyn_is(a, 7) or not __dyn_is(b, 7):
        __dyn_err("TypeError", "'dot' : deux list de nombres attendues (obtenu '" + __dyn_type_name(a) + "', '" + __dyn_type_name(b) + "')")
    i := __nat_int("dot", ia, "l'indice dans a")
    j := __nat_int("dot", ib, "l'indice dans b")
    k := __nat_int("dot", kk, "la longueur")
    if k < 0 or i < 0 or j < 0 or i + k > __dyn_list_len(a) or j + k > __dyn_list_len(b):
        __dyn_err("IndexError", "'dot' : tranche [" + __int_to_str(i) + ", +" + __int_to_str(k) + "] / [" + __int_to_str(j) +
                  ", +" + __int_to_str(k) + "] hors des listes")
    pa := __load64(__load64(a + 8) + 16) + 8 * i
    pb := __load64(__load64(b + 8) + 16) + 8 * j
    acc := 0.0
    t := 0
    while t < k:
        acc = acc + __nat_numeric("dot", __load64(pa + 8 * t)) * __nat_numeric("dot", __load64(pb + 8 * t))
        t += 1
    return __dyn_float(acc)

func __nat__native_math__pow(n: int, a: int, b: int) -> int:
    __nat_between("pow", n, 2, 2)
    x := __nat_numeric("pow", a)
    y := __nat_numeric("pow", b)
    return __dyn_float(__dyn_math_pow(x, y))

func __nat_minmax(fn: str, wantMin: bool, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                  a7: int, x: int) -> int:
    if n < 1:
        __dyn_err("ArgumentError", "'" + fn + "' attend entre 1 et 18446744073709551615 argument(s), obtenu " +
                  __int_to_str(n))
    i := 0
    while i < n:
        __nat_numeric(fn, __dyn_argi(i, a0, a1, a2, a3, a4, a5, a6, a7, x))
        i += 1
    best := a0
    bv := __nat_numeric(fn, a0)
    i = 1
    while i < n:
        v := __dyn_argi(i, a0, a1, a2, a3, a4, a5, a6, a7, x)
        fv := __nat_numeric(fn, v)
        better := fv > bv
        if wantMin:
            better = fv < bv
        if better:
            best = v
            bv = fv
        i += 1
    return best

func __nat__native_math__min(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int,
                             x: int) -> int:
    return __nat_minmax("min", true, n, a0, a1, a2, a3, a4, a5, a6, a7, x)

func __nat__native_math__max(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int,
                             x: int) -> int:
    return __nat_minmax("max", false, n, a0, a1, a2, a3, a4, a5, a6, a7, x)

# ---- _native_collections ---------------------------------------------------------------------------------------

func __nat_dict(fn: str, v: int) -> int:
    if not __dyn_is(v, 9):
        __dyn_err("TypeError", "'" + fn + "' : le premier argument doit être un dict (obtenu '" + __dyn_type_name(v) +
                  "')")
    return __dyn_dv(v)

func __nat_key(fn: str, k: int):
    if not __dyn_hashable(k):
        __dyn_err("TypeError", "'" + fn + "' : clé de type '" + __dyn_type_name(k) + "' non hashable (Addendum A.8)")

func __nat__native_collections__keys(n: int, d: int) -> int:
    __nat_range("keys", n, 1, 1)
    return __dyn_list_wrap(__rt_dict_list(__nat_dict("keys", d), 24))

func __nat__native_collections__values(n: int, d: int) -> int:
    __nat_range("values", n, 1, 1)
    return __dyn_list_wrap(__rt_dict_list(__nat_dict("values", d), 32))

func __nat__native_collections__items(n: int, d: int) -> int:
    __nat_range("items", n, 1, 1)
    nd := __nat_dict("items", d)
    out := __dyn_list_new(0)
    used := __load64(nd + 8)
    e := 0
    while e < used:
        if __load64(__load64(nd + 40) + 8 * e) >= 0:
            t := __dyn_tuple_new(2)
            __dyn_tuple_put(t, 0, __load64(__load64(nd + 24) + 8 * e))
            __dyn_tuple_put(t, 1, __load64(__load64(nd + 32) + 8 * e))
            __dyn_list_push(out, t)
        e += 1
    return out

func __nat__native_collections__get(n: int, d: int, k: int, dflt: int) -> int:
    __nat_range("get", n, 2, 3)
    nd := __nat_dict("get", d)
    __nat_key("get", k)
    e := __rt_dict_index(nd, k, 3)
    if e >= 0:
        return __load64(__load64(nd + 32) + 8 * e)
    if n == 3:
        return dflt
    return 0

func __nat__native_collections__set(n: int, d: int, k: int, v: int) -> int:
    __nat_range("set", n, 3, 3)
    nd := __nat_dict("set", d)
    __nat_key("set", k)
    __rt_dict_set(nd, k, v, 3)
    return 0

func __nat__native_collections__contains_key(n: int, d: int, k: int) -> int:
    __nat_range("contains_key", n, 2, 2)
    nd := __nat_dict("contains_key", d)
    __nat_key("contains_key", k)
    return __dyn_bool(__rt_dict_index(nd, k, 3) >= 0)

# ---- _native_string ----------------------------------------------------------------------------------------------

# mode : 0 majuscules, 1 minuscules, 2 capitalize, 3 title (ASCII seulement, comme la VM).
func __nat_case(s: str, mode: int) -> str:
    n := __nat_blen(s)
    p := __nat_bp(s)
    r := __rt_str_new(n)
    first := true
    i := 0
    while i < n:
        c := __load8(p + i)
        o := c
        if mode == 0:
            o = __nat_upper_b(c)
        elif mode == 1:
            o = __nat_lower_b(c)
        elif mode == 2:
            if c < 128:
                if first:
                    o = __nat_upper_b(c)
                else:
                    o = __nat_lower_b(c)
            first = false
        else:
            if __nat_is_ws(c):
                first = true
            elif c < 128:
                if first:
                    o = __nat_upper_b(c)
                else:
                    o = __nat_lower_b(c)
                first = false
            else:
                first = false
        __store8(r + 8 + i, o)
        i += 1
    return __as_str(r)

func __nat__native_string__upper(n: int, a: int) -> int:
    __nat_exact("upper", n, 1)
    return __dyn_str(__nat_case(__nat_str("upper", a, "l'argument"), 0))

func __nat__native_string__lower(n: int, a: int) -> int:
    __nat_exact("lower", n, 1)
    return __dyn_str(__nat_case(__nat_str("lower", a, "l'argument"), 1))

func __nat__native_string__capitalize(n: int, a: int) -> int:
    __nat_exact("capitalize", n, 1)
    return __dyn_str(__nat_case(__nat_str("capitalize", a, "l'argument"), 2))

func __nat__native_string__title(n: int, a: int) -> int:
    __nat_exact("title", n, 1)
    return __dyn_str(__nat_case(__nat_str("title", a, "l'argument"), 3))

func __nat_trim(s: str) -> str:
    p := __nat_bp(s)
    a := 0
    b := __nat_blen(s)
    while a < b and __nat_is_ws(__load8(p + a)):
        a += 1
    while b > a and __nat_is_ws(__load8(p + b - 1)):
        b -= 1
    return __nat_make(p + a, b - a)

func __nat__native_string__trim(n: int, a: int) -> int:
    __nat_exact("trim", n, 1)
    return __dyn_str(__nat_trim(__nat_str("trim", a, "l'argument")))

func __nat__native_string__strip(n: int, a: int) -> int:
    __nat_exact("strip", n, 1)
    return __dyn_str(__nat_trim(__nat_str("strip", a, "l'argument")))

func __nat__native_string__starts_with(n: int, a: int, b: int) -> int:
    __nat_exact("starts_with", n, 2)
    s := __nat_str("starts_with", a, "le premier argument")
    pre := __nat_str("starts_with", b, "le préfixe")
    m := __nat_blen(pre)
    if __nat_blen(s) < m:
        return __dyn_bool(false)
    return __dyn_bool(__dyn_find_bytes(__nat_make(__nat_bp(s), m), pre, 0) == 0)

func __nat__native_string__ends_with(n: int, a: int, b: int) -> int:
    __nat_exact("ends_with", n, 2)
    s := __nat_str("ends_with", a, "le premier argument")
    suf := __nat_str("ends_with", b, "le suffixe")
    m := __nat_blen(suf)
    ls := __nat_blen(s)
    if ls < m:
        return __dyn_bool(false)
    return __dyn_bool(__dyn_find_bytes(__nat_make(__nat_bp(s) + ls - m, m), suf, 0) == 0)

func __nat__native_string__contains(n: int, a: int, b: int) -> int:
    __nat_exact("contains", n, 2)
    s := __nat_str("contains", a, "le premier argument")
    sub := __nat_str("contains", b, "la sous-chaîne")
    return __dyn_bool(__nat_blen(sub) == 0 or __dyn_find_bytes(s, sub, 0) >= 0)

func __nat__native_string__split(n: int, a: int, b: int) -> int:
    __nat_exact("split", n, 2)
    s := __nat_str("split", a, "le premier argument")
    sep := __nat_str("split", b, "le séparateur")
    if __nat_blen(sep) == 0:
        __dyn_err("ArgumentError", "split(...) : le séparateur ne peut pas être vide")
    out := __dyn_list_new(0)
    start := 0
    while true:
        pos := __dyn_find_bytes(s, sep, start)
        if pos < 0:
            __dyn_list_push(out, __dyn_str(__nat_sub(s, start, __nat_blen(s) - start)))
            break
        __dyn_list_push(out, __dyn_str(__nat_sub(s, start, pos - start)))
        start = pos + __nat_blen(sep)
    return out

func __nat__native_string__join(n: int, a: int, b: int) -> int:
    __nat_exact("join", n, 2)
    sep := __nat_str("join", a, "le séparateur")
    if not __dyn_is(b, 7):
        __dyn_err("TypeError", "'join' : le second argument doit être une list (obtenu '" + __dyn_type_name(b) + "')")
    sb := __rt_sb_new()
    m := __dyn_list_len(b)
    i := 0
    while i < m:
        if i > 0:
            __rt_sb_add(sb, sep)
        __rt_sb_add(sb, __nat_str("join", __dyn_list_at(b, i), "l'élément " + __int_to_str(i) + " de la liste"))
        i += 1
    return __dyn_str(__rt_sb_str(sb))

func __nat__native_string__replace(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("replace", n, 3)
    s := __nat_str("replace", a, "le premier argument")
    old := __nat_str("replace", b, "l'ancienne sous-chaîne")
    rep := __nat_str("replace", c, "la nouvelle sous-chaîne")
    if __nat_blen(old) == 0:
        __dyn_err("ArgumentError", "replace(...) : la sous-chaîne à remplacer ne peut pas être vide")
    sb := __rt_sb_new()
    start := 0
    while true:
        pos := __dyn_find_bytes(s, old, start)
        if pos < 0:
            __rt_sb_add(sb, __nat_sub(s, start, __nat_blen(s) - start))
            break
        __rt_sb_add(sb, __nat_sub(s, start, pos - start))
        __rt_sb_add(sb, rep)
        start = pos + __nat_blen(old)
    return __dyn_str(__rt_sb_str(sb))

func __nat__native_string__find(n: int, a: int, b: int) -> int:
    __nat_exact("find", n, 2)
    s := __nat_str("find", a, "le premier argument")
    sub := __nat_str("find", b, "la sous-chaîne recherchée")
    if __nat_blen(sub) == 0:
        return __dyn_int(0)
    pos := __dyn_find_bytes(s, sub, 0)
    if pos < 0:
        return __dyn_int(-1)
    return __dyn_int(__load64(__nat_decode(__nat_sub(s, 0, pos))))

func __nat__native_string__substring(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("substring", n, 3)
    s := __nat_str("substring", a, "le premier argument")
    if not __dyn_is(b, 1) or not __dyn_is(c, 1):
        __dyn_err("TypeError", "substring(...) : start/end doivent être des int")
    cps := __nat_decode(s)
    count := __load64(cps)
    start := __dyn_iv(b)
    end := __dyn_iv(c)
    if start < 0 or end < start or end > count:
        __dyn_err("IndexError", "substring(" + __int_to_str(start) + ", " + __int_to_str(end) + ") hors limites (longueur " +
                  __int_to_str(count) + ", §10)")
    return __dyn_str(__nat_encode(cps, start, end))

func __nat__native_string__count(n: int, a: int, b: int) -> int:
    __nat_exact("count", n, 2)
    s := __nat_str("count", a, "le premier argument")
    sub := __nat_str("count", b, "la sous-chaîne")
    if __nat_blen(sub) == 0:
        __dyn_err("ArgumentError", "count(...) : la sous-chaîne ne peut pas être vide")
    k := 0
    start := 0
    while true:
        pos := __dyn_find_bytes(s, sub, start)
        if pos < 0:
            break
        k += 1
        start = pos + __nat_blen(sub)
    return __dyn_int(k)

func __nat__native_string__repeat(n: int, a: int, b: int) -> int:
    __nat_exact("repeat", n, 2)
    s := __nat_str("repeat", a, "le premier argument")
    if not __dyn_is(b, 1):
        __dyn_err("TypeError", "repeat(...) : n doit être un int")
    k := __dyn_iv(b)
    if k < 0:
        __dyn_err("ArgumentError", "repeat(...) : n doit être >= 0")
    m := __nat_blen(s)
    if m > 0 and k > 4611686018427387903 // m:
        __dyn_err("MemoryError", "mémoire insuffisante")
    if m * k > 68719476736: # au-delà de 64 Gio : la réservation de la VM échoue de même
        __dyn_err("MemoryError", "mémoire insuffisante")
    r := __rt_str_new(m * k)
    i := 0
    while i < k:
        __copy(r + 8 + i * m, __nat_bp(s), m)
        i += 1
    return __dyn_str(__as_str(r))

func __nat__native_string__chr(n: int, a: int) -> int:
    __nat_exact("chr", n, 1)
    if not __dyn_is(a, 1):
        __dyn_err("TypeError", "chr(...) : le code doit être un int (obtenu '" + __dyn_type_name(a) + "')")
    cp := __dyn_iv(a)
    if cp < 0 or cp > 1114111 or (cp >= 55296 and cp <= 57343):
        __dyn_err("ValueError", "chr(" + __int_to_str(cp) + ") : point de code Unicode invalide")
    return __dyn_char(cp)

func __nat__native_string__ord(n: int, a: int) -> int:
    __nat_exact("ord", n, 1)
    if __dyn_is(a, 4):
        return __dyn_int(__load64(a + 8))
    if not __dyn_is_str(a):
        __dyn_err("TypeError", "ord(...) : attend un char ou une str d'un caractère (obtenu '" + __dyn_type_name(a) + "')")
    cps := __nat_decode(__dyn_sv(a))
    if __load64(cps) != 1:
        __dyn_err("ValueError", "ord(...) : attend exactement 1 caractère (longueur " + __int_to_str(__load64(cps)) + ")")
    return __dyn_int(__load64(__load64(cps + 16)))

func __nat_slice_arg(v: int, label: str) -> int:
    if v != 0 and not __dyn_is(v, 1):
        __dyn_err("TypeError", "slice(...) : " + label + " doit être un int ou null (obtenu '" + __dyn_type_name(v) + "')")
    return v

func __nat_slice_adj(v: int, n: int, lo: int, hi: int) -> int:
    if v < 0:
        v += n
        if v < lo:
            v = lo
    elif v > hi:
        v = hi
    return v

func __nat__native_string__slice(n: int, a: int, b: int, c: int, d: int) -> int:
    if n < 1 or n > 4:
        __dyn_err("ArgumentError", "'slice' attend de 1 à 4 argument(s), obtenu " + __int_to_str(n))
    s := __nat_str("slice", a, "le premier argument")
    vb := 0
    vc := 0
    vd := 0
    if n > 1:
        vb = __nat_slice_arg(b, "start")
    if n > 2:
        vc = __nat_slice_arg(c, "stop")
    if n > 3:
        vd = __nat_slice_arg(d, "step")
    step := 1
    if vd != 0:
        step = __dyn_iv(vd)
    if step == 0:
        __dyn_err("ValueError", "slice(...) : le pas ne peut pas être nul")
    cps := __nat_decode(s)
    m := __load64(cps)
    lo := 0
    hi := m
    if step < 0:
        lo = -1
        hi = m - 1
    bb := lo
    ee := hi
    if step < 0:
        bb = hi
        ee = lo
    if vb != 0:
        bb = __nat_slice_adj(__dyn_iv(vb), m, lo, hi)
    if vc != 0:
        ee = __nat_slice_adj(__dyn_iv(vc), m, lo, hi)
    sb := __rt_sb_new()
    dd := __load64(cps + 16)
    i := bb
    if step > 0:
        while i < ee:
            __nat_sb_cp(sb, __load64(dd + 8 * i))
            i += step
    else:
        while i > ee:
            __nat_sb_cp(sb, __load64(dd + 8 * i))
            i += step
    return __dyn_str(__rt_sb_str(sb))

func __nat__native_string__byte_len(n: int, a: int) -> int:
    __nat_exact("byte_len", n, 1)
    return __dyn_int(__nat_blen(__nat_str("byte_len", a, "l'argument")))

func __nat__native_string__byte_at(n: int, a: int, b: int) -> int:
    __nat_exact("byte_at", n, 2)
    s := __nat_str("byte_at", a, "le premier argument")
    i := __nat_int("byte_at", b, "l'indice")
    if i < 0 or i >= __nat_blen(s):
        __dyn_err("IndexError", "byte_at(" + __int_to_str(i) + ") hors limites (" + __int_to_str(__nat_blen(s)) + " octets)")
    return __dyn_int(__load8(__nat_bp(s) + i))

func __nat__native_string__byte_slice(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("byte_slice", n, 3)
    s := __nat_str("byte_slice", a, "le premier argument")
    x := __nat_int("byte_slice", b, "le début")
    y := __nat_int("byte_slice", c, "la fin")
    m := __nat_blen(s)
    if x < 0:
        x = 0
    if y > m:
        y = m
    if y <= x:
        return __dyn_str("")
    return __dyn_str(__nat_sub(s, x, y - x))

func __nat__native_string__byte_find(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("byte_find", n, 3)
    s := __nat_str("byte_find", a, "le premier argument")
    sub := __nat_str("byte_find", b, "la sous-chaîne recherchée")
    start := __nat_int("byte_find", c, "le début")
    if start < 0:
        start = 0
    if start > __nat_blen(s):
        return __dyn_int(-1)
    return __dyn_int(__dyn_find_bytes(s, sub, start))

func __nat__native_string__byte_char(n: int, a: int) -> int:
    __nat_exact("byte_char", n, 1)
    v := __nat_int("byte_char", a, "l'argument")
    r := __rt_str_new(1)
    __store8(r + 8, v & 255)
    return __dyn_str(__as_str(r))

func __nat__native_string__byte_pack(n: int, a: int) -> int:
    __nat_exact("byte_pack", n, 1)
    if not __dyn_is(a, 7):
        __dyn_err("TypeError", "'byte_pack' : l'argument doit être une list[int] (obtenu '" + __dyn_type_name(a) + "')")
    m := __dyn_list_len(a)
    r := __rt_str_new(m)
    i := 0
    while i < m:
        __store8(r + 8 + i, __nat_int("byte_pack", __dyn_list_at(a, i), "chaque élément") & 255)
        i += 1
    return __dyn_str(__as_str(r))

func __nat__native_string__byte_unpack(n: int, a: int) -> int:
    __nat_exact("byte_unpack", n, 1)
    s := __nat_str("byte_unpack", a, "l'argument")
    m := __nat_blen(s)
    out := __dyn_list_new(0)
    i := 0
    while i < m:
        __dyn_list_push(out, __dyn_int(__load8(__nat_bp(s) + i)))
        i += 1
    return out

func __nat__native_string__byte_join(n: int, a: int) -> int:
    __nat_exact("byte_join", n, 1)
    if not __dyn_is(a, 7):
        __dyn_err("TypeError", "'byte_join' : l'argument doit être une list[str] (obtenu '" + __dyn_type_name(a) + "')")
    m := __dyn_list_len(a)
    i := 0
    while i < m:
        __nat_str("byte_join", __dyn_list_at(a, i), "chaque élément")
        i += 1
    sb := __rt_sb_new()
    i = 0
    while i < m:
        __rt_sb_add(sb, __dyn_sv(__dyn_list_at(a, i)))
        i += 1
    return __dyn_str(__rt_sb_str(sb))

func __nat_hex(d: int) -> int:
    if d < 10:
        return 48 + d
    return 87 + d

func __nat__native_string__json_quote(n: int, a: int) -> int:
    if n != 1 or not __dyn_is_str(a):
        __dyn_err("TypeError", "json_quote(s : str) attendu")
    s := __dyn_sv(a)
    p := __nat_bp(s)
    m := __nat_blen(s)
    sb := __rt_sb_new()
    __rt_sb_byte(sb, 34)
    i := 0
    while i < m:
        c := __load8(p + i)
        if c == 34:
            __rt_sb_add(sb, "\\\"")
        elif c == 92:
            __rt_sb_add(sb, "\\\\")
        elif c == 10:
            __rt_sb_add(sb, "\\n")
        elif c == 9:
            __rt_sb_add(sb, "\\t")
        elif c == 13:
            __rt_sb_add(sb, "\\r")
        elif c == 8:
            __rt_sb_add(sb, "\\b")
        elif c == 12:
            __rt_sb_add(sb, "\\f")
        elif c < 32:
            __rt_sb_add(sb, "\\u00")
            __rt_sb_byte(sb, __nat_hex(c >> 4))
            __rt_sb_byte(sb, __nat_hex(c & 15))
        else:
            __rt_sb_byte(sb, c)
        i += 1
    __rt_sb_byte(sb, 34)
    return __dyn_str(__rt_sb_str(sb))

# json_parse : lecteur [texte (chaîne native), position, profondeur].
func __nat_json_fail():
    __dyn_err("ArgumentError", "json_parse : JSON invalide")

func __nat_jc(r: int) -> int: # octet courant, -1 en fin de texte
    i := __load64(r + 8)
    s := __as_str(__load64(r))
    if i >= __nat_blen(s):
        return -1
    return __load8(__nat_bp(s) + i)

func __nat_jadv(r: int, k: int):
    __store64(r + 8, __load64(r + 8) + k)

func __nat_jws(r: int):
    c := __nat_jc(r)
    while c == 32 or c == 9 or c == 10 or c == 13:
        __nat_jadv(r, 1)
        c = __nat_jc(r)

func __nat_jhex4(r: int) -> int:
    v := 0
    k := 0
    while k < 4:
        c := __nat_jc(r)
        if c < 0:
            __nat_json_fail()
        __nat_jadv(r, 1)
        v = v << 4
        if c >= 48 and c <= 57:
            v = v | (c - 48)
        elif c >= 97 and c <= 102:
            v = v | (c - 87)
        elif c >= 65 and c <= 70:
            v = v | (c - 55)
        else:
            __nat_json_fail()
        k += 1
    return v

func __nat_jstr(r: int) -> str:
    __nat_jadv(r, 1)
    sb := __rt_sb_new()
    while true:
        c := __nat_jc(r)
        if c < 0:
            __nat_json_fail()
        __nat_jadv(r, 1)
        if c == 34:
            return __rt_sb_str(sb)
        if c < 32:
            __nat_json_fail()
        if c != 92:
            __rt_sb_byte(sb, c)
            continue
        e := __nat_jc(r)
        if e < 0:
            __nat_json_fail()
        __nat_jadv(r, 1)
        if e == 34 or e == 92 or e == 47:
            __rt_sb_byte(sb, e)
        elif e == 98:
            __rt_sb_byte(sb, 8)
        elif e == 102:
            __rt_sb_byte(sb, 12)
        elif e == 110:
            __rt_sb_byte(sb, 10)
        elif e == 114:
            __rt_sb_byte(sb, 13)
        elif e == 116:
            __rt_sb_byte(sb, 9)
        elif e == 117:
            cp := __nat_jhex4(r)
            if cp >= 56320 and cp <= 57343:
                __nat_json_fail()
            if cp >= 55296 and cp <= 56319:
                if __nat_jc(r) != 92:
                    __nat_json_fail()
                __nat_jadv(r, 1)
                if __nat_jc(r) != 117:
                    __nat_json_fail()
                __nat_jadv(r, 1)
                lo := __nat_jhex4(r)
                if lo < 56320 or lo > 57343:
                    __nat_json_fail()
                cp = 65536 + ((cp - 55296) << 10) + (lo - 56320)
            __nat_sb_cp(sb, cp)
        else:
            __nat_json_fail()
    return ""

func __nat_jword(r: int, w: str) -> bool:
    s := __as_str(__load64(r))
    i := __load64(r + 8)
    m := __nat_blen(w)
    if i + m > __nat_blen(s):
        return false
    if __dyn_find_bytes(__nat_sub(s, i, m), w, 0) != 0:
        return false
    __nat_jadv(r, m)
    return true

func __nat_jdigit(c: int) -> bool:
    return c >= 48 and c <= 57

func __nat_jvalue(r: int) -> int:
    __nat_jws(r)
    c := __nat_jc(r)
    if c < 0:
        __nat_json_fail()
    if c == 123 or c == 91:
        __store64(r + 16, __load64(r + 16) + 1)
        if __load64(r + 16) > 100:
            __nat_json_fail()
        __nat_jadv(r, 1)
        close := 93
        out := 0
        if c == 123:
            close = 125
            out = __dyn_dict_new()
        else:
            out = __dyn_list_new(0)
        __nat_jws(r)
        if __nat_jc(r) == close:
            __nat_jadv(r, 1)
            __store64(r + 16, __load64(r + 16) - 1)
            return out
        while true:
            if c == 123:
                __nat_jws(r)
                if __nat_jc(r) != 34:
                    __nat_json_fail()
                k := __nat_jstr(r)
                __nat_jws(r)
                if __nat_jc(r) != 58:
                    __nat_json_fail()
                __nat_jadv(r, 1)
                v := __nat_jvalue(r)
                __rt_dict_set(__dyn_dv(out), __dyn_str(k), v, 3)
            else:
                __dyn_list_push(out, __nat_jvalue(r))
            __nat_jws(r)
            d := __nat_jc(r)
            if d == 44:
                __nat_jadv(r, 1)
                continue
            if d == close:
                __nat_jadv(r, 1)
                __store64(r + 16, __load64(r + 16) - 1)
                return out
            __nat_json_fail()
    if c == 34:
        return __dyn_str(__nat_jstr(r))
    if __nat_jword(r, "true"):
        return __dyn_bool(true)
    if __nat_jword(r, "false"):
        return __dyn_bool(false)
    if __nat_jword(r, "null"):
        return 0
    st := __load64(r + 8)
    if c == 45:
        __nat_jadv(r, 1)
    if not __nat_jdigit(__nat_jc(r)):
        __nat_json_fail()
    if __nat_jc(r) == 48:
        __nat_jadv(r, 1)
    else:
        while __nat_jdigit(__nat_jc(r)):
            __nat_jadv(r, 1)
    isFloat := false
    if __nat_jc(r) == 46:
        isFloat = true
        __nat_jadv(r, 1)
        if not __nat_jdigit(__nat_jc(r)):
            __nat_json_fail()
        while __nat_jdigit(__nat_jc(r)):
            __nat_jadv(r, 1)
    if __nat_jc(r) == 101 or __nat_jc(r) == 69:
        isFloat = true
        __nat_jadv(r, 1)
        if __nat_jc(r) == 43 or __nat_jc(r) == 45:
            __nat_jadv(r, 1)
        if not __nat_jdigit(__nat_jc(r)):
            __nat_json_fail()
        while __nat_jdigit(__nat_jc(r)):
            __nat_jadv(r, 1)
    num := __nat_sub(__as_str(__load64(r)), st, __load64(r + 8) - st)
    if not isFloat:
        # entier dans 64 bits (sinon : flottant, comme strtoll en dépassement)
        p := __nat_bp(num)
        m := __nat_blen(num)
        neg := __load8(p) == 45
        i := 0
        if neg:
            i = 1
        acc := 0
        ok := true
        while i < m:
            dg := __load8(p + i) - 48
            if acc < (-9223372036854775807 - 1 + dg) // 10:
                ok = false
                break
            acc = acc * 10 - dg
            i += 1
        if ok and not neg and acc == -9223372036854775807 - 1:
            ok = false
        if ok:
            if neg:
                return __dyn_int(acc)
            return __dyn_int(0 - acc)
    return __dyn_float(__nat_json_float(num))

# Flottant d'un nombre JSON valide (strtod) : dépassement -> JSON invalide, sous-dépassement -> 0.
func __nat_json_float(num: str) -> float:
    p := __nat_bp(num)
    m := __nat_blen(num)
    # exposant décimal approximatif : chiffres avant le point (sans zéros de tête) + exposant
    i := 0
    if __load8(p) == 45:
        i = 1
    lead := 0
    nz := false
    frac := false
    fz := 0
    ex := 0
    while i < m and __load8(p + i) != 101 and __load8(p + i) != 69:
        c := __load8(p + i)
        if c == 46:
            frac = true
        elif c != 48 or nz:
            nz = true
            if not frac:
                lead += 1
        elif frac and not nz:
            fz += 1
        i += 1
    if i < m:
        j := i + 1
        eneg := false
        if __load8(p + j) == 43 or __load8(p + j) == 45:
            eneg = __load8(p + j) == 45
            j += 1
        while j < m:
            if ex < 100000:
                ex = ex * 10 + __load8(p + j) - 48
            j += 1
        if eneg:
            ex = 0 - ex
    if not nz:
        if __load8(p) == 45:
            return __bits2f(-9223372036854775807 - 1)
        return 0.0
    mag := ex + lead
    if lead == 0:
        mag = ex - fz
    if mag > 309:
        __nat_json_fail()
    if mag < -323:
        if __load8(p) == 45:
            return __bits2f(-9223372036854775807 - 1)
        return 0.0
    return __rt_str_to_float(num)

func __nat__native_string__json_parse(n: int, a: int) -> int:
    if n != 1 or not __dyn_is_str(a):
        __dyn_err("TypeError", "json_parse(texte : str) attendu")
    r := __alloc(24)
    __store64(r, __load64(a + 8))
    v := __nat_jvalue(r)
    __nat_jws(r)
    if __nat_jc(r) >= 0:
        __nat_json_fail()
    return v

# ---- Appels système : chaînes C, erreurs --------------------------------------------------------------------------

func __nat_c(s: str) -> int:
    p := __str_addr(s)
    n := __load64(p)
    c := __alloc_raw(n + 1)
    __copy(c, p + 8, n)
    __store8(c + n, 0)
    return c

func __nat_from_c(c: int) -> str:
    n := 0
    while __load8(c + n) != 0:
        n += 1
    return __nat_make(c, n)

# strerror (glibc) des erreurs courantes.
func __nat_errno_text(e: int) -> str:
    if e == 1:
        return "Operation not permitted"
    if e == 2:
        return "No such file or directory"
    if e == 3:
        return "No such process"
    if e == 5:
        return "Input/output error"
    if e == 9:
        return "Bad file descriptor"
    if e == 10:
        return "No child processes"
    if e == 11:
        return "Resource temporarily unavailable"
    if e == 12:
        return "Cannot allocate memory"
    if e == 13:
        return "Permission denied"
    if e == 14:
        return "Bad address"
    if e == 16:
        return "Device or resource busy"
    if e == 17:
        return "File exists"
    if e == 18:
        return "Invalid cross-device link"
    if e == 20:
        return "Not a directory"
    if e == 21:
        return "Is a directory"
    if e == 22:
        return "Invalid argument"
    if e == 24:
        return "Too many open files"
    if e == 26:
        return "Text file busy"
    if e == 27:
        return "File too large"
    if e == 28:
        return "No space left on device"
    if e == 30:
        return "Read-only file system"
    if e == 31:
        return "Too many links"
    if e == 32:
        return "Broken pipe"
    if e == 36:
        return "File name too long"
    if e == 38:
        return "Function not implemented"
    if e == 39:
        return "Directory not empty"
    if e == 40:
        return "Too many levels of symbolic links"
    if e == 95:
        return "Operation not supported"
    if e == 122:
        return "Disk quota exceeded"
    return "Unknown error " + __int_to_str(e)

func __nat_io_fail(ctx: str, text: str):
    __dyn_err("IoError", ctx + " : " + text)

func __nat_ctx(fn: str, a: str) -> str:
    return fn + "('" + a + "')"

func __nat_ctx2(fn: str, a: str, b: str) -> str:
    return fn + "('" + a + "', '" + b + "')"

# stat (lstat si nofollow) : tampon de 144 octets, ou erreur négative (-errno) en tête.
func __nat_stat(path: str, nofollow: bool) -> int:
    st := __alloc_raw(144)
    nr := 4
    if nofollow:
        nr = 6
    r := __syscall(nr, __nat_c(path), st)
    if r < 0:
        __store64(st, r)
        __store64(st + 136, 1)
        return st
    __store64(st + 136, 0)
    return st

func __nat_st_failed(st: int) -> bool:
    return __load64(st + 136) != 0

func __nat_st_errno(st: int) -> int:
    return 0 - __load64(st)

func __nat_st_type(st: int) -> int: # S_IFMT
    if __nat_st_failed(st):
        return -1
    return __load32(st + 24) & 61440

func __nat_ts(st: int, off: int) -> float:
    return __i2f(__load64(st + off)) + __i2f(__load64(st + off + 8)) * 0.000000001

# Taille d'un fichier ordinaire (std::filesystem::file_size) ; IoError « fn('chemin') : raison » sinon.
func __nat_fsize(fn: str, path: str) -> int:
    st := __nat_stat(path, false)
    if __nat_st_failed(st):
        __nat_io_fail(__nat_ctx(fn, path), __nat_errno_text(__nat_st_errno(st)))
    t := __nat_st_type(st)
    if t == 16384:
        __nat_io_fail(__nat_ctx(fn, path), "Is a directory")
    if t != 32768:
        __nat_io_fail(__nat_ctx(fn, path), "Operation not supported")
    return __load64(st + 48)

func __nat_read_fd(fd: int, limit: int) -> str:
    sb := __rt_sb_new()
    buf := __alloc_raw(65536)
    total := 0
    while limit < 0 or total < limit:
        want := 65536
        if limit >= 0 and limit - total < want:
            want = limit - total
        k := __syscall(0, fd, buf, want)
        if k <= 0:
            break
        __rt_sb_reserve(sb, k)
        __copy(__load64(sb + 16) + __load64(sb), buf, k)
        __store64(sb, __load64(sb) + k)
        total += k
    return __rt_sb_str(sb)

func __nat_write_fd(fd: int, s: str) -> bool:
    p := __nat_bp(s)
    n := __nat_blen(s)
    done := 0
    while done < n:
        w := __syscall(1, fd, p + done, n - done)
        if w <= 0:
            return false
        done += w
    return true

# ---- _native_io -----------------------------------------------------------------------------------------------------

func __nat__native_io__read_file(n: int, a: int) -> int:
    __nat_exact("read_file", n, 1)
    path := __nat_str("read_file", a, "le chemin")
    fd := __syscall(2, __nat_c(path), 0)
    if fd < 0:
        __dyn_err("IoError", "read_file('" + path + "') : impossible d'ouvrir le fichier")
    s := __nat_read_fd(fd, -1)
    __syscall(3, fd)
    return __dyn_str(s)

func __nat_write_file(fn: str, n: int, a: int, b: int, flags: int, openMsg: str) -> int:
    __nat_exact(fn, n, 2)
    path := __nat_str(fn, a, "le chemin")
    content := __nat_str(fn, b, "le contenu")
    fd := __syscall(2, __nat_c(path), flags, 438)
    if fd < 0:
        __dyn_err("IoError", fn + "('" + path + "') : " + openMsg)
    ok := __nat_write_fd(fd, content)
    __syscall(3, fd)
    if not ok:
        __dyn_err("IoError", fn + "('" + path + "') : erreur d'écriture")
    return 0

func __nat__native_io__write_file(n: int, a: int, b: int) -> int:
    return __nat_write_file("write_file", n, a, b, 577, "impossible d'ouvrir le fichier en écriture")

func __nat__native_io__append_file(n: int, a: int, b: int) -> int:
    return __nat_write_file("append_file", n, a, b, 1089, "impossible d'ouvrir le fichier")

func __nat__native_io__file_exists(n: int, a: int) -> int:
    __nat_exact("file_exists", n, 1)
    path := __nat_str("file_exists", a, "le chemin")
    return __dyn_bool(__nat_st_type(__nat_stat(path, false)) == 32768)

func __nat__native_io__delete_file(n: int, a: int) -> int:
    __nat_exact("delete_file", n, 1)
    path := __nat_str("delete_file", a, "le chemin")
    if __nat_st_type(__nat_stat(path, false)) != 32768:
        __dyn_err("IoError", "delete_file('" + path + "') : fichier introuvable")
    if __syscall(87, __nat_c(path)) != 0:
        __dyn_err("IoError", "delete_file('" + path + "') : suppression impossible")
    return 0

func __nat__native_io__flush_stdout(n: int) -> int:
    if n != 0:
        __dyn_err("ArgumentError", "'flush_stdout' n'attend aucun argument")
    __flush()
    return 0

func __nat_offset(fn: str, v: int) -> int:
    off := __nat_int(fn, v, "la position")
    if off < 0:
        __dyn_err("ArgumentError", "'" + fn + "' : la position doit être >= 0")
    return off

func __nat_open_at(fn: str, path: str, off: int) -> int:
    fd := __syscall(2, __nat_c(path), 0)
    if fd < 0:
        __nat_io_fail(__nat_ctx(fn, path), "impossible d'ouvrir le fichier")
    if off > 0:
        __syscall(8, fd, off, 0)
    return fd

func __nat_text_result(text: str, consumed: int) -> int:
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_str(text))
    __dyn_list_push(l, __dyn_int(consumed))
    return l

func __nat_utf8_len(lead: int) -> int:
    if lead < 128:
        return 1
    if (lead & 224) == 192:
        return 2
    if (lead & 240) == 224:
        return 3
    if (lead & 248) == 240:
        return 4
    return 1

# read_text / read_line : texte à partir de l'octet `off` (\r\n et \r -> \n) ; [texte, octets consommés].
func __nat_scan_text(fn: str, path: str, off: int, maxChars: int, lineMode: bool) -> int:
    size := __nat_fsize(fn, path)
    if off >= size:
        return __nat_text_result("", 0)
    fd := __nat_open_at(fn, path, off)
    data := __nat_read_fd(fd, -1)
    __syscall(3, fd)
    p := __nat_bp(data)
    m := __nat_blen(data)
    sb := __rt_sb_new()
    i := 0
    chars := 0
    while i < m:
        if not lineMode and maxChars >= 0 and chars >= maxChars:
            break
        c := __load8(p + i)
        i += 1
        if c == 13:
            if i < m and __load8(p + i) == 10:
                i += 1
            __rt_sb_byte(sb, 10)
            chars += 1
            if lineMode:
                break
            continue
        if c == 10:
            __rt_sb_byte(sb, 10)
            chars += 1
            if lineMode:
                break
            continue
        __rt_sb_byte(sb, c)
        need := __nat_utf8_len(c)
        k := 1
        while k < need:
            if i >= m or (__load8(p + i) & 192) != 128:
                break
            __rt_sb_byte(sb, __load8(p + i))
            i += 1
            k += 1
        chars += 1
    return __nat_text_result(__rt_sb_str(sb), i)

func __nat__native_io__read_text(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("read_text", n, 3)
    path := __nat_str("read_text", a, "le chemin")
    off := __nat_offset("read_text", b)
    chars := __nat_int("read_text", c, "le nombre de caractères")
    return __nat_scan_text("read_text", path, off, chars, false)

func __nat__native_io__read_line(n: int, a: int, b: int) -> int:
    __nat_exact("read_line", n, 2)
    path := __nat_str("read_line", a, "le chemin")
    off := __nat_offset("read_line", b)
    return __nat_scan_text("read_line", path, off, -1, true)

func __nat_bytes_list(s: str) -> int:
    m := __nat_blen(s)
    out := __dyn_list_new(0)
    p := __nat_bp(s)
    i := 0
    while i < m:
        __dyn_list_push(out, __dyn_int(__load8(p + i)))
        i += 1
    return out

func __nat__native_io__read_bytes(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("read_bytes", n, 3)
    path := __nat_str("read_bytes", a, "le chemin")
    off := __nat_offset("read_bytes", b)
    length := __nat_int("read_bytes", c, "la longueur")
    __nat_fsize("read_bytes", path)
    fd := __nat_open_at("read_bytes", path, off)
    data := __nat_read_fd(fd, length)
    __syscall(3, fd)
    return __nat_bytes_list(data)

# Octets d'une list/tuple d'entiers 0..255 (ou de byte).
func __nat_list_bytes(fn: str, v: int) -> str:
    k := __dyn_kind(v)
    if k != 7 and k != 8:
        __dyn_err("TypeError", "'" + fn + "' : les données doivent être une list d'octets (entiers 0..255) (obtenu '" +
                  __dyn_type_name(v) + "')")
    m := 0
    if k == 7:
        m = __dyn_list_len(v)
    else:
        m = __dyn_tuple_len(v)
    r := __rt_str_new(m)
    i := 0
    while i < m:
        b := 0
        if k == 7:
            b = __dyn_list_at(v, i)
        else:
            b = __dyn_tuple_at(v, i)
        x := 0
        if __dyn_is(b, 1) or __dyn_is(b, 5):
            x = __load64(b + 8)
        else:
            __dyn_err("TypeError", "'" + fn + "' : chaque octet doit être un int (obtenu '" + __dyn_type_name(b) + "')")
        if x < 0 or x > 255:
            __dyn_err("ArgumentError", "'" + fn + "' : octet hors limites (" + __int_to_str(x) + ", attendu 0..255)")
        __store8(r + 8 + i, x)
        i += 1
    return __as_str(r)

func __nat__native_io__write_bytes(n: int, a: int, b: int) -> int:
    __nat_exact("write_bytes", n, 2)
    path := __nat_str("write_bytes", a, "le chemin")
    data := __nat_list_bytes("write_bytes", b)
    fd := __syscall(2, __nat_c(path), 577, 438)
    if fd < 0:
        __nat_io_fail(__nat_ctx("write_bytes", path), "impossible d'ouvrir le fichier en écriture")
    ok := __nat_write_fd(fd, data)
    __syscall(3, fd)
    if not ok:
        __nat_io_fail(__nat_ctx("write_bytes", path), "erreur d'écriture")
    return 0

func __nat_write_at(fn: str, path: str, off: int, data: str) -> int:
    if off < 0:
        fd := __syscall(2, __nat_c(path), 1089, 438)
        if fd < 0:
            __nat_io_fail(__nat_ctx(fn, path), "impossible d'ouvrir le fichier en écriture")
        ok := __nat_write_fd(fd, data)
        __syscall(3, fd)
        if not ok:
            __nat_io_fail(__nat_ctx(fn, path), "erreur d'écriture")
        return __dyn_int(__nat_blen(data))
    size := __nat_fsize(fn, path)
    fd := __syscall(2, __nat_c(path), 2, 438)
    if fd < 0:
        __nat_io_fail(__nat_ctx(fn, path), "impossible d'ouvrir le fichier en écriture")
    if off > size:
        __syscall(77, fd, off)
    __syscall(8, fd, off, 0)
    ok := __nat_write_fd(fd, data)
    __syscall(3, fd)
    if not ok:
        __nat_io_fail(__nat_ctx(fn, path), "erreur d'écriture")
    return __dyn_int(__nat_blen(data))

func __nat__native_io__write_bytes_at(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("write_bytes_at", n, 3)
    path := __nat_str("write_bytes_at", a, "le chemin")
    off := -1
    if b != 0:
        off = __nat_offset("write_bytes_at", b)
    return __nat_write_at("write_bytes_at", path, off, __nat_list_bytes("write_bytes_at", c))

func __nat__native_io__write_at(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("write_at", n, 3)
    path := __nat_str("write_at", a, "le chemin")
    off := -1
    if b != 0:
        off = __nat_offset("write_at", b)
    return __nat_write_at("write_at", path, off, __nat_str("write_at", c, "le texte"))

# ---- fichiers à accès aléatoire, descripteur gardé ouvert (moteurs de stockage : pages, journaux) ----------------
# fopen(chemin, créer) -> descripteur ; pread(fd, position, n) -> octets (list, plus courte en fin de fichier) ;
# pwrite(fd, position, octets) -> n ; fsync(fd) : données sur le support ; fsize(fd) ; fclose(fd).
# Un seul open / close par fichier au lieu d'un par accès (sous Windows, chaque fermeture d'un fichier modifié
# coûte des millisecondes : analyse antivirus) ; fsync rend durable ce qui a été écrit.
func __nat__native_io__fopen(n: int, a: int, b: int) -> int:
    __nat_exact("fopen", n, 2)
    path := __nat_cstr("fopen", a, "le chemin")
    flags := 2 | 524288                 # O_RDWR | O_CLOEXEC
    if __nat_bool("fopen", b, "créer"):
        flags = flags | 64              # O_CREAT
    fd := __syscall(2, __nat_c(path), flags, 420)
    if fd < 0:
        __nat_io_fail(__nat_ctx("fopen", path), __nat_errno_text(0 - fd))
    return __dyn_int(fd)

func __nat_fd_pos(fn: str, fd: int, off: int):
    if off < 0:
        __dyn_err("ArgumentError", "'" + fn + "' : position négative")
    r := __syscall(8, fd, off, 0)
    if r < 0:
        __nat_io_fail(fn, __nat_errno_text(0 - r))

func __nat__native_io__pread(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("pread", n, 3)
    fd := __nat_int("pread", a, "le descripteur")
    off := __nat_int("pread", b, "la position")
    length := __nat_int("pread", c, "la longueur")
    if length < 0 or length > 268435456:
        __dyn_err("ArgumentError", "'pread' : longueur hors de 0..256 Mio")
    __nat_fd_pos("pread", fd, off)
    return __nat_bytes_list(__nat_read_fd(fd, length))

func __nat__native_io__pwrite(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("pwrite", n, 3)
    fd := __nat_int("pwrite", a, "le descripteur")
    off := __nat_int("pwrite", b, "la position")
    data := __nat_list_bytes("pwrite", c)
    __nat_fd_pos("pwrite", fd, off)
    if not __nat_write_fd(fd, data):
        __nat_io_fail("pwrite", "erreur d'écriture")
    return __dyn_int(__nat_blen(data))

func __nat__native_io__fsync(n: int, a: int) -> int:
    __nat_exact("fsync", n, 1)
    r := __syscall(74, __nat_int("fsync", a, "le descripteur"))
    if r < 0:
        __nat_io_fail("fsync", __nat_errno_text(0 - r))
    return 0

func __nat__native_io__fsize(n: int, a: int) -> int:
    __nat_exact("fsize", n, 1)
    r := __syscall(8, __nat_int("fsize", a, "le descripteur"), 0, 2)
    if r < 0:
        __nat_io_fail("fsize", __nat_errno_text(0 - r))
    return __dyn_int(r)

# CRC-32 (IEEE 802.3, celui de zlib) des octets l[a:z] d'une list d'entiers : sommes de contrôle des pages et des
# journaux, sur chaque lecture et écriture (2 ms par page de 4 Kio en ALEX interprété).
func __nat__native_io__crc32(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("crc32", n, 3)
    if not __dyn_is(a, 7):
        __dyn_err("TypeError", "'crc32' : list d'octets attendue (obtenu '" + __dyn_type_name(a) + "')")
    lo := __nat_int("crc32", b, "le début")
    hi := __nat_int("crc32", c, "la fin")
    if lo < 0 or hi < lo or hi > __dyn_list_len(a):
        __dyn_err("IndexError", "'crc32' : tranche [" + __int_to_str(lo) + ":" + __int_to_str(hi) + "] hors de la liste")
    p := __load64(__load64(a + 8) + 16)
    crc := 4294967295
    i := lo
    while i < hi:
        v := __load64(p + 8 * i)
        x := 0
        if __dyn_is(v, 1):
            x = __dyn_iv(v) & 255
        else:
            __dyn_err("TypeError", "'crc32' : octet non entier")
        crc = crc ^ x
        k := 0
        while k < 8:
            if (crc & 1) != 0:
                crc = (crc >> 1) ^ 3988292384
            else:
                crc = crc >> 1
            k += 1
        i += 1
    return __dyn_int((crc ^ 4294967295) & 4294967295)

func __nat__native_io__fclose(n: int, a: int) -> int:
    __nat_exact("fclose", n, 1)
    __syscall(3, __nat_int("fclose", a, "le descripteur"))
    return 0

func __nat__native_io__truncate(n: int, a: int, b: int) -> int:
    __nat_exact("truncate", n, 2)
    path := __nat_str("truncate", a, "le chemin")
    size := __nat_int("truncate", b, "la taille")
    if size < 0:
        __dyn_err("ArgumentError", "'truncate' : la taille doit être >= 0")
    __nat_fsize("truncate", path)
    r := __syscall(76, __nat_c(path), size)
    if r < 0:
        __nat_io_fail(__nat_ctx("truncate", path), __nat_errno_text(0 - r))
    return 0

func __nat__native_io__create_file(n: int, a: int) -> int:
    __nat_exact("create_file", n, 1)
    path := __nat_str("create_file", a, "le chemin")
    fd := __syscall(2, __nat_c(path), 193 + 524288, 438)
    if fd < 0:
        if fd == -17:
            __nat_io_fail(__nat_ctx("create_file", path), "le fichier existe déjà")
        __nat_io_fail(__nat_ctx("create_file", path), __nat_errno_text(0 - fd))
    __syscall(3, fd)
    return 0

# ---- _native_os -----------------------------------------------------------------------------------------------------

func __nat_uname(field: int) -> str:
    buf := __alloc_raw(390)
    __syscall(63, buf)
    return __nat_from_c(buf + 65 * field)

# ---- os.alex_build / alex_satisfies : version du compilateur qui a produit l'exécutable (src/Semver.cpp) ----

func __nat__native_os__alex_build(n: int) -> int:
    __nat_range("alex_build", n, 0, 0)
    f := __nat_split_bytes(__dyn_build_info(), 124)
    d := __dyn_dict_new()
    names := __nat_split_bytes("version|full|base|major|minor|patch|channel|build|date|source_id|commit|compiler|host", 124)
    nf := __load64(f)
    if nf > 13:
        nf = 13
    i := 0
    while i < nf:
        v := __as_str(__rt_vec_at(f, i))
        if i >= 3 and i <= 5 or i == 7:
            __nat_dict_put(d, __as_str(__rt_vec_at(names, i)), __dyn_int(__rt_str_to_int(v)))
        else:
            __nat_dict_put(d, __as_str(__rt_vec_at(names, i)), __dyn_str(v))
        i += 1
    return d

func __sv_digit(c: int) -> bool:
    return c >= 48 and c <= 57

func __sv_alnum(c: int) -> bool:
    return __sv_digit(c) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122)

func __sv_numeric(s: str) -> bool:
    n := __nat_blen(s)
    if n == 0:
        return false
    p := __nat_bp(s)
    i := 0
    while i < n:
        if not __sv_digit(__load8(p + i)):
            return false
        i += 1
    return true

func __sv_ids_ok(s: str, pre: bool) -> bool:
    if __nat_blen(s) == 0:
        return false
    ids := __nat_split_bytes(s, 46)
    i := 0
    while i < __load64(ids):
        id := __as_str(__rt_vec_at(ids, i))
        m := __nat_blen(id)
        if m == 0:
            return false
        p := __nat_bp(id)
        k := 0
        while k < m:
            c := __load8(p + k)
            if not (__sv_alnum(c) or c == 45):
                return false
            k += 1
        if pre and __sv_numeric(id) and m > 1 and __load8(p) == 48:
            return false
        i += 1
    return true

# Version : [0] majeur [8] mineur [16] correctif [24] pré-version (str) ; 0 si invalide.
func __sv_parse(s: str, minParts: int) -> int:
    v := __alloc(32)
    __store64(v + 24, __str_addr(""))
    p := __nat_bp(s)
    m := __nat_blen(s)
    pos := 0
    k := 0
    while k < 3:
        st := pos
        while pos < m and __sv_digit(__load8(p + pos)):
            pos += 1
        if pos == st or pos - st > 9:
            return 0
        __store64(v + 8 * k, __rt_str_to_int(__nat_sub(s, st, pos - st)))
        k += 1
        if pos < m and __load8(p + pos) == 46:
            pos += 1
            continue
        break
    if k < minParts:
        return 0
    if pos < m:
        if k != 3:
            return 0
        rest := __nat_sub(s, pos, m - pos)
        plus := __dyn_find_bytes(rest, "+", 0)
        head := rest
        if plus >= 0:
            head = __nat_sub(rest, 0, plus)
            if not __sv_ids_ok(__nat_sub(rest, plus + 1, __nat_blen(rest) - plus - 1), false):
                return 0
        if __nat_blen(head) > 0:
            if __load8(__nat_bp(head)) != 45:
                return 0
            pre := __nat_sub(head, 1, __nat_blen(head) - 1)
            if not __sv_ids_ok(pre, true):
                return 0
            __store64(v + 24, __str_addr(pre))
    return v

func __sv_cmp_str(a: str, b: str) -> int:
    if __rt_str_eq(a, b):
        return 0
    na := __nat_blen(a)
    nb := __nat_blen(b)
    pa := __nat_bp(a)
    pb := __nat_bp(b)
    i := 0
    while i < na and i < nb:
        if __load8(pa + i) != __load8(pb + i):
            if __load8(pa + i) < __load8(pb + i):
                return -1
            return 1
        i += 1
    if na < nb:
        return -1
    return 1

func __sv_cmp_pre(a: str, b: str) -> int:
    if __nat_blen(a) == 0 and __nat_blen(b) == 0:
        return 0
    if __nat_blen(a) == 0:
        return 1
    if __nat_blen(b) == 0:
        return -1
    xa := __nat_split_bytes(a, 46)
    xb := __nat_split_bytes(b, 46)
    i := 0
    while i < __load64(xa) and i < __load64(xb):
        sa := __as_str(__rt_vec_at(xa, i))
        sb := __as_str(__rt_vec_at(xb, i))
        na := __sv_numeric(sa)
        nb := __sv_numeric(sb)
        if na and nb:
            if __nat_blen(sa) != __nat_blen(sb):
                if __nat_blen(sa) < __nat_blen(sb):
                    return -1
                return 1
            c := __sv_cmp_str(sa, sb)
            if c != 0:
                return c
        elif na != nb:
            if na:
                return -1
            return 1
        else:
            c := __sv_cmp_str(sa, sb)
            if c != 0:
                return c
        i += 1
    if __load64(xa) != __load64(xb):
        if __load64(xa) < __load64(xb):
            return -1
        return 1
    return 0

func __sv_cmp(a: int, b: int) -> int:
    k := 0
    while k < 3:
        x := __load64(a + 8 * k)
        y := __load64(b + 8 * k)
        if x != y:
            if x < y:
                return -1
            return 1
        k += 1
    return __sv_cmp_pre(__as_str(__load64(a + 24)), __as_str(__load64(b + 24)))

func __sv_mk(a: int, b: int, c: int) -> int:
    v := __alloc(32)
    __store64(v, a)
    __store64(v + 8, b)
    __store64(v + 16, c)
    __store64(v + 24, __str_addr(""))
    return v

func __nat__native_os__alex_satisfies(n: int, a: int) -> int:
    __nat_range("alex_satisfies", n, 1, 1)
    if not __dyn_is_str(a):
        __dyn_err("TypeError", "alex_satisfies : contrainte (str) attendue")
    raw := __dyn_sv(a)
    sb := __rt_sb_new()
    rp := __nat_bp(raw)
    i := 0
    while i < __nat_blen(raw):
        c := __load8(rp + i)
        if not (c == 32 or (c >= 9 and c <= 13)):
            __rt_sb_byte(sb, c)
        i += 1
    s := __rt_sb_str(sb)
    if __rt_str_eq(s, "*"):
        return __dyn_bool(true)
    kind := 1 # 0 exact, 1 caret, 2 tilde, 3 >=
    rest := s
    m := __nat_blen(s)
    if m >= 2 and __load8(__nat_bp(s)) == 62 and __load8(__nat_bp(s) + 1) == 61:
        kind = 3
        rest = __nat_sub(s, 2, m - 2)
    elif m >= 1 and __load8(__nat_bp(s)) == 94:
        rest = __nat_sub(s, 1, m - 1)
    elif m >= 1 and __load8(__nat_bp(s)) == 126:
        kind = 2
        rest = __nat_sub(s, 1, m - 1)
    elif m >= 1 and __load8(__nat_bp(s)) == 61:
        kind = 0
        rest = __nat_sub(s, 1, m - 1)
    cv := __sv_parse(rest, 1)
    if cv == 0:
        __dyn_err("ArgumentError", "alex_satisfies : contrainte de version invalide : « " + raw + " »")
    v := __sv_parse(__as_str(__rt_vec_at(__nat_split_bytes(__dyn_build_info(), 124), 0)), 3)
    if v == 0:
        return __dyn_bool(false)
    r := __sv_cmp(v, cv)
    if kind == 0:
        return __dyn_bool(r == 0)
    if kind == 3:
        return __dyn_bool(r >= 0)
    up := 0
    if kind == 2:
        up = __sv_mk(__load64(cv), __load64(cv + 8) + 1, 0)
    elif __load64(cv) > 0:
        up = __sv_mk(__load64(cv) + 1, 0, 0)
    elif __load64(cv + 8) > 0:
        up = __sv_mk(0, __load64(cv + 8) + 1, 0)
    else:
        up = __sv_mk(0, 0, __load64(cv + 16) + 1)
    return __dyn_bool(r >= 0 and __sv_cmp(v, up) < 0)

func __nat__native_os__name(n: int) -> int:
    __nat_range("name", n, 0, 0)
    return __dyn_str(__nat_uname(0))

func __nat__native_os__platform(n: int) -> int:
    __nat_range("platform", n, 0, 0)
    if __windows():
        return __dyn_str("windows")
    return __dyn_str("linux")

func __nat__native_os__arch(n: int) -> int:
    __nat_range("arch", n, 0, 0)
    return __dyn_str(__nat_uname(4))

func __nat__native_os__version(n: int) -> int:
    __nat_range("version", n, 0, 0)
    return __dyn_str(__nat_uname(2))

func __nat__native_os__hostname(n: int) -> int:
    __nat_range("hostname", n, 0, 0)
    return __dyn_str(__nat_uname(1))

func __nat__native_os__user_id(n: int) -> int:
    __nat_range("user_id", n, 0, 0)
    if __windows():
        return 0
    return __dyn_int(__syscall(107))

func __nat__native_os__group_id(n: int) -> int:
    __nat_range("group_id", n, 0, 0)
    if __windows():
        return 0
    return __dyn_int(__syscall(108))

# Champ `field` (0 nom, 5 dossier) de l'entrée de /etc/passwd de l'utilisateur effectif, ou "".
func __nat_passwd(field: int) -> str:
    fd := __syscall(2, __nat_c("/etc/passwd"), 0)
    if fd < 0:
        return ""
    data := __nat_read_fd(fd, -1)
    __syscall(3, fd)
    uid := __int_to_str(__syscall(107))
    lines := __nat_split_bytes(data, 10)
    i := 0
    while i < __load64(lines):
        f := __nat_split_bytes(__as_str(__rt_vec_at(lines, i)), 58)
        if __load64(f) >= 7 and __rt_str_eq(__as_str(__rt_vec_at(f, 2)), uid):
            return __as_str(__rt_vec_at(f, field))
        i += 1
    return ""

# Découpe sur l'octet `sep` : liste native de chaînes natives.
func __nat_split_bytes(s: str, sep: int) -> int:
    out := __rt_list_new(0)
    p := __nat_bp(s)
    m := __nat_blen(s)
    st := 0
    i := 0
    while i <= m:
        if i == m or __load8(p + i) == sep:
            __rt_list_push(out, __str_addr(__nat_make(p + st, i - st)))
            st = i + 1
        i += 1
    return out

func __nat__native_os__username(n: int) -> int:
    __nat_range("username", n, 0, 0)
    if __windows():
        return __pw_username()
    u := __nat_passwd(0)
    if __nat_blen(u) == 0:
        u = __nat_env_get("LOGNAME", "")
    if __nat_blen(u) == 0:
        u = __nat_env_get("USER", "")
    if __nat_blen(u) == 0:
        return 0
    return __dyn_str(u)

func __nat__native_os__home(n: int) -> int:
    __nat_range("home", n, 0, 0)
    if __windows():
        hw := __nat_env_get("USERPROFILE", "")
        if __nat_blen(hw) == 0 and __nat_env_find("HOMEDRIVE") >= 0 and __nat_env_find("HOMEPATH") >= 0:
            hw = __nat_env_get("HOMEDRIVE", "") + __nat_env_get("HOMEPATH", "")
        if __nat_blen(hw) == 0:
            return 0
        return __dyn_str(hw)
    h := __nat_env_get("HOME", "")
    if __nat_blen(h) == 0:
        h = __nat_passwd(5)
    if __nat_blen(h) == 0:
        return 0
    return __dyn_str(h)

func __nat_is_dir(path: str) -> bool:
    return __nat_st_type(__nat_stat(path, false)) == 16384

func __nat__native_os__tmp_dir(n: int) -> int:
    __nat_range("tmp_dir", n, 0, 0)
    if __windows():
        return __pw_tmp_dir()
    p := ""
    names := "TMPDIR:TMP:TEMP:TEMPDIR"
    l := __nat_split_bytes(names, 58)
    i := 0
    while i < 4 and __nat_blen(p) == 0:
        p = __nat_env_get(__as_str(__rt_vec_at(l, i)), "")
        i += 1
    if __nat_blen(p) == 0:
        p = "/tmp"
    if not __nat_is_dir(p):
        __nat_io_fail("tmp_dir()", "Not a directory")
    return __dyn_str(p)

# Windows : GetTempPathW tel quel (barre oblique inverse finale comprise), comme temp_directory_path de libstdc++.
func __pw_tmp_dir() -> int:
    if __windows():
        w := __alloc_raw(2 * 32768 + 2)
        k := __rt_w32(__wincall("GetTempPathW", 32767, w))
        p := __pw_narrow(w, k)
        if k == 0 or not __nat_is_dir(p):
            __nat_io_fail("tmp_dir()", "Not a directory")
        return __dyn_str(p)
    return 0

func __nat_cwd() -> str:
    buf := __alloc_raw(4096)
    r := __syscall(79, buf, 4096)
    if r < 0:
        __nat_io_fail("cwd()", __nat_errno_text(0 - r))
    return __nat_from_c(buf)

func __nat__native_os__cwd(n: int) -> int:
    __nat_range("cwd", n, 0, 0)
    return __dyn_str(__nat_cwd())

func __nat__native_os__chdir(n: int, a: int) -> int:
    __nat_range("chdir", n, 1, 1)
    path := __nat_cstr("chdir", a, "le chemin")
    r := __syscall(80, __nat_c(path))
    if r < 0:
        __nat_io_fail(__nat_ctx("chdir", path), __nat_errno_text(0 - r))
    return 0

func __nat__native_os__cpu_count(n: int) -> int:
    __nat_range("cpu_count", n, 0, 0)
    if __windows():
        return __dyn_int(__pw_cpu_count())
    buf := __alloc_raw(128)
    __zero(buf, 128)
    r := __syscall(204, 0, 128, buf)
    k := 0
    if r > 0:
        i := 0
        while i < r:
            b := __load8(buf + i)
            while b != 0:
                k += b & 1
                b = b >> 1
            i += 1
    if k <= 0:
        k = 1
    return __dyn_int(k)

func __nat__native_os__total_memory(n: int) -> int:
    __nat_range("total_memory", n, 0, 0)
    if __windows():
        ms := __alloc_raw(72)
        __zero(ms, 72)
        __store32(ms, 64)
        if __rt_w32(__wincall("GlobalMemoryStatusEx", ms)) == 0:
            return 0
        return __dyn_int(__load64(ms + 8))
    buf := __alloc_raw(128)
    if __syscall(99, buf) != 0:
        return 0
    unit := __load32(buf + 104)
    if unit == 0:
        unit = 1
    pages := (__load64(buf + 32) * unit) // 4096
    if pages <= 0:
        return 0
    return __dyn_int(pages * 4096)

func __nat__native_os__exit(n: int, a: int) -> int:
    __nat_range("exit", n, 0, 1)
    code := 0
    if n == 1:
        code = __nat_int("exit", a, "le code de sortie")
    if code < 0 or code > 255:
        __dyn_err("ValueError", "exit : le code de sortie doit être compris entre 0 et 255 (obtenu " + __int_to_str(code) +
                  ")")
    __fd_restore_all()
    __flush()
    __exit(code)
    return 0

func __nat__native_os__process_args(n: int) -> int:
    __nat_range("process_args", n, 0, 0)
    sp := __argv_base()
    m := __load64(sp)
    out := __dyn_list_new(0)
    i := __dyn_argv_shift() # VM écrite en ALEX : « alexvm [options] prog.albc args... » -> [prog.albc, args...]
    while i < m:
        a := __nat_from_c(__load64(sp + 8 + 8 * i))
        if i == __dyn_argv_shift() and __nat_blen(__dyn_script()) > 0:
            a = __dyn_script() # comme `alexc run` : argv[0] est le script
        __dyn_list_push(out, __dyn_str(a))
        i += 1
    return out

# Environnement du processus : liste native de chaînes « nom=valeur » (dans l'état du mode dynamique, [72]),
# copiée de l'environnement initial au premier accès ; set_env / unset_env la modifient comme setenv / unsetenv.
func __nat_env() -> int:
    ds := __dyn_ds()
    l := __load64(ds + 72)
    if l != 0:
        return l
    l = __rt_list_new(0)
    sp := __argv_base()
    p := sp + 8 * (__load64(sp) + 2)
    while __load64(p) != 0:
        __rt_list_push(l, __str_addr(__nat_from_c(__load64(p))))
        p += 8
    __store64(ds + 72, l)
    return l

func __nat_fold(b: int) -> int:
    if __windows():
        return __nat_lower_b(b)
    return b

# Indice de la variable `name` dans l'environnement, ou -1.
func __nat_env_find(name: str) -> int:
    l := __nat_env()
    k := __nat_blen(name)
    q := __nat_bp(name)
    i := 0
    while i < __load64(l):
        e := __rt_vec_at(l, i)
        if __load64(e) > k and __load8(e + 8 + k) == 61:
            j := 0
            while j < k and __nat_fold(__load8(e + 8 + j)) == __nat_fold(__load8(q + j)):
                j += 1
            if j == k:
                return i
        i += 1
    return -1

func __nat_env_get(name: str, dflt: str) -> str:
    i := __nat_env_find(name)
    if i < 0:
        return dflt
    e := __as_str(__rt_vec_at(__nat_env(), i))
    k := __nat_blen(name)
    return __nat_sub(e, k + 1, __nat_blen(e) - k - 1)

func __nat__native_os__get_env(n: int, a: int, b: int) -> int:
    __nat_range("get_env", n, 1, 2)
    name := __nat_cstr("get_env", a, "le nom")
    i := __nat_env_find(name)
    if i >= 0:
        return __dyn_str(__nat_env_get(name, ""))
    if n == 2:
        return b
    return 0

func __nat_env_name_ok(name: str) -> bool:
    if __nat_blen(name) == 0:
        return false
    return __dyn_find_bytes(name, "=", 0) < 0

func __nat__native_os__set_env(n: int, a: int, b: int) -> int:
    __nat_range("set_env", n, 2, 2)
    name := __nat_cstr("set_env", a, "le nom")
    value := __nat_cstr("set_env", b, "la valeur")
    if not __nat_env_name_ok(name):
        __nat_io_fail(__nat_ctx("set_env", name), "Invalid argument")
    entry := __str_addr(name + "=" + value)
    l := __nat_env()
    i := __nat_env_find(name)
    if i >= 0:
        __store64(__load64(l + 16) + 8 * i, entry)
    else:
        __rt_list_push(l, entry)
    return 0

func __nat__native_os__unset_env(n: int, a: int) -> int:
    __nat_range("unset_env", n, 1, 1)
    name := __nat_cstr("unset_env", a, "le nom")
    if not __nat_env_name_ok(name):
        __nat_io_fail(__nat_ctx("unset_env", name), "Invalid argument")
    i := __nat_env_find(name)
    if i >= 0:
        __rt_vec_remove(__nat_env(), __rt_vec_at(__nat_env(), i))
    return 0

func __nat__native_os__env_list(n: int) -> int:
    __nat_range("env_list", n, 0, 0)
    l := __nat_env()
    out := __dyn_list_new(0)
    i := 0
    while i < __load64(l):
        e := __as_str(__rt_vec_at(l, i))
        eq := __dyn_find_bytes(e, "=", 0)
        if eq > 0:
            pair := __dyn_list_new(0)
            __dyn_list_push(pair, __dyn_str(__nat_sub(e, 0, eq)))
            __dyn_list_push(pair, __dyn_str(__nat_sub(e, eq + 1, __nat_blen(e) - eq - 1)))
            __dyn_list_push(out, pair)
        i += 1
    return out

func __nat__native_os__exists(n: int, a: int) -> int:
    __nat_range("exists", n, 1, 1)
    path := __nat_cstr("exists", a, "le chemin")
    return __dyn_bool(not __nat_st_failed(__nat_stat(path, false)))

func __nat__native_os__is_file(n: int, a: int) -> int:
    __nat_range("is_file", n, 1, 1)
    path := __nat_cstr("is_file", a, "le chemin")
    return __dyn_bool(__nat_st_type(__nat_stat(path, false)) == 32768)

func __nat__native_os__is_dir(n: int, a: int) -> int:
    __nat_range("is_dir", n, 1, 1)
    path := __nat_cstr("is_dir", a, "le chemin")
    return __dyn_bool(__nat_is_dir(path))

func __nat__native_os__is_link(n: int, a: int) -> int:
    __nat_range("is_link", n, 1, 1)
    path := __nat_cstr("is_link", a, "le chemin")
    return __dyn_bool(__nat_st_type(__nat_stat(path, true)) == 40960)

# stat suivi d'un IoError « ctx : raison » en cas d'échec.
func __nat_stat_or_fail(ctx: str, path: str) -> int:
    st := __nat_stat(path, false)
    if __nat_st_failed(st):
        __nat_io_fail(ctx, __nat_errno_text(__nat_st_errno(st)))
    return st

func __nat__native_os__size(n: int, a: int) -> int:
    __nat_range("size", n, 1, 1)
    path := __nat_cstr("size", a, "le chemin")
    c := __nat_ctx("size", path)
    st := __nat_stat_or_fail(c, path)
    if __nat_st_type(st) != 32768:
        __nat_io_fail(c, "n'est pas un fichier régulier")
    return __dyn_int(__load64(st + 48))

func __nat_time_of(fn: str, n: int, a: int, off: int) -> int:
    __nat_range(fn, n, 1, 1)
    path := __nat_cstr(fn, a, "le chemin")
    return __dyn_float(__nat_ts(__nat_stat_or_fail(__nat_ctx(fn, path), path), off))

func __nat__native_os__mtime(n: int, a: int) -> int:
    return __nat_time_of("mtime", n, a, 88)

func __nat__native_os__atime(n: int, a: int) -> int:
    return __nat_time_of("atime", n, a, 72)

func __nat__native_os__ctime(n: int, a: int) -> int:
    return __nat_time_of("ctime", n, a, 104)

func __nat__native_os__remove_file(n: int, a: int) -> int:
    __nat_range("remove_file", n, 1, 1)
    path := __nat_cstr("remove_file", a, "le chemin")
    c := __nat_ctx("remove", path)
    st := __nat_stat(path, true)
    if __nat_st_failed(st):
        __nat_io_fail(c, __nat_errno_text(__nat_st_errno(st)))
    if __nat_st_type(st) == 16384:
        __nat_io_fail(c, "est un dossier (utiliser rmdir)")
    if __windows():
        if __rt_w32(__wincall("DeleteFileW", __pw_wide(path))) == 0:
            __nat_io_fail(c, __pw_msg_ansi(__pw_last()))
        return 0
    r := __syscall(87, __nat_c(path))
    if r < 0:
        __nat_io_fail(c, __nat_errno_text(0 - r))
    return 0

func __nat__native_os__copy_file(n: int, a: int, b: int) -> int:
    __nat_range("copy_file", n, 2, 2)
    src := __nat_cstr("copy_file", a, "la source")
    dst := __nat_cstr("copy_file", b, "la destination")
    c := __nat_ctx2("copy", src, dst)
    st := __nat_stat_or_fail(c, src)
    if __nat_st_type(st) != 32768:
        __nat_io_fail(c, "Operation not supported")
    if __windows():
        if __pw_same_file(src, dst):
            __nat_io_fail(c, "File exists")
        if __rt_w32(__wincall("CopyFileW", __pw_wide(src), __pw_wide(dst), 0)) == 0:
            __nat_io_fail(c, __nat_errno_text(__rt_win_errno()))
        return 0
    dt := __nat_stat(dst, false)
    if not __nat_st_failed(dt) and __load64(dt) == __load64(st) and __load64(dt + 8) == __load64(st + 8):
        __nat_io_fail(c, "File exists")
    fd := __syscall(2, __nat_c(src), 0)
    if fd < 0:
        __nat_io_fail(c, __nat_errno_text(0 - fd))
    data := __nat_read_fd(fd, -1)
    __syscall(3, fd)
    out := __syscall(2, __nat_c(dst), 577, __load32(st + 24) & 4095)
    if out < 0:
        __nat_io_fail(c, __nat_errno_text(0 - out))
    ok := __nat_write_fd(out, data)
    __syscall(3, out)
    if not ok:
        __nat_io_fail(c, "Input/output error")
    return 0

func __nat__native_os__rename(n: int, a: int, b: int) -> int:
    __nat_range("rename", n, 2, 2)
    src := __nat_cstr("rename", a, "la source")
    dst := __nat_cstr("rename", b, "la destination")
    if __windows():
        if __rt_w32(__wincall("MoveFileExW", __pw_wide(src), __pw_wide(dst), 3)) != 0:
            return __dyn_bool(true)
        e := __rt_win_errno()
        if e == 18:
            return __dyn_bool(false)
        __nat_io_fail(__nat_ctx2("move", src, dst), __nat_errno_text(e))
    r := __syscall(82, __nat_c(src), __nat_c(dst))
    if r == 0:
        return __dyn_bool(true)
    if r == -18:
        return __dyn_bool(false)
    __nat_io_fail(__nat_ctx2("move", src, dst), __nat_errno_text(0 - r))
    return 0

func __nat__native_os__make_dir(n: int, a: int) -> int:
    __nat_range("make_dir", n, 1, 1)
    path := __nat_cstr("make_dir", a, "le chemin")
    r := __syscall(83, __nat_c(path), 511)
    if r < 0:
        __nat_io_fail(__nat_ctx("mkdir", path), __nat_errno_text(0 - r))
    return 0

func __nat__native_os__remove_dir(n: int, a: int) -> int:
    __nat_range("remove_dir", n, 1, 1)
    path := __nat_cstr("remove_dir", a, "le chemin")
    c := __nat_ctx("rmdir", path)
    st := __nat_stat(path, true)
    if __nat_st_failed(st):
        __nat_io_fail(c, __nat_errno_text(__nat_st_errno(st)))
    if __nat_st_type(st) != 16384:
        __nat_io_fail(c, "n'est pas un dossier")
    if __windows():
        # std::filesystem::remove (libstdc++) : RemoveDirectoryW, sinon DeleteFileW, dont l'erreur est rendue
        w := __pw_wide(path)
        if __rt_w32(__wincall("RemoveDirectoryW", w)) == 0 and __rt_w32(__wincall("DeleteFileW", w)) == 0:
            __nat_io_fail(c, __pw_msg_ansi(__pw_last()))
        return 0
    r := __syscall(84, __nat_c(path))
    if r < 0:
        __nat_io_fail(c, __nat_errno_text(0 - r))
    return 0

# Tri par insertion d'une liste native de chaînes natives (ordre des octets, comme std::sort sur std::string).
func __nat_sort_strs(l: int):
    d := __load64(l + 16)
    m := __load64(l)
    i := 1
    while i < m:
        x := __load64(d + 8 * i)
        j := i - 1
        while j >= 0 and __rt_str_cmp(__as_str(__load64(d + 8 * j)), __as_str(x)) > 0:
            __store64(d + 8 * (j + 1), __load64(d + 8 * j))
            j -= 1
        __store64(d + 8 * (j + 1), x)
        i += 1

func __nat__native_os__list_dir(n: int, a: int) -> int:
    __nat_range("list_dir", n, 1, 1)
    path := __nat_cstr("list_dir", a, "le chemin")
    c := __nat_ctx("list_dir", path)
    if __windows():
        return __nat_win_list_dir(c, path)
    fd := __syscall(2, __nat_c(path), 65536)
    if fd < 0:
        __nat_io_fail(c, __nat_errno_text(0 - fd))
    names := __rt_list_new(0)
    buf := __alloc_raw(32768)
    while true:
        k := __syscall(217, fd, buf, 32768)
        if k < 0:
            __syscall(3, fd)
            __nat_io_fail(c, __nat_errno_text(0 - k))
        if k == 0:
            break
        off := 0
        while off < k:
            reclen := __load16(buf + off + 16)
            nm := __nat_from_c(buf + off + 19)
            if not __rt_str_eq(nm, ".") and not __rt_str_eq(nm, ".."):
                __rt_list_push(names, __str_addr(nm))
            off += reclen
    __syscall(3, fd)
    __nat_sort_strs(names)
    return __nat_str_list(names)

# Windows : FindFirstFileW / FindNextFileW sur « chemin\* » (WIN32_FIND_DATAW : nom UTF-16 au décalage 44).
func __nat_win_list_dir(c: str, path: str) -> int:
    if __windows():
        pat := path
        k := __nat_blen(path)
        if k > 0:
            last := __load8(__nat_bp(path) + k - 1)
            if last != 47 and last != 92:
                pat = pat + "\\"
        pat = pat + "*"
        data := __alloc_raw(600)
        h := __wincall("FindFirstFileW", __rt_win_wide(__nat_c(pat)), data)
        if h == -1:
            __nat_io_fail(c, __nat_errno_text(__rt_win_errno()))
        names := __rt_list_new(0)
        buf := __alloc_raw(1100)
        while true:
            if __rt_w32(__wincall("WideCharToMultiByte", 65001, 0, data + 44, -1, buf, 1100, 0, 0)) > 0:
                nm := __nat_from_c(buf)
                if not __rt_str_eq(nm, ".") and not __rt_str_eq(nm, ".."):
                    __rt_list_push(names, __str_addr(nm))
            if __rt_w32(__wincall("FindNextFileW", h, data)) == 0:
                e := __rt_w32(__wincall("GetLastError"))
                __wincall("FindClose", h)
                if e != 18: # ERROR_NO_MORE_FILES
                    __nat_io_fail(c, __nat_errno_text(__rt_win_errno_of(e)))
                break
        __nat_sort_strs(names)
        return __nat_str_list(names)
    return 0

func __nat_absolute(path: str) -> str:
    if __windows():
        return __pw_full_path(path)
    if __nat_blen(path) > 0 and __load8(__nat_bp(path)) == 47:
        return path
    cwd := __nat_cwd()
    if __nat_blen(cwd) > 0 and __load8(__nat_bp(cwd) + __nat_blen(cwd) - 1) == 47:
        return cwd + path
    return cwd + "/" + path

func __nat__native_os__absolute_path(n: int, a: int) -> int:
    __nat_range("absolute_path", n, 1, 1)
    path := __nat_cstr("absolute_path", a, "le chemin")
    if __nat_blen(path) == 0:
        path = "."
    return __dyn_str(__nat_absolute(path))

# Chemin canonique d'un chemin existant (lien /proc/self/fd), ou "" en cas d'échec.
func __nat_canonical(path: str) -> str:
    fd := __syscall(2, __nat_c(path), 2097152) # O_PATH
    if fd < 0:
        return ""
    buf := __alloc_raw(4096)
    k := __syscall(89, __nat_c("/proc/self/fd/" + __int_to_str(fd)), buf, 4096)
    __syscall(3, fd)
    if k <= 0:
        return ""
    return __nat_make(buf, k)

# std::filesystem::weakly_canonical : partie existante canonique, reste normalisé lexicalement.
func __nat__native_os__real_path(n: int, a: int) -> int:
    __nat_range("real_path", n, 1, 1)
    path := __nat_cstr("real_path", a, "le chemin")
    if __nat_blen(path) == 0:
        path = "."
    if __windows():
        if path == "/proc/self/exe":
            mb := __alloc_raw(4104)
            mk := __rt_w32(__wincall("GetModuleFileNameW", 0, mb, 2048))
            if mk > 0:
                return __dyn_str(__pw_narrow(mb, mk))
        fw := __pw_full_path(path)
        k := __nat_blen(fw)
        if k > 3 and (__load8(__nat_bp(fw) + k - 1) == 92 or __load8(__nat_bp(fw) + k - 1) == 47):
            fw = __nat_sub(fw, 0, k - 1)
        return __dyn_str(fw)
    parts := __nat_split_bytes(__nat_absolute(path), 47)
    # plus long préfixe existant
    k := __load64(parts)
    best := ""
    bi := 0
    pre := ""
    i := 0
    while i < k:
        comp := __as_str(__rt_vec_at(parts, i))
        if __nat_blen(comp) > 0:
            pre = pre + "/" + comp
            if __nat_st_failed(__nat_stat(pre, false)):
                break
            bi = i + 1
        else:
            bi = i + 1
        i += 1
    if bi > 0:
        bp := ""
        j := 0
        while j < bi:
            comp := __as_str(__rt_vec_at(parts, j))
            if __nat_blen(comp) > 0:
                bp = bp + "/" + comp
            j += 1
        if __nat_blen(bp) == 0:
            bp = "/"
        best = __nat_canonical(bp)
        if __nat_blen(best) == 0:
            __nat_io_fail(__nat_ctx("realpath", path), "No such file or directory")
    out := __rt_list_new(0)
    if __nat_blen(best) > 0:
        bparts := __nat_split_bytes(best, 47)
        j := 0
        while j < __load64(bparts):
            comp := __as_str(__rt_vec_at(bparts, j))
            if __nat_blen(comp) > 0:
                __rt_list_push(out, __str_addr(comp))
            j += 1
    trailing := false
    j := bi
    while j < k:
        comp := __as_str(__rt_vec_at(parts, j))
        if __nat_blen(comp) == 0:
            if j == k - 1:
                trailing = true
        elif __rt_str_eq(comp, "."):
            trailing = true
        elif __rt_str_eq(comp, ".."):
            if __load64(out) > 0:
                __store64(out, __load64(out) - 1)
            trailing = true
        else:
            __rt_list_push(out, __str_addr(comp))
            trailing = false
        j += 1
    sb := __rt_sb_new()
    j = 0
    while j < __load64(out):
        __rt_sb_add(sb, "/")
        __rt_sb_add(sb, __as_str(__rt_vec_at(out, j)))
        j += 1
    r := __rt_sb_str(sb)
    if __nat_blen(r) == 0:
        r = "/"
    if trailing and not __rt_str_eq(r, "/"):
        r = r + "/"
    return __dyn_str(r)

func __nat__native_os__get_mode(n: int, a: int) -> int:
    __nat_range("get_mode", n, 1, 1)
    path := __nat_cstr("get_mode", a, "le chemin")
    st := __nat_stat_or_fail(__nat_ctx("permissions", path), path)
    return __dyn_int(__load32(st + 24) & 4095)

func __nat__native_os__set_mode(n: int, a: int, b: int) -> int:
    __nat_range("set_mode", n, 2, 2)
    path := __nat_cstr("set_mode", a, "le chemin")
    mode := __nat_int("set_mode", b, "le mode")
    if mode < 0 or mode > 4095:
        __dyn_err("ArgumentError", "'chmod' : mode hors limites (0..07777 = 0..4095)")
    if __windows():
        __pw_chmod(path, mode)
        return 0
    r := __syscall(90, __nat_c(path), mode)
    if r < 0:
        __nat_io_fail(__nat_ctx("chmod", path), __nat_errno_text(0 - r))
    return 0

func __nat__native_os__access(n: int, a: int, b: int) -> int:
    __nat_range("access", n, 2, 2)
    path := __nat_cstr("access", a, "le chemin")
    bits := __nat_int("access", b, "le mode")
    if bits < 0 or bits > 7:
        __dyn_err("ArgumentError", "'access' : mode invalide (attendu 0..7)")
    if __windows():
        return __dyn_bool(__pw_access(path, bits))
    return __dyn_bool(__syscall(21, __nat_c(path), bits) == 0)

func __nat_timespec(t: float, ts: int):
    whole := __rt_floor(t)
    __store64(ts, __f2i(whole))
    ns := __f2i((t - whole) * 1000000000.0)
    if ns < 0:
        ns = 0
    if ns > 999999999:
        ns = 999999999
    __store64(ts + 8, ns)

func __nat__native_os__set_times(n: int, a: int, b: int, c: int) -> int:
    __nat_range("set_times", n, 3, 3)
    path := __nat_cstr("set_times", a, "le chemin")
    if __windows():
        __pw_set_times(path, n, b, c)
        return 0
    ts := __alloc_raw(32)
    __store64(ts, 0)
    __store64(ts + 8, 1073741822) # UTIME_OMIT
    __store64(ts + 16, 0)
    __store64(ts + 24, 1073741822)
    if b != 0:
        __nat_timespec(__nat_number("set_times", b, "la date d'accès"), ts)
    if c != 0:
        __nat_timespec(__nat_number("set_times", c, "la date de modification"), ts + 16)
    r := __syscall(280, -100, __nat_c(path), ts, 0)
    if r < 0:
        __nat_io_fail(__nat_ctx("set_times", path), __nat_errno_text(0 - r))
    return 0

func __nat__native_os__pid(n: int) -> int:
    __nat_range("pid", n, 0, 0)
    return __dyn_int(__syscall(39))

func __nat__native_os__parent_pid(n: int) -> int:
    __nat_range("parent_pid", n, 0, 0)
    return __dyn_int(__syscall(110))

func __nat_clock(id: int) -> float:
    ts := __alloc_raw(16)
    __syscall(228, id, ts)
    return __i2f(__load64(ts) * 1000000000 + __load64(ts + 8)) / 1000000000.0

func __nat__native_os__time(n: int) -> int:
    __nat_range("time", n, 0, 0)
    return __dyn_float(__nat_clock(0))

func __nat__native_os__monotonic_time(n: int) -> int:
    __nat_range("monotonic_time", n, 0, 0)
    return __dyn_float(__nat_clock(1))

func __nat__native_os__sleep(n: int, a: int) -> int:
    __nat_range("sleep", n, 1, 1)
    s := __nat_number("sleep", a, "la durée")
    if not (s >= 0.0) or s == __bits2f(9218868437227405312):
        __dyn_err("ArgumentError", "'sleep' : durée négative, infinie ou invalide")
    __flush()
    target := __nat_clock(1) + s
    ts := __alloc_raw(16)
    while true:
        rem := target - __nat_clock(1)
        if rem <= 0.0:
            break
        if rem > 0.05:
            rem = 0.05
        if __sig_pending_auto():
            break
        __store64(ts, 0)
        __store64(ts + 8, __f2i(rem * 1000000000.0))
        __syscall(35, ts, 0)
    return 0

# Date civile d'un nombre de jours depuis 1970-01-01 (algorithme de H. Hinnant) : [année, mois, jour].
func __nat_civil(days: int, out: int):
    z := days + 719468
    era := z // 146097
    doe := z - era * 146097
    yoe := (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    y := yoe + era * 400
    doy := doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp := (5 * doy + 2) // 153
    d := doy - (153 * mp + 2) // 5 + 1
    m := mp + 3
    if mp >= 10:
        m = mp - 9
    if m <= 2:
        y += 1
    __store64(out, y)
    __store64(out + 8, m)
    __store64(out + 16, d)

# local_time : temps universel (fuseau « UTC », décalage 0 ; les fichiers de fuseau ne sont pas lus).
func __nat__native_os__local_time(n: int) -> int:
    __nat_range("local_time", n, 0, 0)
    now := __nat_clock(0)
    whole := __rt_floor(now)
    t := __f2i(whole)
    days := t // 86400
    secs := t - days * 86400
    cv := __alloc_raw(24)
    __nat_civil(days, cv)
    y := __load64(cv)
    leap := (y % 4 == 0 and y % 100 != 0) or y % 400 == 0
    starts := "0,31,59,90,120,151,181,212,243,273,304,334"
    l := __nat_split_bytes(starts, 44)
    m := __load64(cv + 8)
    yday := __rt_str_to_int(__as_str(__rt_vec_at(l, m - 1))) + __load64(cv + 16)
    if leap and m > 2:
        yday += 1
    d := __dyn_dict_new()
    __nat_dict_put(d, "year", __dyn_int(y))
    __nat_dict_put(d, "month", __dyn_int(m))
    __nat_dict_put(d, "day", __dyn_int(__load64(cv + 16)))
    __nat_dict_put(d, "hour", __dyn_int(secs // 3600))
    __nat_dict_put(d, "minute", __dyn_int((secs % 3600) // 60))
    __nat_dict_put(d, "second", __dyn_int(secs % 60))
    __nat_dict_put(d, "microsecond", __dyn_int(__f2i((now - whole) * 1000000.0)))
    __nat_dict_put(d, "weekday", __dyn_int((days % 7 + 10) % 7))
    __nat_dict_put(d, "yearday", __dyn_int(yday))
    __nat_dict_put(d, "utc_offset", __dyn_int(0))
    __nat_dict_put(d, "is_dst", __dyn_bool(false))
    __nat_dict_put(d, "timezone", __dyn_str("UTC"))
    __nat_dict_put(d, "timestamp", __dyn_float(now))
    return d

func __nat_isatty(fd: int) -> bool:
    if __windows():
        return __rt_win_console(__rt_win_handle(fd))
    buf := __alloc_raw(64)
    return __syscall(16, fd, 21505, buf) == 0 # TCGETS

func __nat__native_os__terminal(n: int) -> int:
    __nat_range("terminal", n, 0, 0)
    d := __dyn_dict_new()
    __nat_dict_put(d, "stdin", __dyn_bool(__nat_isatty(0)))
    __nat_dict_put(d, "stdout", __dyn_bool(__nat_isatty(1)))
    __nat_dict_put(d, "stderr", __dyn_bool(__nat_isatty(2)))
    cols := 0
    rows := 0
    if __windows():
        ci := __alloc_raw(32)
        k := 1
        while k <= 2:
            h := __rt_win_handle(k)
            if __rt_win_console(h) and __rt_w32(__wincall("GetConsoleScreenBufferInfo", h, ci)) != 0:
                cols = __load16(ci + 14) - __load16(ci + 10) + 1
                rows = __load16(ci + 16) - __load16(ci + 12) + 1
                break
            k += 1
        if cols > 0:
            __nat_dict_put(d, "columns", __dyn_int(cols))
        else:
            __nat_dict_put(d, "columns", 0)
        if rows > 0:
            __nat_dict_put(d, "rows", __dyn_int(rows))
        else:
            __nat_dict_put(d, "rows", 0)
        return d
    ws := __alloc_raw(8)
    fds := __alloc_raw(24)
    __store64(fds, 1)
    __store64(fds + 8, 2)
    __store64(fds + 16, 0)
    i := 0
    while i < 3:
        fd := __load64(fds + 8 * i)
        if __nat_isatty(fd) and __syscall(16, fd, 21523, ws) == 0 and __load16(ws + 2) > 0 and __load16(ws) > 0:
            cols = __load16(ws + 2)
            rows = __load16(ws)
            break
        i += 1
    if cols > 0:
        __nat_dict_put(d, "columns", __dyn_int(cols))
        __nat_dict_put(d, "rows", __dyn_int(rows))
    else:
        __nat_dict_put(d, "columns", 0)
        __nat_dict_put(d, "rows", 0)
    return d

# ---- _native_asyncio -------------------------------------------------------------------------------------------

func __nat_future(fn: str, v: int, label: str) -> int:
    if not __dyn_is(v, 15):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un futur ou une tâche (obtenu '" + __dyn_type_name(v) +
                  "')")
    return __load64(v + 8)

func __nat_delay(fn: str, v: int) -> float:
    t := __nat_number(fn, v, "le délai")
    if not (t >= 0.0):
        __dyn_err("ArgumentError", "'" + fn + "' : le délai doit être >= 0")
    return t

func __nat__native_asyncio__future(n: int) -> int:
    __nat_range("future", n, 0, 0)
    __rt_sched()
    return __dyn_future_box(__rt_future_new(""))

func __nat__native_asyncio__resolve(n: int, a: int, v: int) -> int:
    __nat_range("resolve", n, 2, 2)
    return __dyn_bool(__rt_resolve(__nat_future("resolve", a, "le futur"), v))

func __nat__native_asyncio__reject(n: int, a: int, b: int, c: int) -> int:
    __nat_range("reject", n, 3, 3)
    f := __nat_future("reject", a, "le futur")
    t := __nat_str("reject", b, "le type d'exception")
    m := __nat_str("reject", c, "le message")
    return __dyn_bool(__rt_reject(f, __rt_exc_new(t, m)))

func __nat__native_asyncio__cancel(n: int, a: int) -> int:
    __nat_range("cancel", n, 1, 1)
    return __dyn_bool(__rt_cancel(__nat_future("cancel", a, "l'argument")))

func __nat__native_asyncio__done(n: int, a: int) -> int:
    __nat_range("done", n, 1, 1)
    return __dyn_bool(__load64(__nat_future("done", a, "l'argument")) != 0)

func __nat__native_asyncio__cancelled(n: int, a: int) -> int:
    __nat_range("cancelled", n, 1, 1)
    return __dyn_bool(__load64(__nat_future("cancelled", a, "l'argument")) == 3)

func __nat__native_asyncio__failed(n: int, a: int) -> int:
    __nat_range("failed", n, 1, 1)
    return __dyn_bool(__load64(__nat_future("failed", a, "l'argument")) == 2)

func __nat__native_asyncio__result(n: int, a: int) -> int:
    __nat_range("result", n, 1, 1)
    f := __nat_future("result", a, "l'argument")
    if __load64(f) != 1:
        __dyn_err("ArgumentError", "'result' : le futur n'est pas terminé avec succès (utilisez await)")
    return __load64(f + 8)

func __nat__native_asyncio__abandoned(n: int, a: int) -> int:
    __nat_range("abandoned", n, 1, 1)
    return __dyn_bool(__rt_abandoned(__nat_future("abandoned", a, "l'argument")))

func __nat__native_asyncio__is_future(n: int, a: int) -> int:
    __nat_range("is_future", n, 1, 1)
    return __dyn_bool(__dyn_is(a, 15))

func __nat__native_asyncio__is_task(n: int, a: int) -> int:
    __nat_range("is_task", n, 1, 1)
    return __dyn_bool(__dyn_is(a, 15) and __load64(__load64(a + 8) + 40) != 0)

func __nat__native_asyncio__sleep(n: int, a: int) -> int:
    __nat_range("sleep", n, 1, 1)
    __rt_sched()
    return __dyn_future_box(__rt_sleep(__nat_delay("sleep", a)))

func __nat__native_asyncio__timeout(n: int, a: int, b: int) -> int:
    __nat_range("timeout", n, 2, 2)
    f := __nat_future("timeout", a, "le futur")
    return __dyn_future_box(__rt_timeout(f, __nat_delay("timeout", b)))

func __nat__native_asyncio__race(n: int, a: int) -> int:
    __nat_range("race", n, 1, 1)
    if not __dyn_is(a, 7):
        __dyn_err("TypeError", "'race' : l'argument doit être une liste de futurs (obtenu '" + __dyn_type_name(a) + "')")
    fs := __rt_list_new(0)
    i := 0
    while i < __dyn_list_len(a):
        __rt_list_push(fs, __nat_future("race", __dyn_list_at(a, i), "chaque élément"))
        i += 1
    if __load64(fs) == 0:
        __dyn_err("ArgumentError", "'race' : la liste ne doit pas être vide")
    return __dyn_future_box(__rt_race(fs))

func __nat__native_asyncio__now(n: int) -> int:
    __nat_range("now", n, 0, 0)
    return __dyn_float(__rt_now())

# ---- _native_cli -------------------------------------------------------------------------------------------------

func __nat__native_cli__exit(n: int, a: int) -> int:
    __nat_range("exit", n, 1, 1)
    code := __nat_int("exit", a, "le code")
    if code < 0 or code > 255:
        __dyn_err("ArgumentError", "'exit' : code hors limites (0..255)")
    __fd_restore_all()
    __flush()
    __exit(code)
    return 0

func __nat__native_cli__write_out(n: int, a: int) -> int:
    __nat_range("write_out", n, 1, 1)
    s := __nat_str("write_out", a, "le texte")
    __flush()
    __nat_write_fd(1, s)
    return 0

func __nat__native_cli__write_err(n: int, a: int) -> int:
    __nat_range("write_err", n, 1, 1)
    s := __nat_str("write_err", a, "le texte")
    __flush()
    __nat_write_fd(2, s)
    return 0

func __nat__native_cli__flush(n: int) -> int:
    __nat_range("flush", n, 0, 0)
    __flush()
    return 0

# Mode texte des flux standard sous Windows (LF <-> CR LF, Ctrl+Z = fin) : text_mode(false) les passe en binaire,
# comme _setmode(_O_BINARY), pour écrire ou lire des octets bruts. Rend l'état précédent ; sans effet ailleurs.
func __nat__native_cli__text_mode(n: int, a: int) -> int:
    __nat_range("text_mode", n, 1, 1)
    if not __windows():
        return __dyn_bool(false)
    __flush()
    old := __load64(__state() + 1600) != 0
    __store64(__state() + 1600, 1 if __dyn_truthy(a) else 0)
    return __dyn_bool(old)

# ---- _native_hwsim : RAM physique simulée (pages de 4 Kio créées à la première écriture) -----------------------
# Machine (état du mode dynamique, [88]) : [0] taille [8] début du tas [16] pages (dict natif page -> zone)
# [24] adresses des plages libres (liste native triée) [32] leurs nombres de pages [40] allocations (adresse -> pages)
# [48] initialisée.

func __hw_m() -> int:
    ds := __dyn_ds()
    m := __load64(ds + 88)
    if m == 0:
        m = __alloc(56)
        __store64(m, 67108864)
        __store64(m + 8, 16777216)
        __store64(ds + 88, m)
    if __load64(m + 48) == 0:
        __hw_reset(m, __load64(m), __load64(m + 8))
    return m

func __hw_reset(m: int, sz: int, start: int):
    __store64(m, sz)
    __store64(m + 8, start)
    __store64(m + 16, __rt_dict_new(16))
    __store64(m + 24, __rt_list_new(0))
    __store64(m + 32, __rt_list_new(0))
    __store64(m + 40, __rt_dict_new(16))
    if start < sz:
        __rt_list_push(__load64(m + 24), start)
        __rt_list_push(__load64(m + 32), (sz - start) // 4096)
    __store64(m + 48, 1)

func __hw_fail(msg: str):
    __dyn_err("MemoryError", "hw (simulé) : " + msg)

func __hw_check(m: int, addr: int, n: int, what: str):
    sz := __load64(m)
    if __rt_ule(sz + 1, addr) or __rt_ule(sz - addr + 1, n):
        __hw_fail(what + " hors de la RAM simulée (adresse " + __int_to_str(addr) + ", " + __int_to_str(n) +
                  " octet(s), RAM de " + __int_to_str(sz) + " octets)")

func __hw_addr(fn: str, v: int) -> int:
    a := __nat_int(fn, v, "l'adresse")
    if a < 0:
        __hw_fail(fn + " : adresse négative")
    return a

# Zone de la page p (0 si absente et create faux).
func __hw_page(m: int, p: int, create: bool) -> int:
    d := __load64(m + 16)
    e := __rt_dict_index(d, p, 0)
    if e >= 0:
        return __load64(__load64(d + 32) + 8 * e)
    if not create:
        return 0
    z := __alloc_raw(4096)
    __zero(z, 4096)
    __rt_dict_set(d, p, z, 0)
    return z

func __hw_read_into(m: int, addr: int, out: int, n: int):
    while n > 0:
        p := addr // 4096
        off := addr % 4096
        k := 4096 - off
        if n < k:
            k = n
        z := __hw_page(m, p, false)
        if z != 0:
            __copy(out, z + off, k)
        else:
            __zero(out, k)
        addr += k
        out += k
        n -= k

func __hw_write_from(m: int, addr: int, src: int, n: int):
    while n > 0:
        p := addr // 4096
        off := addr % 4096
        k := 4096 - off
        if n < k:
            k = n
        __copy(__hw_page(m, p, true) + off, src, k)
        addr += k
        src += k
        n -= k

func __hw_size_arg(fn: str, v: int) -> int:
    s := __nat_int(fn, v, "la taille")
    if s != 1 and s != 2 and s != 4 and s != 8:
        __dyn_err("ArgumentError", "'" + fn + "' : taille 1, 2, 4 ou 8 attendue")
    return s

func __nat__native_hwsim__reset(n: int, a: int, b: int) -> int:
    __nat_range("reset", n, 2, 2)
    sz := __nat_int("reset", a, "la taille")
    start := __nat_int("reset", b, "le début du tas")
    if sz <= 0 or sz % 4096 != 0 or start < 0 or start % 4096 != 0 or start > sz:
        __dyn_err("ArgumentError", "'reset' : tailles multiples de 4096, 0 <= début <= taille")
    m := __hw_m()
    __hw_reset(m, sz, start)
    return 0

func __nat__native_hwsim__size(n: int) -> int:
    __nat_range("size", n, 0, 0)
    return __dyn_int(__load64(__hw_m()))

func __nat__native_hwsim__read(n: int, a: int, b: int) -> int:
    __nat_range("read", n, 2, 2)
    addr := __hw_addr("read", a)
    k := __hw_size_arg("read", b)
    m := __hw_m()
    __hw_check(m, addr, k, "lecture")
    buf := __alloc_raw(8)
    __store64(buf, 0)
    __hw_read_into(m, addr, buf, k)
    return __dyn_int(__load64(buf))

func __nat__native_hwsim__write(n: int, a: int, b: int, c: int) -> int:
    __nat_range("write", n, 3, 3)
    addr := __hw_addr("write", a)
    k := __hw_size_arg("write", b)
    v := __nat_int("write", c, "la valeur")
    m := __hw_m()
    __hw_check(m, addr, k, "écriture")
    buf := __alloc_raw(8)
    __store64(buf, v)
    __hw_write_from(m, addr, buf, k)
    return 0

func __nat__native_hwsim__read_bytes(n: int, a: int, b: int) -> int:
    __nat_range("read_bytes", n, 2, 2)
    addr := __hw_addr("read_bytes", a)
    k := __nat_int("read_bytes", b, "la longueur")
    if k < 0:
        __dyn_err("ArgumentError", "'read_bytes' : longueur négative")
    m := __hw_m()
    __hw_check(m, addr, k, "lecture")
    r := __rt_str_new(k)
    __hw_read_into(m, addr, r + 8, k)
    return __dyn_str(__as_str(r))

func __nat__native_hwsim__write_bytes(n: int, a: int, b: int) -> int:
    __nat_range("write_bytes", n, 2, 2)
    addr := __hw_addr("write_bytes", a)
    s := __nat_str("write_bytes", b, "les octets")
    m := __hw_m()
    __hw_check(m, addr, __nat_blen(s), "écriture")
    __hw_write_from(m, addr, __nat_bp(s), __nat_blen(s))
    return __dyn_int(__nat_blen(s))

func __nat__native_hwsim__copy(n: int, a: int, b: int, c: int) -> int:
    __nat_range("copy", n, 3, 3)
    dst := __hw_addr("copy", a)
    src := __hw_addr("copy", b)
    k := __nat_int("copy", c, "la longueur")
    if k < 0:
        __dyn_err("ArgumentError", "'copy' : longueur négative")
    m := __hw_m()
    __hw_check(m, src, k, "copie (source)")
    __hw_check(m, dst, k, "copie (destination)")
    tmp := __alloc_raw(k + 8)
    __hw_read_into(m, src, tmp, k)
    __hw_write_from(m, dst, tmp, k)
    return 0

func __nat__native_hwsim__fill(n: int, a: int, b: int, c: int) -> int:
    __nat_range("fill", n, 3, 3)
    addr := __hw_addr("fill", a)
    k := __nat_int("fill", b, "la longueur")
    v := __nat_int("fill", c, "l'octet")
    if k < 0:
        __dyn_err("ArgumentError", "'fill' : longueur négative")
    m := __hw_m()
    __hw_check(m, addr, k, "remplissage")
    tmp := __alloc_raw(k + 8)
    i := 0
    while i < k:
        __store8(tmp + i, v & 255)
        i += 1
    __hw_write_from(m, addr, tmp, k)
    return 0

func __hw_list_insert(l: int, i: int, v: int):
    __rt_list_push(l, 0)
    d := __load64(l + 16)
    j := __load64(l) - 1
    while j > i:
        __store64(d + 8 * j, __load64(d + 8 * j - 8))
        j -= 1
    __store64(d + 8 * i, v)

func __hw_list_del(l: int, i: int):
    d := __load64(l + 16)
    m := __load64(l)
    j := i
    while j + 1 < m:
        __store64(d + 8 * j, __load64(d + 8 * j + 8))
        j += 1
    __store64(l, m - 1)

func __nat__native_hwsim__alloc(n: int, a: int) -> int:
    __nat_range("alloc", n, 1, 1)
    k := __nat_int("alloc", a, "le nombre de pages")
    if k < 1:
        __dyn_err("ArgumentError", "'alloc' : au moins une page")
    m := __hw_m()
    fa := __load64(m + 24)
    fc := __load64(m + 32)
    i := 0
    while i < __load64(fa):
        cnt := __rt_vec_at(fc, i)
        if cnt >= k:
            addr := __rt_vec_at(fa, i)
            left := cnt - k
            __hw_list_del(fa, i)
            __hw_list_del(fc, i)
            if left > 0:
                __hw_list_insert(fa, i, addr + k * 4096)
                __hw_list_insert(fc, i, left)
            __rt_dict_set(__load64(m + 40), addr, k, 0)
            p := 0
            pd := __load64(m + 16)
            while p < k:
                if __rt_dict_index(pd, addr // 4096 + p, 0) >= 0:
                    __rt_dict_remove(pd, addr // 4096 + p, 0)
                p += 1
            return __dyn_int(addr)
        i += 1
    return __dyn_int(-1)

func __nat__native_hwsim__free(n: int, a: int, b: int) -> int:
    __nat_range("free", n, 2, 2)
    addr := __hw_addr("free", a)
    k := __nat_int("free", b, "le nombre de pages")
    m := __hw_m()
    used := __load64(m + 40)
    e := __rt_dict_index(used, addr, 0)
    if e < 0 or __load64(__load64(used + 32) + 8 * e) != k:
        __hw_fail("free_pages(" + __int_to_str(addr) + ", " + __int_to_str(k) + ") ne correspond à aucune allocation")
    __rt_dict_remove(used, addr, 0)
    fa := __load64(m + 24)
    fc := __load64(m + 32)
    start := addr
    count := k
    # position d'insertion (lower_bound)
    i := 0
    while i < __load64(fa) and __rt_vec_at(fa, i) < start:
        i += 1
    if i > 0 and __rt_vec_at(fa, i - 1) + __rt_vec_at(fc, i - 1) * 4096 == start:
        start = __rt_vec_at(fa, i - 1)
        count += __rt_vec_at(fc, i - 1)
        __hw_list_del(fa, i - 1)
        __hw_list_del(fc, i - 1)
        i -= 1
    if i < __load64(fa) and __rt_vec_at(fa, i) == addr + k * 4096:
        count += __rt_vec_at(fc, i)
        __hw_list_del(fa, i)
        __hw_list_del(fc, i)
    __hw_list_insert(fa, i, start)
    __hw_list_insert(fc, i, count)
    return 0

func __nat__native_hwsim__allocated(n: int) -> int:
    __nat_range("allocated", n, 0, 0)
    vals := __rt_dict_list(__load64(__hw_m() + 40), 32)
    t := 0
    i := 0
    while i < __load64(vals):
        t += __rt_vec_at(vals, i)
        i += 1
    return __dyn_int(t)

func __nat__native_hwsim__cas(n: int, a: int, b: int, c: int) -> int:
    __nat_range("cas", n, 3, 3)
    addr := __hw_addr("cas", a)
    m := __hw_m()
    __hw_check(m, addr, 8, "cas")
    buf := __alloc_raw(8)
    __hw_read_into(m, addr, buf, 8)
    old := __load64(buf)
    if old == __nat_int("cas", b, "la valeur attendue"):
        __store64(buf, __nat_int("cas", c, "la nouvelle valeur"))
        __hw_write_from(m, addr, buf, 8)
    return __dyn_int(old)

func __nat__native_hwsim__xadd(n: int, a: int, b: int) -> int:
    __nat_range("xadd", n, 2, 2)
    addr := __hw_addr("xadd", a)
    m := __hw_m()
    __hw_check(m, addr, 8, "xadd")
    buf := __alloc_raw(8)
    __hw_read_into(m, addr, buf, 8)
    old := __load64(buf)
    __store64(buf, old + __nat_int("xadd", b, "la valeur"))
    __hw_write_from(m, addr, buf, 8)
    return __dyn_int(old)

func __nat__native_hwsim__pages(n: int) -> int:
    __nat_range("pages", n, 0, 0)
    return __dyn_int(__load64(__load64(__hw_m() + 16)))

# ---- Utilitaires : délais, listes d'arguments ---------------------------------------------------------------

# Délai optionnel (null : sans limite -> -1.0), comme args::optTimeout de la VM.
func __nat_timeout(fn: str, v: int) -> float:
    if v == 0:
        return -1.0
    t := __nat_number(fn, v, "le délai")
    if not (t >= 0.0) or t > 1000000000.0:
        __dyn_err("ArgumentError", "'" + fn + "' : délai négatif, infini ou invalide")
    return t

# Échéance (horloge monotone) d'un délai, -1.0 si aucun.
func __nat_deadline(t: float) -> float:
    if t < 0.0:
        return -1.0
    return __nat_clock(1) + t

func __nat_remaining_ms(end: float) -> int:
    if end < 0.0:
        return -1
    left := (end - __nat_clock(1)) * 1000.0
    if left <= 0.0:
        return 0
    if left > 2000000000.0:
        return 2000000000
    return __f2i(left)

# Éléments d'une list ou d'un tuple (liste native de valeurs).
func __nat_items(fn: str, v: int, label: str, expected: str) -> int:
    out := __rt_list_new(0)
    if __dyn_is(v, 7):
        i := 0
        while i < __dyn_list_len(v):
            __rt_list_push(out, __dyn_list_at(v, i))
            i += 1
        return out
    if __dyn_is(v, 8):
        i := 0
        while i < __dyn_tuple_len(v):
            __rt_list_push(out, __dyn_tuple_at(v, i))
            i += 1
        return out
    __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être " + expected + " (obtenu '" + __dyn_type_name(v) + "')")
    return out

func __nat_bool(fn: str, v: int, label: str) -> bool:
    if not __dyn_is(v, 3):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un bool (obtenu '" + __dyn_type_name(v) + "')")
    return __load64(v + 8) != 0

func __nat_int_list(l: int) -> int: # liste native d'entiers -> valeur list[int]
    out := __dyn_list_new(0)
    i := 0
    while i < __load64(l):
        __dyn_list_push(out, __dyn_int(__rt_vec_at(l, i)))
        i += 1
    return out

func __nat_errno_name(e: int) -> str:
    names := "1:EPERM,2:ENOENT,3:ESRCH,4:EINTR,5:EIO,6:ENXIO,9:EBADF,11:EAGAIN,12:ENOMEM,13:EACCES,16:EBUSY,17:EEXIST,19:ENODEV,20:ENOTDIR,21:EISDIR,22:EINVAL,25:ENOTTY,28:ENOSPC,30:EROFS,32:EPIPE,38:ENOSYS,71:EPROTO,75:EOVERFLOW,108:ESHUTDOWN,110:ETIMEDOUT,111:ECONNREFUSED"
    l := __nat_split_bytes(names, 44)
    i := 0
    while i < __load64(l):
        it := __as_str(__rt_vec_at(l, i))
        c := __dyn_find_bytes(it, ":", 0)
        if __rt_str_eq(__nat_sub(it, 0, c), __int_to_str(e)):
            return __nat_sub(it, c + 1, __nat_blen(it) - c - 1)
        i += 1
    return "E" + __int_to_str(e)

# ---- _native_fd : descripteurs, tubes nommés, terminal, poll, inotify ---------------------------------------
# État (état du mode dynamique, [96]) : [0] descripteurs créés par ce module (dict natif fd -> 1)
# [8] réglages d'origine des terminaux modifiés (dict natif fd -> termios de 64 octets).

func __fd_st() -> int:
    ds := __dyn_ds()
    s := __load64(ds + 96)
    if s == 0:
        s = __alloc(24)
        __store64(s, __rt_dict_new(8))
        __store64(s + 8, __rt_dict_new(4))
        __store64(s + 16, __rt_dict_new(4)) # Windows : pid -> poignée des fils de os.spawn (__pw_os_wait)
        __store64(ds + 96, s)
    return s

func __fd_own(fd: int):
    __rt_dict_set(__load64(__fd_st()), fd, 1, 0)

func __fd_arg(fn: str, v: int) -> int:
    fd := __nat_int(fn, v, "le descripteur")
    if fd < 0 or fd > 1000000:
        __dyn_err("ArgumentError", "'" + fn + "' : descripteur invalide")
    return fd

# Fin du programme : terminaux rendus dans leur état d'origine.
func __fd_restore_all():
    s := __load64(__dyn_ds() + 96)
    if s == 0:
        return
    d := __load64(s + 8)
    used := __load64(d + 8)
    e := 0
    while e < used:
        if __load64(__load64(d + 40) + 8 * e) >= 0:
            if __windows():
                __fdw_restore(__load64(__load64(d + 24) + 8 * e), __load64(__load64(d + 32) + 8 * e))
            else:
                __syscall(16, __load64(__load64(d + 24) + 8 * e), 21506, __load64(__load64(d + 32) + 8 * e)) # TCSETS
        e += 1

func __nat__native_fd__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    return __dyn_bool(not __windows())

func __nat__native_fd__pipe(n: int) -> int:
    __fd_win_off()
    __nat_range("pipe", n, 0, 0)
    p := __alloc_raw(8)
    r := __syscall(293, p, 524288) # pipe2(O_CLOEXEC)
    if r < 0:
        __dyn_err("IoError", "pipe : " + __nat_errno_text(0 - r))
    a := __load32(p)
    b := __load32(p + 4)
    __fd_own(a)
    __fd_own(b)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(a))
    __dyn_list_push(l, __dyn_int(b))
    return l

# ---- Windows : sous-ensemble de _native_fd (chaîne d'outils : alexc repl, debug, lsp) ----------------------------
# read / write / close sur 0, 1, 2 et sur les tubes de open_fifo. Un « fifo » est un tube nommé Windows (chemin
# \\.\pipe\...) : mkfifo ne crée rien (le nom n'est pas un fichier), open_fifo crée l'extrémité serveur en mode
# non bloquant (PIPE_NOWAIT) et rend la main sans attendre le client ; read et write attendent sa connexion (la VM
# ouvre le même nom par CreateFileW) puis les données, par sondage (PeekNamedPipe), dans le délai demandé. Les
# deux extrémités peuvent ainsi s'ouvrir dans n'importe quel ordre.

func __fdw_pipe_name(path: str) -> bool:
    return __nat_blen(path) > 9 and __nat_sub(path, 0, 9) == "\\\\.\\pipe\\"

func __fdw_wait(end: float) -> bool:
    if __windows():
        if __nat_remaining_ms(end) == 0:
            return false
        __wincall("Sleep", 2)
        return true
    return false

func __fdw_open_fifo(path: str) -> int:
    if __windows():
        if not __fdw_pipe_name(path):
            return __dyn_int(-22)
        # PIPE_ACCESS_DUPLEX | FILE_FLAG_FIRST_PIPE_INSTANCE ; octets, PIPE_NOWAIT ; une seule instance
        h := __wincall("CreateNamedPipeW", __pw_wide(path), 3 | 524288, 1, 1, 65536, 65536, 0, 0)
        if h == -1 or h == 0:
            return __dyn_int(0 - __rt_win_errno())
        __wincall("ConnectNamedPipe", h, 0) # mode non bloquant : arme l'écoute, rend la main aussitôt
        __fd_own(h)
        return __dyn_int(h)
    return 0

# Lecture : données (str), "" en fin de flux, null (0) à l'échéance, -errno en cas d'erreur.
func __fdw_read(fd: int, mx: int, end: float) -> int:
    if __windows():
        h := __rt_win_handle(fd)
        buf := __alloc_raw(mx)
        got := __alloc_raw(8)
        kind := __rt_w32(__wincall("GetFileType", h))
        while true:
            if kind == 3: # tube (anonyme ou nommé)
                __store64(got, 0)
                if __rt_w32(__wincall("PeekNamedPipe", h, 0, 0, 0, got, 0)) != 0:
                    avail := __load32(got)
                    if avail > 0:
                        if avail > mx:
                            avail = mx
                        __store64(got, 0)
                        if __rt_w32(__wincall("ReadFile", h, buf, avail, got, 0)) != 0:
                            return __dyn_str(__nat_make(buf, __rt_w32(__load64(got))))
                        e := __rt_w32(__wincall("GetLastError"))
                        if e == 109 or e == 233:
                            return __dyn_str("")
                        if e != 232:
                            return __dyn_int(0 - __rt_win_errno_of(e))
                else:
                    e := __rt_w32(__wincall("GetLastError"))
                    if e == 109 or e == 233: # client parti : fin du flux
                        return __dyn_str("")
                    if e != 536 and e != 230 and e != 232: # 536, 230 : pas encore de client ; 232 : rien à lire
                        return __dyn_int(0 - __rt_win_errno_of(e))
            elif kind == 2 and fd == 0: # console
                ms := __nat_remaining_ms(end)
                if ms < 0:
                    ms = 4294967295
                w := __rt_w32(__wincall("WaitForSingleObject", h, ms))
                if w == 258:
                    return 0
                if __fdw_console_char(h):
                    k := __fdw_read_console(h, buf, mx)
                    if k < 0:
                        return __dyn_int(k)
                    return __dyn_str(__nat_make(buf, k))
                if __nat_remaining_ms(end) == 0:
                    return 0
                continue
            else: # fichier : lecture directe
                k := __rt_win_read_raw(fd, buf, mx)
                if k < 0:
                    return __dyn_int(k)
                return __dyn_str(__nat_make(buf, k))
            if not __fdw_wait(end):
                return 0
    return 0

# Écriture complète (ou partielle à l'échéance) ; nombre d'octets, -errno en cas d'erreur.
func __fdw_write(fd: int, p: int, m: int, end: float) -> int:
    if __windows():
        if fd == 1 or fd == 2:
            done := 0
            while done < m:
                k := __rt_win_write(fd, p + done, m - done)
                if k < 0:
                    return __dyn_int(k)
                if k == 0:
                    return __dyn_int(-5)
                done += k
            return __dyn_int(done)
        h := __rt_win_handle(fd)
        got := __alloc_raw(8)
        done := 0
        while done < m:
            __store64(got, 0)
            if __rt_w32(__wincall("WriteFile", h, p + done, m - done, got, 0)) != 0:
                k := __rt_w32(__load64(got))
                if k > 0:
                    done += k
                    continue
            else:
                e := __rt_w32(__wincall("GetLastError"))
                if e == 232 or e == 109 or e == 233:
                    return __dyn_int(-32) # EPIPE : le client est parti
                if e != 536 and e != 230:
                    return __dyn_int(0 - __rt_win_errno_of(e))
            if not __fdw_wait(end): # pas encore de client, ou tube plein
                if done > 0:
                    return __dyn_int(done)
                return __dyn_int(-110)
        return __dyn_int(done)
    return 0

# Console en mode brut (tui, éditeur) : modes d'origine gardés une fois ([entrée][sortie], -1 sans console de
# sortie), puis entrée sans ligne ni Ctrl+C traité (ENABLE_LINE_INPUT, ENABLE_PROCESSED_INPUT), sans écho, en
# séquences VT (ENABLE_VIRTUAL_TERMINAL_INPUT) et sans QuickEdit (la souris arrive au programme) ; sortie qui
# interprète les séquences VT (ENABLE_VIRTUAL_TERMINAL_PROCESSING).
func __fdw_set_mode(fd: int, raw: bool, echo: bool) -> bool:
    if __windows():
        hin := __rt_win_handle(fd)
        hout := __wincall("GetStdHandle", -11)
        m := __alloc_raw(8)
        __store64(m, 0)
        if __rt_w32(__wincall("GetConsoleMode", hin, m)) == 0:
            return false
        saved := __load64(__fd_st() + 8)
        e := __rt_dict_index(saved, fd, 0)
        keep := 0
        if e < 0:
            keep = __alloc_raw(16)
            __store64(keep, __load32(m))
            __store64(keep + 8, -1)
            __store64(m, 0)
            if __rt_w32(__wincall("GetConsoleMode", hout, m)) != 0:
                __store64(keep + 8, __load32(m))
            __rt_dict_set(saved, fd, keep, 0)
        else:
            keep = __load64(__load64(saved + 32) + 8 * e)
        mode := __load64(keep)
        if raw:
            mode = ((mode & ~(2 | 1 | 64)) | 512 | 128)
        if not echo:
            mode = mode & ~4
        ok := __rt_w32(__wincall("SetConsoleMode", hin, mode)) != 0
        if __load64(keep + 8) >= 0:
            __wincall("SetConsoleMode", hout, __load64(keep + 8) | 1 | 4)
        return ok
    return false

func __fdw_restore(fd: int, keep: int):
    if __windows():
        __wincall("SetConsoleMode", __rt_win_handle(fd), __load64(keep))
        if __load64(keep + 8) >= 0:
            __wincall("SetConsoleMode", __wincall("GetStdHandle", -11), __load64(keep + 8))

# Console : vrai si un caractère attend (touche enfoncée porteuse d'un caractère) ; les autres événements
# (relâchement, focus, souris hors séquences VT, redimensionnement) sont consommés, sans quoi ReadConsoleW
# resterait bloqué jusqu'à la prochaine touche.
func __fdw_console_char(h: int) -> bool:
    if __windows():
        cnt := __alloc_raw(8)
        __store64(cnt, 0)
        if __rt_w32(__wincall("GetNumberOfConsoleInputEvents", h, cnt)) == 0:
            return true
        k := __load32(cnt)
        if k <= 0:
            return false
        rec := __alloc_raw(20 * k + 8)
        got := __alloc_raw(8)
        __store64(got, 0)
        if __rt_w32(__wincall("PeekConsoleInputW", h, rec, k, got)) == 0:
            return true
        k = __load32(got)
        i := 0
        while i < k:
            r := rec + 20 * i
            if __load16(r) == 1 and __load32(r + 4) != 0 and __load16(r + 14) != 0:
                return true
            i += 1
        __wincall("ReadConsoleInputW", h, rec, k, got)
        return false
    return false

# Lecture console : en mode ligne, celle du runtime (Ctrl+Z en début de ligne = fin de flux) ; en mode brut, les
# caractères tels quels (Ctrl+Z est une touche comme une autre : annuler, dans l'éditeur).
func __fdw_read_console(h: int, buf: int, mx: int) -> int:
    if __windows():
        m := __alloc_raw(8)
        __store64(m, 0)
        __wincall("GetConsoleMode", h, m)
        if (__load32(m) & 2) != 0:
            return __rt_win_read_console(h, buf, mx)
        chars := mx // 3
        if chars > 8192:
            chars = 8192
        if chars < 1:
            return 0
        w := __alloc_raw(2 * chars + 2)
        got := __alloc_raw(8)
        __store64(got, 0)
        if __rt_w32(__wincall("ReadConsoleW", h, w, chars, got, 0)) == 0:
            return 0 - __rt_win_errno()
        k := __rt_w32(__load64(got))
        if k == 0:
            return 0
        return __rt_w32(__wincall("WideCharToMultiByte", 65001, 0, w, k, buf, mx, 0, 0))
    return 0

func __nat__native_fd__mkfifo(n: int, a: int, b: int) -> int:
    if __windows():
        __nat_range("mkfifo", n, 2, 2)
        return __dyn_int(0 if __fdw_pipe_name(__nat_cstr("mkfifo", a, "le chemin")) else -22)
    __nat_range("mkfifo", n, 2, 2)
    path := __nat_cstr("mkfifo", a, "le chemin")
    mode := __nat_int("mkfifo", b, "le mode")
    r := __syscall(133, __nat_c(path), 4096 | (mode & 4095), 0) # mknod(S_IFIFO)
    if r < 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_fd__open_fifo(n: int, a: int, b: int, c: int) -> int:
    __nat_range("open_fifo", n, 3, 3)
    path := __nat_cstr("open_fifo", a, "le chemin")
    writing := __nat_bool("open_fifo", b, "l'écriture")
    end := __nat_deadline(__nat_timeout("open_fifo", c))
    if __windows():
        return __fdw_open_fifo(path)
    st := __nat_stat(path, false)
    if __nat_st_failed(st):
        return __dyn_int(0 - __nat_st_errno(st))
    if __nat_st_type(st) != 4096:
        return __dyn_int(-22)
    flags := 2048 | 524288 # O_NONBLOCK | O_CLOEXEC
    if writing:
        flags = flags | 1
    ts := __alloc_raw(16)
    while true:
        fd := __syscall(2, __nat_c(path), flags)
        if fd >= 0:
            __fd_own(fd)
            return __dyn_int(fd)
        if not (writing and fd == -6):
            return __dyn_int(fd)
        if __nat_remaining_ms(end) == 0:
            return __dyn_int(-110)
        __store64(ts, 0)
        __store64(ts + 8, 10000000)
        __syscall(35, ts, 0)
    return 0

func __nat__native_fd__open_device(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("open_device", n, 2, 2)
    path := __nat_cstr("open_device", a, "le chemin")
    writing := __nat_bool("open_device", b, "l'écriture")
    flags := 2048 | 524288
    if writing:
        flags = flags | 2
    fd := __syscall(2, __nat_c(path), flags)
    if fd < 0:
        return __dyn_int(fd)
    __fd_own(fd)
    return __dyn_int(fd)

func __nat__native_fd__readlink(n: int, a: int) -> int:
    __fd_win_off()
    __nat_range("readlink", n, 1, 1)
    path := __nat_cstr("readlink", a, "le chemin")
    buf := __alloc_raw(4096)
    k := __syscall(89, __nat_c(path), buf, 4095)
    if k < 0:
        return 0
    return __dyn_str(__nat_make(buf, k))

# poll d'un seul descripteur : 1 prêt, 0 délai écoulé, < 0 erreur.
func __fd_poll1(fd: int, events: int, ms: int) -> int:
    p := __alloc_raw(8)
    __store32(p, fd)
    __store16(p + 4, events)
    __store16(p + 6, 0)
    if __load64(__dyn_ds() + 144) == 0:
        return __syscall(7, p, 1, ms)
    # fils actifs : attente par tranches, descripteurs fermés par un autre fil répercutés entre deux tranches
    end := -1.0
    if ms >= 0:
        end = __nat_clock(1) + __i2f(ms) / 1000.0
    while true:
        __fd_sync()
        slice := 50
        if end >= 0.0:
            left := __nat_remaining_ms(end)
            if left < slice:
                slice = left
        r := __syscall(7, p, 1, slice)
        if r != 0 or (end >= 0.0 and __nat_clock(1) >= end):
            return r
    return 0

# Descripteurs partagés entre fils (processus) : un descripteur fermé dans un fil l'est dans tous, comme dans la VM
# où les fils partagent la table des descripteurs. Journal dans la région des fils : R+512 [nombre] puis 64
# entrées [descripteur][périphérique][inode] ; [272] de l'état : entrées déjà traitées par ce processus.
func __fd_mark_closed(fd: int):
    r := __load64(__dyn_ds() + 144)
    if r == 0:
        return
    st := __alloc_raw(144)
    if __syscall(5, fd, st) != 0:
        return
    __th_lock(r)
    k := __load64(r + 512)
    e := r + 520 + 24 * (k % 64)
    __store64(e, fd)
    __store64(e + 8, __load64(st))
    __store64(e + 16, __load64(st + 8))
    __store64(r + 512, k + 1)
    __th_unlock(r)
    __store64(__dyn_ds() + 272, k + 1)

func __fd_sync():
    r := __load64(__dyn_ds() + 144)
    if r == 0:
        return
    k := __load64(r + 512)
    seen := __load64(__dyn_ds() + 272)
    if seen < k - 64:
        seen = k - 64
    st := __alloc_raw(144)
    while seen < k:
        e := r + 520 + 24 * (seen % 64)
        fd := __load64(e)
        if __syscall(5, fd, st) == 0 and __load64(st) == __load64(e + 8) and __load64(st + 8) == __load64(e + 16):
            d := __load64(__fd_st())
            if __rt_dict_index(d, fd, 0) >= 0:
                __rt_dict_remove(d, fd, 0)
                __syscall(3, fd)
        seen += 1
    __store64(__dyn_ds() + 272, seen)

func __nat__native_fd__read(n: int, a: int, b: int, c: int) -> int:
    __nat_range("read", n, 3, 3)
    fd := __fd_arg("read", a)
    mx := __nat_int("read", b, "la taille")
    if mx < 1 or mx > 67108864:
        __dyn_err("ArgumentError", "'read' : taille hors de 1..64 Mio")
    end := __nat_deadline(__nat_timeout("read", c))
    if __windows():
        return __fdw_read(fd, mx, end)
    buf := __alloc_raw(mx)
    while true:
        r := __fd_poll1(fd, 1, __nat_remaining_ms(end))
        if r == -4:
            continue
        if r < 0:
            return __dyn_int(r)
        if r == 0:
            return 0
        k := __syscall(0, fd, buf, mx)
        if k >= 0:
            return __dyn_str(__nat_make(buf, k))
        if k == -4 or k == -11:
            continue
        return __dyn_int(k)
    return 0

func __nat__native_fd__write(n: int, a: int, b: int, c: int) -> int:
    __nat_range("write", n, 3, 3)
    fd := __fd_arg("write", a)
    data := __nat_str("write", b, "les données")
    end := __nat_deadline(__nat_timeout("write", c))
    if __windows():
        return __fdw_write(fd, __nat_bp(data), __nat_blen(data), end)
    done := 0
    m := __nat_blen(data)
    while done < m:
        k := __syscall(1, fd, __nat_bp(data) + done, m - done)
        if k > 0:
            done += k
            continue
        if k == -4:
            continue
        if k < 0 and k != -11:
            return __dyn_int(k)
        r := __fd_poll1(fd, 4, __nat_remaining_ms(end))
        if r == 0:
            if done > 0:
                return __dyn_int(done)
            return __dyn_int(-110)
    return __dyn_int(done)

func __nat__native_fd__close(n: int, a: int) -> int:
    __nat_range("close", n, 1, 1)
    fd := __fd_arg("close", a)
    d := __load64(__fd_st())
    if __rt_dict_index(d, fd, 0) < 0:
        return __dyn_bool(false)
    __rt_dict_remove(d, fd, 0)
    if __windows():
        __pw_close(fd)
        return __dyn_bool(true)
    __fd_mark_closed(fd)
    __syscall(3, fd)
    return __dyn_bool(true)

# ---- USB par usbfs (ioctl USBDEVFS_*) ----

func __usb_ioctl_int(fn: str, n: int, a: int, b: int, req: int, label: str) -> int:
    __nat_range(fn, n, 2, 2)
    fd := __fd_arg(fn, a)
    v := __alloc_raw(8)
    __store64(v, __nat_int(fn, b, label) & 4294967295)
    r := __syscall(16, fd, req, v)
    if r < 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_fd__usb_claim(n: int, a: int, b: int) -> int:
    __fd_win_off()
    return __usb_ioctl_int("usb_claim", n, a, b, 2147767567, "l'interface")

func __nat__native_fd__usb_release(n: int, a: int, b: int) -> int:
    __fd_win_off()
    return __usb_ioctl_int("usb_release", n, a, b, 2147767568, "l'interface")

func __nat__native_fd__usb_clear_halt(n: int, a: int, b: int) -> int:
    __fd_win_off()
    return __usb_ioctl_int("usb_clear_halt", n, a, b, 2147767573, "le point d'accès")

func __nat__native_fd__usb_reset(n: int, a: int) -> int:
    __fd_win_off()
    __nat_range("usb_reset", n, 1, 1)
    r := __syscall(16, __fd_arg("usb_reset", a), 21780, 0)
    if r < 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_fd__usb_detach(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("usb_detach", n, 2, 2)
    fd := __fd_arg("usb_detach", a)
    cmd := __alloc_raw(16)
    __zero(cmd, 16)
    __store32(cmd, __nat_int("usb_detach", b, "l'interface") & 4294967295)
    __store32(cmd + 4, 21782)
    r := __syscall(16, fd, 3222295826, cmd)
    if r < 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_fd__usb_control(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                   a7: int, x: int) -> int:
    __fd_win_off()
    __nat_range("usb_control", n, 7, 7)
    fd := __fd_arg("usb_control", a0)
    c := __alloc_raw(24)
    __zero(c, 24)
    rt := __nat_int("usb_control", a1, "le type") & 255
    __store8(c, rt)
    __store8(c + 1, __nat_int("usb_control", a2, "la requête") & 255)
    __store16(c + 2, __nat_int("usb_control", a3, "la valeur") & 65535)
    __store16(c + 4, __nat_int("usb_control", a4, "l'index") & 65535)
    __store32(c + 8, __nat_int("usb_control", a6, "le délai") & 4294967295)
    inb := (rt & 128) != 0
    len := 0
    data := ""
    if inb:
        len = __nat_int("usb_control", a5, "la longueur")
    elif a5 != 0:
        data = __nat_str("usb_control", a5, "les données")
        len = __nat_blen(data)
    if len > 65535:
        __dyn_err("ArgumentError", "'usb_control' : 65535 octets au plus")
    buf := __alloc_raw(len + 8)
    if not inb:
        __copy(buf, __nat_bp(data), len)
    __store16(c + 6, len)
    if len > 0:
        __store64(c + 16, buf)
    r := __syscall(16, fd, 3222820096, c)
    if r < 0:
        return __dyn_int(r)
    if not inb:
        return __dyn_str("")
    return __dyn_str(__nat_make(buf, r))

func __nat__native_fd__usb_bulk(n: int, a: int, b: int, c: int, d: int) -> int:
    __fd_win_off()
    __nat_range("usb_bulk", n, 4, 4)
    fd := __fd_arg("usb_bulk", a)
    t := __alloc_raw(24)
    __zero(t, 24)
    ep := __nat_int("usb_bulk", b, "le point d'accès") & 4294967295
    __store32(t, ep)
    __store32(t + 8, __nat_int("usb_bulk", d, "le délai") & 4294967295)
    inb := (ep & 128) != 0
    len := 0
    data := ""
    if inb:
        len = __nat_int("usb_bulk", c, "la longueur")
    else:
        data = __nat_str("usb_bulk", c, "les données")
        len = __nat_blen(data)
    buf := __alloc_raw(len + 8)
    if not inb:
        __copy(buf, __nat_bp(data), len)
    __store32(t + 4, len)
    if len > 0:
        __store64(t + 16, buf)
    r := __syscall(16, fd, 3222820098, t)
    if r < 0:
        return __dyn_int(r)
    if not inb:
        return __dyn_int(r)
    return __dyn_str(__nat_make(buf, r))

func __nat__native_fd__isatty(n: int, a: int) -> int:
    __nat_range("isatty", n, 1, 1)
    return __dyn_bool(__nat_isatty(__fd_arg("isatty", a)))

func __nat__native_fd__set_nonblocking(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("set_nonblocking", n, 2, 2)
    fd := __fd_arg("set_nonblocking", a)
    on := __nat_bool("set_nonblocking", b, "l'état")
    fl := __syscall(72, fd, 3, 0) # F_GETFL
    if fl < 0:
        return __dyn_int(fl)
    if on:
        fl = fl | 2048
    else:
        fl = fl & ~2048
    r := __syscall(72, fd, 4, fl) # F_SETFL
    if r != 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_fd__set_mode(n: int, a: int, b: int, c: int) -> int:
    __nat_range("set_mode", n, 3, 3)
    fd := __fd_arg("set_mode", a)
    raw := __nat_bool("set_mode", b, "brut")
    echo := __nat_bool("set_mode", c, "écho")
    if __windows():
        return __dyn_bool(__fdw_set_mode(fd, raw, echo))
    t := __alloc_raw(64)
    if __syscall(16, fd, 21505, t) != 0: # TCGETS
        return __dyn_bool(false)
    saved := __load64(__fd_st() + 8)
    e := __rt_dict_index(saved, fd, 0)
    if e < 0:
        keep := __alloc_raw(64)
        __copy(keep, t, 64)
        __rt_dict_set(saved, fd, keep, 0)
    else:
        __copy(t, __load64(__load64(saved + 32) + 8 * e), 64)
    if raw:
        __store32(t + 12, __load32(t + 12) & ~(2 | 32768 | 1)) # ICANON | IEXTEN | ISIG
        __store32(t, __load32(t) & ~(1024 | 256))             # IXON | ICRNL
        __store8(t + 23, 1)                                    # VMIN
        __store8(t + 22, 0)                                    # VTIME
    if not echo:
        __store32(t + 12, __load32(t + 12) & ~(8 | 64))       # ECHO | ECHONL
    return __dyn_bool(__syscall(16, fd, 21506, t) == 0)

func __nat__native_fd__restore(n: int, a: int) -> int:
    __nat_range("restore", n, 1, 1)
    fd := __fd_arg("restore", a)
    saved := __load64(__fd_st() + 8)
    e := __rt_dict_index(saved, fd, 0)
    if e < 0:
        return __dyn_bool(false)
    if __windows():
        __fdw_restore(fd, __load64(__load64(saved + 32) + 8 * e))
        return __dyn_bool(true)
    __syscall(16, fd, 21506, __load64(__load64(saved + 32) + 8 * e))
    return __dyn_bool(true)

func __nat__native_fd__poll(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("poll", n, 2, 2)
    items := __nat_items("poll", a, "les descripteurs", "une list")
    end := __nat_deadline(__nat_timeout("poll", b))
    k := __load64(items)
    p := __alloc_raw(8 * k + 8)
    i := 0
    while i < k:
        pair := __nat_items("poll", __rt_vec_at(items, i), "un élément [fd, mode]", "une list")
        if __load64(pair) != 2:
            __dyn_err("ArgumentError", "'poll' : élément [fd, mode] attendu")
        mode := __nat_cstr("poll", __rt_vec_at(pair, 1), "le mode")
        ev := 0
        if __dyn_find_bytes(mode, "r", 0) >= 0:
            ev = ev | 1
        if __dyn_find_bytes(mode, "w", 0) >= 0:
            ev = ev | 4
        __store32(p + 8 * i, __fd_arg("poll", __rt_vec_at(pair, 0)))
        __store16(p + 8 * i + 4, ev)
        __store16(p + 8 * i + 6, 0)
        i += 1
    out := __dyn_list_new(0)
    while true:
        r := __syscall(7, p, k, __nat_remaining_ms(end))
        if r == -4:
            if __nat_remaining_ms(end) == 0:
                return out
            continue
        if r < 0:
            return __dyn_int(r)
        break
    i = 0
    while i < k:
        rev := __load16(p + 8 * i + 6)
        if rev != 0:
            sb := __rt_sb_new()
            if (rev & 1) != 0:
                __rt_sb_add(sb, "r")
            if (rev & 4) != 0:
                __rt_sb_add(sb, "w")
            if (rev & 16) != 0:
                __rt_sb_add(sb, "h")
            if (rev & 40) != 0:
                __rt_sb_add(sb, "e")
            l := __dyn_list_new(0)
            fdv := __load32(p + 8 * i)
            if fdv >= 2147483648:
                fdv = fdv - 4294967296
            __dyn_list_push(l, __dyn_int(fdv))
            __dyn_list_push(l, __dyn_str(__rt_sb_str(sb)))
            __dyn_list_push(out, l)
        i += 1
    return out

func __nat__native_fd__file_kind(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("file_kind", n, 1, 2)
    path := __nat_cstr("file_kind", a, "le chemin")
    follow := true
    if n >= 2 and b != 0:
        follow = __nat_bool("file_kind", b, "suivre les liens")
    st := __nat_stat(path, not follow)
    t := __nat_st_type(st)
    if t < 0:
        return 0
    if t == 32768:
        return __dyn_str("file")
    if t == 16384:
        return __dyn_str("dir")
    if t == 40960:
        return __dyn_str("link")
    if t == 4096:
        return __dyn_str("fifo")
    if t == 49152:
        return __dyn_str("socket")
    if t == 8192:
        return __dyn_str("char")
    if t == 24576:
        return __dyn_str("block")
    return __dyn_str("other")

func __nat_major(d: int) -> int:
    return ((d >> 8) & 4095) | ((d >> 32) & ~4095 & 4294967295)

func __nat_minor(d: int) -> int:
    return (d & 255) | ((d >> 12) & ~255 & 4294967295)

func __nat__native_fd__stat(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("stat", n, 1, 2)
    path := __nat_cstr("stat", a, "le chemin")
    follow := true
    if n >= 2 and b != 0:
        follow = __nat_bool("stat", b, "suivre les liens")
    st := __nat_stat(path, not follow)
    if __nat_st_failed(st):
        return 0
    l := __dyn_list_new(0)
    rdev := __load64(st + 40)
    dev := __load64(st)
    __dyn_list_push(l, __dyn_int(__load32(st + 24)))
    __dyn_list_push(l, __dyn_int(__load32(st + 28)))
    __dyn_list_push(l, __dyn_int(__load32(st + 32)))
    __dyn_list_push(l, __dyn_int(__nat_major(rdev)))
    __dyn_list_push(l, __dyn_int(__nat_minor(rdev)))
    __dyn_list_push(l, __dyn_int(__load64(st + 48)))
    __dyn_list_push(l, __dyn_int(__load64(st + 8)))
    __dyn_list_push(l, __dyn_int(__nat_major(dev)))
    __dyn_list_push(l, __dyn_int(__nat_minor(dev)))
    return l

func __nat__native_fd__ids(n: int) -> int:
    __fd_win_off()
    __nat_range("ids", n, 0, 0)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__syscall(102)))
    __dyn_list_push(l, __dyn_int(__syscall(107)))
    __dyn_list_push(l, __dyn_int(__syscall(104)))
    __dyn_list_push(l, __dyn_int(__syscall(108)))
    g := __dyn_list_new(0)
    k := __syscall(115, 0, 0)
    if k > 0:
        buf := __alloc_raw(4 * k + 4)
        k = __syscall(115, k, buf)
        i := 0
        while i < k:
            __dyn_list_push(g, __dyn_int(__load32(buf + 4 * i)))
            i += 1
    __dyn_list_push(l, g)
    return l

# Entrées de /etc/passwd ou /etc/group : liste native de listes natives de champs.
func __nat_db(path: str) -> int:
    out := __rt_list_new(0)
    fd := __syscall(2, __nat_c(path), 0)
    if fd < 0:
        return out
    data := __nat_read_fd(fd, -1)
    __syscall(3, fd)
    lines := __nat_split_bytes(data, 10)
    i := 0
    while i < __load64(lines):
        ln := __as_str(__rt_vec_at(lines, i))
        if __nat_blen(ln) > 0 and __load8(__nat_bp(ln)) != 35:
            __rt_list_push(out, __nat_split_bytes(ln, 58))
        i += 1
    return out

func __nat_db_find(db: int, col: int, key: str, minFields: int) -> int:
    i := 0
    while i < __load64(db):
        f := __rt_vec_at(db, i)
        if __load64(f) >= minFields and __rt_str_eq(__as_str(__rt_vec_at(f, col)), key):
            return f
        i += 1
    return 0

func __nat__native_fd__user_name(n: int, a: int) -> int:
    __fd_win_off()
    __nat_range("user_name", n, 1, 1)
    uid := __nat_int("user_name", a, "l'uid")
    f := __nat_db_find(__nat_db("/etc/passwd"), 2, __int_to_str(uid), 7)
    if f == 0:
        return 0
    return __dyn_str(__as_str(__rt_vec_at(f, 0)))

func __nat__native_fd__group_name(n: int, a: int) -> int:
    __fd_win_off()
    __nat_range("group_name", n, 1, 1)
    gid := __nat_int("group_name", a, "le gid")
    f := __nat_db_find(__nat_db("/etc/group"), 2, __int_to_str(gid), 3)
    if f == 0:
        return 0
    return __dyn_str(__as_str(__rt_vec_at(f, 0)))

func __nat__native_fd__group_id(n: int, a: int) -> int:
    __fd_win_off()
    __nat_range("group_id", n, 1, 1)
    name := __nat_cstr("group_id", a, "le nom")
    f := __nat_db_find(__nat_db("/etc/group"), 0, name, 3)
    if f == 0:
        return __dyn_int(-1)
    return __dyn_int(__rt_str_to_int(__as_str(__rt_vec_at(f, 2))))

func __nat__native_fd__group_members(n: int, a: int) -> int:
    __fd_win_off()
    __nat_range("group_members", n, 1, 1)
    name := __nat_cstr("group_members", a, "le nom")
    l := __dyn_list_new(0)
    f := __nat_db_find(__nat_db("/etc/group"), 0, name, 3)
    if f != 0 and __load64(f) >= 4:
        mem := __as_str(__rt_vec_at(f, 3))
        if __nat_blen(mem) > 0:
            ms := __nat_split_bytes(mem, 44)
            i := 0
            while i < __load64(ms):
                __dyn_list_push(l, __dyn_str(__as_str(__rt_vec_at(ms, i))))
                i += 1
    return l

func __nat__native_fd__inotify_supported(n: int) -> int:
    if __windows():
        return __dyn_bool(false)
    __nat_range("inotify_supported", n, 0, 0)
    return __dyn_bool(not __windows())

func __nat__native_fd__inotify_init(n: int) -> int:
    __fd_win_off()
    __nat_range("inotify_init", n, 0, 0)
    fd := __syscall(294, 2048 | 524288)
    if fd < 0:
        return __dyn_int(fd)
    __fd_own(fd)
    return __dyn_int(fd)

func __fd_inotify_names() -> int:
    return __nat_split_bytes("1:access,2:modify,4:attrib,8:close_write,16:close_nowrite,32:open,64:moved_from,128:moved_to,256:create,512:delete,1024:delete_self,2048:move_self,32768:ignored,1073741824:isdir,16384:overflow,8192:unmount", 44)

func __nat__native_fd__inotify_add(n: int, a: int, b: int, c: int) -> int:
    __fd_win_off()
    __nat_range("inotify_add", n, 3, 3)
    fd := __fd_arg("inotify_add", a)
    path := __nat_cstr("inotify_add", b, "le chemin")
    evs := __nat_items("inotify_add", c, "les événements", "une list")
    names := __fd_inotify_names()
    mask := 0
    i := 0
    while i < __load64(evs):
        nm := __nat_cstr("inotify_add", __rt_vec_at(evs, i), "les événements (élément)")
        found := false
        j := 0
        while j < __load64(names):
            it := __as_str(__rt_vec_at(names, j))
            cpos := __dyn_find_bytes(it, ":", 0)
            if __rt_str_eq(__nat_sub(it, cpos + 1, __nat_blen(it) - cpos - 1), nm):
                mask = mask | __rt_str_to_int(__nat_sub(it, 0, cpos))
                found = true
            j += 1
        if __rt_str_eq(nm, "all"):
            mask = mask | 4095
            found = true
        if not found:
            __dyn_err("ArgumentError", "'inotify_add' : événement inconnu '" + nm + "'")
        i += 1
    wd := __syscall(254, fd, __nat_c(path), mask)
    return __dyn_int(wd)

func __nat__native_fd__inotify_remove(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("inotify_remove", n, 2, 2)
    fd := __fd_arg("inotify_remove", a)
    wd := __nat_int("inotify_remove", b, "la surveillance")
    r := __syscall(255, fd, wd)
    if r == 0:
        return __dyn_int(0)
    return __dyn_int(r)

func __nat__native_fd__inotify_read(n: int, a: int, b: int) -> int:
    __fd_win_off()
    __nat_range("inotify_read", n, 2, 2)
    fd := __fd_arg("inotify_read", a)
    end := __nat_deadline(__nat_timeout("inotify_read", b))
    out := __dyn_list_new(0)
    r := __fd_poll1(fd, 1, __nat_remaining_ms(end))
    while r == -4:
        r = __fd_poll1(fd, 1, __nat_remaining_ms(end))
    if r <= 0:
        return out
    buf := __alloc_raw(16384)
    k := __syscall(0, fd, buf, 16384)
    if k < 0:
        if k == -11:
            return out
        return __dyn_int(k)
    names := __fd_inotify_names()
    off := 0
    while off < k:
        ev := buf + off
        l := __dyn_list_new(0)
        wd := __load32(ev)
        if wd >= 2147483648:
            wd = wd - 4294967296
        __dyn_list_push(l, __dyn_int(wd))
        nl := __dyn_list_new(0)
        mask := __load32(ev + 4)
        j := 0
        while j < __load64(names):
            it := __as_str(__rt_vec_at(names, j))
            cpos := __dyn_find_bytes(it, ":", 0)
            if (mask & __rt_str_to_int(__nat_sub(it, 0, cpos))) != 0:
                __dyn_list_push(nl, __dyn_str(__nat_sub(it, cpos + 1, __nat_blen(it) - cpos - 1)))
            j += 1
        __dyn_list_push(l, nl)
        __dyn_list_push(l, __dyn_int(__load32(ev + 8)))
        ln := __load32(ev + 12)
        nm := ""
        if ln > 0:
            q := 0
            while q < ln and __load8(ev + 16 + q) != 0:
                q += 1
            nm = __nat_make(ev + 16, q)
        __dyn_list_push(l, __dyn_str(nm))
        __dyn_list_push(out, l)
        off += 16 + ln
    return out

# Windows : io.pipe / io.console non pris en charge, comme la VM C++ (fd_native.cpp).
func __fd_win_off():
    if __windows():
        __dyn_err("IoError", "io.pipe / io.console : non pris en charge sur cette plateforme")

func __nat__native_fd__strerror(n: int, a: int) -> int:
    return __nat_strerror_impl(n, a)

func __nat_strerror_impl(n: int, a: int) -> int:
    __nat_range("strerror", n, 1, 1)
    c := __nat_int("strerror", a, "le code")
    if c < 0:
        c = 0 - c
    if c == 0:
        return __dyn_str("Success")
    return __dyn_str(__nat_errno_text(c))

func __nat__native_fd__errno_name(n: int, a: int) -> int:
    __nat_range("errno_name", n, 1, 1)
    c := __nat_int("errno_name", a, "le code")
    if c < 0:
        c = 0 - c
    return __dyn_str(__nat_errno_name(c))

# ---- _native_signal (noms et numéros ; interception : à venir) ---------------------------------------------------

func __sig_table() -> int:
    if __windows():
        return __nat_split_bytes("INT:2:0,TERM:15:0", 44) # comme la VM C++ sous Windows : rien d'interceptable
    return __nat_split_bytes("HUP:1:1,INT:2:1,QUIT:3:1,ILL:4:0,TRAP:5:1,ABRT:6:1,BUS:7:0,FPE:8:0,KILL:9:0,USR1:10:1,SEGV:11:0,USR2:12:1,PIPE:13:1,ALRM:14:1,TERM:15:1,CHLD:17:1,CONT:18:1,STOP:19:0,TSTP:20:1,TTIN:21:1,TTOU:22:1,URG:23:1,XCPU:24:1,XFSZ:25:1,VTALRM:26:1,PROF:27:1,WINCH:28:1,IO:29:1,SYS:31:1", 44)

func __sig_field(entry: int, k: int) -> str:
    return __as_str(__rt_vec_at(__nat_split_bytes(__as_str(entry), 58), k))

func __nat__native_signal__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    return __dyn_bool(not __windows())

func __nat__native_signal__names(n: int) -> int:
    __nat_range("names", n, 0, 0)
    t := __sig_table()
    l := __dyn_list_new(0)
    i := 0
    while i < __load64(t):
        __dyn_list_push(l, __dyn_str(__sig_field(__rt_vec_at(t, i), 0)))
        i += 1
    return l

func __nat__native_signal__number(n: int, a: int) -> int:
    __nat_range("number", n, 1, 1)
    name := __nat_case(__nat_str("number", a, "le nom du signal"), 0)
    if __nat_blen(name) >= 3 and __rt_str_eq(__nat_sub(name, 0, 3), "SIG"):
        name = __nat_sub(name, 3, __nat_blen(name) - 3)
    t := __sig_table()
    i := 0
    while i < __load64(t):
        if __rt_str_eq(__sig_field(__rt_vec_at(t, i), 0), name):
            return __dyn_int(__rt_str_to_int(__sig_field(__rt_vec_at(t, i), 1)))
        i += 1
    return __dyn_int(-1)

func __nat__native_signal__name(n: int, a: int) -> int:
    __nat_range("name", n, 1, 1)
    k := __nat_int("name", a, "le numéro du signal")
    t := __sig_table()
    i := 0
    while i < __load64(t):
        if __rt_str_eq(__sig_field(__rt_vec_at(t, i), 1), __int_to_str(k)):
            return __dyn_str(__sig_field(__rt_vec_at(t, i), 0))
        i += 1
    return 0

func __nat__native_signal__is_main_thread(n: int) -> int:
    __nat_range("is_main_thread", n, 0, 0)
    return __dyn_bool(__load64(__dyn_ds() + 120) == 0)

func __nat__native_signal__send(n: int, a: int, b: int) -> int:
    __nat_range("send", n, 2, 2)
    pid := __nat_int("send", a, "le pid")
    sig := __sig_arg("send", b)
    if __windows():
        return __dyn_int(-38)
    if pid <= 0:
        __dyn_err("ArgumentError", "signal.send : pid > 0 attendu")
    r := __syscall(62, pid, sig)
    if pid == __syscall(39):
        __store64(__dyn_ds() + 256, 1) # signal à soi-même : traité au prochain point sûr
    if r == 0:
        return __dyn_int(0)
    return __dyn_int(r)

func __nat__native_signal__strerror(n: int, a: int) -> int:
    return __nat_strerror_impl(n, a)

func __nat__native_signal__errno_name(n: int, a: int) -> int:
    __nat_range("errno_name", n, 1, 1)
    c := __nat_int("errno_name", a, "le code")
    if c < 0:
        c = 0 - c
    if c == 1:
        return __dyn_str("EPERM")
    if c == 3:
        return __dyn_str("ESRCH")
    if c == 22:
        return __dyn_str("EINVAL")
    return __dyn_str("EUNKNOWN")


# ---- signaux interceptés : bloqués et lus par signalfd ---------------------------------------------------------
# État (état du mode dynamique) : [200] gestionnaire actif (points sûrs du code traduit), [208] signalfd (-1 aucun),
# [216] masque des signaux interceptés, [224] tampon de 65 modes (0 intact, 1 gestionnaire, 2 file, 3 ignoré)
# [232] compteurs « gestionnaire », [240] compteurs « file », [248] répartiteur Alex, [256] compte à rebours,
# [264] dans le gestionnaire.

func __sig_state(off: int) -> int:
    ds := __dyn_ds()
    if __load64(ds + 224) == 0:
        __store64(ds + 224, __alloc_raw(8 * 65))
        __zero(__load64(ds + 224), 8 * 65)
        __store64(ds + 232, __alloc_raw(8 * 65))
        __zero(__load64(ds + 232), 8 * 65)
        __store64(ds + 240, __alloc_raw(8 * 65))
        __zero(__load64(ds + 240), 8 * 65)
        __store64(ds + 208, -1)
    return __load64(ds + off)

func __sig_catchable(n: int) -> int: # 1 interceptable, 0 non, -1 inconnu
    t := __sig_table()
    i := 0
    while i < __load64(t):
        e := __rt_vec_at(t, i)
        if __rt_str_eq(__sig_field(e, 1), __int_to_str(n)):
            if __rt_str_eq(__sig_field(e, 2), "1"):
                return 1
            return 0
        i += 1
    return -1

func __sig_arg(fn: str, v: int) -> int:
    n := __nat_int(fn, v, "le numéro du signal")
    if n <= 0 or n >= 65:
        __dyn_err("ArgumentError", "signal." + fn + " : numéro de signal invalide")
    return n

func __sig_procmask(how: int, n: int):
    m := __alloc_raw(8)
    __store64(m, 1 << (n - 1))
    __syscall(14, how, m, 0, 8)

func __sig_update_fd():
    ds := __dyn_ds()
    __sig_state(0)
    m := __alloc_raw(8)
    __store64(m, __load64(ds + 216))
    fd := __syscall(289, __load64(ds + 208), m, 8, 2048 | 524288) # signalfd4(SFD_NONBLOCK | SFD_CLOEXEC)
    if fd >= 0:
        __store64(ds + 208, fd)

# Lit les signaux arrivés et les range selon leur mode.
func __sig_drain():
    ds := __dyn_ds()
    fd := __load64(ds + 208)
    if fd < 0:
        return
    buf := __alloc_raw(128 * 16)
    while true:
        k := __syscall(0, fd, buf, 128 * 16)
        if k <= 0:
            return
        off := 0
        while off + 128 <= k:
            n := __load32(buf + off)
            if n > 0 and n < 65:
                if __load64(__load64(ds + 224) + 8 * n) == 1:
                    __store64(__load64(ds + 232) + 8 * n, __load64(__load64(ds + 232) + 8 * n) + 1)
                else:
                    __store64(__load64(ds + 240) + 8 * n, __load64(__load64(ds + 240) + 8 * n) + 1)
            off += 128

# Point sûr : appelle le répartiteur pour chaque signal « gestionnaire » arrivé.
func __sig_check():
    ds := __dyn_ds()
    c := __load64(ds + 256) - 1
    if c > 0:
        __store64(ds + 256, c)
        return
    __store64(ds + 256, 512)
    __sig_dispatch()

func __sig_dispatch():
    ds := __dyn_ds()
    if __load64(ds + 264) != 0 or __load64(ds + 248) == 0:
        return
    __sig_drain()
    n := 1
    while n < 65:
        cnt := __load64(__load64(ds + 232) + 8 * n)
        if cnt > 0:
            __store64(__load64(ds + 232) + 8 * n, cnt - 1)
            __store64(ds + 264, 1)
            try:
                __dyn_call1(__load64(ds + 248), __dyn_int(n))
            catch e:
                __store64(ds + 264, 0)
                __rt_throw(__addr(e))
            __store64(ds + 264, 0)
            n = 0
        n += 1

# true si un signal attend son gestionnaire (pauses : sleep s'interrompt).
func __sig_pending_auto() -> bool:
    ds := __dyn_ds()
    if __load64(ds + 200) == 0:
        return false
    __sig_drain()
    n := 1
    while n < 65:
        if __load64(__load64(ds + 232) + 8 * n) > 0:
            return true
        n += 1
    return false

func __sig_install(n: int, mode: int) -> int:
    if __sig_catchable(n) != 1:
        return -1
    ds := __dyn_ds()
    __sig_state(0)
    __store64(__load64(ds + 224) + 8 * n, mode)
    act := __alloc_raw(32)
    __zero(act, 32)
    if mode == 3:
        __store64(act, 1)
        __store64(ds + 216, __load64(ds + 216) & ~(1 << (n - 1)))
        __sig_update_fd()
        __sig_procmask(1, n)
        r := __syscall(13, n, act, 0, 8)
        if r < 0:
            return r
        return 0
    if mode == 0:
        __sig_drain()
        __store64(ds + 216, __load64(ds + 216) & ~(1 << (n - 1)))
        __sig_update_fd()
        r := __syscall(13, n, act, 0, 8)
        __sig_procmask(1, n) # SIG_UNBLOCK
        if r < 0:
            return r
        return 0
    __syscall(13, n, act, 0, 8)
    __store64(ds + 216, __load64(ds + 216) | (1 << (n - 1)))
    __sig_procmask(0, n) # SIG_BLOCK
    __sig_update_fd()
    if mode == 1:
        __store64(ds + 200, 1)
    return 0

func __nat__native_signal__intercept(n: int, a: int, b: int) -> int:
    __nat_range("intercept", n, 2, 2)
    s := __sig_arg("intercept", a)
    mode := 2
    if __dyn_truthy(b):
        mode = 1
    return __dyn_int(__sig_install(s, mode))

func __nat__native_signal__ignore(n: int, a: int) -> int:
    __nat_range("ignore", n, 1, 1)
    return __dyn_int(__sig_install(__sig_arg("ignore", a), 3))

func __nat__native_signal__reset(n: int, a: int) -> int:
    __nat_range("reset", n, 1, 1)
    s := __sig_arg("reset", a)
    r := __sig_install(s, 0)
    ds := __dyn_ds()
    __store64(__load64(ds + 232) + 8 * s, 0)
    __store64(__load64(ds + 240) + 8 * s, 0)
    return __dyn_int(r)

func __nat__native_signal__pending(n: int, a: int) -> int:
    __nat_range("pending", n, 1, 1)
    s := __sig_arg("pending", a)
    __sig_state(0)
    __sig_drain()
    return __dyn_int(__load64(__load64(__dyn_ds() + 240) + 8 * s))

func __nat__native_signal__take(n: int, a: int) -> int:
    __nat_range("take", n, 1, 1)
    s := __sig_arg("take", a)
    __sig_state(0)
    __sig_drain()
    q := __load64(__dyn_ds() + 240) + 8 * s
    v := __load64(q)
    __store64(q, 0)
    return __dyn_int(v)

func __nat__native_signal__take_all(n: int) -> int:
    __nat_range("take_all", n, 0, 0)
    __sig_state(0)
    __sig_drain()
    l := __dyn_list_new(0)
    s := 1
    while s < 65:
        q := __load64(__dyn_ds() + 240) + 8 * s
        c := __load64(q)
        __store64(q, 0)
        while c > 0:
            __dyn_list_push(l, __dyn_int(s))
            c -= 1
        s += 1
    return l

func __sig_any_queued() -> bool:
    s := 1
    while s < 65:
        if __load64(__load64(__dyn_ds() + 240) + 8 * s) > 0:
            return true
        s += 1
    return false

func __nat__native_signal__wait(n: int, a: int) -> int:
    __nat_range("wait", n, 1, 1)
    t := -1.0
    if a != 0:
        t = __nat_number("wait", a, "le délai")
        if not (t >= 0.0):
            __dyn_err("ArgumentError", "signal.wait : délai négatif")
    if __windows():
        return __dyn_bool(false)
    __sig_state(0)
    end := __nat_deadline(t)
    while true:
        __sig_drain()
        if __sig_any_queued() or __sig_pending_auto():
            return __dyn_bool(true)
        ms := 1000
        if end >= 0.0:
            ms = __nat_remaining_ms(end)
            if ms <= 0:
                return __dyn_bool(false)
            if ms > 1000:
                ms = 1000
        fd := __load64(__dyn_ds() + 208)
        if fd >= 0:
            __fd_poll1(fd, 1, ms)
        else:
            ts := __alloc_raw(16)
            __store64(ts, ms // 1000)
            __store64(ts + 8, (ms % 1000) * 1000000)
            __syscall(35, ts, 0)
    return 0

func __nat__native_signal__set_dispatcher(n: int, a: int) -> int:
    __nat_range("set_dispatcher", n, 1, 1)
    if __load64(__dyn_ds() + 120) != 0:
        return __dyn_bool(false)
    if a != 0 and not __dyn_is(a, 10):
        __dyn_err("TypeError", "signal.set_dispatcher : fonction attendue")
    __sig_state(0)
    __store64(__dyn_ds() + 248, a)
    return __dyn_bool(true)
# ---- _native_gc --------------------------------------------------------------------------------------------------
# Le ramasse-miettes natif mesure des octets (pas des objets) : statistiques approchées.

# Comptes du GC façon VM (état du mode dynamique) : [312] alloués [320] libérés [328] vivants [336] pic
# [344] seuil (objets vivants déclenchant une collecte : max(16384, 2 x vivants après la précédente)) [352] désactivé
# [360] stress (collecte toutes les n allocations) [376] collecte en cours [384] allocations restant avant le
# prochain contrôle [392] lot en cours (les comptes ne sont mis à jour qu'aux contrôles : allocation rapide).

# Allocations du lot en cours non encore comptées.
func __dyn_gc_pending(ds: int) -> int:
    return __load64(ds + 392) - __load64(ds + 384)

func __dyn_gc_flush(ds: int):
    k := __dyn_gc_pending(ds)
    live := __load64(ds + 328) + k
    __store64(ds + 328, live)
    __store64(ds + 312, __load64(ds + 312) + k)
    if live > __load64(ds + 336):
        __store64(ds + 336, live)
    __store64(ds + 392, __load64(ds + 384))

func __dyn_gc_rearm(ds: int):
    b := 1048576
    if __load64(ds + 352) == 0:
        b = __load64(ds + 344) - __load64(ds + 328)
        sv := __load64(ds + 360)
        if sv > 0 and sv < b:
            b = sv
        if b < 1:
            b = 1
    __store64(ds + 384, b)
    __store64(ds + 392, b)

func __dyn_gc_check(st: int):
    ds := __load64(__globals_start())
    __dyn_gc_flush(ds)
    if __load64(ds + 376) == 0 and __load64(ds + 352) == 0:
        if __load64(ds + 328) >= __load64(ds + 344) or __load64(ds + 360) > 0 or __load64(st + 256) > __load64(st + 264):
            __dyn_gc_run(st)
    __dyn_gc_rearm(ds)

func __dyn_gc_run(st: int):
    ds := __load64(__globals_start())
    __store64(ds + 376, 1)
    __rt_gc(st)
    __store64(ds + 376, 0)

func __dyn_gc_swept(liveObjs: int, freedObjs: int):
    ds := __load64(__globals_start())
    if ds == 0:
        return
    __dyn_gc_flush(ds)
    __store64(ds + 320, __load64(ds + 320) + freedObjs)
    __store64(ds + 328, liveObjs)
    # Comme la VM (2 x vivants), avec un plancher de 16384 objets : un balayage parcourt tout le tas, il doit
    # être amorti sur assez d'allocations (l'objet VM vaut ici plusieurs allocations du runtime).
    # Au moins 128 allocations par page de 64 Kio en service : le coût d'un balayage, proportionnel au tas,
    # reste amorti quand le tas a grandi puis s'est vidé.
    t := 2 * liveObjs
    if t < 16384:
        t = 16384
    if t < 128 * __load64(ds + 448):
        t = 128 * __load64(ds + 448)
    # pile profonde (récursion) : chaque collection en parcourt tous les mots
    # (pile du programme seulement : hors tâches async, dont les piles sont ailleurs)
    if __load64(__state() + 960) == 0:
        sw := (__stack_top() - __sp()) >> 3
        if sw > 0 and sw < 67108864 and t < sw:
            t = sw
    __store64(ds + 344, t)
    __dyn_gc_rearm(ds)

func __nat__native_gc__collect(n: int) -> int:
    __nat_range("collect", n, 0, 0)
    if __load64(__state() + 960) == 0:
        __gc_scrub()
    __rt_gc(__state())
    return 0

# Collecte explicite hors tâches : efface la zone morte sous la pile (anciens cadres) pour qu'aucune valeur périmée
# n'y retienne d'objet lors du parcours conservatif des cadres de la collecte.
func __gc_scrub():
    p := __sp() - 32768
    while p < __sp() - 16:
        __store64(p, 0)
        p += 8

func __nat__native_gc__stats(n: int) -> int:
    __nat_range("stats", n, 0, 0)
    ds := __dyn_ds()
    __dyn_gc_flush(ds)
    d := __dyn_dict_new()
    __nat_dict_put(d, "live", __dyn_int(__load64(ds + 328)))
    __nat_dict_put(d, "peak", __dyn_int(__load64(ds + 336)))
    __nat_dict_put(d, "allocated", __dyn_int(__load64(ds + 312)))
    __nat_dict_put(d, "freed", __dyn_int(__load64(ds + 320)))
    __nat_dict_put(d, "collections", __dyn_int(__load64(__state() + 488)))
    __nat_dict_put(d, "threshold", __dyn_int(__load64(ds + 344)))
    __nat_dict_put(d, "enabled", __dyn_bool(__load64(ds + 352) == 0))
    return d

func __nat__native_gc__enable(n: int, a: int) -> int:
    __nat_range("enable", n, 1, 1)
    ds := __dyn_ds()
    prev := __load64(ds + 352) == 0
    v := 1
    if __nat_bool("enable", a, "l'indicateur"):
        v = 0
    __dyn_gc_flush(ds)
    __store64(ds + 352, v)
    __dyn_gc_rearm(ds)
    return __dyn_bool(prev)

func __nat__native_gc__set_threshold(n: int, a: int) -> int:
    __nat_range("set_threshold", n, 1, 1)
    k := __nat_int("set_threshold", a, "le seuil")
    if k < 1:
        __dyn_err("ArgumentError", "'set_threshold' : seuil >= 1 requis")
    ds := __dyn_ds()
    prev := __load64(ds + 344)
    __dyn_gc_flush(ds)
    __store64(ds + 344, k)
    __dyn_gc_rearm(ds)
    return __dyn_int(prev)

func __nat__native_gc__set_stress(n: int, a: int) -> int:
    __nat_range("set_stress", n, 1, 1)
    k := __nat_int("set_stress", a, "l'intervalle")
    if k < 0:
        __dyn_err("ArgumentError", "'set_stress' : intervalle >= 0 requis")
    ds := __dyn_ds()
    __dyn_gc_flush(ds)
    __store64(ds + 360, k)
    __dyn_gc_rearm(ds)
    return 0

# ---- _native_net : octets et nombres (les sockets suivent) -----------------------------------------------------

func __nat__native_net__blen(n: int, a: int) -> int:
    __nat_range("blen", n, 1, 1)
    return __dyn_int(__nat_blen(__nat_str("blen", a, "les octets")))

func __nat__native_net__bfind(n: int, a: int, b: int, c: int) -> int:
    __nat_range("bfind", n, 3, 3)
    s := __nat_str("bfind", a, "les octets")
    sub := __nat_str("bfind", b, "le motif")
    start := __nat_int("bfind", c, "le début")
    if start < 0 or start > __nat_blen(s):
        return __dyn_int(-1)
    return __dyn_int(__dyn_find_bytes(s, sub, start))

func __nat__native_net__bslice(n: int, a: int, b: int, c: int) -> int:
    __nat_range("bslice", n, 3, 3)
    s := __nat_str("bslice", a, "les octets")
    lo := __nat_int("bslice", b, "le début")
    hi := __nat_int("bslice", c, "la fin")
    m := __nat_blen(s)
    if lo < 0:
        lo = 0
    if hi > m:
        hi = m
    if hi <= lo:
        return __dyn_str("")
    return __dyn_str(__nat_sub(s, lo, hi - lo))

func __nat__native_net__utf8_prefix(n: int, a: int) -> int:
    __nat_range("utf8_prefix", n, 1, 1)
    s := __nat_str("utf8_prefix", a, "les octets")
    m := __nat_blen(s)
    p := __nat_bp(s)
    i := m
    back := 0
    while i > 0 and back < 4 and (__load8(p + i - 1) & 192) == 128:
        i -= 1
        back += 1
    if i == 0:
        return __dyn_int(m)
    lead := __load8(p + i - 1)
    need := 1
    if lead >= 240:
        need = 4
    elif lead >= 224:
        need = 3
    elif lead >= 192:
        need = 2
    if need > 1 and back + 1 < need:
        return __dyn_int(i - 1)
    return __dyn_int(m)

func __nat__native_net__to_bytes(n: int, a: int) -> int:
    __nat_range("to_bytes", n, 1, 1)
    return __nat_bytes_list(__nat_str("to_bytes", a, "les octets"))

func __nat__native_net__from_bytes(n: int, a: int) -> int:
    __nat_range("from_bytes", n, 1, 1)
    items := __nat_items("from_bytes", a, "les octets", "une list")
    k := __load64(items)
    r := __rt_str_new(k)
    i := 0
    while i < k:
        b := __nat_int("from_bytes", __rt_vec_at(items, i), "un octet")
        if b < 0 or b > 255:
            __dyn_err("ArgumentError", "'from_bytes' : octet hors de 0..255")
        __store8(r + 8 + i, b)
        i += 1
    return __dyn_str(__as_str(r))

func __nat__native_net__mask(n: int, a: int, b: int) -> int:
    __nat_range("mask", n, 2, 2)
    data := __nat_str("mask", a, "les données")
    key := __nat_str("mask", b, "la clé")
    kl := __nat_blen(key)
    if kl == 0:
        __dyn_err("ArgumentError", "'mask' : clé vide")
    m := __nat_blen(data)
    r := __rt_str_new(m)
    i := 0
    while i < m:
        __store8(r + 8 + i, __load8(__nat_bp(data) + i) ^ __load8(__nat_bp(key) + i % kl))
        i += 1
    return __dyn_str(__as_str(r))

func __nat__native_net__utf8_valid(n: int, a: int) -> int:
    __nat_range("utf8_valid", n, 1, 1)
    s := __nat_str("utf8_valid", a, "les octets")
    p := __nat_bp(s)
    m := __nat_blen(s)
    i := 0
    while i < m:
        c := __load8(p + i)
        if c < 128:
            i += 1
            continue
        need := 0
        cp := 0
        if c >= 194 and c <= 223:
            need = 1
            cp = c & 31
        elif c >= 224 and c <= 239:
            need = 2
            cp = c & 15
        elif c >= 240 and c <= 244:
            need = 3
            cp = c & 7
        else:
            return __dyn_bool(false)
        if i + need >= m:
            return __dyn_bool(false)
        k := 1
        while k <= need:
            if (__load8(p + i + k) & 192) != 128:
                return __dyn_bool(false)
            cp = (cp << 6) | (__load8(p + i + k) & 63)
            k += 1
        if (need == 2 and cp < 2048) or (need == 3 and cp < 65536) or cp > 1114111 or (cp >= 55296 and cp <= 57343):
            return __dyn_bool(false)
        i += need + 1
    return __dyn_bool(true)

func __nat__native_net__f64_bits(n: int, a: int) -> int:
    __nat_range("f64_bits", n, 1, 1)
    return __dyn_int(__f2bits(__nat_number("f64_bits", a, "la valeur")))

func __nat__native_net__bits_f64(n: int, a: int) -> int:
    __nat_range("bits_f64", n, 1, 1)
    return __dyn_float(__bits2f(__nat_int("bits_f64", a, "les bits")))

# float -> bits IEEE 754 simple précision (arrondi au plus proche, pair en cas d'égalité, comme le C++).
func __nat_f32_bits(d: float) -> int:
    b := __f2bits(d)
    sign := 0
    if b < 0:
        sign = 2147483648
    e := (b >> 52) & 2047
    m := b & 4503599627370495
    if e == 2047:
        if m == 0:
            return sign | 2139095040
        return sign | 2143289344 | ((m >> 29) & 4194303)
    if e == 0:
        return sign
    full := m | 4503599627370496
    fe := e - 1023 + 127
    shift := 29
    if fe <= 0:
        shift = 30 - fe
        fe = 0
    if shift > 60:
        return sign
    q := full >> shift
    rem := full & ((1 << shift) - 1)
    half := 1 << (shift - 1)
    if rem > half or (rem == half and (q & 1) == 1):
        q += 1
    if fe == 0:
        return sign | q
    if q >= 16777216:
        q = q >> 1
        fe += 1
    if fe >= 255:
        return sign | 2139095040
    return sign | (fe << 23) | (q & 8388607)

func __nat_f32_value(bits: int) -> float:
    sign := (bits >> 31) & 1
    fe := (bits >> 23) & 255
    fm := bits & 8388607
    v := 0.0
    if fe == 255:
        db := 9218868437227405312 | (fm << 29)
        if sign == 1:
            db = db | (-9223372036854775807 - 1)
        return __bits2f(db)
    if fe == 0:
        v = __i2f(fm) * __bits2f(3936146074321813504) # 2^-149
    else:
        v = __bits2f(((fe - 127 + 1023) << 52) | (fm << 29))
    if sign == 1:
        return 0.0 - v
    return v

func __nat__native_net__f32_bits(n: int, a: int) -> int:
    __nat_range("f32_bits", n, 1, 1)
    return __dyn_int(__nat_f32_bits(__nat_number("f32_bits", a, "la valeur")))

func __nat__native_net__bits_f32(n: int, a: int) -> int:
    __nat_range("bits_f32", n, 1, 1)
    return __dyn_float(__nat_f32_value(__nat_int("bits_f32", a, "les bits") & 4294967295))

# ---- Processus fils : fork + execve (posix_spawnp de la VM) ------------------------------------------------------

# Tableau C (NULL final) de chaînes natives (liste native d'adresses de chaînes).
func __nat_cvec(l: int) -> int:
    k := __load64(l)
    v := __alloc_raw(8 * k + 8)
    i := 0
    while i < k:
        __store64(v + 8 * i, __nat_c(__as_str(__rt_vec_at(l, i))))
        i += 1
    __store64(v + 8 * k, 0)
    return v

func __nat_wexit(st: int) -> int: # WEXITSTATUS / -WTERMSIG
    if (st & 127) == 0:
        return (st >> 8) & 255
    if ((st & 127) + 1) >> 1 > 0 and (st & 127) != 127:
        return 0 - (st & 127)
    return -1

func __nat_waitpid(pid: int, flags: int) -> int: # [r][statut] : r < 0 erreur, 0 pas fini (WNOHANG)
    st := __alloc_raw(8)
    __store64(st, 0)
    while true:
        r := __syscall(61, pid, st, flags, 0)
        if r == -4:
            continue
        out := __alloc_raw(16)
        __store64(out, r)
        __store64(out + 8, __nat_wexit(__load32(st)))
        return out
    return 0

func __nat_sigpipe(ignore: bool) -> int: # SIGPIPE ignoré (ou rétabli) ; renvoie l'ancienne action
    act := __alloc_raw(32)
    __zero(act, 32)
    if ignore:
        __store64(act, 1)
    old := __alloc_raw(32)
    __syscall(13, 13, act, old, 8)
    return old

func __nat_sigpipe_restore(old: int):
    __syscall(13, 13, old, 0, 8)

# Lance `prog` (recherché dans PATH s'il ne contient pas de « / »). in/out/err : -1 hériter, -2 /dev/null,
# -3 fusion avec la sortie (stderr seulement), sinon descripteur à mettre en place ; fdsToClose : liste native de
# descripteurs à fermer dans le fils (côtés parents des tubes). Renvoie le pid, ou -errno.
func __nat_spawn(prog: str, args: int, cwd: str, env: int, inFd: int, outFd: int, errFd: int, group: bool) -> int:
    __flush()
    argl := __rt_list_new(0)
    __rt_list_push(argl, __str_addr(prog))
    i := 0
    while i < __load64(args):
        __rt_list_push(argl, __rt_vec_at(args, i))
        i += 1
    argv := __nat_cvec(argl)
    envl := env
    if envl == 0:
        envl = __nat_env()
    envp := __nat_cvec(envl)
    # chemins candidats
    cands := __rt_list_new(0)
    if __dyn_find_bytes(prog, "/", 0) >= 0:
        __rt_list_push(cands, __nat_c(prog))
    else:
        path := __nat_env_get("PATH", "/bin:/usr/bin")
        dirs := __nat_split_bytes(path, 58)
        j := 0
        while j < __load64(dirs):
            d := __as_str(__rt_vec_at(dirs, j))
            if __nat_blen(d) == 0:
                d = "."
            __rt_list_push(cands, __nat_c(d + "/" + prog))
            j += 1
    devnull := __nat_c("/dev/null")
    cwdc := 0
    if __nat_blen(cwd) > 0:
        cwdc = __nat_c(cwd)
    ep := __alloc_raw(8)
    if __syscall(293, ep, 524288) < 0:
        return -24
    er := __load32(ep)
    ew := __load32(ep + 4)
    pid := __syscall(57)
    if pid < 0:
        __syscall(3, er)
        __syscall(3, ew)
        return pid
    if pid == 0:
        # ---- fils : appels système seulement ----
        e := 0
        if group:
            __syscall(109, 0, 0)
        if inFd >= 0:
            __syscall(33, inFd, 0)
        elif inFd == -2:
            nd := __syscall(2, devnull, 0)
            __syscall(33, nd, 0)
        if outFd >= 0:
            __syscall(33, outFd, 1)
        elif outFd == -2:
            nd := __syscall(2, devnull, 1)
            __syscall(33, nd, 1)
        if errFd >= 0:
            __syscall(33, errFd, 2)
        elif errFd == -2:
            nd := __syscall(2, devnull, 1)
            __syscall(33, nd, 2)
        elif errFd == -3:
            __syscall(33, 1, 2)
        if cwdc != 0:
            r := __syscall(80, cwdc)
            if r < 0:
                e = 0 - r
        if e == 0:
            seenAcces := false
            k := 0
            while k < __load64(cands):
                r := __syscall(59, __rt_vec_at(cands, k), argv, envp)
                e = 0 - r
                if e == 13:
                    seenAcces = true
                if e != 2 and e != 20 and e != 13:
                    break
                k += 1
            if seenAcces and (e == 2 or e == 20):
                e = 13
        buf := __alloc_raw(8)
        __store32(buf, e)
        __syscall(1, ew, buf, 4)
        __syscall(231, 127)
    __syscall(3, ew)
    buf := __alloc_raw(8)
    __store32(buf, 0)
    k := __syscall(0, er, buf, 4)
    while k == -4:
        k = __syscall(0, er, buf, 4)
    __syscall(3, er)
    if k == 4:
        __nat_waitpid(pid, 0)
        return 0 - __load32(buf)
    return pid

func __nat_pipe2() -> int: # [lecture][écriture] (O_CLOEXEC), ou 0
    p := __alloc_raw(8)
    if __syscall(293, p, 524288) < 0:
        return 0
    out := __alloc_raw(16)
    __store64(out, __load32(p))
    __store64(out + 8, __load32(p + 4))
    return out

# Liste native de chaînes natives d'une list/tuple de str (requireStrList).
func __nat_str_items(fn: str, v: int, label: str) -> int:
    k := __dyn_kind(v)
    if k != 7 and k != 8:
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être une list de str (obtenu '" + __dyn_type_name(v) + "')")
    items := __nat_items(fn, v, label, "une list")
    out := __rt_list_new(0)
    i := 0
    while i < __load64(items):
        __rt_list_push(out, __str_addr(__nat_cstr(fn, __rt_vec_at(items, i), label + " (élément)")))
        i += 1
    return out

func __nat_proc_fail(ctx: str, r: int):
    __nat_io_fail(ctx, __nat_errno_text(0 - r))

# ---- Windows : processus (os_backend_windows.cpp, process_backend_windows.cpp) -----------------------------------
# CreateProcessW (ligne de commande quotée selon CommandLineToArgvW, aucun shell), tubes anonymes dont seule
# l'extrémité du fils est héritable, erreurs rédigées par FormatMessageW (langue du système), comme la VM C++.
# Fiche d'un fils (_native_process) : celle de Linux, plus [80] poignée du processus [88] objet Job (groupe)
# [96] « signal » demandé par kill (code rapporté : -signal).

func __pw_last() -> int:
    if __windows():
        return __rt_w32(__wincall("GetLastError"))
    return 0

# Chaîne UTF-8 de n caractères UTF-16.
func __pw_narrow(w: int, n: int) -> str:
    if __windows():
        if n <= 0:
            return ""
        m := __rt_w32(__wincall("WideCharToMultiByte", 65001, 0, w, n, 0, 0, 0, 0))
        if m <= 0:
            return ""
        b := __alloc_raw(m + 8)
        __wincall("WideCharToMultiByte", 65001, 0, w, n, b, m, 0, 0)
        return __nat_make(b, m)
    return ""

# Texte d'une erreur Win32 (winErrorText du C++) : sans fin de ligne, espaces ni point finals.
func __pw_msg(code: int) -> str:
    if __windows():
        buf := __alloc_raw(1040)
        n := __rt_w32(__wincall("FormatMessageW", 4608, 0, code, 0, buf, 512, 0))
        if n == 0:
            return "erreur système " + __int_to_str(code)
        while n > 0:
            ch := __load16(buf + 2 * (n - 1))
            if ch == 13 or ch == 10 or ch == 32 or ch == 46:
                n -= 1
            else:
                break
        return __pw_narrow(buf, n)
    return ""

# Message d'erreur système de std::error_code (libstdc++ sous Windows) : FormatMessageA, octets de la page de
# code ANSI (pas de l'UTF-8), sans fin de ligne ni point final.
func __pw_msg_ansi(code: int) -> str:
    if __windows():
        buf := __alloc_raw(1040)
        n := __rt_w32(__wincall("FormatMessageA", 4608, 0, code, 0, buf, 1024, 0))
        if n == 0:
            return "erreur système " + __int_to_str(code)
        while n > 0 and (__load8(buf + n - 1) == 10 or __load8(buf + n - 1) == 13 or __load8(buf + n - 1) == 32):
            n -= 1
        if n > 0 and __load8(buf + n - 1) == 46:
            n -= 1
        return __nat_make(buf, n)
    return ""

func __pw_fail(ctx: str, code: int):
    if __windows():
        __nat_io_fail(ctx, __pw_msg(code))

func __pw_wide(s: str) -> int:
    if __windows():
        return __rt_win_wide(__nat_c(s))
    return 0

func __pw_close(h: int):
    if __windows():
        if h > 0:
            __wincall("CloseHandle", h)

# Argument quoté selon les règles de CommandLineToArgvW (appendQuoted du C++).
func __pw_quote(sb: int, a: str):
    if __windows():
        n := __nat_blen(a)
        p := __nat_bp(a)
        plain := n > 0
        i := 0
        while i < n and plain:
            c := __load8(p + i)
            if c == 32 or c == 9 or c == 10 or c == 11 or c == 34:
                plain = false
            i += 1
        if plain:
            __rt_sb_add(sb, a)
            return
        __rt_sb_byte(sb, 34)
        i = 0
        while true:
            bs := 0
            while i < n and __load8(p + i) == 92:
                i += 1
                bs += 1
            if i == n:
                k := 0
                while k < 2 * bs:
                    __rt_sb_byte(sb, 92)
                    k += 1
                break
            c := __load8(p + i)
            k := 0
            if c == 34:
                while k < 2 * bs + 1:
                    __rt_sb_byte(sb, 92)
                    k += 1
            else:
                while k < bs:
                    __rt_sb_byte(sb, 92)
                    k += 1
            __rt_sb_byte(sb, c)
            i += 1
        __rt_sb_byte(sb, 34)

# Ligne de commande UTF-16 (modifiable, comme CreateProcessW l'exige) : programme puis arguments (liste native).
func __pw_cmdline(prog: str, args: int) -> int:
    if __windows():
        sb := __rt_sb_new()
        __pw_quote(sb, prog)
        i := 0
        while i < __load64(args):
            __rt_sb_byte(sb, 32)
            __pw_quote(sb, __as_str(__rt_vec_at(args, i)))
            i += 1
        return __pw_wide(__rt_sb_str(sb))
    return 0

# Bloc d'environnement UTF-16 « A=1\0B=2\0\0 » d'une liste native de chaînes.
func __pw_env_block(env: int) -> int:
    if __windows():
        cap := 4
        i := 0
        while i < __load64(env):
            cap += __nat_blen(__as_str(__rt_vec_at(env, i))) + 1
            i += 1
        b := __alloc_raw(2 * cap + 8)
        pos := 0
        i = 0
        while i < __load64(env):
            e := __as_str(__rt_vec_at(env, i))
            if __nat_blen(e) > 0:
                pos += __rt_w32(__wincall("MultiByteToWideChar", 65001, 0, __nat_bp(e), __nat_blen(e), b + 2 * pos, cap - pos))
            __store16(b + 2 * pos, 0)
            pos += 1
            i += 1
        if __load64(env) == 0:
            __store16(b, 0)
            pos = 1
        __store16(b + 2 * pos, 0)
        return b
    return 0

func __pw_sa() -> int: # SECURITY_ATTRIBUTES héritable
    sa := __alloc_raw(24)
    __store64(sa, 24)
    __store64(sa + 8, 0)
    __store64(sa + 16, 1)
    return sa

# Tube anonyme [extrémité du parent (non héritable)][extrémité du fils], ou 0 (GetLastError).
func __pw_pipe(child_reads: bool, size: int) -> int:
    if __windows():
        hp := __alloc_raw(16)
        if __rt_w32(__wincall("CreatePipe", hp, hp + 8, __pw_sa(), size)) == 0:
            return 0
        r := __load64(hp)
        w := __load64(hp + 8)
        out := __alloc_raw(16)
        if child_reads:
            __store64(out, w)
            __store64(out + 8, r)
        else:
            __store64(out, r)
            __store64(out + 8, w)
        __wincall("SetHandleInformation", __load64(out), 1, 0)
        return out
    return 0

func __pw_nul(write: bool) -> int:
    if __windows():
        acc := 2147483648
        if write:
            acc = 1073741824
        h := __wincall("CreateFileW", __pw_wide("NUL"), acc, 3, __pw_sa(), 3, 0, 0)
        if h == -1:
            return 0
        return h
    return 0

# Copie héritable d'une poignée (0 si la source manque).
func __pw_dup(src: int) -> int:
    if __windows():
        if src == 0 or src == -1:
            return 0
        d := __alloc_raw(8)
        __store64(d, 0)
        if __rt_w32(__wincall("DuplicateHandle", -1, src, -1, d, 0, 1, 2)) == 0:
            return 0
        return __load64(d)
    return 0

func __pw_std(k: int) -> int:
    if __windows():
        return __wincall("GetStdHandle", -10 - k)
    return 0

# Flux standard d'un fils qui hérite de ceux du parent : copies héritables, données explicitement dans le
# STARTUPINFOW `si` (STARTF_USESTDHANDLES). Renvoie les drapeaux de création à ajouter : sans fenêtre console
# (sortie redirigée : IDE, CI, tube, fichier), CREATE_NO_WINDOW évite d'en ouvrir une — mais le fils recevrait
# alors une console neuve et invisible pour flux standard, et sa sortie serait perdue sans ces copies.
func __pw_si_inherit(si: int) -> int:
    if __windows():
        h0 := __pw_dup(__pw_std(0))
        h1 := __pw_dup(__pw_std(1))
        h2 := __pw_dup(__pw_std(2))
        if h0 != 0 or h1 != 0 or h2 != 0:
            __store32(si + 60, 256)
            __store64(si + 80, h0)
            __store64(si + 88, h1)
            __store64(si + 96, h2)
        if __wincall("GetConsoleWindow") == 0:
            return 134217728
        return 0
    return 0

# Ferme dans le parent les copies posées par __pw_si_inherit (après CreateProcessW).
func __pw_si_close(si: int):
    if __windows():
        if (__load32(si + 60) & 256) != 0:
            __pw_close(__load64(si + 80))
            __pw_close(__load64(si + 88))
            __pw_close(__load64(si + 96))

# Lance un processus ; poignées standard du fils (0 : aucune), environnement (liste native, 0 : celui du runtime),
# dossier ("" : courant), groupe (objet Job). Résultat [hProcess][pid][job], ou 0 : erreur Win32 en [8] de `err`.
func __pw_create(prog: str, args: int, cwd: str, env: int, cin: int, cout: int, cerr: int, group: bool, err: int) -> int:
    if __windows():
        cmd := __pw_cmdline(prog, args)
        eb := 0
        if env != 0:
            eb = __pw_env_block(env)
        else:
            eb = __pw_env_block(__nat_env())
        si := __alloc_raw(112)
        __zero(si, 112)
        __store32(si, 104)
        std := cin != 0 or cout != 0 or cerr != 0
        if std:
            __store32(si + 60, 256)
            __store64(si + 80, cin)
            __store64(si + 88, cout)
            __store64(si + 96, cerr)
        flags := 1024
        if group:
            flags = flags | 516
        if __wincall("GetConsoleWindow") == 0:
            flags = flags | 134217728
        wcwd := 0
        if __nat_blen(cwd) > 0:
            wcwd = __pw_wide(cwd)
        pi := __alloc_raw(32)
        __zero(pi, 32)
        if __rt_w32(__wincall("CreateProcessW", 0, cmd, 0, 0, 1, flags, eb, wcwd, si, pi)) == 0:
            __store64(err + 8, __pw_last())
            return 0
        r := __alloc_raw(24)
        __store64(r, __load64(pi))
        __store64(r + 8, __load32(pi + 16))
        __store64(r + 16, 0)
        if group:
            job := __wincall("CreateJobObjectW", 0, 0)
            if job != 0 and __rt_w32(__wincall("AssignProcessToJobObject", job, __load64(pi))) != 0:
                __store64(r + 16, job)
            else:
                __pw_close(job)
            __wincall("ResumeThread", __load64(pi + 8))
        __pw_close(__load64(pi + 8))
        return r
    return 0

# Code de sortie DWORD -> int signé (static_cast<int>).
func __pw_code(h: int) -> int:
    if __windows():
        b := __alloc_raw(8)
        __store64(b, 0)
        if __rt_w32(__wincall("GetExitCodeProcess", h, b)) == 0:
            return -9223372036854775807 - 1
        x := __load32(b)
        if x >= 2147483648:
            x -= 4294967296
        return x
    return 0

# Pause progressive (procb::backoff) : 0, 1, 2, 4, 8, 10 ms, bornée par l'échéance ; renvoie la pause suivante.
func __pw_backoff(pause: int, end: float) -> int:
    if __windows():
        left := __nat_remaining_ms_up(end)
        ms := pause
        if left >= 0 and left < ms:
            ms = left
        __wincall("Sleep", ms)
        if pause == 0:
            return 1
        if pause * 2 > 10:
            return 10
        return pause * 2
    return 0

# Lit ce qui est disponible sur un tube sans bloquer (pump) vers sb ; état [poignée][fin] à l'adresse `st`.
# true si des octets ont été lus ou si la fin du flux est atteinte.
func __pw_pump(st: int, sb: int) -> bool:
    if __windows():
        h := __load64(st)
        if h < 0:
            return false
        av := __alloc_raw(8)
        __store64(av, 0)
        if __rt_w32(__wincall("PeekNamedPipe", h, 0, 0, 0, av, 0)) == 0:
            __pw_close(h)
            __store64(st, -1)
            __store64(st + 8, 1)
            return true
        n := __load32(av)
        if n == 0:
            return false
        if n > 65536:
            n = 65536
        buf := __alloc_raw(n + 8)
        got := __alloc_raw(8)
        __store64(got, 0)
        if __rt_w32(__wincall("ReadFile", h, buf, n, got, 0)) == 0:
            __pw_close(h)
            __store64(st, -1)
            __store64(st + 8, 1)
            return true
        k := __load32(got)
        i := 0
        while i < k:
            __rt_sb_byte(sb, __load8(buf + i))
            i += 1
        return k > 0
    return false

# Échanges avec un fils : écrit `input` sur `inH` (tube rendu non bloquant), lit les tubes out / err jusqu'à leur
# fin (ou l'échéance). st : [in][_][out][fin out][err][fin err]. Renvoie true si le délai a expiré.
func __pw_exchange(st: int, input: str, so: int, se: int, end: float) -> bool:
    if __windows():
        written := 0
        m := __nat_blen(input)
        if __load64(st) >= 0:
            if m > 0:
                mode := __alloc_raw(8)
                __store64(mode, 1) # PIPE_NOWAIT
                __wincall("SetNamedPipeHandleState", __load64(st), mode, 0, 0)
            else:
                __pw_close(__load64(st))
                __store64(st, -1)
        pause := 0
        got := __alloc_raw(8)
        while __load64(st) >= 0 or __load64(st + 16) >= 0 or __load64(st + 32) >= 0:
            any := false
            if __load64(st) >= 0:
                k := m - written
                if k > 65536:
                    k = 65536
                __store64(got, 0)
                if __rt_w32(__wincall("WriteFile", __load64(st), __nat_bp(input) + written, k, got, 0)) == 0:
                    __pw_close(__load64(st))
                    __store64(st, -1)
                else:
                    if __load32(got) > 0:
                        any = true
                    written += __load32(got)
                    if written >= m:
                        __pw_close(__load64(st))
                        __store64(st, -1)
            if __pw_pump(st + 16, so):
                any = true
            if __pw_pump(st + 32, se):
                any = true
            if any:
                pause = 0
                continue
            if end >= 0.0 and __nat_clock(1) >= end:
                return true
            pause = __pw_backoff(pause, end)
        return false
    return false

# ---- os.spawn / run / execute / wait / kill / process_exists ----

func __pw_os_spawn(prog: str, args: int) -> int:
    if __windows():
        __flush()
        err := __alloc_raw(16)
        cin := __pw_dup(__pw_std(0))
        cout := __pw_dup(__pw_std(1))
        cerr := __pw_dup(__pw_std(2))
        r := __pw_create(prog, args, "", 0, cin, cout, cerr, false, err)
        __pw_close(cin)
        __pw_close(cout)
        __pw_close(cerr)
        if r == 0:
            __pw_fail(__nat_ctx("spawn", prog), __load64(err + 8))
        # poignée gardée jusqu'à os.wait : un fils déjà terminé reste interrogeable (sans elle, Windows libère son
        # pid et OpenProcess échoue : « Paramètre incorrect »)
        __rt_dict_set(__load64(__fd_st() + 16), __load64(r + 8), __load64(r), 0)
        return __dyn_int(__load64(r + 8))
    return 0

func __pw_os_run(prog: str, args: int, hasIn: bool, input: str) -> int:
    if __windows():
        ctx := __nat_ctx("run", prog)
        __flush()
        po := __pw_pipe(false, 0)
        if po == 0:
            __pw_fail(ctx, __pw_last())
        pe := __pw_pipe(false, 0)
        if pe == 0:
            __pw_fail(ctx, __pw_last())
        pin := 0
        cin := __pw_std(0)
        if hasIn:
            pin = __pw_pipe(true, 0)
            if pin == 0:
                __pw_fail(ctx, __pw_last())
            cin = __load64(pin + 8)
        err := __alloc_raw(16)
        r := __pw_create(prog, args, "", 0, cin, __load64(po + 8), __load64(pe + 8), false, err)
        __pw_close(__load64(po + 8))
        __pw_close(__load64(pe + 8))
        if hasIn:
            __pw_close(__load64(pin + 8))
        if r == 0:
            __pw_close(__load64(po))
            __pw_close(__load64(pe))
            if hasIn:
                __pw_close(__load64(pin))
            __pw_fail(ctx, __load64(err + 8))
        st := __alloc_raw(48)
        __store64(st, -1)
        if hasIn:
            __store64(st, __load64(pin))
        __store64(st + 16, __load64(po))
        __store64(st + 24, 0)
        __store64(st + 32, __load64(pe))
        __store64(st + 40, 0)
        so := __rt_sb_new()
        se := __rt_sb_new()
        __pw_exchange(st, input, so, se, -1.0)
        __wincall("WaitForSingleObject", __load64(r), 4294967295)
        code := __pw_code(__load64(r))
        if code == -9223372036854775807 - 1:
            e := __pw_last()
            __pw_close(__load64(r))
            __pw_fail(ctx, e)
        __pw_close(__load64(r))
        d := __dyn_dict_new()
        __nat_dict_put(d, "code", __dyn_int(code))
        __nat_dict_put(d, "stdout", __dyn_str(__rt_sb_str(so)))
        __nat_dict_put(d, "stderr", __dyn_str(__rt_sb_str(se)))
        return d
    return 0

# _wsystem : « %COMSPEC% /c commande » (cmd.exe), flux hérités ; code de sortie de cmd.
func __pw_os_execute(cmd: str) -> int:
    if __windows():
        __flush()
        comspec := __nat_env_get("COMSPEC", "")
        if __nat_blen(comspec) == 0:
            comspec = "cmd.exe"
        line := __pw_wide(comspec + " /c " + cmd)
        si := __alloc_raw(112)
        __zero(si, 112)
        __store32(si, 104)
        flags := 1024 | __pw_si_inherit(si)
        pi := __alloc_raw(32)
        __zero(pi, 32)
        ok := __rt_w32(__wincall("CreateProcessW", 0, line, 0, 0, 1, flags, __pw_env_block(__nat_env()), 0, si, pi))
        __pw_si_close(si)
        if ok == 0:
            __nat_io_fail(__nat_ctx("execute", cmd), "No such file or directory")
        __pw_close(__load64(pi + 8))
        __wincall("WaitForSingleObject", __load64(pi), 4294967295)
        code := __pw_code(__load64(pi))
        __pw_close(__load64(pi))
        return __dyn_int(code)
    return 0

func __pw_os_wait(pid: int, t: float) -> int:
    if __windows():
        ctx := "wait(" + __int_to_str(pid) + ")"
        spawned := __load64(__fd_st() + 16)
        e0 := __rt_dict_index(spawned, pid, 0)
        h := 0
        if e0 >= 0:
            h = __load64(__load64(spawned + 32) + 8 * e0)
            __rt_dict_remove(spawned, pid, 0)
        else:
            h = __wincall("OpenProcess", 1052672, 0, pid)
            if h == 0:
                __pw_fail(ctx, __pw_last())
        ms := 4294967295
        if t >= 0.0:
            v := t * 1000.0
            if v >= 4294967294.0:
                ms = 4294967294
            else:
                ms = __f2i(v)
        w := __rt_w32(__wincall("WaitForSingleObject", h, ms))
        if w == 258:
            if e0 >= 0: # délai écoulé : la poignée reste pour le prochain wait
                __rt_dict_set(spawned, pid, h, 0)
            else:
                __pw_close(h)
            return 0
        if w != 0:
            e := __pw_last()
            __pw_close(h)
            __pw_fail(ctx, e)
        code := __pw_code(h)
        if code == -9223372036854775807 - 1:
            e := __pw_last()
            __pw_close(h)
            __pw_fail(ctx, e)
        __pw_close(h)
        return __dyn_int(code)
    return 0

func __pw_exists(pid: int) -> bool:
    if __windows():
        h := __wincall("OpenProcess", 4096, 0, pid)
        if h == 0:
            return __pw_last() == 5
        code := __pw_code(h)
        __pw_close(h)
        return code == 259
    return false

func __pw_os_kill(pid: int, sig: int):
    if __windows():
        ctx := "kill(" + __int_to_str(pid) + ")"
        if sig == 0:
            if not __pw_exists(pid):
                __nat_io_fail(ctx, "Aucun processus de ce type")
            return
        h := __wincall("OpenProcess", 1, 0, pid)
        if h == 0:
            __pw_fail(ctx, __pw_last())
        if __rt_w32(__wincall("TerminateProcess", h, 1)) == 0:
            e := __pw_last()
            __pw_close(h)
            __pw_fail(ctx, e)
        __pw_close(h)

# ---- _native_process ----

func __pw_proc_spawn(ctx: str, prog: str, args: int, cwd: str, env: int, mi: int, mo: int, me: int, fdbuf: int, group: bool) -> int:
    if __windows():
        if __nat_blen(cwd) > 0:
            attr := __rt_w32(__wincall("GetFileAttributesW", __pw_wide(cwd)))
            if attr == 4294967295:
                __pw_fail(ctx, __pw_last())
            if (attr & 16) == 0:
                __nat_io_fail(ctx, "le répertoire de travail n'est pas un dossier : " + cwd)
        __flush()
        c := __alloc(104)
        __store64(c + 24, -1)
        __store64(c + 32, -1)
        __store64(c + 56, -1)
        __store64(c + 48, __str_addr(""))
        __store64(c + 72, __str_addr(""))
        cin := 0
        cout := 0
        cerr := 0
        fail := 0
        if mi == 1:
            p := __pw_pipe(true, 65536)
            if p == 0:
                fail = __pw_last()
            else:
                __store64(c + 24, __load64(p))
                cin = __load64(p + 8)
        elif mi == 2:
            cin = __pw_nul(false)
        elif mi == 4:
            cin = __pw_dup(__load64(fdbuf))
        else:
            cin = __pw_dup(__pw_std(0))
        if fail == 0:
            if mo == 1:
                p := __pw_pipe(false, 65536)
                if p == 0:
                    fail = __pw_last()
                else:
                    __store64(c + 32, __load64(p))
                    cout = __load64(p + 8)
            elif mo == 2:
                cout = __pw_nul(true)
            elif mo == 4:
                cout = __pw_dup(__load64(fdbuf + 8))
            else:
                cout = __pw_dup(__pw_std(1))
        if fail == 0:
            if me == 1:
                p := __pw_pipe(false, 65536)
                if p == 0:
                    fail = __pw_last()
                else:
                    __store64(c + 56, __load64(p))
                    cerr = __load64(p + 8)
            elif me == 2:
                cerr = __pw_nul(true)
            elif me == 3:
                cerr = cout
            elif me == 4:
                cerr = __pw_dup(__load64(fdbuf + 16))
            else:
                cerr = __pw_dup(__pw_std(2))
        err := __alloc_raw(16)
        r := 0
        if fail == 0:
            r = __pw_create(prog, args, cwd, env, cin, cout, cerr, group, err)
            if r == 0:
                fail = __load64(err + 8)
        __pw_close(cin)
        __pw_close(cout)
        if cerr != cout:
            __pw_close(cerr)
        if fail != 0:
            __pw_close(__load64(c + 24))
            __pw_close(__load64(c + 32))
            __pw_close(__load64(c + 56))
            __pw_fail(ctx, fail)
        __store64(c, __load64(r + 8))
        __store64(c + 80, __load64(r))
        __store64(c + 88, __load64(r + 16))
        return c
    return 0

func __pw_finish(c: int, ctx: str) -> int:
    if __windows():
        code := __pw_code(__load64(c + 80))
        if code == -9223372036854775807 - 1:
            __pw_fail(ctx, __pw_last())
        if __load64(c + 96) > 0:
            code = 0 - __load64(c + 96)
        __store64(c + 8, 1)
        __store64(c + 16, code)
        return __dyn_int(code)
    return 0

func __pw_proc_wait(c: int, t: float, ctx: str) -> int:
    if __windows():
        if __load64(c + 8) != 0:
            return __dyn_int(__load64(c + 16))
        ms := 4294967295
        if t >= 0.0:
            v := t * 1000.0
            if v <= 0.0:
                ms = 0
            elif v >= 4294967000.0:
                ms = 4294967000
            else:
                ms = __f2i(v) + 1
        w := __rt_w32(__wincall("WaitForSingleObject", __load64(c + 80), ms))
        if w == 258:
            return 0
        if w != 0:
            __pw_fail(ctx, __pw_last())
        return __pw_finish(c, ctx)
    return 0

func __pw_proc_kill(c: int, sig: int, group: bool):
    if __windows():
        if __load64(c + 8) != 0:
            return
        hp := __load64(c + 80)
        if __rt_w32(__wincall("WaitForSingleObject", hp, 0)) == 0:
            return
        if sig == 0:
            return
        ok := 0
        if group and __load64(c + 88) > 0:
            ok = __rt_w32(__wincall("TerminateJobObject", __load64(c + 88), 128 + sig))
        else:
            ok = __rt_w32(__wincall("TerminateProcess", hp, 128 + sig))
        if ok == 0:
            e := __pw_last()
            if __rt_w32(__wincall("WaitForSingleObject", hp, 0)) == 0:
                return
            __pw_fail("kill()", e)
        __store64(c + 96, sig)

# Lecture d'un flux capturé (fill) : bloquante sans échéance, sinon sondage avec pause progressive.
func __pw_fill(c: int, off: int, end: float, ctx: str) -> bool:
    if __windows():
        if end < 0.0:
            h := __load64(c + off)
            buf := __alloc_raw(65536)
            got := __alloc_raw(8)
            while true:
                __store64(got, 0)
                if __rt_w32(__wincall("ReadFile", h, buf, 65536, got, 0)) == 0:
                    e := __pw_last()
                    if e != 109 and e != 38 and e != 232:
                        __pw_fail(ctx, e)
                    __pw_close(h)
                    __store64(c + off, -1)
                    __store64(c + off + 8, 1)
                    return true
                k := __load32(got)
                if k > 0:
                    __store64(c + off + 16, __str_addr(__as_str(__load64(c + off + 16)) + __nat_make(buf, k)))
                    return true
            return true
        pause := 0
        while true:
            sb := __rt_sb_new()
            if __pw_pump(c + off, sb):
                __store64(c + off + 16, __str_addr(__as_str(__load64(c + off + 16)) + __rt_sb_str(sb)))
                return true
            if __nat_clock(1) >= end:
                return false
            pause = __pw_backoff(pause, end)
        return false
    return false

func __pw_proc_write(c: int, data: str) -> int:
    if __windows():
        h := __load64(c + 24)
        if h < 0:
            __nat_io_fail("write()", "stdin n'est pas ouvert (mode pipe requis, ou déjà fermé)")
        done := 0
        m := __nat_blen(data)
        got := __alloc_raw(8)
        while done < m:
            k := m - done
            if k > 65536:
                k = 65536
            __store64(got, 0)
            if __rt_w32(__wincall("WriteFile", h, __nat_bp(data) + done, k, got, 0)) == 0:
                __pw_fail("write()", __pw_last())
            done += __load32(got)
        return __dyn_int(done)
    return 0

func __pw_proc_communicate(c: int, hasIn: bool, input: str, end: float) -> int:
    if __windows():
        so := __rt_sb_new()
        se := __rt_sb_new()
        __rt_sb_add(so, __as_str(__load64(c + 48)))
        __rt_sb_add(se, __as_str(__load64(c + 72)))
        __store64(c + 48, __str_addr(""))
        __store64(c + 72, __str_addr(""))
        st := __alloc_raw(48)
        __store64(st, __load64(c + 24))
        __store64(st + 16, __load64(c + 32))
        __store64(st + 24, __load64(c + 40))
        __store64(st + 32, __load64(c + 56))
        __store64(st + 40, __load64(c + 64))
        data := ""
        if hasIn:
            data = input
        timedOut := __pw_exchange(st, data, so, se, end)
        __store64(c + 24, __load64(st))
        __store64(c + 32, __load64(st + 16))
        __store64(c + 40, __load64(st + 24))
        __store64(c + 56, __load64(st + 32))
        __store64(c + 64, __load64(st + 40))
        dd := __dyn_dict_new()
        __nat_dict_put(dd, "stdout", __dyn_str(__rt_sb_str(so)))
        __nat_dict_put(dd, "stderr", __dyn_str(__rt_sb_str(se)))
        __nat_dict_put(dd, "timed_out", __dyn_bool(timedOut))
        return dd
    return 0


# ---- Windows : os (os_backend_windows.cpp) ----

# Chemin absolu normalisé (GetFullPathNameW : « . », « .. », « / » -> « \ »), comme std::filesystem::absolute.
func __pw_full_path(path: str) -> str:
    if __windows():
        w := __pw_wide(path)
        cap := 1024
        while true:
            buf := __alloc_raw(2 * cap + 8)
            k := __rt_w32(__wincall("GetFullPathNameW", w, cap, buf, 0))
            if k == 0:
                return path
            if k < cap:
                return __pw_narrow(buf, k)
            cap = k + 1
        return path
    return ""

# Même fichier (volume et index), comme std::filesystem::equivalent.
func __pw_same_file(a: str, b: str) -> bool:
    if __windows():
        ia := __pw_file_id(a)
        ib := __pw_file_id(b)
        return ia != 0 and ib != 0 and __load64(ia) == __load64(ib) and __load64(ia + 8) == __load64(ib + 8)
    return false

func __pw_file_id(p: str) -> int:
    if __windows():
        h := __wincall("CreateFileW", __pw_wide(p), 0, 7, 0, 3, 33554432, 0)
        if h == -1:
            return 0
        bi := __alloc_raw(56)
        ok := __rt_w32(__wincall("GetFileInformationByHandle", h, bi))
        __pw_close(h)
        if ok == 0:
            return 0
        r := __alloc_raw(16)
        __store64(r, __load32(bi + 28))
        __store64(r + 8, (__load32(bi + 44) << 32) | __load32(bi + 48))
        return r
    return 0

func __pw_username() -> int:
    if __windows():
        buf := __alloc_raw(1040)
        sz := __alloc_raw(8)
        __store64(sz, 512)
        if __rt_w32(__wincall("advapi32.dll!GetUserNameW", buf, sz)) != 0 and __load32(sz) > 0:
            u := __pw_narrow(buf, __load32(sz) - 1)
            if __nat_blen(u) > 0:
                return __dyn_str(u)
            return 0
        u := __nat_env_get("USERNAME", "")
        if __nat_blen(u) == 0:
            return 0
        return __dyn_str(u)
    return 0

func __pw_cpu_count() -> int:
    if __windows():
        m := __alloc_raw(16)
        __zero(m, 16)
        if __rt_w32(__wincall("GetProcessAffinityMask", -1, m, m + 8)) != 0 and __load64(m) != 0:
            k := 0
            v := __load64(m)
            while v != 0:
                k += v & 1
                v = (v >> 1) & 9223372036854775807
            if k > 0:
                return k
        si := __alloc_raw(64)
        __zero(si, 64)
        __wincall("GetSystemInfo", si)
        k := __load32(si + 32)
        if k > 0:
            return k
        return 1
    return 0

func __pw_exec_ext(path: str) -> bool:
    if __windows():
        n := __nat_blen(path)
        p := __nat_bp(path)
        dot := -1
        sep := -1
        i := 0
        while i < n:
            c := __load8(p + i)
            if c == 46:
                dot = i
            if c == 47 or c == 92:
                sep = i
            i += 1
        if dot < 0 or dot < sep:
            return false
        ext := __nat_case(__nat_sub(path, dot, n - dot), 1)
        return ext == ".exe" or ext == ".bat" or ext == ".cmd" or ext == ".com"
    return false

func __pw_attrs(path: str) -> int:
    if __windows():
        return __rt_w32(__wincall("GetFileAttributesW", __pw_wide(path)))
    return 0

# _waccess + extensions exécutables (accessPath du C++).
func __pw_access(path: str, bits: int) -> bool:
    if __windows():
        at := __pw_attrs(path)
        if at == 4294967295:
            return false
        if (bits & 2) != 0 and (at & 1) != 0 and (at & 16) == 0:
            return false
        if (bits & 1) != 0:
            if (at & 16) == 0 and not __pw_exec_ext(path):
                return false
        return true
    return false

# _wchmod : seul le bit d'écriture du propriétaire compte (attribut lecture seule) ; erreur errno.
func __pw_chmod(path: str, mode: int):
    if __windows():
        w := __pw_wide(path)
        at := __rt_w32(__wincall("GetFileAttributesW", w))
        if at == 4294967295:
            __nat_io_fail(__nat_ctx("chmod", path), __nat_errno_text(__rt_win_errno()))
        if (mode & 128) != 0:
            at = at & 4294967294
        else:
            at = at | 1
        if __rt_w32(__wincall("SetFileAttributesW", w, at)) == 0:
            __nat_io_fail(__nat_ctx("chmod", path), __nat_errno_text(__rt_win_errno()))

# Secondes depuis 1970 -> FILETIME (centaines de ns depuis 1601).
func __pw_filetime(t: float, out: int):
    if __windows():
        ticks := (t + 11644473600.0) * 10000000.0
        if ticks < 0.0:
            ticks = 0.0
        __store64(out, __f2i(ticks))

func __pw_set_times(path: str, n: int, b: int, c: int):
    if __windows():
        ctx := __nat_ctx("set_times", path)
        fa := 0
        fm := 0
        if b != 0:
            fa = __alloc_raw(8)
            __pw_filetime(__nat_number("set_times", b, "la date d'accès"), fa)
        if c != 0:
            fm = __alloc_raw(8)
            __pw_filetime(__nat_number("set_times", c, "la date de modification"), fm)
        h := __wincall("CreateFileW", __pw_wide(path), 256, 7, 0, 3, 33554432, 0)
        if h == -1:
            __pw_fail(ctx, __pw_last())
        ok := __rt_w32(__wincall("SetFileTime", h, 0, fa, fm))
        e := __pw_last()
        __pw_close(h)
        if ok == 0:
            __pw_fail(ctx, e)

# ---- Windows : réseau (Winsock 2 : sockets derrière les appels système, voir RuntimeWindows) -------------------
# Résolution par getaddrinfo (pas de /etc/resolv.conf) ; fichier hosts de Windows ; interfaces par
# GetAdaptersAddresses. La VM C++ compilée pour Windows n'a pas de réseau : alexvm.exe va au-delà.

func __pw_hosts_path() -> str:
    if __windows():
        root := __nat_env_get("SystemRoot", "C:\\Windows")
        return root + "\\System32\\drivers\\etc\\hosts"
    return ""

# Résolution : liste native d'entrées [famille, adresse] ; en cas d'échec, message (chaîne) rangé dans err[0].
func __pw_resolve(host: str, fam: int, udp: bool, err: int) -> int:
    if __windows():
        __rt_ws_table()
        hints := __alloc_raw(64)
        __zero(hints, 64)
        if fam == 4:
            __store32(hints + 4, 2)
        elif fam == 6:
            __store32(hints + 4, 23)
        if udp:
            __store32(hints + 8, 2)
        else:
            __store32(hints + 8, 1)
        res := __alloc_raw(8)
        __store64(res, 0)
        rc := __rt_w32(__wincall("ws2_32.dll!getaddrinfo", __nat_c(host), 0, hints, res))
        if rc != 0:
            msg := __pw_msg(rc)
            if rc == 11001 or rc == 11004:
                msg = "Name or service not known"
            elif rc == 11002:
                msg = "Temporary failure in name resolution"
            __store64(err, __str_addr(msg))
            return __rt_list_new(0)
        found := __rt_list_new(0)
        seen := __rt_list_new(0)
        ai := __load64(res)
        while ai != 0:
            af := __load32(ai + 4)
            sa := __load64(ai + 32)
            f := 0
            a := ""
            if af == 2:
                f = 4
                a = __ns_ntop4(sa + 4)
            elif af == 23:
                f = 6
                a = __ns_ntop6(sa + 8)
            if f != 0:
                key := __int_to_str(f) + a
                dup := false
                i := 0
                while i < __load64(seen):
                    if __rt_str_eq(__as_str(__rt_vec_at(seen, i)), key):
                        dup = true
                    i += 1
                if not dup:
                    __rt_list_push(seen, __str_addr(key))
                    e := __rt_list_new(0)
                    __rt_list_push(e, f)
                    __rt_list_push(e, __str_addr(a))
                    __rt_list_push(found, e)
            ai = __load64(ai + 40)
        __wincall("ws2_32.dll!freeaddrinfo", __load64(res))
        return found
    return 0

# Interfaces (GetAdaptersAddresses) : entrées [nom, 0, null, null, null, drapeaux, index] (lien) puis une par
# adresse [nom, famille, adresse, masque, diffusion, drapeaux, index], comme sous Linux.
func __pw_interfaces() -> int:
    if __windows():
        __rt_ws_table()
        size := __alloc_raw(8)
        cap := 16384
        buf := 0
        k := 0
        while k < 4:
            buf = __alloc_raw(cap)
            __store64(size, cap)
            r := __rt_w32(__wincall("iphlpapi.dll!GetAdaptersAddresses", 0, 14, 0, buf, size))
            if r == 0:
                break
            if r != 111:                     # ERROR_BUFFER_OVERFLOW
                return __dyn_int(0 - __rt_win_errno_of(r))
            cap = __load32(size) + 1024
            k += 1
        out := __dyn_list_new(0)
        links := __dyn_list_new(0)
        addrs := __dyn_list_new(0)
        ad := buf
        while ad != 0:
            index := __load32(ad + 4)
            fn := __load64(ad + 72)
            n := 0
            while fn != 0 and __load16(fn + 2 * n) != 0:
                n += 1
            name := __pw_narrow(fn, n)
            bits := 0
            if __load32(ad + 104) == 1:
                bits = 65
            if __load32(ad + 100) == 24:
                bits = bits | 8
            else:
                bits = bits | 4098
            fl := __nif_flags(bits)
            e := __dyn_list_new(0)
            __dyn_list_push(e, __dyn_str(name))
            __dyn_list_push(e, __dyn_int(0))
            __dyn_list_push(e, 0)
            __dyn_list_push(e, 0)
            __dyn_list_push(e, 0)
            __dyn_list_push(e, fl)
            __dyn_list_push(e, __dyn_int(index))
            __dyn_list_push(links, e)
            ua := __load64(ad + 24)
            while ua != 0:
                sa := __load64(ua + 16)
                af := __load16(sa)
                prefix := __load8(ua + 56)       # OnLinkPrefixLength (52 : LeaseLifetime)
                if af == 2 and prefix > 32:
                    prefix = 32
                elif prefix > 128:
                    prefix = 128
                f := 0
                if af == 2:
                    f = 4
                elif af == 23:
                    f = 6
                if f != 0:
                    a := __alloc_raw(16)
                    if f == 4:
                        __copy(a, sa + 4, 4)
                    else:
                        __copy(a, sa + 8, 16)
                    x := __dyn_list_new(0)
                    __dyn_list_push(x, __dyn_str(name))
                    __dyn_list_push(x, __dyn_int(f))
                    __dyn_list_push(x, __nif_addr(f, a))
                    __dyn_list_push(x, __nif_mask(f, prefix))
                    if f == 4 and __load32(ad + 100) != 24 and prefix < 32:
                        b := __alloc_raw(8)
                        m := 0
                        if prefix > 0:
                            m = (4294967295 << (32 - prefix)) & 4294967295
                        v := (__load8(a) << 24) | (__load8(a + 1) << 16) | (__load8(a + 2) << 8) | __load8(a + 3)
                        v = v | (4294967295 & ~m)
                        __store8(b, (v >> 24) & 255)
                        __store8(b + 1, (v >> 16) & 255)
                        __store8(b + 2, (v >> 8) & 255)
                        __store8(b + 3, v & 255)
                        __dyn_list_push(x, __nif_addr(4, b))
                    else:
                        __dyn_list_push(x, 0)
                    __dyn_list_push(x, __nif_flags(bits))
                    __dyn_list_push(x, __dyn_int(index))
                    __dyn_list_push(addrs, x)
                ua = __load64(ua + 8)
            ad = __load64(ad + 8)
        i := 0
        while i < __dyn_list_len(links):
            __dyn_list_push(out, __dyn_list_at(links, i))
            i += 1
        i = 0
        while i < __dyn_list_len(addrs):
            __dyn_list_push(out, __dyn_list_at(addrs, i))
            i += 1
        return out
    return 0

# ---- os : spawn, run, execute, wait, kill, process_exists ----

func __nat__native_os__spawn(n: int, a: int, b: int) -> int:
    __nat_range("spawn", n, 2, 2)
    prog := __nat_cstr("spawn", a, "le programme")
    if __nat_blen(prog) == 0:
        __dyn_err("ArgumentError", "'spawn' : programme vide")
    args := __nat_str_items("spawn", b, "les arguments")
    if __windows():
        return __pw_os_spawn(prog, args)
    pid := __nat_spawn(prog, args, "", 0, -1, -1, -1, false)
    if pid < 0:
        __nat_proc_fail(__nat_ctx("spawn", prog), pid)
    return __dyn_int(pid)

func __nat_drain(fd: int, sb: int) -> bool: # false : fin de flux
    buf := __alloc_raw(65536)
    k := __syscall(0, fd, buf, 65536)
    if k > 0:
        i := 0
        while i < k:
            __rt_sb_byte(sb, __load8(buf + i))
            i += 1
        return true
    if k == -4 or k == -11:
        return true
    return false

func __nat__native_os__run(n: int, a: int, b: int, c: int) -> int:
    __nat_range("run", n, 3, 3)
    prog := __nat_cstr("run", a, "le programme")
    if __nat_blen(prog) == 0:
        __dyn_err("ArgumentError", "'run' : programme vide")
    args := __nat_str_items("run", b, "les arguments")
    hasIn := c != 0
    input := ""
    if hasIn:
        input = __nat_cstr("run", c, "l'entrée")
    if __windows():
        return __pw_os_run(prog, args, hasIn, input)
    ctx := __nat_ctx("run", prog)
    po := __nat_pipe2()
    pe := __nat_pipe2()
    pin := 0
    if hasIn:
        pin = __nat_pipe2()
    inFd := -1
    if hasIn:
        inFd = __load64(pin)
    pid := __nat_spawn(prog, args, "", 0, inFd, __load64(po + 8), __load64(pe + 8), false)
    __syscall(3, __load64(po + 8))
    __syscall(3, __load64(pe + 8))
    if hasIn:
        __syscall(3, __load64(pin))
    if pid < 0:
        __syscall(3, __load64(po))
        __syscall(3, __load64(pe))
        if hasIn:
            __syscall(3, __load64(pin + 8))
        __nat_proc_fail(ctx, pid)
    outR := __load64(po)
    errR := __load64(pe)
    inW := -1
    old := 0
    if hasIn:
        inW = __load64(pin + 8)
        old = __nat_sigpipe(true)
        fl := __syscall(72, inW, 3, 0)
        if fl >= 0:
            __syscall(72, inW, 4, fl | 2048)
        if __nat_blen(input) == 0:
            __syscall(3, inW)
            inW = -1
    so := __rt_sb_new()
    se := __rt_sb_new()
    written := 0
    fds := __alloc_raw(24)
    while outR >= 0 or errR >= 0 or inW >= 0:
        k := 0
        iOut := -1
        iErr := -1
        iIn := -1
        if outR >= 0:
            iOut = k
            __store32(fds + 8 * k, outR)
            __store16(fds + 8 * k + 4, 1)
            __store16(fds + 8 * k + 6, 0)
            k += 1
        if errR >= 0:
            iErr = k
            __store32(fds + 8 * k, errR)
            __store16(fds + 8 * k + 4, 1)
            __store16(fds + 8 * k + 6, 0)
            k += 1
        if inW >= 0:
            iIn = k
            __store32(fds + 8 * k, inW)
            __store16(fds + 8 * k + 4, 4)
            __store16(fds + 8 * k + 6, 0)
            k += 1
        pr := __syscall(7, fds, k, -1)
        if pr == -4:
            continue
        if pr < 0:
            break
        if iOut >= 0 and (__load16(fds + 8 * iOut + 6) & 25) != 0:
            if not __nat_drain(outR, so):
                __syscall(3, outR)
                outR = -1
        if iErr >= 0 and (__load16(fds + 8 * iErr + 6) & 25) != 0:
            if not __nat_drain(errR, se):
                __syscall(3, errR)
                errR = -1
        if iIn >= 0 and __load16(fds + 8 * iIn + 6) != 0:
            if (__load16(fds + 8 * iIn + 6) & 4) != 0:
                w := __syscall(1, inW, __nat_bp(input) + written, __nat_blen(input) - written)
                if w > 0:
                    written += w
                    if written >= __nat_blen(input):
                        __syscall(3, inW)
                        inW = -1
                elif w < 0 and w != -11 and w != -4:
                    __syscall(3, inW)
                    inW = -1
            else:
                __syscall(3, inW)
                inW = -1
    if outR >= 0:
        __syscall(3, outR)
    if errR >= 0:
        __syscall(3, errR)
    if old != 0:
        __nat_sigpipe_restore(old)
    w := __nat_waitpid(pid, 0)
    if __load64(w) < 0:
        __nat_proc_fail(ctx, __load64(w))
    d := __dyn_dict_new()
    __nat_dict_put(d, "code", __dyn_int(__load64(w + 8)))
    __nat_dict_put(d, "stdout", __dyn_str(__rt_sb_str(so)))
    __nat_dict_put(d, "stderr", __dyn_str(__rt_sb_str(se)))
    return d

func __nat__native_os__execute(n: int, a: int) -> int:
    __nat_range("execute", n, 1, 1)
    cmd := __nat_cstr("execute", a, "la commande")
    if __windows():
        return __pw_os_execute(cmd)
    args := __rt_list_new(0)
    __rt_list_push(args, __str_addr("-c"))
    __rt_list_push(args, __str_addr(cmd))
    pid := __nat_spawn_named("/bin/sh", "sh", args)
    if pid < 0:
        __nat_proc_fail(__nat_ctx("execute", cmd), pid)
    w := __nat_waitpid(pid, 0)
    if __load64(w) < 0:
        __nat_proc_fail(__nat_ctx("execute", cmd), __load64(w))
    return __dyn_int(__load64(w + 8))

# Comme __nat_spawn, mais argv[0] = name (programme `path`, chemin complet).
func __nat_spawn_named(path: str, name: str, args: int) -> int:
    __flush()
    argl := __rt_list_new(0)
    __rt_list_push(argl, __str_addr(name))
    i := 0
    while i < __load64(args):
        __rt_list_push(argl, __rt_vec_at(args, i))
        i += 1
    argv := __nat_cvec(argl)
    envp := __nat_cvec(__nat_env())
    pc := __nat_c(path)
    pid := __syscall(57)
    if pid == 0:
        __syscall(59, pc, argv, envp)
        __syscall(231, 127)
    return pid

func __nat__native_os__wait(n: int, a: int, b: int) -> int:
    __nat_range("wait", n, 2, 2)
    pid := __nat_int("wait", a, "le pid")
    if pid <= 0:
        __dyn_err("ArgumentError", "'wait' : pid invalide (" + __int_to_str(pid) + ")")
    t := -1.0
    if b != 0:
        t = __nat_number("wait", b, "le délai")
        if not (t >= 0.0):
            __dyn_err("ArgumentError", "'wait' : délai négatif ou invalide")
    if __windows():
        return __pw_os_wait(pid, t)
    ctx := "wait(" + __int_to_str(pid) + ")"
    if t < 0.0:
        w := __nat_waitpid(pid, 0)
        if __load64(w) < 0:
            __nat_proc_fail(ctx, __load64(w))
        return __dyn_int(__load64(w + 8))
    end := __nat_clock(1) + t
    pause := 200
    ts := __alloc_raw(16)
    while true:
        w := __nat_waitpid(pid, 1)
        if __load64(w) < 0:
            __nat_proc_fail(ctx, __load64(w))
        if __load64(w) == pid:
            return __dyn_int(__load64(w + 8))
        if __nat_clock(1) >= end:
            return 0
        __store64(ts, 0)
        __store64(ts + 8, pause * 1000)
        __syscall(35, ts, 0)
        pause = pause * 2
        if pause > 10000:
            pause = 10000
    return 0

func __nat_signal_from_name(raw: str) -> int:
    name := __nat_case(raw, 0)
    if __nat_blen(name) >= 3 and __rt_str_eq(__nat_sub(name, 0, 3), "SIG"):
        name = __nat_sub(name, 3, __nat_blen(name) - 3)
    t := 0
    if __windows():
        t = __nat_split_bytes("HUP:1,INT:2,QUIT:3,ABRT:6,KILL:9,TERM:15", 44)
    else:
        t = __nat_split_bytes("HUP:1,INT:2,QUIT:3,ABRT:6,KILL:9,USR1:10,USR2:12,ALRM:14,TERM:15,STOP:19,CONT:18,TSTP:20", 44)
    i := 0
    while i < __load64(t):
        it := __as_str(__rt_vec_at(t, i))
        c := __dyn_find_bytes(it, ":", 0)
        if __rt_str_eq(__nat_sub(it, 0, c), name):
            return __rt_str_to_int(__nat_sub(it, c + 1, __nat_blen(it) - c - 1))
        i += 1
    return -1

func __nat_sig_arg(fn: str, v: int) -> int:
    if __dyn_is_str(v):
        name := __nat_cstr(fn, v, "le signal")
        sig := __nat_signal_from_name(name)
        if sig < 0:
            __dyn_err("ArgumentError", "'" + fn + "' : signal inconnu '" + name + "'")
        return sig
    k := __nat_int(fn, v, "le signal")
    if k < 0 or k > 64:
        __dyn_err("ArgumentError", "'" + fn + "' : numéro de signal invalide")
    return k

func __nat__native_os__kill(n: int, a: int, b: int) -> int:
    __nat_range("kill", n, 2, 2)
    pid := __nat_int("kill", a, "le pid")
    if pid <= 0:
        __dyn_err("ArgumentError", "'kill' : pid invalide (" + __int_to_str(pid) + ")")
    sig := __nat_sig_arg("kill", b)
    if __windows():
        __pw_os_kill(pid, sig)
        return 0
    r := __syscall(62, pid, sig)
    if r < 0:
        __nat_proc_fail("kill(" + __int_to_str(pid) + ")", r)
    return 0

func __nat__native_os__process_exists(n: int, a: int) -> int:
    __nat_range("process_exists", n, 1, 1)
    pid := __nat_int("process_exists", a, "le pid")
    if pid <= 0:
        return __dyn_bool(false)
    if __windows():
        return __dyn_bool(__pw_exists(pid))
    r := __syscall(62, pid, 0)
    return __dyn_bool(r == 0 or r == -1)

# ---- _native_process : fils avec flux redirigés ----
# Fils : [0] pid [8] attendu [16] code [24] stdin [32] stdout [40] fin de stdout [48] en attente (stdout, chaîne native)
# [56] stderr [64] fin de stderr [72] en attente (stderr). Table : état du mode dynamique [104] (handle -> fils), [112].

func __pr_table() -> int:
    ds := __dyn_ds()
    t := __load64(ds + 104)
    if t == 0:
        t = __rt_dict_new(8)
        __store64(ds + 104, t)
        __store64(ds + 112, 1)
    return t

func __pr_child(fn: str, v: int) -> int:
    h := __nat_int(fn, v, "le handle")
    t := __pr_table()
    e := __rt_dict_index(t, h, 0)
    if e < 0:
        __dyn_err("ArgumentError", "'" + fn + "' : handle de processus invalide ou déjà libéré (" + __int_to_str(h) + ")")
    return __load64(__load64(t + 32) + 8 * e)

# Mode d'un flux : 0 hériter, 1 tube, 2 /dev/null, 3 fusion (stderr), [4, fd] (descripteur) ; renvoie le mode
# (4 : descripteur en [out]).
func __pr_mode(fn: str, v: int, label: str, allowMerge: bool, out: int) -> int:
    if __dyn_is(v, 7) or __dyn_is(v, 8):
        l := __nat_items(fn, v, label, "une list")
        if __load64(l) != 2 or __nat_int(fn, __rt_vec_at(l, 0), label) != 4:
            __dyn_err("ArgumentError", "'" + fn + "' : mode " + label + " invalide")
        fd := __nat_int(fn, __rt_vec_at(l, 1), "le descripteur")
        if fd < 0 or fd > 1000000:
            __dyn_err("ArgumentError", "'" + fn + "' : descripteur invalide")
        __store64(out, fd)
        return 4
    m := __nat_int(fn, v, label)
    mx := 2
    if allowMerge:
        mx = 3
    if m < 0 or m > mx:
        __dyn_err("ArgumentError", "'" + fn + "' : mode " + label + " invalide (" + __int_to_str(m) + ")")
    return m

func __nat__native_process__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    return __dyn_bool(true)

func __nat__native_process__spawn(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                  a7: int, x: int) -> int:
    __nat_range("spawn", n, 8, 8)
    prog := __nat_cstr("spawn", a0, "le programme")
    if __nat_blen(prog) == 0:
        __dyn_err("ArgumentError", "'spawn' : programme vide")
    args := __nat_str_items("spawn", a1, "les arguments")
    cwd := ""
    if a2 != 0:
        cwd = __nat_cstr("spawn", a2, "cwd")
    env := 0
    if a3 != 0:
        env = __nat_str_items("spawn", a3, "env")
        i := 0
        while i < __load64(env):
            e := __as_str(__rt_vec_at(env, i))
            if __dyn_find_bytes(e, "=", 0) <= 0:
                __dyn_err("ArgumentError", "'spawn' : entrée d'environnement invalide '" + e + "' (attendu NOM=valeur)")
            i += 1
    fdbuf := __alloc_raw(24)
    mi := __pr_mode("spawn", a4, "stdin", false, fdbuf)
    mo := __pr_mode("spawn", a5, "stdout", false, fdbuf + 8)
    me := __pr_mode("spawn", a6, "stderr", true, fdbuf + 16)
    group := __nat_bool("spawn", a7, "group")
    ctx := __nat_ctx("spawn", prog)
    if __nat_blen(cwd) > 0:
        st := __nat_stat(cwd, false)
        if __nat_st_failed(st):
            __nat_io_fail(ctx, __nat_errno_text(__nat_st_errno(st)))
        if __nat_st_type(st) != 16384:
            __nat_io_fail(ctx, "le répertoire de travail n'est pas un dossier : " + cwd)
    if __windows():
        return __pr_register(__pw_proc_spawn(ctx, prog, args, cwd, env, mi, mo, me, fdbuf, group))
    pin := 0
    pout := 0
    perr := 0
    if mi == 1:
        pin = __nat_pipe2()
    if mo == 1:
        pout = __nat_pipe2()
    if me == 1:
        perr = __nat_pipe2()
    inFd := -1
    if mi == 1:
        inFd = __load64(pin)
    elif mi == 2:
        inFd = -2
    elif mi == 4:
        inFd = __load64(fdbuf)
    outFd := -1
    if mo == 1:
        outFd = __load64(pout + 8)
    elif mo == 2:
        outFd = -2
    elif mo == 4:
        outFd = __load64(fdbuf + 8)
    errFd := -1
    if me == 1:
        errFd = __load64(perr + 8)
    elif me == 2:
        errFd = -2
    elif me == 3:
        errFd = -3
    elif me == 4:
        errFd = __load64(fdbuf + 16)
    pid := __nat_spawn(prog, args, cwd, env, inFd, outFd, errFd, group)
    if mi == 1:
        __syscall(3, __load64(pin))
    if mo == 1:
        __syscall(3, __load64(pout + 8))
    if me == 1:
        __syscall(3, __load64(perr + 8))
    if pid < 0:
        if mi == 1:
            __syscall(3, __load64(pin + 8))
        if mo == 1:
            __syscall(3, __load64(pout))
        if me == 1:
            __syscall(3, __load64(perr))
        __nat_proc_fail(ctx, pid)
    c := __alloc(80)
    __store64(c, pid)
    __store64(c + 24, -1)
    __store64(c + 32, -1)
    __store64(c + 56, -1)
    __store64(c + 48, __str_addr(""))
    __store64(c + 72, __str_addr(""))
    if mi == 1:
        __store64(c + 24, __load64(pin + 8))
    if mo == 1:
        __store64(c + 32, __load64(pout))
    if me == 1:
        __store64(c + 56, __load64(perr))
    return __pr_register(c)

func __pr_register(c: int) -> int:
    t := __pr_table()
    h := __load64(__dyn_ds() + 112)
    __store64(__dyn_ds() + 112, h + 1)
    __rt_dict_set(t, h, c, 0)
    return __dyn_int(h)

func __nat__native_process__pid(n: int, a: int) -> int:
    __nat_range("pid", n, 1, 1)
    return __dyn_int(__load64(__pr_child("pid", a)))

func __pr_stream_no(fn: str, v: int) -> int:
    s := __nat_int(fn, v, "le flux")
    if s != 1 and s != 2:
        __dyn_err("ArgumentError", "'" + fn + "' : flux attendu 1 (stdout) ou 2 (stderr)")
    return s

# Flux : décalage du descripteur dans le fils (32 stdout, 56 stderr) ; vérifie qu'il est capturé.
func __pr_stream(c: int, which: int, ctx: str) -> int:
    off := 32
    if which == 2:
        off = 56
    if __load64(c + off) < 0 and __load64(c + off + 8) == 0 and __load64(__load64(c + off + 16)) == 0:
        nm := "stdout"
        if which == 2:
            nm = "stderr"
        __dyn_err("IoError", ctx + " : " + nm + " n'est pas capturé (mode pipe requis)")
    return off

# Lit une fois (après poll) vers les octets en attente ; false si le délai expire.
func __pr_fill(c: int, off: int, end: float, ctx: str) -> bool:
    if __windows():
        return __pw_fill(c, off, end, ctx)
    fd := __load64(c + off)
    while true:
        r := __fd_poll1(fd, 1, __nat_remaining_ms_up(end))
        if r == -4:
            continue
        if r < 0:
            __nat_io_fail(ctx, __nat_errno_text(0 - r))
        if r == 0:
            return false
        buf := __alloc_raw(65536)
        k := __syscall(0, fd, buf, 65536)
        if k == -4 or k == -11:
            continue
        if k < 0:
            __nat_io_fail(ctx, __nat_errno_text(0 - k))
        if k == 0:
            __store64(c + off + 8, 1)
            __syscall(3, fd)
            __store64(c + off, -1)
        else:
            __store64(c + off + 16, __str_addr(__as_str(__load64(c + off + 16)) + __nat_make(buf, k)))
        return true
    return false

func __nat_remaining_ms_up(end: float) -> int: # arrondi par excès (procb::remainingMs)
    if end < 0.0:
        return -1
    left := end - __nat_clock(1)
    if left <= 0.0:
        return 0
    ms := left * 1000.0
    if ms > 2000000000.0:
        return 2000000000
    return __f2i(ms) + 1

func __pr_complete_prefix(s: str) -> int:
    m := __nat_blen(s)
    p := __nat_bp(s)
    back := 1
    while back <= 3 and back <= m:
        c := __load8(p + m - back)
        if (c & 192) == 128:
            back += 1
            continue
        need := 1
        if c >= 240:
            need = 4
        elif c >= 224:
            need = 3
        elif c >= 192:
            need = 2
        if need > back:
            return m - back
        return m
    return m

func __nat__native_process__read(n: int, a: int, b: int, c2: int, d: int) -> int:
    __nat_range("read", n, 4, 4)
    c := __pr_child("read", a)
    which := __pr_stream_no("read", b)
    mx := __nat_int("read", c2, "max")
    if mx < 1 or mx > 1073741824:
        __dyn_err("ArgumentError", "'read' : max hors limites (1..2^30)")
    end := __nat_deadline(__nat_timeout("read", d))
    off := __pr_stream(c, which, "read()")
    while true:
        pend := __as_str(__load64(c + off + 16))
        ready := __pr_complete_prefix(pend)
        if ready == 0 and __load64(c + off + 8) != 0:
            ready = __nat_blen(pend)
        if ready > 0:
            take := ready
            if mx < take:
                take = mx
                while take < ready and (__load8(__nat_bp(pend) + take) & 192) == 128:
                    take += 1
            __store64(c + off + 16, __str_addr(__nat_sub(pend, take, __nat_blen(pend) - take)))
            return __dyn_str(__nat_sub(pend, 0, take))
        if __load64(c + off + 8) != 0:
            return __dyn_str("")
        if not __pr_fill(c, off, end, "read()"):
            return 0
    return 0

func __nat__native_process__read_line(n: int, a: int, b: int, d: int) -> int:
    __nat_range("read_line", n, 3, 3)
    c := __pr_child("read_line", a)
    which := __pr_stream_no("read_line", b)
    end := __nat_deadline(__nat_timeout("read_line", d))
    off := __pr_stream(c, which, "read_line()")
    while true:
        pend := __as_str(__load64(c + off + 16))
        nl := __dyn_find_bytes(pend, "\n", 0)
        if nl >= 0:
            __store64(c + off + 16, __str_addr(__nat_sub(pend, nl + 1, __nat_blen(pend) - nl - 1)))
            return __dyn_str(__nat_sub(pend, 0, nl + 1))
        if __load64(c + off + 8) != 0:
            __store64(c + off + 16, __str_addr(""))
            return __dyn_str(pend)
        if not __pr_fill(c, off, end, "read_line()"):
            return 0
    return 0

func __nat__native_process__write(n: int, a: int, b: int) -> int:
    __nat_range("write", n, 2, 2)
    c := __pr_child("write", a)
    data := __nat_str("write", b, "les données")
    fd := __load64(c + 24)
    if fd < 0:
        __nat_io_fail("write()", "stdin n'est pas ouvert (mode pipe requis, ou déjà fermé)")
    if __windows():
        return __pw_proc_write(c, data)
    old := __nat_sigpipe(true)
    done := 0
    m := __nat_blen(data)
    while done < m:
        k := __syscall(1, fd, __nat_bp(data) + done, m - done)
        if k == -4:
            continue
        if k < 0:
            __nat_sigpipe_restore(old)
            __nat_io_fail("write()", __nat_errno_text(0 - k))
        done += k
    __nat_sigpipe_restore(old)
    return __dyn_int(done)

func __nat__native_process__close_stdin(n: int, a: int) -> int:
    __nat_range("close_stdin", n, 1, 1)
    c := __pr_child("close_stdin", a)
    if __load64(c + 24) >= 0:
        __syscall(3, __load64(c + 24))
        __store64(c + 24, -1)
    return 0

func __pr_poll(c: int) -> int: # code, ou 0 (valeur null) si toujours vivant
    if __load64(c + 8) != 0:
        return __dyn_int(__load64(c + 16))
    if __windows():
        return __pw_proc_wait(c, 0.0, "poll()")
    w := __nat_waitpid(__load64(c), 1)
    if __load64(w) < 0:
        __nat_io_fail("poll()", __nat_errno_text(0 - __load64(w)))
    if __load64(w) == 0:
        return 0
    __store64(c + 8, 1)
    __store64(c + 16, __load64(w + 8))
    return __dyn_int(__load64(w + 8))

func __nat__native_process__poll(n: int, a: int) -> int:
    __nat_range("poll", n, 1, 1)
    return __pr_poll(__pr_child("poll", a))

func __nat__native_process__wait(n: int, a: int, b: int) -> int:
    __nat_range("wait", n, 2, 2)
    c := __pr_child("wait", a)
    t := __nat_timeout("wait", b)
    if __load64(c + 8) != 0:
        return __dyn_int(__load64(c + 16))
    if __windows():
        return __pw_proc_wait(c, t, "wait()")
    if t < 0.0:
        w := __nat_waitpid(__load64(c), 0)
        if __load64(w) < 0:
            __nat_io_fail("wait()", __nat_errno_text(0 - __load64(w)))
        __store64(c + 8, 1)
        __store64(c + 16, __load64(w + 8))
        return __dyn_int(__load64(w + 8))
    end := __nat_clock(1) + t
    pause := 200
    ts := __alloc_raw(16)
    while true:
        r := __pr_poll(c)
        if r != 0:
            return r
        if __nat_clock(1) >= end:
            return 0
        __store64(ts, 0)
        __store64(ts + 8, pause * 1000)
        __syscall(35, ts, 0)
        pause = pause * 2
        if pause > 10000:
            pause = 10000
    return 0

func __nat__native_process__kill(n: int, a: int, b: int, d: int) -> int:
    __nat_range("kill", n, 3, 3)
    c := __pr_child("kill", a)
    sig := __nat_sig_arg("kill", b)
    group := __nat_bool("kill", d, "group")
    if __windows():
        __pw_proc_kill(c, sig, group)
        return 0
    if __load64(c + 8) != 0:
        return 0
    target := __load64(c)
    if group:
        target = 0 - target
    r := __syscall(62, target, sig)
    if r < 0 and r != -3:
        __nat_io_fail("kill()", __nat_errno_text(0 - r))
    return 0

func __nat__native_process__communicate(n: int, a: int, b: int, d: int) -> int:
    __nat_range("communicate", n, 3, 3)
    c := __pr_child("communicate", a)
    hasIn := b != 0
    input := ""
    if hasIn:
        input = __nat_str("communicate", b, "l'entrée")
    end := __nat_deadline(__nat_timeout("communicate", d))
    if hasIn and __load64(c + 24) < 0:
        __nat_io_fail("communicate()", "stdin n'est pas ouvert : impossible d'envoyer l'entrée")
    if __windows():
        return __pw_proc_communicate(c, hasIn, input, end)
    so := __rt_sb_new()
    se := __rt_sb_new()
    __rt_sb_add(so, __as_str(__load64(c + 48)))
    __rt_sb_add(se, __as_str(__load64(c + 72)))
    __store64(c + 48, __str_addr(""))
    __store64(c + 72, __str_addr(""))
    old := __nat_sigpipe(true)
    written := 0
    if __load64(c + 24) >= 0:
        if hasIn and __nat_blen(input) > 0:
            fl := __syscall(72, __load64(c + 24), 3, 0)
            if fl >= 0:
                __syscall(72, __load64(c + 24), 4, fl | 2048)
        else:
            __syscall(3, __load64(c + 24))
            __store64(c + 24, -1)
    timedOut := false
    fds := __alloc_raw(24)
    while __load64(c + 32) >= 0 or __load64(c + 56) >= 0 or __load64(c + 24) >= 0:
        if end >= 0.0 and __nat_clock(1) >= end:
            timedOut = true
            break
        k := 0
        iOut := -1
        iErr := -1
        iIn := -1
        if __load64(c + 32) >= 0:
            iOut = k
            __store32(fds + 8 * k, __load64(c + 32))
            __store16(fds + 8 * k + 4, 1)
            __store16(fds + 8 * k + 6, 0)
            k += 1
        if __load64(c + 56) >= 0:
            iErr = k
            __store32(fds + 8 * k, __load64(c + 56))
            __store16(fds + 8 * k + 4, 1)
            __store16(fds + 8 * k + 6, 0)
            k += 1
        if __load64(c + 24) >= 0:
            iIn = k
            __store32(fds + 8 * k, __load64(c + 24))
            __store16(fds + 8 * k + 4, 4)
            __store16(fds + 8 * k + 6, 0)
            k += 1
        pr := __syscall(7, fds, k, __nat_remaining_ms_up(end))
        if pr == -4:
            continue
        if pr < 0:
            __nat_sigpipe_restore(old)
            __nat_io_fail("communicate()", __nat_errno_text(0 - pr))
        if iOut >= 0 and __load16(fds + 8 * iOut + 6) != 0:
            if not __nat_drain(__load64(c + 32), so):
                __syscall(3, __load64(c + 32))
                __store64(c + 32, -1)
                __store64(c + 40, 1)
        if iErr >= 0 and __load16(fds + 8 * iErr + 6) != 0:
            if not __nat_drain(__load64(c + 56), se):
                __syscall(3, __load64(c + 56))
                __store64(c + 56, -1)
                __store64(c + 64, 1)
        if iIn >= 0 and __load16(fds + 8 * iIn + 6) != 0:
            if (__load16(fds + 8 * iIn + 6) & 4) != 0:
                w := __syscall(1, __load64(c + 24), __nat_bp(input) + written, __nat_blen(input) - written)
                if w > 0:
                    written += w
                    if written >= __nat_blen(input):
                        __syscall(3, __load64(c + 24))
                        __store64(c + 24, -1)
                elif w < 0 and w != -11 and w != -4:
                    __syscall(3, __load64(c + 24))
                    __store64(c + 24, -1)
            else:
                __syscall(3, __load64(c + 24))
                __store64(c + 24, -1)
    __nat_sigpipe_restore(old)
    dd := __dyn_dict_new()
    __nat_dict_put(dd, "stdout", __dyn_str(__rt_sb_str(so)))
    __nat_dict_put(dd, "stderr", __dyn_str(__rt_sb_str(se)))
    __nat_dict_put(dd, "timed_out", __dyn_bool(timedOut))
    return dd

func __nat__native_process__release(n: int, a: int) -> int:
    __nat_range("release", n, 1, 1)
    h := __nat_int("release", a, "le handle")
    t := __pr_table()
    e := __rt_dict_index(t, h, 0)
    if e >= 0:
        c := __load64(__load64(t + 32) + 8 * e)
        if __load64(c + 24) >= 0:
            __syscall(3, __load64(c + 24))
        if __load64(c + 32) >= 0:
            __syscall(3, __load64(c + 32))
        if __load64(c + 56) >= 0:
            __syscall(3, __load64(c + 56))
        if __windows():
            __pw_close(__load64(c + 80))
            __pw_close(__load64(c + 88))
        __rt_dict_remove(t, h, 0)
    return 0

func __nat__native_process__live_count(n: int) -> int:
    __nat_range("live_count", n, 0, 0)
    return __dyn_int(__load64(__pr_table()))

# ---- Valeurs copiables d'un fil à l'autre (thread.Portable de la VM) : sérialisation en octets ----------------
# null 0 | bool 1 b | int 2 i64 | float 3 bits | char 4 cp | byte 5 b | str 6 n octets | list 7 n v... | tuple 8 n v...
# | dict 9 n (k v)...

func __pt_put8(sb: int, v: int):
    i := 0
    while i < 8:
        __rt_sb_byte(sb, (v >> (8 * i)) & 255)
        i += 1

func __pt_write(sb: int, v: int, where: str, depth: int):
    if depth > 512:
        __dyn_err("TypeError", where + " : structure trop profonde (plus de 512 niveaux) ou cyclique")
    k := __dyn_kind(v)
    if k == 0:
        __rt_sb_byte(sb, 0)
        return
    if k == 3 or k == 5: # bool -> 1, byte -> 5
        if k == 3:
            __rt_sb_byte(sb, 1)
        else:
            __rt_sb_byte(sb, 5)
        __rt_sb_byte(sb, __load64(v + 8) & 255)
        return
    if k == 1 or k == 2 or k == 4: # int -> 2, float -> 3, char -> 4
        if k == 4:
            __rt_sb_byte(sb, 4)
        else:
            __rt_sb_byte(sb, k + 1)
        __pt_put8(sb, __load64(v + 8))
        return
    if k == 6:
        s := __dyn_sv(v)
        __rt_sb_byte(sb, 6)
        __pt_put8(sb, __nat_blen(s))
        __rt_sb_add(sb, s)
        return
    if k == 7 or k == 8:
        m := 0
        if k == 7:
            m = __dyn_list_len(v)
        else:
            m = __dyn_tuple_len(v)
        __rt_sb_byte(sb, k)
        __pt_put8(sb, m)
        i := 0
        while i < m:
            it := 0
            if k == 7:
                it = __dyn_list_at(v, i)
            else:
                it = __dyn_tuple_at(v, i)
            __pt_write(sb, it, where + "[" + __int_to_str(i) + "]", depth + 1)
            i += 1
        return
    if k == 9:
        d := __dyn_dv(v)
        __rt_sb_byte(sb, 9)
        __pt_put8(sb, __load64(d))
        used := __load64(d + 8)
        e := 0
        while e < used:
            if __load64(__load64(d + 40) + 8 * e) >= 0:
                key := __load64(__load64(d + 24) + 8 * e)
                __pt_write(sb, key, where + " (clé)", depth + 1)
                __pt_write(sb, __load64(__load64(d + 32) + 8 * e), where + "[" + __dyn_display(key) + "]", depth + 1)
            e += 1
        return
    __dyn_err("TypeError", where + " : une valeur '" + __dyn_type_name(v) +
              "' ne peut pas passer d'un fil à l'autre (seulement null, bool, nombres, char, str, list, tuple, dict)")

func __pt_encode(v: int, where: str) -> str:
    sb := __rt_sb_new()
    __pt_write(sb, v, where, 0)
    return __rt_sb_str(sb)

func __pt_get8(p: int) -> int:
    v := 0
    i := 7
    while i >= 0:
        v = (v << 8) | __load8(p + i)
        i -= 1
    return v

# Lit une valeur en [cur] (adresse courante, avancée) ; renvoie la valeur dynamique.
func __pt_read(cur: int) -> int:
    p := __load64(cur)
    t := __load8(p)
    p += 1
    r := 0
    if t == 1:
        r = __dyn_bool(__load8(p) != 0)
        p += 1
    elif t == 2:
        r = __dyn_int(__pt_get8(p))
        p += 8
    elif t == 3:
        r = __dyn_float_bits(__pt_get8(p))
        p += 8
    elif t == 4:
        r = __dyn_char(__pt_get8(p))
        p += 8
    elif t == 5:
        r = __dyn_byte(__load8(p))
        p += 1
    elif t == 6:
        n := __pt_get8(p)
        r = __dyn_str(__nat_make(p + 8, n))
        p += 8 + n
    elif t == 7 or t == 8:
        n := __pt_get8(p)
        p += 8
        __store64(cur, p)
        if t == 7:
            r = __dyn_list_new(0)
            i := 0
            while i < n:
                __dyn_list_push(r, __pt_read(cur))
                i += 1
        else:
            r = __dyn_tuple_new(n)
            i := 0
            while i < n:
                __dyn_tuple_put(r, i, __pt_read(cur))
                i += 1
        return r
    elif t == 9:
        n := __pt_get8(p)
        p += 8
        __store64(cur, p)
        r = __dyn_dict_new()
        i := 0
        while i < n:
            key := __pt_read(cur)
            val := __pt_read(cur)
            __rt_dict_set(__dyn_dv(r), key, val, 3)
            i += 1
        return r
    __store64(cur, p)
    return r

func __pt_decode_at(addr: int) -> int:
    cur := __alloc_raw(8)
    __store64(cur, addr)
    return __pt_read(cur)

# ---- _native_thread : fils d'exécution = processus (fork) partageant une région de mémoire -------------------------
# Comme dans la VM, un fil ne partage rien avec les autres : ses arguments, ses messages et son résultat sont des
# copies. Région partagée (MAP_SHARED, créée avant le premier fil, héritée par les fils) à l'adresse R :
#   R+0 verrou   R+8 séquence (futex, incrémentée à chaque changement)   R+16 fin du tas   R+24 prochain fil
#   R+32 prochain canal   R+40 fils en cours   R+64.. listes libres par classe de taille
#   R+4096 fils : 16384 entrées de 128 octets   R+4096+2 Mio canaux : 65536 entrées de 64 octets   puis le tas.
# État du processus (état du mode dynamique) : [120] fil courant (0 : programme principal), [128] canal vers moi,
# [136] canal depuis moi, [144] R.

# ---- Windows : fils = processus (la VM elle-même) partageant une section de mémoire ------------------------------
# La région des fils (même disposition que sous Linux) est une section du fichier d'échange (CreateFileMappingW,
# SEC_RESERVE, 4 Gio réservés) projetée à la même adresse dans chaque processus ; ses pages sont engagées à mesure
# que le tas partagé grandit. Un fil est un processus lancé avec la ligne de commande du programme et
# ALEX_FIL=section:adresse:fil dans son environnement : la VM (runtime/vm/vm.al) le reconnaît au démarrage, importe
# le programme (code de haut niveau, comme la VM C++ importe le module de la fonction) puis appelle la fonction.
# Attentes : sondage de la séquence (pas de futex entre processus sous Windows).
# État du mode dynamique : [472] phase d'import d'un fil, [304] poignée de la section, [368] 1 si l'exécutable sait
# lancer des fils (la VM), [296] objet Job des fils (fermé avec le processus : les fils meurent avec lui),
# [488] octets du module de la VM, [496] leur copie dans la région partagée.

func __th_win_region() -> int:
    if __windows():
        ds := __dyn_ds()
        h := __wincall("CreateFileMappingW", -1, __pw_sa(), 67108868, 1, 0, 0)
        if h == 0:
            __dyn_err("IoError", "thread : région partagée indisponible (" + __pw_msg(__pw_last()) + ")")
        base := 0
        k := 0
        while k < 6 and base == 0:
            want := (122 - 16 * k) << 40
            base = __wincall("MapViewOfFileEx", h, 983071, 0, 0, 0, want)
            k += 1
        if base == 0:
            e := __pw_last()
            __pw_close(h)
            __dyn_err("IoError", "thread : région partagée indisponible (" + __pw_msg(e) + ")")
        if __wincall("VirtualAlloc", base, 4096 + 2097152 + 4194304 + 524288, 4096, 4) == 0:
            __dyn_err("IoError", "thread : région partagée indisponible (" + __pw_msg(__pw_last()) + ")")
        __store64(ds + 304, h)
        return base
    return 0

func __th_win_yield():
    if __windows():
        __wincall("SwitchToThread")

# Attente d'un changement de la séquence après `seq` : sondage (bref, puis pauses de 1 ms), au plus ~50 ms par appel.
func __th_win_wait(r: int, seq: int, end: float) -> bool:
    if __windows():
        if end >= 0.0 and __nat_clock(1) >= end:
            return false
        i := 0
        while __load32(r + 8) == seq and i < 2000:
            __wincall("SwitchToThread")
            i += 1
        i = 0
        while __load32(r + 8) == seq and i < 50:
            __wincall("Sleep", 1)
            if end >= 0.0 and __nat_clock(1) >= end:
                return true
            i += 1
        return true
    return false

# Lance le fil `id` (entrée w) : même exécutable, même ligne de commande, ALEX_FIL dans l'environnement.
func __th_win_spawn(r: int, id: int, w: int, f: int, args: str) -> bool:
    if __windows():
        ds := __dyn_ds()
        if __load64(ds + 368) == 0:
            return false
        __th_lock(r)
        __store64(w + 104, __th_blob(r, __as_str(__load64(f + 16))))
        __store64(w + 112, __th_blob(r, args))
        __th_unlock(r)
        exe := __alloc_raw(4104)
        if __rt_w32(__wincall("GetModuleFileNameW", 0, exe, 2048)) == 0:
            return false
        cl := __wincall("GetCommandLineW")
        n := 0
        while __load16(cl + 2 * n) != 0:
            n += 1
        cmd := __alloc_raw(2 * n + 8)
        __copy(cmd, cl, 2 * n)
        __store16(cmd + 2 * n, 0)
        env := __rt_list_new(0)
        base := __nat_env()
        i := 0
        while i < __load64(base):
            e := __as_str(__rt_vec_at(base, i))
            if not (__nat_blen(e) >= 9 and __rt_str_eq(__nat_sub(e, 0, 9), "ALEX_FIL=")):
                __rt_list_push(env, __str_addr(e))
            i += 1
            # module du programme (VM) : copié une fois dans la région, le fil le relit de là
        mb := __load64(ds + 488)
        if __load64(ds + 496) == 0 and mb != 0:
            __th_lock(r)
            __store64(ds + 496, __th_blob(r, __as_str(mb)))
            __th_unlock(r)
        __rt_list_push(env, __str_addr("ALEX_FIL=" + __int_to_str(__load64(ds + 304)) + ":" + __int_to_str(r) + ":" + __int_to_str(id) + ":" + __int_to_str(__load64(ds + 496))))
        si := __alloc_raw(112)
        __zero(si, 112)
        __store32(si, 104)
        flags := 1024 | __pw_si_inherit(si)
        pi := __alloc_raw(32)
        __zero(pi, 32)
        ok := __rt_w32(__wincall("CreateProcessW", exe, cmd, 0, 0, 1, flags, __pw_env_block(env), 0, si, pi))
        __pw_si_close(si)
        if ok == 0:
            return false
        job := __load64(ds + 296)
        if job == 0:
            job = __wincall("CreateJobObjectW", 0, 0)
            if job != 0:
                info := __alloc_raw(152)
                __zero(info, 152)
                __store32(info + 16, 8192) # JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE
                __wincall("SetInformationJobObject", job, 9, info, 144)
                __store64(ds + 296, job)
        if job != 0:
            __wincall("AssignProcessToJobObject", job, __load64(pi))
        __pw_close(__load64(pi + 8))
        __pw_close(__load64(pi))
        __store64(w + 72, __load32(pi + 16))
        return true
    return false

func __th_region() -> int:
    ds := __dyn_ds()
    r := __load64(ds + 144)
    if r != 0:
        return r
    size := 4294967296
    if __windows():
        r = __th_win_region()
    else:
        r = __syscall(9, 0, size, 3, 33 | 16384, -1, 0) # PROT_READ|WRITE, MAP_SHARED|ANONYMOUS|NORESERVE
    if r < 0:
        __dyn_err("IoError", "thread : région partagée indisponible (" + __nat_errno_text(0 - r) + ")")
    __store64(r + 16, 4096 + 2097152 + 4194304 + 524288)
    __store64(r + 56, 1)
    __store64(r + 24, 1)
    __store64(r + 32, 1)
    __store64(r + 48, size)
    __store64(ds + 144, r)
    return r

func __th_lock(r: int):
    spins := 0
    while __cas(r, 0, 1) != 0:
        spins += 1
        if spins > 100:
            if __windows():
                __th_win_yield()
            else:
                __syscall(24)
            spins = 0

func __th_unlock(r: int):
    __xadd(r, -1)

func __th_notify(r: int):
    __xadd(r + 8, 1)
    if __windows():
        return
    __syscall(202, r + 8, 1, 2147483647, 0, 0, 0) # FUTEX_WAKE

func __th_seq(r: int) -> int:
    return __load32(r + 8)

# Attend un changement après `seq` (ou l'échéance) ; faux si l'échéance est passée.
func __th_wait(r: int, seq: int, end: float) -> bool:
    if __windows():
        return __th_win_wait(r, seq, end)
    if end < 0.0:
        __syscall(202, r + 8, 0, seq, 0, 0, 0)
        return true
    left := end - __nat_clock(1)
    if left <= 0.0:
        return false
    ts := __alloc_raw(16)
    __store64(ts, __f2i(left))
    __store64(ts + 8, __f2i((left - __rt_floor(left)) * 1000000000.0))
    __syscall(202, r + 8, 0, seq, ts, 0, 0)
    return true

# Tas partagé : blocs [classe][données] ; classe k = 32 << k octets (en-tête compris). Sous le verrou.
func __th_alloc(r: int, n: int) -> int:
    k := 0
    while (32 << k) < n + 8:
        k += 1
    head := __load64(r + 64 + 8 * k)
    if head != 0:
        __store64(r + 64 + 8 * k, __load64(head + 8))
        __store64(head, k)
        return head + 8
    b := r + __load64(r + 16)
    if __load64(r + 16) + (32 << k) > __load64(r + 48):
        return 0
    __store64(r + 16, __load64(r + 16) + (32 << k))
    if __windows():
        if __wincall("VirtualAlloc", b, 32 << k, 4096, 4) == 0:
            __store64(r + 16, __load64(r + 16) - (32 << k))
            return 0
    __store64(b, k)
    return b + 8

func __th_free(r: int, p: int):
    if p == 0:
        return
    b := p - 8
    k := __load64(b)
    __store64(b + 8, __load64(r + 64 + 8 * k))
    __store64(r + 64 + 8 * k, b)

# Copie d'une chaîne native dans le tas partagé : [longueur][octets] (adresse), sous le verrou.
func __th_blob(r: int, s: str) -> int:
    n := __nat_blen(s)
    p := __th_alloc(r, n + 8)
    if p == 0:
        __th_unlock(r)
        __dyn_err("MemoryError", "thread : mémoire partagée épuisée")
    __store64(p, n)
    __copy(p + 8, __nat_bp(s), n)
    return p

func __th_blob_str(p: int) -> str:
    if p == 0:
        return ""
    return __nat_make(p + 8, __load64(p))

func __th_worker_entry(r: int, id: int) -> int:
    return r + 4096 + 128 * id

func __th_chan_entry(r: int, id: int) -> int:
    return r + 4096 + 2097152 + 64 * id

# Canal [0] utilisé [8] fermé [16] capacité [24] nombre [32] tête [40] queue ; nœud [suivant][message (blob)].
func __th_new_chan(r: int, cap: int) -> int:
    id := __load64(r + 32)
    if id >= 65536:
        __th_unlock(r)
        __dyn_err("IoError", "thread : trop de canaux (65535 au plus)")
    __store64(r + 32, id + 1)
    c := __th_chan_entry(r, id)
    __zero(c, 64)
    __store64(c, 1)
    __store64(c + 16, cap)
    return id

func __th_chan(fn: str, v: int) -> int:
    r := __th_region()
    id := __nat_int(fn, v, "le canal")
    if id <= 0 or id >= __load64(r + 32) or id >= 65536:
        __dyn_err("ArgumentError", "'" + fn + "' : canal inconnu (" + __int_to_str(id) + ")")
    return id

func __th_worker(fn: str, v: int) -> int:
    r := __th_region()
    id := __nat_int(fn, v, "l'identifiant du fil")
    if id <= 0 or id >= __load64(r + 24) or id >= 16384:
        __dyn_err("ArgumentError", "'" + fn + "' : fil inconnu (" + __int_to_str(id) + ")")
    return id

# Envoi (sous le verrou pris ici) : 1 envoyé, 0 délai dépassé, 2 canal fermé.
func __th_send(id: int, msg: str, end: float) -> int:
    r := __th_region()
    c := __th_chan_entry(r, id)
    while true:
        __th_lock(r)
        if __load64(c + 8) != 0:
            __th_unlock(r)
            return 2
        if __load64(c + 16) == 0 or __load64(c + 24) < __load64(c + 16):
            node := __th_alloc(r, 16)
            if node == 0:
                __th_unlock(r)
                __dyn_err("MemoryError", "thread : mémoire partagée épuisée")
            __store64(node, 0)
            __store64(node + 8, __th_blob(r, msg))
            if __load64(c + 40) != 0:
                __store64(__load64(c + 40), node)
            else:
                __store64(c + 32, node)
            __store64(c + 40, node)
            __store64(c + 24, __load64(c + 24) + 1)
            __th_unlock(r)
            __th_notify(r)
            return 1
        seq := __th_seq(r)
        __th_unlock(r)
        if not __th_wait(r, seq, end):
            return 0
    return 0

# Réception : [statut, valeur] (1 reçu, 0 délai dépassé, 2 fermé et vide).
func __th_recv(id: int, end: float) -> int:
    r := __th_region()
    c := __th_chan_entry(r, id)
    out := __dyn_list_new(0)
    while true:
        __th_lock(r)
        node := __load64(c + 32)
        if node != 0:
            __store64(c + 32, __load64(node))
            if __load64(c + 32) == 0:
                __store64(c + 40, 0)
            __store64(c + 24, __load64(c + 24) - 1)
            blob := __load64(node + 8)
            msg := __th_blob_str(blob)
            __th_free(r, blob)
            __th_free(r, node)
            __th_unlock(r)
            __th_notify(r)
            __dyn_list_push(out, __dyn_int(1))
            __dyn_list_push(out, __pt_decode_at(__nat_bp(msg)))
            return out
        if __load64(c + 8) != 0:
            __th_unlock(r)
            __dyn_list_push(out, __dyn_int(2))
            return out
        seq := __th_seq(r)
        __th_unlock(r)
        if not __th_wait(r, seq, end):
            __dyn_list_push(out, __dyn_int(0))
            return out
    return out

func __th_close_chan(id: int):
    r := __th_region()
    __th_lock(r)
    __store64(__th_chan_entry(r, id) + 8, 1)
    __th_unlock(r)
    __th_notify(r)

func __nat__native_thread__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    if __windows():
        return __dyn_bool(__load64(__dyn_ds() + 368) != 0)
    return __dyn_bool(true)

func __nat__native_thread__cpu_count(n: int) -> int:
    __nat_range("cpu_count", n, 0, 0)
    return __nat__native_os__cpu_count(0)

func __nat__native_thread__current_id(n: int) -> int:
    __nat_range("current_id", n, 0, 0)
    return __dyn_int(__load64(__dyn_ds() + 120))

func __nat__native_thread__is_main(n: int) -> int:
    __nat_range("is_main", n, 0, 0)
    return __dyn_bool(__load64(__dyn_ds() + 120) == 0)

func __nat__native_thread__active_count(n: int) -> int:
    __nat_range("active_count", n, 0, 0)
    if __load64(__dyn_ds() + 144) == 0:
        return __dyn_int(0)
    return __dyn_int(__load64(__th_region() + 40))

func __nat__native_thread__channel(n: int, a: int) -> int:
    __nat_range("channel", n, 1, 1)
    cap := __nat_int("channel", a, "la capacité")
    if cap < 0:
        __dyn_err("ArgumentError", "'channel' : capacité >= 0 attendue")
    r := __th_region()
    __th_lock(r)
    id := __th_new_chan(r, cap)
    __th_unlock(r)
    return __dyn_int(id)

func __nat__native_thread__send(n: int, a: int, b: int, c: int) -> int:
    __nat_range("send", n, 3, 3)
    id := __th_chan("send", a)
    msg := __pt_encode(b, "thread : message envoyé")
    end := __nat_deadline(__nat_timeout("send", c))
    return __dyn_int(__th_send(id, msg, end))

func __nat__native_thread__recv(n: int, a: int, b: int) -> int:
    __nat_range("recv", n, 2, 2)
    id := __th_chan("recv", a)
    end := __nat_deadline(__nat_timeout("recv", b))
    return __th_recv(id, end)

func __nat__native_thread__close(n: int, a: int) -> int:
    __nat_range("close", n, 1, 1)
    __th_close_chan(__th_chan("close", a))
    return 0

func __nat__native_thread__size(n: int, a: int) -> int:
    __nat_range("size", n, 1, 1)
    id := __th_chan("size", a)
    r := __th_region()
    __th_lock(r)
    k := __load64(__th_chan_entry(r, id) + 24)
    __th_unlock(r)
    return __dyn_int(k)

func __nat__native_thread__closed(n: int, a: int) -> int:
    __nat_range("closed", n, 1, 1)
    id := __th_chan("closed", a)
    r := __th_region()
    __th_lock(r)
    k := __load64(__th_chan_entry(r, id) + 8)
    __th_unlock(r)
    return __dyn_bool(k != 0)

# Fil : [0] utilisé [8] fini [16] réussi [24] résultat [32] type d'erreur [40] message [48] trace [56] canal vers
# [64] canal depuis [72] pid [80] attendu [88] nom [96] canal des tâches (service) + 2^32 x (fil lanceur + 1).

func __nat__native_thread__name(n: int, a: int) -> int:
    __nat_range("name", n, 1, 1)
    id := __th_worker("name", a)
    r := __th_region()
    return __dyn_str(__th_blob_str(__load64(__th_worker_entry(r, id) + 88)))

func __nat__native_thread__is_alive(n: int, a: int) -> int:
    __nat_range("is_alive", n, 1, 1)
    id := __th_worker("is_alive", a)
    r := __th_region()
    __th_lock(r)
    done := __load64(__th_worker_entry(r, id) + 8)
    __th_unlock(r)
    return __dyn_bool(done == 0)

func __nat__native_thread__mailbox(n: int, a: int) -> int:
    __nat_range("mailbox", n, 1, 1)
    id := __nat_int("mailbox", a, "l'identifiant du fil")
    l := __dyn_list_new(0)
    ds := __dyn_ds()
    if id == 0:
        if __load64(ds + 120) == 0:
            __dyn_err("ArgumentError", "thread : le programme principal n'a pas de boîte aux lettres de fil")
        __dyn_list_push(l, __dyn_int(__load64(ds + 128)))
        __dyn_list_push(l, __dyn_int(__load64(ds + 136)))
        return l
    w := __th_worker_entry(__th_region(), __th_worker("mailbox", a))
    __dyn_list_push(l, __dyn_int(__load64(w + 56)))
    __dyn_list_push(l, __dyn_int(__load64(w + 64)))
    return l

func __th_reap(w: int):
    if __windows():
        return
    pid := __load64(w + 72)
    if pid > 0:
        __nat_waitpid(pid, 1)

func __nat__native_thread__join(n: int, a: int, b: int) -> int:
    __nat_range("join", n, 2, 2)
    id := __th_worker("join", a)
    if id == __load64(__dyn_ds() + 120):
        __dyn_err("ArgumentError", "'join' : un fil ne peut pas s'attendre lui-même")
    end := __nat_deadline(__nat_timeout("join", b))
    r := __th_region()
    w := __th_worker_entry(r, id)
    while true:
        __th_lock(r)
        if __load64(w + 8) != 0:
            __store64(w + 80, 1)
            l := __dyn_list_new(0)
            if __load64(w + 16) != 0:
                __dyn_list_push(l, __dyn_bool(true))
                res := __th_blob_str(__load64(w + 24))
                __th_unlock(r)
                __dyn_list_push(l, __pt_decode_at(__nat_bp(res)))
            else:
                __dyn_list_push(l, __dyn_bool(false))
                __dyn_list_push(l, __dyn_str(__th_blob_str(__load64(w + 32))))
                __dyn_list_push(l, __dyn_str(__th_blob_str(__load64(w + 40))))
                __dyn_list_push(l, __dyn_str(__th_blob_str(__load64(w + 48))))
                __th_unlock(r)
            __th_reap(w)
            return l
        seq := __th_seq(r)
        __th_unlock(r)
        if not __th_wait(r, seq, end):
            return 0
    return 0

func __nat__native_thread__worker_args(n: int) -> int:
    __nat_range("worker_args", n, 0, 0)
    return __dyn_list_new(0)

func __nat__native_thread__worker_return(n: int, a: int) -> int:
    __nat_range("worker_return", n, 1, 1)
    __pt_encode(a, "thread : valeur rendue par le fil")
    return 0

# Fonction de premier niveau d'un module (pas une fermeture, une méthode ni une lambda).
func __th_check_fn(who: str, f: int):
    if not __dyn_is(f, 10):
        __dyn_err("TypeError", "'" + who + "' : la fonction doit être une fonction de premier niveau (obtenu '" +
                  __dyn_type_name(f) + "')")
    raw := __as_str(__load64(f + 16))
    if __load64(f + 40) != 0 or __load64(f + 48) != 0:
        __dyn_err("ArgumentError", who + " : la fonction doit être de premier niveau dans un module (ni fermeture, ni méthode, ni lambda) : '" + __dyn_fn_display(raw) + "'")
    name := raw
    q := __nat_blen(name) - 2
    while q >= 0:
        if __load8(__nat_bp(name) + q) == 58 and __load8(__nat_bp(name) + q + 1) == 58:
            name = __nat_sub(name, q + 2, __nat_blen(name) - q - 2)
            break
        q -= 1
    i := 0
    while i < __nat_blen(name):
        c := __load8(__nat_bp(name) + i)
        ok := (c >= 48 and c <= 57) or (c >= 65 and c <= 90) or (c >= 97 and c <= 122) or c == 95
        if not ok:
            __dyn_err("ArgumentError", who + " : la fonction doit être de premier niveau dans un module (ni fermeture, ni méthode, ni lambda) : '" + name + "'")
        i += 1

# Échec de la fonction d'un fil : [type, message, trace] de l'exception native e.
func __th_failure(w: int, r: int, e: int):
    t := __as_str(__load64(e))
    m := __as_str(__load64(e + 8))
    tr := __dyn_exc_trace(e)
    sb := __rt_sb_new()
    i := 0
    while i < __dyn_list_len(tr):
        __rt_sb_add(sb, "  ")
        __rt_sb_add(sb, __dyn_sv(__dyn_list_at(tr, i)))
        __rt_sb_add(sb, "\n")
        i += 1
    __th_lock(r)
    __store64(w + 32, __th_blob(r, t))
    __store64(w + 40, __th_blob(r, m))
    __store64(w + 48, __th_blob(r, __rt_sb_str(sb)))
    __th_unlock(r)

# Corps du fil (processus fils) : appelle la fonction, range le résultat, ferme le canal sortant, se termine.
func __th_child(id: int, w: int, f: int, args: str, jobs: int, results: int):
    r := __th_region()
    ds := __dyn_ds()
    __store64(ds + 120, id)
    __store64(ds + 128, __load64(w + 56))
    __store64(ds + 136, __load64(w + 64))
    __store64(ds + 104, 0) # processus fils (module process) et sockets : propres au fil
    __store64(ds + 152, 0)
    __store64(ds + 248, 0) # gestionnaires de signaux : programme principal seulement
    __store64(ds + 200, 0)
    ok := false
    try:
        if jobs != 0:
            __th_service(f, jobs, results)
            ok = true
            __th_lock(r)
            __store64(w + 24, __th_blob(r, __pt_encode(0, "thread : valeur rendue par le fil")))
            __th_unlock(r)
        else:
            al := __pt_decode_at(__nat_bp(args))
            v := __dyn_call_spread(f, al)
            enc := __pt_encode(v, "thread : valeur rendue par le fil")
            __th_lock(r)
            __store64(w + 24, __th_blob(r, enc))
            __th_unlock(r)
            ok = true
    catch e:
        __th_failure(w, r, __addr(e))
    __th_finish(w, r, ok)

# Fin d'un fil : sorties, tâches async, fils lancés, état (réussi ou non), canal sortant fermé ; termine le processus.
func __th_finish(w: int, r: int, ok: bool):
    __flush()
    __rt_async_end()
    __th_join_all()
    __th_lock(r)
    if ok:
        __store64(w + 16, 1)
    __store64(w + 8, 1)
    __store64(r + 40, __load64(r + 40) - 1)
    c := __th_chan_entry(r, __load64(w + 64))
    __store64(c + 8, 1)
    __th_unlock(r)
    __th_notify(r)
    __fd_restore_all()
    __flush()
    if __windows():
        __exit(0)
    __syscall(231, 0)

# Fil de réserve (ThreadPool) : tâches [numéro, [arguments]] -> résultats [numéro, true, v] | [numéro, false, type,
# message, trace], jusqu'à la fermeture du canal des tâches.
func __th_service(f: int, jobs: int, results: int):
    while true:
        rv := __th_recv(jobs, -1.0)
        if __dyn_iv(__dyn_list_at(rv, 0)) != 1:
            return
        job := __dyn_list_at(rv, 1)
        num := __dyn_list_at(job, 0)
        al := __dyn_list_at(job, 1)
        reply := __dyn_list_new(0)
        __dyn_list_push(reply, num)
        try:
            v := __dyn_call_spread(f, al)
            __dyn_list_push(reply, __dyn_bool(true))
            __dyn_list_push(reply, v)
        catch e:
            ex := __addr(e)
            reply = __dyn_list_new(0)
            __dyn_list_push(reply, num)
            __dyn_list_push(reply, __dyn_bool(false))
            __dyn_list_push(reply, __dyn_str(__as_str(__load64(ex))))
            __dyn_list_push(reply, __dyn_str(__as_str(__load64(ex + 8))))
            __dyn_list_push(reply, __dyn_exc_trace(ex))
        __th_send(results, __pt_encode(reply, "thread : message envoyé"), -1.0)

func __th_spawn(who: str, f: int, argsV: int, nameV: int, jobs: int, results: int) -> int:
    __th_check_fn(who, f)
    if __load64(__dyn_ds() + 120) != 0 and __load64(__dyn_ds() + 472) != 0:
        return __dyn_int(-1) # code de haut niveau d'un module importé dans un fil (Windows : import du programme)
    args := ""
    if jobs == 0:
        if not __dyn_is(argsV, 7) and not __dyn_is(argsV, 8):
            __dyn_err("TypeError", "'" + who + "' : les arguments doivent être une list (obtenu '" + __dyn_type_name(argsV) + "')")
        al := __dyn_list_new(0)
        m := 0
        if __dyn_is(argsV, 7):
            m = __dyn_list_len(argsV)
        else:
            m = __dyn_tuple_len(argsV)
        i := 0
        while i < m:
            it := 0
            if __dyn_is(argsV, 7):
                it = __dyn_list_at(argsV, i)
            else:
                it = __dyn_tuple_at(argsV, i)
            __pt_encode(it, who + " : argument " + __int_to_str(i))
            __dyn_list_push(al, it)
            i += 1
        args = __pt_encode(al, who)
    r := __th_region()
    __th_lock(r)
    if __load64(r + 40) >= 256:
        __th_unlock(r)
        return __dyn_int(-2)
    id := __load64(r + 24)
    if id >= 16384:
        __th_unlock(r)
        __dyn_err("IoError", who + " : trop de fils (16383 au plus)")
    __store64(r + 24, id + 1)
    w := __th_worker_entry(r, id)
    __zero(w, 128)
    __store64(w, 1)
    __store64(w + 56, __th_new_chan(r, 0))
    __store64(w + 64, __th_new_chan(r, 0))
    if jobs != 0:
        # le fil qui lance ce fil de réserve est noté avec le canal : seul lui fermera ce canal en finissant
        __store64(w + 96, jobs + 4294967296 * (__load64(__dyn_ds() + 120) + 1))
    __store64(r + 40, __load64(r + 40) + 1)
    __th_unlock(r)
    name := "fil-" + __int_to_str(id)
    if nameV != 0:
        name = __nat_cstr(who, nameV, "le nom")
    __th_lock(r)
    __store64(w + 88, __th_blob(r, name))
    __store64(w + 120, results)
    __th_unlock(r)
    __flush()
    if __windows():
        if not __th_win_spawn(r, id, w, f, args):
            __th_lock(r)
            __store64(r + 40, __load64(r + 40) - 1)
            __store64(w + 8, 1)
            __th_unlock(r)
            __dyn_err("IoError", "thread.spawn : impossible de créer le fil système")
        return __dyn_int(id)
    pid := __syscall(57)
    if pid < 0:
        __th_lock(r)
        __store64(r + 40, __load64(r + 40) - 1)
        __store64(w + 8, 1)
        __th_unlock(r)
        __dyn_err("IoError", "thread.spawn : impossible de créer le fil système")
    if pid == 0:
        __syscall(157, 1, 9, 0, 0, 0) # PR_SET_PDEATHSIG : le fil disparaît avec le processus qui l'a lancé
        __th_child(id, w, f, args, jobs, results)
    __store64(w + 72, pid)
    return __dyn_int(id)

func __nat__native_thread__spawn(n: int, a: int, b: int, c: int) -> int:
    __nat_range("spawn", n, 3, 3)
    return __th_spawn("thread.spawn", a, b, c, 0, 0)

func __nat__native_thread__spawn_service(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("spawn_service", n, 4, 4)
    jobs := __nat_int("spawn_service", b, "le canal des tâches")
    results := __nat_int("spawn_service", c, "le canal des résultats")
    __th_chan("spawn_service", b)
    __th_chan("spawn_service", c)
    return __th_spawn("thread.ThreadPool", a, 0, d, jobs, results)

# Fin du programme (ou d'un fil) : ferme les canaux des fils de réserve, attend tous les fils lancés, signale ceux qui
# ont échoué sans être attendus.
func __th_join_all():
    ds := __dyn_ds()
    r := __load64(ds + 144)
    if r == 0:
        return
    me := __load64(ds + 120)
    __th_lock(r)
    top := __load64(r + 24)
    i := 1
    while i < top:
        w := __th_worker_entry(r, i)
        # seulement les réserves lancées par CE fil (ou programme) : un fil qui finit ne doit pas arrêter les
        # réserves de son parent (la zone des canaux est partagée par tous les processus)
        sv := __load64(w + 96)
        if sv != 0 and __load64(w + 72) != 0 and sv // 4294967296 - 1 == me:
            __store64(__th_chan_entry(r, sv % 4294967296) + 8, 1)
        i += 1
    __th_unlock(r)
    __th_notify(r)
    # attend les fils que ce processus a lancés
    while true:
        __th_lock(r)
        pending := false
        i = 1
        while i < top:
            w := __th_worker_entry(r, i)
            if __load64(w + 72) != 0 and __load64(w + 8) == 0:
                pending = true
            i += 1
        seq := __th_seq(r)
        __th_unlock(r)
        if not pending or me != 0:
            break
        __th_wait(r, seq, __nat_clock(1) + 0.5)
    if me != 0:
        return
    __flush()
    i = 1
    while i < top:
        w := __th_worker_entry(r, i)
        if __load64(w + 8) != 0 and __load64(w + 80) == 0 and __load64(w + 16) == 0:
            __write_err("thread : le fil " + __int_to_str(i) + " (" + __th_blob_str(__load64(w + 88)) + ") a échoué sans être attendu : " +
                        __th_blob_str(__load64(w + 32)) + ": " + __th_blob_str(__load64(w + 40)) + "\n")
        i += 1

# ---- _native_net : sockets (TCP, UDP, local), adresses, DNS ---------------------------------------------------------
# Socket : [0] descripteur [8] famille (4, 6, 1) [16] UDP. Table : état du mode dynamique [152] (handle -> socket),
# [160] prochain handle.

func __ns_table() -> int:
    ds := __dyn_ds()
    t := __load64(ds + 152)
    if t == 0:
        t = __rt_dict_new(8)
        __store64(ds + 152, t)
        __store64(ds + 160, 1)
    return t

func __ns_sock(fn: str, v: int) -> int:
    h := __nat_int(fn, v, "le handle")
    t := __ns_table()
    e := __rt_dict_index(t, h, 0)
    if e < 0:
        __dyn_err("ArgumentError", "'" + fn + "' : handle de socket invalide ou déjà fermé (" + __int_to_str(h) + ")")
    return __load64(__load64(t + 32) + 8 * e)

func __ns_adopt(fd: int, family: int, udp: bool) -> int:
    s := __alloc(24)
    __store64(s, fd)
    __store64(s + 8, family)
    if udp:
        __store64(s + 16, 1)
    t := __ns_table()
    h := __load64(__dyn_ds() + 160)
    __store64(__dyn_ds() + 160, h + 1)
    __rt_dict_set(t, h, s, 0)
    return h

func __ns_nonblock(fd: int):
    fl := __syscall(72, fd, 3, 0)
    if fl >= 0:
        __syscall(72, fd, 4, fl | 2048)

func __ns_family(fn: str, v: int) -> int:
    f := __nat_int(fn, v, "la famille")
    if f != 4 and f != 6 and f != 1:
        __dyn_err("ArgumentError", "'" + fn + "' : famille 4, 6 ou 1 (Unix) attendue")
    return f

func __ns_udp(fn: str, v: int) -> bool:
    k := __nat_cstr(fn, v, "le type")
    if __rt_str_eq(k, "tcp"):
        return false
    if __rt_str_eq(k, "udp"):
        return true
    __dyn_err("ArgumentError", "'" + fn + "' : type \"tcp\" ou \"udp\" attendu (obtenu \"" + k + "\")")
    return false

func __ns_port(fn: str, v: int) -> int:
    p := __nat_int(fn, v, "le port")
    if p < 0 or p > 65535:
        __dyn_err("ArgumentError", "'" + fn + "' : port hors de 0..65535")
    return p

# Échéance d'une opération réseau : -1.0 sans limite ; zéro : opération qui ne bloque pas (EAGAIN à l'échéance).
func __ns_expired(t: float) -> int:
    if t >= 0.0 and t <= 0.0:
        return -11
    return -110

func __ns_wait_fd(fd: int, events: int, end: float) -> bool:
    while true:
        r := __fd_poll1(fd, events, __nat_remaining_ms(end))
        if r > 0:
            return true
        if r == 0:
            return false
        if r != -4:
            return true
    return true

# ---- adresses : inet_pton / inet_ntop ----

# IPv4 « a.b.c.d » -> 4 octets en [out] ; faux si invalide (comme inet_pton : pas de zéro initial).
func __ns_pton4(s: str, out: int) -> bool:
    p := __nat_bp(s)
    m := __nat_blen(s)
    parts := 0
    val := 0
    digits := 0
    i := 0
    while i <= m:
        c := 46
        if i < m:
            c = __load8(p + i)
        if c == 46:
            if digits == 0 or parts >= 4:
                return false
            __store8(out + parts, val)
            parts += 1
            val = 0
            digits = 0
        elif c >= 48 and c <= 57:
            if digits > 0 and val == 0:
                return false
            val = val * 10 + c - 48
            digits += 1
            if val > 255:
                return false
        else:
            return false
        i += 1
    return parts == 4

func __ns_hexval(c: int) -> int:
    if c >= 48 and c <= 57:
        return c - 48
    if c >= 97 and c <= 102:
        return c - 87
    if c >= 65 and c <= 70:
        return c - 55
    return -1

# IPv6 -> 16 octets en [out] ; faux si invalide.
func __ns_pton6(s: str, out: int) -> bool:
    p := __nat_bp(s)
    m := __nat_blen(s)
    words := __alloc_raw(32)
    __zero(words, 32)
    n := 0
    gap := -1
    i := 0
    if m >= 2 and __load8(p) == 58:
        if __load8(p + 1) != 58:
            return false
        gap = 0
        i = 2
        if m == 2:
            __zero(out, 16)
            return true
    while i < m:
        # groupe hexadécimal, ou IPv4 final
        j := i
        while j < m and __load8(p + j) != 58:
            j += 1
        grp := __nat_sub(s, i, j - i)
        if __dyn_find_bytes(grp, ".", 0) >= 0:
            if j != m or n > 6:
                return false
            v4 := __alloc_raw(8)
            if not __ns_pton4(grp, v4):
                return false
            __store16(words + 2 * n, (__load8(v4) << 8) | __load8(v4 + 1))
            __store16(words + 2 * n + 2, (__load8(v4 + 2) << 8) | __load8(v4 + 3))
            n += 2
            i = m
            break
        k := j - i
        if k < 1 or k > 4 or n >= 8:
            return false
        v := 0
        q := i
        while q < j:
            h := __ns_hexval(__load8(p + q))
            if h < 0:
                return false
            v = (v << 4) | h
            q += 1
        __store16(words + 2 * n, v)
        n += 1
        if j == m:
            i = m
            break
        # « : » ou « :: »
        if j + 1 < m and __load8(p + j + 1) == 58:
            if gap >= 0:
                return false
            gap = n
            i = j + 2
            if i == m:
                break
        else:
            i = j + 1
            if i == m:
                return false
    if gap >= 0:
        if n > 7:
            return false
        shift := 8 - n
        k := n - 1
        while k >= gap:
            __store16(words + 2 * (k + shift), __load16(words + 2 * k))
            k -= 1
        k = gap
        while k < gap + shift:
            __store16(words + 2 * k, 0)
            k += 1
    elif n != 8:
        return false
    k := 0
    while k < 8:
        w := __load16(words + 2 * k)
        __store8(out + 2 * k, (w >> 8) & 255)
        __store8(out + 2 * k + 1, w & 255)
        k += 1
    return true

func __ns_ntop4(a: int) -> str:
    return __int_to_str(__load8(a)) + "." + __int_to_str(__load8(a + 1)) + "." + __int_to_str(__load8(a + 2)) + "." + __int_to_str(__load8(a + 3))

func __ns_hex16(v: int) -> str:
    sb := __rt_sb_new()
    started := false
    sh := 12
    while sh >= 0:
        d := (v >> sh) & 15
        if d != 0 or started or sh == 0:
            __rt_sb_byte(sb, __nat_hex(d))
            started = true
        sh -= 4
    return __rt_sb_str(sb)

# inet_ntop(AF_INET6) de la glibc (plus longue suite de zéros remplacée par « :: », fin IPv4 si adresse mappée).
func __ns_ntop6(a: int) -> str:
    w := __alloc_raw(64)
    k := 0
    while k < 8:
        __store64(w + 8 * k, (__load8(a + 2 * k) << 8) | __load8(a + 2 * k + 1))
        k += 1
    best := -1
    bestLen := 0
    cur := -1
    curLen := 0
    k = 0
    while k < 8:
        if __load64(w + 8 * k) == 0:
            if cur < 0:
                cur = k
                curLen = 1
            else:
                curLen += 1
        else:
            if cur >= 0 and (best < 0 or curLen > bestLen):
                best = cur
                bestLen = curLen
            cur = -1
        k += 1
    if cur >= 0 and (best < 0 or curLen > bestLen):
        best = cur
        bestLen = curLen
    if best >= 0 and bestLen < 2:
        best = -1
    sb := __rt_sb_new()
    k = 0
    while k < 8:
        if best >= 0 and k >= best and k < best + bestLen:
            if k == best:
                __rt_sb_byte(sb, 58)
            k += 1
            continue
        if k != 0:
            __rt_sb_byte(sb, 58)
        if k == 6 and best == 0 and (bestLen == 6 or (bestLen == 7 and __load64(w + 56) != 1) or (bestLen == 5 and __load64(w + 40) == 65535)):
            __rt_sb_add(sb, __ns_ntop4(a + 12))
            k = 8
            break
        __rt_sb_add(sb, __ns_hex16(__load64(w + 8 * k)))
        k += 1
    if best >= 0 and best + bestLen == 8:
        __rt_sb_byte(sb, 58)
    return __rt_sb_str(sb)

# sockaddr (tampon de 128 octets) de la famille du socket ; renvoie sa longueur.
func __ns_sockaddr(fn: str, family: int, addr: str, port: int, ss: int) -> int:
    __zero(ss, 128)
    if family == 1:
        m := __nat_blen(addr)
        if m == 0 or m >= 108 or __dyn_find_bytes(addr, "\x00", 0) >= 0:
            __dyn_err("ArgumentError", "'" + fn + "' : chemin de socket local vide ou trop long (107 octets au plus)")
        __store16(ss, 1)
        __copy(ss + 2, __nat_bp(addr), m)
        if __load8(ss + 2) == 64:
            __store8(ss + 2, 0)
            return 2 + m
        return 2 + m + 1
    if family == 4:
        __store16(ss, 2)
        __store8(ss + 2, (port >> 8) & 255)
        __store8(ss + 3, port & 255)
        if __nat_blen(addr) > 0 and not __ns_pton4(addr, ss + 4):
            __dyn_err("ArgumentError", "'" + fn + "' : adresse IPv4 invalide '" + addr + "'")
        return 16
    __store16(ss, 10)
    __store8(ss + 2, (port >> 8) & 255)
    __store8(ss + 3, port & 255)
    if __nat_blen(addr) > 0 and not __ns_pton6(addr, ss + 8):
        __dyn_err("ArgumentError", "'" + fn + "' : adresse IPv6 invalide '" + addr + "'")
    return 28

# sockaddr -> [adresse (chaîne native), port, famille] (liste native).
func __ns_from_sockaddr(ss: int) -> int:
    out := __rt_list_new(0)
    fam := __load16(ss)
    if fam == 1:
        path := __nat_from_c(ss + 2)
        if __nat_blen(path) == 0 and __load8(ss + 3) != 0:
            path = "@" + __nat_from_c(ss + 3)
        __rt_list_push(out, __str_addr(path))
        __rt_list_push(out, 0)
        __rt_list_push(out, 1)
        return out
    port := (__load8(ss + 2) << 8) | __load8(ss + 3)
    if fam == 2:
        __rt_list_push(out, __str_addr(__ns_ntop4(ss + 4)))
        __rt_list_push(out, port)
        __rt_list_push(out, 4)
        return out
    __rt_list_push(out, __str_addr(__ns_ntop6(ss + 8)))
    __rt_list_push(out, port)
    __rt_list_push(out, 6)
    return out

func __ns_pair(ap: int) -> int:
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_str(__as_str(__rt_vec_at(ap, 0))))
    __dyn_list_push(l, __dyn_int(__rt_vec_at(ap, 1)))
    return l

func __nat__native_net__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    return __dyn_bool(true)

func __nat__native_net__socket(n: int, a: int, b: int) -> int:
    __nat_range("socket", n, 2, 2)
    f := __ns_family("socket", a)
    udp := __ns_udp("socket", b)
    af := 1
    if f == 4:
        af = 2
    elif f == 6:
        af = 10
    ty := 1
    if udp:
        ty = 2
    fd := __syscall(41, af, ty | 524288, 0)
    if fd < 0:
        return __dyn_int(fd)
    __ns_nonblock(fd)
    return __dyn_int(__ns_adopt(fd, f, udp))

func __nat__native_net__socketpair(n: int, a: int) -> int:
    __nat_range("socketpair", n, 1, 1)
    udp := __ns_udp("socketpair", a)
    ty := 1
    if udp:
        ty = 2
    fds := __alloc_raw(8)
    r := __syscall(53, 1, ty | 524288, 0, fds)
    if r != 0:
        return __dyn_int(r)
    a0 := __load32(fds)
    a1 := __load32(fds + 4)
    __ns_nonblock(a0)
    __ns_nonblock(a1)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__ns_adopt(a0, 1, udp)))
    __dyn_list_push(l, __dyn_int(__ns_adopt(a1, 1, udp)))
    return l

func __nat__native_net__connect(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("connect", n, 4, 4)
    s := __ns_sock("connect", a)
    addr := __nat_cstr("connect", b, "l'adresse")
    port := __ns_port("connect", c)
    end := __nat_deadline(__nat_timeout("connect", d))
    ss := __alloc_raw(128)
    len := __ns_sockaddr("connect", __load64(s + 8), addr, port, ss)
    r := __syscall(42, __load64(s), ss, len)
    if r == 0:
        return __dyn_int(0)
    if r != -115 and r != -4:
        return __dyn_int(r)
    if not __ns_wait_fd(__load64(s), 4, end):
        return __dyn_int(-110)
    err := __alloc_raw(8)
    __store64(err, 0)
    el := __alloc_raw(8)
    __store64(el, 4)
    g := __syscall(55, __load64(s), 1, 4, err, el) # SOL_SOCKET, SO_ERROR
    if g != 0:
        return __dyn_int(g)
    return __dyn_int(0 - __load32(err))

func __nat__native_net__bind(n: int, a: int, b: int, c: int) -> int:
    __nat_range("bind", n, 3, 3)
    s := __ns_sock("bind", a)
    addr := __nat_cstr("bind", b, "l'adresse")
    port := __ns_port("bind", c)
    ss := __alloc_raw(128)
    len := __ns_sockaddr("bind", __load64(s + 8), addr, port, ss)
    r := __syscall(49, __load64(s), ss, len)
    if r != 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_net__listen(n: int, a: int, b: int) -> int:
    __nat_range("listen", n, 2, 2)
    s := __ns_sock("listen", a)
    backlog := __nat_int("listen", b, "la file d'attente")
    if backlog < 1:
        __dyn_err("ArgumentError", "'listen' : file d'attente >= 1 attendue")
    if backlog > 4096:
        backlog = 4096
    r := __syscall(50, __load64(s), backlog)
    if r != 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_net__accept(n: int, a: int, b: int) -> int:
    __nat_range("accept", n, 2, 2)
    s := __ns_sock("accept", a)
    t := __nat_timeout("accept", b)
    end := __nat_deadline(t)
    ss := __alloc_raw(128)
    ln := __alloc_raw(8)
    while true:
        __zero(ss, 128)
        __store64(ln, 128)
        fd := __syscall(288, __load64(s), ss, ln, 2048 | 524288)
        if fd >= 0:
            ap := __ns_from_sockaddr(ss)
            l := __dyn_list_new(0)
            __dyn_list_push(l, __dyn_int(__ns_adopt(fd, __rt_vec_at(ap, 2), false)))
            __dyn_list_push(l, __dyn_str(__as_str(__rt_vec_at(ap, 0))))
            __dyn_list_push(l, __dyn_int(__rt_vec_at(ap, 1)))
            return l
        if fd == -4 or fd == -103:
            continue
        if fd != -11:
            return __dyn_int(fd)
        if not __ns_wait_fd(__load64(s), 1, end):
            return __dyn_int(__ns_expired(t))
    return 0

func __nat__native_net__send(n: int, a: int, b: int, c: int) -> int:
    __nat_range("send", n, 3, 3)
    s := __ns_sock("send", a)
    data := __nat_str("send", b, "les données")
    t := __nat_timeout("send", c)
    end := __nat_deadline(t)
    done := 0
    m := __nat_blen(data)
    while done < m:
        k := __syscall(44, __load64(s), __nat_bp(data) + done, m - done, 16384, 0, 0) # MSG_NOSIGNAL
        if k > 0:
            done += k
            continue
        if k == -4:
            continue
        if k < 0 and k != -11:
            return __dyn_int(k)
        if not __ns_wait_fd(__load64(s), 4, end):
            if done > 0:
                return __dyn_int(done)
            return __dyn_int(__ns_expired(t))
    return __dyn_int(done)

func __nat__native_net__recv(n: int, a: int, b: int, c: int) -> int:
    __nat_range("recv", n, 3, 3)
    s := __ns_sock("recv", a)
    mx := __nat_int("recv", b, "la taille")
    if mx < 1 or mx > 67108864:
        __dyn_err("ArgumentError", "'recv' : taille hors de 1..64 Mio")
    t := __nat_timeout("recv", c)
    end := __nat_deadline(t)
    buf := __alloc_raw(mx)
    while true:
        k := __syscall(45, __load64(s), buf, mx, 0, 0, 0)
        if k >= 0:
            return __dyn_str(__nat_make(buf, k))
        if k == -4:
            continue
        if k != -11:
            return __dyn_int(k)
        if not __ns_wait_fd(__load64(s), 1, end):
            return __dyn_int(__ns_expired(t))
    return 0

func __nat__native_net__sendto(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("sendto", n, 4, 4)
    s := __ns_sock("sendto", a)
    data := __nat_str("sendto", b, "les données")
    addr := __nat_cstr("sendto", c, "l'adresse")
    port := __ns_port("sendto", d)
    ss := __alloc_raw(128)
    len := __ns_sockaddr("sendto", __load64(s + 8), addr, port, ss)
    end := __nat_deadline(5.0)
    while true:
        k := __syscall(44, __load64(s), __nat_bp(data), __nat_blen(data), 16384, ss, len)
        if k >= 0:
            return __dyn_int(k)
        if k == -4:
            continue
        if k != -11:
            return __dyn_int(k)
        if not __ns_wait_fd(__load64(s), 4, end):
            return __dyn_int(-110)
    return 0

func __nat__native_net__recvfrom(n: int, a: int, b: int, c: int) -> int:
    __nat_range("recvfrom", n, 3, 3)
    s := __ns_sock("recvfrom", a)
    mx := __nat_int("recvfrom", b, "la taille")
    if mx < 1 or mx > 65536:
        __dyn_err("ArgumentError", "'recvfrom' : taille hors de 1..65536")
    t := __nat_timeout("recvfrom", c)
    end := __nat_deadline(t)
    buf := __alloc_raw(mx)
    ss := __alloc_raw(128)
    ln := __alloc_raw(8)
    while true:
        __zero(ss, 128)
        __store64(ln, 128)
        k := __syscall(45, __load64(s), buf, mx, 0, ss, ln)
        if k >= 0:
            ap := __ns_from_sockaddr(ss)
            l := __dyn_list_new(0)
            __dyn_list_push(l, __dyn_str(__nat_make(buf, k)))
            __dyn_list_push(l, __dyn_str(__as_str(__rt_vec_at(ap, 0))))
            __dyn_list_push(l, __dyn_int(__rt_vec_at(ap, 1)))
            return l
        if k == -4:
            continue
        if k != -11:
            return __dyn_int(k)
        if not __ns_wait_fd(__load64(s), 1, end):
            return __dyn_int(__ns_expired(t))
    return 0

func __ns_address(fn: str, n: int, a: int, nr: int) -> int:
    __nat_range(fn, n, 1, 1)
    s := __ns_sock(fn, a)
    ss := __alloc_raw(128)
    __zero(ss, 128)
    ln := __alloc_raw(8)
    __store64(ln, 128)
    r := __syscall(nr, __load64(s), ss, ln)
    if r != 0:
        return __dyn_int(r)
    return __ns_pair(__ns_from_sockaddr(ss))

func __nat__native_net__local_address(n: int, a: int) -> int:
    return __ns_address("local_address", n, a, 51)

func __nat__native_net__peer_address(n: int, a: int) -> int:
    return __ns_address("peer_address", n, a, 52)

func __ns_setopt(fd: int, level: int, opt: int, val: int, size: int) -> int:
    b := __alloc_raw(8)
    __store64(b, val)
    r := __syscall(54, fd, level, opt, b, size)
    if r != 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_net__set_option(n: int, a: int, b: int, c: int) -> int:
    __nat_range("set_option", n, 3, 3)
    s := __ns_sock("set_option", a)
    name := __nat_cstr("set_option", b, "l'option")
    fd := __load64(s)
    level := 1
    opt := 0
    boolean := true
    if __rt_str_eq(name, "reuse_address"):
        opt = 2
    elif __rt_str_eq(name, "broadcast"):
        opt = 6
    elif __rt_str_eq(name, "keep_alive"):
        opt = 9
    elif __rt_str_eq(name, "no_delay"):
        level = 6
        opt = 1
    elif __rt_str_eq(name, "receive_buffer"):
        opt = 8
        boolean = false
    elif __rt_str_eq(name, "send_buffer"):
        opt = 7
        boolean = false
    elif __rt_str_eq(name, "reuse_port"):
        opt = 15
    elif __rt_str_eq(name, "ttl") or __rt_str_eq(name, "multicast_ttl") or __rt_str_eq(name, "multicast_loop"):
        v6 := __load64(s + 8) == 6
        v := 0
        if __rt_str_eq(name, "multicast_loop"):
            if __nat_bool("set_option", c, "la valeur"):
                v = 1
        else:
            t := __nat_int("set_option", c, "la valeur")
            if t < 0 or t > 255:
                __dyn_err("ArgumentError", "'set_option' : durée de vie hors de 0..255")
            v = t
        if v6:
            o := 19
            if __rt_str_eq(name, "ttl"):
                o = 16
            elif __rt_str_eq(name, "multicast_ttl"):
                o = 18
            return __ns_setopt(fd, 41, o, v, 4)
        if __rt_str_eq(name, "ttl"):
            return __ns_setopt(fd, 0, 2, v, 4)
        o := 34
        if __rt_str_eq(name, "multicast_ttl"):
            o = 33
        return __ns_setopt(fd, 0, o, v, 1)
    else:
        __dyn_err("ArgumentError", "'set_option' : option inconnue '" + name + "'")
    val := 0
    if boolean:
        if __nat_bool("set_option", c, "la valeur"):
            val = 1
    else:
        v := __nat_int("set_option", c, "la valeur")
        if v < 1 or v > 1073741824:
            __dyn_err("ArgumentError", "'set_option' : taille de tampon invalide")
        val = v
    return __ns_setopt(fd, level, opt, val, 4)

# Index d'une interface par son nom (SIOCGIFINDEX), 0 si inconnue.
func __ns_ifindex(name: str) -> int:
    fd := __syscall(41, 2, 2 | 524288, 0)
    if fd < 0:
        return 0
    req := __alloc_raw(40)
    __zero(req, 40)
    m := __nat_blen(name)
    if m > 15:
        m = 15
    __copy(req, __nat_bp(name), m)
    r := __syscall(16, fd, 35123, req)
    __syscall(3, fd)
    if r != 0:
        return 0
    return __load32(req + 16)

func __nat__native_net__multicast(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("multicast", n, 4, 4)
    s := __ns_sock("multicast", a)
    op := __nat_cstr("multicast", b, "l'opération")
    group := __nat_cstr("multicast", c, "le groupe")
    iface := __nat_cstr("multicast", d, "l'interface")
    if not __rt_str_eq(op, "join") and not __rt_str_eq(op, "leave") and not __rt_str_eq(op, "interface"):
        __dyn_err("ArgumentError", "'multicast' : opération \"join\", \"leave\" ou \"interface\" attendue")
    fd := __load64(s)
    buf := __alloc_raw(32)
    __zero(buf, 32)
    if __load64(s + 8) == 4:
        ifa := __alloc_raw(8)
        __store32(ifa, 0)
        if __nat_blen(iface) > 0 and not __ns_pton4(iface, ifa):
            __dyn_err("ArgumentError", "'multicast' : adresse d'interface IPv4 invalide '" + iface + "'")
        if __rt_str_eq(op, "interface"):
            r := __syscall(54, fd, 0, 32, ifa, 4)
            if r != 0:
                return __dyn_int(r)
            return __dyn_int(0)
        if not __ns_pton4(group, buf):
            __dyn_err("ArgumentError", "'multicast' : groupe IPv4 invalide '" + group + "'")
        __store32(buf + 4, __load32(ifa))
        o := 36
        if __rt_str_eq(op, "join"):
            o = 35
        r := __syscall(54, fd, 0, o, buf, 8)
        if r != 0:
            return __dyn_int(r)
        return __dyn_int(0)
    if __load64(s + 8) != 6:
        __dyn_err("ArgumentError", "'multicast' : socket IPv4 ou IPv6 attendu")
    index := 0
    if __nat_blen(iface) > 0:
        index = __ns_ifindex(iface)
        if index == 0:
            __dyn_err("ArgumentError", "'multicast' : interface inconnue '" + iface + "'")
    if __rt_str_eq(op, "interface"):
        return __ns_setopt(fd, 41, 17, index, 4)
    if not __ns_pton6(group, buf):
        __dyn_err("ArgumentError", "'multicast' : groupe IPv6 invalide '" + group + "'")
    __store32(buf + 16, index)
    o := 21
    if __rt_str_eq(op, "join"):
        o = 20
    r := __syscall(54, fd, 41, o, buf, 20)
    if r != 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_net__shutdown(n: int, a: int, b: int) -> int:
    __nat_range("shutdown", n, 2, 2)
    s := __ns_sock("shutdown", a)
    how := __nat_cstr("shutdown", b, "le sens")
    h := -1
    if __rt_str_eq(how, "read"):
        h = 0
    elif __rt_str_eq(how, "write"):
        h = 1
    elif __rt_str_eq(how, "both"):
        h = 2
    if h < 0:
        __dyn_err("ArgumentError", "'shutdown' : sens \"read\", \"write\" ou \"both\" attendu")
    r := __syscall(48, __load64(s), h)
    if r != 0:
        return __dyn_int(r)
    return __dyn_int(0)

func __nat__native_net__close(n: int, a: int) -> int:
    __nat_range("close", n, 1, 1)
    h := __nat_int("close", a, "le handle")
    t := __ns_table()
    e := __rt_dict_index(t, h, 0)
    if e >= 0:
        s := __load64(__load64(t + 32) + 8 * e)
        __syscall(3, __load64(s))
        __rt_dict_remove(t, h, 0)
    return 0

func __nat__native_net__wait(n: int, a: int, b: int, c: int) -> int:
    __nat_range("wait", n, 3, 3)
    hs := __nat_items("wait", a, "les handles", "une list")
    mode := __nat_cstr("wait", b, "le mode")
    if not __rt_str_eq(mode, "read") and not __rt_str_eq(mode, "write"):
        __dyn_err("ArgumentError", "'wait' : mode \"read\" ou \"write\" attendu")
    end := __nat_deadline(__nat_timeout("wait", c))
    ev := 4
    if __rt_str_eq(mode, "read"):
        ev = 1
    k := __load64(hs)
    p := __alloc_raw(8 * k + 8)
    i := 0
    while i < k:
        s := __ns_sock("wait", __rt_vec_at(hs, i))
        __store32(p + 8 * i, __load64(s))
        __store16(p + 8 * i + 4, ev)
        __store16(p + 8 * i + 6, 0)
        i += 1
    while true:
        r := __syscall(7, p, k, __nat_remaining_ms(end))
        if r == -4:
            continue
        if r < 0:
            __dyn_err("IoError", "wait : " + __nat_errno_text(0 - r))
        break
    out := __dyn_list_new(0)
    i = 0
    while i < k:
        if __load16(p + 8 * i + 6) != 0:
            __dyn_list_push(out, __rt_vec_at(hs, i))
        i += 1
    return out

func __nat__native_net__family(n: int, a: int) -> int:
    __nat_range("family", n, 1, 1)
    return __dyn_int(__load64(__ns_sock("family", a) + 8))

func __nat__native_net__fd(n: int, a: int) -> int:
    __nat_range("fd", n, 1, 1)
    return __dyn_int(__load64(__ns_sock("fd", a)))

func __nat__native_net__strerror(n: int, a: int) -> int:
    __nat_range("strerror", n, 1, 1)
    c := __nat_int("strerror", a, "le code")
    if c < 0:
        c = 0 - c
    return __dyn_str(__ns_strerror(c))

func __ns_strerror(c: int) -> str:
    if c == 0:
        return "Success"
    t := __nat_split_bytes("97:Address family not supported by protocol|98:Address already in use|99:Cannot assign requested address|100:Network is down|101:Network is unreachable|103:Software caused connection abort|104:Connection reset by peer|105:No buffer space available|106:Transport endpoint is already connected|107:Transport endpoint is not connected|110:Connection timed out|111:Connection refused|113:No route to host|115:Operation now in progress|90:Message too long|88:Socket operation on non-socket|92:Protocol not available|93:Protocol not supported|94:Socket type not supported|95:Operation not supported", 124)
    i := 0
    while i < __load64(t):
        it := __as_str(__rt_vec_at(t, i))
        q := __dyn_find_bytes(it, ":", 0)
        if __rt_str_eq(__nat_sub(it, 0, q), __int_to_str(c)):
            return __nat_sub(it, q + 1, __nat_blen(it) - q - 1)
        i += 1
    return __nat_errno_text(c)

func __nat__native_net__errno_name(n: int, a: int) -> int:
    __nat_range("errno_name", n, 1, 1)
    c := __nat_int("errno_name", a, "le code")
    if c < 0:
        c = 0 - c
    t := __nat_split_bytes("111:ECONNREFUSED,110:ETIMEDOUT,104:ECONNRESET,32:EPIPE,113:EHOSTUNREACH,101:ENETUNREACH,98:EADDRINUSE,99:EADDRNOTAVAIL,11:EAGAIN,107:ENOTCONN,13:EACCES,22:EINVAL,103:ECONNABORTED,97:EAFNOSUPPORT,106:EISCONN,90:EMSGSIZE,1:EPERM,100:ENETDOWN", 44)
    i := 0
    while i < __load64(t):
        it := __as_str(__rt_vec_at(t, i))
        q := __dyn_find_bytes(it, ":", 0)
        if __rt_str_eq(__nat_sub(it, 0, q), __int_to_str(c)):
            return __dyn_str(__nat_sub(it, q + 1, __nat_blen(it) - q - 1))
        i += 1
    return __dyn_str("E" + __int_to_str(c))

func __nat__native_net__random_bytes(n: int, a: int) -> int:
    __nat_range("random_bytes", n, 1, 1)
    k := __nat_int("random_bytes", a, "la taille")
    if k < 0 or k > 1048576:
        __dyn_err("ArgumentError", "'random_bytes' : taille hors de 0..1 Mio")
    r := __rt_str_new(k)
    got := 0
    while got < k:
        g := __syscall(318, r + 8 + got, k - got, 0)
        if g == -4:
            continue
        if g <= 0:
            __dyn_err("IoError", "random_bytes : " + __nat_errno_text(0 - g))
        got += g
    return __dyn_str(__as_str(r))

func __nat__native_net__live_count(n: int) -> int:
    __nat_range("live_count", n, 0, 0)
    return __dyn_int(__load64(__ns_table()))

# ---- DNS : /etc/hosts, puis requête UDP aux serveurs de /etc/resolv.conf (getaddrinfo) ----

# Adresses de `host` dans /etc/hosts : liste native de [famille, adresse] (listes natives).
func __ns_hosts(host: str, fam: int) -> int:
    out := __rt_list_new(0)
    db := 0
    if __windows():
        db = __nat_db_ws(__pw_hosts_path())
    else:
        db = __nat_db_ws("/etc/hosts")
    lname := __nat_case(host, 1)
    i := 0
    while i < __load64(db):
        f := __rt_vec_at(db, i)
        if __load64(f) >= 2:
            addr := __as_str(__rt_vec_at(f, 0))
            j := 1
            hit := false
            while j < __load64(f):
                if __rt_str_eq(__nat_case(__as_str(__rt_vec_at(f, j)), 1), lname):
                    hit = true
                j += 1
            if hit:
                b := __alloc_raw(16)
                af := 0
                if __ns_pton4(addr, b):
                    af = 4
                elif __ns_pton6(addr, b):
                    af = 6
                if af != 0 and (fam == 0 or fam == af):
                    e := __rt_list_new(0)
                    __rt_list_push(e, af)
                    if af == 4:
                        __rt_list_push(e, __str_addr(__ns_ntop4(b)))
                    else:
                        __rt_list_push(e, __str_addr(__ns_ntop6(b)))
                    __rt_list_push(out, e)
        i += 1
    return out

# Lignes d'un fichier en champs séparés par des blancs (commentaires « # » ôtés).
func __nat_db_ws(path: str) -> int:
    out := __rt_list_new(0)
    fd := __syscall(2, __nat_c(path), 0)
    if fd < 0:
        return out
    data := __nat_read_fd(fd, -1)
    __syscall(3, fd)
    lines := __nat_split_bytes(data, 10)
    i := 0
    while i < __load64(lines):
        ln := __as_str(__rt_vec_at(lines, i))
        h := __dyn_find_bytes(ln, "#", 0)
        if h >= 0:
            ln = __nat_sub(ln, 0, h)
        f := __rt_list_new(0)
        p := __nat_bp(ln)
        m := __nat_blen(ln)
        j := 0
        while j < m:
            while j < m and (__load8(p + j) == 32 or __load8(p + j) == 9 or __load8(p + j) == 13):
                j += 1
            st := j
            while j < m and __load8(p + j) != 32 and __load8(p + j) != 9 and __load8(p + j) != 13:
                j += 1
            if j > st:
                __rt_list_push(f, __str_addr(__nat_make(p + st, j - st)))
        if __load64(f) > 0:
            __rt_list_push(out, f)
        i += 1
    return out

# Requête DNS (type 1 : A, 28 : AAAA) ; renvoie [code, adresses...] : code 0 réponse, 3 nom inconnu, -1 aucune réponse.
func __ns_dns(host: str, qtype: int) -> int:
    out := __rt_list_new(0)
    conf := __nat_db_ws("/etc/resolv.conf")
    servers := __rt_list_new(0)
    timeout := 5
    attempts := 2
    i := 0
    while i < __load64(conf):
        f := __rt_vec_at(conf, i)
        key := __as_str(__rt_vec_at(f, 0))
        if __rt_str_eq(key, "nameserver") and __load64(f) >= 2:
            __rt_list_push(servers, __rt_vec_at(f, 1))
        if __rt_str_eq(key, "options"):
            j := 1
            while j < __load64(f):
                o := __as_str(__rt_vec_at(f, j))
                if __nat_blen(o) > 8 and __rt_str_eq(__nat_sub(o, 0, 8), "timeout:"):
                    timeout = __rt_str_to_int(__nat_sub(o, 8, __nat_blen(o) - 8))
                if __nat_blen(o) > 9 and __rt_str_eq(__nat_sub(o, 0, 9), "attempts:"):
                    attempts = __rt_str_to_int(__nat_sub(o, 9, __nat_blen(o) - 9))
                j += 1
        i += 1
    if __load64(servers) == 0:
        __rt_list_push(servers, __str_addr("127.0.0.1"))
    # requête
    sb := __rt_sb_new()
    qid := __syscall(39) & 65535
    __rt_sb_byte(sb, qid >> 8)
    __rt_sb_byte(sb, qid & 255)
    __rt_sb_byte(sb, 1)
    __rt_sb_byte(sb, 0)
    __rt_sb_byte(sb, 0)
    __rt_sb_byte(sb, 1)
    k := 0
    while k < 6:
        __rt_sb_byte(sb, 0)
        k += 1
    labels := __nat_split_bytes(host, 46)
    k = 0
    while k < __load64(labels):
        lb := __as_str(__rt_vec_at(labels, k))
        if __nat_blen(lb) > 0:
            __rt_sb_byte(sb, __nat_blen(lb) & 63)
            __rt_sb_add(sb, lb)
        k += 1
    __rt_sb_byte(sb, 0)
    __rt_sb_byte(sb, 0)
    __rt_sb_byte(sb, qtype)
    __rt_sb_byte(sb, 0)
    __rt_sb_byte(sb, 1)
    q := __rt_sb_str(sb)
    buf := __alloc_raw(4096)
    att := 0
    while att < attempts:
        si := 0
        while si < __load64(servers):
            srv := __as_str(__rt_vec_at(servers, si))
            ss := __alloc_raw(128)
            fam := 4
            if __dyn_find_bytes(srv, ":", 0) >= 0:
                fam = 6
            __zero(ss, 128)
            ok := true
            if fam == 4:
                __store16(ss, 2)
                ok = __ns_pton4(srv, ss + 4)
            else:
                __store16(ss, 10)
                ok = __ns_pton6(srv, ss + 8)
            __store8(ss + 3, 53)
            if ok:
                af := 2
                if fam == 6:
                    af = 10
                fd := __syscall(41, af, 2 | 524288, 0)
                if fd >= 0:
                    sl := 16
                    if fam == 6:
                        sl = 28
                    __syscall(44, fd, __nat_bp(q), __nat_blen(q), 16384, ss, sl)
                    end := __nat_clock(1) + __i2f(timeout)
                    while true:
                        r := __fd_poll1(fd, 1, __nat_remaining_ms(end))
                        if r <= 0 and r != -4:
                            break
                        got := __syscall(45, fd, buf, 4096, 0, 0, 0)
                        if got >= 12 and ((__load8(buf) << 8) | __load8(buf + 1)) == qid:
                            __syscall(3, fd)
                            return __ns_dns_parse(buf, got, qtype)
                    __syscall(3, fd)
            si += 1
        att += 1
    __rt_list_push(out, -1)
    return out

func __ns_dns_skip_name(buf: int, n: int, p: int) -> int:
    while p < n:
        l := __load8(buf + p)
        if l == 0:
            return p + 1
        if (l & 192) == 192:
            return p + 2
        p += 1 + l
    return n

func __ns_dns_parse(buf: int, n: int, qtype: int) -> int:
    out := __rt_list_new(0)
    rcode := __load8(buf + 3) & 15
    __rt_list_push(out, rcode)
    qd := (__load8(buf + 4) << 8) | __load8(buf + 5)
    an := (__load8(buf + 6) << 8) | __load8(buf + 7)
    p := 12
    i := 0
    while i < qd:
        p = __ns_dns_skip_name(buf, n, p) + 4
        i += 1
    i = 0
    while i < an and p + 10 <= n:
        p = __ns_dns_skip_name(buf, n, p)
        ty := (__load8(buf + p) << 8) | __load8(buf + p + 1)
        rl := (__load8(buf + p + 8) << 8) | __load8(buf + p + 9)
        p += 10
        if ty == qtype and qtype == 1 and rl == 4:
            __rt_list_push(out, __str_addr(__ns_ntop4(buf + p)))
        if ty == qtype and qtype == 28 and rl == 16:
            __rt_list_push(out, __str_addr(__ns_ntop6(buf + p)))
        p += rl
        i += 1
    return out

func __nat__native_net__resolve(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("resolve", n, 4, 4)
    host := __nat_cstr("resolve", a, "l'hôte")
    port := 0
    if b != 0:
        port = __ns_port("resolve", b)
    fam := __nat_int("resolve", c, "la famille")
    if fam != 0 and fam != 4 and fam != 6:
        __dyn_err("ArgumentError", "'resolve' : famille 0, 4 ou 6 attendue")
    __ns_udp("resolve", d)
    found := __rt_list_new(0)
    nb := __alloc_raw(16)
    if __ns_pton4(host, nb):
        if fam == 6:
            return __dyn_str("Address family for hostname not supported")
        e := __rt_list_new(0)
        __rt_list_push(e, 4)
        __rt_list_push(e, __str_addr(__ns_ntop4(nb)))
        __rt_list_push(found, e)
    elif __ns_pton6(host, nb):
        if fam == 4:
            return __dyn_str("Address family for hostname not supported")
        e := __rt_list_new(0)
        __rt_list_push(e, 6)
        __rt_list_push(e, __str_addr(__ns_ntop6(nb)))
        __rt_list_push(found, e)
    elif __windows():
        found = __ns_hosts(host, fam)
        if __load64(found) == 0:
            werr := __alloc(8)
            found = __pw_resolve(host, fam, __ns_udp("resolve", d), werr)
            if __load64(werr) != 0:
                return __dyn_str(__as_str(__load64(werr)))
    else:
        found = __ns_hosts(host, fam)
        if __load64(found) == 0:
            if __nat_blen(host) == 0:
                return __dyn_str("Name or service not known")
            nx := false
            answered := false
            if fam == 0 or fam == 4:
                r := __ns_dns(host, 1)
                code := __rt_vec_at(r, 0)
                if code == 3:
                    nx = true
                if code >= 0:
                    answered = true
                i := 1
                while i < __load64(r):
                    e := __rt_list_new(0)
                    __rt_list_push(e, 4)
                    __rt_list_push(e, __rt_vec_at(r, i))
                    __rt_list_push(found, e)
                    i += 1
            if (fam == 0 or fam == 6) and not nx:
                r := __ns_dns(host, 28)
                code := __rt_vec_at(r, 0)
                if code == 3:
                    nx = true
                if code >= 0:
                    answered = true
                i := 1
                while i < __load64(r):
                    e := __rt_list_new(0)
                    __rt_list_push(e, 6)
                    __rt_list_push(e, __rt_vec_at(r, i))
                    __rt_list_push(found, e)
                    i += 1
            if __load64(found) == 0:
                if nx or answered:
                    return __dyn_str("Name or service not known")
                return __dyn_str("Temporary failure in name resolution")
    out := __dyn_list_new(0)
    i := 0
    while i < __load64(found):
        e := __rt_vec_at(found, i)
        l := __dyn_list_new(0)
        __dyn_list_push(l, __dyn_int(__rt_vec_at(e, 0)))
        __dyn_list_push(l, __dyn_str(__as_str(__rt_vec_at(e, 1))))
        __dyn_list_push(l, __dyn_int(port))
        __dyn_list_push(out, l)
        i += 1
    return out

func __nat__native_net__reverse(n: int, a: int) -> int:
    __nat_range("reverse", n, 1, 1)
    addr := __nat_cstr("reverse", a, "l'adresse")
    ss := __alloc_raw(128)
    fam := 4
    if __dyn_find_bytes(addr, ":", 0) >= 0:
        fam = 6
    __ns_sockaddr("reverse", fam, addr, 0, ss)
    canon := ""
    if fam == 4:
        canon = __ns_ntop4(ss + 4)
    else:
        canon = __ns_ntop6(ss + 8)
    db := 0
    if __windows():
        db = __nat_db_ws(__pw_hosts_path())
    else:
        db = __nat_db_ws("/etc/hosts")
    i := 0
    while i < __load64(db):
        f := __rt_vec_at(db, i)
        if __load64(f) >= 2:
            b := __alloc_raw(16)
            a2 := __as_str(__rt_vec_at(f, 0))
            same := false
            if fam == 4 and __ns_pton4(a2, b):
                same = __rt_str_eq(__ns_ntop4(b), canon)
            if fam == 6 and __ns_pton6(a2, b):
                same = __rt_str_eq(__ns_ntop6(b), canon)
            if same:
                return __dyn_str(__as_str(__rt_vec_at(f, 1)))
        i += 1
    return 0

# ---- _native_tls : indisponible dans un exécutable natif (la VM charge OpenSSL dynamiquement) ------------------

func __nat__native_tls__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    return __dyn_bool(false)

func __nat__native_tls__why(n: int) -> int:
    __nat_range("why", n, 0, 0)
    return __dyn_str("TLS non pris en charge dans un exécutable natif (OpenSSL n'y est pas chargeable)")

func __tls_off(fn: str):
    __dyn_err("IoError", fn + " : TLS indisponible — TLS non pris en charge dans un exécutable natif (OpenSSL n'y est pas chargeable)")

func __nat__native_tls__version(n: int) -> int:
    __nat_range("version", n, 0, 0)
    __tls_off("version")
    return 0

func __nat__native_tls__client(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int, x: int) -> int:
    __nat_range("client", n, 9, 9)
    __tls_off("client")
    return 0

func __nat__native_tls__server(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("server", n, 5, 5)
    __tls_off("server")
    return 0

func __nat__native_tls__read(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("read", n, 3, 3)
    __tls_off("read")
    return 0

func __nat__native_tls__write(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("write", n, 3, 3)
    __tls_off("write")
    return 0

func __nat__native_tls__pending(n: int, a0: int) -> int:
    __nat_range("pending", n, 1, 1)
    __tls_off("pending")
    return 0

func __nat__native_tls__shutdown(n: int, a0: int, a1: int) -> int:
    __nat_range("shutdown", n, 2, 2)
    __tls_off("shutdown")
    return 0

func __nat__native_tls__info(n: int, a0: int) -> int:
    __nat_range("info", n, 1, 1)
    __tls_off("info")
    return 0

func __nat__native_tls__peer_certificate(n: int, a0: int) -> int:
    __nat_range("peer_certificate", n, 1, 1)
    __tls_off("peer_certificate")
    return 0

func __nat__native_tls__digest(n: int, a0: int, a1: int) -> int:
    __nat_range("digest", n, 2, 2)
    return 0

func __nat__native_tls__hmac(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("hmac", n, 3, 3)
    return 0

func __nat__native_tls__pbkdf2(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("pbkdf2", n, 5, 5)
    return 0

func __nat__native_tls__close(n: int, a0: int) -> int:
    __nat_range("close", n, 1, 1)
    return 0

func __nat__native_tls__live_count(n: int) -> int:
    __nat_range("live_count", n, 0, 0)
    return __dyn_int(0)

# ---- _native_sync : objets de synchronisation, dans la région partagée des fils (__th_region) -----------------------
# Table R+4096+6 Mio : 65536 pointeurs ; R+56 prochain identifiant. Objet (bloc partagé de 64 octets) : [0] genre
# 1 atomic, 2 ref, 3 mutex, 4 rwlock, 5 spinlock, 6 semaphore, 7 condition, 8 barrier, 9 latch, 10 once, 11 event,
# puis ses champs. Attentes : séquence de la région (__th_wait), comme les canaux.

func __sy_table(r: int) -> int:
    return r + 4096 + 2097152 + 4194304

func __sy_token() -> int: # identité du fil : 1 programme principal, id + 1 pour un fil
    return __load64(__dyn_ds() + 120) + 1

func __sy_kind_name(k: int) -> str:
    l := __nat_split_bytes(",atomic,ref,mutex,rwlock,spinlock,semaphore,condition,barrier,latch,once,event", 44)
    return __as_str(__rt_vec_at(l, k))

func __sy_new(kind: int) -> int: # sous le verrou : [identifiant, objet] -> objet (identifiant en [56] de l'objet)
    r := __th_region()
    id := __load64(r + 56)
    if id >= 65536:
        __th_unlock(r)
        __dyn_err("IoError", "sync : trop d'objets de synchronisation")
    o := __th_alloc(r, 64)
    if o == 0:
        __th_unlock(r)
        __dyn_err("MemoryError", "sync : mémoire partagée épuisée")
    __zero(o, 64)
    __store64(o, kind)
    __store64(o + 56, id)
    __store64(__sy_table(r) + 8 * id, o)
    __store64(r + 56, id + 1)
    return o

func __sy_get(fn: str, v: int, kind: int) -> int:
    id := __nat_int(fn, v, "l'identifiant")
    r := __th_region()
    o := 0
    if id > 0 and id < 65536:
        o = __load64(__sy_table(r) + 8 * id)
    if o == 0:
        __dyn_err("ArgumentError", "'" + fn + "' : objet de synchronisation inconnu ou détruit (" + __int_to_str(id) + ")")
    if kind != 0 and __load64(o) != kind:
        __dyn_err("TypeError", "'" + fn + "' : l'objet " + __int_to_str(id) + " est un(e) " + __sy_kind_name(__load64(o)))
    return o

func __sy_create(kind: int, a: int, b: int, c: int) -> int:
    r := __th_region()
    __th_lock(r)
    o := __sy_new(kind)
    __store64(o + 8, a)
    __store64(o + 16, b)
    __store64(o + 24, c)
    __th_unlock(r)
    return __dyn_int(__load64(o + 56))

func __nat__native_sync__token(n: int) -> int:
    __nat_range("token", n, 0, 0)
    return __dyn_int(__sy_token())

func __nat__native_sync__kind(n: int, a: int) -> int:
    __nat_range("kind", n, 1, 1)
    id := __nat_int("kind", a, "l'identifiant")
    r := __th_region()
    if id <= 0 or id >= 65536 or __load64(__sy_table(r) + 8 * id) == 0:
        return 0
    return __dyn_str(__sy_kind_name(__load64(__load64(__sy_table(r) + 8 * id))))

func __nat__native_sync__destroy(n: int, a: int) -> int:
    __nat_range("destroy", n, 1, 1)
    id := __nat_int("destroy", a, "l'identifiant")
    r := __th_region()
    if id <= 0 or id >= 65536:
        return __dyn_bool(false)
    __th_lock(r)
    o := __load64(__sy_table(r) + 8 * id)
    if o != 0:
        __store64(__sy_table(r) + 8 * id, 0)
        __th_free(r, o)
    __th_unlock(r)
    __th_notify(r)
    return __dyn_bool(o != 0)

func __nat__native_sync__live(n: int) -> int:
    __nat_range("live", n, 0, 0)
    r := __th_region()
    k := 0
    i := 1
    while i < __load64(r + 56):
        if __load64(__sy_table(r) + 8 * i) != 0:
            k += 1
        i += 1
    return __dyn_int(k)

# ---- atomiques ----

func __nat__native_sync__atomic_new(n: int, a: int) -> int:
    __nat_range("atomic_new", n, 1, 1)
    return __sy_create(1, __nat_int("atomic_new", a, "la valeur"), 0, 0)

func __nat__native_sync__atomic_load(n: int, a: int) -> int:
    __nat_range("atomic_load", n, 1, 1)
    return __dyn_int(__xadd(__sy_get("atomic_load", a, 1) + 8, 0))

func __sy_changed():
    __th_notify(__th_region())

func __nat__native_sync__atomic_store(n: int, a: int, b: int) -> int:
    __nat_range("atomic_store", n, 2, 2)
    o := __sy_get("atomic_store", a, 1)
    v := __nat_int("atomic_store", b, "la valeur")
    old := __load64(o + 8)
    while __cas(o + 8, old, v) != old:
        old = __load64(o + 8)
    __sy_changed()
    return 0

func __nat__native_sync__atomic_exchange(n: int, a: int, b: int) -> int:
    __nat_range("atomic_exchange", n, 2, 2)
    o := __sy_get("atomic_exchange", a, 1)
    v := __nat_int("atomic_exchange", b, "la valeur")
    old := __load64(o + 8)
    while __cas(o + 8, old, v) != old:
        old = __load64(o + 8)
    __sy_changed()
    return __dyn_int(old)

func __nat__native_sync__atomic_cas(n: int, a: int, b: int, c: int) -> int:
    __nat_range("atomic_cas", n, 3, 3)
    o := __sy_get("atomic_cas", a, 1)
    e := __nat_int("atomic_cas", b, "la valeur attendue")
    d := __nat_int("atomic_cas", c, "la nouvelle valeur")
    old := __cas(o + 8, e, d)
    ok := old == e
    if ok:
        __sy_changed()
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_bool(ok))
    __dyn_list_push(l, __dyn_int(old))
    return l

func __nat__native_sync__atomic_fetch(n: int, a: int, b: int, c: int) -> int:
    __nat_range("atomic_fetch", n, 3, 3)
    o := __sy_get("atomic_fetch", a, 1)
    op := __nat_cstr("atomic_fetch", b, "l'opération")
    v := __nat_int("atomic_fetch", c, "l'opérande")
    code := 0
    names := __nat_split_bytes("add,sub,and,or,xor,nand,max,min", 44)
    i := 0
    while i < 8:
        if __rt_str_eq(__as_str(__rt_vec_at(names, i)), op):
            code = i + 1
        i += 1
    if code == 0:
        __dyn_err("ArgumentError", "'atomic_fetch' : opération inconnue '" + op + "'")
    while true:
        old := __load64(o + 8)
        nv := old
        if code == 1:
            nv = old + v
        elif code == 2:
            nv = old - v
        elif code == 3:
            nv = old & v
        elif code == 4:
            nv = old | v
        elif code == 5:
            nv = old ^ v
        elif code == 6:
            nv = ~(old & v)
        elif code == 7:
            if v > old:
                nv = v
        else:
            if v < old:
                nv = v
        if __cas(o + 8, old, nv) == old:
            __sy_changed()
            return __dyn_int(old)
    return 0

func __nat__native_sync__atomic_wait(n: int, a: int, b: int, c: int) -> int:
    __nat_range("atomic_wait", n, 3, 3)
    o := __sy_get("atomic_wait", a, 1)
    old := __nat_int("atomic_wait", b, "la valeur")
    end := __nat_deadline(__nat_timeout("atomic_wait", c))
    r := __th_region()
    while true:
        seq := __th_seq(r)
        if __load64(o + 8) != old:
            return __dyn_int(1)
        if not __th_wait(r, seq, end):
            return __dyn_int(0)
    return 0

func __nat__native_sync__atomic_notify(n: int, a: int, b: int) -> int:
    __nat_range("atomic_notify", n, 1, 2)
    __sy_get("atomic_notify", a, 1)
    __sy_changed()
    return 0

# ---- référence atomique : [8] valeur (blob sérialisé) [16] version ----

func __nat__native_sync__ref_new(n: int, a: int) -> int:
    __nat_range("ref_new", n, 1, 1)
    enc := __pt_encode(a, "AtomicReference : valeur")
    r := __th_region()
    __th_lock(r)
    o := __sy_new(2)
    __store64(o + 8, __th_blob(r, enc))
    __th_unlock(r)
    return __dyn_int(__load64(o + 56))

func __nat__native_sync__ref_load(n: int, a: int) -> int:
    __nat_range("ref_load", n, 1, 1)
    o := __sy_get("ref_load", a, 2)
    r := __th_region()
    __th_lock(r)
    v := __th_blob_str(__load64(o + 8))
    __th_unlock(r)
    return __pt_decode_at(__nat_bp(v))

func __sy_ref_set(o: int, enc: str) -> str: # renvoie l'ancienne valeur sérialisée
    r := __th_region()
    __th_lock(r)
    old := __th_blob_str(__load64(o + 8))
    __th_free(r, __load64(o + 8))
    __store64(o + 8, __th_blob(r, enc))
    __store64(o + 16, __load64(o + 16) + 1)
    __th_unlock(r)
    __th_notify(r)
    return old

func __nat__native_sync__ref_store(n: int, a: int, b: int) -> int:
    __nat_range("ref_store", n, 2, 2)
    o := __sy_get("ref_store", a, 2)
    __sy_ref_set(o, __pt_encode(b, "AtomicReference : valeur"))
    return 0

func __nat__native_sync__ref_exchange(n: int, a: int, b: int) -> int:
    __nat_range("ref_exchange", n, 2, 2)
    o := __sy_get("ref_exchange", a, 2)
    old := __sy_ref_set(o, __pt_encode(b, "AtomicReference : valeur"))
    return __pt_decode_at(__nat_bp(old))

# Égalité de valeurs copiables (portableEq) : nombres par valeur, le reste structurellement.
func __sy_peq(a: int, b: int) -> bool:
    ka := __dyn_kind(a)
    kb := __dyn_kind(b)
    if (ka == 1 or ka == 2) and (kb == 1 or kb == 2):
        if ka == 1 and kb == 1:
            return __dyn_iv(a) == __dyn_iv(b)
        x := 0.0
        y := 0.0
        if ka == 1:
            x = __i2f(__dyn_iv(a))
        else:
            x = __dyn_fv(a)
        if kb == 1:
            y = __i2f(__dyn_iv(b))
        else:
            y = __dyn_fv(b)
        return x == y
    if ka != kb:
        return false
    if ka == 7 or ka == 8:
        m := 0
        mb := 0
        if ka == 7:
            m = __dyn_list_len(a)
            mb = __dyn_list_len(b)
        else:
            m = __dyn_tuple_len(a)
            mb = __dyn_tuple_len(b)
        if m != mb:
            return false
        i := 0
        while i < m:
            if ka == 7:
                if not __sy_peq(__dyn_list_at(a, i), __dyn_list_at(b, i)):
                    return false
            elif not __sy_peq(__dyn_tuple_at(a, i), __dyn_tuple_at(b, i)):
                return false
            i += 1
        return true
    if ka == 9:
        da := __dyn_dv(a)
        db := __dyn_dv(b)
        if __load64(da) != __load64(db):
            return false
        e := 0
        while e < __load64(da + 8):
            if __load64(__load64(da + 40) + 8 * e) >= 0:
                k := __load64(__load64(da + 24) + 8 * e)
                found := false
                f := 0
                while f < __load64(db + 8) and not found:
                    if __load64(__load64(db + 40) + 8 * f) >= 0 and __sy_peq(k, __load64(__load64(db + 24) + 8 * f)):
                        if not __sy_peq(__load64(__load64(da + 32) + 8 * e), __load64(__load64(db + 32) + 8 * f)):
                            return false
                        found = true
                    f += 1
                if not found:
                    return false
            e += 1
        return true
    return __dyn_eq(a, b)

func __nat__native_sync__ref_cas(n: int, a: int, b: int, c: int) -> int:
    __nat_range("ref_cas", n, 3, 3)
    o := __sy_get("ref_cas", a, 2)
    expected := __pt_decode_at(__nat_bp(__pt_encode(b, "AtomicReference : valeur attendue")))
    enc := __pt_encode(c, "AtomicReference : nouvelle valeur")
    r := __th_region()
    __th_lock(r)
    cur := __pt_decode_at(__nat_bp(__th_blob_str(__load64(o + 8))))
    l := __dyn_list_new(0)
    if __sy_peq(cur, expected):
        __th_free(r, __load64(o + 8))
        __store64(o + 8, __th_blob(r, enc))
        __store64(o + 16, __load64(o + 16) + 1)
        __th_unlock(r)
        __th_notify(r)
        __dyn_list_push(l, __dyn_bool(true))
        __dyn_list_push(l, __pt_decode_at(__nat_bp(enc)))
        return l
    __th_unlock(r)
    __dyn_list_push(l, __dyn_bool(false))
    __dyn_list_push(l, cur)
    return l

func __nat__native_sync__ref_version(n: int, a: int) -> int:
    __nat_range("ref_version", n, 1, 1)
    return __dyn_int(__load64(__sy_get("ref_version", a, 2) + 16))

# ---- mutex : [8] récursif [16] propriétaire [24] niveau [32] en attente ----

# Prise logique (verrou de la région pris à l'entrée, rendu en sortie) : 1 pris, 0 délai, -1 interblocage.
func __sy_lock_mutex(o: int, end: float, me: int) -> int:
    r := __th_region()
    if __load64(o + 16) == me:
        if __load64(o + 8) == 0:
            __th_unlock(r)
            return -1
        __store64(o + 24, __load64(o + 24) + 1)
        __th_unlock(r)
        return 1
    __store64(o + 32, __load64(o + 32) + 1)
    while __load64(o + 16) != 0:
        seq := __th_seq(r)
        __th_unlock(r)
        ok := __th_wait(r, seq, end)
        __th_lock(r)
        if not ok and __load64(o + 16) != 0:
            __store64(o + 32, __load64(o + 32) - 1)
            __th_unlock(r)
            return 0
    __store64(o + 32, __load64(o + 32) - 1)
    __store64(o + 16, me)
    __store64(o + 24, 1)
    __th_unlock(r)
    return 1

func __nat__native_sync__mutex_new(n: int, a: int) -> int:
    __nat_range("mutex_new", n, 1, 1)
    rec := 0
    if __nat_bool("mutex_new", a, "récursif"):
        rec = 1
    return __sy_create(3, rec, 0, 0)

func __nat__native_sync__mutex_lock(n: int, a: int, b: int) -> int:
    __nat_range("mutex_lock", n, 2, 2)
    o := __sy_get("mutex_lock", a, 3)
    end := __nat_deadline(__nat_timeout("mutex_lock", b))
    __th_lock(__th_region())
    return __dyn_int(__sy_lock_mutex(o, end, __sy_token()))

func __nat__native_sync__mutex_unlock(n: int, a: int) -> int:
    __nat_range("mutex_unlock", n, 1, 1)
    o := __sy_get("mutex_unlock", a, 3)
    r := __th_region()
    __th_lock(r)
    if __load64(o + 16) != __sy_token():
        __th_unlock(r)
        return __dyn_int(-1)
    __store64(o + 24, __load64(o + 24) - 1)
    if __load64(o + 24) == 0:
        __store64(o + 16, 0)
    __th_unlock(r)
    __th_notify(r)
    return __dyn_int(0)

func __nat__native_sync__mutex_info(n: int, a: int) -> int:
    __nat_range("mutex_info", n, 1, 1)
    o := __sy_get("mutex_info", a, 3)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_bool(__load64(o + 16) != 0))
    __dyn_list_push(l, __dyn_int(__load64(o + 16)))
    __dyn_list_push(l, __dyn_int(__load64(o + 24)))
    __dyn_list_push(l, __dyn_int(__load64(o + 32)))
    return l

# ---- verrou lecteurs / écrivain : [8] lecteurs (total) [16] écrivain [24] niveau d'écriture [32] écrivains en attente
# [40] table des lecteurs (bloc partagé : 64 paires [fil][prises]) ----

func __sy_readers_slot(o: int, me: int, create: bool) -> int:
    t := __load64(o + 40)
    i := 0
    free := -1
    while i < 64:
        if __load64(t + 16 * i) == me:
            return t + 16 * i
        if free < 0 and __load64(t + 16 * i) == 0:
            free = i
        i += 1
    if not create or free < 0:
        return 0
    __store64(t + 16 * free, me)
    __store64(t + 16 * free + 8, 0)
    return t + 16 * free

func __nat__native_sync__rw_new(n: int) -> int:
    __nat_range("rw_new", n, 0, 0)
    r := __th_region()
    __th_lock(r)
    o := __sy_new(4)
    t := __th_alloc(r, 1024)
    __zero(t, 1024)
    __store64(o + 40, t)
    __th_unlock(r)
    return __dyn_int(__load64(o + 56))

func __nat__native_sync__rw_read(n: int, a: int, b: int) -> int:
    __nat_range("rw_read", n, 2, 2)
    o := __sy_get("rw_read", a, 4)
    end := __nat_deadline(__nat_timeout("rw_read", b))
    me := __sy_token()
    r := __th_region()
    __th_lock(r)
    if __sy_readers_slot(o, me, false) == 0 and __load64(o + 16) != me:
        while __load64(o + 16) != 0 or __load64(o + 32) != 0:
            seq := __th_seq(r)
            __th_unlock(r)
            ok := __th_wait(r, seq, end)
            __th_lock(r)
            if not ok and (__load64(o + 16) != 0 or __load64(o + 32) != 0):
                __th_unlock(r)
                return __dyn_int(0)
    slot := __sy_readers_slot(o, me, true)
    __store64(slot + 8, __load64(slot + 8) + 1)
    __store64(o + 8, __load64(o + 8) + 1)
    __th_unlock(r)
    return __dyn_int(1)

func __nat__native_sync__rw_write(n: int, a: int, b: int) -> int:
    __nat_range("rw_write", n, 2, 2)
    o := __sy_get("rw_write", a, 4)
    end := __nat_deadline(__nat_timeout("rw_write", b))
    me := __sy_token()
    r := __th_region()
    __th_lock(r)
    if __load64(o + 16) == me:
        __store64(o + 24, __load64(o + 24) + 1)
        __th_unlock(r)
        return __dyn_int(1)
    if __sy_readers_slot(o, me, false) != 0:
        __th_unlock(r)
        return __dyn_int(-1)
    __store64(o + 32, __load64(o + 32) + 1)
    while __load64(o + 16) != 0 or __load64(o + 8) != 0:
        seq := __th_seq(r)
        __th_unlock(r)
        ok := __th_wait(r, seq, end)
        __th_lock(r)
        if not ok and (__load64(o + 16) != 0 or __load64(o + 8) != 0):
            __store64(o + 32, __load64(o + 32) - 1)
            __th_unlock(r)
            __th_notify(r)
            return __dyn_int(0)
    __store64(o + 32, __load64(o + 32) - 1)
    __store64(o + 16, me)
    __store64(o + 24, 1)
    __th_unlock(r)
    return __dyn_int(1)

func __nat__native_sync__rw_unlock_read(n: int, a: int) -> int:
    __nat_range("rw_unlock_read", n, 1, 1)
    o := __sy_get("rw_unlock_read", a, 4)
    r := __th_region()
    __th_lock(r)
    slot := __sy_readers_slot(o, __sy_token(), false)
    if slot == 0:
        __th_unlock(r)
        return __dyn_int(-1)
    __store64(slot + 8, __load64(slot + 8) - 1)
    if __load64(slot + 8) == 0:
        __store64(slot, 0)
    __store64(o + 8, __load64(o + 8) - 1)
    __th_unlock(r)
    __th_notify(r)
    return __dyn_int(0)

func __nat__native_sync__rw_unlock_write(n: int, a: int) -> int:
    __nat_range("rw_unlock_write", n, 1, 1)
    o := __sy_get("rw_unlock_write", a, 4)
    r := __th_region()
    __th_lock(r)
    if __load64(o + 16) != __sy_token():
        __th_unlock(r)
        return __dyn_int(-1)
    __store64(o + 24, __load64(o + 24) - 1)
    if __load64(o + 24) == 0:
        __store64(o + 16, 0)
    __th_unlock(r)
    __th_notify(r)
    return __dyn_int(0)

func __nat__native_sync__rw_downgrade(n: int, a: int) -> int:
    __nat_range("rw_downgrade", n, 1, 1)
    o := __sy_get("rw_downgrade", a, 4)
    me := __sy_token()
    r := __th_region()
    __th_lock(r)
    if __load64(o + 16) != me or __load64(o + 24) != 1:
        __th_unlock(r)
        return __dyn_int(-1)
    __store64(o + 16, 0)
    __store64(o + 24, 0)
    slot := __sy_readers_slot(o, me, true)
    __store64(slot + 8, __load64(slot + 8) + 1)
    __store64(o + 8, __load64(o + 8) + 1)
    __th_unlock(r)
    __th_notify(r)
    return __dyn_int(0)

func __nat__native_sync__rw_info(n: int, a: int) -> int:
    __nat_range("rw_info", n, 1, 1)
    o := __sy_get("rw_info", a, 4)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__load64(o + 8)))
    __dyn_list_push(l, __dyn_int(__load64(o + 16)))
    __dyn_list_push(l, __dyn_int(__load64(o + 32)))
    return l

# ---- verrou tournant : [8] propriétaire ----

func __nat__native_sync__spin_new(n: int) -> int:
    __nat_range("spin_new", n, 0, 0)
    return __sy_create(5, 0, 0, 0)

func __nat__native_sync__spin_lock(n: int, a: int, b: int) -> int:
    __nat_range("spin_lock", n, 2, 2)
    o := __sy_get("spin_lock", a, 5)
    end := __nat_deadline(__nat_timeout("spin_lock", b))
    me := __sy_token()
    if __load64(o + 8) == me:
        return __dyn_int(-1)
    spins := 0
    while true:
        if __load64(o + 8) == 0 and __cas(o + 8, 0, me) == 0:
            return __dyn_int(1)
        spins += 1
        if (spins & 63) == 63:
            if end >= 0.0 and __nat_clock(1) >= end:
                return __dyn_int(0)
            __syscall(24)
    return 0

func __nat__native_sync__spin_unlock(n: int, a: int) -> int:
    __nat_range("spin_unlock", n, 1, 1)
    o := __sy_get("spin_unlock", a, 5)
    me := __sy_token()
    if __load64(o + 8) != me:
        return __dyn_int(-1)
    __cas(o + 8, me, 0)
    return __dyn_int(0)

func __nat__native_sync__spin_info(n: int, a: int) -> int:
    __nat_range("spin_info", n, 1, 1)
    return __dyn_int(__load64(__sy_get("spin_info", a, 5) + 8))

# ---- sémaphore : [8] valeur [16] maximum [24] en attente ----

func __nat__native_sync__sem_new(n: int, a: int, b: int) -> int:
    __nat_range("sem_new", n, 2, 2)
    v := __nat_int("sem_new", a, "la valeur")
    mx := __nat_int("sem_new", b, "le maximum")
    if v < 0 or mx < 0 or (mx > 0 and v > mx):
        __dyn_err("ArgumentError", "'sem_new' : valeur hors de 0..max")
    return __sy_create(6, v, mx, 0)

func __nat__native_sync__sem_acquire(n: int, a: int, b: int, c: int) -> int:
    __nat_range("sem_acquire", n, 3, 3)
    o := __sy_get("sem_acquire", a, 6)
    k := __nat_int("sem_acquire", b, "le nombre")
    if k < 1:
        __dyn_err("ArgumentError", "'sem_acquire' : nombre >= 1 attendu")
    end := __nat_deadline(__nat_timeout("sem_acquire", c))
    r := __th_region()
    __th_lock(r)
    __store64(o + 24, __load64(o + 24) + 1)
    while __load64(o + 8) < k:
        seq := __th_seq(r)
        __th_unlock(r)
        ok := __th_wait(r, seq, end)
        __th_lock(r)
        if not ok and __load64(o + 8) < k:
            __store64(o + 24, __load64(o + 24) - 1)
            __th_unlock(r)
            return __dyn_int(0)
    __store64(o + 24, __load64(o + 24) - 1)
    __store64(o + 8, __load64(o + 8) - k)
    __th_unlock(r)
    return __dyn_int(1)

func __nat__native_sync__sem_release(n: int, a: int, b: int) -> int:
    __nat_range("sem_release", n, 2, 2)
    o := __sy_get("sem_release", a, 6)
    k := __nat_int("sem_release", b, "le nombre")
    if k < 1:
        __dyn_err("ArgumentError", "'sem_release' : nombre >= 1 attendu")
    r := __th_region()
    __th_lock(r)
    if __load64(o + 16) > 0 and __load64(o + 8) + k > __load64(o + 16):
        __th_unlock(r)
        return __dyn_int(-1)
    __store64(o + 8, __load64(o + 8) + k)
    __th_unlock(r)
    __th_notify(r)
    return __dyn_int(0)

func __nat__native_sync__sem_value(n: int, a: int) -> int:
    __nat_range("sem_value", n, 1, 1)
    o := __sy_get("sem_value", a, 6)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__load64(o + 8)))
    __dyn_list_push(l, __dyn_int(__load64(o + 16)))
    __dyn_list_push(l, __dyn_int(__load64(o + 24)))
    return l

# ---- condition : [8] mutex (objet) [16] en attente [24] permis ----

func __nat__native_sync__cond_new(n: int, a: int) -> int:
    __nat_range("cond_new", n, 1, 1)
    m := __sy_get("cond_new", a, 3)
    return __sy_create(7, m, 0, 0)

func __nat__native_sync__cond_wait(n: int, a: int, b: int) -> int:
    __nat_range("cond_wait", n, 2, 2)
    o := __sy_get("cond_wait", a, 7)
    end := __nat_deadline(__nat_timeout("cond_wait", b))
    mx := __load64(o + 8)
    me := __sy_token()
    r := __th_region()
    __th_lock(r)
    if __load64(mx + 16) != me:
        __th_unlock(r)
        return __dyn_int(-1)
    level := __load64(mx + 24)
    __store64(mx + 16, 0)
    __store64(mx + 24, 0)
    __store64(o + 16, __load64(o + 16) + 1)
    __th_unlock(r)
    __th_notify(r)
    __th_lock(r)
    got := true
    while __load64(o + 24) <= 0:
        seq := __th_seq(r)
        __th_unlock(r)
        ok := __th_wait(r, seq, end)
        __th_lock(r)
        if not ok and __load64(o + 24) <= 0:
            got = false
            break
    if got:
        __store64(o + 24, __load64(o + 24) - 1)
    __store64(o + 16, __load64(o + 16) - 1)
    __store64(mx + 32, __load64(mx + 32) + 1)
    while __load64(mx + 16) != 0:
        seq := __th_seq(r)
        __th_unlock(r)
        __th_wait(r, seq, -1.0)
        __th_lock(r)
    __store64(mx + 32, __load64(mx + 32) - 1)
    __store64(mx + 16, me)
    __store64(mx + 24, level)
    __th_unlock(r)
    if got:
        return __dyn_int(1)
    return __dyn_int(0)

func __nat__native_sync__cond_notify(n: int, a: int, b: int) -> int:
    __nat_range("cond_notify", n, 2, 2)
    o := __sy_get("cond_notify", a, 7)
    k := __nat_int("cond_notify", b, "le nombre")
    mx := __load64(o + 8)
    r := __th_region()
    __th_lock(r)
    if __load64(mx + 16) != __sy_token():
        __th_unlock(r)
        return __dyn_int(-1)
    free := __load64(o + 16) - __load64(o + 24)
    m := free
    if k >= 0 and k < free:
        m = k
    if m < 0:
        m = 0
    __store64(o + 24, __load64(o + 24) + m)
    __th_unlock(r)
    if m > 0:
        __th_notify(r)
    return __dyn_int(m)

# ---- barrière : [8] participants [16] arrivés [24] génération [32] cassée ----

func __nat__native_sync__barrier_new(n: int, a: int) -> int:
    __nat_range("barrier_new", n, 1, 1)
    k := __nat_int("barrier_new", a, "le nombre de participants")
    if k < 1:
        __dyn_err("ArgumentError", "'barrier_new' : au moins 1 participant")
    return __sy_create(8, k, 0, 0)

func __nat__native_sync__barrier_wait(n: int, a: int, b: int) -> int:
    __nat_range("barrier_wait", n, 2, 2)
    o := __sy_get("barrier_wait", a, 8)
    end := __nat_deadline(__nat_timeout("barrier_wait", b))
    r := __th_region()
    __th_lock(r)
    if __load64(o + 32) != 0:
        __th_unlock(r)
        return __dyn_int(-2)
    gen := __load64(o + 24)
    rank := __load64(o + 16)
    __store64(o + 16, rank + 1)
    if rank + 1 == __load64(o + 8):
        __store64(o + 16, 0)
        __store64(o + 24, gen + 1)
        __th_unlock(r)
        __th_notify(r)
        return __dyn_int(rank)
    while __load64(o + 24) == gen and __load64(o + 32) == 0:
        seq := __th_seq(r)
        __th_unlock(r)
        ok := __th_wait(r, seq, end)
        __th_lock(r)
        if not ok and __load64(o + 24) == gen and __load64(o + 32) == 0:
            __store64(o + 32, 1)
            __th_unlock(r)
            __th_notify(r)
            return __dyn_int(-1)
    if __load64(o + 24) != gen:
        __th_unlock(r)
        return __dyn_int(rank)
    __th_unlock(r)
    return __dyn_int(-2)

func __nat__native_sync__barrier_reset(n: int, a: int) -> int:
    __nat_range("barrier_reset", n, 1, 1)
    o := __sy_get("barrier_reset", a, 8)
    r := __th_region()
    __th_lock(r)
    if __load64(o + 16) > 0:
        __store64(o + 32, 1)
    __th_unlock(r)
    __th_notify(r)
    __th_lock(r)
    __store64(o + 16, 0)
    __store64(o + 32, 0)
    __store64(o + 24, __load64(o + 24) + 1)
    __th_unlock(r)
    return 0

func __nat__native_sync__barrier_abort(n: int, a: int) -> int:
    __nat_range("barrier_abort", n, 1, 1)
    o := __sy_get("barrier_abort", a, 8)
    r := __th_region()
    __th_lock(r)
    __store64(o + 32, 1)
    __th_unlock(r)
    __th_notify(r)
    return 0

func __nat__native_sync__barrier_info(n: int, a: int) -> int:
    __nat_range("barrier_info", n, 1, 1)
    o := __sy_get("barrier_info", a, 8)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__load64(o + 8)))
    __dyn_list_push(l, __dyn_int(__load64(o + 16)))
    __dyn_list_push(l, __dyn_bool(__load64(o + 32) != 0))
    __dyn_list_push(l, __dyn_int(__load64(o + 24)))
    return l

# ---- loquet : [8] compte ----

func __nat__native_sync__latch_new(n: int, a: int) -> int:
    __nat_range("latch_new", n, 1, 1)
    k := __nat_int("latch_new", a, "le compte")
    if k < 0:
        __dyn_err("ArgumentError", "'latch_new' : compte >= 0 attendu")
    return __sy_create(9, k, 0, 0)

func __nat__native_sync__latch_count_down(n: int, a: int, b: int) -> int:
    __nat_range("latch_count_down", n, 2, 2)
    o := __sy_get("latch_count_down", a, 9)
    k := __nat_int("latch_count_down", b, "le nombre")
    if k < 1:
        __dyn_err("ArgumentError", "'latch_count_down' : nombre >= 1 attendu")
    r := __th_region()
    __th_lock(r)
    c := __load64(o + 8) - k
    if c < 0:
        c = 0
    __store64(o + 8, c)
    __th_unlock(r)
    if c == 0:
        __th_notify(r)
    return __dyn_int(c)

func __nat__native_sync__latch_wait(n: int, a: int, b: int) -> int:
    __nat_range("latch_wait", n, 2, 2)
    o := __sy_get("latch_wait", a, 9)
    end := __nat_deadline(__nat_timeout("latch_wait", b))
    r := __th_region()
    while true:
        seq := __th_seq(r)
        if __load64(o + 8) == 0:
            return __dyn_int(1)
        if not __th_wait(r, seq, end):
            if __load64(o + 8) == 0:
                return __dyn_int(1)
            return __dyn_int(0)
    return 0

func __nat__native_sync__latch_count(n: int, a: int) -> int:
    __nat_range("latch_count", n, 1, 1)
    return __dyn_int(__load64(__sy_get("latch_count", a, 9) + 8))

# ---- exécution unique : [8] état (0 jamais, 1 en cours, 2 fait) ----

func __nat__native_sync__once_new(n: int) -> int:
    __nat_range("once_new", n, 0, 0)
    return __sy_create(10, 0, 0, 0)

func __nat__native_sync__once_enter(n: int, a: int, b: int) -> int:
    __nat_range("once_enter", n, 2, 2)
    o := __sy_get("once_enter", a, 10)
    end := __nat_deadline(__nat_timeout("once_enter", b))
    r := __th_region()
    __th_lock(r)
    while __load64(o + 8) == 1:
        seq := __th_seq(r)
        __th_unlock(r)
        ok := __th_wait(r, seq, end)
        __th_lock(r)
        if not ok and __load64(o + 8) == 1:
            __th_unlock(r)
            return __dyn_int(-1)
    if __load64(o + 8) == 2:
        __th_unlock(r)
        return __dyn_int(0)
    __store64(o + 8, 1)
    __th_unlock(r)
    return __dyn_int(1)

func __nat__native_sync__once_leave(n: int, a: int, b: int) -> int:
    __nat_range("once_leave", n, 2, 2)
    o := __sy_get("once_leave", a, 10)
    ok := __nat_bool("once_leave", b, "réussi")
    r := __th_region()
    __th_lock(r)
    if ok:
        __store64(o + 8, 2)
    else:
        __store64(o + 8, 0)
    __th_unlock(r)
    __th_notify(r)
    return 0

func __nat__native_sync__once_state(n: int, a: int) -> int:
    __nat_range("once_state", n, 1, 1)
    return __dyn_int(__load64(__sy_get("once_state", a, 10) + 8))

# ---- événement : [8] levé [16] génération ----

func __nat__native_sync__event_new(n: int, a: int) -> int:
    __nat_range("event_new", n, 1, 1)
    v := 0
    if __nat_bool("event_new", a, "levé"):
        v = 1
    return __sy_create(11, v, 0, 0)

func __nat__native_sync__event_set(n: int, a: int) -> int:
    __nat_range("event_set", n, 1, 1)
    o := __sy_get("event_set", a, 11)
    r := __th_region()
    __th_lock(r)
    __store64(o + 8, 1)
    __store64(o + 16, __load64(o + 16) + 1)
    __th_unlock(r)
    __th_notify(r)
    return 0

func __nat__native_sync__event_clear(n: int, a: int) -> int:
    __nat_range("event_clear", n, 1, 1)
    o := __sy_get("event_clear", a, 11)
    __store64(o + 8, 0)
    return 0

func __nat__native_sync__event_wait(n: int, a: int, b: int) -> int:
    __nat_range("event_wait", n, 2, 2)
    o := __sy_get("event_wait", a, 11)
    end := __nat_deadline(__nat_timeout("event_wait", b))
    r := __th_region()
    gen := __load64(o + 16)
    while true:
        seq := __th_seq(r)
        if __load64(o + 8) != 0 or __load64(o + 16) != gen:
            return __dyn_int(1)
        if not __th_wait(r, seq, end):
            if __load64(o + 8) != 0 or __load64(o + 16) != gen:
                return __dyn_int(1)
            return __dyn_int(0)
    return 0

func __nat__native_sync__event_is_set(n: int, a: int) -> int:
    __nat_range("event_is_set", n, 1, 1)
    return __dyn_bool(__load64(__sy_get("event_is_set", a, 11) + 8) != 0)

# ---- _native_sync : objets du système (mémoire partagée, files de messages, sémaphores nommés) -----------------------
# Tables (état du mode dynamique) : [168] mémoires partagées (handle -> [adresse][taille][nom]), [176] files (handle ->
# descripteur), [184] sémaphores (handle -> adresse du sem_t), [192] prochain handle.

func __ipc_table(off: int) -> int:
    ds := __dyn_ds()
    t := __load64(ds + off)
    if t == 0:
        t = __rt_dict_new(4)
        __store64(ds + off, t)
        if __load64(ds + 192) == 0:
            __store64(ds + 192, 1)
    return t

func __ipc_put(off: int, v: int) -> int:
    t := __ipc_table(off)
    h := __load64(__dyn_ds() + 192)
    __store64(__dyn_ds() + 192, h + 1)
    __rt_dict_set(t, h, v, 0)
    return h

func __ipc_get(off: int, fn: str, v: int, what: str) -> int:
    h := __nat_int(fn, v, "le handle")
    t := __ipc_table(off)
    e := __rt_dict_index(t, h, 0)
    if e < 0:
        __dyn_err("ArgumentError", "'" + fn + "' : " + what + " inconnue ou fermée (" + __int_to_str(h) + ")")
    return __load64(__load64(t + 32) + 8 * e)

func __ipc_name(fn: str, v: int) -> str:
    n := __nat_cstr(fn, v, "le nom")
    m := __nat_blen(n)
    if m == 0 or m > 250 or __dyn_find_bytes(n, "/", 1) >= 0:
        __dyn_err("ArgumentError", "'" + fn + "' : nom invalide (1 à 250 caractères, sans '/') : '" + n + "'")
    if __load8(__nat_bp(n)) == 47:
        return n
    return "/" + n

func __ipc_flags(fn: str, v: int) -> int:
    m := __nat_cstr(fn, v, "le mode")
    if __rt_str_eq(m, "create"):
        return 64 | 128
    if __rt_str_eq(m, "open"):
        return 0
    if __rt_str_eq(m, "open_or_create"):
        return 64
    __dyn_err("ArgumentError", "'" + fn + "' : mode \"create\", \"open\" ou \"open_or_create\" attendu")
    return 0

func __nat__native_sync__supported_ipc(n: int) -> int:
    __nat_range("supported_ipc", n, 0, 0)
    return __dyn_bool(not __windows())

func __nat__native_sync__shm_open(n: int, a: int, b: int, c: int) -> int:
    __ipc_win_off()
    __nat_range("shm_open", n, 3, 3)
    name := __ipc_name("shm_open", a)
    size := __nat_int("shm_open", b, "la taille")
    flags := __ipc_flags("shm_open", c)
    if size < 0:
        __dyn_err("ArgumentError", "'shm_open' : taille >= 0 attendue")
    fd := __syscall(2, __nat_c("/dev/shm" + name), flags | 2 | 524288 | 131072, 384)
    if fd < 0:
        return __dyn_int(fd)
    st := __alloc_raw(144)
    r := __syscall(5, fd, st)
    if r != 0:
        __syscall(3, fd)
        return __dyn_int(r)
    cur := __load64(st + 48)
    if cur < size:
        r = __syscall(77, fd, size)
        if r != 0:
            __syscall(3, fd)
            return __dyn_int(r)
        cur = size
    if cur == 0:
        __syscall(3, fd)
        return __dyn_int(-22)
    p := __syscall(9, 0, cur, 3, 1, fd, 0)
    __syscall(3, fd)
    if p < 0 and p > -4096:
        return __dyn_int(p)
    rec := __alloc(24)
    __store64(rec, p)
    __store64(rec + 8, cur)
    __store64(rec + 16, __str_addr(name))
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__ipc_put(168, rec)))
    __dyn_list_push(l, __dyn_int(cur))
    return l

func __nat__native_sync__shm_close(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("shm_close", n, 1, 1)
    h := __nat_int("shm_close", a, "le handle")
    t := __ipc_table(168)
    e := __rt_dict_index(t, h, 0)
    if e < 0:
        return __dyn_bool(false)
    rec := __load64(__load64(t + 32) + 8 * e)
    __munmap(__load64(rec), __load64(rec + 8))
    __rt_dict_remove(t, h, 0)
    return __dyn_bool(true)

func __nat__native_sync__shm_unlink(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("shm_unlink", n, 1, 1)
    name := __ipc_name("shm_unlink", a)
    r := __syscall(87, __nat_c("/dev/shm" + name))
    if r == 0:
        return __dyn_int(0)
    return __dyn_int(r)

func __shm(fn: str, v: int) -> int:
    return __ipc_get(168, fn, v, "mémoire partagée")

func __nat__native_sync__shm_size(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("shm_size", n, 1, 1)
    return __dyn_int(__load64(__shm("shm_size", a) + 8))

func __nat__native_sync__shm_name(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("shm_name", n, 1, 1)
    return __dyn_str(__as_str(__load64(__shm("shm_name", a) + 16)))

func __shm_range(fn: str, rec: int, pos: int, k: int) -> int:
    p := __nat_int(fn, pos, "la position")
    if p < 0 or k < 0 or p + k > __load64(rec + 8):
        __dyn_err("IndexError", "'" + fn + "' : zone [" + __int_to_str(p) + ", " + __int_to_str(p + k) +
                  ") hors de la mémoire partagée (" + __int_to_str(__load64(rec + 8)) + " octets)")
    return __load64(rec) + p

func __nat__native_sync__shm_read(n: int, a: int, b: int, c: int) -> int:
    __ipc_win_off()
    __nat_range("shm_read", n, 3, 3)
    rec := __shm("shm_read", a)
    k := __nat_int("shm_read", c, "la longueur")
    q := __shm_range("shm_read", rec, b, k)
    return __dyn_str(__nat_make(q, k))

func __nat__native_sync__shm_write(n: int, a: int, b: int, c: int) -> int:
    __ipc_win_off()
    __nat_range("shm_write", n, 3, 3)
    rec := __shm("shm_write", a)
    data := __nat_str("shm_write", c, "les octets")
    q := __shm_range("shm_write", rec, b, __nat_blen(data))
    __copy(q, __nat_bp(data), __nat_blen(data))
    return __dyn_int(__nat_blen(data))

func __shm_tsize(fn: str, t: str) -> int:
    if __rt_str_eq(t, "i8") or __rt_str_eq(t, "u8"):
        return 1
    if __rt_str_eq(t, "i16") or __rt_str_eq(t, "u16"):
        return 2
    if __rt_str_eq(t, "i32") or __rt_str_eq(t, "u32") or __rt_str_eq(t, "f32"):
        return 4
    if __rt_str_eq(t, "i64") or __rt_str_eq(t, "f64"):
        return 8
    __dyn_err("ArgumentError", "'" + fn + "' : type inconnu '" + t + "' (i8 u8 i16 u16 i32 u32 i64 f32 f64)")
    return 0

func __sx(v: int, bits: int) -> int: # extension de signe
    sh := 64 - bits
    return (v << sh) >> sh

func __nat__native_sync__shm_get(n: int, a: int, b: int, c: int) -> int:
    __ipc_win_off()
    __nat_range("shm_get", n, 3, 3)
    rec := __shm("shm_get", a)
    t := __nat_cstr("shm_get", c, "le type")
    k := __shm_tsize("shm_get", t)
    q := __shm_range("shm_get", rec, b, k)
    if __rt_str_eq(t, "i8"):
        return __dyn_int(__sx(__load8(q), 8))
    if __rt_str_eq(t, "u8"):
        return __dyn_int(__load8(q))
    if __rt_str_eq(t, "i16"):
        return __dyn_int(__sx(__load16(q), 16))
    if __rt_str_eq(t, "u16"):
        return __dyn_int(__load16(q))
    if __rt_str_eq(t, "i32"):
        return __dyn_int(__sx(__load32(q), 32))
    if __rt_str_eq(t, "u32"):
        return __dyn_int(__load32(q))
    if __rt_str_eq(t, "f32"):
        return __dyn_float(__nat_f32_value(__load32(q)))
    if __rt_str_eq(t, "f64"):
        return __dyn_float(__bits2f(__load64(q)))
    return __dyn_int(__load64(q))

func __nat__native_sync__shm_set(n: int, a: int, b: int, c: int, d: int) -> int:
    __ipc_win_off()
    __nat_range("shm_set", n, 4, 4)
    rec := __shm("shm_set", a)
    t := __nat_cstr("shm_set", c, "le type")
    k := __shm_tsize("shm_set", t)
    q := __shm_range("shm_set", rec, b, k)
    if __rt_str_eq(t, "f32"):
        __store32(q, __nat_f32_bits(__nat_number("shm_set", d, "la valeur")))
        return 0
    if __rt_str_eq(t, "f64"):
        __store64(q, __f2bits(__nat_number("shm_set", d, "la valeur")))
        return 0
    v := __nat_int("shm_set", d, "la valeur")
    i := 0
    while i < k:
        __store8(q + i, (v >> (8 * i)) & 255)
        i += 1
    return 0

# Opération atomique 64 bits (32 bits : sur le mot de 8 octets aligné qui le contient).
func __shm_cas32(q: int, expected: int, desired: int) -> int: # renvoie l'ancienne valeur 32 bits
    base := q - (q & 7)
    sh := 8 * (q & 7)
    while true:
        w := __load64(base)
        cur := (w >> sh) & 4294967295
        if cur != (expected & 4294967295):
            return cur
        nw := (w & ~(4294967295 << sh)) | ((desired & 4294967295) << sh)
        if __cas(base, w, nw) == w:
            return cur
    return 0

func __nat__native_sync__shm_atomic(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                    a7: int, x: int) -> int:
    __ipc_win_off()
    __nat_range("shm_atomic", n, 6, 6)
    rec := __shm("shm_atomic", a0)
    width := __nat_int("shm_atomic", a2, "la largeur")
    op := __nat_cstr("shm_atomic", a3, "l'opération")
    v := 0
    if a4 != 0:
        v = __nat_int("shm_atomic", a4, "la valeur")
    v2 := 0
    if a5 != 0:
        v2 = __nat_int("shm_atomic", a5, "la seconde valeur")
    if width != 32 and width != 64:
        __dyn_err("ArgumentError", "'shm_atomic' : largeur 32 ou 64 attendue")
    q := __shm_range("shm_atomic", rec, a1, width // 8)
    if (q - __load64(rec)) % (width // 8) != 0:
        __dyn_err("ArgumentError", "'shm_atomic' : position non alignée sur " + __int_to_str(width // 8) + " octets")
    codes := __nat_split_bytes("load,store,exchange,add,sub,and,or,xor,cas", 44)
    code := 0
    i := 0
    while i < 9:
        if __rt_str_eq(__as_str(__rt_vec_at(codes, i)), op):
            code = i + 1
        i += 1
    if code == 0:
        __dyn_err("ArgumentError", "'shm_atomic' : opération inconnue '" + op + "'")
    while true:
        old := 0
        if width == 64:
            old = __load64(q)
        else:
            old = __load32(q)
        nv := old
        if code == 1:
            return __dyn_int(__shm_result(old, width))
        if code == 2 or code == 3:
            nv = v
        elif code == 4:
            nv = old + v
        elif code == 5:
            nv = old - v
        elif code == 6:
            nv = old & v
        elif code == 7:
            nv = old | v
        elif code == 8:
            nv = old ^ v
        else:
            if (old & 4294967295) != (v & 4294967295) and width == 32:
                return __dyn_int(__shm_result(old, width))
            if old != v and width == 64:
                return __dyn_int(old)
            nv = v2
        got := 0
        if width == 64:
            got = __cas(q, old, nv)
        else:
            got = __shm_cas32(q, old, nv)
        if got == old:
            return __dyn_int(__shm_result(old, width))
    return 0

func __shm_result(old: int, width: int) -> int:
    if width == 32:
        return __sx(old, 32)
    return old

func __nat__native_sync__shm_wait(n: int, a: int, b: int, c: int, d: int) -> int:
    __ipc_win_off()
    __nat_range("shm_wait", n, 4, 4)
    rec := __shm("shm_wait", a)
    q := __shm_range("shm_wait", rec, b, 4)
    if (q - __load64(rec)) % 4 != 0:
        __dyn_err("ArgumentError", "'shm_wait' : position non alignée sur 4 octets")
    expected := __nat_int("shm_wait", c, "la valeur attendue") & 4294967295
    end := __nat_deadline(__nat_timeout("shm_wait", d))
    ts := __alloc_raw(16)
    while true:
        if __load32(q) != expected:
            return __dyn_int(1)
        tp := 0
        if end >= 0.0:
            left := end - __nat_clock(1)
            if left <= 0.0:
                return __dyn_int(0)
            __store64(ts, __f2i(left))
            __store64(ts + 8, __f2i((left - __rt_floor(left)) * 1000000000.0))
            tp = ts
        r := __syscall(202, q, 0, expected, tp, 0, 0)
        if r == 0 or r == -11:
            return __dyn_int(1)
        if r == -110:
            return __dyn_int(0)
        if r != -4:
            return __dyn_int(r)
    return 0

func __nat__native_sync__shm_wake(n: int, a: int, b: int, c: int) -> int:
    __ipc_win_off()
    __nat_range("shm_wake", n, 3, 3)
    rec := __shm("shm_wake", a)
    q := __shm_range("shm_wake", rec, b, 4)
    k := __nat_int("shm_wake", c, "le nombre")
    if k < 0 or k > 2147483647:
        k = 2147483647
    r := __syscall(202, q, 1, k, 0, 0, 0)
    if r < 0:
        return __dyn_int(0)
    return __dyn_int(r)

# ---- files de messages POSIX ----

func __mq(fn: str, v: int) -> int:
    return __ipc_get(176, fn, v, "file de messages")

func __mq_mqname(name: str) -> int: # nom sans « / » initial (comme la glibc)
    return __nat_c(__nat_sub(name, 1, __nat_blen(name) - 1))

func __mq_attr(fd: int) -> int:
    at := __alloc_raw(64)
    __zero(at, 64)
    __syscall(245, fd, 0, at)
    return at

func __mq_set_block(fd: int, block: bool):
    at := __alloc_raw(64)
    __zero(at, 64)
    if not block:
        __store64(at, 2048)
    __syscall(245, fd, at, 0)

func __mq_abs(t: float) -> int: # échéance absolue (CLOCK_REALTIME)
    ts := __alloc_raw(16)
    __syscall(228, 0, ts)
    ns := __f2i(t * 1000000000.0) + __load64(ts + 8)
    __store64(ts, __load64(ts) + ns // 1000000000)
    __store64(ts + 8, ns % 1000000000)
    return ts

func __nat__native_sync__mq_supported(n: int) -> int:
    if __windows():
        return __dyn_bool(false)
    __nat_range("mq_supported", n, 0, 0)
    fd := __syscall(240, __nat_c("alex_probe_mq"), 64 | 524288, 384, 0)
    if fd < 0:
        return __dyn_bool(false)
    __syscall(3, fd)
    __syscall(241, __nat_c("alex_probe_mq"))
    return __dyn_bool(true)

func __nat__native_sync__mq_open(n: int, a: int, b: int, c: int, d: int) -> int:
    __ipc_win_off()
    __nat_range("mq_open", n, 4, 4)
    name := __ipc_name("mq_open", a)
    flags := __ipc_flags("mq_open", b)
    maxmsg := __nat_int("mq_open", c, "le nombre maximal de messages")
    msgsize := __nat_int("mq_open", d, "la taille maximale d'un message")
    at := 0
    if (flags & 64) != 0:
        at = __alloc_raw(64)
        __zero(at, 64)
        __store64(at + 8, maxmsg)
        __store64(at + 16, msgsize)
    fd := __syscall(240, __mq_mqname(name), flags | 2 | 524288 | 2048, 384, at)
    if fd < 0:
        return __dyn_int(fd)
    return __dyn_int(__ipc_put(176, fd))

func __nat__native_sync__mq_send(n: int, a: int, b: int, c: int, d: int) -> int:
    __ipc_win_off()
    __nat_range("mq_send", n, 4, 4)
    fd := __mq("mq_send", a)
    data := __nat_str("mq_send", b, "les octets")
    prio := __nat_int("mq_send", c, "la priorité")
    t := __nat_timeout("mq_send", d)
    if prio < 0 or prio > 31:
        __dyn_err("ArgumentError", "'mq_send' : priorité hors de 0..31")
    while true:
        r := 0
        if t >= 0.0 and t <= 0.0:
            r = __syscall(242, fd, __nat_bp(data), __nat_blen(data), prio, 0)
            if r == -11:
                return __dyn_int(0)
        else:
            __mq_set_block(fd, true)
            ts := 0
            if t > 0.0:
                ts = __mq_abs(t)
            r = __syscall(242, fd, __nat_bp(data), __nat_blen(data), prio, ts)
            __mq_set_block(fd, false)
            if r == -110:
                return __dyn_int(0)
        if r == 0:
            return __dyn_int(1)
        if r != -4:
            return __dyn_int(r)
    return 0

func __nat__native_sync__mq_receive(n: int, a: int, b: int) -> int:
    __ipc_win_off()
    __nat_range("mq_receive", n, 2, 2)
    fd := __mq("mq_receive", a)
    t := __nat_timeout("mq_receive", b)
    size := __load64(__mq_attr(fd) + 16)
    buf := __alloc_raw(size + 8)
    pr := __alloc_raw(8)
    while true:
        __store64(pr, 0)
        k := 0
        if t >= 0.0 and t <= 0.0:
            k = __syscall(243, fd, buf, size, pr, 0)
            if k == -11:
                return __dyn_int(0)
        else:
            __mq_set_block(fd, true)
            ts := 0
            if t > 0.0:
                ts = __mq_abs(t)
            k = __syscall(243, fd, buf, size, pr, ts)
            __mq_set_block(fd, false)
            if k == -110:
                return __dyn_int(0)
        if k >= 0:
            l := __dyn_list_new(0)
            __dyn_list_push(l, __dyn_str(__nat_make(buf, k)))
            __dyn_list_push(l, __dyn_int(__load32(pr)))
            return l
        if k != -4:
            return __dyn_int(k)
    return 0

func __nat__native_sync__mq_attr(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("mq_attr", n, 1, 1)
    at := __mq_attr(__mq("mq_attr", a))
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__load64(at + 8)))
    __dyn_list_push(l, __dyn_int(__load64(at + 16)))
    __dyn_list_push(l, __dyn_int(__load64(at + 24)))
    return l

func __nat__native_sync__mq_close(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("mq_close", n, 1, 1)
    h := __nat_int("mq_close", a, "le handle")
    t := __ipc_table(176)
    e := __rt_dict_index(t, h, 0)
    if e < 0:
        return __dyn_bool(false)
    __syscall(3, __load64(__load64(t + 32) + 8 * e))
    __rt_dict_remove(t, h, 0)
    return __dyn_bool(true)

func __nat__native_sync__mq_unlink(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("mq_unlink", n, 1, 1)
    name := __ipc_name("mq_unlink", a)
    r := __syscall(241, __mq_mqname(name))
    if r == 0:
        return __dyn_int(0)
    return __dyn_int(r)

# ---- sémaphores nommés : /dev/shm/sem.NOM, sem_t de la glibc (valeur : 32 bits bas, attentes : 32 bits hauts) ----

func __nsem(fn: str, v: int) -> int:
    return __ipc_get(184, fn, v, "sémaphore nommé")

func __nat__native_sync__nsem_open(n: int, a: int, b: int, c: int) -> int:
    __ipc_win_off()
    __nat_range("nsem_open", n, 3, 3)
    name := __ipc_name("nsem_open", a)
    flags := __ipc_flags("nsem_open", b)
    value := __nat_int("nsem_open", c, "la valeur")
    if value < 0:
        __dyn_err("ArgumentError", "'nsem_open' : valeur >= 0 attendue")
    path := "/dev/shm/sem." + __nat_sub(name, 1, __nat_blen(name) - 1)
    created := false
    fd := -2
    if (flags & 64) != 0:
        fd = __syscall(2, __nat_c(path), 2 | 64 | 128 | 524288, 384)
        if fd >= 0:
            created = true
        elif fd != -17 or (flags & 128) != 0:
            return __dyn_int(fd)
    if not created:
        fd = __syscall(2, __nat_c(path), 2 | 524288, 0)
        if fd < 0:
            return __dyn_int(fd)
    if created:
        init := __alloc_raw(32)
        __zero(init, 32)
        __store64(init, value)
        __store32(init + 8, 0) # partagé entre processus (comme sem_open)
        __syscall(1, fd, init, 32)
    p := __syscall(9, 0, 32, 3, 1, fd, 0)
    __syscall(3, fd)
    if p < 0 and p > -4096:
        return __dyn_int(p)
    return __dyn_int(__ipc_put(184, p))

func __nat__native_sync__nsem_wait(n: int, a: int, b: int) -> int:
    __ipc_win_off()
    __nat_range("nsem_wait", n, 2, 2)
    s := __nsem("nsem_wait", a)
    t := __nat_timeout("nsem_wait", b)
    end := __nat_deadline(t)
    ts := __alloc_raw(16)
    while true:
        w := __load64(s)
        if (w & 4294967295) > 0:
            if __cas(s, w, w - 1) == w:
                return __dyn_int(1)
            continue
        if t >= 0.0 and t <= 0.0:
            return __dyn_int(0)
        tp := 0
        if end >= 0.0:
            left := end - __nat_clock(1)
            if left <= 0.0:
                return __dyn_int(0)
            __store64(ts, __f2i(left))
            __store64(ts + 8, __f2i((left - __rt_floor(left)) * 1000000000.0))
            tp = ts
        __xadd(s, 4294967296)
        r := __syscall(202, s, 0, 0, tp, 0, 0)
        __xadd(s, -4294967296)
        if r == -110:
            return __dyn_int(0)
    return 0

func __nat__native_sync__nsem_post(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("nsem_post", n, 1, 1)
    s := __nsem("nsem_post", a)
    old := __xadd(s, 1)
    if (old >> 32) > 0:
        __syscall(202, s, 1, 1, 0, 0, 0)
    return __dyn_int(0)

func __nat__native_sync__nsem_value(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("nsem_value", n, 1, 1)
    return __dyn_int(__load64(__nsem("nsem_value", a)) & 2147483647)

func __nat__native_sync__nsem_close(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("nsem_close", n, 1, 1)
    h := __nat_int("nsem_close", a, "le handle")
    t := __ipc_table(184)
    e := __rt_dict_index(t, h, 0)
    if e < 0:
        return __dyn_bool(false)
    __munmap(__load64(__load64(t + 32) + 8 * e), 32)
    __rt_dict_remove(t, h, 0)
    return __dyn_bool(true)

func __nat__native_sync__nsem_unlink(n: int, a: int) -> int:
    __ipc_win_off()
    __nat_range("nsem_unlink", n, 1, 1)
    name := __ipc_name("nsem_unlink", a)
    r := __syscall(87, __nat_c("/dev/shm/sem." + __nat_sub(name, 1, __nat_blen(name) - 1)))
    if r == 0:
        return __dyn_int(0)
    return __dyn_int(r)

# Windows : pas d'objets système nommés, comme la VM C++ (sync_native.cpp).
func __ipc_win_off():
    if __windows():
        __dyn_err("IoError", "ipc : mémoire partagée, files et sémaphores nommés indisponibles sur cette plateforme")

func __nat__native_sync__strerror(n: int, a: int) -> int:
    if __windows():
        __nat_range("strerror", n, 1, 1)
        return __dyn_str("erreur " + __int_to_str(__nat_int("strerror", a, "le code")))
    return __nat_strerror_impl(n, a)

func __nat__native_sync__errno_name(n: int, a: int) -> int:
    if __windows():
        __nat_range("strerror", n, 1, 1)
        return __dyn_str("erreur " + __int_to_str(__nat_int("strerror", a, "le code")))
    __nat_range("errno_name", n, 1, 1)
    c := __nat_int("errno_name", a, "le code")
    if c < 0:
        c = 0 - c
    t := __nat_split_bytes("17:EEXIST,2:ENOENT,13:EACCES,22:EINVAL,11:EAGAIN,110:ETIMEDOUT,38:ENOSYS,90:EMSGSIZE,36:ENAMETOOLONG,24:EMFILE,12:ENOMEM,28:ENOSPC,1:EPERM,9:EBADF", 44)
    i := 0
    while i < __load64(t):
        it := __as_str(__rt_vec_at(t, i))
        q := __dyn_find_bytes(it, ":", 0)
        if __rt_str_eq(__nat_sub(it, 0, q), __int_to_str(c)):
            return __dyn_str(__nat_sub(it, q + 1, __nat_blen(it) - q - 1))
        i += 1
    return __dyn_str("E" + __int_to_str(c))

# ---- _native_ffi : indisponible dans un exécutable natif statique (pas de chargeur de bibliothèques) ---------------

func __ffi_off(fn: str):
    __dyn_err("IoError", fn + " : ffi n'est pas supporté sur cette plateforme (x86-64/arm64 POSIX requis)")

func __nat__native_ffi__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    return __dyn_bool(false)

func __nat__native_ffi__type_size(n: int, a: int) -> int:
    __nat_range("type_size", n, 1, 1)
    t := __nat_cstr("type_size", a, "le type")
    tab := __nat_split_bytes("void:0,bool:1,i8:1,int8:1,u8:1,uint8:1,byte:1,i16:2,short:2,u16:2,ushort:2,i32:4,int:4,u32:4,uint:4,i64:8,long:8,longlong:8,ssize_t:8,isize:8,u64:8,ulong:8,size_t:8,usize:8,f32:4,float:4,f64:8,double:8,ptr:8,pointer:8,void*:8,cstr:8,char*:8,string:8", 44)
    i := 0
    while i < __load64(tab):
        it := __as_str(__rt_vec_at(tab, i))
        q := __dyn_find_bytes(it, ":", 0)
        if __rt_str_eq(__nat_sub(it, 0, q), t):
            return __dyn_int(__rt_str_to_int(__nat_sub(it, q + 1, __nat_blen(it) - q - 1)))
        i += 1
    __dyn_err("ArgumentError", "'type_size' : type FFI inconnu '" + t + "'")
    return 0

func __nat__native_ffi__live_counts(n: int) -> int:
    __nat_range("live_counts", n, 0, 0)
    d := __dyn_dict_new()
    __nat_dict_put(d, "libraries", __dyn_int(0))
    __nat_dict_put(d, "functions", __dyn_int(0))
    __nat_dict_put(d, "buffers", __dyn_int(0))
    return d

func __nat__native_ffi__bind_addr(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("bind_addr", n, 4, 4)
    __ffi_off("bind_addr")
    return 0

func __nat__native_ffi__buf_copy(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("buf_copy", n, 5, 5)
    __ffi_off("buf_copy")
    return 0

func __nat__native_ffi__buf_read_array(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("buf_read_array", n, 4, 4)
    __ffi_off("buf_read_array")
    return 0

func __nat__native_ffi__buf_write_array(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("buf_write_array", n, 4, 4)
    __ffi_off("buf_write_array")
    return 0

func __nat__native_ffi__ptr_read(n: int, a0: int, a1: int) -> int:
    __nat_range("ptr_read", n, 2, 2)
    __ffi_off("ptr_read")
    return 0

func __nat__native_ffi__ptr_read_bytes(n: int, a0: int, a1: int) -> int:
    __nat_range("ptr_read_bytes", n, 2, 2)
    __ffi_off("ptr_read_bytes")
    return 0

func __nat__native_ffi__ptr_write(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("ptr_write", n, 3, 3)
    __ffi_off("ptr_write")
    return 0

func __nat__native_ffi__symbol_address(n: int, a0: int, a1: int) -> int:
    __nat_range("symbol_address", n, 2, 2)
    __ffi_off("symbol_address")
    return 0

func __nat__native_ffi__audio_mix(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int) -> int:
    __nat_range("audio_mix", n, 8, 8)
    __ffi_off("audio_mix")
    return 0

func __nat__native_ffi__audio_out(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("audio_out", n, 4, 4)
    __ffi_off("audio_out")
    return 0

func __nat__native_ffi__audio_resample(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("audio_resample", n, 5, 5)
    __ffi_off("audio_resample")
    return 0

func __nat__native_ffi__audio_imdct(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("audio_imdct", n, 5, 5)
    __ffi_off("audio_imdct")
    return 0

func __nat__native_ffi__audio_vcouple(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("audio_vcouple", n, 3, 3)
    __ffi_off("audio_vcouple")
    return 0

func __nat__native_ffi__audio_vfloor(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("audio_vfloor", n, 5, 5)
    __ffi_off("audio_vfloor")
    return 0

func __nat__native_ffi__audio_vwindow(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int) -> int:
    __nat_range("audio_vwindow", n, 8, 8)
    __ffi_off("audio_vwindow")
    return 0

func __nat__native_ffi__audio_voverlap(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int) -> int:
    __nat_range("audio_voverlap", n, 8, 8)
    __ffi_off("audio_voverlap")
    return 0

func __nat__native_ffi__anim_skin(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int) -> int:
    __nat_range("anim_skin", n, 8, 8)
    __ffi_off("anim_skin")
    return 0

func __nat__native_ffi__jpeg_idct(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int) -> int:
    __nat_range("jpeg_idct", n, 8, 8)
    __ffi_off("jpeg_idct")
    return 0

func __nat__native_ffi__jpeg_color(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int) -> int:
    __nat_range("jpeg_color", n, 8, 8)
    __ffi_off("jpeg_color")
    return 0

func __nat__native_ffi__jpeg_scan(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("jpeg_scan", n, 4, 4)
    __ffi_off("jpeg_scan")
    return 0

func __nat__native_ffi__anim_sample(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("anim_sample", n, 5, 5)
    __ffi_off("anim_sample")
    return 0

func __nat__native_ffi__anim_resolve(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("anim_resolve", n, 4, 4)
    __ffi_off("anim_resolve")
    return 0

func __nat__native_ffi__anim_additive(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int) -> int:
    __nat_range("anim_additive", n, 6, 6)
    __ffi_off("anim_additive")
    return 0

func __nat__native_ffi__img_orient(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("img_orient", n, 5, 5)
    __ffi_off("img_orient")
    return 0

func __nat__native_ffi__zstd_decompress(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __nat_range("zstd_decompress", n, 5, 5)
    __ffi_off("zstd_decompress")
    return 0

func __nat__native_ffi__load(n: int, a0: int) -> int:
    __nat_range("load", n, 1, 1)
    __ffi_off("load")
    return 0

func __nat__native_ffi__unload(n: int, a0: int) -> int:
    __nat_range("unload", n, 1, 1)
    __ffi_off("unload")
    return 0

func __nat__native_ffi__has_symbol(n: int, a0: int, a1: int) -> int:
    __nat_range("has_symbol", n, 2, 2)
    __ffi_off("has_symbol")
    return 0

func __nat__native_ffi__bind(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("bind", n, 4, 4)
    __ffi_off("bind")
    return 0

func __nat__native_ffi__unbind(n: int, a0: int) -> int:
    __nat_range("unbind", n, 1, 1)
    __ffi_off("unbind")
    return 0

func __nat__native_ffi__call(n: int, a0: int, a1: int) -> int:
    __nat_range("call", n, 2, 2)
    __ffi_off("call")
    return 0

func __nat__native_ffi__buf_alloc(n: int, a0: int) -> int:
    __nat_range("buf_alloc", n, 1, 1)
    __ffi_off("buf_alloc")
    return 0

func __nat__native_ffi__buf_free(n: int, a0: int) -> int:
    __nat_range("buf_free", n, 1, 1)
    __ffi_off("buf_free")
    return 0

func __nat__native_ffi__buf_size(n: int, a0: int) -> int:
    __nat_range("buf_size", n, 1, 1)
    __ffi_off("buf_size")
    return 0

func __nat__native_ffi__buf_address(n: int, a0: int) -> int:
    __nat_range("buf_address", n, 1, 1)
    __ffi_off("buf_address")
    return 0

func __nat__native_ffi__buf_read(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("buf_read", n, 3, 3)
    __ffi_off("buf_read")
    return 0

func __nat__native_ffi__buf_write(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("buf_write", n, 4, 4)
    __ffi_off("buf_write")
    return 0

func __nat__native_ffi__buf_read_bytes(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("buf_read_bytes", n, 3, 3)
    __ffi_off("buf_read_bytes")
    return 0

func __nat__native_ffi__buf_write_bytes(n: int, a0: int, a1: int, a2: int) -> int:
    __nat_range("buf_write_bytes", n, 3, 3)
    __ffi_off("buf_write_bytes")
    return 0

func __nat__native_ffi__buf_fill(n: int, a0: int, a1: int, a2: int, a3: int) -> int:
    __nat_range("buf_fill", n, 4, 4)
    __ffi_off("buf_fill")
    return 0

# ---- net.repr_float : écriture la plus courte qui se relit à l'identique (comme repr de Python) -----------------

# Arrondit (au plus proche, pair en cas d'égalité, sur la valeur exacte) des chiffres [d, nd, x10] à `keep` chiffres
# significatifs ; renvoie un nouveau triplet (tampon de 24 octets).
func __rf_round(d: int, nd: int, x10: int, keep: int) -> int:
    out := __alloc(24) # parcouru par le GC : il retient le tampon des chiffres
    buf := __alloc_raw(nd + keep + 8)
    if keep >= nd:
        __copy(buf, d, nd)
        __store64(out, buf)
        __store64(out + 8, nd)
        __store64(out + 16, x10)
        return out
    __copy(buf, d, keep)
    up := false
    r := __load8(d + keep)
    if r > 5:
        up = true
    elif r == 5:
        rest := false
        j := keep + 1
        while j < nd:
            if __load8(d + j) != 0:
                rest = true
            j += 1
        if rest:
            up = true
        elif keep > 0:
            up = (__load8(d + keep - 1) % 2) == 1
    if up:
        j := keep - 1
        carry := true
        while carry and j >= 0:
            v := __load8(buf + j) + 1
            if v == 10:
                __store8(buf + j, 0)
                j -= 1
            else:
                __store8(buf + j, v)
                carry = false
        if carry:
            __store8(buf, 1)
            j = 1
            while j < keep:
                __store8(buf + j, 0)
                j += 1
            x10 += 1
    __store64(out, buf)
    __store64(out + 8, keep)
    __store64(out + 16, x10)
    return out

func __rf_digit(t: int, i: int) -> int:
    if i < __load64(t + 8):
        return __load8(__load64(t) + i)
    return 0

func __nat__native_net__repr_float(n: int, a: int) -> int:
    __nat_range("repr_float", n, 1, 1)
    x := __nat_number("repr_float", a, "la valeur")
    if x != x:
        return __dyn_str("nan")
    bits := __f2bits(x)
    neg := bits < 0
    ax := x
    if neg:
        ax = 0.0 - x
    if ax == __bits2f(9218868437227405312):
        if neg:
            return __dyn_str("-inf")
        return __dyn_str("inf")
    sign := ""
    if neg:
        sign = "-"
    if ax == 0.0:
        return __dyn_str(sign + "0.0")
    ab := __f2bits(ax)
    e := (ab >> 52) & 2047
    m := ab & 4503599627370495
    e2 := e - 1075
    if e == 0:
        e2 = -1074
    else:
        m = m | 4503599627370496
    res := __alloc_raw(24)
    __rt_exact_digits(m, e2, res)
    d := __load64(res)
    nd := __load64(res + 8)
    x10 := __load64(res + 16)
    # plus petite précision qui se relit à l'identique
    prec := 17
    t := 0
    p := 1
    while p <= 17:
        t = __rf_round(d, nd, x10, p)
        if e == 0:
            p = 17
            t = __rf_round(d, nd, x10, 17)
            break
        sb := __rt_sb_new()
        i := 0
        while i < p:
            if i == 1:
                __rt_sb_byte(sb, 46)
            __rt_sb_byte(sb, 48 + __rf_digit(t, i))
            i += 1
        __rt_sb_add(sb, "e" + __int_to_str(__load64(t + 16)))
        same := false
        try:
            same = __f2bits(__rt_str_to_float(__rt_sb_str(sb))) == ab
        catch e:
            same = false
        if same:
            break
        p += 1
    if p > 17:
        p = 17
        t = __rf_round(d, nd, x10, 17)
    prec = p
    ex := __load64(t + 16)
    out := __rt_sb_new()
    __rt_sb_add(out, sign)
    if ex >= -4 and ex < 16:
        decimals := prec - 1 - ex
        if decimals < 1:
            decimals = 1
        f := __rf_round(d, nd, x10, ex + 1 + decimals)
        fx := __load64(f + 16)
        # partie entière
        if fx < 0:
            __rt_sb_byte(out, 48)
        else:
            i := 0
            while i <= fx:
                __rt_sb_byte(out, 48 + __rf_digit(f, i))
                i += 1
        __rt_sb_byte(out, 46)
        fr := __rt_sb_new()
        k := 1
        while k <= decimals:
            idx := fx + k
            if idx < 0:
                __rt_sb_byte(fr, 48)
            else:
                __rt_sb_byte(fr, 48 + __rf_digit(f, idx))
            k += 1
        frs := __rt_sb_str(fr)
        ln := __nat_blen(frs)
        while ln > 1 and __load8(__nat_bp(frs) + ln - 1) == 48:
            ln -= 1
        __rt_sb_add(out, __nat_sub(frs, 0, ln))
        return __dyn_str(__rt_sb_str(out))
    i := 0
    while i < prec:
        if i == 1:
            __rt_sb_byte(out, 46)
        __rt_sb_byte(out, 48 + __rf_digit(t, i))
        i += 1
    __rt_sb_byte(out, 101)
    ae := ex
    if ex < 0:
        __rt_sb_byte(out, 45)
        ae = 0 - ex
    else:
        __rt_sb_byte(out, 43)
    if ae < 10:
        __rt_sb_byte(out, 48)
    __rt_sb_add(out, __int_to_str(ae))
    return __dyn_str(__rt_sb_str(out))

# ---- os : charge, disque, copie de lien ----

func __nat__native_os__load_average(n: int) -> int:
    __nat_range("load_average", n, 0, 0)
    fd := __syscall(2, __nat_c("/proc/loadavg"), 0)
    if fd < 0:
        return 0
    data := __nat_read_fd(fd, 256)
    __syscall(3, fd)
    parts := __nat_split_bytes(data, 32)
    if __load64(parts) < 3:
        return 0
    l := __dyn_list_new(0)
    i := 0
    while i < 3:
        __dyn_list_push(l, __dyn_float(__rt_str_to_float(__as_str(__rt_vec_at(parts, i)))))
        i += 1
    return l

func __nat__native_os__disk_usage(n: int, a: int) -> int:
    __nat_range("disk_usage", n, 1, 1)
    path := __nat_str("disk_usage", a, "le chemin")
    if __windows():
        q := __alloc_raw(24)
        if __rt_w32(__wincall("GetDiskFreeSpaceExW", __pw_wide(path), q, q + 8, q + 16)) == 0:
            return 0
        lw := __dyn_list_new(0)
        __dyn_list_push(lw, __dyn_int(__load64(q + 8)))
        __dyn_list_push(lw, __dyn_int(__load64(q + 16)))
        __dyn_list_push(lw, __dyn_int(__load64(q)))
        return lw
    st := __alloc_raw(128)
    if __syscall(137, __nat_c(path), st) != 0:
        return 0
    unit := __load64(st + 72)
    if unit == 0:
        unit = __load64(st + 8)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_int(__load64(st + 16) * unit))
    __dyn_list_push(l, __dyn_int(__load64(st + 24) * unit))
    __dyn_list_push(l, __dyn_int(__load64(st + 32) * unit))
    return l

func __nat__native_os__copy_symlink(n: int, a: int, b: int) -> int:
    __nat_range("copy_symlink", n, 2, 2)
    src := __nat_cstr("copy_symlink", a, "la source")
    dst := __nat_cstr("copy_symlink", b, "la destination")
    c := __nat_ctx2("copy", src, dst)
    buf := __alloc_raw(4096)
    k := __syscall(89, __nat_c(src), buf, 4095)
    if k < 0:
        __nat_io_fail(c, __nat_errno_text(0 - k))
    r := __syscall(88, __nat_c(__nat_make(buf, k)), __nat_c(dst))
    if r < 0:
        __nat_io_fail(c, __nat_errno_text(0 - r))
    return 0

# ---- _native_memory : blocs de mémoire native suivis (gérés, bruts, mappés, externes) --------------------------------
# Registre (état du mode dynamique [280]) : [0] blocs (dict id -> bloc) [8] blocs triés par adresse (liste native)
# [16] adresses libérées (dict) [24] leur ordre (liste native) [32] prochain id [40] contrôles [48] gardes [56] limite
# [64] octets vivants [72] pic [80] allocations [88] libérations [96] gardes en attente (zone brute : [n][objet, id]...).
# Bloc : [0] id [8] genre (0 managed, 1 raw, 2 mapped, 3 external) [16] base [24] taille [32] alignement
# [40] zone d'origine [48] garde avant [56] gardé [64] lecture seule [72] étiquette (0 : aucune) [80] longueur mappée
# [88] protections par page (zone brute).

func __mm() -> int:
    ds := __dyn_ds()
    r := __load64(ds + 280)
    if r != 0:
        return r
    r = __alloc(112)
    __store64(r, __rt_dict_new(16))
    __store64(r + 8, __rt_list_new(0))
    __store64(r + 16, __rt_dict_new(16))
    __store64(r + 24, __rt_list_new(0))
    __store64(r + 32, 1)
    __store64(r + 40, 1)
    __store64(r + 48, 1)
    __store64(r + 56, -1)
    g := __alloc_raw(8 + 16 * 4096)
    __store64(g, 0)
    __store64(r + 96, g)
    __store64(ds + 280, r)
    return r

# Protection Windows (winProt de memory_native.cpp) : 1=R, 2=W, 4=X.
func __mm_win_prot(p: int) -> int:
    if p == 1:
        return 2        # PAGE_READONLY
    if p == 3 or p == 2:
        return 4        # PAGE_READWRITE
    if p == 4:
        return 16       # PAGE_EXECUTE
    if p == 5:
        return 32       # PAGE_EXECUTE_READ
    return 1            # PAGE_NOACCESS

func __mm_fail(fn: str, t: str):
    __dyn_err("MemoryError", "'" + fn + "' : " + t)

func __mm_arg(fn: str, t: str):
    __dyn_err("ArgumentError", "'" + fn + "' : " + t)

func __mm_hex(v: int) -> str:
    if v == 0:
        return "0x0"
    sb := __rt_sb_new()
    started := false
    sh := 60
    while sh >= 0:
        d := (v >> sh) & 15
        if d != 0 or started:
            __rt_sb_byte(sb, __nat_hex(d))
            started = true
        sh -= 4
    return "0x" + __rt_sb_str(sb)

func __mm_kind_name(k: int) -> str:
    if k == 0:
        return "managed"
    if k == 1:
        return "raw"
    if k == 2:
        return "mapped"
    return "external"

# Types : 0 bool 1 i8 2 u8 3 i16 4 u16 5 i32 6 u32 7 i64 8 u64 9 f32 10 f64 11 ptr
func __mm_type(fn: str, v: int) -> int:
    name := __nat_cstr(fn, v, "le type")
    tab := __nat_split_bytes("bool:0,i8:1,int8:1,u8:2,uint8:2,byte:2,i16:3,short:3,u16:4,ushort:4,i32:5,int:5,u32:6,uint:6,i64:7,long:7,isize:7,u64:8,ulong:8,size_t:8,usize:8,f32:9,float:9,f64:10,double:10,ptr:11,pointer:11,void*:11", 44)
    i := 0
    while i < __load64(tab):
        it := __as_str(__rt_vec_at(tab, i))
        q := __dyn_find_bytes(it, ":", 0)
        if __rt_str_eq(__nat_sub(it, 0, q), name):
            return __rt_str_to_int(__nat_sub(it, q + 1, __nat_blen(it) - q - 1))
        i += 1
    __mm_arg(fn, "type mémoire inconnu '" + name + "'")
    return 0

func __mm_tsize(t: int) -> int:
    if t <= 2:
        return 1
    if t <= 4:
        return 2
    if t <= 6 or t == 9:
        return 4
    return 8

func __mm_load(fn: str, p: int, t: int, big: bool) -> int:
    k := __mm_tsize(t)
    raw := 0
    i := 0
    while i < k:
        b := __load8(p + i)
        if big:
            raw = (raw << 8) | b
        else:
            raw = raw | (b << (8 * i))
        i += 1
    if t == 9:
        return __dyn_float(__nat_f32_value(raw))
    if t == 10:
        return __dyn_float(__bits2f(raw))
    if t == 0:
        return __dyn_bool((raw & 255) != 0)
    if t == 1:
        return __dyn_int(__sx(raw, 8))
    if t == 3:
        return __dyn_int(__sx(raw, 16))
    if t == 5:
        return __dyn_int(__sx(raw, 32))
    if t == 8 and raw < 0:
        __dyn_err("ValueError", "'" + fn + "' : valeur u64 > 2^63-1, non représentable par un int ALEX (lire en i64)")
    if t == 11 and raw == 0:
        return 0
    return __dyn_int(raw)

func __mm_store(fn: str, p: int, t: int, v: int, big: bool):
    k := __mm_tsize(t)
    raw := 0
    if t == 9:
        raw = __nat_f32_bits(__nat_number(fn, v, "la valeur"))
    elif t == 10:
        raw = __f2bits(__nat_number(fn, v, "la valeur"))
    elif t == 11 and v == 0:
        raw = 0
    elif t == 0:
        if __nat_bool(fn, v, "la valeur"):
            raw = 1
    else:
        x := __nat_int(fn, v, "la valeur")
        lo := 0
        hi := 0
        ok := true
        if t == 1:
            ok = x >= -128 and x <= 127
        elif t == 2:
            ok = x >= 0 and x <= 255
        elif t == 3:
            ok = x >= -32768 and x <= 32767
        elif t == 4:
            ok = x >= 0 and x <= 65535
        elif t == 5:
            ok = x >= -2147483648 and x <= 2147483647
        elif t == 6:
            ok = x >= 0 and x <= 4294967295
        if not ok:
            __mm_arg(fn, "valeur hors limites pour ce type (" + __int_to_str(x) + ")")
        raw = x
    i := 0
    while i < k:
        sh := 8 * i
        if big:
            sh = 8 * (k - 1 - i)
        __store8(p + i, (raw >> sh) & 255)
        i += 1

func __mm_blk(fn: str, v: int) -> int:
    id := __nat_int(fn, v, "le bloc")
    r := __mm()
    e := __rt_dict_index(__load64(r), id, 0)
    if e < 0:
        if id >= 1 and id < __load64(r + 32):
            __mm_fail(fn, "bloc " + __int_to_str(id) + " déjà libéré (double free ou utilisation après libération)")
        __mm_arg(fn, "identifiant de bloc invalide (" + __int_to_str(id) + ")")
    return __load64(__load64(__load64(r) + 32) + 8 * e)

# Bloc contenant [addr, addr + len[ (0 si aucun).
func __mm_containing(addr: int, len: int) -> int:
    r := __mm()
    l := __load64(r + 8)
    i := 0
    while i < __load64(l):
        b := __rt_vec_at(l, i)
        base := __load64(b + 16)
        if __rt_ule(base, addr) and __rt_ule(addr - base, __load64(b + 24)) and __rt_ule(len, __load64(b + 24) - (addr - base)):
            return b
        i += 1
    return 0

func __mm_insert(b: int):
    r := __mm()
    __rt_dict_set(__load64(r), __load64(b), b, 0)
    l := __load64(r + 8)
    __rt_list_push(l, b)
    d := __load64(l + 16)
    j := __load64(l) - 1
    while j > 0 and __rt_ule(__load64(b + 16), __load64(__load64(d + 8 * (j - 1)) + 16)):
        __store64(d + 8 * j, __load64(d + 8 * (j - 1)))
        j -= 1
    __store64(d + 8 * j, b)

func __mm_remove(b: int):
    r := __mm()
    __rt_dict_remove(__load64(r), __load64(b), 0)
    __rt_vec_remove(__load64(r + 8), b)

func __mm_range(fn: str, b: int, off: int, len: int):
    if off < 0 or len < 0 or off + len > __load64(b + 24) or off + len < off:
        __dyn_err("IndexError", "'" + fn + "' : accès hors bloc (offset " + __int_to_str(off) + ", longueur " + __int_to_str(len) +
                  ", taille " + __int_to_str(__load64(b + 24)) + ")")

func __mm_access(fn: str, b: int, off: int, len: int, write: bool):
    __mm_range(fn, b, off, len)
    if write and __load64(b + 64) != 0:
        __mm_fail(fn, "bloc " + __int_to_str(__load64(b)) + " en lecture seule")
    if __load64(b + 8) == 2 and len > 0:
        need := 1
        if write:
            need = 2
        pg := off // 4096
        while pg <= (off + len - 1) // 4096:
            if (__load8(__load64(b + 88) + pg) & need) == 0:
                w := "lisible"
                if write:
                    w = "inscriptible"
                __mm_fail(fn, "page " + __int_to_str(pg) + " non " + w + " (protection mémoire)")
            pg += 1

func __mm_resolve(fn: str, addr: int, len: int, write: bool) -> int:
    if len < 0:
        __mm_arg(fn, "longueur négative")
    if __rt_ule(addr, 4095):
        __mm_fail(fn, "déréférencement d'un pointeur nul ou quasi nul (" + __mm_hex(addr) + ")")
    r := __mm()
    if __load64(r + 40) == 0:
        return addr
    b := __mm_containing(addr, len)
    if b == 0:
        why := "adresse " + __mm_hex(addr) + " (+" + __int_to_str(len) + ") hors de toute région suivie"
        if __rt_dict_index(__load64(r + 16), addr, 0) >= 0:
            why = why + " — bloc déjà libéré (use-after-free)"
        __mm_fail(fn, why + " ; track() ou set_checks(false) pour un accès nu")
    __mm_access(fn, b, addr - __load64(b + 16), len, write)
    return addr

# Allocation de tas (managed / raw), avec gardes de 16 octets (canari 0xA5) et remplissage 0xCD si non mis à zéro.
func __mm_alloc(fn: str, size: int, align: int, zero: bool, kind: int, tag: int) -> int:
    r := __mm()
    if __load64(r + 56) >= 0 and __load64(r + 64) + size > __load64(r + 56):
        __mm_fail(fn, "quota mémoire dépassé (limite " + __int_to_str(__load64(r + 56)) + " octets, " + __int_to_str(__load64(r + 64)) + " déjà alloués)")
    eff := align
    if eff < 16:
        eff = 16
    front := 0
    rear := 0
    if __load64(r + 48) != 0:
        front = (16 + eff - 1) // eff * eff
        rear = 16
    total := front + size + rear
    if total < 0 or total > 70368744177664:
        __mm_fail(fn, "taille demandée trop grande (" + __int_to_str(size) + ")")
    zone := __alloc_raw(total + eff)
    origin := (zone + eff - 1) // eff * eff
    base := origin + front
    if front > 0:
        __mem_fill(base - 16, 16, 165)
        __mem_fill(base + size, 16, 165)
    if zero:
        __zero(base, size)
    else:
        __mem_fill(base, size, 205)
    b := __alloc(104)
    id := __load64(r + 32)
    __store64(r + 32, id + 1)
    __store64(b, id)
    __store64(b + 8, kind)
    __store64(b + 16, base)
    __store64(b + 24, size)
    __store64(b + 32, align)
    __store64(b + 40, zone)
    __store64(b + 48, front)
    if front > 0:
        __store64(b + 56, 1)
    __store64(b + 72, tag)
    if __rt_dict_index(__load64(r + 16), base, 0) >= 0:
        __rt_dict_remove(__load64(r + 16), base, 0)
    __store64(r + 64, __load64(r + 64) + size)
    if __load64(r + 64) > __load64(r + 72):
        __store64(r + 72, __load64(r + 64))
    __store64(r + 80, __load64(r + 80) + 1)
    __mm_insert(b)
    return b

func __mem_fill(p: int, n: int, v: int):
    i := 0
    while i < n:
        __store8(p + i, v)
        i += 1

func __mm_guards_ok(b: int) -> bool:
    if __load64(b + 56) == 0:
        return true
    base := __load64(b + 16)
    i := 0
    while i < 16:
        if __load8(base - 16 + i) != 165 or __load8(base + __load64(b + 24) + i) != 165:
            return false
        i += 1
    return true

func __mm_corruption(b: int) -> str:
    front := false
    i := 0
    while i < 16:
        if __load8(__load64(b + 16) - 16 + i) != 165:
            front = true
        i += 1
    where := "APRÈS la fin"
    if front:
        where = "AVANT le début"
    return "corruption du tas dans le bloc " + __int_to_str(__load64(b)) + " : écriture " + where + " (débordement de tampon)"

func __mm_release(b: int, remember: bool) -> bool:
    r := __mm()
    ok := __mm_guards_ok(b)
    if __load64(b + 24) <= 1048576:
        __mem_fill(__load64(b + 16), __load64(b + 24), 221)
    __store64(r + 64, __load64(r + 64) - __load64(b + 24))
    __store64(r + 88, __load64(r + 88) + 1)
    __mm_remove(b)
    if remember:
        base := __load64(b + 16)
        __rt_dict_set(__load64(r + 16), base, 1, 0)
        ord := __load64(r + 24)
        __rt_list_push(ord, base)
        if __load64(ord) > 65536:
            old := __rt_vec_at(ord, 0)
            __rt_vec_remove(ord, old)
            if __rt_dict_index(__load64(r + 16), old, 0) >= 0:
                __rt_dict_remove(__load64(r + 16), old, 0)
    return ok

# Après une collecte : libère les blocs « managed » dont l'objet garde a été collecté (son en-tête n'est plus alloué).
func __mem_after_gc():
    r := __load64(__dyn_ds() + 280)
    if r == 0:
        return
    g := __load64(r + 96)
    n := __load64(g)
    i := 0
    while i < n:
        obj := __load64(g + 8 + 16 * i)
        if (__load64(obj - 8) & 1) == 0:
            id := __load64(g + 16 + 16 * i)
            __store64(g + 8 + 16 * i, __load64(g + 8 + 16 * (n - 1)))
            __store64(g + 16 + 16 * i, __load64(g + 16 + 16 * (n - 1)))
            n -= 1
            __store64(g, n)
            e := __rt_dict_index(__load64(r), id, 0)
            if e >= 0:
                b := __load64(__load64(__load64(r) + 32) + 8 * e)
                if __load64(b + 8) == 0:
                    __mm_release(b, false)
            continue
        i += 1

func __mm_describe(b: int) -> int:
    d := __dyn_dict_new()
    __nat_dict_put(d, "id", __dyn_int(__load64(b)))
    __nat_dict_put(d, "kind", __dyn_str(__mm_kind_name(__load64(b + 8))))
    __nat_dict_put(d, "address", __dyn_int(__load64(b + 16)))
    __nat_dict_put(d, "size", __dyn_int(__load64(b + 24)))
    __nat_dict_put(d, "align", __dyn_int(__load64(b + 32)))
    __nat_dict_put(d, "readonly", __dyn_bool(__load64(b + 64) != 0))
    if __load64(b + 72) == 0:
        __nat_dict_put(d, "tag", 0)
    else:
        __nat_dict_put(d, "tag", __dyn_str(__as_str(__load64(b + 72))))
    return d

func __nat__native_memory__supported(n: int) -> int:
    __nat_range("supported", n, 0, 0)
    return __dyn_bool(true)

func __nat__native_memory__page_size(n: int) -> int:
    __nat_range("page_size", n, 0, 0)
    return __dyn_int(4096)

func __nat__native_memory__word_size(n: int) -> int:
    __nat_range("word_size", n, 0, 0)
    return __dyn_int(8)

func __nat__native_memory__endianness(n: int) -> int:
    __nat_range("endianness", n, 0, 0)
    return __dyn_str("little")

func __nat__native_memory__type_size(n: int, a: int) -> int:
    __nat_range("type_size", n, 1, 1)
    return __dyn_int(__mm_tsize(__mm_type("type_size", a)))

func __nat__native_memory__stats(n: int) -> int:
    __nat_range("stats", n, 0, 0)
    r := __mm()
    cnt := __alloc_raw(64)
    __zero(cnt, 64)
    l := __load64(r + 8)
    i := 0
    while i < __load64(l):
        b := __rt_vec_at(l, i)
        k := __load64(b + 8)
        __store64(cnt + 8 * k, __load64(cnt + 8 * k) + 1)
        __store64(cnt + 32 + 8 * k, __load64(cnt + 32 + 8 * k) + __load64(b + 24))
        i += 1
    d := __dyn_dict_new()
    k := 0
    while k < 4:
        __nat_dict_put(d, __mm_kind_name(k) + "_blocks", __dyn_int(__load64(cnt + 8 * k)))
        __nat_dict_put(d, __mm_kind_name(k) + "_bytes", __dyn_int(__load64(cnt + 32 + 8 * k)))
        k += 1
    __nat_dict_put(d, "live_bytes", __dyn_int(__load64(r + 64)))
    __nat_dict_put(d, "peak_bytes", __dyn_int(__load64(r + 72)))
    __nat_dict_put(d, "total_allocs", __dyn_int(__load64(r + 80)))
    __nat_dict_put(d, "total_frees", __dyn_int(__load64(r + 88)))
    return d

func __nat__native_memory__live(n: int, a: int) -> int:
    __nat_range("live", n, 0, 1)
    only := ""
    if n == 1 and a != 0:
        only = __nat_cstr("live", a, "le genre")
    r := __mm()
    out := __dyn_list_new(0)
    ids := __rt_dict_list(__load64(r), 24)
    # ordre des identifiants (std::map)
    __mm_sort_ints(ids)
    i := 0
    while i < __load64(ids):
        e := __rt_dict_index(__load64(r), __rt_vec_at(ids, i), 0)
        b := __load64(__load64(__load64(r) + 32) + 8 * e)
        if __nat_blen(only) == 0 or __rt_str_eq(only, __mm_kind_name(__load64(b + 8))):
            __dyn_list_push(out, __mm_describe(b))
        i += 1
    return out

func __mm_sort_ints(l: int):
    d := __load64(l + 16)
    m := __load64(l)
    i := 1
    while i < m:
        x := __load64(d + 8 * i)
        j := i - 1
        while j >= 0 and __load64(d + 8 * j) > x:
            __store64(d + 8 * (j + 1), __load64(d + 8 * j))
            j -= 1
        __store64(d + 8 * (j + 1), x)
        i += 1

func __nat__native_memory__set_limit(n: int, a: int) -> int:
    __nat_range("set_limit", n, 1, 1)
    r := __mm()
    prev := __load64(r + 56)
    if a == 0:
        __store64(r + 56, -1)
    else:
        k := __nat_int("set_limit", a, "la limite")
        if k < 0:
            __mm_arg("set_limit", "limite négative")
        __store64(r + 56, k)
    if prev < 0:
        return 0
    return __dyn_int(prev)

func __nat__native_memory__limit(n: int) -> int:
    __nat_range("limit", n, 0, 0)
    v := __load64(__mm() + 56)
    if v < 0:
        return 0
    return __dyn_int(v)

func __nat__native_memory__set_checks(n: int, a: int) -> int:
    __nat_range("set_checks", n, 1, 1)
    r := __mm()
    prev := __load64(r + 40) != 0
    v := 0
    if __nat_bool("set_checks", a, "l'indicateur"):
        v = 1
    __store64(r + 40, v)
    return __dyn_bool(prev)

func __nat__native_memory__checks(n: int) -> int:
    __nat_range("checks", n, 0, 0)
    return __dyn_bool(__load64(__mm() + 40) != 0)

func __nat__native_memory__set_guards(n: int, a: int) -> int:
    __nat_range("set_guards", n, 1, 1)
    r := __mm()
    prev := __load64(r + 48) != 0
    v := 0
    if __nat_bool("set_guards", a, "l'indicateur"):
        v = 1
    __store64(r + 48, v)
    return __dyn_bool(prev)

# parseAlloc : (taille, alignement = 16, zero, étiquette) -> [taille, alignement, zero, étiquette]
func __mm_parse_alloc(fn: str, n: int, a: int, b: int, c: int, d: int, dz: bool, out: int):
    __nat_range(fn, n, 1, 4)
    size := __nat_int(fn, a, "la taille")
    if size < 1:
        __mm_arg(fn, "taille invalide (>= 1 requis)")
    al := 16
    if n > 1 and b != 0:
        al = __nat_int(fn, b, "l'alignement")
    if al <= 0 or (al & (al - 1)) != 0 or al > 65536:
        __mm_arg(fn, "alignement invalide (puissance de 2, 1..65536)")
    zero := dz
    if n > 2 and c != 0:
        zero = __nat_bool(fn, c, "l'indicateur zero")
    tag := 0
    if n > 3 and d != 0:
        tag = __str_addr(__nat_cstr(fn, d, "l'étiquette"))
    __store64(out, size)
    __store64(out + 8, al)
    __store64(out + 16, 0)
    if zero:
        __store64(out + 16, 1)
    __store64(out + 24, tag)

func __nat__native_memory__alloc(n: int, a: int, b: int, c: int, d: int) -> int:
    pa := __alloc_raw(32)
    __mm_parse_alloc("alloc", n, a, b, c, d, true, pa)
    blk := __mm_alloc("alloc", __load64(pa), __load64(pa + 8), __load64(pa + 16) != 0, 0, __load64(pa + 24))
    return __dyn_int(__load64(blk))

func __nat__native_memory__free(n: int, a: int) -> int:
    __nat_range("free", n, 1, 1)
    b := __mm_blk("free", a)
    k := __load64(b + 8)
    if k != 0:
        hint := "untrack"
        if k == 1:
            hint = "raw_free"
        elif k == 2:
            hint = "vm_unmap"
        __mm_arg("free", "bloc de genre '" + __mm_kind_name(k) + "' : utiliser " + hint)
    if not __mm_release(b, false):
        __mm_fail("free", "corruption du tas détectée à la libération du bloc " + __int_to_str(__load64(b)) + " (débordement de tampon)")
    return 0

func __nat__native_memory__realloc(n: int, a: int, b2: int, c: int) -> int:
    __nat_range("realloc", n, 2, 3)
    b := __mm_blk("realloc", a)
    if __load64(b + 8) != 0:
        __mm_arg("realloc", "seuls les blocs 'managed' sont redimensionnables (raw : raw_realloc)")
    size := __nat_int("realloc", b2, "la nouvelle taille")
    if size < 1:
        __mm_arg("realloc", "taille invalide (>= 1 requis)")
    zero := true
    if n > 2 and c != 0:
        zero = __nat_bool("realloc", c, "zero")
    if not __mm_guards_ok(b):
        __mm_fail("realloc", __mm_corruption(b))
    keep := __load64(b + 24)
    if size < keep:
        keep = size
    nb := __mm_alloc("realloc", size, __load64(b + 32), zero, 0, __load64(b + 72))
    __copy(__load64(nb + 16), __load64(b + 16), keep)
    # le bloc d'origine garde son identifiant : échange des champs physiques
    r := __mm()
    __rt_vec_remove(__load64(r + 8), b)
    __rt_vec_remove(__load64(r + 8), nb)
    i := 16
    while i < 64:
        if i != 32:
            t := __load64(b + i)
            __store64(b + i, __load64(nb + i))
            __store64(nb + i, t)
        i += 8
    __rt_list_push(__load64(r + 8), nb)
    __rt_vec_remove(__load64(r + 8), nb)
    __rt_dict_remove(__load64(r), __load64(b), 0)
    __mm_insert(b)
    __rt_dict_set(__load64(r), __load64(nb), nb, 0)
    __rt_list_push(__load64(r + 8), nb)
    __mm_release(nb, false)
    return 0

func __nat__native_memory__guard(n: int, a: int) -> int:
    __nat_range("guard", n, 1, 1)
    b := __mm_blk("guard", a)
    if __load64(b + 8) != 0:
        __mm_arg("guard", "seuls les blocs 'managed' ont une garde de libération automatique")
    g := __dyn_native_new(__fnaddr("__dyn_native_missing"), "<memory-guard>")
    r := __mm()
    gl := __load64(r + 96)
    k := __load64(gl)
    if k < 4096:
        __store64(gl + 8 + 16 * k, g)
        __store64(gl + 16 + 16 * k, __load64(b))
        __store64(gl, k + 1)
    return g

func __nat__native_memory__size(n: int, a: int) -> int:
    __nat_range("size", n, 1, 1)
    return __dyn_int(__load64(__mm_blk("size", a) + 24))

func __nat__native_memory__address(n: int, a: int) -> int:
    __nat_range("address", n, 1, 1)
    return __dyn_int(__load64(__mm_blk("address", a) + 16))

func __nat__native_memory__align_of(n: int, a: int) -> int:
    __nat_range("align_of", n, 1, 1)
    return __dyn_int(__load64(__mm_blk("align_of", a) + 32))

func __nat__native_memory__kind(n: int, a: int) -> int:
    __nat_range("kind", n, 1, 1)
    return __dyn_str(__mm_kind_name(__load64(__mm_blk("kind", a) + 8)))

func __nat__native_memory__alive(n: int, a: int) -> int:
    __nat_range("alive", n, 1, 1)
    id := __nat_int("alive", a, "le bloc")
    return __dyn_bool(__rt_dict_index(__load64(__mm()), id, 0) >= 0)

func __nat__native_memory__info(n: int, a: int) -> int:
    __nat_range("info", n, 1, 1)
    return __mm_describe(__mm_blk("info", a))

func __mm_bool_opt(fn: str, n: int, k: int, v: int, label: str) -> bool:
    if n > k and v != 0:
        return __nat_bool(fn, v, label)
    return false

func __nat__native_memory__read(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("read", n, 3, 4)
    blk := __mm_blk("read", a)
    off := __nat_int("read", b, "l'offset")
    t := __mm_type("read", c)
    big := __mm_bool_opt("read", n, 3, d, "big")
    __mm_access("read", blk, off, __mm_tsize(t), false)
    return __mm_load("read", __load64(blk + 16) + off, t, big)

func __nat__native_memory__write(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_range("write", n, 4, 5)
    blk := __mm_blk("write", a)
    off := __nat_int("write", b, "l'offset")
    t := __mm_type("write", c)
    big := __mm_bool_opt("write", n, 4, e, "big")
    __mm_access("write", blk, off, __mm_tsize(t), true)
    __mm_store("write", __load64(blk + 16) + off, t, d, big)
    return __dyn_int(__mm_tsize(t))

func __nat__native_memory__read_bytes(n: int, a: int, b: int, c: int) -> int:
    __nat_range("read_bytes", n, 3, 3)
    blk := __mm_blk("read_bytes", a)
    off := __nat_int("read_bytes", b, "l'offset")
    len := __nat_int("read_bytes", c, "la longueur")
    __mm_access("read_bytes", blk, off, len, false)
    return __dyn_str(__nat_make(__load64(blk + 16) + off, len))

func __nat__native_memory__write_bytes(n: int, a: int, b: int, c: int) -> int:
    __nat_range("write_bytes", n, 3, 3)
    blk := __mm_blk("write_bytes", a)
    off := __nat_int("write_bytes", b, "l'offset")
    s := __nat_str("write_bytes", c, "les octets")
    __mm_access("write_bytes", blk, off, __nat_blen(s), true)
    __copy(__load64(blk + 16) + off, __nat_bp(s), __nat_blen(s))
    return __dyn_int(__nat_blen(s))

func __nat__native_memory__fill(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("fill", n, 4, 4)
    blk := __mm_blk("fill", a)
    off := __nat_int("fill", b, "l'offset")
    len := __nat_int("fill", c, "la longueur")
    v := __nat_int("fill", d, "l'octet")
    if v < 0 or v > 255:
        __mm_arg("fill", "octet hors limites (0..255)")
    __mm_access("fill", blk, off, len, true)
    __mem_fill(__load64(blk + 16) + off, len, v)
    return 0

func __mem_move(d: int, s: int, n: int):
    if n <= 0:
        return
    if __rt_ule(d, s) or __rt_ule(s + n, d):
        i := 0
        while i < n:
            __store8(d + i, __load8(s + i))
            i += 1
        return
    i := n - 1
    while i >= 0:
        __store8(d + i, __load8(s + i))
        i -= 1

func __mem_cmp(p: int, q: int, n: int) -> int:
    i := 0
    while i < n:
        x := __load8(p + i)
        y := __load8(q + i)
        if x != y:
            if x < y:
                return -1
            return 1
        i += 1
    return 0

func __nat__native_memory__copy(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_range("copy", n, 5, 5)
    db := __mm_blk("copy", a)
    doff := __nat_int("copy", b, "l'offset destination")
    sbk := __mm_blk("copy", c)
    soff := __nat_int("copy", d, "l'offset source")
    len := __nat_int("copy", e, "la longueur")
    __mm_access("copy", sbk, soff, len, false)
    __mm_access("copy", db, doff, len, true)
    __mem_move(__load64(db + 16) + doff, __load64(sbk + 16) + soff, len)
    return __dyn_int(len)

func __nat__native_memory__compare(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_range("compare", n, 5, 5)
    x := __mm_blk("compare", a)
    xo := __nat_int("compare", b, "l'offset A")
    y := __mm_blk("compare", c)
    yo := __nat_int("compare", d, "l'offset B")
    len := __nat_int("compare", e, "la longueur")
    __mm_access("compare", x, xo, len, false)
    __mm_access("compare", y, yo, len, false)
    return __dyn_int(__mem_cmp(__load64(x + 16) + xo, __load64(y + 16) + yo, len))

func __nat__native_memory__find(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("find", n, 4, 4)
    blk := __mm_blk("find", a)
    off := __nat_int("find", b, "l'offset")
    len := __nat_int("find", c, "la longueur")
    needle := __nat_str("find", d, "le motif")
    __mm_access("find", blk, off, len, false)
    if __nat_blen(needle) == 0:
        return __dyn_int(0)
    return __dyn_int(__dyn_find_bytes(__nat_make(__load64(blk + 16) + off, len), needle, 0))

func __nat__native_memory__zero_secure(n: int, a: int, b: int, c: int) -> int:
    __nat_range("zero_secure", n, 3, 3)
    blk := __mm_blk("zero_secure", a)
    off := __nat_int("zero_secure", b, "l'offset")
    len := __nat_int("zero_secure", c, "la longueur")
    __mm_access("zero_secure", blk, off, len, true)
    __mem_fill(__load64(blk + 16) + off, len, 0)
    return 0

func __nat__native_memory__byte_len(n: int, a: int) -> int:
    __nat_range("byte_len", n, 1, 1)
    return __dyn_int(__nat_blen(__nat_str("byte_len", a, "le texte")))

func __nat__native_memory__read_cstr(n: int, a: int, b: int, c: int) -> int:
    __nat_range("read_cstr", n, 3, 3)
    blk := __mm_blk("read_cstr", a)
    off := __nat_int("read_cstr", b, "l'offset")
    mx := __nat_int("read_cstr", c, "la longueur max")
    __mm_access("read_cstr", blk, off, mx, false)
    p := __load64(blk + 16) + off
    i := 0
    while i < mx:
        if __load8(p + i) == 0:
            return __dyn_str(__nat_make(p, i))
        i += 1
    __mm_arg("read_cstr", "aucun NUL de fin dans la plage demandée")
    return 0

func __nat__native_memory__check(n: int, a: int) -> int:
    __nat_range("check", n, 1, 1)
    b := __mm_blk("check", a)
    if not __mm_guards_ok(b):
        __mm_fail("check", __mm_corruption(b))
    return __dyn_bool(true)

func __nat__native_memory__check_all(n: int) -> int:
    __nat_range("check_all", n, 0, 0)
    r := __mm()
    ids := __rt_dict_list(__load64(r), 24)
    __mm_sort_ints(ids)
    i := 0
    while i < __load64(ids):
        e := __rt_dict_index(__load64(r), __rt_vec_at(ids, i), 0)
        b := __load64(__load64(__load64(r) + 32) + 8 * e)
        if not __mm_guards_ok(b):
            __mm_fail("check_all", __mm_corruption(b))
        i += 1
    return __dyn_int(__load64(ids))

func __nat__native_memory__set_readonly(n: int, a: int, b: int) -> int:
    __nat_range("set_readonly", n, 2, 2)
    blk := __mm_blk("set_readonly", a)
    v := 0
    if __nat_bool("set_readonly", b, "l'indicateur"):
        v = 1
    __store64(blk + 64, v)
    return 0

func __nat__native_memory__is_readonly(n: int, a: int) -> int:
    __nat_range("is_readonly", n, 1, 1)
    return __dyn_bool(__load64(__mm_blk("is_readonly", a) + 64) != 0)

# ---- niveau brut ----

func __nat__native_memory__raw_alloc(n: int, a: int, b: int, c: int, d: int) -> int:
    pa := __alloc_raw(32)
    __mm_parse_alloc("raw_alloc", n, a, b, c, d, false, pa)
    blk := __mm_alloc("raw_alloc", __load64(pa), __load64(pa + 8), __load64(pa + 16) != 0, 1, __load64(pa + 24))
    return __dyn_int(__load64(blk + 16))

func __mm_raw_at(fn: str, addr: int) -> int:
    r := __mm()
    l := __load64(r + 8)
    i := 0
    while i < __load64(l):
        b := __rt_vec_at(l, i)
        if __load64(b + 16) == addr:
            if __load64(b + 8) != 1:
                __mm_arg(fn, "région de genre '" + __mm_kind_name(__load64(b + 8)) + "' : genre incompatible (alloc/free ou vm_map/vm_unmap mélangés)")
            return b
        i += 1
    if __rt_dict_index(__load64(r + 16), addr, 0) >= 0:
        __mm_fail(fn, "double free : " + __mm_hex(addr) + " a déjà été libéré")
    inb := __mm_containing(addr, 0)
    if inb != 0:
        __mm_fail(fn, "pointeur intérieur " + __mm_hex(addr) + " (bloc " + __int_to_str(__load64(inb)) + ") : seul le début du bloc peut être libéré")
    __mm_fail(fn, "pointeur " + __mm_hex(addr) + " non alloué par raw_alloc")
    return 0

func __nat__native_memory__raw_free(n: int, a: int) -> int:
    __nat_range("raw_free", n, 1, 1)
    b := __mm_raw_at("raw_free", __nat_int("raw_free", a, "le pointeur"))
    if not __mm_release(b, true):
        __mm_fail("raw_free", "corruption du tas détectée à la libération (débordement de tampon)")
    return 0

func __nat__native_memory__raw_realloc(n: int, a: int, c: int) -> int:
    __nat_range("raw_realloc", n, 2, 2)
    old := __mm_raw_at("raw_realloc", __nat_int("raw_realloc", a, "le pointeur"))
    size := __nat_int("raw_realloc", c, "la nouvelle taille")
    if size < 1:
        __mm_arg("raw_realloc", "taille invalide (>= 1 requis)")
    if not __mm_guards_ok(old):
        __mm_fail("raw_realloc", __mm_corruption(old))
    keep := __load64(old + 24)
    if size < keep:
        keep = size
    nb := __mm_alloc("raw_realloc", size, __load64(old + 32), false, 1, __load64(old + 72))
    __copy(__load64(nb + 16), __load64(old + 16), keep)
    if size > keep:
        __zero(__load64(nb + 16) + keep, size - keep)
    res := __load64(nb + 16)
    __mm_release(old, true)
    return __dyn_int(res)

func __nat__native_memory__peek(n: int, a: int, b: int, c: int) -> int:
    __nat_range("peek", n, 2, 3)
    addr := __nat_int("peek", a, "l'adresse")
    t := __mm_type("peek", b)
    big := __mm_bool_opt("peek", n, 2, c, "big")
    return __mm_load("peek", __mm_resolve("peek", addr, __mm_tsize(t), false), t, big)

func __nat__native_memory__poke(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("poke", n, 3, 4)
    addr := __nat_int("poke", a, "l'adresse")
    t := __mm_type("poke", b)
    big := __mm_bool_opt("poke", n, 3, d, "big")
    __mm_store("poke", __mm_resolve("poke", addr, __mm_tsize(t), true), t, c, big)
    return __dyn_int(__mm_tsize(t))

func __nat__native_memory__peek_bytes(n: int, a: int, b: int) -> int:
    __nat_range("peek_bytes", n, 2, 2)
    addr := __nat_int("peek_bytes", a, "l'adresse")
    len := __nat_int("peek_bytes", b, "la longueur")
    return __dyn_str(__nat_make(__mm_resolve("peek_bytes", addr, len, false), len))

func __nat__native_memory__poke_bytes(n: int, a: int, b: int) -> int:
    __nat_range("poke_bytes", n, 2, 2)
    addr := __nat_int("poke_bytes", a, "l'adresse")
    s := __nat_str("poke_bytes", b, "les octets")
    p := __mm_resolve("poke_bytes", addr, __nat_blen(s), true)
    __mem_move(p, __nat_bp(s), __nat_blen(s))
    return __dyn_int(__nat_blen(s))

func __nat__native_memory__peek_cstr(n: int, a: int, b: int) -> int:
    __nat_range("peek_cstr", n, 1, 2)
    addr := __nat_int("peek_cstr", a, "l'adresse")
    mx := -1
    if n > 1 and b != 0:
        mx = __nat_int("peek_cstr", b, "la longueur max")
    if mx < -1:
        __mm_arg("peek_cstr", "longueur max invalide")
    if __rt_ule(addr, 4095):
        __mm_fail("peek_cstr", "déréférencement d'un pointeur nul")
    if __load64(__mm() + 40) != 0:
        blk := __mm_containing(addr, 0)
        if blk == 0:
            __mm_fail("peek_cstr", "adresse " + __mm_hex(addr) + " hors de toute région suivie")
        off := addr - __load64(blk + 16)
        limit := __load64(blk + 24) - off
        if mx >= 0 and mx < limit:
            limit = mx
        __mm_access("peek_cstr", blk, off, limit, false)
        i := 0
        while i < limit:
            if __load8(addr + i) == 0:
                return __dyn_str(__nat_make(addr, i))
            i += 1
        if mx >= 0 and limit == mx:
            return __dyn_str(__nat_make(addr, limit))
        __mm_fail("peek_cstr", "aucun NUL de fin avant la fin de la région")
    i := 0
    while mx < 0 or i < mx:
        if __load8(addr + i) == 0:
            break
        i += 1
    return __dyn_str(__nat_make(addr, i))

func __nat__native_memory__raw_fill(n: int, a: int, b: int, c: int) -> int:
    __nat_range("raw_fill", n, 3, 3)
    addr := __nat_int("raw_fill", a, "l'adresse")
    len := __nat_int("raw_fill", b, "la longueur")
    v := __nat_int("raw_fill", c, "l'octet")
    if v < 0 or v > 255:
        __mm_arg("raw_fill", "octet hors limites (0..255)")
    __mem_fill(__mm_resolve("raw_fill", addr, len, true), len, v)
    return 0

func __nat__native_memory__raw_copy(n: int, a: int, b: int, c: int) -> int:
    __nat_range("raw_copy", n, 3, 3)
    dst := __nat_int("raw_copy", a, "la destination")
    src := __nat_int("raw_copy", b, "la source")
    len := __nat_int("raw_copy", c, "la longueur")
    sp := __mm_resolve("raw_copy", src, len, false)
    dp := __mm_resolve("raw_copy", dst, len, true)
    __mem_move(dp, sp, len)
    return __dyn_int(len)

func __nat__native_memory__raw_compare(n: int, a: int, b: int, c: int) -> int:
    __nat_range("raw_compare", n, 3, 3)
    x := __nat_int("raw_compare", a, "l'adresse A")
    y := __nat_int("raw_compare", b, "l'adresse B")
    len := __nat_int("raw_compare", c, "la longueur")
    p := __mm_resolve("raw_compare", x, len, false)
    q := __mm_resolve("raw_compare", y, len, false)
    return __dyn_int(__mem_cmp(p, q, len))

func __nat__native_memory__track(n: int, a: int, b: int, c: int) -> int:
    __nat_range("track", n, 2, 3)
    addr := __nat_int("track", a, "l'adresse")
    size := __nat_int("track", b, "la taille")
    if __rt_ule(addr, 4095) or size < 1:
        __mm_arg("track", "région invalide")
    tag := 0
    if n > 2 and c != 0:
        tag = __str_addr(__nat_cstr("track", c, "l'étiquette"))
    if __rt_ule(addr + size, addr - 1) and addr + size != 0:
        __mm_arg("track", "région débordant l'espace d'adressage")
    if __mm_containing(addr, 0) != 0 or __mm_containing(addr, size) != 0:
        __mm_arg("track", "la région chevauche une région déjà suivie")
    l := __load64(__mm() + 8)
    i := 0
    while i < __load64(l):
        base := __load64(__rt_vec_at(l, i) + 16)
        if __rt_ule(addr, base) and __rt_ule(base + 1, addr + size):
            __mm_arg("track", "la région chevauche une région déjà suivie")
        i += 1
    r := __mm()
    blk := __alloc(104)
    id := __load64(r + 32)
    __store64(r + 32, id + 1)
    __store64(blk, id)
    __store64(blk + 8, 3)
    __store64(blk + 16, addr)
    __store64(blk + 24, size)
    __store64(blk + 32, 16)
    __store64(blk + 72, tag)
    __mm_insert(blk)
    return __dyn_int(id)

func __nat__native_memory__untrack(n: int, a: int) -> int:
    __nat_range("untrack", n, 1, 1)
    b := __mm_blk("untrack", a)
    if __load64(b + 8) != 3:
        __mm_arg("untrack", "seules les régions 'external' se retirent par untrack")
    __mm_remove(b)
    return 0

func __nat__native_memory__region_of(n: int, a: int) -> int:
    __nat_range("region_of", n, 1, 1)
    addr := __nat_int("region_of", a, "l'adresse")
    b := __mm_containing(addr, 0)
    if b == 0:
        return 0
    d := __mm_describe(b)
    __nat_dict_put(d, "offset", __dyn_int(addr - __load64(b + 16)))
    return d

func __nat__native_memory__accessible(n: int, a: int, b: int, c: int) -> int:
    __nat_range("accessible", n, 2, 3)
    addr := __nat_int("accessible", a, "l'adresse")
    len := __nat_int("accessible", b, "la longueur")
    write := __mm_bool_opt("accessible", n, 2, c, "write")
    if len < 0 or __rt_ule(addr, 4095):
        return __dyn_bool(false)
    blk := __mm_containing(addr, len)
    if blk == 0:
        return __dyn_bool(false)
    ok := true
    try:
        __mm_access("accessible", blk, addr - __load64(blk + 16), len, write)
    catch e:
        ok = false
    return __dyn_bool(ok)

func __nat__native_memory__probe(n: int, a: int, b: int) -> int:
    __nat_range("probe", n, 2, 2)
    addr := __nat_int("probe", a, "l'adresse")
    len := __nat_int("probe", b, "la longueur")
    if len < 1 or __rt_ule(addr, 4095):
        return __dyn_bool(false)
    first := addr - (addr & 4095)
    end := addr + len
    if __rt_ule(end, addr):
        return __dyn_bool(false)
    if __windows():
        mi := __alloc_raw(48)
        pg := first
        while not __rt_ule(end, pg):
            if __wincall("VirtualQuery", pg, mi, 48) == 0:
                return __dyn_bool(false)
            if __load32(mi + 32) != 4096 or (__load32(mi + 36) & 257) != 0:
                return __dyn_bool(false)
            pg += 4096
        return __dyn_bool(true)
    pages := (end - first + 4095) // 4096
    vec := __alloc_raw(pages + 8)
    return __dyn_bool(__syscall(27, first, pages * 4096, vec) == 0)

# ---- mémoire virtuelle ----

func __mm_prot(fn: str, v: int) -> int:
    p := __nat_int(fn, v, "la protection")
    if p < 0 or p > 7:
        __mm_arg(fn, "protection invalide (combinaison de 1=R, 2=W, 4=X)")
    if (p & 2) != 0 and (p & 4) != 0:
        __mm_arg(fn, "protection W+X refusée (politique W^X)")
    return p

func __mm_mapped(fn: str, v: int) -> int:
    b := __mm_blk(fn, v)
    if __load64(b + 8) != 2:
        __mm_arg(fn, "région de genre '" + __mm_kind_name(__load64(b + 8)) + "' : une région mappée est requise")
    return b

func __mm_page_range(fn: str, b: int, off: int, len: int):
    if off < 0 or len < 1 or off % 4096 != 0 or len % 4096 != 0:
        __mm_arg(fn, "offset et longueur doivent être des multiples de la page (4096) ; longueur >= 1")
    if off + len > __load64(b + 80):
        __dyn_err("IndexError", "'" + fn + "' : plage hors de la région mappée")

func __mm_register_map(p: int, logical: int, mapLen: int, prot: int, tag: int) -> int:
    r := __mm()
    b := __alloc(104)
    id := __load64(r + 32)
    __store64(r + 32, id + 1)
    __store64(b, id)
    __store64(b + 8, 2)
    __store64(b + 16, p)
    __store64(b + 24, logical)
    __store64(b + 32, 4096)
    __store64(b + 72, tag)
    __store64(b + 80, mapLen)
    pp := __alloc_raw(mapLen // 4096 + 8)
    __mem_fill(pp, mapLen // 4096, prot)
    __store64(b + 88, pp)
    if __rt_dict_index(__load64(r + 16), p, 0) >= 0:
        __rt_dict_remove(__load64(r + 16), p, 0)
    __mm_insert(b)
    return __dyn_int(id)

func __nat__native_memory__vm_map(n: int, a: int, b: int, c: int) -> int:
    __nat_range("vm_map", n, 1, 3)
    size := __nat_int("vm_map", a, "la taille")
    if size < 1 or size > 1099511627776:
        __mm_arg("vm_map", "taille invalide")
    prot := 3
    if n > 1 and b != 0:
        prot = __mm_prot("vm_map", b)
    tag := 0
    if n > 2 and c != 0:
        tag = __str_addr(__nat_cstr("vm_map", c, "l'étiquette"))
    len := (size + 4095) // 4096 * 4096
    if __windows():
        pw := __wincall("VirtualAlloc", 0, len, 12288, __mm_win_prot(prot))
        if pw == 0:
            __mm_fail("vm_map", "VirtualAlloc a échoué (code " + __int_to_str(__pw_last()) + ")")
        return __mm_register_map(pw, len, len, prot, tag)
    p := __syscall(9, 0, len, prot, 34, -1, 0)
    if p < 0 and p > -4096:
        __mm_fail("vm_map", "mmap a échoué : " + __nat_errno_text(0 - p))
    return __mm_register_map(p, len, len, prot, tag)

func __nat__native_memory__vm_unmap(n: int, a: int) -> int:
    __nat_range("vm_unmap", n, 1, 1)
    b := __mm_mapped("vm_unmap", a)
    __munmap(__load64(b + 16), __load64(b + 80))
    __mm_remove(b)
    return 0

func __nat__native_memory__vm_protect(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("vm_protect", n, 4, 4)
    blk := __mm_mapped("vm_protect", a)
    off := __nat_int("vm_protect", b, "l'offset")
    len := __nat_int("vm_protect", c, "la longueur")
    prot := __mm_prot("vm_protect", d)
    __mm_page_range("vm_protect", blk, off, len)
    if __windows():
        old := __alloc_raw(8)
        if __rt_w32(__wincall("VirtualProtect", __load64(blk + 16) + off, len, __mm_win_prot(prot), old)) == 0:
            __dyn_err("IoError", "'vm_protect' : VirtualProtect a échoué")
        pw := off // 4096
        while pw < (off + len) // 4096:
            __store8(__load64(blk + 88) + pw, prot)
            pw += 1
        return 0
    r := __syscall(10, __load64(blk + 16) + off, len, prot)
    if r != 0:
        __dyn_err("IoError", "'vm_protect' : mprotect a échoué : " + __nat_errno_text(0 - r))
    pg := off // 4096
    while pg < (off + len) // 4096:
        __store8(__load64(blk + 88) + pg, prot)
        pg += 1
    return 0

func __nat__native_memory__vm_prot(n: int, a: int, b: int) -> int:
    __nat_range("vm_prot", n, 2, 2)
    blk := __mm_mapped("vm_prot", a)
    off := __nat_int("vm_prot", b, "l'offset")
    if off < 0 or off >= __load64(blk + 80):
        __dyn_err("IndexError", "'vm_prot' : offset hors région")
    return __dyn_int(__load8(__load64(blk + 88) + off // 4096))

func __nat__native_memory__vm_lock(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("vm_lock", n, 4, 4)
    blk := __mm_mapped("vm_lock", a)
    off := __nat_int("vm_lock", b, "l'offset")
    len := __nat_int("vm_lock", c, "la longueur")
    lock := __nat_bool("vm_lock", d, "lock")
    __mm_page_range("vm_lock", blk, off, len)
    if __windows():
        okw := 0
        if lock:
            okw = __rt_w32(__wincall("VirtualLock", __load64(blk + 16) + off, len))
        else:
            okw = __rt_w32(__wincall("VirtualUnlock", __load64(blk + 16) + off, len))
        if okw == 0:
            __dyn_err("IoError", "'vm_lock' : verrouillage refusé")
        return 0
    nr := 150
    nm := "munlock"
    if lock:
        nr = 149
        nm = "mlock"
    r := __syscall(nr, __load64(blk + 16) + off, len)
    if r != 0:
        __dyn_err("IoError", "'vm_lock' : " + nm + " refusé : " + __nat_errno_text(0 - r) + " (RLIMIT_MEMLOCK ?)")
    return 0

func __nat__native_memory__vm_advise(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("vm_advise", n, 4, 4)
    blk := __mm_mapped("vm_advise", a)
    off := __nat_int("vm_advise", b, "l'offset")
    len := __nat_int("vm_advise", c, "la longueur")
    adv := __nat_cstr("vm_advise", d, "le conseil")
    __mm_page_range("vm_advise", blk, off, len)
    if __windows():
        __dyn_err("IoError", "'vm_advise' : non supporté sous Windows")
    code := -1
    if __rt_str_eq(adv, "normal"):
        code = 0
    elif __rt_str_eq(adv, "random"):
        code = 1
    elif __rt_str_eq(adv, "sequential"):
        code = 2
    elif __rt_str_eq(adv, "willneed"):
        code = 3
    elif __rt_str_eq(adv, "dontneed"):
        code = 4
    if code < 0:
        __mm_arg("vm_advise", "conseil inconnu '" + adv + "' (normal, sequential, random, willneed, dontneed)")
    r := __syscall(28, __load64(blk + 16) + off, len, code)
    if r != 0:
        __dyn_err("IoError", "'vm_advise' : madvise a échoué : " + __nat_errno_text(0 - r))
    return 0

func __nat__native_memory__vm_resident(n: int, a: int, b: int, c: int) -> int:
    __nat_range("vm_resident", n, 3, 3)
    blk := __mm_mapped("vm_resident", a)
    off := __nat_int("vm_resident", b, "l'offset")
    len := __nat_int("vm_resident", c, "la longueur")
    __mm_page_range("vm_resident", blk, off, len)
    if __windows():
        __dyn_err("IoError", "'vm_resident' : non supporté sous Windows")
    pages := len // 4096
    vec := __alloc_raw(pages + 8)
    r := __syscall(27, __load64(blk + 16) + off, len, vec)
    if r != 0:
        __dyn_err("IoError", "'vm_resident' : mincore a échoué : " + __nat_errno_text(0 - r))
    k := 0
    i := 0
    while i < pages:
        k += __load8(vec + i) & 1
        i += 1
    return __dyn_int(k)

func __nat__native_memory__vm_map_file(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int,
                                       a7: int, x: int) -> int:
    __nat_range("vm_map_file", n, 1, 6)
    path := __nat_cstr("vm_map_file", a0, "le chemin")
    writable := __mm_bool_opt("vm_map_file", n, 1, a1, "inscriptible")
    shared := __mm_bool_opt("vm_map_file", n, 2, a2, "partagé")
    offset := 0
    if n > 3 and a3 != 0:
        offset = __nat_int("vm_map_file", a3, "l'offset")
    length := -1
    if n > 4 and a4 != 0:
        length = __nat_int("vm_map_file", a4, "la longueur")
    tag := __str_addr(path)
    if n > 5 and a5 != 0:
        tag = __str_addr(__nat_cstr("vm_map_file", a5, "l'étiquette"))
    if offset < 0 or offset % 4096 != 0:
        __mm_arg("vm_map_file", "offset non aligné sur la page")
    if __windows():
        __dyn_err("IoError", "'vm_map_file' : non supporté sous Windows")
    flags := 0
    if writable and shared:
        flags = 2
    fd := __syscall(2, __nat_c(path), flags)
    if fd < 0:
        __dyn_err("IoError", "'vm_map_file' : open('" + path + "') : " + __nat_errno_text(0 - fd))
    st := __alloc_raw(144)
    if __syscall(5, fd, st) != 0:
        __syscall(3, fd)
        __dyn_err("IoError", "'vm_map_file' : fstat a échoué")
    if (__load32(st + 24) & 61440) != 32768:
        __syscall(3, fd)
        __mm_arg("vm_map_file", "'" + path + "' n'est pas un fichier régulier")
    fsize := __load64(st + 48)
    if offset >= fsize:
        __syscall(3, fd)
        __mm_arg("vm_map_file", "offset au-delà de la fin du fichier")
    avail := fsize - offset
    if length < 0:
        length = avail
    if length < 1 or length > avail:
        __syscall(3, fd)
        __mm_arg("vm_map_file", "longueur invalide (fichier : " + __int_to_str(avail) + " octets disponibles)")
    mapLen := (length + 4095) // 4096 * 4096
    prot := 1
    if writable:
        prot = 3
    mf := 2
    if shared:
        mf = 1
    p := __syscall(9, 0, mapLen, prot, mf, fd, offset)
    __syscall(3, fd)
    if p < 0 and p > -4096:
        __mm_fail("vm_map_file", "mmap a échoué : " + __nat_errno_text(0 - p))
    return __mm_register_map(p, length, mapLen, prot, tag)

func __nat__native_memory__vm_sync(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_range("vm_sync", n, 4, 4)
    blk := __mm_mapped("vm_sync", a)
    off := __nat_int("vm_sync", b, "l'offset")
    len := __nat_int("vm_sync", c, "la longueur")
    asy := __nat_bool("vm_sync", d, "async")
    __mm_page_range("vm_sync", blk, off, len)
    if __windows():
        if __rt_w32(__wincall("FlushViewOfFile", __load64(blk + 16) + off, len)) == 0:
            __dyn_err("IoError", "'vm_sync' : FlushViewOfFile a échoué")
        return 0
    fl := 4
    if asy:
        fl = 1
    r := __syscall(26, __load64(blk + 16) + off, len, fl)
    if r != 0:
        __dyn_err("IoError", "'vm_sync' : msync a échoué : " + __nat_errno_text(0 - r))
    return 0

# ---- net.interfaces : getifaddrs de la glibc, par netlink (RTM_GETLINK puis RTM_GETADDR) ----

# Envoie une requête de vidage et renvoie la liste native des messages (str) de type `want`, ou -errno.
func __nif_dump(fd: int, typ: int, want: int, seq: int) -> int:
    req := __alloc_raw(24)
    __zero(req, 24)
    __store32(req, 17)
    __store16(req + 4, typ)
    __store16(req + 6, 769)
    __store32(req + 8, seq)
    sa := __alloc_raw(16)
    __zero(sa, 16)
    __store16(sa, 16)
    r := __syscall(44, fd, req, 20, 0, sa, 12)
    if r < 0:
        return r
    out := __rt_list_new(0)
    buf := __alloc_raw(65536)
    while true:
        n := __syscall(45, fd, buf, 65536, 0, 0, 0)
        if n < 0:
            if n == -4:
                continue
            return n
        if n == 0:
            return out
        p := 0
        while p + 16 <= n:
            len := __load32(buf + p)
            t := __load16(buf + p + 4)
            if len < 16 or p + len > n:
                return out
            if t == 3:
                return out
            if t == 2:
                e := __load32(buf + p + 16)
                if e >= 2147483648:
                    return e - 4294967296
                return out
            if t == want:
                __rt_list_push(out, __str_addr(__nat_make(buf + p, len)))
            p += (len + 3) & ~3

func __nif_flags(fl: int) -> int:
    l := __dyn_list_new(0)
    names := __nat_split_bytes("1:up,2:broadcast,8:loopback,16:point_to_point,64:running,4096:multicast,256:promiscuous", 44)
    i := 0
    while i < __load64(names):
        it := __as_str(__rt_vec_at(names, i))
        q := __dyn_find_bytes(it, ":", 0)
        if (fl & __rt_str_to_int(__nat_sub(it, 0, q))) != 0:
            __dyn_list_push(l, __dyn_str(__nat_sub(it, q + 1, __nat_blen(it) - q - 1)))
        i += 1
    return l

func __nif_addr(fam: int, p: int) -> int:
    if fam == 4:
        return __dyn_str(__ns_ntop4(p))
    return __dyn_str(__ns_ntop6(p))

func __nif_mask(fam: int, prefix: int) -> int:
    m := __alloc_raw(16)
    __zero(m, 16)
    k := 0
    while k < prefix and k < 128:
        __store8(m + k // 8, __load8(m + k // 8) | (128 >> (k % 8)))
        k += 1
    return __nif_addr(fam, m)

func __nat__native_net__interfaces(n: int) -> int:
    __nat_range("interfaces", n, 0, 0)
    if __windows():
        return __pw_interfaces()
    fd := __syscall(41, 16, 524291, 0)
    if fd < 0:
        return __dyn_int(fd)
    links := __nif_dump(fd, 18, 16, 1)
    if links < 0 and links > -4096:
        __syscall(3, fd)
        return __dyn_int(links)
    addrs := __nif_dump(fd, 22, 20, 2)
    __syscall(3, fd)
    if addrs < 0 and addrs > -4096:
        return __dyn_int(addrs)
    # index -> [nom, drapeaux]
    idx := __rt_dict_new(16)
    out := __dyn_list_new(0)
    i := 0
    while i < __load64(links):
        m := __as_str(__rt_vec_at(links, i))
        b := __nat_bp(m)
        ln := __nat_blen(m)
        index := __load32(b + 20)
        flags := __load32(b + 24)
        name := ""
        p := 32
        while p + 4 <= ln:
            al := __load16(b + p)
            if al < 4:
                break
            if __load16(b + p + 2) == 3:
                name = __nat_from_c(b + p + 4)
            p += (al + 3) & ~3
        info := __alloc(16)
        __store64(info, __str_addr(name))
        __store64(info + 8, flags)
        __rt_dict_set(idx, index, info, 0)
        e := __dyn_list_new(0)
        __dyn_list_push(e, __dyn_str(name))
        __dyn_list_push(e, __dyn_int(0))
        __dyn_list_push(e, 0)
        __dyn_list_push(e, 0)
        __dyn_list_push(e, 0)
        __dyn_list_push(e, __nif_flags(flags))
        __dyn_list_push(e, __dyn_int(index))
        __dyn_list_push(out, e)
        i += 1
    i = 0
    while i < __load64(addrs):
        m := __as_str(__rt_vec_at(addrs, i))
        b := __nat_bp(m)
        ln := __nat_blen(m)
        af := __load8(b + 16)
        prefix := __load8(b + 17)
        index := __load32(b + 20)
        fam := 0
        if af == 2:
            fam = 4
        elif af == 10:
            fam = 6
        if fam == 0:
            i += 1
            continue
        name := ""
        flags := 0
        ie := __rt_dict_index(idx, index, 0)
        if ie >= 0:
            info := __load64(__load64(idx + 32) + 8 * ie)
            name = __as_str(__load64(info))
            flags = __load64(info + 8)
        addr := 0
        dst := 0
        p := 24
        while p + 4 <= ln:
            al := __load16(b + p)
            if al < 4:
                break
            at := __load16(b + p + 2)
            v := b + p + 4
            if at == 1:
                if addr != 0:
                    dst = v
                else:
                    addr = v
            elif at == 2:
                if addr != 0:
                    dst = addr
                addr = v
            elif at == 4:
                dst = v
            elif at == 3:
                name = __nat_from_c(v)
            p += (al + 3) & ~3
        e := __dyn_list_new(0)
        __dyn_list_push(e, __dyn_str(name))
        __dyn_list_push(e, __dyn_int(fam))
        if addr != 0:
            __dyn_list_push(e, __nif_addr(fam, addr))
        else:
            __dyn_list_push(e, 0)
        __dyn_list_push(e, __nif_mask(fam, prefix))
        if fam == 4 and (flags & 2) != 0 and dst != 0:
            __dyn_list_push(e, __nif_addr(fam, dst))
        else:
            __dyn_list_push(e, 0)
        __dyn_list_push(e, __nif_flags(flags))
        __dyn_list_push(e, __dyn_int(index))
        __dyn_list_push(out, e)
        i += 1
    return out

