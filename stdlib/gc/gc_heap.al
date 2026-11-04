# ALEX STANDARD LIBRARY — gc.gc_heap
#
# Le tas géré par le ramasse-miettes, vu de l'intérieur : objets vivants, pic, objets créés et libérés,
# seuil et marge avant la prochaine collecte ; collecte avec compte rendu.
#
#   use gc.gc_heap as heap
#   h := heap.info()
#   print(h.live, h.until_next_collection())      # objets vivants, marge
#   r := heap.collect_now()                        # collecte effective + bilan
#   print(r["freed"], r["live_after"])
#   print(heap.pressure())                         # live / threshold (>= 1 : collecte imminente)
#
# Les nombres sont des OBJETS ALEX (listes, dicts, chaînes, instances...), pas des octets : la mémoire
# native (module memory) n'est pas comptée ici.
# Erreurs : aucune.

from core use type
use _native_gc as _g

class HeapInfo:
    func init(s):
        self.live = s["live"]
        self.peak = s["peak"]
        self.allocated = s["allocated"]
        self.freed = s["freed"]
        self.collections = s["collections"]
        self.threshold = s["threshold"]
        self.enabled = s["enabled"]

    # Objets à créer avant que la VM ne déclenche une collecte (0 : imminente).
    func until_next_collection():
        n := self.threshold - self.live
        if n < 0:
            return 0
        return n

    func pressure():
        return self.live / self.threshold

    func survival_rate():
        if self.allocated == 0:
            return 0.0
        return (self.allocated - self.freed) / self.allocated

    func to_dict():
        return {"live": self.live, "peak": self.peak, "allocated": self.allocated, "freed": self.freed,
                "collections": self.collections, "threshold": self.threshold, "enabled": self.enabled}

    func __str__():
        return "HeapInfo(vivants " + str(self.live) + ", pic " + str(self.peak) + ", collectes " + str(self.collections) + ", seuil " + str(self.threshold) + ")"

func info():
    return HeapInfo(_g.stats())

func live_objects():
    return _g.stats()["live"]

func peak_objects():
    return _g.stats()["peak"]

func pressure():
    return info().pressure()

func _sync():
    # Une instruction après collect() : la collecte demandée a lieu entre les deux.
    return null

# Collecte EFFECTIVE (pas seulement demandée) et bilan {"freed", "live_before", "live_after", "collections"}.
func collect_now():
    before := _g.stats()
    _g.collect()
    _sync()
    after := _g.stats()
    return {"freed": after["freed"] - before["freed"], "live_before": before["live"], "live_after": after["live"],
            "collections": after["collections"] - before["collections"]}

# Collecte jusqu'à stabilité (aucun objet libéré) ou max_rounds ; renvoie le total libéré.
func collect_fully(max_rounds=4):
    total := 0
    i := 0
    while i < max_rounds:
        r := collect_now()
        total += r["freed"]
        if r["freed"] == 0:
            break
        i += 1
    return total

# Collecte si la pression dépasse ratio ; renvoie true si une collecte a eu lieu.
func collect_if_pressure(ratio=0.8):
    if pressure() >= ratio:
        collect_now()
        return true
    return false
