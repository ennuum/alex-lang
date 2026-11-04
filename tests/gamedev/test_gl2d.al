# ALEX - rendu GPU des outils 2D : tuiles Tiled, sprites, particules, retournements, mélange additif.
# Linux : affichage X11 nécessaire (make test-gl le lance sous Xvfb). ./alex run tests/gamedev/test_gl2d.al
use os
use gl
use gl.window as glw
use gl.render as gr
use sprite
use tilemap
use particles
use testing
from testing use assert_eq, assert_true

const DATA := "tests/gamedev/data/"

if os.platform() != "windows" and os.getenv("DISPLAY") == null:
    print("GL2D: ignoré (pas d'affichage ; lancer sous Xvfb : make test-gl)")
else:
    w := glw.Window("test2d", 96, 64, {"vsync": false})
    r := gr.Renderer(w)
    b := gr.SpriteBatch(r)

    # (x, y) en coordonnées écran (haut gauche) -> RGBA
    func px(pixels, x, y):
        k := 4 * ((63 - y) * 96 + x)
        return [pixels[k], pixels[k + 1], pixels[k + 2], pixels[k + 3]]

    func t_tilemap():
        m := tilemap.load(DATA + "niveau.tmj")
        rd := tilemap.MapRenderer(m)
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        b.begin()
        rd.draw(b, [0, 0, 96, 64])
        b.end()
        p := w.read_pixels()
        assert_eq(px(p, 8, 56), [255, 0, 0, 255])        # sol : tuile 1 (rouge)
        assert_eq(px(p, 72, 40), [0, 255, 0, 255])       # tuile 2 (verte) en (4, 2)
        assert_eq(px(p, 8, 8), [0, 0, 255, 255])         # deco (0, 0) : tuile animée 4 -> image 3 (bleue) à t = 0
        assert_eq(px(p, 24, 8), [0, 0, 255, 255])        # deco (1, 0) : GID 3 = tuile locale 2 (bleue), retournée
        rd.update(0.15)                                  # animation : image suivante (tuile 4, jaune)
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        b.begin()
        rd.draw(b, [0, 0, 96, 64])
        b.end()
        p = w.read_pixels()
        assert_eq(px(p, 8, 8), [255, 255, 0, 255])
        assert_eq(gl.errors(), [])

    testing.test("carte Tiled : blocs statiques, tuiles animées", t_tilemap)

    func t_flips():
        tex := gr.Texture(2, 2, [255, 0, 0, 255, 0, 255, 0, 255, 0, 0, 255, 255, 255, 255, 255, 255], 4, "nearest", "clamp", false)
        # rouge vert / bleu blanc ; retournement horizontal -> vert rouge / blanc bleu
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        b.begin()
        b.draw_tile(tex, 0, 0, 32, 32, 0.0, 0.0, 1.0, 1.0, 4)
        b.draw_tile(tex, 32, 0, 32, 32, 0.0, 0.0, 1.0, 1.0, 1)      # diagonal : rouge bleu / vert blanc
        b.end()
        p := w.read_pixels()
        assert_eq(px(p, 8, 8), [0, 255, 0, 255])
        assert_eq(px(p, 24, 8), [255, 0, 0, 255])
        assert_eq(px(p, 8, 24), [255, 255, 255, 255])
        assert_eq(px(p, 40, 8), [255, 0, 0, 255])
        assert_eq(px(p, 56, 8), [0, 0, 255, 255])
        assert_eq(px(p, 40, 24), [0, 255, 0, 255])

    testing.test("retournements H / diagonal", t_flips)

    func t_sprite_particles():
        tex := gr.Texture(2, 1, [255, 0, 0, 255, 0, 0, 255, 255], 4, "nearest", "clamp", false)
        a := sprite.grid(tex, 1, 1)
        s := sprite.Sprite(a, [48, 32])
        s.scale = [20.0, 20.0]
        s.set_frame(1)
        r.begin_frame([0.0, 0.0, 0.0, 1.0])
        b.begin()
        s.draw(b)
        e := particles.Emitter({"burst": 1, "duration": 0.0, "lifetime": [10, 10], "speed": [0, 0],
                                "size_start": [8, 8], "size_end": [8, 8], "blend": "add",
                                "colors": [[0.0, [0.5, 0.0, 0.0, 1.0]], [1.0, [0.5, 0.0, 0.0, 1.0]]]}, [48, 32])
        e.update(0.01)
        e.draw(b)
        b.end()
        p := w.read_pixels()
        assert_eq(px(p, 40, 32), [0, 0, 255, 255])        # sprite bleu
        q := px(p, 48, 32)                                 # bleu + rouge additif
        assert_true(q[0] >= 126 and q[0] <= 129 and q[2] == 255)
        assert_eq(gl.errors(), [])

    testing.test("sprite + particule additive", t_sprite_particles)

    failed := testing.run()
    w.close()
    if failed > 0:
        raise("AssertionError", str(failed) + " test(s) gl 2D en échec")
    print("GL2D: OK")
