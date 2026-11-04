# ALEX STANDARD LIBRARY — web.http.message_body
#
# Corps des messages HTTP/1.1 (RFC 9112 §6, §7) : cadrage (longueur connue, « chunked », jusqu'à la fermeture),
# codage et décodage « chunked » (aussi incrémental, pour une lecture réseau morceau par morceau), et conversions
# de contenu courantes (texte, JSON, formulaire).
#
# Les corps sont des str d'OCTETS (UTF-8 pour du texte) : leurs longueurs se comptent avec byte_len.
#
#   use web.http.message_body as mb
#   mb.encode_chunked("Bonjour", 4)        # "4\r\nBonj\r\n3\r\nour\r\n0\r\n\r\n"
#   r := mb.decode_chunked("4\r\nBonj\r\n3\r\nour\r\n0\r\n\r\n")
#   r.body, r.consumed                    # Bonjour 26
#   d := mb.ChunkedDecoder()
#   d.feed("4\r\nBo")                     # "Bo"   (données disponibles)
#   d.feed("nj\r\n0\r\n\r\n")             # "nj" ; d.done == true
#   mb.response_framing("GET", 200, h)    # "length", "chunked", "close" ou "none"
#   mb.json_body({"ok": true})            # ("{\"ok\":true}", "application/json")
#
# Erreurs : HttpParseError (400 : taille de bloc invalide, CRLF manquant ; 501 : Transfer-Encoding inconnu),
# HttpLimitError (413 : corps trop grand).

from core use len, type, to_int
from collections use append
use string as _s
use json as _json
use web.http.http_errors as _err
use web.http.headers as _headers
use web.http.header_value as _hv
use web.http.content_length as _cl
use web.http.status_code as _status
use web.url.form_url_encoding as _form

const NONE := "none"
const LENGTH := "length"
const CHUNKED := "chunked"
const CLOSE := "close"

const MAX_CHUNK_LINE := 4096

# ---------------------------------------------------------------- contenu

# Corps str depuis : str (tel quel), liste d'octets (int 0..255), null ("").
func to_bytes(value):
    if value == null:
        return ""
    t := type(value)
    if t == "str":
        return value
    if t == "list":
        return _s.byte_pack(value)
    raise("TypeError", "message_body.to_bytes : str, liste d'octets ou null attendu (obtenu " + t + ")")

func length(body):
    return _cl.of(body)

# (corps, type) pour du texte.
func text_body(text, sub="plain"):
    return (str(text), "text/" + sub + "; charset=utf-8")

# (corps, type) pour une valeur JSON (ordre des clés conservé).
func json_body(value):
    return (_json.stringify(value, null, false), "application/json")

# (corps, type) pour un formulaire application/x-www-form-urlencoded.
func form_body(data):
    return (_form.encode(data), "application/x-www-form-urlencoded")

func parse_json(body):
    if body == null or body == "":
        return null
    return _json.parse(body)

func parse_form(body):
    return _form.decode(body)

# ---------------------------------------------------------------- cadrage

# Codages de transfert d'une valeur Transfer-Encoding, en minuscules : « gzip, chunked » -> ["gzip", "chunked"].
func transfer_codings(value):
    out := []
    for item in _hv.split_list(value):
        append(out, _s.lower(_hv.parse_parameters(item)[0]))
    return out

# Cadrage du corps d'une REQUÊTE (RFC 9112 §6.3) : « chunked », « length » ou « none ». Transfer-Encoding dont le
# dernier codage n'est pas chunked : 400 ; codage inconnu : 501 ; avec Content-Length : 400.
func request_framing(headers):
    fn := "message_body.request_framing"
    if headers.has("transfer-encoding"):
        if headers.has("content-length"):
            _err.parse_error(fn, "Content-Length et Transfer-Encoding ensemble")
        codings := []
        for v in headers.get_all("transfer-encoding"):
            for c in transfer_codings(v):
                append(codings, c)
        if len(codings) == 0 or codings[len(codings) - 1] != "chunked":
            _err.parse_error(fn, "le dernier Transfer-Encoding d'une requête doit être chunked")
        for c in codings:
            if c != "chunked":
                _err.parse_error(fn, "Transfer-Encoding non pris en charge « " + c + " »", 501)
        return CHUNKED
    n := _cl.from_headers(headers)
    if n == null or n == 0:
        return NONE
    return LENGTH

# Cadrage du corps d'une RÉPONSE à method : « none » (HEAD, 1xx, 204, 304, CONNECT 2xx), « chunked »,
# « length », ou « close » (lu jusqu'à la fermeture de la connexion).
func response_framing(method, status, headers):
    if method == "HEAD" or not _status.allows_body(status):
        return NONE
    if method == "CONNECT" and _status.is_success(status):
        return NONE
    if headers.has("transfer-encoding"):
        codings := []
        for v in headers.get_all("transfer-encoding"):
            for c in transfer_codings(v):
                append(codings, c)
        if len(codings) > 0 and codings[len(codings) - 1] == "chunked":
            return CHUNKED
        return CLOSE
    n := _cl.from_headers(headers, false)
    if n != null:
        return LENGTH
    return CLOSE

# ---------------------------------------------------------------- chunked : écriture

func _hex(n):
    if n == 0:
        return "0"
    digits := "0123456789abcdef"
    out := ""
    while n > 0:
        out = str(digits[n & 15]) + out
        n = n >> 4
    return out

