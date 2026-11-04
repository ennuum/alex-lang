# Tests : memory.allocator, arena, pool_allocator, aligned_memory, memory_region, memory_stats,
# memory_protection, page_allocator, memory_errors.
from core use len, type
from collections use append
use check as t
use memory.buffer as buf
use memory.allocator as alc
use memory.arena as arena
use memory.pool_allocator as pa
use memory.aligned_memory as am
use memory.memory_region as mr
use memory.memory_stats as ms
use memory.memory_protection as mp
use memory.page_allocator as pg
use memory.memory_errors as me

# ---------------------------------------------------------------- errors
t.check(me.is_memory_error("StaleViewError"), "is_memory_error")
t.check(me.is_power_of_two(64) and not me.is_power_of_two(48), "is_power_of_two")
t.raises(() => me.need_align("f", 3), "AlignmentError", "need_align")

# ---------------------------------------------------------------- aligned_memory
t.eq(am.align_up(13, 8), 16, "align_up")
t.eq(am.align_down(13, 8), 8, "align_down")
t.eq(am.padding(13, 8), 3, "padding")
t.eq(am.next_power_of_two(1000), 1024, "next_power_of_two")
t.eq(am.alignment_of(24), 8, "alignment_of")
ab := am.AlignedBuffer(4096, 4096)
t.check(am.is_aligned(ab.address(), 4096), "AlignedBuffer page")
ab.write("u32", 5, 0)
t.eq(ab.read("u32", 0), 5, "AlignedBuffer accès")
b64 := buf.Buffer(256, true, 16)
sl := am.aligned_slice(b64.view(1), 64)
t.check(am.is_aligned(sl.address(), 64), "aligned_slice")
t.raises(() => am.align_up(3, 6), "AlignmentError", "align non puissance de 2")
t.eq(am.stride(10, 8), 16, "stride")

# ---------------------------------------------------------------- allocator
sys := alc.SystemAllocator()
tr := alc.TrackingAllocator(sys)
x := tr.allocate(64)
x.view.write("u32", 7)
t.eq(x.view.read("u32"), 7, "allocation utilisable")
t.eq(tr.stats()["live_allocations"], 1, "tracking vivantes")
y := tr.allocate(32)
t.eq(tr.stats()["peak_bytes"], 96, "tracking pic")
tr.deallocate(x)
t.check(not x.valid(), "allocation libérée invalide")
t.raises(() => x.view.read("u32"), "MemoryError", "use after free")
t.raises(() => tr.deallocate(x), "MemoryError", "double free")
t.eq(len(tr.leaks()), 1, "fuites")
t.eq(tr.release_all(), 1, "release_all")
t.eq(tr.leak_report(), "tracking : aucune fuite", "rapport vide")
lim := alc.LimitedAllocator(alc.SystemAllocator(), 100)
l1 := lim.allocate(60)
t.raises(() => lim.allocate(50), "MemoryError", "quota")
lim.deallocate(l1)
t.eq(lim.remaining(), 100, "quota rendu")
other := alc.SystemAllocator().allocate(8)
t.raises(() => sys.deallocate(other), "AllocatorError", "allocation étrangère")
used := alc.with_allocation(16, (a) => a.size)
t.eq(used, 16, "with_allocation")

