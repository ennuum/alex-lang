# ALEX STANDARD LIBRARY — web.dom.keyboard_event
#
# KeyboardEvent : touche (key), code physique (code), modificateurs, emplacement, répétition, composition ;
# table des codes usuels et construction depuis un raccourci (« Ctrl+Shift+K »).
#
#   use web.dom.keyboard_event as ke
#   e := ke.KeyboardEvent("keydown", {"key": "Enter", "code": "Enter", "ctrl_key": true, "bubbles": true})
#   e.key, e.ctrl_key, e.get_modifier_state("Control")      # Enter true true
#   ke.from_shortcut("Ctrl+Shift+K")                       # KeyboardEvent keydown key « K », ctrl et shift
#   ke.matches_shortcut(e, "Ctrl+Enter")                   # true
#   ke.code_for("a")                                       # KeyA
#   ke.is_printable("é"), ke.is_printable("ArrowLeft")    # true false
#
# Erreurs : DomError (raccourci invalide).

from core use len, type
from collections use append, keys
use string as _s
use web.dom.dom_errors as _err
from web.dom.event use UIEvent

const DOM_KEY_LOCATION_STANDARD := 0
const DOM_KEY_LOCATION_LEFT := 1
const DOM_KEY_LOCATION_RIGHT := 2
const DOM_KEY_LOCATION_NUMPAD := 3

