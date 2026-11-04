# Test du module ffi : appels C (libc / libm), conversions, buffers, erreurs.
# x86-64 / arm64 POSIX ; ignoré ailleurs.

from core use len, type
from collections use append, clear
use string as s
use ffi as ffi

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func near(actual, expected, label):
    d := actual - expected
    if d < 0.0:
        d = 0.0 - d
    check(d < 0.000001, f"{label} : obtenu {actual}, attendu {expected}")

func raises1(f, a, error_type, label):
    got := "aucune erreur"
    try:
        f(a)
    catch e:
        got = e.type
    check_eq(got, error_type, label)

func run(name, fn):
    clear(notes)
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

libc := null
libm := null

# --- cibles des tests d'erreurs -------------------------------------
func _bind_missing(x):
    return libc.function("symbole_inexistant_xyz", [], "void")
func _bind_bad_type(x):
    return libc.function("abs", ["entier"], "i32")
func _bind_void_arg(x):
    return libc.function("abs", ["void"], "i32")
func _bind_too_many_ints(x):
    # 6 entiers en registres + 16 sur la pile au plus : 23 entiers sont refusés
    return libc.function("abs", ["i32" for k in 0..23], "i32")
func _bind_too_many_floats(x):
    # 8 flottants en registres + 16 sur la pile au plus : 25 flottants sont refusés
    return libc.function("abs", ["f64" for k in 0..25], "f64")
func _load_missing(x):
    return ffi.Library("bibliotheque_inexistante_xyz")
func _call_wrong_arity(f):
    return f.call([1, 2])
func _call_overflow_i32(f):
    return f.call([4294967296])
func _call_overflow_u8(f):
    return f.call([256])
func _call_wrong_type(f):
    return f.call(["texte"])
func _call_nul_in_cstr(f):
    return f.call(["a\0b"])
func _call_ptr_str(f):
    return f.call(["pas un pointeur"])
func _read_oob(b):
    return b.read("i32", 14)
func _read_negative(b):
    return b.read("i32", -1)
func _write_oob(b):
    return b.write("i64", 1, 12)
func _read_no_nul(b):
    return b.read_str(0)
func _bytes_oob(b):
    return b.read_bytes(10, 100)
func _alloc_zero(x):
    return ffi.Buffer(0)
func _bad_type_name(b):
    return b.read("nimporte", 0)
func _use_freed(b):
    return b.size()
func _u8_out_of_range(b):
    return b.write("u8", 300, 0)
func _use_closed_lib(l):
    return l.has("abs")
func _call_after_unload(f):
    return f.call([1])

func t_math():
    cos := libm.function("cos", ["f64"], "f64")
    near(cos.call([0.0]), 1.0, "cos(0)")
    near(cos.call1(3.141592653589793), -1.0, "cos(pi)")
    near(cos.call([1]), 0.5403023058681398, "int accepté pour f64")
    pow := libm.function("pow", ["f64", "f64"], "f64")
    check_eq(pow.call([2.0, 10.0]), 1024.0, "pow")
    fma := libm.function("fma", ["f64", "f64", "f64"], "f64")
    check_eq(fma.call([2.0, 3.0, 4.0]), 10.0, "fma (3 flottants)")

func t_mixed_classes():
    # Entiers et flottants entrelacés : chaque classe garde son ordre.
    ldexp := libm.function("ldexp", ["f64", "i32"], "f64")
    check_eq(ldexp.call([1.5, 4]), 24.0, "ldexp(double, int)")
    check_eq(ldexp.call([3.0, -1]), 1.5, "exposant négatif")

func t_float32():
    powf := libm.function("powf", ["f32", "f32"], "f32")
    check_eq(powf.call([2.0, 10.0]), 1024.0, "powf")
    sqrtf := libm.function("sqrtf", ["f32"], "f32")
    near(sqrtf.call([2.0]), 1.4142135, "sqrtf (précision float)")
    check(sqrtf.call([2.0]) != 1.4142135623730951, "résultat f32, pas f64")

func t_integers():
    abs_ := libc.function("abs", ["i32"], "i32")
    check_eq(abs_.call([-42]), 42, "abs")
    check_eq(abs_.call([-2147483647]), 2147483647, "i32 limite")
    labs := libc.function("labs", ["i64"], "i64")
    check_eq(labs.call([-9000000000]), 9000000000, "i64 > 2^32")
    toupper := libc.function("toupper", ["i32"], "i32")
    check_eq(toupper.call([97]), 65, "toupper")
    strtoul := libc.function("strtoul", ["cstr", "ptr", "i32"], "u64")
    check_eq(strtoul.call(["4294967296", null, 10]), 4294967296, "u64 via cstr + ptr null")

func t_u64_overflow():
    strtoul := libc.function("strtoul", ["cstr", "ptr", "i32"], "u64")
    got := "aucune erreur"
    try:
        strtoul.call(["-1", null, 10])
    catch e:
        got = e.type
    check_eq(got, "ValueError", "u64 > 2^63-1 refusé")
    # La même valeur lue en i64 est le motif de bits -1 : représentable.
    strtol := libc.function("strtol", ["cstr", "ptr", "i32"], "i64")
    check_eq(strtol.call(["-1", null, 10]), -1, "i64 -1")

