# ALEX STANDARD LIBRARY — web.css.animations
#
# Animations CSS : construction et analyse de la propriété animation, et SIMULATION d'une animation dans le
# temps (délai, durée, nombre d'itérations, direction, remplissage, fonction de temps) avec ses @keyframes
# (web.css.keyframes) — pour tester l'état d'un élément à un instant donné.
#
#   use web.css.animations as an
#   a := an.Animation("apparition", "300ms", "ease-out", 0, 1, "normal", "both")
#   a.to_css()                     # apparition 300ms ease-out 0ms 1 normal both
#   an.animation("spin", "1s", "linear", "infinite")    # {"animation": "spin 1s linear infinite"}
#   an.parse("pulse 2s ease-in-out 500ms infinite alternate")[0].iterations   # infinite
#   a.state(150)                   # ("actif", itération 0, progression avancée de l'image clé)
#   a.values_at(kf, 150)           # {"opacity": "0.6..."} (kf : Keyframes)
#   a.end_time()                   # 300.0
#
# Erreurs : CssValueError (animation mal formée).

from core use len, type, to_float, to_int
from collections use append
use string as _s
use web.css.css_errors as _err
use web.css.value as _value
use web.css.units as _units
use web.css.transitions as _tr

const DIRECTIONS := ["normal", "reverse", "alternate", "alternate-reverse"]
const FILL_MODES := ["none", "forwards", "backwards", "both"]
const PLAY_STATES := ["running", "paused"]

func _fail(msg):
    _err.value_error("animations", msg)

func _time(v):
    if type(v) == "int" or type(v) == "float":
        return _units.format_number(v) + "ms"
    return str(v)

func _ms(text):
    d := _units.parse(_s.trim(str(text)))
    if d.unit == "" and to_float(d.value) == 0.0:
        return 0.0
    if _units.kind_of(d.unit) != "time":
        _fail("durée invalide « " + str(text) + " »")
    return _units.to_ms(d)

class Animation:
    # iterations : nombre (fractions permises) ou "infinite".
    func init(name, duration=0, timing="ease", delay=0, iterations=1, direction="normal", fill_mode="none", play_state="running"):
        self.name = str(name)
        self.duration = _ms(_time(duration))
        self.timing = _tr.easing(timing)
        self.delay = _ms(_time(delay))
        if iterations == "infinite":
            self.iterations = "infinite"
        else:
            self.iterations = to_float(iterations)
            if self.iterations < 0:
                _fail("nombre d'itérations négatif")
        if not (direction in DIRECTIONS):
            _fail("direction inconnue « " + str(direction) + " »")
        if not (fill_mode in FILL_MODES):
            _fail("mode de remplissage inconnu « " + str(fill_mode) + " »")
        if not (play_state in PLAY_STATES):
            _fail("état inconnu « " + str(play_state) + " »")
        self.direction = direction
        self.fill_mode = fill_mode
        self.play_state = play_state

    func to_css():
        parts := [self.name, _units.format_number(self.duration) + "ms", self.timing.to_css(), _units.format_number(self.delay) + "ms", "infinite" if self.iterations == "infinite" else _units.format_number(self.iterations), self.direction, self.fill_mode]
        if self.play_state != "running":
            append(parts, self.play_state)
        return _s.join(" ", parts)

    func __str__():
        return self.to_css()

    func is_infinite():
        return self.iterations == "infinite"

    # Fin de l'effet actif (ms), ou null si infini.
    func end_time():
        if self.is_infinite():
            return null
        return self.delay + self.duration * self.iterations

    # État à t ms : (phase, itération, progression de l'image clé après direction et accélération, ou null).
    # phase : "avant", "actif", "après".
    func state(t):
        time := to_float(t)
        active := time - self.delay
        if active < 0:
            if self.fill_mode == "backwards" or self.fill_mode == "both":
                return ("avant", 0, self._directed(0, 0.0))
            return ("avant", 0, null)
        total := null if self.is_infinite() else self.duration * self.iterations
        if total != null and active >= total:
            if not (self.fill_mode == "forwards" or self.fill_mode == "both"):
                return ("après", 0, null)
            iters := self.iterations
            if iters == 0:
                return ("après", 0, self._directed(0, 0.0))
            whole := to_int(iters)
            frac := iters - whole
            if frac == 0:
                return ("après", whole - 1, self._directed(whole - 1, 1.0))
            return ("après", whole, self._directed(whole, frac))
        if self.duration <= 0:
            return ("actif", 0, self._directed(0, 1.0))
        it := to_int(active / self.duration)
        local := (active - it * self.duration) / self.duration
        return ("actif", it, self._directed(it, local))

    func _directed(iteration, local):
        forward := true
        d := self.direction
        if d == "reverse":
            forward = false
        elif d == "alternate":
            forward = iteration % 2 == 0
        elif d == "alternate-reverse":
            forward = iteration % 2 == 1
        p := local if forward else 1.0 - local
        return self.timing.at(p)

    # Valeurs des propriétés animées à t ms (dict vide hors de l'effet sans remplissage).
    func values_at(keyframes, t, base=null):
        st := self.state(t)
        if st[2] == null:
            return {}
        p := st[2]
        if p < 0:
            p = 0.0
        if p > 1:
            p = 1.0
        return keyframes.at(p, base)

