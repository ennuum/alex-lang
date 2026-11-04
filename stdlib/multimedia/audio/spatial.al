# ALEX STANDARD LIBRARY — multimedia.audio.spatial
#
# Placement du son dans l'espace :
#   - panoramique mono -> stéréo selon trois lois : « linear », « constant_power » (sin / cos, -3 dB au centre),
#     « minus_4_5db » (compromis) ;
#   - balance stéréo, largeur stéréo (milieu / côté : 0 = mono, 1 = inchangé, 2 = élargi) ;
#   - Source3D : position (x, y, z) d'une source par rapport à l'auditeur -> gain par distance (modèles
#     « inverse », « linear », « exponential » comme OpenAL / Web Audio), panoramique d'azimut, différence de
#     temps interaurale (ITD, formule de Woodworth) et d'intensité (ILD simplifiée) pour un rendu au casque.
#
#   use multimedia.audio.spatial as sp
#   st := sp.pan(mono, -0.5)                         # flottants stéréo entrelacés
#   large := sp.width(stereo, 1.5)
#   s := sp.Source3D(48000)
#   s.set_position(2.0, 0.0, 1.0)                    # 2 m à droite, 1 m devant
#   casque := s.render(mono)                         # stéréo avec ITD / ILD et atténuation
#
# Erreurs : FormatError (loi, modèle, paramètres hors limites).

from core use len, to_int
from collections use append
use math as _m
use multimedia.core.errors as merr

const LAWS := ["linear", "constant_power", "minus_4_5db"]

# Gains [gauche, droite] pour une position -1 (gauche) .. 1 (droite).
func pan_gains(position, law="constant_power"):
    if position < -1 or position > 1:
        merr.fail(merr.FORMAT, "panoramique hors de -1..1 : " + str(position))
    p := (position + 1.0) / 2.0
    if law == "linear":
        return [1.0 - p, p]
    if law == "constant_power":
        return [_m.cos(p * _m.PI / 2), _m.sin(p * _m.PI / 2)]
    if law == "minus_4_5db":
        return [_m.sqrt((1.0 - p) * _m.cos(p * _m.PI / 2)), _m.sqrt(p * _m.sin(p * _m.PI / 2))]
    merr.fail(merr.FORMAT, "loi de panoramique inconnue : " + str(law))

func pan(mono, position, law="constant_power"):
    g := pan_gains(position, law)
    out := []
    for x in mono:
        append(out, x * g[0])
        append(out, x * g[1])
    return out

# Balance d'un signal déjà stéréo : -1 (tout à gauche) .. 1.
func balance(stereo, b):
    if b < -1 or b > 1:
        merr.fail(merr.FORMAT, "balance hors de -1..1")
    gl := 1.0 if b <= 0 else 1.0 - b
    gr := 1.0 if b >= 0 else 1.0 + b
    return [stereo[k] * (gl if k % 2 == 0 else gr) for k in 0..len(stereo)]

func width(stereo, w):
    if w < 0 or w > 4:
        merr.fail(merr.FORMAT, "largeur hors de 0..4")
    out := []
    for i in 0..len(stereo) // 2:
        l := stereo[2 * i]
        r := stereo[2 * i + 1]
        m := (l + r) / 2
        s := (l - r) / 2 * w
        append(out, m + s)
        append(out, m - s)
    return out

const MODELS := ["inverse", "linear", "exponential"]

func distance_gain(d, model="inverse", ref=1.0, max_distance=100.0, rolloff=1.0):
    if not (model in MODELS):
        merr.fail(merr.FORMAT, "modèle de distance inconnu : " + str(model))
    dd := d if d > ref else ref
    if dd > max_distance:
        dd = max_distance
    if model == "inverse":
        return ref / (ref + rolloff * (dd - ref))
    if model == "linear":
        g := 1.0 - rolloff * (dd - ref) / (max_distance - ref)
        return g if g > 0 else 0.0
    return _m.pow(dd / ref, -rolloff)

class Source3D:
    func init(rate, model="inverse", head_radius=0.0875, speed_of_sound=343.0):
        self.rate = rate
        self.model = model
        self.head_radius = head_radius
        self.c = speed_of_sound
        self.x = 0.0
        self.y = 0.0
        self.z = 1.0
        self.gain = 1.0

    # x : droite (+) / gauche (-), y : haut, z : devant (+) / derrière (-), en mètres.
    func set_position(x, y, z):
        self.x = x
        self.y = y
        self.z = z

    func distance():
        return _m.sqrt(self.x * self.x + self.y * self.y + self.z * self.z)

    # Azimut en radians : 0 devant, +pi/2 à droite.
    func azimuth():
        return _m.atan2(self.x, self.z)

    # Différence de temps interaurale (s), > 0 : l'oreille droite reçoit d'abord.
    func itd():
        az := self.azimuth()
        a := az
        if a > _m.PI / 2:
            a = _m.PI - a
        if a < -_m.PI / 2:
            a = -_m.PI - a
        return self.head_radius / self.c * (a + _m.sin(a))

    func render(mono):
        g := self.gain * distance_gain(self.distance(), self.model)
        az := self.azimuth()
        # ILD : jusqu'à ~ -6 dB sur l'oreille opposée à 90°
        s := _m.sin(az)
        gl := g * (1.0 - 0.5 * (s if s > 0 else 0.0))
        gr := g * (1.0 - 0.5 * (-s if s < 0 else 0.0))
        delay := to_int((self.itd() if self.itd() >= 0 else -self.itd()) * self.rate + 0.5)
        dl := delay if self.itd() > 0 else 0       # retard de l'oreille la plus éloignée
        dr := delay if self.itd() < 0 else 0
        n := len(mono)
        out := []
        for i in 0..n:
            l := mono[i - dl] if i - dl >= 0 else 0.0
            r := mono[i - dr] if i - dr >= 0 else 0.0
            append(out, l * gl)
            append(out, r * gr)
        return out
