# ALEX STANDARD LIBRARY — web.client.proxy
#
# Mandataires HTTP (proxies) du client : un mandataire « http://hôte:port » relaie les requêtes http (cible en
# forme absolue) et ouvre un tunnel CONNECT pour les requêtes https (le chiffrement reste de bout en bout).
# Identifiants Basic facultatifs (dans l'URL du mandataire ou à part), liste d'exclusions NO_PROXY.
#
#   use web.client.proxy as px
#   p := px.Proxy("http://proxy.interne:3128", ["localhost", ".interne", "10.0.0.0/8"])
#   p.applies_to("https://exemple.org/")      # true
#   p.applies_to("http://app.interne/")       # false (exclu)
#   px.from_env()                             # depuis HTTPS_PROXY / HTTP_PROXY / ALL_PROXY / NO_PROXY (ou null)
#   p.authorization()                         # « Basic … » si des identifiants sont donnés
#
# Les mandataires SOCKS ne sont pas pris en charge (ClientProxyError).
# Erreurs : ClientProxyError, erreurs de web.url.

from core use len, type
from collections use append
use string as _s
use os as _os
use web.client.client_errors as _err
use web.url.url as _url
use web.url.host as _host
use web.url.percent_encoding as _pe
use web.http.request as _request

class Proxy:
    # url : « http://[utilisateur:mot@]hôte:port » ; no_proxy : liste d'exclusions (hôtes, suffixes « .domaine »,
    # « * », adresses IPv4 ou réseaux CIDR, « hôte:port ») ; username / password : identifiants explicites.
    func init(url, no_proxy=null, username=null, password=null):
        u := _url.parse(url if _s.contains(url, "://") else "http://" + url)
        if u.scheme != "http" and u.scheme != "https":
            _err.proxy_error("Proxy", "schéma de mandataire non pris en charge « " + u.scheme + " » (http ou https)")
        if u.host == null or u.host == "":
            _err.proxy_error("Proxy", "mandataire sans hôte « " + url + " »")
        self.url = u
        self.scheme = u.scheme
        self.host = u.hostname()
        self.port = u.effective_port()     # port explicite, sinon 80 (http) / 443 (https)
        self.username = username if username != null else (_pe.decode(u.username) if u.username != "" else null)
        self.password = password if password != null else (_pe.decode(u.password) if u.password != null else null)
        self.no_proxy = []
        if no_proxy != null:
            for x in (no_proxy if type(no_proxy) == "list" or type(no_proxy) == "tuple" else _s.split(no_proxy, ",")):
                t := _s.lower(_s.trim(str(x)))
                if t != "":
                    append(self.no_proxy, t)

    # Valeur de Proxy-Authorization, ou null.
    func authorization():
        if self.username == null:
            return null
        return _request.basic_auth_header(self.username, self.password if self.password != null else "")

    # Vrai si ce mandataire doit servir pour l'URL (texte ou Url).
    func applies_to(target):
        u := target
        if type(target) == "str":
            u = _url.parse(target)
        return not bypass(self.no_proxy, u.hostname(), u.effective_port())

    func address():
        return (self.host, self.port)

    func __str__():
        return self.url.redacted()

# Vrai si host:port est exclu par la liste no_proxy.
func bypass(no_proxy, host, port=null):
    h := _s.lower(str(host))
    for rule in no_proxy:
        if rule == "*":
            return true
        r := rule
        rule_port := null
        c := _s.find(r, ":")
        if c > 0 and _s.count(r, ":") == 1:
            rule_port = r[c + 1:len(r)]
            r = r[0:c]
            if port != null and str(port) != rule_port:
                continue
        if _s.contains(r, "/"):
            if _in_cidr(h, r):
                return true
            continue
        if _s.starts_with(r, "."):
            if _s.ends_with(h, r) or h == r[1:len(r)]:
                return true
        elif h == r or _s.ends_with(h, "." + r):
            return true
    return false

func _in_cidr(host, cidr):
    slash := _s.find(cidr, "/")
    net := cidr[0:slash]
    bits_text := cidr[slash + 1:len(cidr)]
    if not _host.is_ipv4(host) or not _host.is_ipv4(net):
        return false
    bits := 0
    for ch in bits_text:
        if ch < '0' or ch > '9':
            return false
        bits = bits * 10 + (_s.ord(ch) - 48)
    if bits > 32:
        return false
    a := _host.ipv4_parse(host)
    b := _host.ipv4_parse(net)
    if bits == 0:
        return true
    shift := 32 - bits
    return (a >> shift) == (b >> shift)

func _env(names):
    for n in names:
        v := null
        try:
            v = _os.getenv(n)
        catch e:
            v = null
        if v != null and v != "":
            return v
    return null

# Mandataire pour le schéma (http / https) depuis l'environnement, ou null.
func from_env(scheme="https"):
    names := ["HTTPS_PROXY", "https_proxy"] if scheme == "https" else ["HTTP_PROXY", "http_proxy"]
    v := _env(names)
    if v == null:
        v = _env(["ALL_PROXY", "all_proxy"])
    if v == null:
        return null
    if _s.starts_with(_s.lower(v), "socks"):
        _err.proxy_error("proxy.from_env", "mandataire SOCKS non pris en charge (« " + v + " »)")
    return Proxy(v, _env(["NO_PROXY", "no_proxy"]))

# Mandataire à utiliser pour une URL : celui de l'environnement (ou proxy donné) s'il s'applique, sinon null.
func select(target, proxy=null):
    u := target
    if type(target) == "str":
        u = _url.parse(target)
    p := proxy
    if p == "env":
        p = from_env(u.scheme)
    if p == null:
        return null
    if type(p) == "str":
        p = Proxy(p)
    if p.applies_to(u):
        return p
    return null
