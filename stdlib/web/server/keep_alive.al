# ALEX STANDARD LIBRARY — web.server.keep_alive
#
# Connexions persistantes (RFC 9112 §9.3) : après une réponse, la connexion reste-t-elle ouverte pour la requête
# suivante ? Oui en HTTP/1.1 par défaut, en HTTP/1.0 seulement sur demande (« Connection: keep-alive »), et
# jamais quand : le client ou la réponse demandent « close », le corps de la requête n'a pas été entièrement lu,
# la réponse est délimitée par la fermeture, la connexion a servi max_requests requêtes, ou le serveur s'arrête.
#
#   use web.server.keep_alive as ka
#   p := ka.KeepAlivePolicy(true, 15, 1000)
#   p.decide(requete, reponse, connexion, en_arret)    # true / false
#   p.header_value(connexion)                          # « timeout=15, max=997 » (en-tête Keep-Alive, HTTP/1.0)

from core use len, type, to_int
use web.http.message_body as _mb

class KeepAlivePolicy:
    func init(enabled=true, timeout=15, max_requests=1000):
        self.enabled = enabled
        self.timeout = timeout
        self.max_requests = max_requests

    # Décision de persistance après la réponse à request sur conn ; draining : arrêt en cours.
    func decide(request, response, conn, draining=false):
        if not self.enabled or draining or conn.closing:
            return false
        if request == null:
            return false
        if not request.keep_alive():
            return false
        if response.headers.has_token("connection", "close"):
            return false
        if conn.requests_served + 1 >= self.max_requests:
            return false
        if response.body_stream != null and request.version == "HTTP/1.0":
            return false
        if response.status == 101:
            return false
        return true

    # Valeur de l'en-tête Keep-Alive (indicatif, utile aux clients HTTP/1.0).
    func header_value(conn):
        left := self.max_requests - conn.requests_served - 1
        if left < 0:
            left = 0
        return "timeout=" + str(to_int(self.timeout)) + ", max=" + str(left)

func default():
    return KeepAlivePolicy()

func disabled():
    return KeepAlivePolicy(false)
