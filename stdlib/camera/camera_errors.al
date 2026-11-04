# ALEX STANDARD LIBRARY — camera.camera_errors
#
# Erreurs de la caméra et diagnostic : nœuds /dev/video*, droits (groupe « video »), caméra déjà occupée,
# outils présents (ffmpeg pour la capture, v4l2-ctl pour les formats et réglages), et vérification d'une image
# capturée (noire : obturateur, cache ; uniforme : flux figé ; tronquée).
#   CameraError        erreur générale
#   CameraUnavailable  aucune caméra, droits insuffisants, outil absent
#   CameraBusy         caméra utilisée par un autre programme
#   ControlError       réglage inconnu ou valeur hors limites (camera_controls)
#
#   use camera.camera_errors as cerr
#   print(cerr.diagnose())                 # {"devices": [...], "readable": [...], "ffmpeg": true, "advice": ...}
#   print(cerr.check_frame(image))         # {"ok": true, "problem": null, "brightness": 112.4}
#   print(cerr.from_message("Device or resource busy"))     # "CameraBusy"
#
# Erreurs : celles ci-dessus.

from core use len, type
from collections use append
use string as _s
use os as _os
use hardware.permissions as _perm
use hardware._sys as _sys
use hardware._windows as _win

const CAMERA := "CameraError"
const UNAVAILABLE := "CameraUnavailable"
const BUSY := "CameraBusy"
const CONTROL := "ControlError"

func diagnose():
    devs := []
    readable := []
    if _win.is_windows():
        # DirectShow : pas de droits par nœud ; une caméra listée est utilisable (sauf refus dans Confidentialité,
        # visible à l'ouverture).
        devs = [_win.source(d) for d in _win.dshow_video()]
        readable = devs
    elif _os.isdir(_sys.p("/dev")):
        for n in _os.list_dir(_sys.p("/dev")):
            if _s.starts_with(n, "video"):
                p := "/dev/" + n
                append(devs, p)
                if _perm.can_read(p):
                    append(readable, p)
    ff := _sys.find_tool(["ffmpeg"]) != null
    v4 := _sys.find_tool(["v4l2-ctl"]) != null
    advice := null
    if not ff:
        advice = "ffmpeg absent : installer ffmpeg pour capturer"
    elif len(devs) == 0:
        advice = "aucune caméra " + ("DirectShow" if _win.is_windows() else "/dev/video*") + " (une mire de test reste possible : camera.test_pattern)"
    elif len(readable) == 0:
        advice = "caméras illisibles : ajouter l'utilisateur au groupe « video » (sudo usermod -aG video $USER)"
    return {"devices": devs, "readable": readable, "ffmpeg": ff, "v4l2_ctl": v4, "advice": advice,
            "ok": ff and len(readable) > 0}

func require_camera():
    d := diagnose()
    if not d["ok"]:
        raise(UNAVAILABLE, "caméra inaccessible : " + str(d["advice"]))
    return d

# Type d'erreur probable d'après un message (ffmpeg, v4l2).
func from_message(message):
    m := _s.lower(message)
    if _s.contains(m, "busy"):
        return BUSY
    if _s.contains(m, "permission denied") or _s.contains(m, "no such file") or _s.contains(m, "not found"):
        return UNAVAILABLE
    if _s.contains(m, "invalid argument") and _s.contains(m, "control"):
        return CONTROL
    return CAMERA

# Vérifie une image capturée (camera.video_frame.VideoFrame).
func check_frame(frame, dark_level=8.0):
    if not frame.valid():
        return {"ok": false, "problem": "image tronquée ou format incohérent", "brightness": null}
    b := frame.brightness()
    problem := null
    if b < dark_level:
        problem = "image noire (obturateur fermé, cache, éclairage)"
    else:
        h := frame.histogram(16)
        nonzero := len([x for x in h if x > 0])
        if nonzero <= 1:
            problem = "image uniforme (flux figé ou mire unie)"
    return {"ok": problem == null, "problem": problem, "brightness": b}

func is_camera_error(t):
    return t == CAMERA or t == UNAVAILABLE or t == BUSY or t == CONTROL
