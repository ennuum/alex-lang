# Tests : modules de pilotes ajoutés (sous-ensemble natif, exécutés ici dans la machine simulée de la VM) :
# pci.pci_errors / pci_bar / pci_capability, interrupt.*, dma.dma_errors / dma_descriptor / dma_coherency,
# driver.driver_version / driver_permissions / driver_lifecycle / driver_loader,
# storage_driver.storage_errors / storage_request / storage_partition / storage_cache,
# network_driver.network_driver_errors / network_ring / network_offload / network_interface,
# usb_driver.usb_driver_errors / usb_hid / usb_mass_storage / usb_serial,
# gpu_driver.gpu_driver_errors / gpu_scheduler / gpu_firmware / gpu_device_binding.
# Les mêmes modules sont compilés avec --native --freestanding par tests/stdlib2/native_drivers.sh.
from core use len, type
from collections use append
use check as t
use hw
use hw.sim_pci as sp
use pci.pci_config as cfg
use pci.pci_bus as pbus
use pci.pci_errors as perr
use pci.pci_bar as pb
use pci.pci_capability as pc
use interrupt.interrupt_errors as ierr
use interrupt.interrupt_vector as iv
use interrupt.interrupt_affinity as ia
use dma
use dma.dma_errors as derr
use dma.dma_descriptor as dd
use dma.dma_coherency as dc
from driver use Driver
use driver.driver_info as di
from driver.driver_info use DriverInfo
use driver.driver_manager as dmg
use driver.driver_version as dv
use driver.driver_permissions as dp
use driver.driver_lifecycle as dl
from driver.driver_lifecycle use PowerHooks
use driver.driver_loader as dld
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice
use storage_driver.disk as dk
use storage_driver.storage_errors as se
use storage_driver.storage_request as sr
use storage_driver.storage_partition as spart
use storage_driver.storage_cache as sc
use network_driver.ethernet as eth
use network_driver.network_packet as np
use network_driver.network_buffer as nb
use network_driver.network_device as nd
use network_driver.network_driver_errors as nde
use network_driver.network_ring as nr
use network_driver.network_offload as no
use network_driver.network_interface as ni
use usb.usb_descriptor as ud
use usb_driver.usb_host_controller as uhc
from usb_driver.usb_host_controller use HostController
use usb_driver.usb_driver_errors as ude
use usb_driver.usb_hid as hid
use usb_driver.usb_mass_storage as ms
use usb_driver.usb_serial as us
use gpu_driver.gpu_capabilities as gcap
use gpu_driver.gpu_command as gc
use gpu_driver.gpu_driver_errors as gde
use gpu_driver.gpu_scheduler as gs
use gpu_driver.gpu_firmware as gf
use gpu_driver.gpu_device_binding as gb

hw.sim_reset(64 * 1024 * 1024, 8 * 1024 * 1024)

# ------------------------------------------------------------------ pci
host := sp.install(0xE0000000, 2)
nic := sp.SimPciFunction(0x8086, 0x100E, 0x02, 0x00, 0, 3)
nic.set_bar(0, 0x20000, "mem32")
nic.set_bar(1, 64, "io")
nic.set_interrupt(1, 11)
nic.add_power_management()
nic.add_msi(true)
host.attach(0, 3, 0, nic)
gpu := sp.SimPciFunction(0x1234, 0x1111, 0x03, 0x00)
gpu.set_bar(0, 0x1000000, "mem64", true)
host.attach(0, 2, 0, gpu)
bus := pbus.PciBus(cfg.PortConfig())
bus.scan()
d := bus.find(0x8086, 0x100E)
t.check(d != null, "pci : e1000 trouvé")
t.check(pb.decode(1).is_io(), "pci_bar : BAR d'E/S")
t.check(pb.decode(0x0C).is64() and pb.decode(0x0C).prefetchable, "pci_bar : BAR 64 bits préchargeable")
pb.assign(d, 0, 0xFEB00000)
w := pb.window(d, 0)
t.eq(w.size, 0x20000, "pci_bar : fenêtre BAR0")
t.raises(() => w.read32(0x20000), "PciBarError", "pci_bar : accès hors fenêtre")
g := bus.find(0x1234, 0x1111)
t.eq(pb.memory_footprint(g.bars()), 0x1000000, "pci_bar : empreinte mémoire")
t.check(perr.has_errors(0x8000), "pci_errors : erreur de parité détectée")
t.check(not perr.has_errors(0x0010), "pci_errors : état sans erreur")
t.check(perr.describe_status(0x2000) != "", "pci_errors : texte d'état")
t.raises(() => perr.require_capability(g, 5), "PciCapabilityError", "pci_errors : capacité absente")
pm := pc.power(d)
t.check(pm != null and pm.state() == 0, "pci_capability : gestion d'énergie D0")
pm.set_state(3)
t.eq(pm.state_name(), "D3", "pci_capability : passage en D3hot")
pm.set_state(0)
m := pc.msi(d)
t.check(m != null and m.is64(), "pci_capability : MSI 64 bits")
m.configure(0xFEE00000, 0x41, 0)
m.enable(true)
t.check(m.enabled() and m.address() == 0xFEE00000 and m.data() == 0x41, "pci_capability : MSI programmé")
st := nic.msi_state()
t.check(st[0] and st[2] == 0x41, "pci_capability : vu côté périphérique")

