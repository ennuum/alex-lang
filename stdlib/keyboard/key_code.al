# ALEX STANDARD LIBRARY — keyboard.key_code
#
# Codes de touches dans TOUS les systèmes de numérotation, autour d'un nom uniforme (keyboard.key) :
#   vk      codes virtuels des fenêtres (window / ui, façon Win32 : A = 65)
#   evdev   codes du noyau Linux (hardware.keyboard : A = 30)
#   hid     usages HID USB, page clavier 0x07 (rapports des claviers USB, usb_driver.usb_hid : A = 4)
#   dom     KeyboardEvent.code du Web (« KeyA », « Digit1 », « ArrowLeft », « ShiftLeft »)
# KeyCode réunit tout cela pour une touche ; les fonctions de conversion passent d'un système à l'autre.
#
#   use keyboard.key_code as kc
#   k := kc.KeyCode("a")
#   print(k.vk, k.evdev, k.hid, k.dom)           # 65 30 4 KeyA
#   print(kc.from_hid(0x28).name, kc.hid_to_vk(0x29))     # enter 27
#   print(kc.from_dom("ArrowLeft").evdev)         # 105
#   print(kc.parse("vk:112").name, kc.parse("hid:58").name, kc.parse("Escape").name)   # f1 f1 escape
#   print(kc.HID_MODIFIERS)                       # bits du premier octet d'un rapport HID
#
# Erreurs : ArgumentError (touche ou code inconnus).

from core use len, type, to_int
from collections use append
use string as _s
use keyboard.key as _key

func _build_hid():
    t := {}
    letters := "abcdefghijklmnopqrstuvwxyz"
    i := 0
    while i < 26:
        t[4 + i] = str(letters[i])
        i += 1
    digits := "1234567890"
    i = 0
    while i < 10:
        t[30 + i] = str(digits[i])
        i += 1
    named := {40: "enter", 41: "escape", 42: "backspace", 43: "tab", 44: "space", 45: "minus", 46: "equal",
              47: "left_brace", 48: "right_brace", 49: "backslash", 51: "semicolon", 52: "apostrophe", 53: "grave",
              54: "comma", 55: "dot", 56: "slash", 57: "caps_lock", 70: "print_screen", 71: "scroll_lock", 72: "pause",
              73: "insert", 74: "home", 75: "page_up", 76: "delete", 77: "end", 78: "page_down", 79: "right",
              80: "left", 81: "down", 82: "up", 83: "num_lock", 84: "kp_slash", 85: "kp_asterisk", 86: "kp_minus",
              87: "kp_plus", 88: "kp_enter", 99: "kp_dot", 100: "less_greater", 101: "menu",
              224: "left_ctrl", 225: "left_shift", 226: "left_alt", 227: "left_meta", 228: "right_ctrl",
              229: "right_shift", 230: "right_alt", 231: "right_meta"}
    for k in named:
        t[k] = named[k]
    f := 1
    while f <= 12:
        t[57 + f] = "f" + str(f)
        f += 1
    f = 13
    while f <= 24:
        t[104 + f - 13] = "f" + str(f)
        f += 1
    kp := "123456789"
    i = 0
    while i < 9:
        t[89 + i] = "kp_" + str(kp[i])
        i += 1
    t[98] = "kp_0"
    return t

func _build_dom():
    t := {}
    for c in "abcdefghijklmnopqrstuvwxyz":
        t[str(c)] = "Key" + _s.upper(str(c))
    for d in "0123456789":
        t[str(d)] = "Digit" + str(d)
        t["kp_" + str(d)] = "Numpad" + str(d)
    named := {"enter": "Enter", "escape": "Escape", "backspace": "Backspace", "tab": "Tab", "space": "Space",
              "minus": "Minus", "equal": "Equal", "left_brace": "BracketLeft", "right_brace": "BracketRight",
              "backslash": "Backslash", "semicolon": "Semicolon", "apostrophe": "Quote", "grave": "Backquote",
              "comma": "Comma", "dot": "Period", "slash": "Slash", "caps_lock": "CapsLock",
              "print_screen": "PrintScreen", "scroll_lock": "ScrollLock", "pause": "Pause", "insert": "Insert",
              "home": "Home", "page_up": "PageUp", "delete": "Delete", "end": "End", "page_down": "PageDown",
              "right": "ArrowRight", "left": "ArrowLeft", "down": "ArrowDown", "up": "ArrowUp", "num_lock": "NumLock",
              "kp_slash": "NumpadDivide", "kp_asterisk": "NumpadMultiply", "kp_minus": "NumpadSubtract",
              "kp_plus": "NumpadAdd", "kp_enter": "NumpadEnter", "kp_dot": "NumpadDecimal",
              "less_greater": "IntlBackslash", "menu": "ContextMenu", "left_ctrl": "ControlLeft",
              "right_ctrl": "ControlRight", "left_shift": "ShiftLeft", "right_shift": "ShiftRight",
              "left_alt": "AltLeft", "right_alt": "AltRight", "left_meta": "MetaLeft", "right_meta": "MetaRight"}
    for k in named:
        t[k] = named[k]
    f := 1
    while f <= 24:
        t["f" + str(f)] = "F" + str(f)
        f += 1
    return t

