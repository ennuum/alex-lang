# alex: native
# ALEX STANDARD LIBRARY — usb_driver.usb_host_controller
#
# Contrôleurs hôtes USB d'un noyau Alex :
#   - interface HostController : ports racines (connexion, réinitialisation, vitesse), transferts de contrôle,
#     bloc et interruption vers un périphérique (adresse, point d'accès, bascule DATA0 / DATA1) ;
#   - UhciController : UHCI (Intel PIIX3 / PIIX4 / ICH, QEMU « piix3-usb-uhci ») : registres en ports
#     d'entrée-sortie (BAR4), liste de 1024 trames, une file (QH) où s'enchaînent les descripteurs de
#     transfert (TD), paquets de 8 / 64 octets, pleine et basse vitesse ;
#   - UsbDev : un périphérique énuméré (adresse, vitesse, descripteurs, bascules par point d'accès) ;
#   - enumerate(hc, port, adresse) : réinitialisation du port, lecture des descripteurs, SET_ADDRESS,
#     SET_CONFIGURATION.
#
#   hc := UhciController(0xC040)
#   hc.setup()
#   for p in 0..hc.port_count():
#       if hc.port_connected(p):
#           d := enumerate(hc, p, adresse_libre)
#
# Erreurs : DeviceTimeout, DeviceIoError (STALL, erreur de bus), UnsupportedDevice. Compilable en natif.

from collections use append, contains_key
from core use len
use hw
use driver.driver_errors as de
use dma.dma_mapping as dmm
from dma.dma_mapping use DmaPool
use usb.usb_descriptor as ud
from usb.usb_descriptor use DeviceDescriptor, ConfigurationDescriptor, SetupPacket

const SPEED_LOW := 0
const SPEED_FULL := 1
const SPEED_HIGH := 2

const PID_SETUP := 0x2D
const PID_IN := 0x69
const PID_OUT := 0xE1

func speed_name(s: int) -> str:
    if s == SPEED_LOW:
        return "basse vitesse (1,5 Mbit/s)"
    if s == SPEED_FULL:
        return "pleine vitesse (12 Mbit/s)"
    return "haute vitesse (480 Mbit/s)"

# ---------------------------------------------------------------- périphérique énuméré
class UsbDev:
    address: int := 0
    port: int := 0
    speed: int := 1
    max_packet0: int := 8
    descriptor: DeviceDescriptor
    config: ConfigurationDescriptor
    toggles: dict[int, int] := {}
    product: str := ""
    manufacturer: str := ""

    func init(address: int, port: int, speed: int):
        self.address = address
        self.port = port
        self.speed = speed
        self.max_packet0 = 8
        self.descriptor = DeviceDescriptor()
        self.config = ConfigurationDescriptor()
        self.toggles = {}
        self.product = ""
        self.manufacturer = ""

    func low_speed() -> bool:
        return self.speed == SPEED_LOW

    func toggle(ep: int) -> int:
        if contains_key(self.toggles, ep):
            return self.toggles[ep]
        return 0

    func set_toggle(ep: int, v: int):
        self.toggles[ep] = v & 1

    func describe() -> str:
        t := "adresse " + str(self.address) + " (port " + str(self.port) + ", " + speed_name(self.speed) + ") [" + self.descriptor.id_text() + "]"
        if self.product != "":
            t = t + " " + self.product
        return t

