# ALEX STANDARD LIBRARY — physics.physics2d
#
# Physique 2D pour les jeux : formes (cercle, boîte, polygone convexe, demi-plan), collisions avec manifolds de contacts
# (SAT + découpage des arêtes), corps rigides avec solveur d'impulsions séquentielles (friction de Coulomb, restitution,
# endormissement), détection continue anti-traversée, articulations (pivot, soudure, distance / corde / ressort),
# raycasts et requêtes de recouvrement, couches, déclencheurs et événements de contact. ALEX pur. Même esprit et mêmes
# noms que `physics` (3D).
#
#   use physics.physics2d as p2
#   w := p2.World()                                               # gravité (0, -9.81) par défaut
#   w.add(p2.static_body(p2.halfplane([0, 1], 0)))                 # sol : tout ce qui est sous y = 0 est solide
#   ball := w.add(p2.Body(p2.circle(0.5), 1.0, [0, 5]))
#   ball.restitution = 0.6
#   crate := w.add(p2.Body(p2.box([0.5, 0.5]), 2.0, [2, 3], 0.3))   # demi-dimensions, masse, position, angle (rad)
#   for i in range(600):
#       w.step(1.0 / 60.0)
#   hit := w.raycast([0, 10], [0, -1], 100)                       # {"body", "t", "point", "normal"} ou null
#
# CONVENTIONS : repère main droite, Y vers le haut, angles en radians dans le sens trigonométrique, unités SI.
#   Les vecteurs sont des listes [x, y]. Une forme est centrée sur le centre de masse du corps. Un contact est
#   {"normal": n, "points": [[point, profondeur], ...]} : n unitaire, de A vers B ; profondeur > 0 = interpénétration.
# FORMES : circle(rayon), box(demi-dimensions), polygon(sommets) convexe (recentré sur son centre de gravité, orienté
#   dans le sens trigonométrique), halfplane(normale, décalage) = demi-espace n·p <= décalage (statique uniquement).
# TYPES DE CORPS : mass > 0 = dynamique ; mass == 0 = statique ; kinematic_body = déplacé par sa vitesse.
# ARTICULATIONS : revolute_joint (pivot, limites d'angle, moteur), weld_joint, distance_joint (tige, corde),
#   spring_joint ; w.add_joint(j). Même principe que `physics` : résolues avec les contacts, îlot de sommeil commun.
# LIMITES : pas de capsule 2D (utiliser un polygone ou deux cercles), pas de polygones concaves (les assembler à partir
#   de plusieurs corps reliés par weld_joint), pas de glissière 2D.
#
# Erreurs : ValueError (forme ou paramètre invalide), TypeError.

use math
use physics.spatial as spatial
from core use len, to_int
from collections use append, pop, keys

const VERSION := "1.0.0"
const EPS := 0.000000001
const BIG := 1000000000000.0
const _UID := [0]

# =============================================================================
# Petits outils 2D (listes de 2 flottants), internes
# =============================================================================

func _dot(a, b):
    return a[0] * b[0] + a[1] * b[1]

func _cross(a, b):
    return a[0] * b[1] - a[1] * b[0]

func _sub(a, b):
    return [a[0] - b[0], a[1] - b[1]]

func _add(a, b):
    return [a[0] + b[0], a[1] + b[1]]

func _scale(a, s):
    return [a[0] * s, a[1] * s]

func _len(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1])

func _norm(a):
    l := _len(a)
    if l < EPS:
        return [0.0, 0.0]
    return [a[0] / l, a[1] / l]

# Rotation d'un vecteur par (c, s) = (cos, sin).
func _rot(c, s, v):
    return [c * v[0] - s * v[1], s * v[0] + c * v[1]]

func _clip(x, m):
    if x > m:
        return m
    if x < 0.0 - m:
        return 0.0 - m
    return x

func _pair_key(a, b):
    if a.uid < b.uid:
        return a.uid * 2147483648 + b.uid
    return b.uid * 2147483648 + a.uid

# =============================================================================
# Formes
# =============================================================================

func circle(radius):
    if radius <= 0:
        raise("ValueError", "physics2d.circle : rayon > 0 requis")
    return {"type": "circle", "radius": radius * 1.0}

# Boîte de demi-dimensions half = [hx, hy].
func box(half):
    if half[0] <= 0 or half[1] <= 0:
        raise("ValueError", "physics2d.box : demi-dimensions > 0 requises")
    s := polygon([[0.0 - half[0], 0.0 - half[1]], [half[0], 0.0 - half[1]], [half[0], half[1]], [0.0 - half[0], half[1]]])
    s["half"] = [half[0] * 1.0, half[1] * 1.0]
    return s

func box_from_size(width, height):
    return box([width * 0.5, height * 0.5])

# Polygone convexe (au moins 3 sommets), dans un sens quelconque ; recentré sur son centre de gravité.
func polygon(verts):
    n := len(verts)
    if n < 3:
        raise("ValueError", "physics2d.polygon : au moins 3 sommets requis")
    v := []
    for p in verts:
        append(v, [p[0] * 1.0, p[1] * 1.0])
    area := 0.0
    cx := 0.0
    cy := 0.0
    i := 0
    while i < n:
        a := v[i]
        b := v[(i + 1) % n]
        cr := _cross(a, b)
        area = area + cr * 0.5
        cx = cx + (a[0] + b[0]) * cr
        cy = cy + (a[1] + b[1]) * cr
        i += 1
    if math.abs(area) < EPS:
        raise("ValueError", "physics2d.polygon : aire nulle")
    if area < 0:
        v = _reversed(v)
        area = 0.0 - area
        cx = 0.0 - cx
        cy = 0.0 - cy
    c := [cx / (6.0 * area), cy / (6.0 * area)]
    w := []
    for p in v:
        append(w, [p[0] - c[0], p[1] - c[1]])
    normals := []
    sg := 0
    i = 0
    while i < n:
        e := _sub(w[(i + 1) % n], w[i])
        if _len(e) < EPS:
            raise("ValueError", "physics2d.polygon : sommets confondus")
        append(normals, _norm([e[1], 0.0 - e[0]]))
        t := _cross(e, _sub(w[(i + 2) % n], w[(i + 1) % n]))
        if t < 0.0 - 0.000000001:
            raise("ValueError", "physics2d.polygon : polygone non convexe")
        i += 1
    rad := 0.0
    num := 0.0
    den := 0.0
    i = 0
    while i < n:
        a := w[i]
        b := w[(i + 1) % n]
        cr := _cross(a, b)
        num = num + cr * (_dot(a, a) + _dot(a, b) + _dot(b, b))
        den = den + cr
        rad = math.max(rad, _len(a))
        i += 1
    return {"type": "polygon", "verts": w, "normals": normals, "area": area, "radius": rad, "inertia_unit": num / (6.0 * den), "center": c}

func _reversed(a):
    out := []
    i := len(a) - 1
    while i >= 0:
        append(out, a[i])
        i -= 1
    return out

# Demi-espace {p : n·p <= offset}. La normale est normalisée.
func halfplane(normal, offset=0.0):
    n := _norm(normal)
    if _len(n) < 0.5:
        raise("ValueError", "physics2d.halfplane : normale nulle")
    return {"type": "halfplane", "normal": n, "offset": offset * 1.0}

func shape_area(shape):
    t := shape["type"]
    if t == "circle":
        return math.PI * shape["radius"] * shape["radius"]
    if t == "polygon":
        return shape["area"]
    return 0.0

