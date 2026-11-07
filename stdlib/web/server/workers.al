# ALEX STANDARD LIBRARY — web.server.workers
#
# Plusieurs processus sur le même port, pour utiliser plusieurs cœurs : le programme est lancé une fois (le
# MAÎTRE), qui relance N copies de lui-même (les OUVRIERS). Chaque ouvrier écoute le même port avec SO_REUSEPORT ;
# le noyau répartit les connexions entre eux. Le maître relance un ouvrier qui meurt, relaie INT / TERM (arrêt
# propre de tous), et un ouvrier s'arrête seul si le maître disparaît.
#
#   use web.server as server
#   use web.server.workers as workers
#
#   app := server.App()
#   app.get("/", (req) => "Bonjour")
#   await workers.serve(app, "0.0.0.0", 8080, 4)      # 4 ouvriers (0 : un par cœur)
#
# Le même fichier s'exécute dans le maître et dans chaque ouvrier : tout ce qui précède `serve` (création de
# l'application, connexion à une base...) se fait dans chaque processus. `workers.is_worker()` /
# `workers.worker_index()` permettent de distinguer. Pas d'état partagé en mémoire entre ouvriers : sessions,
# caches et compteurs vont dans une base, un fichier ou un service.
#
# Supervisor sert aussi seul (tests, outils) : Supervisor(n, hôte, port).start(), wait_ready(), step(), stop().
#
# Services du maître : serve(..., env, services) ou sup.add_service(s). Un service est un objet qui a step(délai)
# (attend au plus délai secondes un évènement puis le traite, par exemple un serveur de base de données local) et,
# s'il le veut, shutdown(). Le maître les fait tourner à la place de ses pauses, y compris pendant l'arrêt des
# ouvriers (qui peuvent finir leurs requêtes), et les arrête après eux. env : variables ajoutées à celles des
# ouvriers (adresse d'un service, par exemple).
#
# Rechargement à chaud (développement) : serve(..., reload=true) ou Supervisor(...).watch([dossiers]) : le maître
# surveille les fichiers .al (racine du projet par défaut) et relance les ouvriers quand l'un change ; un
# programme qui ne démarre plus (erreur de syntaxe) est relancé à la modification suivante.
#
# Limites : POSIX (SO_REUSEPORT) ; un port explicite, ou 0 (le maître choisit alors un port libre et le transmet).

from core use len, type, to_int
from collections use append, keys
use os as _os
use io as _io
use time as _time
use asyncio as _aio
use concurrency.thread as _thread
use process as _proc
use process.process_signal as _psig
use signal as _signal
use network.utils as _nu
use web.server as _server
use web.server.server_config as _config

const ENV_WORKER := "ALEX_WEB_WORKER"
const ENV_PORT := "ALEX_WEB_PORT"
const ENV_MASTER := "ALEX_WEB_MASTER"
const ENV_READY := "ALEX_WEB_READY"       # dossier où chaque ouvrier signale qu'il écoute (fichier <index>)

# Vrai dans un processus ouvrier lancé par un Supervisor.
func is_worker():
    v := _os.getenv(ENV_WORKER)
    return v != null and v != ""

# Numéro de l'ouvrier (0..n-1), ou null dans le maître.
func worker_index():
    return to_int(_os.getenv(ENV_WORKER)) if is_worker() else null

# Nombre d'ouvriers par défaut : un par cœur.
func default_count():
    try:
        n := _thread.cpu_count()
        return n if n > 0 else 1
    catch e:
        return 1

# Sert app avec count ouvriers (0 ou null : un par cœur). Dans le maître : lance et surveille les ouvriers jusqu'à
# INT / TERM, puis rend le Supervisor ; dans un ouvrier : sert (boucle async) jusqu'à l'arrêt, puis rend le Server.
async func serve(app, host="127.0.0.1", port=8080, count=0, cfg=null, quiet=false, reload=false, env=null, services=null):
    if is_worker():
        return await _serve_worker(app, host, cfg)
    n := count if count != null and count > 0 else default_count()
    sup := Supervisor(n, host, port, null, env)
    if services != null:
        for s in services:
            sup.add_service(s)
    if reload:
        sup.watch(null, quiet)
    sup.start()
    if not quiet:
        print("Serveur à l'écoute sur http://" + (host if host != "0.0.0.0" and host != "" else "127.0.0.1") + ":" + str(sup.port) + "/ (" + str(n) + " ouvrier" + ("s" if n > 1 else "") + ", maître " + str(_os.pid()) + ")")
        _io.flush()
    sup.run()
    return sup

