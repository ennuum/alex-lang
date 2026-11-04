# ALEX STANDARD LIBRARY — memory
#
# Gestion de la mémoire en MODÈLE HYBRIDE :
#
#     Safe Alex                              unsafe Alex
#     ─────────                              ───────────
#     gestion automatique                    pointeurs / mémoire brute
#     memory.buffer        Buffer, Arena     memory.alloc    raw, calloc, realloc
#     memory.memory_view   MemoryView        memory.free     address, FreeList
#     memory.reference     Ref Rc Weak ...   memory.pointer  Pointer typé
#                                            memory.virtual_memory  pages, mprotect
#                       frontière : memory.unsafe  (block(), require(), audit)
#
# memory/
#   ├── alloc            allocation : blocs gérés (sûr) et adresses brutes (unsafe)
#   ├── free             libération, détection double free, FreeList / scope, fuites
#   ├── buffer           Buffer propriétaire, Arena, scoped()
#   ├── pointer          Pointer typé + arithmétique (déréférencement = unsafe)
#   ├── reference        Ref, Rc/Weak, RefCell (emprunts vérifiés), HandleTable
#   ├── memory_view      MemoryView : tranches bornées, lecture seule, invalidation
#   └── virtual_memory   mmap : pages, protections R/W/X, fichiers, pages de garde
#   (+ unsafe            le garde-fou : unsafe.block(fonction))
#
# Ce fichier (la façade) offre les raccourcis les plus courants et les diagnostics
# globaux. Les CLASSES (Buffer, MemoryView, Pointer, Ref...) se prennent dans leur
# sous-module :   use memory.buffer as buffer   puis   buffer.Buffer(64)
#
# Exemple SÛR (aucun unsafe) :
#   use memory
#   func saluer(b):
#       b.write_str("bonjour")
#       return b.read_str()
#   print(memory.scoped(256, saluer))       # bonjour — tampon libéré ici, même sur exception
#
# Exemple UNSAFE (isolé et audité) :
#   use memory
#   use memory.pointer as pointer
#   func brut():
#       p := pointer.malloc(4, "i32")
#       p.write(42)
#       print(p.read())
#       p.free()
#   memory.unsafe_block(brut, "error")      # "error" : fuite => LeakError
#
# Garanties du modèle
#   SÛR      jamais de lecture hors bornes, après libération, ni d'écriture en lecture seule :
#            toutes ces erreurs sont des exceptions (IndexError, MemoryError, ...).
#   UNSAFE   tout déréférencement d'adresse exige un bloc unsafe ; par défaut chaque accès
#            est validé contre le registre des régions (MemoryError au lieu d'un segfault).
#            Seul unsafe.set_checks(false) donne l'accès nu de C.
#
# Plateformes : POSIX 64 bits little-endian testé (Linux x86-64). Windows : tout le niveau
# sûr + alloc/pointer/vm_map/protect via VirtualAlloc, NON testé ici ; map_file, advise,
# resident : non supportés. big-endian : supported() est faux.

use _native_memory as _m
use memory.unsafe as _unsafe
use memory.buffer as _buffer
use memory.memory_view as _view
use memory.free as _free
use memory.alloc as _alloc
use memory.virtual_memory as _vm

const VERSION := "1.0.0"

func version():
    return VERSION

func supported():
    return _m.supported()

func page_size():
    return _m.page_size()

func word_size():
    return _m.word_size()

func endianness():
    return _m.endianness()

# Taille en octets d'un type ("i32" -> 4, "ptr" -> 8).
func sizeof(type_name):
    return _m.type_size(type_name)

# --- raccourcis du niveau sûr -------------------------------------------

# Nouveau Buffer(size) zéro-initialisé.
func buffer(size, zero=true, align=16, tag=null):
    return _buffer.Buffer(size, zero, align, tag)

func arena(capacity, tag=null):
    return _buffer.Arena(capacity, tag)

# Buffer passé à body(b), libéré à coup sûr à la sortie.
func scoped(size, body, zero=true):
    return _buffer.scoped(size, body, zero)

func view(source, offset=0, length=null, readonly=false):
    return _view.view(source, offset, length, readonly)

func from_bytes(data):
    return _buffer.from_bytes(data)

# --- raccourcis du niveau unsafe ----------------------------------------

# Exécute body() en mode unsafe (voir memory.unsafe). leaks : "ignore" | "free" | "error".
func unsafe_block(body, leaks="ignore"):
    return _unsafe.block(body, leaks)

# --- configuration / diagnostics ----------------------------------------

func set_limit(max_bytes):
    return _alloc.set_limit(max_bytes)

func limit():
    return _alloc.limit()

# Compteurs du registre (voir memory.alloc.stats).
func stats():
    return _alloc.stats()

# Vérifie les canaris de tous les blocs (MemoryError au premier débordement).
func check_all():
    return _alloc.check_all()

# Régions brutes / mappées / externes non libérées, sous forme de liste.
func leaks():
    return _free.leaks()

func leak_report():
    return _free.leak_report()

# Compteurs d'audit des opérations unsafe.
func unsafe_stats():
    return _unsafe.stats()
