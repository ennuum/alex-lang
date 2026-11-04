# ALEX STANDARD LIBRARY — keyboard.key
#
# Les touches : noms uniformes (« a », « 1 », « enter », « left », « f5 », « left_ctrl »...), codes virtuels des
# fenêtres (ceux de window / ui, façon Win32 : A = 65, F1 = 112, flèche gauche = 37) et codes du noyau Linux
# (evdev, ceux de hardware.keyboard : A = 30). Modificateurs en masque de bits.
#
#   use keyboard.key as key
#   print(key.name(65), key.code("f5"), key.from_evdev(30))      # a 116 a
#   print(key.mods_names(key.CTRL | key.SHIFT))                  # [ctrl, shift]
#   print(key.is_modifier("left_shift"), key.is_printable("a"))
#
# Les noms suivent hardware.keyboard (evdev) : un même nom désigne la même touche quelle que soit la source.

from core use type, len
from collections use append, contains_key, keys
use string as _s

# Modificateurs (mêmes valeurs que les événements de fenêtre : MOD_ALT=1, MOD_CONTROL=2, MOD_SHIFT=4, MOD_WIN=8).
const ALT := 1
const CTRL := 2
const SHIFT := 4
const META := 8

# Codes virtuels courants.
const BACKSPACE := 8
const TAB := 9
const ENTER := 13
const SHIFT_KEY := 16
const CTRL_KEY := 17
const ALT_KEY := 18
const PAUSE := 19
const CAPS_LOCK := 20
const ESCAPE := 27
const SPACE := 32
const PAGE_UP := 33
const PAGE_DOWN := 34
const END := 35
const HOME := 36
const LEFT := 37
const UP := 38
const RIGHT := 39
const DOWN := 40
const INSERT := 45
const DELETE := 46
const F1 := 112
const F12 := 123

func _build_vk():
    t := {8: "backspace", 9: "tab", 13: "enter", 16: "shift", 17: "ctrl", 18: "alt", 19: "pause", 20: "caps_lock",
          27: "escape", 32: "space", 33: "page_up", 34: "page_down", 35: "end", 36: "home", 37: "left", 38: "up",
          39: "right", 40: "down", 44: "print_screen", 45: "insert", 46: "delete", 91: "left_meta", 92: "right_meta",
          93: "menu", 106: "kp_asterisk", 107: "kp_plus", 109: "kp_minus", 110: "kp_dot", 111: "kp_slash",
          144: "num_lock", 145: "scroll_lock", 160: "left_shift", 161: "right_shift", 162: "left_ctrl",
          163: "right_ctrl", 164: "left_alt", 165: "right_alt", 186: "semicolon", 187: "equal", 188: "comma",
          189: "minus", 190: "dot", 191: "slash", 192: "grave", 219: "left_brace", 220: "backslash",
          221: "right_brace", 222: "apostrophe", 226: "less_greater"}
    letters := "abcdefghijklmnopqrstuvwxyz"
    i := 0
    while i < 26:
        t[65 + i] = str(letters[i])
        i += 1
    d := 0
    while d < 10:
        t[48 + d] = str(d)
        t[96 + d] = "kp_" + str(d)
        d += 1
    f := 1
    while f <= 24:
        t[111 + f] = "f" + str(f)
        f += 1
    return t

_VK := _build_vk()
_BY_NAME := {}
for _k in keys(_VK):
    if not contains_key(_BY_NAME, _VK[_k]):
        _BY_NAME[_VK[_k]] = _k

# evdev (linux/input-event-codes.h) -> nom : les mêmes noms que hardware.keyboard.
_EVDEV := {1: "escape", 2: "1", 3: "2", 4: "3", 5: "4", 6: "5", 7: "6", 8: "7", 9: "8", 10: "9", 11: "0", 12: "minus",
           13: "equal", 14: "backspace", 15: "tab", 16: "q", 17: "w", 18: "e", 19: "r", 20: "t", 21: "y", 22: "u", 23: "i",
           24: "o", 25: "p", 26: "left_brace", 27: "right_brace", 28: "enter", 29: "left_ctrl", 30: "a", 31: "s", 32: "d",
           33: "f", 34: "g", 35: "h", 36: "j", 37: "k", 38: "l", 39: "semicolon", 40: "apostrophe", 41: "grave",
           42: "left_shift", 43: "backslash", 44: "z", 45: "x", 46: "c", 47: "v", 48: "b", 49: "n", 50: "m", 51: "comma",
           52: "dot", 53: "slash", 54: "right_shift", 55: "kp_asterisk", 56: "left_alt", 57: "space", 58: "caps_lock",
           59: "f1", 60: "f2", 61: "f3", 62: "f4", 63: "f5", 64: "f6", 65: "f7", 66: "f8", 67: "f9", 68: "f10", 69: "num_lock",
           70: "scroll_lock", 71: "kp_7", 72: "kp_8", 73: "kp_9", 74: "kp_minus", 75: "kp_4", 76: "kp_5", 77: "kp_6",
           78: "kp_plus", 79: "kp_1", 80: "kp_2", 81: "kp_3", 82: "kp_0", 83: "kp_dot", 86: "less_greater", 87: "f11",
           88: "f12", 96: "kp_enter", 97: "right_ctrl", 98: "kp_slash", 99: "print_screen", 100: "right_alt", 102: "home",
           103: "up", 104: "page_up", 105: "left", 106: "right", 107: "end", 108: "down", 109: "page_down", 110: "insert",
           111: "delete", 113: "mute", 114: "volume_down", 115: "volume_up", 116: "power", 119: "pause", 125: "left_meta",
           126: "right_meta", 127: "menu"}
