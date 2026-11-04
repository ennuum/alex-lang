# alex: native
# ALEX STANDARD LIBRARY — gpu_driver.gpu_command
#
# Tampons de commandes 2D et leur exécution sur une surface en mémoire (VRAM ou RAM) :
#   - Surface2D : zone de points 32 bits (0x00RRGGBB) de largeur, hauteur et pas (octets par ligne) donnés,
#     avec les primitives : point, remplissage, rectangle plein, ligne (Bresenham), copie d'une zone (avec
#     recouvrement), copie depuis la mémoire, somme de contrôle (tests) ;
#   - CommandBuffer : suite de commandes encodées (entiers) qu'on enregistre puis qu'on soumet en une fois :
#     CLEAR, FILL_RECT, LINE, PIXEL, BLIT, UPLOAD, FENCE ;
#   - GpuEngine : exécute un tampon de commandes sur une surface (moteur logiciel : la carte Bochs n'a pas de
#     2D matérielle), compte les commandes et les points écrits, signale les barrières (FENCE).
#
#   s := Surface2D(adresse, 640, 480, 640 * 4)
#   cb := CommandBuffer()
#   cb.clear(0x000020)
#   cb.fill_rect(10, 10, 100, 50, 0xFF8800)
#   cb.line(0, 0, 639, 479, 0xFFFFFF)
#   GpuEngine().execute(cb, s)
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw

const OP_CLEAR := 1
const OP_FILL_RECT := 2
const OP_LINE := 3
const OP_PIXEL := 4
const OP_BLIT := 5
const OP_UPLOAD := 6
const OP_FENCE := 7

func rgb(r: int, g: int, b: int) -> int:
    return ((r & 255) << 16) | ((g & 255) << 8) | (b & 255)

class Surface2D:
    base: int := 0
    width: int := 0
    height: int := 0
    pitch: int := 0

    func init(base: int, width: int, height: int, pitch: int):
        self.base = base
        self.width = width
        self.height = height
        self.pitch = pitch

    func addr(x: int, y: int) -> int:
        return self.base + y * self.pitch + 4 * x

    func pixel(x: int, y: int) -> int:
        if x < 0 or y < 0 or x >= self.width or y >= self.height:
            return 0
        return hw.peek32(self.addr(x, y)) & 0xFFFFFF

    func set_pixel(x: int, y: int, color: int):
        if x >= 0 and y >= 0 and x < self.width and y < self.height:
            hw.poke32(self.addr(x, y), color)

    # Rectangle plein, découpé aux bords ; renvoie le nombre de points écrits.
    func fill_rect(x: int, y: int, w: int, h: int, color: int) -> int:
        x0 := x
        y0 := y
        x1 := x + w
        y1 := y + h
        if x0 < 0:
            x0 = 0
        if y0 < 0:
            y0 = 0
        if x1 > self.width:
            x1 = self.width
        if y1 > self.height:
            y1 = self.height
        if x0 >= x1 or y0 >= y1:
            return 0
        row := y0
        while row < y1:
            a := self.addr(x0, row)
            k := 0
            n := x1 - x0
            while k < n:
                hw.poke32(a + 4 * k, color)
                k += 1
            row += 1
        return (x1 - x0) * (y1 - y0)

    func clear(color: int) -> int:
        return self.fill_rect(0, 0, self.width, self.height, color)

    func line(xa: int, ya: int, xb: int, yb: int, color: int) -> int:
        dx := xb - xa
        if dx < 0:
            dx = -dx
        dy := yb - ya
        if dy < 0:
            dy = -dy
        dy = -dy
        sx := 1
        if xa > xb:
            sx = -1
        sy := 1
        if ya > yb:
            sy = -1
        err := dx + dy
        x := xa
        y := ya
        n := 0
        while true:
            self.set_pixel(x, y, color)
            n += 1
            if x == xb and y == yb:
                break
            e2 := 2 * err
            if e2 >= dy:
                err += dy
                x += sx
            if e2 <= dx:
                err += dx
                y += sy
        return n

    # Copie la zone (sx, sy, w, h) vers (dx, dy) de la même surface (recouvrement géré).
    func blit(sx: int, sy: int, dx: int, dy: int, w: int, h: int) -> int:
        if w <= 0 or h <= 0:
            return 0
        if dy <= sy:
            row := 0
            while row < h:
                self._copy_row(sx, sy + row, dx, dy + row, w)
                row += 1
        else:
            row := h - 1
            while row >= 0:
                self._copy_row(sx, sy + row, dx, dy + row, w)
                row -= 1
        return w * h

    func _copy_row(sx: int, sy: int, dx: int, dy: int, w: int):
        if sy < 0 or sy >= self.height or dy < 0 or dy >= self.height:
            return
        if dx > sx:
            k := w - 1
            while k >= 0:
                self.set_pixel(dx + k, dy, self.pixel(sx + k, sy))
                k -= 1
        else:
            k := 0
            while k < w:
                self.set_pixel(dx + k, dy, self.pixel(sx + k, sy))
                k += 1

    # Copie une image en mémoire (src, w x h points, src_pitch octets par ligne) en (dx, dy).
    func upload(src: int, src_pitch: int, dx: int, dy: int, w: int, h: int) -> int:
        row := 0
        while row < h:
            if dy + row >= 0 and dy + row < self.height:
                k := 0
                while k < w:
                    self.set_pixel(dx + k, dy + row, hw.peek32(src + row * src_pitch + 4 * k))
                    k += 1
            row += 1
        return w * h

    # Somme de contrôle (FNV-1a sur les points) d'une zone : sert à comparer des images.
    func checksum(x: int, y: int, w: int, h: int) -> int:
        hsh := 2166136261
        row := 0
        while row < h:
            k := 0
            while k < w:
                hsh = ((hsh ^ self.pixel(x + k, y + row)) * 16777619) & 0xFFFFFFFF
                k += 1
            row += 1
        return hsh

