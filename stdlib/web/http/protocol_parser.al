# ALEX STANDARD LIBRARY — web.http.protocol_parser
#
# Analyse du protocole HTTP/1.x (RFC 9112) indépendante du réseau : on lui donne des octets au fur et à mesure
# (feed), il rend les messages complets. Le même analyseur sert au serveur (RequestParser : requêtes, pipelining
# compris) et au client (ResponseParser : réponses, corps jusqu'à la fermeture compris).
#
# Sécurité : chaque limite est contrôlée AVANT d'accumuler (ligne de départ -> 414, en-têtes -> 431, corps -> 413),
# Content-Length est strict, Content-Length + Transfer-Encoding est refusé, les lignes repliées (obs-fold) et les
# espaces avant « : » sont refusés : un message ambigu n'est jamais interprété (anti « request smuggling »).
#
#   use web.http.protocol_parser as pp
#   p := pp.RequestParser()
#   reqs := p.feed("GET /a HTTP/1.1\r\nHost: h\r\n\r\nGET /b HTTP/1.1\r\nHo")
#   len(reqs), reqs[0].target          # 1 /a     (la deuxième requête attend la suite)
#   reqs = p.feed("st: h\r\n\r\n")      # [Request GET /b]
#
#   r := pp.parse_response("HTTP/1.1 200 OK\r\nContent-Length: 2\r\n\r\nok")
#   r.status, r.body                  # 200 ok
#   rp := pp.ResponseParser("GET")      # corps « jusqu'à la fermeture » : rp.finish() à la fin du flux
#
# Erreurs : HttpParseError (400), HttpVersionError (505), HttpLimitError (413, 414, 431), HttpHeaderError (400),
# HttpParseError 501 (Transfer-Encoding inconnu). Le code est lisible par http_errors.status_for(e).

from core use len, type
from collections use append
use string as _s
use web.http.http_errors as _err
use web.http.headers as _headers
use web.http.header_value as _hv
use web.http.method as _method
use web.http.version as _version
use web.http.status_code as _status
use web.http.content_length as _cl
use web.http.message_body as _mb
use web.http.request as _request
use web.http.response as _response
use web.url.percent_encoding as _pe

# Limites d'analyse ; max_body=false : corps sans limite (à réserver aux clients de confiance).
class Limits:
    func init(max_start_line=8192, max_header_bytes=65536, max_headers=100, max_body=10485760, allow_obs_fold=false):
        self.max_start_line = max_start_line      # ligne de requête / de statut (octets) -> 414 / erreur
        self.max_header_bytes = max_header_bytes  # section d'en-têtes complète (octets) -> 431
        self.max_headers = max_headers            # nombre de lignes d'en-têtes -> 431
        self.max_body = null if max_body == false else max_body   # corps (octets ; null : sans limite) -> 413
        self.allow_obs_fold = allow_obs_fold      # tolérer les lignes repliées (déconseillé)

func default_limits():
    return Limits()

# ---------------------------------------------------------------- lignes de départ

# « GET /chemin HTTP/1.1 » -> (méthode, cible, version texte) ; exactement deux espaces simples.
func parse_request_line(line, max_length=8192):
    fn := "protocol_parser.parse_request_line"
    if max_length != null and _s.byte_len(line) > max_length:
        _err.limit_error(fn, "ligne de requête de plus de " + str(max_length) + " octets", 414)
    parts := _s.split(line, " ")
    if len(parts) != 3:
        if len(parts) > 3 and _s.starts_with(parts[len(parts) - 1], "HTTP/"):
            _err.parse_error(fn, "espaces en trop dans la ligne de requête")
        _err.parse_error(fn, "ligne de requête invalide '" + _hv.sanitize(line[0:80]) + "'")
    if not _method.is_token(parts[0]):
        _err.parse_error(fn, "méthode invalide '" + _hv.sanitize(parts[0]) + "'")
    v := _version.parse(parts[2])
    if v.major != 1:
        _err.version_error(fn, "version non prise en charge " + parts[2])
    if parts[1] == "":
        _err.parse_error(fn, "cible de requête vide")
    return (parts[0], parts[1], parts[2])

