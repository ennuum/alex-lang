# ALEX STANDARD LIBRARY — math3d
#
# Mathématiques des jeux 2D et 3D : vecteurs Vec2/Vec3/Vec4, matrices Mat3 (transformations 2D affines)
# et Mat4 (3D), quaternions, plans, boîtes englobantes (AABB), frustum. ALEX pur, aucune dépendance native.
# (Pour l'algèbre linéaire générale sur matrices quelconques, voir le module `linalg`.)
#
#   use math3d
#   p := math3d.vec3(1, 2, 3)
#   q := math3d.quat_from_axis_angle(math3d.vec3_unit_y(), math3d.PI / 2)
#   print(math3d.vec3_to_string(math3d.quat_rotate(q, p)))       # (3, 2, -1)
#   m := math3d.mat4_compose(p, q, math3d.vec3(1, 1, 1))
#   proj := math3d.mat4_perspective(math3d.radians(60), 16 / 9, 0.1, 100)
#
# REPRÉSENTATION (le langage ne surcharge pas d'opérateurs pour les listes : fonctions libres)
#   Vec2 / Vec3 / Vec4 : listes [x, y], [x, y, z], [x, y, z, w] de flottants.
#   Quat               : liste [x, y, z, w] (w = partie scalaire), unitaire pour représenter une rotation.
#   Mat3               : 9 flottants, ORDRE COLONNE : m[colonne * 3 + ligne]. Sert aux transformations 2D
#                        affines (rotation, échelle, translation dans la 3e colonne) et aux rotations 3D.
#   Mat4               : 16 flottants, ORDRE COLONNE : m[colonne * 4 + ligne] (comme OpenGL / glTF).
#                        La translation est donc en m[12], m[13], m[14].
#   Plan               : [nx, ny, nz, d], un point p est sur le plan si n·p + d = 0 ; positif = côté de la normale.
#   AABB               : [min, max], deux Vec3.
#
# CONVENTIONS
#   - Repère main droite, Y vers le haut, la caméra regarde vers -Z (`mat4_look_at`, `mat4_perspective`
#     suivent OpenGL : profondeur normalisée dans [-1, 1]). Les angles sont en RADIANS.
#   - Une rotation « Euler » est ordonnée YXZ (lacet y, tangage x, roulis z) : `quat_from_euler(x, y, z)`.
#   - Toutes les fonctions RENVOIENT une nouvelle liste et ne modifient jamais leurs arguments.
#   - Les entiers sont acceptés partout (convertis en flottants par les constructeurs).
#   - Erreurs : division par zéro / matrice singulière -> ValueError ; argument de mauvaise taille -> TypeError.

use math
from core use len, is_int, is_float
from collections use append

const PI := 3.14159265358979323846
const TAU := 6.28318530717958647692
const HALF_PI := 1.57079632679489661923
const EPSILON := 0.000000001
const DEG2RAD := 0.01745329251994329577
const RAD2DEG := 57.29577951308232087680

# =============================================================================
# Scalaires
# =============================================================================

func radians(deg):
    return deg * DEG2RAD

func degrees(rad):
    return rad * RAD2DEG

func clamp(x, low, high):
    if x < low:
        return low
    if x > high:
        return high
    return x

func clamp01(x):
    return clamp(x, 0.0, 1.0)

func lerp(a, b, t):
    return a + (b - a) * t

# Position de x entre a et b (0 en a, 1 en b) ; 0 si a == b.
func inverse_lerp(a, b, x):
    if a == b:
        return 0.0
    return (x - a) / (b - a)

# Convertit x de l'intervalle [a, b] vers [c, d].
func remap(x, a, b, c, d):
    return lerp(c, d, inverse_lerp(a, b, x))

func smoothstep(edge0, edge1, x):
    t := clamp01(inverse_lerp(edge0, edge1, x))
    return t * t * (3.0 - 2.0 * t)

func smootherstep(edge0, edge1, x):
    t := clamp01(inverse_lerp(edge0, edge1, x))
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0)

func approx(a, b, eps=0.000001):
    return math.abs(a - b) <= eps

func sign(x):
    if x > 0:
        return 1.0
    if x < 0:
        return -1.0
    return 0.0

# Avance de a vers b d'au plus max_delta sans dépasser b.
func move_towards(a, b, max_delta):
    if math.abs(b - a) <= max_delta:
        return b
    return a + sign(b - a) * max_delta

# Ramène un angle dans ]-pi, pi].
func wrap_angle(a):
    r := math.fmod(a + PI, TAU)
    if r <= 0.0:
        r = r + TAU
    return r - PI

# Différence angulaire signée la plus courte de a vers b, dans ]-pi, pi].
func angle_delta(a, b):
    return wrap_angle(b - a)

func lerp_angle(a, b, t):
    return a + angle_delta(a, b) * t

# Lissage exponentiel indépendant du framerate : renvoie la nouvelle valeur de `current` (lambda > 0 : vitesse).
func damp(current, target, rate, dt):
    return lerp(current, target, 1.0 - math.exp(0.0 - rate * dt))

# Valeur qui oscille entre 0 et length.
func ping_pong(t, length):
    if length == 0:
        return 0.0
    r := math.fmod(t, length * 2.0)
    if r < 0.0:
        r = r + length * 2.0
    if r > length:
        return length * 2.0 - r
    return r

# =============================================================================
# Vec2
# =============================================================================

func vec2(x=0.0, y=0.0):
    return [x * 1.0, y * 1.0]

func vec2_zero():
    return [0.0, 0.0]

func vec2_one():
    return [1.0, 1.0]

func vec2_unit_x():
    return [1.0, 0.0]

func vec2_unit_y():
    return [0.0, 1.0]

func vec2_add(a, b):
    return [a[0] + b[0], a[1] + b[1]]

func vec2_sub(a, b):
    return [a[0] - b[0], a[1] - b[1]]

# Produit composante par composante.
func vec2_mul(a, b):
    return [a[0] * b[0], a[1] * b[1]]

func vec2_div(a, b):
    if b[0] == 0 or b[1] == 0:
        raise("ValueError", "math3d.vec2_div : division par zéro")
    return [a[0] / b[0], a[1] / b[1]]

func vec2_scale(a, s):
    return [a[0] * s, a[1] * s]

func vec2_neg(a):
    return [0.0 - a[0], 0.0 - a[1]]

func vec2_dot(a, b):
    return a[0] * b[0] + a[1] * b[1]

# Produit vectoriel 2D (composante z du produit 3D) : > 0 si b est à gauche de a (sens trigonométrique).
func vec2_cross(a, b):
    return a[0] * b[1] - a[1] * b[0]

func vec2_length_sq(a):
    return a[0] * a[0] + a[1] * a[1]

func vec2_length(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1])

func vec2_distance(a, b):
    return vec2_length(vec2_sub(a, b))

func vec2_distance_sq(a, b):
    return vec2_length_sq(vec2_sub(a, b))

