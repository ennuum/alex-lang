# alex: native
# ALEX STANDARD LIBRARY — usb_driver.usb_class
#
# Pilotes de CLASSE USB (au-dessus d'un contrôleur hôte, usb_driver.usb_host_controller) :
#   - interface UsbClassDriver : name(), matches(dev, interface), attach(hc, dev, interface), poll(), describe() ;
#   - HidKeyboard : clavier HID en protocole d'amorçage (SET_PROTOCOL, SET_IDLE), rapports de 8 octets,
#     touches nouvellement enfoncées -> caractères (disposition QWERTY US, Maj, Verr. Maj), file de saisie ;
#   - HidMouse : souris HID d'amorçage : boutons, déplacements relatifs, molette, position cumulée ;
#   - MassStorage : stockage de masse « Bulk-Only Transport » + commandes SCSI (INQUIRY, TEST UNIT READY,
#     READ CAPACITY (10), READ (10), WRITE (10), SYNCHRONIZE CACHE) ; c'est un BlockDevice
#     (storage_driver.block_device) : partitions, cache, systèmes de fichiers fonctionnent dessus.
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use hw
use driver.driver_errors as de
use usb.usb_descriptor as ud
from usb.usb_descriptor use InterfaceDescriptor, EndpointDescriptor
use usb_driver.usb_host_controller as uhc
from usb_driver.usb_host_controller use HostController, UsbDev
use storage_driver.block_device as bd
from storage_driver.block_device use BlockDevice

interface UsbClassDriver:
    func name() -> str
    func matches(dev: UsbDev, itf: InterfaceDescriptor) -> bool
    func attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor)
    # Interroge le périphérique (sans bloquer longtemps) ; renvoie le nombre d'événements obtenus.
    func poll() -> int
    func describe() -> str

# ---------------------------------------------------------------- clavier
const MOD_LCTRL := 0x01
const MOD_LSHIFT := 0x02
const MOD_LALT := 0x04
const MOD_RSHIFT := 0x20

class HidKeyboard implements UsbClassDriver:
    hc: HostController?
    dev: UsbDev?
    endpoint: int := 0x81
    packet: int := 8
    buffer: int := 0
    previous: list[int] := []
    text: str := ""
    keys: list[int] := []           # codes HID enfoncés, dans l'ordre
    caps: bool := false
    modifiers: int := 0
    reports: int := 0
    pipe: int := -1

    func init():
        self.hc = null
        self.dev = null
        self.pipe = -1
        self.previous = [0, 0, 0, 0, 0, 0]
        self.text = ""
        self.keys = []
        self.caps = false
        self.modifiers = 0
        self.reports = 0

    func name() -> str:
        return "clavier HID"

    func matches(dev: UsbDev, itf: InterfaceDescriptor) -> bool:
        return itf.is_boot_keyboard()

    func attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor):
        self.hc = hc
        self.dev = dev
        e := itf.endpoint(ud.EP_INTERRUPT, true)
        if e != null:
            self.endpoint = e.address
            self.packet = e.packet_size()
        self.buffer = hw.alloc_pages(1)
        hc.control(dev, ud.hid_set_protocol(itf.number, 0), self.buffer)
        try:
            hc.control(dev, ud.hid_set_idle(itf.number, 0), self.buffer)
        catch e2:
            self.reports = 0          # SET_IDLE est facultatif (STALL toléré)
        self.pipe = hc.interrupt_open(dev, self.endpoint, self.packet)

    func _read(length: int) -> int:
        h := self.hc
        if h != null:
            return h.interrupt_read(self.pipe, self.buffer)
        return -1

    func poll() -> int:
        n := self._read(8)
        if n < 3:
            return 0
        self.reports += 1
        self.modifiers = hw.peek8(self.buffer)
        events := 0
        k := 2
        while k < 8 and k < n:
            code := hw.peek8(self.buffer + k)
            if code > 3 and not _has(self.previous, code):
                append(self.keys, code)
                self._type(code)
                events += 1
            k += 1
        self.previous = [hw.peek8(self.buffer + i) for i in 2..8]
        return events

    func _type(code: int):
        if code == 57:
            self.caps = not self.caps
            return
        shift := self.modifiers & (MOD_LSHIFT | MOD_RSHIFT) != 0
        c := usage_char(code, shift, self.caps)
        if c != "":
            self.text = self.text + c

    # Texte tapé depuis le dernier appel (vidé).
    func take_text() -> str:
        t := self.text
        self.text = ""
        return t

    func describe() -> str:
        return "clavier USB (EP " + ud._hex2(self.endpoint) + "), " + str(self.reports) + " rapports"

