# ALEX STANDARD LIBRARY — event.event_subscription
#
# Abonnements : un objet Subscription pour chaque écouteur inscrit sur un EventEmitter, un Dispatcher ou un
# EventTarget (ou toute source qui rend une fonction de désinscription) — pause / reprise, compteur d'appels,
# filtre, fin automatique après n appels ou à une échéance, désinscription garantie (with) — et des groupes
# d'abonnements que l'on ferme d'un coup (un composant qui se démonte, une connexion qui se ferme).
#
#   use event.event_subscription as es
#   s := es.subscribe(bus, "message", (texte) => print(texte))     # EventEmitter, Dispatcher ou EventTarget
#   s.pause() ; bus.emit("message", "ignoré") ; s.resume()
#   print(s.calls, s.active())
#   s.cancel()
#   g := es.SubscriptionGroup()
#   g.add(es.subscribe(bus, "a", fa))
#   g.add(es.subscribe(bus, "b", fb, 3))          # 3 appels au plus, puis désinscription automatique
#   g.cancel_all()
#   with es.subscribe(bus, "x", fx) as tmp:       # désinscrit à la sortie du bloc
#       ...
#
# Erreurs : EventError (source sans méthode d'inscription connue, abonnement annulé), TypeError.

from core use len, type
from collections use append
use os as _os
use _native_reflect as _r

class Subscription:
    func init(event_type, handler, max_calls=null, expires_in=null, filter=null):
        if type(handler) != "function":
            raise("TypeError", "Subscription : fonction attendue")
        self.event_type = event_type
        self.handler = handler
        self.max_calls = max_calls
        self.expires = null
        if expires_in != null:
            self.expires = _os.monotonic_time() + expires_in
        self.filter = filter
        self.calls = 0
        self.skipped = 0
        self.paused = false
        self.cancelled = false
        self._off = null

    # Fonction à inscrire auprès de la source (appelle handler selon l'état de l'abonnement).
    func listener():
        return (*args) => self._deliver(args)

    func _deliver(args):
        if self.cancelled:
            return null
        if self.expires != null and _os.monotonic_time() >= self.expires:
            self.cancel()
            return null
        if self.paused:
            self.skipped += 1
            return null
        if self.filter != null:
            first := null
            if len(args) > 0:
                first = args[0]
            f := self.filter
            if not f(first):
                self.skipped += 1
                return null
        self.calls += 1
        h := self.handler
        r := h(*args)
        if self.max_calls != null and self.calls >= self.max_calls:
            self.cancel()
        return r

    func attach(off_fn):
        self._off = off_fn
        return self

    func pause():
        self.paused = true
        return self

    func resume():
        if self.cancelled:
            raise("EventError", "Subscription.resume : abonnement annulé")
        self.paused = false
        return self

    func active():
        return not self.cancelled and not self.paused

    func cancel():
        if not self.cancelled:
            self.cancelled = true
            if self._off != null:
                off := self._off
                off()

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.cancel()

    func __str__():
        state := "active"
        if self.cancelled:
            state = "annulée"
        elif self.paused:
            state = "en pause"
        return "Subscription(" + str(self.event_type) + ", " + state + ", " + str(self.calls) + " appel(s))"

# Inscrit handler sur source ; Subscription.
func subscribe(source, event_type, handler, max_calls=null, expires_in=null, filter=null, priority=0):
    sub := Subscription(event_type, handler, max_calls, expires_in, filter)
    l := sub.listener()
    off := null
    if _r.method(source, "add_listener") != null:
        off = _target_off(source, event_type, l, priority)
    elif _r.method(source, "subscribe") != null:
        off = source.subscribe(event_type, l, priority)
    elif _r.method(source, "on") != null:
        off = source.on(event_type, l, priority)
    else:
        raise("EventError", "subscribe : la source n'a ni on, ni subscribe, ni add_listener")
    if type(off) != "function":
        off = () => _noop()
    return sub.attach(off)

func _target_off(target, event_type, l, priority):
    target.add_listener(event_type, l, false, priority)
    return () => target.remove_listener(event_type, l)

func _noop():
    return null

func once(source, event_type, handler):
    return subscribe(source, event_type, handler, 1)

class SubscriptionGroup:
    func init(name="groupe"):
        self.name = name
        self.subs = []

    func add(sub):
        append(self.subs, sub)
        return sub

    func subscribe(source, event_type, handler, max_calls=null):
        return self.add(subscribe(source, event_type, handler, max_calls))

    func pause_all():
        for s in self.subs:
            if not s.cancelled:
                s.pause()

    func resume_all():
        for s in self.subs:
            if not s.cancelled:
                s.resume()

    func cancel_all():
        n := 0
        for s in self.subs:
            if not s.cancelled:
                s.cancel()
                n += 1
        self.subs = []
        return n

    func active_count():
        return len([s for s in self.subs if s.active()])

    func size():
        return len(self.subs)

    func prune():
        self.subs = [s for s in self.subs if not s.cancelled]
        return self

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.cancel_all()
