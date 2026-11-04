# ALEX STANDARD LIBRARY — animation
#
# Animation 3D : modèles glTF 2.0 complets (hiérarchie de nœuds, maillages, squelettes / skins, cibles de morphing,
# clips d'animation, matériaux), échantillonnage des clips (STEP, LINEAR avec slerp, CUBICSPLINE), poses, mélange
# pondéré, fondus enchaînés, vitesse, boucle, événements de fin, morphing (poids par nœud), et calcul des matrices
# d'os en code natif (une seule opération par image et par squelette). Le rendu GPU (skinning et morphing dans le
# shader) est gl.render.ModelRenderer.
#
#   use animation
#   use gl.render as gr
#   modele := animation.load_gltf("perso.glb")
#   print(modele.clip_names())                       # ["idle", "walk", "run", ...]
#   anim := animation.Animator(modele)
#   anim.play("idle")
#   rendu := gr.ModelRenderer(r, modele)              # r : gl.render.Renderer
#   # à chaque image :
#   anim.play("walk", 0.25)                           # fondu de 0,25 s (sans effet si déjà en cours)
#   anim.update(dt)
#   rendu.draw(anim, m3.mat4_translation(x, 0, z))
#   # mélange piloté : marche / course selon la vitesse ; un clip de visage s'ajoute sans gêner le corps
#   anim.blend([["walk", 1.0 - k], ["run", k], ["sourire", 1.0]])
#
# MÉLANGE : chaque canal (translation / rotation / échelle / poids d'un nœud) ne mélange que les pistes qui
#   l'animent, avec leurs poids (ramenés à 1 s'ils dépassent 1, complétés par la pose de repos s'ils sont < 1).
#
# POSE : par nœud, translation [x, y, z], rotation quaternion [x, y, z, w], échelle [x, y, z], poids de morphing.
# CONVENTIONS : celles de math3d (main droite, Y vers le haut, matrices en ordre colonne).
#
# Erreurs : ParseError (glTF invalide), KeyError (clip inconnu), ValueError.

from core use len, type, to_int
from collections use append
use math
use math3d as m3
use mesh as _mesh
use ffi
use _native_ffi as _nf

# ---------------------------------------------------------------------------------------------------------------------
# Modèle
# ---------------------------------------------------------------------------------------------------------------------

class Clip:
    func init(name):
        self.name = name
        self.channels = []          # {"node", "path", "times", "values", "interp", "n"} ; n = composantes
        self.duration = 0.0
        self._buf = null
        self._weights = []

    # Canaux TRS compilés pour le code natif (anim_sample) : ffi.Buffer, reconstruit après add_channel.
    func native_buffer():
        if self._buf != null:
            return self._buf
        chs := [c for c in self.channels if c["path"] != "weights"]
        head := [len(chs) * 1.0]
        data := []
        base := 1 + 8 * len(chs)
        for c in chs:
            to := base + len(data)
            for x in c["times"]:
                append(data, x * 1.0)
            vo := base + len(data)
            for x in c["values"]:
                append(data, x * 1.0)
            pc := 0 if c["path"] == "translation" else (1 if c["path"] == "rotation" else 2)
            ic := 0 if c["interp"] == "STEP" else (2 if c["interp"] == "CUBICSPLINE" else 1)
            head = head + [c["node"] * 1.0, pc * 1.0, c["n"] * 1.0, ic * 1.0, len(c["times"]) * 1.0, to * 1.0, vo * 1.0, 0.0]
        all := head + data
        b := ffi.Buffer(8 * len(all))
        b.write_array("f64", all)
        self._buf = b
        self._weights = [c for c in self.channels if c["path"] == "weights"]
        return b

    # Ajoute un canal : path "translation" | "rotation" | "scale" | "weights".
    func add_channel(node, path, times, values, interp="LINEAR", ncomp=null):
        self._buf = null
        n := ncomp
        if n == null:
            n = 4 if path == "rotation" else 3
        append(self.channels, {"node": node, "path": path, "times": times, "values": values, "interp": interp, "n": n})
        if len(times) > 0 and times[len(times) - 1] > self.duration:
            self.duration = times[len(times) - 1] * 1.0

class Model:
    func init():
        self.nodes = []             # {"name", "parent", "children", "t", "r", "s", "mesh", "skin", "weights"}
        self.order = []             # indices des nœuds, parents avant enfants
        self.meshes = []            # par maillage glTF : list de primitives (voir load_gltf)
        self.skins = []             # {"name", "joints", "ibm" (list de Mat4), "skeleton"}
        self.clips = {}
        self.materials = []         # {"name", "color", "texture" (indice d'image), "emissive", "double_sided", "alpha"}
        self.images = []            # {"uri" (chemin) ou "bytes" (list d'octets), "mime"}
        self.base = ""

    func clip(name):
        if not (name in self.clips):
            raise("KeyError", "animation : clip inconnu '" + str(name) + "'")
        return self.clips[name]

    func clip_names():
        return [k for k in self.clips]

    func node_index(name):
        k := 0
        while k < len(self.nodes):
            if self.nodes[k]["name"] == name:
                return k
            k += 1
        return -1

    # Pose de repos (valeurs des nœuds dans le fichier).
    func rest_pose():
        p := Pose(len(self.nodes))
        k := 0
        while k < len(self.nodes):
            nd := self.nodes[k]
            p.t[k] = [x for x in nd["t"]]
            p.r[k] = [x for x in nd["r"]]
            p.s[k] = [x for x in nd["s"]]
            p.w[k] = [x for x in nd["weights"]] if nd["weights"] != null else null
            k += 1
        return p

    func _compute_order():
        out := []
        stack := []
        k := len(self.nodes) - 1
        while k >= 0:
            if self.nodes[k]["parent"] < 0:
                append(stack, k)
            k -= 1
        while len(stack) > 0:
            i := stack[len(stack) - 1]
            stack = stack[0:len(stack) - 1]
            append(out, i)
            ch := self.nodes[i]["children"]
            j := len(ch) - 1
            while j >= 0:
                append(stack, ch[j])
                j -= 1
        if len(out) != len(self.nodes):
            raise("ParseError", "animation : hiérarchie de nœuds invalide (cycle ou nœud partagé)")
        self.order = out

