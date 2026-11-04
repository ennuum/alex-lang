# ALEX STANDARD LIBRARY — web.server.response_writer
#
# Écriture d'une réponse sur une connexion du serveur : en-têtes complétés selon le protocole (Date, Server,
# Content-Length ou Transfer-Encoding: chunked, Connection, Keep-Alive), puis le corps — str, fichier envoyé par
# morceaux (body_file / body_range, sans le charger en mémoire), ou flux produit par une fonction (body_stream,
# envoyé en chunked). HEAD, 1xx, 204 et 304 n'ont jamais de corps.
#
#   use web.server.response_writer as rw
#   w := rw.ResponseWriter("Alex-web/1.0", 30.0)
#   n := w.write(conn, requete, reponse, true)      # octets envoyés ; reponse.keep_alive : décision finale
#   w.write_error(conn, 400, "requête invalide")    # réponse d'erreur minimale, connexion à fermer
#
# Erreurs : NetworkError / TimeoutError (client parti, écriture trop lente) : la connexion doit être fermée.

from core use len, type
use string as _s
use io as _io
use os as _os
use web.http.protocol_writer as _writer
use web.http.message_body as _mb
use web.http.status_code as _status

const CHUNK_SIZE := 65536

class ResponseWriter:
    func init(server_name="Alex-web/1.0", write_timeout=30.0, chunk_size=CHUNK_SIZE, keep_alive_policy=null):
        self.server_name = server_name
        self.write_timeout = write_timeout
        self.chunk_size = chunk_size
        self.keep_alive_policy = keep_alive_policy

    # Envoie resp en réponse à req sur conn ; keep_alive : persistance souhaitée. Renvoie les octets envoyés.
    func write(conn, req, resp, keep_alive=true):
        method := req.method if req != null else "GET"
        version := req.version if req != null else "HTTP/1.1"
        if resp.body_file != null and resp.body_range == null:
            resp.body_range = (0, _os.size(resp.body_file))
        _writer.prepare_response(resp, method, version, keep_alive, self.server_name)
        if resp.keep_alive and version == "HTTP/1.0" and self.keep_alive_policy != null:
            resp.headers.set("Keep-Alive", self.keep_alive_policy.header_value(conn))
        head := _writer.write_response_head(resp)
        no_body := method == "HEAD" or not _status.allows_body(resp.status)
        t := self.write_timeout
        if no_body:
            return conn.send(head, t)
        if resp.body_stream != null:
            return self._write_stream(conn, resp, head, t)
        if resp.body_file != null:
            return self._write_file(conn, resp, head, t)
        if resp.headers.has_token("transfer-encoding", "chunked"):
            return conn.send(head + _mb.encode_chunked(resp.body, self.chunk_size), t)
        return conn.send(_s.byte_join([head, resp.body]), t)

    func _write_file(conn, resp, head, t):
        n := conn.send(head, t)
        offset := resp.body_range[0]
        remaining := resp.body_range[1]
        while remaining > 0:
            k := self.chunk_size if remaining > self.chunk_size else remaining
            data := _s.byte_pack(_io.read_bytes(resp.body_file, offset, k))
            got := _s.byte_len(data)
            if got == 0:
                break      # fichier raccourci entre-temps : la connexion sera fermée (longueur annoncée non tenue)
            n += conn.send(data, t)
            offset += got
            remaining -= got
        if remaining > 0:
            conn.closing = true
        return n

    func _write_stream(conn, resp, head, t):
        chunked := resp.headers.has_token("transfer-encoding", "chunked")
        n := conn.send(head, t)
        while true:
            piece := resp.body_stream()
            if piece == null:
                break
            data := _mb.to_bytes(piece)
            if data == "":
                continue
            if chunked:
                n += conn.send(_mb.chunk(data), t)
            else:
                n += conn.send(data, t)
        if chunked:
            n += conn.send(_mb.last_chunk(), t)
        else:
            conn.closing = true      # HTTP/1.0 : fin du corps = fermeture
        return n

    # Réponse d'erreur minimale (protocole) ; la connexion doit être fermée ensuite.
    func write_error(conn, status, message=null):
        try:
            return conn.send(_writer.simple_error(status, message, self.server_name), self.write_timeout)
        catch e:
            return 0

    # « 100 Continue » pour un client qui attend avant d'envoyer son corps.
    func write_continue(conn):
        conn.continue_sent = true
        return conn.send(_writer.continue_response(), self.write_timeout)
