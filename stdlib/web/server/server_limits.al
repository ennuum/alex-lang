# ALEX STANDARD LIBRARY — web.server.server_limits
#
# Limites du serveur : ce qu'un client peut consommer. Chaque limite protège contre une forme d'abus (requêtes
# géantes, en-têtes sans fin, connexions par milliers) et produit la réponse HTTP prévue par la RFC.
#
#   | Limite                       | Défaut   | Dépassement                                   |
#   |------------------------------|----------|-----------------------------------------------|
#   | max_request_line             | 8 Kio    | 414 URI Too Long                              |
#   | max_header_bytes             | 64 Kio   | 431 Request Header Fields Too Large           |
#   | max_headers                  | 100      | 431                                           |
#   | max_body                     | 10 Mio   | 413 Content Too Large                         |
#   | max_connections              | 1024     | 503 et fermeture immédiate                    |
#   | max_requests_per_connection  | 1000     | Connection: close après la dernière           |
#   | max_pipelined                | 16       | requêtes en attente sur une connexion : lecture suspendue |
#
#   use web.server.server_limits as sl
#   lim := sl.Limits()
#   lim2 := sl.Limits(4096, 16384, 50, 1048576, 256)     # serveur exposé, petits corps
#   lim.parser_limits()                                  # web.http.protocol_parser.Limits correspondantes
#
# Erreurs : ServerConfigError (valeur invalide).

from core use len, type
use web.server.server_errors as _err
use web.http.protocol_parser as _pp

func _positive(fn, label, v, allow_unlimited=false):
    if allow_unlimited and (v == false):
        return null
    if type(v) != "int" or v <= 0:
        _err.config_error(fn, label + " : entier > 0 attendu (obtenu " + str(v) + ")")
    return v

class Limits:
    # max_body=false : corps sans limite (déconseillé).
    func init(max_request_line=8192, max_header_bytes=65536, max_headers=100, max_body=10485760, max_connections=1024, max_requests_per_connection=1000, max_pipelined=16):
        self.max_request_line = _positive("Limits", "max_request_line", max_request_line)
        self.max_header_bytes = _positive("Limits", "max_header_bytes", max_header_bytes)
        self.max_headers = _positive("Limits", "max_headers", max_headers)
        self.max_body = _positive("Limits", "max_body", max_body, true)
        self.max_connections = _positive("Limits", "max_connections", max_connections)
        self.max_requests_per_connection = _positive("Limits", "max_requests_per_connection", max_requests_per_connection)
        self.max_pipelined = _positive("Limits", "max_pipelined", max_pipelined)

    # Limites de l'analyseur web.http.
    func parser_limits():
        return _pp.Limits(self.max_request_line, self.max_header_bytes, self.max_headers, self.max_body if self.max_body != null else false)

    func copy():
        return Limits(self.max_request_line, self.max_header_bytes, self.max_headers, self.max_body if self.max_body != null else false, self.max_connections, self.max_requests_per_connection, self.max_pipelined)

func default():
    return Limits()

# Profil prudent pour un service exposé à Internet derrière peu de ressources.
func strict():
    return Limits(4096, 16384, 50, 1048576, 256, 100, 4)

# Profil pour les envois de gros fichiers (1 Gio).
func uploads(max_body=1073741824):
    return Limits(8192, 65536, 100, max_body)