# Vecteur unitaire de même direction ; le vecteur nul reste nul.
func vec2_normalize(a):
    l := vec2_length(a)
    if l < EPSILON:
        return [0.0, 0.0]
    return [a[0] / l, a[1] / l]

func vec2_lerp(a, b, t):
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t]

# Perpendiculaire à gauche (rotation de +90°).
func vec2_perp(a):
    return [0.0 - a[1], a[0]]

# Rotation de `angle` radians autour de l'origine (sens trigonométrique).
func vec2_rotate(a, angle):
    c := math.cos(angle)
    s := math.sin(angle)
    return [a[0] * c - a[1] * s, a[0] * s + a[1] * c]

# Rotation autour d'un pivot.
func vec2_rotate_around(a, pivot, angle):
    return vec2_add(vec2_rotate(vec2_sub(a, pivot), angle), pivot)

# Angle du vecteur par rapport à l'axe X, dans ]-pi, pi].
func vec2_angle(a):
    return math.atan2(a[1], a[0])

func vec2_from_angle(angle, length=1.0):
    return [math.cos(angle) * length, math.sin(angle) * length]

# Angle signé de a vers b.
func vec2_angle_between(a, b):
    return math.atan2(vec2_cross(a, b), vec2_dot(a, b))

# Réflexion de a sur une surface de normale n (unitaire).
func vec2_reflect(a, n):
    d := 2.0 * vec2_dot(a, n)
    return [a[0] - d * n[0], a[1] - d * n[1]]

# Projection de a sur b.
func vec2_project(a, b):
    d := vec2_length_sq(b)
    if d < EPSILON:
        return [0.0, 0.0]
    return vec2_scale(b, vec2_dot(a, b) / d)

func vec2_clamp_length(a, max_length):
    l := vec2_length(a)
    if l > max_length and l > EPSILON:
        return vec2_scale(a, max_length / l)
    return [a[0], a[1]]

func vec2_min(a, b):
    return [math.min(a[0], b[0]), math.min(a[1], b[1])]

func vec2_max(a, b):
    return [math.max(a[0], b[0]), math.max(a[1], b[1])]

func vec2_abs(a):
    return [math.abs(a[0]), math.abs(a[1])]

func vec2_floor(a):
    return [math.floor(a[0]) * 1.0, math.floor(a[1]) * 1.0]

func vec2_move_towards(a, b, max_delta):
    d := vec2_sub(b, a)
    l := vec2_length(d)
    if l <= max_delta or l < EPSILON:
        return [b[0], b[1]]
    return vec2_add(a, vec2_scale(d, max_delta / l))

func vec2_equals(a, b, eps=0.000001):
    return math.abs(a[0] - b[0]) <= eps and math.abs(a[1] - b[1]) <= eps

func vec2_to_string(a):
    return f"({a[0]}, {a[1]})"

# =============================================================================
# Vec3
# =============================================================================

func vec3(x=0.0, y=0.0, z=0.0):
    return [x * 1.0, y * 1.0, z * 1.0]

func vec3_zero():
    return [0.0, 0.0, 0.0]

func vec3_one():
    return [1.0, 1.0, 1.0]

func vec3_unit_x():
    return [1.0, 0.0, 0.0]

func vec3_unit_y():
    return [0.0, 1.0, 0.0]

func vec3_unit_z():
    return [0.0, 0.0, 1.0]

# Vecteur « avant » d'un objet non tourné (-Z), « haut » (+Y) et « droite » (+X).
func vec3_forward():
    return [0.0, 0.0, -1.0]

func vec3_up():
    return [0.0, 1.0, 0.0]

func vec3_right():
    return [1.0, 0.0, 0.0]

func vec3_add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

func vec3_sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

func vec3_mul(a, b):
    return [a[0] * b[0], a[1] * b[1], a[2] * b[2]]

func vec3_div(a, b):
    if b[0] == 0 or b[1] == 0 or b[2] == 0:
        raise("ValueError", "math3d.vec3_div : division par zéro")
    return [a[0] / b[0], a[1] / b[1], a[2] / b[2]]

func vec3_scale(a, s):
    return [a[0] * s, a[1] * s, a[2] * s]

func vec3_neg(a):
    return [0.0 - a[0], 0.0 - a[1], 0.0 - a[2]]

# a + b * s (utile pour l'intégration : p = vec3_madd(p, v, dt)).
func vec3_madd(a, b, s):
    return [a[0] + b[0] * s, a[1] + b[1] * s, a[2] + b[2] * s]

func vec3_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

func vec3_cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

# Produit mixte a · (b × c) : volume signé du parallélépipède.
func vec3_triple(a, b, c):
    return vec3_dot(a, vec3_cross(b, c))

func vec3_length_sq(a):
    return a[0] * a[0] + a[1] * a[1] + a[2] * a[2]

func vec3_length(a):
    return math.sqrt(a[0] * a[0] + a[1] * a[1] + a[2] * a[2])

func vec3_distance(a, b):
    return vec3_length(vec3_sub(a, b))

func vec3_distance_sq(a, b):
    return vec3_length_sq(vec3_sub(a, b))

func vec3_normalize(a):
    l := vec3_length(a)
    if l < EPSILON:
        return [0.0, 0.0, 0.0]
    return [a[0] / l, a[1] / l, a[2] / l]

func vec3_lerp(a, b, t):
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t]

# Angle non signé entre a et b, dans [0, pi].
func vec3_angle_between(a, b):
    d := vec3_length(a) * vec3_length(b)
    if d < EPSILON:
        return 0.0
    return math.acos(clamp(vec3_dot(a, b) / d, -1.0, 1.0))

func vec3_reflect(a, n):
    d := 2.0 * vec3_dot(a, n)
    return [a[0] - d * n[0], a[1] - d * n[1], a[2] - d * n[2]]

# Réfraction de a (unitaire) à travers une surface de normale n (unitaire), eta = n1/n2.
# Renvoie le vecteur nul en cas de réflexion totale interne.
func vec3_refract(a, n, eta):
    cos_i := 0.0 - vec3_dot(n, a)
    k := 1.0 - eta * eta * (1.0 - cos_i * cos_i)
    if k < 0.0:
        return [0.0, 0.0, 0.0]
    f := eta * cos_i - math.sqrt(k)
    return [a[0] * eta + n[0] * f, a[1] * eta + n[1] * f, a[2] * eta + n[2] * f]

# Projection de a sur b.
func vec3_project(a, b):
    d := vec3_length_sq(b)
    if d < EPSILON:
        return [0.0, 0.0, 0.0]
    return vec3_scale(b, vec3_dot(a, b) / d)

# Composante de a perpendiculaire à b.
func vec3_reject(a, b):
    return vec3_sub(a, vec3_project(a, b))

# Projection de a sur le plan de normale n (unitaire).
func vec3_project_on_plane(a, n):
    return vec3_sub(a, vec3_scale(n, vec3_dot(a, n)))

