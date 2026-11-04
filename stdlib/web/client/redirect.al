# ALEX STANDARD LIBRARY — web.client.redirect
#
# Redirections HTTP (RFC 9110 §15.4) suivies par le client, avec les règles de sécurité des navigateurs :
#   - 301 / 302 / 303 : POST devient GET (303 : toute méthode sauf HEAD), le corps et ses en-têtes sont retirés ;
#   - 307 / 308 : méthode et corps conservés ;
#   - Location relative résolue contre l'URL courante, fragment hérité s'il manque ;
#   - Authorization, Cookie et Proxy-Authorization retirés quand l'origine change ;
#   - https -> http refusé par défaut (allow_downgrade) ; seuls http et https sont suivis ;
#   - au plus max_redirects redirections, boucle détectée.
#
#   use web.client.redirect as rd
#   p := rd.RedirectPolicy(5)
#   suivante := p.next_request(requete, reponse, historique)   # ClientRequest, ou null s'il ne faut pas suivre
#   rd.never()                                                 # ne jamais suivre
#
# Erreurs : TooManyRedirects (limite ou boucle), ClientError (Location invalide, rétrogradation refusée).

from core use len, type
from collections use append
use string as _s
use web.client.client_errors as _err
use web.client.client_request as _creq
use web.url.url as _url
use web.http.method as _method
use web.http.status_code as _status

const STRIP_ON_CROSS_ORIGIN := ["authorization", "cookie", "proxy-authorization"]
const BODY_HEADERS := ["content-type", "content-length", "content-encoding", "content-language", "content-location", "transfer-encoding", "digest"]

class RedirectPolicy:
    func init(max_redirects=10, follow=true, allow_downgrade=false, keep_auth_on_cross_origin=false):
        self.max_redirects = max_redirects
        self.follow = follow
        self.allow_downgrade = allow_downgrade
        self.keep_auth_on_cross_origin = keep_auth_on_cross_origin

    func copy():
        return RedirectPolicy(self.max_redirects, self.follow, self.allow_downgrade, self.keep_auth_on_cross_origin)

    # Requête suivante pour une réponse de redirection, ou null (pas une redirection, ou redirections désactivées).
    # history : liste des réponses déjà suivies (pour la limite et la détection de boucle).
    func next_request(request, response, history):
        follow := self.follow if request.follow_redirects == null else request.follow_redirects
        if not follow or not _status.is_redirect(response.status):
            return null
        loc := response.headers.get("location")
        if loc == null or loc == "":
            return null
        if len(history) >= self.max_redirects:
            _err.too_many_redirects("redirect", "plus de " + str(self.max_redirects) + " redirections (dernière vers « " + loc + " »)")
        target := null
        try:
            target = _url.parse(loc, request.url)
        catch e:
            _err.client_error("redirect", "Location invalide « " + loc + " » : " + e.message)
        if not target.is_http():
            _err.client_error("redirect", "redirection vers un schéma non pris en charge « " + target.scheme + " »")
        if request.url.scheme == "https" and target.scheme == "http" and not self.allow_downgrade:
            _err.client_error("redirect", "redirection de https vers http refusée (« " + target.href() + " »)")
        # boucle : même URL et même méthode déjà visitée
        method := _method.after_redirect(request.method, response.status)
        for old in history:
            if old.url != null and str(old.url) == target.href() and old.request != null and old.request.method == method:
                _err.too_many_redirects("redirect", "boucle de redirections sur « " + target.href() + " »")
        nr := request.copy()
        nr.url = target.without_fragment()
        nr.method = method
        if method != request.method or not _status.preserves_method(response.status):
            if method == "GET" or method == "HEAD":
                nr.body = ""
                for h in BODY_HEADERS:
                    nr.headers.remove(h)
        if target.origin() != request.url.origin() and not self.keep_auth_on_cross_origin:
            for h in STRIP_ON_CROSS_ORIGIN:
                nr.headers.remove(h)
        nr.headers.remove("host")
        nr.attempt = 0
        return nr

func default():
    return RedirectPolicy()

func never():
    return RedirectPolicy(0, false)

# Depuis un entier (maximum), true / false (suivre ou non), une RedirectPolicy ou null (défaut).
func from_value(value):
    if value == null or value == true:
        return RedirectPolicy()
    if value == false:
        return never()
    if isinstance(value, RedirectPolicy):
        return value
    if type(value) == "int":
        return RedirectPolicy(value)
    _err.client_error("redirect.from_value", "entier, booléen, RedirectPolicy ou null attendu")
