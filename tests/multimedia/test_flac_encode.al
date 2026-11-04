# multimedia.codec.audio.flac_encoder : encodage FLAC en ALEX pur relu AU BIT PRÈS par le décodeur ALEX (CRC, MD5
# compris) et, s'il est installé, par ffmpeg ; sous-trames constante / fixe / verbatim, bits perdus, stéréo
# décorrélée, tailles de bloc et fréquences hors table, 8 à 32 bits, 1 à 8 canaux, étiquettes, écriture
# progressive, compression réelle.
from core use len, to_int
from collections use append
use io
use os
use math
use audio.audio_format as af
use multimedia.codec.audio.flac as flac
use multimedia.codec.audio.flac_encoder as fe
use multimedia.container.demux as dmx
use multimedia.container.mux as mux
use multimedia.codec.registry as reg
use multimedia.container.probe as probe
use multimedia.metadata.tags as tg
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.testing.assertions as ta
use multimedia.testing.fixtures as fx

t := ta.Checker("multimedia FLAC (encodeur)")

# Signal musical déterministe : deux sinus, une enveloppe, un peu de « bruit » pseudo-aléatoire.
func signal(n, rate, bits, phase=0.0, noise=3):
    amp := (1 << (bits - 1)) * 0.4
    out := []
    seed := 12345
    for i in 0..n:
        seed = (seed * 1103515245 + 12345) % 2147483648
        x := math.sin(2.0 * math.PI * 440.0 * i / rate + phase) * 0.7 + math.sin(2.0 * math.PI * 1234.5 * i / rate) * 0.3
        append(out, to_int(amp * x * (0.5 + 0.5 * math.sin(3.0 * i / rate))) + (seed % (2 * noise + 1)) - noise)
    return out

func roundtrip(chans, rate, bits, label, block=fe.DEFAULT_BLOCK, md5=true):
    data := fe.encode(chans, rate, bits, block, null, md5)
    got := flac.decode(data)
    same := got["channels"] == chans
    t.check(same and got["info"]["rate"] == rate and got["info"]["bits"] == bits and got["info"]["samples"] == len(chans[0]), label + " : identique (" + str(len(data)) + " octets)")
    if md5:
        t.check(got["md5_checked"], label + " : MD5 vérifié")
    return data

