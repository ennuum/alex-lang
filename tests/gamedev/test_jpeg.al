# ALEX - tests du décodeur JPEG (comparé au décodage de libjpeg, références PNG). ./alex run tests/gamedev/test_jpeg.al
use multimedia.image.jpeg as jpeg
use multimedia.image.decode as dec
use io
use testing
from testing use assert_eq, assert_true

const DATA := "tests/gamedev/data/"

func compare(name, mean_max=0.5, worst_max=8, refname=null):
    r := jpeg.decode_rgba(io.read_bytes(DATA + name + ".jpg"))
    ref := dec.load(DATA + (refname if refname != null else name) + ".ref.png")
    assert_eq([r["width"], r["height"]], [ref.width, ref.height])
    px := r["buffer"].read_array("u8", r["width"] * r["height"] * 4)
    total := 0
    worst := 0
    k := 0
    while k < len(px):
        dd := px[k] - ref.pixels[k]
        if dd < 0:
            dd = 0 - dd
        total += dd
        if dd > worst:
            worst = dd
        k += 1
    mean := total * 1.0 / len(px)
    assert_true(mean < mean_max)
    assert_true(worst <= worst_max)
    return r

func t_baseline():
    compare("photo420")

testing.test("séquentiel 4:2:0", t_baseline)

func t_progressive():
    compare("photo_prog")
    compare("photo_gris_prog")

testing.test("progressif (couleur et gris)", t_progressive)

func t_restart():
    compare("photo_rst")

testing.test("intervalles de reprise (RST)", t_restart)

func t_dispatch():
    img := dec.load(DATA + "photo420.jpg")
    assert_eq([img.width, img.height, img.mode], [202, 148, "rgba"])
    assert_eq(dec.detect(io.read_bytes(DATA + "photo420.jpg")), "jpeg")

testing.test("multimedia.image.decode reconnaît le JPEG", t_dispatch)

# Les fichiers suivants sont produits par libjpeg-turbo 3 (tests/gamedev/data/mkjpeg_ref.py) ; références décodées
# par libjpeg-turbo (Pillow), sauf 12 bits (image source).

func t_arith():
    r := compare("arith_seq")
    assert_eq([r["info"]["coding"], r["info"]["process"]], ["arithmetic", "extended"])
    r = compare("arith_prog")
    assert_eq([r["info"]["coding"], r["info"]["process"]], ["arithmetic", "progressive"])
    compare("arith_gray_rst")

testing.test("codage arithmétique (séquentiel, progressif, RST)", t_arith)

func t_lossless():
    r := compare("lossless_gray", 0.001, 0)
    assert_eq(r["info"]["process"], "lossless")
    compare("lossless_rgb", 0.001, 0)
    compare("lossless_ycc", 0.001, 0)
    r = compare("lossless12", 0.001, 0)
    assert_eq(r["info"]["precision"], 12)

testing.test("sans perte (prédicteurs 1, 4, 6, 7, RST, 12 bits) : identique au pixel près", t_lossless)

func t_12bits():
    # référence = image source : l'écart vient de la compression (même ordre qu'en 8 bits, qualité 95)
    r := compare("p12", 7.0, 140)
    assert_eq(r["info"]["precision"], 12)
    compare("p12_prog", 7.0, 140, "p12")

testing.test("précision 12 bits (étendu et progressif)", t_12bits)

func t_cmyk():
    r := compare("cmyk")
    assert_eq(r["info"]["colorspace"], "cmyk")
    r = compare("ycck", 0.5, 10)
    assert_eq(r["info"]["colorspace"], "ycck")

testing.test("CMYK et YCCK (Adobe)", t_cmyk)

func t_orientation():
    b := io.read_bytes(DATA + "exif6.jpg")
    r := jpeg.decode_rgba(b)
    assert_eq([r["width"], r["height"], r["orientation"]], [61, 47, 6])
    src := r["buffer"].read_array("u8", 61 * 47 * 4)
    o := jpeg.decode_rgba(b, null, true)
    assert_eq([o["width"], o["height"], o["orientation"], o["info"]["exif_orientation"]], [47, 61, 1, 6])
    dst := o["buffer"].read_array("u8", 61 * 47 * 4)
    # orientation 6 : rotation de 90° dans le sens horaire -> dst(x, y) = src(y, H - 1 - x)
    for p in [[0, 0], [10, 5], [46, 60], [30, 17]]:
        x := p[0]
        y := p[1]
        assert_eq(dst[4 * (y * 47 + x)], src[4 * ((46 - x) * 61 + y)])
    img := jpeg.decode(b, null, true)
    assert_eq([img.width, img.height], [47, 61])
    # les huit orientations : 5..8 échangent les dimensions, 1 ne change rien
    k := 1
    while k <= 8:
        t := jpeg.orient_rgba(r["buffer"], 61, 47, k)
        assert_eq([t[1], t[2]], [47, 61] if k >= 5 else [61, 47])
        if k == 1:
            assert_eq(t[0].read_array("u8", 61 * 47 * 4), src)
        if k == 3:
            # demi-tour
            back := jpeg.orient_rgba(t[0], 61, 47, 3)
            assert_eq(back[0].read_array("u8", 61 * 47 * 4), src)
        t[0].free()
        k += 1

testing.test("orientation Exif appliquée sur demande", t_orientation)

func t_refused():
    # SOF11 (sans perte arithmétique) : refus explicite
    b := io.read_bytes(DATA + "lossless_gray.jpg")
    k := 0
    while k + 1 < len(b):
        if b[k] == 255 and b[k + 1] == 195:
            b[k + 1] = 203
            break
        k += 1
    msg := ""
    try:
        jpeg.decode_rgba(b)
    catch e:
        msg = str(e)
    assert_true(len(msg) > 0)

testing.test("refus explicite : sans perte arithmétique", t_refused)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) jpeg en échec")
print("JPEG: OK")
