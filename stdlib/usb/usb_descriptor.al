# alex: native
# ALEX STANDARD LIBRARY — usb.usb_descriptor
#
# Descripteurs USB (spécification USB 2.0, chapitre 9) à partir de leurs octets (list[int]) : périphérique,
# configuration (avec ses interfaces, réglages alternatifs, points d'accès, descripteurs HID et de classe),
# chaînes (UTF-16LE), et paquets de requête de contrôle (SETUP) standard. Commun aux applications (usbfs,
# usb.usb_device) et aux pilotes du noyau (usb_driver).
#
#   use usb.usb_descriptor as ud
#   dev := ud.parse_device(octets_18)
#   print(dev.vendor, dev.product, ud.class_name(dev.device_class))
#   cfg := ud.parse_configuration(octets_config)
#   for itf in cfg.interfaces:
#       for ep in itf.endpoints:
#           print(ep.describe())                   # « EP 0x81 entrée interruption 8 octets / 10 ms »
#   setup := ud.get_descriptor(ud.DT_DEVICE, 0, 18)   # 8 octets de la requête
#
# Compilable en natif (# alex: native).

from collections use append
from core use len

const DT_DEVICE := 1
const DT_CONFIGURATION := 2
const DT_STRING := 3
const DT_INTERFACE := 4
const DT_ENDPOINT := 5
const DT_DEVICE_QUALIFIER := 6
const DT_INTERFACE_ASSOCIATION := 11
const DT_BOS := 15
const DT_HID := 0x21
const DT_REPORT := 0x22
const DT_HUB := 0x29
const DT_SS_ENDPOINT_COMPANION := 0x30

const REQ_GET_STATUS := 0
const REQ_CLEAR_FEATURE := 1
const REQ_SET_FEATURE := 3
const REQ_SET_ADDRESS := 5
const REQ_GET_DESCRIPTOR := 6
const REQ_SET_DESCRIPTOR := 7
const REQ_GET_CONFIGURATION := 8
const REQ_SET_CONFIGURATION := 9
const REQ_GET_INTERFACE := 10
const REQ_SET_INTERFACE := 11

const DIR_OUT := 0x00
const DIR_IN := 0x80
const TYPE_STANDARD := 0x00
const TYPE_CLASS := 0x20
const TYPE_VENDOR := 0x40
const RECIP_DEVICE := 0
const RECIP_INTERFACE := 1
const RECIP_ENDPOINT := 2

const EP_CONTROL := 0
const EP_ISOCHRONOUS := 1
const EP_BULK := 2
const EP_INTERRUPT := 3

const CLASS_AUDIO := 0x01
const CLASS_CDC := 0x02
const CLASS_HID := 0x03
const CLASS_IMAGE := 0x06
const CLASS_PRINTER := 0x07
const CLASS_MASS_STORAGE := 0x08
const CLASS_HUB := 0x09
const CLASS_CDC_DATA := 0x0A
const CLASS_VIDEO := 0x0E
const CLASS_WIRELESS := 0xE0
const CLASS_MISC := 0xEF
const CLASS_VENDOR := 0xFF

func class_name(c: int) -> str:
    if c == 0:
        return "par interface"
    if c == CLASS_AUDIO:
        return "audio"
    if c == CLASS_CDC:
        return "communication"
    if c == CLASS_HID:
        return "hid"
    if c == 0x05:
        return "physique"
    if c == CLASS_IMAGE:
        return "image"
    if c == CLASS_PRINTER:
        return "imprimante"
    if c == CLASS_MASS_STORAGE:
        return "stockage de masse"
    if c == CLASS_HUB:
        return "concentrateur"
    if c == CLASS_CDC_DATA:
        return "données CDC"
    if c == 0x0B:
        return "carte à puce"
    if c == 0x0D:
        return "sécurité du contenu"
    if c == CLASS_VIDEO:
        return "vidéo"
    if c == 0x0F:
        return "santé"
    if c == 0x10:
        return "audio / vidéo"
    if c == 0x11:
        return "panneau d'affichage"
    if c == 0xDC:
        return "diagnostic"
    if c == CLASS_WIRELESS:
        return "sans fil"
    if c == CLASS_MISC:
        return "divers"
    if c == 0xFE:
        return "spécifique à l'application"
    if c == CLASS_VENDOR:
        return "propre au fabricant"
    return "classe " + str(c)

