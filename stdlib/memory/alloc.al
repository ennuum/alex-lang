# ALEX STANDARD LIBRARY — memory.alloc
#
# Allocation de mémoire. Deux niveaux, un seul registre natif :
#
#   SÛR      alloc.block(size)        bloc géré par IDENTIFIANT (jamais recyclé) : bornes
#                                     vérifiées, canaris de débordement, mémoire initialisée.
#                                     Un Buffer (memory.buffer) en est le propriétaire.
#   UNSAFE   alloc.raw(size)          ADRESSE brute (comme malloc) ; exige un bloc unsafe.
#            alloc.calloc / aligned / realloc / usable_size
#
# Mémoire fraîche : zéro pour block() et calloc() ; motif 0xCD (détecte les lectures de
# mémoire non initialisée) pour raw(). Tailles >= 1 ; alignement = puissance de 2 (<= 65536).
# Les débordements d'entiers (count * elem_size) sont refusés avant l'appel.
#
# Quota : alloc.set_limit(octets) borne le total vivant (blocs + adresses brutes) ;
# dépasser lève MemoryError. alloc.stats() donne les compteurs du registre.
#
# Erreurs : MemoryError (quota, mémoire insuffisante, double free), ArgumentError
#           (taille/alignement invalides), UnsafeError (niveau brut hors bloc unsafe).

from core use len, type

use _native_memory as _m
use memory.unsafe as _u

func _need_int(fn, v, label):
    if type(v) != "int":
        raise("TypeError", "memory.alloc." + fn + "() : " + label + " doit être un int (obtenu '" + type(v) + "')")
    return v

# --- niveau sûr ---------------------------------------------------------

# Identifiant d'un nouveau bloc géré. Pas de libération automatique : préférer
# memory.buffer.Buffer, qui en possède le cycle de vie.
func block(size, align=16, zero=true, tag=null):
    _need_int("block", size, "size")
    return _m.alloc(size, align, zero, tag)

# --- niveau unsafe ------------------------------------------------------

# Adresse (int) d'un bloc brut de `size` octets, NON initialisé (0xCD), à libérer avec
# memory.free.address().
func raw(size, align=16, zero=false, tag=null):
    _u.require("memory.alloc.raw")
    _need_int("raw", size, "size")
    addr := _m.raw_alloc(size, align, zero, tag)
    _u.note_alloc(addr, size)
    return addr

# Comme raw() mais zéro-initialisé.
func zeroed(size, align=16, tag=null):
    return raw(size, align, true, tag)

# count * elem_size octets, zéro-initialisés ; refuse le débordement du produit.
func calloc(count, elem_size, align=16, tag=null):
    _u.require("memory.alloc.calloc")
    _need_int("calloc", count, "count")
    _need_int("calloc", elem_size, "elem_size")
    if count < 1 or elem_size < 1:
        raise("ArgumentError", "memory.alloc.calloc() : count et elem_size doivent être >= 1")
    if count > 9223372036854775807 // elem_size:
        raise("MemoryError", "memory.alloc.calloc() : count * elem_size déborde")
    return raw(count * elem_size, align, true, tag)

# Bloc brut dont l'adresse est un multiple de `align`.
func aligned(size, align, zero=false, tag=null):
    return raw(size, align, zero, tag)

# Redimensionne un bloc brut. L'ANCIENNE adresse devient invalide ; retourne la nouvelle
# (contenu conservé, octets ajoutés à zéro).
func realloc(address, new_size):
    _u.require("memory.alloc.realloc")
    _need_int("realloc", address, "address")
    _need_int("realloc", new_size, "new_size")
    fresh := _m.raw_realloc(address, new_size)
    _u.note_free(address)
    _u.note_alloc(fresh, new_size)
    return fresh

# Taille utilisable du bloc brut commençant à `address` (région suivie), ou null.
func usable_size(address):
    _u.require("memory.alloc.usable_size")
    r := _m.region_of(address)
    if r == null or r["offset"] != 0:
        return null
    return r["size"]

# --- configuration et diagnostics ---------------------------------------

# Borne le total d'octets vivants (null = illimité). Retourne l'ancienne limite.
func set_limit(max_bytes):
    return _m.set_limit(max_bytes)

func limit():
    return _m.limit()

# Compteurs : managed_blocks/bytes, raw_..., mapped_..., external_..., live_bytes,
# peak_bytes, total_allocs, total_frees.
func stats():
    return _m.stats()

# Vérifie les canaris de TOUS les blocs ; retourne le nombre de blocs vérifiés.
# Lève MemoryError au premier débordement détecté.
func check_all():
    return _m.check_all()

# Active/désactive les canaris pour les FUTURES allocations (retourne l'état précédent).
func set_guards(enabled):
    return _m.set_guards(enabled)
