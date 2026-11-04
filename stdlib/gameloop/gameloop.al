# ALEX STANDARD LIBRARY — gameloop
#
# Boucle de jeu à pas de temps FIXE pour la simulation (physique, logique) et pas variable pour l'affichage, avec
# interpolation, delta time borné, échelle de temps, pause, plafonnement du framerate, minuteries, planificateur et
# interpolations (tweens / easings). ALEX pur ; l'horloge est injectable, donc tout est testable sans attendre.
#
#   use gameloop
#   func update(dt):                 # appelée à pas FIXE (ici 1/60 s), 0, 1 ou plusieurs fois par image
#       world.step(dt)
#   func render(alpha):              # appelée une fois par image ; alpha dans [0, 1) = avancement vers le prochain pas
#       draw(lerp(prev, cur, alpha))
#   loop := gameloop.GameLoop(update, render, 1.0 / 60.0)
#   loop.run()                       # jusqu'à loop.stop() ; loop.run(null, 600) pour 600 images seulement
#   # ou, avec sa propre boucle d'événements : à chaque image  loop.frame()   (mesure le temps lui-même)
#   #                                           ou, déterministe : loop.advance(0.016)
#
# ALGORITHME (« Fix your timestep ») : le temps réel écoulé depuis l'image précédente (borné par max_frame_time
# pour éviter la « spirale de la mort » après une pause du débogueur) multiplié par time_scale est ajouté à un
# accumulateur ; tant que l'accumulateur contient un pas complet, update(fixed_dt) est appelée. Le reste, divisé par
# fixed_dt, est l'alpha d'interpolation passé à render. Au plus max_steps pas sont joués par image ; le surplus est
# abandonné (le jeu ralentit plutôt que de geler).
#
# Erreurs : ValueError (paramètre invalide), TypeError.

use math
use time
from core use len, is_int, is_float
from collections use append, pop

const VERSION := "1.0.0"

# =============================================================================
# GameLoop
# =============================================================================

