# alex: native
# ALEX STANDARD LIBRARY — driver.driver_manager
#
# Le gestionnaire de pilotes : il connaît les pilotes (DriverRegistry), les périphériques (énumération PCI,
# périphériques de plate-forme / ISA déclarés), et les lie : pour chaque périphérique, les pilotes candidats
# sont essayés du plus précis au moins précis (probe puis attach) jusqu'à ce que l'un le prenne. Un journal
# garde ce qui s'est passé ; un rappel prévient de chaque liaison.
#
#   use driver.driver_manager as dmg
#   m := dmg.DriverManager()
#   m.register(Ata())
#   m.add_pci_bus(PciBus(PortConfig()))
#   m.add_device(di.platform("com1", 0x3F8, 8, 4))
#   n := m.bind_all()
#   print(m.report())
#   d := m.driver_of("00:03.0")
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use pci.pci_bus as pbus
from pci.pci_bus use PciBus
use driver.driver as drv
from driver.driver use Driver
use driver.driver_info as di
from driver.driver_info use HwDevice
use driver.driver_registry as dr
from driver.driver_registry use DriverRegistry
use driver.device_binding as dbind
from driver.device_binding use Binding

class DriverManager:
    registry: DriverRegistry
    devices: list[HwDevice] := []
    bindings: list[Binding] := []
    log: list[str] := []
    on_bind: func(Binding)?

    func init():
        self.registry = DriverRegistry()
        self.devices = []
        self.bindings = []
        self.log = []
        self.on_bind = null

    func register(d: Driver):
        self.registry.add(d)
        append(self.log, "pilote " + d.info().name + " " + d.info().version)

    func add_device(h: HwDevice):
        append(self.devices, h)

    # Ajoute toutes les fonctions du bus (sauf les ponts) ; renvoie leur nombre.
    func add_pci_bus(bus: PciBus) -> int:
        n := 0
        for d in bus.scan():
            if d.cls == 6:
                continue
            self.add_device(di.from_pci(d))
            n += 1
        return n

    func notify(f: func(Binding)):
        self.on_bind = f

    func binding_of(h: HwDevice) -> Binding?:
        for b in self.bindings:
            if b.device.bus == h.bus and b.device.location == h.location and b.bound():
                return b
        return null

    # Lie un périphérique : renvoie le lien obtenu (ou le dernier essai), null si aucun pilote ne le reconnaît.
    func bind(h: HwDevice) -> Binding?:
        existing := self.binding_of(h)
        if existing != null:
            return existing
        last: Binding? := null
        for d in self.registry.candidates(h):
            b := Binding(d, h)
            ok := b.bind()
            append(self.log, b.describe())
            append(self.bindings, b)
            last = b
            if ok:
                f := self.on_bind
                if f != null:
                    f(b)
                return b
        if last == null:
            h.state = "sans pilote"
            append(self.log, h.describe() + " : aucun pilote")
        return last

    # Lie tous les périphériques sans pilote ; renvoie le nombre de liaisons réussies.
    func bind_all() -> int:
        n := 0
        for h in self.devices:
            if self.binding_of(h) == null:
                b := self.bind(h)
                if b != null:
                    if b.bound():
                        n += 1
        return n

    func unbind(h: HwDevice) -> bool:
        b := self.binding_of(h)
        if b == null:
            return false
        b.unbind()
        append(self.log, h.describe() + " : détaché")
        return true

    func unbind_all():
        for b in self.bindings:
            if b.bound():
                b.unbind()

    # Pilote lié au périphérique d'emplacement location (« 00:03.0 », nom de plate-forme), ou "".
    func driver_of(location: str) -> str:
        for b in self.bindings:
            if b.device.location == location and b.bound():
                return b.driver_name()
        return ""

    func device(location: str) -> HwDevice?:
        for h in self.devices:
            if h.location == location:
                return h
        return null

    func bound_count() -> int:
        n := 0
        for b in self.bindings:
            if b.bound():
                n += 1
        return n

    func unclaimed() -> list[HwDevice]:
        out: list[HwDevice] := []
        for h in self.devices:
            if self.binding_of(h) == null:
                append(out, h)
        return out

    func report() -> str:
        out := "pilotes : " + str(self.registry.count()) + ", périphériques : " + str(len(self.devices)) + ", liés : " + str(self.bound_count()) + "\n"
        for h in self.devices:
            b := self.binding_of(h)
            if b != null:
                out = out + "  " + h.describe() + " -> " + b.driver_name() + " : " + b.status() + "\n"
            else:
                out = out + "  " + h.describe() + " : " + h.state + "\n"
        return out
