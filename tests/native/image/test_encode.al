# alex: native
# image.encode (natif seulement : les décodeurs et encodeurs d'image travaillent en mémoire brute) : PNG sans
# perte, JPEG proche de l'original, orientation Exif, découpe, vignettes « fit » et « cover », format « auto ».
#   sh tests/native/image/run.sh
use io
use os
use image.image as im
use image.raster as rs
use image.encode as enc
from image.raster use Raster
from image.image use Anim
from core use len

func check(ok: bool, what: str, fails: list[int]):
    if ok:
        print("ok    " + what)
    else:
        print("ÉCHEC " + what)
        fails[0] = fails[0] + 1

func gradient(w: int, h: int, alpha: bool) -> Raster:
    r := rs.create(w, h)
    y := 0
    while y < h:
        x := 0
        while x < w:
            a := 255
            if alpha and x < w // 4:
                a = (y * 255) // h
            rs.put(r, x, y, (a << 24) | (((x * 255) // w) << 16) | (((y * 255) // h) << 8) | 128)
            x += 1
        y += 1
    return r

func max_diff(a: Raster, b: Raster) -> int:
    m := 0
    y := 0
    while y < a.height:
        x := 0
        while x < a.width:
            p := rs.get(a, x, y)
            q := rs.get(b, x, y)
            k := 0
            while k < 32:
                d := ((p >> k) & 255) - ((q >> k) & 255)
                if d < 0:
                    d = -d
                if d > m:
                    m = d
                k += 8
            x += 1
        y += 1
    return m

func decode1(data: str) -> Raster:
    an: Anim := im.decode(data)
    r: Raster := an.frames[0]
    return r

func main():
    fails: list[int] := [0]
    g := gradient(37, 23, true)
    p := enc.png(g)
    check(im.kind(p) == "png", "PNG reconnu", fails)
    back := decode1(p)
    check(back.width == 37 and back.height == 23 and max_diff(g, back) == 0, "PNG RGBA sans perte", fails)
    o := gradient(64, 40, false)
    check(not enc.has_alpha(o) and enc.has_alpha(g), "has_alpha", fails)
    check(max_diff(o, decode1(enc.png(o))) == 0, "PNG RGB sans perte", fails)
    j := enc.jpeg(o, 92)
    check(im.kind(j) == "jpeg", "JPEG reconnu", fails)
    jb := decode1(j)
    check(jb.width == 64 and jb.height == 40 and max_diff(o, jb) <= 24, "JPEG proche de l'original (écart " + str(max_diff(o, jb)) + ")", fails)
    check(len(enc.jpeg(o, 20)) < len(j), "qualité plus basse : fichier plus petit", fails)
    # orientation : 3 × 2, points numérotés
    t := rs.create(3, 2)
    i := 0
    while i < 6:
        rs.put(t, i % 3, i // 3, 0xFF000000 | i)
        i += 1
    r6 := enc.orient(t, 6)
    check(r6.width == 2 and r6.height == 3 and (rs.get(r6, 0, 0) & 255) == 3 and (rs.get(r6, 1, 0) & 255) == 0 and (rs.get(r6, 1, 2) & 255) == 2, "orientation 6 (90° horaire)", fails)
    r3 := enc.orient(t, 3)
    check((rs.get(r3, 0, 0) & 255) == 5 and (rs.get(r3, 2, 1) & 255) == 0, "orientation 3 (180°)", fails)
    r8 := enc.orient(t, 8)
    check(r8.width == 2 and (rs.get(r8, 0, 0) & 255) == 2 and (rs.get(r8, 1, 2) & 255) == 3, "orientation 8 (90° antihoraire)", fails)
    c := enc.crop(o, 10, 5, 20, 7)
    check(c.width == 20 and c.height == 7 and rs.get(c, 0, 0) == rs.get(o, 10, 5), "découpe", fails)
    # Exif d'une photo « tenue en portrait » : 48 × 24 enregistrée, orientation 6
    ex := io.read_file("tests/native/image/exif6.jpg")
    check(enc.exif_orientation(ex) == 6 and enc.exif_orientation(j) == 1, "orientation Exif lue", fails)
    v := decode1(enc.thumbnail(ex, 100, 100, "fit", "png", 80))
    check(v.width == 24 and v.height == 48, "vignette : orientation appliquée", fails)
    check(((rs.get(v, 12, 2) >> 16) & 255) < 100 and ((rs.get(v, 12, 45) >> 16) & 255) > 150, "vignette : bande bleue en haut", fails)
    big := enc.png(gradient(400, 200, false))
    f := decode1(enc.thumbnail(big, 100, 100, "fit", "jpeg", 80))
    check(f.width == 100 and f.height == 50, "fit 100 × 100 : 100 × 50", fails)
    cv := decode1(enc.thumbnail(big, 100, 100, "cover", "png", 80))
    check(cv.width == 100 and cv.height == 100, "cover 100 × 100", fails)
    check(im.kind(enc.thumbnail(enc.png(g), 10, 10, "fit", "auto", 80)) == "png" and im.kind(enc.thumbnail(big, 10, 10, "fit", "auto", 80)) == "jpeg", "auto : PNG si transparence, sinon JPEG", fails)
    small := decode1(enc.thumbnail(enc.png(gradient(20, 10, false)), 100, 100, "fit", "png", 80))
    check(small.width == 20 and small.height == 10, "jamais d'agrandissement", fails)
    if fails[0] > 0:
        print(str(fails[0]) + " échec(s)")
        os.exit(1)
    print("image.encode : tout est correct")

main()