async func _serve_worker(app, host, cfg):
    c := cfg if cfg != null else _config.ServerConfig(host, 0)
    c.host = host
    c.port = to_int(_os.getenv(ENV_PORT))
    c.reuse_port = true
    c.handle_signals = true
    srv := _server.Server(app, c).start()
    _signal_ready()
    master := _os.getenv(ENV_MASTER)
    watcher := _watch_master(srv, to_int(master) if master != null and master != "" else null)
    await srv.serve_forever_async()
    _aio.cancel(watcher)
    return srv

# L'ouvrier écoute : il l'écrit pour son maître (fichier <index> contenant son pid).
func _signal_ready():
    d := _os.getenv(ENV_READY)
    if d == null or d == "":
        return
    try:
        _io.write_file(_os.join(d, _os.getenv(ENV_WORKER)), str(_os.pid()))
    catch e:
        ignored := e

# Arrête l'ouvrier si le maître a disparu (tué sans avoir pu prévenir ses ouvriers).
async func _watch_master(srv, master_pid):
    if master_pid == null:
        return
    while not srv.shutdown.is_stopped():
        await _aio.sleep(1.0)
        if not _psig.exists(master_pid):
            srv.stop()
            return

# ---------------------------------------------------------------- superviseur

class Worker:
    func init(index):
        self.index = index
        self.process = null
        self.started_at = 0.0
        self.restarts = 0
        self.quick_failures = 0          # morts successives moins d'une seconde après le lancement
        self.given_up = false

    func pid():
        return self.process.pid() if self.process != null else null

    func running():
        return self.process != null and self.process.running()

