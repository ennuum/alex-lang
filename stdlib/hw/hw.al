# ALEX STANDARD LIBRARY — hw (MACHINE SIMULÉE, pour la VM)
#
# Dans un noyau compilé avec `alexc build --native --freestanding`, `use hw` donne l'accès direct au matériel
# (ports d'entrée-sortie, mémoire physique, interruptions, instructions privilégiées : docs/NATIVE.md). Ce
# fichier-ci est la version de la VM (`alexc run`) : une MACHINE SIMULÉE qui offre les mêmes fonctions, avec la
# même sémantique, au-dessus d'une RAM simulée et de modèles de périphériques écrits en Alex. Les pilotes (pci,
# interrupt, dma, storage_driver...) s'exécutent ainsi sans QEMU, et se testent dans la VM.
#
#   use hw
#   hw.sim_reset(64 * 1024 * 1024)              # RAM simulée neuve (64 Mio), tas à partir de 16 Mio
#   hw.sim_map_ports(0x1F0, 8, mon_disque)      # modèle : io_read(port, taille) / io_write(port, taille, valeur)
#   hw.sim_map_mmio(0xFEBC0000, 0x20000, nic)   # modèle : mem_read(décalage, taille) / mem_write(...)
#   hw.on_interrupt(33, gestionnaire)
#   hw.pic_init()
#   hw.irq_enable(1)
#   hw.sti()
#   hw.sim_raise_irq(1)                         # le gestionnaire du vecteur 33 s'exécute
#
# Fidélité :
#   - ports non attribués : lecture 0xFF / 0xFFFF / 0xFFFFFFFF (bus flottant), écriture ignorée ;
#   - mémoire : petit-boutiste ; accès hors de la RAM simulée et hors des zones MMIO déclarées : MemoryError ;
#   - hw.mmio(phys) renvoie la même adresse que dans un vrai noyau (fenêtre à 512 Gio) ;
#   - interruptions : drapeau IF (cli / sti / disable_saved / restore), PIC 8259 maître/esclave simulé sur les
#     ports 0x20-0x21 / 0xA0-0xA1 (ICW1-4, masques, EOI, IRR / ISR lisibles), minuterie PIT (0x40-0x43) qui
#     tique quand le temps simulé avance (sim_tick, wait) ;
#   - un seul cœur ; pas de mode utilisateur ni d'assembleur en ligne (HardwareError).
#
# Erreurs : MemoryError (adresse invalide), HardwareError (fonction indisponible dans la simulation),
# ArgumentError.

from core use len, type
from collections use append, contains_key, keys
use _native_hwsim as _m
use _native_net as _b
use _native_fd as _fd
use os as _os

const MMIO_WINDOW := 549755813888     # 512 Gio : fenêtre sans cache des périphériques (comme le noyau Alex)

# ---------------------------------------------------------------- état de la machine
_state := {"if": false, "time": 0, "pit_hz": 0, "pit_divisor": 0, "pit_access": 0, "pit_latch": 0, "cr3": 4096,
           "cr2": 0, "trace": false, "in_handler": 0, "halted": 0}
_ports := []          # [début, fin (exclue), modèle]
_mmio := []           # [début physique, fin, modèle]
_handlers := {}       # vecteur -> fonction(code)
_pending := []        # [vecteur, code] en attente (IF = 0 ou masqué)
_msrs := {27: 4276094976 | 2304}     # IA32_APIC_BASE = 0xFEE00000 | BSP | activé
_trace := []
_syscall := [null]

func _unsupported(what):
    raise("HardwareError", "hw." + what + " : indisponible dans la machine simulée de la VM (compiler avec --freestanding et lancer sous QEMU)")

