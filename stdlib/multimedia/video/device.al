# ALEX STANDARD LIBRARY — multimedia.video.device
#
# Caméras de la machine (au-dessus du paquet camera) : liste, caméra par défaut, diagnostic. Aucune caméra n'est
# simulée : sans périphérique, la liste est vide et diagnose() dit pourquoi.
#
#   use multimedia.video.device as vd
#   for c in vd.cameras():
#       print(c["path"], c["name"], c["readable"])
#   print(vd.diagnose()["advice"])

from core use len
from collections use append
use camera as _cam
use camera.camera_errors as _cerr

func diagnose():
    try:
        return _cerr.diagnose()
    catch e:
        return {"devices": [], "readable": [], "ffmpeg": false, "advice": e.message, "ok": false}

func cameras():
    d := diagnose()
    out := []
    names := {}
    try:
        for c in _cam.cameras():
            try:
                names[c.path] = c.name
            catch e:
                names = names
    catch e:
        names = {}
    for p in d["devices"]:
        append(out, {"path": p, "name": names[p] if p in names else p, "readable": p in d["readable"]})
    return out

func default():
    for c in cameras():
        if c["readable"]:
            return c
    return null

func available():
    return default() != null and diagnose()["ffmpeg"]
