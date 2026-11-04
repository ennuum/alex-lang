#!/usr/bin/env python3
"""Corpus d'images de référence pour tests/multimedia/test_image.al.

Chaque image est produite par Pillow ou ImageMagick ; la référence attendue (<nom>.rgba, points RGBA 8 bits)
est extraite par ImageMagick (`convert fichier -depth 8 RGBA:-`), indépendamment du décodeur ALEX.
manifest.txt : nom largeur hauteur (une ligne par image). Relancer : python3 tests/multimedia/fixtures/make_fixtures.py
"""
import os, struct, subprocess, zlib
from PIL import Image

D = os.path.join(os.path.dirname(os.path.abspath(__file__)), "images")
os.makedirs(D, exist_ok=True)
W, H = 13, 7

def base():
    im = Image.new("RGBA", (W, H))
    for y in range(H):
        for x in range(W):
            im.putpixel((x, y), ((x * 19) % 256, (y * 37) % 256, (x * y * 11) % 256, 255 if (x + y) % 3 else (x * 20) % 256))
    return im

b = base()
made = []
def save(img, name, **kw):
    img.save(os.path.join(D, name), **kw); made.append(name)
def im_convert(src, name, *args):
    subprocess.run(["convert", os.path.join(D, src), *args, os.path.join(D, name)], check=True); made.append(name)

save(b, "rgba8.png")
save(b.convert("RGB"), "rgb8.png")
save(b.convert("L"), "gray8.png")
save(b.convert("LA"), "graya8.png")
save(b.convert("L").point(lambda v: 255 if v > 100 else 0).convert("1"), "gray1.png")
save(b.convert("RGB").quantize(16), "pal4.png", bits=4)
save(b.convert("RGB").quantize(200), "pal8.png")
p = b.convert("RGB").quantize(8); save(p, "pal_trns.png", transparency=3)
save(b.convert("RGB"), "rgb_trns.png", transparency=(b.convert("RGB").getpixel((0, 0))))
save(b.convert("L"), "gray_trns.png", transparency=b.convert("L").getpixel((1, 1)))
im_convert("rgba8.png", "rgba16.png", "-depth", "16", "-define", "png:bit-depth=16")
im_convert("rgb8.png", "rgb16.png", "-depth", "16", "-define", "png:bit-depth=16", "-define", "png:color-type=2")
im_convert("gray8.png", "gray16.png", "-depth", "16", "-define", "png:bit-depth=16", "-define", "png:color-type=0")
# PNG écrits ici directement (profondeurs et entrelacement que les outils ne produisent pas à coup sûr)
ADAM7 = [(0, 0, 8, 8), (4, 0, 8, 8), (0, 4, 4, 8), (2, 0, 4, 4), (0, 2, 2, 4), (1, 0, 2, 2), (0, 1, 1, 2)]
def write_png(name, ct, depth, samples, interlace=False, plte=None, trns=None):
    """samples(x, y) -> tuple d'entiers (valeurs dans la profondeur)"""
    nch = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    def row_bytes(xs, y):
        vals = [v for x in xs for v in samples(x, y)]
        if depth == 16:
            return b"".join(struct.pack(">H", v) for v in vals)
        if depth == 8:
            return bytes(vals)
        out, acc, n = bytearray(), 0, 0
        for v in vals:
            acc = (acc << depth) | v; n += depth
            if n == 8: out.append(acc); acc, n = 0, 0
        if n: out.append(acc << (8 - n))
        return bytes(out)
    raw = b""
    passes = ADAM7 if interlace else [(0, 0, 1, 1)]
    for (x0, y0, dx, dy) in passes:
        xs = list(range(x0, W, dx)); ys = list(range(y0, H, dy))
        if not xs or not ys: continue
        for y in ys:
            raw += b"\0" + row_bytes(xs, y)      # filtre 0 ; les autres filtres viennent des fichiers Pillow / ImageMagick
    def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
    data = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", W, H, depth, ct, 0, 0, 1 if interlace else 0))
    if plte: data += chunk(b"PLTE", plte)
    if trns: data += chunk(b"tRNS", trns)
    data += chunk(b"IDAT", zlib.compress(raw)) + chunk(b"IEND", b"")
    open(os.path.join(D, name), "wb").write(data); made.append(name)
