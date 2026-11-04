# ALEX STANDARD LIBRARY — memory.arena
#
# Arène EXTENSIBLE à points de restauration (complète memory.buffer.Arena, qui a une capacité fixe).
# Allocation « bump » en O(1) dans des tronçons (chunks) ; quand un tronçon est plein, un nouveau est créé
# (taille doublée, plafonnée). Rien ne se libère individuellement : on libère TOUT d'un coup (reset/free),
# ou on revient à un point de restauration (mark / rollback) — idéal pour une requête, une image, un parse.
# Les vues rendues deviennent invalides (StaleViewError) dès que leur espace est récupéré.
#
#   use memory.arena as arena
#   a := arena.Arena(1024)
#   v := a.alloc(16, 8)                        # MemoryView de 16 octets alignée sur 8
#   s := a.alloc_str("bonjour")                # copie dans l'arène (avec NUL)
#   m := a.mark()
#   tmp := a.alloc(500)
#   a.rollback(m)                              # tmp invalide, v et s restent valides
#   a.reset()                                  # tout invalide, mémoire réutilisée
#   arena.scoped(4096, traiter)                # arène libérée à la sortie, même sur erreur
#
# Arena implémente memory.allocator.Allocator (deallocate ne fait rien : la mémoire revient au reset).
# Erreurs : MemoryError (arène libérée, max_bytes dépassé), StaleViewError, AlignmentError, ArgumentError.

from core use len, type
from collections use append, pop
use _native_memory as _m
from memory.buffer use Buffer
use memory.memory_view as _mv
use memory.allocator as _alc
from memory.allocator use Allocator, Allocation
use memory.memory_errors as _e

# Époque d'un segment d'allocations : chaque mark() ouvre un segment ; récupérer son espace (rollback, reset)
# incrémente son époque, ce qui invalide toutes les vues émises dans ce segment et seulement elles.
class _Segment:
    func init(token=0):
        self._epoch = 0
        self.token = token

class _Chunk:
    func init(size):
        self.buf = Buffer(size, true, 16)
        self.size = size
        self.top = 0

class ArenaMark:
    func init(arena_id, chunk, top, generation, depth, token):
        self.token = token
        self.arena_id = arena_id
        self.chunk = chunk
        self.top = top
        self.generation = generation
        self.depth = depth

