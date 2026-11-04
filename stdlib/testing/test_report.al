# ALEX STANDARD LIBRARY — testing.test_report
#
# Résultats d'une exécution de tests et leurs rapports : texte lisible, JUnit XML (Jenkins, GitLab, GitHub
# Actions...), JSON, et la ligne de synthèse « nom : N OK, M échecs » lue par tests/run_checked.sh.
#
#   use testing.test_report as tr
#   rep := runner.run(suite)                  # TestReport
#   print(rep.summary_line("unitaires"))      # « unitaires : 12 OK, 1 échecs »
#   print(rep.to_text())
#   rep.save_junit("rapport.xml", "unitaires")
#   print(rep.ok(), rep.counts())
#
# États d'un résultat : passed, failed (AssertionError), error (autre exception), skipped (SkipTest).

from core use len, type, to_int
from collections use append
use string as _s
use json as _json
use xml as _xml
use io as _io

class TestResult:
    func init(name, status, duration=0.0, message=null, error_type=null, trace=null, suite=""):
        self.name = name
        self.status = status
        self.duration = duration
        self.message = message
        self.error_type = error_type
        self.trace = trace
        self.suite = suite

    func passed():
        return self.status == "passed"

    func to_dict():
        return {"name": self.name, "suite": self.suite, "status": self.status, "duration": self.duration,
                "message": self.message, "error_type": self.error_type}

    func __str__():
        mark := {"passed": "[OK]    ", "failed": "[ÉCHEC] ", "error": "[ERREUR]", "skipped": "[IGNORÉ]"}
        out := mark[self.status] + " " + self.name
        if self.message != null and self.status != "passed":
            out += " — " + str(self.message)
        return out

class TestReport:
    func init(name="tests"):
        self.name = name
        self.results = []
        self.duration = 0.0

    func add(result):
        append(self.results, result)
        return result

    func count(status):
        n := 0
        for r in self.results:
            if r.status == status:
                n += 1
        return n

    func counts():
        return {"passed": self.count("passed"), "failed": self.count("failed"), "errors": self.count("error"),
                "skipped": self.count("skipped"), "total": len(self.results)}

    func ok():
        return self.count("failed") == 0 and self.count("error") == 0

    func failures():
        return [r for r in self.results if r.status == "failed" or r.status == "error"]

    # Ligne au format attendu par tests/run_checked.sh.
    func summary_line(label=null):
        l := label
        if l == null:
            l = self.name
        return l + " : " + str(self.count("passed")) + " OK, " + str(self.count("failed") + self.count("error")) + " échecs"

    func slowest(n=5):
        out := self.results[:]
        i := 1
        while i < len(out):
            v := out[i]
            j := i - 1
            while j >= 0 and out[j].duration < v.duration:
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = v
            i += 1
        return out[:n]

    func to_text(verbose=true):
        lines := []
        if verbose:
            for r in self.results:
                append(lines, str(r))
        c := self.counts()
        append(lines, "")
        append(lines, str(c["total"]) + " test(s) : " + str(c["passed"]) + " réussi(s), " + str(c["failed"]) + " échec(s), " + str(c["errors"]) + " erreur(s), " + str(c["skipped"]) + " ignoré(s) en " + str(_r3(self.duration)) + " s")
        return _s.join("\n", lines)

    func to_dict():
        return {"name": self.name, "duration": self.duration, "counts": self.counts(), "results": [r.to_dict() for r in self.results]}

    func to_json():
        return _json.stringify(self.to_dict(), 2)

    # JUnit XML (une suite par nom de suite des résultats).
    func to_junit(name=null):
        n := name
        if n == null:
            n = self.name
        suites := {}
        order := []
        for r in self.results:
            sname := r.suite
            if sname == "":
                sname = n
            if not (sname in suites):
                suites[sname] = []
                append(order, sname)
            append(suites[sname], r)
        children := []
        for sname in order:
            rs := suites[sname]
            cases := []
            fails := 0
            errs := 0
            skips := 0
            total_time := 0.0
            for r in rs:
                total_time += r.duration
                sub := []
                if r.status == "failed":
                    fails += 1
                    append(sub, _xml.element("failure", {"message": str(r.message), "type": str(r.error_type)}, [_trace_text(r)]))
                elif r.status == "error":
                    errs += 1
                    append(sub, _xml.element("error", {"message": str(r.message), "type": str(r.error_type)}, [_trace_text(r)]))
                elif r.status == "skipped":
                    skips += 1
                    append(sub, _xml.element("skipped", {"message": str(r.message)}))
                append(cases, _xml.element("testcase", {"name": r.name, "classname": sname, "time": str(_r3(r.duration))}, sub))
            append(children, _xml.element("testsuite", {"name": sname, "tests": str(len(rs)), "failures": str(fails),
                   "errors": str(errs), "skipped": str(skips), "time": str(_r3(total_time))}, cases))
        root := _xml.element("testsuites", {"name": n, "tests": str(len(self.results)), "time": str(_r3(self.duration))}, children)
        return _xml.pretty(root, 2, true)

    func save_junit(path, name=null):
        _io.write_file(path, self.to_junit(name) + "\n")

    func save_json(path):
        _io.write_file(path, self.to_json() + "\n")

    func merge(other):
        for r in other.results:
            append(self.results, r)
        self.duration += other.duration
        return self

func _trace_text(r):
    if type(r.trace) == "list":
        return _s.join("\n", [str(x) for x in r.trace])
    if r.message == null:
        return ""
    return str(r.message)

func _r3(x):
    return to_int(x * 1000 + 0.5) / 1000.0
