# ALEX STANDARD LIBRARY — multimedia.backends.video.system
#
# Dorsal vidéo du système : caméras (paquet camera, ffmpeg / Video4Linux), décodage et encodage vidéo et capture
# d'écran (adaptateur ffmpeg). Point d'entrée unique pour savoir ce qui est disponible et ouvrir une source.
#
#   use multimedia.backends.video.system as vsys
#   print(vsys.describe())                    # {"cameras": [...], "ffmpeg": true, "screen": false, ...}
#   src := vsys.open_source("pattern", 320, 240, 15)      # VideoCapture

use multimedia.video.device as _vd
use multimedia.video.capture as _vcap
use multimedia.backends.codecs.ffmpeg as _ff
use multimedia.recording.screen_capture as _sc

func describe():
    return {"cameras": _vd.cameras(), "camera_ok": _vd.available(), "ffmpeg": _ff.available(),
            "screen": _sc.available(), "screen_details": _sc.diagnose()}

func open_source(kind="camera", width=320, height=240, fps=15, path=null, limit=null):
    return _vcap.VideoCapture(kind, width, height, fps, path, limit)
