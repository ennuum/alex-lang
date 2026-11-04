# multimedia : adaptateur système ffmpeg (sondage, décodage MP3 / AAC / Opus / Vorbis, encodages vérifiés par le
# décodeur FLAC ALEX, vidéo), absence simulée de ffmpeg, registre « système », repli de demux.open ; plateformes,
# dorsaux audio / vidéo / GPU, journal, analyse dans un processus isolé, outils alex-media.
from core use len, to_int
from collections use append
use io
use os
use string as _s
use audio.audio_format as af
use audio.audio_effects as afx
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.backends.audio.system as asys
use multimedia.backends.video.system as vsys
use multimedia.backends.gpu.gpu as mgpu
use multimedia.container.demux as dmx
use multimedia.container.probe as probe
use multimedia.codec.registry as reg
use multimedia.codec.audio.flac as flac
use multimedia.platform.platform as plat
use multimedia.platform.android as android
use multimedia.platform.alex_os as alexos
use hardware._windows as win
use multimedia.diagnostics.logging as mlog
use multimedia.diagnostics.capabilities as dcaps
use multimedia.security.sandbox as msb
use multimedia.image.image as mi
use multimedia.testing.fixtures as fx
use multimedia.testing.assertions as ta
use multimedia

t := ta.Checker("multimedia système")
M := "tests/multimedia/fixtures/media/"

if ff.available():
    # ---------------------------------------------------------------- sondage et décodage
    for f in [["tone_v24.mp3", "mp3", "mp3"], ["tone.m4a", "mp4", "aac"], ["tone.mka", "matroska", "opus"], ["tone.aiff", "aiff", "pcm_s16be"], ["tone.avi", "avi", "pcm_s16le"]]:
        i := probe.probe(M + f[0])
        t.check(i.container == f[1] and i.first("audio").codec == f[2] and i.decodable(), f[0] + " : " + i.container + " / " + i.first("audio").codec)
        d := dmx.open(M + f[0])
        x := d.read_all()
        dur := 1.0 * len(x) / d.format.channels / d.format.rate
        t.check(dur > 0.23 and dur < 0.33 and afx.peak(x) > 0.05, f[0] + " : décodé par ffmpeg (" + str(dur) + " s)")
        d.close()
    vo := dmx.open("tests/multimedia/fixtures/ogg/vorbis.ogg")
    t.check(vo.format.rate == 44100 and len(vo.read_all()) > 2 * 60000, "Ogg Vorbis : décodage par repli système")
    t.raises("UnsupportedError", () => dmx.open(M + "tone.m4a", null, "native_only"), "native_only : pas de repli")
    d2 := dmx.open(M + "tone.m4a")
    d2.seek(0.1)
    t.check(d2.read_frame(10).pts.pts == 800, "recherche par ffmpeg")
    d2.close()
    # ---------------------------------------------------------------- encodage : FLAC relu par ALEX
    sig := afx.sine(440, 0.5, 16000)
    pf := fx.temp_path("enc.flac")
    e := ff.AudioEncoder(pf, af.AudioFormat(16000, 1, "f32le"), null, null, null, "s16le")
    e.write(sig)
    e.close()
    dec := flac.decode(io.read_bytes(pf))
    t.check(dec["md5_checked"] and dec["info"]["bits"] == 16 and len(dec["channels"][0]) == 8000, "FLAC écrit par ffmpeg, relu par le décodeur ALEX (MD5)")
    mx := 0
    for k in 0..8000:
        dd := dec["channels"][0][k] - to_int(sig[k] * 32767.0)
        if dd < 0:
            dd = -dd
        if dd > mx:
            mx = dd
    t.check(mx <= 1, "échantillons à 1 près (arrondi de ffmpeg) : " + str(mx))
    for ext in [".opus", ".mp3", ".ogg", ".m4a"]:
        pe := fx.temp_path("enc" + ext)
        en := ff.AudioEncoder(pe, af.AudioFormat(16000, 1, "f32le"))
        en.write(sig)
        en.close()
        back := dmx.open(pe).read_all()
        t.check(len(back) > 0 and afx.peak(back) > 0.3 and afx.peak(back) < 0.7, ext + " : aller-retour avec perte, niveau conservé (" + str(afx.peak(back)) + ")")
    # ---------------------------------------------------------------- vidéo
    pv := fx.temp_path("v.mp4")
    ve := ff.VideoEncoder(pv, 32, 24, 10)
    for k in 0..10:
        ve.write(mi.new(32, 24, "rgb", [k * 25, 100, 200 - k * 20]))
    ve.close()
    vd := ff.VideoDecoder(pv)
    frames := []
    while true:
        im := vd.read()
        if im == null:
            break
        append(frames, im)
    t.check(len(frames) == 10 and frames[9].meta["pts"] == 0.9, "vidéo H.264 : 10 images relues")
    c5 := frames[5].get(16, 12)
    t.check(c5[0] > 110 and c5[0] < 140 and c5[2] > 85 and c5[2] < 115, "couleur conservée à la compression près : " + str(c5))
    t.check(len(ff.encoders()) > 10 and ff.has_encoder("flac"), "encodeurs de ce ffmpeg")
    # ---------------------------------------------------------------- registre
    n := ff.install()
    t.check(n > 10 and reg.can_decode("h264") and reg.find("h264")["origin"] == "système" and reg.find("flac")["origin"] == "intégré", "codecs système déclarés (" + str(n) + "), FLAC reste intégré")
    t.check(reg.find("aac")["licence"] != null, "note de licence conservée")
    # ---------------------------------------------------------------- absence simulée
    ff.set_tools(null, null)
    t.check(not ff.available(), "ffmpeg masqué")
    t.raises("UnsupportedError", () => ff.probe(M + "tone.m4a"), "sans ffmpeg : explication")
    t.raises("UnsupportedError", () => dmx.open(M + "tone.m4a"), "sans ffmpeg : MP4 non pris en charge")
    i2 := probe.probe(M + "tone.m4a")
    t.check(i2.container == "mp4" and not i2.decodable() and len(i2.warnings) == 1, "sans ffmpeg : MP4 reconnu, non décodable")
    ff.reset()
    t.check(ff.available(), "ffmpeg retrouvé")
