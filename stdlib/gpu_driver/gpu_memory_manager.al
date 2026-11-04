# alex: native
# ALEX STANDARD LIBRARY — gpu_driver.gpu_memory_manager
#
# Gestion de la mémoire vidéo (VRAM) d'une carte : des zones (surfaces hors écran, textures, tampons) prises
# dans l'espace qui reste après l'image affichée, alignées, rendues au gestionnaire ; premier ajustement avec
# fusion des trous libérés ; statistiques.
#
#   mm := GpuMemoryManager(taille_vram, octets_de_l_ecran, 4096)
#   z := mm.allocate(256 * 256 * 4, "sprite")      # VramBlock (décalage dans la VRAM) ou null si plein
#   ...
#   mm.release(z)
#
# Compilable en natif (# alex: native).

from collections use append
from core use len

class VramBlock:
    offset: int := 0
    size: int := 0
    label: str := ""
    used: bool := true

    func init(offset: int, size: int, label: str, used: bool):
        self.offset = offset
        self.size = size
        self.label = label
        self.used = used

    func end() -> int:
        return self.offset + self.size

class GpuMemoryManager:
    total: int := 0
    reserved: int := 0
    align: int := 4096
    blocks: list[VramBlock] := []
    failures: int := 0

    # total : taille de la VRAM ; reserved : octets du début réservés (image affichée, double tampon).
    func init(total: int, reserved: int, align: int):
        self.total = total
        self.align = align
        self.reserved = _round(reserved, align)
        self.blocks = [VramBlock(self.reserved, total - self.reserved, "libre", false)]
        self.failures = 0

    # Change la zone réservée (changement de mode) ; faux si des allocations l'empêchent.
    func set_reserved(reserved: int) -> bool:
        r := _round(reserved, self.align)
        for b in self.blocks:
            if b.used and b.offset < r:
                return false
        self.reserved = r
        keep: list[VramBlock] := []
        for b in self.blocks:
            if b.used:
                append(keep, b)
        self.blocks = keep
        self._rebuild_free()
        return true

    func _rebuild_free():
        used: list[VramBlock] := []
        for b in self.blocks:
            if b.used:
                append(used, b)
        # tri par décalage
        k := 1
        while k < len(used):
            x := used[k]
            j := k - 1
            while j >= 0 and used[j].offset > x.offset:
                used[j + 1] = used[j]
                j -= 1
            used[j + 1] = x
            k += 1
        out: list[VramBlock] := []
        pos := self.reserved
        for b in used:
            if b.offset > pos:
                append(out, VramBlock(pos, b.offset - pos, "libre", false))
            append(out, b)
            pos = b.end()
        if pos < self.total:
            append(out, VramBlock(pos, self.total - pos, "libre", false))
        self.blocks = out

    func allocate(size: int, label: str) -> VramBlock?:
        n := _round(size, self.align)
        for b in self.blocks:
            if not b.used and b.size >= n:
                z := VramBlock(b.offset, n, label, true)
                b.offset = b.offset + n
                b.size = b.size - n
                append(self.blocks, z)
                self._rebuild_free()
                return z
        self.failures += 1
        return null

    func release(z: VramBlock):
        z.used = false
        keep: list[VramBlock] := []
        for b in self.blocks:
            if b.used and not (b.offset == z.offset and b.size == z.size):
                append(keep, b)
        self.blocks = keep
        self._rebuild_free()

    func used_bytes() -> int:
        n := 0
        for b in self.blocks:
            if b.used:
                n += b.size
        return n

    func free_bytes() -> int:
        return self.total - self.reserved - self.used_bytes()

    func largest_free() -> int:
        m := 0
        for b in self.blocks:
            if not b.used and b.size > m:
                m = b.size
        return m

    func describe() -> str:
        return "VRAM : " + str(self.total // 1024) + " Kio, réservés " + str(self.reserved // 1024) + ", utilisés " + str(self.used_bytes() // 1024) + ", libres " + str(self.free_bytes() // 1024) + " (plus grand bloc " + str(self.largest_free() // 1024) + ")"

func _round(v: int, a: int) -> int:
    if a <= 1:
        return v
    return (v + a - 1) // a * a
