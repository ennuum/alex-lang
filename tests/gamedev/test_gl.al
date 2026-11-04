# ALEX - tests de gl / gl.window / gl.render (rendu réel par OpenGL). Linux : affichage X11 nécessaire
# (make test-gl le lance sous Xvfb). ./alex run tests/gamedev/test_gl.al
use os
use gl
use gl.window as glw
use gl.render as gr
use mesh
use math3d as m3
use testing
from testing use assert_eq, assert_true

if os.platform() != "windows" and os.getenv("DISPLAY") == null:
    print("GL: ignoré (pas d'affichage ; lancer sous Xvfb : make test-gl)")
else:
    w := glw.Window("test", 64, 64, {"vsync": false})
    r := gr.Renderer(w)

    func px(x, y):
        p := w.read_pixels()
        k := 4 * (y * 64 + x)
        return [p[k], p[k + 1], p[k + 2], p[k + 3]]

    func t_context():
        assert_eq(gl.missing_functions(), [])
        assert_true(gl.get_integer(gl.GL_MAX_TEXTURE_SIZE) >= 1024)

    testing.test("contexte et fonctions", t_context)

    func t_clear():
        r.begin_frame([1.0, 0.5, 0.0, 1.0])
        assert_eq(px(10, 10), [255, 128, 0, 255])
        assert_eq(gl.errors(), [])

    testing.test("effacement", t_clear)

    func t_mesh():
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        r.set_perspective(m3.radians(60), [0.0, 0.0, 3.0], [0.0, 0.0, 0.0])
        mat := gr.Material([0.0, 1.0, 0.0, 1.0], null, 0.0, 1.0, true)
        r.draw(gr.GpuMesh(mesh.box(1, 1, 1)), null, mat)
        assert_eq(px(32, 32), [0, 255, 0, 255])
        assert_eq(px(1, 1), [0, 0, 0, 255])
        assert_eq(gl.errors(), [])

    testing.test("maillage non éclairé", t_mesh)

    func t_sprites():
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        b := gr.SpriteBatch(r)
        tex := gr.Texture(2, 1, [255, 0, 0, 255, 0, 0, 255, 255], 4, "nearest", "clamp", false)
        b.begin()
        b.draw(tex, 0, 0, 64, 32)                       # moitié haute : rouge | bleu
        b.rect(0, 32, 64, 32, [1.0, 1.0, 0.0, 1.0])
        b.end()
        assert_eq(px(10, 50), [255, 0, 0, 255])          # lignes du bas en premier : y = 50 est en haut
        assert_eq(px(50, 50), [0, 0, 255, 255])
        assert_eq(px(10, 10), [255, 255, 0, 255])
        assert_eq(gl.errors(), [])

    testing.test("sprites et textures", t_sprites)

    func t_target():
        rt := gr.RenderTarget(16, 16)
        rt.begin([0.0, 0.0, 1.0, 1.0])
        rt.end(w)
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        b := gr.SpriteBatch(r)
        b.begin()
        b.draw(rt.texture, 0, 0, 64, 64)
        b.end()
        assert_eq(px(32, 32), [0, 0, 255, 255])
        rt.delete()

    testing.test("rendu dans une texture", t_target)

    failed := testing.run()
    w.close()
    if failed > 0:
        raise("AssertionError", str(failed) + " test(s) gl en échec")
    print("GL: OK")
