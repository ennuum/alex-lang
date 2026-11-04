# Pilote virtio-blk (interface PCI « legacy » de virtio 0.9.5 / 1.0 transitionnelle : registres dans l'espace
# des ports, BAR 0) : disque de QEMU (`-device virtio-blk-pci`), secteurs de 512 octets, LBA 64 bits.
#
# Une file virtqueue (descripteurs, anneau « avail » écrit par le pilote, anneau « used » écrit par le
# périphérique) en mémoire physique contiguë ; chaque requête enchaîne trois descripteurs (en-tête, données,
# octet d'état) ; le pilote prévient le périphérique (port de notification) puis attend la fin par scrutation
# de l'anneau « used » (pas d'interruption). Mêmes fonctions que disque.al : init, read, write.
use hw
use bus_pci as pci

const VENDOR := 6900       # 0x1AF4 (Red Hat, virtio)
const DEVICE_BLK := 4097   # 0x1001 : bloc, transitionnel
# Registres (décalages dans le BAR 0)
const HOST_FEATURES := 0
const GUEST_FEATURES := 4
const QUEUE_PFN := 8
const QUEUE_SIZE := 12
const QUEUE_SELECT := 14
const QUEUE_NOTIFY := 16
const STATUS := 18
const ISR := 19
const CONFIG := 20         # configuration du disque (sans MSI-X) : capacité (u64, secteurs) en premier
# Bits d'état du périphérique
const ACKNOWLEDGE := 1
const DRIVER := 2
const DRIVER_OK := 4
const FAILED := 128
# Descripteurs
const NEXT := 1
const WRITE := 2           # tampon écrit par le périphérique
# Requêtes
const T_IN := 0            # lecture
const T_OUT := 1           # écriture
const T_FLUSH := 4

io := 0                    # base des ports, 0 : absent
size := 0                  # nombre d'entrées de la file
desc := 0                  # table des descripteurs (16 octets chacun)
avail := 0                 # anneau avail : flags u16, idx u16, ring[size] u16
used := 0                  # anneau used : flags u16, idx u16, ring[size] (id u32, len u32)
last_used := 0             # dernier indice used consommé
req := 0                   # page des requêtes : en-tête en 0, état en 16, données en 512
sectors := 0
flush_ok := false          # le périphérique accepte FLUSH (fonction VIRTIO_BLK_F_FLUSH, bit 9)

func _align(v: int, a: int) -> int:
    return (v + a - 1) // a * a

# Détecte et initialise le disque virtio ; renvoie son nombre de secteurs (0 : pas de disque virtio).
func init() -> int:
    d := pci.find(VENDOR, DEVICE_BLK)
    if d == null:
        return 0
    base := pci.bar(d, 0)
    if base == 0:
        return 0
    pci.enable(d)
    io = base
    hw.outb(io + STATUS, 0)                          # réinitialisation
    hw.outb(io + STATUS, ACKNOWLEDGE)
    hw.outb(io + STATUS, ACKNOWLEDGE | DRIVER)
    features := hw.inl(io + HOST_FEATURES)
    flush_ok = (features & 512) != 0
    hw.outl(io + GUEST_FEATURES, features & 512)     # seule fonction utilisée : FLUSH
    hw.outw(io + QUEUE_SELECT, 0)
    size = hw.inw(io + QUEUE_SIZE)
    if size == 0:
        hw.outb(io + STATUS, FAILED)
        io = 0
        return 0
    # Disposition « legacy » : descripteurs, anneau avail, puis anneau used aligné sur 4 Kio.
    used_off := _align(16 * size + 6 + 2 * size, 4096)
    total := used_off + _align(6 + 8 * size, 4096)
    q := hw.alloc_pages(total // 4096)
    desc = q
    avail = q + 16 * size
    used = q + used_off
    last_used = 0
    hw.outl(io + QUEUE_PFN, q >> 12)
    req = hw.alloc_pages(1)
    hw.outb(io + STATUS, ACKNOWLEDGE | DRIVER | DRIVER_OK)
    sectors = _config64(0)
    return sectors

# Mot de 64 bits de la configuration du périphérique (deux lectures de 32 bits).
func _config64(off: int) -> int:
    lo := hw.inl(io + CONFIG + off)
    hi := hw.inl(io + CONFIG + off + 4)
    return lo | (hi << 32)

func _set_desc(i: int, addr: int, length: int, flags: int, next: int):
    e := desc + 16 * i
    hw.poke64(e, addr)
    hw.poke32(e + 8, length)
    hw.poke16(e + 12, flags)
    hw.poke16(e + 14, next)

# Soumet la requête (type, secteur) préparée dans req et attend sa fin ; data_len octets en req + 512.
func _submit(kind: int, lba: int, data_len: int):
    if io == 0:
        raise("DiskError", "pas de disque virtio")
    hw.poke32(req, kind)
    hw.poke32(req + 4, 0)
    hw.poke64(req + 8, lba)
    hw.poke8(req + 16, 255)                          # état : écrit par le périphérique
    if data_len > 0:
        data_flags := NEXT
        if kind == T_IN:
            data_flags = NEXT | WRITE
        _set_desc(0, req, 16, NEXT, 1)
        _set_desc(1, req + 512, data_len, data_flags, 2)
        _set_desc(2, req + 16, 1, WRITE, 0)
    else:
        _set_desc(0, req, 16, NEXT, 2)
        _set_desc(2, req + 16, 1, WRITE, 0)
    idx := hw.peek16(avail + 2)
    hw.poke16(avail + 4 + 2 * (idx % size), 0)       # tête de chaîne : descripteur 0
    hw.poke16(avail + 2, (idx + 1) & 65535)          # publié après la chaîne (x86 : ordre conservé)
    hw.outw(io + QUEUE_NOTIFY, 0)
    while hw.peek16(used + 2) == last_used:
        hw.pause()
    last_used = (last_used + 1) & 65535
    hw.inb(io + ISR)                                 # acquitte l'interruption éventuelle
    st := hw.peek8(req + 16)
    if st != 0:
        raise("DiskError", f"erreur virtio-blk (état {st}, secteur {lba})")

func _check(lba: int):
    if lba < 0 or lba >= sectors:
        raise("DiskError", "secteur " + str(lba) + " hors du disque (" + str(sectors) + " secteurs)")

# Lit le secteur lba dans les 512 octets en buf.
func read(lba: int, buf: int):
    _check(lba)
    _submit(T_IN, lba, 512)
    hw.copy(buf, req + 512, 512)

# Écrit les 512 octets en buf dans le secteur lba (puis vide le cache du disque si possible).
func write(lba: int, buf: int):
    _check(lba)
    hw.copy(req + 512, buf, 512)
    _submit(T_OUT, lba, 512)
    if flush_ok:
        _submit(T_FLUSH, 0, 0)
