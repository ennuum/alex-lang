# ALEX STANDARD LIBRARY — multimedia.recording.recorder
#
# Enregistreur audio : lit une SOURCE (tout objet avec read(trames) -> échantillons flottants, [] à la fin :
# microphone.audio_input.AudioInput, audio.audio_stream.CaptureStream, multimedia.testing.fake_device.
# FakeAudioInput...) et écrit vers une DESTINATION choisie par l'extension : .wav (multiplexeur intégré) ou tout
# format de l'adaptateur ffmpeg (.flac, .opus, .mp3, .ogg, .m4a). Durée fixe, arrêt sur silence prolongé, pause,
# limites (durée, taille), vumètre en continu, annulation, fermeture propre même en cas d'erreur.
#
#   use multimedia.recording.recorder as rec
#   r := rec.Recorder(source, af.VOICE, "note.wav")
#   r.on_level = (dbfs) => print(dbfs)
#   stats := r.record(10.0)                       # au plus 10 s
#   stats2 := r2.record_until_silence(30.0, -45.0, 1.5)
#   print(stats["frames"], stats["duration"], stats["peak_db"], stats["stopped_by"])
#
# Erreurs : StateError, LimitError, CancelledError, et celles de la destination.

from core use len, to_int
use string as _s
use audio.audio_format as _af
use multimedia.core.errors as merr
use multimedia.core.cancellation as mc
use multimedia.container.mux as mux
use multimedia.security.limits as lim
use multimedia.audio.meter as mt
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.metadata.tags as tg

# Écrivain d'après l'extension : WAV, FLAC et Ogg FLAC (.oga) en ALEX pur ; les autres par l'adaptateur ffmpeg.
func open_destination(path, fmt, tags=null):
    p := _s.lower(path)
    if _s.ends_with(p, ".wav") or _s.ends_with(p, ".flac") or _s.ends_with(p, ".oga"):
        return mux.open(path, fmt, tags)
    return ff.AudioEncoder(path, _af.AudioFormat(fmt.rate, fmt.channels, "f32le"), null, null, tags, fmt.sample_format)

class Recorder:
    func init(source, fmt, path, tags=null, block=1024, limits=null):
        self.source = source
        self.format = _af.named(fmt)
        self.path = path
        self.block = block
        self.limits = lim.of(limits)
        self.dest = open_destination(path, self.format, tags if tags != null else tg.Tags())
        self.frames = 0
        self.peak = 0.0
        self.paused = false
        self.closed = false
        self.on_level = null
        self.stopped_by = null

    func pause():
        self.paused = true

    func resume():
        self.paused = false

    func _write(x):
        if self.paused or len(x) == 0:
            return
        self.dest.write_samples(x)
        self.frames += len(x) // self.format.channels
        p := mt.peak(x)
        if p > self.peak:
            self.peak = p
        if self.on_level != null:
            self.on_level(mt.db(mt.rms(x)))

    func _stats():
        return {"frames": self.frames, "duration": 1.0 * self.frames / self.format.rate, "peak_db": mt.db(self.peak),
                "stopped_by": self.stopped_by, "path": self.path}

    func _loop(max_seconds, token, silence_db, silence_seconds):
        self.limits.check("max_duration", max_seconds)
        target := to_int(max_seconds * self.format.rate)
        quiet := 0
        heard := false
        try:
            while self.frames < target:
                mc.check(token)
                n := self.block
                if self.frames + n > target:
                    n = target - self.frames
                x := self.source.read(n)
                if len(x) == 0:
                    self.stopped_by = "fin de la source"
                    break
                self._write(x)
                if silence_db != null:
                    if mt.db(mt.rms(x)) < silence_db:
                        quiet += len(x) // self.format.channels
                    else:
                        quiet = 0
                        heard = true
                    if heard and quiet >= silence_seconds * self.format.rate:
                        self.stopped_by = "silence"
                        break
            if self.stopped_by == null:
                self.stopped_by = "durée"
        finally:
            self.close()
        return self._stats()

    func record(seconds, token=null):
        return self._loop(seconds, token, null, 0)

    # S'arrête après `silence_seconds` sous `threshold_db` (une fois du son entendu), ou à `max_seconds`.
    func record_until_silence(max_seconds, threshold_db=-45.0, silence_seconds=1.5, token=null):
        return self._loop(max_seconds, token, threshold_db, silence_seconds)

    func close():
        if self.closed:
            return
        self.closed = true
        err := null
        try:
            self.dest.close()
        catch e:
            err = e
        try:
            self.source.close()
        catch e2:
            err = err
        if err != null:
            raise(err.type, err.message)
