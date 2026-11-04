# ALEX STANDARD LIBRARY — network.mime
#
# MIME (RFC 2045 à 2049, 2231, 2047) : types de contenu par extension, en-têtes encodés (« =?UTF-8?B?...?= »),
# encodages de transfert (7bit, 8bit, quoted-printable, base64), repli des longs en-têtes, et arbre de parties
# (MimePart) : construction, sérialisation, analyse, parcours. Sert de base à network.email et
# network.http_multipart.
#
#   guess_type("photo.JPG") -> "image/jpeg"        guess_extension("application/pdf") -> ".pdf"
#   encode_header("Café ☕") -> "=?utf-8?q?Caf=C3=A9_=E2=98=95?="     decode_header(...) -> texte
#   leaf(données, "text/plain; charset=utf-8")   multipart("mixed", [parties])
#   part.to_bytes()            message complet (CRLF)        parse(octets) -> MimePart
#   part.walk()                toutes les parties, en profondeur
#
# Erreurs : MimeError (structure invalide), EncodingError (encodage), TypeError.
#
# Exemple
#   use network.mime as mime
#   p := mime.multipart("mixed", [mime.leaf("Bonjour", "text/plain; charset=utf-8"),
#                         mime.leaf(octets_pdf, "application/pdf", null, "rapport.pdf")])
#   texte := p.to_bytes()
#   q := mime.parse(texte)
#   for part in q.walk():
#       print(part.content_type(), part.filename())

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use network.encoding as _enc
use network.http_headers as _hh

func _fail(message):
    raise("MimeError", "mime : " + message)

# ---------------------------------------------------------------- types par extension

