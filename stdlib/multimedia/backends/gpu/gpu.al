# ALEX STANDARD LIBRARY — multimedia.backends.gpu.gpu
#
# Accélération : état des cartes graphiques (paquet gpu : sysfs, nvidia-smi) et des accélérations vidéo
# exposées par ffmpeg (hwaccels : vaapi, cuda, qsv, videotoolbox, d3d11va...). Rien n'est activé
# implicitement : decode_args(nom) donne les options ffmpeg d'une accélération PRÉSENTE, sinon UnsupportedError.
#
#   use multimedia.backends.gpu.gpu as mg
#   print(mg.describe())                        # {"gpus": [...], "hwaccels": ["vaapi", ...]}
#   args := mg.decode_args("vaapi")             # ["-hwaccel", "vaapi"]

from core use len
from collections use append
use string as _s
use process as _proc
use gpu as _gpu
use multimedia.core.errors as merr
use multimedia.backends.codecs.ffmpeg as _ff

func hwaccels():
    if not _ff.available():
        return []
    r := _proc.run(_ff._state["ffmpeg"], ["-hide_banner", "-hwaccels"])
    out := []
    started := false
    for line in _s.split(r.stdout, "\n"):
        t := _s.trim(line)
        if _s.starts_with(t, "Hardware acceleration methods"):
            started = true
            continue
        if started and len(t) > 0:
            append(out, t)
    return out

func gpus():
    try:
        return [g.describe() for g in _gpu.list()]
    catch e:
        return []

func describe():
    return {"gpus": gpus(), "hwaccels": hwaccels()}

func decode_args(name):
    if not (name in hwaccels()):
        merr.unsupported("accélération « " + str(name) + " »", "absente de ce ffmpeg ou de cette machine")
    return ["-hwaccel", name]
