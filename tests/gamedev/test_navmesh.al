# ALEX - tests du navmesh 3D (module ai). Lancer depuis la racine : ./alex run tests/gamedev/test_navmesh.al
use ai
use math
use testing
from collections use append
from core use len
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises, assert_null, assert_not_null

# Grille de n x n cases de côté s dans le plan XZ à partir de (x0, z0), à la hauteur y ; les cases dont keep(i, j) est
# faux sont omises. Triangles en sens trigonométrique vu de dessus (normale +Y).
func grid_mesh(n, s, x0, z0, y, keep):
    pos := []
    idx := []
    j := 0
    while j <= n:
        i := 0
        while i <= n:
            append(pos, [x0 + i * s, y, z0 + j * s])
            i += 1
        j += 1
    j = 0
    while j < n:
        i := 0
        while i < n:
            if keep(i, j):
                a := j * (n + 1) + i
                b := a + 1
                c := a + (n + 1)
                d := c + 1
                append(idx, a)
                append(idx, c)
                append(idx, b)
                append(idx, b)
                append(idx, c)
                append(idx, d)
            i += 1
        j += 1
    return [pos, idx]

func all_cells(i, j):
    return true

func t_build_and_height():
    g := grid_mesh(4, 2.0, 0.0, 0.0, 1.5, all_cells)
    nm := ai.NavMesh(g[0], g[1])
    assert_eq(nm.triangle_count(), 32)
    assert_near(nm.height_at(3.3, 4.1, 1.0), 1.5, 0.0001)
    assert_null(nm.height_at(20.0, 4.1, 1.0))
    cp := nm.closest_point([-3.0, 1.5, 4.0])
    assert_near(cp["point"][0], 0.0, 0.0001)
    assert_near(cp["point"][2], 4.0, 0.0001)
    assert_near(cp["distance"], 3.0, 0.0001)
    assert_raises(() => ai.NavMesh([[0.0, 0.0, 0.0]], [0, 0]), "ValueError")

testing.test("construction, hauteur, point le plus proche", t_build_and_height)

func t_straight_and_corner():
    # sol en L : 6x6 cases, on retire le quart haut-droit pour obliger à contourner l'angle
    g := grid_mesh(6, 1.0, 0.0, 0.0, 0.0, (i, j) => not (i >= 2 and j >= 2))
    nm := ai.NavMesh(g[0], g[1])
    p := nm.find_path([0.5, 0.0, 5.5], [5.5, 0.0, 0.5])
    assert_not_null(p)
    # chemin direct impossible : passe par le coin (2, 0, 2)
    assert_true(len(p) >= 3)
    found := false
    for q in p:
        if math.abs(q[0] - 2.0) < 0.001 and math.abs(q[2] - 2.0) < 0.001:
            found = true
    assert_true(found)
    expect := math.sqrt(1.5 * 1.5 + 3.5 * 3.5) + math.sqrt(3.5 * 3.5 + 1.5 * 1.5)
    assert_near(ai.path_length_3d(p), expect, 0.01)
    # ligne droite sur un sol dégagé : deux points seulement
    full := grid_mesh(6, 1.0, 0.0, 0.0, 0.0, all_cells)
    nf := ai.NavMesh(full[0], full[1])
    q := nf.find_path([0.5, 0.0, 0.5], [5.5, 0.0, 4.5])
    assert_eq(len(q), 2)
    assert_true(nm.line_of_sight([0.5, 0.0, 5.5], [1.5, 0.0, 0.5]))
    assert_false(nm.line_of_sight([0.5, 0.0, 5.5], [5.5, 0.0, 0.5]))
    r := nm.raycast([0.5, 0.0, 5.5], [5.5, 0.0, 0.5])
    assert_false(r["clear"])
    assert_true(r["point"][0] < 3.0)

testing.test("chemin droit, contournement d'angle, rayons", t_straight_and_corner)

