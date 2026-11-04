# ALEX STANDARD LIBRARY — audio.audio_effects
#
# Générateurs et effets sur des échantillons flottants (-1.0..1.0, entrelacés si plusieurs canaux) :
#   - générateurs : sine, square, sawtooth, triangle, noise (bruit blanc reproductible), silence, chirp
#     (balayage de fréquence), envelope ADSR ;
#   - effets : gain (dB ou facteur), normalize, fade_in / fade_out, reverse, echo (retard + réinjection),
#     reverb (réverbération de Schroeder : 4 filtres en peigne + 2 passe-tout), lowpass / highpass / bandpass
#     (biquads RBJ), compressor, limiter (écrêtage doux), distortion, tremolo, pan (mono -> stéréo), mix
#     (sec / traité), concat, speed (rééchantillonnage) ;
#   - mesures : rms, peak, db, zero_crossings, estimate_pitch (autocorrélation).
#
#   use audio.audio_effects as fx
#   la := fx.sine(440, 1.0, 44100)
#   la = fx.envelope(la, 44100, 0.01, 0.1, 0.7, 0.2)
#   son := fx.reverb(fx.echo(la, 44100, 0.25, 0.4), 44100, 0.5)
#   print(fx.estimate_pitch(la, 44100))           # ~440

from core use len, to_int, to_float
from collections use append
use math

# ---------------------------------------------------------------- générateurs
func sine(frequency, seconds, rate=44100, amplitude=0.5, phase=0.0):
    n := to_int(seconds * rate)
    w := 2.0 * math.PI * frequency / rate
    # oscillateur récursif : y[k] = 2 cos(w) y[k-1] - y[k-2]
    c := 2.0 * math.cos(w)
    y1 := math.sin(phase - w)
    y2 := math.sin(phase - 2.0 * w)
    out := []
    k := 0
    while k < n:
        y := c * y1 - y2
        append(out, amplitude * y)
        y2 = y1
        y1 = y
        k += 1
    return out

func square(frequency, seconds, rate=44100, amplitude=0.5, duty=0.5):
    n := to_int(seconds * rate)
    period := 1.0 * rate / frequency
    out := []
    k := 0
    while k < n:
        p := k - to_int(k / period) * period
        append(out, amplitude if p < duty * period else -amplitude)
        k += 1
    return out

func sawtooth(frequency, seconds, rate=44100, amplitude=0.5):
    n := to_int(seconds * rate)
    period := 1.0 * rate / frequency
    out := []
    k := 0
    while k < n:
        p := (k - to_int(k / period) * period) / period
        append(out, amplitude * (2.0 * p - 1.0))
        k += 1
    return out

func triangle(frequency, seconds, rate=44100, amplitude=0.5):
    n := to_int(seconds * rate)
    period := 1.0 * rate / frequency
    out := []
    k := 0
    while k < n:
        p := (k - to_int(k / period) * period) / period
        v := 4.0 * p - 1.0
        if p > 0.5:
            v = 3.0 - 4.0 * p
        append(out, amplitude * v)
        k += 1
    return out

# Bruit blanc (générateur congruentiel : même graine, même bruit).
func noise(seconds, rate=44100, amplitude=0.3, seed=12345):
    n := to_int(seconds * rate)
    out := []
    s := seed
    k := 0
    while k < n:
        s = (s * 1103515245 + 12345) & 0x7FFFFFFF
        append(out, amplitude * (s / 1073741823.5 - 1.0))
        k += 1
    return out

func silence(seconds, rate=44100, channels=1):
    return [0.0 for i in 0..to_int(seconds * rate) * channels]

# Balayage linéaire de f0 à f1 Hz.
func chirp(f0, f1, seconds, rate=44100, amplitude=0.5):
    n := to_int(seconds * rate)
    out := []
    phase := 0.0
    k := 0
    while k < n:
        f := f0 + (f1 - f0) * k / n
        phase += 2.0 * math.PI * f / rate
        if phase > 2.0 * math.PI:
            phase -= 2.0 * math.PI
        append(out, amplitude * math.sin(phase))
        k += 1
    return out

# Enveloppe ADSR (attaque, déclin, niveau de maintien, relâchement ; secondes), appliquée sur toute la durée.
func envelope(samples, rate, attack, decay, sustain, release, channels=1):
    frames := len(samples) // channels
    a := to_int(attack * rate)
    d := to_int(decay * rate)
    r := to_int(release * rate)
    out := []
    f := 0
    while f < frames:
        g := sustain
        if f < a:
            g = 1.0 * f / a
        elif f < a + d:
            g = 1.0 - (1.0 - sustain) * (f - a) / d
        if f >= frames - r and r > 0:
            g = g * (frames - f) / r
        c := 0
        while c < channels:
            append(out, samples[f * channels + c] * g)
            c += 1
        f += 1
    return out

# ---------------------------------------------------------------- effets simples
func db_to_gain(db):
    return math.pow(10.0, db / 20.0)

func gain_to_db(g):
    if g <= 0:
        return -1000.0
    return 20.0 * math.log10(g)

