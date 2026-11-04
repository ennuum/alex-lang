# ALEX STANDARD LIBRARY — web.url
#
# Point d'entrée du paquet web.url : URL web (http, https, ws, wss, ftp, file et tout schéma hiérarchique ou
# opaque) analysées comme dans un navigateur, manipulées sans les modifier (chaque with_* rend une nouvelle Url),
# résolues, relativisées, normalisées.
#
# | Module                     | Rôle                                                                  |
# |----------------------------|-----------------------------------------------------------------------|
# | web.url (ce module)        | Url, parse, join, quote / unquote                                     |
# | web.url.url_parser         | découpage et validation des composants (UrlParts)                     |
# | web.url.url_builder        | construction pas à pas (UrlBuilder)                                   |
# | web.url.scheme / host / port / path / path_segment / query / fragment   | chaque composant       |
# | web.url.query_params       | QueryParams (URLSearchParams)                                         |
# | web.url.percent_encoding   | « %XX » et ensembles d'encodage                                       |
# | web.url.form_url_encoding  | application/x-www-form-urlencoded                                     |
# | web.url.relative_url       | résolution (RFC 3986 §5) et références relatives                      |
# | web.url.url_normalization  | formes canoniques, équivalence, clé de cache                          |
# | web.url.url_errors         | UrlError, UrlSchemeError, UrlHostError, UrlPortError, UrlEncodingError |
#
#   use web.url as url
#   u := url.parse("https://Bücher.example:443/a b/./c?x=1&y=é#top")
#   u.href()                       # https://xn--bcher-kva.example/a%20b/c?x=1&y=%C3%A9#top
#   u.host, u.effective_port()     # xn--bcher-kva.example 443
#   u.param("y")                   # é
#   u.origin()                     # https://xn--bcher-kva.example
#   u.join("../d?z=2").href()      # https://xn--bcher-kva.example/d?z=2
#   u.with_param("page", 2).query  # x=1&y=%C3%A9&page=2
#   url.parse("/docs", "http://h/a/b").href()   # http://h/docs
#   url.try_parse("http://[::1") == null         # true
#
# Erreurs : UrlError, UrlSchemeError, UrlHostError, UrlPortError, UrlEncodingError (web.url.url_errors), TypeError.

from core use len, type
from collections use append
use string as _s
use web.url.url_errors as _err
use web.url.url_parser as _parser
from web.url.url_parser use UrlParts
use web.url.percent_encoding as _pe
use web.url.form_url_encoding as _form
use web.url.scheme as _scheme
use web.url.host as _host
use web.url.port as _port
use web.url.path as _path
use web.url.path_segment as _seg
use web.url.query as _query
use web.url.query_params as _qp
use web.url.fragment as _frag
use web.url.relative_url as _rel
use web.url.url_normalization as _norm

