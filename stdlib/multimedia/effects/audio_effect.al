# ALEX STANDARD LIBRARY — multimedia.effects.audio_effect
#
# Effets audio EN CONTINU (état conservé d'un bloc à l'autre : aucun clic aux frontières), contrairement aux
# fonctions sur tampon entier de audio.audio_effects :
#   Gain, Biquad (passe-bas, passe-haut, passe-bande, crête « peaking », plateaux grave / aigu, coupe-bande —
#   formules du « Audio EQ Cookbook »), Equalizer (chaîne de biquads), Delay (écho à rétroaction), Compressor
#   (détection RMS, attaque / relâchement, genou), Limiter (anticipation), NoiseGate, Chain (enchaînement).
# Chaque effet : process(échantillons entrelacés) -> échantillons ; reset() ; utilisable comme nœud de pipeline
# (effect_node).
#
#   use multimedia.effects.audio_effect as ae
#   eq := ae.Equalizer(48000, 2, [["lowshelf", 100, 0.7, 3.0], ["peaking", 2500, 1.0, -4.0]])
#   ch := ae.Chain([eq, ae.Compressor(48000, 2, -18.0, 3.0), ae.Limiter(48000, 2, -1.0)])
#   sortie := ch.process(bloc)
#   noeud := ae.effect_node("mastering", ch)          # multimedia.pipeline.node
#
# Erreurs : FormatError (paramètres).

from core use len, to_int
from collections use append
use math as _m
use multimedia.core.errors as merr
use multimedia.core.buffer as mb
use multimedia.pipeline.node as nd
from multimedia.pipeline.node use Node

func _db(g):
    return _m.pow(10.0, g / 20.0)

class Gain:
    func init(db=0.0):
        self.g = _db(db)

    func process(x):
        return [v * self.g for v in x]

    func reset():
        return null

const BIQUADS := ["lowpass", "highpass", "bandpass", "notch", "peaking", "lowshelf", "highshelf"]