# =============================================================================
# Corps
# =============================================================================

class Body:
    func init(shape, mass=1.0, position=null, angle=0.0):
        self.shape = shape
        self.position = [0.0, 0.0]
        if position != null:
            self.position = [position[0] * 1.0, position[1] * 1.0]
        self.angle = angle * 1.0
        self.velocity = [0.0, 0.0]
        self.angular_velocity = 0.0
        self.force = [0.0, 0.0]
        self.torque = 0.0
        self.restitution = 0.2
        self.friction = 0.5
        self.linear_damping = 0.01
        self.angular_damping = 0.05
        self.gravity_scale = 1.0
        self.layer = 1
        self.mask = 4294967295
        self.is_trigger = false
        self.lock_rotation = false
        self.allow_sleep = true
        self.sleeping = false
        self.sleep_timer = 0.0
        self.user_data = null
        self.continuous = true
        self.kind = "dynamic"
        self.mass = mass * 1.0
        self.inv_mass = 0.0
        self.inv_inertia = 0.0
        self.id = 0
        _UID[0] = _UID[0] + 1
        self.uid = _UID[0]
        self.joint_count = 0
        self._c = 1.0
        self._s = 0.0
        self._wv = []
        self._wn = []
        self.set_mass(mass)
        self.refresh()

    func set_mass(mass):
        if mass < 0:
            raise("ValueError", "physics2d.Body.set_mass : masse négative")
        if self.shape["type"] == "halfplane" and mass != 0:
            raise("ValueError", "physics2d.Body : un demi-plan est forcément statique (masse 0)")
        self.mass = mass * 1.0
        if mass == 0:
            self.inv_mass = 0.0
            self.inv_inertia = 0.0
            if self.kind == "dynamic":
                self.kind = "static"
        else:
            self.inv_mass = 1.0 / mass
            t := self.shape["type"]
            i := 0.0
            if t == "circle":
                i = 0.5 * mass * self.shape["radius"] * self.shape["radius"]
            else:
                i = mass * self.shape["inertia_unit"]
            self.inv_inertia = 1.0 / i
            if self.kind == "static":
                self.kind = "dynamic"
        if self.lock_rotation:
            self.inv_inertia = 0.0

    func is_static():
        return self.kind == "static"

    func is_dynamic():
        return self.kind == "dynamic"

    # Recalcule les données dérivées (cos, sin, sommets et normales monde) : à appeler après avoir modifié position ou
    # angle à la main.
    func refresh():
        self._c = math.cos(self.angle)
        self._s = math.sin(self.angle)
        if self.shape["type"] == "polygon":
            wv := []
            wn := []
            vs := self.shape["verts"]
            ns := self.shape["normals"]
            k := 0
            while k < len(vs):
                r := _rot(self._c, self._s, vs[k])
                append(wv, [self.position[0] + r[0], self.position[1] + r[1]])
                append(wn, _rot(self._c, self._s, ns[k]))
                k += 1
            self._wv = wv
            self._wn = wn

    func set_position(p):
        self.position = [p[0] * 1.0, p[1] * 1.0]
        self.refresh()
        self.wake()

    func set_angle(a):
        self.angle = a * 1.0
        self.refresh()
        self.wake()

    func wake():
        self.sleeping = false
        self.sleep_timer = 0.0

    func core_radius():
        t := self.shape["type"]
        if t == "circle":
            return self.shape["radius"]
        if t == "polygon":
            m := BIG
            k := 0
            vs := self._wv
            ns := self._wn
            while k < len(vs):
                d := _dot(_sub(self.position, vs[k]), ns[k])
                if d < m:
                    m = d
                k += 1
            return math.max(m, 0.001)
        return BIG

    func apply_force(f):
        self.force = _add(self.force, f)
        self.wake()

    func apply_force_at(f, point):
        self.force = _add(self.force, f)
        self.torque = self.torque + _cross(_sub(point, self.position), f)
        self.wake()

    func apply_torque(t):
        self.torque = self.torque + t
        self.wake()

    func apply_impulse(j):
        if self.kind != "dynamic":
            return null
        self.velocity = [self.velocity[0] + j[0] * self.inv_mass, self.velocity[1] + j[1] * self.inv_mass]
        self.wake()

    func apply_impulse_at(j, point):
        if self.kind != "dynamic":
            return null
        self.velocity = [self.velocity[0] + j[0] * self.inv_mass, self.velocity[1] + j[1] * self.inv_mass]
        self.angular_velocity = self.angular_velocity + self.inv_inertia * _cross(_sub(point, self.position), j)
        self.wake()

    func velocity_at(point):
        r := _sub(point, self.position)
        return [self.velocity[0] - self.angular_velocity * r[1], self.velocity[1] + self.angular_velocity * r[0]]

    func kinetic_energy():
        e := 0.5 * self.mass * _dot(self.velocity, self.velocity)
        if self.kind == "dynamic" and self.inv_inertia > 0.0:
            e = e + 0.5 * self.angular_velocity * self.angular_velocity / self.inv_inertia
        return e

    # Boîte englobante monde [min, max] (infinie pour un demi-plan).
    func aabb():
        t := self.shape["type"]
        p := self.position
        if t == "circle":
            r := self.shape["radius"]
            return [[p[0] - r, p[1] - r], [p[0] + r, p[1] + r]]
        if t == "polygon":
            lo := [BIG, BIG]
            hi := [0.0 - BIG, 0.0 - BIG]
            for v in self._wv:
                lo = [math.min(lo[0], v[0]), math.min(lo[1], v[1])]
                hi = [math.max(hi[0], v[0]), math.max(hi[1], v[1])]
            return [lo, hi]
        return [[0.0 - BIG, 0.0 - BIG], [BIG, BIG]]

    # Sommets monde d'un polygone (liste vide pour les autres formes).
    func vertices():
        return self._wv

func static_body(shape, position=null, angle=0.0):
    return Body(shape, 0.0, position, angle)

func kinematic_body(shape, position=null, angle=0.0):
    b := Body(shape, 0.0, position, angle)
    b.kind = "kinematic"
    return b

# Corps statique minuscule servant d'ancrage au monde pour une articulation.
func fixed_point(position):
    return static_body(circle(0.001), position)

# =============================================================================
# Détection de collisions
# =============================================================================

func _rank(shape):
    t := shape["type"]
    if t == "circle":
        return 0
    if t == "polygon":
        return 1
    return 2

# Contact entre deux corps : {"normal", "points"} (normale de A vers B) ou null. Ne tient pas compte des couches.
func collide(a, b):
    if _rank(a.shape) > _rank(b.shape):
        c := collide(b, a)
        if c == null:
            return null
        return {"normal": _scale(c["normal"], -1.0), "points": c["points"]}
    ta := a.shape["type"]
    tb := b.shape["type"]
    if ta == "circle":
        if tb == "circle":
            return _circle_circle(a.position, a.shape["radius"], b.position, b.shape["radius"])
        if tb == "polygon":
            c := _poly_circle(b, a.position, a.shape["radius"])
            if c == null:
                return null
            return {"normal": _scale(c["normal"], -1.0), "points": c["points"]}
        return _circle_plane(a.position, a.shape["radius"], b.shape)
    if ta == "polygon":
        if tb == "polygon":
            return _poly_poly(a, b)
        return _poly_plane(a, b.shape)
    return null

