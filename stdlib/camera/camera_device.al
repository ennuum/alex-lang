# ALEX STANDARD LIBRARY — camera.camera_device
#
# Les caméras de la machine (Linux : Video4Linux, via hardware.camera) : nom, nœud /dev/videoN, pilote, bus,
# formats proposés (v4l2-ctl --list-formats-ext s'il est installé), choix d'un format proche de la taille
# voulue, ouverture d'une capture.
#
#   use camera.camera_device as cd
#   for c in cd.cameras():
#       print(c.describe())                 # « /dev/video0 Integrated Camera (uvcvideo, usb) »
#       for f in c.formats():
#           print(f.describe())             # « 1280x720 mjpeg 30 i/s »
#   cap := cd.default().open(1280, 720)     # camera_capture.CameraCapture

from core use len
from collections use append
use process
use hardware.camera as _hc
use camera.camera_format as cf
use camera.camera_capture as cc

class CameraDevice:
    func init(info):
        self.info = info                 # hardware.camera.Camera
        self.path = info.path
        self.name = info.name
        self.driver = info.driver
        self.bus = info.bus
        self._formats = null

    # Formats proposés (list de CameraFormat) ; [] si v4l2-ctl n'est pas installé.
    func formats():
        if self._formats != null:
            return self._formats
        out := []
        if process.which("v4l2-ctl") != null:
            r := process.Command("v4l2-ctl").args(["-d", self.path, "--list-formats-ext"]).run(null, 10)
            if r.code == 0:
                out = cf.parse_v4l2_formats(r.stdout)
        self._formats = out
        return out

    # Format proposé le plus proche de width x height (ou le format demandé tel quel si la liste est vide).
    func best_format(width, height, pixel_format=null):
        fs := self.formats()
        if len(fs) == 0:
            return cf.CameraFormat(width, height, pixel_format if pixel_format != null else "yuyv422", 30)
        return cf.closest(fs, width, height, pixel_format)

    func open(width=640, height=480, output="rgb24"):
        return cc.CameraCapture(self.path, self.best_format(width, height), output)

    func snapshot(width=640, height=480):
        return cc.snapshot(self.path, self.best_format(width, height))

    func describe():
        t := self.path
        if self.name != null:
            t = t + " " + self.name
        extra := []
        if self.driver != null:
            append(extra, self.driver)
        if self.bus != null:
            append(extra, self.bus)
        if len(extra) > 0:
            t = t + " (" + extra[0]
            if len(extra) > 1:
                t = t + ", " + extra[1]
            t = t + ")"
        return t

func cameras():
    return [CameraDevice(c) for c in _hc.cameras()]

func default():
    cs := cameras()
    if len(cs) == 0:
        return null
    return cs[0]

func available():
    return len(cameras()) > 0