_EVDEV_BY_NAME := {}
for _e in keys(_EVDEV):
    _EVDEV_BY_NAME[_EVDEV[_e]] = _e

# Nom d'un code virtuel de fenêtre (« key_N » s'il est inconnu).
func name(vk):
    if type(vk) != "int":
        raise("TypeError", "key.name : code (int) attendu")
    if contains_key(_VK, vk):
        return _VK[vk]
    return "key_" + str(vk)

_ALIASES := {"return": "enter", "esc": "escape", "del": "delete", "ins": "insert", "pgup": "page_up",
             "pgdn": "page_down", "control": "ctrl", "option": "alt", "cmd": "meta", "command": "meta", "super": "meta",
             "win": "meta", "windows": "meta", "spacebar": "space", "period": "dot", "backquote": "grave",
             "arrowleft": "left", "arrowright": "right", "arrowup": "up", "arrowdown": "down"}

# Nom normalisé (minuscules, alias résolus) : « Return » -> « enter ».
func normalize(n):
    if type(n) != "str":
        raise("TypeError", "key.normalize : nom (str) attendu")
    low := _s.lower(_s.trim(n))
    if contains_key(_ALIASES, low):
        return _ALIASES[low]
    return low

# Code virtuel d'un nom (null s'il n'en a pas).
func code(n):
    low := normalize(n)
    if contains_key(_BY_NAME, low):
        return _BY_NAME[low]
    if low == "meta":
        return 91
    return null

func from_evdev(evcode):
    if contains_key(_EVDEV, evcode):
        return _EVDEV[evcode]
    return "key_" + str(evcode)

func to_evdev(n):
    low := normalize(n)
    if contains_key(_EVDEV_BY_NAME, low):
        return _EVDEV_BY_NAME[low]
    return null

# Touches de modification (shift, ctrl, alt, meta, à gauche ou à droite).
func is_modifier(n):
    low := normalize(n)
    for m in ["shift", "ctrl", "alt", "meta", "left_shift", "right_shift", "left_ctrl", "right_ctrl", "left_alt",
              "right_alt", "left_meta", "right_meta"]:
        if low == m:
            return true
    return false

# Modificateur générique d'une touche (« left_ctrl » -> CTRL), 0 sinon.
func modifier_bit(n):
    low := normalize(n)
    if _s.ends_with(low, "shift"):
        return SHIFT
    if _s.ends_with(low, "ctrl"):
        return CTRL
    if _s.ends_with(low, "alt"):
        return ALT
    if _s.ends_with(low, "meta"):
        return META
    return 0

# Une lettre, un chiffre ou un signe qui produit du texte.
func is_printable(n):
    low := normalize(n)
    if len(low) == 1:
        return true
    for p in ["space", "minus", "equal", "comma", "dot", "slash", "semicolon", "apostrophe", "grave", "left_brace",
              "right_brace", "backslash", "less_greater"]:
        if low == p:
            return true
    return _s.starts_with(low, "kp_") and len(low) == 4

func is_function_key(n):
    low := normalize(n)
    return len(low) >= 2 and low[0] == 'f' and _all_digits(_s.substring(low, 1, len(low)))

func is_navigation(n):
    low := normalize(n)
    for p in ["left", "right", "up", "down", "home", "end", "page_up", "page_down"]:
        if low == p:
            return true
    return false

func _all_digits(t):
    if t == "":
        return false
    for c in t:
        if c < '0' or c > '9':
            return false
    return true

# ["ctrl", "shift"...] d'un masque de modificateurs (ordre : ctrl, alt, shift, meta).
func mods_names(mods):
    out := []
    if mods & CTRL:
        append(out, "ctrl")
    if mods & ALT:
        append(out, "alt")
    if mods & SHIFT:
        append(out, "shift")
    if mods & META:
        append(out, "meta")
    return out

func mods_from_names(names):
    m := 0
    for n in names:
        b := modifier_bit(n)
        if b == 0:
            raise("ArgumentError", "key.mods_from_names : modificateur inconnu '" + n + "'")
        m = m | b
    return m

# Tous les noms connus.
func all_names():
    seen := {}
    out := []
    for k in keys(_VK):
        n := _VK[k]
        if not contains_key(seen, n):
            seen[n] = true
            append(out, n)
    for k in keys(_EVDEV):
        n := _EVDEV[k]
        if not contains_key(seen, n):
            seen[n] = true
            append(out, n)
    return out
