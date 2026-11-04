# ALEX STANDARD LIBRARY — web.client.client_config
#
# ClientConfig : tous les réglages d'un client HTTP en un objet — délais, TLS, mandataire, reprises,
# redirections, User-Agent, en-têtes par défaut, URL de base, réserve de connexions, limites, décompression,
# cookies. Chaque champ a une valeur par défaut raisonnable ; les méthodes with_* rendent une copie modifiée.
#
#   use web.client.client_config as cc
#   cfg := cc.ClientConfig()
#   cfg = cfg.with_base_url("https://api.exemple.org/v1/").with_header("Accept", "application/json")
#   cfg = cfg.with_timeout(5).with_retries(3).with_proxy("env")
#   cfg.max_response_size        # 104857600 (100 Mio)
#
# Erreurs : ClientError.

from core use len, type
use web.client.client_errors as _err
use web.client.timeout as _timeout
use web.client.tls_config as _tls
use web.client.proxy as _proxy
use web.client.retry_policy as _retry
use web.client.redirect as _redirect
use web.client.user_agent as _ua
use web.http.headers as _headers
use web.url.url as _url

class ClientConfig:
    func init():
        self.timeout = _timeout.Timeout()
        self.tls = _tls.TlsConfig()
        self.proxy = null                    # null, "env", texte d'URL ou web.client.proxy.Proxy
        self.retry = _retry.RetryPolicy()
        self.redirect = _redirect.RedirectPolicy()
        self.user_agent = _ua.default()
        self.headers = _headers.Headers()    # en-têtes ajoutés à chaque requête (sans écraser ceux de la requête)
        self.base_url = null                 # Url : les URL relatives sont résolues contre elle
        self.keep_alive = true               # connexions réutilisées (réserve)
        self.max_connections_per_host = 8
        self.max_idle_connections = 32
        self.idle_timeout = 60.0             # secondes avant de fermer une connexion inactive de la réserve
        self.max_response_size = 104857600   # corps de réponse (octets, après décompression)
        self.max_header_bytes = 65536
        self.decompress = true               # Accept-Encoding: gzip, deflate et décodage automatique
        self.cookies = true                  # mémoriser et renvoyer les cookies (CookieJar du client)
        self.raise_for_status = false        # lever HttpStatusError sur 4xx / 5xx

    func copy():
        c := ClientConfig()
        c.timeout = self.timeout
        c.tls = self.tls
        c.proxy = self.proxy
        c.retry = self.retry
        c.redirect = self.redirect
        c.user_agent = self.user_agent
        c.headers = self.headers.copy()
        c.base_url = self.base_url
        c.keep_alive = self.keep_alive
        c.max_connections_per_host = self.max_connections_per_host
        c.max_idle_connections = self.max_idle_connections
        c.idle_timeout = self.idle_timeout
        c.max_response_size = self.max_response_size
        c.max_header_bytes = self.max_header_bytes
        c.decompress = self.decompress
        c.cookies = self.cookies
        c.raise_for_status = self.raise_for_status
        return c

    # Délais : nombre (tous) ou web.client.timeout.Timeout.
    func with_timeout(value):
        c := self.copy()
        c.timeout = _timeout.from_value(value)
        return c

    func with_tls(tls_config):
        c := self.copy()
        c.tls = tls_config
        return c

    # Vérification TLS désactivée (tests uniquement).
    func insecure():
        return self.with_tls(_tls.insecure())

    # Mandataire : URL, Proxy, "env" (variables d'environnement) ou null (aucun).
    func with_proxy(proxy):
        c := self.copy()
        if proxy != null and proxy != "env" and type(proxy) == "str":
            c.proxy = _proxy.Proxy(proxy)
        else:
            c.proxy = proxy
        return c

    func with_retries(value):
        c := self.copy()
        c.retry = _retry.from_value(value)
        return c

    func with_redirects(value):
        c := self.copy()
        c.redirect = _redirect.from_value(value)
        return c

    func with_user_agent(value):
        c := self.copy()
        c.user_agent = value
        return c

    func with_header(name, value):
        c := self.copy()
        c.headers.set(name, value)
        return c

    func with_headers(data):
        c := self.copy()
        c.headers.replace_all(data)
        return c

    func with_base_url(url):
        c := self.copy()
        c.base_url = _url.parse(url) if type(url) == "str" else url
        return c

    func with_keep_alive(on):
        c := self.copy()
        c.keep_alive = on
        return c

    func with_max_response_size(n):
        c := self.copy()
        c.max_response_size = n
        return c

    func with_cookies(on):
        c := self.copy()
        c.cookies = on
        return c

    func with_raise_for_status(on=true):
        c := self.copy()
        c.raise_for_status = on
        return c

func default():
    return ClientConfig()
