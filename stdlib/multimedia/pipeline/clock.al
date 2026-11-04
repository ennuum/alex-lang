# ALEX STANDARD LIBRARY — multimedia.pipeline.clock
#
# Horloges :
#   SystemClock   horloge monotone de la machine (secondes) ;
#   ManualClock   horloge pilotée à la main (tests, rendu hors temps réel) : advance(s), set(s) ;
#   MediaClock    position dans le média (secondes) au-dessus d'une horloge de base : lecture, pause, reprise,
#                 vitesse (0,5x, 2x...), repositionnement après une recherche. En pause, la position ne bouge pas.
#
#   use multimedia.pipeline.clock as pc
#   base := pc.ManualClock()
#   m := pc.MediaClock(base)
#   m.start()
#   base.advance(2.0)
#   print(m.time())                 # 2.0
#   m.pause()
#   base.advance(5.0)
#   print(m.time())                 # 2.0
#   m.set_rate(2.0)
#   m.resume()
#   base.advance(1.0)
#   print(m.time())                 # 4.0
#   m.seek(30.0)
#
# Erreurs : FormatError (vitesse <= 0).

use time as _t
use multimedia.core.errors as merr

class SystemClock:
    func init():
        self.origin = _t.monotonic()

    func now():
        return _t.monotonic() - self.origin

class ManualClock:
    func init(start=0.0):
        self.t = start

    func now():
        return self.t

    func advance(seconds):
        self.t = self.t + seconds
        return self.t

    func set(seconds):
        self.t = seconds

class MediaClock:
    func init(base=null):
        self.base = base if base != null else SystemClock()
        self.rate = 1.0
        self.running = false
        self.anchor_media = 0.0
        self.anchor_base = self.base.now()

    func time():
        if not self.running:
            return self.anchor_media
        return self.anchor_media + (self.base.now() - self.anchor_base) * self.rate

    func _rebase():
        self.anchor_media = self.time()
        self.anchor_base = self.base.now()

    func start(at=0.0):
        self.anchor_media = at
        self.anchor_base = self.base.now()
        self.running = true

    func pause():
        if self.running:
            self._rebase()
            self.running = false

    func resume():
        if not self.running:
            self.anchor_base = self.base.now()
            self.running = true

    func is_running():
        return self.running

    func seek(seconds):
        self.anchor_media = seconds
        self.anchor_base = self.base.now()

    func set_rate(rate):
        if rate <= 0:
            merr.fail(merr.FORMAT, "vitesse de lecture invalide : " + str(rate))
        self._rebase()
        self.rate = rate

    # Durée réelle (horloge de base) avant que la position média atteigne `media_time` ; 0 si déjà passée.
    func delay_until(media_time):
        if not self.running:
            return null
        d := (media_time - self.time()) / self.rate
        return d if d > 0 else 0.0
