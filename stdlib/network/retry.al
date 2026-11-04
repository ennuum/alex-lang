# ALEX STANDARD LIBRARY — network.retry
#
# Nouvelles tentatives avec attente exponentielle et gigue, et disjoncteur (circuit breaker).
#
#   RetryPolicy    combien de fois, quelles erreurs, quelle attente : base * multiplier^(n-1), bornée par max_delay,
#                  avec gigue « pleine » ou proportionnelle (évite que tous les clients repartent ensemble).
#   retry(fn)      appelle fn() jusqu'au succès ou à l'épuisement des tentatives ; relance la DERNIÈRE erreur.
#   retry_async    même chose pour une fonction qui renvoie une tâche async.
#   CircuitBreaker coupe les appels vers un service qui échoue en série, puis le resonde après un délai.
#
# Par défaut, seules les erreurs passagères sont retentées (network.errors.is_transient : délai dépassé, connexion
# refusée ou coupée, réseau injoignable) : une erreur de protocole ou d'usage ne sert à rien de répéter.
#
# Exemple
#   use network.retry as rt
#   p := rt.RetryPolicy(5, 0.2)                     # 5 tentatives, 0.2 s puis 0.4, 0.8, 1.6...
#   r := rt.retry(() => http.get("http://service/api"), p)
#
#   cb := rt.CircuitBreaker(3, 30.0)
#   r := cb.call(() => client.get("/santé"))        # RetryError (« circuit ouvert ») après 3 échecs de suite

from core use len, type, to_int, to_float
from collections use append
use string as _s
use time as _time
use random as _rand
use asyncio as _aio
use network.errors as _err

class RetryPolicy:
    # max_attempts : nombre total d'appels (>= 1) ; base_delay / max_delay en secondes ; multiplier : facteur de
    # croissance ; jitter : "full" (attente tirée dans [0, d]), un réel 0..1 (± cette fraction) ou 0 (aucune) ;
    # retry_on : types d'erreurs retentés (null : erreurs passagères) ; retry_if : prédicat(erreur) prioritaire ;
    # statuses : statuts HTTP retentés par retry_response ; max_total : temps total maximal (secondes) ou null.
    func init(max_attempts=3, base_delay=0.1, max_delay=10.0, multiplier=2.0, jitter=0.1, retry_on=null, retry_if=null, statuses=null, max_total=null):
        if type(max_attempts) != "int" or max_attempts < 1:
            raise("ArgumentError", "network.retry.RetryPolicy : max_attempts entier >= 1 attendu")
        if base_delay < 0 or max_delay < 0 or multiplier < 1:
            raise("ArgumentError", "network.retry.RetryPolicy : délais >= 0 et multiplier >= 1 attendus")
        self.max_attempts = max_attempts
        self.base_delay = base_delay
        self.max_delay = max_delay
        self.multiplier = multiplier
        self.jitter = jitter
        self.retry_on = retry_on
        self.retry_if = retry_if
        self.statuses = statuses
        if statuses == null:
            self.statuses = [408, 425, 429, 500, 502, 503, 504]
        self.max_total = max_total

    # Attente avant la tentative numéro attempt + 1 (attempt >= 1 : tentatives déjà faites).
    func delay(attempt):
        d := self.base_delay * (self.multiplier ** (attempt - 1))
        if d > self.max_delay:
            d = self.max_delay
        if self.jitter == "full":
            return _rand.uniform(0.0, d)
        if type(self.jitter) == "int" or type(self.jitter) == "float":
            if self.jitter > 0:
                d = d * (1.0 + _rand.uniform(-self.jitter, self.jitter))
        if d < 0:
            d = 0.0
        return d

    # Vrai si l'erreur e mérite une nouvelle tentative.
    func should_retry(e):
        if self.retry_if != null:
            return self.retry_if(e)
        if self.retry_on != null:
            return _err.is_a(e, self.retry_on)
        return _err.is_transient(e)

    func retries_status(status):
        for s in self.statuses:
            if s == status:
                return true
        return false

    func str():
        return "RetryPolicy(" + str(self.max_attempts) + " tentatives, base " + str(self.base_delay) + " s, max " + str(self.max_delay) + " s)"

# Politique sans nouvelle tentative.
func no_retry():
    return RetryPolicy(1, 0.0, 0.0)

# Attentes successives (sans gigue) d'une politique : utile pour l'afficher ou la tester.
func schedule(policy):
    out := []
    i := 1
    while i < policy.max_attempts:
        d := policy.base_delay * (policy.multiplier ** (i - 1))
        if d > policy.max_delay:
            d = policy.max_delay
        append(out, d)
        i += 1
    return out

# Appelle fn() (sans argument) ; en cas d'erreur retentable, attend puis recommence. on_retry(erreur, tentative,
# attente) est appelé avant chaque attente. Relance la dernière erreur quand les tentatives sont épuisées.
# sleep : fonction d'attente (secondes), remplaçable dans les tests.
func retry(fn, policy=null, on_retry=null, sleep=null):
    p := policy
    if p == null:
        p = RetryPolicy()
    wait := sleep
    if wait == null:
        wait = _time.sleep
    start := _time.monotonic()
    attempt := 1
    while true:
        try:
            return fn()
        catch e:
            if attempt >= p.max_attempts or not p.should_retry(e):
                raise(e)
            d := p.delay(attempt)
            if p.max_total != null and _time.monotonic() - start + d > p.max_total:
                raise(e)
            if on_retry != null:
                on_retry(e, attempt, d)
            wait(d)
            attempt += 1

