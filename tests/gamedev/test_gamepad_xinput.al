# ALEX - tests de input.gamepad : XInputReader (API XInput simulée) et vibration. ./alex run tests/gamedev/test_gamepad_xinput.al
use ffi
use input.gamepad as gp
use testing
from testing use assert_eq, assert_true, assert_near, assert_raises
from collections use append

# Fausse API XInput : écrit un XINPUT_STATE dans le tampon donné.
class FakeXInput:
    func init():
        self.packet = 1
        self.buttons = 0
        self.lt = 0
        self.rt = 0
        self.lx = 0
        self.ly = 0
        self.connected = true
        self.vib = []

    func get(index, addr):
        if not self.connected:
            return 1167
        ffi.poke(addr, "u32", self.packet)
        ffi.poke(addr + 4, "u16", self.buttons)
        ffi.poke(addr + 6, "u8", self.lt)
        ffi.poke(addr + 7, "u8", self.rt)
        ffi.poke(addr + 8, "i16", self.lx)
        ffi.poke(addr + 10, "i16", self.ly)
        ffi.poke(addr + 12, "i16", 0)
        ffi.poke(addr + 14, "i16", 0)
        return 0

    func set(index, addr):
        append(self.vib, [ffi.peek(addr, "u16"), ffi.peek(addr + 2, "u16")])
        return 0

func make():
    fake := FakeXInput()
    api := {"get": (i, a) => fake.get(i, a), "set": (i, a) => fake.set(i, a)}
    return [fake, gp.XInputReader(0, 0.1, api)]

func t_buttons_axes():
    m := make()
    fake := m[0]
    r := m[1]
    r.poll()
    assert_true(r.connected)
    fake.packet = 2
    fake.buttons = 0x1000 | 0x0004 | 0x0200          # A, gauche, RB
    fake.lt = 255
    fake.lx = 32767
    fake.ly = 32767                                   # stick poussé vers le HAUT
    r.poll()
    p := r.pad
    assert_true(p.is_down("a"))
    assert_true(p.is_down("rb"))
    assert_eq(p.dpad(), [-1, 0])
    assert_near(p.trigger("left"), 1.0)
    st := p.left_stick()
    assert_true(st[0] > 0.6)
    assert_true(st[1] < -0.6)                         # convention evdev : haut = négatif
    fake.packet = 3
    fake.buttons = 0
    r.poll()
    assert_true(not p.is_down("a"))
    fake.connected = false
    r.poll()
    assert_true(not r.connected)

testing.test("XInput : boutons, croix, gâchettes, sticks", t_buttons_axes)

func t_events_rumble():
    m := make()
    fake := m[0]
    r := m[1]
    fake.buttons = 0x2000
    e := r.read()
    names := []
    while e != null:
        append(names, e.name)
        e = r.read()
    assert_true("east" in names)
    r.pad.rumble(1.0, 0.5, 0.0)
    assert_eq(fake.vib[0], [65535, 32767])
    r.pad.stop_rumble()
    assert_eq(fake.vib[1], [0, 0])

testing.test("XInput : InputEvent et vibration", t_events_rumble)

func t_no_rumble():
    assert_raises(() => gp.Gamepad().rumble())

testing.test("vibration sans lecteur", t_no_rumble)

failed := testing.run()
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) gamepad en échec")
print("GAMEPAD_XINPUT: OK")
