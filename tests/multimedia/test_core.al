# multimedia.core, security et diagnostics : erreurs, Result, horodatages exacts, formats, Packet / Frame,
# tampon circulaire, descriptions de pistes, annulation, limites, lecture bornée, mesures.
from core use len
use audio.audio_format as af
use multimedia.core.errors as merr
use multimedia.core.result as res
use multimedia.core.timestamp as ts
use multimedia.core.format as mf
use multimedia.core.buffer as mb
use multimedia.core.stream as ms
use multimedia.core.cancellation as mc
use multimedia.security.limits as lim
use multimedia.security.validation as val
use multimedia.diagnostics.metrics as mm
use multimedia.diagnostics.capabilities as dcaps
use multimedia.testing.assertions as ta
use multimedia.backends.codecs.ffmpeg as ff

t := ta.Checker("multimedia core")

# ---------------------------------------------------------------- erreurs et Result
t.raises("UnsupportedError", () => merr.unsupported("codec x"), "unsupported")
t.check(merr.is_media_error("LimitError") and not merr.is_media_error("TypeError"), "types d'erreurs")
t.check(merr.category("AudioDeviceError") == "DeviceError" and merr.category("CompressionError") == "CorruptDataError", "catégories des paquets existants")
r := res.attempt(() => merr.corrupt("x", "y"))
t.check(not r.ok and r.error_type == "CorruptDataError" and r.unwrap_or(7) == 7, "Result en échec")
t.raises("CorruptDataError", () => r.unwrap(), "unwrap relève l'erreur d'origine")
t.check(res.ok(3).map((x) => x + 1).unwrap() == 4, "map")
pp := res.partition([1, 0, 4], (x) => 8 // x)
t.check(len(pp[0]) == 2 and len(pp[1]) == 1, "partition")

# ---------------------------------------------------------------- horodatages
b48 := ts.TimeBase(1, 48000)
t48 := ts.Timestamp(96000, b48)
t.check(t48.seconds() == 2.0 and t48.rescale(ts.MILLIS).pts == 2000, "conversion de base")
t.check(ts.TimeBase(2, 96000).equals(ts.TimeBase(1, 48000)), "base réduite")
t.check(ts.rescale_pts(1, ts.TimeBase(1, 3), ts.MILLIS) == 333 and ts.rescale_pts(2, ts.TimeBase(1, 3), ts.MILLIS) == 667, "arrondi au plus proche")
t.check(ts.rescale_pts(-2, ts.TimeBase(1, 3), ts.MILLIS) == -667, "arrondi des négatifs")
t.check(ts.Timestamp(1, ts.TimeBase(1, 3)).compare(ts.Timestamp(333, ts.MILLIS)) == 1, "comparaison exacte sans flottants")
t.check(ts.Timestamp(90000, ts.MPEG).equals(ts.Timestamp(1000, ts.MILLIS)), "égalité entre bases")
t.check(t48.plus(ts.Timestamp(500)).pts == 120000 and t48.minus(ts.Timestamp(1000)).pts == 48000, "addition / soustraction")
t.check(ts.from_seconds(1.5, ts.MICROS).pts == 1500000 and ts.from_seconds(-0.25).pts == -250, "depuis des secondes")
t.check(ts.format_clock(3723.5) == "01:02:03.500" and ts.format_clock(1.25, ",") == "00:00:01,250" and ts.format_clock(-1.0) == "-00:00:01.000", "format horloge")
t.check(ts.parse_clock("00:01:02,250") == 62.25 and ts.parse_clock("1:30") == 90.0 and ts.parse_clock("45") == 45.0, "lecture horloge")
t.raises("FormatError", () => ts.parse_clock("00:61:00"), "minutes >= 60")
t.raises("FormatError", () => ts.parse_clock("1:2:3:4"), "trop de champs")
t.raises("FormatError", () => ts.parse_clock("abc"), "horloge illisible")
t.raises("FormatError", () => ts.TimeBase(1, 0), "base nulle")
# dérive : 1 h à 44,1 kHz par blocs de 1024 trames reste exacte
acc := ts.Timestamp(0, ts.for_rate(44100))
for i in 0..3445:
    acc = acc.plus_pts(1024)
t.check(acc.pts == 3527680 and acc.rescale(ts.MILLIS).pts == 79993, "accumulation sans dérive")

# ---------------------------------------------------------------- formats
v := mf.VideoFormat(1280, 720, "yuv420p", 30000, 1001)
t.check(v.frame_bytes() == 1382400 and v.describe() == "1280x720 yuv420p 29.97 i/s", "VideoFormat : " + v.describe())
t.check(mf.image_bytes(4, 2, "rgba32") == 32 and mf.image_bytes(4, 2, "nv12") == 12 and mf.image_bytes(4, 2, "yuyv422") == 16, "tailles d'images")
t.raises("FormatError", () => mf.image_bytes(3, 2, "yuv420p"), "4:2:0 impair")
t.raises("FormatError", () => mf.VideoFormat(0, 10), "dimensions nulles")
t.raises("FormatError", () => mf.VideoFormat(10, 10, "xyz"), "format de points inconnu")
t.raises("FormatError", () => mf.audio(100, 2), "fréquence audio invalide")
t.check(mf.VideoFormat(10, 10, "rgb24", 50, 2).rate_num == 25 and mf.video_byte_rate(mf.VideoFormat(2, 2, "rgb24", 10, 1)) == 120, "cadence réduite, débit")
t.check(mf.has_alpha("bgra32") and not mf.has_alpha("nv12"), "alpha")

# ---------------------------------------------------------------- Packet, Frame, RingBuffer
f8 := af.AudioFormat(8000, 2, "s16le")
fr := mb.audio_frame([0.1, 0.2, 0.3, 0.4], f8, ts.Timestamp(8000, ts.for_rate(8000)))
t.check(fr.frames() == 2 and fr.seconds() == 1.0 and fr.duration == 0.00025, "Frame audio")
t.raises("FormatError", () => mb.audio_frame([0.1], f8), "trame incomplète")
t.check(mb.end_of_stream(1).eos and mb.end_frame().eos and mb.Packet(0, [1, 2]).size() == 2, "fins de flux, paquets")
rb := mb.RingBuffer(4)
rb.write([1, 2, 3])
t.raises("LimitError", () => rb.write([4, 5]), "débordement refusé (politique error)")
t.check(rb.read(2) == [1, 2] and rb.available() == 1, "lecture partielle")
t.check(rb.read_padded(3) == [3, 0.0, 0.0] and rb.underruns == 1, "sous-alimentation comblée par du silence")
ro := mb.RingBuffer(4, "drop_oldest")
ro.write([1, 2, 3])
ro.write([4, 5, 6])
t.check(ro.read(4) == [3, 4, 5, 6] and ro.dropped == 2, "drop_oldest")
ro.write([1, 2, 3, 4, 5, 6, 7, 8, 9])
t.check(ro.read(4) == [6, 7, 8, 9] and ro.dropped == 7, "écriture plus grande que la capacité")
rn := mb.RingBuffer(3, "drop_newest")
t.check(rn.write([1, 2, 3, 4]) == 3 and rn.read(5) == [1, 2, 3] and rn.dropped == 1, "drop_newest")
last := []
for k in 0..50:
    ro.write([k, k + 1])
    last = ro.read(2)
t.check(ro.is_empty() and last == [49, 50] and ro.dropped == 7, "tampon circulaire : rotation sans perte")
t.raises("FormatError", () => mb.RingBuffer(0), "capacité nulle")

# ---------------------------------------------------------------- StreamInfo / MediaInfo
info := ms.MediaInfo("x.wav", "wav", 100)
s0 := ms.StreamInfo(0, "audio", "pcm_s16le", f8, ts.for_rate(8000))
s0.duration = 2.5
s0.decodable = true
info.add_stream(s0)
t.check(info.duration == 2.5 and info.has("audio") and not info.has("video") and info.decodable(), "MediaInfo")
t.check(info.to_dict()["streams"][0]["codec"] == "pcm_s16le", "MediaInfo en dict")
t.raises("FormatError", () => ms.StreamInfo(1, "hologramme", "x"), "genre de piste vérifié")

# ---------------------------------------------------------------- annulation
src := mc.source()
mc.check(src.token)
t.check(not mc.is_cancelled(src.token) and not mc.is_cancelled(null), "jeton actif")
src.cancel("arrêt")
t.raises("CancelledError", () => mc.check(src.token), "annulation constatée")
dl := mc.Deadline(0.0)
t.raises("CancelledError", () => dl.check(), "échéance")

# ---------------------------------------------------------------- limites et lecture bornée
l := lim.strict()
t.raises("LimitError", () => l.check_dimensions(5000, 10), "largeur limitée")
t.raises("LimitError", () => l.with({"max_pixels": 1000}).check_dimensions(100, 100), "nombre de points limité")
t.raises("FormatError", () => l.check_dimensions(-1, 10), "dimension négative")
t.raises("LimitError", () => l.check_audio(48000, 9), "canaux limités")
t.check(l.with({"max_width": 8000}).get("max_width") == 8000 and l.get("max_width") == 4096, "with() ne modifie pas l'original")
t.raises("FormatError", () => lim.Limits({"max_banane": 1}), "limite inconnue")
rd := val.Reader([82, 73, 70, 70, 4, 0, 0, 0, 65, 0, 255, 255, 255, 255], "x")
t.check(rd.tag(0) == "RIFF" and rd.u32le(4) == 4 and rd.text(8, 2) == "A" and rd.s32le(10) == -1 and rd.u16be(8) == 16640, "lecture bornée")
t.raises("CorruptDataError", () => rd.u32le(12), "lecture hors des données")
t.raises("CorruptDataError", () => val.check_chunk(10, 100, 50, "bloc"), "bloc hors du fichier")
t.raises("CorruptDataError", () => val.check_magic([1, 2], 0, [1, 2, 3], "x"), "signature tronquée")
t.check(rd.tag(10) == "", "étiquette non imprimable")
t.check(val.is_bytes([0, 255]) and not val.is_bytes([256]) and not val.is_bytes("x"), "octets valides")

# ---------------------------------------------------------------- mesures et capacités
now := [0.0]
m := mm.Metrics(() => now[0])
h := m.start("decode")
now[0] = 0.5
m.stop(h)
m.record("decode", 1.5)
m.count("frames", 10)
now[0] = 2.0
rp := m.report()
t.check(rp["timings"]["decode"]["count"] == 2 and rp["timings"]["decode"]["mean"] == 1.0 and rp["timings"]["decode"]["max"] == 1.5, "chronométrages")
t.check(m.rate("frames") == 5.0 and m.counter("absent") == 0, "débit")
c := dcaps.detect()
t.check("png" in c["images"]["decode"] and "wav" in c["containers"]["read"] and c["video_playback"] == ff.available(), "capacités détectées (lecture vidéo si ffmpeg)")
t.check(len(dcaps.report()) > 0, "rapport de capacités")

t.summary()