func _has(xs: list[int], v: int) -> bool:
    for x in xs:
        if x == v:
            return true
    return false

# Code d'usage HID (page clavier) -> caractère (QWERTY US) ; "" pour les touches sans caractère.
func usage_char(code: int, shift: bool, caps: bool) -> str:
    lower := "abcdefghijklmnopqrstuvwxyz"
    upper := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    if code >= 4 and code <= 29:
        up := shift != caps
        if up:
            return str(upper[code - 4])
        return str(lower[code - 4])
    digits := "1234567890"
    shifted_digits := "!@#$%^&*()"
    if code >= 30 and code <= 39:
        if shift:
            return str(shifted_digits[code - 30])
        return str(digits[code - 30])
    if code == 40:
        return "\n"
    if code == 42:
        return "\u0008"
    if code == 43:
        return "\t"
    if code == 44:
        return " "
    plain := "-=[]\\#;'`,./"
    shifted := "_+{}|~:\"~<>?"
    if code >= 45 and code <= 56:
        if shift:
            return str(shifted[code - 45])
        return str(plain[code - 45])
    return ""

# ---------------------------------------------------------------- souris
class HidMouse implements UsbClassDriver:
    hc: HostController?
    dev: UsbDev?
    endpoint: int := 0x81
    packet: int := 4
    buffer: int := 0
    buttons: int := 0
    x: int := 0
    y: int := 0
    wheel: int := 0
    reports: int := 0
    pipe: int := -1

    func init():
        self.hc = null
        self.dev = null
        self.pipe = -1
        self.buttons = 0
        self.x = 0
        self.y = 0
        self.wheel = 0
        self.reports = 0

    func name() -> str:
        return "souris HID"

    func matches(dev: UsbDev, itf: InterfaceDescriptor) -> bool:
        return itf.is_boot_mouse()

    func attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor):
        self.hc = hc
        self.dev = dev
        e := itf.endpoint(ud.EP_INTERRUPT, true)
        if e != null:
            self.endpoint = e.address
            self.packet = e.packet_size()
        self.buffer = hw.alloc_pages(1)
        hc.control(dev, ud.hid_set_protocol(itf.number, 0), self.buffer)
        self.pipe = hc.interrupt_open(dev, self.endpoint, self.packet)

    func _read(length: int) -> int:
        h := self.hc
        if h != null:
            return h.interrupt_read(self.pipe, self.buffer)
        return -1

    func poll() -> int:
        n := self._read(self.packet)
        if n < 3:
            return 0
        self.reports += 1
        self.buttons = hw.peek8(self.buffer)
        self.x += _signed8(hw.peek8(self.buffer + 1))
        self.y += _signed8(hw.peek8(self.buffer + 2))
        if n >= 4:
            self.wheel += _signed8(hw.peek8(self.buffer + 3))
        return 1

    func left() -> bool:
        return self.buttons & 1 != 0

    func right() -> bool:
        return self.buttons & 2 != 0

    func describe() -> str:
        return "souris USB : position (" + str(self.x) + ", " + str(self.y) + "), boutons " + str(self.buttons)

func _signed8(v: int) -> int:
    if v >= 128:
        return v - 256
    return v

