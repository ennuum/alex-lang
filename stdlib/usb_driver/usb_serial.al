# alex: native
# ALEX STANDARD LIBRARY — usb_driver.usb_serial
#
# Ports série USB :
#   - CDC-ACM (classe 02 / sous-classe 02, interface de données classe 0A) : modems, cartes Arduino, la
#     plupart des microcontrôleurs ; LineCoding (débit, bits de données, parité, bits d'arrêt) codé sur 7
#     octets, requêtes SET_LINE_CODING / GET_LINE_CODING / SET_CONTROL_LINE_STATE (DTR, RTS) /
#     SEND_BREAK, notification SERIAL_STATE (DCD, DSR, RI, erreurs) ;
#   - AcmSerial : pilote de classe (UsbClassDriver) : trouve les points d'accès bloc de l'interface de
#     données, configure la ligne, write(texte) / read() par transferts bloc, file de réception ;
#   - FTDI (FT232R / FT232H) : calcul du diviseur de débit (fraction en huitièmes) et débit réellement
#     obtenu, erreur relative.
#
#   use usb_driver.usb_serial as us
#   lc := us.LineCoding(115200, 8, us.PARITY_NONE, us.STOP_1)
#   print(lc.describe())                     # « 115200 bauds 8N1 »
#   port := us.AcmSerial()                   # enregistré dans usb_driver_registry comme les autres
#   port.write("bonjour\r\n") ; print(port.read())
#   print(us.ftdi_divisor(115200, 3000000))  # [valeur, index, débit obtenu]
#
# Erreurs : ArgumentError (paramètres de ligne invalides), UsbProtocolError (points d'accès absents),
# DeviceIoError (transfert). Compilable en natif.

from core use len
from collections use append
use hw
use usb.usb_descriptor as ud
from usb.usb_descriptor use InterfaceDescriptor, SetupPacket
use usb_driver.usb_host_controller as uhc
from usb_driver.usb_host_controller use HostController, UsbDev
use usb_driver.usb_class as uc
from usb_driver.usb_class use UsbClassDriver

const PARITY_NONE := 0
const PARITY_ODD := 1
const PARITY_EVEN := 2
const PARITY_MARK := 3
const PARITY_SPACE := 4

const STOP_1 := 0
const STOP_1_5 := 1
const STOP_2 := 2

const REQ_SET_LINE_CODING := 0x20
const REQ_GET_LINE_CODING := 0x21
const REQ_SET_CONTROL_LINE_STATE := 0x22
const REQ_SEND_BREAK := 0x23

class LineCoding:
    baud: int := 9600
    data_bits: int := 8
    parity: int := 0
    stop: int := 0

    func init(baud: int, data_bits: int, parity: int, stop: int):
        if baud <= 0 or baud > 12000000:
            raise("ArgumentError", "débit " + str(baud) + " invalide")
        if data_bits != 5 and data_bits != 6 and data_bits != 7 and data_bits != 8 and data_bits != 16:
            raise("ArgumentError", "bits de données : 5, 6, 7, 8 ou 16")
        if parity < 0 or parity > 4 or stop < 0 or stop > 2:
            raise("ArgumentError", "parité 0..4, bits d'arrêt 0..2")
        self.baud = baud
        self.data_bits = data_bits
        self.parity = parity
        self.stop = stop

    func to_bytes() -> list[int]:
        return [self.baud & 255, (self.baud >> 8) & 255, (self.baud >> 16) & 255, (self.baud >> 24) & 255, self.stop, self.parity, self.data_bits]

    func write(addr: int):
        b := self.to_bytes()
        k := 0
        while k < 7:
            hw.poke8(addr + k, b[k])
            k += 1

    func describe() -> str:
        p := "N"
        if self.parity == PARITY_ODD:
            p = "O"
        elif self.parity == PARITY_EVEN:
            p = "E"
        elif self.parity == PARITY_MARK:
            p = "M"
        elif self.parity == PARITY_SPACE:
            p = "S"
        s := "1"
        if self.stop == STOP_1_5:
            s = "1.5"
        elif self.stop == STOP_2:
            s = "2"
        return str(self.baud) + " bauds " + str(self.data_bits) + p + s

