# ALEX — machine virtuelle écrite en ALEX (étape D de l'autonomie : docs/SELFHOST.md, « Étape D »).
#
# Interpréteur du bytecode .albc, écrit dans le dialecte du runtime natif (sous-ensemble typé, intrinsèques
# mémoire) et compilé en code machine par le compilateur natif écrit en ALEX (`alexc vm`, native.vm). Il
# s'appuie sur le runtime du mode dynamique (runtime/alex/native/dyn*.al, lui aussi écrit en ALEX) : même
# représentation des valeurs, mêmes opérations que la VM C++ (VM.cpp, Value.cpp), mêmes modules natifs, même
# ramasse-miettes, mêmes tâches. La VM n'ajoute que le chargement du .albc, le décodage, la boucle d'exécution, les
# cadres d'appel, les gestionnaires try/catch du bytecode, les traces de pile, le profileur, et les modules natifs
# qui manquent au mode dynamique (_native_reflect ; _native_ffi et _native_tls, la VM étant un ELF dynamique).
#
#   alexvm [--script NOM] [--profile[=rapport.json]] prog.albc [arguments...]   # comme `alexc run prog.albc`
#   (alexc run ajoute --parent PID : la VM meurt avec alexc ; --delete : le .albc temporaire est effacé une fois lu)
#
# Valeurs : celles du mode dynamique (voir RuntimeDyn.hpp). Une fonction du bytecode est une valeur fonction [10]
# dont le code est __vm_fn_entry ; son nom est une chaîne « marquée » : le mot qui la précède en mémoire désigne
# son descripteur (bloc [descripteur][longueur][octets], la chaîne commence au 2e mot).
#
# État de la VM (globale 1 du programme natif, la globale 0 étant l'état du mode dynamique) :
#   [0] constantes (tableau de valeurs)  [8] leur nombre  [16] descripteurs  [24] leur nombre
#   [32] id de fonction -> descripteur  [40] nom de globale -> adresse de sa case  [48] bloc de cases courant
#   [56] cases utilisées  [64] blocs de cases  [72] descripteur du point d'entrée  [80] chemin du script
#   [88] décalage d'argv  [96] cadre courant du programme principal  [104] octets du module  [112] nom -> descripteur
#   [120] adresse de la section de code  [128] version mineure  [136] nombre d'octets de code
#   [144..200] ffi et TLS (voir ces sections)  [208..280] profileur  [304] gc.collect() différé (arguments + 1)
#
# Descripteur de fonction :
#   [0] instructions décodées (32 octets : opcode, a, b, c)  [8] leur nombre  [16] locales  [24] pile maximale
#   [32] nom marqué  [40] fichier (traces)  [48] lignes par instruction  [56] nom affiché  [64] cachée ($...)
#   [72] paramètres reçus  [80] arité min  [88] arité max  [96] async  [104] id  [112] décalage du code
#   [120] longueur du code  [128] décodée  [136] table de lignes brute [décalage, ligne]...  [144] sa taille
#   [152] adresse de fin des instructions  [160] cadres libres (réutilisés)
#   profileur : [176] appels  [184] instructions  [192] temps propre  [200] temps total  [208] appels en cours
#
# Cadre d'appel (un par appel, sur le tas) :
#   [0] cadre appelant  [8] descripteur  [16] instruction courante  [24] gestionnaires actifs  [32] leur table
#   ([cible, locale ou -1, pile] x n)  [40] valeur fonction appelée  [48] instruction de reprise  [56] pile de reprise
#   [64] profondeur d'appel (état [80] du mode dynamique)  [72] libre  [80..] locales, puis pile d'opérandes
#
# Cases des globales : blocs de 4096 mots jamais déplacés ; « indéfinie » = 1 (comme le mode dynamique). Le
# registre des méthodes du runtime dynamique repère une globale par son rang depuis __globals_start() : celui d'une
# case de la VM est (adresse - __globals_start()) / 8.

# ---- État ---------------------------------------------------------------------------------------------------------

func __vm_st() -> int:
    return __load64(__globals_start() + 8)

func __vm_script() -> str:
    vs := __vm_st()
    if vs == 0 or __load64(vs + 80) == 0:
        return ""
    return __as_str(__load64(vs + 80))

func __vm_argv_shift() -> int:
    vs := __vm_st()
    if vs == 0:
        return 0
    return __load64(vs + 88)

# Case du cadre courant de la tâche en cours (chaîne des cadres, pour les traces) : celle du programme principal
# dans l'état de la VM, celle d'une tâche dans son entrée de la table des tâches (mot 112, libre).
func __vm_cur_slot() -> int:
    t := __load64(__state() + 960)
    if t == 0:
        return __vm_st() + 96
    c := __rt_cur()
    if c == 0:
        return __vm_st() + 96
    return t + 128 * c + 112

# ---- Chaînes ------------------------------------------------------------------------------------------------------

# Chaîne marquée : copie de s précédée du descripteur d.
func __vm_tag_str(s: str, d: int) -> str:
    n := __nat_blen(s)
    b := __alloc(16 + n)
    __store64(b, d)
    __store64(b + 8, n)
    __copy(b + 16, __nat_bp(s), n)
    return __as_str(b + 8)

func __vm_findb(s: str, c: int) -> int:
    n := __nat_blen(s)
    p := __nat_bp(s)
    i := 0
    while i < n:
        if __load8(p + i) == c:
            return i
        i += 1
    return -1

# Dernière occurrence de « :: », ou -1.
func __vm_rfind_colons(s: str) -> int:
    p := __nat_bp(s)
    i := __nat_blen(s) - 2
    while i >= 0:
        if __load8(p + i) == 58 and __load8(p + i + 1) == 58:
            return i
        i -= 1
    return -1

func __vm_after(s: str, k: int) -> str:
    return __nat_sub(s, k, __nat_blen(s) - k)

# Nom lisible d'une fonction (displayFunctionName de VM.cpp).
func __vm_display_name(n0: str) -> str:
    n := n0
    q := __vm_rfind_colons(n)
    if q >= 0:
        n = __vm_after(n, q + 2)
    if __nat_blen(n) == 0 or n == "$entry":
        return "<module>"
    at := __vm_findb(n, 64)
    if at >= 0:
        base := __nat_sub(n, 0, at)
        if __nat_blen(base) == 0 or base == "<lambda>":
            return "<lambda>"
        return base
    h := __vm_findb(n, 35)
    if h >= 0:
        ty := __nat_sub(n, 0, h)
        q2 := __vm_rfind_colons(ty)
        if q2 >= 0:
            ty = __vm_after(ty, q2 + 2)
        return ty + "." + __vm_after(n, h + 1)
    return n

# Fonction synthétique du chargeur ($link...) : absente des traces.
func __vm_hidden(n: str) -> bool:
    bare := n
    q := __vm_rfind_colons(n)
    if q >= 0:
        bare = __vm_after(n, q + 2)
    return __nat_blen(bare) > 0 and __load8(__nat_bp(bare)) == 36 and bare != "$entry"

# ---- Lecture du fichier .albc ---------------------------------------------------------------------------------------
# Lecteur : [début][taille][position].

func __vm_need(r: int, n: int):
    if __load64(r + 16) + n > __load64(r + 8):
        __dyn_err("BytecodeError", "fichier .albc tronqué à l'octet " + __int_to_str(__load64(r + 16)))

func __vm_u8(r: int) -> int:
    __vm_need(r, 1)
    p := __load64(r + 16)
    __store64(r + 16, p + 1)
    return __load8(__load64(r) + p)

func __vm_u16(r: int) -> int:
    __vm_need(r, 2)
    p := __load64(r + 16)
    a := __load64(r) + p
    __store64(r + 16, p + 2)
    return __load8(a) | (__load8(a + 1) << 8)

func __vm_u32(r: int) -> int:
    __vm_need(r, 4)
    p := __load64(r + 16)
    a := __load64(r) + p
    __store64(r + 16, p + 4)
    return __load8(a) | (__load8(a + 1) << 8) | (__load8(a + 2) << 16) | (__load8(a + 3) << 24)

func __vm_u64(r: int) -> int:
    __vm_need(r, 8)
    p := __load64(r + 16)
    a := __load64(r) + p
    __store64(r + 16, p + 8)
    v := 0
    i := 7
    while i >= 0:
        v = (v << 8) | __load8(a + i)
        i -= 1
    return v

func __vm_text(r: int, n: int) -> str:
    __vm_need(r, n)
    p := __load64(r + 16)
    __store64(r + 16, p + n)
    return __nat_make(__load64(r) + p, n)

func __vm_rd32(a: int) -> int:
    return __load8(a) | (__load8(a + 1) << 8) | (__load8(a + 2) << 16) | (__load8(a + 3) << 24)

# Nombre d'opérandes u32 d'un opcode (src/Opcode.cpp operandCount).
func __vm_nops(op: int) -> int:
    if op == 37 or op == 66:
        return 2
    if op <= 4 or op == 25 or op == 26 or op == 27 or op == 28 or op == 30 or op == 31 or op == 32:
        return 1
    if op == 35 or op == 36 or op == 44 or op == 45 or op == 47 or op == 60 or op == 62 or op == 65 or op == 67:
        return 1
    return 0

# ---- Globales -------------------------------------------------------------------------------------------------------

# Adresse de la case de la globale `name` (créée « indéfinie » au besoin).
func __vm_gslot(name: str) -> int:
    vs := __vm_st()
    d := __load64(vs + 40)
    e := __rt_dict_index(d, __str_addr(name), 1)
    if e >= 0:
        return __load64(__load64(d + 32) + 8 * e)
    c := __load64(vs + 48)
    u := __load64(vs + 56)
    if c == 0 or u == 4096:
        c = __alloc(8 * 4096)
        __rt_list_push(__load64(vs + 64), c)
        __store64(vs + 48, c)
        u = 0
    slot := c + 8 * u
    __store64(slot, 1)
    __store64(vs + 56, u + 1)
    __rt_dict_set(d, __str_addr(name), slot, 1)
    return slot

func __vm_gindex(slot: int) -> int:
    return (slot - __globals_start()) >> 3

# Valeur de la fonction d'identifiant id (exports du prélude core), 0 si absente.
func __vm_func_by_id(id: int) -> int:
    dd := __load64(__vm_st() + 32)
    e := __rt_dict_index(dd, id, 0)
    if e < 0:
        return 0
    d := __load64(__load64(dd + 32) + 8 * e)
    return __load64(__vm_gslot(__as_str(__load64(d + 32))))

# ---- Chargement du module ---------------------------------------------------------------------------------------------

func __vm_const_value(r: int) -> int:
    t := __vm_u8(r)
    if t == 0:
        return 0
    if t == 1:
        return __dyn_bool(__vm_u8(r) != 0)
    if t == 2:
        return __dyn_int(__vm_u64(r))
    if t == 3:
        return __dyn_float_bits(__vm_u64(r))
    if t == 4:
        return __dyn_char(__vm_u32(r))
    if t == 5:
        return __dyn_byte(__vm_u8(r))
    if t == 6:
        return __dyn_str(__vm_text(r, __vm_u32(r)))
    __dyn_err("BytecodeError", "étiquette de constante inconnue " + __int_to_str(t))
    return 0

func __vm_const_str(k: int, what: str) -> str:
    return __vm_const_str_in(__vm_st(), k, what)

# Constante chaîne k d'un module (rec : [0] constantes, [8] leur nombre — l'état de la VM pour le module chargé).
func __vm_const_str_in(rec: int, k: int, what: str) -> str:
    if k >= __load64(rec + 8):
        __dyn_err("BytecodeError", what + " : index de constante " + __int_to_str(k) + " hors limites")
    v := __load64(__load64(rec) + 8 * k)
    if not __dyn_is_str(v):
        __dyn_err("TypeError", what + " : la constante référencée doit être une chaîne (nom), obtenu '" + __dyn_type_name(v) + "'")
    return __dyn_sv(v)

func __vm_load(bytes: str):
    vs := __vm_st()
    __store64(vs + 104, __str_addr(bytes))
    r := __alloc_raw(24)
    __store64(r, __nat_bp(bytes))
    __store64(r + 8, __nat_blen(bytes))
    if __nat_blen(bytes) < 4 or __load8(__nat_bp(bytes)) != 65 or __load8(__nat_bp(bytes) + 1) != 76 or __load8(__nat_bp(bytes) + 2) != 66 or __load8(__nat_bp(bytes) + 3) != 67:
        __dyn_err("BytecodeError", "signature ALBC absente")
    __store64(r + 16, 4)
    major := __vm_u16(r)
    minor := __vm_u16(r)
    if major != 0:
        __dyn_err("BytecodeError", "version majeure " + __int_to_str(major) + " non prise en charge")
    if minor > 4:
        __dyn_err("BytecodeError", "bytecode au format 0." + __int_to_str(minor) + " (plus récent que 0.4)")
    __store64(vs + 128, minor)
    __vm_u32(r) # drapeaux
    nconst := __vm_u32(r)
    nfn := __vm_u32(r)
    ncode := __vm_u32(r)
    entry := __vm_u32(r)
    consts := __alloc(8 * nconst + 8)
    __store64(vs, consts)
    __store64(vs + 8, nconst)
    i := 0
    while i < nconst:
        __store64(consts + 8 * i, __vm_const_value(r))
        i += 1
    # données du module, propres à chacune de ses fonctions (descripteur [216]) : plusieurs modules peuvent être
    # chargés l'un après l'autre (boucle interactive) en gardant les globales
    #   [0] constantes  [8] leur nombre  [16] section de code  [24] nom -> descripteur  [32] octets du module
    rec := __alloc(48)
    __store64(rec, consts)
    __store64(rec + 8, nconst)
    __store64(rec + 24, __rt_dict_new(64))
    __store64(rec + 32, __str_addr(bytes))
    __store64(vs + 112, __load64(rec + 24))
    descs := __alloc(8 * nfn + 8)
    __store64(vs + 16, descs)
    __store64(vs + 24, nfn)
    i = 0
    while i < nfn:
        d := __alloc(256)
        __store64(d + 104, __vm_u32(r))
        nc := __vm_u32(r)
        __store64(d + 112, __vm_u32(r))
        __store64(d + 120, __vm_u32(r))
        __store64(d + 80, __vm_u16(r))
        __store64(d + 88, __vm_u16(r))
        __store64(d + 16, __vm_u16(r))
        __vm_u16(r) # drapeaux
        name := __vm_const_str(nc, "name_const de la fonction " + __int_to_str(__load64(d + 104)))
        __store64(d + 32, __str_addr(__vm_tag_str(name, d)))
        __store64(d + 56, __str_addr(__vm_display_name(name)))
        if __vm_hidden(name):
            __store64(d + 64, 1)
        amax := __load64(d + 88)
        slots := amax & 32767
        if (amax & 32768) != 0:
            slots += 1
        if __vm_findb(name, 35) >= 0:
            slots += 1
        __store64(d + 72, slots)
        __store64(d + 40, __str_addr("<inconnu>"))
        __store64(d + 216, rec)
        __store64(descs + 8 * i, d)
        __rt_dict_set(__load64(vs + 32), __load64(d + 104), d, 0)
        __rt_dict_set(__load64(rec + 24), __str_addr(name), d, 1)
        if __load64(d + 104) == entry:
            __store64(vs + 72, d)
        i += 1
    __vm_need(r, ncode)
    code := __load64(r) + __load64(r + 16)
    __store64(vs + 120, code)
    __store64(rec + 16, code)
    __store64(vs + 136, ncode)
    __store64(r + 16, __load64(r + 16) + ncode)
    i = 0
    while i < nfn:
        d := __load64(descs + 8 * i)
        if __load64(d + 112) + __load64(d + 120) > ncode:
            __dyn_err("BytecodeError", "code_offset/code_length dépasse CODE_SECTION")
        if __load64(d + 120) > 0 and __load8(code + __load64(d + 112)) == 68:
            __store64(d + 96, 1)
        if minor >= 2:
            sc := __vm_u32(r)
            if sc != 4294967295 and sc < nconst:
                v := __load64(consts + 8 * sc)
                if __dyn_is_str(v) and __nat_blen(__dyn_sv(v)) > 0:
                    __store64(d + 40, __str_addr(__dyn_sv(v)))
                    __store64(d + 240, 1)
        nl := __vm_u32(r)
        __vm_need(r, 8 * nl)
        tab := __alloc_raw(16 * nl + 8)
        k := 0
        while k < nl:
            __store64(tab + 16 * k, __vm_u32(r))
            __store64(tab + 16 * k + 8, __vm_u32(r))
            k += 1
        __store64(d + 136, tab)
        __store64(d + 144, nl)
        if minor >= 3:
            nn := __vm_u32(r)
            names := __alloc(8 * nn + 8)
            __store64(names, nn)
            k = 0
            while k < nn:
                __store64(names + 8 + 8 * k, __str_addr(__vm_text(r, __vm_u32(r))))
                k += 1
            __store64(d + 168, names)
        i += 1
    if __load64(vs + 72) == 0:
        __dyn_err("BytecodeError", "ENTRY_FUNCTION introuvable dans FUNCTION_SECTION")

# ---- Décodage d'une fonction (au premier appel) ----------------------------------------------------------------------

func __vm_pops(op: int, a: int, b: int) -> int:
    if op == 0 or op == 1 or op == 3 or op == 41 or op == 43 or op == 45 or op == 47 or op == 65:
        return 0
    if op == 2 or op == 4 or op == 40 or op == 42 or op == 62 or op == 26:
        return 1
    if (op >= 5 and op <= 17) or (op >= 19 and op <= 23) or op == 33 or op == 51 or op == 53 or op == 56:
        return 2
    if op == 60 or op == 61 or op == 70 or op == 73 or op == 75 or op == 76 or op == 78 or op == 79:
        return 2
    if op == 18 or op == 24 or op == 35 or op == 46 or (op >= 48 and op <= 50) or op == 54 or op == 63 or op == 69 or op == 77:
        return 1
    if op == 27:
        return a + 1
    if op == 30 or op == 31:
        return a
    if op == 32:
        return 2 * a
    if op == 66:
        return b
    if op == 34 or op == 52 or op == 71 or op == 72:
        return 3
    if op == 36 or op == 58 or op == 59 or op == 64 or op == 55:
        return 2
    if op == 74:
        return 4
    return 0

func __vm_pushes(op: int) -> int:
    if op == 0 or op == 1 or op == 3 or op == 41 or op == 43 or op == 45 or op == 47 or op == 65:
        return 1
    if (op >= 5 and op <= 17) or (op >= 19 and op <= 23) or op == 33 or op == 51 or op == 53 or op == 56:
        return 1
    if op == 60 or op == 61 or op == 70 or op == 73 or op == 75 or op == 76 or op == 78 or op == 79:
        return 1
    if op == 18 or op == 24 or op == 35 or op == 46 or (op >= 48 and op <= 50) or op == 54 or op == 63 or op == 69 or op == 77:
        return 1
    if op == 27 or op == 30 or op == 31 or op == 32 or op == 66 or op == 52 or op == 71 or op == 74:
        return 1
    return 0

func __vm_ends(op: int) -> bool:
    return op == 29 or op == 57 or op == 39 or op == 55 or op == 28

# Indice de l'instruction au décalage relatif `off` (table offs), ou erreur.
func __vm_target(offs: int, len: int, off: int, d: int) -> int:
    if off < 0 or off >= len or __load64(offs + 8 * off) < 0:
        __dyn_err("BytecodeError", "cible de saut invalide dans " + __as_str(__load64(d + 56)))
    return __load64(offs + 8 * off)

func __vm_flow(depth: int, work: int, to: int, dd: int, n: int, d: int):
    if to >= n:
        return
    cur := __load64(depth + 8 * to)
    if cur < 0:
        __store64(depth + 8 * to, dd)
        __rt_list_push(work, to)
    elif cur != dd:
        __dyn_err("BytecodeError", "profondeur de pile incohérente dans " + __as_str(__load64(d + 56)) + " (instruction " + __int_to_str(to) + ")")

func __vm_prepare(d: int):
    rec := __load64(d + 216)
    base := __load64(rec + 16) + __load64(d + 112)
    len := __load64(d + 120)
    # 1. limites des instructions
    offs := __alloc_raw(8 * len + 8)
    i := 0
    while i < len:
        __store64(offs + 8 * i, -1)
        i += 1
    n := 0
    p := 0
    while p < len:
        op := __load8(base + p)
        if op >= 80:
            __dyn_err("BytecodeError", "octet d'opcode " + __int_to_str(op) + " non reconnu à l'offset " + __int_to_str(__load64(d + 112) + p))
        sz := 1 + 4 * __vm_nops(op)
        if p + sz > len:
            __dyn_err("BytecodeError", "instruction tronquée à l'offset " + __int_to_str(__load64(d + 112) + p))
        __store64(offs + 8 * p, n)
        n += 1
        p += sz
    code := __alloc(32 * n + 32)
    lines := __alloc_raw(8 * n + 8)
    raw := __alloc_raw(24 * n + 8) # [op, a, b] bruts, pour l'analyse de pile
    # 2. décodage brut et lignes
    tab := __load64(d + 136)
    nt := __load64(d + 144)
    k := 0
    ln := 0
    i = 0
    p = 0
    while p < len:
        op := __load8(base + p)
        na := __vm_nops(op)
        a := 0
        b := 0
        if na >= 1:
            a = __vm_rd32(base + p + 1)
        if na >= 2:
            b = __vm_rd32(base + p + 5)
        while k < nt and __load64(tab + 16 * k) <= p:
            ln = __load64(tab + 16 * k + 8)
            k += 1
        __store64(lines + 8 * i, ln)
        __store64(raw + 24 * i, op)
        __store64(raw + 24 * i + 8, a)
        __store64(raw + 24 * i + 16, b)
        i += 1
        p += 1 + 4 * na
    # 3. profondeur de pile (même analyse que le mode dynamique)
    depth := __alloc_raw(8 * n + 8)
    i = 0
    while i < n:
        __store64(depth + 8 * i, -1)
        i += 1
    work := __rt_list_new(0)
    if n > 0:
        __vm_flow(depth, work, 0, 0, n, d)
    while __load64(work) > 0:
        w := __load64(work) - 1
        i = __load64(__load64(work + 16) + 8 * w)
        __store64(work, w)
        op := __load64(raw + 24 * i)
        a := __load64(raw + 24 * i + 8)
        sd := __load64(depth + 8 * i)
        pops := __vm_pops(op, a, __load64(raw + 24 * i + 16))
        if sd < pops:
            __dyn_err("BytecodeError", "pile insuffisante pour l'opcode " + __int_to_str(op) + " dans " + __as_str(__load64(d + 56)))
        after := sd - pops + __vm_pushes(op)
        if op == 25:
            __vm_flow(depth, work, __vm_target(offs, len, a, d), after, n, d)
        elif op == 26:
            __vm_flow(depth, work, __vm_target(offs, len, a, d), after, n, d)
            __vm_flow(depth, work, i + 1, after, n, d)
        elif op == 37:
            __vm_flow(depth, work, __vm_target(offs, len, a, d), sd, n, d)
            __vm_flow(depth, work, i + 1, after, n, d)
        elif not __vm_ends(op):
            __vm_flow(depth, work, i + 1, after, n, d)
    maxd := 0
    i = 0
    while i < n:
        if __load64(depth + 8 * i) > maxd:
            maxd = __load64(depth + 8 * i)
        if __vm_pushes(__load64(raw + 24 * i)) > maxd:
            maxd = __vm_pushes(__load64(raw + 24 * i))
        i += 1
    # 4. instructions résolues
    i = 0
    while i < n:
        op := __load64(raw + 24 * i)
        a := __load64(raw + 24 * i + 8)
        b := __load64(raw + 24 * i + 16)
        ins := code + 32 * i
        __store64(ins, op)
        if op == 0:
            if a >= __load64(rec + 8):
                __dyn_err("BytecodeError", "CONST : index de constante " + __int_to_str(a) + " hors limites")
            __store64(ins + 8, __load64(__load64(rec) + 8 * a))
        elif op == 1 or op == 2 or op == 62 or op == 67:
            if a >= __load64(d + 16):
                __dyn_err("BytecodeError", "index de locale " + __int_to_str(a) + " hors limites dans " + __as_str(__load64(d + 56)))
            __store64(ins + 8, 8 * a)
        elif op == 3 or op == 4:
            nm := __vm_const_str_in(rec, a, "LOAD_GLOBAL" if op == 3 else "STORE_GLOBAL")
            __store64(ins + 8, __vm_gslot(nm))
            __store64(ins + 16, __str_addr(nm))
        elif op == 25 or op == 26:
            t := __vm_target(offs, len, a, d)
            __store64(ins + 8, code + 32 * t)
            if t <= i:
                __store64(ins + 16, 1)
        elif op == 37:
            __store64(ins + 8, code + 32 * __vm_target(offs, len, a, d))
            if b == 4294967295 or b >= __load64(d + 16):
                __store64(ins + 16, -1)
            else:
                __store64(ins + 16, 8 * b)
        elif op == 35 or op == 36 or op == 44 or op == 45 or op == 47 or op == 60:
            __store64(ins + 8, __str_addr(__vm_const_str_in(rec, a, "nom")))
        elif op == 66:
            nm := __vm_const_str_in(rec, a, "MAKE_CLOSURE")
            nd := __load64(rec + 24)
            e := __rt_dict_index(nd, __str_addr(nm), 1)
            if e < 0:
                __dyn_err("BytecodeError", "MAKE_CLOSURE : fonction '" + nm + "' introuvable")
            __store64(ins + 8, __load64(__load64(nd + 32) + 8 * e))
            __store64(ins + 16, b)
        else:
            __store64(ins + 8, a)
            __store64(ins + 16, b)
        i += 1
    __store64(d, code)
    __store64(d + 8, n)
    __store64(d + 24, maxd + 8)
    __store64(d + 48, lines)
    __store64(d + 152, code + 32 * n)
    __store64(d + 128, 1)

# ---- Appels -----------------------------------------------------------------------------------------------------------
# Un appel d'une fonction du bytecode depuis le bytecode ne récurse pas en natif : __vm_run empile le cadre et
# continue (comme la VM C++). Une activation de __vm_run (__vm_exec) ne commence que lorsqu'une native, une méthode
# liée par le runtime, une surcharge d'opérateur ou une tâche appelle une fonction du bytecode (__vm_fn_entry).

func __vm_frame(d: int, f: int) -> int:
    if __load64(d + 128) == 0:
        __vm_prepare(d)
    nl := __load64(d + 16)
    fr := __load64(d + 160)
    if fr != 0:
        __store64(d + 160, __load64(fr))
    else:
        fr = __alloc(80 + 8 * (nl + __load64(d + 24)))
    __store64(fr + 8, d)
    __store64(fr + 16, __load64(d))
    __store64(fr + 40, f)
    __store64(fr + 48, __load64(d))
    __store64(fr + 56, fr + 80 + 8 * nl)
    return fr

# Cadre rendu (retour normal) : remis à zéro (locales, pile, gestionnaires) et gardé par son descripteur pour le
# prochain appel. Aucun objet ne garde de référence à un cadre terminé (les traces copient fichier, ligne, nom).
func __vm_recycle(fr: int):
    d := __load64(fr + 8)
    __zero(fr + 80, 8 * (__load64(d + 16) + __load64(d + 24)))
    __store64(fr + 24, 0)
    __store64(fr + 40, 0)
    __store64(fr, __load64(d + 160))
    __store64(d + 160, fr)

# Code des fonctions du bytecode (convention du mode dynamique : arguments déjà normalisés par __dyn_call).
func __vm_fn_entry(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int, x: int) -> int:
    d := __load64(__load64(f + 16) - 8)
    fr := __vm_frame(d, f)
    slots := __load64(d + 72)
    if slots > __load64(d + 16):
        slots = __load64(d + 16)
    loc := fr + 80
    if slots > 0:
        __store64(loc, a0)
    if slots > 1:
        __store64(loc + 8, a1)
    if slots > 2:
        __store64(loc + 16, a2)
    if slots > 3:
        __store64(loc + 24, a3)
    if slots > 4:
        __store64(loc + 32, a4)
    if slots > 5:
        __store64(loc + 40, a5)
    if slots > 6:
        __store64(loc + 48, a6)
    if slots > 7:
        __store64(loc + 56, a7)
    i := 8
    while i < slots:
        __store64(loc + 8 * i, __dyn_xarg(x, i - 8))
        i += 1
    return __vm_exec(fr)

# Cadre prêt (arguments args[0..argc-1] copiés) si f est une fonction du bytecode appelable directement (arité
# fixe respectée, pas async), sinon 0 : l'appel passe alors par __dyn_call (natives, __call__, variadiques...).
func __vm_enter(f: int, args: int, argc: int) -> int:
    if f == 0 or __load64(f) != 10 or __load64(f + 8) != __fnaddr("__vm_fn_entry") or __load64(f + 56) != 0:
        return 0
    amax := __load64(f + 32)
    if (amax & 32768) != 0 or argc < __load64(f + 24) or argc > amax:
        return 0
    d := __load64(__load64(f + 16) - 8)
    fr := __vm_frame(d, f)
    lim := __load64(d + 72)
    if lim > __load64(d + 16):
        lim = __load64(d + 16)
    loc := fr + 80
    j := 0
    b := __load64(f + 48)
    if b != 0:
        if lim > 0:
            __store64(loc, b)
        j = 1
    i := 0
    while i < argc and j + i < lim:
        __store64(loc + 8 * (j + i), __load64(args + 8 * i))
        i += 1
    return fr

# Appel général par __dyn_call. Toutes les cases du cadre natif sont écrites avant l'appel (arguments absents : 0) :
# le GC conservatif parcourt ce cadre pendant l'appel, une case non écrite garderait une valeur périmée en vie.
func __vm_call_slow(f: int, args: int, argc: int) -> int:
    if argc > 8:
        return __vm_call_many(f, args, argc)
    a0 := 0
    a1 := 0
    a2 := 0
    a3 := 0
    a4 := 0
    a5 := 0
    a6 := 0
    a7 := 0
    if argc > 0:
        a0 = __load64(args)
    if argc > 1:
        a1 = __load64(args + 8)
    if argc > 2:
        a2 = __load64(args + 16)
    if argc > 3:
        a3 = __load64(args + 24)
    if argc > 4:
        a4 = __load64(args + 32)
    if argc > 5:
        a5 = __load64(args + 40)
    if argc > 6:
        a6 = __load64(args + 48)
    if argc > 7:
        a7 = __load64(args + 56)
    return __dyn_call(f, argc, a0, a1, a2, a3, a4, a5, a6, a7, 0)

func __vm_call_many(f: int, args: int, argc: int) -> int:
    x := __dyn_tuple_new(argc - 8)
    j := 8
    while j < argc:
        __dyn_tuple_put(x, j - 8, __load64(args + 8 * j))
        j += 1
    return __dyn_call(f, argc, __load64(args), __load64(args + 8), __load64(args + 16), __load64(args + 24),
                      __load64(args + 32), __load64(args + 40), __load64(args + 48), __load64(args + 56), x)

# gc.collect() explicite : le GC est conservatif et les cadres natifs du runtime ne sont pas remis à zéro ; la zone de
# pile où vont s'installer les cadres de l'appel (natives, collecteur) est effacée, pour qu'aucune valeur périmée
# d'un appel précédent n'y soit prise pour une racine (libération déterministe, comme la VM C++).
# Appel de gc.collect différé par __vm_run (état [304] : nombre d'arguments + 1) : résultat empilé dans le cadre courant.
func __vm_pending_collect(slot: int):
    vs := __vm_st()
    argc := __load64(vs + 304) - 1
    __store64(vs + 304, 0)
    fr := __load64(slot)
    cb := __load64(fr + 56)
    r := __vm_call_slow(__load64(cb), cb + 8, argc)
    __store64(cb, r)
    __store64(fr + 56, cb + 8)

func __vm_scrub_low() -> int:
    lo := __sp() - 16384
    t := __load64(__state() + 960)
    if t != 0 and __rt_cur() != 0:
        base := __load64(t + 128 * __rt_cur() + 8) + 8192
        if lo < base:
            lo = base
    return lo

# Activation : exécute le cadre fr (et les cadres qu'il empile) jusqu'à son retour. Une exception est routée vers le
# gestionnaire try le plus proche parmi les cadres de l'activation (du plus récent au plus ancien) ; sans gestionnaire,
# elle est propagée à l'appelant natif après relevé de la trace.
func __vm_exec(fr: int) -> int:
    ds := __dyn_ds()
    depth := __load64(ds + 80)
    if depth >= 100000:
        __dyn_recursion_error()
    __store64(fr + 64, depth + 1)
    __store64(ds + 80, depth + 1)
    if __load64(ds + 200) != 0:
        __sig_check()
    slot := __vm_cur_slot()
    __store64(fr, __load64(slot))
    __store64(slot, fr)
    cur := fr
    while true:
        done := false
        r := 0
        ex := 0
        try:
            r = __vm_run(cur, fr, slot)
            while __load64(__vm_st() + 304) != 0:
                # gc.collect() demandé par __vm_run : le cadre natif de la boucle (valeurs intermédiaires périmées)
                # et ceux des appels précédents sont morts ; la pile sous ce cadre est effacée avant la collecte.
                lo := __vm_scrub_low()
                hi := __sp() - 8
                if lo < hi:
                    __zero(lo, hi - lo)
                __vm_pending_collect(slot)
                cur = __load64(slot)
                r = __vm_run(cur, fr, slot)
            done = true
        catch e:
            __store64(__vm_st() + 304, 0)
            ex = __addr(e)
        if done:
            __store64(slot, __load64(fr))
            __store64(ds + 80, depth)
            __vm_recycle(fr)
            return r
        f := __load64(slot)
        __vm_capture(ex, f)
        if __load64(__vm_st() + 208) == 2:
            __vm_dbg_exception(ex, f)
        cur = 0
        while cur == 0:
            if __vm_handle(f, ex):
                cur = f
            elif f == fr:
                __store64(slot, __load64(fr))
                __store64(ds + 80, depth)
                __rt_throw(ex)
            else:
                f = __load64(f)
        __store64(slot, cur)
        __store64(ds + 80, __load64(cur + 64))
    return 0

# Gestionnaire try actif du cadre fr : le consomme et prépare la reprise à sa cible (pile purgée, exception liée).
func __vm_handle(fr: int, ex: int) -> bool:
    n := __load64(fr + 24)
    if n == 0:
        return false
    h := __load64(fr + 32) + 24 * (n - 1)
    __store64(fr + 24, n - 1)
    __store64(fr + 48, __load64(h))
    __store64(fr + 56, __load64(h + 16))
    lo := __load64(h + 8)
    if lo >= 0:
        __store64(fr + 80 + lo, __dyn_exc_box(ex))
    return true

# Trace de pile, relevée une fois (pile d'appels encore intacte) : [-1-n][fichier, ligne, fonction]... du cadre le plus
# ancien au plus récent ; lue par __dyn_exc_trace (e.trace) et par l'affichage d'une erreur non rattrapée.
func __vm_capture(ex: int, fr: int):
    t := __load64(ex + 16)
    if t != 0 and __load64(t) < 0:
        return
    n := 0
    f := fr
    while f != 0:
        if __load64(__load64(f + 8) + 64) == 0:
            n += 1
        f = __load64(f)
    buf := __alloc(8 + 24 * n)
    __store64(buf, -1 - n)
    k := n - 1
    f = fr
    while f != 0:
        d := __load64(f + 8)
        if __load64(d + 64) == 0:
            e := buf + 8 + 24 * k
            __store64(e, __load64(d + 40))
            line := 0
            if __load64(d + 8) > 0:
                idx := (__load64(f + 16) - __load64(d)) >> 5
                if idx >= __load64(d + 8):
                    idx = __load64(d + 8) - 1
                if idx < 0:
                    idx = 0
                line = __load64(__load64(d + 48) + 8 * idx)
            __store64(e + 8, line)
            __store64(e + 16, __load64(d + 56))
            k -= 1
        f = __load64(f)
    __store64(ex + 16, buf)

func __vm_push_handler(fr: int, target: int, local: int, sp: int):
    n := __load64(fr + 24)
    t := __load64(fr + 32)
    if t == 0 or n % 8 == 0:
        nt := __alloc(24 * (n + 8))
        if t != 0:
            __copy(nt, t, 24 * n)
        __store64(fr + 32, nt)
        t = nt
    h := t + 24 * n
    __store64(h, target)
    __store64(h + 8, local)
    __store64(h + 16, sp)
    __store64(fr + 24, n + 1)

# ---- Boucle d'exécution -------------------------------------------------------------------------------------------------

