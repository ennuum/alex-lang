# ALEX - tests du module physics.physics2d. Lancer depuis la racine : ./alex run tests/gamedev/test_physics2d.al
use physics.physics2d as p2
use testing
use math
from collections use append
from core use len
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises, assert_null, assert_not_null

func ground(w):
    return w.add(p2.static_body(p2.halfplane([0.0, 1.0], 0.0)))

func dist(a, b):
    return math.sqrt((a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]))

func run(w, n):
    i := 0
    while i < n:
        w.step(1.0 / 60.0)
        i += 1

func t_shapes():
    bx := p2.box([1.0, 0.5])
    assert_near(bx["area"], 2.0, 0.0001)
    assert_near(bx["inertia_unit"], (4.0 + 1.0) / 12.0, 0.0001)
    # polygone dans le sens horaire, décentré : recentré et réorienté
    tri := p2.polygon([[3.0, 3.0], [3.0, 5.0], [5.0, 3.0]])
    assert_near(tri["area"], 2.0, 0.0001)
    assert_near(tri["center"][0], 3.6666667, 0.001)
    s := 0.0
    for v in tri["verts"]:
        s = s + v[0]
    assert_near(s, 0.0, 0.0001)
    assert_raises(() => p2.circle(0.0), "ValueError")
    assert_raises(() => p2.box([0.0, 1.0]), "ValueError")
    assert_raises(() => p2.polygon([[0.0, 0.0], [1.0, 0.0]]), "ValueError")
    assert_raises(() => p2.polygon([[0.0, 0.0], [2.0, 0.0], [1.0, 0.2], [2.0, 2.0], [0.0, 2.0]]), "ValueError")
    assert_raises(() => p2.Body(p2.halfplane([0.0, 1.0], 0.0), 1.0), "ValueError")

testing.test("formes et validation", t_shapes)

func t_collide_pairs():
    c1 := p2.Body(p2.circle(1.0), 1.0, [0.0, 0.0])
    c2 := p2.Body(p2.circle(1.0), 1.0, [1.5, 0.0])
    c := p2.collide(c1, c2)
    assert_not_null(c)
    assert_near(c["normal"][0], 1.0, 0.0001)
    assert_near(c["points"][0][1], 0.5, 0.0001)
    assert_null(p2.collide(c1, p2.Body(p2.circle(1.0), 1.0, [5.0, 0.0])))
    b1 := p2.Body(p2.box([1.0, 1.0]), 1.0, [0.0, 0.0])
    b2 := p2.Body(p2.box([1.0, 1.0]), 1.0, [1.8, 0.2])
    bb := p2.collide(b1, b2)
    assert_not_null(bb)
    assert_near(bb["normal"][0], 1.0, 0.001)
    assert_true(len(bb["points"]) == 2)
    assert_near(bb["points"][0][1], 0.2, 0.001)
    assert_null(p2.collide(b1, p2.Body(p2.box([1.0, 1.0]), 1.0, [2.5, 0.0])))
    # boîte tournée de 45° : sommet contre face
    rot := p2.Body(p2.box([1.0, 1.0]), 1.0, [2.3, 0.0], math.PI / 4.0)
    assert_not_null(p2.collide(b1, rot))
    cb := p2.collide(p2.Body(p2.circle(0.5), 1.0, [1.3, 0.0]), b1)
    assert_not_null(cb)
    assert_near(cb["normal"][0], -1.0, 0.001)
    assert_near(cb["points"][0][1], 0.2, 0.001)
    # cercle au-dessus d'un coin
    corner := p2.collide(p2.Body(p2.circle(0.5), 1.0, [1.3, 1.3]), b1)
    assert_not_null(corner)
    assert_null(p2.collide(p2.Body(p2.circle(0.2), 1.0, [1.3, 1.3]), b1))
    pl := p2.static_body(p2.halfplane([0.0, 1.0], 0.0))
    assert_not_null(p2.collide(p2.Body(p2.box([1.0, 1.0]), 1.0, [0.0, 0.9]), pl))
    assert_not_null(p2.collide(p2.Body(p2.circle(1.0), 1.0, [0.0, 0.9]), pl))
    assert_null(p2.collide(p2.Body(p2.circle(1.0), 1.0, [0.0, 1.1]), pl))
    # symétrie
    d1 := p2.collide(c1, c2)
    d2 := p2.collide(c2, c1)
    assert_near(d1["normal"][0], -d2["normal"][0], 0.0001)
    e1 := p2.collide(b1, b2)
    e2 := p2.collide(b2, b1)
    assert_near(e1["normal"][0], -e2["normal"][0], 0.001)

