# Tests : event.event_filter / event_subscription / event_errors, window.window_geometry / window_events /
# window_properties / window_errors, keyboard.key_code / key_mapping / keyboard_errors, mouse.mouse_button /
# pointer_position / mouse_errors, input.*, ui.component / dialog / accessibility / ui_renderer.
# À lancer avec ALEX_UI_BACKEND=headless.
from core use len, type
from collections use append
use check as t
use os
use io
use string
use json
use event
use event.event_emitter as ee
use event.event_dispatcher as ed
use event.event_filter as ef
use event.event_subscription as es
use event.event_errors as everr
use window
use window.window_geometry as wg
use window.window_events as wev
use window.window_properties as wp
use window.window_errors as werr
use keyboard.key_event as ke
use keyboard.key_code as kc
use keyboard.key_mapping as km
use keyboard.keyboard_errors as kerr
use mouse.mouse_event as me
use mouse.mouse_button as mb
use mouse.pointer_position as pp
use mouse.mouse_errors as merr
use hardware._input as hin
use hardware._sys as hsys
use input.input_event as iev
use input.input_device as idev
use input.input_manager as im
use input.touch as itouch
use input.multitouch as imt
use input.gamepad as igp
use input.gesture as igs
use input.input_errors as ierr
use input.input as inp
use ui.view as v
use ui.component as uc
use ui.dialog as dlg
use ui.accessibility as a11y
use ui.ui_renderer as ur
from ui.component use Component

# ---------------- event
e1 := event.Event("commande.creee", {"montant": 250, "id": 1})
e2 := event.Event("commande.annulee", {"montant": 50, "id": 2})
f := ef.both(ef.type_is("commande.*"), ef.field_gt("montant", 100))
t.check(f(e1) and not f(e2), "both/type_is/field_gt")
t.check(ef.either(ef.field_eq("id", 2), ef.never())(e2), "either")
t.check(ef.negate(ef.type_is("x"))(e1), "negate")
fp := ef.parse("type=commande.* and montant>=100 and id in [1,3]")
t.check(fp(e1) and not fp(e2), "parse")
t.check(ef.parse("montant<60 or id=1")(e2), "parse or")
t.raises(() => ef.parse("n'importe quoi"), "ArgumentError", "parse invalide")
d := ef.distinct((x) => x.get("id"))
t.check(d(e1) and not d(e1) and d(e2), "distinct")
s3 := ef.sample(3)
t.eq([s3(e1), s3(e1), s3(e1), s3(e1)], [true, false, false, true], "sample")
clk := [0.0]
rl := ef.rate_limit(2, 1.0, () => clk[0])
t.eq([rl(e1), rl(e1), rl(e1)], [true, true, false], "rate_limit")
clk[0] = 1.5
t.check(rl(e1), "rate_limit après la fenêtre")
t.eq([ef.take(1)(e1), ef.skip(1)(e1)], [true, false], "take/skip")
bus := ee.EventEmitter()
recus := []
bus.on("cmd", ef.guard(ef.field_gt("montant", 100), (e) => append(recus, e.get("id"))))
bus.emit("cmd", e1)
bus.emit("cmd", e2)
t.eq(recus, [1], "guard")
vus := []
sub := es.subscribe(bus, "m", (x) => append(vus, x))
bus.emit("m", 1)
sub.pause()
bus.emit("m", 2)
sub.resume()
bus.emit("m", 3)
t.eq(vus, [1, 3], "pause/resume")
t.eq(sub.skipped, 1, "skipped")
sub.cancel()
bus.emit("m", 4)
t.eq(vus, [1, 3], "cancel")
t.eq(bus.listener_count("m"), 0, "désinscrit de la source")
n3 := es.subscribe(bus, "k", (x) => append(vus, x), 2)
bus.emit("k", 5)
bus.emit("k", 6)
bus.emit("k", 7)
t.eq(vus, [1, 3, 5, 6], "max_calls")
t.check(n3.cancelled, "auto-annulé")
disp := ed.Dispatcher()
g := es.SubscriptionGroup()
dv := []
g.add(es.subscribe(disp, "a.b", (e) => append(dv, e.type)))
g.add(es.subscribe(disp, "a", (e) => append(dv, "parent")))
disp.publish("a.b", {})
t.eq(dv, ["a.b", "parent"], "dispatcher + hiérarchie")
t.eq(g.cancel_all(), 2, "cancel_all")
disp.publish("a.b", {})
t.eq(len(dv), 2, "groupe annulé")
tgt := ed.EventTarget("racine")
tv := []
with es.subscribe(tgt, "click", (e) => append(tv, e.type)) as tmp:
    tgt.dispatch(event.Event("click"))
