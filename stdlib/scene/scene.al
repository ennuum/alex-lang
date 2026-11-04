# ALEX STANDARD LIBRARY — scene
#
# Graphe de scène pour les jeux 2D et 3D : hiérarchie de nœuds avec matrices monde en cache, caméras
# (perspective, orthographique, 2D), lumières (directionnelle, ponctuelle, spot), culling par frustum, listes de rendu
# triées, picking par rayon. ALEX pur, sans dépendance graphique : ce module décide QUOI dessiner et OÙ ; il ne dessine pas.
#
#   use scene
#   use math3d
#   world := scene.Scene()
#   cam := scene.Camera("cam", math3d.radians(60), 16 / 9)
#   cam.set_position([0, 2, 8])
#   cam.look_at([0, 0, 0])
#   world.set_camera(cam)
#   ship := world.add(scene.Node("ship"))
#   ship.bounds = math3d.aabb([-1, -1, -1], [1, 1, 1])      # boîte locale ; drawable = ce qu'on veut dessiner
#   ship.drawable = "vaisseau"
#   ship.set_position([3, 0, -10])
#   for item in world.render_list():                         # [nœud, distance], visibles, du plus proche au plus loin
#       print(item[0].name, item[1])
#
# CONVENTIONS (voir math3d) : repère main droite, Y vers le haut, avant = -Z, rotations = quaternions [x, y, z, w],
# matrices Mat4 en ordre colonne. Un nœud 2D est un nœud ordinaire utilisant x, y et la rotation autour de Z
# (set_position2d, set_rotation2d) ; Camera2D est une caméra indépendante du graphe (axe Y vers le BAS en pixels).
#
# CACHE : la matrice monde est recalculée paresseusement ; toute modification de position / rotation / échelle d'un nœud
# invalide la sienne et celles de ses descendants.
#
# Erreurs : ValueError (cycle dans la hiérarchie, paramètre invalide), TypeError.

use math
use math3d
use algorithm
from core use len
from collections use append, pop, clear

const VERSION := "1.0.0"

# =============================================================================
# Node
# =============================================================================