testing.test("détection pour chaque paire de formes", t_collide_pairs)

func t_fall_rest_bounce():
    w := p2.World()
    ground(w)
    ball := w.add(p2.Body(p2.circle(0.5), 1.0, [0.0, 5.0]))
    run(w, 240)
    assert_true(ball.position[1] > 0.45 and ball.position[1] < 0.55)
    assert_true(_len(ball.velocity) < 0.1)
    w2 := p2.World()
    ground(w2)
    b := w2.add(p2.Body(p2.circle(0.5), 1.0, [0.0, 4.0]))
    b.restitution = 0.8
    b.linear_damping = 0.0
    top := 0.0
    bounced := false
    i := 0
    while i < 150:
        w2.step(1.0 / 60.0)
        if b.velocity[1] > 1.0:
            bounced = true
        if bounced and b.position[1] > top:
            top = b.position[1]
        i += 1
    assert_true(bounced)
    assert_true(top > 1.5)

func _len(v):
    return math.sqrt(v[0] * v[0] + v[1] * v[1])

testing.test("chute, repos et rebond", t_fall_rest_bounce)

func t_stack_and_friction():
    w := p2.World()
    ground(w)
    boxes := []
    i := 0
    while i < 3:
        append(boxes, w.add(p2.Body(p2.box([0.5, 0.5]), 1.0, [0.0, 0.5 + 1.05 * i])))
        i += 1
    run(w, 240)
    k := 0
    while k < 3:
        assert_true(math.abs(boxes[k].position[0]) < 0.1)
        assert_true(math.abs(boxes[k].position[1] - (0.5 + k * 1.0)) < 0.1)
        k += 1
    # pente de 30° : tient avec mu = 0.9, glisse avec mu = 0.05
    n := [-0.5, 0.8660254]
    w2 := p2.World()
    w2.add(p2.static_body(p2.halfplane(n, 0.0)))
    grip := w2.add(p2.Body(p2.box([0.3, 0.3]), 1.0, [0.0, 0.35], 0.5235988))
    grip.friction = 1.0
    slick := w2.add(p2.Body(p2.box([0.3, 0.3]), 1.0, [-4.0, 0.35 + 4.0 * 0.5773503], 0.5235988))
    slick.friction = 0.02
    start := [slick.position[0], slick.position[1]]
    g0 := [grip.position[0], grip.position[1]]
    run(w2, 120)
    assert_true(dist(grip.position, g0) < 0.5)
    assert_true(dist(slick.position, start) > 1.5)

testing.test("pile stable et friction sur pente", t_stack_and_friction)

func t_events_layers():
    w := p2.World()
    ground(w)
    ball := w.add(p2.Body(p2.circle(0.5), 1.0, [0.0, 2.0]))
    zone := w.add(p2.static_body(p2.box([2.0, 0.5]), [0.0, 0.25]))
    zone.is_trigger = true
    log := []
    w.on_begin((a, b, c) => append(log, "debut"))
    w.on_end((a, b, c) => append(log, "fin"))
    run(w, 60)
    assert_true(len(log) >= 1)
    assert_eq(log[0], "debut")
    # couches : deux corps qui ne se voient pas se traversent
    w2 := p2.World()
    ground(w2)
    ghost := w2.add(p2.Body(p2.circle(0.5), 1.0, [0.0, 3.0]))
    ghost.layer = 2
    ghost.mask = 4
    run(w2, 120)
    assert_true(ghost.position[1] < 0.0 - 1.0)
    other := w2.add(p2.Body(p2.circle(0.5), 1.0, [0.0, 3.0]))
    other.mask = 1
    other.layer = 1
    ghost.mask = 1
    ghost.layer = 8
    run(w2, 5)

testing.test("événements et couches", t_events_layers)

