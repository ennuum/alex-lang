# multimedia.image : décodage PNG / BMP / PNM comparé à un corpus de référence (tests/multimedia/fixtures, points
# extraits par ImageMagick ; écart de 1 toléré quand la profondeur source n'est pas 8 bits : arrondis différents), allers-retours d'encodage, conversions, redimensionnement, métadonnées.
from core use len
use io
use os
use string as _s
use multimedia.image.image as mi
use multimedia.image.decode as dec
use multimedia.image.encode as enc
use multimedia.image.convert as cv
use multimedia.image.resize as rs
use multimedia.image.metadata as imeta
use multimedia.security.limits as lim
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia image")
D := "tests/multimedia/fixtures/images/"

# ---------------------------------------------------------------- corpus de référence
for line in _s.split(io.read_file(D + "manifest.txt"), "\n"):
    if len(_s.trim(line)) == 0:
        continue
    parts := _s.split(line, " ")
    name := parts[0]
    want := io.read_bytes(D + name + ".rgba")
    r := t.attempt(() => dec.load(D + name), "décodage " + name)
    if r.ok:
        got := cv.to_mode(r.value, "rgba")
        tol := 0
        if _s.contains(name, "16") or _s.contains(name, "565") or name == "ascii.pgm":
            tol = 1
        t.check(got.width == 13 and got.height == 7, name + " : dimensions " + got.describe())
        t.check(ta.max_byte_difference(got.pixels, want) <= tol, name + " : points (écart " + str(ta.max_byte_difference(got.pixels, want)) + ")")

# ---------------------------------------------------------------- allers-retours
g := mi.gradient(37, 11, "rgba")
g.set(3, 4, [10, 20, 30, 0])
g.set(5, 6, [200, 100, 50, 128])
for mode in ["gray", "rgb", "rgba"]:
    src := cv.to_mode(g, mode)
    back := dec.decode(enc.encode_png(src))
    t.check(back.equals(src), "PNG aller-retour " + mode)
    b2 := dec.decode(enc.encode_bmp(src))
    want := src if mode != "gray" else cv.to_mode(src, "rgb")
    t.check(b2.equals(want), "BMP aller-retour " + mode)
    p2 := dec.decode(enc.encode_pnm(src))
    t.check(p2.equals(src if mode != "rgba" else cv.flatten(src)), "PNM aller-retour " + mode)
t.check(dec.decode(enc.encode_png(g, null, 6, false)).equals(g), "PNG sans filtre adaptatif")
tmp := os.tmp_dir() + "/alex_mm_" + str(os.pid()) + ".png"
enc.save(g, tmp, {"Title": "Essai", "Author": "ALEX"})
m := imeta.read(tmp)
t.check(m["format"] == "png" and m["width"] == 37 and m["height"] == 11 and m["color"] == "rgba", "métadonnées PNG")
t.check(m["text"]["Title"] == "Essai" and m["text"]["Author"] == "ALEX", "textes PNG")
t.check(dec.load(tmp).meta["text"]["Title"] == "Essai", "textes PNG au décodage")
os.remove(tmp)
t.check(imeta.read(D + "rgb24.bmp")["bit_depth"] == 24 and imeta.read(D + "pal4.png")["color"] == "palette", "métadonnées BMP / palette")
t.check(imeta.read(D + "rgba8_adam7.png")["interlaced"], "entrelacement signalé")

# ---------------------------------------------------------------- détection et formats non pris en charge
t.check(dec.detect([255, 216, 255, 224]) == "jpeg" and dec.detect([71, 73, 70, 56, 57, 97]) == "gif", "détection JPEG / GIF")
t.raises("CorruptDataError", () => dec.decode([255, 216, 255, 224, 0, 16]), "JPEG tronqué : erreur de données (pas d'image simulée)")
t.raises("UnsupportedError", () => dec.decode([1, 2, 3, 4]), "signature inconnue")
t.raises("UnsupportedError", () => enc.save(g, "x.jpg"), "extension non prise en charge")

