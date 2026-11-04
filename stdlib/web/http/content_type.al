# ALEX STANDARD LIBRARY — web.http.content_type
#
# Types de médias (en-tête Content-Type, RFC 9110 §8.3) : « type/sous-type; paramètres ». Analyse, comparaison
# avec jokers, charset, frontière multipart, et table des types usuels par extension de fichier.
#
#   use web.http.content_type as ct
#   m := ct.parse("Text/HTML; Charset=\"UTF-8\"")
#   m.essence()                  # text/html     (type et sous-type en minuscules)
#   m.charset()                  # utf-8
#   m.is_text()                  # true
#   m.matches("text/*")          # true
#   str(ct.json())               # application/json
#   str(ct.text("html"))         # text/html; charset=utf-8
#   ct.guess("photo.JPG")        # image/jpeg
#   ct.guess("inconnu.xyz")      # application/octet-stream
#   ct.extension_for("image/png")   # png
#
# Erreurs : HttpHeaderError (type mal formé), TypeError.

from core use len, type
from collections use append, keys
use string as _s
use web.http.http_errors as _err
use web.http.header_value as _hv
use web.http.method as _method

const TEXT_PLAIN := "text/plain"
const TEXT_HTML := "text/html"
const TEXT_CSS := "text/css"
const TEXT_CSV := "text/csv"
const TEXT_JAVASCRIPT := "text/javascript"
const APPLICATION_JSON := "application/json"
const APPLICATION_XML := "application/xml"
const APPLICATION_OCTET_STREAM := "application/octet-stream"
const APPLICATION_FORM := "application/x-www-form-urlencoded"
const MULTIPART_FORM := "multipart/form-data"
const DEFAULT_CHARSET := "utf-8"