# « HTTP/1.1 404 Not Found » -> (version, statut int, raison).
func parse_status_line(line):
    fn := "protocol_parser.parse_status_line"
    sp := _s.find(line, " ")
    if sp < 0:
        _err.parse_error(fn, "ligne de statut invalide '" + _hv.sanitize(line[0:80]) + "'")
    v := line[0:sp]
    _version.parse(v)
    rest := line[sp + 1:len(line)]
    code_text := rest
    reason := ""
    sp2 := _s.find(rest, " ")
    if sp2 >= 0:
        code_text = rest[0:sp2]
        reason = rest[sp2 + 1:len(rest)]
    if len(code_text) != 3:
        _err.parse_error(fn, "code de statut invalide '" + _hv.sanitize(code_text) + "'")
    code := 0
    for c in code_text:
        if c < '0' or c > '9':
            _err.parse_error(fn, "code de statut invalide '" + _hv.sanitize(code_text) + "'")
        code = code * 10 + (_s.ord(c) - 48)
    if code < 100:
        _err.parse_error(fn, "code de statut invalide " + code_text)
    return (v, code, reason)

# ---------------------------------------------------------------- analyseur commun

# Moteur d'analyse d'un flux de messages : ligne de départ, en-têtes, corps. Les sous-classes décident du cadrage
# du corps et construisent les messages.
class MessageParser:
    func init(limits=null):
        self.limits = limits if limits != null else Limits()
        self.buffer = ""               # octets reçus ; ceux avant pos sont consommés
        self.pos = 0
        self.state = "start"           # start, headers, body_length, body_chunked, body_close, done
        self.start = null              # ligne de départ analysée
        self.headers = null
        self.header_bytes = 0
        self.header_count = 0
        self.body_parts = []
        self.body_size = 0
        self.remaining = 0
        self.chunked = null
        self.closed = false            # plus rien ne sera accepté (après une erreur ou finish)
        self.messages_parsed = 0

    # Ligne terminée par LF (CR optionnel retiré) ; null si incomplète. limit : longueur maximale.
    func _line(limit, status, what):
        i := _s.byte_find(self.buffer, "\n", self.pos)
        if i < 0:
            if limit != null and self.pending() > limit:
                _err.limit_error("protocol_parser", what + " de plus de " + str(limit) + " octets", status)
            return null
        if limit != null and i - self.pos > limit + 1:
            _err.limit_error("protocol_parser", what + " de plus de " + str(limit) + " octets", status)
        line := _s.byte_slice(self.buffer, self.pos, i)
        used := i + 1 - self.pos
        self.pos = i + 1
        n := _s.byte_len(line)
        if n > 0 and _s.byte_at(line, n - 1) == 13:
            line = _s.byte_slice(line, 0, n - 1)
        if not _pe.is_valid_utf8(_s.byte_unpack(line)):
            _err.parse_error("protocol_parser", what + " : octets non UTF-8")
        return (line, used)

    # Octets en attente (début d'un message suivant non encore complet).
    func pending():
        return _s.byte_len(self.buffer) - self.pos

    func is_idle():
        return self.state == "start" and self.pending() == 0

    # Retire les octets consommés du tampon (une copie par appel de feed).
    func _compact():
        if self.pos > 0:
            self.buffer = _s.byte_slice(self.buffer, self.pos, _s.byte_len(self.buffer))
            self.pos = 0

    # Octets restants, retirés du tampon.
    func _take_all():
        rest := _s.byte_slice(self.buffer, self.pos, _s.byte_len(self.buffer))
        self.buffer = ""
        self.pos = 0
        return rest

    # Vrai si une section d'en-têtes est entièrement lue et que le corps est attendu.
    func in_body():
        return self.state == "body_length" or self.state == "body_chunked" or self.state == "body_close"

    func _reset_message():
        self.state = "start"
        self.start = null
        self.headers = null
        self.header_bytes = 0
        self.header_count = 0
        self.body_parts = []
        self.body_size = 0
        self.remaining = 0
        self.chunked = null

    func _add_body(data):
        if data == "":
            return
        self.body_size += _s.byte_len(data)
        if self.limits.max_body != null and self.body_size > self.limits.max_body:
            _err.limit_error("protocol_parser", "corps de plus de " + str(self.limits.max_body) + " octets", 413)
        append(self.body_parts, data)

    # Fait avancer l'analyse ; rend la liste des messages complétés.
    func feed(data):
        if self.closed:
            _err.http_error("protocol_parser.feed", "analyseur fermé")
        self._compact()
        self.buffer = self.buffer + data
        out := []
        while true:
            progressed := self._step(out)
            if not progressed:
                break
        self._compact()
        return out

    func _step(out):
        if self.state == "start":
            r := self._line(self.limits.max_start_line, self._start_line_status(), "ligne de départ")
            if r == null:
                return false
            if r[0] == "":
                return true     # lignes vides tolérées avant un message (RFC 9112 §2.2)
            self.start = self._parse_start(r[0])
            self.headers = _headers.Headers()
            self.state = "headers"
            return true
        if self.state == "headers":
            remaining_budget := self.limits.max_header_bytes - self.header_bytes
            r := self._line(remaining_budget, 431, "section d'en-têtes")
            if r == null:
                return false
            self.header_bytes += r[1]
            if self.header_bytes > self.limits.max_header_bytes:
                _err.limit_error("protocol_parser", "en-têtes de plus de " + str(self.limits.max_header_bytes) + " octets", 431)
            line := r[0]
            if line == "":
                self._headers_done(out)
                return true
            if line[0] == ' ' or line[0] == '\t':
                if not self.limits.allow_obs_fold or self.headers.size() == 0:
                    _err.parse_error("protocol_parser", "ligne d'en-tête repliée (obs-fold) refusée")
                last := self.headers.entries[self.headers.size() - 1]
                last[1] = last[1] + " " + _hv.trim(line)
                return true
            self.header_count += 1
            if self.header_count > self.limits.max_headers:
                _err.limit_error("protocol_parser", "plus de " + str(self.limits.max_headers) + " en-têtes", 431)
            p := _headers.parse_line(line)
            append(self.headers.entries, [p[0], p[1]])
            return true
        if self.state == "body_length":
            avail := self.pending()
            if avail == 0:
                return false
            k := self.remaining
            if avail < k:
                k = avail
            self._add_body(_s.byte_slice(self.buffer, self.pos, self.pos + k))
            self.pos += k
            self.remaining -= k
            if self.remaining == 0:
                self._complete(out, null)
            return true
        if self.state == "body_chunked":
            if self.pending() == 0:
                return false
            data := self._take_all()
            self._add_body(self.chunked.feed(data))
            if self.chunked.done:
                self.buffer = self.chunked.rest()
                self.pos = 0
                self._complete(out, self.chunked.trailers)
                return true
            return false
        if self.state == "body_close":
            if self.pending() == 0:
                return false
            self._add_body(self._take_all())
            return false
        return false

    func _headers_done(out):
        framing := self._framing()
        if framing == _mb.NONE:
            self._complete(out, null)
        elif framing == _mb.LENGTH:
            n := _cl.from_headers(self.headers)
            if self.limits.max_body != null and n > self.limits.max_body:
                _err.limit_error("protocol_parser", "corps annoncé de " + str(n) + " octets, limite " + str(self.limits.max_body), 413)
            self.remaining = n
            self.state = "body_length"
            if n == 0:
                self._complete(out, null)
        elif framing == _mb.CHUNKED:
            self.chunked = _mb.ChunkedDecoder(self.limits.max_body)
            self.state = "body_chunked"
        else:
            self.state = "body_close"

    func _complete(out, trailers):
        msg := self._build(_s.byte_join(self.body_parts), trailers)
        self.messages_parsed += 1
        self._reset_message()
        if msg != null:
            append(out, msg)

    # À la fin du flux : termine un corps « jusqu'à la fermeture » ; HttpParseError si un message est tronqué.
    func finish():
        out := []
        if self.state == "body_close":
            self._complete(out, null)
        elif self.state != "start" or self.pending() > 0:
            self.closed = true
            _err.parse_error("protocol_parser.finish", "message HTTP tronqué (flux terminé pendant « " + self.state + " »)")
        self.closed = true
        return out

    # À redéfinir.
    func _start_line_status():
        return 400

    func _parse_start(line):
        return line

    func _framing():
        return _mb.NONE

    func _build(body, trailers):
        return null

