# ALEX STANDARD LIBRARY — event.event_emitter
#
# EventEmitter : des écouteurs nommés par type d'événement, appelés quand on émet ce type (comme Node.js).
#
#   use event.event_emitter as ee
#   bus := ee.EventEmitter()
#   off := bus.on("message", (texte) => print("reçu", texte))
#   bus.once("pret", () => print("prêt !"))
#   bus.on("*", (type, args) => journal(type))        # joker : tous les types (type, liste des arguments)
#   bus.emit("message", "bonjour")                     # renvoie le nombre d'écouteurs appelés
#   off()                                              # retire l'écouteur
#   v := await bus.wait_for("reponse", 2.0)            # futur du prochain événement « reponse » (premier argument)
#   await bus.emit_async("sauvegarde", doc)            # attend aussi les écouteurs async
#
# Un écouteur reçoit autant d'arguments qu'il en déclare (les autres sont ignorés, les manquants valent null).
# Ordre : priorité décroissante (on(type, fn, priorité)), puis ordre d'inscription. Une exception levée par un
# écouteur est remise aux écouteurs de "error" (fn(type, message, type_d_evenement)) s'il y en a, sinon relancée
# par emit (comme Node.js).
#
# Erreurs : TypeError (écouteur non fonction), ArgumentError (trop d'arguments), TimeoutError (wait_for).

from core use len, type, arity
from collections use append, contains_key, keys
use asyncio

# Appelle fn avec autant d'arguments qu'elle en accepte : les arguments en trop sont ignorés, ceux qui manquent
# valent null (un écouteur peut donc ignorer les données de l'événement).
func _call(fn, args):
    ar := arity(fn)
    n := len(args)
    if n > ar[1]:
        n = ar[1]
    if n < ar[0]:
        args = [args[k] if k < len(args) else null for k in 0..ar[0]]
        n = ar[0]
    if n == 0:
        return fn()
    if n == 1:
        return fn(args[0])
    if n == 2:
        return fn(args[0], args[1])
    if n == 3:
        return fn(args[0], args[1], args[2])
    if n == 4:
        return fn(args[0], args[1], args[2], args[3])
    if n == 5:
        return fn(args[0], args[1], args[2], args[3], args[4])
    raise("ArgumentError", "EventEmitter.emit : 5 arguments au plus")

class EventEmitter:
    func init(max_listeners=100):
        self._listeners = {}      # type -> liste de [id, priorité, fonction, une_fois]
        self._next = 1
        self.max_listeners = max_listeners
        self.emitted = 0

    func _insert(event_type, entry):
        if not contains_key(self._listeners, event_type):
            self._listeners[event_type] = []
        lst := self._listeners[event_type]
        if self.max_listeners > 0 and len(lst) >= self.max_listeners:
            raise("ArgumentError", "EventEmitter : plus de " + str(self.max_listeners) + " écouteurs pour '" + event_type + "' (fuite ?)")
        i := 0
        while i < len(lst) and lst[i][1] >= entry[1]:
            i += 1
        out := []
        for k in 0..i:
            append(out, lst[k])
        append(out, entry)
        for k in i..len(lst):
            append(out, lst[k])
        self._listeners[event_type] = out

    # Ajoute un écouteur ; renvoie une fonction qui le retire.
    func on(event_type, fn, priority=0):
        if type(fn) != "function":
            raise("TypeError", "EventEmitter.on : fonction attendue")
        id := self._next
        self._next += 1
        self._insert(event_type, [id, priority, fn, false])
        return () => self._remove_id(event_type, id)

    func once(event_type, fn, priority=0):
        if type(fn) != "function":
            raise("TypeError", "EventEmitter.once : fonction attendue")
        id := self._next
        self._next += 1
        self._insert(event_type, [id, priority, fn, true])
        return () => self._remove_id(event_type, id)

    func _remove_id(event_type, id):
        if not contains_key(self._listeners, event_type):
            return false
        before := len(self._listeners[event_type])
        self._listeners[event_type] = [e for e in self._listeners[event_type] if e[0] != id]
        return len(self._listeners[event_type]) < before

    # Retire l'écouteur fn (toutes ses inscriptions pour ce type).
    func off(event_type, fn):
        if not contains_key(self._listeners, event_type):
            return false
        before := len(self._listeners[event_type])
        self._listeners[event_type] = [e for e in self._listeners[event_type] if e[2] != fn]
        return len(self._listeners[event_type]) < before

    # Retire tous les écouteurs d'un type (ou de tous les types si null).
    func remove_all(event_type=null):
        if event_type == null:
            self._listeners = {}
        elif contains_key(self._listeners, event_type):
            self._listeners[event_type] = []

    func listener_count(event_type):
        if not contains_key(self._listeners, event_type):
            return 0
        return len(self._listeners[event_type])

    func event_types():
        return [k for k in keys(self._listeners) if len(self._listeners[k]) > 0]

    func _take(event_type):
        if not contains_key(self._listeners, event_type):
            return []
        lst := self._listeners[event_type]
        if len(lst) == 0:
            return []
        self._listeners[event_type] = [e for e in lst if not e[3]]
        return lst

    func _fail(event_type, err_type, message):
        if event_type != "error" and self.listener_count("error") > 0:
            self.emit("error", err_type, message, event_type)
            return
        raise(err_type, message)

    # Appelle les écouteurs de event_type avec les arguments ; renvoie leur nombre. Les futurs renvoyés par des
    # écouteurs async ne sont pas attendus (voir emit_async).
    func emit(event_type, a=null, b=null, c=null, d=null):
        return self.emit_args(event_type, _args(a, b, c, d))

    func emit_args(event_type, args):
        self.emitted += 1
        called := 0
        for e in self._take(event_type):
            called += 1
            try:
                _call(e[2], args)
            catch ex:
                self._fail(event_type, ex.type, ex.message)
        if event_type != "*":
            for e in self._take("*"):
                try:
                    _call(e[2], [event_type, args])
                catch ex:
                    self._fail(event_type, ex.type, ex.message)
        return called

    # Comme emit, puis attend les futurs des écouteurs async (dans l'ordre) ; futur du nombre d'écouteurs.
    func emit_async(event_type, a=null, b=null, c=null, d=null):
        return _emit_async(self, event_type, _args(a, b, c, d))

    # Futur du premier argument du prochain event_type ; TimeoutError après timeout secondes.
    func wait_for(event_type, timeout=null):
        p := asyncio.future()
        self.once(event_type, (x) => asyncio.resolve(p, x))
        if timeout != null:
            return asyncio.timeout(p, timeout)
        return p

# Arguments passés à emit : seulement ceux fournis jusqu'au dernier non nul (null explicite au milieu gardé).
func _args(a, b, c, d):
    all := [a, b, c, d]
    n := 4
    while n > 0 and all[n - 1] == null:
        n -= 1
    return [all[k] for k in 0..n]

async func _emit_async(em, event_type, args):
    em.emitted += 1
    called := 0
    for e in em._take(event_type):
        called += 1
        try:
            r := _call(e[2], args)
            if asyncio.is_future(r):
                await r
        catch ex:
            em._fail(event_type, ex.type, ex.message)
    return called

func emitter(max_listeners=100):
    return EventEmitter(max_listeners)
