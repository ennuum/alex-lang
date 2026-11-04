#!/usr/bin/env python3
"""Génère les atlas de glyphes de runtime/alex/native/dyn_ui_font.al : glyphes anti-crénelés (4 bits/pixel)
rendus depuis DejaVu Sans (licence libre, redistribution autorisée) à FONT_PX pixels. Utilisés par le
rasteriseur logiciel du module ui (runtime/alex/native/dyn_ui_raster.al : X11, Win32, headless).
Outil de développement (Pillow), sans rôle dans la construction : les données générées sont versionnées.

Usage : python3 tools/gen_font.py [chemin/vers/DejaVuSans.ttf]                 (__uf_sans_*)
        python3 tools/gen_font.py --mono [chemin/vers/DejaVuSansMono.ttf]   (police du code : __uf_mono_*)
"""
import sys
from PIL import Image, ImageDraw, ImageFont

FONT_PX = 28
args = [a for a in sys.argv[1:] if a != "--mono"]
MONO = "--mono" in sys.argv[1:]
default = "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf" if MONO else "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
path = args[0] if args else default
PFX = "mono" if MONO else "sans"
OUTFILE = "runtime/alex/native/dyn_ui_font.al"
FAMILY = "DejaVu Sans Mono" if MONO else "DejaVu Sans"
font = ImageFont.truetype(path, FONT_PX)
asc, desc = font.getmetrics()

cps = list(range(0x20, 0x7F)) + list(range(0xA0, 0x100)) + [
    0x2013, 0x2014, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2026, 0x20AC,
    0x2190, 0x2191, 0x2192, 0x2193, 0x2212, 0x2260, 0x2264, 0x2265, 0x2713, 0x2715, 0x25CF,
    # français (Œ œ Ÿ) et symboles de l'IDE (ALEX Studio) : ‹ › ‖ ✗ ⚠ ▶ ■ □ ◆ ○ ▸ ▾ ◂ ★ ↻ ⟳ ⋯ ‰ · ×
    0x0152, 0x0153, 0x0178, 0x2039, 0x203A, 0x2016, 0x2717, 0x26A0, 0x25B6, 0x25A0, 0x25A1, 0x25C6, 0x25CB,
    0x25B8, 0x25BE, 0x25C2, 0x2605, 0x21BB, 0x27F3, 0x22EF, 0x2030, 0x00B7, 0x00D7, 0x2026, 0x21B5, 0x2318,
    0x21B6, 0x21B7, 0x25B2, 0x25BC, 0x2191, 0x2193, 0x21E7, 0x2302, 0x26A1, 0x2699, 0x270E, 0x2714, 0x2716]
if MONO:
    cps += [0x00B7, 0x2500, 0x2502, 0x250C, 0x2510, 0x2514, 0x2518, 0x251C, 0x2524, 0x252C, 0x2534, 0x253C,
            0x256D, 0x256E, 0x256F, 0x2570, 0x2588, 0x2591, 0x25B8, 0x25BE, 0x2192, 0x21D2, 0x2200, 0x2208,
            0x221E, 0x2227, 0x2228, 0x03B1, 0x03B2, 0x03B3, 0x03BB, 0x03C0, 0x03A3, 0x0152, 0x0153, 0x25C2, 0x25B4, 0x25C0, 0x25B6, 0x25B2, 0x25BC, 0x25CB, 0x2022, 0x00BB]
cps = sorted(set(cps))

W = H = 96
OX, OY = 24, 64
glyphs = []
blob = bytearray()
for cp in cps:
    ch = chr(cp)
    im = Image.new("L", (W, H), 0)
    ImageDraw.Draw(im).text((OX, OY), ch, font=font, fill=255, anchor="ls")
    adv = font.getlength(ch)
    bb = im.getbbox()
    if bb is None:
        glyphs.append((cp, int(round(adv * 16)), 0, 0, 0, 0, len(blob)))
        continue
    crop = im.crop(bb)
    w, h = crop.size
    px = [min(15, (v + 8) // 17) for v in crop.tobytes()]
    off = len(blob)
    for i in range(0, len(px), 2):
        a = px[i]
        b = px[i + 1] if i + 1 < len(px) else 0
        blob.append((a << 4) | b)
    glyphs.append((cp, int(round(adv * 16)), bb[0] - OX, OY - bb[1], w, h, off))

# Trois fonctions par police : métriques « px:ascendante:descendante », glyphes « cp:avance*16:bx:haut:l:h:décalage »
# (haut : au-dessus de la ligne de base), atlas en hexadécimal (deux pixels de 4 bits par octet).
funcs = {
    "__uf_%s_metrics" % PFX: "%d:%d:%d" % (FONT_PX, asc, desc),
    "__uf_%s_glyphs" % PFX: ",".join(":".join(str(v) for v in g) for g in glyphs),
    "__uf_%s_blob" % PFX: blob.hex() + "00",   # octet nul final (sentinelle)
}
try:
    lines = open(OUTFILE, encoding="utf-8").read().split("\n")
except FileNotFoundError:
    lines = []
out = []
i = 0
seen = set()
while i < len(lines):
    l = lines[i]
    name = l[5:l.index("(")] if l.startswith("func ") and "(" in l else None
    if name in funcs:
        out += [l, '    return "%s"' % funcs[name]]
        seen.add(name)
        i += 2
        continue
    out.append(l)
    i += 1
for name, v in funcs.items():
    if name not in seen:
        out += ["", "func %s() -> str:" % name, '    return "%s"' % v]
open(OUTFILE, "w", encoding="utf-8").write("\n".join(out))
print("glyphes:", len(glyphs), "blob:", len(blob), "octets")
