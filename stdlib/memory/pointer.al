# ALEX STANDARD LIBRARY — memory.pointer
#
# Pointeurs TYPÉS sur mémoire brute (niveau UNSAFE du modèle hybride).
#
#   use memory.unsafe  as unsafe
#   use memory.pointer as pointer
#
#   func demo():
#       p := pointer.malloc(4, "i32")           # 4 entiers 32 bits, à libérer
#       p.write(10)
#       p.offset(1).write(20)                   # arithmétique en ÉLÉMENTS
#       print(p.read_array(2))                  # [10, 20]
#       pointer.free(p)
#   unsafe.block(demo)
#
# Règle du modèle : CRÉER, copier, comparer, décaler un Pointer est sûr (ce n'est qu'un
# nombre) ; le DÉRÉFÉRENCER (read/write/copy/fill/cstr...) exige un bloc unsafe — sinon
# UnsafeError. Les méthodes de pure information (address, is_null, is_valid, region,
# is_aligned, offset, cast, diff, comparaisons) sont sûres.
#
# Validation : par défaut chaque déréférencement vérifie que [adresse, adresse+taille) est
# DANS une région suivie (blocs alloc, raw, vm_map, track) et lisible/inscriptible ;
# sinon MemoryError — pas de segfault. memory.unsafe.set_checks(false) supprime ce
# contrôle (accès nu, comme C).
#
# Pointeurs étrangers (venus de C via ffi) : track(adresse, taille) les déclare ;
# probe() / is_valid() interrogent aussi l'OS.
#
# Erreurs : UnsafeError, MemoryError, ArgumentError, TypeError, ValueError.

from core use len, type
from collections use append
use _native_memory as _m
use memory.unsafe as _u
use memory.alloc as _alloc
use memory.free as _free

