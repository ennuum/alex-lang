# Lecteur vidéo : images décodées par ffmpeg, synchronisées sur le son ; chaque image est enregistrée en PNG
# (ou affichée : remplacer le puits par un dessin dans une fenêtre ui).
#   alex run examples/multimedia/video_player/main.al -- film.ogv [dossier_images]
from core use len
use os
use audio.audio_format as af
use multimedia.video.playback as vp
use multimedia.video.scaler as vs
use multimedia.image.encode as enc
use multimedia.testing.fake_device as fake

a := os.args()
path := a[0] if len(a) > 0 else "tests/multimedia/fixtures/ogg/theora.ogv"
out_dir := a[1] if len(a) > 1 else os.tmp_dir() + "/alex_video"
if not os.isdir(out_dir):
    os.mkdir(out_dir)
n := [0]
func show(f):
    if n[0] % 5 == 0:
        enc.save(f.image, out_dir + "/image_" + str(f.index) + ".png")
    n[0] += 1
p := vp.VideoPlayer(show, fake.FakeAudioOutput(af.AudioFormat(48000, 2, "f32le")), vs.Scaler(160, 120, "fit"), false)
info := p.open(path)
print(path + " : " + info.describe())
p.play()
p.run()
print(str(n[0]) + " images présentées ; " + str(p.stats()) + " ; aperçus dans " + out_dir)
p.close()
