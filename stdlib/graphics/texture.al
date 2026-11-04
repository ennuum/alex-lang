# ALEX STANDARD LIBRARY — graphics.texture
#
# Textures : images RGBA (points empaquetés comme graphics.surface) échantillonnées par coordonnées (u, v)
# dans 0..1 : filtrage au plus proche ou bilinéaire, répétition ou bord étiré, mipmaps (réductions par 2) et
# choix du niveau ; création depuis une Surface, une camera.video_frame.VideoFrame, une liste de points, ou
# des motifs (damier, dégradé).
#
#   use graphics.texture as gt
#   t := gt.checkerboard(64, 64, 8, 0xFFFFFFFF, 0xFF000000)
#   t.filter = "linear"
#   c := t.sample(0.25, 0.75)                     # [r, g, b, a] (0..1)

from core use len, to_int, to_float
from collections use append
use graphics.surface as gs

class Texture:
    func init(width, height, pixels=null):
        self.width = width
        self.height = height
        self.pixels = pixels if pixels != null else [0 for i in 0..width * height]
        self.filter = "nearest"      # ou "linear"
        self.wrap = "repeat"         # ou "clamp"
        self.mips = []

    func get(x, y):
        if self.wrap == "repeat":
            x = x % self.width
            y = y % self.height
            if x < 0:
                x += self.width
            if y < 0:
                y += self.height
        else:
            if x < 0:
                x = 0
            if y < 0:
                y = 0
            if x >= self.width:
                x = self.width - 1
            if y >= self.height:
                y = self.height - 1
        return self.pixels[y * self.width + x]

    func set(x, y, c):
        self.pixels[y * self.width + x] = c

    # Couleur [r, g, b, a] (0..1) en (u, v).
    func sample(u, v):
        if self.filter == "nearest":
            x := to_int(_floor(u * self.width))
            y := to_int(_floor(v * self.height))
            return gs.to_floats(self.get(x, y))
        fx := u * self.width - 0.5
        fy := v * self.height - 0.5
        x0 := to_int(_floor(fx))
        y0 := to_int(_floor(fy))
        tx := fx - x0
        ty := fy - y0
        c00 := gs.to_floats(self.get(x0, y0))
        c10 := gs.to_floats(self.get(x0 + 1, y0))
        c01 := gs.to_floats(self.get(x0, y0 + 1))
        c11 := gs.to_floats(self.get(x0 + 1, y0 + 1))
        out := []
        k := 0
        while k < 4:
            a := c00[k] + (c10[k] - c00[k]) * tx
            b := c01[k] + (c11[k] - c01[k]) * tx
            append(out, a + (b - a) * ty)
            k += 1
        return out

    # Réductions successives par 2 (moyenne de 4 points) jusqu'à 1x1.
    func build_mipmaps():
        self.mips = [self]
        cur := self
        while cur.width > 1 or cur.height > 1:
            w := cur.width // 2 if cur.width > 1 else 1
            h := cur.height // 2 if cur.height > 1 else 1
            px := []
            y := 0
            while y < h:
                x := 0
                while x < w:
                    acc := [0, 0, 0, 0]
                    for d in [[0, 0], [1, 0], [0, 1], [1, 1]]:
                        c := gs.unpack(cur.get(2 * x + d[0], 2 * y + d[1]))
                        k := 0
                        while k < 4:
                            acc[k] = acc[k] + c[k]
                            k += 1
                    append(px, gs.pack(acc[0] // 4, acc[1] // 4, acc[2] // 4, acc[3] // 4))
                    x += 1
                y += 1
            nxt := Texture(w, h, px)
            nxt.filter = self.filter
            nxt.wrap = self.wrap
            append(self.mips, nxt)
            cur = nxt
        return len(self.mips)

    # Niveau de mipmap adapté à un échantillonnage de pas texels par point de l'écran.
    func level(texels_per_pixel):
        if len(self.mips) == 0:
            return self
        lv := 0
        t := texels_per_pixel
        while t > 1.5 and lv < len(self.mips) - 1:
            t = t / 2.0
            lv += 1
        return self.mips[lv]

    func to_surface():
        s := gs.Surface(self.width, self.height, false)
        s.color = [p for p in self.pixels]
        return s

func _floor(x):
    i := to_int(x)
    if x < 0 and i != x:
        return i - 1
    return i

func from_surface(s):
    return Texture(s.width, s.height, [c for c in s.color])

# Depuis une VideoFrame (camera.video_frame) : convertie en RGB puis RGBA opaque.
func from_frame(frame):
    f := frame.to_rgb()
    px := []
    i := 0
    while i + 2 < len(f.data):
        append(px, gs.pack(f.data[i], f.data[i + 1], f.data[i + 2], 255))
        i += 3
    return Texture(f.width, f.height, px)

func checkerboard(width, height, cell, a, b):
    px := []
    y := 0
    while y < height:
        x := 0
        while x < width:
            append(px, a if ((x // cell) + (y // cell)) % 2 == 0 else b)
            x += 1
        y += 1
    return Texture(width, height, px)

# Dégradé horizontal de la couleur a à la couleur b.
func gradient(width, height, a, b):
    ca := gs.unpack(a)
    cb := gs.unpack(b)
    px := []
    y := 0
    while y < height:
        x := 0
        while x < width:
            t := x / (width - 1.0) if width > 1 else 0.0
            append(px, gs.pack(to_int(ca[0] + (cb[0] - ca[0]) * t), to_int(ca[1] + (cb[1] - ca[1]) * t), to_int(ca[2] + (cb[2] - ca[2]) * t), to_int(ca[3] + (cb[3] - ca[3]) * t)))
            x += 1
        y += 1
    return Texture(width, height, px)

func solid(width, height, c):
    return Texture(width, height, [c for i in 0..width * height])
