# ALEX STANDARD LIBRARY — web.server.static_files
#
# Fichiers statiques : servir un dossier en toute sécurité, comme un serveur web de production.
#   - chemins sûrs : segments décodés un à un, « .. », « . », « \ », octet nul et fichiers cachés refusés ; liens
#     symboliques qui sortent du dossier refusés (realpath) ;
#   - type MIME par extension (charset=utf-8 pour le texte), Last-Modified, ETag faible (taille + date) ;
#   - requêtes conditionnelles : If-None-Match / If-Modified-Since -> 304 ;
#   - plages : Range « bytes=a-b », « a- », « -n » -> 206 + Content-Range ; plage impossible -> 416 ; If-Range ;
#   - dossiers : redirection 301 vers « dossier/ », fichier d'index (index.html), liste facultative ;
#   - Cache-Control configurable ; repli pour les applications monopages (fallback).
#
#   use web.server.static_files as sf
#   statique := sf.StaticFiles("public", ["index.html"], false, 3600)
#   r := statique.serve(requete, "css/site.css")      # Response, ou null si le fichier n'existe pas
#   spa := sf.StaticFiles("dist", ["index.html"], false, 0, "index.html")   # fallback monopage
#
# Le corps des fichiers n'est pas chargé en mémoire : body_file / body_range (web.server.response_writer).
# Erreurs : ServerConfigError (dossier racine absent).

from core use len, type, to_int
from collections use append, keys
use string as _s
use os as _os
use web.server.server_errors as _err
use web.server.directory_listing as _listing
use web.http.response as _response
use web.http.content_type as _ct
use web.http.date_header as _date
use web.http.header_value as _hv
use web.url.path as _path
use web.url.percent_encoding as _pe

class StaticFiles:
    # root : dossier servi ; index : fichiers d'index ; listing : liste des dossiers sans index ; max_age : secondes
    # de Cache-Control (0 : « no-cache », revalidation) ; fallback : fichier servi pour un chemin introuvable
    # (application monopage) ; show_hidden : servir les fichiers « .xxx » (non, par défaut).
    func init(root, index=null, listing=false, max_age=0, fallback=null, show_hidden=false, immutable_prefixes=null):
        if not _os.isdir(root):
            _err.config_error("StaticFiles", "dossier introuvable « " + str(root) + " »")
        self.root = _os.realpath(root)
        self.index = index if index != null else ["index.html", "index.htm"]
        self.listing = listing
        self.max_age = max_age
        self.fallback = fallback
        self.show_hidden = show_hidden
        self.immutable_prefixes = immutable_prefixes if immutable_prefixes != null else []

    # Chemin disque sûr pour un sous-chemin d'URL encodé (« css/site%20v2.css »), ou null s'il est refusé.
    func resolve(subpath):
        parts := []
        raw := subpath
        if _s.starts_with(raw, "/"):
            raw = raw[1:len(raw)]
        if raw != "":
            for seg in _s.split(raw, "/"):
                if seg == "":
                    continue
                if not _pe.is_well_formed(seg):
                    return null
                v := _pe.decode(seg)
                if v == "." or v == ".." or v == "":
                    return null
                for c in v:
                    if c == '/' or c == '\\' or _s.ord(c) == 0:
                        return null
                if _s.starts_with(v, ".") and not self.show_hidden:
                    return null
                append(parts, v)
        full := self.root
        for p in parts:
            full = _os.join(full, p)
        if not _os.exists(full):
            return full
        real := _os.realpath(full)
        if real != self.root and not _s.starts_with(real, self.root + "/") and not _s.starts_with(real, self.root + "\\"):
            return null
        return real

    # Réponse pour le sous-chemin (encodé) demandé, ou null si rien ne correspond (le routeur répondra 404).
    func serve(req, subpath):
        if req.method != "GET" and req.method != "HEAD":
            r := _response.method_not_allowed(["GET", "HEAD"])
            return r
        full := self.resolve(subpath)
        if full == null:
            return _response.error(404)
        if _os.isdir(full):
            if not _s.ends_with(req.raw_path(), "/"):
                loc := req.raw_path() + "/"
                if req.query_string() != null:
                    loc = loc + "?" + req.query_string()
                return _response.redirect(loc, 301)
            for name in self.index:
                f := _os.join(full, name)
                if _os.isfile(f):
                    return self.file_response(req, f)
            if self.listing:
                return _listing.render(full, req.path(), self.show_hidden)
            return _response.error(403, "liste du dossier non autorisée")
        if _os.isfile(full):
            return self.file_response(req, full, subpath)
        if self.fallback != null:
            f := _os.join(self.root, self.fallback)
            if _os.isfile(f):
                return self.file_response(req, f)
        return null

    # Réponse pour un fichier existant (conditionnelle, plage).
    func file_response(req, file_path, subpath=""):
        size := _os.size(file_path)
        mtime := to_int(_os.mtime(file_path))
        etag := "W/\"" + _hex(size) + "-" + _hex(mtime) + "\""
        last_modified := _date.format(mtime)
        h := {"ETag": etag, "Last-Modified": last_modified, "Accept-Ranges": "bytes", "Cache-Control": self._cache_control(subpath)}
        # requêtes conditionnelles (RFC 9110 §13.2.2 : If-None-Match l'emporte sur If-Modified-Since)
        inm := req.header("if-none-match")
        if inm != null:
            if etag_matches(inm, etag):
                return _not_modified(h)
        else:
            ims := req.header("if-modified-since")
            if ims != null and _date.not_modified_since(mtime, ims):
                return _not_modified(h)
        r := _response.file(file_path, _ct.guess_with_charset(file_path))
        for k in keys(h):
            r.headers.set(k, h[k])
        rng := req.header("range")
        if rng != null and req.method == "GET":
            ir := req.header("if-range")
            if ir == null or ir == etag or (_date.parse(ir) != null and _date.parse(ir) >= mtime):
                spec := parse_range(rng, size)
                if spec == "unsatisfiable":
                    e := _response.error(416)
                    e.headers.set("Content-Range", "bytes */" + str(size))
                    return e
                if spec != null:
                    r.status = 206
                    r.reason = "Partial Content"
                    r.body_range = (spec[0], spec[1] - spec[0] + 1)
                    r.headers.set("Content-Range", "bytes " + str(spec[0]) + "-" + str(spec[1]) + "/" + str(size))
                    return r
        r.body_range = (0, size)
        return r

    func _cache_control(subpath):
        for p in self.immutable_prefixes:
            if _s.starts_with(subpath, p):
                return "public, max-age=31536000, immutable"
        if self.max_age <= 0:
            return "no-cache"
        return "public, max-age=" + str(self.max_age)

