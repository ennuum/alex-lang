# ALEX STANDARD LIBRARY — hardware.keyboard
#
# Claviers branchés (Linux : /proc/bus/input/devices) et lecture de leurs touches au niveau du matériel
# (/dev/input/eventN) : appuis ET relâchements, toutes les touches (Maj, Ctrl, Fn...), même sans terminal.
# La lecture exige les droits sur /dev/input (root ou groupe « input »), sinon HardwareError.
#
# Pour lire une touche dans le terminal (cas courant, sans droits particuliers) : read_terminal_key(), qui
# est io.console.read_key.
#
# Exemple
#   use hardware.keyboard as keyboard
#   for k in keyboard.keyboards():
#       print(k.name, k.path)
#   kb := keyboard.open()
#   e := kb.read(5.0)          # KeyEvent : e.key ("a", "enter", "left_shift"...), e.action ("press"...)
#   kb.close()
#
# Erreurs : HardwareError (aucun clavier, droits, plateforme).

from core use len, type
from collections use append, contains_key
use hardware._sys as _sys
use hardware._input as _in
use io.console as _console

class Keyboard:
    func init(info):
        self.name = info["name"]
        self.path = null
        if len(info["events"]) > 0:
            self.path = info["events"][0]
        self.phys = info["phys"]
        self.vendor_id = info["vendor"]
        self.product_id = info["product"]
        self.bus = info["bus"]

    func open():
        return open(self)

func _is_keyboard(d):
    has_kbd := false
    for h in d["handlers"]:
        if h == "kbd":
            has_kbd = true
    if not has_kbd or (d["ev"] >> _in.EV_KEY) & 1 != 1:
        return false
    if len(d["key"]) > 0:
        return _sys.mask_bit(d["key"], 30) and _sys.mask_bit(d["key"], 57)   # A et Espace
    return (d["ev"] >> 20) & 1 == 1                                          # répétition automatique

# Claviers présents (list de Keyboard) ; [] hors Linux.
func keyboards():
    return [Keyboard(d) for d in _sys.input_devices() if _is_keyboard(d)]

func available():
    return len(keyboards()) > 0

_NAMES := {1: "escape", 2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0", 12: "minus", 13: "equal", 14: "backspace", 15: "tab", 16: "q", 17: "w", 18: "e", 19: "r", 20: "t", 21: "y", 22: "u", 23: "i", 24: "o", 25: "p", 26: "left_brace", 27: "right_brace", 28: "enter", 29: "left_ctrl", 30: "a", 31: "s", 32: "d", 33: "f", 34: "g", 35: "h", 36: "j", 37: "k", 38: "l", 39: "semicolon", 40: "apostrophe", 41: "grave", 42: "left_shift", 43: "backslash", 44: "z", 45: "x", 46: "c", 47: "v", 48: "b", 49: "n", 50: "m", 51: "comma", 52: "dot", 53: "slash", 54: "right_shift", 55: "kp_asterisk", 56: "left_alt", 57: "space", 58: "caps_lock", 59: "f1", 60: "f2", 61: "f3", 62: "f4", 63: "f5", 64: "f6", 65: "f7", 66: "f8", 67: "f9", 68: "f10", 69: "num_lock", 70: "scroll_lock", 71: "kp_7", 72: "kp_8", 73: "kp_9", 74: "kp_minus", 75: "kp_4", 76: "kp_5", 77: "kp_6", 78: "kp_plus", 79: "kp_1", 80: "kp_2", 81: "kp_3", 82: "kp_0", 83: "kp_dot", 86: "less_greater", 87: "f11", 88: "f12", 96: "kp_enter", 97: "right_ctrl", 98: "kp_slash", 99: "print_screen", 100: "right_alt", 102: "home", 103: "up", 104: "page_up", 105: "left", 106: "right", 107: "end", 108: "down", 109: "page_down", 110: "insert", 111: "delete", 113: "mute", 114: "volume_down", 115: "volume_up", 116: "power", 119: "pause", 125: "left_meta", 126: "right_meta", 127: "menu"}

# Nom d'un code de touche Linux (KEY_*) : "a", "enter", "left_shift"... ; "key_<code>" s'il est inconnu.
func key_name(code):
    if contains_key(_NAMES, code):
        return _NAMES[code]
    return "key_" + str(code)

_ACTIONS := ["release", "press", "repeat"]

class KeyEvent:
    func init(key, code, action, time):
        self.key = key
        self.code = code
        self.action = action      # "press", "release" ou "repeat"
        self.time = time

    func pressed():
        return self.action != "release"

class KeyboardReader:
    func init(path):
        self.path = path
        self._r = _in.Reader(path, "keyboard.open")

    # Prochain événement de touche (KeyEvent), ou null après timeout secondes.
    func read(timeout=null):
        while true:
            e := self._r.read_event(timeout)
            if e == null:
                return null
            if e.type == _in.EV_KEY and e.code < 256 and e.value >= 0 and e.value <= 2:
                return KeyEvent(key_name(e.code), e.code, _ACTIONS[e.value], e.time)

    func close():
        self._r.close()

# Ouvre un clavier (Keyboard, chemin /dev/input/eventN, ou null : le premier trouvé).
func open(device=null):
    path := device
    if device == null:
        ks := keyboards()
        if len(ks) == 0:
            _sys.fail("keyboard.open", "aucun clavier trouvé")
        path = ks[0].path
    elif type(device) != "str":
        path = device.path
    if path == null:
        _sys.fail("keyboard.open", "ce clavier n'a pas de nœud /dev/input/event")
    return KeyboardReader(path)

# Touche lue dans le terminal (io.console.read_key) : "a", "up", "enter", "ctrl+c"... ou null après timeout.
func read_terminal_key(timeout=null):
    return _console.read_key(timeout)
