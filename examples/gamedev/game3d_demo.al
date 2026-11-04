# Démo de jeu 3D : physique (physics) + scène et caméra (scene) + maillages (mesh) + rendu logiciel (graphics),
# pilotés par une boucle à pas fixe (gameloop). Des caisses et des balles tombent sur un sol.
# Lancer depuis la racine : ./alex run examples/gamedev/game3d_demo.al
use math3d
use mesh
use scene
use physics
use gameloop
use time
from collections use append
use graphics.surface as gs
use graphics.buffer as gb
use graphics.shader as sh
use graphics.pipeline as gp
use graphics.render_pass as grp

const W := 160
const H := 120

# Un maillage de mesh -> tampons de graphics (position, normale, uv + indices).
func to_buffers(m):
    return [gb.VertexBuffer(gb.POSITION_NORMAL_UV, m.to_interleaved("pnu")), gb.IndexBuffer(m.indices)]

func make_world():
    w := physics.World()
    w.add(physics.static_body(physics.plane([0.0, 1.0, 0.0], 0.0)))
    items := []
    i := 0
    while i < 6:
        b := w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 1.0, [0.15 * i, 0.5 + 1.1 * i, 0.0]))
        append(items, [b, "caisse"])
        i += 1
    j := 0
    while j < 3:
        s := w.add(physics.Body(physics.sphere(0.4), 1.0, [-2.0 + j, 4.0 + j, 0.5]))
        s.restitution = 0.5
        append(items, [s, "balle"])
        j += 1
    return [w, items]

func draw_frame(items, cam, box_bufs, ball_bufs, ground_bufs):
    s := gs.Surface(W, H)
    # math3d est en ordre colonne, graphics.shader en ordre ligne : on transpose.
    view_proj := math3d.mat4_transpose(cam.view_projection())
    rp := grp.RenderPass(s)
    rp.clear_color = gs.rgba(0.35, 0.55, 0.85)
    rp.begin()
    lit := gp.Pipeline(sh.lit())
    ground_u := gb.UniformBuffer({"mvp": view_proj, "model": sh.identity(), "light_dir": [0.4, 0.8, 0.5], "diffuse": [0.3, 0.6, 0.3, 1.0]})
    rp.draw(lit, ground_bufs[0], ground_bufs[1], ground_u)
    for it in items:
        b := it[0]
        model := math3d.mat4_compose(b.position, b.rotation, [1.0, 1.0, 1.0])
        bufs := box_bufs if it[1] == "caisse" else ball_bufs
        colour := [0.9, 0.6, 0.3, 1.0] if it[1] == "caisse" else [0.9, 0.2, 0.2, 1.0]
        u := gb.UniformBuffer({"mvp": math3d.mat4_transpose(math3d.mat4_mul(cam.view_projection(), model)),
                               "model": math3d.mat4_transpose(model), "light_dir": [0.4, 0.8, 0.5], "diffuse": colour})
        rp.draw(lit, bufs[0], bufs[1], u)
    rp.end()
    return s

func main():
    pair := make_world()
    world := pair[0]
    items := pair[1]
    cam := scene.Camera("cam", math3d.radians(60.0), W * 1.0 / H, 0.1, 100.0)
    cam.set_position([0.0, 3.0, 8.0])
    cam.look_at([0.0, 1.5, 0.0])
    box_bufs := to_buffers(mesh.box(1.0, 1.0, 1.0))
    ball_bufs := to_buffers(mesh.sphere(0.4, 12, 8))
    ground_bufs := to_buffers(mesh.plane(20.0, 20.0, 1, 1))
    state := {"frame": 0}
    func update(dt):
        world.step(dt)
    func render(alpha):
        state["frame"] = state["frame"] + 1
    loop := gameloop.GameLoop(update, render, 1.0 / 60.0)
    t0 := time.monotonic()
    k := 0
    while k < 90:
        loop.advance(1.0 / 60.0)
        k += 1
    t1 := time.monotonic()
    img := draw_frame(items, cam, box_bufs, ball_bufs, ground_bufs)
    t2 := time.monotonic()
    print("simulation : 90 pas en", t1 - t0, "s ;", "rendu 1 image", W, "x", H, "en", t2 - t1, "s")
    print("pas joués :", loop.step_count, "temps simulé :", loop.sim_time)
    img.save_ppm("/tmp/game3d_demo.ppm")
    print("image écrite : /tmp/game3d_demo.ppm  (pixels non noirs :", img.count(0xFF000000) < W * H, ")")

main()
