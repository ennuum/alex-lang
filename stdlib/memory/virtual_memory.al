# ALEX STANDARD LIBRARY — memory.virtual_memory
#
# Mémoire virtuelle : pages anonymes ou fichiers mappés, avec PROTECTIONS par page
# (mmap / mprotect / madvise / mlock sous POSIX ; VirtualAlloc sous Windows).
#
#   use memory.virtual_memory as vm
#   r := vm.map(3 * vm.page_size())                 # 3 pages lecture+écriture, zéro
#   r.write("u32", 7, 0)
#   r.protect(vm.READ, 0, vm.page_size())           # 1re page : lecture seule
#   r.write("u32", 8, 0)                            # MemoryError (protection), pas de crash
#   r.unmap()
#
# Protections (combinables par +) : NONE=0 READ=1 WRITE=2 EXEC=4 ; RW=3 RX=5.
# Politique W^X : WRITE+EXEC refusé (ArgumentError). Toute protection contenant EXEC exige
# un bloc unsafe (memory.unsafe) — la mémoire exécutable n'est pas « sûre ».
#
# Les accès Region.read/write/... sont BORNÉS et contrôlent la protection de chaque page
# touchée : une page PROT_NONE ou lecture seule lève MemoryError au lieu de planter le
# processus. (Seul un accès par Pointer avec set_checks(false) peut encore déclencher un
# signal.) Les vues (Region.view) héritent de ces contrôles.
#
# Régions à page de garde : map_guarded(size) place les données contre une page PROT_NONE ;
# un débordement (ou, avec at_end=false, un dépassement par le bas) est détecté
# immédiatement et à l'octet près.
#
# Limites : vm_map_file/advise/resident/lock sont POSIX (Windows : IoError « non supporté »).
# Un `vm.map` anonyme est zéro-initialisé ; advise("dontneed") sur un mapping anonyme
# privé REMET les pages à zéro (Linux). Les longueurs/offsets de protect/lock/advise/sync
# sont multiples de page_size().
#
# Erreurs : MemoryError (protection, mmap refusé), ArgumentError, IndexError, IoError,
#           UnsafeError (EXEC hors bloc unsafe).

from core use len, type
from collections use append
use _native_memory as _m
use memory.unsafe as _u
use memory.memory_view as _mv

const NONE := 0
const READ := 1
const WRITE := 2
const EXEC := 4
const RW := 3
const RX := 5

func page_size():
    return _m.page_size()

