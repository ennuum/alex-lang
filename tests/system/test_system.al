# Test de system.signal, system.environment, system.system_info, des façades system.process /
# system.filesystem / system.time, et de memory.virtual.

from core use len, type
from collections use append, contains_key
use string as s
use os
use system.signal as signal
use system.environment as env
use system.system_info as info
use system.process as process
use system.filesystem as fs
use system.time as time
use memory.virtual as vm
use concurrency.thread as thread
use tests.system.system_workers as w

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

func error_of(f):
    try:
        f()
    catch e:
        return e.type
    return "aucune erreur"

# Calcul récursif avec des valeurs intermédiaires sur la pile : un gestionnaire inséré au milieu ne doit
# rien en déranger.
func fib(n):
    if n < 2:
        return n
    return fib(n - 1) + fib(n - 2)

func test_signal():
    check(signal.supported(), "signal.supported")
    check_eq([signal.number("INT"), signal.number("sigterm"), signal.name_of(10)], [2, 15, "USR1"], "noms et numéros")
    check(contains_key({n: 1 for n in signal.names()}, "WINCH"), "names")
    check_eq(error_of(() => signal.number("NOPE")), "ArgumentError", "signal inconnu")
    check_eq(error_of(() => signal.on("KILL", (n) => null)), "ArgumentError", "KILL non interceptable")
    check_eq(error_of(() => signal.on("SEGV", (n) => null)), "ArgumentError", "SEGV non interceptable")
    check_eq(error_of(() => signal.on("USR1", 3)), "TypeError", "gestionnaire non fonction")

    # Gestionnaire appelé entre deux instructions.
    got := []
    signal.on("USR1", (n) => append(got, n))
    signal.raise_signal("USR1")
    x := 0
    for i in 0..100:
        x += i
    check_eq([got, x], [["USR1"], 4950], "on : gestionnaire exécuté")

    # Signaux envoyés par un autre processus pendant un calcul profond : résultat intact.
    got2 := []
    signal.on("USR2", (n) => append(got2, fib(5)))
    pid := os.pid()
    sender := process.spawn("sh", ["-c", "for i in 1 2 3 4 5; do sleep 0.05; kill -USR2 " + str(pid) + "; done"])
    total := 0
    t0 := os.monotonic_time()
    while len(got2) < 5 and os.monotonic_time() - t0 < 10:
        total += fib(15)
    sender.wait()
    check_eq(got2, [5, 5, 5, 5, 5], "signaux d'un autre processus pendant un calcul")
    check(total > 0 and total % 610 == 0, "calcul non perturbé")

    # Une exception levée par le gestionnaire part de l'endroit où en était le programme ; finally s'applique.
    signal.interrupt_on("INT")
    trace := []
    t1 := os.monotonic_time()
    try:
        try:
            signal.raise_signal("INT")
            os.sleep(5)
            append(trace, "après sleep")
        finally:
            append(trace, "finally")
    catch e:
        append(trace, e.type)
    check_eq(trace, ["finally", "InterruptError"], "interrupt_on : InterruptError et finally")
    check(os.monotonic_time() - t1 < 2, "sleep interrompu par le signal")
    signal.reset("INT")

    # with_handler : gestionnaire temporaire, puis comportement d'origine.
    seen := []
    r := signal.with_handler("HUP", (n) => append(seen, n), () => signal.raise_signal("HUP") or "fait")
    check_eq([r, seen], ["fait", ["HUP"]], "with_handler")

    # Surveillance sans gestionnaire.
    signal.watch("WINCH")
    check_eq(signal.received("WINCH"), false, "received : rien")
    signal.raise_signal("WINCH")
    signal.raise_signal("WINCH")
    check_eq(signal.pending("WINCH"), 2, "pending")
    check_eq(signal.received("WINCH"), true, "received")
    check_eq(signal.pending("WINCH"), 0, "received consomme")
    check_eq(signal.wait("WINCH", 0.1), null, "wait : délai")
    process.spawn("sh", ["-c", "sleep 0.1; kill -WINCH " + str(pid)])
    t2 := os.monotonic_time()
    check_eq(signal.wait(["WINCH"], 5.0), "WINCH", "wait : signal d'un autre processus")
    check(os.monotonic_time() - t2 < 3, "wait réveillé aussitôt")
    signal.reset("WINCH")

    # Pendant wait, les gestionnaires de on() s'exécutent.
    signal.watch("ALRM")
    got3 := []
    signal.on("USR1", (n) => append(got3, n))
    process.spawn("sh", ["-c", "sleep 0.05; kill -USR1 " + str(pid) + "; sleep 0.1; kill -ALRM " + str(pid)])
    check_eq([signal.wait("ALRM", 5.0), got3], ["ALRM", ["USR1"]], "wait + gestionnaire")
    signal.reset("ALRM")

    # ignore, envoi à un processus.
    signal.ignore("USR1")
    signal.raise_signal("USR1")
    check(true, "ignore : le programme continue")
    signal.reset("USR1")
    signal.reset("USR2")
    child := process.spawn("sleep", ["10"])
    signal.send(child.pid(), "TERM")
    check_eq(child.wait(), -15, "send TERM à un fils")
    check_eq(error_of(() => signal.send(999999, "TERM")), "ProcessError", "send : processus absent")

    # Un fil ne peut pas intercepter.
    t := thread.spawn(w.try_on, [])
    check_eq(t.join(), "ThreadError", "on depuis un fil")

