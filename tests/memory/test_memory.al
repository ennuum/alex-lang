# Test du module memory : niveau sûr (Buffer, MemoryView, Arena, reference), frontière unsafe
# (alloc brut, Pointer, free), mémoire virtuelle, interop ffi. POSIX 64 bits little-endian.

from core use len, type
from collections use append, clear
use string as s
use os as os
use file as file
use ffi as ffi
use memory as memory
use memory.unsafe as unsafe
use memory.alloc as alloc
use memory.free as free
use memory.buffer as buffer
use memory.memory_view as mview
use memory.pointer as pointer
use memory.reference as reference
use memory.virtual_memory as vm
use gc as gc

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

# f() doit lever une exception de type `error_type`.
func raises(f, error_type, label):
    got := "aucune erreur"
    try:
        f()
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

func live():
    return memory.stats()["live_bytes"]

# ---------------------------------------------------------------------
# Informations
# ---------------------------------------------------------------------

func t_info():
    check(memory.supported(), "supported")
    check(memory.page_size() >= 4096, "page_size >= 4096")
    check_eq(memory.word_size(), 8, "word_size")
    check_eq(memory.endianness(), "little", "endianness")
    check_eq(memory.sizeof("i32"), 4, "sizeof i32")
    check_eq(memory.sizeof("ptr"), 8, "sizeof ptr")
    check_eq(memory.sizeof("double"), 8, "sizeof alias double")
    raises(() => memory.sizeof("nimporte"), "ArgumentError", "type inconnu")

# ---------------------------------------------------------------------
# Buffer
# ---------------------------------------------------------------------

func t_buffer_basic():
    b := buffer.Buffer(64)
    check_eq(b.size(), 64, "size")
    check(b.alive(), "alive")
    check_eq(b.address() % 16, 0, "aligné sur 16")
    check_eq(b.read("u64", 0), 0, "zéro-initialisé")
    check_eq(b.read_bytes(0, 64), s.repeat("\0", 64), "64 octets nuls")
    b.free()
    check(not b.alive(), "alive après free")
    b.free()
    check(true, "free idempotent")

func t_buffer_types():
    b := buffer.Buffer(64)
    b.write("i8", -5, 0)
    check_eq(b.read("i8", 0), -5, "i8")
    check_eq(b.read("u8", 0), 251, "u8 du même octet")
    b.write("u16", 65535, 2)
    check_eq(b.read("u16", 2), 65535, "u16")
    check_eq(b.read("i16", 2), -1, "i16 du même motif")
    b.write("i32", -123456, 4)
    check_eq(b.read("i32", 4), -123456, "i32")
    b.write("u32", 4294967295, 8)
    check_eq(b.read("u32", 8), 4294967295, "u32 max")
    b.write("i64", -9000000000, 16)
    check_eq(b.read("i64", 16), -9000000000, "i64")
    b.write("u64", 9000000000, 24)
    check_eq(b.read("u64", 24), 9000000000, "u64")
    b.write("f64", 3.25, 32)
    check_eq(b.read("f64", 32), 3.25, "f64")
    b.write("f32", 1.5, 40)
    check_eq(b.read("f32", 40), 1.5, "f32")
    b.write("bool", true, 44)
    check_eq(b.read("bool", 44), true, "bool")
    b.write("ptr", null, 48)
    check_eq(b.read("ptr", 48), null, "ptr nul -> null")
    b.write("ptr", 123456, 48)
    check_eq(b.read("ptr", 48), 123456, "ptr")
    b.write("int", 7, 56)
    check_eq(b.read("i32", 56), 7, "alias int")
    b.free()

func t_buffer_endian():
    b := buffer.Buffer(16)
    b.write("u32", 3735928559, 0, true)
    check_eq(b.read("u8", 0), 222, "gros-boutiste octet 0 (0xDE)")
    check_eq(b.read("u8", 3), 239, "gros-boutiste octet 3 (0xEF)")
    check_eq(b.read("u32", 0, true), 3735928559, "relecture BE")
    b.write("u16", 258, 8)
    check_eq(b.read("u8", 8), 2, "petit-boutiste octet bas")
    b.write("f64", 1.0, 8, true)
    check_eq(b.read("u8", 8), 63, "f64 BE : 0x3F en tête")
    check_eq(b.read("f64", 8, true), 1.0, "f64 BE aller-retour")
    b.free()

func t_buffer_arrays_strings():
    b := buffer.Buffer(64)
    check_eq(b.write_array("i32", [1, 2, 3, -4]), 16, "write_array retourne les octets")
    check_eq(b.read_array("i32", 4), [1, 2, 3, -4], "read_array")
    check_eq(b.write_bytes("abc", 20), 3, "write_bytes")
    check_eq(b.read_bytes(20, 3), "abc", "read_bytes")
    check_eq(b.write_str("héllo", 32), 7, "write_str compte les OCTETS UTF-8 + NUL")
    check_eq(b.read_str(32), "héllo", "read_str UTF-8")
    b.fill(255, 40, 4)
    check_eq(b.read("u32", 40), 4294967295, "fill")
    b.fill()
    check_eq(b.read_bytes(0, 8), s.repeat("\0", 8), "fill() total remet à zéro")
    nn := buffer.Buffer(8)
    nn.fill(65)
    raises(() => nn.read_str(0), "ArgumentError", "read_str sans NUL")
    nn.free()
    c := buffer.from_bytes("xyz")
    check_eq(c.size(), 3, "from_bytes")
    check_eq(c.to_bytes(), "xyz", "to_bytes")
    d := buffer.from_str("hé")
    check_eq(d.size(), 4, "from_str : 3 octets + NUL")
    e := buffer.from_values("u16", [1, 2, 3])
    check_eq(e.read_array("u16", 3), [1, 2, 3], "from_values")
    fv := buffer.from_values("i32", [-2], true)
    check_eq(fv.read("i32", 0, true), -2, "from_values big")
    fv.free()
    b.free()
    c.free()
    d.free()
    e.free()

func t_buffer_bounds():
    b := buffer.Buffer(16)
    raises(() => b.read("i32", 14), "IndexError", "lecture partielle hors borne")
    raises(() => b.read("u8", 16), "IndexError", "lecture à size")
    raises(() => b.read("u8", -1), "IndexError", "offset négatif")
    raises(() => b.write("i64", 1, 12), "IndexError", "écriture hors borne")
    raises(() => b.read_bytes(10, 100), "IndexError", "read_bytes hors borne")
    raises(() => b.write_bytes("0123456789ABCDEFG", 0), "IndexError", "write_bytes déborde")
    raises(() => b.fill(0, 8, 100), "IndexError", "fill hors borne")
    raises(() => b.write("u8", 300, 0), "ArgumentError", "u8 hors limites")
    raises(() => b.write("i8", -129, 0), "ArgumentError", "i8 hors limites")
    raises(() => b.write("u8", "x", 0), "TypeError", "mauvais type")
    raises(() => b.write("bool", 1, 0), "TypeError", "bool strict")
    raises(() => b.read("nimporte", 0), "ArgumentError", "type inconnu")
    raises(() => buffer.Buffer(0), "ArgumentError", "taille 0")
    raises(() => buffer.Buffer(-4), "ArgumentError", "taille négative")
    raises(() => buffer.Buffer(8, true, 3), "ArgumentError", "alignement non puissance de 2")
    raises(() => buffer.Buffer("8"), "TypeError", "taille non entière")
    b.write("i64", -1, 0)
    raises(() => b.read("u64", 0), "ValueError", "u64 > 2^63-1 refusé")
    check_eq(b.read("i64", 0), -1, "lecture en i64")
    b.free()

