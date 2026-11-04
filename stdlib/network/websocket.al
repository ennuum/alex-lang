# ALEX STANDARD LIBRARY — network.websocket
#
# WebSocket (RFC 6455) en ALEX pur, client ET serveur, sur network.tcp (ws://) ou network.tls (wss://).
#
# Ce que le module garantit
#   - poignée de main HTTP/1.1 validée des deux côtés (Sec-WebSocket-Accept recalculé avec SHA-1 de network crypto) ;
#   - trames : longueurs 7 / 16 / 64 bits, masquage obligatoire client -> serveur (clé aléatoire du système) et
#     interdit serveur -> client, bits RSV refusés (aucune extension n'est négociée), contrôles <= 125 octets non
#     fragmentés ;
#   - messages fragmentés réassemblés ; texte vérifié en UTF-8 (sinon fermeture 1007) ; taille maximale
#     (max_message, fermeture 1009) ; ping répondu automatiquement par pong, pong ignoré ;
#   - fermeture : close(code, motif) envoie la trame, attend celle du pair (délai), puis coupe ; une trame close
#     reçue reçoit la réponse avant que receive() renvoie null.
#
# Données : un message est une `str` d'octets (texte UTF-8 pour « text », octets bruts pour « binary »).
#
# Erreurs
#   WebSocketError  poignée de main refusée, trame invalide (message de fermeture 1002 envoyé), envoi sur une
#                   connexion fermée.
#   NetworkError, TimeoutError, DnsError, TlsError   voir network.tcp / network.tls.
#
# Exemple (client)
#   use network.websocket as ws
#   c := ws.connect("ws://127.0.0.1:8080/chat")
#   c.send_text("bonjour")
#   m := c.receive(5.0)
#   print(m.kind, m.text())
#   c.close()
#
# Exemple (serveur)
#   srv := ws.Server("127.0.0.1", 8080)
#   c := srv.accept()
#   m := c.receive()
#   c.send_text("écho : " + m.text())
#   c.close()

from core use len, type, to_int
from collections use append
use string as _s
use _native_net as _n
use network.tcp as _tcp
use network.tls as _tls
use network.http as _http
use crypto as _c

const GUID := "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"
const DEFAULT_MAX_MESSAGE := 16777216
const HEADER_LIMIT := 65536

const OP_CONTINUATION := 0
const OP_TEXT := 1
const OP_BINARY := 2
const OP_CLOSE := 8
const OP_PING := 9
const OP_PONG := 10

const CLOSE_NORMAL := 1000
const CLOSE_GOING_AWAY := 1001
const CLOSE_PROTOCOL := 1002
const CLOSE_UNSUPPORTED := 1003
const CLOSE_NO_STATUS := 1005
const CLOSE_ABNORMAL := 1006
const CLOSE_BAD_DATA := 1007
const CLOSE_POLICY := 1008
const CLOSE_TOO_BIG := 1009
const CLOSE_INTERNAL := 1011

func _fail(message):
    raise("WebSocketError", message)

# ------------------------------------------------------------------- poignée de main

# Valeur de Sec-WebSocket-Accept pour une clé client (RFC 6455 §4.2.2).
func accept_key(key):
    return _c.base64_encode(_c.sha1_bytes(_n.to_bytes(key + GUID)))

func _new_key():
    return _c.base64_encode(_n.to_bytes(_n.random_bytes(16)))

# Vrai si la valeur d'un en-tête à jetons séparés par des virgules (Connection, Upgrade) contient jeton.
func _has_token(value, token):
    if value == null:
        return false
    for part in _s.split(_s.lower(value), ","):
        if _s.trim(part) == token:
            return true
    return false

# Codes de fermeture qu'une application peut envoyer ou recevoir (RFC 6455 §7.4).
func valid_close_code(code):
    if type(code) != "int":
        return false
    return (code >= 1000 and code <= 1003) or (code >= 1007 and code <= 1011) or (code >= 3000 and code <= 4999)

class Message:
    func init(kind, data):
        self.kind = kind    # "text" | "binary"
        self.data = data    # octets bruts (str)

    func is_text():
        return self.kind == "text"

    func text():
        return self.data

    func bytes():
        return _n.to_bytes(self.data)

    func size():
        return _n.blen(self.data)

# ------------------------------------------------------------------- connexion

