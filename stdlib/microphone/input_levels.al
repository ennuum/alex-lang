# ALEX STANDARD LIBRARY — microphone.input_levels
#
# Mesure des NIVEAUX d'entrée, comme un vumètre : crête et efficace (RMS) en dBFS par bloc, BALISTIQUE
# (montée rapide, retombée lente), maintien de crête, détection d'écrêtage, estimation du BRUIT DE FOND
# (percentile bas des niveaux récents), rapport signal / bruit, détection de parole par seuil adaptatif,
# historique, et barre textuelle pour un affichage terminal.
#
#   use microphone.input_levels as lv
#   m := lv.LevelMeter(16000)
#   entree.on_block((b) => m.feed(b))         # microphone.audio_input.AudioInput
#   print(m.rms_db, m.peak_db, m.hold_db, m.clipped)
#   print(m.noise_floor_db(), m.snr_db(), m.is_speech())
#   print(lv.bar(m.display_db, 40))           # « ██████████████░░░░░░  -18.0 dB »
#
# Niveaux en dBFS (0 = pleine échelle, -inf ramené à floor_db). Erreurs : ArgumentError.

from core use len, type
from collections use append
use math as _math

func to_db(gain, floor_db=-100.0):
    if gain <= 0:
        return floor_db
    d := 20.0 * _math.log10(gain)
    if d < floor_db:
        return floor_db
    return d

func block_levels(samples):
    peak := 0.0
    sq := 0.0
    for x in samples:
        a := x
        if a < 0:
            a = -a
        if a > peak:
            peak = a
        sq += x * x
    rms := 0.0
    if len(samples) > 0:
        rms = _math.sqrt(sq / len(samples))
    return [peak, rms]

class LevelMeter:
    func init(rate=16000, attack=0.01, release=0.3, hold=1.0, floor_db=-100.0, history=200, clip_level=0.999):
        self.rate = rate
        self.attack = attack
        self.release = release
        self.hold = hold
        self.floor_db = floor_db
        self.clip_level = clip_level
        self.peak_db = floor_db
        self.rms_db = floor_db
        self.display_db = floor_db
        self.hold_db = floor_db
        self.hold_left = 0.0
        self.clipped = 0
        self.blocks = 0
        self.history = []
        self.max_history = history
        self.elapsed = 0.0

    # Bloc d'échantillons (mono ou entrelacés) ; renvoie [crête dB, rms dB].
    func feed(samples, channels=1):
        if len(samples) == 0:
            return [self.peak_db, self.rms_db]
        lv := block_levels(samples)
        dt := len(samples) / channels / self.rate
        self.elapsed += dt
        self.peak_db = to_db(lv[0], self.floor_db)
        self.rms_db = to_db(lv[1], self.floor_db)
        for x in samples:
            if x >= self.clip_level or x <= -self.clip_level:
                self.clipped += 1
        # balistique : coefficient selon le temps de montée / descente
        tc := self.release
        if self.rms_db > self.display_db:
            tc = self.attack
        k := 1.0
        if tc > 0:
            k = 1.0 - _math.exp(-dt / tc)
        self.display_db = self.display_db + (self.rms_db - self.display_db) * k
        if self.peak_db >= self.hold_db or self.hold_left <= 0:
            self.hold_db = self.peak_db
            self.hold_left = self.hold
        else:
            self.hold_left -= dt
        append(self.history, self.rms_db)
        if len(self.history) > self.max_history:
            self.history = self.history[1:]
        self.blocks += 1
        return [self.peak_db, self.rms_db]

    # Bruit de fond : 10e percentile des niveaux récents.
    func noise_floor_db():
        if len(self.history) == 0:
            return self.floor_db
        h := self.history[:]
        i := 1
        while i < len(h):
            v := h[i]
            j := i - 1
            while j >= 0 and h[j] > v:
                h[j + 1] = h[j]
                j -= 1
            h[j + 1] = v
            i += 1
        return h[len(h) // 10]

    func snr_db():
        return self.rms_db - self.noise_floor_db()

    # Parole (ou signal) : niveau au-dessus du bruit de fond d'au moins margin dB, et au-dessus de min_db.
    func is_speech(margin=12.0, min_db=-50.0):
        return self.rms_db > min_db and self.snr_db() >= margin

    func reset():
        self.history = []
        self.clipped = 0
        self.blocks = 0
        self.peak_db = self.floor_db
        self.rms_db = self.floor_db
        self.display_db = self.floor_db
        self.hold_db = self.floor_db

    func to_dict():
        return {"peak_db": self.peak_db, "rms_db": self.rms_db, "display_db": self.display_db, "hold_db": self.hold_db,
                "clipped": self.clipped, "noise_floor_db": self.noise_floor_db(), "blocks": self.blocks}

func _fmt(db):
    v := db
    neg := v < 0
    if neg:
        v = -v
    t := str(_math.floor(v * 10 + 0.5) / 10.0)
    if neg:
        t = "-" + t
    return t

# Barre de niveau de largeur width entre min_db et 0 dB.
func bar(db, width=40, min_db=-60.0):
    f := (db - min_db) / -min_db
    if f < 0:
        f = 0.0
    if f > 1:
        f = 1.0
    n := _math.floor(f * width + 0.5)
    out := ""
    i := 0
    while i < width:
        if i < n:
            out += "█"
        else:
            out += "░"
        i += 1
    return out + "  " + _fmt(db) + " dB"
