# =============================================================================
# ALEX — paquets process, pipe, signal, ipc (docs/SYSAPP.md).
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/sysapp/test_process_pipe_signal_ipc.al
# =============================================================================
from core use len, type
from collections use append
use os
use process
use process.command as command
use process.exit_code as ec
use process.environment as penv
use process.process_info as pinfo
use process.process_manager as pm
use pipe
use pipe.named_pipe as np
use pipe.pipe_stream as ps
use signal
use signal.signal_constants as sc
use ipc
use ipc.shared_memory as shm
use ipc.message_queue as mq
use ipc.semaphore as sem
use ipc.local_socket as ls
use ipc.channel as ch

stats := [0, 0]
notes := []
func check(cond, label):
    if cond:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label)
func check_eq(a, b, label):
    if a == b:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label + " : obtenu " + str(a) + ", attendu " + str(b))
func raises(f, kind, label):
    try:
        f()
        check(false, label + " (aucune erreur)")
    catch e:
        check_eq(e.type, kind, label)

ALEX := os.getenv("ALEX_BIN", "./alex")
CHILD := "tests/sysapp/sysapp_child.al"

func test_command():
    check_eq(command.split("grep -r 'mot clé' src \"a\\\"b\" x\\ y"), ["grep", "-r", "mot clé", "src", "a\"b", "x y"], "split")
    raises(() => command.split("echo 'ouvert"), "ArgumentError", "split : guillemet non fermé")
    check_eq(command.join(["echo", "it's", "a b", "ok"]), "echo 'it'\"'\"'s' 'a b' ok", "join / quote")
    check_eq(command.split(command.join(["a b", "c'd", "$x"])), ["a b", "c'd", "$x"], "aller-retour quote/split")
    c := command.Command("printf").args(["%s\n", "b", "a"])
    check_eq(c.output(), "b\na\n", "Command.output")
    check_eq(c.pipe(command.Command("sort")).run().stdout, "a\nb\n", "Command.pipe")
    check_eq(command.parse("sh -c 'exit 3'").status(), 3, "parse + status")
    check_eq(command.Command("cat").input("bonjour").output(), "bonjour", "input")
    check_eq(command.Command("sh").args(["-c", "echo $FOO"]).env_var("FOO", "barre").copy().output(), "barre\n", "env_var + copy")
    check(not command.parse("false").succeeds(), "succeeds")
    raises(() => command.parse("false").check().run(), "ProcessError", "check")
    r := command.parse("sleep 5").timeout(0.2).run()
    check(r.timed_out, "timeout")

func test_exit_code():
    check_eq(ec.describe(-9), "tué par le signal KILL (9)", "describe signal")
    check_eq(ec.describe(0), "succès", "describe 0")
    check_eq(ec.to_shell(-15), 143, "to_shell")
    check_eq(ec.from_shell(137), -9, "from_shell")
    check_eq(ec.ExitStatus(-15).signal(), "TERM", "ExitStatus.signal")
    raises(() => ec.ExitStatus(2).check("x"), "ProcessError", "ExitStatus.check")
    check_eq(ec.for_error("ArgumentError"), ec.USAGE, "for_error")

func test_environment():
    e := penv.minimal({"FOO": "1"}).prepend_path("/opt/x").set("BAR", true)
    check_eq(e.get("BAR"), "1", "bool -> 1")
    check(e.to_list()[0] == "BAR=1", "to_list trié")
    check_eq(e.run("sh", ["-c", "echo $FOO-$BAR-$LANG"]).stdout, "1-1-C\n", "Environment.run")
    d := e.copy().unset("FOO").set("Z", "z")
    df := e.diff(d)
    check_eq([df["added"], df["removed"]], [{"Z": "z"}, ["FOO"]], "diff")
    check_eq(e.expand("${FOO}/${NOPE:-def}"), "1/def", "expand")
    raises(() => e.set("A=B", 1), "ArgumentError", "nom invalide")
    check(len(penv.inherit().names()) > 0, "inherit")

func test_process_info():
    me := pinfo.current()
    check_eq(me.pid, os.pid(), "current.pid")
    check(me.rss > 0 and me.threads >= 1, "rss / threads")
    check(me.age() >= 0, "age")
    p := process.spawn("sleep", ["5"])
    check_eq([k.name for k in pinfo.children(me.pid)], ["sleep"], "children")
    check(pinfo.tree(me.pid).size() == 2, "tree")
    check(len(pinfo.find("sleep")) >= 1, "find")
    p.kill()
    p.wait()
    p.close()
    check(pinfo.get_or_null(999999999) == null, "absent")
    raises(() => pinfo.get(999999999), "ProcessError", "get absent")