class Node:
    func init(name=""):
        self.name = name
        self.parent = null
        self.children = []
        self.position = [0.0, 0.0, 0.0]
        self.rotation = [0.0, 0.0, 0.0, 1.0]
        self.scale = [1.0, 1.0, 1.0]
        self.visible = true
        self.drawable = null
        self.bounds = null
        self.data = {}
        self.layer = 0
        self._local = null
        self._world = null
        self._world_dirty = true

    # --- invalidation du cache ---
    func _invalidate_world():
        if self._world_dirty:
            return null
        self._world_dirty = true
        for c in self.children:
            c._invalidate_world()

    func _invalidate_local():
        self._local = null
        self._invalidate_world()
        # un nœud déjà « sale » peut avoir des enfants propres si on vient de lui ajouter un enfant : on force
        for c in self.children:
            c._invalidate_world()

    # --- transformation locale ---
    func set_position(p):
        self.position = [p[0] * 1.0, p[1] * 1.0, p[2] * 1.0]
        self._invalidate_local()

    func set_position2d(x, y):
        self.position = [x * 1.0, y * 1.0, self.position[2]]
        self._invalidate_local()

    func set_rotation(q):
        self.rotation = math3d.quat_normalize(q)
        self._invalidate_local()

    # Rotation Euler ordonnée YXZ (radians), voir math3d.quat_from_euler.
    func set_euler(x, y, z):
        self.rotation = math3d.quat_from_euler(x, y, z)
        self._invalidate_local()

    # Rotation autour de Z (nœuds 2D, sens trigonométrique).
    func set_rotation2d(angle):
        self.rotation = math3d.quat_from_axis_angle([0.0, 0.0, 1.0], angle)
        self._invalidate_local()

    # Angle de rotation autour de Z (nœuds 2D).
    func get_rotation2d():
        v := math3d.quat_rotate(self.rotation, [1.0, 0.0, 0.0])
        return math.atan2(v[1], v[0])

    func set_scale(s):
        self.scale = [s[0] * 1.0, s[1] * 1.0, s[2] * 1.0]
        self._invalidate_local()

    func set_uniform_scale(s):
        self.scale = [s * 1.0, s * 1.0, s * 1.0]
        self._invalidate_local()

    # Déplace de v : dans le repère du nœud (local = true) ou du parent.
    func translate(v, local=false):
        d := v
        if local:
            d = math3d.quat_rotate(self.rotation, v)
        self.position = math3d.vec3_add(self.position, d)
        self._invalidate_local()

    # Compose une rotation : q est appliqué APRÈS l'orientation actuelle dans le repère du parent (local = false)
    # ou AVANT, dans le repère propre du nœud (local = true).
    func rotate(q, local=true):
        if local:
            self.rotation = math3d.quat_normalize(math3d.quat_mul(self.rotation, q))
        else:
            self.rotation = math3d.quat_normalize(math3d.quat_mul(q, self.rotation))
        self._invalidate_local()

    func rotate_axis(axis, angle, local=true):
        self.rotate(math3d.quat_from_axis_angle(axis, angle), local)

    # Oriente l'avant (-Z) du nœud vers un point du MONDE. Le point doit être distinct de la position monde.
    func look_at(target, up=null):
        u := up
        if u == null:
            u = [0.0, 1.0, 0.0]
        wp := self.world_position()
        dirw := math3d.vec3_sub(target, wp)
        if math3d.vec3_length_sq(dirw) < 0.000000000001:
            raise("ValueError", "scene.Node.look_at : cible confondue avec le nœud")
        qw := math3d.quat_look_rotation(dirw, u)
        if self.parent == null:
            self.rotation = qw
        else:
            self.rotation = math3d.quat_normalize(math3d.quat_mul(math3d.quat_inverse(self.parent.world_rotation()), qw))
        self._invalidate_local()

    func local_matrix():
        if self._local == null:
            self._local = math3d.mat4_compose(self.position, self.rotation, self.scale)
        return self._local

    # --- transformation monde (en cache) ---
    func world_matrix():
        if self._world_dirty or self._world == null:
            if self.parent == null:
                self._world = self.local_matrix()
            else:
                self._world = math3d.mat4_mul(self.parent.world_matrix(), self.local_matrix())
            self._world_dirty = false
        return self._world

    func world_position():
        m := self.world_matrix()
        return [m[12], m[13], m[14]]

    # Orientation monde (la hiérarchie ne doit pas contenir de cisaillement).
    func world_rotation():
        if self.parent == null:
            return self.rotation
        return math3d.quat_normalize(math3d.quat_mul(self.parent.world_rotation(), self.rotation))

    func world_scale():
        return math3d.mat4_get_scale(self.world_matrix())

    # Directions monde unitaires du nœud.
    func forward():
        return math3d.vec3_normalize(math3d.mat4_transform_direction(self.world_matrix(), [0.0, 0.0, -1.0]))

    func right():
        return math3d.vec3_normalize(math3d.mat4_transform_direction(self.world_matrix(), [1.0, 0.0, 0.0]))

    func up_direction():
        return math3d.vec3_normalize(math3d.mat4_transform_direction(self.world_matrix(), [0.0, 1.0, 0.0]))

    # Point du repère du nœud -> monde, et inversement.
    func to_world(p):
        return math3d.mat4_transform_point(self.world_matrix(), p)

    func to_local(p):
        return math3d.mat4_transform_point(math3d.mat4_inverse_affine(self.world_matrix()), p)

    # Place le nœud pour que sa position MONDE soit p (tient compte du parent).
    func set_world_position(p):
        if self.parent == null:
            self.set_position(p)
        else:
            self.set_position(self.parent.to_local(p))

    # --- hiérarchie ---
    func is_ancestor_of(other):
        n := other.parent
        guard := 0
        while n != null:
            if n == self:
                return true
            n = n.parent
            guard += 1
            if guard > 100000:
                return true
        return false

    # Ajoute child comme enfant (le détache de son ancien parent). La transformation LOCALE de l'enfant est
    # conservée ; avec keep_world = true, c'est la transformation monde qui est conservée. Renvoie child.
    func add_child(child, keep_world=false):
        if child == self or child.is_ancestor_of(self):
            raise("ValueError", "scene.Node.add_child : cycle dans la hiérarchie")
        saved := null
        if keep_world:
            saved = child.world_matrix()
        if child.parent != null:
            child.parent._remove_child_link(child)
        child.parent = self
        append(self.children, child)
        if keep_world:
            local := math3d.mat4_mul(math3d.mat4_inverse_affine(self.world_matrix()), saved)
            d := math3d.mat4_decompose(local)
            child.position = d[0]
            child.rotation = d[1]
            child.scale = d[2]
            child._local = null
        child._invalidate_world()
        for c in child.children:
            c._invalidate_world()
        return child

    func _remove_child_link(child):
        k := 0
        while k < len(self.children):
            if self.children[k] == child:
                pop(self.children, k)
                return null
            k += 1

    func remove_child(child):
        if child.parent != self:
            raise("ValueError", "scene.Node.remove_child : ce nœud n'est pas un enfant")
        self._remove_child_link(child)
        child.parent = null
        child._invalidate_world()
        for c in child.children:
            c._invalidate_world()

    # Se retire de son parent (sans effet pour une racine).
    func detach(keep_world=false):
        if self.parent == null:
            return null
        old := self.parent
        saved := self.world_matrix()
        old.remove_child(self)
        if keep_world:
            d := math3d.mat4_decompose(saved)
            self.position = d[0]
            self.rotation = d[1]
            self.scale = d[2]
            self._local = null
            self._invalidate_world()

    # Premier descendant (en profondeur d'abord, dans l'ordre d'insertion) portant ce nom, ou null.
    func find(name):
        for c in self.children:
            if c.name == name:
                return c
            r := c.find(name)
            if r != null:
                return r
        return null

    # Nœud désigné par un chemin « a/b/c » relatif à ce nœud, ou null.
    func find_path(path):
        cur := self
        for part in path.split("/"):
            if len(part) == 0:
                continue
            nxt := null
            for c in cur.children:
                if c.name == part:
                    nxt = c
                    break
            if nxt == null:
                return null
            cur = nxt
        return cur

    # Liste (ordre préfixe) de ce nœud et de tous ses descendants.
    func subtree():
        out := [self]
        k := 0
        while k < len(out):
            for c in out[k].children:
                append(out, c)
            k += 1
        return out

    # Appelle fn(nœud) pour ce nœud puis ses descendants (ordre préfixe).
    func traverse(fn):
        fn(self)
        snapshot := []
        for c in self.children:
            append(snapshot, c)
        for c in snapshot:
            c.traverse(fn)

    # Descendants pour lesquels pred(nœud) est vrai.
    func find_all(pred):
        out := []
        for n in self.subtree():
            if pred(n):
                append(out, n)
        return out

    func ancestors():
        out := []
        n := self.parent
        while n != null:
            append(out, n)
            n = n.parent
        return out

    func depth():
        return len(self.ancestors())

    func root():
        n := self
        while n.parent != null:
            n = n.parent
        return n

    # Chemin complet « racine/…/nom ».
    func path():
        parts := [self.name]
        for a in self.ancestors():
            append(parts, a.name)
        r := ""
        k := len(parts) - 1
        while k >= 0:
            if len(r) > 0:
                r = r + "/"
            r = r + parts[k]
            k -= 1
        return r

    # Visible lui-même ET tous ses ancêtres le sont.
    func is_visible_in_tree():
        n := self
        while n != null:
            if not n.visible:
                return false
            n = n.parent
        return true

    # Boîte englobante MONDE du nœud (bounds transformée par la matrice monde), ou null sans bounds.
    func world_bounds():
        if self.bounds == null:
            return null
        return math3d.aabb_transform(self.bounds, self.world_matrix())

    # Boîte englobante monde de tout le sous-arbre visible qui porte des bounds (null s'il n'y en a pas).
    func subtree_bounds():
        acc := null
        for n in self.subtree():
            wb := n.world_bounds()
            if wb != null:
                if acc == null:
                    acc = wb
                else:
                    acc = math3d.aabb_union(acc, wb)
        return acc

