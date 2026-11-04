# ALEX STANDARD LIBRARY — hw.sim_pci (MACHINE SIMULÉE, VM seulement)
#
# Bus PCI simulé pour la machine de `hw` : un contrôleur hôte qui répond au mécanisme n° 1 (ports 0xCF8 /
# 0xCFC..0xCFF) et, si on le demande, à l'ECAM PCI Express (fenêtre MMIO de 256 Mio au plus), avec des fonctions
# dont l'espace de configuration se comporte comme le vrai :
#   - identifiants, classe, révision, en-tête en lecture seule ;
#   - registre de commande inscriptible (bits IO, MEMORY, BUS_MASTER, INTX_DISABLE...), état « écrire 1 efface » ;
#   - registres de base (BAR) qui renvoient leur masque de taille après une écriture de 0xFFFFFFFF (mémoire 32 /
#     64 bits, préchargeable, ou ports), puis l'adresse attribuée ;
#   - liste chaînée de capacités (MSI 32 / 64 bits, MSI-X, gestion d'énergie, PCI Express, propre au fabricant) ;
#   - ponts PCI-PCI (en-tête de type 1) avec bus primaire / secondaire / subordonné ;
#   - fonctions multiples (bit 7 du type d'en-tête mis automatiquement sur la fonction 0).
# Chaque fonction peut porter un modèle de périphérique : quand le pilote programme un BAR et active le décodage
# (commande IO / MEMORY), la zone est branchée sur la machine (hw.sim_map_ports / hw.sim_map_mmio) et les accès
# vont aux méthodes io_read / io_write / mem_read / mem_write du modèle, avec (numéro de BAR, décalage).
#
#   use hw
#   use hw.sim_pci as sp
#   hw.sim_reset()
#   host := sp.install()                                      # ports 0xCF8..0xCFF
#   nic := sp.SimPciFunction(0x8086, 0x100E, 0x02, 0x00)      # e1000
#   nic.set_bar(0, 0x20000, "mem32")
#   nic.set_bar(1, 64, "io")
#   nic.set_interrupt(1, 11)
#   nic.add_msi(true)
#   host.attach(0, 3, 0, nic)
#   # le pilote voit alors 00:03.0 avec pci.pci_bus.PciBus(pci.pci_config.PortConfig())
#
# Erreurs : ArgumentError (emplacement occupé, BAR invalide).

from core use len, type
from collections use append, contains_key, keys
use hw

const ADDRESS_PORT := 0xCF8

func _cat(a, b):
    out := [x for x in a]
    for x in b:
        append(out, x)
    return out

func _bytes(n):
    return [0 for i in 0..n]