func vec3_clamp_length(a, max_length):
    l := vec3_length(a)
    if l > max_length and l > EPSILON:
        return vec3_scale(a, max_length / l)
    return [a[0], a[1], a[2]]

func vec3_min(a, b):
    return [math.min(a[0], b[0]), math.min(a[1], b[1]), math.min(a[2], b[2])]

func vec3_max(a, b):
    return [math.max(a[0], b[0]), math.max(a[1], b[1]), math.max(a[2], b[2])]

func vec3_abs(a):
    return [math.abs(a[0]), math.abs(a[1]), math.abs(a[2])]

func vec3_move_towards(a, b, max_delta):
    d := vec3_sub(b, a)
    l := vec3_length(d)
    if l <= max_delta or l < EPSILON:
        return [b[0], b[1], b[2]]
    return vec3_add(a, vec3_scale(d, max_delta / l))

# Rotation de v autour d'un axe (unitaire ou non) de `angle` radians (formule de Rodrigues).
func vec3_rotate_axis(v, axis, angle):
    k := vec3_normalize(axis)
    c := math.cos(angle)
    s := math.sin(angle)
    kv := vec3_cross(k, v)
    d := vec3_dot(k, v) * (1.0 - c)
    return [v[0] * c + kv[0] * s + k[0] * d, v[1] * c + kv[1] * s + k[1] * d, v[2] * c + kv[2] * s + k[2] * d]

# Deux vecteurs unitaires t, b tels que (n, t, b) forment une base orthonormée directe (n unitaire).
func vec3_orthonormal_basis(n):
    t := [0.0, 0.0, 0.0]
    if math.abs(n[0]) > 0.57735:
        t = vec3_normalize([0.0 - n[1], n[0], 0.0])
    else:
        t = vec3_normalize([0.0, 0.0 - n[2], n[1]])
    return [t, vec3_cross(n, t)]

func vec3_equals(a, b, eps=0.000001):
    return math.abs(a[0] - b[0]) <= eps and math.abs(a[1] - b[1]) <= eps and math.abs(a[2] - b[2]) <= eps

func vec3_to_string(a):
    return f"({a[0]}, {a[1]}, {a[2]})"

# Conversions entre dimensions.
func vec3_from_vec2(a, z=0.0):
    return [a[0], a[1], z * 1.0]

func vec2_from_vec3(a):
    return [a[0], a[1]]

# =============================================================================
# Vec4
# =============================================================================

func vec4(x=0.0, y=0.0, z=0.0, w=0.0):
    return [x * 1.0, y * 1.0, z * 1.0, w * 1.0]

func vec4_from_vec3(a, w=1.0):
    return [a[0], a[1], a[2], w * 1.0]

func vec4_xyz(a):
    return [a[0], a[1], a[2]]

func vec4_add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2], a[3] + b[3]]

func vec4_sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2], a[3] - b[3]]

func vec4_mul(a, b):
    return [a[0] * b[0], a[1] * b[1], a[2] * b[2], a[3] * b[3]]

func vec4_scale(a, s):
    return [a[0] * s, a[1] * s, a[2] * s, a[3] * s]

func vec4_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]

func vec4_length(a):
    return math.sqrt(vec4_dot(a, a))

func vec4_normalize(a):
    l := vec4_length(a)
    if l < EPSILON:
        return [0.0, 0.0, 0.0, 0.0]
    return [a[0] / l, a[1] / l, a[2] / l, a[3] / l]

func vec4_lerp(a, b, t):
    return [a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t]

# Division perspective : (x/w, y/w, z/w).
func vec4_to_vec3(a):
    if a[3] == 0:
        return [a[0], a[1], a[2]]
    return [a[0] / a[3], a[1] / a[3], a[2] / a[3]]

func vec4_equals(a, b, eps=0.000001):
    return math.abs(a[0] - b[0]) <= eps and math.abs(a[1] - b[1]) <= eps and math.abs(a[2] - b[2]) <= eps and math.abs(a[3] - b[3]) <= eps

func vec4_to_string(a):
    return f"({a[0]}, {a[1]}, {a[2]}, {a[3]})"

# Couleur : composantes RGBA [0, 1] <-> entier 0xRRGGBBAA.
func color_to_int(c):
    r := math.floor(clamp01(c[0]) * 255.0 + 0.5)
    g := math.floor(clamp01(c[1]) * 255.0 + 0.5)
    b := math.floor(clamp01(c[2]) * 255.0 + 0.5)
    a := math.floor(clamp01(c[3]) * 255.0 + 0.5)
    return ((r * 256 + g) * 256 + b) * 256 + a