# =============================================================================
# Camera (3D)
# =============================================================================

class Camera extends Node:
    func init(name="camera", fov=1.0471975511965976, aspect=1.7777777777777777, near=0.1, far=1000.0):
        super.init(name)
        self.fov = fov
        self.aspect = aspect
        self.near = near
        self.far = far
        self.orthographic = false
        self.ortho_height = 10.0

    func set_perspective(fov, aspect, near, far):
        self.fov = fov
        self.aspect = aspect
        self.near = near
        self.far = far
        self.orthographic = false

    # Projection orthographique : ortho_height = hauteur visible dans le monde (la largeur en découle via aspect).
    func set_orthographic(ortho_height, aspect, near, far):
        self.ortho_height = ortho_height
        self.aspect = aspect
        self.near = near
        self.far = far
        self.orthographic = true

    func projection_matrix():
        if self.orthographic:
            hh := self.ortho_height * 0.5
            hw := hh * self.aspect
            return math3d.mat4_ortho(0.0 - hw, hw, 0.0 - hh, hh, self.near, self.far)
        return math3d.mat4_perspective(self.fov, self.aspect, self.near, self.far)

    # Matrice de vue = inverse de la matrice monde de la caméra.
    func view_matrix():
        return math3d.mat4_inverse_affine(self.world_matrix())

    func view_projection():
        return math3d.mat4_mul(self.projection_matrix(), self.view_matrix())

    # Les 6 plans du frustum (normales vers l'intérieur), pour aabb_in_frustum / sphere_in_frustum.
    func frustum_planes():
        return math3d.mat4_frustum_planes(self.view_projection())

    # Rayon monde passant par le pixel (x, y) (origine en haut à gauche) d'une fenêtre w x h : [origine, direction unitaire].
    func screen_to_ray(x, y, w, h):
        inv := math3d.mat4_inverse(self.view_projection())
        a := math3d.mat4_unproject(inv, x, y, 0.0, w, h)
        b := math3d.mat4_unproject(inv, x, y, 1.0, w, h)
        return [a, math3d.vec3_normalize(math3d.vec3_sub(b, a))]

    # Pixel [x, y, profondeur 0..1] d'un point monde, ou null s'il est derrière la caméra.
    func world_to_screen(p, w, h):
        return math3d.mat4_project_to_screen(self.view_projection(), p, w, h)

    # Distance (le long de l'axe de visée) d'un point monde : positive devant la caméra.
    func depth_of(p):
        v := math3d.mat4_transform_point(self.view_matrix(), p)
        return 0.0 - v[2]