func t_queries():
    w := p2.World()
    ground(w)
    c := w.add(p2.Body(p2.circle(1.0), 1.0, [0.0, 5.0]))
    b := w.add(p2.static_body(p2.box([1.0, 1.0]), [5.0, 5.0], 0.0))
    h := w.raycast([0.0, 10.0], [0.0, -1.0], 100.0)
    assert_true(h["body"] == c)
    assert_near(h["t"], 4.0, 0.001)
    assert_near(h["normal"][1], 1.0, 0.001)
    hb := w.raycast([0.0, 5.0], [1.0, 0.0], 100.0, null, c)
    assert_true(hb["body"] == b)
    assert_near(hb["t"], 4.0, 0.001)
    assert_near(hb["normal"][0], -1.0, 0.001)
    assert_near(w.raycast([20.0, 5.0], [0.0, -1.0])["t"], 5.0, 0.001)
    assert_null(w.raycast([0.0, 10.0], [0.0, 1.0], 100.0))
    assert_eq(len(w.raycast_all([-10.0, 5.0], [1.0, 0.0])), 2)
    assert_eq(len(w.overlap_aabb([-0.5, 4.5], [0.5, 5.5])), 1)
    assert_eq(len(w.overlap_circle([4.0, 5.0], 0.5)), 1)
    assert_eq(len(w.overlap_circle([2.5, 5.0], 0.2)), 0)

testing.test("raycasts et recouvrements", t_queries)

func t_ccd():
    w := p2.World()
    w.gravity = [0.0, 0.0]
    wall := w.add(p2.static_body(p2.box([0.02, 5.0]), [10.0, 0.0]))
    wall.restitution = 0.0
    b := w.add(p2.Body(p2.circle(0.1), 1.0, [0.0, 0.0]))
    b.velocity = [300.0, 0.0]
    b.restitution = 0.0
    b.linear_damping = 0.0
    run(w, 6)
    assert_true(b.position[0] < 10.0 and b.position[0] > 9.5)
    w2 := p2.World()
    w2.gravity = [0.0, 0.0]
    w2.ccd = false
    w2.add(p2.static_body(p2.box([0.02, 5.0]), [10.0, 0.0]))
    b2 := w2.add(p2.Body(p2.circle(0.1), 1.0, [0.3, 0.0]))
    b2.velocity = [300.0, 0.0]
    run(w2, 6)
    assert_true(b2.position[0] > 10.5)

testing.test("détection continue", t_ccd)

func t_joints():
    # pendule à pivot
    w := p2.World()
    pivot := p2.fixed_point([0.0, 5.0])
    bob := w.add(p2.Body(p2.circle(0.5), 1.0, [2.0, 5.0]))
    bob.linear_damping = 0.0
    w.add_joint(p2.revolute_joint(pivot, bob, [0.0, 5.0]))
    low := 100.0
    i := 0
    while i < 150:
        w.step(1.0 / 60.0)
        d := dist(bob.position, [0.0, 5.0])
        assert_true(d > 1.9 and d < 2.1)
        low = math.min(low, bob.position[1])
        i += 1
    assert_true(low < 3.3 and low > 2.9)
    # pivot à limites et moteur
    w2 := p2.World()
    w2.gravity = [0.0, 0.0]
    post := p2.fixed_point([0.0, 0.0])
    arm := w2.add(p2.Body(p2.box([1.0, 0.1]), 1.0, [1.0, 0.0]))
    arm.angular_damping = 0.0
    j := w2.add_joint(p2.revolute_joint(post, arm, [0.0, 0.0], 0.0 - 0.2, 1.0))
    j.motor_enabled = true
    j.motor_speed = 2.0
    j.max_motor_torque = 1000.0
    run(w2, 120)
    assert_near(j.angle(), 1.0, 0.03)
    j.motor_speed = 0.0 - 2.0
    run(w2, 200)
    assert_near(j.angle(), 0.0 - 0.2, 0.03)
    assert_true(dist(arm.position, [math.cos(j.angle()), math.sin(j.angle())]) < 0.05)
    # corde et tige
    w3 := p2.World()
    top := p2.fixed_point([0.0, 10.0])
    rope := w3.add(p2.Body(p2.circle(0.2), 1.0, [2.0, 9.0]))
    rod := w3.add(p2.Body(p2.circle(0.2), 1.0, [0.0, 8.0]))
    w3.add_joint(p2.distance_joint(top, rope, [0.0, 10.0], [2.0, 9.0], null, 3.0))
    w3.add_joint(p2.distance_joint(top, rod, [0.0, 10.0], [0.0, 8.0]))
    k := 0
    while k < 150:
        w3.step(1.0 / 60.0)
        assert_true(dist(rope.position, [0.0, 10.0]) < 3.1)
        assert_true(math.abs(dist(rod.position, [0.0, 10.0]) - 2.0) < 0.1)
        k += 1
    # ressort : équilibre à rest + g / ω²
    w4 := p2.World()
    t4 := p2.fixed_point([0.0, 10.0])
    m := w4.add(p2.Body(p2.circle(0.2), 1.0, [0.0, 8.0]))
    m.linear_damping = 0.0
    w4.add_joint(p2.spring_joint(t4, m, [0.0, 10.0], [0.0, 8.0], 1.0, 1.0, 2.0))
    run(w4, 480)
    assert_near(m.position[1], 10.0 - 2.0 - 0.2485, 0.06)
    # soudure
    w5 := p2.World()
    ground(w5)
    a := w5.add(p2.Body(p2.box([0.5, 0.5]), 1.0, [0.0, 3.0]))
    b := w5.add(p2.Body(p2.box([0.5, 0.5]), 1.0, [1.0, 3.0]))
    w5.add_joint(p2.weld_joint(a, b))
    run(w5, 150)
    assert_true(math.abs(dist(a.position, b.position) - 1.0) < 0.1)
    assert_true(math.abs(a.angle - b.angle) < 0.05)