tgt.dispatch(event.Event("click"))
t.eq(tv, ["click"], "EventTarget + with")
col := everr.ErrorCollector()
bus.on("x", everr.safe((v1) => v1["absent"], col))
bus.emit("x", {})
t.eq(col.count(), 1, "safe collecte")
t.raises(() => col.raise_if_any(), "ListenerError", "raise_if_any")
t.raises(() => everr.call_all([(a) => a, (a) => raise("ValueError", "x")], [1]), "ListenerError", "call_all")

# ---------------- window
r := wg.Rect(100, 50, 800, 600)
scr := wg.Rect(0, 0, 1920, 1040)
t.eq(r.right(), 900, "right")
t.eq(r.center(), [500, 350], "center")
t.check(r.contains(150, 60) and not r.contains(900, 60), "contains")
t.eq(r.centered_in(scr), [560, 220, 800, 600], "centered_in")
t.eq(r.aligned_in(scr, "bottom-right", 16), [1104, 424, 800, 600], "aligned_in")
t.eq(wg.Rect(1800, 900, 400, 400).clamped_to(scr), [1520, 640, 400, 400], "clamped_to")
t.eq(r.intersection(wg.Rect(0, 0, 200, 100)), [100, 50, 100, 50], "intersection")
t.eq(r.intersection(wg.Rect(0, 0, 10, 10)), null, "pas d'intersection")
t.eq(wg.fit(1920, 1080, 800, 800), [800, 450], "fit")
t.eq(wg.layout(scr, "right_half"), [960, 0, 960, 1040], "layout")
t.eq(len(wg.tile(scr, 5)), 5, "tile")
t.eq(scr.split_columns(3, 10)[2], [1286, 0, 634, 1040], "split_columns")
t.raises(() => wg.Rect(0, 0, -1, 5), "GeometryError", "dimensions négatives")
t.raises(() => wg.layout(scr, "partout"), "GeometryError", "disposition inconnue")
t.check(werr.backend() == "headless", "backend headless")
t.check(werr.require_display(), "require_display")
w := window.Window("Test", 300, 200)
w.show()
evs := wev.WindowEvents(w)
tailles := []
etats := []
evs.on_resize((e) => append(tailles, [e.width, e.height]))
evs.on_state((e) => append(etats, [e.old_state, e.state]))
rec := wev.EventRecorder(w)
w.maximize()
w.dispatch_events()
t.check(len(tailles) >= 1, "on_resize")
t.eq(etats[len(etats) - 1][1], "maximized", "on_state")
t.check(rec.count("state") >= 1, "recorder")
w.restore()
w.dispatch_events()
p := wp.read(w)
t.eq(p.title, "Test", "read title")
q := p.copy()
q.title = "Brouillon *"
q.opacity = 0.9
dd := wp.diff(p, q)
t.check("title" in dd and "opacity" in dd and len(dd) == 2, "diff")
sent := q.apply(w)
t.check("title" in sent and "opacity" in sent, "apply")
t.eq(w.title(), "Brouillon *", "titre appliqué")
t.eq(wp.read(w).opacity, 0.9, "opacité appliquée")
rr := wg.Rect(10, 20, 640, 480)
wg.apply(w, rr)
w.dispatch_events()
t.eq(wg.of(w), [10, 20, 640, 480], "geometry apply/of")
bag := wp.PropertyBag()
chg := []
bag.on_change((k, a, b) => append(chg, [k, b]))
bag.set("doc", "a.txt")
bag.set("doc", "a.txt")
bag.set("doc", "b.txt")
t.eq(chg, [["doc", "a.txt"], ["doc", "b.txt"]], "PropertyBag")
t.eq(wev.wrap({"type": "drop", "data": "/a\n/b"}).paths, ["/a", "/b"], "DropEvent")
t.eq(wev.category("key_down"), "input", "category")
w.close()
msg := ""
try:
    w.set_title("x")
catch err:
    msg = werr.classify(err)
t.eq(msg, "closed", "classify fermée")

