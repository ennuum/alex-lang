# multimedia.container et codec : sondage (corpus ffmpeg de tests/multimedia/fixtures/media), démultiplexage WAV
# comparé aux échantillons décodés par ffmpeg, recherche temporelle, multiplexage et allers-retours d'étiquettes,
# registre des codecs.
from core use len
use io
use os
use audio.audio_format as af
use multimedia.container.probe as probe
use multimedia.container.demux as dmx
use multimedia.container.mux as mux
use multimedia.container.metadata as cmeta
use multimedia.codec.registry as reg
use multimedia.codec.capabilities as caps
use multimedia.metadata.tags as tg
use multimedia.core.buffer as mb
use multimedia.core.timestamp as ts
use multimedia.security.limits as lim
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia conteneurs")
M := "tests/multimedia/fixtures/media/"

# ---------------------------------------------------------------- WAV : tous les formats PCM contre ffmpeg
for sf in ["u8", "s16le", "s24le", "s32le", "f32le"]:
    d := dmx.open(M + "st_" + sf + ".wav")
    t.check(d.format.rate == 11025 and d.format.channels == 2 and d.format.sample_format == sf, "format " + sf + " : " + d.format.describe())
    ref := af.decode(io.read_bytes(M + "st_" + sf + ".f32"), af.AudioFormat(11025, 2, "f32le"))
    got := d.read_all()
    eps := 0.0001
    if sf == "u8":
        eps = 0.01
    t.check(d.frames == 2205 and len(got) == len(ref), sf + " : nombre d'échantillons " + str(len(got)) + " / " + str(len(ref)))
    t.samples_near(got, ref, eps, sf + " : échantillons identiques à ffmpeg")
    t.check(d.at_end() and d.read_packet().eos and d.read_frame().eos, sf + " : fin de flux")
    d.close()
    t.raises("StateError", () => d.read_packet(), sf + " : lecture après fermeture")

# ---------------------------------------------------------------- lecture par blocs et recherche
d := dmx.open(M + "st_s16le.wav")
ref := af.decode(io.read_bytes(M + "st_s16le.f32"), af.AudioFormat(11025, 2, "f32le"))
p := d.read_packet(1000)
t.check(p.size() == 4000 and p.pts.pts == 0 and p.duration == 1000 and p.pts.base.den == 11025, "paquet brut : " + p.describe())
f := d.read_frame(500)
t.check(f.frames() == 500 and ts.Timestamp(1000, ts.for_rate(11025)).equals(f.pts), "trame décodée et pts")
t.near(d.seek(0.1), 0.1, 0.0001, "recherche 0,1 s")
f2 := d.read_frame(10)
t.samples_near(f2.data, [ref[k] for k in 2 * 1103..2 * 1113], 0.0001, "données après recherche")
t.check(d.seek(99.0) == d.duration() and d.read_frame().eos, "recherche au-delà de la fin : bornée")
t.check(d.seek(-5.0) == 0.0, "recherche négative : début")
d.close()

# ---------------------------------------------------------------- sondage
i := probe.probe(M + "tags.wav")
t.check(i.container == "wav" and i.decodable() and i.first("audio").codec == "pcm_s16le", "sondage WAV")
t.near(i.duration, 0.25, 0.001, "durée WAV")
t.check(i.tags["title"] == "Essai" and i.tags["artist"] == "ALEX", "étiquettes LIST/INFO : " + str(i.tags))
fl := probe.probe(M + "tone.flac")
t.check(fl.container == "flac" and fl.first("audio").format.rate == 8000 and fl.first("audio").format.channels == 1, "FLAC : STREAMINFO")
t.near(fl.duration, 0.25, 0.001, "FLAC : durée")
t.check(fl.tags["title"] == "Essai" and fl.tags["album"] == "Tests" and fl.decodable(), "FLAC : commentaires, décodable")
for v in ["v23", "v24"]:
    m3 := probe.probe(M + "tone_" + v + ".mp3")
    t.check(m3.container == "mp3" and m3.tags["title"] == "Essai" and m3.tags["artist"] == "ALEX" and m3.tags["track"] == "3/12", "MP3 ID3 " + v + " : " + str(m3.tags))
