# alex: native
# ALEX STANDARD LIBRARY — usb_driver.usb_mass_storage
#
# Stockage de masse USB : tout ce qu'il faut autour du transport « Bulk-Only » (usb_class.MassStorage) pour
# les clés et disques réels :
#   - CBW / CSW : construction et analyse en mémoire (signatures, étiquette, résidu, état 0 / 1 / 2 = erreur
#     de phase) ;
#   - commandes SCSI : CDB de INQUIRY, TEST UNIT READY, REQUEST SENSE, READ CAPACITY (10) et (16), READ /
#     WRITE (10) et (16), MODE SENSE (6), SYNCHRONIZE CACHE, START STOP UNIT (éjection) ;
#   - réponses : InquiryData (type de périphérique, amovible, fabricant, produit, révision), capacité 10 / 16,
#     protection en écriture (MODE SENSE), SenseData (clé, ASC / ASCQ et leur texte : « support absent »,
#     « en cours de démarrage », « bloc illisible »...) et la conduite à tenir (réessayer, attendre, échouer) ;
#   - réinitialisation « Bulk-Only Mass Storage Reset » + CLEAR_FEATURE(HALT) des deux points d'accès
#     (requêtes de contrôle à envoyer, dans l'ordre), GET MAX LUN.
#
#   use usb_driver.usb_mass_storage as ms
#   ms.write_cbw(tampon, 7, 512, true, 0, ms.cdb_read10(lba, 1))
#   c := ms.parse_csw(tampon_csw, 13)          # Csw : tag, residue, status
#   s := ms.parse_sense(donnees, 18)
#   print(s.describe(), ms.sense_action(s))     # « NOT READY : support absent » « échouer »
#
# Erreurs : UsbProtocolError (CSW invalide, données trop courtes). Compilable en natif.

from core use len
from collections use append
use hw
use usb.usb_descriptor as ud
from usb.usb_descriptor use SetupPacket

const CBW_SIGNATURE := 0x43425355
const CSW_SIGNATURE := 0x53425355
const CSW_PASSED := 0
const CSW_FAILED := 1
const CSW_PHASE_ERROR := 2

# ---------------------------------------------------------------- CBW / CSW
func write_cbw(addr: int, tag: int, length: int, input: bool, lun: int, cdb: list[int]):
    hw.zero(addr, 31)
    hw.poke32(addr, CBW_SIGNATURE)
    hw.poke32(addr + 4, tag)
    hw.poke32(addr + 8, length)
    if input:
        hw.poke8(addr + 12, 0x80)
    hw.poke8(addr + 13, lun & 15)
    hw.poke8(addr + 14, len(cdb))
    k := 0
    while k < len(cdb) and k < 16:
        hw.poke8(addr + 15 + k, cdb[k])
        k += 1

class Csw:
    tag: int := 0
    residue: int := 0
    status: int := 0

    func init(tag: int, residue: int, status: int):
        self.tag = tag
        self.residue = residue
        self.status = status

    func ok() -> bool:
        return self.status == CSW_PASSED

    func describe() -> str:
        st := "réussie"
        if self.status == CSW_FAILED:
            st = "échouée (lire REQUEST SENSE)"
        elif self.status == CSW_PHASE_ERROR:
            st = "erreur de phase (réinitialisation nécessaire)"
        return "CSW tag " + str(self.tag) + " : " + st + ", résidu " + str(self.residue)

func parse_csw(addr: int, n: int) -> Csw:
    if n != 13 or hw.peek32(addr) != CSW_SIGNATURE:
        raise("UsbProtocolError", "CSW invalide (" + str(n) + " octets)")
    return Csw(hw.peek32(addr + 4), hw.peek32(addr + 8), hw.peek8(addr + 12))

func write_csw(addr: int, tag: int, residue: int, status: int):
    hw.poke32(addr, CSW_SIGNATURE)
    hw.poke32(addr + 4, tag)
    hw.poke32(addr + 8, residue)
    hw.poke8(addr + 12, status)

# ---------------------------------------------------------------- CDB
func cdb_inquiry(length: int) -> list[int]:
    return [0x12, 0, 0, 0, length & 255, 0]

func cdb_test_unit_ready() -> list[int]:
    return [0, 0, 0, 0, 0, 0]

func cdb_request_sense(length: int) -> list[int]:
    return [0x03, 0, 0, 0, length & 255, 0]

func cdb_read_capacity10() -> list[int]:
    return [0x25, 0, 0, 0, 0, 0, 0, 0, 0, 0]

func cdb_read_capacity16() -> list[int]:
    return [0x9E, 0x10, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 32, 0, 0]

