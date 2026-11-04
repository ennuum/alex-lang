# ALEX STANDARD LIBRARY — graphics.surface
#
# Surface de rendu : tampon de couleurs (points RGBA empaquetés 0xAARRGGBB) et tampon de profondeur
# (flottants, 1.0 = le plus loin) de largeur x hauteur ; effacement, lecture / écriture de points, mélange
# alpha, copie, comparaison, export (octets RGBA pour ui.canvas_put_pixels, PPM) et conversion en
# camera.video_frame.VideoFrame.
#
#   use graphics.surface as gs
#   s := gs.Surface(320, 240)
#   s.clear(gs.rgba(0.1, 0.1, 0.2, 1.0))
#   s.set_pixel(10, 10, gs.pack(255, 0, 0, 255))
#   s.save_ppm("image.ppm")

from core use len, to_int
from collections use append
use io as _io
use _native_net as _b

func pack(r, g, b, a=255):
    return ((a & 255) << 24) | ((r & 255) << 16) | ((g & 255) << 8) | (b & 255)

func _c(v):
    if v <= 0.0:
        return 0
    if v >= 1.0:
        return 255
    return to_int(v * 255.0 + 0.5)

# Couleur depuis des composantes 0.0..1.0.
func rgba(r, g, b, a=1.0):
    return pack(_c(r), _c(g), _c(b), _c(a))

func unpack(c):
    return [(c >> 16) & 255, (c >> 8) & 255, c & 255, (c >> 24) & 255]

# Composantes flottantes [r, g, b, a] (0..1).
func to_floats(c):
    return [((c >> 16) & 255) / 255.0, ((c >> 8) & 255) / 255.0, (c & 255) / 255.0, ((c >> 24) & 255) / 255.0]

# Mélange « source par-dessus » (alpha de la source).
func blend_over(dst, src):
    sa := (src >> 24) & 255
    if sa == 255:
        return src
    if sa == 0:
        return dst
    da := 255 - sa
    r := (((src >> 16) & 255) * sa + ((dst >> 16) & 255) * da) // 255
    g := (((src >> 8) & 255) * sa + ((dst >> 8) & 255) * da) // 255
    b := ((src & 255) * sa + (dst & 255) * da) // 255
    a := sa + (((dst >> 24) & 255) * da) // 255
    return pack(r, g, b, a)

# Mélange additif (lumières, particules).
func blend_add(dst, src):
    r := ((dst >> 16) & 255) + ((src >> 16) & 255)
    g := ((dst >> 8) & 255) + ((src >> 8) & 255)
    b := (dst & 255) + (src & 255)
    return pack(r if r < 255 else 255, g if g < 255 else 255, b if b < 255 else 255, 255)

class Surface:
    func init(width, height, depth=true):
        if width <= 0 or height <= 0:
            raise("ArgumentError", "Surface : dimensions invalides")
        self.width = width
        self.height = height
        self.color = [0 for i in 0..width * height]
        self.depth = [1.0 for i in 0..width * height] if depth else []
        self.has_depth = depth

    func clear(color=0xFF000000):
        self.color = [color for i in 0..self.width * self.height]

    func clear_depth(value=1.0):
        if self.has_depth:
            self.depth = [value for i in 0..self.width * self.height]

    func pixel(x, y):
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return 0
        return self.color[y * self.width + x]

    func set_pixel(x, y, c):
        if x >= 0 and y >= 0 and x < self.width and y < self.height:
            self.color[y * self.width + x] = c

    func fill_rect(x, y, w, h, c):
        row := y if y > 0 else 0
        while row < y + h and row < self.height:
            col := x if x > 0 else 0
            while col < x + w and col < self.width:
                self.color[row * self.width + col] = c
                col += 1
            row += 1

    # Copie src (Surface) en (dx, dy), avec mélange alpha si blend.
    func draw_surface(src, dx, dy, blend=true):
        y := 0
        while y < src.height:
            x := 0
            while x < src.width:
                tx := dx + x
                ty := dy + y
                if tx >= 0 and ty >= 0 and tx < self.width and ty < self.height:
                    s := src.color[y * src.width + x]
                    k := ty * self.width + tx
                    self.color[k] = blend_over(self.color[k], s) if blend else s
                x += 1
            y += 1

    func copy():
        s := Surface(self.width, self.height, self.has_depth)
        s.color = [c for c in self.color]
        if self.has_depth:
            s.depth = [d for d in self.depth]
        return s

    # Nombre de points différents de other (même taille), à tolerance près par composante.
    func diff(other, tolerance=0):
        n := 0
        i := 0
        while i < len(self.color):
            a := self.color[i]
            b := other.color[i]
            if a != b:
                if tolerance == 0:
                    n += 1
                else:
                    ua := unpack(a)
                    ub := unpack(b)
                    k := 0
                    big := false
                    while k < 4:
                        d := ua[k] - ub[k]
                        if d < 0:
                            d = -d
                        if d > tolerance:
                            big = true
                        k += 1
                    if big:
                        n += 1
            i += 1
        return n

    # Nombre de points de couleur c.
    func count(c):
        n := 0
        for v in self.color:
            if v == c:
                n += 1
        return n

    func checksum():
        h := 2166136261
        for v in self.color:
            h = ((h ^ v) * 16777619) & 0xFFFFFFFF
        return h

    # Octets RGBA (str binaire) pour ui.canvas_put_pixels.
    func to_rgba_bytes():
        out := []
        for c in self.color:
            append(out, (c >> 16) & 255)
            append(out, (c >> 8) & 255)
            append(out, c & 255)
            append(out, (c >> 24) & 255)
        return _b.from_bytes(out)

    func to_rgb_list():
        out := []
        for c in self.color:
            append(out, (c >> 16) & 255)
            append(out, (c >> 8) & 255)
            append(out, c & 255)
        return out

    func save_ppm(path):
        out := [x for x in _b.to_bytes("P6\n" + str(self.width) + " " + str(self.height) + "\n255\n")]
        for v in self.to_rgb_list():
            append(out, v)
        _io.write_bytes(path, out)

    func describe():
        return "surface " + str(self.width) + "x" + str(self.height) + (" avec profondeur" if self.has_depth else "")
