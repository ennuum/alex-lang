# Bas niveau : machine simulée, `pci`, `interrupt`, `dma`, `driver`, pilotes

Tout ce qu'il faut pour écrire un **système d'exploitation** en Alex : accès PCI, contrôleurs
d'interruptions, DMA, un cadre de pilotes, et des pilotes réels (stockage, réseau, USB, graphique).

Tous ces modules commencent par la ligne `# alex: native` : ils sont compilés par `alexc build --native
--freestanding` dans un noyau (image Multiboot démarrée par QEMU ou GRUB), ET ils s'exécutent dans la VM
(`alexc run`) grâce à la **machine simulée** de `hw` : RAM simulée, PIC 8259 et PIT, ports et zones MMIO
attribués à des modèles de périphériques écrits en Alex.

```
# noyau.al — alexc build --native --freestanding noyau.al -o noyau.bin ; qemu-system-x86_64 -kernel noyau.bin ...
use hw
use interrupt
use storage_driver
use storage_driver.block_device as bd
use network_driver
use usb_driver
use gpu_driver

m := interrupt.with_pic()
pile := storage_driver.stack()                    # IDE, AHCI, NVMe trouvés sur le bus PCI
for d in pile.disks():
    print(bd.describe(d))
carte := network_driver.find_e1000()
usb := usb_driver.start()                         # UHCI : clavier HID, clé USB
g := gpu_driver.find_bochs()
if g != null:
    g.set_mode(800, 600, 32, true)
```

## Machine simulée (VM)

| Module | Rôle |
|---|---|
| `hw` (VM) | mêmes fonctions que le `hw` natif (ports, mémoire, interruptions, pages) sur une machine simulée ; `sim_reset`, `sim_map_ports`, `sim_map_mmio`, `sim_raise_irq`, `sim_raise_interrupt`, `sim_tick`, `sim_trace`, `sim_pic`... |
| `hw.sim_pci` | contrôleur hôte PCI (0xCF8 / 0xCFC et ECAM), fonctions avec BAR dimensionnables, capacités (MSI, MSI-X, PM, PCIe), ponts, multifonction ; les BAR programmés branchent les modèles de périphériques |
| `hw.sim_apic` | APIC local (EOI, IPI vers soi, minuterie) et IO-APIC (table de redirection, démasquage des demandes en attente) |

## Pilotes et tests sous QEMU

| Paquet | Matériel | Vérifié sous QEMU par |
|---|---|---|
| `interrupt` | PIC 8259, PIT, APIC local, IO-APIC, MSI, exceptions | `k_interrupt` |
| `dma` | tampons contigus, zone basse et rebond, PRD, anneaux, 8237 | `k_dma` |
| `storage_driver` | IDE / ATA PIO (LBA48), AHCI (FIS, PRDT), NVMe (files admin / E/S, PRP), MBR / GPT, cache, file de requêtes | `k_storage` (trois disques à la fois) |
| `network_driver` | Intel e1000 (anneaux RX / TX), ARP, IPv4, ICMP, UDP | `k_network` (passerelle simulée par `tests/drivers/kernel/netpeer.py` via `-netdev dgram`) |
| `usb_driver` | UHCI, énumération, clavier HID (frappes envoyées par le moniteur QEMU), stockage de masse BOT / SCSI | `k_usb` |
| `gpu_driver` | carte Bochs / QEMU stdvga (DISPI), double tampon, 2D, VRAM | `k_gpu` |

`make test-drivers` : modules dans la machine simulée (pci 29, interruptions 41, dma 32, cadre 20,
stockage 23, réseau 23, gpu 18 vérifications). `make test-drivers-kernel` : les six noyaux de
`tests/drivers/kernel` sous QEMU, sortie série comparée à `k_*_expected.txt` (options de QEMU dans
`k_*_qemu.txt`, disques préparés par `k_*_disk.sh`, frappes dans `k_*_keys.txt`, pair réseau dans
`k_*_peer.txt`).

Limites actuelles : pas d'OHCI / EHCI / xHCI ni de concentrateurs USB externes, pas de virtio-net, pas de
2D matérielle (le moteur de commandes 2D est logiciel), interruptions des cartes non utilisées par les
pilotes de stockage et de réseau (scrutation).

## Paquet `hw`

### `hw`

```text
Dans un noyau compilé avec `alexc build --native --freestanding`, `use hw` donne l'accès direct au matériel
(ports d'entrée-sortie, mémoire physique, interruptions, instructions privilégiées : docs/NATIVE.md). Ce
fichier-ci est la version de la VM (`alexc run`) : une MACHINE SIMULÉE qui offre les mêmes fonctions, avec la
même sémantique, au-dessus d'une RAM simulée et de modèles de périphériques écrits en Alex. Les pilotes (pci,
interrupt, dma, storage_driver...) s'exécutent ainsi sans QEMU, et se testent dans la VM.

  use hw
  hw.sim_reset(64 * 1024 * 1024)              # RAM simulée neuve (64 Mio), tas à partir de 16 Mio
  hw.sim_map_ports(0x1F0, 8, mon_disque)      # modèle : io_read(port, taille) / io_write(port, taille, valeur)
  hw.sim_map_mmio(0xFEBC0000, 0x20000, nic)   # modèle : mem_read(décalage, taille) / mem_write(...)
  hw.on_interrupt(33, gestionnaire)
  hw.pic_init()
  hw.irq_enable(1)
  hw.sti()
  hw.sim_raise_irq(1)                         # le gestionnaire du vecteur 33 s'exécute

Fidélité :
  - ports non attribués : lecture 0xFF / 0xFFFF / 0xFFFFFFFF (bus flottant), écriture ignorée ;
  - mémoire : petit-boutiste ; accès hors de la RAM simulée et hors des zones MMIO déclarées : MemoryError ;
  - hw.mmio(phys) renvoie la même adresse que dans un vrai noyau (fenêtre à 512 Gio) ;
  - interruptions : drapeau IF (cli / sti / disable_saved / restore), PIC 8259 maître/esclave simulé sur les
    ports 0x20-0x21 / 0xA0-0xA1 (ICW1-4, masques, EOI, IRR / ISR lisibles), minuterie PIT (0x40-0x43) qui
    tique quand le temps simulé avance (sim_tick, wait) ;
  - un seul cœur ; pas de mode utilisateur ni d'assembleur en ligne (HardwareError).

Erreurs : MemoryError (adresse invalide), HardwareError (fonction indisponible dans la simulation),
ArgumentError.
```

API publique :

- `sim_reset(ram_bytes=67108864, heap_start=16777216)`
- `sim_map_ports(start, count, model)`
- `sim_map_mmio(phys, size, model)`
- `sim_unmap(model)`
- `sim_trace(enabled=true)`
- `sim_trace_log()`
- `sim_time()`
- `sim_interrupts_enabled()`
- `sim_pic()`
- `sim_timer_hz()`
- `sim_pages_allocated()`
- `sim_raise_interrupt(vector, code=0)`
- `sim_raise_irq(irq)`
- `on_interrupt(vector, handler)`
- `pic_init()`
- `irq_enable(irq)`
- `irq_disable(irq)`
- `eoi(irq)`
- `timer_start(hz)`
- `sim_tick(n=1)`
- `wait()`
- `disable_saved()`
- `restore(state)`
- `enable()`
- `disable()`
- `cli()`
- `sti()`
- `hlt()`
- `pause()`
- `outb(port, value)`
- `outw(port, value)`
- `outl(port, value)`
- `inb(port)`
- `inw(port)`
- `inl(port)`
- `mmio(phys)`
- `peek8(addr)`
- `peek16(addr)`
- `peek32(addr)`
- `peek64(addr)`
- `poke8(addr, value)`
- `poke16(addr, value)`
- `poke32(addr, value)`
- `poke64(addr, value)`
- `alloc_pages(n)`
- `free_pages(addr, n)`
- `copy(dst, src, n)`
- `zero(addr, n)`
- `string_at(addr, n)`
- `store_string(s, addr)`
- `byte_addr(s)`
- `byte_size(s)`
- `memory_end()`
- `cas(addr, expected, new)`
- `atomic_add(addr, v)`
- `spin_lock(addr)`
- `spin_unlock(addr)`
- `cpu_id()`
- `cpus()`
- `cpu_block()`
- `from_user()`
- `smp_prepare(index, idle)`
- `cpu_online(block)`
- `rdmsr(msr)`
- `wrmsr(msr, value)`
- `cr2()`
- `cr3()`
- `invlpg(addr)`
- `flush_tlb()`
- `kernel_space()`
- `set_space(pml4)`
- `on_syscall(handler)`
- `enter_user(rip, rsp)`
- `leave_user(code)`
- `console_write(s)`
- `exit(code)`
- `asm(code)`
- `asm_value(code)`

### `hw.sim_apic`

```text
APIC local (0xFEE00000) et IO-APIC (0xFEC00000) simulés pour la machine de `hw`, afin d'exécuter dans la VM
les pilotes de interrupt.interrupt_controller (LocalApic, IoApic) :
  - APIC local : registres lisibles / inscriptibles, identifiant, version (6 entrées LVT), SVR, TPR, EOI
    (compté ; efface le bit en service le plus prioritaire), ICR (interruption vers soi-même ou vers l'APIC
    0 : délivrée par hw.sim_raise_interrupt), minuterie (compte décrémenté par sim_tick_timer, périodique ou
    unique, vecteur de la LVT) ;
  - IO-APIC : REGSEL / WINDOW, identifiant, version (24 entrées), table de redirection ; raise_gsi(n) délivre
    le vecteur programmé si l'entrée n'est pas masquée (sinon la demande est gardée pour le démasquage en
    déclenchement par niveau).

  use hw.sim_apic as sa
  lapic, ioapic := ...
  apic := sa.install()          # [lapic, ioapic]
  apic[1].raise_gsi(2)
  apic[0].tick(1000)            # minuterie
```

API publique :

- class `SimLocalApic(apic_id=0)` : `mem_read(offset, size)`, `mem_write(offset, size, value)`, `deliver(vector)`, `tick(n=1)`
- class `SimIoApic(apic_id=0, entries=24)` : `mem_read(offset, size)`, `mem_write(offset, size, value)`, `raise_gsi(n)`
- `install(lapic_phys=0xFEE00000, ioapic_phys=0xFEC00000)`

