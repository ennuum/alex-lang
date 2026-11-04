# ALEX STANDARD LIBRARY — web.server.timeout
#
# Délais du serveur, en secondes : ils libèrent les connexions des clients lents ou absents (attaque « slowloris »)
# et bornent le temps d'arrêt.
#
#   | Délai       | Défaut | Mesure                                                          | Effet           |
#   |-------------|--------|-----------------------------------------------------------------|-----------------|
#   | header      | 15     | du premier octet d'une requête à la fin de ses en-têtes          | 408 et fermeture |
#   | body        | 60     | de la fin des en-têtes à la fin du corps                         | 408 et fermeture |
#   | idle        | 15     | inactivité entre deux requêtes d'une connexion persistante       | fermeture        |
#   | write       | 30     | envoi d'un morceau de réponse                                    | fermeture        |
#   | handshake   | 10     | poignée de main TLS                                              | fermeture        |
#   | shutdown    | 10     | attente des requêtes en cours lors d'un arrêt propre             | fermeture forcée |
#
#   use web.server.timeout as to
#   t := to.Timeouts()
#   t2 := to.Timeouts(5, 30, 5)          # serveur exposé
#   t.expired_reason(conn, now)          # null, "header", "body" ou "idle"
#
# Erreurs : ServerConfigError.

from core use len, type
use time as _time
use web.server.server_errors as _err

func _check(label, v):
    if (type(v) != "int" and type(v) != "float") or v <= 0:
        _err.config_error("Timeouts", label + " : nombre de secondes > 0 attendu (obtenu " + str(v) + ")")
    return v

class Timeouts:
    func init(header=15.0, body=60.0, idle=15.0, write=30.0, handshake=10.0, shutdown=10.0):
        self.header = _check("header", header)
        self.body = _check("body", body)
        self.idle = _check("idle", idle)
        self.write = _check("write", write)
        self.handshake = _check("handshake", handshake)
        self.shutdown = _check("shutdown", shutdown)

    # Raison de l'expiration d'une connexion (web.server.connection.ServerConnection) à l'instant now, ou null.
    func expired_reason(conn, now=null):
        t := now if now != null else _time.monotonic()
        phase := conn.phase()
        if phase == "idle":
            if t - conn.last_activity > self.idle:
                return "idle"
            return null
        if phase == "header":
            if t - conn.request_started_at > self.header:
                return "header"
            return null
        if phase == "body":
            if t - conn.head_completed_at > self.body:
                return "body"
            return null
        return null

    func copy():
        return Timeouts(self.header, self.body, self.idle, self.write, self.handshake, self.shutdown)

func default():
    return Timeouts()

# Délais courts pour un service exposé (clients lents écartés plus vite).
func strict():
    return Timeouts(5.0, 30.0, 5.0, 15.0, 5.0, 5.0)

# Monotone courant (secondes).
func now():
    return _time.monotonic()