class Supervisor:
    # count : nombre d'ouvriers ; port 0 : un port libre est choisi ici et transmis aux ouvriers. command : liste
    # [programme, arguments...] d'un ouvrier (par défaut : ce programme, relancé avec les mêmes arguments).
    func init(count, host="127.0.0.1", port=8080, command=null, env=null):
        if type(count) != "int" or count < 1:
            raise("ServerConfigError", "workers.Supervisor : au moins un ouvrier (obtenu " + str(count) + ")")
        self.count = count
        self.host = host
        self.port = port if port != 0 else _nu.free_port(host if host != "" and host != "0.0.0.0" else "127.0.0.1")
        self.command = command if command != null else self_command()
        self.extra_env = env if env != null else {}
        self.workers = []
        self.stopping = false
        self.flags = []
        self.max_quick_failures = 5      # au-delà, l'ouvrier n'est plus relancé (erreur au démarrage)
        self.watch_roots = null          # dossiers surveillés (rechargement à chaud), ou null
        self.watch_state = null
        self.reloads = 0
        self.quiet_reload = false
        self.ready_dir = _os.join(_os.tmp_dir(), "alex-web-" + str(_os.pid()) + "-" + str(_nu.free_port("127.0.0.1")))
        self.services = []               # objets step(délai) [et shutdown()] servis par le maître

    func add_service(service):
        append(self.services, service)
        return self

    # Pause du maître : les services en profitent (au plus seconds secondes en tout), sinon simple attente.
    func _idle(seconds):
        if len(self.services) == 0:
            _time.sleep(seconds)
            return
        part := seconds / len(self.services)
        for s in self.services:
            try:
                s.step(part)
            catch e:
                print("workers : service en erreur : " + str(e.type) + " : " + str(e.message))
                _io.flush()
                _time.sleep(part)

    func _shutdown_services():
        for s in self.services:
            try:
                s.shutdown()
            catch e:
                ignored := e
        self.services = []

    func start():
        _os.mkdir_all(self.ready_dir)
        i := 0
        while i < self.count:
            w := Worker(i)
            append(self.workers, w)
            self._launch(w)
            i += 1
        return self

    func _launch(w):
        marker := _os.join(self.ready_dir, str(w.index))
        if _os.exists(marker):
            _os.remove(marker)
        env := {ENV_WORKER: str(w.index), ENV_PORT: str(self.port), ENV_MASTER: str(_os.pid()), ENV_READY: self.ready_dir}
        for k in keys(self.extra_env):
            env[k] = self.extra_env[k]
        prog := self.command[0]
        args := self.command[1:len(self.command)]
        w.process = _proc.spawn(prog, args, null, env)
        w.started_at = _time.monotonic()

    # Un tour de surveillance : relance les ouvriers morts. Rend le nombre d'ouvriers relancés.
    func step():
        n := 0
        if self.stopping:
            return 0
        for w in self.workers:
            if w.given_up or w.process == null or w.process.running():
                continue
            code := w.process.poll()
            lived := _time.monotonic() - w.started_at
            if lived < 1.0:
                w.quick_failures += 1
            else:
                w.quick_failures = 0
            if w.quick_failures >= self.max_quick_failures:
                w.given_up = true
                if self.watch_roots != null:
                    print("workers : l'ouvrier " + str(w.index) + " ne démarre pas (code " + str(code) + ") : en attente d'une modification")
                    _io.flush()
                else:
                    print("workers : l'ouvrier " + str(w.index) + " échoue au démarrage (code " + str(code) + ") : abandon")
                    _io.flush()
                continue
            w.restarts += 1
            self._launch(w)
            n += 1
        return n

    # Nombre d'ouvriers vivants qui ont signalé écouter le port.
    func ready_count():
        n := 0
        for w in self.workers:
            if not w.running():
                continue
            # présence du fichier : il est effacé avant chaque lancement (son contenu est le pid de la VM, qui
            # peut différer de celui du processus lancé, `alex run` exécutant la VM dans un fils)
            if _os.exists(_os.join(self.ready_dir, str(w.index))):
                n += 1
        return n

    # Attend que TOUS les ouvriers écoutent (au plus timeout secondes) ; rend true si c'est le cas. Les ouvriers
    # abandonnés (échec au démarrage) ne sont pas attendus.
    func wait_ready(timeout=20.0):
        t0 := _time.monotonic()
        while _time.monotonic() - t0 < timeout:
            want := 0
            for w in self.workers:
                if not w.given_up:
                    want += 1
            if want > 0 and self.ready_count() >= want:
                return true
            self.step()
            self._idle(0.05)
        return false

    func pids():
        out := []
        for w in self.workers:
            if w.running():
                append(out, w.pid())
        return out

    func alive_count():
        return len(self.pids())

    func restarts():
        n := 0
        for w in self.workers:
            n += w.restarts
        return n

    # Arrêt propre : TERM à chaque ouvrier (il finit ses requêtes en cours), KILL après grace secondes.
    func stop(grace=10.0, cleanup=true):
        self.stopping = true
        for w in self.workers:
            if w.running():
                try:
                    w.process.kill("TERM")
                catch e:
                    ignored := e
        t0 := _time.monotonic()
        while _time.monotonic() - t0 < grace and self.alive_count() > 0:
            self._idle(0.05)
        for w in self.workers:
            if w.running():
                try:
                    w.process.kill("KILL")
                catch e:
                    ignored := e
            if w.process != null:
                w.process.wait(1.0)
        if cleanup:
            try:
                _os.rmdir(self.ready_dir, true)
            catch e:
                ignored := e

    # Rechargement à chaud : surveille les fichiers .al de roots (null : racine du projet, c'est-à-dire le dossier
    # le plus proche du programme qui contient alex.toml, sinon le dossier du programme) ; un changement
    # relance tous les ouvriers (voir reload_if_changed).
    func watch(roots=null, quiet=false):
        if roots == null:
            roots = [_project_root()]
        self.watch_roots = roots
        self.quiet_reload = quiet
        self.max_quick_failures = 1      # code inchangé : inutile de réessayer avant la prochaine modification
        self.watch_state = _snapshot(roots)
        return self

    # Relance les ouvriers si un fichier surveillé a changé (ajout, suppression, modification). Rend le chemin du
    # premier fichier changé, ou null.
    func reload_if_changed(grace=3.0):
        if self.watch_roots == null:
            return null
        now := _snapshot(self.watch_roots)
        changed := _diff(self.watch_state, now)
        if changed == null:
            return null
        self.watch_state = now
        if not self.quiet_reload:
            print("workers : " + changed + " a changé, relance des ouvriers")
            _io.flush()
        self.restart(grace)
        self.reloads += 1
        return changed

    # Arrête puis relance tous les ouvriers (y compris ceux abandonnés après des échecs au démarrage).
    func restart(grace=3.0):
        self.stop(grace, false)
        self.stopping = false
        for w in self.workers:
            w.given_up = false
            w.quick_failures = 0
            self._launch(w)

    # Surveille jusqu'à INT / TERM, puis arrête proprement les ouvriers.
    func run(poll=0.2, grace=10.0):
        self._install_signals()
        while not self._signalled():
            self.step()
            self.reload_if_changed()
            if self._all_given_up() and self.watch_roots == null:
                print("workers : plus aucun ouvrier en état de servir")
                _io.flush()
                break
            self._idle(poll)
        self.stop(grace)
        self._shutdown_services()
        return self

    func _install_signals():
        try:
            if _signal.supported():
                for s in ["INT", "TERM"]:
                    append(self.flags, _signal.flag(s))
        catch e:
            self.flags = []

    func _signalled():
        for f in self.flags:
            if f.is_set():
                f.take()
                return true
        return false

    func _all_given_up():
        for w in self.workers:
            if not w.given_up:
                return false
        return true

