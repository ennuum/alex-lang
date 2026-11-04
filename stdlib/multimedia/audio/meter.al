# ALEX STANDARD LIBRARY — multimedia.audio.meter
#
# Mesures de niveau :
#   - crête échantillon et crête vraie (« true peak », suréchantillonnage x4 par filtre sinc), RMS, en dBFS ;
#   - sonie EBU R128 / ITU-R BS.1770-4 : filtre de pondération K (deux biquads aux coefficients recalculés pour la
#     fréquence), sonie momentanée (400 ms), court terme (3 s), INTÉGRÉE (porte absolue -70 LUFS, porte relative
#     -10 LU), plage de sonie LRA (10e-95e centiles des blocs de 3 s, porte -20 LU) ;
#   - vumètre en continu (LoudnessMeter.process par blocs).
#
#   use multimedia.audio.meter as mt
#   m := mt.LoudnessMeter(48000, 2)
#   m.process(bloc)
#   print(m.integrated(), m.momentary(), m.short_term(), m.lra(), m.sample_peak_db())
#   print(mt.db(mt.true_peak(echantillons, 48000, 2)))   # crête vraie en dBTP
#   print(mt.loudness(echantillons, 48000, 2))   # LUFS intégrés d'un tampon
#
# Valeurs vérifiées contre le filtre ebur128 de ffmpeg (tests/multimedia/test_audio_ext.al).

from core use len, to_int
from collections use append
use math as _m
use algorithm.sort as _sort
use multimedia.core.errors as merr
use multimedia.audio.resampler as rsm

func db(x):
    if x <= 0:
        return -1000.0
    return 20.0 * _m.log10(x)

func peak(samples):
    m := 0.0
    for x in samples:
        a := x if x >= 0 else -x
        if a > m:
            m = a
    return m

func rms(samples):
    if len(samples) == 0:
        return 0.0
    s := 0.0
    for x in samples:
        s += x * x
    return _m.sqrt(s / len(samples))

# Crête vraie : suréchantillonnage x4 par canal (BS.1770-4, annexe 2).
func true_peak(samples, rate, channels=1):
    m := 0.0
    for c in 0..channels:
        ch := [samples[k] for k in c..len(samples) if (k - c) % channels == 0]
        up := rsm.resample(ch, rate, rate * 4, 1, "sinc", 48)
        p := peak(up)
        if p > m:
            m = p
        p2 := peak(ch)
        if p2 > m:
            m = p2
    return m

# Coefficients K (BS.1770) pour la fréquence fs : [b0, b1, b2, a1, a2] pour les deux étages.
func k_filter(fs):
    # étage 1 : plateau haute fréquence (+4 dB)
    f0 := 1681.974450955533
    G := 3.999843853973347
    Q := 0.7071752369554196
    K := _m.tan(_m.PI * f0 / fs)
    Vh := _m.pow(10.0, G / 20.0)
    Vb := _m.pow(Vh, 0.4996667741545416)
    a0 := 1.0 + K / Q + K * K
    s1 := [(Vh + Vb * K / Q + K * K) / a0, 2.0 * (K * K - Vh) / a0, (Vh - Vb * K / Q + K * K) / a0,
           2.0 * (K * K - 1.0) / a0, (1.0 - K / Q + K * K) / a0]
    # étage 2 : passe-haut (RLB)
    f1 := 38.13547087602444
    Q1 := 0.5003270373238773
    K1 := _m.tan(_m.PI * f1 / fs)
    a01 := 1.0 + K1 / Q1 + K1 * K1
    s2 := [1.0, -2.0, 1.0, 2.0 * (K1 * K1 - 1.0) / a01, (1.0 - K1 / Q1 + K1 * K1) / a01]
    return [s1, s2]

const WEIGHTS := [1.0, 1.0, 1.0, 0.0, 1.41, 1.41]      # L, R, C, LFE, Ls, Rs (BS.1770)