class Biquad:
    func init(rate, channels, kind, frequency, q=0.7071, gain_db=0.0):
        if not (kind in BIQUADS):
            merr.fail(merr.FORMAT, "filtre inconnu : " + str(kind))
        if frequency <= 0 or frequency >= rate / 2:
            merr.fail(merr.FORMAT, "fréquence " + str(frequency) + " hors de 0..Nyquist")
        if q <= 0:
            merr.fail(merr.FORMAT, "Q invalide")
        self.channels = channels
        A := _m.pow(10.0, gain_db / 40.0)
        w := 2.0 * _m.PI * frequency / rate
        cw := _m.cos(w)
        sw := _m.sin(w)
        alpha := sw / (2.0 * q)
        b0 := 0.0
        b1 := 0.0
        b2 := 0.0
        a0 := 0.0
        a1 := 0.0
        a2 := 0.0
        if kind == "lowpass":
            b0 = (1 - cw) / 2
            b1 = 1 - cw
            b2 = (1 - cw) / 2
            a0 = 1 + alpha
            a1 = -2 * cw
            a2 = 1 - alpha
        elif kind == "highpass":
            b0 = (1 + cw) / 2
            b1 = -(1 + cw)
            b2 = (1 + cw) / 2
            a0 = 1 + alpha
            a1 = -2 * cw
            a2 = 1 - alpha
        elif kind == "bandpass":
            b0 = alpha
            b1 = 0.0
            b2 = -alpha
            a0 = 1 + alpha
            a1 = -2 * cw
            a2 = 1 - alpha
        elif kind == "notch":
            b0 = 1.0
            b1 = -2 * cw
            b2 = 1.0
            a0 = 1 + alpha
            a1 = -2 * cw
            a2 = 1 - alpha
        elif kind == "peaking":
            b0 = 1 + alpha * A
            b1 = -2 * cw
            b2 = 1 - alpha * A
            a0 = 1 + alpha / A
            a1 = -2 * cw
            a2 = 1 - alpha / A
        else:
            sa := 2 * _m.sqrt(A) * alpha
            if kind == "lowshelf":
                b0 = A * ((A + 1) - (A - 1) * cw + sa)
                b1 = 2 * A * ((A - 1) - (A + 1) * cw)
                b2 = A * ((A + 1) - (A - 1) * cw - sa)
                a0 = (A + 1) + (A - 1) * cw + sa
                a1 = -2 * ((A - 1) + (A + 1) * cw)
                a2 = (A + 1) + (A - 1) * cw - sa
            else:
                b0 = A * ((A + 1) + (A - 1) * cw + sa)
                b1 = -2 * A * ((A - 1) + (A + 1) * cw)
                b2 = A * ((A + 1) + (A - 1) * cw - sa)
                a0 = (A + 1) - (A - 1) * cw + sa
                a1 = 2 * ((A - 1) - (A + 1) * cw)
                a2 = (A + 1) - (A - 1) * cw - sa
        self.c = [b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0]
        self.reset()

    func reset():
        self.z = [[0.0, 0.0] for c in 0..self.channels]

    # Gain (linéaire) à la fréquence f : |H(e^jw)|.
    func response(f, rate):
        w := 2.0 * _m.PI * f / rate
        c := self.c
        nr := c[0] + c[1] * _m.cos(w) + c[2] * _m.cos(2 * w)
        ni := -(c[1] * _m.sin(w) + c[2] * _m.sin(2 * w))
        dr := 1.0 + c[3] * _m.cos(w) + c[4] * _m.cos(2 * w)
        di := -(c[3] * _m.sin(w) + c[4] * _m.sin(2 * w))
        return _m.sqrt((nr * nr + ni * ni) / (dr * dr + di * di))

    func process(x):
        ch := self.channels
        c := self.c
        out := [0.0 for v in x]
        for k in 0..len(x):
            z := self.z[k % ch]
            v := x[k]
            y := c[0] * v + z[0]
            z[0] = c[1] * v - c[3] * y + z[1]
            z[1] = c[2] * v - c[4] * y
            out[k] = y
        return out

class Equalizer:
    func init(rate, channels, bands):
        self.bands = [Biquad(rate, channels, b[0], b[1], b[2], b[3] if len(b) > 3 else 0.0) for b in bands]

    func process(x):
        y := x
        for b in self.bands:
            y = b.process(y)
        return y

    func reset():
        for b in self.bands:
            b.reset()

class Delay:
    func init(rate, channels, seconds=0.3, feedback=0.4, wet=0.5):
        if seconds <= 0 or feedback < 0 or feedback >= 1 or wet < 0 or wet > 1:
            merr.fail(merr.FORMAT, "paramètres d'écho invalides")
        self.channels = channels
        self.n = to_int(seconds * rate) * channels
        self.feedback = feedback
        self.wet = wet
        self.reset()

    func reset():
        self.buf = [0.0 for i in 0..self.n]
        self.pos = 0

    func process(x):
        out := []
        for v in x:
            d := self.buf[self.pos]
            self.buf[self.pos] = v + d * self.feedback
            self.pos = (self.pos + 1) % self.n
            append(out, v * (1.0 - self.wet) + d * self.wet)
        return out

