# ALEX STANDARD LIBRARY — keyboard.key_event
#
# KeyEvent : un appui, un relâchement ou une répétition de touche, quelle que soit sa source — fenêtre (window,
# ui), clavier brut du noyau (hardware.keyboard / evdev), ou terminal (io.console.read_key) — avec le même nom de
# touche (keyboard.key), les modificateurs et le texte produit.
#
#   use keyboard.key_event as ke
#   e := ke.from_window_event(ev)              # ev : dict de window.poll()
#   if e != null and e.matches("ctrl+s"):
#       sauvegarder()
#   r := ke.parse_shortcut("Ctrl+Shift+F5")    # ["f5", CTRL | SHIFT]
#   print(e.describe())                         # « ctrl+shift+f5 (appui) »
#
# Erreurs : ArgumentError (raccourci mal formé), TypeError.

from core use type, len
from collections use contains_key, append
use string as _s
use os as _os
use keyboard.key as _key

class KeyEvent:
    func init(key, action="press", mods=0, text="", code=null, source="program", time=null):
        self.key = key            # nom uniforme (keyboard.key)
        self.action = action      # "press", "release" ou "repeat"
        self.mods = mods          # masque keyboard.key.CTRL | SHIFT | ALT | META
        self.text = text          # texte produit (UTF-8), "" pour une touche de commande
        self.code = code          # code d'origine (virtuel ou evdev)
        self.source = source      # "window", "evdev", "terminal" ou "program"
        if time == null:
            time = _os.monotonic_time()
        self.time = time

    func pressed():
        return self.action != "release"

    func is_repeat():
        return self.action == "repeat"

    func ctrl():
        return (self.mods & _key.CTRL) != 0

    func shift():
        return (self.mods & _key.SHIFT) != 0

    func alt():
        return (self.mods & _key.ALT) != 0

    func meta():
        return (self.mods & _key.META) != 0

    # Vrai si l'événement est un appui (ou une répétition) qui correspond au raccourci (« ctrl+s », « F5 »).
    # Les modificateurs doivent être exactement ceux du raccourci.
    func matches(shortcut):
        if self.action == "release":
            return false
        r := parse_shortcut(shortcut)
        return self.key == r[0] and (self.mods & 15) == r[1]

    # « ctrl+shift+f5 »
    func combo():
        parts := _key.mods_names(self.mods)
        if not _key.is_modifier(self.key):
            append(parts, self.key)
        elif len(parts) == 0:
            append(parts, self.key)
        return _s.join("+", parts)

    func describe():
        a := {"press": "appui", "release": "relâchement", "repeat": "répétition"}
        return self.combo() + " (" + a[self.action] + ")"

    func to_dict():
        return {"key": self.key, "action": self.action, "mods": self.mods, "text": self.text, "code": self.code,
                "source": self.source}

# [nom de touche, masque de modificateurs] d'un raccourci « Ctrl+Shift+S » (séparateurs « + » ou « - »).
func parse_shortcut(text):
    if type(text) != "str" or _s.trim(text) == "":
        raise("ArgumentError", "parse_shortcut : raccourci (str non vide) attendu")
    t := _s.replace(_s.trim(text), " ", "")
    parts := _s.split(t, "+")
    if len(parts) == 1 and len(t) > 1 and _s.contains(t, "-"):
        parts = _s.split(t, "-")
    mods := 0
    key := null
    for p in parts:
        if p == "":
            raise("ArgumentError", "parse_shortcut : raccourci mal formé '" + text + "'")
        n := _key.normalize(p)
        b := 0
        if n == "ctrl" or n == "shift" or n == "alt" or n == "meta":
            b = _key.modifier_bit(n)
        if b != 0:
            mods = mods | b
        else:
            if key != null:
                raise("ArgumentError", "parse_shortcut : plusieurs touches dans '" + text + "'")
            key = n
    if key == null:
        raise("ArgumentError", "parse_shortcut : aucune touche dans '" + text + "'")
    return [key, mods]

func format_shortcut(key, mods):
    parts := _key.mods_names(mods)
    append(parts, key)
    return _s.join("+", parts)

# KeyEvent d'un dict d'événement de fenêtre (window / ui : key_down, key_up), ou null pour un autre type.
func from_window_event(ev):
    if ev == null or type(ev) != "dict" or not contains_key(ev, "type"):
        return null
    t := ev["type"]
    if t != "key_down" and t != "key_up":
        return null
    vk := 0
    if contains_key(ev, "key"):
        vk = ev["key"]
    mods := 0
    if contains_key(ev, "mods"):
        mods = ev["mods"]
    text := ""
    if contains_key(ev, "text"):
        text = ev["text"]
    action := "press"
    if t == "key_up":
        action = "release"
    name := _key.name(vk)
    if vk == 0 and text != "":
        name = _s.lower(text)    # saisie de texte sans code de touche (composition, inject_text)
    return KeyEvent(name, action, mods, text, vk, "window")

# KeyEvent d'un hardware.keyboard.KeyEvent (lecture brute evdev) ; mods : état des modificateurs connu.
func from_evdev(e, mods=0):
    return KeyEvent(_key.from_evdev(e.code), e.action, mods, "", e.code, "evdev", e.time)

# KeyEvent d'un nom de touche d'io.console.read_key (« ctrl+c », « up », « a »...).
func from_terminal(name):
    if name == null:
        return null
    mods := 0
    k := name
    if _s.starts_with(name, "ctrl+") and len(name) > 5:
        mods = _key.CTRL
        k = _s.substring(name, 5, len(name))
    text := ""
    if len(k) == 1 and mods == 0:
        text = k
    return KeyEvent(_key.normalize(k), "press", mods, text, null, "terminal")
