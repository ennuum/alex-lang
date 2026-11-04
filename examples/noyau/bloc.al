# Périphérique de bloc du système de fichiers : disque virtio (virtio_blk.al) s'il y en a un, sinon disque
# ATA (disque.al). Secteurs de 512 octets.
use disque
use virtio_blk

kind := 0 # 0 : ATA, 1 : virtio

# Détecte le disque (virtio d'abord) ; renvoie son nombre de secteurs (0 : aucun).
func init() -> int:
    n := virtio_blk.init()
    if n > 0:
        kind = 1
        return n
    kind = 0
    return disque.init()

# Pilote en service.
func name() -> str:
    if kind == 1:
        return "virtio-blk"
    return "ATA"

func sectors() -> int:
    if kind == 1:
        return virtio_blk.sectors
    return disque.sectors

func read(lba: int, buf: int):
    if kind == 1:
        virtio_blk.read(lba, buf)
    else:
        disque.read(lba, buf)

func write(lba: int, buf: int):
    if kind == 1:
        virtio_blk.write(lba, buf)
    else:
        disque.write(lba, buf)
