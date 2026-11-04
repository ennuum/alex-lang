# ALEX - tests des extensions de ffi (adresses, tableaux en bloc, flottants). ./alex run tests/gamedev/test_ffi_ext.al
use ffi
use testing
from testing use assert_eq, assert_true, assert_near, assert_raises

func t_float_call():
    m := ffi.Library("m")
    assert_near(m.function("cos", ["f64"], "f64").call([0.0]), 1.0)
    assert_near(m.function("powf", ["f32", "f32"], "f32").call([2.0, 10.0]), 1024.0)
    assert_near(m.function("fma", ["f64", "f64", "f64"], "f64").call([2.0, 3.0, 1.0]), 7.0)

testing.test("appels flottants", t_float_call)

func t_function_at():
    c := ffi.Library("c")
    a := c.address("strlen")
    assert_true(a != 0)
    assert_eq(c.address("symbole_qui_n_existe_pas"), 0)
    f := ffi.function_at(a, "strlen", ["cstr"], "u64")
    assert_eq(f.call1("bonjour"), 7)
    assert_raises(() => ffi.function_at(0, "x", [], "void"))

testing.test("fonction par adresse", t_function_at)

func t_arrays():
    b := ffi.Buffer(64)
    assert_eq(b.write_array("f32", [1.5, 2.5, -3.25]), 12)
    assert_eq(b.read_array("f32", 3), [1.5, 2.5, -3.25])
    b.write_array("u16", [1, 65535], 16)
    assert_eq(b.read_array("u16", 2, 16), [1, 65535])
    b.write_array("pcm16", [0.5, -2.0, 1.0], 32)
    assert_eq(b.read_array("i16", 3, 32), [16383, -32767, 32767])
    assert_near(ffi.peek(b.address(), "f32"), 1.5)
    ffi.poke(b.address() + 40, "i32", -7)
    assert_eq(b.read("i32", 40), -7)
    c := ffi.Buffer(16)
    c.copy_from(b, 12)
    assert_eq(c.read_array("f32", 3), [1.5, 2.5, -3.25])
    assert_raises(() => b.write_array("f32", [0.0 for i in 0..20]))
    b.free()
    c.free()

testing.test("tableaux en bloc, peek / poke, copie", t_arrays)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) ffi en échec")
print("FFI_EXT: OK")