class Pointer:
    # address : int (0 = nul) ; type_name : type des éléments pointés (défaut "u8").
    func init(address=0, type_name="u8"):
        if type(address) != "int":
            raise("TypeError", "memory.pointer.Pointer() : adresse int attendue (obtenu '" + type(address) + "')")
        self._addr = address
        self._type = type_name
        self._size = _m.type_size(type_name)   # valide aussi le nom de type

    # --- sûr : informations et arithmétique ----------------------------

    func address():
        return self._addr

    func type_name():
        return self._type

    func elem_size():
        return self._size

    func is_null():
        return self._addr == 0

    # Pointeur décalé de n ÉLÉMENTS (n peut être négatif). Ne déréférence rien.
    func offset(n):
        return Pointer(self._addr + n * self._size, self._type)

    func add_bytes(n):
        return Pointer(self._addr + n, self._type)

    # Même adresse, autre type d'élément (réinterprétation).
    func cast(type_name):
        return Pointer(self._addr, type_name)

    # Distance en ÉLÉMENTS jusqu'à `other` (self - other) ; les adresses doivent être alignées
    # à la taille d'élément l'une par rapport à l'autre.
    func diff(other):
        d := self._addr - other._addr
        if d % self._size != 0:
            raise("ArgumentError", "memory.pointer.diff() : différence non multiple de la taille d'élément")
        return d // self._size

    func eq(other):
        return self._addr == other._addr

    func lt(other):
        return self._addr < other._addr

    func is_aligned(alignment=null):
        a := alignment
        if a == null:
            a = self._size
        return self._addr % a == 0

    # Les `count` éléments à partir d'ici sont-ils dans une région suivie accessible ?
    func is_valid(count=1, write=false):
        return _m.accessible(self._addr, count * self._size, write)

    # L'OS considère-t-il ces pages comme mappées ? (indépendant du registre ; sans risque)
    func probe(count=1):
        return _m.probe(self._addr, count * self._size)

    # Description de la région contenant le pointeur (dict) ou null : id, kind, address,
    # size, readonly, tag, offset.
    func region():
        return _m.region_of(self._addr)

    # --- unsafe : déréférencement ---------------------------------------

    # Élément d'indice `index` (comme p[index] en C).
    func read(index=0):
        _u.require("Pointer.read")
        return _m.peek(self._addr + index * self._size, self._type)

    func write(value, index=0):
        _u.require("Pointer.write")
        return _m.poke(self._addr + index * self._size, self._type, value)

    func read_big(index=0):
        _u.require("Pointer.read_big")
        return _m.peek(self._addr + index * self._size, self._type, true)

    func write_big(value, index=0):
        _u.require("Pointer.write_big")
        return _m.poke(self._addr + index * self._size, self._type, value, true)

    func read_array(count, index=0):
        _u.require("Pointer.read_array")
        out := []
        i := 0
        while i < count:
            append(out, _m.peek(self._addr + (index + i) * self._size, self._type))
            i = i + 1
        return out

    func write_array(values, index=0):
        _u.require("Pointer.write_array")
        i := 0
        for v in values:
            _m.poke(self._addr + (index + i) * self._size, self._type, v)
            i = i + 1
        return i

    func read_bytes(length, byte_offset=0):
        _u.require("Pointer.read_bytes")
        return _m.peek_bytes(self._addr + byte_offset, length)

    func write_bytes(data, byte_offset=0):
        _u.require("Pointer.write_bytes")
        return _m.poke_bytes(self._addr + byte_offset, data)

    # Chaîne C à cette adresse (jusqu'au NUL) ; max_length borne la lecture.
    func cstr(max_length=null):
        _u.require("Pointer.cstr")
        return _m.peek_cstr(self._addr, max_length)

    # Copie `count` éléments vers `destination` (memmove : chevauchement permis).
    func copy_to(destination, count):
        _u.require("Pointer.copy_to")
        return _m.raw_copy(destination._addr, self._addr, count * self._size)

    func copy_from(source, count):
        return source.copy_to(self, count)

    func fill(byte_value, count):
        _u.require("Pointer.fill")
        _m.raw_fill(self._addr, count * self._size, byte_value)
        return null

    # -1, 0 ou 1 sur `count` éléments.
    func compare(other, count):
        _u.require("Pointer.compare")
        return _m.raw_compare(self._addr, other._addr, count * self._size)

    # Libère ce bloc (doit être le DÉBUT d'un bloc obtenu par malloc/alloc.raw).
    func free():
        _free.address(self._addr)
        return null

func nullptr(type_name="u8"):
    return Pointer(0, type_name)

func from_address(address, type_name="u8"):
    return Pointer(address, type_name)

# Pointeur sur le premier octet (ou l'octet `byte_offset`) d'un Buffer/Region. Un Pointer NE garde PAS le
# Buffer vivant : si le Buffer devient inaccessible, le GC libère son bloc et le déréférencement lève
# MemoryError (contrôles actifs) ou plante (contrôles coupés). Conserver une référence au Buffer.
func from_buffer(source, byte_offset=0, type_name="u8"):
    return Pointer(source.address() + byte_offset, type_name)

# `count` éléments de `type_name`, bloc brut zéro-initialisé. Exige un bloc unsafe.
func malloc(count, type_name="u8", zero=true, tag=null):
    _u.require("memory.pointer.malloc")
    step := _m.type_size(type_name)
    if type(count) != "int" or count < 1:
        raise("ArgumentError", "memory.pointer.malloc() : count doit être un int >= 1")
    if count > 9223372036854775807 // step:
        raise("MemoryError", "memory.pointer.malloc() : count * taille d'élément déborde")
    return Pointer(_alloc.raw(count * step, 16, zero, tag), type_name)

func free(pointer):
    return pointer.free()

# Déclare une région étrangère (retournée par du C) pour autoriser son déréférencement
# validé. Retourne l'identifiant à passer à untrack().
func track(address, size, tag=null):
    _u.require("memory.pointer.track")
    return _m.track(address, size, tag)

func untrack(region_id):
    _u.require("memory.pointer.untrack")
    return _m.untrack(region_id)
