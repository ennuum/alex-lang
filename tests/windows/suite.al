# Suite de tests SOUS WINDOWS de la chaîne ALEX pure (alex.exe + alexvm.exe, produits sous Linux par la chaîne
# ALEX elle-même). Lancée depuis la racine du projet, dans une invite de commandes ou PowerShell :
#
#   bin\alex.exe run tests\windows\suite.al [--quick] [--keep]
#
#   1. VM sous Windows (alex.exe run) : programmes de tests/native, sortie / erreur / code identiques aux références
#      enregistrées sous Linux (tests/windows/expected, sh tests/windows/record.sh) ;
#   2. compilateur natif SOUS WINDOWS (alex.exe build --native --windows) : exécutable produit identique octet pour
#      octet à celui produit sous Linux, exécuté : mêmes résultats que la VM, aussi avec ALEX_GC_STRESS=1 ;
#   3. spécificités Windows : ligne de commande (règles de citation de Microsoft), entrée CRLF, os / io en UTF-16 ;
#   4. bibliothèque standard : suites portables exécutées par la VM ;
#   5. interface graphique : backend Win32 du module ui (fenêtre réelle) et rendu hors écran (headless).
# Bilan final et code de sortie 0 si tout passe. Résultat détaillé aussi dans tests\windows\resultat.txt.
use os
use io
use string as s
use process
use crypto
from core use len, type
from collections use append

args := os.args()
QUICK := "--quick" in args
KEEP := "--keep" in args
ALEX := os.realpath(os.getenv("ALEX_SUITE_BIN", "bin/alex.exe"))
TMP := os.join(os.tmp_dir(), "alex_suite_" + str(os.pid()))
os.mkdir_all(TMP)
E := "tests/windows/expected"
log := []
count := {"ok": 0, "ko": 0}

func say(line):
    print(line)
    append(log, line)

func ok(what):
    count["ok"] = count["ok"] + 1
    say("ok    " + what)

func ko(what, detail=""):
    count["ko"] = count["ko"] + 1
    say("ÉCHEC " + what)
    if detail != "":
        for l in s.split(detail, "\n")[0:12]:
            say("        " + l)

func clean_err(t):
    out := []
    for l in s.split(s.replace(t, "\r\n", "\n"), "\n"):
        if l != "" and not s.starts_with(l, "-- terminé"):
            append(out, l)
    return s.join("\n", out)

func last_line(t):
    l := s.split(clean_err(t), "\n")
    return l[len(l) - 1]

func read(p):
    try:
        return io.read_file(p)
    catch e:
        return null

func run(prog, a, env=null, input=null, timeout=600.0):
    try:
        return process.run(prog, a, input, timeout, null, env)
    catch e:
        return process.Result(-1, "", e.type + ": " + e.message, false)

func diff_hint(want, got):
    wl := s.split(want, "\n")
    gl := s.split(got, "\n")
    i := 0
    while i < len(wl) and i < len(gl) and wl[i] == gl[i]:
        i += 1
    w := wl[i] if i < len(wl) else "<fin>"
    g := gl[i] if i < len(gl) else "<fin>"
    return "ligne " + str(i + 1) + " :\n  attendu : " + w + "\n  obtenu  : " + g

func norm(t):
    return s.replace(t, "\r\n", "\n")

say("== ALEX sous Windows : " + s.split(s.trim(run(ALEX, ["version"]).stdout), "\n")[0])
say("   " + os.name() + " " + os.version() + ", " + os.arch() + ", dossier temporaire " + TMP)

progs := []
for f in os.list_dir("tests/native"):
    if (s.starts_with(f, "ok_") or s.starts_with(f, "err_")) and s.ends_with(f, ".al"):
        append(progs, "tests/native/" + f)
append(progs, "tests/native/only/ok_tasks.al")
append(progs, "tests/native/only/err_tasks.al")
progs = sorted(progs)
if QUICK:
    progs = [p for p in progs if s.contains(p, "ok_arith") or s.contains(p, "ok_closures") or s.contains(p, "err_index") or s.contains(p, "ok_io_os") or s.contains(p, "ok_tasks")]

