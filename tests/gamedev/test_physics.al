# ALEX - tests du module physics. Lancer depuis la racine : ./alex run tests/gamedev/test_physics.al
use physics
use math3d
use testing
use math
use algorithm
from collections use append
from core use len
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises, assert_null, assert_not_null

func ground(w):
    return w.add(physics.static_body(physics.plane([0.0, 1.0, 0.0], 0.0)))

func t_rays():
    assert_near(physics.ray_sphere([0.0, 0.0, 5.0], [0.0, 0.0, -1.0], [0.0, 0.0, 0.0], 1.0), 4.0)
    assert_null(physics.ray_sphere([0.0, 3.0, 5.0], [0.0, 0.0, -1.0], [0.0, 0.0, 0.0], 1.0))
    assert_near(physics.ray_plane([0.0, 5.0, 0.0], [0.0, -1.0, 0.0], [0.0, 1.0, 0.0], 0.0), 5.0)
    t := physics.ray_triangle([0.2, 0.2, 5.0], [0.0, 0.0, -1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    assert_not_null(t)
    miss := physics.ray_triangle([2.0, 2.0, 5.0], [0.0, 0.0, -1.0], [0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    assert_null(miss)

testing.test("rayons contre formes", t_rays)

func t_collide_pairs():
    s1 := physics.Body(physics.sphere(1.0), 1.0, [0.0, 0.0, 0.0])
    s2 := physics.Body(physics.sphere(1.0), 1.0, [1.5, 0.0, 0.0])
    c := physics.collide(s1, s2)
    assert_not_null(c)
    assert_near(c["normal"][0], 1.0, 0.0001)
    assert_near(c["points"][0][1], 0.5, 0.0001)
    far := physics.Body(physics.sphere(1.0), 1.0, [5.0, 0.0, 0.0])
    assert_null(physics.collide(s1, far))
    b1 := physics.Body(physics.box([1.0, 1.0, 1.0]), 1.0, [0.0, 0.0, 0.0])
    b2 := physics.Body(physics.box([1.0, 1.0, 1.0]), 1.0, [1.8, 0.2, 0.0])
    assert_not_null(physics.collide(b1, b2))
    b3 := physics.Body(physics.box([1.0, 1.0, 1.0]), 1.0, [2.5, 0.0, 0.0])
    assert_null(physics.collide(b1, b3))
    cap := physics.Body(physics.capsule(0.5, 1.0), 1.0, [0.0, 0.0, 0.0])
    sph := physics.Body(physics.sphere(0.5), 1.0, [0.8, 1.2, 0.0])
    assert_not_null(physics.collide(cap, sph))
    pl := physics.static_body(physics.plane([0.0, 1.0, 0.0], 0.0))
    low := physics.Body(physics.box([1.0, 1.0, 1.0]), 1.0, [0.0, 0.9, 0.0])
    assert_not_null(physics.collide(low, pl))
    sb := physics.Body(physics.sphere(1.0), 1.0, [0.0, 0.0, 0.0])
    bx := physics.Body(physics.box([1.0, 1.0, 1.0]), 1.0, [1.9, 0.0, 0.0])
    assert_not_null(physics.collide(sb, bx))
    # symétrie : la normale change de sens quand on échange A et B
    c1 := physics.collide(s1, s2)
    c2 := physics.collide(s2, s1)
    assert_near(c1["normal"][0], -c2["normal"][0], 0.0001)

testing.test("détection pour chaque paire de formes", t_collide_pairs)

func t_fall_and_rest():
    w := physics.World()
    ground(w)
    ball := w.add(physics.Body(physics.sphere(0.5), 1.0, [0.0, 5.0, 0.0]))
    i := 0
    while i < 300:
        w.step(1.0 / 60.0)
        i += 1
    assert_true(ball.position[1] > 0.45 and ball.position[1] < 0.55)
    assert_true(math3d.vec3_length(ball.velocity) < 0.1)

testing.test("chute puis repos sur le sol", t_fall_and_rest)

func t_restitution():
    w := physics.World()
    g := ground(w)
    g.restitution = 1.0
    ball := w.add(physics.Body(physics.sphere(0.5), 1.0, [0.0, 3.0, 0.0]))
    ball.restitution = 1.0
    ball.linear_damping = 0.0
    top := 0.0
    went_up := false
    i := 0
    while i < 240:
        w.step(1.0 / 60.0)
        if ball.velocity[1] > 1.0:
            went_up = true
        i += 1
    assert_true(went_up)

testing.test("rebond (restitution)", t_restitution)

func t_stack():
    w := physics.World()
    ground(w)
    a := w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 1.0, [0.0, 0.5, 0.0]))
    b := w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 1.0, [0.0, 1.5, 0.0]))
    c := w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 1.0, [0.0, 2.5, 0.0]))
    i := 0
    while i < 300:
        w.step(1.0 / 60.0)
        i += 1
    assert_true(math3d.vec3_length([a.position[0], 0.0, a.position[2]]) < 0.1)
    assert_true(c.position[1] > 2.3 and c.position[1] < 2.7)
    assert_true(b.position[1] > 1.3 and b.position[1] < 1.7)