# ------------------------------------------------------------------ interrupt
va := iv.VectorAllocator(80, 223)
v1 := va.allocate("e1000")
blk := va.allocate_block(4, "nvme")
t.eq(v1, 80, "interrupt_vector : premier vecteur libre")
t.eq(blk % 4, 0, "interrupt_vector : bloc MSI aligné")
t.eq(va.owner(blk + 2), "nvme", "interrupt_vector : propriétaire")
t.eq(va.free_owner("nvme"), 4, "interrupt_vector : libération par propriétaire")
dm_ := iv.decode_msi(iv.msi_address(3), iv.msi_data(0x51, false, false))
t.eq(dm_, [3, 0, 0x51, 0], "interrupt_vector : MSI codé / décodé")
t.check(ierr.exception_name(14) != "" and ierr.mnemonic(14) == "#PF", "interrupt_errors : nom d'exception")
t.check(ierr.page_fault_text(6) != "", "interrupt_errors : code de défaut de page")
t.raises(() => ierr.check_vector(300), "InvalidVector", "interrupt_errors : vecteur invalide")
s := ia.parse("0-3,6")
t.eq(s.format(), "0-3,6", "interrupt_affinity : notation de liste")
t.eq(s.count(), 5, "interrupt_affinity : nombre de processeurs")
t.eq(s.mask(), 79, "interrupt_affinity : masque")
t.raises(() => ia.parse("0-x"), "InterruptError", "interrupt_affinity : liste mal formée")
tab := ia.AffinityTable(4)
tab.spread([40, 41, 42, 43])
t.eq([tab.target(40), tab.target(41), tab.target(42), tab.target(43)], [0, 1, 2, 3], "interrupt_affinity : tourniquet")
tab.balance({40: 900, 41: 10, 42: 500, 43: 400})
loads := tab.load_per_cpu({40: 900, 41: 10, 42: 500, 43: 400})
t.check(loads[tab.target(40)] == 900, "interrupt_affinity : la source la plus chargée seule sur son processeur")

# ------------------------------------------------------------------ dma
b := dma.alloc(8192)
sg := dma.scatter(65536, 65536)
sg.add(b.phys, 8192)
tb := dma.alloc(4096)
t.eq(dd.write_ahci_prdt(tb.addr, sg, true), 1, "dma_descriptor : une entrée PRDT")
t.eq(dd.ahci_prdt_length(tb.addr, 1), 8192, "dma_descriptor : longueur PRDT")
lb := dma.alloc(4096)
prp := dd.nvme_prp(b.phys, 8192, lb)
t.eq(prp[1], b.phys + 4096, "dma_descriptor : PRP2 = deuxième page")
t.eq(len(derr.violations(b.phys + 1, 100, 0xFFFF, 4, 65536)), 2, "dma_errors : alignement + masque 24 bits")
t.check(derr.crosses(0xFFF0, 0x20, 0x10000), "dma_errors : frontière de 64 Kio traversée")
z := dc.Ownership(dma.map(b.addr, 4096, dma.TO_DEVICE, dma.MASK_32))
z.cpu_write32(0, 7)
z.give_to_device()
t.raises(() => z.cpu_read32(0), "DmaStateError", "dma_coherency : accès processeur interdit pendant le transfert")
z.take_back()
t.eq(z.cpu_read32(0), 7, "dma_coherency : donnée retrouvée")
lay := dd.DescriptorLayout(16)
lay.field("n", 8, 4)
lay.write(tb.addr, "n", 512)
t.eq(lay.read(tb.addr, "n"), 512, "dma_descriptor : champ nommé")

# ------------------------------------------------------------------ driver
t.eq(dv.parse("v1.4.2-rc1").format(), "1.4.2-rc1", "driver_version : analyse")
t.eq(dv.compare("1.10", "1.9"), 1, "driver_version : comparaison numérique")
t.eq(dv.compare("2.0.0-rc1", "2.0"), -1, "driver_version : pré-version antérieure")
t.check(dv.satisfies("1.4.2", "^1.2") and not dv.satisfies("1.4.2", ">=1.2, <1.4"), "driver_version : contraintes")
t.check(dv.satisfies("1.2.9", "~1.2.3") and not dv.satisfies("0.3.1", "^0.2"), "driver_version : ~ et ^0.x")
t.eq(dv.latest(["1.0", "1.10.1", "1.9"]), "1.10.1", "driver_version : la plus récente")
t.raises(() => dv.parse("1.x"), "DriverVersionError", "driver_version : version mal formée")
com := di.platform("com1", 0x3F8, 8, 4)
pol := dp.PermissionPolicy(true)
perm := pol.for_device("serie", com)
t.check(perm.check_io(0x3FD, 1) and perm.check_irq(4), "driver_permissions : ressources du périphérique accordées")
t.raises(() => perm.check_io(0x60, 1), "DriverPermissionError", "driver_permissions : port hors des droits")
perm.grant("dma", 0, 0xFFFFFFFF)
t.raises(() => perm.check_dma(0x100000000), "DriverPermissionError", "driver_permissions : DMA au-delà de 4 Gio")
t.eq(pol.denied_count(), 2, "driver_permissions : refus journalisés")
t.eq(perm.describe(), "serie : io 1016+8, irq 4, bus platform, dma <= 4294967295", "driver_permissions : description")
lenient := dp.PermissionPolicy(false).get("x")
t.check(not lenient.check_mmio(0, 4) and len(lenient.denied) == 1, "driver_permissions : mode journal seulement")