gl = b.convert("L")
write_png("gray2.png", 0, 2, lambda x, y: (gl.getpixel((x, y)) >> 6,))
write_png("gray4.png", 0, 4, lambda x, y: (gl.getpixel((x, y)) >> 4,))
write_png("gray4_adam7.png", 0, 4, lambda x, y: (gl.getpixel((x, y)) >> 4,), True)
write_png("rgba8_adam7.png", 6, 8, lambda x, y: b.getpixel((x, y)), True)
write_png("rgba16_adam7.png", 6, 16, lambda x, y: tuple(v * 257 for v in b.getpixel((x, y))), True)
write_png("graya16.png", 4, 16, lambda x, y: (gl.getpixel((x, y)) * 257, b.getpixel((x, y))[3] * 257))
pal = bytes([0, 0, 0, 255, 0, 0, 0, 255, 0, 40, 60, 250])
write_png("pal2_trns.png", 3, 2, lambda x, y: ((x + y) % 4,), False, pal, bytes([255, 128, 0]))
write_png("rgb16_trns.png", 2, 16, lambda x, y: tuple(v * 257 for v in b.convert("RGB").getpixel((x, y))), False, None, struct.pack(">HHH", *(v * 257 for v in b.convert("RGB").getpixel((0, 0)))))
save(b.convert("RGB"), "rgb24.bmp")
save(b, "rgba32.bmp")
save(b.convert("RGB").quantize(200), "pal8.bmp")
save(b.convert("L").point(lambda v: 255 if v > 100 else 0).convert("1"), "mono1.bmp")
subprocess.run(["convert", os.path.join(D, "rgb8.png"), "-colors", "12", "-type", "Palette", "-define", "bmp:format=bmp3", "BMP3:" + os.path.join(D, "pal4.bmp")], check=True); made.append("pal4.bmp")
subprocess.run(["convert", os.path.join(D, "rgb8.png"), "-define", "bmp:subtype=RGB565", os.path.join(D, "rgb565.bmp")], check=True); made.append("rgb565.bmp")
# BMP haut en bas : hauteur négative, lignes dans l'ordre
rgb = b.convert("RGB"); stride = (W * 3 + 3) // 4 * 4
rows = b""
for y in range(H):
    r = b"".join(bytes((rgb.getpixel((x, y))[2], rgb.getpixel((x, y))[1], rgb.getpixel((x, y))[0])) for x in range(W))
    rows += r + b"\0" * (stride - len(r))
hdr = struct.pack("<IiiHHIIiiII", 40, W, -H, 1, 24, 0, len(rows), 2835, 2835, 0, 0)
open(os.path.join(D, "topdown.bmp"), "wb").write(b"BM" + struct.pack("<IHHI", 14 + 40 + len(rows), 0, 0, 54) + hdr + rows); made.append("topdown.bmp")
save(b.convert("RGB"), "rgb.ppm")
save(b.convert("L"), "gray.pgm")
g = b.convert("L")
open(os.path.join(D, "ascii.pgm"), "w").write("P2\n# commentaire\n%d %d\n1000\n" % (W, H) + " ".join(str(round(g.getpixel((x, y)) * 1000 / 255)) for y in range(H) for x in range(W)) + "\n"); made.append("ascii.pgm")
c = b.convert("RGB")
open(os.path.join(D, "ascii.ppm"), "w").write("P3\n%d %d\n255\n" % (W, H) + "\n".join(" ".join(str(v) for v in c.getpixel((x, y))) for y in range(H) for x in range(W)) + "\n"); made.append("ascii.ppm")
bits = b.convert("L").point(lambda v: 255 if v > 100 else 0)
open(os.path.join(D, "ascii.pbm"), "w").write("P1\n%d %d\n" % (W, H) + "\n".join(" ".join("0" if bits.getpixel((x, y)) else "1" for x in range(W)) for y in range(H)) + "\n"); made.append("ascii.pbm")
save(bits.convert("1"), "bin.pbm")
open(os.path.join(D, "gray16.pgm"), "wb").write(b"P5\n%d %d\n65535\n" % (W, H) + b"".join(struct.pack(">H", g.getpixel((x, y)) * 257) for y in range(H) for x in range(W))); made.append("gray16.pgm")

with open(os.path.join(D, "manifest.txt"), "w") as m:
    for name in made:
        out = subprocess.run(["convert", os.path.join(D, name), "-depth", "8", "RGBA:-"], check=True, capture_output=True).stdout
        assert len(out) == W * H * 4, (name, len(out))
        open(os.path.join(D, name + ".rgba"), "wb").write(out)
        m.write("%s %d %d\n" % (name, W, H))
print(len(made), "images")
