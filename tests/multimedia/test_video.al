# multimedia.video : images horodatées, mise à l'échelle, couleur (comparée à ffmpeg), composition, cadence,
# capture (factice, mire, fichier), lecteur vidéo synchronisé.
from core use len, to_int
from collections use append
use io
use audio.audio_format as af
use multimedia.image.image as mi
use multimedia.video.frame as vfr
use multimedia.video.scaler as vs
use multimedia.video.color as vc
use multimedia.video.compositor as comp
use multimedia.video.frame_rate as fr
use multimedia.video.capture as vcap
use multimedia.video.playback as vp
use multimedia.video.video_format as vfmt
use multimedia.pipeline.clock as pc
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.testing.fake_device as fake
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia vidéo")
V := "tests/multimedia/fixtures/video/"

# ---------------------------------------------------------------- VideoFrame
img := mi.gradient(16, 8)
f := vfr.VideoFrame(img, 1.25, 0.04, 31)
t.check(f.end() == 1.29 and f.width() == 16 and vfr.is_frame(f) and not vfr.is_frame(img), "VideoFrame")
t.check(f.to_pipeline().kind == "video" and f.to_pipeline().pts.pts == 1250000, "vers une Frame de pipeline")
t.check(vfmt.with_rate(64, 48, "29.97").describe() == "64x48 yuv420p 29.97 i/s", "cadences nommées")

# ---------------------------------------------------------------- mise à l'échelle
s := vs.Scaler(320, 180, "fit")
t.check(s.geometry(1920, 1080) == {"x": 0, "y": 0, "w": 320, "h": 180} and s.geometry(1000, 1000) == {"x": 70, "y": 0, "w": 180, "h": 180}, "géométrie letterbox / pillarbox")
sq := vs.Scaler(8, 4, "fit", [9, 9, 9]).apply(mi.new(4, 4, "rgb", [200, 0, 0]))
t.check(sq.get(0, 0) == [9, 9, 9] and sq.get(4, 2) == [200, 0, 0] and sq.get(7, 0) == [9, 9, 9], "bandes de fond")
t.check(vs.Scaler(8, 4, "fill").apply(f).image.describe() == "8x4 rgb" and vs.Scaler(5, 5, "stretch").apply(img).describe() == "5x5 rgb", "fill / stretch, VideoFrame conservé")

# ---------------------------------------------------------------- couleur
for m in ["bt601", "bt709"]:
    for rng in ["limited", "full"]:
        worst := 0
        for c in [[0, 0, 0], [255, 255, 255], [200, 30, 60], [12, 240, 99], [128, 128, 128]]:
            y := vc.rgb_to_ycbcr(c[0], c[1], c[2], m, rng)
            back := vc.ycbcr_to_rgb(y[0], y[1], y[2], m, rng)
            for k in 0..3:
                d := back[k] - c[k]
                if d < 0:
                    d = -d
                if d > worst:
                    worst = d
        t.check(worst <= 3, "aller-retour " + m + " " + rng + " (écart " + str(worst) + ")")
t.check(vc.rgb_to_ycbcr(255, 255, 255) == [235, 128, 128] and vc.rgb_to_ycbcr(0, 0, 0) == [16, 128, 128], "plage limitée 16..235")
for pf in ["yuv420p", "nv12", "yuyv422"]:
    got := vc.from_planes(pf, io.read_bytes(V + "frame." + pf), 64, 48)
    want := io.read_bytes(V + "frame." + pf + ".rgb")
    worst := 0
    for y in 0..48:
        for x in 0..64:
            if x % 16 < 2 or x % 16 > 13 or y % 16 < 2 or y % 16 > 13:
                continue                     # bords des aplats : interpolation de chrominance différente
            k := (y * 64 + x) * 3
            for c in 0..3:
                d := got.pixels[k + c] - want[k + c]
                if d < 0:
                    d = -d
                if d > worst:
                    worst = d
    t.check(worst <= 4, pf + " -> rgb comparé à ffmpeg (intérieur des aplats ; swscale arrondit en virgule fixe rapide) : écart max " + str(worst))
pl := vc.to_yuv420p(mi.new(4, 2, "rgb", [255, 255, 255]))
t.check(len(pl) == 12 and pl[0] == 235 and pl[8] == 128, "rgb -> plans yuv420p")
adj := vc.adjust(mi.new(1, 1, "rgb", [100, 150, 200]), 10, 1.0, 0.0)
t.check(adj.get(0, 0)[0] == adj.get(0, 0)[1] and adj.get(0, 0)[1] == adj.get(0, 0)[2], "saturation 0 : gris")
t.check(vc.adjust(mi.new(1, 1, "gray", [64]), 0, 1.0, 1.0, 2.0).get(0, 0)[0] == 128, "gamma 2 : 64 -> 128")
t.raises("FormatError", () => vc.rgb_to_ycbcr(1, 2, 3, "bt2020"), "matrice inconnue")

