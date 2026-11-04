# alex: native
# ALEX STANDARD LIBRARY — gpu_driver.gpu_firmware
#
# Micrologiciels et données fournies par le matériel graphique :
#   - ROM d'extension PCI (VBIOS) : chaîne d'images (signature 55 AA, structure « PCIR » : fabricant,
#     périphérique, classe, longueur, type de code x86 / Open Firmware / EFI, dernière image), somme de
#     contrôle des images x86, type de machine des images EFI (x64, IA32, ARM64, EBC) ;
#   - EDID (128 octets, lu sur le moniteur par DDC) : fabricant (3 lettres), produit, numéro de série, date,
#     version, entrée numérique / analogique, taille en cm, mode préféré (synchronisation détaillée :
#     horloge, actif / blanking, fréquence), nom et numéro de série du moniteur, limites de balayage, somme ;
#   - FirmwareStore : micrologiciels embarqués dans l'image du noyau (nom, version, octets) retrouvés par nom
#     avec vérification de taille et de CRC32 (comme request_firmware de Linux, sans système de fichiers).
#
#   use gpu_driver.gpu_firmware as gf
#   for img in gf.parse_option_rom(rom, taille): print(img.describe())
#   e := gf.parse_edid(tampon)
#   print(e.describe())               # « QEMU Monitor (RHT 1234) 1024x768 @ 60 Hz ... »
#
# Erreurs : FirmwareError (signature, somme de contrôle, structure PCIR, micrologiciel absent ou corrompu).
# Compilable en natif.

from core use len
from collections use append
use hw

# ---------------------------------------------------------------- ROM d'extension
class RomImage:
    offset: int := 0
    length: int := 0
    vendor: int := 0
    device: int := 0
    class_code: int := 0
    code_type: int := 0
    last: bool := false
    checksum_ok: bool := true
    efi_machine: int := 0
    revision: int := 0

    func init(offset: int):
        self.offset = offset

    func code_name() -> str:
        if self.code_type == 0:
            return "x86 (BIOS)"
        if self.code_type == 1:
            return "Open Firmware"
        if self.code_type == 2:
            return "HP PA-RISC"
        if self.code_type == 3:
            m := self.efi_machine
            if m == 0x8664:
                return "EFI x64"
            if m == 0x14C:
                return "EFI IA32"
            if m == 0xAA64:
                return "EFI ARM64"
            if m == 0x0EBC:
                return "EFI EBC"
            return "EFI"
        return "type " + str(self.code_type)

    func is_vga() -> bool:
        return (self.class_code >> 16) == 0x03

    func describe() -> str:
        t := "image @" + str(self.offset) + " : " + self.code_name() + ", " + str(self.length) + " octets, " + _hex4(self.vendor) + ":" + _hex4(self.device) + " classe " + _hex6(self.class_code)
        if not self.checksum_ok:
            t = t + " [somme fausse]"
        if self.last:
            t = t + " (dernière)"
        return t

func _hexd(v: int, n: int) -> str:
    h := "0123456789abcdef"
    t := ""
    k := n - 1
    while k >= 0:
        t = t + str(h[(v >> (4 * k)) & 15])
        k -= 1
    return t

func _hex4(v: int) -> str:
    return _hexd(v, 4)

func _hex6(v: int) -> str:
    return _hexd(v, 6)

func sum8(addr: int, n: int) -> int:
    s := 0
    i := 0
    while i < n:
        s = (s + hw.peek8(addr + i)) & 255
        i += 1
    return s

# Images de la ROM de taille size en addr (la ROM d'un BAR d'extension activé, ou une copie).
func parse_option_rom(addr: int, size: int) -> list[RomImage]:
    out: list[RomImage] := []
    off := 0
    while off + 0x1A <= size:
        if hw.peek16(addr + off) != 0xAA55:
            if off == 0:
                raise("FirmwareError", "ROM : signature 55 AA absente")
            break
        p := hw.peek16(addr + off + 0x18)
        if off + p + 0x18 > size or hw.string_at(addr + off + p, 4) != "PCIR":
            raise("FirmwareError", "ROM : structure PCIR absente à l'image " + str(off))
        r := addr + off + p
        img := RomImage(off)
        img.vendor = hw.peek16(r + 4)
        img.device = hw.peek16(r + 6)
        img.revision = hw.peek8(r + 0x0C)
        img.class_code = (hw.peek8(r + 0x0F) << 16) | (hw.peek8(r + 0x0E) << 8) | hw.peek8(r + 0x0D)
        img.length = hw.peek16(r + 0x10) * 512
        img.code_type = hw.peek8(r + 0x14)
        img.last = hw.peek8(r + 0x15) & 0x80 != 0
        if img.length == 0 or off + img.length > size:
            raise("FirmwareError", "ROM : longueur d'image " + str(img.length) + " invalide")
        if img.code_type == 0:
            img.checksum_ok = sum8(addr + off, img.length) == 0
        elif img.code_type == 3:
            if hw.peek16(addr + off + 8) == 0x0EF1:
                img.efi_machine = hw.peek16(addr + off + 0x0C)
        append(out, img)
        if img.last:
            break
        off += img.length
    return out

