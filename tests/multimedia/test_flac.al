# multimedia : décodeur FLAC (codec.audio.flac) et démultiplexeur (container.flac_demux), comparés AU BIT PRÈS aux
# échantillons décodés par ffmpeg (tests/multimedia/fixtures/flac : niveaux de compression 0 à 12, quatre modes
# stéréo, 16 / 24 / 32 bits, 1 à 6 canaux, LPC d'ordre 32, petits blocs, blocs de taille impaire, bruit, silence),
# contrôle MD5, recherche exacte, paquets, lecteur, fichiers corrompus et mutations.
from core use len, to_int
use io
use os
use string as _s
use audio.audio_format as af
use multimedia.codec.audio.flac as flac
use multimedia.container.flac_demux as fdx
use multimedia.container.demux as dmx
use multimedia.container.probe as probe
use multimedia.codec.registry as reg
use multimedia.core.errors as merr
use multimedia.playback.player as mp
use multimedia.testing.fake_device as fake
use multimedia.testing.fixtures as fx
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia FLAC")
D := "tests/multimedia/fixtures/flac/"

# Référence ffmpeg : entiers 32 bits -> valeurs dans la profondeur du fichier -> flottants exacts.
func reference(name, bits):
    b := io.read_bytes(D + name + ".pcm")
    shift := 32 - bits
    scale := 1.0 / (1 << (bits - 1))
    n := len(b) // 4
    out := [0.0 for i in 0..n]
    for i in 0..n:
        k := 4 * i
        v := b[k] | (b[k + 1] << 8) | (b[k + 2] << 16) | (b[k + 3] << 24)
        if v >= 2147483648:
            v = v - 4294967296
        out[i] = (v >> shift) * scale
    return out

names := []
for f in os.list_dir(D):
    if _s.ends_with(f, ".flac"):
        names = names + [_s.substring(f, 0, len(f) - 5)]

# ---------------------------------------------------------------- corpus : identique au bit près
for n in names:
    d := dmx.open(D + n + ".flac")
    ref := reference(n, d.bits)
    got := d.read_all()
    same := len(got) == len(ref)
    if same:
        for i in 0..len(ref):
            if got[i] != ref[i]:
                same = false
                break
    t.check(same, n + " : identique à ffmpeg (" + str(len(got)) + " / " + str(len(ref)) + " échantillons, " + d.format.describe() + ")")
    t.check(d.at_end() and d.read_frame().eos and len(d.info.warnings) == 0, n + " : fin de flux propre")
    d.close()

# ---------------------------------------------------------------- MD5 de STREAMINFO
for n in ["st16_l8", "st24", "ch6", "noise24"]:
    r := flac.decode(io.read_bytes(D + n + ".flac"))
    t.check(r["md5_checked"], n + " : MD5 vérifié")
info := flac.read_header(io.read_bytes(D + "mono16.flac"))
t.check(len(info["md5"]) == 32 and info["rate"] == 8000 and info["bits"] == 16 and info["samples"] == 3200, "STREAMINFO")

# ---------------------------------------------------------------- recherche exacte (avec et sans SEEKTABLE)
d := dmx.open(D + "long_seek.flac")
ref := reference("long", 16)
t.check(len(d.meta["seektable"]) == 4 and len(dmx.open(D + "long.flac").meta["seektable"]) == 0, "SEEKTABLE lue (" + str(len(d.meta["seektable"])) + " points, point de réserve ignoré)")
for target in [0.0, 0.5, 1.2345, 2.9, 3.0]:
    got := d.seek(target)
    f := d.read_frame(100)
    k := d.format.rate
    s0 := to_int(target * k + 0.5)
    want := [ref[i] for i in s0..(s0 + 100 if s0 + 100 < len(ref) else len(ref))]
    data := [] if f.eos else f.data
    t.check(data == want and f.eos == (len(want) == 0), "recherche " + str(target) + " s : échantillons exacts")
    if not f.eos:
        t.check(f.pts.pts == s0, "pts après recherche " + str(target))
