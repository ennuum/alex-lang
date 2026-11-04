# ALEX STANDARD LIBRARY — input.input_manager
#
# Gestionnaire d'entrées d'une application (jeu, kiosque, interface tactile) : réunit plusieurs SOURCES
# (fenêtre, périphériques evdev ouverts, événements injectés), diffuse des InputEvent unifiés, tient l'état
# courant (touches et boutons enfoncés, axes, position), et associe des ACTIONS nommées à plusieurs entrées
# (« sauter » = espace OU bouton south de la manette OU tap) avec des AXES virtuels (« horizontal » =
# flèches gauche/droite OU stick gauche).
#
#   use input.input_manager as im
#   m := im.InputManager()
#   m.add_window(fenetre)                          # événements de fenêtre
#   m.add_device(input_device.first("gamepad"))    # ou toute source ayant read(timeout)
#   m.bind_action("sauter", ["key:space", "button:south", "gesture:tap"])
#   m.bind_axis("horizontal", "key:left", "key:right", "axis:x")
#   m.on_action("sauter", () => joueur.sauter())
#   while actif:
#       m.poll()                                    # lit toutes les sources, met l'état à jour, rappels
#       vx := m.axis("horizontal")                  # -1..1
#       if m.is_action_down("sauter"): ...
#   m.inject(input_event.InputEvent("key", "space", 1))   # tests / rejeu
#
# Erreurs : ArgumentError (liaison mal formée), TypeError.

from core use len, type
from collections use append
use string as _s
use event.event_emitter as _ee
use input.input_event as _ev
use input.gamepad as _gp

func _parse_binding(b):
    k := _s.find(b, ":")
    if k <= 0:
        raise("ArgumentError", "liaison « genre:nom » attendue (key:space, button:south, axis:x, gesture:tap) : " + b)
    return [_s.substring(b, 0, k), _s.substring(b, k + 1, len(b))]

class InputManager:
    func init():
        self.sources = []         # [genre, objet]
        self.events = _ee.EventEmitter(1000)
        self.down = {}            # "key:a" / "button:left" -> true
        self.axes = {}            # nom d'axe brut -> valeur
        self.position = [0, 0]
        self.actions = {}         # action -> [liaisons]
        self.virtual_axes = {}    # nom -> [négatif, positif, axe]
        self.action_cbs = {}
        self.pads = {}            # source -> Gamepad (normalisation des axes de manette)
        self.processed = 0

    func add_window(win):
        append(self.sources, ["window", win])
        return self

    func add_device(device):
        r := device
        try:
            r = device.open()
        catch e:
            r = device
        append(self.sources, ["device", r])
        if device.kind == "gamepad":
            self.pads[len(self.sources) - 1] = _gp.Gamepad()
        return self

    func add_reader(reader, kind="unknown"):
        append(self.sources, ["device", reader])
        if kind == "gamepad":
            self.pads[len(self.sources) - 1] = _gp.Gamepad()
        return self

    func on(kind, fn):
        return self.events.on(kind, fn)

    func bind_action(action, bindings):
        for b in bindings:
            _parse_binding(b)
        self.actions[action] = bindings
        return self

    func bind_axis(name, negative, positive, analog=null):
        self.virtual_axes[name] = [negative, positive, analog]
        return self

    func on_action(action, fn):
        if not (action in self.action_cbs):
            self.action_cbs[action] = []
        append(self.action_cbs[action], fn)
        return self

    func _key_of(e):
        if e.kind == "key":
            return "key:" + str(e.name)
        if e.kind == "button":
            return "button:" + str(e.name)
        return null

    # Traite un événement (InputEvent ou dict de geste {"type": ...}).
    func inject(e, source_index=null):
        self.processed += 1
        if type(e) == "dict":
            self.events.emit("gesture", e)
            self._fire("gesture:" + e["type"], e)
            return
        k := self._key_of(e)
        if k != null:
            was := k in self.down
            if e.value != 0:
                self.down[k] = true
                if not was:
                    self._fire(k, e)
            elif was:
                del self.down[k]
        elif e.kind == "axis":
            v := e.value
            if source_index != null and source_index in self.pads:
                pad := self.pads[source_index]
                pad.feed(e)
                v = pad.axis(e.name)
            self.axes[e.name] = v
        elif e.kind == "motion" and e.x != null:
            self.position = [e.x, e.y]
        self.events.emit(e.kind, e)
        self.events.emit("*", e)

    func _fire(binding, e):
        for a in self.actions:
            if binding in self.actions[a]:
                if a in self.action_cbs:
                    for fn in self.action_cbs[a]:
                        fn()
                self.events.emit("action", a)

    # Lit toutes les sources disponibles ; nombre d'événements traités.
    func poll(timeout=0.0):
        n := 0
        i := 0
        while i < len(self.sources):
            src := self.sources[i]
            if src[0] == "window":
                for raw in src[1].poll_all():
                    e := _ev.from_window_event(raw)
                    if e != null:
                        self.inject(e, i)
                        n += 1
            else:
                e := src[1].read(timeout)
                while e != null:
                    if e.kind != "sync":
                        self.inject(e, i)
                        n += 1
                    e = src[1].read(0.0)
            i += 1
        return n

    func is_down(binding):
        return binding in self.down

    func is_action_down(action):
        if not (action in self.actions):
            return false
        for b in self.actions[action]:
            if b in self.down:
                return true
        return false

    func raw_axis(name):
        if name in self.axes:
            return self.axes[name]
        return 0.0

    # Axe virtuel dans [-1, 1] : entrée analogique si elle dépasse la zone morte, sinon les deux entrées tout-ou-rien.
    func axis(name, deadzone=0.15):
        if not (name in self.virtual_axes):
            raise("ArgumentError", "axe virtuel inconnu : " + name)
        va := self.virtual_axes[name]
        if va[2] != null:
            p := _parse_binding(va[2])
            v := self.raw_axis(p[1])
            if v > deadzone or v < -deadzone:
                return v
        out := 0.0
        if va[0] in self.down:
            out -= 1.0
        if va[1] in self.down:
            out += 1.0
        return out

    func pressed():
        return [k for k in self.down]

    func reset():
        self.down = {}
        self.axes = {}

    func close():
        for s in self.sources:
            if s[0] == "device":
                try:
                    s[1].close()
                catch e:
                    s = s
        self.sources = []