class Arena implements Allocator:
    func init(chunk_size=4096, max_bytes=null, max_chunk=1048576):
        _e.need_size("Arena", chunk_size)
        self.id = _alc._new_id()
        self._first = chunk_size
        self._next_size = chunk_size
        self._max_chunk = max_chunk
        self._max_bytes = max_bytes
        self._chunks = [_Chunk(chunk_size)]
        self._cur = 0
        self._allocs = 0
        self._generation = 0
        self._freed = false
        self._segments = [_Segment()]

    func _live(fn):
        if self._freed:
            raise(_e.MEMORY, "Arena." + fn + " : arène déjà libérée")

    func _reserved():
        n := 0
        for c in self._chunks:
            n += c.size
        return n

    func _new_chunk(at_least):
        size := self._next_size * 2
        if size > self._max_chunk:
            size = self._max_chunk
        if size < at_least:
            size = at_least
        if self._max_bytes != null and self._reserved() + size > self._max_bytes:
            size = at_least
            if self._reserved() + size > self._max_bytes:
                _e.out_of_memory("Arena.alloc", at_least, self._max_bytes - self._reserved())
        self._next_size = size
        append(self._chunks, _Chunk(size))
        self._cur = len(self._chunks) - 1

    # Vue de size octets, adresse alignée sur align.
    func alloc(size, align=8):
        self._live("alloc")
        _e.need_size("Arena.alloc", size)
        _e.need_align("Arena.alloc", align)
        while true:
            c := self._chunks[self._cur]
            base := c.buf.address()
            start := ((base + c.top + align - 1) // align) * align - base
            if start + size <= c.size:
                c.top = start + size
                self._allocs += 1
                seg := self._segments[len(self._segments) - 1]
                return _mv.MemoryView(c.buf._id, start, size, false, seg, c.buf)
            if self._cur + 1 < len(self._chunks):
                self._cur += 1
                self._chunks[self._cur].top = 0
            else:
                self._new_chunk(size + align)

    # Allocator.allocate : même chose, enveloppé dans une Allocation.
    func allocate(size, align=8):
        v := self.alloc(size, align)
        return Allocation(v, size, align, self.id)

    # Sans effet : l'espace revient au prochain reset / rollback.
    func deallocate(allocation):
        if not self.owns(allocation):
            _e.foreign("Arena.deallocate")
        allocation.freed = true

    func owns(allocation):
        return isinstance(allocation, Allocation) and allocation.allocator_id == self.id

    # Copie d'octets (str d'octets) dans l'arène.
    func alloc_bytes(data, align=1):
        n := _m.byte_len(data)
        v := self.alloc(n, align)
        v.write_bytes(data, 0)
        return v

    # Chaîne UTF-8 terminée par NUL.
    func alloc_str(text):
        n := _m.byte_len(text) + 1
        v := self.alloc(n, 1)
        v.write_str(text, 0)
        return v

    # Tableau de valeurs typées (aligné naturellement).
    func alloc_values(type_name, values):
        sz := _m.type_size(type_name)
        v := self.alloc(sz * len(values), sz)
        v.write_array(type_name, values, 0)
        return v

    # Point de restauration.
    func mark():
        self._live("mark")
        token := _alc._new_id()
        m := ArenaMark(self.id, self._cur, self._chunks[self._cur].top, self._generation, len(self._segments), token)
        append(self._segments, _Segment(token))
        return m

    # Revient au point m : les vues allouées depuis deviennent invalides.
    func rollback(m):
        self._live("rollback")
        if not isinstance(m, ArenaMark) or m.arena_id != self.id:
            raise("ArgumentError", "Arena.rollback : point de restauration d'une autre arène")
        if m.generation != self._generation:
            raise(_e.STALE_VIEW, "Arena.rollback : point de restauration antérieur à un reset()")
        if m.depth >= len(self._segments) or self._segments[m.depth].token != m.token:
            raise(_e.STALE_VIEW, "Arena.rollback : point de restauration abandonné (rollback vers un point antérieur)")
        # Segments ouverts depuis m : leurs vues deviennent invalides.
        while len(self._segments) > m.depth:
            sg := pop(self._segments)
            sg._epoch += 1
        append(self._segments, _Segment(m.token))
        k := m.chunk
        c := self._chunks[k]
        if c.top > m.top:
            c.buf.fill(0, m.top, c.top - m.top)
        c.top = m.top
        i := k + 1
        while i < len(self._chunks):
            ci := self._chunks[i]
            if ci.top > 0:
                ci.buf.fill(0, 0, ci.top)
            ci.top = 0
            i += 1
        self._cur = k

    # Invalide toutes les vues ; garde les tronçons (ou seulement le premier si shrink).
    func reset(shrink=false):
        self._live("reset")
        for seg in self._segments:
            seg._epoch += 1
        self._segments = [_Segment()]
        for c in self._chunks:
            if c.top > 0:
                c.buf.fill(0, 0, c.top)
            c.top = 0
        if shrink and len(self._chunks) > 1:
            while len(self._chunks) > 1:
                last := pop(self._chunks)
                last.buf.free()
            self._next_size = self._first
        self._cur = 0
        self._allocs = 0
        self._generation += 1

    func free():
        if self._freed:
            return
        for seg in self._segments:
            seg._epoch += 1
        for c in self._chunks:
            c.buf.free()
        self._chunks = []
        self._freed = true

    func used():
        n := 0
        for c in self._chunks:
            n += c.top
        return n

    func reserved():
        return self._reserved()

    func chunk_count():
        return len(self._chunks)

    func stats():
        return {"used": self.used(), "reserved": self._reserved(), "chunks": len(self._chunks),
                "allocations": self._allocs, "generation": self._generation}

# Arène passée à body(arena) ; libérée à la sortie, y compris sur erreur.
func scoped(chunk_size, body, max_bytes=null):
    a := Arena(chunk_size, max_bytes)
    try:
        return body(a)
    finally:
        a.free()
