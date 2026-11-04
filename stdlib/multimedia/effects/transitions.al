# ALEX STANDARD LIBRARY — multimedia.effects.transitions
#
# Transitions entre deux plans, pour une progression t de 0 (tout A) à 1 (tout B) :
#   images : crossfade (fondu enchaîné), fade_to (fondu vers une couleur), wipe (volet gauche->droite,
#   haut->bas...), dissolve (fondu par points, pseudo-aléatoire reproductible), slide (glissement) ;
#   audio : crossfade à puissance constante (ou linéaire) entre deux blocs, fade_in / fade_out ;
#   courbes : linear, ease_in, ease_out, ease_in_out, smoothstep.
#
#   use multimedia.effects.transitions as tr
#   img := tr.crossfade(a, b, tr.ease("ease_in_out", 0.3))
#   son := tr.audio_crossfade(fin_a, debut_b, 2)
#
# Erreurs : FormatError (images de tailles différentes, direction ou courbe inconnue).

from core use len, to_int
from collections use append
use math as _m
use multimedia.core.errors as merr
use multimedia.image.image as mi
use multimedia.image.convert as cv

func ease(curve, t):
    x := 0.0 if t < 0 else (1.0 if t > 1 else t)
    if curve == "linear":
        return x
    if curve == "ease_in":
        return x * x
    if curve == "ease_out":
        return 1.0 - (1.0 - x) * (1.0 - x)
    if curve == "ease_in_out":
        return 2 * x * x if x < 0.5 else 1.0 - 2 * (1.0 - x) * (1.0 - x)
    if curve == "smoothstep":
        return x * x * (3.0 - 2.0 * x)
    merr.fail(merr.FORMAT, "courbe inconnue : " + str(curve))

func _same(a, b):
    if a.width != b.width or a.height != b.height:
        merr.fail(merr.FORMAT, "transition entre images de tailles différentes : " + a.describe() + " / " + b.describe())
    if a.mode == b.mode:
        return [a, b]
    m := "rgba" if a.mode == "rgba" or b.mode == "rgba" else "rgb"
    return [cv.to_mode(a, m), cv.to_mode(b, m)]

func crossfade(a, b, t):
    p := _same(a, b)
    x := 0.0 if t < 0 else (1.0 if t > 1 else t)
    w := to_int(x * 256 + 0.5)
    pa := p[0].pixels
    pb := p[1].pixels
    out := [(pa[k] * (256 - w) + pb[k] * w + 128) >> 8 for k in 0..len(pa)]
    return mi.Image(a.width, a.height, p[0].mode, out)

func fade_to(a, color, t):
    c := mi.new(a.width, a.height, a.mode, color if len(color) == a.channels else ([color[0]] if a.channels == 1 else (color + [255] if a.channels == 4 else color)))
    return crossfade(a, c, t)

func wipe(a, b, t, direction="left"):
    p := _same(a, b)
    x := 0.0 if t < 0 else (1.0 if t > 1 else t)
    out := p[0].copy()
    if direction == "left" or direction == "right":
        edge := to_int(a.width * x + 0.5)
        for y in 0..a.height:
            for xx in 0..a.width:
                take := xx < edge if direction == "left" else xx >= a.width - edge
                if take:
                    out.set(xx, y, p[1].get(xx, y))
    elif direction == "down" or direction == "up":
        edge := to_int(a.height * x + 0.5)
        for y in 0..a.height:
            take := y < edge if direction == "down" else y >= a.height - edge
            if take:
                for xx in 0..a.width:
                    out.set(xx, y, p[1].get(xx, y))
    else:
        merr.fail(merr.FORMAT, "direction inconnue : " + str(direction))
    return out

func dissolve(a, b, t, seed=7):
    p := _same(a, b)
    x := 0.0 if t < 0 else (1.0 if t > 1 else t)
    out := p[0].copy()
    state := seed & 0x7FFFFFFF
    thr := to_int(x * 1000)
    for y in 0..a.height:
        for xx in 0..a.width:
            state = (state * 1103515245 + 12345) & 0x7FFFFFFF
            if state % 1000 < thr:
                out.set(xx, y, p[1].get(xx, y))
    return out

func slide(a, b, t):
    p := _same(a, b)
    x := 0.0 if t < 0 else (1.0 if t > 1 else t)
    off := to_int(a.width * x + 0.5)
    out := p[0].copy()
    for y in 0..a.height:
        for xx in 0..a.width:
            sx := xx + off
            if sx < a.width:
                out.set(xx, y, p[0].get(sx, y))
            else:
                out.set(xx, y, p[1].get(sx - a.width, y))
    return out

# Fondu enchaîné audio : a se termine pendant que b commence (même longueur), puissance constante par défaut.
func audio_crossfade(a, b, channels=1, law="constant_power"):
    if len(a) != len(b):
        merr.fail(merr.FORMAT, "fondu audio : blocs de longueurs différentes")
    n := len(a) // channels
    out := []
    for i in 0..n:
        t := (i + 0.5) / n
        ga := 0.0
        gb := 0.0
        if law == "constant_power":
            ga = _m.cos(t * _m.PI / 2)
            gb = _m.sin(t * _m.PI / 2)
        elif law == "linear":
            ga = 1.0 - t
            gb = t
        else:
            merr.fail(merr.FORMAT, "loi de fondu inconnue : " + str(law))
        for c in 0..channels:
            append(out, a[i * channels + c] * ga + b[i * channels + c] * gb)
    return out

func audio_fade(x, channels=1, fade_in=true, curve="linear"):
    n := len(x) // channels
    out := []
    for i in 0..n:
        g := ease(curve, (i + 0.5) / n)
        if not fade_in:
            g = 1.0 - g
        for c in 0..channels:
            append(out, x[i * channels + c] * g)
    return out
