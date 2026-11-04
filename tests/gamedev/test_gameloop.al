# ALEX - tests du module gameloop. Lancer depuis la racine : ./alex run tests/gamedev/test_gameloop.al
use gameloop
use testing
from testing use assert_eq, assert_true, assert_false, assert_near, assert_raises

func t_fixed_steps():
    ticks := []
    alphas := []
    loop := gameloop.GameLoop((dt) => ticks.append(dt), (a) => alphas.append(a), 0.1)
    assert_eq(loop.advance(0.25), 2)
    assert_eq(len(ticks), 2)
    assert_near(ticks[0], 0.1)
    assert_near(loop.alpha, 0.5, 0.0001)
    assert_eq(loop.advance(0.05), 1)
    assert_eq(loop.step_count, 3)
    assert_near(loop.sim_time, 0.3, 0.0001)

testing.test("pas fixes et accumulateur", t_fixed_steps)

func t_spiral():
    n := [0]
    loop := gameloop.GameLoop((dt) => n.append(1), null, 0.1, 0.5, 3)
    steps := loop.advance(10.0)
    assert_true(steps <= 3)
    assert_true(loop.dropped_time > 0.0)

testing.test("anti spirale de la mort", t_spiral)

func t_pause_scale():
    n := []
    loop := gameloop.GameLoop((dt) => n.append(dt), null, 0.1)
    loop.time_scale = 2.0
    assert_eq(loop.advance(0.1), 2)
    loop.pause()
    assert_eq(loop.advance(1.0), 0)
    loop.resume()
    assert_true(loop.advance(0.1) >= 1)

testing.test("échelle de temps et pause", t_pause_scale)

func t_fake_clock():
    now := [0.0]
    ticks := [0]
    loop := gameloop.GameLoop((dt) => ticks.append(1), null, 0.1, 1.0, 8, () => now[0])
    loop.frame()
    now[0] = 0.35
    assert_eq(loop.frame(), 3)

testing.test("horloge injectée", t_fake_clock)

func t_run_limit():
    n := []
    loop := gameloop.GameLoop((dt) => n.append(1), null, 0.01)
    loop.sleep_fn = (s) => null
    frames := loop.run(5)
    assert_eq(frames, 5)

testing.test("run avec limite d'images", t_run_limit)

func t_timer():
    fired := []
    t := gameloop.Timer(1.0, true, () => fired.append(1))
    t.update(0.5)
    assert_near(t.progress(), 0.5)
    t.update(0.5)
    assert_eq(len(fired), 1)
    t.update(1.0)
    assert_eq(len(fired), 2)
    one := gameloop.Timer(1.0)
    one.update(2.0)
    one.update(2.0)
    assert_true(one.remaining() <= 0.0)

testing.test("minuteries", t_timer)

func t_scheduler():
    log := []
    s := gameloop.Scheduler()
    s.after(1.0, () => log.append("a"))
    id := s.every(0.5, () => log.append("e"))
    s.update(0.5)
    assert_eq(len(log), 1)
    s.update(0.5)
    assert_true(len(log) >= 3)
    s.cancel(id)
    before := len(log)
    s.update(5.0)
    assert_eq(len(log), before)

testing.test("planificateur", t_scheduler)

func t_tween():
    seen := []
    done := []
    tw := gameloop.Tween(0.0, 10.0, 2.0, gameloop.linear, (v) => seen.append(v), () => done.append(true))
    tw.update(1.0)
    assert_near(tw.value(), 5.0)
    tw.update(1.0)
    assert_near(tw.value(), 10.0)
    assert_eq(len(done), 1)
    for name in ["linear", "in_quad", "out_cubic", "in_out_sine", "out_bounce"]:
        f := gameloop.easing(name)
        assert_near(f(0.0), 0.0, 0.0001)
        assert_near(f(1.0), 1.0, 0.0001)

testing.test("tweens et courbes", t_tween)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) gameloop en échec")
print("GAMELOOP: OK")
