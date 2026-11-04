# ALEX - tests du module mesh. Lancer depuis la racine : ./alex run tests/gamedev/test_mesh.al
use mesh
use math3d
use testing
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises

func t_primitives():
    b := mesh.box(2.0, 1.0, 1.0)
    assert_eq(b.vertex_count(), 24)
    assert_eq(b.triangle_count(), 12)
    assert_near(b.volume(), 2.0, 0.0001)
    assert_near(b.surface_area(), 10.0, 0.0001)
    s := mesh.sphere(1.0, 32, 16)
    assert_true(s.volume() > 4.0 and s.volume() < 4.2)
    for m in [mesh.plane(2.0, 2.0, 2, 2), mesh.cylinder(), mesh.cone(), mesh.capsule(), mesh.torus(), mesh.icosphere(0.5, 2), mesh.disc()]:
        assert_true(m.triangle_count() > 0)
        assert_true(m.validate())

testing.test("primitives", t_primitives)

func t_bounds_transform():
    b := mesh.box(2.0, 2.0, 2.0)
    bb := b.bounds()
    assert_true(math3d.vec3_equals(bb[0], [-1.0, -1.0, -1.0]))
    assert_true(math3d.vec3_equals(bb[1], [1.0, 1.0, 1.0]))
    t := b.transformed(math3d.mat4_translation(10.0, 0.0, 0.0))
    assert_true(math3d.vec3_equals(t.bounds()[0], [9.0, -1.0, -1.0]))
    assert_true(math3d.vec3_equals(b.bounds()[0], [-1.0, -1.0, -1.0]))
    r := t.copy()
    r.recenter()
    assert_true(math3d.vec3_equals(math3d.aabb_center(r.bounds()), [0.0, 0.0, 0.0], 0.0001))

testing.test("bornes et transformations", t_bounds_transform)

func t_manual():
    m := mesh.Mesh("tri")
    a := m.add_vertex([0.0, 0.0, 0.0])
    b := m.add_vertex([1.0, 0.0, 0.0])
    c := m.add_vertex([0.0, 1.0, 0.0])
    m.add_triangle(a, b, c)
    m.compute_normals()
    assert_true(m.has_normals())
    assert_true(math3d.vec3_equals(m.triangle_normal(0), [0.0, 0.0, 1.0]))
    assert_near(m.triangle_area(0), 0.5)
    m.flip_winding()
    assert_true(math3d.vec3_equals(m.triangle_normal(0), [0.0, 0.0, -1.0]))

testing.test("maillage construit à la main", t_manual)

func t_obj():
    src := "# test\nv 0 0 0\nv 1 0 0\nv 1 1 0\nv 0 1 0\nvt 0 0\nvt 1 0\nvt 1 1\nvt 0 1\nvn 0 0 1\nf 1/1/1 2/2/1 3/3/1 4/4/1\n"
    m := mesh.parse_obj(src)
    assert_eq(m.triangle_count(), 2)
    assert_true(m.has_uvs())
    assert_near(m.surface_area(), 1.0)
    text := mesh.to_obj(m)
    m2 := mesh.parse_obj(text)
    assert_eq(m2.triangle_count(), 2)
    assert_near(m2.surface_area(), 1.0)
    neg := mesh.parse_obj("v 0 0 0\nv 1 0 0\nv 0 1 0\nf -3 -2 -1\n")
    assert_eq(neg.triangle_count(), 1)
    assert_raises(() => mesh.parse_obj("v 0 0 0\nf 1 2 9\n"))

testing.test("OBJ aller-retour", t_obj)

func t_interleaved():
    m := mesh.box(1.0, 1.0, 1.0)
    d := m.to_interleaved("pnu")
    assert_eq(len(d), m.vertex_count() * 8)

testing.test("tampon entrelacé", t_interleaved)

func t_gltf():
    src := "{\"asset\": {\"version\": \"2.0\"}, \"scene\": 0, \"scenes\": [{\"nodes\": [0]}], \"nodes\": [{\"mesh\": 0, \"translation\": [5, 0, 0]}], \"meshes\": [{\"name\": \"tri\", \"primitives\": [{\"attributes\": {\"POSITION\": 0}, \"indices\": 1}]}], \"buffers\": [{\"byteLength\": 44, \"uri\": \"data:application/octet-stream;base64,AAAAAAAAAAAAAAAAAACAPwAAAAAAAAAAAAAAAAAAgD8AAAAAAAABAAIAAAA=\"}], \"bufferViews\": [{\"buffer\": 0, \"byteOffset\": 0, \"byteLength\": 36}, {\"buffer\": 0, \"byteOffset\": 36, \"byteLength\": 6}], \"accessors\": [{\"bufferView\": 0, \"componentType\": 5126, \"count\": 3, \"type\": \"VEC3\", \"min\": [0, 0, 0], \"max\": [1, 1, 0]}, {\"bufferView\": 1, \"componentType\": 5123, \"count\": 3, \"type\": \"SCALAR\"}]}"
    ms := mesh.parse_gltf(src)
    assert_eq(len(ms), 1)
    assert_eq(ms[0].triangle_count(), 1)
    assert_eq(ms[0].name, "tri")
    assert_true(math3d.vec3_equals(ms[0].bounds()[0], [5.0, 0.0, 0.0]))
    assert_true(math3d.vec3_equals(ms[0].bounds()[1], [6.0, 1.0, 0.0]))
    assert_raises(() => mesh.parse_gltf("{\"asset\": {\"version\": \"2.0\"}, \"buffers\": [{\"byteLength\": 4, \"uri\": \"data:application/octet-stream;base64,AAAA\"}], \"bufferViews\": [{\"buffer\": 0, \"byteLength\": 99}], \"accessors\": [{\"bufferView\": 0, \"componentType\": 5126, \"count\": 3, \"type\": \"VEC3\"}], \"meshes\": [{\"primitives\": [{\"attributes\": {\"POSITION\": 0}}]}], \"nodes\": [{\"mesh\": 0}], \"scenes\": [{\"nodes\": [0]}]}"))

testing.test("glTF intégré (base64)", t_gltf)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) mesh en échec")
print("MESH: OK")
