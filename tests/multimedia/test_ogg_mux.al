# multimedia.container.ogg_mux : pages Ogg (segments, paquets multiples de 255, débordement sur plusieurs pages,
# granules, BOS / EOS, CRC) relues par multimedia.container.ogg ; Ogg FLAC écrit en ALEX pur et relu au bit près
# (démultiplexeur ALEX, et ffmpeg s'il est installé), étiquettes, durée, MD5 de la page BOS réécrite.
from core use len, to_int
from collections use append
use io
use os
use math
use audio.audio_format as af
use multimedia.container.ogg as ogg
use multimedia.container.ogg_mux as om
use multimedia.container.demux as dmx
use multimedia.container.mux as mux
use multimedia.container.probe as probe
use multimedia.codec.audio.flac as flac
use multimedia.metadata.tags as tg
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.testing.assertions as ta
use multimedia.testing.fixtures as fx

t := ta.Checker("multimedia Ogg (écriture)")

# ---------------------------------------------------------------- pages et paquets
pages := []
w := om.OggPageWriter((p) => append(pages, p), 1234, 1000)
w.packet([1, 2, 3], 0, true)
w.packet([7 for i in 0..255], 10)                 # multiple de 255 : segment nul de fin
w.packet([9 for i in 0..70000], 20)               # > 255 segments : déborde sur la page suivante
w.packet([5], 30)
w.close(30)
octets := []
for p in pages:
    octets = octets + p
infos := []
at := 0
while at < len(octets):
    pg := ogg.parse_page(octets, at)
    append(infos, pg)
    if pg["error"] != null:
        break
    at = pg["end"]
t.check(len([i for i in infos if i["error"] == null]) == len(pages) and at == len(octets), str(len(pages)) + " pages valides (CRC)")
t.check(infos[0]["bos"] and not infos[1]["bos"] and infos[len(infos) - 1]["eos"] and infos[0]["serial"] == 1234, "BOS, EOS, numéro de série")
t.check(infos[1]["segments"][0] == 255 and infos[1]["segments"][1] == 0, "paquet de 255 octets : segment nul de fin")
# page 1 : paquet de 255 octets terminé (granule 10) + début du gros paquet ; page 2 : sa suite (continued)
t.check(len(infos) == 4 and not infos[1]["continued"] and infos[1]["granule"] == 10 and infos[2]["continued"] and infos[2]["granule"] == 20, "paquet sur plusieurs pages (continued, granules)")
t.check([i["seq"] for i in infos] == [k for k in 0..len(infos)], "numéros de page consécutifs")
t.check(infos[len(infos) - 1]["granule"] == 30, "granule de la dernière page")

# ---------------------------------------------------------------- Ogg FLAC
func signal(n, rate, f):
    return [0.4 * math.sin(2.0 * math.PI * f * i / rate) + 0.1 * math.sin(2.0 * math.PI * 3.1 * f * i / rate) for i in 0..n]

rate := 44100
g := signal(12000, rate, 440.0)
d := signal(12000, rate, 550.0)
inter := []
for i in 0..12000:
    append(inter, g[i])
    append(inter, d[i])
p := fx.temp_path("essai.oga")
tags := tg.Tags({"title": "Ogg ALEX", "artist": "Encodeur"})
m := om.OggFlacMuxer(p, af.AudioFormat(rate, 2, "s16le"), tags)
for k in 0..6:
    m.write_samples(inter[k * 4000:(k + 1) * 4000])
t.check(m.close() == 3 and m.samples() == 12000, "Ogg FLAC : 3 trames, 12000 échantillons")
info := probe.probe(p)
s0 := info.streams[0]
t.check(info.container == "ogg" and s0.codec == "flac" and s0.format.rate == rate and s0.format.channels == 2, "sondage : " + info.describe())
t.near(s0.duration, 12000.0 / rate, 0.0001, "durée par la granule")
t.check(info.tags.get("title") == "Ogg ALEX" and info.tags.get("artist") == "Encodeur", "étiquettes relues")
x := dmx.open(p)
relu := x.read_all()
x.close()
err := 0.0
for i in 0..len(inter):
    e := relu[i] - inter[i]
    if e < 0:
        e = -e
    if e > err:
        err = e
t.check(len(relu) == 24000 and err < 1.0 / 32768 + 1e-9, "décodage par le démultiplexeur Ogg ALEX")
# STREAMINFO de la page BOS réécrite : nombre d'échantillons et MD5 vérifiable
b := io.read_bytes(p)
bos := ogg.parse_page(b, 0)
t.check(bos["error"] == null and bos["bos"] and bos["segments"] == [51], "page BOS réécrite (CRC valide)")
first := [b[k] for k in bos["body"]..bos["end"]]
# « fLaC » + bloc STREAMINFO du premier paquet (octets 13 et suivants), marqué « dernier bloc »
si := flac.read_header(first[9:13] + [first[13] | 128] + first[14:] + [0, 0])
t.check(si["samples"] == 12000 and si["md5"] != "00000000000000000000000000000000", "STREAMINFO final : 12000 échantillons, MD5")
t.check(om.write_ogg_flac(fx.temp_path("court.oga"), [0.1, 0.2, 0.3], af.AudioFormat(8000, 1, "s16le")) == 1, "write_ogg_flac")
mm := mux.open(fx.temp_path("mux.oga"), af.AudioFormat(8000, 1, "s16le"))
mm.write_samples([0.25, -0.25])
t.check(mm.close() == 1 and len(dmx.open(mm.path).read_all()) == 2, "mux.open(« .oga »)")
t.raises("UnsupportedError", () => mux.open("x.ogg", af.CD), ".ogg (Vorbis) : par ffmpeg seulement")

if ff.available():
    raw := fx.temp_path("croise.pcm")
    r := os.run("ffmpeg", ["-hide_banner", "-loglevel", "error", "-y", "-i", p, "-f", "s16le", raw])
    t.check(r["code"] == 0, "ffmpeg lit l'Ogg FLAC : " + r["stderr"])
    rb := io.read_bytes(raw)
    ok := len(rb) == 4 * 12000
    if ok:
        for i in 0..24000:
            v := rb[2 * i] | (rb[2 * i + 1] << 8)
            if v >= 32768:
                v -= 65536
            e := v / 32768.0 - relu[i]
            if e > 1e-9 or e < -1e-9:
                ok = false
                break
    t.check(ok, "ffmpeg : échantillons identiques à ceux du décodeur ALEX")
    rv := os.run("ffmpeg", ["-hide_banner", "-v", "error", "-i", p, "-f", "null", "-"])
    t.check(rv["code"] == 0 and rv["stderr"] == "", "ffmpeg : aucun avertissement")
else:
    print("(ffmpeg absent : contrôle croisé ignoré)")
fx.cleanup()
t.summary()
