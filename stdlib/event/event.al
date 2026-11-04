# ALEX STANDARD LIBRARY — event
#
# Le système d'événements : un Event (type, données, horodatage, source, propagation) et les modules qui les
# font circuler.
#
# | Module               | Rôle                                                                             |
# |----------------------|----------------------------------------------------------------------------------|
# | event                | Event : la valeur qui circule (ici)                                              |
# | event.event_emitter  | EventEmitter : on / once / off / emit (comme Node.js), écouteurs async, wait_for  |
# | event.event_dispatcher | EventTarget (capture / cible / bouillonnement, comme le DOM), Dispatcher (bus)  |
# | event.event_queue    | EventQueue (priorités, fusion), ThreadEventQueue (entre fils)                    |
# | event.timer          | Timer, Interval, debounce, throttle                                              |
# | event.watcher        | FileWatcher (fichiers et dossiers : inotify ou scrutation), ValueWatcher         |
# | event.event_loop     | EventLoop : file d'événements + minuteurs + descripteurs + signaux, en une boucle |
#
#   use event
#   e := event.Event("click", {"x": 10, "y": 20})
#   print(e.type, e.data["x"], e.timestamp)
#   e.stop_propagation()
#
# Un événement est une valeur ordinaire : n'importe quel objet peut le transporter. Pour le faire passer d'un
# fil à l'autre, to_dict() / from_dict() (seules des valeurs copiables traversent).

from core use type
from collections use contains_key
use asyncio
use os as _os

_next_id := [1]

class Event:
    func init(event_type, data=null, source=null):
        if type(event_type) != "str" or event_type == "":
            raise("TypeError", "Event : type (str non vide) attendu")
        self.type = event_type
        self.data = data
        self.source = source
        self.target = null            # renseigné par event_dispatcher
        self.current_target = null
        self.phase = "none"           # none | capture | target | bubble
        self.timestamp = _os.time()
        self.id = _next_id[0]
        _next_id[0] += 1
        self.propagation_stopped = false
        self.immediate_stopped = false
        self.default_prevented = false

    # Plus aucun autre nœud ne reçoit l'événement (les écouteurs du nœud courant finissent).
    func stop_propagation():
        self.propagation_stopped = true

    # Plus aucun écouteur, même sur le nœud courant.
    func stop_immediate_propagation():
        self.propagation_stopped = true
        self.immediate_stopped = true

    # Demande à l'émetteur de ne pas exécuter l'action par défaut (dispatch renvoie alors false).
    func prevent_default():
        self.default_prevented = true

    # Champ de data (dict), ou fallback.
    func get(key, fallback=null):
        if type(self.data) == "dict" and contains_key(self.data, key):
            return self.data[key]
        return fallback

    func to_dict():
        return {"type": self.type, "data": self.data, "timestamp": self.timestamp, "id": self.id}

    func to_string():
        return "Event(" + self.type + ", " + str(self.data) + ")"

func create(event_type, data=null, source=null):
    return Event(event_type, data, source)

func is_event(x):
    return isinstance(x, Event)

# Event à partir d'un dict (to_dict), par exemple reçu d'un autre fil.
func from_dict(d):
    e := Event(d["type"], d["data"])
    if contains_key(d, "timestamp"):
        e.timestamp = d["timestamp"]
    return e

# Event à partir d'un Event, d'un dict {"type", "data"} ou d'un nom de type.
func coerce(x, data=null):
    if isinstance(x, Event):
        return x
    if type(x) == "str":
        return Event(x, data)
    if type(x) == "dict" and contains_key(x, "type"):
        return from_dict(_complete(x))
    raise("TypeError", "event : Event, type (str) ou dict {\"type\", \"data\"} attendu")

func _complete(d):
    if not contains_key(d, "data"):
        d["data"] = null
    return d