func _circle_circle(ca, ra, cb, rb):
    d := _sub(cb, ca)
    dist := _len(d)
    if dist >= ra + rb:
        return null
    n := [1.0, 0.0]
    if dist > EPS:
        n = _scale(d, 1.0 / dist)
    mid := [ca[0] + n[0] * (ra - (ra + rb - dist) * 0.5), ca[1] + n[1] * (ra - (ra + rb - dist) * 0.5)]
    return {"normal": n, "points": [[mid, ra + rb - dist]]}

# Cercle (A) contre demi-plan (B) : normale de A vers B = -n (n pointe hors de la matière, vers le cercle).
func _circle_plane(c, r, pl):
    n := pl["normal"]
    dist := _dot(n, c) - pl["offset"]
    if dist >= r:
        return null
    mid := c[0] - n[0] * (dist + r) * 0.5
    midy := c[1] - n[1] * (dist + r) * 0.5
    return {"normal": [0.0 - n[0], 0.0 - n[1]], "points": [[[mid, midy], r - dist]]}

# Polygone contre cercle : normale du polygone vers le cercle.
func _poly_circle(pb, c, r):
    vs := pb._wv
    ns := pb._wn
    n := len(vs)
    best := 0.0 - BIG
    bi := 0
    i := 0
    while i < n:
        s := _dot(ns[i], _sub(c, vs[i]))
        if s > r:
            return null
        if s > best:
            best = s
            bi = i
        i += 1
    v1 := vs[bi]
    v2 := vs[(bi + 1) % n]
    if best < EPS:
        # centre dans le polygone : sur la face la plus proche
        nn := ns[bi]
        return {"normal": nn, "points": [[[c[0] - nn[0] * (r + best) * 0.5, c[1] - nn[1] * (r + best) * 0.5], r - best]]}
    e := _sub(v2, v1)
    u1 := _dot(_sub(c, v1), e)
    u2 := _dot(_sub(c, v2), _scale(e, -1.0))
    if u1 <= 0.0:
        d := _sub(c, v1)
        dist := _len(d)
        if dist >= r:
            return null
        nn := _norm(d)
        return {"normal": nn, "points": [[v1, r - dist]]}
    if u2 <= 0.0:
        d := _sub(c, v2)
        dist := _len(d)
        if dist >= r:
            return null
        nn := _norm(d)
        return {"normal": nn, "points": [[v2, r - dist]]}
    nn := ns[bi]
    return {"normal": nn, "points": [[[c[0] - nn[0] * best, c[1] - nn[1] * best], r - best]]}

# Polygone contre demi-plan (le plan est B) : normale de A vers B = -n.
func _poly_plane(a, pl):
    n := pl["normal"]
    pts := []
    for v in a._wv:
        d := pl["offset"] - _dot(n, v)
        if d > 0.0:
            append(pts, [v, d])
    if len(pts) == 0:
        return null
    # au plus deux points : les plus profonds
    if len(pts) > 2:
        first := pts[0]
        second := pts[1]
        for p in pts:
            if p[1] > first[1]:
                second = first
                first = p
            else:
                if p[1] > second[1] and p != first:
                    second = p
        pts = [first, second]
    return {"normal": _scale(n, -1.0), "points": pts}

# Séparation maximale de B sur les faces de A : [séparation, indice de face].
func _max_sep(a, b):
    best := 0.0 - BIG
    bi := 0
    i := 0
    na := a._wn
    va := a._wv
    while i < len(na):
        mn := BIG
        for v in b._wv:
            d := _dot(na[i], _sub(v, va[i]))
            if d < mn:
                mn = d
        if mn > best:
            best = mn
            bi = i
        i += 1
    return [best, bi]

func _poly_poly(a, b):
    ra := a.shape["radius"] + b.shape["radius"]
    if _len(_sub(b.position, a.position)) > ra:
        return null
    sa := _max_sep(a, b)
    if sa[0] > 0.0:
        return null
    sb := _max_sep(b, a)
    if sb[0] > 0.0:
        return null
    ref := a
    inc := b
    fi := sa[1]
    flip := false
    if sb[0] > sa[0] + 0.0005:
        ref = b
        inc = a
        fi = sb[1]
        flip = true
    rn := ref._wn[fi]
    rv1 := ref._wv[fi]
    rv2 := ref._wv[(fi + 1) % len(ref._wv)]
    # arête incidente : la plus anti-parallèle à la normale de référence
    ii := 0
    md := BIG
    k := 0
    while k < len(inc._wn):
        d := _dot(rn, inc._wn[k])
        if d < md:
            md = d
            ii = k
        k += 1
    p1 := inc._wv[ii]
    p2 := inc._wv[(ii + 1) % len(inc._wv)]
    t := _norm(_sub(rv2, rv1))
    # découpage par les deux côtés de la face de référence
    c1 := _clip_seg(p1, p2, [0.0 - t[0], 0.0 - t[1]], 0.0 - _dot(t, rv1))
    if c1 == null:
        return null
    c2 := _clip_seg(c1[0], c1[1], t, _dot(t, rv2))
    if c2 == null:
        return null
    pts := []
    for q in c2:
        sep := _dot(rn, _sub(q, rv1))
        if sep <= 0.0:
            append(pts, [_sub(q, _scale(rn, sep * 0.5)), 0.0 - sep])
    if len(pts) == 0:
        return null
    n := rn
    if flip:
        n = _scale(rn, -1.0)
    return {"normal": n, "points": pts}

# Découpe le segment [p1, p2] par le demi-plan {p : n·p <= offset}.
func _clip_seg(p1, p2, n, offset):
    d1 := _dot(n, p1) - offset
    d2 := _dot(n, p2) - offset
    out := []
    if d1 <= 0.0:
        append(out, p1)
    if d2 <= 0.0:
        append(out, p2)
    if d1 * d2 < 0.0:
        u := d1 / (d1 - d2)
        append(out, [p1[0] + (p2[0] - p1[0]) * u, p1[1] + (p2[1] - p1[1]) * u])
    if len(out) < 2:
        return null
    return [out[0], out[1]]

# =============================================================================
# Rayons
# =============================================================================

# Rayon contre cercle : t >= 0 de l'entrée, ou null.
func ray_circle(origin, direction, center, radius):
    m := _sub(origin, center)
    a := _dot(direction, direction)
    b := _dot(m, direction)
    c := _dot(m, m) - radius * radius
    if c > 0.0 and b > 0.0:
        return null
    disc := b * b - a * c
    if disc < 0.0 or a < EPS:
        return null
    t := (0.0 - b - math.sqrt(disc)) / a
    if t < 0.0:
        t = 0.0
    return t

# Rayon contre polygone convexe monde (sommets CCW) : [t, normale] ou null (découpage de Cyrus-Beck).
func ray_polygon(origin, direction, verts, normals):
    t0 := 0.0
    t1 := BIG
    nrm := null
    i := 0
    while i < len(verts):
        den := _dot(normals[i], direction)
        num := _dot(normals[i], _sub(verts[i], origin))
        if math.abs(den) < EPS:
            if num < 0.0:
                return null
        else:
            t := num / den
            if den < 0.0:
                if t > t0:
                    t0 = t
                    nrm = normals[i]
            else:
                if t < t1:
                    t1 = t
        if t0 > t1:
            return null
        i += 1
    if nrm == null:
        return [0.0, [0.0 - direction[0], 0.0 - direction[1]]]
    return [t0, nrm]