class Serial implements Driver:
    func init():
        self.i = DriverInfo("serie", "1.2.0", "port série", "platform")
        self.i.add_id(di.named("com1"))
        self.fails = 0
    func info():
        return self.i
    func probe(dev):
        return true
    func attach(dev):
        if self.fails > 0:
            self.fails -= 1
            raise("DeviceTimeout", "pas de réponse")
    func detach(dev):
        self.fails = self.fails
    func status(dev):
        return "ok"

class Tty implements Driver:
    func init():
        self.i = DriverInfo("tty", "0.3", "terminal", "platform")
        self.i.add_id(di.named("tty0"))
    func info():
        return self.i
    func probe(dev):
        return true
    func attach(dev):
        self.i = self.i
    func detach(dev):
        self.i = self.i
    func status(dev):
        return "ok"

class Hooks implements PowerHooks:
    func init():
        self.n = 0
    func suspend(dev):
        self.n += 1
    func resume(dev):
        self.n += 10

made := [0]
func make_serial():
    made[0] += 1
    return Serial()
func make_tty():
    return Tty()

mgr := dmg.DriverManager()
ld := dld.DriverLoader(mgr)
ld.add(dld.DriverFactory("serie", make_serial, [], "^1.0"))
ld.add(dld.DriverFactory("tty", make_tty, ["serie"], "*"))
ld.add(dld.DriverFactory("futur", make_tty, [], ">=2.0"))
t.eq(ld.order("tty"), ["serie", "tty"], "driver_loader : dépendances d'abord")
t.eq(ld.configure("# conf\noption serie baud=115200 bits=8\nblacklist vieux"), 2, "driver_loader : configuration")
t.eq(ld.option("serie", "baud", "9600"), "115200", "driver_loader : option")
t.raises(() => ld.load("futur"), "DriverLoadError", "driver_loader : API incompatible")
t.raises(() => ld.load("vieux"), "DriverLoadError", "driver_loader : fabrique inconnue")
mgr.add_device(com)
mgr.add_device(di.platform("tty0", 0, 0, -1))
t.eq(ld.autoload(), 2, "driver_loader : chargement automatique et liaison")
t.eq(ld.loaded, ["serie", "tty"], "driver_loader : pilotes chargés")
t.raises(() => ld.unload("serie"), "DriverLoadError", "driver_loader : déchargement refusé (dépendant)")
cyc := dld.DriverLoader(dmg.DriverManager())
cyc.add(dld.DriverFactory("a", make_tty, ["b"], "*"))
cyc.add(dld.DriverFactory("b", make_tty, ["a"], "*"))
t.raises(() => cyc.order("a"), "DriverLoadError", "driver_loader : cycle détecté")
lc := dl.Lifecycle(mgr)
hk := Hooks()
lc.set_power_hooks("serie", hk)
t.check(lc.start(com), "driver_lifecycle : démarrage")
lc.suspend(com)
t.eq(lc.state_name(com), "suspendu", "driver_lifecycle : veille")
lc.resume(com)
t.eq(hk.n, 11, "driver_lifecycle : crochets suspend / resume")
t.raises(() => lc.resume(com), "DriverStateError", "driver_lifecycle : reprise sans veille")
lc.fail(com, "file bloquée")
t.eq(lc.state(com), dl.FAILED, "driver_lifecycle : échec signalé")
t.check(lc.restart(com), "driver_lifecycle : redémarrage")
lc.max_restarts = 1
lc.fail(com, "encore")
t.raises(() => lc.restart(com), "DriverStateError", "driver_lifecycle : trop de redémarrages")
lc.remove(com)
t.eq(lc.state_name(com), "retiré", "driver_lifecycle : retrait")
t.check(len(lc.history) >= 8, "driver_lifecycle : historique")
ld.unload("tty")
ld.unload("serie")
t.eq(ld.loaded, [], "driver_loader : tout déchargé")

