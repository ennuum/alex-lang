# ALEX STANDARD LIBRARY — web.client.timeout
#
# Délais du client HTTP. Quatre délais indépendants, en secondes (false : pas de limite ; un argument null prend
# la valeur par défaut) :
#   connect   établissement de la connexion TCP (et poignée de main TLS)
#   read      INACTIVITÉ en lecture : temps maximal sans recevoir un octet
#   write     envoi de la requête
#   total     durée totale d'un appel (redirections et reprises comprises)
#
# Deadline suit le délai total pendant un appel et plafonne chaque attente (cap).
#
#   use web.client.timeout as to
#   t := to.Timeout(5, 30, 30, 60)
#   t2 := to.uniform(10)                  # les quatre délais à 10 s
#   t3 := to.Timeout(5, false)            # lecture sans limite
#   d := to.Deadline(t.total)
#   d.cap(t.read)                         # min(délai de lecture, temps restant)
#   d.expired()                           # vrai si le délai total est écoulé
#
# Erreurs : ClientError (valeur négative), ClientTimeoutError (Deadline.check).

from core use len, type
use time as _time
use web.client.client_errors as _err

func _check(fn, label, v):
    if v == null:
        return null
    if (type(v) != "int" and type(v) != "float") or v < 0:
        _err.client_error(fn, label + " : nombre de secondes >= 0 ou null attendu (obtenu " + str(v) + ")")
    return v

class Timeout:
    func init(connect=10.0, read=30.0, write=30.0, total=null):
        self.connect = _check("Timeout", "connect", connect if connect != false else null)
        self.read = _check("Timeout", "read", read if read != false else null)
        self.write = _check("Timeout", "write", write if write != false else null)
        self.total = _check("Timeout", "total", total if total != false else null)

    func copy():
        return Timeout(self.connect if self.connect != null else false, self.read if self.read != null else false, self.write if self.write != null else false, self.total if self.total != null else false)

    func __str__():
        return "Timeout(connect=" + str(self.connect) + ", read=" + str(self.read) + ", write=" + str(self.write) + ", total=" + str(self.total) + ")"

# Les quatre délais à la même valeur (total compris).
func uniform(seconds):
    return Timeout(seconds, seconds, seconds, seconds)

# Délai par défaut : connexion 10 s, lecture et écriture 30 s, pas de total.
func default():
    return Timeout()

# Aucun délai (false désactive ; null redonnerait les valeurs par défaut).
func none():
    return Timeout(false, false, false, false)

# Depuis un nombre (délai total ET de chaque étape), un Timeout, ou null (défaut).
func from_value(value):
    if value == null:
        return Timeout()
    if isinstance(value, Timeout):
        return value
    if type(value) == "int" or type(value) == "float":
        return uniform(value)
    _err.client_error("timeout.from_value", "nombre, Timeout ou null attendu (obtenu " + type(value) + ")")

class Deadline:
    func init(total=null):
        self.total = total
        self.start = _time.monotonic()

    func elapsed():
        return _time.monotonic() - self.start

    # Secondes restantes, ou null s'il n'y a pas de délai total.
    func remaining():
        if self.total == null:
            return null
        r := self.total - self.elapsed()
        if r < 0:
            return 0.0
        return r

    func expired():
        return self.total != null and self.elapsed() >= self.total

    # Plus petit de t et du temps restant (null : pas de limite).
    func cap(t):
        r := self.remaining()
        if r == null:
            return t
        if t == null or r < t:
            return r
        return t

    # ClientTimeoutError si le délai total est écoulé.
    func check(where="requête"):
        if self.expired():
            _err.timeout_error("timeout", where + " : délai total de " + str(self.total) + " s dépassé")
