# ALEX STANDARD LIBRARY — web.server.connection
#
# ServerConnection : une connexion acceptée par le serveur. Elle lit SANS BLOQUER ce qui est disponible, le donne
# à l'analyseur incrémental (web.http.protocol_parser.RequestParser), garde en file les requêtes complètes
# (pipelining), et suit son état pour les délais : idle (entre deux requêtes), header (requête commencée),
# body (en-têtes reçus, corps en cours), closed.
#
#   use web.server.connection as sc
#   c := sc.ServerConnection(sock, ("127.0.0.1", 50312), false, limits)
#   n := c.read_available()          # octets lus (0 : rien ; -1 : fin du flux)
#   r := c.next_request()            # web.http.request.Request, ou null
#   c.send(octets, 30.0)
#   c.close()
#
# Erreurs : celles de l'analyseur (HttpParseError, HttpLimitError...) sont levées par read_available ; le serveur
# les traduit en réponse 4xx / 5xx.

from core use len, type
from collections use append
use web.server.http2 as _h2
use string as _s
use time as _time
use web.http.protocol_parser as _pp

_ids := [0]

class ServerConnection:
    func init(sock, address, secure=false, limits=null, local_address=null):
        _ids[0] = _ids[0] + 1
        self.id = _ids[0]
        self.socket = sock               # network.socket.Socket ou network.tls.TlsSocket
        self.address = address           # (hôte, port) du client
        self.local_address = local_address
        self.secure = secure
        self.parser = _pp.RequestParser(limits.parser_limits() if limits != null else null)
        self.queue = []                  # requêtes complètes en attente de traitement
        now := _time.monotonic()
        self.opened_at = now
        self.last_activity = now
        self.request_started_at = null   # premier octet de la requête en cours
        self.head_completed_at = null    # fin des en-têtes de la requête en cours
        self.requests_served = 0
        self.bytes_in = 0
        self.bytes_out = 0
        self.closing = false             # fermer après la réponse en cours
        self.closed = false
        self.continue_sent = false       # « 100 Continue » envoyé pour la requête en cours
        self.eof = false
        self.in_flight = null            # [requête, futur, début] : réponse d'un gestionnaire async attendue
        self.outgoing = null             # envoi de fichier en cours, morceau par morceau (web.server.response_writer)
        self.h2c = false                 # vrai : une préface HTTP/2 en début de connexion bascule en HTTP/2
        self.h2_initial = null           # octets reçus quand la préface HTTP/2 a été reconnue

    # Vrai si la connexion attend la réponse d'un gestionnaire async (ses requêtes suivantes patientent, pour
    # que les réponses partent dans l'ordre des requêtes).
    func is_waiting():
        return self.in_flight != null or self.outgoing != null

    # Socket brut (pour l'attente d'événements) : le socket TCP sous-jacent d'une session TLS.
    func raw_socket():
        try:
            return self.socket.socket if self.secure else self.socket
        catch e:
            return self.socket

    # Données TLS déjà déchiffrées en attente (invisibles pour l'attente sur le socket brut).
    func has_buffered_input():
        if not self.secure:
            return false
        try:
            return self.socket.pending() > 0
        catch e:
            return false

    # Phase : idle, header, body ou closed.
    func phase():
        if self.closed:
            return "closed"
        if self.parser.in_body():
            return "body"
        if self.request_started_at != null:
            return "header"
        return "idle"

    # Lit ce qui est disponible sans attendre ; renvoie le nombre d'octets lus (0 : rien ; -1 : fin du flux).
    func read_available(max_bytes=65536):
        if self.closed or self.eof:
            return -1
        total := 0
        while total < max_bytes * 4:
            data := self.socket.try_recv(max_bytes)
            if data == null:
                break
            if data == "":
                self.eof = true
                if total == 0:
                    return -1
                break
            n := _s.byte_len(data)
            if self.h2c and self.bytes_in == 0 and _h2.looks_like_preface(data):
                self.h2_initial = data
                self.bytes_in += n
                return n
            total += n
            self.bytes_in += n
            self.last_activity = _time.monotonic()
            if self.request_started_at == null:
                self.request_started_at = self.last_activity
            was_in_body := self.parser.in_body()
            for r in self.parser.feed(data):
                r.remote_address = self.address
                r.local_address = self.local_address
                r.secure = self.secure
                r.received_at = _time.time()
                append(self.queue, r)
            if self.parser.in_body() and not was_in_body:
                self.head_completed_at = _time.monotonic()
            if self.parser.is_idle() or (self.parser.state == "start" and self.parser.pending() == 0):
                self.request_started_at = null
                self.head_completed_at = null
            elif self.parser.state == "start" and self.parser.pending() > 0:
                self.request_started_at = self.last_activity
        return total

    # Prochaine requête complète, ou null.
    func next_request():
        if len(self.queue) == 0:
            return null
        r := self.queue[0]
        self.queue = self.queue[1:len(self.queue)]
        self.continue_sent = false
        return r

    func has_request():
        return len(self.queue) > 0

    # « Expect: 100-continue » : les en-têtes sont reçus et le corps est attendu.
    func wants_continue():
        return self.parser.continue_pending and not self.continue_sent

    func send(data, timeout=null):
        if self.closed:
            return 0
        n := self.socket.send(data, timeout)
        self.bytes_out += n
        self.last_activity = _time.monotonic()
        return n

    func close():
        if self.closed:
            return
        self.closed = true
        try:
            self.socket.close()
        catch e:
            ignored := e

    func idle_time():
        return _time.monotonic() - self.last_activity

    func age():
        return _time.monotonic() - self.opened_at

    func __str__():
        return "<ServerConnection #" + str(self.id) + " " + str(self.address[0]) + ":" + str(self.address[1]) + " " + self.phase() + ">"