# =============================================================================
# Monde
# =============================================================================

func _link(adj, a, b):
    if a.uid in adj:
        append(adj[a.uid], b)
    else:
        adj[a.uid] = [b]

func _hits_any(bd, others):
    for ob in others:
        if collide(bd, ob) != null:
            return true
    return false

class World:
    func init():
        self.gravity = [0.0, -9.81]
        self.bodies = []
        self.joints = []
        self.solver_iterations = 10
        self.substeps = 1
        self.baumgarte = 0.2
        self.slop = 0.005
        self.max_bias = 4.0
        self.restitution_threshold = 1.0
        self.allow_sleep = true
        self.sleep_time = 0.5
        self.sleep_linear = 0.05
        self.sleep_angular = 0.05
        self.max_speed = 500.0
        self.ccd = true
        self.broadphase = "auto"
        self.hash_cell = null
        self.hash_threshold = 48
        self.joint_baumgarte = 0.2
        self.joint_max_bias = 10.0
        self.contacts = []
        self.time = 0.0
        self._pairs = {}
        self._on_begin = []
        self._on_end = []
        self._next_id = 1
        self._joint_pairs = {}
        self._active_joints = []

    func add(body):
        body.id = self._next_id
        self._next_id += 1
        body.refresh()
        append(self.bodies, body)
        return body

    func remove(body):
        k := 0
        while k < len(self.bodies):
            if self.bodies[k] == body:
                pop(self.bodies, k)
                for j in self.joints[0:len(self.joints)]:
                    if j.a == body or j.b == body:
                        self.remove_joint(j)
                return true
            k += 1
        return false

    func clear():
        self.bodies = []
        self.joints = []
        self.contacts = []
        self._pairs = {}
        self._joint_pairs = {}
        self._active_joints = []

    func add_joint(j):
        append(self.joints, j)
        j.a.joint_count += 1
        j.b.joint_count += 1
        key := _pair_key(j.a, j.b)
        if key in self._joint_pairs:
            append(self._joint_pairs[key], j)
        else:
            self._joint_pairs[key] = [j]
        j.a.wake()
        j.b.wake()
        return j

    func remove_joint(j):
        k := 0
        while k < len(self.joints):
            if self.joints[k] == j:
                pop(self.joints, k)
                j.a.joint_count -= 1
                j.b.joint_count -= 1
                key := _pair_key(j.a, j.b)
                lst := self._joint_pairs[key]
                m := 0
                while m < len(lst):
                    if lst[m] == j:
                        pop(lst, m)
                        break
                    m += 1
                if len(lst) == 0:
                    del self._joint_pairs[key]
                j.a.wake()
                j.b.wake()
                return true
            k += 1
        return false

    # fn(corps_a, corps_b, contact) au début / à la fin d'un contact (déclencheurs inclus).
    func on_begin(fn):
        append(self._on_begin, fn)

    func on_end(fn):
        append(self._on_end, fn)

    func _can_collide(a, b):
        if a.kind != "dynamic" and b.kind != "dynamic":
            return false
        if (a.layer & b.mask) == 0 or (b.layer & a.mask) == 0:
            return false
        if a.joint_count > 0 and b.joint_count > 0:
            key := _pair_key(a, b)
            if key in self._joint_pairs:
                for j in self._joint_pairs[key]:
                    if j.enabled and not j.collide_connected:
                        return false
        return true

    func _candidate_pairs():
        mode := self.broadphase
        if mode == "auto":
            mode = "sweep"
            if len(self.bodies) > self.hash_threshold:
                mode = "hash"
        planes := []
        rest := []
        boxes := []
        for bd in self.bodies:
            if bd.shape["type"] == "halfplane":
                append(planes, bd)
            else:
                append(rest, bd)
                append(boxes, bd.aabb())
        pairs := []
        if mode == "hash":
            cell := self.hash_cell
            if cell == null:
                cell = spatial.suggest_cell_size(_lift(boxes))
            grid := spatial.SpatialHash(cell)
            byid := {}
            k := 0
            while k < len(rest):
                grid.insert(rest[k].id, [boxes[k][0][0], boxes[k][0][1], 0.0], [boxes[k][1][0], boxes[k][1][1], 0.0])
                byid[rest[k].id] = rest[k]
                k += 1
            for pr in grid.pairs():
                a := byid[pr[0]]
                b := byid[pr[1]]
                if self._can_collide(a, b) and not (a.sleeping and b.sleeping):
                    append(pairs, [a, b])
        else:
            order := _sort_by_x(rest, boxes)
            i := 0
            while i < len(order):
                ai := order[i]
                j := i + 1
                while j < len(order) and order[j][0] <= ai[2][1][0]:
                    bj := order[j]
                    if self._can_collide(ai[1], bj[1]) and not (ai[1].sleeping and bj[1].sleeping):
                        if ai[2][0][1] <= bj[2][1][1] and ai[2][1][1] >= bj[2][0][1]:
                            append(pairs, [ai[1], bj[1]])
                    j += 1
                i += 1
        for pl in planes:
            for bd in rest:
                if self._can_collide(pl, bd) and not (pl.sleeping and bd.sleeping):
                    append(pairs, [pl, bd])
        return pairs

    func _find_contacts():
        found := []
        for pr in self._candidate_pairs():
            a := pr[0]
            b := pr[1]
            c := collide(a, b)
            if c != null:
                append(found, {"a": a, "b": b, "normal": c["normal"], "points": c["points"], "trigger": a.is_trigger or b.is_trigger})
        return found

    func step(dt):
        if dt <= 0:
            return null
        n := self.substeps
        if n < 1:
            n = 1
        h := dt / n
        events := {}
        i := 0
        while i < n:
            self._substep(h)
            for c in self.contacts:
                a := c["a"]
                b := c["b"]
                key := f"{a.id}:{b.id}"
                if a.id > b.id:
                    key = f"{b.id}:{a.id}"
                events[key] = c
            i += 1
        self.time = self.time + dt
        for key in keys(events):
            if not (key in self._pairs):
                c := events[key]
                for fn in self._on_begin:
                    fn(c["a"], c["b"], c)
        for key in keys(self._pairs):
            if not (key in events):
                c := self._pairs[key]
                for fn in self._on_end:
                    fn(c["a"], c["b"], c)
        self._pairs = events

    func _substep(h):
        g := self.gravity
        ms2 := self.max_speed * self.max_speed
        for bd in self.bodies:
            if bd.kind == "dynamic" and not bd.sleeping:
                v := bd.velocity
                f := bd.force
                im := bd.inv_mass
                damp := 1.0 / (1.0 + bd.linear_damping * h)
                vx := (v[0] + (g[0] * bd.gravity_scale + f[0] * im) * h) * damp
                vy := (v[1] + (g[1] * bd.gravity_scale + f[1] * im) * h) * damp
                sp2 := vx * vx + vy * vy
                if sp2 > ms2:
                    k := self.max_speed / math.sqrt(sp2)
                    vx = vx * k
                    vy = vy * k
                bd.velocity = [vx, vy]
                if not bd.lock_rotation:
                    bd.angular_velocity = (bd.angular_velocity + bd.torque * bd.inv_inertia * h) / (1.0 + bd.angular_damping * h)
        self._prepare_joints(h)
        found := self._find_contacts()
        for c in found:
            a := c["a"]
            b := c["b"]
            if a.sleeping and not b.sleeping and b.kind != "static" and b.sleep_timer < self.sleep_time * 0.5:
                a.wake()
            if b.sleeping and not a.sleeping and a.kind != "static" and a.sleep_timer < self.sleep_time * 0.5:
                b.wake()
        self.contacts = found
        solid := []
        for c in found:
            if c["trigger"]:
                continue
            if c["a"].sleeping and c["b"].sleeping:
                continue
            append(solid, c)
        self._solve(solid, h)
        for j in self._active_joints:
            if j.break_force != null and j.impulse_magnitude() / h > j.break_force:
                j.broken = true
                j.enabled = false
                j.a.wake()
                j.b.wake()
        for bd in self.bodies:
            if bd.kind == "static" or bd.sleeping:
                continue
            moved := false
            if self.ccd and bd.continuous and bd.kind == "dynamic":
                moved = self._ccd_move(bd, h)
            if not moved:
                bd.position = [bd.position[0] + bd.velocity[0] * h, bd.position[1] + bd.velocity[1] * h]
            bd.angle = bd.angle + bd.angular_velocity * h
            bd.refresh()
            bd.force = [0.0, 0.0]
            bd.torque = 0.0
            if bd.kind == "dynamic":
                self._update_sleep(bd, h)
        if len(self.joints) > 0:
            self._sleep_islands()

    func _prepare_joints(h):
        active := []
        for j in self.joints:
            if not j.enabled:
                continue
            a := j.a
            b := j.b
            ad := a.kind == "dynamic"
            bd := b.kind == "dynamic"
            if ad and bd and a.sleeping != b.sleeping:
                a.wake()
                b.wake()
            if ad and not bd and a.sleeping and b.kind == "kinematic" and (_dot(b.velocity, b.velocity) > 0.0 or b.angular_velocity != 0.0):
                a.wake()
            if bd and not ad and b.sleeping and a.kind == "kinematic" and (_dot(a.velocity, a.velocity) > 0.0 or a.angular_velocity != 0.0):
                b.wake()
            if (not ad or a.sleeping) and (not bd or b.sleeping):
                continue
            j.prepare(h, self.joint_baumgarte, self.joint_max_bias)
            append(active, j)
        self._active_joints = active

    func _sleep_islands():
        adj := {}
        busy := {}
        for j in self.joints:
            if not j.enabled:
                continue
            if j.keeps_awake():
                busy[j.a.uid] = true
                busy[j.b.uid] = true
            if j.a.kind == "dynamic" and j.b.kind == "dynamic":
                _link(adj, j.a, j.b)
                _link(adj, j.b, j.a)
        seen := {}
        for bd in self.bodies:
            if bd.kind != "dynamic" or bd.joint_count == 0 or bd.uid in seen:
                continue
            comp := [bd]
            seen[bd.uid] = true
            qi := 0
            while qi < len(comp):
                cur := comp[qi]
                qi += 1
                if cur.uid in adj:
                    for nb in adj[cur.uid]:
                        if not (nb.uid in seen):
                            seen[nb.uid] = true
                            append(comp, nb)
            ok := true
            for m in comp:
                if m.uid in busy:
                    ok = false
                    break
                if m.sleeping:
                    continue
                if not (self.allow_sleep and m.allow_sleep) or m.sleep_timer < self.sleep_time:
                    ok = false
                    break
            if ok:
                for m in comp:
                    if not m.sleeping:
                        m.sleeping = true
                        m.velocity = [0.0, 0.0]
                        m.angular_velocity = 0.0

    func _update_sleep(bd, h):
        if not (self.allow_sleep and bd.allow_sleep):
            return null
        lin := _dot(bd.velocity, bd.velocity)
        ang := bd.angular_velocity * bd.angular_velocity
        if lin < self.sleep_linear * self.sleep_linear and ang < self.sleep_angular * self.sleep_angular:
            bd.sleep_timer = bd.sleep_timer + h
            if bd.sleep_timer >= self.sleep_time and bd.joint_count == 0:
                bd.sleeping = true
                bd.velocity = [0.0, 0.0]
                bd.angular_velocity = 0.0
        else:
            bd.sleep_timer = 0.0

    # Déplacement continu d'un corps rapide (voir physics) : balayage de la trajectoire du sous-pas.
    func _ccd_move(bd, h):
        v := bd.velocity
        mv := [v[0] * h, v[1] * h]
        dist := _len(mv)
        core := bd.core_radius()
        if dist <= core or bd.is_trigger:
            return false
        start := bd.position
        bb0 := bd.aabb()
        bd.position = _add(start, mv)
        bd.refresh()
        bb1 := bd.aabb()
        bd.position = start
        bd.refresh()
        lo := [math.min(bb0[0][0], bb1[0][0]), math.min(bb0[0][1], bb1[0][1])]
        hi := [math.max(bb0[1][0], bb1[1][0]), math.max(bb0[1][1], bb1[1][1])]
        others := []
        for ob in self.bodies:
            if ob == bd or ob.is_trigger or not self._can_collide(bd, ob):
                continue
            if ob.shape["type"] != "halfplane":
                bo := ob.aabb()
                if bo[0][0] > hi[0] or bo[1][0] < lo[0] or bo[0][1] > hi[1] or bo[1][1] < lo[1]:
                    continue
            append(others, ob)
        if len(others) == 0:
            return false
        if _hits_any(bd, others):
            return false
        steps := to_int(math.ceil(dist / (core * 0.9)))
        if steps > 256:
            steps = 256
        s := 1
        first := 0
        while s <= steps:
            bd.position = [start[0] + mv[0] * s / steps, start[1] + mv[1] * s / steps]
            bd.refresh()
            if _hits_any(bd, others):
                first = s
                break
            s += 1
        if first == 0:
            bd.position = start
            bd.refresh()
            return false
        t_lo := (first - 1) * 1.0 / steps
        t_hi := first * 1.0 / steps
        it := 0
        while it < 8:
            mid := (t_lo + t_hi) * 0.5
            bd.position = [start[0] + mv[0] * mid, start[1] + mv[1] * mid]
            bd.refresh()
            if _hits_any(bd, others):
                t_hi = mid
            else:
                t_lo = mid
            it += 1
        bd.position = [start[0] + mv[0] * t_hi, start[1] + mv[1] * t_hi]
        bd.refresh()
        return true

    # Impulsions séquentielles : friction puis normale, cumul borné par point de contact.
    func _solve(contacts, h):
        rows := []
        for c in contacts:
            a := c["a"]
            b := c["b"]
            n := c["normal"]
            t := [0.0 - n[1], n[0]]
            mu := math.sqrt(a.friction * b.friction)
            e := math.max(a.restitution, b.restitution)
            for pt in c["points"]:
                ra := _sub(pt[0], a.position)
                rb := _sub(pt[0], b.position)
                vn0 := _dot(_sub(b.velocity_at(pt[0]), a.velocity_at(pt[0])), n)
                bias := (self.baumgarte / h) * math.max(pt[1] - self.slop, 0.0)
                if bias > self.max_bias:
                    bias = self.max_bias
                if vn0 < 0.0 - self.restitution_threshold:
                    rest := 0.0 - e * vn0
                    if rest > bias:
                        bias = rest
                rn_a := _cross(ra, n)
                rn_b := _cross(rb, n)
                rt_a := _cross(ra, t)
                rt_b := _cross(rb, t)
                kn := a.inv_mass + b.inv_mass + a.inv_inertia * rn_a * rn_a + b.inv_inertia * rn_b * rn_b
                kt := a.inv_mass + b.inv_mass + a.inv_inertia * rt_a * rt_a + b.inv_inertia * rt_b * rt_b
                mn := 0.0
                mt := 0.0
                if kn > EPS:
                    mn = 1.0 / kn
                if kt > EPS:
                    mt = 1.0 / kt
                append(rows, [a, b, n, t, ra, rb, mu, bias, 0.0, 0.0, mn, mt, rn_a, rn_b, rt_a, rt_b])
        joints := self._active_joints
        it := 0
        while it < self.solver_iterations:
            for j in joints:
                j.solve()
            for r in rows:
                a := r[0]
                b := r[1]
                n := r[2]
                t := r[3]
                va := a.velocity
                vb := b.velocity
                ima := a.inv_mass
                imb := b.inv_mass
                iia := a.inv_inertia
                iib := b.inv_inertia
                # friction
                vrel := t[0] * (vb[0] - va[0]) + t[1] * (vb[1] - va[1]) + b.angular_velocity * r[15] - a.angular_velocity * r[14]
                maxf := r[6] * r[8]
                nacc := r[9] - vrel * r[11]
                if nacc > maxf:
                    nacc = maxf
                if nacc < 0.0 - maxf:
                    nacc = 0.0 - maxf
                l := nacc - r[9]
                r[9] = nacc
                va[0] = va[0] - t[0] * l * ima
                va[1] = va[1] - t[1] * l * ima
                a.angular_velocity = a.angular_velocity - iia * r[14] * l
                vb[0] = vb[0] + t[0] * l * imb
                vb[1] = vb[1] + t[1] * l * imb
                b.angular_velocity = b.angular_velocity + iib * r[15] * l
                # normale
                vrel = n[0] * (vb[0] - va[0]) + n[1] * (vb[1] - va[1]) + b.angular_velocity * r[13] - a.angular_velocity * r[12]
                nacc = r[8] + r[10] * (r[7] - vrel)
                if nacc < 0.0:
                    nacc = 0.0
                l = nacc - r[8]
                r[8] = nacc
                va[0] = va[0] - n[0] * l * ima
                va[1] = va[1] - n[1] * l * ima
                a.angular_velocity = a.angular_velocity - iia * r[12] * l
                vb[0] = vb[0] + n[0] * l * imb
                vb[1] = vb[1] + n[1] * l * imb
                b.angular_velocity = b.angular_velocity + iib * r[13] * l
            it += 1

    # --- requêtes ---

    # Premier corps touché par le rayon : {"body", "t", "point", "normal"} ou null. t en unités de `direction`.
    func raycast(origin, direction, max_distance=null, mask=null, ignore=null):
        best := null
        for bd in self.bodies:
            if ignore != null and bd == ignore:
                continue
            if mask != null and (bd.layer & mask) == 0:
                continue
            h := self._ray_body(bd, origin, direction)
            if h != null and (max_distance == null or h[0] <= max_distance):
                if best == null or h[0] < best["t"]:
                    best = {"body": bd, "t": h[0], "point": [origin[0] + direction[0] * h[0], origin[1] + direction[1] * h[0]], "normal": h[1]}
        return best

    func raycast_all(origin, direction, max_distance=null, mask=null):
        out := []
        for bd in self.bodies:
            if mask != null and (bd.layer & mask) == 0:
                continue
            h := self._ray_body(bd, origin, direction)
            if h != null and (max_distance == null or h[0] <= max_distance):
                append(out, {"body": bd, "t": h[0], "point": [origin[0] + direction[0] * h[0], origin[1] + direction[1] * h[0]], "normal": h[1]})
        return _sort_hits(out)

    func _ray_body(bd, origin, direction):
        t := bd.shape["type"]
        if t == "circle":
            tt := ray_circle(origin, direction, bd.position, bd.shape["radius"])
            if tt == null:
                return null
            p := [origin[0] + direction[0] * tt, origin[1] + direction[1] * tt]
            return [tt, _norm(_sub(p, bd.position))]
        if t == "polygon":
            return ray_polygon(origin, direction, bd._wv, bd._wn)
        n := bd.shape["normal"]
        den := _dot(n, direction)
        if math.abs(den) < EPS:
            return null
        tt := (bd.shape["offset"] - _dot(n, origin)) / den
        if tt < 0.0:
            return null
        if den > 0.0:
            return null
        return [tt, n]

    # Corps dont la boîte englobante recouvre [box_min, box_max].
    func overlap_aabb(box_min, box_max, mask=null):
        out := []
        for bd in self.bodies:
            if mask != null and (bd.layer & mask) == 0:
                continue
            if bd.shape["type"] == "halfplane":
                n := bd.shape["normal"]
                lo := BIG
                for cx in [box_min[0], box_max[0]]:
                    for cy in [box_min[1], box_max[1]]:
                        lo = math.min(lo, n[0] * cx + n[1] * cy)
                if lo <= bd.shape["offset"]:
                    append(out, bd)
                continue
            bb := bd.aabb()
            if bb[0][0] <= box_max[0] and bb[1][0] >= box_min[0] and bb[0][1] <= box_max[1] and bb[1][1] >= box_min[1]:
                append(out, bd)
        return out

    # Corps réellement touchés par le cercle (centre, rayon).
    func overlap_circle(center, radius, mask=null):
        probe := Body(circle(radius), 1.0, center)
        out := []
        for bd in self.bodies:
            if mask != null and (bd.layer & mask) == 0:
                continue
            if collide(probe, bd) != null:
                append(out, bd)
        return out

    func kinetic_energy():
        e := 0.0
        for bd in self.bodies:
            if bd.kind == "dynamic":
                e = e + bd.kinetic_energy()
        return e

    func sleeping_count():
        n := 0
        for bd in self.bodies:
            if bd.sleeping:
                n += 1
        return n

