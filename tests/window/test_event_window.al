# =============================================================================
# ALEX — paquets event, window, keyboard, mouse (docs/EVENT_WINDOW.md).
# Lancer DEPUIS LA RACINE DU PROJET :
#   ALEX_UI_BACKEND=headless ./alex run tests/window/test_event_window.al
# =============================================================================
from core use len, type
from collections use append, sort
use asyncio
use os
use event
use event.event_emitter as ee
use event.event_dispatcher as ed
use event.event_queue as eq
use event.timer as timer
use event.watcher as watcher
use event.event_loop as el
use pipe
use keyboard
use keyboard.key as key
use keyboard.key_event as ke
use keyboard.keyboard_layout as kl
use mouse
use mouse.mouse_event as me
use mouse.pointer as pt
use mouse.cursor as cursor
use window
use window.window_manager as wm
use window.window_style as wst
use window.window_state as ws
use window.screen as screen
use window.display as display
use _native_net as _b

stats := [0, 0]
notes := []
func check(c, label):
    if c:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label)
func check_eq(a, b, label):
    if a == b:
        stats[0] += 1
    else:
        stats[1] += 1
        append(notes, label + " : obtenu " + str(a) + ", attendu " + str(b))
func raises(f, kind, label):
    try:
        f()
        check(false, label + " (aucune erreur)")
    catch e:
        check_eq(e.type, kind, label)

TMP := "/tmp/alex-test-event-window-" + str(os.pid())

