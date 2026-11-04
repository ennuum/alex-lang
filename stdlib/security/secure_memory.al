# ALEX STANDARD LIBRARY — security.secure_memory
#
# Secrets en mémoire protégée : un SecureBuffer place ses octets dans des pages dédiées (mmap), VERROUILLÉES en
# mémoire vive quand le système le permet (mlock : jamais écrites dans le swap), rendues INACCESSIBLES
# (PROT_NONE) en dehors des accès explicites, et EFFACÉES de façon non optimisable à la destruction.
# Les str d'ALEX sont immuables et gérées par le ramasse-miettes : un secret qui passe par une str ne peut pas
# être effacé — garder les secrets en SecureBuffer (ou en listes d'octets effacées avec security.wipe).
#
#   use security.secure_memory as sm
#   s := sm.from_text("mot de passe")
#   print(s.size(), s.locked)                          # 12 true (si mlock autorisé)
#   s.access((octets) => verifier(octets))             # accès temporaire (pages ouvertes puis refermées)
#   print(s.equals("mot de passe"))                    # comparaison en temps constant
#   s.destroy()                                        # effacement + libération ; tout accès lève ensuite
#   with sm.SecureBuffer(32) as cle:                   # détruit en sortie de bloc
#       cle.write(random_secure.random_bytes(32))
#
# Erreurs : SecurityError (tampon détruit, taille), MemoryError (accès direct aux pages fermées).

from core use len, type
from collections use append
use string as _s
use memory.virtual_memory as _vm
use _native_memory as _m
use security.security as _sec
use _native_reflect as _r

class SecureBuffer:
    func init(size):
        if type(size) != "int" or size < 1:
            raise("SecurityError", "SecureBuffer : taille entière >= 1 attendue")
        self.capacity = size
        self.length = 0
        self.region = _vm.map(size)
        self.locked = false
        try:
            self.region.lock()
            self.locked = true
        catch e:
            self.locked = false
        self.destroyed = false
        self._close()

    func _open():
        self.region.protect(_vm.RW)

    func _close():
        self.region.protect(_vm.NONE)

    func _live():
        if self.destroyed:
            raise("SecurityError", "SecureBuffer : tampon détruit")

    func size():
        return self.length

    func is_protected():
        return not self.destroyed and self.region.prot_at(0) == _vm.NONE

    # Remplace le contenu (str UTF-8 ou liste d'octets) ; la liste fournie n'est PAS effacée.
    func write(data):
        self._live()
        b := _sec.to_bytes(data)
        if len(b) > self.capacity:
            raise("SecurityError", "SecureBuffer : " + str(len(b)) + " octets pour une capacité de " + str(self.capacity))
        self._open()
        try:
            self.region.fill(0)
            if len(b) > 0:
                self.region.write_bytes(_s.byte_pack(b), 0)
            self.length = len(b)
        finally:
            self._close()
        return self

    # fn(octets) avec une COPIE des octets, effacée après l'appel ; rend le résultat de fn.
    func access(fn):
        self._live()
        self._open()
        data := []
        try:
            if self.length > 0:
                data = _s.byte_unpack(self.region.read_bytes(0, self.length))
        finally:
            self._close()
        try:
            return fn(data)
        finally:
            _sec.wipe(data)

    # Copie des octets (à effacer par l'appelant avec security.wipe).
    func reveal():
        return self.access((d) => d[:])

    # Texte (crée une str non effaçable : à éviter pour les secrets durables).
    func reveal_text():
        return self.access((d) => _s.byte_pack(d))

    func equals(other):
        o := other
        if _is_secure(other):
            o = other.reveal()
        return self.access((d) => _sec.constant_time_equals(d, o))

    func destroy():
        if self.destroyed:
            return
        self._open()
        self.region.fill(0)
        try:
            _m.zero_secure(self.region._block_id(), self.region._base_offset(), self.region.size())
        catch e:
            self.region.fill(0)
        if self.locked:
            try:
                self.region.unlock()
            catch e:
                self.locked = false
        self.region.unmap()
        self.length = 0
        self.destroyed = true

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.destroy()

    func __str__():
        if self.destroyed:
            return "SecureBuffer(détruit)"
        return "SecureBuffer(" + str(self.length) + " octets, ***)"

func _is_secure(v):
    return _r.is_instance(v) and _r.has_field(v, "region") and _r.has_field(v, "capacity")

func from_bytes(data):
    b := _sec.to_bytes(data)
    n := len(b)
    if n < 1:
        n = 1
    return SecureBuffer(n).write(b)

func from_text(text):
    return from_bytes(text)

# Verrouillage mémoire disponible (mlock autorisé) ?
func can_lock():
    b := SecureBuffer(16)
    ok := b.locked
    b.destroy()
    return ok
