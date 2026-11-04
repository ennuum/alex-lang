

# ---- Appels ---------------------------------------------------------------------------------------------------

# i-ème argument d'un appel (a0..a7 puis le tuple x).
func __dyn_argi(i: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int, x: int) -> int:
    if i == 0:
        return a0
    if i == 1:
        return a1
    if i == 2:
        return a2
    if i == 3:
        return a3
    if i == 4:
        return a4
    if i == 5:
        return a5
    if i == 6:
        return a6
    if i == 7:
        return a7
    if x == 0 or i - 8 >= __load64(x + 8):
        return 0
    return __load64(x + 16 + 8 * (i - 8))

# Appelle le code de f avec les valeurs de la liste native `args` (normalisées).
func __dyn_invoke_list(f: int, args: int) -> int:
    n := __load64(args)
    d := __load64(args + 16)
    v := __alloc(64)
    i := 0
    while i < 8 and i < n:
        __store64(v + 8 * i, __load64(d + 8 * i))
        i += 1
    x := 0
    if n > 8:
        x = __dyn_tuple_new(n - 8)
        j := 8
        while j < n:
            __store64(x + 16 + 8 * (j - 8), __load64(d + 8 * j))
            j += 1
    return __dyn_invoke(f, n, __load64(v), __load64(v + 8), __load64(v + 16), __load64(v + 24), __load64(v + 32),
                        __load64(v + 40), __load64(v + 48), __load64(v + 56), x)

func __dyn_recursion_error():
    __store64(__dyn_ds() + 80, 99990) # marge : le gestionnaire (et l'affichage de l'erreur) peuvent encore appeler
    __dyn_err("RecursionError", "profondeur d'appel maximale dépassée (100000)")

func __dyn_arity_error(f: int, n: int):
    amin := __load64(f + 24)
    amax := __load64(f + 32)
    s := "entre " + __int_to_str(amin) + " et " + __int_to_str(amax)
    if (amax & 32768) != 0:
        s = "au moins " + __int_to_str(amin)
    __dyn_err("ArgumentError", "'" + __dyn_fn_display(__as_str(__load64(f + 16))) + "' attend " + s +
              " argument(s), obtenu " + __int_to_str(n) + " (§7)")

func __dyn_call(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int, x: int) -> int:
    k := __dyn_kind(f)
    if k == 12:
        m := __dyn_find_method(__as_str(__load64(f + 8)), "__call__")
        if m != 0:
            f = __dyn_bind(m, f)
            k = 10
    if k == 11:
        return __dyn_invoke(f, n, a0, a1, a2, a3, a4, a5, a6, a7, x)
    if k != 10:
        __dyn_err("TypeError", "CALL : la valeur appelée n'est pas une fonction (type '" + __dyn_type_name(f) + "')")
    amin := __load64(f + 24)
    amax := __load64(f + 32)
    variadic := (amax & 32768) != 0
    fixed := amax & 32767
    if n < amin or (not variadic and n > amax):
        __dyn_arity_error(f, n)
    bound := __load64(f + 48)
    if not variadic and __load64(f + 56) == 0:
        if bound == 0:
            return __dyn_invoke(f, n, a0, a1, a2, a3, a4, a5, a6, a7, x)
        if n < 8: # méthode liée : receveur en tête, sans liste intermédiaire
            return __dyn_invoke(f, n + 1, bound, a0, a1, a2, a3, a4, a5, a6, 0)
    args := __rt_list_new(0)
    if bound != 0:
        __rt_list_push(args, bound)
    i := 0
    lim := n
    if variadic and lim > fixed:
        lim = fixed
    while i < lim:
        __rt_list_push(args, __dyn_argi(i, a0, a1, a2, a3, a4, a5, a6, a7, x))
        i += 1
    if variadic:
        while i < fixed: # paramètres fixes absents : null, puis la liste des arguments supplémentaires
            __rt_list_push(args, 0)
            i += 1
        rest := __dyn_list_new(0)
        j := fixed
        while j < n:
            __dyn_list_push(rest, __dyn_argi(j, a0, a1, a2, a3, a4, a5, a6, a7, x))
            j += 1
        __rt_list_push(args, rest)
    if __load64(f + 56) != 0:
        return __dyn_spawn(f, args)
    return __dyn_invoke_list(f, args)

# Appels depuis le runtime (surcharges, rappels) : 0, 1, 2 ou 3 arguments.
func __dyn_call0(f: int) -> int:
    return __dyn_call(f, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)

func __dyn_call1(f: int, a: int) -> int:
    return __dyn_call(f, 1, a, 0, 0, 0, 0, 0, 0, 0, 0)

func __dyn_call2(f: int, a: int, b: int) -> int:
    return __dyn_call(f, 2, a, b, 0, 0, 0, 0, 0, 0, 0)

func __dyn_call3(f: int, a: int, b: int, c: int) -> int:
    return __dyn_call(f, 3, a, b, c, 0, 0, 0, 0, 0, 0)

# CALL_SPREAD : f(*liste).
func __dyn_call_spread(f: int, l: int) -> int:
    if not __dyn_is(l, 7):
        __dyn_err("BytecodeError", "CALL_SPREAD : liste attendue")
    n := __dyn_list_len(l)
    v := __alloc(64)
    i := 0
    while i < 8 and i < n:
        __store64(v + 8 * i, __dyn_list_at(l, i))
        i += 1
    x := 0
    if n > 8:
        x = __dyn_tuple_new(n - 8)
        j := 8
        while j < n:
            __store64(x + 16 + 8 * (j - 8), __dyn_list_at(l, j))
            j += 1
    return __dyn_call(f, n, __load64(v), __load64(v + 8), __load64(v + 16), __load64(v + 24), __load64(v + 32),
                      __load64(v + 40), __load64(v + 48), __load64(v + 56), x)

# Nouvelle valeur fonction (globale d'une fonction du module, ou fermeture de MAKE_CLOSURE).
func __dyn_func_new(code: int, name: str, amin: int, amax: int, env: int, isAsync: int) -> int:
    f := __alloc(64)
    __store64(f, 10)
    __store64(f + 8, code)
    __store64(f + 16, __str_addr(name))
    __store64(f + 24, amin)
    __store64(f + 32, amax)
    __store64(f + 40, env)
    __store64(f + 56, isAsync)
    return f

func __dyn_native_new(code: int, name: str) -> int:
    f := __alloc(24)
    __store64(f, 11)
    __store64(f + 8, code)
    __store64(f + 16, __str_addr(name))
    return f

# Méthode liée : même code et même arité, receveur fixé (`self`).
func __dyn_bind(m: int, recv: int) -> int:
    b := __alloc(64)
    __copy(b, m, 64)
    __store64(b + 48, recv)
    return b

func __dyn_upvalue(f: int, i: int) -> int:
    env := __load64(f + 40)
    if env == 0 or i >= __load64(env + 8):
        __dyn_err("BytecodeError", "UPVALUE_CELL " + __int_to_str(i) + " : la fonction courante n'est pas une fermeture à ce rang")
    return __load64(env + 16 + 8 * i)

# ---- Globales ---------------------------------------------------------------------------------------------------

func __dyn_name_error(name: str):
    __dyn_err("NameError", "'" + name + "' n'est pas défini (§5.3)")

func __dyn_reg_method(name: str, g: int):
    __rt_dict_set(__load64(__dyn_ds() + 24), __str_addr(name), g, 1)
    c := __load64(__dyn_ds() + 408)
    if c != 0:
        __zero(c, 24 * 1024) # cache des méthodes invalidé

# ---- Classes (DEF_CLASS, ADD_INTERFACE), méthodes, sous-typage ---------------------------------------------------

func __dyn_class_rec(name: str) -> int:
    d := __load64(__dyn_ds() + 16)
    e := __rt_dict_index(d, __str_addr(name), 1)
    if e < 0:
        return 0
    return __load64(__load64(d + 32) + 8 * e)

func __dyn_def_class(nameV: int, baseV: int):
    if not __dyn_is_str(nameV):
        __dyn_err("TypeError", "DEF_CLASS (nom) : un nom (chaîne) est attendu sur la pile, obtenu '" + __dyn_type_name(nameV) + "'")
    if baseV != 0 and not __dyn_is_str(baseV):
        __dyn_err("TypeError", "DEF_CLASS (base) : un nom (chaîne) est attendu sur la pile, obtenu '" + __dyn_type_name(baseV) + "'")
    name := __dyn_sv(nameV)
    mc := __load64(__dyn_ds() + 408)
    if mc != 0:
        __zero(mc, 24 * 1024) # hiérarchie modifiée : cache des méthodes invalidé
    rec := __dyn_class_rec(name)
    if rec == 0:
        rec = __alloc(16)
        __store64(rec + 8, __rt_list_new(0))
        __rt_dict_set(__load64(__dyn_ds() + 16), __str_addr(name), rec, 1)
    if baseV == 0:
        __store64(rec, 0)
    else:
        __store64(rec, __load64(baseV + 8))

