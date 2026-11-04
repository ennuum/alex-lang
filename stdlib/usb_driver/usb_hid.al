# alex: native
# ALEX STANDARD LIBRARY — usb_driver.usb_hid
#
# HID générique (au-delà du protocole d'amorçage de usb_class) : analyse du DESCRIPTEUR DE RAPPORT et
# décodage des rapports de n'importe quel périphérique HID (claviers complets, souris à molettes et
# boutons multiples, manettes, tablettes, touches multimédia).
#   - parse_report_descriptor : éléments courts (Main / Global / Local), pile Push / Pop, identifiants de
#     rapport, collections ; produit une liste de HidField (sorte input / output / feature, identifiant,
#     décalage en bits, taille, nombre, page d'usage, usages ou intervalle d'usages, bornes logiques, drapeaux
#     constante / variable / relatif) ;
#   - ReportLayout : longueurs des rapports par identifiant, decode(adresse, n) -> HidValue (page, usage,
#     valeur signée selon les bornes) ; champs « tableau » (touches enfoncées) traduits en usages ;
#   - device_kind : clavier, souris, manette, joystick, multimédia, d'après la collection d'application ;
#   - HidDevice : pilote de classe (UsbClassDriver) : lit le descripteur de rapport, ouvre le point
#     d'interruption, poll() décode et garde les dernières valeurs (value(page, usage)).
#
#   use usb_driver.usb_hid as hid
#   lay := hid.parse_bytes(octets_du_descripteur)
#   for f in lay.fields: print(f.describe())
#   for v in lay.decode(adresse_rapport, 4): print(v.describe())    # « page 9 usage 1 = 1 » (bouton 1)
#
# Erreurs : UsbProtocolError (descripteur mal formé : End Collection sans Collection, Pop sans Push, rapport
# trop court). Compilable en natif.

from core use len
from collections use append
use hw
use usb.usb_descriptor as ud
from usb.usb_descriptor use InterfaceDescriptor
use usb_driver.usb_host_controller as uhc
from usb_driver.usb_host_controller use HostController, UsbDev
use usb_driver.usb_class as uc
from usb_driver.usb_class use UsbClassDriver

const INPUT := 1
const OUTPUT := 2
const FEATURE := 3

const PAGE_GENERIC := 0x01
const PAGE_KEYBOARD := 0x07
const PAGE_LED := 0x08
const PAGE_BUTTON := 0x09
const PAGE_CONSUMER := 0x0C

func kind_name(k: int) -> str:
    if k == INPUT:
        return "input"
    if k == OUTPUT:
        return "output"
    return "feature"

class HidField:
    kind: int := 1
    report_id: int := 0
    bit_offset: int := 0
    size: int := 0
    count: int := 0
    usage_page: int := 0
    usages: list[int] := []
    usage_min: int := 0
    usage_max: int := -1
    logical_min: int := 0
    logical_max: int := 0
    flags: int := 0
    collection: int := 0       # usage de la collection d'application englobante

    func init(kind: int, report_id: int, bit_offset: int, size: int, count: int):
        self.kind = kind
        self.report_id = report_id
        self.bit_offset = bit_offset
        self.size = size
        self.count = count
        self.usages = []
        self.usage_min = 0
        self.usage_max = -1

    func constant() -> bool:
        return self.flags & 1 != 0

    func variable() -> bool:
        return self.flags & 2 != 0

    func relative() -> bool:
        return self.flags & 4 != 0

    # Usage du i-ème élément d'un champ variable.
    func usage_of(i: int) -> int:
        if len(self.usages) > 0:
            if i < len(self.usages):
                return self.usages[i]
            return self.usages[len(self.usages) - 1]
        if self.usage_max >= self.usage_min:
            u := self.usage_min + i
            return u if u <= self.usage_max else self.usage_max
        return 0

    func describe() -> str:
        t := kind_name(self.kind)
        if self.report_id != 0:
            t = t + " #" + str(self.report_id)
        t = t + " bit " + str(self.bit_offset) + " : " + str(self.count) + " x " + str(self.size) + " bits"
        if self.constant():
            return t + " (remplissage)"
        t = t + " page " + str(self.usage_page)
        if len(self.usages) > 0:
            t = t + " usages"
            for u in self.usages:
                t = t + " " + str(u)
        elif self.usage_max >= self.usage_min:
            t = t + " usages " + str(self.usage_min) + ".." + str(self.usage_max)
        t = t + " [" + str(self.logical_min) + ", " + str(self.logical_max) + "]"
        if not self.variable():
            t = t + " tableau"
        if self.relative():
            t = t + " relatif"
        return t