else:
    print("(ffmpeg absent : tests de l'adaptateur système ignorés)")
    t.raises("UnsupportedError", () => ff.require(), "ffmpeg absent : erreur explicite")

# ---------------------------------------------------------------- plateformes et dorsaux
# liste DirectShow de ffmpeg (Windows) : format récent (« (video) ») et ancien (sections), noms internes
nouveau := "[in#0 @ 0000] \"HP HD Camera\" (video)\n[in#0 @ 0000]   Alternative name \"@device_pnp_\\\\?\\usb#vid_30c9\"\n[in#0 @ 0000] \"Réseau de microphones (Intel® Smart Sound)\" (audio)\n[in#0 @ 0000]   Alternative name \"@device_cm_{33D9}\\wave_{3645}\"\n[in#0 @ 0000] \"OBS Virtual\" (none)\ndummy: Immediate exit requested\n"
ds := win.parse_dshow(nouveau)
t.check(len(ds) == 2 and ds[0]["kind"] == "video" and ds[0]["name"] == "HP HD Camera" and ds[1]["kind"] == "audio" and ds[1]["alt"] == "@device_cm_{33D9}\\wave_{3645}", "DirectShow : liste ffmpeg récente")
t.check(win.source(ds[1]) == "audio=@device_cm_{33D9}\\wave_{3645}" and win.input_args(ds[0]) == ["-f", "dshow", "-i", "video=@device_pnp_\\\\?\\usb#vid_30c9"], "DirectShow : arguments ffmpeg")
ancien := "[dshow @ 01] DirectShow video devices\n[dshow @ 01]  \"USB2.0 Camera\"\n[dshow @ 01] DirectShow audio devices\n[dshow @ 01]  \"Microphone (Realtek)\"\n"
da := win.parse_dshow(ancien)
t.check(len(da) == 2 and da[0]["kind"] == "video" and da[1]["kind"] == "audio" and win.source(da[1]) == "audio=Microphone (Realtek)", "DirectShow : liste ffmpeg ancienne")
t.check(plat.current() == os.platform(), "plateforme courante : " + plat.current())
m := plat.matrix()
t.check("linux" in m and "android" in m and "ios" in m and m["linux"]["pure_alex"] == "validé", "matrice de compatibilité")
t.raises("UnsupportedError", () => android.require_backend("AAudio"), "Android : dorsal absent déclaré")
t.raises("UnsupportedError", () => alexos.require_backend("son"), "ALEX OS : dorsal absent déclaré")
t.check(plat.report()["platform"] == plat.current() and "support" in plat.report(), "rapport de plateforme")
t.check("can_play" in asys.describe() and "ffmpeg" in vsys.describe() and "hwaccels" in mgpu.describe(), "dorsaux audio, vidéo, GPU")
if not asys.can_record():
    t.raises("DeviceError", () => asys.open_input(), "pas d'entrée audio : erreur expliquée")
