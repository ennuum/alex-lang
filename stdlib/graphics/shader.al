# ALEX STANDARD LIBRARY — graphics.shader
#
# Shaders en Alex et mathématiques 3D :
#   - vecteurs (list de 3 / 4 flottants) et matrices 4x4 (list de 16 flottants, ligne par ligne, vecteurs en
#     colonne) : identity, mul, translate, scale, rotate_x / y / z, perspective, orthographic, look_at,
#     transform, normal_matrix, dot, cross, normalize ;
#   - Shader : un nuanceur de SOMMETS vertex(attributs, uniforms) -> [position (x, y, z, w), varyings] et un
#     nuanceur de FRAGMENTS fragment(varyings, uniforms) -> [r, g, b, a] (0..1) ou null (fragment rejeté) ;
#     les varyings (list de flottants) sont interpolés en perspective entre les sommets ;
#   - shaders fournis : couleur par sommet, couleur unie, texture (avec teinte), éclairage de Lambert
#     (lumière directionnelle + ambiante, texture facultative), profondeur (gris).
#
#   use graphics.shader as sh
#   mvp := sh.mul(sh.perspective(1.0, 4.0 / 3.0, 0.1, 100.0), sh.look_at([0.0, 0.0, 3.0], [0.0, 0.0, 0.0], [0.0, 1.0, 0.0]))
#   prog := sh.vertex_color()
#   func mon_fragment(v, u):
#       return [v[0], 0.0, 1.0 - v[0], 1.0]
#   perso := sh.Shader(sh.vs_vertex_color, mon_fragment, 4, "perso")

from core use len, to_float
from collections use append
use math

# ---------------------------------------------------------------- vecteurs
func dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

func cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

func length(a):
    return math.sqrt(dot(a, a))

func normalize(a):
    n := length(a)
    if n == 0.0:
        return [0.0, 0.0, 0.0]
    return [a[0] / n, a[1] / n, a[2] / n]

func sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

func add(a, b):
    return [a[0] + b[0], a[1] + b[1], a[2] + b[2]]

func scale3(a, s):
    return [a[0] * s, a[1] * s, a[2] * s]