testing.test("pile de trois boîtes stable", t_stack)

func t_events_layers():
    w := physics.World()
    ground(w)
    begins := []
    w.on_begin((a, b, c) => begins.append(1))
    trig := w.add(physics.static_body(physics.box([1.0, 1.0, 1.0]), [0.0, 3.0, 0.0]))
    trig.is_trigger = true
    ball := w.add(physics.Body(physics.sphere(0.25), 1.0, [0.0, 6.0, 0.0]))
    i := 0
    while i < 120:
        w.step(1.0 / 60.0)
        i += 1
    assert_true(len(begins) >= 1)
    # un déclencheur ne bloque pas : la balle l'a traversé et repose sur le sol
    assert_true(ball.position[1] < 1.0)

testing.test("déclencheurs et événements de contact", t_events_layers)

func t_masks():
    w := physics.World()
    ground(w)
    ghost := w.add(physics.Body(physics.sphere(0.5), 1.0, [0.0, 3.0, 0.0]))
    ghost.layer = 2
    ghost.mask = 4
    i := 0
    while i < 120:
        w.step(1.0 / 60.0)
        i += 1
    assert_true(ghost.position[1] < -1.0)

testing.test("filtrage par couches", t_masks)

func t_queries():
    w := physics.World()
    ground(w)
    ball := w.add(physics.Body(physics.sphere(0.5), 1.0, [0.0, 0.5, 0.0]))
    ball.allow_sleep = false
    h := w.raycast([0.0, 10.0, 0.0], [0.0, -1.0, 0.0], 100.0)
    assert_not_null(h)
    assert_true(h["body"] == ball)
    assert_near(h["t"], 9.0, 0.01)
    assert_eq(len(w.raycast_all([0.0, 10.0, 0.0], [0.0, -1.0, 0.0])), 2)
    assert_null(w.raycast([0.0, 10.0, 0.0], [0.0, -1.0, 0.0], 5.0))
    ig := w.raycast([0.0, 10.0, 0.0], [0.0, -1.0, 0.0], 100.0, null, ball)
    assert_true(ig["body"] != ball)
    assert_true(len(w.overlap_sphere([0.0, 0.5, 0.0], 0.2)) >= 1)
    assert_true(len(w.overlap_aabb([-1.0, 0.0, -1.0], [1.0, 1.0, 1.0])) >= 1)

testing.test("requêtes du monde", t_queries)

func t_forces_kinematic():
    w := physics.World()
    w.gravity = [0.0, 0.0, 0.0]
    b := w.add(physics.Body(physics.sphere(0.5), 2.0, [0.0, 0.0, 0.0]))
    b.linear_damping = 0.0
    b.apply_impulse([4.0, 0.0, 0.0])
    assert_near(b.velocity[0], 2.0, 0.0001)
    w.step(1.0)
    assert_near(b.position[0], 2.0, 0.05)
    k := w.add(physics.kinematic_body(physics.box([1.0, 0.2, 1.0]), [0.0, 5.0, 0.0]))
    k.velocity = [1.0, 0.0, 0.0]
    w.step(1.0)
    assert_near(k.position[0], 1.0, 0.05)
    s := physics.static_body(physics.sphere(1.0), [0.0, 0.0, 0.0])
    assert_true(s.is_static())
    assert_raises(() => physics.Body(physics.sphere(1.0), -1.0))

testing.test("impulsions, cinématique et statique", t_forces_kinematic)

func run_sim():
    w := physics.World()
    ground(w)
    bodies := []
    i := 0
    while i < 4:
        bodies.append(w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 1.0, [0.1 * i, 1.0 + 1.2 * i, 0.0])))
        i += 1
    j := 0
    while j < 200:
        w.step(1.0 / 60.0)
        j += 1
    out := []
    for b in bodies:
        out.append(b.position[1])
    return out

func t_determinism():
    assert_eq(run_sim(), run_sim())

testing.test("simulation déterministe", t_determinism)


# ---------------------------------------------------------------------------
# Détection continue
# ---------------------------------------------------------------------------

