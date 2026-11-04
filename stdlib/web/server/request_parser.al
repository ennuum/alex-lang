# ALEX STANDARD LIBRARY — web.server.request_parser
#
# Côté serveur, ce qui entoure l'analyse d'une requête (l'analyse elle-même est web.http.protocol_parser,
# alimentée par web.server.connection) :
#   - traduction d'une erreur d'analyse en réponse (400, 408, 413, 414, 431, 501, 505) ;
#   - contrôles de sécurité de la cible et de l'hôte (octet nul, Host autorisés : protection contre le
#     « DNS rebinding ») ;
#   - adresse réelle du client et schéma d'origine derrière un mandataire DE CONFIANCE (Forwarded,
#     X-Forwarded-For, X-Forwarded-Proto, X-Forwarded-Host) ;
#   - chemin de routage normalisé (segments « . » / « .. » résolus).
#
#   use web.server.request_parser as rp
#   st := rp.error_status(e)                       # (413, "corps trop grand") pour une HttpLimitError 413
#   rp.client_ip(req, ["127.0.0.1"])               # IP du client d'origine si le pair est un mandataire de confiance
#   rp.host_allowed(req, ["exemple.org", ".exemple.org"])
#   rp.routing_path(req)                           # « /a/c » pour « /a/b/../c »
#
# Erreurs : aucune levée ; les fonctions rendent des statuts ou des booléens.

from core use len, type
from collections use append
use string as _s
use web.http.http_errors as _herr
use web.http.header_value as _hv
use web.url.path as _path
use web.url.percent_encoding as _pe
use web.url.host as _host

# (statut, message court) pour une erreur levée pendant l'analyse d'une requête.
func error_status(e):
    t := e.type
    if t == "TimeoutError":
        return (408, "délai de requête dépassé")
    status := _herr.status_for(e)
    msg := _herr.message_of(e)
    if status == 414:
        return (414, "cible de requête trop longue")
    if status == 431:
        return (431, "en-têtes trop volumineux")
    if status == 413:
        return (413, "corps de requête trop grand")
    if status == 505:
        return (505, "version HTTP non prise en charge")
    if status == 501:
        return (501, "fonctionnalité non prise en charge (" + msg + ")")
    if status >= 500:
        return (400, "requête invalide")
    return (status, "requête invalide (" + msg + ")")

# Chemin de routage : décodé segment par segment, segments « . » / « .. » résolus, « / » final conservé.
func routing_path(req):
    raw := req.raw_path()
    if raw == "*":
        return "*"
    return _pe.decode(_path.normalize(raw))

# Vrai si la cible contient un octet nul ou des séquences d'échappement invalides (requête à refuser : 400).
func has_bad_target(req):
    raw := req.raw_path()
    if not _pe.is_well_formed(raw):
        return true
    decoded := _pe.decode(raw)
    for c in decoded:
        if _s.ord(c) == 0:
            return true
    return false

func _ip_in(ip, trusted):
    for t in trusted:
        if t == "*" or t == ip:
            return true
        if _s.ends_with(t, ".") and _s.starts_with(ip, t):
            return true
    return false

# Adresse IP du client d'origine. Les en-têtes de mandataire ne sont crus que si le pair direct est dans trusted
# (liste d'IP, de préfixes « 10. », ou « * ») : sinon n'importe quel client pourrait se faire passer pour un autre.
func client_ip(req, trusted=null):
    peer := req.remote_address[0] if req.remote_address != null else null
    if trusted == null or peer == null or not _ip_in(peer, trusted):
        return peer
    fwd := forwarded(req)
    if len(fwd) > 0:
        for i in _range_desc(len(fwd)):
            f := fwd[i]
            if "for" in f:
                ip := _strip_port(f["for"])
                if not _ip_in(ip, trusted):
                    return ip
        return _strip_port(fwd[0]["for"]) if "for" in fwd[0] else peer
    xff := req.headers.get_list("x-forwarded-for")
    i := len(xff) - 1
    while i >= 0:
        ip := _strip_port(xff[i])
        if not _ip_in(ip, trusted):
            return ip
        i -= 1
    if len(xff) > 0:
        return _strip_port(xff[0])
    return peer

func _range_desc(n):
    out := []
    i := n - 1
    while i >= 0:
        append(out, i)
        i -= 1
    return out

func _strip_port(v):
    t := _hv.unquote(_s.trim(v))
    if _s.starts_with(t, "["):
        e := _s.find(t, "]")
        if e > 0:
            return t[1:e]
    if _s.count(t, ":") == 1:
        return t[0:_s.find(t, ":")]
    return t

# En-tête Forwarded (RFC 7239) : liste de dict (for, proto, host, by) dans l'ordre.
func forwarded(req):
    out := []
    for v in req.headers.get_all("forwarded"):
        for element in _hv.split_list(v):
            d := {}
            for pair in _hv.split_quoted(element, ';'):
                eq := _s.find(pair, "=")
                if eq > 0:
                    d[_s.lower(_s.trim(pair[0:eq]))] = _hv.unquote(pair[eq + 1:len(pair)])
            append(out, d)
    return out

# Schéma d'origine (« https » derrière un mandataire TLS de confiance), sinon celui de la connexion.
func scheme(req, trusted=null):
    peer := req.remote_address[0] if req.remote_address != null else null
    if trusted != null and peer != null and _ip_in(peer, trusted):
        fwd := forwarded(req)
        if len(fwd) > 0 and "proto" in fwd[0]:
            return _s.lower(fwd[0]["proto"])
        p := req.headers.get("x-forwarded-proto")
        if p != null:
            return _s.lower(_s.trim(_hv.split_list(p)[0]))
    return "https" if req.secure else "http"

# Hôte demandé (sans port), tenant compte de X-Forwarded-Host derrière un mandataire de confiance.
func host(req, trusted=null):
    peer := req.remote_address[0] if req.remote_address != null else null
    if trusted != null and peer != null and _ip_in(peer, trusted):
        xh := req.headers.get("x-forwarded-host")
        if xh != null:
            h := _s.trim(_hv.split_list(xh)[0])
            return _strip_port(h)
    return req.host()

# Vrai si l'hôte demandé est autorisé : allowed = liste de noms exacts, de suffixes « .exemple.org », ou « * »
# (null : tout est autorisé). Les adresses IP littérales sont acceptées si allow_ip.
func host_allowed(req, allowed=null, allow_ip=false):
    if allowed == null:
        return true
    h := req.host()
    if h == null:
        return false
    h = _s.lower(h)
    if allow_ip and _host.is_ip(h):
        return true
    for a in allowed:
        x := _s.lower(a)
        if x == "*" or x == h:
            return true
        if _s.starts_with(x, ".") and (_s.ends_with(h, x) or h == x[1:len(x)]):
            return true
    return false
