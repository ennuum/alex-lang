# ALEX STANDARD LIBRARY — multimedia.video.frame_rate
#
# Cadence des images :
#   - FrameRateConverter : convertit un flux de VideoFrame vers une cadence fixe (répète ou jette des images selon
#     leur pts, sans dérive : les instants de sortie sont n / cadence, calculés en rationnels) ;
#   - FpsMeter : cadence mesurée (moyenne glissante), gigue, images manquantes (écart > 1,5 période) ;
#   - noms courants : 23.976 (24000/1001), 29.97 (30000/1001), 59.94...
#
#   use multimedia.video.frame_rate as fr
#   conv := fr.FrameRateConverter(25, 1)
#   for f in images_30ips:
#       for g in conv.push(f):           # 0, 1 ou plusieurs images à 25 i/s
#           afficher(g)
#   m := fr.FpsMeter()
#   m.tick(t)                            # à chaque image ; m.fps(), m.dropped, m.jitter()
#
# Erreurs : FormatError (cadence invalide).

from core use len, to_int
from collections use append
use math as _m
use multimedia.core.errors as merr

const NAMED := {"23.976": [24000, 1001], "24": [24, 1], "25": [25, 1], "29.97": [30000, 1001], "30": [30, 1],
    "50": [50, 1], "59.94": [60000, 1001], "60": [60, 1]}

func named(name):
    if not (name in NAMED):
        merr.fail(merr.FORMAT, "cadence inconnue : " + str(name))
    return NAMED[name]

class FrameRateConverter:
    func init(num, den=1):
        if num <= 0 or den <= 0:
            merr.fail(merr.FORMAT, "cadence invalide")
        self.num = num
        self.den = den
        self.next_index = 0
        self.last = null
        self.dropped = 0
        self.duplicated = 0
        self.emitted = 0

    func _t(i):
        return 1.0 * i * self.den / self.num

    # Images de sortie dues jusqu'au pts de `frame` (l'image précédente couvre l'intervalle).
    func push(frame):
        out := []
        if self.last == null:
            self.last = frame
            if frame.pts > self._t(self.next_index) + 1e-9:
                # première image en retard : on commence à sa position
                self.next_index = to_int(frame.pts * self.num / self.den + 0.999999)
            return out
        used := false
        while self._t(self.next_index) < frame.pts - 1e-9:
            g := self.last.with_image(self.last.image)
            g.pts = self._t(self.next_index)
            g.duration = 1.0 * self.den / self.num
            g.index = self.next_index
            append(out, g)
            if used:
                self.duplicated += 1
            used = true
            self.next_index += 1
            self.emitted += 1
        if not used:
            self.dropped += 1
        self.last = frame
        return out

    # Vide la dernière image (fin du flux) jusqu'à `end` secondes.
    func flush(end=null):
        out := []
        if self.last == null:
            return out
        stop := end if end != null else self.last.pts + self.last.duration
        used := false
        while self._t(self.next_index) < stop - 1e-9:
            g := self.last.with_image(self.last.image)
            g.pts = self._t(self.next_index)
            g.duration = 1.0 * self.den / self.num
            g.index = self.next_index
            append(out, g)
            if used:
                self.duplicated += 1
            used = true
            self.next_index += 1
            self.emitted += 1
        if not used:
            self.dropped += 1
        self.last = null
        return out

class FpsMeter:
    func init(window=30, nominal=null):
        self.window = window
        self.times = []
        self.dropped = 0
        self.nominal = nominal
        self.count = 0

    func tick(t):
        if len(self.times) > 0 and self.nominal != null:
            gap := t - self.times[len(self.times) - 1]
            period := 1.0 / self.nominal
            if gap > 1.5 * period:
                self.dropped += to_int(gap / period + 0.5) - 1
        append(self.times, t)
        if len(self.times) > self.window:
            self.times = [self.times[k] for k in 1..len(self.times)]
        self.count += 1

    func fps():
        if len(self.times) < 2:
            return 0.0
        span := self.times[len(self.times) - 1] - self.times[0]
        if span <= 0:
            return 0.0
        return (len(self.times) - 1) / span

    # Écart type des intervalles (secondes).
    func jitter():
        n := len(self.times)
        if n < 3:
            return 0.0
        gaps := [self.times[k + 1] - self.times[k] for k in 0..n - 1]
        mean := 0.0
        for g in gaps:
            mean += g
        mean = mean / len(gaps)
        v := 0.0
        for g in gaps:
            v += (g - mean) * (g - mean)
        return _m.sqrt(v / len(gaps))
