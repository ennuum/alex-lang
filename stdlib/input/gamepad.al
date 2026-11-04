# ALEX STANDARD LIBRARY — input.gamepad
#
# Manettes de jeu : état complet (boutons, sticks normalisés en [-1, 1] avec zone morte, gâchettes en [0, 1],
# croix directionnelle) construit à partir des événements evdev selon la disposition standard du noyau Linux
# (BTN_SOUTH = A / croix, BTN_EAST = B / rond, ABS_X / ABS_Y stick gauche, ABS_RX / ABS_RY stick droit,
# ABS_Z / ABS_RZ gâchettes, ABS_HAT0X / HAT0Y croix), plages d'axes configurables, et rappels sur appui /
# relâchement / mouvement d'axe.
#
#   use input.gamepad as gp
#   pad := gp.Gamepad()
#   pad.on_button((nom, appuye) => print(nom, appuye))
#   for e in evenements:                      # InputEvent evdev d'une manette (input.input_device)
#       pad.feed(e)
#   print(pad.is_down("south"), pad.left_stick(), pad.trigger("right"), pad.dpad())
#   m := gp.open_first()                      # première manette : evdev (Linux) ou XInput (Windows)
#   m.poll(0.01) ; print(m.pad.left_stick())
#   m.pad.rumble(0.8, 0.4, 0.25)              # vibration : moteur fort, moteur faible, durée (s)
#
# WINDOWS : XInput (xinput1_4.dll, sinon xinput1_3 / xinput9_1_0) par ffi, manettes 0 à 3 ; XInputReader a la même
#   interface que GamepadReader (poll, pad, read, close) et émet des InputEvent (utilisable par input_manager).
#   Les sticks sont ramenés à la convention evdev (Y vers le BAS positif).
# VIBRATION : XInput (XInputSetState) ; Linux : retour de force evdev (ioctl EVIOCSFF, effet FF_RUMBLE) sur le
#   périphérique ouvert en écriture (droits sur /dev/input/eventN requis).
# Erreurs : DeviceNotFound (open_first), UnsupportedDevice (rumble sans retour de force).

from core use len, type, to_int
from collections use append
use math as _math
use os as _os
use time as _time
use ffi
use input.input_device as _dev
use input.input_event as _ev

const BUTTONS := ["south", "east", "north", "west", "tl", "tr", "tl2", "tr2", "select", "start", "mode", "thumbl",
                  "thumbr", "dpad_up", "dpad_down", "dpad_left", "dpad_right"]
const ALIASES := {"a": "south", "b": "east", "x": "west", "y": "north", "lb": "tl", "rb": "tr", "lt": "tl2",
                  "rt": "tr2", "back": "select", "guide": "mode", "ls": "thumbl", "rs": "thumbr", "croix": "south",
                  "rond": "east", "carré": "west", "triangle": "north", "l1": "tl", "r1": "tr", "l2": "tl2", "r2": "tr2"}

func button_name(name):
    if name in ALIASES:
        return ALIASES[name]
    return name

class AxisRange:
    func init(minimum, maximum, flat=0):
        self.min = minimum
        self.max = maximum
        self.flat = flat

    # Valeur brute -> [-1, 1] (centre au milieu de la plage).
    func symmetric(v):
        c := (self.min + self.max) / 2.0
        half := (self.max - self.min) / 2.0
        if half == 0:
            return 0.0
        r := (v - c) / half
        if r > 1:
            r = 1.0
        if r < -1:
            r = -1.0
        return r

    # Valeur brute -> [0, 1].
    func unit(v):
        span := self.max - self.min
        if span == 0:
            return 0.0
        r := (v - self.min) / span
        if r < 0:
            r = 0.0
        if r > 1:
            r = 1.0
        return r