func gain(samples, factor):
    return [x * factor for x in samples]

func gain_db(samples, db):
    return gain(samples, db_to_gain(db))

# Amène le pic à level (0..1).
func normalize(samples, level=0.95):
    p := peak(samples)
    if p == 0:
        return [x for x in samples]
    return gain(samples, level / p)

func fade_in(samples, rate, seconds, channels=1):
    n := to_int(seconds * rate) * channels
    out := []
    i := 0
    for x in samples:
        if i < n:
            append(out, x * (i // channels) / (n // channels))
        else:
            append(out, x)
        i += 1
    return out

func fade_out(samples, rate, seconds, channels=1):
    n := to_int(seconds * rate) * channels
    total := len(samples)
    out := []
    i := 0
    for x in samples:
        left := total - i
        if left <= n:
            append(out, x * ((left - 1) // channels) / (n // channels))
        else:
            append(out, x)
        i += 1
    return out

func reverse(samples, channels=1):
    frames := len(samples) // channels
    out := []
    f := frames - 1
    while f >= 0:
        c := 0
        while c < channels:
            append(out, samples[f * channels + c])
            c += 1
        f -= 1
    return out

func concat(parts):
    out := []
    for p in parts:
        for x in p:
            append(out, x)
    return out

# Mélange sec / traité : wet de 0 (sec) à 1 (traité).
func mix(dry, wet_samples, wet):
    n := len(dry)
    if len(wet_samples) > n:
        n = len(wet_samples)
    out := []
    i := 0
    while i < n:
        a := dry[i] if i < len(dry) else 0.0
        b := wet_samples[i] if i < len(wet_samples) else 0.0
        append(out, a * (1.0 - wet) + b * wet)
        i += 1
    return out

# Mono -> stéréo : position de -1 (gauche) à 1 (droite), loi à puissance constante.
func pan(mono, position):
    angle := (position + 1.0) * math.PI / 4.0
    gl := math.cos(angle)
    gr := math.sin(angle)
    out := []
    for x in mono:
        append(out, x * gl)
        append(out, x * gr)
    return out

func tremolo(samples, rate, frequency=5.0, depth=0.5):
    w := 2.0 * math.PI * frequency / rate
    out := []
    k := 0
    for x in samples:
        append(out, x * (1.0 - depth * 0.5 * (1.0 + math.sin(w * k))))
        k += 1
    return out

# Écrêtage doux (tanh) d'intensité drive.
func distortion(samples, drive=5.0):
    norm := math.tanh(drive)
    return [math.tanh(x * drive) / norm for x in samples]

# Limiteur : rien ne dépasse threshold (écrêtage doux au-delà).
func limiter(samples, threshold=0.9):
    out := []
    room := 1.0 - threshold
    for x in samples:
        a := x
        if a < 0:
            a = -a
        if a <= threshold:
            append(out, x)
        else:
            y := threshold + room * math.tanh((a - threshold) / room)
            append(out, y if x > 0 else -y)
    return out

# Compresseur : au-delà de threshold (dB), le niveau monte ratio fois moins vite ; attaque et relâchement en s.
func compressor(samples, rate, threshold_db=-18.0, ratio=4.0, attack=0.01, release=0.1, makeup_db=0.0):
    ga := math.exp(-1.0 / (attack * rate))
    gr := math.exp(-1.0 / (release * rate))
    env := 0.0
    makeup := db_to_gain(makeup_db)
    out := []
    for x in samples:
        a := x if x >= 0 else -x
        if a > env:
            env = ga * env + (1.0 - ga) * a
        else:
            env = gr * env + (1.0 - gr) * a
        g := 1.0
        if env > 0.0:
            level := gain_to_db(env)
            if level > threshold_db:
                reduced := threshold_db + (level - threshold_db) / ratio
                g = db_to_gain(reduced - level)
        append(out, x * g * makeup)
    return out

# ---------------------------------------------------------------- retards
# Écho : retard (s), réinjection (0..1), mélange.
func echo(samples, rate, delay=0.3, feedback=0.4, wet=0.5, channels=1):
    d := to_int(delay * rate) * channels
    buf := [x for x in samples]
    i := d
    while i < len(buf):
        buf[i] = buf[i] + buf[i - d] * feedback
        i += 1
    return mix(samples, buf, wet)

func _comb(x, delay, feedback, damp):
    out := [0.0 for i in 0..len(x)]
    store := 0.0
    i := 0
    while i < len(x):
        y := x[i]
        if i >= delay:
            store = out[i - delay] * (1.0 - damp) + store * damp
            y = y + store * feedback
        out[i] = y
        i += 1
    return out

func _allpass(x, delay, g):
    out := [0.0 for i in 0..len(x)]
    i := 0
    while i < len(x):
        prev_in := x[i - delay] if i >= delay else 0.0
        prev_out := out[i - delay] if i >= delay else 0.0
        out[i] = -g * x[i] + prev_in + g * prev_out
        i += 1
    return out

# Réverbération (Schroeder) d'un signal mono : room de 0 (petite) à 1 (grande).
func reverb(samples, rate, room=0.5, wet=0.3):
    scale := rate / 44100.0
    fb := 0.7 + 0.28 * room
    acc := [0.0 for i in 0..len(samples)]
    for d in [1116, 1188, 1277, 1356]:
        c := _comb(samples, to_int(d * scale), fb, 0.2)
        i := 0
        while i < len(acc):
            acc[i] = acc[i] + c[i] * 0.25
            i += 1
    acc = _allpass(acc, to_int(556 * scale), 0.5)
    acc = _allpass(acc, to_int(441 * scale), 0.5)
    return mix(samples, acc, wet)

# ---------------------------------------------------------------- filtres (biquads RBJ)
class Biquad:
    func init(b0, b1, b2, a1, a2):
        self.b0 = b0
        self.b1 = b1
        self.b2 = b2
        self.a1 = a1
        self.a2 = a2
        self.x1 = 0.0
        self.x2 = 0.0
        self.y1 = 0.0
        self.y2 = 0.0

    func process(x):
        y := self.b0 * x + self.b1 * self.x1 + self.b2 * self.x2 - self.a1 * self.y1 - self.a2 * self.y2
        self.x2 = self.x1
        self.x1 = x
        self.y2 = self.y1
        self.y1 = y
        return y

    func run(samples):
        return [self.process(x) for x in samples]

func _biquad(kind, frequency, rate, q):
    w := 2.0 * math.PI * frequency / rate
    cw := math.cos(w)
    alpha := math.sin(w) / (2.0 * q)
    a0 := 1.0 + alpha
    if kind == "lowpass":
        return Biquad((1.0 - cw) / 2.0 / a0, (1.0 - cw) / a0, (1.0 - cw) / 2.0 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0)
    if kind == "highpass":
        return Biquad((1.0 + cw) / 2.0 / a0, -(1.0 + cw) / a0, (1.0 + cw) / 2.0 / a0, -2.0 * cw / a0, (1.0 - alpha) / a0)
    return Biquad(alpha / a0, 0.0, -alpha / a0, -2.0 * cw / a0, (1.0 - alpha) / a0)

func lowpass(samples, rate, cutoff, q=0.7071):
    return _biquad("lowpass", cutoff, rate, q).run(samples)

func highpass(samples, rate, cutoff, q=0.7071):
    return _biquad("highpass", cutoff, rate, q).run(samples)

func bandpass(samples, rate, center, q=1.0):
    return _biquad("bandpass", center, rate, q).run(samples)

# Vitesse (et hauteur) multipliée par factor (rééchantillonnage linéaire).
func speed(samples, factor):
    n := to_int(len(samples) / factor)
    out := []
    i := 0
    while i < n:
        pos := i * factor
        k := to_int(pos)
        t := pos - k
        a := samples[k]
        b := samples[k + 1] if k + 1 < len(samples) else a
        append(out, a + (b - a) * t)
        i += 1
    return out

# ---------------------------------------------------------------- mesures
func rms(samples):
    if len(samples) == 0:
        return 0.0
    s := 0.0
    for x in samples:
        s += x * x
    return math.sqrt(s / len(samples))

func peak(samples):
    p := 0.0
    for x in samples:
        a := x if x >= 0 else -x
        if a > p:
            p = a
    return p

# Niveau efficace en dBFS.
func db(samples):
    return gain_to_db(rms(samples))

func zero_crossings(samples):
    n := 0
    i := 1
    while i < len(samples):
        if (samples[i - 1] < 0.0) != (samples[i] < 0.0):
            n += 1
        i += 1
    return n

# Hauteur fondamentale (Hz) par autocorrélation entre fmin et fmax ; 0 si le signal est trop faible.
# Le premier maximum local qui atteint 90 % du maximum global est retenu (évite les octaves inférieures).
func estimate_pitch(samples, rate, fmin=50.0, fmax=2000.0):
    n := len(samples)
    if n > 2048:
        n = 2048
    if rms(samples) < 0.001:
        return 0.0
    lo := to_int(rate / fmax)
    hi := to_int(rate / fmin)
    if hi >= n - 1:
        hi = n - 2
    values := []
    lag := lo
    while lag <= hi + 1:
        s := 0.0
        i := 0
        while i + lag < n:
            s += samples[i] * samples[i + lag]
            i += 1
        append(values, s / (n - lag))
        lag += 1
    top := 0.0
    for v in values:
        if v > top:
            top = v
    if top <= 0.0:
        return 0.0
    k := 1
    while k < len(values) - 1:
        if values[k] >= 0.9 * top and values[k] >= values[k - 1] and values[k] >= values[k + 1]:
            # interpolation parabolique autour du maximum
            a := values[k - 1]
            b := values[k]
            c := values[k + 1]
            d := a - 2.0 * b + c
            shift := 0.0
            if d != 0.0:
                shift = 0.5 * (a - c) / d
            return 1.0 * rate / (lo + k + shift)
        k += 1
    return 0.0