_TYPES := {".txt": "text/plain", ".text": "text/plain", ".log": "text/plain", ".md": "text/markdown", ".csv": "text/csv", ".tsv": "text/tab-separated-values", ".html": "text/html", ".htm": "text/html", ".css": "text/css", ".js": "text/javascript", ".mjs": "text/javascript", ".xml": "application/xml", ".xsl": "application/xslt+xml", ".json": "application/json", ".jsonld": "application/ld+json", ".map": "application/json", ".yaml": "application/yaml", ".yml": "application/yaml", ".toml": "application/toml", ".ics": "text/calendar", ".vcf": "text/vcard", ".rtf": "application/rtf", ".pdf": "application/pdf", ".ps": "application/postscript", ".eps": "application/postscript", ".zip": "application/zip", ".gz": "application/gzip", ".tgz": "application/gzip", ".bz2": "application/x-bzip2", ".xz": "application/x-xz", ".7z": "application/x-7z-compressed", ".rar": "application/vnd.rar", ".tar": "application/x-tar", ".zst": "application/zstd", ".jar": "application/java-archive", ".wasm": "application/wasm", ".bin": "application/octet-stream", ".exe": "application/vnd.microsoft.portable-executable", ".dll": "application/vnd.microsoft.portable-executable", ".so": "application/octet-stream", ".deb": "application/vnd.debian.binary-package", ".rpm": "application/x-rpm", ".iso": "application/x-iso9660-image", ".doc": "application/msword", ".docx": "application/vnd.openxmlformats-officedocument.wordprocessingml.document", ".xls": "application/vnd.ms-excel", ".xlsx": "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet", ".ppt": "application/vnd.ms-powerpoint", ".pptx": "application/vnd.openxmlformats-officedocument.presentationml.presentation", ".odt": "application/vnd.oasis.opendocument.text", ".ods": "application/vnd.oasis.opendocument.spreadsheet", ".odp": "application/vnd.oasis.opendocument.presentation", ".epub": "application/epub+zip", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg", ".jpe": "image/jpeg", ".gif": "image/gif", ".webp": "image/webp", ".avif": "image/avif", ".bmp": "image/bmp", ".ico": "image/vnd.microsoft.icon", ".svg": "image/svg+xml", ".tif": "image/tiff", ".tiff": "image/tiff", ".heic": "image/heic", ".mp3": "audio/mpeg", ".wav": "audio/wav", ".ogg": "audio/ogg", ".oga": "audio/ogg", ".opus": "audio/opus", ".flac": "audio/flac", ".m4a": "audio/mp4", ".aac": "audio/aac", ".mid": "audio/midi", ".midi": "audio/midi", ".mp4": "video/mp4", ".m4v": "video/mp4", ".webm": "video/webm", ".ogv": "video/ogg", ".mov": "video/quicktime", ".avi": "video/x-msvideo", ".mkv": "video/x-matroska", ".mpeg": "video/mpeg", ".mpg": "video/mpeg", ".woff": "font/woff", ".woff2": "font/woff2", ".ttf": "font/ttf", ".otf": "font/otf", ".eml": "message/rfc822", ".mbox": "application/mbox", ".pem": "application/x-pem-file", ".crt": "application/x-x509-ca-cert", ".cer": "application/pkix-cert", ".der": "application/x-x509-ca-cert", ".p12": "application/x-pkcs12", ".pfx": "application/x-pkcs12", ".key": "application/x-pem-file", ".al": "text/x-alex", ".py": "text/x-python", ".c": "text/x-c", ".h": "text/x-c", ".cpp": "text/x-c++", ".hpp": "text/x-c++", ".java": "text/x-java", ".rs": "text/x-rust", ".go": "text/x-go", ".sh": "application/x-sh", ".sql": "application/sql", ".proto": "text/x-protobuf", ".webmanifest": "application/manifest+json", ".txz": "application/x-xz"}

const DEFAULT_TYPE := "application/octet-stream"

func _ext_of(name):
    n := _s.lower(str(name))
    q := _s.find(n, "?")
    if q >= 0:
        n = _s.substring(n, 0, q)
    k := len(n) - 1
    while k >= 0 and n[k] != '.' and n[k] != '/' and n[k] != '\\':
        k -= 1
    if k < 0 or n[k] != '.':
        return ""
    return _s.substring(n, k, len(n))

# Type MIME d'après l'extension d'un nom de fichier ou d'une URL (default si inconnue).
func guess_type(filename, default=DEFAULT_TYPE):
    e := _ext_of(filename)
    if contains_key(_TYPES, e):
        return _TYPES[e]
    return default

# Extension habituelle d'un type (« .pdf »), ou null.
func guess_extension(content_type):
    t := _hh.parse_value(content_type)[0]
    preferred := {"image/jpeg": ".jpg", "text/plain": ".txt", "text/html": ".html", "application/octet-stream": ".bin", "video/mp4": ".mp4", "audio/mpeg": ".mp3", "application/gzip": ".gz", "text/javascript": ".js", "application/yaml": ".yaml", "image/tiff": ".tiff", "audio/midi": ".mid", "video/mpeg": ".mpeg"}
    if contains_key(preferred, t):
        return preferred[t]
    for e in keys(_TYPES):
        if _TYPES[e] == t:
            return e
    return null

# Ajoute ou remplace une association extension -> type.
func add_type(content_type, extension):
    e := _s.lower(extension)
    if not _s.starts_with(e, "."):
        e = "." + e
    _TYPES[e] = content_type

func is_text_type(content_type):
    t := _hh.parse_value(content_type)[0]
    if _s.starts_with(t, "text/"):
        return true
    return t == "application/json" or t == "application/xml" or t == "application/javascript" or _s.ends_with(t, "+json") or _s.ends_with(t, "+xml") or t == "application/x-www-form-urlencoded" or t == "image/svg+xml" or t == "application/yaml"

# ---------------------------------------------------------------- en-têtes encodés (RFC 2047)

func _needs_encoding(text):
    for c in text:
        o := _s.ord(c)
        if o >= 128 or (o < 32 and c != '\t'):
            return true
    return _s.contains(text, "=?")

# Encode un texte d'en-tête en mots encodés si nécessaire (texte ASCII rendu tel quel). encoding : "B" (base64),
# "Q" (quoted-printable) ou null (le plus court). Les mots ne dépassent pas 75 caractères et ne coupent jamais un
# caractère UTF-8.
func encode_header(text, charset="utf-8", encoding=null):
    if text == null:
        return ""
    t := str(text)
    if not _needs_encoding(t):
        return t
    raw := _enc.encode_charset(t, charset)
    enc := encoding
    if enc == null:
        qlen := len(_enc.qp_encode(raw, true))
        blen := ((_n.blen(raw) + 2) // 3) * 4
        enc = "B"
        if qlen <= blen:
            enc = "Q"
    enc = _s.upper(enc)
    prefix := "=?" + _s.lower(charset) + "?" + _s.lower(enc) + "?"
    budget := 75 - len(prefix) - 2
    words := []
    # découpe par caractères pour ne pas couper une séquence UTF-8
    chunk := ""
    for c in t:
        cand := chunk + str(c)
        cr := _enc.encode_charset(cand, charset)
        size := 0
        if enc == "B":
            size = ((_n.blen(cr) + 2) // 3) * 4
        else:
            size = len(_enc.qp_encode(cr, true))
        if size > budget and chunk != "":
            append(words, _encode_word(chunk, charset, enc, prefix))
            chunk = str(c)
        else:
            chunk = cand
    if chunk != "":
        append(words, _encode_word(chunk, charset, enc, prefix))
    return _s.join(" ", words)

func _encode_word(text, charset, enc, prefix):
    raw := _enc.encode_charset(text, charset)
    if enc == "B":
        return prefix + _enc.base64_encode(raw) + "?="
    return prefix + _enc.qp_encode(raw, true) + "?="

# Décode les mots encodés d'un en-tête (l'espace entre deux mots encodés adjacents disparaît, RFC 2047 §6.2).
func decode_header(text):
    if text == null:
        return null
    t := str(text)
    if not _s.contains(t, "=?"):
        return t
    out := []
    i := 0
    n := len(t)
    pending_space := ""
    last_was_word := false
    while i < n:
        start := _find_from(t, "=?", i)
        if start < 0:
            append(out, pending_space + _s.substring(t, i, n))
            pending_space = ""
            break
        between := _s.substring(t, i, start)
        word := _parse_word(t, start)
        if word == null:
            append(out, pending_space + between + "=?")
            pending_space = ""
            last_was_word = false
            i = start + 2
            continue
        if last_was_word and _s.trim(between) == "":
            pass
        else:
            append(out, pending_space + between)
        pending_space = ""
        append(out, word[0])
        last_was_word = true
        i = word[1]
    return _s.join("", out)

func _find_from(s, sub, start):
    k := _s.find(_s.substring(s, start, len(s)), sub)
    if k < 0:
        return -1
    return start + k

# (texte décodé, position après « ?= ») du mot encodé commençant à `start`, ou null s'il est mal formé.
func _parse_word(t, start):
    q1 := _find_from(t, "?", start + 2)
    if q1 < 0:
        return null
    q2 := _find_from(t, "?", q1 + 1)
    if q2 < 0 or q2 != q1 + 2:
        return null
    end := _find_from(t, "?=", q2 + 1)
    if end < 0:
        return null
    charset := _s.substring(t, start + 2, q1)
    star := _s.find(charset, "*")      # langue RFC 2231 : « utf-8*fr »
    if star >= 0:
        charset = _s.substring(charset, 0, star)
    enc := _s.upper(_s.substring(t, q1 + 1, q2))
    payload := _s.substring(t, q2 + 1, end)
    if _s.contains(payload, " "):
        return null
    raw := null
    try:
        if enc == "B":
            raw = _enc.base64_decode(payload)
        elif enc == "Q":
            raw = _enc.qp_decode(payload, true)
        else:
            return null
        return (_enc.decode_charset(raw, charset, "replace"), end + 2)
    catch e:
        return null

# Replie un en-tête long sur plusieurs lignes (« \r\n » + espace) aux espaces, lignes de max_line au plus quand
# c'est possible. Rend « Nom: valeur » replié (sans CRLF final).
func fold_header(name, value, max_line=78):
    words := _s.split(str(value), " ")
    lines := []
    cur := name + ":"
    for w in words:
        if w == "":
            continue
        if len(cur) + 1 + len(w) > max_line and _s.trim(cur) != name + ":":
            append(lines, cur)
            cur = " " + w
        else:
            cur += " " + w
    append(lines, cur)
    return _s.join("\r\n", lines)

# ---------------------------------------------------------------- encodages de transfert

# Encodage de transfert adapté : "7bit" (ASCII, lignes courtes), "quoted-printable" (texte surtout ASCII) ou
# "base64" (binaire ou texte très accentué).
func choose_transfer_encoding(data, is_text=true):
    raw := data
    if type(data) == "list":
        raw = _n.from_bytes(data)
    b := _n.to_bytes(raw)
    high := 0
    ctrl := false
    line := 0
    long_line := false
    for x in b:
        if x == 10:
            line = 0
            continue
        line += 1
        if line > 998:
            long_line = true
        if x >= 128:
            high += 1
        elif x == 0 or (x < 32 and x != 9 and x != 13):
            ctrl = true
    if not is_text or ctrl:
        return "base64"
    if high == 0 and not long_line:
        return "7bit"
    if high * 6 < len(b):
        return "quoted-printable"
    return "base64"

func encode_body(data, cte):
    raw := data
    if type(data) == "list":
        raw = _n.from_bytes(data)
    c := _s.lower(cte)
    if c == "base64":
        return _enc.base64_encode(raw, false, true, 76)
    if c == "quoted-printable":
        return _enc.qp_encode(raw)
    if c == "7bit" or c == "8bit" or c == "binary":
        return _to_crlf(raw)
    _fail("encodage de transfert inconnu « " + cte + " »")

func decode_body(data, cte):
    if cte == null:
        return data
    c := _s.lower(_s.trim(cte))
    if c == "base64":
        return _enc.base64_decode(data)
    if c == "quoted-printable":
        return _enc.qp_decode(data)
    return data

func _to_crlf(text):
    t := _s.replace(text, "\r\n", "\n")
    return _s.replace(t, "\n", "\r\n")

# ---------------------------------------------------------------- arbre de parties

func new_boundary():
    return "=_alex_" + _enc.hex_encode(_n.random_bytes(12))

class MimePart:
    func init(headers=null, body="", parts=null):
        self.headers = headers        # network.http_headers.Headers
        if headers == null:
            self.headers = _hh.Headers()
        self.body = body              # contenu DÉCODÉ (octets bruts) d'une feuille
        self.parts = parts            # list de MimePart pour une partie multipart, sinon null
        self.preamble = ""
        self.epilogue = ""

    func is_multipart():
        return self.parts != null

    # Type sans paramètres, en minuscules (« text/plain » par défaut, RFC 2045 §5.2).
    func content_type():
        v := self.headers.get("content-type")
        if v == null:
            return "text/plain"
        return _hh.parse_value(v)[0]

    func params():
        v := self.headers.get("content-type")
        if v == null:
            return {}
        return _hh.parse_value(v)[1]

    func param(name, default=null):
        p := self.params()
        if contains_key(p, _s.lower(name)):
            return p[_s.lower(name)]
        return default

    func charset():
        return self.param("charset", "us-ascii")

    func boundary():
        return self.param("boundary")

    func transfer_encoding():
        v := self.headers.get("content-transfer-encoding")
        if v == null:
            return "7bit"
        return _s.lower(_s.trim(v))

    # (disposition, paramètres) — disposition en minuscules (« attachment », « inline »), ou null.
    func disposition():
        v := self.headers.get("content-disposition")
        if v == null:
            return null
        return _hh.parse_value(v)[0]

    # Nom de fichier (Content-Disposition filename / filename*, sinon Content-Type name), décodé.
    func filename():
        v := self.headers.get("content-disposition")
        if v != null:
            p := _hh.parse_value(v)[1]
            if contains_key(p, "filename"):
                return decode_header(p["filename"])
        n := self.param("name")
        if n != null:
            return decode_header(n)
        return null

    func content_id():
        v := self.headers.get("content-id")
        if v == null:
            return null
        t := _s.trim(v)
        if _s.starts_with(t, "<") and _s.ends_with(t, ">"):
            t = _s.substring(t, 1, len(t) - 1)
        return t

    func is_attachment():
        d := self.disposition()
        if d == "attachment":
            return true
        return d == "inline" and self.filename() != null and not _s.starts_with(self.content_type(), "text/")

    # Contenu décodé en texte (selon charset), pour une feuille.
    func text():
        return _enc.decode_charset(self.body, self.charset(), "replace")

    func data():
        return self.body

    func header(name, default=null):
        v := self.headers.get(name)
        if v == null:
            return default
        return decode_header(v)

    # Cette partie et toutes ses descendantes, en profondeur (ordre du document).
    func walk():
        out := [self]
        if self.parts != null:
            for p in self.parts:
                for x in p.walk():
                    append(out, x)
        return out

    # Parties feuilles.
    func leaves():
        out := []
        for p in self.walk():
            if not p.is_multipart():
                append(out, p)
        return out

    # Première feuille du type donné (« text/plain »), hors pièces jointes, ou null.
    func find_type(content_type):
        for p in self.leaves():
            if p.content_type() == content_type and not p.is_attachment():
                return p
        return null

    # Sérialisation complète : en-têtes + ligne vide + corps (CRLF).
    func to_bytes():
        out := []
        self._write(out)
        return _s.join("", out)

    func _write(out):
        if self.parts != null:
            b := self.boundary()
            if b == null:
                b = new_boundary()
                self.headers.set("Content-Type", self.headers.get("content-type", "multipart/mixed") + "; boundary=\"" + b + "\"")
            for e in self.headers.entries:
                append(out, _header_line(e[0], e[1]))
            append(out, "\r\n")
            if self.preamble != "":
                append(out, _to_crlf(self.preamble) + "\r\n")
            for p in self.parts:
                append(out, "--" + b + "\r\n")
                p._write(out)
                append(out, "\r\n")
            append(out, "--" + b + "--\r\n")
            if self.epilogue != "":
                append(out, _to_crlf(self.epilogue))
            return
        cte := self.transfer_encoding()
        for e in self.headers.entries:
            append(out, _header_line(e[0], e[1]))
        append(out, "\r\n")
        append(out, encode_body(self.body, cte))

    func str():
        return self.to_bytes()

# Feuille : données (str d'octets ou liste), type (avec paramètres), encodage de transfert (null : choisi),
# nom de fichier (pièce jointe) et disposition.
func leaf(data, content_type="text/plain; charset=utf-8", transfer_encoding=null, filename=null, disposition=null, content_id=null):
    raw := data
    if type(data) == "list":
        raw = _n.from_bytes(data)
    if raw == null:
        raw = ""
    p := MimePart()
    p.body = raw
    p.headers.set("Content-Type", content_type)
    cte := transfer_encoding
    if cte == null:
        cte = choose_transfer_encoding(raw, is_text_type(content_type))
    p.headers.set("Content-Transfer-Encoding", cte)
    if filename != null or disposition != null:
        d := disposition
        if d == null:
            d = "attachment"
        p.headers.set("Content-Disposition", mail_disposition(d, filename))
        if filename != null and _needs_encoding(filename):
            # ancien usage, encore lu par certains clients : nom encodé (RFC 2047) dans le type de contenu
            p.headers.set("Content-Type", content_type + "; name=\"" + encode_header(filename) + "\"")
    if content_id != null:
        cid := content_id
        if not _s.starts_with(cid, "<"):
            cid = "<" + cid + ">"
        p.headers.set("Content-ID", cid)
    return p

# Partie multipart/<subtype> (mixed, alternative, related, form-data...).
func multipart(subtype, parts, boundary=null):
    p := MimePart(null, "", [])
    for x in parts:
        append(p.parts, x)
    b := boundary
    if b == null:
        b = new_boundary()
    p.headers.set("Content-Type", "multipart/" + subtype + "; boundary=\"" + b + "\"")
    return p

# Content-Disposition d'une partie de courriel : nom ASCII entre guillemets, ou forme étendue RFC 2231 seule
# (« filename*=utf-8''donn%C3%A9es.bin ») pour un nom non ASCII, comme les messageries actuelles.
func mail_disposition(disposition, filename):
    if filename == null:
        return disposition
    if _needs_encoding(filename):
        return disposition + "; filename*=" + _hh.encode_ext_value(filename)
    return disposition + "; filename=" + _hh.quote(filename)

func _header_line(name, value):
    v := value
    if _needs_encoding(v) and not _s.contains(v, "=?"):
        lname := _s.lower(name)
        # les en-têtes structurés (type, disposition) gardent leurs paramètres déjà encodés
        if lname != "content-type" and lname != "content-disposition":
            v = encode_header(v)
    line := name + ": " + v
    if len(line) > 78:
        line = fold_header(name, v)
    return line + "\r\n"

# ---------------------------------------------------------------- analyse

# Sépare en-têtes et corps (ligne vide « \r\n\r\n » ou « \n\n ») : (texte des en-têtes, corps).
func split_message(raw):
    i := _n.bfind(raw, "\r\n\r\n", 0)
    j := _n.bfind(raw, "\n\n", 0)
    if i >= 0 and (j < 0 or i <= j):
        return (_n.bslice(raw, 0, i), _n.bslice(raw, i + 4, _n.blen(raw)))
    if j >= 0:
        return (_n.bslice(raw, 0, j), _n.bslice(raw, j + 2, _n.blen(raw)))
    return (raw, "")

# Analyse tolérante d'un bloc d'en-têtes MIME (lignes repliées, lignes invalides ignorées).
func parse_headers(text):
    h := _hh.Headers()
    last := null
    for line in _s.split(text, "\n"):
        l := line
        if _s.ends_with(l, "\r"):
            l = _s.substring(l, 0, len(l) - 1)
        if l == "":
            continue
        if (l[0] == ' ' or l[0] == '\t') and last != null:
            last[1] = last[1] + " " + _s.trim(l)
            continue
        c := _s.find(l, ":")
        if c <= 0:
            continue
        name := _s.trim(_s.substring(l, 0, c))
        if not _hh.is_valid_name(name):
            continue
        append(h.entries, [name, _s.trim(_s.substring(l, c + 1, len(l)))])
        last = h.entries[len(h.entries) - 1]
    return h

# Découpe le corps d'une partie multipart : (préambule, [corps bruts des parties], épilogue).
func split_multipart(body, boundary):
    if boundary == null or boundary == "":
        _fail("frontière multipart absente")
    delim := "--" + boundary
    parts := []
    pos := 0
    n := _n.blen(body)
    # première frontière (en début de corps ou après un saut de ligne)
    first := -1
    if _n.bfind(body, delim, 0) == 0:
        first = 0
    else:
        k := _n.bfind(body, "\n" + delim, 0)
        if k >= 0:
            first = k + 1
    if first < 0:
        _fail("frontière « " + boundary + " » introuvable")
    preamble := _n.bslice(body, 0, first)
    pos = first + _n.blen(delim)
    epilogue := ""
    while true:
        # après la frontière : « -- » (fin) ou fin de ligne
        if _n.bslice(body, pos, pos + 2) == "--":
            rest := _n.bslice(body, pos + 2, n)
            le := _n.bfind(rest, "\n", 0)
            if le >= 0:
                epilogue = _n.bslice(rest, le + 1, _n.blen(rest))
            break
        le := _n.bfind(body, "\n", pos)
        if le < 0:
            break
        start := le + 1
        nxt := _n.bfind(body, "\n" + delim, start - 1)
        if nxt < 0:
            # frontière finale absente : le reste forme la dernière partie
            append(parts, _n.bslice(body, start, n))
            break
        end := nxt
        if end > start and _n.bslice(body, end - 1, end) == "\r":
            end -= 1
        if end < start:
            end = start
        append(parts, _n.bslice(body, start, end))
        pos = nxt + 1 + _n.blen(delim)
    return (preamble, parts, epilogue)

# Analyse un message ou une partie MIME (octets bruts) en arbre de MimePart ; les corps des feuilles sont
# décodés (base64, quoted-printable). max_depth borne l'imbrication.
func parse(raw, max_depth=32):
    if type(raw) != "str":
        raise("TypeError", "mime.parse : str (octets) attendue")
    hb := split_message(raw)
    return _parse_part(parse_headers(hb[0]), hb[1], max_depth)

func _parse_part(headers, body, depth):
    p := MimePart(headers, "", null)
    ct := p.content_type()
    if _s.starts_with(ct, "multipart/") and p.boundary() != null:
        if depth <= 0:
            _fail("imbrication multipart trop profonde")
        sp := split_multipart(body, p.boundary())
        p.parts = []
        p.preamble = sp[0]
        p.epilogue = sp[2]
        for raw in sp[1]:
            hb := null
            if _s.starts_with(raw, "\r\n") or _s.starts_with(raw, "\n"):
                hb = ("", _n.bslice(raw, _n.bfind(raw, "\n", 0) + 1, _n.blen(raw)))   # partie sans en-têtes
            else:
                hb = split_message(raw)
            append(p.parts, _parse_part(parse_headers(hb[0]), hb[1], depth - 1))
        return p
    p.body = decode_body(body, p.transfer_encoding())
    return p
