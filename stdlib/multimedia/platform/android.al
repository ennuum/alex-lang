# ALEX STANDARD LIBRARY — multimedia.platform.android
#
# Android : le code multimédia en ALEX pur (WAV, FLAC, Ogg, images, pipelines, sous-titres...) est portable ;
# aucun dorsal matériel (AAudio, Camera2, MediaCodec) n'est encore écrit : lecture, capture et caméra lèvent
# UnsupportedError sur cette plateforme.
#
#   use multimedia.platform.android as an
#   print(an.report())

use multimedia.core.errors as merr

const SUPPORT := {"audio_playback": "non pris en charge (dorsal AAudio à écrire)", "audio_capture": "non pris en charge",
    "camera": "non pris en charge (Camera2 à écrire)", "screen_capture": "non pris en charge (MediaProjection)",
    "codecs_system": "non pris en charge (MediaCodec à écrire)", "pure_alex": "non validé (portable, non exécuté)"}

func report():
    return {"platform": "android", "supported": false, "support": SUPPORT}

func require_backend(name):
    merr.unsupported("dorsal Android « " + str(name) + " »", "non écrit : seul le code ALEX pur est disponible")