# ------------------------------------------------------------------ storage_driver
t.eq(se.ata_error_text(0x44), "UNC (donnée illisible), ABRT (commande refusée)", "storage_errors : registre ATA")
t.eq(se.ahci_tfd_text(0x4051), "état DRDY, ERR ; erreur UNC (donnée illisible)", "storage_errors : TFD AHCI")
t.eq(se.nvme_status_text(0x0281), "erreur de lecture non corrigible", "storage_errors : statut NVMe")
t.check(se.nvme_retryable(0x0004) and not se.nvme_retryable(0x4004), "storage_errors : DNR")
ram := bd.RamDisk("ram0", 512, 8192)
gl := spart.GptLayout(ram, 2048)
t.eq([gl.first_usable(), gl.last_usable()], [34, 8158], "storage_partition : zone utilisable")
gl.add("EFI", spart.type_guid("efi"), 2048)
gl.add("racine", spart.type_guid("linux"), 0)
gl.write(0x5EED)
t.eq(spart.verify(ram), [], "storage_partition : table cohérente")
parts := dk.Disk(ram).partitions()
t.eq(len(parts), 2, "storage_partition : relue par storage_driver.disk")
t.check(parts[0].start == 2048 and parts[0].label == "EFI" and parts[1].count == 4063, "storage_partition : entrées")
t.eq(parts[1].type_guid, "0FC63DAF-8483-4772-8E79-3D69D8477DE4", "storage_partition : GUID de type")
t.eq(spart.guid_bytes("C12A7328-F81F-11D2-BA4B-00A0C93EC93B")[0:4], [0x28, 0x73, 0x2A, 0xC1], "storage_partition : ordre mixte des GUID")
g2 := spart.load(ram, 2048)
t.check(g2.disk_guid == gl.disk_guid and g2.parts[0].unique_guid == gl.parts[0].unique_guid, "storage_partition : reprise d'une table")
g2.remove(2)
g2.add("swap", spart.type_guid("swap"), 1024)
t.eq(g2.free_ranges(), [[34, 2047], [5120, 8158]], "storage_partition : espaces libres")
t.raises(() => g2.add_at("x", spart.type_guid("linux"), 4096, 10), "PartitionError", "storage_partition : chevauchement")
t.raises(() => spart.type_guid("ntfs"), "PartitionError", "storage_partition : type inconnu")
g2.write(7)
t.eq(spart.verify(ram), [], "storage_partition : table modifiée cohérente")
buf := hw.alloc_pages(1)
ram.read_blocks(1, 1, buf)
hw.poke8(buf + 40, 0x55)
ram.write_blocks(1, 1, buf)
pbs := spart.verify(ram)
t.check("en-tête principal : CRC incorrect" in pbs, "storage_partition : corruption détectée")
t.eq(spart.crc32(buf, 0), 0, "storage_partition : CRC vide")

class Flaky implements BlockDevice:
    func init(inner):
        self.inner = inner
        self.fail_next = 0
    func name():
        return "flaky"
    func block_size():
        return 512
    func block_count():
        return self.inner.block_count()
    func read_blocks(lba, count, b):
        if self.fail_next > 0:
            self.fail_next -= 1
            raise("DeviceIoError", "CRC")
        return self.inner.read_blocks(lba, count, b)
    func write_blocks(lba, count, b):
        return self.inner.write_blocks(lba, count, b)
    func flush():
        return true
    func read_only():
        return false

fl := Flaky(ram)
trk := sr.RequestTracker(fl, 4)
b2 := hw.alloc_pages(4)
r := sr.IoRequest(sr.READ, 10, 0)
r.add_segment(b2, 4).add_segment(b2 + 2048, 4)
fl.fail_next = 2
t.check(trk.execute(r) and r.attempts == 3, "storage_request : réussite après deux nouvelles tentatives")
r2 := sr.IoRequest(sr.READ, 10, 0).add_segment(b2, 1)
fl.fail_next = 5
t.check(not trk.execute(r2) and r2.status == sr.FAILED, "storage_request : échec définitif")
big := sr.IoRequest(sr.WRITE, 0, 0).add_segment(b2, 5).add_segment(b2 + 4096, 6)
pieces := big.split(4, 512)
t.eq([len(pieces), pieces[1].lba, pieces[1].count(), len(pieces[1].segments)], [3, 4, 4, 2], "storage_request : découpe")
tags := []
k := 0
while k < 6:
    q := sr.IoRequest(sr.READ, k, k).add_segment(b2, 1)
    q.timeout = 5
    append(tags, trk.start(q))
    k += 1
t.eq(tags, [0, 1, 2, 3, -1, -1], "storage_request : étiquettes NCQ")
t.eq(trk.complete(1, true, "").status, sr.DONE, "storage_request : fin asynchrone")
t.eq(trk.complete(2, false, "erreur").status, sr.INFLIGHT, "storage_request : nouvelle tentative remise en file")
t.eq(trk.tick(10), 4, "storage_request : délais dépassés")
t.raises(() => trk.execute(sr.IoRequest(sr.READ, 9000, 0).add_segment(b2, 1)), "DeviceIoError", "storage_request : hors du disque")
cache := sc.ReadaheadCache(ram, 64, 2, 16)
k = 0
while k < 8:
    cache.read_blocks(100 + k * 4, 4, b2)
    k += 1
cst := cache.stats()
t.check(cst.prefetch_used > 0 and cst.hits > cst.misses, "storage_cache : lecture anticipée efficace")
cache.write_blocks(500, 4, b2)
t.eq(cache.dirty_blocks(), 4, "storage_cache : écriture différée")
t.eq(cache.invalidate(500, 2), 2, "storage_cache : invalidation")
cache.flush()
t.eq(cache.dirty_blocks(), 0, "storage_cache : vidage")
t.raises(() => sc.ReadaheadCache(ram, 4, 2, 8), "CacheError", "storage_cache : paramètres invalides")

