# Multiprocesseur : cœurs annoncés par l'ACPI (table MADT), APIC local de chaque cœur (registres lus par la
# fenêtre hw.mmio), démarrage des autres cœurs (INIT puis deux SIPI vers la page de démarrage en 0x8000) et
# minuterie APIC par cœur (préemption : chaque tic appelle tasks.yield_now()).
#
# Le code Alex du noyau s'exécute sous le verrou global du noyau : un seul cœur à la fois, mais les programmes
# en anneau 3 (processus.al) tournent en parallèle, un par cœur.
use hw
use tasks
from collections use append
from core use len

const TIMER_VECTOR := 48
const SPURIOUS_VECTOR := 255
const MAX_CPUS := 16

lapic_phys := 4276092928 # 0xFEE00000, remplacé par l'adresse de la MADT
lapic := 0
ticks_per_ms := 0 # minuterie APIC (diviseur 16) : décomptes par milliseconde
timer_hz := 0
apic_ids: list[int] := [] # identifiants APIC des cœurs utilisables (MADT), cœur de démarrage compris
ticks: list[int] := [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] # tics de minuterie reçus, par cœur

# ---- APIC local ----
func _r(off: int) -> int:
    return hw.peek32(lapic + off)

func _w(off: int, v: int):
    hw.poke32(lapic + off, v)

func apic_id() -> int:
    return _r(32) >> 24

func eoi():
    _w(176, 0)

# Active l'APIC local du cœur courant (registre SVR : vecteur parasite 255, bit 8) et accepte toutes les priorités.
func _enable():
    _w(128, 0)
    _w(240, 256 | SPURIOUS_VECTOR)
    hw.poke64(hw.cpu_block() + 48, apic_id())

func _ignore(code: int):
    return

func _tick(code: int):
    eoi()
    c := hw.cpu_id()
    ticks[c] = ticks[c] + 1
    tasks.yield_now()

# Minuterie APIC périodique du cœur courant (vecteur 48), hz tics par seconde.
func start_timer(hz: int):
    _w(992, 3)                          # diviseur 16
    _w(800, TIMER_VECTOR | 131072)      # LVT : périodique
    _w(896, ticks_per_ms * 1000 // hz)  # compte initial

func stop_timer():
    _w(800, 65536) # masquée

# Décomptes de la minuterie APIC pendant 10 ms mesurées par le canal 2 du PIT (mode 0, porte du port 0x61).
func _calibrate():
    _w(992, 3)
    hw.outb(97, (hw.inb(97) & 253) | 1)
    hw.outb(67, 176)
    hw.outb(66, 11932 & 255)
    hw.outb(66, 11932 >> 8)
    g := hw.inb(97) & 254
    hw.outb(97, g)
    hw.outb(97, g | 1)
    _w(896, 4294967295)
    while (hw.inb(97) & 32) == 0:
        hw.pause()
    elapsed := 4294967295 - _r(912)
    _w(896, 0)
    ticks_per_ms = elapsed // 10
    if ticks_per_ms < 1:
        ticks_per_ms = 1

# ---- ACPI : RSDP -> RSDT / XSDT -> MADT ----
func _p(addr: int) -> int:
    return hw.mmio(addr)

func _is(addr: int, sig: str) -> bool:
    i := 0
    while i < hw.byte_size(sig):
        if hw.peek8(_p(addr + i)) != hw.peek8(hw.byte_addr(sig) + i):
            return false
        i += 1
    return true

func _rsdp() -> int:
    ebda := hw.peek16(_p(1038)) << 4
    for zone in [(ebda, ebda + 1024), (917504, 1048576)]:
        a := zone[0]
        while a < zone[1]:
            if _is(a, "RSD PTR "):
                return a
            a += 16
    return 0

# Table ACPI de signature sig (4 lettres), ou 0.
func _table(sig: str) -> int:
    rsdp := _rsdp()
    if rsdp == 0:
        return 0
    root := hw.peek32(_p(rsdp + 16))
    width := 4
    if hw.peek8(_p(rsdp + 15)) >= 2 and hw.peek64(_p(rsdp + 24)) != 0:
        root = hw.peek64(_p(rsdp + 24))
        width = 8
    n := (hw.peek32(_p(root + 4)) - 36) // width
    i := 0
    while i < n:
        t := hw.peek32(_p(root + 36 + width * i))
        if width == 8:
            t = hw.peek64(_p(root + 36 + width * i))
        if _is(t, sig):
            return t
        i += 1
    return 0

# Identifiants APIC des cœurs utilisables (entrées de type 0, activées) ; à défaut, le cœur courant seul.
func _cpus_from_madt() -> list[int]:
    ids: list[int] := []
    madt := _table("APIC")
    if madt == 0:
        return ids
    lapic_phys = hw.peek32(_p(madt + 36))
    end := madt + hw.peek32(_p(madt + 4))
    e := madt + 44
    while e < end:
        kind := hw.peek8(_p(e))
        size := hw.peek8(_p(e + 1))
        if size == 0:
            break
        if kind == 0 and (hw.peek32(_p(e + 4)) & 3) != 0:
            append(ids, hw.peek8(_p(e + 3)))
        e += size
    return ids

# ---- Démarrage des autres cœurs ----
# Attente de us microsecondes mesurées par la minuterie APIC du cœur (étalonnée ; masquée, un seul tour).
func _delay(us: int):
    _w(800, 65536)
    _w(992, 3)
    n := ticks_per_ms * us // 1000
    if n < 1:
        n = 1
    _w(896, n)
    while _r(912) != 0:
        hw.pause()

func _ipi(apic: int, command: int):
    _w(784, apic << 24)
    _w(768, command)
    while (_r(768) & 4096) != 0: # envoi en cours
        hw.pause()

func _wait_online(block: int, us: int) -> bool:
    i := 0
    while i < us:
        if hw.cpu_online(block):
            return true
        _delay(10)
        i += 10
    return hw.cpu_online(block)

# Tâche inactive d'un autre cœur : APIC, minuterie, puis attente d'interruption (verrou global rendu).
func _idle():
    _enable()
    if timer_hz > 0:
        start_timer(timer_hz)
    while true:
        hw.wait()
        tasks.yield_now()

# Active l'APIC du cœur de démarrage, étalonne sa minuterie, démarre les autres cœurs ; chacun, cœur de
# démarrage compris, reçoit une minuterie à hz tics par seconde (0 : aucune). Renvoie le nombre de cœurs en
# service.
func start(hz: int) -> int:
    ids := _cpus_from_madt()
    lapic = hw.mmio(lapic_phys)
    hw.on_interrupt(SPURIOUS_VECTOR, _ignore)
    hw.on_interrupt(TIMER_VECTOR, _tick)
    _enable()
    _calibrate()
    timer_hz = hz
    me := apic_id()
    apic_ids = [me]
    index := 1
    for id in ids:
        if id == me or index >= MAX_CPUS:
            continue
        b := hw.smp_prepare(index, _idle)
        hw.poke64(b + 48, id)
        _ipi(id, 17664)          # INIT (0x4500)
        _delay(10000)
        _ipi(id, 17928)          # SIPI, vecteur 8 : page 0x8000 (0x4608)
        if not _wait_online(b, 200):
            _ipi(id, 17928)
            _wait_online(b, 100000)
        if hw.cpu_online(b):
            append(apic_ids, id)
            index += 1
    if hz > 0:
        start_timer(hz)
    return hw.cpus()
