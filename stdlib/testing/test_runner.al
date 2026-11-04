# ALEX STANDARD LIBRARY — testing.test_runner
#
# TestRunner : exécute une TestSuite (ou une instance de TestCase) — fixtures, chronométrage, classement
# réussi / échec / erreur / ignoré, arrêt au premier échec si demandé, délai par test signalé — et rend un
# TestReport (testing.test_report).
#
#   use testing.test_runner as trun
#   r := trun.TestRunner(true)              # verbose : une ligne par test
#   rapport := r.run(suite)
#   print(rapport.summary_line("unitaires"))
#   trun.main(suite, "unitaires")           # exécute, affiche, écrit $ALEX_JUNIT si défini, rend 0 ou 1
#   r2 := trun.TestRunner(false, true)      # fail_fast
#   r2.slow_threshold = 0.5                 # avertit des tests de plus de 0,5 s
#
# Erreurs : aucune ne s'échappe (les erreurs des tests sont dans le rapport).

from core use len, type
from collections use append
use string as _s
use os as _os
use _native_reflect as _r
use testing.test_report as _rep
use testing.test_suite as _ts
use testing.testing_errors as _e

class TestRunner:
    func init(verbose=false, fail_fast=false, pattern=null):
        self.verbose = verbose
        self.fail_fast = fail_fast
        self.pattern = pattern
        self.slow_threshold = null
        self.slow = []
        self.on_result = null
        self._case_ready = {}

    func _say(text):
        if self.verbose:
            print(text)

    func _invoke(e):
        if e.case == null:
            e.fn()
            return
        e.case.set_up()
        failure := null
        try:
            m := _r.method(e.case, e.method)
            m()
        catch err:
            failure = err
        try:
            e.case.tear_down()
        catch err2:
            if failure == null:
                failure = err2
        if failure != null:
            raise(failure)

    func _prepare_case(e, report):
        if e.case == null:
            return true
        key := e.suite
        if key in self._case_ready:
            return self._case_ready[key]
        ok := true
        try:
            e.case.set_up_class()
        catch err:
            ok = false
            report.add(_rep.TestResult(e.suite + ".set_up_class", "error", 0.0, err.type + " : " + err.message, _e.SETUP, null, e.suite))
        self._case_ready[key] = ok
        return ok

    func run_entry(e, report):
        t0 := _os.monotonic_time()
        status := "passed"
        message := null
        etype := null
        trace := null
        try:
            self._invoke(e)
        catch err:
            etype = err.type
            message = err.message
            try:
                trace = err.trace
            catch x:
                trace = null
            if _e.is_skip(err.type):
                status = "skipped"
            elif _e.is_failure(err.type):
                status = "failed"
            else:
                status = "error"
                message = err.type + " : " + err.message
        d := _os.monotonic_time() - t0
        res := report.add(_rep.TestResult(e.name, status, d, message, etype, trace, e.suite))
        if self.slow_threshold != null and d > self.slow_threshold:
            append(self.slow, [e.name, d])
        self._say(str(res))
        if self.on_result != null:
            self.on_result(res)
        return res

    func run(suite):
        report := _rep.TestReport(suite.name)
        t0 := _os.monotonic_time()
        s := suite
        if self.pattern != null:
            s = suite.filter(self.pattern)
        cases := []
        for e in s.entries:
            if not self._prepare_case(e, report):
                report.add(_rep.TestResult(e.name, "error", 0.0, "set_up_class en échec", _e.SETUP, null, e.suite))
                continue
            if e.case != null:
                known := false
                for c in cases:
                    if c[0] == e.suite:
                        known = true
                if not known:
                    append(cases, [e.suite, e.case])
            r := self.run_entry(e, report)
            if self.fail_fast and (r.status == "failed" or r.status == "error"):
                break
        for c in cases:
            try:
                c[1].tear_down_class()
            catch err:
                report.add(_rep.TestResult(c[0] + ".tear_down_class", "error", 0.0, err.type + " : " + err.message, _e.SETUP, null, c[0]))
        report.duration = _os.monotonic_time() - t0
        if self.verbose:
            print(report.to_text(false))
        return report

    func run_case(case, only=null):
        s := _ts.TestSuite(_r.display_name(_r.type_name(case)))
        s.add_case(case)
        if only != null:
            s = s.filter(only)
        return self.run(s)

    func run_functions(name, pairs):
        return self.run(_ts.from_functions(name, pairs))

# Exécute, affiche le rapport et la ligne de synthèse ; JUnit écrit dans $ALEX_JUNIT s'il est défini.
# Renvoie 0 (tout est passé) ou 1.
func main(suite, label=null, verbose=true):
    r := TestRunner(verbose).run(suite)
    junit := _os.getenv("ALEX_JUNIT")
    if junit != null and junit != "":
        r.save_junit(junit, label)
    for f in r.failures():
        print("ÉCHEC " + f.name + " : " + str(f.message))
    print(r.summary_line(label))
    if r.ok():
        return 0
    return 1
