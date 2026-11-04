# ALEX STANDARD LIBRARY — audio.audio_output
#
# Sortie audio de haut niveau au-dessus d'un flux (audio_stream : PlayerStream vers le haut-parleur, WavWriter,
# MemorySink...) : FILE de tampons à jouer, volume (linéaire ou dB) et sourdine appliqués bloc par bloc,
# fondus d'entrée et de sortie, chaîne de traitements (fonctions échantillons -> échantillons), position de
# lecture, envoi par blocs (synchrone : pump / play_all, ou asynchrone : run), et sorties multiples (tee).
#
#   use audio.audio_output as ao
#   use audio.audio_stream as ast
#   out := ao.AudioOutput(ast.open_output(af.CD))        # haut-parleur (HardwareError sans lecteur)
#   out.set_volume_db(-6)
#   out.add_effect((s) => fx.lowpass(s, 44100, 8000))
#   out.enqueue(tampon1)
#   out.enqueue(tampon2, 0.5)                             # fondu d'entrée de 0,5 s
#   out.play_all()                                        # écrit tout, bloc par bloc
#   print(out.position(), out.blocks_written)
#   test := ao.AudioOutput(ast.MemorySink(af.CD))         # même chose en mémoire (tests)
#   await out.run()                                       # version asynchrone (laisse tourner l'application)
#
# Erreurs : AudioFormatError (tampon d'un autre format), AudioError (sortie fermée), et celles du flux.

from core use len, type
from collections use append
use math as _math
use asyncio
use audio.audio_format as af

class _Item:
    func init(samples, fade_in, fade_out):
        self.samples = samples
        self.pos = 0
        self.fade_in = fade_in
        self.fade_out = fade_out

class AudioOutput:
    func init(sink, fmt=null, block_frames=1024):
        self.sinks = [sink]
        self.format = fmt
        if self.format == null:
            try:
                self.format = sink.format
            catch e:
                self.format = af.CD
        self.block_frames = block_frames
        self.queue = []
        self.volume = 1.0
        self.muted = false
        self.effects = []
        self.frames_written = 0
        self.blocks_written = 0
        self.closed = false
        self.stopped = false

    func add_sink(sink):
        append(self.sinks, sink)
        return self

    func set_volume(v):
        if v < 0:
            v = 0.0
        self.volume = v * 1.0
        return self

    func set_volume_db(db):
        self.volume = _math.pow(10.0, db / 20.0)
        return self

    func volume_db():
        if self.volume <= 0:
            return -1000.0
        return 20.0 * _math.log10(self.volume)

    func mute(on=true):
        self.muted = on
        return self

    func add_effect(fn):
        append(self.effects, fn)
        return self

    # Ajoute un tampon (audio_stream.AudioBuffer ou liste d'échantillons) à la file.
    func enqueue(buf, fade_in=0.0, fade_out=0.0):
        s := buf
        if type(buf) != "list":
            if not buf.format.equals(self.format):
                if buf.format.rate != self.format.rate or buf.format.channels != self.format.channels:
                    raise("AudioFormatError", "AudioOutput : tampon " + buf.format.describe() + " pour une sortie " + self.format.describe() + " (convertir d'abord)")
            s = buf.samples
        append(self.queue, _Item(s, fade_in, fade_out))
        return self

    func queued_frames():
        n := 0
        for it in self.queue:
            n += (len(it.samples) - it.pos) // self.format.channels
        return n

    func position():
        return self.frames_written / self.format.rate

    func _gain_at(it, frame):
        g := self.volume
        if self.muted:
            return 0.0
        total := len(it.samples) // self.format.channels
        rate := self.format.rate
        if it.fade_in > 0:
            fi := it.fade_in * rate
            if frame < fi:
                g = g * frame / fi
        if it.fade_out > 0:
            fo := it.fade_out * rate
            left := total - frame
            if left < fo:
                g = g * left / fo
        return g

    func _next_block():
        c := self.format.channels
        want := self.block_frames * c
        out := []
        while len(out) < want and len(self.queue) > 0:
            it := self.queue[0]
            while len(out) < want and it.pos < len(it.samples):
                frame := it.pos // c
                append(out, it.samples[it.pos] * self._gain_at(it, frame))
                it.pos += 1
            if it.pos >= len(it.samples):
                self.queue = self.queue[1:]
        return out

    # Écrit un bloc (traité) dans les sorties ; nombre de trames écrites (0 : file vide).
    func pump():
        if self.closed:
            raise("AudioError", "AudioOutput : sortie fermée")
        b := self._next_block()
        if len(b) == 0:
            return 0
        for fx in self.effects:
            b = fx(b)
        for s in self.sinks:
            s.write(b)
        n := len(b) // self.format.channels
        self.frames_written += n
        self.blocks_written += 1
        return n

    func play_all():
        total := 0
        n := self.pump()
        while n > 0 and not self.stopped:
            total += n
            n = self.pump()
        for s in self.sinks:
            s.drain()
        return total

    func play(buf, fade_in=0.0, fade_out=0.0):
        self.enqueue(buf, fade_in, fade_out)
        return self.play_all()

    # Version asynchrone : un bloc par tour de boucle.
    func run():
        return _run(self)

    func stop():
        self.stopped = true
        self.queue = []

    func close():
        if not self.closed:
            for s in self.sinks:
                s.close()
            self.closed = true

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.close()

async func _run(o):
    total := 0
    n := o.pump()
    while n > 0 and not o.stopped:
        total += n
        await asyncio.sleep(0)
        n = o.pump()
    for s in o.sinks:
        s.drain()
    return total
