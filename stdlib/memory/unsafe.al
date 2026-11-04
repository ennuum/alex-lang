# ALEX STANDARD LIBRARY — memory.unsafe
#
# La FRONTIÈRE du modèle hybride. Tout ce qui manipule de la mémoire brute
# (adresses, raw_alloc, déréférencement de Pointer, pages exécutables) exige d'être
# exécuté À L'INTÉRIEUR d'un bloc unsafe, comme `unsafe { }` en Rust :
#
#   use memory.unsafe as unsafe
#   use memory.alloc as alloc
#
#   func travail():
#       p := alloc.raw(64)          # exige un bloc unsafe
#       ...
#       free.address(p)
#   unsafe.block(travail)           # ALEX n'a pas de bloc anonyme : fonction nommée ou lambda () => expr
#
# Créer ou copier un Pointer reste sûr ; le DÉRÉFÉRENCER ne l'est pas : un Pointer sorti
# du bloc ne peut plus être lu ni écrit (UnsafeError).
#
# Fuites : block(body, leaks) décide du sort des allocations brutes faites dans le bloc
# et jamais libérées : "ignore" (défaut), "free" (libérées à la sortie), "error"
# (libérées, puis LeakError).
#
# Limite assumée : le compteur de profondeur est global. Un `await` DANS un bloc unsafe
# laisserait d'autres tâches s'exécuter « en mode unsafe » : ne pas suspendre dans un bloc.
#
# Erreurs : UnsafeError (opération hors bloc), LeakError (leaks="error"),
#           ArgumentError (option invalide).

from core use len, type
from collections use append, pop, keys, contains_key, remove

use _native_memory as _m

_state := {"depth": 0, "ops": 0, "blocks": 0, "scopes": []}

# Vrai si l'on est dans un bloc unsafe.
func active():
    return _state["depth"] > 0

func depth():
    return _state["depth"]

# Point de contrôle de toutes les opérations brutes de la stdlib.
func require(what):
    if _state["depth"] <= 0:
        raise("UnsafeError", what + " : opération unsafe hors d'un bloc — utiliser memory.unsafe.block(fonction)")
    _state["ops"] = _state["ops"] + 1
    return null

# Suivi des allocations brutes par portée (appelé par memory.alloc / memory.free).
func note_alloc(address, size):
    scopes := _state["scopes"]
    if len(scopes) > 0:
        scopes[len(scopes) - 1][address] = size
    return null

func note_free(address):
    scopes := _state["scopes"]
    i := len(scopes) - 1
    while i >= 0:
        if contains_key(scopes[i], address):
            remove(scopes[i], address)
            return null
        i = i - 1
    return null

# Exécute body() en mode unsafe ; retourne sa valeur. La profondeur est restaurée même si
# body lève une exception (qui est alors relevée telle quelle).
func block(body, leaks="ignore"):
    if leaks != "ignore" and leaks != "free" and leaks != "error":
        raise("ArgumentError", "memory.unsafe.block() : leaks doit valoir \"ignore\", \"free\" ou \"error\"")
    scope := {}
    append(_state["scopes"], scope)
    _state["depth"] = _state["depth"] + 1
    _state["blocks"] = _state["blocks"] + 1
    failure := null
    result := null
    try:
        result = body()
    catch e:
        failure = e
    _state["depth"] = _state["depth"] - 1
    pop(_state["scopes"])
    leaked := keys(scope)
    if len(leaked) > 0 and leaks != "ignore":
        for address in leaked:
            try:
                _m.raw_free(address)
            catch e2:
                null
    if failure != null:
        raise(failure.type, failure.message)
    if len(leaked) > 0 and leaks == "error":
        raise("LeakError", f"memory.unsafe.block() : {len(leaked)} allocation(s) brute(s) non libérée(s) dans le bloc (libérées automatiquement)")
    return result

# Compteurs d'audit : {"blocks": blocs exécutés, "ops": opérations brutes contrôlées, "depth": ...}.
func stats():
    return {"blocks": _state["blocks"], "ops": _state["ops"], "depth": _state["depth"]}

# Active/désactive la validation des accès par adresse (niveau unsafe).
#   true  (défaut) : toute adresse doit appartenir à une région suivie (alloc, vm_map, track).
#   false : accès nu comme en C ; une adresse invalide peut faire planter le processus.
# Retourne l'état précédent. Exige un bloc unsafe.
func set_checks(enabled):
    require("memory.unsafe.set_checks")
    return _m.set_checks(enabled)

func checks():
    return _m.checks()