class Compressor:
    func init(rate, channels, threshold_db=-18.0, ratio=4.0, attack=0.005, release=0.1, knee_db=6.0, makeup_db=0.0):
        if ratio < 1:
            merr.fail(merr.FORMAT, "rapport de compression < 1")
        self.channels = channels
        self.t = threshold_db
        self.ratio = ratio
        self.knee = knee_db
        self.makeup = _db(makeup_db)
        self.att = _m.exp(-1.0 / (attack * rate)) if attack > 0 else 0.0
        self.rel = _m.exp(-1.0 / (release * rate)) if release > 0 else 0.0
        self.reset()

    func reset():
        self.env = 0.0
        self.min_gain = 1.0

    func _curve(level_db):
        over := level_db - self.t
        if self.knee > 0 and 2 * over > -self.knee and 2 * over < self.knee:
            return (1.0 / self.ratio - 1.0) * (over + self.knee / 2) * (over + self.knee / 2) / (2 * self.knee)
        if over <= 0:
            return 0.0
        return over * (1.0 / self.ratio - 1.0)

    func process(x):
        ch := self.channels
        out := [0.0 for v in x]
        n := len(x) // ch
        for i in 0..n:
            p := 0.0
            for c in 0..ch:
                v := x[i * ch + c]
                if v * v > p:
                    p = v * v
            coef := self.att if p > self.env else self.rel
            self.env = coef * self.env + (1.0 - coef) * p
            level := 10.0 * _m.log10(self.env) if self.env > 1e-12 else -120.0
            g := _db(self._curve(level)) * self.makeup
            if g < self.min_gain:
                self.min_gain = g
            for c in 0..ch:
                out[i * ch + c] = x[i * ch + c] * g
        return out

# Limiteur à anticipation (lookahead) : la crête est vue `lookahead` secondes à l'avance ; sortie <= plafond.
class Limiter:
    func init(rate, channels, ceiling_db=-1.0, lookahead=0.005, release=0.05):
        self.channels = channels
        self.ceiling = _db(ceiling_db)
        self.look = to_int(lookahead * rate)
        if self.look < 1:
            self.look = 1
        self.rel = _m.exp(-1.0 / (release * rate))
        self.reset()

    func reset():
        self.delay = [[0.0 for i in 0..self.look] for c in 0..self.channels]
        self.peaks = [0.0 for i in 0..self.look]
        self.pos = 0
        self.gain = 1.0

    func process(x):
        ch := self.channels
        n := len(x) // ch
        out := [0.0 for v in x]
        for i in 0..n:
            p := 0.0
            for c in 0..ch:
                v := x[i * ch + c]
                a := v if v >= 0 else -v
                if a > p:
                    p = a
            self.peaks[self.pos] = p
            m := 0.0
            for q in self.peaks:
                if q > m:
                    m = q
            target := 1.0 if m <= self.ceiling else self.ceiling / m
            if target < self.gain:
                self.gain = target
            else:
                self.gain = target + (self.gain - target) * self.rel
            for c in 0..ch:
                d := self.delay[c][self.pos]
                self.delay[c][self.pos] = x[i * ch + c]
                y := d * self.gain
                if y > self.ceiling:
                    y = self.ceiling
                if y < -self.ceiling:
                    y = -self.ceiling
                out[i * ch + c] = y
            self.pos = (self.pos + 1) % self.look
        return out

class NoiseGate:
    func init(rate, channels, threshold_db=-50.0, hold=0.05, release=0.05):
        self.channels = channels
        self.t = _db(threshold_db)
        self.hold = to_int(hold * rate)
        self.rel = _m.exp(-1.0 / (release * rate))
        self.reset()

    func reset():
        self.count = 0
        self.g = 0.0

    func process(x):
        ch := self.channels
        out := [0.0 for v in x]
        for i in 0..len(x) // ch:
            p := 0.0
            for c in 0..ch:
                v := x[i * ch + c]
                a := v if v >= 0 else -v
                if a > p:
                    p = a
            if p >= self.t:
                self.count = self.hold
                self.g = 1.0
            elif self.count > 0:
                self.count -= 1
            else:
                self.g = self.g * self.rel
            for c in 0..ch:
                out[i * ch + c] = x[i * ch + c] * self.g
        return out

class Chain:
    func init(effects):
        self.effects = effects

    func process(x):
        y := x
        for e in self.effects:
            y = e.process(y)
        return y

    func reset():
        for e in self.effects:
            e.reset()

class EffectNode extends Node:
    func init(name, effect):
        super.init(name)
        self.effect = effect

    func process(f):
        if f.data == null:
            return [f]
        return [mb.Frame(f.kind, self.effect.process(f.data), f.format, f.pts, f.duration)]

func effect_node(name, effect):
    return EffectNode(name, effect)