# ---------------------------------------------------------------------------------------------------------------------
# Chargement glTF
# ---------------------------------------------------------------------------------------------------------------------

func _get(d, k, default):
    if k in d:
        return d[k]
    return default

func _flat(vals):
    out := []
    for v in vals:
        if type(v) == "list":
            for x in v:
                append(out, x * 1.0)
        else:
            append(out, v * 1.0)
    return out

func _decompose(mat):
    d := m3.mat4_decompose([x * 1.0 for x in mat])
    return d

# Charge un .gltf / .glb : nœuds, maillages (avec os et cibles de morphing), squelettes, clips, matériaux, images.
func load_gltf(path, flip_v=true):
    g := _mesh.load_gltf_document(path)
    doc := g["doc"]
    bufs := g["buffers"]
    m := Model()
    m.base = g["base"]
    nodes := _get(doc, "nodes", [])
    k := 0
    while k < len(nodes):
        nd := nodes[k]
        t := [0.0, 0.0, 0.0]
        r := [0.0, 0.0, 0.0, 1.0]
        s := [1.0, 1.0, 1.0]
        if "matrix" in nd:
            dec := _decompose(nd["matrix"])
            t = dec[0]
            r = dec[1]
            s = dec[2]
        else:
            t = [x * 1.0 for x in _get(nd, "translation", t)]
            r = [x * 1.0 for x in _get(nd, "rotation", r)]
            s = [x * 1.0 for x in _get(nd, "scale", s)]
        w := null
        if "weights" in nd:
            w = [x * 1.0 for x in nd["weights"]]
        elif "mesh" in nd and "weights" in doc["meshes"][nd["mesh"]]:
            w = [x * 1.0 for x in doc["meshes"][nd["mesh"]]["weights"]]
        append(m.nodes, {"name": _get(nd, "name", "node" + str(k)), "parent": -1, "children": _get(nd, "children", []),
                         "t": t, "r": r, "s": s, "mesh": _get(nd, "mesh", -1), "skin": _get(nd, "skin", -1), "weights": w})
        k += 1
    k = 0
    while k < len(m.nodes):
        for c in m.nodes[k]["children"]:
            m.nodes[c]["parent"] = k
        k += 1
    m._compute_order()
    # maillages
    for md in _get(doc, "meshes", []):
        prims := []
        for p in _get(md, "primitives", []):
            if _get(p, "mode", 4) != 4:
                continue
            at := p["attributes"]
            if not ("POSITION" in at):
                continue
            mm := _mesh.Mesh(_get(md, "name", "mesh"))
            for v in _mesh.gltf_accessor(doc, bufs, at["POSITION"]):
                append(mm.positions, [v[0], v[1], v[2]])
            if "NORMAL" in at:
                for v in _mesh.gltf_accessor(doc, bufs, at["NORMAL"]):
                    append(mm.normals, [v[0], v[1], v[2]])
            if "TEXCOORD_0" in at:
                for v in _mesh.gltf_accessor(doc, bufs, at["TEXCOORD_0"]):
                    append(mm.uvs, [v[0], 1.0 - v[1]] if flip_v else [v[0], v[1]])
            if "indices" in p:
                mm.indices = [to_int(i) for i in _mesh.gltf_accessor(doc, bufs, p["indices"])]
            else:
                mm.indices = [i for i in 0..len(mm.positions)]
            if not mm.has_normals():
                mm.normals = []
                mm.compute_normals()
            joints := null
            weights := null
            if "JOINTS_0" in at and "WEIGHTS_0" in at:
                joints = _mesh.gltf_accessor(doc, bufs, at["JOINTS_0"])
                weights = _mesh.gltf_accessor(doc, bufs, at["WEIGHTS_0"])
            targets := []
            for tg in _get(p, "targets", []):
                tp := _mesh.gltf_accessor(doc, bufs, tg["POSITION"]) if "POSITION" in tg else null
                tn := _mesh.gltf_accessor(doc, bufs, tg["NORMAL"]) if "NORMAL" in tg else null
                append(targets, {"positions": tp, "normals": tn})
            append(prims, {"mesh": mm, "joints": joints, "weights": weights, "targets": targets,
                           "material": _get(p, "material", -1)})
        append(m.meshes, prims)
    # squelettes
    for sk in _get(doc, "skins", []):
        ibm := []
        if "inverseBindMatrices" in sk:
            ibm = [[x * 1.0 for x in mat] for mat in _mesh.gltf_accessor(doc, bufs, sk["inverseBindMatrices"])]
        else:
            ibm = [m3.mat4_identity() for j in sk["joints"]]
        append(m.skins, {"name": _get(sk, "name", "skin"), "joints": sk["joints"], "ibm": ibm, "skeleton": _get(sk, "skeleton", -1)})
    # clips
    ai := 0
    for an in _get(doc, "animations", []):
        c := Clip(_get(an, "name", "anim" + str(ai)))
        samplers := an["samplers"]
        for ch in an["channels"]:
            tg := ch["target"]
            if not ("node" in tg):
                continue
            sm := samplers[ch["sampler"]]
            times := [x * 1.0 for x in _mesh.gltf_accessor(doc, bufs, sm["input"])]
            vals := _flat(_mesh.gltf_accessor(doc, bufs, sm["output"]))
            path := tg["path"]
            interp := _get(sm, "interpolation", "LINEAR")
            n := 4 if path == "rotation" else 3
            if path == "weights":
                per_key := len(vals) / len(times) if len(times) > 0 else 0
                n = to_int(per_key / 3) if interp == "CUBICSPLINE" else to_int(per_key)
            c.add_channel(tg["node"], path, times, vals, interp, n)
        m.clips[c.name] = c
        ai += 1
    # matériaux et images
    for mt in _get(doc, "materials", []):
        pbr := _get(mt, "pbrMetallicRoughness", {})
        tex := -1
        if "baseColorTexture" in pbr:
            texs := _get(doc, "textures", [])
            ti := pbr["baseColorTexture"]["index"]
            if ti < len(texs) and "source" in texs[ti]:
                tex = texs[ti]["source"]
        append(m.materials, {"name": _get(mt, "name", ""), "color": [x * 1.0 for x in _get(pbr, "baseColorFactor", [1, 1, 1, 1])],
                             "texture": tex, "emissive": [x * 1.0 for x in _get(mt, "emissiveFactor", [0, 0, 0])],
                             "double_sided": _get(mt, "doubleSided", false), "alpha": _get(mt, "alphaMode", "OPAQUE")})
    for im in _get(doc, "images", []):
        if "uri" in im and not (len(im["uri"]) > 5 and im["uri"][0:5] == "data:"):
            append(m.images, {"uri": (g["base"] + "/" + im["uri"]) if g["base"] != "" else im["uri"], "mime": _get(im, "mimeType", "")})
        elif "bufferView" in im:
            bv := doc["bufferViews"][im["bufferView"]]
            data := bufs[bv["buffer"]]
            o := _get(bv, "byteOffset", 0)
            append(m.images, {"bytes": data[o:o + bv["byteLength"]], "mime": _get(im, "mimeType", "")})
        else:
            append(m.images, {"uri": null, "mime": ""})
    return m