# Écrit une image de ROM minimale (tests, ROM virtuelles) : renvoie sa longueur.
func build_rom_image(addr: int, vendor: int, device: int, class_code: int, code_type: int, blocks: int, last: bool) -> int:
    n := blocks * 512
    hw.zero(addr, n)
    hw.poke16(addr, 0xAA55)
    hw.poke8(addr + 2, blocks)
    if code_type == 3:
        hw.poke16(addr + 8, 0x0EF1)
        hw.poke16(addr + 0x0C, 0x8664)
    hw.poke16(addr + 0x18, 0x40)
    r := addr + 0x40
    hw.store_string("PCIR", r)
    hw.poke16(r + 4, vendor)
    hw.poke16(r + 6, device)
    hw.poke16(r + 0x0A, 0x18)
    hw.poke8(r + 0x0D, class_code & 255)
    hw.poke8(r + 0x0E, (class_code >> 8) & 255)
    hw.poke8(r + 0x0F, (class_code >> 16) & 255)
    hw.poke16(r + 0x10, blocks)
    hw.poke8(r + 0x14, code_type)
    if last:
        hw.poke8(r + 0x15, 0x80)
    if code_type == 0:
        hw.poke8(addr + n - 1, (256 - sum8(addr, n)) & 255)
    return n

# ---------------------------------------------------------------- EDID
class Edid:
    manufacturer: str := ""
    product: int := 0
    serial: int := 0
    week: int := 0
    year: int := 0
    version: str := ""
    digital: bool := false
    width_cm: int := 0
    height_cm: int := 0
    pixel_clock_khz: int := 0
    width: int := 0
    height: int := 0
    refresh: int := 0
    name: str := ""
    serial_text: str := ""
    min_v: int := 0
    max_v: int := 0
    extensions: int := 0
    checksum_ok: bool := false

    func init():
        self.manufacturer = ""

    func describe() -> str:
        t := self.name if self.name != "" else "moniteur"
        t = t + " (" + self.manufacturer + " " + _hex4(self.product) + ")"
        if self.width > 0:
            t = t + " " + str(self.width) + "x" + str(self.height) + " @ " + str(self.refresh) + " Hz"
        t = t + ", EDID " + self.version
        if self.digital:
            t = t + ", numérique"
        else:
            t = t + ", analogique"
        if self.width_cm > 0:
            t = t + ", " + str(self.width_cm) + "x" + str(self.height_cm) + " cm"
        if self.year > 0:
            t = t + ", fabriqué en " + str(self.year)
        if not self.checksum_ok:
            t = t + " [somme fausse]"
        return t

func _text(addr: int) -> str:
    table := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    out := ""
    k := 0
    while k < 13:
        c := hw.peek8(addr + k)
        if c == 0x0A or c == 0:
            break
        if c >= 32 and c < 127:
            out = out + str(table[c - 32])
        k += 1
    while len(out) > 0 and out[len(out) - 1] == ' ':
        trimmed := ""
        i := 0
        while i < len(out) - 1:
            trimmed = trimmed + str(out[i])
            i += 1
        out = trimmed
    return out