func fast_wall_world(ccd):
    w := physics.World()
    w.gravity = [0.0, 0.0, 0.0]
    w.ccd = ccd
    wall := w.add(physics.static_body(physics.box([0.02, 5.0, 5.0]), [10.0, 0.0, 0.0]))
    wall.restitution = 0.0
    b := w.add(physics.Body(physics.sphere(0.1), 1.0, [0.0, 0.0, 0.0]))
    b.velocity = [300.0, 0.0, 0.0]
    b.restitution = 0.0
    b.linear_damping = 0.0
    return [w, b]

func t_ccd_wall():
    off := fast_wall_world(false)
    i := 0
    while i < 6:
        off[0].step(1.0 / 60.0)
        i += 1
    assert_true(off[1].position[0] > 10.5)
    on := fast_wall_world(true)
    j := 0
    while j < 6:
        on[0].step(1.0 / 60.0)
        j += 1
    assert_true(on[1].position[0] < 10.0)
    assert_true(on[1].position[0] > 9.5)
    assert_true(on[1].velocity[0] < 1.0)

testing.test("détection continue : mur mince", t_ccd_wall)

func t_ccd_ground_and_flags():
    w := physics.World()
    ground(w)
    ball := w.add(physics.Body(physics.sphere(0.2), 1.0, [0.0, 40.0, 0.0]))
    ball.velocity = [0.0, -400.0, 0.0]
    box := w.add(physics.Body(physics.box([0.3, 0.3, 0.3]), 1.0, [3.0, 40.0, 0.0]))
    box.velocity = [0.0, -400.0, 0.0]
    i := 0
    while i < 4:
        w.step(1.0 / 60.0)
        assert_true(ball.position[1] > 0.15)
        assert_true(box.position[1] > 0.25)
        i += 1
    # sans balayage pour ce corps, la traversée se produit
    w2 := physics.World()
    w2.add(physics.static_body(physics.box([5.0, 0.02, 5.0]), [0.0, 0.0, 0.0]))
    thru := w2.add(physics.Body(physics.sphere(0.1), 1.0, [0.0, 10.0, 0.0]))
    thru.continuous = false
    thru.velocity = [0.0, -300.0, 0.0]
    k := 0
    while k < 5:
        w2.step(1.0 / 60.0)
        k += 1
    assert_true(thru.position[1] < -1.0)

testing.test("détection continue : sol et réglage par corps", t_ccd_ground_and_flags)

# ---------------------------------------------------------------------------
# Articulations
# ---------------------------------------------------------------------------

func t_ball_pendulum():
    w := physics.World()
    anchor := physics.fixed_point([0.0, 5.0, 0.0])
    bob := w.add(physics.Body(physics.sphere(0.2), 1.0, [2.0, 5.0, 0.0]))
    bob.linear_damping = 0.0
    j := w.add_joint(physics.ball_joint(anchor, bob, [0.0, 5.0, 0.0]))
    low := 100.0
    i := 0
    while i < 180:
        w.step(1.0 / 60.0)
        d := math3d.vec3_length(math3d.vec3_sub(bob.position, [0.0, 5.0, 0.0]))
        assert_true(d > 1.9 and d < 2.1)
        if bob.position[1] < low:
            low = bob.position[1]
        i += 1
    assert_true(low < 3.2 and low > 2.9)
    assert_true(j.error() < 0.1)

testing.test("articulation rotule : pendule", t_ball_pendulum)

func t_hinge_limits_motor():
    w := physics.World()
    w.gravity = [0.0, 0.0, 0.0]
    post := physics.fixed_point([0.0, 0.0, 0.0])
    door := w.add(physics.Body(physics.box([1.0, 0.1, 0.05]), 2.0, [1.0, 0.0, 0.0]))
    door.angular_damping = 0.0
    j := w.add_joint(physics.hinge_joint(post, door, [0.0, 0.0, 0.0], [0.0, 1.0, 0.0], 0.0 - 0.1, math.PI / 2.0))
    j.motor_enabled = true
    j.motor_speed = 1.0
    j.max_motor_torque = 100.0
    i := 0
    while i < 60:
        w.step(1.0 / 60.0)
        i += 1
    assert_near(math.abs(door.angular_velocity[1]), 1.0, 0.1)
    assert_near(math.abs(j.angle()), 1.0, 0.15)
    # le moteur pousse jusqu'à la butée (angle positif autour de +Y = sens du moteur)
    j.motor_speed = 0.0 - 3.0
    k := 0
    while k < 200:
        w.step(1.0 / 60.0)
        k += 1
    assert_true(j.angle() > 0.0 - 0.2 and j.angle() < 0.05)
    j.motor_speed = 3.0
    m := 0
    while m < 300:
        w.step(1.0 / 60.0)
        m += 1
    assert_true(j.angle() > 1.4 and j.angle() < math.PI / 2.0 + 0.1)
    # l'axe de la charnière reste aligné
    assert_true(math.abs(door.position[1]) < 0.02)

