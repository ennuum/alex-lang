# ALEX - tests des modules sprite et particles (sans rendu). ./alex run tests/gamedev/test_sprite_particles.al
use sprite
use particles
use testing
from testing use assert_eq, assert_true, assert_near
from collections use append

class FakeTex:
    func init(w, h):
        self.width = w
        self.height = h

class FakeBatch:
    func init():
        self.calls = []
        self.blend = "alpha"
        self.renderer = {"white": "blanc"}
    func draw(img, x, y, w=null, h=null, color=null, rotation=0.0, origin=null, flip_x=false, flip_y=false):
        append(self.calls, [img, x, y, w, h, rotation, flip_x])
    func rect(x, y, w, h, c):
        append(self.calls, ["rect", x, y, w, h])
    func set_blend(m):
        self.blend = m

func t_atlas():
    a := sprite.grid(FakeTex(64, 32), 16, 16)
    assert_eq(len(a.order), 8)
    f := a.frame(5)
    assert_eq([f.x, f.y, f.w, f.h], [16, 16, 16, 16])
    assert_near(f.u0, 0.25)
    assert_near(f.v1, 1.0)
    a2 := sprite.grid(FakeTex(36, 18), 16, 16, 1, 2)
    assert_eq(len(a2.order), 2)
    assert_eq(a2.frame(1).x, 19)
    js := {"frames": {"marche_0": {"frame": {"x": 0, "y": 0, "w": 10, "h": 12}, "duration": 100,
                                    "spriteSourceSize": {"x": 2, "y": 1, "w": 10, "h": 12}, "sourceSize": {"w": 14, "h": 14}},
                      "marche_1": {"frame": {"x": 10, "y": 0, "w": 10, "h": 12}, "duration": 200}},
           "meta": {"frameTags": [{"name": "marche", "from": 0, "to": 1, "direction": "pingpong"}]}}
    b := sprite.load_atlas_json(js, FakeTex(32, 32))
    assert_eq(b.frame("marche_0").offset, [2, 1])
    an := b.animation("marche")
    assert_eq(an.mode, "pingpong")
    assert_eq(an.durations, [0.1, 0.2])

testing.test("atlas : grille, marge, JSON Aseprite", t_atlas)

func t_animation():
    a := sprite.grid(FakeTex(64, 16), 16, 16)
    an := sprite.Animation(a.frames_range(0, 3), 10, "once")
    an.on_frame(2, "pas")
    ev := []
    fin := []
    p := sprite.AnimationPlayer()
    p.on_event = (pl, n) => append(ev, n)
    p.on_end = (pl) => append(fin, 1)
    p.play(an)
    p.update(0.25)
    assert_eq(p.index, 2)
    assert_eq(ev, ["pas"])
    p.update(1.0)
    assert_true(p.finished)
    assert_eq(p.index, 3)
    assert_eq(len(fin), 1)
    pp := sprite.Animation(a.frames_range(0, 2), 10, "pingpong")
    p.play(pp)
    seq := []
    for k in range(6):
        append(seq, p.index)
        p.update(0.1)
    assert_eq(seq, [0, 1, 2, 1, 0, 1])

testing.test("animations : once, événements, pingpong", t_animation)

func t_sprite():
    a := sprite.grid(FakeTex(64, 16), 16, 16)
    a.add_animation("tourne", sprite.Animation(a.frames_range(0, 3), 4))
    s := sprite.Sprite(a, [100, 50])
    s.play("tourne")
    s.update(0.3)
    assert_eq(s.frame.name, "1")
    s.scale = [2.0, 2.0]
    assert_eq(s.bounds(), [84.0, 34.0, 32.0, 32.0])
    assert_true(s.contains(90, 40))
    b := FakeBatch()
    s.flip_x = true
    s.draw(b)
    c := b.calls[0]
    assert_eq([c[1], c[2], c[3], c[4], c[6]], [84.0, 34.0, 32.0, 32.0, true])
    s2 := sprite.Sprite(a.frame(0), [0, 0])
    s2.depth = -1
    s.depth = 5
    b2 := FakeBatch()
    sprite.draw_all([s, s2], b2)
    assert_eq(b2.calls[0][0].name, "0")

testing.test("sprites : lecture, bornes, dessin, profondeur", t_sprite)

func t_particles():
    e := particles.Emitter({"burst": 50, "duration": 0.0, "lifetime": [0.5, 0.5], "speed": [100, 100], "angle": 0,
                            "spread": 0, "gravity": [0, 100]}, [10, 20])
    sysp := particles.ParticleSystem()
    sysp.add(e)
    sysp.update(0.1)
    assert_eq(sysp.count(), 50)
    p := e.particle(0)
    assert_near(p[0], 20.0, 0.01)                      # 10 + 100 * 0.1
    assert_near(p[1], 21.0, 0.01)                      # gravité : vy = 10 px/s après 0,1 s
    sysp.update(0.5)
    assert_eq(sysp.count(), 0)
    assert_eq(len(sysp.emitters), 0)                   # rafale terminée : émetteur retiré
    f := particles.Emitter(particles.preset("fire"), [0, 0])
    k := 0
    while k < 60:
        f.update(1.0 / 60.0)
        k += 1
    assert_true(f.count() > 40 and f.count() < 120)
    b := FakeBatch()
    f.draw(b)
    assert_eq(len(b.calls), f.count())
    assert_eq(b.blend, "alpha")                        # mode restauré après le dessin additif
    for name in ["fire", "smoke", "explosion", "sparks", "rain", "snow", "dust", "magic"]:
        particles.Emitter(particles.preset(name)).update(0.05)
    c := particles.sample_curve([[0.0, [0.0, 0.0]], [1.0, [1.0, 2.0]]], 0.25)
    assert_near(c[1], 0.5)

testing.test("particules : rafale, gravité, retrait, préréglages, courbes", t_particles)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) sprite / particles en échec")
print("SPRITE_PARTICLES: OK")
