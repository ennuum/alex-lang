# ALEX - tests du module ecs. Lancer depuis la racine : ./alex run tests/gamedev/test_ecs.al
use ecs
use testing
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises, assert_null

func move_system(world, dt, rows):
    for row in rows:
        p := row[1]
        v := row[2]
        p[0] = p[0] + v[0] * dt
        p[1] = p[1] + v[1] * dt

func t_basic():
    w := ecs.World()
    e := w.create({"position": [0.0, 0.0], "vitesse": [1.0, 0.5]})
    assert_true(w.is_alive(e))
    assert_eq(w.count(), 1)
    assert_true(w.has(e, "position"))
    assert_false(w.has(e, "santé"))
    w.add_system("mouvement", move_system, ["position", "vitesse"])
    w.run(2.0)
    p := w.get(e, "position")
    assert_near(p[0], 2.0)
    assert_near(p[1], 1.0)
    w.remove(e, "vitesse")
    assert_false(w.has(e, "vitesse"))
    assert_null(w.get(e, "vitesse"))

testing.test("entités, composants, systèmes", t_basic)

func t_generations():
    w := ecs.World()
    a := w.create({"x": 1})
    w.destroy(a)
    assert_false(w.is_alive(a))
    b := w.create({"x": 2})
    assert_true(w.is_alive(b))
    assert_false(w.is_alive(a))
    assert_true(a != b)
    assert_null(w.get(a, "x"))
    assert_raises(() => w.add(a, "x", 3), "ValueError")

testing.test("recyclage et générations", t_generations)

func t_query():
    w := ecs.World()
    a := w.create({"p": 1, "v": 1})
    b := w.create({"p": 2})
    c := w.create({"p": 3, "v": 3, "mort": true})
    assert_eq(len(w.query(["p"])), 3)
    assert_eq(len(w.query(["p", "v"])), 2)
    assert_eq(len(w.query(["p", "v"], ["mort"])), 1)
    assert_eq(w.count_with("v"), 2)

testing.test("requêtes", t_query)

func t_hierarchy():
    w := ecs.World()
    root := w.create({"t": 1})
    kid := w.create({"t": 2})
    grand := w.create({"t": 3})
    w.set_parent(kid, root)
    w.set_parent(grand, kid)
    assert_eq(w.parent_of(kid), root)
    assert_eq(len(w.descendants(root)), 2)
    w.destroy(root)
    assert_false(w.is_alive(kid))
    assert_false(w.is_alive(grand))
    assert_eq(w.count(), 0)

testing.test("hiérarchie et destruction récursive", t_hierarchy)

func t_events_resources():
    w := ecs.World()
    w.set_resource("gravité", 9.81)
    assert_near(w.resource("gravité"), 9.81)
    assert_true(w.has_resource("gravité"))
    w.emit("coup", {"dégâts": 3})
    w.emit("coup", {"dégâts": 5})
    assert_eq(len(w.peek("coup")), 2)
    got := w.drain("coup")
    assert_eq(len(got), 2)
    assert_eq(len(w.peek("coup")), 0)

testing.test("ressources et événements", t_events_resources)

func t_prefab_snapshot():
    w := ecs.World()
    w.register_prefab("orc", {"santé": 10, "pos": [0.0, 0.0]})
    o1 := w.spawn("orc", {"santé": 20})
    o2 := w.spawn("orc")
    assert_eq(w.get(o1, "santé"), 20)
    assert_eq(w.get(o2, "santé"), 10)
    # les composants des instances sont indépendants
    w.get(o1, "pos")[0] = 5.0
    assert_near(w.get(o2, "pos")[0], 0.0)
    snap := w.snapshot()
    w.destroy(o1)
    w.restore(snap)
    assert_true(w.is_alive(o1))
    assert_eq(w.count(), 2)
    assert_true(len(w.to_json()) > 2)

testing.test("préfabriqués et instantanés", t_prefab_snapshot)

func t_hooks_defer():
    w := ecs.World()
    log := []
    w.on_add("pv", (world, e, v) => log.append(["add", v]))
    e := w.create({"pv": 10})
    assert_eq(len(log), 1)
    w.defer_destroy(e)
    assert_true(w.is_alive(e))
    w.flush()
    assert_false(w.is_alive(e))

testing.test("hooks et opérations différées", t_hooks_defer)

func t_phases_priority():
    w := ecs.World()
    order := []
    w.add_system("b", (world, dt, rows) => order.append("b"), null, "update", 5)
    w.add_system("a", (world, dt, rows) => order.append("a"), null, "update", 1)
    w.run(0.1)
    assert_eq(len(order), 2)
    assert_eq(w.system_order("update")[0], "a")

testing.test("priorité des systèmes", t_phases_priority)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) ecs en échec")
print("ECS: OK")
