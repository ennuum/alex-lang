# ALEX STANDARD LIBRARY — network.grpc_client
#
# Client gRPC sur HTTP/2 (network.grpc) : canal persistant vers un serveur, appels des quatre formes (unaire, flux
# serveur, flux client, bidirectionnel), délais (grpc-timeout), métadonnées, statuts ; souche typée à partir d'un
# schéma Protocol Buffers (network.protobuf).
#
#   ch := Channel("127.0.0.1:50051")                   en clair (h2c) ; Channel("hôte:443", true) : TLS + ALPN h2
#   r := ch.unary("/paquet.Service/Méthode", octets)    octets de la réponse ; GrpcError si statut != OK
#   for m in ch.server_stream(chemin, octets) ...       liste des réponses
#   ch.client_stream(chemin, [octets...]) / ch.bidi_stream(chemin, [octets...])
#   stub := Stub(ch, schéma, "paquet.Service")         stub.call("Méthode", {...}) -> dict (ou list de dict)
#   ch.last_call                                         en-têtes, métadonnées de fin, statut du dernier appel
#
# Les appels d'un canal passent l'un après l'autre sur la même connexion HTTP/2 (rétablie si le serveur l'a
# fermée). Une réponse en flux est lue entièrement avant de rendre la main (liste).
#
# Erreurs : GrpcError « [CODE] message » (voir network.grpc.status_of), TimeoutError (délai local),
# NetworkError, TlsError, ProtocolError.
#
# Exemple
#   use network.grpc_client as gc
#   use network.protobuf as pb
#   s := pb.load_proto("salut.proto")
#   stub := gc.Stub(gc.Channel("127.0.0.1:50051"), s, "salut.Saluer")
#   print(stub.call("Dire", {"nom": "Ada"})["message"])

from core use len, type
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use network.tcp as _tcp
use network.tls as _tls
use network.core as _core
use network.utils as _u
use network.grpc as _g
use network.compression as _z

const USER_AGENT := "grpc-alex/1.0"

class CallInfo:
    func init():
        self.headers = []
        self.trailers = []
        self.metadata = {}            # métadonnées d'en-tête de la réponse
        self.trailing_metadata = {}
        self.status = null
        self.message = ""
        self.elapsed = 0.0