# ---------------------------------------------------------------------------------------------------------------------
# Poses et échantillonnage
# ---------------------------------------------------------------------------------------------------------------------

class Pose:
    func init(n):
        self.n = n
        self.t = [null for k in 0..n]
        self.r = [null for k in 0..n]
        self.s = [null for k in 0..n]
        self.w = [null for k in 0..n]

    func copy():
        p := Pose(self.n)
        k := 0
        while k < self.n:
            p.t[k] = [x for x in self.t[k]]
            p.r[k] = [x for x in self.r[k]]
            p.s[k] = [x for x in self.s[k]]
            p.w[k] = [x for x in self.w[k]] if self.w[k] != null else null
            k += 1
        return p

func _find_key(times, t):
    n := len(times)
    if t <= times[0]:
        return 0
    if t >= times[n - 1]:
        return n - 1
    lo := 0
    hi := n - 1
    while hi - lo > 1:
        mid := (lo + hi) // 2
        if times[mid] <= t:
            lo = mid
        else:
            hi = mid
    return lo

func _normalize4(q):
    l := math.sqrt(q[0] * q[0] + q[1] * q[1] + q[2] * q[2] + q[3] * q[3])
    if l < 1e-12:
        return [0.0, 0.0, 0.0, 1.0]
    return [q[0] / l, q[1] / l, q[2] / l, q[3] / l]

func slerp(a, b, t):
    d := a[0] * b[0] + a[1] * b[1] + a[2] * b[2] + a[3] * b[3]
    bb := b
    if d < 0.0:
        d = 0.0 - d
        bb = [0.0 - b[0], 0.0 - b[1], 0.0 - b[2], 0.0 - b[3]]
    if d > 0.9995:
        return _normalize4([a[k] + (bb[k] - a[k]) * t for k in 0..4])
    th := math.acos(d)
    sn := math.sin(th)
    wa := math.sin((1.0 - t) * th) / sn
    wb := math.sin(t * th) / sn
    return [a[k] * wa + bb[k] * wb for k in 0..4]

# Valeur d'un canal à l'instant t.
func sample_channel(ch, t):
    times := ch["times"]
    vals := ch["values"]
    n := ch["n"]
    i := _find_key(times, t)
    interp := ch["interp"]
    if interp == "CUBICSPLINE":
        # triplets (tangente d'entrée, valeur, tangente de sortie)
        if len(times) == 1 or t <= times[0] or t >= times[len(times) - 1] or interp == "":
            j := i
            return vals[(3 * j + 1) * n:(3 * j + 2) * n]
        t0 := times[i]
        t1 := times[i + 1]
        dt := t1 - t0
        u := (t - t0) / dt
        u2 := u * u
        u3 := u2 * u
        h00 := 2.0 * u3 - 3.0 * u2 + 1.0
        h10 := u3 - 2.0 * u2 + u
        h01 := -2.0 * u3 + 3.0 * u2
        h11 := u3 - u2
        out := []
        k := 0
        while k < n:
            p0 := vals[(3 * i + 1) * n + k]
            m0 := vals[(3 * i + 2) * n + k]
            p1 := vals[(3 * (i + 1) + 1) * n + k]
            m1 := vals[(3 * (i + 1)) * n + k]
            append(out, h00 * p0 + h10 * dt * m0 + h01 * p1 + h11 * dt * m1)
            k += 1
        if ch["path"] == "rotation":
            return _normalize4(out)
        return out
    if interp == "STEP" or len(times) == 1 or t <= times[0] or t >= times[len(times) - 1]:
        return vals[i * n:(i + 1) * n]
    t0 := times[i]
    t1 := times[i + 1]
    u := (t - t0) / (t1 - t0)
    a := vals[i * n:(i + 1) * n]
    b := vals[(i + 1) * n:(i + 2) * n]
    if ch["path"] == "rotation":
        return slerp(a, b, u)
    return [a[k] + (b[k] - a[k]) * u for k in 0..n]

