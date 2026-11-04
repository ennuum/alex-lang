# multimedia.audio et effects : rééchantillonnage (précision, anti-repliement, continuité par blocs), sonie EBU R128
# comparée au filtre ebur128 de ffmpeg (tests/multimedia/fixtures/loudness), crête vraie, spatialisation, effets en
# continu (réponses des biquads, écho, compresseur, limiteur, porte), effets vidéo, transitions, montage.
from core use len, to_int, to_float
use io
use math
use string as _s
use audio.audio_format as af
use audio.audio_effects as afx
use multimedia.container.demux as dmx
use multimedia.audio.resampler as rsm
use multimedia.audio.meter as mt
use multimedia.audio.spatial as sp
use multimedia.audio.audio as mau
use multimedia.effects.audio_effect as ae
use multimedia.effects.video_effect as ve
use multimedia.effects.transitions as tr
use multimedia.effects.timeline as tl
use multimedia.image.image as mi
use multimedia.pipeline.node as nd
use multimedia.pipeline.scheduler as ps
use multimedia.core.buffer as mb
use multimedia.testing.assertions as ta

t := ta.Checker("multimedia audio avancé et effets")

func sine(f, n, rate, amp=0.5, phase=0.0):
    return [amp * math.sin(2 * math.PI * f * i / rate + phase) for i in 0..n]

# ---------------------------------------------------------------- rééchantillonnage
x := sine(1000, 4410, 44100)
y := rsm.resample(x, 44100, 48000, 1, "sinc", 32)
ref := sine(1000, 4800, 48000)
t.check(len(y) == 4800, "longueur exacte 44,1 -> 48 kHz : " + str(len(y)))
t.samples_near([y[k] for k in 100..4700], [ref[k] for k in 100..4700], 0.002, "sinus 1 kHz reconstruit (sinc 32)")
yl := rsm.resample(x, 44100, 48000, 1, "linear")
t.samples_near([yl[k] for k in 100..4700], [ref[k] for k in 100..4700], 0.01, "interpolation linéaire")
alias := rsm.resample(sine(15000, 4800, 48000), 48000, 16000, 1, "sinc", 64)
t.check(mt.peak([alias[k] for k in 100..1500]) < 0.01, "anti-repliement : 15 kHz supprimé en passant à 16 kHz (" + str(mt.peak([alias[k] for k in 100..1500])) + ")")
r := rsm.Resampler(44100, 48000, 2, "sinc", 16)
st := sine(440, 2000, 44100)
stereo := []
for v in st:
    stereo = stereo + [v, -v]
part := []
for k in 0..10:
    part = part + r.process([stereo[q] for q in 400 * k..400 * (k + 1)])
part = part + r.flush()
whole := rsm.Resampler(44100, 48000, 2, "sinc", 16)
w := whole.process(stereo) + whole.flush()
t.samples_near([part[k] for k in 0..4000], [w[k] for k in 0..4000], 1e-12, "par blocs = d'un coup (aucune discontinuité)")
t.check(r.up == 160 and r.down == 147, "rapport rationnel réduit 160/147")
t.raises("FormatError", () => rsm.Resampler(44100, 48000, 1, "sinc", 7), "taps impair refusé")

# ---------------------------------------------------------------- sonie (référence ffmpeg ebur128)
L := "tests/multimedia/fixtures/loudness/"
for f in ["sine1k_m23.wav", "music.wav", "pink.wav"]:
    txt := io.read_file(L + f + ".ebur128.txt")
    want_i := 0.0
    want_lra := 0.0
    for line in _s.split(txt, "\n"):
        p := _s.split(_s.trim(line), " ")
        if len(p) >= 2 and p[0] == "I:":
            want_i = to_float(p[1])
        if len(p) >= 2 and p[0] == "LRA:":
            want_lra = to_float(p[1])
    d := dmx.open(L + f)
    m := mt.LoudnessMeter(d.format.rate, d.format.channels)
    m.process(d.read_all())
    t.near(m.integrated(), want_i, 0.15, f + " : sonie intégrée (LUFS) contre ffmpeg")
    t.near(m.lra(), want_lra, 0.3, f + " : plage de sonie (LU) contre ffmpeg")
    t.check(m.momentary() > -1000 and m.short_term() > -1000, f + " : momentanée et court terme")
t.check(mt.loudness([0.0 for i in 0..48000], 48000, 1) == -1000.0, "silence : sous la porte absolue")
q := sine(12000, 4800, 48000, 0.5, math.PI / 4)
t.check(mt.true_peak(q, 48000) >= mt.peak(q), "crête vraie >= crête échantillon")
qq := [0.7 * math.sin(math.PI / 2 * i + math.PI / 4) for i in 0..4800]
tp := mt.true_peak(qq, 48000)
t.check(mt.peak(qq) < 0.5 and tp > 0.65, "crête inter-échantillons détectée (fs/4 à 45°) : " + str(mt.peak(qq)) + " -> " + str(tp))
t.near(mt.normalization_gain(ta_x(), 48000, 1, -23.0) + mt.loudness(ta_x(), 48000, 1), -23.0, 0.001, "gain de normalisation")
func ta_x():
    return sine(1000, 48000, 48000, 0.25)