# Animations d'une valeur de la propriété animation (plusieurs séparées par des virgules).
func parse(text):
    t := _s.trim(str(text))
    if t == "" or _s.lower(t) == "none":
        return []
    out := []
    for group in _value.parse(t).split_commas():
        name := null
        times := []
        timing := null
        iterations := null
        direction := null
        fill := null
        play := null
        for it in group:
            if isinstance(it, _value.Token) and it.kind == _value.WHITESPACE:
                continue
            s := it.to_css()
            ls := _s.lower(s)
            if isinstance(it, _value.Token) and it.kind == _value.DIMENSION and _units.kind_of(it.unit) == "time":
                append(times, s)
            elif isinstance(it, _value.Token) and it.kind == _value.NUMBER and iterations == null:
                iterations = to_float(it.value)
            elif ls == "infinite" and iterations == null:
                iterations = "infinite"
            elif timing == null and (isinstance(it, _value.Function) or ls in _tr.NAMED or ls in ["step-start", "step-end"]):
                timing = s
            elif ls in DIRECTIONS and direction == null:
                direction = ls
            elif ls in FILL_MODES and fill == null:
                fill = ls
            elif ls in PLAY_STATES and play == null:
                play = ls
            elif isinstance(it, _value.Token) and (it.kind == _value.IDENT or it.kind == _value.STRING) and name == null:
                name = it.value
            else:
                _fail("élément inattendu « " + s + " » dans une animation")
        if len(times) > 2:
            _fail("plus de deux durées dans « " + _value.serialize(group) + " »")
        append(out, Animation(name if name != null else "none", times[0] if len(times) > 0 else 0, timing if timing != null else "ease", times[1] if len(times) > 1 else 0, iterations if iterations != null else 1, direction if direction != null else "normal", fill if fill != null else "none", play if play != null else "running"))
    return out

func is_valid(text):
    try:
        parse(text)
        return true
    catch e:
        return false

# Déclaration animation (iterations : nombre ou "infinite").
func animation(name, duration="1s", timing="ease", iterations=null, direction=null, fill_mode=null, delay=null):
    parts := [str(name), _time(duration), _tr.easing(timing).to_css()]
    if delay != null:
        append(parts, _time(delay))
    if iterations != null:
        append(parts, str(iterations))
    if direction != null:
        append(parts, direction)
    if fill_mode != null:
        append(parts, fill_mode)
    return {"animation": _s.join(" ", parts)}

func pause():
    return {"animation-play-state": "paused"}

func none():
    return {"animation": "none"}

# Animation à déclencher au défilement (scroll-driven) sur une ligne de temps de vue.
func on_view(name, range_start="entry 0%", range_end="cover 40%", fill="both"):
    return {"animation": str(name) + " linear " + fill, "animation-timeline": "view()", "animation-range": range_start + " " + range_end}