# ------------------------------------------------------------------ network_driver
pool := nb.BufferPool(96)
pk := pool.get()
np.build_udp(pk, eth.parse_mac("52:54:00:12:34:56"), eth.BROADCAST, np.ip("10.0.2.15"), np.ip("10.0.2.2"), 1234, 53, "bonjour")
t.eq(nde.frame_problem(pk.data(), pk.length, false), "", "network_driver_errors : trame correcte")
t.check(nde.frame_problem(pk.data(), 20, false) != "", "network_driver_errors : trame courte")
hw.poke32(pk.data() + pk.length, eth.crc32_at(pk.data(), pk.length))
t.eq(nde.frame_problem(pk.data(), pk.length + 4, true), "", "network_driver_errors : FCS correct")
hw.poke8(pk.data() + 30, 1)
t.eq(nde.frame_problem(pk.data(), pk.length + 4, true), "FCS faux (CRC-32)", "network_driver_errors : FCS faux")
t.eq(no.verify_checksums(pk), [false, false], "network_offload : sommes fausses après modification")
no.fill_checksums(pk)
t.eq(no.verify_checksums(pk), [true, true], "network_offload : sommes recalculées")
no.insert_vlan(pk, 42, 3)
t.eq(eth.vlan_of(pk.data()), 42, "network_offload : étiquette VLAN")
t.raises(() => no.insert_vlan(pk, 7, 0), "OffloadError", "network_offload : double étiquette")
t.eq(no.strip_vlan(pk), 42, "network_offload : retrait VLAN")
t.check(np.parse(pk).is_udp() and no.verify_checksums(pk) == [true, true], "network_offload : trame intacte")
t.eq(no.negotiate(no.Features(no.TSO | no.TX_CSUM | no.RX_CSUM), no.ALL).describe(), " rx-csum tx-csum", "network_offload : TSO exige la dispersion")
bigp := pool.get()
payload := ""
k = 0
while k < 100:
    payload = payload + "0123456789"
    k += 1
no.build_tcp(bigp, 1, 2, np.ip("10.0.0.1"), np.ip("10.0.0.2"), 4000, 80, 1000, 1, 0x19, payload)
segs := no.segment_tcp(bigp, 300, pool)
t.eq(len(segs), 4, "network_offload : TSO logiciel")
seqs := [sg2.u32(38) for sg2 in segs]
t.eq(seqs, [1000, 1300, 1600, 1900], "network_offload : numéros de séquence")
t.eq([sg2.u8(47) for sg2 in segs], [16, 16, 16, 25], "network_offload : FIN / PSH sur la dernière")
okc := true
total := 0
for sg2 in segs:
    v := no.verify_checksums(sg2)
    okc = okc and v[0] and v[1]
    total += np.parse(sg2).payload_length
t.check(okc and total == 1000, "network_offload : segments valides")
t.eq(no.e1000_context(bigp), [14, 24, 33, 34, 50, 0], "network_offload : contexte e1000")
tx := nr.TxRing(4, nr.legacy_tx(), pool)
sent := 0
k = 0
while k < 4:
    p2 := pool.get()
    p2.put_string("x")
    if tx.send(p2):
        sent += 1
    k += 1
t.eq(sent, 3, "network_ring : anneau plein à n-1")
tx.device_complete(0)
tx.device_complete(1)
t.eq(tx.reclaim(), 2, "network_ring : récupération des descripteurs émis")
rx := nr.RxRing(4, nr.legacy_rx(), pool)
t.eq(rx.fill(), 4, "network_ring : garnissage")
src := hw.alloc_pages(1)
hw.store_string("trame-reçue", src)
rx.device_receive(src, 12, true, 0)
rx.device_receive(src, 5, false, 0)
rx.device_receive(src, 7, true, 0x01)
got := rx.harvest(8)
t.check(len(got) == 1 and got[0].string(0, 5) == "trame", "network_ring : réception")
t.check(rx.errors == 2 and rx.fragments == 1, "network_ring : erreurs et fragments")
tbl := ni.InterfaceTable()
lo := tbl.add(nd.LoopbackDevice(pool), "lo")
e0 := tbl.add(nd.LoopbackDevice(pool), "eth")
e1 := tbl.add(nd.LoopbackDevice(pool), "eth")
t.eq([lo.name, e0.name, e1.name], ["lo", "eth0", "eth1"], "network_interface : nommage")
tbl.assign("lo", np.ip("127.0.0.1"), 8)
tbl.assign("eth0", np.ip("10.0.2.15"), 24)
tbl.assign("eth1", np.ip("192.168.1.10"), 24)
tbl.add_route(0, 0, np.ip("10.0.2.2"), "eth0", 100)
tbl.add_route(0, 0, np.ip("192.168.1.1"), "eth1", 50)
lo.set_up(true)
e0.set_up(true)
t.eq(tbl.lookup(np.ip("8.8.8.8")).describe(), "default via 10.0.2.2 dev eth0 metric 100", "network_interface : seule route active")
e1.set_up(true)
t.eq(tbl.lookup(np.ip("8.8.8.8")).iface, "eth1", "network_interface : plus petite métrique")
lk := tbl.lookup(np.ip("10.0.2.77"))
t.check(lk.connected and np.ip_text(lk.next_hop(np.ip("10.0.2.77"))) == "10.0.2.77", "network_interface : plus long préfixe, voisin direct")
t.eq(np.ip_text(e0.addresses[0].broadcast()), "10.0.2.255", "network_interface : diffusion")
t.raises(() => e0.set_mtu(70000), "NetworkDriverError", "network_interface : MTU invalide")
e0.set_up(false)
e1.set_up(false)
t.raises(() => tbl.lookup(np.ip("8.8.8.8")), "LinkDown", "network_interface : aucune route")