func _sort_hits(hits):
    out := hits[0:len(hits)]
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j]["t"] > v["t"]:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

func _sort_by_x(rest, boxes):
    items := []
    k := 0
    while k < len(rest):
        append(items, [boxes[k][0][0], rest[k], boxes[k]])
        k += 1
    i := 1
    while i < len(items):
        v := items[i]
        j := i - 1
        while j >= 0 and items[j][0] > v[0]:
            items[j + 1] = items[j]
            j -= 1
        items[j + 1] = v
        i += 1
    return items

func _lift(boxes):
    out := []
    for b in boxes:
        append(out, [[b[0][0], b[0][1], 0.0], [b[1][0], b[1][1], 0.0]])
    return out

# =============================================================================
# Articulations 2D
# =============================================================================
# Les ancres sont données en coordonnées monde à la création et mémorisées dans le repère de chaque corps.
#   j.enabled, j.collide_connected (false par défaut), j.break_force (N, null = incassable), j.broken, j.user_data.

func _limit_target(c, h, beta, maxb, inside):
    if inside:
        return 0.0 - c / h
    return _clip(0.0 - beta / h * c, maxb)

# Résout une contrainte scalaire le long de la direction d (avec bras de levier ra, rb) ; renvoie l'impulsion cumulée.
func _lin_solve(a, b, d, ra, rb, ma, target, acc, lo, hi):
    rad := _cross(ra, d)
    rbd := _cross(rb, d)
    vrel := d[0] * (b.velocity[0] - a.velocity[0]) + d[1] * (b.velocity[1] - a.velocity[1]) + b.angular_velocity * rbd - a.angular_velocity * rad
    nacc := acc + (target - vrel) * ma
    if nacc < lo:
        nacc = lo
    if nacc > hi:
        nacc = hi
    l := nacc - acc
    a.velocity = [a.velocity[0] - d[0] * l * a.inv_mass, a.velocity[1] - d[1] * l * a.inv_mass]
    a.angular_velocity = a.angular_velocity - a.inv_inertia * rad * l
    b.velocity = [b.velocity[0] + d[0] * l * b.inv_mass, b.velocity[1] + d[1] * l * b.inv_mass]
    b.angular_velocity = b.angular_velocity + b.inv_inertia * rbd * l
    return nacc

