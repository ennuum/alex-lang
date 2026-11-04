# Tests : diagnostics.stack_trace, performance_counter, cpu_stats, memory_profiler, trace, profiler,
# crash_report.
from core use len, type
from collections use append
use check as t
use os
use io
use string
use json
use diagnostics.stack_trace as st
use diagnostics.performance_counter as pc
use diagnostics.cpu_stats as cs
use diagnostics.memory_profiler as mp
use diagnostics.trace as tr
use diagnostics.profiler as pf
use diagnostics.crash_report as cr

# stack_trace
func profond(n):
    if n == 0:
        return st.current()
    return profond(n - 1)

pile := profond(3)
t.eq(pile.functions()[pile.depth() - 4:], ["profond", "profond", "profond", "profond"], "current")
t.check(string.ends_with(pile.top().file, "test_diagnostics2.al"), "fichier")
t.eq(pile.top().source(), "return st.current()", "ligne de source")

func qui():
    return st.caller()

func appelant():
    return qui()

t.eq(appelant(), "appelant", "caller")
func echoue():
    raise("ValueError", "mauvais")

err := null
try:
    echoue()
catch e:
    err = e
tt := st.from_error(err)
t.eq(tt.top().function, "echoue", "from_error top")
t.eq(tt.error_type, "ValueError", "from_error type")
t.check(string.contains(st.format_error(err), "raise(\"ValueError\", \"mauvais\")"), "format_error avec source")
f := st.parse_entry("/a/b.al:12, dans g")
t.check(f.file == "/a/b.al" and f.line == 12 and f.function == "g", "parse_entry")

# performance_counter
sw := pc.Stopwatch().start()
os.sleep(0.01)
l1 := sw.lap()
t.check(l1 >= 0.009, "lap")
sw.stop()
e1 := sw.elapsed()
os.sleep(0.005)
t.eq(sw.elapsed(), e1, "arrêté")
t.raises(() => sw.stop(), "ArgumentError", "stop arrêté")
pc.increment("req")
pc.increment("req", 2)
pc.record("lat", 0.5)
pc.record("lat", 1.5)
t.eq(pc.get("req").count, 3, "increment")
t.eq(pc.get("lat").mean(), 1.0, "mean")
t.eq(pc.get("lat").max, 1.5, "max")
with pc.timer("bloc"):
    os.sleep(0.005)
t.check(pc.get("bloc").total >= 0.004, "timer")
t.check(string.contains(pc.report(), "lat"), "report")
t.eq(pc.time_call((a, b) => a + b, [2, 3])[1], 5, "time_call")

# cpu_stats
pt := cs.process_times()
t.check(pt["total"] != null and pt["total"] >= 0, "process_times")
sm := cs.CpuSampler()
x := 0
i := 0
while i < 200000:
    x += i
    i += 1
u := sm.usage()
t.check(u["total"] != null and u["total"] >= 0 and u["total"] <= 100, "usage total")
t.eq(len(u["cpus"]), cs.cpu_count(), "usage par cœur")
t.eq(len(cs.load_average()), 3, "load_average")
t.check(cs.context_switches()["voluntary"] != null, "context_switches")
m := cs.measure(() => [k * k for k in 0..50000])
t.check(m["wall"] > 0 and len(m["result"]) == 50000, "measure")
t.check(len(cs.thread_times()) >= 1, "thread_times")

# memory_profiler
gardes := []
r := mp.profile(() => [append(gardes, [k]) for k in 0..2000])
t.check(r.retained_objects >= 2000, "objets retenus " + str(r.retained_objects))
r2 := mp.profile(() => len([[k] for k in 0..2000]))
t.check(r2.retained_objects < 100, "objets libérés " + str(r2.retained_objects))
lc := mp.leak_check(() => append(gardes, [1, 2]), 30)
t.check(lc["suspect"], "fuite détectée")
lc2 := mp.leak_check(() => len([1, 2, 3]), 30)
t.check(not lc2["suspect"], "pas de fuite")
prof := mp.MemoryProfiler()
prof.track("étape", () => [k for k in 0..100])
prof.sample("fin")
t.check(string.contains(prof.report(), "étape"), "report mémoire")
t.eq(len(prof.heaviest(1)), 1, "heaviest")

# trace
tc := tr.Tracer("test")
with tc.span("requête", {"url": "/x"}) as s:
    s.event("début")
    with tc.span("db"):
        os.sleep(0.002)
    s.set("statut", 200)
t.eq(len(tc.spans), 2, "spans")
t.eq(tc.spans[0].name, "db", "ordre de fin")
t.eq(tc.spans[0].parent.name, "requête", "parent")
t.eq(tc.spans[1].attributes["statut"], 200, "attribut")
w := tc.wrap((n) => n * 2, "double")
t.eq(w(4), 8, "wrap")
t.raises(() => tc.run("casse", () => raise("IoError", "x")), "IoError", "run relance")
t.eq(tc.spans[len(tc.spans) - 1].status, "error", "span en erreur")
t.eq(tc.summary()["double"]["count"], 1, "summary")
ch := tc.to_chrome()
t.eq(ch["traceEvents"][0]["ph"], "X", "chrome")
t.check(string.contains(tr.format_tree(tc), "  db"), "arbre")
t.check(json.parse(tc.to_json())["tracer"] == "test", "to_json")

# profiler (instrumentation)
p := pf.Profiler()
lent := p.wrap((n) => [k for k in 0..n], "lent")
ext := p.wrap((n) => len(lent(n)), "externe")
ext(20000)
ext(100)
t.eq(p.get("externe").calls, 2, "appels")
t.check(p.get("externe").self_time < p.get("externe").total, "temps propre < total")
t.check(string.contains(p.report(), "lent"), "report")
# profileur natif
rep := pf.profile_source("func carre(n) => n * n\nfunc boucle():\n    s := 0\n    for i in 0..20000:\n        s += carre(i)\n    return s\nprint(boucle())\n")
t.check(rep.function("carre") != null and rep.function("carre").calls == 20000, "profil natif : appels")
t.check(string.contains(rep.stdout, "2666466670000"), "sortie du programme")
t.check(string.contains(rep.format(5), "carre"), "format natif")
t.check(string.contains(rep.hottest_lines(3), ".al:"), "lignes chaudes")
t.raises(() => pf.profile_source("raise(\"ValueError\", \"x\")\n"), "ProfilerError", "programme en échec")

# crash_report
func plante():
    x := {"a": 1}
    return x["b"]

rep2 := null
try:
    plante()
catch e:
    rep2 = cr.CrashReport(e, {"version": "1.0"})
t.eq(rep2.error_type, "KeyError", "type")
t.check(string.contains(rep2.to_text(), ">> "), "extrait de source")
t.check(string.contains(rep2.to_text(), "version = 1.0"), "contexte")
d := json.parse(rep2.to_json())
t.eq(d["error"]["type"], "KeyError", "json")
dossier := "/tmp/alex_crash_" + str(os.pid())
chemin := rep2.save(dossier)
t.check(os.exists(chemin), "save")
t.eq(cr.load(chemin)["context"]["version"], "1.0", "load")
t.eq(len(cr.list_reports(dossier)), 1, "list_reports")
code := cr.guard(() => plante(), dossier)
t.eq(code, 1, "guard code")
t.eq(len(cr.list_reports(dossier)), 2, "guard enregistre")
t.eq(cr.guard(() => 1), 0, "guard ok")
for n in os.list_dir(dossier):
    os.remove(dossier + "/" + n)
os.rmdir(dossier)

t.summary("test_diagnostics2")
