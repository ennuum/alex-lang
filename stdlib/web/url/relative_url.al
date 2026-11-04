# ALEX STANDARD LIBRARY — web.url.relative_url
#
# Références relatives (RFC 3986 §4.2, §5) : résolution d'une référence (« ../img/a.png », « //cdn/x »,
# « ?page=2 », « #haut ») contre une URL de base, et l'inverse : la référence la plus courte qui mène d'une base à
# une cible (pour produire des liens relatifs dans un site statique, par exemple).
#
#   use web.url.relative_url as rel
#   rel.resolve("http://a/b/c/d;p?q", "../g")        # http://a/b/g          (exemples de la RFC 3986 §5.4)
#   rel.resolve("http://a/b/c/d;p?q", "?y")          # http://a/b/c/d;p?y
#   rel.resolve("http://a/b/c/d;p?q", "//g")         # http://g/
#   rel.relativize("https://h/a/b/c", "https://h/a/d?x=1")   # ../d?x=1
#   rel.relativize("https://h/a", "http://h/a")      # http://h/a   (autre schéma : URL absolue)
#   rel.is_relative("../x")                          # true
#
# Les fonctions *_parts travaillent sur des web.url.url_parser.UrlParts ; les autres sur du texte.
# Erreurs : UrlError (base relative, base à chemin opaque), et celles de web.url.url_parser.

from core use len
use string as _s
use web.url.url_errors as _err
use web.url.url_parser as _parser
use web.url.path as _path
use web.url.scheme as _scheme

# Résolution RFC 3986 §5.2.2 de ref (UrlParts) contre base (UrlParts absolu) ; renvoie un nouvel UrlParts.
func resolve_parts(base, ref):
    fn := "relative_url.resolve"
    if base.scheme == null:
        _err.url_error(fn, "la base doit être une URL absolue (obtenu '" + base.serialize() + "')")
    t := _parser.UrlParts()
    if ref.scheme != null:
        t = ref.copy()
        if not t.has_opaque_path():
            t.path = _path.remove_dot_segments(t.path)
        return _finish(t)
    if base.has_opaque_path():
        if ref.path == "" and ref.host == null and ref.query == null:
            t = base.copy()
            t.fragment = ref.fragment
            return t
        _err.url_error(fn, "impossible de résoudre une référence contre une base à chemin opaque '" + base.serialize() + "'")
    if ref.host != null:
        t.username = ref.username
        t.password = ref.password
        t.host = ref.host
        t.host_kind = ref.host_kind
        t.port = ref.port
        t.path = _path.remove_dot_segments(ref.path)
        t.query = ref.query
    else:
        if ref.path == "":
            t.path = base.path
            t.query = ref.query if ref.query != null else base.query
        else:
            if _s.starts_with(ref.path, "/"):
                t.path = _path.remove_dot_segments(ref.path)
            else:
                t.path = _path.remove_dot_segments(_path.merge(base.path, ref.path, base.host != null))
            t.query = ref.query
        t.username = base.username
        t.password = base.password
        t.host = base.host
        t.host_kind = base.host_kind
        t.port = base.port
    t.scheme = base.scheme
    t.fragment = ref.fragment
    return _finish(t)

func _finish(t):
    if _scheme.is_special(t.scheme) and t.path == "":
        t.path = "/"
    if t.port != null and _scheme.is_special(t.scheme) and _scheme.is_default_port(t.scheme, t.port):
        t.port = null
    return t

# Résolution sur du texte : renvoie l'URL absolue (texte).
func resolve(base, ref):
    b := _parser.parse_absolute(base)
    return resolve_parts(b, _parser.parse_reference(ref, b.scheme)).serialize()

# Vrai si text est une référence relative (sans schéma).
func is_relative(text):
    return not _parser.has_scheme(text)

# Référence relative au réseau (« //hôte/chemin »).
func is_network_path(text):
    return _s.starts_with(_parser.clean(text), "//")

# Référence relative absolue en chemin (« /chemin »), sans autorité.
func is_absolute_path(text):
    t := _parser.clean(text)
    return _s.starts_with(t, "/") and not _s.starts_with(t, "//")

# Référence la plus courte qui, résolue contre base, donne target (UrlParts absolus).
func relativize_parts(base, target):
    if base.scheme != target.scheme:
        return target.serialize()
    if base.authority() != target.authority():
        out := "//" + target.authority() + target.path
        if target.query != null:
            out = out + "?" + target.query
        if target.fragment != null:
            out = out + "#" + target.fragment
        return out
    if base.has_opaque_path() or target.has_opaque_path():
        return target.serialize()
    out := ""
    if target.path == base.path:
        if target.query != base.query:
            if target.query != null:
                out = "?" + target.query
            else:
                out = _path.relative(base.path, target.path)
    else:
        out = _path.relative(base.path, target.path)
        if target.query != null:
            out = out + "?" + target.query
    if target.fragment != null:
        out = out + "#" + target.fragment
    return out

# Référence relative (texte) entre deux URL absolues (texte).
func relativize(base, target):
    return relativize_parts(_parser.parse_absolute(base), _parser.parse_absolute(target))