say("")
say("== 1. VM sous Windows (alex.exe run) contre les références Linux")
vm := {}
for src in progs:
    n := s.replace(os.basename(src), ".al", "")
    r := run(ALEX, ["run", src], {"ALEX_NO_TRACE": "1"})
    vm[n] = r
    want_out := norm(read(E + "/" + n + ".out"))
    want_err := clean_err(read(E + "/" + n + ".err"))
    want_rc := s.trim(read(E + "/" + n + ".rc"))
    if norm(r.stdout) != want_out:
        ko("vm " + n + " : sortie standard", diff_hint(want_out, norm(r.stdout)))
    elif str(r.code) != want_rc:
        ko("vm " + n + " : code " + str(r.code) + " au lieu de " + want_rc, clean_err(r.stderr))
    elif clean_err(r.stderr) != want_err:
        ko("vm " + n + " : sortie d'erreur", diff_hint(want_err, clean_err(r.stderr)))
    else:
        ok("vm " + n + " (code " + str(r.code) + ")")

say("")
say("== 2. compilateur natif sous Windows (alex.exe build --native --windows)")
for src in progs:
    n := s.replace(os.basename(src), ".al", "")
    exe := os.join(TMP, n + ".exe")
    b := run(ALEX, ["build", "--native", "--windows", src, "-o", exe])
    want_hash := read(E + "/" + n + ".exe.sha256")
    if b.code != 0:
        if want_hash == null:
            ok("natif " + n + " : refusé comme sous Linux")
        else:
            ko("natif " + n + " : compilation", clean_err(b.stderr))
        continue
    h := crypto.sha256(io.read_file(exe))
    same := want_hash != null and h == s.trim(want_hash)
    r := run(exe, [])
    v := vm[n]
    detail := ""
    if norm(r.stdout) != norm(v.stdout):
        detail = "sortie standard : " + diff_hint(norm(v.stdout), norm(r.stdout))
    elif r.code != v.code:
        detail = "code " + str(r.code) + " au lieu de " + str(v.code) + "\n" + clean_err(r.stderr)
    elif v.code != 0 and last_line(r.stderr) != last_line(v.stderr):
        detail = "erreur : " + last_line(r.stderr) + " au lieu de " + last_line(v.stderr)
    if detail != "":
        ko("natif " + n, detail)
        continue
    stress := ""
    if n != "ok_gc" and n != "err_recursion" and not QUICK:
        rs := run(exe, [], {"ALEX_GC_STRESS": "1"})
        if norm(rs.stdout) != norm(v.stdout):
            ko("natif " + n + " : résultat différent sous ALEX_GC_STRESS=1")
            continue
        stress = ", GC stress"
    if same:
        ok("natif " + n + " (identique à l'exécutable produit sous Linux" + stress + ")")
    else:
        ko("natif " + n + " : exécutable différent de celui produit sous Linux (" + h[0:12] + ")")

say("")
say("== 3. spécificités Windows")
W := "tests/native/windows"
exe := os.join(TMP, "win_args.exe")
if run(ALEX, ["build", "--native", "--windows", W + "/win_args.al", "-o", exe]).code == 0:
    r := run(exe, ["simple", "deux mots", "", "guillemet \" dedans", "barres \\\\ et fin\\", "\\\"début", "accents été ☀ 😀", "a\\\\\\\"b", "\ttab"])
    want := norm(read(W + "/win_args_expected.txt"))
    if norm(r.stdout + r.stderr) == want:
        ok("win_args (ligne de commande CreateProcess / CommandLineToArgvW)")
    else:
        ko("win_args", diff_hint(want, norm(r.stdout + r.stderr)))
else:
    ko("win_args : compilation")
exe = os.join(TMP, "win_input.exe")
if run(ALEX, ["build", "--native", "--windows", W + "/win_input.al", "-o", exe]).code == 0:
    r := run(exe, [], null, "abc\r\nété\r\n\r\nx y\nfin\r\n")
    want := read(W + "/win_input_expected.txt")
    if r.stdout + r.stderr == want or norm(r.stdout + r.stderr) == norm(want):
        ok("win_input (entrée par tube, CRLF)")
    else:
        ko("win_input", diff_hint(norm(want), norm(r.stdout + r.stderr)))
else:
    ko("win_input : compilation")
exe = os.join(TMP, "win_os.exe")
if run(ALEX, ["build", "--native", "--windows", W + "/win_os.al", "-o", exe]).code == 0:
    d := os.join(TMP, "dossier é")
    os.mkdir_all(d)
    r := run(exe, [], {"ALEX_WIN_VAR": "oui", "ALEX_WIN_DIR": os.realpath(d)})
    want := norm(read(W + "/win_os_expected.txt"))
    if norm(r.stdout + r.stderr) == want:
        ok("win_os (os et io sous Windows, chemins UTF-16)")
    else:
        ko("win_os", diff_hint(want, norm(r.stdout + r.stderr)))