func color_from_int(v):
    a := v % 256
    b := (v // 256) % 256
    g := (v // 65536) % 256
    r := (v // 16777216) % 256
    return [r / 255.0, g / 255.0, b / 255.0, a / 255.0]

# =============================================================================
# Mat3 (ordre colonne, m[colonne * 3 + ligne]) : transformations 2D affines et rotations 3D
# =============================================================================

func mat3_identity():
    return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 1.0]

func mat3_translation(x, y):
    return [1.0, 0.0, 0.0, 0.0, 1.0, 0.0, x * 1.0, y * 1.0, 1.0]

# Rotation 2D de `angle` radians (sens trigonométrique).
func mat3_rotation(angle):
    c := math.cos(angle)
    s := math.sin(angle)
    return [c, s, 0.0, 0.0 - s, c, 0.0, 0.0, 0.0, 1.0]

func mat3_scaling(sx, sy):
    return [sx * 1.0, 0.0, 0.0, 0.0, sy * 1.0, 0.0, 0.0, 0.0, 1.0]

func mat3_mul(a, b):
    r := []
    c := 0
    while c < 3:
        row := 0
        while row < 3:
            append(r, a[row] * b[c * 3] + a[3 + row] * b[c * 3 + 1] + a[6 + row] * b[c * 3 + 2])
            row += 1
        c += 1
    return r

# Transformation 2D = translation * rotation * échelle (dans cet ordre d'application : échelle, rotation, translation).
func mat3_compose(position, angle, scale):
    c := math.cos(angle)
    s := math.sin(angle)
    return [c * scale[0], s * scale[0], 0.0, 0.0 - s * scale[1], c * scale[1], 0.0, position[0] * 1.0, position[1] * 1.0, 1.0]

# Inverse de mat3_compose : [position, angle, échelle]. Un cisaillement éventuel est ignoré.
func mat3_decompose(m):
    sx := math.sqrt(m[0] * m[0] + m[1] * m[1])
    sy := math.sqrt(m[3] * m[3] + m[4] * m[4])
    if mat3_determinant(m) < 0.0:
        sy = 0.0 - sy
    return [[m[6], m[7]], math.atan2(m[1], m[0]), [sx, sy]]

# Applique la matrice à un point 2D (la translation compte).
func mat3_transform_point(m, p):
    return [m[0] * p[0] + m[3] * p[1] + m[6], m[1] * p[0] + m[4] * p[1] + m[7]]

# Applique la matrice à un vecteur 2D (la translation ne compte pas).
func mat3_transform_vector(m, v):
    return [m[0] * v[0] + m[3] * v[1], m[1] * v[0] + m[4] * v[1]]

func mat3_mul_vec3(m, v):
    return [m[0] * v[0] + m[3] * v[1] + m[6] * v[2], m[1] * v[0] + m[4] * v[1] + m[7] * v[2], m[2] * v[0] + m[5] * v[1] + m[8] * v[2]]

func mat3_transpose(m):
    return [m[0], m[3], m[6], m[1], m[4], m[7], m[2], m[5], m[8]]

func mat3_determinant(m):
    return m[0] * (m[4] * m[8] - m[7] * m[5]) - m[3] * (m[1] * m[8] - m[7] * m[2]) + m[6] * (m[1] * m[5] - m[4] * m[2])

# Inverse générale (matrice adjointe). ValueError si la matrice est singulière.
func mat3_inverse(m):
    det := mat3_determinant(m)
    if math.abs(det) < 0.000000000001:
        raise("ValueError", "math3d.mat3_inverse : matrice singulière")
    id := 1.0 / det
    return [
        (m[4] * m[8] - m[7] * m[5]) * id, (m[7] * m[2] - m[1] * m[8]) * id, (m[1] * m[5] - m[4] * m[2]) * id,
        (m[6] * m[5] - m[3] * m[8]) * id, (m[0] * m[8] - m[6] * m[2]) * id, (m[3] * m[2] - m[0] * m[5]) * id,
        (m[3] * m[7] - m[6] * m[4]) * id, (m[6] * m[1] - m[0] * m[7]) * id, (m[0] * m[4] - m[3] * m[1]) * id]

# Partie 3x3 supérieure gauche d'une Mat4.
func mat3_from_mat4(m):
    return [m[0], m[1], m[2], m[4], m[5], m[6], m[8], m[9], m[10]]

# Matrice des normales d'une Mat4 : transposée de l'inverse de la partie 3x3 (à utiliser pour éclairer
# correctement des objets à échelle non uniforme).
func mat3_normal_matrix(m4):
    return mat3_transpose(mat3_inverse(mat3_from_mat4(m4)))

func mat3_equals(a, b, eps=0.000001):
    i := 0
    while i < 9:
        if math.abs(a[i] - b[i]) > eps:
            return false
        i += 1
    return true

# =============================================================================
# Mat4 (ordre colonne, m[colonne * 4 + ligne])
# =============================================================================

func mat4_identity():
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

func mat4_zero():
    return [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]

# Construit une matrice à partir de 4 lignes de 4 valeurs (écriture « mathématique » naturelle).
func mat4_from_rows(rows):
    r := []
    c := 0
    while c < 4:
        i := 0
        while i < 4:
            append(r, rows[i][c] * 1.0)
            i += 1
        c += 1
    return r

func mat4_translation(x, y, z):
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, x * 1.0, y * 1.0, z * 1.0, 1.0]

func mat4_translation_v(v):
    return mat4_translation(v[0], v[1], v[2])

func mat4_scaling(x, y, z):
    return [x * 1.0, 0.0, 0.0, 0.0, 0.0, y * 1.0, 0.0, 0.0, 0.0, 0.0, z * 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

func mat4_scaling_v(v):
    return mat4_scaling(v[0], v[1], v[2])

func mat4_rotation_x(angle):
    c := math.cos(angle)
    s := math.sin(angle)
    return [1.0, 0.0, 0.0, 0.0, 0.0, c, s, 0.0, 0.0, 0.0 - s, c, 0.0, 0.0, 0.0, 0.0, 1.0]

func mat4_rotation_y(angle):
    c := math.cos(angle)
    s := math.sin(angle)
    return [c, 0.0, 0.0 - s, 0.0, 0.0, 1.0, 0.0, 0.0, s, 0.0, c, 0.0, 0.0, 0.0, 0.0, 1.0]

func mat4_rotation_z(angle):
    c := math.cos(angle)
    s := math.sin(angle)
    return [c, s, 0.0, 0.0, 0.0 - s, c, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

# Rotation autour d'un axe quelconque.
func mat4_rotation_axis(axis, angle):
    return mat4_from_quat(quat_from_axis_angle(axis, angle))

# Rotation à partir d'un quaternion unitaire.
func mat4_from_quat(q):
    x := q[0]
    y := q[1]
    z := q[2]
    w := q[3]
    xx := x * x
    yy := y * y
    zz := z * z
    xy := x * y
    xz := x * z
    yz := y * z
    wx := w * x
    wy := w * y
    wz := w * z
    return [
        1.0 - 2.0 * (yy + zz), 2.0 * (xy + wz), 2.0 * (xz - wy), 0.0,
        2.0 * (xy - wz), 1.0 - 2.0 * (xx + zz), 2.0 * (yz + wx), 0.0,
        2.0 * (xz + wy), 2.0 * (yz - wx), 1.0 - 2.0 * (xx + yy), 0.0,
        0.0, 0.0, 0.0, 1.0]

# Produit a * b : applique d'abord b, puis a (convention colonne, comme OpenGL).
func mat4_mul(a, b):
    r := []
    c := 0
    while c < 4:
        b0 := b[c * 4]
        b1 := b[c * 4 + 1]
        b2 := b[c * 4 + 2]
        b3 := b[c * 4 + 3]
        row := 0
        while row < 4:
            append(r, a[row] * b0 + a[4 + row] * b1 + a[8 + row] * b2 + a[12 + row] * b3)
            row += 1
        c += 1
    return r

# Produit de plusieurs matrices, de gauche à droite : mat4_chain([a, b, c]) = a * b * c.
func mat4_chain(ms):
    r := ms[0]
    i := 1
    while i < len(ms):
        r = mat4_mul(r, ms[i])
        i += 1
    return r

func mat4_mul_vec4(m, v):
    return [
        m[0] * v[0] + m[4] * v[1] + m[8] * v[2] + m[12] * v[3],
        m[1] * v[0] + m[5] * v[1] + m[9] * v[2] + m[13] * v[3],
        m[2] * v[0] + m[6] * v[1] + m[10] * v[2] + m[14] * v[3],
        m[3] * v[0] + m[7] * v[1] + m[11] * v[2] + m[15] * v[3]]

# Transforme un POINT (w = 1) d'une matrice affine : sans division par w.
func mat4_transform_point(m, p):
    return [
        m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12],
        m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13],
        m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14]]

# Transforme une DIRECTION (w = 0) : ignore la translation.
func mat4_transform_direction(m, v):
    return [
        m[0] * v[0] + m[4] * v[1] + m[8] * v[2],
        m[1] * v[0] + m[5] * v[1] + m[9] * v[2],
        m[2] * v[0] + m[6] * v[1] + m[10] * v[2]]