# Applique un clip à l'instant t sur une pose (les nœuds non animés gardent leur valeur).
func sample_clip(clip, t, pose):
    for ch in clip.channels:
        v := sample_channel(ch, t)
        nd := ch["node"]
        p := ch["path"]
        if p == "translation":
            pose.t[nd] = v
        elif p == "rotation":
            pose.r[nd] = v
        elif p == "scale":
            pose.s[nd] = v
        elif p == "weights":
            pose.w[nd] = v
    return pose

# Mélange de poses : [[pose, poids], ...]. Les poses peuvent être partielles (valeurs null = canal non animé) :
# chaque canal ne mélange que les poses qui l'animent ; si leur poids total est < 1, la pose de repos complète.
# Rotations par nlerp avec alignement des signes.
func blend_poses(items, rest):
    out := rest.copy()
    k := 0
    while k < out.n:
        out.t[k] = _blend_vec([[it[0].t[k], it[1]] for it in items if it[0].t[k] != null], rest.t[k])
        out.s[k] = _blend_vec([[it[0].s[k], it[1]] for it in items if it[0].s[k] != null], rest.s[k])
        out.r[k] = _blend_quat([[it[0].r[k], it[1]] for it in items if it[0].r[k] != null], rest.r[k])
        if rest.w[k] != null:
            out.w[k] = _blend_vec([[it[0].w[k], it[1]] for it in items if it[0].w[k] != null], rest.w[k])
        k += 1
    return out

func _blend_vec(lst, rest):
    if len(lst) == 0:
        return [x for x in rest]
    total := 0.0
    for it in lst:
        total += it[1]
    out := [0.0 for x in rest]
    if total <= 0.0:
        return [x for x in rest]
    norm := total if total > 1.0 else 1.0
    for it in lst:
        f := it[1] / norm
        j := 0
        while j < len(out) and j < len(it[0]):
            out[j] += it[0][j] * f
            j += 1
    if total < 1.0:
        j := 0
        while j < len(out):
            out[j] += rest[j] * (1.0 - total)
            j += 1
    return out

func _blend_quat(lst, rest):
    if len(lst) == 0:
        return [x for x in rest]
    total := 0.0
    for it in lst:
        total += it[1]
    if total <= 0.0:
        return [x for x in rest]
    norm := total if total > 1.0 else 1.0
    ref := lst[0][0]
    r := [0.0, 0.0, 0.0, 0.0]
    for it in lst:
        q := it[0]
        f := it[1] / norm
        if q[0] * ref[0] + q[1] * ref[1] + q[2] * ref[2] + q[3] * ref[3] < 0.0:
            f = 0.0 - f
        r = [r[0] + q[0] * f, r[1] + q[1] * f, r[2] + q[2] * f, r[3] + q[3] * f]
    if total < 1.0:
        f := 1.0 - total
        if rest[0] * ref[0] + rest[1] * ref[1] + rest[2] * ref[2] + rest[3] * ref[3] < 0.0:
            f = 0.0 - f
        r = [r[0] + rest[0] * f, r[1] + rest[1] * f, r[2] + rest[2] * f, r[3] + rest[3] * f]
    return _normalize4(r)

# ---------------------------------------------------------------------------------------------------------------------
# Animator : pistes, fondus, mélange, matrices
# ---------------------------------------------------------------------------------------------------------------------

class Track:
    func init(clip, loop, speed):
        self.clip = clip
        self.time = 0.0
        self.weight = 0.0
        self.target = 1.0
        self.rate = 0.0             # variation du poids par seconde (fondus)
        self.loop = loop
        self.speed = speed
        self.finished = false
        self.mask = null            # ffi.Buffer : un poids par nœud (couches masquées)
        self.additive = false
        self.ref_time = 0.0         # pose de référence d'une piste additive
        self.name = null            # nom de couche
        self.removing = false       # couche en fondu de sortie (clear_layer)

