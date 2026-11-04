# Programmes système : `process`, `pipe`, `signal`, `ipc`

Ces quatre paquets donnent à un programme Alex ce qu'il faut pour être un **vrai programme du système** :
lancer et surveiller d'autres programmes, leur parler par des tubes, réagir aux signaux, communiquer avec
d'autres processus de la machine.

```
use process
use pipe
use signal
use ipc

use process.command as command
r := command.Command("git").args(["log", "-n", "3"]).timeout(5).run()
print(r.stdout)
t := pipe.create()                          # tube anonyme
signal.on("TERM", (n) => arreter())         # gestionnaire de signal (programme principal)
m := ipc.shared_memory("compteurs", 4096)   # mémoire partagée entre processus
srv := ipc.serve("service")                 # canal de valeurs (socket Unix + JSON)
```

| Besoin | Outil |
|---|---|
| lancer un programme, capturer sa sortie, délai, code de sortie | `process.command`, `process.exit_code` |
| surveiller / relancer des services | `process.process_manager` |
| inspecter les processus (pid, mémoire, état, arbre) | `process.process_info` |
| environnement (variables, PATH, fichiers .env) | `process.environment` |
| tubes anonymes / nommés, chaînes de processus | `pipe` |
| signaux POSIX (TERM, INT, HUP, USR1...), gestionnaires, masques | `signal` |
| mémoire partagée, files de messages, sémaphores nommés, sockets locaux, canaux | `ipc` |

Natifs ajoutés : `_native_sync` (atomiques, verrous, mémoire partagée POSIX, files `mq_*`, sémaphores
nommés), extension de `_native_fd` (`poll`, `inotify`, `stat`, `ids`, noms d'utilisateurs / de groupes,
ioctl usbfs), sockets Unix dans `_native_net` (famille 1, `socketpair`, noms abstraits `@nom`).

Tests : `make test-sysapp` (`tests/sysapp/test_process_pipe_signal_ipc.al`, 89 vérifications : vrais
processus fils, signaux, mémoire partagée entre processus).

## Paquet `process`

### `process`

```text
Lancer et piloter des processus fils, sans shell.

Architecture
  process.al        API publique ALEX (Command, Process, Result, run, ...).
  _native_process   primitives système (runtime/native/process/) : table de
                    handles, pipes, délais, signaux. POSIX uniquement : sous
                    Windows les fonctions lèvent IoError (os.run / os.spawn
                    restent disponibles).

Principes
  - AUCUN shell : le programme est cherché dans le PATH, les arguments sont
    passés tels quels. Pas d'échappement à faire, pas d'injection possible.
  - Un code de sortie non nul n'est PAS une erreur (sauf check=true).
    code < 0 : processus tué par le signal -code (POSIX).
  - Les flux sont du texte UTF-8 ; un caractère n'est jamais coupé en deux
    entre deux lectures.
  - Pas de GC des handles : un Process se libère avec close(). run() et
    check_output() le font eux-mêmes, y compris en cas d'erreur.

Erreurs
  IoError        programme introuvable, droits, pipe cassé...
  TypeError      argument d'un mauvais type.
  ArgumentError  valeur invalide (mode inconnu, signal inconnu, ...).
  ProcessError   check=true et code de sortie non nul.
  TimeoutError   check=true (ou check_output) et délai dépassé.

Exemple
  use process
  r := process.run("git", ["rev-parse", "HEAD"])
  if r.ok():
      print(r.stdout)

  p := process.Command("sort").stdin("pipe").stdout("pipe").spawn()
  p.write("b\na\n")
  p.close_stdin()
  print(p.read_all())
  p.wait()
  p.close()
```

API publique :

- `str_of(v)`
- class `Result(code, stdout, stderr, timed_out)` : `ok()`, `check()`
- class `Process(handle, grouped=false)` : `pid()`, `poll()`, `running()`, `wait(timeout=null)`, `kill(signal="TERM", group=false)`, `terminate(group=false)`, `stop(grace=3.0, group=false)`, `write(data)`, `write_line(text)`, `close_stdin()`, `read(stream="stdout", max=65536, timeout=null)`, `read_line(stream="stdout", timeout=null)`, `read_line_raw(stream="stdout", timeout=null)`, `read_all(stream="stdout")`, `communicate(input=null, timeout=null)`, `close()`
- class `Command(program, args=null)` : `arg(value)`, `args(values)`, `cwd(path)`, `env(overrides)`, `clear_env()`, `stdin(mode)`, `stdout(mode)`, `stderr(mode)`, `group()`, `spawn()`, `run(input=null, timeout=null, grace=2.0, check=false)`
- `list_copy(items)`
- `run(program, args=null, input=null, timeout=null, cwd=null, env=null, check=false)`
- `spawn(program, args=null, cwd=null, env=null, stdin="inherit", stdout="inherit", stderr="inherit")`
- `check_output(program, args=null, input=null, timeout=null, cwd=null, env=null)`
- `which(program)`
- `open_handles()`
- `supported()`

