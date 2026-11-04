# Convertit un WAV (fréquence, canaux, format d'échantillon) par un pipeline borné : lecture par blocs ->
# conversion -> gain -> écriture, avec barre de progression et mesures.
#   alex run examples/multimedia/audio_converter.al -- entree.wav sortie.wav [fréquence] [canaux] [format] [gain]
#   (sans argument : convertit un fichier du corpus de test en 16 kHz mono f32le vers /tmp)
from core use len, to_int, to_float
use os
use audio.audio_format as af
use multimedia.core.buffer as mb
use multimedia.container.demux as dmx
use multimedia.container.mux as mux
use multimedia.pipeline.node as nd
use multimedia.pipeline.scheduler as ps
use multimedia.diagnostics.metrics as mm

a := os.args()
src := a[0] if len(a) > 0 else "tests/multimedia/fixtures/media/st_s24le.wav"
dst := a[1] if len(a) > 1 else os.tmp_dir() + "/alex_conversion.wav"
rate := to_int(a[2]) if len(a) > 2 else 16000
channels := to_int(a[3]) if len(a) > 3 else 1
sf := a[4] if len(a) > 4 else "f32le"
gain := to_float(a[5]) if len(a) > 5 else 0.8

d := dmx.open(src)
cible := af.AudioFormat(rate, channels, sf)
print(src + " : " + d.format.describe() + ", " + str(d.duration()) + " s -> " + cible.describe())
w := mux.WavMuxer(dst, cible, d.tags)
m := mm.Metrics()

func convertir(f):
    h := m.start("conversion")
    s := f.data
    if f.format.channels != cible.channels:
        s = af.convert_channels(s, f.format.channels, cible.channels)
    if f.format.rate != cible.rate:
        s = af.resample(s, f.format.rate, cible.rate, cible.channels)
    m.stop(h)
    m.count("trames", f.frames())
    return mb.audio_frame(s, cible, f.pts)

total := d.frames
func progression(f):
    p := to_int(100.0 * m.counter("trames") / total)
    print("  " + str(p) + " %")

ps.run_chain([nd.demux_source("lecture", d, 4096), nd.map("conversion", convertir), nd.audio_gain("gain", gain),
              nd.map("progression", (f) => _avec(f, progression)), nd.audio_output("écriture", w, true, "write_samples")], 4)

func _avec(f, fn):
    fn(f)
    return f

r := m.report()
print(dst + " : " + str(w.frames) + " trames écrites, conversion " + str(r["timings"]["conversion"]["count"]) + " blocs")
