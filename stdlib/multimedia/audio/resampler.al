# ALEX STANDARD LIBRARY — multimedia.audio.resampler
#
# Rééchantillonnage de qualité, en continu (par blocs, sans discontinuité aux frontières) :
#   « linear »  interpolation linéaire (rapide, repliement possible) ;
#   « sinc »    filtre sinc fenêtré (Kaiser) polyphasé : passe-bas anti-repliement à min(fe, fs) / 2, latence
#               nulle (filtre centré) ; `taps` règle la qualité (16 : rapide, 32 : bon, 64 : très bon).
# Le rapport est exact (rationnel réduit : 44100 -> 48000 = 147 / 160) : aucune dérive sur un long flux.
#
#   use multimedia.audio.resampler as rsm
#   r := rsm.Resampler(44100, 48000, 2, "sinc", 32)
#   sortie := r.process(bloc)          # flottants entrelacés, autant de fois que nécessaire
#   fin := r.flush()                   # fin du flux : vide la latence du filtre
#   x := rsm.resample(echantillons, 44100, 16000, 1)   # tout d'un coup
#
# Erreurs : FormatError (fréquences, canaux, méthode, taps).

from core use len, to_int, gcd
from collections use append
use math as _m
use _native_math as _nm
use multimedia.core.errors as merr

func _bessel_i0(x):
    s := 1.0
    t := 1.0
    k := 1
    while k < 50:
        t = t * (x / (2 * k)) * (x / (2 * k))
        s += t
        if t < 1e-12 * s:
            break
        k += 1
    return s

_tables := {}

class Resampler:
    func init(src_rate, dst_rate, channels=1, method="sinc", taps=32, beta=8.0):
        if src_rate <= 0 or dst_rate <= 0:
            merr.fail(merr.FORMAT, "fréquences invalides")
        if channels <= 0:
            merr.fail(merr.FORMAT, "nombre de canaux invalide")
        if method != "sinc" and method != "linear":
            merr.fail(merr.FORMAT, "méthode inconnue : " + str(method) + " (sinc, linear)")
        if taps < 4 or taps > 256 or taps % 2 != 0:
            merr.fail(merr.FORMAT, "taps : nombre pair entre 4 et 256")
        g := gcd(src_rate, dst_rate)
        self.up = dst_rate // g           # L
        self.down = src_rate // g         # M
        self.src_rate = src_rate
        self.dst_rate = dst_rate
        self.channels = channels
        self.method = method
        self.half = taps // 2
        self.history = [[0.0 for i in 0..self.half] for c in 0..channels]
        self.pos = 0                       # position de sortie, en 1/L d'échantillon d'entrée
        self.consumed = 0                  # échantillons d'entrée déjà retirés de l'historique
        self.base = -self.half             # indice absolu du premier échantillon de l'historique
        self.in_total = 0
        self.out_total = 0
        self.table = null
        if method == "sinc":
            self._build(beta)

    # Table polyphasée : pour chaque phase p (0..L-1), les 2*half coefficients. Partagée entre les rééchantillonneurs
    # de mêmes rapport et paramètres (lecture seule) : un nouveau flux 44,1 -> 48 kHz ne la recalcule pas.
    func _build(beta):
        key := str(self.up) + "/" + str(self.down) + "/" + str(self.half) + "/" + str(beta)
        if key in _tables:
            self.table = _tables[key]
            return null
        self._compute(beta)
        _tables[key] = self.table

    func _compute(beta):
        cutoff := 1.0 if self.up >= self.down else 1.0 * self.up / self.down
        n := 2 * self.half
        i0b := _bessel_i0(beta)
        self.table = []
        for p in 0..self.up:
            frac := 1.0 * p / self.up
            row := []
            s := 0.0
            for k in 0..n:
                x := (k - self.half + 1) - frac
                w := 0.0
                r := x / self.half
                if r > -1.0 and r < 1.0:
                    w = _bessel_i0(beta * _m.sqrt(1.0 - r * r)) / i0b
                v := 0.0
                if x == 0:
                    v = cutoff
                else:
                    v = _m.sin(_m.PI * cutoff * x) / (_m.PI * x)
                c := v * w
                append(row, c)
                s += c
            # gain unitaire en continu
            row = [c / s for c in row]
            append(self.table, row)

    # Le filtre est centré : la sortie n correspond exactement à l'instant n / fs_sortie (aucun décalage).
    func latency_out():
        return 0

    func process(samples):
        ch := self.channels
        n := len(samples) // ch
        hist := self.history
        if ch == 1:
            h := hist[0]
            for x in samples:
                append(h, x)
        else:
            for c in 0..ch:
                h := hist[c]
                for i in 0..n:
                    append(h, samples[i * ch + c])
        self.in_total += n
        out := []
        # boucle chaude : attributs en variables locales
        up := self.up
        down := self.down
        half := self.half
        base := self.base
        pos := self.pos
        avail := base + len(hist[0])          # indice absolu après le dernier échantillon
        if self.method == "sinc":
            table := self.table
            taps := 2 * half
            last := avail - half - 1          # dernière position entière calculable
            # produit scalaire natif (_native_math.dot) : même somme, dans le même ordre, que la boucle ALEX
            dot := _nm.dot
            if ch == 1:
                h := hist[0]
                while true:
                    ipos := pos // up
                    if ipos > last:
                        break
                    append(out, dot(table[pos - ipos * up], 0, h, ipos - half + 1 - base, taps))
                    pos += down
            else:
                while true:
                    ipos := pos // up
                    if ipos > last:
                        break
                    row := table[pos - ipos * up]
                    start := ipos - half + 1 - base
                    for c in 0..ch:
                        append(out, dot(row, 0, hist[c], start, taps))
                    pos += down
        else:
            while true:
                ipos := pos // up
                if ipos + 2 > avail:
                    break
                t := 1.0 * (pos - ipos * up) / up
                for c in 0..ch:
                    h := hist[c]
                    a := h[ipos - base]
                    b := h[ipos + 1 - base]
                    append(out, a + (b - a) * t)
                pos += down
        self.pos = pos
        # retire l'historique devenu inutile
        keep_from := pos // up - half - 1
        if keep_from > base:
            drop := keep_from - base
            for c in 0..ch:
                hist[c] = hist[c][drop:]
            self.base = keep_from
        self.out_total += len(out) // ch
        return out

    # Fin du flux : complète par du silence pour sortir les derniers échantillons (longueur exacte L/M).
    func flush():
        want := (self.in_total * self.up + self.down - 1) // self.down
        out := []
        guard := 0
        while self.out_total < want + self.latency_out() and guard < 64:
            out = out + self.process([0.0 for i in 0..self.half * self.channels])
            guard += 1
        return out

# Rééchantillonne d'un coup ; compense la latence : sortie de longueur ceil(n * L / M).
func resample(samples, src_rate, dst_rate, channels=1, method="sinc", taps=32):
    if src_rate == dst_rate:
        return [x for x in samples]
    r := Resampler(src_rate, dst_rate, channels, method, taps)
    out := r.process(samples) + r.flush()
    n := len(samples) // channels
    want := (n * r.up + r.down - 1) // r.down
    lat := r.latency_out() if method == "sinc" else 0
    start := lat * channels
    end := start + want * channels
    if end > len(out):
        end = len(out)
    return [out[k] for k in start..end]