func _rw10(op: int, lba: int, count: int) -> list[int]:
    return [op, 0, (lba >> 24) & 255, (lba >> 16) & 255, (lba >> 8) & 255, lba & 255, 0, (count >> 8) & 255, count & 255, 0]

func _rw16(op: int, lba: int, count: int) -> list[int]:
    out: list[int] := [op, 0]
    k := 7
    while k >= 0:
        append(out, (lba >> (8 * k)) & 255)
        k -= 1
    append(out, (count >> 24) & 255)
    append(out, (count >> 16) & 255)
    append(out, (count >> 8) & 255)
    append(out, count & 255)
    append(out, 0)
    append(out, 0)
    return out

func cdb_read10(lba: int, count: int) -> list[int]:
    return _rw10(0x28, lba, count)

func cdb_write10(lba: int, count: int) -> list[int]:
    return _rw10(0x2A, lba, count)

func cdb_read16(lba: int, count: int) -> list[int]:
    return _rw16(0x88, lba, count)

func cdb_write16(lba: int, count: int) -> list[int]:
    return _rw16(0x8A, lba, count)

# READ (10) pour les disques de moins de 2 Tio, READ (16) au-delà.
func cdb_read(lba: int, count: int) -> list[int]:
    if lba + count > 0xFFFFFFFF or count > 0xFFFF:
        return cdb_read16(lba, count)
    return cdb_read10(lba, count)

func cdb_mode_sense6(page: int, length: int) -> list[int]:
    return [0x1A, 0, page & 0x3F, 0, length & 255, 0]

func cdb_sync_cache() -> list[int]:
    return [0x35, 0, 0, 0, 0, 0, 0, 0, 0, 0]

# START STOP UNIT : start (true : démarrer), eject (LoEj).
func cdb_start_stop(start: bool, eject: bool) -> list[int]:
    v := 0
    if start:
        v = v | 1
    if eject:
        v = v | 2
    return [0x1B, 0, 0, 0, v, 0]

# ---------------------------------------------------------------- réponses
func _be32(addr: int) -> int:
    return (hw.peek8(addr) << 24) | (hw.peek8(addr + 1) << 16) | (hw.peek8(addr + 2) << 8) | hw.peek8(addr + 3)

func _ascii(addr: int, n: int) -> str:
    table := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    out := ""
    pending := ""
    k := 0
    while k < n:
        c := hw.peek8(addr + k)
        if c == 32:
            pending = pending + " "
        elif c > 32 and c < 127:
            if out != "":
                out = out + pending
            pending = ""
            out = out + str(table[c - 32])
        k += 1
    return out

class InquiryData:
    device_type: int := 0
    removable: bool := false
    version: int := 0
    vendor: str := ""
    product: str := ""
    revision: str := ""

    func init():
        self.vendor = ""

    func type_name() -> str:
        t := self.device_type
        if t == 0:
            return "disque"
        if t == 1:
            return "bande"
        if t == 5:
            return "lecteur CD / DVD"
        if t == 7:
            return "disque optique"
        if t == 0x0E:
            return "disque simplifié (RBC)"
        if t == 0x1F:
            return "inconnu / absent"
        return "type " + str(t)

    func describe() -> str:
        t := self.vendor + " " + self.product + " " + self.revision + " (" + self.type_name()
        if self.removable:
            t = t + ", amovible"
        return t + ")"

func parse_inquiry(addr: int, n: int) -> InquiryData:
    if n < 36:
        raise("UsbProtocolError", "INQUIRY : " + str(n) + " octets (36 attendus)")
    d := InquiryData()
    d.device_type = hw.peek8(addr) & 0x1F
    d.removable = hw.peek8(addr + 1) & 0x80 != 0
    d.version = hw.peek8(addr + 2)
    d.vendor = _ascii(addr + 8, 8)
    d.product = _ascii(addr + 16, 16)
    d.revision = _ascii(addr + 32, 4)
    return d

# [nombre de blocs, taille d'un bloc] depuis READ CAPACITY (10) ; un dernier bloc 0xFFFFFFFF signifie qu'il
# faut READ CAPACITY (16).
func parse_capacity10(addr: int, n: int) -> list[int]:
    if n < 8:
        raise("UsbProtocolError", "READ CAPACITY (10) : réponse trop courte")
    out: list[int] := []
    last := _be32(addr)
    if last == 0xFFFFFFFF:
        append(out, -1)
    else:
        append(out, last + 1)
    append(out, _be32(addr + 4))
    return out

