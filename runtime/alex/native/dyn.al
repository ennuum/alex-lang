

# ---- État et valeurs de base ---------------------------------------------------------------------------------

func __dyn_ds() -> int:
    return __load64(__globals_start())

func __dyn_init():
    ds := __alloc(512)
    __store64(ds + 344, 16384)
    __store64(ds + 384, 16384)
    __store64(ds + 392, 16384)
    __store64(__globals_start(), ds)
    t := __alloc(16)
    __store64(t, 3)
    __store64(t + 8, 1)
    f := __alloc(16)
    __store64(f, 3)
    __store64(ds, t)
    __store64(ds + 8, f)
    __store64(ds + 16, __rt_dict_new(16))
    __store64(ds + 24, __rt_dict_new(64))
    __store64(ds + 32, __rt_dict_new(16))
    __store64(ds + 40, __rt_dict_new(8))
    __store64(ds + 48, __rt_list_new(0))
    __store64(ds + 64, __rt_dict_new(16))
    # Pile : jusqu'à 512 Mio (récursion profonde, comme les 100000 frames de la VM), si la limite dure le permet.
    lim := __alloc_raw(16)
    if __syscall(97, 3, lim) == 0:
        want := 536870912
        if __load64(lim + 8) >= 0 and __load64(lim + 8) < want:
            want = __load64(lim + 8)
        if __load64(lim) >= 0 and __load64(lim) < want:
            __store64(lim, want)
            __syscall(160, 3, lim)
    # ALEX_EXE : compilateur d'origine, sauf si l'environnement le fixe déjà (lancé depuis alex)
    ic := __alloc(8 * 1280)
    k := 0
    while k < 1280:
        o := __alloc_raw(16)
        __store64(o, 1)
        __store64(o + 8, k - 256)
        __store64(ic + 8 * k, o)
        k += 1
    __store64(ds + 400, ic)
    exe := __dyn_alex_exe()
    if __nat_blen(exe) > 0 and __nat_env_find("ALEX_EXE") < 0:
        __rt_list_push(__nat_env(), __str_addr("ALEX_EXE=" + exe))

func __dyn_kind(v: int) -> int:
    if v == 0:
        return 0
    return __load64(v)

# Boîte [genre][charge] (int, float, char, byte) : chemin rapide de l'allocateur (case de 24 octets, classe 1,
# prise directement dans sa liste libre, comptes du GC au fil de l'eau), sinon allocation ordinaire.
func __dyn_box(k: int, x: int) -> int:
    st := __state()
    slot := __load64(st + 8)
    if slot != 0:
        ds := __load64(__globals_start())
        if ds != 0:
            c := __load64(ds + 384) - 1
            if c > 0:
                __store64(ds + 384, c)
                __store64(st + 8, __load64(slot))
                __store64(slot, 261) # alloué, sans pointeurs (raw), classe 1
                __store64(slot + 8, k)
                __store64(slot + 16, x)
                __store64(st + 256, __load64(st + 256) + 24)
                return slot + 8
    o := __alloc_raw(16)
    __store64(o, k)
    __store64(o + 8, x)
    return o

# Petits entiers (-256..1023) partagés : boîtes préallouées (état [400]), comme des valeurs immuables.
func __dyn_int(i: int) -> int:
    if __rt_ule(i + 256, 1279):
        ds := __load64(__globals_start())
        if ds != 0:
            t := __load64(ds + 400)
            if t != 0:
                return __load64(t + 8 * (i + 256))
    return __dyn_box(1, i)

func __dyn_float(x: float) -> int:
    return __dyn_box(2, __f2bits(x))

func __dyn_fv(v: int) -> float:
    return __bits2f(__load64(v + 8))

func __dyn_iv(v: int) -> int:
    return __load64(v + 8)

func __dyn_bool(b: bool) -> int:
    if b:
        return __load64(__dyn_ds())
    return __load64(__dyn_ds() + 8)

