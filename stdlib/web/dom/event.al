# ALEX STANDARD LIBRARY — web.dom.event
#
# Événements DOM : Event (phases capture / cible / bouillonnement, annulation, arrêt de propagation, chemin
# composé, horodatage), UIEvent (vue, détail) et FocusEvent (focus, blur, focusin, focusout). Les
# événements spécialisés sont dans keyboard_event, mouse_event, pointer_event, input_event, custom_event.
#
#   use web.dom.event as ev
#   e := ev.Event("enregistrer", true, true)       # type, bouillonne, annulable
#   cible.dispatch_event(e)                        # false si un écouteur a appelé prevent_default()
#   e.default_prevented, e.event_phase, e.target, e.current_target
#   ev.Event("x", {"bubbles": true})               # options en dict (comme EventInit)
#
# Erreurs : DomError (type vide), InvalidStateError (réinitialisation pendant la distribution).

from core use len, type
from collections use append
use time as _time
use web.dom.dom_errors as _err

const NONE := 0
const CAPTURING_PHASE := 1
const AT_TARGET := 2
const BUBBLING_PHASE := 3

_origin := [_time.monotonic()]

# Millisecondes depuis le chargement du module (performance.now() simplifié).
func now():
    return (_time.monotonic() - _origin[0]) * 1000.0

func _opt(options, name, fallback):
    if type(options) == "dict" and name in options:
        return options[name]
    return fallback

class Event:
    # bubbles : bool ou dict d'options (bubbles, cancelable, composed).
    func init(event_type, bubbles=false, cancelable=false, composed=false):
        if type(event_type) != "str" or event_type == "":
            _err.dom_error("Event", "type d'événement vide")
        self.type = event_type
        if type(bubbles) == "dict":
            opts := bubbles
            self.bubbles = _opt(opts, "bubbles", false)
            self.cancelable = _opt(opts, "cancelable", false)
            self.composed = _opt(opts, "composed", false)
        else:
            self.bubbles = bubbles
            self.cancelable = cancelable
            self.composed = composed
        self.target = null
        self.current_target = null
        self.related_target = null
        self.event_phase = NONE
        self.default_prevented = false
        self.is_trusted = false
        self.time_stamp = now()
        self.dispatching = false
        self.stop_flag = false
        self.stop_immediate_flag = false
        self.in_passive_listener = false
        self.path = []                 # chemin de distribution (cible d'abord)

    func prevent_default():
        if self.cancelable and not self.in_passive_listener:
            self.default_prevented = true

    func stop_propagation():
        self.stop_flag = true

    func stop_immediate_propagation():
        self.stop_flag = true
        self.stop_immediate_flag = true

    # Valeur héritée de l'API : vrai si l'événement n'a pas été annulé.
    func return_value():
        return not self.default_prevented

    func composed_path():
        if not self.dispatching:
            return []
        out := []
        for p in self.path:
            append(out, p)
        return out

    func init_event(event_type, bubbles=false, cancelable=false):
        if self.dispatching:
            _err.invalid_state("Event.init_event", "événement en cours de distribution")
        self.type = event_type
        self.bubbles = bubbles
        self.cancelable = cancelable
        self.default_prevented = false
        self.stop_flag = false
        self.stop_immediate_flag = false
        return self

    func __str__():
        return "<" + self.type + ">"

class UIEvent extends Event:
    func init(event_type, options=null):
        o := options if options != null else {}
        super.init(event_type, _opt(o, "bubbles", false), _opt(o, "cancelable", false), _opt(o, "composed", false))
        self.view = _opt(o, "view", null)
        self.detail = _opt(o, "detail", 0)

class FocusEvent extends UIEvent:
    func init(event_type, options=null):
        super.init(event_type, options)
        self.related_target = _opt(options if options != null else {}, "related_target", null)

func event(event_type, options=null):
    return Event(event_type, options if options != null else {})

# Événement « bouillonnant et annulable » (le cas le plus courant pour un événement applicatif).
func bubbling(event_type):
    return Event(event_type, true, true)

func focus_event(event_type, related=null):
    bubbles := event_type == "focusin" or event_type == "focusout"
    return FocusEvent(event_type, {"bubbles": bubbles, "composed": true, "related_target": related})