func _eff(a, b, d, ra, rb):
    rad := _cross(ra, d)
    rbd := _cross(rb, d)
    k := a.inv_mass + b.inv_mass + a.inv_inertia * rad * rad + b.inv_inertia * rbd * rbd
    if k < EPS:
        return 0.0
    return 1.0 / k

# Résout une contrainte angulaire scalaire (vitesse relative d'angle).
func _ang_solve(a, b, ma, target, acc, lo, hi):
    nacc := acc + (target - (b.angular_velocity - a.angular_velocity)) * ma
    if nacc < lo:
        nacc = lo
    if nacc > hi:
        nacc = hi
    l := nacc - acc
    a.angular_velocity = a.angular_velocity - a.inv_inertia * l
    b.angular_velocity = b.angular_velocity + b.inv_inertia * l
    return nacc

class Joint:
    func init(kind, a, b):
        if a == null or b == null:
            raise("ValueError", "physics2d.Joint : deux corps requis (utiliser fixed_point pour un ancrage au monde)")
        if a == b:
            raise("ValueError", "physics2d.Joint : les deux corps doivent être différents")
        self.kind = kind
        self.a = a
        self.b = b
        self.enabled = true
        self.collide_connected = false
        self.break_force = null
        self.broken = false
        self.user_data = null
        self._inv = [0.0, 0.0, 0.0, 0.0]
        self._bias = [0.0, 0.0]
        self._ra = [0.0, 0.0]
        self._rb = [0.0, 0.0]
        self._pacc = [0.0, 0.0]

    func prepare(h, beta, maxb):
        return null

    func solve():
        return null

    func impulse_magnitude():
        return 0.0

    func keeps_awake():
        return false

    # Point : K 2x2 inversé, résolu en bloc.
    func _prep_point(h, beta, maxb, la, lb):
        a := self.a
        b := self.b
        ra := _rot(a._c, a._s, la)
        rb := _rot(b._c, b._s, lb)
        err := _sub(_add(b.position, rb), _add(a.position, ra))
        ma := a.inv_mass + b.inv_mass
        k11 := ma + a.inv_inertia * ra[1] * ra[1] + b.inv_inertia * rb[1] * rb[1]
        k12 := 0.0 - a.inv_inertia * ra[0] * ra[1] - b.inv_inertia * rb[0] * rb[1]
        k22 := ma + a.inv_inertia * ra[0] * ra[0] + b.inv_inertia * rb[0] * rb[0]
        det := k11 * k22 - k12 * k12
        if math.abs(det) < 0.00000000000001:
            self._inv = [0.0, 0.0, 0.0, 0.0]
        else:
            self._inv = [k22 / det, 0.0 - k12 / det, 0.0 - k12 / det, k11 / det]
        bias := _scale(err, 0.0 - beta / h)
        bl := _len(bias)
        if bl > maxb:
            bias = _scale(bias, maxb / bl)
        self._bias = bias
        self._ra = ra
        self._rb = rb
        self._pacc = [0.0, 0.0]

    func _solve_point():
        a := self.a
        b := self.b
        ra := self._ra
        rb := self._rb
        vp := [b.velocity[0] - b.angular_velocity * rb[1] - a.velocity[0] + a.angular_velocity * ra[1], b.velocity[1] + b.angular_velocity * rb[0] - a.velocity[1] - a.angular_velocity * ra[0]]
        rhs := [self._bias[0] - vp[0], self._bias[1] - vp[1]]
        k := self._inv
        lam := [k[0] * rhs[0] + k[2] * rhs[1], k[1] * rhs[0] + k[3] * rhs[1]]
        self._pacc = [self._pacc[0] + lam[0], self._pacc[1] + lam[1]]
        a.velocity = [a.velocity[0] - lam[0] * a.inv_mass, a.velocity[1] - lam[1] * a.inv_mass]
        a.angular_velocity = a.angular_velocity - a.inv_inertia * _cross(ra, lam)
        b.velocity = [b.velocity[0] + lam[0] * b.inv_mass, b.velocity[1] + lam[1] * b.inv_mass]
        b.angular_velocity = b.angular_velocity + b.inv_inertia * _cross(rb, lam)