### `hw.sim_pci`

```text
Bus PCI simulé pour la machine de `hw` : un contrôleur hôte qui répond au mécanisme n° 1 (ports 0xCF8 /
0xCFC..0xCFF) et, si on le demande, à l'ECAM PCI Express (fenêtre MMIO de 256 Mio au plus), avec des fonctions
dont l'espace de configuration se comporte comme le vrai :
  - identifiants, classe, révision, en-tête en lecture seule ;
  - registre de commande inscriptible (bits IO, MEMORY, BUS_MASTER, INTX_DISABLE...), état « écrire 1 efface » ;
  - registres de base (BAR) qui renvoient leur masque de taille après une écriture de 0xFFFFFFFF (mémoire 32 /
    64 bits, préchargeable, ou ports), puis l'adresse attribuée ;
  - liste chaînée de capacités (MSI 32 / 64 bits, MSI-X, gestion d'énergie, PCI Express, propre au fabricant) ;
  - ponts PCI-PCI (en-tête de type 1) avec bus primaire / secondaire / subordonné ;
  - fonctions multiples (bit 7 du type d'en-tête mis automatiquement sur la fonction 0).
Chaque fonction peut porter un modèle de périphérique : quand le pilote programme un BAR et active le décodage
(commande IO / MEMORY), la zone est branchée sur la machine (hw.sim_map_ports / hw.sim_map_mmio) et les accès
vont aux méthodes io_read / io_write / mem_read / mem_write du modèle, avec (numéro de BAR, décalage).

  use hw
  use hw.sim_pci as sp
  hw.sim_reset()
  host := sp.install()                                      # ports 0xCF8..0xCFF
  nic := sp.SimPciFunction(0x8086, 0x100E, 0x02, 0x00)      # e1000
  nic.set_bar(0, 0x20000, "mem32")
  nic.set_bar(1, 64, "io")
  nic.set_interrupt(1, 11)
  nic.add_msi(true)
  host.attach(0, 3, 0, nic)
  # le pilote voit alors 00:03.0 avec pci.pci_bus.PciBus(pci.pci_config.PortConfig())

Erreurs : ArgumentError (emplacement occupé, BAR invalide).
```

API publique :

- class `SimPciFunction(vendor, device, cls, subclass, prog_if=0, revision=1, header_type=0)` : `vendor()`, `command()`, `header_kind()`, `set_bar(n, size, kind="mem32", prefetch=false, base=0)`, `bar_address(n)`, `set_interrupt(pin, line=0)`, `set_subsystem(vendor, device)`, `add_capability(cap_id, body, writable=true)`, `add_msi(is64=true, vectors_log2=0)`, `add_power_management()`, `add_pcie(port_type=0)`, `add_msix(table_size, table_bar, table_offset, pba_bar, pba_offset)`, `add_vendor_capability(data)`, `msi_state()`, `attach_model(model)`, `read32(offset)`, `write32(offset, value)`
- `bridge(vendor=0x8086, device=0x244E)`
- class `SimPciHost()` : `attach(bus, dev, fn, f)`, `detach(bus, dev, fn)`, `at(bus, dev, fn)`, `read(bus, dev, fn, offset)`, `write(bus, dev, fn, offset, value)`, `io_read(port, size)`, `io_write(port, size, value)`, `mem_read(offset, size)`, `mem_write(offset, size, value)`
- `install(ecam_base=null, buses=8, host_bridge=true)`

## Paquet `pci`

### `pci`

```text
Bus PCI / PCI Express : énumérer les périphériques, lire leurs identifiants, classes, registres de base (BAR),
capacités, et (avec les droits, ou dans un noyau) régler leur registre de commande.

Trois façons d'atteindre l'espace de configuration (pci.pci_config.ConfigAccess) :
  - SysfsConfig (ici) : sous Linux, les fichiers /sys/bus/pci/devices/*/config — sans privilège pour les 64
    premiers octets (tout l'en-tête utile), en entier (256 / 4096 octets) pour root ;
  - PortConfig : ports 0xCF8 / 0xCFC, dans un noyau Alex (--freestanding) ou dans la machine simulée (VM) ;
  - EcamConfig : MMIO PCI Express (table ACPI MCFG), dans un noyau.
Les mêmes PciDevice / PciBus servent dans les trois cas.

  use pci
  for d in pci.devices():                    # système hôte (Linux)
      print(d.describe())                    # 00:02.0 Contrôleur VGA [0300]: Intel ... [8086:3e9b] (rev 02)
  print(pci.lspci())                         # tout, comme la commande lspci
  gpu := pci.find_class(0x03, 0x00)

Dans un noyau (sous-ensemble natif) : utiliser directement pci.pci_bus.PciBus(pci.pci_config.PortConfig()) —
ce module-ci lit /sys et n'est pas compilable avec --freestanding.

Erreurs : HardwareError (hors Linux pour devices / lspci), IoError.
```

API publique :

- class `SysfsConfig()` : `read32(bus, dev, fn, offset)`, `write32(bus, dev, fn, offset, value)`, `available()`
- `supported()`
- `refresh()`
- `devices()`
- `find(vendor, device)`
- `find_class(cls, subclass, prog_if=-1)`
- `driver_of(d)`
- `lspci(verbose=false)`
- `vendor_name(v)`
- `class_name(cls, subclass, prog_if=0)`

### `pci.pci_bus` (natif)

```text
Énumération du bus PCI : toutes les fonctions présentes, en descendant derrière les ponts PCI-PCI (bus
secondaires), plusieurs bus hôtes compris ; recherche par identifiants ou par classe ; arborescence.

  use pci.pci_config as cfg
  use pci.pci_bus as bus
  b := bus.PciBus(cfg.PortConfig())
  devs := b.scan()
  for d in devs:
      print(d.describe())
  nic := b.find(0x8086, 0x100E)                 # PciDevice? (null : absent)
  disques := b.find_class(0x01, 0x06)           # contrôleurs SATA
  print(b.tree())

Module du sous-ensemble natif (noyau --freestanding ou VM).
```

API publique :

- class `PciBus(config: ConfigAccess)` : `scan()`, `rescan()`, `find(vendor: int, device: int)`, `find_class(cls: int, subclass: int, prog_if: int = 256)`, `find_vendor(vendor: int)`, `at(bus: int, slot: int, fn: int)`, `count()`, `tree()`
- `len_of(xs: list[PciDevice])`
- `scan(config: ConfigAccess)`

### `pci.pci_config` (natif)

```text
Espace de configuration PCI : l'accès aux registres de configuration de chaque fonction (bus, emplacement,
fonction, décalage), derrière une interface commune ConfigAccess, et les constantes des registres.

  PortConfig    mécanisme n° 1 des PC (ports 0xCF8 / 0xCFC) : 256 octets par fonction, tous les PC et QEMU ;
  EcamConfig    PCI Express « ECAM » (MMIO, 4096 octets par fonction) : adresse de base donnée par la table
                ACPI MCFG (QEMU q35 : 0xB0000000) ;
  (pci.pci : SysfsConfig, l'espace de configuration lu dans /sys sous Linux, sans privilège pour 64 octets.)

  use pci.pci_config as cfg
  c := cfg.PortConfig()
  v := c.read32(0, 3, 0, cfg.VENDOR_ID)          # (device << 16) | vendor
  print(cfg.read16(c, 0, 3, 0, cfg.COMMAND))

Module du sous-ensemble natif, à utiliser avec --freestanding (noyau) ou dans la VM (machine simulée de hw).
```

API publique :

- interface `ConfigAccess` : `read32(bus: int, dev: int, fn: int, offset: int)`, `write32(bus: int, dev: int, fn: int, offset: int, value: int)`
- class `PortConfig()` : `read32(bus: int, dev: int, fn: int, offset: int)`, `write32(bus: int, dev: int, fn: int, offset: int, value: int)`
- class `EcamConfig(base: int, start_bus: int, end_bus: int)` : `read32(bus: int, dev: int, fn: int, offset: int)`, `write32(bus: int, dev: int, fn: int, offset: int, value: int)`
- `read16(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int)`
- `read8(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int)`
- `write16(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int, value: int)`
- `write8(c: ConfigAccess, bus: int, dev: int, fn: int, offset: int, value: int)`
- `present(c: ConfigAccess, bus: int, dev: int, fn: int)`
- `port_mechanism_present()`

### `pci.pci_device` (natif)

```text
PciDevice : une fonction PCI identifiée (bus, emplacement, fonction) — identifiants, classe, en-tête, ligne
d'interruption — avec ses registres de base (BAR : ports ou mémoire, adresse, TAILLE mesurée, 64 bits,
préchargeable), sa liste de capacités (MSI, MSI-X, PCI Express, gestion d'énergie...) et les réglages du
registre de commande (décodage des ports / de la mémoire, maîtrise du bus pour le DMA, INTx).

  use pci.pci_device as pd
  d := pd.read_device(cfg, 0, 3, 0)            # null si l'emplacement est vide
  print(d.location(), d.name(), d.class_name())  # 00:03.0 82540EM Gigabit Ethernet ... Ethernet
  for b in d.bars():
      print(b.describe())                        # BAR0 mémoire 0xfebc0000 (128 Kio)
  d.enable_memory()
  d.enable_bus_master()
  if d.find_capability(pci_config.CAP_MSI) != 0: ...

Module du sous-ensemble natif (noyau --freestanding ou VM).
```

API publique :

- class `Bar(index: int, is_io: bool, address: int, size: int, prefetchable: bool, is64: bool)` : `describe()`
- `size_text(n: int)`
- class `Capability(id: int, offset: int)` : `name()`
- `capability_name(id: int)`
- class `PciDevice(config: ConfigAccess, bus: int, slot: int, fn: int)` : `refresh()`, `read32(offset: int)`, `read16(offset: int)`, `read8(offset: int)`, `write32(offset: int, value: int)`, `write16(offset: int, value: int)`, `write8(offset: int, value: int)`, `header_kind()`, `is_multifunction()`, `is_bridge()`, `location()`, `id_text()`, `vendor_name()`, `name()`, `class_name()`, `class_code()`, `is_class(cls: int, subclass: int)`, `describe()`, `command()`, `set_command_bits(bits: int, on: bool)`, `enable_io()`, `enable_memory()`, `enable_bus_master()`, `disable_intx()`, `enable_intx()`, `enable()`, `status()`, `bar_count()`, `bar_address(n: int)`, `bars()`, `capabilities()`, `find_capability(id: int)`, `configure_msi(address: int, data: int)`, `bridge_buses()`
- `read_device(c: ConfigAccess, bus: int, slot: int, fn: int)`

