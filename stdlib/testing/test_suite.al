# ALEX STANDARD LIBRARY — testing.test_suite
#
# TestSuite : un ensemble NOMMÉ de tests — fonctions (nom, fn), instances de TestCase, et sous-suites — avec
# étiquettes et filtres, à confier à un TestRunner.
#
#   use testing.test_suite as ts
#   s := ts.TestSuite("unitaires")
#   s.add("addition", () => assertions.equal(1 + 1, 2))
#   s.add("réseau", test_reseau, ["lent", "réseau"])
#   s.add_case(PileTest())
#   s.add_suite(autre_suite)
#   rapide := s.filter(null, ["lent"])          # sans les tests étiquetés « lent »
#   print(s.size(), s.names())
#
# Erreurs : ArgumentError (nom en double), TypeError.

from core use len, type
from collections use append
use string as _s
use _native_reflect as _r

class TestEntry:
    func init(name, fn, tags, case=null, method=null, suite=""):
        self.name = name
        self.fn = fn
        self.tags = tags
        self.case = case
        self.method = method
        self.suite = suite

    func has_tag(t):
        for x in self.tags:
            if x == t:
                return true
        return false

class TestSuite:
    func init(name="suite"):
        self.name = name
        self.entries = []
        self._names = {}

    func _push(e):
        full := e.suite + "::" + e.name
        if full in self._names:
            raise("ArgumentError", "TestSuite : test '" + e.name + "' en double")
        self._names[full] = true
        append(self.entries, e)

    func add(name, fn, tags=null):
        if type(fn) != "function":
            raise("TypeError", "TestSuite.add : fonction attendue pour '" + str(name) + "'")
        tg := tags
        if tg == null:
            tg = []
        self._push(TestEntry(name, fn, tg, null, null, self.name))
        return self

    # Ajoute les méthodes test_* d'une instance de TestCase.
    func add_case(case):
        cname := _r.display_name(_r.type_name(case))
        tagmap := {}
        if _r.method(case, "tags") != null:
            tagmap = case.tags()
        for m in _test_methods(case):
            tg := []
            if m in tagmap:
                tg = tagmap[m]
            self._push(TestEntry(m, null, tg, case, m, cname))
        return self

    func add_suite(other):
        for e in other.entries:
            self._push(e)
        return self

    func size():
        return len(self.entries)

    func names():
        return [e.name for e in self.entries]

    # Nouvelle suite : noms contenant pattern (null : tous), sans les étiquettes exclude, avec au moins une
    # étiquette de include (null : pas de condition).
    func filter(pattern=null, exclude=null, include=null):
        out := TestSuite(self.name)
        for e in self.entries:
            if pattern != null and not _s.contains(e.name, pattern):
                continue
            skip := false
            if exclude != null:
                for t in exclude:
                    if e.has_tag(t):
                        skip = true
            if skip:
                continue
            if include != null:
                ok := false
                for t in include:
                    if e.has_tag(t):
                        ok = true
                if not ok:
                    continue
            out._push(e)
        return out

func _test_methods(case):
    out := []
    tn := _r.type_name(case)
    seen := {}
    cur := tn
    guard := 0
    while cur != null and guard < 64:
        for m in _r.methods(cur):
            if _s.starts_with(m, "test_") and not (m in seen):
                seen[m] = true
                append(out, m)
        info := _r.class_info(cur)
        if info == null:
            break
        cur = info["base"]
        guard += 1
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j] > v:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

func suite(name="suite"):
    return TestSuite(name)

func from_functions(name, pairs):
    s := TestSuite(name)
    for p in pairs:
        s.add(p[0], p[1])
    return s

func test_methods(case):
    return _test_methods(case)