class Gamepad:
    func init(deadzone=0.12, name="manette"):
        self.name = name
        self.deadzone = deadzone
        self.buttons = {}
        self.raw_axes = {}
        self.ranges = {"x": AxisRange(-32768, 32767), "y": AxisRange(-32768, 32767), "rx": AxisRange(-32768, 32767),
                       "ry": AxisRange(-32768, 32767), "z": AxisRange(0, 255), "rz": AxisRange(0, 255),
                       "hat0x": AxisRange(-1, 1), "hat0y": AxisRange(-1, 1)}
        self._button_cbs = []
        self._axis_cbs = []
        self.events = 0
        self._rumble = null                  # fonction (fort, faible, durée) fournie par le lecteur

    func set_range(axis, minimum, maximum):
        self.ranges[axis] = AxisRange(minimum, maximum)
        return self

    func on_button(fn):
        append(self._button_cbs, fn)
        return self

    func on_axis(fn):
        append(self._axis_cbs, fn)
        return self

    func feed(e):
        self.events += 1
        if e.kind == "button":
            n := e.name
            down := e.value != 0
            was := self.is_down(n)
            self.buttons[n] = down
            if down != was:
                for cb in self._button_cbs:
                    cb(n, down)
        elif e.kind == "axis":
            old := null
            if e.name in self.raw_axes:
                old = self.raw_axes[e.name]
            self.raw_axes[e.name] = e.value
            if not (old == e.value):
                for cb in self._axis_cbs:
                    cb(e.name, self.axis(e.name))
        return self

    func is_down(name):
        n := button_name(name)
        if n in self.buttons:
            return self.buttons[n]
        # croix directionnelle donnée par les axes HAT
        d := self.dpad()
        if n == "dpad_left":
            return d[0] < 0
        if n == "dpad_right":
            return d[0] > 0
        if n == "dpad_up":
            return d[1] < 0
        if n == "dpad_down":
            return d[1] > 0
        return false

    func pressed_buttons():
        return [b for b in BUTTONS if self.is_down(b)]

    func axis(name):
        if not (name in self.raw_axes):
            return 0.0
        if not (name in self.ranges):
            return self.raw_axes[name] * 1.0
        r := self.ranges[name]
        if name == "z" or name == "rz":
            return r.unit(self.raw_axes[name])
        return r.symmetric(self.raw_axes[name])

    func _stick(ax, ay):
        x := self.axis(ax)
        y := self.axis(ay)
        m := _math.sqrt(x * x + y * y)
        if m < self.deadzone:
            return [0.0, 0.0]
        # zone morte radiale avec remise à l'échelle
        k := (m - self.deadzone) / (1 - self.deadzone) / m
        x = x * k
        y = y * k
        if x > 1:
            x = 1.0
        if x < -1:
            x = -1.0
        if y > 1:
            y = 1.0
        if y < -1:
            y = -1.0
        return [x, y]

    func left_stick():
        return self._stick("x", "y")

    func right_stick():
        return self._stick("rx", "ry")

    func trigger(side):
        if side == "left":
            v := self.axis("z")
            if v == 0.0 and self.is_down("tl2"):
                return 1.0
            return v
        v := self.axis("rz")
        if v == 0.0 and self.is_down("tr2"):
            return 1.0
        return v

    # [x, y] de la croix : -1, 0 ou 1.
    func dpad():
        x := 0
        y := 0
        if "hat0x" in self.raw_axes:
            x = self.raw_axes["hat0x"]
        if "hat0y" in self.raw_axes:
            y = self.raw_axes["hat0y"]
        if "dpad_left" in self.buttons and self.buttons["dpad_left"]:
            x = -1
        if "dpad_right" in self.buttons and self.buttons["dpad_right"]:
            x = 1
        if "dpad_up" in self.buttons and self.buttons["dpad_up"]:
            y = -1
        if "dpad_down" in self.buttons and self.buttons["dpad_down"]:
            y = 1
        return [_sign(x), _sign(y)]

    # Vibration : intensités 0..1 des moteurs fort (basses fréquences) et faible, durée en secondes.
    func rumble(strong=1.0, weak=1.0, duration=0.2):
        if self._rumble == null:
            raise("UnsupportedDevice", "gamepad.rumble : cette manette n'a pas de lecteur capable de vibrer")
        self._rumble(_clamp01(strong), _clamp01(weak), duration)

    func stop_rumble():
        if self._rumble != null:
            self._rumble(0.0, 0.0, 0.0)

    func snapshot():
        return {"buttons": self.pressed_buttons(), "left": self.left_stick(), "right": self.right_stick(),
                "triggers": [self.trigger("left"), self.trigger("right")], "dpad": self.dpad()}

func _clamp01(v):
    if v < 0:
        return 0.0
    if v > 1:
        return 1.0
    return v * 1.0

func _sign(v):
    if v < 0:
        return -1
    if v > 0:
        return 1
    return 0