# ---------------------------------------------------------------- spatialisation
for law in ["constant_power", "linear", "minus_4_5db"]:
    g := sp.pan_gains(-1.0, law)
    t.check(g[0] > 0.99 and g[1] < 0.01, law + " : tout à gauche")
c := sp.pan_gains(0.0)
t.near(c[0] * c[0] + c[1] * c[1], 1.0, 1e-9, "puissance constante au centre")
t.check(sp.width([0.5, 0.1], 0.0) == [0.3, 0.3], "largeur 0 : mono")
t.check(sp.balance([1.0, 1.0], 0.5) == [1.0, 1.0] or sp.balance([1.0, 1.0], 0.5) == [0.5, 1.0], "balance")
s3 := sp.Source3D(48000)
s3.set_position(1.0, 0.0, 0.0)
t.near(s3.itd(), 0.000656, 0.00002, "ITD à 90° (Woodworth) : " + str(s3.itd()))
out := s3.render([1.0] + [0.0 for i in 0..99])
first_l := -1
first_r := -1
for i in 0..100:
    if first_l < 0 and out[2 * i] != 0:
        first_l = i
    if first_r < 0 and out[2 * i + 1] != 0:
        first_r = i
t.check(first_r == 0 and first_l == 31 and out[1] > out[62], "son à droite : oreille gauche retardée de 31 échantillons et plus faible")
t.check(sp.distance_gain(2.0) == 0.5 and sp.distance_gain(200.0, "linear") == 0.0 and sp.distance_gain(4.0, "exponential", 1.0, 100.0, 1.0) == 0.25, "modèles de distance")

# ---------------------------------------------------------------- effets audio en continu
lp := ae.Biquad(48000, 1, "lowpass", 1000, 0.7071)
t.near(lp.response(1000, 48000), 0.7071, 0.002, "passe-bas : -3 dB à la coupure")
pk := ae.Biquad(48000, 1, "peaking", 2000, 1.0, 6.0)
t.near(mt.db(pk.response(2000, 48000)), 6.0, 0.01, "crête +6 dB au centre")
ls := ae.Biquad(48000, 1, "lowshelf", 200, 0.7071, -6.0)
t.near(mt.db(ls.response(20, 48000)), -6.0, 0.2, "plateau grave -6 dB")
t.near(mt.db(ls.response(10000, 48000)), 0.0, 0.1, "plateau grave neutre en aigu")
sig := sine(1000, 4800, 48000)
lp2 := ae.Biquad(48000, 1, "lowpass", 300)
blocks := []
for k in 0..12:
    blocks = blocks + lp2.process([sig[q] for q in 400 * k..400 * (k + 1)])
lp3 := ae.Biquad(48000, 1, "lowpass", 300)
t.samples_near(blocks, lp3.process(sig), 1e-12, "biquad par blocs = d'un coup")
dl := ae.Delay(1000, 1, 0.01, 0.5, 1.0)
e := dl.process([1.0] + [0.0 for i in 0..30])
t.check(e[10] == 1.0 and e[20] == 0.5 and e[0] == 0.0, "écho : retard 10 ms, rétroaction 0,5")
cmp_ := ae.Compressor(48000, 1, -20.0, 4.0, 0.001, 0.05, 0.0)
loud := cmp_.process(sine(1000, 48000, 48000, 0.9))
t.check(mt.peak([loud[k] for k in 40000..48000]) < 0.45, "compresseur : niveau réduit (" + str(mt.peak([loud[k] for k in 40000..48000])) + ")")
lim_ := ae.Limiter(48000, 2, -3.0)
lo := lim_.process([v * 3 for v in sine(500, 9600, 48000)])
t.check(mt.peak(lo) <= 0.7080 + 1e-9, "limiteur : plafond -3 dBFS respecté (" + str(mt.peak(lo)) + ")")
gate := ae.NoiseGate(48000, 1, -40.0, 0.001, 0.001)
gq := gate.process([0.001 for i in 0..4800])
t.check(mt.peak([gq[k] for k in 2000..4800]) < 0.0001, "porte de bruit : bruit faible coupé")
chain := ae.Chain([ae.Gain(-6.0206), ae.Gain(6.0206)])
t.samples_near(chain.process([0.3, -0.2]), [0.3, -0.2], 1e-9, "chaîne d'effets")
eq := ae.Equalizer(48000, 1, [["highpass", 100, 0.7071], ["peaking", 3000, 1.0, 3.0]])
t.check(len(eq.process(sig)) == len(sig), "égaliseur multi-bandes")
col := nd.collect("c")
src := nd.from_list("s", [mb.audio_frame([1.0, 1.0], af.AudioFormat(8000, 1, "f32le"))])
ps.run_chain([src, ae.effect_node("gain", ae.Gain(-6.0206)), col])
t.near(col.items[0].data[0], 0.5, 0.0001, "effet comme nœud de pipeline")

