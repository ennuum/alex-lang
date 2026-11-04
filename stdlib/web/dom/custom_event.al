# ALEX STANDARD LIBRARY — web.dom.custom_event
#
# CustomEvent : événement applicatif portant une donnée quelconque (detail).
#
#   use web.dom.custom_event as ce
#   e := ce.CustomEvent("panier:ajout", {"detail": {"id": 42}, "bubbles": true})
#   e.detail["id"]                                 # 42
#   ce.custom("panier:ajout", {"id": 42})          # bouillonnant et annulable
#
# Erreurs : DomError (type vide).

from core use len, type
from web.dom.event use Event

class CustomEvent extends Event:
    func init(event_type, options=null):
        o := options if options != null else {}
        super.init(event_type, o)
        self.detail = o["detail"] if type(o) == "dict" and "detail" in o else null

    func init_custom_event(event_type, bubbles=false, cancelable=false, detail=null):
        self.init_event(event_type, bubbles, cancelable)
        self.detail = detail
        return self

func custom(event_type, detail=null, bubbles=true, cancelable=true):
    return CustomEvent(event_type, {"detail": detail, "bubbles": bubbles, "cancelable": cancelable})
