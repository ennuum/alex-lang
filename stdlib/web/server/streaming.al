# ALEX STANDARD LIBRARY — web.server.streaming
#
# Réponses en flux sans bloquer le serveur : un producteur async écrit des morceaux quand il veut (journal en
# direct, export long, progression), et les Server-Sent Events (EventSource des navigateurs). Exige la boucle
# async du serveur (serve_forever_async, serve_async).
#
#   use web.server as server
#   use web.server.streaming as st
#
#   async func horloge(req, flux):
#       n := 0
#       while not flux.closed:
#           await flux.send({"n": n}, "tick")        # événement « tick », données JSON
#           await aio.sleep(1.0)
#           n += 1
#
#   app.get("/evenements", st.sse(horloge))
#   app.get("/export.csv", st.stream(produire_csv, "text/csv; charset=utf-8"))
#
# Le producteur reçoit la requête et le flux : write(morceau) (flux brut), send(données, événement, id, retry) et
# comment(texte) (SSE). Les écritures partent tout de suite et rendent un futur déjà terminé (await sans coût).
# flux.closed devient vrai quand le client part (détecté à l'écriture et à chaque tour du serveur) ou à l'arrêt du
# serveur : le producteur doit alors s'arrêter. Une exception du producteur termine le flux (consignée dans
# srv.errors). Le flux se termine au retour du producteur ; la connexion est alors fermée.
#
# SSE : flux.last_event_id = en-tête Last-Event-ID envoyé par le navigateur à la reconnexion (reprise) ;
# keepalive : commentaire envoyé si rien n'est parti depuis `keepalive` secondes (mandataires, délais).

from core use len, type
from collections use append
use asyncio as _aio
use string as _s
use time as _time
use json as _json
use web.http.response as _response
use web.http.message_body as _mb

# Gestionnaire de route qui sert un flux brut produit par producer(req, flux).
func stream(producer, content_type="application/octet-stream"):
    return (req) => _begin(req, producer, content_type, false, null)

# Gestionnaire de route qui sert des Server-Sent Events produits par producer(req, flux). keepalive : secondes
# entre deux commentaires de maintien quand rien n'est envoyé (null : jamais).
func sse(producer, keepalive=15.0):
    return (req) => _begin(req, producer, "text/event-stream; charset=utf-8", true, keepalive)

func _begin(req, producer, content_type, is_sse, keepalive):
    r := _response.Response(200, "")
    r.headers.set("Content-Type", content_type)
    r.headers.set("Cache-Control", "no-cache")
    r.headers.set("X-Accel-Buffering", "no")      # nginx : ne pas mettre le flux en tampon
    req.state["stream"] = {"producer": producer, "sse": is_sse, "keepalive": keepalive}
    return r

class Stream:
    # conn : web.server.connection.ServerConnection détachée du HTTP ; chunked : codage HTTP/1.1 des morceaux.
    func init(conn, request, chunked=true, is_sse=false, keepalive=null):
        self.conn = conn
        self.request = request
        self.chunked = chunked
        self.is_sse = is_sse
        self.keepalive = keepalive
        self.closed = false
        self.bytes_sent = 0
        self.chunks = 0
        self.last_write = _time.monotonic()
        self.last_event_id = request.headers.get("last-event-id") if request != null else null

    # Écrit un morceau (str d'octets) ; rend un futur déjà terminé. Sans effet si le flux est fermé.
    func write(data):
        if self.closed or data == null or data == "":
            return _done(not self.closed)
        frame := (_hex(_s.byte_len(data)) + "\r\n" + data + "\r\n") if self.chunked else data
        try:
            self.bytes_sent += self.conn.send(frame, 10.0)
            self.chunks += 1
            self.last_write = _time.monotonic()
        catch e:
            self.closed = true
        return _done(not self.closed)

    # Événement SSE. data : str (lignes multiples permises) ou valeur JSON ; event : nom (null : « message ») ;
    # id : identifiant (repris par Last-Event-ID) ; retry : délai de reconnexion conseillé (ms).
    func send(data, event=null, id=null, retry=null):
        text := data if type(data) == "str" else _json.stringify(data)
        out := ""
        if event != null:
            out += "event: " + _single_line(str(event)) + "\n"
        if id != null:
            out += "id: " + _single_line(str(id)) + "\n"
        if retry != null:
            out += "retry: " + str(retry) + "\n"
        for line in _s.split(_s.replace(text, "\r\n", "\n"), "\n"):
            out += "data: " + line + "\n"
        return self.write(out + "\n")

    # Commentaire SSE (ignoré par EventSource) : maintien de connexion.
    func comment(text=""):
        return self.write(": " + _single_line(text) + "\n\n")

    # Termine le flux (dernier morceau chunked) ; la connexion est fermée.
    func close():
        if self.closed:
            return
        self.closed = true
        if self.chunked:
            try:
                self.conn.send("0\r\n\r\n", 2.0)
            catch e:
                ignored := e
        self.conn.close()

    # Appelé par le serveur à chaque tour : client parti ? (lecture non bloquante : fin de flux) ; maintien SSE.
    func poll():
        if self.closed:
            return
        try:
            d := self.conn.socket.try_recv(4096)
            if d == "":
                self.closed = true
                self.conn.close()
                return
        catch e:
            self.closed = true
            self.conn.close()
            return
        if self.is_sse and self.keepalive != null and _time.monotonic() - self.last_write >= self.keepalive:
            self.comment("keepalive")

func _hex(n):
    digits := "0123456789abcdef"
    if n == 0:
        return "0"
    out := ""
    v := n
    while v > 0:
        out = digits[v % 16:v % 16 + 1] + out
        v = v // 16
    return out

func _single_line(s):
    return _s.replace(_s.replace(s, "\r", " "), "\n", " ")

func _done(value=null):
    f := _aio.future()
    _aio.resolve(f, value)
    return f