# Commande qui relance ce programme : [alex, "run", script, "--", args...] pour un script, sinon [exécutable,
# args...] (programme compilé).
func self_command():
    argv := _os.argv()
    script := argv[0] if len(argv) > 0 else ""
    rest := argv[1:len(argv)] if len(argv) > 1 else []
    if len(script) > 3 and script[len(script) - 3:len(script)] == ".al":
        exe := _os.getenv("ALEX_EXE")
        if exe == null or exe == "":
            exe = "alex"
        return [exe, "run", script, "--"] + rest
    return [script] + rest

# ---------------------------------------------------------------- rechargement à chaud

# Dossier le plus proche du programme qui contient alex.toml ; à défaut, le dossier du programme.
func _project_root():
    script := _os.argv()[0] if len(_os.argv()) > 0 else "."
    start := _os.dirname(_os.absolute(script))
    d := start
    k := 0
    while k < 32 and d != "" and d != "/":
        if _os.exists(_os.join(d, "alex.toml")):
            return d
        parent := _os.dirname(d)
        if parent == d:
            break
        d = parent
        k += 1
    return start if start != "" else "."

# {chemin: date de modification} des fichiers .al sous roots (dossiers cachés et build / alex_packages ignorés).
func _snapshot(roots):
    out := {}
    for r in roots:
        _scan(r, out, 0)
    return out

func _scan(d, out, depth):
    if depth > 12:
        return
    names := []
    try:
        names = _os.list_dir(d)
    catch e:
        return
    for n in names:
        if len(n) > 0 and n[0:1] == ".":
            continue
        p := _os.join(d, n)
        if _os.isdir(p):
            if n != "build" and n != "alex_packages" and n != "dist":
                _scan(p, out, depth + 1)
        elif len(n) > 3 and n[len(n) - 3:len(n)] == ".al":
            try:
                out[p] = [_os.mtime(p), _os.size(p)]
            catch e:
                ignored := e

# Premier chemin ajouté, supprimé ou modifié entre deux instantanés, ou null.
func _diff(a, b):
    for k in keys(b):
        if not (k in a) or a[k] != b[k]:
            return k
    for k in keys(a):
        if not (k in b):
            return k
    return null