class Animator:
    func init(model):
        self.model = model
        self.rest = model.rest_pose()
        self.tracks = []
        self.layers = []            # couches au-dessus des pistes de base (remplacement masqué ou additif)
        self.speed = 1.0
        self.on_end = null          # fn(animator, nom du clip) quand un clip non bouclé se termine
        n := len(model.nodes)
        self._trs = ffi.Buffer(80 * (n if n > 0 else 1))
        self._parents = ffi.Buffer(8 * (n if n > 0 else 1))
        self._order = ffi.Buffer(8 * (n if n > 0 else 1))
        self._world = ffi.Buffer(128 * (n if n > 0 else 1))
        if n > 0:
            self._parents.write_array("i64", [nd["parent"] for nd in model.nodes])
            self._order.write_array("i64", model.order)
        self.skins = []             # par squelette : [joints (i64), ibm (f64), sortie (f32), nombre d'os]
        k := 0
        for sk in model.skins:
            nj := len(sk["joints"])
            mesh_node := -1
            ni := 0
            while ni < n:
                if model.nodes[ni]["skin"] == k:
                    mesh_node = ni
                ni += 1
            jb := ffi.Buffer(8 * (nj + 2))
            jb.write_array("i64", [nj, mesh_node] + sk["joints"])
            ib := ffi.Buffer(128 * (nj if nj > 0 else 1))
            flat := []
            for mtx in sk["ibm"]:
                for x in mtx:
                    append(flat, x)
            if len(flat) > 0:
                ib.write_array("f64", flat)
            append(self.skins, [jb, ib, ffi.Buffer(64 * (nj if nj > 0 else 1)), nj])
            k += 1
        self.world = []
        self.rest_flat = []
        self.rest_weights = {}
        k = 0
        while k < n:
            nd := model.nodes[k]
            for x in nd["t"] + nd["r"] + nd["s"]:
                append(self.rest_flat, x * 1.0)
            if nd["weights"] != null:
                self.rest_weights[k] = [x for x in nd["weights"]]
            k += 1
        self.flat = [x for x in self.rest_flat]
        self._rest_buf = ffi.Buffer(80 * (n if n > 0 else 1))
        self._acc = ffi.Buffer(144 * (n if n > 0 else 1))
        if n > 0:
            self._rest_buf.write_array("f64", self.rest_flat)
        self.weights = {}
        for k2 in self.rest_weights:
            self.weights[k2] = [x for x in self.rest_weights[k2]]
        self._flat_stale = false
        self._write_trs()

    func _clip(c):
        if type(c) == "str":
            return self.model.clip(c)
        return c

    func _track(clip):
        for t in self.tracks:
            if t.clip == clip:
                return t
        return null

    # Joue un clip : fondu enchaîné de `fade` secondes depuis les pistes en cours (0 = immédiat).
    func play(name, fade=0.0, loop=true, speed=1.0, restart=false):
        clip := self._clip(name)
        tr := self._track(clip)
        if tr != null and not restart and tr.target == 1.0 and len(self.tracks) == 1:
            return tr
        if tr == null:
            tr = Track(clip, loop, speed)
            append(self.tracks, tr)
        elif restart:
            tr.time = 0.0
            tr.finished = false
        tr.loop = loop
        tr.speed = speed
        for t in self.tracks:
            if t == tr:
                t.target = 1.0
                if fade <= 0.0:
                    t.weight = 1.0
                    t.rate = 0.0
                else:
                    t.rate = (1.0 - t.weight) / fade
            else:
                t.target = 0.0
                if fade <= 0.0:
                    t.weight = 0.0
                    t.rate = 0.0
                else:
                    t.rate = (0.0 - t.weight) / fade
        if fade <= 0.0:
            self.tracks = [tr]
        return tr

    # Mélange piloté : [[clip, poids], ...] (poids fixés ; les pistes absentes sont retirées).
    func blend(items, loop=true):
        keep := []
        for it in items:
            clip := self._clip(it[0])
            tr := self._track(clip)
            if tr == null:
                tr = Track(clip, loop, 1.0)
            tr.weight = it[1] * 1.0
            tr.target = tr.weight
            tr.rate = 0.0
            append(keep, tr)
        self.tracks = keep

    # Couche au-dessus des pistes de base : `mask` (animation.mask / bone_mask) limite les os touchés ; additive =
    # la différence avec la pose de référence (instant ref_time du clip) s'ajoute (respiration, recul, visée...).
    # Une couche de même nom est remplacée ; fondu de `fade` secondes. Rend la piste.
    func set_layer(name, clip, weight=1.0, mask=null, additive=false, fade=0.0, loop=true, speed=1.0, ref_time=0.0):
        c := self._clip(clip)
        old := null
        keep := []
        for t in self.layers:
            if t.name == name:
                old = t
            else:
                append(keep, t)
        tr := Track(c, loop, speed)
        tr.name = name
        tr.mask = mask
        tr.additive = additive
        tr.ref_time = ref_time
        if old != null and old.clip == c:
            tr.time = old.time
            tr.weight = old.weight
        else:
            tr.weight = 0.0 if fade > 0.0 else weight * 1.0
        tr.target = weight * 1.0
        tr.rate = (tr.target - tr.weight) / fade if fade > 0.0 else 0.0
        if fade <= 0.0:
            tr.weight = weight * 1.0
        append(keep, tr)
        self.layers = keep
        return tr

    # Retire une couche (fondu de sortie si fade > 0).
    func clear_layer(name, fade=0.0):
        keep := []
        for t in self.layers:
            if t.name == name and fade > 0.0:
                t.target = 0.0
                t.rate = (0.0 - t.weight) / fade
                t.removing = true
                append(keep, t)
            elif t.name != name:
                append(keep, t)
        self.layers = keep

    # Pose locale [translation, rotation, échelle] d'un nœud (après évaluation).
    func local_trs(i):
        f := self._trs.read_array("f64", 10, 80 * i)
        return [f[0:3], f[3:7], f[7:10]]

    func set_local_rotation(i, q):
        self._trs.write_array("f64", [q[0] * 1.0, q[1] * 1.0, q[2] * 1.0, q[3] * 1.0], 80 * i + 24)
        self._flat_stale = true

    func _node(x):
        if type(x) == "str":
            i := self.model.node_index(x)
            if i < 0:
                raise("KeyError", "animation : nœud inconnu '" + x + "'")
            return i
        return x

    # Rotation monde (quaternion) d'un nœud.
    func world_rotation(i):
        m := self.world_matrix(i)
        sx := math.sqrt(m[0] * m[0] + m[1] * m[1] + m[2] * m[2])
        sy := math.sqrt(m[4] * m[4] + m[5] * m[5] + m[6] * m[6])
        sz := math.sqrt(m[8] * m[8] + m[9] * m[9] + m[10] * m[10])
        return _normalize4(m3.quat_from_mat3([m[0] / sx, m[1] / sx, m[2] / sx, m[4] / sy, m[5] / sy, m[6] / sy, m[8] / sz, m[9] / sz, m[10] / sz]))

    # ---- cinématique inverse (après update) ----

    # IK à deux os (bras, jambe) : place l'extrémité `tip` sur `target` (position monde, repère du modèle) en tournant
    # `root` et `mid` ; `pole` (position monde) choisit le plan de pliage (coude, genou). weight 0..1.
    func ik_two_bone(root, mid, tip, target, pole=null, weight=1.0):
        ia := self._node(root)
        ib := self._node(mid)
        ic := self._node(tip)
        a := self.node_position(ia)
        b := self.node_position(ib)
        c := self.node_position(ic)
        t := target
        lab := m3.vec3_length(m3.vec3_sub(b, a))
        lcb := m3.vec3_length(m3.vec3_sub(b, c))
        lat := _clampf(m3.vec3_length(m3.vec3_sub(t, a)), 0.0001, lab + lcb - 0.0001)
        ca := m3.vec3_sub(c, a)
        ba := m3.vec3_sub(b, a)
        ab := m3.vec3_sub(a, b)
        cb := m3.vec3_sub(c, b)
        ta := m3.vec3_sub(t, a)
        ac_ab_0 := math.acos(_clampf(m3.vec3_dot(m3.vec3_normalize(ca), m3.vec3_normalize(ba)), -1.0, 1.0))
        ba_bc_0 := math.acos(_clampf(m3.vec3_dot(m3.vec3_normalize(ab), m3.vec3_normalize(cb)), -1.0, 1.0))
        ac_at_0 := math.acos(_clampf(m3.vec3_dot(m3.vec3_normalize(ca), m3.vec3_normalize(ta)), -1.0, 1.0))
        ac_ab_1 := math.acos(_clampf((lcb * lcb - lab * lab - lat * lat) / (-2.0 * lab * lat), -1.0, 1.0))
        ba_bc_1 := math.acos(_clampf((lat * lat - lab * lab - lcb * lcb) / (-2.0 * lab * lcb), -1.0, 1.0))
        dref := m3.vec3_sub(pole, a) if pole != null else ba
        axis0 := m3.vec3_cross(ca, dref)
        if m3.vec3_length(axis0) < 1e-9:
            axis0 = m3.vec3_cross(ca, [0.0, 0.0, 1.0])
        axis0 = m3.vec3_normalize(axis0)
        axis1 := m3.vec3_cross(ca, ta)
        ra := self.world_rotation(ia)
        rb := self.world_rotation(ib)
        la := self.local_trs(ia)[1]
        lb := self.local_trs(ib)[1]
        q0 := m3.quat_from_axis_angle(m3.quat_rotate(m3.quat_conjugate(ra), axis0), ac_ab_1 - ac_ab_0)
        q1 := m3.quat_from_axis_angle(m3.quat_rotate(m3.quat_conjugate(rb), axis0), ba_bc_1 - ba_bc_0)
        # monde : plier (q0, q1) puis viser (q2) ; en local : a * q2 * q0, b * q1
        na := m3.quat_mul(la, q0)
        nb := m3.quat_mul(lb, q1)
        if m3.vec3_length(axis1) > 1e-9:
            axis1 = m3.vec3_normalize(axis1)
            q2 := m3.quat_from_axis_angle(m3.quat_rotate(m3.quat_conjugate(ra), axis1), ac_at_0)
            na = m3.quat_mul(m3.quat_mul(la, q2), q0)
        if weight < 1.0:
            na = slerp(la, na, weight)
            nb = slerp(lb, nb, weight)
        self.set_local_rotation(ia, _normalize4(na))
        self.set_local_rotation(ib, _normalize4(nb))
        self.compute()

    # IK par descente de coordonnées cyclique (CCD) sur une chaîne [racine, ..., extrémité] : queues, colonnes,
    # tentacules. Rend la distance restante.
    func ik_ccd(chain, target, iterations=10, tolerance=0.001, weight=1.0):
        ids := [self._node(x) for x in chain]
        tip := ids[len(ids) - 1]
        it := 0
        while it < iterations:
            k := len(ids) - 2
            while k >= 0:
                j := ids[k]
                p := self.node_position(j)
                e := self.node_position(tip)
                v1 := m3.vec3_sub(e, p)
                v2 := m3.vec3_sub(target, p)
                if m3.vec3_length(v1) > 1e-9 and m3.vec3_length(v2) > 1e-9:
                    v1 = m3.vec3_normalize(v1)
                    v2 = m3.vec3_normalize(v2)
                    ang := math.acos(_clampf(m3.vec3_dot(v1, v2), -1.0, 1.0)) * weight
                    ax := m3.vec3_cross(v1, v2)
                    if ang > 1e-6 and m3.vec3_length(ax) > 1e-9:
                        rw := self.world_rotation(j)
                        lq := self.local_trs(j)[1]
                        q := m3.quat_from_axis_angle(m3.quat_rotate(m3.quat_conjugate(rw), m3.vec3_normalize(ax)), ang)
                        self.set_local_rotation(j, _normalize4(m3.quat_mul(lq, q)))
                        self.compute()
                k -= 1
            if m3.vec3_length(m3.vec3_sub(self.node_position(tip), target)) < tolerance:
                break
            it += 1
        return m3.vec3_length(m3.vec3_sub(self.node_position(tip), target))

    # Oriente un os vers une cible (tête, yeux, tourelle) : `axis` = direction locale qui doit viser (Z+ par défaut).
    func look_at(bone, target, axis=null, weight=1.0):
        i := self._node(bone)
        ax := axis if axis != null else [0.0, 0.0, 1.0]
        rw := self.world_rotation(i)
        cur := m3.quat_rotate(rw, ax)
        want := m3.vec3_sub(target, self.node_position(i))
        if m3.vec3_length(want) < 1e-9:
            return
        cur = m3.vec3_normalize(cur)
        want = m3.vec3_normalize(want)
        ang := math.acos(_clampf(m3.vec3_dot(cur, want), -1.0, 1.0)) * weight
        cr := m3.vec3_cross(cur, want)
        if ang < 1e-6 or m3.vec3_length(cr) < 1e-9:
            return
        lq := self.local_trs(i)[1]
        q := m3.quat_from_axis_angle(m3.quat_rotate(m3.quat_conjugate(rw), m3.vec3_normalize(cr)), ang)
        self.set_local_rotation(i, _normalize4(m3.quat_mul(lq, q)))
        self.compute()

    # Synchronise les durées des clips mélangés (marche / course en phase) : temps normalisé commun.
    func sync_phase():
        if len(self.tracks) < 2:
            return
        ref := self.tracks[0]
        for t in self.tracks:
            if t.weight > ref.weight:
                ref = t
        ph := ref.time / ref.clip.duration if ref.clip.duration > 0 else 0.0
        for t in self.tracks:
            t.time = ph * t.clip.duration

    func stop(fade=0.0):
        if fade <= 0.0:
            self.tracks = []
            return
        for t in self.tracks:
            t.target = 0.0
            t.rate = (0.0 - t.weight) / fade

    func current():
        best := null
        for t in self.tracks:
            if best == null or t.weight > best.weight:
                best = t
        return best.clip.name if best != null else null

    func update(dt):
        for t in self.layers:
            d := t.clip.duration
            t.time += dt * t.speed * self.speed
            if d > 0.0:
                if t.loop:
                    while t.time >= d:
                        t.time -= d
                elif t.time >= d:
                    t.time = d
                    if not t.finished:
                        t.finished = true
                        if self.on_end != null:
                            self.on_end(self, t.clip.name)
            if t.rate != 0.0:
                t.weight += t.rate * dt
                if (t.rate > 0.0 and t.weight >= t.target) or (t.rate < 0.0 and t.weight <= t.target):
                    t.weight = t.target
                    t.rate = 0.0
        # couches retirées en fondu (clear_layer) : supprimées une fois éteintes
        self.layers = [t for t in self.layers if not t.removing or t.rate != 0.0]
        alive := []
        for t in self.tracks:
            d := t.clip.duration
            t.time += dt * t.speed * self.speed
            if d > 0.0:
                if t.loop:
                    while t.time >= d:
                        t.time -= d
                    while t.time < 0.0:
                        t.time += d
                elif t.time >= d:
                    t.time = d
                    if not t.finished:
                        t.finished = true
                        if self.on_end != null:
                            self.on_end(self, t.clip.name)
            if t.rate != 0.0:
                t.weight += t.rate * dt
                if (t.rate > 0.0 and t.weight >= t.target) or (t.rate < 0.0 and t.weight <= t.target):
                    t.weight = t.target
                    t.rate = 0.0
            if t.weight > 0.0001 or t.rate > 0.0 or t.target > 0.0:
                append(alive, t)
        self.tracks = alive
        self.evaluate()
        self.compute()

    # Pose courante à partir des pistes : canaux TRS échantillonnés et mélangés en code natif (anim_sample,
    # anim_resolve) ; poids de morphing en ALEX.
    func evaluate():
        n := len(self.model.nodes)
        weights := {}
        for k in self.rest_weights:
            weights[k] = self.rest_weights[k][0:len(self.rest_weights[k])]
        live := [t for t in self.tracks if t.weight > 0.0]
        if n > 0:
            self._acc.fill(0)
            for t in live:
                _nf.anim_sample(t.clip.native_buffer()._live(), t.time * 1.0, t.weight * 1.0, self._acc._live(), t.mask._live() if t.mask != null else null)
            _nf.anim_resolve(self._acc._live(), self._rest_buf._live(), self._trs._live(), n)
            # couches : remplacement masqué (fondu vers la couche) puis additif
            for t in self.layers:
                if t.weight <= 0.0:
                    continue
                if t.additive:
                    _nf.anim_additive(t.clip.native_buffer()._live(), t.time * 1.0, t.weight * 1.0, self._trs._live(), t.ref_time * 1.0, t.mask._live() if t.mask != null else null)
                else:
                    self._acc.fill(0)
                    _nf.anim_sample(t.clip.native_buffer()._live(), t.time * 1.0, math.min(t.weight, 1.0) * 1.0, self._acc._live(), t.mask._live() if t.mask != null else null)
                    _nf.anim_resolve(self._acc._live(), self._trs._live(), self._trs._live(), n)
        # poids de morphing : moyenne pondérée des pistes qui les animent, complétée par le repos
        acc := {}
        for t in live:
            t.clip.native_buffer()
            for ch in t.clip._weights:
                v := sample_channel(ch, t.time)
                e := acc[ch["node"]] if ch["node"] in acc else null
                if e == null:
                    e = [[0.0 for i in 0..len(v)], 0.0]
                    acc[ch["node"]] = e
                i := 0
                while i < len(v) and i < len(e[0]):
                    e[0][i] += v[i] * t.weight
                    i += 1
                e[1] += t.weight
        for node in acc:
            e := acc[node]
            total := e[1]
            norm := total if total > 1.0 else 1.0
            rw := self.rest_weights[node] if node in self.rest_weights else [0.0 for i in 0..len(e[0])]
            weights[node] = [e[0][i] / norm + (rw[i] * (1.0 - total) if total < 1.0 and i < len(rw) else 0.0) for i in 0..len(e[0])]
        self.weights = weights
        self._flat_stale = true

    # Valeurs TRS courantes (10 flottants par nœud).
    func flat_pose():
        if self._flat_stale:
            n := len(self.model.nodes)
            self.flat = self._trs.read_array("f64", 10 * n) if n > 0 else []
            self._flat_stale = false
        return self.flat

    # Pose courante sous forme d'objet Pose (copie ; pour inspection ou blend_poses).
    func current_pose():
        p := Pose(len(self.model.nodes))
        k := 0
        f := self.flat_pose()
        while k < p.n:
            p.t[k] = f[10 * k:10 * k + 3]
            p.r[k] = f[10 * k + 3:10 * k + 7]
            p.s[k] = f[10 * k + 7:10 * k + 10]
            p.w[k] = self.weights[k] if k in self.weights else null
            k += 1
        return p

    func _write_trs(upload=true):
        n := len(self.model.nodes)
        if n == 0:
            return
        if upload:
            self._trs.write_array("f64", self.flat)
        if len(self.skins) == 0:
            _nf.anim_skin(self._trs._live(), self._parents._live(), self._order._live(), n, self._world._live(), null, null, null)
        for sk in self.skins:
            _nf.anim_skin(self._trs._live(), self._parents._live(), self._order._live(), n, self._world._live(), sk[0]._live(), sk[1]._live(), sk[2]._live())

    # Matrices monde des nœuds et matrices d'os (code natif), depuis la pose évaluée.
    func compute():
        self._write_trs(false)

    # Matrice monde (Mat4) du nœud i dans la pose courante.
    func world_matrix(i):
        return self._world.read_array("f64", 16, 128 * i)

    # Tampon ffi des matrices d'os (16 flottants 32 bits par os) du squelette s.
    func joint_buffer(s):
        return self.skins[s][2]

    # Poids de morphing du nœud i dans la pose courante (ou null).
    func morph_weights(i):
        if i in self.weights:
            return self.weights[i]
        return null

    # Position monde d'un os / nœud (attacher une arme, une caméra...).
    func node_position(name_or_index):
        i := name_or_index
        if type(i) == "str":
            i = self.model.node_index(i)
        m := self.world_matrix(i)
        return [m[12], m[13], m[14]]