### `process.command`

```text
Construire, afficher, analyser et enchaîner des lignes de commande, SANS shell.

  use process.command as command
  c := command.Command("git").args(["log", "-n", "3"]).cwd("/src").timeout(5)
  print(c.to_string())                    # git log -n 3
  print(c.output())                       # stdout (ProcessError si le code n'est pas 0)
  parts := command.split("grep -r 'mot clé' src")   # ["grep", "-r", "mot clé", "src"]
  r := command.parse("ls -l /tmp").run()
  p := command.Command("printf").args(["b\na\n"]).pipe(command.Command("sort")).run()
  print(p.stdout)                          # "a\nb\n"

Command (héritée de process.Command : arg, args, cwd, env, clear_env, stdin, stdout, stderr, group, spawn,
run) ajoute : timeout, input, check, env_var, output, status, succeeds, pipe, program, arguments,
to_string, to_list, copy. split / quote / join suivent les règles du shell POSIX (guillemets simples et
doubles, barre oblique inverse) mais n'interprètent RIEN d'autre : ni variables, ni jokers, ni `;`/`|`.

Erreurs : ArgumentError (ligne de commande mal formée : guillemet non fermé), TypeError, et celles de
process (IoError, ProcessError, TimeoutError).
```

API publique :

- `split(line)`
- `quote(arg)`
- `join(args)`
- class `Command(program, args=null)` : `timeout(seconds)`, `input(text)`, `check(enabled=true)`, `env_var(name, value)`, `program()`, `arguments()`, `to_list()`, `to_string()`, `copy()`, `run(input=null, timeout=null, grace=2.0, check=null)`, `output()`, `status()`, `succeeds()`, `pipe(other)`
- `parse(line)`
- `from_list(argv)`
- class `Pipeline(commands)` : `pipe(other)`, `timeout(seconds)`, `to_string()`, `run(input=null, check=false)`, `output()`

### `process.environment`

```text
Environnement des processus : celui du programme (lecture, modification, expansion « $VAR », voir
system.environment) et des environnements construits pour un processus fils, sans toucher au programme.

  use process.environment as env
  e := env.inherit().set("LANG", "C").prepend_path("/opt/outils/bin").unset("DEBUG")
  r := e.run("make", ["-j4"])                 # le fils voit l'environnement e
  cmd := e.apply(process.Command("env"))      # ou : appliqué à une commande (clear_env + env)
  print(env.get("HOME"), env.expand("${HOME}/données"))

Environment est une valeur : set / unset / update / prepend_path... renvoient self pour l'enchaînement et ne
modifient que l'objet (jamais l'environnement du programme).

Erreurs : ArgumentError (nom de variable invalide), TypeError.
```

API publique :

- `get(name, fallback=null)`
- `set(name, value)`
- `unset(name)`
- `has(name)`
- `all()`
- `get_int(name, fallback=null)`
- `get_bool(name, fallback=null)`
- `expand(text, vars=null)`
- `with_vars(vars, fn)`
- `path_separator()`
- class `Environment(vars=null)` : `get(name, fallback=null)`, `has(name)`, `set(name, value)`, `unset(name)`, `update(vars)`, `keep(names)`, `names()`, `size()`, `prepend_path(dir, var="PATH")`, `append_path(dir, var="PATH")`, `expand(text)`, `to_dict()`, `to_list()`, `copy()`, `diff(other)`, `apply(command)`, `run(program, args=null, input=null, timeout=null, cwd=null, check=false)`, `spawn(program, args=null, cwd=null, stdin="inherit", stdout="inherit", stderr="inherit")`
- `inherit()`
- `empty()`
- `minimal(vars=null)`

### `process.exit_code`

```text
Codes de sortie des processus : conventions (0 succès, 1 échec, 2 mauvais usage, sysexits.h 64..78, 126/127 du
shell, 128+n « tué par le signal n »), signaux, et une valeur ExitStatus qui sait se décrire.

  use process.exit_code as ec
  s := ec.ExitStatus(process.run("false").code)
  print(s.success(), s.describe())        # false  « échec (code 1) »
  print(ec.describe(-9))                   # « tué par le signal KILL (9) »
  print(ec.describe(130))                  # « code 130 (convention du shell : signal INT) »
  os.exit(ec.USAGE)

Dans le module process, un code NÉGATIF signifie « tué par le signal -code ». Un shell, lui, renvoie 128 + n :
from_shell / to_shell convertissent d'une convention à l'autre.
```

