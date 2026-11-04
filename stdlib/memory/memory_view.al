# ALEX STANDARD LIBRARY — memory.memory_view
#
# Vue SÛRE sur une plage d'un bloc mémoire : (bloc, décalage, longueur) — comme une
# tranche (slice) de Go/Rust. Une vue NE POSSÈDE PAS la mémoire : elle ne la libère jamais.
#
# Garanties (niveau sûr, aucun bloc unsafe requis)
#   - tous les accès sont relatifs à la vue et bornés par SA longueur (IndexError) ;
#   - une sous-vue ne peut jamais dépasser sa vue parente ;
#   - vue en lecture seule (readonly) : toute écriture est refusée (MemoryError) ;
#   - bloc libéré => la vue est invalide : MemoryError au prochain accès, jamais de lecture
#     de mémoire libérée (les identifiants de bloc ne sont pas recyclés) ;
#   - bloc réduit (realloc) sous la plage de la vue => MemoryError ;
#   - vues d'une Arena : reset() de l'arène invalide ses vues (StaleViewError).
#
# Création :  buffer.view(offset, length, readonly)  |  memory_view.view(source, ...)
#             region.view(...)  (memory.virtual_memory)  |  vue.slice(offset, length)
#
# Types : voir memory.buffer (bool i8 u8 i16 u16 i32 u32 i64 u64 f32 f64 ptr, + alias).
# `big=true` lit/écrit en gros-boutiste (protocoles réseau).
#
# Erreurs : IndexError, MemoryError, StaleViewError, ArgumentError, TypeError.

from core use len, type
from collections use append
use string as _s
use _native_memory as _m

const _HEX := "0123456789abcdef"

