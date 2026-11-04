# Démo : animation squelettique et morphing (animation, gl.render.ModelRenderer) + ressources (assets).
#
#   ./alex run examples/gamedev/animation_demo.al
#
# Pour un personnage glTF animé : animation.load_gltf("perso.glb") puis gr.ModelRenderer / animation.Animator.
#
# Un tentacule à 8 os est construit dans le code (squelette, poids, deux clips « vague » et « tourbillon ») ;
# maintenir Espace mélange progressivement les deux clips. Le sol utilise une texture JPEG chargée en arrière-plan,
# rechargée à chaud si le fichier change. Échap : quitter.

from collections use append
use math
use math3d as m3
use mesh
use gl
use gl.window as glw
use gl.render as gr
use animation
use assets
from core use to_int

const BONES := 8
const SEG := 0.5

# Tentacule : cylindre de BONES segments, chaque anneau lié aux deux os voisins.
func tentacle():
    m := animation.Model()
    k := 0
    while k < BONES:
        append(m.nodes, {"name": "os" + str(k), "parent": k - 1, "children": [k + 1] if k + 1 < BONES else [],
                         "t": [0.0, SEG if k > 0 else 0.0, 0.0], "r": [0.0, 0.0, 0.0, 1.0], "s": [1.0, 1.0, 1.0],
                         "mesh": -1, "skin": -1, "weights": null})
        k += 1
    append(m.nodes, {"name": "corps", "parent": -1, "children": [], "t": [0.0, 0.0, 0.0], "r": [0.0, 0.0, 0.0, 1.0],
                     "s": [1.0, 1.0, 1.0], "mesh": 0, "skin": 0, "weights": null})
    m._compute_order()
    cyl := mesh.Mesh("tentacule")
    joints := []
    weights := []
    rings := BONES * 4 + 1
    sides := 12
    r := 0
    while r < rings:
        y := r * SEG * BONES / (rings - 1)
        rad := 0.35 * (1.0 - 0.8 * r / (rings - 1))
        b := y / SEG
        j0 := math.min(to_int(math.floor(b)), BONES - 1)
        f := b - j0
        j1 := math.min(j0 + 1, BONES - 1)
        s := 0
        while s < sides:
            a := 6.283185307179586 * s / sides
            append(cyl.positions, [math.cos(a) * rad, y, math.sin(a) * rad])
            append(cyl.normals, [math.cos(a), 0.0, math.sin(a)])
            append(cyl.uvs, [s * 1.0 / sides, y / (SEG * BONES)])
            append(joints, [j0, j1, 0, 0])
            append(weights, [1.0 - f, f, 0.0, 0.0])
            s += 1
        r += 1
    r = 0
    while r < rings - 1:
        s := 0
        while s < sides:
            a0 := r * sides + s
            a1 := r * sides + (s + 1) % sides
            cyl.add_triangle(a0, a1 + sides, a1)
            cyl.add_triangle(a0, a0 + sides, a1 + sides)
            s += 1
        r += 1
    append(m.meshes, [{"mesh": cyl, "joints": joints, "weights": weights, "targets": [], "material": 0}])
    ibm := []
    k = 0
    while k < BONES:
        append(ibm, m3.mat4_translation(0.0, 0.0 - k * SEG, 0.0))
        k += 1
    append(m.skins, {"name": "squelette", "joints": [k for k in 0..BONES], "ibm": ibm, "skeleton": 0})
    append(m.materials, {"name": "peau", "color": [0.55, 0.3, 0.75, 1.0], "texture": -1, "emissive": [0.0, 0.0, 0.0],
                         "double_sided": false, "alpha": "OPAQUE"})
    # clips : ondulation (rotation z déphasée) et tourbillon (rotation x)
    for spec in [["vague", 2.0, [0.0, 0.0, 1.0], 0.35], ["tourbillon", 1.5, [1.0, 0.0, 0.0], 0.45]]:
        c := animation.Clip(spec[0])
        k = 0
        while k < BONES:
            times := []
            vals := []
            n := 16
            i := 0
            while i <= n:
                t := spec[1] * i / n
                ang := spec[3] * math.sin(6.283185307179586 * t / spec[1] + k * 0.6)
                q := m3.quat_from_axis_angle(spec[2], ang)
                append(times, t)
                vals = vals + q
                i += 1
            c.add_channel(k, "rotation", times, vals)
            k += 1
        m.clips[c.name] = c
    return m

w := glw.Window("ALEX — animation 3D", 1280, 720, {"vsync": true})
r := gr.Renderer(w)
r.set_sun([-0.5, -1.0, -0.3], [0.9, 0.9, 0.85])
r.set_ambient([0.25, 0.25, 0.32])
am := assets.AssetManager("tests/gamedev/data")
am.renderer = r
am.watch(true)
sol_tex := am.load_async("photo420.jpg", "texture", {"filter": "linear"})
sol := gr.GpuMesh(mesh.plane(20, 20))
m_sol := gr.Material([1.0, 1.0, 1.0, 1.0], null, 0.1)
m_sol.uv_rect = [0.0, 0.0, 4.0, 4.0]

modeles := []
tent := tentacle()
append(modeles, [gr.ModelRenderer(r, tent), animation.Animator(tent), [0.0, 0.0, 0.0]])
bras := animation.load_gltf("tests/gamedev/data/bras.glb")
append(modeles, [gr.ModelRenderer(r, bras), animation.Animator(bras), [-4.0, 0.0, 0.0]])
modeles[0][1].blend([["vague", 1.0], ["tourbillon", 0.0]])
modeles[1][1].play("plie", 0.0, true)
mix := 0.0
while w.is_open():
    for e in w.poll():
        if e["type"] == "key_down" and e["key"] == "escape":
            w.close()
    if not w.is_open():
        break
    dt := w.dt if w.dt > 0.0 and w.dt < 0.1 else 1.0 / 60.0
    am.update()
    if sol_tex.ready() and m_sol.texture != sol_tex.value:
        m_sol.texture = sol_tex.value
    cible := 1.0 if w.key_down("space") else 0.0
    mix += (cible - mix) * math.min(1.0, dt * 3.0)
    modeles[0][1].blend([["vague", 1.0 - mix], ["tourbillon", mix]])
    for md in modeles:
        md[1].update(dt)
    t := w.time()
    r.begin_frame([0.08, 0.09, 0.13, 1.0])
    r.set_perspective(m3.radians(55), [math.sin(t * 0.2) * 9.0, 4.0, math.cos(t * 0.2) * 9.0], [0.0, 2.0, 0.0])
    r.draw(sol, null, m_sol)
    for md in modeles:
        md[0].draw(md[1], m3.mat4_translation(md[2][0], md[2][1], md[2][2]))
    w.swap()
    if w.frame_count % 30 == 0:
        w.set_title("ALEX — animation 3D — " + str(math.round(w.fps)) + " img/s — mélange " + str(math.round(mix * 100)) + " %")
am.shutdown()