func _u16(b: list[int], at: int) -> int:
    return b[at] | (b[at + 1] << 8)

func _hex4(v: int) -> str:
    d := "0123456789abcdef"
    return str(d[(v >> 12) & 15]) + str(d[(v >> 8) & 15]) + str(d[(v >> 4) & 15]) + str(d[v & 15])

func _hex2(v: int) -> str:
    d := "0123456789abcdef"
    return str(d[(v >> 4) & 15]) + str(d[v & 15])

# Version BCD (0x0200 -> « 2.00 »).
func bcd_text(v: int) -> str:
    major := ((v >> 12) & 15) * 10 + ((v >> 8) & 15)
    return str(major) + "." + str((v >> 4) & 15) + str(v & 15)

# ---------------------------------------------------------------- périphérique
class DeviceDescriptor:
    usb_version: int := 0
    device_class: int := 0
    device_subclass: int := 0
    protocol: int := 0
    max_packet0: int := 8
    vendor: int := 0
    product: int := 0
    release: int := 0
    manufacturer_index: int := 0
    product_index: int := 0
    serial_index: int := 0
    configurations: int := 0

    func init():
        self.max_packet0 = 8

    func id_text() -> str:
        return _hex4(self.vendor) + ":" + _hex4(self.product)

    func describe() -> str:
        return "USB " + bcd_text(self.usb_version) + " [" + self.id_text() + "] classe " + class_name(self.device_class) + ", EP0 " + str(self.max_packet0) + " octets, " + str(self.configurations) + " configuration(s)"

# 18 octets (ou au moins 8 : seuls les premiers champs sont lus).
func parse_device(b: list[int]) -> DeviceDescriptor:
    d := DeviceDescriptor()
    if len(b) < 8 or b[1] != DT_DEVICE:
        raise("ArgumentError", "descripteur de périphérique invalide")
    d.usb_version = _u16(b, 2)
    d.device_class = b[4]
    d.device_subclass = b[5]
    d.protocol = b[6]
    d.max_packet0 = b[7]
    if len(b) >= 18:
        d.vendor = _u16(b, 8)
        d.product = _u16(b, 10)
        d.release = _u16(b, 12)
        d.manufacturer_index = b[14]
        d.product_index = b[15]
        d.serial_index = b[16]
        d.configurations = b[17]
    return d

# ---------------------------------------------------------------- point d'accès
class EndpointDescriptor:
    address: int := 0
    attributes: int := 0
    max_packet: int := 0
    interval: int := 0

    func init(address: int, attributes: int, max_packet: int, interval: int):
        self.address = address
        self.attributes = attributes
        self.max_packet = max_packet
        self.interval = interval

    func number() -> int:
        return self.address & 15

    func is_in() -> bool:
        return self.address & 0x80 != 0

    func transfer_type() -> int:
        return self.attributes & 3

    # Taille utile d'un paquet (bits 0-10) et transactions supplémentaires par micro-trame (bits 11-12).
    func packet_size() -> int:
        return self.max_packet & 0x7FF

    func describe() -> str:
        sens := "sortie"
        if self.is_in():
            sens = "entrée"
        t := "EP 0x" + _hex2(self.address) + " " + sens + " " + transfer_name(self.transfer_type()) + " " + str(self.packet_size()) + " octets"
        if self.transfer_type() == EP_INTERRUPT or self.transfer_type() == EP_ISOCHRONOUS:
            t = t + " / " + str(self.interval)
        return t

func transfer_name(t: int) -> str:
    if t == EP_CONTROL:
        return "contrôle"
    if t == EP_ISOCHRONOUS:
        return "isochrone"
    if t == EP_BULK:
        return "bloc"
    return "interruption"