const NAMED_KEYS := ["Enter", "Tab", "Escape", "Backspace", "Delete", "Insert", "Home", "End", "PageUp", "PageDown", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Shift", "Control", "Alt", "Meta", "CapsLock", "NumLock", "ScrollLock", "ContextMenu", "PrintScreen", "Pause", "F1", "F2", "F3", "F4", "F5", "F6", "F7", "F8", "F9", "F10", "F11", "F12", "Dead", "Unidentified", "Process", "AltGraph"]
const _ALIASES := {"ctrl": "Control", "control": "Control", "cmd": "Meta", "meta": "Meta", "super": "Meta", "win": "Meta", "alt": "Alt", "option": "Alt", "shift": "Shift", "esc": "Escape", "escape": "Escape", "enter": "Enter", "return": "Enter", "space": " ", "tab": "Tab", "del": "Delete", "delete": "Delete", "backspace": "Backspace", "up": "ArrowUp", "down": "ArrowDown", "left": "ArrowLeft", "right": "ArrowRight", "home": "Home", "end": "End", "pageup": "PageUp", "pagedown": "PageDown", "insert": "Insert"}

func _opt(o, name, fallback):
    if type(o) == "dict" and name in o:
        return o[name]
    return fallback

func _copy(options):
    o := {}
    if options != null:
        for k in keys(options):
            o[k] = options[k]
    return o

class KeyboardEvent extends UIEvent:
    func init(event_type, options=null):
        o := _copy(options)
        if not ("cancelable" in o):
            o["cancelable"] = true
        if not ("bubbles" in o):
            o["bubbles"] = true
        if not ("composed" in o):
            o["composed"] = true
        super.init(event_type, o)
        self.key = _opt(o, "key", "")
        self.code = _opt(o, "code", code_for(self.key) if self.key != "" else "")
        self.location = _opt(o, "location", 0)
        self.ctrl_key = _opt(o, "ctrl_key", false)
        self.shift_key = _opt(o, "shift_key", false)
        self.alt_key = _opt(o, "alt_key", false)
        self.meta_key = _opt(o, "meta_key", false)
        self.repeat = _opt(o, "repeat", false)
        self.is_composing = _opt(o, "is_composing", false)
        self.caps_lock = _opt(o, "caps_lock", false)

    func get_modifier_state(name):
        if name == "Control":
            return self.ctrl_key
        if name == "Shift":
            return self.shift_key
        if name == "Alt":
            return self.alt_key
        if name == "Meta":
            return self.meta_key
        if name == "CapsLock":
            return self.caps_lock
        return false

    # Code numérique hérité (keyCode) pour les touches courantes.
    func key_code():
        k := self.key
        if len(k) == 1:
            c := _s.upper(k)
            o := _s.ord(c[0])
            if (o >= 65 and o <= 90) or (o >= 48 and o <= 57):
                return o
            if k == " ":
                return 32
        table := {"Enter": 13, "Tab": 9, "Escape": 27, "Backspace": 8, "Delete": 46, "ArrowLeft": 37, "ArrowUp": 38, "ArrowRight": 39, "ArrowDown": 40, "Shift": 16, "Control": 17, "Alt": 18, "Meta": 91, "Home": 36, "End": 35, "PageUp": 33, "PageDown": 34}
        if k in table:
            return table[k]
        return 0

    func shortcut():
        parts := []
        if self.ctrl_key:
            append(parts, "Ctrl")
        if self.alt_key:
            append(parts, "Alt")
        if self.shift_key:
            append(parts, "Shift")
        if self.meta_key:
            append(parts, "Meta")
        k := self.key
        if not (k in ["Control", "Alt", "Shift", "Meta"]):
            append(parts, "Space" if k == " " else (_s.upper(k) if len(k) == 1 else k))
        return _s.join("+", parts)

# Code physique (KeyboardEvent.code) d'une touche sur un clavier QWERTY de référence.
func code_for(key):
    if len(key) == 1:
        c := _s.upper(key)
        o := _s.ord(c[0])
        if o >= 65 and o <= 90:
            return "Key" + c
        if o >= 48 and o <= 57:
            return "Digit" + c
        table := {" ": "Space", "-": "Minus", "=": "Equal", "[": "BracketLeft", "]": "BracketRight", "\\": "Backslash", ";": "Semicolon", "'": "Quote", ",": "Comma", ".": "Period", "/": "Slash", "`": "Backquote"}
        if key in table:
            return table[key]
        return ""
    if key == "Control":
        return "ControlLeft"
    if key == "Shift":
        return "ShiftLeft"
    if key == "Alt":
        return "AltLeft"
    if key == "Meta":
        return "MetaLeft"
    if key in NAMED_KEYS:
        return key
    return ""

# Vrai si la touche produit du texte (un seul caractère).
func is_printable(key):
    return len(key) == 1

func _parse_shortcut(text):
    mods := {"ctrl_key": false, "shift_key": false, "alt_key": false, "meta_key": false}
    key := null
    parts := _s.split(_s.replace(str(text), " ", ""), "+")
    if len(parts) > 1 and parts[len(parts) - 1] == "" and parts[len(parts) - 2] == "":
        parts = parts[0:len(parts) - 2] + ["+"]
    for p in parts:
        if p == "":
            _err.dom_error("keyboard_event", "raccourci invalide « " + str(text) + " »")
        lp := _s.lower(p)
        name := _ALIASES[lp] if lp in _ALIASES else p
        if name == "Control":
            mods["ctrl_key"] = true
        elif name == "Shift":
            mods["shift_key"] = true
        elif name == "Alt":
            mods["alt_key"] = true
        elif name == "Meta":
            mods["meta_key"] = true
        else:
            if key != null:
                _err.dom_error("keyboard_event", "plusieurs touches dans « " + str(text) + " »")
            key = name
    return (key, mods)

# Événement depuis un raccourci « Ctrl+Shift+K » (type keydown par défaut).
func from_shortcut(text, event_type="keydown"):
    r := _parse_shortcut(text)
    o := {"key": r[0] if r[0] != null else "", "bubbles": true, "cancelable": true}
    for k in ["ctrl_key", "shift_key", "alt_key", "meta_key"]:
        o[k] = r[1][k]
    return KeyboardEvent(event_type, o)

# Vrai si l'événement correspond au raccourci (modificateurs exacts, lettre sans casse).
func matches_shortcut(e, text):
    r := _parse_shortcut(text)
    m := r[1]
    if e.ctrl_key != m["ctrl_key"] or e.shift_key != m["shift_key"] or e.alt_key != m["alt_key"] or e.meta_key != m["meta_key"]:
        return false
    if r[0] == null:
        return true
    return _s.lower(e.key) == _s.lower(r[0])

func key_event(event_type, key, options=null):
    o := _copy(options)
    o["key"] = key
    return KeyboardEvent(event_type, o)