# Transforme un point par une matrice de projection, avec division par w.
func mat4_project_point(m, p):
    r := mat4_mul_vec4(m, [p[0], p[1], p[2], 1.0])
    if math.abs(r[3]) < EPSILON:
        return [r[0], r[1], r[2]]
    return [r[0] / r[3], r[1] / r[3], r[2] / r[3]]

func mat4_transpose(m):
    r := []
    row := 0
    while row < 4:
        c := 0
        while c < 4:
            append(r, m[c * 4 + row])
            c += 1
        row += 1
    return r

func mat4_get_translation(m):
    return [m[12], m[13], m[14]]

func mat4_set_translation(m, v):
    r := mat4_copy(m)
    r[12] = v[0] * 1.0
    r[13] = v[1] * 1.0
    r[14] = v[2] * 1.0
    return r

func mat4_copy(m):
    r := []
    for x in m:
        append(r, x)
    return r

# Colonne c (0..3) sous forme de Vec4.
func mat4_column(m, c):
    return [m[c * 4], m[c * 4 + 1], m[c * 4 + 2], m[c * 4 + 3]]

# Ligne r (0..3) sous forme de Vec4.
func mat4_row(m, r):
    return [m[r], m[4 + r], m[8 + r], m[12 + r]]

# Échelle portée par la matrice (longueur des colonnes X, Y, Z).
func mat4_get_scale(m):
    return [math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2]), math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6]), math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10])]

# Déterminant (élimination de Gauss avec pivot partiel).
func mat4_determinant(m):
    a := mat4_copy(m)
    det := 1.0
    col := 0
    while col < 4:
        piv := col
        best := math.abs(a[col * 4 + col])
        r := col + 1
        while r < 4:
            v := math.abs(a[col * 4 + r])
            if v > best:
                best = v
                piv = r
            r += 1
        if best < 0.000000000000001:
            return 0.0
        if piv != col:
            k := 0
            while k < 4:
                t := a[k * 4 + col]
                a[k * 4 + col] = a[k * 4 + piv]
                a[k * 4 + piv] = t
                k += 1
            det = 0.0 - det
        p := a[col * 4 + col]
        det = det * p
        r = col + 1
        while r < 4:
            f := a[col * 4 + r] / p
            k := col
            while k < 4:
                a[k * 4 + r] = a[k * 4 + r] - f * a[k * 4 + col]
                k += 1
            r += 1
        col += 1
    return det

# Inverse générale (Gauss-Jordan, pivot partiel). ValueError si la matrice est singulière.
func mat4_inverse(m):
    a := mat4_copy(m)
    inv := mat4_identity()
    col := 0
    while col < 4:
        piv := col
        best := math.abs(a[col * 4 + col])
        r := col + 1
        while r < 4:
            v := math.abs(a[col * 4 + r])
            if v > best:
                best = v
                piv = r
            r += 1
        if best < 0.000000000000001:
            raise("ValueError", "math3d.mat4_inverse : matrice singulière")
        if piv != col:
            k := 0
            while k < 4:
                t := a[k * 4 + col]
                a[k * 4 + col] = a[k * 4 + piv]
                a[k * 4 + piv] = t
                t2 := inv[k * 4 + col]
                inv[k * 4 + col] = inv[k * 4 + piv]
                inv[k * 4 + piv] = t2
                k += 1
        p := 1.0 / a[col * 4 + col]
        k := 0
        while k < 4:
            a[k * 4 + col] = a[k * 4 + col] * p
            inv[k * 4 + col] = inv[k * 4 + col] * p
            k += 1
        r = 0
        while r < 4:
            if r != col:
                f := a[col * 4 + r]
                if f != 0.0:
                    k = 0
                    while k < 4:
                        a[k * 4 + r] = a[k * 4 + r] - f * a[k * 4 + col]
                        inv[k * 4 + r] = inv[k * 4 + r] - f * inv[k * 4 + col]
                        k += 1
            r += 1
        col += 1
    return inv

# Inverse rapide d'une transformation affine (dernière ligne 0 0 0 1) : rotation/échelle/translation.
func mat4_inverse_affine(m):
    i3 := mat3_inverse(mat3_from_mat4(m))
    t := [m[12], m[13], m[14]]
    ti := mat3_mul_vec3(i3, [t[0], t[1], t[2]])
    return [i3[0], i3[1], i3[2], 0.0, i3[3], i3[4], i3[5], 0.0, i3[6], i3[7], i3[8], 0.0, 0.0 - ti[0], 0.0 - ti[1], 0.0 - ti[2], 1.0]

# Matrice TRS : échelle, puis rotation (quaternion), puis translation.
func mat4_compose(position, rotation, scale):
    r := mat4_from_quat(rotation)
    r[0] = r[0] * scale[0]
    r[1] = r[1] * scale[0]
    r[2] = r[2] * scale[0]
    r[4] = r[4] * scale[1]
    r[5] = r[5] * scale[1]
    r[6] = r[6] * scale[1]
    r[8] = r[8] * scale[2]
    r[9] = r[9] * scale[2]
    r[10] = r[10] * scale[2]
    r[12] = position[0] * 1.0
    r[13] = position[1] * 1.0
    r[14] = position[2] * 1.0
    return r

# Inverse de mat4_compose : [position, quaternion, échelle]. Un cisaillement éventuel est ignoré.
func mat4_decompose(m):
    s := mat4_get_scale(m)
    if mat4_determinant(m) < 0.0:
        s[0] = 0.0 - s[0]
    sx := s[0]
    if sx == 0.0:
        sx = 1.0
    sy := s[1]
    if sy == 0.0:
        sy = 1.0
    sz := s[2]
    if sz == 0.0:
        sz = 1.0
    rot := [m[0] / sx, m[1] / sx, m[2] / sx, m[4] / sy, m[5] / sy, m[6] / sy, m[8] / sz, m[9] / sz, m[10] / sz]
    return [[m[12], m[13], m[14]], quat_from_mat3(rot), s]

# Matrice de vue : place la caméra en `eye` regardant `target`, `up` = direction approximative du haut.
func mat4_look_at(eye, target, up):
    f := vec3_normalize(vec3_sub(target, eye))
    if vec3_length_sq(f) < EPSILON:
        raise("ValueError", "math3d.mat4_look_at : eye et target confondus")
    s := vec3_cross(f, up)
    if vec3_length_sq(s) < EPSILON:
        # `up` colinéaire à la direction du regard : on choisit un autre haut.
        alt := [0.0, 0.0, 1.0]
        if math.abs(f[2]) > 0.99:
            alt = [1.0, 0.0, 0.0]
        s = vec3_cross(f, alt)
    s = vec3_normalize(s)
    u := vec3_cross(s, f)
    return [
        s[0], u[0], 0.0 - f[0], 0.0,
        s[1], u[1], 0.0 - f[1], 0.0,
        s[2], u[2], 0.0 - f[2], 0.0,
        0.0 - vec3_dot(s, eye), 0.0 - vec3_dot(u, eye), vec3_dot(f, eye), 1.0]

