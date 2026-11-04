# multimedia.recording.screen_capture sur un VRAI affichage (make test-multimedia-display lance Xvfb ; sous
# Windows, le bureau par gdigrab) : image capturée, enregistrement vidéo relu par l'adaptateur ffmpeg.
use os
use multimedia.recording.screen_capture as sc
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia capture d'écran")
d := sc.diagnose()
attendu := {"linux": "x11grab", "windows": "gdigrab", "macos": "avfoundation"}
t.check(d["ok"] and d["backend"] == attendu[os.platform()], "affichage détecté : " + str(d))
g := sc.ScreenGrabber(64, 48, 5)
img := g.read()
g.close()
t.check(img != null and img.describe() == "64x48 rgb" and img.meta["index"] == 0, "image capturée")
p := os.tmp_dir() + "/alex_ecran_" + str(os.pid()) + ".mp4"
sc.record(p, 1.0, 5, 64, 48)
i := ff.probe(p)
t.check(i.first("video").format.width == 64 and i.duration > 0.5, "vidéo de l'écran relue : " + i.describe())
os.remove(p)
t.summary()
