# ALEX STANDARD LIBRARY — multimedia.playback.controls
#
# Commandes de lecture :
#   - PlaybackState : machine d'états « idle » (rien d'ouvert), « ready » (ouvert, arrêté), « playing »,
#     « paused », « ended », « closed » ; seules les transitions valides sont acceptées (StateError sinon) et
#     chaque changement est notifié ;
#   - Volume : gain 0..max (linéaire ou en dB), sourdine, rampe sans clic quand le gain change (le gain passe
#     progressivement de l'ancien au nouveau sur un bloc d'échantillons).
#
#   use multimedia.playback.controls as ctl
#   st := ctl.PlaybackState()
#   st.on_change = (avant, apres) => print(avant + " -> " + apres)
#   st.go("ready")
#   v := ctl.Volume(0.8)
#   v.set_db(-6.0)
#   sortie := v.apply(echantillons, 2)        # 2 canaux : rampe par trame
#
# Erreurs : StateError (transition invalide), FormatError (gain négatif ou au-delà du maximum).

from core use len, to_int
from collections use append
use math as _m
use multimedia.core.errors as merr

const STATES := ["idle", "ready", "playing", "paused", "ended", "closed"]

const TRANSITIONS := {"idle": ["ready", "closed"],
    "ready": ["playing", "ready", "idle", "closed"],
    "playing": ["paused", "ready", "ended", "playing", "idle", "closed"],
    "paused": ["playing", "ready", "paused", "idle", "closed", "ended"],
    "ended": ["playing", "ready", "paused", "idle", "closed", "ended"],
    "closed": []}

class PlaybackState:
    func init():
        self.state = "idle"
        self.on_change = null
        self.history = ["idle"]

    func can(target):
        return target in TRANSITIONS[self.state]

    func go(target):
        if not (target in STATES):
            merr.fail(merr.FORMAT, "état de lecture inconnu : " + str(target))
        if not self.can(target):
            merr.state("transition « " + self.state + " » -> « " + target + " » impossible")
        before := self.state
        self.state = target
        if before != target:
            append(self.history, target)
            if self.on_change != null:
                self.on_change(before, target)
        return target

    func is_(s):
        return self.state == s

func db_to_gain(db):
    return _m.pow(10.0, db / 20.0)

func gain_to_db(g):
    if g <= 0:
        return -1000.0
    return 20.0 * _m.log10(g)

class Volume:
    func init(gain=1.0, maximum=2.0):
        self.maximum = maximum
        self.muted = false
        self._applied = gain
        self.gain = 1.0
        self.set(gain)
        self._applied = self.gain

    func set(gain):
        if gain < 0 or gain > self.maximum:
            merr.fail(merr.FORMAT, "gain " + str(gain) + " hors de 0.." + str(self.maximum))
        self.gain = gain

    func set_db(db):
        self.set(db_to_gain(db))

    func db():
        return gain_to_db(self.gain)

    func mute(on=true):
        self.muted = on

    func toggle_mute():
        self.muted = not self.muted
        return self.muted

    func effective():
        return 0.0 if self.muted else self.gain

    # Gain appliqué à des échantillons entrelacés ; rampe linéaire de l'ancien gain vers le nouveau sur le bloc.
    func apply(samples, channels=1):
        target := self.effective()
        start := self._applied
        frames := len(samples) // channels
        out := []
        if start == target:
            if target == 1.0:
                self._applied = target
                return [x for x in samples]
            for x in samples:
                append(out, _clip(x * target))
            return out
        for f in 0..frames:
            g := start + (target - start) * (f + 1) / frames
            for c in 0..channels:
                append(out, _clip(samples[f * channels + c] * g))
        self._applied = target
        return out

func _clip(v):
    if v > 1.0:
        return 1.0
    if v < -1.0:
        return -1.0
    return v