func _not_modified(h):
    r := _response.Response(304)
    for k in keys(h):
        if k != "Accept-Ranges":
            r.headers.set(k, h[k])
    return r

func _hex(v):
    if v == 0:
        return "0"
    digits := "0123456789abcdef"
    out := ""
    x := v
    while x > 0:
        out = str(digits[x & 15]) + out
        x = x >> 4
    return out

# Vrai si If-None-Match (liste ou « * ») correspond à l'ETag (comparaison faible).
func etag_matches(header, etag):
    if _s.trim(header) == "*":
        return true
    want := _weak(etag)
    for t in _hv.split_list(header):
        if _weak(t) == want:
            return true
    return false

func _weak(tag):
    t := _s.trim(tag)
    if _s.starts_with(t, "W/"):
        return t[2:len(t)]
    return t

# Plage unique « bytes=a-b » -> (début, fin incluse) bornée à size ; null : en-tête ignoré (syntaxe inconnue,
# plusieurs plages) ; "unsatisfiable" : plage hors du fichier (416).
func parse_range(header, size):
    h := _s.trim(header)
    if not _s.starts_with(_s.lower(h), "bytes="):
        return null
    spec := _s.trim(h[6:len(h)])
    if _s.contains(spec, ","):
        return null
    dash := _s.find(spec, "-")
    if dash < 0:
        return null
    a := _s.trim(spec[0:dash])
    b := _s.trim(spec[dash + 1:len(spec)])
    if a == "":
        n := _num(b)
        if n == null:
            return null
        if n == 0 or size == 0:
            return "unsatisfiable"
        if n > size:
            n = size
        return (size - n, size - 1)
    start := _num(a)
    if start == null:
        return null
    end := size - 1
    if b != "":
        e := _num(b)
        if e == null or e < start:
            return null
        if e < end:
            end = e
    if start >= size:
        return "unsatisfiable"
    return (start, end)

func _num(t):
    if t == "" or len(t) > 18:
        return null
    n := 0
    for c in t:
        if c < '0' or c > '9':
            return null
        n = n * 10 + (_s.ord(c) - 48)
    return n

func static_files(root, index=null, listing=false, max_age=0):
    return StaticFiles(root, index, listing, max_age)
