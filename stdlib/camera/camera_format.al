# ALEX STANDARD LIBRARY — camera.camera_format
#
# Formats d'image d'une caméra : dimensions, format des points (« rgb24 », « bgr24 », « rgba », « gray »,
# « yuyv422 », « nv12 », « mjpeg »), images par seconde ; taille d'une image brute, noms Video4Linux (fourcc)
# et ffmpeg, résolutions courantes, et lecture de la liste « v4l2-ctl --list-formats-ext ».
#
#   use camera.camera_format as cf
#   f := cf.CameraFormat(640, 480, "yuyv422", 30)
#   print(f.frame_bytes(), f.fourcc(), f.describe())     # 614400 YUYV « 640x480 yuyv422 30 i/s »
#   formats := cf.parse_v4l2_formats(texte)

from core use len, to_int, to_float
from collections use append
use string as _s

const PIXEL_FORMATS := ["rgb24", "bgr24", "rgba", "gray", "yuyv422", "nv12", "mjpeg"]

# Octets par point (formats bruts ; nv12 : 1,5 ; mjpeg : variable -> 0).
func bytes_per_pixel_x2(pixel_format):
    if pixel_format == "rgb24" or pixel_format == "bgr24":
        return 6
    if pixel_format == "rgba":
        return 8
    if pixel_format == "gray":
        return 2
    if pixel_format == "yuyv422":
        return 4
    if pixel_format == "nv12":
        return 3
    if pixel_format == "mjpeg":
        return 0
    raise("ArgumentError", "caméra : format de points inconnu '" + str(pixel_format) + "'")

class CameraFormat:
    func init(width=640, height=480, pixel_format="rgb24", fps=30):
        if width <= 0 or height <= 0:
            raise("ArgumentError", "CameraFormat : dimensions invalides")
        bytes_per_pixel_x2(pixel_format)
        self.width = width
        self.height = height
        self.pixel_format = pixel_format
        self.fps = fps

    func pixels():
        return self.width * self.height

    # Taille d'une image brute (0 pour mjpeg : variable).
    func frame_bytes():
        return self.pixels() * bytes_per_pixel_x2(self.pixel_format) // 2

    func size_text():
        return str(self.width) + "x" + str(self.height)

    func fourcc():
        p := self.pixel_format
        if p == "yuyv422":
            return "YUYV"
        if p == "mjpeg":
            return "MJPG"
        if p == "nv12":
            return "NV12"
        if p == "gray":
            return "GREY"
        if p == "rgb24":
            return "RGB3"
        if p == "bgr24":
            return "BGR3"
        return "AB24"

    # Nom du format pour ffmpeg (-pix_fmt / -input_format).
    func ffmpeg_name():
        if self.pixel_format == "gray":
            return "gray"
        return self.pixel_format

    func aspect():
        return 1.0 * self.width / self.height

    func with_pixel_format(p):
        return CameraFormat(self.width, self.height, p, self.fps)

    func describe():
        return self.size_text() + " " + self.pixel_format + " " + str(self.fps) + " i/s"

func from_fourcc(code):
    c := _s.upper(_s.trim(code))
    if c == "YUYV":
        return "yuyv422"
    if c == "MJPG":
        return "mjpeg"
    if c == "NV12":
        return "nv12"
    if c == "GREY":
        return "gray"
    if c == "RGB3":
        return "rgb24"
    if c == "BGR3":
        return "bgr24"
    return null

VGA := CameraFormat(640, 480, "rgb24", 30)
QVGA := CameraFormat(320, 240, "rgb24", 30)
HD := CameraFormat(1280, 720, "rgb24", 30)
FULL_HD := CameraFormat(1920, 1080, "rgb24", 30)

# Analyse la sortie de « v4l2-ctl --list-formats-ext » : list de CameraFormat (un par taille et cadence).
func parse_v4l2_formats(text):
    out := []
    fmt := null
    w := 0
    h := 0
    for raw in _s.split(text, "\n"):
        line := _s.trim(raw)
        if _s.starts_with(line, "[") and _s.contains(line, "'"):
            a := _s.find(line, "'")
            rest := _s.slice(line, a + 1)
            fmt = from_fourcc(_s.slice(rest, 0, _s.find(rest, "'")))
        elif _s.starts_with(line, "Size:") and _s.contains(line, "x"):
            words := [x for x in _s.split(line, " ") if x != ""]
            dims := _s.split(words[len(words) - 1], "x")
            w = to_int(dims[0])
            h = to_int(dims[1])
        elif _s.starts_with(line, "Interval:") and _s.contains(line, "(") and fmt != null and w > 0:
            a := _s.find(line, "(")
            b := _s.find(line, " fps")
            fps := to_float(_s.slice(line, a + 1, b))
            fr := to_int(fps + 0.5)
            append(out, CameraFormat(w, h, fmt, fr))
    return out

# Le format le plus proche de (width, height) parmi formats (préférant pixel_format s'il est donné).
func closest(formats, width, height, pixel_format=null):
    best := null
    best_score := -1
    for f in formats:
        d := f.width - width
        if d < 0:
            d = -d
        e := f.height - height
        if e < 0:
            e = -e
        score := d + e
        if pixel_format != null and f.pixel_format != pixel_format:
            score += 100000
        if best == null or score < best_score or (score == best_score and f.fps > best.fps):
            best = f
            best_score = score
    return best