d.meta["seektable"] = []
d.seek(2.0)
t.check(d.read_frame(50).data == [ref[i] for i in 16000..16050], "recherche sans table (depuis le début)")
d.seek(1.0)
a := d.read_frame(7)
b := d.read_frame(13)
t.check(a.data + b.data == [ref[i] for i in 8000..8020] and b.pts.pts == 8007, "lectures successives après recherche")
d.close()
t.raises("StateError", () => d.read_frame(), "lecture après fermeture")

# ---------------------------------------------------------------- paquets
d2 := dmx.open(D + "odd_blocks.flac")
total := 0
nb := 0
crc_ok := true
while true:
    p := d2.read_packet()
    if p.eos:
        break
    if p.pts.pts != total:
        crc_ok = false
    total += p.duration
    nb += 1
t.check(total == d2.frames and nb == (d2.frames + 999) // 1000 and crc_ok, "paquets : " + str(nb) + " trames de 1000, pts continus")
d2.close()

# ---------------------------------------------------------------- sondage, registre, lecteur
i := probe.probe(D + "st24.flac")
t.check(i.container == "flac" and i.decodable() and i.first("audio").format.sample_format == "s24le" and len(i.warnings) == 0, "sondage : FLAC décodable")
t.check(reg.can_decode("flac") and reg.can_encode("flac") and reg.find("flac")["origin"] == "intégré", "registre : décodeur et encodeur intégrés")
t.check(len(reg.decoder("flac")(io.read_bytes(D + "silence.flac"))["channels"][0]) == 2400, "décodeur du registre")
out := fake.FakeAudioOutput(af.AudioFormat(8000, 1, "s16le"))
pl := mp.Player(out, null, 1000)
pl.open(D + "mono16.flac")
pl.play()
pl.run()
t.check(pl.state() == "ended" and out.samples == reference("mono16", 16), "lecteur : FLAC joué au bit près")
pl.seek(0.2)
t.check(pl.position() == 0.2, "lecteur : recherche dans un FLAC")
pl.close()

# ---------------------------------------------------------------- fichiers corrompus
src := io.read_bytes(D + "st16_l5.flac")
hdr := flac.read_header(src)
ff := hdr["first_frame"]
func expect_error(b, label, kind):
    p := fx.temp_path("x.flac")
    io.write_bytes(p, b)
    got := null
    try:
        dd := dmx.open(p, null, "native_only")
        dd.read_all()
    catch e:
        got = e.type
    t.check(got == kind, label + " : " + str(got))
c1 := [x for x in src]
c1[ff + 2] = c1[ff + 2] ^ 0x10
expect_error(c1, "en-tête de trame modifié (CRC-8)", "CorruptDataError")
c2 := [x for x in src]
c2[ff + 200] = c2[ff + 200] ^ 0x01
expect_error(c2, "octet de sous-trame modifié (CRC-16)", "CorruptDataError")
c3 := [x for x in src]
c3[0] = 70
expect_error(c3, "signature fausse", "UnsupportedError")
expect_error([src[k] for k in 0..30], "STREAMINFO tronqué", "CorruptDataError")
p4 := fx.temp_path("trunc.flac")
io.write_bytes(p4, [src[k] for k in 0..len(src) - 500])
d4 := dmx.open(p4)
part := d4.read_all()
t.check(len(part) > 0 and len(part) < 2 * 13230 and len(d4.info.warnings) == 1, "fichier tronqué : trames complètes lues, avertissement")
c5 := [x for x in src]
c5[8 + 10] = 0
c5[8 + 11] = 0
c5[8 + 12] = 0
expect_error(c5, "fréquence nulle dans STREAMINFO", "CorruptDataError")
# mutations reproductibles
state := [99]
func rnd(n):
    state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
    return state[0] % n
small := io.read_bytes(D + "small_blocks.flac")
internal := []
for k in 0..60:
    m := [x for x in small]
    for j in 0..1 + rnd(3):
        m[rnd(len(m))] = rnd(256)
    if k % 3 == 0:
        m = [m[q] for q in 0..rnd(len(m))]
    try:
        flac.decode(m, null, false)
    catch e:
        if not merr.is_media_error(e.type):
            internal = internal + [e.type + " : " + e.message]
t.check(len(internal) == 0, "FLAC mutés : seulement des erreurs multimédias " + str(internal))

fx.cleanup()
t.summary()