const _TYPES := {"html": "text/html", "htm": "text/html", "xhtml": "application/xhtml+xml", "css": "text/css", "js": "text/javascript", "mjs": "text/javascript", "cjs": "text/javascript", "json": "application/json", "jsonld": "application/ld+json", "map": "application/json", "webmanifest": "application/manifest+json", "xml": "application/xml", "rss": "application/rss+xml", "atom": "application/atom+xml", "txt": "text/plain", "text": "text/plain", "log": "text/plain", "md": "text/markdown", "markdown": "text/markdown", "csv": "text/csv", "tsv": "text/tab-separated-values", "ics": "text/calendar", "vcf": "text/vcard", "yaml": "application/yaml", "yml": "application/yaml", "toml": "application/toml", "al": "text/plain", "png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "jpe": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "avif": "image/avif", "svg": "image/svg+xml", "svgz": "image/svg+xml", "ico": "image/vnd.microsoft.icon", "bmp": "image/bmp", "tif": "image/tiff", "tiff": "image/tiff", "heic": "image/heic", "apng": "image/apng", "woff": "font/woff", "woff2": "font/woff2", "ttf": "font/ttf", "otf": "font/otf", "eot": "application/vnd.ms-fontobject", "mp3": "audio/mpeg", "wav": "audio/wav", "ogg": "audio/ogg", "oga": "audio/ogg", "opus": "audio/opus", "flac": "audio/flac", "m4a": "audio/mp4", "aac": "audio/aac", "weba": "audio/webm", "mid": "audio/midi", "midi": "audio/midi", "mp4": "video/mp4", "m4v": "video/mp4", "webm": "video/webm", "ogv": "video/ogg", "mov": "video/quicktime", "avi": "video/x-msvideo", "mkv": "video/x-matroska", "mpeg": "video/mpeg", "ts": "video/mp2t", "m3u8": "application/vnd.apple.mpegurl", "pdf": "application/pdf", "zip": "application/zip", "gz": "application/gzip", "tgz": "application/gzip", "tar": "application/x-tar", "bz2": "application/x-bzip2", "xz": "application/x-xz", "7z": "application/x-7z-compressed", "rar": "application/vnd.rar", "wasm": "application/wasm", "doc": "application/msword", "docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", "xls": "application/vnd.ms-excel", "xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", "ppt": "application/vnd.ms-powerpoint", "pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation", "odt": "application/vnd.oasis.opendocument.text", "ods": "application/vnd.oasis.opendocument.spreadsheet", "odp": "application/vnd.oasis.opendocument.presentation", "rtf": "application/rtf", "epub": "application/epub+zip", "jar": "application/java-archive", "bin": "application/octet-stream", "exe": "application/octet-stream", "dll": "application/octet-stream", "iso": "application/octet-stream", "dmg": "application/octet-stream", "deb": "application/vnd.debian.binary-package", "apk": "application/vnd.android.package-archive", "sh": "application/x-sh", "py": "text/x-python", "c": "text/x-c", "h": "text/x-c", "cpp": "text/x-c++", "java": "text/x-java", "go": "text/x-go", "rs": "text/x-rust", "sql": "application/sql", "graphql": "application/graphql", "pem": "application/x-pem-file", "crt": "application/x-x509-ca-cert", "der": "application/x-x509-ca-cert"}

# Types textuels hors « text/* ».
const _TEXTUAL := ["application/json", "application/xml", "application/javascript", "application/xhtml+xml", "application/ld+json", "application/manifest+json", "application/rss+xml", "application/atom+xml", "application/yaml", "application/toml", "application/sql", "application/graphql", "application/x-www-form-urlencoded", "image/svg+xml", "application/x-sh"]

class MediaType:
    func init(main="application", sub="octet-stream", params=null):
        self.main = _s.lower(main)
        self.sub = _s.lower(sub)
        self.params = params if params != null else {}

    # « type/sous-type » en minuscules (sans paramètres).
    func essence():
        return self.main + "/" + self.sub

    func param(name, fallback=null):
        k := _s.lower(name)
        if k in self.params:
            return self.params[k]
        return fallback

    func charset(fallback=null):
        c := self.param("charset")
        if c == null:
            return fallback
        return _s.lower(c)

    func boundary():
        return self.param("boundary")

    # Suffixe structuré (RFC 6839) : « json » pour application/ld+json.
    func suffix():
        i := _s.find(self.sub, "+")
        if i < 0:
            return null
        return self.sub[i + 1:len(self.sub)]

    func is_text():
        return self.main == "text" or self.essence() in _TEXTUAL or self.suffix() == "json" or self.suffix() == "xml"

    func is_json():
        return self.essence() == APPLICATION_JSON or self.suffix() == "json"

    func is_html():
        return self.essence() == TEXT_HTML or self.essence() == "application/xhtml+xml"

    func is_xml():
        return self.essence() == APPLICATION_XML or self.essence() == "text/xml" or self.suffix() == "xml"

    func is_form():
        return self.essence() == APPLICATION_FORM

    func is_multipart():
        return self.main == "multipart"

    func is_image():
        return self.main == "image"

    func is_audio():
        return self.main == "audio"

    func is_video():
        return self.main == "video"

    func is_font():
        return self.main == "font"

    # Comparaison avec jokers : « */* », « text/* », ou type exact ; les paramètres de pattern doivent concorder.
    func matches(pattern):
        p := pattern
        if type(pattern) == "str":
            p = parse(pattern)
        if p.main != "*" and p.main != self.main:
            return false
        if p.sub != "*" and p.sub != self.sub:
            return false
        for k in keys(p.params):
            if k == "q":
                continue
            if self.param(k) == null or _s.lower(self.param(k)) != _s.lower(p.params[k]):
                return false
        return true

    func with_param(name, value):
        params := {}
        for k in keys(self.params):
            params[k] = self.params[k]
        if value == null:
            if _s.lower(name) in params:
                del params[_s.lower(name)]
        else:
            params[_s.lower(name)] = str(value)
        return MediaType(self.main, self.sub, params)

    func with_charset(charset):
        return self.with_param("charset", charset)

    func to_string():
        return _hv.format_parameters(self.essence(), self.params)

    func __str__():
        return self.to_string()

    func __eq__(other):
        o := other
        if type(other) == "str":
            o = try_parse(other)
            if o == null:
                return false
        if not isinstance(o, MediaType):
            return false
        if o.essence() != self.essence():
            return false
        return o.charset() == self.charset()

# Analyse un type de média ; HttpHeaderError s'il est mal formé.
func parse(text):
    fn := "content_type.parse"
    if type(text) != "str":
        raise("TypeError", fn + " : str attendue (obtenu " + type(text) + ")")
    pr := _hv.parse_parameters(text)
    essence := pr[0]
    slash := _s.find(essence, "/")
    if slash <= 0 or slash == len(essence) - 1:
        _err.header_error(fn, "type de média invalide '" + _hv.sanitize(text) + "'")
    main := _hv.trim(essence[0:slash])
    sub := _hv.trim(essence[slash + 1:len(essence)])
    if not _method.is_token(main) or not _method.is_token(sub):
        _err.header_error(fn, "type de média invalide '" + _hv.sanitize(text) + "'")
    return MediaType(main, sub, pr[1])

func try_parse(text):
    if text == null:
        return null
    try:
        return parse(text)
    catch e:
        return null

func of(essence, params=null):
    m := parse(essence)
    if params != null:
        for k in keys(params):
            m.params[_s.lower(k)] = str(params[k])
    return m

# text/<sous-type>; charset=utf-8
func text(sub="plain", charset=DEFAULT_CHARSET):
    return MediaType("text", sub, {"charset": charset})

func html(charset=DEFAULT_CHARSET):
    return text("html", charset)

func json():
    return MediaType("application", "json")

func octet_stream():
    return MediaType("application", "octet-stream")

func form():
    return MediaType("application", "x-www-form-urlencoded")

func multipart(boundary, sub="form-data"):
    return MediaType("multipart", sub, {"boundary": boundary})

# Type de média selon l'extension d'un nom de fichier ou d'un chemin (fallback si inconnue).
func guess(filename, fallback=APPLICATION_OCTET_STREAM):
    ext := extension_of(filename)
    if ext in _registered:
        return _registered[ext]
    if ext in _TYPES:
        return _TYPES[ext]
    return fallback

# Comme guess, avec « ; charset=utf-8 » pour les types textuels (valeur prête pour Content-Type).
func guess_with_charset(filename, fallback=APPLICATION_OCTET_STREAM):
    t := guess(filename, fallback)
    m := parse(t)
    if m.is_text() and m.charset() == null:
        return t + "; charset=utf-8"
    return t

func extension_of(filename):
    name := str(filename)
    i := len(name) - 1
    while i >= 0:
        c := name[i]
        if c == '.':
            return _s.lower(name[i + 1:len(name)])
        if c == '/' or c == '\\':
            return ""
        i -= 1
    return ""

# Extension usuelle d'un type de média, ou null.
func extension_for(media_type):
    e := media_type
    if type(media_type) != "str":
        e = media_type.essence()
    else:
        m := try_parse(media_type)
        if m != null:
            e = m.essence()
    preferred := {"text/html": "html", "image/jpeg": "jpg", "text/javascript": "js", "text/plain": "txt", "image/tiff": "tiff", "audio/mpeg": "mp3", "video/mp4": "mp4", "application/gzip": "gz"}
    if e in preferred:
        return preferred[e]
    for k in keys(_TYPES):
        if _TYPES[k] == e:
            return k
    return null

# Types ajoutés par l'application : register("dart", "application/dart") (prioritaires sur la table).
_registered := {}

func register(extension, media_type):
    parse(media_type)
    _registered[_s.lower(extension)] = media_type

func known_extensions():
    out := keys(_TYPES)
    for k in keys(_registered):
        if not (k in out):
            append(out, k)
    return out
