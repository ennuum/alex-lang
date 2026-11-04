# ALEX STANDARD LIBRARY — multimedia.playback.seek
#
# Calcul des positions de recherche temporelle, indépendant du lecteur :
#   absolute(t, durée)            borné à [0, durée] ;
#   relative(pos, delta, durée)   avance / recul (± 10 s...) ;
#   percent(p, durée)             0..100 % ;
#   frame_aligned(t, fréquence)   au début de trame (audio) ou d'image (vidéo) le plus proche ;
#   keyframe_before(t, clés)      dernière image clé <= t (vidéo : on décode depuis une image clé) ;
#   chapter(pos, chapitres, sens) début du chapitre suivant (+1) ou précédent (-1).
#
#   use multimedia.playback.seek as sk
#   cible := sk.relative(lecteur.position(), -10.0, lecteur.duration())
#   print(sk.parse("1:30"), sk.parse("+15"), sk.parse("50%"))   # instants ou décalages, cf. resolve
#
# Erreurs : FormatError (texte de position illisible, fréquence invalide).

from core use len, to_int, to_float
use string as _s
use multimedia.core.errors as merr
use multimedia.core.timestamp as ts

func absolute(t, duration=null):
    if t < 0:
        return 0.0
    if duration != null and t > duration:
        return 1.0 * duration
    return 1.0 * t

func relative(pos, delta, duration=null):
    return absolute(pos + delta, duration)

func percent(p, duration):
    if duration == null:
        merr.fail(merr.FORMAT, "recherche en pourcentage sans durée connue")
    q := p
    if q < 0:
        q = 0
    if q > 100:
        q = 100
    return duration * q / 100.0

func frame_aligned(t, rate):
    if rate <= 0:
        merr.fail(merr.FORMAT, "fréquence invalide : " + str(rate))
    return 1.0 * to_int(t * rate + 0.5) / rate

func keyframe_before(t, keyframes):
    best := 0.0
    for k in keyframes:
        if k <= t and k > best:
            best = k
    return best

func chapter(pos, chapters, direction=1):
    if direction > 0:
        n := chapters.next_start(pos)
        return n
    return chapters.previous_start(pos)

# Texte -> ["abs", s] | ["rel", s] | ["pct", p] : « 90 », « 1:30 », « +15 », « -5 », « 50% ».
func parse(text):
    t := _s.trim(text)
    if len(t) == 0:
        merr.fail(merr.FORMAT, "position vide")
    if _s.ends_with(t, "%"):
        v := _s.trim(_s.substring(t, 0, len(t) - 1))
        try:
            return ["pct", to_float(v)]
        catch e:
            merr.fail(merr.FORMAT, "pourcentage illisible : " + text)
    if _s.starts_with(t, "+") or _s.starts_with(t, "-"):
        sign := 1.0 if _s.starts_with(t, "+") else -1.0
        return ["rel", sign * ts.parse_clock(_s.substring(t, 1, len(t)))]
    return ["abs", ts.parse_clock(t)]

func resolve(text, pos, duration=null):
    p := parse(text)
    if p[0] == "pct":
        return percent(p[1], duration)
    if p[0] == "rel":
        return relative(pos, p[1], duration)
    return absolute(p[1], duration)