func __dyn_add_interface(nameV: int, ifaceV: int):
    if not __dyn_is_str(ifaceV):
        __dyn_err("TypeError", "ADD_INTERFACE (interface) : un nom (chaîne) est attendu sur la pile, obtenu '" + __dyn_type_name(ifaceV) + "'")
    if not __dyn_is_str(nameV):
        __dyn_err("TypeError", "ADD_INTERFACE (classe) : un nom (chaîne) est attendu sur la pile, obtenu '" + __dyn_type_name(nameV) + "'")
    name := __dyn_sv(nameV)
    rec := __dyn_class_rec(name)
    if rec == 0:
        rec = __alloc(16)
        __store64(rec + 8, __rt_list_new(0))
        __rt_dict_set(__load64(__dyn_ds() + 16), __str_addr(name), rec, 1)
    __rt_list_push(__load64(rec + 8), __load64(ifaceV + 8))

# Méthode `member` du type `t` ou de ses ancêtres (valeur fonction), 0 si aucune.
# Cache des méthodes (état [408] : tableau parcouru par le GC de 1024 x (classe, membre, globale)) : évite de
# construire « classe#membre » à chaque appel. Les clés sont des pointeurs de chaînes, gardées vivantes par le
# tableau (aucune réutilisation d'adresse) ; vidé à chaque enregistrement de méthode.
func __dyn_mcache() -> int:
    ds := __dyn_ds()
    c := __load64(ds + 408)
    if c == 0:
        c = __alloc(24 * 1024)
        __store64(ds + 408, c)
    return c

func __dyn_find_method(t: str, member: str) -> int:
    ta := __str_addr(t)
    ma := __str_addr(member)
    c := __dyn_mcache()
    h := ((ta >> 4) ^ (ma >> 3) ^ (ma >> 13)) & 1023
    e := c + 24 * h
    if __load64(e) == ta and __load64(e + 8) == ma:
        v := __load64(__globals_start() + 8 * __load64(e + 16))
        if __dyn_is(v, 10):
            return v
    g := __dyn_find_method_global(t, member)
    if g == -9223372036854775807 - 1:
        return 0
    __store64(e, ta)
    __store64(e + 8, ma)
    __store64(e + 16, g)
    return __load64(__globals_start() + 8 * g)

# Globale de la méthode `member` de la classe `t` ou d'un ancêtre (rang depuis __globals_start(), négatif pour une
# case de la VM placée sous l'image, comme sous Windows), ou -2^63 si aucune.
func __dyn_find_method_global(t: str, member: str) -> int:
    cur := t
    meths := __load64(__dyn_ds() + 24)
    depth := 0
    while depth < 256:
        key := cur + "#" + member
        e := __rt_dict_index(meths, __str_addr(key), 1)
        if e >= 0:
            g := __load64(__load64(meths + 32) + 8 * e)
            v := __load64(__globals_start() + 8 * g)
            if __dyn_is(v, 10):
                return g
        rec := __dyn_class_rec(cur)
        if rec == 0 or __load64(rec) == 0:
            return -9223372036854775807 - 1
        cur = __as_str(__load64(rec))
        depth += 1
    __dyn_err("TypeError", "hiérarchie de classes trop profonde ou cyclique en résolvant '" + t + "." + member + "'")
    return -9223372036854775807 - 1

func __dyn_subtype(name: str, target: str) -> bool:
    cur := name
    depth := 0
    while depth < 256:
        if cur == target:
            return true
        rec := __dyn_class_rec(cur)
        if rec == 0:
            return false
        ifs := __load64(rec + 8)
        n := __load64(ifs)
        i := 0
        while i < n:
            if __as_str(__load64(__load64(ifs + 16) + 8 * i)) == target:
                return true
            i += 1
        if __load64(rec) == 0:
            return false
        cur = __as_str(__load64(rec))
        depth += 1
    return false

func __dyn_instance_of(v: int, typeV: int) -> int:
    if not __dyn_is_str(typeV):
        __dyn_err("TypeError", "INSTANCE_OF (type) : un nom (chaîne) est attendu sur la pile, obtenu '" + __dyn_type_name(typeV) + "'")
    if __dyn_is(v, 12):
        return __dyn_bool(__dyn_subtype(__as_str(__load64(v + 8)), __dyn_sv(typeV)))
    return __dyn_bool(false)

func __dyn_exc_matches(e: int, typeV: int) -> int:
    if not __dyn_is_str(typeV):
        __dyn_err("TypeError", "EXC_MATCHES (type) : un nom (chaîne) est attendu sur la pile, obtenu '" + __dyn_type_name(typeV) + "'")
    if not __dyn_is(e, 13):
        return __dyn_bool(false)
    target := __dyn_sv(typeV)
    actual := __as_str(__load64(__load64(e + 8)))
    return __dyn_bool(target == "Exception" or actual == target or __dyn_subtype(actual, target))

func __dyn_get_super(recv: int, baseV: int, member: str) -> int:
    if not __dyn_is_str(baseV):
        __dyn_err("TypeError", "GET_SUPER (base) : un nom (chaîne) est attendu sur la pile, obtenu '" + __dyn_type_name(baseV) + "'")
    if not __dyn_is(recv, 12):
        __dyn_err("TypeError", "super : le receveur n'est pas une instance (type '" + __dyn_type_name(recv) + "')")
    m := __dyn_find_method(__dyn_sv(baseV), member)
    if m == 0:
        __dyn_err("AttributeError", "super : aucune classe parente ('" + __dyn_sv(baseV) + "' et ses ancêtres) ne définit '" + member + "'")
    return __dyn_bind(m, recv)

# ---- Instances et membres -----------------------------------------------------------------------------------------

func __dyn_new_instance(t: str) -> int:
    o := __alloc(24)
    __store64(o, 12)
    __store64(o + 8, __str_addr(t))
    __store64(o + 16, __rt_dict_new(8))
    return o

func __dyn_field_index(o: int, member: str) -> int:
    return __rt_dict_index(__load64(o + 16), __str_addr(member), 1)

func __dyn_get_member(o: int, member: str) -> int:
    k := __dyn_kind(o)
    if k == 13:
        e := __load64(o + 8)
        if member == "type":
            return __dyn_str(__as_str(__load64(e)))
        if member == "message":
            return __dyn_str(__as_str(__load64(e + 8)))
        if member == "trace":
            return __dyn_exc_trace(e)
        __dyn_err("AttributeError", "une exception n'a pas de membre '" + member + "' (membres exposés : 'type', 'message', 'trace', §9)")
    if k != 12:
        ext := __dyn_find_method(__dyn_type_name(o), member)
        if ext != 0:
            return __dyn_bind(ext, o)
        __dyn_err("TypeError", "le type '" + __dyn_type_name(o) + "' n'a pas de membre '" + member + "'")
    fi := __dyn_field_index(o, member)
    if fi >= 0:
        return __load64(__load64(__load64(o + 16) + 32) + 8 * fi)
    m := __dyn_find_method(__as_str(__load64(o + 8)), member)
    if m != 0:
        return __dyn_bind(m, o)
    __dyn_err("AttributeError", "'" + __as_str(__load64(o + 8)) + "' n'a pas de membre '" + member + "'")
    return 0

func __dyn_set_member(o: int, member: str, v: int):
    if not __dyn_is(o, 12):
        __dyn_err("TypeError", "le type '" + __dyn_type_name(o) + "' ne supporte pas l'affectation membre ('.')")
    __dyn_check_field(__as_str(__load64(o + 8)), member, v)
    __rt_dict_set(__load64(o + 16), __str_addr(member), v, 1)

# ---- Arithmétique, comparaisons, bit à bit (execArithmetic, execComparison, execBitwise) -----------------------

func __dyn_op_name(op: int) -> str:
    if op == 5:
        return "ADD"
    if op == 6:
        return "SUB"
    if op == 7:
        return "MUL"
    if op == 8:
        return "DIV"
    if op == 9:
        return "FLOORDIV"
    if op == 10:
        return "MOD"
    if op == 11:
        return "POW"
    if op == 14:
        return "LT"
    if op == 15:
        return "LE"
    if op == 16:
        return "GT"
    if op == 17:
        return "GE"
    if op == 19:
        return "BAND"
    if op == 20:
        return "BOR"
    if op == 21:
        return "BXOR"
    if op == 22:
        return "SHL"
    if op == 23:
        return "SHR"
    return "?"

func __dyn_type_error(op: int, l: int, r: int):
    __dyn_err("TypeError", "opérande(s) incompatible(s) pour '" + __dyn_op_name(op) + "' : '" + __dyn_type_name(l) + "' et '" +
              __dyn_type_name(r) + "'")

# Méthode de surcharge d'un opérateur binaire, et son reflet (`__radd__`...).
func __dyn_ovl_name(op: int) -> str:
    if op == 5:
        return "__add__"
    if op == 6:
        return "__sub__"
    if op == 7:
        return "__mul__"
    if op == 8:
        return "__truediv__"
    if op == 9:
        return "__floordiv__"
    if op == 10:
        return "__mod__"
    if op == 11:
        return "__pow__"
    if op == 12:
        return "__eq__"
    if op == 13:
        return "__ne__"
    if op == 14:
        return "__lt__"
    if op == 15:
        return "__le__"
    if op == 16:
        return "__gt__"
    if op == 17:
        return "__ge__"
    if op == 19:
        return "__and__"
    if op == 20:
        return "__or__"
    if op == 21:
        return "__xor__"
    if op == 22:
        return "__lshift__"
    if op == 23:
        return "__rshift__"
    if op == 33:
        return "__getitem__"
    return ""

func __dyn_ovl_rname(op: int) -> str:
    if op == 5:
        return "__radd__"
    if op == 6:
        return "__rsub__"
    if op == 7:
        return "__rmul__"
    if op == 8:
        return "__rtruediv__"
    if op == 9:
        return "__rfloordiv__"
    if op == 10:
        return "__rmod__"
    if op == 11:
        return "__rpow__"
    return ""

