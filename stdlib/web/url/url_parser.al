# ALEX STANDARD LIBRARY — web.url.url_parser
#
# Analyseur d'URL : découpe une URL absolue ou une référence relative en composants (RFC 3986 §3, §4.1) en
# appliquant les règles de tolérance des navigateurs (WHATWG URL) :
#   - espaces et contrôles C0 en début et fin supprimés, tabulations et sauts de ligne retirés ;
#   - schéma et hôte en minuscules, port par défaut omis, hôte IDNA / IPv4 / IPv6 normalisé (web.url.host) ;
#   - pour les schémas spéciaux (http, https, ws, wss, ftp, file) : « \ » vaut « / », « http:exemple.org » est
#     compris comme « http://exemple.org », un chemin vide devient « / » ;
#   - caractères interdits encodés dans chaque composant (espace -> %20, non ASCII -> UTF-8 encodé).
#
# Le résultat est un UrlParts (composants sous forme ENCODÉE) ; web.url.url en fait un Url complet, résout les
# références relatives (web.url.relative_url) et offre l'API de haut niveau. Utilisez de préférence web.url.
#
#   use web.url.url_parser as up
#   p := up.parse_reference("HTTP://Exemple.org:80/a/./b?x=1#f")
#   p.scheme, p.host, p.port, p.path, p.query, p.fragment     # http exemple.org null /a/b x=1 f
#   up.parse_reference("../c?d").scheme                      # null : référence relative
#   up.split("https://u:p@h:8443/p?q#f")                     # composants bruts, sans validation
#
# Erreurs : UrlError, UrlSchemeError, UrlHostError, UrlPortError, TypeError.

from core use len, type
from collections use append
use string as _s
use web.url.url_errors as _err
use web.url.percent_encoding as _pe
use web.url.scheme as _scheme
use web.url.host as _host
use web.url.port as _port
use web.url.path as _path

const MAX_LENGTH := 2097152

# Composants d'une URL ou d'une référence relative, sous forme encodée.
class UrlParts:
    func init(scheme=null, username="", password=null, host=null, port=null, path="", query=null, fragment=null, host_kind=null):
        self.scheme = scheme          # en minuscules ; null pour une référence relative
        self.username = username      # encodé ; "" si absent
        self.password = password      # encodé ; null si absent
        self.host = host              # forme canonique (IPv6 entre crochets) ; null : pas d'autorité
        self.host_kind = host_kind    # domain, ipv4, ipv6, opaque, empty (web.url.host)
        self.port = port              # int ; null si absent ou égal au port par défaut d'un schéma spécial
        self.path = path              # encodé
        self.query = query            # encodée, sans « ? » ; null si absente
        self.fragment = fragment      # encodé, sans « # » ; null si absent

    func has_authority():
        return self.host != null

    func is_special():
        return _scheme.is_special(self.scheme)

    func is_absolute():
        return self.scheme != null

    # Chemin « opaque » (mailto:x, urn:...) : pas d'autorité et chemin ne commençant pas par « / ».
    func has_opaque_path():
        return self.scheme != null and self.host == null and not _s.starts_with(self.path, "/")

    func userinfo():
        if self.username == "" and self.password == null:
            return ""
        if self.password == null:
            return self.username
        return self.username + ":" + self.password

    # « utilisateur:mot@hôte:port », ou null s'il n'y a pas d'autorité.
    func authority():
        if self.host == null:
            return null
        out := ""
        ui := self.userinfo()
        if ui != "":
            out = ui + "@"
        out = out + self.host
        if self.port != null:
            out = out + ":" + str(self.port)
        return out

    func copy():
        return UrlParts(self.scheme, self.username, self.password, self.host, self.port, self.path, self.query, self.fragment, self.host_kind)

    # Forme textuelle (WHATWG URL §4.5, « URL serializer »).
    func serialize(exclude_fragment=false):
        out := []
        if self.scheme != null:
            append(out, self.scheme + ":")
        if self.host != null:
            append(out, "//" + self.authority())
        elif self.scheme != null and _s.starts_with(self.path, "//"):
            append(out, "/.")
        append(out, self.path)
        if self.query != null:
            append(out, "?" + self.query)
        if self.fragment != null and not exclude_fragment:
            append(out, "#" + self.fragment)
        return _s.join("", out)

    func __str__():
        return self.serialize()

# ---------------------------------------------------------------- découpage brut

# Retire les espaces et contrôles C0 aux extrémités, et les tabulations / sauts de ligne partout.
func clean(text):
    _err.need_str("url_parser.clean", "text", text)
    if len(text) > MAX_LENGTH:
        _err.url_error("url_parser", "URL de plus de " + str(MAX_LENGTH) + " caractères")
    start := 0
    n := len(text)
    while start < n and _s.ord(text[start]) <= 32:
        start += 1
    end := n
    while end > start and _s.ord(text[end - 1]) <= 32:
        end -= 1
    t := text[start:end]
    if _s.contains(t, "\t") or _s.contains(t, "\n") or _s.contains(t, "\r"):
        t = _s.replace(_s.replace(_s.replace(t, "\t", ""), "\n", ""), "\r", "")
    return t

# Découpage RFC 3986 (annexe B) sans validation : dict scheme, authority, path, query, fragment (null si absents).
func split(text):
    t := text
    out := {"scheme": null, "authority": null, "path": "", "query": null, "fragment": null}
    h := _s.find(t, "#")
    if h >= 0:
        out["fragment"] = t[h + 1:len(t)]
        t = t[0:h]
    q := _s.find(t, "?")
    if q >= 0:
        out["query"] = t[q + 1:len(t)]
        t = t[0:q]
    sc := _scheme.detect(t)
    if sc != null:
        out["scheme"] = t[0:sc[1] - 1]
        t = t[sc[1]:len(t)]
    if _s.starts_with(t, "//"):
        rest := t[2:len(t)]
        slash := _s.find(rest, "/")
        if slash < 0:
            out["authority"] = rest
            t = ""
        else:
            out["authority"] = rest[0:slash]
            t = rest[slash:len(rest)]
    out["path"] = t
    return out