# =============================================================================
# Light
# =============================================================================

# kind : "directional" (soleil : direction seule), "point" (ampoule : position + portée), "spot" (projecteur : cône).
# La direction d'éclairage d'une lumière directionnelle ou spot est l'AVANT (-Z) du nœud.
class Light extends Node:
    func init(name="light", kind="point", color=null, intensity=1.0, range=10.0):
        super.init(name)
        if kind != "directional" and kind != "point" and kind != "spot":
            raise("ValueError", "scene.Light : type de lumière inconnu '" + kind + "' (directional, point, spot)")
        self.kind = kind
        self.color = [1.0, 1.0, 1.0]
        if color != null:
            self.color = [color[0] * 1.0, color[1] * 1.0, color[2] * 1.0]
        self.intensity = intensity
        self.range = range
        self.inner_angle = 0.2617993877991494
        self.outer_angle = 0.5235987755982988
        self.enabled = true

    # Direction (unitaire) vers laquelle la lumière éclaire.
    func direction():
        return self.forward()

    # Atténuation en fonction de la distance : 1 près de la source, 0 à `range` (lissée : (1 - (d/r)^4)^2 / (d^2 + 1)).
    func attenuation(distance):
        if self.kind == "directional":
            return 1.0
        if distance >= self.range:
            return 0.0
        r := distance / self.range
        f := 1.0 - r * r * r * r
        if f < 0.0:
            f = 0.0
        return f * f / (distance * distance + 1.0)

    # Facteur du cône (spot) pour un point monde : 1 dans le cône intérieur, 0 hors du cône extérieur.
    func spot_factor(point):
        if self.kind != "spot":
            return 1.0
        to_p := math3d.vec3_normalize(math3d.vec3_sub(point, self.world_position()))
        c := math3d.vec3_dot(self.direction(), to_p)
        return math3d.smoothstep(math.cos(self.outer_angle), math.cos(self.inner_angle), c)

    # Éclairement diffus (Lambert) RGB reçu par un point monde de normale n (unitaire) : couleur * intensité *
    # max(0, n·L) * atténuation * cône.
    func illuminate(point, normal):
        if not self.enabled:
            return [0.0, 0.0, 0.0]
        l := [0.0, 0.0, 0.0]
        att := 1.0
        if self.kind == "directional":
            l = math3d.vec3_neg(self.direction())
        else:
            d := math3d.vec3_sub(self.world_position(), point)
            dist := math3d.vec3_length(d)
            if dist < 0.000000001:
                return math3d.vec3_scale(self.color, self.intensity)
            l = math3d.vec3_scale(d, 1.0 / dist)
            att = self.attenuation(dist) * self.spot_factor(point)
        nl := math3d.vec3_dot(normal, l)
        if nl <= 0.0:
            return [0.0, 0.0, 0.0]
        return math3d.vec3_scale(self.color, self.intensity * nl * att)