# Pivot : les deux ancres coïncident ; rotation libre, avec limites d'angle (radians, angle relatif b - a - angle de
# référence) et moteur (vitesse cible + couple max) optionnels.
class RevoluteJoint extends Joint:
    func init(a, b, world_anchor, lower=null, upper=null):
        super.init("revolute", a, b)
        self.local_a = _rot(a._c, 0.0 - a._s, _sub(world_anchor, a.position))
        self.local_b = _rot(b._c, 0.0 - b._s, _sub(world_anchor, b.position))
        self.ref_angle = b.angle - a.angle
        self.lower = lower
        self.upper = upper
        self.motor_enabled = false
        self.motor_speed = 0.0
        self.max_motor_torque = 0.0
        self._am = 0.0
        self._lim_lo = null
        self._lim_hi = null
        self._acc_lo = 0.0
        self._acc_hi = 0.0
        self._macc = 0.0
        self._mmax = 0.0

    # Angle relatif actuel (radians).
    func angle():
        return self.b.angle - self.a.angle - self.ref_angle

    func prepare(h, beta, maxb):
        self._prep_point(h, beta, maxb, self.local_a, self.local_b)
        k := self.a.inv_inertia + self.b.inv_inertia
        self._am = 0.0
        if k > EPS:
            self._am = 1.0 / k
        self._lim_lo = null
        self._lim_hi = null
        self._acc_lo = 0.0
        self._acc_hi = 0.0
        self._macc = 0.0
        self._mmax = self.max_motor_torque * h
        th := self.angle()
        if self.lower != null:
            c := th - self.lower
            self._lim_lo = _limit_target(c, h, beta, maxb, c >= 0.0)
        if self.upper != null:
            c2 := th - self.upper
            self._lim_hi = _limit_target(c2, h, beta, maxb, c2 <= 0.0)

    func solve():
        a := self.a
        b := self.b
        if self.motor_enabled:
            self._macc = _ang_solve(a, b, self._am, self.motor_speed, self._macc, 0.0 - self._mmax, self._mmax)
        if self._lim_lo != null:
            self._acc_lo = _ang_solve(a, b, self._am, self._lim_lo, self._acc_lo, 0.0, BIG)
        if self._lim_hi != null:
            self._acc_hi = _ang_solve(a, b, self._am, self._lim_hi, self._acc_hi, 0.0 - BIG, 0.0)
        self._solve_point()

    func impulse_magnitude():
        return _len(self._pacc)

    func keeps_awake():
        return self.motor_enabled

