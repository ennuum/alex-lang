# Lecteur audio en ligne de commande : WAV, FLAC, Ogg FLAC en ALEX ; MP3, Opus, AAC... par ffmpeg.
#   alex run examples/multimedia/audio_player/main.al -- fichier [volume] [--muet]
#   --muet : sortie factice (machine sans carte son) ; la lecture et la progression sont les mêmes.
from core use len, to_float, to_int
use os
use audio.audio_format as af
use multimedia.playback.player as mp
use multimedia.testing.fake_device as fake

a := os.args()
path := a[0] if len(a) > 0 else "tests/multimedia/fixtures/flac/mono16.flac"
vol := 1.0
for x in a:
    if x != path and x != "--muet":
        vol = to_float(x)
out := null
if "--muet" in a:
    out = fake.FakeAudioOutput(af.AudioFormat(48000, 2, "f32le"))
p := mp.Player(out, null, 4096, (fmt) => fake.FakeAudioOutput(fmt) if "--muet" in a else null)
info := p.open(path)
print(path + " : " + info.describe())
last := [-1]
p.on("position", (s) => _progress(p, s, last))
func _progress(pl, s, last):
    d := pl.duration()
    if d == null or d <= 0:
        return
    pc := to_int(100 * s / d)
    if pc // 10 != last[0]:
        last[0] = pc // 10
        print("  " + str(pc) + " %")
p.on("end", (pl_) => print("fin"))
p.set_volume(vol)
p.play()
p.run()
p.close()
