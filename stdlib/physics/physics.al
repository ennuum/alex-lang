# ALEX STANDARD LIBRARY — physics
#
# Physique 3D pour les jeux : formes (sphère, boîte orientée, capsule, plan), détection de collisions avec
# manifolds de contacts, requêtes (raycasts, recouvrements), corps rigides avec un solveur d'impulsions séquentielles
# (friction de Coulomb, restitution, amortissement, endormissement), filtrage par couches, déclencheurs et
# événements de contact, détection continue (balayage anti-traversée), articulations (rotule, charnière, distance /
# ressort, fixe, glissière) et phase large par hachage spatial. ALEX pur. La version 2D est dans `physics.physics2d`,
# le hachage spatial dans `physics.spatial`.
#
#   use physics
#   w := physics.World()                                           # gravité (0, -9.81, 0) par défaut
#   w.add(physics.static_body(physics.plane([0, 1, 0], 0)))        # sol
#   ball := w.add(physics.Body(physics.sphere(0.5), 1.0, [0, 5, 0]))
#   ball.restitution = 0.6
#   crate := w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 2.0, [2, 3, 0]))
#   for i in range(600):
#       w.step(1.0 / 60.0)
#   hit := w.raycast([0, 10, 0], [0, -1, 0], 100)                  # {"body", "t", "point", "normal"} ou null
#   print(ball.position, hit["body"] == ball)
#
# CONVENTIONS (voir math3d) : repère main droite, Y vers le haut, unités SI (mètres, kilogrammes, secondes),
#   quaternions [x, y, z, w]. Une forme est centrée sur le centre de masse du corps. Un contact est
#   {"normal": n, "points": [[point, profondeur], ...]} où n est unitaire et va du corps A vers le corps B ;
#   profondeur > 0 = interpénétration.
# FORMES : sphere(rayon), box(demi-dimensions), capsule(rayon, demi-hauteur du segment) d'axe local Y,
#   plane(normale, décalage) = demi-espace n·p = décalage (statique uniquement ; la matière est du côté -n).
# TYPES DE CORPS : mass > 0 = dynamique ; mass == 0 = statique (immobile) ; kinematic_body = déplacé par sa vitesse,
#   masse infinie (plateformes mobiles).
# DÉTECTION CONTINUE : tout corps dynamique qui parcourt, en un sous-pas, plus que son rayon de cœur (sphère/capsule :
#   rayon ; boîte : plus petite demi-dimension) est balayé le long de sa trajectoire et arrêté au premier contact, au lieu
#   de traverser un mur mince. Réglages : World.ccd (global, true par défaut), Body.continuous (par corps, true).
#   Limites : les autres corps sont considérés immobiles pendant le sous-pas, et la rotation n'est pas balayée.
# ARTICULATIONS : ball_joint, hinge_joint (limites d'angle, moteur), distance_joint (tige, corde, ressort), fixed_joint,
#   slider_joint (limites, moteur) ; w.add_joint(j). Elles sont résolues avec les contacts, appartiennent à un îlot
#   d'endormissement commun et peuvent casser (j.break_force). Par défaut les corps reliés ne se heurtent pas.
# PHASE LARGE : balayage sur X pour les petits mondes, hachage spatial (physics.spatial) au-delà de 48 corps
#   (World.broadphase = "auto" | "sweep" | "hash").
# LIMITES : pas de mailles triangulaires dynamiques (raycast_mesh sert aux requêtes), effet gyroscopique ignoré,
#   pas de mouvement relatif des corps lors du balayage continu. La stabilité d'empilements élevés demande
#   solver_iterations plus grand.
#
# Erreurs : ValueError (forme ou paramètre invalide), TypeError.

use math
use math3d
use algorithm
use physics.spatial as spatial
from core use len, to_int
from collections use append, pop, contains_key, keys

const VERSION := "1.1.0"
const EPS := 0.000000001
const BIG := 1000000000000.0
const _UID := [0]

# =============================================================================
# Petits outils vectoriels (listes de 3 flottants), internes
# =============================================================================

func _add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

func _sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

func _scale(a, s):
    return [a[0] * s, a[1] * s, a[2] * s]

func _madd(a, b, s):
    return [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s]

func _dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

func _cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

func _neg(a):
    return [0.0 - a[0], 0.0 - a[1], 0.0 - a[2]]

func _len(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])

func _norm(a):
    l := math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])
    if l < EPS:
        return [0.0, 0.0, 0.0]
    return [a[0] / l, a[1] / l, a[2] / l]

func _mulv(m, v):
    return [m[0] * v[0] + m[3] * v[1] + m[6] * v[2], m[1] * v[0] + m[4] * v[1] + m[7] * v[2], m[2] * v[0] + m[5] * v[1] + m[8] * v[2]]

func _sgn(x):
    if x < 0.0:
        return -1.0
    return 1.0

func _clampf(x, lo, hi):
    if x < lo:
        return lo
    if x > hi:
        return hi
    return x

# =============================================================================
# Formes
# =============================================================================

func sphere(radius):
    if radius <= 0:
        raise("ValueError", "physics.sphere : rayon > 0 requis")
    return {"type": "sphere", "radius": radius * 1.0}

# Boîte de demi-dimensions half = [hx, hy, hz].
func box(half):
    if half[0] <= 0 or half[1] <= 0 or half[2] <= 0:
        raise("ValueError", "physics.box : demi-dimensions > 0 requises")
    return {"type": "box", "half": [half[0] * 1.0, half[1] * 1.0, half[2] * 1.0]}

# Boîte à partir de ses dimensions complètes.
func box_from_size(width, height, depth):
    return box([width * 0.5, height * 0.5, depth * 0.5])

# Capsule d'axe local Y : segment de longueur 2 * half_height, épaissi de `radius`.
func capsule(radius, half_height):
    if radius <= 0 or half_height < 0:
        raise("ValueError", "physics.capsule : rayon > 0 et demi-hauteur >= 0 requis")
    return {"type": "capsule", "radius": radius * 1.0, "half_height": half_height * 1.0}

# Demi-espace {p : n·p <= offset}. La normale est normalisée.
func plane(normal, offset=0.0):
    n := _norm(normal)
    if _len(n) < 0.5:
        raise("ValueError", "physics.plane : normale nulle")
    return {"type": "plane", "normal": n, "offset": offset * 1.0}

func _rank(shape):
    t := shape["type"]
    if t == "sphere":
        return 0
    if t == "capsule":
        return 1
    if t == "box":
        return 2
    return 3

# Volume d'une forme (0 pour un plan).
func shape_volume(shape):
    t := shape["type"]
    if t == "sphere":
        return 4.0 / 3.0 * math.PI * shape["radius"] * shape["radius"] * shape["radius"]
    if t == "box":
        h := shape["half"]
        return 8.0 * h[0] * h[1] * h[2]
    if t == "capsule":
        r := shape["radius"]
        return math.PI * r * r * 2.0 * shape["half_height"] + 4.0 / 3.0 * math.PI * r * r * r
    return 0.0

# Tenseur d'inertie diagonal [Ix, Iy, Iz] (repère local) pour une masse m.
func shape_inertia(shape, mass):
    t := shape["type"]
    if t == "sphere":
        i := 0.4 * mass * shape["radius"] * shape["radius"]
        return [i, i, i]
    if t == "box":
        h := shape["half"]
        w := 2.0 * h[0]
        hh := 2.0 * h[1]
        d := 2.0 * h[2]
        return [mass / 12.0 * (hh * hh + d * d), mass / 12.0 * (w * w + d * d), mass / 12.0 * (w * w + hh * hh)]
    if t == "capsule":
        r := shape["radius"]
        hl := 2.0 * shape["half_height"]
        vc := math.PI * r * r * hl
        vh := 4.0 / 3.0 * math.PI * r * r * r
        mc := mass * vc / (vc + vh)
        mh := mass - mc
        iy := mc * r * r * 0.5 + mh * 0.4 * r * r
        ix := mc * (hl * hl / 12.0 + r * r / 4.0) + mh * (0.4 * r * r + hl * hl * 0.25 + 3.0 * hl * r / 8.0)
        return [ix, iy, ix]
    return [BIG, BIG, BIG]

# =============================================================================
# Géométrie : points les plus proches, rayons
# =============================================================================

# Point du segment [a, b] le plus proche de p.
func closest_point_on_segment(p, a, b):
    ab := _sub(b, a)
    l2 := _dot(ab, ab)
    if l2 < EPS:
        return [a[0], a[1], a[2]]
    t := _clampf(_dot(_sub(p, a), ab) / l2, 0.0, 1.0)
    return _madd(a, ab, t)

# Points les plus proches de deux segments [p1, q1] et [p2, q2] : [c1, c2, s, t] (s, t dans [0, 1]).
func closest_points_segments(p1, q1, p2, q2):
    d1 := _sub(q1, p1)
    d2 := _sub(q2, p2)
    r := _sub(p1, p2)
    a := _dot(d1, d1)
    e := _dot(d2, d2)
    f := _dot(d2, r)
    s := 0.0
    t := 0.0
    if a < EPS and e < EPS:
        return [[p1[0], p1[1], p1[2]], [p2[0], p2[1], p2[2]], 0.0, 0.0]
    if a < EPS:
        t = _clampf(f / e, 0.0, 1.0)
    else:
        c := _dot(d1, r)
        if e < EPS:
            s = _clampf(0.0 - c / a, 0.0, 1.0)
        else:
            b := _dot(d1, d2)
            denom := a * e - b * b
            if denom > EPS * a * e:
                s = _clampf((b * f - c * e) / denom, 0.0, 1.0)
            t = (b * s + f) / e
            if t < 0.0:
                t = 0.0
                s = _clampf(0.0 - c / a, 0.0, 1.0)
            elif t > 1.0:
                t = 1.0
                s = _clampf((b - c) / a, 0.0, 1.0)
    return [_madd(p1, d1, s), _madd(p2, d2, t), s, t]

