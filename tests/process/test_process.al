# Test du module process : exécution, pipes, délais, signaux, groupes, erreurs.
# POSIX uniquement (utilise sh, cat, sleep, env).

from core use len, type
from collections use append, clear
use string as s
use os as os
use process as proc

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

# Vérifie que f() / f(a) lève une erreur du type donné.
func raises0(f, error_type, label):
    got := "aucune erreur"
    try:
        f()
    catch e:
        got = e.type
    check_eq(got, error_type, label)

func raises1(f, a, error_type, label):
    got := "aucune erreur"
    try:
        f(a)
    catch e:
        got = e.type
    check_eq(got, error_type, label)

# --- cibles des tests d'erreurs (pas de lambdas dans le langage) ---
func _bad_cwd(x):
    return sh("true").cwd("/inexistant_xyz").run()
func _timeout_checked(x):
    return proc.run("sleep", ["30"], null, 0.1, null, null, true)
func _missing_program(x):
    return proc.run("programme_inexistant_xyz")
func _args_not_list(x):
    return proc.run("echo", "pas une liste")
func _bad_stdout_mode(x):
    return proc.Command("echo").stdout("nimporte").spawn()
func _bad_stdin_mode(x):
    return proc.Command("echo").stdin("stdout").spawn()
func _bad_signal(x):
    p := proc.spawn("sleep", ["1"])
    try:
        p.kill("NOPE")
    catch e:
        p.kill("KILL")
        p.wait()
        p.close()
        raise(e.type, e.message)
func _read_default(p):
    return p.read()
func _read_bad_stream(p):
    return p.read("autre")
func _poll_it(p):
    return p.poll()
func _write_x(p):
    return p.write("x")
func _write_big(p):
    return p.write(s.repeat("x", 100000))
func _check_it(r):
    return r.check()
func _read_line_short(p):
    return p.read_line("stdout", 0.05)
func _check_out_fail(x):
    return proc.check_output("sh", ["-c", "exit 2"])

func run(name, fn):
    clear(notes)
    before := stats[1]
    fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

func sh(script):
    return proc.Command("sh", ["-c", script])

func t_basic():
    r := proc.run("echo", ["bonjour", "monde"])
    check_eq(r.code, 0, "code")
    check_eq(r.stdout, "bonjour monde\n", "stdout")
    check_eq(r.stderr, "", "stderr vide")
    check(r.ok(), "ok()")

func t_exit_code():
    r := proc.run("sh", ["-c", "echo err >&2; exit 3"])
    check_eq(r.code, 3, "code 3")
    check_eq(r.stderr, "err\n", "stderr capturé")
    check(not r.ok(), "ok() faux")
    raises0(r.check, "ProcessError", "check()")

func t_no_shell():
    # Un argument avec métacaractères reste littéral : aucun shell.
    r := proc.run("echo", ["$HOME; echo piraté"])
    check_eq(r.stdout, "$HOME; echo piraté\n", "littéral")
    proc.run("echo", [], null, null, null, null, false)

func t_input_large():
    # 1 Mio dans les deux sens : détecte un interblocage lecture/écriture.
    big := s.repeat("0123456789abcdef", 65536)
    r := proc.run("cat", [], big)
    check_eq(len(r.stdout), len(big), "écho complet de 1 Mio")
    check_eq(r.code, 0, "cat code")

func t_cwd_env():
    r := sh("pwd; echo $FOO").cwd("/tmp").env({"FOO": "bar"}).run()
    check_eq(r.stdout, "/tmp\nbar\n", "cwd + env")
    r = sh("echo ${HOME:-vide}").env({"HOME": null}).run()
    check_eq(r.stdout, "vide\n", "variable supprimée (null)")
    r = proc.Command("env").clear_env().env({"A": "1"}).run()
    check_eq(r.stdout, "A=1\n", "clear_env")
    raises1(_bad_cwd, null, "IoError", "cwd inexistant")

func t_merge():
    r := sh("echo out; echo err >&2").stderr("stdout").run()
    check_eq(s.contains(r.stdout, "out"), true, "out présent")
    check_eq(s.contains(r.stdout, "err"), true, "err fusionné")
    check_eq(r.stderr, "", "stderr vide")

func t_interactive():
    p := proc.Command("cat").stdin("pipe").stdout("pipe").spawn()
    p.write_line("a")
    check_eq(p.read_line(), "a", "ligne a")
    p.write("b\r\nc")
    check_eq(p.read_line(), "b", "CRLF retiré")
    p.close_stdin()
    check_eq(p.read_line(), "c", "dernière ligne sans \\n")
    check_eq(p.read_line(), null, "fin de flux")
    check_eq(p.wait(), 0, "code")
    p.close()

func t_empty_line_vs_eof():
    p := sh("printf '\\n'").stdout("pipe").spawn()
    check_eq(p.read_line(), "", "ligne vide")
    check_eq(p.read_line(), null, "puis EOF")
    p.wait()
    p.close()

func t_read_timeout():
    p := sh("sleep 0.4; echo tard").stdout("pipe").spawn()
    check_eq(p.read("stdout", 100, 0.05), null, "read : délai")
    raises1(_read_line_short, p, "TimeoutError", "read_line : délai")
    check_eq(p.read_line(), "tard", "la donnée arrive ensuite")
    p.wait()
    p.close()

func t_utf8_boundary():
    # Lecture par petits morceaux impairs : aucun caractère coupé en deux.
    p := sh("i=0; while [ $i -lt 3000 ]; do printf 'é'; i=$((i+1)); done").stdout("pipe").spawn()
    total := 0
    broken := 0
    while true:
        chunk := p.read("stdout", 7)
        if chunk == "":
            break
        if s.replace(chunk, "é", "") != "":
            broken = broken + 1
        total = total + len(chunk)
    check_eq(total, 3000, "3000 caractères")
    check_eq(broken, 0, "aucun morceau invalide")
    p.wait()
    p.close()