# Requêtes reçues par un serveur.
class RequestParser extends MessageParser:
    func init(limits=null):
        super.init(limits)
        self.continue_pending = false    # « Expect: 100-continue » reçu, corps pas encore lu

    func _start_line_status():
        return 414

    func _parse_start(line):
        return parse_request_line(line, self.limits.max_start_line)

    func _framing():
        if self.start[2] == "HTTP/1.1" and not self.headers.has("host"):
            _err.parse_error("protocol_parser", "en-tête Host manquant (obligatoire en HTTP/1.1)")
        if self.headers.count("host") > 1:
            _err.parse_error("protocol_parser", "plusieurs en-têtes Host")
        f := _mb.request_framing(self.headers)
        if f == _mb.CHUNKED and self.start[2] == "HTTP/1.0":
            _err.parse_error("protocol_parser", "Transfer-Encoding en HTTP/1.0")
        self.continue_pending = f != _mb.NONE and _s.lower(self.headers.get("expect", "")) == "100-continue"
        return f

    func _build(body, trailers):
        self.continue_pending = false
        r := _request.Request(self.start[0], self.start[1], self.headers, body, self.start[2])
        r.trailers = trailers
        return r

    # Méthode, cible et en-têtes de la requête en cours (après les en-têtes, avant le corps), ou null.
    func current_head():
        if self.headers == null or self.state == "headers" or self.state == "start":
            return null
        return (self.start[0], self.start[1], self.start[2], self.headers)

