# ALEX STANDARD LIBRARY — event.event_dispatcher
#
# Distribution d'événements (event.Event) :
#   - EventTarget : des nœuds en arbre (interface, documents, scènes) ; un événement envoyé à un nœud traverse
#     la phase de CAPTURE (de la racine vers la cible), la CIBLE, puis le BOUILLONNEMENT (de la cible vers la
#     racine), comme dans le DOM. stop_propagation / prevent_default sont respectés.
#   - Dispatcher : un bus central par type d'événement, avec priorités, filtres et types hiérarchiques
#     (« fenetre.clavier.appui » atteint aussi les abonnés de « fenetre.clavier » et « fenetre »).
#
#   use event
#   use event.event_dispatcher as ed
#   racine := ed.EventTarget("fenêtre")
#   bouton := ed.EventTarget("ok", racine)
#   racine.add_listener("click", (e) => print("capture", e.target.name), true)
#   bouton.add_listener("click", (e) => print("bouton"))
#   racine.add_listener("click", (e) => print("bouillonnement"))
#   bouton.dispatch(event.Event("click", {"x": 3}))         # capture, bouton, bouillonnement
#
#   bus := ed.Dispatcher()
#   bus.subscribe("commande.creee", traiter, 10, (e) => e.get("montant") > 100)
#   bus.publish("commande.creee", {"montant": 250})
#
# Erreurs : TypeError ; une exception d'un écouteur traverse dispatch / publish (Dispatcher.on_error pour la
# capturer et continuer).

from core use len, type, arity
from collections use append, contains_key, keys
use string as _s
use event as _ev

func _call1(fn, e):
    ar := arity(fn)
    if ar[1] == 0:
        return fn()
    return fn(e)

func _insert_sorted(lst, entry):
    i := 0
    while i < len(lst) and lst[i][1] >= entry[1]:
        i += 1
    out := []
    for k in 0..i:
        append(out, lst[k])
    append(out, entry)
    for k in i..len(lst):
        append(out, lst[k])
    return out

class EventTarget:
    func init(name="", parent=null):
        self.name = name
        self.parent = null
        self.children = []
        self._listeners = {}   # type -> liste de [id, priorité, fonction, capture, une_fois]
        self._next = 1
        if parent != null:
            parent.append_child(self)

    func append_child(child):
        if child.parent != null:
            child.parent.remove_child(child)
        child.parent = self
        append(self.children, child)
        return child

    func remove_child(child):
        self.children = [c for c in self.children if c != child]
        child.parent = null

    # Chemin de la racine jusqu'à ce nœud (inclus).
    func path():
        out := []
        n := self
        depth := 0
        while n != null and depth < 10000:
            append(out, n)
            n = n.parent
            depth += 1
        return [out[len(out) - 1 - k] for k in 0..len(out)]

    # capture=true : appelé pendant la phase de capture (en descendant), sinon à la cible et en remontant.
    # Renvoie une fonction qui retire l'écouteur.
    func add_listener(event_type, fn, capture=false, priority=0, once=false):
        if type(fn) != "function":
            raise("TypeError", "EventTarget.add_listener : fonction attendue")
        id := self._next
        self._next += 1
        if not contains_key(self._listeners, event_type):
            self._listeners[event_type] = []
        self._listeners[event_type] = _insert_sorted(self._listeners[event_type], [id, priority, fn, capture, once])
        return () => self._remove(event_type, id)

    func _remove(event_type, id):
        if contains_key(self._listeners, event_type):
            self._listeners[event_type] = [e for e in self._listeners[event_type] if e[0] != id]

    func remove_listener(event_type, fn):
        if contains_key(self._listeners, event_type):
            self._listeners[event_type] = [e for e in self._listeners[event_type] if e[2] != fn]

    func listener_count(event_type):
        if not contains_key(self._listeners, event_type):
            return 0
        return len(self._listeners[event_type])

    func _invoke(e, capture_phase, target_phase):
        if not contains_key(self._listeners, e.type):
            return
        e.current_target = self
        for entry in self._listeners[e.type]:
            if e.immediate_stopped:
                return
            if not target_phase and entry[3] != capture_phase:
                continue
            if entry[4]:
                self._remove(e.type, entry[0])
            _call1(entry[2], e)

    # Envoie l'événement (event.Event, ou un type et des données) à ce nœud ; renvoie false si un écouteur a
    # appelé prevent_default.
    func dispatch(e, data=null):
        e = _ev.coerce(e, data)
        e.target = self
        chain := self.path()
        n := len(chain)
        e.phase = "capture"
        for k in 0..(n - 1):
            if e.propagation_stopped:
                break
            chain[k]._invoke(e, true, false)
        if not e.propagation_stopped:
            e.phase = "target"
            self._invoke(e, false, true)
        k := n - 2
        e.phase = "bubble"
        while k >= 0 and not e.propagation_stopped:
            chain[k]._invoke(e, false, false)
            k -= 1
        e.phase = "none"
        e.current_target = null
        return not e.default_prevented

    # Premier descendant (profondeur d'abord) de ce nom, ou null.
    func find(name):
        if self.name == name:
            return self
        for c in self.children:
            r := c.find(name)
            if r != null:
                return r
        return null