# ---------------- keyboard
k := kc.KeyCode("a")
t.eq([k.vk, k.evdev, k.hid, k.dom], [65, 30, 4, "KeyA"], "KeyCode a")
t.eq(kc.from_hid(0x28).name, "enter", "from_hid")
t.eq(kc.hid_to_vk(0x29), 27, "hid_to_vk escape")
t.eq(kc.from_dom("ArrowLeft").evdev, 105, "from_dom")
t.eq(kc.parse("vk:112").name, "f1", "parse vk")
t.eq(kc.parse("hid:0x3a").name, "f1", "parse hid hex")
t.eq(kc.parse("Escape").name, "escape", "parse dom")
t.eq(kc.hid_modifier_names(5), ["left_ctrl", "left_alt"], "hid modifiers")
t.raises(() => kc.KeyCode("touche_imaginaire"), "ArgumentError", "touche inconnue")
m := km.KeyMap()
m.bind("ctrl+s", "enregistrer")
m.bind("ctrl+k ctrl+c", "commenter")
m.bind("escape", "fermer", "menu")
m.context("menu", "global")
m.remap("caps_lock", "escape")
acts := []
m.on_action((a, e) => append(acts, a))
t.eq(m.handle(ke.KeyEvent("s", "press", 2)), "enregistrer", "raccourci")
t.eq(m.handle(ke.KeyEvent("k", "press", 2)), km.PENDING, "séquence entamée")
t.eq(m.handle(ke.KeyEvent("c", "press", 2)), "commenter", "séquence complète")
t.eq(m.handle(ke.KeyEvent("escape")), null, "hors contexte")
m.set_context("menu")
t.eq(m.handle(ke.KeyEvent("caps_lock")), "fermer", "remap + contexte")
t.eq(m.handle(ke.KeyEvent("s", "press", 2)), "enregistrer", "héritage global")
t.eq(acts, ["enregistrer", "commenter", "fermer", "enregistrer"], "on_action")
m.bind("ctrl+k", "autre")
t.check(len(m.conflicts()) >= 1, "conflit de préfixe")
m2 := km.from_dict(json.parse(json.stringify(m.to_dict())))
m2.set_context("menu")
t.eq(m2.handle(ke.KeyEvent("caps_lock")), "fermer", "from_dict")
t.raises(() => m.remap("escape", "caps_lock"), "MappingError", "boucle de remap")
t.raises(() => m.bind("ctrl++", "x"), "ShortcutError", "raccourci invalide")
t.eq(kerr.check_shortcut("ctrl+shift+s"), null, "check_shortcut ok")
t.check(kerr.check_shortcut("") != null, "check_shortcut vide")
kd := kerr.diagnose_raw_access()
t.check(type(kd["ok"]) == "bool" and kd["advice"] != null or kd["ok"], "diagnostic clavier")

# ---------------- mouse
t.eq(mb.from_evdev(273), "right", "mb evdev")
t.eq(mb.to_dom("middle"), 1, "mb dom")
t.eq(mb.from_hid_mask(5), ["left", "middle"], "mb hid")
t.eq(mb.normalize("gauche"), "left", "mb alias")
bs := mb.ButtonState()
bs.press("left")
bs.press("right")
t.eq(bs.chord(), "left+right", "chord")
t.eq(bs.mask(), 3, "mask")
bs.release("left")
t.check(not bs.is_down("left") and bs.is_down("right"), "release")
t.eq(bs.feed_hid_mask(4), [["middle"], ["right"]], "feed_hid_mask")
bs.left_handed = true
t.eq(bs.logical("left"), "right", "gaucher")
tr := pp.PositionTracker(100, 100, 32, 0.0, 2.0, 5.0)
tr.feed_relative(3, 0)
t.eq(tr.position(), [53.0, 50.0], "relatif sous le seuil")
tr.feed_relative(10, 0)
t.eq(tr.position(), [73.0, 50.0], "accélération")
tr.feed_relative(500, 500)
t.eq(tr.position(), [99, 99], "borné")
t.eq(tr.direction(), "down", "direction")
tr.feed(me.MouseEvent("move", 10, 20))
t.eq(tr.position(), [10.0, 20.0], "absolu")
cs := pp.CoordinateSpace(800, 600, 192)
t.eq(cs.normalize(400, 300), [0.5, 0.5], "normalize")
t.eq(cs.to_dp(400, 300), [200.0, 150.0], "to_dp")
t.eq(cs.to_local(400, 300, 100, 100, 2.0), [150.0, 100.0], "to_local")
t.eq(cs.map_to(pp.CoordinateSpace(400, 300), 400, 300), [200.0, 150.0], "map_to")
t.raises(() => merr.require_cursor("licorne"), "CursorError", "curseur inconnu")
t.eq(merr.require_cursor("pointer"), "pointer", "curseur connu")

