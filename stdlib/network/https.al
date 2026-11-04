# ALEX STANDARD LIBRARY — network.https
#
# HTTPS strict, au-dessus de network.http_client et network.tls :
#   - refuse toute URL http:// et toute redirection vers http:// (pas de rétrogradation) ;
#   - vérification des certificats TOUJOURS active (autorité système ou ca_file fourni) ;
#   - HSTS (RFC 6797) : mémorise Strict-Transport-Security des réponses et réécrit en https:// les URL des hôtes
#     connus (y compris les sous-domaines si includeSubDomains) ; stockage persistant facultatif ;
#   - en-têtes de sécurité vérifiables sur une réponse (security_headers) ;
#   - inspection de la connexion TLS d'un hôte : version, suite, ALPN, vérification, sujet et émetteur.
#
#   use network.https as https
#   c := https.Client("https://api.exemple.org/", {"Accept": "application/json"})
#   r := c.get("v1/etat")                       # SecurityError si l'URL ou une redirection est en clair
#   print(r.status, https.security_headers(r))  # {"hsts": true, "csp": false, ...}
#   print(https.tls_info("exemple.org"))        # {"version": "TLSv1.3", "cipher": ..., "verified": true, ...}
#   print(https.upgrade("http://exemple.org/x", c.hsts))   # https://exemple.org/x si l'hôte est en HSTS
#   print(https.get("https://exemple.org/").status)
#
# Erreurs : SecurityError (URL en clair, rétrogradation), TlsError / CertificateError (certificat), et celles
# de network.http_client.

from core use len, type, to_int
from collections use append
use string as _s
use io as _io
use os as _os
use json as _json
use time as _time
use network.http_client as _hc
use network.tls as _tls
use network.url as _url

class HstsStore:
    func init(path=null):
        self.path = path
        self.hosts = {}       # hôte -> {"expires", "subdomains"}
        if path != null and _os.exists(path):
            try:
                self.hosts = _json.parse(_io.read_file(path))
            catch e:
                self.hosts = {}

    func add(host, max_age, subdomains=false):
        h := _s.lower(host)
        if max_age <= 0:
            if h in self.hosts:
                del self.hosts[h]
        else:
            self.hosts[h] = {"expires": _time.time() + max_age, "subdomains": subdomains}
        self.save()

    # Analyse « max-age=31536000; includeSubDomains » ; vrai si accepté.
    func observe(host, header_value):
        if header_value == null:
            return false
        max_age := null
        sub := false
        for part in _s.split(header_value, ";"):
            p := _s.trim(part)
            lp := _s.lower(p)
            if _s.starts_with(lp, "max-age="):
                v := _s.replace(_s.substring(p, 8, len(p)), "\"", "")
                ok := len(v) > 0
                for c in v:
                    if c < '0' or c > '9':
                        ok = false
                if ok:
                    max_age = to_int(v)
            elif lp == "includesubdomains":
                sub = true
        if max_age == null:
            return false
        self.add(host, max_age, sub)
        return true

    func is_known(host):
        h := _s.lower(host)
        now := _time.time()
        if h in self.hosts and self.hosts[h]["expires"] > now:
            return true
        parts := _s.split(h, ".")
        i := 1
        while i < len(parts) - 1:
            parent := _s.join(".", parts[i:])
            if parent in self.hosts and self.hosts[parent]["subdomains"] and self.hosts[parent]["expires"] > now:
                return true
            i += 1
        return false

    func save():
        if self.path != null:
            _io.write_file(self.path, _json.stringify(self.hosts))

func upgrade(url, store=null):
    if not _s.starts_with(_s.lower(url), "http://"):
        return url
    u := _url.parse(url)
    if store != null and store.is_known(u.host):
        return "https://" + _s.substring(url, 7, len(url))
    return url

func _require_https(url, what):
    if not _s.starts_with(_s.lower(url), "https://"):
        raise("SecurityError", "https : " + what + " en clair refusé(e) : " + url)

class Client:
    func init(base_url=null, headers=null, timeout=30.0, ca_file=null, hsts=null, auth=null):
        if base_url != null:
            _require_https(base_url, "URL de base")
        self.hsts = hsts
        if self.hsts == null:
            self.hsts = HstsStore()
        self.inner = _hc.Client(base_url, headers, timeout, true, ca_file, auth)
        self.base_url = base_url

    func _absolute(url):
        if _s.starts_with(_s.lower(url), "http://") or _s.starts_with(_s.lower(url), "https://"):
            return upgrade(url, self.hsts)
        if self.base_url == null:
            raise("SecurityError", "https : URL relative sans URL de base")
        return url

    func _check(r):
        for h in r.history:
            _require_https(h.url, "étape de redirection")
        _require_https(r.url, "URL finale")
        try:
            v := r.headers.get("strict-transport-security")
            if v != null:
                self.hsts.observe(_url.parse(r.url).host, v)
        catch e:
            v2 := null
        return r

    func request(method, url, params=null, data=null, json=null, headers=null, timeout=null):
        u := self._absolute(url)
        if _s.starts_with(_s.lower(u), "http://"):
            _require_https(u, "URL")
        r := self.inner.request(method, u, params, data, json, headers, null, null, timeout)
        return self._check(r)

    func get(url, params=null, headers=null, timeout=null):
        return self.request("GET", url, params, null, null, headers, timeout)

    func post(url, data=null, json=null, headers=null, timeout=null):
        return self.request("POST", url, null, data, json, headers, timeout)

    func put(url, data=null, json=null, headers=null, timeout=null):
        return self.request("PUT", url, null, data, json, headers, timeout)

    func delete(url, params=null, headers=null, timeout=null):
        return self.request("DELETE", url, params, null, null, headers, timeout)

    func close():
        self.inner.close()

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.close()

# Présence des en-têtes de sécurité usuels dans une réponse.
func security_headers(response):
    h := response.headers
    return {"hsts": h.has("strict-transport-security"), "csp": h.has("content-security-policy"),
            "nosniff": _s.lower(str(h.get("x-content-type-options"))) == "nosniff",
            "frame_options": h.has("x-frame-options") or _s.contains(str(h.get("content-security-policy")), "frame-ancestors"),
            "referrer_policy": h.has("referrer-policy")}

# Connexion TLS d'inspection (fermée aussitôt).
func tls_info(host, port=443, timeout=10.0, verify=true, ca_file=null):
    c := _tls.connect(host, port, timeout, verify, ca_file, ["h2", "http/1.1"])
    s := c.socket
    try:
        return {"host": host, "port": port, "version": s.version, "cipher": s.cipher, "alpn": s.alpn,
                "verified": s.verify_result == 0, "subject": s.peer_subject, "issuer": s.peer_issuer}
    finally:
        c.close()

func supported():
    return _tls.supported()

_shared := [null]

func _client():
    if _shared[0] == null:
        _shared[0] = Client()
    return _shared[0]

func get(url, params=null, headers=null, timeout=null):
    _require_https(upgrade(url, _client().hsts), "URL")
    return _client().get(url, params, headers, timeout)

func post(url, data=null, json=null, headers=null, timeout=null):
    _require_https(upgrade(url, _client().hsts), "URL")
    return _client().post(url, data, json, headers, timeout)
