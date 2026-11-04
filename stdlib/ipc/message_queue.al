# ALEX STANDARD LIBRARY — ipc.message_queue
#
# Files de messages NOMMÉES entre processus : un processus dépose des messages (texte ou octets), un autre les
# retire dans l'ordre, chacun entier. Deux réalisations derrière la même interface :
#   - PosixQueue : les files POSIX du système (mq_open, Linux) — priorités 0..31 (la plus haute sort d'abord),
#     limites du système (souvent 10 messages de 8 Kio sans privilège : /proc/sys/fs/mqueue) ;
#   - ShmQueue   : une file circulaire en mémoire partagée (ipc.shared_memory), portable, capacité choisie
#     librement ; ordre FIFO strict (la priorité est ignorée).
# open() choisit PosixQueue si le système le permet, sinon ShmQueue (backend="posix" | "shm" pour forcer).
#
#   use ipc.message_queue as mq
#   q := mq.open("travaux", 64, 4096)           # au plus 64 messages de 4096 octets
#   q.send("tâche 1")
#   q.send_json({"id": 2})
#   print(q.receive(1.0))                        # « tâche 1 » (null après 1 s sans message)
#   print(q.receive_json(1.0))
#   q.close()
#   mq.unlink("travaux")
#
# send(data, priorité, délai) renvoie false si la file est restée pleine jusqu'au délai (0 : ne pas attendre) ;
# receive(délai) renvoie null si elle est restée vide.
#
# Erreurs : IpcError (système, message trop grand), TypeError, ArgumentError.

from core use len, type
use json as _json
use os as _os
use _native_sync as _s
use _native_net as _b
use ipc.shared_memory as _shm

func _fail(op, code):
    raise("IpcError", op + " : " + _s.strerror(code) + " [" + _s.errno_name(code) + "]")

func _need_str(fn, data):
    if type(data) != "str":
        raise("TypeError", "message_queue." + fn + " : str attendue (obtenu '" + type(data) + "')")

# Vrai si les files POSIX du système sont utilisables.
func posix_supported():
    return _s.supported_ipc() and _s.mq_supported()

class PosixQueue:
    func init(name, max_messages=10, max_size=8192, mode="open_or_create"):
        h := _s.mq_open(name, mode, max_messages, max_size)
        if h < 0:
            _fail("PosixQueue('" + name + "')", h)
        self.name = name
        self.backend = "posix"
        self._h = h
        a := _s.mq_attr(h)
        self.max_messages = a[0]
        self.max_size = a[1]
        self.closed = false

    func send(data, priority=0, timeout=null):
        _need_str("send", data)
        if _b.blen(data) > self.max_size:
            raise("IpcError", "message_queue.send : message de " + str(_b.blen(data)) + " octets (maximum " + str(self.max_size) + ")")
        r := _s.mq_send(self._h, data, priority, timeout)
        if r < 0:
            _fail("message_queue.send", r)
        return r == 1

    # Message suivant (str), ou null après timeout.
    func receive(timeout=null):
        r := self.receive_with_priority(timeout)
        if r == null:
            return null
        return r[0]

    # (message, priorité), ou null après timeout.
    func receive_with_priority(timeout=null):
        r := _s.mq_receive(self._h, timeout)
        if type(r) == "int":
            if r == 0:
                return null
            _fail("message_queue.receive", r)
        return (r[0], r[1])

    func size():
        return _s.mq_attr(self._h)[2]

    func close():
        if not self.closed:
            _s.mq_close(self._h)
            self.closed = true

    func unlink():
        r := _s.mq_unlink(self.name)
        return r == 0

    func send_json(value, priority=0, timeout=null):
        return self.send(_json.stringify(value), priority, timeout)

    func receive_json(timeout=null):
        m := self.receive(timeout)
        if m == null:
            return null
        return _json.parse(m)

# ---------------------------------------------------------------- file en mémoire partagée
# En-tête (64 octets) : 0 verrou (i32), 4 séquence « non vide » (i32), 8 séquence « non pleine » (i32),
# 16 tête (i64), 24 queue (i64), 32 nombre de messages (i64), 40 capacité en octets (i64), 48 max_messages,
# 56 max_size. Puis l'anneau ; chaque message : longueur (u32 sur 4 octets) puis ses octets.
const _HDR := 64

