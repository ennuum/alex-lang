# Paquet microphone : entrée par blocs (gain, porte, niveaux, rappels async), enregistreur (durée, silence,
# WAV), segments de parole ; la « capture » vient d'une source mémoire puis d'un outil (tests/media/pipe_tool.al
# relit un PCM brut) ; avec ALEX_MEDIA_REAL=1, enregistrement sur le vrai microphone.
from core use len, to_int
from collections use append
use os
use asyncio
use audio.audio_format as af
use audio.audio_stream as ast
use audio.audio_effects as fx
use microphone
use microphone.audio_input as ai
use microphone.capture as cap
use microphone.microphone_info as mi
use hardware.microphone as hmic

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

f := af.AudioFormat(8000, 1, "s16le")
# 0,5 s de silence, 1 s de « voix » (sinus), 1 s de silence, 0,3 s de voix, 0,5 s de silence
signal := fx.concat([fx.silence(0.5, 8000), fx.sine(300, 1.0, 8000, 0.4), fx.silence(1.0, 8000), fx.sine(500, 0.3, 8000, 0.4), fx.silence(0.5, 8000)])
entree := ai.AudioInput(f, null, ast.MemorySource(signal, f))
check(entree.block_frames == 800, "bloc de 0,1 s")
b := entree.read()
check(len(b) == 800 and entree.level_db() < -100, "silence")
entree.read(4000)
entree.read(800)
check(near(entree.level_db(), -10.97, 0.5), "niveau du sinus : " + str(entree.level_db()))
entree.set_gain_db(6.0)
b = entree.read(800)
check(near(fx.peak(b), 0.8, 0.02), "gain +6 dB")
entree.gate_db = 0.0
check(fx.peak(entree.read(800)) == 0.0, "porte de bruit")

# boucle asynchrone avec rappels
e2 := ai.AudioInput(f, null, ast.MemorySource(signal, f))
vus := []
e2.on_block((bloc) => append(vus, len(bloc)))
total := await e2.run(1.0)
check(total == 8000 and len(vus) == 10, "run(1 s) : " + str(total) + " trames, " + str(len(vus)) + " blocs")

# enregistreur
r := cap.Recorder(f, null, ast.MemorySource(signal, f))
b1 := r.record(1.25)
check(b1.frames() == 10000, "durée fixe")
r2 := cap.Recorder(f, null, ast.MemorySource(signal, f))
b2 := r2.record_until_silence(10.0, 0.5)
check(near(b2.duration(), 1.5, 0.11), "jusqu'au silence : " + str(b2.duration()))
check(r2.speech_started, "parole détectée")
segs := cap.split_on_silence(ast.AudioBuffer(signal, f))
check(len(segs) == 2 and near(segs[0][0], 0.5, 0.03) and near(segs[0][1], 1.5, 0.03) and near(segs[1][0], 2.5, 0.03), "segments : " + str(segs))
chemin := os.tmp_dir() + "/alex_mic_" + str(os.pid()) + ".wav"
r3 := cap.Recorder(f, null, ast.MemorySource(signal, f))
check(r3.record_to_wav(chemin, 2.0) == 16000, "vers WAV")
check(ast.load_wav(chemin).frames() == 16000, "WAV relu")
os.remove(chemin)

# capture par un outil : un PCM brut relu par tests/media/pipe_tool.al (portable, Windows compris)
brut := os.tmp_dir() + "/alex_mic_raw_" + str(os.pid())
outil := ["run", "tests/media/pipe_tool.al", "--"]
ps := ast.PlayerStream(f, null, [os.executable(), outil + ["sink", brut]])
ps.write(signal)
ps.close()
r4 := cap.Recorder(f, null, ast.CaptureStream(f, null, [os.executable(), outil + ["source", brut]]))
b4 := r4.record(3.3)
check(b4.frames() == 26400 and near(microphone.level(b4), -14.0, 2.0), "capture par un outil : " + str(microphone.level(b4)))
r4.close()
os.remove(brut)
check(len(mi.microphones()) >= 0 and mi.default().is_default(), "inventaire")
# vrai microphone (ALEX_MEDIA_REAL=1) : 1 s par l'outil du système (Windows : ffmpeg DirectShow)
if os.getenv("ALEX_MEDIA_REAL", "") == "1" and hmic.available():
    print("microphone réel : " + hmic.microphones()[0].name)
    vrai := os.tmp_dir() + "/alex_mic_real_" + str(os.pid()) + ".wav"
    hmic.record(vrai, 1.0)
    w := ast.load_wav(vrai)
    check(w.format.rate == 16000 and w.frames() >= 15900 and w.frames() <= 16100, "enregistrement réel : " + w.describe())
    vi := ast.CaptureStream(af.VOICE)
    lus := vi.read(8000)
    vi.close()
    check(len(lus) == 8000, "capture réelle en continu : " + str(len(lus)))
    os.remove(vrai)
print("microphone : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")