# ---------------------------------------------------------------- PIC 8259 simulé (maître 0x20, esclave 0xA0)
class _Pic:
    func init(name, base):
        self.name = name
        self.base = base         # vecteur de la ligne 0 (programmé par ICW2)
        self.imr = 255           # tout masqué au départ
        self.irr = 0
        self.isr = 0
        self.icw_step = 0
        self.read_isr = false
        self.eoi_count = 0

    func io_read(port, size):
        if port % 2 == 0:
            if self.read_isr:
                return self.isr
            return self.irr
        return self.imr

    func io_write(port, size, value):
        value = value & 255
        if port % 2 == 0:
            if value & 16 != 0:            # ICW1
                self.icw_step = 1
                self.imr = 0
                self.isr = 0
                self.irr = 0
                return
            if value & 24 == 8:            # OCW3
                if value & 3 == 3:
                    self.read_isr = true
                elif value & 3 == 2:
                    self.read_isr = false
                return
            if value & 32 != 0:            # OCW2 : EOI
                self.eoi_count += 1
                if value & 64 != 0:        # EOI spécifique
                    self.isr = self.isr & ~(1 << (value & 7))
                else:
                    k := 0
                    while k < 8:
                        if self.isr & (1 << k) != 0:
                            self.isr = self.isr & ~(1 << k)
                            break
                        k += 1
                _deliver_pending()
            return
        if self.icw_step == 1:
            self.base = value & 248        # ICW2
            self.icw_step = 2
        elif self.icw_step == 2:
            self.icw_step = 3              # ICW3
        elif self.icw_step == 3:
            self.icw_step = 0              # ICW4
        else:
            self.imr = value               # OCW1 : masque
            _deliver_pending()

_master := _Pic("maître", 8)
_slave := _Pic("esclave", 112)

# ---------------------------------------------------------------- PIT 8253/8254 simulé (canal 0)
class _Pit:
    func init():
        self.reload = 0
        self.byte_low = true
        self.partial = 0

    func io_read(port, size):
        return 0

    func io_write(port, size, value):
        value = value & 255
        if port == 67:                     # 0x43 : commande
            self.byte_low = true
            return
        if port == 64:                     # 0x40 : canal 0, octet bas puis haut
            if self.byte_low:
                self.partial = value
                self.byte_low = false
            else:
                self.reload = self.partial | (value << 8)
                if self.reload == 0:
                    self.reload = 65536
                _state["pit_divisor"] = self.reload
                _state["pit_hz"] = 1193182 // self.reload
                self.byte_low = true

_pit := _Pit()

func _builtin_ports():
    return [[32, 34, _master], [160, 162, _slave], [64, 68, _pit]]

# ---------------------------------------------------------------- configuration de la simulation
# RAM simulée neuve (octets) ; les pages de alloc_pages sont prises à partir de heap_start. Oublie les modèles et
# les gestionnaires, remet les PIC et la minuterie à zéro.
func sim_reset(ram_bytes=67108864, heap_start=16777216):
    _m.reset(ram_bytes, heap_start)
    _reset_lists()

func _reset_lists():
    while len(_ports) > 0:
        _ports_pop()
    while len(_mmio) > 0:
        _mmio_pop()
    for k in keys(_handlers):
        _handlers[k] = null
    while len(_pending) > 0:
        _pending_pop()
    _master.init("maître", 8)
    _slave.init("esclave", 112)
    _pit.init()
    _state["if"] = false
    _state["time"] = 0
    _state["pit_hz"] = 0
    _state["in_handler"] = 0
    _state["halted"] = 0
    _syscall[0] = null

func _ports_pop():
    _list_pop(_ports)

func _mmio_pop():
    _list_pop(_mmio)

func _pending_pop():
    _list_pop(_pending)

use collections as _col

func _list_pop(l):
    _col.pop(l)

# Attribue les ports [start, start + count) au modèle (méthodes io_read(port, taille), io_write(port, taille, v)).
func sim_map_ports(start, count, model):
    for p in _ports:
        if start < p[1] and p[0] < start + count:
            raise("ArgumentError", "hw.sim_map_ports : ports " + str(start) + ".." + str(start + count - 1) + " déjà attribués")
    append(_ports, [start, start + count, model])

