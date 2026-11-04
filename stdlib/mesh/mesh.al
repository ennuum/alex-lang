# ALEX STANDARD LIBRARY — mesh
#
# Maillages triangulés pour la 2D et la 3D : classe `Mesh`, primitives (plan, quad, boîte, sphère UV, icosphère,
# cylindre, cône, capsule, tore, disque), import / export Wavefront OBJ, import glTF 2.0 (.gltf, .glb). ALEX pur.
#
#   use mesh
#   m := mesh.box(2, 1, 1)                          # boîte 2 x 1 x 1 centrée à l'origine
#   m.compute_tangents()
#   print(m.vertex_count(), m.triangle_count())     # 24 12
#   obj := mesh.load_obj("modele.obj")              # Mesh (groupes OBJ dans obj.groups)
#   for g in mesh.load_gltf("scene.glb"):           # un Mesh par primitive, nœuds appliqués
#       print(g.name, g.triangle_count())
#   gpu := m.to_interleaved("pnu")                  # [px, py, pz, nx, ny, nz, u, v, ...] prêt pour un tampon
#
# REPRÉSENTATION
#   positions : liste de Vec3 ; normals : liste de Vec3 (vide ou de même taille) ; uvs : liste de Vec2 (idem) ;
#   tangents : liste de Vec4 (xyz + signe de la bitangente, vide tant que compute_tangents n'est pas appelé) ;
#   indices : liste plate d'entiers, 3 par triangle. Face avant = sens TRIGONOMÉTRIQUE vu de l'extérieur ;
#   les normales pointent vers l'extérieur. Origine des UV en BAS à gauche (v vers le haut, comme OBJ) : l'import
#   glTF inverse donc v (option flip_v). Le module ne dépend d'aucune API graphique.
#   groups : liste de {"name", "material", "start", "count"} (plages dans indices), remplie par l'import OBJ.
#
# Erreurs : ValueError (données invalides), TypeError, ParseError (OBJ / glTF mal formé), IoError (fichier).

use math
use math3d
use string
use json
use crypto
use file
from core use len, to_int, to_float, type
from collections use append, clear, contains_key, keys, remove

const VERSION := "1.0.0"

# =============================================================================
# Outils internes
# =============================================================================

func _need(cond, message):
    if not cond:
        raise("ValueError", "mesh : " + message)

func _get(d, k, default):
    if k in d:
        return d[k]
    return default

func _vec_copy(v):
    r := []
    for x in v:
        append(r, x)
    return r

# =============================================================================
# Classe Mesh
# =============================================================================