func t_strings():
    strlen := libc.function("strlen", ["cstr"], "size_t")
    check_eq(strlen.call(["bonjour"]), 7, "strlen ASCII")
    check_eq(strlen.call(["héllo"]), 6, "strlen compte les octets UTF-8")
    getenv := libc.function("getenv", ["cstr"], "cstr")
    check_eq(getenv.call(["VARIABLE_INEXISTANTE_XYZ"]), null, "char* NULL -> null")
    check_eq(type(getenv.call(["PATH"])), "str", "char* -> str")
    strcmp := libc.function("strcmp", ["cstr", "cstr"], "i32")
    check_eq(strcmp.call(["a", "a"]), 0, "strcmp égal")
    check(strcmp.call(["a", "b"]) < 0, "strcmp inférieur")
    strchr := libc.function("strchr", ["cstr", "i32"], "ptr")
    check_eq(strchr.call(["abc", 122]), null, "ptr NULL -> null")

func t_out_param():
    # strtol(chaîne dans un Buffer, &fin, base) : fin - début = octets consommés.
    cs := ffi.cstring("ff zz")
    end := ffi.Buffer(8)
    strtol := libc.function("strtol", ["ptr", "ptr", "i32"], "i64")
    check_eq(strtol.call([cs.address(), end.address(), 16]), 255, "valeur")
    check_eq(end.read("ptr") - cs.address(), 2, "pointeur de fin")
    cs.free()
    end.free()

func t_memory_functions():
    a := ffi.Buffer(16)
    b := ffi.Buffer(16)
    a.write_array("i32", [10, 20, 30, 40])
    memcpy := libc.function("memcpy", ["ptr", "ptr", "size_t"], "ptr")
    r := memcpy.call([b.address(), a.address(), 16])
    check_eq(r, b.address(), "memcpy retourne dest")
    check_eq(b.read_array("i32", 4), [10, 20, 30, 40], "copie")
    memset := libc.function("memset", ["ptr", "i32", "size_t"], "ptr")
    memset.call([b.address(), 65, 3])
    check_eq(b.read_bytes(0, 3), "AAA", "memset")
    check_eq(b.read("u8", 3), 0, "octet suivant intact (poids fort de 10)")
    a.free()
    b.free()

func t_buffer_types():
    b := ffi.Buffer(64)
    check_eq(b.size(), 64, "taille")
    check_eq(b.read("i64", 0), 0, "initialisé à zéro")
    b.write("i8", -5, 0)
    check_eq(b.read("i8", 0), -5, "i8")
    check_eq(b.read("u8", 0), 251, "même octet en u8")
    b.write("u16", 65535, 2)
    check_eq(b.read("u16", 2), 65535, "u16")
    b.write("i32", -123456, 4)
    check_eq(b.read("i32", 4), -123456, "i32")
    b.write("u32", 4294967295, 8)
    check_eq(b.read("u32", 8), 4294967295, "u32")
    b.write("i64", -9000000000, 16)
    check_eq(b.read("i64", 16), -9000000000, "i64")
    b.write("f64", 3.5, 24)
    check_eq(b.read("f64", 24), 3.5, "f64")
    b.write("f32", 0.5, 32)
    check_eq(b.read("f32", 32), 0.5, "f32")
    b.write("ptr", 4096, 40)
    check_eq(b.read("ptr", 40), 4096, "ptr")
    b.write("ptr", null, 40)
    check_eq(b.read("ptr", 40), null, "ptr NULL <-> null")
    n := b.write_str("héllo", 48)
    check_eq(n, 7, "octets écrits (NUL compris)")
    check_eq(b.read_str(48), "héllo", "chaîne C")
    b.fill(7, 0, 4)
    check_eq(b.read("u32", 0), 117901063, "fill")
    b.fill()
    check_eq(b.read("i64", 16), 0, "fill complet")
    check_eq(b.write_array("i16", [1, 2, 3]), 6, "write_array")
    check_eq(b.read_array("i16", 3), [1, 2, 3], "read_array")
    b.free()

func t_buffer_errors():
    b := ffi.Buffer(16)
    raises1(_read_oob, b, "IndexError", "lecture hors buffer")
    raises1(_read_negative, b, "IndexError", "offset négatif")
    raises1(_write_oob, b, "IndexError", "écriture hors buffer")
    raises1(_bytes_oob, b, "IndexError", "read_bytes hors buffer")
    raises1(_bad_type_name, b, "ArgumentError", "type inconnu")
    raises1(_u8_out_of_range, b, "ArgumentError", "u8 hors bornes")
    b.fill(1)
    raises1(_read_no_nul, b, "ArgumentError", "chaîne sans NUL")
    raises1(_alloc_zero, null, "ArgumentError", "taille 0 refusée")
    b.free()
    b.free()  # idempotent
    raises1(_use_freed, b, "ArgumentError", "Buffer libéré")

