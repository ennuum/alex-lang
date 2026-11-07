# ALEX STANDARD LIBRARY — web.server.http2
#
# HTTP/2 (RFC 9113) côté serveur, piloté par la boucle de web.server (aucun fil, aucune lecture bloquante) :
#   - h2c « prior knowledge » : une connexion en clair qui commence par la préface HTTP/2 (curl --http2-prior-knowledge,
#     mandataires inverses) ; config.http2 = false le désactive ;
#   - h2 sur TLS : protocole ALPN « h2 » (tls_server.TlsServerConfig(..., ["h2", "http/1.1"])) ;
#   - flux multiplexés : chaque requête est servie par la même application que HTTP/1.1 (gestionnaires async compris),
#     les réponses partent dans l'ordre où elles sont prêtes ;
#   - contrôle de flux des deux côtés (WINDOW_UPDATE), trames DATA bornées par SETTINGS_MAX_FRAME_SIZE ;
#   - corps str, fichiers (par morceaux, sans tout charger) et réponses en flux / SSE (web.server.streaming) ;
#   - HPACK de network.grpc (décodeur complet, encodeur sans table dynamique) ;
#   - erreurs de protocole : GOAWAY puis fermeture ; erreurs d'un flux : RST_STREAM.
# Non pris en charge : push serveur (désactivé), WebSocket sur HTTP/2 (RFC 8441 : les navigateurs ouvrent alors une
# connexion HTTP/1.1), priorités (ignorées), h2c par Upgrade depuis HTTP/1.1.

from core use len, type, to_int
from collections use append, keys, remove
use string as _s
use time as _time
use io as _io
use os as _os
use asyncio as _aio
use network.grpc as _g
use web.http.request as _request
use web.http.response as _response
use web.http.status_code as _status
use web.http.date_header as _date

const PREFACE := "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"
const LOCAL_WINDOW := 4194304
const MAX_FRAME := 16384
const MAX_STREAMS := 100
const FILE_CHUNK := 65536

# En-têtes propres à une connexion HTTP/1.1, interdits en HTTP/2 (RFC 9113 §8.2.2).
const HOP_BY_HOP := ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade", "te"]

# Vrai si data (début d'une connexion) est une tentative HTTP/2 : début de la préface (« PRI » est réservé à
# HTTP/2 ; une préface fausse au-delà reçoit un GOAWAY plutôt qu'une réponse HTTP/1.1).
func looks_like_preface(data):
    n := _s.byte_len(data)
    if n == 0:
        return false
    k := n if n < 4 else 4
    return _s.byte_slice(data, 0, k) == _s.byte_slice(PREFACE, 0, k)

func _u32(v):
    return _s.byte_pack([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255])

func _setting(ident, value):
    return _s.byte_pack([(ident >> 8) & 255, ident & 255]) + _u32(value)

func _frame(ftype, flags, sid, payload):
    n := _s.byte_len(payload)
    return _s.byte_pack([(n >> 16) & 255, (n >> 8) & 255, n & 255, ftype, flags, (sid >> 24) & 127, (sid >> 16) & 255, (sid >> 8) & 255, sid & 255]) + payload

# Flux d'une session : requête reçue, réponse à envoyer.
class H2Stream:
    func init(sid, send_window):
        self.id = sid
        self.headers = null              # [nom, valeur] décodés (pseudo-en-têtes compris)
        self.body = []                   # morceaux du corps reçu
        self.body_size = 0
        self.ended = false               # END_STREAM reçu
        self.request = null
        self.future = null               # réponse async attendue
        self.t0 = _time.monotonic()
        self.send_window = send_window
        self.out = ""                    # octets de réponse en attente (contrôle de flux)
        self.file = null                 # [chemin, position, restant] d'un corps fichier
        self.finish = false              # END_STREAM à poser quand tout est parti
        self.done = false                # réponse entièrement envoyée
        self.reset = false               # RST_STREAM reçu ou envoyé
        self.sent = 0
        self.response = null
        self.flux = null                 # réponse en flux (web.server.streaming.Stream)