# ---------------------------------------------------------------- interface
class InterfaceDescriptor:
    number: int := 0
    alternate: int := 0
    iclass: int := 0
    subclass: int := 0
    protocol: int := 0
    string_index: int := 0
    endpoints: list[EndpointDescriptor] := []
    hid_report_length: int := 0
    extra: list[list[int]] := []      # descripteurs de classe non interprétés

    func init(number: int, alternate: int, iclass: int, subclass: int, protocol: int):
        self.number = number
        self.alternate = alternate
        self.iclass = iclass
        self.subclass = subclass
        self.protocol = protocol
        self.string_index = 0
        self.endpoints = []
        self.hid_report_length = 0
        self.extra = []

    # Premier point d'accès de ce type et de ce sens, ou null.
    func endpoint(kind: int, input: bool) -> EndpointDescriptor?:
        for e in self.endpoints:
            if e.transfer_type() == kind and e.is_in() == input:
                return e
        return null

    # Clavier / souris d'amorçage (HID, sous-classe 1, protocole 1 / 2).
    func is_boot_keyboard() -> bool:
        return self.iclass == CLASS_HID and self.subclass == 1 and self.protocol == 1

    func is_boot_mouse() -> bool:
        return self.iclass == CLASS_HID and self.subclass == 1 and self.protocol == 2

    func describe() -> str:
        t := "interface " + str(self.number)
        if self.alternate != 0:
            t = t + " (réglage " + str(self.alternate) + ")"
        t = t + " : " + class_name(self.iclass) + " " + str(self.subclass) + "/" + str(self.protocol)
        for e in self.endpoints:
            t = t + "\n    " + e.describe()
        return t

# ---------------------------------------------------------------- configuration
class ConfigurationDescriptor:
    total_length: int := 0
    value: int := 1
    string_index: int := 0
    attributes: int := 0
    max_power_ma: int := 0
    interface_count: int := 0
    interfaces: list[InterfaceDescriptor] := []

    func init():
        self.interfaces = []

    func self_powered() -> bool:
        return self.attributes & 0x40 != 0

    func remote_wakeup() -> bool:
        return self.attributes & 0x20 != 0

    # Interface (réglage 0) numéro n, ou null.
    func find_interface(n: int) -> InterfaceDescriptor?:
        for i in self.interfaces:
            if i.number == n and i.alternate == 0:
                return i
        return null

    func find_class(c: int) -> InterfaceDescriptor?:
        for i in self.interfaces:
            if i.iclass == c:
                return i
        return null

    func describe() -> str:
        t := "configuration " + str(self.value) + " : " + str(self.interface_count) + " interface(s), " + str(self.max_power_ma) + " mA"
        if self.self_powered():
            t = t + ", autoalimenté"
        for i in self.interfaces:
            t = t + "\n  " + i.describe()
        return t

# Configuration complète (wTotalLength octets) : interfaces, points d'accès, descripteurs HID.
func parse_configuration(b: list[int]) -> ConfigurationDescriptor:
    c := ConfigurationDescriptor()
    if len(b) < 9 or b[1] != DT_CONFIGURATION:
        raise("ArgumentError", "descripteur de configuration invalide")
    c.total_length = _u16(b, 2)
    c.interface_count = b[4]
    c.value = b[5]
    c.string_index = b[6]
    c.attributes = b[7]
    c.max_power_ma = b[8] * 2
    pos := b[0]
    n := len(b)
    if c.total_length < n:
        n = c.total_length
    cur: InterfaceDescriptor? := null
    while pos + 2 <= n:
        size := b[pos]
        kind := b[pos + 1]
        if size < 2 or pos + size > n:
            break
        if kind == DT_INTERFACE and size >= 9:
            i := InterfaceDescriptor(b[pos + 2], b[pos + 3], b[pos + 5], b[pos + 6], b[pos + 7])
            i.string_index = b[pos + 8]
            append(c.interfaces, i)
            cur = i
        elif kind == DT_ENDPOINT and size >= 7:
            if cur != null:
                append(cur.endpoints, EndpointDescriptor(b[pos + 2], b[pos + 3], _u16(b, pos + 4), b[pos + 6]))
        elif kind == DT_HID and size >= 9:
            if cur != null:
                cur.hid_report_length = _u16(b, pos + 7)
        else:
            if cur != null:
                append(cur.extra, [b[k] for k in pos..pos + size])
        pos += size
    return c

# Longueur totale annoncée par les 9 premiers octets d'une configuration.
func configuration_length(b: list[int]) -> int:
    return _u16(b, 2)