API publique :

- `is_signal(code)`
- `signal_of(code)`
- `from_signal(sig)`
- `from_shell(code)`
- `to_shell(code)`
- `success(code)`
- `describe(code)`
- `for_error(error_type)`
- class `ExitStatus(code)` : `finished()`, `success()`, `signaled()`, `signal()`, `shell_code()`, `describe()`, `check(what="processus")`

### `process.process_info`

```text
Informations sur les processus de la machine (comme ps / top) : identité, parent, état, commande, mémoire,
temps processeur, fils, arborescence. Source : /proc (Linux) ; ailleurs, `ps` s'il existe (informations
réduites). Une information indisponible (processus d'un autre utilisateur, plateforme) vaut null.

  use process.process_info as pinfo
  me := pinfo.current()
  print(me.pid, me.name, me.state_name(), pinfo.format_bytes(me.rss))
  for p in pinfo.find("sshd"):
      print(p.pid, p.cmdline)
  print(pinfo.tree(1).render())                     # arborescence à partir de init
  print(pinfo.cpu_percent(me.pid, 0.2))            # % d'un cœur sur 0,2 s

Erreurs : ProcessError (processus absent pour get), TypeError.
```

API publique :

- `supported()`
- class `ProcessInfo(pid)` : `state_name()`, `cpu_time()`, `start_time()`, `age()`, `is_running()`, `is_zombie()`, `command()`, `children()`, `parent()`, `to_dict()`
- `get_or_null(pid)`
- `get(pid)`
- `current()`
- `parent()`
- `exists(pid)`
- `pids()`
- `list_processes()`
- `find(name, contains=false)`
- `children(pid)`
- `descendants(pid)`
- class `ProcessTree(info, children)` : `size()`, `pids()`, `render(indent="")`
- `tree(pid)`
- `boot_time()`
- `cpu_percent(pid, interval=0.5)`
- `format_bytes(n)`

### `process.process_manager`

```text
Superviser plusieurs processus fils : démarrage, arrêt propre (TERM puis KILL), redémarrage automatique avec
délai croissant, sortie capturée, événements ; et exécution parallèle bornée d'une liste de commandes.

  use process.process_manager as pm
  m := pm.ProcessManager()
  m.add("web", ["python3", "-m", "http.server", "8000"], {"restart": "on_failure", "max_restarts": 5})
  m.add("worker", "./worker --queue jobs", {"restart": "always", "output": "capture"})
  m.on("exit", (ev) => print(ev["name"], ev["code"]))
  m.start_all()
  m.supervise(60)                        # surveille 60 s (redémarrages, sorties capturées, événements)
  print(m.status())
  m.stop_all(3)

  results := pm.run_parallel([["gzip", "-k", "a"], ["gzip", "-k", "b"]], max_parallel=4)

Options de add (dict, toutes facultatives) : "restart" (politique), "max_restarts" (3), "backoff" (0.5 s),
"max_backoff" (30 s), "output" ("inherit", "null" ou "capture" : lignes gardées, voir logs), "keep_lines" (1000).

Politique de redémarrage : "never" (défaut), "on_failure" (code non nul ou signal), "always". Le n-ième
redémarrage attend backoff × 2^(n-1) secondes (au plus max_backoff). Au-delà de max_restarts, l'état passe à
"failed". Événements : "start", "exit", "restart", "failed", "stop" ; le gestionnaire reçoit un dict
{"name", "event", "code", "pid", "restarts"}.

Commandes acceptées : [programme, arguments...], une ligne de texte (découpée sans shell, process.command.split)
ou un objet process.Command / process.command.Command.

Erreurs : ArgumentError (nom inconnu ou déjà utilisé, politique invalide), ProcessError, IoError.
```

API publique :

- class `ManagedProcess(name, command, restart, max_restarts, backoff, max_backoff, output, keep_lines)` : `running()`, `uptime()`, `describe()`
- class `ProcessManager()` : `on(event, handler)`, `add(name, command, options=null)`, `get(name)`, `names()`, `remove(name)`, `start(name)`, `start_all()`, `stop(name, grace=3.0)`, `stop_all(grace=3.0)`, `restart(name, grace=3.0)`, `poll()`, `active()`, `supervise(duration=null, interval=0.05)`, `wait(name, timeout=null)`, `wait_all(timeout=null)`, `logs(name, stream=null)`, `status()`, `running()`
- `run_parallel(commands, max_parallel=null, timeout=null, stop_on_error=false)`

