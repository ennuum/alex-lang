# ALEX — tests de string.chr / string.ord / string.slice
use core
use string

failures := 0

func check(value, name):
    if not value:
        raise("AssertionError", name)

func raises(fn, code, name):
    ok := false
    try:
        fn()
    catch e:
        ok = string.contains(f"{e}", code)
    check(ok, name)

# --- chr / ord ---------------------------------------------------------------
check(string.ord("A") == 65, "ord str")
check(string.ord("é") == 233, "ord accent")
check(string.ord("€") == 8364, "ord euro")
check(string.ord("😀") == 128512, "ord hors BMP")
s := "héllo"
check(string.ord(s[1]) == 233, "ord sur un char (s[i])")
check(str(string.chr(65)) == "A", "chr ASCII")
check(str(string.chr(233)) == "é", "chr accent")
check(str(string.chr(8364)) == "€", "chr euro")
check(str(string.chr(128512)) == "😀", "chr hors BMP")
check(core.type(string.chr(65)) == "char", "chr renvoie un char")
check(string.chr(233) == "héllo"[1], "chr == s[i]")
check(string.chr(string.ord(s[1])) == s[1], "chr(ord(c)) == c")
check(str(string.chr(0)) == "\0", "chr 0")
i := 0
while i < 600:
    if i < 55296:
        check(string.ord(string.chr(i)) == i, "aller-retour chr/ord")
    i = i + 1

func untyped(v):
    return v

raises(func() => string.chr(-1), "ValueError", "chr négatif")
raises(func() => string.chr(1114112), "ValueError", "chr > 0x10FFFF")
raises(func() => string.chr(55296), "ValueError", "chr substitut")
raises(func() => string.chr(untyped("a")), "TypeError", "chr non int (vérifié à l'exécution)")
raises(func() => string.ord(""), "ValueError", "ord vide")
raises(func() => string.ord("ab"), "ValueError", "ord 2 caractères")
raises(func() => string.ord(65), "TypeError", "ord int")

# --- slice -------------------------------------------------------------------
t := "abcdef"
check(string.slice(t) == "abcdef", "slice sans bornes")
check(string.slice(t, 2) == "cdef", "slice start")
check(string.slice(t, 1, 4) == "bcd", "slice start stop")
check(string.slice(t, null, 3) == "abc", "slice stop seul")
check(string.slice(t, -2) == "ef", "slice start négatif")
check(string.slice(t, 0, -1) == "abcde", "slice stop négatif")
check(string.slice(t, -4, -1) == "cde", "slice deux négatifs")
check(string.slice(t, 0, 100) == "abcdef", "slice stop trop grand")
check(string.slice(t, -100, 2) == "ab", "slice start trop petit")
check(string.slice(t, 4, 2) == "", "slice start > stop")
check(string.slice(t, 10) == "", "slice start hors limites")
check(string.slice("", 0, 3) == "", "slice chaîne vide")
check(string.slice(t, null, null, 2) == "ace", "slice pas 2")
check(string.slice(t, 1, null, 2) == "bdf", "slice pas 2 depuis 1")
check(string.slice(t, null, null, -1) == "fedcba", "slice inversion")
check(string.slice(t, 4, 1, -1) == "edc", "slice pas -1 bornes")
check(string.slice(t, null, null, -2) == "fdb", "slice pas -2")
check(string.slice(t, 100, null, -1) == "fedcba", "slice pas négatif start trop grand")
check(string.slice(t, -1, -4, -1) == "fed", "slice pas négatif indices négatifs")
check(string.slice("héllo😀", 1, 3) == "él", "slice unicode")
check(string.slice("héllo😀", null, null, -1) == "😀olléh", "slice unicode inversé")
check(string.slice("héllo😀", -1) == "😀", "slice dernier point de code")

raises(func() => string.slice(t, 0, 3, 0), "ValueError", "slice pas nul")
raises(func() => string.slice(t, untyped("a")), "TypeError", "slice start non int")
raises(func() => string.slice(untyped(42)), "TypeError", "slice non str")

print("STRING chr/ord/slice: OK")
