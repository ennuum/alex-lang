# ALEX STANDARD LIBRARY — atomic
#
# Valeurs ATOMIQUES partagées entre fils d'exécution réels (thread, concurrency.thread) : AtomicInteger,
# AtomicBoolean, AtomicReference. Chaque opération est indivisible, même exécutée sur plusieurs cœurs à la fois.
# Les objets passent d'un fil à l'autre par leur identifiant entier (.id) : attach(id) les retrouve.
#
#   use atomic
#   n := atomic.integer(0)
#   fini := atomic.boolean(false)
#   etat := atomic.reference({"phase": 1})
#   ids := [n.id, fini.id, etat.id]          # à passer aux fils
#   x := atomic.attach(ids[0])               # AtomicInteger (le type est retrouvé)
#
# Entre TÂCHES async d'un même fil (coopératives), concurrency.atomic suffit ; ces types-ci fonctionnent aussi
# dans ce cas. Barrières mémoire : chaque opération est séquentiellement cohérente (seq_cst) ; fence() est
# fournie pour la lisibilité et ne fait rien de plus.
#
# Mémoire : un objet atomique vit jusqu'à destroy() (ou la fin du processus) ; live_objects() compte les objets
# de synchronisation natifs (atomiques, verrous, sémaphores...).

use _native_sync as _s
use atomic.atomic_integer as _ai
use atomic.atomic_boolean as _ab
use atomic.atomic_reference as _ar

func integer(value=0):
    return _ai.AtomicInteger(value)

func boolean(value=false):
    return _ab.AtomicBoolean(value)

func reference(value=null):
    return _ar.AtomicReference(value)

# Objet atomique désigné par son identifiant : AtomicReference, ou AtomicInteger (as_bool=true : AtomicBoolean).
func attach(id, as_bool=false):
    k := _s.kind(id)
    if k == "ref":
        return _ar.attach(id)
    if k == "atomic":
        if as_bool:
            return _ab.attach(id)
        return _ai.attach(id)
    if k == null:
        raise("ArgumentError", "atomic.attach : objet " + str(id) + " inconnu ou détruit")
    raise("TypeError", "atomic.attach : l'objet " + str(id) + " est un(e) " + k)

# Barrière mémoire complète (toutes les opérations de ce paquet le sont déjà).
func fence():
    return null

func live_objects():
    return _s.live()
