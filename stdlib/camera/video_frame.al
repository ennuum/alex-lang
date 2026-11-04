# ALEX STANDARD LIBRARY — camera.video_frame
#
# Une image vidéo : dimensions, format des points, octets (list[int]), numéro et instant de capture ;
# conversions (YUYV / NV12 / BGR / gris -> RGB, RGBA pour ui.canvas), accès aux points, recadrage,
# redimensionnement (plus proche voisin), miroir, niveaux de gris, luminosité moyenne, histogramme,
# différence entre deux images (détection de mouvement), écriture / lecture PPM et PGM.
#
#   use camera.video_frame as vf
#   rgb := image.to_rgb()                       # VideoFrame en rgb24
#   print(rgb.pixel(10, 10))                    # [r, g, b]
#   petit := rgb.resize(160, 120)
#   petit.save_ppm("photo.ppm")
#   if vf.motion(avant, apres) > 0.02:          # proportion de points qui ont changé
#       print("mouvement")
#   canvas_put_pixels(c, 0, 0, w, h, rgb.to_rgba_bytes())

from core use len, to_int
from collections use append
use string as _s
use io as _io
use _native_net as _b
use camera.camera_format as cf

func _clamp(v):
    if v < 0:
        return 0
    if v > 255:
        return 255
    return v

# YUV (BT.601, plage limitée) -> [r, g, b].
func yuv_to_rgb(y, u, v):
    c := y - 16
    d := u - 128
    e := v - 128
    r := (298 * c + 409 * e + 128) >> 8
    g := (298 * c - 100 * d - 208 * e + 128) >> 8
    b := (298 * c + 516 * d + 128) >> 8
    return [_clamp(r), _clamp(g), _clamp(b)]

func rgb_to_yuv(r, g, b):
    y := ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16
    u := ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128
    v := ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128
    return [_clamp(y), _clamp(u), _clamp(v)]