class Mesh:
    func init(name=""):
        self.name = name
        self.positions = []
        self.normals = []
        self.uvs = []
        self.tangents = []
        self.indices = []
        self.groups = []
        self.material = null

    func vertex_count():
        return len(self.positions)

    func triangle_count():
        return len(self.indices) // 3

    func has_normals():
        return len(self.normals) > 0 and len(self.normals) == len(self.positions)

    func has_uvs():
        return len(self.uvs) > 0 and len(self.uvs) == len(self.positions)

    func has_tangents():
        return len(self.tangents) > 0 and len(self.tangents) == len(self.positions)

    # Ajoute un sommet ; normale et uv facultatifs (cohérence : tous ou aucun). Renvoie son indice.
    func add_vertex(position, normal=null, uv=null):
        append(self.positions, [position[0] * 1.0, position[1] * 1.0, position[2] * 1.0])
        if normal != null:
            append(self.normals, [normal[0] * 1.0, normal[1] * 1.0, normal[2] * 1.0])
        if uv != null:
            append(self.uvs, [uv[0] * 1.0, uv[1] * 1.0])
        return len(self.positions) - 1

    func add_triangle(a, b, c):
        append(self.indices, a)
        append(self.indices, b)
        append(self.indices, c)

    # Quadrilatère a, b, c, d (sens trigonométrique) en deux triangles (a, b, c) et (a, c, d).
    func add_quad(a, b, c, d):
        self.add_triangle(a, b, c)
        self.add_triangle(a, c, d)

    # Positions du triangle numéro i : [a, b, c].
    func triangle(i):
        return [self.positions[self.indices[i * 3]], self.positions[self.indices[i * 3 + 1]], self.positions[self.indices[i * 3 + 2]]]

    # Normale géométrique (unitaire) du triangle i.
    func triangle_normal(i):
        t := self.triangle(i)
        return math3d.vec3_normalize(math3d.vec3_cross(math3d.vec3_sub(t[1], t[0]), math3d.vec3_sub(t[2], t[0])))

    func triangle_area(i):
        t := self.triangle(i)
        return 0.5 * math3d.vec3_length(math3d.vec3_cross(math3d.vec3_sub(t[1], t[0]), math3d.vec3_sub(t[2], t[0])))

    func surface_area():
        s := 0.0
        i := 0
        n := self.triangle_count()
        while i < n:
            s = s + self.triangle_area(i)
            i += 1
        return s

    # Volume signé par somme de tétraèdres (exact pour un maillage fermé ; positif si les faces sont tournées
    # vers l'extérieur).
    func volume():
        v := 0.0
        i := 0
        n := self.triangle_count()
        while i < n:
            t := self.triangle(i)
            v = v + math3d.vec3_dot(t[0], math3d.vec3_cross(t[1], t[2])) / 6.0
            i += 1
        return v

    # Boîte englobante alignée [min, max] ; ValueError si le maillage n'a aucun sommet.
    func bounds():
        return math3d.aabb_from_points(self.positions)

    # Sphère englobante [centre, rayon] (centre de la boîte englobante : simple et rapide, pas minimale).
    func bounding_sphere():
        b := self.bounds()
        c := math3d.aabb_center(b)
        r := 0.0
        for p in self.positions:
            d := math3d.vec3_distance_sq(p, c)
            if d > r:
                r = d
        return [c, math.sqrt(r)]

    # Normales lisses : somme des normales de faces pondérées par l'aire (les sommets partagés sont lissés).
    func compute_normals():
        acc := []
        for p in self.positions:
            append(acc, [0.0, 0.0, 0.0])
        i := 0
        n := self.triangle_count()
        while i < n:
            ia := self.indices[i * 3]
            ib := self.indices[i * 3 + 1]
            ic := self.indices[i * 3 + 2]
            pa := self.positions[ia]
            fn := math3d.vec3_cross(math3d.vec3_sub(self.positions[ib], pa), math3d.vec3_sub(self.positions[ic], pa))
            acc[ia] = math3d.vec3_add(acc[ia], fn)
            acc[ib] = math3d.vec3_add(acc[ib], fn)
            acc[ic] = math3d.vec3_add(acc[ic], fn)
            i += 1
        self.normals = []
        for a in acc:
            l := math3d.vec3_length(a)
            if l < 0.000000000001:
                append(self.normals, [0.0, 1.0, 0.0])
            else:
                append(self.normals, [a[0] / l, a[1] / l, a[2] / l])

    # Ombrage à facettes : duplique les sommets pour que chaque triangle ait ses propres normales.
    func make_flat():
        pos := []
        nor := []
        uv := []
        idx := []
        has_uv := self.has_uvs()
        i := 0
        n := self.triangle_count()
        while i < n:
            fn := self.triangle_normal(i)
            k := 0
            while k < 3:
                v := self.indices[i * 3 + k]
                append(idx, len(pos))
                append(pos, self.positions[v])
                append(nor, fn)
                if has_uv:
                    append(uv, self.uvs[v])
                k += 1
            i += 1
        self.positions = pos
        self.normals = nor
        self.uvs = uv
        self.indices = idx
        self.tangents = []

    # Tangentes (méthode de Lengyel) : demande normales et uvs. Remplit tangents avec des Vec4 (w = ±1).
    func compute_tangents():
        if not self.has_normals() or not self.has_uvs():
            raise("ValueError", "mesh.compute_tangents : normales et uvs requis")
        nv := len(self.positions)
        tan1 := []
        tan2 := []
        for p in self.positions:
            append(tan1, [0.0, 0.0, 0.0])
            append(tan2, [0.0, 0.0, 0.0])
        i := 0
        n := self.triangle_count()
        while i < n:
            ia := self.indices[i * 3]
            ib := self.indices[i * 3 + 1]
            ic := self.indices[i * 3 + 2]
            e1 := math3d.vec3_sub(self.positions[ib], self.positions[ia])
            e2 := math3d.vec3_sub(self.positions[ic], self.positions[ia])
            du1 := self.uvs[ib][0] - self.uvs[ia][0]
            dv1 := self.uvs[ib][1] - self.uvs[ia][1]
            du2 := self.uvs[ic][0] - self.uvs[ia][0]
            dv2 := self.uvs[ic][1] - self.uvs[ia][1]
            det := du1 * dv2 - du2 * dv1
            if math.abs(det) > 0.000000000001:
                r := 1.0 / det
                sdir := [(e1[0] * dv2 - e2[0] * dv1) * r, (e1[1] * dv2 - e2[1] * dv1) * r, (e1[2] * dv2 - e2[2] * dv1) * r]
                tdir := [(e2[0] * du1 - e1[0] * du2) * r, (e2[1] * du1 - e1[1] * du2) * r, (e2[2] * du1 - e1[2] * du2) * r]
                for v in [ia, ib, ic]:
                    tan1[v] = math3d.vec3_add(tan1[v], sdir)
                    tan2[v] = math3d.vec3_add(tan2[v], tdir)
            i += 1
        self.tangents = []
        v := 0
        while v < nv:
            nrm := self.normals[v]
            t := tan1[v]
            # Gram-Schmidt
            tt := math3d.vec3_normalize(math3d.vec3_sub(t, math3d.vec3_scale(nrm, math3d.vec3_dot(nrm, t))))
            if math3d.vec3_length_sq(tt) < 0.5:
                basis := math3d.vec3_orthonormal_basis(nrm)
                tt = basis[0]
            w := 1.0
            if math3d.vec3_dot(math3d.vec3_cross(nrm, tt), tan2[v]) < 0.0:
                w = -1.0
            append(self.tangents, [tt[0], tt[1], tt[2], w])
            v += 1

    # Inverse le sens des faces (échange deux sommets de chaque triangle) ; les normales ne changent pas.
    func flip_winding():
        i := 0
        n := self.triangle_count()
        while i < n:
            t := self.indices[i * 3 + 1]
            self.indices[i * 3 + 1] = self.indices[i * 3 + 2]
            self.indices[i * 3 + 2] = t
            i += 1

    # Retourne le maillage « à l'envers » : faces ET normales inversées (pour voir l'intérieur d'une pièce).
    func invert():
        self.flip_winding()
        k := 0
        while k < len(self.normals):
            self.normals[k] = math3d.vec3_neg(self.normals[k])
            k += 1

    func copy():
        m := Mesh(self.name)
        for p in self.positions:
            append(m.positions, _vec_copy(p))
        for p in self.normals:
            append(m.normals, _vec_copy(p))
        for p in self.uvs:
            append(m.uvs, _vec_copy(p))
        for p in self.tangents:
            append(m.tangents, _vec_copy(p))
        for i in self.indices:
            append(m.indices, i)
        for g in self.groups:
            append(m.groups, {"name": g["name"], "material": g["material"], "start": g["start"], "count": g["count"]})
        m.material = self.material
        return m

    # Nouvelle copie transformée par une Mat4 affine (positions ; normales par la matrice des normales ; tangentes).
    # Si le déterminant est négatif (miroir), le sens des faces est rétabli.
    func transformed(matrix):
        m := self.copy()
        m.transform(matrix)
        return m

    # Transforme le maillage EN PLACE.
    func transform(matrix):
        k := 0
        while k < len(self.positions):
            self.positions[k] = math3d.mat4_transform_point(matrix, self.positions[k])
            k += 1
        if len(self.normals) > 0 or len(self.tangents) > 0:
            nm := math3d.mat3_normal_matrix(matrix)
            rot := math3d.mat3_from_mat4(matrix)
            k = 0
            while k < len(self.normals):
                self.normals[k] = math3d.vec3_normalize(math3d.mat3_mul_vec3(nm, self.normals[k]))
                k += 1
            k = 0
            while k < len(self.tangents):
                t := self.tangents[k]
                tv := math3d.vec3_normalize(math3d.mat3_mul_vec3(rot, [t[0], t[1], t[2]]))
                self.tangents[k] = [tv[0], tv[1], tv[2], t[3]]
                k += 1
        if math3d.mat4_determinant(matrix) < 0.0:
            self.flip_winding()

    # Ajoute une copie de other (éventuellement transformée par une Mat4) à ce maillage. Les attributs absents d'un
    # des deux maillages sont complétés (normale +Y, uv (0, 0)) pour que les tableaux restent alignés.
    func append_mesh(other, matrix=null):
        src := other
        if matrix != null:
            src = other.transformed(matrix)
        base := len(self.positions)
        want_n := self.has_normals() or (len(self.positions) == 0 and src.has_normals())
        want_uv := self.has_uvs() or (len(self.positions) == 0 and src.has_uvs())
        if len(self.positions) > 0 and (self.has_normals() != src.has_normals()):
            want_n = true
        if len(self.positions) > 0 and (self.has_uvs() != src.has_uvs()):
            want_uv = true
        if want_n and len(self.positions) > 0 and not self.has_normals():
            for p in self.positions:
                append(self.normals, [0.0, 1.0, 0.0])
        if want_uv and len(self.positions) > 0 and not self.has_uvs():
            for p in self.positions:
                append(self.uvs, [0.0, 0.0])
        k := 0
        while k < len(src.positions):
            append(self.positions, _vec_copy(src.positions[k]))
            if want_n:
                if src.has_normals():
                    append(self.normals, _vec_copy(src.normals[k]))
                else:
                    append(self.normals, [0.0, 1.0, 0.0])
            if want_uv:
                if src.has_uvs():
                    append(self.uvs, _vec_copy(src.uvs[k]))
                else:
                    append(self.uvs, [0.0, 0.0])
            k += 1
        start := len(self.indices)
        for i in src.indices:
            append(self.indices, i + base)
        for g in src.groups:
            append(self.groups, {"name": g["name"], "material": g["material"], "start": g["start"] + start, "count": g["count"]})
        self.tangents = []

    # Nouveau maillage = union de self et de other.
    func merged(other, matrix=null):
        m := self.copy()
        m.append_mesh(other, matrix)
        return m

    # Fusionne les sommets identiques (positions à eps près, mêmes normales et uvs à eps près). Renvoie le nombre
    # de sommets supprimés. Les tangentes sont recalculées si elles existaient.
    func weld(eps=0.000001):
        had_tangents := self.has_tangents()
        seen := {}
        remap := []
        pos := []
        nor := []
        uv := []
        hn := self.has_normals()
        hu := self.has_uvs()
        k := 0
        while k < len(self.positions):
            p := self.positions[k]
            key := f"{math.floor(p[0] / eps + 0.5)},{math.floor(p[1] / eps + 0.5)},{math.floor(p[2] / eps + 0.5)}"
            if hn:
                q := self.normals[k]
                key = key + f"|{math.floor(q[0] / eps + 0.5)},{math.floor(q[1] / eps + 0.5)},{math.floor(q[2] / eps + 0.5)}"
            if hu:
                q := self.uvs[k]
                key = key + f"|{math.floor(q[0] / eps + 0.5)},{math.floor(q[1] / eps + 0.5)}"
            if key in seen:
                append(remap, seen[key])
            else:
                seen[key] = len(pos)
                append(remap, len(pos))
                append(pos, p)
                if hn:
                    append(nor, self.normals[k])
                if hu:
                    append(uv, self.uvs[k])
            k += 1
        removed := len(self.positions) - len(pos)
        k = 0
        while k < len(self.indices):
            self.indices[k] = remap[self.indices[k]]
            k += 1
        self.positions = pos
        self.normals = nor
        self.uvs = uv
        self.tangents = []
        if had_tangents and hn and hu:
            self.compute_tangents()
        return removed

    # Centre la boîte englobante sur l'origine ; renvoie le décalage appliqué (Vec3).
    func recenter():
        c := math3d.aabb_center(self.bounds())
        k := 0
        while k < len(self.positions):
            self.positions[k] = math3d.vec3_sub(self.positions[k], c)
            k += 1
        return c

    # Multiplie les uvs (répétition de texture).
    func scale_uvs(su, sv):
        k := 0
        while k < len(self.uvs):
            self.uvs[k] = [self.uvs[k][0] * su, self.uvs[k][1] * sv]
            k += 1

    # Vérifie la cohérence : tailles des tableaux alignées, indices dans les bornes, multiple de 3.
    # Lève ValueError sinon ; renvoie true.
    func validate():
        n := len(self.positions)
        if len(self.indices) % 3 != 0:
            raise("ValueError", "mesh.validate : le nombre d'indices n'est pas un multiple de 3")
        if len(self.normals) != 0 and len(self.normals) != n:
            raise("ValueError", "mesh.validate : normales désalignées")
        if len(self.uvs) != 0 and len(self.uvs) != n:
            raise("ValueError", "mesh.validate : uvs désalignés")
        if len(self.tangents) != 0 and len(self.tangents) != n:
            raise("ValueError", "mesh.validate : tangentes désalignées")
        for i in self.indices:
            if i < 0 or i >= n:
                raise("ValueError", f"mesh.validate : indice {i} hors bornes (0..{n - 1})")
        return true

    # Tableau plat de flottants prêt à envoyer à un tampon de sommets. layout : suite de lettres
    # p = position (3), n = normale (3), u = uv (2), t = tangente (4). Un attribut demandé mais absent est
    # complété par zéros (normale (0, 1, 0)).
    func to_interleaved(layout="pnu"):
        out := []
        k := 0
        while k < len(self.positions):
            for ch in layout:
                c := str(ch)
                if c == "p":
                    p := self.positions[k]
                    append(out, p[0])
                    append(out, p[1])
                    append(out, p[2])
                elif c == "n":
                    if self.has_normals():
                        q := self.normals[k]
                        append(out, q[0])
                        append(out, q[1])
                        append(out, q[2])
                    else:
                        append(out, 0.0)
                        append(out, 1.0)
                        append(out, 0.0)
                elif c == "u":
                    if self.has_uvs():
                        append(out, self.uvs[k][0])
                        append(out, self.uvs[k][1])
                    else:
                        append(out, 0.0)
                        append(out, 0.0)
                elif c == "t":
                    if self.has_tangents():
                        t := self.tangents[k]
                        append(out, t[0])
                        append(out, t[1])
                        append(out, t[2])
                        append(out, t[3])
                    else:
                        append(out, 1.0)
                        append(out, 0.0)
                        append(out, 0.0)
                        append(out, 1.0)
                else:
                    raise("ValueError", "mesh.to_interleaved : lettre de disposition inconnue '" + c + "' (p n u t)")
            k += 1
        return out

    # Un maillage par groupe OBJ (ou le maillage entier s'il n'y a pas de groupes). Les sommets sont recopiés.
    func split_groups():
        if len(self.groups) == 0:
            return [self.copy()]
        out := []
        for g in self.groups:
            m := Mesh(g["name"])
            m.material = g["material"]
            remap := {}
            hn := self.has_normals()
            hu := self.has_uvs()
            k := g["start"]
            while k < g["start"] + g["count"]:
                v := self.indices[k]
                if not (v in remap):
                    remap[v] = len(m.positions)
                    m.add_vertex(self.positions[v], self.normals[v] if hn else null, self.uvs[v] if hu else null)
                append(m.indices, remap[v])
                k += 1
            append(out, m)
        return out

    func to_string():
        return f"Mesh({self.name}: {self.vertex_count()} sommets, {self.triangle_count()} triangles)"

