# ALEX STANDARD LIBRARY — particles
#
# Systèmes de particules 2D : émetteurs continus ou en rafales, formes d'émission (point, cercle, anneau,
# rectangle, segment), durée de vie, vitesse et angle aléatoires, gravité, frottement, accélération radiale,
# rotation, taille et couleur au cours de la vie (dégradés), image ou animation (sprite.Frame / gl.render.Region),
# mélange alpha ou additif, espace monde ou local. Préréglages : feu, fumée, explosion, étincelles, pluie, neige,
# poussière, magie. Dessin par gl.render.SpriteBatch (GPU) ou sur un canvas ui.
#
#   use particles
#   feu := particles.Emitter(particles.preset("fire"), [400, 300])
#   sys := particles.ParticleSystem()
#   sys.add(feu)
#   sys.add(particles.Emitter(particles.preset("explosion"), [200, 200]))   # rafale unique, retirée à la fin
#   # à chaque image :
#   sys.update(dt)
#   batch.begin() ; sys.draw(batch) ; batch.end()
#
# CONFIGURATION (dict, toutes les clés facultatives ; [a, b] = valeur aléatoire uniforme entre a et b) :
#   rate (particules/s), burst (nombre émis d'un coup au départ), bursts ([[instant s, nombre], ...]),
#   duration (s, null = sans fin), max (particules vivantes au plus), lifetime [a, b],
#   speed [a, b], angle (degrés, 0 = droite, 90 = bas), spread (degrés autour de angle),
#   gravity [gx, gy] (px/s²), drag (0..1 perdu par seconde), radial_accel [a, b] (px/s², depuis l'émetteur),
#   shape "point" | "circle" | "ring" | "rect" | "line", radius, size [l, h] (rect), line [[x0, y0], [x1, y1]],
#   size_start [a, b], size_end [a, b] (px ; ou size_curve [[t, valeur], ...]),
#   colors [[t, [r, g, b, a]], ...] (t de 0 à 1 sur la vie), rotation [a, b] (degrés), spin [a, b] (degrés/s),
#   align (orienter selon la vitesse), image (Frame, Region, Texture ou list d'images = animation sur la vie),
#   blend "alpha" | "add", local (particules qui suivent l'émetteur), seed.
#
# PERFORMANCES : quelques milliers de particules en tout à 60 images/s (mise à jour en ALEX) ; préférer moins de
#   particules plus grandes.
#
# Erreurs : ValueError (préréglage ou forme inconnus).

from core use len, type, to_int
from collections use append
use math
use ui.canvas as _cv
use ui.paint as _paint

const _DEG := 0.017453292519943295

func _range(v, default):
    if v == null:
        return [default, default]
    if type(v) == "list":
        if len(v) == 1:
            return [v[0] * 1.0, v[0] * 1.0]
        return [v[0] * 1.0, v[1] * 1.0]
    return [v * 1.0, v * 1.0]

func _get(cfg, key, default):
    if key in cfg:
        return cfg[key]
    return default

# Valeur d'une courbe [[t, v], ...] (v nombre ou liste) à l'instant t (0..1), interpolation linéaire.
func sample_curve(curve, t):
    n := len(curve)
    if n == 0:
        return null
    if t <= curve[0][0]:
        return curve[0][1]
    k := 1
    while k < n:
        if t <= curve[k][0]:
            a := curve[k - 1]
            b := curve[k]
            span := b[0] - a[0]
            f := (t - a[0]) / span if span > 0 else 1.0
            if type(a[1]) == "list":
                return [a[1][j] + (b[1][j] - a[1][j]) * f for j in 0..len(a[1])]
            return a[1] + (b[1] - a[1]) * f
        k += 1
    return curve[n - 1][1]

