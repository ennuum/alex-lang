# alex: native
# ALEX STANDARD LIBRARY — driver.driver_info
#
# Ce qu'un pilote déclare et ce qu'il pilote :
#   - DriverInfo : nom, version, auteur, description, bus ("pci", "usb", "isa", "platform", "virtual") et table
#     des périphériques reconnus (DeviceId) ;
#   - DeviceId : motif de correspondance (fabricant, modèle, classe, sous-classe, interface ; -1 = indifférent,
#     ou un nom pour les périphériques de plate-forme / ISA) ;
#   - HwDevice : un périphérique concret présenté aux pilotes : bus, emplacement, identifiants, classe, ligne
#     d'interruption, ressources (ports, zones MMIO), et, pour PCI, son pci.pci_device.PciDevice.
#
#   use driver.driver_info as di
#   info := di.DriverInfo("e1000", "1.0", "réseau Intel PRO/1000", "pci")
#   info.add_id(di.pci_id(0x8086, 0x100E))
#   info.add_id(di.pci_class(0x02, 0x00))
#   score := info.matches(dev)            # 0 : non ; plus grand = plus précis
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use pci.pci_device as pd
from pci.pci_device use PciDevice
use pci.pci_ids as ids

const ANY := -1

class DeviceId:
    vendor: int := -1
    device: int := -1
    cls: int := -1
    subclass: int := -1
    prog_if: int := -1
    name: str := ""

    func init(vendor: int, device: int, cls: int, subclass: int, prog_if: int, name: str):
        self.vendor = vendor
        self.device = device
        self.cls = cls
        self.subclass = subclass
        self.prog_if = prog_if
        self.name = name

    # Précision de la correspondance avec dev (0 : aucune). Un identifiant exact (fabricant + modèle) l'emporte
    # sur une classe ; un nom exact sur le reste.
    func score(dev: HwDevice) -> int:
        if self.name != "":
            if self.name == dev.name:
                return 100
            return 0
        s := 1
        if self.vendor != -1:
            if self.vendor != dev.vendor:
                return 0
            s += 20
        if self.device != -1:
            if self.device != dev.device:
                return 0
            s += 40
        if self.cls != -1:
            if self.cls != dev.cls:
                return 0
            s += 4
        if self.subclass != -1:
            if self.subclass != dev.subclass:
                return 0
            s += 4
        if self.prog_if != -1:
            if self.prog_if != dev.prog_if:
                return 0
            s += 2
        return s

    func describe() -> str:
        if self.name != "":
            return "nom " + self.name
        t := ""
        if self.vendor != -1:
            t = ids.hex16(self.vendor) + ":"
            if self.device != -1:
                t = t + ids.hex16(self.device)
            else:
                t = t + "*"
        if self.cls != -1:
            if t != "":
                t = t + " "
            t = t + "classe " + ids.hex8(self.cls)
            if self.subclass != -1:
                t = t + ids.hex8(self.subclass)
            if self.prog_if != -1:
                t = t + "." + ids.hex8(self.prog_if)
        return t

func pci_id(vendor: int, device: int) -> DeviceId:
    return DeviceId(vendor, device, -1, -1, -1, "")

func pci_class(cls: int, subclass: int) -> DeviceId:
    return DeviceId(-1, -1, cls, subclass, -1, "")

func pci_class_if(cls: int, subclass: int, prog_if: int) -> DeviceId:
    return DeviceId(-1, -1, cls, subclass, prog_if, "")

func vendor_any(vendor: int) -> DeviceId:
    return DeviceId(vendor, -1, -1, -1, -1, "")

func named(name: str) -> DeviceId:
    return DeviceId(-1, -1, -1, -1, -1, name)