class VideoFrame:
    func init(width, height, pixel_format, data, index=0, timestamp=0.0):
        self.width = width
        self.height = height
        self.pixel_format = pixel_format
        self.data = data
        self.index = index
        self.timestamp = timestamp

    func format():
        return cf.CameraFormat(self.width, self.height, self.pixel_format, 0)

    func valid():
        if self.pixel_format == "mjpeg":
            return len(self.data) > 2 and self.data[0] == 0xFF and self.data[1] == 0xD8
        return len(self.data) == self.format().frame_bytes()

    # Image en rgb24 (copie, ou la même si elle l'est déjà).
    func to_rgb():
        p := self.pixel_format
        w := self.width
        h := self.height
        d := self.data
        if p == "rgb24":
            return self
        out := []
        if p == "bgr24" or p == "rgba":
            step := 3 if p == "bgr24" else 4
            i := 0
            while i + 2 < len(d):
                if p == "bgr24":
                    append(out, d[i + 2])
                    append(out, d[i + 1])
                    append(out, d[i])
                else:
                    append(out, d[i])
                    append(out, d[i + 1])
                    append(out, d[i + 2])
                i += step
        elif p == "gray":
            for v in d:
                append(out, v)
                append(out, v)
                append(out, v)
        elif p == "yuyv422":
            i := 0
            while i + 3 < len(d):
                u := d[i + 1]
                v := d[i + 3]
                for c in yuv_to_rgb(d[i], u, v):
                    append(out, c)
                for c in yuv_to_rgb(d[i + 2], u, v):
                    append(out, c)
                i += 4
        elif p == "nv12":
            uv := w * h
            y := 0
            while y < h:
                x := 0
                while x < w:
                    k := uv + (y // 2) * w + (x // 2) * 2
                    for c in yuv_to_rgb(d[y * w + x], d[k], d[k + 1]):
                        append(out, c)
                    x += 1
                y += 1
        else:
            raise("ArgumentError", "VideoFrame.to_rgb : format " + p + " (mjpeg : décoder avec ffmpeg)")
        return VideoFrame(w, h, "rgb24", out, self.index, self.timestamp)

    # [r, g, b] du point (x, y).
    func pixel(x, y):
        f := self.to_rgb()
        k := 3 * (y * self.width + x)
        return [f.data[k], f.data[k + 1], f.data[k + 2]]

    func to_gray():
        f := self.to_rgb()
        out := []
        i := 0
        while i + 2 < len(f.data):
            append(out, (77 * f.data[i] + 150 * f.data[i + 1] + 29 * f.data[i + 2]) >> 8)
            i += 3
        return VideoFrame(self.width, self.height, "gray", out, self.index, self.timestamp)

    # Octets RGBA (str binaire) pour ui.canvas_put_pixels.
    func to_rgba_bytes():
        f := self.to_rgb()
        out := []
        i := 0
        while i + 2 < len(f.data):
            append(out, f.data[i])
            append(out, f.data[i + 1])
            append(out, f.data[i + 2])
            append(out, 255)
            i += 3
        return _b.from_bytes(out)

    func crop(x, y, w, h):
        f := self.to_rgb()
        out := []
        row := y
        while row < y + h:
            k := 3 * (row * self.width + x)
            for i in 0..3 * w:
                append(out, f.data[k + i])
            row += 1
        return VideoFrame(w, h, "rgb24", out, self.index, self.timestamp)

    func resize(w, h):
        f := self.to_rgb()
        out := []
        row := 0
        while row < h:
            sy := row * self.height // h
            col := 0
            while col < w:
                sx := col * self.width // w
                k := 3 * (sy * self.width + sx)
                append(out, f.data[k])
                append(out, f.data[k + 1])
                append(out, f.data[k + 2])
                col += 1
            row += 1
        return VideoFrame(w, h, "rgb24", out, self.index, self.timestamp)

    func mirror():
        f := self.to_rgb()
        out := []
        row := 0
        while row < self.height:
            col := self.width - 1
            while col >= 0:
                k := 3 * (row * self.width + col)
                append(out, f.data[k])
                append(out, f.data[k + 1])
                append(out, f.data[k + 2])
                col -= 1
            row += 1
        return VideoFrame(self.width, self.height, "rgb24", out, self.index, self.timestamp)

    # Luminosité moyenne (0..255).
    func brightness():
        g := self.to_gray().data
        if len(g) == 0:
            return 0.0
        s := 0
        for v in g:
            s += v
        return 1.0 * s / len(g)

    # Histogramme des niveaux de gris en bins classes.
    func histogram(bins=16):
        out := [0 for i in 0..bins]
        for v in self.to_gray().data:
            out[v * bins // 256] = out[v * bins // 256] + 1
        return out

    func save_ppm(path):
        f := self.to_rgb()
        header := _b.to_bytes("P6\n" + str(self.width) + " " + str(self.height) + "\n255\n")
        out := [x for x in header]
        for v in f.data:
            append(out, v)
        _io.write_bytes(path, out)

    func save_pgm(path):
        g := self.to_gray()
        out := [x for x in _b.to_bytes("P5\n" + str(self.width) + " " + str(self.height) + "\n255\n")]
        for v in g.data:
            append(out, v)
        _io.write_bytes(path, out)

    func describe():
        return "image " + str(self.index) + " : " + str(self.width) + "x" + str(self.height) + " " + self.pixel_format + ", " + str(len(self.data)) + " octets"

# Image binaire PPM (P6) ou PGM (P5).
func load_pnm(path):
    d := _io.read_bytes(path)
    fields := []
    i := 0
    cur := ""
    while len(fields) < 4 and i < len(d):
        c := d[i]
        if c == 35:
            while i < len(d) and d[i] != 10:
                i += 1
        elif c == 32 or c == 10 or c == 13 or c == 9:
            if cur != "":
                append(fields, cur)
                cur = ""
        else:
            cur = cur + _b.from_bytes([c])
        i += 1
    if len(fields) < 4 or (fields[0] != "P6" and fields[0] != "P5"):
        raise("ArgumentError", "load_pnm : PPM / PGM binaire attendu")
    w := to_int(fields[1])
    h := to_int(fields[2])
    fmt := "rgb24" if fields[0] == "P6" else "gray"
    return VideoFrame(w, h, fmt, [d[k] for k in i..len(d)])

# Proportion (0..1) de points dont le gris a changé de plus de threshold entre deux images de même taille.
func motion(a, b, threshold=25):
    ga := a.to_gray().data
    gb := b.to_gray().data
    if len(ga) != len(gb) or len(ga) == 0:
        return 1.0
    n := 0
    i := 0
    while i < len(ga):
        d := ga[i] - gb[i]
        if d < 0:
            d = -d
        if d > threshold:
            n += 1
        i += 1
    return 1.0 * n / len(ga)

# Image unie (tests, fonds).
func solid(width, height, r, g, b):
    out := []
    k := 0
    while k < width * height:
        append(out, r)
        append(out, g)
        append(out, b)
        k += 1
    return VideoFrame(width, height, "rgb24", out)