# Rayon / sphère : t >= 0 de la première entrée, ou null. Origine dans la sphère -> t = 0.
func ray_sphere(origin, direction, center, radius):
    m := _sub(origin, center)
    a := _dot(direction, direction)
    b := _dot(m, direction)
    c := _dot(m, m) - radius * radius
    if c <= 0.0:
        return 0.0
    if a < EPS:
        return null
    disc := b * b - a * c
    if disc < 0.0:
        return null
    t := (0.0 - b - math.sqrt(disc)) / a
    if t < 0.0:
        return null
    return t

# Rayon / plan (face avant seulement) : t ou null. Du côté matière (n·o < offset) -> t = 0.
func ray_plane(origin, direction, normal, offset):
    dist := _dot(normal, origin) - offset
    if dist <= 0.0:
        return 0.0
    dn := _dot(normal, direction)
    if dn >= 0.0:
        return null
    return dist / (0.0 - dn)

# Rayon / boîte orientée (centre, axes monde unitaires [ax, ay, az], demi-dimensions) : [t, normale] ou null.
func ray_box(origin, direction, center, axes, half):
    o := _sub(origin, center)
    lo := [_dot(o, axes[0]), _dot(o, axes[1]), _dot(o, axes[2])]
    ld := [_dot(direction, axes[0]), _dot(direction, axes[1]), _dot(direction, axes[2])]
    tmin := 0.0
    tmax := BIG
    nidx := -1
    nsign := 1.0
    i := 0
    while i < 3:
        if math.abs(ld[i]) < 0.000000000000001:
            if lo[i] < 0.0 - half[i] or lo[i] > half[i]:
                return null
        else:
            inv := 1.0 / ld[i]
            t1 := (0.0 - half[i] - lo[i]) * inv
            t2 := (half[i] - lo[i]) * inv
            s := -1.0
            if t1 > t2:
                tt := t1
                t1 = t2
                t2 = tt
                s = 1.0
            if t1 > tmin:
                tmin = t1
                nidx = i
                nsign = s
            if t2 < tmax:
                tmax = t2
            if tmin > tmax:
                return null
        i += 1
    if nidx < 0:
        return [0.0, _neg(_norm(direction))]
    return [tmin, _scale(axes[nidx], nsign)]

# Rayon / capsule (extrémités du segment p0, p1 et rayon) : [t, normale] ou null.
func ray_capsule(origin, direction, p0, p1, radius):
    best := null
    axis := _sub(p1, p0)
    seg_len := _len(axis)
    candidates := []
    t0 := ray_sphere(origin, direction, p0, radius)
    if t0 != null:
        append(candidates, t0)
    t1 := ray_sphere(origin, direction, p1, radius)
    if t1 != null:
        append(candidates, t1)
    if seg_len > EPS:
        a := _scale(axis, 1.0 / seg_len)
        m := _sub(origin, p0)
        dd := _sub(direction, _scale(a, _dot(direction, a)))
        mm := _sub(m, _scale(a, _dot(m, a)))
        qa := _dot(dd, dd)
        qb := _dot(mm, dd)
        qc := _dot(mm, mm) - radius * radius
        if qa > EPS:
            disc := qb * qb - qa * qc
            if disc >= 0.0:
                t := (0.0 - qb - math.sqrt(disc)) / qa
                if t >= 0.0:
                    s := _dot(_add(m, _scale(direction, t)), a)
                    if s >= 0.0 and s <= seg_len:
                        append(candidates, t)
        elif qc <= 0.0:
            # rayon parallèle à l'axe et dans le cylindre : seul l'embout compte (déjà couvert par les sphères)
            pass
    for t in candidates:
        if best == null or t < best:
            best = t
    if best == null:
        return null
    hit := _madd(origin, direction, best)
    c := closest_point_on_segment(hit, p0, p1)
    n := _norm(_sub(hit, c))
    if best == 0.0:
        n = _neg(_norm(direction))
    return [best, n]

# Rayon / triangle (Möller-Trumbore) : t ou null. cull_back = true ignore les triangles vus de dos
# (face avant = sens trigonométrique vu de la caméra).
func ray_triangle(origin, direction, a, b, c, cull_back=false):
    e1 := _sub(b, a)
    e2 := _sub(c, a)
    p := _cross(direction, e2)
    det := _dot(e1, p)
    if cull_back:
        if det < EPS:
            return null
    else:
        if math.abs(det) < EPS:
            return null
    inv := 1.0 / det
    tv := _sub(origin, a)
    u := _dot(tv, p) * inv
    if u < 0.0 or u > 1.0:
        return null
    q := _cross(tv, e1)
    v := _dot(direction, q) * inv
    if v < 0.0 or u + v > 1.0:
        return null
    t := _dot(e2, q) * inv
    if t < 0.0:
        return null
    return t

