# ALEX - tests du module tilemap (import Tiled .tmj / .tmx, collisions). ./alex run tests/gamedev/test_tilemap.al
use tilemap
use testing
from testing use assert_eq, assert_true, assert_near

const DATA := "tests/gamedev/data/"

func check_map(m):
    assert_eq([m.width, m.height, m.tilewidth, m.tileheight], [6, 4, 16, 16])
    assert_near(m.properties["gravite"], 9.5)
    assert_eq(len(m.tilesets), 1)
    ts := m.tilesets[0]
    assert_eq(ts.columns, 4)
    assert_true(ts.image != null and ts.image[len(ts.image) - 10:len(ts.image)] == "tuiles.png")
    assert_eq(ts.source_rect(2), [32, 0, 16, 16])
    assert_eq(ts.tiles[3]["animation"], [[2, 0.1], [3, 0.1]])
    sol := m.layer("sol")
    assert_eq(sol.gid(0, 3), 1)
    assert_eq(sol.gid(4, 2), 2)
    assert_eq(sol.gid(0, 0), 0)
    assert_eq(sol.gid(-1, 0), 0)
    assert_eq(m.tile_properties(1)["solide"], true)
    deco := m.layer("deco")
    assert_eq(deco.gid(0, 0), 4)
    assert_eq(deco.raw(1, 0), 3 | tilemap.FLIP_H)
    assert_eq(tilemap.flip_flags(deco.raw(1, 0)), 4)
    assert_eq(tilemap.flip_flags(deco.raw(2, 0)), 1)
    o := m.object_named("depart")
    assert_eq(o["type"], "joueur")
    assert_eq(o["shape"], "point")
    assert_eq(o["properties"]["vies"], 3)
    z := m.objects("piege")
    assert_eq(len(z), 1)
    assert_eq(z[0]["shape"], "polygon")
    assert_eq(len(z[0]["points"]), 3)
    assert_eq(m.layer("objets").offset, [5.0, 0.0])

func t_tmj():
    check_map(tilemap.load(DATA + "niveau.tmj"))

testing.test("Tiled JSON (base64 + zlib, groupe, objets)", t_tmj)

func t_tmx():
    check_map(tilemap.load(DATA + "niveau.tmx"))

testing.test("Tiled TMX (csv, base64 + gzip, tileset externe)", t_tmx)

func t_collisions():
    m := tilemap.load(DATA + "niveau.tmj")
    sol := m.layer("sol")
    rects := m.solid_rects(sol)
    assert_eq(rects, [[64, 32, 16, 16], [0, 48, 96, 16]])
    seul := m.solid_rects(sol, (g, p) => "solide" in p and p["solide"])
    assert_eq(seul, [[0, 48, 96, 16]])
    assert_true(m.overlaps(sol, [10, 40, 8, 10]))
    assert_true(not m.overlaps(sol, [10, 20, 8, 10]))
    r := m.move(sol, [10, 20, 8, 10], 0, 40)            # chute : s'arrête sur le sol (y = 48)
    assert_true(r["hit_y"])
    assert_true(r["on_ground"])
    assert_near(r["rect"][1], 38.0)
    r = m.move(sol, [40, 34, 8, 10], 30, 0)             # mur : la tuile (4, 2) commence à x = 64
    assert_true(r["hit_x"])
    assert_near(r["rect"][0], 56.0)
    t := tilemap.TileMap(4, 4, 8, 8)
    l := t.add_tile_layer("x")
    l.set(1, 1, 5, tilemap.FLIP_V)
    assert_eq(l.gid(1, 1), 5)
    assert_eq(l.version, 1)

testing.test("collisions, déplacement, couche générée", t_collisions)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) tilemap en échec")
print("TILEMAP: OK")
