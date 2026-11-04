# ALEX STANDARD LIBRARY — microphone.capture
#
# Enregistrer : durée fixe, jusqu'au silence (détection d'activité vocale par l'énergie, avec temps de
# maintien), vers un fichier WAV pendant la capture, ou découpage d'un enregistrement en segments de parole.
#
#   use microphone.capture as cap
#   r := cap.Recorder(af.VOICE)                       # micro par défaut
#   b := r.record(3.0)                                # AudioBuffer de 3 s
#   b = r.record_until_silence(10.0, 0.8)             # au plus 10 s, s'arrête après 0,8 s de silence
#   r.record_to_wav("note.wav", 5.0)
#   for seg in cap.split_on_silence(b):               # [début, fin] en secondes
#       print(seg)

from core use len, to_int
from collections use append
use audio.audio_format as af
use audio.audio_stream as ast
use audio.audio_effects as fx
use microphone.audio_input as ai

class Recorder:
    # device : nom ALSA ou null (défaut) ; stream : autre source (voir audio_input.AudioInput).
    func init(fmt=null, device=null, stream=null):
        self.format = af.named(fmt if fmt != null else af.VOICE)
        self.input = ai.AudioInput(self.format, device, stream)
        self.threshold_db = -40.0        # sous ce niveau : silence
        self.speech_started = false

    func record(seconds):
        out := []
        need := to_int(seconds * self.format.rate)
        got := 0
        while got < need:
            n := self.input.block_frames
            if need - got < n:
                n = need - got
            b := self.input.read(n)
            if len(b) == 0:
                break
            for x in b:
                append(out, x)
            got += len(b) // self.format.channels
        return ast.AudioBuffer(out, self.format)

    # Enregistre jusqu'à silence secondes de silence APRÈS le début de la parole (ou max_seconds).
    func record_until_silence(max_seconds, silence=0.8, wait_speech=true):
        out := []
        quiet := 0.0
        block_s := 1.0 * self.input.block_frames / self.format.rate
        elapsed := 0.0
        self.speech_started = not wait_speech
        while elapsed < max_seconds:
            b := self.input.read()
            if len(b) == 0:
                break
            elapsed += block_s
            loud := fx.gain_to_db(fx.rms(b)) >= self.threshold_db
            if loud:
                self.speech_started = true
                quiet = 0.0
            elif self.speech_started:
                quiet += block_s
            if self.speech_started:
                for x in b:
                    append(out, x)
                if quiet >= silence:
                    break
        return ast.AudioBuffer(out, self.format)

    # Écrit la capture dans un WAV au fur et à mesure ; renvoie le nombre de trames écrites.
    func record_to_wav(path, seconds):
        w := ast.WavWriter(path, self.format)
        need := to_int(seconds * self.format.rate)
        got := 0
        while got < need:
            n := self.input.block_frames
            if need - got < n:
                n = need - got
            b := self.input.read(n)
            if len(b) == 0:
                break
            w.write(b)
            got += len(b) // self.format.channels
        w.close()
        return got

    func close():
        self.input.close()

# Segments de parole [début, fin] (secondes) d'un AudioBuffer : blocs de block secondes au-dessus de
# threshold_db, réunis si l'écart est inférieur à min_gap.
func split_on_silence(buf, threshold_db=-40.0, block=0.02, min_gap=0.3):
    s := buf.samples
    if buf.format.channels > 1:
        s = buf.channel(0)
    n := to_int(block * buf.format.rate)
    if n < 1:
        n = 1
    segments := []
    start := -1.0
    last_loud := -1.0
    i := 0
    while i < len(s):
        chunk := [s[k] for k in i..(i + n if i + n < len(s) else len(s))]
        t := 1.0 * i / buf.format.rate
        if fx.gain_to_db(fx.rms(chunk)) >= threshold_db:
            if start < 0:
                start = t
            elif t - last_loud > min_gap:
                append(segments, [start, last_loud + block])
                start = t
            last_loud = t
        i += n
    if start >= 0:
        append(segments, [start, last_loud + block])
    return segments