# ---------------------------------------------------------------- analyse

# Analyse une URL absolue ou une référence relative. base_scheme : schéma de la base éventuelle (une référence
# « http:chemin » sur une base http est relative, comme dans un navigateur ; sans schéma, les règles du schéma de
# la base s'appliquent).
func parse_reference(text, base_scheme=null):
    t := clean(text)
    parts := UrlParts()
    rest := t
    sc := _scheme.detect(t)
    if sc != null:
        parts.scheme = sc[0]
        rest = t[sc[1]:len(t)]
    special := false
    if parts.scheme != null:
        special = _scheme.is_special(parts.scheme)
    else:
        special = _scheme.is_special(base_scheme)
    # fragment, puis requête
    h := _s.find(rest, "#")
    if h >= 0:
        parts.fragment = _pe.encode_fragment(rest[h + 1:len(rest)])
        rest = rest[0:h]
    q := _s.find(rest, "?")
    if q >= 0:
        parts.query = _pe.encode_query(rest[q + 1:len(rest)], special)
        rest = rest[0:q]
    if special:
        rest = _s.replace(rest, "\\", "/")
    # « http:chemin » sur une base http : référence relative (WHATWG « special relative or authority »)
    if parts.scheme != null and special and parts.scheme == base_scheme and not _s.starts_with(rest, "//"):
        parts.scheme = null
    if _s.starts_with(rest, "//"):
        rest = rest[2:len(rest)]
        _parse_authority_and_path(parts, rest, special)
    elif parts.scheme != null and special and parts.scheme != "file":
        # « http:exemple.org/x » ou « http:/exemple.org » : l'autorité suit, barres obliques ignorées
        while _s.starts_with(rest, "/"):
            rest = rest[1:len(rest)]
        _parse_authority_and_path(parts, rest, special)
    elif parts.scheme == "file":
        parts.host = ""
        parts.host_kind = _host.EMPTY
        p := rest
        if not _s.starts_with(p, "/"):
            p = "/" + p
        parts.path = _pe.encode_path(p)
    else:
        if parts.scheme != null and not _s.starts_with(rest, "/"):
            parts.path = _pe.encode_set(rest, "")     # chemin opaque (mailto:, urn:, data:...)
        else:
            parts.path = _pe.encode_path(rest)
    if parts.scheme != null and not parts.has_opaque_path():
        parts.path = _path.remove_dot_segments(parts.path)
        if special and parts.path == "":
            parts.path = "/"
    return parts

func _parse_authority_and_path(parts, rest, special):
    end := len(rest)
    i := 0
    while i < len(rest):
        if rest[i] == '/':
            end = i
            break
        i += 1
    authority := rest[0:end]
    parts.path = _pe.encode_path(rest[end:len(rest)])
    parse_authority(parts, authority, special)

# Remplit username, password, host, host_kind et port de parts depuis le texte de l'autorité.
func parse_authority(parts, authority, special):
    fn := "url_parser.parse_authority"
    hostport := authority
    at := -1
    i := len(authority) - 1
    while i >= 0:
        if authority[i] == '@':
            at = i
            break
        i -= 1
    if at >= 0:
        info := authority[0:at]
        hostport = authority[at + 1:len(authority)]
        colon := _s.find(info, ":")
        if colon >= 0:
            parts.username = _pe.encode_userinfo(info[0:colon])
            parts.password = _pe.encode_userinfo(info[colon + 1:len(info)])
            if parts.password == "":
                parts.password = null
        else:
            parts.username = _pe.encode_userinfo(info)
    host_text := hostport
    port_text := null
    if _s.starts_with(hostport, "["):
        close := _s.find(hostport, "]")
        if close < 0:
            _err.host_error(fn, "IPv6 sans « ] » dans '" + authority + "'")
        host_text = hostport[0:close + 1]
        after := hostport[close + 1:len(hostport)]
        if after != "":
            if after[0] != ':':
                _err.url_error(fn, "texte inattendu après « ] » dans '" + authority + "'")
            port_text = after[1:len(after)]
    else:
        c := -1
        j := len(hostport) - 1
        while j >= 0:
            if hostport[j] == ':':
                c = j
                break
            j -= 1
        if c >= 0:
            host_text = hostport[0:c]
            port_text = hostport[c + 1:len(hostport)]
    if special and host_text == "" and parts.scheme != "file":
        _err.host_error(fn, "hôte vide dans '" + authority + "'")
    h := _host.parse(host_text, special)
    parts.host = h.serialize()
    parts.host_kind = h.kind
    p := _port.parse(port_text)
    if p != null and special and _scheme.is_default_port(parts.scheme, p):
        p = null
    parts.port = p
    if (parts.username != "" or parts.password != null or p != null) and h.kind == _host.EMPTY:
        _err.host_error(fn, "identifiants ou port sans hôte dans '" + authority + "'")

# Analyse une URL qui doit être absolue (avec schéma) ; UrlError sinon.
func parse_absolute(text):
    p := parse_reference(text)
    if p.scheme == null:
        _err.url_error("url_parser.parse_absolute", "URL relative sans base '" + text + "'")
    return p

# Vrai si text commence par un schéma valide.
func has_scheme(text):
    return _scheme.detect(clean(text)) != null