# Réponses reçues par un client ; method : méthode de la requête (HEAD : jamais de corps).
class ResponseParser extends MessageParser:
    func init(method="GET", limits=null):
        super.init(limits)
        self.method = method
        self.informational = []        # réponses 1xx reçues (100 Continue, 103 Early Hints)

    func _start_line_status():
        return 502

    func _parse_start(line):
        return parse_status_line(line)

    func _framing():
        return _mb.response_framing(self.method, self.start[1], self.headers)

    func _build(body, trailers):
        r := _response.Response(self.start[1], body, self.headers, self.start[2], self.start[0])
        r.trailers = trailers
        if _status.is_informational(self.start[1]) and self.start[1] != 101:
            append(self.informational, r)
            return null
        return r

    # Nouvelle requête sur la même connexion.
    func expect(method):
        self.method = method

# ---------------------------------------------------------------- messages complets

# Une requête complète (texte) ; HttpParseError si le texte est incomplet ou contient plus d'une requête.
func parse_request(text, limits=null):
    p := RequestParser(limits)
    msgs := p.feed(text)
    if len(msgs) == 0:
        _err.parse_error("protocol_parser.parse_request", "requête incomplète")
    if len(msgs) > 1 or p.pending() > 0:
        _err.parse_error("protocol_parser.parse_request", "données après la fin de la requête")
    return msgs[0]

# Toutes les requêtes d'un texte (pipelining).
func parse_requests(text, limits=null):
    p := RequestParser(limits)
    msgs := p.feed(text)
    if p.pending() > 0:
        _err.parse_error("protocol_parser.parse_requests", "requête incomplète en fin de texte")
    return msgs

# Une réponse complète ; un corps sans longueur est lu jusqu'à la fin du texte.
func parse_response(text, method="GET", limits=null):
    p := ResponseParser(method, limits)
    msgs := p.feed(text)
    if len(msgs) == 0:
        msgs = p.finish()
    if len(msgs) == 0:
        _err.parse_error("protocol_parser.parse_response", "réponse incomplète")
    return msgs[0]