### `pci.pci_ids` (natif)

```text
Noms des identifiants PCI : fabricants (vendor), périphériques connus (machines virtuelles QEMU / KVM /
VirtualBox / VMware, puces Intel, virtio...), et la table COMPLÈTE des classes, sous-classes et interfaces de
programmation (PCI Code and ID Assignment Specification). Aussi quelques fabricants USB.

  use pci.pci_ids as ids
  print(ids.vendor_name(0x8086))                 # Intel
  print(ids.device_name(0x8086, 0x100E))         # 82540EM Gigabit Ethernet (e1000)
  print(ids.class_name(0x01, 0x06, 0x01))        # SATA (AHCI 1.0)

Module du sous-ensemble natif : utilisable dans un noyau (--freestanding) comme dans la VM.
```

API publique :

- `vendor_name(vendor: int)`
- `device_name(vendor: int, device: int)`
- `known_device(vendor: int, device: int)`
- `base_class_name(cls: int)`
- `class_name(cls: int, subclass: int, prog_if: int)`
- `usb_vendor_name(vendor: int)`
- `hex8(v: int)`
- `hex16(v: int)`
- `hex32(v: int)`

## Paquet `interrupt`

### `interrupt` (natif)

```text
Gestion des interruptions d'un NOYAU (compilé avec --freestanding) ou de la machine simulée de la VM :
un InterruptManager relie un contrôleur (PIC 8259 ou IO-APIC) aux gestionnaires Alex, gère les lignes
partagées, les interruptions parasites, la fin d'interruption, les vecteurs MSI, les exceptions du
processeur, et tient des statistiques.

  use hw
  use interrupt
  use interrupt.interrupt_types as it
  m := interrupt.with_pic()                       # PIC remappé à 32..47, tout masqué
  m.on_simple(it.IRQ_TIMER, (irq) => tick())      # gestionnaire, ligne démasquée, EOI automatique
  m.on(it.IRQ_ATA_PRIMARY, (irq) => disque.interruption(), "ata")   # ligne partagée : -> bool
  v := m.allocate_msi((v) => carte.interruption(), "e1000")         # vecteur MSI (80..223)
  m.on_exception(it.PAGE_FAULT, (code) => defaut_de_page(code))
  hw.enable()
  ...
  print(m.report())

Le gestionnaire s'exécute interruptions masquées ; l'EOI est envoyée après lui. Pour une section critique :
interrupt.critical(fn) (masque, exécute, rétablit l'état précédent).

Modules : interrupt.interrupt_types (vecteurs, noms), interrupt.interrupt_controller (Pic8259, LocalApic,
IoApic), interrupt.interrupt_handler (InterruptHandler, HandlerChain, Deferred).
```

API publique :

- class `InterruptManager(controller: InterruptController)` : `setup()`, `use_lapic(l: LocalApic)`, `chain(irq: int)`, `register(irq: int, h: InterruptHandler)`, `on(irq: int, fn: func(int) -> bool, label: str)`, `on_simple(irq: int, fn: func(int))`, `unregister(irq: int, label: str)`, `mask(irq: int)`, `unmask(irq: int)`, `on_exception(vector: int, fn: func(int))`, `allocate_msi(fn: func(int), label: str)`, `on_vector(vector: int, fn: func(int))`, `count(irq: int)`, `vector_count(vector: int)`, `report()`
- `with_pic()`
- `with_ioapic(ioapic_phys: int)`
- `legacy_gsi(irq: int)`
- `critical(fn: func())`

### `interrupt.interrupt_controller` (natif)

```text
Contrôleurs d'interruptions x86 :
  - Pic8259 : les deux PIC 8259A en cascade (ports 0x20/0x21, 0xA0/0xA1), remappés aux vecteurs choisis,
    masques, fin d'interruption, registres IRR / ISR, détection des interruptions parasites (IRQ 7 / 15) ;
  - LocalApic : APIC local du processeur (MMIO 0xFEE00000, MSR 0x1B) : activation, identifiant, priorité,
    fin d'interruption, minuterie (périodique / unique), interruptions inter-processeurs ;
  - IoApic : IO-APIC (MMIO 0xFEC00000) : table de redirection (vecteur, destination, front / niveau,
    polarité, masque) pour chaque entrée globale (GSI).
Pic8259 et IoApic implémentent InterruptController (enable / disable / eoi / vector_of), ce qui permet à
interrupt.InterruptManager de fonctionner avec l'un ou l'autre.

  use interrupt.interrupt_controller as ic
  pic := ic.Pic8259(32, 40)
  pic.setup()                      # tout masqué
  pic.enable(1)                    # clavier -> vecteur 33
  ...
  pic.eoi(1)

  lapic := ic.LocalApic(0)         # 0 : adresse lue dans le MSR IA32_APIC_BASE
  lapic.setup()
  ioapic := ic.IoApic(0xFEC00000, 0, lapic)
  ic.Pic8259(32, 40).disable_all() # le PIC hérité se tait
  ioapic.route(2, 32, lapic.id(), false, false)   # PIT (GSI 2 sous QEMU / ACPI) -> vecteur 32

Compilable en natif (# alex: native) ; dans la VM, la machine simulée de hw fournit le PIC (et hw.sim_apic
l'APIC local et l'IO-APIC).
```

API publique :

- interface `InterruptController` : `name()`, `setup()`, `enable(irq: int)`, `disable(irq: int)`, `eoi(irq: int)`, `vector_of(irq: int)`, `lines()`, `spurious(irq: int)`
- class `Pic8259(master_base: int, slave_base: int)` : `name()`, `setup()`, `lines()`, `vector_of(irq: int)`, `enable(irq: int)`, `disable(irq: int)`, `disable_all()`, `mask()`, `set_mask(m: int)`, `eoi(irq: int)`, `irr()`, `isr()`, `spurious(irq: int)`
- class `LocalApic(phys: int)` : `read(reg: int)`, `write(reg: int, value: int)`, `setup()`, `enabled()`, `id()`, `version()`, `max_lvt()`, `set_priority(p: int)`, `eoi()`, `timer_start(vector: int, initial: int, divide: int, periodic: bool)`, `timer_stop()`, `timer_current()`, `send_ipi(dest: int, vector: int)`, `send_self(vector: int)`, `ipi_pending()`, `error_status()`, `in_service(vector: int)`
- class `IoApic(phys: int, gsi_base: int, lapic: LocalApic)` : `name()`, `read(reg: int)`, `write(reg: int, value: int)`, `id()`, `version()`, `setup()`, `lines()`, `entry(n: int)`, `set_entry(n: int, low: int, dest: int)`, `route(gsi: int, vector: int, dest: int, level: bool, active_low: bool)`, `vector_of(irq: int)`, `enable(irq: int)`, `disable(irq: int)`, `masked(irq: int)`, `eoi(irq: int)`, `spurious(irq: int)`
- `has_apic()`

### `interrupt.interrupt_handler` (natif)

```text
Gestionnaires d'interruption :
  - InterruptHandler (interface) : handle(irq) -> bool, vrai si LE périphérique du gestionnaire a levé
    l'interruption (lignes partagées : PCI INTx, IO-APIC en niveau) ;
  - FunctionHandler : une fonction Alex comme gestionnaire ;
  - HandlerChain : les gestionnaires d'une même ligne, appelés à tour de rôle, avec compteurs (traitées,
    non revendiquées) ;
  - Deferred : travail différé (« moitié basse ») : le gestionnaire note la ligne dans un anneau sans allouer,
    une tâche ou la boucle principale traite ensuite (drain), interruptions de nouveau permises.

  use interrupt.interrupt_handler as ih
  h := ih.FunctionHandler("clavier", (irq) => clavier.lire_octet())
  chain := ih.HandlerChain(1, 33)
  chain.add(h)
  chain.dispatch(1)

Un gestionnaire s'exécute interruptions masquées : il doit être court (lire un registre, acquitter le
périphérique, noter le travail) ; le reste se fait hors interruption (Deferred).

Compilable en natif (# alex: native).
```

API publique :

- interface `InterruptHandler` : `handle(irq: int)`, `name()`
- class `FunctionHandler(label: str, fn: func(int) -> bool)` : `handle(irq: int)`, `name()`
- class `SimpleHandler(label: str, fn: func(int))` : `handle(irq: int)`, `name()`
- class `HandlerChain(irq: int, vector: int)` : `add(h: InterruptHandler)`, `remove(label: str)`, `size()`, `names()`, `dispatch(irq: int)`, `describe()`
- class `Deferred(capacity: int)` : `pending()`, `post(n: int)`, `take()`, `drain(fn: func(int))`

### `interrupt.interrupt_types` (natif)

```text
Vocabulaire des interruptions x86-64 : vecteurs des exceptions du processeur (0..31) et leurs noms, lignes
d'interruption (IRQ) héritées du PC, vecteurs choisis par la bibliothèque (PIC remappé à 32, APIC, MSI,
inter-processeurs, parasite), modes de déclenchement.

  use interrupt.interrupt_types as it
  print(it.exception_name(14))                  # « défaut de page (#PF) »
  v := it.irq_vector(it.IRQ_KEYBOARD)           # 33
  print(it.kind_of(v))                          # « irq »

Module compilable en natif (# alex: native) : utilisable dans un noyau (--freestanding) comme dans la VM.
```

API publique :

- `is_exception(vector: int)`
- `has_error_code(vector: int)`
- `exception_name(vector: int)`
- `irq_name(irq: int)`
- `irq_vector(irq: int)`
- `vector_irq(vector: int)`
- `kind_of(vector: int)`
- `describe(vector: int)`
- `msi_message(vector: int, apic_id: int, level: bool)`

## Paquet `dma`

### `dma` (natif)

