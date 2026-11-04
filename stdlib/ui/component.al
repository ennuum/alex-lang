# ALEX STANDARD LIBRARY — ui.component
#
# Composants RÉUTILISABLES et à ÉTAT pour ui.view (affichés par gui.run ou tui.run) : une classe Component
# a des propriétés (props, données d'entrée), un état propre (state) et une méthode render() qui rend l'arbre
# ui.view. set_state() modifie l'état et la vue suivante en tient compte. Les composants enfants sont
# identifiés par une CLÉ : leur état survit d'un rendu à l'autre ; ceux qui disparaissent sont démontés.
# Cycle de vie : on_mount() (premier rendu), on_update(anciennes_props), on_unmount().
#
#   use ui.view as v
#   use ui.component as uc
#   from ui.component use Component
#   class Compteur extends Component:
#       func initial_state():
#           return {"n": self.prop("depart", 0)}
#       func render():
#           return v.row([v.text(self.prop("libelle", "") + str(self.state["n"])),
#                         v.button("+1", () => self.set_state({"n": self.state["n"] + 1}))])
#   class Appli extends Component:
#       func render():
#           return v.column([self.child("a", (p) => Compteur(p), {"libelle": "A : "}),
#                            self.child("b", (p) => Compteur(p), {"libelle": "B : ", "depart": 10})])
#   vue := uc.mount(Appli())          # fonction de vue pour gui.run(vue) / tui.run(vue)
#
# Les classes ne sont pas des valeurs en ALEX : child() reçoit une FABRIQUE (props) => instance.
# Erreurs : TypeError (render ne rend pas un nœud, fabrique invalide), ArgumentError.

from core use len, type
from collections use append
use ui.view.node as _n

_ids := [0]

class Component:
    func init(props=null):
        self.props = props
        if self.props == null:
            self.props = {}
        _ids[0] += 1
        self.component_id = _ids[0]
        self.state = self.initial_state()
        if self.state == null:
            self.state = {}
        self.mounted = false
        self.renders = 0
        self.dirty = true
        self._children = {}       # clé -> instance
        self._seen = {}           # clés vues pendant le rendu en cours
        self.parent = null

    # À redéfinir.
    func initial_state():
        return {}

    func render():
        raise("TypeError", "Component.render : à redéfinir (doit rendre un nœud ui.view)")

    func on_mount():
        return null

    func on_update(old_props):
        return null

    func on_unmount():
        return null

    # Faut-il recalculer avec ces nouvelles props ? (par défaut : oui)
    func should_update(new_props):
        return true

    func prop(name, default=null):
        if name in self.props:
            return self.props[name]
        return default

    func set_state(patch):
        for k in patch:
            self.state[k] = patch[k]
        self.dirty = true
        p := self.parent
        while p != null:
            p.dirty = true
            p = p.parent
        return self

    func set_props(new_props):
        old := self.props
        self.props = new_props
        self.dirty = true
        if self.mounted:
            self.on_update(old)
        return self

    # Composant enfant identifié par key ; fabrique(props) => instance (appelée au premier rendu seulement).
    func child(key, factory, props=null):
        p := props
        if p == null:
            p = {}
        c := null
        if key in self._children:
            c = self._children[key]
            if not _same_props(c.props, p) and c.should_update(p):
                c.set_props(p)
        else:
            if type(factory) != "function":
                raise("TypeError", "Component.child : fabrique (props) => composant attendue")
            c = factory(p)
            c.parent = self
            self._children[key] = c
        self._seen[key] = true
        return c.tree()

    func children():
        return [self._children[k] for k in self._children]

    # Arbre ui.view du composant (rend, monte, démonte les enfants disparus).
    func tree():
        self._seen = {}
        t := self.render()
        if type(t) == "str" or type(t) == "int" or type(t) == "float" or t == null:
            t = _n.coerce(t)
        if not _n.is_node(t):
            raise("TypeError", "Component.render doit rendre un nœud ui.view")
        self.renders += 1
        self.dirty = false
        gone := [k for k in self._children if not (k in self._seen)]
        for k in gone:
            _unmount(self._children[k])
            del self._children[k]
        if not self.mounted:
            self.mounted = true
            self.on_mount()
        return t

    func unmount():
        _unmount(self)

func _unmount(c):
    for k in c._children:
        _unmount(c._children[k])
    c._children = {}
    if c.mounted:
        c.mounted = false
        c.on_unmount()

func _same_props(a, b):
    if len(a) != len(b):
        return false
    for k in a:
        if not (k in b):
            return false
        x := a[k]
        y := b[k]
        if type(x) == "function" or type(y) == "function":
            continue
        if not (x == y):
            return false
    return true

# Fonction de vue pour gui.run / tui.run.
func mount(root):
    return () => root.tree()

# Composant à partir d'une simple fonction render(props, state, set_state).
class FunctionComponent extends Component:
    func init(fn, props=null, state=null):
        self.fn = fn
        self._initial = state
        super.init(props)

    func initial_state():
        if self._initial == null:
            return {}
        out := {}
        for k in self._initial:
            out[k] = self._initial[k]
        return out

    func render():
        f := self.fn
        return f(self.props, self.state, (patch) => self.set_state(patch))

func functional(fn, initial_state=null):
    return (props) => FunctionComponent(fn, props, initial_state)

# Mémoïsation : recalcule fn(arg) seulement quand arg change.
func memo(fn):
    cache := [null, null, false]
    return (arg) => _memo_call(cache, fn, arg)

func _memo_call(cache, fn, arg):
    if cache[2] and cache[0] == arg:
        return cache[1]
    cache[0] = arg
    cache[1] = fn(arg)
    cache[2] = true
    return cache[1]
