# ALEX STANDARD LIBRARY — multimedia.image.image
#
# Image en mémoire, écrite en ALEX pur : largeur, hauteur, mode (« gray » 1 canal, « rgb » 3, « rgba » 4) et
# points 8 bits ligne par ligne (list[int]). Accès aux points, remplissage, recadrage, miroirs, rotation de
# 90°, collage avec mélange alpha, comparaison ; passerelles avec camera.video_frame.VideoFrame.
#
#   use multimedia.image.image as mi
#   img := mi.new(320, 200, "rgb", [16, 24, 48])
#   img.set(10, 10, [255, 0, 0])
#   print(img.get(10, 10), img.describe())        # [255, 0, 0] 320x200 rgb
#   vignette := img.crop(0, 0, 64, 64).flip_h()
#   cadre := mi.from_video_frame(camera.read())   # VideoFrame -> Image rgb
#
# Erreurs : FormatError (dimensions, mode, taille des données, coordonnées hors de l'image).

from core use len, type, to_int
from collections use append
use multimedia.core.errors as merr
use camera.video_frame as _vfm

const MODES := {"gray": 1, "rgb": 3, "rgba": 4}

func channels_of(mode):
    if not (mode in MODES):
        merr.fail(merr.FORMAT, "mode d'image inconnu : " + str(mode) + " (gray, rgb, rgba)")
    return MODES[mode]

class Image:
    func init(width, height, mode="rgba", pixels=null):
        if type(width) != "int" or type(height) != "int" or width <= 0 or height <= 0:
            merr.fail(merr.FORMAT, "dimensions d'image invalides : " + str(width) + "x" + str(height))
        self.width = width
        self.height = height
        self.mode = mode
        self.channels = channels_of(mode)
        self.meta = {}
        n := width * height * self.channels
        if pixels == null:
            self.pixels = [0 for i in 0..n]
        else:
            if len(pixels) != n:
                merr.fail(merr.FORMAT, "image " + str(width) + "x" + str(height) + " " + mode + " : " + str(n) + " octets attendus, " + str(len(pixels)) + " reçus")
            self.pixels = pixels

    func _at(x, y):
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            merr.fail(merr.FORMAT, "point (" + str(x) + ", " + str(y) + ") hors de l'image " + str(self.width) + "x" + str(self.height))
        return (y * self.width + x) * self.channels

    func get(x, y):
        i := self._at(x, y)
        return [self.pixels[i + c] for c in 0..self.channels]

    func set(x, y, value):
        i := self._at(x, y)
        for c in 0..self.channels:
            self.pixels[i + c] = value[c]

    func fill(value):
        for i in 0..self.width * self.height:
            for c in 0..self.channels:
                self.pixels[i * self.channels + c] = value[c]
        return self

    func fill_rect(x, y, w, h, value):
        x0 := x if x > 0 else 0
        y0 := y if y > 0 else 0
        x1 := x + w if x + w < self.width else self.width
        y1 := y + h if y + h < self.height else self.height
        for yy in y0..y1:
            for xx in x0..x1:
                i := (yy * self.width + xx) * self.channels
                for c in 0..self.channels:
                    self.pixels[i + c] = value[c]
        return self

    func copy():
        return Image(self.width, self.height, self.mode, [p for p in self.pixels])

    func row(y):
        a := y * self.width * self.channels
        return [self.pixels[k] for k in a..a + self.width * self.channels]

    func crop(x, y, w, h):
        if x < 0 or y < 0 or w <= 0 or h <= 0 or x + w > self.width or y + h > self.height:
            merr.fail(merr.FORMAT, "recadrage hors de l'image : " + str(x) + "," + str(y) + " " + str(w) + "x" + str(h))
        out := []
        for yy in y..y + h:
            a := (yy * self.width + x) * self.channels
            for k in a..a + w * self.channels:
                append(out, self.pixels[k])
        return Image(w, h, self.mode, out)

    func flip_h():
        out := []
        for y in 0..self.height:
            for x in 0..self.width:
                i := (y * self.width + (self.width - 1 - x)) * self.channels
                for c in 0..self.channels:
                    append(out, self.pixels[i + c])
        return Image(self.width, self.height, self.mode, out)

    func flip_v():
        out := []
        for y in 0..self.height:
            a := ((self.height - 1 - y) * self.width) * self.channels
            for k in a..a + self.width * self.channels:
                append(out, self.pixels[k])
        return Image(self.width, self.height, self.mode, out)

    # Rotation de 90° dans le sens horaire.
    func rotate90():
        out := []
        for y in 0..self.width:
            for x in 0..self.height:
                i := ((self.height - 1 - x) * self.width + y) * self.channels
                for c in 0..self.channels:
                    append(out, self.pixels[i + c])
        return Image(self.height, self.width, self.mode, out)

    # Colle `src` (même mode, ou rgba sur rgb/rgba avec mélange alpha) en (x, y), découpé aux bords.
    func paste(src, x, y):
        blend := src.mode == "rgba" and self.mode != "gray"
        if src.mode != self.mode and not blend:
            merr.fail(merr.FORMAT, "collage " + src.mode + " sur " + self.mode + " : convertir d'abord")
        for sy in 0..src.height:
            ty := y + sy
            if ty < 0 or ty >= self.height:
                continue
            for sx in 0..src.width:
                tx := x + sx
                if tx < 0 or tx >= self.width:
                    continue
                si := (sy * src.width + sx) * src.channels
                di := (ty * self.width + tx) * self.channels
                if blend:
                    a := src.pixels[si + 3]
                    for c in 0..3:
                        self.pixels[di + c] = (src.pixels[si + c] * a + self.pixels[di + c] * (255 - a) + 127) // 255
                    if self.channels == 4:
                        da := self.pixels[di + 3]
                        self.pixels[di + 3] = a + (da * (255 - a) + 127) // 255
                else:
                    for c in 0..self.channels:
                        self.pixels[di + c] = src.pixels[si + c]
        return self

    func equals(o):
        return self.width == o.width and self.height == o.height and self.mode == o.mode and self.pixels == o.pixels

    # Plus grand écart entre deux images de même géométrie (0 = identiques).
    func max_difference(o):
        if self.width != o.width or self.height != o.height or self.mode != o.mode:
            return 255
        m := 0
        for k in 0..len(self.pixels):
            d := self.pixels[k] - o.pixels[k]
            if d < 0:
                d = -d
            if d > m:
                m = d
        return m

    func byte_size():
        return len(self.pixels)

    func describe():
        return str(self.width) + "x" + str(self.height) + " " + self.mode