func t_buffer_uninit_alignment():
    b := buffer.Buffer(16, false)
    check_eq(b.read("u8", 0), 205, "non initialisé = 0xCD")
    b.free()
    c := buffer.Buffer(10, true, 256)
    check_eq(c.address() % 256, 0, "alignement 256")
    c.free()
    d := buffer.Buffer(10, true, 4096)
    check_eq(d.address() % 4096, 0, "alignement 4096")
    d.free()

func t_buffer_lifecycle():
    base := live()
    b := buffer.Buffer(100)
    check_eq(live(), base + 100, "live_bytes + 100")
    b.free()
    check_eq(live(), base, "live_bytes revient à la base")
    raises(() => b.size(), "MemoryError", "size après free")
    raises(() => b.read("u8", 0), "MemoryError", "read après free")
    raises(() => b.write("u8", 1, 0), "MemoryError", "write après free")
    raises(() => b.view(), "MemoryError", "view après free")
    b2 := buffer.Buffer(8)
    ident := b2._id
    b2.free()
    raises(() => free.block(ident), "MemoryError", "double free par identifiant")
    raises(() => free.block(999999), "ArgumentError", "identifiant inconnu")

func t_buffer_resize_freeze_clone():
    b := buffer.Buffer(8)
    b.write("u32", 42, 0)
    b.resize(32)
    check_eq(b.size(), 32, "resize agrandit")
    check_eq(b.read("u32", 0), 42, "contenu conservé")
    check_eq(b.read("u64", 24), 0, "octets ajoutés à zéro")
    v := b.view(0, 32)
    b.resize(4)
    check_eq(b.read("u32", 0), 42, "contenu conservé en réduisant")
    check(not v.valid(), "vue invalide après réduction")
    raises(() => v.read("u8", 0), "MemoryError", "accès par vue réduite")
    b.freeze()
    check(b.is_readonly(), "is_readonly")
    raises(() => b.write("u8", 1, 0), "MemoryError", "écriture sur tampon gelé")
    raises(() => b.fill(1), "MemoryError", "fill sur tampon gelé")
    raises(() => b.view().write("u8", 1, 0), "MemoryError", "écriture via vue d'un tampon gelé")
    check_eq(b.read("u32", 0), 42, "lecture permise")
    b.thaw()
    b.write("u8", 7, 0)
    check_eq(b.read("u8", 0), 7, "thaw")
    c := b.clone()
    c.write("u8", 9, 0)
    check_eq(b.read("u8", 0), 7, "clone indépendant")
    check(not b.equals(c), "equals faux")
    c.write("u8", 7, 0)
    check(b.equals(c), "equals vrai")
    b.free()
    c.free()

func t_buffer_copy_find():
    b := buffer.Buffer(32)
    b.write_bytes("hello world", 0)
    check_eq(b.find("world"), 6, "find")
    check_eq(b.find("zzz"), -1, "find absent")
    check_eq(b.find("o", 5), 7, "find avec offset")
    b.copy_from(b.view(0, 11), 0, 4, 11)
    check_eq(b.read_bytes(0, 15), "hellhello world", "copie avec chevauchement (memmove)")
    c := buffer.Buffer(8)
    src := buffer.from_bytes("ABCDEFGHIJ")
    c.copy_from(src.view(), 2, 0, 5)
    src.free()
    check_eq(c.read_bytes(0, 5), "CDEFG", "copy_from avec offsets")
    check_eq(c.compare(c), 0, "compare identique")
    d := buffer.from_bytes("a")
    e := buffer.from_bytes("b")
    check_eq(d.compare(e), -1, "compare <")
    check_eq(e.compare(d), 1, "compare >")
    c.wipe()
    check_eq(c.read("u64", 0), 0, "wipe")
    raises(() => b.copy_from(c.view(), 0, 30, 8), "IndexError", "copie hors destination")
    b.free()
    c.free()
    d.free()
    e.free()

func t_guards():
    b := buffer.Buffer(8)
    check(b.check(), "canaris intacts")
    func _fn32():
        p := pointer.from_buffer(b)
        unsafe.set_checks(false)
        p.add_bytes(8).write(1)          # 1er octet de la garde arrière
        unsafe.set_checks(true)
    unsafe.block(_fn32)
    raises(() => b.check(), "MemoryError", "débordement arrière détecté")
    raises(() => alloc.check_all(), "MemoryError", "check_all détecte")
    raises(() => b.free(), "MemoryError", "free signale la corruption")
    check(not b.alive(), "bloc tout de même libéré")
    c := buffer.Buffer(8)
    func _fn31():
        p := pointer.from_buffer(c)
        unsafe.set_checks(false)
        p.add_bytes(-1).write(1)          # dernier octet de la garde avant
        unsafe.set_checks(true)
    unsafe.block(_fn31)
    raises(() => c.check(), "MemoryError", "débordement avant détecté")
    raises(() => c.free(), "MemoryError", "free signale (avant)")
    check_eq(alloc.check_all() >= 0, true, "plus de corruption après nettoyage")

func t_quota():
    base := live()
    prev := alloc.set_limit(base + 1000)
    b := buffer.Buffer(900)
    raises(() => buffer.Buffer(200), "MemoryError", "quota dépassé")
    b.free()
    c := buffer.Buffer(1000)
    c.free()
    check_eq(alloc.limit(), base + 1000, "limit()")
    alloc.set_limit(null)
    check_eq(alloc.limit(), null, "quota levé")
    raises(() => buffer.Buffer(1000000000000000), "MemoryError", "taille énorme refusée proprement")

# ---------------------------------------------------------------------
# scoped / FreeList
# ---------------------------------------------------------------------

func t_scoped():
    base := live()
    func _fn30(b):
        b.write("u32", 5, 0)
        return b.read("u32", 0) + 1
    r := buffer.scoped(128, _fn30)
    check_eq(r, 6, "scoped retourne la valeur")
    check_eq(live(), base, "scoped libère")
    kept := [null]
    func _fn29(b):
        kept[0] = b
        raise("ValueError", "boum")
    raises(() => buffer.scoped(64, _fn29), "ValueError", "l'exception du corps est relevée")
    check_eq(live(), base, "scoped libère même sur exception")
    check(not kept[0].alive(), "buffer libéré après exception")
    func _fn28(a):
        v := a.alloc(16)
        v.write("u8", 9, 0)
        return v.read("u8", 0)
    r2 := buffer.scoped_arena(256, _fn28)
    check_eq(r2, 9, "scoped_arena")
    check_eq(live(), base, "scoped_arena libère")

