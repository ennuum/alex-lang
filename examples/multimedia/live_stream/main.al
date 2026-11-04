# Diffusion en direct sur la machine locale : un émetteur envoie un signal en paquets UDP (format AMS1), un
# récepteur le remet en ordre (tampon de gigue) et l'enregistre ; statistiques de pertes à la fin.
#   alex run examples/multimedia/live_stream/main.al
from core use len
use os
use audio.audio_format as af
use audio.audio_effects as fx
use multimedia.streaming.sink as snk
use multimedia.streaming.source as src
use multimedia.container.mux as mux

fmt := af.AudioFormat(16000, 1, "s16le")
rx := src.UdpAudioSource(0, 4)
tx := snk.UdpAudioSink("127.0.0.1", rx.port, fmt, 320)
print("émission vers 127.0.0.1:" + str(rx.port))
signal := fx.sine(440, 1.0, 16000)
for k in 0..10:
    tx.write([signal[i] for i in k * 1600..(k + 1) * 1600])
tx.close()
dst := os.tmp_dir() + "/alex_direct.wav"
w := mux.WavMuxer(dst, fmt)
while true:
    b := rx.read(1600)
    if len(b) == 0:
        break
    w.write_samples(b)
print("reçu " + str(w.close()) + " trames -> " + dst + " ; " + str(rx.buffer.stats()))
rx.close()
