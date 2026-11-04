# ALEX STANDARD LIBRARY — network.grpc_server
#
# Serveur gRPC sur HTTP/2 (network.grpc) : méthodes brutes (octets) ou services typés par un schéma Protocol
# Buffers (network.protobuf), quatre formes d'appel, métadonnées, délais, statuts, en clair (h2c) ou en TLS
# (ALPN h2). Plusieurs connexions sont multiplexées par une boucle d'événements ; les appels sont traités l'un
# après l'autre.
#
#   srv := Server("127.0.0.1", 50051)
#   srv.add_service(schéma, "salut.Saluer", {"Dire": dire, "Répéter": repeter})
#       dire(requête_dict, ctx) -> réponse_dict                                  (unaire)
#       repeter(requête_dict, ctx) -> list de réponses, ou ctx.send(...) en cours de route   (flux serveur)
#       flux client : handler(list de requêtes, ctx) ; bidirectionnel : handler(list, ctx) -> list
#   srv.add_method("/paquet.Service/Brut", (octets, ctx) => octets)             méthode sans schéma
#   srv.serve_forever() / srv.serve(n) / srv.stop()
#
# Contexte (ctx) : method, metadata (dict), peer, time_remaining(), set_trailing_metadata(dict),
# set_header_metadata(dict), abort(code, message), send(message) (flux serveur), is_cancelled().
#
# Réponses d'erreur : méthode inconnue -> UNIMPLEMENTED ; exception GrpcError du gestionnaire -> son statut ;
# autre exception -> UNKNOWN (message dans server.errors) ; délai du client dépassé -> DEADLINE_EXCEEDED.
#
# Exemple
#   use network.grpc_server as gs
#   use network.protobuf as pb
#   s := pb.parse_proto("syntax = \"proto3\"; package salut; message Q { string nom = 1; } message R { string message = 1; } service Saluer { rpc Dire (Q) returns (R); }")
#   srv := gs.Server("127.0.0.1", 50051)
#   srv.add_service(s, "salut.Saluer", {"Dire": (q, ctx) => {"message": "Bonjour " + q["nom"]}})
#   srv.serve_forever()

from core use len, type
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use network.socket as _sk
use network.tcp as _tcp
use network.tls as _tls
use network.grpc as _g
use network.compression as _z

class Context:
    func init(server, h2, stream, method, headers, peer):
        self.server = server
        self.h2 = h2
        self.stream = stream
        self.method = method                      # « /paquet.Service/Méthode »
        self.headers = headers                    # en-têtes HTTP/2 bruts [nom, valeur]
        self.metadata = _g.headers_to_metadata(headers)
        self.peer = peer                          # (hôte, port)
        self.trailing_metadata = {}
        self.header_metadata = {}
        self.headers_sent = false
        self.deadline = null
        t := _g.parse_timeout(_g.header_value(headers, "grpc-timeout"))
        if t != null:
            self.deadline = _time.monotonic() + t
        self.encoding = _g.header_value(headers, "grpc-encoding")
        self.sent = 0
        self.encoder = null                       # fonction de sérialisation (services typés)

    # Secondes restantes avant le délai du client (null : sans délai).
    func time_remaining():
        if self.deadline == null:
            return null
        r := self.deadline - _time.monotonic()
        if r < 0:
            return 0.0
        return r

    func is_cancelled():
        return self.stream.reset_code != null

    func set_trailing_metadata(md):
        for k in keys(md):
            self.trailing_metadata[k] = md[k]

    func set_header_metadata(md):
        if self.headers_sent:
            raise("ArgumentError", "grpc_server : en-têtes déjà envoyés")
        for k in keys(md):
            self.header_metadata[k] = md[k]

    # Termine l'appel avec un statut d'erreur.
    func abort(code, message=""):
        _g.fail(code, message)

    func _send_headers():
        if self.headers_sent:
            return
        hs := [[":status", "200"], ["content-type", "application/grpc"], ["grpc-accept-encoding", "gzip,identity"]]
        for h in _g.metadata_to_headers(self.header_metadata):
            append(hs, h)
        self.h2.send_headers(self.stream.id, hs, false)
        self.headers_sent = true

    # Envoie une réponse tout de suite (flux serveur / bidirectionnel) ; message : dict (service typé) ou octets.
    func send(message):
        if self.is_cancelled():
            _g.fail(_g.CANCELLED, "appel annulé par le client")
        data := message
        if self.encoder != null:
            data = self.encoder(message)
        self._send_headers()
        self.h2.send_data(self.stream.id, _g.frame_message(data), false, 30.0)
        self.sent += 1

