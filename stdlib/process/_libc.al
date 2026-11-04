# ALEX STANDARD LIBRARY — process._libc (interne)
#
# Liaisons ffi vers la libc, créées à la première utilisation et mises en cache, pour les appels système
# sans primitive native dédiée (priorités, limites, groupes de processus). available() est faux hors
# POSIX x86-64/arm64 ou si ffi est indisponible : les modules appelants se replient alors sur /proc ou
# lèvent une erreur explicite.

from core use type
use ffi as _ffi
use os as _os

_lib := [null, false]
_fns := {}

func available():
    if _lib[1]:
        return _lib[0] != null
    _lib[1] = true
    if _os.platform() == "windows":
        return false
    try:
        if _ffi.supported():
            _lib[0] = _ffi.Library(null)
    catch e:
        _lib[0] = null
    return _lib[0] != null

# Fonction C liée (ou null si indisponible).
func fn(name, args, ret):
    if name in _fns:
        return _fns[name]
    if not available():
        return null
    f := null
    try:
        if _lib[0].has(name):
            f = _lib[0].function(name, args, ret)
    catch e:
        f = null
    _fns[name] = f
    return f

# Appelle name ; IoError explicite si la fonction est indisponible.
func call(name, args, ret, values, what):
    f := fn(name, args, ret)
    if f == null:
        raise("IoError", what + " : appel système '" + name + "' indisponible sur cette plateforme")
    return f.call(values)

func buffer(size):
    return _ffi.Buffer(size)