# Position d'un sommet après skinning (vérification, sélection, collisions) : primitive, indice du sommet,
# animateur et squelette.
func skinned_position(prim, vi, anim, skin=0):
    p := prim["mesh"].positions[vi]
    if prim["joints"] == null:
        return p
    js := prim["joints"][vi]
    ws := prim["weights"][vi]
    jm := anim.joint_buffer(skin).read_array("f32", 16 * anim.skins[skin][3])
    out := [0.0, 0.0, 0.0]
    k := 0
    while k < 4:
        w := ws[k]
        if w > 0.0:
            b := 16 * to_int(js[k])
            m := jm[b:b + 16]
            out[0] += w * (m[0] * p[0] + m[4] * p[1] + m[8] * p[2] + m[12])
            out[1] += w * (m[1] * p[0] + m[5] * p[1] + m[9] * p[2] + m[13])
            out[2] += w * (m[2] * p[0] + m[6] * p[1] + m[10] * p[2] + m[14])
        k += 1
    return out

func _clampf(x, a, b):
    if x < a:
        return a
    if x > b:
        return b
    return x

# Masque de couche : poids par nœud (ffi.Buffer). `bones` : noms ou indices ; with_children inclut les descendants
# (ex. ["spine_02"] = tout le haut du corps).
func bone_mask(model, bones, weight=1.0, with_children=true):
    n := len(model.nodes)
    w := [0.0 for k in 0..n]
    stack := []
    for b in bones:
        i := model.node_index(b) if type(b) == "str" else b
        if i < 0:
            raise("KeyError", "animation.bone_mask : nœud inconnu '" + str(b) + "'")
        append(stack, i)
    while len(stack) > 0:
        i := stack[len(stack) - 1]
        stack = stack[0:len(stack) - 1]
        w[i] = weight * 1.0
        if with_children:
            for c in model.nodes[i]["children"]:
                append(stack, c)
    b := ffi.Buffer(8 * (n if n > 0 else 1))
    if n > 0:
        b.write_array("f64", w)
    return b