testing.test("articulations : pivot, moteur, corde, ressort, soudure", t_joints)

func t_joint_misc():
    w := p2.World()
    w.gravity = [0.0, 0.0]
    a := w.add(p2.Body(p2.circle(1.0), 1.0, [0.0, 0.0]))
    b := w.add(p2.Body(p2.circle(1.0), 1.0, [1.0, 0.0]))
    j := w.add_joint(p2.distance_joint(a, b))
    w.step(1.0 / 60.0)
    assert_eq(len(w.contacts), 0)
    j.collide_connected = true
    w.step(1.0 / 60.0)
    assert_true(len(w.contacts) > 0)
    assert_true(w.remove_joint(j))
    assert_raises(() => p2.revolute_joint(a, a, [0.0, 0.0]), "ValueError")
    # rupture
    w2 := p2.World()
    top := p2.fixed_point([0.0, 6.0])
    h := w2.add(p2.Body(p2.circle(0.3), 10.0, [0.0, 4.0]))
    jb := w2.add_joint(p2.distance_joint(top, h, [0.0, 6.0], [0.0, 4.0]))
    jb.break_force = 50.0
    run(w2, 30)
    assert_true(jb.broken)
    assert_true(h.position[1] < 3.5)
    # îlot de sommeil
    w3 := p2.World()
    anc := p2.fixed_point([0.0, 6.0])
    b1 := w3.add(p2.Body(p2.circle(0.2), 1.0, [0.0, 5.0]))
    b2 := w3.add(p2.Body(p2.circle(0.2), 1.0, [0.0, 4.0]))
    w3.add_joint(p2.distance_joint(anc, b1, [0.0, 6.0], [0.0, 5.0]))
    w3.add_joint(p2.distance_joint(b1, b2, [0.0, 5.0], [0.0, 4.0]))
    run(w3, 400)
    assert_true(b1.sleeping and b2.sleeping)
    b2.apply_impulse([4.0, 0.0])
    w3.step(1.0 / 60.0)
    assert_false(b1.sleeping)

testing.test("articulations : connexion, rupture, sommeil", t_joint_misc)

func pair_ids(pairs):
    out := []
    for p in pairs:
        a := p[0].id
        b := p[1].id
        if a > b:
            t := a
            a = b
            b = t
        append(out, a * 1000 + b)
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j] > v:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out

func t_broadphase_determinism():
    w := p2.World()
    ground(w)
    i := 0
    while i < 8:
        j := 0
        while j < 8:
            w.add(p2.Body(p2.circle(0.5), 1.0, [i * 0.9 - 3.0, 0.5 + (i + j) % 3 * 0.2 + j * 0.0]))
            j += 1
        i += 1
    w.broadphase = "sweep"
    ref := pair_ids(w._candidate_pairs())
    w.broadphase = "hash"
    assert_eq(pair_ids(w._candidate_pairs()), ref)
    assert_true(len(ref) > 30)
    # déterminisme
    res := []
    r := 0
    while r < 2:
        wd := p2.World()
        ground(wd)
        k := 0
        while k < 6:
            wd.add(p2.Body(p2.box([0.4, 0.3]), 1.0, [0.2 * k, 0.5 + k], 0.1 * k))
            k += 1
        run(wd, 90)
        append(res, wd.bodies[3].position[0] * 1000.0 + wd.bodies[3].position[1])
        r += 1
    assert_eq(res[0], res[1])

testing.test("phase large et déterminisme", t_broadphase_determinism)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) physics2d en échec")
print("PHYSICS2D: OK")
