# ALEX STANDARD LIBRARY — web.client
#
# Point d'entrée du client HTTP : fonctions directes (un client partagé, créé au premier appel) et création de
# clients configurés. Les fonctions de ce module acceptent les arguments nommés.
#
# | Module                        | Rôle                                                             |
# |-------------------------------|------------------------------------------------------------------|
# | web.client (ce module)        | get, post, put, patch, delete, head, request, Client, Config     |
# | web.client.http_client        | HttpClient (réserve, redirections, reprises, cookies), CookieJar |
# | web.client.client_config      | ClientConfig et ses with_*                                       |
# | web.client.client_request / client_response | requête à envoyer, réponse reçue (text, json…) |
# | web.client.request_builder    | construction chaînée (c.build("POST", url).json(v).send())       |
# | web.client.response_reader    | lecture d'une réponse sur une connexion                          |
# | web.client.connection / connection_pool | connexions TCP / TLS / mandataire, réserve keep-alive  |
# | web.client.timeout / retry_policy / redirect / proxy / tls_config / user_agent | réglages        |
# | web.client.client_errors      | erreurs et classification des reprises                           |
#
#   use web.client as http
#   r := http.get("https://exemple.org/", params={"q": "chat"})
#   print(r.status, r.header("content-type"), len(r.text()))
#   data := http.get_json("https://api.exemple.org/notes", headers={"Authorization": "Bearer …"})
#   r2 := http.post("https://api.exemple.org/notes", json={"titre": "Été"}, timeout=5)
#   r3 := http.post("https://exemple.org/connexion", form={"user": "zoe", "mdp": "…"})
#   up := http.post("https://exemple.org/upload", files=[("fichier", "a.txt", "contenu", "text/plain")])
#
#   c := http.Client(base_url="https://api.exemple.org/v1/", timeout=10, retries=3, headers={"Accept": "application/json"})
#   c.get("notes/7").json()
#   c.close()
#
# Erreurs : voir web.client.client_errors.

from core use len, type
use web.client.client_errors as _err
use web.client.http_client as _hc
use web.client.client_config as _config
use web.client.client_request as _creq
use web.client.tls_config as _tls
use web.client.timeout as _timeout
use web.client.retry_policy as _retry
use web.client.redirect as _redirect

_shared := [null]

# Client partagé par les fonctions de ce module (créé au premier appel).
func shared():
    if _shared[0] == null or _shared[0].closed:
        _shared[0] = _hc.HttpClient()
    return _shared[0]

# Ferme les connexions du client partagé.
func close():
    if _shared[0] != null:
        _shared[0].close()
        _shared[0] = null

# Configuration : arguments nommés facultatifs ; verify=false désactive la vérification TLS (tests).
func Config(base_url=null, timeout=null, retries=null, redirects=null, headers=null, proxy=null, user_agent=null, verify=true, ca_file=null, cookies=true, keep_alive=true, max_response_size=null, raise_for_status=false):
    c := _config.ClientConfig()
    if base_url != null:
        c = c.with_base_url(base_url)
    if timeout != null:
        c = c.with_timeout(timeout)
    if retries != null:
        c = c.with_retries(retries)
    if redirects != null:
        c = c.with_redirects(redirects)
    if headers != null:
        c = c.with_headers(headers)
    if proxy != null:
        c = c.with_proxy(proxy)
    if user_agent != null:
        c = c.with_user_agent(user_agent)
    if not verify or ca_file != null:
        c = c.with_tls(_tls.TlsConfig(verify, ca_file))
    if max_response_size != null:
        c = c.with_max_response_size(max_response_size)
    c = c.with_cookies(cookies).with_keep_alive(keep_alive).with_raise_for_status(raise_for_status)
    return c

# Client configuré (mêmes arguments que Config) ; à fermer avec close() (ou with … as c).
func Client(base_url=null, timeout=null, retries=null, redirects=null, headers=null, proxy=null, user_agent=null, verify=true, ca_file=null, cookies=true, keep_alive=true, max_response_size=null, raise_for_status=false):
    return _hc.HttpClient(Config(base_url, timeout, retries, redirects, headers, proxy, user_agent, verify, ca_file, cookies, keep_alive, max_response_size, raise_for_status))

# Requête complète. Corps : body (str / octets, avec content_type), json (valeur), form (dict), ou files
# (multipart, avec les champs de form). auth : (utilisateur, mot de passe) ; bearer : jeton ;
# follow_redirects : true / false ; timeout : secondes ou Timeout ; client : HttpClient à utiliser.
func request(method, url, params=null, headers=null, body=null, content_type=null, json=null, form=null, files=null, auth=null, bearer=null, timeout=null, follow_redirects=null, client=null):
    c := client if client != null else shared()
    r := _creq.ClientRequest(method, c.resolve_url(url), headers, null, params, timeout)
    if files != null:
        r.set_multipart(form, files)
    elif body != null:
        r.set_body(body, content_type)
    elif json != null:
        r.set_json(json)
    elif form != null:
        r.set_form(form)
    if auth != null:
        r.set_basic_auth(auth[0], auth[1])
    if bearer != null:
        r.set_bearer(bearer)
    if follow_redirects != null:
        r.follow_redirects = follow_redirects
    return c.send(r)

func get(url, params=null, headers=null, timeout=null, auth=null, bearer=null, follow_redirects=null, client=null):
    return request("GET", url, params, headers, null, null, null, null, null, auth, bearer, timeout, follow_redirects, client)

func head(url, params=null, headers=null, timeout=null, client=null):
    return request("HEAD", url, params, headers, null, null, null, null, null, null, null, timeout, null, client)

func options(url, headers=null, timeout=null, client=null):
    return request("OPTIONS", url, null, headers, null, null, null, null, null, null, null, timeout, null, client)

func delete(url, params=null, headers=null, timeout=null, auth=null, bearer=null, client=null):
    return request("DELETE", url, params, headers, null, null, null, null, null, auth, bearer, timeout, null, client)

func post(url, body=null, content_type=null, json=null, form=null, files=null, params=null, headers=null, timeout=null, auth=null, bearer=null, client=null):
    return request("POST", url, params, headers, body, content_type, json, form, files, auth, bearer, timeout, null, client)

func put(url, body=null, content_type=null, json=null, form=null, params=null, headers=null, timeout=null, auth=null, bearer=null, client=null):
    return request("PUT", url, params, headers, body, content_type, json, form, null, auth, bearer, timeout, null, client)

func patch(url, body=null, content_type=null, json=null, form=null, params=null, headers=null, timeout=null, auth=null, bearer=null, client=null):
    return request("PATCH", url, params, headers, body, content_type, json, form, null, auth, bearer, timeout, null, client)

# Corps JSON décodé ; HttpStatusError si le statut est une erreur.
func get_json(url, params=null, headers=null, timeout=null, bearer=null, client=null):
    h := headers if headers != null else {}
    r := request("GET", url, params, h, null, null, null, null, null, null, bearer, timeout, null, client)
    return r.raise_for_status().json()

# Texte du corps ; HttpStatusError si le statut est une erreur.
func get_text(url, params=null, headers=null, timeout=null, client=null):
    return get(url, params, headers, timeout, null, null, null, client).raise_for_status().text()

func download(url, path, params=null, headers=null, client=null):
    c := client if client != null else shared()
    return c.download(url, path, params, headers)

# Constructeur chaîné attaché au client partagé (ou à client).
func build(method, url, client=null):
    c := client if client != null else shared()
    return c.build(method, url)