# ------------------------------------------------------------------ usb_driver
t.eq(ude.uhci_error_type(0x400000), "UsbStall", "usb_driver_errors : STALL")
t.eq(ude.uhci_error_type(0x440000), "UsbTimeout", "usb_driver_errors : délai")
t.raises(() => ude.check_td("ep1", 0x100000), "UsbBabble", "usb_driver_errors : babble")
mouse := hid.parse_bytes(hid.mouse_descriptor())
t.eq(len(mouse.fields), 3, "usb_hid : champs de la souris")
t.eq(hid.device_kind(mouse), "souris", "usb_hid : sorte de périphérique")
t.eq(mouse.report_bytes(hid.INPUT, 0), 4, "usb_hid : longueur du rapport")
rep := hw.alloc_pages(1)
for i, v in [[0, 5], [1, 0xFE], [2, 3], [3, 0xFF]]:
    hw.poke8(rep + i, v)
vals := [[x.page, x.usage, x.value] for x in mouse.decode(rep, 4)]
t.eq(vals, [[9, 1, 1], [9, 2, 0], [9, 3, 1], [1, 48, -2], [1, 49, 3], [1, 56, -1]], "usb_hid : décodage boutons / axes signés")
kb := hid.parse_bytes(hid.keyboard_descriptor())
t.eq([hid.device_kind(kb), kb.report_bytes(hid.INPUT, 0), kb.report_bytes(hid.OUTPUT, 0)], ["clavier", 8, 1], "usb_hid : clavier")
hw.zero(rep, 8)
hw.poke8(rep, 0x02)
hw.poke8(rep + 2, 4)
hw.poke8(rep + 3, 5)
pressed := [x.usage for x in kb.decode(rep, 8) if x.value != 0]
t.eq(pressed, [225, 4, 5], "usb_hid : Maj gauche + A + B")
t.raises(() => hid.parse_bytes([0xC0]), "UsbProtocolError", "usb_hid : End Collection orphelin")
ids := hid.parse_bytes([0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x85, 0x01, 0x05, 0x09, 0x19, 0x01, 0x29, 0x08, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x85, 0x02, 0x05, 0x01, 0x09, 0x30, 0x16, 0x00, 0x80, 0x26, 0xFF, 0x7F, 0x75, 0x10, 0x95, 0x01, 0x81, 0x02, 0xC0])
t.eq(ids.report_ids(hid.INPUT), [1, 2], "usb_hid : identifiants de rapport")
t.eq(ids.report_bytes(hid.INPUT, 2), 3, "usb_hid : longueur avec identifiant")
hw.poke8(rep, 2)
hw.poke16(rep + 1, 0xFFFF)
t.eq([[x.usage, x.value] for x in ids.decode(rep, 3)], [[48, -1]], "usb_hid : rapport n° 2, valeur 16 bits signée")
cbw := hw.alloc_pages(1)
ms.write_cbw(cbw, 9, 512, true, 0, ms.cdb_read(100, 1))
t.check(hw.peek32(cbw) == ms.CBW_SIGNATURE and hw.peek8(cbw + 14) == 10 and hw.peek8(cbw + 15) == 0x28, "usb_mass_storage : CBW READ (10)")
t.eq(len(ms.cdb_read(0x100000000, 8)), 16, "usb_mass_storage : READ (16) au-delà de 2 Tio")
ms.write_csw(cbw, 9, 0, 1)
t.check(not ms.parse_csw(cbw, 13).ok(), "usb_mass_storage : CSW en échec")
t.raises(() => ms.parse_csw(cbw, 12), "UsbProtocolError", "usb_mass_storage : CSW tronqué")
hw.zero(cbw, 64)
hw.poke8(cbw, 0x70)
hw.poke8(cbw + 2, 2)
hw.poke8(cbw + 12, 0x3A)
sn := ms.parse_sense(cbw, 18)
t.eq([sn.describe(), ms.sense_action(sn)], ["NOT READY : support absent", "échouer"], "usb_mass_storage : support absent")
hw.poke8(cbw + 12, 0x04)
hw.poke8(cbw + 13, 0x01)
t.eq(ms.sense_action(ms.parse_sense(cbw, 18)), "attendre", "usb_mass_storage : en cours de démarrage")
hw.zero(cbw, 64)
hw.poke8(cbw + 1, 0x80)
hw.store_string("ALEXCORPCle USB magique 1.00", cbw + 8)
inq := ms.parse_inquiry(cbw, 36)
t.check(inq.removable and inq.vendor == "ALEXCORP" and inq.product == "Cle USB magique" and inq.revision == "1.00", "usb_mass_storage : INQUIRY")
hw.zero(cbw, 16)
hw.poke8(cbw + 3, 1)
hw.poke8(cbw + 7, 0xFF)
hw.poke8(cbw + 10, 2)
t.eq(ms.parse_capacity16(cbw, 12), [4294967552, 512], "usb_mass_storage : capacité 16")
t.eq(len(ms.reset_recovery(0, 0x81, 0x02)), 3, "usb_mass_storage : séquence de réinitialisation")
lcod := us.LineCoding(115200, 8, us.PARITY_EVEN, us.STOP_2)
t.eq(lcod.describe(), "115200 bauds 8E2", "usb_serial : description")
t.eq(lcod.to_bytes(), [0, 194, 1, 0, 2, 2, 8], "usb_serial : codage sur 7 octets")
t.raises(() => us.LineCoding(9600, 9, 0, 0), "ArgumentError", "usb_serial : bits de données invalides")
t.eq(us.ftdi_divisor(115200, 3000000), [26, 0, 115384], "usb_serial : diviseur FTDI 115200")
t.eq(us.ftdi_divisor(9600, 3000000), [16696, 0, 9600], "usb_serial : diviseur FTDI 9600 (0x4138)")

