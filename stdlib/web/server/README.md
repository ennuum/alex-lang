# web.server — serveur HTTP/1.1

`web.server` sert des applications web : routes typées, fichiers statiques, intergiciels, HTTPS, connexions
persistantes, délais et limites contre les abus, mesures, arrêt propre. Le protocole vient de `web.http`, le HTML
des pages d'erreur et des listes de dossiers de `web.html`, le réseau de `network.tcp` / `network.tls`.

## Architecture

```text
stdlib/web/server/
├── server.al               point d'entrée : Server, App, serve, start, abort
├── server_config.al        ServerConfig (profils development / production)
├── server_limits.al        Limits : ligne, en-têtes, corps, connexions, pipelining
├── timeout.al              Timeouts : en-têtes, corps, inactivité, écriture, TLS, arrêt
├── listener.al             Listener : écoute TCP, acceptation non bloquante
├── connection.al           ServerConnection : lecture non bloquante, analyse incrémentale, file de requêtes
├── connection_manager.al   ConnectionManager : admission, délais, fermeture
├── request_parser.al       erreurs -> statuts, Host autorisés, IP réelle derrière mandataire, chemin de routage
├── response_writer.al      ResponseWriter : en-têtes, corps str / fichier / flux, 100 Continue
├── request_dispatch.al     Router : routes, montages, statique, intergiciels (logger, cors, compress…)
├── static_files.al         StaticFiles : chemins sûrs, ETag, 304, plages 206 / 416, index, repli SPA
├── directory_listing.al    liste HTML d'un dossier
├── keep_alive.al           KeepAlivePolicy : persistance des connexions
├── graceful_shutdown.al    ShutdownController : stop(), INT / TERM, délai de grâce
├── concurrency.al          EventLoop, Policy (équité entre connexions)
├── tls_server.al           TlsServerConfig, HSTS, certificat de développement
├── server_metrics.al       Metrics : compteurs, durées, export Prometheus
├── server_errors.al        erreurs, abort(statut)
└── README.md
```

## Exemple

```al
use web.server as server
use web.server.request_dispatch as rd

func voir(req):
    n := notes_trouver(req.route_params["id"])
    if n == null:
        server.abort(404, "note introuvable")
    return n                                   # dict -> JSON

app := server.App()
app.middleware(rd.logger())
app.middleware(rd.security_headers())
app.get("/", (req) => "<h1>Notes</h1>")
app.get("/notes/{id:int}", voir, "note")
app.post("/notes", (req) => (notes_creer(req.json()), 201))
app.static("/static", "public", null, false, 3600)
server.serve(app, "0.0.0.0", 8080)             # Ctrl+C : arrêt propre
```

Résultats acceptés d'un gestionnaire : `Response`, `str` (HTML s'il commence par « < », texte sinon),
`dict` / `list` (JSON), `(corps, statut[, en-têtes])`, `int` (statut seul), `Document` / `Element` de `web.html`,
`null` (204).

## Modèle d'exécution

Un seul fil et une boucle d'événements : toutes les connexions sont surveillées ensemble et lues sans blocage ;
une requête n'est traitée qu'une fois entièrement reçue (un client lent ne bloque pas les autres pendant l'envoi
de sa requête). Les gestionnaires ordinaires s'exécutent l'un après l'autre : pour un calcul long, déléguer à un
fil (`thread`) ou à une file de travaux. Pour plusieurs cœurs, lancer plusieurs processus derrière un répartiteur.

### Gestionnaires async

Un gestionnaire peut être une `async func` (ou rendre une tâche) : pendant qu'il attend (`await` d'une E/S, d'un
minuteur), le serveur continue de servir les autres connexions. Il faut alors une boucle async :

```al
async func voir(req):
    note := await base.trouver(req.route_params["id"])
    return note

app.get("/notes/{id:int}", voir)
await server.serve_async(app, "0.0.0.0", 8080)          # ou await srv.serve_forever_async()
```

- Variantes de `Server` : `serve_forever_async()`, `serve_async(n, délai)`, `serve_for_async(s)`.
- Ordre HTTP : une connexion qui attend une réponse async garde ses requêtes suivantes (pipelining) en file.
- Exceptions et `abort()` dans une `async func` donnent les mêmes réponses d'erreur qu'en synchrone.
- Client parti pendant l'attente : la tâche est annulée (`CancelledError` à son prochain `await`), la connexion
  libérée ; compteur `async_cancelled` dans les mesures.
- Servi par une boucle synchrone (`serve_forever`), un gestionnaire async est refusé par une 500 explicite
  (message dans `srv.errors`) plutôt que de figer la connexion.
- Les intergiciels synchrones de ce module qui transforment la réponse (`logger`, `cors`, `compress`,
  `security_headers`, `request_id`, `timing`) ne peuvent pas attendre une réponse async : les placer autour de routes
  synchrones, ou utiliser des intergiciels async (par exemple ceux du framework alweb).

Mesure (2 cœurs, 8 clients sur `/rapide` pendant que 8 autres appellent un `/lent` de 100 ms) : 1 092 req/s sur
`/rapide` (médiane 5 ms) contre 9 req/s (médiane 816 ms) avec un gestionnaire synchrone ; aucun surcoût mesurable
sur une route synchrone (1 596 contre 1 568 req/s). Tests : `tests/web/test_web_server_async.al`.

## Protections par défaut

| Risque                         | Défense                                                           |
|--------------------------------|-------------------------------------------------------------------|
| requêtes géantes               | 414 / 431 / 413 selon la partie, avant accumulation               |
| clients lents (slowloris)      | délais d'en-têtes (15 s), de corps (60 s), d'inactivité (15 s)    |
| trop de connexions             | 503 immédiat au-delà de 1024                                      |
| contrebande de requêtes        | Content-Length strict, CL + TE refusé, obs-fold refusé            |
| traversée de dossiers          | segments décodés un à un, « .. » / « \ » / NUL refusés, realpath  |
| DNS rebinding                  | `allowed_hosts` (421)                                             |
| usurpation d'IP                | en-têtes de mandataire crus seulement depuis `trusted_proxies`    |
| fuite d'informations           | détail des exceptions seulement en mode `debug`                   |

## Arrêt propre

`srv.stop()` (ou INT / TERM avec `handle_signals`) : plus de nouvelles connexions, connexions inactives fermées,
requêtes en cours terminées avec `Connection: close`, puis arrêt — au plus tard après `timeouts.shutdown`
secondes.

## Mesures

```al
app.get("/metrics", (req) => req.state["server"].metrics_response("prometheus"))
```

## Erreurs

`ServerError`, `ServerConfigError`, `RouteError`, et `HttpAbort` (levée par `abort`).
