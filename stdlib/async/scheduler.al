# ALEX STANDARD LIBRARY — async.scheduler
#
# Planificateur de travaux sur la boucle async : une fois après un délai, à une heure, périodiquement, ou selon
# une expression CRON (minute heure jour mois jour-de-semaine). Les fonctions peuvent être ordinaires ou async.
#
#   use async.scheduler as sched
#   s := sched.Scheduler()
#   s.call_later(2.0, rappel)                         # dans 2 s
#   j := s.every(0.5, sonder, [capteur])              # toutes les 0,5 s
#   s.every(60, rapport, null, 10)                    # 10 fois seulement
#   s.cron("*/15 8-18 * * 1-5", sauvegarde)           # toutes les 15 min, 8 h-18 h, du lundi au vendredi
#   s.start()                                         # tâche de fond ; ou : await s.run(30) pendant 30 s
#   ...
#   j.cancel()
#   s.stop()
#
# Un travail n'est jamais exécuté deux fois en même temps : si une exécution async dure plus que la période, la
# suivante attend sa fin (pas de chevauchement). Une erreur dans un travail est gardée dans job.last_error et
# comptée dans job.errors ; elle n'arrête pas le planificateur (on_error(fn) pour être prévenu).
#
# Erreurs : ArgumentError (délai négatif, expression cron invalide), TypeError.

from core use len, type, to_int
from collections use append, contains
use string as _str
use asyncio
use os as _os
use time as _time

class Job:
    func init(scheduler, fn, args, when, interval, count, cron):
        self.scheduler = scheduler
        self.fn = fn
        self.args = args
        self.next_time = when       # horloge asyncio.now()
        self.interval = interval
        self.remaining = count      # null : sans limite
        self.cron = cron
        self.runs = 0
        self.errors = 0
        self.last_error = null
        self.cancelled = false
        self.running = false

    func cancel():
        self.cancelled = true
        self.scheduler._wake()

    func active():
        return not self.cancelled and (self.remaining == null or self.remaining > 0)

    # Secondes avant la prochaine exécution (null si terminé).
    func due_in():
        if not self.active():
            return null
        d := self.next_time - asyncio.now()
        if d < 0:
            return 0.0
        return d

func _call(fn, args):
    if args == null or len(args) == 0:
        return fn()
    if len(args) == 1:
        return fn(args[0])
    if len(args) == 2:
        return fn(args[0], args[1])
    if len(args) == 3:
        return fn(args[0], args[1], args[2])
    if len(args) == 4:
        return fn(args[0], args[1], args[2], args[3])
    raise("ArgumentError", "scheduler : 4 arguments au plus")

class Scheduler:
    func init():
        self._jobs = []
        self._wake_future = null
        self._task = null
        self._stop = false
        self._error_handler = null

    func _wake():
        if self._wake_future != null:
            asyncio.resolve(self._wake_future, true)

    func _add(job):
        append(self._jobs, job)
        self._wake()
        return job

    func call_later(delay, fn, args=null):
        if delay < 0:
            raise("ArgumentError", "Scheduler.call_later : délai négatif")
        return self._add(Job(self, fn, args, asyncio.now() + delay, null, 1, null))

    # À l'instant t de l'horloge système (secondes depuis 1970, comme os.time()).
    func call_at(t, fn, args=null):
        return self.call_later(_max(0, t - _os.time()), fn, args)

    # Toutes les interval secondes (première exécution après first_delay, par défaut interval) ; count fois.
    func every(interval, fn, args=null, count=null, first_delay=null):
        if interval <= 0:
            raise("ArgumentError", "Scheduler.every : période > 0 attendue")
        if first_delay == null:
            first_delay = interval
        return self._add(Job(self, fn, args, asyncio.now() + first_delay, interval, count, null))

    # Expression cron à 5 champs (heure locale) : minute heure jour-du-mois mois jour-de-la-semaine (0 = dimanche).
    func cron(expression, fn, args=null, count=null):
        spec := parse_cron(expression)
        job := Job(self, fn, args, 0, null, count, spec)
        job.next_time = asyncio.now() + seconds_until_next(spec, _os.time())
        return self._add(job)

    func on_error(fn):
        self._error_handler = fn
        return self

    func cancel(job):
        job.cancel()

    func cancel_all():
        for j in self._jobs:
            j.cancelled = true
        self._wake()

    func jobs():
        return [j for j in self._jobs if j.active()]

    func _reschedule(job):
        job.runs += 1
        if job.remaining != null:
            job.remaining -= 1
        if job.interval != null:
            job.next_time = job.next_time + job.interval
            now := asyncio.now()
            if job.next_time < now:     # retard (exécution longue) : on rattrape sans rafale
                job.next_time = now
        elif job.cron != null:
            job.next_time = asyncio.now() + seconds_until_next(job.cron, _os.time())

    # Fait tourner le planificateur pendant duration secondes (null : jusqu'à stop() ou plus aucun travail).
    func run(duration=null):
        return _run(self, duration)

    # Lance run() en tâche de fond ; renvoie la tâche.
    func start():
        if self._task == null or asyncio.done(self._task):
            self._stop = false
            self._task = _run(self, null, true)
        return self._task

    func stop():
        self._stop = true
        self._wake()

