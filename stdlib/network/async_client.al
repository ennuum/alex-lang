# ALEX STANDARD LIBRARY — network.async_client
#
# Réseau asynchrone (async / await, voir docs/ASYNC.md) : connexions TCP / TLS dont les lectures et écritures
# cèdent la main pendant l'attente, serveur TCP qui sert plusieurs clients à la fois, client HTTP/1.1 asynchrone
# et téléchargements concurrents.
#
#   c := await connect("exemple.org", 80, 5.0)            AsyncConnection : read, read_line, read_exact,
#   await c.write("...") ; l := await c.read_line()        read_until, read_all, write, close
#   r := await get("https://exemple.org/")                 network.http_client.Response
#   rs := await fetch_all([url1, url2, url3], 4)           au plus 4 requêtes en vol ; Result (value ou error)
#   srv := AsyncServer("127.0.0.1", 0, gestionnaire)       gestionnaire : async func(conn)
#   await srv.serve(10)                                     sert 10 connexions, concurremment
#
# Modèle : coroutines coopératives sur un seul fil ; l'attente d'un socket est un sondage non bloquant entrecoupé
# de asyncio.sleep (intervalle croissant de 1 à 20 ms), si bien que d'autres tâches avancent pendant ce temps.
# La résolution DNS et la poignée de main TLS restent bloquantes (bornées par le délai) : elles sont courtes.
#
# Erreurs : comme network.tcp / network.http_client (NetworkError, TimeoutError, HttpError, TlsError...) ;
# CancelledError si la tâche est annulée.

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use json as _json
use asyncio as _aio
use network.socket as _sk
use network.dns as _dns
use network.tls as _tls
use network.url as _url
use network.http_headers as _hh
use network.http_client as _hc
use network.compression as _z
use network.constants as _c

const MIN_POLL := 0.001
const MAX_POLL := 0.02

func _deadline(timeout):
    if timeout == null:
        return null
    return _time.monotonic() + timeout

func _left(deadline, what):
    if deadline == null:
        return null
    left := deadline - _time.monotonic()
    if left <= 0:
        raise("TimeoutError", what + " : délai dépassé")
    return left

class AsyncConnection:
    func init(sock):
        self.socket = sock            # network.socket.Socket ou network.tls.TlsSocket
        self.buffer = ""
        self.eof = false

    # Ajoute des octets au tampon ; false à la fin du flux.
    async func _fill(timeout):
        if self.eof:
            return false
        deadline := _deadline(timeout)
        delay := MIN_POLL
        while true:
            data := self.socket.try_recv(65536)
            if data != null:
                if data == "":
                    self.eof = true
                    return false
                self.buffer = self.buffer + data
                return true
            _left(deadline, "async_client.read")
            await _aio.sleep(delay)
            if delay < MAX_POLL:
                delay = delay * 2

    func _take(n):
        out := _n.bslice(self.buffer, 0, n)
        self.buffer = _n.bslice(self.buffer, n, _n.blen(self.buffer))
        return out

    # Octets disponibles (au plus max) ; "" à la fin du flux.
    async func read(max=65536, timeout=null):
        if _n.blen(self.buffer) == 0:
            await self._fill(timeout)
        k := _n.blen(self.buffer)
        if k > max:
            k = max
        return self._take(k)

    async func read_exact(n, timeout=null):
        deadline := _deadline(timeout)
        while _n.blen(self.buffer) < n:
            more := await self._fill(_left(deadline, "async_client.read_exact"))
            if not more:
                raise("NetworkError", "async_client.read_exact : connexion fermée après " + str(_n.blen(self.buffer)) + " octets sur " + str(n))
        return self._take(n)

    # Tout jusqu'au séparateur (exclu) ; à la fin du flux : le reste, ou null s'il est vide.
    async func read_until(sep, timeout=null, limit=1048576):
        deadline := _deadline(timeout)
        start := 0
        while true:
            i := _n.bfind(self.buffer, sep, start)
            if i >= 0:
                out := self._take(i)
                self._take(_n.blen(sep))
                return out
            if _n.blen(self.buffer) > limit:
                raise("NetworkError", "async_client.read_until : plus de " + str(limit) + " octets sans séparateur")
            start = _n.blen(self.buffer) - _n.blen(sep) + 1
            if start < 0:
                start = 0
            more := await self._fill(_left(deadline, "async_client.read_until"))
            if not more:
                if _n.blen(self.buffer) == 0:
                    return null
                return self._take(_n.blen(self.buffer))

    async func read_line(timeout=null, limit=1048576):
        line := await self.read_until("\n", timeout, limit)
        if line != null and _s.ends_with(line, "\r"):
            line = _n.bslice(line, 0, _n.blen(line) - 1)
        return line

    async func read_all(timeout=null):
        deadline := _deadline(timeout)
        while true:
            more := await self._fill(_left(deadline, "async_client.read_all"))
            if not more:
                return self._take(_n.blen(self.buffer))

    # Envoie tout (str ou octets) ; cède la main quand le tampon d'envoi du système est plein.
    async func write(data, timeout=null):
        raw := data
        if type(data) == "list":
            raw = _n.from_bytes(data)
        deadline := _deadline(timeout)
        total := _n.blen(raw)
        pos := 0
        delay := MIN_POLL
        while pos < total:
            chunk := _n.bslice(raw, pos, total)
            sent := 0
            try:
                sent = self.socket.send(chunk, 0)
            catch e:
                if e.type != "TimeoutError":
                    raise(e)
                sent = 0
            if sent > 0:
                pos += sent
                delay = MIN_POLL
                continue
            _left(deadline, "async_client.write")
            await _aio.sleep(delay)
            if delay < MAX_POLL:
                delay = delay * 2
        return total

    async func write_line(text, timeout=null):
        return await self.write(text + "\n", timeout)

    func peer_address():
        return self.socket.peer_address()

    func local_address():
        return self.socket.local_address()

    func close():
        self.socket.close()

    func is_closed():
        return self.socket.is_closed()