# Plus petit multiple de page >= n.
func round_up(n):
    ps := _m.page_size()
    return ((n + ps - 1) // ps) * ps

func _check_prot(fn, prot):
    if type(prot) != "int":
        raise("TypeError", "memory.virtual_memory." + fn + "() : protection int attendue (obtenu '" + type(prot) + "')")
    if (prot & WRITE) != 0 and (prot & EXEC) != 0:
        raise("ArgumentError", "memory.virtual_memory." + fn + "() : protection WRITE+EXEC refusée (politique W^X)")
    if (prot & EXEC) != 0:
        _u.require("memory.virtual_memory." + fn + " (protection EXEC)")
    return prot

class Region:
    # Interne : préférer map() / reserve() / map_file().
    func init(block_id):
        self._id = block_id

    func _live():
        if self._id == null:
            raise("MemoryError", "memory.virtual_memory : région déjà démappée (utilisation après unmap)")
        return self._id

    func size():
        return _m.size(self._live())

    func address():
        return _m.address(self._live())

    func page_count():
        return round_up(_m.size(self._live())) // _m.page_size()

    func alive():
        return self._id != null

    func _block_id():
        return self._live()

    func _base_offset():
        return 0

    # --- protections ------------------------------------------------------

    # Change la protection de [offset, offset+length) (multiples de page). length=null =>
    # jusqu'à la fin de la région.
    func protect(prot, offset=0, length=null):
        _check_prot("protect", prot)
        n := length
        if n == null:
            n = round_up(_m.size(self._live())) - offset
        _m.vm_protect(self._live(), offset, n, prot)
        return null

    # Protection de la page contenant `offset`.
    func prot_at(offset=0):
        return _m.vm_prot(self._live(), offset)

    # --- accès (bornés + protection vérifiée) -----------------------------

    func read(type_name, offset=0, big=false):
        return _m.read(self._live(), offset, type_name, big)

    func write(type_name, value, offset=0, big=false):
        return _m.write(self._live(), offset, type_name, value, big)

    func read_bytes(offset=0, length=null):
        n := length
        if n == null:
            n = _m.size(self._live()) - offset
        return _m.read_bytes(self._live(), offset, n)

    func write_bytes(data, offset=0):
        return _m.write_bytes(self._live(), offset, data)

    func fill(byte_value=0, offset=0, length=null):
        n := length
        if n == null:
            n = _m.size(self._live()) - offset
        _m.fill(self._live(), offset, n, byte_value)
        return null

    func view(offset=0, length=null, readonly=false):
        return _mv.from_block(self._live(), offset, length, readonly, self)

    # --- gestion mémoire --------------------------------------------------

    # Verrouille en RAM (pas de swap) : mlock. Peut échouer selon RLIMIT_MEMLOCK (IoError).
    func lock(offset=0, length=null):
        n := length
        if n == null:
            n = round_up(_m.size(self._live())) - offset
        _m.vm_lock(self._live(), offset, n, true)
        return null

    func unlock(offset=0, length=null):
        n := length
        if n == null:
            n = round_up(_m.size(self._live())) - offset
        _m.vm_lock(self._live(), offset, n, false)
        return null

    # Conseil au noyau : "normal" "sequential" "random" "willneed" "dontneed".
    func advise(advice, offset=0, length=null):
        n := length
        if n == null:
            n = round_up(_m.size(self._live())) - offset
        _m.vm_advise(self._live(), offset, n, advice)
        return null

    # Nombre de pages actuellement résidentes en RAM dans la plage.
    func resident(offset=0, length=null):
        n := length
        if n == null:
            n = round_up(_m.size(self._live())) - offset
        return _m.vm_resident(self._live(), offset, n)

    # Écrit les modifications d'un mapping de fichier PARTAGÉ sur le disque (msync).
    func sync(offset=0, length=null, asynchronous=false):
        n := length
        if n == null:
            n = round_up(_m.size(self._live())) - offset
        _m.vm_sync(self._live(), offset, n, asynchronous)
        return null

    # Démappe. Idempotent. Vues et adresses obtenues deviennent invalides.
    func unmap():
        if self._id != null:
            ident := self._id
            self._id = null
            _m.vm_unmap(ident)
        return null

    func free():
        return self.unmap()

# Région anonyme de `size` octets (arrondie à la page), zéro-initialisée.
func map(size, prot=3, tag=null):
    _check_prot("map", prot)
    return Region(_m.vm_map(size, prot, tag))

# Réserve de l'espace d'adressage inaccessible (PROT_NONE) ; rendre des pages utilisables
# avec protect(READ + WRITE, ...). Utile pour des tas/piles à croissance contrôlée.
func reserve(size, tag=null):
    return Region(_m.vm_map(size, 0, tag))

# Mappe un fichier. writable+shared => les écritures atteignent le fichier ; writable sans
# shared => copie privée (copy-on-write, le fichier reste intact). offset multiple de page.
func map_file(path, writable=false, shared=false, offset=0, length=null):
    return Region(_m.vm_map_file(path, writable, shared, offset, length, null))

# Données bordées de pages PROT_NONE : tout accès hors des `size` octets lève MemoryError.
class GuardedRegion:
    func init(region, data_offset, size):
        self._r = region
        self._off = data_offset
        self._size = size

    func size():
        return self._size

    func address():
        return self._r.address() + self._off

    func _span(fn, offset, n):
        # PAS de contrôle de bornes ALEX volontaire : c'est la page de garde qui protège,
        # y compris pour les accès franchissant la fin des données.
        return self._off + offset

    func read(type_name, offset=0, big=false):
        return self._r.read(type_name, self._span("read", offset, 0), big)

    func write(type_name, value, offset=0, big=false):
        return self._r.write(type_name, value, self._span("write", offset, 0), big)

    func read_bytes(offset=0, length=null):
        n := length
        if n == null:
            n = self._size - offset
        return self._r.read_bytes(self._span("read_bytes", offset, n), n)

    func write_bytes(data, offset=0):
        return self._r.write_bytes(data, self._span("write_bytes", offset, 0))

    func fill(byte_value=0, offset=0, length=null):
        n := length
        if n == null:
            n = self._size - offset
        return self._r.fill(byte_value, self._span("fill", offset, n), n)

    func view(offset=0, length=null, readonly=false):
        n := length
        if n == null:
            n = self._size - offset
        if offset < 0 or n < 0 or offset + n > self._size:
            raise("IndexError", f"memory.virtual_memory.GuardedRegion.view() : plage hors données (offset {offset}, longueur {n}, taille {self._size})")
        return self._r.view(self._off + offset, n, readonly)

    func unmap():
        return self._r.unmap()

    func free():
        return self._r.unmap()

# `size` octets utilisables. at_end=true (défaut) : les données finissent exactement sur la
# page de garde suivante (détecte les DÉBORDEMENTS, l'erreur classique) ; at_end=false : elles
# commencent juste après la garde précédente (détecte les dépassements par le bas).
func map_guarded(size, at_end=true, tag=null):
    ps := _m.page_size()
    data_pages := (size + ps - 1) // ps
    r := Region(_m.vm_map((data_pages + 2) * ps, 0, tag))
    r.protect(3, ps, data_pages * ps)
    off := ps
    if at_end:
        off = ps + data_pages * ps - size
    return GuardedRegion(r, off, size)