# =============================================================================
# Primitives
# =============================================================================

# Quadrilatère dans le plan XY, face +Z, centré à l'origine : sprites, écrans, UI 3D.
func quad(width=1.0, height=1.0):
    m := Mesh("quad")
    hx := width * 0.5
    hy := height * 0.5
    a := m.add_vertex([0.0 - hx, 0.0 - hy, 0.0], [0.0, 0.0, 1.0], [0.0, 0.0])
    b := m.add_vertex([hx, 0.0 - hy, 0.0], [0.0, 0.0, 1.0], [1.0, 0.0])
    c := m.add_vertex([hx, hy, 0.0], [0.0, 0.0, 1.0], [1.0, 1.0])
    d := m.add_vertex([0.0 - hx, hy, 0.0], [0.0, 0.0, 1.0], [0.0, 1.0])
    m.add_quad(a, b, c, d)
    return m

# Plan horizontal XZ, face +Y, subdivisé en segments_x par segments_z cases, centré à l'origine (sol, terrain).
func plane(width=1.0, depth=1.0, segments_x=1, segments_z=1):
    _need(segments_x >= 1 and segments_z >= 1, "plane : au moins 1 segment par axe")
    m := Mesh("plane")
    iz := 0
    while iz <= segments_z:
        ix := 0
        while ix <= segments_x:
            u := ix / segments_x
            v := iz / segments_z
            m.add_vertex([(u - 0.5) * width, 0.0, (v - 0.5) * depth], [0.0, 1.0, 0.0], [u, 1.0 - v])
            ix += 1
        iz += 1
    iz = 0
    while iz < segments_z:
        ix := 0
        while ix < segments_x:
            a := iz * (segments_x + 1) + ix
            b := a + 1
            c := a + segments_x + 1
            d := c + 1
            m.add_triangle(a, c, b)
            m.add_triangle(b, c, d)
            ix += 1
        iz += 1
    return m

