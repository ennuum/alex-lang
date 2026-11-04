# ALEX STANDARD LIBRARY — multimedia.playback.player
#
# Lecteur audio : ouverture d'un fichier (WAV par multimedia.container.demux), lecture par blocs vers une
# SORTIE (par défaut le lecteur du système, audio.audio_stream.PlayerStream ; injectable : MemorySink,
# multimedia.testing.fake_device.FakeAudioOutput, WavMuxer...), pause / reprise / arrêt, recherche, volume avec
# rampe sans clic, sourdine, position exacte d'après les trames écrites, sous-titres synchronisés, listes de
# lecture, événements, annulation, fermeture propre.
#
#   use multimedia.playback.player as mp
#   p := mp.Player()                          # sortie système ouverte à la lecture (DeviceError si absente)
#   p.on("end", (lecteur) => print("fini"))
#   p.open("voix.wav")
#   p.set_volume(0.7)
#   p.play()
#   p.run()                                   # joue jusqu'à la fin (ou pause / stop depuis un événement)
#   p.seek(12.0)
#   print(p.position(), p.duration(), p.state())
#   p.close()
#
#   # pas à pas (boucle d'événements d'une interface) : p.pump() écrit un bloc et rend la main
#   # liste : p.open_playlist(pl.load("soiree.m3u")) puis p.run() enchaîne les entrées
#
# Événements : « state » (avant, après), « position » (secondes), « end », « error » (type, message),
# « track » (Entry de la liste). Erreurs : StateError, DeviceError, et celles du démultiplexeur.

from core use len
from collections use append, keys
use audio.audio_stream as _ast
use multimedia.core.errors as merr
use multimedia.core.cancellation as mc
use multimedia.container.demux as dmx
use multimedia.pipeline.sync as sy
use multimedia.playback.controls as ctl
use multimedia.playback.seek as sk
use multimedia.playback.subtitles as psub
use multimedia.security.limits as lim