# Comme retry pour une réponse HTTP : refait la requête tant que le statut est dans policy.statuses (en respectant
# un Retry-After raisonnable). fn() renvoie un objet avec .status et .header(nom).
func retry_response(fn, policy=null, on_retry=null, sleep=null):
    p := policy
    if p == null:
        p = RetryPolicy()
    wait := sleep
    if wait == null:
        wait = _time.sleep
    attempt := 1
    while true:
        r := null
        try:
            r = fn()
        catch e:
            if attempt >= p.max_attempts or not p.should_retry(e):
                raise(e)
            d := p.delay(attempt)
            if on_retry != null:
                on_retry(e, attempt, d)
            wait(d)
            attempt += 1
            continue
        if attempt >= p.max_attempts or not p.retries_status(r.status):
            return r
        d := p.delay(attempt)
        ra := parse_retry_after(r.header("retry-after"))
        if ra != null:
            d = ra
            if d > p.max_delay:
                return r     # le serveur demande d'attendre plus que la politique ne l'accepte
        if on_retry != null:
            on_retry(r, attempt, d)
        wait(d)
        attempt += 1

# Version async : fn() renvoie une tâche (ou un futur) ; l'attente entre deux tentatives cède la main.
async func retry_async(fn, policy=null, on_retry=null):
    p := policy
    if p == null:
        p = RetryPolicy()
    attempt := 1
    while true:
        try:
            return await fn()
        catch e:
            if e.type == "CancelledError" or attempt >= p.max_attempts or not p.should_retry(e):
                raise(e)
            d := p.delay(attempt)
            if on_retry != null:
                on_retry(e, attempt, d)
            await _aio.sleep(d)
            attempt += 1

const _MONTHS := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

# Secondes d'attente demandées par un en-tête Retry-After (« 120 » ou une date HTTP), ou null.
func parse_retry_after(value, now=null):
    if value == null:
        return null
    v := _s.trim(str(value))
    if v == "":
        return null
    digits := true
    for c in v:
        if c < '0' or c > '9':
            digits = false
    if digits:
        return to_float(to_int(v))
    # IMF-fixdate : « Sun, 06 Nov 1994 08:49:37 GMT »
    parts := _s.split(v, " ")
    if len(parts) != 6:
        return null
    day := to_int(parts[1])
    month := -1
    i := 0
    while i < 12:
        if _s.lower(parts[2]) == _MONTHS[i]:
            month = i + 1
        i += 1
    year := to_int(parts[3])
    hms := _s.split(parts[4], ":")
    if month < 0 or len(hms) != 3:
        return null
    ts := _time.days_from_civil(year, month, day) * 86400 + to_int(hms[0]) * 3600 + to_int(hms[1]) * 60 + to_int(hms[2])
    t := now
    if t == null:
        t = _time.time()
    d := ts - t
    if d < 0:
        return 0.0
    return to_float(d)

# ---------------------------------------------------------------- disjoncteur

const CLOSED := "closed"
const OPEN := "open"
const HALF_OPEN := "half_open"

class CircuitBreaker:
    # failure_threshold : échecs consécutifs qui ouvrent le circuit ; reset_timeout : secondes avant d'autoriser
    # un appel d'essai (demi-ouvert) ; counts_as_failure(erreur) : prédicat (défaut : toute erreur).
    func init(failure_threshold=5, reset_timeout=30.0, counts_as_failure=null, clock=null):
        self.failure_threshold = failure_threshold
        self.reset_timeout = reset_timeout
        self.counts_as_failure = counts_as_failure
        self.clock = clock
        self.state = CLOSED
        self.failures = 0
        self.opened_at = 0.0
        self.successes = 0
        self.rejected = 0

    func _now():
        if self.clock != null:
            return self.clock()
        return _time.monotonic()

    # État courant ("closed", "open", "half_open") ; un circuit ouvert passe en demi-ouvert après reset_timeout.
    func current_state():
        if self.state == OPEN and self._now() - self.opened_at >= self.reset_timeout:
            self.state = HALF_OPEN
        return self.state

    func allow():
        return self.current_state() != OPEN

    func record_success():
        self.failures = 0
        self.successes += 1
        self.state = CLOSED

    func record_failure():
        self.failures += 1
        if self.state == HALF_OPEN or self.failures >= self.failure_threshold:
            self.state = OPEN
            self.opened_at = self._now()

    # Appelle fn() si le circuit le permet ; RetryError « circuit ouvert » sinon.
    func call(fn):
        if not self.allow():
            self.rejected += 1
            raise("RetryError", "circuit ouvert : appel refusé (" + str(self.failures) + " échecs consécutifs)")
        try:
            r := fn()
            self.record_success()
            return r
        catch e:
            if self.counts_as_failure == null or self.counts_as_failure(e):
                self.record_failure()
            raise(e)

    func reset():
        self.state = CLOSED
        self.failures = 0