# =============================================================================
# Scene
# =============================================================================

class Scene:
    func init(name="scene"):
        self.name = name
        self.root = Node("root")
        self.camera = null
        self.ambient = [0.1, 0.1, 0.1]

    # Ajoute un nœud sous `parent` (la racine par défaut). Renvoie le nœud.
    func add(node, parent=null):
        p := parent
        if p == null:
            p = self.root
        p.add_child(node)
        return node

    func remove(node):
        node.detach()

    func set_camera(cam):
        self.camera = cam
        if cam.root() != self.root:
            self.add(cam)

    func find(name):
        return self.root.find(name)

    func nodes():
        out := self.root.subtree()
        return out

    # Lumières actives du graphe (visibles dans l'arbre).
    func lights():
        out := []
        for n in self.root.subtree():
            if isinstance(n, Light) and n.enabled and n.is_visible_in_tree():
                append(out, n)
        return out

    # Nœuds à dessiner : visibles dans l'arbre, avec un `drawable`, et — si bounds est défini — dans le frustum de la
    # caméra. Un nœud sans bounds est toujours conservé. Sans caméra, aucun culling.
    func visible_nodes(camera=null):
        cam := camera
        if cam == null:
            cam = self.camera
        planes := null
        if cam != null:
            planes = cam.frustum_planes()
        out := []
        # parcours avec élagage des sous-arbres masqués
        stack := [self.root]
        while len(stack) > 0:
            n := pop(stack)
            if not n.visible:
                continue
            if n.drawable != null:
                keep := true
                if planes != null and n.bounds != null:
                    keep = math3d.aabb_in_frustum(n.world_bounds(), planes)
                if keep:
                    append(out, n)
            k := len(n.children) - 1
            while k >= 0:
                append(stack, n.children[k])
                k -= 1
        return out

    # Liste de rendu : [[nœud, distance], ...] des nœuds visibles. tri = "front_to_back" (opaques : moins de
    # surdessin), "back_to_front" (transparents) ou null (ordre du graphe). La distance est celle du centre de la
    # boîte monde (ou de la position monde) à la caméra.
    func render_list(tri="front_to_back", camera=null):
        cam := camera
        if cam == null:
            cam = self.camera
        out := []
        eye := [0.0, 0.0, 0.0]
        if cam != null:
            eye = cam.world_position()
        for n in self.visible_nodes(cam):
            c := n.world_position()
            wb := n.world_bounds()
            if wb != null:
                c = math3d.aabb_center(wb)
            append(out, [n, math3d.vec3_distance(c, eye)])
        if tri == "front_to_back":
            return algorithm.sorted(out, (e) => e[1])
        if tri == "back_to_front":
            return algorithm.sorted(out, (e) => e[1], true)
        return out

    # Picking : nœud dessinable le plus proche touché par le rayon (origine, direction), selon sa boîte monde.
    # Renvoie [nœud, distance] ou null. Les nœuds invisibles et sans bounds sont ignorés.
    func pick(origin, direction, max_distance=null):
        best := null
        dn := math3d.vec3_normalize(direction)
        for n in self.root.subtree():
            if n.bounds == null or n.drawable == null or not n.is_visible_in_tree():
                continue
            t := math3d.aabb_ray_intersect(n.world_bounds(), origin, dn, max_distance)
            if t != null:
                if best == null or t < best[1]:
                    best = [n, t]
        return best

    # Pick sous le curseur (x, y) d'une fenêtre w x h avec la caméra de la scène.
    func pick_screen(x, y, w, h):
        if self.camera == null:
            raise("ValueError", "scene.Scene.pick_screen : pas de caméra")
        r := self.camera.screen_to_ray(x, y, w, h)
        return self.pick(r[0], r[1])

    # Éclairement total RGB d'un point (ambiante + toutes les lumières actives).
    func lighting_at(point, normal):
        acc := [self.ambient[0], self.ambient[1], self.ambient[2]]
        for l in self.lights():
            acc = math3d.vec3_add(acc, l.illuminate(point, normal))
        return acc

