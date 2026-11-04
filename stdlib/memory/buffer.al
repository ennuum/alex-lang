# ALEX STANDARD LIBRARY — memory.buffer
#
# Tampon d'octets SÛR et PROPRIÉTAIRE : le niveau « gestion automatique » du modèle
# hybride. Aucun bloc unsafe n'est jamais nécessaire.
#
#   use memory.buffer as buffer
#   b := buffer.Buffer(1024)                 # zéro-initialisé, aligné sur 16
#   b.write("u32", 0xCAFEBABE, 0, true)      # gros-boutiste
#   print(b.read("u8", 0))                   # 202
#   v := b.view(16, 64)                      # MemoryView borné
#   b.free()                                 # idempotent
#
# Garanties
#   - bornes vérifiées à chaque accès (IndexError) ; canaris avant/après le bloc, contrôlés
#     à la libération et par check() : un débordement d'un code natif/unsafe est détecté
#     (MemoryError) ;
#   - utilisation après free() => MemoryError (jamais de lecture de mémoire libérée) ;
#   - gel : freeze() rend le tampon en lecture seule (écritures refusées, même via ses vues) ;
#   - libération AUTOMATIQUE à trois niveaux :
#       1. scoped(size, body) / Arena : libération déterministe à la sortie de portée,
#          y compris si body lève une exception (ALEX n'a pas de `finally`) ;
#       2. free() explicite ;
#       3. ramasse-miettes : un « garde » natif attaché au Buffer libère le bloc quand le GC détruit
#          un Buffer devenu inaccessible (le GC de la VM est actif : module gc). Il est déclenché par le
#          NOMBRE d'objets ALEX, pas par les octets natifs : un gros Buffer abandonné peut y rester
#          longtemps — pour borner la consommation, préférer 1 ou 2, ou appeler gc.collect().
#          Une MemoryView garde son Buffer vivant ; un Pointer/une adresse brute (address(),
#          pointer.from_buffer) NE le garde PAS : conserver le Buffer tant qu'on s'en sert.
#
# Types : bool i8 u8 i16 u16 i32 u32 i64 u64 f32 f64 ptr ;
#   alias int=i32 uint=u32 long=i64 size_t=u64 float=f32 double=f64 byte=u8.
#   u64 > 2^63-1 : ValueError à la lecture (lire en i64).
#
# Erreurs : IndexError, MemoryError, ArgumentError, TypeError, ValueError.

from core use len, type
from collections use append
use _native_memory as _m
use memory.memory_view as _mv

class Buffer:
    # `size` octets (>= 1). zero=false => motif 0xCD (détecte les lectures non initialisées).
    func init(size, zero=true, align=16, tag=null):
        self._id = _m.alloc(size, align, zero, tag)
        self._guard = _m.guard(self._id)

    func _live():
        if self._id == null:
            raise("MemoryError", "memory.buffer : Buffer déjà libéré (utilisation après free)")
        return self._id

    # --- informations ---------------------------------------------------

    func size():
        return _m.size(self._live())

    # Adresse brute du premier octet (pour ffi) ; invalide après free()/resize().
    func address():
        return _m.address(self._live())

    func alive():
        return self._id != null

    func is_readonly():
        return _m.is_readonly(self._live())

    func _block_id():
        return self._live()

    func _base_offset():
        return 0

    # --- accès typés (chemin direct, sans objet intermédiaire) ----------

    func read(type_name, offset=0, big=false):
        return _m.read(self._live(), offset, type_name, big)

    func write(type_name, value, offset=0, big=false):
        return _m.write(self._live(), offset, type_name, value, big)

    func read_array(type_name, count, offset=0, big=false):
        step := _m.type_size(type_name)
        id := self._live()
        out := []
        i := 0
        while i < count:
            append(out, _m.read(id, offset + i * step, type_name, big))
            i = i + 1
        return out

    func write_array(type_name, values, offset=0, big=false):
        step := _m.type_size(type_name)
        id := self._live()
        i := 0
        for v in values:
            _m.write(id, offset + i * step, type_name, v, big)
            i = i + 1
        return i * step

    func read_bytes(offset=0, length=null):
        n := length
        if n == null:
            n = _m.size(self._live()) - offset
        return _m.read_bytes(self._live(), offset, n)

    func write_bytes(data, offset=0):
        return _m.write_bytes(self._live(), offset, data)

    func read_str(offset=0):
        return _m.read_cstr(self._live(), offset, _m.size(self._live()) - offset)

    func write_str(text, offset=0):
        return _m.write_bytes(self._live(), offset, text + "\0")

    func fill(byte_value=0, offset=0, length=null):
        n := length
        if n == null:
            n = _m.size(self._live()) - offset
        _m.fill(self._live(), offset, n, byte_value)
        return null

    # Efface avec une écriture non supprimable par l'optimiseur (clés, secrets).
    func wipe():
        _m.zero_secure(self._live(), 0, _m.size(self._live()))
        return null

    # --- vues, copie, comparaison ---------------------------------------

    func view(offset=0, length=null, readonly=false):
        return _mv.from_block(self._live(), offset, length, readonly, self)

    func copy_from(source, source_offset=0, offset=0, length=null):
        return self.view().copy_from(source, source_offset, offset, length)

    func copy_to(destination, offset=0, destination_offset=0, length=null):
        return destination.copy_from(self.view(), offset, destination_offset, length)

    func find(needle, offset=0):
        return self.view().find(needle, offset)

    func equals(other):
        return self.view().equals(other.view())

    func compare(other):
        return self.view().compare(other.view())

    func to_bytes():
        return self.view().to_bytes()

    func hexdump(width=16, max_bytes=256):
        return self.view().hexdump(width, max_bytes)

    # Nouveau Buffer indépendant, même contenu.
    func clone():
        c := Buffer(self.size())
        c.copy_from(self.view())
        return c

    # --- cycle de vie ------------------------------------------------------

    # Redimensionne (contenu conservé, octets ajoutés à zéro). L'adresse peut changer ;
    # les vues dépassant la nouvelle taille deviennent invalides.
    func resize(new_size):
        _m.realloc(self._live(), new_size, true)
        return self

    # Lecture seule (même via les vues). thaw() annule.
    func freeze():
        _m.set_readonly(self._live(), true)
        return self

    func thaw():
        _m.set_readonly(self._live(), false)
        return self

    # Vérifie les canaris ; MemoryError si un débordement a écrasé les gardes.
    func check():
        return _m.check(self._live())

    # Libère le bloc. Idempotent. Les vues et adresses déjà obtenues deviennent invalides.
    func free():
        if self._id != null:
            ident := self._id
            self._id = null
            _m.free(ident)
        return null

    func close():
        return self.free()