```text
Accès direct à la mémoire pour les pilotes (noyau --freestanding, ou machine simulée de la VM) :

| Module               | Contenu                                                                       |
|----------------------|-------------------------------------------------------------------------------|
| dma.dma_buffer       | DmaBuffer : mémoire physiquement contiguë, alignée, lue / écrite par octets…  |
| dma.dma_mapping      | DmaMapping (masque d'adressage, tampon de rebond, synchronisation),           |
|                      | ScatterList (segments, tables PRD), DmaPool (descripteurs), DmaRing (anneaux) |
| dma.dma_transfer     | Transfer, DmaEngine, MemcpyEngine (logiciel), Isa8237 (contrôleur ISA)        |

  use dma
  b := dma.alloc(4096)                         # tampon contigu
  r := dma.ring(256, 16, 128)                  # 256 descripteurs de 16 octets, alignés sur 128
  sg := dma.scatter(65536, 65536)              # segments de 64 Kio max., sans traverser 64 Kio
  sg.add_buffer(b)
  mp := dma.map(adresse, 512, dma.FROM_DEVICE, dma.MASK_32)

Compilable en natif (# alex: native).
```

API publique :

- `alloc(size: int)`
- `alloc_aligned(size: int, align: int)`
- `low_zone(start: int, size: int)`
- `alloc_below(size: int, mask: int)`
- `map(addr: int, length: int, direction: int, mask: int)`
- `scatter(max_segment: int, boundary: int)`
- `pool(block: int)`
- `ring(count: int, desc_size: int, align: int)`
- `engine()`
- `copy(dst: int, src: int, n: int)`

### `dma.dma_buffer` (natif)

```text
Tampon DMA : mémoire PHYSIQUEMENT CONTIGUË, alignée sur la page, mise à zéro, qu'un périphérique peut lire ou
écrire par accès direct (bus master). Dans le noyau Alex, le premier Gio est en identité : l'adresse vue par
le processeur (addr) est aussi l'adresse physique (phys) donnée au périphérique. Dans la VM, les pages
viennent de la RAM simulée de hw.

  use dma.dma_buffer as db
  b := db.DmaBuffer(8192, 4096)
  b.write32(0, 0xCAFE)
  carte.programmer(b.phys, b.size)
  ...
  s := b.read_str(0, 512)          # octets reçus (str)
  b.free()

Erreurs : MemoryError (accès hors du tampon, tampon libéré), ArgumentError.

Compilable en natif (# alex: native).
```

API publique :

- `low_zone(start: int, size: int)`
- `low_zone_free()`
- `pages_for(size: int)`
- class `DmaBuffer(size: int, align: int)` : `read8(offset: int)`, `read16(offset: int)`, `read32(offset: int)`, `read64(offset: int)`, `write8(offset: int, v: int)`, `write16(offset: int, v: int)`, `write32(offset: int, v: int)`, `write64(offset: int, v: int)`, `read_str(offset: int, n: int)`, `write_str(offset: int, s: str)`, `fill(offset: int, n: int, value: int)`, `zero()`, `copy_from(offset: int, src: int, n: int)`, `copy_to(dst: int, offset: int, n: int)`, `fits(mask: int)`, `crosses(boundary: int)`, `free()`, `describe()`
- `alloc_below(size: int, align: int, mask: int)`
- `alloc(size: int)`
- `alloc_aligned(size: int, align: int)`

### `dma.dma_mapping` (natif)

```text
Rendre une zone de mémoire accessible à un périphérique, avec ses contraintes :
  - DmaMapping : une zone (adresse, longueur, sens) vue par le périphérique ; si elle dépasse son masque
    d'adressage (ex. 32 bits, 24 bits pour l'ISA) ou traverse une frontière interdite, elle passe par un
    tampon de rebond (bounce buffer) : sync_for_device copie vers lui avant le transfert, sync_for_cpu
    recopie après (selon le sens) ;
  - ScatterList : liste de segments [adresse physique, longueur] découpés selon la taille maximale d'un
    segment et les frontières (tables PRD d'ATA, PRDT d'AHCI, listes PRP de NVMe) ;
  - DmaPool : petits blocs de taille fixe alignés (descripteurs), pris dans des pages DMA ;
  - DmaRing : anneau de descripteurs (cartes réseau, files NVMe, xHCI) : indices de tête / queue, adresse de
    chaque descripteur.

  use dma.dma_mapping as dm
  mp := dm.map_region(tampon, 4096, dm.TO_DEVICE, dm.MASK_32)
  mp.sync_for_device()
  carte.envoyer(mp.device_addr, mp.length)
  mp.unmap()

Compilable en natif (# alex: native).
```

API publique :

- `direction_name(d: int)`
- class `DmaMapping(cpu_addr: int, length: int, direction: int, mask: int, boundary: int)` : `bounced()`, `sync_for_device()`, `sync_for_cpu()`, `unmap()`, `describe()`
- `map_region(cpu_addr: int, length: int, direction: int, mask: int)`
- `map_region_bounded(cpu_addr: int, length: int, direction: int, mask: int, boundary: int)`
- `map_buffer(b: DmaBuffer, direction: int, mask: int)`
- class `Segment(addr: int, length: int)`
- class `ScatterList(max_segment: int, boundary: int)` : `add(addr: int, length: int)`, `add_buffer(b: DmaBuffer)`, `count()`, `total()`, `write_prd(addr: int)`
- class `DmaPool(block: int)` : `alloc()`, `release(addr: int)`, `destroy()`
- class `DmaRing(count: int, desc_size: int, align: int)` : `phys()`, `bytes()`, `desc(i: int)`, `full()`, `empty()`, `space()`, `produce()`, `consume()`, `free()`

### `dma.dma_transfer` (natif)

```text
Transferts DMA :
  - Transfer : une opération (source, destination, longueur, sens), son état (pending, running, done, error),
    sa progression et sa fonction de fin ;
  - DmaEngine (interface) : submit(t), poll() -> transferts terminés, idle() ; un pilote de périphérique
    bus master (AHCI, NVMe, carte réseau) peut l'implémenter pour son propre moteur ;
  - MemcpyEngine : moteur logiciel (copie mémoire par morceaux), utile pour tester les pilotes et comme
    solution de repli ;
  - Isa8237 : contrôleur DMA du PC (8237A, canaux 0..3 en 8 bits, 5..7 en 16 bits) : programmation de
    l'adresse, du compte, de la page, du mode (lecture / écriture, unique / bloc, auto-initialisation),
    masques et état (fin de compte). Sert à la disquette, au Sound Blaster, au port parallèle ECP.

  use dma.dma_transfer as dt
  e := dt.MemcpyEngine(4096)
  t := dt.Transfer(src, dst, 65536, dt.MEM_TO_MEM)
  e.submit(t)
  while not t.finished():
      e.poll()

  isa := dt.Isa8237()
  isa.setup(2, tampon.phys, 512, dt.ISA_WRITE, false)   # disquette : canal 2, le périphérique écrit en mémoire
  isa.enable(2)

Compilable en natif (# alex: native).
```

API publique :

- `state_name(s: int)`
- class `Transfer(source: int, dest: int, length: int, direction: int)` : `then(fn: func(Transfer))`, `finished()`, `progress()`, `complete(ok: bool, error: str)`, `describe()`
- interface `DmaEngine` : `name()`, `submit(t: Transfer)`, `poll()`, `idle()`
- class `MemcpyEngine(chunk: int)` : `name()`, `submit(t: Transfer)`, `poll()`, `idle()`, `run_all()`
- class `Isa8237()` : `disable(ch: int)`, `enable(ch: int)`, `setup(ch: int, phys: int, length: int, direction: int, auto_init: bool)`, `remaining(ch: int)`, `terminal_counts(high: bool)`, `mode_of(ch: int)`

## Paquet `driver`

### `driver` (natif)

```text
Modèle de pilote de périphérique, commun au noyau Alex (--freestanding) et à la machine simulée de la VM :

  interface Driver
      info() -> DriverInfo          nom, version, bus, table des périphériques reconnus
      probe(dev) -> bool            « est-ce bien le mien ? » (lecture de registres, sans rien changer)
      attach(dev)                   prise en main : réinitialisation, interruptions, files (erreur : échec)
      detach(dev)                   arrêt propre
      status(dev) -> str            état lisible

Les autres modules : driver.driver_info (DriverInfo, DeviceId, HwDevice, Resource), driver.device_binding
(Binding), driver.driver_registry (DriverRegistry), driver.driver_manager (DriverManager : énumère, choisit le
meilleur pilote, lie, journalise), driver.driver_errors (erreurs, attentes bornées).

  from driver use Driver
  use driver.driver_info as di
  use driver.driver_manager as dmg
  class MonPilote implements Driver:
      ...
  m := dmg.DriverManager()
  m.register(MonPilote())
  m.add_pci_bus(pci.pci_bus.PciBus(pci.pci_config.PortConfig()))
  m.bind_all()
  print(m.report())

Pilotes fournis : storage_driver (ATA, AHCI, NVMe), network_driver (e1000), usb_driver (UHCI, HID),
gpu_driver (Bochs / QEMU BGA).

Compilable en natif (# alex: native).
```

API publique :

- interface `Driver` : `info()`, `probe(dev: HwDevice)`, `attach(dev: HwDevice)`, `detach(dev: HwDevice)`, `status(dev: HwDevice)`

### `driver.device_binding` (natif)

```text
Lien entre un périphérique (driver_info.HwDevice) et le pilote qui le gère : état (lié, échec, détaché),
erreur éventuelle, nombre de tentatives. Le DriverManager crée les liens ; un pilote peut retrouver le sien.

  b := Binding(pilote, dev)
  b.bind()                    # probe puis attach ; capture l'erreur
  print(b.describe())         # « pci 00:03.0 Intel 82540EM -> e1000 : lié »
  b.unbind()

Compilable en natif (# alex: native).
```

API publique :

- `state_name(s: int)`
- class `Binding(driver: Driver, device: HwDevice)` : `driver_name()`, `bind()`, `unbind()`, `bound()`, `status()`, `describe()`

### `driver.driver_errors` (natif)