## Paquet `pipe`

### `pipe`

```text
Tubes : anonymes (pipe.anonymous_pipe), nommés (pipe.named_pipe), duplex, flux structurés et attente sur
plusieurs tubes (pipe.pipe_stream), chaînes de processus sans shell (pipeline).

  use pipe
  t := pipe.create()                          # tube anonyme : t.reader, t.writer
  t.send_line("bonjour")
  print(t.receive_line(1))
  d := pipe.duplex()                           # deux sens : d[0], d[1]
  f := pipe.named("/tmp/canal")                # FIFO (créé si besoin)
  s := pipe.stream(t)                          # messages délimités, JSON
  r := pipe.pipeline([["ls"], ["sort", "-r"], ["head", "-n", "3"]])
  print(r.stdout, r.codes, r.ok())
  prets := pipe.poll([t1.reader, t2.reader], 0.5)

Les modules détaillés restent accessibles : pipe.anonymous_pipe, pipe.named_pipe, pipe.pipe_stream, et la
couche io.pipe sur laquelle ils reposent (docs/PIPE.md).
```

API publique :

- `supported()`
- `create()`
- `duplex()`
- `named(path, mode=384)`
- `temporary_named()`
- `stream(source, writer=null)`
- `pipeline(commands, input=null, timeout=null, check=false)`
- `poll(streams, timeout=null)`
- `copy(reader, writer)`
- `reader_from_fd(fd)`
- `writer_from_fd(fd)`

### `pipe.anonymous_pipe`

```text
Tubes anonymes : un canal d'octets à sens unique entre deux bouts (lecture, écriture) d'un même processus, de
deux fils (concurrency.thread / thread : le bout passe par son numéro de descripteur) ou d'un parent et de son
fils (process.Command(...).stdin(tube.reader)). Et tubes DUPLEX (deux sens, une paire de sockets locaux).

  use pipe.anonymous_pipe as ap
  t := ap.AnonymousPipe()
  t.send("bonjour\n")
  print(t.receive_line(1.0))             # « bonjour »
  t.close()

  d := ap.duplex()                       # deux extrémités reliées : d[0], d[1]
  a := d[0]
  b := d[1]
  a.send_line("ping")
  print(b.read_line(1.0))                # « ping »
  b.send_line("pong")
  print(a.read_line(1.0))                # « pong »

Les bouts sont des flux io.stream (read, read_line, read_all, write, write_line...). Pour qu'un lecteur voie
la fin du flux, TOUS les bouts d'écriture doivent être fermés (y compris la copie gardée par le parent après
l'avoir donnée à un fils).

Erreurs : IoError (système ; « [EPIPE] » si plus personne ne lit), TimeoutError, ArgumentError.
```

API publique :

- `supported()`
- class `AnonymousPipe()` : `fds()`, `send(text)`, `send_line(text)`, `receive(max=65536, timeout=null)`, `receive_line(timeout=null)`, `readable()`, `close_reader()`, `close_writer()`, `close()`, `closed()`
- `create()`
- `reader_from_fd(fd)`
- `writer_from_fd(fd)`
- class `DuplexEnd(h)` : `fd()`, `send(text)`, `send_line(text)`, `read(max=65536, timeout=null)`, `read_line(timeout=null)`, `read_exact(n, timeout=null)`, `read_all(timeout=null)`, `close_write()`, `close()`
- `duplex()`

### `pipe.named_pipe`

```text
Tubes nommés (FIFO) : un chemin du système de fichiers que deux processus SANS lien de parenté ouvrent pour se
parler, l'un en lecture, l'autre en écriture.

  use pipe.named_pipe as np
  f := np.NamedPipe("/tmp/commandes")
  f.create()                                  # mkfifo (droits 0600)
  # processus A                               # processus B
  r := f.open_reader()                        w := np.NamedPipe("/tmp/commandes").open_writer(5)
  print(r.read_line(10))                      w.write_line("stop")
  f.unlink()

  np.with_temporary((tube) => ...)            # tube temporaire unique, supprimé ensuite

Règles du système : open_writer attend qu'un lecteur ait ouvert le tube (au plus timeout secondes, sinon
TimeoutError) ; le lecteur voit la fin du flux quand le dernier écrivain ferme. Un tube nommé ne garde rien :
ce qui est écrit sans lecteur n'existe pas.

Erreurs : IoError (système, chemin qui n'est pas un tube), TimeoutError, TypeError.
```

API publique :

