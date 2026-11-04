# ALEX STANDARD LIBRARY — gc.gc_roots
#
# Racines explicites : garder des objets VIVANTS indépendamment des variables du programme (comme les
# handles « épinglés » des runtimes managés). Un objet épinglé ne peut pas être collecté tant que son
# épingle existe — utile quand seule une adresse native (ffi, memory.Buffer.address()) ou un identifiant
# circule, et que l'objet ALEX propriétaire doit survivre.
#
#   use gc.gc_roots as roots
#   h := roots.pin(tampon)               # handle (int)
#   roots.get(h)                         # l'objet
#   roots.unpin(h)                       # redevient collectable
#   rs := roots.RootSet("rendu")
#   rs.add("texture", tex)
#   rs.clear()
#   roots.keep_alive([a, b], travail)    # a et b épinglés pendant travail()
#
# Erreurs : GcRootError (handle inconnu ou déjà relâché).

from core use len, type
from collections use append
use gc.gc_errors as _e

_pins := {}
_next := [0]

func pin(obj):
    _next[0] += 1
    _pins[_next[0]] = obj
    return _next[0]

func unpin(handle):
    if not (handle in _pins):
        _e.root("gc_roots.unpin", "handle " + str(handle) + " inconnu ou déjà relâché")
    del _pins[handle]

func get(handle):
    if not (handle in _pins):
        _e.root("gc_roots.get", "handle " + str(handle) + " inconnu ou déjà relâché")
    return _pins[handle]

func is_pinned(handle):
    return handle in _pins

func pinned_count():
    return len(_pins)

# Épingle objs pendant body() puis les relâche (même sur erreur).
func keep_alive(objs, body):
    hs := [pin(o) for o in objs]
    try:
        return body()
    finally:
        for h in hs:
            if h in _pins:
                del _pins[h]

# Ensemble nommé de racines (clé -> objet), relâchées ensemble.
class RootSet:
    func init(name="racines"):
        self.name = name
        self._h = {}

    func add(key, obj):
        if key in self._h:
            unpin(self._h[key])
        self._h[key] = pin(obj)
        return obj

    func get(key):
        if not (key in self._h):
            _e.root("RootSet.get", self.name + " : clé '" + str(key) + "' absente")
        return get(self._h[key])

    func remove(key):
        if not (key in self._h):
            return false
        unpin(self._h[key])
        del self._h[key]
        return true

    func contains(key):
        return key in self._h

    func keys():
        return [k for k in self._h]

    func size():
        return len(self._h)

    func clear():
        for k in self._h:
            unpin(self._h[k])
        self._h = {}