# Surcharge (tryOverload) : résultat, ou 1 (pas de surcharge applicable).
func __dyn_overload(op: int, a: int, b: int) -> int:
    name := __dyn_ovl_name(op)
    if (op == 6 or op == 5) and __dyn_is(b, 12) and __dyn_is(a, 1) and __load64(a + 8) == 0:
        neg := "__pos__"
        if op == 6:
            neg = "__neg__"
        mn := __dyn_find_method(__as_str(__load64(b + 8)), neg)
        if mn != 0:
            return __dyn_call0(__dyn_bind(mn, b))
    if __dyn_is(a, 12):
        m := __dyn_find_method(__as_str(__load64(a + 8)), name)
        if m == 0 and op == 13:
            m2 := __dyn_find_method(__as_str(__load64(a + 8)), "__eq__")
            if m2 != 0:
                return __dyn_bool(not __dyn_truthy(__dyn_call1(__dyn_bind(m2, a), b)))
        if m != 0:
            return __dyn_call1(__dyn_bind(m, a), b)
    rname := __dyn_ovl_rname(op)
    if rname != "" and __dyn_is(b, 12):
        mr := __dyn_find_method(__as_str(__load64(b + 8)), rname)
        if mr != 0:
            return __dyn_call1(__dyn_bind(mr, b), a)
    return 1

func __dyn_valid_cp(cp: int) -> bool:
    return cp >= 0 and cp <= 1114111 and not (cp >= 55296 and cp <= 57343)

func __dyn_cp_error(cp: int):
    __dyn_err("ValueError", "résultat hors du domaine d'un Char valide (point de code " + __int_to_str(cp) +
              ", attendu 0..0x10FFFF hors substituts UTF-16, §3.1)")

func __dyn_fpow(a: float, b: float) -> float:
    return __dyn_math_pow(a, b)

