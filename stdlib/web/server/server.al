# ALEX STANDARD LIBRARY — web.server
#
# Point d'entrée du serveur HTTP/1.1 : Server relie l'écoute (listener), les connexions (connection,
# connection_manager), l'analyse incrémentale (web.http + request_parser), l'aiguillage (request_dispatch.Router
# ou une simple fonction), l'écriture des réponses (response_writer), la persistance (keep_alive), les délais
# (timeout), les limites (server_limits), HTTPS (tls_server), les mesures (server_metrics) et l'arrêt propre
# (graceful_shutdown), dans une boucle d'événements à un seul fil (concurrency).
#
# | Module                        | Rôle                                                              |
# |-------------------------------|-------------------------------------------------------------------|
# | web.server (ce module)        | Server, App, serve, start                                         |
# | web.server.request_dispatch   | Router : routes typées, montages, statique, intergiciels, erreurs |
# | web.server.static_files / directory_listing | fichiers statiques sûrs (ETag, 304, plages), listes |
# | web.server.server_config / server_limits / timeout / keep_alive | réglages                       |
# | web.server.listener / connection / connection_manager | sockets et connexions                   |
# | web.server.request_parser / response_writer | entrée et sortie du protocole                     |
# | web.server.tls_server         | HTTPS, HSTS, certificat de développement                          |
# | web.server.concurrency        | boucle d'événements, équité                                       |
# | web.server.graceful_shutdown  | arrêt propre (stop(), INT, TERM)                                  |
# | web.server.server_metrics     | mesures, export Prometheus                                        |
# | web.server.server_errors      | erreurs, abort(statut)                                            |
#
#   use web.server as server
#   app := server.App()
#   app.get("/", (req) => "<h1>Bonjour</h1>")
#   app.get("/salut/{nom}", (req) => {"salut": req.route_params["nom"]})
#   app.post("/echo", (req) => (req.text(), 200))
#   app.static("/static", "public")
#   server.serve(app, "127.0.0.1", 8080)              # bloquant ; Ctrl+C : arrêt propre
#
#   srv := server.Server(app, server.config("127.0.0.1", 0)).start()   # port choisi par le système
#   srv.url("/")                                       # http://127.0.0.1:41233/
#   srv.serve(10)                                      # traite 10 requêtes puis rend la main
#   srv.stop()                                         # arrêt propre (les requêtes en cours finissent)
#
# Erreurs : ServerError, ServerConfigError, RouteError ; abort(statut) dans un gestionnaire.

from core use len, type, to_int
from collections use append
use string as _s
use time as _time
use network.socket as _sk
use web.server.server_errors as _err
use web.server.server_config as _config
use web.server.listener as _listener
use web.server.connection as _conn
use web.server.connection_manager as _manager
use web.server.request_parser as _rp
use web.server.response_writer as _writer
use web.server.request_dispatch as _dispatch
use web.server.server_metrics as _metrics
use web.server.graceful_shutdown as _shutdown
use web.server.concurrency as _conc
use web.server.tls_server as _tls
use web.http.protocol_writer as _pw
use web.http.response as _response

