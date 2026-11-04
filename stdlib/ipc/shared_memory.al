# ALEX STANDARD LIBRARY — ipc.shared_memory
#
# Mémoire partagée NOMMÉE entre processus (POSIX shm_open + mmap) : les mêmes octets, vus par tous les processus
# qui ouvrent le même nom. Lecture et écriture d'octets et d'entiers à une position, opérations ATOMIQUES (même
# entre processus), attente efficace d'un changement de valeur (futex sous Linux), et deux outils construits
# dessus : SharedMutex (verrou entre processus) et SharedCounter (compteur atomique).
#
#   use ipc.shared_memory as shm
#   m := shm.SharedMemory("mon-appli", 4096)          # créé s'il n'existe pas (zéros), sinon ouvert
#   m.set(0, "i64", 42)
#   m.write(64, "bonjour")
#   print(m.get(0, "i64"), m.read(64, 7))
#   c := shm.SharedCounter(m, 8)
#   c.add(1)                                           # atomique, même avec d'autres processus
#   verrou := shm.SharedMutex(m, 16)
#   verrou.lock()   ...   verrou.unlock()
#   m.close()
#   shm.unlink("mon-appli")                            # le nom disparaît ; la mémoire, au dernier close
#
# Types : i8 u8 i16 u16 i32 u32 i64 f32 f64 (petit-boutiste). Atomiques : mots de 32 ou 64 bits ALIGNÉS
# (position multiple de 4 ou 8). wait / wake : mots de 32 bits.
#
# Erreurs : IpcError (système : nom invalide, droits, déjà existant avec create), IndexError (zone hors de la
# mémoire), ArgumentError, TypeError, TimeoutError (SharedMutex.lock avec délai via try_lock / lock(timeout)).

from core use len, type
use _native_sync as _s
use _native_net as _b

func supported():
    return _s.supported_ipc()

func _fail(op, code):
    name := _s.errno_name(code)
    raise("IpcError", op + " : " + _s.strerror(code) + " [" + name + "]")

class SharedMemory:
    # mode : "open_or_create" (défaut), "create" (échoue si le nom existe), "open" (échoue s'il n'existe pas).
    # size : taille minimale (agrandie si plus grande que l'existante ; 0 avec "open" : taille existante).
    func init(name, size=0, mode="open_or_create"):
        if not _s.supported_ipc():
            raise("IpcError", "ipc.shared_memory : non pris en charge sur cette plateforme")
        r := _s.shm_open(name, size, mode)
        if type(r) == "int":
            _fail("SharedMemory('" + name + "')", r)
        self.name = name
        self.handle = r[0]
        self.size = r[1]
        self.closed = false

    func _h():
        if self.closed:
            raise("IpcError", "SharedMemory '" + self.name + "' : fermée")
        return self.handle

    # n octets à partir de offset (str, binaire possible).
    func read(offset, n):
        return _s.shm_read(self._h(), offset, n)

    # Écrit les octets de data (str) en offset ; renvoie leur nombre.
    func write(offset, data):
        return _s.shm_write(self._h(), offset, data)

    func read_bytes(offset, n):
        return _b.to_bytes(self.read(offset, n))

    func write_bytes(offset, data):
        return self.write(offset, _b.from_bytes(data))

    # Texte terminé par un octet nul (au plus max octets).
    func read_cstring(offset, max=4096):
        if offset + max > self.size:
            max = self.size - offset
        data := self.read(offset, max)
        i := _b.bfind(data, "\u0000", 0)
        if i < 0:
            return data
        return _b.bslice(data, 0, i)

    func write_cstring(offset, text):
        return self.write(offset, text + "\u0000")

    func get(offset, kind):
        return _s.shm_get(self._h(), offset, kind)

    func set(offset, kind, value):
        _s.shm_set(self._h(), offset, kind, value)

    func fill(offset, n, byte=0):
        chunk := ""
        k := 0
        while k < 256:
            chunk = chunk + _b.from_bytes([byte])
            k += 1
        done := 0
        while done < n:
            m := n - done
            if m > 256:
                m = 256
            self.write(offset + done, _b.bslice(chunk, 0, m))
            done += m

    # ---- atomiques (width 32 ou 64) : renvoient l'ancienne valeur ----
    func atomic_load(offset, width=64):
        return _s.shm_atomic(self._h(), offset, width, "load", 0, 0)

    func atomic_store(offset, value, width=64):
        return _s.shm_atomic(self._h(), offset, width, "store", value, 0)

    func atomic_exchange(offset, value, width=64):
        return _s.shm_atomic(self._h(), offset, width, "exchange", value, 0)

    func atomic_add(offset, delta, width=64):
        return _s.shm_atomic(self._h(), offset, width, "add", delta, 0)

    func atomic_sub(offset, delta, width=64):
        return _s.shm_atomic(self._h(), offset, width, "sub", delta, 0)

    func atomic_and(offset, mask, width=64):
        return _s.shm_atomic(self._h(), offset, width, "and", mask, 0)

    func atomic_or(offset, mask, width=64):
        return _s.shm_atomic(self._h(), offset, width, "or", mask, 0)

    func atomic_xor(offset, mask, width=64):
        return _s.shm_atomic(self._h(), offset, width, "xor", mask, 0)

    # Si le mot vaut expected, y écrit new. Renvoie l'ancienne valeur (== expected : réussi).
    func compare_exchange(offset, expected, new, width=64):
        return _s.shm_atomic(self._h(), offset, width, "cas", expected, new)

    # Attend que le mot de 32 bits en offset ne vaille plus expected (ou un wake) ; false après timeout.
    func wait(offset, expected, timeout=null):
        r := _s.shm_wait(self._h(), offset, expected, timeout)
        if r < 0:
            _fail("SharedMemory.wait", r)
        return r == 1

    # Réveille au plus n processus / fils qui attendent sur ce mot (n < 0 : tous) ; renvoie leur nombre.
    func wake(offset, n=-1):
        return _s.shm_wake(self._h(), offset, n)

    # Détache la mémoire de ce processus (le nom reste ; voir unlink).
    func close():
        if not self.closed:
            _s.shm_close(self.handle)
            self.closed = true

    # Supprime le nom (les processus qui l'ont ouverte la gardent jusqu'à leur close).
    func unlink():
        unlink(self.name)