func t_blocking_and_cost():
    g := grid_mesh(6, 1.0, 0.0, 0.0, 0.0, all_cells)
    nm := ai.NavMesh(g[0], g[1])
    base := nm.find_path([0.5, 0.0, 3.0], [5.5, 0.0, 3.0])
    assert_near(ai.path_length_3d(base), 5.0, 0.001)
    # mur au milieu avec une porte en haut : le chemin doit contourner
    n := nm.block_region([3.0, 0.0, 2.0], 1.9)
    assert_true(n > 0)
    around := nm.find_path([0.5, 0.0, 1.0], [5.5, 0.0, 1.0])
    assert_not_null(around)
    assert_true(ai.path_length_3d(around) > 5.2)
    assert_false(nm.line_of_sight([0.5, 0.0, 1.0], [5.5, 0.0, 1.0]))
    # tout bloquer : inaccessible
    nm.block_region([3.0, 0.0, 3.0], 20.0)
    assert_null(nm.find_path([0.5, 0.0, 1.0], [5.5, 0.0, 1.0]))
    nm.block_region([3.0, 0.0, 3.0], 20.0, false)
    assert_not_null(nm.find_path([0.5, 0.0, 1.0], [5.5, 0.0, 1.0]))
    # zone coûteuse : le chemin évite la bande lente
    h := grid_mesh(6, 1.0, 0.0, 0.0, 0.0, all_cells)
    nc := ai.NavMesh(h[0], h[1])
    t := 0
    while t < nc.triangle_count():
        c := nc.centers[t]
        if c[0] > 2.0 and c[0] < 4.0 and c[2] > 1.0 and c[2] < 5.0:
            nc.set_cost(t, 20.0)
        t += 1
    slow := nc.find_path([0.5, 0.0, 3.0], [5.5, 0.0, 3.0])
    assert_true(ai.path_length_3d(slow) > 5.5)
    assert_raises(() => nc.set_cost(0, 0.5), "ValueError")

testing.test("blocage dynamique et coûts de zone", t_blocking_and_cost)

func t_slope_and_levels():
    # rampe : un sol à y = 0 et un plan incliné ; max_slope filtre la face trop raide
    pos := [[0.0, 0.0, 0.0], [4.0, 0.0, 0.0], [0.0, 0.0, 4.0], [4.0, 0.0, 4.0], [8.0, 4.0, 0.0], [8.0, 4.0, 4.0]]
    idx := [0, 2, 1, 1, 2, 3, 1, 3, 4, 4, 3, 5]
    steep := ai.NavMesh(pos, idx, 30.0)
    assert_eq(steep.triangle_count(), 2)
    ramp := ai.NavMesh(pos, idx, 80.0)
    assert_eq(ramp.triangle_count(), 4)
    # deux étages superposés : le chemin reste à l'étage de départ
    lo := grid_mesh(4, 1.0, 0.0, 0.0, 0.0, all_cells)
    hi := grid_mesh(4, 1.0, 0.0, 0.0, 5.0, all_cells)
    pos2 := []
    idx2 := []
    for p in lo[0]:
        append(pos2, p)
    for q in lo[1]:
        append(idx2, q)
    off := len(lo[0])
    for p in hi[0]:
        append(pos2, p)
    for q in hi[1]:
        append(idx2, q + off)
    two := ai.NavMesh(pos2, idx2)
    assert_near(two.height_at(1.5, 1.5, 0.2), 0.0, 0.0001)
    assert_near(two.height_at(1.5, 1.5, 4.8), 5.0, 0.0001)
    pth := two.find_path([0.5, 0.2, 0.5], [3.5, 0.2, 3.5])
    for q in pth:
        assert_near(q[1], 0.0, 0.0001)
    # les deux étages ne sont pas reliés
    assert_null(two.find_path([0.5, 0.2, 0.5], [3.5, 4.8, 3.5]))

testing.test("pentes et étages superposés", t_slope_and_levels)

func t_radius_and_random():
    g := grid_mesh(6, 1.0, 0.0, 0.0, 0.0, (i, j) => not (i >= 2 and j >= 2))
    nm := ai.NavMesh(g[0], g[1])
    plain := nm.find_path([0.5, 0.0, 5.5], [5.5, 0.0, 0.5])
    wide := nm.find_path([0.5, 0.0, 5.5], [5.5, 0.0, 0.5], 0.4)
    assert_not_null(wide)
    assert_true(ai.path_length_3d(wide) >= ai.path_length_3d(plain) - 0.0001)
    # marge : aucun point de passage intermédiaire n'est sur l'angle exact
    interior := wide[1]
    assert_true(math.abs(interior[0] - 2.0) > 0.01 or math.abs(interior[2] - 2.0) > 0.01)
    seed := [12345]
    rnd := () => lcg(seed)
    k := 0
    while k < 50:
        p := nm.random_point(rnd)
        assert_not_null(p)
        assert_true(not (p[0] > 2.0001 and p[2] > 2.0001))
        assert_true(p[0] >= 0.0 and p[0] <= 6.0 and p[2] >= 0.0 and p[2] <= 6.0)
        k += 1

func lcg(seed):
    seed[0] = (seed[0] * 1103515245 + 12345) % 2147483648
    return seed[0] / 2147483648.0

testing.test("rayon d'agent et points aléatoires", t_radius_and_random)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) navmesh en échec")
print("NAVMESH: OK")