# Projection perspective (champ de vision vertical fovy en radians), profondeur dans [-1, 1].
func mat4_perspective(fovy, aspect, near, far):
    if near <= 0 or far <= near or aspect <= 0 or fovy <= 0 or fovy >= PI:
        raise("ValueError", "math3d.mat4_perspective : paramètres invalides")
    f := 1.0 / math.tan(fovy / 2.0)
    return [
        f / aspect, 0.0, 0.0, 0.0,
        0.0, f, 0.0, 0.0,
        0.0, 0.0, (far + near) / (near - far), -1.0,
        0.0, 0.0, 2.0 * far * near / (near - far), 0.0]

# Projection orthographique.
func mat4_ortho(left, right, bottom, top, near, far):
    if right == left or top == bottom or far == near:
        raise("ValueError", "math3d.mat4_ortho : volume dégénéré")
    return [
        2.0 / (right - left), 0.0, 0.0, 0.0,
        0.0, 2.0 / (top - bottom), 0.0, 0.0,
        0.0, 0.0, -2.0 / (far - near), 0.0,
        0.0 - (right + left) / (right - left), 0.0 - (top + bottom) / (top - bottom), 0.0 - (far + near) / (far - near), 1.0]

# Projection 2D : l'écran va de (0, 0) en haut à gauche à (width, height) en bas à droite (axe Y vers le bas).
func mat4_ortho_screen(width, height):
    return mat4_ortho(0.0, width * 1.0, height * 1.0, 0.0, -1.0, 1.0)

# Frustum asymétrique.
func mat4_frustum(left, right, bottom, top, near, far):
    return [
        2.0 * near / (right - left), 0.0, 0.0, 0.0,
        0.0, 2.0 * near / (top - bottom), 0.0, 0.0,
        (right + left) / (right - left), (top + bottom) / (top - bottom), 0.0 - (far + near) / (far - near), -1.0,
        0.0, 0.0, -2.0 * far * near / (far - near), 0.0]

# Projette un point monde sur l'écran : [x, y, profondeur] où x, y sont en pixels (origine en haut à gauche) et
# la profondeur dans [0, 1]. mvp = projection * vue * modèle. Renvoie null si le point est derrière la caméra.
func mat4_project_to_screen(mvp, p, viewport_w, viewport_h):
    r := mat4_mul_vec4(mvp, [p[0], p[1], p[2], 1.0])
    if r[3] <= EPSILON:
        return null
    nx := r[0] / r[3]
    ny := r[1] / r[3]
    nz := r[2] / r[3]
    return [(nx * 0.5 + 0.5) * viewport_w, (1.0 - (ny * 0.5 + 0.5)) * viewport_h, nz * 0.5 + 0.5]

# Inverse de mat4_project_to_screen : point monde pour un pixel (x, y) et une profondeur dans [0, 1].
# inv_vp = inverse(projection * vue).
func mat4_unproject(inv_vp, x, y, depth, viewport_w, viewport_h):
    nx := (x / viewport_w) * 2.0 - 1.0
    ny := (1.0 - y / viewport_h) * 2.0 - 1.0
    nz := depth * 2.0 - 1.0
    r := mat4_mul_vec4(inv_vp, [nx, ny, nz, 1.0])
    if math.abs(r[3]) < EPSILON:
        raise("ValueError", "math3d.mat4_unproject : w nul")
    return [r[0] / r[3], r[1] / r[3], r[2] / r[3]]

# Les 6 plans du frustum d'une matrice view-projection (gauche, droite, bas, haut, proche, loin), normalisés,
# normales vers l'INTÉRIEUR : un point est visible si plane_distance(plan, p) >= 0 pour les 6 plans.
func mat4_frustum_planes(vp):
    r0 := mat4_row(vp, 0)
    r1 := mat4_row(vp, 1)
    r2 := mat4_row(vp, 2)
    r3 := mat4_row(vp, 3)
    return [
        plane_normalize(vec4_add(r3, r0)),
        plane_normalize(vec4_sub(r3, r0)),
        plane_normalize(vec4_add(r3, r1)),
        plane_normalize(vec4_sub(r3, r1)),
        plane_normalize(vec4_add(r3, r2)),
        plane_normalize(vec4_sub(r3, r2))]

func mat4_equals(a, b, eps=0.000001):
    i := 0
    while i < 16:
        if math.abs(a[i] - b[i]) > eps:
            return false
        i += 1
    return true

func mat4_to_string(m):
    lines := []
    row := 0
    while row < 4:
        append(lines, f"[{m[row]}, {m[4 + row]}, {m[8 + row]}, {m[12 + row]}]")
        row += 1
    return lines[0] + "\n" + lines[1] + "\n" + lines[2] + "\n" + lines[3]

# =============================================================================
# Quaternions [x, y, z, w]
# =============================================================================

func quat_identity():
    return [0.0, 0.0, 0.0, 1.0]

func quat(x, y, z, w):
    return [x * 1.0, y * 1.0, z * 1.0, w * 1.0]

func quat_from_axis_angle(axis, angle):
    k := vec3_normalize(axis)
    s := math.sin(angle / 2.0)
    return [k[0] * s, k[1] * s, k[2] * s, math.cos(angle / 2.0)]

# Rotation Euler ordonnée YXZ : lacet y, puis tangage x, puis roulis z (angles en radians).
func quat_from_euler(x, y, z):
    qy := quat_from_axis_angle([0.0, 1.0, 0.0], y)
    qx := quat_from_axis_angle([1.0, 0.0, 0.0], x)
    qz := quat_from_axis_angle([0.0, 0.0, 1.0], z)
    return quat_mul(quat_mul(qy, qx), qz)

# [x, y, z] tels que quat_from_euler(x, y, z) redonne la rotation (x dans [-pi/2, pi/2]).
func quat_to_euler(q):
    m := mat3_from_mat4(mat4_from_quat(quat_normalize(q)))
    # Mat3 colonne : m[col*3+ligne]
    sx := 0.0 - m[7]
    sx = clamp(sx, -1.0, 1.0)
    ex := math.asin(sx)
    ey := 0.0
    ez := 0.0
    if math.abs(sx) < 0.9999999:
        ey = math.atan2(m[6], m[8])
        ez = math.atan2(m[1], m[4])
    else:
        ey = math.atan2(0.0 - m[2], m[0])
        ez = 0.0
    return [ex, ey, ez]

func quat_mul(a, b):
    return [
        a[3] * b[0] + a[0] * b[3] + a[1] * b[2] - a[2] * b[1],
        a[3] * b[1] - a[0] * b[2] + a[1] * b[3] + a[2] * b[0],
        a[3] * b[2] + a[0] * b[1] - a[1] * b[0] + a[2] * b[3],
        a[3] * b[3] - a[0] * b[0] - a[1] * b[1] - a[2] * b[2]]

func quat_conjugate(q):
    return [0.0 - q[0], 0.0 - q[1], 0.0 - q[2], q[3]]

