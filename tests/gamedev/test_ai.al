# ALEX - tests du module ai. Lancer depuis la racine : ./alex run tests/gamedev/test_ai.al
use ai
use math3d
use testing
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises, assert_null, assert_not_null

func t_grid_path():
    g := ai.grid_from_rows(["..#.", "..#.", "...."])
    p := ai.find_path(g, [0, 0], [3, 0])
    assert_not_null(p)
    assert_eq(p[0], [0, 0])
    assert_eq(p[len(p) - 1], [3, 0])
    assert_near(ai.path_cost(g, p), 6.414213562, 0.0001)
    for c in p:
        assert_true(g.walkable(c[0], c[1]))
    assert_eq(ai.find_path(g, [1, 1], [1, 1]), [[1, 1]])

testing.test("A* sur grille", t_grid_path)

func t_unreachable():
    g := ai.grid_from_rows([".#.", ".#.", ".#."])
    assert_null(ai.find_path(g, [0, 0], [2, 0]))
    blocked := ai.grid_from_rows(["#.", ".."])
    assert_null(ai.find_path(blocked, [0, 0], [1, 1]))
    assert_raises(() => ai.find_path(g, [0, 0], [9, 9]), "ValueError")

testing.test("but inaccessible et hors grille", t_unreachable)

func t_corner_cutting():
    g := ai.grid_from_rows([".#", "#."])
    assert_null(ai.find_path(g, [0, 0], [1, 1]))
    open := ai.grid_from_rows(["..", ".."])
    p := ai.find_path(open, [0, 0], [1, 1])
    assert_eq(len(p), 2)
    four := ai.find_path(open, [0, 0], [1, 1], false, "manhattan")
    assert_eq(len(four), 3)

testing.test("pas de coupe-coin et 4 directions", t_corner_cutting)

func t_costs_optimal():
    # le couloir du haut est cher (coût 9), celui du bas est libre : A* doit contourner
    g := ai.grid_from_rows(["999", "...", "..."])
    p := ai.find_path(g, [0, 1], [2, 1])
    for c in p:
        assert_true(c[1] != 0)
    d := ai.find_path(g, [0, 1], [2, 1], true, "zero")
    assert_near(ai.path_cost(g, d), ai.path_cost(g, p), 0.0001)

testing.test("coûts de case et optimalité", t_costs_optimal)

func t_large_open_grid():
    g := ai.Grid(40, 40)
    g.block_rect(10, 0, 2, 35)
    g.block_rect(25, 5, 2, 35)
    p := ai.find_path(g, [0, 0], [39, 39])
    assert_not_null(p)
    assert_eq(p[len(p) - 1], [39, 39])
    assert_null(ai.find_path(g, [0, 0], [39, 39], true, "octile", 5))

testing.test("grande grille et limite max_nodes", t_large_open_grid)

func t_los_smooth():
    g := ai.grid_from_rows(["......", "..##..", "..##..", "......"])
    assert_true(ai.line_of_sight(g, [0, 0], [5, 0]))
    assert_false(ai.line_of_sight(g, [0, 1], [5, 1]))
    p := ai.find_path(g, [0, 0], [5, 3])
    s := ai.smooth_path(g, p)
    assert_true(len(s) <= len(p))
    assert_eq(s[0], [0, 0])
    assert_eq(s[len(s) - 1], [5, 3])
    i := 1
    while i < len(s):
        assert_true(ai.line_of_sight(g, s[i - 1], s[i]))
        i += 1

testing.test("ligne de vue et lissage", t_los_smooth)

func t_distance_map():
    g := ai.grid_from_rows(["..#", "..#", "..."])
    dm := ai.distance_map(g, [0, 0])
    assert_near(dm[0], 0.0)
    assert_near(dm[1], 1.0)
    assert_true(dm[2 * 3 + 2] > 2.0)
    assert_near(dm[2], -1.0)
    assert_eq(len(ai.reachable(g, [0, 0])), 7)
    assert_true(len(ai.reachable(g, [0, 0], 1.0)) == 3)

testing.test("carte de distances", t_distance_map)

func nb(n):
    out := []
    if n * 2 <= 100:
        out.append(n * 2)
    if n + 3 <= 100:
        out.append(n + 3)
    return out

func t_graph():
    p := ai.graph_search(1, 25, nb, (a, b) => 1.0)
    assert_not_null(p)
    assert_eq(p[0], 1)
    assert_eq(p[len(p) - 1], 25)
    i := 1
    while i < len(p):
        assert_true(p[i] == p[i - 1] * 2 or p[i] == p[i - 1] + 3)
        i += 1
    assert_null(ai.graph_search(1, 1000, nb, (a, b) => 1.0))

testing.test("A* sur graphe générique", t_graph)