```text
Erreurs des pilotes de périphériques et attente bornée du matériel.

| Type d'erreur        | Quand                                                              |
|----------------------|--------------------------------------------------------------------|
| DriverError          | erreur générale du pilote                                          |
| DeviceNotFound       | le périphérique attendu ne répond pas / est absent                 |
| DeviceTimeout        | le périphérique n'a pas répondu à temps                            |
| DeviceBusy           | ressource déjà utilisée (pilote déjà lié, file pleine)             |
| UnsupportedDevice    | modèle, révision ou mode non pris en charge                        |
| DeviceIoError        | erreur signalée par le matériel (registre d'état, code d'erreur)   |

  use driver.driver_errors as de
  if not de.wait_until(() => hw.inb(STATUS) & BSY == 0, 100000):
      de.timeout("ata", "BSY ne retombe pas")
  try:
      ...
  catch e:
      if de.is_driver_error(e.type):
          ...

Compilable en natif (# alex: native).
```

API publique :

- `is_driver_error(kind: str)`
- `fail(driver: str, message: str)`
- `not_found(driver: str, what: str)`
- `timeout(driver: str, what: str)`
- `busy(driver: str, what: str)`
- `unsupported(driver: str, what: str)`
- `io_error(driver: str, what: str, status: int)`
- `wait_until(cond: func() -> bool, tries: int)`
- `wait_port(port: int, mask: int, value: int, tries: int)`
- `wait_mmio32(addr: int, mask: int, value: int, tries: int)`
- `io_delay(us: int)`

### `driver.driver_info` (natif)

```text
Ce qu'un pilote déclare et ce qu'il pilote :
  - DriverInfo : nom, version, auteur, description, bus ("pci", "usb", "isa", "platform", "virtual") et table
    des périphériques reconnus (DeviceId) ;
  - DeviceId : motif de correspondance (fabricant, modèle, classe, sous-classe, interface ; -1 = indifférent,
    ou un nom pour les périphériques de plate-forme / ISA) ;
  - HwDevice : un périphérique concret présenté aux pilotes : bus, emplacement, identifiants, classe, ligne
    d'interruption, ressources (ports, zones MMIO), et, pour PCI, son pci.pci_device.PciDevice.

  use driver.driver_info as di
  info := di.DriverInfo("e1000", "1.0", "réseau Intel PRO/1000", "pci")
  info.add_id(di.pci_id(0x8086, 0x100E))
  info.add_id(di.pci_class(0x02, 0x00))
  score := info.matches(dev)            # 0 : non ; plus grand = plus précis

Compilable en natif (# alex: native).
```

API publique :

- class `DeviceId(vendor: int, device: int, cls: int, subclass: int, prog_if: int, name: str)` : `score(dev: HwDevice)`, `describe()`
- `pci_id(vendor: int, device: int)`
- `pci_class(cls: int, subclass: int)`
- `pci_class_if(cls: int, subclass: int, prog_if: int)`
- `vendor_any(vendor: int)`
- `named(name: str)`
- class `DriverInfo(name: str, version: str, description: str, bus: str)` : `add_id(d: DeviceId)`, `matches(dev: HwDevice)`, `describe()`
- class `Resource(kind: str, start: int, size: int)` : `describe()`
- class `HwDevice(bus: str, location: str, name: str)` : `add_resource(kind: str, start: int, size: int)`, `resource(kind: str, index: int)`, `io_base(index: int)`, `mem_base(index: int)`, `describe()`
- `from_pci(d: PciDevice)`
- `platform(name: str, io_start: int, io_size: int, irq: int)`

### `driver.driver_manager` (natif)

```text
Le gestionnaire de pilotes : il connaît les pilotes (DriverRegistry), les périphériques (énumération PCI,
périphériques de plate-forme / ISA déclarés), et les lie : pour chaque périphérique, les pilotes candidats
sont essayés du plus précis au moins précis (probe puis attach) jusqu'à ce que l'un le prenne. Un journal
garde ce qui s'est passé ; un rappel prévient de chaque liaison.

  use driver.driver_manager as dmg
  m := dmg.DriverManager()
  m.register(Ata())
  m.add_pci_bus(PciBus(PortConfig()))
  m.add_device(di.platform("com1", 0x3F8, 8, 4))
  n := m.bind_all()
  print(m.report())
  d := m.driver_of("00:03.0")

Compilable en natif (# alex: native).
```

API publique :

- class `DriverManager()` : `register(d: Driver)`, `add_device(h: HwDevice)`, `add_pci_bus(bus: PciBus)`, `notify(f: func(Binding))`, `binding_of(h: HwDevice)`, `bind(h: HwDevice)`, `bind_all()`, `unbind(h: HwDevice)`, `unbind_all()`, `driver_of(location: str)`, `device(location: str)`, `bound_count()`, `unclaimed()`, `report()`

### `driver.driver_registry` (natif)

```text
Registre des pilotes disponibles : enregistrement, recherche par nom, choix du pilote le plus précis pour un
périphérique (score de DriverInfo.matches ; à égalité, le premier enregistré), liste des candidats.

  r := DriverRegistry()
  r.add(Ahci())
  r.add(AtaPio())
  d := r.best_for(dev)          # Driver?, celui dont l'identifiant correspond le mieux

Compilable en natif (# alex: native).
```

API publique :

- class `DriverRegistry()` : `add(d: Driver)`, `remove(name: str)`, `find(name: str)`, `count()`, `names()`, `candidates(dev: HwDevice)`, `best_for(dev: HwDevice)`, `describe()`

## Paquet `storage_driver`

### `storage_driver` (natif)

```text
Pilotes de stockage d'un noyau Alex (--freestanding) :

| Module                          | Contenu                                                           |
|---------------------------------|-------------------------------------------------------------------|
| storage_driver.block_device     | interface BlockDevice, RamDisk, Partition, BlockCache, accès octet |
| storage_driver.disk             | Disk : tables MBR / GPT, write_mbr                                 |
| storage_driver.ata              | IDE / ATA en PIO (LBA28 / LBA48), AtaDriver                        |
| storage_driver.ahci             | SATA AHCI (DMA, FIS, PRDT), AhciDriver                             |
| storage_driver.nvme             | NVMe (files admin / E/S, PRP), NvmeDriver                          |
| storage_driver.storage_queue    | file de requêtes : ascenseur, fusion, barrières                    |

  use storage_driver
  disques := storage_driver.discover()          # tous les disques des contrôleurs PCI reconnus
  for d in disques:
      print(block_device.describe(d))

Compilable en natif (# alex: native). Dans la VM, RamDisk, Partition, BlockCache, Disk et la file
fonctionnent sur la RAM simulée de hw.
```

API publique :

- class `StorageStack()` : `discover(bus: PciBus)`, `disks()`, `report()`
- `stack()`
- `discover()`

### `storage_driver.ahci` (natif)

```text
Pilote AHCI (SATA) : contrôleur PCI de classe 01:06 / interface 01, registres en MMIO (BAR5, « ABAR »).
  - initialisation du contrôleur (mode AHCI, interruptions coupées), ports implantés (PI), détection des
    disques présents (SSTS.DET = 3) et de leur type (signature : SATA, ATAPI, multiplicateur) ;
  - par port : liste de commandes (32 emplacements), zone des FIS reçus, tables de commande avec PRDT ;
  - commandes ATA par FIS hôte -> périphérique : IDENTIFY, READ / WRITE DMA EXT (LBA48), FLUSH CACHE EXT ;
  - fin de commande par scrutation de CI ; erreurs : IS.TFES et registre TFD.

  use storage_driver.ahci as ahci
  ctl := ahci.AhciController(hw.mmio(abar_phys))
  ctl.setup()
  for d in ctl.disks():           # AhciDisk (BlockDevice)
      d.read_blocks(0, 8, tampon)

  Pilote du cadre driver : AhciDriver (PCI 01:06:01).

Erreurs : DeviceTimeout, DeviceIoError. Compilable en natif (# alex: native).
```

API publique :

- `signature_name(sig: int)`
- class `AhciPort(abar: int, index: int)` : `read(reg: int)`, `write(reg: int, v: int)`, `present()`, `signature()`, `stop()`, `start()`, `command(cmd: int, lba: int, count: int, bytes: int, write: bool, who: str)`
- class `AhciDisk(port: AhciPort, label: str)` : `name()`, `block_size()`, `block_count()`, `read_only()`, `identify()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `describe()`
- class `AhciController(abar: int)` : `read(reg: int)`, `write(reg: int, v: int)`, `version()`, `port_count()`, `supports_64bit()`, `setup()`, `disks()`, `describe()`
- class `AhciDriver()` : `info()`, `probe(dev: HwDevice)`, `attach(dev: HwDevice)`, `detach(dev: HwDevice)`, `status(dev: HwDevice)`, `disks()`

### `storage_driver.ata` (natif)

```text
Pilote ATA / IDE en mode PIO : deux canaux (primaire 0x1F0 / 0x3F6, secondaire 0x170 / 0x376, ou les ports
des BAR d'un contrôleur PCI en mode natif), deux disques par canal (maître / esclave), IDENTIFY (modèle,
numéro de série, capacité, LBA48), lecture / écriture de secteurs en LBA28 ou LBA48, vidage du cache,
détection des lecteurs ATAPI (ignorés) et des canaux vides (bus flottant).

  use storage_driver.ata as ata
  disks := ata.probe_legacy()                  # list[AtaDisk] trouvés sur les deux canaux
  d := disks[0]
  print(d.model, d.block_count())
  d.read_blocks(0, 1, tampon)

  Pilote du cadre driver : AtaDriver (contrôleurs PCI de classe 01:01) ; après attach, disks() les donne.