# Disque dans le plan XZ, face +Y.
func disc(radius=1.0, segments=32):
    _need(segments >= 3, "disc : au moins 3 segments")
    m := Mesh("disc")
    m.add_vertex([0.0, 0.0, 0.0], [0.0, 1.0, 0.0], [0.5, 0.5])
    s := 0
    while s <= segments:
        phi := math3d.TAU * s / segments
        m.add_vertex([math.cos(phi) * radius, 0.0, 0.0 - math.sin(phi) * radius], [0.0, 1.0, 0.0], [0.5 + 0.5 * math.cos(phi), 0.5 + 0.5 * math.sin(phi)])
        s += 1
    s = 0
    while s < segments:
        m.add_triangle(0, s + 1, s + 2)
        s += 1
    return m

# Boîte centrée à l'origine ; 24 sommets (normales par face), uvs 0..1 sur chaque face.
func box(width=1.0, height=1.0, depth=1.0):
    m := Mesh("box")
    hx := width * 0.5
    hy := height * 0.5
    hz := depth * 0.5
    faces := [
        [[0.0, 0.0, 1.0], [0.0 - hx, 0.0 - hy, hz], [hx, 0.0 - hy, hz], [hx, hy, hz], [0.0 - hx, hy, hz]],
        [[0.0, 0.0, -1.0], [hx, 0.0 - hy, 0.0 - hz], [0.0 - hx, 0.0 - hy, 0.0 - hz], [0.0 - hx, hy, 0.0 - hz], [hx, hy, 0.0 - hz]],
        [[1.0, 0.0, 0.0], [hx, 0.0 - hy, hz], [hx, 0.0 - hy, 0.0 - hz], [hx, hy, 0.0 - hz], [hx, hy, hz]],
        [[-1.0, 0.0, 0.0], [0.0 - hx, 0.0 - hy, 0.0 - hz], [0.0 - hx, 0.0 - hy, hz], [0.0 - hx, hy, hz], [0.0 - hx, hy, 0.0 - hz]],
        [[0.0, 1.0, 0.0], [0.0 - hx, hy, hz], [hx, hy, hz], [hx, hy, 0.0 - hz], [0.0 - hx, hy, 0.0 - hz]],
        [[0.0, -1.0, 0.0], [0.0 - hx, 0.0 - hy, 0.0 - hz], [hx, 0.0 - hy, 0.0 - hz], [hx, 0.0 - hy, hz], [0.0 - hx, 0.0 - hy, hz]]]
    uvs := [[0.0, 0.0], [1.0, 0.0], [1.0, 1.0], [0.0, 1.0]]
    for f in faces:
        a := m.add_vertex(f[1], f[0], uvs[0])
        b := m.add_vertex(f[2], f[0], uvs[1])
        c := m.add_vertex(f[3], f[0], uvs[2])
        d := m.add_vertex(f[4], f[0], uvs[3])
        m.add_quad(a, b, c, d)
    return m

# Sphère UV (pôles sur ±Y). segments = méridiens, rings = parallèles.
func sphere(radius=0.5, segments=24, rings=16):
    _need(segments >= 3 and rings >= 2, "sphere : segments >= 3 et rings >= 2")
    m := Mesh("sphere")
    r := 0
    while r <= rings:
        theta := math3d.PI * r / rings
        s := 0
        while s <= segments:
            phi := math3d.TAU * s / segments
            n := [math.sin(theta) * math.cos(phi), math.cos(theta), 0.0 - math.sin(theta) * math.sin(phi)]
            m.add_vertex(math3d.vec3_scale(n, radius), n, [s / segments, 1.0 - r / rings])
            s += 1
        r += 1
    r = 0
    while r < rings:
        s := 0
        while s < segments:
            a := r * (segments + 1) + s
            b := a + segments + 1
            if r != 0:
                m.add_triangle(a, b, a + 1)
            if r != rings - 1:
                m.add_triangle(a + 1, b, b + 1)
            s += 1
        r += 1
    return m

# Icosphère (triangles quasi équilatéraux) : subdivisions 0 = 12 sommets, chaque niveau multiplie les faces par 4.
func icosphere(radius=0.5, subdivisions=2):
    _need(subdivisions >= 0 and subdivisions <= 6, "icosphere : subdivisions entre 0 et 6")
    t := (1.0 + math.sqrt(5.0)) / 2.0
    raw := [[-1.0, t, 0.0], [1.0, t, 0.0], [-1.0, 0.0 - t, 0.0], [1.0, 0.0 - t, 0.0], [0.0, -1.0, t], [0.0, 1.0, t], [0.0, -1.0, 0.0 - t], [0.0, 1.0, 0.0 - t], [t, 0.0, -1.0], [t, 0.0, 1.0], [0.0 - t, 0.0, -1.0], [0.0 - t, 0.0, 1.0]]
    pts := []
    for p in raw:
        append(pts, math3d.vec3_normalize(p))
    tris := [[0, 11, 5], [0, 5, 1], [0, 1, 7], [0, 7, 10], [0, 10, 11], [1, 5, 9], [5, 11, 4], [11, 10, 2], [10, 7, 6], [7, 1, 8], [3, 9, 4], [3, 4, 2], [3, 2, 6], [3, 6, 8], [3, 8, 9], [4, 9, 5], [2, 4, 11], [6, 2, 10], [8, 6, 7], [9, 8, 1]]
    level := 0
    while level < subdivisions:
        cache := {}
        nt := []
        for tri in tris:
            mid := []
            e := 0
            while e < 3:
                i := tri[e]
                j := tri[(e + 1) % 3]
                lo := i
                hi := j
                if lo > hi:
                    lo = j
                    hi = i
                key := f"{lo},{hi}"
                if not (key in cache):
                    cache[key] = len(pts)
                    append(pts, math3d.vec3_normalize(math3d.vec3_add(pts[i], pts[j])))
                append(mid, cache[key])
                e += 1
            append(nt, [tri[0], mid[0], mid[2]])
            append(nt, [tri[1], mid[1], mid[0]])
            append(nt, [tri[2], mid[2], mid[1]])
            append(nt, [mid[0], mid[1], mid[2]])
        tris = nt
        level += 1
    m := Mesh("icosphere")
    for p in pts:
        m.add_vertex(math3d.vec3_scale(p, radius), p, [0.5 + math.atan2(p[2], p[0]) / math3d.TAU, 0.5 + math.asin(math3d.clamp(p[1], -1.0, 1.0)) / math3d.PI])
    for tri in tris:
        m.add_triangle(tri[0], tri[1], tri[2])
    return m

