# multimedia.container.ogg : pages (CRC-32), paquets, flux logiques, identification FLAC / Vorbis / Opus / Speex /
# Theora comparée à ffprobe (tests/multimedia/fixtures/ogg/*.json), Ogg FLAC décodé AU BIT PRÈS contre ffmpeg,
# recherche, paquets bruts, pistes multiples, lecteur, corruption (resynchronisation), troncature, mutations.
from core use len, to_int, to_float
use io
use json
use os
use string as _s
use audio.audio_format as af
use multimedia.container.ogg as ogg
use multimedia.container.demux as dmx
use multimedia.container.probe as probe
use multimedia.core.errors as merr
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.playback.player as mp
use multimedia.testing.fake_device as fake
use multimedia.testing.fixtures as fx
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia Ogg")
D := "tests/multimedia/fixtures/ogg/"

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

# ---------------------------------------------------------------- CRC et pages
page := io.read_bytes(D + "vorbis.ogg", 0, 4096)
p0 := ogg.parse_page(page, 0)
t.check(p0["error"] == null and p0["bos"] and p0["granule"] == 0 and not p0["continued"], "première page : BOS, CRC valide")
bad := [x for x in page]
bad[p0["body"] + 3] = bad[p0["body"] + 3] ^ 1
t.check(ogg.parse_page(bad, 0)["error"] == "CRC faux", "CRC faux détecté")
t.check(ogg.parse_page([79, 103, 103, 83, 0], 0)["error"] == "tronquée" or ogg.parse_page([79, 103, 103, 83, 0], 0)["error"] == "capture OggS absente", "page tronquée")

# ---------------------------------------------------------------- comparaison avec ffprobe
for f in ["flac.oga", "flac_mono.oga", "vorbis.ogg", "opus.opus", "speex.spx", "theora.ogv", "two_streams.ogg"]:
    ref := json.parse(io.read_file(D + f + ".json"))
    i := probe.probe(D + f)
    t.check(i.container == "ogg" and len(i.streams) == len(ref["streams"]), f + " : " + str(len(i.streams)) + " piste(s)")
    for k in 0..len(ref["streams"]):
        rs := ref["streams"][k]
        ms_ := i.streams[k]
        t.check(ms_.codec == rs["codec_name"], f + " #" + str(k) + " : codec " + ms_.codec)
        if "sample_rate" in rs:
            t.check(ms_.format.rate == to_int(rs["sample_rate"]) and ms_.format.channels == rs["channels"], f + " #" + str(k) + " : " + ms_.format.describe())
        if "width" in rs:
            t.check(ms_.format.width == rs["width"] and ms_.format.height == rs["height"], f + " #" + str(k) + " : " + str(ms_.format.width) + "x" + str(ms_.format.height))
        want := to_float(rs["duration"])
        tol := 0.0011
        if ms_.codec == "opus":
            want = want - 312.0 / 48000      # RFC 7845 : durée = granule - pre-skip (ffprobe ne retire pas le pre-skip)
        if ms_.codec == "speex":
            tol = 0.02                        # granule écrite par l'encodeur (ffprobe compte les paquets)
        t.near(ms_.duration, want, tol, f + " #" + str(k) + " : durée")
        if "tags" in rs and "title" in rs["tags"]:
            t.check(i.tags["title"] == rs["tags"]["title"] and i.tags["artist"] == rs["tags"]["artist"], f + " : étiquettes")
    if i.streams[0].codec == "flac":
        t.check(i.streams[0].decodable, f + " : décodable (FLAC natif)")
    else:
        t.check(i.streams[0].decodable == ff.available(), f + " : décodable si et seulement si ffmpeg est présent")

# ---------------------------------------------------------------- Ogg FLAC : décodage exact
for n in ["flac", "flac_mono"]:
    d := dmx.open(D + n + ".oga")
    got := d.read_all()
    ref := reference(n, 16)
    t.check(len(got) == len(ref) and got == ref, n + " : identique à ffmpeg (" + str(len(got)) + " échantillons)")
    t.check(d.at_end() and d.read_frame().eos, n + " : fin de flux")
    d.close()
d := dmx.open(D + "flac.oga")
ref := reference("flac", 16)
for target in [0.0, 0.25, 1.0, 1.731, 1.99]:
    d.seek(target)
    f := d.read_frame(64)
    s0 := to_int(target * 22050 + 0.5)
    t.check(f.data == [ref[k] for k in 2 * s0..2 * s0 + 128] and f.pts.pts == s0, "recherche " + str(target) + " s : exacte")
d.seek(2.0)
t.check(d.read_frame().eos, "recherche à la fin")
d.bisect_min = 2048                  # force la dichotomie sur ce petit fichier
for target in [0.1, 0.97, 1.5, 1.9]:
    d.seek(target)
    f := d.read_frame(32)
    s0 := to_int(target * 22050 + 0.5)
    t.check(f.data == [ref[k] for k in 2 * s0..2 * s0 + 64], "dichotomie " + str(target) + " s : exacte")