# Établit une connexion sans bloquer les autres tâches pendant l'attente de la réponse du serveur.
async func _connect_socket(addr, port, timeout):
    s := _sk.Socket(addr.family, "tcp")
    deadline := _deadline(timeout)
    r := _n.connect(s.handle, addr.host, port, 0)
    if r == 0:
        return s
    name := _n.errno_name(r)
    if name != "ETIMEDOUT" and name != "EAGAIN":
        s.close()
        _sk.fail("connect(" + _sk.format_address(addr.host, port) + ")", r)
    delay := MIN_POLL
    while true:
        ready := _n.wait([s.handle], "write", 0)
        if len(ready) > 0:
            r2 := _n.connect(s.handle, addr.host, port, 0)
            n2 := ""
            if r2 != 0:
                n2 = _n.errno_name(r2)
            if r2 == 0 or n2 == "EISCONN":
                return s
            if n2 != "ETIMEDOUT" and n2 != "EAGAIN" and n2 != "E114":
                s.close()
                _sk.fail("connect(" + _sk.format_address(addr.host, port) + ")", r2)
        if deadline != null and _time.monotonic() >= deadline:
            s.close()
            raise("TimeoutError", "connect(" + _sk.format_address(addr.host, port) + ") : délai dépassé")
        await _aio.sleep(delay)
        if delay < MAX_POLL:
            delay = delay * 2

# Connexion TCP (secure=false) ou TLS : AsyncConnection. Chaque adresse résolue est essayée dans l'ordre.
async func connect(host, port, timeout=30.0, secure=false, verify=true, ca_file=null, server_name=null, alpn=null):
    last := null
    for a in _dns.lookup(host, port, 0, "tcp"):
        try:
            s := await _connect_socket(a, port, timeout)
            if secure:
                name := server_name
                if name == null:
                    name = host
                try:
                    s = _tls.wrap_client(s, name, verify, ca_file, alpn, timeout)
                catch e:
                    s.close()
                    raise(e)
            return AsyncConnection(s)
        catch e:
            if e.type == "CancelledError" or e.type == "TlsError":
                raise(e)
            last = e
    raise(last)

# ---------------------------------------------------------------- serveur

