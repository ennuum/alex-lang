# ALEX STANDARD LIBRARY — keyboard
#
# Le clavier : état des touches (lesquelles sont enfoncées, modificateurs), raccourcis, saisie de texte, quelle que
# soit la source des événements — une fenêtre (window), le clavier brut du noyau (evdev, hardware.keyboard) ou le
# terminal.
#
#   use keyboard
#   kb := keyboard.Keyboard()
#   kb.shortcuts.add("ctrl+s", sauvegarder)
#   kb.shortcuts.add("ctrl+q", () => fenetre.close())
#   for ev in fenetre.poll_all():
#       kb.feed_window_event(ev)                 # met à jour l'état, déclenche les raccourcis
#   if kb.is_pressed("left") and kb.shift():
#       selectionner()
#
#   r := keyboard.open_raw()                     # clavier physique (droits sur /dev/input)
#   e := r.read(1.0)                             # keyboard.key_event.KeyEvent (ou null)
#   print(keyboard.layout().type_text(evenements))
#
# Modules : keyboard.key (noms et codes), keyboard.key_event (KeyEvent, raccourcis), keyboard.keyboard_layout
# (dispositions AZERTY, QWERTY, QWERTZ...), hardware.keyboard (périphériques).
#
# Erreurs : HardwareError (clavier brut absent ou droits), ArgumentError (raccourci mal formé), TypeError.

from core use type, len, arity
from collections use append, contains_key, keys, remove
use keyboard.key as _key
use keyboard.key_event as _ke
use keyboard.keyboard_layout as _layout
use hardware.keyboard as _hw
use io.console as _console

class Shortcuts:
    func init():
        self._map = {}        # "ctrl+s" -> [fonction]

    # Associe le raccourci (« ctrl+s », « F5 », « ctrl+shift+z ») à fn(KeyEvent) ou fn().
    func add(shortcut, fn):
        r := _ke.parse_shortcut(shortcut)
        k := _ke.format_shortcut(r[0], r[1])
        if not contains_key(self._map, k):
            self._map[k] = []
        append(self._map[k], fn)
        return k

    func remove(shortcut):
        r := _ke.parse_shortcut(shortcut)
        k := _ke.format_shortcut(r[0], r[1])
        if contains_key(self._map, k):
            _col_remove(self._map, k)
            return true
        return false

    func has(shortcut):
        r := _ke.parse_shortcut(shortcut)
        return contains_key(self._map, _ke.format_shortcut(r[0], r[1]))

    func list():
        return [k for k in keys(self._map)]

    # Exécute les fonctions du raccourci correspondant à l'événement (appui) ; renvoie true s'il y en avait.
    func handle(e):
        if e == null or e.action == "release":
            return false
        k := _ke.format_shortcut(e.key, e.mods & 15)
        if not contains_key(self._map, k):
            return false
        for fn in self._map[k]:
            if arity(fn)[1] == 0:
                fn()
            else:
                fn(e)
        return true

func _col_remove(d, k):
    remove(d, k)

class Keyboard:
    func init(layout_code=null):
        self._down = {}            # nom -> instant de l'appui
        self._mods = 0
        self.shortcuts = Shortcuts()
        self.text = []             # texte saisi (fenêtre)
        self.history = []          # derniers KeyEvent (au plus 64)
        self.layout = null
        if layout_code != null:
            self.layout = _layout.get(layout_code)

    # Met à jour l'état avec un KeyEvent ; déclenche les raccourcis. Renvoie l'événement.
    func feed(e):
        if e == null:
            return null
        if e.action == "release":
            if contains_key(self._down, e.key):
                remove(self._down, e.key)
        else:
            if not contains_key(self._down, e.key):
                self._down[e.key] = e.time
        bit := 0
        if _key.is_modifier(e.key):
            bit = _key.modifier_bit(e.key)
        if bit != 0:
            if e.action == "release":
                if not self._any_down_with_bit(bit):
                    self._mods = self._mods & ~bit
            else:
                self._mods = self._mods | bit
        elif e.source == "window":
            self._mods = e.mods & 15          # la fenêtre donne l'état exact des modificateurs
        if e.pressed() and e.text != "" and (e.mods & (_key.CTRL | _key.ALT)) == 0:
            append(self.text, e.text)
        append(self.history, e)
        if len(self.history) > 64:
            self.history = [self.history[k] for k in 1..len(self.history)]
        self.shortcuts.handle(e)
        return e

    func _any_down_with_bit(bit):
        for k in keys(self._down):
            if _key.is_modifier(k) and _key.modifier_bit(k) == bit:
                return true
        return false

    # Événement de fenêtre (dict de window.poll / ui) ; ignore les autres types. Renvoie le KeyEvent ou null.
    func feed_window_event(ev):
        return self.feed(_ke.from_window_event(ev))

    func is_pressed(name):
        return contains_key(self._down, _key.normalize(name))

    func pressed():
        return [k for k in keys(self._down)]

    func mods():
        return self._mods

    func ctrl():
        return (self._mods & _key.CTRL) != 0

    func shift():
        return (self._mods & _key.SHIFT) != 0

    func alt():
        return (self._mods & _key.ALT) != 0

    func meta():
        return (self._mods & _key.META) != 0

    # Durée (secondes) depuis l'appui de la touche, ou null si elle n'est pas enfoncée.
    func held_for(name, now=null):
        n := _key.normalize(name)
        if not contains_key(self._down, n):
            return null
        if now == null:
            now = _now()
        return now - self._down[n]

    # Texte saisi depuis le dernier appel (et le vide).
    func take_text():
        t := _join(self.text)
        self.text = []
        return t

    func reset():
        self._down = {}
        self._mods = 0
        self.text = []

use os as _os
use string as _s

func _now():
    return _os.monotonic_time()

func _join(parts):
    return _s.join("", parts)

# ---------------------------------------------------------------- clavier brut (evdev)
class RawKeyboard:
    func init(device=null, layout_code=null):
        self._r = _hw.open(device)
        self.state = Keyboard(layout_code)

    # Prochain KeyEvent (modificateurs suivis), ou null après timeout secondes.
    func read(timeout=null):
        e := self._r.read(timeout)
        if e == null:
            return null
        k := _ke.from_evdev(e, self.state.mods())
        self.state.feed(k)
        k.mods = self.state.mods()
        return k

    func close():
        self._r.close()

func open_raw(device=null, layout_code=null):
    return RawKeyboard(device, layout_code)

# Claviers physiques (hardware.keyboard.Keyboard).
func devices():
    return _hw.keyboards()

func available():
    return _hw.available()

# Disposition (keyboard_layout.KeyboardLayout) : celle demandée, ou celle du système.
func layout(code=null):
    if code == null:
        code = _layout.detect()
    return _layout.get(code)

# Touche du terminal (io.console.read_key) en KeyEvent ; null après timeout.
func read_terminal_key(timeout=null):
    return _ke.from_terminal(_console.read_key(timeout))
