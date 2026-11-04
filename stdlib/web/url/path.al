# ALEX STANDARD LIBRARY — web.url.path
#
# Chemins d'URL (RFC 3986 §3.3, §5.2.3-5.2.4) : découpage en segments, suppression des segments « . » et « .. »,
# fusion avec un chemin de base, jointure, chemin relatif entre deux chemins. Les chemins manipulés ici sont sous
# forme ENCODÉE (« /a%20b/c ») ; decoded_segments / from_segments passent des valeurs décodées.
#
#   use web.url.path as p
#   p.remove_dot_segments("/a/b/../c/./d")      # /a/c/d
#   p.merge("/a/b/c", "d/e", true)              # /a/b/d/e
#   p.join("/api/", "v1", "/users")            # /api/v1/users
#   p.decoded_segments("/docs/caf%C3%A9")       # ["docs", "café"]
#   p.from_segments(["docs", "a b"])           # /docs/a%20b
#   p.relative("/a/b/c", "/a/d/e")              # ../d/e
#   x := p.Path("/a/b/")                        # x.segments == ["a", "b", ""], x.parent().text == "/a/"
#
# Erreurs : TypeError.

from core use len, type
from collections use append, pop
use string as _s
use web.url.url_errors as _err
use web.url.percent_encoding as _pe
use web.url.path_segment as _seg

func is_absolute(path):
    return len(path) > 0 and path[0] == '/'

# Segments encodés (sans le « / » initial d'un chemin absolu) : « /a/b/ » -> ["a", "b", ""].
func segments(path):
    _err.need_str("path.segments", "path", path)
    if path == "" or path == "/":
        return []
    p := path
    if p[0] == '/':
        p = p[1:len(p)]
    return _s.split(p, "/")

# Valeurs décodées des segments.
func decoded_segments(path):
    out := []
    for s in segments(path):
        append(out, _seg.decode(s))
    return out

# Chemin encodé depuis des valeurs de segments (chaque valeur est encodée, « / » compris).
func from_segments(values, absolute=true, trailing_slash=false):
    enc := []
    for v in values:
        append(enc, _seg.encode(str(v)))
    out := _s.join("/", enc)
    if absolute:
        out = "/" + out
    if trailing_slash and not _s.ends_with(out, "/"):
        out = out + "/"
    return out

# Encode les caractères qui ne peuvent figurer tels quels dans un chemin (espace, non ASCII, « ? », « # »...) en
# gardant « / » et les « %XX » existants.
func encode(path):
    return _pe.encode_path(path)

func decode(path):
    return _pe.decode(path)

# Suppression des segments « . » et « .. » (RFC 3986 §5.2.4 ; formes encodées « %2e » reconnues comme un
# navigateur). Un « .. » au-dessus de la racine est ignoré.
func remove_dot_segments(path):
    _err.need_str("path.remove_dot_segments", "path", path)
    if path == "":
        return ""
    absolute := path[0] == '/'
    parts := _s.split(path, "/")
    if absolute:
        parts = parts[1:len(parts)]
    out := []
    n := len(parts)
    i := 0
    while i < n:
        seg := parts[i]
        last := i == n - 1
        if _seg.is_double_dot(seg):
            if len(out) > 0:
                pop(out)
            if last:
                append(out, "")
        elif _seg.is_single_dot(seg):
            if last:
                append(out, "")
        else:
            append(out, seg)
        i += 1
    result := _s.join("/", out)
    if absolute:
        return "/" + result
    return result

# Fusion d'un chemin relatif avec le chemin de base (RFC 3986 §5.2.3).
func merge(base_path, ref_path, base_has_authority=false):
    if base_has_authority and base_path == "":
        return "/" + ref_path
    i := len(base_path) - 1
    while i >= 0:
        if base_path[i] == '/':
            return base_path[0:i + 1] + ref_path
        i -= 1
    return ref_path