# EDID de 128 octets en addr ; FirmwareError si l'en-tête est absent.
func parse_edid(addr: int) -> Edid:
    if hw.peek8(addr) != 0 or hw.peek8(addr + 7) != 0:
        raise("FirmwareError", "EDID : en-tête absent")
    k := 1
    while k < 7:
        if hw.peek8(addr + k) != 0xFF:
            raise("FirmwareError", "EDID : en-tête absent")
        k += 1
    e := Edid()
    m := (hw.peek8(addr + 8) << 8) | hw.peek8(addr + 9)
    letters := "?ABCDEFGHIJKLMNOPQRSTUVWXYZ?????"
    e.manufacturer = str(letters[(m >> 10) & 31]) + str(letters[(m >> 5) & 31]) + str(letters[m & 31])
    e.product = hw.peek16(addr + 10)
    e.serial = hw.peek32(addr + 12)
    e.week = hw.peek8(addr + 16)
    e.year = hw.peek8(addr + 17) + 1990
    e.version = str(hw.peek8(addr + 18)) + "." + str(hw.peek8(addr + 19))
    e.digital = hw.peek8(addr + 20) & 0x80 != 0
    e.width_cm = hw.peek8(addr + 21)
    e.height_cm = hw.peek8(addr + 22)
    e.extensions = hw.peek8(addr + 126)
    e.checksum_ok = sum8(addr, 128) == 0
    d := 0
    while d < 4:
        b := addr + 54 + 18 * d
        clock := hw.peek16(b)
        if clock != 0:
            if e.width == 0:
                ha := hw.peek8(b + 2) | ((hw.peek8(b + 4) & 0xF0) << 4)
                hb := hw.peek8(b + 3) | ((hw.peek8(b + 4) & 0x0F) << 8)
                va := hw.peek8(b + 5) | ((hw.peek8(b + 7) & 0xF0) << 4)
                vb := hw.peek8(b + 6) | ((hw.peek8(b + 7) & 0x0F) << 8)
                e.pixel_clock_khz = clock * 10
                e.width = ha
                e.height = va
                total := (ha + hb) * (va + vb)
                if total > 0:
                    e.refresh = (clock * 10000 + total // 2) // total
        else:
            tag := hw.peek8(b + 3)
            if tag == 0xFC:
                e.name = _text(b + 5)
            elif tag == 0xFF:
                e.serial_text = _text(b + 5)
            elif tag == 0xFD:
                e.min_v = hw.peek8(b + 5)
                e.max_v = hw.peek8(b + 6)
        d += 1
    return e

# EDID synthétique valide (tests, moniteur virtuel) : fabricant 3 lettres, mode préféré w x h à 60 Hz.
func build_edid(addr: int, manufacturer: str, product: int, width: int, height: int, name: str):
    hw.zero(addr, 128)
    k := 1
    while k < 7:
        hw.poke8(addr + k, 0xFF)
        k += 1
    m := 0
    for ch in manufacturer:
        m = (m << 5) | (_code(ch) & 31)
    hw.poke8(addr + 8, (m >> 8) & 255)
    hw.poke8(addr + 9, m & 255)
    hw.poke16(addr + 10, product)
    hw.poke8(addr + 17, 34)
    hw.poke8(addr + 18, 1)
    hw.poke8(addr + 19, 4)
    hw.poke8(addr + 20, 0x80)
    hw.poke8(addr + 21, 52)
    hw.poke8(addr + 22, 29)
    hb := width // 4
    vb := 30
    clock := (width + hb) * (height + vb) * 60 // 10000
    b := addr + 54
    hw.poke16(b, clock)
    hw.poke8(b + 2, width & 255)
    hw.poke8(b + 3, hb & 255)
    hw.poke8(b + 4, ((width >> 8) << 4) | ((hb >> 8) & 15))
    hw.poke8(b + 5, height & 255)
    hw.poke8(b + 6, vb & 255)
    hw.poke8(b + 7, ((height >> 8) << 4) | ((vb >> 8) & 15))
    n := addr + 54 + 18
    hw.poke8(n + 3, 0xFC)
    i := 0
    for ch in name:
        if i < 13:
            hw.poke8(n + 5 + i, _code8(ch))
        i += 1
    if i < 13:
        hw.poke8(n + 5 + i, 0x0A)
    hw.poke8(addr + 127, (256 - sum8(addr, 127)) & 255)

func _code(ch: char) -> int:
    letters := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    i := 0
    while i < 26:
        if letters[i] == ch:
            return i + 1
        i += 1
    return 0

func _code8(ch: char) -> int:
    table := " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~"
    i := 0
    while i < len(table):
        if table[i] == ch:
            return i + 32
        i += 1
    return 63

# ---------------------------------------------------------------- micrologiciels embarqués
func crc32(addr: int, n: int) -> int:
    c := 0xFFFFFFFF
    i := 0
    while i < n:
        c = c ^ hw.peek8(addr + i)
        k := 0
        while k < 8:
            if c & 1 != 0:
                c = 0xEDB88320 ^ (c >> 1)
            else:
                c = c >> 1
            k += 1
        i += 1
    return c ^ 0xFFFFFFFF

class FirmwareBlob:
    name: str := ""
    version: str := ""
    addr: int := 0
    size: int := 0
    crc: int := 0

    func init(name: str, version: str, addr: int, size: int, crc: int):
        self.name = name
        self.version = version
        self.addr = addr
        self.size = size
        self.crc = crc

    func describe() -> str:
        return self.name + " " + self.version + " (" + str(self.size) + " octets, crc " + _hexd(self.crc, 8) + ")"

class FirmwareStore:
    blobs: list[FirmwareBlob] := []
    loads: int := 0

    func init():
        self.blobs = []
        self.loads = 0

    # Enregistre un micrologiciel déjà en mémoire ; son CRC est calculé maintenant.
    func add(name: str, version: str, addr: int, size: int) -> FirmwareBlob:
        b := FirmwareBlob(name, version, addr, size, crc32(addr, size))
        append(self.blobs, b)
        return b

    # Micrologiciel name (version la plus récente enregistrée en dernier) ; vérifie taille minimale et CRC.
    func request(name: str, min_size: int) -> FirmwareBlob:
        found: FirmwareBlob? := null
        for b in self.blobs:
            if b.name == name:
                found = b
        if found == null:
            raise("FirmwareError", "micrologiciel « " + name + " » absent de l'image")
        f := found
        if f != null:
            if f.size < min_size:
                raise("FirmwareError", "micrologiciel « " + name + " » trop petit (" + str(f.size) + " < " + str(min_size) + ")")
            if crc32(f.addr, f.size) != f.crc:
                raise("FirmwareError", "micrologiciel « " + name + " » corrompu (CRC)")
            self.loads += 1
            return f
        raise("FirmwareError", "micrologiciel « " + name + " » absent de l'image")

    func names() -> list[str]:
        out: list[str] := []
        for b in self.blobs:
            append(out, b.name)
        return out