# ---------------- input (système simulé : faux /proc et faux /dev/input)
root := "/tmp/alex_input_" + str(os.pid())
os.mkdir_all(root + "/proc/bus/input")
os.mkdir_all(root + "/dev/input")
devtxt := "I: Bus=0003 Vendor=045e Product=028e Version=0110\nN: Name=\"Manette X\"\nP: Phys=usb-1/input0\nS: Sysfs=/devices/x\nH: Handlers=event5 js0\nB: EV=20000b\nB: KEY=7cdb000000000000 0 0 0 0\nB: ABS=3003f\n\nI: Bus=0011 Vendor=0001 Product=0001 Version=ab41\nN: Name=\"AT Keyboard\"\nP: Phys=isa0060/serio0/input0\nH: Handlers=sysrq kbd event0\nB: EV=120013\nB: KEY=402000000 3803078f800d001 feffffdfffefffff fffffffffffffffe\n\nI: Bus=0018 Vendor=06cb Product=0001 Version=0100\nN: Name=\"Ecran tactile\"\nH: Handlers=event7\nB: EV=b\nB: KEY=400 0 0 0 0 0\nB: ABS=6618000 3\n\n"
io.write_file(root + "/proc/bus/input/devices", devtxt)
hsys.set_root(root)
kinds := [x.kind for x in idev.devices()]
t.eq(kinds, ["gamepad", "keyboard", "touchscreen"], "classification " + str(kinds))
t.eq(idev.summary()["gamepad"], 1, "summary")
t.check(inp.available("gamepad") and not inp.available("tablet"), "available")
t.raises(() => idev.first("tablet"), "DeviceNotFound", "first absent")
# événements de manette encodés
raw := []
for ev in [[1, 304, 1], [3, 0, 32767], [3, 1, 0], [3, 5, 255], [3, 16, -1], [0, 0, 0], [1, 304, 0], [0, 0, 0]]:
    raw = raw + hin.encode(ev[0], ev[1], ev[2], 1, 0)
io.write_bytes(root + "/dev/input/event5", raw)
rd := idev.first("gamepad").open()
fr := rd.read_frame(0.1)
t.eq([x.kind for x in fr], ["button", "axis", "axis", "axis", "axis"], "trame evdev")
t.eq(fr[0].name, "south", "nom de bouton")
pad := igp.Gamepad()
appuis := []
pad.on_button((nm, dn) => append(appuis, [nm, dn]))
for x in fr:
    pad.feed(x)
t.check(pad.is_down("a"), "alias a = south")
ls := pad.left_stick()
t.check(ls[0] > 0.99 and ls[1] < 0.001 and ls[1] > -0.001, "stick gauche " + str(ls))
t.eq(pad.trigger("right"), 1.0, "gâchette")
t.eq(pad.dpad(), [-1, 0], "croix")
for x in rd.read_frame(0.1):
    pad.feed(x)
t.check(not pad.is_down("south"), "relâché")
t.eq(appuis, [["south", true], ["south", false]], "on_button")
rd.close()
t.raises(() => pad.rumble(), "UnsupportedDevice", "rumble")
hsys.set_root("")
for nm in ["/dev/input/event5"]:
    os.remove(root + nm)
os.remove(root + "/proc/bus/input/devices")

# conversions
we := iev.from_window_event({"type": "pointer_down", "x": 3, "y": 4, "button": 1})
t.check(we.kind == "button" and we.name == "left" and we.pressed(), "from_window_event")
t.eq(iev.abs_name(53), "mt_position_x", "abs_name")
t.eq(iev.btn_code("touch"), 330, "btn_code")
# touch simple
tt := itouch.TouchTracker(0.3, 10)
c0 := [0.0]
tt.clock = () => c0[0]
p1 := tt.feed_window({"type": "pointer_down", "x": 10, "y": 10})
t.eq(p1.phase, "began", "touch began")
c0[0] = 0.1
p2 := tt.feed_window({"type": "pointer_up", "x": 12, "y": 11})
t.check(p2.phase == "ended" and tt.last_was_tap, "tap")
# multitouch : deux doigts qui s'écartent
dec := imt.MultiTouchDecoder()
func axis(nm, val, tm):
    return iev.InputEvent("axis", nm, val, null, "touchscreen", "evdev", tm)
func syn(tm):
    return iev.InputEvent("sync", "report", 0, 0, "touchscreen", "evdev", tm)