class DriverInfo:
    name: str := ""
    version: str := ""
    description: str := ""
    bus: str := ""
    author: str := ""
    ids: list[DeviceId] := []

    func init(name: str, version: str, description: str, bus: str):
        self.name = name
        self.version = version
        self.description = description
        self.bus = bus
        self.author = ""
        self.ids = []

    func add_id(d: DeviceId) -> DriverInfo:
        append(self.ids, d)
        return self

    # Meilleur score des identifiants pour dev (0 : le pilote ne le reconnaît pas ; bus différent : 0).
    func matches(dev: HwDevice) -> int:
        if self.bus != "" and self.bus != dev.bus:
            return 0
        best := 0
        for d in self.ids:
            s := d.score(dev)
            if s > best:
                best = s
        return best

    func describe() -> str:
        t := self.name + " " + self.version + " (" + self.bus + ") — " + self.description
        if len(self.ids) > 0:
            t = t + " ; reconnaît :"
            for d in self.ids:
                t = t + " [" + d.describe() + "]"
        return t

# ---------------------------------------------------------------- périphérique présenté aux pilotes
class Resource:
    kind: str := ""          # "io", "mem", "irq", "dma"
    start: int := 0
    size: int := 0

    func init(kind: str, start: int, size: int):
        self.kind = kind
        self.start = start
        self.size = size

    func describe() -> str:
        if self.kind == "irq" or self.kind == "dma":
            return self.kind + " " + str(self.start)
        return self.kind + " " + str(self.start) + "+" + str(self.size)

class HwDevice:
    bus: str := ""
    location: str := ""
    name: str := ""
    vendor: int := -1
    device: int := -1
    cls: int := -1
    subclass: int := -1
    prog_if: int := -1
    irq: int := -1
    resources: list[Resource] := []
    pci: PciDevice?
    state: str := "nouveau"        # nouveau, lié, échec, retiré

    func init(bus: str, location: str, name: str):
        self.bus = bus
        self.location = location
        self.name = name
        self.vendor = -1
        self.device = -1
        self.cls = -1
        self.subclass = -1
        self.prog_if = -1
        self.irq = -1
        self.resources = []
        self.pci = null
        self.state = "nouveau"

    func add_resource(kind: str, start: int, size: int):
        append(self.resources, Resource(kind, start, size))

    # Première ressource de cette sorte (index-ième : 0, 1...), ou null.
    func resource(kind: str, index: int) -> Resource?:
        k := 0
        for r in self.resources:
            if r.kind == kind:
                if k == index:
                    return r
                k += 1
        return null

    func io_base(index: int) -> int:
        r := self.resource("io", index)
        if r == null:
            return -1
        return r.start

    func mem_base(index: int) -> int:
        r := self.resource("mem", index)
        if r == null:
            return -1
        return r.start

    func describe() -> str:
        t := self.bus + " " + self.location + " " + self.name
        if self.vendor != -1:
            t = t + " [" + ids.hex16(self.vendor) + ":" + ids.hex16(self.device) + "]"
        if self.irq >= 0:
            t = t + " irq " + str(self.irq)
        return t

# Périphérique PCI : identifiants, BAR (ressources io / mem), ligne d'interruption.
func from_pci(d: PciDevice) -> HwDevice:
    h := HwDevice("pci", d.location(), d.name())
    h.vendor = d.vendor
    h.device = d.device
    h.cls = d.cls
    h.subclass = d.subclass
    h.prog_if = d.prog_if
    if d.irq_pin != 0:
        h.irq = d.irq_line
    if d.header_kind() == 0:
        for b in d.bars():
            if b.is_io:
                h.add_resource("io", b.address, b.size)
            else:
                h.add_resource("mem", b.address, b.size)
    h.pci = d
    return h

# Périphérique ISA / de plate-forme à ressources fixes (ports, ligne d'interruption ; -1 : aucune).
func platform(name: str, io_start: int, io_size: int, irq: int) -> HwDevice:
    h := HwDevice("platform", name, name)
    if io_size > 0:
        h.add_resource("io", io_start, io_size)
    if irq >= 0:
        h.irq = irq
        h.add_resource("irq", irq, 1)
    return h