async func _execute(s, job):
    job.running = true
    try:
        r := _call(job.fn, job.args)
        if asyncio.is_future(r):
            await r
    catch e:
        job.errors += 1
        job.last_error = e.type + ": " + e.message
        if s._error_handler != null:
            h := s._error_handler
            h(job, e.type, e.message)
    finally:
        job.running = false
        s._wake()

async func _run(s, duration, forever=false):
    end := null
    if duration != null:
        end = asyncio.now() + duration
    while not s._stop:
        s._jobs = [j for j in s._jobs if j.active()]
        if len(s._jobs) == 0 and not forever and end == null:
            return
        now := asyncio.now()
        if end != null and now >= end:
            return
        nearest := null
        for j in s._jobs:
            if j.running:
                continue
            if j.next_time <= now:
                s._reschedule(j)
                _execute(s, j)
            elif nearest == null or j.next_time < nearest:
                nearest = j.next_time
        wait := 3600.0
        if nearest != null:
            wait = nearest - now
        if end != null and end - now < wait:
            wait = end - now
        if wait < 0:
            wait = 0
        s._wake_future = asyncio.future()
        await asyncio.race([asyncio.sleep(wait), s._wake_future])
        s._wake_future = null

func _max(a, b):
    if a > b:
        return a
    return b

# ---------------------------------------------------------------- cron

func _parse_field(text, lo, hi, name):
    out := []
    for part in _str.split(text, ","):
        step := 1
        rng := part
        k := _str.find(part, "/")
        if k >= 0:
            rng = _str.substring(part, 0, k)
            step = _int(_str.substring(part, k + 1, len(part)), name)
            if step < 1:
                raise("ArgumentError", "cron : pas invalide dans '" + name + "'")
        a := lo
        b := hi
        if rng != "*":
            d := _str.find(rng, "-")
            if d >= 0:
                a = _int(_str.substring(rng, 0, d), name)
                b = _int(_str.substring(rng, d + 1, len(rng)), name)
            else:
                a = _int(rng, name)
                if k < 0:
                    b = a
        if a < lo or b > hi or a > b:
            raise("ArgumentError", "cron : valeur hors de " + str(lo) + ".." + str(hi) + " dans '" + name + "' (" + part + ")")
        v := a
        while v <= b:
            if not contains(out, v):
                append(out, v)
            v += step
    return out

func _int(s, name):
    try:
        return to_int(s)
    catch e:
        raise("ArgumentError", "cron : nombre invalide '" + s + "' dans '" + name + "'")

# {"minute": [...], "hour": [...], "day": [...], "month": [...], "weekday": [...], "day_any", "weekday_any"}
func parse_cron(expression):
    if type(expression) != "str":
        raise("TypeError", "cron : expression (str) attendue")
    fields := [f for f in _str.split(_str.trim(expression), " ") if f != ""]
    if len(fields) != 5:
        raise("ArgumentError", "cron : 5 champs attendus (minute heure jour mois jour-de-semaine), obtenu '" + expression + "'")
    wd := _parse_field(fields[4], 0, 7, "jour-de-semaine")
    if contains(wd, 7) and not contains(wd, 0):
        append(wd, 0)
    return {"minute": _parse_field(fields[0], 0, 59, "minute"), "hour": _parse_field(fields[1], 0, 23, "heure"),
            "day": _parse_field(fields[2], 1, 31, "jour"), "month": _parse_field(fields[3], 1, 12, "mois"),
            "weekday": wd, "day_any": fields[2] == "*", "weekday_any": fields[4] == "*"}

func _day_ok(spec, t):
    dom := contains(spec["day"], t["day"])
    wd := (t["weekday"] + 1) % 7      # time : lundi = 0 ; cron : dimanche = 0
    dow := contains(spec["weekday"], wd)
    # Règle de cron : si les deux champs jour sont restreints, l'un OU l'autre suffit.
    if not spec["day_any"] and not spec["weekday_any"]:
        return dom or dow
    return dom and dow

# Secondes (> 0) entre now (secondes depuis 1970) et la prochaine minute qui correspond (heure locale). Saute
# des journées ou des heures entières quand le mois, le jour ou l'heure ne correspondent pas.
func seconds_until_next(spec, now):
    start := (_to_int_floor(now) // 60 + 1) * 60
    t := start
    limit := start + 366 * 24 * 3600 * 5
    while t < limit:
        f := _time.localtime(t)
        into_day := f["hour"] * 3600 + f["minute"] * 60 + f["second"]
        if not contains(spec["month"], f["month"]) or not _day_ok(spec, f):
            t = t + 86400 - into_day
        elif not contains(spec["hour"], f["hour"]):
            t = t + 3600 - f["minute"] * 60 - f["second"]
        elif not contains(spec["minute"], f["minute"]):
            t += 60
        else:
            return t - now
    raise("ArgumentError", "cron : aucune date ne correspond dans les cinq prochaines années")

func _to_int_floor(x):
    return to_int(x)

# Prochaine date (secondes depuis 1970) qui correspond à l'expression.
func next_run(expression, now=null):
    if now == null:
        now = _os.time()
    return now + seconds_until_next(parse_cron(expression), now)
