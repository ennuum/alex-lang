# ALEX STANDARD LIBRARY — memory.allocator
#
# Interface commune des allocateurs (stratégies interchangeables, comme std::pmr ou les allocateurs de Zig)
# et allocateurs de base. Une allocation rend un objet Allocation dont .view est une MemoryView SÛRE
# (bornes vérifiées, invalide après libération).
#
#   Allocator (interface)  allocate(size, align) -> Allocation ; deallocate(a) ; owns(a) ; stats()
#   SystemAllocator        un Buffer par allocation (libéré par deallocate, ou par le GC)
#   TrackingAllocator      enveloppe : compte octets / pics / allocations vivantes, rapport de fuites
#   LimitedAllocator       enveloppe : refuse au-delà d'un quota (MemoryError)
#   FallbackAllocator      essaie un allocateur, puis un autre en cas d'échec
#
#   use memory.allocator as alc
#   use memory.arena as arena
#   a := alc.TrackingAllocator(alc.SystemAllocator())
#   x := a.allocate(64)
#   x.view.write("u32", 7)
#   print(a.stats()["live_allocations"])        # 1
#   a.deallocate(x)
#   print(a.leaks())                             # []
#   rapide := alc.FallbackAllocator(arena.Arena(4096), alc.SystemAllocator())
#
# Erreurs : MemoryError (quota, double libération), AllocatorError (allocation étrangère), AlignmentError.

from core use len, type
from collections use append
use memory.buffer as _buf
use memory.memory_errors as _e

_next := [0]

func _new_id():
    _next[0] += 1
    return _next[0]

interface Allocator:
    func allocate(size, align)
    func deallocate(allocation)
    func owns(allocation)
    func stats()

# Une allocation : une vue sûre + ses métadonnées.
class Allocation:
    func init(view, size, align, allocator_id, holder=null, tag=null):
        self.view = view
        self.size = size
        self.align = align
        self.allocator_id = allocator_id
        self.id = _new_id()
        self.freed = false
        self.tag = tag
        self._holder = holder

    func address():
        return self.view.address()

    func valid():
        return not self.freed and self.view.valid()

    func __str__():
        state := "vivante"
        if self.freed:
            state = "libérée"
        return "Allocation(#" + str(self.id) + ", " + str(self.size) + " o, " + state + ")"

class SystemAllocator implements Allocator:
    func init():
        self.id = _new_id()
        self._count = 0
        self._bytes = 0
        self._total = 0

    func allocate(size, align=16):
        _e.need_size("SystemAllocator.allocate", size)
        _e.need_align("SystemAllocator.allocate", align)
        b := _buf.Buffer(size, true, align)
        self._count += 1
        self._bytes += size
        self._total += 1
        return Allocation(b.view(0, size), size, align, self.id, b)

    func deallocate(allocation):
        if not self.owns(allocation):
            _e.foreign("SystemAllocator.deallocate")
        if allocation.freed:
            _e.double_free("SystemAllocator.deallocate")
        allocation.freed = true
        allocation._holder.free()
        self._count -= 1
        self._bytes -= allocation.size

    func owns(allocation):
        return isinstance(allocation, Allocation) and allocation.allocator_id == self.id

    func stats():
        return {"live_allocations": self._count, "live_bytes": self._bytes, "total_allocations": self._total}