func __dyn_char(c: int) -> int:
    return __dyn_box(4, c)

func __dyn_byte(b: int) -> int:
    o := __alloc_raw(16)
    __store64(o, 5)
    __store64(o + 8, b & 255)
    return o

# Valeur str : [6][chaîne][nombre de points de code + 1, 0 tant qu'inconnu][curseur : (indice << 32) | octet du
# dernier point de code atteint] — chaînes immuables : le nombre est calculé une fois (égal à la longueur en octets
# pour une chaîne ASCII, dont l'indexation est alors directe) et le curseur rend le parcours séquentiel linéaire.
func __dyn_str(s: str) -> int:
    o := __alloc(32)
    __store64(o, 6)
    __store64(o + 8, __str_addr(s))
    return o

func __dyn_svlen(v: int) -> int:
    c := __load64(v + 16)
    if c != 0:
        return c - 1
    n := __rt_str_len(__as_str(__load64(v + 8)))
    __store64(v + 16, n + 1)
    return n

# Point de code d'indice p (0 <= p < longueur).
func __dyn_svchar(v: int, p: int) -> int:
    a := __load64(v + 8)
    n := __load64(a)
    if __dyn_svlen(v) == n:
        return __load8(a + 8 + p)
    if n >= 2147483648:
        return __rt_str_char_at(__as_str(a), p)
    cur := __load64(v + 24)
    ci := cur >> 32
    bi := cur & 4294967295
    if p < ci:
        ci = 0
        bi = 0
    while ci < p:
        bi += 1
        while bi < n and (__load8(a + 8 + bi) & 192) == 128:
            bi += 1
        ci += 1
    __store64(v + 24, (ci << 32) | bi)
    b := __load8(a + 8 + bi)
    if b < 128:
        return b
    extra := 1
    cp := b & 31
    if b >= 240:
        extra = 3
        cp = b & 7
    elif b >= 224:
        extra = 2
        cp = b & 15
    j := 1
    while j <= extra and bi + j < n:
        cp = (cp << 6) | (__load8(a + 8 + bi + j) & 63)
        j += 1
    return cp

# Chaîne native d'une valeur str.
func __dyn_sv(v: int) -> str:
    return __as_str(__load64(v + 8))

func __dyn_list_wrap(l: int) -> int:
    o := __alloc(24)
    __store64(o, 7)
    __store64(o + 8, l)
    return o

func __dyn_list_new(n: int) -> int:
    return __dyn_list_wrap(__rt_list_new(n))

# Liste native d'une valeur list.
func __dyn_lv(v: int) -> int:
    return __load64(v + 8)

func __dyn_list_len(v: int) -> int:
    return __load64(__load64(v + 8))

func __dyn_list_at(v: int, i: int) -> int:
    return __load64(__load64(__load64(v + 8) + 16) + 8 * i)

func __dyn_list_put(v: int, i: int, x: int):
    __store64(__load64(__load64(v + 8) + 16) + 8 * i, x)

func __dyn_list_push(v: int, x: int):
    __rt_list_push(__load64(v + 8), x)

func __dyn_tuple_new(n: int) -> int:
    o := __alloc(16 + 8 * n)
    __store64(o, 8)
    __store64(o + 8, n)
    return o

func __dyn_tuple_len(t: int) -> int:
    return __load64(t + 8)

func __dyn_tuple_at(t: int, i: int) -> int:
    return __load64(t + 16 + 8 * i)

func __dyn_tuple_put(t: int, i: int, x: int):
    __store64(t + 16 + 8 * i, x)

func __dyn_dict_new() -> int:
    o := __alloc(32)
    __store64(o, 9)
    __store64(o + 8, __rt_dict_new(8))
    return o

# Dict natif d'une valeur dict.
func __dyn_dv(v: int) -> int:
    return __load64(v + 8)

