# ALEX STANDARD LIBRARY — multimedia.streaming.live
#
# Session en direct robuste : connexion par une fonction fournie, RECONNEXION automatique avec attente
# exponentielle bornée et gigue déterministe, nombre d'essais limité, état et statistiques (connexions, coupures,
# temps connecté), annulation. Sert d'enveloppe à un émetteur ou à un récepteur (sink / source).
#
#   use multimedia.streaming.live as live
#   s := live.LiveSession(() => snk.TcpAudioSink("serveur", 7000, fmt), live.Backoff(0.5, 10.0, 8))
#   s.write(bloc)                        # en cas d'erreur réseau : reconnecte puis réécrit le bloc
#   print(s.state, s.stats())
#   s.close()
#
# Erreurs : DeviceError (essais épuisés), CancelledError.

from core use len, to_int
use time as _t
use multimedia.core.errors as merr
use multimedia.core.cancellation as mc

const NETWORK_ERRORS := ["NetworkError", "TimeoutError", "IoError", "DeviceError", "DnsError"]

class Backoff:
    func init(initial=0.5, maximum=10.0, attempts=8, factor=2.0, jitter=0.1, seed=1):
        self.initial = initial
        self.maximum = maximum
        self.attempts = attempts
        self.factor = factor
        self.jitter = jitter
        self.state = seed & 0x7FFFFFFF

    # Attente avant l'essai n (0 = premier essai : aucune attente).
    func delay(n):
        if n <= 0:
            return 0.0
        d := self.initial
        for i in 0..n - 1:
            d = d * self.factor
            if d > self.maximum:
                d = self.maximum
                break
        self.state = (self.state * 1103515245 + 12345) & 0x7FFFFFFF
        r := (self.state % 1000) / 1000.0
        return d * (1.0 - self.jitter + 2 * self.jitter * r)

class LiveSession:
    func init(connect, backoff=null, sleeper=null, token=null):
        self.connect = connect
        self.backoff = backoff if backoff != null else Backoff()
        self.sleep = sleeper if sleeper != null else (s) => _t.sleep(s)
        self.token = token
        self.endpoint = null
        self.state = "déconnecté"
        self.connections = 0
        self.failures = 0
        self.drops = 0
        self.waited = 0.0
        self.last_error = null

    func _connect():
        n := 0
        while true:
            mc.check(self.token)
            if n >= self.backoff.attempts:
                self.state = "abandonné"
                merr.fail(merr.DEVICE, "connexion impossible après " + str(n) + " essais : " + str(self.last_error))
            d := self.backoff.delay(n)
            if d > 0:
                self.waited += d
                self.sleep(d)
            n += 1
            try:
                self.endpoint = self.connect()
                self.connections += 1
                self.state = "connecté"
                return self.endpoint
            catch e:
                if not (e.type in NETWORK_ERRORS):
                    raise(e.type, e.message)
                self.failures += 1
                self.last_error = e.type + " : " + e.message
                self.state = "reconnexion"

    func ensure():
        if self.endpoint == null:
            self._connect()
        return self.endpoint

    # Appelle fn(endpoint) ; sur erreur réseau, reconnecte et réessaie (une fois par connexion).
    func call(fn):
        while true:
            ep := self.ensure()
            try:
                return fn(ep)
            catch e:
                if not (e.type in NETWORK_ERRORS):
                    raise(e.type, e.message)
                self.drops += 1
                self.last_error = e.type + " : " + e.message
                try:
                    ep.close()
                catch e2:
                    self.drops = self.drops
                self.endpoint = null
                self.state = "reconnexion"

    func write(samples):
        return self.call((ep) => ep.write(samples))

    func read(frames):
        return self.call((ep) => ep.read(frames))

    func stats():
        return {"state": self.state, "connections": self.connections, "failures": self.failures, "drops": self.drops,
                "waited": self.waited, "last_error": self.last_error}

    func close():
        if self.endpoint != null:
            try:
                self.endpoint.close()
            catch e:
                self.last_error = e.message
            self.endpoint = null
        self.state = "fermé"