class WebSocket:
    # conn : network.tcp.Connection déjà passée en mode WebSocket ; is_client : masque les trames sortantes.
    func init(conn, is_client, max_message=DEFAULT_MAX_MESSAGE, subprotocol=null, url=null):
        self.conn = conn
        self.is_client = is_client
        self.max_message = max_message
        self.subprotocol = subprotocol    # sous-protocole négocié, ou null
        self.url = url
        self.closed = false               # plus d'envoi ni de réception possibles
        self.close_sent = false
        self.close_code = null            # code reçu du pair (1005 : trame sans code)
        self.close_reason = ""
        self.timeout = null
        self.pings = 0                    # pings reçus (et répondus)
        self.pending_kind = null          # message fragmenté en cours de réception
        self.pending_data = ""

    func set_timeout(t):
        self.timeout = t

    func _t(timeout):
        if timeout == null:
            return self.timeout
        return timeout

    # Trame sortante : en-tête (FIN, opcode, masque, longueur) + charge utile (masquée côté client).
    func _frame(opcode, payload, fin=true):
        n := _n.blen(payload)
        first := opcode
        if fin:
            first = first + 128
        mask_bit := 0
        if self.is_client:
            mask_bit = 128
        head := [first]
        if n < 126:
            append(head, mask_bit + n)
        elif n < 65536:
            append(head, mask_bit + 126)
            append(head, n // 256)
            append(head, n % 256)
        else:
            append(head, mask_bit + 127)
            shift := 56
            while shift >= 0:
                append(head, (n // (1 << shift)) % 256)
                shift -= 8
        out := _n.from_bytes(head)
        if self.is_client:
            key := _n.random_bytes(4)
            return out + key + _n.mask(payload, key)
        return out + payload

    func _send_frame(opcode, payload, fin=true, timeout=null):
        if self.closed or (self.close_sent and opcode != OP_CLOSE):
            _fail("websocket : connexion fermée")
        self.conn.write(self._frame(opcode, payload, fin), self._t(timeout))

    # Envoie un message texte (UTF-8). fragment_size : découpe en trames de cette taille (null : une trame).
    func send_text(text, fragment_size=null, timeout=null):
        if type(text) != "str":
            raise("TypeError", "websocket.send_text : str attendue (obtenu '" + type(text) + "')")
        if not _n.utf8_valid(text):
            raise("ArgumentError", "websocket.send_text : texte UTF-8 invalide (voir send_binary)")
        self._send_message(OP_TEXT, text, fragment_size, timeout)

    # Envoie un message binaire : str d'octets bruts ou list[int].
    func send_binary(data, fragment_size=null, timeout=null):
        if type(data) == "list":
            data = _n.from_bytes(data)
        if type(data) != "str":
            raise("TypeError", "websocket.send_binary : str ou list[int] attendus (obtenu '" + type(data) + "')")
        self._send_message(OP_BINARY, data, fragment_size, timeout)

    func _send_message(opcode, data, fragment_size, timeout):
        n := _n.blen(data)
        if fragment_size == null or n <= fragment_size:
            self._send_frame(opcode, data, true, timeout)
            return
        if type(fragment_size) != "int" or fragment_size < 1:
            raise("ArgumentError", "websocket : fragment_size entier >= 1 attendu")
        pos := 0
        op := opcode
        while pos < n:
            end := pos + fragment_size
            if end > n:
                end = n
            piece := _n.bslice(data, pos, end)
            if opcode == OP_TEXT and end < n:
                # une trame ne coupe pas un caractère en deux octets pour rien : le pair valide le message ENTIER,
                # mais on garde des coupures sur les frontières de caractères par courtoisie.
                keep := _n.utf8_prefix(piece)
                if keep > 0 and keep < _n.blen(piece):
                    end = pos + keep
                    piece = _n.bslice(data, pos, end)
            self._send_frame(op, piece, end >= n, timeout)
            op = OP_CONTINUATION
            pos = end

    func ping(data="", timeout=null):
        if _n.blen(data) > 125:
            raise("ArgumentError", "websocket.ping : 125 octets au plus")
        self._send_frame(OP_PING, data, true, timeout)

    func pong(data="", timeout=null):
        if _n.blen(data) > 125:
            raise("ArgumentError", "websocket.pong : 125 octets au plus")
        self._send_frame(OP_PONG, data, true, timeout)

    # Lit une trame : (fin, opcode, charge utile) ; fermeture 1002 / 1009 / 1007 puis WebSocketError si invalide.
    func _read_frame(timeout):
        head := _n.to_bytes(self.conn.read_exact(2, timeout))
        fin := head[0] >= 128
        if head[0] % 128 >= 16:    # RSV1..3 : aucune extension négociée
            self._protocol_error("bits RSV non nuls (aucune extension négociée)")
        opcode := head[0] % 16
        masked := head[1] >= 128
        n := head[1] % 128
        if n == 126:
            b := _n.to_bytes(self.conn.read_exact(2, timeout))
            n = b[0] * 256 + b[1]
        elif n == 127:
            b := _n.to_bytes(self.conn.read_exact(8, timeout))
            if b[0] >= 128:
                self._protocol_error("longueur de trame invalide (bit de poids fort)")
            n = 0
            for x in b:
                n = n * 256 + x
        if opcode >= 8:
            if not fin:
                self._protocol_error("trame de contrôle fragmentée")
            if n > 125:
                self._protocol_error("trame de contrôle de plus de 125 octets")
        elif opcode > 2:
            self._protocol_error("opcode réservé " + str(opcode))
        if self.is_client and masked:
            self._protocol_error("trame masquée reçue du serveur")
        if not self.is_client and not masked:
            self._protocol_error("trame non masquée reçue du client")
        if n > self.max_message:
            self._close_with(CLOSE_TOO_BIG, "message trop grand")
            _fail("websocket : trame de " + str(n) + " octets, au-delà de max_message (" + str(self.max_message) + ")")
        key := null
        if masked:
            key = self.conn.read_exact(4, timeout)
        payload := ""
        if n > 0:
            payload = self.conn.read_exact(n, timeout)
        if masked:
            payload = _n.mask(payload, key)
        return [fin, opcode, payload]

    func _protocol_error(why):
        self._close_with(CLOSE_PROTOCOL, why)
        _fail("websocket : " + why)

    # Envoie une trame close (une fois) et marque la connexion comme terminée côté lecture.
    func _close_with(code, reason):
        if not self.close_sent:
            self.close_sent = true
            try:
                body := ""
                if code != null:
                    body = _n.from_bytes([code // 256, code % 256]) + reason
                self.conn.write(self._frame(OP_CLOSE, body, true), 2.0)
            catch e:
                ignored := e   # le pair est peut-être déjà parti
        self.closed = true

    # Prochain message (Message), ou null quand la connexion est fermée (close_code / close_reason renseignés).
    # Les ping reçoivent un pong ; les pong sont ignorés. timeout : délai d'INACTIVITÉ.
    func receive(timeout=null):
        if self.closed:
            return null
        t := self._t(timeout)
        while true:
            f := null
            try:
                f = self._read_frame(t)
            catch e:
                if e.type == "NetworkError" and not self.closed:
                    self.closed = true
                    self.close_code = CLOSE_ABNORMAL
                    return null
                raise(e)
            fin := f[0]
            op := f[1]
            data := f[2]
            if op == OP_PING:
                self.pings += 1
                try:
                    self._send_frame(OP_PONG, data, true, t)
                catch e:
                    ignored := e
                continue
            if op == OP_PONG:
                continue
            if op == OP_CLOSE:
                self._on_close(data)
                return null
            if op == OP_CONTINUATION:
                if self.pending_kind == null:
                    self._protocol_error("trame de continuation sans message en cours")
                self.pending_data = self.pending_data + data
                if _n.blen(self.pending_data) > self.max_message:
                    self._close_with(CLOSE_TOO_BIG, "message trop grand")
                    _fail("websocket : message au-delà de max_message (" + str(self.max_message) + ")")
                if fin:
                    m := self._finish(self.pending_kind, self.pending_data)
                    self.pending_kind = null
                    self.pending_data = ""
                    if m != null:
                        return m
                continue
            # texte ou binaire : début d'un message
            if self.pending_kind != null:
                self._protocol_error("nouveau message au milieu d'un message fragmenté")
            kind := "text"
            if op == OP_BINARY:
                kind = "binary"
            if fin:
                m := self._finish(kind, data)
                if m != null:
                    return m
            else:
                self.pending_kind = kind
                self.pending_data = data

    func _finish(kind, data):
        if kind == "text" and not _n.utf8_valid(data):
            self._close_with(CLOSE_BAD_DATA, "texte non UTF-8")
            _fail("websocket : message texte qui n'est pas de l'UTF-8 valide")
        return Message(kind, data)

    func _on_close(data):
        n := _n.blen(data)
        code := CLOSE_NO_STATUS
        reason := ""
        if n == 1:
            self._close_with(CLOSE_PROTOCOL, "corps de fermeture invalide")
            _fail("websocket : trame close d'un seul octet")
        if n >= 2:
            b := _n.to_bytes(_n.bslice(data, 0, 2))
            code = b[0] * 256 + b[1]
            reason = _n.bslice(data, 2, n)
            if not valid_close_code(code):
                self._close_with(CLOSE_PROTOCOL, "code de fermeture invalide")
                _fail("websocket : code de fermeture invalide " + str(code))
            if not _n.utf8_valid(reason):
                self._close_with(CLOSE_PROTOCOL, "motif non UTF-8")
                _fail("websocket : motif de fermeture non UTF-8")
        self.close_code = code
        self.close_reason = reason
        # on répond en renvoyant le même code (RFC 6455 §5.5.1), puis la connexion est finie
        if code == CLOSE_NO_STATUS:
            self._close_with(null, "")
        else:
            self._close_with(code, "")
        self.conn.close()

    # Ferme proprement : trame close, attente de celle du pair (au plus timeout secondes, les messages encore en
    # route sont écartés), puis coupure de la connexion.
    func close(code=CLOSE_NORMAL, reason="", timeout=5.0):
        if self.conn.is_closed():
            self.closed = true
            return
        if code != null and not valid_close_code(code):
            raise("ArgumentError", "websocket.close : code de fermeture invalide " + str(code))
        if _n.blen(reason) > 123:
            raise("ArgumentError", "websocket.close : motif de 123 octets au plus")
        if not self.close_sent:
            self._close_with(code, reason)
            self.closed = false     # on lit encore la réponse du pair
            try:
                while self.close_code == null:
                    f := self._read_frame(timeout)
                    if f[1] == OP_CLOSE:
                        n := _n.blen(f[2])
                        self.close_code = CLOSE_NO_STATUS
                        if n >= 2:
                            b := _n.to_bytes(_n.bslice(f[2], 0, 2))
                            self.close_code = b[0] * 256 + b[1]
                            self.close_reason = _n.bslice(f[2], 2, n)
            catch e:
                ignored := e    # délai, coupure, trame invalide : on coupe de toute façon
        self.closed = true
        self.conn.close()

    func is_closed():
        return self.closed

# ------------------------------------------------------------------- client

class WsUrl:
    func init(secure, host, port, target, http_url):
        self.secure = secure
        self.host = host
        self.port = port
        self.target = target
        self.http_url = http_url

# Analyse ws://hôte[:port]/chemin[?requête] ou wss://... (le fragment est ignoré).
func parse_url(url):
    if type(url) != "str":
        raise("TypeError", "websocket.parse_url : str attendue (obtenu '" + type(url) + "')")
    lower := _s.lower(url)
    http_form := ""
    secure := false
    if _s.starts_with(lower, "wss://"):
        secure = true
        http_form = "https://" + _s.substring(url, 6, len(url))
    elif _s.starts_with(lower, "ws://"):
        http_form = "http://" + _s.substring(url, 5, len(url))
    else:
        _fail("websocket : URL ws:// ou wss:// attendue (« " + url + " »)")
    u := null
    try:
        u = _http.parse_url(http_form)
    catch e:
        _fail("websocket : " + e.message)
    return WsUrl(secure, u.host, u.port, u.target(), u)

# Connexion à une URL ws:// / wss://. headers : en-têtes supplémentaires de la requête (dict) ; protocols : liste
# des sous-protocoles proposés (le choix du serveur est dans .subprotocol) ; origin : en-tête Origin ; verify,
# ca_file : voir network.tls.connect (wss).
func connect(url, headers=null, protocols=null, timeout=10.0, max_message=DEFAULT_MAX_MESSAGE, origin=null, verify=true, ca_file=null):
    u := parse_url(url)
    conn := null
    if u.secure:
        conn = _tls.connect(u.host, u.port, timeout, verify, ca_file, ["http/1.1"])
    else:
        conn = _tcp.connect(u.host, u.port, timeout)
    try:
        key := _new_key()
        authority := u.http_url.authority()
        req := "GET " + u.target + " HTTP/1.1\r\nHost: " + authority + "\r\nUpgrade: websocket\r\nConnection: Upgrade\r\n"
        req += "Sec-WebSocket-Key: " + key + "\r\nSec-WebSocket-Version: 13\r\n"
        if origin != null:
            req += "Origin: " + origin + "\r\n"
        if protocols != null and len(protocols) > 0:
            req += "Sec-WebSocket-Protocol: " + _s.join(", ", protocols) + "\r\n"
        if headers != null:
            for k in headers:
                low := _s.lower(k)
                if low == "host" or low == "upgrade" or low == "connection" or _s.starts_with(low, "sec-websocket-"):
                    raise("ArgumentError", "websocket.connect : l'en-tête '" + k + "' est géré par le module")
                req += k + ": " + str(headers[k]) + "\r\n"
        conn.write(req + "\r\n", timeout)
        status := conn.read_line(timeout, HEADER_LIMIT)
        if status == null:
            _fail("websocket : le serveur a fermé la connexion sans répondre")
        parts := _s.split(status, " ")
        if len(parts) < 2 or not _s.starts_with(parts[0], "HTTP/"):
            _fail("websocket : ligne de statut invalide « " + status + " »")
        code := to_int(parts[1])
        hdrs := _read_headers(conn, timeout)
        if code != 101:
            _fail("websocket : poignée de main refusée, statut " + parts[1] + " (" + u.target + ")")
        if not _has_token(hdrs.get("upgrade"), "websocket"):
            _fail("websocket : réponse sans « Upgrade: websocket »")
        if not _has_token(hdrs.get("connection"), "upgrade"):
            _fail("websocket : réponse sans « Connection: Upgrade »")
        if hdrs.get("sec-websocket-accept") == null or _s.trim(hdrs.get("sec-websocket-accept")) != accept_key(key):
            _fail("websocket : Sec-WebSocket-Accept invalide (le serveur ne parle pas WebSocket ?)")
        if hdrs.has("sec-websocket-extensions"):
            _fail("websocket : extension non demandée imposée par le serveur (" + hdrs.get("sec-websocket-extensions") + ")")
        chosen := hdrs.get("sec-websocket-protocol")
        if chosen != null:
            chosen = _s.trim(chosen)
            ok := false
            if protocols != null:
                for p in protocols:
                    if p == chosen:
                        ok = true
            if not ok:
                _fail("websocket : sous-protocole « " + chosen + " » non proposé")
        return WebSocket(conn, true, max_message, chosen, url)
    catch e:
        conn.close()
        raise(e)

# En-têtes d'une requête ou d'une réponse jusqu'à la ligne vide (noms en minuscules ; répétés : joints par « , »).
func _read_headers(conn, timeout):
    h := _http.Headers()
    count := 0
    while true:
        line := conn.read_line(timeout, HEADER_LIMIT)
        if line == null:
            _fail("websocket : en-têtes interrompus")
        if line == "":
            return h
        count += 1
        if count > 200:
            _fail("websocket : trop d'en-têtes")
        i := _s.find(line, ":")
        if i <= 0:
            _fail("websocket : en-tête invalide « " + line + " »")
        h.add(_s.trim(_s.substring(line, 0, i)), _s.trim(_s.substring(line, i + 1, len(line))))

# ------------------------------------------------------------------- serveur

# Accepte la mise à niveau d'une connexion TCP/TLS déjà acceptée : lit la requête, valide, répond 101 (ou 400 / 426
# / 404 avec un message) et renvoie le WebSocket. protocols : sous-protocoles acceptés par ordre de préférence ;
# path : si donné, seul ce chemin est servi ; origins : liste d'origines autorisées (null : toutes).
func accept_connection(conn, protocols=null, path=null, origins=null, max_message=DEFAULT_MAX_MESSAGE, timeout=10.0):
    line := conn.read_line(timeout, HEADER_LIMIT)
    if line == null or line == "":
        _fail("websocket : connexion fermée avant la requête")
    parts := _s.split(line, " ")
    if len(parts) != 3 or not _s.starts_with(parts[2], "HTTP/"):
        _reject(conn, 400, "requête invalide")
        _fail("websocket : ligne de requête invalide « " + line + " »")
    hdrs := _read_headers(conn, timeout)
    if _s.upper(parts[0]) != "GET":
        _reject(conn, 405, "GET attendu")
        _fail("websocket : méthode " + parts[0] + " au lieu de GET")
    if not _has_token(hdrs.get("upgrade"), "websocket") or not _has_token(hdrs.get("connection"), "upgrade"):
        _reject(conn, 426, "mise à niveau WebSocket requise")
        _fail("websocket : requête sans Upgrade: websocket")
    if hdrs.get("sec-websocket-version") == null or _s.trim(hdrs.get("sec-websocket-version")) != "13":
        _reject(conn, 426, "version WebSocket 13 requise", "Sec-WebSocket-Version: 13\r\n")
        _fail("websocket : version non prise en charge")
    key := hdrs.get("sec-websocket-key")
    if key == null or not _valid_key(_s.trim(key)):
        _reject(conn, 400, "Sec-WebSocket-Key invalide")
        _fail("websocket : Sec-WebSocket-Key absente ou invalide")
    target := parts[1]
    if path != null:
        q := _s.find(target, "?")
        only := target
        if q >= 0:
            only = _s.substring(target, 0, q)
        if only != path:
            _reject(conn, 404, "chemin inconnu")
            _fail("websocket : chemin " + only + " non servi")
    if origins != null:
        o := hdrs.get("origin")
        allowed := false
        for x in origins:
            if x == o:
                allowed = true
        if not allowed:
            _reject(conn, 403, "origine refusée")
            _fail("websocket : origine refusée (" + str(o) + ")")
    chosen := null
    offered := hdrs.get("sec-websocket-protocol")
    if protocols != null and offered != null:
        wanted := []
        for p in _s.split(offered, ","):
            append(wanted, _s.trim(p))
        for mine in protocols:
            if chosen == null:
                for w in wanted:
                    if w == mine:
                        chosen = mine
    resp := "HTTP/1.1 101 Switching Protocols\r\nUpgrade: websocket\r\nConnection: Upgrade\r\nSec-WebSocket-Accept: " + accept_key(_s.trim(key)) + "\r\n"
    if chosen != null:
        resp += "Sec-WebSocket-Protocol: " + chosen + "\r\n"
    conn.write(resp + "\r\n", timeout)
    return WebSocket(conn, false, max_message, chosen, target)

# Clé de poignée de main : 16 octets en base64.
func _valid_key(k):
    try:
        return len(_c.base64_decode(k)) == 16
    catch e:
        return false

func _reject(conn, status, message, extra=""):
    body := message + "\n"
    try:
        conn.write("HTTP/1.1 " + str(status) + " " + _http.reason_phrase(status) + "\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: " + str(_n.blen(body)) + "\r\nConnection: close\r\n" + extra + "\r\n" + body, 2.0)
    catch e:
        ignored := e

class Server:
    # Serveur WebSocket en écoute sur host:port (port 0 : choisi par le système). cert_file + key_file : wss://.
    func init(host="127.0.0.1", port=0, protocols=null, path=null, origins=null, max_message=DEFAULT_MAX_MESSAGE, cert_file=null, key_file=null, handshake_timeout=10.0):
        self.protocols = protocols
        self.path = path
        self.origins = origins
        self.max_message = max_message
        self.handshake_timeout = handshake_timeout
        self.secure = cert_file != null
        if self.secure:
            self.listener = _tls.listen(host, port, cert_file, key_file, ["http/1.1"], 128, true, handshake_timeout)
        else:
            self.listener = _tcp.listen(host, port)
        self.rejected = 0    # poignées de main refusées (HTTP ou TLS)

    func port():
        return self.listener.port()

    func url(path="/"):
        a := self.listener.address()
        scheme := "ws"
        if self.secure:
            scheme = "wss"
        return scheme + "://" + a[0] + ":" + str(a[1]) + path

    # Prochaine connexion WebSocket établie. Une requête qui n'est pas une mise à niveau valide reçoit sa réponse
    # d'erreur HTTP et lève WebSocketError ; le serveur peut appeler accept() de nouveau.
    func accept(timeout=null):
        conn := self.listener.accept(timeout)
        try:
            return accept_connection(conn, self.protocols, self.path, self.origins, self.max_message, self.handshake_timeout)
        catch e:
            self.rejected += 1
            conn.close()
            raise(e)

    # Sert les connexions une par une : handler(websocket) ; une poignée de main refusée est ignorée. S'arrête
    # après max_connections connexions établies (null : jamais).
    func serve(handler, max_connections=null, on_error=null):
        served := 0
        while max_connections == null or served < max_connections:
            ws := null
            try:
                ws = self.accept()
            catch e:
                if e.type == "WebSocketError" or e.type == "TlsError" or e.type == "NetworkError" or e.type == "TimeoutError":
                    continue
                raise(e)
            try:
                handler(ws)
            catch e:
                if on_error == null:
                    ws.close()
                    raise(e)
                on_error(e, ws)
            ws.close()
            served += 1
        return served

    func close():
        self.listener.close()