# Soudure : position et angle relatifs figés.
class WeldJoint extends Joint:
    func init(a, b, world_anchor):
        super.init("weld", a, b)
        self.local_a = _rot(a._c, 0.0 - a._s, _sub(world_anchor, a.position))
        self.local_b = _rot(b._c, 0.0 - b._s, _sub(world_anchor, b.position))
        self.ref_angle = b.angle - a.angle
        self._am = 0.0
        self._abias = 0.0
        self._aacc = 0.0

    func prepare(h, beta, maxb):
        self._prep_point(h, beta, maxb, self.local_a, self.local_b)
        k := self.a.inv_inertia + self.b.inv_inertia
        self._am = 0.0
        if k > EPS:
            self._am = 1.0 / k
        self._abias = _clip(0.0 - beta / h * (self.b.angle - self.a.angle - self.ref_angle), maxb)
        self._aacc = 0.0

    func solve():
        self._aacc = _ang_solve(self.a, self.b, self._am, self._abias, self._aacc, 0.0 - BIG, BIG)
        self._solve_point()

    func impulse_magnitude():
        return _len(self._pacc) + math.abs(self._aacc)

# Distance : tige (min == max), corde (max seul), butée (min seul) ou ressort amorti (frequency > 0).
class DistanceJoint extends Joint:
    func init(a, b, world_anchor_a, world_anchor_b, min_length=null, max_length=null):
        super.init("distance", a, b)
        self.local_a = _rot(a._c, 0.0 - a._s, _sub(world_anchor_a, a.position))
        self.local_b = _rot(b._c, 0.0 - b._s, _sub(world_anchor_b, b.position))
        cur := _len(_sub(world_anchor_b, world_anchor_a))
        if min_length == null and max_length == null:
            self.min_length = cur
            self.max_length = cur
        else:
            self.min_length = 0.0
            self.max_length = BIG
            if min_length != null:
                self.min_length = min_length * 1.0
            if max_length != null:
                self.max_length = max_length * 1.0
        if self.min_length > self.max_length:
            raise("ValueError", "physics2d.distance_joint : min_length > max_length")
        self.rest_length = cur
        self.frequency = 0.0
        self.damping_ratio = 0.5
        self._dir = [0.0, 1.0]
        self._m = 0.0
        self._acc = 0.0
        self._acc2 = 0.0
        self._tar = 0.0
        self._tmax = null
        self._tmin = null
        self._gamma = 0.0
        self._sbias = 0.0
        self._soft = false
        self._rigid = true

    func current_length():
        a := self.a
        b := self.b
        return _len(_sub(_add(b.position, _rot(b._c, b._s, self.local_b)), _add(a.position, _rot(a._c, a._s, self.local_a))))

    func prepare(h, beta, maxb):
        a := self.a
        b := self.b
        ra := _rot(a._c, a._s, self.local_a)
        rb := _rot(b._c, b._s, self.local_b)
        d := _sub(_add(b.position, rb), _add(a.position, ra))
        ln := _len(d)
        dirn := [0.0, 1.0]
        if ln > EPS:
            dirn = _scale(d, 1.0 / ln)
        self._dir = dirn
        self._ra = ra
        self._rb = rb
        self._m = _eff(a, b, dirn, ra, rb)
        self._acc = 0.0
        self._acc2 = 0.0
        self._soft = false
        self._tmax = null
        self._tmin = null
        if self.frequency > 0.0:
            m := self._m
            om := 2.0 * math.PI * self.frequency
            dc := 2.0 * m * self.damping_ratio * om
            kk := m * om * om
            g := h * (dc + h * kk)
            if g > 0.0:
                g = 1.0 / g
            self._gamma = g
            self._sbias = (ln - self.rest_length) * h * kk * g
            self._soft = true
            return null
        if self.min_length == self.max_length:
            self._rigid = true
            self._tar = _clip(0.0 - beta / h * (ln - self.max_length), maxb)
            return null
        self._rigid = false
        if self.max_length < BIG:
            c := ln - self.max_length
            self._tmax = _limit_target(c, h, beta, maxb, c <= 0.0)
        if self.min_length > 0.0:
            c2 := ln - self.min_length
            self._tmin = _limit_target(c2, h, beta, maxb, c2 >= 0.0)

    func solve():
        a := self.a
        b := self.b
        if self._soft:
            ms := 0.0
            if self._m > 0.0:
                ms = 1.0 / (1.0 / self._m + self._gamma)
            d := self._dir
            vrel := d[0] * (b.velocity[0] - a.velocity[0]) + d[1] * (b.velocity[1] - a.velocity[1]) + b.angular_velocity * _cross(self._rb, d) - a.angular_velocity * _cross(self._ra, d)
            imp := 0.0 - ms * (vrel + self._sbias + self._gamma * self._acc)
            self._acc = self._acc + imp
            _apply_lin(a, b, d, self._ra, self._rb, imp)
            return null
        if self._rigid:
            self._acc = _lin_solve(a, b, self._dir, self._ra, self._rb, self._m, self._tar, self._acc, 0.0 - BIG, BIG)
            return null
        if self._tmax != null:
            self._acc = _lin_solve(a, b, self._dir, self._ra, self._rb, self._m, self._tmax, self._acc, 0.0 - BIG, 0.0)
        if self._tmin != null:
            self._acc2 = _lin_solve(a, b, self._dir, self._ra, self._rb, self._m, self._tmin, self._acc2, 0.0, BIG)

    func impulse_magnitude():
        return math.abs(self._acc) + math.abs(self._acc2)

func _apply_lin(a, b, d, ra, rb, l):
    a.velocity = [a.velocity[0] - d[0] * l * a.inv_mass, a.velocity[1] - d[1] * l * a.inv_mass]
    a.angular_velocity = a.angular_velocity - a.inv_inertia * _cross(ra, d) * l
    b.velocity = [b.velocity[0] + d[0] * l * b.inv_mass, b.velocity[1] + d[1] * l * b.inv_mass]
    b.angular_velocity = b.angular_velocity + b.inv_inertia * _cross(rb, d) * l

# --- fabriques ---

func revolute_joint(a, b, world_anchor, lower=null, upper=null):
    return RevoluteJoint(a, b, world_anchor, lower, upper)

func weld_joint(a, b, world_anchor=null):
    anchor := world_anchor
    if anchor == null:
        anchor = _scale(_add(a.position, b.position), 0.5)
    return WeldJoint(a, b, anchor)

func distance_joint(a, b, world_anchor_a=null, world_anchor_b=null, min_length=null, max_length=null):
    pa := world_anchor_a
    pb := world_anchor_b
    if pa == null:
        pa = a.position
    if pb == null:
        pb = b.position
    return DistanceJoint(a, b, pa, pb, min_length, max_length)

# Ressort amorti : frequency en Hz, damping_ratio dans [0, 1].
func spring_joint(a, b, world_anchor_a, world_anchor_b, frequency, damping_ratio=0.5, rest_length=null):
    j := DistanceJoint(a, b, world_anchor_a, world_anchor_b)
    j.frequency = frequency * 1.0
    j.damping_ratio = damping_ratio * 1.0
    if rest_length != null:
        j.rest_length = rest_length * 1.0
    return j
