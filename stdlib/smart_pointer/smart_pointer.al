# ALEX STANDARD LIBRARY — smart_pointer
#
# Pointeurs intelligents : propriété explicite et fin de vie déterministe des ressources.
#
#   UniquePtr  (smart_pointer.unique_ptr)       propriétaire unique, move(), suppresseur à la destruction
#   SharedPtr  (smart_pointer.shared_ptr)       propriété partagée à comptage, dernier relâchement = destruction
#   WeakPtr    (smart_pointer.weak_ptr)         observateur non propriétaire (casse les cycles)
#   ControlBlock / Counter (smart_pointer.reference_count)
#   Owned / using / DisposeBag / scope (smart_pointer.ownership)
#
#   use smart_pointer as smp
#   u := smp.make_unique(ressource, (r) => r.close())
#   s := smp.make_shared(cache)
#   w := smp.make_weak(s)
#   print(smp.kind(u), smp.kind(s), smp.kind(w))     # unique shared weak
#   print(smp.deref(s) == cache)                     # true
#
# La mémoire elle-même reste gérée par la VM (ramasse-miettes) : ces types gouvernent QUAND une ressource
# est libérée (suppresseur), et vérifient à l'exécution qu'on n'utilise pas une valeur déplacée ou détruite.
# Erreurs : voir smart_pointer.smart_pointer_errors.

from core use type
use smart_pointer.unique_ptr as _up
use smart_pointer.shared_ptr as _sp
use smart_pointer.weak_ptr as _wp
use smart_pointer.ownership as _own
from smart_pointer.unique_ptr use UniquePtr
from smart_pointer.shared_ptr use SharedPtr
from smart_pointer.weak_ptr use WeakPtr

func make_unique(value, deleter=null):
    return _up.make_unique(value, deleter)

func make_shared(value, deleter=null):
    return _sp.make_shared(value, deleter)

func make_weak(shared):
    return _wp.WeakPtr(shared)

func owned(value, name="valeur"):
    return _own.Owned(value, name)

# "unique", "shared", "weak", "owned" ou null.
func kind(p):
    if isinstance(p, UniquePtr):
        return "unique"
    if isinstance(p, SharedPtr):
        return "shared"
    if isinstance(p, WeakPtr):
        return "weak"
    if isinstance(p, _own.Owned):
        return "owned"
    return null

func is_smart_pointer(p):
    return kind(p) != null

# Valeur pointée (WeakPtr : null si expirée).
func deref(p):
    k := kind(p)
    if k == "weak":
        return p.peek()
    if k == null:
        raise("TypeError", "smart_pointer.deref : pointeur intelligent attendu (obtenu '" + type(p) + "')")
    return p.get()

# Libère la propriété (drop), quel que soit le type.
func drop(p):
    k := kind(p)
    if k == "unique" or k == "shared":
        p.drop()
    elif k == "weak":
        p.reset()
    elif k == "owned":
        if p.is_owned():
            p.take()