class Channel:
    # target : « hôte:port », « [v6]:port » ou URL « http(s)://hôte:port ». secure : TLS (ALPN h2).
    # metadata : métadonnées ajoutées à chaque appel ; timeout : délai par défaut d'un appel (secondes).
    func init(target, secure=null, ca_file=null, verify=true, metadata=null, timeout=30.0, connect_timeout=10.0, authority=null, max_message=4194304, compression=null):
        t := target
        sec := secure
        if _s.starts_with(t, "https://") or _s.starts_with(t, "grpcs://"):
            t = _s.substring(t, _s.find(t, "://") + 3, len(t))
            if sec == null:
                sec = true
        elif _s.starts_with(t, "http://") or _s.starts_with(t, "grpc://"):
            t = _s.substring(t, _s.find(t, "://") + 3, len(t))
        if _s.ends_with(t, "/"):
            t = _s.substring(t, 0, len(t) - 1)
        if sec == null:
            sec = false
        default_port := 50051
        if sec:
            default_port = 443
        hp := _u.split_host_port(t, default_port)
        self.host = hp[0]
        self.port = hp[1]
        self.secure = sec
        self.ca_file = ca_file
        self.verify = verify
        self.metadata = metadata
        self.timeout = timeout
        self.connect_timeout = connect_timeout
        self.authority = authority
        if authority == null:
            self.authority = _u.join_host_port(self.host, self.port)
        self.max_message = max_message
        self.compression = compression     # "gzip" pour compresser les requêtes, ou null
        self.h2 = null
        self.last_call = null
        self.calls = 0

    func _connection():
        if self.h2 != null and not self.h2.closed and self.h2.goaway == null:
            return self.h2
        if self.h2 != null:
            try:
                self.h2.close()
            catch e:
                ignored := e
        conn := null
        if self.secure:
            conn = _core.open_connection(self.host, self.port, true, self.connect_timeout, self.verify, self.ca_file, ["h2"])
            if conn.socket.alpn != "h2":
                conn.close()
                _g.fail(_g.UNAVAILABLE, "le serveur n'a pas négocié HTTP/2 (ALPN « " + str(conn.socket.alpn) + " »)")
        else:
            conn = _tcp.connect(self.host, self.port, self.connect_timeout)
        h2 := _g.H2Connection(conn, true)
        h2.timeout = self.connect_timeout
        h2.start(self.connect_timeout)
        self.h2 = h2
        return h2

    func close():
        if self.h2 != null:
            self.h2.close()
            self.h2 = null

    func __enter__():
        return self

    func __exit__(t, v, tb):
        self.close()
        return false

    func _request_headers(path, metadata, timeout):
        scheme := "http"
        if self.secure:
            scheme = "https"
        hs := [[":method", "POST"], [":scheme", scheme], [":path", path], [":authority", self.authority], ["content-type", "application/grpc"], ["te", "trailers"], ["user-agent", USER_AGENT], ["grpc-accept-encoding", "gzip,identity"]]
        if self.compression != null:
            append(hs, ["grpc-encoding", self.compression])
        if timeout != null:
            append(hs, ["grpc-timeout", _g.encode_timeout(timeout)])
        for h in _g.metadata_to_headers(self.metadata):
            append(hs, h)
        for h in _g.metadata_to_headers(metadata):
            append(hs, h)
        return hs

    # Appel générique : envoie les messages (octets) puis lit toutes les réponses. Rend la liste des réponses.
    func call(path, requests, metadata=null, timeout=null):
        if type(path) != "str" or not _s.starts_with(path, "/"):
            raise("ArgumentError", "grpc_client : chemin « /paquet.Service/Méthode » attendu")
        t := timeout
        if t == null:
            t = self.timeout
        start := _time.monotonic()
        attempt := 0
        while true:
            attempt += 1
            h2 := self._connection()
            st := null
            try:
                st = h2.new_stream()
                h2.timeout = t
                h2.send_headers(st.id, self._request_headers(path, metadata, t), false)
                body := []
                for r in requests:
                    data := r
                    if type(r) == "list":
                        data = _n.from_bytes(r)
                    if self.compression != null:
                        append(body, _g.frame_message(_z.encode(data, self.compression), true))
                    else:
                        append(body, _g.frame_message(data))
                h2.send_data(st.id, _s.join("", body), true, t)
            catch e:
                # connexion réutilisée fermée par le serveur : une nouvelle tentative
                if attempt == 1 and (e.type == "NetworkError" or e.type == "TlsError" or e.type == "ProtocolError"):
                    self.close()
                    continue
                self.close()
                raise(e)
            return self._finish(h2, st, start, t)

    func _finish(h2, st, start, t):
        info := CallInfo()
        self.last_call = info
        self.calls += 1
        try:
            h2.wait_until(() => st.ended or st.reset_code != null, t - (_time.monotonic() - start))
        catch e:
            if e.type == "TimeoutError":
                try:
                    h2.reset_stream(st.id, _g.ERR_CANCEL)
                catch e2:
                    ignored := e2
                _g.fail(_g.DEADLINE_EXCEEDED, "délai de " + str(t) + " s dépassé")
            self.close()
            raise(e)
        info.elapsed = _time.monotonic() - start
        if st.reset_code != null and not st.ended:
            _g.fail(_g.UNAVAILABLE, "flux réinitialisé par le serveur (code " + str(st.reset_code) + ")")
        if st.headers == null:
            _g.fail(_g.INTERNAL, "réponse sans en-têtes")
        info.headers = st.headers
        http_status := _g.header_value(st.headers, ":status")
        trailers := st.trailers
        if trailers == null:
            trailers = st.headers          # réponse « trailers-only »
        info.trailers = trailers
        info.metadata = _g.headers_to_metadata(st.headers)
        info.trailing_metadata = _g.headers_to_metadata(trailers)
        gs := _g.header_value(trailers, "grpc-status")
        if http_status != "200":
            code := _g.UNKNOWN
            if http_status == "400":
                code = _g.INTERNAL
            elif http_status == "401":
                code = _g.UNAUTHENTICATED
            elif http_status == "403":
                code = _g.PERMISSION_DENIED
            elif http_status == "404":
                code = _g.UNIMPLEMENTED
            elif http_status == "429" or http_status == "502" or http_status == "503" or http_status == "504":
                code = _g.UNAVAILABLE
            if gs == null:
                _g.fail(code, "réponse HTTP " + str(http_status))
        ct := _g.header_value(st.headers, "content-type", "")
        if gs == null:
            _g.fail(_g.INTERNAL, "réponse sans grpc-status")
        info.status = _str_to_int(gs)
        info.message = _g.decode_grpc_message(_g.header_value(trailers, "grpc-message", ""))
        if info.status != _g.OK:
            _g.fail(info.status, info.message)
        if not _s.starts_with(ct, "application/grpc"):
            _g.fail(_g.INTERNAL, "type de contenu inattendu « " + ct + " »")
        enc := _g.header_value(st.headers, "grpc-encoding")
        msgs := _g.unframe_messages(st.take_data(), enc, self.max_message)
        if _n.blen(msgs[1]) > 0:
            _g.fail(_g.INTERNAL, "message de réponse tronqué")
        return msgs[0]

    # Appel unaire : un message -> une réponse (octets).
    func unary(path, request, metadata=null, timeout=null):
        r := self.call(path, [request], metadata, timeout)
        if len(r) != 1:
            _g.fail(_g.INTERNAL, "appel unaire : " + str(len(r)) + " réponses au lieu d'une")
        return r[0]

    func server_stream(path, request, metadata=null, timeout=null):
        return self.call(path, [request], metadata, timeout)

    func client_stream(path, requests, metadata=null, timeout=null):
        r := self.call(path, requests, metadata, timeout)
        if len(r) != 1:
            _g.fail(_g.INTERNAL, "flux client : " + str(len(r)) + " réponses au lieu d'une")
        return r[0]

    func bidi_stream(path, requests, metadata=null, timeout=null):
        return self.call(path, requests, metadata, timeout)

    # Aller-retour HTTP/2 (PING) : latence en secondes.
    func ping(timeout=5.0):
        return self._connection().ping(timeout)

