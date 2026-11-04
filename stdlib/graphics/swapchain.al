# ALEX STANDARD LIBRARY — graphics.swapchain
#
# Chaîne d'images à présenter : plusieurs surfaces (double / triple tampon) ; on dessine dans l'image acquise
# pendant que la précédente est montrée, puis on la PRÉSENTE à une destination :
#   - WindowPresenter : un canvas d'une fenêtre du module ui (ui.canvas_put_pixels, X11 / sans écran) ;
#   - FilePresenter : une image PPM par présentation (séquence « image_0001.ppm »...) ;
#   - MemoryPresenter : garde la dernière image (tests, capture d'écran) ;
# avec mesure de la cadence (images par seconde) et limite facultative.
#
#   sc := Swapchain(320, 240, 2, MemoryPresenter())
#   s := sc.acquire()
#   ...dessiner dans s...
#   sc.present()
#   print(sc.fps())

from core use len
from collections use append
use asyncio
use graphics.surface as gs

class MemoryPresenter:
    func init():
        self.last = null
        self.count = 0

    func present(surface):
        self.last = surface.copy()
        self.count += 1

class FilePresenter:
    func init(prefix):
        self.prefix = prefix
        self.count = 0
        self.paths = []

    func present(surface):
        self.count += 1
        n := str(self.count)
        while len(n) < 4:
            n = "0" + n
        p := self.prefix + "_" + n + ".ppm"
        surface.save_ppm(p)
        append(self.paths, p)

class WindowPresenter:
    # ui_module : le module ui (use ui) ; canvas : identifiant de canvas d'une fenêtre ; x, y : position.
    func init(ui_module, canvas, x=0, y=0):
        self.ui = ui_module
        self.canvas = canvas
        self.x = x
        self.y = y
        self.count = 0

    func present(surface):
        self.ui.canvas_put_pixels(self.canvas, self.x, self.y, surface.width, surface.height, surface.to_rgba_bytes())
        self.count += 1

class Swapchain:
    func init(width, height, images=2, presenter=null, depth=true):
        if images < 1:
            raise("ArgumentError", "Swapchain : au moins une image")
        self.width = width
        self.height = height
        self.images = [gs.Surface(width, height, depth) for i in 0..images]
        self.presenter = presenter if presenter != null else MemoryPresenter()
        self.current = -1
        self.presented = 0
        self.times = []
        self.max_fps = null

    # Prochaine image à dessiner.
    func acquire():
        self.current = (self.current + 1) % len(self.images)
        return self.images[self.current]

    # Présente l'image acquise ; respecte max_fps si fixé (attente active courte).
    func present():
        if self.current < 0:
            raise("InvalidStateError", "Swapchain : present sans acquire")
        now := asyncio.now()
        if self.max_fps != null and len(self.times) > 0:
            wait := 1.0 / self.max_fps - (now - self.times[len(self.times) - 1])
            while wait > 0:
                now = asyncio.now()
                wait = 1.0 / self.max_fps - (now - self.times[len(self.times) - 1])
        self.presenter.present(self.images[self.current])
        self.presented += 1
        append(self.times, now)
        if len(self.times) > 60:
            self.times = [self.times[k] for k in 1..len(self.times)]

    # Cadence des dernières présentations.
    func fps():
        n := len(self.times)
        if n < 2:
            return 0.0
        span := self.times[n - 1] - self.times[0]
        if span <= 0:
            return 0.0
        return (n - 1) / span

    func resize(width, height):
        self.width = width
        self.height = height
        self.images = [gs.Surface(width, height, self.images[0].has_depth) for i in 0..len(self.images)]
        self.current = -1