testing.test("charnière : limites et moteur", t_hinge_limits_motor)

func t_distance_modes():
    w := physics.World()
    top := physics.fixed_point([0.0, 10.0, 0.0])
    rod := w.add(physics.Body(physics.sphere(0.2), 1.0, [0.0, 8.0, 0.0]))
    w.add_joint(physics.distance_joint(top, rod, [0.0, 10.0, 0.0], [0.0, 8.0, 0.0]))
    rope := w.add(physics.Body(physics.sphere(0.2), 1.0, [2.5, 9.0, 0.0]))
    w.add_joint(physics.distance_joint(top, rope, [0.0, 10.0, 0.0], [2.5, 9.0, 0.0], null, 3.0))
    i := 0
    while i < 150:
        w.step(1.0 / 60.0)
        dr := math3d.vec3_length(math3d.vec3_sub(rod.position, [0.0, 10.0, 0.0]))
        dp := math3d.vec3_length(math3d.vec3_sub(rope.position, [0.0, 10.0, 0.0]))
        assert_true(dr > 1.9 and dr < 2.1)
        assert_true(dp < 3.1)
        i += 1
    # la corde est tendue au bout de sa longueur, pas plus courte que ce que la gravité impose
    dp2 := math3d.vec3_length(math3d.vec3_sub(rope.position, [0.0, 10.0, 0.0]))
    assert_true(dp2 > 2.8)

testing.test("distance : tige et corde", t_distance_modes)

func t_spring():
    w := physics.World()
    top := physics.fixed_point([0.0, 10.0, 0.0])
    m := w.add(physics.Body(physics.sphere(0.2), 1.0, [0.0, 8.0, 0.0]))
    m.linear_damping = 0.0
    j := w.add_joint(physics.spring_joint(top, m, [0.0, 10.0, 0.0], [0.0, 8.0, 0.0], 1.0, 1.0, 2.0))
    # allongement d'équilibre : g / ω² = 9.81 / (2π)² ≈ 0.2485 m
    i := 0
    while i < 480:
        w.step(1.0 / 60.0)
        i += 1
    assert_near(m.position[1], 10.0 - 2.0 - 0.2485, 0.06)
    assert_true(math.abs(m.velocity[1]) < 0.1)

testing.test("ressort amorti à l'équilibre", t_spring)

func t_fixed_joint():
    w := physics.World()
    ground(w)
    a := w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 1.0, [0.0, 3.0, 0.0]))
    b := w.add(physics.Body(physics.box([0.5, 0.5, 0.5]), 1.0, [1.0, 3.0, 0.0]))
    j := w.add_joint(physics.fixed_joint(a, b))
    i := 0
    while i < 150:
        w.step(1.0 / 60.0)
        i += 1
    rel := math3d.vec3_sub(b.position, a.position)
    assert_true(math3d.vec3_length(rel) > 0.9 and math3d.vec3_length(rel) < 1.1)
    # même orientation (produit scalaire des quaternions proche de ±1)
    d := a.rotation[0] * b.rotation[0] + a.rotation[1] * b.rotation[1] + a.rotation[2] * b.rotation[2] + a.rotation[3] * b.rotation[3]
    assert_true(math.abs(d) > 0.98)
    assert_true(a.position[1] > 0.4 and a.position[1] < 0.6)

testing.test("articulation fixe (soudure)", t_fixed_joint)

func t_slider():
    w := physics.World()
    rail := physics.fixed_point([0.0, 2.0, 0.0])
    car := w.add(physics.Body(physics.box([0.3, 0.3, 0.3]), 1.0, [0.0, 2.0, 0.0]))
    j := w.add_joint(physics.slider_joint(rail, car, [0.0, 2.0, 0.0], [1.0, 0.0, 0.0], 0.0 - 1.0, 1.0))
    car.apply_impulse([10.0, 0.0, 0.0])
    i := 0
    while i < 120:
        w.step(1.0 / 60.0)
        assert_true(j.position() < 1.1)
        i += 1
    assert_true(j.position() > 0.9)
    # la gravité n'a pas décroché le chariot du rail
    assert_true(math.abs(car.position[1] - 2.0) < 0.05)
    car.apply_impulse([0.0 - 20.0, 0.0, 0.0])
    k := 0
    while k < 120:
        w.step(1.0 / 60.0)
        assert_true(j.position() > 0.0 - 1.1)
        k += 1
    assert_true(j.position() < 0.0 - 0.9)

