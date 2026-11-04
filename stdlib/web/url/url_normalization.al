# ALEX STANDARD LIBRARY — web.url.url_normalization
#
# Normalisation d'URL (RFC 3986 §6) : ramener des écritures différentes d'une même ressource à une seule forme,
# pour comparer, dédupliquer ou servir de clé de cache.
#
# Normalisations SÛRES (le sens est préservé, appliquées par défaut) :
#   schéma et hôte en minuscules, port par défaut omis, « %xx » en majuscules, octets non réservés décodés
#   (« %7E » -> « ~ »), segments « . » et « .. » supprimés, chemin vide -> « / » (schémas spéciaux).
# Normalisations OPTIONNELLES (peuvent changer la ressource désignée) : Options(...)
#   sort_query          trier les paramètres            remove_fragment      retirer « #… »
#   remove_empty_query  retirer un « ? » vide           remove_trailing_slash  « /a/ » -> « /a »
#   remove_index        « /a/index.html » -> « /a/ »    remove_www           « www.exemple.org » -> « exemple.org »
#   remove_params       noms à retirer (« utm_* » : préfixe)   force_https   http -> https, ws -> wss
#
#   use web.url.url_normalization as norm
#   norm.normalize("HTTP://Exemple.ORG:80/a/./b/../%7euser/?")          # http://exemple.org/a/~user/?
#   norm.normalize("http://h/a/?b=2&a=1&utm_source=x#x", norm.aggressive())   # http://h/a/?a=1&b=2
#   norm.equivalent("http://h:80/a", "HTTP://H/a")                     # true
#   norm.normalize(u, norm.Options(true, true))                         # tri de la requête, sans fragment
#
# Erreurs : celles de web.url.url_parser.

from core use len, type
from collections use append
use string as _s
use web.url.url_parser as _parser
use web.url.percent_encoding as _pe
use web.url.path as _path
use web.url.scheme as _scheme
use web.url.query_params as _qp

const TRACKING_PARAMS := ["utm_*", "fbclid", "gclid", "dclid", "msclkid", "mc_cid", "mc_eid", "_ga", "yclid"]
const INDEX_FILES := ["index.html", "index.htm", "index.php", "default.asp", "default.aspx"]

class Options:
    func init(sort_query=false, remove_fragment=false, remove_empty_query=false, remove_trailing_slash=false, remove_index=false, remove_www=false, remove_params=null, force_https=false):
        self.sort_query = sort_query
        self.remove_fragment = remove_fragment
        self.remove_empty_query = remove_empty_query
        self.remove_trailing_slash = remove_trailing_slash
        self.remove_index = remove_index
        self.remove_www = remove_www
        self.remove_params = remove_params if remove_params != null else []
        self.force_https = force_https

# Normalisations sûres uniquement (RFC 3986 §6.2.2).
func safe():
    return Options()

# Forme canonique « agressive » pour dédupliquer des liens : requête triée, sans fragment, sans « ? » vide,
# sans paramètres de pistage, sans « index.html ».
func aggressive():
    return Options(true, true, true, false, true, false, TRACKING_PARAMS, false)

func _param_matches(name, patterns):
    for p in patterns:
        if _s.ends_with(p, "*"):
            if _s.starts_with(name, p[0:len(p) - 1]):
                return true
        elif name == p:
            return true
    return false

# Normalise un UrlParts (absolu) ; renvoie une copie.
func normalize_parts(parts, options=null):
    o := options if options != null else safe()
    t := parts.copy()
    if t.scheme != null:
        t.scheme = _s.lower(t.scheme)
    if o.force_https:
        t.scheme = _scheme.secure_variant(t.scheme)
    if t.host != null and t.host_kind != "opaque":
        t.host = _s.lower(t.host)
        if o.remove_www and _s.starts_with(t.host, "www.") and t.host_kind == "domain":
            t.host = t.host[4:len(t.host)]
    if t.port != null and _scheme.is_default_port(t.scheme, t.port):
        t.port = null
    t.username = _pe.normalize(t.username)
    if t.password != null:
        t.password = _pe.normalize(t.password)
    if not t.has_opaque_path():
        t.path = _path.remove_dot_segments(_pe.normalize(t.path))
        if t.path == "" and (_scheme.is_special(t.scheme) or t.host != null):
            t.path = "/"
        if o.remove_index:
            for f in INDEX_FILES:
                if _s.ends_with(t.path, "/" + f):
                    t.path = t.path[0:len(t.path) - len(f)]
                    break
        if o.remove_trailing_slash and len(t.path) > 1 and _s.ends_with(t.path, "/"):
            t.path = t.path[0:len(t.path) - 1]
    if t.query != null:
        q := _pe.normalize(t.query)
        if len(o.remove_params) > 0 or o.sort_query:
            p := _qp.parse(q)
            if len(o.remove_params) > 0:
                kept := []
                for pair in p.pairs():
                    if not _param_matches(pair[0], o.remove_params):
                        append(kept, pair)
                p = _qp.QueryParams(kept)
            if o.sort_query:
                p.sort()
            q = p.to_string()
        t.query = q
        if o.remove_empty_query and t.query == "":
            t.query = null
    if t.fragment != null:
        if o.remove_fragment:
            t.fragment = null
        else:
            t.fragment = _pe.normalize(t.fragment)
    return t

# Normalise une URL (texte, ou objet doté de serialize()) ; renvoie du texte.
func normalize(url, options=null):
    text := url
    if type(url) != "str":
        text = url.serialize()
    return normalize_parts(_parser.parse_absolute(text), options).serialize()

# Vrai si deux URL désignent la même ressource après normalisation (options : voir Options).
func equivalent(a, b, options=null):
    return normalize(a, options) == normalize(b, options)

# Clé de cache : forme agressive sans fragment.
func cache_key(url):
    return normalize(url, aggressive())
