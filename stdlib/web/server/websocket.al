# ALEX STANDARD LIBRARY — web.server.websocket
#
# WebSocket (RFC 6455) dans web.server, sans bloquer la boucle : après la poignée de main, la connexion quitte le
# HTTP et passe à une session async ; les lectures cèdent la main tant que rien n'arrive, si bien que des
# milliers de sessions et les requêtes HTTP partagent le même fil. Exige la boucle async du serveur
# (serve_forever_async, serve_async).
#
#   use web.server as server
#
#   async func echo(req, ws):
#       while true:
#           m := await ws.receive()           # Message (network.websocket), ou null à la fermeture
#           if m == null:
#               return
#           await ws.send_text("écho : " + m.text())
#
#   app := server.App()
#   app.websocket("/ws", echo)                # options : protocols, max_message, origins
#   await server.serve_async(app, "127.0.0.1", 8080)
#
# Le gestionnaire reçoit la requête de la poignée de main (chemin, paramètres de route, cookies, en-têtes) et la
# session ; à son retour la session est fermée (1000), sur exception elle l'est avec 1011. À l'arrêt du serveur,
# les sessions ouvertes reçoivent 1001 (« going away »).
#
# Garanties reprises de network.websocket : trames client masquées exigées, bits RSV refusés, contrôles <= 125
# octets non fragmentés, messages fragmentés réassemblés, texte UTF-8 vérifié (1007), taille maximale (1009),
# ping répondu par pong.

from core use len, type
from collections use append
use asyncio as _aio
use _native_net as _n
use string as _s
use time as _time
use network.websocket as _ws
use network.http_headers as _hh
use web.http.response as _response

const MIN_POLL := 0.001
const MAX_POLL := 0.02

# Réponse à une demande de mise à niveau : 101 (session confiée au serveur), ou 400 / 403 / 426.
func upgrade(req, handler, protocols=null, max_message=_ws.DEFAULT_MAX_MESSAGE, origins=null):
    up := _s.lower(req.headers.get("upgrade", "")) == "websocket" and _s.contains(_s.lower(req.headers.get("connection", "")), "upgrade")
    if not up or req.method != "GET":
        r := _response.error(426, "mise à niveau WebSocket attendue")
        r.headers.set("Upgrade", "websocket")
        return r
    key := req.headers.get("sec-websocket-key")
    if key == null or req.headers.get("sec-websocket-version") != "13":
        r := _response.error(400, "poignée de main WebSocket invalide")
        r.headers.set("Sec-WebSocket-Version", "13")
        return r
    if origins != null:
        o := req.headers.get("origin")
        if not (o in origins):
            return _response.error(403, "origine refusée")
    chosen := null
    if protocols != null and req.headers.has("sec-websocket-protocol"):
        for p in _hh.parse_list(req.headers.get("sec-websocket-protocol", "", true)):
            if chosen == null and p in protocols:
                chosen = p
    r := _response.Response(101, "")
    r.headers.set("Upgrade", "websocket")
    r.headers.set("Connection", "Upgrade")
    r.headers.set("Sec-WebSocket-Accept", _ws.accept_key(key))
    if chosen != null:
        r.headers.set("Sec-WebSocket-Protocol", chosen)
    req.state["websocket"] = {"handler": handler, "max_message": max_message, "protocol": chosen}
    return r