# ---------------------------------------------------------------- sous-trames et canaux
mono := signal(10000, 44100, 16)
d1 := roundtrip([mono], 44100, 16, "mono 16 bits")
t.check(len(d1) < 10000 * 2 * 0.8, "compression réelle : " + str(len(d1)) + " octets pour " + str(10000 * 2) + " en PCM")
gauche := signal(9000, 48000, 16)
droite := [v // 2 + 7 for v in gauche]
roundtrip([gauche, droite], 48000, 16, "stéréo corrélée 16 bits")
roundtrip([signal(5000, 44100, 24), signal(5000, 44100, 24, 1.0)], 44100, 24, "stéréo 24 bits")
roundtrip([[1000 for i in 0..3000]], 22050, 16, "constante")
roundtrip([[0 for i in 0..4096]], 8000, 8, "silence 8 bits")
bruit := []
s := 7
for i in 0..2000:
    s = (s * 1103515245 + 12345) % 2147483648
    append(bruit, (s >> 8) % 65536 - 32768)
roundtrip([bruit], 44100, 16, "bruit blanc (verbatim)")
roundtrip([[v << 8 for v in signal(3000, 44100, 16)]], 44100, 24, "16 bits rangés dans 24 (bits perdus)")
roundtrip([signal(2000, 96000, 32, 0.0, 1000)], 96000, 32, "32 bits")
roundtrip([signal(1500, 44100, 12)], 44100, 12, "12 bits")
roundtrip([signal(1200, 44100, 16, k * 0.3) for k in 0..6], 44100, 16, "6 canaux")
roundtrip([signal(700, 11025, 16)], 11025, 16, "fréquence 11025 Hz (hors table)")
roundtrip([signal(900, 37800, 16)], 37800, 16, "fréquence 37800 Hz (codée sur 16 bits)")
roundtrip([signal(1000, 44100, 16)], 44100, 16, "blocs de 300 échantillons", 300)
roundtrip([signal(20000, 44100, 16)], 44100, 16, "blocs de 1152", 1152)
roundtrip([signal(5, 44100, 16)], 44100, 16, "5 échantillons")
data := roundtrip([signal(2000, 44100, 16)], 44100, 16, "sans MD5", 4096, false)
t.check(flac.read_header(data)["md5"] == "00000000000000000000000000000000", "sans MD5 : empreinte nulle")
t.check(fe._utf8_number(0x7F) == [0x7F] and fe._utf8_number(0x80) == [0xC2, 0x80] and fe._utf8_number(0x10000) == [0xF0, 0x90, 0x80, 0x80], "numéro de trame en UTF-8 étendu")
t.raises("FormatError", () => fe.encode([[1, 2]], 44100, 40), "bits invalides refusés")

# ---------------------------------------------------------------- écriture progressive, flottants, étiquettes
p := fx.temp_path("enc.flac")
tags := tg.Tags({"title": "Essai", "artist": "ALEX", "track": "3", "comment_libre": "oui"})
e := fe.FlacEncoder(p, af.AudioFormat(44100, 2, "s16le"), tags)
flot := []
for i in 0..10000:
    append(flot, 0.5 * math.sin(2.0 * math.PI * 440.0 * i / 44100))
    append(flot, 0.25 * math.sin(2.0 * math.PI * 660.0 * i / 44100))
for k in 0..10:
    e.write_samples(flot[k * 2000:(k + 1) * 2000])
t.check(e.close() == 3 and e.samples() == 10000 and e.duration() > 0.22, "écriture progressive : 3 trames, 10000 échantillons")
info := probe.probe(p)
t.check(info.container == "flac" and info.streams[0].format.channels == 2 and info.tags.get("title") == "Essai" and info.tags.get("track") == "3", "sondage du fichier écrit : " + info.describe())
d := dmx.open(p)
relu := d.read_all()
err := 0.0
for i in 0..len(flot):
    x := relu[i] - flot[i]
    if x < 0:
        x = -x
    if x > err:
        err = x
t.check(len(relu) == 20000 and err < 1.0 / 32768 + 1e-9, "flottants relus à un pas de quantification près")
d.close()
whole := flac.decode(io.read_bytes(p))
t.check(whole["md5_checked"], "écriture progressive : MD5 de STREAMINFO vérifié")
t.check(fe.write_flac(fx.temp_path("court.flac"), [0.1, -0.1, 0.2, -0.2], af.AudioFormat(8000, 1, "s16le")) == 1, "write_flac")
m := mux.open(fx.temp_path("mux.flac"), af.AudioFormat(22050, 1, "s16le"))
m.write_bytes(af.encode([0.5, -0.5, 0.25], af.AudioFormat(22050, 1, "s16le")))
t.check(m.close() == 1, "mux.open(« .flac ») : une trame")
t.samples_near(dmx.open(m.path).read_all(), [0.5, -0.5, 0.25], 1.0 / 32768 + 1e-9, "mux.open(« .flac ») : octets PCM écrits et relus")
octets := reg.encoder("flac")([0.5, -0.5], af.AudioFormat(8000, 1, "s16le"))
t.check(reg.decoder("flac")(octets)["channels"] == [[16384, -16384]], "registre : encodeur flac intégré")

# ---------------------------------------------------------------- contrôle croisé par ffmpeg
if ff.available():
    q := fx.temp_path("croise.flac")
    io.write_bytes(q, fe.encode([gauche, droite], 48000, 16))
    raw := fx.temp_path("croise.pcm")
    r := os.run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", "-i", q, "-f", "s16le", raw])
    t.check(r["code"] == 0, "ffmpeg décode le FLAC écrit : " + r["stderr"])
    b := io.read_bytes(raw)
    ok := len(b) == 4 * len(gauche)
    if ok:
        for i in 0..len(gauche):
            k := 4 * i
            l := b[k] | (b[k + 1] << 8)
            rr := b[k + 2] | (b[k + 3] << 8)
            if l >= 32768:
                l -= 65536
            if rr >= 32768:
                rr -= 65536
            if l != gauche[i] or rr != droite[i]:
                ok = false
                break
    t.check(ok, "ffmpeg : échantillons identiques au bit près")
    rv := os.run("ffmpeg", ["-hide_banner", "-v", "error", "-i", q, "-f", "null", "-"])
    t.check(rv["code"] == 0 and rv["stderr"] == "", "ffmpeg : aucun avertissement (CRC, MD5)")
else:
    print("(ffmpeg absent : contrôle croisé ignoré)")
fx.cleanup()
t.summary()