class GamepadReader:
    func init(device, deadzone=0.12):
        self.device = device
        self.kind = "gamepad"
        self.reader = device.open()
        self.pad = Gamepad(deadzone, device.name)
        self._ff = null
        self.pad._rumble = (s, w, d) => self._evdev_rumble(s, w, d)

    # Retour de force evdev : effet FF_RUMBLE téléversé (EVIOCSFF) puis joué (événement EV_FF).
    func _evdev_rumble(strong, weak, duration):
        if self._ff == null:
            libc := ffi.Library("c")
            fd := libc.function("open", ["cstr", "i32"], "i32").call2(self.device.path, 2 | 2048)   # O_RDWR | O_NONBLOCK
            if fd < 0:
                raise("UnsupportedDevice", "gamepad.rumble : ouverture en écriture de " + str(self.device.path) + " impossible (droits ?)")
            self._ff = {"fd": fd, "id": -1, "ioctl": libc.function("ioctl", ["i32", "u64", "ptr"], "i32"),
                        "write": libc.function("write", ["i32", "ptr", "u64"], "i64"),
                        "close": libc.function("close", ["i32"], "i32")}
        ff := self._ff
        e := ffi.Buffer(48)
        e.write("u16", 0x50, 0)                                   # FF_RUMBLE
        e.write("i16", ff["id"], 2)
        e.write("u16", to_int_ms(duration), 10)                   # replay.length (ms)
        e.write("u16", to_int(strong * 65535), 16)
        e.write("u16", to_int(weak * 65535), 18)
        r := ff["ioctl"].call3(ff["fd"], 0x40304580, e.address())  # EVIOCSFF
        if r < 0:
            e.free()
            raise("UnsupportedDevice", "gamepad.rumble : la manette refuse l'effet de vibration (EVIOCSFF)")
        ff["id"] = e.read("i16", 2)
        e.free()
        ev := ffi.Buffer(24)
        ev.write("u16", 0x15, 16)                                 # EV_FF
        ev.write("u16", ff["id"], 18)
        ev.write("i32", 1 if duration > 0 and (strong > 0 or weak > 0) else 0, 20)
        ff["write"].call3(ff["fd"], ev.address(), 24)
        ev.free()

    # Traite les événements disponibles (attend au plus timeout pour le premier) ; nombre traité.
    func poll(timeout=0.0):
        n := 0
        e := self.reader.read(timeout)
        while e != null:
            self.pad.feed(e)
            n += 1
            e = self.reader.read(0.0)
        return n

    # Événement brut suivant (InputEvent) ou null : pour input_manager.
    func read(timeout=0.0):
        e := self.reader.read(timeout)
        if e != null:
            self.pad.feed(e)
        return e

    func close():
        if self._ff != null:
            self._ff["close"].call1(self._ff["fd"])
            self._ff = null
        self.reader.close()

func to_int_ms(seconds):
    ms := to_int(seconds * 1000.0)
    if ms < 0:
        return 0
    if ms > 65535:
        return 65535
    return ms

# ---------------------------------------------------------------------------------------------------------------------
# Windows : XInput
# ---------------------------------------------------------------------------------------------------------------------

const _XI_BUTTONS := [[0x0001, "dpad_up"], [0x0002, "dpad_down"], [0x0004, "dpad_left"], [0x0008, "dpad_right"],
                      [0x0010, "start"], [0x0020, "select"], [0x0040, "thumbl"], [0x0080, "thumbr"], [0x0100, "tl"],
                      [0x0200, "tr"], [0x1000, "south"], [0x2000, "east"], [0x4000, "west"], [0x8000, "north"]]

_xinput := [null]

func _xi():
    if _xinput[0] == null:
        lib := null
        for nm in ["xinput1_4", "xinput1_3", "xinput9_1_0"]:
            if lib == null:
                try:
                    lib = ffi.Library(nm)
                catch e:
                    lib = null
        if lib == null:
            raise("DeviceNotFound", "XInput introuvable (xinput1_4.dll)")
        fget := lib.function("XInputGetState", ["u32", "ptr"], "u32")
        fset := lib.function("XInputSetState", ["u32", "ptr"], "u32")
        _xinput[0] = {"get": (i, a) => fget.call2(i, a), "set": (i, a) => fset.call2(i, a)}
    return _xinput[0]

