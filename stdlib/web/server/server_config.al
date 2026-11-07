# ALEX STANDARD LIBRARY — web.server.server_config
#
# ServerConfig : tous les réglages du serveur — adresse et port, limites (web.server.server_limits), délais
# (web.server.timeout), persistance des connexions (web.server.keep_alive), HTTPS (web.server.tls_server),
# politique d'exécution (web.server.concurrency), nom du serveur, hôtes autorisés, mandataires de confiance,
# mode debug, journal d'accès.
#
#   use web.server.server_config as sc
#   cfg := sc.ServerConfig("0.0.0.0", 8080)
#   cfg.allowed_hosts = ["exemple.org", ".exemple.org"]     # Host refusé sinon (421)
#   cfg.trusted_proxies = ["127.0.0.1"]                      # X-Forwarded-For / -Proto crus depuis ces pairs
#   cfg.tls = tls_server.TlsServerConfig("cert.pem", "key.pem")
#   cfg.debug = true                                          # détail des exceptions dans les réponses 500
#   cfg.access_log = true                                     # une ligne par requête (print), ou fonction (ligne)
#
# Erreurs : ServerConfigError.

from core use len, type
use web.server.server_errors as _err
use web.server.server_limits as _limits
use web.server.timeout as _timeout
use web.server.keep_alive as _keep
use web.server.concurrency as _conc

const DEFAULT_SERVER_NAME := "Alex-web/1.0"

class ServerConfig:
    func init(host="127.0.0.1", port=8080):
        if type(port) != "int" or port < 0 or port > 65535:
            _err.config_error("ServerConfig", "port entre 0 et 65535 attendu (obtenu " + str(port) + ")")
        self.host = host
        self.port = port
        self.backlog = 128
        self.limits = _limits.Limits()
        self.timeouts = _timeout.Timeouts()
        self.keep_alive = _keep.KeepAlivePolicy(true, 15, 1000)
        self.policy = _conc.Policy()
        self.tls = null                       # web.server.tls_server.TlsServerConfig pour HTTPS
        self.http2 = true                     # HTTP/2 en clair (h2c, préface) ; sur TLS : ALPN « h2 » (web.server.http2)
        self.server_name = DEFAULT_SERVER_NAME   # en-tête Server (false : absent)
        self.allowed_hosts = null             # null : tout Host accepté
        self.trusted_proxies = null           # IP / préfixes des mandataires de confiance
        self.debug = false
        self.access_log = false               # true : print ; fonction (ligne) : destination
        self.poll_interval = 0.5              # attente maximale d'un tour de boucle (secondes)
        self.handle_signals = false           # INT / TERM : arrêt propre (serve_forever)
        self.reuse_port = false               # SO_REUSEPORT : plusieurs processus sur le même port (workers)

    func is_secure():
        return self.tls != null

    func scheme():
        return "https" if self.tls != null else "http"

    func with_limits(limits):
        self.limits = limits
        return self

    func with_timeouts(timeouts):
        self.timeouts = timeouts
        self.keep_alive.timeout = timeouts.idle
        return self

    func with_tls(tls):
        self.tls = tls
        return self

    func validate():
        if self.limits == null or self.timeouts == null:
            _err.config_error("ServerConfig", "limites et délais requis")
        if self.poll_interval <= 0:
            _err.config_error("ServerConfig", "poll_interval doit être > 0")
        return self

func config(host="127.0.0.1", port=8080):
    return ServerConfig(host, port)

# Profil de développement : debug, journal d'accès, port 8000 sur l'interface locale.
func development(port=8000):
    c := ServerConfig("127.0.0.1", port)
    c.debug = true
    c.access_log = true
    return c

# Profil de production : toutes interfaces, limites et délais stricts, arrêt propre sur signal.
func production(port=8080, allowed_hosts=null):
    c := ServerConfig("0.0.0.0", port)
    c.limits = _limits.strict()
    c.timeouts = _timeout.strict()
    c.keep_alive = _keep.KeepAlivePolicy(true, c.timeouts.idle, 100)
    c.allowed_hosts = allowed_hosts
    c.handle_signals = true
    return c