- `is_fifo(path)`
- class `NamedPipe(path)` : `exists()`, `create(mode=384, exist_ok=true)`, `open_reader()`, `open_writer(timeout=null)`, `send(text, timeout=null)`, `send_line(text, timeout=null)`, `receive_all(timeout=null)`, `unlink()`, `to_string()`
- `create(path, mode=384)`
- `temporary(prefix="alex-fifo-")`
- `with_temporary(fn)`

### `pipe.pipe_stream`

```text
Flux structurés au-dessus d'un tube (ou de tout couple io.stream Reader / Writer) : lignes, MESSAGES délimités
(préfixe de longueur : un message n'est jamais coupé ni collé au suivant), valeurs JSON ; attente sur
plusieurs tubes à la fois (poll), copie, duplication (tee).

  use pipe.pipe_stream as ps
  use pipe.anonymous_pipe as ap
  t := ap.AnonymousPipe()
  s := ps.PipeStream(t.reader, t.writer)
  s.send_message("un\nmessage\nsur plusieurs lignes")
  s.send_json({"cmd": "start", "n": 3})
  print(s.receive_message(1.0))              # le texte exact
  print(s.receive_json(1.0)["cmd"])          # « start »
  prets := ps.poll([t1.reader, t2.reader], 0.5)   # lecteurs qui ont des données

Format d'un message : « <longueur en octets>\n<octets> ». Il convient au texte comme au binaire et se lit
facilement depuis un autre langage.

Erreurs : ProtocolError (message mal formé ou trop grand), IoError, TimeoutError, TypeError.
```

API publique :

- class `PipeStream(reader, writer=null, max_message=MAX_MESSAGE)` : `send(text)`, `send_line(text)`, `receive(max=65536, timeout=null)`, `receive_line(timeout=null)`, `send_message(data)`, `receive_message(timeout=null)`, `send_json(value)`, `receive_json(timeout=null)`, `request(value, timeout=null)`, `close()`
- `poll(streams, timeout=null)`
- `copy(reader, writer, chunk=65536)`
- `tee(reader, writers, chunk=65536)`

## Paquet `signal`

### `signal`

```text
Signaux du système (POSIX) : intercepter, ignorer, attendre, envoyer. Ce paquet réunit system.signal (un
gestionnaire par signal, surveillance, envoi), signal.signal_handler (plusieurs gestionnaires, priorités,
groupes, arrêt propre) et signal.signal_constants (numéros, actions par défaut, descriptions).

  use signal
  signal.on("USR1", (nom) => print("reçu", nom))         # un gestionnaire (remplace le précédent)
  t := signal.add("HUP", relire_config)                  # un gestionnaire de plus (jeton)
  arret := signal.graceful_shutdown()                     # INT / TERM : arrêt demandé, puis immédiat
  signal.send(pid, "TERM")
  print(signal.wait(["USR2"], 5))                         # après signal.watch("USR2")
  print(signal.describe("WINCH"), signal.number("USR1"))

Erreurs : ArgumentError (signal inconnu ou non interceptable), SignalError, ProcessError (send vers un
processus absent), ThreadError (interception depuis un fil), InterruptError (interrupt_on, arrêt forcé).
```

API publique :

- `supported()`
- `names()`
- `number(sig)`
- `name_of(sig)`
- `describe(sig)`
- `default_action(sig)`
- `is_catchable(sig)`
- `on(sig, handler)`
- `interrupt_on(sig="INT")`
- `watch(sig)`
- `ignore(sig)`
- `reset(sig)`
- `pending(sig)`
- `received(sig)`
- `wait(sigs=null, timeout=null)`
- `with_handler(sig, handler, fn)`
- `send(pid, sig="TERM")`
- `raise_signal(sig)`
- `add(sig, handler, priority=0)`
- `once(sig, handler, priority=0)`
- `remove(token)`
- `clear(sig)`
- `scoped(sig, handler, body)`
- `group()`
- `flag(sig)`
- `graceful_shutdown(callback=null, signals=null, force=true)`

### `signal.signal_constants`

```text
Table des signaux POSIX : nom, numéro sur la plateforme courante (et sous Linux / macOS), action par défaut,
interceptable ou non, description en français.

  use signal.signal_constants as sc
  print(sc.SIGTERM, sc.number("USR1"), sc.describe("WINCH"))
  print(sc.default_action("CHLD"))         # « ignorer »
  for s in sc.catchable():  ...

Les constantes SIGxxx valent le numéro de la plateforme où le programme s'exécute (lu dans le runtime), donc
différent entre Linux et macOS pour USR1, USR2, CHLD, BUS... : utiliser les noms dans le code portable.
```

API publique :