class Dispatcher:
    func init():
        self._subs = {}      # type -> [id, priorité, fonction, filtre]
        self._next = 1
        self._error_handler = null
        self.published = 0

    # handler(event) pour le type (et ses sous-types « type.xxx ») ; filter(event) -> bool facultatif.
    # Renvoie une fonction qui annule l'abonnement.
    func subscribe(event_type, handler, priority=0, filter=null):
        if type(handler) != "function":
            raise("TypeError", "Dispatcher.subscribe : fonction attendue")
        id := self._next
        self._next += 1
        if not contains_key(self._subs, event_type):
            self._subs[event_type] = []
        self._subs[event_type] = _insert_sorted(self._subs[event_type], [id, priority, handler, filter])
        return () => self._unsubscribe(event_type, id)

    func _unsubscribe(event_type, id):
        if contains_key(self._subs, event_type):
            self._subs[event_type] = [s for s in self._subs[event_type] if s[0] != id]

    # handler(type, message, event) appelé quand un abonné lève une exception (sinon elle est relancée).
    func on_error(handler):
        self._error_handler = handler

    func subscriber_count(event_type):
        if not contains_key(self._subs, event_type):
            return 0
        return len(self._subs[event_type])

    # Types concernés par event_type : lui-même puis ses préfixes (« a.b.c », « a.b », « a »), puis « * ».
    func _chain(event_type):
        out := [event_type]
        cur := event_type
        k := _last_dot(cur)
        while k > 0:
            cur = _s.substring(cur, 0, k)
            append(out, cur)
            k = _last_dot(cur)
        append(out, "*")
        return out

    # Publie ; renvoie le nombre d'abonnés appelés.
    func publish(e, data=null):
        e = _ev.coerce(e, data)
        self.published += 1
        called := 0
        for t in self._chain(e.type):
            if not contains_key(self._subs, t):
                continue
            for s in self._subs[t]:
                if e.immediate_stopped or e.propagation_stopped:
                    return called
                if s[3] != null:
                    flt := s[3]
                    if not flt(e):
                        continue
                called += 1
                try:
                    _call1(s[2], e)
                catch ex:
                    if self._error_handler == null:
                        raise(ex.type, ex.message)
                    h := self._error_handler
                    h(ex.type, ex.message, e)
        return called

func _last_dot(s):
    i := len(s) - 1
    while i >= 0:
        if s[i] == '.':
            return i
        i -= 1
    return -1

func target(name="", parent=null):
    return EventTarget(name, parent)

func dispatcher():
    return Dispatcher()
