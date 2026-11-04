# ALEX - outils 2D sur ui.canvas (sans GPU) : image_region, sprites, tuiles Tiled, particules.
# ./alex run tests/gamedev/test_canvas2d.al (sans affichage : écran virtuel « headless »)
use os
use ui
use ui.canvas as canvas
use ui.image as uimg
use sprite
use tilemap
use particles
use multimedia.image.decode as dec
use testing
from testing use assert_eq, assert_true

const DATA := "tests/gamedev/data/"
const OUT := "/tmp/alex_canvas2d.png"

if os.getenv("ALEX_UI_BACKEND") == null and os.getenv("DISPLAY") == null:
    os.setenv("ALEX_UI_BACKEND", "headless")
win := ui.window("canvas2d", 96, 64, true)
cv := canvas.create(win)
ui.show(win)

func shot():
    canvas.save_png(cv, OUT)
    return dec.load(OUT)

func at(img, x, y):
    return img.get(x, y)[0:3]

func t_region_sprite():
    tiles := uimg.load(DATA + "tuiles.png")
    assert_eq(uimg.size(tiles), [64, 16])
    canvas.begin(cv)
    canvas.clear(cv, {"r": 0, "g": 0, "b": 0, "a": 255})
    canvas.image_region(cv, tiles, 32, 0, 16, 16, 0, 0, 32, 32)          # tuile bleue agrandie
    a := sprite.grid(tiles, 16, 16)
    s := sprite.Sprite(a, [64, 16])
    s.set_frame(1)
    s.flip_x = true
    sprite.draw_canvas(cv, s)                                              # tuile verte, retournée
    canvas.end(cv)
    img := shot()
    assert_eq(at(img, 10, 10), [0, 0, 255])
    assert_eq(at(img, 64, 16), [0, 255, 0])
    assert_eq(len(tiles["_crops"]), 2)                   # une découpe par zone, gardée en cache

testing.test("image_region et sprite (canvas)", t_region_sprite)

func t_tilemap_canvas():
    m := tilemap.load(DATA + "niveau.tmj")
    canvas.begin(cv)
    canvas.clear(cv, {"r": 0, "g": 0, "b": 0, "a": 255})
    tilemap.draw_canvas(cv, m)
    canvas.end(cv)
    img := shot()
    assert_eq(at(img, 8, 56), [255, 0, 0])
    assert_eq(at(img, 72, 40), [0, 255, 0])
    assert_eq(at(img, 8, 30), [0, 0, 0])

testing.test("carte Tiled sur canvas", t_tilemap_canvas)

func t_particles_canvas():
    e := particles.Emitter(particles.preset("explosion"), [48, 32])
    e.update(0.05)
    canvas.begin(cv)
    canvas.clear(cv, {"r": 0, "g": 0, "b": 0, "a": 255})
    e.draw_canvas(cv)
    canvas.end(cv)
    img := shot()
    c := at(img, 48, 32)
    assert_true(c[0] > 100)

testing.test("particules sur canvas", t_particles_canvas)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) canvas 2D en échec")
print("CANVAS2D: OK")
