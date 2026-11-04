# Sans OS (QEMU) : pilotes de stockage — IDE (PIO), AHCI (SATA), NVMe, liés par le cadre driver ; tables
# de partitions, file de requêtes (fusion), cache de blocs, partition, accès à l'octet.
use hw
use storage_driver
use storage_driver.block_device as bd
use storage_driver.disk as dk
use storage_driver.storage_queue as sq
from storage_driver.block_device use BlockDevice, BlockCache, Partition
from core use len

s := storage_driver.stack()
print(s.report())
ds := s.disks()
print("disques : " + str(len(ds)))
buf := hw.alloc_pages(64)
for d in ds:
    print(bd.describe(d))
    d.read_blocks(1, 1, buf)
    print("  signature : " + hw.string_at(buf, 11))
    d.read_blocks(90, 20, buf)
    print("  motif : " + str(hw.peek8(buf + 10 * 512 + 200)))
    hw.store_string("écrit sur " + d.name(), buf)
    d.write_blocks(3000, 1, buf)
    d.flush()
    hw.zero(buf, 512)
    d.read_blocks(3000, 1, buf)
    print("  relu : " + hw.string_at(buf, 11 + len(d.name())))
    k := dk.Disk(d)
    k.partitions()
    print("  table " + k.scheme + " : " + str(len(k.entries)) + " partitions, " + k.entries[1].kind())
    p := k.open(2)
    print("  " + bd.describe(p))
# file de requêtes : 16 lectures contiguës d'un bloc -> une commande
d0 := ds[0]
q := sq.StorageQueue(d0, 256)
i := 15
while i >= 0:
    q.read(100 + i, 1, buf + 512 * i)
    i -= 1
q.flush()
q.write(4000, 2, buf)
q.run()
print("file : " + q.stats())
print("  ordre rétabli : " + str(hw.peek8(buf + 255)) + " " + str(hw.peek8(buf + 15 * 512 + 3)))
# cache de blocs
c := BlockCache(d0, 8, true)
c.read_blocks(1, 1, buf)
c.read_blocks(1, 1, buf)
hw.store_string("cache", buf)
c.write_blocks(5000, 1, buf)
print("cache : " + str(c.hits) + " succès, " + str(c.misses) + " défauts, " + str(c.dirty_count()) + " modifié(s)")
c.flush()
d0.read_blocks(5000, 1, buf + 4096)
print("  écrit au vidage : " + hw.string_at(buf + 4096, 5))
bd.write_string(d0, 6000 * 512 + 510, "à cheval")
print("octets : " + bd.read_string(d0, 6000 * 512 + 510, 9))
