# ALEX STANDARD LIBRARY — web.http.protocol_writer
#
# Écriture du protocole HTTP/1.x (RFC 9112) : lignes de départ, en-têtes, cadrage du corps. Produit des str
# d'octets prêtes à envoyer ; le réseau est l'affaire de web.client et web.server.
#
# prepare_request / prepare_response complètent un message selon les règles du protocole avant l'envoi :
#   - Content-Length calculé pour un corps connu ; « Transfer-Encoding: chunked » pour un flux (HTTP/1.1) ;
#   - pas de corps pour HEAD, 1xx, 204, 304 (mais Content-Length gardé pour HEAD) ;
#   - Date et Server ajoutés aux réponses, Host aux requêtes HTTP/1.1 ;
#   - Connection: close / keep-alive selon la décision de persistance.
#
#   use web.http.protocol_writer as pw
#   use web.http.request as rq
#   pw.write_request(rq.Request("GET", "/", {"Host": "exemple.org"}))
#   # "GET / HTTP/1.1\r\nHost: exemple.org\r\n\r\n"
#   use web.http.response as rs
#   r := pw.prepare_response(rs.text("ok"), "GET", "HTTP/1.1", true)
#   pw.write_response(r, "GET")          # "HTTP/1.1 200 OK\r\nContent-Type: ...\r\nContent-Length: 2\r\n...\r\n\r\nok"
#
# Erreurs : HttpError (message incohérent : corps fichier ou flux passé à write_*, Host manquant), HttpHeaderError.

from core use len, type
use string as _s
use web.http.http_errors as _err
use web.http.headers as _headers
use web.http.status_code as _status
use web.http.date_header as _date
use web.http.message_body as _mb
use web.http.method as _method

const DEFAULT_SERVER := "Alex-web/1.0"

func request_line(method, target, version="HTTP/1.1"):
    _method.check(method)
    for c in target:
        o := _s.ord(c)
        if o <= 32 or o == 127:
            _err.http_error("protocol_writer.request_line", "caractère interdit dans la cible « " + target + " »")
    return method + " " + target + " " + version + "\r\n"

func status_line(status, reason=null, version="HTTP/1.1"):
    _status.check(status)
    r := reason if reason != null else _status.reason(status)
    for c in r:
        o := _s.ord(c)
        if (o < 32 and o != 9) or o == 127:
            _err.http_error("protocol_writer.status_line", "caractère de contrôle dans la raison")
    return version + " " + str(status) + " " + r + "\r\n"

# Ligne de départ + en-têtes + ligne vide.
func head(start_line, headers):
    return start_line + headers.to_wire() + "\r\n"

# ---------------------------------------------------------------- requêtes

# Complète une requête avant l'envoi : Host (depuis host si absent), Content-Length / chunked. Modifie et rend req.
func prepare_request(req, host=null, keep_alive=true):
    h := req.headers
    if not h.has("host"):
        if host != null:
            h.set("Host", host)
        elif req.version == "HTTP/1.1":
            _err.http_error("protocol_writer.prepare_request", "en-tête Host requis en HTTP/1.1")
    if h.has("transfer-encoding"):
        h.remove("content-length")
    elif req.body != "" or _method.expects_body(req.method):
        h.set("Content-Length", _s.byte_len(req.body))
    if not keep_alive:
        h.set("Connection", "close")
    return req

func write_request_head(req):
    return head(request_line(req.method, req.target, req.version), req.headers)

# Requête complète (en-têtes + corps, chunked si Transfer-Encoding le demande).
func write_request(req):
    out := write_request_head(req)
    if req.headers.has_token("transfer-encoding", "chunked"):
        return out + _mb.encode_chunked(req.body)
    return out + req.body

# ---------------------------------------------------------------- réponses

# Complète une réponse avant l'envoi. request_method : méthode de la requête (HEAD : pas de corps) ;
# request_version : version de la requête (1.0 : pas de chunked, réponse en 1.0) ; keep_alive : la connexion
# reste-t-elle ouverte ? date : valeur de Date (null : maintenant ; false : ne pas ajouter) ; server=false : pas
# d'en-tête Server.
func prepare_response(resp, request_method="GET", request_version="HTTP/1.1", keep_alive=true, server=DEFAULT_SERVER, date=null):
    h := resp.headers
    if request_version == "HTTP/1.0":
        resp.version = "HTTP/1.0"
    else:
        resp.version = "HTTP/1.1"
    if date != false and not h.has("date"):
        h.set("Date", date if date != null else _date.now())
    if server != null and server != false and not h.has("server"):
        h.set("Server", server)
    no_body := not _status.allows_body(resp.status)
    if no_body:
        h.remove("content-length")
        h.remove("transfer-encoding")
        resp.body = ""
        resp.body_file = null
        resp.body_stream = null
    elif resp.body_stream != null:
        h.remove("content-length")
        if resp.version == "HTTP/1.1":
            h.set("Transfer-Encoding", "chunked")
        else:
            keep_alive = false      # HTTP/1.0 : corps délimité par la fermeture
    else:
        size := resp.body_size()
        if size != null:
            h.remove("transfer-encoding")
            h.set("Content-Length", size)
        elif resp.body_file != null:
            # taille inconnue (fichier sans plage) : à l'appelant de fixer body_range
            _err.http_error("protocol_writer.prepare_response", "body_file sans body_range (taille inconnue)")
    if keep_alive:
        if resp.version == "HTTP/1.0":
            h.set("Connection", "keep-alive")
        elif h.has_token("connection", "close"):
            keep_alive = false
    else:
        h.set("Connection", "close")
    resp.keep_alive = keep_alive
    return resp

func write_response_head(resp):
    return head(status_line(resp.status, resp.reason, resp.version), resp.headers)

# Réponse complète pour un corps str (HEAD : en-têtes seuls). Les corps fichier / flux s'écrivent par morceaux
# (web.server.response_writer).
func write_response(resp, request_method="GET"):
    if resp.body_file != null or resp.body_stream != null:
        _err.http_error("protocol_writer.write_response", "corps fichier ou flux : utiliser un écrivain de flux")
    out := write_response_head(resp)
    if request_method == "HEAD" or not _status.allows_body(resp.status):
        return out
    if resp.headers.has_token("transfer-encoding", "chunked"):
        return out + _mb.encode_chunked(resp.body)
    return out + resp.body

# Réponse intermédiaire « 100 Continue ».
func continue_response(version="HTTP/1.1"):
    return version + " 100 Continue\r\n\r\n"

# Réponse d'erreur minimale complète (connexion fermée ensuite), pour les erreurs de protocole.
func simple_error(status, message=null, server=DEFAULT_SERVER):
    body := str(status) + " " + _status.reason(status)
    if message != null:
        body = body + "\n" + str(message)
    body = body + "\n"
    h := _headers.Headers()
    h.set("Content-Type", "text/plain; charset=utf-8")
    h.set("Content-Length", _s.byte_len(body))
    h.set("Connection", "close")
    h.set("Date", _date.now())
    if server != null and server != false:
        h.set("Server", server)
    return head(status_line(status), h) + body