class HidValue:
    page: int := 0
    usage: int := 0
    value: int := 0

    func init(page: int, usage: int, value: int):
        self.page = page
        self.usage = usage
        self.value = value

    func describe() -> str:
        return "page " + str(self.page) + " usage " + str(self.usage) + " = " + str(self.value)

class _Globals:
    page: int := 0
    lmin: int := 0
    lmax: int := 0
    size: int := 0
    count: int := 0
    report_id: int := 0

    func init():
        self.page = 0

    func copy() -> _Globals:
        g := _Globals()
        g.page = self.page
        g.lmin = self.lmin
        g.lmax = self.lmax
        g.size = self.size
        g.count = self.count
        g.report_id = self.report_id
        return g

class _Offset:
    kind: int := 0
    report_id: int := 0
    bits: int := 0

    func init(kind: int, report_id: int):
        self.kind = kind
        self.report_id = report_id
        self.bits = 0

class ReportLayout:
    fields: list[HidField] := []
    offsets: list[_Offset] := []
    applications: list[int] := []    # (page << 16) | usage des collections d'application
    uses_ids: bool := false

    func init():
        self.fields = []
        self.offsets = []
        self.applications = []
        self.uses_ids = false

    func _offset(kind: int, rid: int) -> _Offset:
        for o in self.offsets:
            if o.kind == kind and o.report_id == rid:
                return o
        o := _Offset(kind, rid)
        append(self.offsets, o)
        return o

    # Longueur en octets d'un rapport (identifiant compris s'il y en a).
    func report_bytes(kind: int, rid: int) -> int:
        for o in self.offsets:
            if o.kind == kind and o.report_id == rid:
                n := (o.bits + 7) // 8
                if self.uses_ids:
                    n += 1
                return n
        return 0

    func report_ids(kind: int) -> list[int]:
        out: list[int] := []
        for o in self.offsets:
            if o.kind == kind:
                append(out, o.report_id)
        return out

    # Valeurs du rapport d'entrée de n octets en addr.
    func decode(addr: int, n: int) -> list[HidValue]:
        out: list[HidValue] := []
        rid := 0
        base := addr
        avail := n
        if self.uses_ids:
            if n < 1:
                raise("UsbProtocolError", "rapport HID vide")
            rid = hw.peek8(addr)
            base = addr + 1
            avail = n - 1
        for f in self.fields:
            if f.kind != INPUT or f.report_id != rid or f.constant():
                continue
            i := 0
            while i < f.count:
                bit := f.bit_offset + i * f.size
                if bit + f.size > avail * 8:
                    raise("UsbProtocolError", "rapport HID trop court (" + str(n) + " octets)")
                raw := extract_bits(base, bit, f.size)
                v := raw
                if f.logical_min < 0 and f.size > 0 and raw >= (1 << (f.size - 1)):
                    v = raw - (1 << f.size)
                if f.variable():
                    append(out, HidValue(f.usage_page, f.usage_of(i), v))
                else:
                    # tableau : la valeur est un indice d'usage ; 0 / hors bornes : rien
                    if v >= f.logical_min and v <= f.logical_max and v != 0:
                        u := v
                        if f.usage_max >= f.usage_min and len(f.usages) == 0:
                            u = f.usage_min + (v - f.logical_min)
                        elif len(f.usages) > 0:
                            idx := v - f.logical_min
                            u = f.usages[idx] if idx < len(f.usages) else v
                        append(out, HidValue(f.usage_page, u, 1))
                i += 1
        return out