- `number(name)`
- `linux_number(name)`
- `macos_number(name)`
- `name_of(num)`
- `describe(name)`
- `default_action(name)`
- `is_catchable(name)`
- `exists(name)`
- `all_names()`
- `catchable()`
- `shutdown_signals()`
- `terminates(name)`

### `signal.signal_handler`

```text
Plusieurs gestionnaires par signal, priorités, gestionnaires à usage unique, groupes que l'on installe et
désinstalle d'un coup, et arrêt propre en deux temps (premier Ctrl+C : arrêt demandé ; second : immédiat).

  use signal.signal_handler as sh
  jeton := sh.add("USR1", (nom) => recharger_config())
  sh.add("USR1", (nom) => journal.info("USR1 reçu"), 10)     # priorité 10 : appelé avant
  sh.remove(jeton)

  arret := sh.graceful_shutdown((nom) => print("arrêt demandé par", nom))
  while not arret.requested():
      travailler()                     # un second signal lève InterruptError

  g := sh.HandlerGroup()
  g.add("HUP", relire)
  g.add("TERM", fermer)
  g.install()   ...   g.uninstall()    # rend l'état précédent

Repose sur system.signal (un seul gestionnaire système par signal) : ce module installe un répartiteur qui
appelle, dans l'ordre des priorités décroissantes puis d'enregistrement, chaque fonction enregistrée. Quand le
dernier gestionnaire d'un signal est retiré, le comportement d'origine est rétabli. Une exception levée par un
gestionnaire interrompt la répartition et part de l'endroit où en était le programme (system.signal).

Seul le programme principal intercepte les signaux (ThreadError depuis un fil).
```

API publique :

- `add(sig, handler, priority=0, once=false)`
- `once(sig, handler, priority=0)`
- `remove_token(token)`
- `remove(token)`
- `clear(sig)`
- `count(sig)`
- `scoped(sig, handler, body)`
- class `HandlerGroup()` : `add(sig, handler, priority=0)`, `install()`, `uninstall()`, `installed()`
- `add_handler(sig, handler, priority=0)`
- class `ShutdownRequest(signals, callback, force_after)` : `requested()`, `wait(timeout=null)`, `cancel()`
- `graceful_shutdown(callback=null, signals=null, force=true)`
- class `SignalFlag(sig)` : `is_set()`, `take()`, `close()`
- `flag(sig)`

## Paquet `ipc`

### `ipc`

```text
Communication entre PROCESSUS de la même machine :

| Besoin                                         | Outil                                   |
|------------------------------------------------|-----------------------------------------|
| partager des octets, des compteurs, un verrou  | ipc.shared_memory (SharedMemory, SharedCounter, SharedMutex) |
| déposer / retirer des messages                 | ipc.message_queue (POSIX ou mémoire partagée)             |
| limiter l'accès à une ressource                | ipc.semaphore (NamedSemaphore)                            |
| un flux d'octets bidirectionnel                | ipc.local_socket (socket Unix : serveur, connexions)      |
| échanger des valeurs, appeler des fonctions    | ipc.channel (JSON, question / réponse, multi-clients)     |
| relier un parent et ses fils                   | pipe (tubes), process (flux des fils)                     |

  use ipc
  m := ipc.shared_memory("compteurs", 4096)
  q := ipc.message_queue("travaux")
  s := ipc.semaphore("gpu", 1)
  c := ipc.connect("service")              # canal de valeurs (ipc.channel)
  srv := ipc.serve("service")

Les noms sont propres à la machine ; ils survivent aux processus jusqu'à unlink (mémoire, files, sémaphores)
ou close du serveur (sockets). ipc.cleanup(nom) supprime tout ce qui porte ce nom.
```

API publique :

- `supported()`
- `shared_memory(name, size=0, mode="open_or_create")`
- `message_queue(name, max_messages=10, max_size=8192, backend=null)`
- `semaphore(name, value=1)`
- `listen(name)`
- `connect_socket(name, timeout=null)`
- `connect(name, timeout=null)`
- `serve(name)`
- `cleanup(name)`

### `ipc.channel`

```text
Canaux de VALEURS entre processus : des dict, listes, textes, nombres (JSON) passent d'un processus à l'autre
sur un socket local, message par message ; et un petit protocole question / réponse avec serveur multi-clients.

  use ipc.channel as ch
  # serveur
  srv := ch.serve_on("calcul")
  srv.handle("somme", (args) => args[0] + args[1])
  srv.handle("echo", (args) => args)
  srv.run(10)                                   # répond pendant 10 s (null : jusqu'à srv.stop())
  # client (autre processus)
  c := ch.connect("calcul", 2.0)
  print(c.call("somme", [2, 3]))                # 5
  c.close()

  # canal brut : send / receive de valeurs
  a := ch.connect("journal")
  a.send({"niveau": "info", "texte": "démarré"})

Une erreur levée par une fonction du serveur revient au client sous forme de RemoteError (type et message
d'origine dans le message). Un client peut enchaîner autant d'appels qu'il veut sur la même connexion.

Erreurs : IpcError, TimeoutError, RemoteError, ProtocolError.
```