func t_timeout_term():
    t0 := os.monotonic_time()
    r := proc.run("sleep", ["30"], null, 0.2)
    check(r.timed_out, "timed_out")
    check_eq(r.code, -15, "tué par TERM")
    check(os.monotonic_time() - t0 < 5.0, "rapide")
    raises1(_timeout_checked, null, "TimeoutError", "check + délai")

func t_timeout_kill_escalation():
    # TERM ignoré (hérité par sleep) : seule l'escalade KILL aboutit.
    t0 := os.monotonic_time()
    r := sh("trap '' TERM; sleep 30").run(null, 0.2, 0.3)
    check(r.timed_out, "timed_out")
    check_eq(r.code, -9, "tué par KILL")
    check(os.monotonic_time() - t0 < 5.0, "rapide")

func t_timeout_keeps_partial_output():
    r := sh("echo début; sleep 30").run(null, 0.3)
    check(r.timed_out, "timed_out")
    check_eq(r.stdout, "début\n", "sortie partielle conservée")

func t_group_kill():
    # Le petit-fils garde le pipe stdout ouvert : sans kill de groupe,
    # read_all() resterait bloqué ~30 s.
    p := sh("sleep 30 & echo $!; wait").stdout("pipe").group().spawn()
    check(p.read_line() != null, "pid du petit-fils")
    t0 := os.monotonic_time()
    p.stop(1.0, true)
    p.read_all()
    check(os.monotonic_time() - t0 < 5.0, "EOF rapide : descendants tués")
    p.close()

func t_lifecycle():
    p := proc.spawn("sleep", ["30"])
    check(p.running(), "running")
    check_eq(p.poll(), null, "poll null")
    check_eq(p.wait(0.05), null, "wait : délai")
    p.kill("KILL")
    check_eq(p.wait(), -9, "code -9")
    check(not p.running(), "plus running")
    p.kill("TERM")  # déjà attendu : sans effet, jamais d'erreur
    check_eq(p.stop(), -9, "stop idempotent")
    raises1(_bad_signal, null, "ArgumentError", "signal inconnu")
    p.close()

func t_communicate_timeout():
    p := sh("echo un; sleep 30").stdout("pipe").spawn()
    r := p.communicate(null, 0.3)
    check(r.timed_out, "timed_out")
    check_eq(r.stdout, "un\n", "partiel")
    check_eq(r.code, null, "code inconnu")
    p.stop(1.0)
    p.close()

func t_epipe():
    p := proc.Command("true").stdin("pipe").spawn()
    p.wait()
    raises1(_write_big, p, "IoError", "écriture vers un fils terminé")
    p.close()

func t_errors():
    raises1(_missing_program, null, "IoError", "programme absent")
    raises1(_args_not_list, null, "TypeError", "args non liste")
    raises1(_bad_stdout_mode, null, "ArgumentError", "mode invalide")
    raises1(_bad_stdin_mode, null, "ArgumentError", "stdout interdit pour stdin")
    p := proc.Command("echo").stdout("null").spawn()
    raises1(_read_default, p, "IoError", "flux non capturé")
    raises1(_write_x, p, "IoError", "stdin non ouvert")
    raises1(_read_bad_stream, p, "ArgumentError", "flux inconnu")
    p.wait()
    p.close()
    p.close()  # idempotent
    raises1(_poll_it, p, "ArgumentError", "Process fermé")

func t_which():
    check(proc.which("sh") != null, "sh trouvé")
    check_eq(proc.which("programme_inexistant_xyz"), null, "absent")
    check_eq(proc.which("/bin/sh") != null, true, "chemin explicite")

func t_check_output():
    check_eq(proc.check_output("echo", ["ok"]), "ok\n", "check_output")
    raises1(_check_out_fail, null, "ProcessError", "échec")


func main():
    before := proc.open_handles()
    run("run : capture de base", t_basic)
    run("run : code de sortie, stderr, check()", t_exit_code)
    run("run : aucun shell (pas d'injection)", t_no_shell)
    run("run : 1 Mio dans les deux sens sans interblocage", t_input_large)
    run("Command : cwd, env, suppression, clear_env", t_cwd_env)
    run("Command : stderr fusionné dans stdout", t_merge)
    run("Process : dialogue interactif (cat)", t_interactive)
    run("Process : ligne vide ≠ fin de flux", t_empty_line_vs_eof)
    run("Process : délais de lecture", t_read_timeout)
    run("Process : pas de coupure UTF-8", t_utf8_boundary)
    run("run : timeout -> TERM", t_timeout_term)
    run("run : timeout -> escalade KILL", t_timeout_kill_escalation)
    run("run : timeout garde la sortie partielle", t_timeout_keeps_partial_output)
    run("Process : kill de groupe atteint les descendants", t_group_kill)
    run("Process : poll / wait / kill / stop", t_lifecycle)
    run("Process : communicate avec délai", t_communicate_timeout)
    run("Process : EPIPE -> IoError, pas de crash", t_epipe)
    run("Erreurs d'usage et système", t_errors)
    run("which", t_which)
    run("check_output", t_check_output)
    check_eq(proc.open_handles(), before, "aucun handle fuité par la suite")
    if proc.open_handles() != before:
        print(f"  [ÉCHEC]  handles ouverts : {proc.open_handles()} (début : {before})")

if not proc.supported():
    print("process non supporté ici : test ignoré")
else:
    main()

print(f"process : {stats[0]} vérifications OK, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_process : échecs")
