# ALEX STANDARD LIBRARY — web.url.url_builder
#
# UrlBuilder : construction d'une URL pas à pas, à partir de VALEURS DÉCODÉES (segments, paramètres, identifiants)
# encodées au moment de build(). Chaque méthode renvoie le constructeur (chaînage).
#
#   use web.url.url_builder as ub
#   b := ub.UrlBuilder("https", "api.exemple.org")
#   b.segment("v1").segment("utilisateurs").segment("Zoé Martin")
#   b.param("champs", "nom,email").param("tag", ["a", "b"]).fragment("résumé")
#   u := b.build()
#   u.href()    # https://api.exemple.org/v1/utilisateurs/Zo%C3%A9%20Martin?champs=nom%2Cemail&tag=a&tag=b#r%C3%A9sum%C3%A9
#
#   b := ub.from_url("http://h/a?x=1")      # repartir d'une URL existante
#   b.clear_params().port(8080).path("/b/").build_string()   # http://h:8080/b/
#
# Erreurs : celles de web.url (hôte, port, schéma invalides) levées par build().

from core use len, type
from collections use append
use string as _s
use web.url.url as _url
use web.url.scheme as _scheme
use web.url.path_segment as _seg
use web.url.query_params as _qp
use web.url.percent_encoding as _pe

class UrlBuilder:
    func init(scheme="https", host=null):
        self._scheme = scheme
        self._host = host
        self._port = null
        self._user = null
        self._password = null
        self._segments = []          # valeurs décodées
        self._raw_path = null        # chemin brut (path()) avant les segments
        self._trailing_slash = false
        self._params = _qp.QueryParams()
        self._fragment = null

    func scheme(value):
        self._scheme = value
        return self

    func host(value):
        self._host = value
        return self

    func port(value):
        self._port = value
        return self

    func userinfo(username, password=null):
        self._user = username
        self._password = password
        return self

    # Chemin brut (encodé au besoin, « / » gardés) ; remplace les segments ajoutés jusque-là.
    func path(value):
        self._raw_path = value
        self._segments = []
        self._trailing_slash = _s.ends_with(value, "/")
        return self

    # Ajoute un segment (valeur décodée : « / » y est encodé).
    func segment(value):
        append(self._segments, str(value))
        self._trailing_slash = false
        return self

    func segments(values):
        for v in values:
            self.segment(v)
        return self

    func trailing_slash(on=true):
        self._trailing_slash = on
        return self

    # Ajoute une valeur au paramètre (les valeurs multiples sont gardées).
    func param(name, value):
        if type(value) == "list" or type(value) == "tuple":
            for v in value:
                self._params.add(name, v)
        elif value != null:
            self._params.add(name, value)
        return self

    # Remplace toutes les valeurs du paramètre.
    func set_param(name, value):
        self._params.set(name, value)
        return self

    func params(data):
        self._params.update(data)
        return self

    func remove_param(name):
        self._params.remove(name)
        return self

    func clear_params():
        self._params.clear()
        return self

    func fragment(value):
        self._fragment = value
        return self

    func _path_text():
        p := ""
        if self._raw_path != null:
            p = _pe.encode_path(self._raw_path)
        for v in self._segments:
            if not _s.ends_with(p, "/"):
                p = p + "/"
            p = p + _seg.encode(v)
        if self._trailing_slash and not _s.ends_with(p, "/"):
            p = p + "/"
        if p == "" or not _s.starts_with(p, "/"):
            p = "/" + p
        return p

    # Url (web.url.Url) ; erreurs de validation levées ici.
    func build():
        if self._host == null:
            raise("UrlError", "UrlBuilder.build : hôte manquant")
        u := _url.parse(_scheme.normalize(self._scheme) + "://placeholder.invalid/")
        u = u.with_host(str(self._host))
        if self._port != null:
            u = u.with_port(self._port)
        u.path = _path_normalized(self._path_text())
        if not self._params.is_empty():
            u.query = self._params.to_string()
        if self._fragment != null:
            u = u.with_fragment(self._fragment)
        if self._user != null:
            u = u.with_userinfo(self._user, self._password)
        return u

    func build_string():
        return self.build().href()

    func __str__():
        return self.build_string()

func _path_normalized(p):
    return _url.parse("http://x" + p).path

# Constructeur prérempli depuis une URL (texte ou Url).
func from_url(u):
    x := u
    if type(u) == "str":
        x = _url.parse(u)
    b := UrlBuilder(x.scheme, x.hostname() if x.host_kind != "ipv6" else x.host)
    b._port = x.port
    if x.username != "":
        b._user = _pe.decode(x.username)
        b._password = _pe.decode(x.password) if x.password != null else null
    b._raw_path = x.path
    b._trailing_slash = _s.ends_with(x.path, "/")
    b._params = x.params()
    b._fragment = _pe.decode(x.fragment) if x.fragment != null else null
    return b

func builder(scheme="https", host=null):
    return UrlBuilder(scheme, host)
