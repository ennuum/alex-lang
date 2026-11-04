# ALEX STANDARD LIBRARY — microphone.audio_input
#
# Une entrée audio ouverte : lecture par blocs depuis un micro (outil de capture du système) ou depuis une autre
# source (fichier WAV, mémoire, commande), gain numérique, porte de bruit, mesure de niveau (crête, efficace,
# dBFS) et rappels par bloc ; boucle asynchrone (asyncio) pour traiter le son pendant que l'application tourne.
#
#   use microphone.audio_input as ai
#   entree := ai.AudioInput(af.VOICE)                # micro par défaut ; AudioInput(fmt, "plughw:1,0")
#   fichier := ai.AudioInput(null, null, ast.WavReader("voix.wav"))
#   entree.on_block((bloc) => print(entree.level_db()))
#   await entree.run(5.0)                            # 5 s de capture, rappel à chaque bloc
#   bloc := entree.read(1600)                        # ou lecture directe (0,1 s à 16 kHz)
#   entree.close()

from core use len, to_int
from collections use append
use asyncio
use audio.audio_format as af
use audio.audio_stream as ast
use audio.audio_effects as fx

class AudioInput:
    # device : null (micro par défaut) ou nom ALSA (« plughw:1,0 », MicrophoneInfo.alsa_name()) ;
    # stream : autre source qui a read(trames) (audio_stream.MemorySource, WavReader, CaptureStream...).
    func init(fmt=null, device=null, stream=null, block_frames=null):
        self.format = af.named(fmt if fmt != null else af.VOICE)
        self.block_frames = block_frames if block_frames != null else self.format.rate // 10
        self.gain = 1.0
        self.gate_db = null             # porte de bruit : sous ce niveau, le bloc devient silence
        self.callbacks = []
        self.last_peak = 0.0
        self.last_rms = 0.0
        self.frames = 0
        self.blocks = 0
        self.stopped = false
        if stream != null:
            self.stream = stream
        else:
            self.stream = ast.CaptureStream(self.format, device)

    func set_gain_db(db):
        self.gain = fx.db_to_gain(db)

    func on_block(fn):
        append(self.callbacks, fn)

    # frames trames (bloc par défaut) après gain et porte ; [] à la fin de la source.
    func read(frames=null, timeout=null):
        n := frames if frames != null else self.block_frames
        raw := []
        if timeout != null:
            raw = self.stream.read(n, timeout)
        else:
            raw = self.stream.read(n)
        s := raw
        if self.gain != 1.0:
            s = fx.limiter(fx.gain(raw, self.gain), 0.99)
        self.last_peak = fx.peak(s)
        self.last_rms = fx.rms(s)
        if self.gate_db != null and fx.gain_to_db(self.last_rms) < self.gate_db:
            s = [0.0 for x in s]
        self.frames += len(s) // self.format.channels
        if len(s) > 0:
            self.blocks += 1
        return s

    func level_db():
        return fx.gain_to_db(self.last_rms)

    func peak_db():
        return fx.gain_to_db(self.last_peak)

    func elapsed():
        return 1.0 * self.frames / self.format.rate

    func stop():
        self.stopped = true

    # Lit des blocs pendant duration secondes (null : jusqu'à stop() ou la fin) et appelle les rappels.
    async func run(duration=null):
        while not self.stopped:
            if duration != null and self.elapsed() >= duration:
                break
            b := self.read()
            if len(b) == 0:
                break
            for fn in self.callbacks:
                fn(b)
            await asyncio.sleep(0)
        return self.frames

    func close():
        self.stream.close()