func t_freelist():
    base := live()
    order := []
    fl := free.FreeList()
    fl.push(buffer.Buffer(10))
    fl.defer(() => append(order, "a"))
    fl.push(buffer.Buffer(20))
    fl.defer(() => append(order, "b"))
    check_eq(fl.count(), 4, "4 entrées")
    fl.run()
    check_eq(order, ["b", "a"], "ordre LIFO")
    check_eq(live(), base, "tout libéré")
    check_eq(fl.count(), 0, "vide")
    func _fn27(f):
        f.push(buffer.Buffer(33))
        return 5
    r := free.scope(_fn27)
    check_eq(r, 5, "free.scope")
    check_eq(live(), base, "free.scope libère")
    func _fn26(f):
        f.push(buffer.Buffer(33))
        raise("ArgumentError", "x")
    raises(() => free.scope(_fn26), "ArgumentError", "free.scope relève")
    check_eq(live(), base, "free.scope libère sur exception")
    z := buffer.Buffer(5)
    def_addr := [0]
    func _prep():
        q := alloc.raw(8)
        free.address(q)
        def_addr[0] = q
    unsafe.block(_prep)
    func _rel():
        free.release_all([def_addr[0], z])
    func _blk():
        raises(_rel, "MemoryError", "release_all relève la première erreur")
    unsafe.block(_blk)
    check(not z.alive(), "release_all continue après une erreur")

# ---------------------------------------------------------------------
# MemoryView
# ---------------------------------------------------------------------

func t_view_basic():
    b := buffer.Buffer(32)
    b.write_array("u8", [0, 1, 2, 3, 4, 5, 6, 7, 8, 9], 0)
    v := b.view(2, 8)
    check_eq(v.size(), 8, "size")
    check_eq(v.read("u8", 0), 2, "lecture relative")
    check_eq(v.read("u8", 7), 9, "dernier octet")
    raises(() => v.read("u8", 8), "IndexError", "hors vue")
    raises(() => v.read("u32", 6), "IndexError", "lecture partielle hors vue")
    raises(() => v.read("u8", -1), "IndexError", "avant la vue")
    v.write("u8", 99, 0)
    check_eq(b.read("u8", 2), 99, "écriture visible dans le tampon")
    sub := v.slice(1, 4)
    check_eq(sub.size(), 4, "sous-vue")
    check_eq(sub.read("u8", 0), 3, "sous-vue relative")
    raises(() => v.slice(4, 5), "IndexError", "sous-vue dépassant le parent")
    raises(() => sub.read("u8", 4), "IndexError", "sous-vue : borne propre")
    raises(() => v.slice(-1, 2), "IndexError", "sous-vue négative")
    check_eq(v.slice(3).size(), 5, "slice jusqu'à la fin")
    check_eq(v.address(), b.address() + 2, "address()")
    check_eq(v.to_list("u8"), [99, 3, 4, 5, 6, 7, 8, 9], "to_list")
    check_eq(mview.view(b, 4, 2).size(), 2, "mview.view")
    check_eq(memory.view(b, 1).size(), 31, "memory.view")
    b.free()

func t_view_readonly():
    b := buffer.Buffer(16)
    ro := b.view(0, 16, true)
    check(ro.is_readonly(), "is_readonly")
    raises(() => ro.write("u8", 1, 0), "MemoryError", "écriture refusée")
    raises(() => ro.fill(1), "MemoryError", "fill refusé")
    raises(() => ro.write_bytes("a", 0), "MemoryError", "write_bytes refusé")
    raises(() => ro.write_str("a", 0), "MemoryError", "write_str refusé")
    raises(() => ro.wipe(), "MemoryError", "wipe refusé")
    raises(() => ro.slice(0, 4).write("u8", 1, 0), "MemoryError", "sous-vue hérite lecture seule")
    check(ro.slice(0, 4).is_readonly(), "sous-vue readonly")
    check(b.view().as_readonly().is_readonly(), "as_readonly")
    check_eq(ro.read("u8", 0), 0, "lecture ok")
    rw := b.view()
    rw.write("u8", 5, 0)
    check_eq(ro.read("u8", 0), 5, "la vue lecture seule voit les écritures")
    b.free()

func t_view_invalidation():
    b := buffer.Buffer(16)
    v := b.view(0, 8)
    check(v.valid(), "valide")
    b.free()
    check(not v.valid(), "invalide après free")
    raises(() => v.read("u8", 0), "MemoryError", "lecture après free du bloc")
    raises(() => v.write("u8", 1, 0), "MemoryError", "écriture après free")
    raises(() => v.slice(0, 1), "MemoryError", "slice après free")
    raises(() => v.address(), "MemoryError", "address après free")

func t_view_ops():
    b := buffer.Buffer(32)
    b.write_bytes("abcdefghij", 0)
    v := b.view(0, 10)
    parts := v.split_at(4)
    check_eq(parts[0].to_bytes(), "abcd", "split_at gauche")
    check_eq(parts[1].to_bytes(), "efghij", "split_at droite")
    ch := v.chunks(4)
    check_eq(len(ch), 3, "chunks")
    check_eq(ch[2].to_bytes(), "ij", "dernier chunk court")
    raises(() => v.chunks(0), "ArgumentError", "chunks(0)")
    check_eq(v.find("fg"), 5, "find")
    check(v.contains("j"), "contains")
    check(not v.contains("z"), "contains faux")
    check_eq(v.slice(2).find("b"), -1, "find limité à la vue")
    check_eq(v.slice(2).find("c"), 0, "find relatif à la sous-vue")
    v.write_str("xy", 0)
    check_eq(v.read_str(0), "xy", "write_str/read_str")
    raises(() => b.view(0, 2).write_str("xy", 0), "IndexError", "write_str + NUL déborde")
    check_eq(b.view(0, 4).equals(b.view(0, 4)), true, "equals")
    check_eq(b.view(0, 4).equals(b.view(1, 4)), false, "equals faux")
    check_eq(v.compare(b.view(0, 10)), 0, "compare")
    w := buffer.Buffer(8)
    n := w.view().copy_from(b.view(0, 3))
    check_eq(n, 3, "copy_from min des restes")
    check_eq(w.read_bytes(0, 3), "xy\0", "copie")
    b.view(0, 5).copy_to(w.view(), 0, 2, 3)
    check_eq(w.read_bytes(2, 3), "xy\0", "copy_to")
    raises(() => w.view(0, 2).copy_from(b.view(0, 8), 0, 0, 8), "IndexError", "copie trop longue")
    check_eq(v.read_array("u8", 2), [120, 121], "read_array")
    check_eq(v.write_array("u16", [1, 2], 4), 4, "write_array")
    check_eq(v.read_array("u16", 2, 4), [1, 2], "write/read_array u16")
    v.fill(7, 0, 3)
    check_eq(v.to_list("u8")[0], 7, "fill")
    v.wipe()
    check_eq(v.to_list("u8")[2], 0, "wipe")
    check_eq(v.write("u16", 1, 0, true), 2, "BE")
    check_eq(v.read("u8", 1), 1, "BE : octet bas en second")
    b.free()
    w.free()

func t_hexdump():
    b := buffer.from_bytes("Hello, hexdump!!XYZ")
    d := b.hexdump()
    check(s.starts_with(d, "000000  48 65 6c 6c 6f 2c 20 68"), "préfixe hexdump")
    check(s.contains(d, "|Hello, hexdump!!|"), "colonne texte")
    check(s.contains(d, "000010  58 59 5a"), "2e ligne")
    check(s.contains(b.hexdump(16, 4), "(15 octets omis)"), "troncature")
    b.free()