class GameLoop:
    func init(update=null, render=null, fixed_dt=0.016666666666666666, max_frame_time=0.25, max_steps=8, clock=null):
        if fixed_dt <= 0:
            raise("ValueError", "gameloop.GameLoop : fixed_dt doit être > 0")
        if max_frame_time <= 0 or max_steps < 1:
            raise("ValueError", "gameloop.GameLoop : max_frame_time > 0 et max_steps >= 1 requis")
        self.update_fn = update
        self.render_fn = render
        self.fixed_dt = fixed_dt * 1.0
        self.max_frame_time = max_frame_time * 1.0
        self.max_steps = max_steps
        self.clock = clock
        self.time_scale = 1.0
        self.paused = false
        self.running = false
        self.target_fps = null
        self.sleep_fn = null
        self.accumulator = 0.0
        self.alpha = 0.0
        self.sim_time = 0.0              # temps de simulation écoulé (somme des pas fixes)
        self.real_time = 0.0             # temps réel cumulé (après bornage)
        self.step_count = 0              # nombre total de pas fixes joués
        self.frame_count = 0
        self.dropped_time = 0.0          # temps abandonné faute de pouvoir rattraper
        self.delta = 0.0                 # dernier delta réel (après bornage, avant time_scale)
        self.fps = 0.0                   # images par seconde, lissées
        self.scheduler = Scheduler()
        self._last = null
        self._fps_acc = 0.0
        self._fps_frames = 0

    func _now():
        if self.clock != null:
            return self.clock()
        return time.monotonic()

    # Fait avancer le jeu de real_dt secondes de temps réel (déterministe : n'utilise aucune horloge).
    # Renvoie le nombre de pas fixes joués.
    func advance(real_dt):
        if real_dt < 0:
            raise("ValueError", "gameloop.GameLoop.advance : durée négative")
        dt := real_dt * 1.0
        if dt > self.max_frame_time:
            dt = self.max_frame_time
        self.delta = dt
        self.real_time = self.real_time + dt
        self.frame_count += 1
        # lissage du fps sur ~0.5 s
        self._fps_acc = self._fps_acc + dt
        self._fps_frames += 1
        if self._fps_acc >= 0.5:
            self.fps = self._fps_frames / self._fps_acc
            self._fps_acc = 0.0
            self._fps_frames = 0
        steps := 0
        if not self.paused:
            self.accumulator = self.accumulator + dt * self.time_scale
            while self.accumulator + 0.000000000001 >= self.fixed_dt and steps < self.max_steps:
                if self.update_fn != null:
                    self.update_fn(self.fixed_dt)
                self.scheduler.update(self.fixed_dt)
                self.accumulator = self.accumulator - self.fixed_dt
                self.sim_time = self.sim_time + self.fixed_dt
                self.step_count += 1
                steps += 1
            if self.accumulator < 0.0:
                self.accumulator = 0.0
            if steps == self.max_steps and self.accumulator + 0.000000000001 >= self.fixed_dt:
                # on n'arrive pas à rattraper : le temps restant est abandonné
                self.dropped_time = self.dropped_time + self.accumulator
                self.accumulator = 0.0
        self.alpha = self.accumulator / self.fixed_dt
        if self.alpha > 1.0:
            self.alpha = 1.0
        if self.render_fn != null:
            self.render_fn(self.alpha)
        return steps

    # Une image mesurée avec l'horloge (la première mesure un delta nul). Renvoie le nombre de pas fixes joués.
    func frame():
        now := self._now()
        d := 0.0
        if self._last != null:
            d = now - self._last
            if d < 0.0:
                d = 0.0
        self._last = now
        return self.advance(d)

    # Boucle jusqu'à stop(), max_frames images ou max_seconds de temps réel. Plafonne le framerate si target_fps est défini.
    func run(max_frames=null, max_seconds=null):
        self.running = true
        self._last = null
        started := self.real_time
        frames := 0
        while self.running:
            t0 := self._now()
            self.frame()
            frames += 1
            if max_frames != null and frames >= max_frames:
                break
            if max_seconds != null and self.real_time - started >= max_seconds:
                break
            if self.target_fps != null and self.target_fps > 0:
                spent := self._now() - t0
                wait := 1.0 / self.target_fps - spent
                if wait > 0.0:
                    if self.sleep_fn != null:
                        self.sleep_fn(wait)
                    else:
                        time.sleep(wait)
        self.running = false
        return frames

    func stop():
        self.running = false

    func pause():
        self.paused = true

    func resume():
        self.paused = false
        # l'horloge a continué : on ne rattrape pas le temps passé en pause
        self._last = null

    # Rejoue la dernière interpolation : état = lerp(précédent, courant, alpha).
    func interpolate(previous, current):
        return previous + (current - previous) * self.alpha

    # Remet les compteurs à zéro (pas le planificateur).
    func reset():
        self.accumulator = 0.0
        self.alpha = 0.0
        self.sim_time = 0.0
        self.real_time = 0.0
        self.step_count = 0
        self.frame_count = 0
        self.dropped_time = 0.0
        self._last = null

# =============================================================================
# Timer
# =============================================================================

# Minuterie à avancer avec update(dt). repeat = true : se réarme (et peut se déclencher plusieurs fois dans un gros dt).
class Timer:
    func init(duration, repeat=false, callback=null):
        if duration <= 0:
            raise("ValueError", "gameloop.Timer : durée > 0 requise")
        self.duration = duration * 1.0
        self.repeat = repeat
        self.callback = callback
        self.elapsed = 0.0
        self.finished = false
        self.running = true
        self.fired = 0

    # Renvoie le nombre de déclenchements pendant ce pas.
    func update(dt):
        if not self.running or self.finished:
            return 0
        self.elapsed = self.elapsed + dt
        n := 0
        while self.elapsed + 0.000000000001 >= self.duration:
            n += 1
            self.fired += 1
            if self.callback != null:
                self.callback()
            if self.repeat:
                self.elapsed = self.elapsed - self.duration
                if self.elapsed < 0.0:
                    self.elapsed = 0.0
            else:
                self.elapsed = self.duration
                self.finished = true
                break
        return n

    func progress():
        p := self.elapsed / self.duration
        if p > 1.0:
            return 1.0
        return p

    func remaining():
        r := self.duration - self.elapsed
        if r < 0.0:
            return 0.0
        return r

    func pause():
        self.running = false

    func resume():
        self.running = true

    func reset():
        self.elapsed = 0.0
        self.finished = false
        self.running = true