hw := mgpu.hwaccels()
if len(hw) > 0:
    t.check(mgpu.decode_args(hw[0]) == ["-hwaccel", hw[0]], "options d'accélération")
t.raises("UnsupportedError", () => mgpu.decode_args("inexistant"), "accélération absente")
c := dcaps.detect()
t.check("flac" in c["containers"]["read"] and "ogg" in c["containers"]["read"] and "flac" in c["codecs"]["decode"], "capacités : FLAC et Ogg natifs")

# ---------------------------------------------------------------- journal
lines := []
j := mlog.MediaLog("info", 3, () => 0.0)
j.sink = (l) => append(lines, l)
j.debug("x", "ignoré")
j.info("player", "lecture", {"fichier": "a.flac"})
j.warning("demux", "tronqué")
j.error("demux", "échec")
j.info("player", "fin")
t.check(j.count("debug") == 0 and j.count("info") == 2 and len(j.entries) == 3 and lines[0] == "INFO [player] lecture fichier=a.flac", "journal : niveaux, capacité, format")
j.log_warnings("probe", probe.probe("tests/multimedia/fixtures/ogg/vorbis.ogg", null))
t.check(j.count("warning") >= 2, "avertissements d'un sondage journalisés")

# ---------------------------------------------------------------- processus isolé
r := msb.isolated_probe("tests/multimedia/fixtures/flac/mono16.flac")
# Windows : pas de limite mémoire du noyau (ulimit) ; enforced doit le dire au lieu de le prétendre.
t.check(r["ok"] and r["info"]["container"] == "flac" and r["enforced"]["memory"] == (os.platform() != "windows"), "sondage isolé : " + str(r["ok"]))
bad := fx.temp_path("bad.png")
img := fx.hostile_images()[0]
io.write_bytes(bad, img[1])
rc := msb.isolated_check(bad)
t.check(not rc["ok"] and rc["error_type"] == "CorruptDataError", "fichier hostile analysé à part : " + str(rc["error_type"]))
rg := msb.isolated_check("tests/multimedia/fixtures/images/rgba8.png")
t.check(rg["ok"] and rg["summary"]["width"] == 13 and len(rg["summary"]["md5"]) == 32, "image valide vérifiée à part")
t.raises("MediaError", () => msb.isolated_probe("absent.wav"), "fichier absent")

# ---------------------------------------------------------------- outils alex-media
exe := os.executable()
if exe == null:
    exe = "./alex"
pr := os.run(exe, ["run", "tools/alex-media/alex-media.al", "--", "probe", "--json", "tests/multimedia/fixtures/flac/st24.flac"])
t.check(pr["code"] == 0 and _s.contains(pr["stdout"], "\"container\":\"flac\""), "alex-media probe --json")
out := fx.temp_path("conv.wav")
cv := os.run(exe, ["run", "tools/alex-media/alex-media.al", "--", "convert", "tests/multimedia/fixtures/flac/mono16.flac", out, "--rate", "16000"])
t.check(cv["code"] == 0 and dmx.open(out).frames == 6400, "alex-media convert (FLAC 8 kHz -> WAV 16 kHz)")
rcd := fx.temp_path("rec.wav")
rr := os.run(exe, ["run", "tools/alex-media/alex-media.al", "--", "record", rcd, "--seconds", "0.5", "--rate", "8000", "--test-tone"])
t.check(rr["code"] == 0 and dmx.open(rcd).frames == 4000, "alex-media record --test-tone")
bm := os.run(exe, ["run", "tools/alex-media/alex-media.al", "--", "benchmark", "--tsv", "--quick"])
t.check(bm["code"] == 0 and len(_s.split(_s.trim(bm["stdout"]), "\n")) >= 6, "alex-media benchmark")
t.check(_s.contains(multimedia.capabilities(), "flac"), "façade : capacités")

fx.cleanup()
t.summary()