# ---------------------------------------------------------------------
# Arena
# ---------------------------------------------------------------------

func t_arena():
    base := live()
    a := buffer.Arena(256)
    check_eq(a.capacity(), 256, "capacity")
    v1 := a.alloc(10)
    v2 := a.alloc(8, 8)
    check_eq(v2.address() % 8, 0, "alignement 8 absolu")
    v3 := a.alloc(4, 64)
    check_eq(v3.address() % 64, 0, "alignement 64 absolu")
    v1.write("u8", 1, 0)
    v2.write("u8", 2, 0)
    check_eq(v1.read("u8", 0), 1, "vues disjointes")
    check(a.used() > 22, "used")
    check_eq(a.remaining(), 256 - a.used(), "remaining")
    raises(() => a.alloc(1000), "MemoryError", "arène pleine")
    raises(() => a.alloc(0), "ArgumentError", "taille 0")
    raises(() => a.alloc(4, 3), "ArgumentError", "alignement invalide")
    raises(() => v1.read("u8", 10), "IndexError", "vue d'arène bornée")
    sub := v1.slice(0, 4)
    a.reset()
    check_eq(a.used(), 0, "reset")
    raises(() => v1.read("u8", 0), "StaleViewError", "vue périmée par reset")
    raises(() => sub.read("u8", 0), "StaleViewError", "sous-vue périmée par reset")
    check(not v1.valid(), "valid() faux")
    v4 := a.alloc(16)
    check_eq(v4.read("u8", 0), 0, "espace remis à zéro")
    v4.write("u8", 5, 0)
    a.free()
    raises(() => v4.read("u8", 0), "StaleViewError", "vue périmée par free")
    check_eq(live(), base, "arène libérée")

# ---------------------------------------------------------------------
# Frontière unsafe
# ---------------------------------------------------------------------

func t_unsafe_gate():
    check(not unsafe.active(), "hors bloc")
    raises(() => alloc.raw(8), "UnsafeError", "alloc.raw hors bloc")
    raises(() => alloc.calloc(2, 2), "UnsafeError", "calloc hors bloc")
    raises(() => free.address(4096), "UnsafeError", "free.address hors bloc")
    raises(() => unsafe.set_checks(false), "UnsafeError", "set_checks hors bloc")
    raises(() => pointer.malloc(2), "UnsafeError", "malloc hors bloc")
    p := pointer.from_address(12345, "u8")
    raises(() => p.read(), "UnsafeError", "déréférencement hors bloc")
    raises(() => p.write(1), "UnsafeError", "écriture hors bloc")
    check_eq(p.address(), 12345, "address est sûr")
    check_eq(p.offset(3).address(), 12348, "offset est sûr")
    check(p.is_aligned(), "is_aligned est sûr")
    inside := [false]
    func _fn25():
        inside[0] = unsafe.active()
        return 42
    r := unsafe.block(_fn25)
    check(inside[0], "actif dans le bloc")
    check_eq(r, 42, "block retourne la valeur")
    check(not unsafe.active(), "inactif après")
    func _fn24():
        raise("ValueError", "x")
    raises(() => unsafe.block(_fn24), "ValueError", "l'exception traverse le bloc")
    check(not unsafe.active(), "profondeur restaurée après exception")
    depths := []
    func _fn23():
        append(depths, unsafe.depth())
        func _fn22():
            append(depths, unsafe.depth())
        unsafe.block(_fn22)
        append(depths, unsafe.depth())
    unsafe.block(_fn23)
    check_eq(depths, [1, 2, 1], "blocs imbriqués")
    raises(() => unsafe.block(() => 1, "inconnu"), "ArgumentError", "option leaks invalide")
    before := unsafe.stats()["ops"]
    func _fn21():
        q := alloc.raw(8)
        free.address(q)
    unsafe.block(_fn21)
    check(unsafe.stats()["ops"] >= before + 2, "audit des opérations")
    # un pointeur sorti d'un bloc ne se déréférence plus
    esc := [null]
    func _fn20():
        esc[0] = pointer.malloc(1, "u8")
        esc[0].write(5)
    unsafe.block(_fn20)
    raises(() => esc[0].read(), "UnsafeError", "pointeur échappé inutilisable")
    func _fn19():
        check_eq(esc[0].read(), 5, "même pointeur utilisable dans un nouveau bloc")
        esc[0].free()
    unsafe.block(_fn19)

func t_unsafe_leaks():
    base := live()
    func _fn18():
        alloc.raw(100)
    unsafe.block(_fn18)
    check_eq(live(), base + 100, "fuite tolérée par défaut")
    check_eq(len(free.leaks()), 1, "leaks() la voit")
    check(s.contains(free.leak_report(), "100 octets"), "leak_report")
    func _fn17():
        p := free.leaks()[0]["address"]
        free.address(p)
    unsafe.block(_fn17)
    check_eq(live(), base, "libérée à la main")
    check_eq(free.leak_report(), "aucune fuite", "rapport vide")
    func _fn16():
        alloc.raw(50)
    unsafe.block(_fn16, "free")
    check_eq(live(), base, "leaks=free libère")
    func _fn15():
        alloc.raw(60)
    raises(() => unsafe.block(_fn15, "error"), "LeakError", "leaks=error signale")
    check_eq(live(), base, "leaks=error libère aussi")
    func _fn14():
        p := alloc.raw(10)
        free.address(p)
    unsafe.block(_fn14, "error")
    check(true, "pas de fuite => pas d'erreur")

func t_alloc_raw():
    func _fn13():
        a := alloc.raw(16)
        check_eq(a % 16, 0, "aligné")
        check_eq(alloc.usable_size(a), 16, "usable_size")
        check_eq(alloc.usable_size(a + 1), null, "usable_size d'un pointeur intérieur")
        z := alloc.zeroed(16)
        check_eq(pointer.from_address(z, "u64").read(), 0, "zeroed")
        c := alloc.calloc(4, 8)
        check_eq(pointer.from_address(c, "u64").read_array(4), [0, 0, 0, 0], "calloc")
        al := alloc.aligned(10, 512)
        check_eq(al % 512, 0, "aligned(512)")
        pa := pointer.from_address(a, "u8")
        pa.write_bytes("0123456789ABCDEF")
        a2 := alloc.realloc(a, 32)
        pa2 := pointer.from_address(a2, "u8")
        check_eq(pa2.read_bytes(16), "0123456789ABCDEF", "realloc conserve")
        check_eq(pa2.read_bytes(16, 16), s.repeat("\0", 16), "realloc : ajout à zéro")
        raises(() => pa.read(), "MemoryError", "ancienne adresse invalide après realloc")
        raises(() => alloc.raw(0), "ArgumentError", "taille 0")
        raises(() => alloc.raw(8, 3), "ArgumentError", "alignement")
        raises(() => alloc.calloc(9223372036854775807, 8), "MemoryError", "calloc déborde")
        raises(() => alloc.calloc(0, 8), "ArgumentError", "calloc 0")
        free.address(a2)
        free.address(z)
        free.address(c)
        free.address(al)
    unsafe.block(_fn13)