t.check(d.bisect_steps >= 8, "dichotomie effectuée (" + str(d.bisect_steps) + " pas)")
d.close()
t.raises("StateError", () => d.read_frame(), "après fermeture")

# ---------------------------------------------------------------- pistes multiples, paquets bruts
two := ogg.OggDemuxer(D + "two_streams.ogg", null, 1)
mono := two.read_all()
t.check(two.selected.channels == 1 and len(mono) == 12800, "piste 1 choisie : " + str(len(mono)) + " échantillons")
t.raises("FormatError", () => ogg.OggDemuxer(D + "two_streams.ogg", null, 5), "piste inexistante")
v := ogg.OggDemuxer(D + "theora.ogv", null, 0)
nb := 0
last := -1
while true:
    p := v.read_packet()
    if p.eos:
        break
    nb += 1
    if p.granule >= 0:
        last = p.granule
t.check(nb == 10 and last >= 0, "Theora : " + str(nb) + " paquets bruts d'images")
t.raises("UnsupportedError", () => v.read_frame(), "Theora : pas de décodage simulé")
vo := dmx.open(D + "vorbis.ogg", null, "native_only")
t.raises("UnsupportedError", () => vo.read_frame(), "Vorbis : pas de décodage simulé")
pk := vo.read_packet()
t.check(not pk.eos and pk.size() > 0, "Vorbis : paquets bruts disponibles")
op := dmx.open(D + "opus.opus", null, "native_only")
count := 0
while not op.read_packet().eos:
    count += 1
t.check(count == 63, "Opus : 63 paquets de 20 ms (" + str(count) + ")")

# ---------------------------------------------------------------- lecteur
out := fake.FakeAudioOutput(af.AudioFormat(8000, 1, "s16le"))
pl := mp.Player(out, null, 512)
pl.open(D + "flac_mono.oga")
pl.play()
pl.run()
t.check(pl.state() == "ended" and out.samples == reference("flac_mono", 16), "lecteur : Ogg FLAC joué au bit près")
pl.close()

# ---------------------------------------------------------------- corruption et troncature
src := io.read_bytes(D + "flac.oga")          # 2 s stéréo, plusieurs pages de données
offs := []
k := 0
while k + 4 < len(src):
    if src[k] == 79 and src[k + 1] == 103 and src[k + 2] == 103 and src[k + 3] == 83:
        offs = offs + [k]
    k += 1
t.check(len(offs) >= 15, "plusieurs pages (" + str(len(offs)) + ")")
c1 := [x for x in src]
mid := offs[len(offs) // 2]
c1[mid + 60] = c1[mid + 60] ^ 255
p1 := fx.temp_path("c1.oga")
io.write_bytes(p1, c1)
d1 := dmx.open(p1)
part := d1.read_all()
t.check(len(part) < 88200 and len(part) > 70000 and len(d1.info.warnings) >= 1, "page de données corrompue : ignorée avec avertissement, lecture continue (" + str(len(part)) + " / 88200)")
d1.seek(1.9)
t.check(not d1.read_frame(10).eos, "recherche après la page corrompue")
p2 := fx.temp_path("c2.oga")
io.write_bytes(p2, [src[q] for q in 0..len(src) - 3000])
d2 := dmx.open(p2)
part2 := d2.read_all()
t.check(len(part2) > 44100 and len(part2) < 88200 and len(d2.info.warnings) >= 1, "fichier tronqué : pages complètes lues, avertissement (" + str(len(part2)) + ")")
ch := io.read_bytes(D + "flac_mono.oga")
c4 := [x for x in ch]
c4[79 + 40] = c4[79 + 40] ^ 255
p4 := fx.temp_path("c4.oga")
io.write_bytes(p4, c4)
d4 := dmx.open(p4)
t.check(len(d4.read_all()) == 4000 and len(d4.info.warnings) >= 1, "page de commentaires corrompue : audio intact")
p3 := fx.temp_path("c3.oga")
io.write_bytes(p3, [79, 103, 103, 83] + [0 for q in 0..100])
got := null
try:
    dmx.open(p3)
catch e:
    got = e.type
t.check(got == "CorruptDataError", "aucune page valide : " + str(got))
state := [5]
func rnd(n):
    state[0] = (state[0] * 1103515245 + 12345) & 0x7FFFFFFF
    return state[0] % n
internal := []
for q in 0..40:
    m := [x for x in ch]
    for j in 0..1 + rnd(4):
        m[rnd(len(m))] = rnd(256)
    pm := fx.temp_path("m.oga")
    io.write_bytes(pm, m)
    try:
        dm := dmx.open(pm)
        dm.read_all()
    catch e:
        if not merr.is_media_error(e.type):
            internal = internal + [e.type + " : " + e.message]
t.check(len(internal) == 0, "Ogg mutés : seulement des erreurs multimédias " + str(internal))

fx.cleanup()
t.summary()