# Chaîne (descripteur de type 3, UTF-16LE) -> texte (caractères hors ASCII remplacés par « ? » en natif).
func parse_string(b: list[int]) -> str:
    chars := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    if len(b) < 2 or b[1] != DT_STRING:
        return ""
    n := b[0]
    if n > len(b):
        n = len(b)
    out := ""
    k := 2
    while k + 1 < n:
        c := b[k] | (b[k + 1] << 8)
        if c >= 32 and c < 127:
            out = out + str(chars[c - 32])
        else:
            out = out + "?"
        k += 2
    return out

# Langues proposées (descripteur de chaîne 0) : list d'identifiants (0x0409 : anglais américain).
func parse_languages(b: list[int]) -> list[int]:
    out: list[int] := []
    k := 2
    while k + 1 < len(b) and k + 1 < b[0]:
        append(out, b[k] | (b[k + 1] << 8))
        k += 2
    return out

# ---------------------------------------------------------------- requêtes de contrôle
class SetupPacket:
    request_type: int := 0
    request: int := 0
    value: int := 0
    index: int := 0
    length: int := 0

    func init(request_type: int, request: int, value: int, index: int, length: int):
        self.request_type = request_type
        self.request = request
        self.value = value
        self.index = index
        self.length = length

    func is_in() -> bool:
        return self.request_type & 0x80 != 0

    func to_bytes() -> list[int]:
        return [self.request_type, self.request, self.value & 255, (self.value >> 8) & 255, self.index & 255, (self.index >> 8) & 255, self.length & 255, (self.length >> 8) & 255]

    func describe() -> str:
        return "SETUP type " + str(self.request_type) + " requête " + str(self.request) + " valeur " + str(self.value) + " index " + str(self.index) + " longueur " + str(self.length)

func get_descriptor(kind: int, index: int, length: int) -> SetupPacket:
    return SetupPacket(DIR_IN | TYPE_STANDARD | RECIP_DEVICE, REQ_GET_DESCRIPTOR, (kind << 8) | index, 0, length)

func get_string(index: int, language: int, length: int) -> SetupPacket:
    return SetupPacket(DIR_IN | TYPE_STANDARD | RECIP_DEVICE, REQ_GET_DESCRIPTOR, (DT_STRING << 8) | index, language, length)

func set_address(address: int) -> SetupPacket:
    return SetupPacket(DIR_OUT | TYPE_STANDARD | RECIP_DEVICE, REQ_SET_ADDRESS, address, 0, 0)

func set_configuration(value: int) -> SetupPacket:
    return SetupPacket(DIR_OUT | TYPE_STANDARD | RECIP_DEVICE, REQ_SET_CONFIGURATION, value, 0, 0)

func set_interface(iface: int, alternate: int) -> SetupPacket:
    return SetupPacket(DIR_OUT | TYPE_STANDARD | RECIP_INTERFACE, REQ_SET_INTERFACE, alternate, iface, 0)

func get_status() -> SetupPacket:
    return SetupPacket(DIR_IN | TYPE_STANDARD | RECIP_DEVICE, REQ_GET_STATUS, 0, 0, 2)

func clear_halt(endpoint: int) -> SetupPacket:
    return SetupPacket(DIR_OUT | TYPE_STANDARD | RECIP_ENDPOINT, REQ_CLEAR_FEATURE, 0, endpoint, 0)

# HID : SET_PROTOCOL (0 : amorçage, 1 : rapport), SET_IDLE, GET_REPORT.
func hid_set_protocol(iface: int, protocol: int) -> SetupPacket:
    return SetupPacket(DIR_OUT | TYPE_CLASS | RECIP_INTERFACE, 0x0B, protocol, iface, 0)

func hid_set_idle(iface: int, duration: int) -> SetupPacket:
    return SetupPacket(DIR_OUT | TYPE_CLASS | RECIP_INTERFACE, 0x0A, duration << 8, iface, 0)

func hid_get_report_descriptor(iface: int, length: int) -> SetupPacket:
    return SetupPacket(DIR_IN | TYPE_STANDARD | RECIP_INTERFACE, REQ_GET_DESCRIPTOR, DT_REPORT << 8, iface, length)