func _hex2(b):
    return _s.substring(_HEX, b // 16, b // 16 + 1) + _s.substring(_HEX, b % 16, b % 16 + 1)

func _need_int(fn, v, label):
    if type(v) != "int":
        raise("TypeError", "memory_view." + fn + "() : " + label + " doit être un int (obtenu '" + type(v) + "')")
    return v

class MemoryView:
    # Constructeur de bas niveau : préférer view() / Buffer.view() / slice().
    func init(block_id, offset, length, readonly=false, owner=null, holder=null):
        self._holder = holder   # propriétaire gardé VIVANT (Buffer, Region) : sans lui le GC libérerait le bloc
        self._id = block_id
        self._off = offset
        self._len = length
        self._ro = readonly
        self._owner = owner
        self._epoch = 0
        if owner != null:
            self._epoch = owner._epoch

    # Lève si la vue n'est plus valable (bloc libéré/réduit, arène réinitialisée).
    func _check():
        if self._owner != null and self._owner._epoch != self._epoch:
            raise("StaleViewError", "memory_view : vue invalidée par reset() de son arène")
        if not _m.alive(self._id):
            raise("MemoryError", "memory_view : le bloc sous-jacent a été libéré (vue invalide)")
        if self._off + self._len > _m.size(self._id):
            raise("MemoryError", "memory_view : le bloc sous-jacent a été réduit sous la plage de la vue")
        return null

    func _at(fn, off, n):
        self._check()
        _need_int(fn, off, "offset")
        _need_int(fn, n, "longueur")
        if off < 0 or n < 0 or off + n > self._len:
            raise("IndexError", f"memory_view.{fn}() : accès hors vue (offset {off}, longueur {n}, taille {self._len})")
        return self._off + off

    func _writable(fn):
        if self._ro:
            raise("MemoryError", "memory_view." + fn + "() : vue en lecture seule")
        return null

    # --- informations ---------------------------------------------------

    func size():
        return self._len

    func is_readonly():
        return self._ro

    # Vrai si la vue est encore utilisable (ne lève jamais).
    func valid():
        if self._owner != null and self._owner._epoch != self._epoch:
            return false
        if not _m.alive(self._id):
            return false
        return self._off + self._len <= _m.size(self._id)

    # Adresse absolue du premier octet (à passer à ffi ; ne pas conserver après free).
    func address():
        self._check()
        return _m.address(self._id) + self._off

    func _block_id():
        return self._id

    func _base_offset():
        return self._off

    # --- sous-vues ------------------------------------------------------

    # Sous-vue [offset, offset+length) ; length=null => jusqu'à la fin. Hérite readonly.
    func slice(offset=0, length=null, readonly=false):
        self._check()
        n := length
        if n == null:
            n = self._len - offset
        _need_int("slice", offset, "offset")
        _need_int("slice", n, "longueur")
        if offset < 0 or n < 0 or offset + n > self._len:
            raise("IndexError", f"memory_view.slice() : sous-vue hors vue (offset {offset}, longueur {n}, taille {self._len})")
        return MemoryView(self._id, self._off + offset, n, self._ro or readonly, self._owner, self._holder)

    func view(offset=0, length=null, readonly=false):
        return self.slice(offset, length, readonly)

    # Même plage, écriture interdite.
    func as_readonly():
        return self.slice(0, self._len, true)

    # (gauche, droite) autour de `index`.
    func split_at(index):
        return [self.slice(0, index), self.slice(index, self._len - index)]

    # Liste de sous-vues de `n` octets (la dernière peut être plus courte).
    func chunks(n):
        _need_int("chunks", n, "n")
        if n < 1:
            raise("ArgumentError", "memory_view.chunks() : n doit être >= 1")
        out := []
        pos := 0
        while pos < self._len:
            take := n
            if pos + take > self._len:
                take = self._len - pos
            append(out, self.slice(pos, take))
            pos = pos + take
        return out

    # --- lecture / écriture typées -------------------------------------

    func read(type_name, offset=0, big=false):
        return _m.read(self._id, self._at("read", offset, _m.type_size(type_name)), type_name, big)

    func write(type_name, value, offset=0, big=false):
        self._writable("write")
        return _m.write(self._id, self._at("write", offset, _m.type_size(type_name)), type_name, value, big)

    func read_array(type_name, count, offset=0, big=false):
        step := _m.type_size(type_name)
        start := self._at("read_array", offset, count * step)
        out := []
        i := 0
        while i < count:
            append(out, _m.read(self._id, start + i * step, type_name, big))
            i = i + 1
        return out

    func write_array(type_name, values, offset=0, big=false):
        self._writable("write_array")
        step := _m.type_size(type_name)
        start := self._at("write_array", offset, len(values) * step)
        i := 0
        for v in values:
            _m.write(self._id, start + i * step, type_name, v, big)
            i = i + 1
        return i * step

    func read_bytes(offset=0, length=null):
        n := length
        if n == null:
            n = self._len - offset
        return _m.read_bytes(self._id, self._at("read_bytes", offset, n), n)

    func write_bytes(data, offset=0):
        self._writable("write_bytes")
        n := _m.byte_len(data)
        return _m.write_bytes(self._id, self._at("write_bytes", offset, n), data)

    # Chaîne C : jusqu'au premier NUL, qui doit se trouver DANS la vue.
    func read_str(offset=0):
        start := self._at("read_str", offset, 0)
        return _m.read_cstr(self._id, start, self._len - offset)

    # Écrit text + NUL ; retourne le nombre d'octets écrits (NUL compris).
    func write_str(text, offset=0):
        self._writable("write_str")
        n := _m.byte_len(text) + 1
        return _m.write_bytes(self._id, self._at("write_str", offset, n), text + "\0")

    func fill(byte_value=0, offset=0, length=null):
        self._writable("fill")
        n := length
        if n == null:
            n = self._len - offset
        _m.fill(self._id, self._at("fill", offset, n), n, byte_value)
        return null

    # Efface avec une écriture que l'optimiseur ne peut pas supprimer (secrets, clés).
    func wipe():
        self._writable("wipe")
        _m.zero_secure(self._id, self._at("wipe", 0, self._len), self._len)
        return null

    # --- copie / comparaison / recherche -------------------------------

    # Copie `length` octets depuis `source` (vue) ; les plages peuvent se chevaucher
    # (sémantique memmove). length=null => min(restant source, restant destination).
    func copy_from(source, source_offset=0, offset=0, length=null):
        self._writable("copy_from")
        n := length
        if n == null:
            n = source._len - source_offset
            if self._len - offset < n:
                n = self._len - offset
        d := self._at("copy_from", offset, n)
        s := source._at("copy_from", source_offset, n)
        _m.copy(self._id, d, source._id, s, n)
        return n

    func copy_to(destination, offset=0, destination_offset=0, length=null):
        return destination.copy_from(self, offset, destination_offset, length)

    # -1, 0 ou 1 (ordre lexicographique des octets) ; sur min(taille, taille) octets
    # puis par taille.
    func compare(other):
        n := self._len
        if other._len < n:
            n = other._len
        c := _m.compare(self._id, self._at("compare", 0, n), other._id, other._at("compare", 0, n), n)
        if c != 0:
            return c
        if self._len < other._len:
            return -1
        if self._len > other._len:
            return 1
        return 0

    func equals(other):
        return self._len == other._len and self.compare(other) == 0

    # Indice (relatif à la vue, offset compris) de la première occurrence de `needle`
    # (str d'octets) à partir de `offset`, ou -1.
    func find(needle, offset=0):
        n := self._len - offset
        i := _m.find(self._id, self._at("find", offset, n), n, needle)
        if i == -1:
            return -1
        return offset + i

    func contains(needle):
        return self.find(needle) != -1

    # --- export ----------------------------------------------------------

    func to_bytes():
        return _m.read_bytes(self._id, self._at("to_bytes", 0, self._len), self._len)

    func to_list(type_name="u8", big=false):
        return self.read_array(type_name, self._len // _m.type_size(type_name), 0, big)

    # Vidage hexadécimal : "00000000  48 65 6c ...  |Hel...|" ; max_bytes borne la sortie.
    func hexdump(width=16, max_bytes=256):
        n := self._len
        if n > max_bytes:
            n = max_bytes
        bytes := self.read_array("u8", n)
        lines := []
        pos := 0
        while pos < n:
            hexpart := ""
            textpart := ""
            j := 0
            while j < width:
                if pos + j < n:
                    b := bytes[pos + j]
                    hexpart = hexpart + _hex2(b) + " "
                    if b >= 32 and b < 127:
                        textpart = textpart + str(_s.chr(b))
                    else:
                        textpart = textpart + "."
                else:
                    hexpart = hexpart + "   "
                j = j + 1
            append(lines, _hex2((pos // 65536) % 256) + _hex2((pos // 256) % 256) + _hex2(pos % 256) + "  " + hexpart + " |" + textpart + "|")
            pos = pos + width
        out := ""
        first := true
        for l in lines:
            if first:
                out = l
                first = false
            else:
                out = out + "\n" + l
        if self._len > max_bytes:
            out = out + f"\n... ({self._len - max_bytes} octets omis)"
        return out

# Vue sur n'importe quelle source possédant view() : Buffer, Region, MemoryView.
func view(source, offset=0, length=null, readonly=false):
    return source.view(offset, length, readonly)

# Vue directe sur un bloc géré (par identifiant) ; length=null => jusqu'à la fin. `holder` : l'objet propriétaire
# (Buffer, Region) que la vue garde vivant : une vue ne doit jamais survivre au bloc que le GC libérerait.
func from_block(block_id, offset=0, length=null, readonly=false, holder=null):
    size := _m.size(block_id)
    n := length
    if n == null:
        n = size - offset
    _need_int("from_block", offset, "offset")
    _need_int("from_block", n, "longueur")
    if offset < 0 or n < 0 or offset + n > size:
        raise("IndexError", f"memory_view.from_block() : plage hors bloc (offset {offset}, longueur {n}, taille {size})")
    return MemoryView(block_id, offset, n, readonly, null, holder)