API publique :

- class `Channel(conn)` : `send(value, timeout=null)`, `receive(timeout=null)`, `call(name, args=null, timeout=null)`, `readable(timeout=0)`, `close()`
- `connect(name, timeout=null)`
- `pair()`
- class `ChannelServer(name)` : `handle(name, fn)`, `stop()`, `step(timeout=0.05)`, `run(duration=null)`, `clients()`, `close()`
- `serve_on(name)`

### `ipc.local_socket`

```text
Sockets LOCAUX (domaine Unix) : comme TCP, mais entre processus de la même machine, désignés par un chemin
du système de fichiers (droits d'accès des fichiers) ou par un nom abstrait « @nom » (Linux, sans fichier).
Plus rapides que TCP en boucle locale, invisibles du réseau.

  use ipc.local_socket as ls
  serveur := ls.listen("mon-service")         # /tmp/alex-mon-service.sock (ou un chemin, ou « @nom »)
  # autre processus :
  c := ls.connect("mon-service", 2.0)
  c.send_line("ping")
  # serveur :
  conn := serveur.accept(5.0)
  print(conn.read_line(1.0))                  # « ping »
  conn.send_message("réponse complète")       # message délimité (longueur + octets)
  conn.close()
  serveur.close()                             # supprime aussi le fichier du socket

Messages : send_message / receive_message transportent des messages entiers (« <longueur>\n<octets> », comme
pipe.pipe_stream) ; send_json / receive_json des valeurs JSON.

Erreurs : IpcError (adresse occupée, absente, droits...), TimeoutError, ProtocolError, TypeError.
```

API publique :

- `address(name)`
- class `LocalConnection(sock, address)` : `fd()`, `send(data, timeout=null)`, `send_line(text, timeout=null)`, `read(max=65536, timeout=null)`, `read_line(timeout=null)`, `read_exact(n, timeout=null)`, `read_all(timeout=null)`, `send_message(data, timeout=null)`, `receive_message(timeout=null)`, `send_json(value, timeout=null)`, `receive_json(timeout=null)`, `readable(timeout=0)`, `peer()`, `close_write()`, `close()`
- class `LocalServer(name, backlog=64, mode=null)` : `accept(timeout=null)`, `fd()`, `close()`
- `listen(name, backlog=64, mode=null)`
- `connect(name, timeout=null)`
- `pair()`
- `wait(conns, timeout=null)`

### `ipc.message_queue`

```text
Files de messages NOMMÉES entre processus : un processus dépose des messages (texte ou octets), un autre les
retire dans l'ordre, chacun entier. Deux réalisations derrière la même interface :
  - PosixQueue : les files POSIX du système (mq_open, Linux) — priorités 0..31 (la plus haute sort d'abord),
    limites du système (souvent 10 messages de 8 Kio sans privilège : /proc/sys/fs/mqueue) ;
  - ShmQueue   : une file circulaire en mémoire partagée (ipc.shared_memory), portable, capacité choisie
    librement ; ordre FIFO strict (la priorité est ignorée).
open() choisit PosixQueue si le système le permet, sinon ShmQueue (backend="posix" | "shm" pour forcer).

  use ipc.message_queue as mq
  q := mq.open("travaux", 64, 4096)           # au plus 64 messages de 4096 octets
  q.send("tâche 1")
  q.send_json({"id": 2})
  print(q.receive(1.0))                        # « tâche 1 » (null après 1 s sans message)
  print(q.receive_json(1.0))
  q.close()
  mq.unlink("travaux")

send(data, priorité, délai) renvoie false si la file est restée pleine jusqu'au délai (0 : ne pas attendre) ;
receive(délai) renvoie null si elle est restée vide.

Erreurs : IpcError (système, message trop grand), TypeError, ArgumentError.
```

API publique :

- `posix_supported()`
- class `PosixQueue(name, max_messages=10, max_size=8192, mode="open_or_create")` : `send(data, priority=0, timeout=null)`, `receive(timeout=null)`, `receive_with_priority(timeout=null)`, `size()`, `close()`, `unlink()`, `send_json(value, priority=0, timeout=null)`, `receive_json(timeout=null)`
- class `ShmQueue(name, max_messages=64, max_size=8192, mode="open_or_create")` : `send(data, priority=0, timeout=null)`, `receive_with_priority(timeout=null)`, `receive(timeout=null)`, `size()`, `close()`, `unlink()`, `send_json(value, priority=0, timeout=null)`, `receive_json(timeout=null)`
- `open(name, max_messages=10, max_size=8192, backend=null, mode="open_or_create")`
- `unlink(name)`