func extract_bits(addr: int, bit: int, size: int) -> int:
    v := 0
    k := 0
    while k < size:
        b := bit + k
        if (hw.peek8(addr + b // 8) >> (b % 8)) & 1 != 0:
            v = v | (1 << k)
        k += 1
    return v

func _signed(v: int, bytes: int) -> int:
    if bytes == 1 and v >= 0x80:
        return v - 0x100
    if bytes == 2 and v >= 0x8000:
        return v - 0x10000
    if bytes == 4 and v >= 0x80000000:
        return v - 0x100000000
    return v

# Analyse n octets de descripteur de rapport en addr.
func parse_report_descriptor(addr: int, n: int) -> ReportLayout:
    lay := ReportLayout()
    g := _Globals()
    stack: list[_Globals] := []
    usages: list[int] := []
    umin := 0
    umax := -1
    depth := 0
    app := 0
    pos := 0
    while pos < n:
        prefix := hw.peek8(addr + pos)
        if prefix == 0xFE:
            if pos + 2 >= n:
                break
            pos += 3 + hw.peek8(addr + pos + 1)
            continue
        sz := prefix & 3
        if sz == 3:
            sz = 4
        typ := (prefix >> 2) & 3
        tag := prefix >> 4
        if pos + 1 + sz > n:
            raise("UsbProtocolError", "descripteur de rapport tronqué à l'octet " + str(pos))
        data := 0
        k := 0
        while k < sz:
            data = data | (hw.peek8(addr + pos + 1 + k) << (8 * k))
            k += 1
        pos += 1 + sz
        if typ == 0:
            if tag == 8 or tag == 9 or tag == 11:
                kind := INPUT
                if tag == 9:
                    kind = OUTPUT
                elif tag == 11:
                    kind = FEATURE
                o := lay._offset(kind, g.report_id)
                f := HidField(kind, g.report_id, o.bits, g.size, g.count)
                f.usage_page = g.page
                f.logical_min = g.lmin
                f.logical_max = g.lmax
                f.flags = data
                f.collection = app
                for u in usages:
                    append(f.usages, u)
                f.usage_min = umin
                f.usage_max = umax
                append(lay.fields, f)
                o.bits = o.bits + g.size * g.count
            elif tag == 10:
                if data == 1 and depth == 0:
                    u := 0
                    if len(usages) > 0:
                        u = usages[0]
                    app = (g.page << 16) | u
                    append(lay.applications, app)
                depth += 1
            elif tag == 12:
                if depth == 0:
                    raise("UsbProtocolError", "End Collection sans Collection")
                depth -= 1
            usages = []
            umin = 0
            umax = -1
        elif typ == 1:
            if tag == 0:
                g.page = data
            elif tag == 1:
                g.lmin = _signed(data, sz)
            elif tag == 2:
                g.lmax = data
                if g.lmin < 0:
                    g.lmax = _signed(data, sz)
            elif tag == 7:
                g.size = data
            elif tag == 8:
                g.report_id = data
                lay.uses_ids = true
            elif tag == 9:
                g.count = data
            elif tag == 10:
                append(stack, g.copy())
            elif tag == 11:
                if len(stack) == 0:
                    raise("UsbProtocolError", "Pop sans Push")
                g = stack[len(stack) - 1]
                rest: list[_Globals] := []
                j := 0
                while j < len(stack) - 1:
                    append(rest, stack[j])
                    j += 1
                stack = rest
        elif typ == 2:
            if tag == 0:
                append(usages, data & 0xFFFF)
            elif tag == 1:
                umin = data
            elif tag == 2:
                umax = data
    if depth != 0:
        raise("UsbProtocolError", "collection non fermée")
    return lay

func parse_bytes(bytes: list[int]) -> ReportLayout:
    a := hw.alloc_pages((len(bytes) + 4095) // 4096 + 1)
    i := 0
    while i < len(bytes):
        hw.poke8(a + i, bytes[i])
        i += 1
    lay := parse_report_descriptor(a, len(bytes))
    hw.free_pages(a, (len(bytes) + 4095) // 4096 + 1)
    return lay

func device_kind(lay: ReportLayout) -> str:
    for a in lay.applications:
        page := a >> 16
        u := a & 0xFFFF
        if page == PAGE_GENERIC:
            if u == 6:
                return "clavier"
            if u == 2:
                return "souris"
            if u == 5:
                return "manette"
            if u == 4:
                return "joystick"
        if page == PAGE_CONSUMER and u == 1:
            return "multimédia"
        if page == 0x0D:
            return "tablette / écran tactile"
    return "HID"

# Descripteurs de référence (souris 3 boutons + molette, clavier d'amorçage) pour les tests et la
# documentation.
func mouse_descriptor() -> list[int]:
    return [0x05, 0x01, 0x09, 0x02, 0xA1, 0x01, 0x09, 0x01, 0xA1, 0x00, 0x05, 0x09, 0x19, 0x01, 0x29, 0x03, 0x15, 0x00, 0x25, 0x01, 0x95, 0x03, 0x75, 0x01, 0x81, 0x02, 0x95, 0x01, 0x75, 0x05, 0x81, 0x01, 0x05, 0x01, 0x09, 0x30, 0x09, 0x31, 0x09, 0x38, 0x15, 0x81, 0x25, 0x7F, 0x75, 0x08, 0x95, 0x03, 0x81, 0x06, 0xC0, 0xC0]

func keyboard_descriptor() -> list[int]:
    return [0x05, 0x01, 0x09, 0x06, 0xA1, 0x01, 0x05, 0x07, 0x19, 0xE0, 0x29, 0xE7, 0x15, 0x00, 0x25, 0x01, 0x75, 0x01, 0x95, 0x08, 0x81, 0x02, 0x95, 0x01, 0x75, 0x08, 0x81, 0x01, 0x95, 0x05, 0x75, 0x01, 0x05, 0x08, 0x19, 0x01, 0x29, 0x05, 0x91, 0x02, 0x95, 0x01, 0x75, 0x03, 0x91, 0x01, 0x95, 0x06, 0x75, 0x08, 0x15, 0x00, 0x25, 0x65, 0x05, 0x07, 0x19, 0x00, 0x29, 0x65, 0x81, 0x00, 0xC0]

class HidDevice implements UsbClassDriver:
    hc: HostController?
    dev: UsbDev?
    layout: ReportLayout
    endpoint: int := 0x81
    packet: int := 8
    buffer: int := 0
    pipe: int := -1
    reports: int := 0
    last: list[HidValue] := []
    kind: str := "HID"

    func init():
        self.hc = null
        self.dev = null
        self.layout = ReportLayout()
        self.pipe = -1
        self.reports = 0
        self.last = []
        self.kind = "HID"

    func name() -> str:
        return "HID générique"

    func matches(dev: UsbDev, itf: InterfaceDescriptor) -> bool:
        return itf.iclass == ud.CLASS_HID

    func attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor):
        self.hc = hc
        self.dev = dev
        e := itf.endpoint(ud.EP_INTERRUPT, true)
        if e != null:
            self.endpoint = e.address
            self.packet = e.packet_size()
        self.buffer = hw.alloc_pages(1)
        n := itf.hid_report_length
        if n <= 0 or n > 4096:
            n = 512
        got := hc.control(dev, ud.hid_get_report_descriptor(itf.number, n), self.buffer)
        self.layout = parse_report_descriptor(self.buffer, got)
        self.kind = device_kind(self.layout)
        if itf.subclass == 1:
            try:
                hc.control(dev, ud.hid_set_protocol(itf.number, 1), self.buffer)
            catch e2:
                self.reports = 0
        self.pipe = hc.interrupt_open(dev, self.endpoint, self.packet)

    func poll() -> int:
        h := self.hc
        if h == null:
            return 0
        n := h.interrupt_read(self.pipe, self.buffer)
        if n <= 0:
            return 0
        self.reports += 1
        self.last = self.layout.decode(self.buffer, n)
        return len(self.last)

    func value(page: int, usage: int) -> int:
        for v in self.last:
            if v.page == page and v.usage == usage:
                return v.value
        return 0

    func pressed(page: int) -> list[int]:
        out: list[int] := []
        for v in self.last:
            if v.page == page and v.value != 0:
                append(out, v.usage)
        return out

    func describe() -> str:
        return self.kind + " USB (EP " + ud._hex2(self.endpoint) + "), " + str(len(self.layout.fields)) + " champs, " + str(self.reports) + " rapports"