# Un bloc : « taille-hex CRLF données CRLF » (un bloc vide n'est PAS émis : ce serait la fin du corps).
func chunk(data):
    n := _s.byte_len(data)
    if n == 0:
        return ""
    return _hex(n) + "\r\n" + data + "\r\n"

# Dernier bloc et en-têtes de fin (trailers : Headers, dict ou null).
func last_chunk(trailers=null):
    out := "0\r\n"
    if trailers != null:
        out = out + _headers.from_data(trailers).to_wire()
    return out + "\r\n"

# Corps complet encodé en blocs de chunk_size octets au plus.
func encode_chunked(body, chunk_size=16384, trailers=null):
    out := []
    n := _s.byte_len(body)
    i := 0
    while i < n:
        end := i + chunk_size
        if end > n:
            end = n
        append(out, chunk(_s.byte_slice(body, i, end)))
        i = end
    append(out, last_chunk(trailers))
    return _s.byte_join(out)

# ---------------------------------------------------------------- chunked : lecture

class DecodeResult:
    func init(body, trailers, consumed):
        self.body = body            # corps décodé
        self.trailers = trailers    # Headers des en-têtes de fin
        self.consumed = consumed    # octets lus dans l'entrée

# Analyse d'une ligne de taille « 1a;ext=x » -> entier ; HttpParseError si invalide.
func parse_chunk_size(line):
    fn := "message_body.parse_chunk_size"
    t := line
    semi := _s.find(t, ";")
    if semi >= 0:
        t = t[0:semi]
    t = _hv.trim(t)
    if len(t) == 0 or len(t) > 15:
        _err.parse_error(fn, "taille de bloc invalide '" + _hv.sanitize(line) + "'")
    n := 0
    for c in t:
        d := -1
        if c >= '0' and c <= '9':
            d = _s.ord(c) - 48
        elif c >= 'a' and c <= 'f':
            d = _s.ord(c) - 87
        elif c >= 'A' and c <= 'F':
            d = _s.ord(c) - 55
        else:
            _err.parse_error(fn, "taille de bloc invalide '" + _hv.sanitize(line) + "'")
        n = n * 16 + d
    return n

# Décodeur incrémental : feed(octets) rend les données de corps devenues disponibles ; done passe à true après le
# dernier bloc et les en-têtes de fin. max_size : limite du corps décodé (HttpLimitError 413).
class ChunkedDecoder:
    func init(max_size=null):
        self.buffer = ""          # octets reçus ; ceux avant pos sont déjà consommés
        self.pos = 0
        self.state = "size"       # size, data, data_crlf, trailers, done
        self.remaining = 0
        self.total = 0
        self.max_size = max_size
        self.trailers = _headers.Headers()
        self.done = false
        self.consumed = 0         # octets consommés (hors reste non utilisé)

    func _avail():
        return _s.byte_len(self.buffer) - self.pos

    func _take_line():
        i := _s.byte_find(self.buffer, "\r\n", self.pos)
        if i < 0:
            if self._avail() > MAX_CHUNK_LINE:
                _err.parse_error("ChunkedDecoder", "ligne de bloc trop longue")
            return null
        line := _s.byte_slice(self.buffer, self.pos, i)
        self.consumed += i + 2 - self.pos
        self.pos = i + 2
        return line

    # Retire les octets consommés du tampon (une copie par appel de feed, pas par bloc).
    func _compact():
        if self.pos > 0:
            self.buffer = _s.byte_slice(self.buffer, self.pos, _s.byte_len(self.buffer))
            self.pos = 0

    func feed(data):
        self._compact()
        self.buffer = self.buffer + data
        if self.done:
            return ""
        out := []
        while not self.done:
            if self.state == "size":
                line := self._take_line()
                if line == null:
                    break
                self.remaining = parse_chunk_size(line)
                if self.remaining == 0:
                    self.state = "trailers"
                else:
                    self.total += self.remaining
                    if self.max_size != null and self.total > self.max_size:
                        _err.limit_error("ChunkedDecoder", "corps de plus de " + str(self.max_size) + " octets", 413)
                    self.state = "data"
            elif self.state == "data":
                avail := self._avail()
                if avail == 0:
                    break
                k := self.remaining
                if avail < k:
                    k = avail
                append(out, _s.byte_slice(self.buffer, self.pos, self.pos + k))
                self.pos += k
                self.consumed += k
                self.remaining -= k
                if self.remaining == 0:
                    self.state = "data_crlf"
            elif self.state == "data_crlf":
                if self._avail() < 2:
                    break
                if _s.byte_slice(self.buffer, self.pos, self.pos + 2) != "\r\n":
                    _err.parse_error("ChunkedDecoder", "CRLF manquant après les données d'un bloc")
                self.pos += 2
                self.consumed += 2
                self.state = "size"
            elif self.state == "trailers":
                line := self._take_line()
                if line == null:
                    break
                if line == "":
                    self.state = "done"
                    self.done = true
                else:
                    p := _headers.parse_line(line)
                    self.trailers.add(p[0], p[1])
        self._compact()
        return _s.byte_join(out)

    # Octets reçus après la fin du corps (début du message suivant).
    func rest():
        return _s.byte_slice(self.buffer, self.pos, _s.byte_len(self.buffer))

# Décode un corps chunked complet ; HttpParseError s'il est tronqué ou mal formé.
func decode_chunked(data, max_size=null):
    d := ChunkedDecoder(max_size)
    body := d.feed(data)
    if not d.done:
        _err.parse_error("message_body.decode_chunked", "corps chunked incomplet")
    return DecodeResult(body, d.trailers, d.consumed)