func t_binding_errors():
    raises1(_bind_missing, null, "IoError", "symbole inexistant")
    raises1(_bind_bad_type, null, "ArgumentError", "type inconnu")
    raises1(_bind_void_arg, null, "ArgumentError", "void en argument")
    raises1(_bind_too_many_ints, null, "ArgumentError", "23 entiers")
    raises1(_bind_too_many_floats, null, "ArgumentError", "25 flottants")
    raises1(_load_missing, null, "IoError", "bibliothèque absente")

func t_call_errors():
    abs_ := libc.function("abs", ["i32"], "i32")
    raises1(_call_wrong_arity, abs_, "ArgumentError", "arité")
    raises1(_call_overflow_i32, abs_, "ArgumentError", "i32 hors bornes")
    raises1(_call_wrong_type, abs_, "TypeError", "str pour i32")
    strlen := libc.function("strlen", ["cstr"], "size_t")
    raises1(_call_nul_in_cstr, strlen, "ArgumentError", "NUL dans une cstr")
    toupper8 := libc.function("toupper", ["u8"], "i32")
    raises1(_call_overflow_u8, toupper8, "ArgumentError", "u8 hors bornes")
    # Refusé AVANT l'appel : free() n'est jamais exécutée avec une valeur invalide.
    free_ := libc.function("free", ["ptr"], "void")
    raises1(_call_ptr_str, free_, "TypeError", "str pour ptr")

func t_lifecycle():
    lib := ffi.Library("m")
    f := lib.function("cos", ["f64"], "f64")
    check_eq(f.call([0.0]), 1.0, "avant unload")
    check(lib.has("sin"), "has(sin)")
    check(not lib.has("symbole_inexistant_xyz"), "has(absent)")
    lib.close()
    raises1(_call_after_unload, f, "ArgumentError", "Function invalide après close()")
    raises1(_use_closed_lib, lib, "ArgumentError", "Library fermée")
    lib.close()  # idempotent

func t_resources():
    before := ffi.live_counts()
    b := ffi.Buffer(8)
    lib := ffi.Library("m")
    f := lib.function("sin", ["f64"], "f64")
    mid := ffi.live_counts()
    check_eq(mid["buffers"], before["buffers"] + 1, "buffer compté")
    check_eq(mid["libraries"], before["libraries"] + 1, "bibliothèque comptée")
    check_eq(mid["functions"], before["functions"] + 1, "fonction comptée")
    b.free()
    lib.close()
    after := ffi.live_counts()
    check_eq(after["buffers"], before["buffers"], "buffer libéré")
    check_eq(after["libraries"], before["libraries"], "bibliothèque déchargée")
    check_eq(after["functions"], before["functions"], "fonctions invalidées avec la bibliothèque")

func t_sizeof():
    check_eq(ffi.sizeof("i8"), 1, "i8")
    check_eq(ffi.sizeof("short"), 2, "short")
    check_eq(ffi.sizeof("int"), 4, "int")
    check_eq(ffi.sizeof("float"), 4, "float")
    check_eq(ffi.sizeof("double"), 8, "double")
    check_eq(ffi.sizeof("size_t"), 8, "size_t")
    check_eq(ffi.sizeof("char*"), 8, "char*")

func t_void_and_aliases():
    srand := libc.function("srand", ["uint"], "void")
    check_eq(srand.call([42]), null, "void -> null")
    rand := libc.function("rand", [], "int")
    a := rand.call()
    srand.call([42])
    check_eq(rand.call(), a, "rand reproductible après srand")
    check_eq(libc.call("abs", ["int"], "int", [-3]), 3, "Library.call raccourci")

func main():
    global_before := ffi.live_counts()
    run("libm : appels flottants", t_math)
    run("entiers/flottants entrelacés", t_mixed_classes)
    run("f32 : arguments et retour", t_float32)
    run("entiers signés/non signés", t_integers)
    run("u64 > 2^63-1 refusé", t_u64_overflow)
    run("chaînes C et pointeurs NULL", t_strings)
    run("paramètre de sortie (strtol)", t_out_param)
    run("memcpy / memset sur Buffer", t_memory_functions)
    run("Buffer : tous les types", t_buffer_types)
    run("Buffer : erreurs et bornes", t_buffer_errors)
    run("liaison : erreurs", t_binding_errors)
    run("appel : erreurs de type, bornes, arité", t_call_errors)
    run("cycle de vie Library / Function", t_lifecycle)
    run("comptage des ressources", t_resources)
    run("sizeof", t_sizeof)
    run("void, alias, raccourcis", t_void_and_aliases)

if not ffi.supported():
    print("ffi non supporté ici : test ignoré")
else:
    libc = ffi.Library(null)
    libm = ffi.Library("m")
    main()
    libm.close()

print(f"ffi : {stats[0]} vérifications OK, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_ffi : échecs")
