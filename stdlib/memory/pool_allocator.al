# ALEX STANDARD LIBRARY — memory.pool_allocator
#
# Pools d'emplacements de taille fixe :
#   PoolAllocator(block_size, capacity)   emplacements d'octets dans UN Buffer ; alloc/free en O(1) (liste
#                                         libre) ; un emplacement rendu invalide ses vues (StaleViewError) ;
#                                         double libération et allocation étrangère détectées.
#   ObjectPool(factory, reset, max_size)  réutilisation d'OBJETS ALEX coûteux à créer (connexions, tampons) :
#                                         acquire / release, réinitialisés par reset(obj).
#
#   use memory.pool_allocator as pa
#   p := pa.PoolAllocator(64, 128)                # 128 emplacements de 64 octets
#   a := p.allocate()                             # Allocation (taille fixe)
#   a.view.write("u64", 42)
#   p.deallocate(a)
#   a.view.read("u64")                            # StaleViewError
#   g := pa.PoolAllocator(32, 4, true)            # extensible : un nouveau bloc de 4 quand c'est plein
#   op := pa.ObjectPool(() => Connexion(), (c) => c.vider(), 10)
#   c := op.acquire()
#   op.release(c)
#
# Erreurs : PoolExhaustedError (pool plein non extensible), MemoryError (double libération),
#           AllocatorError (allocation étrangère), ArgumentError.

from core use len, type
from collections use append, pop
from memory.buffer use Buffer
use memory.memory_view as _mv
use memory.allocator as _alc
from memory.allocator use Allocator, Allocation
use memory.memory_errors as _e
use memory.aligned_memory as _am

class _SlotOwner:
    func init():
        self._epoch = 0

class PoolAllocator implements Allocator:
    func init(block_size, capacity, growable=false, align=8):
        _e.need_size("PoolAllocator", block_size)
        _e.need_size("PoolAllocator", capacity)
        _e.need_align("PoolAllocator", align)
        self.id = _alc._new_id()
        self.block_size = block_size
        self.stride = _am.align_up(block_size, align)
        self.align = align
        self.growable = growable
        self._per_chunk = capacity
        self._chunks = []
        self._owners = []      # une époque par emplacement
        self._free = []        # numéros d'emplacements libres (pile)
        self._used = {}        # numéro -> id d'allocation
        self._peak = 0
        self._grow()

    func _grow():
        c := len(self._chunks)
        append(self._chunks, Buffer(self.stride * self._per_chunk, true, 16))
        base := c * self._per_chunk
        i := self._per_chunk - 1
        while i >= 0:
            append(self._owners, _SlotOwner())
            i -= 1
        i = self._per_chunk - 1
        while i >= 0:
            append(self._free, base + i)
            i -= 1

    func capacity():
        return len(self._chunks) * self._per_chunk

    func available():
        return len(self._free)

    func in_use():
        return len(self._used)

    # Allocation d'un emplacement (size, si fourni, doit tenir dans block_size).
    func allocate(size=null, align=null):
        if size != null and size > self.block_size:
            raise("ArgumentError", "PoolAllocator.allocate : " + str(size) + " octets > taille d'emplacement " + str(self.block_size))
        if align != null and align > self.align:
            raise(_e.ALIGNMENT, "PoolAllocator.allocate : alignement " + str(align) + " > " + str(self.align))
        if len(self._free) == 0:
            if not self.growable:
                raise(_e.POOL_EXHAUSTED, "PoolAllocator : pool plein (" + str(self.capacity()) + " emplacements)")
            self._grow()
        slot := pop(self._free)
        chunk := self._chunks[slot // self._per_chunk]
        off := (slot % self._per_chunk) * self.stride
        owner := self._owners[slot]
        chunk.fill(0, off, self.stride)
        v := _mv.MemoryView(chunk._id, off, self.block_size, false, owner, chunk)
        a := Allocation(v, self.block_size, self.align, self.id)
        a.slot = slot
        self._used[slot] = a.id
        if len(self._used) > self._peak:
            self._peak = len(self._used)
        return a

    func deallocate(allocation):
        if not isinstance(allocation, Allocation) or allocation.allocator_id != self.id:
            _e.foreign("PoolAllocator.deallocate")
        slot := allocation.slot
        if not (slot in self._used) or self._used[slot] != allocation.id:
            _e.double_free("PoolAllocator.deallocate")
        del self._used[slot]
        self._owners[slot]._epoch += 1
        allocation.freed = true
        append(self._free, slot)

    func owns(allocation):
        return isinstance(allocation, Allocation) and allocation.allocator_id == self.id and not allocation.freed

    # Rend tous les emplacements (toutes les vues deviennent invalides).
    func reset():
        for slot in [k for k in self._used]:
            self._owners[slot]._epoch += 1
        self._used = {}
        self._free = []
        i := self.capacity() - 1
        while i >= 0:
            append(self._free, i)
            i -= 1

    func free():
        self.reset()
        for c in self._chunks:
            c.free()
        self._chunks = []
        self._free = []

    func stats():
        return {"block_size": self.block_size, "stride": self.stride, "capacity": self.capacity(),
                "in_use": len(self._used), "available": len(self._free), "peak": self._peak,
                "chunks": len(self._chunks), "bytes": self.capacity() * self.stride}

class ObjectPool:
    func init(factory, reset=null, max_size=null, prefill=0):
        if type(factory) != "function":
            raise("TypeError", "ObjectPool : factory doit être une fonction")
        self._factory = factory
        self._reset = reset
        self.max_size = max_size
        self._idle = []
        self._out = 0
        self.created = 0
        self.reused = 0
        i := 0
        while i < prefill:
            append(self._idle, self._make())
            i += 1

    func _make():
        self.created += 1
        return factory_call(self._factory)

    func acquire():
        if len(self._idle) > 0:
            self.reused += 1
            self._out += 1
            return pop(self._idle)
        if self.max_size != null and self._out >= self.max_size:
            raise(_e.POOL_EXHAUSTED, "ObjectPool : " + str(self.max_size) + " objets déjà sortis")
        self._out += 1
        return self._make()

    func release(obj):
        if self._out <= 0:
            raise(_e.ALLOCATOR, "ObjectPool.release : aucun objet sorti")
        self._out -= 1
        if self._reset != null:
            self._reset(obj)
        append(self._idle, obj)

    # body(obj) ; obj rendu au pool à la sortie, même sur erreur.
    func with_object(body):
        obj := self.acquire()
        try:
            return body(obj)
        finally:
            self.release(obj)

    func idle():
        return len(self._idle)

    func in_use():
        return self._out

    func clear():
        self._idle = []

    func stats():
        return {"idle": len(self._idle), "in_use": self._out, "created": self.created, "reused": self.reused,
                "max_size": self.max_size}

func factory_call(f):
    return f()
