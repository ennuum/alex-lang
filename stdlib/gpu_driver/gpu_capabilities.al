# alex: native
# ALEX STANDARD LIBRARY — gpu_driver.gpu_capabilities
#
# Ce qu'une carte graphique sait faire, tel que le pilote le découvre : mémoire vidéo, résolution et
# profondeurs maximales, modes proposés, double tampon (défilement vertical de la mémoire), accélération 2D
# matérielle ou non, curseur matériel.
#
#   caps := pilote.capabilities()
#   print(caps.describe())
#   m := caps.best_mode(1024, 768)        # VideoMode le plus proche sans dépasser
#
# Compilable en natif (# alex: native).

from collections use append
from core use len

class VideoMode:
    width: int := 0
    height: int := 0
    bpp: int := 32

    func init(width: int, height: int, bpp: int):
        self.width = width
        self.height = height
        self.bpp = bpp

    func pitch() -> int:
        return self.width * self.bpp // 8

    func bytes() -> int:
        return self.pitch() * self.height

    func describe() -> str:
        return str(self.width) + "x" + str(self.height) + "x" + str(self.bpp)

class GpuCapabilities:
    name: str := ""
    vram: int := 0
    max_width: int := 0
    max_height: int := 0
    depths: list[int] := []
    modes: list[VideoMode] := []
    double_buffer: bool := false
    hw_2d: bool := false
    hw_cursor: bool := false
    version: int := 0

    func init(name: str, vram: int, max_width: int, max_height: int):
        self.name = name
        self.vram = vram
        self.max_width = max_width
        self.max_height = max_height
        self.depths = []
        self.modes = []
        self.double_buffer = false
        self.hw_2d = false
        self.hw_cursor = false
        self.version = 0

    func add_mode(width: int, height: int, bpp: int):
        m := VideoMode(width, height, bpp)
        if m.bytes() <= self.vram and width <= self.max_width and height <= self.max_height:
            append(self.modes, m)

    # Modes courants (VESA) qui tiennent dans la mémoire, en 32 bits par point.
    func add_standard_modes():
        sizes: list[list[int]] := [[640, 480], [800, 600], [1024, 768], [1280, 720], [1280, 1024], [1366, 768], [1600, 900], [1920, 1080], [2560, 1440]]
        for s in sizes:
            self.add_mode(s[0], s[1], 32)

    func supports(width: int, height: int, bpp: int) -> bool:
        if width > self.max_width or height > self.max_height:
            return false
        ok := false
        for d in self.depths:
            if d == bpp:
                ok = true
        return ok and width * height * bpp // 8 <= self.vram

    # Le plus grand mode proposé qui ne dépasse pas width x height (ou le plus petit s'il n'y en a pas).
    func best_mode(width: int, height: int) -> VideoMode?:
        best: VideoMode? := null
        best_area := -1
        for m in self.modes:
            if m.width <= width and m.height <= height and m.width * m.height > best_area:
                best = m
                best_area = m.width * m.height
        if best == null and len(self.modes) > 0:
            return self.modes[0]
        return best

    # Peut-on avoir deux images (affichée + en préparation) dans la mémoire vidéo pour ce mode ?
    func can_double_buffer(m: VideoMode) -> bool:
        return self.double_buffer and 2 * m.bytes() <= self.vram

    func describe() -> str:
        t := self.name + " : " + str(self.vram // 1048576) + " Mio de mémoire vidéo, jusqu'à " + str(self.max_width) + "x" + str(self.max_height)
        if self.double_buffer:
            t = t + ", double tampon"
        if self.hw_2d:
            t = t + ", 2D matérielle"
        else:
            t = t + ", 2D logicielle"
        t = t + ", " + str(len(self.modes)) + " modes"
        return t