func _str_to_int(s):
    v := 0
    for c in _s.trim(s):
        if c < '0' or c > '9':
            return _g.UNKNOWN
        v = v * 10 + (_s.ord(c) - 48)
    return v

# Souche typée : encode / décode les messages avec un schéma Protocol Buffers.
class Stub:
    func init(channel, schema, service_name):
        self.channel = channel
        self.schema = schema
        self.service = schema.service(service_name)

    # Appelle `method` ; request : dict (ou liste de dict pour un flux client). Rend un dict, ou une liste de dict
    # pour un flux serveur ou bidirectionnel.
    func call(method, request, metadata=null, timeout=null):
        m := self.service.method(method)
        path := "/" + self.service.full_name + "/" + method
        reqs := []
        if m.client_streaming:
            for r in request:
                append(reqs, self.schema.encode(m.input_type, r))
        else:
            reqs = [self.schema.encode(m.input_type, request)]
        raw := self.channel.call(path, reqs, metadata, timeout)
        out := []
        for x in raw:
            append(out, self.schema.decode(m.output_type, x))
        if m.server_streaming:
            return out
        if len(out) != 1:
            _g.fail(_g.INTERNAL, method + " : " + str(len(out)) + " réponses au lieu d'une")
        return out[0]

    # Fonction d'appel d'une méthode : stub.method("Dire")({"nom": "x"}).
    func method(name):
        me := self
        return (request) => me.call(name, request)
