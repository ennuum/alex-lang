# ALEX STANDARD LIBRARY — input.input_event
#
# Événement d'entrée UNIFIÉ, quelle que soit la source (fenêtre, périphérique evdev, programme) et le genre de
# périphérique (clavier, souris, pavé ou écran tactile, manette, tablette) :
#   InputEvent(kind, code, value, ...)
#   kind : key | button | motion | relative | scroll | touch | axis | sync
# avec les tables de noms evdev (EV_*, ABS_*, REL_*, BTN_* des manettes et du tactile) et les conversions
# depuis un événement brut du noyau (hardware._input.Event) ou un dict d'événement de fenêtre.
#
#   use input.input_event as iev
#   e := iev.from_evdev(brut, "gamepad")          # InputEvent("button", "south", 1, ...)
#   print(e.kind, e.name, e.value, e.pressed())
#   w := iev.from_window_event({"type": "pointer_move", "x": 3, "y": 4})   # motion (3, 4)
#   print(iev.abs_name(53), iev.btn_name(304), iev.rel_name(8))           # mt_position_x south wheel
#
# Erreurs : TypeError (source invalide).

from core use len, type
from collections use append
use os as _os
use keyboard.key as _key

const EV_SYN := 0
const EV_KEY := 1
const EV_REL := 2
const EV_ABS := 3
const EV_MSC := 4

const ABS_NAMES := {0: "x", 1: "y", 2: "z", 3: "rx", 4: "ry", 5: "rz", 6: "throttle", 7: "rudder", 8: "wheel",
    9: "gas", 10: "brake", 16: "hat0x", 17: "hat0y", 18: "hat1x", 19: "hat1y", 24: "pressure", 25: "distance",
    26: "tilt_x", 27: "tilt_y", 47: "mt_slot", 48: "mt_touch_major", 49: "mt_touch_minor", 50: "mt_width_major",
    51: "mt_width_minor", 52: "mt_orientation", 53: "mt_position_x", 54: "mt_position_y", 55: "mt_tool_type",
    57: "mt_tracking_id", 58: "mt_pressure", 59: "mt_distance"}
const REL_NAMES := {0: "x", 1: "y", 2: "z", 6: "hwheel", 8: "wheel", 11: "wheel_hi_res", 12: "hwheel_hi_res"}
const BTN_NAMES := {272: "left", 273: "right", 274: "middle", 275: "side", 276: "extra", 277: "forward", 278: "back",
    304: "south", 305: "east", 306: "c", 307: "north", 308: "west", 309: "z", 310: "tl", 311: "tr", 312: "tl2",
    313: "tr2", 314: "select", 315: "start", 316: "mode", 317: "thumbl", 318: "thumbr",
    320: "tool_pen", 321: "tool_rubber", 325: "tool_finger", 330: "touch", 331: "stylus", 332: "stylus2",
    333: "tool_doubletap", 334: "tool_tripletap", 335: "tool_quadtap",
    544: "dpad_up", 545: "dpad_down", 546: "dpad_left", 547: "dpad_right"}

func abs_name(code):
    if code in ABS_NAMES:
        return ABS_NAMES[code]
    return "abs_" + str(code)

func rel_name(code):
    if code in REL_NAMES:
        return REL_NAMES[code]
    return "rel_" + str(code)

func btn_name(code):
    if code in BTN_NAMES:
        return BTN_NAMES[code]
    return null

func _code_of(table, name):
    for k in table:
        if table[k] == name:
            return k
    return null

func abs_code(name):
    return _code_of(ABS_NAMES, name)

func btn_code(name):
    return _code_of(BTN_NAMES, name)

