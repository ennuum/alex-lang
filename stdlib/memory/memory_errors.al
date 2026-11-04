# ALEX STANDARD LIBRARY — memory.memory_errors
#
# Erreurs de la gestion mémoire (natives et ALEX), avec leur sens :
#   MemoryError          quota dépassé, mémoire insuffisante, utilisation après libération, double free
#   UnsafeError          opération brute hors d'un bloc unsafe
#   LeakError            fuite constatée à la sortie d'un bloc unsafe (leaks="error")
#   StaleViewError       vue invalidée (reset d'arène, emplacement de pool rendu)
#   BorrowError          emprunts RefCell incompatibles
#   StaleHandleError     handle générationnel périmé
#   OwnershipError       usage d'un propriétaire déjà relâché / transfert invalide
#   PoolExhaustedError   pool d'emplacements plein (pool non extensible)
#   AllocatorError       allocation rendue au mauvais allocateur, allocation inconnue
#   AlignmentError       alignement qui n'est pas une puissance de 2, adresse mal alignée
#
#   use memory.memory_errors as me
#   me.need_align("Arena.alloc", align)
#   if me.is_memory_error(e.type): ...

from core use type

const MEMORY := "MemoryError"
const UNSAFE := "UnsafeError"
const LEAK := "LeakError"
const STALE_VIEW := "StaleViewError"
const BORROW := "BorrowError"
const STALE_HANDLE := "StaleHandleError"
const OWNERSHIP := "OwnershipError"
const POOL_EXHAUSTED := "PoolExhaustedError"
const ALLOCATOR := "AllocatorError"
const ALIGNMENT := "AlignmentError"

func kinds():
    return [MEMORY, UNSAFE, LEAK, STALE_VIEW, BORROW, STALE_HANDLE, OWNERSHIP, POOL_EXHAUSTED, ALLOCATOR, ALIGNMENT]

func is_memory_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func is_power_of_two(n):
    return type(n) == "int" and n > 0 and (n & (n - 1)) == 0

func need_size(fn, size):
    if type(size) != "int":
        raise("TypeError", fn + " : taille int attendue (obtenu '" + type(size) + "')")
    if size < 1:
        raise("ArgumentError", fn + " : taille >= 1 attendue (obtenu " + str(size) + ")")

func need_align(fn, align):
    if not is_power_of_two(align):
        raise(ALIGNMENT, fn + " : alignement " + str(align) + " invalide (puissance de 2 attendue)")

func out_of_memory(fn, requested, available):
    raise(MEMORY, fn + " : mémoire insuffisante (demandé " + str(requested) + " octets, disponible " + str(available) + ")")

func foreign(fn):
    raise(ALLOCATOR, fn + " : allocation n'appartenant pas à cet allocateur")

func double_free(fn):
    raise(MEMORY, fn + " : double libération")