# Cylindre d'axe Y centré à l'origine. caps = true ajoute les deux disques.
func cylinder(radius=0.5, height=1.0, segments=24, caps=true):
    _need(segments >= 3, "cylinder : au moins 3 segments")
    m := Mesh("cylinder")
    hy := height * 0.5
    s := 0
    while s <= segments:
        phi := math3d.TAU * s / segments
        c := math.cos(phi)
        sn := 0.0 - math.sin(phi)
        m.add_vertex([c * radius, 0.0 - hy, sn * radius], [c, 0.0, sn], [s / segments, 0.0])
        m.add_vertex([c * radius, hy, sn * radius], [c, 0.0, sn], [s / segments, 1.0])
        s += 1
    s = 0
    while s < segments:
        a := s * 2
        m.add_triangle(a, a + 2, a + 1)
        m.add_triangle(a + 2, a + 3, a + 1)
        s += 1
    if caps:
        for side in [1.0, -1.0]:
            center := m.add_vertex([0.0, hy * side, 0.0], [0.0, side, 0.0], [0.5, 0.5])
            first := len(m.positions)
            s = 0
            while s <= segments:
                phi := math3d.TAU * s / segments
                m.add_vertex([math.cos(phi) * radius, hy * side, 0.0 - math.sin(phi) * radius], [0.0, side, 0.0], [0.5 + 0.5 * math.cos(phi), 0.5 + 0.5 * math.sin(phi) * side])
                s += 1
            s = 0
            while s < segments:
                if side > 0.0:
                    m.add_triangle(center, first + s, first + s + 1)
                else:
                    m.add_triangle(center, first + s + 1, first + s)
                s += 1
    return m

# Cône d'axe Y (base en bas, pointe en haut), centré à l'origine.
func cone(radius=0.5, height=1.0, segments=24, cap=true):
    _need(segments >= 3, "cone : au moins 3 segments")
    m := Mesh("cone")
    hy := height * 0.5
    s := 0
    while s <= segments:
        phi := math3d.TAU * s / segments
        c := math.cos(phi)
        sn := 0.0 - math.sin(phi)
        m.add_vertex([c * radius, 0.0 - hy, sn * radius], math3d.vec3_normalize([c * height, radius, sn * height]), [s / segments, 0.0])
        # pointe : une copie par segment, avec la normale de la médiatrice du segment
        mid := math3d.TAU * (s + 0.5) / segments
        m.add_vertex([0.0, hy, 0.0], math3d.vec3_normalize([math.cos(mid) * height, radius, 0.0 - math.sin(mid) * height]), [(s + 0.5) / segments, 1.0])
        s += 1
    s = 0
    while s < segments:
        a := s * 2
        m.add_triangle(a, a + 2, a + 1)
        s += 1
    if cap:
        center := m.add_vertex([0.0, 0.0 - hy, 0.0], [0.0, -1.0, 0.0], [0.5, 0.5])
        first := len(m.positions)
        s = 0
        while s <= segments:
            phi := math3d.TAU * s / segments
            m.add_vertex([math.cos(phi) * radius, 0.0 - hy, 0.0 - math.sin(phi) * radius], [0.0, -1.0, 0.0], [0.5 + 0.5 * math.cos(phi), 0.5 - 0.5 * math.sin(phi)])
            s += 1
        s = 0
        while s < segments:
            m.add_triangle(center, first + s + 1, first + s)
            s += 1
    return m

# Capsule d'axe Y : `height` est la longueur de la partie cylindrique (hors hémisphères). rings = parallèles par hémisphère.
func capsule(radius=0.5, height=1.0, segments=24, rings=8):
    _need(segments >= 3 and rings >= 1, "capsule : segments >= 3 et rings >= 1")
    m := Mesh("capsule")
    hy := height * 0.5
    rows := []
    i := 0
    while i <= rings:
        theta := math3d.HALF_PI * i / rings
        append(rows, [hy + radius * math.cos(theta), radius * math.sin(theta), math.cos(theta), math.sin(theta)])
        i += 1
    i = 0
    while i <= rings:
        theta := math3d.HALF_PI + math3d.HALF_PI * i / rings
        append(rows, [0.0 - hy + radius * math.cos(theta), radius * math.sin(theta), math.cos(theta), math.sin(theta)])
        i += 1
    total := len(rows)
    r := 0
    while r < total:
        row := rows[r]
        s := 0
        while s <= segments:
            phi := math3d.TAU * s / segments
            c := math.cos(phi)
            sn := 0.0 - math.sin(phi)
            m.add_vertex([c * row[1], row[0], sn * row[1]], [c * row[3], row[2], sn * row[3]], [s / segments, 1.0 - r / (total - 1)])
            s += 1
        r += 1
    r = 0
    while r < total - 1:
        s := 0
        while s < segments:
            a := r * (segments + 1) + s
            b := a + segments + 1
            # aux pôles, un des deux triangles est dégénéré : on le saute
            if rows[r][1] > 0.0000001:
                m.add_triangle(a, b, a + 1)
            if rows[r + 1][1] > 0.0000001:
                m.add_triangle(a + 1, b, b + 1)
            s += 1
        r += 1
    return m

# Tore d'axe Y : major_radius = rayon du cercle central, minor_radius = rayon du tube.
func torus(major_radius=0.5, minor_radius=0.2, segments=32, sides=16):
    _need(segments >= 3 and sides >= 3, "torus : segments >= 3 et sides >= 3")
    m := Mesh("torus")
    i := 0
    while i <= segments:
        phi := math3d.TAU * i / segments
        c := math.cos(phi)
        sn := 0.0 - math.sin(phi)
        j := 0
        while j <= sides:
            theta := math3d.TAU * j / sides
            ct := math.cos(theta)
            st := math.sin(theta)
            n := [c * ct, st, sn * ct]
            m.add_vertex([c * (major_radius + minor_radius * ct), minor_radius * st, sn * (major_radius + minor_radius * ct)], n, [i / segments, j / sides])
            j += 1
        i += 1
    i = 0
    while i < segments:
        j := 0
        while j < sides:
            a := i * (sides + 1) + j
            b := a + sides + 1
            m.add_triangle(a, b, a + 1)
            m.add_triangle(a + 1, b, b + 1)
            j += 1
        i += 1
    return m

# =============================================================================
# Wavefront OBJ
# =============================================================================

func _words(line):
    s := string.replace(string.replace(line, "\t", " "), "\r", "")
    out := []
    for w in string.split(s, " "):
        if len(w) > 0:
            append(out, w)
    return out

func _obj_index(token, count, line_no):
    n := to_int(token)
    r := 0
    if n > 0:
        r = n - 1
    elif n < 0:
        r = count + n
    else:
        raise("ParseError", f"obj ligne {line_no} : indice 0 invalide")
    if r < 0 or r >= count:
        raise("ParseError", f"obj ligne {line_no} : indice {n} hors bornes")
    return r