class _Method:
    func init(path, handler, kind, decode, encode):
        self.path = path
        self.handler = handler
        self.kind = kind          # "unary", "server_streaming", "client_streaming", "bidi_streaming"
        self.decode = decode      # octets -> valeur (ou null : octets bruts)
        self.encode = encode      # valeur -> octets

class _Client:
    func init(h2, peer):
        self.h2 = h2
        self.peer = peer
        self.last_active = _time.monotonic()

class Server:
    func init(host="127.0.0.1", port=50051, cert_file=null, key_file=null, max_message=4194304, expose_errors=true, idle_timeout=300.0):
        self.listener = _tcp.listen(host, port)
        self.secure = cert_file != null
        self.cert_file = cert_file
        self.key_file = key_file
        self.max_message = max_message
        self.expose_errors = expose_errors
        self.idle_timeout = idle_timeout
        self.methods = {}
        self.clients = []
        self.running = false
        self.handled = 0
        self.errors = []
        self.rejected = 0

    func port():
        return self.listener.port()

    func address():
        a := self.listener.address()
        return _sk.format_address(a[0], a[1])

    # Méthode brute : handler(requête, ctx) ; requête et réponse(s) en octets (str brute).
    func add_method(path, handler, kind="unary", decode=null, encode=null):
        if not _s.starts_with(path, "/") or _s.count(path, "/") != 2:
            raise("ArgumentError", "grpc_server.add_method : chemin « /paquet.Service/Méthode » attendu")
        self.methods[path] = _Method(path, handler, kind, decode, encode)
        return self

    # Service typé : implementation = dict nom de méthode -> gestionnaire (voir l'en-tête).
    func add_service(schema, service_name, implementation):
        sv := schema.service(service_name)
        for name in keys(implementation):
            m := sv.method(name)
            self.add_method("/" + sv.full_name + "/" + name, implementation[name], m.kind(), _decoder(schema, m.input_type), _encoder(schema, m.output_type))
        return self

    # Noms des méthodes servies.
    func method_names():
        out := []
        for k in keys(self.methods):
            append(out, k)
        return out

    func stop():
        self.running = false

    func serve_forever(poll=0.5):
        self.running = true
        while self.running:
            self.step(poll)
        self.close_clients()

    # Sert jusqu'à avoir traité `count` appels de plus (ou jusqu'à stop()).
    func serve(count, poll=0.5):
        target := self.handled + count
        self.running = true
        while self.running and self.handled < target:
            self.step(poll)

    func step(timeout=0.5):
        socks := [self.listener.socket]
        for c in self.clients:
            if _n.blen(c.h2.conn.buffer) > 0 or (self.secure and c.h2.conn.socket.pending() > 0):
                self._read(c)
                return
            append(socks, _raw(c.h2.conn.socket))
        ready := _sk.wait(socks, "read", timeout)
        for s in ready:
            if s == self.listener.socket:
                self._accept()
            else:
                for c in self.clients:
                    if _raw(c.h2.conn.socket) == s:
                        self._read(c)
        now := _time.monotonic()
        for c in self.clients:
            if now - c.last_active > self.idle_timeout:
                self._drop(c)

    func _accept():
        r := null
        try:
            r = self.listener.socket.accept(0)
        catch e:
            return
        sock := r[0]
        conn := null
        try:
            if self.secure:
                ts := _tls.wrap_server(sock, self.cert_file, self.key_file, ["h2"], 10.0)
                conn = _tcp.Connection(ts)
                if ts.alpn != "h2":
                    conn.close()
                    self.rejected += 1
                    return
            else:
                conn = _tcp.Connection(sock)
            h2 := _g.H2Connection(conn, false)
            h2.timeout = 30.0
            h2.start(10.0)
            append(self.clients, _Client(h2, (r[1], r[2])))
        catch e:
            self.rejected += 1
            try:
                sock.close()
            catch e2:
                ignored := e2

    func _drop(c):
        kept := []
        for x in self.clients:
            if x != c:
                append(kept, x)
        self.clients = kept
        try:
            c.h2.close()
        catch e:
            ignored := e

    func close_clients():
        for c in self.clients:
            try:
                c.h2.close()
            catch e:
                ignored := e
        self.clients = []

    func close():
        self.close_clients()
        self.listener.close()

    func _read(c):
        c.last_active = _time.monotonic()
        try:
            c.h2.read_frame(30.0)
        catch e:
            self._drop(c)
            return
        # appels complets (END_STREAM reçu)
        pending := []
        for st in c.h2.new_streams:
            if st.ended:
                self._handle(c, st)
            elif st.reset_code == null:
                append(pending, st)
        c.h2.new_streams = pending

    func _trailers_only(h2, sid, code, message):
        h2.send_headers(sid, [[":status", "200"], ["content-type", "application/grpc"], ["grpc-status", str(code)], ["grpc-message", _g.encode_grpc_message(message)]], true)

    func _handle(c, st):
        h2 := c.h2
        hs := st.headers
        path := _g.header_value(hs, ":path", "")
        method := _g.header_value(hs, ":method", "")
        ct := _g.header_value(hs, "content-type", "")
        self.handled += 1
        try:
            if method != "POST":
                h2.send_headers(st.id, [[":status", "405"], ["allow", "POST"]], true)
                return
            if not _s.starts_with(ct, "application/grpc"):
                h2.send_headers(st.id, [[":status", "415"], ["content-type", "text/plain"]], true)
                return
            if not contains_key(self.methods, path):
                self._trailers_only(h2, st.id, _g.UNIMPLEMENTED, "méthode inconnue " + path)
                return
            m := self.methods[path]
            ctx := Context(self, h2, st, path, hs, c.peer)
            ctx.encoder = m.encode
            status := _g.OK
            message := ""
            outputs := []
            try:
                raw := _g.unframe_messages(st.take_data(), ctx.encoding, self.max_message)
                if _n.blen(raw[1]) > 0:
                    _g.fail(_g.INTERNAL, "message de requête tronqué")
                reqs := []
                for x in raw[0]:
                    if m.decode != null:
                        try:
                            append(reqs, m.decode(x))
                        catch e:
                            _g.fail(_g.INTERNAL, "requête illisible : " + e.message)
                    else:
                        append(reqs, x)
                if ctx.deadline != null and ctx.time_remaining() <= 0:
                    _g.fail(_g.DEADLINE_EXCEEDED, "délai expiré avant le traitement")
                result := null
                if m.kind == "unary" or m.kind == "server_streaming":
                    if len(reqs) != 1:
                        _g.fail(_g.INTERNAL, "un message de requête attendu (" + str(len(reqs)) + " reçus)")
                    result = m.handler(reqs[0], ctx)
                else:
                    result = m.handler(reqs, ctx)
                if m.kind == "unary" or m.kind == "client_streaming":
                    if result == null:
                        _g.fail(_g.INTERNAL, "le gestionnaire n'a rien renvoyé")
                    outputs = [result]
                elif result != null:
                    outputs = result
                if ctx.deadline != null and ctx.time_remaining() <= 0:
                    _g.fail(_g.DEADLINE_EXCEEDED, "délai du client dépassé")
            catch e:
                outputs = []
                if e.type == "GrpcError":
                    sm := _g.status_of(e)
                    status = sm[0]
                    message = sm[1]
                else:
                    append(self.errors, e.type + ": " + e.message)
                    status = _g.UNKNOWN
                    message = "erreur du gestionnaire"
                    if self.expose_errors:
                        message = e.type + " : " + e.message
            if st.reset_code != null:
                return
            if status != _g.OK and not ctx.headers_sent:
                tr := [[":status", "200"], ["content-type", "application/grpc"], ["grpc-status", str(status)], ["grpc-message", _g.encode_grpc_message(message)]]
                for h in _g.metadata_to_headers(ctx.trailing_metadata):
                    append(tr, h)
                h2.send_headers(st.id, tr, true)
                return
            if len(outputs) > 0 or not ctx.headers_sent:
                ctx._send_headers()
            body := []
            for o in outputs:
                data := o
                if m.encode != null:
                    data = m.encode(o)
                append(body, _g.frame_message(data))
            if len(body) > 0:
                h2.send_data(st.id, _s.join("", body), false, 30.0)
            tr := [["grpc-status", str(status)]]
            if message != "":
                append(tr, ["grpc-message", _g.encode_grpc_message(message)])
            for h in _g.metadata_to_headers(ctx.trailing_metadata):
                append(tr, h)
            h2.send_headers(st.id, tr, true)
        catch e:
            append(self.errors, e.type + ": " + e.message)
            self._drop(c)

func _decoder(schema, type_name):
    return (data) => schema.decode(type_name, data)

func _encoder(schema, type_name):
    return (value) => schema.encode(type_name, value)

func _raw(s):
    if isinstance(s, _tls.TlsSocket):
        return s.socket
    return s
