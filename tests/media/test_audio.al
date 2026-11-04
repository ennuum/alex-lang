# Paquet audio : formats et encodages, tampons, WAV progressif, générateurs, effets, filtres, mixeur,
# flux mémoire, commande des lecteurs ; lecture réelle par un faux lecteur (programme qui lit stdin).
from core use len, to_int
use os
use audio
use audio.audio_format as af
use audio.audio_stream as ast
use audio.audio_effects as fx
use audio.audio_mixer as am
use audio.audio_device as ad
use hardware.audio as haudio

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

func near(a, b, eps):
    d := a - b
    if d < 0:
        d = -d
    return d <= eps

f := af.AudioFormat(48000, 2, "s16le")
check(f.frame_bytes() == 4 and f.bytes_per_second() == 192000 and f.alsa_name() == "S16_LE", "format")
check(af.named("cd").rate == 44100 and af.VOICE.channels == 1, "formats nommés")
erreur := ""
try:
    af.AudioFormat(44100, 1, "s12")
catch e:
    erreur = e.type
check(erreur == "ArgumentError", "format inconnu")
for nom in af.FORMATS:
    g := af.AudioFormat(8000, 1, nom)
    x := af.decode(af.encode([0.5, -0.25, 0.0, 1.0, -1.0], g), g)
    check(len(x) == 5 and near(x[0], 0.5, 0.01) and near(x[1], -0.25, 0.01) and near(x[3], 1.0, 0.01) and near(x[4], -1.0, 0.01), "aller-retour " + nom + " : " + str(x))
check(af.encode([2.0], af.AudioFormat(8000, 1, "s16le")) == [255, 127], "écrêtage à l'encodage")
st := af.convert_channels([0.2, 0.4, 0.6, 0.8], 2, 1)
check(near(st[0], 0.3, 0.0001) and near(st[1], 0.7, 0.0001), "stéréo -> mono")
check(af.convert_channels([0.1, 0.2], 1, 2) == [0.1, 0.1, 0.2, 0.2], "mono -> stéréo")
r := af.resample([0.0, 1.0, 0.0, -1.0], 4, 8)
check(len(r) == 8 and near(r[1], 0.5, 0.0001), "rééchantillonnage")

la := fx.sine(440, 0.25, 8000)
check(len(la) == 2000 and near(fx.peak(la), 0.5, 0.01) and near(fx.rms(la), 0.3536, 0.01), "sinus : crête, efficace")
check(near(fx.estimate_pitch(la, 8000), 440.0, 4.0), "hauteur estimée : " + str(fx.estimate_pitch(la, 8000)))
check(near(fx.zero_crossings(la) / 0.25 / 2, 440.0, 8.0), "passages par zéro")
sq := fx.square(100, 0.1, 8000)
check(near(fx.peak(sq), 0.5, 0.0001) and near(fx.rms(sq), 0.5, 0.01), "carré")
n1 := fx.noise(0.01, 8000)
check(n1 == fx.noise(0.01, 8000) and n1 != fx.noise(0.01, 8000, 0.3, 7), "bruit reproductible")
env := fx.envelope([1.0 for i in 0..1000], 1000, 0.1, 0.1, 0.5, 0.2)
check(near(env[50], 0.5, 0.02) and near(env[300], 0.5, 0.001) and env[999] < 0.01, "ADSR")
check(near(fx.peak(fx.normalize(la, 0.9)), 0.9, 0.001), "normalisation")
check(near(fx.peak(fx.gain_db(la, -6.0206)), 0.25, 0.005), "gain en dB")
fi := fx.fade_in([1.0 for i in 0..100], 100, 0.5)
check(fi[0] == 0.0 and near(fi[25], 0.5, 0.03) and fi[99] == 1.0, "fondu d'entrée")
check(fx.reverse([1.0, 2.0, 3.0, 4.0], 2) == [3.0, 4.0, 1.0, 2.0], "inversion stéréo")
p := fx.pan([1.0], -1.0)
check(near(p[0], 1.0, 0.001) and near(p[1], 0.0, 0.001), "panoramique gauche")
haut := fx.sine(3000, 0.2, 8000)
bas := fx.sine(100, 0.2, 8000)
check(fx.rms(fx.lowpass(haut, 8000, 300)) < 0.05 and fx.rms(fx.lowpass(bas, 8000, 300)) > 0.3, "passe-bas")
check(fx.rms(fx.highpass(bas, 8000, 2000)) < 0.05, "passe-haut")
lim := fx.limiter([2.0, -3.0, 0.5], 0.9)
check(fx.peak(lim) <= 1.0 and lim[2] == 0.5 and lim[1] < -0.9, "limiteur")
comp := fx.compressor(fx.sine(200, 0.3, 8000, 0.9), 8000, -12.0, 8.0, 0.001, 0.05)
stable := [comp[i] for i in 800..2400]
check(fx.peak(stable) < 0.6, "compresseur : " + str(fx.peak(stable)))
ec := fx.echo([1.0, 0.0, 0.0, 0.0, 0.0], 2, 1.0, 0.5, 1.0)
check(near(ec[2], 0.5, 0.0001) and near(ec[4], 0.25, 0.0001), "écho")
rv := fx.reverb(fx.sine(300, 0.1, 8000), 8000, 0.5, 0.3)
check(len(rv) == 800 and fx.peak(rv) > 0.0, "réverbération")
check(len(fx.speed(la, 2.0)) == 1000, "vitesse x2")

