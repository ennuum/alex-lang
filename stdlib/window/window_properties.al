# ALEX STANDARD LIBRARY — window.window_properties
#
# Propriétés d'une fenêtre lues et appliquées EN BLOC : titre, position, taille, état, visibilité, focus, style
# (redimensionnable, décorée, toujours devant, opacité, tailles min / max). read(fenêtre) donne un instantané ;
# apply() n'envoie que ce qui change ; diff() compare deux instantanés ; to_dict / from_dict pour l'enregistrer.
# Plus : des propriétés LIBRES attachées à une fenêtre (PropertyBag), avec notification de changement.
#
#   use window.window_properties as wp
#   p := wp.read(fenetre)
#   print(p.title, p.width, p.state, p.opacity)
#   q := p.copy()
#   q.title = "Brouillon *"
#   q.opacity = 0.95
#   print(wp.diff(p, q))                     # {"title": ["…", "Brouillon *"], "opacity": [1.0, 0.95]}
#   q.apply(fenetre)                         # seuls titre et opacité sont envoyés
#   sac := wp.PropertyBag()
#   sac.on_change((cle, ancienne, nouvelle) => print(cle, nouvelle))
#   sac.set("document", "/tmp/a.txt")
#
# Erreurs : ArgumentError (propriété inconnue, valeur invalide), IoError (fenêtre fermée).

from core use len, type
from collections use append
use _native_reflect as _r

const FIELDS := ["title", "x", "y", "width", "height", "state", "visible", "focused", "resizable", "decorated",
                 "topmost", "opacity", "min_width", "min_height", "max_width", "max_height"]

class WindowProperties:
    func init(d=null):
        self.title = "Alex"
        self.x = 0
        self.y = 0
        self.width = 800
        self.height = 600
        self.state = "normal"
        self.visible = false
        self.focused = false
        self.resizable = true
        self.decorated = true
        self.topmost = false
        self.opacity = 1.0
        self.min_width = 0
        self.min_height = 0
        self.max_width = 0
        self.max_height = 0
        if d != null:
            for k in d:
                if k in FIELDS:
                    _r.set_field(self, k, d[k])

    func to_dict():
        out := {}
        for f in FIELDS:
            out[f] = _r.get_field(self, f)
        return out

    func copy():
        return WindowProperties(self.to_dict())

    func set(name, value):
        if not (name in FIELDS):
            raise("ArgumentError", "propriété de fenêtre inconnue : " + name)
        _r.set_field(self, name, value)
        return self

    func get(name):
        if not (name in FIELDS):
            raise("ArgumentError", "propriété de fenêtre inconnue : " + name)
        return _r.get_field(self, name)

    # Applique à win ce qui diffère de son état actuel ; liste des propriétés envoyées.
    func apply(win):
        cur := read(win)
        changes := diff(cur, self)
        sent := []
        if "title" in changes:
            win.set_title(self.title)
            append(sent, "title")
        if "state" in changes and self.state != "normal":
            win.set_state(self.state)
            append(sent, "state")
        elif "state" in changes:
            win.restore()
            append(sent, "state")
        if self.state == "normal":
            if "x" in changes or "y" in changes:
                win.move(self.x, self.y)
                append(sent, "position")
            if "width" in changes or "height" in changes:
                win.set_size(self.width, self.height)
                append(sent, "size")
        if "resizable" in changes:
            win.set_resizable(self.resizable)
            append(sent, "resizable")
        if "decorated" in changes:
            win.set_decorated(self.decorated)
            append(sent, "decorated")
        if "topmost" in changes:
            win.set_topmost(self.topmost)
            append(sent, "topmost")
        if "opacity" in changes:
            if self.opacity < 0 or self.opacity > 1:
                raise("ArgumentError", "opacité 0..1 attendue")
            win.set_opacity(self.opacity)
            append(sent, "opacity")
        if "min_width" in changes or "min_height" in changes:
            win.set_min_size(self.min_width, self.min_height)
            append(sent, "min_size")
        if "max_width" in changes or "max_height" in changes:
            win.set_max_size(self.max_width, self.max_height)
            append(sent, "max_size")
        if "visible" in changes:
            if self.visible:
                win.show()
            else:
                win.hide()
            append(sent, "visible")
        return sent

    func __str__():
        return "WindowProperties(" + self.title + ", " + str(self.width) + "x" + str(self.height) + " @ " + str(self.x) + "," + str(self.y) + ", " + self.state + ")"

func read(win):
    i := win.info()
    p := WindowProperties()
    for f in FIELDS:
        if f in i:
            _r.set_field(p, f, i[f])
    return p

func from_dict(d):
    return WindowProperties(d)

# {propriété: [avant, après]} des propriétés qui diffèrent.
func diff(a, b):
    out := {}
    for f in FIELDS:
        x := _r.get_field(a, f)
        y := _r.get_field(b, f)
        if not (x == y):
            out[f] = [x, y]
    return out

class PropertyBag:
    func init():
        self.values = {}
        self.listeners = []

    func set(key, value):
        old := null
        if key in self.values:
            old = self.values[key]
        self.values[key] = value
        if not (old == value):
            for l in self.listeners:
                l(key, old, value)
        return self

    func get(key, default=null):
        if key in self.values:
            return self.values[key]
        return default

    func has(key):
        return key in self.values

    func remove(key):
        if key in self.values:
            old := self.values[key]
            del self.values[key]
            for l in self.listeners:
                l(key, old, null)
            return true
        return false

    func keys():
        return [k for k in self.values]

    func on_change(fn):
        append(self.listeners, fn)
        return self
