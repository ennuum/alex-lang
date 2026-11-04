# Démo du module memory : modèle hybride (Safe Alex / unsafe Alex).
use memory
use memory.buffer as buffer
use memory.pointer as pointer
use memory.reference as reference
use memory.virtual_memory as vm

print("=== Safe Alex : gestion automatique ===")

func remplir(b):
    b.write("u32", 3405691582, 0, true)      # 0xCAFEBABE en gros-boutiste
    b.write_str("bonjour", 8)
    print(b.view(0, 16).hexdump())
    return b.read_str(8)

print(memory.scoped(32, remplir))             # tampon libéré à la sortie, même sur exception

arene := buffer.Arena(128)
v := arene.alloc(16, 8)
v.write("i64", 42)
print(v.read("i64"))
arene.reset()                                 # invalide toutes les vues de l'arène
try:
    v.read("i64")
catch e:
    print(e.type)                             # StaleViewError

compteur := reference.rc("ressource", (x) => print("relâchée :", x))
copie := compteur.clone()
compteur.drop()
copie.drop()                                  # dernier propriétaire : on_drop s'exécute

print("=== unsafe Alex : pointeurs / mémoire brute ===")

func brut():
    p := pointer.malloc(4, "i32")
    p.write_array([10, 20, 30, 40])
    print(p.offset(2).read())                 # 30
    try:
        p.offset(4).read()                    # un élément après la fin : MemoryError, pas de segfault
    catch e:
        print(e.type)
    p.free()

memory.unsafe_block(brut, "error")            # "error" : toute fuite devient une erreur

try:
    pointer.malloc(4)                         # hors bloc unsafe
catch e:
    print(e.type)                             # UnsafeError

print("=== mémoire virtuelle ===")
ps := vm.page_size()
r := vm.map(2 * ps)
r.write("u8", 1, 0)
r.protect(vm.READ, 0, ps)                     # première page en lecture seule
try:
    r.write("u8", 2, 0)
catch e:
    print(e.type)                             # MemoryError (pas de crash)
r.unmap()
print(memory.leak_report())                   # aucune fuite
