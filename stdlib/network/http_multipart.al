# ALEX STANDARD LIBRARY — network.http_multipart
#
# Corps multipart en HTTP : formulaires multipart/form-data (RFC 7578) avec champs et fichiers, dans les deux
# sens (client : encode ; serveur : parse), et réponses multipart/byteranges (plusieurs plages, RFC 9110 §14.6).
#
#   encode(champs, fichiers)          -> (corps, Content-Type)       champs : dict ou liste de paires
#   File(nom_de_fichier, données, type)                              fichier à envoyer
#   parse(corps, content_type)        -> FormData (fields, files)    côté serveur
#   byteranges(données, plages, type) -> (corps, Content-Type)
#
# Les données sont des octets bruts (str) ; les noms de champs et de fichiers non ASCII sont acceptés (UTF-8,
# comme les navigateurs). Les fichiers reçus restent en mémoire : `max_size` borne l'ensemble (défaut 100 Mio)
# et `max_parts` le nombre de parties.
#
# Erreurs : HttpError (corps mal formé, limite dépassée), TypeError.
#
# Exemple (client)
#   use network.http_multipart as mp
#   corps, ct := mp.encode({"titre": "Vacances"}, {"photo": mp.File("plage.jpg", octets)})
#   r := http.post(url, corps, {"Content-Type": ct})
#
# Exemple (serveur)
#   form := mp.parse(req.body, req.header("content-type"))
#   print(form.field("titre"), form.file("photo").filename, form.file("photo").size())

from core use len, type
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use io as _io
use network.mime as _mime
use network.http_headers as _hh
use network.encoding as _enc

const DEFAULT_MAX_SIZE := 104857600
const DEFAULT_MAX_PARTS := 1000

func _fail(message):
    raise("HttpError", "multipart : " + message)

func _raw(data):
    t := type(data)
    if t == "str":
        return data
    if t == "list" or t == "tuple":
        return _n.from_bytes(data)
    if data == null:
        return ""
    return str(data)

# Fichier à envoyer dans un formulaire.
class File:
    # content_type null : deviné d'après le nom de fichier.
    func init(filename, data, content_type=null, headers=null):
        self.filename = filename
        self.data = _raw(data)
        self.content_type = content_type
        if content_type == null:
            self.content_type = _mime.guess_type(filename)
        self.headers = headers    # dict d'en-têtes supplémentaires, ou null

# Fichier lu sur le disque (nom d'envoi : celui du fichier).
func file_from_path(path, content_type=null, filename=null):
    name := filename
    if name == null:
        k := len(path) - 1
        while k >= 0 and path[k] != '/' and path[k] != '\\':
            k -= 1
        name = _s.substring(path, k + 1, len(path))
    return File(name, _n.from_bytes(_io.read_bytes(path)), content_type)

func _escape_name(s):
    # RFC 7578 §4.2 / HTML : guillemets et fins de ligne encodés en %XX
    return _s.replace(_s.replace(_s.replace(str(s), "\"", "%22"), "\r", "%0D"), "\n", "%0A")

func _pairs(x):
    out := []
    if x == null:
        return out
    if type(x) == "dict":
        for k in keys(x):
            v := x[k]
            if type(v) == "list":
                for item in v:
                    append(out, [k, item])
            else:
                append(out, [k, v])
        return out
    for p in x:
        append(out, [p[0], p[1]])
    return out

func _boundary_for(chunks):
    while true:
        b := "----AlexFormBoundary" + _s.replace(_mime.new_boundary(), "=_alex_", "")
        clash := false
        for c in chunks:
            if _n.bfind(c, b, 0) >= 0:
                clash = true
        if not clash:
            return b

# Encode un formulaire : (corps, valeur de Content-Type). fields : dict / paires de valeurs (str, nombres...) ;
# files : dict / paires nom -> File (ou (nom_de_fichier, données[, type])).
func encode(fields=null, files=null, boundary=null):
    parts := []
    contents := []
    for p in _pairs(fields):
        v := p[1]
        if isinstance(v, File):
            append(parts, [p[0], v])
            append(contents, v.data)
        else:
            sv := v
            if v == true:
                sv = "true"
            elif v == false:
                sv = "false"
            elif v == null:
                sv = ""
            else:
                sv = _raw(v)
            append(parts, [p[0], sv])
            append(contents, sv)
    for p in _pairs(files):
        f := p[1]
        if not isinstance(f, File):
            if type(f) == "tuple" or type(f) == "list":
                if len(f) >= 3:
                    f = File(f[0], f[1], f[2])
                else:
                    f = File(f[0], f[1])
            else:
                raise("TypeError", "multipart.encode : fichier File ou (nom, données[, type]) attendu pour « " + str(p[0]) + " »")
        append(parts, [p[0], f])
        append(contents, f.data)
    b := boundary
    if b == null:
        b = _boundary_for(contents)
    out := []
    for p in parts:
        append(out, "--" + b + "\r\n")
        v := p[1]
        if isinstance(v, File):
            append(out, "Content-Disposition: form-data; name=\"" + _escape_name(p[0]) + "\"; filename=\"" + _escape_name(v.filename) + "\"\r\n")
            append(out, "Content-Type: " + v.content_type + "\r\n")
            if v.headers != null:
                for k in keys(v.headers):
                    append(out, _hh.check_name(k) + ": " + _hh.check_value(k, v.headers[k]) + "\r\n")
            append(out, "\r\n")
            append(out, v.data)
        else:
            append(out, "Content-Disposition: form-data; name=\"" + _escape_name(p[0]) + "\"\r\n\r\n")
            append(out, v)
        append(out, "\r\n")
    append(out, "--" + b + "--\r\n")
    return (_s.join("", out), "multipart/form-data; boundary=" + b)