func t_free_errors():
    func _fn12():
        a := alloc.raw(32)
        raises(() => free.address(a + 8), "MemoryError", "pointeur intérieur")
        raises(() => free.address(4096 * 1000), "MemoryError", "pointeur inconnu")
        raises(() => free.address("x"), "TypeError", "type")
        free.address(a)
        raises(() => free.address(a), "MemoryError", "double free")
        raises(() => pointer.from_address(a, "u8").read(), "MemoryError", "lecture après free")
        raises(() => pointer.from_address(a, "u8").write(1), "MemoryError", "écriture après free")
        b := buffer.Buffer(8)
        raises(() => free.address(b.address()), "ArgumentError", "bloc géré libéré comme brut")
        r := vm.map(4096)
        raises(() => free.address(r.address()), "ArgumentError", "page libérée par free")
        raises(() => free.block(b._id + 100), "ArgumentError", "id inconnu")
        b.free()
        r.unmap()
        raises(() => free.release_all([123456789]), "MemoryError", "release d'une adresse inconnue")
    unsafe.block(_fn12)

func t_free_release():
    func _fn11():
        a := alloc.raw(8)
        free.release(a)
        raises(() => free.release(a), "MemoryError", "release : double free")
        b := buffer.Buffer(8)
        free.release(b)
        check(not b.alive(), "release d'un Buffer")
        p := pointer.malloc(2, "u32")
        free.release(p)
        raises(() => p.free(), "MemoryError", "double free via Pointer")
    unsafe.block(_fn11)

# ---------------------------------------------------------------------
# Pointer
# ---------------------------------------------------------------------

func t_pointer():
    func _fn10():
        p := pointer.malloc(8, "i32")
        check_eq(p.elem_size(), 4, "elem_size")
        check_eq(p.type_name(), "i32", "type_name")
        check(not p.is_null(), "non nul")
        check(pointer.nullptr().is_null(), "nullptr")
        p.write_array([10, 20, 30, 40, 50, 60, 70, 80])
        check_eq(p.read(), 10, "read")
        check_eq(p.read(3), 40, "read indexé")
        check_eq(p.offset(2).read(), 30, "offset en éléments")
        check_eq(p.offset(7).offset(-2).read(), 60, "offset négatif")
        check_eq(p.offset(5).diff(p), 5, "diff")
        check_eq(p.diff(p.offset(3)), -3, "diff négatif")
        check(p.offset(1).lt(p) == false, "lt")
        check(p.lt(p.offset(1)), "lt vrai")
        check(p.eq(p.offset(0)), "eq")
        check_eq(p.cast("u8").read(), 10, "cast")
        check_eq(p.cast("u8").read(4), 20, "cast: octets suivants")
        check_eq(p.cast("u16").offset(1).address(), p.address() + 2, "cast + offset")
        check_eq(p.read_array(3, 5), [60, 70, 80], "read_array indexé")
        p.offset(1).write(-1)
        check_eq(p.cast("u32").read(1), 4294967295, "réinterprétation")
        check_eq(p.write(7, 2), 4, "write retourne les octets")
        check_eq(p.read(2), 7, "write indexé")
        p.write_big(1, 0)
        check_eq(p.cast("u8").read(3), 1, "write_big")
        check_eq(p.read_big(0), 1, "read_big")
        q := pointer.malloc(8, "i32")
        check_eq(p.copy_to(q, 8), 32, "copy_to")
        check_eq(q.read_array(3), [16777216, -1, 7], "copie fidèle (BE puis LE)")
        check_eq(p.compare(q, 8), 0, "compare égal")
        q.write(0, 7)
        check(p.compare(q, 8) != 0, "compare différent")
        p.copy_to(p.offset(1), 7)
        check_eq(p.read_array(3), [16777216, 16777216, -1], "copy_to chevauchant (memmove)")
        q.fill(255, 8)
        check_eq(q.cast("u8").read(31), 255, "fill")
        raises(() => p.read(8), "MemoryError", "hors bloc (+1 élément)")
        raises(() => p.offset(-1).read(), "MemoryError", "avant le bloc")
        raises(() => p.offset(7).read_array(2), "MemoryError", "lecture débordante")
        raises(() => p.copy_to(q, 9), "MemoryError", "copie débordante")
        raises(() => pointer.nullptr().read(), "MemoryError", "déréférencement nul")
        raises(() => pointer.from_address(100, "u8").read(), "MemoryError", "adresse quasi nulle")
        raises(() => pointer.from_address(4096 * 4096 * 7, "u8").read(), "MemoryError", "adresse inconnue")
        raises(() => pointer.Pointer("x"), "TypeError", "adresse non entière")
        raises(() => pointer.Pointer(0, "nimporte"), "ArgumentError", "type inconnu")
        raises(() => pointer.malloc(0), "ArgumentError", "malloc(0)")
        raises(() => p.diff(p.cast("u8").offset(1).cast("i32")), "ArgumentError", "diff non multiple")
        check(p.is_valid(8), "is_valid 8")
        check(not p.is_valid(9), "is_valid 9 faux")
        check(p.is_valid(8, true), "is_valid en écriture")
        check(p.probe(8), "probe (OS)")
        check(not pointer.nullptr().probe(), "probe nul")
        check_eq(p.region()["size"], 32, "region().size")
        check_eq(p.offset(2).region()["offset"], 8, "region().offset")
        check_eq(p.region()["kind"], "raw", "region().kind")
        check_eq(pointer.from_address(4096 * 4096 * 7).region(), null, "region inconnue")
        pointer.free(p)
        pointer.free(q)
    unsafe.block(_fn10)

func t_pointer_cstr():
    func _fn9():
        p := pointer.malloc(32, "u8")
        p.write_bytes("salut\0reste")
        check_eq(p.cstr(), "salut", "cstr")
        check_eq(p.cstr(3), "sal", "cstr borné")
        p.fill(65, 32)
        raises(() => p.cstr(), "MemoryError", "cstr sans NUL dans la région")
        check_eq(len(p.cstr(10)), 10, "cstr borné sans NUL")
        p.free()
    unsafe.block(_fn9)

func t_pointer_from_buffer():
    b := buffer.Buffer(16)
    b.write("u32", 777, 4)
    func _fn8():
        p := pointer.from_buffer(b, 4, "u32")
        check_eq(p.read(), 777, "lecture via pointeur")
        p.write(888)
        check_eq(p.region()["kind"], "managed", "région managed")
        check(p.is_valid(3), "3 u32 valides depuis l'offset 4")
        check(not p.is_valid(4), "4 u32 dépassent")
    unsafe.block(_fn8)
    check_eq(b.read("u32", 4), 888, "écriture visible dans le Buffer")
    b.freeze()
    func _fn7():
        p := pointer.from_buffer(b, 4, "u32")
        raises(() => p.write(1), "MemoryError", "écriture par pointeur sur tampon gelé")
        check_eq(p.read(), 888, "lecture ok")
        check(not p.is_valid(1, true), "is_valid écriture faux")
    unsafe.block(_fn7)
    b.free()
    func _fn6():
        p := pointer.from_address(4096 * 4096 * 9, "u8")
        raises(() => p.read(), "MemoryError", "adresse libre quelconque")
    unsafe.block(_fn6)