frames := []
for x in [axis("mt_slot", 0, 0.0), axis("mt_tracking_id", 1, 0.0), axis("mt_position_x", 100, 0.0), axis("mt_position_y", 100, 0.0),
          axis("mt_slot", 1, 0.0), axis("mt_tracking_id", 2, 0.0), axis("mt_position_x", 200, 0.0), axis("mt_position_y", 100, 0.0), syn(0.0),
          axis("mt_slot", 0, 0.1), axis("mt_position_x", 50, 0.1), axis("mt_slot", 1, 0.1), axis("mt_position_x", 250, 0.1), syn(0.1),
          axis("mt_slot", 0, 0.2), axis("mt_tracking_id", -1, 0.2), axis("mt_slot", 1, 0.2), axis("mt_tracking_id", -1, 0.2), syn(0.2)]:
    fr2 := dec.feed(x)
    if fr2 != null:
        append(frames, fr2)
t.eq(len(frames), 3, "trames multitouch")
t.eq([pt.phase for pt in frames[0]], ["began", "began"], "began x2")
t.eq([pt.phase for pt in frames[2]], ["ended", "ended"], "ended x2")
gr := igs.GestureRecognizer()
kinds2 := []
for fr3 in frames:
    for gg in gr.feed(fr3):
        append(kinds2, gg["type"])
t.check("pinch_start" in kinds2 and "pinch" in kinds2 and "pinch_end" in kinds2, "pinch " + str(kinds2))
# swipe à un doigt
gr2 := igs.GestureRecognizer()
a := itouch.TouchPoint(9, 0, 0, null, 0.0)
sw := []
gr2.on("swipe", (gg) => append(sw, gg["direction"]))
gr2.feed([a.copy()])
a.move_to(100, 5, 0.1)
gr2.feed([a.copy()])
a.move_to(200, 8, 0.2)
a.end(0.2)
gr2.feed([a.copy()])
t.eq(sw, ["right"], "swipe")
# tap / double tap / appui long
ck := [0.0]
gr3 := igs.GestureRecognizer(0.3, 12.0, 0.35, 0.6, 60.0, 300.0, () => ck[0])
names3 := []
func tap_at(tm, x):
    pt := itouch.TouchPoint(tm * 10, x, 0, null, tm)
    for gg in gr3.feed([pt.copy()]):
        append(names3, gg["type"])
    pt.end(tm + 0.05)
    for gg in gr3.feed([pt.copy()]):
        append(names3, gg["type"])
tap_at(1.0, 5)
tap_at(1.2, 6)
t.eq(names3, ["tap", "tap", "double_tap"], "double tap")
lp := itouch.TouchPoint(77, 0, 0, null, 5.0)
gr3.feed([lp.copy()])
ck[0] = 5.7
t.eq([gg["type"] for gg in gr3.tick()], ["long_press"], "appui long")
# gestionnaire d'entrées
mgr := im.InputManager()
mgr.bind_action("sauter", ["key:space", "button:south", "gesture:tap"])
mgr.bind_axis("h", "key:left", "key:right", "axis:x")
sauts := [0]
mgr.on_action("sauter", () => sauts.__setitem__(0, sauts[0] + 1) if false else _incr(sauts))
func _incr(c):
    c[0] += 1
mgr.inject(iev.InputEvent("key", "space", 1))
mgr.inject(iev.InputEvent("key", "space", 2))
t.check(mgr.is_action_down("sauter"), "action enfoncée")
mgr.inject(iev.InputEvent("key", "space", 0))
mgr.inject({"type": "tap", "x": 0, "y": 0})
t.eq(sauts[0], 2, "on_action (sans répétition)")
mgr.inject(iev.InputEvent("key", "right", 1))
t.eq(mgr.axis("h"), 1.0, "axe virtuel numérique")
mgr.inject(iev.InputEvent("axis", "x", -0.8))
t.eq(mgr.axis("h"), -0.8, "axe analogique prioritaire")
d2 := ierr.diagnose()
t.check(type(d2["ok"]) == "bool", "diagnostic entrées")

# ---------------- ui
class Compteur extends Component:
    func initial_state():
        return {"n": self.prop("depart", 0)}
    func render():
        return v.row([v.text(self.prop("libelle", "") + str(self.state["n"])), v.button("+1", () => self.set_state({"n": self.state["n"] + 1}))])