func __dyn_dict_len(v: int) -> int:
    return __load64(__load64(v + 8))

func __dyn_is(v: int, k: int) -> bool:
    return v != 0 and __load64(v) == k

func __dyn_is_str(v: int) -> bool:
    return v != 0 and __load64(v) == 6

# Erreur d'exécution (exception rattrapable, comme une RuntimeError de la VM).
func __dyn_err(t: str, m: str):
    __rt_throw(__rt_exc_new(t, m))

# ---- Noms de types, vérité, égalité, hachage (Value.cpp) ------------------------------------------------------

func __dyn_type_name(v: int) -> str:
    k := __dyn_kind(v)
    if k == 0:
        return "null"
    if k == 1:
        return "int"
    if k == 2:
        return "float"
    if k == 3:
        return "bool"
    if k == 4:
        return "char"
    if k == 5:
        return "byte"
    if k == 6:
        return "str"
    if k == 7:
        return "list"
    if k == 8:
        return "tuple"
    if k == 9:
        return "dict"
    if k == 10:
        return "function"
    if k == 11:
        return "native"
    if k == 12:
        return "instance"
    if k == 13:
        return "exception"
    if k == 14:
        return "cell"
    if k == 15:
        if __load64(v + 16) != 0:
            return "task"
        return "future"
    return "obj"

func __dyn_truthy(v: int) -> bool:
    k := __dyn_kind(v)
    if k == 0:
        return false
    if k == 3 or k == 1:
        return __load64(v + 8) != 0
    if k == 2:
        return __dyn_fv(v) != 0.0
    if k == 6:
        return __load64(__load64(v + 8)) != 0
    return true

# Égalité exacte int == float (sans perte au-delà de 2^53) : le flottant doit être entier et représentable.
func __dyn_int_eq_float(i: int, f: float) -> bool:
    if not (f == __rt_floor(f)):
        return false
    if f >= 9223372036854775808.0 or f <= -9223372036854775808.0:
        if f == -9223372036854775808.0:
            return i == -9223372036854775807 - 1
        return false
    return __f2i(f) == i

func __dyn_eq(a: int, b: int) -> bool:
    if a == b and (a == 0 or __load64(a) != 2): # même objet : égal, sauf un flottant NaN (comparé par valeur)
        return true
    ka := __dyn_kind(a)
    kb := __dyn_kind(b)
    if ka != kb:
        if ka == 1 and kb == 2:
            return __dyn_int_eq_float(__load64(a + 8), __dyn_fv(b))
        if ka == 2 and kb == 1:
            return __dyn_int_eq_float(__load64(b + 8), __dyn_fv(a))
        return false
    if ka == 0:
        return true
    if ka == 1 or ka == 3 or ka == 4 or ka == 5:
        return __load64(a + 8) == __load64(b + 8)
    if ka == 2:
        return __dyn_fv(a) == __dyn_fv(b)
    if ka == 6:
        return __rt_str_eq(__dyn_sv(a), __dyn_sv(b))
    if ka == 7 or ka == 8 or ka == 9:
        ds := __dyn_ds()
        depth := __load64(ds + 56) + 1
        if depth > 2000:
            __store64(ds + 56, 0)
            __dyn_err("RecursionError", "comparaison de structures trop profonde (structure cyclique ?)")
        __store64(ds + 56, depth)
        r := __dyn_eq_coll(a, b, ka)
        d2 := __load64(ds + 56)
        if d2 > 0:
            __store64(ds + 56, d2 - 1)
        return r
    return false