# Attribue la zone physique [phys, phys + size) au modèle (mem_read(décalage, taille), mem_write(décalage, taille, v)).
func sim_map_mmio(phys, size, model):
    for r in _mmio:
        if phys < r[1] and r[0] < phys + size:
            raise("ArgumentError", "hw.sim_map_mmio : zone déjà attribuée")
    append(_mmio, [phys, phys + size, model])

func sim_unmap(model):
    keep := [p for p in _ports if p[2] != model]
    while len(_ports) > 0:
        _ports_pop()
    for p in keep:
        append(_ports, p)
    keep2 := [r for r in _mmio if r[2] != model]
    while len(_mmio) > 0:
        _mmio_pop()
    for r in keep2:
        append(_mmio, r)

# Journal des accès aux ports (liste de [« in » / « out », port, taille, valeur]).
func sim_trace(enabled=true):
    _state["trace"] = enabled
    while len(_trace) > 0:
        _list_pop(_trace)

func sim_trace_log():
    return [t for t in _trace]

func sim_time():
    return _state["time"]

func sim_interrupts_enabled():
    return _state["if"]

func sim_pic():
    return {"master_mask": _master.imr, "slave_mask": _slave.imr, "master_base": _master.base, "slave_base": _slave.base,
            "eoi": _master.eoi_count + _slave.eoi_count, "master_isr": _master.isr, "slave_isr": _slave.isr}

func sim_timer_hz():
    return _state["pit_hz"]

func sim_pages_allocated():
    return _m.allocated()

# ---------------------------------------------------------------- interruptions
# Demande l'interruption vector (code : code d'erreur du processeur) ; délivrée tout de suite si IF = 1, sinon à sti.
func sim_raise_interrupt(vector, code=0):
    append(_pending, [vector, code])
    _deliver_pending()

# La ligne irq (0..15) du PIC est levée : délivrée si elle n'est pas masquée (sinon gardée dans IRR).
func sim_raise_irq(irq):
    pic := _master
    line := irq
    if irq >= 8:
        pic = _slave
        line = irq - 8
    pic.irr = pic.irr | (1 << line)
    _deliver_pending()

func _pic_next():
    # Ligne la plus prioritaire en attente et non masquée (esclave via la ligne 2 du maître).
    k := 0
    while k < 8:
        bit := 1 << k
        if k == 2:
            if _master.imr & 4 == 0 and _master.isr & 4 == 0:
                j := 0
                while j < 8:
                    b2 := 1 << j
                    if _slave.irr & b2 != 0 and _slave.imr & b2 == 0 and _slave.isr & b2 == 0:
                        return 8 + j
                    j += 1
        elif _master.irr & bit != 0 and _master.imr & bit == 0 and _master.isr & bit == 0:
            return k
        k += 1
    return -1

func _deliver_pending():
    if not _state["if"] or _state["in_handler"] > 0:
        return
    while _state["if"]:
        if len(_pending) > 0:
            p := _pending[0]
            rest := [_pending[k] for k in 1..len(_pending)]
            while len(_pending) > 0:
                _pending_pop()
            for r in rest:
                append(_pending, r)
            _dispatch(p[0], p[1])
            continue
        irq := _pic_next()
        if irq < 0:
            return
        if irq < 8:
            _master.irr = _master.irr & ~(1 << irq)
            _master.isr = _master.isr | (1 << irq)
            _dispatch(_master.base + irq, 0)
        else:
            _slave.irr = _slave.irr & ~(1 << (irq - 8))
            _slave.isr = _slave.isr | (1 << (irq - 8))
            _master.isr = _master.isr | 4
            _dispatch(_slave.base + irq - 8, 0)

func _dispatch(vector, code):
    h := null
    if contains_key(_handlers, vector):
        h = _handlers[vector]
    saved := _state["if"]
    _state["if"] = false              # interruptions masquées pendant le gestionnaire, comme le noyau
    _state["in_handler"] += 1
    try:
        if h != null:
            h(code)
        elif vector >= 32 and vector < 48:
            eoi(vector - 32)
        elif vector < 32:
            raise("CPUError", "exception du processeur " + str(vector) + " (code " + str(code) + ") sans gestionnaire")
    finally:
        _state["in_handler"] -= 1
        _state["if"] = saved

