# ALEX STANDARD LIBRARY — input.input_errors
#
# Erreurs du paquet input et diagnostic des périphériques d'entrée :
#   InputError         erreur générale (événement invalide, état incohérent)
#   DeviceNotFound     aucun périphérique du genre demandé (clavier, souris, manette, écran tactile...)
#   InputUnavailable   périphériques présents mais illisibles (droits sur /dev/input), ou pas de /dev/input
#   UnsupportedDevice  périphérique d'un genre non pris en charge par l'opération
#
#   use input.input_errors as ie
#   print(ie.diagnose())          # {"ok", "devices", "readable", "advice"}
#   ie.require_access()           # InputUnavailable expliquée
#
# Erreurs : celles ci-dessus.

from core use len, type
from collections use append
use string as _s
use _native_fd as _f
use hardware._sys as _sys

const INPUT := "InputError"
const NOT_FOUND := "DeviceNotFound"
const UNAVAILABLE := "InputUnavailable"
const UNSUPPORTED := "UnsupportedDevice"

func fail(message):
    raise(INPUT, message)

func not_found(kind):
    raise(NOT_FOUND, "aucun périphérique d'entrée de genre « " + kind + " »")

func diagnose():
    out := {"ok": false, "devices": [], "readable": [], "advice": null}
    devs := _sys.input_devices()
    for d in devs:
        for ev in d["events"]:
            append(out["devices"], ev)
            fd := -1
            try:
                fd = _f.open_device(_sys.p(ev), false)
            catch e:
                fd = -1
            if type(fd) == "int" and fd >= 0:
                append(out["readable"], ev)
                _f.close(fd)
    if len(devs) == 0:
        out["advice"] = "aucun périphérique d'entrée (/proc/bus/input/devices absent ou vide : conteneur, serveur, ou système non Linux)"
    elif len(out["readable"]) == 0:
        out["advice"] = "périphériques illisibles : ajouter l'utilisateur au groupe « input » (sudo usermod -aG input $USER)"
    else:
        out["ok"] = true
    return out

func require_access():
    d := diagnose()
    if not d["ok"]:
        raise(UNAVAILABLE, "entrées physiques inaccessibles : " + str(d["advice"]))
    return d

func is_input_error(t):
    return t == INPUT or t == NOT_FOUND or t == UNAVAILABLE or t == UNSUPPORTED
