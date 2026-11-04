# ALEX — commands.test
#
# `alexc test [chemins...] [--filter texte | -k texte] [--json] [--list] [-j N]` : exécuteur de tests, comme
# alex::tooling (TestRunner.cpp). Chaque fichier test_*.al / *_test.al est exécuté dans un processus fils
# `alexc __test-file fichier filtre` (fonctions test_* sans paramètre enregistrées par un épilogue ajouté à la
# source, sauf si le fichier lance lui-même testing.run) ; les résultats arrivent en lignes « @@ALEXTEST {json} ».
#
#   use commands.test as ct
#   code := ct.run(["tests"], "/chemin/alexc")
#   tests := ct.discover("tests/test_x.al")     # {"tests": [[nom, ligne]...], "self_running", "has_functions"}
#
# Erreurs : aucune levée.

from core use len, type, to_int, to_float
from collections use append
use string as _s
use os as _os
use io as _io
use process as _pr
use commands.common as cc
use parser as _bp

func is_test_file_name(name):
    if len(name) < 4 or not cc.ends_with(name, ".al"):
        return false
    return _s.starts_with(name, "test_") or (len(name) > 8 and cc.ends_with(name, "_test.al"))

func _is_word(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '_'

# Noms des tests enregistrés sur une ligne : test("nom" / skip("nom" (regex \b(?:test|skip)\(\s*"([^"]+)").
func _registered(line):
    out := []
    n := len(line)
    i := 0
    while i < n:
        k := 0
        if i + 5 <= n and _s.substring(line, i, i + 5) == "test(":
            k = 5
        elif i + 5 <= n and _s.substring(line, i, i + 5) == "skip(":
            k = 5
        if k == 0 or (i > 0 and _is_word(line[i - 1])):
            i += 1
            continue
        j := i + k
        while j < n and (line[j] == ' ' or line[j] == '\t'):
            j += 1
        if j < n and line[j] == '"':
            e := j + 1
            while e < n and line[e] != '"':
                e += 1
            if e < n and e > j + 1:
                append(out, _s.substring(line, j + 1, e))
                i = e + 1
                continue
        i += 1
    return out

func discover(file):
    tests := []
    text := ""
    try:
        text = _io.read_file(file)
    catch e:
        text = ""
    self_running := _s.contains(text, "testing.run(") or _s.contains(text, ".run_tests(")
    has_fns := false
    try:
        prog := _bp.parse_text(text, file)
        for st in prog.top_level:
            if st.kind == "FunctionDecl" and _s.starts_with(st.name, "test_") and len(st.params) == 0:
                append(tests, [st.name, st.line])
                has_fns = true
    catch e:
        pass
    ln := 0
    for line in _s.split(text, "\n"):
        ln += 1
        h := _s.find(line, "#")
        if h >= 0:
            q := _s.find(line, "\"")
            if q < 0 or q > h:
                continue
        for name in _registered(line):
            dup := false
            for c in tests:
                if c[0] == name:
                    dup = true
            if not dup:
                append(tests, [name, ln])
    return {"tests": tests, "self_running": self_running, "has_functions": has_fns}

func epilogue(tests, filter):
    s := "\nuse testing as __alex_testing\n"
    for t in tests:
        if _s.starts_with(t[0], "test_"):
            s += "__alex_testing.test(\"" + t[0] + "\", " + t[0] + ")\n"
    s += "__alex_testing.run(true, "
    if filter == "":
        s += "null"
    else:
        s += "\""
        for c in filter:
            if c == '"' or c == '\\':
                s += "\\"
            s += str(c)
        s += "\""
    return s + ")\n"

func _abs_norm(p):
    return _os.normalize(_os.absolute(p))

func find_test_files(paths):
    out := []
    for p in paths:
        if _os.isfile(p):
            append(out, _abs_norm(p))
            continue
        if not _os.isdir(p):
            continue
        for f in cc.walk_files(p, is_test_file_name, true):
            append(out, _abs_norm(f))
    out = cc.sort_strings(out)
    uniq := []
    for f in out:
        if len(uniq) == 0 or uniq[len(uniq) - 1] != f:
            append(uniq, f)
    return uniq

func relative(p):
    cwd := _os.cwd()
    if p == cwd:
        return "."
    pre := cwd if cc.ends_with(cwd, "/") else cwd + "/"
    if _s.starts_with(p, pre):
        return _s.substring(p, len(pre), len(p))
    return p

func fixed(x, d):
    m := 1
    k := 0
    while k < d:
        m *= 10
        k += 1
    v := to_int(x * m + 0.5) if x >= 0 else -to_int(-x * m + 0.5)
    neg := v < 0
    if neg:
        v = -v
    ip := v // m
    fp := str(v % m)
    while len(fp) < d:
        fp = "0" + fp
    return ("-" if neg else "") + str(ip) + ("." + fp if d > 0 else "")

func fmt_ms(s):
    if s < 1.0:
        return fixed(s * 1000, 1) + " ms"
    return fixed(s, 2) + " s"

func _is_summary(line):
    # ^\d+ réussi\(s\), \d+ échec\(s\), \d+ erreur\(s\), \d+ ignoré\(s\) sur \d+
    parts := [" réussi(s), ", " échec(s), ", " erreur(s), ", " ignoré(s) sur "]
    i := 0
    for sep in parts:
        j := i
        while j < len(line) and line[j] >= '0' and line[j] <= '9':
            j += 1
        if j == i:
            return false
        if not _s.starts_with(_s.substring(line, j, len(line)), sep):
            return false
        i = j + len(sep)
    return i < len(line) and line[i] >= '0' and line[i] <= '9'

# « N échecs » d'un script sans test structuré : ([1-9]\d*) (échecs?|échec\(s\)|failed|erreur\(s\))
func _has_failures(text):
    n := len(text)
    i := 0
    while i < n:
        if text[i] >= '1' and text[i] <= '9':
            j := i
            while j < n and text[j] >= '0' and text[j] <= '9':
                j += 1
            rest := _s.substring(text, j, len(text))
            for w in [" échec", " failed", " erreur(s)"]:
                if _s.starts_with(rest, w):
                    return true
            i = j
            continue
        i += 1
    return false

class FileRun:
    func init(file):
        self.file = file
        self.discovered = []
        self.results = []
        self.output = ""
        self.exit_code = 0
        self.duration = 0.0
        self.proc = null
        self.buf = []
        self.t0 = 0.0
        self.done = false

func _start(fr, exe, filter):
    fr.t0 = _os.monotonic_time()
    try:
        fr.proc = _pr.Command(exe, ["__test-file", fr.file, filter]).stdout("pipe").stderr("stdout").spawn()
    catch e:
        fr.proc = null
        fr.exit_code = -1
        fr.output = "impossible de lancer " + exe
        fr.done = true

func _finish(fr):
    code := fr.proc.wait()
    fr.proc.close()
    fr.exit_code = code if code != null else -1
    if fr.exit_code < 0:
        fr.exit_code = 128 - fr.exit_code
    fr.duration = _os.monotonic_time() - fr.t0
    all := _s.join("", fr.buf)
    fr.buf = []
    lines := _s.split(all, "\n")
    if len(lines) > 0 and lines[len(lines) - 1] == "":
        lines = lines[0:len(lines) - 1]
    out := []
    for line in lines:
        if cc.ends_with(line, "\r"):
            line = _s.substring(line, 0, len(line) - 1)
        if _s.starts_with(line, "@@ALEXTEST "):
            try:
                j := cc.json_parse(_s.substring(line, 11, len(line)))
                r := {"name": str(j["name"]), "line": 0, "status": str(j["status"]), "message": str(j["message"]) if j["message"] != null else "",
                      "duration": to_float(j["duration"])}
                for d in fr.discovered:
                    if d[0] == r["name"]:
                        r["line"] = d[1]
                append(fr.results, r)
            catch e:
                pass
            continue
        if _s.starts_with(line, "  [OK]") or _s.starts_with(line, "  [ÉCHEC]") or _s.starts_with(line, "  [ERREUR]") or _s.starts_with(line, "  [IGNORÉ]") or _s.starts_with(line, "      "):
            continue
        if _is_summary(line):
            continue
        append(out, line + "\n")
    o := _s.join("", out)
    while len(o) > 0 and (o[len(o) - 1] == '\n' or o[0] == '\n'):
        if o[len(o) - 1] == '\n':
            o = _s.substring(o, 0, len(o) - 1)
        else:
            o = _s.substring(o, 1, len(o))
    fr.output = o
    _conclude(fr)
    fr.done = true

func _conclude(fr):
    if len(fr.results) == 0:
        r := {"name": _os.stem(fr.file), "line": 0, "status": "passed", "message": "", "duration": fr.duration}
        if fr.exit_code != 0:
            r["status"] = "error"
            r["message"] = "code de sortie " + str(fr.exit_code) if fr.output == "" else fr.output
        elif _has_failures(fr.output):
            r["status"] = "failed"
            r["message"] = fr.output
        append(fr.results, r)
    elif fr.exit_code != 0:
        any_fail := false
        for r in fr.results:
            if r["status"] == "failed" or r["status"] == "error":
                any_fail = true
        if not any_fail:
            append(fr.results, {"name": _os.basename(fr.file), "line": 0, "status": "error",
                                "message": "code de sortie " + str(fr.exit_code) if fr.output == "" else fr.output, "duration": 0.0})

# Fait avancer les processus actifs (lecture non bloquante) ; vrai si quelque chose a été lu ou terminé.
func _pump(active):
    progress := false
    for fr in active:
        if fr.done or fr.proc == null:
            continue
        while true:
            chunk := fr.proc.read("stdout", 65536, 0)
            if chunk == null:
                break
            progress = true
            if chunk == "":
                _finish(fr)
                break
            append(fr.buf, chunk)
    return progress

func _cpu_jobs():
    n := 1
    try:
        n = _os.cpu_count()
    catch e:
        n = 1
    if n < 1:
        n = 1
    return n if n < 8 else 8

func _atoi(s):
    v := 0
    neg := false
    i := 0
    if i < len(s) and (s[i] == '-' or s[i] == '+'):
        neg = s[i] == '-'
        i += 1
    while i < len(s) and s[i] >= '0' and s[i] <= '9':
        v = v * 10 + (to_int(_s.ord(s[i])) - 48)
        i += 1
    return -v if neg else v

func _print_lines(text, prefix, limit):
    k := 0
    ls := _s.split(text, "\n")
    if len(ls) > 0 and ls[len(ls) - 1] == "":
        ls = ls[0:len(ls) - 1]
    for l in ls:
        if limit >= 0 and k >= limit:
            break
        k += 1
        print(prefix + l)

func run(args, exe):
    paths := []
    filter := ""
    json := false
    list := false
    jobs := _cpu_jobs()
    i := 0
    while i < len(args):
        a := args[i]
        if a == "--json":
            json = true
        elif a == "--list":
            list = true
        elif (a == "--filter" or a == "-k") and i + 1 < len(args):
            i += 1
            filter = args[i]
        elif a == "-j" and i + 1 < len(args):
            i += 1
            jobs = _atoi(args[i])
            jobs = jobs if jobs > 1 else 1
        elif _s.starts_with(a, "-j") and len(a) > 2:
            jobs = _atoi(_s.substring(a, 2, len(a)))
            jobs = jobs if jobs > 1 else 1
        elif a == "--help" or a == "-h":
            print("usage: alexc test [chemins...] [--filter texte] [--json] [--list] [-j N]")
            return 0
        else:
            append(paths, a)
        i += 1
    if len(paths) == 0:
        d := _os.cwd()
        root := d
        cur := d
        while true:
            if _os.exists(_os.join(cur, "alex.toml")):
                root = cur
                break
            parent := _os.dirname(cur)
            if parent == cur or parent == "":
                break
            cur = parent
        append(paths, root)
    files := find_test_files(paths)
    runs := []
    for f in files:
        fr := FileRun(f)
        fr.discovered = discover(f)["tests"]
        append(runs, fr)
    if list:
        for r in runs:
            if json:
                print(cc.json_dump({"event": "file", "file": r.file, "tests": [{"name": t[0], "line": t[1]} for t in r.discovered]}))
            else:
                print(relative(r.file))
                for t in r.discovered:
                    print("  " + t[0] + " (ligne " + str(t[1]) + ")")
        return 0
    _os.setenv("ALEX_TEST_REPORT", "1")
    t0 := _os.monotonic_time()
    started := 0
    active := []
    passed := 0
    failed := 0
    errors := 0
    skipped := 0
    k := 0
    while k < len(runs):
        # fenêtre de `jobs` processus en cours
        while started < len(runs) and started < k + jobs:
            _start(runs[started], exe, filter)
            append(active, runs[started])
            started += 1
        fr := runs[k]
        while not fr.done:
            if not _pump(active):
                _os.sleep(0.002)
        active = [x for x in active if not x.done]
        f_fail := 0
        for r in fr.results:
            st := r["status"]
            if st == "passed":
                passed += 1
            elif st == "failed":
                failed += 1
                f_fail += 1
            elif st == "error":
                errors += 1
                f_fail += 1
            else:
                skipped += 1
        if json:
            for r in fr.results:
                print(cc.json_dump({"event": "test", "file": fr.file, "name": r["name"], "line": r["line"], "status": r["status"],
                                    "message": r["message"], "duration": r["duration"]}))
            j := {"event": "file", "file": fr.file, "status": "failed" if f_fail > 0 else "passed", "duration": fr.duration, "exitCode": fr.exit_code}
            if fr.output != "":
                j["output"] = fr.output
            print(cc.json_dump(j))
        else:
            print(("✗ " if f_fail > 0 else "✓ ") + relative(fr.file) + "  (" + fmt_ms(fr.duration) + ")")
            for r in fr.results:
                st := r["status"]
                mark := "    ✓ " if st == "passed" else "    ○ " if st == "skipped" else "    ✗ "
                line := mark + r["name"]
                if st == "skipped":
                    line += " (ignoré" + ("" if r["message"] == "" else " : " + r["message"]) + ")"
                if st == "failed" or st == "error":
                    print(line + ("  [erreur]" if st == "error" else ""))
                    _print_lines(r["message"], "        ", -1)
                    if r["line"] > 0:
                        print("        à " + relative(fr.file) + ":" + str(r["line"]))
                    continue
                print(line)
            if f_fail > 0 and fr.output != "" and len(fr.results) > 1:
                print("    sortie :")
                _print_lines(fr.output, "      ", 30)
        cc.flush()
        k += 1
    total := _os.monotonic_time() - t0
    count := passed + failed + errors + skipped
    if json:
        print(cc.json_dump({"event": "summary", "passed": passed, "failed": failed, "errors": errors, "skipped": skipped,
                            "files": len(runs), "duration": total}))
    else:
        print("\n" + ("ÉCHEC" if failed + errors > 0 else "OK") + " : " + str(passed) + " réussi(s), " + str(failed) + " échec(s), " +
              str(errors) + " erreur(s), " + str(skipped) + " ignoré(s) — " + str(count) + " test(s) dans " + str(len(runs)) +
              " fichier(s) (" + fmt_ms(total) + ")")
    return 1 if failed + errors > 0 else 0