# Connexion « socket » vue par web.server.streaming.Stream pour une réponse en flux sur un flux HTTP/2.
class _FluxPipe:
    func init(session, st):
        self.session = session
        self.st = st
        self.socket = self

    func send(data, timeout=null):
        return self.session._queue(self.st, data)

    func close():
        self.session._end(self.st)

    # Stream.poll : "" (fin) si le client a annulé le flux ou fermé la connexion, sinon rien à lire.
    func try_recv(n=4096):
        if self.st.reset or self.session.closed:
            return ""
        return null

class H2Session:
    # conn : web.server.connection.ServerConnection détachée du HTTP/1 ; server : web.server.Server ; initial :
    # octets déjà reçus (préface comprise).
    func init(conn, server, initial=""):
        self.conn = conn
        self.server = server
        self.buf = initial
        self.preface_seen = false
        self.decoder = _g.HpackDecoder(4096, server.config.limits.max_header_bytes)
        self.encoder = _g.HpackEncoder()
        self.streams = {}
        self.last_sid = 0
        self.peer_window = 65535         # fenêtre initiale des flux annoncée par le client
        self.peer_frame = MAX_FRAME
        self.send_window = 65535         # fenêtre d'envoi de la connexion
        self.header_block = null         # [flux, octets, drapeaux] (CONTINUATION)
        self.closed = false
        self.goaway_sent = false
        self.requests = 0
        self.last_activity = _time.monotonic()
        self._write(_frame(_g.SETTINGS, 0, 0, _setting(_g.SETTINGS_ENABLE_PUSH, 0) + _setting(_g.SETTINGS_MAX_CONCURRENT_STREAMS, MAX_STREAMS) + _setting(_g.SETTINGS_INITIAL_WINDOW_SIZE, LOCAL_WINDOW) + _setting(_g.SETTINGS_MAX_HEADER_LIST_SIZE, server.config.limits.max_header_bytes)) + _frame(_g.WINDOW_UPDATE, 0, 0, _u32(LOCAL_WINDOW - 65535)))
        self._process()

    func raw_socket():
        return self.conn.raw_socket()

    # Flux dont la réponse n'est pas encore terminée.
    func active():
        n := 0
        for k in keys(self.streams):
            if not self.streams[k].done:
                n += 1
        return n

    # Vrai si une réponse async est attendue (la boucle laisse alors la main aux tâches).
    func waiting():
        for k in keys(self.streams):
            if self.streams[k].future != null:
                return true
        return false

    # ------------------------------------------------------------ lecture

    func on_readable():
        if self.closed:
            return
        while true:
            data := null
            try:
                data = self.conn.socket.try_recv(65536)
            catch e:
                self.close()
                return
            if data == null:
                break
            if data == "":
                self.close()
                return
            self.conn.bytes_in += _s.byte_len(data)
            self.buf = self.buf + data
            self.last_activity = _time.monotonic()
        self._process()

    func _process():
        try:
            self._frames()
        catch e:
            if not self.closed:
                self._connection_error(_g.ERR_PROTOCOL, str(e.message))

    func _frames():
        if not self.preface_seen:
            if _s.byte_len(self.buf) < 24:
                if self.buf != "" and not looks_like_preface(self.buf):
                    self._connection_error(_g.ERR_PROTOCOL, "préface HTTP/2 invalide")
                return
            if _s.byte_slice(self.buf, 0, 24) != PREFACE:
                self._connection_error(_g.ERR_PROTOCOL, "préface HTTP/2 invalide")
                return
            self.preface_seen = true
            self.buf = _s.byte_slice(self.buf, 24, _s.byte_len(self.buf))
        while not self.closed:
            n := _s.byte_len(self.buf)
            if n < 9:
                return
            h := _s.byte_unpack(_s.byte_slice(self.buf, 0, 9))
            length := (h[0] << 16) | (h[1] << 8) | h[2]
            if length > MAX_FRAME:
                self._connection_error(_g.ERR_FRAME_SIZE, "trame de " + str(length) + " octets (maximum " + str(MAX_FRAME) + ")")
                return
            if n < 9 + length:
                return
            payload := _s.byte_slice(self.buf, 9, 9 + length)
            self.buf = _s.byte_slice(self.buf, 9 + length, n)
            sid := ((h[5] & 127) << 24) | (h[6] << 16) | (h[7] << 8) | h[8]
            self._frame_in(h[3], h[4], sid, payload)

    func _frame_in(ftype, flags, sid, payload):
        if self.header_block != null and ftype != _g.CONTINUATION:
            self._connection_error(_g.ERR_PROTOCOL, "CONTINUATION attendue")
            return
        if ftype == _g.HEADERS:
            self._on_headers(sid, flags, payload)
        elif ftype == _g.CONTINUATION:
            if self.header_block == null or self.header_block[0] != sid:
                self._connection_error(_g.ERR_PROTOCOL, "CONTINUATION inattendue")
                return
            self.header_block[1] = self.header_block[1] + payload
            if _s.byte_len(self.header_block[1]) > self.server.config.limits.max_header_bytes * 2:
                self._connection_error(_g.ERR_PROTOCOL, "bloc d'en-têtes trop grand")
                return
            if (flags & _g.FLAG_END_HEADERS) != 0:
                hb := self.header_block
                self.header_block = null
                self._headers_complete(hb[0], hb[2], hb[1])
        elif ftype == _g.DATA:
            self._on_data(sid, flags, payload)
        elif ftype == _g.SETTINGS:
            self._on_settings(sid, flags, payload)
        elif ftype == _g.WINDOW_UPDATE:
            if sid != 0 and self._idle(sid):
                self._connection_error(_g.ERR_PROTOCOL, "WINDOW_UPDATE sur un flux inactif")
                return
            self._on_window(sid, payload)
        elif ftype == _g.PRIORITY:
            if sid == 0:
                self._connection_error(_g.ERR_PROTOCOL, "PRIORITY sur le flux 0")
                return
            if _s.byte_len(payload) != 5:
                self._stream_error(sid, _g.ERR_FRAME_SIZE)
                return
            if self._depends_on(payload) == sid:
                self._stream_error(sid, _g.ERR_PROTOCOL)
        elif ftype == _g.PING:
            if sid != 0 or _s.byte_len(payload) != 8:
                self._connection_error(_g.ERR_PROTOCOL, "PING invalide")
                return
            if (flags & _g.FLAG_ACK) == 0:
                self._write(_frame(_g.PING, _g.FLAG_ACK, 0, payload))
        elif ftype == _g.RST_STREAM:
            if sid == 0 or self._idle(sid):
                self._connection_error(_g.ERR_PROTOCOL, "RST_STREAM sur un flux inactif")
                return
            if _s.byte_len(payload) != 4:
                self._connection_error(_g.ERR_FRAME_SIZE, "RST_STREAM de taille invalide")
                return
            if sid in self.streams:
                st := self.streams[sid]
                st.reset = true
                st.done = true
                if st.future != null:
                    _aio.cancel(st.future)
                    st.future = null
                self._forget(st)
        elif ftype == _g.GOAWAY:
            if sid != 0:
                self._connection_error(_g.ERR_PROTOCOL, "GOAWAY sur un flux")
                return
            self.goaway_sent = true          # le client part : plus de nouveaux flux ; on termine les réponses en cours
        elif ftype == _g.PUSH_PROMISE:
            self._connection_error(_g.ERR_PROTOCOL, "PUSH_PROMISE envoyé par un client")
        # PRIORITY et types inconnus : ignorés (RFC 9113 §5.5)

    func _strip_padding(flags, payload):
        if (flags & _g.FLAG_PADDED) == 0:
            return payload
        n := _s.byte_len(payload)
        if n < 1:
            self._connection_error(_g.ERR_PROTOCOL, "remplissage invalide")
            return ""
        pad := _s.byte_at(payload, 0)
        if pad >= n:
            self._connection_error(_g.ERR_PROTOCOL, "remplissage trop long")
            return ""
        return _s.byte_slice(payload, 1, n - pad)

    # Flux jamais ouvert (identifiant client au-delà du dernier vu).
    func _idle(sid):
        return sid > self.last_sid and not (sid in self.streams)

    func _depends_on(prio):
        b := _s.byte_unpack(_s.byte_slice(prio, 0, 4))
        return ((b[0] & 127) << 24) | (b[1] << 16) | (b[2] << 8) | b[3]

    # Erreur limitée à un flux : RST_STREAM (le flux est oublié s'il existait).
    func _stream_error(sid, code):
        if sid in self.streams:
            self._reset(self.streams[sid], code)
        else:
            self._write(_frame(_g.RST_STREAM, 0, sid, _u32(code)))

    func _on_headers(sid, flags, payload):
        if sid == 0 or sid % 2 == 0:
            self._connection_error(_g.ERR_PROTOCOL, "HEADERS sur un flux invalide")
            return
        p := self._strip_padding(flags, payload)
        if (flags & _g.FLAG_PRIORITY) != 0:
            if _s.byte_len(p) < 5:
                self._connection_error(_g.ERR_FRAME_SIZE, "HEADERS avec priorité trop court")
                return
            if self._depends_on(p) == sid:
                self._stream_error(sid, _g.ERR_PROTOCOL)
                if sid > self.last_sid:
                    self.last_sid = sid
                return
            p = _s.byte_slice(p, 5, _s.byte_len(p))
        if (flags & _g.FLAG_END_HEADERS) == 0:
            self.header_block = [sid, p, flags]
            return
        self._headers_complete(sid, flags, p)

    func _headers_complete(sid, flags, block):
        hs := null
        try:
            hs = self.decoder.decode(_s.byte_unpack(block))
        catch e:
            self._connection_error(_g.ERR_COMPRESSION, "HPACK : " + str(e.message))
            return
        if sid in self.streams:
            st := self.streams[sid]          # en-têtes de fin (trailers) : terminent le corps, sans pseudo-en-tête
            if st.ended:
                self._stream_error(sid, _g.ERR_STREAM_CLOSED)
                return
            if (flags & _g.FLAG_END_STREAM) == 0:
                self._stream_error(sid, _g.ERR_PROTOCOL)
                return
            for h in hs:
                if _s.starts_with(h[0], ":"):
                    self._stream_error(sid, _g.ERR_PROTOCOL)
                    return
            st.ended = true
            self._end_of_body(st)
            return
        if sid <= self.last_sid:
            self._connection_error(_g.ERR_STREAM_CLOSED if sid % 2 == 1 else _g.ERR_PROTOCOL, "identifiant de flux réutilisé " + str(sid))
            return
        self.last_sid = sid
        bad := _check_request_fields(hs)
        if bad != null:
            self._stream_error(sid, _g.ERR_PROTOCOL)
            return
        if self.goaway_sent or self.active() >= MAX_STREAMS:
            self._write(_frame(_g.RST_STREAM, 0, sid, _u32(_g.ERR_REFUSED_STREAM)))
            return
        st := H2Stream(sid, self.peer_window)
        st.headers = hs
        self.streams[sid] = st
        if (flags & _g.FLAG_END_STREAM) != 0:
            st.ended = true
            self._end_of_body(st)

    # Corps complet : contrôle de content-length (RFC 9113 §8.1.1), puis traitement.
    func _end_of_body(st):
        for h in st.headers:
            if h[0] == "content-length":
                ok := true
                try:
                    ok = to_int(h[1]) == st.body_size
                catch e:
                    ok = false
                if not ok:
                    self._stream_error(st.id, _g.ERR_PROTOCOL)
                    return
        self._dispatch(st)

    func _on_data(sid, flags, payload):
        n := _s.byte_len(payload)
        if sid == 0 or self._idle(sid):
            self._connection_error(_g.ERR_PROTOCOL, "DATA sur un flux inconnu")
            return
        if not (sid in self.streams) or self.streams[sid].ended:
            # flux fermé (ou demi-fermé côté client) : STREAM_CLOSED, puis on rend le crédit de la connexion
            self._stream_error(sid, _g.ERR_STREAM_CLOSED)
            if n > 0:
                self._write(_frame(_g.WINDOW_UPDATE, 0, 0, _u32(n)))
            return
        st := self.streams[sid]
        data := self._strip_padding(flags, payload)
        st.body_size += _s.byte_len(data)
        maxb := self.server.config.limits.max_body
        if maxb != null and st.body_size > maxb:
            self._respond_now(st, _response.error(413))
            return
        append(st.body, data)
        if n > 0:
            out := _frame(_g.WINDOW_UPDATE, 0, 0, _u32(n))
            if (flags & _g.FLAG_END_STREAM) == 0:
                out = out + _frame(_g.WINDOW_UPDATE, 0, sid, _u32(n))
            self._write(out)
        if (flags & _g.FLAG_END_STREAM) != 0:
            st.ended = true
            self._end_of_body(st)

    func _on_settings(sid, flags, payload):
        if sid != 0:
            self._connection_error(_g.ERR_PROTOCOL, "SETTINGS sur un flux")
            return
        if (flags & _g.FLAG_ACK) != 0:
            if _s.byte_len(payload) != 0:
                self._connection_error(_g.ERR_FRAME_SIZE, "SETTINGS ACK avec contenu")
            return
        b := _s.byte_unpack(payload)
        if len(b) % 6 != 0:
            self._connection_error(_g.ERR_FRAME_SIZE, "SETTINGS de taille invalide")
            return
        i := 0
        while i < len(b):
            ident := (b[i] << 8) | b[i + 1]
            value := (b[i + 2] << 24) | (b[i + 3] << 16) | (b[i + 4] << 8) | b[i + 5]
            if ident == _g.SETTINGS_ENABLE_PUSH and value > 1:
                self._connection_error(_g.ERR_PROTOCOL, "SETTINGS_ENABLE_PUSH invalide")
                return
            if ident == _g.SETTINGS_INITIAL_WINDOW_SIZE:
                if value > 2147483647:
                    self._connection_error(_g.ERR_FLOW_CONTROL, "fenêtre initiale trop grande")
                    return
                delta := value - self.peer_window
                self.peer_window = value
                for k in keys(self.streams):
                    self.streams[k].send_window += delta
                    if self.streams[k].send_window > 2147483647:
                        self._connection_error(_g.ERR_FLOW_CONTROL, "fenêtre de flux trop grande")
                        return
            elif ident == _g.SETTINGS_MAX_FRAME_SIZE:
                if value < 16384 or value > 16777215:
                    self._connection_error(_g.ERR_PROTOCOL, "taille de trame maximale invalide")
                    return
                self.peer_frame = value
            i += 6
        self._write(_frame(_g.SETTINGS, _g.FLAG_ACK, 0, ""))
        self._flush_all()

    func _on_window(sid, payload):
        if _s.byte_len(payload) != 4:
            self._connection_error(_g.ERR_FRAME_SIZE, "WINDOW_UPDATE de taille invalide")
            return
        b := _s.byte_unpack(payload)
        inc := ((b[0] & 127) << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
        if inc == 0:
            if sid == 0:
                self._connection_error(_g.ERR_PROTOCOL, "WINDOW_UPDATE nul")
            else:
                self._stream_error(sid, _g.ERR_PROTOCOL)
            return
        if sid == 0:
            self.send_window += inc
            if self.send_window > 2147483647:
                self._connection_error(_g.ERR_FLOW_CONTROL, "fenêtre de connexion au-delà de 2^31-1")
                return
        elif sid in self.streams:
            st := self.streams[sid]
            st.send_window += inc
            if st.send_window > 2147483647:
                self._reset(st, _g.ERR_FLOW_CONTROL)
                return
        self._flush_all()

    # ------------------------------------------------------------ requêtes

    func _dispatch(st):
        method := null
        path := null
        authority := null
        scheme := null
        headers := []
        for h in st.headers:
            n := h[0]
            if _s.starts_with(n, ":"):
                if n == ":method":
                    method = h[1]
                elif n == ":path":
                    path = h[1]
                elif n == ":authority":
                    authority = h[1]
                elif n == ":scheme":
                    scheme = h[1]
            elif n == "cookie":
                append(headers, h)               # recollés plus bas (RFC 9113 §8.2.3)
            else:
                append(headers, h)
        if method == null or path == null or (method != "CONNECT" and scheme == null):
            self._reset(st, _g.ERR_PROTOCOL)
            return
        req := null
        try:
            req = _request.Request(method, path, null, _s.join("", st.body), "HTTP/2")
            cookies := []
            for h in headers:
                if h[0] == "cookie":
                    append(cookies, h[1])
                else:
                    req.headers.add(h[0], h[1])
            if len(cookies) > 0:
                req.headers.set("Cookie", _s.join("; ", cookies))
            if authority != null and not req.headers.has("host"):
                req.headers.set("Host", authority)
            req.request_target()
        catch e:
            self._respond_now(st, _response.error(400))
            return
        st.body = []
        req.remote_address = self.conn.address
        req.local_address = self.conn.local_address
        req.secure = self.conn.secure
        req.received_at = _time.time()
        st.request = req
        st.t0 = _time.monotonic()
        self.requests += 1
        resp := self.server._h2_call(req)
        if _aio.is_future(resp):
            st.future = resp
        else:
            self._respond(st, resp)

    # Réponses async terminées, envois en attente ; rend vrai s'il reste des réponses attendues.
    func poll():
        if self.closed:
            return false
        pending := false
        for k in keys(self.streams):
            st := self.streams[k]
            if st.future == null:
                continue
            if not _aio.done(st.future):
                pending = true
                continue
            f := st.future
            st.future = null
            resp := null
            if _aio.failed(f) or _aio.cancelled(f):
                resp = _response.error(500)
            else:
                resp = _aio.result(f)
            self._respond(st, resp)
        self._flush_all()
        return pending

    func _respond_now(st, resp):
        if st.request == null:
            st.request = _request.Request("GET", "/", null, "", "HTTP/2")
        self._respond(st, resp)

    func _respond(st, resp):
        if self.closed or st.reset:
            return
        req := st.request
        st.response = resp
        if "stream" in req.state and resp.status == 200:
            self._start_flux(st, resp)
            return
        method := req.method
        no_body := method == "HEAD" or not _status.allows_body(resp.status)
        body := ""
        size := 0
        if not no_body:
            if resp.body_file != null:
                rng := resp.body_range if resp.body_range != null else (0, _os.size(resp.body_file))
                st.file = [resp.body_file, rng[0], rng[1]]
                size = rng[1]
            elif resp.body_stream != null:
                parts := []
                while true:
                    piece := resp.body_stream()
                    if piece == null:
                        break
                    append(parts, str(piece))
                body = _s.join("", parts)
                size = _s.byte_len(body)
            else:
                body = resp.body if type(resp.body) == "str" else str(resp.body)
                size = _s.byte_len(body)
        fields := [[":status", str(resp.status)]]
        for e in resp.headers.entries:
            n := e[2]
            if n in HOP_BY_HOP or n == "content-length" or n == "date" or n == "server":
                continue
            append(fields, [n, e[1]])
        append(fields, ["date", _date.now()])
        sname := self.server.config.server_name
        if sname != null and sname != false:
            append(fields, ["server", sname])
        if not no_body or (method == "HEAD" and _status.allows_body(resp.status)):
            append(fields, ["content-length", str(size if not no_body else _head_length(resp))])
        has_body := not no_body and (size > 0)
        self._send_headers(st.id, fields, not has_body)
        if not has_body:
            self._complete(st)
            return
        st.out = body
        st.finish = true
        self._flush(st)

    func _send_headers(sid, fields, end_stream):
        block := _s.byte_pack(self.encoder.encode(fields))
        flags := _g.FLAG_END_STREAM if end_stream else 0
        total := _s.byte_len(block)
        maxf := self.peer_frame
        if total <= maxf:
            self._write(_frame(_g.HEADERS, flags | _g.FLAG_END_HEADERS, sid, block))
            return
        out := _frame(_g.HEADERS, flags, sid, _s.byte_slice(block, 0, maxf))
        pos := maxf
        while pos < total:
            end := pos + maxf
            f := 0
            if end >= total:
                end = total
                f = _g.FLAG_END_HEADERS
            out = out + _frame(_g.CONTINUATION, f, sid, _s.byte_slice(block, pos, end))
            pos = end
        self._write(out)

    # Envoie ce que les fenêtres permettent ; END_STREAM quand tout est parti.
    func _flush(st):
        if st.done or st.reset or self.closed:
            return
        frames := []
        while true:
            if st.out == "" and st.file != null and st.file[2] > 0:
                want := FILE_CHUNK if st.file[2] > FILE_CHUNK else st.file[2]
                data := _io.read_raw(st.file[0], st.file[1], want)
                got := _s.byte_len(data)
                if got == 0:
                    st.file[2] = 0
                else:
                    st.out = data
                    st.file[1] = st.file[1] + got
                    st.file[2] = st.file[2] - got
            remaining := _s.byte_len(st.out)
            file_left := st.file != null and st.file[2] > 0
            if remaining == 0:
                if st.finish and not file_left:
                    append(frames, _frame(_g.DATA, _g.FLAG_END_STREAM, st.id, ""))
                    self._write(_s.join("", frames))
                    self._complete(st)
                    return
                break
            k := remaining
            if k > self.peer_frame:
                k = self.peer_frame
            if k > self.send_window:
                k = self.send_window
            if k > st.send_window:
                k = st.send_window
            if k <= 0:
                break
            chunk := _s.byte_slice(st.out, 0, k)
            st.out = _s.byte_slice(st.out, k, remaining)
            self.send_window -= k
            st.send_window -= k
            st.sent += k
            last := st.finish and st.out == "" and not (st.file != null and st.file[2] > 0)
            append(frames, _frame(_g.DATA, _g.FLAG_END_STREAM if last else 0, st.id, chunk))
            if last:
                self._write(_s.join("", frames))
                self._complete(st)
                return
            if len(frames) >= 16:
                self._write(_s.join("", frames))
                frames = []
        if len(frames) > 0:
            self._write(_s.join("", frames))

    func _flush_all():
        for k in keys(self.streams):
            st := self.streams[k]
            if not st.done and (st.out != "" or st.finish or st.file != null):
                self._flush(st)

    func _complete(st):
        st.done = true
        req := st.request
        resp := st.response
        if req != null and resp != null and st.flux == null:
            self.server._h2_done(req, resp, st.t0, st.sent)
        self._forget(st)

    func _forget(st):
        if st.id in self.streams and st.done and st.future == null:
            remove(self.streams, st.id)

    func _reset(st, code):
        self._write(_frame(_g.RST_STREAM, 0, st.id, _u32(code)))
        st.reset = true
        st.done = true
        if st.future != null:
            _aio.cancel(st.future)
            st.future = null
        self._forget(st)

    # ------------------------------------------------------------ réponses en flux (SSE)

    func _start_flux(st, resp):
        info := st.request.state["stream"]
        fields := [[":status", "200"]]
        for e in resp.headers.entries:
            n := e[2]
            if n in HOP_BY_HOP or n == "content-length" or n == "date" or n == "server":
                continue
            append(fields, [n, e[1]])
        append(fields, ["date", _date.now()])
        if st.request.method == "HEAD":
            self._send_headers(st.id, fields, true)
            self._complete(st)
            return
        self._send_headers(st.id, fields, false)
        self.server._h2_done(st.request, resp, st.t0, 0)
        st.flux = self.server._h2_flux(_FluxPipe(self, st), st.request, info)

    func _queue(st, data):
        if st.done or st.reset or self.closed:
            raise("NetworkError", "http2 : flux fermé")
        n := _s.byte_len(data)
        st.out = st.out + data
        self._flush(st)
        return n

    func _end(st):
        if st.done or st.reset or self.closed:
            return
        st.finish = true
        self._flush(st)

    # ------------------------------------------------------------ écriture, fermeture

    func _write(data):
        if self.closed or data == "":
            return
        try:
            self.conn.bytes_out += self.conn.send(data, self.server.config.timeouts.write)
        catch e:
            self.close()

    func _connection_error(code, message):
        if self.closed:
            return
        self._write(_frame(_g.GOAWAY, 0, 0, _u32(self.last_sid) + _u32(code) + message))
        self.server._record_error("HTTP/2 : " + message)
        self.close()

    # Arrêt propre : plus de nouveaux flux (GOAWAY), les réponses en cours se terminent.
    func shutdown():
        if not self.goaway_sent and not self.closed:
            self.goaway_sent = true
            self._write(_frame(_g.GOAWAY, 0, 0, _u32(self.last_sid) + _u32(_g.ERR_NO_ERROR)))

    func close():
        if self.closed:
            return
        self.closed = true
        for k in keys(self.streams):
            st := self.streams[k]
            if st.future != null:
                _aio.cancel(st.future)
                st.future = null
            st.reset = true
        try:
            self.conn.close()
        catch e:
            ignored := e

func _head_length(resp):
    if resp.body_file != null:
        return resp.body_range[1] if resp.body_range != null else _os.size(resp.body_file)
    if type(resp.body) == "str":
        return _s.byte_len(resp.body)
    return 0

const REQUEST_PSEUDO := [":method", ":scheme", ":authority", ":path"]
const CONNECTION_FIELDS := ["connection", "keep-alive", "proxy-connection", "transfer-encoding", "upgrade"]

# Champs d'une requête conformes à RFC 9113 §8.2 et §8.3 ? Rend la raison du refus, ou null.
func _check_request_fields(hs):
    seen := {}
    regular := false
    for h in hs:
        n := h[0]
        if n != _s.lower(n):
            return "nom en majuscules"
        if _s.starts_with(n, ":"):
            if regular:
                return "pseudo-en-tête après un champ ordinaire"
            if not (n in REQUEST_PSEUDO):
                return "pseudo-en-tête inconnu " + n
            if n in seen:
                return "pseudo-en-tête répété " + n
            seen[n] = true
        else:
            regular = true
            if n in CONNECTION_FIELDS:
                return "champ propre à HTTP/1.1 : " + n
            if n == "te" and _s.lower(_s.trim(h[1])) != "trailers":
                return "TE autre que trailers"
    if not (":method" in seen):
        return ":method absent"
    for h in hs:
        if h[0] == ":method" and h[1] == "CONNECT":
            return null
    if not (":scheme" in seen) or not (":path" in seen):
        return ":scheme ou :path absent"
    for h in hs:
        if h[0] == ":path" and h[1] == "":
            return ":path vide"
    return null