# Lit un texte OBJ. Gère v / vt / vn / f (polygones triangulés en éventail, indices négatifs relatifs), o / g
# (groupes), usemtl. Les lignes l, p, s, mtllib et les commentaires sont ignorés. Sans normales dans le fichier,
# des normales lisses sont calculées (compute_normals=true).
func parse_obj(text, compute_normals=true):
    vs := []
    vts := []
    vns := []
    m := Mesh("obj")
    cache := {}
    cur_name := "default"
    cur_mat := null
    group := null
    line_no := 0
    for raw in string.split(text, "\n"):
        line_no += 1
        line := raw
        h := string.find(line, "#")
        if h >= 0:
            line = string.slice(line, 0, h)
        w := _words(line)
        if len(w) == 0:
            continue
        kind := w[0]
        if kind == "v":
            if len(w) < 4:
                raise("ParseError", f"obj ligne {line_no} : sommet incomplet")
            append(vs, [to_float(w[1]), to_float(w[2]), to_float(w[3])])
        elif kind == "vt":
            if len(w) < 3:
                raise("ParseError", f"obj ligne {line_no} : uv incomplet")
            append(vts, [to_float(w[1]), to_float(w[2])])
        elif kind == "vn":
            if len(w) < 4:
                raise("ParseError", f"obj ligne {line_no} : normale incomplète")
            append(vns, [to_float(w[1]), to_float(w[2]), to_float(w[3])])
        elif kind == "o" or kind == "g":
            if len(w) > 1:
                cur_name = w[1]
            group = null
        elif kind == "usemtl":
            if len(w) > 1:
                cur_mat = w[1]
            group = null
        elif kind == "f":
            if len(w) < 4:
                raise("ParseError", f"obj ligne {line_no} : face de moins de 3 sommets")
            corners := []
            k := 1
            while k < len(w):
                parts := string.split(w[k], "/")
                vi := _obj_index(parts[0], len(vs), line_no)
                ti := -1
                ni := -1
                if len(parts) > 1 and len(parts[1]) > 0:
                    ti = _obj_index(parts[1], len(vts), line_no)
                if len(parts) > 2 and len(parts[2]) > 0:
                    ni = _obj_index(parts[2], len(vns), line_no)
                key := f"{vi}/{ti}/{ni}"
                if not (key in cache):
                    cache[key] = len(m.positions)
                    append(m.positions, vs[vi])
                    if ti >= 0:
                        append(m.uvs, vts[ti])
                    if ni >= 0:
                        append(m.normals, vns[ni])
                append(corners, cache[key])
                k += 1
            if group == null:
                group = {"name": cur_name, "material": cur_mat, "start": len(m.indices), "count": 0}
                append(m.groups, group)
            k = 1
            while k + 1 < len(corners):
                m.add_triangle(corners[0], corners[k], corners[k + 1])
                k += 1
            group["count"] = len(m.indices) - group["start"]
    # Attributs partiels (certains sommets sans uv / normale) : on complète pour garder l'alignement.
    if len(m.uvs) != len(m.positions):
        m.uvs = []
    if len(m.normals) != len(m.positions):
        m.normals = []
        if compute_normals:
            m.compute_normals()
    if len(m.groups) == 1:
        m.material = m.groups[0]["material"]
    return m

func load_obj(path, compute_normals=true):
    m := parse_obj(file.read(path), compute_normals)
    return m

# Écrit un maillage au format OBJ (indices 1-based, f v/vt/vn selon les attributs présents).
func to_obj(m, name=null):
    lines := ["# exporté par ALEX mesh"]
    if name != null:
        append(lines, "o " + name)
    elif m.name != "":
        append(lines, "o " + m.name)
    for p in m.positions:
        append(lines, f"v {p[0]} {p[1]} {p[2]}")
    hu := m.has_uvs()
    hn := m.has_normals()
    if hu:
        for t in m.uvs:
            append(lines, f"vt {t[0]} {t[1]}")
    if hn:
        for n in m.normals:
            append(lines, f"vn {n[0]} {n[1]} {n[2]}")
    i := 0
    while i < len(m.indices):
        parts := []
        k := 0
        while k < 3:
            v := m.indices[i + k] + 1
            if hu and hn:
                append(parts, f"{v}/{v}/{v}")
            elif hu:
                append(parts, f"{v}/{v}")
            elif hn:
                append(parts, f"{v}//{v}")
            else:
                append(parts, f"{v}")
            k += 1
        append(lines, "f " + string.join(" ", parts))
        i += 3
    return string.join("\n", lines) + "\n"

func save_obj(m, path):
    file.write(path, to_obj(m))

# =============================================================================
# glTF 2.0 / GLB
# =============================================================================

func _u32(data, o):
    return data[o] | (data[o + 1] << 8) | (data[o + 2] << 16) | (data[o + 3] << 24)

func _i32(data, o):
    v := _u32(data, o)
    if v >= 2147483648:
        return v - 4294967296
    return v

func _f32(data, o):
    bits := _u32(data, o)
    sign := 1.0
    if (bits >> 31) & 1 == 1:
        sign = -1.0
    ex := (bits >> 23) & 255
    mant := bits & 8388607
    if ex == 255:
        if mant == 0:
            return sign * math.INF
        return math.NAN
    if ex == 0:
        return sign * mant * math.ldexp(1.0, -149)
    return sign * (1.0 + mant / 8388608.0) * math.ldexp(1.0, ex - 127)

func _component(data, o, ctype, normalized):
    v := 0
    if ctype == 5126:
        return _f32(data, o)
    if ctype == 5120:
        v = data[o]
        if v >= 128:
            v = v - 256
        if normalized:
            return math.max(v / 127.0, -1.0)
        return v
    if ctype == 5121:
        v = data[o]
        if normalized:
            return v / 255.0
        return v
    if ctype == 5122:
        v = data[o] | (data[o + 1] << 8)
        if v >= 32768:
            v = v - 65536
        if normalized:
            return math.max(v / 32767.0, -1.0)
        return v
    if ctype == 5123:
        v = data[o] | (data[o + 1] << 8)
        if normalized:
            return v / 65535.0
        return v
    if ctype == 5125:
        return _u32(data, o)
    raise("ParseError", f"gltf : componentType {ctype} inconnu")

func _comp_size(ctype):
    if ctype == 5120 or ctype == 5121:
        return 1
    if ctype == 5122 or ctype == 5123:
        return 2
    if ctype == 5125 or ctype == 5126:
        return 4
    raise("ParseError", f"gltf : componentType {ctype} inconnu")

func _type_count(t):
    if t == "SCALAR":
        return 1
    if t == "VEC2":
        return 2
    if t == "VEC3":
        return 3
    if t == "VEC4" or t == "MAT2":
        return 4
    if t == "MAT3":
        return 9
    if t == "MAT4":
        return 16
    raise("ParseError", f"gltf : type d'accesseur '{t}' inconnu")