# ---------------------------------------------------------------- effets vidéo
flat := mi.new(12, 8, "rgb", [90, 120, 200])
t.check(ve.blur(flat, 3).equals(flat), "flou : image uniforme inchangée")
b := ve.blur(mi.checkerboard(8, 8, 1, null, null, "gray"), 1)
t.check(b.get(4, 4)[0] > 90 and b.get(4, 4)[0] < 170, "flou : damier moyenné")
t.check(ve.edge(flat).get(5, 5) == [0] and ve.edge(mi.checkerboard(8, 8, 4, null, null, "gray")).get(4, 2)[0] > 200, "contours de Sobel")
t.check(ve.sepia(mi.new(1, 1, "rgb", [100, 100, 100])).get(0, 0) == [135, 120, 93], "sépia")
px := ve.pixelate(mi.gradient(16, 16), 8)
t.check(px.get(0, 0) == px.get(7, 7) and px.get(0, 0) != px.get(8, 8), "pixellisation par blocs")
vg := ve.vignette(mi.new(9, 9, "rgb", [200, 200, 200]), 0.5)
t.check(vg.get(4, 4) == [200, 200, 200] and vg.get(0, 0)[0] == 100, "vignettage")
t.check(ve.sharpen(flat).equals(flat) and ve.overlay_text_box(flat).get(0, 7)[0] < 90, "netteté, bandeau de sous-titre")
t.check(ve.chain([ve.Effect((i) => ve.invert(i)), ve.Effect((i) => ve.invert(i))]).process(flat).equals(flat), "chaîne d'effets vidéo")

# ---------------------------------------------------------------- transitions
a := mi.new(4, 2, "rgb", [200, 0, 0])
bb := mi.new(4, 2, "rgb", [0, 0, 200])
t.check(tr.crossfade(a, bb, 0.0).equals(a) and tr.crossfade(a, bb, 1.0).equals(bb) and tr.crossfade(a, bb, 0.5).get(0, 0) == [100, 0, 100], "fondu enchaîné")
wp := tr.wipe(a, bb, 0.5)
t.check(wp.get(1, 0) == [0, 0, 200] and wp.get(2, 0) == [200, 0, 0], "volet à mi-course")
big1 := mi.new(40, 40, "gray", [0])
big2 := mi.new(40, 40, "gray", [255])
ds := tr.dissolve(big1, big2, 0.3)
cnt := 0
for v in ds.pixels:
    if v == 255:
        cnt += 1
t.check(cnt > 380 and cnt < 580, "fondu par points : ~30 % (" + str(cnt) + " / 1600)")
t.check(tr.slide(a, bb, 0.5).get(3, 0) == [0, 0, 200], "glissement")
t.check(tr.ease("ease_in_out", 0.5) == 0.5 and tr.ease("ease_in", 0.5) == 0.25 and tr.ease("smoothstep", 1.0) == 1.0, "courbes")
xf := tr.audio_crossfade([1.0 for i in 0..100], [1.0 for i in 0..100])
t.check(xf[50] > 1.40 and xf[50] < 1.42 and xf[0] > 0.99, "fondu audio à puissance constante")
t.raises("FormatError", () => tr.crossfade(a, mi.new(3, 3, "rgb"), 0.5), "tailles différentes refusées")

# ---------------------------------------------------------------- montage
f8 := af.AudioFormat(8000, 1, "f32le")
tm := tl.Timeline(8000, 1, 8, 4, 10)
tm.add_audio(tl.AudioClip([0.25 for i in 0..8000], f8, 0.0))
tm.add_audio(tl.AudioClip([0.5 for i in 0..4000], f8, 0.5, -6.0206))
mix := tm.render_audio()
t.check(len(mix) == 8000 and mix[1000] == 0.25 and mix[3999] == 0.25 and ta.near(mix[5000], 0.5, 0.0001) and ta.near(mix[7999], 0.5, 0.0001), "mixage de deux clips (second à 0,5 s, -6 dB)")
fd := tl.AudioClip([1.0 for i in 0..1600], f8, 0.0, 0.0, 0.05, 0.05)
fr2 := fd.rendered(8000, 1)
t.check(fr2[0] < 0.01 and fr2[800] == 1.0 and fr2[1599] < 0.01 and fr2[200] > 0.49 and fr2[200] < 0.51, "fondus de clip")
tm.add_video(tl.VideoClip(mi.new(8, 4, "rgb", [255, 0, 0]), 0.0, 1.0))
tm.add_video(tl.VideoClip(mi.new(8, 4, "rgb", [0, 255, 0]), 0.5, 0.5, "crossfade", 0.2))
t.check(tm.render_frame(0.2).get(0, 0) == [255, 0, 0] and tm.render_frame(0.6).get(0, 0) == [128, 128, 0] and tm.render_frame(0.9).get(0, 0) == [0, 255, 0], "image composée et transition")
t.check(len(tm.frame_times()) == 10 and tm.duration() == 1.0, "instants des images")
t.raises("FormatError", () => tl.AudioClip([0.0], f8, 0.0, 0.0, 0.0, 0.0, 1.0), "clip vide après rognage")

t.summary()