class FakeHc implements HostController:
    func name():
        return "faux"
    func setup():
        self.log = self.log
    func port_count():
        return 1
    func port_connected(port):
        return true
    func reset_port(port):
        return 1
    func init():
        self.log = []
        self.report = []
        self.echo = ""
    func control(dev, setup, b):
        append(self.log, [setup.request_type, setup.request, setup.value])
        if setup.request == ud.REQ_GET_DESCRIPTOR and (setup.value >> 8) == ud.DT_REPORT:
            dsc := hid.mouse_descriptor()
            i := 0
            while i < len(dsc):
                hw.poke8(b + i, dsc[i])
                i += 1
            return len(dsc)
        return setup.length
    func bulk(dev, endpoint, max_packet, b, length, tries):
        if endpoint & 0x80 != 0:
            if self.echo == "":
                return -1
            n := hw.byte_size(self.echo)
            hw.store_string(self.echo, b)
            self.echo = ""
            return n
        self.echo = self.echo + hw.string_at(b, length)
        return length
    func interrupt_open(dev, endpoint, max_packet):
        return 7
    func interrupt_read(pipe, b):
        i := 0
        while i < len(self.report):
            hw.poke8(b + i, self.report[i])
            i += 1
        return len(self.report)

fhc := FakeHc()
udev := uhc.UsbDev(1, 1, 1)
itf := ud.InterfaceDescriptor(0, 0, ud.CLASS_HID, 0, 0)
append(itf.endpoints, ud.EndpointDescriptor(0x81, 3, 4, 10))
itf.hid_report_length = 52
hd := hid.HidDevice()
hd.attach(fhc, udev, itf)
fhc.report = [1, 10, 0xF6, 1]
t.eq(hd.poll(), 6, "usb_hid : HidDevice décode le rapport")
t.eq([hd.value(hid.PAGE_GENERIC, 0x30), hd.value(hid.PAGE_GENERIC, 0x31), hd.pressed(hid.PAGE_BUTTON)], [10, -10, [1]], "usb_hid : valeurs")
data := ud.InterfaceDescriptor(1, 0, ud.CLASS_CDC_DATA, 0, 0)
append(data.endpoints, ud.EndpointDescriptor(0x82, 2, 64, 0))
append(data.endpoints, ud.EndpointDescriptor(0x02, 2, 64, 0))
acm := us.AcmSerial()
t.check(acm.matches(udev, data), "usb_serial : interface de données CDC reconnue")
acm.attach(fhc, udev, data)
t.eq(acm.write("bonjour\r\n"), 9, "usb_serial : écriture")
t.eq(acm.read(), "bonjour\r\n", "usb_serial : lecture (écho)")
t.eq(fhc.log[len(fhc.log) - 2:len(fhc.log)], [[33, 32, 0], [33, 34, 3]], "usb_serial : SET_LINE_CODING puis DTR+RTS")

# ------------------------------------------------------------------ gpu_driver
caps := gcap.GpuCapabilities("bochs", 16 * 1024 * 1024, 2560, 1600)
caps.depths = [8, 16, 24, 32]
gde.check_mode(caps, 1024, 768, 32)
t.raises(() => gde.check_mode(caps, 4096, 768, 32), "ModeError", "gpu_driver_errors : trop large")
small := gcap.GpuCapabilities("petite", 4 * 1024 * 1024, 2560, 1600)
small.depths = [32]
t.raises(() => gde.check_mode(small, 1920, 1080, 32), "ModeError", "gpu_driver_errors : VRAM insuffisante")
t.raises(() => gde.check_mode(caps, 1024, 768, 12), "ModeError", "gpu_driver_errors : profondeur")
mem := hw.alloc_pages(64)
sa := gc.Surface2D(mem, 64, 64, 256)
sb := gc.Surface2D(mem + 64 * 256, 64, 64, 256)
sch := gs.GpuScheduler(4)
desk := sch.context("bureau", gs.PRIO_HIGH, sa)
app := sch.context("appli", gs.PRIO_NORMAL, sb)
bg := sch.context("fond", gs.PRIO_NORMAL, sb)
cb := gc.CommandBuffer()
k = 0
while k < 10:
    cb.fill_rect(k, k, 4, 4, 0xFF0000)
    k += 1