func t_checks_off():
    func _fn5():
        p := pointer.malloc(4, "u32")
        check(unsafe.checks(), "checks actifs par défaut")
        old := unsafe.set_checks(false)
        check(old, "set_checks retourne l'ancien état")
        check(not unsafe.checks(), "checks coupés")
        p.write(31337)
        check_eq(p.read(), 31337, "accès nu sur mémoire valide")
        raises(() => pointer.nullptr().read(), "MemoryError", "le nul reste refusé sans contrôles")
        unsafe.set_checks(true)
        pointer.free(p)
    unsafe.block(_fn5)

func t_track_external():
    libc := ffi.Library(null)
    malloc := libc.function("malloc", ["size_t"], "ptr")
    cfree := libc.function("free", ["ptr"], "void")
    addr := malloc.call1(64)
    func _fn4():
        p := pointer.from_address(addr, "u32")
        raises(() => p.write(1), "MemoryError", "mémoire étrangère non suivie")
        tid := pointer.track(addr, 64, "libc malloc")
        p.write(123)
        check_eq(p.read(), 123, "accès après track")
        check_eq(p.region()["kind"], "external", "kind external")
        check_eq(p.region()["tag"], "libc malloc", "tag")
        raises(() => pointer.from_address(addr + 64, "u8").read(), "MemoryError", "au-delà de la région externe")
        raises(() => pointer.track(addr + 8, 8), "ArgumentError", "chevauchement refusé")
        raises(() => pointer.track(4, 8), "ArgumentError", "adresse invalide")
        raises(() => free.address(addr), "ArgumentError", "free refuse external")
        pointer.untrack(tid)
        raises(() => p.read(), "MemoryError", "après untrack")
    unsafe.block(_fn4)
    cfree.call1(addr)
    libc.close()

func t_ffi_interop():
    libc := ffi.Library(null)
    strlen := libc.function("strlen", ["ptr"], "size_t")
    memset := libc.function("memset", ["ptr", "i32", "size_t"], "ptr")
    b := buffer.Buffer(32)
    b.write_str("interop")
    check_eq(strlen.call1(b.address()), 7, "strlen sur un Buffer memory")
    memset.call([b.address() + 8, 90, 4])
    check_eq(b.read_bytes(8, 4), "ZZZZ", "memset C sur un Buffer memory")
    check_eq(b.read("u8", 12), 0, "pas de débordement")
    check_eq(b.view(8, 4).address(), b.address() + 8, "adresse de vue")
    b.check()
    b.free()
    libc.close()

# ---------------------------------------------------------------------
# reference
# ---------------------------------------------------------------------

func t_ref():
    a := reference.Ref(1)
    b := reference.ref(2)
    check_eq(a.get(), 1, "get")
    check_eq(a.set(5), 5, "set")
    check_eq(a.replace(6), 5, "replace retourne l'ancien")
    a.swap(b)
    check_eq(a.get(), 2, "swap a")
    check_eq(b.get(), 6, "swap b")
    check_eq(a.update((x) => x * 10), 20, "update")
    check_eq(a.take(0), 20, "take")
    check_eq(a.get(), 0, "après take")
    check(a.compare_and_set(0, 1), "cas ok")
    check(not a.compare_and_set(0, 2), "cas refusé")
    check_eq(a.get(), 1, "cas : valeur")
    alias := a
    alias.set(9)
    check_eq(a.get(), 9, "alias partagé")

func t_rc():
    dropped := []
    r := reference.rc("v", (v) => append(dropped, v))
    check_eq(r.get(), "v", "get")
    check_eq(r.count(), 1, "count 1")
    r2 := r.clone()
    r3 := r2.clone()
    check_eq(r.count(), 3, "count 3")
    check(r.ptr_eq(r3), "ptr_eq")
    check(not r.ptr_eq(reference.rc("v")), "ptr_eq faux")
    w := r.downgrade()
    check_eq(r.weak_count(), 1, "weak_count")
    check(w.alive(), "weak vivante")
    check_eq(w.strong_count(), 3, "strong_count via weak")
    check(r2.drop(), "drop vrai")
    check(not r2.drop(), "drop idempotent")
    check_eq(r.count(), 2, "count 2")
    raises(() => r2.get(), "OwnershipError", "usage après drop")
    raises(() => r2.clone(), "OwnershipError", "clone après drop")
    up := w.upgrade()
    check(up != null, "upgrade réussit")
    check_eq(r.count(), 3, "upgrade compte")
    up.drop()
    r.drop()
    check_eq(len(dropped), 0, "pas encore détruit")
    r3.drop()
    check_eq(dropped, ["v"], "on_drop une fois")
    check(not w.alive(), "weak morte")
    check_eq(w.upgrade(), null, "upgrade null")
    check_eq(w.strong_count(), 0, "strong_count 0")
    u := reference.rc(5)
    check_eq(u.try_unwrap(), 5, "try_unwrap unique")
    check(not u.is_held(), "relâché par try_unwrap")
    v := reference.rc(6)
    v2 := v.clone()
    check_eq(v.try_unwrap(), null, "try_unwrap partagé")
    check(v.is_held(), "toujours détenu")
    v2.drop()
    check_eq(v.try_unwrap(), 6, "try_unwrap après relâchement des autres")

func t_refcell():
    c := reference.cell(10)
    check(not c.is_borrowed(), "libre")
    r1 := c.borrow()
    r2 := c.borrow()
    check_eq(r1.get(), 10, "lecture")
    check(c.is_borrowed(), "emprunté")
    raises(() => c.borrow_mut(), "BorrowError", "mut pendant lecteurs")
    raises(() => r1.set(1), "BorrowError", "écriture via emprunt partagé")
    r1.release()
    r1.release()
    raises(() => r1.get(), "BorrowError", "usage après release")
    raises(() => c.borrow_mut(), "BorrowError", "encore un lecteur")
    r2.release()
    w := c.borrow_mut()
    check(c.is_borrowed_mut(), "is_borrowed_mut")
    raises(() => c.borrow(), "BorrowError", "lecture pendant écriture")
    raises(() => c.borrow_mut(), "BorrowError", "double écriture")
    w.set(11)
    w.release()
    check(not c.is_borrowed(), "libre après release")
    check_eq(c.with_borrow((v) => v), 11, "valeur écrite")
    check_eq(c.with_borrow_mut((v) => v + 1), 12, "with_borrow_mut")
    check_eq(c.with_borrow((v) => v * 2), 24, "with_borrow")
    raises(() => c.with_borrow_mut((v) => raise("ValueError", "x")), "ValueError", "exception relevée")
    check(not c.is_borrowed_mut(), "relâché malgré l'exception")
    check_eq(c.with_borrow((v) => v), 12, "valeur inchangée par l'échec")