# Exécute le cadre fr0 de l'activation de base `base` ; `slot` : case du cadre courant de la tâche.
func __vm_run(fr0: int, base: int, slot: int) -> int:
    fr := fr0
    d := __load64(fr + 8)
    loc := fr + 80
    sbase := loc + 8 * __load64(d + 16)
    ip := __load64(fr + 48)
    sp := __load64(fr + 56)
    end := __load64(d + 152)
    ds := __dyn_ds()
    rv := 0
    prof := __load64(__vm_st() + 208)
    while true:
        if ip >= end:
            # retour (RETURN, HALT ou fin du code) avec la valeur rv
            if fr == base:
                return rv
            p := __load64(fr)
            __store64(slot, p)
            __store64(ds + 80, __load64(p + 64))
            __vm_recycle(fr)
            fr = p
            d = __load64(fr + 8)
            loc = fr + 80
            sbase = loc + 8 * __load64(d + 16)
            ip = __load64(fr + 48)
            sp = __load64(fr + 56)
            end = __load64(d + 152)
            __store64(sp, rv)
            sp += 8
            rv = 0
            continue
        __store64(fr + 16, ip)
        if prof != 0:
            if prof == 2:
                __store64(fr + 48, ip)
                __store64(fr + 56, sp)
                __vm_dbg_hook(fr, ip)
            else:
                __vm_prof(fr, ip)
        op := __load64(ip)
        if op == 1:
            __store64(sp, __load64(loc + __load64(ip + 8)))
            sp += 8
            ip += 32
        elif op == 0:
            __store64(sp, __load64(ip + 8))
            sp += 8
            ip += 32
        elif op == 3:
            v := __load64(__load64(ip + 8))
            if v == 1:
                __dyn_name_error(__as_str(__load64(ip + 16)))
            __store64(sp, v)
            sp += 8
            ip += 32
        elif op == 2:
            sp -= 8
            __store64(loc + __load64(ip + 8), __load64(sp))
            ip += 32
        elif op == 27:
            argc := __load64(ip + 8)
            cb := sp - 8 * (argc + 1)
            nf := __vm_enter(__load64(cb), cb + 8, argc)
            if nf == 0:
                fv := __load64(cb)
                if fv != 0 and __load64(fv) == 11 and __load64(fv + 8) == __vm_gc_collect_code():
                    # gc.collect() explicite : exécuté par l'activation (__vm_exec), une fois ce cadre natif quitté
                    __store64(fr + 48, ip + 32)
                    __store64(fr + 56, cb)
                    __store64(__vm_st() + 304, argc + 1)
                    return 0
                r := __vm_call_slow(fv, cb + 8, argc)
                __store64(cb, r)
                r = 0 # le GC est conservatif : pas de copie périmée d'une valeur dans le cadre de la boucle
                sp = cb + 8
                ip += 32
            else:
                __store64(fr + 48, ip + 32)
                __store64(fr + 56, cb)
                depth := __load64(ds + 80)
                if depth >= 100000:
                    __dyn_recursion_error()
                __store64(nf, fr)
                __store64(nf + 64, depth + 1)
                __store64(ds + 80, depth + 1)
                __store64(slot, nf)
                fr = nf
                d = __load64(fr + 8)
                loc = fr + 80
                sbase = loc + 8 * __load64(d + 16)
                ip = __load64(fr + 48)
                sp = __load64(fr + 56)
                end = __load64(d + 152)
                if __load64(ds + 200) != 0:
                    __sig_check()
        elif op == 26:
            sp -= 8
            v := __load64(sp)
            if v == __load64(ds):
                ip += 32
            elif v == __load64(ds + 8):
                ip = __load64(ip + 8)
            elif __dyn_truthy(v):
                ip += 32
            else:
                ip = __load64(ip + 8)
        elif op == 35:
            __store64(sp - 8, __dyn_get_member(__load64(sp - 8), __as_str(__load64(ip + 8))))
            ip += 32
        elif op == 25:
            if __load64(ip + 16) != 0 and __load64(ds + 200) != 0:
                __sig_check()
            ip = __load64(ip + 8)
        elif op == 40:
            sp -= 8
            ip += 32
        elif op >= 12 and op <= 17:
            sp -= 8
            l := __load64(sp - 8)
            rr := __load64(sp)
            res := 0
            if l != 0 and rr != 0 and __load64(l) == 1 and __load64(rr) == 1:
                a := __load64(l + 8)
                b := __load64(rr + 8)
                c := false
                if op == 12:
                    c = a == b
                elif op == 13:
                    c = a != b
                elif op == 14:
                    c = a < b
                elif op == 15:
                    c = a <= b
                elif op == 16:
                    c = a > b
                else:
                    c = a >= b
                if c:
                    res = __load64(ds)
                else:
                    res = __load64(ds + 8)
            else:
                res = __dyn_compare(op, l, rr)
            __store64(sp - 8, res)
            ip += 32
        elif op >= 5 and op <= 7:
            sp -= 8
            l := __load64(sp - 8)
            rr := __load64(sp)
            res := 0
            if l != 0 and rr != 0 and __load64(l) == 1 and __load64(rr) == 1:
                if op == 5:
                    res = __dyn_int(__load64(l + 8) + __load64(rr + 8))
                elif op == 6:
                    res = __dyn_int(__load64(l + 8) - __load64(rr + 8))
                else:
                    res = __dyn_int(__load64(l + 8) * __load64(rr + 8))
            else:
                res = __dyn_arith(op, l, rr)
            __store64(sp - 8, res)
            ip += 32
        elif op == 29 or op == 57:
            if sp > sbase:
                rv = __load64(sp - 8)
            ip = end
        elif op == 33:
            sp -= 8
            __store64(sp - 8, __dyn_get_index(__load64(sp - 8), __load64(sp)))
            ip += 32
        elif op == 41:
            __store64(sp, __load64(sp - 8))
            sp += 8
            ip += 32
        elif op == 37:
            __vm_push_handler(fr, __load64(ip + 8), __load64(ip + 16), sp)
            ip += 32
        elif op == 38:
            n := __load64(fr + 24)
            if n == 0:
                __dyn_err("BytecodeError", "TRY_END sans TRY_BEGIN")
            __store64(fr + 24, n - 1)
            ip += 32
        elif op == 63:
            __store64(sp - 8, __dyn_cell_get(__load64(sp - 8)))
            ip += 32
        elif op == 65:
            __store64(sp, __dyn_upvalue(__load64(fr + 40), __load64(ip + 8)))
            sp += 8
            ip += 32
        else:
            sp = __vm_rare(fr, ip, sp)
            ip += 32
    return 0

# Opcodes moins fréquents (cadre plus petit pour la boucle principale) : renvoie la nouvelle pile.
func __vm_rare(fr: int, ip: int, sp: int) -> int:
    op := __load64(ip)
    a := __load64(ip + 8)
    if op == 4:
        __store64(a, __load64(sp - 8))
        return sp - 8
    if op == 36:
        __dyn_set_member(__load64(sp - 16), __as_str(a), __load64(sp - 8))
        return sp - 16
    if op == 34:
        __dyn_set_index(__load64(sp - 24), __load64(sp - 16), __load64(sp - 8))
        return sp - 24
    if op == 18:
        __store64(sp - 8, __dyn_not(__load64(sp - 8)))
        return sp
    if op >= 8 and op <= 11:
        __store64(sp - 16, __dyn_arith(op, __load64(sp - 16), __load64(sp - 8)))
        return sp - 8
    if op >= 19 and op <= 23:
        __store64(sp - 16, __dyn_bitwise(op, __load64(sp - 16), __load64(sp - 8)))
        return sp - 8
    if op == 24:
        __store64(sp - 8, __dyn_bitnot(__load64(sp - 8)))
        return sp
    if op == 30 or op == 31:
        base := sp - 8 * a
        l := 0
        if op == 30:
            l = __dyn_list_new(a)
        else:
            l = __dyn_tuple_new(a)
        j := 0
        while j < a:
            if op == 30:
                __dyn_list_put(l, j, __load64(base + 8 * j))
            else:
                __dyn_tuple_put(l, j, __load64(base + 8 * j))
            j += 1
        __store64(base, l)
        return base + 8
    if op == 32:
        base := sp - 16 * a
        dd := __dyn_dict_new()
        j := 0
        while j < a:
            __dyn_dict_lit_set(dd, __load64(base + 16 * j), __load64(base + 16 * j + 8))
            j += 1
        __store64(base, dd)
        return base + 8
    if op == 42:
        if __load64(__vm_st() + 208) == 2:
            __vm_dbg_print(__load64(sp - 8))
        else:
            __dyn_print(__load64(sp - 8))
        return sp - 8
    if op == 43:
        if __load64(__vm_st() + 208) == 2:
            __store64(sp, __vm_dbg_input())
        else:
            __store64(sp, __dyn_input())
        return sp + 8
    if op == 39:
        __dyn_throw(__load64(sp - 8))
        return sp
    if op == 55:
        __dyn_raise(__load64(sp - 16), __load64(sp - 8))
        return sp
    if op == 46:
        __store64(sp - 8, __dyn_to_string(__load64(sp - 8)))
        return sp
    if op == 48:
        __store64(sp - 8, __dyn_type_name_v(__load64(sp - 8)))
        return sp
    if op == 49:
        __store64(sp - 8, __dyn_len(__load64(sp - 8)))
        return sp
    if op == 50:
        __store64(sp - 8, __dyn_dict_keys(__load64(sp - 8)))
        return sp
    if op == 54:
        __store64(sp - 8, __dyn_list_clear(__load64(sp - 8)))
        return sp
    if op == 69:
        __store64(sp - 8, __dyn_await(__load64(sp - 8)))
        return sp
    if op == 77:
        __store64(sp - 8, __dyn_list_to_tuple(__load64(sp - 8)))
        return sp
    if op == 51 or op == 53 or op == 56 or op == 61 or op == 70 or op == 73 or op == 75 or op == 76 or op == 78:
        x := __load64(sp - 16)
        y := __load64(sp - 8)
        r := 0
        if op == 51:
            r = __dyn_list_append(x, y)
        elif op == 53:
            r = __dyn_list_remove_at(x, y)
        elif op == 56:
            r = __dyn_dict_remove_key(x, y)
        elif op == 61:
            r = __dyn_instance_of(x, y)
        elif op == 70:
            r = __dyn_exc_matches(x, y)
        elif op == 73:
            r = __dyn_contains(x, y)
        elif op == 75:
            r = __dyn_del_item(x, y)
        elif op == 76:
            r = __dyn_list_extend(x, y)
        else:
            r = __dyn_dict_update(x, y)
        __store64(sp - 16, r)
        return sp - 8
    if op == 52:
        __store64(sp - 24, __dyn_list_insert(__load64(sp - 24), __load64(sp - 16), __load64(sp - 8)))
        return sp - 16
    if op == 58:
        __dyn_def_class(__load64(sp - 16), __load64(sp - 8))
        return sp - 16
    if op == 59:
        __dyn_add_interface(__load64(sp - 16), __load64(sp - 8))
        return sp - 16
    if op == 60:
        __store64(sp - 16, __dyn_get_super(__load64(sp - 16), __load64(sp - 8), __as_str(a)))
        return sp - 8
    if op == 62:
        __store64(fr + 80 + a, __dyn_cell_new(__load64(sp - 8)))
        return sp - 8
    if op == 67:
        __store64(fr + 80 + a, __dyn_cell_empty())
        return sp
    if op == 64:
        __dyn_cell_set(__load64(sp - 8), __load64(sp - 16))
        return sp - 16
    if op == 66:
        k := __load64(ip + 16)
        base := sp - 8 * k
        env := 0
        if k > 0:
            env = __dyn_tuple_new(k)
            j := 0
            while j < k:
                __dyn_tuple_put(env, j, __load64(base + 8 * j))
                j += 1
        md := a
        __store64(base, __dyn_func_new(__fnaddr("__vm_fn_entry"), __as_str(__load64(md + 32)), __load64(md + 80), __load64(md + 88), env, __load64(md + 96)))
        return base + 8
    if op == 68:
        return sp
    if op == 71:
        __dyn_check_type(__load64(sp - 24), __load64(sp - 16), __load64(sp - 8))
        return sp - 16
    if op == 72:
        __dyn_declare_field_type(__load64(sp - 24), __load64(sp - 16), __load64(sp - 8))
        return sp - 24
    if op == 74:
        __store64(sp - 32, __dyn_get_slice(__load64(sp - 32), __load64(sp - 24), __load64(sp - 16), __load64(sp - 8)))
        return sp - 24
    if op == 79:
        __store64(sp - 16, __dyn_call_spread(__load64(sp - 16), __load64(sp - 8)))
        return sp - 8
    if op == 47:
        __store64(sp, __dyn_new_instance(__as_str(a)))
        return sp + 8
    if op == 45:
        mo := __vm_module(__as_str(a))
        if mo == 0:
            __dyn_import_error(__as_str(a))
        __store64(sp, mo)
        return sp + 8
    if op == 44:
        mo := __vm_module(__as_str(a))
        if mo == 0:
            __dyn_import_error(__as_str(a))
        fd := __load64(mo + 16)
        used := __load64(fd + 8)
        e := 0
        while e < used:
            if __load64(__load64(fd + 40) + 8 * e) >= 0:
                nm := __as_str(__load64(__load64(fd + 24) + 8 * e))
                __store64(__vm_gslot(nm), __dyn_get_member(mo, nm))
            e += 1
        return sp
    if op == 28:
        __dyn_err("BytecodeError", "opcode CALL_NATIVE non pris en charge")
    __dyn_err("BytecodeError", "opcode " + __int_to_str(op) + " non pris en charge par la VM")
    return sp

# ---- Programme principal ------------------------------------------------------------------------------------------------

func __vm_usage():
    __write_err("usage: alexvm fichier.albc [arguments...]\n")
    __flush()
    __exit(2)

func __vm_path_key(p: str) -> str:
    n := __nat_blen(p)
    while n > 1 and __load8(__nat_bp(p) + n - 1) == 47:
        n -= 1
    return __nat_sub(p, 0, n)

# pathRelativeTo (alex/PathPrefix.hpp) : chemin relatif à dir s'il se trouve dessous, sinon inchangé.
func __vm_rel(path: str, dir: str) -> str:
    if __nat_blen(dir) == 0:
        return path
    pk := __vm_path_key(path)
    dk := __vm_path_key(dir)
    np := __nat_blen(pk)
    nd := __nat_blen(dk)
    if np < nd:
        return path
    i := 0
    while i < nd:
        if __load8(__nat_bp(pk) + i) != __load8(__nat_bp(dk) + i):
            return path
        i += 1
    dslash := __load8(__nat_bp(dk) + nd - 1) == 47
    if not (np == nd or __load8(__nat_bp(pk) + nd) == 47 or dslash):
        return path
    k := nd
    if not dslash:
        k += 1
    if k >= __nat_blen(path):
        return ""
    return __vm_after(path, k)

# Exception non rattrapée : trace (sauf ALEX_NO_TRACE=1), puis « Type: message », code de sortie 1 (comme alexc run).
func __vm_uncaught(ex: int):
    __flush()
    if __load64(__vm_st() + 208) == 2:
        __th_join_all()
        __vm_dbg_finish("exception", __rt_exc_str(ex))
    t := __load64(ex + 16)
    if not __rt_env("ALEX_NO_TRACE=1") and t != 0 and __load64(t) < -1:
        cwd := ""
        buf := __alloc_raw(4096)
        if __syscall(79, buf, 4096) >= 0:
            cwd = __nat_from_c(buf)
        sb := __rt_sb_new()
        __rt_sb_add(sb, "Trace (appel le plus récent en dernier) :\n")
        k := 0
        while k < -1 - __load64(t):
            e := t + 8 + 24 * k
            __rt_sb_add(sb, "  ")
            __rt_sb_add(sb, __vm_rel(__as_str(__load64(e)), cwd))
            if __load64(e + 8) > 0:
                __rt_sb_add(sb, ":")
                __rt_sb_add(sb, __int_to_str(__load64(e + 8)))
            __rt_sb_add(sb, ", dans ")
            __rt_sb_add(sb, __as_str(__load64(e + 16)))
            __rt_sb_add(sb, "\n")
            k += 1
        __write_err(__rt_sb_str(sb))
    __th_join_all()
    __vm_prof_report()
    __write_err(__rt_exc_str(ex) + "\n")
    __fd_restore_all()
    __flush()
    __exit(1)

# Fonctions du module chargé, comme globales (et registre des méthodes « Type#m »), puis core ; renvoie la valeur
# fonction du point d'entrée.
func __vm_install() -> int:
    vs := __vm_st()
    entry := __fnaddr("__vm_fn_entry")
    nf := __load64(vs + 24)
    i := 0
    efn := 0
    while i < nf:
        d := __load64(__load64(vs + 16) + 8 * i)
        nm := __as_str(__load64(d + 32))
        slot := __vm_gslot(nm)
        fv := __dyn_func_new(entry, nm, __load64(d + 80), __load64(d + 88), 0, __load64(d + 96))
        __store64(slot, fv)
        if __vm_findb(nm, 35) >= 0:
            __dyn_reg_method(nm, __vm_gindex(slot))
        if d == __load64(vs + 72):
            efn = fv
        i += 1
    core := __vm_core_boot()
    __store64(__vm_gslot("len"), __dyn_get_member(core, "len"))
    __store64(__vm_gslot("to_int"), __dyn_get_member(core, "to_int"))
    __store64(__vm_gslot("core"), core)
    return efn

# --parent PID : la VM meurt avec alexc (arrêt par un IDE, délai dépassé, gestionnaire des tâches). Linux :
# prctl(PR_SET_PDEATHSIG, SIGKILL) puis contrôle que le parent n'est pas déjà parti. Windows : contrôle, puis attente
# du processus parent par le pool de threads de Windows (RegisterWaitForSingleObject), dont le rappel est ExitProcess
# lui-même — rappel(contexte = 1, délai écoulé) revient à ExitProcess(1) : aucun code ALEX hors du fil principal.
func __vm_watch_parent(ppid: int):
    if __windows():
        if __syscall(110) != ppid:
            __exit(1)
        h := __wincall("OpenProcess", 1048576, 0, ppid) # SYNCHRONIZE
        if h != 0:
            k32 := __wincall("GetModuleHandleW", __rt_win_wide(__nat_c("kernel32.dll")))
            ep := __wincall("GetProcAddress", k32, __nat_c("ExitProcess"))
            if ep != 0:
                wh := __alloc_raw(8)
                __wincall("RegisterWaitForSingleObject", wh, h, ep, 1, 4294967295, 8) # INFINITE, WT_EXECUTEONLYONCE
    else:
        __syscall(157, 1, 9, 0, 0, 0)
        if __syscall(110) != ppid:
            __exit(1)

# Canal de commande avec alexc (repl, debug). Sous Windows c'est un tube nommé (\\.\pipe\...) dont alexc crée
# l'extrémité serveur après avoir lancé la VM : nouvelles tentatives pendant 10 s (fichier absent, instance occupée).
func __vm_open_chan(path: str) -> int:
    fd := __syscall(2, __nat_c(path), 2 | 524288)
    if __windows():
        k := 0
        while fd < 0 and k < 1000:
            __wincall("Sleep", 10)
            fd = __syscall(2, __nat_c(path), 2 | 524288)
            k += 1
    return fd

func __vm_read_fd_line(fd: int) -> str:
    sb := __rt_sb_new()
    b := __alloc_raw(8)
    while true:
        k := __syscall(0, fd, b, 1)
        if k == -4:
            continue
        if k <= 0:
            return __rt_sb_str(sb)
        c := __load8(b)
        if c == 10:
            return __rt_sb_str(sb)
        __rt_sb_byte(sb, c)
    return ""