f1 := sch.submit(app, cb)
f2 := sch.submit(bg, cb)
cb2 := gc.CommandBuffer()
cb2.clear(0x000020)
cb2.fence(7)
f3 := sch.submit(desk, cb2)
sch.run(1)
t.eq(sch.fence(desk), f3, "gpu_scheduler : priorité haute d'abord")
t.eq(sa.pixel(5, 5), 0x000020, "gpu_scheduler : surface du bureau effacée")
sch.run(2)
t.check(app.preemptions == 1 and bg.slices == 1, "gpu_scheduler : tourniquet et préemption")
t.check(sch.wait(app, f1) and sb.pixel(9, 9) == 0xFF0000, "gpu_scheduler : attente d'une barrière")
sch.run(100)
t.eq(sch.pending(), 0, "gpu_scheduler : tout exécuté")
sch.hang_slices = 2
longcb := gc.CommandBuffer()
k = 0
while k < 40:
    longcb.pixel(1, 1, 5)
    k += 1
sch.submit(app, longcb)
sch.submit(desk, cb2)
sch.run(100)
t.check(app.hangs == 1 and app.guilty and sch.fence(desk) == 2, "gpu_scheduler : blocage détecté, les autres continuent")
rom := hw.alloc_pages(8)
n1 := gf.build_rom_image(rom, 0x1234, 0x1111, 0x030000, 0, 4, false)
n2 := gf.build_rom_image(rom + n1, 0x1234, 0x1111, 0x030000, 3, 2, true)
imgs := gf.parse_option_rom(rom, n1 + n2)
t.eq([x.code_name() for x in imgs], ["x86 (BIOS)", "EFI x64"], "gpu_firmware : chaîne d'images")
t.check(imgs[0].checksum_ok and imgs[0].is_vga() and imgs[1].last, "gpu_firmware : somme, classe, dernière image")
hw.poke8(rom + 100, 7)
t.check(not gf.parse_option_rom(rom, n1 + n2)[0].checksum_ok, "gpu_firmware : somme fausse détectée")
t.raises(() => gf.parse_option_rom(rom + 1, 100), "FirmwareError", "gpu_firmware : signature absente")
ed := hw.alloc_pages(1)
gf.build_edid(ed, "RHT", 0x1234, 1024, 768, "QEMU Monitor")
e := gf.parse_edid(ed)
t.eq([e.manufacturer, e.name, e.width, e.height, e.refresh, e.checksum_ok], ["RHT", "QEMU Monitor", 1024, 768, 60, true], "gpu_firmware : EDID")
hw.poke8(ed + 3, 0)
t.raises(() => gf.parse_edid(ed), "FirmwareError", "gpu_firmware : en-tête EDID")
store := gf.FirmwareStore()
blob := hw.alloc_pages(1)
hw.store_string("microcode v2", blob)
store.add("gpu/ucode.bin", "2", blob, 12)
t.eq(store.request("gpu/ucode.bin", 8).crc, 0xA1B61158, "gpu_firmware : CRC32 (identique à zlib)")
hw.poke8(blob, 0x6E)
t.raises(() => store.request("gpu/ucode.bin", 8), "FirmwareError", "gpu_firmware : micrologiciel corrompu")
vga := di.platform("00:02.0", 0, 0, -1)
vga.cls = 3
vga.subclass = 0
vga.add_resource("mem", 0xFD000000, 0x1000000)
g3 := di.platform("01:00.0", 0, 0, -1)
g3.cls = 3
g3.subclass = 2
g3.add_resource("mem", 0xE0000000, 0x10000000)
nicdev := di.platform("00:03.0", 0, 0, -1)
nicdev.cls = 2
btab := gb.GpuBindingTable()
t.eq(btab.scan([g3, nicdev, vga]), 2, "gpu_device_binding : cartes graphiques retenues")
t.eq(btab.primary().location, "00:02.0", "gpu_device_binding : VGA compatible par défaut")
btab.set_boot_framebuffer(0xE0100000, 1024 * 768 * 4)
t.eq(btab.primary().location, "01:00.0", "gpu_device_binding : carte du tampon d'amorçage")
t.check(btab.bind(g3, "pilote-3d", 0xE0000000, 256 * 1048576).handover, "gpu_device_binding : reprise du tampon")
t.check(not btab.bind(vga, "bochs-vga", 0xFD000000, 16 * 1048576).handover, "gpu_device_binding : une seule reprise")
t.raises(() => btab.bind(vga, "x", 0, 0), "BindingError", "gpu_device_binding : double liaison")
t.eq(btab.conflicts(), [], "gpu_device_binding : aucun conflit")
g3.add_resource("mem", 0xFD800000, 0x1000)
t.eq(len(btab.conflicts()), 1, "gpu_device_binding : recouvrement détecté")

t.summary("test_drivers2")