func __dyn_eq_coll(a: int, b: int, k: int) -> bool:
    if k == 7:
        n := __dyn_list_len(a)
        if n != __dyn_list_len(b):
            return false
        i := 0
        while i < n:
            if not __dyn_eq(__dyn_list_at(a, i), __dyn_list_at(b, i)):
                return false
            i += 1
        return true
    if k == 8:
        n2 := __load64(a + 8)
        if n2 != __load64(b + 8):
            return false
        j := 0
        while j < n2:
            if not __dyn_eq(__load64(a + 16 + 8 * j), __load64(b + 16 + 8 * j)):
                return false
            j += 1
        return true
    da := __dyn_dv(a)
    db := __dyn_dv(b)
    if __load64(da) != __load64(db):
        return false
    used := __load64(da + 8)
    e := 0
    while e < used:
        if __load64(__load64(da + 40) + 8 * e) >= 0:
            k2 := __load64(__load64(da + 24) + 8 * e)
            x := __rt_dict_index(db, k2, 3)
            if x < 0:
                return false
            if not __dyn_eq(__load64(__load64(da + 32) + 8 * e), __load64(__load64(db + 32) + 8 * x)):
                return false
        e += 1
    return true

func __dyn_hashable(v: int) -> bool:
    k := __dyn_kind(v)
    if k == 0 or k == 1 or k == 3 or k == 4 or k == 5 or k == 6:
        return true
    if k == 2:
        x := __dyn_fv(v)
        return x == x
    if k == 8:
        n := __load64(v + 8)
        i := 0
        while i < n:
            if not __dyn_hashable(__load64(v + 16 + 8 * i)):
                return false
            i += 1
        return true
    return false

# Hachage interne des clés (toujours >= 0) ; 1 et 1.0 hachent de même (ils sont égaux).
func __dyn_hash(v: int) -> int:
    k := __dyn_kind(v)
    if k == 0:
        return 40503
    if k == 6:
        return __rt_hash(__load64(v + 8), 1)
    if k == 1: # comme un flottant entier égal (1 == 1.0 : même clé)
        return __rt_hash(__load64(v + 8), 0)
    if k == 2:
        x := __dyn_fv(v)
        if x == __rt_floor(x) and x < 9223372036854775808.0 and x >= -9223372036854775808.0:
            return __rt_hash(__f2i(x), 0)
        return __rt_hash(__load64(v + 8), 2)
    if k == 8:
        h := 2685821657736338717
        n := __load64(v + 8)
        i := 0
        while i < n:
            h = (h ^ (__dyn_hash(__load64(v + 16 + 8 * i)) + 2654435769 + (h << 6) + (h >> 2))) & 9223372036854775807
            i += 1
        return h
    return __rt_hash(__load64(v + 8) + 1000003 * k, 0)

func __dyn_need_hashable(k: int, ctx: str):
    if not __dyn_hashable(k):
        __dyn_err("TypeError", "clé de type '" + __dyn_type_name(k) + "' non hashable" + ctx + " (Addendum A.8)")

# ---- Affichage (toDisplayString) -----------------------------------------------------------------------------

# Nom affiché d'une fonction : sans qualificatif de module (« $mod…:: ») ni suffixe « @ligne:col#n ».
func __dyn_fn_display(name: str) -> str:
    p := __str_addr(name)
    n := __load64(p)
    start := 0
    i := 0
    while i + 1 < n:
        if __load8(p + 8 + i) == 58 and __load8(p + 9 + i) == 58:
            start = i + 2
        i += 1
    stop := n
    j := start
    while j < n:
        if __load8(p + 8 + j) == 64:
            stop = j
            break
        j += 1
    return __dyn_substr(name, start, stop)

# Octets [a, b) d'une chaîne native.
func __dyn_substr(s: str, a: int, b: int) -> str:
    if a <= 0 and b >= __load64(__str_addr(s)):
        return s
    if b <= a:
        return ""
    t := __rt_str_new(b - a)
    __copy(t + 8, __str_addr(s) + 8 + a, b - a)
    return __as_str(t)

# Nom de type d'une instance, sans qualificatif de module.
func __dyn_short_type(tn: str) -> str:
    p := __str_addr(tn)
    n := __load64(p)
    start := 0
    i := 0
    while i + 1 < n:
        if __load8(p + 8 + i) == 58 and __load8(p + 9 + i) == 58:
            start = i + 2
        i += 1
    return __dyn_substr(tn, start, n)

