# ALEX - tests du module physics.spatial. Lancer depuis la racine : ./alex run tests/gamedev/test_spatial.al
use physics.spatial as sp
use testing
from core use len
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises, assert_null, assert_not_null

func t_basic():
    h := sp.SpatialHash(2.0)
    h.insert(1, [0.0, 0.0, 0.0], [1.0, 1.0, 1.0])
    h.insert(2, [0.5, 0.5, 0.5], [2.0, 2.0, 2.0])
    h.insert(3, [20.0, 0.0, 0.0], [21.0, 1.0, 1.0])
    assert_eq(h.size(), 3)
    assert_eq(h.query_aabb([0.0, 0.0, 0.0], [0.6, 0.6, 0.6]), [1, 2])
    assert_eq(h.query_aabb([19.0, 0.0, 0.0], [22.0, 1.0, 1.0]), [3])
    assert_eq(h.query_point([0.7, 0.7, 0.7]), [1, 2])
    assert_eq(h.pairs(), [[1, 2]])
    h.update(2, [20.5, 0.5, 0.5], [21.5, 1.5, 1.5])
    assert_eq(h.pairs(), [[2, 3]])
    assert_true(h.remove(3))
    assert_false(h.remove(3))
    assert_eq(h.pairs(), [])
    assert_raises(() => h.insert(1, [0.0, 0.0, 0.0], [1.0, 1.0, 1.0]))
    assert_raises(() => sp.SpatialHash(0.0))

testing.test("insertion, requêtes, paires, mise à jour", t_basic)

func t_negative_and_sphere():
    h := sp.SpatialHash(1.0)
    h.insert(7, [-3.5, -0.5, -2.0], [-2.5, 0.5, -1.0])
    h.insert(8, [4.0, 4.0, 4.0], [5.0, 5.0, 5.0])
    assert_eq(h.query_aabb([-4.0, -1.0, -3.0], [-3.0, 1.0, 0.0]), [7])
    assert_eq(h.query_sphere([-3.0, 0.0, -1.5], 0.4), [7])
    assert_eq(h.query_sphere([0.0, 0.0, 0.0], 1.0), [])
    assert_eq(h.query_sphere([0.0, 0.0, 0.0], 8.0), [7, 8])

testing.test("coordonnées négatives et sphères", t_negative_and_sphere)

func t_ray_and_large():
    h := sp.SpatialHash(1.0, 64)
    h.insert(1, [5.0, -0.5, -0.5], [6.0, 0.5, 0.5])
    h.insert(2, [10.0, 3.0, 3.0], [11.0, 4.0, 4.0])
    h.insert(3, [-1000.0, -1.0, -1000.0], [1000.0, 0.0, 1000.0])
    assert_eq(h.query_ray([0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 50.0), [1, 3])
    assert_eq(h.query_ray([0.0, 0.0, 0.0], [1.0, 0.0, 0.0], 3.0), [3])
    assert_eq(h.query_ray([10.5, 10.0, 3.5], [0.0, -1.0, 0.0], 50.0), [2, 3])
    assert_eq(h.query_aabb([5.0, 0.0, 0.0], [5.5, 0.4, 0.4]), [1, 3])
    big := h.pairs()
    assert_eq(len(big), 1)
    assert_eq(big[0], [1, 3])

testing.test("rayon (DDA) et grands objets", t_ray_and_large)

func t_suggest():
    s := sp.suggest_cell_size([[[0.0, 0.0, 0.0], [1.0, 1.0, 1.0]], [[2.0, 0.0, 0.0], [3.0, 1.0, 1.0]], [[-5000.0, 0.0, -5000.0], [5000.0, 0.0, 5000.0]]])
    assert_near(s, 2.0, 0.001)

testing.test("taille de cellule conseillée", t_suggest)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) spatial en échec")
print("SPATIAL: OK")