func parse_capacity16(addr: int, n: int) -> list[int]:
    if n < 12:
        raise("UsbProtocolError", "READ CAPACITY (16) : réponse trop courte")
    out: list[int] := []
    append(out, ((_be32(addr) << 32) | _be32(addr + 4)) + 1)
    append(out, _be32(addr + 8))
    return out

# MODE SENSE (6) : bit WP de l'octet 2 de l'en-tête.
func write_protected(addr: int, n: int) -> bool:
    if n < 4:
        raise("UsbProtocolError", "MODE SENSE : réponse trop courte")
    return hw.peek8(addr + 2) & 0x80 != 0

class SenseData:
    key: int := 0
    asc: int := 0
    ascq: int := 0
    valid: bool := false
    information: int := 0

    func init(key: int, asc: int, ascq: int):
        self.key = key
        self.asc = asc
        self.ascq = ascq
        self.valid = false
        self.information = 0

    func key_name() -> str:
        k := self.key
        if k == 0:
            return "NO SENSE"
        if k == 1:
            return "RECOVERED ERROR"
        if k == 2:
            return "NOT READY"
        if k == 3:
            return "MEDIUM ERROR"
        if k == 4:
            return "HARDWARE ERROR"
        if k == 5:
            return "ILLEGAL REQUEST"
        if k == 6:
            return "UNIT ATTENTION"
        if k == 7:
            return "DATA PROTECT"
        if k == 0xB:
            return "ABORTED COMMAND"
        return "clé " + str(k)

    func detail() -> str:
        a := self.asc
        q := self.ascq
        if a == 0 and q == 0:
            return "aucune information"
        if a == 0x04 and q == 0x01:
            return "en cours de démarrage"
        if a == 0x04:
            return "unité pas prête"
        if a == 0x11:
            return "bloc illisible"
        if a == 0x0C:
            return "erreur d'écriture"
        if a == 0x1A:
            return "longueur de liste de paramètres invalide"
        if a == 0x20:
            return "commande inconnue"
        if a == 0x21:
            return "adresse de bloc hors limites"
        if a == 0x24:
            return "champ invalide dans la commande"
        if a == 0x25:
            return "unité logique non prise en charge"
        if a == 0x27:
            return "protégé en écriture"
        if a == 0x28:
            return "support changé (prêt)"
        if a == 0x29:
            return "réinitialisation"
        if a == 0x3A:
            return "support absent"
        return "ASC " + str(a) + " / ASCQ " + str(q)

    func describe() -> str:
        return self.key_name() + " : " + self.detail()

func parse_sense(addr: int, n: int) -> SenseData:
    if n < 14:
        raise("UsbProtocolError", "REQUEST SENSE : " + str(n) + " octets")
    code := hw.peek8(addr) & 0x7F
    if code == 0x72 or code == 0x73:
        s := SenseData(hw.peek8(addr + 1) & 15, hw.peek8(addr + 2), hw.peek8(addr + 3))
        return s
    s := SenseData(hw.peek8(addr + 2) & 15, hw.peek8(addr + 12), hw.peek8(addr + 13))
    s.valid = hw.peek8(addr) & 0x80 != 0
    s.information = _be32(addr + 3)
    return s

# Conduite à tenir : « réessayer », « attendre » (démarrage, support changé), « échouer ».
func sense_action(s: SenseData) -> str:
    if s.key == 0 or s.key == 1:
        return "réessayer"
    if s.key == 6:
        return "réessayer"
    if s.key == 2:
        if s.asc == 0x04 and (s.ascq == 0x01 or s.ascq == 0x00):
            return "attendre"
        return "échouer"
    if s.key == 0xB:
        return "réessayer"
    return "échouer"

# ---------------------------------------------------------------- requêtes de classe
func get_max_lun(iface: int) -> SetupPacket:
    return SetupPacket(ud.DIR_IN | ud.TYPE_CLASS | ud.RECIP_INTERFACE, 0xFE, 0, iface, 1)

func bulk_only_reset(iface: int) -> SetupPacket:
    return SetupPacket(ud.DIR_OUT | ud.TYPE_CLASS | ud.RECIP_INTERFACE, 0xFF, 0, iface, 0)

# Séquence de « reset recovery » : réinitialisation puis CLEAR_FEATURE(HALT) en entrée et en sortie.
func reset_recovery(iface: int, bulk_in: int, bulk_out: int) -> list[SetupPacket]:
    out: list[SetupPacket] := []
    append(out, bulk_only_reset(iface))
    append(out, ud.clear_halt(bulk_in))
    append(out, ud.clear_halt(bulk_out))
    return out