func on_interrupt(vector, handler):
    _handlers[vector] = handler

func pic_init():
    outb(32, 17)
    outb(160, 17)
    outb(33, 32)
    outb(161, 40)
    outb(33, 4)
    outb(161, 2)
    outb(33, 1)
    outb(161, 1)
    outb(33, 255)
    outb(161, 255)

func irq_enable(irq):
    if irq < 8:
        outb(33, inb(33) & ~(1 << irq))
    else:
        outb(161, inb(161) & ~(1 << (irq - 8)))
        outb(33, inb(33) & ~4)

func irq_disable(irq):
    if irq < 8:
        outb(33, inb(33) | (1 << irq))
    else:
        outb(161, inb(161) | (1 << (irq - 8)))

func eoi(irq):
    if irq >= 8:
        outb(160, 32)
    outb(32, 32)

func timer_start(hz):
    d := 1193182 // hz
    outb(67, 54)
    outb(64, d & 255)
    outb(64, (d >> 8) & 255)

# Avance le temps simulé de n tics de la minuterie (chacun lève la ligne 0 du PIC si la minuterie tourne).
func sim_tick(n=1):
    k := 0
    while k < n:
        _state["time"] += 1
        if _state["pit_hz"] > 0:
            sim_raise_irq(0)
        k += 1

func wait():
    _state["if"] = true
    before := _state["time"]
    _deliver_pending()
    if len(_pending) == 0 and _pic_next() < 0 and _state["pit_hz"] > 0:
        sim_tick(1)                 # hlt : le prochain événement est le tic de la minuterie
    _state["halted"] += 1

func disable_saved():
    s := 0
    if _state["if"]:
        s = 512
    _state["if"] = false
    return s

func restore(state):
    _state["if"] = state & 512 != 0
    _deliver_pending()

func enable():
    _state["if"] = true
    _deliver_pending()

func disable():
    _state["if"] = false

func cli():
    disable()

func sti():
    enable()

func hlt():
    _state["halted"] += 1
    _deliver_pending()

func pause():
    return null

# ---------------------------------------------------------------- ports
func _port_model(port):
    for p in _ports:
        if port >= p[0] and port < p[1]:
            return p[2]
    for p in _builtin_ports():
        if port >= p[0] and port < p[1]:
            return p[2]
    return null

func _in(port, size):
    m := _port_model(port)
    v := (1 << (8 * size)) - 1
    if m != null:
        v = m.io_read(port, size) & ((1 << (8 * size)) - 1)
    if _state["trace"]:
        append(_trace, ["in", port, size, v])
    return v

func _out(port, size, value):
    value = value & ((1 << (8 * size)) - 1)
    if _state["trace"]:
        append(_trace, ["out", port, size, value])
    m := _port_model(port)
    if m != null:
        m.io_write(port, size, value)

func outb(port, value):
    _out(port, 1, value)

func outw(port, value):
    _out(port, 2, value)

func outl(port, value):
    _out(port, 4, value)

func inb(port):
    return _in(port, 1)

func inw(port):
    return _in(port, 2)

func inl(port):
    return _in(port, 4)

# ---------------------------------------------------------------- mémoire
func mmio(phys):
    return MMIO_WINDOW + phys

func _mmio_model(addr):
    phys := addr
    if addr >= MMIO_WINDOW:
        phys = addr - MMIO_WINDOW
    for r in _mmio:
        if phys >= r[0] and phys < r[1]:
            return [r[2], phys - r[0]]
    if addr >= MMIO_WINDOW:
        raise("MemoryError", "hw (simulé) : aucun périphérique à l'adresse physique " + str(phys) + " (fenêtre MMIO)")
    return null

func _load(addr, size):
    m := _mmio_model(addr)
    if m != null:
        return m[0].mem_read(m[1], size) & _mask(size)
    return _m.read(addr, size)

func _store(addr, size, value):
    m := _mmio_model(addr)
    if m != null:
        m[0].mem_write(m[1], size, value & _mask(size))
        return
    _m.write(addr, size, value)