### `ipc.semaphore`

```text
Sémaphores NOMMÉS entre processus (POSIX sem_open) : un compteur de jetons partagé par tous les processus qui
ouvrent le même nom. acquire prend un jeton (attend s'il n'y en a plus), release en rend un. Sert à limiter le
nombre de processus qui utilisent une ressource en même temps, ou à signaler un événement d'un processus à un
autre.

  use ipc.semaphore as sem
  s := sem.NamedSemaphore("imprimante", 2)     # 2 jetons à la création (ignoré si le nom existe déjà)
  if s.acquire(5.0):                            # au plus 5 s d'attente
      try:
          imprimer()
      finally:
          s.release()
  s.with_permit(imprimer)                       # la même chose
  s.close()
  sem.unlink("imprimante")

Pour des fils d'un même processus, synchronization.semaphore est plus simple (pas de nom à gérer).

Erreurs : IpcError (système), TimeoutError (with_permit, run avec délai), TypeError.
```

API publique :

- class `NamedSemaphore(name, value=1, mode="open_or_create")` : `acquire(timeout=null)`, `try_acquire()`, `release(n=1)`, `value()`, `with_permit(fn, timeout=null)`, `close()`, `unlink()`
- `unlink(name)`
- `open(name, value=1)`

### `ipc.shared_memory`

```text
Mémoire partagée NOMMÉE entre processus (POSIX shm_open + mmap) : les mêmes octets, vus par tous les processus
qui ouvrent le même nom. Lecture et écriture d'octets et d'entiers à une position, opérations ATOMIQUES (même
entre processus), attente efficace d'un changement de valeur (futex sous Linux), et deux outils construits
dessus : SharedMutex (verrou entre processus) et SharedCounter (compteur atomique).

  use ipc.shared_memory as shm
  m := shm.SharedMemory("mon-appli", 4096)          # créé s'il n'existe pas (zéros), sinon ouvert
  m.set(0, "i64", 42)
  m.write(64, "bonjour")
  print(m.get(0, "i64"), m.read(64, 7))
  c := shm.SharedCounter(m, 8)
  c.add(1)                                           # atomique, même avec d'autres processus
  verrou := shm.SharedMutex(m, 16)
  verrou.lock()   ...   verrou.unlock()
  m.close()
  shm.unlink("mon-appli")                            # le nom disparaît ; la mémoire, au dernier close

Types : i8 u8 i16 u16 i32 u32 i64 f32 f64 (petit-boutiste). Atomiques : mots de 32 ou 64 bits ALIGNÉS
(position multiple de 4 ou 8). wait / wake : mots de 32 bits.

Erreurs : IpcError (système : nom invalide, droits, déjà existant avec create), IndexError (zone hors de la
mémoire), ArgumentError, TypeError, TimeoutError (SharedMutex.lock avec délai via try_lock / lock(timeout)).
```

API publique :

- `supported()`
- class `SharedMemory(name, size=0, mode="open_or_create")` : `read(offset, n)`, `write(offset, data)`, `read_bytes(offset, n)`, `write_bytes(offset, data)`, `read_cstring(offset, max=4096)`, `write_cstring(offset, text)`, `get(offset, kind)`, `set(offset, kind, value)`, `fill(offset, n, byte=0)`, `atomic_load(offset, width=64)`, `atomic_store(offset, value, width=64)`, `atomic_exchange(offset, value, width=64)`, `atomic_add(offset, delta, width=64)`, `atomic_sub(offset, delta, width=64)`, `atomic_and(offset, mask, width=64)`, `atomic_or(offset, mask, width=64)`, `atomic_xor(offset, mask, width=64)`, `compare_exchange(offset, expected, new, width=64)`, `wait(offset, expected, timeout=null)`, `wake(offset, n=-1)`, `close()`, `unlink()`
- `create(name, size)`
- `open(name)`
- `open_or_create(name, size)`
- `unlink(name)`
- `exists(name)`
- `with_temporary(size, fn)`
- class `SharedCounter(memory, offset)` : `value()`, `set(v)`, `add(delta=1)`, `sub(delta=1)`, `compare_exchange(expected, new)`
- class `SharedMutex(memory, offset)` : `lock(timeout=null)`, `try_lock()`, `unlock()`, `locked()`, `force_unlock()`, `run(fn)`

