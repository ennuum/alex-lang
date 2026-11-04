# ALEX STANDARD LIBRARY — diagnostics.trace
#
# Traçage d'exécution : intervalles (spans) imbriqués avec attributs et événements, journal des appels de
# fonctions tracées, et export au format Chrome Trace Event (ouvrable dans chrome://tracing ou Perfetto) ou en
# JSON simple.
#
#   use diagnostics.trace as tr
#   t := tr.Tracer("service")
#   with t.span("requête", {"url": "/api"}) as s:
#       s.event("cache manquant")
#       with t.span("base de données"):
#           interroger()
#       s.set("statut", 200)
#   f2 := t.wrap(calcul, "calcul")       # chaque appel de f2 devient un span (arguments en attributs)
#   f2(3)
#   print(t.summary())                   # durées cumulées par nom
#   t.save_chrome("/tmp/trace.json")     # pour chrome://tracing
#   print(tr.format_tree(t))             # arbre indenté des spans
#
# Les spans se terminent même si le bloc lève (with garantit __exit__) ; un span est marqué « error » s'il a
# été fermé par fail(). Erreurs : ArgumentError (fin d'un span déjà terminé), TypeError.

from core use len, type, to_int
from collections use append, pop
use string as _s
use os as _os
use io as _io
use json as _json

_ids := [0]

class Span:
    func init(tracer, name, parent, attributes):
        _ids[0] += 1
        self.id = _ids[0]
        self.tracer = tracer
        self.name = name
        self.parent = parent
        self.attributes = attributes
        if self.attributes == null:
            self.attributes = {}
        self.events = []
        self.start = _os.monotonic_time()
        self.end = null
        self.status = "ok"
        self.depth = 0
        if parent != null:
            self.depth = parent.depth + 1

    func set(key, value):
        self.attributes[key] = value
        return self

    func event(name, attributes=null):
        append(self.events, {"name": name, "time": _os.monotonic_time(), "attributes": attributes})
        return self

    func fail(message):
        self.status = "error"
        self.attributes["error"] = message
        return self

    func finish():
        if self.end != null:
            raise("ArgumentError", "Span.finish : span '" + self.name + "' déjà terminé")
        self.end = _os.monotonic_time()
        self.tracer._closed(self)
        return self

    func duration():
        if self.end == null:
            return _os.monotonic_time() - self.start
        return self.end - self.start

    func __enter__():
        return self

    func __exit__(a, b, c):
        if self.end == null:
            self.finish()

    func to_dict():
        p := null
        if self.parent != null:
            p = self.parent.id
        return {"id": self.id, "name": self.name, "parent": p, "start": self.start - self.tracer.origin,
                "duration": self.duration(), "attributes": self.attributes, "events": self.events, "status": self.status}

class Tracer:
    func init(name="trace", enabled=true):
        self.name = name
        self.enabled = enabled
        self.origin = _os.monotonic_time()
        self.spans = []           # terminés, dans l'ordre de fin
        self.stack = []
        self.max_spans = 100000

    func current():
        if len(self.stack) == 0:
            return null
        return self.stack[len(self.stack) - 1]

    func span(name, attributes=null):
        s := Span(self, name, self.current(), attributes)
        append(self.stack, s)
        return s

    func _closed(s):
        # retire s de la pile (normalement au sommet)
        i := len(self.stack) - 1
        while i >= 0:
            if self.stack[i].id == s.id:
                self.stack = self.stack[:i] + self.stack[i + 1:]
                break
            i -= 1
        if self.enabled and len(self.spans) < self.max_spans:
            append(self.spans, s)

    # Fonction enveloppée : chaque appel est un span (arguments dans « args »).
    func wrap(fn, name=null):
        if type(fn) != "function":
            raise("TypeError", "Tracer.wrap : fonction attendue")
        nm := name
        if nm == null:
            nm = "fonction"
        return (*args) => _traced_call(self, nm, fn, args)

    func run(name, fn):
        s := self.span(name)
        try:
            return fn()
        catch e:
            s.fail(e.type + " : " + e.message)
            raise(e.type, e.message)
        finally:
            if s.end == null:
                s.finish()

    func clear():
        self.spans = []
        self.stack = []

    # {nom: {"count", "total", "max"}}
    func summary():
        out := {}
        for s in self.spans:
            if not (s.name in out):
                out[s.name] = {"count": 0, "total": 0.0, "max": 0.0}
            d := out[s.name]
            d["count"] += 1
            d["total"] += s.duration()
            if s.duration() > d["max"]:
                d["max"] = s.duration()
        return out

    func to_json():
        return _json.stringify({"tracer": self.name, "spans": [s.to_dict() for s in self.spans]})

    # Format Chrome Trace Event (événements « X » complets, microsecondes).
    func to_chrome():
        evs := []
        for s in self.spans:
            append(evs, {"name": s.name, "cat": self.name, "ph": "X", "ts": to_int((s.start - self.origin) * 1000000),
                         "dur": to_int(s.duration() * 1000000), "pid": _os.pid(), "tid": 1, "args": s.attributes})
            for e in s.events:
                append(evs, {"name": e["name"], "cat": self.name, "ph": "i", "s": "t", "ts": to_int((e["time"] - self.origin) * 1000000),
                             "pid": _os.pid(), "tid": 1})
        return {"traceEvents": evs, "displayTimeUnit": "ms"}

    func save_chrome(path):
        _io.write_file(path, _json.stringify(self.to_chrome()))
        return path

func _traced_call(tracer, name, fn, args):
    s := tracer.span(name, {"args": str(args)})
    try:
        r := fn(*args)
        return r
    catch e:
        s.fail(e.type + " : " + e.message)
        raise(e.type, e.message)
    finally:
        if s.end == null:
            s.finish()

func _ms(x):
    return str(to_int(x * 100000 + 0.5) / 100.0) + " ms"

# Arbre indenté des spans terminés (dans l'ordre de début).
func format_tree(tracer):
    ss := tracer.spans[:]
    i := 1
    while i < len(ss):
        v := ss[i]
        j := i - 1
        while j >= 0 and ss[j].start > v.start:
            ss[j + 1] = ss[j]
            j -= 1
        ss[j + 1] = v
        i += 1
    lines := []
    for s in ss:
        mark := ""
        if s.status == "error":
            mark = "  [erreur : " + str(s.attributes["error"]) + "]"
        append(lines, _s.repeat("  ", s.depth) + s.name + " — " + _ms(s.duration()) + mark)
    return _s.join("\n", lines)

_default := [null]

func default_tracer():
    if _default[0] == null:
        _default[0] = Tracer("défaut")
    return _default[0]

func span(name, attributes=null):
    return default_tracer().span(name, attributes)