_HID := _build_hid()
_HID_BY_NAME := {}
for _h in _HID:
    _HID_BY_NAME[_HID[_h]] = _h
_DOM := _build_dom()
_DOM_BY_CODE := {}
for _d in _DOM:
    _DOM_BY_CODE[_DOM[_d]] = _d

# Bits du premier octet (modificateurs) d'un rapport clavier HID « boot ».
const HID_MODIFIERS := {1: "left_ctrl", 2: "left_shift", 4: "left_alt", 8: "left_meta", 16: "right_ctrl",
                        32: "right_shift", 64: "right_alt", 128: "right_meta"}

func _safe(fn):
    try:
        return fn()
    catch e:
        return null

class KeyCode:
    func init(name):
        n := _key.normalize(name)
        self.name = n
        self.vk = _safe(() => _key.code(n))
        self.evdev = _safe(() => _key.to_evdev(n))
        self.hid = null
        if n in _HID_BY_NAME:
            self.hid = _HID_BY_NAME[n]
        self.dom = null
        if n in _DOM:
            self.dom = _DOM[n]
        if self.vk == null and self.evdev == null and self.hid == null and self.dom == null:
            raise("ArgumentError", "touche inconnue : '" + str(name) + "'")

    func is_modifier():
        return _key.is_modifier(self.name)

    func is_printable():
        return _key.is_printable(self.name)

    func to_dict():
        return {"name": self.name, "vk": self.vk, "evdev": self.evdev, "hid": self.hid, "dom": self.dom}

    func __str__():
        return "KeyCode(" + self.name + ")"

func from_vk(vk):
    n := _key.name(vk)
    if n == null:
        raise("ArgumentError", "code virtuel inconnu : " + str(vk))
    return KeyCode(n)

func from_evdev(code):
    n := _key.from_evdev(code)
    if n == null:
        raise("ArgumentError", "code evdev inconnu : " + str(code))
    return KeyCode(n)

func from_hid(usage):
    if not (usage in _HID):
        raise("ArgumentError", "usage HID clavier inconnu : " + str(usage))
    return KeyCode(_HID[usage])

func from_dom(code):
    if not (code in _DOM_BY_CODE):
        raise("ArgumentError", "KeyboardEvent.code inconnu : '" + str(code) + "'")
    return KeyCode(_DOM_BY_CODE[code])

func hid_to_vk(usage):
    return from_hid(usage).vk

func hid_to_evdev(usage):
    return from_hid(usage).evdev

func evdev_to_hid(code):
    return from_evdev(code).hid

func vk_to_hid(vk):
    return from_vk(vk).hid

# Modificateurs (noms) d'un octet HID, et masque keyboard.key (CTRL | SHIFT | ALT | META).
func hid_modifier_names(byte_value):
    out := []
    for bit in HID_MODIFIERS:
        if byte_value & bit != 0:
            append(out, HID_MODIFIERS[bit])
    return out

func hid_modifier_mask(byte_value):
    m := 0
    if byte_value & 17 != 0:
        m = m | _key.CTRL
    if byte_value & 34 != 0:
        m = m | _key.SHIFT
    if byte_value & 68 != 0:
        m = m | _key.ALT
    if byte_value & 136 != 0:
        m = m | _key.META
    return m

# « vk:65 », « evdev:30 », « hid:4 », « dom:KeyA » / « KeyA », ou un nom (« a », « Escape »).
func parse(text):
    t := _s.trim(str(text))
    if _s.contains(t, ":"):
        k := _s.find(t, ":")
        sys := _s.lower(_s.substring(t, 0, k))
        v := _s.substring(t, k + 1, len(t))
        if sys == "vk":
            return from_vk(_num(v))
        if sys == "evdev":
            return from_evdev(_num(v))
        if sys == "hid":
            return from_hid(_num(v))
        if sys == "dom":
            return from_dom(v)
        raise("ArgumentError", "système de codes inconnu : '" + sys + "'")
    if t in _DOM_BY_CODE:
        return from_dom(t)
    return KeyCode(t)

func _num(v):
    t := _s.lower(_s.trim(v))
    if _s.starts_with(t, "0x"):
        n := 0
        for c in _s.substring(t, 2, len(t)):
            d := _s.find("0123456789abcdef", str(c))
            if d < 0:
                raise("ArgumentError", "nombre hexadécimal invalide : " + v)
            n = n * 16 + d
        return n
    return to_int(t)

func hid_names():
    return [_HID[k] for k in _HID]

func dom_codes():
    return [k for k in _DOM_BY_CODE]
