# ALEX STANDARD LIBRARY — microphone.capture_session
#
# Session d'enregistrement pilotée : démarrer, mettre en PAUSE, reprendre, arrêter ; accumulation en mémoire
# et / ou écriture progressive en WAV ; MARQUEURS horodatés ; durée maximale ; arrêt automatique après un
# silence prolongé (une fois la parole détectée) ; vumètre (input_levels) mis à jour à chaque bloc ; rappels
# par bloc et par changement d'état ; résumé final (durée, niveaux, marqueurs, segments de parole).
#
#   use microphone.capture_session as cs
#   s := cs.CaptureSession(audio_input.AudioInput(af.VOICE))    # ou toute source ayant read()
#   s.max_duration = 30.0
#   s.stop_on_silence = 1.5                       # s'arrête après 1,5 s de silence suivant la parole
#   s.wav_path = "note.wav"
#   s.on_state((etat) => print("état :", etat))
#   s.start()
#   while s.step():                               # un bloc par appel (ou : s.run_until_done(), await s.run())
#       if touche_pause():
#           s.pause()
#   s.mark("chapitre 2")
#   r := s.stop()                                 # résumé
#   tampon := s.buffer()                          # audio_stream.AudioBuffer
#
# États : idle -> recording <-> paused -> stopped. Erreurs : CaptureError (transition impossible).

from core use len, type
from collections use append
use asyncio
use audio.audio_stream as ast
use audio.audio_format as af
use microphone.input_levels as lv
use microphone.capture as _cap

class CaptureSession:
    func init(source, fmt=null):
        self.source = source
        self.format = fmt
        if self.format == null:
            try:
                self.format = source.format
            catch e:
                self.format = af.VOICE
        self.state = "idle"
        self.samples = []
        self.keep = true
        self.wav_path = null
        self._wav = null
        self.max_duration = null
        self.stop_on_silence = null
        self.silence_db = -45.0
        self.meter = lv.LevelMeter(self.format.rate)
        self.markers = []
        self.recorded = 0.0
        self._silence = 0.0
        self._heard = false
        self._block_cbs = []
        self._state_cbs = []
        self.block_frames = self.format.rate // 10
        self.stop_reason = null

    func _set(st):
        self.state = st
        for f in self._state_cbs:
            f(st)

    func on_block(fn):
        append(self._block_cbs, fn)
        return self

    func on_state(fn):
        append(self._state_cbs, fn)
        return self

    func start():
        if self.state != "idle":
            raise("CaptureError", "start : session déjà " + self.state)
        if self.wav_path != null:
            self._wav = ast.WavWriter(self.wav_path, self.format)
        self._set("recording")
        return self

    func pause():
        if self.state != "recording":
            raise("CaptureError", "pause : session " + self.state)
        self._set("paused")

    func resume():
        if self.state != "paused":
            raise("CaptureError", "resume : session " + self.state)
        self._set("recording")

    func mark(label):
        append(self.markers, [self.recorded, label])
        return self.recorded

    # Lit et traite un bloc ; false quand la session est terminée.
    func step():
        if self.state == "stopped" or self.state == "idle":
            return false
        b := self.source.read(self.block_frames)
        if len(b) == 0:
            self._finish("fin de la source")
            return false
        if self.state == "paused":
            return true
        ch := self.format.channels
        dt := len(b) / ch / self.format.rate
        self.meter.feed(b, ch)
        if self.keep:
            for x in b:
                append(self.samples, x)
        if self._wav != null:
            self._wav.write(b)
        self.recorded += dt
        if self.meter.rms_db > self.silence_db:
            self._heard = true
            self._silence = 0.0
        else:
            self._silence += dt
        for f in self._block_cbs:
            f(b)
        if self.max_duration != null and self.recorded >= self.max_duration:
            self._finish("durée maximale")
            return false
        if self.stop_on_silence != null and self._heard and self._silence >= self.stop_on_silence:
            self._finish("silence")
            return false
        return true

    func run_until_done(limit_blocks=1000000):
        n := 0
        while n < limit_blocks and self.step():
            n += 1
        if self.state != "stopped":
            self._finish("arrêt")
        return self.summary()

    func run():
        return _run(self)

    func _finish(reason):
        if self.state == "stopped":
            return
        self.stop_reason = reason
        if self._wav != null:
            self._wav.close()
            self._wav = null
        self._set("stopped")

    func stop():
        if self.state == "idle":
            raise("CaptureError", "stop : session jamais démarrée")
        self._finish("arrêt demandé")
        return self.summary()

    func buffer():
        return ast.AudioBuffer(self.samples, self.format)

    func segments(threshold_db=-40.0):
        if len(self.samples) == 0:
            return []
        return _cap.split_on_silence(self.buffer(), threshold_db)

    func summary():
        return {"state": self.state, "duration": self.recorded, "reason": self.stop_reason, "markers": self.markers,
                "peak_db": self.meter.hold_db, "noise_floor_db": self.meter.noise_floor_db(),
                "clipped": self.meter.clipped, "wav": self.wav_path, "frames": len(self.samples) // self.format.channels}

    func close():
        self._finish("fermeture")
        try:
            self.source.close()
        catch e:
            self.stop_reason = self.stop_reason

async func _run(s):
    if s.state == "idle":
        s.start()
    while s.step():
        await asyncio.sleep(0)
    return s.summary()