func new(width, height, mode="rgba", color=null):
    img := Image(width, height, mode)
    if color != null:
        img.fill(color)
    return img

# Dégradé de test (rouge selon x, vert selon y, bleu constant).
func gradient(width, height, mode="rgb"):
    img := Image(width, height, mode)
    for y in 0..height:
        for x in 0..width:
            r := (x * 255) // (width - 1 if width > 1 else 1)
            g := (y * 255) // (height - 1 if height > 1 else 1)
            if mode == "gray":
                img.set(x, y, [(r + g) // 2])
            elif mode == "rgb":
                img.set(x, y, [r, g, 128])
            else:
                img.set(x, y, [r, g, 128, 255])
    return img

func checkerboard(width, height, cell=8, a=null, b=null, mode="rgb"):
    ca := a if a != null else ([255] if mode == "gray" else ([255, 255, 255] if mode == "rgb" else [255, 255, 255, 255]))
    cb := b if b != null else ([0] if mode == "gray" else ([0, 0, 0] if mode == "rgb" else [0, 0, 0, 255]))
    img := Image(width, height, mode)
    for y in 0..height:
        for x in 0..width:
            if ((x // cell) + (y // cell)) % 2 == 0:
                img.set(x, y, ca)
            else:
                img.set(x, y, cb)
    return img

# camera.video_frame.VideoFrame (tout format de points) -> Image rgb.
func from_video_frame(frame):
    rgb := frame.to_rgb()
    return Image(rgb.width, rgb.height, "rgb", [b for b in rgb.data])

func to_video_frame(img, index=0, timestamp=0.0):
    px := img.pixels
    if img.mode != "rgb":
        px = []
        for i in 0..img.width * img.height:
            if img.mode == "gray":
                v := img.pixels[i]
                append(px, v)
                append(px, v)
                append(px, v)
            else:
                for c in 0..3:
                    append(px, img.pixels[i * 4 + c])
    return _vfm.VideoFrame(img.width, img.height, "rgb24", px, index, timestamp)