# ---------------------------------------------------------------------------------------------------------------------
# Passage d'un modèle entre fils (assets) : dict de valeurs copiables et retour
# ---------------------------------------------------------------------------------------------------------------------

func model_to_dict(m):
    meshes := []
    for prims in m.meshes:
        lst := []
        for p in prims:
            mm := p["mesh"]
            append(lst, {"name": mm.name, "positions": mm.positions, "normals": mm.normals, "uvs": mm.uvs,
                         "indices": mm.indices, "joints": p["joints"], "weights": p["weights"], "targets": p["targets"],
                         "material": p["material"]})
        append(meshes, lst)
    clips := {}
    for k in m.clips:
        c := m.clips[k]
        clips[k] = {"name": c.name, "duration": c.duration,
                    "channels": [{"node": ch["node"], "path": ch["path"], "times": ch["times"], "values": ch["values"],
                                  "interp": ch["interp"], "n": ch["n"]} for ch in c.channels]}
    return {"nodes": m.nodes, "order": m.order, "meshes": meshes, "skins": m.skins, "clips": clips,
            "materials": m.materials, "images": m.images, "base": m.base}

func model_from_dict(d):
    m := Model()
    m.nodes = d["nodes"]
    m.order = d["order"]
    for prims in d["meshes"]:
        lst := []
        for p in prims:
            mm := _mesh.Mesh(p["name"])
            mm.positions = p["positions"]
            mm.normals = p["normals"]
            mm.uvs = p["uvs"]
            mm.indices = p["indices"]
            append(lst, {"mesh": mm, "joints": p["joints"], "weights": p["weights"], "targets": p["targets"], "material": p["material"]})
        append(m.meshes, lst)
    m.skins = d["skins"]
    for k in d["clips"]:
        cd := d["clips"][k]
        c := Clip(cd["name"])
        for ch in cd["channels"]:
            c.add_channel(ch["node"], ch["path"], ch["times"], ch["values"], ch["interp"], ch["n"])
        m.clips[k] = c
    m.materials = d["materials"]
    m.images = d["images"]
    m.base = d["base"]
    return m
