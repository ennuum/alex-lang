# Enregistreur d'écran (ffmpeg : x11grab, gdigrab, avfoundation). Sans affichage, explique pourquoi.
#   alex run examples/multimedia/screen_recorder/main.al -- sortie.mp4 [secondes]
from core use len, to_float
use os
use multimedia.recording.screen_capture as sc

a := os.args()
dst := a[0] if len(a) > 0 else os.tmp_dir() + "/alex_ecran.mp4"
secs := to_float(a[1]) if len(a) > 1 else 3.0
d := sc.diagnose()
if not d["ok"]:
    print("capture d'écran indisponible : " + str(d["advice"]))
else:
    print(str(sc.record(dst, secs, 10)))