# Rayon / maillage (objet avec `positions` : liste de Vec3 et `indices` : liste plate, comme mesh.Mesh).
# matrix = Mat4 du maillage dans le monde (null = identité). Renvoie le plus proche
# {"t", "point", "normal", "triangle"} ou null. t est exprimé dans les unités de `direction`.
func ray_mesh(origin, direction, positions, indices, matrix=null, max_t=null, cull_back=false):
    o := origin
    d := direction
    inv := null
    if matrix != null:
        inv = math3d.mat4_inverse_affine(matrix)
        o = math3d.mat4_transform_point(inv, origin)
        d = math3d.mat4_transform_direction(inv, direction)
    best := null
    best_i := -1
    i := 0
    n := len(indices)
    while i + 2 < n:
        t := ray_triangle(o, d, positions[indices[i]], positions[indices[i + 1]], positions[indices[i + 2]], cull_back)
        if t != null and (max_t == null or t <= max_t):
            if best == null or t < best:
                best = t
                best_i = i
        i += 3
    if best == null:
        return null
    ta := positions[indices[best_i]]
    tb := positions[indices[best_i + 1]]
    tc := positions[indices[best_i + 2]]
    ln := _norm(_cross(_sub(tb, ta), _sub(tc, ta)))
    if _dot(ln, d) > 0.0:
        ln = _neg(ln)
    wn := ln
    if matrix != null:
        wn = _norm(_mulv(math3d.mat3_normal_matrix(matrix), ln))
    return {"t": best, "point": _madd(origin, direction, best), "normal": wn, "triangle": best_i // 3}

# =============================================================================
# Corps rigide
# =============================================================================

class Body:
    func init(shape, mass=1.0, position=null, rotation=null):
        self.shape = shape
        self.position = [0.0, 0.0, 0.0]
        if position != null:
            self.position = [position[0] * 1.0, position[1] * 1.0, position[2] * 1.0]
        self.rotation = [0.0, 0.0, 0.0, 1.0]
        if rotation != null:
            self.rotation = math3d.quat_normalize(rotation)
        self.velocity = [0.0, 0.0, 0.0]
        self.angular_velocity = [0.0, 0.0, 0.0]
        self.force = [0.0, 0.0, 0.0]
        self.torque = [0.0, 0.0, 0.0]
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
        self.kind = "dynamic"
        self.mass = mass * 1.0
        self.inv_mass = 0.0
        self.inv_inertia = [0.0, 0.0, 0.0]
        self.id = 0
        _UID[0] = _UID[0] + 1
        self.uid = _UID[0]
        self.continuous = true
        self.joint_count = 0
        self._axes = null
        self._iinv = null
        self.set_mass(mass)
        self.refresh()

    # (Re)définit la masse et le tenseur d'inertie d'après la forme. 0 = statique.
    func set_mass(mass):
        if mass < 0:
            raise("ValueError", "physics.Body.set_mass : masse négative")
        if self.shape["type"] == "plane" and mass != 0:
            raise("ValueError", "physics.Body : un plan est forcément statique (masse 0)")
        self.mass = mass * 1.0
        if mass == 0:
            self.inv_mass = 0.0
            self.inv_inertia = [0.0, 0.0, 0.0]
            if self.kind == "dynamic":
                self.kind = "static"
        else:
            self.inv_mass = 1.0 / mass
            i := shape_inertia(self.shape, mass)
            self.inv_inertia = [1.0 / i[0], 1.0 / i[1], 1.0 / i[2]]
            if self.kind == "static":
                self.kind = "dynamic"
        self.refresh()

    # Rayon de cœur : distance au-delà de laquelle un déplacement en un sous-pas risque de traverser un obstacle mince.
    func core_radius():
        t := self.shape["type"]
        if t == "sphere" or t == "capsule":
            return self.shape["radius"]
        if t == "box":
            h := self.shape["half"]
            return math.min(h[0], math.min(h[1], h[2]))
        return BIG

    func is_static():
        return self.kind == "static"

    func is_dynamic():
        return self.kind == "dynamic"

    # Recalcule les données dérivées (axes, inertie inverse monde) : à appeler après avoir modifié rotation à la main.
    func refresh():
        m4 := math3d.mat4_from_quat(self.rotation)
        self._axes = [[m4[0], m4[1], m4[2]], [m4[4], m4[5], m4[6]], [m4[8], m4[9], m4[10]]]
        if self.kind != "dynamic" or self.lock_rotation:
            self._iinv = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        else:
            ii := self.inv_inertia
            ax := self._axes
            r := []
            c := 0
            while c < 3:
                row := 0
                while row < 3:
                    s := 0.0
                    k := 0
                    while k < 3:
                        s = s + ax[k][row] * ii[k] * ax[k][c]
                        k += 1
                    append(r, s)
                    row += 1
                c += 1
            self._iinv = r

    func set_position(p):
        self.position = [p[0] * 1.0, p[1] * 1.0, p[2] * 1.0]
        self.wake()

    func set_rotation(q):
        self.rotation = math3d.quat_normalize(q)
        self.refresh()
        self.wake()

    func wake():
        self.sleeping = false
        self.sleep_timer = 0.0

    # Axes locaux exprimés dans le monde (colonnes de la rotation).
    func axes():
        return self._axes

    # Force (N) appliquée au centre de masse pour le prochain pas ; effacée après le pas.
    func apply_force(f):
        self.force = _add(self.force, f)
        self.wake()

    func apply_force_at(f, point):
        self.force = _add(self.force, f)
        self.torque = _add(self.torque, _cross(_sub(point, self.position), f))
        self.wake()

    func apply_torque(t):
        self.torque = _add(self.torque, t)
        self.wake()

    # Impulsion (N·s) : change immédiatement la vitesse de j / m.
    func apply_impulse(j):
        if self.kind != "dynamic":
            return null
        self.velocity = _madd(self.velocity, j, self.inv_mass)
        self.wake()

    func apply_impulse_at(j, point):
        if self.kind != "dynamic":
            return null
        self.velocity = _madd(self.velocity, j, self.inv_mass)
        self.angular_velocity = _add(self.angular_velocity, _mulv(self._iinv, _cross(_sub(point, self.position), j)))
        self.wake()

    # Vitesse du point matériel situé (en coordonnées monde) à `point`.
    func velocity_at(point):
        return _add(self.velocity, _cross(self.angular_velocity, _sub(point, self.position)))

    func kinetic_energy():
        e := 0.5 * self.mass * _dot(self.velocity, self.velocity)
        if self.kind == "dynamic":
            ii := self.inv_inertia
            w := self.angular_velocity
            ax := self._axes
            k := 0
            while k < 3:
                wl := _dot(w, ax[k])
                if ii[k] > 0.0:
                    e = e + 0.5 * wl * wl / ii[k]
                k += 1
        return e

    func momentum():
        return _scale(self.velocity, self.mass)

    # Boîte englobante monde [min, max] (infinie pour un plan).
    func aabb():
        t := self.shape["type"]
        p := self.position
        if t == "sphere":
            r := self.shape["radius"]
            return [[p[0] - r, p[1] - r, p[2] - r], [p[0] + r, p[1] + r, p[2] + r]]
        if t == "box":
            h := self.shape["half"]
            ax := self._axes
            e := [0.0, 0.0, 0.0]
            i := 0
            while i < 3:
                e[i] = math.abs(ax[0][i]) * h[0] + math.abs(ax[1][i]) * h[1] + math.abs(ax[2][i]) * h[2]
                i += 1
            return [[p[0] - e[0], p[1] - e[1], p[2] - e[2]], [p[0] + e[0], p[1] + e[1], p[2] + e[2]]]
        if t == "capsule":
            seg := self.capsule_segment()
            r := self.shape["radius"]
            return [[math.min(seg[0][0], seg[1][0]) - r, math.min(seg[0][1], seg[1][1]) - r, math.min(seg[0][2], seg[1][2]) - r], [math.max(seg[0][0], seg[1][0]) + r, math.max(seg[0][1], seg[1][1]) + r, math.max(seg[0][2], seg[1][2]) + r]]
        return [[0.0 - BIG, 0.0 - BIG, 0.0 - BIG], [BIG, BIG, BIG]]

    # Extrémités monde du segment d'une capsule : [p0 (bas), p1 (haut)].
    func capsule_segment():
        a := self._axes[1]
        h := self.shape["half_height"]
        return [_madd(self.position, a, 0.0 - h), _madd(self.position, a, h)]

    # Sommets monde d'une boîte (8 points).
    func box_vertices():
        h := self.shape["half"]
        ax := self._axes
        out := []
        for sx in [-1.0, 1.0]:
            for sy in [-1.0, 1.0]:
                for sz in [-1.0, 1.0]:
                    v := self.position
                    v = _madd(v, ax[0], sx * h[0])
                    v = _madd(v, ax[1], sy * h[1])
                    v = _madd(v, ax[2], sz * h[2])
                    append(out, v)
        return out

func static_body(shape, position=null, rotation=null):
    return Body(shape, 0.0, position, rotation)

# Corps cinématique : déplacé uniquement par sa vitesse (velocity, angular_velocity), repousse les corps dynamiques.
func kinematic_body(shape, position=null, rotation=null):
    b := Body(shape, 0.0, position, rotation)
    b.kind = "kinematic"
    b.refresh()
    return b

# =============================================================================
# Détection de collisions (phase étroite)
# =============================================================================

# Contact entre deux corps : {"normal", "points"} (normale de A vers B) ou null. Ne tient pas compte des couches.
func collide(a, b):
    if _rank(a.shape) > _rank(b.shape):
        c := collide(b, a)
        if c == null:
            return null
        return {"normal": _neg(c["normal"]), "points": c["points"]}
    ta := a.shape["type"]
    tb := b.shape["type"]
    if ta == "sphere":
        if tb == "sphere":
            return _sphere_sphere(a.position, a.shape["radius"], b.position, b.shape["radius"])
        if tb == "capsule":
            seg := b.capsule_segment()
            q := closest_point_on_segment(a.position, seg[0], seg[1])
            return _sphere_sphere(a.position, a.shape["radius"], q, b.shape["radius"])
        if tb == "box":
            return _sphere_box(a.position, a.shape["radius"], b)
        return _sphere_plane(a.position, a.shape["radius"], b.shape)
    if ta == "capsule":
        sa := a.capsule_segment()
        if tb == "capsule":
            sb := b.capsule_segment()
            cp := closest_points_segments(sa[0], sa[1], sb[0], sb[1])
            return _sphere_sphere(cp[0], a.shape["radius"], cp[1], b.shape["radius"])
        if tb == "box":
            return _capsule_box(sa, a.shape["radius"], b)
        # capsule / plan : les deux extrémités comme sphères
        pts := []
        for q in sa:
            c := _sphere_plane(q, a.shape["radius"], b.shape)
            if c != null:
                for p in c["points"]:
                    append(pts, p)
        if len(pts) == 0:
            return null
        return {"normal": _neg(b.shape["normal"]), "points": pts}
    if ta == "box":
        if tb == "box":
            return _box_box(a, b)
        return _box_plane(a, b.shape)
    return null

func _sphere_sphere(ca, ra, cb, rb):
    d := _sub(cb, ca)
    dist := _len(d)
    rs := ra + rb
    if dist >= rs:
        return null
    n := [0.0, 1.0, 0.0]
    if dist > EPS:
        n = _scale(d, 1.0 / dist)
    depth := rs - dist
    p := _madd(ca, n, ra - depth * 0.5)
    return {"normal": n, "points": [[p, depth]]}

func _sphere_plane(c, r, pl):
    dist := _dot(pl["normal"], c) - pl["offset"]
    if dist >= r:
        return null
    depth := r - dist
    p := _madd(c, pl["normal"], 0.0 - dist + depth * 0.5)
    return {"normal": _neg(pl["normal"]), "points": [[p, depth]]}

# Sphère (centre c, rayon r) contre une boîte orientée (corps b). Normale : sphère -> boîte.
func _sphere_box(c, r, b):
    h := b.shape["half"]
    ax := b.axes()
    rel := _sub(c, b.position)
    local := [_dot(rel, ax[0]), _dot(rel, ax[1]), _dot(rel, ax[2])]
    q := [_clampf(local[0], 0.0 - h[0], h[0]), _clampf(local[1], 0.0 - h[1], h[1]), _clampf(local[2], 0.0 - h[2], h[2])]
    d := _sub(local, q)
    dist2 := _dot(d, d)
    if dist2 > r * r:
        return null
    if dist2 > EPS * EPS:
        dist := math.sqrt(dist2)
        nl := _scale(d, 1.0 / dist)
        # normale monde boîte -> sphère
        nw := _add(_add(_scale(ax[0], nl[0]), _scale(ax[1], nl[1])), _scale(ax[2], nl[2]))
        depth := r - dist
        pw := _add(b.position, _add(_add(_scale(ax[0], q[0]), _scale(ax[1], q[1])), _scale(ax[2], q[2])))
        return {"normal": _neg(nw), "points": [[pw, depth]]}
    # centre à l'intérieur : sortir par la face la plus proche
    best := 0
    bestd := h[0] - math.abs(local[0])
    i := 1
    while i < 3:
        di := h[i] - math.abs(local[i])
        if di < bestd:
            bestd = di
            best = i
        i += 1
    s := _sgn(local[best])
    nw := _scale(ax[best], s)
    depth := r + bestd
    pw := _madd(c, nw, 0.0 - bestd)
    return {"normal": _neg(nw), "points": [[pw, depth]]}

# Segment de capsule (sa) de rayon r contre une boîte (corps b). Normale : capsule -> boîte.
func _capsule_box(sa, r, b):
    h := b.shape["half"]
    ax := b.axes()
    s := closest_point_on_segment(b.position, sa[0], sa[1])
    q := b.position
    i := 0
    while i < 5:
        q = _closest_on_box(s, b)
        s = closest_point_on_segment(q, sa[0], sa[1])
        i += 1
    return _sphere_box(s, r, b)

func _closest_on_box(p, b):
    h := b.shape["half"]
    ax := b.axes()
    rel := _sub(p, b.position)
    q := b.position
    k := 0
    while k < 3:
        q = _madd(q, ax[k], _clampf(_dot(rel, ax[k]), 0.0 - h[k], h[k]))
        k += 1
    return q

func _box_plane(a, pl):
    pts := []
    n := pl["normal"]
    for v in a.box_vertices():
        dist := _dot(n, v) - pl["offset"]
        if dist < 0.0:
            append(pts, [_madd(v, n, 0.0 - dist * 0.5), 0.0 - dist])
    if len(pts) == 0:
        return null
    return {"normal": _neg(n), "points": pts}

# Rayon de projection d'une boîte (axes, demi-dimensions) sur la direction l.
func _proj_radius(axes, half, l):
    return half[0] * math.abs(_dot(axes[0], l)) + half[1] * math.abs(_dot(axes[1], l)) + half[2] * math.abs(_dot(axes[2], l))

# Boîte / boîte par axes séparateurs (15 axes) + découpage de face pour obtenir jusqu'à 4 points de contact.
func _box_box(a, b):
    ha := a.shape["half"]
    hb := b.shape["half"]
    axa := a.axes()
    axb := b.axes()
    d := _sub(b.position, a.position)
    best_face_pen := BIG
    best_face := -1
    best_face_l := null
    best_edge_pen := BIG
    best_edge := -1
    best_edge_l := null
    idx := 0
    while idx < 15:
        l := null
        if idx < 3:
            l = axa[idx]
        elif idx < 6:
            l = axb[idx - 3]
        else:
            e := idx - 6
            l = _cross(axa[e // 3], axb[e % 3])
            ll := _len(l)
            if ll < 0.0001:
                idx += 1
                continue
            l = _scale(l, 1.0 / ll)
        pen := _proj_radius(axa, ha, l) + _proj_radius(axb, hb, l) - math.abs(_dot(d, l))
        if pen < 0.0:
            return null
        if idx < 6:
            if pen < best_face_pen:
                best_face_pen = pen
                best_face = idx
                best_face_l = l
        else:
            if pen < best_edge_pen:
                best_edge_pen = pen
                best_edge = idx
                best_edge_l = l
        idx += 1
    use_edge := best_edge >= 0 and best_edge_pen < best_face_pen * 0.95 - 0.01
    l := best_face_l
    pen := best_face_pen
    which := best_face
    if use_edge:
        l = best_edge_l
        pen = best_edge_pen
        which = best_edge
    if _dot(d, l) < 0.0:
        l = _neg(l)
    if use_edge:
        e := which - 6
        ia := e // 3
        ib := e % 3
        pa := a.position
        k := 0
        while k < 3:
            if k != ia:
                pa = _madd(pa, axa[k], _sgn(_dot(axa[k], l)) * ha[k])
            k += 1
        pb := b.position
        k = 0
        while k < 3:
            if k != ib:
                pb = _madd(pb, axb[k], _sgn(_dot(axb[k], _neg(l))) * hb[k])
            k += 1
        ea := axa[ia]
        eb := axb[ib]
        r := _sub(pa, pb)
        bb := _dot(ea, eb)
        c := _dot(ea, r)
        f := _dot(eb, r)
        denom := 1.0 - bb * bb
        s := 0.0
        if denom > 0.000001:
            s = (bb * f - c) / denom
        t := bb * s + f
        qa := _madd(pa, ea, s)
        qb := _madd(pb, eb, t)
        mid := _scale(_add(qa, qb), 0.5)
        return {"normal": l, "points": [[mid, pen]]}
    pts := []
    if which < 3:
        pts = _face_contacts(a.position, axa, ha, which, l, b.position, axb, hb)
    else:
        pts = _face_contacts(b.position, axb, hb, which - 3, _neg(l), a.position, axa, ha)
    if len(pts) == 0:
        return {"normal": l, "points": [[_scale(_add(a.position, b.position), 0.5), pen]]}
    return {"normal": l, "points": _reduce_contacts(pts, l)}

# Points de contact entre la face de référence (axe i de la boîte de référence, normale sortante n_out) et la face
# incidente de l'autre boîte la plus opposée, découpée par les côtés de la face de référence.
func _face_contacts(rpos, raxes, rhalf, i, n_out, ipos, iaxes, ihalf):
    k := 0
    best := -1.0
    sg := 1.0
    j := 0
    while j < 3:
        dj := _dot(iaxes[j], n_out)
        if math.abs(dj) > best:
            best = math.abs(dj)
            k = j
            sg = _sgn(dj)
        j += 1
    n_inc := _scale(iaxes[k], 0.0 - sg)
    ic := _madd(ipos, n_inc, ihalf[k])
    ka := (k + 1) % 3
    kb := (k + 2) % 3
    ua := _scale(iaxes[ka], ihalf[ka])
    ub := _scale(iaxes[kb], ihalf[kb])
    poly := [_add(_add(ic, ua), ub), _add(_sub(ic, ua), ub), _sub(_sub(ic, ua), ub), _sub(_add(ic, ua), ub)]
    fc := _madd(rpos, n_out, rhalf[i])
    p := (i + 1) % 3
    q := (i + 2) % 3
    for side in [p, q]:
        u := raxes[side]
        poly = _clip_poly(poly, u, _dot(fc, u) + rhalf[side])
        poly = _clip_poly(poly, _neg(u), 0.0 - _dot(fc, u) + rhalf[side])
        if len(poly) == 0:
            return []
    out := []
    for v in poly:
        depth := 0.0 - _dot(_sub(v, fc), n_out)
        if depth >= 0.0 - 0.0001:
            if depth < 0.0:
                depth = 0.0
            append(out, [_madd(v, n_out, depth * 0.5), depth])
    return out

# Sutherland-Hodgman : garde la partie du polygone où n·p <= d.
func _clip_poly(poly, n, d):
    out := []
    cnt := len(poly)
    if cnt == 0:
        return out
    i := 0
    while i < cnt:
        a := poly[i]
        b := poly[(i + 1) % cnt]
        da := _dot(n, a) - d
        db := _dot(n, b) - d
        if da <= 0.0:
            append(out, a)
        if (da < 0.0 and db > 0.0) or (da > 0.0 and db < 0.0):
            t := da / (da - db)
            append(out, _madd(a, _sub(b, a), t))
        i += 1
    return out

# Réduit à 4 points bien répartis (le plus profond, le plus éloigné de lui, puis ceux qui maximisent l'aire).
func _reduce_contacts(pts, normal):
    if len(pts) <= 4:
        return pts
    first := 0
    i := 1
    while i < len(pts):
        if pts[i][1] > pts[first][1]:
            first = i
        i += 1
    chosen := [first]
    far := -1
    fd := -1.0
    i = 0
    while i < len(pts):
        dd := _dot(_sub(pts[i][0], pts[first][0]), _sub(pts[i][0], pts[first][0]))
        if dd > fd:
            fd = dd
            far = i
        i += 1
    append(chosen, far)
    while len(chosen) < 4:
        bi := -1
        bv := -1.0
        i = 0
        while i < len(pts):
            used := false
            for c in chosen:
                if c == i:
                    used = true
            if not used:
                m := BIG
                for c in chosen:
                    dd := _len(_sub(pts[i][0], pts[c][0]))
                    if dd < m:
                        m = dd
                if m > bv:
                    bv = m
                    bi = i
            i += 1
        append(chosen, bi)
    out := []
    for c in chosen:
        append(out, pts[c])
    return out

# =============================================================================
# Monde physique
# =============================================================================

class World:
    func init():
        self.gravity = [0.0, -9.81, 0.0]
        self.bodies = []
        self.solver_iterations = 12
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
        self.contacts = []
        self.time = 0.0
        self._pairs = {}
        self._on_begin = []
        self._on_end = []
        self._next_id = 1
        self.ccd = true
        self.broadphase = "auto"
        self.hash_cell = null
        self.hash_threshold = 48
        self.joints = []
        self.joint_baumgarte = 0.2
        self.joint_max_bias = 10.0
        self._joint_pairs = {}
        self._active_joints = []

    func add(body):
        body.id = self._next_id
        self._next_id += 1
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
        self.contacts = []
        self._pairs = {}
        self.joints = []
        self._joint_pairs = {}
        self._active_joints = []

    # Ajoute une articulation (les deux corps doivent déjà être dans le monde, ou être des points fixes).
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

    # fn(corps_a, corps_b, contact_ou_null) au début / à la fin d'un contact (déclencheurs inclus).
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

    # Paires candidates : balayage sur X ou hachage spatial selon World.broadphase ("auto" : hachage au-delà de
    # hash_threshold corps) ; les plans sont testés contre tous.
    func _candidate_pairs():
        mode := self.broadphase
        if mode == "auto":
            mode = "sweep"
            if len(self.bodies) > self.hash_threshold:
                mode = "hash"
        if mode == "hash":
            return self._hash_pairs()
        return self._sweep_pairs()

    func _hash_pairs():
        planes := []
        byid := {}
        boxes := []
        for bd in self.bodies:
            if bd.shape["type"] == "plane":
                append(planes, bd)
            else:
                append(boxes, bd.aabb())
        cell := self.hash_cell
        if cell == null:
            cell = spatial.suggest_cell_size(boxes)
        grid := spatial.SpatialHash(cell)
        k := 0
        for bd in self.bodies:
            if bd.shape["type"] != "plane":
                grid.insert(bd.id, boxes[k][0], boxes[k][1])
                byid[bd.id] = bd
                k += 1
        pairs := []
        for pr in grid.pairs():
            a := byid[pr[0]]
            b := byid[pr[1]]
            if self._can_collide(a, b) and not (a.sleeping and b.sleeping):
                append(pairs, [a, b])
        for pl in planes:
            for bd in self.bodies:
                if bd.shape["type"] != "plane" and self._can_collide(pl, bd) and not (pl.sleeping and bd.sleeping):
                    append(pairs, [pl, bd])
        return pairs

    func _sweep_pairs():
        items := []
        planes := []
        for bd in self.bodies:
            if bd.shape["type"] == "plane":
                append(planes, bd)
            else:
                bb := bd.aabb()
                append(items, [bb[0][0], bd, bb])
        order := algorithm.sorted(items, (it) => it[0])
        pairs := []
        i := 0
        while i < len(order):
            ai := order[i]
            j := i + 1
            while j < len(order) and order[j][0] <= ai[2][1][0]:
                bj := order[j]
                if self._can_collide(ai[1], bj[1]) and not (ai[1].sleeping and bj[1].sleeping):
                    if ai[2][0][1] <= bj[2][1][1] and ai[2][1][1] >= bj[2][0][1] and ai[2][0][2] <= bj[2][1][2] and ai[2][1][2] >= bj[2][0][2]:
                        append(pairs, [ai[1], bj[1]])
                j += 1
            i += 1
        for pl in planes:
            for it in order:
                if self._can_collide(pl, it[1]) and not (pl.sleeping and it[1].sleeping):
                    append(pairs, [pl, it[1]])
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

    # Avance la simulation de dt secondes (divisé en `substeps` sous-pas).
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
        # événements début / fin
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
                gs := bd.gravity_scale
                im := bd.inv_mass
                f := bd.force
                damp := 1.0 / (1.0 + bd.linear_damping * h)
                vx := (v[0] + (g[0] * gs + f[0] * im) * h) * damp
                vy := (v[1] + (g[1] * gs + f[1] * im) * h) * damp
                vz := (v[2] + (g[2] * gs + f[2] * im) * h) * damp
                sp2 := vx * vx + vy * vy + vz * vz
                if sp2 > ms2:
                    k := self.max_speed / math.sqrt(sp2)
                    vx = vx * k
                    vy = vy * k
                    vz = vz * k
                bd.velocity = [vx, vy, vz]
                if not bd.lock_rotation:
                    w := _add(bd.angular_velocity, _scale(_mulv(bd._iinv, bd.torque), h))
                    bd.angular_velocity = _scale(w, 1.0 / (1.0 + bd.angular_damping * h))
        self._prepare_joints(h)
        found := self._find_contacts()
        # réveil : un corps endormi touché par un corps actif et récemment en mouvement se réveille
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
        self._check_joints(h)
        use_ccd := self.ccd
        for bd in self.bodies:
            if bd.kind == "static" or bd.sleeping:
                continue
            moved := false
            if use_ccd and bd.continuous and bd.kind == "dynamic":
                moved = self._ccd_move(bd, h)
            if not moved:
                bd.position = _madd(bd.position, bd.velocity, h)
            w := bd.angular_velocity
            if _dot(w, w) > 0.0:
                dq := math3d.quat_mul([w[0] * h * 0.5, w[1] * h * 0.5, w[2] * h * 0.5, 0.0], bd.rotation)
                bd.rotation = math3d.quat_normalize([bd.rotation[0] + dq[0], bd.rotation[1] + dq[1], bd.rotation[2] + dq[2], bd.rotation[3] + dq[3]])
                bd.refresh()
            bd.force = [0.0, 0.0, 0.0]
            bd.torque = [0.0, 0.0, 0.0]
            if bd.kind == "dynamic":
                self._update_sleep(bd, h)
        if len(self.joints) > 0:
            self._sleep_islands()

    # Réveille les îlots d'articulations dont un membre est actif, retient les articulations dont tous les corps
    # dynamiques dorment, et prépare les autres (ancres monde, erreurs de position).
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
            if ad and not bd and a.sleeping and b.kind == "kinematic" and _dot(b.velocity, b.velocity) + _dot(b.angular_velocity, b.angular_velocity) > 0.0:
                a.wake()
            if bd and not ad and b.sleeping and a.kind == "kinematic" and _dot(a.velocity, a.velocity) + _dot(a.angular_velocity, a.angular_velocity) > 0.0:
                b.wake()
            if (not ad or a.sleeping) and (not bd or b.sleeping):
                continue
            j.prepare(h, self.joint_baumgarte, self.joint_max_bias)
            append(active, j)
        self._active_joints = active

    func _check_joints(h):
        for j in self._active_joints:
            if j.break_force != null and j.impulse_magnitude() / h > j.break_force:
                j.broken = true
                j.enabled = false
                j.a.wake()
                j.b.wake()

    # Les corps reliés par des articulations dorment ensemble : seulement si tout l'îlot est au repos depuis assez
    # longtemps. Composantes connexes du graphe des articulations entre corps dynamiques.
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
                        m.velocity = [0.0, 0.0, 0.0]
                        m.angular_velocity = [0.0, 0.0, 0.0]

    # Déplacement continu d'un corps rapide : balaie la trajectoire du sous-pas et s'arrête juste après le premier
    # contact (pénétration infime) pour que le solveur le traite au sous-pas suivant. Renvoie true si le corps a été
    # déplacé ici (la position n'est alors plus à intégrer).
    func _ccd_move(bd, h):
        v := bd.velocity
        mv := [v[0] * h, v[1] * h, v[2] * h]
        dist := _len(mv)
        core := bd.core_radius()
        if dist <= core or bd.is_trigger:
            return false
        start := bd.position
        bb0 := bd.aabb()
        bd.position = _add(start, mv)
        bb1 := bd.aabb()
        bd.position = start
        lo := [math.min(bb0[0][0], bb1[0][0]), math.min(bb0[0][1], bb1[0][1]), math.min(bb0[0][2], bb1[0][2])]
        hi := [math.max(bb0[1][0], bb1[1][0]), math.max(bb0[1][1], bb1[1][1]), math.max(bb0[1][2], bb1[1][2])]
        others := []
        for ob in self.bodies:
            if ob == bd or ob.is_trigger or not self._can_collide(bd, ob):
                continue
            if ob.shape["type"] != "plane":
                bo := ob.aabb()
                if bo[0][0] > hi[0] or bo[1][0] < lo[0] or bo[0][1] > hi[1] or bo[1][1] < lo[1] or bo[0][2] > hi[2] or bo[1][2] < lo[2]:
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
            bd.position = _madd(start, mv, s * 1.0 / steps)
            if _hits_any(bd, others):
                first = s
                break
            s += 1
        if first == 0:
            bd.position = start
            return false
        t_lo := (first - 1) * 1.0 / steps
        t_hi := first * 1.0 / steps
        it := 0
        while it < 8:
            mid := (t_lo + t_hi) * 0.5
            bd.position = _madd(start, mv, mid)
            if _hits_any(bd, others):
                t_hi = mid
            else:
                t_lo = mid
            it += 1
        bd.position = _madd(start, mv, t_hi)
        return true

    func _update_sleep(bd, h):
        if not (self.allow_sleep and bd.allow_sleep):
            return null
        lin := _dot(bd.velocity, bd.velocity)
        ang := _dot(bd.angular_velocity, bd.angular_velocity)
        if lin < self.sleep_linear * self.sleep_linear and ang < self.sleep_angular * self.sleep_angular:
            bd.sleep_timer = bd.sleep_timer + h
            if bd.sleep_timer >= self.sleep_time and bd.joint_count == 0:
                bd.sleeping = true
                bd.velocity = [0.0, 0.0, 0.0]
                bd.angular_velocity = [0.0, 0.0, 0.0]
        else:
            bd.sleep_timer = 0.0

    # Impulsions séquentielles : friction puis normale, avec cumul borné par contact. Calcul scalaire : pour chaque
    # direction d, les termes r×d et I⁻¹(r×d) sont précalculés une fois par contact, puis réutilisés à chaque itération.
    func _solve(contacts, h):
        rows := []
        for c in contacts:
            a := c["a"]
            b := c["b"]
            n := c["normal"]
            basis := math3d.vec3_orthonormal_basis(n)
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
                append(rows, [a, b, mu, bias, 0.0, 0.0, 0.0, _dir_row(a, b, ra, rb, basis[0]), _dir_row(a, b, ra, rb, basis[1]), _dir_row(a, b, ra, rb, n)])
        joints := self._active_joints
        it := 0
        while it < self.solver_iterations:
            for j in joints:
                j.solve()
            for r in rows:
                a := r[0]
                b := r[1]
                va := a.velocity
                wa := a.angular_velocity
                vb := b.velocity
                wb := b.angular_velocity
                ima := a.inv_mass
                imb := b.inv_mass
                nrm := r[9]
                # friction (bornée par mu * impulsion normale accumulée), deux directions tangentes
                maxf := r[2] * r[4]
                k := 7
                while k < 9:
                    dr := r[k]
                    d := dr[0]
                    vrel := d[0] * (vb[0] - va[0]) + d[1] * (vb[1] - va[1]) + d[2] * (vb[2] - va[2]) + wb[0] * dr[1][0] + wb[1] * dr[1][1] + wb[2] * dr[1][2] - wa[0] * dr[2][0] - wa[1] * dr[2][1] - wa[2] * dr[2][2]
                    acc := r[k - 2]
                    nacc := acc - vrel * dr[5]
                    if nacc > maxf:
                        nacc = maxf
                    if nacc < 0.0 - maxf:
                        nacc = 0.0 - maxf
                    l := nacc - acc
                    r[k - 2] = nacc
                    _push(a, b, dr, l)
                    k += 1
                # normale
                d := nrm[0]
                vrel := d[0] * (vb[0] - va[0]) + d[1] * (vb[1] - va[1]) + d[2] * (vb[2] - va[2]) + wb[0] * nrm[1][0] + wb[1] * nrm[1][1] + wb[2] * nrm[1][2] - wa[0] * nrm[2][0] - wa[1] * nrm[2][1] - wa[2] * nrm[2][2]
                acc := r[4]
                nacc := acc + nrm[5] * (r[3] - vrel)
                if nacc < 0.0:
                    nacc = 0.0
                r[4] = nacc
                _push(a, b, nrm, nacc - acc)
            it += 1

    # --- requêtes ---
    # Premier corps touché par le rayon : {"body", "t", "point", "normal"} ou null. direction n'a pas à être unitaire (t en
    # unités de direction). mask : couches testées (null = toutes). ignore : corps à ignorer.
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
                    best = {"body": bd, "t": h[0], "point": _madd(origin, direction, h[0]), "normal": h[1]}
        return best

    # Tous les corps touchés, du plus proche au plus loin.
    func raycast_all(origin, direction, max_distance=null, mask=null):
        out := []
        for bd in self.bodies:
            if mask != null and (bd.layer & mask) == 0:
                continue
            h := self._ray_body(bd, origin, direction)
            if h != null and (max_distance == null or h[0] <= max_distance):
                append(out, {"body": bd, "t": h[0], "point": _madd(origin, direction, h[0]), "normal": h[1]})
        return algorithm.sorted(out, (x) => x["t"])

    func _ray_body(bd, origin, direction):
        t := bd.shape["type"]
        if t == "sphere":
            h := ray_sphere(origin, direction, bd.position, bd.shape["radius"])
            if h == null:
                return null
            if h == 0.0:
                return [0.0, _neg(_norm(direction))]
            p := _madd(origin, direction, h)
            return [h, _norm(_sub(p, bd.position))]
        if t == "box":
            return ray_box(origin, direction, bd.position, bd.axes(), bd.shape["half"])
        if t == "capsule":
            sg := bd.capsule_segment()
            return ray_capsule(origin, direction, sg[0], sg[1], bd.shape["radius"])
        h := ray_plane(origin, direction, bd.shape["normal"], bd.shape["offset"])
        if h == null:
            return null
        return [h, bd.shape["normal"]]

    # Corps dont la boîte englobante touche la boîte [min, max].
    func overlap_aabb(box_min, box_max, mask=null):
        out := []
        for bd in self.bodies:
            if bd.shape["type"] == "plane":
                continue
            if mask != null and (bd.layer & mask) == 0:
                continue
            bb := bd.aabb()
            if bb[0][0] <= box_max[0] and bb[1][0] >= box_min[0] and bb[0][1] <= box_max[1] and bb[1][1] >= box_min[1] and bb[0][2] <= box_max[2] and bb[1][2] >= box_min[2]:
                append(out, bd)
        return out

    # Corps réellement en contact avec une sphère de test.
    func overlap_sphere(center, radius, mask=null):
        probe := Body(sphere(radius), 0.0, center)
        out := []
        for bd in self.bodies:
            if mask != null and (bd.layer & mask) == 0:
                continue
            if collide(probe, bd) != null:
                append(out, bd)
        return out

    # Énergie cinétique totale des corps dynamiques.
    func kinetic_energy():
        e := 0.0
        for bd in self.bodies:
            if bd.kind == "dynamic":
                e = e + bd.kinetic_energy()
        return e

    # Nombre de corps dynamiques endormis.
    func sleeping_count():
        n := 0
        for bd in self.bodies:
            if bd.sleeping:
                n += 1
        return n

func _pair_key(a, b):
    if a.uid < b.uid:
        return a.uid * 2147483648 + b.uid
    return b.uid * 2147483648 + a.uid

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

# Ligne de contrainte pour une direction d : [d, rb×d... voir ci-dessous]
#   [0] d ; [1] rb×d ; [2] ra×d ; [3] I⁻¹a (ra×d) ; [4] I⁻¹b (rb×d) ; [5] masse effective.
func _dir_row(a, b, ra, rb, d):
    raxd := _cross(ra, d)
    rbxd := _cross(rb, d)
    ia := _mulv(a._iinv, raxd)
    ib := _mulv(b._iinv, rbxd)
    k := a.inv_mass + b.inv_mass + _dot(ia, raxd) + _dot(ib, rbxd)
    m := 0.0
    if k > EPS:
        m = 1.0 / k
    return [d, rbxd, raxd, ia, ib, m]

# Applique l'impulsion l * d : +l au corps b, -l au corps a (déplacements nuls pour les corps non dynamiques,
# dont l'inverse de masse et d'inertie sont nuls).
func _push(a, b, dr, l):
    if l == 0.0:
        return null
    d := dr[0]
    va := a.velocity
    wa := a.angular_velocity
    vb := b.velocity
    wb := b.angular_velocity
    f := l * a.inv_mass
    va[0] = va[0] - d[0] * f
    va[1] = va[1] - d[1] * f
    va[2] = va[2] - d[2] * f
    ia := dr[3]
    wa[0] = wa[0] - ia[0] * l
    wa[1] = wa[1] - ia[1] * l
    wa[2] = wa[2] - ia[2] * l
    f = l * b.inv_mass
    vb[0] = vb[0] + d[0] * f
    vb[1] = vb[1] + d[1] * f
    vb[2] = vb[2] + d[2] * f
    ib := dr[4]
    wb[0] = wb[0] + ib[0] * l
    wb[1] = wb[1] + ib[1] * l
    wb[2] = wb[2] + ib[2] * l

func _eff_mass(a, b, ra, rb, dirn):
    raxn := _cross(ra, dirn)
    rbxn := _cross(rb, dirn)
    k := a.inv_mass + b.inv_mass + _dot(_cross(_mulv(a._iinv, raxn), ra), dirn) + _dot(_cross(_mulv(b._iinv, rbxn), rb), dirn)
    if k < EPS:
        return 0.0
    return 1.0 / k

# Applique l'impulsion p au corps b (+p) et au corps a (-p) aux bras de levier ra, rb.
func _apply(a, b, ra, rb, p):
    if a.kind == "dynamic":
        a.velocity = _madd(a.velocity, p, 0.0 - a.inv_mass)
        a.angular_velocity = _sub(a.angular_velocity, _mulv(a._iinv, _cross(ra, p)))
    if b.kind == "dynamic":
        b.velocity = _madd(b.velocity, p, b.inv_mass)
        b.angular_velocity = _add(b.angular_velocity, _mulv(b._iinv, _cross(rb, p)))

# =============================================================================
# Articulations
# =============================================================================
# Chaque articulation relie deux corps (a, b) ; un corps statique (ou fixed_point) sert d'ancrage au monde. Elles sont
# résolues par impulsions séquentielles avec les contacts. Les ancres sont données en coordonnées MONDE à la création
# et mémorisées dans le repère de chaque corps.
#   j.enabled, j.collide_connected (false : les deux corps ne se heurtent pas), j.break_force (N, null = incassable),
#   j.broken, j.user_data.

func _to_world(body, l):
    ax := body._axes
    return [ax[0][0] * l[0] + ax[1][0] * l[1] + ax[2][0] * l[2], ax[0][1] * l[0] + ax[1][1] * l[1] + ax[2][1] * l[2], ax[0][2] * l[0] + ax[1][2] * l[1] + ax[2][2] * l[2]]

func _to_local(body, w):
    ax := body._axes
    return [_dot(w, ax[0]), _dot(w, ax[1]), _dot(w, ax[2])]

# Vitesse relative (b par rapport à a) le long d'une ligne de contrainte.
func _vrel(a, b, dr):
    d := dr[0]
    va := a.velocity
    wa := a.angular_velocity
    vb := b.velocity
    wb := b.angular_velocity
    return d[0] * (vb[0] - va[0]) + d[1] * (vb[1] - va[1]) + d[2] * (vb[2] - va[2]) + wb[0] * dr[1][0] + wb[1] * dr[1][1] + wb[2] * dr[1][2] - wa[0] * dr[2][0] - wa[1] * dr[2][1] - wa[2] * dr[2][2]

# Une itération sur une ligne : amène la vitesse relative à `target`, impulsion cumulée bornée à [lo, hi].
func _row_solve(a, b, dr, target, acc, lo, hi):
    nacc := acc + (target - _vrel(a, b, dr)) * dr[5]
    if nacc < lo:
        nacc = lo
    if nacc > hi:
        nacc = hi
    _push(a, b, dr, nacc - acc)
    return nacc

# Ligne purement angulaire autour de d (axe monde unitaire).
func _ang_row(a, b, d):
    ia := _mulv(a._iinv, d)
    ib := _mulv(b._iinv, d)
    k := _dot(ia, d) + _dot(ib, d)
    m := 0.0
    if k > EPS:
        m = 1.0 / k
    return [[0.0, 0.0, 0.0], d, d, ia, ib, m]

# Inverse d'une matrice 3x3 symétrique stockée en 9 flottants ; la matrice nulle si elle est singulière.
func _inv3(m):
    a := m[0]
    b := m[3]
    c := m[6]
    d := m[1]
    e := m[4]
    f := m[7]
    g := m[2]
    h := m[5]
    i := m[8]
    c00 := e * i - f * h
    c01 := f * g - d * i
    c02 := d * h - e * g
    det := a * c00 + b * c01 + c * c02
    if math.abs(det) < 0.00000000000001:
        return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
    r := 1.0 / det
    return [c00 * r, c01 * r, c02 * r, (c * h - b * i) * r, (a * i - c * g) * r, (b * g - a * h) * r, (b * f - c * e) * r, (c * d - a * f) * r, (a * e - b * d) * r]

# Cible de vitesse d'une limite : tant que la limite n'est pas franchie (inside), on autorise exactement la vitesse
# qui l'atteindrait à la fin du pas (limite « spéculative », sans dépassement ni rebond) ; une fois franchie, on
# ramène la position par stabilisation de Baumgarte (écart c, de même signe que le dépassement).
func _limit_target(c, h, beta, maxb, inside):
    if inside:
        return 0.0 - c / h
    return _clip(0.0 - beta / h * c, maxb)

func _clip(x, m):
    if x > m:
        return m
    if x < 0.0 - m:
        return 0.0 - m
    return x

func _angle_wrap(x):
    while x > math.PI:
        x = x - 2.0 * math.PI
    while x < 0.0 - math.PI:
        x = x + 2.0 * math.PI
    return x

class Joint:
    func init(kind, a, b):
        if a == null or b == null:
            raise("ValueError", "physics.Joint : deux corps requis (utiliser fixed_point pour un ancrage au monde)")
        if a == b:
            raise("ValueError", "physics.Joint : les deux corps doivent être différents")
        self.kind = kind
        self.a = a
        self.b = b
        self.enabled = true
        self.collide_connected = false
        self.break_force = null
        self.broken = false
        self.user_data = null
        self._pinv = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        self._pbias = [0.0, 0.0, 0.0]
        self._pra = [0.0, 0.0, 0.0]
        self._prb = [0.0, 0.0, 0.0]
        self._pacc = [0.0, 0.0, 0.0]
        self._linv = [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]
        self._lbias = [0.0, 0.0, 0.0]
        self._lacc = [0.0, 0.0, 0.0]

    func prepare(h, beta, maxb):
        return null

    func solve():
        return null

    func impulse_magnitude():
        return 0.0

    # Une articulation motorisée garde ses corps éveillés (le moteur peut être réglé à tout moment).
    func keeps_awake():
        return false

    # Contrainte de point résolue en bloc : la matrice K 3x3 (masses et inerties aux ancres) est inversée une fois par
    # sous-pas, l'impulsion exacte est alors trouvée en une itération (pas de convergence lente quand les inerties
    # sont très différentes).
    func _prep_point(h, beta, maxb, local_a, local_b):
        a := self.a
        b := self.b
        ra := _to_world(a, local_a)
        rb := _to_world(b, local_b)
        err := _sub(_add(b.position, rb), _add(a.position, ra))
        m := a.inv_mass + b.inv_mass
        c0 := _add(_scale([1.0, 0.0, 0.0], m), _add(_cross(_mulv(a._iinv, _cross(ra, [1.0, 0.0, 0.0])), ra), _cross(_mulv(b._iinv, _cross(rb, [1.0, 0.0, 0.0])), rb)))
        c1 := _add(_scale([0.0, 1.0, 0.0], m), _add(_cross(_mulv(a._iinv, _cross(ra, [0.0, 1.0, 0.0])), ra), _cross(_mulv(b._iinv, _cross(rb, [0.0, 1.0, 0.0])), rb)))
        c2 := _add(_scale([0.0, 0.0, 1.0], m), _add(_cross(_mulv(a._iinv, _cross(ra, [0.0, 0.0, 1.0])), ra), _cross(_mulv(b._iinv, _cross(rb, [0.0, 0.0, 1.0])), rb)))
        self._pinv = _inv3([c0[0], c0[1], c0[2], c1[0], c1[1], c1[2], c2[0], c2[1], c2[2]])
        bias := _scale(err, 0.0 - beta / h)
        bl := _len(bias)
        if bl > maxb:
            bias = _scale(bias, maxb / bl)
        self._pbias = bias
        self._pra = ra
        self._prb = rb
        self._pacc = [0.0, 0.0, 0.0]

    func _solve_point():
        a := self.a
        b := self.b
        ra := self._pra
        rb := self._prb
        vp := _sub(_add(b.velocity, _cross(b.angular_velocity, rb)), _add(a.velocity, _cross(a.angular_velocity, ra)))
        lam := _mulv(self._pinv, _sub(self._pbias, vp))
        self._pacc = _add(self._pacc, lam)
        _apply(a, b, ra, rb, lam)

    # Verrouillage des 3 rotations relatives par rapport à la rotation relative de référence q0 (bloc 3x3).
    func _prep_lock(h, beta, maxb, q0):
        a := self.a
        b := self.b
        qt := math3d.quat_mul(a.rotation, q0)
        qd := math3d.quat_mul(b.rotation, math3d.quat_conjugate(qt))
        sg := 1.0
        if qd[3] < 0.0:
            sg = -1.0
        c := [2.0 * sg * qd[0], 2.0 * sg * qd[1], 2.0 * sg * qd[2]]
        k := []
        i := 0
        while i < 9:
            append(k, a._iinv[i] + b._iinv[i])
            i += 1
        self._linv = _inv3(k)
        bias := _scale(c, 0.0 - beta / h)
        bl := _len(bias)
        if bl > maxb:
            bias = _scale(bias, maxb / bl)
        self._lbias = bias
        self._lacc = [0.0, 0.0, 0.0]

    func _solve_lock():
        a := self.a
        b := self.b
        lam := _mulv(self._linv, _sub(self._lbias, _sub(b.angular_velocity, a.angular_velocity)))
        self._lacc = _add(self._lacc, lam)
        a.angular_velocity = _sub(a.angular_velocity, _mulv(a._iinv, lam))
        b.angular_velocity = _add(b.angular_velocity, _mulv(b._iinv, lam))

# Rotule : les deux ancres coïncident, les rotations sont libres.
class BallJoint extends Joint:
    func init(a, b, world_anchor):
        super.init("ball", a, b)
        self.local_a = _to_local(a, _sub(world_anchor, a.position))
        self.local_b = _to_local(b, _sub(world_anchor, b.position))

    func prepare(h, beta, maxb):
        self._prep_point(h, beta, maxb, self.local_a, self.local_b)

    func solve():
        self._solve_point()

    func impulse_magnitude():
        return _len(self._pacc)

    # Écart actuel entre les ancres (m) : mesure de l'étirement.
    func error():
        return _len(_sub(_add(self.b.position, _to_world(self.b, self.local_b)), _add(self.a.position, _to_world(self.a, self.local_a))))

# Soudure : position et orientation relatives figées.
class FixedJoint extends Joint:
    func init(a, b, world_anchor):
        super.init("fixed", a, b)
        self.local_a = _to_local(a, _sub(world_anchor, a.position))
        self.local_b = _to_local(b, _sub(world_anchor, b.position))
        self.q0 = math3d.quat_mul(math3d.quat_conjugate(a.rotation), b.rotation)

    func prepare(h, beta, maxb):
        self._prep_point(h, beta, maxb, self.local_a, self.local_b)
        self._prep_lock(h, beta, maxb, self.q0)

    func solve():
        self._solve_lock()
        self._solve_point()

    func impulse_magnitude():
        return _len(self._pacc) + _len(self._lacc)

# Charnière : une seule rotation libre, autour de `axis`. Limites d'angle (radians, lower <= 0 <= upper en général,
# angle 0 = orientation relative à la création, mesuré dans ]-π, π]) et moteur (vitesse cible + couple max).
class HingeJoint extends Joint:
    func init(a, b, world_anchor, world_axis, lower=null, upper=null):
        super.init("hinge", a, b)
        ax := _norm(world_axis)
        if _len(ax) < 0.5:
            raise("ValueError", "physics.hinge_joint : axe nul")
        self.local_a = _to_local(a, _sub(world_anchor, a.position))
        self.local_b = _to_local(b, _sub(world_anchor, b.position))
        self.axis_a = _to_local(a, ax)
        self.axis_b = _to_local(b, ax)
        basis := math3d.vec3_orthonormal_basis(ax)
        self.ref_a = _to_local(a, basis[0])
        self.ref_b = _to_local(b, basis[0])
        self.lower = lower
        self.upper = upper
        self.motor_enabled = false
        self.motor_speed = 0.0
        self.max_motor_torque = 0.0
        self._ka = [0.0, 1.0, 0.0]
        self._angle = 0.0
        self._arow = []
        self._atar = [0.0, 0.0]
        self._aacc = [0.0, 0.0]
        self._macc = 0.0
        self._limacc = 0.0
        self._mrow = null
        self._limrow = null
        self._lim_lo = null
        self._lim_hi = null
        self._acc_lo = 0.0
        self._acc_hi = 0.0
        self._mmax = 0.0

    # Angle actuel de la charnière (radians).
    func angle():
        ka := _to_world(self.a, self.axis_a)
        ra := _to_world(self.a, self.ref_a)
        rb := _to_world(self.b, self.ref_b)
        return math.atan2(_dot(_cross(ra, rb), ka), _dot(ra, rb))

    func prepare(h, beta, maxb):
        a := self.a
        b := self.b
        self._prep_point(h, beta, maxb, self.local_a, self.local_b)
        ka := _to_world(a, self.axis_a)
        kb := _to_world(b, self.axis_b)
        self._ka = ka
        e := _cross(ka, kb)
        basis := math3d.vec3_orthonormal_basis(ka)
        self._arow = [_ang_row(a, b, basis[0]), _ang_row(a, b, basis[1])]
        self._atar = [_clip(0.0 - beta / h * _dot(e, basis[0]), maxb), _clip(0.0 - beta / h * _dot(e, basis[1]), maxb)]
        self._aacc = [0.0, 0.0]
        main := _ang_row(a, b, ka)
        self._mrow = null
        if self.motor_enabled:
            self._mrow = main
            self._mmax = self.max_motor_torque * h
            self._macc = 0.0
        self._limrow = main
        self._lim_lo = null
        self._lim_hi = null
        self._acc_lo = 0.0
        self._acc_hi = 0.0
        if self.lower != null or self.upper != null:
            th := self.angle()
            self._angle = th
            if self.lower != null:
                c := th - self.lower
                self._lim_lo = _limit_target(c, h, beta, maxb, c >= 0.0)
            if self.upper != null:
                c2 := th - self.upper
                self._lim_hi = _limit_target(c2, h, beta, maxb, c2 <= 0.0)

    func solve():
        a := self.a
        b := self.b
        if self._mrow != null:
            self._macc = _row_solve(a, b, self._mrow, self.motor_speed, self._macc, 0.0 - self._mmax, self._mmax)
        if self._lim_lo != null:
            self._acc_lo = _row_solve(a, b, self._limrow, self._lim_lo, self._acc_lo, 0.0, BIG)
        if self._lim_hi != null:
            self._acc_hi = _row_solve(a, b, self._limrow, self._lim_hi, self._acc_hi, 0.0 - BIG, 0.0)
        self._aacc[0] = _row_solve(a, b, self._arow[0], self._atar[0], self._aacc[0], 0.0 - BIG, BIG)
        self._aacc[1] = _row_solve(a, b, self._arow[1], self._atar[1], self._aacc[1], 0.0 - BIG, BIG)
        self._solve_point()

    func impulse_magnitude():
        return _len(self._pacc) + math.abs(self._aacc[0]) + math.abs(self._aacc[1])

    func keeps_awake():
        return self.motor_enabled

# Distance : tige rigide (min == max), corde (max seul), butée (min seul) ou ressort amorti (frequency > 0, autour de
# rest_length ; damping_ratio : 0 = sans frottement, 1 = amortissement critique).
class DistanceJoint extends Joint:
    func init(a, b, world_anchor_a, world_anchor_b, min_length=null, max_length=null):
        super.init("distance", a, b)
        self.local_a = _to_local(a, _sub(world_anchor_a, a.position))
        self.local_b = _to_local(b, _sub(world_anchor_b, b.position))
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
            raise("ValueError", "physics.distance_joint : min_length > max_length")
        self.rest_length = cur
        self.frequency = 0.0
        self.damping_ratio = 0.5
        self._row = null
        self._tar = 0.0
        self._lo = 0.0
        self._hi = 0.0
        self._acc = 0.0
        self._gamma = 0.0
        self._bias = 0.0
        self._soft = false
        self._active = false
        self._rigid = true
        self._acc2 = 0.0
        self._tmax = null
        self._tmin = null

    func current_length():
        return _len(_sub(_add(self.b.position, _to_world(self.b, self.local_b)), _add(self.a.position, _to_world(self.a, self.local_a))))

    func prepare(h, beta, maxb):
        a := self.a
        b := self.b
        ra := _to_world(a, self.local_a)
        rb := _to_world(b, self.local_b)
        d := _sub(_add(b.position, rb), _add(a.position, ra))
        ln := _len(d)
        dirn := [0.0, 1.0, 0.0]
        if ln > EPS:
            dirn = _scale(d, 1.0 / ln)
        self._row = _dir_row(a, b, ra, rb, dirn)
        self._acc = 0.0
        self._active = true
        self._soft = false
        if self.frequency > 0.0:
            m := self._row[5]
            om := 2.0 * math.PI * self.frequency
            dc := 2.0 * m * self.damping_ratio * om
            kk := m * om * om
            g := h * (dc + h * kk)
            if g > 0.0:
                g = 1.0 / g
            self._gamma = g
            self._bias = (ln - self.rest_length) * h * kk * g
            self._soft = true
            return null
        if self.min_length == self.max_length:
            self._tar = _clip(0.0 - beta / h * (ln - self.max_length), maxb)
            self._lo = 0.0 - BIG
            self._hi = BIG
            self._rigid = true
            return null
        self._rigid = false
        self._acc2 = 0.0
        self._tmax = null
        self._tmin = null
        if self.max_length < BIG:
            c := ln - self.max_length
            self._tmax = _limit_target(c, h, beta, maxb, c <= 0.0)
        if self.min_length > 0.0:
            c2 := ln - self.min_length
            self._tmin = _limit_target(c2, h, beta, maxb, c2 >= 0.0)

    func solve():
        if not self._active:
            return null
        if self._soft:
            row := self._row
            k := row[5]
            ms := 0.0
            if k > 0.0:
                ms = 1.0 / (1.0 / k + self._gamma)
            imp := 0.0 - ms * (_vrel(self.a, self.b, row) + self._bias + self._gamma * self._acc)
            self._acc = self._acc + imp
            _push(self.a, self.b, row, imp)
            return null
        if self._rigid:
            self._acc = _row_solve(self.a, self.b, self._row, self._tar, self._acc, self._lo, self._hi)
            return null
        if self._tmax != null:
            self._acc = _row_solve(self.a, self.b, self._row, self._tmax, self._acc, 0.0 - BIG, 0.0)
        if self._tmin != null:
            self._acc2 = _row_solve(self.a, self.b, self._row, self._tmin, self._acc2, 0.0, BIG)

    func impulse_magnitude():
        return math.abs(self._acc) + math.abs(self._acc2)

# Glissière : translation libre le long de `axis`, rotations et décalage latéral bloqués ; limites de course
# (mètres, mesurées depuis l'ancre de création) et moteur linéaire.
class SliderJoint extends Joint:
    func init(a, b, world_anchor, world_axis, lower=null, upper=null):
        super.init("slider", a, b)
        ax := _norm(world_axis)
        if _len(ax) < 0.5:
            raise("ValueError", "physics.slider_joint : axe nul")
        self.local_a = _to_local(a, _sub(world_anchor, a.position))
        self.local_b = _to_local(b, _sub(world_anchor, b.position))
        self.axis_a = _to_local(a, ax)
        self.q0 = math3d.quat_mul(math3d.quat_conjugate(a.rotation), b.rotation)
        self.lower = lower
        self.upper = upper
        self.motor_enabled = false
        self.motor_speed = 0.0
        self.max_motor_force = 0.0
        self._lat = []
        self._lattar = [0.0, 0.0]
        self._latacc = [0.0, 0.0]
        self._mrow = null
        self._macc = 0.0
        self._mmax = 0.0
        self._limrow = null
        self._lim_lo = null
        self._lim_hi = null
        self._acc_lo = 0.0
        self._acc_hi = 0.0

    # Position actuelle le long de l'axe (m).
    func position():
        ka := _to_world(self.a, self.axis_a)
        err := _sub(_add(self.b.position, _to_world(self.b, self.local_b)), _add(self.a.position, _to_world(self.a, self.local_a)))
        return _dot(ka, err)

    func prepare(h, beta, maxb):
        a := self.a
        b := self.b
        self._prep_lock(h, beta, maxb, self.q0)
        ra := _to_world(a, self.local_a)
        rb := _to_world(b, self.local_b)
        err := _sub(_add(b.position, rb), _add(a.position, ra))
        ka := _to_world(a, self.axis_a)
        basis := math3d.vec3_orthonormal_basis(ka)
        self._lat = [_dir_row(a, b, ra, rb, basis[0]), _dir_row(a, b, ra, rb, basis[1])]
        self._lattar = [_clip(0.0 - beta / h * _dot(err, basis[0]), maxb), _clip(0.0 - beta / h * _dot(err, basis[1]), maxb)]
        self._latacc = [0.0, 0.0]
        main := _dir_row(a, b, ra, rb, ka)
        self._mrow = null
        if self.motor_enabled:
            self._mrow = main
            self._mmax = self.max_motor_force * h
            self._macc = 0.0
        self._limrow = main
        self._lim_lo = null
        self._lim_hi = null
        self._acc_lo = 0.0
        self._acc_hi = 0.0
        sp := _dot(ka, err)
        if self.lower != null:
            c := sp - self.lower
            self._lim_lo = _limit_target(c, h, beta, maxb, c >= 0.0)
        if self.upper != null:
            c2 := sp - self.upper
            self._lim_hi = _limit_target(c2, h, beta, maxb, c2 <= 0.0)

    func solve():
        a := self.a
        b := self.b
        if self._mrow != null:
            self._macc = _row_solve(a, b, self._mrow, self.motor_speed, self._macc, 0.0 - self._mmax, self._mmax)
        if self._lim_lo != null:
            self._acc_lo = _row_solve(a, b, self._limrow, self._lim_lo, self._acc_lo, 0.0, BIG)
        if self._lim_hi != null:
            self._acc_hi = _row_solve(a, b, self._limrow, self._lim_hi, self._acc_hi, 0.0 - BIG, 0.0)
        self._solve_lock()
        self._latacc[0] = _row_solve(a, b, self._lat[0], self._lattar[0], self._latacc[0], 0.0 - BIG, BIG)
        self._latacc[1] = _row_solve(a, b, self._lat[1], self._lattar[1], self._latacc[1], 0.0 - BIG, BIG)

    func impulse_magnitude():
        return math.abs(self._latacc[0]) + math.abs(self._latacc[1]) + _len(self._lacc)

    func keeps_awake():
        return self.motor_enabled

# --- fabriques ---

# Corps statique minuscule servant d'ancrage au monde pour une articulation.
func fixed_point(position):
    return static_body(sphere(0.001), position)

func ball_joint(a, b, world_anchor):
    return BallJoint(a, b, world_anchor)

func fixed_joint(a, b, world_anchor=null):
    anchor := world_anchor
    if anchor == null:
        anchor = _scale(_add(a.position, b.position), 0.5)
    return FixedJoint(a, b, anchor)

func hinge_joint(a, b, world_anchor, world_axis, lower=null, upper=null):
    return HingeJoint(a, b, world_anchor, world_axis, lower, upper)

func distance_joint(a, b, world_anchor_a=null, world_anchor_b=null, min_length=null, max_length=null):
    pa := world_anchor_a
    pb := world_anchor_b
    if pa == null:
        pa = a.position
    if pb == null:
        pb = b.position
    return DistanceJoint(a, b, pa, pb, min_length, max_length)

# Ressort amorti entre deux ancres : frequency en Hz, damping_ratio dans [0, 1].
func spring_joint(a, b, world_anchor_a, world_anchor_b, frequency, damping_ratio=0.5, rest_length=null):
    j := DistanceJoint(a, b, world_anchor_a, world_anchor_b)
    j.frequency = frequency * 1.0
    j.damping_ratio = damping_ratio * 1.0
    if rest_length != null:
        j.rest_length = rest_length * 1.0
    return j

func slider_joint(a, b, world_anchor, world_axis, lower=null, upper=null):
    return SliderJoint(a, b, world_anchor, world_axis, lower, upper)