func test_manager():
    m := pm.ProcessManager()
    evs := []
    m.on("exit", (ev) => append(evs, ev["name"]))
    m.add("ok", ["sh", "-c", "echo bonjour; echo erreur >&2"], {"output": "capture"})
    m.add("flaky", "sh -c 'exit 3'", {"restart": "on_failure", "max_restarts": 2, "backoff": 0.02})
    m.add("long", ["sleep", "30"])
    raises(() => m.add("ok", ["true"]), "ArgumentError", "nom en double")
    raises(() => m.add("x", ["true"], {"restart": "parfois"}), "ArgumentError", "politique inconnue")
    m.start_all()
    m.supervise(1.0)
    check_eq(m.logs("ok"), [("stdout", "bonjour"), ("stderr", "erreur")], "logs capturés")
    st := m.status()
    check_eq([st["ok"]["state"], st["flaky"]["state"], st["flaky"]["restarts"], st["long"]["state"]],
             ["exited", "failed", 2, "running"], "états")
    check_eq(len(evs), 4, "événements exit")
    m.stop_all(1)
    check_eq(m.status()["long"]["last_code"], -15, "stop_all : TERM")
    rs := pm.run_parallel([["sh", "-c", "sleep 0.1; echo a"], ["sh", "-c", "echo b"], ["sleep", "5"]], 2, 0.5)
    check_eq([r.stdout for r in rs], ["a\n", "b\n", ""], "run_parallel : sorties")
    check(rs[2].timed_out, "run_parallel : délai")

func test_pipe():
    t := pipe.create()
    t.send_line("bonjour")
    check(t.readable(), "readable")
    check_eq(t.receive_line(1.0), "bonjour", "receive_line")
    check(not t.readable(), "plus rien")
    d := pipe.duplex()
    d[0].send_line("ping")
    check_eq(d[1].read_line(1.0), "ping", "duplex a -> b")
    d[1].send_line("pong")
    check_eq(d[0].read_line(1.0), "pong", "duplex b -> a")
    d[0].close()
    check_eq(d[1].read_all(1.0), "", "duplex : fin du flux")
    d[1].close()
    s := pipe.stream(t)
    s.send_message("un\nmessage")
    s.send_json({"cmd": "start", "n": 3})
    check_eq(s.receive_message(1.0), "un\nmessage", "message délimité")
    check_eq(s.receive_json(1.0), {"cmd": "start", "n": 3}, "message JSON")
    t2 := pipe.create()
    t2.send("x")
    check_eq(len(pipe.poll([t.reader, t2.reader], 0.2)), 1, "poll")
    raises(() => t.receive(10, 0.05), "TimeoutError", "délai de lecture")
    t.close()
    t2.close()
    check_eq(pipe.pipeline([["printf", "b\na\nc\n"], ["sort"], ["head", "-n", "2"]]).stdout, "a\nb\n", "pipeline")
    check(np.with_temporary((f) => f.exists()), "fifo temporaire")
    check(np.with_temporary(_fifo_roundtrip), "fifo entre processus")

func _fifo_roundtrip(f):
    p := process.Command("cat").args([f.path]).stdout("pipe").spawn()
    w := f.open_writer(5)
    w.write_line("via fifo")
    w.close()
    out := p.read_all()
    p.wait()
    p.close()
    return out == "via fifo\n"

func test_signal():
    log := []
    t1 := signal.add("USR1", (n) => append(log, "a"))
    t2 := signal.add("USR1", (n) => append(log, "b"), 10)
    signal.once("USR1", (n) => append(log, "once"))
    signal.raise_signal("USR1")
    os.sleep(0.05)
    check_eq(log, ["b", "a", "once"], "priorités + once")
    signal.remove(t2)
    signal.raise_signal("USR1")
    os.sleep(0.05)
    check_eq(log, ["b", "a", "once", "a"], "remove")
    signal.remove(t1)
    f := signal.flag("USR2")
    signal.raise_signal("USR2")
    signal.raise_signal("USR2")
    os.sleep(0.05)
    check_eq(f.take(), 2, "flag : deux arrivées")
    check(not f.is_set(), "flag remis à zéro")
    f.close()
    arret := signal.graceful_shutdown((n) => append(log, "arret:" + n), ["TERM"])
    signal.raise_signal("TERM")
    check_eq(arret.wait(1), "TERM", "graceful_shutdown : demande")
    forced := false
    try:
        signal.raise_signal("TERM")
        os.sleep(0.2)
    catch InterruptError as e:
        forced = true
    check(forced, "graceful_shutdown : second signal")
    arret.cancel()
    check_eq(sc.SIGTERM, 15, "SIGTERM")
    check_eq(sc.number("sigusr1"), signal.number("USR1"), "number")
    check_eq(sc.default_action("CHLD"), "ignorer", "action par défaut")
    check(not sc.is_catchable("KILL"), "KILL non interceptable")
    check(len(sc.catchable()) > 20, "catchable")