func quat_dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]

func quat_length(q):
    return math.sqrt(quat_dot(q, q))

func quat_normalize(q):
    l := quat_length(q)
    if l < EPSILON:
        return [0.0, 0.0, 0.0, 1.0]
    return [q[0] / l, q[1] / l, q[2] / l, q[3] / l]

# Inverse (conjugué divisé par la norme au carré) ; ValueError pour le quaternion nul.
func quat_inverse(q):
    d := quat_dot(q, q)
    if d < EPSILON:
        raise("ValueError", "math3d.quat_inverse : quaternion nul")
    return [0.0 - q[0] / d, 0.0 - q[1] / d, 0.0 - q[2] / d, q[3] / d]

# Fait tourner un Vec3 par le quaternion unitaire q.
func quat_rotate(q, v):
    u := [q[0], q[1], q[2]]
    t := vec3_scale(vec3_cross(u, v), 2.0)
    c := vec3_cross(u, t)
    return [v[0] + q[3] * t[0] + c[0], v[1] + q[3] * t[1] + c[1], v[2] + q[3] * t[2] + c[2]]

# Interpolation linéaire normalisée (rapide, vitesse angulaire non constante), chemin le plus court.
func quat_nlerp(a, b, t):
    bb := b
    if quat_dot(a, b) < 0.0:
        bb = [0.0 - b[0], 0.0 - b[1], 0.0 - b[2], 0.0 - b[3]]
    return quat_normalize([a[0] + (bb[0] - a[0]) * t, a[1] + (bb[1] - a[1]) * t, a[2] + (bb[2] - a[2]) * t, a[3] + (bb[3] - a[3]) * t])

# Interpolation sphérique (vitesse angulaire constante), chemin le plus court.
func quat_slerp(a, b, t):
    d := quat_dot(a, b)
    bb := b
    if d < 0.0:
        bb = [0.0 - b[0], 0.0 - b[1], 0.0 - b[2], 0.0 - b[3]]
        d = 0.0 - d
    if d > 0.9995:
        return quat_nlerp(a, bb, t)
    theta := math.acos(clamp(d, -1.0, 1.0))
    s := math.sin(theta)
    wa := math.sin((1.0 - t) * theta) / s
    wb := math.sin(t * theta) / s
    return [a[0] * wa + bb[0] * wb, a[1] * wa + bb[1] * wb, a[2] * wa + bb[2] * wb, a[3] * wa + bb[3] * wb]

# Angle (radians, [0, pi]) de la rotation relative entre deux orientations.
func quat_angle_between(a, b):
    d := math.abs(quat_dot(quat_normalize(a), quat_normalize(b)))
    return 2.0 * math.acos(clamp(d, 0.0, 1.0))

# [axe, angle] de la rotation (axe = +X si la rotation est nulle).
func quat_to_axis_angle(q):
    n := quat_normalize(q)
    w := n[3]
    if w < 0.0:
        n = [0.0 - n[0], 0.0 - n[1], 0.0 - n[2], 0.0 - n[3]]
        w = n[3]
    angle := 2.0 * math.acos(clamp(w, -1.0, 1.0))
    s := math.sqrt(1.0 - w * w)
    if s < 0.000001:
        return [[1.0, 0.0, 0.0], angle]
    return [[n[0] / s, n[1] / s, n[2] / s], angle]

# Rotation la plus courte qui amène la direction a sur la direction b.
func quat_from_to(a, b):
    u := vec3_normalize(a)
    v := vec3_normalize(b)
    d := vec3_dot(u, v)
    if d > 0.999999:
        return [0.0, 0.0, 0.0, 1.0]
    if d < -0.999999:
        # directions opposées : demi-tour autour d'un axe perpendiculaire quelconque
        axis := vec3_cross([1.0, 0.0, 0.0], u)
        if vec3_length_sq(axis) < 0.000001:
            axis = vec3_cross([0.0, 1.0, 0.0], u)
        return quat_from_axis_angle(axis, PI)
    c := vec3_cross(u, v)
    return quat_normalize([c[0], c[1], c[2], 1.0 + d])

# Orientation dont l'avant (-Z) pointe vers `direction`, le haut étant au plus près de `up`.
func quat_look_rotation(direction, up):
    f := vec3_normalize(direction)
    if vec3_length_sq(f) < EPSILON:
        return [0.0, 0.0, 0.0, 1.0]
    r := vec3_cross(f, up)
    if vec3_length_sq(r) < EPSILON:
        alt := [0.0, 0.0, 1.0]
        if math.abs(f[2]) > 0.99:
            alt = [1.0, 0.0, 0.0]
        r = vec3_cross(f, alt)
    r = vec3_normalize(r)
    u := vec3_cross(r, f)
    # colonnes : droite, haut, arrière (= -avant)
    return quat_from_mat3([r[0], r[1], r[2], u[0], u[1], u[2], 0.0 - f[0], 0.0 - f[1], 0.0 - f[2]])

# Quaternion d'une Mat3 de rotation (ordre colonne).
func quat_from_mat3(m):
    tr := m[0] + m[4] + m[8]
    if tr > 0.0:
        s := math.sqrt(tr + 1.0) * 2.0
        return quat_normalize([(m[5] - m[7]) / s, (m[6] - m[2]) / s, (m[1] - m[3]) / s, 0.25 * s])
    if m[0] > m[4] and m[0] > m[8]:
        s := math.sqrt(1.0 + m[0] - m[4] - m[8]) * 2.0
        return quat_normalize([0.25 * s, (m[3] + m[1]) / s, (m[6] + m[2]) / s, (m[5] - m[7]) / s])
    if m[4] > m[8]:
        s := math.sqrt(1.0 + m[4] - m[0] - m[8]) * 2.0
        return quat_normalize([(m[3] + m[1]) / s, 0.25 * s, (m[7] + m[5]) / s, (m[6] - m[2]) / s])
    s := math.sqrt(1.0 + m[8] - m[0] - m[4]) * 2.0
    return quat_normalize([(m[6] + m[2]) / s, (m[7] + m[5]) / s, 0.25 * s, (m[1] - m[3]) / s])

func quat_from_mat4(m):
    return quat_from_mat3(mat3_from_mat4(m))

func quat_equals(a, b, eps=0.000001):
    # q et -q représentent la même rotation
    same := math.abs(a[0] - b[0]) <= eps and math.abs(a[1] - b[1]) <= eps and math.abs(a[2] - b[2]) <= eps and math.abs(a[3] - b[3]) <= eps
    opp := math.abs(a[0] + b[0]) <= eps and math.abs(a[1] + b[1]) <= eps and math.abs(a[2] + b[2]) <= eps and math.abs(a[3] + b[3]) <= eps
    return same or opp

func quat_to_string(q):
    return f"({q[0]}, {q[1]}, {q[2]}, {q[3]})"

# =============================================================================
# Plans [nx, ny, nz, d] (n·p + d = 0)
# =============================================================================