# ---------------------------------------------------------------- arena
a := arena.Arena(256)
v := a.alloc(16, 8)
t.check(am.is_aligned(v.address(), 8), "alignement")
v.write("u64", 99)
s := a.alloc_str("bonjour")
t.eq(s.read_str(0), "bonjour", "alloc_str")
m := a.mark()
tmp := a.alloc(100)
a.rollback(m)
t.raises(() => tmp.read("u8", 0), "StaleViewError", "rollback invalide les vues récentes")
t.eq(v.read("u64"), 99, "rollback garde les vues anciennes")
tmp2 := a.alloc(100)
a.rollback(m)
t.check(not tmp2.valid(), "rollback réutilisable")
big := a.alloc(1000)
t.check(a.chunk_count() >= 2, "nouveau tronçon")
big.write("u8", 1, 999)
t.eq(a.alloc_values("i32", [1, 2, 3]).read_array("i32", 3), [1, 2, 3], "alloc_values")
m2 := a.mark()
m3 := a.mark()
a.rollback(m2)
t.raises(() => a.rollback(m3), "StaleViewError", "point abandonné")
a.reset()
t.raises(() => v.read("u64"), "StaleViewError", "reset")
t.eq(a.used(), 0, "used après reset")
a.reset(true)
t.eq(a.chunk_count(), 1, "reset shrink")
alloc_a := a.allocate(8)
t.check(a.owns(alloc_a), "Arena allocator")
a.free()
t.raises(() => a.alloc(8), "MemoryError", "arène libérée")
capped := arena.Arena(64, 128)
capped.alloc(60)
t.raises(() => capped.alloc(100), "MemoryError", "max_bytes")
r := arena.scoped(128, (ar) => ar.alloc(4).size())
t.eq(r, 4, "scoped")

# ---------------------------------------------------------------- pool
p := pa.PoolAllocator(64, 4)
a1 := p.allocate()
a1.view.write("u64", 42)
t.eq(a1.view.read("u64"), 42, "slot utilisable")
p.deallocate(a1)
t.raises(() => a1.view.read("u64"), "StaleViewError", "slot rendu")
t.raises(() => p.deallocate(a1), "MemoryError", "double free pool")
slots := [p.allocate() for i in 0..4]
t.raises(() => p.allocate(), "PoolExhaustedError", "pool plein")
t.eq(p.stats()["in_use"], 4, "in_use")
p.deallocate(slots[0])
t.eq(p.available(), 1, "available")
again := p.allocate()
t.eq(again.view.read("u64"), 0, "slot réinitialisé")
g := pa.PoolAllocator(32, 2, true)
g.allocate()
g.allocate()
g.allocate()
t.eq(g.capacity(), 4, "pool extensible")
t.raises(() => g.allocate(64), "ArgumentError", "taille > slot")
fb := alc.FallbackAllocator(pa.PoolAllocator(16, 1), alc.SystemAllocator())
fb.allocate(16)
fb.allocate(16)
t.eq(fb.fallbacks, 1, "fallback")

created := [0]
func make_obj():
    created[0] += 1
    return {"n": created[0], "data": []}
op := pa.ObjectPool(make_obj, (o) => o["data"].clear(), 2)
o1 := op.acquire()
append(o1["data"], 1)
op.release(o1)
o2 := op.acquire()
t.eq(o2["n"], 1, "objet réutilisé")
t.eq(len(o2["data"]), 0, "objet réinitialisé")
op.acquire()
t.raises(() => op.acquire(), "PoolExhaustedError", "ObjectPool max")
t.eq(op.stats()["created"], 2, "ObjectPool créés")

# ---------------------------------------------------------------- region
rg := mr.MemoryRegion(0x1000, 0x2000, "code", "r-x")
t.check(rg.contains(0x1800) and not rg.contains(0x3000), "contains")
t.eq(mr.hex(rg.end()), "0x3000", "hex")
t.check(rg.executable() and not rg.writable(), "prot")
rmap := mr.RegionMap()
rmap.insert(rg)
rmap.insert(mr.MemoryRegion(0x4000, 0x1000, "pile", "rw-"))
t.eq(rmap.find(0x4010).name, "pile", "find")
t.eq(rmap.find(0x3500), null, "find trou")
gaps := rmap.gaps(0, 0x6000)
t.eq([gg.start for gg in gaps], [0, 0x3000, 0x5000], "gaps")
t.eq(rmap.find_free(0x800, 0x3000, 0x6000, 0x1000), 0x3000, "find_free")
t.raises(() => rmap.insert(mr.MemoryRegion(0x2000, 0x100)), "ArgumentError", "chevauchement")
t.eq(len(rg.subtract(mr.MemoryRegion(0x1800, 0x100))), 2, "subtract")
t.eq(rg.intersect(mr.MemoryRegion(0x2800, 0x1000)).size, 0x800, "intersect")
mm2 := mr.RegionMap([mr.MemoryRegion(0, 10, "a"), mr.MemoryRegion(10, 10, "a"), mr.MemoryRegion(30, 5, "b")])
t.eq(mm2.merge_adjacent(), 1, "merge_adjacent")
t.eq(mm2.total_size(), 25, "total_size")
pm := mr.parse_maps("00400000-00452000 r-xp 00000000 08:02 173521 /usr/bin/dbus\n7ffd1000-7ffd2000 rw-p 00000000 00:00 0 [stack]\n")
t.eq(pm.size(), 2, "parse_maps")
t.eq(pm.find(0x400010).kind, "file", "parse_maps kind")
t.check(mr.process_map().size() > 3, "process_map")