# Boucle interactive (`alexc repl`) : la VM lit les lignes sur l'entrée standard (même tampon qu'input()), les
# envoie au compilateur (alexc) par le tube nommé req, qui répond sur rep « R chemin.albc » (module compilé) ou
# « E » (erreur déjà affichée) ; chaque module est chargé et exécuté en gardant les globales des précédents, sa
# valeur (expression seule sur la ligne) est affichée si elle n'est pas null.
func __vm_repl(req: str, rep: str):
    vs := __vm_st()
    fw := __vm_open_chan(req)
    fr := __vm_open_chan(rep)
    if fw < 0 or fr < 0:
        __write_err("alexvm --repl : tubes de commande inaccessibles\n")
        __exit(2)
    __store64(vs + 80, __str_addr("<repl>"))
    while true:
        __nat_write_fd(1, ">>> ")
        __flush()
        line := __rt_input()
        if __nat_blen(line) == 0:
            if __load64(__state() + 824) != 0:
                __nat_write_fd(1, "\n")
                break
            continue
        __nat_write_fd(fw, line + "\n")
        reply := __vm_read_fd_line(fr)
        if __nat_blen(reply) == 0:
            break
        if __nat_blen(reply) < 3 or __load8(__nat_bp(reply)) != 82:
            continue
        path := __vm_after(reply, 2)
        ex := 0
        try:
            fd := __syscall(2, __nat_c(path), 0)
            if fd < 0:
                __dyn_err("IoError", "impossible de lire '" + path + "'")
            bytes := __nat_read_fd(fd, -1)
            __syscall(3, fd)
            __vm_load(bytes)
            efn := __vm_install()
            __store64(vs + 96, 0)
            r := __vm_fn_entry(efn, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
            if r != 0:
                __dyn_print(r)
        catch e:
            ex = __addr(e)
        __flush()
        if ex != 0:
            __write_err(__rt_exc_str(ex) + "\n")
        __flush()
    __syscall(3, fw)
    __syscall(3, fr)
    __dyn_end()
    __flush()
    __exit(0)

# ---- Exécutable autonome (`alexc build --standalone`) ------------------------------------------------------------
# Bytecode embarqué en fin d'exécutable : [bytecode][taille u64 petit-boutiste]["ALEXAPP1"] (docs/STANDALONE.md).
# Renvoie le bytecode, "" sans remorque ; remorque invalide : message et code 1.
func __vm_self_exe() -> str:
    if __windows():
        mb := __alloc_raw(4104)
        mk := __rt_w32(__wincall("GetModuleFileNameW", 0, mb, 2048))
        if mk > 0:
            return __pw_narrow(mb, mk)
        return ""
    return "/proc/self/exe"

func __vm_payload() -> str:
    exe := __vm_self_exe()
    if __nat_blen(exe) == 0:
        return ""
    fd := __syscall(2, __nat_c(exe), 0)
    if fd < 0:
        return ""
    size := __syscall(8, fd, 0, 2)
    if size < 16:
        __syscall(3, fd)
        return ""
    __syscall(8, fd, size - 16, 0)
    tail := __nat_read_fd(fd, 16)
    if __nat_blen(tail) != 16 or __nat_sub(tail, 8, 8) != "ALEXAPP1":
        __syscall(3, fd)
        return ""
    tp := __nat_bp(tail)
    n := 0
    i := 7
    while i >= 0:
        n = (n << 8) | __load8(tp + i)
        i -= 1
    if n <= 0 or n > size - 16:
        __syscall(3, fd)
        __write_err("erreur: exécutable autonome corrompu : taille de bytecode embarqué invalide\n")
        __exit(1)
    __syscall(8, fd, size - 16 - n, 0)
    bytes := __nat_read_fd(fd, n)
    __syscall(3, fd)
    return bytes

func __vm_main():
    __dyn_init()
    if __windows():
        __store64(__state() + 1600, 1) # mode texte de la CRT, comme la VM C++ sous Windows (LF <-> CR LF)
    vs := __alloc(512)
    __store64(__globals_start() + 8, vs)
    __store64(vs + 32, __rt_dict_new(64))
    __store64(vs + 40, __rt_dict_new(256))
    __store64(vs + 64, __rt_list_new(0))
    __store64(vs + 112, __rt_dict_new(64))
    # alexvm [--script NOM] [--profile[=rapport.json]] prog.albc [arguments...] : --script fixe argv[0] du programme
    # (os.args()), comme `alexc run prog.al` qui y met le source plutôt que le .albc compilé ; --profile : profileur
    # (rapport sur stderr, et JSON dans le fichier donné), comme `alexc run --profile`.
    sp := __argv_base()
    argc := __load64(sp)
    ai := 1
    script := ""
    del_after := 0
    payload := ""
    payload = __vm_payload()
    standalone := __nat_blen(payload) > 0
    if standalone:
        ai = 0      # toute la ligne de commande appartient à l'application (os.args()[0] : l'exécutable)
    while not standalone and ai + 1 < argc:
        opt := __nat_from_c(__load64(sp + 8 + 8 * ai))
        if opt == "--script":
            script = __nat_from_c(__load64(sp + 16 + 8 * ai))
            ai += 2
        elif opt == "--parent" and ai + 2 < argc:
            # lancée par alexc run : meurt avec son parent (prctl PR_SET_PDEATHSIG, SIGKILL), comme le programme
            # exécuté dans le processus d'alex le ferait
            ppid := __vm_dbg_atoi(__nat_from_c(__load64(sp + 16 + 8 * ai)))
            if not __vm_is_fil():
                __vm_watch_parent(ppid)
            ai += 2
        elif opt == "--delete":
            if not __vm_is_fil():
                del_after = 1
            ai += 1
        elif opt == "--debug" and ai + 6 < argc:
            g := sp + 16 + 8 * ai
            __vm_dbg_start(__nat_from_c(__load64(g)), __nat_from_c(__load64(g + 8)), __vm_dbg_atoi(__nat_from_c(__load64(g + 16))), __nat_from_c(__load64(g + 24)), __nat_from_c(__load64(g + 32)), __vm_dbg_atoi(__nat_from_c(__load64(g + 40))))
            ai += 7
        elif opt == "--repl" and ai + 2 < argc:
            __vm_repl(__nat_from_c(__load64(sp + 16 + 8 * ai)), __nat_from_c(__load64(sp + 24 + 8 * ai)))
        elif opt == "--profile":
            __store64(vs + 208, 1)
            ai += 1
        elif __nat_blen(opt) > 10 and __nat_sub(opt, 0, 10) == "--profile=":
            __store64(vs + 208, 1)
            __store64(vs + 216, __str_addr(__vm_after(opt, 10)))
            ai += 1
        else:
            break
    if ai >= argc:
        __vm_usage()
    path := __nat_from_c(__load64(sp + 8 + 8 * ai))
    if __nat_blen(script) == 0:
        script = path
    __store64(vs + 80, __str_addr(script))
    __store64(vs + 88, ai)
    ex := 0
    r := 0
    try:
        bytes := ""
        if __vm_is_fil():
            bytes = __vm_fil_module()
        elif standalone:
            bytes = payload
        else:
            fd := __syscall(2, __nat_c(path), 0)
            if fd < 0:
                __dyn_err("IoError", "impossible de lire '" + path + "'")
            bytes = __nat_read_fd(fd, -1)
            __syscall(3, fd)
        if __windows():
            __store64(__dyn_ds() + 488, __str_addr(bytes)) # copié dans la région partagée au premier fil
        if del_after != 0:
            __syscall(87, __nat_c(path))
        __vm_load(bytes)
    catch e:
        ex = __addr(e)
    if ex != 0:
        __flush()
        __write_err(__rt_exc_str(ex) + "\n")
        __exit(1)
    efn := __vm_install()
    if __windows():
        __store64(__dyn_ds() + 368, 1) # la VM sait lancer des fils (processus, voir __vm_fil_windows)
        __vm_fil_windows(efn)
    try:
        r = __vm_fn_entry(efn, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
    catch e2:
        ex = __addr(e2)
    if ex != 0:
        __vm_uncaught(ex)
    __dyn_end()
    __flush()
    if __load64(vs + 208) == 2:
        __vm_dbg_finish("terminated", "")
    __vm_prof_report()
    __flush()
    __exit(0)

# ---- Fils sous Windows ---------------------------------------------------------------------------------------
# Processus fil (ALEX_FIL dans l'environnement) : ni --parent (son parent est la VM qui l'a lancé), ni --delete ; le
# module vient de la région partagée (4e champ de ALEX_FIL : copie [longueur][octets] faite par le programme
# principal), le .albc temporaire d'alexc run ayant pu être effacé.
func __vm_is_fil() -> bool:
    if __windows():
        return __nat_env_find("ALEX_FIL") >= 0
    else:
        return false

func __vm_fil_module() -> str:
    if __windows():
        parts := __nat_split_bytes(__nat_env_get("ALEX_FIL", ""), 58)
        if __load64(parts) != 4:
            __dyn_err("IoError", "thread : description du fil invalide")
        h := __vm_dbg_atoi(__as_str(__rt_vec_at(parts, 0)))
        base := __vm_dbg_atoi(__as_str(__rt_vec_at(parts, 1)))
        if __wincall("MapViewOfFileEx", h, 983071, 0, 0, 0, base) != base:
            __write_err("thread : région partagée inaccessible dans un fil\n")
            __exit(1)
        __store64(__dyn_ds() + 304, h)
        __store64(__dyn_ds() + 144, base)
        return __th_blob_str(__vm_dbg_atoi(__as_str(__rt_vec_at(parts, 3))))
    else:
        return ""

func __vm_noop_entry(n: int) -> int:
    return 0

func __vm_qualified(name: str) -> bool:
    q := 0
    while q + 1 < __nat_blen(name):
        if __load8(__nat_bp(name) + q) == 58 and __load8(__nat_bp(name) + q + 1) == 58:
            return true
        q += 1
    return false

# Processus lancé par thread.spawn (RuntimeDynNat, « Windows : fils = processus ») : ALEX_FIL=section:adresse:fil.
# Projette la région partagée à la même adresse, importe le programme (son code de haut niveau, `thread.is_main()`
# faux, thread.spawn y renvoie -1 ; sauté si la fonction du fil appartient à un module de bibliothèque), puis
# appelle la fonction du fil avec ses arguments ; ne revient pas.
func __vm_fil_windows(efn: int):
    if __windows():
        spec := __nat_env_get("ALEX_FIL", "")
        if __nat_blen(spec) == 0:
            return
        i := __nat_env_find("ALEX_FIL")
        if i >= 0:
            __rt_vec_remove(__nat_env(), __rt_vec_at(__nat_env(), i))
        parts := __nat_split_bytes(spec, 58)
        if __load64(parts) != 4:
            return
        h := __vm_dbg_atoi(__as_str(__rt_vec_at(parts, 0)))
        base := __vm_dbg_atoi(__as_str(__rt_vec_at(parts, 1)))
        id := __vm_dbg_atoi(__as_str(__rt_vec_at(parts, 2)))
        ds := __dyn_ds()
        __store64(ds + 304, h)
        __store64(ds + 144, base)
        w := __th_worker_entry(base, id)
        __store64(ds + 120, id)
        __store64(ds + 128, __load64(w + 56))
        __store64(ds + 136, __load64(w + 64))
        __store64(ds + 472, 1)
        # Fonction d'un module de bibliothèque (« module::nom », réserve de fils d'assets...) : seuls les modules
        # importés s'initialisent ; le code de haut niveau du programme principal ($entry) n'est pas exécuté, il n'a
        # donc pas besoin de `if thread.is_main():` (même comportement que sous Linux, où le fil est une copie).
        fname := __th_blob_str(__load64(w + 104))
        if __vm_qualified(fname):
            __store64(__vm_gslot("$entry"), __dyn_native_new(__fnaddr("__vm_noop_entry"), "$entry"))
        ex := 0
        try:
            __vm_fn_entry(efn, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        catch e:
            ex = __addr(e)
        __store64(ds + 472, 0)
        if ex != 0:
            __th_failure(w, base, ex)
            __th_finish(w, base, false)
        name := __th_blob_str(__load64(w + 104))
        f := __load64(__vm_gslot(name))
        __th_child(id, w, f, __th_blob_str(__load64(w + 112)), __load64(w + 96), __load64(w + 120))

# ---- Débogueur (`alexc debug`) -----------------------------------------------------------------------------------
# alexvm --debug CMD EVT PROTOCOLE ENTREE BIBLIO EXC [--script NOM] prog.albc [arguments...] : la VM exécute le
# programme sous le contrôle du frontal (alexc debug, commands.debug), qui parle le protocole JSON Lines avec
# l'IDE ; entre eux, deux tubes nommés (commandes CMD, événements EVT), une ligne par message, champs séparés par
# des tabulations (« \ », tabulation, fin de ligne et retour chariot échappés).
#
# Comme DebugController (include/alex/vm/DebugController.hpp) : arrêt d'entrée, pause demandée, pas à pas (entrer,
# passer, sortir — nouvelle ligne pour un niveau d'appel), points d'arrêt (options évaluées par le frontal),
# arrêt sur exception non rattrapée (pile intacte) ; inspection pendant l'arrêt comme DebugInspector (variables
# nommées, dépliables par références, globales, aperçus) et opérations élémentaires de son évaluateur.
#
# Événements : P raison fichier ligne [type message] (arrêt) · H id fichier ligne (point d'arrêt à options : le
# frontal répond y ou n) · O texte (print, protocole 2) · I (demande d'entrée) · R valeur | ! message (réponse) ·
# X terminated|stopped|exception message (fin).
# Commandes : c · s into|over|out · p · q · ba|br fichier ligne · bo id fichier ligne · bc fichier · be 0|1 · i texte ·
# requêtes à l'arrêt : F (cadres) · F1 (protocole 1) · G (globales) · K réf (enfants) · N cadre nom · M h membre ·
# X h valeur · L h · D h · E h1 h2 · Q h (aperçu) · R h (aperçu et référence).
#
# État (état de la VM [312]) :
#   [0] mode (0 continuer, 1 entrer, 2 passer, 3 sortir)  [8] pause demandée  [16] profondeur d'origine
#   [24] entrée faite  [32] arrêt sur exception  [40] fichier principal normalisé  [48] préfixe de bibliothèque
#   [56] points d'arrêt (fichier normalisé -> (ligne -> id + 1))  [64] lignes par profondeur [80] leur nombre
#   [72] leur capacité  [88] tube des commandes  [96] tube des événements  [104] protocole  [112] valeurs (requêtes)
#   [120] cadre arrêté  [128] compteur de scrutation  [136] entrées en attente  [144] dernière exception signalée
#   [176] références (variables dépliables)  [184] profondeur à l'arrêt  [192] cmd : fin de flux
# Descripteur : [168] noms des locales  [224] fichier normalisé  [232] drapeaux (1 calculés, 2 fichier source,
# 4 bibliothèque, 8 fichier principal)  [240] fichier source présent.

func __vm_dbg() -> int:
    return __load64(__vm_st() + 312)

func __vm_dbg_on() -> bool:
    vs := __vm_st()
    return vs != 0 and __load64(vs + 312) != 0

func __vm_dbg_esc(s: str) -> str:
    n := __nat_blen(s)
    p := __nat_bp(s)
    sb := __rt_sb_new()
    i := 0
    while i < n:
        c := __load8(p + i)
        if c == 92:
            __rt_sb_add(sb, "\\\\")
        elif c == 9:
            __rt_sb_add(sb, "\\t")
        elif c == 10:
            __rt_sb_add(sb, "\\n")
        elif c == 13:
            __rt_sb_add(sb, "\\r")
        else:
            __rt_sb_byte(sb, c)
        i += 1
    return __rt_sb_str(sb)

func __vm_dbg_unesc(s: str) -> str:
    n := __nat_blen(s)
    p := __nat_bp(s)
    sb := __rt_sb_new()
    i := 0
    while i < n:
        c := __load8(p + i)
        if c == 92 and i + 1 < n:
            e := __load8(p + i + 1)
            i += 2
            if e == 116:
                __rt_sb_byte(sb, 9)
            elif e == 110:
                __rt_sb_byte(sb, 10)
            elif e == 114:
                __rt_sb_byte(sb, 13)
            else:
                __rt_sb_byte(sb, e)
            continue
        __rt_sb_byte(sb, c)
        i += 1
    return __rt_sb_str(sb)

# Champ k (séparé par des tabulations) d'une ligne de commande, déséchappé ; "" s'il manque.
func __vm_dbg_field(s: str, k: int) -> str:
    n := __nat_blen(s)
    p := __nat_bp(s)
    i := 0
    f := 0
    start := 0
    while i <= n:
        if i == n or __load8(p + i) == 9:
            if f == k:
                return __vm_dbg_unesc(__nat_sub(s, start, i - start))
            f += 1
            start = i + 1
        i += 1
    return ""

func __vm_dbg_atoi(s: str) -> int:
    n := __nat_blen(s)
    p := __nat_bp(s)
    i := 0
    neg := false
    if n > 0 and __load8(p) == 45:
        neg = true
        i = 1
    v := 0
    while i < n:
        c := __load8(p + i)
        if c < 48 or c > 57:
            break
        v = v * 10 + c - 48
        i += 1
    if neg:
        return 0 - v
    return v

func __vm_dbg_send(s: str):
    __nat_write_fd(__load64(__vm_dbg() + 96), s + "\n")

# Ligne de commande suivante (bloquant) ; fin du flux (frontal disparu) : arrêt du programme.
func __vm_dbg_read() -> str:
    dbg := __vm_dbg()
    fd := __load64(dbg + 88)
    sb := __rt_sb_new()
    b := __alloc_raw(8)
    while true:
        k := __syscall(0, fd, b, 1)
        if k == -4 or k == -11:
            continue
        if k <= 0:
            __vm_dbg_finish("stopped", "")
        c := __load8(b)
        if c == 10:
            return __rt_sb_str(sb)
        __rt_sb_byte(sb, c)
    return ""

# Fin de la session : événement X, puis sortie (code 1 après une exception).
func __vm_dbg_finish(kind: str, msg: str):
    __flush()
    __vm_dbg_send("X\t" + kind + "\t" + __vm_dbg_esc(msg))
    __fd_restore_all()
    __flush()
    if kind == "exception":
        __exit(1)
    __exit(0)

# Commande vide d'attente immédiate ? (poll, délai nul)
func __vm_dbg_ready() -> bool:
    if __windows():
        # tube nommé : poll ne sait sonder que les sockets sous Windows (un tube y paraît toujours prêt)
        av := __alloc_raw(8)
        __store64(av, 0)
        if __rt_w32(__wincall("PeekNamedPipe", __rt_win_handle(__load64(__vm_dbg() + 88)), 0, 0, 0, av, 0)) == 0:
            return true # alexc parti : la lecture verra la fin du flux
        return __load32(av) > 0
    pf := __alloc_raw(16)
    __store32(pf, __load64(__vm_dbg() + 88))
    __store16(pf + 4, 1)
    __store16(pf + 6, 0)
    r := __syscall(7, pf, 1, 0)
    return r > 0 and (__load16(pf + 6) & 25) != 0

# Windows : « \ » -> « / » et minuscules ASCII (le système de fichiers ignore la casse), pour comparer les chemins.
func __vm_dbg_win_key(p: str) -> str:
    n := __nat_blen(p)
    b := __alloc_raw(n + 8)
    i := 0
    while i < n:
        c := __load8(__nat_bp(p) + i)
        if c == 92:
            c = 47
        elif c >= 65 and c <= 90:
            c = c + 32
        __store8(b + i, c)
        i += 1
    return __nat_make(b, n)

# Chemin absolu normalisé (clé de comparaison des fichiers : entrée, bibliothèque, points d'arrêt) ; sous Windows
# « /d:/dossier/prog.al » pour D:\Dossier\prog.al, d:/... et d:\... (UNC : « /serveur/partage/... »).
func __vm_dbg_norm(p: str) -> str:
    if __nat_blen(p) == 0:
        return p
    a := p
    if __windows():
        a = __vm_dbg_win_key(p)
    absolute := __load8(__nat_bp(a)) == 47
    if __windows() and __nat_blen(a) >= 2 and __load8(__nat_bp(a) + 1) == 58:
        absolute = true
    if not absolute:
        buf := __alloc_raw(4096)
        cwd := "/"
        if __syscall(79, buf, 4096) >= 0:
            cwd = __nat_from_c(buf)
        if __windows():
            cwd = __vm_dbg_win_key(cwd)
        a = cwd + "/" + a
    n := __nat_blen(a)
    q := __nat_bp(a)
    parts := __rt_list_new(0)
    i := 0
    start := 0
    while i <= n:
        if i == n or __load8(q + i) == 47:
            seg := __nat_sub(a, start, i - start)
            if __nat_blen(seg) == 0 or seg == ".":
                start = start
            elif seg == "..":
                if __load64(parts) > 0:
                    __store64(parts, __load64(parts) - 1)
            else:
                __rt_list_push(parts, __str_addr(seg))
            start = i + 1
        i += 1
    sb := __rt_sb_new()
    k := 0
    while k < __load64(parts):
        __rt_sb_add(sb, "/")
        __rt_sb_add(sb, __as_str(__rt_vec_at(parts, k)))
        k += 1
    if __load64(parts) == 0:
        return "/"
    return __rt_sb_str(sb)

func __vm_dbg_prefix(s: str, pre: str) -> bool:
    n := __nat_blen(pre)
    if __nat_blen(s) < n:
        return false
    i := 0
    while i < n:
        if __load8(__nat_bp(s) + i) != __load8(__nat_bp(pre) + i):
            return false
        i += 1
    return true

# Drapeaux du fichier source d'une fonction (calculés une fois).
func __vm_dbg_info(d: int) -> int:
    fl := __load64(d + 232)
    if fl != 0:
        return fl
    dbg := __vm_dbg()
    fl = 1
    raw := __as_str(__load64(d + 40))
    nf := ""
    if __load64(d + 240) != 0:
        fl = fl | 2
        nf = __vm_dbg_norm(raw)
        lib := __load8(__nat_bp(raw)) == 60 or __vm_dbg_prefix(raw, "stdlib/")
        if __load64(dbg + 48) != 0 and __vm_dbg_prefix(nf, __as_str(__load64(dbg + 48))):
            lib = true
        if __load64(dbg + 48) == 0:
            lib = false
        if lib:
            fl = fl | 4
        if __load64(dbg + 40) != 0 and nf == __as_str(__load64(dbg + 40)):
            fl = fl | 8
    __store64(d + 224, __str_addr(nf))
    __store64(d + 232, fl)
    return fl

func __vm_dbg_line(fr: int) -> int:
    d := __load64(fr + 8)
    if __load64(d + 8) == 0:
        return 0
    idx := (__load64(fr + 16) - __load64(d)) >> 5
    if idx >= __load64(d + 8):
        idx = __load64(d + 8) - 1
    if idx < 0:
        idx = 0
    return __load64(__load64(d + 48) + 8 * idx)

func __vm_dbg_file(d: int) -> str:
    if __load64(d + 240) == 0:
        return ""
    return __as_str(__load64(d + 40))

# Avant chaque instruction (état [208] = 2).
func __vm_dbg_hook(fr: int, ip: int):
    dbg := __vm_dbg()
    c := __load64(dbg + 128) + 1
    if c >= 2048:
        c = 0
        __store64(dbg + 128, 0)
        __vm_dbg_poll()
    __store64(dbg + 128, c)
    d := __load64(fr + 8)
    idx := (ip - __load64(d)) >> 5
    line := __load64(__load64(d + 48) + 8 * idx)
    depth := __load64(fr + 64)
    # ligne courante de chaque niveau d'appel : revenir d'un appel sur la même ligne ne compte pas
    n := __load64(dbg + 80)
    if n > depth + 1:
        n = depth + 1
    if n < depth + 1:
        if depth + 1 > __load64(dbg + 72):
            cap := 2 * (depth + 1) + 16
            na := __alloc_raw(16 * cap)
            __copy(na, __load64(dbg + 64), 16 * n)
            __store64(dbg + 64, na)
            __store64(dbg + 72, cap)
        while n < depth + 1:
            __store64(__load64(dbg + 64) + 16 * n, -1)
            __store64(__load64(dbg + 64) + 16 * n + 8, -1)
            n += 1
    __store64(dbg + 80, n)
    e := __load64(dbg + 64) + 16 * depth
    new_line := __load64(e) != d or __load64(e + 8) != line
    __store64(e, d)
    __store64(e + 8, line)
    fl := __vm_dbg_info(d)
    user := line > 0 and (fl & 2) != 0 and (fl & 4) == 0
    stop := false
    reason := ""
    if __load64(dbg + 8) != 0 and user and (__load64(dbg + 24) != 0 or __load64(dbg + 40) == 0 or (fl & 8) != 0):
        stop = true
        if __load64(dbg + 24) != 0:
            reason = "pause"
        else:
            reason = "entry"
    mode := __load64(dbg)
    if new_line and user:
        if mode == 1:
            stop = true
        elif mode == 2 and depth <= __load64(dbg + 16):
            stop = true
        elif mode == 3 and depth < __load64(dbg + 16):
            stop = true
    if stop and __nat_blen(reason) == 0:
        reason = "step"
    if new_line and line > 0 and (fl & 2) != 0:
        bps := __load64(dbg + 56)
        k := __rt_dict_index(bps, __load64(d + 224), 1)
        if k >= 0:
            lines := __load64(__load64(bps + 32) + 8 * k)
            j := __rt_dict_index(lines, line, 0)
            if j >= 0:
                id := __load64(__load64(lines + 32) + 8 * j) - 1
                hit := true
                if id > 0:
                    hit = __vm_dbg_ask(fr, id, __vm_dbg_file(d), line)
                if hit:
                    stop = true
                    reason = "breakpoint"
    if not stop:
        return
    __store64(dbg + 24, 1)
    __vm_dbg_pause(fr, reason, "", "")

# Point d'arrêt à options (condition, compteur, journal) : décision du frontal, qui peut interroger l'état.
func __vm_dbg_ask(fr: int, id: int, file: str, line: int) -> bool:
    dbg := __vm_dbg()
    __store64(dbg + 120, fr)
    __vm_dbg_send("H\t" + __int_to_str(id) + "\t" + __vm_dbg_esc(file) + "\t" + __int_to_str(line))
    r := false
    while true:
        cmd := __vm_dbg_read()
        if cmd == "y":
            r = true
            break
        if cmd == "n":
            break
        __vm_dbg_command(cmd, true)
    __vm_dbg_clear()
    return r

func __vm_dbg_clear():
    dbg := __vm_dbg()
    __store64(dbg + 112, __rt_list_new(0))
    __store64(dbg + 176, __rt_list_new(0))

func __vm_dbg_pause(fr: int, reason: str, et: str, em: str):
    dbg := __vm_dbg()
    __store64(dbg + 120, fr)
    __store64(dbg + 184, __load64(fr + 64))
    __vm_dbg_clear()
    d := __load64(fr + 8)
    ev := "P\t" + reason + "\t" + __vm_dbg_esc(__vm_dbg_file(d)) + "\t" + __int_to_str(__vm_dbg_line(fr))
    if reason == "exception":
        ev = ev + "\t" + __vm_dbg_esc(et) + "\t" + __vm_dbg_esc(em)
    __flush()
    __vm_dbg_send(ev)
    while true:
        cmd := __vm_dbg_read()
        if __vm_dbg_command(cmd, true):
            break
    # reprise : profondeur d'origine du pas à pas, pause demandée effacée
    __store64(dbg + 16, __load64(dbg + 184))
    __store64(dbg + 8, 0)
    __vm_dbg_clear()

# Commandes reçues pendant l'exécution (scrutation non bloquante).
func __vm_dbg_poll():
    while __vm_dbg_ready():
        __vm_dbg_command(__vm_dbg_read(), false)

func __vm_dbg_bp_set(file: str, line: int, val: int):
    bps := __load64(__vm_dbg() + 56)
    nf := __vm_dbg_norm(file)
    k := __rt_dict_index(bps, __str_addr(nf), 1)
    lines := 0
    if k >= 0:
        lines = __load64(__load64(bps + 32) + 8 * k)
    else:
        lines = __rt_dict_new(8)
        __rt_dict_set(bps, __str_addr(nf), lines, 1)
    if val == 0:
        if __rt_dict_index(lines, line, 0) >= 0:
            __rt_dict_remove(lines, line, 0)
        return
    __rt_dict_set(lines, line, val, 0)

# Traite une commande ; vrai si elle reprend l'exécution (paused : programme arrêté, requêtes permises).
func __vm_dbg_command(cmd: str, paused: bool) -> bool:
    dbg := __vm_dbg()
    if __nat_blen(cmd) == 0:
        return false
    op := __vm_dbg_field(cmd, 0)
    if op == "c":
        __store64(dbg, 0)
        return paused
    if op == "s":
        m := __vm_dbg_field(cmd, 1)
        if m == "into":
            __store64(dbg, 1)
        elif m == "out":
            __store64(dbg, 3)
        else:
            __store64(dbg, 2)
        return paused
    if op == "p":
        __store64(dbg + 8, 1)
        return false
    if op == "q":
        __vm_dbg_finish("stopped", "")
    if op == "ba":
        __vm_dbg_bp_set(__vm_dbg_field(cmd, 1), __vm_dbg_atoi(__vm_dbg_field(cmd, 2)), 1)
        return false
    if op == "bo":
        __vm_dbg_bp_set(__vm_dbg_field(cmd, 2), __vm_dbg_atoi(__vm_dbg_field(cmd, 3)), 1 + __vm_dbg_atoi(__vm_dbg_field(cmd, 1)))
        return false
    if op == "br":
        __vm_dbg_bp_set(__vm_dbg_field(cmd, 1), __vm_dbg_atoi(__vm_dbg_field(cmd, 2)), 0)
        return false
    if op == "bc":
        bps := __load64(dbg + 56)
        nf := __vm_dbg_norm(__vm_dbg_field(cmd, 1))
        if __rt_dict_index(bps, __str_addr(nf), 1) >= 0:
            __rt_dict_set(bps, __str_addr(nf), __rt_dict_new(8), 1)
        return false
    if op == "be":
        __store64(dbg + 32, __vm_dbg_atoi(__vm_dbg_field(cmd, 1)))
        return false
    if op == "i":
        __rt_list_push(__load64(dbg + 136), __str_addr(__vm_dbg_field(cmd, 1)))
        return false
    if not paused:
        return false
    ex := 0
    r := ""
    try:
        r = __vm_dbg_query(op, cmd)
    catch e:
        ex = __addr(e)
    if ex != 0:
        __vm_dbg_send("!\t" + __vm_dbg_esc(__as_str(__load64(ex + 8))))
    else:
        __vm_dbg_send("R\t" + __vm_dbg_esc(r))
    return false

func __vm_dbg_fail(m: str):
    __rt_throw(__rt_exc_new("Debug", m))

# ---- Inspection ----------------------------------------------------------------------------------------------

func __vm_dbg_unwrap(v: int) -> int:
    if v != 0 and __load64(v) == 14:
        return __load64(v + 8)
    return v

func __vm_dbg_bare(n: str) -> str:
    q := __vm_rfind_colons(n)
    if q >= 0:
        return __vm_after(n, q + 2)
    return n

func __vm_dbg_fn_name(n0: str) -> str:
    n := __vm_dbg_bare(n0)
    at := __vm_findb(n, 64)
    if at >= 0:
        return __nat_sub(n, 0, at)
    return n

func __vm_dbg_type(v0: int) -> str:
    v := __vm_dbg_unwrap(v0)
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
        return "func"
    if k == 11:
        return "func (native)"
    if k == 12:
        return __vm_dbg_bare(__as_str(__load64(v + 8)))
    if k == 13:
        return __as_str(__load64(__load64(v + 8)))
    if k == 14:
        return "cell"
    if k == 15:
        return "future"
    return "?"

func __vm_dbg_expandable(v0: int) -> bool:
    v := __vm_dbg_unwrap(v0)
    k := __dyn_kind(v)
    if k == 7:
        return __dyn_list_len(v) > 0
    if k == 8:
        return __load64(v + 8) > 0
    if k == 9:
        return __load64(__dyn_dv(v)) > 0
    if k == 12:
        return __load64(__load64(v + 16)) > 0
    if k == 13 or k == 15:
        return true
    return false

func __vm_dbg_quoted(s: str) -> str:
    n := __nat_blen(s)
    p := __nat_bp(s)
    sb := __rt_sb_new()
    __rt_sb_byte(sb, 34)
    i := 0
    while i < n:
        c := __load8(p + i)
        if c == 34:
            __rt_sb_add(sb, "\\\"")
        elif c == 92:
            __rt_sb_add(sb, "\\\\")
        elif c == 10:
            __rt_sb_add(sb, "\\n")
        elif c == 9:
            __rt_sb_add(sb, "\\t")
        else:
            __rt_sb_byte(sb, c)
        i += 1
    __rt_sb_byte(sb, 34)
    return __rt_sb_str(sb)

func __vm_dbg_sblen(sb: int) -> int:
    return __load64(sb)

# Aperçu (DebugInspector::preview).
func __vm_dbg_preview(v0: int, depth: int) -> str:
    v := __vm_dbg_unwrap(v0)
    k := __dyn_kind(v)
    if k == 6:
        s := __dyn_sv(v)
        if __nat_blen(s) > 200:
            s = __nat_sub(s, 0, 200) + "…"
        return __vm_dbg_quoted(s)
    if k == 7 or k == 8:
        n := 0
        if k == 7:
            n = __dyn_list_len(v)
        else:
            n = __load64(v + 8)
        if depth > 1:
            if k == 7:
                return "[…] (" + __int_to_str(n) + ")"
            return "(…) (" + __int_to_str(n) + ")"
        sb := __rt_sb_new()
        if k == 7:
            __rt_sb_add(sb, "[")
        else:
            __rt_sb_add(sb, "(")
        i := 0
        while i < n:
            if i > 0:
                __rt_sb_add(sb, ", ")
            if __vm_dbg_sblen(sb) > 120:
                __rt_sb_add(sb, "… +" + __int_to_str(n - i))
                break
            x := 0
            if k == 7:
                x = __dyn_list_at(v, i)
            else:
                x = __load64(v + 16 + 8 * i)
            __rt_sb_add(sb, __vm_dbg_preview(x, depth + 1))
            i += 1
        if k == 7:
            __rt_sb_add(sb, "]")
        else:
            __rt_sb_add(sb, ")")
        return __rt_sb_str(sb)
    if k == 9:
        d := __dyn_dv(v)
        cnt := __load64(d)
        if depth > 1:
            return "{…} (" + __int_to_str(cnt) + ")"
        sb := __rt_sb_new()
        __rt_sb_add(sb, "{")
        used := __load64(d + 8)
        e := 0
        i := 0
        while e < used:
            if __load64(__load64(d + 40) + 8 * e) >= 0:
                if i > 0:
                    __rt_sb_add(sb, ", ")
                if __vm_dbg_sblen(sb) > 120:
                    __rt_sb_add(sb, "… +" + __int_to_str(cnt - i))
                    break
                __rt_sb_add(sb, __vm_dbg_preview(__load64(__load64(d + 24) + 8 * e), depth + 1))
                __rt_sb_add(sb, ": ")
                __rt_sb_add(sb, __vm_dbg_preview(__load64(__load64(d + 32) + 8 * e), depth + 1))
                i += 1
            e += 1
        __rt_sb_add(sb, "}")
        return __rt_sb_str(sb)
    if k == 12:
        tname := __vm_dbg_bare(__as_str(__load64(v + 8)))
        if depth > 0:
            return tname + "{…}"
        f := __load64(v + 16)
        names := __rt_dict_list(f, 24)
        __vm_sort_strs(names)
        sb := __rt_sb_new()
        __rt_sb_add(sb, tname + "{")
        i := 0
        while i < __load64(names):
            if i > 0:
                __rt_sb_add(sb, ", ")
            if __vm_dbg_sblen(sb) > 120:
                __rt_sb_add(sb, "…")
                break
            nm := __rt_vec_at(names, i)
            __rt_sb_add(sb, __as_str(nm) + ": ")
            __rt_sb_add(sb, __vm_dbg_preview(__load64(__load64(f + 32) + 8 * __rt_dict_index(f, nm, 1)), depth + 1))
            i += 1
        __rt_sb_add(sb, "}")
        return __rt_sb_str(sb)
    if k == 13:
        x := __load64(v + 8)
        return __as_str(__load64(x)) + ": " + __as_str(__load64(x + 8))
    if k == 10:
        return "func " + __vm_dbg_fn_name(__as_str(__load64(v + 16)))
    s := __dyn_display(v)
    if k == 4:
        return "'" + s + "'"
    return s

# Chaîne JSON (UTF-8 valide garanti : octet invalide -> U+FFFD), comme jsonEscape.
func __vm_dbg_json(sb: int, s: str):
    n := __nat_blen(s)
    p := __nat_bp(s)
    __rt_sb_byte(sb, 34)
    i := 0
    while i < n:
        c := __load8(p + i)
        if c >= 128:
            ln := 0
            if (c & 224) == 192:
                ln = 2
            elif (c & 240) == 224:
                ln = 3
            elif (c & 248) == 240:
                ln = 4
            ok := ln != 0 and i + ln <= n and c >= 194
            k := 1
            while ok and k < ln:
                if (__load8(p + i + k) & 192) != 128:
                    ok = false
                k += 1
            if ok:
                k = 0
                while k < ln:
                    __rt_sb_byte(sb, __load8(p + i + k))
                    k += 1
                i += ln
            else:
                __rt_sb_add(sb, "\xEF\xBF\xBD")
                i += 1
            continue
        if c == 34:
            __rt_sb_add(sb, "\\\"")
        elif c == 92:
            __rt_sb_add(sb, "\\\\")
        elif c == 10:
            __rt_sb_add(sb, "\\n")
        elif c == 13:
            __rt_sb_add(sb, "\\r")
        elif c == 9:
            __rt_sb_add(sb, "\\t")
        elif c == 8:
            __rt_sb_add(sb, "\\b")
        elif c == 12:
            __rt_sb_add(sb, "\\f")
        elif c < 32:
            hx := "0123456789abcdef"
            __rt_sb_add(sb, "\\u00")
            __rt_sb_byte(sb, __load8(__nat_bp(hx) + (c >> 4)))
            __rt_sb_byte(sb, __load8(__nat_bp(hx) + (c & 15)))
        else:
            __rt_sb_byte(sb, c)
        i += 1
    __rt_sb_byte(sb, 34)

func __vm_dbg_ref(v: int) -> int:
    if not __vm_dbg_expandable(v):
        return 0
    refs := __load64(__vm_dbg() + 176)
    __rt_list_push(refs, __vm_dbg_unwrap(v))
    return __load64(refs)

# Variable (DebugInspector::variableJson) : {"name", "type", "value", "ref"?}.
func __vm_dbg_var(sb: int, name: str, v: int):
    __rt_sb_add(sb, "{\"name\":")
    __vm_dbg_json(sb, name)
    __rt_sb_add(sb, ",\"type\":")
    __vm_dbg_json(sb, __vm_dbg_type(v))
    __rt_sb_add(sb, ",\"value\":")
    __vm_dbg_json(sb, __vm_dbg_preview(v, 0))
    r := __vm_dbg_ref(v)
    if r != 0:
        __rt_sb_add(sb, ",\"ref\":" + __int_to_str(r))
    __rt_sb_add(sb, "}")

func __vm_dbg_row(sb: int, name: str, ty: str, value: str):
    __rt_sb_add(sb, "{\"name\":")
    __vm_dbg_json(sb, name)
    __rt_sb_add(sb, ",\"type\":")
    __vm_dbg_json(sb, ty)
    __rt_sb_add(sb, ",\"value\":")
    __vm_dbg_json(sb, value)
    __rt_sb_add(sb, "}")

# Cadres du programme principal vers le cadre arrêté (liste native de cadres).
func __vm_dbg_frames() -> int:
    l := __rt_list_new(0)
    f := __load64(__vm_dbg() + 120)
    while f != 0:
        __rt_list_push(l, f)
        f = __load64(f)
    n := __load64(l)
    out := __rt_list_new(0)
    i := n - 1
    while i >= 0:
        __rt_list_push(out, __rt_vec_at(l, i))
        i -= 1
    return out

func __vm_dbg_visible(fr: int) -> bool:
    d := __load64(fr + 8)
    return __load64(d + 240) != 0 or __vm_dbg_line(fr) != 0

# Variables nommées d'un cadre (DebugInspector::frameVariables) : liste native [nom, valeur, nom, valeur...].
func __vm_dbg_frame_vars(fr: int) -> int:
    d := __load64(fr + 8)
    nl := __load64(d + 16)
    loc := fr + 80
    out := __rt_list_new(0)
    names := __load64(d + 168)
    if names == 0 or __load64(names) == 0:
        i := 0
        while i < nl:
            __rt_list_push(out, __str_addr("local[" + __int_to_str(i) + "]"))
            __rt_list_push(out, __load64(loc + 8 * i))
            i += 1
        return out
    best := __rt_dict_new(16)
    order := __rt_list_new(0)
    nn := __load64(names)
    i := 0
    while i < nn and i < nl:
        nm := __load64(names + 8 + 8 * i)
        s := __as_str(nm)
        if __nat_blen(s) > 0 and __load8(__nat_bp(s)) != 36:
            e := __rt_dict_index(best, nm, 1)
            if e < 0:
                __rt_dict_set(best, nm, i, 1)
                __rt_list_push(order, nm)
            else:
                cur := __load64(__load64(best + 32) + 8 * e)
                if __vm_dbg_unwrap(__load64(loc + 8 * i)) != 0 or __vm_dbg_unwrap(__load64(loc + 8 * cur)) == 0:
                    __rt_dict_set(best, nm, i, 1)
        i += 1
    k := 0
    while k < __load64(order):
        nm := __rt_vec_at(order, k)
        __rt_list_push(out, nm)
        __rt_list_push(out, __load64(loc + 8 * __load64(__load64(best + 32) + 8 * __rt_dict_index(best, nm, 1))))
        k += 1
    return out

func __vm_dbg_tag(v: int) -> str:
    k := __dyn_kind(v)
    if k == 0:
        return "Null"
    if k == 1:
        return "Int"
    if k == 2:
        return "Float"
    if k == 3:
        return "Bool"
    if k == 4:
        return "Char"
    if k == 5:
        return "Byte"
    return "Obj"

func __vm_dbg_q_frames(proto1: bool) -> str:
    frames := __vm_dbg_frames()
    sb := __rt_sb_new()
    __rt_sb_add(sb, "[")
    first := true
    i := 0
    while i < __load64(frames):
        fr := __rt_vec_at(frames, i)
        i += 1
        if not proto1 and not __vm_dbg_visible(fr):
            continue
        d := __load64(fr + 8)
        if not first:
            __rt_sb_add(sb, ",")
        first = false
        __rt_sb_add(sb, "{\"function\":")
        __vm_dbg_json(sb, __as_str(__load64(d + 32)))
        __rt_sb_add(sb, ",\"file\":")
        __vm_dbg_json(sb, __vm_dbg_file(d))
        __rt_sb_add(sb, ",\"line\":" + __int_to_str(__vm_dbg_line(fr)) + ",\"locals\":[")
        if proto1:
            k := 0
            while k < __load64(d + 16):
                v := __load64(fr + 80 + 8 * k)
                if k > 0:
                    __rt_sb_add(sb, ",")
                __vm_dbg_row(sb, "local[" + __int_to_str(k) + "]", __vm_dbg_tag(v), __dyn_display(v))
                k += 1
        else:
            vars := __vm_dbg_frame_vars(fr)
            k := 0
            while k < __load64(vars):
                if k > 0:
                    __rt_sb_add(sb, ",")
                __vm_dbg_var(sb, __as_str(__rt_vec_at(vars, k)), __rt_vec_at(vars, k + 1))
                k += 2
        __rt_sb_add(sb, "]}")
    __rt_sb_add(sb, "]")
    return __rt_sb_str(sb)

func __vm_dbg_all_funcs(v: int) -> bool:
    f := __load64(v + 16)
    if __load64(f) == 0:
        return false
    used := __load64(f + 8)
    e := 0
    while e < used:
        if __load64(__load64(f + 40) + 8 * e) >= 0:
            y := __vm_dbg_unwrap(__load64(__load64(f + 32) + 8 * e))
            yk := __dyn_kind(y)
            if yk != 10 and yk != 11:
                return false
        e += 1
    return true

func __vm_dbg_q_globals() -> str:
    gd := __load64(__vm_st() + 40)
    names := __rt_list_new(0)
    used := __load64(gd + 8)
    e := 0
    while e < used:
        if __load64(__load64(gd + 40) + 8 * e) >= 0:
            nm := __load64(__load64(gd + 24) + 8 * e)
            s := __as_str(nm)
            v := __load64(__load64(__load64(gd + 32) + 8 * e))
            ok := v != 1 and __nat_blen(s) > 0 and __load8(__nat_bp(s)) != 95 and __load8(__nat_bp(s)) != 36 and __vm_rfind_colons(s) < 0
            if ok:
                x := __vm_dbg_unwrap(v)
                xk := __dyn_kind(x)
                if xk == 10 or xk == 11:
                    ok = false
                elif xk == 12 and __vm_dbg_all_funcs(x):
                    ok = false
            if ok:
                __rt_list_push(names, nm)
        e += 1
    __vm_sort_strs(names)
    sb := __rt_sb_new()
    __rt_sb_add(sb, "[")
    i := 0
    while i < __load64(names):
        nm := __rt_vec_at(names, i)
        if i > 0:
            __rt_sb_add(sb, ",")
        __vm_dbg_var(sb, __as_str(nm), __load64(__vm_gslot(__as_str(nm))))
        i += 1
    __rt_sb_add(sb, "]")
    return __rt_sb_str(sb)

func __vm_dbg_q_children(ref: int) -> str:
    refs := __load64(__vm_dbg() + 176)
    if ref < 1 or ref > __load64(refs):
        __vm_dbg_fail("référence de variable invalide")
    v := __rt_vec_at(refs, ref - 1)
    k := __dyn_kind(v)
    sb := __rt_sb_new()
    __rt_sb_add(sb, "[")
    if k == 7 or k == 8:
        n := 0
        if k == 7:
            n = __dyn_list_len(v)
        else:
            n = __load64(v + 8)
        i := 0
        while i < n and i < 2000:
            x := 0
            if k == 7:
                x = __dyn_list_at(v, i)
            else:
                x = __load64(v + 16 + 8 * i)
            if i > 0:
                __rt_sb_add(sb, ",")
            __vm_dbg_var(sb, "[" + __int_to_str(i) + "]", x)
            i += 1
    elif k == 9:
        d := __dyn_dv(v)
        used := __load64(d + 8)
        e := 0
        n := 0
        while e < used:
            if __load64(__load64(d + 40) + 8 * e) >= 0:
                n += 1
                if n > 2000:
                    break
                if n > 1:
                    __rt_sb_add(sb, ",")
                __vm_dbg_var(sb, __vm_dbg_preview(__load64(__load64(d + 24) + 8 * e), 1), __load64(__load64(d + 32) + 8 * e))
            e += 1
    elif k == 12:
        f := __load64(v + 16)
        names := __rt_dict_list(f, 24)
        __vm_sort_strs(names)
        i := 0
        while i < __load64(names):
            nm := __rt_vec_at(names, i)
            if i > 0:
                __rt_sb_add(sb, ",")
            __vm_dbg_var(sb, __as_str(nm), __load64(__load64(f + 32) + 8 * __rt_dict_index(f, nm, 1)))
            i += 1
    elif k == 13:
        x := __load64(v + 8)
        __vm_dbg_row(sb, "type", "str", __vm_dbg_quoted(__as_str(__load64(x))))
        __rt_sb_add(sb, ",")
        __vm_dbg_row(sb, "message", "str", __vm_dbg_quoted(__as_str(__load64(x + 8))))
        t := __load64(x + 16)
        if t != 0 and __load64(t) < -1:
            i := 0
            while i < -1 - __load64(t):
                en := t + 8 + 24 * i
                __rt_sb_add(sb, ",")
                __vm_dbg_row(sb, "trace[" + __int_to_str(i) + "]", "frame", __as_str(__load64(en + 16)) + " (" + __as_str(__load64(en)) + ":" + __int_to_str(__load64(en + 8)) + ")")
                i += 1
    __rt_sb_add(sb, "]")
    return __rt_sb_str(sb)

# Valeur pour l'évaluateur du frontal : ["N"] ["B",b] ["I",n] ["F",bits] ["S",texte] ["V",h,type].
func __vm_dbg_ev(v0: int) -> str:
    v := __vm_dbg_unwrap(v0)
    k := __dyn_kind(v)
    sb := __rt_sb_new()
    if k == 0:
        return "[\"N\"]"
    if k == 3:
        if __load64(v + 8) != 0:
            return "[\"B\",true]"
        return "[\"B\",false]"
    if k == 1 or k == 5:
        return "[\"I\"," + __int_to_str(__load64(v + 8)) + "]"
    if k == 2:
        return "[\"F\"," + __int_to_str(__load64(v + 8)) + "]"
    if k == 6 or k == 4:
        __rt_sb_add(sb, "[\"S\",")
        if k == 6:
            __vm_dbg_json(sb, __dyn_sv(v))
        else:
            __vm_dbg_json(sb, __rt_char_str(__load64(v + 8)))
        __rt_sb_add(sb, "]")
        return __rt_sb_str(sb)
    vals := __load64(__vm_dbg() + 112)
    __rt_list_push(vals, v)
    __rt_sb_add(sb, "[\"V\"," + __int_to_str(__load64(vals)) + ",")
    __vm_dbg_json(sb, __vm_dbg_type(v))
    __rt_sb_add(sb, "]")
    return __rt_sb_str(sb)

func __vm_dbg_val(h: int) -> int:
    vals := __load64(__vm_dbg() + 112)
    if h < 1 or h > __load64(vals):
        __vm_dbg_fail("valeur inconnue")
    return __rt_vec_at(vals, h - 1)

# Égalité d'une clé de dictionnaire avec une valeur encodée de l'évaluateur (EV::equal).
func __vm_dbg_key_eq(key0: int, enc: str) -> bool:
    key := __vm_dbg_unwrap(key0)
    k := __dyn_kind(key)
    t := __vm_dbg_field(enc, 0)
    if t == "I" or t == "F":
        if k != 1 and k != 2 and k != 5:
            return false
        x := 0.0
        if t == "I":
            x = __i2f(__vm_dbg_atoi(__vm_dbg_field(enc, 1)))
        else:
            x = __bits2f(__vm_dbg_atoi(__vm_dbg_field(enc, 1)))
        y := 0.0
        if k == 2:
            y = __dyn_fv(key)
        else:
            y = __i2f(__load64(key + 8))
        return x == y
    if t == "N":
        return k == 0
    if t == "B":
        return k == 3 and (__load64(key + 8) != 0) == (__vm_dbg_field(enc, 1) == "1")
    if t == "S":
        s := ""
        if k == 6:
            s = __dyn_sv(key)
        elif k == 4:
            s = __rt_char_str(__load64(key + 8))
        else:
            return false
        return s == __vm_dbg_field(enc, 1)
    if k == 0 or k == 1 or k == 2 or k == 3 or k == 4 or k == 5 or k == 6:
        return false
    return __dyn_eq(key, __vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(enc, 1))))

# Cadre visible d'indice idx (-1 ou hors limites : le plus récent), 0 s'il n'y en a pas.
func __vm_dbg_eval_frame(idx: int) -> int:
    frames := __vm_dbg_frames()
    vis := __rt_list_new(0)
    i := 0
    while i < __load64(frames):
        if __vm_dbg_visible(__rt_vec_at(frames, i)):
            __rt_list_push(vis, __rt_vec_at(frames, i))
        i += 1
    if __load64(vis) == 0:
        return 0
    if idx < 0 or idx >= __load64(vis):
        return __rt_vec_at(vis, __load64(vis) - 1)
    return __rt_vec_at(vis, idx)

func __vm_dbg_q_name(fidx: int, name: str) -> str:
    fr := __vm_dbg_eval_frame(fidx)
    if fr != 0:
        vars := __vm_dbg_frame_vars(fr)
        k := 0
        while k < __load64(vars):
            if __as_str(__rt_vec_at(vars, k)) == name:
                return __vm_dbg_ev(__rt_vec_at(vars, k + 1))
            k += 2
    gd := __load64(__vm_st() + 40)
    e := __rt_dict_index(gd, __str_addr(name), 1)
    if e >= 0:
        v := __load64(__load64(__load64(gd + 32) + 8 * e))
        if v != 1:
            return __vm_dbg_ev(v)
    used := __load64(gd + 8)
    e = 0
    while e < used:
        if __load64(__load64(gd + 40) + 8 * e) >= 0:
            v := __load64(__load64(__load64(gd + 32) + 8 * e))
            if v != 1 and __vm_dbg_bare(__as_str(__load64(__load64(gd + 24) + 8 * e))) == name:
                return __vm_dbg_ev(v)
        e += 1
    __vm_dbg_fail("'" + name + "' n'est pas défini ici")
    return ""

func __vm_dbg_query(op: str, cmd: str) -> str:
    if op == "F":
        return __vm_dbg_q_frames(false)
    if op == "F1":
        return __vm_dbg_q_frames(true)
    if op == "G":
        return __vm_dbg_q_globals()
    if op == "K":
        return __vm_dbg_q_children(__vm_dbg_atoi(__vm_dbg_field(cmd, 1)))
    if op == "N":
        return __vm_dbg_q_name(__vm_dbg_atoi(__vm_dbg_field(cmd, 1)), __vm_dbg_field(cmd, 2))
    if op == "Q" or op == "R":
        v := __vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(cmd, 1)))
        sb := __rt_sb_new()
        __rt_sb_add(sb, "[")
        __vm_dbg_json(sb, __vm_dbg_preview(v, 0))
        __rt_sb_add(sb, ",")
        __vm_dbg_json(sb, __vm_dbg_type(v))
        r := 0
        if op == "R":
            r = __vm_dbg_ref(v)
        __rt_sb_add(sb, "," + __int_to_str(r) + "]")
        return __rt_sb_str(sb)
    if op == "D":
        sb := __rt_sb_new()
        __vm_dbg_json(sb, __dyn_display(__vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(cmd, 1)))))
        return __rt_sb_str(sb)
    if op == "L":
        v := __vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(cmd, 1)))
        k := __dyn_kind(v)
        if k == 7:
            return __int_to_str(__dyn_list_len(v))
        if k == 8:
            return __int_to_str(__load64(v + 8))
        if k == 9:
            return __int_to_str(__load64(__dyn_dv(v)))
        __vm_dbg_fail("len() : valeur sans longueur")
    if op == "E":
        if __dyn_eq(__vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(cmd, 1))), __vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(cmd, 2)))):
            return "1"
        return "0"
    if op == "M":
        v := __vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(cmd, 1)))
        m := __vm_dbg_field(cmd, 2)
        k := __dyn_kind(v)
        if k == 12:
            f := __load64(v + 16)
            e := __rt_dict_index(f, __str_addr(m), 1)
            if e >= 0:
                return __vm_dbg_ev(__load64(__load64(f + 32) + 8 * e))
            __vm_dbg_fail("l'objet " + __vm_dbg_bare(__as_str(__load64(v + 8))) + " n'a pas de champ '" + m + "'")
        if k == 13:
            x := __load64(v + 8)
            if m == "message":
                return __vm_dbg_ev(__dyn_str(__as_str(__load64(x + 8))))
            if m == "type":
                return __vm_dbg_ev(__dyn_str(__as_str(__load64(x))))
        __vm_dbg_fail("membre '" + m + "' inaccessible sur une valeur de type " + __vm_dbg_type(v))
    if op == "X":
        v := __vm_dbg_val(__vm_dbg_atoi(__vm_dbg_field(cmd, 1)))
        enc := __vm_dbg_field(cmd, 2)
        k := __dyn_kind(v)
        if k == 7 or k == 8:
            if __vm_dbg_field(enc, 0) != "I":
                __vm_dbg_fail("indice entier attendu")
            n := 0
            if k == 7:
                n = __dyn_list_len(v)
            else:
                n = __load64(v + 8)
            i := __vm_dbg_atoi(__vm_dbg_field(enc, 1))
            if i < 0:
                i = i + n
            if i < 0 or i >= n:
                __vm_dbg_fail("indice hors limites")
            if k == 7:
                return __vm_dbg_ev(__dyn_list_at(v, i))
            return __vm_dbg_ev(__load64(v + 16 + 8 * i))
        if k == 9:
            d := __dyn_dv(v)
            used := __load64(d + 8)
            e := 0
            while e < used:
                if __load64(__load64(d + 40) + 8 * e) >= 0 and __vm_dbg_key_eq(__load64(__load64(d + 24) + 8 * e), enc):
                    return __vm_dbg_ev(__load64(__load64(d + 32) + 8 * e))
                e += 1
            __vm_dbg_fail("clé absente")
        __vm_dbg_fail("valeur non indexable")
    __vm_dbg_fail("requête inconnue : " + op)
    return ""

# ---- Points d'entrée -----------------------------------------------------------------------------------------

# print (protocole 2 : événement de sortie ; protocole 1 : stderr, stdout restant réservé au protocole).
func __vm_dbg_print(v: int):
    s := __dyn_display(v)
    if __load64(__vm_dbg() + 104) == 2:
        __vm_dbg_send("O\t" + __vm_dbg_esc(s + "\n"))
    else:
        __flush()
        __write_err(s + "\n")

# input (protocole 2) : demande transmise au frontal, réponse par la commande « i ».
func __vm_dbg_input() -> int:
    dbg := __vm_dbg()
    if __load64(dbg + 104) != 2:
        return __dyn_input()
    __flush()
    __vm_dbg_send("I")
    q := __load64(dbg + 136)
    while __load64(q) == 0:
        __vm_dbg_command(__vm_dbg_read(), false)
    s := __rt_vec_at(q, 0)
    i := 1
    while i < __load64(q):
        __store64(__load64(q + 16) + 8 * (i - 1), __rt_vec_at(q, i))
        i += 1
    __store64(q, __load64(q) - 1)
    return __dyn_str(__as_str(s))

