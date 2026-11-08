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
use io as _io
use asyncio as _aio
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
use web.server.websocket as _wsk
use web.server.streaming as _stream
use web.server.http2 as _h2
use thread.offload as _offload
use web.http.date_header as _date
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
        self.writer.background = true
        self.loop = _conc.EventLoop()
        self.shutdown = _shutdown.ShutdownController(c.timeouts.shutdown)
        self.listener = null
        self.accepting = false
        self.handled = 0
        self.errors = []                 # « Type : message » des exceptions de gestionnaires (fonction simple)
        self.waiting = []                # connexions dont la réponse vient d'un gestionnaire async en cours
        self.async_mode = false          # vrai pendant serve_forever_async / serve_async / serve_for_async
        self.websockets = []             # sessions WebSocket ouvertes (web.server.websocket.ServerWebSocket)
        self.streams = []                # réponses en flux en cours (web.server.streaming.Stream)
        self.h2_sessions = []            # connexions HTTP/2 (web.server.http2.H2Session)
        if isinstance(app, _dispatch.Router):
            app.debug = app.debug or c.debug

    # ---------------------------------------------------------------- cycle de vie

    # Ouvre l'écoute (idempotent) ; renvoie le serveur.
    func start():
        if self.listener != null:
            return self
        if self.config.tls != null:
            _tls.require()
        self.listener = _listener.Listener(self.config.host, self.config.port, self.config.backlog, true, self.config.reuse_port)
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
            for h in self.h2_sessions:
                h.close()
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

    # ---------------------------------------------------------------- service async
    #
    # Les gestionnaires `async func` (ou qui rendent une tâche) exigent une boucle async : la boucle cède la main
    # à l'ordonnanceur entre deux tours, si bien que les tâches avancent pendant que le serveur sert les autres
    # connexions. Une connexion dont la réponse est attendue garde ses requêtes suivantes en file (ordre HTTP).
    #
    #   await server.Server(app, cfg).serve_forever_async()

    async func serve_forever_async():
        self.start()
        self.async_mode = true
        if self.config.handle_signals:
            self.shutdown.install_signals()
        while not self.shutdown.is_stopped():
            await self._async_round()
        self._stop_accepting()
        self.manager.close_all()
        self._complete()
        self.close_websockets()
        self.close_streams()
        self.shutdown.uninstall_signals()
        self.async_mode = false

    async func serve_async(count, timeout=null):
        self.start()
        self.async_mode = true
        target := self.handled + count
        t0 := _time.monotonic()
        while self.handled < target and not self.shutdown.is_stopped():
            if timeout != null and _time.monotonic() - t0 > timeout:
                break
            await self._async_round()
        self.async_mode = false
        return self.handled

    async func serve_for_async(seconds):
        self.start()
        self.async_mode = true
        t0 := _time.monotonic()
        while _time.monotonic() - t0 < seconds and not self.shutdown.is_stopped():
            await self._async_round()
        self.async_mode = false
        return self.handled

    # Attente maximale sur les sockets pendant un tour async : nulle si des réponses async sont attendues, courte
    # sinon (les tâches de fond de l'application avancent aussi entre deux tours).
    func _async_wait():
        if len(self.waiting) > 0:
            return 0
        for ws in self.websockets:
            if ws.is_busy():
                return 0.002             # session qui attend autre chose que son socket (minuteur, E/S)
        for h in self.h2_sessions:
            if h.waiting():
                return 0
        if _offload.pending() > 0:
            return 0.002                 # calculs délégués à des fils : résultats relevés toutes les 2 ms
        if len(self.streams) > 0:
            return 0.01                  # producteurs de flux : minuteurs servis au plus 10 ms en retard
        return self.config.poll_interval if self.config.poll_interval < 0.05 else 0.05

    # Un tour de la boucle async : un tour de serveur, puis la main aux tâches prêtes. Les réponses async qui se
    # terminent sans vraie attente (intergiciels, calcul court) partent dans le même tour ; on ne dort 1 ms que si
    # une réponse attend encore une E/S ou un minuteur.
    async func _async_round():
        self.step(self._async_wait())
        k := 0
        while k < 32:
            await _aio.sleep(0)
            self._complete()
            if not self._tasks_progressing():
                return
            k += 1
        if len(self.waiting) > 0:
            await _aio.sleep(0.001)

    # Vrai si des tâches du serveur avancent sans attendre de socket : réponse async pas encore prête, session
    # WebSocket en train de traiter un message. La boucle leur laisse alors la main plusieurs fois de suite
    # (chaque tâche imbriquée coûte un passage par l'ordonnanceur).
    func _tasks_progressing():
        if len(self.waiting) > 0:
            return true
        for h in self.h2_sessions:
            if h.waiting():
                return true
        for ws in self.websockets:
            if ws.is_busy():
                return true
        return false

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
            h2_busy := false
            for h in self.h2_sessions:
                h.shutdown()
                if h.active() == 0:
                    h.close()
                else:
                    h2_busy = true
            if (self.shutdown.should_finish(self.manager) and not h2_busy) or self.shutdown.remaining() <= 0:
                for h in self.h2_sessions:
                    h.close()
                self.manager.close_all()
                self.shutdown.finish()
                return
        busy := len(self.manager.with_pending_work()) > 0
        if self._push_outgoing() and timeout > 0.005:
            timeout = 0.005
        socks := []
        if self.accepting:
            append(socks, self.listener.socket)
        for c in self.manager.readable_candidates():
            append(socks, c.raw_socket())
        live := []
        for h in self.h2_sessions:
            if not h.closed:
                append(live, h)
                append(socks, h.raw_socket())
        self.h2_sessions = live
        for ws in self.websockets:
            if ws.wake != null and not ws.closed:
                if ws.conn.has_buffered_input():
                    ws.notify()
                    busy = true
                else:
                    append(socks, ws.conn.raw_socket())
        ready := self.loop.wait(socks, 0 if busy else timeout)
        for s in ready:
            if self.accepting and s == self.listener.socket:
                self._accept_some()
            else:
                c := self.manager.by_socket(s)
                if c != null:
                    self._read(c)
                elif not self._wake_h2(s):
                    self._wake_websocket(s)
        for c in self.manager.all():
            if c.has_buffered_input() and not c.closed:
                self._read(c)
        _offload.poll()
        self._complete()
        for h in self.h2_sessions:
            if h.conn.has_buffered_input():
                h.on_readable()          # TLS : octets déjà déchiffrés, le socket brut ne se signalera plus
            h.poll()
        self._process(tick)
        self._expire()
        for st in self.streams:
            st.poll()

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
            try:
                # pas d'algorithme de Nagle : une réponse écrite en plusieurs fois (enregistrements TLS, trames
                # HTTP/2) n'attend pas l'accusé de réception retardé du client (40 ms)
                sock.set_option("no_delay", true)
            catch e:
                ignored := e
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
            if self.config.tls != null:
                alpn := null
                try:
                    alpn = s.alpn
                catch e:
                    alpn = null
                if alpn == "h2":
                    self._start_h2(conn, "")
                    continue
            else:
                conn.h2c = self.config.http2
            self.manager.add(conn)
            self._read(conn)

    func _read(conn):
        n := 0
        try:
            n = conn.read_available()
            if conn.h2_initial != null:
                self.manager.detach(conn)
                self._start_h2(conn, conn.h2_initial)
                return
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
            if conn.is_waiting():
                # le client est parti pendant un gestionnaire async : on annule la tâche (CancelledError à son
                # prochain await) et on libère la connexion, plutôt que de calculer une réponse que personne ne lira
                _aio.cancel(conn.in_flight[1])
                conn.in_flight = null
                self.manager.remove(conn)
                self.metrics.async_cancelled += 1
            elif conn.has_request():
                conn.closing = true
            else:
                self.manager.remove(conn)

    func _process(tick):
        pol := self.config.policy
        total := 0
        for conn in pol.order(self.manager.all(), tick):
            k := 0
            while not conn.closed and not conn.is_waiting() and conn.has_request() and k < pol.per_connection and total < pol.max_per_tick:
                self._handle(conn, conn.next_request())
                k += 1
                total += 1
            if conn.is_waiting():
                continue
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
            result := self.app(req)
            if _aio.is_future(result):
                return self._settle(result, req)
            return _dispatch.to_response(result, req)
        catch e:
            return self._handler_failure(req, e)

    # Tâche qui attend un gestionnaire async (fonction simple) et rend toujours une Response.
    async func _settle(pending, req):
        try:
            return _dispatch.to_response(await pending, req)
        catch e:
            return self._handler_failure(req, e)

    func _handler_failure(req, e):
        if _err.is_abort(e):
            d := _err.abort_details(e)
            return _dispatch.error_response(req, d[0], d[1])
        self._record_error(str(e.type) + " : " + str(e.message))
        return _dispatch.error_response(req, 500, str(e.type) + " : " + str(e.message) if self.config.debug else null)

    func _record_error(text):
        self.metrics.handler_error()
        append(self.errors, text)
        if len(self.errors) > 100:
            self.errors = self.errors[len(self.errors) - 100:len(self.errors)]

    func _collect_router_errors():
        if isinstance(self.app, _dispatch.Router) and len(self.app.errors) > 0:
            for e in self.app.errors:
                self._record_error(e)
            self.app.errors = []

    # Envoie les réponses async terminées ; abandonne (annule) celles des connexions fermées entre-temps.
    func _complete():
        if len(self.waiting) == 0:
            return
        pending := self.waiting
        self.waiting = []
        for conn in pending:
            entry := conn.in_flight
            if entry == null:
                continue
            fut := entry[1]
            if conn.closed:
                conn.in_flight = null
                _aio.cancel(fut)
                continue
            if not _aio.done(fut):
                append(self.waiting, conn)
                continue
            conn.in_flight = null
            resp := null
            if _aio.failed(fut) or _aio.cancelled(fut):
                resp = _dispatch.error_response(entry[0], 500, null)
                self._record_error("AsyncError : tâche de gestionnaire échouée ou annulée")
            else:
                resp = _aio.result(fut)
            self._collect_router_errors()
            self._respond(conn, entry[0], resp, entry[2])

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
            self._collect_router_errors()
        if _aio.is_future(resp):
            if not self.async_mode:
                # personne ne ferait avancer la tâche : erreur explicite plutôt qu'une connexion figée
                _aio.cancel(resp)
                self._record_error("ServerError : gestionnaire async servi par une boucle synchrone (utiliser serve_forever_async, serve_async ou web.server.serve_async)")
                resp = _dispatch.error_response(req, 500, "gestionnaire async : serveur lancé sans boucle async" if c.debug else null)
            else:
                conn.in_flight = [req, resp, t0]
                append(self.waiting, conn)
                return
        self._respond(conn, req, resp, t0)

    # Écrit la réponse d'une requête et met à jour la connexion, les mesures et le journal.
    func _respond(conn, req, resp, t0):
        c := self.config
        if "stream" in req.state and resp.status == 200:
            if self.async_mode:
                self._start_stream(conn, req, resp, t0)
                return
            self._record_error("ServerError : réponse en flux servie par une boucle synchrone (utiliser serve_forever_async, serve_async ou web.server.serve_async)")
            resp = _dispatch.error_response(req, 500, "flux : serveur lancé sans boucle async" if c.debug else null)
        if resp.status == 101 and "websocket" in req.state:
            if self.async_mode:
                self._start_websocket(conn, req, resp, t0)
                return
            self._record_error("ServerError : WebSocket servi par une boucle synchrone (utiliser serve_forever_async, serve_async ou web.server.serve_async)")
            resp = _dispatch.error_response(req, 500, "WebSocket : serveur lancé sans boucle async" if c.debug else null)
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
        if conn.outgoing != null:
            # gros fichier : la suite part en arrière-plan (_push_outgoing) ; bilan à la fin de l'envoi
            conn.outgoing["done"] = [req, resp, t0]
            return
        self._written(conn, req, resp, t0, sent)

    # Après l'envoi complet d'une réponse : compteurs, journal, fermeture éventuelle de la connexion.
    func _written(conn, req, resp, t0, sent):
        conn.requests_served += 1
        self.handled += 1
        dt := _time.monotonic() - t0
        self.metrics.request_done(req.method, resp.status, dt, _s.byte_len(req.body), sent)
        self._log(req, resp, sent, dt)
        if not resp.keep_alive or conn.closing:
            if not conn.has_request() or not resp.keep_alive:
                self.manager.remove(conn)

    # Fait avancer les envois de fichiers en arrière-plan dont le socket accepte des octets ; rend vrai si l'un
    # d'eux attend encore (la boucle ne dort alors que quelques millisecondes).
    func _push_outgoing():
        senders := []
        for c in self.manager.all():
            if c.outgoing != null and not c.closed:
                append(senders, c)
        if len(senders) == 0:
            return false
        socks := []
        for c in senders:
            append(socks, c.raw_socket())
        ready := []
        try:
            ready = _sk.wait(socks, "write", 0)
        catch e:
            ready = socks
        pending := false
        for c in senders:
            if not (c.raw_socket() in ready):
                pending = true
                if _time.monotonic() - c.outgoing["last"] > self.config.timeouts.write:
                    self.manager.remove(c)
                continue
            state := "timeout"
            try:
                state = _writer.push(c, self.writer.chunk_size)
            catch e:
                state = "error"
            if state == "pending":
                pending = true
            elif state == "done":
                o := c.outgoing
                c.outgoing = null
                d := o["done"]
                if d != null:
                    self._written(c, d[0], d[1], d[2], o["sent"])
            else:
                c.outgoing = null
                self.manager.remove(c)
        return pending

    # Poignée de main WebSocket : 101 écrit tel quel (Connection: Upgrade), la connexion quitte le HTTP et devient
    # une session async ; les octets déjà reçus après la poignée de main lui sont confiés.
    func _start_websocket(conn, req, resp, t0):
        info := req.state["websocket"]
        resp.headers.set("Date", _date.now())
        sent := 0
        try:
            sent = conn.send(_pw.write_response_head(resp), self.config.timeouts.write)
        catch e:
            self.manager.remove(conn)
            return
        conn.requests_served += 1
        self.handled += 1
        dt := _time.monotonic() - t0
        self.metrics.request_done(req.method, 101, dt, 0, sent)
        self._log(req, resp, sent, dt)
        p := conn.parser
        rest := _s.byte_slice(p.buffer, p.pos, _s.byte_len(p.buffer)) if p.pending() > 0 else ""
        self.manager.detach(conn)
        ws := _wsk.ServerWebSocket(conn, req, info["max_message"], info["protocol"], rest, self)
        append(self.websockets, ws)
        self.metrics.websockets_opened += 1
        self._ws_session(ws, info["handler"])

    async func _ws_session(ws, handler):
        try:
            r := handler(ws.request, ws)
            if _aio.is_future(r):
                await r
        catch e:
            if e.type != "CancelledError" and not ws.closed:
                self._record_error("WebSocket : " + str(e.type) + " : " + str(e.message))
                ws._send_close(1011, "erreur interne")
        try:
            if not ws.closed:
                await ws.close()
        catch e:
            ignored := e
        ws.closed = true
        ws.conn.close()
        kept := []
        for w in self.websockets:
            if w != ws:
                append(kept, w)
        self.websockets = kept

    # Réponse en flux : en-tête écrit (chunked en HTTP/1.1, fermeture en HTTP/1.0), la connexion quitte le HTTP et
    # le producteur async écrit le corps ; la connexion est fermée à la fin du flux.
    func _start_stream(conn, req, resp, t0):
        info := req.state["stream"]
        resp.body_stream = (x) => null        # marque « corps en flux » pour prepare_response
        _pw.prepare_response(resp, req.method, req.version, false, self.config.server_name)
        resp.body_stream = null
        sent := 0
        try:
            sent = conn.send(_pw.write_response_head(resp), self.config.timeouts.write)
        catch e:
            self.manager.remove(conn)
            return
        conn.requests_served += 1
        self.handled += 1
        dt := _time.monotonic() - t0
        self.metrics.request_done(req.method, 200, dt, 0, sent)
        self._log(req, resp, sent, dt)
        self.manager.detach(conn)
        chunked := resp.headers.has_token("transfer-encoding", "chunked")
        st := _stream.Stream(conn, req, chunked, info["sse"], info["keepalive"])
        append(self.streams, st)
        self.metrics.streams_opened += 1
        if req.method == "HEAD":
            st.close()
            return
        self._stream_session(st, info["producer"])

    async func _stream_session(st, producer):
        try:
            r := producer(st.request, st)
            if _aio.is_future(r):
                await r
        catch e:
            if e.type != "CancelledError":
                self._record_error("Stream : " + str(e.type) + " : " + str(e.message))
        st.close()
        kept := []
        for x in self.streams:
            if x != st:
                append(kept, x)
        self.streams = kept

    # ---------------------------------------------------------------- HTTP/2 (web.server.http2)

    func _start_h2(conn, initial):
        self.metrics.http2_sessions += 1
        h := _h2.H2Session(conn, self, initial)
        append(self.h2_sessions, h)
        h.on_readable()

    func _wake_h2(sock):
        for h in self.h2_sessions:
            if h.raw_socket() == sock:
                h.on_readable()
                return true
        return false

    # Requête d'un flux HTTP/2 : mêmes contrôles et même application qu'en HTTP/1.1 ; Response ou tâche.
    func _h2_call(req):
        c := self.config
        if not _rp.host_allowed(req, c.allowed_hosts):
            return _dispatch.error_response(req, 421, "hôte non servi ici")
        if c.trusted_proxies != null:
            req.state["client_ip"] = _rp.client_ip(req, c.trusted_proxies)
            req.state["scheme"] = _rp.scheme(req, c.trusted_proxies)
        else:
            req.state["client_ip"] = req.remote_address[0] if req.remote_address != null else null
            req.state["scheme"] = c.scheme()
        req.state["server"] = self
        req.state["http_version"] = "2"
        resp := self._call_app(req)
        self._collect_router_errors()
        if _aio.is_future(resp) and not self.async_mode:
            _aio.cancel(resp)
            self._record_error("ServerError : gestionnaire async servi par une boucle synchrone (utiliser serve_forever_async, serve_async ou web.server.serve_async)")
            return _dispatch.error_response(req, 500, null)
        return resp

    func _h2_done(req, resp, t0, sent):
        self.handled += 1
        dt := _time.monotonic() - t0
        self.metrics.request_done(req.method, resp.status, dt, _s.byte_len(req.body), sent)
        self._log(req, resp, sent, dt)

    # Réponse en flux (SSE) sur un flux HTTP/2 : même Stream et même producteur qu'en HTTP/1.1.
    func _h2_flux(pipe, req, info):
        st := _stream.Stream(pipe, req, false, info["sse"], info["keepalive"])
        append(self.streams, st)
        self.metrics.streams_opened += 1
        self._stream_session(st, info["producer"])
        return st

    # Termine tous les flux en cours (arrêt du serveur) : les producteurs voient flux.closed.
    func close_streams():
        for st in self.streams:
            st.close()

    func _wake_websocket(sock):
        for ws in self.websockets:
            if ws.wake != null and ws.conn.raw_socket() == sock:
                ws.notify()
                return

    # Ferme toutes les sessions WebSocket (1001 : le serveur s'en va).
    func close_websockets():
        for ws in self.websockets:
            if not ws.closed:
                ws._send_close(1001, "arrêt du serveur")
                ws.closed = true
                ws.conn.close()
                ws.notify()
        self.websockets = []

    func _log(req, resp, sent, dt):
        sink := self.config.access_log
        if sink == false or sink == null:
            return
        who := req.state["client_ip"] if "client_ip" in req.state and req.state["client_ip"] != null else "-"
        line := str(who) + " \"" + req.method + " " + req.target + " " + req.version + "\" " + str(resp.status) + " " + str(sent) + " " + str(to_int(dt * 1000)) + "ms"
        if sink == true:
            print(line)
            _io.flush()                  # sortie tamponnée quand elle est un fichier ou un tube (systemd, Docker)
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
    _io.flush()
    srv.serve_forever()
    return srv

# Comme serve, avec une boucle async : nécessaire dès qu'un gestionnaire est une `async func`.
#   await server.serve_async(app, "0.0.0.0", 8080)
async func serve_async(app, host="127.0.0.1", port=8080, cfg=null):
    c := cfg if cfg != null else _config.ServerConfig(host, port)
    c.host = host
    c.port = port
    c.handle_signals = true
    srv := Server(app, c).start()
    print("Serveur à l'écoute sur " + srv.url())
    _io.flush()
    await srv.serve_forever_async()
    return srv

# Interrompt un gestionnaire avec une réponse d'erreur (voir server_errors.abort).
func abort(status, message=null):
    _err.abort(status, message)
