# ALEX STANDARD LIBRARY — multimedia.core.timestamp
#
# Horodatages EXACTS : un instant est un entier `pts` dans une base de temps rationnelle (num / den secondes),
# comme dans les conteneurs (1/44100 pour l'audio, 1/90000 pour MPEG, 1/1000 pour les sous-titres). Les calculs
# restent en entiers ; la conversion vers une autre base arrondit au plus proche.
#
#   use multimedia.core.timestamp as ts
#   b := ts.TimeBase(1, 48000)
#   t := ts.Timestamp(96000, b)
#   print(t.seconds(), t.rescale(ts.MILLIS).pts)      # 2.0 2000
#   print(ts.format_clock(3723.5))                    # 01:02:03.500
#   print(ts.parse_clock("00:01:02,250"))             # 62.25  (virgule SRT ou point WebVTT)
#   d := ts.from_seconds(1.5, ts.MICROS)              # Timestamp(1500000, 1/1000000)
#
# Erreurs : FormatError (base nulle ou négative, texte d'horloge invalide).

from core use len, type, to_int, to_float, gcd
use string as _s
use multimedia.core.errors as merr

class TimeBase:
    func init(num=1, den=1000):
        if type(num) != "int" or type(den) != "int" or num <= 0 or den <= 0:
            merr.fail(merr.FORMAT, "base de temps invalide : " + str(num) + "/" + str(den))
        g := gcd(num, den)
        self.num = num // g
        self.den = den // g

    func seconds(pts):
        return 1.0 * pts * self.num / self.den

    func equals(other):
        return self.num == other.num and self.den == other.den

    func describe():
        return str(self.num) + "/" + str(self.den)

MILLIS := TimeBase(1, 1000)
MICROS := TimeBase(1, 1000000)
MPEG := TimeBase(1, 90000)

func for_rate(rate):
    return TimeBase(1, rate)

# Division entière arrondie au plus proche (demi vers +infini), valable pour a de signe quelconque.
func _div_round(a, b):
    if a >= 0:
        return (2 * a + b) // (2 * b)
    return -((2 * (-a) + b - 1) // (2 * b))

# pts exprimé dans `src` -> pts dans `dst`.
func rescale_pts(pts, src, dst):
    if src.equals(dst):
        return pts
    return _div_round(pts * src.num * dst.den, src.den * dst.num)

class Timestamp:
    func init(pts, base=null):
        if type(pts) != "int":
            pts = to_int(pts)
        self.pts = pts
        self.base = base if base != null else MILLIS

    func seconds():
        return self.base.seconds(self.pts)

    func rescale(base):
        return Timestamp(rescale_pts(self.pts, self.base, base), base)

    func plus(other):
        return Timestamp(self.pts + rescale_pts(other.pts, other.base, self.base), self.base)

    func minus(other):
        return Timestamp(self.pts - rescale_pts(other.pts, other.base, self.base), self.base)

    func plus_pts(n):
        return Timestamp(self.pts + n, self.base)

    # -1, 0 ou 1, comparaison exacte (produits en croix, sans flottants).
    func compare(other):
        a := self.pts * self.base.num * other.base.den
        b := other.pts * other.base.num * self.base.den
        if a < b:
            return -1
        if a > b:
            return 1
        return 0

    func equals(other):
        return self.compare(other) == 0

    func describe():
        return format_clock(self.seconds()) + " (" + str(self.pts) + " × " + self.base.describe() + ")"

func from_seconds(seconds, base=null):
    b := base if base != null else MILLIS
    return Timestamp(_div_round(to_int(seconds * 1000000 + (0.5 if seconds >= 0 else -0.5)) * b.den, 1000000 * b.num), b)

ZERO := Timestamp(0, MILLIS)

func _pad(n, w):
    s := str(n)
    while len(s) < w:
        s = "0" + s
    return s

# Secondes -> « HH:MM:SS.mmm » (sep : séparateur des millisecondes, « , » pour SRT).
func format_clock(seconds, sep="."):
    neg := seconds < 0
    ms := to_int(seconds * 1000 + (-0.5 if neg else 0.5))
    if neg:
        ms = -ms
    h := ms // 3600000
    m := (ms // 60000) % 60
    s := (ms // 1000) % 60
    out := _pad(h, 2) + ":" + _pad(m, 2) + ":" + _pad(s, 2) + sep + _pad(ms % 1000, 3)
    return "-" + out if neg else out

func _digits(text, what):
    t := _s.trim(text)
    if len(t) == 0:
        merr.fail(merr.FORMAT, "horloge invalide : " + what)
    for c in _s.byte_unpack(t):
        if c < 48 or c > 57:
            merr.fail(merr.FORMAT, "horloge invalide : " + what)
    return to_int(t)

# « HH:MM:SS.mmm », « MM:SS.mmm », « HH:MM:SS,mmm » ou « SS » -> secondes (float).
func parse_clock(text):
    t := _s.replace(_s.trim(text), ",", ".")
    frac := 0.0
    dot := _s.find(t, ".")
    if dot >= 0:
        f := _s.substring(t, dot + 1, len(t))
        if len(f) == 0 or len(f) > 9:
            merr.fail(merr.FORMAT, "horloge invalide : " + text)
        frac = 1.0 * _digits(f, text)
        for i in 0..len(f):
            frac = frac / 10
        t = _s.substring(t, 0, dot)
    parts := _s.split(t, ":")
    if len(parts) > 3:
        merr.fail(merr.FORMAT, "horloge invalide : " + text)
    total := 0
    for i in 0..len(parts):
        v := _digits(parts[i], text)
        if i > 0 and v >= 60:
            merr.fail(merr.FORMAT, "horloge invalide (minutes ou secondes >= 60) : " + text)
        total = total * 60 + v
    return total + frac