func plane_from_normal_point(normal, point):
    n := vec3_normalize(normal)
    return [n[0], n[1], n[2], 0.0 - vec3_dot(n, point)]

# Plan passant par trois points (normale = (b-a) × (c-a), sens trigonométrique vu de la normale).
func plane_from_points(a, b, c):
    n := vec3_cross(vec3_sub(b, a), vec3_sub(c, a))
    if vec3_length_sq(n) < EPSILON * EPSILON:
        raise("ValueError", "math3d.plane_from_points : points alignés")
    return plane_from_normal_point(n, a)

# Normalise la normale (et d en conséquence).
func plane_normalize(p):
    l := math.sqrt(p[0] * p[0] + p[1] * p[1] + p[2] * p[2])
    if l < EPSILON:
        return [0.0, 0.0, 0.0, p[3]]
    return [p[0] / l, p[1] / l, p[2] / l, p[3] / l]

# Distance signée d'un point au plan (positive du côté de la normale).
func plane_distance(p, point):
    return p[0] * point[0] + p[1] * point[1] + p[2] * point[2] + p[3]

func plane_closest_point(p, point):
    d := plane_distance(p, point)
    return [point[0] - p[0] * d, point[1] - p[1] * d, point[2] - p[2] * d]

# =============================================================================
# AABB [min, max]
# =============================================================================

func aabb(min_corner, max_corner):
    return [[min_corner[0] * 1.0, min_corner[1] * 1.0, min_corner[2] * 1.0], [max_corner[0] * 1.0, max_corner[1] * 1.0, max_corner[2] * 1.0]]

func aabb_from_center_extents(center, half):
    return [[center[0] - half[0], center[1] - half[1], center[2] - half[2]], [center[0] + half[0], center[1] + half[1], center[2] + half[2]]]

# Plus petite boîte contenant tous les points (liste de Vec3 non vide).
func aabb_from_points(points):
    if len(points) == 0:
        raise("ValueError", "math3d.aabb_from_points : liste vide")
    lo := [points[0][0], points[0][1], points[0][2]]
    hi := [points[0][0], points[0][1], points[0][2]]
    for p in points:
        lo = [math.min(lo[0], p[0]), math.min(lo[1], p[1]), math.min(lo[2], p[2])]
        hi = [math.max(hi[0], p[0]), math.max(hi[1], p[1]), math.max(hi[2], p[2])]
    return [lo, hi]

func aabb_center(b):
    return [(b[0][0] + b[1][0]) * 0.5, (b[0][1] + b[1][1]) * 0.5, (b[0][2] + b[1][2]) * 0.5]

# Demi-dimensions.
func aabb_extents(b):
    return [(b[1][0] - b[0][0]) * 0.5, (b[1][1] - b[0][1]) * 0.5, (b[1][2] - b[0][2]) * 0.5]

func aabb_size(b):
    return vec3_sub(b[1], b[0])

func aabb_volume(b):
    s := vec3_sub(b[1], b[0])
    return s[0] * s[1] * s[2]

func aabb_surface_area(b):
    s := vec3_sub(b[1], b[0])
    return 2.0 * (s[0] * s[1] + s[1] * s[2] + s[0] * s[2])

func aabb_union(a, b):
    return [vec3_min(a[0], b[0]), vec3_max(a[1], b[1])]

# Agrandit la boîte de `margin` dans toutes les directions.
func aabb_expand(b, margin):
    return [[b[0][0] - margin, b[0][1] - margin, b[0][2] - margin], [b[1][0] + margin, b[1][1] + margin, b[1][2] + margin]]

func aabb_contains_point(b, p):
    return p[0] >= b[0][0] and p[0] <= b[1][0] and p[1] >= b[0][1] and p[1] <= b[1][1] and p[2] >= b[0][2] and p[2] <= b[1][2]

func aabb_intersects(a, b):
    return a[0][0] <= b[1][0] and a[1][0] >= b[0][0] and a[0][1] <= b[1][1] and a[1][1] >= b[0][1] and a[0][2] <= b[1][2] and a[1][2] >= b[0][2]

func aabb_closest_point(b, p):
    return [clamp(p[0], b[0][0], b[1][0]), clamp(p[1], b[0][1], b[1][1]), clamp(p[2], b[0][2], b[1][2])]

# Boîte alignée englobant la boîte b transformée par la matrice affine m (méthode d'Arvo, exacte et rapide).
func aabb_transform(b, m):
    lo := [m[12], m[13], m[14]]
    hi := [m[12], m[13], m[14]]
    i := 0
    while i < 3:
        j := 0
        while j < 3:
            e := m[j * 4 + i] * b[0][j]
            f := m[j * 4 + i] * b[1][j]
            lo[i] = lo[i] + math.min(e, f)
            hi[i] = hi[i] + math.max(e, f)
            j += 1
        i += 1
    return [lo, hi]

# La boîte est-elle (au moins en partie) à l'intérieur des 6 plans du frustum (mat4_frustum_planes) ?
# Test conservateur : peut garder de rares boîtes invisibles près des coins, jamais l'inverse.
func aabb_in_frustum(b, planes):
    for pl in planes:
        # sommet de la boîte le plus avancé dans le sens de la normale
        px := b[0][0]
        if pl[0] >= 0.0:
            px = b[1][0]
        py := b[0][1]
        if pl[1] >= 0.0:
            py = b[1][1]
        pz := b[0][2]
        if pl[2] >= 0.0:
            pz = b[1][2]
        if pl[0] * px + pl[1] * py + pl[2] * pz + pl[3] < 0.0:
            return false
    return true

# La sphère (centre, rayon) est-elle (au moins en partie) à l'intérieur du frustum ?
func sphere_in_frustum(center, radius, planes):
    for pl in planes:
        if plane_distance(pl, center) < 0.0 - radius:
            return false
    return true

# Intersection rayon / AABB (méthode des dalles). Renvoie la distance t >= 0 le long de `direction` (t = 0 si
# l'origine est dans la boîte) ou null si le rayon la manque ou si t dépasse max_t. `direction` n'a pas besoin d'être
# unitaire (t est alors exprimé en longueurs de `direction`).
func aabb_ray_intersect(b, origin, direction, max_t=null):
    tmin := 0.0
    tmax := 10.0 ** 300
    if max_t != null:
        tmax = max_t * 1.0
    i := 0
    while i < 3:
        d := direction[i]
        if math.abs(d) < 0.000000000000001:
            if origin[i] < b[0][i] or origin[i] > b[1][i]:
                return null
        else:
            inv := 1.0 / d
            t1 := (b[0][i] - origin[i]) * inv
            t2 := (b[1][i] - origin[i]) * inv
            if t1 > t2:
                tt := t1
                t1 = t2
                t2 = tt
            if t1 > tmin:
                tmin = t1
            if t2 < tmax:
                tmax = t2
            if tmin > tmax:
                return null
        i += 1
    return tmin
