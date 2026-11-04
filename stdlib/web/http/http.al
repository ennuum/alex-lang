# ALEX STANDARD LIBRARY — web.http
#
# Point d'entrée du paquet web.http : le protocole HTTP/1.1 (RFC 9110 sémantique, RFC 9112 syntaxe) sans réseau.
# Messages, en-têtes, analyse et écriture ; web.client et web.server y ajoutent les connexions.
#
# | Module                      | Rôle                                                              |
# |-----------------------------|-------------------------------------------------------------------|
# | web.http (ce module)        | raccourcis : Request, Response, Headers, parse_*, write_*         |
# | web.http.request / response | messages et constructeurs (text, html, json, redirect, error...)  |
# | web.http.headers            | Headers (multi-valeurs, insensible à la casse, validé)            |
# | web.http.header_name / header_value | noms canoniques, listes, paramètres, qualités, directives |
# | web.http.method / status_code / version | méthodes, statuts, versions                         |
# | web.http.content_type / content_length / date_header | Content-Type, Content-Length, dates HTTP |
# | web.http.request_target     | les quatre formes de cible de requête                             |
# | web.http.message_body       | cadrage, chunked (incrémental), JSON / formulaire                 |
# | web.http.protocol_parser    | analyseurs incrémentaux de requêtes et de réponses (limites)      |
# | web.http.protocol_writer    | préparation et écriture des messages                             |
# | web.http.http_errors        | erreurs et code de statut associé                                 |
#
#   use web.http as http
#   req := http.parse_request("GET /bonjour?nom=Zoé HTTP/1.1\r\nHost: h\r\n\r\n")
#   req.query_param("nom")                                  # Zoé
#   resp := http.json({"salut": req.query_param("nom")})
#   wire := http.write_response(resp, req)                  # message complet, Date / Content-Length compris
#   back := http.parse_response(wire)
#   back.json_value()["salut"]                              # Zoé
#
# Erreurs : voir web.http.http_errors.

from core use len, type
use web.http.http_errors as _err
use web.http.headers as _headers
use web.http.request as _request
use web.http.response as _response
use web.http.status_code as _status
use web.http.method as _method
use web.http.version as _version
use web.http.content_type as _ct
use web.http.date_header as _date
use web.http.protocol_parser as _parser
use web.http.protocol_writer as _writer

const HTTP_1_0 := "HTTP/1.0"
const HTTP_1_1 := "HTTP/1.1"

# ---------------------------------------------------------------- messages

func Headers(data=null):
    return _headers.Headers(data)

func Request(method="GET", target="/", headers=null, body="", version=HTTP_1_1):
    return _request.Request(method, target, headers, body, version)

func Response(status=200, body="", headers=null):
    return _response.Response(status, body, headers)

func text(body, status=200, headers=null):
    return _response.text(body, status, headers)

func html(body, status=200, headers=null):
    return _response.html(body, status, headers)

func json(value, status=200, headers=null):
    return _response.json(value, status, headers)

func redirect(location, status=302):
    return _response.redirect(location, status)

func error(status, message=null):
    return _response.error(status, message)

func no_content():
    return _response.no_content()

# ---------------------------------------------------------------- analyse / écriture

func parse_request(text, limits=null):
    return _parser.parse_request(text, limits)

func parse_requests(text, limits=null):
    return _parser.parse_requests(text, limits)

func parse_response(text, method="GET", limits=null):
    return _parser.parse_response(text, method, limits)

func request_parser(limits=null):
    return _parser.RequestParser(limits)

func response_parser(method="GET", limits=null):
    return _parser.ResponseParser(method, limits)

func limits(max_start_line=8192, max_header_bytes=65536, max_headers=100, max_body=10485760):
    return _parser.Limits(max_start_line, max_header_bytes, max_headers, max_body)

# Requête complète prête à envoyer (Host, Content-Length complétés).
func write_request(req, host=null):
    _writer.prepare_request(req, host)
    return _writer.write_request(req)

# Réponse complète à une requête (req : Request, ou null pour GET HTTP/1.1).
func write_response(resp, req=null, keep_alive=true):
    m := "GET"
    v := HTTP_1_1
    if req != null:
        m = req.method
        v = req.version
        keep_alive = keep_alive and req.keep_alive()
    _writer.prepare_response(resp, m, v, keep_alive)
    return _writer.write_response(resp, m)

# ---------------------------------------------------------------- raccourcis

func reason(status):
    return _status.reason(status)

func is_success(status):
    return _status.is_success(status)

func http_date(timestamp=null):
    if timestamp == null:
        return _date.now()
    return _date.format(timestamp)

func parse_http_date(text):
    return _date.parse(text)

func guess_type(filename):
    return _ct.guess(filename)

func is_http_error(e):
    return _err.is_http_error(e.type)

func status_for_error(e):
    return _err.status_for(e)