# Arène : allocateur « bump » sur un bloc unique. alloc() rend des MemoryView ; reset()
# invalide TOUTES les vues émises (StaleViewError) et recycle l'espace ; free() libère le tout.
# Idéal pour des données de durée de vie commune (une requête, une frame, un parse).
class Arena:
    func init(capacity, tag=null):
        self._buf = Buffer(capacity, true, 16, tag)
        self._top = 0
        self._epoch = 0
        self._cap = capacity

    # Vue de `size` octets alignée sur `align` (puissance de 2, ABSOLUE : tient compte de
    # l'adresse réelle du bloc). MemoryError si l'arène est pleine.
    func alloc(size, align=1):
        if type(size) != "int" or size < 1:
            raise("ArgumentError", "memory.buffer.Arena.alloc() : size doit être un int >= 1")
        if type(align) != "int" or align < 1 or (align & (align - 1)) != 0:
            raise("ArgumentError", "memory.buffer.Arena.alloc() : align doit être une puissance de 2")
        base := self._buf.address()
        start := ((base + self._top + align - 1) // align) * align - base
        if start + size > self._cap:
            raise("MemoryError", f"memory.buffer.Arena : arène pleine (demandé {size}, restant {self._cap - self._top})")
        self._top = start + size
        return _mv.MemoryView(self._buf._id, start, size, false, self)

    # Invalide les vues, remet à zéro l'espace utilisé et repart du début.
    func reset():
        used := self._top
        self._epoch = self._epoch + 1
        if used > 0:
            self._buf.fill(0, 0, used)
        self._top = 0
        return null

    func used():
        return self._top

    func capacity():
        return self._cap

    func remaining():
        return self._cap - self._top

    func free():
        self._epoch = self._epoch + 1
        self._buf.free()
        return null

# Buffer(size) passé à body(buffer) ; libération GARANTIE à la sortie, y compris sur
# exception. Retourne la valeur de body. Si body retourne le Buffer ou une vue dessus,
# ils sont déjà invalides : copier d'abord ce qui doit survivre (to_bytes()).
func scoped(size, body, zero=true):
    b := Buffer(size, zero)
    failure := null
    result := null
    try:
        result = body(b)
    catch e:
        failure = e
    b.free()
    if failure != null:
        raise(failure.type, failure.message)
    return result

# Même chose pour une arène.
func scoped_arena(capacity, body):
    a := Arena(capacity)
    failure := null
    result := null
    try:
        result = body(a)
    catch e:
        failure = e
    a.free()
    if failure != null:
        raise(failure.type, failure.message)
    return result

# --- constructeurs pratiques -------------------------------------------

# Buffer contenant exactement les octets de `data` (str) ; data non vide.
func from_bytes(data):
    b := Buffer(_m.byte_len(data))
    b.write_bytes(data, 0)
    return b

# Buffer contenant `text` UTF-8 suivi d'un NUL.
func from_str(text):
    b := Buffer(_m.byte_len(text) + 1)
    b.write_str(text, 0)
    return b

# Buffer de valeurs consécutives d'un type : from_values("i32", [1, 2, 3]).
func from_values(type_name, values, big=false):
    b := Buffer(len(values) * _m.type_size(type_name))
    b.write_array(type_name, values, 0, big)
    return b
