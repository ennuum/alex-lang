# ALEX STANDARD LIBRARY — mouse.pointer_position
#
# Position du pointeur et espaces de coordonnées :
#   PositionTracker  position courante et historique, à partir d'événements absolus (fenêtre) ou RELATIFS
#                    (souris brute evdev : intégrés, avec courbe d'accélération, et bornés à une zone d'écran),
#                    lissage exponentiel, vitesse, direction, distance parcourue
#   CoordinateSpace  conversions fenêtre <-> normalisé [0,1] <-> points indépendants (dp, selon le DPI) <->
#                    repère local d'un élément (origine, échelle)
#
#   use mouse.pointer_position as pp
#   t := pp.PositionTracker(1920, 1080)
#   t.feed_relative(12, -3)                 # déplacement brut : position intégrée et bornée
#   t.set(300, 200)                         # position absolue (événement de fenêtre)
#   print(t.x, t.y, t.speed(), t.direction(), t.distance)
#   s := pp.CoordinateSpace(800, 600, 144)  # fenêtre 800x600 à 144 DPI
#   print(s.normalize(400, 300), s.to_dp(400, 300), s.to_local(400, 300, 100, 100, 2.0))
#
# Erreurs : ArgumentError (dimensions, facteur), TypeError.

from core use len, type, to_int
from collections use append
use os as _os
use math as _math

func _clamp(v, lo, hi):
    if v < lo:
        return lo
    if v > hi:
        return hi
    return v

class PositionTracker:
    func init(width=null, height=null, history=32, smoothing=0.0, acceleration=1.0, threshold=6.0):
        self.width = width
        self.height = height
        self.x = 0.0
        self.y = 0.0
        if width != null:
            self.x = width / 2.0
        if height != null:
            self.y = height / 2.0
        self.sx = self.x
        self.sy = self.y
        self.max_history = history
        self.history = []
        self.smoothing = smoothing
        self.acceleration = acceleration
        self.threshold = threshold
        self.distance = 0.0
        self.clock = null

    func _now():
        if self.clock != null:
            c := self.clock
            return c()
        return _os.monotonic_time()

    func _push(nx, ny):
        if self.width != null:
            nx = _clamp(nx, 0, self.width - 1)
        if self.height != null:
            ny = _clamp(ny, 0, self.height - 1)
        dx := nx - self.x
        dy := ny - self.y
        self.distance += _math.sqrt(dx * dx + dy * dy)
        self.x = nx
        self.y = ny
        a := self.smoothing
        self.sx = a * self.sx + (1 - a) * nx
        self.sy = a * self.sy + (1 - a) * ny
        append(self.history, [nx, ny, self._now()])
        if len(self.history) > self.max_history:
            self.history = self.history[1:]
        return [nx, ny]

    func set(x, y):
        return self._push(x * 1.0, y * 1.0)

    # Déplacement relatif ; au-delà de threshold (unités par événement), multiplié par acceleration.
    func feed_relative(dx, dy):
        m := _math.sqrt(dx * dx + dy * dy)
        f := 1.0
        if m > self.threshold:
            f = self.acceleration
        return self._push(self.x + dx * f, self.y + dy * f)

    # MouseEvent (mouse.mouse_event) : absolu (window) ou relatif (evdev).
    func feed(e):
        if e == null:
            return null
        if e.kind == "relative":
            return self.feed_relative(e.dx, e.dy)
        if e.kind == "wheel" or e.kind == "leave":
            return [self.x, self.y]
        return self.set(e.x, e.y)

    func position():
        return [self.x, self.y]

    func smoothed():
        return [self.sx, self.sy]

    # Vitesse (unités / s) entre le plus ancien et le plus récent échantillon.
    func speed():
        n := len(self.history)
        if n < 2:
            return 0.0
        a := self.history[0]
        b := self.history[n - 1]
        dt := b[2] - a[2]
        if dt <= 0:
            return 0.0
        return _math.sqrt((b[0] - a[0]) * (b[0] - a[0]) + (b[1] - a[1]) * (b[1] - a[1])) / dt

    # « left », « right », « up », « down » (ou null) selon le dernier mouvement dominant.
    func direction():
        n := len(self.history)
        if n < 2:
            return null
        a := self.history[n - 2]
        b := self.history[n - 1]
        dx := b[0] - a[0]
        dy := b[1] - a[1]
        if dx == 0 and dy == 0:
            return null
        if _abs(dx) >= _abs(dy):
            if dx > 0:
                return "right"
            return "left"
        if dy > 0:
            return "down"
        return "up"

    func reset(x=null, y=null):
        self.history = []
        self.distance = 0.0
        if x != null:
            self.x = x * 1.0
            self.y = y * 1.0
            self.sx = self.x
            self.sy = self.y

func _abs(v):
    if v < 0:
        return -v
    return v

class CoordinateSpace:
    func init(width, height, dpi=96):
        if width <= 0 or height <= 0:
            raise("ArgumentError", "CoordinateSpace : dimensions > 0 attendues")
        self.width = width
        self.height = height
        self.dpi = dpi

    func scale():
        return self.dpi / 96.0

    func normalize(x, y):
        return [x / self.width, y / self.height]

    func denormalize(u, v):
        return [u * self.width, v * self.height]

    func to_dp(x, y):
        s := self.scale()
        return [x / s, y / s]

    func from_dp(x, y):
        s := self.scale()
        return [x * s, y * s]

    # Repère local d'un élément d'origine (ox, oy) et d'échelle k.
    func to_local(x, y, ox, oy, k=1.0):
        if k == 0:
            raise("ArgumentError", "to_local : échelle non nulle attendue")
        return [(x - ox) / k, (y - oy) / k]

    func from_local(lx, ly, ox, oy, k=1.0):
        return [lx * k + ox, ly * k + oy]

    func contains(x, y):
        return x >= 0 and y >= 0 and x < self.width and y < self.height

    # Conversion vers un autre espace (redimensionnement de fenêtre) en gardant la position relative.
    func map_to(other, x, y):
        n := self.normalize(x, y)
        return other.denormalize(n[0], n[1])
