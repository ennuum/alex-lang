# Tests : gc.gc_config, gc_heap, gc_roots, gc_stats, gc_errors.
from core use len, type
from collections use append
use check as t
use gc
use gc.gc_config as gcc
use gc.gc_heap as heap
use gc.gc_roots as roots
use gc.gc_stats as gs

func garbage(n):
    i := 0
    while i < n:
        x := [i, [i], {"k": i}]
        i += 1
    return n

# config
c0 := gcc.current()
t.check(c0.enabled, "activé par défaut")
before := gcc.GcConfig(true, 4096).apply()
t.eq(gcc.current().threshold >= 1, true, "seuil appliqué")
before.apply()
func inside():
    return gcc.current().enabled
t.eq(gcc.with_config(gcc.preset("off"), inside), false, "with_config")
t.check(gcc.current().enabled, "restauré")
t.eq(gcc.without_gc(inside), false, "without_gc")
t.raises(() => gcc.preset("turbo"), "GcConfigError", "préréglage inconnu")
t.raises(() => gcc.GcConfig(true, 0), "GcConfigError", "seuil invalide")
t.eq(len(gcc.presets()), 6, "presets")
t.check(gcc.GcConfig(true, 10) == gcc.GcConfig(true, 10), "égalité")
func boom():
    raise("ValueError", "x")
t.raises(() => gcc.with_config(gcc.preset("off"), boom), "ValueError", "with_config propage")
t.check(gcc.current().enabled, "restauré après erreur")

# heap
h := heap.info()
t.check(h.live > 0 and h.threshold > 0, "info")
garbage(3000)
r := heap.collect_now()
t.check(r["collections"] >= 1, "collect_now effective")
t.check(r["freed"] > 0, "objets libérés")
t.check(heap.pressure() >= 0, "pressure")
t.check(heap.info().until_next_collection() >= 0, "until_next_collection")
t.check(heap.collect_fully() >= 0, "collect_fully")
t.check(len(str(h)) > 0, "HeapInfo str")

# roots
hd := roots.pin([1, 2, 3])
t.eq(roots.get(hd), [1, 2, 3], "pin/get")
t.check(roots.is_pinned(hd), "is_pinned")
roots.unpin(hd)
t.raises(() => roots.get(hd), "GcRootError", "après unpin")
t.raises(() => roots.unpin(hd), "GcRootError", "double unpin")
n0 := roots.pinned_count()
rs := roots.RootSet("rendu")
rs.add("tex", {"w": 4})
rs.add("buf", [0])
t.eq(rs.get("tex")["w"], 4, "RootSet.get")
t.eq(roots.pinned_count(), n0 + 2, "épingles")
t.check(rs.remove("buf"), "remove")
rs.clear()
t.eq(roots.pinned_count(), n0, "clear")
t.eq(roots.keep_alive([1, 2], () => roots.pinned_count()), n0 + 2, "keep_alive")
t.eq(roots.pinned_count(), n0, "keep_alive relâche")
pinned := roots.pin(garbage)
heap.collect_now()
t.check(roots.get(pinned) == garbage, "épinglé survit à la collecte")
roots.unpin(pinned)

# stats
m := gs.measure(() => garbage(2000))
t.eq(m["result"], 2000, "measure résultat")
t.check(m["allocated"] >= 2000, "measure allocated")
mon := gs.GcMonitor("test")
garbage(500)
mon.sample()
garbage(500)
mon.sample()
t.eq(mon.count(), 3, "échantillons")
t.eq(len(mon.deltas()), 2, "deltas")
t.check(mon.total()["allocated"] >= 1000, "total")
t.check(len(mon.report()) > 20, "report")
t.raises(() => gs.measure(5), "TypeError", "measure(non fonction)")

t.summary("gc2")