class Emitter:
    func init(config=null, position=null):
        c := config if config != null else {}
        self.config = c
        self.position = [position[0] * 1.0, position[1] * 1.0] if position != null else [0.0, 0.0]
        self.rate = _get(c, "rate", 0.0) * 1.0
        self.burst = _get(c, "burst", 0)
        self.bursts = [[b[0] * 1.0, b[1]] for b in _get(c, "bursts", [])]
        self.duration = _get(c, "duration", null)
        self.max = _get(c, "max", 1000)
        self.lifetime = _range(_get(c, "lifetime", null), 1.0)
        self.speed = _range(_get(c, "speed", null), 50.0)
        self.angle = _get(c, "angle", -90.0) * 1.0
        self.spread = _get(c, "spread", 360.0) * 1.0
        g := _get(c, "gravity", [0.0, 0.0])
        self.gravity = [g[0] * 1.0, g[1] * 1.0]
        self.drag = _get(c, "drag", 0.0) * 1.0
        self.radial = _range(_get(c, "radial_accel", null), 0.0)
        self.shape = _get(c, "shape", "point")
        if self.shape != "point" and self.shape != "circle" and self.shape != "ring" and self.shape != "rect" and self.shape != "line":
            raise("ValueError", "particles : forme d'émission inconnue '" + str(self.shape) + "'")
        self.radius = _get(c, "radius", 10.0) * 1.0
        self.area = _get(c, "size", [20.0, 20.0])
        self.line = _get(c, "line", [[-10.0, 0.0], [10.0, 0.0]])
        self.size_start = _range(_get(c, "size_start", null), 8.0)
        self.size_end = _range(_get(c, "size_end", null), 8.0)
        self.size_curve = _get(c, "size_curve", null)
        self.colors = _get(c, "colors", [[0.0, [1.0, 1.0, 1.0, 1.0]], [1.0, [1.0, 1.0, 1.0, 0.0]]])
        self.rot = _range(_get(c, "rotation", null), 0.0)
        self.spin = _range(_get(c, "spin", null), 0.0)
        self.align = _get(c, "align", false)
        img := _get(c, "image", null)
        self.images = img if type(img) == "list" else ([img] if img != null else [])
        self.blend = _get(c, "blend", "alpha")
        self.local = _get(c, "local", false)
        self._seed = _get(c, "seed", 12345) & 0x7FFFFFFF
        self.active = true
        self.age = 0.0
        self._acc = 0.0
        self._burst_done = false
        self._next_burst = 0
        # particules : tableaux parallèles (rapide en ALEX)
        self.px = []
        self.py = []
        self.vx = []
        self.vy = []
        self.life = []
        self.ttl = []
        self.s0 = []
        self.s1 = []
        self.rot0 = []
        self.spn = []
        self.rad = []

    func count():
        return len(self.px)

    # Fini : plus d'émission et plus aucune particule vivante.
    func done():
        return not self.active and len(self.px) == 0

    func stop():
        self.active = false

    func restart():
        self.active = true
        self.age = 0.0
        self._acc = 0.0
        self._burst_done = false
        self._next_burst = 0

    func move_to(x, y):
        self.position = [x * 1.0, y * 1.0]

    # Aléa rapide (congruence linéaire), reproductible avec la clé « seed ».
    func _rand():
        self._seed = (self._seed * 1103515245 + 12345) & 0x7FFFFFFF
        return self._seed / 2147483648.0

    func _u(r):
        if r[0] == r[1]:
            return r[0]
        return r[0] + (r[1] - r[0]) * self._rand()

    # Émet n particules.
    func emit(n):
        k := 0
        while k < n and len(self.px) < self.max:
            ox := 0.0
            oy := 0.0
            sh := self.shape
            if sh == "circle":
                a := self._rand() * 6.283185307179586
                r := self.radius * math.sqrt(self._rand())
                ox = math.cos(a) * r
                oy = math.sin(a) * r
            elif sh == "ring":
                a := self._rand() * 6.283185307179586
                ox = math.cos(a) * self.radius
                oy = math.sin(a) * self.radius
            elif sh == "rect":
                ox = (self._rand() - 0.5) * self.area[0]
                oy = (self._rand() - 0.5) * self.area[1]
            elif sh == "line":
                t := self._rand()
                ox = self.line[0][0] + (self.line[1][0] - self.line[0][0]) * t
                oy = self.line[0][1] + (self.line[1][1] - self.line[0][1]) * t
            ang := (self.angle + (self._rand() - 0.5) * self.spread) * _DEG
            sp := self._u(self.speed)
            if self.local:
                append(self.px, ox)
                append(self.py, oy)
            else:
                append(self.px, self.position[0] + ox)
                append(self.py, self.position[1] + oy)
            append(self.vx, math.cos(ang) * sp)
            append(self.vy, math.sin(ang) * sp)
            append(self.life, 0.0)
            append(self.ttl, self._u(self.lifetime))
            append(self.s0, self._u(self.size_start))
            append(self.s1, self._u(self.size_end))
            append(self.rot0, self._u(self.rot) * _DEG)
            append(self.spn, self._u(self.spin) * _DEG)
            append(self.rad, self._u(self.radial))
            k += 1

    func update(dt):
        if self.active:
            if not self._burst_done:
                self._burst_done = true
                if self.burst > 0:
                    self.emit(self.burst)
            while self._next_burst < len(self.bursts) and self.bursts[self._next_burst][0] <= self.age:
                self.emit(self.bursts[self._next_burst][1])
                self._next_burst += 1
            if self.rate > 0.0:
                self._acc += self.rate * dt
                n := to_int(self._acc)
                if n > 0:
                    self._acc -= n
                    self.emit(n)
            self.age += dt
            if self.duration != null and self.age >= self.duration:
                self.active = false
        # mise à jour et compactage des tableaux
        gx := self.gravity[0] * dt
        gy := self.gravity[1] * dt
        damp := 1.0 - self.drag * dt
        if damp < 0.0:
            damp = 0.0
        cx := 0.0 if self.local else self.position[0]
        cy := 0.0 if self.local else self.position[1]
        has_rad := self.radial[0] != 0.0 or self.radial[1] != 0.0
        n := len(self.px)
        w := 0
        k := 0
        px := self.px
        py := self.py
        vx := self.vx
        vy := self.vy
        life := self.life
        ttl := self.ttl
        while k < n:
            l := life[k] + dt
            if l < ttl[k]:
                x := vx[k] * damp + gx
                y := vy[k] * damp + gy
                if has_rad:
                    dx := px[k] - cx
                    dy := py[k] - cy
                    d := math.sqrt(dx * dx + dy * dy)
                    if d > 0.0001:
                        x += dx / d * self.rad[k] * dt
                        y += dy / d * self.rad[k] * dt
                px[w] = px[k] + x * dt
                py[w] = py[k] + y * dt
                vx[w] = x
                vy[w] = y
                life[w] = l
                ttl[w] = ttl[k]
                self.s0[w] = self.s0[k]
                self.s1[w] = self.s1[k]
                self.rot0[w] = self.rot0[k] + self.spn[k] * dt
                self.spn[w] = self.spn[k]
                self.rad[w] = self.rad[k]
                w += 1
            k += 1
        if w < n:
            self.px = px[0:w]
            self.py = py[0:w]
            self.vx = vx[0:w]
            self.vy = vy[0:w]
            self.life = life[0:w]
            self.ttl = ttl[0:w]
            self.s0 = self.s0[0:w]
            self.s1 = self.s1[0:w]
            self.rot0 = self.rot0[0:w]
            self.spn = self.spn[0:w]
            self.rad = self.rad[0:w]

    # État de la particule k : [x, y, taille, couleur, rotation (rad), image ou null].
    func particle(k):
        t := self.life[k] / self.ttl[k]
        size := 0.0
        if self.size_curve != null:
            size = sample_curve(self.size_curve, t)
        else:
            size = self.s0[k] + (self.s1[k] - self.s0[k]) * t
        col := sample_curve(self.colors, t)
        rot := self.rot0[k]
        if self.align:
            rot = math.atan2(self.vy[k], self.vx[k])
        img := null
        ni := len(self.images)
        if ni == 1:
            img = self.images[0]
        elif ni > 1:
            idx := to_int(t * ni)
            img = self.images[idx if idx < ni else ni - 1]
        x := self.px[k]
        y := self.py[k]
        if self.local:
            x += self.position[0]
            y += self.position[1]
        return [x, y, size, col, rot, img]

    # Dessin dans un gl.render.SpriteBatch commencé.
    func draw(batch):
        n := len(self.px)
        if n == 0:
            return
        old := batch.blend
        if self.blend != old:
            batch.set_blend(self.blend)
        k := 0
        while k < n:
            p := self.particle(k)
            s := p[2]
            if s > 0.0:
                if p[5] == null:
                    if p[4] == 0.0:
                        batch.rect(p[0] - s * 0.5, p[1] - s * 0.5, s, s, p[3])
                    else:
                        batch.draw(batch.renderer.white, p[0] - s * 0.5, p[1] - s * 0.5, s, s, p[3], p[4])
                else:
                    batch.draw(p[5], p[0] - s * 0.5, p[1] - s * 0.5, s, s, p[3], p[4])
            k += 1
        if self.blend != old:
            batch.set_blend(old)

    # Dessin sur un canvas ui : disques de couleur (ou images ui si `image` est une image ui).
    func draw_canvas(canvas):
        k := 0
        while k < len(self.px):
            p := self.particle(k)
            c := p[3]
            a := c[3] if len(c) > 3 else 1.0
            paint := _paint.fill({"r": _b255(c[0]), "g": _b255(c[1]), "b": _b255(c[2]), "a": _b255(a)})
            _cv.circle(canvas, p[0], p[1], p[2] * 0.5, paint)
            k += 1

