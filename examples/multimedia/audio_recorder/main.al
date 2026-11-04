# Enregistreur : microphone (ou tonalité de test) -> WAV / FLAC... avec vumètre et arrêt sur silence.
#   alex run examples/multimedia/audio_recorder/main.al -- sortie.wav [secondes] [--test]
from core use len, to_float, to_int
use os
use audio.audio_format as af
use multimedia.recording.recorder as rec
use multimedia.recording.microphone as mic
use multimedia.testing.fake_device as fake

a := os.args()
dst := a[0] if len(a) > 0 else os.tmp_dir() + "/alex_enregistrement.wav"
secs := to_float(a[1]) if len(a) > 1 and a[1] != "--test" else 3.0
fmt := af.AudioFormat(48000, 1, "s16le")
src := null
if "--test" in a or not mic.available():
    print("source : tonalité de test (" + ("demandée" if "--test" in a else "pas de microphone : " + str(mic.diagnose()["advice"])) + ")")
    src = fake.FakeAudioInput(fmt, "sine", 440.0, secs)
else:
    src = mic.open(fmt)
r := rec.Recorder(src, fmt, dst)
n := [0]
r.on_level = (db) => _meter(db, n)
func _meter(db, n):
    n[0] += 1
    if n[0] % 20 == 0:
        bar := ""
        k := to_int((db + 60) / 3)
        for i in 0..(k if k > 0 else 0):
            bar = bar + "#"
        print(bar + " " + str(to_int(db)) + " dBFS")
st := r.record_until_silence(secs, -50.0, 2.0)
print(dst + " : " + str(st["duration"]) + " s, crête " + str(to_int(st["peak_db"])) + " dBFS (" + str(st["stopped_by"]) + ")")