# ---------------------------------------------------------------- stockage de masse (BOT + SCSI)
class MassStorage implements UsbClassDriver, BlockDevice:
    hc: HostController?
    dev: UsbDev?
    bulk_in: int := 0x81
    bulk_out: int := 0x02
    packet: int := 64
    buf: int := 0
    tag: int := 1
    blocks: int := 0
    bsize: int := 512
    vendor: str := ""
    product: str := ""
    label: str := "usb0"
    ready: bool := false

    func init(label: str):
        self.hc = null
        self.dev = null
        self.tag = 1
        self.label = label
        self.ready = false

    func name() -> str:
        return self.label

    func matches(dev: UsbDev, itf: InterfaceDescriptor) -> bool:
        return itf.iclass == ud.CLASS_MASS_STORAGE and itf.subclass == 6 and itf.protocol == 0x50

    func attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor):
        self.hc = hc
        self.dev = dev
        ei := itf.endpoint(ud.EP_BULK, true)
        eo := itf.endpoint(ud.EP_BULK, false)
        if ei == null or eo == null:
            de.unsupported(self.label, "points d'accès bloc absents")
        if ei != null:
            self.bulk_in = ei.address
            self.packet = ei.packet_size()
        if eo != null:
            self.bulk_out = eo.address
        self.buf = hw.alloc_pages(2)
        data := self.buf + 1024
        self._scsi([0x12, 0, 0, 0, 36, 0], 36, true, data)            # INQUIRY
        self.vendor = _trim_ascii(data + 8, 8)
        self.product = _trim_ascii(data + 16, 16)
        k := 0
        while k < 5:
            try:
                self._scsi([0, 0, 0, 0, 0, 0], 0, true, data)          # TEST UNIT READY
                break
            catch e:
                k += 1
        self._scsi([0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0], 8, true, data)  # READ CAPACITY (10)
        last := (hw.peek8(data) << 24) | (hw.peek8(data + 1) << 16) | (hw.peek8(data + 2) << 8) | hw.peek8(data + 3)
        self.bsize = (hw.peek8(data + 4) << 24) | (hw.peek8(data + 5) << 16) | (hw.peek8(data + 6) << 8) | hw.peek8(data + 7)
        self.blocks = last + 1
        self.ready = true

    # Commande SCSI par BOT : CBW (31 octets), données (length octets à data), CSW (13 octets).
    func _bulk(ep: int, addr: int, length: int) -> int:
        h := self.hc
        d := self.dev
        if h != null:
            if d != null:
                return h.bulk(d, ep, self.packet, addr, length, 1000000)
        de.fail(self.label, "non attaché")
        return -1

    func _scsi(cdb: list[int], length: int, input: bool, data: int):
        cbw := self.buf
        hw.zero(cbw, 31)
        hw.poke32(cbw, 0x43425355)            # « USBC »
        hw.poke32(cbw + 4, self.tag)
        hw.poke32(cbw + 8, length)
        if input:
            hw.poke8(cbw + 12, 0x80)
        hw.poke8(cbw + 14, len(cdb))
        k := 0
        while k < len(cdb):
            hw.poke8(cbw + 15 + k, cdb[k])
            k += 1
        self._bulk(self.bulk_out, cbw, 31)
        if length > 0:
            if input:
                self._bulk(self.bulk_in, data, length)
            else:
                self._bulk(self.bulk_out, data, length)
        csw := self.buf + 64
        n := self._bulk(self.bulk_in, csw, 13)
        if n != 13 or hw.peek32(csw) != 0x53425355:
            de.io_error(self.label, "CSW invalide", n)
        if hw.peek32(csw + 4) != self.tag:
            de.io_error(self.label, "étiquette du CSW", hw.peek32(csw + 4))
        self.tag += 1
        status := hw.peek8(csw + 12)
        if status != 0:
            de.io_error(self.label, "commande SCSI " + str(cdb[0]) + " en échec", status)

    func block_size() -> int:
        return self.bsize

    func block_count() -> int:
        return self.blocks

    func read_only() -> bool:
        return false

    func _rw(op: int, lba: int, count: int, buf: int, input: bool):
        bd.check_range(self, lba, count)
        limit := 4096 // self.bsize
        done := 0
        while done < count:
            n := count - done
            if n > limit:
                n = limit
            l := lba + done
            self._scsi([op, 0, (l >> 24) & 255, (l >> 16) & 255, (l >> 8) & 255, l & 255, 0, (n >> 8) & 255, n & 255, 0], n * self.bsize, input, buf + done * self.bsize)
            done += n

    func read_blocks(lba: int, count: int, buf: int) -> bool:
        self._rw(0x28, lba, count, buf, true)
        return true

    func write_blocks(lba: int, count: int, buf: int) -> bool:
        self._rw(0x2A, lba, count, buf, false)
        return true

    func flush() -> bool:
        self._scsi([0x35, 0, 0, 0, 0, 0, 0, 0, 0, 0], 0, false, self.buf)
        return true

    func poll() -> int:
        return 0

    func describe() -> str:
        return bd.describe(self) + ", " + self.vendor + " " + self.product + " (USB)"

func _trim_ascii(addr: int, n: int) -> str:
    chars := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    out := ""
    pending := ""
    k := 0
    while k < n:
        ch := hw.peek8(addr + k)
        if ch == 32 or ch == 0:
            if out != "":
                pending = pending + " "
        elif ch > 32 and ch < 127:
            out = out + pending + str(chars[ch - 32])
            pending = ""
        k += 1
    return out