class Url extends UrlParts:
    # Forme textuelle complète.
    func href():
        return self.serialize()

    func to_string():
        return self.serialize()

    # Hôte sans crochets (adresse à donner à une socket) ; null s'il n'y a pas d'autorité.
    func hostname():
        if self.host == null:
            return null
        if _s.starts_with(self.host, "["):
            return self.host[1:len(self.host) - 1]
        return self.host

    # Hôte affichable (étiquettes Punycode décodées).
    func display_host():
        if self.host == null:
            return null
        if self.host_kind == _host.DOMAIN:
            return _host.to_unicode(self.host)
        return self.host

    # Port explicite, sinon port par défaut du schéma, sinon null.
    func effective_port():
        return _port.effective(self.scheme, self.port)

    # « hôte:port » (port seulement s'il est explicite).
    func host_port():
        if self.host == null:
            return null
        if self.port == null:
            return self.host
        return self.host + ":" + str(self.port)

    # Origine (WHATWG §4.7) : « schéma://hôte[:port] » pour http(s), ws(s), ftp ; « null » (opaque) sinon.
    func origin():
        if self.scheme == null or self.host == null or self.scheme == "file" or not _scheme.is_special(self.scheme):
            return "null"
        out := self.scheme + "://" + self.host
        if self.port != null:
            out = out + ":" + str(self.port)
        return out

    func same_origin(other):
        o := other
        if type(other) == "str":
            o = parse(other)
        return self.origin() != "null" and self.origin() == o.origin()

    # Cible de requête HTTP (forme « origin-form ») : chemin + « ?requête ».
    func target():
        p := self.path
        if p == "":
            p = "/"
        if self.query != null:
            return p + "?" + self.query
        return p

    func is_secure():
        return _scheme.is_secure(self.scheme)

    func is_http():
        return _scheme.is_http(self.scheme)

    func is_websocket():
        return _scheme.is_websocket(self.scheme)

    func is_loopback():
        if self.host == null:
            return false
        return _host.parse(self.hostname() if self.host_kind != _host.IPV6 else self.host, true).is_loopback()

    # Identifiants décodés.
    func user():
        return _pe.decode(self.username)

    func secret():
        if self.password == null:
            return null
        return _pe.decode(self.password)

    # ---------------------------------------------------------------- chemin

    func path_segments():
        return _path.decoded_segments(self.path)

    func filename():
        return _path.basename(self.path)

    func extension():
        return _path.extension(self.path)

    func decoded_path():
        return _pe.decode(self.path)

    # ---------------------------------------------------------------- requête

    func params():
        return _query.params(self.query)

    func param(name, fallback=null):
        return self.params().get(name, fallback)

    func param_all(name):
        return self.params().get_all(name)

    func has_param(name):
        return self.params().has(name)

    func decoded_fragment():
        return _frag.decode(self.fragment)

    # ---------------------------------------------------------------- copies modifiées

    func copy():
        return _from_parts(super.copy())

    func with_scheme(scheme):
        t := self.copy()
        t.scheme = _scheme.normalize(scheme)
        t.port = _port.canonical(t.scheme, t.port) if _scheme.is_special(t.scheme) else t.port
        if _scheme.is_special(t.scheme) and t.path == "":
            t.path = "/"
        return t

    # Hôte (nom, IPv4, IPv6 avec ou sans crochets) ; « hôte:port » accepté.
    func with_host(host):
        t := self.copy()
        h := host
        if not _s.starts_with(h, "[") and _s.count(h, ":") >= 2:
            h = "[" + h + "]"
        tmp := _parser.UrlParts(t.scheme)
        _parser.parse_authority(tmp, h, _scheme.is_special(t.scheme))
        t.host = tmp.host
        t.host_kind = tmp.host_kind
        if tmp.port != null or _s.contains(_s.replace(h, "[", "]"), "]:"):
            t.port = tmp.port
        if t.path == "" and _scheme.is_special(t.scheme):
            t.path = "/"
        return t

    func with_port(port):
        t := self.copy()
        if port == null:
            t.port = null
        else:
            p := _port.parse(port)
            t.port = _port.canonical(t.scheme, p) if _scheme.is_special(t.scheme) else p
        return t

    # Chemin brut (encodé au besoin) ; les segments « . » / « .. » sont résolus.
    func with_path(path):
        t := self.copy()
        p := _pe.encode_path(str(path))
        if t.host != null and not _s.starts_with(p, "/") and p != "":
            p = "/" + p
        t.path = _path.remove_dot_segments(p)
        if t.path == "" and _scheme.is_special(t.scheme):
            t.path = "/"
        return t

    # Ajoute des segments (valeurs décodées, encodées au passage) au chemin.
    func with_segments(values):
        t := self.copy()
        p := t.path
        for v in values:
            p = _path.join(p, _seg.encode(str(v)))
        t.path = p
        return t

    # Requête brute (str), dict / liste de paires / QueryParams (encodés), ou null pour la retirer.
    func with_query(query):
        t := self.copy()
        if query == null:
            t.query = null
        elif type(query) == "str":
            q := query
            if _s.starts_with(q, "?"):
                q = q[1:len(q)]
            t.query = _query.encode(q, _scheme.is_special(t.scheme))
        else:
            t.query = _query.build(query)
        return t

    # Remplace / ajoute les paramètres d'un dict (une valeur null supprime le paramètre).
    func with_params(updates):
        t := self.copy()
        t.query = _query.merge(self.query, updates)
        if t.query == "":
            t.query = null
        return t

    func with_param(name, value):
        p := self.params()
        p.set(name, value)
        t := self.copy()
        t.query = p.to_string()
        return t

    func add_param(name, value):
        p := self.params()
        p.add(name, value)
        t := self.copy()
        t.query = p.to_string()
        return t

    func without_param(name):
        t := self.copy()
        t.query = _query.without(self.query, [name])
        if t.query == "":
            t.query = null
        return t

    func without_query():
        return self.with_query(null)

    func with_fragment(fragment):
        t := self.copy()
        t.fragment = _frag.encode(fragment) if fragment != null else null
        return t

    func without_fragment():
        return self.with_fragment(null)

    # Identifiants (valeurs décodées) ; null retire.
    func with_userinfo(username=null, password=null):
        t := self.copy()
        t.username = _pe.encode_userinfo(username) if username != null else ""
        t.password = _pe.encode_userinfo(password) if password != null else null
        return t

    func without_userinfo():
        return self.with_userinfo(null, null)

    # Forme sans mot de passe (« *** »), pour les journaux.
    func redacted():
        if self.password == null:
            return self.serialize()
        t := self.copy()
        t.password = "***"
        return t.serialize()

    # ---------------------------------------------------------------- résolution, normalisation

    # Résout une référence (texte ou Url) contre cette URL.
    func join(ref):
        r := ref
        if type(ref) == "str":
            r = _parser.parse_reference(ref, self.scheme)
        return _from_parts(_rel.resolve_parts(self, r))

    # Référence relative qui mène de base (cette URL si base est null) à target.
    func relative_to(base):
        b := base
        if type(base) == "str":
            b = parse(base)
        return _rel.relativize_parts(b, self)

    func normalize(options=null):
        return _from_parts(_norm.normalize_parts(self, options))

    func equivalent(other, options=null):
        o := other
        if type(other) == "str":
            o = parse(other)
        return self.normalize(options).serialize() == o.normalize(options).serialize()

    func __eq__(other):
        if type(other) == "str":
            return self.serialize() == other
        return isinstance(other, _parser.UrlParts) and self.serialize() == other.serialize()

    func __str__():
        return self.serialize()

    # Composants dans un dict (diagnostic, JSON).
    func to_dict():
        return {"href": self.serialize(), "scheme": self.scheme, "username": self.username, "password": self.password, "host": self.host, "hostname": self.hostname(), "port": self.port, "path": self.path, "query": self.query, "fragment": self.fragment, "origin": self.origin()}