class TrackingAllocator implements Allocator:
    func init(inner, name="tracking"):
        self.inner = inner
        self.name = name
        self._live = {}       # id -> Allocation
        self._bytes = 0
        self._peak = 0
        self._total = 0
        self._total_bytes = 0
        self._frees = 0

    func allocate(size, align=null):
        a := self.inner.allocate(size, align)
        self._live[a.id] = a
        self._bytes += size
        self._total += 1
        self._total_bytes += size
        if self._bytes > self._peak:
            self._peak = self._bytes
        return a

    func deallocate(allocation):
        if not (allocation.id in self._live):
            if allocation.freed:
                _e.double_free("TrackingAllocator.deallocate")
            _e.foreign("TrackingAllocator.deallocate")
        self.inner.deallocate(allocation)
        del self._live[allocation.id]
        self._bytes -= allocation.size
        self._frees += 1

    func owns(allocation):
        return isinstance(allocation, Allocation) and allocation.id in self._live

    func stats():
        return {"name": self.name, "live_allocations": len(self._live), "live_bytes": self._bytes,
                "peak_bytes": self._peak, "total_allocations": self._total, "total_bytes": self._total_bytes,
                "total_frees": self._frees}

    # Allocations encore vivantes : [{"id", "size", "tag"}].
    func leaks():
        out := []
        for k in self._live:
            a := self._live[k]
            append(out, {"id": a.id, "size": a.size, "tag": a.tag})
        return out

    func leak_report():
        l := self.leaks()
        if len(l) == 0:
            return self.name + " : aucune fuite"
        total := 0
        for x in l:
            total += x["size"]
        return self.name + " : " + str(len(l)) + " allocation(s) vivante(s), " + str(total) + " octets"

    # Libère tout ce qui reste ; renvoie le nombre d'allocations libérées.
    func release_all():
        ids := [k for k in self._live]
        for k in ids:
            self.deallocate(self._live[k])
        return len(ids)

class LimitedAllocator implements Allocator:
    func init(inner, max_bytes):
        _e.need_size("LimitedAllocator", max_bytes)
        self.inner = inner
        self.max_bytes = max_bytes
        self._used = 0
        self._sizes = {}

    func allocate(size, align=null):
        if self._used + size > self.max_bytes:
            _e.out_of_memory("LimitedAllocator.allocate", size, self.max_bytes - self._used)
        a := self.inner.allocate(size, align)
        self._used += size
        self._sizes[a.id] = size
        return a

    func deallocate(allocation):
        if not (allocation.id in self._sizes):
            _e.foreign("LimitedAllocator.deallocate")
        self.inner.deallocate(allocation)
        self._used -= self._sizes[allocation.id]
        del self._sizes[allocation.id]

    func owns(allocation):
        return isinstance(allocation, Allocation) and allocation.id in self._sizes

    func remaining():
        return self.max_bytes - self._used

    func stats():
        s := self.inner.stats()
        s["limit"] = self.max_bytes
        s["used"] = self._used
        return s

class FallbackAllocator implements Allocator:
    func init(primary, fallback):
        self.primary = primary
        self.fallback = fallback
        self.fallbacks = 0

    func allocate(size, align=null):
        try:
            return self.primary.allocate(size, align)
        catch e:
            if e.type != _e.MEMORY and e.type != _e.POOL_EXHAUSTED and e.type != _e.ALIGNMENT and e.type != "ArgumentError":
                raise(e)
        self.fallbacks += 1
        return self.fallback.allocate(size, align)

    func deallocate(allocation):
        if self.primary.owns(allocation):
            self.primary.deallocate(allocation)
        elif self.fallback.owns(allocation):
            self.fallback.deallocate(allocation)
        else:
            _e.foreign("FallbackAllocator.deallocate")

    func owns(allocation):
        return self.primary.owns(allocation) or self.fallback.owns(allocation)

    func stats():
        return {"primary": self.primary.stats(), "fallback": self.fallback.stats(), "fallbacks": self.fallbacks}

_default := [null]

# Allocateur par défaut du programme (SystemAllocator au départ).
func default():
    if _default[0] == null:
        _default[0] = SystemAllocator()
    return _default[0]

# Change l'allocateur par défaut ; renvoie l'ancien.
func set_default(allocator):
    if not isinstance(allocator, Allocator):
        raise("TypeError", "allocator.set_default : Allocator attendu")
    old := default()
    _default[0] = allocator
    return old

func allocate(size, align=null):
    return default().allocate(size, align)

func deallocate(allocation):
    default().deallocate(allocation)

# body(allocation) ; libération garantie à la sortie (même sur erreur).
func with_allocation(size, body, allocator=null):
    a := allocator
    if a == null:
        a = default()
    x := a.allocate(size)
    try:
        return body(x)
    finally:
        if not x.freed:
            a.deallocate(x)