# Indices (0..3) des manettes XInput branchées.
func xinput_connected():
    out := []
    if _os.platform() != "windows":
        return out
    f := _xi()
    b := ffi.Buffer(16)
    k := 0
    while k < 4:
        if f["get"](k, b.address()) == 0:
            append(out, k)
        k += 1
    b.free()
    return out

class XInputReader:
    # api : {"get": fn(index, adresse), "set": fn(index, adresse)} (tests) ; par défaut, XInput.
    func init(index=0, deadzone=0.12, api=null):
        self.index = index
        self.kind = "gamepad"
        self.name = "XInput " + str(index)
        self.f = api if api != null else _xi()
        self.state = ffi.Buffer(16)
        self.vib = ffi.Buffer(4)
        self.pad = Gamepad(deadzone, self.name)
        self.pad._rumble = (s, w, d) => self._set_rumble(s, w, d)
        self.connected = false
        self.packet = -1
        self.queue = []
        self.prev_buttons = 0
        self.prev_axes = {}
        self.rumble_end = null

    func open():
        return self

    func _set_rumble(strong, weak, duration):
        self.vib.write("u16", to_int(strong * 65535), 0)
        self.vib.write("u16", to_int(weak * 65535), 2)
        self.f["set"](self.index, self.vib.address())
        if duration > 0 and (strong > 0 or weak > 0):
            self.rumble_end = _time.monotonic() + duration
        else:
            self.rumble_end = null

    func _emit(kind, name, value):
        e := _ev.InputEvent(kind, name, value, null, "gamepad", "xinput")
        self.pad.feed(e)
        append(self.queue, e)

    # Lit l'état de la manette et produit les événements de changement ; rend leur nombre.
    func poll(timeout=0.0):
        if self.rumble_end != null and _time.monotonic() >= self.rumble_end:
            self._set_rumble(0.0, 0.0, 0.0)
        r := self.f["get"](self.index, self.state.address())
        was := self.connected
        self.connected = r == 0
        if not self.connected:
            if was:
                for b in _XI_BUTTONS:
                    if (self.prev_buttons & b[0]) != 0:
                        self._emit("button", b[1], 0)
                self.prev_buttons = 0
            return 0
        pk := self.state.read("u32", 0)
        if pk == self.packet:
            return 0
        self.packet = pk
        n := len(self.queue)
        bt := self.state.read("u16", 4)
        for b in _XI_BUTTONS:
            now := (bt & b[0]) != 0
            if now != ((self.prev_buttons & b[0]) != 0):
                self._emit("button", b[1], 1 if now else 0)
        self.prev_buttons = bt
        lt := self.state.read("u8", 6)
        rt := self.state.read("u8", 7)
        lx := self.state.read("i16", 8)
        ly := self.state.read("i16", 10)
        rx := self.state.read("i16", 12)
        ry := self.state.read("i16", 14)
        axes := {"z": lt, "rz": rt, "x": lx, "y": -1 - ly, "rx": rx, "ry": -1 - ry}  # Y : bas positif (evdev)
        for k in ["x", "y", "rx", "ry", "z", "rz"]:
            if not (k in self.prev_axes) or self.prev_axes[k] != axes[k]:
                self._emit("axis", k, axes[k])
        self.prev_axes = axes
        return len(self.queue) - n

    # Événement suivant (InputEvent) ou null : pour input_manager.
    func read(timeout=0.0):
        if len(self.queue) == 0:
            self.poll()
        if len(self.queue) == 0:
            return null
        e := self.queue[0]
        self.queue = self.queue[1:len(self.queue)]
        return e

    func close():
        if self.connected:
            self._set_rumble(0.0, 0.0, 0.0)
        self.state.free()
        self.vib.free()

# Manettes du système : périphériques evdev (Linux) ou XInputReader branchés (Windows).
func gamepads():
    if _os.platform() == "windows":
        return [XInputReader(k) for k in xinput_connected()]
    return _dev.of_kind("gamepad")

# Première manette : GamepadReader (Linux) ou XInputReader (Windows). DeviceNotFound s'il n'y en a pas.
func open_first(deadzone=0.12):
    if _os.platform() == "windows":
        idx := xinput_connected()
        if len(idx) == 0:
            raise("DeviceNotFound", "aucune manette XInput branchée")
        return XInputReader(idx[0], deadzone)
    return GamepadReader(_dev.first("gamepad"), deadzone)