# ADD .. POW (opcodes 5 à 11).
func __dyn_arith(op: int, l: int, r: int) -> int:
    kl := __dyn_kind(l)
    kr := __dyn_kind(r)
    if kl == 12 or kr == 12:
        o := __dyn_overload(op, l, r)
        if o != 1:
            return o
    if kl == 1 and kr == 1:
        a := __load64(l + 8)
        b := __load64(r + 8)
        if op == 5:
            return __dyn_int(a + b)
        if op == 6:
            return __dyn_int(a - b)
        if op == 7:
            return __dyn_int(a * b)
        if op == 8:
            if b == 0:
                __dyn_err("ZeroDivisionError", "division par zéro (int / 0)")
            return __dyn_float(__i2f(a) / __i2f(b))
        if op == 9:
            if b == 0:
                __dyn_err("ZeroDivisionError", "division entière par zéro (int // 0)")
            return __dyn_int(a // b)
        if op == 10:
            if b == 0:
                __dyn_err("ZeroDivisionError", "modulo par zéro (int % 0)")
            return __dyn_int(a % b)
        if op == 11:
            if b >= 0:
                return __dyn_int(a ** b)
            return __dyn_float(__dyn_fpow(__i2f(a), __i2f(b)))
    if op == 5 and kl == 6 and kr == 6:
        return __dyn_str(__rt_concat(__dyn_sv(l), __dyn_sv(r)))
    if op == 5 and kl == kr and (kl == 7 or kl == 8):
        return __dyn_seq_concat(l, r)
    if op == 7 and ((kr == 1 and (kl == 7 or kl == 8 or kl == 6)) or (kl == 1 and (kr == 7 or kr == 8 or kr == 6))):
        if kr == 1:
            return __dyn_seq_repeat(l, __load64(r + 8))
        return __dyn_seq_repeat(r, __load64(l + 8))
    if kl == 4 and kr == 4 and op == 6:
        return __dyn_int(__load64(l + 8) - __load64(r + 8))
    if kl == 4 and kr == 1 and (op == 5 or op == 6):
        cp := __load64(l + 8) + __load64(r + 8)
        if op == 6:
            cp = __load64(l + 8) - __load64(r + 8)
        if not __dyn_valid_cp(cp):
            __dyn_cp_error(cp)
        return __dyn_char(cp)
    if kl == 1 and kr == 4 and op == 5:
        cp2 := __load64(r + 8) + __load64(l + 8)
        if not __dyn_valid_cp(cp2):
            __dyn_cp_error(cp2)
        return __dyn_char(cp2)
    if not ((kl == 1 or kl == 2) and (kr == 1 or kr == 2)):
        __dyn_type_error(op, l, r)
    x := 0.0
    y := 0.0
    if kl == 1:
        x = __i2f(__load64(l + 8))
    else:
        x = __dyn_fv(l)
    if kr == 1:
        y = __i2f(__load64(r + 8))
    else:
        y = __dyn_fv(r)
    if op == 5:
        return __dyn_float(x + y)
    if op == 6:
        return __dyn_float(x - y)
    if op == 7:
        return __dyn_float(x * y)
    if op == 8:
        if y == 0.0:
            __dyn_err("ZeroDivisionError", "division par zéro (float)")
        return __dyn_float(x / y)
    if op == 9:
        if y == 0.0:
            __dyn_err("ZeroDivisionError", "division entière par zéro (float)")
        return __dyn_float(__rt_floor(x / y))
    if op == 10:
        if y == 0.0:
            __dyn_err("ZeroDivisionError", "modulo par zéro (float)")
        return __dyn_float(__rt_floor_mod(x, y))
    if op == 11:
        return __dyn_float(__dyn_fpow(x, y))
    __dyn_type_error(op, l, r)
    return 0

func __dyn_seq_concat(l: int, r: int) -> int:
    if __load64(l) == 7:
        out := __dyn_list_new(0)
        n := __dyn_list_len(l)
        i := 0
        while i < n:
            __dyn_list_push(out, __dyn_list_at(l, i))
            i += 1
        m := __dyn_list_len(r)
        j := 0
        while j < m:
            __dyn_list_push(out, __dyn_list_at(r, j))
            j += 1
        if __load64(l + 16) == __load64(r + 16):
            __store64(out + 16, __load64(l + 16))
        return out
    na := __load64(l + 8)
    nb := __load64(r + 8)
    t := __dyn_tuple_new(na + nb)
    __copy(t + 16, l + 16, 8 * na)
    __copy(t + 16 + 8 * na, r + 16, 8 * nb)
    return t

func __dyn_seq_repeat(s: int, times: int) -> int:
    if times < 0:
        times = 0
    k := __load64(s)
    unit := 0
    if k == 7:
        unit = __dyn_list_len(s)
    elif k == 8:
        unit = __load64(s + 8)
    else:
        unit = __load64(__load64(s + 8))
    if unit != 0 and times > 2147483648 // unit:
        __dyn_err("ValueError", "répétition trop grande (plus de 2^31 éléments)")
    if k == 6:
        sb := __rt_sb_new()
        i := 0
        while i < times:
            __rt_sb_add(sb, __dyn_sv(s))
            i += 1
        return __dyn_str(__rt_sb_str(sb))
    if k == 7:
        out := __dyn_list_new(0)
        __store64(out + 16, __load64(s + 16))
        j := 0
        while j < times:
            e := 0
            while e < unit:
                __dyn_list_push(out, __dyn_list_at(s, e))
                e += 1
            j += 1
        return out
    t := __dyn_tuple_new(unit * times)
    q := 0
    while q < times:
        __copy(t + 16 + 8 * unit * q, s + 16, 8 * unit)
        q += 1
    return t

# EQ .. GE (opcodes 12 à 17).
func __dyn_compare(op: int, l: int, r: int) -> int:
    kl := __dyn_kind(l)
    kr := __dyn_kind(r)
    if kl == 12 or kr == 12:
        o := __dyn_overload(op, l, r)
        if o != 1:
            return o
    if op == 12:
        return __dyn_bool(__dyn_eq(l, r))
    if op == 13:
        return __dyn_bool(not __dyn_eq(l, r))
    c := 0
    if (kl == 1 or kl == 2) and (kr == 1 or kr == 2):
        if kl == 1 and kr == 1:
            a := __load64(l + 8)
            b := __load64(r + 8)
            if a < b:
                c = -1
            elif a > b:
                c = 1
        else:
            x := 0.0
            y := 0.0
            if kl == 1:
                x = __i2f(__load64(l + 8))
            else:
                x = __dyn_fv(l)
            if kr == 1:
                y = __i2f(__load64(r + 8))
            else:
                y = __dyn_fv(r)
            if x < y:
                c = -1
            elif x > y:
                c = 1
    elif kl == 6 and kr == 6:
        c = __rt_str_cmp(__dyn_sv(l), __dyn_sv(r))
        if c < 0:
            c = -1
        elif c > 0:
            c = 1
    elif kl == 4 and kr == 4:
        if __load64(l + 8) < __load64(r + 8):
            c = -1
        elif __load64(l + 8) > __load64(r + 8):
            c = 1
    else:
        __dyn_type_error(op, l, r)
    if op == 14:
        return __dyn_bool(c < 0)
    if op == 15:
        return __dyn_bool(c <= 0)
    if op == 16:
        return __dyn_bool(c > 0)
    return __dyn_bool(c >= 0)

# BAND .. SHR (opcodes 19 à 23).
func __dyn_bitwise(op: int, l: int, r: int) -> int:
    kl := __dyn_kind(l)
    kr := __dyn_kind(r)
    if kl == 12 or kr == 12:
        o := __dyn_overload(op, l, r)
        if o != 1:
            return o
    if kl == 1 and kr == 1:
        a := __load64(l + 8)
        b := __load64(r + 8)
        if op == 19:
            return __dyn_int(a & b)
        if op == 20:
            return __dyn_int(a | b)
        if op == 21:
            return __dyn_int(a ^ b)
        if op == 22:
            if b < 0 or b >= 64:
                __dyn_err("TypeError", "décalage hors limites (0..63) pour '<<'")
            return __dyn_int(a << b)
        if op == 23:
            if b < 0 or b >= 64:
                __dyn_err("TypeError", "décalage hors limites (0..63) pour '>>'")
            return __dyn_int(a >> b)
    if kl == 5 and kr == 5:
        x := __load64(l + 8)
        y := __load64(r + 8)
        if op == 19:
            return __dyn_byte(x & y)
        if op == 20:
            return __dyn_byte(x | y)
        if op == 21:
            return __dyn_byte(x ^ y)
        if op == 22:
            if y < 0 or y >= 8:
                __dyn_err("TypeError", "décalage hors limites (0..7) pour '<<' sur byte")
            return __dyn_byte((x << y) & 255)
        if op == 23:
            if y < 0 or y >= 8:
                __dyn_err("TypeError", "décalage hors limites (0..7) pour '>>' sur byte")
            return __dyn_byte(x >> y)
    __dyn_type_error(op, l, r)
    return 0

func __dyn_bitnot(v: int) -> int:
    if __dyn_is(v, 1):
        return __dyn_int(~__load64(v + 8))
    if __dyn_is(v, 5):
        return __dyn_byte(~__load64(v + 8) & 255)
    __dyn_err("TypeError", "opérande incompatible pour '~' : '" + __dyn_type_name(v) + "'")
    return 0

func __dyn_not(v: int) -> int:
    return __dyn_bool(not __dyn_truthy(v))

# ---- Conversion en chaîne, longueur (avec surcharges __str__ / __len__) ------------------------------------------

func __dyn_to_string(v: int) -> int:
    if __dyn_is(v, 12):
        m := __dyn_find_method(__as_str(__load64(v + 8)), "__str__")
        if m != 0:
            return __dyn_call0(__dyn_bind(m, v))
    if __dyn_is(v, 6):
        return v
    return __dyn_str(__dyn_display(v))

func __dyn_str_cplen(s: str) -> int:
    return __rt_str_len(s)

func __dyn_len(v: int) -> int:
    k := __dyn_kind(v)
    if k == 12:
        m := __dyn_find_method(__as_str(__load64(v + 8)), "__len__")
        if m != 0:
            return __dyn_call0(__dyn_bind(m, v))
    if k == 7:
        return __dyn_int(__dyn_list_len(v))
    if k == 8:
        return __dyn_int(__load64(v + 8))
    if k == 6:
        return __dyn_int(__dyn_svlen(v))
    if k == 9:
        return __dyn_int(__dyn_dict_len(v))
    __dyn_err("TypeError", "'" + __dyn_type_name(v) + "' n'a pas de longueur (len() attend str/list/tuple/dict)")
    return 0

func __dyn_type_name_v(v: int) -> int:
    return __dyn_str(__dyn_type_name(v))

# ---- Indexation (execGetIndex, execSetIndex), appartenance, tranches ----------------------------------------------

func __dyn_index_error(i: int, n: int, what: str):
    __dyn_err("IndexError", "index " + __int_to_str(i) + " hors limites (" + what + " " + __int_to_str(n) + ", §10)")

func __dyn_get_index(o: int, i: int) -> int:
    k := __dyn_kind(o)
    if k == 12:
        m := __dyn_find_method(__as_str(__load64(o + 8)), "__getitem__")
        if m != 0:
            return __dyn_call1(__dyn_bind(m, o), i)
    if k == 7 or k == 8:
        if not __dyn_is(i, 1):
            __dyn_err("TypeError", "l'index doit être un entier (obtenu '" + __dyn_type_name(i) + "')")
        n := 0
        if k == 7:
            n = __dyn_list_len(o)
        else:
            n = __load64(o + 8)
        x := __load64(i + 8)
        pos := x
        if x < 0:
            pos = x + n
        if pos < 0 or pos >= n:
            __dyn_index_error(x, n, "taille")
        if k == 7:
            return __dyn_list_at(o, pos)
        return __load64(o + 16 + 8 * pos)
    if k == 9:
        __dyn_need_hashable(i, "")
        d := __dyn_dv(o)
        e := __rt_dict_index(d, i, 3)
        if e < 0:
            __dyn_err("KeyError", "clé absente du dictionnaire (§10)")
        return __load64(__load64(d + 32) + 8 * e)
    if k == 6:
        if not __dyn_is(i, 1):
            __dyn_err("TypeError", "l'index doit être un entier (obtenu '" + __dyn_type_name(i) + "')")
        cnt := __dyn_svlen(o)
        y := __load64(i + 8)
        p := y
        if y < 0:
            p = y + cnt
        if p < 0 or p >= cnt:
            __dyn_index_error(y, cnt, "longueur")
        return __dyn_char(__dyn_svchar(o, p))
    __dyn_err("TypeError", "le type '" + __dyn_type_name(o) + "' ne supporte pas l'indexation (§10)")
    return 0

func __dyn_set_index(o: int, i: int, v: int):
    k := __dyn_kind(o)
    if k == 12:
        m := __dyn_find_method(__as_str(__load64(o + 8)), "__setitem__")
        if m != 0:
            __dyn_call2(__dyn_bind(m, o), i, v)
            return
    if k == 7:
        if not __dyn_is(i, 1):
            __dyn_err("TypeError", "l'index doit être un entier (obtenu '" + __dyn_type_name(i) + "')")
        n := __dyn_list_len(o)
        x := __load64(i + 8)
        pos := x
        if x < 0:
            pos = x + n
        if pos < 0 or pos >= n:
            __dyn_index_error(x, n, "taille")
        __dyn_check_write(__load64(o + 16), v, "élément de liste")
        __dyn_list_put(o, pos, v)
        return
    if k == 9:
        __dyn_need_hashable(i, "")
        __dyn_check_write(__load64(o + 16), i, "clé de dict")
        __dyn_check_write(__load64(o + 24), v, "valeur de dict")
        __rt_dict_set(__dyn_dv(o), i, v, 3)
        return
    if k == 8 or k == 6:
        __dyn_err("TypeError", "'" + __dyn_type_name(o) + "' est immuable, affectation indexée impossible (§10)")
    __dyn_err("TypeError", "le type '" + __dyn_type_name(o) + "' ne supporte pas l'affectation indexée (§10)")

func __dyn_dict_get_raw(d: int, k: int) -> int:
    e := __rt_dict_index(__dyn_dv(d), k, 3)
    if e < 0:
        return 1
    return __load64(__load64(__dyn_dv(d) + 32) + 8 * e)

# Chaîne `needle` dans `hay` (octets) : position, ou -1.
func __dyn_find_bytes(hay: str, needle: str, start: int) -> int:
    h := __str_addr(hay)
    n := __str_addr(needle)
    hn := __load64(h)
    nn := __load64(n)
    i := start
    while i + nn <= hn:
        j := 0
        while j < nn and __load8(h + 8 + i + j) == __load8(n + 8 + j):
            j += 1
        if j == nn:
            return i
        i += 1
    return -1

func __dyn_contains(item: int, c: int) -> int:
    k := __dyn_kind(c)
    if k == 12:
        m := __dyn_find_method(__as_str(__load64(c + 8)), "__contains__")
        if m != 0:
            return __dyn_call1(__dyn_bind(m, c), item)
    if k == 7:
        n := __dyn_list_len(c)
        i := 0
        while i < n:
            if __dyn_eq(__dyn_list_at(c, i), item):
                return __dyn_bool(true)
            i += 1
        return __dyn_bool(false)
    if k == 8:
        n2 := __load64(c + 8)
        j := 0
        while j < n2:
            if __dyn_eq(__load64(c + 16 + 8 * j), item):
                return __dyn_bool(true)
            j += 1
        return __dyn_bool(false)
    if k == 9:
        __dyn_need_hashable(item, "")
        return __dyn_bool(__rt_dict_index(__dyn_dv(c), item, 3) >= 0)
    if k == 6:
        if __dyn_is_str(item):
            return __dyn_bool(__dyn_find_bytes(__dyn_sv(c), __dyn_sv(item), 0) >= 0)
        if __dyn_is(item, 4):
            return __dyn_bool(__dyn_find_bytes(__dyn_sv(c), __rt_char_str(__load64(item + 8)), 0) >= 0)
        __dyn_err("TypeError", "'in' sur une chaîne exige une chaîne ou un caractère (obtenu '" + __dyn_type_name(item) + "')")
    __dyn_err("TypeError", "l'opérateur 'in' n'est pas défini pour le type '" + __dyn_type_name(c) + "'")
    return 0

# Indices d'une tranche [start:stop:step] sur `len` éléments (règles de Python) : liste native d'entiers.
func __dyn_slice_bound(v: int, what: str) -> int:
    if v != 0 and not __dyn_is(v, 1):
        __dyn_err("TypeError", "les bornes d'une tranche doivent être des entiers (" + what + " : '" + __dyn_type_name(v) + "')")
    if v == 0:
        return 0
    return __load64(v + 8)

func __dyn_slice_indices(n: int, vStart: int, vStop: int, vStep: int) -> int:
    start := __dyn_slice_bound(vStart, "début")
    stop := __dyn_slice_bound(vStop, "fin")
    step := __dyn_slice_bound(vStep, "pas")
    if vStep == 0:
        step = 1
    if step == 0:
        __dyn_err("ValueError", "le pas d'une tranche ne peut pas être nul")
    lo := 0
    hi := n
    if step < 0:
        lo = -1
        hi = n - 1
    if vStart == 0:
        if step > 0:
            start = lo
        else:
            start = hi
    else:
        start = __dyn_clamp_idx(start, n, lo, hi)
    if vStop == 0:
        if step > 0:
            stop = hi
        else:
            stop = lo
    else:
        stop = __dyn_clamp_idx(stop, n, lo, hi)
    out := __rt_list_new(0)
    i := start
    if step > 0:
        while i < stop:
            __rt_list_push(out, i)
            i += step
    else:
        while i > stop:
            __rt_list_push(out, i)
            i += step
    return out

func __dyn_clamp_idx(v: int, n: int, lo: int, hi: int) -> int:
    if v < 0:
        v += n
        if v < lo:
            v = lo
    elif v > hi:
        v = hi
    return v

func __dyn_get_slice(o: int, a: int, b: int, c: int) -> int:
    k := __dyn_kind(o)
    if not (k == 7 or k == 8 or k == 6):
        __dyn_err("TypeError", "le type '" + __dyn_type_name(o) + "' ne supporte pas les tranches")
    if k == 6:
        idx := __dyn_slice_indices(__dyn_svlen(o), a, b, c)
        sb := __rt_sb_new()
        n := __load64(idx)
        i := 0
        while i < n:
            __nat_sb_cp(sb, __dyn_svchar(o, __load64(__load64(idx + 16) + 8 * i)))
            i += 1
        return __dyn_str(__rt_sb_str(sb))
    len := 0
    if k == 7:
        len = __dyn_list_len(o)
    else:
        len = __load64(o + 8)
    ix := __dyn_slice_indices(len, a, b, c)
    m := __load64(ix)
    if k == 7:
        out := __dyn_list_new(0)
        __store64(out + 16, __load64(o + 16))
        j := 0
        while j < m:
            __dyn_list_push(out, __dyn_list_at(o, __load64(__load64(ix + 16) + 8 * j)))
            j += 1
        return out
    t := __dyn_tuple_new(m)
    q := 0
    while q < m:
        __store64(t + 16 + 8 * q, __load64(o + 16 + 8 * __load64(__load64(ix + 16) + 8 * q)))
        q += 1
    return t

func __dyn_del_item(o: int, key: int) -> int:
    if __dyn_is(o, 9):
        __dyn_need_hashable(key, "")
        d := __dyn_dv(o)
        e := __rt_dict_index(d, key, 3)
        if e < 0:
            __dyn_err("KeyError", "clé absente du dictionnaire (del)")
        __dyn_dict_erase(d, e)
        return 0
    if __dyn_is(o, 7):
        if not __dyn_is(key, 1):
            __dyn_err("TypeError", "l'index doit être un entier (obtenu '" + __dyn_type_name(key) + "')")
        n := __dyn_list_len(o)
        x := __load64(key + 8)
        pos := x
        if x < 0:
            pos = x + n
        if pos < 0 or pos >= n:
            __dyn_err("IndexError", "index " + __int_to_str(x) + " hors limites (taille " + __int_to_str(n) + ", del)")
        __dyn_list_erase(o, pos)
        return 0
    __dyn_err("TypeError", "'del' n'est pas défini pour le type '" + __dyn_type_name(o) + "'")
    return 0

func __dyn_dict_erase(d: int, e: int):
    __store64(__load64(d + 40) + 8 * e, -1)
    __store64(__load64(d + 24) + 8 * e, 0)
    __store64(__load64(d + 32) + 8 * e, 0)
    __store64(d, __load64(d) - 1)

func __dyn_list_erase(o: int, pos: int):
    l := __dyn_lv(o)
    n := __load64(l)
    data := __load64(l + 16)
    __copy(data + 8 * pos, data + 8 * pos + 8, 8 * (n - pos - 1))
    __store64(data + 8 * (n - 1), 0)
    __store64(l, n - 1)

# ---- Collections : construction, opérations de liste et de dict --------------------------------------------------

func __dyn_dict_lit_set(d: int, k: int, v: int):
    if not __dyn_hashable(k):
        __dyn_err("TypeError", "clé de type '" + __dyn_type_name(k) + "' non hashable dans un littéral dictionnaire (Addendum A.8)")
    __rt_dict_set(__dyn_dv(d), k, v, 3)

func __dyn_dict_keys(v: int) -> int:
    if not __dyn_is(v, 9):
        __dyn_err("TypeError", "DICT_KEYS : le type '" + __dyn_type_name(v) + "' n'est pas un dict")
    return __dyn_list_wrap(__rt_dict_list(__dyn_dv(v), 24))

func __dyn_list_append(l: int, v: int) -> int:
    if not __dyn_is(l, 7):
        __dyn_err("TypeError", "LIST_APPEND : '" + __dyn_type_name(l) + "' n'est pas une liste")
    __dyn_check_write(__load64(l + 16), v, "élément ajouté")
    __dyn_list_push(l, v)
    return 0

func __dyn_list_insert(l: int, i: int, v: int) -> int:
    if not __dyn_is(l, 7):
        __dyn_err("TypeError", "LIST_INSERT : '" + __dyn_type_name(l) + "' n'est pas une liste")
    if not __dyn_is(i, 1):
        __dyn_err("TypeError", "LIST_INSERT : l'index doit être un entier (obtenu '" + __dyn_type_name(i) + "')")
    n := __dyn_list_len(l)
    x := __load64(i + 8)
    if x < 0 or x > n:
        __dyn_err("IndexError", "LIST_INSERT : index " + __int_to_str(x) + " hors limites (taille " + __int_to_str(n) + ", §10)")
    __dyn_check_write(__load64(l + 16), v, "élément inséré")
    __dyn_list_push(l, 0)
    data := __load64(__dyn_lv(l) + 16)
    j := n
    while j > x:
        __store64(data + 8 * j, __load64(data + 8 * (j - 1)))
        j -= 1
    __store64(data + 8 * x, v)
    return 0

func __dyn_list_remove_at(l: int, i: int) -> int:
    if not __dyn_is(l, 7):
        __dyn_err("TypeError", "LIST_REMOVE_AT : '" + __dyn_type_name(l) + "' n'est pas une liste")
    if not __dyn_is(i, 1):
        __dyn_err("TypeError", "LIST_REMOVE_AT : l'index doit être un entier (obtenu '" + __dyn_type_name(i) + "')")
    n := __dyn_list_len(l)
    x := __load64(i + 8)
    pos := x
    if x < 0:
        pos = x + n
    if pos < 0 or pos >= n:
        __dyn_err("IndexError", "LIST_REMOVE_AT : index " + __int_to_str(x) + " hors limites (taille " + __int_to_str(n) + ", §10)")
    v := __dyn_list_at(l, pos)
    __dyn_list_erase(l, pos)
    return v

func __dyn_list_clear(l: int) -> int:
    if not __dyn_is(l, 7):
        __dyn_err("TypeError", "LIST_CLEAR : '" + __dyn_type_name(l) + "' n'est pas une liste")
    __store64(__dyn_lv(l), 0)
    return 0

func __dyn_dict_remove_key(d: int, k: int) -> int:
    if not __dyn_is(d, 9):
        __dyn_err("TypeError", "DICT_REMOVE_KEY : '" + __dyn_type_name(d) + "' n'est pas un dict")
    __dyn_need_hashable(k, "")
    dd := __dyn_dv(d)
    e := __rt_dict_index(dd, k, 3)
    if e < 0:
        __dyn_err("KeyError", "DICT_REMOVE_KEY : clé absente du dictionnaire")
    v := __load64(__load64(dd + 32) + 8 * e)
    __dyn_dict_erase(dd, e)
    return v

func __dyn_list_extend(a: int, b: int) -> int:
    if not __dyn_is(a, 7):
        __dyn_err("BytecodeError", "LIST_EXTEND : liste attendue")
    out := __dyn_list_new(0)
    n := __dyn_list_len(a)
    i := 0
    while i < n:
        __dyn_list_push(out, __dyn_list_at(a, i))
        i += 1
    k := __dyn_kind(b)
    if k == 7:
        m := __dyn_list_len(b)
        j := 0
        while j < m:
            __dyn_list_push(out, __dyn_list_at(b, j))
            j += 1
    elif k == 8:
        m2 := __load64(b + 8)
        q := 0
        while q < m2:
            __dyn_list_push(out, __load64(b + 16 + 8 * q))
            q += 1
    elif k == 9:
        keys := __rt_dict_list(__dyn_dv(b), 24)
        nk := __load64(keys)
        r := 0
        while r < nk:
            __dyn_list_push(out, __load64(__load64(keys + 16) + 8 * r))
            r += 1
    elif k == 6:
        cn := __dyn_svlen(b)
        c := 0
        while c < cn:
            __dyn_list_push(out, __dyn_char(__dyn_svchar(b, c)))
            c += 1
    else:
        __dyn_err("TypeError", "'*' attend une liste, un tuple, une chaîne ou un dict (obtenu '" + __dyn_type_name(b) + "')")
    return out

func __dyn_list_to_tuple(l: int) -> int:
    n := __dyn_list_len(l)
    t := __dyn_tuple_new(n)
    i := 0
    while i < n:
        __store64(t + 16 + 8 * i, __dyn_list_at(l, i))
        i += 1
    return t

func __dyn_dict_update(a: int, b: int) -> int:
    if not __dyn_is(b, 9):
        __dyn_err("TypeError", "'**' attend un dict (obtenu '" + __dyn_type_name(b) + "')")
    out := __dyn_dict_new()
    __dyn_dict_merge(out, a)
    __dyn_dict_merge(out, b)
    return out

func __dyn_dict_merge(out: int, src: int):
    d := __dyn_dv(src)
    used := __load64(d + 8)
    e := 0
    while e < used:
        if __load64(__load64(d + 40) + 8 * e) >= 0:
            __rt_dict_set(__dyn_dv(out), __load64(__load64(d + 24) + 8 * e), __load64(__load64(d + 32) + 8 * e), 3)
        e += 1

# ---- Exceptions -----------------------------------------------------------------------------------------------------

# Valeur exception portant l'exception native e (toujours la même pour une même exception : identité).
func __dyn_exc_box(e: int) -> int:
    b := __load64(e + 24)
    if b != 0:
        return b
    b = __alloc(16)
    __store64(b, 13)
    __store64(b + 8, e)
    __store64(e + 24, b)
    return b

func __dyn_throw(v: int):
    if __dyn_is(v, 13):
        __rt_throw(__load64(v + 8))
    __rt_throw(__rt_exc_new("Exception", __dyn_display(v)))

func __dyn_raise(typeV: int, msgV: int):
    if __dyn_is(msgV, 13):
        __rt_throw(__load64(msgV + 8))
    if not __dyn_is_str(typeV):
        __dyn_err("TypeError", "raise(...) : le type doit être une String (obtenu '" + __dyn_type_name(typeV) + "')")
    if not __dyn_is_str(msgV):
        __dyn_err("TypeError", "raise(...) : le message doit être une String (obtenu '" + __dyn_type_name(msgV) + "')")
    __rt_throw(__rt_exc_new(__dyn_sv(typeV), __dyn_sv(msgV)))

# e.trace : « fichier:ligne, dans fonction », appel le plus récent en dernier.
func __dyn_exc_trace(e: int) -> int:
    out := __dyn_list_new(0)
    addrs := __load64(e + 16)
    if addrs == 0:
        return out
    if __load64(addrs) < 0: # trace relevée par la VM écrite en ALEX (runtime/vm) : [-1-n][fichier, ligne, fonction]...
        k := 0
        while k < -1 - __load64(addrs):
            t := addrs + 8 + 24 * k
            sb := __rt_sb_new()
            __rt_sb_add(sb, __as_str(__load64(t)))
            if __load64(t + 8) > 0:
                __rt_sb_add(sb, ":")
                __rt_sb_add(sb, __int_to_str(__load64(t + 8)))
            __rt_sb_add(sb, ", dans ")
            __rt_sb_add(sb, __as_str(__load64(t + 16)))
            __dyn_list_push(out, __dyn_str(__rt_sb_str(sb)))
            k += 1
        return out
    info := __trace_info()
    funcs := info + __load64(info)
    lines := info + __load64(info + 8)
    code := __code_base()
    i := __load64(addrs)
    while i >= 1:
        off := __load64(addrs + 8 * i) - code - 1
        f := __rt_bsearch(funcs, 4, off)
        if f >= 0:
            fe := funcs + 8 + 32 * f
            if off < __load64(fe + 8) and __load64(fe + 24) != 0:
                l := __rt_bsearch(lines, 2, off)
                line := 0
                if l >= 0:
                    line = __load64(lines + 8 + 16 * l + 8)
                sb := __rt_sb_new()
                __rt_sb_add(sb, __as_str(info + __load64(fe + 24)))
                if line > 0:
                    __rt_sb_add(sb, ":")
                    __rt_sb_add(sb, __int_to_str(line))
                __rt_sb_add(sb, ", dans ")
                __rt_sb_add(sb, __as_str(info + __load64(fe + 16)))
                __dyn_list_push(out, __dyn_str(__rt_sb_str(sb)))
        i -= 1
    return out

# ---- Cellules (fermetures) ----------------------------------------------------------------------------------------

func __dyn_cell_new(v: int) -> int:
    c := __alloc(24)
    __store64(c, 14)
    __store64(c + 8, v)
    __store64(c + 16, 1)
    return c

func __dyn_cell_empty() -> int:
    c := __alloc(24)
    __store64(c, 14)
    return c

func __dyn_cell_get(c: int) -> int:
    if not __dyn_is(c, 14):
        __dyn_err("BytecodeError", "CELL_GET : une cellule était attendue (variable capturée non boxée ?)")
    if __load64(c + 16) == 0:
        __dyn_err("NameError", "variable utilisée avant sa déclaration (une fonction imbriquée a été appelée avant que la variable qu'elle capture ne soit déclarée, §5.3)")
    return __load64(c + 8)

func __dyn_cell_set(c: int, v: int):
    if not __dyn_is(c, 14):
        __dyn_err("BytecodeError", "CELL_SET : une cellule était attendue (variable capturée non boxée ?)")
    __store64(c + 8, v)
    __store64(c + 16, 1)

func __dyn_closure_env(n: int) -> int:
    return __dyn_tuple_new(n)

# ---- Divers : arguments au-delà du 8e, constantes, modules, natives absentes --------------------------------------

func __dyn_xarg(x: int, j: int) -> int:
    if x == 0 or j >= __load64(x + 8):
        return 0
    return __load64(x + 16 + 8 * j)

func __dyn_float_bits(b: int) -> int:
    o := __alloc_raw(16)
    __store64(o, 2)
    __store64(o + 8, b)
    return o

func __dyn_import_error(name: str):
    __dyn_err("ImportError", "module '" + name + "' introuvable ou invalide (§19)")

func __dyn_native_missing(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int, x: int) -> int:
    __dyn_err("NotImplementedError", "fonction native '" + __as_str(__load64(f + 16)) + "' : pas encore disponible dans le code natif (mode dynamique)")
    return 0

func __dyn_await(v: int) -> int:
    if not __dyn_is(v, 15):
        __dyn_err("TypeError", "await attend une tâche ou un futur (obtenu '" + __dyn_type_name(v) + "')")
    return __rt_await(__load64(v + 8))

# ---- Entrée ---------------------------------------------------------------------------------------------------------

func __dyn_input() -> int:
    return __dyn_str(__rt_input())

# ---- Annotations (CHECK_TYPE, DECLARE_FIELD_TYPE) -- voir __dyn_type_node ------------------------------------------

func __dyn_check_write(t: int, v: int, where: str):
    if t == 0:
        return
    pb := __dyn_value_matches(v, t)
    if pb == 0:
        return
    __dyn_err("TypeError", where + " : attendu " + __dyn_short_desc(__as_str(__load64(t + 40))) + ", obtenu " +
              __dyn_type_name(v) + __dyn_problem(pb))

func __dyn_check_field(cls: str, member: str, v: int):
    ft := __load64(__dyn_ds() + 40)
    if __load64(ft) == 0:
        return
    cur := cls
    guard := 0
    while guard < 64 and cur != "":
        e := __rt_dict_index(ft, __str_addr(cur), 1)
        if e >= 0:
            fields := __load64(__load64(ft + 32) + 8 * e)
            f := __rt_dict_index(fields, __str_addr(member), 1)
            if f >= 0:
                __dyn_check_write(__load64(__load64(fields + 32) + 8 * f), v, "champ '" + member + "'")
                return
        rec := __dyn_class_rec(cur)
        if rec != 0 and __load64(rec) != 0:
            cur = __as_str(__load64(rec))
        else:
            cur = ""
        guard += 1

func __dyn_declare_field_type(clsV: int, fieldV: int, descV: int):
    ft := __load64(__dyn_ds() + 40)
    cls := __dyn_sv(clsV)
    e := __rt_dict_index(ft, __str_addr(cls), 1)
    fields := 0
    if e >= 0:
        fields = __load64(__load64(ft + 32) + 8 * e)
    else:
        fields = __rt_dict_new(8)
        __rt_dict_set(ft, __str_addr(cls), fields, 1)
    __rt_dict_set(fields, __load64(fieldV + 8), __dyn_type_node(__dyn_sv(descV)), 1)

func __dyn_check_type(v: int, descV: int, whatV: int):
    t := __dyn_type_node(__dyn_sv(descV))
    pb := __dyn_value_matches(v, t)
    if pb == 0:
        return
    __dyn_err("TypeError", __dyn_sv(whatV) + " : attendu " + __dyn_short_desc(__as_str(__load64(t + 40))) + ", obtenu " +
              __dyn_type_name(v) + __dyn_problem(pb))


# ---- Nœuds de type des annotations (VM::parseTypeNode) --------------------------------------------------------------
# Nœud : [genre][nullable][lo][hi][nom][texte][a][b] ; genres : 0 any, 1 null, 2 int, 3 sized, 4 float, 5 bool, 6 str,
# 7 char, 8 byte, 9 list, 10 dict, 11 tuple, 12 func, 13 future, 14 nommé. Internés par texte (état [32]).

func __dyn_tn_kind(name: str) -> int:
    if name == "any":
        return 0
    if name == "null":
        return 1
    if name == "int":
        return 2
    if name == "float" or name == "f32":
        return 4
    if name == "bool":
        return 5
    if name == "str":
        return 6
    if name == "char":
        return 7
    if name == "byte":
        return 8
    if name == "list":
        return 9
    if name == "dict":
        return 10
    if name == "tuple":
        return 11
    if name == "func":
        return 12
    if name == "future":
        return 13
    if name == "i8" or name == "i16" or name == "i32" or name == "u8" or name == "u16" or name == "u32" or name == "u64":
        return 3
    return 14

func __dyn_type_node(text: str) -> int:
    cache := __load64(__dyn_ds() + 32)
    e := __rt_dict_index(cache, __str_addr(text), 1)
    if e >= 0:
        return __load64(__load64(cache + 32) + 8 * e)
    pos := __alloc_raw(8)
    return __dyn_tn_parse(text, pos)

func __dyn_tn_parse(text: str, pos: int) -> int:
    p := __str_addr(text)
    n := __load64(p)
    start := __load64(pos)
    i := start
    while i < n:
        c := __load8(p + 8 + i)
        if c == 91 or c == 93 or c == 44 or c == 63:
            break
        i += 1
    name := __dyn_substr(text, start, i)
    node := __alloc(64)
    k := __dyn_tn_kind(name)
    __store64(node, k)
    __store64(node + 32, __str_addr(name))
    if k == 3:
        lo := 0
        hi := 9223372036854775807
        if name == "i8":
            lo = -128
            hi = 127
        elif name == "i16":
            lo = -32768
            hi = 32767
        elif name == "i32":
            lo = -2147483648
            hi = 2147483647
        elif name == "u8":
            hi = 255
        elif name == "u16":
            hi = 65535
        elif name == "u32":
            hi = 4294967295
        __store64(node + 16, lo)
        __store64(node + 24, hi)
    if i < n and __load8(p + 8 + i) == 91:
        __store64(pos, i + 1)
        __store64(node + 48, __dyn_tn_parse(text, pos))
        i = __load64(pos)
        if i < n and __load8(p + 8 + i) == 44:
            __store64(pos, i + 1)
            __store64(node + 56, __dyn_tn_parse(text, pos))
            i = __load64(pos)
        if i < n and __load8(p + 8 + i) == 93:
            i += 1
    if i < n and __load8(p + 8 + i) == 63:
        __store64(node + 8, 1)
        i += 1
    __store64(pos, i)
    t := __dyn_substr(text, start, i)
    __store64(node + 40, __str_addr(t))
    a := __load64(node + 48)
    if a != 0 and __load64(a) == 0:
        __store64(node + 48, 0)
    b := __load64(node + 56)
    if b != 0 and __load64(b) == 0:
        __store64(node + 56, 0)
    cache := __load64(__dyn_ds() + 32)
    e := __rt_dict_index(cache, __str_addr(t), 1)
    if e >= 0:
        return __load64(__load64(cache + 32) + 8 * e)
    __rt_dict_set(cache, __str_addr(t), node, 1)
    return node

# Descripteur sans qualificatifs de module (« $mod…:: »), pour les messages.
func __dyn_short_desc(s: str) -> str:
    p := __str_addr(s)
    n := __load64(p)
    sb := __rt_sb_new()
    i := 0
    while i < n:
        if __load8(p + 8 + i) == 36:
            q := i
            found := -1
            while q + 1 < n:
                if __load8(p + 8 + q) == 58 and __load8(p + 9 + q) == 58:
                    found = q
                    break
                q += 1
            if found >= 0:
                i = found + 2
                continue
        __rt_sb_byte(sb, __load8(p + 8 + i))
        i += 1
    return __rt_sb_str(sb)

# Problème de correspondance : 0 = la valeur correspond ; sinon 1 (sans détail) ou une chaîne native de détail.
func __dyn_problem(pb: int) -> str:
    if pb == 1:
        return ""
    return __as_str(pb)

func __dyn_tag_compatible(have: int, want: int) -> bool:
    if want == 0 or __load64(want) == 0 or have == want:
        return true
    if have == 0 or __load64(have) == 0:
        return false
    if __load64(have + 8) != 0 and __load64(want + 8) == 0:
        return false
    wk := __load64(want)
    hk := __load64(have)
    if wk == 4:
        return hk == 4 or hk == 2 or hk == 3
    if wk == 2:
        return hk == 2 or hk == 3
    if wk == 3:
        return hk == 3 and __load64(have + 16) >= __load64(want + 16) and __load64(have + 24) <= __load64(want + 24)
    if wk == 9:
        return hk == 9 and __dyn_tag_compatible(__load64(have + 48), __load64(want + 48))
    if wk == 10:
        return hk == 10 and __dyn_tag_compatible(__load64(have + 48), __load64(want + 48)) and __dyn_tag_compatible(__load64(have + 56), __load64(want + 56))
    if wk == 14:
        return hk == 14 and __dyn_subtype(__as_str(__load64(have + 32)), __as_str(__load64(want + 32)))
    return hk == wk

func __dyn_value_matches(v: int, t: int) -> int:
    if t == 0 or __load64(t) == 0:
        return 0
    tk := __load64(t)
    if v == 0:
        if __load64(t + 8) != 0 or tk == 1:
            return 0
        return 1
    k := __load64(v)
    if tk == 2:
        if k == 1:
            return 0
        return 1
    if tk == 4:
        if k == 2 or k == 1:
            return 0
        return 1
    if tk == 5:
        if k == 3:
            return 0
        return 1
    if tk == 7:
        if k == 4:
            return 0
        return 1
    if tk == 8:
        if k == 5:
            return 0
        return 1
    if tk == 3:
        if k != 1:
            return 1
        x := __load64(v + 8)
        if x >= __load64(t + 16) and x <= __load64(t + 24):
            return 0
        return __str_addr(" " + __int_to_str(x) + " (hors bornes " + __int_to_str(__load64(t + 16)) + ".." + __int_to_str(__load64(t + 24)) + ")")
    if tk == 6:
        if k == 6:
            return 0
        return 1
    if tk == 11:
        if k == 8:
            return 0
        return 1
    if tk == 12:
        if k == 10 or k == 11:
            return 0
        return 1
    if tk == 13:
        if k == 15:
            return 0
        return 1
    if tk == 14:
        if k == 12 and __dyn_subtype(__as_str(__load64(v + 8)), __as_str(__load64(t + 32))):
            return 0
        return 1
    if tk == 9:
        if k != 7:
            return 1
        a := __load64(t + 48)
        if a == 0:
            return 0
        et := __load64(v + 16)
        if et != 0:
            if __dyn_tag_compatible(et, a):
                return 0
            return __str_addr(" (liste de " + __dyn_short_desc(__as_str(__load64(et + 40))) + ")")
        n := __dyn_list_len(v)
        i := 0
        while i < n:
            it := __dyn_list_at(v, i)
            sub := __dyn_value_matches(it, a)
            if sub != 0:
                return __str_addr(" (élément " + __int_to_str(i) + " : " + __dyn_type_name(it) + __dyn_problem(sub) + ")")
            i += 1
        __store64(v + 16, a)
        return 0
    if tk == 10:
        if k != 9:
            return 1
        ka := __load64(t + 48)
        kb := __load64(t + 56)
        if ka == 0 and kb == 0:
            return 0
        if __load64(v + 16) != 0 or __load64(v + 24) != 0:
            if __dyn_tag_compatible(__load64(v + 16), ka) and __dyn_tag_compatible(__load64(v + 24), kb):
                return 0
            ks := "any"
            vs := "any"
            if __load64(v + 16) != 0:
                ks = __dyn_short_desc(__as_str(__load64(__load64(v + 16) + 40)))
            if __load64(v + 24) != 0:
                vs = __dyn_short_desc(__as_str(__load64(__load64(v + 24) + 40)))
            return __str_addr(" (dict[" + ks + ", " + vs + "])")
        d := __dyn_dv(v)
        used := __load64(d + 8)
        e := 0
        while e < used:
            if __load64(__load64(d + 40) + 8 * e) >= 0:
                key := __load64(__load64(d + 24) + 8 * e)
                sk := __dyn_value_matches(key, ka)
                if sk != 0:
                    return __str_addr(" (clé " + __dyn_type_name(key) + __dyn_problem(sk) + ")")
                val := __load64(__load64(d + 32) + 8 * e)
                sv := __dyn_value_matches(val, kb)
                if sv != 0:
                    return __str_addr(" (valeur " + __dyn_type_name(val) + __dyn_problem(sv) + ")")
            e += 1
        __store64(v + 16, ka)
        __store64(v + 24, kb)
        return 0
    return 1

# ---- Futurs (async) : ordonnanceur du runtime natif (RuntimeSource, « Tâches ») -----------------------------------
# Valeur future : [15][futur du runtime][tâche ?] ; le futur du runtime garde sa valeur en [104] (identité).

func __dyn_future_box(f: int) -> int:
    if f == 0:
        return 0
    b := __load64(f + 104)
    if b != 0:
        return b
    b = __alloc(24)
    __store64(b, 15)
    __store64(b + 8, f)
    __store64(b + 16, __load64(f + 40))
    __store64(f + 104, b)
    return b

func __dyn_future_display(v: int) -> str:
    return __rt_future_str(__load64(v + 8))

# Appel d'une async func : tâche [code][nom][futur][fonction][arguments] qui démarre au prochain tour de boucle.
func __dyn_spawn(f: int, args: int) -> int:
    c := __alloc(40)
    __store64(c, __fnaddr("__dyn_task_body"))
    __store64(c + 8, __str_addr(__dyn_fn_display(__as_str(__load64(f + 16)))))
    __store64(c + 24, f)
    __store64(c + 32, args)
    return __dyn_future_box(__rt_task_new(c))

func __dyn_task_body(c: int):
    r := __dyn_invoke_list(__load64(c + 24), __load64(c + 32))
    __rt_task_done(__load64(c + 16), r)

# Fin du programme principal : tâches échouées jamais attendues (avertissement, comme la VM).
func __dyn_end():
    __rt_async_end()
    __th_join_all()
    __fd_restore_all()

# ---- Mathématiques : puissance flottante (pow de C99, résultat correctement arrondi) -------------------------------
# Arithmétique double-double : nombre = hi + lo (|lo| <= ulp(hi) / 2), environ 106 bits. Une valeur dd vit dans un
# tampon de 16 octets [hi][lo] (bits IEEE). pow(x, y) = exp(y log x), log et exp en double-double puis arrondi :
# résultat correctement arrondi (sauf cas extrêmement proches d'un milieu), comme pow de la glibc dans la pratique.

func __dd_new(hi: float, lo: float) -> int:
    d := __alloc_raw(16)
    __store64(d, __f2bits(hi))
    __store64(d + 8, __f2bits(lo))
    return d

func __dd_hi(d: int) -> float:
    return __bits2f(__load64(d))

func __dd_lo(d: int) -> float:
    return __bits2f(__load64(d + 8))

func __dd_set(d: int, hi: float, lo: float):
    __store64(d, __f2bits(hi))
    __store64(d + 8, __f2bits(lo))

# Somme exacte a + b = s + e.
func __dd_two_sum(a: float, b: float) -> int:
    s := a + b
    bb := s - a
    e := (a - (s - bb)) + (b - bb)
    return __dd_new(s, e)

func __dd_split_hi(a: float) -> float:
    c := 134217729.0 * a
    return c - (c - a)

# Produit exact a * b = p + e (sans FMA : découpage de Dekker).
func __dd_two_prod(a: float, b: float) -> int:
    p := a * b
    ah := __dd_split_hi(a)
    al := a - ah
    bh := __dd_split_hi(b)
    bl := b - bh
    e := ((ah * bh - p) + ah * bl + al * bh) + al * bl
    return __dd_new(p, e)

func __dd_norm(hi: float, lo: float) -> int:
    s := hi + lo
    return __dd_new(s, lo - (s - hi))

func __dd_add(x: int, y: int) -> int:
    s := __dd_two_sum(__dd_hi(x), __dd_hi(y))
    t := __dd_two_sum(__dd_lo(x), __dd_lo(y))
    hi := __dd_hi(s)
    lo := __dd_lo(s) + __dd_hi(t)
    u := __dd_norm(hi, lo)
    return __dd_norm(__dd_hi(u), __dd_lo(u) + __dd_lo(t))

func __dd_neg(x: int) -> int:
    return __dd_new(0.0 - __dd_hi(x), 0.0 - __dd_lo(x))

func __dd_mul(x: int, y: int) -> int:
    p := __dd_two_prod(__dd_hi(x), __dd_hi(y))
    lo := __dd_lo(p) + (__dd_hi(x) * __dd_lo(y) + __dd_lo(x) * __dd_hi(y))
    return __dd_norm(__dd_hi(p), lo)

func __dd_mul_d(x: int, b: float) -> int:
    p := __dd_two_prod(__dd_hi(x), b)
    return __dd_norm(__dd_hi(p), __dd_lo(p) + __dd_lo(x) * b)

func __dd_div(x: int, y: int) -> int:
    q1 := __dd_hi(x) / __dd_hi(y)
    r := __dd_add(x, __dd_neg(__dd_mul_d(y, q1)))
    q2 := __dd_hi(r) / __dd_hi(y)
    r2 := __dd_add(r, __dd_neg(__dd_mul_d(y, q2)))
    q3 := __dd_hi(r2) / __dd_hi(y)
    u := __dd_norm(q1, q2)
    return __dd_add(u, __dd_new(q3, 0.0))

func __dd_ln2() -> int:
    return __dd_new(__bits2f(4604418534313441775), __bits2f(4358002977218854975))

# log(x) en double-double, x > 0 fini : x = m 2^e, m dans [sqrt(1/2), sqrt(2)), log m = 2 atanh((m-1)/(m+1)).
func __dd_log(x: float) -> int:
    b := __f2bits(x)
    e := ((b >> 52) & 2047) - 1023
    if ((b >> 52) & 2047) == 0: # sous-normal : renormalisé
        x = x * 18014398509481984.0
        b = __f2bits(x)
        e = ((b >> 52) & 2047) - 1023 - 54
    m := __bits2f((b & 4503599627370495) | 4607182418800017408)
    if m > 1.4142135623730951:
        m = m * 0.5
        e += 1
    num := __dd_new(m - 1.0, 0.0)
    den := __dd_two_sum(m, 1.0)
    sd := __dd_div(num, den)
    s2 := __dd_mul(sd, sd)
    acc := __dd_div(__dd_new(1.0, 0.0), __dd_new(49.0, 0.0))
    k := 23
    while k >= 0:
        acc = __dd_add(__dd_mul(acc, s2), __dd_div(__dd_new(1.0, 0.0), __dd_new(__i2f(2 * k + 1), 0.0)))
        k -= 1
    lm := __dd_mul_d(__dd_mul(sd, acc), 2.0)
    return __dd_add(__dd_mul_d(__dd_ln2(), __i2f(e)), lm)

# 2^k exactement (k dans les bornes des doubles normaux).
func __dd_pow2(k: int) -> float:
    return __bits2f((k + 1023) << 52)

# exp(t) arrondi au double, t en double-double.
func __dd_exp_round(t: int) -> float:
    th := __dd_hi(t)
    if th > 709.8:
        return __bits2f(9218868437227405312)
    if th < -745.2:
        return 0.0
    k := __f2i(__rt_floor(th / 0.6931471805599453 + 0.5))
    r := __dd_add(t, __dd_neg(__dd_mul_d(__dd_ln2(), __i2f(k))))
    rs := __dd_mul_d(r, 0.0009765625) # r / 1024
    # exp(rs) - 1 par Taylor (|rs| < 4e-4)
    em := __dd_new(0.0, 0.0)
    term := __dd_new(1.0, 0.0)
    n := 1
    while n <= 13:
        term = __dd_div(__dd_mul(term, rs), __dd_new(__i2f(n), 0.0))
        em = __dd_add(em, term)
        n += 1
    q := 0
    while q < 10: # (1 + E)^2 - 1 = 2E + E^2
        em = __dd_add(__dd_mul_d(em, 2.0), __dd_mul(em, em))
        q += 1
    v := __dd_add(__dd_new(1.0, 0.0), em)
    if k > 1023:
        return (__dd_hi(v) + __dd_lo(v)) * __dd_pow2(1023) * __dd_pow2(k - 1023)
    if k < -1022:
        # résultat sous-normal possible : mise à l'échelle en deux temps
        return (__dd_hi(v) + __dd_lo(v)) * __dd_pow2(k + 600) * __dd_pow2(-600)
    return (__dd_hi(v) + __dd_lo(v)) * __dd_pow2(k)

func __dyn_is_int_f(y: float) -> bool:
    return y == __rt_floor(y)

func __dyn_is_odd_f(y: float) -> bool:
    if not __dyn_is_int_f(y):
        return false
    if y >= 9007199254740992.0 or y <= -9007199254740992.0:
        return false
    return (__f2i(y) & 1) != 0

func __dyn_math_pow(x: float, y: float) -> float:
    inf := __bits2f(9218868437227405312)
    nan := __bits2f(9221120237041090560)
    if y == 0.0:
        return 1.0
    if x == 1.0:
        return 1.0
    if x != x or y != y:
        return nan
    ay := y
    if ay < 0.0:
        ay = 0.0 - ay
    ax := x
    if ax < 0.0:
        ax = 0.0 - ax
    if ay == inf:
        if ax == 1.0:
            return 1.0
        if (ax < 1.0) == (y > 0.0):
            return 0.0
        return inf
    if ax == inf:
        if x > 0.0:
            if y < 0.0:
                return 0.0
            return inf
        if __dyn_is_odd_f(y):
            if y < 0.0:
                return -0.0
            return 0.0 - inf
        if y < 0.0:
            return 0.0
        return inf
    if x == 0.0:
        neg := (__f2bits(x) >> 63) != 0
        if y < 0.0:
            if __dyn_is_odd_f(y) and neg:
                return 0.0 - inf
            return inf
        if __dyn_is_odd_f(y) and neg:
            return -0.0
        return 0.0
    sign := 1.0
    if x < 0.0:
        if not __dyn_is_int_f(y):
            return nan
        if __dyn_is_odd_f(y):
            sign = -1.0
    l := __dd_log(ax)
    t := __dd_mul_d(l, y)
    return sign * __dd_exp_round(t)