func __dyn_displaying(o: int) -> bool:
    l := __load64(__dyn_ds() + 48)
    n := __load64(l)
    i := 0
    while i < n:
        if __load64(__load64(l + 16) + 8 * i) == o:
            return true
        i += 1
    return false

func __dyn_display_push(o: int):
    __rt_list_push(__load64(__dyn_ds() + 48), o)

func __dyn_display_pop():
    l := __load64(__dyn_ds() + 48)
    __store64(l, __load64(l) - 1)

func __dyn_display(v: int) -> str:
    k := __dyn_kind(v)
    if k == 0:
        return "null"
    if k == 6:
        return __dyn_sv(v)
    if k == 1:
        return __int_to_str(__load64(v + 8))
    if k == 2:
        return __rt_float_to_str(__dyn_fv(v))
    if k == 3:
        if __load64(v + 8) != 0:
            return "true"
        return "false"
    if k == 4:
        return __rt_char_str(__load64(v + 8))
    if k == 5:
        return __int_to_str(__load64(v + 8))
    if k == 7:
        if __dyn_displaying(v):
            return "[...]"
        __dyn_display_push(v)
        sb := __rt_sb_new()
        __rt_sb_add(sb, "[")
        n := __dyn_list_len(v)
        i := 0
        while i < n:
            if i > 0:
                __rt_sb_add(sb, ", ")
            __rt_sb_add(sb, __dyn_display(__dyn_list_at(v, i)))
            i += 1
        __rt_sb_add(sb, "]")
        __dyn_display_pop()
        return __rt_sb_str(sb)
    if k == 8:
        if __dyn_displaying(v):
            return "(...)"
        __dyn_display_push(v)
        sb2 := __rt_sb_new()
        __rt_sb_add(sb2, "(")
        n2 := __load64(v + 8)
        j := 0
        while j < n2:
            if j > 0:
                __rt_sb_add(sb2, ", ")
            __rt_sb_add(sb2, __dyn_display(__load64(v + 16 + 8 * j)))
            j += 1
        if n2 == 1:
            __rt_sb_add(sb2, ",")
        __rt_sb_add(sb2, ")")
        __dyn_display_pop()
        return __rt_sb_str(sb2)
    if k == 9:
        if __dyn_displaying(v):
            return "{...}"
        __dyn_display_push(v)
        sb3 := __rt_sb_new()
        __rt_sb_add(sb3, "{")
        d := __dyn_dv(v)
        used := __load64(d + 8)
        first := true
        e := 0
        while e < used:
            if __load64(__load64(d + 40) + 8 * e) >= 0:
                if not first:
                    __rt_sb_add(sb3, ", ")
                first = false
                __rt_sb_add(sb3, __dyn_display(__load64(__load64(d + 24) + 8 * e)))
                __rt_sb_add(sb3, ": ")
                __rt_sb_add(sb3, __dyn_display(__load64(__load64(d + 32) + 8 * e)))
            e += 1
        __rt_sb_add(sb3, "}")
        __dyn_display_pop()
        return __rt_sb_str(sb3)
    if k == 10:
        return "<function " + __dyn_fn_display(__as_str(__load64(v + 16))) + ">"
    if k == 11:
        return "<native " + __as_str(__load64(v + 16)) + ">"
    if k == 12:
        return "<" + __dyn_short_type(__as_str(__load64(v + 8))) + " instance>"
    if k == 13:
        e2 := __load64(v + 8)
        return __as_str(__load64(e2)) + ": " + __as_str(__load64(e2 + 8))
    if k == 14:
        return "<cell>"
    if k == 15:
        return __dyn_future_display(v)
    return "<obj>"

func __dyn_print(v: int):
    print(__dyn_display(v))