# =============================================================================
# Scheduler
# =============================================================================

# Actions différées : after(délai, fn), every(intervalle, fn). update(dt) les fait avancer (GameLoop l'appelle à chaque pas
# fixe : le temps planifié est donc du temps de SIMULATION, il s'arrête en pause).
class Scheduler:
    func init():
        self._tasks = []
        self._next_id = 1
        self.time = 0.0

    func after(delay, fn):
        return self._add(delay, 0.0, fn)

    func every(interval, fn, first_delay=null):
        if interval <= 0:
            raise("ValueError", "gameloop.Scheduler.every : intervalle > 0 requis")
        d := interval
        if first_delay != null:
            d = first_delay
        return self._add(d, interval, fn)

    func _add(delay, interval, fn):
        tid := self._next_id
        self._next_id += 1
        append(self._tasks, {"id": tid, "due": self.time + delay, "interval": interval, "fn": fn, "alive": true})
        return tid

    func cancel(task_id):
        for t in self._tasks:
            if t["id"] == task_id and t["alive"]:
                t["alive"] = false
                return true
        return false

    func pending():
        n := 0
        for t in self._tasks:
            if t["alive"]:
                n += 1
        return n

    # Avance de dt : exécute les actions échues dans l'ordre chronologique. Renvoie le nombre d'exécutions.
    func update(dt):
        self.time = self.time + dt
        ran := 0
        guard := 0
        while true:
            best := null
            for t in self._tasks:
                if t["alive"] and t["due"] <= self.time + 0.000000000001:
                    if best == null or t["due"] < best["due"]:
                        best = t
            if best == null:
                break
            if best["interval"] > 0.0:
                best["due"] = best["due"] + best["interval"]
            else:
                best["alive"] = false
            best["fn"]()
            ran += 1
            guard += 1
            if guard > 100000:
                raise("ValueError", "gameloop.Scheduler.update : actions périodiques en boucle")
        kept := []
        for t in self._tasks:
            if t["alive"]:
                append(kept, t)
        self._tasks = kept
        return ran

# =============================================================================
# Easings
# =============================================================================
# Fonctions d'interpolation t -> t' pour t dans [0, 1] (0 -> 0, 1 -> 1). Hors de [0, 1], t est borné.

func _c01(t):
    if t < 0.0:
        return 0.0
    if t > 1.0:
        return 1.0
    return t

func linear(t):
    return _c01(t)

func ease_in_quad(t):
    x := _c01(t)
    return x * x

func ease_out_quad(t):
    x := _c01(t)
    return 1.0 - (1.0 - x) * (1.0 - x)

func ease_in_out_quad(t):
    x := _c01(t)
    if x < 0.5:
        return 2.0 * x * x
    return 1.0 - 2.0 * (1.0 - x) * (1.0 - x)

func ease_in_cubic(t):
    x := _c01(t)
    return x * x * x

func ease_out_cubic(t):
    x := 1.0 - _c01(t)
    return 1.0 - x * x * x

func ease_in_out_cubic(t):
    x := _c01(t)
    if x < 0.5:
        return 4.0 * x * x * x
    y := 1.0 - x
    return 1.0 - 4.0 * y * y * y

func ease_in_sine(t):
    return 1.0 - math.cos(_c01(t) * math.PI / 2.0)

func ease_out_sine(t):
    return math.sin(_c01(t) * math.PI / 2.0)

func ease_in_out_sine(t):
    return 0.5 - 0.5 * math.cos(math.PI * _c01(t))

func ease_in_expo(t):
    x := _c01(t)
    if x == 0.0:
        return 0.0
    return math.pow(2.0, 10.0 * x - 10.0)

func ease_out_expo(t):
    x := _c01(t)
    if x == 1.0:
        return 1.0
    return 1.0 - math.pow(2.0, 0.0 - 10.0 * x)

func ease_in_back(t):
    x := _c01(t)
    c1 := 1.70158
    return (c1 + 1.0) * x * x * x - c1 * x * x

func ease_out_back(t):
    x := _c01(t) - 1.0
    c1 := 1.70158
    return 1.0 + (c1 + 1.0) * x * x * x + c1 * x * x