# ---------------------------------------------------------------- composition
c := comp.Compositor(10, 10, [0, 0, 0])
c.add("fond", mi.new(10, 10, "rgb", [100, 100, 100]))
c.add("calque", mi.new(2, 2, "rgb", [200, 0, 0]), 4, 4, 0.5)
r := c.render()
t.check(r.get(0, 0) == [100, 100, 100] and r.get(4, 4) == [150, 50, 50], "calque à 50 % : " + str(r.get(4, 4)))
c.show("calque", false)
t.check(c.render().get(4, 4) == [100, 100, 100], "calque masqué")
c.show("calque", true)
c.pip("calque", "haut-gauche", 0.4, 1)
t.check(c.render().get(1, 1) == [150, 50, 50] and c.layer("calque").size == [4, 4], "vignette placée")
t.raises("FormatError", () => c.update("absent", img), "calque inconnu")

# ---------------------------------------------------------------- cadence
src := [vfr.VideoFrame(mi.new(2, 2, "gray", [k]), k / 30.0, 1.0 / 30, k) for k in 0..30]
conv := fr.FrameRateConverter(25)
out := []
for x in src:
    out = out + conv.push(x)
out = out + conv.flush(1.0)
t.check(len(out) == 25 and out[24].pts == 0.96 and conv.dropped == 5, "30 -> 25 i/s : 25 images, 5 jetées")
conv2 := fr.FrameRateConverter(60)
o2 := []
for x in src:
    o2 = o2 + conv2.push(x)
o2 = o2 + conv2.flush(1.0)
t.check(len(o2) == 60 and conv2.duplicated == 30, "30 -> 60 i/s : chaque image doublée")
t.check(fr.named("29.97") == [30000, 1001], "cadence nommée")
meter := fr.FpsMeter(30, 25)
for k in 0..20:
    if k != 7:
        meter.tick(k / 25.0)
t.check(meter.dropped == 1 and meter.fps() > 23.0 and meter.fps() < 26.0 and meter.jitter() > 0.0, "mesure de cadence, image manquante, gigue")

# ---------------------------------------------------------------- capture
cf := vcap.VideoCapture("fake", 16, 8, 25, null, 5)
fs := cf.frames()
t.check(len(fs) == 5 and fs[4].pts == 0.16 and fs[0].image.width == 16, "capture factice")
if ff.available():
    cp := vcap.VideoCapture("pattern", 32, 24, 10, null, 4)
    pf := cp.frames()
    t.check(len(pf) == 4 and pf[3].pts == 0.3 and pf[0].image.describe() == "32x24 rgb", "mire ffmpeg")
    cp.close()
    fl := vcap.VideoCapture("file", 32, 24, 10, "tests/multimedia/fixtures/ogg/theora.ogv")
    t.check(len(fl.frames()) == 10, "images d'un fichier vidéo")
    # ---------------------------------------------------------------- lecteur
    got := []
    out_a := fake.FakeAudioOutput(af.AudioFormat(22050, 2, "f32le"))
    p := vp.VideoPlayer((fr_) => append(got, fr_), out_a, vs.Scaler(32, 24), false)
    info := p.open("tests/multimedia/fixtures/ogg/theora.ogv")
    p.play()
    p.run()
    st := p.stats()
    t.check(p.state() == "ended" and st["presented_total"] == 10 and st["dropped"] == 0 and got[0].image.describe() == "32x24 rgb", "lecture vidéo complète, mise à l'échelle (" + str(st) + ")")
    t.check(out_a.frames() > 20000 and st["max_drift"] < 0.05, "son joué, dérive < 50 ms")
    p.seek(0.5)
    p.play()
    p.run()
    t.check(p.stats()["presented_total"] == 15, "recherche puis lecture de la fin")
    p.close()
    base := pc.ManualClock()
    p2 := vp.VideoPlayer((x) => base.advance(0.0), null, null, true, base)
    p2.open("tests/multimedia/fixtures/ogg/theora.ogv")
    p2.play()
    p2.run(null, 4)
    t.check(p2.presented + p2.sync.dropped >= 1, "temps réel sans son (horloge injectée)")
    p2.close()
else:
    print("(adaptateur ffmpeg absent : tests de mire, fichier et lecteur vidéo ignorés)")

t.summary()