class CommandBuffer:
    words: list[int] := []
    count: int := 0

    func init():
        self.words = []
        self.count = 0

    func _op(op: int, args: list[int]):
        append(self.words, op)
        append(self.words, len(args))
        for a in args:
            append(self.words, a)
        self.count += 1

    func clear(color: int):
        self._op(OP_CLEAR, [color])

    func fill_rect(x: int, y: int, w: int, h: int, color: int):
        self._op(OP_FILL_RECT, [x, y, w, h, color])

    func line(xa: int, ya: int, xb: int, yb: int, color: int):
        self._op(OP_LINE, [xa, ya, xb, yb, color])

    func pixel(x: int, y: int, color: int):
        self._op(OP_PIXEL, [x, y, color])

    func blit(sx: int, sy: int, dx: int, dy: int, w: int, h: int):
        self._op(OP_BLIT, [sx, sy, dx, dy, w, h])

    func upload(src: int, src_pitch: int, dx: int, dy: int, w: int, h: int):
        self._op(OP_UPLOAD, [src, src_pitch, dx, dy, w, h])

    # Barrière : l'exécuteur appelle on_fence(valeur) quand tout ce qui précède est fait.
    func fence(value: int):
        self._op(OP_FENCE, [value])

    func reset():
        self.words = []
        self.count = 0

class GpuEngine:
    commands: int := 0
    pixels: int := 0
    fences: list[int] := []

    func init():
        self.commands = 0
        self.pixels = 0
        self.fences = []

    # Exécute toutes les commandes sur s ; renvoie le nombre de commandes exécutées.
    func execute(cb: CommandBuffer, s: Surface2D) -> int:
        w := cb.words
        i := 0
        n := 0
        while i < len(w):
            op := w[i]
            a := i + 2
            if op == OP_CLEAR:
                self.pixels += s.clear(w[a])
            elif op == OP_FILL_RECT:
                self.pixels += s.fill_rect(w[a], w[a + 1], w[a + 2], w[a + 3], w[a + 4])
            elif op == OP_LINE:
                self.pixels += s.line(w[a], w[a + 1], w[a + 2], w[a + 3], w[a + 4])
            elif op == OP_PIXEL:
                s.set_pixel(w[a], w[a + 1], w[a + 2])
                self.pixels += 1
            elif op == OP_BLIT:
                self.pixels += s.blit(w[a], w[a + 1], w[a + 2], w[a + 3], w[a + 4], w[a + 5])
            elif op == OP_UPLOAD:
                self.pixels += s.upload(w[a], w[a + 1], w[a + 2], w[a + 3], w[a + 4], w[a + 5])
            elif op == OP_FENCE:
                append(self.fences, w[a])
            else:
                raise("DriverError", "GpuEngine : commande inconnue " + str(op))
            i = a + w[i + 1]
            n += 1
        self.commands += n
        return n