interface HostController:
    func name() -> str
    func setup()
    func port_count() -> int
    func port_connected(port: int) -> bool
    # Réinitialise et active le port ; renvoie la vitesse (SPEED_*) ou -1 si rien n'est branché.
    func reset_port(port: int) -> int
    # Transfert de contrôle : setup (8 octets), données à buf (len octets, entrée si setup.is_in()).
    # Renvoie le nombre d'octets de données transférés.
    func control(dev: UsbDev, setup: SetupPacket, buf: int) -> int
    # Bloc / interruption : renvoie les octets transférés, ou -1 (NAK : rien de prêt, pour une interruption
    # avec tries épuisés).
    func bulk(dev: UsbDev, endpoint: int, max_packet: int, buf: int, length: int, tries: int) -> int
    # Point d'accès d'interruption en entrée scruté par le contrôleur lui-même (le transfert reste en file
    # jusqu'à ce que le périphérique réponde) : renvoie un identifiant de tube.
    func interrupt_open(dev: UsbDev, endpoint: int, max_packet: int) -> int
    # Données reçues sur le tube (copiées à buf) : nombre d'octets, ou -1 si rien n'est encore arrivé.
    func interrupt_read(pipe: int, buf: int) -> int

# ---------------------------------------------------------------- UHCI
const UHCI_CMD := 0x00
const UHCI_STS := 0x02
const UHCI_INTR := 0x04
const UHCI_FRNUM := 0x06
const UHCI_FRBASE := 0x08
const UHCI_SOF := 0x0C
const UHCI_PORTSC := 0x10

const TD_ACTIVE := 0x800000
const TD_STALLED := 0x400000
const TD_BUFERR := 0x200000
const TD_BABBLE := 0x100000
const TD_NAK := 0x80000
const TD_CRCTO := 0x40000
const TD_BITSTUFF := 0x20000
const TD_ERRORS := 0x760000
const TD_LS := 0x4000000
const TD_CERR3 := 0x18000000
const TD_SPD := 0x20000000

const TRIES := 3000000

class _IntPipe:
    qh: int := 0
    td: int := 0
    data: int := 0
    dev: UsbDev
    endpoint: int := 0
    max_packet: int := 8
    errors: int := 0

    func init(qh: int, td: int, data: int, dev: UsbDev, endpoint: int, max_packet: int):
        self.qh = qh
        self.td = td
        self.data = data
        self.dev = dev
        self.endpoint = endpoint
        self.max_packet = max_packet
        self.errors = 0