# ---------------------------------------------------------------- analyse (serveur)

class UploadedFile:
    func init(name, filename, content_type, data, headers):
        self.name = name                  # nom du champ
        self.filename = filename          # nom de fichier envoyé par le client (NON fiable : voir safe_filename)
        self.content_type = content_type
        self.data = data                  # octets (str brute)
        self.headers = headers

    func size():
        return _n.blen(self.data)

    func bytes():
        return _n.to_bytes(self.data)

    func text():
        return self.data

    # Nom de fichier sans chemin ni caractère dangereux (« ../../x » -> « x »), utilisable sur le disque.
    func safe_filename(default="fichier"):
        return safe_filename(self.filename, default)

    # Écrit le fichier sur le disque (path : chemin complet choisi par le serveur).
    func save(path):
        _io.write_bytes(path, _n.to_bytes(self.data))

class FormData:
    func init():
        self.fields = []      # [nom, valeur]
        self.files = []       # UploadedFile

    # Dernière valeur du champ, ou default.
    func field(name, default=null):
        v := default
        for f in self.fields:
            if f[0] == name:
                v = f[1]
        return v

    func field_list(name):
        out := []
        for f in self.fields:
            if f[0] == name:
                append(out, f[1])
        return out

    # Premier fichier du champ, ou null.
    func file(name):
        for f in self.files:
            if f.name == name:
                return f
        return null

    func file_list(name):
        out := []
        for f in self.files:
            if f.name == name:
                append(out, f)
        return out

    func to_dict():
        d := {}
        for f in self.fields:
            d[f[0]] = f[1]
        return d

# Nom de fichier sûr : dernier composant, sans contrôles, ni « .. », ni séparateurs ; default s'il ne reste rien.
func safe_filename(name, default="fichier"):
    if name == null:
        return default
    n := _s.replace(str(name), "\\", "/")
    k := len(n) - 1
    while k >= 0 and n[k] != '/':
        k -= 1
    n = _s.substring(n, k + 1, len(n))
    out := []
    for c in n:
        o := _s.ord(c)
        if o < 32 or o == 127 or c == ':' or c == '*' or c == '?' or c == '"' or c == '<' or c == '>' or c == '|':
            append(out, "_")
        else:
            append(out, str(c))
    r := _s.trim(_s.join("", out))
    while _s.starts_with(r, "."):
        r = _s.substring(r, 1, len(r))
    if r == "":
        return default
    if len(r) > 200:
        r = _s.substring(r, len(r) - 200, len(r))
    return r

# Analyse un corps multipart/form-data. content_type : valeur complète de l'en-tête (avec boundary).
func parse(body, content_type, max_size=DEFAULT_MAX_SIZE, max_parts=DEFAULT_MAX_PARTS):
    if content_type == null:
        _fail("Content-Type absent")
    pv := _hh.parse_value(content_type)
    if pv[0] != "multipart/form-data" and not _s.starts_with(pv[0], "multipart/"):
        _fail("type multipart attendu (obtenu « " + pv[0] + " »)")
    if not contains_key(pv[1], "boundary") or pv[1]["boundary"] == "":
        _fail("paramètre boundary absent")
    if _n.blen(body) > max_size:
        _fail("corps trop grand (" + str(_n.blen(body)) + " octets, limite " + str(max_size) + ")")
    sp := null
    try:
        sp = _mime.split_multipart(body, pv[1]["boundary"])
    catch e:
        _fail(e.message)
    if len(sp[1]) > max_parts:
        _fail("trop de parties (" + str(len(sp[1])) + ", limite " + str(max_parts) + ")")
    form := FormData()
    for raw in sp[1]:
        hb := _mime.split_message(raw)
        headers := _mime.parse_headers(hb[0])
        cd := headers.get("content-disposition")
        if cd == null:
            continue
        d := _hh.parse_value(cd)
        params := d[1]
        if not contains_key(params, "name"):
            continue
        name := params["name"]
        data := hb[1]
        cte := headers.get("content-transfer-encoding")
        if cte != null:
            data = _mime.decode_body(data, cte)
        if contains_key(params, "filename"):
            ct := headers.get("content-type", "application/octet-stream")
            append(form.files, UploadedFile(name, params["filename"], ct, data, headers))
        else:
            charset := null
            ctv := headers.get("content-type")
            if ctv != null:
                pp := _hh.parse_value(ctv)[1]
                if contains_key(pp, "charset"):
                    charset = pp["charset"]
            if charset != null:
                data = _enc.decode_charset(data, charset, "replace")
            append(form.fields, [name, data])
    return form

# ---------------------------------------------------------------- multipart/byteranges

# Corps d'une réponse 206 à plusieurs plages : (corps, Content-Type). ranges : liste de [début, fin] inclusives.
func byteranges(data, ranges, content_type, total=null, boundary=null):
    raw := _raw(data)
    size := total
    if size == null:
        size = _n.blen(raw)
    chunks := []
    for r in ranges:
        append(chunks, _n.bslice(raw, r[0], r[1] + 1))
    b := boundary
    if b == null:
        b = _boundary_for(chunks)
    out := []
    i := 0
    for r in ranges:
        append(out, "--" + b + "\r\nContent-Type: " + content_type + "\r\nContent-Range: " + _hh.content_range(r[0], r[1], size) + "\r\n\r\n")
        append(out, chunks[i])
        append(out, "\r\n")
        i += 1
    append(out, "--" + b + "--\r\n")
    return (_s.join("", out), "multipart/byteranges; boundary=" + b)