func test_ipc():
    shm.unlink("alex-test-cnt")
    m := shm.SharedMemory("alex-test-cnt", 4096)
    ps2 := [process.spawn(ALEX, ["run", CHILD, "count", "alex-test-cnt"], null, null, "inherit", "null", "null") for i in 0..4]
    for p in ps2:
        p.wait()
        p.close()
    check_eq(m.get(8, "i64"), 800, "SharedCounter entre 4 processus")
    check_eq(m.get(16, "i64"), 800, "SharedMutex entre 4 processus")
    m.write(100, "bonjour")
    check_eq(m.read_cstring(100), "bonjour", "read_cstring")
    check(not m.wait(200, 0, 0.05), "wait : délai")
    raises(() => m.read(4090, 10), "IndexError", "hors limites")
    m.close()
    check(shm.unlink("alex-test-cnt"), "unlink")
    check(not shm.exists("alex-test-cnt"), "n'existe plus")
    check_eq(shm.with_temporary(64, (mm) => mm.size), 64, "with_temporary")
    backends := ["shm"]
    if mq.posix_supported():
        append(backends, "posix")
    for b in backends:
        mq.unlink("alex-test-q")
        q := mq.open("alex-test-q", 8, 256, b)
        p := process.spawn(ALEX, ["run", CHILD, "mq", "alex-test-q", b], null, null, "inherit", "null", "null")
        check_eq([q.receive(5), q.receive_json(5), q.receive(0.05)], ["salut du fils", {"n": 42}, null], "message_queue " + b)
        p.wait()
        p.close()
        q.close()
        mq.unlink("alex-test-q")
    q2 := mq.open("alex-test-q2", 2, 16, "shm")
    check_eq([q2.send("a"), q2.send("b"), q2.send("c", 0, 0.05), q2.size()], [true, true, false, 2], "file pleine")
    check_eq([q2.receive(), q2.receive(), q2.receive(0)], ["a", "b", null], "FIFO")
    raises(() => q2.send("0123456789abcdefg"), "IpcError", "message trop grand")
    q2.close()
    mq.unlink("alex-test-q2")
    sem.unlink("alex-test-sem")
    s := sem.NamedSemaphore("alex-test-sem", 1)
    check_eq([s.acquire(0), s.acquire(0.05)], [true, false], "sémaphore nommé")
    s.release()
    check_eq(s.value(), 1, "valeur")
    s.close()
    check(sem.unlink("alex-test-sem"), "sem unlink")
    srv := ls.listen("alex-test-sock")
    c := ls.connect("alex-test-sock", 1)
    k := srv.accept(1)
    c.send_line("ping")
    check_eq(k.read_line(1), "ping", "local_socket")
    k.send_message("multi\nligne")
    check_eq(c.receive_message(1), "multi\nligne", "local_socket : message")
    c.close()
    check_eq(k.receive_message(1), null, "fermeture")
    k.close()
    srv.close()
    raises(() => ls.connect("alex-test-sock", 0.5), "IpcError", "connexion refusée")
    abstract := ls.listen("@alex-test-abstrait")
    c2 := ls.connect("@alex-test-abstrait", 1)
    check(len(ls.wait([abstract], 1)) == 1, "nom abstrait")
    c2.close()
    abstract.close()
    srv2 := ch.serve_on("alex-test-chan")
    srv2.handle("somme", (a) => a[0] + a[1])
    srv2.handle("boom", (a) => 1 // 0)
    p := process.spawn(ALEX, ["run", CHILD, "client", "alex-test-chan"], null, null, "inherit", "pipe", "null")
    # le fils compile puis se connecte : service jusqu'à ses deux appels (au plus 20 s), puis encore un instant
    limite := os.monotonic_time() + 20.0
    while srv2.calls < 2 and os.monotonic_time() < limite:
        srv2.step(0.05)
    srv2.run(0.3)
    check_eq(p.read_all(), "5\nremote\nZeroDivisionError: division entière par zéro (int // 0)\n", "channel : appels distants")
    p.wait()
    p.close()
    srv2.close()
    pr := ch.pair()
    pr[0].send([1, "deux", {"trois": 3.0}])
    check_eq(pr[1].receive(1), [1, "deux", {"trois": 3.0}], "channel.pair")

func main():
    test_command()
    test_exit_code()
    test_environment()
    test_process_info()
    test_manager()
    test_pipe()
    test_signal()
    if ipc.supported():
        test_ipc()
    print(f"process / pipe / signal / ipc : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_process_pipe_signal_ipc : échecs")

main()