Erreurs : DeviceTimeout, DeviceIoError (bit ERR du registre d'état). Compilable en natif (# alex: native).
```

API publique :

- class `AtaChannel(base: int, ctrl: int, irq: int)` : `status()`, `alt_status()`, `delay()`, `select(slave: int, lba_high: int)`, `wait_not_busy()`, `wait_data(who: str)`, `set_interrupts(enabled: bool)`, `software_reset()`
- class `AtaDisk(channel: AtaChannel, slave: int, label: str)` : `name()`, `block_size()`, `block_count()`, `read_only()`, `identify()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `describe()`
- `probe_channels(channels: list[AtaChannel])`
- `legacy_channels()`
- `probe_legacy()`
- class `AtaDriver()` : `info()`, `channels(dev: HwDevice)`, `probe(dev: HwDevice)`, `attach(dev: HwDevice)`, `detach(dev: HwDevice)`, `status(dev: HwDevice)`, `disks()`

### `storage_driver.block_device` (natif)

```text
Périphérique de blocs : l'interface commune des disques (ATA, AHCI, NVMe, virtio, disque en mémoire,
partition), utilisée par les systèmes de fichiers et storage_driver.storage_queue.

  interface BlockDevice
      name() -> str
      block_size() -> int                    512 en général (4096 pour certains NVMe)
      block_count() -> int
      read_blocks(lba, count, buf) -> bool   buf : adresse (mémoire du noyau / tampon DMA)
      write_blocks(lba, count, buf) -> bool
      flush() -> bool
      read_only() -> bool

Fournis ici : RamDisk (en mémoire), Partition (vue décalée d'un autre périphérique), BlockCache (cache de
blocs avec écriture différée), et les fonctions read_bytes / write_bytes (accès à l'octet au-dessus des blocs).

  d := RamDisk("ram0", 512, 2048)              # 1 Mio
  buf := hw.alloc_pages(1)
  d.write_blocks(10, 1, buf)
  p := Partition(d, 2048, 4096, "ram0p1")

Erreurs : DeviceIoError (hors du disque, lecture seule). Compilable en natif (# alex: native).
```

API publique :

- interface `BlockDevice` : `name()`, `block_size()`, `block_count()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `read_only()`
- `check_range(d: BlockDevice, lba: int, count: int)`
- `capacity(d: BlockDevice)`
- `size_text(n: int)`
- `describe(d: BlockDevice)`
- class `RamDisk(label: str, bsize: int, count: int)` : `name()`, `block_size()`, `block_count()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `read_only()`, `set_read_only(ro: bool)`, `free()`
- class `Partition(parent: BlockDevice, start: int, count: int, label: str)` : `name()`, `block_size()`, `block_count()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `read_only()`
- class `BlockCache(dev: BlockDevice, slots: int, write_back: bool)` : `name()`, `block_size()`, `block_count()`, `read_only()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `dirty_count()`
- `read_bytes(d: BlockDevice, offset: int, n: int, dst: int)`
- `write_bytes(d: BlockDevice, offset: int, n: int, src: int)`
- `read_string(d: BlockDevice, offset: int, n: int)`
- `write_string(d: BlockDevice, offset: int, s: str)`

### `storage_driver.disk` (natif)

```text
Un disque et ses partitions : lecture des tables de partitions MBR (DOS, 4 entrées principales) et GPT
(UEFI : en-tête en LBA 1, entrées de 128 octets, noms UTF-16), création d'une table MBR, identité du disque
(modèle, numéro de série, fournis par le pilote).

  use storage_driver.disk as dk
  d := dk.Disk(ata0)                 # tout BlockDevice
  for p in d.partitions():           # PartitionEntry
      print(p.describe())            # « 1 : FAT32 (LBA) début 2048, 204800 blocs »
  part := d.open(1)                  # block_device.Partition
  dk.write_mbr(ram, [[0x0C, 2048, 4096]], 0x1234ABCD)

Compilable en natif (# alex: native).
```

API publique :

- class `PartitionEntry(index: int, scheme: str, type_id: int, start: int, count: int)` : `kind()`, `describe()`
- `mbr_type_name(t: int)`
- `gpt_type_name(g: str)`
- `guid_at(addr: int)`
- class `Disk(dev: BlockDevice)` : `name()`, `partitions()`, `rescan()`, `open(index: int)`, `describe()`
- `chr_of(c: int)`
- `write_mbr(d: BlockDevice, parts: list[list[int]], disk_id: int)`

### `storage_driver.nvme` (natif)

```text
Pilote NVMe (PCI Express, classe 01:08 / interface 02), registres en MMIO (BAR0) :
  - réinitialisation et activation du contrôleur (CC / CSTS), file d'administration (AQA, ASQ, ACQ) ;
  - IDENTIFY du contrôleur (modèle, numéro de série, micrologiciel, nombre d'espaces de noms) et de chaque
    espace de noms (capacité, taille de bloc d'après le format LBA actif) ;
  - une paire de files d'entrées-sorties (soumission / complétion) créée par commandes d'administration ;
  - lecture / écriture / vidage avec PRP1, PRP2 et liste PRP (tampon de rebond de 64 Kio) ;
  - complétions par bit de phase, sonnettes (doorbells) avec leur pas (CAP.DSTRD).

  use storage_driver.nvme as nvme
  ctl := nvme.NvmeController(hw.mmio(bar0_phys))
  ctl.setup()
  ns := ctl.namespaces()[0]          # NvmeNamespace (BlockDevice)
  ns.read_blocks(0, 8, tampon)

  Pilote du cadre driver : NvmeDriver (PCI 01:08:02).

Erreurs : DeviceTimeout, DeviceIoError (état de complétion). Compilable en natif (# alex: native).
```

API publique :

- class `NvmeQueue(id: int, size: int, regs: int, stride: int)` : `submit(opcode: int, nsid: int, prp1: int, prp2: int, c10: int, c11: int, c12: int, who: str)`
- class `NvmeNamespace(ctl: NvmeController, nsid: int, label: str)` : `name()`, `block_size()`, `block_count()`, `read_only()`, `identify()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `describe()`
- class `NvmeController(regs: int)` : `version()`, `prp2_for(bytes: int)`, `setup()`, `namespaces()`, `shutdown()`, `describe()`
- class `NvmeDriver()` : `info()`, `probe(dev: HwDevice)`, `attach(dev: HwDevice)`, `detach(dev: HwDevice)`, `status(dev: HwDevice)`, `namespaces()`

### `storage_driver.storage_queue` (natif)

```text
File de requêtes d'un périphérique de blocs : les systèmes de fichiers et les applications déposent des
lectures / écritures / vidages ; la file les ordonne (ascenseur : par LBA croissant à partir de la position
courante de la tête, puis retour), FUSIONNE les requêtes contiguës de même sens dont les tampons se suivent,
les exécute sur le BlockDevice et appelle la fonction de fin de chacune. Un vidage (flush) est une barrière :
rien n'est réordonné par-dessus.

  use storage_driver.storage_queue as sq
  q := sq.StorageQueue(disque, 256)            # fusion jusqu'à 256 blocs
  r := q.read(100, 8, tampon)
  q.write(5000, 1, autre)
  q.flush()
  q.run()                                      # tout exécuter
  print(r.done, q.stats())

Compilable en natif (# alex: native).
```

API publique :

- `op_name(op: int)`
- class `Request(op: int, lba: int, count: int, buf: int)` : `then(fn: func(Request))`, `finish(ok: bool, error: str)`, `describe()`
- class `StorageQueue(dev: BlockDevice, max_merge: int)` : `submit(r: Request)`, `read(lba: int, count: int, buf: int)`, `write(lba: int, count: int, buf: int)`, `flush()`, `size()`, `process(max_ops: int)`, `run()`, `stats()`

## Paquet `network_driver`

### `network_driver` (natif)

```text
Pilotes réseau d'un noyau Alex (--freestanding), et le pilote Intel PRO/1000 (e1000 : 82540EM de QEMU,
82545EM, 82574L...) :
  - réinitialisation, adresse MAC (registres RAL/RAH ou EEPROM), lien (STATUS.LU), table de multidiffusion ;
  - anneaux de réception et d'émission (descripteurs de 16 octets, tampons de 2048 octets, DMA) ;
  - émission par copie dans le tampon du descripteur, fin d'émission par le bit DD ;
  - réception par scrutation des descripteurs (DD, EOP, erreurs), recyclage des tampons ;
  - interruptions (ICR / IMS) optionnelles, compteurs matériels (CRCERRS, MPC, GPRC, GPTC).

| Module                           | Contenu                                                       |
|----------------------------------|---------------------------------------------------------------|
| network_driver.ethernet          | adresses MAC, en-tête, EtherType, CRC-32                      |
| network_driver.network_buffer    | PacketBuffer (marges, push / pull), BufferPool                |
| network_driver.network_packet    | ARP, IPv4, ICMP, UDP : construction, analyse, sommes          |
| network_driver.network_device    | interface NetworkDevice, LoopbackDevice, NetInterface (IPv4)  |
| network_driver.network_stats     | compteurs                                                     |

  use network_driver
  carte := network_driver.find_e1000()             # E1000Device? (bus PCI, pilote lié)
  itf := NetInterface(carte, np.ip("10.0.2.15"), np.ip("10.0.2.2"))
  print(itf.ping(itf.gateway, 1, 1000000))

Erreurs : DeviceTimeout, DeviceNotFound. Compilable en natif (# alex: native).
```

API publique :

- class `E1000Device(regs: int, label: str)` : `read(reg: int)`, `write(reg: int, v: int)`, `setup()`, `name()`, `mac()`, `mtu()`, `link_up()`, `speed_mbps()`, `set_promiscuous(on: bool)`, `send(b: PacketBuffer)`, `flush_tx(tries: int)`, `receive()`, `recycle(b: PacketBuffer)`, `stats()`, `hardware_counters()`, `enable_interrupts(mask: int)`, `interrupt_causes()`, `describe()`
- class `E1000Driver()` : `info()`, `probe(dev: HwDevice)`, `attach(dev: HwDevice)`, `detach(dev: HwDevice)`, `status(dev: HwDevice)`
- `find_e1000()`

### `network_driver.ethernet` (natif)

```text
Couche Ethernet (IEEE 802.3) : adresses MAC (entier de 48 bits), en-tête de trame (destination, source,
type ou étiquette VLAN 802.1Q), types de protocole (EtherType), CRC-32 de la séquence de contrôle (FCS),
tailles minimale et maximale des trames.

  use network_driver.ethernet as eth
  m := eth.parse_mac("52:54:00:12:34:56")
  print(eth.mac_text(m), eth.is_multicast(m))
  eth.write_header(adresse, eth.BROADCAST, m, eth.TYPE_ARP)
  print(eth.crc32_at(adresse, 60))

Compilable en natif (# alex: native).
```

API publique :

- `type_name(t: int)`
- `mac_text(m: int)`
- `parse_mac(text: str)`
- `is_broadcast(m: int)`
- `is_multicast(m: int)`
- `is_local(m: int)`
- `read_mac(addr: int)`
- `write_mac(addr: int, m: int)`
- `read16be(addr: int)`
- `write16be(addr: int, v: int)`
- `read32be(addr: int)`
- `write32be(addr: int, v: int)`
- `write_header(addr: int, dst: int, src: int, ethertype: int)`
- `dst_of(addr: int)`
- `src_of(addr: int)`
- `type_of(addr: int)`
- `vlan_of(addr: int)`
- `header_size(addr: int)`
- `crc32_at(addr: int, n: int)`

### `network_driver.network_buffer` (natif)

```text
Tampons de paquets pour les pilotes réseau :
  - PacketBuffer : zone contiguë (adressable par la carte, DMA) avec une marge de tête (headroom) : on écrit
    la charge utile, puis on « pousse » les en-têtes devant (push) ; à la réception on les « retire » (pull).
    Lecture / écriture d'entiers gros-boutistes, d'octets, de chaînes, à une position relative aux données ;
  - BufferPool : réserve de tampons de taille fixe (2048 octets) pris dans des pages, réutilisés.

  use network_driver.network_buffer as nb
  pool := nb.BufferPool(64)
  b := pool.get()
  b.put_string("bonjour")                # charge utile
  h := b.push(8)                         # adresse de 8 octets d'en-tête devant
  ...
  pool.put(b)

Compilable en natif (# alex: native).
```

API publique :

- class `PacketBuffer(base: int, capacity: int)` : `reset()`, `reset_raw(length: int)`, `data()`, `headroom()`, `tailroom()`, `put(n: int)`, `push(n: int)`, `pull(n: int)`, `trim(n: int)`, `u8(offset: int)`, `u16(offset: int)`, `u32(offset: int)`, `set_u8(offset: int, v: int)`, `set_u16(offset: int, v: int)`, `set_u32(offset: int, v: int)`, `string(offset: int, n: int)`, `put_string(s: str)`, `pad_to(n: int)`, `copy_from(src: int, n: int)`
- class `BufferPool(limit: int)` : `get()`, `put(b: PacketBuffer)`, `available()`

### `network_driver.network_device` (natif)

```text
Interface réseau vue par la pile au-dessus du pilote :

  interface NetworkDevice
      name() -> str             « eth0 », « lo »
      mac() -> int              adresse MAC (48 bits)
      mtu() -> int
      link_up() -> bool
      send(b) -> bool           émet la trame du PacketBuffer (le pilote ne le garde pas : il copie ou attend)
      receive() -> PacketBuffer?  prochaine trame reçue (à rendre avec recycle), ou null
      recycle(b)                rend un tampon reçu
      stats() -> NetworkStats

Fournis ici : LoopbackDevice (« lo » : ce qui est émis est reçu), et NetInterface : interface + adresse IPv4,
table ARP, réponse automatique aux requêtes ARP et aux échos ICMP (ping), envoi UDP, attente d'un paquet.

  lo := LoopbackDevice(pool)
  itf := NetInterface(carte, ip("10.0.2.15"), ip("10.0.2.2"))
  mac := itf.resolve(itf.gateway, 200000)      # ARP
  print(itf.ping(itf.gateway, 1, 200000))       # vrai si réponse

Compilable en natif (# alex: native).
```

API publique :

- interface `NetworkDevice` : `name()`, `mac()`, `mtu()`, `link_up()`, `send(b: PacketBuffer)`, `receive()`, `recycle(b: PacketBuffer)`, `stats()`
- class `LoopbackDevice(pool: BufferPool)` : `name()`, `mac()`, `mtu()`, `link_up()`, `send(b: PacketBuffer)`, `receive()`, `recycle(b: PacketBuffer)`, `stats()`
- class `NetInterface(dev: NetworkDevice, address: int, gateway: int)` : `poll()`, `resolve(target: int, tries: int)`, `ping(target: int, seq: int, tries: int)`, `send_udp(target: int, sport: int, dport: int, payload: str, tries: int)`

### `network_driver.network_packet` (natif)

```text
Paquets au-dessus d'Ethernet, construits et analysés directement dans un PacketBuffer (sans copie) :
  - adresses IPv4 (entier 32 bits <-> « 10.0.2.15 »), somme de contrôle Internet (RFC 1071) ;
  - ARP (requête / réponse), IPv4 (en-tête de 20 octets, somme de contrôle), ICMP (écho), UDP (avec
    pseudo-en-tête) ;
  - Packet : analyse d'une trame reçue (Ethernet -> ARP / IPv4 -> ICMP / UDP / TCP) avec vérification des
    sommes de contrôle, et description lisible.

  use network_driver.network_packet as np
  b := pool.get()
  np.build_icmp_echo(b, mon_mac, passerelle_mac, np.ip("10.0.2.15"), np.ip("10.0.2.2"), 1, 1, "ping")
  carte.send(b)
  p := np.parse(recu)
  if p.is_icmp_reply():
      print(p.describe())

Compilable en natif (# alex: native).
```

API publique :

- `ip(text: str)`
- `ip_text(v: int)`
- `sum16(addr: int, n: int, acc: int)`
- `fold(s: int)`
- `checksum(addr: int, n: int)`
- `build_arp(b: PacketBuffer, op: int, src_mac: int, src_ip: int, dst_mac: int, dst_ip: int)`
- `push_ipv4(b: PacketBuffer, src: int, dst: int, proto: int, ident: int, ttl: int)`
- `push_ethernet(b: PacketBuffer, dst_mac: int, src_mac: int, ethertype: int)`
- `build_icmp_echo(b: PacketBuffer, src_mac: int, dst_mac: int, src: int, dst: int, ident: int, seq: int, payload: str)`
- `build_udp(b: PacketBuffer, src_mac: int, dst_mac: int, src: int, dst: int, sport: int, dport: int, payload: str)`
- class `Packet()` : `is_arp()`, `is_ipv4()`, `is_icmp_reply()`, `is_udp()`, `payload_string()`, `describe()`
- `parse(b: PacketBuffer)`
- `parse_at(addr: int, n: int)`

### `network_driver.network_stats` (natif)

```text
Compteurs d'une interface réseau : paquets et octets reçus / émis, erreurs, pertes (file pleine, tampon
manquant), trames trop courtes / longues, diffusion, multidiffusion ; instantané et différence (débits).

  s := NetworkStats()
  s.count_rx(64, false, true)
  print(s.describe())
  avant := s.snapshot()
  ...
  print(s.diff(avant).describe())

Compilable en natif (# alex: native).
```

API publique :

- class `NetworkStats()` : `reset()`, `count_rx(bytes: int, broadcast: bool, multicast: bool)`, `count_tx(bytes: int)`, `snapshot()`, `diff(before: NetworkStats)`, `errors()`, `describe()`

## Paquet `usb_driver`

### `usb_driver` (natif)

```text
Pile USB d'un noyau Alex (--freestanding) :

| Module                            | Contenu                                                          |
|-----------------------------------|------------------------------------------------------------------|
| usb_driver.usb_host_controller    | HostController, UhciController, UsbDev, enumerate                |
| usb_driver.usb_class              | HidKeyboard, HidMouse, MassStorage (BOT + SCSI, BlockDevice)     |
| usb_driver.usb_driver_registry    | UsbDriverRegistry : liaison des interfaces aux pilotes de classe |
| usb.usb_descriptor                | descripteurs et requêtes (commun avec les applications)          |

Ici : UhciDriver (pilote PCI des contrôleurs UHCI, classe 0C:03:00, pour le cadre driver) et UsbStack
(découverte des contrôleurs, énumération des ports, liaison des pilotes de classe, scrutation).

  use usb_driver
  pile := usb_driver.start()                   # contrôleurs, périphériques, pilotes
  print(pile.describe())
  while true:
      pile.poll()
      for k in pile.registry.keyboards:
          print(k.take_text())

Pas encore : OHCI / EHCI / xHCI, concentrateurs externes (seuls les ports racines sont énumérés),
transferts isochrones.

Compilable en natif (# alex: native).
```

API publique :

- class `UhciDriver()` : `info()`, `probe(dev: HwDevice)`, `attach(dev: HwDevice)`, `detach(dev: HwDevice)`, `status(dev: HwDevice)`
- class `UsbStack()` : `discover(bus: PciBus)`, `scan(hc: HostController)`, `poll()`, `describe()`
- `start()`

### `usb_driver.usb_class` (natif)

```text
Pilotes de CLASSE USB (au-dessus d'un contrôleur hôte, usb_driver.usb_host_controller) :
  - interface UsbClassDriver : name(), matches(dev, interface), attach(hc, dev, interface), poll(), describe() ;
  - HidKeyboard : clavier HID en protocole d'amorçage (SET_PROTOCOL, SET_IDLE), rapports de 8 octets,
    touches nouvellement enfoncées -> caractères (disposition QWERTY US, Maj, Verr. Maj), file de saisie ;
  - HidMouse : souris HID d'amorçage : boutons, déplacements relatifs, molette, position cumulée ;
  - MassStorage : stockage de masse « Bulk-Only Transport » + commandes SCSI (INQUIRY, TEST UNIT READY,
    READ CAPACITY (10), READ (10), WRITE (10), SYNCHRONIZE CACHE) ; c'est un BlockDevice
    (storage_driver.block_device) : partitions, cache, systèmes de fichiers fonctionnent dessus.

Compilable en natif (# alex: native).
```

API publique :

- interface `UsbClassDriver` : `name()`, `matches(dev: UsbDev, itf: InterfaceDescriptor)`, `attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor)`, `poll()`, `describe()`
- class `HidKeyboard()` : `name()`, `matches(dev: UsbDev, itf: InterfaceDescriptor)`, `attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor)`, `poll()`, `take_text()`, `describe()`
- `usage_char(code: int, shift: bool, caps: bool)`
- class `HidMouse()` : `name()`, `matches(dev: UsbDev, itf: InterfaceDescriptor)`, `attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor)`, `poll()`, `left()`, `right()`, `describe()`
- class `MassStorage(label: str)` : `name()`, `matches(dev: UsbDev, itf: InterfaceDescriptor)`, `attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor)`, `block_size()`, `block_count()`, `read_only()`, `read_blocks(lba: int, count: int, buf: int)`, `write_blocks(lba: int, count: int, buf: int)`, `flush()`, `poll()`, `describe()`

### `usb_driver.usb_driver_registry` (natif)

```text
Registre des pilotes de classe USB et liaison aux interfaces des périphériques énumérés : pour chaque
interface (réglage 0) de chaque périphérique, le premier pilote dont matches() répond oui l'obtient.
Les pilotes sont fournis par des FABRIQUES (une instance par interface liée).

  r := UsbDriverRegistry()
  r.add_keyboard()
  r.add_mouse()
  r.add_mass_storage()
  r.bind(hc, dev)                       # périphérique énuméré
  for b in r.bound:                     # UsbClassDriver
      print(b.describe())

Compilable en natif (# alex: native).
```

API publique :

- class `UsbDriverRegistry()` : `add(label: str, factory: func() -> UsbClassDriver)`, `add_keyboard()`, `add_mouse()`, `add_mass_storage()`, `add_defaults()`, `bind(hc: HostController, dev: UsbDev)`, `poll()`, `describe()`

### `usb_driver.usb_host_controller` (natif)

```text
Contrôleurs hôtes USB d'un noyau Alex :
  - interface HostController : ports racines (connexion, réinitialisation, vitesse), transferts de contrôle,
    bloc et interruption vers un périphérique (adresse, point d'accès, bascule DATA0 / DATA1) ;
  - UhciController : UHCI (Intel PIIX3 / PIIX4 / ICH, QEMU « piix3-usb-uhci ») : registres en ports
    d'entrée-sortie (BAR4), liste de 1024 trames, une file (QH) où s'enchaînent les descripteurs de
    transfert (TD), paquets de 8 / 64 octets, pleine et basse vitesse ;
  - UsbDev : un périphérique énuméré (adresse, vitesse, descripteurs, bascules par point d'accès) ;
  - enumerate(hc, port, adresse) : réinitialisation du port, lecture des descripteurs, SET_ADDRESS,
    SET_CONFIGURATION.

  hc := UhciController(0xC040)
  hc.setup()
  for p in 0..hc.port_count():
      if hc.port_connected(p):
          d := enumerate(hc, p, adresse_libre)

Erreurs : DeviceTimeout, DeviceIoError (STALL, erreur de bus), UnsupportedDevice. Compilable en natif.
```

API publique :

- `speed_name(s: int)`
- class `UsbDev(address: int, port: int, speed: int)` : `low_speed()`, `toggle(ep: int)`, `set_toggle(ep: int, v: int)`, `describe()`
- interface `HostController` : `name()`, `setup()`, `port_count()`, `port_connected(port: int)`, `reset_port(port: int)`, `control(dev: UsbDev, setup: SetupPacket, buf: int)`, `bulk(dev: UsbDev, endpoint: int, max_packet: int, buf: int, length: int, tries: int)`, `interrupt_open(dev: UsbDev, endpoint: int, max_packet: int)`, `interrupt_read(pipe: int, buf: int)`
- class `UhciController(io: int)` : `name()`, `setup()`, `running()`, `port_count()`, `port_connected(port: int)`, `reset_port(port: int)`, `control(dev: UsbDev, setup: SetupPacket, buf: int)`, `bulk(dev: UsbDev, endpoint: int, max_packet: int, buf: int, length: int, tries: int)`, `interrupt_open(dev: UsbDev, endpoint: int, max_packet: int)`, `interrupt_read(pipe: int, buf: int)`, `describe()`
- `read_string(hc: HostController, dev: UsbDev, index: int, buf: int)`
- `enumerate(hc: HostController, port: int, address: int)`

## Paquet `gpu_driver`

### `gpu_driver` (natif)

```text
Pilotes graphiques d'un noyau Alex (--freestanding). Pilote fourni : carte Bochs / QEMU « stdvga »
(PCI 1234:1111, aussi VirtualBox VBoxVGA en mode compatible) par l'interface DISPI (« BGA ») :
  - détection (registre d'identification 0xB0C0..0xB0C5), mémoire vidéo (registre en blocs de 64 Kio) ;
  - choix du mode (largeur, hauteur, 8 / 15 / 16 / 24 / 32 bits), tampon linéaire (BAR0) ;
  - double tampon par décalage vertical (Y_OFFSET) : on dessine dans l'image cachée puis flip() ;
  - registres par ports 0x1CE / 0x1CF, ou par MMIO (BAR2, décalage 0x500) quand la carte en a ;
  - surfaces 2D (gpu_driver.gpu_command.Surface2D) sur l'image affichée / cachée, et gestion de la VRAM
    restante (gpu_driver.gpu_memory_manager).

| Module                             | Contenu                                                 |
|------------------------------------|---------------------------------------------------------|
| gpu_driver.gpu_capabilities        | GpuCapabilities, VideoMode                              |
| gpu_driver.gpu_memory_manager      | GpuMemoryManager, VramBlock                             |
| gpu_driver.gpu_command             | Surface2D, CommandBuffer, GpuEngine                     |

  use gpu_driver
  g := gpu_driver.find_bochs()                 # BochsGpu? (bus PCI)
  g.set_mode(800, 600, 32, true)               # double tampon
  s := g.back_surface()
  s.clear(0x203040)
  g.flip()

Erreurs : UnsupportedDevice (mode impossible), DeviceNotFound. Compilable en natif (# alex: native).
```

API publique :

- class `BochsGpu(lfb_phys: int, mmio_phys: int)` : `read(reg: int)`, `write(reg: int, v: int)`, `capabilities()`, `set_mode(width: int, height: int, bpp: int, double: bool)`, `disable()`, `enabled()`, `pitch()`, `mode()`, `front_surface()`, `back_surface()`, `flip()`, `displayed_offset()`, `submit(cb: CommandBuffer)`, `offscreen(width: int, height: int)`, `describe()`
- class `BochsGpuDriver()` : `info()`, `probe(dev: HwDevice)`, `attach(dev: HwDevice)`, `detach(dev: HwDevice)`, `status(dev: HwDevice)`
- `find_bochs()`

### `gpu_driver.gpu_capabilities` (natif)

```text
Ce qu'une carte graphique sait faire, tel que le pilote le découvre : mémoire vidéo, résolution et
profondeurs maximales, modes proposés, double tampon (défilement vertical de la mémoire), accélération 2D
matérielle ou non, curseur matériel.

  caps := pilote.capabilities()
  print(caps.describe())
  m := caps.best_mode(1024, 768)        # VideoMode le plus proche sans dépasser

Compilable en natif (# alex: native).
```

API publique :

- class `VideoMode(width: int, height: int, bpp: int)` : `pitch()`, `bytes()`, `describe()`
- class `GpuCapabilities(name: str, vram: int, max_width: int, max_height: int)` : `add_mode(width: int, height: int, bpp: int)`, `add_standard_modes()`, `supports(width: int, height: int, bpp: int)`, `best_mode(width: int, height: int)`, `can_double_buffer(m: VideoMode)`, `describe()`

### `gpu_driver.gpu_command` (natif)

```text
Tampons de commandes 2D et leur exécution sur une surface en mémoire (VRAM ou RAM) :
  - Surface2D : zone de points 32 bits (0x00RRGGBB) de largeur, hauteur et pas (octets par ligne) donnés,
    avec les primitives : point, remplissage, rectangle plein, ligne (Bresenham), copie d'une zone (avec
    recouvrement), copie depuis la mémoire, somme de contrôle (tests) ;
  - CommandBuffer : suite de commandes encodées (entiers) qu'on enregistre puis qu'on soumet en une fois :
    CLEAR, FILL_RECT, LINE, PIXEL, BLIT, UPLOAD, FENCE ;
  - GpuEngine : exécute un tampon de commandes sur une surface (moteur logiciel : la carte Bochs n'a pas de
    2D matérielle), compte les commandes et les points écrits, signale les barrières (FENCE).

  s := Surface2D(adresse, 640, 480, 640 * 4)
  cb := CommandBuffer()
  cb.clear(0x000020)
  cb.fill_rect(10, 10, 100, 50, 0xFF8800)
  cb.line(0, 0, 639, 479, 0xFFFFFF)
  GpuEngine().execute(cb, s)

Compilable en natif (# alex: native).
```

API publique :

- `rgb(r: int, g: int, b: int)`
- class `Surface2D(base: int, width: int, height: int, pitch: int)` : `addr(x: int, y: int)`, `pixel(x: int, y: int)`, `set_pixel(x: int, y: int, color: int)`, `fill_rect(x: int, y: int, w: int, h: int, color: int)`, `clear(color: int)`, `line(xa: int, ya: int, xb: int, yb: int, color: int)`, `blit(sx: int, sy: int, dx: int, dy: int, w: int, h: int)`, `upload(src: int, src_pitch: int, dx: int, dy: int, w: int, h: int)`, `checksum(x: int, y: int, w: int, h: int)`
- class `CommandBuffer()` : `clear(color: int)`, `fill_rect(x: int, y: int, w: int, h: int, color: int)`, `line(xa: int, ya: int, xb: int, yb: int, color: int)`, `pixel(x: int, y: int, color: int)`, `blit(sx: int, sy: int, dx: int, dy: int, w: int, h: int)`, `upload(src: int, src_pitch: int, dx: int, dy: int, w: int, h: int)`, `fence(value: int)`, `reset()`
- class `GpuEngine()` : `execute(cb: CommandBuffer, s: Surface2D)`

### `gpu_driver.gpu_memory_manager` (natif)

```text
Gestion de la mémoire vidéo (VRAM) d'une carte : des zones (surfaces hors écran, textures, tampons) prises
dans l'espace qui reste après l'image affichée, alignées, rendues au gestionnaire ; premier ajustement avec
fusion des trous libérés ; statistiques.

  mm := GpuMemoryManager(taille_vram, octets_de_l_ecran, 4096)
  z := mm.allocate(256 * 256 * 4, "sprite")      # VramBlock (décalage dans la VRAM) ou null si plein
  ...
  mm.release(z)

Compilable en natif (# alex: native).
```

API publique :

- class `VramBlock(offset: int, size: int, label: str, used: bool)` : `end()`
- class `GpuMemoryManager(total: int, reserved: int, align: int)` : `set_reserved(reserved: int)`, `allocate(size: int, label: str)`, `release(z: VramBlock)`, `used_bytes()`, `free_bytes()`, `largest_free()`, `describe()`

