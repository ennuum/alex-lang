# ALEX STANDARD LIBRARY — web.http.request_target
#
# Cible d'une requête HTTP/1.1 (RFC 9112 §3.2), le deuxième mot de la ligne de requête. Quatre formes :
#
#   origin-form     « /chemin?requête »              cas courant
#   absolute-form   « http://hôte/chemin?requête »   requêtes vers un mandataire (et acceptée par un serveur)
#   authority-form  « hôte:port »                    CONNECT uniquement
#   asterisk-form   « * »                            OPTIONS * uniquement
#
#   use web.http.request_target as rt
#   t := rt.parse("/docs/caf%C3%A9?page=2")
#   t.form, t.path, t.query          # origin /docs/caf%C3%A9 page=2
#   t.decoded_path()                 # /docs/café
#   t.params().get_int("page")       # 2
#   t.normalized_path()              # chemin sans « . » ni « .. » (sûr pour un routeur)
#   rt.parse("example.org:443", "CONNECT").host     # example.org
#   rt.parse("*", "OPTIONS").form    # asterisk
#
# Erreurs : HttpParseError (400 : forme invalide, caractère interdit), HttpLimitError (414 : cible trop longue).

from core use len, type
use string as _s
use web.http.http_errors as _err
use web.url.url as _url
use web.url.path as _path
use web.url.query as _query
use web.url.percent_encoding as _pe
use web.url.port as _port

const ORIGIN := "origin"
const ABSOLUTE := "absolute"
const AUTHORITY := "authority"
const ASTERISK := "asterisk"

const DEFAULT_MAX_LENGTH := 8192

class RequestTarget:
    func init(raw, form, path="/", query=null, host=null, port=null, scheme=null):
        self.raw = raw          # texte reçu
        self.form = form        # origin, absolute, authority, asterisk
        self.path = path        # chemin encodé
        self.query = query      # requête encodée sans « ? », ou null
        self.host = host        # absolute / authority : hôte
        self.port = port        # absolute / authority : port (null : défaut)
        self.scheme = scheme    # absolute : schéma

    # Chemin décodé (« %C3%A9 » -> « é ») ; « %2F » reste « / » une fois décodé : préférer segments().
    func decoded_path():
        return _pe.decode(self.path)

    # Valeurs décodées des segments.
    func segments():
        return _path.decoded_segments(self.path)

    # Chemin sans segments « . » / « .. » (forme encodée), « / » si vide.
    func normalized_path():
        p := _path.remove_dot_segments(self.path)
        if p == "":
            return "/"
        return p

    # Vrai si le chemin contient des segments « . » ou « .. » (encodés ou non).
    func has_dot_segments():
        return self.normalized_path() != self.path

    func params():
        return _query.params(self.query)

    # « /chemin?requête » (origin-form équivalent).
    func origin_form():
        if self.query != null:
            return self.path + "?" + self.query
        return self.path

    func __str__():
        return self.raw

func _check_chars(fn, text):
    for c in text:
        o := _s.ord(c)
        if o <= 32 or o == 127:
            _err.parse_error(fn, "caractère interdit dans la cible de requête")

# Analyse la cible ; method permet de contrôler les formes authority (CONNECT) et asterisk (OPTIONS) ;
# max_length=false : pas de limite de longueur.
func parse(text, method=null, max_length=DEFAULT_MAX_LENGTH):
    fn := "request_target.parse"
    if type(text) != "str" or text == "":
        _err.parse_error(fn, "cible de requête vide")
    if max_length != null and max_length != false and _s.byte_len(text) > max_length:
        _err.limit_error(fn, "cible de requête de plus de " + str(max_length) + " octets", 414)
    _check_chars(fn, text)
    if text == "*":
        if method != null and method != "OPTIONS":
            _err.parse_error(fn, "« * » n'est permise qu'avec OPTIONS")
        return RequestTarget(text, ASTERISK, "*")
    if text[0] == '/':
        if _s.starts_with(text, "//"):
            # « //x » serait pris pour une autorité par un analyseur d'URL : chemin tel quel
            q := _s.find(text, "?")
            if q < 0:
                return RequestTarget(text, ORIGIN, text)
            return RequestTarget(text, ORIGIN, text[0:q], text[q + 1:len(text)])
        sp := _query.split(text)
        h := _s.find(sp[0], "#")
        if h >= 0:
            _err.parse_error(fn, "fragment « # » interdit dans une cible de requête")
        return RequestTarget(text, ORIGIN, sp[0], sp[1])
    if method == "CONNECT":
        return _authority(fn, text)
    if _s.contains(text, "://"):
        u := null
        try:
            u = _url.parse(text)
        catch e:
            _err.parse_error(fn, "cible absolue invalide : " + e.message)
        if u.host == null or u.host == "":
            _err.parse_error(fn, "cible absolue sans hôte")
        return RequestTarget(text, ABSOLUTE, u.path if u.path != "" else "/", u.query, u.hostname(), u.port, u.scheme)
    _err.parse_error(fn, "cible de requête invalide (« / », URL absolue, « hôte:port » ou « * » attendus)")

func _authority(fn, text):
    c := -1
    i := len(text) - 1
    while i >= 0:
        if text[i] == ':':
            c = i
            break
        i -= 1
    if c <= 0:
        _err.parse_error(fn, "CONNECT : « hôte:port » attendu")
    host := text[0:c]
    p := null
    try:
        p = _port.parse(text[c + 1:len(text)])
    catch e:
        _err.parse_error(fn, "CONNECT : port invalide")
    if p == null:
        _err.parse_error(fn, "CONNECT : port manquant")
    if _s.starts_with(host, "[") and _s.ends_with(host, "]"):
        host = host[1:len(host) - 1]
    return RequestTarget(text, AUTHORITY, "", null, host, p, null)

func try_parse(text, method=null):
    try:
        return parse(text, method)
    catch e:
        return null

# Cible origin-form à partir d'un chemin et d'une requête (str ou dict de paramètres).
func build(path="/", query=null):
    p := _path.encode(path)
    if not _s.starts_with(p, "/"):
        p = "/" + p
    q := null
    if query != null:
        if type(query) == "str":
            q = _query.encode(query)
        else:
            q = _query.build(query)
    if q != null and q != "":
        return p + "?" + q
    return p
