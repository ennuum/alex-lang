# ALEX - tests du module scene. Lancer depuis la racine : ./alex run tests/gamedev/test_scene.al
use scene
use math3d
use testing
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises, assert_null, assert_not_null

func near3(a, b):
    return math3d.vec3_equals(a, b, 0.0001)

func t_hierarchy():
    root := scene.Node("root")
    kid := scene.Node("kid")
    root.add_child(kid)
    root.set_position([10.0, 0.0, 0.0])
    kid.set_position([0.0, 2.0, 0.0])
    assert_true(near3(kid.world_position(), [10.0, 2.0, 0.0]))
    root.set_euler(0.0, math3d.HALF_PI, 0.0)
    assert_true(near3(kid.world_position(), [10.0, 2.0, 0.0]))
    kid.set_position([1.0, 0.0, 0.0])
    assert_true(near3(kid.world_position(), [10.0, 0.0, -1.0]))
    assert_true(near3(kid.to_local(kid.to_world([3.0, 4.0, 5.0])), [3.0, 4.0, 5.0]))
    assert_eq(kid.depth(), 1)
    assert_true(root.is_ancestor_of(kid))
    assert_true(root.find("kid") == kid)

testing.test("hiérarchie et matrices monde", t_hierarchy)

func t_reparent():
    a := scene.Node("a")
    b := scene.Node("b")
    k := scene.Node("k")
    a.set_position([5.0, 0.0, 0.0])
    a.add_child(k)
    k.set_position([1.0, 0.0, 0.0])
    b.set_position([0.0, 3.0, 0.0])
    b.add_child(k, true)
    assert_true(near3(k.world_position(), [6.0, 0.0, 0.0]))
    k.detach()
    assert_true(k.parent == null)

testing.test("changement de parent (keep_world)", t_reparent)

func t_cycle():
    a := scene.Node("a")
    b := scene.Node("b")
    a.add_child(b)
    assert_raises(() => b.add_child(a))
    assert_raises(() => a.add_child(a))

testing.test("refus des cycles", t_cycle)

func t_look_at():
    n := scene.Node("n")
    n.set_position([0.0, 0.0, 0.0])
    n.look_at([10.0, 0.0, 0.0])
    assert_true(near3(n.forward(), [1.0, 0.0, 0.0]))

testing.test("look_at et forward", t_look_at)

func t_camera_culling():
    world := scene.Scene()
    cam := scene.Camera("cam", math3d.radians(60.0), 16.0 / 9.0, 0.1, 100.0)
    cam.set_position([0.0, 0.0, 10.0])
    cam.look_at([0.0, 0.0, 0.0])
    world.set_camera(cam)
    near := world.add(scene.Node("proche"))
    near.bounds = math3d.aabb([-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    near.drawable = "a"
    far := world.add(scene.Node("loin"))
    far.bounds = math3d.aabb([-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    far.drawable = "b"
    far.set_position([0.0, 0.0, -50.0])
    behind := world.add(scene.Node("derriere"))
    behind.bounds = math3d.aabb([-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    behind.drawable = "c"
    behind.set_position([0.0, 0.0, 50.0])
    side := world.add(scene.Node("cote"))
    side.bounds = math3d.aabb([-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    side.drawable = "d"
    side.set_position([500.0, 0.0, 0.0])
    rl := world.render_list()
    names := []
    for it in rl:
        names.append(it[0].name)
    assert_true("proche" in names)
    assert_true("loin" in names)
    assert_false("derriere" in names)
    assert_false("cote" in names)
    assert_eq(rl[0][0].name, "proche")
    assert_true(rl[0][1] < rl[1][1])
    far.visible = false
    assert_eq(len(world.render_list()), 1)

testing.test("culling par frustum et tri", t_camera_culling)

func t_projection():
    cam := scene.Camera("cam", math3d.radians(90.0), 1.0, 0.1, 100.0)
    cam.set_position([0.0, 0.0, 5.0])
    cam.look_at([0.0, 0.0, 0.0])
    s := cam.world_to_screen([0.0, 0.0, 0.0], 800.0, 600.0)
    assert_near(s[0], 400.0, 0.5)
    assert_near(s[1], 300.0, 0.5)
    ray := cam.screen_to_ray(400.0, 300.0, 800.0, 600.0)
    assert_true(near3(math3d.vec3_normalize(ray[1]), [0.0, 0.0, -1.0]))

testing.test("projection écran et rayon de picking", t_projection)

func t_pick():
    world := scene.Scene()
    cam := scene.Camera("cam")
    cam.set_position([0.0, 0.0, 10.0])
    cam.look_at([0.0, 0.0, 0.0])
    world.set_camera(cam)
    a := world.add(scene.Node("a"))
    a.bounds = math3d.aabb([-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    a.drawable = "x"
    a.set_position([0.0, 0.0, 0.0])
    b := world.add(scene.Node("b"))
    b.bounds = math3d.aabb([-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    b.drawable = "y"
    b.set_position([0.0, 0.0, -5.0])
    hit := world.pick([0.0, 0.0, 10.0], [0.0, 0.0, -1.0])
    assert_not_null(hit)
    assert_true(hit[0] == a)
    assert_null(world.pick([20.0, 0.0, 10.0], [0.0, 0.0, -1.0]))

testing.test("picking par rayon", t_pick)

func t_lights():
    sun := scene.Light("soleil", "directional", [1.0, 1.0, 1.0], 1.0)
    sun.look_at([0.0, -1.0, 0.0])
    assert_true(near3(sun.direction(), [0.0, -1.0, 0.0]))
    lit := sun.illuminate([0.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    assert_true(lit[0] > 0.9)
    dark := sun.illuminate([0.0, 0.0, 0.0], [0.0, -1.0, 0.0])
    assert_near(dark[0], 0.0, 0.0001)
    lamp := scene.Light("lampe", "point", [1.0, 1.0, 1.0], 1.0, 10.0)
    lamp.set_position([0.0, 3.0, 0.0])
    assert_true(lamp.attenuation(1.0) > lamp.attenuation(5.0))
    assert_near(lamp.attenuation(20.0), 0.0, 0.0001)

testing.test("lumières", t_lights)

func t_camera2d():
    c := scene.Camera2D(800.0, 600.0)
    c.zoom = 2.0
    p := c.world_to_screen([10.0, 20.0])
    back := c.screen_to_world(p)
    assert_near(back[0], 10.0, 0.001)
    assert_near(back[1], 20.0, 0.001)

testing.test("caméra 2D", t_camera2d)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) scene en échec")
print("SCENE: OK")