class Player:
    func init(output=null, limits=null, chunk_frames=2048, output_factory=null):
        self.limits = lim.of(limits)
        self.chunk_frames = chunk_frames
        self._output = output
        self._own_output = false
        self._factory = output_factory
        self.status = ctl.PlaybackState()
        self.status.on_change = (a, b) => self._emit("state", [a, b])
        self.volume = ctl.Volume(1.0)
        self.demuxer = null
        self.clock = null
        self.subtitles = null
        self.playlist = null
        self.path = null
        self.listeners = {}
        self.frames_played = 0
        self.underruns = 0

    # ------------------------------------------------------------------ événements
    func on(event, fn):
        if not (event in self.listeners):
            self.listeners[event] = []
        append(self.listeners[event], fn)

    func _emit(event, args):
        if not (event in self.listeners):
            return
        for fn in self.listeners[event]:
            if len(args) == 0:
                fn(self)
            elif len(args) == 1:
                fn(args[0])
            else:
                fn(args[0], args[1])

    # ------------------------------------------------------------------ ouverture
    func open(path):
        if self.status.is_("closed"):
            merr.state("lecteur fermé")
        self._release()
        self.demuxer = dmx.open(path, self.limits)
        self.path = path
        self.clock = sy.SampleClock(self.demuxer.format.rate)
        if self.subtitles != null:
            self.subtitles.reset()
        if not self.status.is_("ready"):
            self.status.go("ready")
        return self.demuxer.info

    func open_playlist(playlist):
        self.playlist = playlist
        e := playlist.current()
        if e == null:
            merr.fail(merr.MEDIA, "liste de lecture vide")
        self._emit("track", [e])
        return self.open(e.path)

    func attach_subtitles(track, delay=0.0):
        self.subtitles = psub.SubtitleDisplay(track, delay)
        return self.subtitles

    func info():
        if self.demuxer == null:
            return null
        return self.demuxer.info

    func _need_open():
        if self.demuxer == null:
            merr.state("aucun média ouvert")

    func _out():
        if self._output == null:
            if self._factory != null:
                self._output = self._factory(self.demuxer.format)
            else:
                try:
                    self._output = _ast.open_output(self.demuxer.format)
                catch e:
                    merr.fail(merr.DEVICE, "aucune sortie audio : " + e.message)
            self._own_output = true
        return self._output

    # ------------------------------------------------------------------ commandes
    func state():
        return self.status.state

    func play():
        self._need_open()
        if self.status.is_("ended"):
            self.seek(0.0)
        self.status.go("playing")

    func pause():
        if self.status.is_("playing"):
            self.status.go("paused")

    func resume():
        if self.status.is_("paused"):
            self.status.go("playing")

    func toggle():
        if self.status.is_("playing"):
            self.pause()
        else:
            self.play()

    func stop():
        if self.demuxer == null:
            return
        if self._output != null:
            try:
                self._output.drain()
            catch e:
                self._emit("error", [e.type, e.message])
        self.demuxer.seek(0.0)
        self.clock.seek(0.0)
        if self.subtitles != null:
            self.subtitles.reset()
        if not self.status.is_("ready"):
            self.status.go("ready")

    func seek(seconds):
        self._need_open()
        target := sk.frame_aligned(sk.absolute(seconds, self.duration()), self.demuxer.format.rate)
        got := self.demuxer.seek(target)
        self.clock.seek(got)
        if self.subtitles != null:
            self.subtitles.reset()
        if self.status.is_("ended"):
            self.status.go("paused")
        self._emit("position", [got])
        return got

    func seek_relative(delta):
        return self.seek(self.position() + delta)

    func set_volume(gain):
        self.volume.set(gain)

    func set_volume_db(db):
        self.volume.set_db(db)

    func mute(on=true):
        self.volume.mute(on)

    func position():
        if self.clock == null:
            return 0.0
        return self.clock.time()

    func duration():
        if self.demuxer == null:
            return null
        return self.demuxer.duration()

    func subtitle_text():
        if self.subtitles == null:
            return ""
        return self.subtitles.text()

    # ------------------------------------------------------------------ lecture
    # Écrit jusqu'à `chunks` blocs si l'état est « playing » ; renvoie le nombre de trames écrites.
    func pump(chunks=1):
        if not self.status.is_("playing"):
            return 0
        out := self._out()
        written := 0
        for i in 0..chunks:
            f := self.demuxer.read_frame(self.chunk_frames)
            if f.eos:
                self._end_of_media()
                break
            data := self.volume.apply(f.data, self.demuxer.format.channels)
            try:
                out.write(data)
            catch e:
                self._emit("error", [e.type, e.message])
                self.status.go("paused")
                merr.fail(merr.category(e.type), "sortie audio : " + e.message)
            n := f.frames()
            self.clock.advance(n)
            self.frames_played += n
            written += n
            if self.subtitles != null:
                self.subtitles.update(self.position())
            self._emit("position", [self.position()])
            if not self.status.is_("playing"):
                break
        return written

    func _end_of_media():
        try:
            self._out().drain()
        catch e:
            self._emit("error", [e.type, e.message])
        self.status.go("ended")
        self._emit("end", [])
        if self.playlist != null:
            nxt := self.playlist.next()
            if nxt != null:
                self._emit("track", [nxt])
                self.open(nxt.path)
                self.status.go("playing")

    func next_track():
        if self.playlist == null:
            return null
        nxt := self.playlist.next(true)
        if nxt != null:
            was := self.status.is_("playing")
            self._emit("track", [nxt])
            self.open(nxt.path)
            if was:
                self.status.go("playing")
        return nxt

    func previous_track():
        if self.playlist == null:
            return null
        if self.position() > 3.0:
            self.seek(0.0)
            return self.playlist.current()
        prv := self.playlist.previous()
        was := self.status.is_("playing")
        self._emit("track", [prv])
        self.open(prv.path)
        if was:
            self.status.go("playing")
        return prv

    # Joue tant que l'état est « playing » (fin du média, pause ou arrêt demandés par un événement).
    func run(token=null, max_chunks=null):
        n := 0
        while self.status.is_("playing"):
            mc.check(token)
            if max_chunks != null and n >= max_chunks:
                break
            self.pump(1)
            n += 1
        return self.position()

    # ------------------------------------------------------------------ fermeture
    func _release():
        if self.demuxer != null:
            self.demuxer.close()
            self.demuxer = null

    func close():
        if self.status.is_("closed"):
            return
        err := null
        if self._output != null and self._own_output:
            try:
                self._output.close()
            catch e:
                err = e
        self._output = null
        self._release()
        self.status.go("closed")
        if err != null:
            merr.fail(merr.category(err.type), "fermeture de la sortie audio : " + err.message)

# Joue un fichier jusqu'au bout (sortie système) : raccourci de mp.Player().
func play_file(path, volume=1.0, output=null, token=null):
    p := Player(output)
    try:
        p.open(path)
        p.set_volume(volume)
        p.play()
        p.run(token)
        return p.position()
    finally:
        p.close()