func _b255(v):
    x := to_int(v * 255.0)
    if x < 0:
        return 0
    if x > 255:
        return 255
    return x

class ParticleSystem:
    func init():
        self.emitters = []

    func add(e):
        append(self.emitters, e)
        return e

    func remove(e):
        self.emitters = [x for x in self.emitters if x != e]

    # Met à jour ; les émetteurs terminés (rafales finies, plus de particules) sont retirés.
    func update(dt):
        alive := []
        for e in self.emitters:
            e.update(dt)
            if not e.done():
                append(alive, e)
        self.emitters = alive

    func count():
        n := 0
        for e in self.emitters:
            n += e.count()
        return n

    func draw(batch):
        for e in self.emitters:
            e.draw(batch)

    func draw_canvas(canvas):
        for e in self.emitters:
            e.draw_canvas(canvas)

    func clear():
        self.emitters = []

# ---------------------------------------------------------------------------------------------------------------------
# Préréglages (copies modifiables)
# ---------------------------------------------------------------------------------------------------------------------

func preset(name):
    if name == "fire":
        return {"rate": 80, "lifetime": [0.5, 1.0], "speed": [40, 90], "angle": -90, "spread": 30,
                "shape": "circle", "radius": 8, "size_start": [18, 26], "size_end": [4, 8], "blend": "add",
                "gravity": [0, -60], "colors": [[0.0, [1.0, 0.9, 0.4, 0.9]], [0.4, [1.0, 0.45, 0.1, 0.7]], [1.0, [0.4, 0.05, 0.0, 0.0]]]}
    if name == "smoke":
        return {"rate": 20, "lifetime": [1.5, 3.0], "speed": [15, 35], "angle": -90, "spread": 25,
                "shape": "circle", "radius": 6, "size_start": [12, 18], "size_end": [40, 60], "drag": 0.3,
                "spin": [-30, 30], "colors": [[0.0, [0.4, 0.4, 0.4, 0.0]], [0.15, [0.35, 0.35, 0.35, 0.5]], [1.0, [0.2, 0.2, 0.2, 0.0]]]}
    if name == "explosion":
        return {"burst": 120, "duration": 0.0, "lifetime": [0.4, 1.0], "speed": [80, 320], "spread": 360,
                "size_start": [10, 18], "size_end": [0, 2], "drag": 1.5, "blend": "add",
                "colors": [[0.0, [1.0, 1.0, 0.8, 1.0]], [0.3, [1.0, 0.6, 0.1, 0.9]], [1.0, [0.5, 0.1, 0.0, 0.0]]]}
    if name == "sparks":
        return {"burst": 40, "duration": 0.0, "lifetime": [0.3, 0.7], "speed": [150, 400], "spread": 360,
                "size_start": [3, 4], "size_end": [1, 2], "gravity": [0, 600], "align": true, "blend": "add",
                "colors": [[0.0, [1.0, 0.95, 0.6, 1.0]], [1.0, [1.0, 0.4, 0.1, 0.0]]]}
    if name == "rain":
        return {"rate": 300, "lifetime": [0.8, 1.0], "speed": [600, 750], "angle": 100, "spread": 4,
                "shape": "line", "line": [[-640, -20], [640, -20]], "size_start": [2, 3], "size_end": [2, 3],
                "align": true, "max": 2000, "colors": [[0.0, [0.6, 0.7, 0.9, 0.6]], [1.0, [0.6, 0.7, 0.9, 0.4]]]}
    if name == "snow":
        return {"rate": 60, "lifetime": [5.0, 8.0], "speed": [30, 60], "angle": 90, "spread": 30,
                "shape": "line", "line": [[-640, -20], [640, -20]], "size_start": [3, 6], "size_end": [3, 6],
                "max": 1500, "colors": [[0.0, [1.0, 1.0, 1.0, 0.0]], [0.1, [1.0, 1.0, 1.0, 0.9]], [1.0, [1.0, 1.0, 1.0, 0.8]]]}
    if name == "dust":
        return {"burst": 12, "duration": 0.0, "lifetime": [0.3, 0.6], "speed": [20, 60], "angle": -90, "spread": 160,
                "size_start": [4, 7], "size_end": [10, 14], "drag": 2.0, "gravity": [0, 40],
                "colors": [[0.0, [0.7, 0.62, 0.5, 0.6]], [1.0, [0.7, 0.62, 0.5, 0.0]]]}
    if name == "magic":
        return {"rate": 50, "lifetime": [0.8, 1.5], "speed": [10, 40], "spread": 360, "shape": "ring", "radius": 24,
                "radial_accel": [-80, -40], "size_start": [5, 8], "size_end": [0, 1], "spin": [-180, 180], "blend": "add",
                "colors": [[0.0, [0.5, 0.7, 1.0, 0.0]], [0.2, [0.6, 0.5, 1.0, 1.0]], [1.0, [1.0, 0.4, 0.9, 0.0]]]}
    raise("ValueError", "particles.preset : préréglage inconnu '" + str(name) + "' (fire, smoke, explosion, sparks, rain, snow, dust, magic)")