func t_handles():
    t := reference.table()
    h1 := t.insert("a")
    h2 := t.insert("b")
    check_eq(t.count(), 2, "count")
    check_eq(t.get(h1), "a", "get")
    t.set(h2, "B")
    check_eq(t.get(h2), "B", "set")
    check_eq(t.remove(h1), "a", "remove")
    check(not t.contains(h1), "contains faux")
    raises(() => t.get(h1), "StaleHandleError", "handle périmé")
    raises(() => t.remove(h1), "StaleHandleError", "double remove")
    h3 := t.insert("c")
    check_eq(h3.index, h1.index, "emplacement réutilisé")
    check(h3.generation != h1.generation, "génération différente")
    raises(() => t.get(h1), "StaleHandleError", "l'ancien handle ne vise pas la nouvelle valeur")
    check_eq(t.get(h3), "c", "nouveau handle")
    check(h3.eq(h3), "Handle.eq")
    check_eq(t.count(), 2, "count final")
    raises(() => t.get(reference.Handle(99, 0)), "StaleHandleError", "index invalide")

# ---------------------------------------------------------------------
# Mémoire virtuelle
# ---------------------------------------------------------------------

func t_vm_basic():
    ps := vm.page_size()
    check_eq(vm.round_up(1), ps, "round_up(1)")
    check_eq(vm.round_up(ps), ps, "round_up(page)")
    check_eq(vm.round_up(ps + 1), 2 * ps, "round_up(page+1)")
    r := vm.map(3 * ps - 5)
    check_eq(r.size(), 3 * ps, "taille arrondie")
    check_eq(r.page_count(), 3, "page_count")
    check_eq(r.address() % ps, 0, "aligné sur la page")
    check_eq(r.read("u64", 0), 0, "zéro-initialisé")
    r.write("u32", 1234, ps)
    check_eq(r.read("u32", ps), 1234, "aller-retour")
    r.write_bytes("page", 2 * ps)
    check_eq(r.read_bytes(2 * ps, 4), "page", "bytes")
    r.fill(1, 0, 8)
    check_eq(r.read("u8", 7), 1, "fill")
    raises(() => r.read("u8", 3 * ps), "IndexError", "hors région")
    check_eq(r.prot_at(0), vm.RW, "prot RW")
    check_eq(r.view(0, 16).size(), 16, "vue sur région")
    func _fn3():
        p := pointer.from_address(r.address(), "u32")
        check_eq(p.read(), 16843009, "pointeur sur page")
        check_eq(p.region()["kind"], "mapped", "kind mapped")
    unsafe.block(_fn3)
    r.unmap()
    check(not r.alive(), "démappée")
    r.unmap()
    raises(() => r.read("u8", 0), "MemoryError", "après unmap")
    raises(() => vm.map(0), "ArgumentError", "taille 0")

func t_vm_protect():
    ps := vm.page_size()
    r := vm.map(3 * ps)
    r.write("u8", 1, 0)
    r.protect(vm.READ, 0, ps)
    check_eq(r.prot_at(0), 1, "page 0 en lecture")
    check_eq(r.prot_at(ps), 3, "page 1 inchangée")
    check_eq(r.read("u8", 0), 1, "lecture permise")
    raises(() => r.write("u8", 2, 0), "MemoryError", "écriture refusée (page RO)")
    raises(() => r.fill(0, 0, 4), "MemoryError", "fill refusé")
    raises(() => r.view().write("u8", 2, 0), "MemoryError", "écriture par vue refusée")
    r.write("u8", 3, ps)
    check_eq(r.read("u8", ps), 3, "page 1 inscriptible")
    raises(() => r.write_bytes("x" + s.repeat("y", ps), ps - 1), "MemoryError", "écriture à cheval sur une page RO")
    r.protect(vm.NONE, ps, ps)
    raises(() => r.read("u8", ps), "MemoryError", "lecture d'une page PROT_NONE")
    raises(() => r.read("u32", ps - 2), "MemoryError", "lecture à cheval sur la page PROT_NONE")
    func _fn2():
        p := pointer.from_address(r.address() + ps, "u8")
        raises(() => p.read(), "MemoryError", "pointeur sur page PROT_NONE refusé")
    unsafe.block(_fn2)
    r.protect(vm.RW, ps, ps)
    check_eq(r.read("u8", ps), 3, "protection rétablie, contenu conservé")
    r.write("u8", 4, ps)
    raises(() => r.protect(7, 0, ps), "ArgumentError", "W+X refusé (W^X)")
    raises(() => r.protect(3, 1, ps), "ArgumentError", "offset non aligné")
    raises(() => r.protect(3, 0, ps + 1), "ArgumentError", "longueur non alignée")
    raises(() => r.protect(3, 0, 100 * ps), "IndexError", "plage hors région")
    raises(() => r.protect(vm.RX, 0, ps), "UnsafeError", "EXEC hors bloc unsafe")
    raises(() => vm.map(ps, vm.RX), "UnsafeError", "map EXEC hors unsafe")
    func _fn1():
        r.protect(vm.RX, 2 * ps, ps)
        check_eq(r.prot_at(2 * ps), 5, "R+X dans un bloc unsafe")
        raises(() => r.write("u8", 1, 2 * ps), "MemoryError", "page R-X non inscriptible")
        r.protect(vm.RW, 2 * ps, ps)
    unsafe.block(_fn1)
    check_eq(r.prot_at(2 * ps), 3, "retour RW")
    r.unmap()

func t_vm_reserve_guard():
    ps := vm.page_size()
    r := vm.reserve(4 * ps)
    check_eq(r.prot_at(0), 0, "réservée PROT_NONE")
    raises(() => r.read("u8", 0), "MemoryError", "lecture de l'espace réservé")
    r.protect(vm.RW, 0, ps)
    r.write("u8", 1, 0)
    check_eq(r.read("u8", 0), 1, "page engagée")
    raises(() => r.read("u8", ps), "MemoryError", "page suivante toujours réservée")
    r.unmap()
    g := vm.map_guarded(100)
    check_eq(g.size(), 100, "taille utile")
    g.write("u8", 7, 0)
    g.write("u8", 8, 99)
    check_eq(g.read("u8", 99), 8, "dernier octet utile")
    raises(() => g.read("u8", 100), "MemoryError", "débordement d'un octet détecté")
    raises(() => g.write("u8", 1, 100), "MemoryError", "écriture débordante détectée")
    raises(() => g.write_bytes(s.repeat("a", 101), 0), "MemoryError", "write_bytes débordant")
    check_eq(g.view(0, 100).size(), 100, "vue")
    raises(() => g.view(0, 101), "IndexError", "vue trop grande")
    check_eq(g.address() % 1, 0, "address")
    g.unmap()
    h := vm.map_guarded(100, false)
    h.write("u8", 5, 0)
    check_eq(h.read("u8", 0), 5, "début de données")
    raises(() => h.read("u8", -1), "MemoryError", "dépassement par le bas détecté")
    h.free()
    mg := vm.map_guarded(vm.page_size() * 2)
    check_eq(mg.size(), vm.page_size() * 2, "taille multiple de page")
    mg.unmap()

