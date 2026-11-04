# ALEX STANDARD LIBRARY — multimedia.recording.screen_capture
#
# Capture d'écran par l'adaptateur système ffmpeg : x11grab (Linux, X11), gdigrab (Windows), avfoundation
# (macOS). Lecture image par image (Image rgb) ou enregistrement direct vers un fichier vidéo. L'écran n'est
# jamais simulé : sans affichage (serveur, conteneur), DeviceError dit pourquoi.
#
#   use multimedia.recording.screen_capture as sc
#   if sc.available():
#       g := sc.ScreenGrabber(640, 360, 10)          # zone / taille de sortie, cadence
#       img := g.read()
#       sc.record("ecran.mp4", 5.0, 10)              # 5 s à 10 i/s
#   print(sc.diagnose())                             # {"backend": "x11grab", "display": ":0", "ok": ...}

from core use len
use os as _os
use multimedia.core.errors as merr
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.image.image as mi
use multimedia.platform.platform as plat
use process as _proc

func diagnose():
    p := plat.current()
    d := {"platform": p, "backend": null, "display": null, "ok": false, "advice": null}
    if not ff.available():
        d["advice"] = "ffmpeg absent : la capture d'écran passe par ffmpeg"
        return d
    if p == "linux":
        d["backend"] = "x11grab"
        disp := _os.get_env("DISPLAY", null)
        d["display"] = disp
        if disp == null or disp == "":
            wl := _os.get_env("WAYLAND_DISPLAY", null)
            d["advice"] = "aucun affichage X11 (DISPLAY vide)" + (" : sous Wayland, utiliser le portail de capture (non pris en charge ici)" if wl != null else " : machine sans écran")
            return d
    elif p == "windows":
        d["backend"] = "gdigrab"
        d["display"] = "desktop"
    elif p == "macos":
        d["backend"] = "avfoundation"
        d["display"] = "1"
    else:
        d["advice"] = "capture d'écran non prise en charge sur " + p
        return d
    d["ok"] = true
    return d

func available():
    return diagnose()["ok"]

func _input_args(d, fps, x, y, w, h):
    if d["backend"] == "x11grab":
        size := [] if w == null else ["-video_size", str(w) + "x" + str(h)]
        return ["-f", "x11grab", "-framerate", str(fps)] + size + ["-i", d["display"] + "+" + str(x) + "," + str(y)]
    if d["backend"] == "gdigrab":
        reg := [] if w == null else ["-offset_x", str(x), "-offset_y", str(y), "-video_size", str(w) + "x" + str(h)]
        return ["-f", "gdigrab", "-framerate", str(fps)] + reg + ["-i", "desktop"]
    return ["-f", "avfoundation", "-framerate", str(fps), "-i", d["display"]]

class ScreenGrabber:
    func init(out_width=640, out_height=360, fps=10, x=0, y=0, width=null, height=null):
        d := diagnose()
        if not d["ok"]:
            merr.fail(merr.DEVICE, "capture d'écran impossible : " + str(d["advice"]))
        self.width = out_width
        self.height = out_height
        self.fps = fps
        self.index = 0
        args := ff.BASE + _input_args(d, fps, x, y, width, height) + ["-vf", "scale=" + str(out_width) + ":" + str(out_height),
                "-f", "rawvideo", "-pix_fmt", "rgb24", "pipe:1"]
        self.reader = ff._Reader(args)

    func read():
        n := self.width * self.height * 3
        b := self.reader.take(n)
        if len(b) < n:
            self.reader.finish()
            return null
        img := mi.Image(self.width, self.height, "rgb", b)
        img.meta = {"pts": 1.0 * self.index / self.fps, "index": self.index}
        self.index += 1
        return img

    func close():
        self.reader.finish()

# Enregistre l'écran `seconds` secondes dans un fichier (codec selon l'extension).
func record(path, seconds, fps=10, width=null, height=null):
    d := diagnose()
    if not d["ok"]:
        merr.fail(merr.DEVICE, "capture d'écran impossible : " + str(d["advice"]))
    out := ["-vf", "scale=" + str(width) + ":" + str(height)] if width != null else []
    r := _run(ff.BASE + ["-y"] + _input_args(d, fps, 0, 0, null, null) + ["-t", str(seconds)] + out + ["-pix_fmt", "yuv420p", path])
    return r

func _run(args):
    r := _proc.run(ff._state["ffmpeg"], args, null, 600.0)
    if r.code != 0:
        merr.fail(merr.DEVICE, "ffmpeg : capture d'écran échouée : " + r.stderr)
    return {"path": args[len(args) - 1], "code": r.code}
