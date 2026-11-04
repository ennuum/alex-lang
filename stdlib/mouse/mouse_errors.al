# ALEX STANDARD LIBRARY — mouse.mouse_errors
#
# Erreurs de la souris et diagnostic de l'accès à la souris PHYSIQUE (lecture brute evdev) :
#   MouseError         erreur générale
#   MouseUnavailable   aucune souris lisible (pas de /dev/input, droits insuffisants, conteneur)
#   CursorError        forme de curseur inconnue
#
#   use mouse.mouse_errors as merr
#   d := merr.diagnose_raw_access()
#   print(d["ok"], d["mice"], d["advice"])
#   merr.require_raw_access()                 # MouseUnavailable expliquée
#   merr.require_cursor("pointer")            # CursorError si la forme n'existe pas
#
# Erreurs : MouseUnavailable, CursorError, MouseError.

from core use len, type
from collections use append
use string as _s
use os as _os
use io as _io
use _native_fd as _f
use mouse.cursor as _cur

const MOUSE := "MouseError"
const UNAVAILABLE := "MouseUnavailable"
const CURSOR := "CursorError"

func _is_mouse(dev):
    try:
        rel := _s.trim(_io.read_file("/sys/class/input/" + dev + "/device/capabilities/rel"))
        return rel != "0" and rel != ""
    catch e:
        return false

func diagnose_raw_access():
    out := {"ok": false, "devices": [], "readable": [], "mice": [], "advice": null}
    if not _os.isdir("/dev/input"):
        out["advice"] = "pas de /dev/input : système sans périphériques d'entrée exposés (conteneur ?), utiliser les événements de fenêtre"
        return out
    for n in _os.list_dir("/dev/input"):
        if _s.starts_with(n, "event"):
            p := "/dev/input/" + n
            append(out["devices"], p)
            if _is_mouse(n):
                append(out["mice"], p)
            fd := -1
            try:
                fd = _f.open_device(p, false)
            catch e:
                fd = -1
            if type(fd) == "int" and fd >= 0:
                append(out["readable"], p)
                _f.close(fd)
    if len(out["devices"]) == 0:
        out["advice"] = "aucun périphérique /dev/input/event*"
    elif len(out["mice"]) == 0:
        out["advice"] = "aucune souris (axes relatifs) parmi les périphériques d'entrée"
    elif len([m for m in out["mice"] if m in out["readable"]]) == 0:
        out["advice"] = "souris présente mais illisible : ajouter l'utilisateur au groupe « input » (sudo usermod -aG input $USER)"
    else:
        out["ok"] = true
    return out

func require_raw_access():
    d := diagnose_raw_access()
    if not d["ok"]:
        raise(UNAVAILABLE, "souris physique inaccessible : " + str(d["advice"]))
    return d

func require_cursor(name):
    if not _cur.is_valid(name):
        raise(CURSOR, "forme de curseur inconnue : '" + str(name) + "' (" + _s.join(", ", _cur.names()) + ")")
    return name

func is_mouse_error(t):
    return t == MOUSE or t == UNAVAILABLE or t == CURSOR