func t_vm_advice():
    ps := vm.page_size()
    r := vm.map(4 * ps)
    check_eq(r.resident(), 0, "rien de résident avant accès")
    r.write("u8", 1, 0)
    r.write("u8", 1, 2 * ps)
    check_eq(r.resident(), 2, "2 pages résidentes après accès")
    check_eq(r.resident(0, ps), 1, "résidence d'une page")
    r.advise("sequential")
    r.advise("willneed", 0, ps)
    r.advise("random")
    r.advise("normal")
    r.advise("dontneed", 0, ps)
    check_eq(r.read("u8", 0), 0, "dontneed remet une page anonyme à zéro")
    raises(() => r.advise("inconnu"), "ArgumentError", "conseil inconnu")
    ok := true
    try:
        r.lock(0, ps)
        r.unlock(0, ps)
    catch e:
        ok = e.type == "IoError"
    check(ok, "lock/unlock : succès ou IoError (RLIMIT_MEMLOCK)")
    r.unmap()

func t_vm_file():
    path := os.join(os.tmp_dir(), "alex_memory_test_" + str(os.pid()) + ".bin")
    file.write(path, "0123456789")
    r := vm.map_file(path)
    check_eq(r.size(), 10, "taille du fichier")
    check_eq(r.read_bytes(0, 10), "0123456789", "contenu mappé")
    check_eq(r.read("u8", 0), 48, "lecture typée")
    raises(() => r.write("u8", 1, 0), "MemoryError", "lecture seule par défaut")
    raises(() => r.read("u8", 10), "IndexError", "borne = taille du fichier")
    r.unmap()
    w := vm.map_file(path, true, true)
    w.write_bytes("AB", 0)
    w.sync()
    w.unmap()
    check_eq(file.read(path), "AB23456789", "écriture partagée atteint le fichier")
    c := vm.map_file(path, true, false)
    c.write_bytes("ZZ", 0)
    check_eq(c.read_bytes(0, 2), "ZZ", "copie privée modifiable")
    c.unmap()
    check_eq(file.read(path), "AB23456789", "copy-on-write : fichier intact")
    raises(() => vm.map_file(path, false, false, 1), "ArgumentError", "offset non aligné")
    raises(() => vm.map_file(path, false, false, 0, 100), "ArgumentError", "longueur trop grande")
    raises(() => vm.map_file(os.join(os.tmp_dir(), "inexistant_alex_xyz")), "IoError", "fichier absent")
    raises(() => vm.map_file(os.tmp_dir()), "ArgumentError", "répertoire refusé")
    p2 := vm.map_file(path, false, false, 0, 4)
    check_eq(p2.read_bytes(0, 4), "AB23", "longueur partielle")
    p2.unmap()
    file.delete(path)

# ---------------------------------------------------------------------
# Libération automatique par le ramasse-miettes
# ---------------------------------------------------------------------

func orphan_buffers(n):
    i := 0
    while i < n:
        b := buffer.Buffer(32)
        b.write("u32", i, 0)
        i = i + 1

func view_of_temp():
    return buffer.Buffer(16).view(0, 16)

func t_gc_auto_free():
    gc.collect()
    base := memory.stats()["managed_blocks"]
    orphan_buffers(500)
    gc.collect()
    check_eq(memory.stats()["managed_blocks"], base, "500 Buffer abandonnés : blocs natifs libérés par le GC")
    check_eq(memory.stats()["managed_bytes"] < 1000, true, "octets natifs rendus")
    v := view_of_temp()
    v.write("u32", 4242, 0)
    gc.collect()
    check_eq(v.read("u32", 0), 4242, "une vue garde son Buffer vivant (pas libéré sous elle)")
    sub := v.slice(0, 8)
    v = null
    gc.collect()
    check_eq(sub.read("u32", 0), 4242, "une sous-vue aussi")
    check_eq(memory.stats()["managed_blocks"], base + 1, "un seul bloc retenu")
    sub = null
    gc.collect()
    check_eq(memory.stats()["managed_blocks"], base, "tout est libéré une fois les vues abandonnées")
    a := buffer.Arena(64)
    av := a.alloc(8)
    av.write("u8", 7, 0)
    a = null
    gc.collect()
    check_eq(av.read("u8", 0), 7, "une vue d'arène garde l'arène vivante")
    av = null

# ---------------------------------------------------------------------
# Comptage global
# ---------------------------------------------------------------------

func t_global_stats():
    st := memory.stats()
    check_eq(st["raw_blocks"], 0, "aucun bloc brut restant")
    check_eq(st["mapped_blocks"], 0, "aucune région mappée restante")
    check_eq(st["external_blocks"], 0, "aucune région externe restante")
    check_eq(st["managed_blocks"], 0, "aucun bloc géré restant")
    check_eq(st["live_bytes"], 0, "live_bytes = 0")
    check(st["peak_bytes"] > 0, "peak_bytes")
    check_eq(st["total_allocs"] - st["total_frees"], 0, "allocations = libérations")
    check_eq(free.leak_report(), "aucune fuite", "aucune fuite")
    check_eq(memory.check_all(), 0, "check_all sur registre vide")

func main():
    run("informations", t_info)
    run("Buffer : base", t_buffer_basic)
    run("Buffer : tous les types", t_buffer_types)
    run("Buffer : gros-boutiste", t_buffer_endian)
    run("Buffer : tableaux, octets, chaînes", t_buffer_arrays_strings)
    run("Buffer : bornes et erreurs", t_buffer_bounds)
    run("Buffer : non initialisé, alignement", t_buffer_uninit_alignment)
    run("Buffer : cycle de vie, use-after-free", t_buffer_lifecycle)
    run("Buffer : resize, gel, clone", t_buffer_resize_freeze_clone)
    run("Buffer : copie, recherche, comparaison", t_buffer_copy_find)
    run("Buffer : canaris de débordement", t_guards)
    run("quota mémoire", t_quota)
    run("scoped / arènes scopées", t_scoped)
    run("FreeList / free.scope", t_freelist)
    run("MemoryView : base et bornes", t_view_basic)
    run("MemoryView : lecture seule", t_view_readonly)
    run("MemoryView : invalidation", t_view_invalidation)
    run("MemoryView : opérations", t_view_ops)
    run("MemoryView : hexdump", t_hexdump)
    run("Arena", t_arena)
    run("unsafe : la frontière", t_unsafe_gate)
    run("unsafe : fuites", t_unsafe_leaks)
    run("alloc : niveau brut", t_alloc_raw)
    run("free : erreurs", t_free_errors)
    run("free : release", t_free_release)
    run("Pointer", t_pointer)
    run("Pointer : chaînes C", t_pointer_cstr)
    run("Pointer : sur Buffer", t_pointer_from_buffer)
    run("contrôles coupés", t_checks_off)
    run("régions externes (ffi)", t_track_external)
    run("interop ffi", t_ffi_interop)
    run("Ref", t_ref)
    run("Rc / Weak", t_rc)
    run("RefCell", t_refcell)
    run("HandleTable", t_handles)
    run("virtual_memory : base", t_vm_basic)
    run("virtual_memory : protections", t_vm_protect)
    run("virtual_memory : réserve, pages de garde", t_vm_reserve_guard)
    run("virtual_memory : conseils, résidence", t_vm_advice)
    run("virtual_memory : fichiers", t_vm_file)
    run("libération automatique (GC)", t_gc_auto_free)
    gc.collect()
    run("comptage global", t_global_stats)

if not memory.supported():
    print("memory non supporté ici : test ignoré")
else:
    main()

print(f"memory : {stats[0]} vérifications OK, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_memory : échecs")