class ShmQueue:
    func init(name, max_messages=64, max_size=8192, mode="open_or_create"):
        cap := max_messages * (max_size + 4)
        existed := _shm.exists("mq-" + name)
        if mode == "open" and not existed:
            raise("IpcError", "message_queue : file '" + name + "' inexistante [ENOENT]")
        if mode == "create" and existed:
            raise("IpcError", "message_queue : file '" + name + "' déjà existante [EEXIST]")
        self.mem = _shm.SharedMemory("mq-" + name, _HDR + cap, "open_or_create")
        self.name = name
        self.backend = "shm"
        self.lock = _shm.SharedMutex(self.mem, 0)
        self.lock.lock()
        if self.mem.get(40, "i64") == 0:     # première ouverture : initialisation
            self.mem.set(40, "i64", cap)
            self.mem.set(48, "i64", max_messages)
            self.mem.set(56, "i64", max_size)
        self.capacity = self.mem.get(40, "i64")
        self.max_messages = self.mem.get(48, "i64")
        self.max_size = self.mem.get(56, "i64")
        self.lock.unlock()
        self.closed = false

    func _used():
        head := self.mem.get(16, "i64")
        tail := self.mem.get(24, "i64")
        return tail - head

    func _put(pos, data):
        n := _b.blen(data)
        p := pos % self.capacity
        first := self.capacity - p
        if first >= n:
            self.mem.write(_HDR + p, data)
        else:
            self.mem.write(_HDR + p, _b.bslice(data, 0, first))
            self.mem.write(_HDR, _b.bslice(data, first, n))

    func _get(pos, n):
        p := pos % self.capacity
        first := self.capacity - p
        if first >= n:
            return self.mem.read(_HDR + p, n)
        return self.mem.read(_HDR + p, first) + self.mem.read(_HDR, n - first)

    func _u32(n):
        return _b.from_bytes([n & 255, (n >> 8) & 255, (n >> 16) & 255, (n >> 24) & 255])

    func _from_u32(s):
        b := _b.to_bytes(s)
        return b[0] | (b[1] << 8) | (b[2] << 16) | (b[3] << 24)

    func send(data, priority=0, timeout=null):
        _need_str("send", data)
        n := _b.blen(data)
        if n > self.max_size:
            raise("IpcError", "message_queue.send : message de " + str(n) + " octets (maximum " + str(self.max_size) + ")")
        deadline := null
        if timeout != null:
            deadline = _os.monotonic_time() + timeout
        while true:
            self.lock.lock()
            count := self.mem.get(32, "i64")
            if count < self.max_messages and self.capacity - self._used() >= n + 4:
                tail := self.mem.get(24, "i64")
                self._put(tail, self._u32(n) + data)
                self.mem.set(24, "i64", tail + n + 4)
                self.mem.set(32, "i64", count + 1)
                self.mem.atomic_add(4, 1, 32)
                self.lock.unlock()
                self.mem.wake(4, -1)
                return true
            seq := self.mem.atomic_load(8, 32)
            self.lock.unlock()
            left := null
            if deadline != null:
                left = deadline - _os.monotonic_time()
                if left <= 0:
                    return false
            self.mem.wait(8, seq, left)

    func receive_with_priority(timeout=null):
        deadline := null
        if timeout != null:
            deadline = _os.monotonic_time() + timeout
        while true:
            self.lock.lock()
            count := self.mem.get(32, "i64")
            if count > 0:
                head := self.mem.get(16, "i64")
                n := self._from_u32(self._get(head, 4))
                data := self._get(head + 4, n)
                head = head + 4 + n
                if count == 1:
                    head = 0
                    self.mem.set(24, "i64", 0)
                self.mem.set(16, "i64", head)
                self.mem.set(32, "i64", count - 1)
                self.mem.atomic_add(8, 1, 32)
                self.lock.unlock()
                self.mem.wake(8, -1)
                return (data, 0)
            seq := self.mem.atomic_load(4, 32)
            self.lock.unlock()
            left := null
            if deadline != null:
                left = deadline - _os.monotonic_time()
                if left <= 0:
                    return null
            self.mem.wait(4, seq, left)

    func receive(timeout=null):
        r := self.receive_with_priority(timeout)
        if r == null:
            return null
        return r[0]

    func size():
        return self.mem.get(32, "i64")

    func close():
        if not self.closed:
            self.mem.close()
            self.closed = true

    func unlink():
        return _shm.unlink("mq-" + self.name)

    func send_json(value, priority=0, timeout=null):
        return self.send(_json.stringify(value), priority, timeout)

    func receive_json(timeout=null):
        m := self.receive(timeout)
        if m == null:
            return null
        return _json.parse(m)

# Ouvre (ou crée) la file nommée. backend : null (POSIX si possible, sinon mémoire partagée), "posix" ou "shm".
# Les deux bouts doivent utiliser le même backend.
func open(name, max_messages=10, max_size=8192, backend=null, mode="open_or_create"):
    if backend == null:
        if posix_supported():
            backend = "posix"
        else:
            backend = "shm"
    if backend == "posix":
        return PosixQueue(name, max_messages, max_size, mode)
    if backend == "shm":
        return ShmQueue(name, max_messages, max_size, mode)
    raise("ArgumentError", "message_queue.open : backend \"posix\" ou \"shm\" attendu")

# Supprime la file (les deux backends) ; renvoie true si quelque chose a été supprimé.
func unlink(name):
    done := false
    if _s.supported_ipc():
        if _s.mq_unlink(name) == 0:
            done = true
        if _shm.unlink("mq-" + name):
            done = true
    return done