class LoudnessMeter:
    func init(rate, channels=2):
        if rate < 8000 or channels < 1:
            merr.fail(merr.FORMAT, "format de mesure invalide")
        self.rate = rate
        self.channels = channels
        f := k_filter(rate)
        self.s1 = f[0]
        self.s2 = f[1]
        self.state = [[0.0, 0.0, 0.0, 0.0] for c in 0..channels]
        self.hop = rate // 10                     # 100 ms
        self.acc = [0.0 for c in 0..channels]     # énergie du pas de 100 ms en cours
        self.acc_n = 0
        self.steps = []                           # énergie pondérée par pas de 100 ms (somme des canaux)
        self.sample_peak = 0.0

    func _weight(c):
        if self.channels <= 2:
            return 1.0
        return WEIGHTS[c] if c < len(WEIGHTS) else 1.0

    func process(samples):
        ch := self.channels
        n := len(samples) // ch
        a := self.s1
        b := self.s2
        for i in 0..n:
            for c in 0..ch:
                x := samples[i * ch + c]
                ax := x if x >= 0 else -x
                if ax > self.sample_peak:
                    self.sample_peak = ax
                st := self.state[c]
                # étage 1 (forme directe II transposée)
                y := a[0] * x + st[0]
                st[0] = a[1] * x - a[3] * y + st[1]
                st[1] = a[2] * x - a[4] * y
                z := b[0] * y + st[2]
                st[2] = b[1] * y - b[3] * z + st[3]
                st[3] = b[2] * y - b[4] * z
                self.acc[c] = self.acc[c] + z * z
            self.acc_n += 1
            if self.acc_n == self.hop:
                e := 0.0
                for c in 0..ch:
                    e += self._weight(c) * self.acc[c] / self.hop
                append(self.steps, e)
                self.acc = [0.0 for c in 0..ch]
                self.acc_n = 0

    func _block_energies(nsteps):
        out := []
        for i in 0..len(self.steps) - nsteps + 1:
            s := 0.0
            for k in i..i + nsteps:
                s += self.steps[k]
            append(out, s / nsteps)
        return out

    func _lufs(e):
        if e <= 0:
            return -1000.0
        return -0.691 + 10.0 * _m.log10(e)

    func momentary():
        if len(self.steps) < 4:
            return -1000.0
        e := 0.0
        for k in len(self.steps) - 4..len(self.steps):
            e += self.steps[k]
        return self._lufs(e / 4)

    func short_term():
        if len(self.steps) < 30:
            return -1000.0
        e := 0.0
        for k in len(self.steps) - 30..len(self.steps):
            e += self.steps[k]
        return self._lufs(e / 30)

    # Sonie intégrée (LUFS) : blocs de 400 ms recouvrants à 75 %, portes absolue et relative.
    func integrated():
        blocks := self._block_energies(4)
        gated := [e for e in blocks if self._lufs(e) > -70.0]
        if len(gated) == 0:
            return -1000.0
        mean := 0.0
        for e in gated:
            mean += e
        mean = mean / len(gated)
        rel := self._lufs(mean) - 10.0
        final := [e for e in gated if self._lufs(e) > rel]
        if len(final) == 0:
            return -1000.0
        m := 0.0
        for e in final:
            m += e
        return self._lufs(m / len(final))

    # Plage de sonie (LU) : blocs de 3 s toutes les 100 ms (recommandation : pas de 1 s ; ici 100 ms, plus fin).
    func lra():
        blocks := self._block_energies(30)
        gated := [e for e in blocks if self._lufs(e) > -70.0]
        if len(gated) < 2:
            return 0.0
        mean := 0.0
        for e in gated:
            mean += e
        mean = mean / len(gated)
        rel := self._lufs(mean) - 20.0
        vals := _sort.sorted([self._lufs(e) for e in gated if self._lufs(e) > rel])
        if len(vals) < 2:
            return 0.0
        lo := vals[to_int(0.10 * (len(vals) - 1) + 0.5)]
        hi := vals[to_int(0.95 * (len(vals) - 1) + 0.5)]
        return hi - lo

    func sample_peak_db():
        return db(self.sample_peak)

func loudness(samples, rate, channels=1):
    m := LoudnessMeter(rate, channels)
    m.process(samples)
    return m.integrated()

# Gain (dB) à appliquer pour atteindre `target` LUFS (normalisation de sonie, -23 LUFS EBU, -14 diffusion web).
func normalization_gain(samples, rate, channels, target=-23.0):
    l := loudness(samples, rate, channels)
    if l <= -1000.0:
        return 0.0
    return target - l