# ---------------------------------------------------------------- fonction PCI
class SimPciFunction:
    func init(vendor, device, cls, subclass, prog_if=0, revision=1, header_type=0):
        self.cfg = _bytes(4096)
        self.readonly = _bytes(4096)        # 1 : octet en lecture seule
        self.bar_info = [null, null, null, null, null, null]  # [taille, sorte, préchargeable] par BAR
        self.bar_mapped = [null, null, null, null, null, null]  # [sorte, base] branché sur la machine
        self.model = null
        self.next_cap = 0x40
        self.location = null
        self.writes = []                     # journal [décalage, valeur] des écritures de configuration
        self._put(0, 2, vendor)
        self._put(2, 2, device)
        self._put(8, 1, revision)
        self._put(9, 1, prog_if)
        self._put(10, 1, subclass)
        self._put(11, 1, cls)
        self._put(14, 1, header_type)
        for off in [0, 1, 2, 3, 8, 9, 10, 11, 14, 0x34, 0x3D]:
            self.readonly[off] = 1
        self._put(6, 2, 0)
        if header_type & 127 == 1:
            # pont : bus primaire / secondaire / subordonné inscriptibles, pas de BAR 2..5
            self.bar_info = [null, null, null, null, null, null]

    func _put(off, size, v):
        k := 0
        while k < size:
            self.cfg[off + k] = (v >> (8 * k)) & 255
            k += 1

    func _get(off, size):
        v := 0
        k := 0
        while k < size:
            v = v | (self.cfg[off + k] << (8 * k))
            k += 1
        return v

    func vendor():
        return self._get(0, 2)

    func command():
        return self._get(4, 2)

    func header_kind():
        return self.cfg[14] & 127

    # Registre de base n : size octets (puissance de 2), sorte "mem32", "mem64" (prend aussi n + 1) ou "io".
    func set_bar(n, size, kind="mem32", prefetch=false, base=0):
        if n < 0 or n > 5 or (kind == "mem64" and n > 4):
            raise("ArgumentError", "SimPciFunction.set_bar : BAR " + str(n) + " invalide")
        if size & (size - 1) != 0 or size < 4:
            raise("ArgumentError", "SimPciFunction.set_bar : taille puissance de 2 attendue")
        self.bar_info[n] = [size, kind, prefetch]
        low := 0
        if kind == "io":
            low = 1
        else:
            if kind == "mem64":
                low = 4
                self.bar_info[n + 1] = [0, "upper", false]
            if prefetch:
                low = low | 8
        self._put(0x10 + 4 * n, 4, (base & ~(size - 1) & 0xFFFFFFFF) | low)
        if kind == "mem64":
            self._put(0x14 + 4 * n, 4, (base >> 32) & 0xFFFFFFFF)
        return self

    # Adresse programmée du BAR n (64 bits combinés), sans les bits de type.
    func bar_address(n):
        info := self.bar_info[n]
        if info == null:
            return 0
        raw := self._get(0x10 + 4 * n, 4)
        if info[1] == "io":
            return raw & 0xFFFFFFFC
        a := raw & 0xFFFFFFF0
        if info[1] == "mem64":
            a = a | (self._get(0x14 + 4 * n, 4) << 32)
        return a

    func set_interrupt(pin, line=0):
        self.cfg[0x3D] = pin & 255
        self.cfg[0x3C] = line & 255
        return self

    func set_subsystem(vendor, device):
        self._put(0x2C, 2, vendor)
        self._put(0x2E, 2, device)
        for off in [0x2C, 0x2D, 0x2E, 0x2F]:
            self.readonly[off] = 1
        return self

    # Ajoute une capacité (id, octets qui suivent l'en-tête [id, suivant]) ; renvoie son décalage.
    func add_capability(cap_id, body, writable=true):
        off := self.next_cap
        if off + 2 + len(body) > 256:
            raise("ArgumentError", "SimPciFunction.add_capability : plus de place dans l'en-tête")
        # chaîner : dernier « suivant » -> off
        if self.cfg[0x34] == 0:
            self.cfg[0x34] = off
        else:
            p := self.cfg[0x34]
            while self.cfg[p + 1] != 0:
                p = self.cfg[p + 1]
            self.cfg[p + 1] = off
        self.cfg[off] = cap_id
        self.cfg[off + 1] = 0
        self.readonly[off] = 1
        self.readonly[off + 1] = 1
        k := 0
        while k < len(body):
            self.cfg[off + 2 + k] = body[k] & 255
            if not writable:
                self.readonly[off + 2 + k] = 1
            k += 1
        self._put(6, 2, self._get(6, 2) | 0x10)        # état : liste de capacités présente
        self.next_cap = (off + 2 + len(body) + 3) & ~3
        return off

    # MSI : contrôle (64 bits si is64), adresse, données.
    func add_msi(is64=true, vectors_log2=0):
        ctrl := (vectors_log2 & 7) << 1
        if is64:
            ctrl = ctrl | 0x80
        body := _cat([ctrl & 255, (ctrl >> 8) & 255], _bytes(12 if is64 else 8))
        return self.add_capability(0x05, body)

    func add_power_management():
        return self.add_capability(0x01, [3, 0, 0, 0, 0, 0])

    func add_pcie(port_type=0):
        return self.add_capability(0x10, _cat([2 | (port_type << 4), 0], _bytes(56)), false)

    func add_msix(table_size, table_bar, table_offset, pba_bar, pba_offset):
        n := table_size - 1
        t := (table_offset & ~7) | table_bar
        p := (pba_offset & ~7) | pba_bar
        return self.add_capability(0x11, [n & 255, (n >> 8) & 7, t & 255, (t >> 8) & 255, (t >> 16) & 255, (t >> 24) & 255,
                                          p & 255, (p >> 8) & 255, (p >> 16) & 255, (p >> 24) & 255])

    func add_vendor_capability(data):
        return self.add_capability(0x09, _cat([len(data) + 3], data))

    # Valeurs MSI programmées par le pilote : [activé, adresse, données], ou null sans capacité MSI.
    func msi_state():
        p := self.cfg[0x34]
        while p != 0:
            if self.cfg[p] == 0x05:
                ctrl := self._get(p + 2, 2)
                addr := self._get(p + 4, 4)
                data_off := p + 8
                if ctrl & 0x80 != 0:
                    addr = addr | (self._get(p + 8, 4) << 32)
                    data_off = p + 12
                return [ctrl & 1 == 1, addr, self._get(data_off, 2)]
            p = self.cfg[p + 1]
        return null

    # Lie un modèle de périphérique (io_read(bar, décalage, taille), io_write(bar, décalage, taille, v),
    # mem_read(bar, décalage, taille), mem_write(bar, décalage, taille, v)).
    func attach_model(model):
        self.model = model
        return self

    # ---- accès de configuration (par le contrôleur hôte) ----
    func read32(offset):
        return self._get(offset & 0xFFC, 4)

    func write32(offset, value):
        off := offset & 0xFFC
        append(self.writes, [off, value])
        if off >= 0x10 and off <= 0x24 and self.header_kind() == 0:
            self._write_bar((off - 0x10) // 4, value)
            return
        if off >= 0x10 and off <= 0x14 and self.header_kind() == 1:
            self._write_bar((off - 0x10) // 4, value)
            return
        if off == 0x30 and self.header_kind() == 0:
            self._put(0x30, 4, 0)        # pas de ROM d'extension
            return
        if off == 4:
            # commande (16 bits bas) ; état (16 bits hauts) : écrire 1 efface
            self._put(4, 2, value & 0x07FF)
            st := self._get(6, 2) & ~((value >> 16) & 0xF900)
            self._put(6, 2, st)
            self._update_mappings()
            return
        k := 0
        while k < 4:
            if self.readonly[off + k] == 0:
                self.cfg[off + k] = (value >> (8 * k)) & 255
            k += 1

    func _write_bar(n, value):
        info := self.bar_info[n]
        if info == null:
            self._put(0x10 + 4 * n, 4, 0)
            return
        if info[1] == "upper":
            low_info := self.bar_info[n - 1]
            mask := ~(low_info[0] - 1)
            self._put(0x10 + 4 * n, 4, value & ((mask >> 32) & 0xFFFFFFFF))
            self._update_mappings()
            return
        size := info[0]
        low := 0
        if info[1] == "io":
            low = 1
        else:
            if info[1] == "mem64":
                low = 4
            if info[2]:
                low = low | 8
        self._put(0x10 + 4 * n, 4, ((value & ~(size - 1)) & 0xFFFFFFFF) | low)
        self._update_mappings()

    # Branche ou débranche les zones des BAR selon le registre de commande.
    func _update_mappings():
        if self.model == null:
            return
        cmd := self.command()
        n := 0
        while n < 6:
            info := self.bar_info[n]
            want := null
            if info != null and info[1] != "upper":
                base := self.bar_address(n)
                if info[1] == "io" and cmd & 1 != 0 and base != 0 and base < 0xFFFC:
                    want = ["io", base]
                elif info[1] != "io" and cmd & 2 != 0 and base != 0 and base < 0xFFFFFFF0 & ~(info[0] - 1):
                    want = ["mem", base]
            cur := self.bar_mapped[n]
            if not _same(cur, want):
                if cur != null:
                    hw.sim_unmap(cur[2])
                    self.bar_mapped[n] = null
                if want != null:
                    w := _BarWindow(self.model, n)
                    w.base = want[1]
                    if want[0] == "io":
                        hw.sim_map_ports(want[1], info[0], w)
                    else:
                        hw.sim_map_mmio(want[1], info[0], w)
                    self.bar_mapped[n] = [want[0], want[1], w]
            n += 1

func _same(cur, want):
    if cur == null or want == null:
        return cur == null and want == null
    return cur[0] == want[0] and cur[1] == want[1]

# Adaptateur : zone d'un BAR -> méthodes du modèle avec le numéro de BAR et le décalage dans la zone.
class _BarWindow:
    func init(model, bar):
        self.model = model
        self.bar = bar
        self.base = 0

    func io_read(port, size):
        return self.model.io_read(self.bar, port - self._io_base(), size)

    func io_write(port, size, value):
        self.model.io_write(self.bar, port - self._io_base(), size, value)

    func _io_base():
        return self.base

    func mem_read(offset, size):
        return self.model.mem_read(self.bar, offset, size)

    func mem_write(offset, size, value):
        self.model.mem_write(self.bar, offset, size, value)

# ---------------------------------------------------------------- pont PCI-PCI
func bridge(vendor=0x8086, device=0x244E):
    b := SimPciFunction(vendor, device, 0x06, 0x04, 0, 1, 1)
    return b

# ---------------------------------------------------------------- contrôleur hôte
class SimPciHost:
    func init():
        self.functions = {}            # bus * 256 + emplacement * 8 + fonction -> SimPciFunction
        self.address = 0
        self.ecam_base = null
        self.accesses = 0

    func _key(bus, dev, fn):
        return bus * 256 + dev * 8 + fn

    func attach(bus, dev, fn, f):
        k := self._key(bus, dev, fn)
        if contains_key(self.functions, k) and self.functions[k] != null:
            raise("ArgumentError", "SimPciHost.attach : " + str(bus) + ":" + str(dev) + "." + str(fn) + " déjà occupé")
        self.functions[k] = f
        f.location = [bus, dev, fn]
        if fn > 0:
            f0 := self.at(bus, dev, 0)
            if f0 != null:
                f0.cfg[14] = f0.cfg[14] | 128
        else:
            for g in [1, 2, 3, 4, 5, 6, 7]:
                if self.at(bus, dev, g) != null:
                    f.cfg[14] = f.cfg[14] | 128
        return f

    func detach(bus, dev, fn):
        k := self._key(bus, dev, fn)
        if contains_key(self.functions, k):
            self.functions[k] = null

    func at(bus, dev, fn):
        k := self._key(bus, dev, fn)
        if contains_key(self.functions, k):
            return self.functions[k]
        return null

    func read(bus, dev, fn, offset):
        self.accesses += 1
        f := self.at(bus, dev, fn)
        if f == null:
            return 0xFFFFFFFF
        return f.read32(offset)

    func write(bus, dev, fn, offset, value):
        self.accesses += 1
        f := self.at(bus, dev, fn)
        if f != null:
            f.write32(offset, value)

    # ---- mécanisme n° 1 : 0xCF8 (adresse), 0xCFC..0xCFF (données) ----
    func io_read(port, size):
        if port >= 0xCF8 and port < 0xCFC:
            return (self.address >> (8 * (port - 0xCF8))) & ((1 << (8 * size)) - 1)
        a := self.address
        if a & 0x80000000 == 0:
            return (1 << (8 * size)) - 1
        v := self.read((a >> 16) & 255, (a >> 11) & 31, (a >> 8) & 7, a & 0xFC)
        return (v >> (8 * (port - 0xCFC))) & ((1 << (8 * size)) - 1)

    func io_write(port, size, value):
        if port >= 0xCF8 and port < 0xCFC:
            if size == 4:
                self.address = value & 0xFFFFFFFF
            return
        a := self.address
        if a & 0x80000000 == 0:
            return
        bus := (a >> 16) & 255
        dev := (a >> 11) & 31
        fn := (a >> 8) & 7
        off := a & 0xFC
        shift := 8 * (port - 0xCFC)
        if size == 4 and shift == 0:
            self.write(bus, dev, fn, off, value)
            return
        old := self.read(bus, dev, fn, off)
        if old == 0xFFFFFFFF and self.at(bus, dev, fn) == null:
            return
        mask := ((1 << (8 * size)) - 1) << shift
        nv := (old & ~mask) | ((value << shift) & mask)
        # registre d'état : ne pas réécrire les bits « écrire 1 efface » d'une écriture partielle de la commande
        if off == 4 and shift < 2:
            nv = nv & 0xFFFF
        self.write(bus, dev, fn, off, nv & 0xFFFFFFFF)

    # ---- ECAM ----
    func mem_read(offset, size):
        bus := (offset >> 20) & 255
        dev := (offset >> 15) & 31
        fn := (offset >> 12) & 7
        reg := offset & 0xFFF
        v := self.read(bus, dev, fn, reg & 0xFFC)
        return (v >> (8 * (reg & 3))) & ((1 << (8 * size)) - 1)

    func mem_write(offset, size, value):
        bus := (offset >> 20) & 255
        dev := (offset >> 15) & 31
        fn := (offset >> 12) & 7
        reg := offset & 0xFFF
        if size == 4:
            self.write(bus, dev, fn, reg, value)
            return
        old := self.read(bus, dev, fn, reg & 0xFFC)
        shift := 8 * (reg & 3)
        mask := ((1 << (8 * size)) - 1) << shift
        self.write(bus, dev, fn, reg & 0xFFC, ((old & ~mask) | ((value << shift) & mask)) & 0xFFFFFFFF)

# Crée le contrôleur hôte et le branche sur la machine simulée : ports 0xCF8..0xCFF, et fenêtre ECAM à
# ecam_base (buses 0..buses-1) si demandée. Un pont hôte (00:00.0, Intel 440FX) est ajouté si host_bridge.
func install(ecam_base=null, buses=8, host_bridge=true):
    h := SimPciHost()
    hw.sim_map_ports(ADDRESS_PORT, 8, h)
    if ecam_base != null:
        hw.sim_map_mmio(ecam_base, buses * 1048576, h)
        h.ecam_base = ecam_base
    if host_bridge:
        h.attach(0, 0, 0, SimPciFunction(0x8086, 0x1237, 0x06, 0x00, 0, 2))
    return h