class InputEvent:
    func init(kind, name=null, value=0, code=null, device="program", source="program", time=null):
        self.kind = kind          # key | button | motion | relative | scroll | touch | axis | sync
        self.name = name          # nom de touche / bouton / axe
        self.value = value        # 1 appui, 0 relâchement, 2 répétition ; valeur d'axe ; delta
        self.code = code          # code d'origine
        self.device = device      # keyboard | mouse | touchpad | touchscreen | gamepad | tablet | window | program
        self.source = source      # window | evdev | program
        self.x = null
        self.y = null
        self.dx = 0
        self.dy = 0
        self.pressure = null
        self.slot = null
        self.mods = 0
        self.text = ""
        if time == null:
            time = _os.monotonic_time()
        self.time = time

    func pressed():
        return (self.kind == "key" or self.kind == "button") and self.value != 0

    func released():
        return (self.kind == "key" or self.kind == "button") and self.value == 0

    func is_repeat():
        return self.kind == "key" and self.value == 2

    func to_dict():
        return {"kind": self.kind, "name": self.name, "value": self.value, "code": self.code, "device": self.device,
                "source": self.source, "x": self.x, "y": self.y, "dx": self.dx, "dy": self.dy, "time": self.time}

    func __str__():
        t := self.kind
        if self.name != null:
            t += " " + str(self.name)
        t += "=" + str(self.value)
        if self.x != null:
            t += " @(" + str(self.x) + ", " + str(self.y) + ")"
        return "InputEvent(" + t + ")"

# InputEvent d'un événement evdev brut (time, type, code, value) ; null pour EV_MSC et autres types ignorés.
func from_evdev(ev, device="unknown"):
    t := ev.type
    if t == EV_SYN:
        return InputEvent("sync", "report", ev.value, ev.code, device, "evdev", ev.time)
    if t == EV_KEY:
        b := btn_name(ev.code)
        if b != null:
            return InputEvent("button", b, ev.value, ev.code, device, "evdev", ev.time)
        n := null
        try:
            n = _key.from_evdev(ev.code)
        catch e:
            n = null
        if n == null:
            n = "key_" + str(ev.code)
        return InputEvent("key", n, ev.value, ev.code, device, "evdev", ev.time)
    if t == EV_REL:
        n := rel_name(ev.code)
        k := "relative"
        if n == "wheel" or n == "hwheel" or n == "wheel_hi_res" or n == "hwheel_hi_res":
            k = "scroll"
        e := InputEvent(k, n, ev.value, ev.code, device, "evdev", ev.time)
        if n == "x" or n == "hwheel":
            e.dx = ev.value
        elif n == "y" or n == "wheel":
            e.dy = ev.value
        return e
    if t == EV_ABS:
        return InputEvent("axis", abs_name(ev.code), ev.value, ev.code, device, "evdev", ev.time)
    return null

const _WIN := {"key_down": "key", "key_up": "key", "pointer_down": "button", "pointer_up": "button",
               "pointer_move": "motion", "wheel": "scroll", "pointer_leave": "motion"}

func from_window_event(ev):
    if type(ev) != "dict" or not ("type" in ev):
        raise("TypeError", "from_window_event : dict d'événement de fenêtre attendu")
    t := ev["type"]
    if not (t in _WIN):
        return null
    k := _WIN[t]
    e := InputEvent(k, null, 0, null, "window", "window")
    if "x" in ev:
        e.x = ev["x"]
        e.y = ev["y"]
    if "mods" in ev:
        e.mods = ev["mods"]
    if k == "key":
        vk := 0
        if "key" in ev:
            vk = ev["key"]
        e.code = vk
        e.name = _key.name(vk)
        if "text" in ev:
            e.text = ev["text"]
        if t == "key_down":
            e.value = 1
    elif k == "button":
        names := {1: "left", 2: "right", 3: "middle"}
        bn := 0
        if "button" in ev:
            bn = ev["button"]
        e.code = bn
        if bn in names:
            e.name = names[bn]
        if t == "pointer_down":
            e.value = 1
    elif k == "scroll":
        if "dx" in ev:
            e.dx = ev["dx"]
        if "dy" in ev:
            e.dy = ev["dy"]
        e.value = e.dy
    elif t == "pointer_leave":
        e.name = "leave"
    return e