else:
    ko("win_os : compilation")
r := run(ALEX, ["build", "--native", "--windows", W + "/win_posix.al", "-o", os.join(TMP, "p.exe")])
if r.code != 0 and s.contains(r.stderr, "indisponible avec --windows"):
    ok("refus de posix avec --windows")
else:
    ko("refus de posix", clean_err(r.stderr))
exe = os.join(TMP, "calc.exe")
r = run(ALEX, ["build", "--native", "--windows", "--gui", "examples/windows/calculatrice.al", "-o", exe])
if r.code == 0 and os.isfile(exe):
    ok("calculatrice : application graphique (--gui) compilée sous Windows")
else:
    ko("calculatrice : compilation --gui", clean_err(r.stderr))
# exécutable autonome (VM + bytecode) et compilation en bytecode
alb := os.join(TMP, "prog.albc")
r = run(ALEX, ["build", "examples/comprehensions.al", "-o", alb])
r2 := run(os.realpath("bin/alexvm.exe"), [alb])
r3 := run(ALEX, ["run", "examples/comprehensions.al"])
if r.code == 0 and r2.code == 0 and norm(r2.stdout) == norm(r3.stdout) and r2.stdout != "":
    ok("bytecode : alex build + alexvm.exe prog.albc")
else:
    ko("bytecode + alexvm.exe", clean_err(r.stderr + r2.stderr))
st := os.join(TMP, "autonome.exe")
r = run(ALEX, ["build", "--standalone", "examples/comprehensions.al", "-o", st])
if r.code == 0:
    r2 = run(st, [])
    if r2.code == 0 and norm(r2.stdout) == norm(r3.stdout):
        ok("exécutable autonome (--standalone)")
    else:
        ko("exécutable autonome : exécution", clean_err(r2.stderr))
else:
    ko("exécutable autonome : construction", clean_err(r.stderr))

say("")
say("== 4. bibliothèque standard (VM)")
SUITES := ["tests/test_path.al", "tests/test_csv.al", "tests/test_xml.al", "tests/test_regex.al", "tests/test_crypto.al",
    "tests/test_json.al", "tests/test_filesystem.al", "tests/test_file.al", "tests/test_time.al", "tests/test_datetime.al",
    "tests/test_string_chr_ord_slice.al", "tests/test_testing_logging.al", "tests/test_functional.al", "tests/test_os.al",
    "tests/test_pure_stdlib.al", "tests/test_constants.al", "tests/test_units.al", "tests/test_array.al", "tests/test_linalg.al",
    "tests/test_stats.al", "tests/lang/test_language.al", "tests/lang/test_runtime.al", "tests/lang/test_closures.al",
    "tests/lang/test_oop.al", "tests/lang/test_exceptions.al", "tests/lang/test_comprehensions.al", "tests/lang/test_async.al",
    "tests/lang/test_builtins.al", "tests/lang/test_pythonic.al", "tests/lang/test_gc.al", "tests/lang/test_dict_order.al"]
if QUICK:
    SUITES = SUITES[0:4]
for t in SUITES:
    r := run(ALEX, ["run", t])
    if r.code == 0:
        ok(t)
    else:
        ko(t + " (code " + str(r.code) + ")", clean_err(r.stdout + "\n" + r.stderr))

say("")
say("== 5. interface graphique")
r = run(ALEX, ["run", "tests/windows/ui_win32.al"], null, null, 120.0)
if r.code == 0 and s.contains(r.stdout, "UI WIN32 : OK"):
    ok("backend Win32 du module ui (fenêtre réelle, événements, rendu)")
else:
    ko("backend Win32 du module ui (code " + str(r.code) + ")", clean_err(r.stdout + "\n" + r.stderr))
for t in ["tests/ui/test_ui_headless.al", "tests/ui/test_interact.al", "tests/ui/test_edit.al"]:
    r = run(ALEX, ["run", t], {"ALEX_UI_BACKEND": "headless"})
    if r.code == 0:
        ok(t + " (headless)")
    else:
        ko(t + " (headless)", clean_err(r.stdout + "\n" + r.stderr))

say("")
say("== bilan : " + str(count["ok"]) + " réussis, " + str(count["ko"]) + " échecs")
io.write_file("tests/windows/resultat.txt", s.join("\n", log) + "\n")
if not KEEP:
    try:
        os.rmdir(TMP, true)
    catch e:
        say("(dossier temporaire conservé : " + TMP + ")")
os.exit(0 if count["ko"] == 0 else 1)