func read_line_coding(addr: int) -> LineCoding:
    baud := hw.peek32(addr)
    return LineCoding(baud, hw.peek8(addr + 6), hw.peek8(addr + 5), hw.peek8(addr + 4))

func set_line_coding(iface: int) -> SetupPacket:
    return SetupPacket(ud.DIR_OUT | ud.TYPE_CLASS | ud.RECIP_INTERFACE, REQ_SET_LINE_CODING, 0, iface, 7)

func get_line_coding(iface: int) -> SetupPacket:
    return SetupPacket(ud.DIR_IN | ud.TYPE_CLASS | ud.RECIP_INTERFACE, REQ_GET_LINE_CODING, 0, iface, 7)

func set_control_lines(iface: int, dtr: bool, rts: bool) -> SetupPacket:
    v := 0
    if dtr:
        v = v | 1
    if rts:
        v = v | 2
    return SetupPacket(ud.DIR_OUT | ud.TYPE_CLASS | ud.RECIP_INTERFACE, REQ_SET_CONTROL_LINE_STATE, v, iface, 0)

func send_break(iface: int, ms: int) -> SetupPacket:
    return SetupPacket(ud.DIR_OUT | ud.TYPE_CLASS | ud.RECIP_INTERFACE, REQ_SEND_BREAK, ms & 0xFFFF, iface, 0)

# Notification SERIAL_STATE (10 octets : en-tête 8 + état 16 bits) -> texte des signaux et erreurs.
func serial_state_text(addr: int, n: int) -> str:
    if n < 10 or hw.peek8(addr + 1) != 0x20:
        return "notification inconnue"
    st := hw.peek16(addr + 8)
    t := ""
    if st & 1 != 0:
        t = t + " DCD"
    if st & 2 != 0:
        t = t + " DSR"
    if st & 4 != 0:
        t = t + " BREAK"
    if st & 8 != 0:
        t = t + " RI"
    if st & 16 != 0:
        t = t + " erreur-de-trame"
    if st & 32 != 0:
        t = t + " erreur-de-parité"
    if st & 64 != 0:
        t = t + " débordement"
    if t == "":
        return "lignes au repos"
    return "état :" + t