# tampons et WAV
b := ast.AudioBuffer(fx.pan(la, 0.0), af.AudioFormat(8000, 2, "s16le"))
check(b.frames() == 2000 and near(b.duration(), 0.25, 0.0001) and len(b.channel(1)) == 2000, "tampon stéréo")
check(b.slice(0.1, 0.2).frames() == 800, "extrait")
c := b.convert(af.AudioFormat(16000, 1, "s16le"))
check(c.frames() == 4000 and c.format.channels == 1, "conversion de format")
chemin := os.tmp_dir() + "/alex_audio_" + str(os.pid()) + ".wav"
w := ast.WavWriter(chemin, af.AudioFormat(8000, 1, "s16le"))
w.write(la)
w.write(la)
w.close()
lu := ast.load_wav(chemin)
check(lu.frames() == 4000 and lu.format.rate == 8000 and near(lu.samples[100], la[100], 0.001), "WAV progressif relu")
rd := ast.WavReader(chemin)
check(len(rd.read(1500)) == 1500 and len(rd.read(5000)) == 2500 and len(rd.read(10)) == 0, "lecture par morceaux")
os.remove(chemin)
check(near(audio.pitch(audio.tone(220, 0.3, 8000)), 220.0, 3.0), "audio.pitch")

# mixeur
m := am.Mixer(af.AudioFormat(8000, 2, "s16le"))
t1 := m.add("a", [0.5 for i in 0..800])
t2 := m.add("b", [0.25 for i in 0..400], 1.0, 1.0)
t2.start = 0.05
out := m.render()
check(out.frames() == 800 and near(m.duration(), 0.1, 0.0001), "durée du mélange")
check(near(out.samples[0], 0.5, 0.01) and near(out.samples[1], 0.5, 0.01), "piste centrée")
check(near(out.samples[2 * 500 + 1], 0.5 + 0.25 * 1.4142, 0.02) and near(out.samples[2 * 500], 0.5, 0.01), "piste à droite entrée à 50 ms")
t2.solo = true
check(near(m.render().samples[0], 0.0, 0.0001), "solo")
t2.solo = false
t1.muted = true
blocs := 0
m.rewind()
while len(m.render_block(256)) > 0:
    blocs += 1
check(blocs == 4, "rendu par blocs : " + str(blocs))
mem := ast.MemorySink(m.format)
m.play_to(mem, 300)
check(mem.frames_written == 900 and mem.closed == false, "lecture vers un flux")

# lecteurs : commande construite, puis vraie lecture en continu vers tests/media/pipe_tool.al (faux lecteur)
cmd := ast.player_command(af.CD, "plughw:0,0", "aplay")
check(cmd[0] == "aplay" and cmd[1][4] == "S16_LE" and cmd[1][9] == "-D", "commande aplay")
check(ast.capture_command(af.VOICE, null, "ffmpeg")[1][4] == "-i", "commande ffmpeg")
sortie := os.tmp_dir() + "/alex_pcm_" + str(os.pid())
outil := ["run", "tests/media/pipe_tool.al", "--"]
ps := ast.PlayerStream(af.AudioFormat(8000, 1, "s16le"), null, [os.executable(), outil + ["sink", sortie]])
ps.write(la)
ps.close()
check(os.size(sortie) == 4000, "flux PCM brut vers le lecteur : " + str(os.size(sortie)))
cs := ast.CaptureStream(af.AudioFormat(8000, 1, "s16le"), null, [os.executable(), outil + ["source", sortie]])
lus := cs.read(1500)
reste := cs.read(5000)
check(len(lus) == 1500 and len(reste) == 500 and near(lus[10], la[10], 0.001), "capture depuis un outil")
cs.close()
os.remove(sortie)
check(len(ad.devices()) >= 0 and ad.default_output().is_default(), "périphériques")
# vraie sortie (ALEX_MEDIA_REAL=1 : un bip court et doux) : lecture en continu par le lecteur du système
if os.getenv("ALEX_MEDIA_REAL", "") == "1" and ast.player_command(af.CD) != null and ad.player_available():
    print("sortie réelle : " + ast.player_command(af.CD)[0])
    sortie_reelle := ast.open_output(af.AudioFormat(44100, 1, "s16le"))
    sortie_reelle.write(haudio.tone(660, 0.3, 44100, 0.08))
    sortie_reelle.close()
    check(sortie_reelle.frames_written == 13230 and sortie_reelle.closed, "lecture réelle (0,3 s)")
print("audio : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")