testing.test("glissière : limites de course", t_slider)

func t_joint_misc():
    # collide_connected : par défaut, pas de contact entre corps reliés
    w := physics.World()
    w.gravity = [0.0, 0.0, 0.0]
    a := w.add(physics.Body(physics.sphere(1.0), 1.0, [0.0, 0.0, 0.0]))
    b := w.add(physics.Body(physics.sphere(1.0), 1.0, [1.0, 0.0, 0.0]))
    j := w.add_joint(physics.distance_joint(a, b))
    w.step(1.0 / 60.0)
    assert_eq(len(w.contacts), 0)
    j.collide_connected = true
    w.step(1.0 / 60.0)
    assert_true(len(w.contacts) > 0)
    assert_true(w.remove_joint(j))
    assert_false(w.remove_joint(j))
    assert_raises(() => physics.ball_joint(a, a, [0.0, 0.0, 0.0]), "ValueError")
    assert_raises(() => physics.ball_joint(a, null, [0.0, 0.0, 0.0]), "ValueError")
    # supprimer un corps supprime ses articulations
    w3 := physics.World()
    p := w3.add(physics.Body(physics.sphere(0.5), 1.0, [0.0, 0.0, 0.0]))
    q := w3.add(physics.Body(physics.sphere(0.5), 1.0, [2.0, 0.0, 0.0]))
    w3.add_joint(physics.distance_joint(p, q))
    w3.remove(q)
    assert_eq(len(w3.joints), 0)

testing.test("articulations : collisions entre corps reliés, retrait", t_joint_misc)

func t_break_and_sleep():
    w := physics.World()
    top := physics.fixed_point([0.0, 6.0, 0.0])
    heavy := w.add(physics.Body(physics.sphere(0.3), 10.0, [0.0, 4.0, 0.0]))
    j := w.add_joint(physics.distance_joint(top, heavy, [0.0, 6.0, 0.0], [0.0, 4.0, 0.0]))
    j.break_force = 50.0
    i := 0
    while i < 30:
        w.step(1.0 / 60.0)
        i += 1
    assert_true(j.broken)
    assert_false(j.enabled)
    assert_true(heavy.position[1] < 3.5)
    # une chaîne au repos s'endort d'un bloc, puis se réveille d'un bloc
    w2 := physics.World()
    anchor := physics.fixed_point([0.0, 6.0, 0.0])
    b1 := w2.add(physics.Body(physics.sphere(0.2), 1.0, [0.0, 5.0, 0.0]))
    b2 := w2.add(physics.Body(physics.sphere(0.2), 1.0, [0.0, 4.0, 0.0]))
    w2.add_joint(physics.distance_joint(anchor, b1, [0.0, 6.0, 0.0], [0.0, 5.0, 0.0]))
    w2.add_joint(physics.distance_joint(b1, b2, [0.0, 5.0, 0.0], [0.0, 4.0, 0.0]))
    k := 0
    while k < 400:
        w2.step(1.0 / 60.0)
        k += 1
    assert_true(b1.sleeping and b2.sleeping)
    b2.apply_impulse([5.0, 0.0, 0.0])
    w2.step(1.0 / 60.0)
    assert_false(b1.sleeping)
    assert_false(b2.sleeping)

testing.test("rupture et îlots d'endormissement", t_break_and_sleep)

# ---------------------------------------------------------------------------
# Phase large par hachage spatial
# ---------------------------------------------------------------------------

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
    return algorithm.sorted(out, (x) => x)

func t_broadphase_hash():
    w := physics.World()
    ground(w)
    i := 0
    while i < 7:
        j := 0
        while j < 7:
            w.add(physics.Body(physics.sphere(0.5), 1.0, [i * 0.9 - 3.0, 0.5 + (i + j) % 3 * 0.2, j * 0.9 - 3.0]))
            j += 1
        i += 1
    w.broadphase = "sweep"
    ref := pair_ids(w._candidate_pairs())
    w.broadphase = "hash"
    got := pair_ids(w._candidate_pairs())
    assert_eq(got, ref)
    assert_true(len(ref) > 50)
    w.broadphase = "auto"
    assert_eq(pair_ids(w._candidate_pairs()), ref)
    # la simulation reste saine avec le hachage
    k := 0
    while k < 20:
        w.step(1.0 / 60.0)
        k += 1
    assert_true(w.bodies[1].position[1] > 0.0)

testing.test("phase large : hachage spatial = balayage", t_broadphase_hash)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) physics en échec")
print("PHYSICS: OK")
