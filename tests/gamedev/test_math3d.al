# ALEX - tests du module math3d. Lancer depuis la racine : ./alex run tests/gamedev/test_math3d.al
use math3d
use graphics.shader as sh
use testing
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises

func near3(a, b):
    return math3d.vec3_equals(a, b, 0.00001)

func t_vec3():
    assert_near(math3d.vec3_length([1.0, 2.0, 2.0]), 3.0)
    assert_true(near3(math3d.vec3_cross([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]), [0.0, 0.0, 1.0]))
    assert_true(near3(math3d.vec3_normalize([0.0, 0.0, 0.0]), [0.0, 0.0, 0.0]))
    assert_true(near3(math3d.vec3_reflect([1.0, -1.0, 0.0], [0.0, 1.0, 0.0]), [1.0, 1.0, 0.0]))
    assert_near(math3d.vec3_angle_between([1.0, 0.0, 0.0], [0.0, 1.0, 0.0]), math3d.HALF_PI)

testing.test("vec3", t_vec3)

func t_quat():
    q := math3d.quat_from_axis_angle([0.0, 1.0, 0.0], math3d.HALF_PI)
    assert_true(near3(math3d.quat_rotate(q, [1.0, 0.0, 0.0]), [0.0, 0.0, -1.0]))
    h := math3d.quat_slerp(math3d.quat_identity(), q, 0.5)
    assert_near(math3d.quat_angle_between(math3d.quat_identity(), h), math3d.HALF_PI / 2.0, 0.0001)
    lr := math3d.quat_look_rotation([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    assert_true(near3(math3d.quat_rotate(lr, [0.0, 0.0, -1.0]), [1.0, 0.0, 0.0]))
    ft := math3d.quat_from_to([1.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    assert_true(near3(math3d.quat_rotate(ft, [1.0, 0.0, 0.0]), [0.0, 1.0, 0.0]))
    inv := math3d.quat_mul(q, math3d.quat_inverse(q))
    assert_true(math3d.quat_equals(inv, math3d.quat_identity()))

testing.test("quaternions", t_quat)

func t_mat4():
    q := math3d.quat_from_axis_angle(math3d.vec3_normalize([1.0, 2.0, 3.0]), 0.9)
    m := math3d.mat4_compose([1.0, 2.0, 3.0], q, [2.0, 1.0, 0.5])
    assert_true(math3d.mat4_equals(math3d.mat4_mul(m, math3d.mat4_inverse(m)), math3d.mat4_identity(), 0.00001))
    d := math3d.mat4_decompose(m)
    assert_true(near3(d[0], [1.0, 2.0, 3.0]))
    assert_true(near3(d[2], [2.0, 1.0, 0.5]))
    assert_true(math3d.quat_equals(d[1], q, 0.00001))
    p := math3d.mat4_transform_point(math3d.mat4_translation(1.0, 2.0, 3.0), [1.0, 1.0, 1.0])
    assert_true(near3(p, [2.0, 3.0, 4.0]))
    singular := math3d.mat4_scaling(1.0, 0.0, 1.0)
    assert_raises(() => math3d.mat4_inverse(singular))

testing.test("mat4", t_mat4)

# Les matrices de math3d sont en ordre COLONNE ; graphics.shader attend l'ordre LIGNE : transposer.
func t_interop_shader():
    eye := [0.0, 2.0, 5.0]
    mine := math3d.mat4_look_at(eye, [0.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    theirs := sh.look_at(eye, [0.0, 0.0, 0.0], [0.0, 1.0, 0.0])
    assert_true(math3d.mat4_equals(math3d.mat4_transpose(mine), theirs, 0.00001))
    pm := math3d.mat4_perspective(1.0, 1.5, 0.1, 50.0)
    ps := sh.perspective(1.0, 1.5, 0.1, 50.0)
    assert_true(math3d.mat4_equals(math3d.mat4_transpose(pm), ps, 0.00001))

testing.test("interop graphics.shader (transposition)", t_interop_shader)

func t_aabb_plane():
    b := math3d.aabb([-1.0, -1.0, -1.0], [1.0, 1.0, 1.0])
    assert_true(math3d.aabb_contains_point(b, [0.0, 0.5, 0.0]))
    assert_false(math3d.aabb_contains_point(b, [2.0, 0.0, 0.0]))
    pl := math3d.plane_from_normal_point([0.0, 1.0, 0.0], [0.0, 2.0, 0.0])
    assert_near(math3d.plane_distance(pl, [0.0, 5.0, 0.0]), 3.0)

testing.test("aabb et plan", t_aabb_plane)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) math3d en échec")
print("MATH3D: OK")