class AcmSerial implements UsbClassDriver:
    hc: HostController?
    dev: UsbDev?
    comm_iface: int := 0
    bulk_in: int := 0x82
    bulk_out: int := 0x02
    packet: int := 64
    buf: int := 0
    coding: LineCoding
    received: str := ""
    sent_bytes: int := 0
    received_bytes: int := 0
    ready: bool := false

    func init():
        self.hc = null
        self.dev = null
        self.coding = LineCoding(115200, 8, PARITY_NONE, STOP_1)
        self.received = ""
        self.sent_bytes = 0
        self.received_bytes = 0
        self.ready = false

    func name() -> str:
        return "série CDC-ACM"

    # Interface de données (classe 0A) avec deux points d'accès bloc ; l'interface de communication (02/02)
    # porte le numéro précédent.
    func matches(dev: UsbDev, itf: InterfaceDescriptor) -> bool:
        if itf.iclass != ud.CLASS_CDC_DATA:
            return false
        return itf.endpoint(ud.EP_BULK, true) != null and itf.endpoint(ud.EP_BULK, false) != null

    func attach(hc: HostController, dev: UsbDev, itf: InterfaceDescriptor):
        self.hc = hc
        self.dev = dev
        ei := itf.endpoint(ud.EP_BULK, true)
        eo := itf.endpoint(ud.EP_BULK, false)
        if ei == null or eo == null:
            raise("UsbProtocolError", "CDC-ACM : points d'accès bloc absents")
        if ei != null:
            self.bulk_in = ei.address
            self.packet = ei.packet_size()
        if eo != null:
            self.bulk_out = eo.address
        self.comm_iface = itf.number - 1 if itf.number > 0 else 0
        self.buf = hw.alloc_pages(1)
        self.configure(self.coding)
        hc.control(dev, set_control_lines(self.comm_iface, true, true), self.buf)
        self.ready = true

    func configure(lc: LineCoding):
        h := self.hc
        d := self.dev
        self.coding = lc
        if h != null:
            if d != null:
                lc.write(self.buf)
                h.control(d, set_line_coding(self.comm_iface), self.buf)

    func write(text: str) -> int:
        h := self.hc
        d := self.dev
        if h == null or d == null:
            raise("DeviceIoError", "CDC-ACM : non attaché")
        n := hw.byte_size(text)
        pages := (n + 4095) // 4096 + 1
        tmp := hw.alloc_pages(pages)
        hw.store_string(text, tmp)
        done := 0
        if h != null:
            if d != null:
                while done < n:
                    chunk := n - done
                    if chunk > 4096:
                        chunk = 4096
                    got := h.bulk(d, self.bulk_out, self.packet, tmp + done, chunk, 100000)
                    if got < 0:
                        hw.free_pages(tmp, pages)
                        raise("DeviceIoError", "CDC-ACM : écriture refusée")
                    done += chunk
        hw.free_pages(tmp, pages)
        self.sent_bytes += done
        return done

    # Interroge le point d'accès d'entrée (sans bloquer longtemps) ; renvoie le nombre d'octets reçus.
    func poll() -> int:
        h := self.hc
        d := self.dev
        if h == null or d == null:
            return 0
        got := 0
        if h != null:
            if d != null:
                got = h.bulk(d, self.bulk_in, self.packet, self.buf + 1024, self.packet, 1)
        if got > 0:
            self.received = self.received + hw.string_at(self.buf + 1024, got)
            self.received_bytes += got
            return got
        return 0

    # Texte reçu depuis le dernier appel.
    func read() -> str:
        self.poll()
        t := self.received
        self.received = ""
        return t

    func describe() -> str:
        return "port série USB " + self.coding.describe() + ", émis " + str(self.sent_bytes) + ", reçus " + str(self.received_bytes)

# FTDI : débit = base / (entier + fraction/8), fractions possibles 0, 1/8, 1/4, 3/8, 1/2, 5/8, 3/4, 7/8 ;
# base 3 MHz (FT232R / FT232BM) ou 12 MHz (FT232H, bit 17 de index). Renvoie [wValue, wIndex, débit obtenu].
func ftdi_divisor(baud: int, base: int) -> list[int]:
    if baud <= 0:
        raise("ArgumentError", "débit " + str(baud) + " invalide")
    out: list[int] := []
    if baud >= base:
        append(out, 0)
        append(out, 0)
        append(out, base)
        return out
    if baud >= base * 2 // 3:
        append(out, 1)
        append(out, 0)
        append(out, base * 2 // 3)
        return out
    # diviseur en huitièmes, arrondi au plus proche
    div8 := (base * 8 + baud // 2) // baud
    if div8 < 16:
        div8 = 16
    if div8 > 0x3FFF * 8 + 7:
        div8 = 0x3FFF * 8 + 7
    whole := div8 // 8
    frac := div8 % 8
    codes := [0, 3, 2, 4, 1, 5, 6, 7]
    code := codes[frac]
    value := whole | ((code & 3) << 14)
    index := (code >> 2) & 1
    if base == 12000000:
        index = index | 0x200
    append(out, value)
    append(out, index)
    append(out, (base * 8) // div8)
    return out

# Erreur relative en pour mille entre le débit demandé et le débit obtenu.
func ftdi_error_permille(baud: int, base: int) -> int:
    got := ftdi_divisor(baud, base)[2]
    d := got - baud
    if d < 0:
        d = -d
    return d * 1000 // baud