class UhciController implements HostController:
    io: int := 0
    frames: int := 0
    qh: int := 0
    pool: DmaPool
    buffer: int := 0           # tampon de données (4 Kio) pour les transferts
    pipes: list[_IntPipe] := []
    first: int := 0            # première file de la liste des trames (tubes d'interruption, puis qh)
    transfers: int := 0
    errors: int := 0

    func init(io: int):
        self.io = io
        self.pool = DmaPool(32)
        self.pipes = []
        self.transfers = 0
        self.errors = 0

    func name() -> str:
        return "UHCI (ports " + str(self.io) + ")"

    func setup():
        # réinitialisation globale puis du contrôleur
        hw.outw(self.io + UHCI_CMD, 4)
        de.io_delay(10000)
        hw.outw(self.io + UHCI_CMD, 0)
        hw.outw(self.io + UHCI_CMD, 2)
        if not de.wait_until(() => hw.inw(self.io + UHCI_CMD) & 2 == 0, TRIES):
            de.timeout("uhci", "réinitialisation")
        hw.outw(self.io + UHCI_INTR, 0)
        self.frames = hw.alloc_pages(1)
        self.qh = self.pool.alloc()
        hw.poke32(self.qh, 1)               # tête : fin
        hw.poke32(self.qh + 4, 1)           # élément : vide
        k := 0
        while k < 1024:
            hw.poke32(self.frames + 4 * k, self.qh | 2)
            k += 1
        self.first = self.qh
        self.buffer = hw.alloc_pages(1)
        hw.outl(self.io + UHCI_FRBASE, self.frames)
        hw.outw(self.io + UHCI_FRNUM, 0)
        hw.outb(self.io + UHCI_SOF, 64)
        hw.outw(self.io + UHCI_STS, 0xFFFF)
        hw.outw(self.io + UHCI_CMD, 0x80 | 1)     # paquets de 64 octets, marche

    func running() -> bool:
        return hw.inw(self.io + UHCI_STS) & 0x20 == 0

    func port_count() -> int:
        # UHCI : au moins deux ports ; un port absent lit 0xFFFF ou n'a pas le bit 7 (toujours 1).
        n := 0
        while n < 8:
            v := hw.inw(self.io + UHCI_PORTSC + 2 * n)
            if v == 0xFFFF or v & 0x80 == 0:
                break
            n += 1
        return n

    func _portsc(port: int) -> int:
        return self.io + UHCI_PORTSC + 2 * port

    func port_connected(port: int) -> bool:
        return hw.inw(self._portsc(port)) & 1 != 0

    func reset_port(port: int) -> int:
        r := self._portsc(port)
        hw.outw(r, hw.inw(r) | 0x200)
        de.io_delay(50000)
        hw.outw(r, hw.inw(r) & ~0x200)
        de.io_delay(300)
        k := 0
        while k < 16:
            v := hw.inw(r)
            if v & 1 == 0:
                return -1
            if v & 0xA != 0:
                hw.outw(r, v & ~4 | 0xA)     # efface CSC / PEC
                continue
            if v & 4 != 0:
                break
            hw.outw(r, v | 4)
            de.io_delay(1000)
            k += 1
        v := hw.inw(r)
        if v & 4 == 0:
            return -1
        if v & 0x100 != 0:
            return SPEED_LOW
        return SPEED_FULL

    func _td(td: int, next: int, ls: bool, pid: int, addr: int, ep: int, toggle: int, length: int, buf: int):
        hw.poke32(td, next)
        st := TD_ACTIVE | TD_CERR3
        if ls:
            st = st | TD_LS
        hw.poke32(td + 4, st)
        maxlen := 0x7FF
        if length > 0:
            maxlen = length - 1
        hw.poke32(td + 8, pid | ((addr & 127) << 8) | ((ep & 15) << 15) | ((toggle & 1) << 19) | (maxlen << 21))
        hw.poke32(td + 12, buf)

    # Exécute la chaîne de TD (tds) dans la file et attend qu'elle soit terminée (ou arrêtée par un paquet
    # court) ; renvoie len(tds), -2 si tries est épuisé (NAK) ; DeviceIoError en cas d'erreur.
    func _run(tds: list[int], tries: int, who: str) -> int:
        hw.poke32(self.qh + 4, tds[0])
        self.transfers += 1
        i := 0
        while i < tries:
            finished := true
            for t in tds:
                st := hw.peek32(t + 4)
                if st & TD_ACTIVE != 0:
                    finished = false
                    break
                if st & TD_ERRORS != 0:
                    hw.poke32(self.qh + 4, 1)
                    self.errors += 1
                    if st & TD_STALLED != 0:
                        de.io_error(who, "STALL", st)
                    de.io_error(who, "erreur de transfert", st)
                maxlen := ((hw.peek32(t + 8) >> 21) + 1) & 0x7FF
                if st & TD_SPD != 0 and self._actual(t) < maxlen:
                    break
            if finished:
                hw.poke32(self.qh + 4, 1)
                return len(tds)
            i += 1
        # Abandon : la file est vidée, puis on laisse passer deux trames (le contrôleur a pu terminer un TD
        # entre-temps : ses données ne doivent pas être perdues).
        hw.poke32(self.qh + 4, 1)
        self._wait_frames(2)
        if hw.peek32(tds[0] + 4) & TD_ACTIVE == 0:
            return len(tds)
        return -2

    func _wait_frames(n: int):
        f := hw.inw(self.io + UHCI_FRNUM) & 0x7FF
        k := 0
        seen := 0
        while k < 1000000 and seen < n:
            g := hw.inw(self.io + UHCI_FRNUM) & 0x7FF
            if g != f:
                seen += 1
                f = g
            k += 1

    func _actual(td: int) -> int:
        n := (hw.peek32(td + 4) + 1) & 0x7FF
        return n

    func control(dev: UsbDev, setup: SetupPacket, buf: int) -> int:
        ls := dev.low_speed()
        mp := dev.max_packet0
        page := self.buffer
        sb := setup.to_bytes()
        k := 0
        while k < 8:
            hw.poke8(page + k, sb[k])
            k += 1
        data := page + 64
        length := setup.length
        if length > 4096 - 64:
            de.unsupported("uhci", "transfert de contrôle de plus de 4032 octets")
        if not setup.is_in() and length > 0:
            hw.copy(data, buf, length)
        tds: list[int] := []
        n := 2 + (length + mp - 1) // mp
        i := 0
        while i < n:
            append(tds, self.pool.alloc())
            i += 1
        self._td(tds[0], tds[1] | 4, ls, PID_SETUP, dev.address, 0, 0, 8, page)
        pid := PID_OUT
        status_pid := PID_IN
        if setup.is_in():
            pid = PID_IN
            status_pid = PID_OUT
        toggle := 1
        off := 0
        j := 1
        while j < n - 1:
            chunk := length - off
            if chunk > mp:
                chunk = mp
            self._td(tds[j], tds[j + 1] | 4, ls, pid, dev.address, 0, toggle, chunk, data + off)
            toggle = 1 - toggle
            off += chunk
            j += 1
        self._td(tds[n - 1], 1, ls, status_pid, dev.address, 0, 1, 0, 0)
        try:
            r := self._run(tds, TRIES, "usb " + str(dev.address))
            if r == -2:
                de.timeout("usb " + str(dev.address), "transfert de contrôle")
        finally:
            for t in tds:
                self.pool.release(t)
        got := 0
        j = 1
        while j < n - 1:
            got += self._actual(tds[j])
            if self._actual(tds[j]) < mp:
                break
            j += 1
        if setup.is_in() and got > 0:
            hw.copy(buf, data, got)
        return got

    func bulk(dev: UsbDev, endpoint: int, max_packet: int, buf: int, length: int, tries: int) -> int:
        ls := dev.low_speed()
        input := endpoint & 0x80 != 0
        ep := endpoint & 15
        pid := PID_OUT
        if input:
            pid = PID_IN
        done := 0
        page := self.buffer
        while done < length or (length == 0 and done == 0):
            chunk := length - done
            if chunk > 4096:
                chunk = 4096
            if not input and chunk > 0:
                hw.copy(page, buf + done, chunk)
            n := (chunk + max_packet - 1) // max_packet
            if n == 0:
                n = 1
            tds: list[int] := []
            i := 0
            while i < n:
                append(tds, self.pool.alloc())
                i += 1
            toggle := dev.toggle(endpoint)
            off := 0
            i = 0
            while i < n:
                size := chunk - off
                if size > max_packet:
                    size = max_packet
                next := 1
                if i + 1 < n:
                    next = tds[i + 1] | 4
                self._td(tds[i], next, ls, pid, dev.address, ep, toggle, size, page + off)
                if input:
                    hw.poke32(tds[i] + 4, hw.peek32(tds[i] + 4) | TD_SPD)
                toggle = 1 - toggle
                off += size
                i += 1
            r := 0
            try:
                r = self._run(tds, tries, "usb " + str(dev.address) + " EP " + str(endpoint))
            catch e:
                for t in tds:
                    self.pool.release(t)
                raise(e.type, e.message)
            got := 0
            completed := 0
            short := false
            for t in tds:
                st := hw.peek32(t + 4)
                if st & TD_ACTIVE != 0:
                    break
                a := self._actual(t)
                got += a
                completed += 1
                if a < max_packet:
                    short = true
                    break
            for t in tds:
                self.pool.release(t)
            dev.set_toggle(endpoint, dev.toggle(endpoint) + completed)
            if r == -2 and completed == 0:
                return -1
            if input and got > 0:
                hw.copy(buf + done, page, got)
            done += got
            if short or length == 0 or r == -2:
                break
        return done

    func _arm(p: _IntPipe):
        self._td(p.td, 1, p.dev.low_speed(), PID_IN, p.dev.address, p.endpoint & 15, p.dev.toggle(p.endpoint), p.max_packet, p.data)
        hw.poke32(p.qh + 4, p.td)

    func interrupt_open(dev: UsbDev, endpoint: int, max_packet: int) -> int:
        qh := self.pool.alloc()
        td := self.pool.alloc()
        data := self.pool.alloc()
        mp := max_packet
        if mp > 32:
            mp = 32
        p := _IntPipe(qh, td, data, dev, endpoint | 0x80, mp)
        hw.poke32(qh, self.first | 2)        # suivante : l'ancienne tête de la liste
        self._arm(p)
        self.first = qh
        k := 0
        while k < 1024:
            hw.poke32(self.frames + 4 * k, qh | 2)
            k += 1
        append(self.pipes, p)
        return len(self.pipes) - 1

    func interrupt_read(pipe: int, buf: int) -> int:
        p := self.pipes[pipe]
        st := hw.peek32(p.td + 4)
        if st & TD_ACTIVE != 0:
            return -1
        if st & TD_ERRORS != 0:
            p.errors += 1
            self.errors += 1
            self._arm(p)
            return -1
        n := self._actual(p.td)
        hw.copy(buf, p.data, n)
        p.dev.set_toggle(p.endpoint, p.dev.toggle(p.endpoint) + 1)
        self.transfers += 1
        self._arm(p)
        return n

    func describe() -> str:
        return self.name() + ", " + str(self.port_count()) + " ports, " + str(self.transfers) + " transferts"

