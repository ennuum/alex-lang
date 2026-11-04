# ALEX STANDARD LIBRARY — window.window_events
#
# Événements de fenêtre TYPÉS : les dicts bruts du backend (resize, move, state, focus_in / focus_out, close,
# close_request, drop, shortcut, key_*, pointer_*, wheel) deviennent des objets avec des champs clairs, et un
# WindowEvents permet de s'abonner par catégorie (on_resize, on_move, on_state, on_focus, on_close_request,
# on_drop...). Un EventRecorder enregistre les événements d'une fenêtre (journal, tests, rejeu).
#
#   use window.window_events as wev
#   ev := wev.WindowEvents(fenetre)
#   ev.on_resize((e) => print("taille", e.width, e.height))
#   ev.on_state((e) => print(e.old_state, "->", e.state))
#   ev.on_close_request((e) => e.cancel() if modifie else null)     # empêche la fermeture
#   ev.on_drop((e) => ouvrir(e.paths))
#   rec := wev.EventRecorder(fenetre)
#   ...
#   print(rec.types(), rec.count("resize"))
#   e := wev.wrap({"type": "resize", "x": 800, "y": 600})   # ResizeEvent
#
# Erreurs : TypeError (fonction attendue).

from core use len, type
from collections use append
use string as _s

class WindowEvent:
    func init(raw):
        self.raw = raw
        self.type = raw["type"]
        self.window = _get(raw, "window")
        self.data = _get(raw, "data")

    func __str__():
        return self.type + "(" + str(self.data) + ")"

func _get(d, k):
    if k in d:
        return d[k]
    return null

class ResizeEvent extends WindowEvent:
    func init(raw):
        super.init(raw)
        self.width = _get(raw, "x")
        self.height = _get(raw, "y")

class MoveEvent extends WindowEvent:
    func init(raw):
        super.init(raw)
        self.x = _get(raw, "x")
        self.y = _get(raw, "y")

class StateEvent extends WindowEvent:
    func init(raw, old_state=null):
        super.init(raw)
        self.state = raw["data"]
        self.old_state = old_state

class FocusEvent extends WindowEvent:
    func init(raw):
        super.init(raw)
        self.gained = raw["type"] == "focus_in"

class CloseRequestEvent extends WindowEvent:
    func init(raw):
        super.init(raw)
        self.cancelled = false

    func cancel():
        self.cancelled = true

class DropEvent extends WindowEvent:
    func init(raw):
        super.init(raw)
        d := _get(raw, "data")
        self.paths = []
        if type(d) == "list":
            self.paths = d
        elif type(d) == "str" and d != "":
            self.paths = [p for p in _s.split(d, "\n") if p != ""]
        self.x = _get(raw, "x")
        self.y = _get(raw, "y")

class InputEvent extends WindowEvent:
    func init(raw):
        super.init(raw)
        self.x = _get(raw, "x")
        self.y = _get(raw, "y")
        self.key = _get(raw, "key")
        self.text = _get(raw, "text")
        self.button = _get(raw, "button")
        self.mods = _get(raw, "mods")

const KINDS := {"resize": "geometry", "move": "geometry", "state": "state", "focus_in": "focus", "focus_out": "focus",
                "close": "lifecycle", "close_request": "lifecycle", "drop": "drop", "shortcut": "input",
                "key_down": "input", "key_up": "input", "text": "input", "pointer_down": "input", "pointer_up": "input",
                "pointer_move": "input", "pointer_leave": "input", "wheel": "input"}

func category(event_type):
    if event_type in KINDS:
        return KINDS[event_type]
    return "other"

func wrap(raw, old_state=null):
    t := raw["type"]
    if t == "resize":
        return ResizeEvent(raw)
    if t == "move":
        return MoveEvent(raw)
    if t == "state":
        return StateEvent(raw, old_state)
    if t == "focus_in" or t == "focus_out":
        return FocusEvent(raw)
    if t == "close_request":
        return CloseRequestEvent(raw)
    if t == "drop":
        return DropEvent(raw)
    if category(t) == "input":
        return InputEvent(raw)
    return WindowEvent(raw)

class WindowEvents:
    func init(win):
        self.win = win
        self.last_state = null
        try:
            self.last_state = win.state()
        catch e:
            self.last_state = null
        self.offs = []

    func _on(t, fn):
        if type(fn) != "function":
            raise("TypeError", "WindowEvents : fonction attendue")
        # un écouteur « * » de l'émetteur reçoit aussi (type, [args]) pour chaque événement : seuls les dicts
        # bruts (émission explicite de la fenêtre) sont retenus
        cb := (raw, extra=null) => self._deliver(raw, fn) if type(raw) == "dict" else null
        append(self.offs, [t, cb])
        self.win.on(t, cb)
        return self

    func _deliver(raw, fn):
        old := self.last_state
        if raw["type"] == "state":
            self.last_state = raw["data"]
        e := wrap(raw, old)
        fn(e)
        if raw["type"] == "close_request" and e.cancelled:
            try:
                self.win.confirm_close(true)
            catch x:
                old = old
        return e

    func on_resize(fn):
        return self._on("resize", fn)

    func on_move(fn):
        return self._on("move", fn)

    func on_state(fn):
        return self._on("state", fn)

    func on_focus(fn):
        self._on("focus_in", fn)
        return self._on("focus_out", fn)

    func on_close_request(fn):
        return self._on("close_request", fn)

    func on_close(fn):
        return self._on("close", fn)

    func on_drop(fn):
        return self._on("drop", fn)

    func on_any(fn):
        return self._on("*", fn)

    func detach():
        for o in self.offs:
            self.win.off(o[0], o[1])
        self.offs = []

class EventRecorder:
    func init(win=null, types=null):
        self.events = []
        self.types_filter = types
        self.win = win
        self._cb = (raw, extra=null) => self.record(raw) if type(raw) == "dict" else null
        if win != null:
            win.on("*", self._cb)

    func record(raw):
        if self.types_filter == null or raw["type"] in self.types_filter:
            append(self.events, raw)

    func count(t=null):
        if t == null:
            return len(self.events)
        return len([e for e in self.events if e["type"] == t])

    func types():
        out := []
        for e in self.events:
            if not (e["type"] in out):
                append(out, e["type"])
        return out

    func last(t=null):
        i := len(self.events) - 1
        while i >= 0:
            if t == null or self.events[i]["type"] == t:
                return self.events[i]
            i -= 1
        return null

    func typed():
        return [wrap(e) for e in self.events]

    func clear():
        self.events = []

    func stop():
        if self.win != null:
            self.win.off("*", self._cb)