# ---------------------------------------------------------------- event
async func test_event():
    e := event.Event("click", {"x": 3})
    check_eq([e.type, e.get("x"), e.get("y", 0)], ["click", 3, 0], "Event")
    check_eq(event.from_dict(e.to_dict()).data, {"x": 3}, "to_dict / from_dict")
    raises(() => event.Event(""), "TypeError", "type vide")
    log := []
    bus := ee.EventEmitter()
    off := bus.on("msg", (t) => append(log, "a:" + t))
    bus.on("msg", (t) => append(log, "b:" + t), 5)
    bus.once("msg", () => append(log, "once"))
    bus.on("*", (ty, args) => append(log, "*" + ty))
    check_eq(bus.emit("msg", "x"), 3, "emit : nombre d'écouteurs")
    check_eq(log, ["b:x", "a:x", "once", "*msg"], "priorités, once, joker")
    off()
    check_eq(bus.listener_count("msg"), 1, "off")
    bus.on("boom", () => 1 // 0)
    raises(() => bus.emit("boom"), "ZeroDivisionError", "erreur relancée sans écouteur error")
    errs := []
    bus.on("error", (t, m, ty) => append(errs, t + "@" + ty))
    bus.emit("boom")
    check_eq(errs, ["ZeroDivisionError@boom"], "écouteur error")
    async func later():
        await asyncio.sleep(0.005)
        bus.emit("reponse", 42)
    later()
    check_eq(await bus.wait_for("reponse", 1), 42, "wait_for")
    async_log := []
    async func ecouteur(x):
        await asyncio.sleep(0.005)
        append(async_log, x)
    bus.on("async", ecouteur)
    await bus.emit_async("async", 7)
    check_eq(async_log, [7], "emit_async attend les écouteurs")
    racine := ed.EventTarget("racine")
    milieu := ed.EventTarget("milieu", racine)
    bouton := ed.EventTarget("bouton", milieu)
    trace := []
    racine.add_listener("click", (ev) => append(trace, "cap-racine"), true)
    milieu.add_listener("click", (ev) => append(trace, "cap-milieu"), true)
    bouton.add_listener("click", (ev) => append(trace, "cible:" + ev.phase))
    milieu.add_listener("click", (ev) => append(trace, "bulle-milieu"))
    racine.add_listener("click", (ev) => append(trace, "bulle-racine"))
    check(bouton.dispatch(event.Event("click")), "dispatch sans prevent_default")
    check_eq(trace, ["cap-racine", "cap-milieu", "cible:target", "bulle-milieu", "bulle-racine"], "capture / cible / bouillonnement")
    trace = []
    milieu.add_listener("click", (ev) => ev.stop_propagation(), false, 10)
    bouton.add_listener("click", (ev) => ev.prevent_default())
    check(not bouton.dispatch("click"), "prevent_default")
    check_eq(trace, ["cap-racine", "cap-milieu", "cible:target", "bulle-milieu"], "stop_propagation")
    check_eq(racine.find("bouton"), bouton, "find")
    d := ed.Dispatcher()
    got := []
    d.subscribe("a", (ev) => append(got, "a"))
    d.subscribe("a.b", (ev) => append(got, "ab"), 1, (ev) => ev.get("n", 0) > 1)
    d.subscribe("*", (ev) => append(got, "*"))
    check_eq(d.publish("a.b.c", {"n": 5}), 3, "Dispatcher : types hiérarchiques")
    check_eq(got, ["ab", "a", "*"], "Dispatcher : ordre")
    got = []
    d.publish("a.b", {"n": 0})
    check_eq(got, ["a", "*"], "Dispatcher : filtre")
    q := eq.EventQueue()
    q.post("bas", 1)
    q.post("haut", 2, 10)
    q.post_unique("resize", 1)
    q.post_unique("resize", 2)
    check_eq([q.size(), q.poll().type], [3, "haut"], "EventQueue : priorités")
    check_eq([x.data for x in q.drain()], [1, 2], "EventQueue : post_unique")
    async func poster():
        await asyncio.sleep(0.005)
        q.post("tard", "x")
    poster()
    check_eq((await q.get(1)).type, "tard", "EventQueue.get")
    check_eq(await q.get(0.01), null, "EventQueue.get : délai")
    bq := eq.EventQueue(1)
    bq.post("a")
    raises(() => bq.post("b"), "QueueFull", "capacité")
    tq := eq.ThreadEventQueue()
    tq.post("t", [1, 2])
    check_eq(tq.get(1).data, [1, 2], "ThreadEventQueue")
    ticks := []
    t := timer.Interval(0.005, () => append(ticks, 1), 3).start()
    check_eq(await t.wait(), 3, "Interval : 3 tics")
    t2 := timer.Timer(0.5, () => append(ticks, 9)).start()
    check(t2.cancel(), "Timer.cancel")
    check_eq(await t2.wait(), 0, "Timer annulé")
    calls := []
    deb := timer.debounce((x) => append(calls, x), 0.01)
    deb(1)
    deb(2)
    deb(3)
    await asyncio.sleep(0.04)
    check_eq(calls, [3], "debounce")
    thr := timer.throttle((x) => append(calls, x), 1)
    check_eq([thr(10), thr(11)], [true, false], "throttle")
    os.mkdir(TMP)
    backends := ["poll"]
    if watcher.FileWatcher(TMP).backend == "inotify":
        append(backends, "inotify")
    for b in backends:
        w := watcher.FileWatcher(TMP, true, b, 0.02)
        os.mkdir(TMP + "/sous_" + b)
        w.poll(0.1)
        f := TMP + "/sous_" + b + "/x.txt"
        os.run("sh", ["-c", "echo a > " + f])
        evs := w.poll(1.0)
        check(len([x for x in evs if x["kind"] == "created" and os.basename(x["path"]) == "x.txt"]) == 1, "watcher " + b + " : created")
        os.remove(f)
        evs = w.poll(1.0)
        check(len([x for x in evs if x["kind"] == "deleted"]) >= 1, "watcher " + b + " : deleted")
        w.close()
    vals := [1]
    changes := []
    vw := watcher.ValueWatcher(() => vals[0], 0.005, (a, b) => append(changes, [a, b]))
    vw.start()
    vals[0] = 2
    await asyncio.sleep(0.03)
    vw.stop()
    check_eq(changes, [[1, 2]], "ValueWatcher")
    loop := el.EventLoop()
    seen := []
    loop.on("cmd", (ev) => append(seen, ev.data))
    tub := pipe.create()
    loop.add_reader(tub.reader.fd, () => loop.post("cmd", tub.receive_line(1)))
    loop.every(0.02, () => append(seen, "tic"))
    loop.call_later(0.03, () => tub.send_line("depuis tube"))
    loop.call_later(0.09, () => loop.stop())
    loop.post("cmd", "direct")
    await loop.run()
    check_eq(seen[0], "direct", "EventLoop : événement posté")
    check(len([x for x in seen if x == "depuis tube"]) == 1, "EventLoop : descripteur")
    check(len([x for x in seen if x == "tic"]) >= 3, "EventLoop : every")
    tub.close()
    loop2 := el.EventLoop()
    loop2.on("x", (ev) => 1 // 0)
    loop2.post("x")
    try:
        await loop2.run(1)
        check(false, "EventLoop : erreur attendue")
    catch ZeroDivisionError as e:
        check(true, "EventLoop : erreur relancée par run")
    errs2 := []
    loop3 := el.EventLoop().on_error((t, m, c) => append(errs2, t))
    loop3.on("x", (ev) => 1 // 0)
    loop3.post("x")
    await loop3.run(0.02)
    check_eq(errs2, ["ZeroDivisionError"], "EventLoop.on_error")
    async func fini():
        await asyncio.sleep(0.01)
        return "ok"
    check_eq(await el.EventLoop().run_until(fini()), "ok", "run_until")
    os.rmdir(TMP, true)

# ---------------------------------------------------------------- keyboard / mouse
func test_keyboard_mouse():
    check_eq([key.name(65), key.code("f5"), key.from_evdev(30), key.code("Return")], ["a", 116, "a", 13], "codes de touches")
    check_eq(key.mods_names(key.CTRL | key.SHIFT), ["ctrl", "shift"], "mods_names")
    check(key.is_modifier("left_shift") and key.is_printable("a") and key.is_function_key("f11"), "classification")
    check_eq(ke.parse_shortcut("Ctrl+Shift+F5"), ["f5", key.CTRL | key.SHIFT], "parse_shortcut")
    raises(() => ke.parse_shortcut("ctrl+a+b"), "ArgumentError", "raccourci à deux touches")
    e := ke.from_window_event({"type": "key_down", "key": 83, "mods": 2, "text": ""})
    check(e.matches("ctrl+s") and not e.matches("s"), "matches")
    check_eq(e.describe(), "ctrl+s (appui)", "describe")
    check_eq(ke.from_terminal("ctrl+c").combo(), "ctrl+c", "from_terminal")
    for code in kl.available():
        kl.get(code)
    fr := kl.get("fr")
    check_eq([fr.char("q"), fr.char("1", true), fr.char("2", false, true), fr.char("a", false, false, true)], ["a", "1", "~", "Q"], "AZERTY")
    check_eq(fr.key_for("é"), ("2", false, false), "key_for")
    us := kl.get("us")
    evs := [ke.KeyEvent("left_shift"), ke.KeyEvent("h"), ke.KeyEvent("left_shift", "release"), ke.KeyEvent("i"),
            ke.KeyEvent("x"), ke.KeyEvent("backspace"), ke.KeyEvent("1", "press", key.SHIFT)]
    check_eq(us.type_text(evs), "Hi1", "type_text")
    check_eq(kl.get("de").char("y"), "z", "QWERTZ")
    raises(() => kl.get("klingon"), "ArgumentError", "disposition inconnue")
    kb := keyboard.Keyboard()
    hits := []
    kb.shortcuts.add("ctrl+s", () => append(hits, "save"))
    kb.feed(ke.KeyEvent("left_ctrl"))
    check(kb.ctrl(), "état ctrl")
    kb.feed(ke.KeyEvent("s", "press", key.CTRL))
    check(kb.is_pressed("s") and kb.is_pressed("left_ctrl"), "touches enfoncées")
    kb.feed(ke.KeyEvent("s", "release", key.CTRL))
    kb.feed(ke.KeyEvent("left_ctrl", "release"))
    check(not kb.ctrl() and not kb.is_pressed("s"), "relâchement")
    check_eq(hits, ["save"], "raccourci")
    kb.feed_window_event({"type": "key_down", "key": 0, "mods": 0, "text": "é"})
    check_eq(kb.take_text(), "é", "texte saisi")
    p := pt.Pointer()
    p.add_region("ok", 10, 10, 50, 20)
    gestures := []
    for ev in [me.MouseEvent("move", 20, 15), me.MouseEvent("down", 20, 15, "left"), me.MouseEvent("up", 20, 15, "left"),
               me.MouseEvent("down", 21, 15, "left"), me.MouseEvent("up", 21, 15, "left")]:
        for g in p.feed(ev):
            append(gestures, g.kind)
    check_eq(gestures, ["move", "down", "up", "click", "down", "up", "click", "double_click"], "clic et double clic")
    check_eq(p.hovered(), "ok", "région survolée")
    gestures = []
    for ev in [me.MouseEvent("down", 0, 0, "left"), me.MouseEvent("move", 2, 0), me.MouseEvent("move", 10, 0), me.MouseEvent("up", 10, 0, "left")]:
        for g in p.feed(ev):
            append(gestures, g.kind)
    check_eq(gestures, ["down", "move", "move", "drag_start", "drag", "up", "drag_end"], "glisser")
    check_eq(me.from_window_event({"type": "wheel", "x": 1, "y": 2, "dx": 0.0, "dy": 1.0, "mods": 0}).dy, 1.0, "molette")
    check_eq(len(cursor.names()), 11, "curseurs")
    raises(() => cursor.set(0, "licorne"), "ArgumentError", "curseur inconnu")

# ---------------------------------------------------------------- window
async func test_window():
    w := window.Window("Test", 400, 300, {"min_size": (200, 100), "x": 10, "y": 20})
    i := w.info()
    check_eq([i["x"], i["y"], i["width"], i["height"], i["min_width"]], [10, 20, 400, 300, 200], "Window : options")
    log := []
    w.on("key", (k) => append(log, "key:" + k.describe()))
    w.on("click", (g) => append(log, "click:" + str(g.clicks)))
    w.on("double_click", (g) => append(log, "dbl"))
    w.on("drag_end", (g) => append(log, "drag:" + str(g.dx)))
    w.on("state", (ev) => append(log, "state:" + ev["data"]))
    w.on("focus_in", (ev) => append(log, "focus"))
    w.show()
    w.inject_press("s", key.CTRL)
    w.inject_mouse("click", 50, 60)
    w.inject_mouse("click", 50, 60)
    w.inject_mouse("down", 10, 10)
    w.inject_mouse("move", 40, 10)
    w.inject_mouse("up", 40, 10)
    w.dispatch_events()
    check_eq(log, ["key:ctrl+s (appui)", "key:ctrl+s (relâchement)", "click:1", "click:2", "dbl", "drag:30"], "événements typés")
    log = []
    w.move(100, 120)
    check_eq(w.position(), (100, 120), "move")
    w.maximize()
    check_eq([w.state(), w.position(), w.size()], ["maximized", (0, 0), (1920, 1040)], "maximize (zone de travail)")
    w.fullscreen()
    check_eq(w.size(), (1920, 1080), "plein écran")
    w.restore()
    check_eq([w.state(), w.position(), w.size()], ["normal", (100, 120), (400, 300)], "restore")
    w.focus()
    w.dispatch_events()
    check_eq(log, ["state:maximized", "state:fullscreen", "state:normal", "focus"], "événements d'état et de focus")
    check(w.focused(), "focused")
    raises(() => w.set_state("géant"), "ArgumentError", "état inconnu")
    wst.OVERLAY.apply(w)
    i = w.info()
    check_eq([i["decorated"], i["topmost"], i["opacity"], i["resizable"]], [false, true, 0.85, false], "style OVERLAY")
    raises(() => w.set_opacity(2), "ArgumentError", "opacité invalide")
    w.set_hints(true, true, false, 1.0, (300, 200), (500, 400))
    w.set_size(100, 50)
    check_eq(wst.of(w).min_size, (300, 200), "WindowStyle.of")
    cursor.set(w, cursor.WAIT)
    check_eq(w.cursor(), "wait", "curseur")
    check_eq(cursor.with_cursor(w, cursor.TEXT, () => w.cursor()), "text", "with_cursor")
    check_eq(w.cursor(), "wait", "curseur rétabli")
    row := _b.from_bytes([255, 0, 0, 255, 0, 255, 0, 255])
    w.draw_pixels(0, 0, 2, 1, row)
    os.mkdir(TMP)
    check(w.screenshot(TMP + "/w.png"), "screenshot")
    check_eq(screen.current().work_height, 1040, "screen")
    check(display.count() >= 1, "display")
    s := w.snapshot()
    ws.save(s, TMP + "/state.json")
    check_eq(ws.load(TMP + "/state.json").to_dict(), s.to_dict(), "window_state save / load")
    check_eq(ws.WindowState(5000, 10, 3000, 500, "minimized").clamp_to(1920, 1080).to_dict(),
             {"x": 0, "y": 10, "width": 1920, "height": 500, "state": "normal"}, "clamp_to")
    m := wm.WindowManager()
    m.add(w)
    b := m.create("B", 300, 200)
    m.tile()
    check_eq([w.position(), b.position(), b.size()], [(0, 0), (960, 0), (960, 1040)], "tile")
    check_eq(m.save_layout(TMP + "/layout.json"), 2, "save_layout")
    b.move(5, 5)
    check_eq(m.restore_layout(TMP + "/layout.json"), 2, "restore_layout")
    check_eq(b.position(), (960, 0), "géométrie restaurée")
    check_eq(m.find("B"), b, "find")
    async func frappe():
        await asyncio.sleep(0.01)
        b.inject_press("enter")
    frappe()
    k := await b.wait_for("key", 1)
    check_eq(k.key, "enter", "wait_for")
    await m.run_async()
    m.close_all()
    check(not w.is_open() and not b.is_open(), "close_all")
    raises(() => w.show(), "IoError", "fenêtre fermée")
    os.rmdir(TMP, true)

async func main():
    await test_event()
    test_keyboard_mouse()
    if window.available():
        await test_window()
    else:
        print("window : aucun backend (lancer avec ALEX_UI_BACKEND=headless)")
    print(f"event / window / keyboard / mouse : {stats[0]} vérifications OK, {stats[1]} échec(s)")
    for n in notes:
        print("  ÉCHEC " + n)
    if stats[1] > 0:
        raise("TestError", "test_event_window : échecs")

await main()
