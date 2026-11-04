# Couche de stockage dans la machine simulée : RamDisk, Partition, BlockCache, Disk (MBR, GPT), accès à
# l'octet, file de requêtes (ascenseur, fusion, barrière, erreurs).
from core use len
from collections use append
use hw
use storage_driver.block_device as bd
use storage_driver.disk as dk
use storage_driver.storage_queue as sq

ok := [0]
ko := [0]
func check(cond, label):
    if cond:
        ok[0] += 1
    else:
        ko[0] += 1
        print("ÉCHEC " + label)

hw.sim_reset(64 * 1024 * 1024, 1024 * 1024)
ram := bd.RamDisk("ram0", 512, 8192)          # 4 Mio
check(bd.capacity(ram) == 4194304, "capacité")
check(bd.describe(ram) == "ram0 : 8192 blocs de 512 octets (4 Mio)", "describe")
buf := hw.alloc_pages(16)
hw.store_string("bloc dix", buf)
ram.write_blocks(10, 1, buf)
hw.zero(buf, 512)
ram.read_blocks(10, 1, buf)
check(hw.string_at(buf, 8) == "bloc dix", "lecture / écriture")
erreur := ""
try:
    ram.read_blocks(8190, 4, buf)
catch e:
    erreur = e.type
check(erreur == "DeviceIoError", "hors du disque")
ram.set_read_only(true)
erreur = ""
try:
    ram.write_blocks(0, 1, buf)
catch e2:
    erreur = e2.type
check(erreur == "DeviceIoError", "lecture seule")
ram.set_read_only(false)

# octets à cheval sur deux blocs
bd.write_string(ram, 1020, "frontière")
check(bd.read_string(ram, 1020, 10) == "frontière", "accès à l'octet")

# MBR
dk.write_mbr(ram, [[0x0C, 2048, 2048], [0x83, 4096, 4096]], 0xCAFE)
disk := dk.Disk(ram)
parts := disk.partitions()
check(disk.scheme == "mbr" and len(parts) == 2 and disk.disk_id == 0xCAFE, "table MBR")
check(parts[0].bootable and parts[0].kind() == "FAT32 (LBA)" and parts[1].kind() == "Linux", "types")
p2 := disk.open(2)
check(p2.block_count() == 4096 and p2.name() == "ram0p2", "partition ouverte")
hw.store_string("dans p2", buf)
p2.write_blocks(0, 1, buf)
ram.read_blocks(4096, 1, buf + 4096)
check(hw.string_at(buf + 4096, 7) == "dans p2", "décalage de la partition")
erreur = ""
try:
    p2.read_blocks(4096, 1, buf)
catch e3:
    erreur = e3.type
check(erreur == "DeviceIoError", "partition bornée")

# GPT (protecteur + en-tête + une entrée « EFI »)
g := bd.RamDisk("ram1", 512, 4096)
dk.write_mbr(g, [[0xEE, 1, 4095]], 0)
h := buf
hw.zero(h, 512)
hw.store_string("EFI PART", h)
hw.poke64(h + 72, 2)
hw.poke32(h + 80, 4)
hw.poke32(h + 84, 128)
g.write_blocks(1, 1, h)
hw.zero(h, 512)
# GUID C12A7328-F81F-11D2-BA4B-00A0C93EC93B
hw.poke32(h, 0xC12A7328)
hw.poke16(h + 4, 0xF81F)
hw.poke16(h + 6, 0x11D2)
octets := [0xBA, 0x4B, 0x00, 0xA0, 0xC9, 0x3E, 0xC9, 0x3B]
for i in 0..8:
    hw.poke8(h + 8 + i, octets[i])
hw.poke64(h + 16, 1)
hw.poke64(h + 32, 34)
hw.poke64(h + 40, 233)
lettres := [69, 70, 73]
for i in 0..3:
    hw.poke16(h + 56 + 2 * i, lettres[i])
g.write_blocks(2, 1, h)
gd := dk.Disk(g)
gp := gd.partitions()
check(gd.scheme == "gpt" and len(gp) == 1, "table GPT")
check(gp[0].kind() == "système EFI" and gp[0].start == 34 and gp[0].count == 200 and gp[0].label == "EFI", "entrée GPT : " + gp[0].describe())

# cache
c := bd.BlockCache(ram, 4, true)
c.read_blocks(10, 1, buf)
c.read_blocks(10, 1, buf)
check(c.hits == 1 and c.misses == 1, "cache : succès")
hw.store_string("différé", buf)
c.write_blocks(20, 1, buf)
ram.read_blocks(20, 1, buf + 4096)
check(hw.string_at(buf + 4096, 9) != "différé" and c.dirty_count() == 1, "écriture différée")
for k2 in 0..6:
    c.read_blocks(100 + k2, 1, buf + 8192)
ram.read_blocks(20, 1, buf + 4096)
check(hw.string_at(buf + 4096, 9) == "différé", "écrit à l'éviction")
c.flush()
check(c.dirty_count() == 0, "vidé")

# file de requêtes
before := ram.reads
q := sq.StorageQueue(ram, 64)
fins := []
i := 7
while i >= 0:
    r := q.read(200 + i, 1, buf + 512 * i)
    r.then((rq) => append(fins, rq.lba))
    i -= 1
q.read(50, 1, buf + 8192)
q.flush()
w := q.write(300, 1, buf)
bad := q.read(9000, 1, buf)
check(q.size() == 12, "12 en file")
q.run()
check(q.completed == 11 and q.failed == 1 and not bad.ok and bad.done, "erreur isolée : " + q.stats())
check(q.operations == 5 and q.merged == 7, "fusion des 8 lectures : " + q.stats())
check(fins[0] == 200 and len(fins) == 8, "ordre croissant")
check(ram.reads - before == 9, "blocs lus")
check(w.ok, "écriture après la barrière")
print("stockage simulé : " + str(ok[0]) + " OK, " + str(ko[0]) + " échecs")