# Fonction de tri 2D : ordre de dessin d'une liste de nœuds, du fond vers le devant : par `layer`, puis par Z monde,
# puis par Y monde croissant si y_sort (jeux en vue de dessus : ce qui est plus bas à l'écran passe devant ; avec un
# axe Y vers le bas, passer y_down = true).
func sort_2d(nodes, y_sort=false, y_down=true):
    return algorithm.sorted(nodes, null, false, (a, b) => _cmp_2d(a, b, y_sort, y_down))

func _cmp_2d(a, b, y_sort, y_down):
    if a.layer != b.layer:
        if a.layer < b.layer:
            return -1
        return 1
    pa := a.world_position()
    pb := b.world_position()
    if pa[2] != pb[2]:
        if pa[2] < pb[2]:
            return -1
        return 1
    if y_sort:
        ya := pa[1]
        yb := pb[1]
        if not y_down:
            ya = 0.0 - ya
            yb = 0.0 - yb
        if ya < yb:
            return -1
        if ya > yb:
            return 1
    return 0

# =============================================================================
# Camera2D (indépendante du graphe)
# =============================================================================

# Caméra 2D en pixels, axe Y vers le BAS (convention écran). `position` est le point du monde au centre de la vue ;
# zoom > 1 agrandit. viewport = [largeur, hauteur] en pixels.
class Camera2D:
    func init(width=800.0, height=600.0):
        self.viewport = [width * 1.0, height * 1.0]
        self.position = [0.0, 0.0]
        self.zoom = 1.0
        self.rotation = 0.0
        self.limits = null

    # Matrice monde -> écran (Mat3) : translation de la caméra, rotation inverse, zoom, puis centrage dans la fenêtre.
    func view_matrix():
        c := math3d.mat3_translation(self.viewport[0] * 0.5, self.viewport[1] * 0.5)
        s := math3d.mat3_scaling(self.zoom, self.zoom)
        r := math3d.mat3_rotation(0.0 - self.rotation)
        t := math3d.mat3_translation(0.0 - self.position[0], 0.0 - self.position[1])
        return math3d.mat3_mul(c, math3d.mat3_mul(s, math3d.mat3_mul(r, t)))

    func world_to_screen(p):
        return math3d.mat3_transform_point(self.view_matrix(), p)

    func screen_to_world(p):
        return math3d.mat3_transform_point(math3d.mat3_inverse(self.view_matrix()), p)

    # Rectangle [xmin, ymin, xmax, ymax] du monde visible (boîte englobante si la caméra est tournée).
    func visible_rect():
        corners := [self.screen_to_world([0.0, 0.0]), self.screen_to_world([self.viewport[0], 0.0]), self.screen_to_world([self.viewport[0], self.viewport[1]]), self.screen_to_world([0.0, self.viewport[1]])]
        x0 := corners[0][0]
        x1 := corners[0][0]
        y0 := corners[0][1]
        y1 := corners[0][1]
        for c in corners:
            x0 = math.min(x0, c[0])
            x1 = math.max(x1, c[0])
            y0 = math.min(y0, c[1])
            y1 = math.max(y1, c[1])
        return [x0, y0, x1, y1]

    # Le rectangle monde [xmin, ymin, xmax, ymax] touche-t-il la vue ?
    func is_visible(rect):
        v := self.visible_rect()
        return rect[0] <= v[2] and rect[2] >= v[0] and rect[1] <= v[3] and rect[3] >= v[1]

    # Rapproche la caméra de target avec un lissage exponentiel indépendant du framerate (rate ~ 5 : doux, 20 : vif).
    func follow(target, dt, rate=8.0):
        self.position = [math3d.damp(self.position[0], target[0], rate, dt), math3d.damp(self.position[1], target[1], rate, dt)]
        self.apply_limits()

    # Zoome d'un facteur autour d'un point de l'écran, qui reste fixe sous le curseur.
    func zoom_at(screen_point, factor, min_zoom=0.05, max_zoom=64.0):
        before := self.screen_to_world(screen_point)
        self.zoom = math3d.clamp(self.zoom * factor, min_zoom, max_zoom)
        after := self.screen_to_world(screen_point)
        self.position = [self.position[0] + before[0] - after[0], self.position[1] + before[1] - after[1]]
        self.apply_limits()

    # Limite le centre de la caméra pour que la vue reste dans le rectangle [xmin, ymin, xmax, ymax] (si possible).
    func set_limits(rect):
        self.limits = rect
        self.apply_limits()

    func apply_limits():
        if self.limits == null:
            return null
        hw := self.viewport[0] * 0.5 / self.zoom
        hh := self.viewport[1] * 0.5 / self.zoom
        lo_x := self.limits[0] + hw
        hi_x := self.limits[2] - hw
        lo_y := self.limits[1] + hh
        hi_y := self.limits[3] - hh
        if lo_x > hi_x:
            self.position[0] = (self.limits[0] + self.limits[2]) * 0.5
        else:
            self.position[0] = math3d.clamp(self.position[0], lo_x, hi_x)
        if lo_y > hi_y:
            self.position[1] = (self.limits[1] + self.limits[3]) * 0.5
        else:
            self.position[1] = math3d.clamp(self.position[1], lo_y, hi_y)

    # Déplacement à l'écran (pixels) -> déplacement dans le monde (glisser pour faire défiler).
    func pan(screen_delta):
        d := math3d.vec2_rotate(math3d.vec2_scale(screen_delta, 1.0 / self.zoom), self.rotation)
        self.position = [self.position[0] - d[0], self.position[1] - d[1]]
        self.apply_limits()

    # Matrice de projection 3D équivalente (Mat4) pour un moteur de rendu : pixels -> clip, axe Y vers le bas.
    func projection_matrix():
        return math3d.mat4_ortho_screen(self.viewport[0], self.viewport[1])