# Exception sur le point d'être propagée depuis le cadre f : arrêt si aucun gestionnaire ne la rattrape.
func __vm_dbg_exception(ex: int, f: int):
    dbg := __vm_dbg()
    if __load64(dbg + 32) == 0 or __load64(dbg + 144) == ex:
        return
    if __load64(__state() + 960) != 0 and __rt_cur() != 0:
        return
    c := f
    while c != 0:
        if __load64(c + 24) > 0:
            return
        c = __load64(c)
    __store64(dbg + 144, ex)
    __vm_dbg_pause(f, "exception", __as_str(__load64(ex)), __as_str(__load64(ex + 8)))

func __vm_dbg_start(cmd: str, evt: str, proto: int, entry: str, lib: str, exc: int):
    vs := __vm_st()
    dbg := __alloc(256)
    __store64(vs + 312, dbg)
    fr := __vm_open_chan(cmd)
    fw := __vm_open_chan(evt)
    if fr < 0 or fw < 0:
        __write_err("alexvm --debug : tubes de commande inaccessibles\n")
        __exit(2)
    __store64(dbg + 88, fr)
    __store64(dbg + 96, fw)
    __store64(dbg + 104, proto)
    __store64(dbg + 8, 1)
    __store64(dbg + 32, exc)
    if __nat_blen(entry) > 0:
        __store64(dbg + 40, __str_addr(__vm_dbg_norm(entry)))
    if __nat_blen(lib) > 0:
        __store64(dbg + 48, __str_addr(__vm_dbg_norm(lib)))
    __store64(dbg + 56, __rt_dict_new(8))
    __store64(dbg + 64, __alloc_raw(16 * 64))
    __store64(dbg + 72, 64)
    __store64(dbg + 136, __rt_list_new(0))
    __vm_dbg_clear()
    __store64(vs + 208, 2)

# ---- Module natif _native_reflect (stdlib/reflection) ------------------
# (les fonctions __nat__native_reflect__* sont dans runtime/alex/native/dyn_nat.al, communes au mode natif)

# Liste native de chaînes triée (ordre des octets, comme std::sort).
func __vm_sort_strs(l: int):
    n := __load64(l)
    d := __load64(l + 16)
    i := 1
    while i < n:
        v := __load64(d + 8 * i)
        j := i - 1
        while j >= 0 and __rt_str_cmp(__as_str(__load64(d + 8 * j)), __as_str(v)) > 0:
            __store64(d + 8 * (j + 1), __load64(d + 8 * j))
            j -= 1
        __store64(d + 8 * (j + 1), v)
        i += 1

func __vm_str_list(l: int) -> int:
    out := __dyn_list_new(0)
    i := 0
    while i < __load64(l):
        __dyn_list_push(out, __dyn_str(__as_str(__rt_vec_at(l, i))))
        i += 1
    return out

func __vm_has_str(l: int, s: str) -> bool:
    i := 0
    while i < __load64(l):
        if __as_str(__rt_vec_at(l, i)) == s:
            return true
        i += 1
    return false

func __vm_short(n: str) -> str:
    q := __vm_rfind_colons(n)
    if q < 0:
        return n
    return __vm_after(n, q + 2)

func __vm_instance(fn: str, v: int) -> int:
    if not __dyn_is(v, 12):
        __dyn_err("TypeError", "'" + fn + "' : l'objet doit être une instance (obtenu '" + __dyn_type_name(v) + "')")
    return v

func __vm_methods_of(t: str) -> int:
    out := __rt_list_new(0)
    meths := __load64(__dyn_ds() + 24)
    used := __load64(meths + 8)
    pre := __nat_blen(t)
    e := 0
    while e < used:
        if __load64(__load64(meths + 40) + 8 * e) >= 0:
            key := __as_str(__load64(__load64(meths + 24) + 8 * e))
            g := __load64(__load64(meths + 32) + 8 * e)
            if __nat_blen(key) > pre + 1 and __nat_sub(key, 0, pre) == t and __load8(__nat_bp(key) + pre) == 35 and __dyn_is(__load64(__globals_start() + 8 * g), 10):
                m := __vm_after(key, pre + 1)
                if __vm_findb(m, 35) < 0 and __vm_findb(m, 64) < 0:
                    __rt_list_push(out, __str_addr(m))
        e += 1
    __vm_sort_strs(out)
    return out

# ---- Module natif _native_ffi --------------------------------------------------
# La VM est un ELF dynamique : dlopen / dlsym / dlclose / dlerror sont liés par ld-linux au chargement
# (__elf_import), les fonctions C sont appelées selon la convention System V (__sysv_call). Les natives __vm_nat_*
# remplacent celles du mode dynamique (__nat_*, sans ffi) dans la table des modules générée (native.vm).
# État : VM [144] prochain identifiant  [152] bibliothèques  [160] fonctions  [168] buffers (dicts id -> fiche).
# Bibliothèque [poignée][nom][globale] ; fonction [adresse][bibliothèque][nom][nb][types][retour] ; buffer [octets][taille].
# Types : 0 void 1 bool 2 i8 3 u8 4 i16 5 u16 6 i32 7 u32 8 i64 9 u64 10 f32 11 f64 12 ptr 13 cstr.

func __vm_c(fp: int, a: int, b: int) -> int:
    f := __alloc_raw(168)
    __store64(f, a)
    __store64(f + 8, b)
    return __vm_sysv(fp, f)

# Appel C (convention System V) ; sous Windows, ni ffi ni TLS (comme la VM C++ : ffi_native.cpp, tls_native.cpp),
# ces appels ne sont jamais atteints.
func __vm_sysv(fp: int, f: int) -> int:
    if __windows():
        return 0
    else:
        return __sysv_call(fp, f)

# Fonctions de libdl / libc liées par ld-linux (0 sous Windows).
func __vm_imp(k: int) -> int:
    if __windows():
        return 0
    else:
        if k == 0:
            return __elf_import("libdl.so.2!dlopen")
        if k == 1:
            return __elf_import("libdl.so.2!dlsym")
        if k == 2:
            return __elf_import("libdl.so.2!dlclose")
        if k == 3:
            return __elf_import("libdl.so.2!dlerror")
        if k == 4:
            return __elf_import("libc.so.6!__errno_location")
        return __elf_import("libc.so.6!clock_gettime")

func __vm_ffi_off(fn: str):
    if __alexos():
        __dyn_err("IoError", fn + " : ffi n'existe pas sous Alex OS (aucune bibliothèque partagée)")
    if __windows() and __a64():
        __dyn_err("IoError", fn + " : ffi n'est pas supporté sur cette plateforme (x86-64 Linux / Windows, arm64 Linux requis)")

# Dernière erreur Windows (GetLastError) en texte court.
func __vm_win_err() -> str:
    if __windows():
        return "erreur Windows " + __int_to_str(__wincall("GetLastError") & 4294967295)
    else:
        return ""

func __vm_dlerror() -> str:
    if __windows():
        return ""
    p := __vm_c(__vm_imp(3), 0, 0)
    if p == 0:
        return ""
    return __nat_from_c(p)

func __vm_ffi_tab(off: int) -> int:
    vs := __vm_st()
    d := __load64(vs + off)
    if d == 0:
        d = __rt_dict_new(8)
        __store64(vs + off, d)
    return d

func __vm_ffi_id() -> int:
    vs := __vm_st()
    n := __load64(vs + 144) + 1
    __store64(vs + 144, n)
    return n

func __vm_ffi_get(off: int, id: int) -> int:
    d := __vm_ffi_tab(off)
    e := __rt_dict_index(d, id, 0)
    if e < 0:
        return 0
    return __load64(__load64(d + 32) + 8 * e)

func __vm_ffi_del(off: int, id: int):
    d := __vm_ffi_tab(off)
    if __rt_dict_index(d, id, 0) >= 0:
        __rt_dict_remove(d, id, 0)

func __vm_ffi_argfail(fn: str, text: str):
    __dyn_err("ArgumentError", "'" + fn + "' : " + text)

func __vm_ffi_type(fn: str, v: int, label: str) -> int:
    t := __nat_cstr(fn, v, label)
    if t == "void":
        return 0
    if t == "bool":
        return 1
    if t == "i8" or t == "int8":
        return 2
    if t == "u8" or t == "uint8" or t == "byte":
        return 3
    if t == "i16" or t == "short":
        return 4
    if t == "u16" or t == "ushort":
        return 5
    if t == "i32" or t == "int":
        return 6
    if t == "u32" or t == "uint":
        return 7
    if t == "i64" or t == "long" or t == "longlong" or t == "ssize_t" or t == "isize":
        return 8
    if t == "u64" or t == "ulong" or t == "size_t" or t == "usize":
        return 9
    if t == "f32" or t == "float":
        return 10
    if t == "f64" or t == "double":
        return 11
    if t == "ptr" or t == "pointer" or t == "void*":
        return 12
    if t == "cstr" or t == "char*" or t == "string":
        return 13
    __vm_ffi_argfail(fn, "type FFI inconnu '" + t + "'")
    return 0

func __vm_ffi_size(t: int) -> int:
    if t == 0:
        return 0
    if t <= 3:
        return 1
    if t <= 5:
        return 2
    if t <= 7 or t == 10:
        return 4
    return 8

func __vm_ffi_int(fn: str, v: int, label: str) -> int:
    return __nat_int(fn, v, label)

func __vm_ffi_number(fn: str, v: int, label: str) -> float:
    if __dyn_is(v, 1):
        return __i2f(__dyn_iv(v))
    if __dyn_is(v, 2):
        return __dyn_fv(v)
    __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un nombre (obtenu '" + __dyn_type_name(v) + "')")
    return 0.0

# Valeur ALEX -> entier du type t (bornes vérifiées).
func __vm_ffi_to_int(fn: str, v: int, t: int, label: str) -> int:
    if t == 1:
        if not __dyn_is(v, 3):
            __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un bool (obtenu '" + __dyn_type_name(v) + "')")
        return __load64(v + 8)
    x := __vm_ffi_int(fn, v, label)
    lo := 0
    hi := 0
    if t == 2:
        lo = -128
        hi = 127
    elif t == 3:
        hi = 255
    elif t == 4:
        lo = -32768
        hi = 32767
    elif t == 5:
        hi = 65535
    elif t == 6:
        lo = -2147483648
        hi = 2147483647
    elif t == 7:
        hi = 4294967295
    else:
        return x
    if x < lo or x > hi:
        __vm_ffi_argfail(fn, label + " hors limites pour ce type (" + __int_to_str(x) + ")")
    return x

# Entier brut (registre, mémoire) -> valeur ALEX du type t.
func __vm_ffi_from_int(fn: str, raw: int, t: int) -> int:
    if t == 1:
        return __dyn_bool((raw & 255) != 0)
    if t == 2:
        return __dyn_int(((raw & 255) ^ 128) - 128)
    if t == 3:
        return __dyn_int(raw & 255)
    if t == 4:
        return __dyn_int(((raw & 65535) ^ 32768) - 32768)
    if t == 5:
        return __dyn_int(raw & 65535)
    if t == 6:
        return __dyn_int(((raw & 4294967295) ^ 2147483648) - 2147483648)
    if t == 7:
        return __dyn_int(raw & 4294967295)
    if t == 9 and raw < 0:
        __dyn_err("ValueError", "'" + fn + "' : résultat u64 > 2^63-1, non représentable par un int ALEX")
    return __dyn_int(raw)

# Appel Windows x64 : n emplacements de 64 bits (entiers, ou bits des flottants) ; fl : rendre xmm0 au lieu de rax.
func __vm_ms(fp: int, s: int, n: int, fl: bool) -> int:
    if __windows():
        if n == 0:
            if fl:
                return __mscall_f(fp)
            return __mscall(fp)
        if n == 1:
            if fl:
                return __mscall_f(fp, __load64(s + 0))
            return __mscall(fp, __load64(s + 0))
        if n == 2:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8))
            return __mscall(fp, __load64(s + 0), __load64(s + 8))
        if n == 3:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16))
        if n == 4:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24))
        if n == 5:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32))
        if n == 6:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40))
        if n == 7:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48))
        if n == 8:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56))
        if n == 9:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64))
        if n == 10:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72))
        if n == 11:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80))
        if n == 12:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88))
        if n == 13:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96))
        if n == 14:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96), __load64(s + 104))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96), __load64(s + 104))
        if n == 15:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96), __load64(s + 104), __load64(s + 112))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96), __load64(s + 104), __load64(s + 112))
        if n == 16:
            if fl:
                return __mscall_f(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96), __load64(s + 104), __load64(s + 112), __load64(s + 120))
            return __mscall(fp, __load64(s + 0), __load64(s + 8), __load64(s + 16), __load64(s + 24), __load64(s + 32), __load64(s + 40), __load64(s + 48), __load64(s + 56), __load64(s + 64), __load64(s + 72), __load64(s + 80), __load64(s + 88), __load64(s + 96), __load64(s + 104), __load64(s + 112), __load64(s + 120))
    return 0

func __vm_nat__native_ffi__supported(n: int) -> int:
    __nat_exact("supported", n, 0)
    return __dyn_bool(not (__windows() and __a64()))

# Ouvre une bibliothèque : dlopen (POSIX) ou LoadLibraryA (Windows) ; 0 et message si échec.
func __vm_ffi_open(c: int) -> int:
    if __windows():
        if c == 0:
            return __wincall("GetModuleHandleA", 0)
        return __wincall("LoadLibraryA", c)
    return __vm_c(__vm_imp(0), c, 2)

func __vm_nat__native_ffi__load(n: int, a: int) -> int:
    __nat_exact("load", n, 1)
    __vm_ffi_off("load")
    lib := __alloc(24)
    name := "<processus>"
    h := 0
    if a == 0:
        h = __vm_ffi_open(0)
        __store64(lib + 16, 1)
    else:
        name = __nat_cstr("load", a, "le chemin")
        c := __nat_c(name)
        h = __vm_ffi_open(c)
    __store64(lib + 8, __str_addr(name))
    if h == 0:
        e := __vm_dlerror()
        if __windows():
            e = __vm_win_err()
        if __nat_blen(e) == 0:
            e = "échec de dlopen"
        __dyn_err("IoError", "load('" + name + "') : " + e)
    __store64(lib, h)
    id := __vm_ffi_id()
    __rt_dict_set(__vm_ffi_tab(152), id, lib, 0)
    return __dyn_int(id)

func __vm_ffi_lib(fn: str, v: int) -> int:
    id := __vm_ffi_int(fn, v, "la bibliothèque")
    lib := __vm_ffi_get(152, id)
    if lib == 0:
        __vm_ffi_argfail(fn, "bibliothèque invalide ou déchargée (" + __int_to_str(id) + ")")
    return lib

func __vm_ffi_lookup(lib: int, name: str) -> int:
    c := __nat_c(name)
    if __windows():
        return __wincall("GetProcAddress", __load64(lib), c)
    __vm_dlerror()
    p := __vm_c(__vm_imp(1), __load64(lib), c)
    if __nat_blen(__vm_dlerror()) != 0:
        return 0
    return p

func __vm_nat__native_ffi__unload(n: int, a: int) -> int:
    __nat_exact("unload", n, 1)
    id := __vm_ffi_int("unload", a, "la bibliothèque")
    lib := __vm_ffi_get(152, id)
    if lib == 0:
        return 0
    if __load64(lib + 16) == 0:
        if __windows():
            __wincall("FreeLibrary", __load64(lib))
        else:
            __vm_c(__vm_imp(2), __load64(lib), 0)
    __vm_ffi_del(152, id)
    fns := __vm_ffi_tab(160)
    e := 0
    while e < __load64(fns + 8):
        if __load64(__load64(fns + 40) + 8 * e) >= 0:
            f := __load64(__load64(fns + 32) + 8 * e)
            if __load64(f + 8) == id:
                __rt_dict_remove(fns, __load64(__load64(fns + 24) + 8 * e), 0)
        e += 1
    return 0

func __vm_nat__native_ffi__has_symbol(n: int, a: int, b: int) -> int:
    __nat_exact("has_symbol", n, 2)
    __vm_ffi_off("has_symbol")
    lib := __vm_ffi_lib("has_symbol", a)
    return __dyn_bool(__vm_ffi_lookup(lib, __nat_cstr("has_symbol", b, "le symbole")) != 0)

# Adresse brute d'un symbole (0 si absent) : pointeur de fonction à passer à du C (procédure de fenêtre...).
func __vm_nat__native_ffi__symbol_address(n: int, a: int, b: int) -> int:
    __nat_exact("symbol_address", n, 2)
    __vm_ffi_off("symbol_address")
    lib := __vm_ffi_lib("symbol_address", a)
    return __dyn_int(__vm_ffi_lookup(lib, __nat_cstr("symbol_address", b, "le symbole")))

# Fiche de fonction liée (adresse connue) : types vérifiés, limites de la convention d'appel.
# POSIX : 6 entiers + 8 flottants en registres, le reste sur la pile (au plus 16 emplacements).
# Windows x64 : au plus 16 arguments, quels que soient leurs types.
func __vm_ffi_make(fn: str, libId: int, name: str, addr: int, c: int, d: int) -> int:
    tl := __nat_items(fn, c, "les types d'arguments", "une list")
    na := __load64(tl)
    types := __alloc_raw(8 * na + 8)
    ints := 0
    floats := 0
    i := 0
    while i < na:
        t := __vm_ffi_type(fn, __rt_vec_at(tl, i), "un type d'argument")
        if t == 0:
            __vm_ffi_argfail(fn, "'void' n'est pas un type d'argument valide")
        if t == 10 or t == 11:
            floats += 1
        else:
            ints += 1
        __store64(types + 8 * i, t)
        i += 1
    if __windows():
        if na > 16:
            __vm_ffi_argfail(fn, "trop d'arguments pour '" + name + "' (16 au plus)")
    else:
        stack := 0
        if ints > 6:
            stack += ints - 6
        if floats > 8:
            stack += floats - 8
        if stack > 16:
            __vm_ffi_argfail(fn, "trop d'arguments pour '" + name + "' (6 entiers et 8 flottants en registres, puis 16 sur la pile)")
    ret := __vm_ffi_type(fn, d, "le type de retour")
    f := __alloc(48)
    __store64(f, addr)
    __store64(f + 8, libId)
    __store64(f + 16, __str_addr(name))
    __store64(f + 24, na)
    __store64(f + 32, types)
    __store64(f + 40, ret)
    id := __vm_ffi_id()
    __rt_dict_set(__vm_ffi_tab(160), id, f, 0)
    return __dyn_int(id)