func _mask(size):
    if size == 8:
        return -1
    return (1 << (8 * size)) - 1

func peek8(addr):
    return _load(addr, 1)

func peek16(addr):
    return _load(addr, 2)

func peek32(addr):
    return _load(addr, 4)

func peek64(addr):
    return _load(addr, 8)

func poke8(addr, value):
    _store(addr, 1, value)

func poke16(addr, value):
    _store(addr, 2, value)

func poke32(addr, value):
    _store(addr, 4, value)

func poke64(addr, value):
    _store(addr, 8, value)

func alloc_pages(n):
    a := _m.alloc(n)
    if a < 0:
        raise("MemoryError", "alloc_pages(" + str(n) + ") : mémoire physique épuisée")
    return a

func free_pages(addr, n):
    _m.free(addr, n)

func copy(dst, src, n):
    if _mmio_model(dst) != null or _mmio_model(src) != null:
        k := 0
        while k < n:
            _store(dst + k, 1, _load(src + k, 1))
            k += 1
        return
    _m.copy(dst, src, n)

func zero(addr, n):
    _m.fill(addr, n, 0)

func string_at(addr, n):
    return _m.read_bytes(addr, n)

func store_string(s, addr):
    return _m.write_bytes(addr, s)

func byte_addr(s):
    _unsupported("byte_addr (adresse d'une chaîne Alex)")

func byte_size(s):
    return _b.blen(s)

func memory_end():
    return _m.size()

# ---------------------------------------------------------------- processeur
func cas(addr, expected, new):
    return _m.cas(addr, expected, new)

func atomic_add(addr, v):
    return _m.xadd(addr, v)

func spin_lock(addr):
    while _m.cas(addr, 0, 1) != 0:
        _deliver_pending()

func spin_unlock(addr):
    _m.write(addr, 8, 0)

func cpu_id():
    return 0

func cpus():
    return 1

func cpu_block():
    _unsupported("cpu_block")

func from_user():
    return false

func smp_prepare(index, idle):
    _unsupported("smp_prepare")

func cpu_online(block):
    _unsupported("cpu_online")

func rdmsr(msr):
    if contains_key(_msrs, msr):
        return _msrs[msr]
    return 0

func wrmsr(msr, value):
    _msrs[msr] = value

func cr2():
    return _state["cr2"]

func cr3():
    return _state["cr3"]

func invlpg(addr):
    return null

func flush_tlb():
    return null

func kernel_space():
    return 4096

func set_space(pml4):
    if pml4 == 0:
        pml4 = 4096
    _state["cr3"] = pml4

func on_syscall(handler):
    _syscall[0] = handler

func enter_user(rip, rsp):
    _unsupported("enter_user (mode utilisateur)")

func leave_user(code):
    _unsupported("leave_user (mode utilisateur)")

func console_write(s):
    _fd.write(1, s, null)

func exit(code):
    _os.exit(code)

func asm(code):
    _unsupported("asm (assembleur en ligne)")

func asm_value(code):
    _unsupported("asm_value (assembleur en ligne)")

_m.reset(67108864, 16777216)

# UEFI (compilation native --uefi seulement) : voir docs/NATIVE.md, section « UEFI ».
func efi_call(fn, a1 = 0, a2 = 0, a3 = 0, a4 = 0, a5 = 0, a6 = 0, a7 = 0, a8 = 0, a9 = 0, a10 = 0, a11 = 0, a12 = 0):
    _unsupported("efi_call (application UEFI native)")

func uefi():
    return false

func efi_image():
    _unsupported("efi_image (application UEFI native)")

func efi_system_table():
    _unsupported("efi_system_table (application UEFI native)")

func multiboot_info():
    return 0

func smp_parallel(on):
    return

func parallel():
    return false

func gc_count():
    return 0

func safepoint():
    return

func runtime_locks(on):
    return

func interrupt_free(vector: int, on: bool):
    return

func bkl_take():
    return

func bkl_drop():
    return

func bkl_held():
    return true
