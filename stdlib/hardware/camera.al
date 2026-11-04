# ALEX STANDARD LIBRARY — hardware.camera
#
# Caméras (Linux : Video4Linux, /sys/class/video4linux et /dev/videoN ; Windows : DirectShow, « video=... ») et capture d'une image ou d'une courte
# vidéo par l'outil du système (ffmpeg, ou fswebcam pour une image).
#
# Une webcam USB expose souvent deux nœuds (image et métadonnées) : cameras() ne garde que ceux qui
# capturent l'image (index 0 de chaque périphérique), all_nodes() les liste tous.
#
# Exemple
#   use hardware.camera as camera
#   c := camera.primary()
#   if c != null:
#       camera.capture("photo.jpg", c, 1280, 720)
#
# Erreurs : HardwareError (aucune caméra, aucun outil, échec de capture).

from core use len, type
from collections use append
use string as _s
use os as _os
use process as _proc
use hardware._sys as _sys
use hardware._windows as _win

class Camera:
    func init(node):
        self.node = node              # « video0 »
        self.path = "/dev/" + node
        self.name = null              # nom donné par le pilote (« Integrated Camera: Integrated C »)
        self.index = 0                # rang du nœud sur son périphérique (0 : flux d'image)
        self.driver = null            # « uvcvideo »...
        self.bus = null               # « usb », « pci », « platform »...

func _node_number(name):
    n := _sys.dec(_s.slice(name, 5))
    if n == null:
        return 0
    return n

# Tous les nœuds Video4Linux (list de Camera), y compris ceux de métadonnées. Windows : caméras DirectShow (vues
# par ffmpeg), de chemin « video=... ».
func all_nodes():
    out := []
    if _win.is_windows():
        for d in _win.dshow_video():
            c := Camera("dshow")
            c.path = _win.source(d)
            c.name = d["name"]
            c.driver = "dshow"
            append(out, c)
        return out
    names := [n for n in _sys.list("/sys/class/video4linux") if _s.starts_with(n, "video")]
    # Ordre numérique (video2 avant video10).
    i := 0
    while i < len(names):
        j := i + 1
        while j < len(names):
            if _node_number(names[j]) < _node_number(names[i]):
                tmp := names[i]
                names[i] = names[j]
                names[j] = tmp
            j += 1
        i += 1
    for name in names:
        base := "/sys/class/video4linux/" + name
        c := Camera(name)
        c.name = _sys.read(base + "/name")
        idx := _sys.dec(_sys.read(base + "/index"))
        if idx != null:
            c.index = idx
        c.driver = _sys.link_name(base + "/device/driver")
        sub := _sys.link_name(base + "/device/subsystem")
        if sub != null:
            c.bus = sub
        append(out, c)
    return out

# Caméras (nœuds qui capturent l'image).
func cameras():
    return [c for c in all_nodes() if c.index == 0]

func available():
    return len(cameras()) > 0

func primary():
    cs := cameras()
    if len(cs) == 0:
        return null
    return cs[0]

_TOOLS := ["ffmpeg", "fswebcam"]

# Format d'entrée de ffmpeg : dshow pour « video=... » (Windows), v4l2 sinon.
func _input_format(dev):
    return "dshow" if _s.starts_with(dev, "video=") else "v4l2"

func tool():
    return _sys.find_tool(_TOOLS)

func _device_path(camera):
    if camera == null:
        c := primary()
        if c == null:
            _sys.fail("camera", "aucune caméra trouvée")
        return c.path
    if type(camera) == "str":
        return camera
    return camera.path

# Enregistre une image (JPEG ou PNG selon l'extension de path) ; renvoie path.
func capture(path, camera=null, width=null, height=null, timeout=20):
    dev := _device_path(camera)
    t := tool()
    if t == null:
        _sys.fail("camera.capture", "aucun outil de capture (ffmpeg ou fswebcam)")
    args := []
    if t == "ffmpeg":
        args = ["-loglevel", "error", "-y", "-f", _input_format(dev)]
        if width != null and height != null:
            append(args, "-video_size")
            append(args, str(width) + "x" + str(height))
        for x in ["-i", dev, "-frames:v", "1", path]:
            append(args, x)
    else:
        args = ["-q", "--no-banner", "-d", dev]
        if width != null and height != null:
            append(args, "-r")
            append(args, str(width) + "x" + str(height))
        append(args, path)
    r := _proc.run(t, args, null, timeout)
    if r.timed_out or r.code != 0 or not _os.exists(path):
        _sys.fail("camera.capture", t + " a échoué : " + _s.trim(r.stderr))
    return path

# Enregistre seconds secondes de vidéo (ffmpeg) ; renvoie path.
func record(path, seconds, camera=null, width=null, height=null):
    dev := _device_path(camera)
    if _proc.which("ffmpeg") == null:
        _sys.fail("camera.record", "ffmpeg est nécessaire")
    args := ["-loglevel", "error", "-y", "-f", _input_format(dev)]
    if width != null and height != null:
        append(args, "-video_size")
        append(args, str(width) + "x" + str(height))
    for x in ["-i", dev, "-t", str(seconds), path]:
        append(args, x)
    r := _proc.run("ffmpeg", args, null, seconds + 30)
    if r.code != 0 or not _os.exists(path):
        _sys.fail("camera.record", "ffmpeg a échoué : " + _s.trim(r.stderr))
    return path