# Lit un accesseur : liste de scalaires (SCALAR) ou de listes (VECn, MATn).
func _read_accessor(doc, buffers, index):
    accs := _get(doc, "accessors", [])
    if index < 0 or index >= len(accs):
        raise("ParseError", f"gltf : accesseur {index} inexistant")
    acc := accs[index]
    count := acc["count"]
    ncomp := _type_count(acc["type"])
    ctype := acc["componentType"]
    csize := _comp_size(ctype)
    normalized := _get(acc, "normalized", false)
    if "sparse" in acc:
        return _read_sparse(doc, buffers, acc, index)
    out := []
    if not ("bufferView" in acc):
        i := 0
        while i < count:
            if ncomp == 1:
                append(out, 0.0)
            else:
                z := []
                k := 0
                while k < ncomp:
                    append(z, 0.0)
                    k += 1
                append(out, z)
            i += 1
        return out
    views := _get(doc, "bufferViews", [])
    bv := views[acc["bufferView"]]
    data := buffers[bv["buffer"]]
    offset := _get(bv, "byteOffset", 0) + _get(acc, "byteOffset", 0)
    stride := _get(bv, "byteStride", ncomp * csize)
    if offset + (count - 1) * stride + ncomp * csize > len(data) and count > 0:
        raise("ParseError", "gltf : accesseur hors du tampon")
    i := 0
    while i < count:
        base := offset + i * stride
        if ncomp == 1:
            append(out, _component(data, base, ctype, normalized))
        else:
            e := []
            k := 0
            while k < ncomp:
                append(e, _component(data, base + k * csize, ctype, normalized))
                k += 1
            append(out, e)
        i += 1
    return out

# Accesseur « sparse » : valeurs de base (ou zéros) puis remplacement des éléments listés.
func _read_sparse(doc, buffers, acc, index):
    base := dict_copy_without(acc, "sparse")
    accs := doc["accessors"]
    saved := accs[index]
    accs[index] = base
    out := _read_accessor(doc, buffers, index)
    accs[index] = saved
    sp := acc["sparse"]
    n := sp["count"]
    views := _get(doc, "bufferViews", [])
    iv := views[sp["indices"]["bufferView"]]
    idata := buffers[iv["buffer"]]
    ioff := _get(iv, "byteOffset", 0) + _get(sp["indices"], "byteOffset", 0)
    ict := sp["indices"]["componentType"]
    isz := _comp_size(ict)
    vv := views[sp["values"]["bufferView"]]
    vdata := buffers[vv["buffer"]]
    voff := _get(vv, "byteOffset", 0) + _get(sp["values"], "byteOffset", 0)
    ncomp := _type_count(acc["type"])
    ctype := acc["componentType"]
    csize := _comp_size(ctype)
    normalized := _get(acc, "normalized", false)
    k := 0
    while k < n:
        i := _component(idata, ioff + k * isz, ict, false)
        if ncomp == 1:
            out[i] = _component(vdata, voff + k * csize, ctype, normalized)
        else:
            e := []
            c := 0
            while c < ncomp:
                append(e, _component(vdata, voff + (k * ncomp + c) * csize, ctype, normalized))
                c += 1
            out[i] = e
        k += 1
    return out

func dict_copy_without(d, key):
    r := {}
    for k in d:
        if k != key:
            r[k] = d[k]
    return r

func _node_matrix(node):
    if "matrix" in node:
        mm := []
        for x in node["matrix"]:
            append(mm, x * 1.0)
        return mm
    t := _get(node, "translation", [0.0, 0.0, 0.0])
    r := _get(node, "rotation", [0.0, 0.0, 0.0, 1.0])
    s := _get(node, "scale", [1.0, 1.0, 1.0])
    return math3d.mat4_compose(t, math3d.quat_normalize(r), s)

# Crée les Mesh d'un maillage glTF (un par primitive triangulaire).
func _build_meshes(doc, buffers, mesh_index, flip_v, label):
    out := []
    mdef := doc["meshes"][mesh_index]
    prims := _get(mdef, "primitives", [])
    pi := 0
    while pi < len(prims):
        p := prims[pi]
        pi += 1
        mode := _get(p, "mode", 4)
        if mode < 4:
            continue
        attrs := p["attributes"]
        if not ("POSITION" in attrs):
            continue
        name := label
        if len(prims) > 1:
            name = f"{label}.{pi - 1}"
        m := Mesh(name)
        pos := _read_accessor(doc, buffers, attrs["POSITION"])
        for v in pos:
            append(m.positions, [v[0], v[1], v[2]])
        if "NORMAL" in attrs:
            for v in _read_accessor(doc, buffers, attrs["NORMAL"]):
                append(m.normals, [v[0], v[1], v[2]])
        if "TEXCOORD_0" in attrs:
            for v in _read_accessor(doc, buffers, attrs["TEXCOORD_0"]):
                if flip_v:
                    append(m.uvs, [v[0], 1.0 - v[1]])
                else:
                    append(m.uvs, [v[0], v[1]])
        raw := []
        if "indices" in p:
            raw = _read_accessor(doc, buffers, p["indices"])
        else:
            k := 0
            while k < len(pos):
                append(raw, k)
                k += 1
        if mode == 4:
            k := 0
            while k + 2 < len(raw):
                m.add_triangle(to_int(raw[k]), to_int(raw[k + 1]), to_int(raw[k + 2]))
                k += 3
        elif mode == 5:
            k := 0
            while k + 2 < len(raw):
                if k % 2 == 0:
                    m.add_triangle(to_int(raw[k]), to_int(raw[k + 1]), to_int(raw[k + 2]))
                else:
                    m.add_triangle(to_int(raw[k + 1]), to_int(raw[k]), to_int(raw[k + 2]))
                k += 1
        else:
            k := 1
            while k + 1 < len(raw):
                m.add_triangle(to_int(raw[0]), to_int(raw[k]), to_int(raw[k + 1]))
                k += 1
        if "material" in p:
            mats := _get(doc, "materials", [])
            mi := p["material"]
            if mi < len(mats) and "name" in mats[mi]:
                m.material = mats[mi]["name"]
            else:
                m.material = mi
        if not m.has_normals():
            m.normals = []
            m.compute_normals()
        m.validate()
        append(out, m)
    return out

