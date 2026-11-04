# ALEX - tests de audio.vorbis (décodeur ALEX, comparé à libvorbisfile si présente). ./alex run tests/gamedev/test_vorbis.al
use audio.vorbis as vorbis
use math
use testing
from testing use assert_eq, assert_true, assert_near

const DATA := "tests/gamedev/data/"

func _decode_alex(path):
    vorbis_buf := vorbis._decode_alex(path)
    return vorbis_buf

func t_probe():
    i := vorbis.probe(DATA + "la440_stereo.ogg")
    assert_eq(i["channels"], 2)
    assert_eq(i["rate"], 44100)
    assert_eq(i["frames"], 88200)

testing.test("en-têtes (probe)", t_probe)

func t_mono():
    d := _decode_alex(DATA + "sinus1k_22k.ogg")
    assert_eq(d["frames"], 22050)
    assert_eq(d["channels"], 1)
    x := d["buffer"].read_array("i16", 22050)
    s := 0.0
    for v in x[2000:20000]:
        s += v * v
    rms := math.sqrt(s / 18000.0) / 32768.0
    assert_near(rms, 0.125 / math.sqrt(2.0), 0.01)    # sinus d'amplitude 1/8 (ffmpeg « sine »)

testing.test("décodeur ALEX : mono", t_mono)

func t_against_vorbisfile():
    lib := vorbis._vorbisfile()
    if lib == null:
        print("  (libvorbisfile absente : comparaison ignorée)")
        return
    a := _decode_alex(DATA + "la440_stereo.ogg")
    b := vorbis._decode_vorbisfile(lib, DATA + "la440_stereo.ogg")
    assert_eq(a["frames"], b["frames"])
    xa := a["buffer"].read_array("i16", 2 * a["frames"])
    xb := b["buffer"].read_array("i16", 2 * b["frames"])
    worst := 0
    k := 0
    while k < len(xa):
        dd := xa[k] - xb[k]
        if dd < 0:
            dd = 0 - dd
        if dd > worst:
            worst = dd
        k += 1
    assert_true(worst <= 2)

testing.test("décodeur ALEX = libvorbisfile (stéréo, couplage)", t_against_vorbisfile)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) vorbis en échec")
print("VORBIS: OK")