journal := []
class Appli extends Component:
    func init(props=null):
        super.init(props)
        self.montrer_b = true
    func render():
        enfants := [self.child("a", (pr) => Compteur(pr), {"libelle": "A : "})]
        if self.montrer_b:
            append(enfants, self.child("b", (pr) => Compteur(pr), {"libelle": "B : ", "depart": 10}))
        return v.column(enfants)
    func on_mount():
        append(journal, "monté")

app := Appli()
vue := uc.mount(app)
arbre := vue()
t.eq(journal, ["monté"], "on_mount")
ca := app.children()[0]
ca.set_state({"n": 5})
t.check(app.dirty, "parent marqué sale")
arbre = vue()
t.eq(arbre.children[0].children[0].props["content"], "A : 5", "état conservé entre rendus")
t.eq(app.children()[1].state["n"], 10, "props initiales")
app.montrer_b = false
vue()
t.eq(len(app.children()), 1, "enfant démonté")
fc := uc.functional((props, state, set_state) => v.text(props["t"] + str(state["k"])), {"k": 1})
t.eq(fc({"t": "x"}).tree().props["content"], "x1", "functional")
compte := [0]
mf := uc.memo((x) => _incr(compte))
mf(1)
mf(1)
mf(2)
t.eq(compte[0], 2, "memo")
dm := dlg.DialogManager()
res := []
dm.confirm("Quitter", "Sûr ?", (ok) => append(res, ok))
dm.prompt("Nom", "Nom :", "", (nm) => append(res, nm), (tx) => null if tx != "" else "nom vide")
t.eq(dm.size(), 2, "pile")
t.eq(dm.overlay().kind, "dialog", "overlay")
t.check(not dm.accept(), "validation refuse")
t.eq(dm.top().error, "nom vide", "erreur de validation")
dm.set_value("Ana")
t.check(dm.accept(), "validation accepte")
dm.cancel()
t.eq(res, ["Ana", false], "résultats")
t.eq(dm.overlay().kind, "spacer", "plus de dialogue")
dm.choose("Format", ["PDF", "HTML"], (i) => append(res, i))
dm.select(1)
dm.accept()
t.eq(res[2], 1, "choose")
t.eq(dlg.filters([["Images", "*.png"]]), "Images (*.png)\0*.png\0", "filters")
func vue_a11y():
    return v.column([v.text("Compteur", style="title"), v.button("+1", null), v.field("", null, placeholder="Votre nom"), v.button("", null), v.image("x.png", alt="")])
probs := a11y.audit(vue_a11y, [["#777777", "#ffffff"]])
rules := [pr["rule"] for pr in probs]
t.check("nom" in rules and "alternative" in rules and "contraste" in rules and "étiquette" in rules, "audit " + str(rules))
t.eq(a11y.contrast_ratio("#000000", "#ffffff"), 21.0, "contraste max")
t.eq(a11y.contrast_level("#777777", "#ffffff"), "AA (grand texte)", "niveau")
t.eq(a11y.focus_order(vue_a11y), ["+1", "Votre nom", null], "focus_order")
t.check(string.starts_with(a11y.speak(vue_a11y), "titre Compteur. bouton +1. zone de texte Votre nom."), "speak : " + a11y.speak(vue_a11y))
func vue_r():
    return v.column([v.text("Bonjour", style="title"), v.row([v.button("OK", null, primary=true), v.checkbox("Option", true)])], padding=1)
lignes := ur.render_text(vue_r, 40, 6)
t.check(string.contains(string.join("\n", lignes), "Bonjour"), "render_text")
html := ur.to_html(vue_r, "Aperçu")
t.check(string.contains(html, "<h1>Bonjour</h1>") and string.contains(html, "<button class=\"primary\">OK</button>") and string.contains(html, "checked"), "to_html")
t.check(string.contains(ur.outline(vue_r), "button « OK »"), "outline")
dj := ur.to_dict(vue_r)
t.eq(ur.to_dict(ur.from_dict(json.parse(json.stringify(dj)))), dj, "sérialisation")
func vue_r2():
    return v.column([v.text("Bonsoir", style="title"), v.row([v.button("OK", null, primary=true)])], padding=1)
df := ur.diff(vue_r, vue_r2)
t.check(len(df) == 2, "diff " + str(df))
t.check(string.contains(ur.render_screen_html(vue_r, 30, 4), "Bonjour"), "screen html")
ur.register("compte", (nd) => str(len(nd.children)))
t.eq(ur.render("compte", vue_r), "2", "moteur nommé")

t.summary("test_interaction2")