func t_fsm():
    log := []
    owner := {"faim": 0, "danger": false}
    fsm := ai.StateMachine(owner)
    fsm.add_state("repos", (o, prev) => log.append("enter repos"), (o, dt) => log.append("zzz"))
    fsm.add_state("fuite", (o, prev) => log.append("enter fuite"), null, (o, nxt) => log.append("exit fuite"))
    fsm.add_transition("repos", "fuite", (o) => o["danger"])
    fsm.add_transition("fuite", "repos", (o) => not o["danger"])
    fsm.start("repos")
    fsm.update(0.1)
    assert_true(fsm.is_in("repos"))
    owner["danger"] = true
    fsm.update(0.1)
    assert_true(fsm.is_in("fuite"))
    assert_near(fsm.time_in_state, 0.1)
    owner["danger"] = false
    fsm.update(0.1)
    assert_true(fsm.is_in("repos"))
    assert_eq(log[0], "enter repos")
    assert_true("exit fuite" in log)
    assert_raises(() => fsm.add_transition("repos", "inconnu", (o) => true), "ValueError")
    assert_raises(() => ai.StateMachine().update(0.1), "ValueError")

testing.test("machine à états", t_fsm)

func t_bt():
    ctx := {"faim": true, "n": 0}
    manger := ai.Action((c, dt) => "success")
    errer := ai.Action((c, dt) => "success")
    tree := ai.Selector([ai.Sequence([ai.Condition((c) => c["faim"]), manger]), errer])
    assert_eq(tree.tick(ctx, 0.1), "success")
    ctx["faim"] = false
    assert_eq(tree.tick(ctx, 0.1), "success")
    inv := ai.Inverter(ai.Condition((c) => c["faim"]))
    assert_eq(inv.tick(ctx, 0.1), "success")
    seq := ai.Sequence([ai.Wait(1.0), ai.Action((c, dt) => "success")])
    assert_eq(seq.tick(ctx, 0.5), "running")
    assert_eq(seq.tick(ctx, 0.6), "success")
    rep := ai.Repeat(ai.Action((c, dt) => c["n"] == c["n"] and "success"), 3)
    assert_eq(rep.tick(ctx, 0.1), "running")
    assert_eq(rep.tick(ctx, 0.1), "running")
    assert_eq(rep.tick(ctx, 0.1), "success")
    fail := ai.Succeeder(ai.Action((c, dt) => "failure"))
    assert_eq(fail.tick(ctx, 0.1), "success")

testing.test("arbres de comportement", t_bt)

func t_steering():
    v := ai.seek([0.0, 0.0, 0.0], [10.0, 0.0, 0.0], 4.0)
    assert_true(math3d.vec3_equals(v, [4.0, 0.0, 0.0]))
    f := ai.flee([0.0, 0.0, 0.0], [10.0, 0.0, 0.0], 4.0)
    assert_true(math3d.vec3_equals(f, [-4.0, 0.0, 0.0]))
    far := ai.arrive([0.0, 0.0, 0.0], [20.0, 0.0, 0.0], 5.0, 4.0)
    assert_near(far[0], 5.0, 0.0001)
    near := ai.arrive([0.0, 0.0, 0.0], [2.0, 0.0, 0.0], 5.0, 4.0)
    assert_near(near[0], 2.5, 0.0001)
    assert_true(math3d.vec3_equals(ai.arrive([1.0, 1.0, 1.0], [1.0, 1.0, 1.0], 5.0, 4.0), [0.0, 0.0, 0.0]))
    p := ai.pursue([0.0, 0.0, 0.0], 5.0, [10.0, 0.0, 0.0], [0.0, 0.0, 5.0])
    assert_true(p[2] > 0.0)
    sep := ai.separation([0.0, 0.0, 0.0], [[1.0, 0.0, 0.0]], 3.0)
    assert_true(sep[0] < 0.0)
    assert_true(math3d.vec3_equals(ai.separation([0.0, 0.0, 0.0], [[9.0, 0.0, 0.0]], 3.0), [0.0, 0.0, 0.0]))
    av := ai.avoid_obstacles([0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [[[5.0, 0.2, 0.0], 1.0]], 10.0, 3.0)
    assert_near(math3d.vec3_length(av), 3.0, 0.0001)
    assert_true(math3d.vec3_equals(ai.avoid_obstacles([0.0, 0.0, 0.0], [1.0, 0.0, 0.0], [[[5.0, 5.0, 0.0], 1.0]], 10.0, 3.0), [0.0, 0.0, 0.0]))

testing.test("comportements de pilotage", t_steering)

func t_steer_converges():
    vel := [0.0, 0.0, 0.0]
    pos := [0.0, 0.0, 0.0]
    i := 0
    while i < 600:
        d := ai.arrive(pos, [10.0, 0.0, 0.0], 4.0, 3.0)
        vel = ai.steer(vel, d, 20.0, 1.0 / 60.0)
        pos = math3d.vec3_madd(pos, vel, 1.0 / 60.0)
        i += 1
    assert_true(math3d.vec3_distance(pos, [10.0, 0.0, 0.0]) < 0.1)

testing.test("arrivée par pilotage", t_steer_converges)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) ai en échec")
print("AI: OK")
