# alex: native
# ALEX STANDARD LIBRARY — driver.driver_permissions
#
# Ce qu'un pilote a le droit de toucher : plages de ports d'E/S, plages de mémoire (MMIO), lignes
# d'interruption, accès DMA (avec masque d'adresses), bus. Les droits sont accordés à partir des ressources
# du périphérique lié (BAR PCI, ports de plate-forme) — principe du moindre privilège — ou explicitement ;
# chaque vérification refusée est journalisée et, en mode strict, lève DriverPermissionError.
#   - Grant : une permission (sorte, début, taille) ;
#   - DriverPermissions : droits d'un pilote ; check_io / check_mmio / check_irq / check_dma ;
#   - PermissionPolicy : droits de tous les pilotes, pilotes de confiance (tout accès), rapport des refus.
#
#   use driver.driver_permissions as dp
#   pol := dp.PermissionPolicy(true)                   # strict
#   p := pol.for_device("e1000", dev)                  # droits = ressources de dev
#   p.check_mmio(dev.mem_base(0) + 0x10, 4)            # vrai
#   p.check_io(0x60, 1)                                # DriverPermissionError : port hors des droits
#   print(pol.report())
#
# Erreurs : DriverPermissionError (mode strict).
# Compilable en natif (# alex: native).

from core use len
from collections use append
use string as _s
use driver.driver_info as di
from driver.driver_info use HwDevice

class Grant:
    kind: str := ""          # io, mem, irq, dma, bus
    start: int := 0
    size: int := 0
    label: str := ""

    func init(kind: str, start: int, size: int, label: str):
        self.kind = kind
        self.start = start
        self.size = size
        self.label = label

    func covers(kind: str, start: int, size: int) -> bool:
        if kind != self.kind:
            return false
        if kind == "irq":
            return start == self.start
        if kind == "dma":
            # start : adresse la plus haute utilisée ; size du droit : masque d'adressage
            return self.size == -1 or start <= self.size
        return start >= self.start and start + size <= self.start + self.size

    func describe() -> str:
        if self.kind == "irq":
            return "irq " + str(self.start)
        if self.kind == "dma":
            if self.size == -1:
                return "dma (64 bits)"
            return "dma <= " + str(self.size)
        if self.kind == "bus":
            return "bus " + self.label
        return self.kind + " " + str(self.start) + "+" + str(self.size)

class DriverPermissions:
    driver: str := ""
    grants: list[Grant] := []
    trusted: bool := false
    strict: bool := true
    denied: list[str] := []
    checks: int := 0

    func init(driver: str, strict: bool):
        self.driver = driver
        self.grants = []
        self.trusted = false
        self.strict = strict
        self.denied = []
        self.checks = 0

    func grant(kind: str, start: int, size: int) -> DriverPermissions:
        append(self.grants, Grant(kind, start, size, ""))
        return self

    func grant_bus(name: str) -> DriverPermissions:
        append(self.grants, Grant("bus", 0, 0, name))
        return self

    # Droits sur toutes les ressources du périphérique (ports, mémoire, interruption) + son bus.
    func grant_device(dev: HwDevice) -> DriverPermissions:
        for r in dev.resources:
            if r.kind == "irq":
                self.grant("irq", r.start, 1)
            elif r.kind == "io" or r.kind == "mem":
                self.grant(r.kind, r.start, r.size)
        if dev.irq >= 0 and not self.allowed("irq", dev.irq, 1):
            self.grant("irq", dev.irq, 1)
        self.grant_bus(dev.bus)
        return self

    func revoke_all():
        self.grants = []

    func allowed(kind: str, start: int, size: int) -> bool:
        if self.trusted:
            return true
        for g in self.grants:
            if g.covers(kind, start, size):
                return true
        return false

    func _check(kind: str, start: int, size: int, what: str) -> bool:
        self.checks += 1
        if self.allowed(kind, start, size):
            return true
        msg := "pilote " + self.driver + " : accès refusé — " + what
        append(self.denied, msg)
        if self.strict:
            raise("DriverPermissionError", msg)
        return false

    func check_io(port: int, size: int) -> bool:
        return self._check("io", port, size, "ports " + str(port) + "+" + str(size))

    func check_mmio(addr: int, size: int) -> bool:
        return self._check("mem", addr, size, "mémoire " + str(addr) + "+" + str(size))

    func check_irq(line: int) -> bool:
        return self._check("irq", line, 1, "interruption " + str(line))

    # highest : plus haute adresse physique que le périphérique lira ou écrira.
    func check_dma(highest: int) -> bool:
        return self._check("dma", highest, 0, "DMA jusqu'à " + str(highest))

    func check_bus(name: str) -> bool:
        self.checks += 1
        if self.trusted:
            return true
        for g in self.grants:
            if g.kind == "bus" and g.label == name:
                return true
        msg := "pilote " + self.driver + " : bus " + name + " non autorisé"
        append(self.denied, msg)
        if self.strict:
            raise("DriverPermissionError", msg)
        return false

    func describe() -> str:
        if self.trusted:
            return self.driver + " : confiance (tout accès)"
        t := self.driver + " :"
        if len(self.grants) == 0:
            return t + " aucun droit"
        first := true
        for g in self.grants:
            if first:
                t = t + " " + g.describe()
                first = false
            else:
                t = t + ", " + g.describe()
        return t

class PermissionPolicy:
    strict: bool := true
    entries: list[DriverPermissions] := []
    trusted_names: list[str] := []

    func init(strict: bool):
        self.strict = strict
        self.entries = []
        self.trusted_names = []

    func trust(name: str):
        append(self.trusted_names, name)
        for e in self.entries:
            if e.driver == name:
                e.trusted = true

    func get(name: str) -> DriverPermissions:
        for e in self.entries:
            if e.driver == name:
                return e
        p := DriverPermissions(name, self.strict)
        for t in self.trusted_names:
            if t == name:
                p.trusted = true
        append(self.entries, p)
        return p

    func for_device(name: str, dev: HwDevice) -> DriverPermissions:
        p := self.get(name)
        p.grant_device(dev)
        return p

    func denied_count() -> int:
        n := 0
        for e in self.entries:
            n += len(e.denied)
        return n

    func report() -> str:
        out := "droits des pilotes (" + ("strict" if self.strict else "journal seulement") + ") :\n"
        for e in self.entries:
            out = out + "  " + e.describe() + "\n"
            for d in e.denied:
                out = out + "    REFUS " + d + "\n"
        return out
