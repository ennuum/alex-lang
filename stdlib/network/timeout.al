# ALEX STANDARD LIBRARY — network.timeout
#
# Délais des opérations réseau.
#
#   Deadline       échéance absolue (horloge monotone) partagée par plusieurs opérations : chaque appel reçoit
#                  le temps RESTANT, l'ensemble ne dépasse jamais le délai global.
#   Timeouts       jeu de délais d'un client (connexion, lecture, écriture, total, réserve de connexions).
#   normalize, check, smallest   validation et combinaison (null = sans limite).
#   with_timeout   attend une tâche async au plus n secondes (TimeoutError, la tâche est annulée).
#
# Convention de tout network.* : un délai null attend sans limite ; un nombre >= 0 attend au plus ce nombre de
# secondes (0 : ne pas attendre du tout).
#
# Exemple
#   use network.timeout as to
#   d := to.Deadline(5.0)
#   c := tcp.connect(hôte, 80, d.remaining())
#   c.write(requête, d.remaining())
#   réponse := c.read_line(d.remaining())        # TimeoutError si les 5 s sont écoulées
#
#   t := to.Timeouts(connect=2.0, read=10.0)

from core use type
use time as _time
use asyncio as _aio

func _check_number(fn, t):
    if t == null:
        return
    if type(t) != "int" and type(t) != "float":
        raise("TypeError", "network.timeout." + fn + " : délai nombre ou null attendu (obtenu '" + type(t) + "')")
    if t < 0:
        raise("ArgumentError", "network.timeout." + fn + " : délai négatif (" + str(t) + ")")

# Valide un délai (null ou nombre >= 0) et le rend en float (ou null).
func normalize(t, fn="normalize"):
    _check_number(fn, t)
    if t == null:
        return null
    return t * 1.0

# Le plus petit de deux délais (null : sans limite).
func smallest(a, b):
    if a == null:
        return b
    if b == null:
        return a
    if a < b:
        return a
    return b

# Lève TimeoutError (opération décrite par what).
func expired(what="opération"):
    raise("TimeoutError", what + " : délai dépassé")

class Deadline:
    # Échéance dans `seconds` secondes (null : jamais).
    func init(seconds=null):
        _check_number("Deadline", seconds)
        self.seconds = seconds
        self.start = _time.monotonic()
        self.end = null
        if seconds != null:
            self.end = self.start + seconds

    # Secondes restantes (>= 0), ou null sans échéance. cap : borne supérieure facultative.
    func remaining(cap=null):
        if self.end == null:
            return cap
        left := self.end - _time.monotonic()
        if left < 0:
            left = 0.0
        if cap != null and cap < left:
            return cap
        return left

    func elapsed():
        return _time.monotonic() - self.start

    func expired():
        return self.end != null and _time.monotonic() >= self.end

    # Lève TimeoutError si l'échéance est passée ; sinon rend le temps restant.
    func check(what="opération"):
        if self.expired():
            raise("TimeoutError", what + " : délai global de " + str(self.seconds) + " s dépassé")
        return self.remaining()

    # Repousse l'échéance de `seconds`.
    func extend(seconds):
        _check_number("extend", seconds)
        if self.end != null:
            self.end += seconds
            self.seconds += seconds

    func str():
        if self.end == null:
            return "Deadline(sans limite)"
        return "Deadline(" + str(self.remaining()) + " s restantes)"

# Deadline depuis un nombre de secondes ou null (sans limite) ; une Deadline existante est rendue telle quelle.
func deadline(value):
    if value != null and type(value) != "int" and type(value) != "float":
        return value
    return Deadline(value)

class Timeouts:
    # connect : établissement TCP/TLS ; read / write : inactivité d'une lecture / écriture ;
    # total : opération complète (requête + réponse) ; pool : attente d'une connexion libre.
    func init(connect=10.0, read=30.0, write=30.0, total=null, pool=10.0):
        _check_number("Timeouts", connect)
        _check_number("Timeouts", read)
        _check_number("Timeouts", write)
        _check_number("Timeouts", total)
        _check_number("Timeouts", pool)
        self.connect = connect
        self.read = read
        self.write = write
        self.total = total
        self.pool = pool

    # Même délai partout (null : sans limite).
    func all(t):
        _check_number("Timeouts.all", t)
        self.connect = t
        self.read = t
        self.write = t
        return self

    func copy():
        return Timeouts(self.connect, self.read, self.write, self.total, self.pool)

    func str():
        return "Timeouts(connect=" + str(self.connect) + ", read=" + str(self.read) + ", write=" + str(self.write) + ", total=" + str(self.total) + ", pool=" + str(self.pool) + ")"

# Timeouts depuis un nombre (même délai pour connexion, lecture et écriture), null, ou un Timeouts.
func timeouts(value):
    if value == null:
        return Timeouts(null, null, null, null, null)
    if type(value) == "int" or type(value) == "float":
        return Timeouts(value, value, value, null, value)
    return value

# Attend la tâche (ou le futur) au plus `seconds` : TimeoutError sinon, et la tâche est annulée.
async func with_timeout(task, seconds):
    _check_number("with_timeout", seconds)
    if seconds == null:
        return await task
    return await _aio.timeout(task, seconds)

# Exécute fn() et lève TimeoutError s'il a dépassé `seconds` (contrôle a posteriori : un appel bloquant n'est pas
# interrompu ; les délais des opérations réseau sous-jacentes doivent être bornés aussi).
func run_within(fn, seconds, what="opération"):
    d := Deadline(seconds)
    r := fn()
    if d.expired():
        raise("TimeoutError", what + " : " + str(seconds) + " s dépassées")
    return r
