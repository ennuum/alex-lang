# ALEX STANDARD LIBRARY — keyboard.keyboard_errors
#
# Erreurs du clavier et diagnostic de l'accès au clavier PHYSIQUE (lecture brute evdev) :
#   KeyboardError        erreur générale
#   KeyboardUnavailable  aucun clavier lisible (pas de /dev/input, droits insuffisants, conteneur)
#   ShortcutError        raccourci ou séquence mal formés (« ctrl++ », touche inconnue)
#   MappingError         conflit ou boucle dans une table de correspondance (key_mapping)
#
#   use keyboard.keyboard_errors as kerr
#   d := kerr.diagnose_raw_access()
#   print(d["ok"], d["readable"], d["advice"])    # ex. false [] « ajouter l'utilisateur au groupe input »
#   kerr.require_raw_access()                      # KeyboardUnavailable avec l'explication
#   print(kerr.check_shortcut("ctrl+shift+s"))     # null si valide, sinon le message d'erreur
#
# Erreurs : KeyboardUnavailable, ShortcutError, MappingError, KeyboardError.

from core use len, type
from collections use append
use string as _s
use os as _os
use io as _io
use _native_fd as _f
use keyboard.key_event as _ke

const KEYBOARD := "KeyboardError"
const UNAVAILABLE := "KeyboardUnavailable"
const SHORTCUT := "ShortcutError"
const MAPPING := "MappingError"

func _is_keyboard(dev):
    caps := "/sys/class/input/" + dev + "/device/capabilities/key"
    try:
        txt := _s.trim(_io.read_file(caps))
        return len(txt) > 10
    catch e:
        return false

# {"ok", "devices", "readable", "keyboards", "advice"}
func diagnose_raw_access():
    out := {"ok": false, "devices": [], "readable": [], "keyboards": [], "advice": null}
    if not _os.isdir("/dev/input"):
        out["advice"] = "pas de /dev/input : système sans périphériques d'entrée exposés (conteneur ?), utiliser les événements de fenêtre"
        return out
    for n in _os.list_dir("/dev/input"):
        if _s.starts_with(n, "event"):
            p := "/dev/input/" + n
            append(out["devices"], p)
            if _is_keyboard(n):
                append(out["keyboards"], p)
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
    elif len(out["readable"]) == 0:
        out["advice"] = "périphériques présents mais illisibles : ajouter l'utilisateur au groupe « input » (sudo usermod -aG input $USER) puis se reconnecter"
    else:
        out["ok"] = true
    return out

func require_raw_access():
    d := diagnose_raw_access()
    if not d["ok"]:
        raise(UNAVAILABLE, "clavier physique inaccessible : " + str(d["advice"]))
    return d

# null si le raccourci est valide, sinon le message d'erreur.
func check_shortcut(text):
    try:
        _ke.parse_shortcut(text)
        return null
    catch e:
        return e.message

func require_shortcut(text):
    m := check_shortcut(text)
    if m != null:
        raise(SHORTCUT, m)
    return _ke.parse_shortcut(text)

func is_keyboard_error(t):
    return t == KEYBOARD or t == UNAVAILABLE or t == SHORTCUT or t == MAPPING