# ---------------------------------------------------------------- matrices 4x4
func identity():
    return [1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

func mul(a, b):
    out := []
    r := 0
    while r < 4:
        c := 0
        while c < 4:
            append(out, a[r * 4] * b[c] + a[r * 4 + 1] * b[4 + c] + a[r * 4 + 2] * b[8 + c] + a[r * 4 + 3] * b[12 + c])
            c += 1
        r += 1
    return out

# Produit de plusieurs matrices, de gauche à droite.
func chain(ms):
    out := identity()
    for m in ms:
        out = mul(out, m)
    return out

func translate(x, y, z):
    return [1.0, 0.0, 0.0, x, 0.0, 1.0, 0.0, y, 0.0, 0.0, 1.0, z, 0.0, 0.0, 0.0, 1.0]

func scale(x, y, z):
    return [x, 0.0, 0.0, 0.0, 0.0, y, 0.0, 0.0, 0.0, 0.0, z, 0.0, 0.0, 0.0, 0.0, 1.0]

func rotate_x(a):
    c := math.cos(a)
    s := math.sin(a)
    return [1.0, 0.0, 0.0, 0.0, 0.0, c, -s, 0.0, 0.0, s, c, 0.0, 0.0, 0.0, 0.0, 1.0]

func rotate_y(a):
    c := math.cos(a)
    s := math.sin(a)
    return [c, 0.0, s, 0.0, 0.0, 1.0, 0.0, 0.0, -s, 0.0, c, 0.0, 0.0, 0.0, 0.0, 1.0]

func rotate_z(a):
    c := math.cos(a)
    s := math.sin(a)
    return [c, -s, 0.0, 0.0, s, c, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0]

# Perspective (champ vertical fovy en radians, rapport largeur / hauteur, plans proche et lointain),
# convention OpenGL (profondeur -1..1 après division).
func perspective(fovy, aspect, near, far):
    f := 1.0 / math.tan(fovy / 2.0)
    return [f / aspect, 0.0, 0.0, 0.0,
            0.0, f, 0.0, 0.0,
            0.0, 0.0, (far + near) / (near - far), 2.0 * far * near / (near - far),
            0.0, 0.0, -1.0, 0.0]

func orthographic(left, right, bottom, top, near, far):
    return [2.0 / (right - left), 0.0, 0.0, -(right + left) / (right - left),
            0.0, 2.0 / (top - bottom), 0.0, -(top + bottom) / (top - bottom),
            0.0, 0.0, -2.0 / (far - near), -(far + near) / (far - near),
            0.0, 0.0, 0.0, 1.0]

func look_at(eye, target, up):
    f := normalize(sub(target, eye))
    s := normalize(cross(f, up))
    u := cross(s, f)
    return [s[0], s[1], s[2], -dot(s, eye),
            u[0], u[1], u[2], -dot(u, eye),
            -f[0], -f[1], -f[2], dot(f, eye),
            0.0, 0.0, 0.0, 1.0]

# m · [x, y, z, w] (un point de 3 composantes reçoit w = 1).
func transform(m, v):
    w := v[3] if len(v) > 3 else 1.0
    return [m[0] * v[0] + m[1] * v[1] + m[2] * v[2] + m[3] * w,
            m[4] * v[0] + m[5] * v[1] + m[6] * v[2] + m[7] * w,
            m[8] * v[0] + m[9] * v[1] + m[10] * v[2] + m[11] * w,
            m[12] * v[0] + m[13] * v[1] + m[14] * v[2] + m[15] * w]

# Direction transformée par la partie 3x3 (normales d'une matrice sans déformation non uniforme).
func transform_dir(m, v):
    return [m[0] * v[0] + m[1] * v[1] + m[2] * v[2], m[4] * v[0] + m[5] * v[1] + m[6] * v[2], m[8] * v[0] + m[9] * v[1] + m[10] * v[2]]

# ---------------------------------------------------------------- shaders
class Shader:
    # vertex(attributs, uniforms) -> [position4, varyings] ; fragment(varyings, uniforms) -> [r, g, b, a] | null.
    func init(vertex, fragment, varyings, name="shader"):
        self.vertex = vertex
        self.fragment = fragment
        self.varyings = varyings
        self.name = name

func _mvp(u):
    m := u.get("mvp")
    if m == null:
        return identity()
    return m

# Couleur par sommet : attributs [position, color].
func vs_vertex_color(attrs, u):
    return [transform(_mvp(u), attrs[0]), attrs[1]]

func fs_vertex_color(v, u):
    return [v[0], v[1], v[2], v[3]]

func vertex_color():
    return Shader(vs_vertex_color, fs_vertex_color, 4, "couleur par sommet")

# Couleur unie (uniform « color » = [r, g, b, a]) : attributs [position, ...].
func vs_position(attrs, u):
    return [transform(_mvp(u), attrs[0]), []]

func fs_solid(v, u):
    return u.get("color", [1.0, 1.0, 1.0, 1.0])

func solid():
    return Shader(vs_position, fs_solid, 0, "couleur unie")

# Texture (uniform « texture », teinte « tint ») : attributs [position, uv].
func vs_textured(attrs, u):
    return [transform(_mvp(u), attrs[0]), attrs[1]]

func fs_textured(v, u):
    t := u.get("texture")
    c := [v[0], v[1], 1.0, 1.0] if t == null else t.sample(v[0], v[1])
    tint := u.get("tint")
    if tint != null:
        c = [c[0] * tint[0], c[1] * tint[1], c[2] * tint[2], c[3] * tint[3]]
    if c[3] < u.get("alpha_cutoff", 0.0):
        return null
    return c

func textured():
    return Shader(vs_textured, fs_textured, 2, "texture")

# Lambert : attributs [position, normal, uv] ; uniforms mvp, model, light_dir, light_color, ambient,
# diffuse (couleur) et texture (facultative).
func vs_lit(attrs, u):
    model := u.get("model", identity())
    n := normalize(transform_dir(model, attrs[1]))
    return [transform(_mvp(u), attrs[0]), [n[0], n[1], n[2], attrs[2][0], attrs[2][1]]]

func fs_lit(v, u):
    n := normalize([v[0], v[1], v[2]])
    l := normalize(u.get("light_dir", [0.3, 0.5, 1.0]))
    k := dot(n, l)
    if k < 0.0:
        k = 0.0
    lc := u.get("light_color", [1.0, 1.0, 1.0])
    amb := u.get("ambient", 0.15)
    base := u.get("diffuse", [0.8, 0.8, 0.8, 1.0])
    t := u.get("texture")
    if t != null:
        tc := t.sample(v[3], v[4])
        base = [base[0] * tc[0], base[1] * tc[1], base[2] * tc[2], base[3] * tc[3]]
    return [base[0] * (amb + k * lc[0]), base[1] * (amb + k * lc[1]), base[2] * (amb + k * lc[2]), base[3]]

func lit():
    return Shader(vs_lit, fs_lit, 5, "Lambert")

# Profondeur en niveaux de gris (débogage) : la profondeur de la fenêtre est passée en varying.
func vs_depth(attrs, u):
    p := transform(_mvp(u), attrs[0])
    return [p, [p[2] / p[3] * 0.5 + 0.5 if p[3] != 0.0 else 0.0]]

func fs_depth(v, u):
    g := 1.0 - v[0]
    return [g, g, g, 1.0]

func depth():
    return Shader(vs_depth, fs_depth, 1, "profondeur")