# ---------------------------------------------------------------- énumération
func _bytes(addr: int, n: int) -> list[int]:
    return [hw.peek8(addr + k) for k in 0..n]

# Lit une chaîne (langue 0x0409) dans buf ; "" si absente.
func read_string(hc: HostController, dev: UsbDev, index: int, buf: int) -> str:
    if index == 0:
        return ""
    try:
        hc.control(dev, ud.get_string(index, 0x0409, 2), buf)
        size := hw.peek8(buf)
        if size < 2:
            return ""
        n := hc.control(dev, ud.get_string(index, 0x0409, size), buf)
        return ud.parse_string(_bytes(buf, n))
    catch e:
        return ""

# Réinitialise le port, lit les descripteurs, donne l'adresse address, choisit la première configuration.
func enumerate(hc: HostController, port: int, address: int) -> UsbDev?:
    speed := hc.reset_port(port)
    if speed < 0:
        return null
    buf := hw.alloc_pages(1)
    d := UsbDev(0, port, speed)
    d.max_packet0 = 8
    n := hc.control(d, ud.get_descriptor(ud.DT_DEVICE, 0, 8), buf)
    if n < 8:
        de.io_error("usb", "descripteur du périphérique incomplet", n)
    d.max_packet0 = hw.peek8(buf + 7)
    hc.control(d, ud.set_address(address), buf)
    de.io_delay(2000)
    d.address = address
    n = hc.control(d, ud.get_descriptor(ud.DT_DEVICE, 0, 18), buf)
    d.descriptor = ud.parse_device(_bytes(buf, n))
    hc.control(d, ud.get_descriptor(ud.DT_CONFIGURATION, 0, 9), buf)
    total := hw.peek16(buf + 2)
    if total > 4000:
        total = 4000
    n = hc.control(d, ud.get_descriptor(ud.DT_CONFIGURATION, 0, total), buf)
    d.config = ud.parse_configuration(_bytes(buf, n))
    d.product = read_string(hc, d, d.descriptor.product_index, buf)
    d.manufacturer = read_string(hc, d, d.descriptor.manufacturer_index, buf)
    hc.control(d, ud.set_configuration(d.config.value), buf)
    hw.free_pages(buf, 1)
    return d