func _from_parts(p):
    return Url(p.scheme, p.username, p.password, p.host, p.port, p.path, p.query, p.fragment, p.host_kind)

# ---------------------------------------------------------------- fonctions

# Analyse une URL ; base (texte ou Url) permet une référence relative.
func parse(text, base=null):
    _err.need_str("url.parse", "text", text)
    if base == null:
        return _from_parts(_parser.parse_absolute(text))
    b := base
    if type(base) == "str":
        b = _parser.parse_absolute(base)
    ref := _parser.parse_reference(text, b.scheme)
    if ref.scheme != null:
        return _from_parts(ref)
    return _from_parts(_rel.resolve_parts(b, ref))

# Comme parse, mais null au lieu d'une erreur.
func try_parse(text, base=null):
    try:
        return parse(text, base)
    catch e:
        return null

func is_valid(text, base=null):
    return try_parse(text, base) != null

# Vrai si text est une URL absolue http(s) valide.
func is_web_url(text):
    u := try_parse(text)
    return u != null and u.is_http() and u.host != null and u.host != ""

# Résolution d'une référence (texte) contre une base (texte) : texte.
func join(base, ref):
    return parse(ref, base).serialize()

# Url depuis ses composants (valeurs décodées pour userinfo, chemin brut, requête dict ou str).
func from_parts(scheme, host, port=null, path="/", query=null, fragment=null, username=null, password=null):
    u := parse(_scheme.normalize(scheme) + "://placeholder.invalid/")
    u = u.with_host(host)
    if port != null:
        u = u.with_port(port)
    u = u.with_path(path).with_query(query).with_fragment(fragment)
    if username != null:
        u = u.with_userinfo(username, password)
    return u

# Encodages usuels.
func quote(text, safe="/"):
    return _pe.encode(str(text), safe)

func quote_plus(text, safe=""):
    return _pe.encode(str(text), safe, true)

func unquote(text):
    return _pe.decode(text)

func unquote_plus(text):
    return _pe.decode(text, true)

func urlencode(data):
    return _form.encode(data)

func parse_qs(text):
    return _form.decode_multi(text)

func parse_qsl(text):
    return _form.decode(text)

func normalize(text, options=null):
    return _norm.normalize(text, options)