class Server:
    # app : Router (web.server.request_dispatch) ou fonction (req) -> résultat ; config : ServerConfig.
    func init(app, config=null):
        if app == null:
            _err.server_error("Server", "application (Router ou fonction) requise")
        self.app = app
        self.config = (config if config != null else _config.ServerConfig()).validate()
        c := self.config
        self.metrics = _metrics.Metrics()
        self.manager = _manager.ConnectionManager(c.limits, c.timeouts, self.metrics)
        self.writer = _writer.ResponseWriter(c.server_name, c.timeouts.write, 65536, c.keep_alive)
        self.loop = _conc.EventLoop()
        self.shutdown = _shutdown.ShutdownController(c.timeouts.shutdown)
        self.listener = null
        self.accepting = false
        self.handled = 0
        self.errors = []                 # « Type : message » des exceptions de gestionnaires (fonction simple)
        if isinstance(app, _dispatch.Router):
            app.debug = app.debug or c.debug

    # ---------------------------------------------------------------- cycle de vie

    # Ouvre l'écoute (idempotent) ; renvoie le serveur.
    func start():
        if self.listener != null:
            return self
        if self.config.tls != null:
            _tls.require()
        self.listener = _listener.Listener(self.config.host, self.config.port, self.config.backlog)
        self.accepting = true
        return self

    func is_running():
        return self.listener != null and not self.shutdown.is_stopped()

    func port():
        self.start()
        return self.listener.port()

    func address():
        self.start()
        return self.listener.address()

    func url(path="/"):
        self.start()
        return self.listener.url(self.config.scheme(), path)

    # Arrêt : propre par défaut (requêtes en cours terminées, délai de grâce), immédiat sinon.
    func stop(graceful=true, grace=null):
        if not graceful:
            self._stop_accepting()
            self.manager.close_all()
            self.shutdown.request("stop", 0)
            self.shutdown.finish()
            return
        self.shutdown.request("stop", grace)

    func close():
        self.stop(false)

    func __enter__():
        return self.start()

    func __exit__(a, b, c):
        self.close()

    # Sert jusqu'à l'arrêt (stop(), ou signal INT / TERM si config.handle_signals).
    func serve_forever():
        self.start()
        if self.config.handle_signals:
            self.shutdown.install_signals()
        while not self.shutdown.is_stopped():
            self.step(self.config.poll_interval)
        self._stop_accepting()
        self.manager.close_all()
        self.shutdown.uninstall_signals()

    # Sert jusqu'à avoir traité count requêtes de plus (ou jusqu'à l'arrêt) ; timeout : durée maximale (s).
    func serve(count, timeout=null):
        self.start()
        target := self.handled + count
        t0 := _time.monotonic()
        while self.handled < target and not self.shutdown.is_stopped():
            if timeout != null and _time.monotonic() - t0 > timeout:
                break
            self.step(self.config.poll_interval)
        return self.handled

    # Sert pendant seconds secondes.
    func serve_for(seconds):
        self.start()
        t0 := _time.monotonic()
        while _time.monotonic() - t0 < seconds and not self.shutdown.is_stopped():
            self.step(0.05)
        return self.handled

    func _stop_accepting():
        if self.listener != null and self.accepting:
            self.accepting = false
            self.listener.close()

    # ---------------------------------------------------------------- boucle

    # Un tour de boucle : accepte, lit, traite les requêtes complètes, applique les délais. timeout : attente
    # maximale d'activité (secondes).
    func step(timeout=0.5):
        self.start()
        self.shutdown.poll()
        tick := self.loop.tick()
        if self.shutdown.is_draining():
            self._stop_accepting()
            self.manager.close_idle()
            if self.shutdown.should_finish(self.manager):
                self.manager.close_all()
                self.shutdown.finish()
                return
        busy := len(self.manager.with_pending_work()) > 0
        socks := []
        if self.accepting:
            append(socks, self.listener.socket)
        for c in self.manager.readable_candidates():
            append(socks, c.raw_socket())
        ready := self.loop.wait(socks, 0 if busy else timeout)
        for s in ready:
            if self.accepting and s == self.listener.socket:
                self._accept_some()
            else:
                c := self.manager.by_socket(s)
                if c != null:
                    self._read(c)
        for c in self.manager.all():
            if c.has_buffered_input() and not c.closed:
                self._read(c)
        self._process(tick)
        self._expire()

    func _accept_some():
        k := 0
        while k < self.config.policy.accept_per_tick:
            k += 1
            r := self.listener.try_accept()
            if r == null:
                return
            sock := r[0]
            addr := r[1]
            if not self.manager.can_accept() or not self.shutdown.is_running():
                self.metrics.connection_rejected()
                try:
                    sock.send(_pw.simple_error(503, "serveur occupé", self.config.server_name), 1.0)
                catch e:
                    ignored := e
                sock.close()
                continue
            local := null
            try:
                local = sock.local_address()
            catch e:
                local = null
            s := sock
            if self.config.tls != null:
                try:
                    s = self.config.tls.wrap(sock, self.config.timeouts.handshake)
                catch e:
                    self.metrics.tls_handshake_failures += 1
                    try:
                        sock.close()
                    catch e2:
                        ignored := e2
                    continue
            conn := _conn.ServerConnection(s, addr, self.config.tls != null, self.config.limits, local)
            self.manager.add(conn)
            self._read(conn)

    func _read(conn):
        n := 0
        try:
            n = conn.read_available()
        catch e:
            st := _rp.error_status(e)
            self.metrics.protocol_error()
            # les requêtes complètes déjà reçues sont servies d'abord ; l'erreur ferme ensuite la connexion
            while conn.has_request() and not conn.closed:
                self._handle(conn, conn.next_request())
            if not conn.closed:
                self.writer.write_error(conn, st[0], st[1])
            self.manager.remove(conn)
            return
        if n == -1:
            if conn.has_request():
                conn.closing = true
            else:
                self.manager.remove(conn)

    func _process(tick):
        pol := self.config.policy
        total := 0
        for conn in pol.order(self.manager.all(), tick):
            k := 0
            while not conn.closed and conn.has_request() and k < pol.per_connection and total < pol.max_per_tick:
                self._handle(conn, conn.next_request())
                k += 1
                total += 1
            if not conn.closed and not conn.has_request() and conn.wants_continue():
                try:
                    self.writer.write_continue(conn)
                catch e:
                    self.manager.remove(conn)
            if not conn.closed and conn.closing and not conn.has_request():
                self.manager.remove(conn)

    func _expire():
        for pair in self.manager.expired():
            conn := pair[0]
            reason := pair[1]
            if reason == "header" or reason == "body":
                self.writer.write_error(conn, 408, "délai de requête dépassé")
                self.metrics.connection_timed_out()
            self.manager.remove(conn)

    # ---------------------------------------------------------------- requêtes

    func _call_app(req):
        if isinstance(self.app, _dispatch.Router):
            return self.app.dispatch(req)
        try:
            return _dispatch.to_response(self.app(req), req)
        catch e:
            if _err.is_abort(e):
                d := _err.abort_details(e)
                return _dispatch.error_response(req, d[0], d[1])
            self.metrics.handler_error()
            append(self.errors, str(e.type) + " : " + str(e.message))
            if len(self.errors) > 100:
                self.errors = self.errors[len(self.errors) - 100:len(self.errors)]
            return _dispatch.error_response(req, 500, str(e.type) + " : " + str(e.message) if self.config.debug else null)

    func _handle(conn, req):
        t0 := _time.monotonic()
        c := self.config
        resp := null
        if not _rp.host_allowed(req, c.allowed_hosts):
            resp = _dispatch.error_response(req, 421, "hôte non servi ici")
        else:
            if c.trusted_proxies != null:
                req.state["client_ip"] = _rp.client_ip(req, c.trusted_proxies)
                req.state["scheme"] = _rp.scheme(req, c.trusted_proxies)
            else:
                req.state["client_ip"] = req.remote_address[0] if req.remote_address != null else null
                req.state["scheme"] = c.scheme()
            req.state["server"] = self
            resp = self._call_app(req)
            if isinstance(self.app, _dispatch.Router) and len(self.app.errors) > 0:
                for e in self.app.errors:
                    append(self.errors, e)
                    self.metrics.handler_error()
                self.app.errors = []
        if conn.requests_served + 1 >= c.limits.max_requests_per_connection:
            conn.closing = true
        # pendant un arrêt, les requêtes déjà reçues (pipelining) sont servies ; la dernière ferme la connexion
        draining := self.shutdown.is_draining() and not conn.has_request()
        keep := c.keep_alive.decide(req, resp, conn, draining) and not conn.eof
        sent := 0
        try:
            sent = self.writer.write(conn, req, resp, keep)
        catch e:
            self.manager.remove(conn)
            self.metrics.request_done(req.method, resp.status, _time.monotonic() - t0, _s.byte_len(req.body), sent)
            self.handled += 1
            return
        conn.requests_served += 1
        self.handled += 1
        dt := _time.monotonic() - t0
        self.metrics.request_done(req.method, resp.status, dt, _s.byte_len(req.body), sent)
        self._log(req, resp, sent, dt)
        if not resp.keep_alive or conn.closing:
            if not conn.has_request() or not resp.keep_alive:
                self.manager.remove(conn)

    func _log(req, resp, sent, dt):
        sink := self.config.access_log
        if sink == false or sink == null:
            return
        who := req.state["client_ip"] if "client_ip" in req.state and req.state["client_ip"] != null else "-"
        line := str(who) + " \"" + req.method + " " + req.target + " " + req.version + "\" " + str(resp.status) + " " + str(sent) + " " + str(to_int(dt * 1000)) + "ms"
        if sink == true:
            print(line)
        else:
            sink(line)

    # ---------------------------------------------------------------- diagnostic

    # Réponse des mesures (JSON, ou texte Prometheus si format == "prometheus").
    func metrics_response(format="json"):
        if format == "prometheus":
            r := _response.text(self.metrics.to_prometheus())
            r.headers.set("Content-Type", "text/plain; version=0.0.4; charset=utf-8")
            return r
        snap := self.metrics.snapshot()
        snap["connections"]["phases"] = self.manager.stats()["phases"]
        return _response.json(snap)

    func stats():
        return self.metrics.snapshot()

# ---------------------------------------------------------------- fonctions

# Routeur d'application (web.server.request_dispatch.Router).
func App():
    return _dispatch.Router()

func Router():
    return _dispatch.Router()

func config(host="127.0.0.1", port=8080):
    return _config.ServerConfig(host, port)

# Serveur démarré (écoute ouverte), sans boucle : à servir avec serve_forever(), serve(n) ou step().
func start(app, host="127.0.0.1", port=8080, cfg=null):
    c := cfg if cfg != null else _config.ServerConfig(host, port)
    if cfg != null:
        c.host = host
        c.port = port
    return Server(app, c).start()

# Sert app jusqu'à l'arrêt (Ctrl+C / TERM : arrêt propre). Affiche l'adresse d'écoute.
func serve(app, host="127.0.0.1", port=8080, cfg=null):
    c := cfg if cfg != null else _config.ServerConfig(host, port)
    c.host = host
    c.port = port
    c.handle_signals = true
    srv := Server(app, c).start()
    print("Serveur à l'écoute sur " + srv.url())
    srv.serve_forever()
    return srv

# Interrompt un gestionnaire avec une réponse d'erreur (voir server_errors.abort).
func abort(status, message=null):
    _err.abort(status, message)
