# ALEX STANDARD LIBRARY — multimedia.video.playback
#
# Lecteur vidéo synchronisé : images décodées (adaptateur ffmpeg), son vers une sortie audio, horloge MAÎTRE
# audio (trames réellement écrites) ou horloge système sans son ; chaque image est présentée, attendue ou jetée
# par multimedia.pipeline.sync.AVSync. Mise à l'échelle optionnelle, pause, reprise, recherche, annulation,
# statistiques (présentées, jetées, dérive). Mode non temps réel (realtime=false) : toutes les images sont
# présentées dans l'ordre, l'audio intercalé jusqu'à leur pts (rendu, export, tests).
#
#   use multimedia.video.playback as vp
#   p := vp.VideoPlayer((f) => canvas_afficher(f.image), sortie_audio)
#   p.open("film.mp4")
#   p.play()
#   p.run()                                    # jusqu'à la fin, pause ou annulation
#   print(p.stats())                           # {"presented": ..., "dropped": ..., "max_drift": ...}
#
# Sortie vidéo : fonction (VideoFrame) ou objet avec present(VideoFrame). Erreurs : UnsupportedError (pas de ffmpeg),
# StateError, CancelledError.

from core use len, to_int, is_function
from collections use append
use time as _t
use multimedia.core.errors as merr
use multimedia.core.cancellation as mc
use multimedia.backends.codecs.ffmpeg as ff
use multimedia.pipeline.sync as sy
use multimedia.pipeline.clock as pc
use multimedia.playback.controls as ctl
use multimedia.video.frame as vfr

class VideoPlayer:
    func init(sink, audio_output=null, scaler=null, realtime=true, clock=null, audio_chunk=1024):
        self.sink = sink
        self.audio_output = audio_output
        self.scaler = scaler
        self.realtime = realtime
        self.base_clock = clock if clock != null else pc.SystemClock()
        self.audio_chunk = audio_chunk
        self.status = ctl.PlaybackState()
        self.volume = ctl.Volume(1.0)
        self.demux = null
        self.presented = 0
        self.audio_frames = 0
        self.audio_done = false

    func open(path, width=null, height=null):
        if self.demux != null:
            self.demux.close()
        self.demux = ff.FfmpegDemuxer(path)
        self.info = self.demux.info
        self.has_video = self.info.has("video")
        self.has_audio = self.info.has("audio") and self.audio_output != null
        if not self.has_video:
            merr.fail(merr.MEDIA, "aucune piste vidéo dans « " + path + " »")
        v := self.info.first("video")
        self.fps = v.format.fps()
        self.width = width
        self.height = height
        self._reset_clock(0.0)
        self.audio_done = not self.has_audio
        if not self.status.is_("ready"):
            self.status.go("ready")
        return self.info

    func _reset_clock(at):
        if self.has_audio:
            self.clock = sy.SampleClock(self.demux.format.rate)
            self.clock.seek(at)
        else:
            self.clock = pc.MediaClock(self.base_clock)
            self.clock.start(at)
            if not self.status.is_("playing"):
                self.clock.pause()
        self.sync = sy.AVSync(self.clock, 0.010, 0.080)

    func state():
        return self.status.state

    func play():
        if self.demux == null:
            merr.state("aucune vidéo ouverte")
        self.status.go("playing")
        if not self.has_audio:
            self.clock.resume()

    func pause():
        if self.status.is_("playing"):
            self.status.go("paused")
            if not self.has_audio:
                self.clock.pause()

    func seek(seconds):
        t := self.demux.seek(seconds)
        self._reset_clock(t)
        self.audio_done = not self.has_audio
        return t

    func position():
        return self.clock.time()

    func _present(f):
        g := f
        if self.scaler != null:
            g = self.scaler.apply(f)
        if is_function(self.sink):
            self.sink(g)
        else:
            self.sink.present(g)
        self.presented += 1

    # Écrit l'audio jusqu'à `until` secondes (ou un bloc si null).
    func _pump_audio(until=null):
        if not self.has_audio or self.audio_done:
            return
        while true:
            if until != null and self.clock.time() >= until:
                return
            fr := self.demux.read_frame(self.audio_chunk)
            if fr.eos:
                self.audio_done = true
                return
            self.audio_output.write(self.volume.apply(fr.data, self.demux.format.channels))
            n := fr.frames()
            self.clock.advance(n)
            self.audio_frames += n
            if until == null:
                return

    func run(token=null, max_frames=null):
        if not self.status.is_("playing"):
            return self.position()
        n := 0
        while self.status.is_("playing"):
            mc.check(token)
            if max_frames != null and n >= max_frames:
                break
            img := self.demux.read_video(self.width, self.height)
            if img == null:
                self._pump_audio(1e18)
                try:
                    if self.audio_output != null:
                        self.audio_output.drain()
                catch e:
                    n = n
                self.status.go("ended")
                break
            f := vfr.from_decoded(img, self.fps)
            n += 1
            if not self.realtime:
                self._pump_audio(f.pts)
                self.sync.decide(f.pts if self.has_audio else self.clock.time())
                self._present(f)
                if not self.has_audio:
                    self.clock.seek(f.end())
                continue
            # temps réel : l'audio avance l'horloge ; sans audio, l'horloge système
            if self.has_audio:
                self._pump_audio(f.pts)
            d := self.sync.decide(f.pts)
            if d[0] == "drop":
                continue
            if d[0] == "wait":
                if self.has_audio:
                    self._pump_audio(f.pts)
                else:
                    _t.sleep(d[1])
            self._present(f)
        return self.position()

    func stats():
        s := self.sync.stats()
        s["presented_total"] = self.presented
        s["audio_frames"] = self.audio_frames
        return s

    func close():
        if self.demux != null:
            self.demux.close()
            self.demux = null
        if self.audio_output != null:
            try:
                self.audio_output.close()
            catch e:
                self.audio_output = null
        if not self.status.is_("closed"):
            self.status.go("closed")