class AsyncServer:
    # handler : async func(AsyncConnection) ; la connexion est fermée quand le gestionnaire se termine.
    func init(host, port, handler, backlog=128):
        family := 4
        addr := host
        if _dns.is_ipv6(host):
            family = 6
        self.socket = _sk.Socket(family, "tcp")
        self.socket.set_option("reuse_address", true)
        self.socket.bind(addr, port)
        self.socket.listen(backlog)
        self.handler = handler
        self.running = false
        self.served = 0
        self.errors = []
        self.tasks = []

    func port():
        return self.socket.local_address()[1]

    func stop():
        self.running = false

    async func _run(conn):
        try:
            await self.handler(conn)
        catch e:
            if e.type != "CancelledError":
                append(self.errors, e.type + ": " + e.message)
        conn.close()

    # Accepte les connexions (au plus max_connections, null : jusqu'à stop()) ; chaque client est servi par sa
    # propre tâche. Attend la fin des gestionnaires en cours avant de rendre la main.
    async func serve(max_connections=null):
        self.running = true
        delay := MIN_POLL
        while self.running and (max_connections == null or self.served < max_connections):
            r := null
            try:
                r = self.socket.accept(0)
            catch e:
                if e.type != "TimeoutError":
                    raise(e)
            if r == null:
                await _aio.sleep(delay)
                if delay < MAX_POLL:
                    delay = delay * 2
                continue
            delay = MIN_POLL
            self.served += 1
            append(self.tasks, self._run(AsyncConnection(r[0])))
        for t in self.tasks:
            await t
        self.tasks = []
        return self.served

    func close():
        self.socket.close()

# ---------------------------------------------------------------- HTTP

async func _read_headers(conn, timeout):
    h := _hh.Headers()
    total := 0
    while true:
        line := await conn.read_line(timeout, 65536)
        if line == null:
            raise("HttpError", "async_client : connexion fermée au milieu des en-têtes")
        if line == "":
            return h
        total += _n.blen(line)
        if total > 65536:
            raise("HttpError", "async_client : en-têtes trop longs")
        c := _s.find(line, ":")
        if c <= 0:
            raise("HttpError", "async_client : en-tête mal formé « " + line + " »")
        append(h.entries, [_s.trim(_s.substring(line, 0, c)), _s.trim(_s.substring(line, c + 1, len(line)))])

async func _read_body(conn, headers, timeout, max_body):
    te := _s.lower(headers.get("transfer-encoding", ""))
    if _s.contains(te, "chunked"):
        parts := []
        total := 0
        while true:
            line := await conn.read_line(timeout, 65536)
            if line == null:
                raise("HttpError", "async_client : corps « chunked » tronqué")
            semi := _s.find(line, ";")
            if semi >= 0:
                line = _s.substring(line, 0, semi)
            n := 0
            for ch in _s.lower(_s.trim(line)):
                d := _s.find("0123456789abcdef", str(ch))
                if d < 0:
                    raise("HttpError", "async_client : taille de morceau invalide")
                n = n * 16 + d
            if n == 0:
                while true:
                    t := await conn.read_line(timeout, 65536)
                    if t == null or t == "":
                        break
                return _s.join("", parts)
            total += n
            if total > max_body:
                raise("HttpError", "async_client : corps trop grand")
            append(parts, await conn.read_exact(n, timeout))
            await conn.read_exact(2, timeout)
    cl := headers.get_int("content-length")
    if cl != null:
        if cl > max_body:
            raise("HttpError", "async_client : corps trop grand")
        if cl == 0:
            return ""
        return await conn.read_exact(cl, timeout)
    return await conn.read_all(timeout)

