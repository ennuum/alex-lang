# ALEX STANDARD LIBRARY — memory.memory_protection
#
# Protection de la mémoire : notation des droits (« rwx »), politique W^X, gel temporaire de tampons,
# régions à pages de garde, effacement sûr des secrets.
#
#   use memory.memory_protection as mp
#   print(mp.to_string(mp.RX), mp.parse("rw-"))       # r-x 3
#   print(mp.allows(mp.parse("r--"), "w"))            # false
#   mp.with_readonly(tampon, lire_seulement)          # tampon gelé pendant l'appel, dégelé ensuite
#   g := mp.guarded(100)                              # 100 octets collés à une page interdite
#   g.write("u8", 1, 99)                              # ok
#   g.write("u8", 1, 100)                             # erreur détectée immédiatement
#   mp.wipe(tampon_de_clé)                            # zéros non optimisables (zero_secure)
#   r := mp.ProtectedRegion(4096)                     # région de pages dont on bascule les droits
#   r.seal()                                          # lecture seule
#
# Protections : NONE=0 READ=1 WRITE=2 EXEC=4 (et combinaisons) ; EXEC exige un bloc unsafe ;
# WRITE+EXEC est toujours refusé.
# Erreurs : ArgumentError (notation invalide, W^X), MemoryError (accès refusé), UnsafeError, TypeError.

from core use len, type
use string as _s
use _native_memory as _m
use memory.virtual_memory as _vm

const NONE := 0
const READ := 1
const WRITE := 2
const EXEC := 4
const RW := 3
const RX := 5

func to_string(prot):
    out := ""
    if (prot & READ) != 0:
        out += "r"
    else:
        out += "-"
    if (prot & WRITE) != 0:
        out += "w"
    else:
        out += "-"
    if (prot & EXEC) != 0:
        out += "x"
    else:
        out += "-"
    return out

# "rw-" / "rx" / "r" -> entier ; ArgumentError pour un caractère inconnu.
func parse(text):
    p := 0
    for c in text:
        if c == 'r':
            p = p | READ
        elif c == 'w':
            p = p | WRITE
        elif c == 'x':
            p = p | EXEC
        elif c != '-' and c != 'p' and c != 's':
            raise("ArgumentError", "memory_protection.parse : caractère '" + str(c) + "' inconnu dans \"" + text + "\"")
    return p

# Le droit ("r", "w" ou "x") est-il accordé ?
func allows(prot, right):
    return (prot & parse(right)) == parse(right)

func is_wx(prot):
    return (prot & WRITE) != 0 and (prot & EXEC) != 0

# Lève ArgumentError si prot viole W^X.
func check_wx(prot, where="memory_protection"):
    if is_wx(prot):
        raise("ArgumentError", where + " : WRITE+EXEC refusé (politique W^X)")
    return prot

# Gèle source (Buffer) pendant body(source) puis rétablit son état d'origine, même sur erreur.
func with_readonly(source, body):
    was := source.is_readonly()
    if not was:
        source.freeze()
    try:
        return body(source)
    finally:
        if not was:
            source.thaw()

# Efface (zéros, écriture que le compilateur ne peut supprimer) un Buffer, une vue ou une région.
func wipe(target):
    target.fill(0)
    try:
        _m.zero_secure(target._block_id(), target._base_offset(), target.size())
    catch AttributeError:
        pass
    return null

# Région de size octets placée contre une page PROT_NONE (débordement détecté à l'octet).
func guarded(size, at_end=true):
    return _vm.map_guarded(size, at_end)

# Région de pages dont on bascule les droits en bloc : seal (lecture seule), unseal (lecture/écriture),
# lock_out (aucun accès), et historique des changements.
class ProtectedRegion:
    func init(size, prot=3):
        check_wx(prot, "ProtectedRegion")
        self.region = _vm.map(size, prot)
        self.size = size
        self.prot = prot
        self.history = [to_string(prot)]

    func set(prot):
        check_wx(prot, "ProtectedRegion.set")
        self.region.protect(prot)
        self.prot = prot
        self.history = self.history + [to_string(prot)]

    func seal():
        self.set(READ)

    func unseal():
        self.set(RW)

    func lock_out():
        self.set(NONE)

    func is_sealed():
        return self.prot == READ

    func readable():
        return (self.prot & READ) != 0

    func writable():
        return (self.prot & WRITE) != 0

    # Droits effectifs de la page contenant offset (relus au noyau).
    func prot_at(offset=0):
        return self.region.prot_at(offset)

    func read(type_name, offset=0):
        return self.region.read(type_name, offset)

    func write(type_name, value, offset=0):
        return self.region.write(type_name, value, offset)

    func view(offset=0, length=null):
        return self.region.view(offset, length)

    # Efface puis démappe.
    func destroy():
        if self.prot != RW:
            self.region.protect(RW)
        self.region.fill(0)
        self.region.unmap()

    func __str__():
        return "ProtectedRegion(" + str(self.size) + " o, " + to_string(self.prot) + ")"

# Teste sans lever : vrai si lire / écrire l'octet offset de target réussit.
func can_read(target, offset=0):
    try:
        target.read("u8", offset)
        return true
    catch (MemoryError, IndexError):
        return false

func can_write(target, offset=0):
    try:
        v := target.read("u8", offset)
        target.write("u8", v, offset)
        return true
    catch (MemoryError, IndexError):
        return false
