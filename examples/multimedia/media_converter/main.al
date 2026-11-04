# Convertisseur : transcode un fichier audio (WAV / FLAC / Ogg en ALEX ; autres par ffmpeg) avec progression.
#   alex run examples/multimedia/media_converter/main.al -- entree sortie [fréquence] [canaux]
from core use len, to_int
use os
use audio.audio_format as af
use multimedia.container.probe as probe
use multimedia.recording.export as ex

a := os.args()
src := a[0] if len(a) > 0 else "tests/multimedia/fixtures/flac/st16_l5.flac"
dst := a[1] if len(a) > 1 else os.tmp_dir() + "/alex_conversion.wav"
i := probe.probe(src).first("audio")
rate := to_int(a[2]) if len(a) > 2 else i.format.rate
ch := to_int(a[3]) if len(a) > 3 else i.format.channels
print(src + " (" + i.format.describe() + ") -> " + dst)
r := ex.transcode(src, dst, af.AudioFormat(rate, ch, "s16le"), (p) => print("  " + str(to_int(p * 100)) + " %"))
print(probe.probe(dst).describe())
