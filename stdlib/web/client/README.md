# web.client — client HTTP/1.1

`web.client` envoie des requêtes HTTP et HTTPS : connexions persistantes, TLS vérifié, mandataires,
redirections sûres, reprises, délais, décompression, cookies. Le protocole vient de `web.http`, les URL de
`web.url`, le réseau de `network.tcp` / `network.tls` (OpenSSL chargé à l'exécution pour HTTPS).

## Architecture

```text
stdlib/web/client/
├── client.al             point d'entrée : get, post, put, patch, delete, head, request, Client, Config
├── http_client.al        HttpClient (envoi, redirections, reprises, cookies), CookieJar
├── client_config.al      ClientConfig et ses with_*
├── client_request.al     ClientRequest : URL, en-têtes, corps JSON / formulaire / multipart, Basic, Bearer
├── client_response.al    ClientResponse : text() décodé, json(), links(), historique, durée
├── request_builder.al    RequestBuilder : construction chaînée
├── response_reader.al    lecture d'une réponse (délais, taille, gzip / deflate, réutilisation)
├── timeout.al            Timeout (connexion, lecture, écriture, total), Deadline
├── redirect.al           RedirectPolicy (méthodes, origine, rétrogradation, boucles)
├── connection.al         Connection : TCP, TLS, tunnel CONNECT
├── connection_pool.al    ConnectionPool : réserve keep-alive par destination
├── retry_policy.al       RetryPolicy : quand et après combien de temps réessayer
├── proxy.al              Proxy : HTTP(S)_PROXY, NO_PROXY, identifiants
├── tls_config.al         TlsConfig : vérification, autorités, certificat client
├── user_agent.al         User-Agent par défaut et analyse
├── client_errors.al      erreurs et classification
└── README.md
```

## Exemples

```al
use web.client as http

r := http.get("https://exemple.org/recherche", params={"q": "chat noir"})
if r.ok():
    print(r.text())

notes := http.get_json("https://api.exemple.org/notes", bearer=jeton)
cree := http.post("https://api.exemple.org/notes", json={"titre": "Été"}, timeout=5)
envoi := http.post("https://exemple.org/upload", form={"titre": "CR"}, files=[("doc", "cr.pdf", octets, "application/pdf")])

c := http.Client(base_url="https://api.exemple.org/v1/", timeout=10, retries=3, headers={"Accept": "application/json"})
r2 := c.build("PATCH", "notes/7").json({"lu": true}).bearer(jeton).send()
c.close()
```

## Comportement par défaut

| Réglage                | Défaut                                                                  |
|------------------------|-------------------------------------------------------------------------|
| Délais                 | connexion 10 s, lecture 30 s (inactivité), écriture 30 s, total illimité |
| TLS                    | certificat et nom vérifiés, TLS 1.2 minimum                              |
| Redirections           | 10 au plus ; 303 → GET ; https → http refusé ; Authorization retiré hors origine |
| Reprises               | 2, méthodes idempotentes, erreurs réseau et 429 / 502 / 503 / 504, Retry-After |
| Connexions             | persistantes, 8 par destination, fermées après 60 s d'inactivité         |
| Réponses               | 100 Mio au plus, gzip / deflate décodés                                  |
| Cookies                | mémorisés et renvoyés (domaine, chemin, Secure, expiration)              |
| Mandataire             | aucun ; `proxy="env"` lit HTTPS_PROXY / HTTP_PROXY / NO_PROXY            |

Une connexion de réserve que le serveur a fermée pendant l'inactivité est remplacée sans erreur pour les
méthodes idempotentes.

## Erreurs

`ClientError`, `ClientConnectionError`, `ClientTimeoutError`, `ClientTlsError`, `ClientProxyError`,
`TooManyRedirects`, `ClientResponseError`, et `HttpStatusError` (de `web.http`) avec `raise_for_status()`.
`client_errors.is_retryable(e)` dit si une erreur est passagère.