func test_environment():
    env.set("ALEX_T_INT", 42)
    env.set("ALEX_T_BOOL", true)
    env.set("ALEX_T_LIST", "a::b:c")
    check_eq([env.get("ALEX_T_INT"), env.get_int("ALEX_T_INT"), env.get_bool("ALEX_T_BOOL")], ["42", 42, true], "set / get typés")
    check_eq(env.get_list("ALEX_T_LIST"), ["a", "b", "c"], "get_list")
    check_eq([env.get_int("ALEX_T_ABSENT", 7), env.get_bool("ALEX_T_ABSENT", false), env.get("ALEX_T_ABSENT")], [7, false, null], "valeurs par défaut")
    env.set("ALEX_T_BAD", "12x")
    check_eq(error_of(() => env.get_int("ALEX_T_BAD")), "ArgumentError", "get_int illisible")
    check_eq(error_of(() => env.get_bool("ALEX_T_BAD")), "ArgumentError", "get_bool illisible")
    check_eq(env.get_int("ALEX_T_INT") + env.get_int("ALEX_T_ABSENT", 0), 42, "get_int : int")
    check_eq(error_of(() => env.set("ALEX_T", [1])), "TypeError", "set d'une liste")
    check_eq(error_of(() => env.get("")), "TypeError", "nom vide")
    check_eq(env.expand("$ALEX_T_INT-${ALEX_T_INT}-${ALEX_T_ABSENT:-def}-$ALEX_T_ABSENT-$$-$-$1"), "42-42-def--$-$-$1", "expand")
    check_eq(env.expand("${X} et $Y", {"X": 1, "Y": "y"}), "1 et y", "expand avec vars")
    r := env.with_vars({"ALEX_T_INT": "9", "ALEX_T_NEW": "n", "ALEX_T_BOOL": null}, () => process.run("sh", ["-c", "echo $ALEX_T_INT$ALEX_T_NEW${ALEX_T_BOOL:-vide}"]).stdout)
    check_eq([r, env.get("ALEX_T_INT"), env.has("ALEX_T_NEW"), env.get("ALEX_T_BOOL")], ["9nvide\n", "42", false, "1"], "with_vars puis rétablissement")
    check(contains_key(env.all(), "ALEX_T_INT") and len(env.names()) > 3, "all / names")
    check(len(env.path_dirs()) > 0 and env.find_program("sh") != null, "path_dirs / find_program")
    check(s.ends_with(env.program(), "test_system.al"), "program")
    check_eq([env.home(), env.cwd(), env.pid()], [os.home(), os.cwd(), os.pid()], "home, cwd, pid")
    for n in ["ALEX_T_INT", "ALEX_T_BOOL", "ALEX_T_LIST", "ALEX_T_BAD"]:
        env.unset(n)
    check(not env.has("ALEX_T_INT"), "unset")

func test_system_info():
    check_eq(info.platform(), os.platform(), "platform")
    check(type(info.cpu_count()) == "int" and info.cpu_count() >= 1, "cpu_count")
    m := info.memory()
    check(m["total"] > 0, "memory.total")
    if info.platform() == "linux":
        check(m["available"] > 0 and m["available"] <= m["total"] and m["used"] == m["total"] - m["available"], "memory.available / used")
        check(info.uptime() > 0 and info.boot_time() < os.time(), "uptime / boot_time")
        check(type(info.kernel_version()) == "str", "kernel_version")
        check(len(info.mounts()) > 0, "mounts")
    la := info.load_average()
    check(la == null or (len(la) == 3 and la[0] >= 0), "load_average")
    d := info.disk_usage("/")
    check(d["total"] > 0 and d["available"] <= d["total"] and d["used"] + d["free"] == d["total"], "disk_usage")
    check_eq(info.disk_usage("/chemin/absent"), null, "disk_usage d'un chemin absent")
    check_eq([info.format_bytes(512), info.format_bytes(1536), info.format_bytes(3 * 1073741824), info.format_bytes(null)], ["512 o", "1.5 Kio", "3.0 Gio", "?"], "format_bytes")
    sm := info.summary()
    check(contains_key(sm, "memory") and contains_key(sm, "cpu_model") and sm["pid"] == os.pid(), "summary")

func test_facades():
    tmp := fs.make_temp_dir("alex_sys_")
    sub := tmp + "/a/b"
    fs.mkdir_all(sub)
    fs.ensure_file(sub + "/f.txt")
    check(fs.is_dir(sub) and fs.exists(sub + "/f.txt"), "filesystem : mkdir_all, ensure_file")
    check(len(fs.find(tmp, "*.txt")) == 1, "filesystem : find")
    du := fs.disk_usage(tmp)
    check(du["available"] > 0, "filesystem : disk_usage")
    check_eq(error_of(() => fs.disk_usage(tmp + "/absent")), "IoError", "filesystem : disk_usage absent")
    fs.remove_tree(tmp)
    check(not fs.exists(tmp), "filesystem : remove_tree")

    check_eq(process.run("echo", ["a"]).stdout, "a\n", "process.run")
    check_eq(process.Command("printf").args(["%s", "b"]).run().stdout, "b", "process.Command")
    check_eq(process.PIPE, "pipe", "process.PIPE")
    check(process.which("sh") != null, "process.which")

    sw := time.Stopwatch(true)
    time.sleep(0.01)
    check(sw.elapsed() >= 0.009, "time.Stopwatch")
    check_eq([time.is_leap(2024), time.MONDAY], [true, 0], "time : calendrier")
    dl := time.Deadline(10)
    check(not dl.expired(), "time.Deadline")

    r := vm.map(2 * vm.page_size())
    r.write("u32", 7, 0)
    check_eq([r.read("u32", 0), vm.RW], [7, 3], "memory.virtual")
    r.unmap()

func main():
    test_signal()
    test_environment()
    test_system_info()
    test_facades()
    print(f"system : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_system : échecs")

if thread.is_main():
    main()
