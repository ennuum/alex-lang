# alex: native
from core use len
from collections use append
use hw
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice, RamDisk
use storage_driver.disk as dk
use storage_driver.storage_errors as se
use storage_driver.storage_request as sr
use storage_driver.storage_partition as sp
use storage_driver.storage_cache as sc

class Flaky implements BlockDevice:
    inner: RamDisk
    fail_next: int := 0
    func init(inner: RamDisk):
        self.inner = inner
        self.fail_next = 0
    func name() -> str:
        return "flaky"
    func block_size() -> int:
        return 512
    func block_count() -> int:
        return self.inner.block_count()
    func read_blocks(lba: int, count: int, buf: int) -> bool:
        if self.fail_next > 0:
            self.fail_next -= 1
            raise("DeviceIoError", "CRC")
        return self.inner.read_blocks(lba, count, buf)
    func write_blocks(lba: int, count: int, buf: int) -> bool:
        return self.inner.write_blocks(lba, count, buf)
    func flush() -> bool:
        return true
    func read_only() -> bool:
        return false

print(se.ata_error_text(0x44))
print(se.ata_status_text(0x51))
print(se.ahci_tfd_text(0x4051))
print(se.nvme_status_text(0x0281))
print(se.nvme_status_text(0x4004))
print(se.nvme_retryable(0x0004))
print(se.nvme_retryable(0x4004))
print(se.ata_retryable(0x80))
ram := RamDisk("ram0", 512, 8192)
g := sp.GptLayout(ram, 2048)
print(g.first_usable())
print(g.last_usable())
g.add("EFI", sp.type_guid("efi"), 2048)
g.add("racine", sp.type_guid("linux"), 0)
g.write(0x5EED)
print(len(sp.verify(ram)))
d := dk.Disk(ram)
for p in d.partitions():
    print(p.describe())
    print(p.type_guid)
g2 := sp.load(ram, 2048)
print(g2.parts[0].unique_guid == g.parts[0].unique_guid)
print(g2.disk_guid == g.disk_guid)
g2.remove(2)
g2.add("swap", sp.type_guid("swap"), 1024)
print(g2.free_ranges())
try:
    g2.add_at("x", sp.type_guid("linux"), 4096, 10)
catch e:
    print(e.type)
g2.write(7)
print(len(sp.verify(ram)))
print(dk.Disk(ram).rescan()[1].describe())
buf := hw.alloc_pages(1)
ram.read_blocks(1, 1, buf)
hw.poke8(buf + 40, 0x55)
ram.write_blocks(1, 1, buf)
print(sp.verify(ram))
fl := Flaky(ram)
t := sr.RequestTracker(fl, 4)
b2 := hw.alloc_pages(4)
r := sr.IoRequest(sr.READ, 10, 0)
r.add_segment(b2, 4).add_segment(b2 + 2048, 4)
fl.fail_next = 2
print(t.execute(r))
print(r.attempts)
r2 := sr.IoRequest(sr.READ, 10, 0)
r2.add_segment(b2, 1)
fl.fail_next = 5
print(t.execute(r2))
print(r2.describe())
big := sr.IoRequest(sr.WRITE, 0, 0)
big.add_segment(b2, 5).add_segment(b2 + 4096, 6)
parts := big.split(4, 512)
print(len(parts))
print(parts[1].lba)
print(parts[1].count())
print(len(parts[1].segments))
tags: list[int] := []
k := 0
while k < 6:
    q := sr.IoRequest(sr.READ, k, k)
    q.add_segment(b2, 1)
    q.timeout = 5
    append(tags, t.start(q))
    k += 1
print(tags)
done := t.complete(1, true, "")
if done != null:
    print(done.describe())
d2 := t.complete(2, false, "erreur")
if d2 != null:
    print(d2.status)
print(t.tick(10))
print(t.report())
try:
    t.execute(sr.IoRequest(sr.READ, 9000, 0).add_segment(b2, 1))
catch e:
    print(e.type)
c := sc.ReadaheadCache(ram, 64, 2, 16)
k = 0
while k < 8:
    c.read_blocks(100 + k * 4, 4, b2)
    k += 1
print(c.stats().describe())
c.write_blocks(500, 4, b2)
print(c.dirty_blocks())
print(c.invalidate(500, 2))
c.write_fua(600, 1, b2)
print(c.dirty_blocks())
c.flush()
print(c.dirty_blocks())
print(c.cached())