# ---------------------------------------------------------------- image : opérations
a := mi.new(4, 3, "rgb", [1, 2, 3])
a.set(0, 0, [9, 9, 9])
t.check(a.get(0, 0) == [9, 9, 9] and a.get(3, 2) == [1, 2, 3], "get / set / remplissage")
t.check(a.flip_h().get(3, 0) == [9, 9, 9] and a.flip_v().get(0, 2) == [9, 9, 9], "miroirs")
rt := a.rotate90()
t.check(rt.width == 3 and rt.height == 4 and rt.get(2, 0) == [9, 9, 9], "rotation 90°")
t.check(a.crop(0, 0, 2, 2).get(0, 0) == [9, 9, 9], "recadrage")
t.raises("FormatError", () => a.get(4, 0), "point hors de l'image")
t.raises("FormatError", () => mi.Image(2, 2, "rgb", [1, 2, 3]), "taille des données vérifiée")
fond := mi.new(2, 1, "rgb", [0, 0, 0])
fond.paste(mi.new(1, 1, "rgba", [255, 255, 255, 128]), 1, 0)
t.check(fond.get(1, 0) == [128, 128, 128] and fond.get(0, 0) == [0, 0, 0], "collage avec alpha")
vf := mi.to_video_frame(mi.gradient(4, 2, "gray"))
t.check(vf.pixel_format == "rgb24" and mi.from_video_frame(vf).equals(cv.to_mode(mi.gradient(4, 2, "gray"), "rgb")), "passerelle VideoFrame")

# ---------------------------------------------------------------- conversions
t.check(cv.luma(255, 255, 255) == 255 and cv.luma(0, 0, 0) == 0, "luminance")
t.check(cv.flatten(mi.new(1, 1, "rgba", [255, 0, 0, 0]), [0, 0, 255]).get(0, 0) == [0, 0, 255], "composition sur fond")
pm := cv.premultiply(mi.new(1, 1, "rgba", [200, 100, 50, 128]))
t.check(pm.get(0, 0) == [100, 50, 25, 128], "alpha prémultiplié : " + str(pm.get(0, 0)))
t.check(ta.max_byte_difference(cv.unpremultiply(pm).pixels, [200, 100, 50, 128]) <= 2, "retour du prémultiplié")
yuv := cv.rgb_to_yuv420p(mi.new(4, 4, "rgb", [120, 60, 200]))
t.check(len(yuv[0]) == 16 and len(yuv[1]) == 4, "plans yuv420p")
t.check(ta.max_byte_difference(cv.yuv420p_to_rgb(yuv, 4, 4).pixels, mi.new(4, 4, "rgb", [120, 60, 200]).pixels) <= 3, "aller-retour YUV")
t.raises("FormatError", () => cv.rgb_to_yuv420p(mi.new(3, 2, "rgb")), "4:2:0 exige des dimensions paires")
t.check(cv.invert(mi.new(1, 1, "rgba", [0, 10, 255, 77])).get(0, 0) == [255, 245, 0, 77], "inversion (alpha conservé)")
t.check(cv.threshold(mi.new(1, 1, "gray", [200])).get(0, 0) == [255], "seuil")

# ---------------------------------------------------------------- redimensionnement
dam := mi.checkerboard(8, 8, 1, null, null, "gray")
t.check(rs.box(dam, 4, 4).get(1, 1) == [128], "réduction par moyenne")
t.check(rs.nearest(mi.new(2, 2, "rgb", [5, 6, 7]), 5, 3).get(4, 2) == [5, 6, 7], "plus proche voisin")
bl := rs.bilinear(mi.Image(2, 1, "gray", [0, 255]), 4, 1)
t.check(bl.pixels[0] == 0 and bl.pixels[3] == 255 and bl.pixels[1] > 0 and bl.pixels[1] < bl.pixels[2], "bilinéaire : " + str(bl.pixels))
t.check(rs.fit_size(1920, 1080, 320, 320) == [320, 180] and rs.fit_size(100, 50, 320, 320) == [100, 50], "taille ajustée")
t.check(rs.cover(mi.gradient(40, 20), 10, 10).width == 10, "remplissage recadré")
t.check(rs.thumbnail(mi.gradient(64, 32), 16).describe() == "16x8 rgb", "vignette")
t.raises("LimitError", () => rs.resize(dam, 5000, 10, "nearest", lim.strict()), "taille cible limitée")

t.summary()