# ---------------------------------------------------------------- stats
s1 := ms.snapshot()
t.check(s1.gc_live > 0, "gc_live")
t.check(s1.rss == null or s1.rss > 0, "rss")
res := ms.measure(() => buf.Buffer(1000))
t.check(res[1].managed_bytes >= 1000, "measure")
t.eq(ms.format_bytes(1536), "1.5 Kio", "format_bytes")
t.check(ms.system()["total"] == null or ms.system()["total"] > 0, "system")
t.check(len(s1.format()) > 10, "format")

# ---------------------------------------------------------------- protection
t.eq(mp.to_string(mp.RX), "r-x", "to_string")
t.eq(mp.parse("rw-"), 3, "parse")
t.check(not mp.allows(mp.parse("r--"), "w"), "allows")
t.raises(() => mp.check_wx(mp.WRITE + mp.EXEC), "ArgumentError", "W^X")
t.raises(() => mp.parse("rz"), "ArgumentError", "parse invalide")
fz := buf.Buffer(8)
func try_write(bb):
    try:
        bb.write("u8", 1)
        return "écrit"
    catch e:
        return e.type
t.eq(mp.with_readonly(fz, try_write), "MemoryError", "with_readonly gèle")
fz.write("u8", 2)
t.eq(fz.read("u8"), 2, "with_readonly dégèle")
gr := mp.guarded(100)
gr.write("u8", 1, 99)
t.check(not mp.can_write(gr, 100), "page de garde")
sec := buf.Buffer(16)
sec.write("u32", 0xdeadbeef)
mp.wipe(sec)
t.eq(sec.read("u32"), 0, "wipe")
prt := mp.ProtectedRegion(4096)
prt.write("u8", 7)
prt.seal()
t.check(not mp.can_write(prt.region), "seal")
t.eq(prt.read("u8"), 7, "lecture après seal")
prt.lock_out()
t.check(not mp.can_read(prt.region), "lock_out")
prt.destroy()

# ---------------------------------------------------------------- pages
pal := pg.PageAllocator(16)
sp := pal.alloc_pages(3)
sp.view().write("u64", 1)
t.eq(sp.first_page, 0, "first fit")
t.eq(pal.free_pages(), 13, "free_pages")
sp2 := pal.alloc_pages(2)
t.eq(sp2.first_page, 3, "suivante")
pal.free_pages_of(sp)
t.raises(() => sp.view(), "StaleViewError", "étendue rendue")
t.raises(() => pal.free_pages_of(sp), "MemoryError", "double free pages")
t.check(not mp.can_read(pal.region, 0), "page rendue inaccessible")
t.eq(pal.largest_free_run(), 11, "largest_free_run")
sp3 := pal.alloc_pages(2)
t.eq(sp3.first_page, 0, "trou réutilisé")
t.eq(pal.map_string(), "##.##...........", "map_string")
t.raises(() => pal.alloc_pages(12), "MemoryError", "plus de place")
pal.destroy()

t.summary("memory2")