func __vm_nat__native_ffi__bind(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("bind", n, 4)
    __vm_ffi_off("bind")
    libId := __vm_ffi_int("bind", a, "la bibliothèque")
    lib := __vm_ffi_lib("bind", a)
    name := __nat_cstr("bind", b, "le symbole")
    addr := __vm_ffi_lookup(lib, name)
    if addr == 0:
        e := __vm_dlerror()
        if __windows():
            e = __vm_win_err()
        if __nat_blen(e) == 0:
            e = "symbole introuvable"
        __dyn_err("IoError", "bind('" + name + "') : " + e)
    return __vm_ffi_make("bind", libId, name, addr, c, d)

# Fonction C à une adresse connue (pointeur rendu par wglGetProcAddress, glXGetProcAddress, une table...).
func __vm_nat__native_ffi__bind_addr(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("bind_addr", n, 4)
    __vm_ffi_off("bind_addr")
    addr := __vm_ffi_int("bind_addr", a, "l'adresse")
    if addr == 0:
        __vm_ffi_argfail("bind_addr", "adresse nulle")
    name := __nat_cstr("bind_addr", b, "le nom")
    return __vm_ffi_make("bind_addr", 0, name, addr, c, d)

func __vm_nat__native_ffi__unbind(n: int, a: int) -> int:
    __nat_exact("unbind", n, 1)
    __vm_ffi_del(160, __vm_ffi_int("unbind", a, "la fonction"))
    return 0

func __vm_nat__native_ffi__call(n: int, a: int, b: int) -> int:
    __nat_exact("call", n, 2)
    __vm_ffi_off("call")
    id := __vm_ffi_int("call", a, "la fonction")
    f := __vm_ffi_get(160, id)
    if f == 0:
        __vm_ffi_argfail("call", "fonction invalide ou bibliothèque déchargée (" + __int_to_str(id) + ")")
    given := __nat_items("call", b, "les arguments", "une list")
    na := __load64(f + 24)
    if __load64(given) != na:
        __vm_ffi_argfail("call", "'" + __as_str(__load64(f + 16)) + "' attend " + __int_to_str(na) + " argument(s), obtenu " + __int_to_str(__load64(given)))
    # cadre System V : [0..40] entiers [48..104] flottants [112] nb sur la pile [120] al [128] rax [136] xmm0
    # [160..288] pile ; Windows : emplacements consécutifs [0..128]
    fr := __alloc(296)       # parcouru par le GC : garde vivantes les chaînes C passées
    keep := __rt_list_new(0)
    win := __windows()
    ni := 0
    nd := 0
    ns := 0
    k := 0
    while k < na:
        t := __load64(__load64(f + 32) + 8 * k)
        label := "l'argument " + __int_to_str(k + 1)
        v := __rt_vec_at(given, k)
        raw := 0
        isf := t == 10 or t == 11
        if t == 11:
            raw = __f2bits(__vm_ffi_number("call", v, label))
        elif t == 10:
            raw = __nat_f32_bits(__vm_ffi_number("call", v, label))
        elif t == 13:
            if v != 0:
                cs := __nat_c(__nat_cstr("call", v, label))
                __rt_list_push(keep, cs)
                raw = cs
        elif t == 12 and v == 0:
            raw = 0
        else:
            raw = __vm_ffi_to_int("call", v, t, label)
        if win:
            __store64(fr + 8 * k, raw)
        elif isf and nd < 8:
            __store64(fr + 48 + 8 * nd, raw)
            nd += 1
        elif (not isf) and ni < 6:
            __store64(fr + 8 * ni, raw)
            ni += 1
        else:
            __store64(fr + 160 + 8 * ns, raw)
            ns += 1
        k += 1
    ret := __load64(f + 40)
    r := 0
    fbits := 0
    if win:
        if ret == 10 or ret == 11:
            fbits = __vm_ms(__load64(f), fr, na, true)
        else:
            r = __vm_ms(__load64(f), fr, na, false)
    else:
        __store64(fr + 112, ns)
        __store64(fr + 120, nd)
        r = __vm_sysv(__load64(f), fr)
        fbits = __load64(fr + 136)
    if __load64(keep) < 0:
        return 0 # garde `keep` vivante jusqu'ici
    if ret == 0:
        return 0
    if ret == 11:
        return __dyn_float(__bits2f(fbits))
    if ret == 10:
        return __dyn_float(__nat_f32_value(fbits & 4294967295))
    if ret == 13:
        if r == 0:
            return 0
        return __dyn_str(__nat_from_c(r))
    if ret == 12:
        if r == 0:
            return 0
        return __dyn_int(r)
    return __vm_ffi_from_int("call", r, ret)

func __vm_ffi_buf(fn: str, v: int) -> int:
    id := __vm_ffi_int(fn, v, "le buffer")
    b := __vm_ffi_get(168, id)
    if b == 0:
        __vm_ffi_argfail(fn, "buffer invalide ou libéré (" + __int_to_str(id) + ")")
    return b

func __vm_ffi_range(fn: str, b: int, off: int, len: int):
    if off < 0 or len < 0 or off + len > __load64(b + 8):
        __dyn_err("IndexError", "'" + fn + "' : accès hors buffer (offset " + __int_to_str(off) + ", longueur " + __int_to_str(len) + ", taille " + __int_to_str(__load64(b + 8)) + ")")

func __vm_nat__native_ffi__buf_alloc(n: int, a: int) -> int:
    __nat_exact("buf_alloc", n, 1)
    sz := __vm_ffi_int("buf_alloc", a, "la taille")
    if sz < 1 or sz > 1073741824:
        __vm_ffi_argfail("buf_alloc", "taille hors limites (1..1073741824)")
    b := __alloc(16)
    __store64(b, __alloc_raw(sz))
    __store64(b + 8, sz)
    id := __vm_ffi_id()
    __rt_dict_set(__vm_ffi_tab(168), id, b, 0)
    return __dyn_int(id)

func __vm_nat__native_ffi__buf_free(n: int, a: int) -> int:
    __nat_exact("buf_free", n, 1)
    __vm_ffi_del(168, __vm_ffi_int("buf_free", a, "le buffer"))
    return 0

func __vm_nat__native_ffi__buf_size(n: int, a: int) -> int:
    __nat_exact("buf_size", n, 1)
    return __dyn_int(__load64(__vm_ffi_buf("buf_size", a) + 8))

func __vm_nat__native_ffi__buf_address(n: int, a: int) -> int:
    __nat_exact("buf_address", n, 1)
    return __dyn_int(__load64(__vm_ffi_buf("buf_address", a)))

func __vm_ffi_load_n(p: int, sz: int) -> int:
    if sz == 1:
        return __load8(p)
    if sz == 2:
        return __load16(p)
    if sz == 4:
        return __load32(p)
    return __load64(p)

func __vm_ffi_store_n(p: int, sz: int, x: int):
    if sz == 1:
        __store8(p, x)
    elif sz == 2:
        __store16(p, x)
    elif sz == 4:
        __store32(p, x)
    else:
        __store64(p, x)

func __vm_nat__native_ffi__buf_read(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("buf_read", n, 3)
    bf := __vm_ffi_buf("buf_read", a)
    off := __vm_ffi_int("buf_read", b, "l'offset")
    t := __vm_ffi_type("buf_read", c, "le type")
    if t == 0:
        __vm_ffi_argfail("buf_read", "'void' n'est pas lisible")
    if t == 13:
        __vm_ffi_range("buf_read", bf, off, 0)
        p := __load64(bf) + off
        k := 0
        while off + k < __load64(bf + 8) and __load8(p + k) != 0:
            k += 1
        if off + k >= __load64(bf + 8):
            __vm_ffi_argfail("buf_read", "aucun NUL de fin dans le buffer à partir de l'offset " + __int_to_str(off))
        return __dyn_str(__nat_make(p, k))
    sz := __vm_ffi_size(t)
    __vm_ffi_range("buf_read", bf, off, sz)
    raw := __vm_ffi_load_n(__load64(bf) + off, sz)
    if t == 10:
        return __dyn_float(__nat_f32_value(raw))
    if t == 11:
        return __dyn_float(__bits2f(raw))
    if t == 12:
        if raw == 0:
            return 0
        return __dyn_int(raw)
    return __vm_ffi_from_int("buf_read", raw, t)

func __vm_nat__native_ffi__buf_write(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("buf_write", n, 4)
    bf := __vm_ffi_buf("buf_write", a)
    off := __vm_ffi_int("buf_write", b, "l'offset")
    t := __vm_ffi_type("buf_write", c, "le type")
    if t == 0:
        __vm_ffi_argfail("buf_write", "'void' n'est pas écrivable")
    if t == 13:
        s := __nat_cstr("buf_write", d, "la valeur")
        __vm_ffi_range("buf_write", bf, off, __nat_blen(s) + 1)
        __copy(__load64(bf) + off, __nat_bp(s), __nat_blen(s))
        __store8(__load64(bf) + off + __nat_blen(s), 0)
        return __dyn_int(__nat_blen(s) + 1)
    sz := __vm_ffi_size(t)
    __vm_ffi_range("buf_write", bf, off, sz)
    p := __load64(bf) + off
    if t == 10:
        __store32(p, __nat_f32_bits(__vm_ffi_number("buf_write", d, "la valeur")))
    elif t == 11:
        __store64(p, __f2bits(__vm_ffi_number("buf_write", d, "la valeur")))
    elif t == 12 and d == 0:
        __store64(p, 0)
    else:
        __vm_ffi_store_n(p, sz, __vm_ffi_to_int("buf_write", d, t, "la valeur"))
    return __dyn_int(sz)

func __vm_nat__native_ffi__buf_read_bytes(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("buf_read_bytes", n, 3)
    bf := __vm_ffi_buf("buf_read_bytes", a)
    off := __vm_ffi_int("buf_read_bytes", b, "l'offset")
    len := __vm_ffi_int("buf_read_bytes", c, "la longueur")
    __vm_ffi_range("buf_read_bytes", bf, off, len)
    return __dyn_str(__nat_make(__load64(bf) + off, len))

func __vm_nat__native_ffi__buf_write_bytes(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("buf_write_bytes", n, 3)
    bf := __vm_ffi_buf("buf_write_bytes", a)
    off := __vm_ffi_int("buf_write_bytes", b, "l'offset")
    s := __nat_str("buf_write_bytes", c, "les octets")
    __vm_ffi_range("buf_write_bytes", bf, off, __nat_blen(s))
    __copy(__load64(bf) + off, __nat_bp(s), __nat_blen(s))
    return __dyn_int(__nat_blen(s))

func __vm_nat__native_ffi__buf_fill(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("buf_fill", n, 4)
    bf := __vm_ffi_buf("buf_fill", a)
    off := __vm_ffi_int("buf_fill", b, "l'offset")
    len := __vm_ffi_int("buf_fill", c, "la longueur")
    v := __vm_ffi_int("buf_fill", d, "l'octet")
    if v < 0 or v > 255:
        __vm_ffi_argfail("buf_fill", "octet hors limites (0..255)")
    __vm_ffi_range("buf_fill", bf, off, len)
    p := __load64(bf) + off
    k := 0
    while k < len:
        __store8(p + k, v)
        k += 1
    return 0

# Écrit une list de nombres en bloc (sommets, indices, échantillons). Type « pcm16 » : flottants [-1, 1] bornés puis
# convertis en entiers 16 bits signés (son). Rend le nombre d'octets écrits.
func __vm_nat__native_ffi__buf_write_array(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("buf_write_array", n, 4)
    bf := __vm_ffi_buf("buf_write_array", a)
    off := __vm_ffi_int("buf_write_array", b, "l'offset")
    pcm := false
    t := 0
    tn := __nat_cstr("buf_write_array", c, "le type")
    if tn == "pcm16":
        pcm = true
        t = 4
    else:
        t = __vm_ffi_type("buf_write_array", c, "le type")
    if t == 0 or t == 13:
        __vm_ffi_argfail("buf_write_array", "type d'élément invalide pour un tableau")
    items := __nat_items("buf_write_array", d, "les valeurs", "une list")
    cnt := __load64(items)
    sz := __vm_ffi_size(t)
    __vm_ffi_range("buf_write_array", bf, off, sz * cnt)
    p := __load64(bf) + off
    k := 0
    while k < cnt:
        v := __rt_vec_at(items, k)
        if pcm:
            x := __vm_ffi_number("buf_write_array", v, "un échantillon")
            if x > 1.0:
                x = 1.0
            if x < -1.0:
                x = -1.0
            __store16(p, __f2i(x * 32767.0) & 65535)
        elif t == 10:
            __store32(p, __nat_f32_bits(__vm_ffi_number("buf_write_array", v, "un élément")))
        elif t == 11:
            __store64(p, __f2bits(__vm_ffi_number("buf_write_array", v, "un élément")))
        elif t == 12 and v == 0:
            __store64(p, 0)
        else:
            __vm_ffi_store_n(p, sz, __vm_ffi_to_int("buf_write_array", v, t, "un élément"))
        p += sz
        k += 1
    return __dyn_int(sz * cnt)

# Lit `count` éléments du type donné en une list.
func __vm_nat__native_ffi__buf_read_array(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("buf_read_array", n, 4)
    bf := __vm_ffi_buf("buf_read_array", a)
    off := __vm_ffi_int("buf_read_array", b, "l'offset")
    t := __vm_ffi_type("buf_read_array", c, "le type")
    if t == 0 or t == 13:
        __vm_ffi_argfail("buf_read_array", "type d'élément invalide pour un tableau")
    cnt := __vm_ffi_int("buf_read_array", d, "le nombre")
    sz := __vm_ffi_size(t)
    __vm_ffi_range("buf_read_array", bf, off, sz * cnt)
    return __vm_ffi_read_list(__load64(bf) + off, t, cnt)

func __vm_ffi_read_list(p: int, t: int, cnt: int) -> int:
    sz := __vm_ffi_size(t)
    out := __dyn_list_new(0)
    k := 0
    while k < cnt:
        raw := __vm_ffi_load_n(p + sz * k, sz)
        if t == 10:
            __dyn_list_push(out, __dyn_float(__nat_f32_value(raw)))
        elif t == 11:
            __dyn_list_push(out, __dyn_float(__bits2f(raw)))
        elif t == 12:
            __dyn_list_push(out, __dyn_int(raw))
        else:
            __dyn_list_push(out, __vm_ffi_from_int("buf_read_array", raw, t))
        k += 1
    return out

# Accès mémoire NON PROTÉGÉS à une adresse brute rendue par du C (champ d'une structure pointée...). Une adresse
# fausse fait planter le processus, comme en C.
func __vm_nat__native_ffi__ptr_read(n: int, a: int, b: int) -> int:
    __nat_exact("ptr_read", n, 2)
    p := __vm_ffi_int("ptr_read", a, "l'adresse")
    if p == 0:
        __vm_ffi_argfail("ptr_read", "adresse nulle")
    t := __vm_ffi_type("ptr_read", b, "le type")
    if t == 0:
        __vm_ffi_argfail("ptr_read", "'void' n'est pas lisible")
    if t == 13:
        q := __load64(p)
        if q == 0:
            return 0
        return __dyn_str(__nat_from_c(q))
    return __dyn_list_at(__vm_ffi_read_list(p, t, 1), 0)

func __vm_nat__native_ffi__ptr_write(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("ptr_write", n, 3)
    p := __vm_ffi_int("ptr_write", a, "l'adresse")
    if p == 0:
        __vm_ffi_argfail("ptr_write", "adresse nulle")
    t := __vm_ffi_type("ptr_write", b, "le type")
    if t == 0 or t == 13:
        __vm_ffi_argfail("ptr_write", "type non écrivable par adresse")
    if t == 10:
        __store32(p, __nat_f32_bits(__vm_ffi_number("ptr_write", c, "la valeur")))
    elif t == 11:
        __store64(p, __f2bits(__vm_ffi_number("ptr_write", c, "la valeur")))
    elif t == 12 and c == 0:
        __store64(p, 0)
    else:
        __vm_ffi_store_n(p, __vm_ffi_size(t), __vm_ffi_to_int("ptr_write", c, t, "la valeur"))
    return 0

func __vm_nat__native_ffi__ptr_read_bytes(n: int, a: int, b: int) -> int:
    __nat_exact("ptr_read_bytes", n, 2)
    p := __vm_ffi_int("ptr_read_bytes", a, "l'adresse")
    len := __vm_ffi_int("ptr_read_bytes", b, "la longueur")
    if p == 0 or len < 0:
        __vm_ffi_argfail("ptr_read_bytes", "adresse nulle ou longueur négative")
    return __dyn_str(__nat_make(p, len))

# Copie d'un buffer vers un autre (offsets et longueur vérifiés).
func __vm_nat__native_ffi__buf_copy(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("buf_copy", n, 5)
    dst := __vm_ffi_buf("buf_copy", a)
    doff := __vm_ffi_int("buf_copy", b, "l'offset de destination")
    src := __vm_ffi_buf("buf_copy", c)
    soff := __vm_ffi_int("buf_copy", d, "l'offset de source")
    len := __vm_ffi_int("buf_copy", e, "la longueur")
    __vm_ffi_range("buf_copy", dst, doff, len)
    __vm_ffi_range("buf_copy", src, soff, len)
    __copy(__load64(dst) + doff, __load64(src) + soff, len)
    return 0

# ---- Mixage audio en code natif (audio.realtime) --------------------------------------------------------------------
# Accumulateur : flottants 64 bits stéréo entrelacés ; sons : entiers 16 bits signés entrelacés (1 ou 2 canaux).

func __vm_s16(v: int) -> int:
    v = v & 65535
    if v >= 32768:
        return v - 65536
    return v

# Ajoute `frames` images du son `src` (à partir de l'image `first`) à l'accumulateur (à partir de son image `at`),
# avec les gains gauche / droite.
func __vm_nat__native_ffi__audio_mix(n: int, a: int, h: int, b: int, c: int, d: int, e: int, f: int, g: int) -> int:
    __nat_exact("audio_mix", n, 8)
    acc := __vm_ffi_buf("audio_mix", a)
    at := __vm_ffi_int("audio_mix", h, "l'image de destination")
    src := __vm_ffi_buf("audio_mix", b)
    first := __vm_ffi_int("audio_mix", c, "la première image")
    frames := __vm_ffi_int("audio_mix", d, "le nombre d'images")
    ch := __vm_ffi_int("audio_mix", e, "le nombre de canaux")
    gl := __vm_ffi_number("audio_mix", f, "le gain gauche") / 32768.0
    gr := __vm_ffi_number("audio_mix", g, "le gain droit") / 32768.0
    if ch != 1 and ch != 2:
        __vm_ffi_argfail("audio_mix", "1 ou 2 canaux")
    __vm_ffi_range("audio_mix", acc, at * 16, frames * 16)
    __vm_ffi_range("audio_mix", src, first * ch * 2, frames * ch * 2)
    pa := __load64(acc) + at * 16
    ps := __load64(src) + first * ch * 2
    k := 0
    while k < frames:
        l := 0.0
        r := 0.0
        if ch == 2:
            l = __i2f(__vm_s16(__load16(ps + 4 * k)))
            r = __i2f(__vm_s16(__load16(ps + 4 * k + 2)))
        else:
            l = __i2f(__vm_s16(__load16(ps + 2 * k)))
            r = l
        q := pa + 16 * k
        __store64(q, __f2bits(__bits2f(__load64(q)) + l * gl))
        __store64(q + 8, __f2bits(__bits2f(__load64(q + 8)) + r * gr))
        k += 1
    return 0

# Accumulateur (flottants, [-1, 1]) -> entiers 16 bits stéréo bornés, multiplié par `gain` ; remet l'accumulateur à zéro.
func __vm_nat__native_ffi__audio_out(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("audio_out", n, 4)
    dst := __vm_ffi_buf("audio_out", a)
    acc := __vm_ffi_buf("audio_out", b)
    frames := __vm_ffi_int("audio_out", c, "le nombre d'images")
    gain := __vm_ffi_number("audio_out", d, "le gain")
    __vm_ffi_range("audio_out", acc, 0, frames * 16)
    __vm_ffi_range("audio_out", dst, 0, frames * 4)
    pa := __load64(acc)
    pd := __load64(dst)
    k := 0
    while k < 2 * frames:
        x := __bits2f(__load64(pa + 8 * k)) * gain
        if x > 1.0:
            x = 1.0
        if x < -1.0:
            x = -1.0
        __store16(pd + 2 * k, __f2i(x * 32767.0) & 65535)
        __store64(pa + 8 * k, 0)
        k += 1
    return 0

# Rééchantillonnage linéaire d'entiers 16 bits entrelacés : src (src_frames images) -> dst (dst_frames images).
func __vm_nat__native_ffi__audio_resample(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("audio_resample", n, 5)
    dst := __vm_ffi_buf("audio_resample", a)
    src := __vm_ffi_buf("audio_resample", b)
    sf := __vm_ffi_int("audio_resample", c, "le nombre d'images source")
    ch := __vm_ffi_int("audio_resample", d, "le nombre de canaux")
    df := __vm_ffi_int("audio_resample", e, "le nombre d'images cible")
    if sf < 1 or df < 1 or ch < 1 or ch > 8:
        __vm_ffi_argfail("audio_resample", "dimensions invalides")
    __vm_ffi_range("audio_resample", src, 0, sf * ch * 2)
    __vm_ffi_range("audio_resample", dst, 0, df * ch * 2)
    ps := __load64(src)
    pd := __load64(dst)
    step := __i2f(sf) / __i2f(df)
    k := 0
    while k < df:
        pos := __i2f(k) * step
        i0 := __f2i(pos)
        if i0 >= sf - 1:
            i0 = sf - 1
        i1 := i0 + 1
        if i1 >= sf:
            i1 = sf - 1
        t := pos - __i2f(i0)
        c2 := 0
        while c2 < ch:
            v0 := __i2f(__vm_s16(__load16(ps + 2 * (i0 * ch + c2))))
            v1 := __i2f(__vm_s16(__load16(ps + 2 * (i1 * ch + c2))))
            __store16(pd + 2 * (k * ch + c2), __f2i(v0 + (v1 - v0) * t) & 65535)
            c2 += 1
        k += 1
    return 0

# IMDCT (décodeur Vorbis, audio.vorbis) : y[i] = somme X[j] cos(pi / 2n (2i + 1 + n/2)(2j + 1)), n/2 coefficients
# -> n échantillons, par une DCT-IV calculée avec une FFT complexe de taille n/4. Flottants 64 bits.
# Table (5 * n/4 flottants, calculée par l'appelant) : [cos, sin de pi(k + 1/4) / (n/2)] x n/4, [cos, sin de
# pi j / (n/2)] x n/4, [cos, sin de 2 pi m / (n/4)] x n/8 ; travail : n/2 flottants.
func __vm_imd_ld(p: int, i: int) -> float:
    return __bits2f(__load64(p + 8 * i))

func __vm_imd_st(p: int, i: int, v: float):
    __store64(p + 8 * i, __f2bits(v))

func __vm_nat__native_ffi__audio_imdct(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("audio_imdct", n, 5)
    ib := __vm_ffi_buf("audio_imdct", a)
    ob := __vm_ffi_buf("audio_imdct", b)
    nn := __vm_ffi_int("audio_imdct", c, "la taille de bloc")
    tb := __vm_ffi_buf("audio_imdct", d)
    wb := __vm_ffi_buf("audio_imdct", e)
    if nn < 16 or (nn & (nn - 1)) != 0:
        __vm_ffi_argfail("audio_imdct", "taille de bloc : puissance de 2 >= 16")
    big := nn >> 1
    h := big >> 1
    __vm_ffi_range("audio_imdct", ib, 0, big * 8)
    __vm_ffi_range("audio_imdct", ob, 0, nn * 8)
    __vm_ffi_range("audio_imdct", tb, 0, 5 * h * 8)
    __vm_ffi_range("audio_imdct", wb, 0, big * 8)
    px := __load64(ib)
    po := __load64(ob)
    pt := __load64(tb)
    pw := __load64(wb)
    ppost := pt + 16 * h
    pfft := pt + 32 * h
    # pré-rotation : w[k] = (X[2k] + i X[N-1-2k]) * exp(-i pi (k + 1/4) / N)
    k := 0
    while k < h:
        re := __vm_imd_ld(px, 2 * k)
        im := __vm_imd_ld(px, big - 1 - 2 * k)
        cc := __vm_imd_ld(pt, 2 * k)
        ss := __vm_imd_ld(pt, 2 * k + 1)
        __vm_imd_st(pw, 2 * k, re * cc + im * ss)
        __vm_imd_st(pw, 2 * k + 1, im * cc - re * ss)
        k += 1
    # permutation par inversion des bits
    bits := 0
    while (1 << bits) < h:
        bits += 1
    k = 0
    while k < h:
        r := 0
        x := k
        q := 0
        while q < bits:
            r = (r << 1) | (x & 1)
            x = x >> 1
            q += 1
        if r > k:
            t0 := __load64(pw + 16 * k)
            t1 := __load64(pw + 16 * k + 8)
            __store64(pw + 16 * k, __load64(pw + 16 * r))
            __store64(pw + 16 * k + 8, __load64(pw + 16 * r + 8))
            __store64(pw + 16 * r, t0)
            __store64(pw + 16 * r + 8, t1)
        k += 1
    # FFT itérative (exp(-2 pi i jk / h))
    size := 2
    lg := 1
    while size <= h:
        half := size >> 1
        step := h >> lg
        start := 0
        while start < h:
            j := 0
            while j < half:
                tc := __vm_imd_ld(pfft, 2 * j * step)
                ts := __vm_imd_ld(pfft, 2 * j * step + 1)
                ia := start + j
                ibx := ia + half
                br := __vm_imd_ld(pw, 2 * ibx)
                bi := __vm_imd_ld(pw, 2 * ibx + 1)
                xr := br * tc + bi * ts
                xi := bi * tc - br * ts
                ar := __vm_imd_ld(pw, 2 * ia)
                ai := __vm_imd_ld(pw, 2 * ia + 1)
                __vm_imd_st(pw, 2 * ia, ar + xr)
                __vm_imd_st(pw, 2 * ia + 1, ai + xi)
                __vm_imd_st(pw, 2 * ibx, ar - xr)
                __vm_imd_st(pw, 2 * ibx + 1, ai - xi)
                j += 1
            start += size
        size = size * 2
        lg += 1
    # post-rotation : u[2j] = Re, u[N-1-2j] = -Im de V[j] * exp(-i pi j / N) (u rangé dans out[0..N))
    j2 := 0
    while j2 < h:
        vr := __vm_imd_ld(pw, 2 * j2)
        vi := __vm_imd_ld(pw, 2 * j2 + 1)
        pc := __vm_imd_ld(ppost, 2 * j2)
        ps := __vm_imd_ld(ppost, 2 * j2 + 1)
        __vm_imd_st(po, 2 * j2, vr * pc + vi * ps)
        __vm_imd_st(po, big - 1 - 2 * j2, 0.0 - (vi * pc - vr * ps))
        j2 += 1
    __copy(pw, po, big * 8)
    # dépliement de la DCT-IV vers les n échantillons
    q2 := big >> 1
    i := 0
    while i < nn:
        if i < q2:
            __vm_imd_st(po, i, __vm_imd_ld(pw, i + q2))
        elif i < 3 * q2:
            __vm_imd_st(po, i, 0.0 - __vm_imd_ld(pw, 3 * q2 - 1 - i))
        else:
            __vm_imd_st(po, i, 0.0 - __vm_imd_ld(pw, i - 3 * q2))
        i += 1
    return 0

# ---- Synthèse Vorbis en code natif (audio.vorbis) : flottants 64 bits -------------------------------------------------

# Découplage carré polaire (magnitude, angle) sur `half` coefficients.
func __vm_nat__native_ffi__audio_vcouple(n: int, a: int, b: int, c: int) -> int:
    __nat_exact("audio_vcouple", n, 3)
    mb := __vm_ffi_buf("audio_vcouple", a)
    ab := __vm_ffi_buf("audio_vcouple", b)
    half := __vm_ffi_int("audio_vcouple", c, "la taille")
    __vm_ffi_range("audio_vcouple", mb, 0, half * 8)
    __vm_ffi_range("audio_vcouple", ab, 0, half * 8)
    pm := __load64(mb)
    pa := __load64(ab)
    j := 0
    while j < half:
        m := __vm_imd_ld(pm, j)
        x := __vm_imd_ld(pa, j)
        if m > 0.0:
            if x > 0.0:
                __vm_imd_st(pa, j, m - x)
            else:
                __vm_imd_st(pa, j, m)
                __vm_imd_st(pm, j, m + x)
        else:
            if x > 0.0:
                __vm_imd_st(pa, j, m + x)
            else:
                __vm_imd_st(pa, j, m)
                __vm_imd_st(pm, j, m - x)
        j += 1
    return 0

func __vm_tdiv(a: int, b: int) -> int:
    na := a
    if na < 0:
        na = 0 - na
    nb := b
    if nb < 0:
        nb = 0 - nb
    q := na / nb
    if (a < 0) != (b < 0):
        return 0 - __f2i(q)
    return __f2i(q)

# Courbe floor 1 : segments entre `npts` points (x, y) entiers (i64 par paires), multipliée dans les coefficients
# (coef[x] *= table[y], table de 256 flottants).
func __vm_nat__native_ffi__audio_vfloor(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("audio_vfloor", n, 5)
    cb := __vm_ffi_buf("audio_vfloor", a)
    pb := __vm_ffi_buf("audio_vfloor", b)
    npts := __vm_ffi_int("audio_vfloor", c, "le nombre de points")
    half := __vm_ffi_int("audio_vfloor", d, "la taille")
    tb := __vm_ffi_buf("audio_vfloor", e)
    __vm_ffi_range("audio_vfloor", cb, 0, half * 8)
    __vm_ffi_range("audio_vfloor", pb, 0, npts * 16)
    __vm_ffi_range("audio_vfloor", tb, 0, 256 * 8)
    pc := __load64(cb)
    pp := __load64(pb)
    pt := __load64(tb)
    k := 0
    while k + 1 < npts:
        x0 := __load64(pp + 16 * k)
        y0 := __load64(pp + 16 * k + 8)
        x1 := __load64(pp + 16 * k + 16)
        y1 := __load64(pp + 16 * k + 24)
        dy := y1 - y0
        adx := x1 - x0
        if adx > 0:
            ady := dy
            if ady < 0:
                ady = 0 - ady
            base := __vm_tdiv(dy, adx)
            sy := base + 1
            if dy < 0:
                sy = base - 1
            ab := base
            if ab < 0:
                ab = 0 - ab
            ady = ady - ab * adx
            x := x0
            y := y0
            err := 0
            while x < x1:
                if x > x0:
                    err += ady
                    if err >= adx:
                        err -= adx
                        y += sy
                    else:
                        y += base
                if x >= 0 and x < half:
                    yy := y
                    if yy < 0:
                        yy = 0
                    if yy > 255:
                        yy = 255
                    __vm_imd_st(pc, x, __vm_imd_ld(pc, x) * __vm_imd_ld(pt, yy))
                x += 1
        k += 1
    return 0

# Fenêtre : 0 avant lws, pente montante (ln valeurs de lwin), 1, pente descendante (rn valeurs de rwin lues à
# rebours) à partir de rws, 0 après.
func __vm_nat__native_ffi__audio_vwindow(n: int, a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int) -> int:
    __nat_exact("audio_vwindow", n, 8)
    bb := __vm_ffi_buf("audio_vwindow", a)
    nn := __vm_ffi_int("audio_vwindow", b, "la taille")
    lws := __vm_ffi_int("audio_vwindow", c, "le début gauche")
    ln := __vm_ffi_int("audio_vwindow", d, "la pente gauche")
    lw := __vm_ffi_buf("audio_vwindow", e)
    rws := __vm_ffi_int("audio_vwindow", f, "le début droit")
    rn := __vm_ffi_int("audio_vwindow", g, "la pente droite")
    rw := __vm_ffi_buf("audio_vwindow", h)
    __vm_ffi_range("audio_vwindow", bb, 0, nn * 8)
    __vm_ffi_range("audio_vwindow", lw, 0, ln * 8)
    __vm_ffi_range("audio_vwindow", rw, 0, rn * 8)
    if lws < 0 or lws + ln > nn or rws < 0 or rws + rn > nn:
        __vm_ffi_argfail("audio_vwindow", "fenêtre hors du bloc")
    p := __load64(bb)
    pl := __load64(lw)
    pr := __load64(rw)
    j := 0
    while j < lws:
        __store64(p + 8 * j, 0)
        j += 1
    j = 0
    while j < ln:
        __vm_imd_st(p, lws + j, __vm_imd_ld(p, lws + j) * __vm_imd_ld(pl, j))
        j += 1
    j = 0
    while j < rn:
        __vm_imd_st(p, rws + j, __vm_imd_ld(p, rws + j) * __vm_imd_ld(pr, rn - 1 - j))
        j += 1
    j = rws + rn
    while j < nn:
        __store64(p + 8 * j, 0)
        j += 1
    return 0

# Recouvrement du bloc courant (n) avec le précédent (pn) et écriture en entiers 16 bits dans `out` (entrelacé,
# canal `chi` sur `nch`) à partir de l'image `at` ; les images au-delà du tampon sont ignorées. Rend le nombre
# d'images produites (n/4 + pn/4).
func __vm_nat__native_ffi__audio_voverlap(n: int, a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int) -> int:
    __nat_exact("audio_voverlap", n, 8)
    pb := __vm_ffi_buf("audio_voverlap", a)
    cb := __vm_ffi_buf("audio_voverlap", b)
    pn := __vm_ffi_int("audio_voverlap", c, "la taille précédente")
    nn := __vm_ffi_int("audio_voverlap", d, "la taille")
    ob := __vm_ffi_buf("audio_voverlap", e)
    at := __vm_ffi_int("audio_voverlap", f, "l'image de départ")
    chi := __vm_ffi_int("audio_voverlap", g, "le canal")
    nch := __vm_ffi_int("audio_voverlap", h, "le nombre de canaux")
    __vm_ffi_range("audio_voverlap", pb, 0, pn * 8)
    __vm_ffi_range("audio_voverlap", cb, 0, nn * 8)
    pp := __load64(pb)
    pc := __load64(cb)
    po := __load64(ob)
    osz := __load64(ob + 8)
    half := nn >> 1
    start := (nn >> 2) - (pn >> 2)
    shift := 3 * (pn >> 2) - (nn >> 2)
    fr := at
    j := start
    while j < half:
        x := 0.0
        if j >= 0:
            x = __vm_imd_ld(pc, j)
        q := j + shift
        if q < pn:
            x = x + __vm_imd_ld(pp, q)
        if x > 1.0:
            x = 1.0
        if x < -1.0:
            x = -1.0
        o := 2 * (fr * nch + chi)
        if o + 2 <= osz:
            __store16(po + o, __f2i(x * 32767.0) & 65535)
        fr += 1
        j += 1
    return __dyn_int(fr - at)

# ---- Animation squelettique (stdlib animation) : matrices monde et matrices d'os en code natif -----------------------
# Mat4 en ordre colonne (math3d) : m[colonne * 4 + ligne].

func __vm_m4_mul(pa: int, pb: int, pr: int):
    c := 0
    while c < 4:
        r := 0
        while r < 4:
            s := 0.0
            k := 0
            while k < 4:
                s = s + __vm_imd_ld(pa, k * 4 + r) * __vm_imd_ld(pb, c * 4 + k)
                k += 1
            __vm_imd_st(pr, c * 4 + r, s)
            r += 1
        c += 1

# Matrice locale depuis translation (3), rotation quaternion (4), échelle (3).
func __vm_m4_trs(pt: int, pm: int):
    tx := __vm_imd_ld(pt, 0)
    ty := __vm_imd_ld(pt, 1)
    tz := __vm_imd_ld(pt, 2)
    x := __vm_imd_ld(pt, 3)
    y := __vm_imd_ld(pt, 4)
    z := __vm_imd_ld(pt, 5)
    w := __vm_imd_ld(pt, 6)
    sx := __vm_imd_ld(pt, 7)
    sy := __vm_imd_ld(pt, 8)
    sz := __vm_imd_ld(pt, 9)
    __vm_imd_st(pm, 0, (1.0 - 2.0 * (y * y + z * z)) * sx)
    __vm_imd_st(pm, 1, (2.0 * (x * y + z * w)) * sx)
    __vm_imd_st(pm, 2, (2.0 * (x * z - y * w)) * sx)
    __vm_imd_st(pm, 3, 0.0)
    __vm_imd_st(pm, 4, (2.0 * (x * y - z * w)) * sy)
    __vm_imd_st(pm, 5, (1.0 - 2.0 * (x * x + z * z)) * sy)
    __vm_imd_st(pm, 6, (2.0 * (y * z + x * w)) * sy)
    __vm_imd_st(pm, 7, 0.0)
    __vm_imd_st(pm, 8, (2.0 * (x * z + y * w)) * sz)
    __vm_imd_st(pm, 9, (2.0 * (y * z - x * w)) * sz)
    __vm_imd_st(pm, 10, (1.0 - 2.0 * (x * x + y * y)) * sz)
    __vm_imd_st(pm, 11, 0.0)
    __vm_imd_st(pm, 12, tx)
    __vm_imd_st(pm, 13, ty)
    __vm_imd_st(pm, 14, tz)
    __vm_imd_st(pm, 15, 1.0)

# Inverse d'une matrice affine (3x3 + translation).
func __vm_m4_inv_affine(pa: int, pr: int):
    a := __vm_imd_ld(pa, 0)
    b := __vm_imd_ld(pa, 4)
    c := __vm_imd_ld(pa, 8)
    d := __vm_imd_ld(pa, 1)
    e := __vm_imd_ld(pa, 5)
    f := __vm_imd_ld(pa, 9)
    g := __vm_imd_ld(pa, 2)
    h := __vm_imd_ld(pa, 6)
    i := __vm_imd_ld(pa, 10)
    det := a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)
    if det == 0.0:
        det = 1.0
    inv := 1.0 / det
    r00 := (e * i - f * h) * inv
    r01 := (c * h - b * i) * inv
    r02 := (b * f - c * e) * inv
    r10 := (f * g - d * i) * inv
    r11 := (a * i - c * g) * inv
    r12 := (c * d - a * f) * inv
    r20 := (d * h - e * g) * inv
    r21 := (b * g - a * h) * inv
    r22 := (a * e - b * d) * inv
    tx := __vm_imd_ld(pa, 12)
    ty := __vm_imd_ld(pa, 13)
    tz := __vm_imd_ld(pa, 14)
    __vm_imd_st(pr, 0, r00)
    __vm_imd_st(pr, 1, r10)
    __vm_imd_st(pr, 2, r20)
    __vm_imd_st(pr, 3, 0.0)
    __vm_imd_st(pr, 4, r01)
    __vm_imd_st(pr, 5, r11)
    __vm_imd_st(pr, 6, r21)
    __vm_imd_st(pr, 7, 0.0)
    __vm_imd_st(pr, 8, r02)
    __vm_imd_st(pr, 9, r12)
    __vm_imd_st(pr, 10, r22)
    __vm_imd_st(pr, 11, 0.0)
    __vm_imd_st(pr, 12, 0.0 - (r00 * tx + r01 * ty + r02 * tz))
    __vm_imd_st(pr, 13, 0.0 - (r10 * tx + r11 * ty + r12 * tz))
    __vm_imd_st(pr, 14, 0.0 - (r20 * tx + r21 * ty + r22 * tz))
    __vm_imd_st(pr, 15, 1.0)

# trs : 10 flottants par nœud ; parents / order : entiers 64 bits (order : parents avant enfants) ; world : 16
# flottants par nœud (sortie) ; joints : [nombre, nœud du maillage ou -1, nœud de chaque os...] ; invbind : 16
# flottants par os ; out : 16 flottants 32 bits par os (matrices d'os prêtes pour la carte graphique).
func __vm_nat__native_ffi__anim_skin(n: int, a: int, b: int, c: int, d: int, e: int, f: int, g: int, h: int) -> int:
    __nat_exact("anim_skin", n, 8)
    tb := __vm_ffi_buf("anim_skin", a)
    pb := __vm_ffi_buf("anim_skin", b)
    ob := __vm_ffi_buf("anim_skin", c)
    nn := __vm_ffi_int("anim_skin", d, "le nombre de nœuds")
    wb := __vm_ffi_buf("anim_skin", e)
    __vm_ffi_range("anim_skin", tb, 0, nn * 80)
    __vm_ffi_range("anim_skin", pb, 0, nn * 8)
    __vm_ffi_range("anim_skin", ob, 0, nn * 8)
    __vm_ffi_range("anim_skin", wb, 0, nn * 128)
    pt := __load64(tb)
    pp := __load64(pb)
    po := __load64(ob)
    pw := __load64(wb)
    tmp := __alloc_raw(384)
    k := 0
    while k < nn:
        i := __load64(po + 8 * k)
        if i < 0 or i >= nn:
            __vm_ffi_argfail("anim_skin", "ordre des nœuds invalide")
        par := __load64(pp + 8 * i)
        if par < 0:
            __vm_m4_trs(pt + 80 * i, pw + 128 * i)
        else:
            __vm_m4_trs(pt + 80 * i, tmp)
            __vm_m4_mul(pw + 128 * par, tmp, pw + 128 * i)
        k += 1
    if f == 0:
        return 0
    jb := __vm_ffi_buf("anim_skin", f)
    ib := __vm_ffi_buf("anim_skin", g)
    outb := __vm_ffi_buf("anim_skin", h)
    __vm_ffi_range("anim_skin", jb, 0, 16)
    pj := __load64(jb)
    nj := __load64(pj)
    __vm_ffi_range("anim_skin", jb, 0, 16 + 8 * nj)
    __vm_ffi_range("anim_skin", ib, 0, nj * 128)
    __vm_ffi_range("anim_skin", outb, 0, nj * 64)
    pi := __load64(ib)
    pout := __load64(outb)
    mesh := __load64(pj + 8)
    inv := tmp + 128
    if mesh >= 0 and mesh < nn:
        __vm_m4_inv_affine(pw + 128 * mesh, inv)
    j := 0
    while j < nj:
        node := __load64(pj + 16 + 8 * j)
        if node < 0 or node >= nn:
            __vm_ffi_argfail("anim_skin", "os hors des nœuds")
        __vm_m4_mul(pw + 128 * node, pi + 128 * j, tmp)
        if mesh >= 0 and mesh < nn:
            __vm_m4_mul(inv, tmp, tmp + 128 + 128)
        q := 0
        while q < 16:
            v := __vm_imd_ld(tmp, q)
            if mesh >= 0 and mesh < nn:
                v = __vm_imd_ld(tmp + 256, q)
            __store32(pout + 64 * j + 4 * q, __nat_f32_bits(v))
            q += 1
        j += 1
    return 0

# ---- Échantillonnage et mélange des clips (stdlib animation) -----------------------------------------------------
# Clip (flottants 64 bits) : [nombre de canaux] puis 8 valeurs par canal [nœud, chemin (0 t, 1 r, 2 s), composantes,
# interpolation (0 STEP, 1 LINEAR, 2 CUBICSPLINE), clés, début des temps, début des valeurs, dernière clé], puis les
# données. Accumulateur : 18 flottants par nœud [10 sommes, poids t / r / s, quaternion de référence (4), drapeau].

func __vm_sin(x: float) -> float:
    # x dans [-pi, pi] : série de Taylor jusqu'à x^19
    x2 := x * x
    term := x
    s := x
    k := 1
    while k < 10:
        term = 0.0 - term * x2 / __i2f((2 * k) * (2 * k + 1))
        s = s + term
        k += 1
    return s

func __vm_cos(x: float) -> float:
    x2 := x * x
    term := 1.0
    s := 1.0
    k := 1
    while k < 10:
        term = 0.0 - term * x2 / __i2f((2 * k - 1) * (2 * k))
        s = s + term
        k += 1
    return s

# acos(d) pour d dans [0, 1) (méthode de Newton sur cos).
func __vm_acos01(d: float) -> float:
    th := 1.5707963267948966 * (1.0 - d)
    if d > 0.5:
        th = __fsqrt(2.0 * (1.0 - d)) * (1.0 + (1.0 - d) / 12.0)
    k := 0
    while k < 6:
        sn := __vm_sin(th)
        if sn < 1.0e-12:
            return th
        th = th + (__vm_cos(th) - d) / sn
        k += 1
    return th

func __an_ld(p: int, i: int) -> float:
    return __bits2f(__load64(p + 8 * i))

func __an_st(p: int, i: int, v: float):
    __store64(p + 8 * i, __f2bits(v))

# Valeur d'un canal du clip (en-tête h) à l'instant t, écrite dans v (nc flottants).
func __an_value(pc: int, h: int, t: float, v: int):
    path := __f2i(__an_ld(pc, h + 1))
    nc := __f2i(__an_ld(pc, h + 2))
    interp := __f2i(__an_ld(pc, h + 3))
    nk := __f2i(__an_ld(pc, h + 4))
    to := __f2i(__an_ld(pc, h + 5))
    vo := __f2i(__an_ld(pc, h + 6))
    stride := nc
    voff := 0
    if interp == 2:
        stride = 3 * nc
        voff = nc
    if nk == 1 or t <= __an_ld(pc, to):
        q := 0
        while q < nc:
            __an_st(v, q, __an_ld(pc, vo + voff + q))
            q += 1
    elif t >= __an_ld(pc, to + nk - 1):
        q := 0
        while q < nc:
            __an_st(v, q, __an_ld(pc, vo + (nk - 1) * stride + voff + q))
            q += 1
    else:
        i := __f2i(__an_ld(pc, h + 7))
        if i < 0 or i >= nk - 1 or not (__an_ld(pc, to + i) <= t and t < __an_ld(pc, to + i + 1)):
            lo := 0
            hi := nk - 1
            while hi - lo > 1:
                mid := (lo + hi) / 2
                mi := __f2i(mid)
                if __an_ld(pc, to + mi) <= t:
                    lo = mi
                else:
                    hi = mi
            i = lo
            __an_st(pc, h + 7, __i2f(i))
        t0 := __an_ld(pc, to + i)
        t1 := __an_ld(pc, to + i + 1)
        dt := t1 - t0
        u := (t - t0) / dt
        a0 := vo + i * stride
        b0 := vo + (i + 1) * stride
        if interp == 0:
            q := 0
            while q < nc:
                __an_st(v, q, __an_ld(pc, a0 + q))
                q += 1
        elif interp == 2:
            u2 := u * u
            u3 := u2 * u
            h00 := 2.0 * u3 - 3.0 * u2 + 1.0
            h10 := u3 - 2.0 * u2 + u
            h01 := 3.0 * u2 - 2.0 * u3
            h11 := u3 - u2
            q := 0
            while q < nc:
                p0 := __an_ld(pc, a0 + nc + q)
                m0 := __an_ld(pc, a0 + 2 * nc + q)
                p1 := __an_ld(pc, b0 + nc + q)
                m1 := __an_ld(pc, b0 + q)
                __an_st(v, q, h00 * p0 + h10 * dt * m0 + h01 * p1 + h11 * dt * m1)
                q += 1
        elif path == 1 and nc == 4:
            x0 := __an_ld(pc, a0)
            y0 := __an_ld(pc, a0 + 1)
            z0 := __an_ld(pc, a0 + 2)
            w0 := __an_ld(pc, a0 + 3)
            x1 := __an_ld(pc, b0)
            y1 := __an_ld(pc, b0 + 1)
            z1 := __an_ld(pc, b0 + 2)
            w1 := __an_ld(pc, b0 + 3)
            dd := x0 * x1 + y0 * y1 + z0 * z1 + w0 * w1
            if dd < 0.0:
                dd = 0.0 - dd
                x1 = 0.0 - x1
                y1 = 0.0 - y1
                z1 = 0.0 - z1
                w1 = 0.0 - w1
            ka := 1.0 - u
            kb := u
            if dd < 0.9995:
                th := __vm_acos01(dd)
                sn := __vm_sin(th)
                ka = __vm_sin((1.0 - u) * th) / sn
                kb = __vm_sin(u * th) / sn
            __an_st(v, 0, x0 * ka + x1 * kb)
            __an_st(v, 1, y0 * ka + y1 * kb)
            __an_st(v, 2, z0 * ka + z1 * kb)
            __an_st(v, 3, w0 * ka + w1 * kb)
        else:
            q := 0
            while q < nc:
                x := __an_ld(pc, a0 + q)
                __an_st(v, q, x + (__an_ld(pc, b0 + q) - x) * u)
                q += 1

# Contrôle d'un canal : rend le nœud.
func __an_check(pc: int, h: int, csz: int, asz: int, per: int) -> int:
    node := __f2i(__an_ld(pc, h))
    nc := __f2i(__an_ld(pc, h + 2))
    interp := __f2i(__an_ld(pc, h + 3))
    nk := __f2i(__an_ld(pc, h + 4))
    to := __f2i(__an_ld(pc, h + 5))
    vo := __f2i(__an_ld(pc, h + 6))
    stride := nc
    if interp == 2:
        stride = 3 * nc
    if node < 0 or per * node + per > asz or nk < 1 or nc < 1 or nc > 4 or vo + nk * stride > csz or to + nk > csz:
        __vm_ffi_argfail("anim", "clip invalide")
    return node

func __vm_nat__native_ffi__anim_sample(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("anim_sample", n, 5)
    cb := __vm_ffi_buf("anim_sample", a)
    t := __vm_ffi_number("anim_sample", b, "le temps")
    w0 := __vm_ffi_number("anim_sample", c, "le poids")
    ab := __vm_ffi_buf("anim_sample", d)
    pm := 0
    if e != 0:
        mb := __vm_ffi_buf("anim_sample", e)
        pm = __load64(mb)
    pc := __load64(cb)
    pa := __load64(ab)
    csz := __f2i(__load64(cb + 8) / 8)
    asz := __f2i(__load64(ab + 8) / 8)
    nch := __f2i(__an_ld(pc, 0))
    v := __alloc_raw(64)
    ch := 0
    while ch < nch:
        h := 1 + 8 * ch
        node := __an_check(pc, h, csz, asz, 18)
        path := __f2i(__an_ld(pc, h + 1))
        nc := __f2i(__an_ld(pc, h + 2))
        w := w0
        if pm != 0:
            w = w0 * __an_ld(pm, node)
        if w <= 0.0:
            ch += 1
            continue
        __an_value(pc, h, t, v)
        if path == 1:
            # normalisation puis accumulation alignée sur le quaternion de référence
            l := __fsqrt(__an_ld(v, 0) * __an_ld(v, 0) + __an_ld(v, 1) * __an_ld(v, 1) + __an_ld(v, 2) * __an_ld(v, 2) + __an_ld(v, 3) * __an_ld(v, 3))
            if l < 1.0e-12:
                l = 1.0
            base := 18 * node
            if __an_ld(pa, base + 17) == 0.0:
                q := 0
                while q < 4:
                    __an_st(pa, base + 13 + q, __an_ld(v, q) / l)
                    q += 1
                __an_st(pa, base + 17, 1.0)
            dot := 0.0
            q := 0
            while q < 4:
                dot = dot + __an_ld(v, q) * __an_ld(pa, base + 13 + q)
                q += 1
            f := w / l
            if dot < 0.0:
                f = 0.0 - f
            q = 0
            while q < 4:
                __an_st(pa, base + 3 + q, __an_ld(pa, base + 3 + q) + __an_ld(v, q) * f)
                q += 1
            __an_st(pa, base + 11, __an_ld(pa, base + 11) + w)
        else:
            base := 18 * node
            off := 0
            tot := 10
            if path == 2:
                off = 7
                tot = 12
            q := 0
            while q < 3 and q < nc:
                __an_st(pa, base + off + q, __an_ld(pa, base + off + q) + __an_ld(v, q) * w)
                q += 1
            __an_st(pa, base + tot, __an_ld(pa, base + tot) + w)
        ch += 1
    return 0

func __an_qmul(ax: float, ay: float, az: float, aw: float, bx: float, by: float, bz: float, bw: float, r: int):
    __an_st(r, 0, aw * bx + ax * bw + ay * bz - az * by)
    __an_st(r, 1, aw * by - ax * bz + ay * bw + az * bx)
    __an_st(r, 2, aw * bz + ax * by - ay * bx + az * bw)
    __an_st(r, 3, aw * bw - ax * bx - ay * by - az * bz)

# Piste ADDITIVE : la différence entre le clip à l'instant t et sa pose de référence (instant ref) est ajoutée à la
# pose `trs` (10 flottants par nœud), avec le poids w et le masque facultatif (un flottant par nœud).
func __vm_nat__native_ffi__anim_additive(n: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    __nat_exact("anim_additive", n, 6)
    cb := __vm_ffi_buf("anim_additive", a)
    t := __vm_ffi_number("anim_additive", b, "le temps")
    w0 := __vm_ffi_number("anim_additive", c, "le poids")
    tb := __vm_ffi_buf("anim_additive", d)
    rt := __vm_ffi_number("anim_additive", e, "le temps de référence")
    pm := 0
    if f != 0:
        pm = __load64(__vm_ffi_buf("anim_additive", f))
    pc := __load64(cb)
    pt := __load64(tb)
    csz := __f2i(__load64(cb + 8) / 8)
    tsz := __f2i(__load64(tb + 8) / 8)
    nch := __f2i(__an_ld(pc, 0))
    v := __alloc_raw(64)
    r := __alloc_raw(64)
    q := __alloc_raw(64)
    ch := 0
    while ch < nch:
        h := 1 + 8 * ch
        node := __an_check(pc, h, csz, tsz, 10)
        path := __f2i(__an_ld(pc, h + 1))
        w := w0
        if pm != 0:
            w = w0 * __an_ld(pm, node)
        if w != 0.0:
            __an_value(pc, h, t, v)
            __an_value(pc, h, rt, r)
            o := 10 * node
            if path == 0:
                k := 0
                while k < 3:
                    __an_st(pt, o + k, __an_ld(pt, o + k) + (__an_ld(v, k) - __an_ld(r, k)) * w)
                    k += 1
            elif path == 2:
                k := 0
                while k < 3:
                    rv := __an_ld(r, k)
                    ratio := 1.0
                    if rv != 0.0:
                        ratio = __an_ld(v, k) / rv
                    __an_st(pt, o + 7 + k, __an_ld(pt, o + 7 + k) * (1.0 + (ratio - 1.0) * w))
                    k += 1
            else:
                # delta = conj(ref) * valeur, réduit par le poids (nlerp depuis l'identité), appliqué localement
                __an_qmul(0.0 - __an_ld(r, 0), 0.0 - __an_ld(r, 1), 0.0 - __an_ld(r, 2), __an_ld(r, 3), __an_ld(v, 0), __an_ld(v, 1), __an_ld(v, 2), __an_ld(v, 3), q)
                dx := __an_ld(q, 0) * w
                dy := __an_ld(q, 1) * w
                dz := __an_ld(q, 2) * w
                dw := __an_ld(q, 3)
                if dw < 0.0:
                    dx = 0.0 - dx
                    dy = 0.0 - dy
                    dz = 0.0 - dz
                    dw = 0.0 - dw
                dw = 1.0 - w + dw * w
                l := __fsqrt(dx * dx + dy * dy + dz * dz + dw * dw)
                if l < 1.0e-12:
                    l = 1.0
                __an_qmul(__an_ld(pt, o + 3), __an_ld(pt, o + 4), __an_ld(pt, o + 5), __an_ld(pt, o + 6), dx / l, dy / l, dz / l, dw / l, q)
                l2 := __fsqrt(__an_ld(q, 0) * __an_ld(q, 0) + __an_ld(q, 1) * __an_ld(q, 1) + __an_ld(q, 2) * __an_ld(q, 2) + __an_ld(q, 3) * __an_ld(q, 3))
                k := 0
                while k < 4:
                    __an_st(pt, o + 3 + k, __an_ld(q, k) / l2)
                    k += 1
        ch += 1
    return 0

# Orientation Exif (1..8) : copie de l'image RGBA src (l x h) dans dst, tournée / retournée (dst : h x l pour 5..8).
func __vm_nat__native_ffi__img_orient(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("img_orient", n, 5)
    sb := __vm_ffi_buf("img_orient", a)
    db := __vm_ffi_buf("img_orient", b)
    w := __vm_ffi_int("img_orient", c, "la largeur")
    h := __vm_ffi_int("img_orient", d, "la hauteur")
    o := __vm_ffi_int("img_orient", e, "l'orientation")
    __vm_ffi_range("img_orient", sb, 0, w * h * 4)
    __vm_ffi_range("img_orient", db, 0, w * h * 4)
    ps := __load64(sb)
    pd := __load64(db)
    dw := w
    if o >= 5:
        dw = h
    y := 0
    while y < h:
        x := 0
        while x < w:
            tx := x
            ty := y
            if o == 2:
                tx = w - 1 - x
            elif o == 3:
                tx = w - 1 - x
                ty = h - 1 - y
            elif o == 4:
                ty = h - 1 - y
            elif o == 5:
                tx = y
                ty = x
            elif o == 6:
                tx = h - 1 - y
                ty = x
            elif o == 7:
                tx = h - 1 - y
                ty = w - 1 - x
            elif o == 8:
                tx = y
                ty = w - 1 - x
            __store32(pd + 4 * (ty * dw + tx), __load32(ps + 4 * (y * w + x)))
            x += 1
        y += 1
    return 0

# Pose finale : chaque canal accumulé (poids ramenés à 1 au-delà, complétés par la pose de repos en dessous).
func __vm_nat__native_ffi__anim_resolve(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("anim_resolve", n, 4)
    ab := __vm_ffi_buf("anim_resolve", a)
    rb := __vm_ffi_buf("anim_resolve", b)
    ob := __vm_ffi_buf("anim_resolve", c)
    nn := __vm_ffi_int("anim_resolve", d, "le nombre de nœuds")
    __vm_ffi_range("anim_resolve", ab, 0, nn * 144)
    __vm_ffi_range("anim_resolve", rb, 0, nn * 80)
    __vm_ffi_range("anim_resolve", ob, 0, nn * 80)
    pa := __load64(ab)
    pr := __load64(rb)
    po := __load64(ob)
    k := 0
    while k < nn:
        base := 18 * k
        o := 10 * k
        # translation et échelle
        g := 0
        while g < 2:
            off := 0
            tot := __an_ld(pa, base + 10)
            if g == 1:
                off = 7
                tot = __an_ld(pa, base + 12)
            q := 0
            while q < 3:
                r := __an_ld(pr, o + off + q)
                if tot <= 0.0:
                    __an_st(po, o + off + q, r)
                else:
                    nrm := tot
                    if nrm < 1.0:
                        nrm = 1.0
                    x := __an_ld(pa, base + off + q) / nrm
                    if tot < 1.0:
                        x = x + r * (1.0 - tot)
                    __an_st(po, o + off + q, x)
                q += 1
            g += 1
        tr := __an_ld(pa, base + 11)
        if tr <= 0.0:
            q := 0
            while q < 4:
                __an_st(po, o + 3 + q, __an_ld(pr, o + 3 + q))
                q += 1
        else:
            nrm := tr
            if nrm < 1.0:
                nrm = 1.0
            x := __an_ld(pa, base + 3) / nrm
            y := __an_ld(pa, base + 4) / nrm
            z := __an_ld(pa, base + 5) / nrm
            w := __an_ld(pa, base + 6) / nrm
            if tr < 1.0:
                rx := __an_ld(pr, o + 3)
                ry := __an_ld(pr, o + 4)
                rz := __an_ld(pr, o + 5)
                rw := __an_ld(pr, o + 6)
                f := 1.0 - tr
                if rx * __an_ld(pa, base + 13) + ry * __an_ld(pa, base + 14) + rz * __an_ld(pa, base + 15) + rw * __an_ld(pa, base + 16) < 0.0:
                    f = 0.0 - f
                x = x + rx * f
                y = y + ry * f
                z = z + rz * f
                w = w + rw * f
            l := __fsqrt(x * x + y * y + z * z + w * w)
            if l < 1.0e-12:
                l = 1.0
            __an_st(po, o + 3, x / l)
            __an_st(po, o + 4, y / l)
            __an_st(po, o + 5, z / l)
            __an_st(po, o + 6, w / l)
        k += 1
    return 0

# ---- JPEG (multimedia.image.jpeg) : IDCT 8x8 et conversion YCbCr -> RGBA en code natif ------------------------------

# coef : 64 entiers 32 bits par bloc (ordre naturel, déquantifiés) ; tab : 64 flottants c[x * 8 + u] ; les blocs
# (nb au total, bw par ligne) sont écrits dans le plan d'octets `out` de pas `stride`.
func __vm_nat__native_ffi__jpeg_idct(n: int, a: int, b: int, c: int, d: int, e: int, f: int, g: int, hh: int) -> int:
    __nat_exact("jpeg_idct", n, 8)
    prec := __vm_ffi_int("jpeg_idct", hh, "la précision")
    shift := 128.5
    maxv := 255
    if prec == 12:
        shift = 2048.5
        maxv = 4095
    cb := __vm_ffi_buf("jpeg_idct", a)
    nb := __vm_ffi_int("jpeg_idct", b, "le nombre de blocs")
    ob := __vm_ffi_buf("jpeg_idct", c)
    bw := __vm_ffi_int("jpeg_idct", d, "les blocs par ligne")
    stride := __vm_ffi_int("jpeg_idct", e, "le pas")
    tb := __vm_ffi_buf("jpeg_idct", f)
    qb := __vm_ffi_buf("jpeg_idct", g)
    __vm_ffi_range("jpeg_idct", qb, 0, 256)
    pq := __load64(qb)
    __vm_ffi_range("jpeg_idct", cb, 0, nb * 256)
    __vm_ffi_range("jpeg_idct", tb, 0, 512)
    if bw < 1 or stride < bw * 8:
        __vm_ffi_argfail("jpeg_idct", "dimensions invalides")
    rows := (nb + bw - 1) / bw
    __vm_ffi_range("jpeg_idct", ob, 0, __f2i(rows) * 8 * stride)
    pc := __load64(cb)
    po := __load64(ob)
    pt := __load64(tb)
    tmp := __alloc_raw(512)
    k := 0
    while k < nb:
        p := pc + 256 * k
        # lignes : tmp[y][x] = somme_u c[x][u] * F[y][u]
        y := 0
        while y < 8:
            x := 0
            while x < 8:
                s := 0.0
                u := 0
                while u < 8:
                    cv := __load32(p + 4 * (y * 8 + u))
                    if cv != 0:
                        if cv >= 2147483648:
                            cv = cv - 4294967296
                        s = s + __vm_imd_ld(pt, x * 8 + u) * __i2f(cv * __load32(pq + 4 * (y * 8 + u)))
                    u += 1
                __vm_imd_st(tmp, y * 8 + x, s)
                x += 1
            y += 1
        bx := (k % bw) * 8
        by := (k / bw)
        by8 := __f2i(by) * 8
        x2 := 0
        while x2 < 8:
            y2 := 0
            while y2 < 8:
                s := 0.0
                v := 0
                while v < 8:
                    s = s + __vm_imd_ld(pt, y2 * 8 + v) * __vm_imd_ld(tmp, v * 8 + x2)
                    v += 1
                val := __f2i(s + shift)
                if s + shift < 0.0:
                    val = 0
                if val > maxv:
                    val = maxv
                if prec == 12:
                    val = val >> 4
                __store8(po + (by8 + y2) * stride + bx + x2, val)
                y2 += 1
            x2 += 1
        k += 1
    return 0

func __vm_jpg_clamp(x: float) -> int:
    if x < 0.0:
        return 0
    if x > 255.0:
        return 255
    return __f2i(x + 0.5)

# Échantillon de chrominance interpolé (bilinéaire, centres alignés comme le « fancy upsampling » de libjpeg).
func __vm_jpg_sample(p: int, stride: int, size: int, x: int, y: int, hc: int, vc: int, hm: int, vm: int) -> float:
    if hc == hm and vc == vm:
        i := y * stride + x
        if i < size:
            return __i2f(__load8(p + i))
        return 128.0
    fx := (__i2f(x) + 0.5) * __i2f(hc) / __i2f(hm) - 0.5
    fy := (__i2f(y) + 0.5) * __i2f(vc) / __i2f(vm) - 0.5
    if fx < 0.0:
        fx = 0.0
    if fy < 0.0:
        fy = 0.0
    x0 := __f2i(fx)
    y0 := __f2i(fy)
    tx := fx - __i2f(x0)
    ty := fy - __i2f(y0)
    rows := size / stride
    maxx := stride - 1
    maxy := __f2i(rows) - 1
    x1 := x0 + 1
    y1 := y0 + 1
    if x1 > maxx:
        x1 = maxx
    if y1 > maxy:
        y1 = maxy
    if x0 > maxx:
        x0 = maxx
    if y0 > maxy:
        y0 = maxy
    a := __i2f(__load8(p + y0 * stride + x0))
    b := __i2f(__load8(p + y0 * stride + x1))
    c := __i2f(__load8(p + y1 * stride + x0))
    d := __i2f(__load8(p + y1 * stride + x1))
    top := a + (b - a) * tx
    bot := c + (d - c) * tx
    return top + (bot - top) * ty

# ---- Décodage entropique JPEG (Huffman, séquentiel et progressif) --------------------------------------------------
# État du lecteur st : [0] position [8] fin [16] accumulateur [24] bits disponibles [32] fin de bloc progressive
# (EOBRUN) [40] adresse des données. Table de Huffman (entiers 32 bits) : [0..512) rapide (longueur << 16 | symbole,
# ou -1), [512..530) maxcode, [530..548) valptr, [548..566) mincode, [566..822) symboles.
func __jpg_fill(st: int):
    pos := __load64(st)
    end := __load64(st + 8)
    acc := __load64(st + 16)
    cnt := __load64(st + 24)
    d := __load64(st + 40)
    while cnt <= 48:
        b := 0
        if pos < end:
            b = __load8(d + pos)
            if b == 255:
                nx := 0
                if pos + 1 < end:
                    nx = __load8(d + pos + 1)
                if nx == 0:
                    pos += 2
                else:
                    b = 0
            else:
                pos += 1
        acc = (acc << 8) | b
        cnt += 8
    __store64(st, pos)
    __store64(st + 16, acc & 72057594037927935)
    __store64(st + 24, cnt)

func __jpg_bits(st: int, n: int) -> int:
    if n == 0:
        return 0
    if __load64(st + 24) < n:
        __jpg_fill(st)
    cnt := __load64(st + 24) - n
    __store64(st + 24, cnt)
    return (__load64(st + 16) >> cnt) & ((1 << n) - 1)

func __jpg_extend(v: int, s: int) -> int:
    if s == 0:
        return 0
    if v < (1 << (s - 1)):
        return v - (1 << s) + 1
    return v

func __jpg_decode(st: int, t: int) -> int:
    if __load64(st + 24) < 16:
        __jpg_fill(st)
    cnt := __load64(st + 24)
    acc := __load64(st + 16)
    look := (acc >> (cnt - 9)) & 511
    e := __load32(t + 4 * look)
    if e != 4294967295:
        __store64(st + 24, cnt - (e >> 16))
        return e & 65535
    code := look
    l := 9
    cnt -= 9
    while l < 16:
        cnt -= 1
        code = (code << 1) | ((acc >> cnt) & 1)
        l += 1
        mx := __load32(t + 4 * (512 + l))
        if mx != 4294967295 and code <= mx:
            __store64(st + 24, cnt)
            return __load32(t + 4 * (566 + __load32(t + 4 * (530 + l)) + code - __load32(t + 4 * (548 + l))))
    __store64(st + 24, cnt)
    return 0

func __jpg_get(c: int, i: int) -> int:
    v := __load32(c + 4 * i)
    if v >= 2147483648:
        return v - 4294967296
    return v

func __jpg_set(c: int, i: int, v: int):
    __store32(c + 4 * i, v & 4294967295)

# Un bloc. zz : table zigzag (64 entiers 32 bits) ; cm : fiche de la composante (entiers 64 bits) [coef, dc, ac,
# prédicteur DC, ...].
func __jpg_block(st: int, cm: int, bi: int, zz: int, tabs: int, prog: int, ss: int, se: int, ah: int, al: int):
    co := __load64(cm) + 256 * bi
    dct := tabs + 3288 * __load64(cm + 8)
    act := tabs + 3288 * (4 + __load64(cm + 16))
    if prog == 0:
        t := __jpg_decode(st, dct)
        pred := __load64(cm + 24) + __jpg_extend(__jpg_bits(st, t), t)
        __store64(cm + 24, pred)
        __jpg_set(co, 0, pred)
        k := 1
        while k < 64:
            rs := __jpg_decode(st, act)
            r := rs >> 4
            sz := rs & 15
            if sz == 0:
                if r != 15:
                    return
                k += 16
            else:
                k += r
                if k > 63:
                    return
                __jpg_set(co, __load32(zz + 4 * k), __jpg_extend(__jpg_bits(st, sz), sz))
                k += 1
        return
    if ss == 0:
        if ah == 0:
            t := __jpg_decode(st, dct)
            pred := __load64(cm + 24) + __jpg_extend(__jpg_bits(st, t), t)
            __store64(cm + 24, pred)
            __jpg_set(co, 0, pred << al)
        elif __jpg_bits(st, 1) == 1:
            __jpg_set(co, 0, __jpg_get(co, 0) | (1 << al))
        return
    if ah == 0:
        eob := __load64(st + 32)
        if eob > 0:
            __store64(st + 32, eob - 1)
            return
        k := ss
        while k <= se:
            rs := __jpg_decode(st, act)
            r := rs >> 4
            sz := rs & 15
            if sz == 0:
                if r < 15:
                    eob = (1 << r) - 1
                    if r > 0:
                        eob += __jpg_bits(st, r)
                    __store64(st + 32, eob)
                    return
                k += 16
            else:
                k += r
                if k > 63:
                    return
                __jpg_set(co, __load32(zz + 4 * k), __jpg_extend(__jpg_bits(st, sz), sz) * (1 << al))
                k += 1
        return
    p1 := 1 << al
    m1 := 0 - p1
    k := ss
    eob := __load64(st + 32)
    if eob <= 0:
        while k <= se:
            rs := __jpg_decode(st, act)
            r := rs >> 4
            sz := rs & 15
            val := 0
            stop := false
            if sz == 0:
                if r < 15:
                    eob = 1 << r
                    if r > 0:
                        eob += __jpg_bits(st, r)
                    stop = true
            else:
                val = m1
                if __jpg_bits(st, 1) == 1:
                    val = p1
            if stop:
                break
            while k <= se:
                z := __load32(zz + 4 * k)
                cv := __jpg_get(co, z)
                if cv != 0:
                    if __jpg_bits(st, 1) == 1 and (cv & p1) == 0:
                        if cv >= 0:
                            __jpg_set(co, z, cv + p1)
                        else:
                            __jpg_set(co, z, cv + m1)
                else:
                    if r == 0:
                        if val != 0:
                            __jpg_set(co, z, val)
                        k += 1
                        break
                    r -= 1
                k += 1
    if eob > 0:
        while k <= se:
            z := __load32(zz + 4 * k)
            cv := __jpg_get(co, z)
            if cv != 0:
                if __jpg_bits(st, 1) == 1 and (cv & p1) == 0:
                    if cv >= 0:
                        __jpg_set(co, z, cv + p1)
                    else:
                        __jpg_set(co, z, cv + m1)
            k += 1
        eob -= 1
    __store64(st + 32, eob)

# ---- Décodage arithmétique (T.81 annexe D, comme jdarith.c) ----------------------------------------------------------
# Espace de travail ar (octets) : [0..912) table Qe (114 entiers 64 bits : Qe << 16 | MPS suivant << 8 | bascule << 7 |
# LPS suivant), [1024..1280) statistiques DC (4 x 64), [1280..2304) statistiques AC (4 x 256), [2304..2400) L[4], U[4],
# K[4] (entiers 64 bits), [2400..2432) contexte DC par composante, [2432] case fixe (état 113).
# État st (en plus du lecteur Huffman) : [48] c, [56] a, [64] ct, [72] marqueur rencontré.
func __jar_byte(st: int) -> int:
    if __load64(st + 72) != 0:
        return 0
    pos := __load64(st)
    end := __load64(st + 8)
    d := __load64(st + 40)
    if pos >= end:
        return 0
    b := __load8(d + pos)
    if b != 255:
        __store64(st, pos + 1)
        return b
    q := pos + 1
    while q < end and __load8(d + q) == 255:
        q += 1
    if q < end and __load8(d + q) == 0:
        __store64(st, q + 1)
        return 255
    # marqueur : ne pas le consommer
    __store64(st + 72, 1)
    __store64(st, pos)
    return 0

func __jar_reset(st: int, ar: int):
    __store64(st + 48, 0)
    __store64(st + 56, 0)
    __store64(st + 64, 0 - 16)
    __store64(st + 72, 0)
    i := 1024
    while i < 2304:
        __store64(ar + i, 0)
        i += 8
    i = 2400
    while i < 2432:
        __store64(ar + i, 0)
        i += 8
    __store8(ar + 2432, 113)

func __jar_decode(st: int, ar: int, sp: int) -> int:
    c := __load64(st + 48)
    a := __load64(st + 56)
    ct := __load64(st + 64)
    while a < 32768:
        ct -= 1
        if ct < 0:
            c = ((c << 8) | __jar_byte(st)) & 1152921504606846975
            ct += 8
            if ct < 0:
                ct += 1
                if ct == 0:
                    a = 32768
        a = a << 1
    sv := __load8(sp)
    qe := __load64(ar + 8 * (sv & 127))
    nl := qe & 255
    qe = qe >> 8
    nm := qe & 255
    qe = qe >> 8
    temp := a - qe
    a = temp
    temp = temp << ct
    if c >= temp:
        c -= temp
        if a < qe:
            a = qe
            __store8(sp, (sv & 128) ^ nm)
        else:
            a = qe
            __store8(sp, (sv & 128) ^ nl)
            sv = sv ^ 128
    elif a < 32768:
        if a < qe:
            __store8(sp, (sv & 128) ^ nl)
            sv = sv ^ 128
        else:
            __store8(sp, (sv & 128) ^ nm)
    __store64(st + 48, c)
    __store64(st + 56, a)
    __store64(st + 64, ct)
    return sv >> 7

# Différence DC (F.1.4.4.1) ; q : indice de la composante dans le balayage, tb : table DC.
func __jar_dc(st: int, ar: int, q: int, tb: int) -> int:
    base := ar + 1024 + 64 * tb
    ctx := __load64(ar + 2400 + 8 * q)
    sp := base + ctx
    if __jar_decode(st, ar, sp) == 0:
        __store64(ar + 2400 + 8 * q, 0)
        return 0
    sign := __jar_decode(st, ar, sp + 1)
    sp = sp + 2 + sign
    m := __jar_decode(st, ar, sp)
    if m != 0:
        sp = base + 20
        while __jar_decode(st, ar, sp) != 0:
            m = m << 1
            if m == 32768:
                return 0
            sp += 1
    lo := (1 << __load64(ar + 2304 + 8 * tb)) >> 1
    hi := (1 << __load64(ar + 2336 + 8 * tb)) >> 1
    if m < lo:
        __store64(ar + 2400 + 8 * q, 0)
    elif m > hi:
        __store64(ar + 2400 + 8 * q, 12 + sign * 4)
    else:
        __store64(ar + 2400 + 8 * q, 4 + sign * 4)
    v := m
    sp += 14
    m = m >> 1
    while m != 0:
        if __jar_decode(st, ar, sp) != 0:
            v = v | m
        m = m >> 1
    v += 1
    if sign != 0:
        v = 0 - v
    return v

# Valeur AC non nulle à la position k (F.1.4.4.2), sp pointant sur la statistique « 3 (k - 1) ».
func __jar_acval(st: int, ar: int, sp: int, ta: int, k: int) -> int:
    sign := __jar_decode(st, ar, ar + 2432)
    sp += 2
    m := __jar_decode(st, ar, sp)
    if m != 0:
        if __jar_decode(st, ar, sp) != 0:
            m = m << 1
            if k <= __load64(ar + 2368 + 8 * ta):
                sp = ar + 1280 + 256 * ta + 189
            else:
                sp = ar + 1280 + 256 * ta + 217
            while __jar_decode(st, ar, sp) != 0:
                m = m << 1
                if m == 32768:
                    return 0
                sp += 1
    v := m
    sp += 14
    m = m >> 1
    while m != 0:
        if __jar_decode(st, ar, sp) != 0:
            v = v | m
        m = m >> 1
    v += 1
    if sign != 0:
        v = 0 - v
    return v

func __jar_block(st: int, cm: int, q: int, bi: int, zz: int, ar: int, prog: int, ss: int, se: int, ah: int, al: int):
    co := __load64(cm) + 256 * bi
    td := __load64(cm + 8)
    ta := __load64(cm + 16)
    if prog == 0 or ss == 0:
        if prog != 0 and ah != 0:
            if __jar_decode(st, ar, ar + 2432) != 0:
                __jpg_set(co, 0, __jpg_get(co, 0) | (1 << al))
            return
        pred := __load64(cm + 24) + __jar_dc(st, ar, q, td)
        pred = pred & 65535
        if pred >= 32768:
            pred -= 65536
        __store64(cm + 24, pred)
        if prog != 0:
            __jpg_set(co, 0, pred << al)
            return
        __jpg_set(co, 0, pred)
        ss = 1
        se = 63
    act := ar + 1280 + 256 * ta
    if prog == 0 or ah == 0:
        k := ss
        while k <= se:
            sp := act + 3 * (k - 1)
            if __jar_decode(st, ar, sp) != 0:
                return
            while __jar_decode(st, ar, sp + 1) == 0:
                sp += 3
                k += 1
                if k > se:
                    return
            v := __jar_acval(st, ar, sp, ta, k)
            __jpg_set(co, __load32(zz + 4 * k), v * (1 << al))
            k += 1
        return
    # raffinement AC (G.1.3.3)
    p1 := 1 << al
    m1 := 0 - p1
    kex := se
    while kex > 0:
        if __jpg_get(co, __load32(zz + 4 * kex)) != 0:
            break
        kex -= 1
    k := ss
    while k <= se:
        sp := act + 3 * (k - 1)
        if k > kex:
            if __jar_decode(st, ar, sp) != 0:
                return
        while true:
            z := __load32(zz + 4 * k)
            cv := __jpg_get(co, z)
            if cv != 0:
                if __jar_decode(st, ar, sp + 2) != 0:
                    if cv < 0:
                        __jpg_set(co, z, cv + m1)
                    else:
                        __jpg_set(co, z, cv + p1)
                break
            if __jar_decode(st, ar, sp + 1) != 0:
                if __jar_decode(st, ar, ar + 2432) != 0:
                    __jpg_set(co, z, m1)
                else:
                    __jpg_set(co, z, p1)
                break
            sp += 3
            k += 1
            if k > se:
                return
        k += 1

# ---- JPEG sans perte (T.81 annexe H, Huffman) -------------------------------------------------------------------------
# Échantillon (x, y) de la composante cm : coef = entiers 32 bits (pas bw), cm + 24 = plan 8 bits de sortie.
# psv : prédicteur, pt : transformation ponctuelle, prec : précision, first : première ligne de l'intervalle RST.
func __jll_sample(st: int, cm: int, x: int, y: int, tabs: int, psv: int, pt: int, prec: int, first: int):
    co := __load64(cm)
    bw := __load64(cm + 32)
    i := y * bw + x
    pred := 0
    if y == first:
        if x == 0:
            pred = 1 << (prec - pt - 1)
        else:
            pred = __jpg_get(co, i - 1)
    elif x == 0:
        pred = __jpg_get(co, i - bw)
    else:
        ra := __jpg_get(co, i - 1)
        rb := __jpg_get(co, i - bw)
        rc := __jpg_get(co, i - bw - 1)
        if psv == 1:
            pred = ra
        elif psv == 2:
            pred = rb
        elif psv == 3:
            pred = rc
        elif psv == 4:
            pred = ra + rb - rc
        elif psv == 5:
            pred = ra + ((rb - rc) >> 1)
        elif psv == 6:
            pred = rb + ((ra - rc) >> 1)
        else:
            pred = (ra + rb) >> 1
    t := __jpg_decode(st, tabs + 3288 * __load64(cm + 8))
    diff := 32768
    if t < 16:
        diff = __jpg_extend(__jpg_bits(st, t), t)
    v := (pred + diff) & 65535
    __jpg_set(co, i, v)
    o := (v << pt) & 65535
    if prec > 8:
        o = o >> (prec - 8)
    elif prec < 8:
        o = __f2i((o * 255) / ((1 << prec) - 1))
    if o > 255:
        o = 255
    __store8(__load64(cm + 24) + i, o)

# Balayage complet. prm (entiers 64 bits) : [nc, ss, se, ah, al, mode, intervalle RST, mcux, mcuy, unités,
# un seul composant, position de départ, taille des données] puis 8 valeurs par composante : [adresse des
# coefficients, table DC, table AC, prédicteur, bw, h, v, blocs par ligne (balayage simple)]. Rend la position de
# fin dans les données. Mode : 0 séquentiel Huffman, 1 progressif Huffman, 2 séquentiel arithmétique, 3 progressif
# arithmétique (c = espace de travail arithmétique), 4 sans perte Huffman (ss = prédicteur, al = transformation
# ponctuelle, ah = précision ; « prédicteur » de la composante = adresse du plan 8 bits, bw = pas en échantillons).
func __vm_nat__native_ffi__jpeg_scan(n: int, a: int, b: int, c: int, d: int) -> int:
    __nat_exact("jpeg_scan", n, 4)
    pb := __vm_ffi_buf("jpeg_scan", a)
    db := __vm_ffi_buf("jpeg_scan", b)
    tb := __vm_ffi_buf("jpeg_scan", c)
    zb := __vm_ffi_buf("jpeg_scan", d)
    __vm_ffi_range("jpeg_scan", pb, 0, 13 * 8 + 4 * 64)
    __vm_ffi_range("jpeg_scan", tb, 0, 26304)
    __vm_ffi_range("jpeg_scan", zb, 0, 256)
    pr := __load64(pb)
    nc := __load64(pr)
    ss := __load64(pr + 8)
    se := __load64(pr + 16)
    ah := __load64(pr + 24)
    al := __load64(pr + 32)
    prog := __load64(pr + 40)
    interval := __load64(pr + 48)
    mcux := __load64(pr + 56)
    total := __load64(pr + 72)
    single := __load64(pr + 80)
    start := __load64(pr + 88)
    size := __load64(pr + 96)
    if size > __load64(db + 8):
        __vm_ffi_argfail("jpeg_scan", "données hors du tampon")
    tabs := __load64(tb)
    zz := __load64(zb)
    st := __alloc_raw(96)
    __store64(st, start)
    __store64(st + 8, size)
    __store64(st + 16, 0)
    __store64(st + 24, 0)
    __store64(st + 32, 0)
    __store64(st + 40, __load64(db))
    mode := prog
    if mode >= 2 and mode <= 3:
        __jar_reset(st, tabs)
        prog = mode - 2
    if interval <= 0:
        interval = total
    first := 0
    done := 0
    while done < total:
        if done > 0 and done % interval == 0:
            # marqueur RST : repartir à l'octet suivant le marqueur
            pos := __load64(st)
            d0 := __load64(st + 40)
            while pos + 1 < size and not (__load8(d0 + pos) == 255 and __load8(d0 + pos + 1) >= 208 and __load8(d0 + pos + 1) <= 215):
                pos += 1
            if pos + 1 < size:
                pos += 2
            __store64(st, pos)
            __store64(st + 16, 0)
            __store64(st + 24, 0)
            __store64(st + 32, 0)
            q := 0
            while q < nc:
                if mode != 4:
                    __store64(pr + 104 + 64 * q + 24, 0)
                q += 1
            if mode >= 2 and mode <= 3:
                __jar_reset(st, tabs)
            first = done
        if mode == 4:
            if single == 1:
                cm := pr + 104
                bpl := __load64(cm + 56)
                lx := done % bpl
                ly := __f2i((done - lx) / bpl)
                __jll_sample(st, cm, lx, ly, tabs, ss, al, ah, __f2i((first - first % bpl) / bpl))
            else:
                mx := done % mcux
                my := __f2i((done - mx) / mcux)
                fr := __f2i((first - first % mcux) / mcux)
                q := 0
                while q < nc:
                    cm := pr + 104 + 64 * q
                    hh := __load64(cm + 40)
                    vv := __load64(cm + 48)
                    v := 0
                    while v < vv:
                        h := 0
                        while h < hh:
                            __jll_sample(st, cm, mx * hh + h, my * vv + v, tabs, ss, al, ah, fr * vv)
                            h += 1
                        v += 1
                    q += 1
        elif mode >= 2:
            if single == 1:
                cm := pr + 104
                bpl := __load64(cm + 56)
                bx := done % bpl
                by := (done - bx) / bpl
                __jar_block(st, cm, 0, __f2i(by) * __load64(cm + 32) + bx, zz, tabs, prog, ss, se, ah, al)
            else:
                mx := done % mcux
                my := __f2i((done - mx) / mcux)
                q := 0
                while q < nc:
                    cm := pr + 104 + 64 * q
                    hh := __load64(cm + 40)
                    vv := __load64(cm + 48)
                    bw := __load64(cm + 32)
                    v := 0
                    while v < vv:
                        h := 0
                        while h < hh:
                            __jar_block(st, cm, q, (my * vv + v) * bw + mx * hh + h, zz, tabs, prog, ss, se, ah, al)
                            h += 1
                        v += 1
                    q += 1
        elif single == 1:
            cm := pr + 104
            bpl := __load64(cm + 56)
            bx := done % bpl
            by := (done - bx) / bpl
            __jpg_block(st, cm, __f2i(by) * __load64(cm + 32) + bx, zz, tabs, prog, ss, se, ah, al)
        else:
            mx := done % mcux
            my := __f2i((done - mx) / mcux)
            q := 0
            while q < nc:
                cm := pr + 104 + 64 * q
                hh := __load64(cm + 40)
                vv := __load64(cm + 48)
                bw := __load64(cm + 32)
                v := 0
                while v < vv:
                    h := 0
                    while h < hh:
                        __jpg_block(st, cm, (my * vv + v) * bw + mx * hh + h, zz, tabs, prog, ss, se, ah, al)
                        h += 1
                    v += 1
                q += 1
        done += 1
    # position du marqueur suivant (les octets déjà mis en réserve ne comptent pas)
    pos := __load64(st)
    d1 := __load64(st + 40)
    while pos + 1 < size and not (__load8(d1 + pos) == 255 and __load8(d1 + pos + 1) != 0 and not (__load8(d1 + pos + 1) >= 208 and __load8(d1 + pos + 1) <= 215)):
        pos += 1
    return __dyn_int(pos)

# Plans Y, Cb, Cr (sous-échantillonnés) -> RGBA. prm (entiers 64 bits) : [composantes (1 ou 3), pasY, pasCb, pasCr,
# hY, vY, hCb, vCb, hCr, vCr, hmax, vmax].
func __vm_nat__native_ffi__jpeg_color(n: int, a: int, b: int, c: int, d: int, e: int, f: int, g: int, hk: int) -> int:
    __nat_exact("jpeg_color", n, 8)
    yb := __vm_ffi_buf("jpeg_color", a)
    cbb := __vm_ffi_buf("jpeg_color", b)
    crb := __vm_ffi_buf("jpeg_color", c)
    ob := __vm_ffi_buf("jpeg_color", d)
    w := __vm_ffi_int("jpeg_color", e, "la largeur")
    h := __vm_ffi_int("jpeg_color", f, "la hauteur")
    prb := __vm_ffi_buf("jpeg_color", g)
    __vm_ffi_range("jpeg_color", prb, 0, 136)
    __vm_ffi_range("jpeg_color", ob, 0, w * h * 4)
    pr := __load64(prb)
    nc := __load64(pr)
    sy := __load64(pr + 8)
    scb := __load64(pr + 16)
    scr := __load64(pr + 24)
    hy := __load64(pr + 32)
    vy := __load64(pr + 40)
    hcb := __load64(pr + 48)
    vcb := __load64(pr + 56)
    hcr := __load64(pr + 64)
    vcr := __load64(pr + 72)
    hm := __load64(pr + 80)
    vm := __load64(pr + 88)
    xform := __load64(pr + 96)
    hkk := __load64(pr + 104)
    vkk := __load64(pr + 112)
    skk := __load64(pr + 120)
    kb := __vm_ffi_buf("jpeg_color", hk)
    pk := __load64(kb)
    ksz := __load64(kb + 8)
    py := __load64(yb)
    pcb := __load64(cbb)
    pcr := __load64(crb)
    po := __load64(ob)
    ysz := __load64(yb + 8)
    cbsz := __load64(cbb + 8)
    crsz := __load64(crb + 8)
    yy := 0
    while yy < h:
        xx := 0
        while xx < w:
            oy := (yy * vy / vm)
            ox := (xx * hy / hm)
            iy := __f2i(oy) * sy + __f2i(ox)
            lum := 0
            if iy < ysz:
                lum = __load8(py + iy)
            o := po + 4 * (yy * w + xx)
            if nc == 1:
                __store8(o, lum)
                __store8(o + 1, lum)
                __store8(o + 2, lum)
            elif nc == 4 or (nc == 3 and xform == 0):
                # CMYK / YCCK (Adobe : valeurs inversées) ou RGB sans transformation
                c1 := __i2f(lum)
                c2 := __vm_jpg_sample(pcb, scb, cbsz, xx, yy, hcb, vcb, hm, vm)
                c3 := __vm_jpg_sample(pcr, scr, crsz, xx, yy, hcr, vcr, hm, vm)
                if xform == 2 or (nc == 3 and xform == 1):
                    fb2 := c2 - 128.0
                    fr2 := c3 - 128.0
                    r0 := c1 + 1.402 * fr2
                    g0 := c1 - 0.344136 * fb2 - 0.714136 * fr2
                    b0 := c1 + 1.772 * fb2
                    c1 = 255.0 - r0
                    c2 = 255.0 - g0
                    c3 = 255.0 - b0
                    if nc == 3:
                        c1 = r0
                        c2 = g0
                        c3 = b0
                rr := c1
                gg2 := c2
                bb2 := c3
                if nc == 4:
                    kv := __vm_jpg_sample(pk, skk, ksz, xx, yy, hkk, vkk, hm, vm)
                    # CMYK Adobe (valeurs inversées) ; YCCK : 255 - R0 donne la même convention
                    rr = c1 * kv / 255.0
                    gg2 = c2 * kv / 255.0
                    bb2 = c3 * kv / 255.0
                __store8(o, __vm_jpg_clamp(rr))
                __store8(o + 1, __vm_jpg_clamp(gg2))
                __store8(o + 2, __vm_jpg_clamp(bb2))
            else:
                cbv := __vm_jpg_sample(pcb, scb, cbsz, xx, yy, hcb, vcb, hm, vm)
                crv := __vm_jpg_sample(pcr, scr, crsz, xx, yy, hcr, vcr, hm, vm)
                fy := __i2f(lum)
                fb := cbv - 128.0
                fr := crv - 128.0
                r := __f2i(fy + 1.402 * fr + 0.5)
                gg := __f2i(fy - 0.344136 * fb - 0.714136 * fr + 0.5)
                bb := __f2i(fy + 1.772 * fb + 0.5)
                if fy + 1.402 * fr + 0.5 < 0.0:
                    r = 0
                if fy - 0.344136 * fb - 0.714136 * fr + 0.5 < 0.0:
                    gg = 0
                if fy + 1.772 * fb + 0.5 < 0.0:
                    bb = 0
                if r > 255:
                    r = 255
                if gg > 255:
                    gg = 255
                if bb > 255:
                    bb = 255
                __store8(o, r)
                __store8(o + 1, gg)
                __store8(o + 2, bb)
            __store8(o + 3, 255)
            xx += 1
        yy += 1
    return 0

# ---- Décompression zstd (RFC 8878 : trames, blocs bruts / RLE / compressés, littéraux Huffman 1 ou 4 flux, séquences
# FSE prédéfinies / RLE / compressées / répétées, décalages répétés). Pas de dictionnaires. --------------------------
# Espace de travail W (octets) : [0..2048) symboles Huffman, [2048..4096) longueurs Huffman, [4096..6144) table LL,
# [6144..8192) table OF, [8192..10240) table ML (entrées 32 bits : symbole | bits << 8 | base << 16),
# [10240..10752) table FSE des poids Huffman, [10752..12800) fréquences / rangs, [12800..14848) compteurs,
# [14848..15104) poids, [15360..15392) flux arrière, [15392..15424) flux avant, [15488..) état :
# 15488 log Huffman, 15496 / 15504 / 15512 logs LL / OF / ML, 15520 / 15528 / 15536 décalages répétés,
# 15544 Huffman valide, 15552 taille des littéraux, 15560 / 15568 / 15576 tables LL / OF / ML valides ;
# [16384..) littéraux (128 Kio).
func __zs_fail(msg: str):
    __vm_ffi_argfail("zstd_decompress", "données zstd invalides (" + msg + ")")

func __zs_hb(x: int) -> int:
    r := 0 - 1
    while x > 0:
        x = x >> 1
        r += 1
    return r

func __zs_get(p: int, n: int, pos: int, nb: int) -> int:
    if nb == 0:
        return 0
    lo := pos >> 3
    sh := pos & 7
    w := 0
    if lo >= 0 and lo + 8 <= n:
        w = __load64(p + lo)
    else:
        k := 0
        while k < 8:
            i := lo + k
            if i >= 0 and i < n:
                w = w | (__load8(p + i) << (8 * k))
            k += 1
    return (w >> sh) & ((1 << nb) - 1)

# Flux arrière bs : [0] adresse, [8] taille, [16] bits restants (négatif : lu au-delà du début, zéros).
func __zs_rinit(bs: int, p: int, n: int):
    if n <= 0:
        __zs_fail("flux vide")
    last := __load8(p + n - 1)
    if last == 0:
        __zs_fail("fin de flux sans marqueur")
    __store64(bs, p)
    __store64(bs + 8, n)
    __store64(bs + 16, (n - 1) * 8 + __zs_hb(last))

func __zs_rd(bs: int, nb: int) -> int:
    if nb == 0:
        return 0
    off := __load64(bs + 16) - nb
    __store64(bs + 16, off)
    if off >= 0:
        return __zs_get(__load64(bs), __load64(bs + 8), off, nb)
    if off + nb <= 0:
        return 0
    return __zs_get(__load64(bs), __load64(bs + 8), 0, off + nb) << (0 - off)

# Flux avant fr : [0] adresse, [8] taille, [16] position en bits.
func __zs_fd(fr: int, nb: int) -> int:
    pos := __load64(fr + 16)
    v := __zs_get(__load64(fr), __load64(fr + 8), pos, nb)
    __store64(fr + 16, pos + nb)
    return v

func __zs_fse_build(tab: int, freq: int, cnt: int, ns: int, al: int):
    size := 1 << al
    high := size - 1
    s := 0
    while s < ns:
        f := __load64(freq + 8 * s)
        if f < 0:
            __store32(tab + 4 * high, s)
            high -= 1
            __store64(cnt + 8 * s, 1)
        else:
            __store64(cnt + 8 * s, f)
        s += 1
    step := (size >> 1) + (size >> 3) + 3
    mask := size - 1
    pos := 0
    s = 0
    while s < ns:
        f := __load64(freq + 8 * s)
        i := 0
        while i < f:
            __store32(tab + 4 * pos, s)
            pos = (pos + step) & mask
            while pos > high:
                pos = (pos + step) & mask
            i += 1
        s += 1
    if pos != 0:
        __zs_fail("table FSE incohérente")
    i := 0
    while i < size:
        s2 := __load32(tab + 4 * i) & 255
        nx := __load64(cnt + 8 * s2)
        __store64(cnt + 8 * s2, nx + 1)
        nb := al - __zs_hb(nx)
        base := (nx << nb) - size
        __store32(tab + 4 * i, s2 | (nb << 8) | (base << 16))
        i += 1

# Description de table FSE (flux avant fr) ; rend le log de précision.
func __zs_fse_hdr(fr: int, tab: int, maxlog: int, maxsym: int, freq: int, cnt: int) -> int:
    al := __zs_fd(fr, 4) + 5
    if al > maxlog:
        __zs_fail("précision FSE trop grande")
    remaining := 1 << al
    sym := 0
    while remaining > 0 and sym <= maxsym:
        bits := __zs_hb(remaining + 1) + 1
        val := __zs_fd(fr, bits)
        lm := (1 << (bits - 1)) - 1
        th := (1 << bits) - 1 - (remaining + 1)
        if (val & lm) < th:
            __store64(fr + 16, __load64(fr + 16) - 1)
            val = val & lm
        elif val > lm:
            val = val - th
        pr := val - 1
        if pr < 0:
            remaining -= 1
        else:
            remaining -= pr
        __store64(freq + 8 * sym, pr)
        sym += 1
        if pr == 0:
            rep := __zs_fd(fr, 2)
            while true:
                i := 0
                while i < rep and sym <= maxsym:
                    __store64(freq + 8 * sym, 0)
                    sym += 1
                    i += 1
                if rep == 3:
                    rep = __zs_fd(fr, 2)
                else:
                    break
    if remaining != 0:
        __zs_fail("probabilités FSE")
    __store64(fr + 16, ((__load64(fr + 16) + 7) >> 3) << 3)
    __zs_fse_build(tab, freq, cnt, sym, al)
    return al

func __zs_run(freq: int, i: int, count: int, v: int) -> int:
    k := 0
    while k < count:
        __store64(freq + 8 * (i + k), v)
        k += 1
    return i + count

# Distributions prédéfinies : 0 LL, 1 OF, 2 ML ; rend le nombre de symboles.
func __zs_predef(freq: int, kind: int) -> int:
    i := 0
    if kind == 0:
        i = __zs_run(freq, i, 1, 4)
        i = __zs_run(freq, i, 1, 3)
        i = __zs_run(freq, i, 11, 2)
        i = __zs_run(freq, i, 3, 1)
        i = __zs_run(freq, i, 9, 2)
        i = __zs_run(freq, i, 1, 3)
        i = __zs_run(freq, i, 1, 2)
        i = __zs_run(freq, i, 5, 1)
        i = __zs_run(freq, i, 4, 0 - 1)
    elif kind == 1:
        i = __zs_run(freq, i, 6, 1)
        i = __zs_run(freq, i, 3, 2)
        i = __zs_run(freq, i, 15, 1)
        i = __zs_run(freq, i, 5, 0 - 1)
    else:
        i = __zs_run(freq, i, 1, 1)
        i = __zs_run(freq, i, 1, 4)
        i = __zs_run(freq, i, 1, 3)
        i = __zs_run(freq, i, 6, 2)
        i = __zs_run(freq, i, 37, 1)
        i = __zs_run(freq, i, 7, 0 - 1)
    return i

# Table de séquences (kind 0 LL, 1 OF, 2 ML) selon le mode ; rend les octets consommés.
func __zs_table(w: int, kind: int, mode: int, p: int, n: int) -> int:
    tab := w + 4096 + 2048 * kind
    maxlog := 9
    maxsym := 35
    if kind == 1:
        maxlog = 8
        maxsym = 31
    elif kind == 2:
        maxsym = 52
    if mode == 0:
        ns := __zs_predef(w + 10752, kind)
        al := 6
        if kind == 1:
            al = 5
        __zs_fse_build(tab, w + 10752, w + 12800, ns, al)
        __store64(w + 15496 + 8 * kind, al)
        __store64(w + 15560 + 8 * kind, 1)
        return 0
    if mode == 1:
        if n < 1:
            __zs_fail("table RLE tronquée")
        sym := __load8(p)
        if sym > maxsym:
            __zs_fail("symbole RLE")
        __store32(tab, sym)
        __store64(w + 15496 + 8 * kind, 0)
        __store64(w + 15560 + 8 * kind, 1)
        return 1
    if mode == 2:
        fr := w + 15392
        __store64(fr, p)
        __store64(fr + 8, n)
        __store64(fr + 16, 0)
        al := __zs_fse_hdr(fr, tab, maxlog, maxsym, w + 10752, w + 12800)
        used := __load64(fr + 16) >> 3
        if used > n:
            __zs_fail("table FSE tronquée")
        __store64(w + 15496 + 8 * kind, al)
        __store64(w + 15560 + 8 * kind, 1)
        return used
    if __load64(w + 15560 + 8 * kind) == 0:
        __zs_fail("table répétée absente")
    return 0

# Arbre de Huffman des littéraux ; rend les octets consommés.
func __zs_huf(w: int, p: int, n: int) -> int:
    if n < 1:
        __zs_fail("arbre de Huffman absent")
    hb := __load8(p)
    wts := w + 14848
    nw := 0
    used := 0
    if hb >= 128:
        nw = hb - 127
        nbytes := (nw + 1) >> 1
        if 1 + nbytes > n:
            __zs_fail("poids tronqués")
        i := 0
        while i < nw:
            b := __load8(p + 1 + (i >> 1))
            if (i & 1) == 0:
                __store8(wts + i, b >> 4)
            else:
                __store8(wts + i, b & 15)
            i += 1
        used = 1 + nbytes
    else:
        if 1 + hb > n or hb == 0:
            __zs_fail("poids FSE tronqués")
        fr := w + 15392
        __store64(fr, p + 1)
        __store64(fr + 8, hb)
        __store64(fr + 16, 0)
        tab := w + 10240
        al := __zs_fse_hdr(fr, tab, 6, 255, w + 10752, w + 12800)
        hbytes := __load64(fr + 16) >> 3
        if hbytes >= hb:
            __zs_fail("poids FSE")
        bs := w + 15360
        __zs_rinit(bs, p + 1 + hbytes, hb - hbytes)
        s1 := __zs_rd(bs, al)
        s2 := __zs_rd(bs, al)
        while true:
            if nw >= 254:
                __zs_fail("trop de poids")
            e := __load32(tab + 4 * s1)
            __store8(wts + nw, e & 255)
            nw += 1
            s1 = (e >> 16) + __zs_rd(bs, (e >> 8) & 255)
            if __load64(bs + 16) < 0:
                __store8(wts + nw, __load32(tab + 4 * s2) & 255)
                nw += 1
                break
            e2 := __load32(tab + 4 * s2)
            __store8(wts + nw, e2 & 255)
            nw += 1
            s2 = (e2 >> 16) + __zs_rd(bs, (e2 >> 8) & 255)
            if __load64(bs + 16) < 0:
                __store8(wts + nw, __load32(tab + 4 * s1) & 255)
                nw += 1
                break
        used = 1 + hb
    total := 0
    i := 0
    while i < nw:
        wv := __load8(wts + i)
        if wv > 11:
            __zs_fail("poids de Huffman")
        if wv > 0:
            total += 1 << (wv - 1)
        i += 1
    if total == 0:
        __zs_fail("arbre de Huffman vide")
    maxb := __zs_hb(total) + 1
    left := (1 << maxb) - total
    if (left & (left - 1)) != 0 or maxb > 11:
        __zs_fail("arbre de Huffman incomplet")
    __store8(wts + nw, __zs_hb(left) + 1)
    nw += 1
    cnt := w + 12800
    idx := w + 10752
    b := 0
    while b <= 12:
        __store64(cnt + 8 * b, 0)
        __store64(idx + 8 * b, 0)
        b += 1
    i = 0
    while i < nw:
        wv := __load8(wts + i)
        if wv > 0:
            nb := maxb + 1 - wv
            __store64(cnt + 8 * nb, __load64(cnt + 8 * nb) + 1)
        i += 1
    __store64(idx + 8 * maxb, 0)
    b = maxb
    while b >= 1:
        st := __load64(idx + 8 * b)
        en := st + __load64(cnt + 8 * b) * (1 << (maxb - b))
        __store64(idx + 8 * (b - 1), en)
        j := st
        while j < en:
            __store8(w + 2048 + j, b)
            j += 1
        b -= 1
    i = 0
    while i < nw:
        wv := __load8(wts + i)
        if wv > 0:
            nb := maxb + 1 - wv
            code := __load64(idx + 8 * nb)
            ln := 1 << (maxb - nb)
            j := 0
            while j < ln:
                __store8(w + code + j, i)
                j += 1
            __store64(idx + 8 * nb, code + ln)
        i += 1
    __store64(w + 15488, maxb)
    __store64(w + 15544, 1)
    return used

func __zs_hstream(w: int, p: int, n: int, out: int, count: int):
    bs := w + 15360
    __zs_rinit(bs, p, n)
    lg := __load64(w + 15488)
    mask := (1 << lg) - 1
    st := __zs_rd(bs, lg)
    i := 0
    while i < count:
        __store8(out + i, __load8(w + st))
        nb := __load8(w + 2048 + st)
        st = ((st << nb) + __zs_rd(bs, nb)) & mask
        i += 1

# Section des littéraux ; rend les octets consommés (littéraux dans W + 16384, taille dans W + 15552).
func __zs_lits(w: int, p: int, n: int) -> int:
    if n < 1:
        __zs_fail("bloc vide")
    lit := w + 16384
    b0 := __load8(p)
    lt := b0 & 3
    sf := (b0 >> 2) & 3
    if lt <= 1:
        rs := 0
        hs := 1
        if sf == 0 or sf == 2:
            rs = b0 >> 3
        elif sf == 1:
            if n < 2:
                __zs_fail("en-tête des littéraux")
            rs = (b0 >> 4) + (__load8(p + 1) << 4)
            hs = 2
        else:
            if n < 3:
                __zs_fail("en-tête des littéraux")
            rs = (b0 >> 4) + (__load8(p + 1) << 4) + (__load8(p + 2) << 12)
            hs = 3
        if rs > 131072:
            __zs_fail("littéraux trop longs")
        __store64(w + 15552, rs)
        if lt == 0:
            if hs + rs > n:
                __zs_fail("littéraux bruts tronqués")
            i := 0
            while i < rs:
                __store8(lit + i, __load8(p + hs + i))
                i += 1
            return hs + rs
        if hs + 1 > n:
            __zs_fail("littéraux RLE tronqués")
        v := __load8(p + hs)
        i := 0
        while i < rs:
            __store8(lit + i, v)
            i += 1
        return hs + 1
    hs := 3
    rs := 0
    cs := 0
    streams := 4
    if n < 5:
        __zs_fail("en-tête des littéraux")
    if sf <= 1:
        h := b0 | (__load8(p + 1) << 8) | (__load8(p + 2) << 16)
        rs = (h >> 4) & 1023
        cs = (h >> 14) & 1023
        if sf == 0:
            streams = 1
    elif sf == 2:
        hs = 4
        h := b0 | (__load8(p + 1) << 8) | (__load8(p + 2) << 16) | (__load8(p + 3) << 24)
        rs = (h >> 4) & 16383
        cs = (h >> 18) & 16383
    else:
        hs = 5
        h := b0 | (__load8(p + 1) << 8) | (__load8(p + 2) << 16) | (__load8(p + 3) << 24) | (__load8(p + 4) << 32)
        rs = (h >> 4) & 262143
        cs = (h >> 22) & 262143
    if hs + cs > n or rs > 131072:
        __zs_fail("littéraux compressés tronqués")
    q := p + hs
    rem := cs
    if lt == 2:
        u := __zs_huf(w, q, rem)
        q += u
        rem -= u
    elif __load64(w + 15544) == 0:
        __zs_fail("arbre de Huffman répété absent")
    if streams == 1:
        __zs_hstream(w, q, rem, lit, rs)
    else:
        if rem < 10:
            __zs_fail("table des flux")
        s1 := __load8(q) | (__load8(q + 1) << 8)
        s2 := __load8(q + 2) | (__load8(q + 3) << 8)
        s3 := __load8(q + 4) | (__load8(q + 5) << 8)
        s4 := rem - 6 - s1 - s2 - s3
        seg := (rs + 3) >> 2
        if s4 < 1 or rs < 3 * seg:
            __zs_fail("tailles des flux")
        __zs_hstream(w, q + 6, s1, lit, seg)
        __zs_hstream(w, q + 6 + s1, s2, lit + seg, seg)
        __zs_hstream(w, q + 6 + s1 + s2, s3, lit + 2 * seg, seg)
        __zs_hstream(w, q + 6 + s1 + s2 + s3, s4, lit + 3 * seg, rs - 3 * seg)
    __store64(w + 15552, rs)
    return hs + cs

func __zs_llbase(c: int) -> int:
    if c < 16:
        return c
    if c >= 25:
        return 1 << (c - 19)
    if c < 20:
        return 16 + 2 * (c - 16)
    if c == 20:
        return 24
    if c == 21:
        return 28
    if c == 22:
        return 32
    if c == 23:
        return 40
    return 48

func __zs_llbits(c: int) -> int:
    if c < 16:
        return 0
    if c >= 25:
        return c - 19
    if c < 20:
        return 1
    if c < 22:
        return 2
    if c < 24:
        return 3
    return 4

func __zs_mlbase(c: int) -> int:
    if c < 32:
        return c + 3
    if c >= 43:
        return (1 << (c - 36)) + 3
    if c < 36:
        return 35 + 2 * (c - 32)
    if c == 36:
        return 43
    if c == 37:
        return 47
    if c == 38:
        return 51
    if c == 39:
        return 59
    if c == 40:
        return 67
    if c == 41:
        return 83
    return 99

func __zs_mlbits(c: int) -> int:
    if c < 32:
        return 0
    if c >= 43:
        return c - 36
    if c < 36:
        return 1
    if c < 38:
        return 2
    if c < 40:
        return 3
    if c < 42:
        return 4
    return 5

func __zs_copy(d: int, s: int, n: int):
    i := 0
    while i < n:
        __store8(d + i, __load8(s + i))
        i += 1

# Section des séquences et exécution ; rend la nouvelle position de sortie.
func __zs_seqs(w: int, p: int, n: int, dst: int, dpos: int, dcap: int, fs: int) -> int:
    lit := w + 16384
    nlit := __load64(w + 15552)
    if n < 1:
        __zs_fail("section des séquences absente")
    b0 := __load8(p)
    q := 1
    nseq := 0
    if b0 < 128:
        nseq = b0
    elif b0 < 255:
        if n < 2:
            __zs_fail("nombre de séquences")
        nseq = ((b0 - 128) << 8) + __load8(p + 1)
        q = 2
    else:
        if n < 3:
            __zs_fail("nombre de séquences")
        nseq = __load8(p + 1) + (__load8(p + 2) << 8) + 32512
        q = 3
    lp := 0
    if nseq > 0:
        if q >= n:
            __zs_fail("modes des séquences")
        modes := __load8(p + q)
        q += 1
        if (modes & 3) != 0:
            __zs_fail("modes réservés")
        q += __zs_table(w, 0, modes >> 6, p + q, n - q)
        q += __zs_table(w, 1, (modes >> 4) & 3, p + q, n - q)
        q += __zs_table(w, 2, (modes >> 2) & 3, p + q, n - q)
        if q >= n:
            __zs_fail("flux des séquences absent")
        bs := w + 15360
        __zs_rinit(bs, p + q, n - q)
        llt := w + 4096
        oft := w + 6144
        mlt := w + 8192
        lls := __zs_rd(bs, __load64(w + 15496))
        ofs := __zs_rd(bs, __load64(w + 15504))
        mls := __zs_rd(bs, __load64(w + 15512))
        r1 := __load64(w + 15520)
        r2 := __load64(w + 15528)
        r3 := __load64(w + 15536)
        k := 0
        while k < nseq:
            ofc := __load32(oft + 4 * ofs) & 255
            llc := __load32(llt + 4 * lls) & 255
            mlc := __load32(mlt + 4 * mls) & 255
            if llc > 35 or mlc > 52 or ofc > 31:
                __zs_fail("code de séquence")
            ofv := (1 << ofc) + __zs_rd(bs, ofc)
            ml := __zs_mlbase(mlc) + __zs_rd(bs, __zs_mlbits(mlc))
            ll := __zs_llbase(llc) + __zs_rd(bs, __zs_llbits(llc))
            k += 1
            if k < nseq:
                e := __load32(llt + 4 * lls)
                lls = (e >> 16) + __zs_rd(bs, (e >> 8) & 255)
                e = __load32(mlt + 4 * mls)
                mls = (e >> 16) + __zs_rd(bs, (e >> 8) & 255)
                e = __load32(oft + 4 * ofs)
                ofs = (e >> 16) + __zs_rd(bs, (e >> 8) & 255)
            off := 0
            if ofv > 3:
                off = ofv - 3
                r3 = r2
                r2 = r1
                r1 = off
            else:
                idx := ofv - 1
                if ll == 0:
                    idx += 1
                if idx == 0:
                    off = r1
                else:
                    if idx == 1:
                        off = r2
                    elif idx == 2:
                        off = r3
                    else:
                        off = r1 - 1
                    if idx > 1:
                        r3 = r2
                    r2 = r1
                    r1 = off
            if lp + ll > nlit:
                __zs_fail("littéraux insuffisants")
            if dpos + ll + ml > dcap:
                __zs_fail("sortie plus grande que prévu")
            __zs_copy(dst + dpos, lit + lp, ll)
            dpos += ll
            lp += ll
            if off < 1 or off > dpos - fs:
                __zs_fail("décalage hors fenêtre")
            s := dst + dpos - off
            if off >= 8:
                i := 0
                while i + 8 <= ml:
                    __store64(dst + dpos + i, __load64(s + i))
                    i += 8
                while i < ml:
                    __store8(dst + dpos + i, __load8(s + i))
                    i += 1
            else:
                __zs_copy(dst + dpos, s, ml)
            dpos += ml
        __store64(w + 15520, r1)
        __store64(w + 15528, r2)
        __store64(w + 15536, r3)
    if dpos + nlit - lp > dcap:
        __zs_fail("sortie plus grande que prévu")
    __zs_copy(dst + dpos, lit + lp, nlit - lp)
    return dpos + nlit - lp

# zstd_decompress(source, décalage, longueur, destination, capacité) -> octets écrits (trames concaténées acceptées).
func __vm_nat__native_ffi__zstd_decompress(n: int, a: int, b: int, c: int, d: int, e: int) -> int:
    __nat_exact("zstd_decompress", n, 5)
    sb := __vm_ffi_buf("zstd_decompress", a)
    so := __vm_ffi_int("zstd_decompress", b, "le décalage")
    sl := __vm_ffi_int("zstd_decompress", c, "la longueur")
    db := __vm_ffi_buf("zstd_decompress", d)
    dcap := __vm_ffi_int("zstd_decompress", e, "la capacité")
    __vm_ffi_range("zstd_decompress", sb, so, sl)
    __vm_ffi_range("zstd_decompress", db, 0, dcap)
    w := __alloc_raw(147520)
    sp := __load64(sb) + so
    send := sp + sl
    dst := __load64(db)
    dpos := 0
    while sp + 4 <= send:
        magic := __load32(sp)
        if (magic & 4294967280) == 407710288:
            if sp + 8 > send:
                __zs_fail("trame ignorable tronquée")
            sp += 8 + __load32(sp + 4)
            continue
        if magic != 4247762216:
            __zs_fail("signature")
        sp += 4
        if sp + 1 > send:
            __zs_fail("en-tête tronqué")
        fhd := __load8(sp)
        sp += 1
        fcsf := fhd >> 6
        single := (fhd >> 5) & 1
        chk := (fhd >> 2) & 1
        didf := fhd & 3
        if (fhd & 8) != 0:
            __zs_fail("bit réservé")
        if single == 0:
            sp += 1
        dsz := didf
        if didf == 3:
            dsz = 4
        did := 0
        k := 0
        while k < dsz:
            if sp + k < send:
                did = did | (__load8(sp + k) << (8 * k))
            k += 1
        if did != 0:
            __vm_ffi_argfail("zstd_decompress", "dictionnaires zstd non pris en charge")
        sp += dsz
        fsz := 0
        if fcsf == 0:
            fsz = single
        else:
            fsz = 1 << fcsf
        sp += fsz
        __store64(w + 15520, 1)
        __store64(w + 15528, 4)
        __store64(w + 15536, 8)
        __store64(w + 15544, 0)
        __store64(w + 15560, 0)
        __store64(w + 15568, 0)
        __store64(w + 15576, 0)
        fs := dpos
        while true:
            if sp + 3 > send:
                __zs_fail("bloc tronqué")
            bh := __load8(sp) | (__load8(sp + 1) << 8) | (__load8(sp + 2) << 16)
            sp += 3
            last := bh & 1
            bt := (bh >> 1) & 3
            bsz := bh >> 3
            if bt == 0:
                if sp + bsz > send or dpos + bsz > dcap:
                    __zs_fail("bloc brut")
                __zs_copy(dst + dpos, sp, bsz)
                sp += bsz
                dpos += bsz
            elif bt == 1:
                if sp + 1 > send or dpos + bsz > dcap:
                    __zs_fail("bloc RLE")
                v := __load8(sp)
                i := 0
                while i < bsz:
                    __store8(dst + dpos + i, v)
                    i += 1
                sp += 1
                dpos += bsz
            elif bt == 2:
                if bsz > 131072 or sp + bsz > send:
                    __zs_fail("bloc compressé")
                used := __zs_lits(w, sp, bsz)
                dpos = __zs_seqs(w, sp + used, bsz - used, dst, dpos, dcap, fs)
                sp += bsz
            else:
                __zs_fail("type de bloc réservé")
            if last != 0:
                break
        if chk != 0:
            sp += 4
    return __dyn_int(dpos)

func __vm_nat__native_ffi__type_size(n: int, a: int) -> int:
    __nat_exact("type_size", n, 1)
    return __dyn_int(__vm_ffi_size(__vm_ffi_type("type_size", a, "le type")))

func __vm_nat__native_ffi__live_counts(n: int) -> int:
    __nat_exact("live_counts", n, 0)
    d := __dyn_dict_new()
    __dyn_dict_lit_set(d, __dyn_str("libraries"), __dyn_int(__load64(__vm_ffi_tab(152))))
    __dyn_dict_lit_set(d, __dyn_str("functions"), __dyn_int(__load64(__vm_ffi_tab(160))))
    __dyn_dict_lit_set(d, __dyn_str("buffers"), __dyn_int(__load64(__vm_ffi_tab(168))))
    return d

# ---- Module natif _native_tls : OpenSSL chargé par dlopen ------------------------
# État : VM [176] fiche [essayé][disponible][motif][version][libssl][libcrypto][fonctions]  [192] sessions
# (id -> [ctx][ssl][fd][protocoles ALPN du serveur])  [200] prochain identifiant.

func __vm_c6(fp: int, a: int, b: int, c: int, d: int, e: int, f: int) -> int:
    fr := __alloc_raw(168)
    __store64(fr, a)
    __store64(fr + 8, b)
    __store64(fr + 16, c)
    __store64(fr + 24, d)
    __store64(fr + 32, e)
    __store64(fr + 40, f)
    return __vm_sysv(fp, fr)

func __vm_errno_ptr() -> int:
    return __vm_c(__vm_imp(4), 0, 0)

func __vm_tls_names() -> str:
    return "OPENSSL_init_ssl TLS_client_method TLS_server_method SSL_CTX_new SSL_CTX_free SSL_CTX_ctrl SSL_CTX_set_options SSL_CTX_set_verify SSL_CTX_set_default_verify_paths SSL_CTX_load_verify_locations SSL_CTX_use_certificate_chain_file SSL_CTX_use_PrivateKey_file SSL_CTX_check_private_key SSL_CTX_set_alpn_protos SSL_CTX_set_alpn_select_cb SSL_new SSL_free SSL_set_fd SSL_connect SSL_accept SSL_read SSL_write SSL_shutdown SSL_get_error SSL_pending SSL_ctrl SSL_set1_host SSL_get0_param X509_VERIFY_PARAM_set1_ip_asc SSL_get_verify_result SSL_get_version SSL_get_current_cipher SSL_CIPHER_get_name SSL_get0_alpn_selected SSL_get_shutdown ERR_get_error ERR_error_string_n ERR_clear_error X509_get_subject_name X509_get_issuer_name X509_NAME_oneline X509_free X509_verify_cert_error_string"

func __vm_tls() -> int:
    vs := __vm_st()
    t := __load64(vs + 176)
    if t == 0:
        t = __alloc(64)
        __store64(t + 16, __str_addr(""))
        __store64(t + 24, __str_addr(""))
        __store64(t + 48, __alloc_raw(8 * 64))
        __store64(vs + 176, t)
    return t

func __vm_tls_fn(k: int) -> int:
    return __load64(__load64(__vm_tls() + 48) + 8 * k)

func __vm_tls_sym(t: int, name: str) -> int:
    c := __nat_c(name)
    dl := __vm_imp(1)
    p := 0
    if __load64(t + 32) != 0:
        p = __vm_c(dl, __load64(t + 32), c)
    if p == 0 and __load64(t + 40) != 0:
        p = __vm_c(dl, __load64(t + 40), c)
    return p

func __vm_tls_open(names: str) -> int:
    i := 0
    n := __nat_blen(names)
    while i < n:
        j := i
        while j < n and __load8(__nat_bp(names) + j) != 32:
            j += 1
        h := __vm_c(__vm_imp(0), __nat_c(__nat_sub(names, i, j - i)), 2)
        if h != 0:
            return h
        i = j + 1
    return 0

func __vm_tls_load() -> bool:
    if __alexos():
        return false   # Alex OS : TLS par la bibliothèque crypto écrite en ALEX, pas de bibliothèque partagée
    t := __vm_tls()
    if __load64(t) != 0:
        return __load64(t + 8) != 0
    __store64(t, 1)
    __store64(t + 32, __vm_tls_open("libssl.so.3 libssl.so.1.1 libssl.so libssl.3.dylib libssl.dylib libssl.so.1.0.0"))
    __store64(t + 40, __vm_tls_open("libcrypto.so.3 libcrypto.so.1.1 libcrypto.so libcrypto.3.dylib libcrypto.dylib libcrypto.so.1.0.0"))
    if __load64(t + 32) == 0 or __load64(t + 40) == 0:
        __store64(t + 16, __str_addr("OpenSSL (libssl / libcrypto) introuvable : installez libssl3 ou libssl1.1"))
        return false
    tab := __load64(t + 48)
    names := __vm_tls_names()
    good := true
    k := 0
    i := 0
    n := __nat_blen(names)
    while i < n:
        j := i
        while j < n and __load8(__nat_bp(names) + j) != 32:
            j += 1
        nm := __nat_sub(names, i, j - i)
        p := __vm_tls_sym(t, nm)
        if p == 0:
            if good:
                __store64(t + 16, __str_addr("symbole OpenSSL absent : " + nm))
            good = false
        __store64(tab + 8 * k, p)
        k += 1
        i = j + 1
    pc := __vm_tls_sym(t, "SSL_get1_peer_certificate")
    if pc == 0:
        pc = __vm_tls_sym(t, "SSL_get_peer_certificate")
        if pc == 0:
            if good:
                __store64(t + 16, __str_addr("symbole OpenSSL absent : SSL_get_peer_certificate"))
            good = false
    __store64(tab + 8 * 43, pc)
    __store64(tab + 8 * 44, __vm_tls_sym(t, "OpenSSL_version"))
    __store64(tab + 8 * 45, __vm_tls_sym(t, "i2d_X509"))
    __store64(tab + 8 * 46, __vm_tls_sym(t, "EVP_get_digestbyname"))
    __store64(tab + 8 * 47, __vm_tls_sym(t, "EVP_Digest"))
    __store64(tab + 8 * 48, __vm_tls_sym(t, "HMAC"))
    __store64(tab + 8 * 49, __vm_tls_sym(t, "PKCS5_PBKDF2_HMAC"))
    __store64(tab + 8 * 50, __vm_tls_sym(t, "CRYPTO_free"))
    if not good:
        return false
    __vm_c(__vm_tls_fn(0), 0, 0)
    # SIGPIPE ignoré (sauf traitement installé par le programme) : écrire vers un pair parti échoue avec EPIPE
    sa := __alloc_raw(32)
    if __syscall(13, 13, 0, sa, 8) == 0 and __load64(sa) == 0:
        na := __alloc_raw(32)
        __store64(na, 1)
        __syscall(13, 13, na, 0, 8)
    if __vm_tls_fn(44) != 0:
        v := __vm_c(__vm_tls_fn(44), 0, 0)
        if v != 0:
            __store64(t + 24, __str_addr(__nat_from_c(v)))
    __store64(t + 8, 1)
    return true

# Windows : TLS non pris en charge (tls_native.cpp, `unsupported`, sans contrôle d'arité).
func __vm_tls_off():
    if __windows():
        __dyn_err("IoError", "tls : non pris en charge sur cette plateforme")

func __vm_tls_require(fn: str):
    if not __vm_tls_load():
        __dyn_err("IoError", fn + " : TLS indisponible — " + __as_str(__load64(__vm_tls() + 16)))

func __vm_tls_session(fn: str, v: int) -> int:
    h := __nat_int(fn, v, "le handle")
    s := __vm_ffi_get(192, h)
    if s == 0:
        __dyn_err("ArgumentError", "'" + fn + "' : handle TLS invalide ou déjà fermé (" + __int_to_str(h) + ")")
    return s

# Échéance : [infini][zéro][fin (s, horloge monotone)]
func __vm_tls_deadline(fn: str, v: int) -> int:
    d := __alloc_raw(24)
    t := __nat_timeout(fn, v)
    if t < 0.0:
        __store64(d, 1)
        return d
    if t <= 0.0:
        __store64(d + 8, 1)
    __store64(d + 16, __f2bits(__nat_deadline(t)))
    return d

func __vm_tls_expired(d: int) -> int:
    if __load64(d + 8) != 0:
        return -11
    return -110

func __vm_tls_wait(fd: int, events: int, d: int) -> bool:
    p := __alloc_raw(8)
    while true:
        ms := -1
        if __load64(d) == 0:
            ms = __nat_remaining_ms(__bits2f(__load64(d + 16)))
        __store32(p, fd)
        __store16(p + 4, events)
        __store16(p + 6, 0)
        r := __syscall(7, p, 1, ms)
        if r > 0:
            return true
        if r == 0:
            return false
        if r != -4:
            return true
    return true

func __vm_tls_errno() -> int:
    return ((__load32(__vm_errno_ptr()) & 4294967295) ^ 2147483648) - 2147483648

func __vm_tls_clear_errno():
    __store32(__vm_errno_ptr(), 0)

func __vm_tls_drain(s: int) -> str:
    msg := ""
    buf := __alloc_raw(256)
    while true:
        e := __vm_c(__vm_tls_fn(35), 0, 0)
        if e == 0:
            break
        __vm_c6(__vm_tls_fn(36), e, buf, 256, 0, 0, 0)
        if __nat_blen(msg) > 0:
            msg = msg + " ; "
        msg = msg + __nat_from_c(buf)
    if s != 0 and __load64(s + 8) != 0:
        vr := __vm_c(__vm_tls_fn(29), __load64(s + 8), 0)
        if vr != 0:
            tx := __vm_c(__vm_tls_fn(42), vr, 0)
            what := "?"
            if tx != 0:
                what = __nat_from_c(tx)
            sep := ""
            if __nat_blen(msg) > 0:
                sep = " — "
            msg = msg + sep + "vérification du certificat : " + what + " (" + __int_to_str(vr) + ")"
    if __nat_blen(msg) == 0:
        return "erreur TLS inconnue"
    return msg

func __vm_tls_error(s: int, prefix: str) -> int:
    vr := 0
    if s != 0 and __load64(s + 8) != 0:
        vr = __vm_c(__vm_tls_fn(29), __load64(s + 8), 0)
    l := __dyn_list_new(0)
    __dyn_list_push(l, __dyn_str(prefix + __vm_tls_drain(s)))
    __dyn_list_push(l, __dyn_int(vr))
    return l

func __vm_tls_alpn_wire(fn: str, v: int) -> str:
    items := __nat_items(fn, v, "alpn", "une list")
    sb := __rt_sb_new()
    i := 0
    while i < __load64(items):
        p := __nat_cstr(fn, __rt_vec_at(items, i), "alpn (élément)")
        if __nat_blen(p) == 0 or __nat_blen(p) > 255:
            __dyn_err("ArgumentError", "'alpn' : protocole de 1 à 255 octets attendu")
        __rt_sb_byte(sb, __nat_blen(p))
        __rt_sb_add(sb, p)
        i += 1
    return __rt_sb_str(sb)

# Rappel de sélection ALPN du serveur, appelé par OpenSSL (convention System V, mêmes registres d'arguments que le
# code natif) : premier protocole du serveur (arg = [chaîne native]) que le client propose.
func __vm_tls_alpn_select(ssl: int, out: int, outlen: int, inp: int, inlen: int, arg: int) -> int:
    mine := __load64(arg)
    n := __load64(mine)
    m := mine + 8
    i := 0
    while i < n:
        len := __load8(m + i)
        j := 0
        while j < (inlen & 4294967295):
            clen := __load8(inp + j)
            if clen == len:
                k := 0
                same := true
                while k < len:
                    if __load8(inp + j + 1 + k) != __load8(m + i + 1 + k):
                        same = false
                        break
                    k += 1
                if same:
                    __store64(out, inp + j + 1)
                    __store8(outlen, len)
                    return 0
            j += 1 + clen
        i += 1 + len
    return 3

# Poignée de main : 0 réussie, sinon la valeur d'échec à renvoyer.
func __vm_tls_handshake(s: int, accept: bool, d: int) -> int:
    while true:
        __vm_c(__vm_tls_fn(37), 0, 0)
        __vm_tls_clear_errno()
        r := 0
        if accept:
            r = __vm_c(__vm_tls_fn(19), __load64(s + 8), 0)
        else:
            r = __vm_c(__vm_tls_fn(18), __load64(s + 8), 0)
        r = ((r & 4294967295) ^ 2147483648) - 2147483648
        if r == 1:
            return __dyn_int(0)
        err := __vm_c(__vm_tls_fn(23), __load64(s + 8), r) & 4294967295
        en := __vm_tls_errno()
        if err == 2:
            if not __vm_tls_wait(__load64(s + 16), 1, d):
                return __dyn_int(__vm_tls_expired(d))
        elif err == 3:
            if not __vm_tls_wait(__load64(s + 16), 4, d):
                return __dyn_int(__vm_tls_expired(d))
        elif err == 5 and en != 0 and en != 4:
            return __dyn_int(0 - en)
        elif err == 5 or err == 6:
            l := __dyn_list_new(0)
            __dyn_list_push(l, __dyn_str("poignée de main TLS : connexion fermée par l'autre extrémité"))
            __dyn_list_push(l, __dyn_int(0))
            return l
        else:
            return __vm_tls_error(s, "poignée de main TLS : ")
    return 0

func __vm_tls_adopt(s: int) -> int:
    vs := __vm_st()
    h := __load64(vs + 200) + 1
    __store64(vs + 200, h)
    __rt_dict_set(__vm_ffi_tab(192), h, s, 0)
    return __dyn_int(h)

func __vm_tls_free(s: int):
    if __load64(s + 8) != 0:
        __vm_c(__vm_tls_fn(16), __load64(s + 8), 0)
        __store64(s + 8, 0)
    if __load64(s) != 0:
        __vm_c(__vm_tls_fn(4), __load64(s), 0)
        __store64(s, 0)

func __vm_tls_files(s: int, fn: str, cert: str, key: str):
    __vm_c(__vm_tls_fn(37), 0, 0)
    if (__vm_c(__vm_tls_fn(10), __load64(s), __nat_c(cert)) & 4294967295) != 1:
        __dyn_err("ArgumentError", "'" + fn + "' : certificat illisible '" + cert + "' : " + __vm_tls_drain(0))
    if (__vm_c6(__vm_tls_fn(11), __load64(s), __nat_c(key), 1, 0, 0, 0) & 4294967295) != 1:
        __dyn_err("ArgumentError", "'" + fn + "' : clé privée illisible '" + key + "' : " + __vm_tls_drain(0))
    if (__vm_c(__vm_tls_fn(12), __load64(s), 0) & 4294967295) != 1:
        __dyn_err("ArgumentError", "'" + fn + "' : la clé privée ne correspond pas au certificat : " + __vm_tls_drain(0))

func __vm_tls_base(s: int):
    __vm_c6(__vm_tls_fn(5), __load64(s), 123, 771, 0, 0, 0)
    __vm_c6(__vm_tls_fn(5), __load64(s), 33, 3, 0, 0, 0)

func __vm_tls_looks_ip(h: str) -> bool:
    n := __nat_blen(h)
    if __vm_findb(h, 58) >= 0:
        return true
    if n == 0:
        return false
    i := 0
    while i < n:
        c := __load8(__nat_bp(h) + i)
        if not ((c >= 48 and c <= 57) or c == 46):
            return false
        i += 1
    return true

func __vm_tls_bool(fn: str, v: int, label: str) -> bool:
    if not __dyn_is(v, 3):
        __dyn_err("TypeError", "'" + fn + "' : " + label + " doit être un bool (obtenu '" + __dyn_type_name(v) + "')")
    return __load64(v + 8) != 0

func __vm_nat__native_tls__supported(n: int) -> int:
    __nat_exact("supported", n, 0)
    if __windows():
        return __dyn_bool(false)
    return __dyn_bool(__vm_tls_load())

func __vm_nat__native_tls__why(n: int) -> int:
    __nat_exact("why", n, 0)
    if __windows():
        return __dyn_str("TLS non pris en charge sur cette plateforme")
    if __vm_tls_load():
        return __dyn_str("")
    return __dyn_str(__as_str(__load64(__vm_tls() + 16)))

func __vm_nat__native_tls__version(n: int) -> int:
    __vm_tls_off()
    __nat_exact("version", n, 0)
    __vm_tls_require("version")
    return __dyn_str(__as_str(__load64(__vm_tls() + 24)))

# client(fd, hôte|null, verify, ca|null, alpn|null, délai, certificat|null, clé|null, strict_eof)
func __vm_nat__native_tls__client(f: int, n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int, a6: int, a7: int, x: int) -> int:
    __vm_tls_off()
    __nat_exact("client", n, 9)
    __vm_tls_require("client")
    a8 := __dyn_xarg(x, 0)
    fd := __nat_int("client", a0, "le descripteur")
    host := ""
    if a1 != 0:
        host = __nat_cstr("client", a1, "le nom d'hôte")
    verify := __vm_tls_bool("client", a2, "verify")
    ca := ""
    if a3 != 0:
        ca = __nat_cstr("client", a3, "le fichier d'autorités")
    alpn := ""
    if a4 != 0:
        alpn = __vm_tls_alpn_wire("client", a4)
    d := __vm_tls_deadline("client", a5)
    cert := ""
    if a6 != 0:
        cert = __nat_cstr("client", a6, "le certificat client")
    key := ""
    if a7 != 0:
        key = __nat_cstr("client", a7, "la clé client")
    strict := __vm_tls_bool("client", a8, "strict_eof")
    if (__nat_blen(cert) == 0) != (__nat_blen(key) == 0):
        __dyn_err("ArgumentError", "'client' : certificat et clé client vont ensemble")
    if verify and __nat_blen(host) == 0:
        __dyn_err("ArgumentError", "'client' : vérifier le certificat exige un nom d'hôte (ou verify=false)")
    s := __alloc(32)
    __store64(s + 16, fd)
    __vm_c(__vm_tls_fn(37), 0, 0)
    __store64(s, __vm_c(__vm_tls_fn(3), __vm_c(__vm_tls_fn(1), 0, 0), 0))
    if __load64(s) == 0:
        return __vm_tls_error(0, "création du contexte TLS : ")
    ok := false
    r := 0
    try:
        __vm_tls_base(s)
        if not strict:
            __vm_c(__vm_tls_fn(6), __load64(s), 128)
        if verify:
            __vm_c6(__vm_tls_fn(7), __load64(s), 1, 0, 0, 0, 0)
            if __nat_blen(ca) > 0:
                if (__vm_c6(__vm_tls_fn(9), __load64(s), __nat_c(ca), 0, 0, 0, 0) & 4294967295) != 1:
                    __dyn_err("ArgumentError", "'client' : fichier d'autorités illisible '" + ca + "' : " + __vm_tls_drain(0))
            else:
                __vm_c(__vm_tls_fn(8), __load64(s), 0)
        else:
            __vm_c6(__vm_tls_fn(7), __load64(s), 0, 0, 0, 0, 0)
        if __nat_blen(cert) > 0:
            __vm_tls_files(s, "client", cert, key)
        if __nat_blen(alpn) > 0:
            __vm_c6(__vm_tls_fn(13), __load64(s), __nat_bp(alpn), __nat_blen(alpn), 0, 0, 0)
        __store64(s + 8, __vm_c(__vm_tls_fn(15), __load64(s), 0))
        if __load64(s + 8) == 0:
            r = __vm_tls_error(0, "création de la session TLS : ")
        else:
            __vm_c(__vm_tls_fn(17), __load64(s + 8), fd)
            if __nat_blen(host) > 0:
                hc := __nat_c(host)
                if __vm_tls_looks_ip(host):
                    if verify:
                        __vm_c(__vm_tls_fn(28), __vm_c(__vm_tls_fn(27), __load64(s + 8), 0), hc)
                else:
                    __vm_c6(__vm_tls_fn(25), __load64(s + 8), 55, 0, hc, 0, 0)
                    if verify:
                        __vm_c(__vm_tls_fn(26), __load64(s + 8), hc)
            r = __vm_tls_handshake(s, false, d)
            ok = __dyn_is(r, 1) and __dyn_iv(r) == 0
    catch e:
        __vm_tls_free(s)
        __rt_throw(__addr(e))
    if not ok:
        __vm_tls_free(s)
        return r
    return __vm_tls_adopt(s)

# server(fd, certificat, clé, alpn|null, délai)
func __vm_nat__native_tls__server(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __vm_tls_off()
    __nat_exact("server", n, 5)
    __vm_tls_require("server")
    fd := __nat_int("server", a0, "le descripteur")
    cert := __nat_cstr("server", a1, "le certificat")
    key := __nat_cstr("server", a2, "la clé privée")
    alpn := ""
    if a3 != 0:
        alpn = __vm_tls_alpn_wire("server", a3)
    d := __vm_tls_deadline("server", a4)
    s := __alloc(32)
    __store64(s + 16, fd)
    __vm_c(__vm_tls_fn(37), 0, 0)
    __store64(s, __vm_c(__vm_tls_fn(3), __vm_c(__vm_tls_fn(2), 0, 0), 0))
    if __load64(s) == 0:
        return __vm_tls_error(0, "création du contexte TLS : ")
    ok := false
    r := 0
    try:
        __vm_tls_base(s)
        __vm_c(__vm_tls_fn(6), __load64(s), 128)
        __vm_tls_files(s, "server", cert, key)
        if __nat_blen(alpn) > 0:
            cell := __alloc(8)
            __store64(cell, __str_addr(alpn))
            __store64(s + 24, cell)
            __vm_c6(__vm_tls_fn(14), __load64(s), __fnaddr("__vm_tls_alpn_select"), cell, 0, 0, 0)
        __store64(s + 8, __vm_c(__vm_tls_fn(15), __load64(s), 0))
        if __load64(s + 8) == 0:
            r = __vm_tls_error(0, "création de la session TLS : ")
        else:
            __vm_c(__vm_tls_fn(17), __load64(s + 8), fd)
            r = __vm_tls_handshake(s, true, d)
            ok = __dyn_is(r, 1) and __dyn_iv(r) == 0
    catch e:
        __vm_tls_free(s)
        __rt_throw(__addr(e))
    if not ok:
        __vm_tls_free(s)
        return r
    return __vm_tls_adopt(s)

# Deux str identiques ?
func __vm_tls_same(a: str, b: str) -> bool:
    n := __nat_blen(a)
    if n != __nat_blen(b):
        return false
    pa := __nat_bp(a)
    pb := __nat_bp(b)
    i := 0
    while i < n:
        if __load8(pa + i) != __load8(pb + i):
            return false
        i += 1
    return true

# Contexte serveur PARTAGÉ pour (certificat, clé, ALPN) : créé une fois, recréé quand stamp change (certificat
# renouvelé ; l'ancien vit tant que des sessions le référencent : SSL_CTX compte ses références). tkeys :
# 80 octets de clés de tickets (nom, HMAC, AES), communes à tous les processus, ou "" (clés tirées au hasard
# par OpenSSL). Entrée : [contexte, cellule ALPN, stamp]. Table : état de la VM, décalage 320.
func __vm_tls_shared_ctx(fn: str, cert: str, key: str, alpn: str, stamp: str, tkeys: str) -> int:
    d := __vm_ffi_tab(320)
    k := cert + "\n" + key + "\n" + alpn
    idx := __rt_dict_index(d, __str_addr(k), 1)
    if idx >= 0:
        e := __load64(__load64(d + 32) + 8 * idx)
        if __vm_tls_same(__as_str(__load64(e + 16)), stamp):
            return __load64(e)
        __vm_c(__vm_tls_fn(4), __load64(e), 0)
        __rt_dict_remove(d, __str_addr(k), 1)
    t := __alloc(32)
    __vm_c(__vm_tls_fn(37), 0, 0)
    __store64(t, __vm_c(__vm_tls_fn(3), __vm_c(__vm_tls_fn(2), 0, 0), 0))
    if __load64(t) == 0:
        __dyn_err("IoError", "'" + fn + "' : création du contexte TLS : " + __vm_tls_drain(0))
    try:
        __vm_tls_base(t)
        __vm_c(__vm_tls_fn(6), __load64(t), 128)
        __vm_tls_files(t, fn, cert, key)
        if __nat_blen(alpn) > 0:
            cell := __alloc(8)
            __store64(cell, __str_addr(alpn))
            __store64(t + 8, cell)
            __vm_c6(__vm_tls_fn(14), __load64(t), __fnaddr("__vm_tls_alpn_select"), cell, 0, 0, 0)
        if __nat_blen(tkeys) == 80:
            # SSL_CTRL_SET_TLSEXT_TICKET_KEYS (59)
            __vm_c6(__vm_tls_fn(5), __load64(t), 59, 80, __nat_bp(tkeys), 0, 0)
    catch e2:
        __vm_c(__vm_tls_fn(4), __load64(t), 0)
        __rt_throw(__addr(e2))
    __store64(t + 16, __str_addr(stamp))
    __store64(t + 24, __str_addr(k))
    __rt_dict_set(d, __str_addr(k), t, 1)
    return __load64(t)

# server_start(fd, cert, key, alpn[, stamp, tkeys]) : session serveur prête, SANS poignée de main ; handle à
# faire avancer par accept_step (boucle d'événements : web.server), puis comme celui de server. Avec stamp
# (empreinte des fichiers, str) : contexte partagé entre les connexions (__vm_tls_shared_ctx : certificat lu
# une fois, tickets de session valables d'une connexion à l'autre ; tkeys : clés des tickets).
func __vm_nat__native_tls__server_start(n: int, a0: int, a1: int, a2: int, a3: int, a4: int, a5: int) -> int:
    __vm_tls_off()
    __nat_range("server_start", n, 4, 6)
    __vm_tls_require("server_start")
    fd := __nat_int("server_start", a0, "le descripteur")
    cert := __nat_cstr("server_start", a1, "le certificat")
    key := __nat_cstr("server_start", a2, "la clé privée")
    alpn := ""
    if a3 != 0:
        alpn = __vm_tls_alpn_wire("server_start", a3)
    if n >= 5 and a4 != 0:
        stamp := __nat_str("server_start", a4, "l'empreinte")
        tkeys := ""
        if n >= 6 and a5 != 0:
            tkeys = __nat_str("server_start", a5, "les clés de tickets")
        ctx := __vm_tls_shared_ctx("server_start", cert, key, alpn, stamp, tkeys)
        sh := __alloc(32)
        __store64(sh + 16, fd)
        __store64(sh + 8, __vm_c(__vm_tls_fn(15), ctx, 0))
        if __load64(sh + 8) == 0:
            return __vm_tls_error(0, "création de la session TLS : ")
        __vm_c(__vm_tls_fn(17), __load64(sh + 8), fd)
        return __vm_tls_adopt(sh)
    s := __alloc(32)
    __store64(s + 16, fd)
    __vm_c(__vm_tls_fn(37), 0, 0)
    __store64(s, __vm_c(__vm_tls_fn(3), __vm_c(__vm_tls_fn(2), 0, 0), 0))
    if __load64(s) == 0:
        return __vm_tls_error(0, "création du contexte TLS : ")
    try:
        __vm_tls_base(s)
        __vm_c(__vm_tls_fn(6), __load64(s), 128)
        __vm_tls_files(s, "server_start", cert, key)
        if __nat_blen(alpn) > 0:
            cell := __alloc(8)
            __store64(cell, __str_addr(alpn))
            __store64(s + 24, cell)
            __vm_c6(__vm_tls_fn(14), __load64(s), __fnaddr("__vm_tls_alpn_select"), cell, 0, 0, 0)
        __store64(s + 8, __vm_c(__vm_tls_fn(15), __load64(s), 0))
    catch e:
        __vm_tls_free(s)
        __rt_throw(__addr(e))
    if __load64(s + 8) == 0:
        r := __vm_tls_error(0, "création de la session TLS : ")
        __vm_tls_free(s)
        return r
    __vm_c(__vm_tls_fn(17), __load64(s + 8), fd)
    return __vm_tls_adopt(s)

# accept_step(handle) : UN essai de poignée de main serveur, sans attendre : 0 terminée, 1 attend que le socket
# soit lisible, 2 qu'il soit inscriptible ; échec : [message, 0] ou -errno, comme server (fermer le handle).
func __vm_nat__native_tls__accept_step(n: int, a0: int) -> int:
    __vm_tls_off()
    __nat_exact("accept_step", n, 1)
    s := __vm_tls_session("accept_step", a0)
    __vm_c(__vm_tls_fn(37), 0, 0)
    __vm_tls_clear_errno()
    r := __vm_c(__vm_tls_fn(19), __load64(s + 8), 0)
    r = ((r & 4294967295) ^ 2147483648) - 2147483648
    if r == 1:
        return __dyn_int(0)
    err := __vm_c(__vm_tls_fn(23), __load64(s + 8), r) & 4294967295
    en := __vm_tls_errno()
    if err == 2:
        return __dyn_int(1)
    if err == 3:
        return __dyn_int(2)
    if err == 5 and en != 0 and en != 4 and en != 11:
        return __dyn_int(0 - en)
    if err == 5 and (en == 4 or en == 11):
        return __dyn_int(1)
    if err == 5 or err == 6:
        l := __dyn_list_new(0)
        __dyn_list_push(l, __dyn_str("poignée de main TLS : connexion fermée par l'autre extrémité"))
        __dyn_list_push(l, __dyn_int(0))
        return l
    return __vm_tls_error(s, "poignée de main TLS : ")

func __vm_nat__native_tls__read(n: int, a0: int, a1: int, a2: int) -> int:
    __vm_tls_off()
    __nat_exact("read", n, 3)
    s := __vm_tls_session("read", a0)
    mx := __nat_int("read", a1, "la taille")
    if mx < 1 or mx > 67108864:
        __dyn_err("ArgumentError", "'read' : taille hors de 1..64 Mio")
    d := __vm_tls_deadline("read", a2)
    buf := __alloc_raw(mx)
    while true:
        __vm_c(__vm_tls_fn(37), 0, 0)
        __vm_tls_clear_errno()
        k := __vm_c6(__vm_tls_fn(20), __load64(s + 8), buf, mx, 0, 0, 0)
        k = ((k & 4294967295) ^ 2147483648) - 2147483648
        if k > 0:
            return __dyn_str(__nat_make(buf, k))
        err := __vm_c(__vm_tls_fn(23), __load64(s + 8), k) & 4294967295
        en := __vm_tls_errno()
        if err == 6:
            return __dyn_str("")
        if err == 2:
            if not __vm_tls_wait(__load64(s + 16), 1, d):
                return __dyn_int(__vm_tls_expired(d))
        elif err == 3:
            if not __vm_tls_wait(__load64(s + 16), 4, d):
                return __dyn_int(__vm_tls_expired(d))
        elif err == 5 and en != 0 and en != 4:
            return __dyn_int(0 - en)
        elif err == 5 and en == 0 and k == 0:
            return __vm_tls_error(s, "lecture TLS : connexion coupée sans close_notify : ")
        else:
            return __vm_tls_error(s, "lecture TLS : ")
    return 0

func __vm_nat__native_tls__write(n: int, a0: int, a1: int, a2: int) -> int:
    __vm_tls_off()
    __nat_exact("write", n, 3)
    s := __vm_tls_session("write", a0)
    data := __nat_str("write", a1, "les données")
    d := __vm_tls_deadline("write", a2)
    done := 0
    total := __nat_blen(data)
    while done < total:
        chunk := total - done
        if chunk > 1048576:
            chunk = 1048576
        __vm_c(__vm_tls_fn(37), 0, 0)
        __vm_tls_clear_errno()
        k := __vm_c6(__vm_tls_fn(21), __load64(s + 8), __nat_bp(data) + done, chunk, 0, 0, 0)
        k = ((k & 4294967295) ^ 2147483648) - 2147483648
        if k > 0:
            done += k
            continue
        err := __vm_c(__vm_tls_fn(23), __load64(s + 8), k) & 4294967295
        en := __vm_tls_errno()
        if err == 3 or err == 2:
            ev := 4
            if err == 2:
                ev = 1
            if not __vm_tls_wait(__load64(s + 16), ev, d):
                if done > 0:
                    return __dyn_int(done)
                return __dyn_int(__vm_tls_expired(d))
        elif err == 5 and en != 0 and en != 4:
            return __dyn_int(0 - en)
        else:
            return __vm_tls_error(s, "écriture TLS : ")
    return __dyn_int(done)

func __vm_nat__native_tls__pending(n: int, a0: int) -> int:
    __vm_tls_off()
    __nat_exact("pending", n, 1)
    s := __vm_tls_session("pending", a0)
    return __dyn_int(((__vm_c(__vm_tls_fn(24), __load64(s + 8), 0) & 4294967295) ^ 2147483648) - 2147483648)

func __vm_nat__native_tls__shutdown(n: int, a0: int, a1: int) -> int:
    __vm_tls_off()
    __nat_exact("shutdown", n, 2)
    s := __vm_tls_session("shutdown", a0)
    d := __vm_tls_deadline("shutdown", a1)
    tries := 0
    while tries < 2:
        __vm_c(__vm_tls_fn(37), 0, 0)
        __vm_tls_clear_errno()
        r := ((__vm_c(__vm_tls_fn(22), __load64(s + 8), 0) & 4294967295) ^ 2147483648) - 2147483648
        if r >= 0:
            return __dyn_int(0)
        err := __vm_c(__vm_tls_fn(23), __load64(s + 8), r) & 4294967295
        en := __vm_tls_errno()
        if err == 3:
            if not __vm_tls_wait(__load64(s + 16), 4, d):
                return __dyn_int(__vm_tls_expired(d))
        elif err == 2:
            if not __vm_tls_wait(__load64(s + 16), 1, d):
                return __dyn_int(__vm_tls_expired(d))
        elif err == 5 and en != 0:
            return __dyn_int(0 - en)
        else:
            __vm_c(__vm_tls_fn(37), 0, 0)
            return __dyn_int(0)
        tries += 1
    return __dyn_int(0)

func __vm_nat__native_tls__close(n: int, a0: int) -> int:
    __vm_tls_off()
    __nat_exact("close", n, 1)
    h := __nat_int("close", a0, "le handle")
    s := __vm_ffi_get(192, h)
    if s != 0:
        __vm_tls_free(s)
        __vm_ffi_del(192, h)
    return 0

func __vm_tls_name_line(nm: int) -> int:
    buf := __alloc_raw(1024)
    if __vm_c6(__vm_tls_fn(40), nm, buf, 1024, 0, 0, 0) == 0:
        return 0
    return __dyn_str(__nat_from_c(buf))

func __vm_nat__native_tls__info(n: int, a0: int) -> int:
    __vm_tls_off()
    __nat_exact("info", n, 1)
    s := __vm_tls_session("info", a0)
    ssl := __load64(s + 8)
    l := __dyn_list_new(0)
    ver := __vm_c(__vm_tls_fn(30), ssl, 0)
    c := __vm_c(__vm_tls_fn(31), ssl, 0)
    cn := 0
    if c != 0:
        cn = __vm_c(__vm_tls_fn(32), c, 0)
    pp := __alloc_raw(16)
    __vm_c6(__vm_tls_fn(33), ssl, pp, pp + 8, 0, 0, 0)
    if ver != 0:
        __dyn_list_push(l, __dyn_str(__nat_from_c(ver)))
    else:
        __dyn_list_push(l, __dyn_str(""))
    if cn != 0:
        __dyn_list_push(l, __dyn_str(__nat_from_c(cn)))
    else:
        __dyn_list_push(l, __dyn_str(""))
    plen := __load32(pp + 8)
    if __load64(pp) != 0 and plen > 0:
        __dyn_list_push(l, __dyn_str(__nat_make(__load64(pp), plen)))
    else:
        __dyn_list_push(l, 0)
    __dyn_list_push(l, __dyn_int(__vm_c(__vm_tls_fn(29), ssl, 0)))
    subject := 0
    issuer := 0
    cert := __vm_c(__vm_tls_fn(43), ssl, 0)
    if cert != 0:
        subject = __vm_tls_name_line(__vm_c(__vm_tls_fn(38), cert, 0))
        issuer = __vm_tls_name_line(__vm_c(__vm_tls_fn(39), cert, 0))
        __vm_c(__vm_tls_fn(41), cert, 0)
    __dyn_list_push(l, subject)
    __dyn_list_push(l, issuer)
    __dyn_list_push(l, __dyn_bool((__vm_c(__vm_tls_fn(34), ssl, 0) & 2) != 0))
    return l

func __vm_tls_crypto_ready() -> bool:
    return __vm_tls_load() and __vm_tls_fn(46) != 0 and __vm_tls_fn(47) != 0 and __vm_tls_fn(48) != 0 and __vm_tls_fn(49) != 0

func __vm_tls_digest_of(fn: str, v: int) -> int:
    name := __nat_cstr(fn, v, "l'algorithme")
    if not (name == "md5" or name == "sha1" or name == "sha224" or name == "sha256" or name == "sha384" or name == "sha512"):
        __dyn_err("ArgumentError", "'" + fn + "' : algorithme inconnu '" + name + "' (md5, sha1, sha224, sha256, sha384, sha512)")
    md := __vm_c(__vm_tls_fn(46), __nat_c(name), 0)
    if md == 0:
        __dyn_err("ArgumentError", "'" + fn + "' : algorithme indisponible '" + name + "'")
    return md

func __vm_nat__native_tls__digest(n: int, a0: int, a1: int) -> int:
    __vm_tls_off()
    __nat_exact("digest", n, 2)
    if not __vm_tls_crypto_ready():
        return 0
    md := __vm_tls_digest_of("digest", a0)
    data := __nat_str("digest", a1, "les données")
    out := __alloc_raw(64)
    ln := __alloc_raw(8)
    if (__vm_c6(__vm_tls_fn(47), __nat_bp(data), __nat_blen(data), out, ln, md, 0) & 4294967295) == 0:
        return 0
    return __dyn_str(__nat_make(out, __load32(ln)))

func __vm_nat__native_tls__hmac(n: int, a0: int, a1: int, a2: int) -> int:
    __vm_tls_off()
    __nat_exact("hmac", n, 3)
    if not __vm_tls_crypto_ready():
        return 0
    md := __vm_tls_digest_of("hmac", a0)
    key := __nat_str("hmac", a1, "la clé")
    data := __nat_str("hmac", a2, "les données")
    out := __alloc_raw(64)
    ln := __alloc_raw(8)
    fr := __alloc_raw(176)
    __store64(fr, md)
    __store64(fr + 8, __nat_bp(key))
    __store64(fr + 16, __nat_blen(key))
    __store64(fr + 24, __nat_bp(data))
    __store64(fr + 32, __nat_blen(data))
    __store64(fr + 40, out)
    __store64(fr + 112, 1)
    __store64(fr + 160, ln)
    if __vm_sysv(__vm_tls_fn(48), fr) == 0:
        return 0
    return __dyn_str(__nat_make(out, __load32(ln)))

func __vm_nat__native_tls__pbkdf2(n: int, a0: int, a1: int, a2: int, a3: int, a4: int) -> int:
    __vm_tls_off()
    __nat_exact("pbkdf2", n, 5)
    if not __vm_tls_crypto_ready():
        return 0
    md := __vm_tls_digest_of("pbkdf2", a0)
    pw := __nat_str("pbkdf2", a1, "le mot de passe")
    salt := __nat_str("pbkdf2", a2, "le sel")
    it := __nat_int("pbkdf2", a3, "le nombre d'itérations")
    len := __nat_int("pbkdf2", a4, "la longueur")
    if it < 1 or it > 100000000:
        __dyn_err("ArgumentError", "'pbkdf2' : itérations hors de 1..10^8")
    if len < 1 or len > 1024:
        __dyn_err("ArgumentError", "'pbkdf2' : longueur hors de 1..1024")
    out := __alloc_raw(len)
    fr := __alloc_raw(184)
    __store64(fr, __nat_bp(pw))
    __store64(fr + 8, __nat_blen(pw))
    __store64(fr + 16, __nat_bp(salt))
    __store64(fr + 24, __nat_blen(salt))
    __store64(fr + 32, it)
    __store64(fr + 40, md)
    __store64(fr + 112, 2)
    __store64(fr + 160, len)
    __store64(fr + 168, out)
    if (__vm_sysv(__vm_tls_fn(49), fr) & 4294967295) == 0:
        return 0
    return __dyn_str(__nat_make(out, len))

func __vm_nat__native_tls__peer_certificate(n: int, a0: int) -> int:
    __vm_tls_off()
    __nat_exact("peer_certificate", n, 1)
    s := __vm_tls_session("peer_certificate", a0)
    if __vm_tls_fn(45) == 0 or __vm_tls_fn(50) == 0:
        __dyn_err("IoError", "'peer_certificate' : i2d_X509 absent d'OpenSSL")
    cert := __vm_c(__vm_tls_fn(43), __load64(s + 8), 0)
    if cert == 0:
        return 0
    pp := __alloc_raw(8)
    k := ((__vm_c(__vm_tls_fn(45), cert, pp) & 4294967295) ^ 2147483648) - 2147483648
    __vm_c(__vm_tls_fn(41), cert, 0)
    if k <= 0 or __load64(pp) == 0:
        return 0
    out := __dyn_str(__nat_make(__load64(pp), k))
    __vm_c6(__vm_tls_fn(50), __load64(pp), __nat_c("vm.al"), 0, 0, 0, 0)
    return out

func __vm_nat__native_tls__live_count(n: int) -> int:
    __vm_tls_off()
    __nat_exact("live_count", n, 0)
    return __dyn_int(__load64(__vm_ffi_tab(192)))

# ---- Profileur (alexc run --profile ; src/tooling/Profiler.cpp) -------------------------------------------------------
# Mesure exacte à chaque instruction : temps propre et instructions par fonction et par ligne, appels et temps inclusif
# par fonction, pile fantôme alignée sur la profondeur d'appel. État de la VM : [208] actif  [216] rapport JSON
# [224] pile fantôme [descripteur][entrée]  [232] lignes ((id << 32) | ligne -> [instructions][temps])
# [240] instructions  [248] début  [256] dernière mesure  [264] commencé  [272] dernière fonction  [280] dernière ligne

func __vm_now() -> float:
    ts := __alloc_raw(16)
    if __alexos():
        __syscall(228, 1, ts)
        return __i2f(__load64(ts)) + __i2f(__load64(ts + 8)) * 0.000000001
    if __windows():
        __syscall(228, 1, ts)
    else:
        __vm_c(__vm_imp(5), 1, ts)
    return __i2f(__load64(ts)) + __i2f(__load64(ts + 8)) * 0.000000001

func __vm_fadd(p: int, x: float):
    __store64(p, __f2bits(__bits2f(__load64(p)) + x))

func __vm_prof_line(d: int, line: int) -> int:
    vs := __vm_st()
    t := __load64(vs + 232)
    if t == 0:
        t = __rt_dict_new(64)
        __store64(vs + 232, t)
    key := (__load64(d + 104) << 32) | line
    e := __rt_dict_index(t, key, 0)
    if e >= 0:
        return __load64(__load64(t + 32) + 8 * e)
    r := __alloc_raw(32)
    __store64(r + 16, d)
    __store64(r + 24, line)
    __rt_dict_set(t, key, r, 0)
    return r

func __vm_prof_pop(depth: int, now: float):
    vs := __vm_st()
    st := __load64(vs + 224)
    while __load64(st) > depth:
        n := __load64(st) - 1
        e := __rt_vec_at(st, n)
        __store64(st, n)
        d := __load64(e)
        __store64(d + 208, __load64(d + 208) - 1)
        if __load64(d + 208) == 0:
            __vm_fadd(d + 200, now - __bits2f(__load64(e + 8)))

func __vm_prof(fr: int, ip: int):
    vs := __vm_st()
    d := __load64(fr + 8)
    depth := __load64(__dyn_ds() + 80)
    now := __vm_now()
    if __load64(vs + 264) == 0:
        __store64(vs + 264, 1)
        __store64(vs + 248, __f2bits(now))
        __store64(vs + 256, __f2bits(now))
        __store64(vs + 224, __rt_list_new(0))
    dt := now - __bits2f(__load64(vs + 256))
    __store64(vs + 256, __f2bits(now))
    ld := __load64(vs + 272)
    if ld != 0:
        __vm_fadd(ld + 192, dt)
        __vm_fadd(__vm_prof_line(ld, __load64(vs + 280)) + 8, dt)
    st := __load64(vs + 224)
    if depth < __load64(st):
        __vm_prof_pop(depth, now)
    if depth == __load64(st) and __load64(st) > 0 and __load64(__rt_vec_at(st, __load64(st) - 1)) != d:
        __vm_prof_pop(depth - 1, now)
    while __load64(st) < depth:
        e := __alloc(16)
        __store64(e, d)
        __store64(e + 8, __f2bits(now))
        __rt_list_push(st, e)
        __store64(d + 176, __load64(d + 176) + 1)
        __store64(d + 208, __load64(d + 208) + 1)
    line := 0
    idx := (ip - __load64(d)) >> 5
    if idx >= 0 and idx < __load64(d + 8):
        line = __load64(__load64(d + 48) + 8 * idx)
    __store64(d + 184, __load64(d + 184) + 1)
    lr := __vm_prof_line(d, line)
    __store64(lr, __load64(lr) + 1)
    __store64(vs + 240, __load64(vs + 240) + 1)
    __store64(vs + 272, d)
    __store64(vs + 280, line)

# Nom du profileur : sans qualificatif ni suffixe, « # » -> « . », « $entry » -> « <module> » ; caché si « $... ».
func __vm_prof_name(d: int) -> str:
    n := __dyn_fn_display(__as_str(__load64(d + 32)))
    sb := __rt_sb_new()
    i := 0
    while i < __nat_blen(n):
        c := __load8(__nat_bp(n) + i)
        if c == 35:
            c = 46
        __rt_sb_byte(sb, c)
        i += 1
    r := __rt_sb_str(sb)
    if r == "$entry":
        return "<module>"
    return r

func __vm_prof_hidden(d: int) -> bool:
    n := __vm_prof_name(d)
    return __nat_blen(n) > 0 and __load8(__nat_bp(n)) == 36

func __vm_prof_file(d: int) -> str:
    f := __as_str(__load64(d + 40))
    if f == "<inconnu>":
        return ""
    return f

func __vm_fixed3(x: float, width: int) -> str:
    neg := x < 0.0
    if neg:
        x = 0.0 - x
    v := __f2i(x * 1000.0 + 0.5)
    fr := __int_to_str(v % 1000)
    while __nat_blen(fr) < 3:
        fr = "0" + fr
    s := __int_to_str(v // 1000) + "." + fr
    if neg:
        s = "-" + s
    while __nat_blen(s) < width:
        s = " " + s
    return s

func __vm_lpad(s: str, width: int) -> str:
    r := s
    while __nat_blen(r) < width:
        r = " " + r
    return r

func __vm_json_num(x: float) -> str:
    if x == __rt_floor(x) and x < 9000000000000000.0 and x > -9000000000000000.0:
        return __int_to_str(__f2i(x))
    return __dyn_display(__dyn_float(x))

func __vm_json_str(s: str) -> str:
    sb := __rt_sb_new()
    __rt_sb_byte(sb, 34)
    i := 0
    hex := "0123456789abcdef"
    while i < __nat_blen(s):
        c := __load8(__nat_bp(s) + i)
        if c == 34 or c == 92:
            __rt_sb_byte(sb, 92)
            __rt_sb_byte(sb, c)
        elif c == 10:
            __rt_sb_add(sb, "\\n")
        elif c == 13:
            __rt_sb_add(sb, "\\r")
        elif c == 9:
            __rt_sb_add(sb, "\\t")
        elif c < 32:
            __rt_sb_add(sb, "\\u00")
            __rt_sb_byte(sb, __load8(__nat_bp(hex) + (c >> 4)))
            __rt_sb_byte(sb, __load8(__nat_bp(hex) + (c & 15)))
        else:
            __rt_sb_byte(sb, c)
        i += 1
    __rt_sb_byte(sb, 34)
    return __rt_sb_str(sb)

func __vm_basename(f: str) -> str:
    k := __nat_blen(f) - 1
    while k >= 0:
        c := __load8(__nat_bp(f) + k)
        if c == 47 or c == 92:
            return __vm_after(f, k + 1)
        k -= 1
    return f

# Tri par temps propre décroissant (descripteurs : [192], lignes : [8]) ; tri par insertion, stable.
func __vm_prof_sort(l: int, off: int):
    n := __load64(l)
    dt := __load64(l + 16)
    i := 1
    while i < n:
        v := __load64(dt + 8 * i)
        j := i - 1
        while j >= 0 and __bits2f(__load64(__load64(dt + 8 * j) + off)) < __bits2f(__load64(v + off)):
            __store64(dt + 8 * (j + 1), __load64(dt + 8 * j))
            j -= 1
        __store64(dt + 8 * (j + 1), v)
        i += 1

func __vm_prof_report():
    vs := __vm_st()
    if __load64(vs + 208) != 1:
        return
    __store64(vs + 208, 0)
    now := __vm_now()
    elapsed := 0.0
    if __load64(vs + 264) != 0:
        ld := __load64(vs + 272)
        if ld != 0:
            dt := now - __bits2f(__load64(vs + 256))
            __vm_fadd(ld + 192, dt)
            __vm_fadd(__vm_prof_line(ld, __load64(vs + 280)) + 8, dt)
        __vm_prof_pop(0, now)
        elapsed = now - __bits2f(__load64(vs + 248))
    fns := __rt_list_new(0)
    i := 0
    while i < __load64(vs + 24):
        d := __load64(__load64(vs + 16) + 8 * i)
        if (__load64(d + 184) > 0 or __load64(d + 176) > 0) and not __vm_prof_hidden(d):
            __rt_list_push(fns, d)
        i += 1
    __vm_prof_sort(fns, 192)
    lines := __rt_list_new(0)
    t := __load64(vs + 232)
    if t != 0:
        e := 0
        while e < __load64(t + 8):
            if __load64(__load64(t + 40) + 8 * e) >= 0:
                key := __load64(__load64(t + 24) + 8 * e)
                r := __load64(__load64(t + 32) + 8 * e)
                if (key & 4294967295) != 0 and not __vm_prof_hidden(__load64(r + 16)):
                    __rt_list_push(lines, r)
            e += 1
    __vm_prof_sort(lines, 8)
    # rapport lisible
    sb := __rt_sb_new()
    __rt_sb_add(sb, "\n== Profil ALEX : " + __vm_fixed3(elapsed, 0) + " s, " + __int_to_str(__load64(vs + 240)) + " instructions ==\n")
    __rt_sb_add(sb, "  temps propre   temps total    appels  instructions  fonction\n")
    i = 0
    while i < __load64(fns) and i < 15:
        d := __rt_vec_at(fns, i)
        fl := 0
        if __load64(d + 144) > 0:
            fl = __load64(__load64(d + 136) + 8)
        __rt_sb_add(sb, "  " + __vm_fixed3(__bits2f(__load64(d + 192)) * 1000.0, 9) + " ms  " + __vm_fixed3(__bits2f(__load64(d + 200)) * 1000.0, 9) + " ms  " + __vm_lpad(__int_to_str(__load64(d + 176)), 8) + "  " + __vm_lpad(__int_to_str(__load64(d + 184)), 12) + "  " + __vm_prof_name(d) + " (" + __vm_basename(__vm_prof_file(d)) + ":" + __int_to_str(fl) + ")\n")
        i += 1
    __rt_sb_add(sb, "  lignes les plus coûteuses :\n")
    i = 0
    while i < __load64(lines) and i < 8 and i < 15:
        r := __rt_vec_at(lines, i)
        d := __load64(r + 16)
        __rt_sb_add(sb, "  " + __vm_fixed3(__bits2f(__load64(r + 8)) * 1000.0, 9) + " ms  " + __vm_lpad(__int_to_str(__load64(r)), 12) + " instr.  " + __vm_basename(__vm_prof_file(d)) + ":" + __int_to_str(__vm_prof_key_line(t, r)) + " (" + __vm_prof_name(d) + ")\n")
        i += 1
    __write_err(__rt_sb_str(sb))
    if __load64(vs + 216) == 0:
        return
    js := __rt_sb_new()
    __rt_sb_add(js, "{\"version\":1,\"elapsed\":" + __vm_json_num(elapsed) + ",\"instructions\":" + __int_to_str(__load64(vs + 240)) + ",\"functions\":[")
    i = 0
    while i < __load64(fns):
        d := __rt_vec_at(fns, i)
        fl := 0
        if __load64(d + 144) > 0:
            fl = __load64(__load64(d + 136) + 8)
        if i > 0:
            __rt_sb_add(js, ",")
        __rt_sb_add(js, "{\"name\":" + __vm_json_str(__vm_prof_name(d)) + ",\"file\":" + __vm_json_str(__vm_prof_file(d)) + ",\"line\":" + __int_to_str(fl) + ",\"calls\":" + __int_to_str(__load64(d + 176)) + ",\"instructions\":" + __int_to_str(__load64(d + 184)) + ",\"self\":" + __vm_json_num(__bits2f(__load64(d + 192))) + ",\"total\":" + __vm_json_num(__bits2f(__load64(d + 200))) + "}")
        i += 1
    __rt_sb_add(js, "],\"lines\":[")
    i = 0
    while i < __load64(lines) and i < 2000:
        r := __rt_vec_at(lines, i)
        d := __load64(r + 16)
        if i > 0:
            __rt_sb_add(js, ",")
        __rt_sb_add(js, "{\"file\":" + __vm_json_str(__vm_prof_file(d)) + ",\"line\":" + __int_to_str(__vm_prof_key_line(t, r)) + ",\"function\":" + __vm_json_str(__vm_prof_name(d)) + ",\"instructions\":" + __int_to_str(__load64(r)) + ",\"self\":" + __vm_json_num(__bits2f(__load64(r + 8))) + "}")
        i += 1
    __rt_sb_add(js, "]}\n")
    path := __as_str(__load64(vs + 216))
    fd := __syscall(2, __nat_c(path), 577, 420)
    if fd >= 0:
        __nat_write_fd(fd, __rt_sb_str(js))
        __syscall(3, fd)
    __write_err("  rapport JSON : " + path + "\n")

# Ligne d'une fiche de ligne.
func __vm_prof_key_line(t: int, r: int) -> int:
    return __load64(r + 24)