# Décode un document glTF (texte JSON ou dict déjà analysé).
#   base_dir  : dossier des fichiers .bin référencés par uri (null = dossier courant)
#   glb_bin   : octets du bloc BIN d'un .glb (null pour un .gltf)
#   flip_v    : inverse v (glTF a l'origine des uvs en haut ; la bibliothèque l'a en bas)
#   bake      : true applique la matrice monde de chaque nœud aux sommets ; false laisse les sommets locaux et
#               enregistre la matrice dans mesh.world_matrix
# Renvoie la liste des Mesh de la scène par défaut (tous les maillages si aucune scène n'est déclarée).
func parse_gltf(source, base_dir=null, glb_bin=null, flip_v=true, bake=true):
    doc := source
    if type(source) == "str":
        doc = json.parse(source)
    if type(doc) != "dict":
        raise("ParseError", "gltf : objet JSON attendu")
    ver := _get(_get(doc, "asset", {}), "version", "")
    if len(ver) == 0 or string.slice(ver, 0, 1) != "2":
        raise("ParseError", "gltf : seule la version 2.x est gérée")
    buffers := []
    bdefs := _get(doc, "buffers", [])
    bi := 0
    while bi < len(bdefs):
        b := bdefs[bi]
        data := null
        if "uri" in b:
            uri := b["uri"]
            if string.starts_with(uri, "data:"):
                comma := string.find(uri, ",")
                if comma < 0:
                    raise("ParseError", "gltf : URI de données invalide")
                data = crypto.base64_decode(string.slice(uri, comma + 1, len(uri)))
            else:
                full := uri
                if base_dir != null and len(base_dir) > 0:
                    sep := "/"
                    if string.ends_with(base_dir, "/") or string.ends_with(base_dir, "\\"):
                        sep = ""
                    full = base_dir + sep + uri
                data = file.read_bytes(full)
        else:
            if glb_bin == null:
                raise("ParseError", f"gltf : tampon {bi} sans uri et sans bloc GLB")
            data = glb_bin
        append(buffers, data)
        bi += 1
    out := []
    meshes := _get(doc, "meshes", [])
    nodes := _get(doc, "nodes", [])
    scenes := _get(doc, "scenes", [])
    if len(scenes) == 0 or len(nodes) == 0:
        mi := 0
        while mi < len(meshes):
            label := _get(meshes[mi], "name", f"mesh{mi}")
            for m in _build_meshes(doc, buffers, mi, flip_v, label):
                append(out, m)
            mi += 1
        return out
    sc := _get(doc, "scene", 0)
    roots := _get(scenes[sc], "nodes", [])
    # parcours en profondeur avec pile explicite : [indice de nœud, matrice du parent]
    stack := []
    k := len(roots) - 1
    while k >= 0:
        append(stack, [roots[k], math3d.mat4_identity(), 0])
        k -= 1
    guard := 0
    while len(stack) > 0:
        item := stack[len(stack) - 1]
        stack = _drop_last(stack)
        guard += 1
        if guard > 1000000 or item[2] > 256:
            raise("ParseError", "gltf : hiérarchie de nœuds cyclique ou trop profonde")
        node := nodes[item[0]]
        world := math3d.mat4_mul(item[1], _node_matrix(node))
        if "mesh" in node:
            label := _get(node, "name", _get(meshes[node["mesh"]], "name", f"node{item[0]}"))
            for m in _build_meshes(doc, buffers, node["mesh"], flip_v, label):
                if bake:
                    m.transform(world)
                    m.world_matrix = math3d.mat4_identity()
                else:
                    m.world_matrix = world
                append(out, m)
        children := _get(node, "children", [])
        c := len(children) - 1
        while c >= 0:
            append(stack, [children[c], world, item[2] + 1])
            c -= 1
    return out

func _drop_last(xs):
    r := []
    i := 0
    while i < len(xs) - 1:
        append(r, xs[i])
        i += 1
    return r

# Décode un fichier GLB (liste d'octets) : en-tête « glTF », bloc JSON, bloc BIN facultatif.
func parse_glb(data, flip_v=true, bake=true):
    if len(data) < 20 or data[0] != 103 or data[1] != 108 or data[2] != 84 or data[3] != 70:
        raise("ParseError", "glb : signature « glTF » absente")
    if _u32(data, 4) != 2:
        raise("ParseError", "glb : seule la version 2 est gérée")
    total := _u32(data, 8)
    if total > len(data):
        raise("ParseError", "glb : fichier tronqué")
    o := 12
    json_text := null
    bin := null
    while o + 8 <= total:
        clen := _u32(data, o)
        ctype := _u32(data, o + 4)
        start := o + 8
        if start + clen > len(data):
            raise("ParseError", "glb : bloc tronqué")
        chunk := _slice(data, start, start + clen)
        if ctype == 1313821514:
            json_text = crypto.utf8_decode(chunk)
        elif ctype == 5130562:
            bin = chunk
        o = start + clen
    if json_text == null:
        raise("ParseError", "glb : bloc JSON absent")
    return parse_gltf(json_text, null, bin, flip_v, bake)

func _slice(xs, a, b):
    r := []
    i := a
    while i < b:
        append(r, xs[i])
        i += 1
    return r

# Tampons d'un document glTF déjà analysé (uri de données, fichiers voisins ou bloc BIN d'un .glb).
func gltf_buffers(doc, base_dir=null, glb_bin=null):
    buffers := []
    for b in _get(doc, "buffers", []):
        data := null
        if "uri" in b:
            uri := b["uri"]
            if string.starts_with(uri, "data:"):
                comma := string.find(uri, ",")
                if comma < 0:
                    raise("ParseError", "gltf : URI de données invalide")
                data = crypto.base64_decode(string.slice(uri, comma + 1, len(uri)))
            else:
                full := uri
                if base_dir != null and len(base_dir) > 0:
                    full = base_dir + "/" + uri
                data = file.read_bytes(full)
        else:
            if glb_bin == null:
                raise("ParseError", "gltf : tampon sans uri et sans bloc GLB")
            data = glb_bin
        append(buffers, data)
    return buffers

# Document glTF brut d'un fichier .gltf / .glb : {"doc", "buffers", "base"} (pour animation, matériaux...).
func load_gltf_document(path):
    low := string.lower(path)
    base := ""
    i := len(path) - 1
    while i >= 0:
        ch := str(path[i])
        if ch == "/" or ch == "\\":
            base = string.slice(path, 0, i)
            break
        i -= 1
    if string.ends_with(low, ".glb"):
        data := file.read_bytes(path)
        if len(data) < 20 or data[0] != 103 or data[1] != 108 or data[2] != 84 or data[3] != 70:
            raise("ParseError", "glb : signature « glTF » absente")
        total := _u32(data, 8)
        o := 12
        doc := null
        bin := null
        while o + 8 <= total and o + 8 <= len(data):
            clen := _u32(data, o)
            ctype := _u32(data, o + 4)
            start := o + 8
            chunk := _slice(data, start, start + clen)
            if ctype == 1313821514:
                doc = json.parse(crypto.utf8_decode(chunk))
            elif ctype == 5130562:
                bin = chunk
            o = start + clen
        if doc == null:
            raise("ParseError", "glb : bloc JSON absent")
        return {"doc": doc, "buffers": gltf_buffers(doc, base, bin), "base": base}
    doc := json.parse(file.read(path))
    return {"doc": doc, "buffers": gltf_buffers(doc, base, null), "base": base}

# Lit l'accesseur `index` d'un document (valeurs ou listes de composantes).
func gltf_accessor(doc, buffers, index):
    return _read_accessor(doc, buffers, index)

# Charge un .gltf (fichiers .bin voisins résolus depuis son dossier) ou un .glb selon l'extension.
func load_gltf(path, flip_v=true, bake=true):
    low := string.lower(path)
    if string.ends_with(low, ".glb"):
        return parse_glb(file.read_bytes(path), flip_v, bake)
    base := ""
    i := len(path) - 1
    while i >= 0:
        ch := str(path[i])
        if ch == "/" or ch == "\\":
            base = string.slice(path, 0, i)
            break
        i -= 1
    return parse_gltf(file.read(path), base, null, flip_v, bake)