t.check(probe.probe(M + "tone.ogg").container == "ogg", "Ogg reconnu")
t.check(probe.probe(M + "tone.m4a").container == "mp4", "MP4 / M4A reconnu")
t.check(probe.probe(M + "tone.mka").container == "matroska", "Matroska reconnu")
t.check(probe.probe(M + "tone.aiff").container == "aiff", "AIFF reconnu")
t.check(probe.probe(M + "tone.avi").container == "avi", "AVI reconnu")
t.check(len(probe.probe(M + "tone.ogg").warnings) >= 1, "Ogg Vorbis : avertissement sur le décodage")
im := probe.probe("tests/multimedia/fixtures/images/rgba8.png")
t.check(im.first("image").format.width == 13 and im.decodable() and im.mime == "image/png", "sondage PNG")
t.raises("UnsupportedError", () => dmx.open(M + "tone.ogg", null, "native_only").read_frame(), "Ogg Vorbis : ouvert, décodage non pris en charge")
t.raises("UnsupportedError", () => dmx.open(M + "mulaw.wav", null, "native_only"), "WAV mu-law : non simulé")
t.raises("LimitError", () => probe.probe(M + "st_f32le.wav", lim.Limits({"max_file_bytes": 1000})), "limite de taille")
t.raises("LimitError", () => probe.probe(M + "st_f32le.wav", lim.Limits({"max_duration": 0.1})), "limite de durée")
t.raises("MediaError", () => probe.probe(M + "absent.wav"), "fichier absent")
pm := probe.probe_many([M + "tags.wav", M + "absent.wav"])
t.check(pm[0][0] != null and pm[1][0] == null and pm[1][1] != null, "sondage d'un lot tolérant")

# ---------------------------------------------------------------- multiplexage
tmp := os.tmp_dir() + "/alex_mm_mux_" + str(os.pid()) + ".wav"
fmt := af.AudioFormat(8000, 2, "s24le")
tags := tg.Tags({"title": "Sortie", "artist": "ALEX", "track": "7"})
w := mux.WavMuxer(tmp, fmt, tags)
w.write_samples([0.5, -0.5, 0.25, -0.25])
w.write_frame(mb.audio_frame([0.1, 0.2, 0.3], af.AudioFormat(8000, 1, "f32le")))
t.raises("FormatError", () => w.write_samples([0.1]), "trame incomplète refusée")
t.check(w.close() == 5 and w.close() == 5, "fermeture idempotente")
t.raises("StateError", () => w.write_samples([0.0, 0.0]), "écriture après fermeture")
d2 := dmx.open(tmp)
t.check(d2.frames == 5 and d2.format.sample_format == "s24le" and len(d2.info.warnings) == 0, "relecture du WAV écrit")
t.samples_near(d2.read_all(), [0.5, -0.5, 0.25, -0.25, 0.1, 0.1, 0.2, 0.2, 0.3, 0.3], 0.0001, "échantillons relus (mono -> stéréo)")
t.check(d2.tags.get("title") == "Sortie" and d2.tags.get("track") == "7", "étiquettes écrites puis relues")
d2.close()
# contrôle croisé par ffprobe quand il est installé
rr := null
try:
    rr = os.run("ffprobe", ["-v", "error", "-show_entries", "format_tags=title", "-of", "csv=p=0", tmp])
catch e:
    rr = null
if rr != null and rr["code"] == 0:
    t.check(rr["stdout"] == "Sortie\n" or rr["stdout"] == "Sortie\r\n", "ffprobe relit le WAV écrit : " + rr["stdout"])
os.remove(tmp)
t.raises("UnsupportedError", () => mux.open("x.mp4", fmt), "multiplexage MP4 : non pris en charge")

# ---------------------------------------------------------------- métadonnées de conteneurs
info := cmeta.build_riff_info(tg.Tags({"title": "Ébauche", "comment": "ok"}))
back := cmeta.read_riff_info([info[k] for k in 8..len(info)])
t.check(back.get("title") == "Ébauche" and back.get("comment") == "ok", "LIST/INFO aller-retour (UTF-8)")
t.check(len(cmeta.build_riff_info(tg.Tags())) == 0, "pas de bloc INFO sans étiquette")
t.check(cmeta.read_id3v2([1, 2, 3]) == null, "pas d'ID3")

# ---------------------------------------------------------------- registre des codecs
f8 := af.AudioFormat(8000, 1, "s16le")
t.samples_near(reg.decoder("pcm_s16le")(reg.encoder("pcm_s16le")([0.5, -0.25], f8), f8), [0.5, -0.25], 0.0001, "codec PCM")
t.check(reg.can_decode("png") and reg.can_encode("bmp") and not reg.can_decode("h264"), "capacités déclarées")
t.raises("UnsupportedError", () => reg.decoder("h264"), "H.264 : explication au lieu d'une simulation")
t.raises("UnsupportedError", () => reg.decoder("inexistant"), "codec inconnu")
t.check(reg.find("aac")["licence"] != null, "note de licence")
reg.register("essai", "audio", (b, fm) => [0.0], null, "optionnel")
t.check(reg.can_decode("essai") and "essai" in caps.decodable("audio"), "dorsal optionnel branché")
reg.unregister("essai")
t.check(not reg.can_decode("essai"), "dorsal retiré")
t.check("h264" in caps.missing("video") and "png" in caps.decodable("image"), "tableau des capacités")

t.summary()