# Requête HTTP/1.1 asynchrone (une connexion par requête, redirections suivies jusqu'à max_redirects).
async func request(method, target, data=null, json=null, headers=null, timeout=30.0, verify=true, ca_file=null, max_redirects=5, max_body=104857600):
    m := _s.upper(method)
    u := _url.parse(target)
    body := data
    ctype := null
    if json != null:
        body = _json.stringify(json)
        ctype = "application/json"
    elif type(data) == "dict":
        body = _url.urlencode(data)
        ctype = "application/x-www-form-urlencoded"
    hops := 0
    while true:
        if u.scheme != "http" and u.scheme != "https":
            raise("HttpError", "async_client : schéma « " + u.scheme + " » non pris en charge")
        start := _time.monotonic()
        conn := await connect(u.host, u.effective_port(), timeout, u.scheme == "https", verify, ca_file, null, ["http/1.1"])
        try:
            h := _hh.Headers(headers)
            h.set_default("Host", u.netloc())
            h.set_default("User-Agent", "Alex-async_client/1.0")
            h.set_default("Accept", "*/*")
            h.set_default("Accept-Encoding", _z.accept_encoding())
            if ctype != null:
                h.set_default("Content-Type", ctype)
            h.set("Connection", "close")
            if body != null or m == "POST" or m == "PUT" or m == "PATCH":
                b := body
                if b == null:
                    b = ""
                h.set("Content-Length", str(_n.blen(b)))
            req := m + " " + u.target() + " HTTP/1.1\r\n" + h.to_text() + "\r\n"
            if body != null:
                req = req + body
            await conn.write(req, timeout)
            status_line := await conn.read_line(timeout, 65536)
            while true:
                if status_line == null:
                    raise("HttpError", "async_client : réponse vide de " + u.origin())
                parts := _s.split(status_line, " ")
                if len(parts) < 2 or not _s.starts_with(parts[0], "HTTP/"):
                    raise("HttpError", "async_client : ligne de statut invalide « " + status_line + " »")
                status := to_int(parts[1])
                reason := ""
                if len(parts) > 2:
                    reason = _s.join(" ", parts[2:len(parts)])
                rh := await _read_headers(conn, timeout)
                if status >= 100 and status < 200:
                    status_line = await conn.read_line(timeout, 65536)
                    continue
                raw := ""
                if _c.response_has_body(status, m):
                    raw = await _read_body(conn, rh, timeout, max_body)
                conn.close()
                r := _hc.Response(status, reason, parts[0], rh, _z.decode(raw, rh.get("content-encoding"), max_body), u.str(), m)
                r.elapsed = _time.monotonic() - start
                if _c.is_redirect_status(status) and rh.has("location") and hops < max_redirects:
                    hops += 1
                    nxt := u.join(rh.get("location"))
                    if status == 303 or ((status == 301 or status == 302) and m == "POST"):
                        m = "GET"
                        body = null
                        ctype = null
                    u = nxt
                    break
                return r
        catch e:
            conn.close()
            raise(e)

async func get(target, headers=null, timeout=30.0, verify=true, ca_file=null):
    return await request("GET", target, null, null, headers, timeout, verify, ca_file)

async func post(target, data=null, json=null, headers=null, timeout=30.0, verify=true, ca_file=null):
    return await request("POST", target, data, json, headers, timeout, verify, ca_file)

async func put(target, data=null, json=null, headers=null, timeout=30.0):
    return await request("PUT", target, data, json, headers, timeout)

async func delete(target, headers=null, timeout=30.0):
    return await request("DELETE", target, null, null, headers, timeout)

# Résultat d'une opération concurrente : value, ou error (exception attrapée).
class Result:
    func init(value, error):
        self.value = value
        self.error = error

    func ok():
        return self.error == null

    func get():
        if self.error != null:
            raise(self.error)
        return self.value

async func _guarded(task):
    try:
        return Result(await task, null)
    catch e:
        if e.type == "CancelledError":
            raise(e)
        return Result(null, e)

# Exécute des fonctions async (sans argument) avec au plus `concurrency` en vol ; rend les Result dans l'ordre.
async func run_limited(functions, concurrency=8):
    results := []
    for f in functions:
        append(results, null)
    i := 0
    while i < len(functions):
        batch := []
        j := i
        while j < len(functions) and j < i + concurrency:
            append(batch, _guarded(functions[j]()))
            j += 1
        k := i
        for t in batch:
            results[k] = await t
            k += 1
        i = j
    return results

# Télécharge plusieurs URL en parallèle (GET) : liste de Result (value : Response).
async func fetch_all(urls, concurrency=8, timeout=30.0, verify=true, ca_file=null):
    fns := []
    for u in urls:
        append(fns, _fetcher(u, timeout, verify, ca_file))
    return await run_limited(fns, concurrency)

func _fetcher(u, timeout, verify, ca_file):
    return () => get(u, null, timeout, verify, ca_file)

# Attend plusieurs tâches et rend leurs résultats dans l'ordre (relance la première erreur).
async func gather(tasks):
    out := []
    for t in tasks:
        append(out, await t)
    return out
