# web.http — le protocole HTTP/1.1, sans réseau

`web.http` décrit et manipule des **messages HTTP** : requêtes, réponses, en-têtes, corps. Il ne lit ni n'écrit
sur le réseau : c'est le socle commun de `web.client` (qui envoie des requêtes) et de `web.server` (qui en reçoit).
Tout est écrit en ALEX ; les seules dépendances sont `web.url`, `string`, `json` et `time`.

Références : RFC 9110 (sémantique), RFC 9112 (HTTP/1.1), RFC 6265 (cookies), RFC 8187 (paramètres non ASCII).

## Architecture

```text
stdlib/web/http/
├── http.al              point d'entrée : raccourcis Request, Response, parse_*, write_*
├── method.al            méthodes : sûre, idempotente, corps attendu, méthode après redirection
├── status_code.al       statuts : constantes, phrases de raison, classes, reprise, corps interdit
├── version.al           HTTP/1.0, HTTP/1.1 (et 2, 3 reconnues pour répondre 505)
├── request.al           Request : chemin, requête, corps texte/JSON/formulaire, cookies, Accept, Basic/Bearer
├── response.al          Response + text, html, json, redirect, error, file, stream ; Set-Cookie
├── headers.al           Headers : ordonnés, multi-valeurs, insensibles à la casse, validés
├── header_name.al       noms canoniques, hop-by-hop, singletons, en-têtes sensibles
├── header_value.al      listes, paramètres, guillemets, qualités (q=), directives, RFC 8187
├── message_body.al      cadrage (length / chunked / close), chunked incrémental, JSON, formulaire
├── content_type.al      MediaType, jokers, charset, table des extensions
├── content_length.al    analyse stricte (anti request smuggling)
├── date_header.al       dates HTTP (IMF-fixdate, RFC 850, asctime), Retry-After
├── request_target.al    origin-form, absolute-form, authority-form, asterisk-form
├── protocol_parser.al   RequestParser / ResponseParser incrémentaux, limites
├── protocol_writer.al   préparation (Date, Server, Content-Length, Connection) et écriture
├── http_errors.al       erreurs, chacune associée au statut HTTP à renvoyer
└── README.md
```

## Exemple

```al
use web.http as http

req := http.parse_request("POST /notes?brouillon=1 HTTP/1.1\r\nHost: exemple.org\r\nContent-Type: application/json\r\nContent-Length: 17\r\n\r\n{\"titre\":\"Été\"}")
print(req.method, req.path(), req.query_param("brouillon"))   # POST /notes 1
print(req.json()["titre"])                                     # Été

resp := http.json({"id": 42}, 201)
resp.set_cookie("sid", "abc123", 3600)
print(http.write_response(resp, req))
```

## Analyse incrémentale

Les analyseurs reçoivent les octets au fil de l'eau et rendent les messages complets ; ils gèrent le
pipelining, `Expect: 100-continue`, les corps `chunked` et les corps « jusqu'à la fermeture » (réponses).

```al
use web.http.protocol_parser as pp

p := pp.RequestParser(pp.Limits(8192, 65536, 100, 1048576))
for r in p.feed(octets_recus):
    traiter(r)
```

| Limite             | Défaut   | Dépassement                 |
|--------------------|----------|-----------------------------|
| ligne de requête   | 8 Kio    | 414 URI Too Long            |
| section d'en-têtes | 64 Kio   | 431                         |
| nombre d'en-têtes  | 100      | 431                         |
| corps              | 10 Mio   | 413 Content Too Large       |

## Sécurité

- Aucun CR, LF ni NUL n'est accepté dans un nom ou une valeur d'en-tête, ni dans une cible : pas d'injection.
- `Content-Length` est strict (chiffres seuls, valeurs répétées identiques) ; avec `Transfer-Encoding`, la
  requête est refusée ; les lignes repliées et les espaces avant « : » aussi.
- Les erreurs d'analyse portent le statut à renvoyer : `http_errors.status_for(e)` (400, 413, 414, 431, 501, 505).
- `Headers.redacted()` masque `Authorization`, `Cookie`, `Set-Cookie`… avant journalisation.

## Erreurs

`HttpError`, `HttpParseError`, `HttpHeaderError`, `HttpMethodError`, `HttpVersionError`, `HttpLimitError`,
`HttpStatusError` — voir `http_errors.al`.