# Session côté serveur. conn : web.server.connection.ServerConnection détachée du HTTP ; initial : octets déjà
# reçus après la poignée de main.
class ServerWebSocket:
    # server : le web.server.Server qui réveille la session quand son socket devient lisible (sans lui, la
    # session sonde son socket : intervalle de 1 à 20 ms).
    func init(conn, request, max_message=_ws.DEFAULT_MAX_MESSAGE, subprotocol=null, initial="", server=null):
        self.conn = conn
        self.server = server
        self.wake = null                 # futur résolu par le serveur quand le socket devient lisible
        self.request = request
        self.max_message = max_message
        self.subprotocol = subprotocol
        self.buffer = initial
        self.closed = false
        self.close_sent = false
        self.close_code = null
        self.close_reason = ""
        self.pings = 0
        self.messages_in = 0
        self.messages_out = 0
        self._encoder = _ws.WebSocket(null, false, max_message)   # encodage des trames (côté serveur : non masquées)
        self._pending_kind = null
        self._pending_data = ""
        self._poll_delay = MIN_POLL

    func is_closed():
        return self.closed

    # ------------------------------------------------------------ envoi

    # Les envois écrivent tout de suite (délai d'écriture de 10 s) et rendent un futur déjà terminé : `await
    # ws.send_text(...)` ne coûte aucun tour de boucle.
    func send_text(text):
        self._send(_ws.OP_TEXT, text)
        self.messages_out += 1
        return _done()

    func send_binary(data):
        self._send(_ws.OP_BINARY, data)
        self.messages_out += 1
        return _done()

    func ping(data=""):
        self._send(_ws.OP_PING, data)
        return _done()

    func _send(opcode, payload):
        if self.closed or self.close_sent:
            raise("WebSocketError", "websocket : envoi sur une session fermée")
        self.conn.send(self._encoder._frame(opcode, payload, true), 10.0)

    # Ferme la session : trame close, attente brève de celle du pair, puis coupure.
    async func close(code=_ws.CLOSE_NORMAL, reason="", timeout=2.0):
        if self.closed and self.close_sent:
            return
        self._send_close(code, reason)
        deadline := _time.monotonic() + timeout
        while not self.closed and _time.monotonic() < deadline:
            try:
                f := self._parse_frame()
                if f != null:
                    if f[1] == _ws.OP_CLOSE:
                        break
                    continue
                st := self._fill()
                if st == "eof":
                    break
                if st == "empty":
                    await self._wait(deadline - _time.monotonic())
                    self.wake = null
            catch e:
                break
        self.closed = true
        self.conn.close()

    func _send_close(code, reason):
        if self.close_sent:
            return
        self.close_sent = true
        try:
            body := ""
            if code != null:
                body = _n.from_bytes([code // 256, code % 256]) + reason
            self.conn.send(self._encoder._frame(_ws.OP_CLOSE, body, true), 2.0)
        catch e:
            ignored := e

    # ------------------------------------------------------------ réception

    # Prochain message (network.websocket.Message), ou null quand la session est fermée. timeout : délai
    # d'inactivité (null : sans limite) ; dépassé, TimeoutError (la session reste ouverte).
    async func receive(timeout=null):
        if self.closed:
            return null
        deadline := _time.monotonic() + timeout if timeout != null else null
        while true:
            f := self._parse_frame()
            if f == null:
                st := self._fill()
                if st == "eof":
                    self.closed = true
                    if self.close_code == null:
                        self.close_code = _ws.CLOSE_ABNORMAL
                    self.conn.close()
                    return null
                if st == "empty":
                    now := _time.monotonic()
                    if deadline != null and now >= deadline:
                        raise("TimeoutError", "websocket : aucun message dans le délai")
                    await self._wait(deadline - now if deadline != null else null)
                    self.wake = null
                else:
                    self._poll_delay = MIN_POLL
                continue
            m := self._handle_frame(f)
            if m == "closed":
                return null
            if m != null:
                return m

    # Traite une trame complète : Message à rendre, null (rien à rendre : contrôle, fragment) ou "closed".
    func _handle_frame(f):
        fin := f[0]
        op := f[1]
        data := f[2]
        if op == _ws.OP_PING:
            self.pings += 1
            try:
                self.conn.send(self._encoder._frame(_ws.OP_PONG, data, true), 2.0)
            catch e:
                ignored := e
            return null
        if op == _ws.OP_PONG:
            return null
        if op == _ws.OP_CLOSE:
            self._on_close(data)
            return "closed"
        if op == _ws.OP_CONTINUATION:
            if self._pending_kind == null:
                self._protocol_error("trame de continuation sans message en cours")
            self._pending_data = self._pending_data + data
            if _n.blen(self._pending_data) > self.max_message:
                self._fail_close(_ws.CLOSE_TOO_BIG, "message trop grand")
            if fin:
                m := self._finish(self._pending_kind, self._pending_data)
                self._pending_kind = null
                self._pending_data = ""
                return m
            return null
        if self._pending_kind != null:
            self._protocol_error("nouveau message au milieu d'un message fragmenté")
        kind := "binary" if op == _ws.OP_BINARY else "text"
        if fin:
            return self._finish(kind, data)
        self._pending_kind = kind
        self._pending_data = data
        return null

    func _finish(kind, data):
        if kind == "text" and not _n.utf8_valid(data):
            self._fail_close(_ws.CLOSE_BAD_DATA, "texte non UTF-8")
        self.messages_in += 1
        return _ws.Message(kind, data)

    func _on_close(data):
        n := _n.blen(data)
        code := _ws.CLOSE_NO_STATUS
        reason := ""
        if n >= 2:
            b := _n.to_bytes(_n.bslice(data, 0, 2))
            code = b[0] * 256 + b[1]
            reason = _n.bslice(data, 2, n)
        self.close_code = code
        self.close_reason = reason
        self._send_close(code if n >= 2 and _ws.valid_close_code(code) else _ws.CLOSE_NORMAL, "")
        self.closed = true
        self.conn.close()

    func _protocol_error(why):
        self._fail_close(_ws.CLOSE_PROTOCOL, why)

    func _fail_close(code, why):
        self._send_close(code, why)
        self.closed = true
        self.conn.close()
        raise("WebSocketError", "websocket : " + why)

    # Lit ce qui est disponible sans attendre : "data" (octets ajoutés), "empty" (rien pour l'instant), "eof".
    func _fill():
        data := null
        try:
            data = self.conn.socket.try_recv(65536)
        catch e:
            return "eof"
        if data == "":
            return "eof"
        if data == null:
            return "empty"
        self.buffer = self.buffer + data
        return "data"

    # Trame complète [fin, opcode, charge utile] retirée du tampon, ou null si elle n'est pas encore arrivée en
    # entier (le tampon est alors laissé intact). Synchrone : aucune tâche créée.
    func _parse_frame():
        total := _n.blen(self.buffer)
        if total < 2:
            return null
        h := _n.to_bytes(_n.bslice(self.buffer, 0, 2))
        fin := h[0] >= 128
        if h[0] % 128 >= 16:
            self._protocol_error("bits RSV non nuls (aucune extension négociée)")
        opcode := h[0] % 16
        masked := h[1] >= 128
        n := h[1] % 128
        pos := 2
        if n == 126:
            if total < 4:
                return null
            bb := _n.to_bytes(_n.bslice(self.buffer, 2, 4))
            n = bb[0] * 256 + bb[1]
            pos = 4
        elif n == 127:
            if total < 10:
                return null
            bb := _n.to_bytes(_n.bslice(self.buffer, 2, 10))
            if bb[0] >= 128:
                self._protocol_error("longueur de trame invalide")
            n = 0
            for x in bb:
                n = n * 256 + x
            pos = 10
        if opcode >= 8:
            if not fin:
                self._protocol_error("trame de contrôle fragmentée")
            if n > 125:
                self._protocol_error("trame de contrôle de plus de 125 octets")
        elif opcode > 2:
            self._protocol_error("opcode réservé " + str(opcode))
        if not masked:
            self._protocol_error("trame non masquée reçue du client")
        if n > self.max_message:
            self._fail_close(_ws.CLOSE_TOO_BIG, "message trop grand")
        if total < pos + 4 + n:
            return null
        key := _n.bslice(self.buffer, pos, pos + 4)
        payload := _n.mask(_n.bslice(self.buffer, pos + 4, pos + 4 + n), key) if n > 0 else ""
        self.buffer = _n.bslice(self.buffer, pos + 4 + n, total)
        return [fin, opcode, payload]

    # Futur à attendre pour avoir des données : réveil par le serveur quand le socket devient lisible, sinon
    # sondage (1 à 20 ms) ; terminé au plus tard après remaining secondes (null : sans limite). Ce n'est pas une
    # tâche : l'attendre ne coûte aucun tour de boucle de plus. Remettre self.wake à null après l'attente.
    func _wait(remaining):
        if self.server == null:
            d := self._poll_delay
            self._poll_delay = d * 2 if d * 2 < MAX_POLL else MAX_POLL
            if remaining != null and remaining < d:
                d = remaining if remaining > 0 else 0
            return _aio.sleep(d)
        f := _aio.future()
        self.wake = f
        if remaining == null:
            return f
        return _aio.race([f, _aio.sleep(remaining if remaining > 0 else 0)])

    # Appelé par le serveur : le socket est lisible (ou la session doit se réveiller pour se terminer).
    func notify():
        f := self.wake
        if f != null:
            self.wake = null
            _aio.resolve(f, true)

    # Vrai si la session travaille (pas en attente de son socket) : la boucle du serveur lui laisse la main.
    func is_busy():
        return not self.closed and self.wake == null

# Futur déjà terminé (await immédiat).
func _done(value=null):
    f := _aio.future()
    _aio.resolve(f, value)
    return f