func ease_out_elastic(t):
    x := _c01(t)
    if x == 0.0 or x == 1.0:
        return x
    return math.pow(2.0, 0.0 - 10.0 * x) * math.sin((x * 10.0 - 0.75) * 2.0943951023931953) + 1.0

func ease_out_bounce(t):
    x := _c01(t)
    n1 := 7.5625
    d1 := 2.75
    if x < 1.0 / d1:
        return n1 * x * x
    if x < 2.0 / d1:
        y := x - 1.5 / d1
        return n1 * y * y + 0.75
    if x < 2.5 / d1:
        y := x - 2.25 / d1
        return n1 * y * y + 0.9375
    y := x - 2.625 / d1
    return n1 * y * y + 0.984375

func ease_in_bounce(t):
    return 1.0 - ease_out_bounce(1.0 - _c01(t))

# Fonction d'easing par son nom ("linear", "in_quad", "out_cubic", "in_out_sine", "out_bounce"...).
func easing(name):
    if name == "linear":
        return linear
    if name == "in_quad":
        return ease_in_quad
    if name == "out_quad":
        return ease_out_quad
    if name == "in_out_quad":
        return ease_in_out_quad
    if name == "in_cubic":
        return ease_in_cubic
    if name == "out_cubic":
        return ease_out_cubic
    if name == "in_out_cubic":
        return ease_in_out_cubic
    if name == "in_sine":
        return ease_in_sine
    if name == "out_sine":
        return ease_out_sine
    if name == "in_out_sine":
        return ease_in_out_sine
    if name == "in_expo":
        return ease_in_expo
    if name == "out_expo":
        return ease_out_expo
    if name == "in_back":
        return ease_in_back
    if name == "out_back":
        return ease_out_back
    if name == "out_elastic":
        return ease_out_elastic
    if name == "in_bounce":
        return ease_in_bounce
    if name == "out_bounce":
        return ease_out_bounce
    raise("ValueError", "gameloop.easing : fonction '" + name + "' inconnue")

# =============================================================================
# Tween
# =============================================================================

# Interpole un nombre OU une liste de nombres (vecteurs) de `start` à `end` en `duration` secondes.
# on_update(valeur) à chaque pas, on_complete() à la fin. Avancer avec update(dt) ; value() donne la valeur courante.
class Tween:
    func init(start, end, duration, easing_fn=null, on_update=null, on_complete=null):
        if duration <= 0:
            raise("ValueError", "gameloop.Tween : durée > 0 requise")
        self.start = start
        self.end = end
        self.duration = duration * 1.0
        self.easing_fn = easing_fn
        if easing_fn == null:
            self.easing_fn = linear
        self.on_update = on_update
        self.on_complete = on_complete
        self.elapsed = 0.0
        self.finished = false
        self.delay = 0.0

    func value():
        k := self.easing_fn(self.elapsed / self.duration)
        if is_int(self.start) or is_float(self.start):
            return self.start + (self.end - self.start) * k
        out := []
        i := 0
        while i < len(self.start):
            append(out, self.start[i] + (self.end[i] - self.start[i]) * k)
            i += 1
        return out

    func update(dt):
        if self.finished:
            return null
        d := dt
        if self.delay > 0.0:
            if self.delay >= d:
                self.delay = self.delay - d
                return null
            d = d - self.delay
            self.delay = 0.0
        self.elapsed = self.elapsed + d
        if self.elapsed >= self.duration:
            self.elapsed = self.duration
            self.finished = true
        if self.on_update != null:
            self.on_update(self.value())
        if self.finished and self.on_complete != null:
            self.on_complete()

    func reset():
        self.elapsed = 0.0
        self.finished = false

# =============================================================================
# Utilitaires
# =============================================================================

# Convertit un delta en secondes et le borne : à utiliser avec une horloge « brute ».
func clamp_delta(dt, max_dt=0.25):
    if dt < 0.0:
        return 0.0
    if dt > max_dt:
        return max_dt
    return dt

# Nombre de pas fixes que contient une durée.
func steps_in(duration, fixed_dt):
    return math.floor(duration / fixed_dt + 0.000000000001)