# Jointure de morceaux de chemin par un seul « / » (les « / » en double aux jonctions sont fusionnés). Le premier
# morceau décide si le résultat est absolu ; le dernier s'il se termine par « / ».
func join(first, second=null, third=null, fourth=null, fifth=null, sixth=null):
    parts := []
    for p in [first, second, third, fourth, fifth, sixth]:
        if p != null:
            append(parts, str(p))
    if len(parts) == 0:
        return ""
    out := parts[0]
    i := 1
    while i < len(parts):
        nxt := parts[i]
        if nxt != "":
            a := _s.ends_with(out, "/")
            b := _s.starts_with(nxt, "/")
            if a and b:
                out = out + nxt[1:len(nxt)]
            elif a or b or out == "":
                out = out + nxt
            else:
                out = out + "/" + nxt
        i += 1
    return out

# Jointure depuis une liste de morceaux.
func join_all(parts):
    out := ""
    for p in parts:
        out = join(out, p)
    return out

# Forme normalisée : segments « . » / « .. » supprimés, encodage « %XX » normalisé ; "" devient « / » si absolute.
func normalize(path, empty_as_root=true):
    p := remove_dot_segments(_pe.normalize(encode(path)))
    if p == "" and empty_as_root:
        return "/"
    return p

# Dernier segment (décodé), "" pour un chemin terminé par « / ».
func basename(path):
    segs := segments(path)
    if len(segs) == 0:
        return ""
    return _seg.decode(segs[len(segs) - 1])

# Chemin du « dossier » contenant (jusqu'au dernier « / » inclus).
func dirname(path):
    i := len(path) - 1
    while i >= 0:
        if path[i] == '/':
            return path[0:i + 1]
        i -= 1
    return ""

# Extension du dernier segment (sans le point), ou "".
func extension(path):
    segs := segments(path)
    if len(segs) == 0:
        return ""
    return _seg.extension(segs[len(segs) - 1])

# Chemin parent : « /a/b/c » -> « /a/b/ », « /a/b/ » -> « /a/ », « / » -> « / ».
func parent(path):
    if path == "/" or path == "":
        return path
    p := path
    if _s.ends_with(p, "/"):
        p = p[0:len(p) - 1]
    d := dirname(p)
    if d == "" and is_absolute(path):
        return "/"
    return d

# Vrai si path se trouve sous prefix (au sens des segments : « /api » couvre « /api/x » mais pas « /apix »).
func starts_with_segments(path, prefix):
    if prefix == "" or prefix == "/":
        return true
    p := prefix
    if _s.ends_with(p, "/"):
        p = p[0:len(p) - 1]
    if path == p:
        return true
    return _s.starts_with(path, p + "/")

# Chemin relatif qui mène de base à target (deux chemins absolus) : relative("/a/b/c", "/a/d") == "../d".
func relative(base, target):
    bs := segments(base)
    ts := segments(target)
    if len(bs) > 0:
        bs = bs[0:len(bs) - 1]     # le dernier segment de la base est un « fichier »
    common := 0
    while common < len(bs) and common < len(ts) - 1 and bs[common] == ts[common]:
        common += 1
    out := []
    i := common
    while i < len(bs):
        append(out, "..")
        i += 1
    j := common
    while j < len(ts):
        append(out, ts[j])
        j += 1
    rel := _s.join("/", out)
    if rel == "":
        if len(ts) > 0:
            return ts[len(ts) - 1] if ts[len(ts) - 1] != "" else "./"
        return "./"
    first := out[0]
    if _s.contains(first, ":") and not _s.starts_with(first, ".."):
        rel = "./" + rel     # « a:b » serait pris pour un schéma
    return rel

# ---------------------------------------------------------------- objet chemin

class Path:
    func init(text="/"):
        _err.need_str("path.Path", "text", text)
        self.text = text

    func segments():
        return segments(self.text)

    func values():
        return decoded_segments(self.text)

    func is_absolute():
        return is_absolute(self.text)

    func has_trailing_slash():
        return _s.ends_with(self.text, "/")

    func normalize():
        return Path(normalize(self.text))

    func join(other):
        return Path(join(self.text, str(other)))

    # Ajoute une VALEUR de segment (encodée au passage).
    func child(value):
        return Path(join(self.text, _seg.encode(str(value))))

    func parent():
        return Path(parent(self.text))

    func basename():
        return basename(self.text)

    func extension():
        return extension(self.text)

    func relative_to(base):
        return relative(str(base), self.text)

    func __str__():
        return self.text

    func __eq__(other):
        return isinstance(other, Path) and other.text == self.text

func parse(text):
    return Path(text)