func create(name, size):
    return SharedMemory(name, size, "create")

func open(name):
    return SharedMemory(name, 0, "open")

func open_or_create(name, size):
    return SharedMemory(name, size, "open_or_create")

# Supprime le nom ; renvoie false s'il n'existait pas.
func unlink(name):
    r := _s.shm_unlink(name)
    if r == 0:
        return true
    if _s.errno_name(r) == "ENOENT":
        return false
    _fail("shared_memory.unlink('" + name + "')", r)

func exists(name):
    r := _s.shm_open(name, 0, "open")
    if type(r) == "int":
        return false
    _s.shm_close(r[0])
    return true

# Appelle fn(mémoire) avec une mémoire partagée NEUVE (nom unique), supprimée ensuite.
func with_temporary(size, fn):
    rnd := _b.to_bytes(_b.random_bytes(8))
    name := "alex-tmp-"
    hex := "0123456789abcdef"
    for x in rnd:
        name = name + str(hex[x >> 4]) + str(hex[x & 15])
    m := create(name, size)
    try:
        return fn(m)
    finally:
        m.close()
        unlink(name)

# ---------------------------------------------------------------- outils construits dessus

# Compteur atomique de 64 bits en offset (aligné sur 8).
class SharedCounter:
    func init(memory, offset):
        if offset % 8 != 0:
            raise("ArgumentError", "SharedCounter : position alignée sur 8 octets attendue")
        self.memory = memory
        self.offset = offset

    func value():
        return self.memory.atomic_load(self.offset, 64)

    func set(v):
        self.memory.atomic_store(self.offset, v, 64)

    # Ajoute delta ; renvoie la NOUVELLE valeur.
    func add(delta=1):
        return self.memory.atomic_add(self.offset, delta, 64) + delta

    func sub(delta=1):
        return self.memory.atomic_sub(self.offset, delta, 64) - delta

    func compare_exchange(expected, new):
        return self.memory.compare_exchange(self.offset, expected, new, 64) == expected

# Verrou d'exclusion mutuelle entre PROCESSUS (et fils), sur un mot de 32 bits en offset (aligné sur 4, à zéro
# au départ). Algorithme à futex d'U. Drepper (« Futexes are tricky ») : 0 libre, 1 pris, 2 pris avec attente.
# Pas de propriétaire : si un processus meurt verrou pris, le verrou reste pris (voir force_unlock).
class SharedMutex:
    func init(memory, offset):
        if offset % 4 != 0:
            raise("ArgumentError", "SharedMutex : position alignée sur 4 octets attendue")
        self.memory = memory
        self.offset = offset

    func _cas(expected, new):
        return self.memory.compare_exchange(self.offset, expected, new, 32)

    # Prend le verrou ; renvoie false si timeout secondes passent avant (null : sans limite).
    func lock(timeout=null):
        c := self._cas(0, 1)
        if c == 0:
            return true
        deadline := null
        if timeout != null:
            deadline = _now() + timeout
        if c != 2:
            c = self.memory.atomic_exchange(self.offset, 2, 32)
        while c != 0:
            left := null
            if deadline != null:
                left = deadline - _now()
                if left <= 0:
                    return false
            self.memory.wait(self.offset, 2, left)
            c = self.memory.atomic_exchange(self.offset, 2, 32)
        return true

    func try_lock():
        return self._cas(0, 1) == 0

    func unlock():
        old := self.memory.atomic_sub(self.offset, 1, 32)
        if old == 0:
            self.memory.atomic_store(self.offset, 0, 32)
            raise("LockError", "SharedMutex.unlock : le verrou est libre")
        if old != 1:
            self.memory.atomic_store(self.offset, 0, 32)
            self.memory.wake(self.offset, 1)

    func locked():
        return self.memory.atomic_load(self.offset, 32) != 0

    # Libère un verrou abandonné (processus mort) : à n'utiliser que si l'on SAIT que personne ne le tient.
    func force_unlock():
        self.memory.atomic_store(self.offset, 0, 32)
        self.memory.wake(self.offset, -1)

    # Exécute fn() verrou pris (rendu même en cas d'erreur).
    func run(fn):
        self.lock()
        try:
            return fn()
        finally:
            self.unlock()

use os as _os

func _now():
    return _os.monotonic_time()
