# ALEX STANDARD LIBRARY — web.client.response_reader
#
# Lecture d'une réponse HTTP sur une connexion du client : octets reçus au fil de l'eau, analysés par
# web.http.protocol_parser.ResponseParser (réponses 1xx ignorées, corps à longueur connue, chunked ou jusqu'à la
# fermeture), délai d'inactivité et délai total respectés, taille plafonnée, décompression gzip / deflate.
# Indique aussi si la connexion peut être réutilisée.
#
#   use web.client.response_reader as rr
#   reader := rr.ResponseReader(104857600, 65536, true)
#   res := reader.read(connexion, "GET", 30.0, deadline)
#   res.response.status, res.reusable, res.stale     # stale : fermée sans réponse (connexion de réserve périmée)
#
# Erreurs : ClientResponseError (réponse invalide, trop grande, tronquée), ClientConnectionError,
# ClientTimeoutError.

from core use len, type
use string as _s
use network.compression as _z
use web.client.client_errors as _err
use web.client.timeout as _timeout
use web.http.protocol_parser as _pp
use web.http.message_body as _mb
use web.http.content_length as _cl

class ReadResult:
    func init(response, reusable, stale=false, informational=null):
        self.response = response            # web.http.response.Response, ou null si stale
        self.reusable = reusable            # la connexion peut servir à nouveau
        self.stale = stale                  # fermée par le serveur avant le moindre octet
        self.informational = informational if informational != null else []

class ResponseReader:
    func init(max_body=104857600, max_header_bytes=65536, decompress=true):
        self.max_body = max_body
        self.max_header_bytes = max_header_bytes
        self.decompress = decompress

    # Lit la réponse à une requête method ; read_timeout : inactivité maximale ; deadline : Deadline ou null.
    func read(conn, method, read_timeout=null, deadline=null):
        d := deadline if deadline != null else _timeout.Deadline()
        where := conn.scheme + "://" + conn.host + ":" + str(conn.port)
        parser := _pp.ResponseParser(method, _pp.Limits(8192, self.max_header_bytes, 100, self.max_body if self.max_body != null else false))
        received := 0
        while true:
            d.check(where)
            data := conn.recv(65536, d.cap(read_timeout))
            msgs := []
            try:
                if data == "":
                    if received == 0:
                        conn.close()
                        return ReadResult(null, false, true)
                    msgs = parser.finish()
                else:
                    received += _s.byte_len(data)
                    msgs = parser.feed(data)
            catch e:
                conn.close()
                _err.wrap(e, where)
            if len(msgs) > 0:
                resp := msgs[0]
                reusable := data != "" and parser.pending() == 0 and _keep_alive(resp, method)
                if self.decompress:
                    self._decode(resp, where)
                return ReadResult(resp, reusable, false, parser.informational)

    func _decode(resp, where):
        enc := resp.headers.get("content-encoding")
        if enc == null or resp.body == "":
            return
        codings := _mb.transfer_codings(enc)
        for c in codings:
            if c != "gzip" and c != "x-gzip" and c != "deflate" and c != "identity":
                return     # codage inconnu (br, zstd...) : corps laissé tel quel
        try:
            limit := self.max_body if self.max_body != null else 1073741824
            resp.body = _z.decode(resp.body, _s.replace(enc, "x-gzip", "gzip"), limit)
        catch e:
            _err.response_error("response_reader", where + " : corps compressé invalide (" + str(e.message) + ")")
        resp.headers.remove("content-encoding")
        resp.headers.set("Content-Length", _s.byte_len(resp.body))

# Persistance après la réponse : HTTP/1.1 sauf « Connection: close » ; HTTP/1.0 avec « keep-alive » ; jamais
# pour un corps délimité par la fermeture.
func _keep_alive(resp, method):
    if resp.headers.has_token("connection", "close"):
        return false
    if _mb.response_framing(method, resp.status, resp.headers) == _mb.CLOSE:
        return false
    if resp.version == "HTTP/1.0":
        return resp.headers.has_token("connection", "keep-alive")
    return true

func reader(max_body=104857600, max_header_bytes=65536, decompress=true):
    return ResponseReader(max_body, max_header_bytes, decompress)
