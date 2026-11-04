# ALEX STANDARD LIBRARY — web.dom.input_event
#
# InputEvent (beforeinput, input) : données saisies, type de saisie (insertText, deleteContentBackward…),
# composition ; CompositionEvent (méthodes de saisie) ; et application d'une saisie à une valeur de champ avec
# sélection (comme le navigateur le ferait pour un <input> ou un <textarea>).
#
#   use web.dom.input_event as ie
#   e := ie.InputEvent("input", {"data": "a", "input_type": ie.INSERT_TEXT})
#   e.data, e.input_type                               # a insertText
#   ie.apply("Bonjour", 7, 7, ie.INSERT_TEXT, " !")    # ("Bonjour !", 9)
#   ie.apply("abc", 3, 3, ie.DELETE_BACKWARD)          # ("ab", 2)
#   ie.apply("un deux", 7, 7, ie.DELETE_WORD_BACKWARD) # ("un ", 3)
#
# Erreurs : DomError (type de saisie inconnu dans apply).

from core use len, type
use string as _s
use web.dom.dom_errors as _err
from web.dom.event use UIEvent

const INSERT_TEXT := "insertText"
const INSERT_LINE_BREAK := "insertLineBreak"
const INSERT_PARAGRAPH := "insertParagraph"
const INSERT_FROM_PASTE := "insertFromPaste"
const INSERT_FROM_DROP := "insertFromDrop"
const INSERT_REPLACEMENT := "insertReplacementText"
const INSERT_COMPOSITION := "insertCompositionText"
const DELETE_BACKWARD := "deleteContentBackward"
const DELETE_FORWARD := "deleteContentForward"
const DELETE_WORD_BACKWARD := "deleteWordBackward"
const DELETE_WORD_FORWARD := "deleteWordForward"
const DELETE_BY_CUT := "deleteByCut"
const HISTORY_UNDO := "historyUndo"
const HISTORY_REDO := "historyRedo"

func _opt(o, name, fallback):
    if type(o) == "dict" and name in o:
        return o[name]
    return fallback

class InputEvent extends UIEvent:
    func init(event_type, options=null):
        o := options if options != null else {}
        is_before := event_type == "beforeinput"
        super.init(event_type, {"bubbles": _opt(o, "bubbles", true), "cancelable": _opt(o, "cancelable", is_before), "composed": true, "view": _opt(o, "view", null)})
        self.data = _opt(o, "data", null)
        self.input_type = _opt(o, "input_type", "")
        self.is_composing = _opt(o, "is_composing", false)
        self.data_transfer = _opt(o, "data_transfer", null)
        self.target_ranges = _opt(o, "target_ranges", [])

    func get_target_ranges():
        return self.target_ranges

class CompositionEvent extends UIEvent:
    func init(event_type, options=null):
        o := options if options != null else {}
        super.init(event_type, {"bubbles": true, "cancelable": event_type == "compositionstart", "composed": true})
        self.data = _opt(o, "data", "")
        self.locale = _opt(o, "locale", "")

func _is_space(c):
    return c == ' ' or c == '\t' or c == '\n'

# Applique une saisie à value avec la sélection [start, end[ : renvoie (nouvelle valeur, position du curseur).
func apply(value, start, end, input_type, data=null):
    v := str(value)
    a := start if start <= end else end
    b := end if end >= start else start
    if a < 0:
        a = 0
    if b > len(v):
        b = len(v)
    t := input_type
    if t == INSERT_TEXT or t == INSERT_FROM_PASTE or t == INSERT_FROM_DROP or t == INSERT_REPLACEMENT or t == INSERT_COMPOSITION:
        d := str(data) if data != null else ""
        return (v[0:a] + d + v[b:len(v)], a + len(d))
    if t == INSERT_LINE_BREAK or t == INSERT_PARAGRAPH:
        return (v[0:a] + "\n" + v[b:len(v)], a + 1)
    if t == DELETE_BY_CUT:
        return (v[0:a] + v[b:len(v)], a)
    if t == DELETE_BACKWARD:
        if a != b:
            return (v[0:a] + v[b:len(v)], a)
        if a == 0:
            return (v, 0)
        return (v[0:a - 1] + v[a:len(v)], a - 1)
    if t == DELETE_FORWARD:
        if a != b:
            return (v[0:a] + v[b:len(v)], a)
        return (v[0:a] + v[a + 1:len(v)], a)
    if t == DELETE_WORD_BACKWARD:
        if a != b:
            return (v[0:a] + v[b:len(v)], a)
        i := a
        while i > 0 and _is_space(v[i - 1]):
            i -= 1
        while i > 0 and not _is_space(v[i - 1]):
            i -= 1
        return (v[0:i] + v[a:len(v)], i)
    if t == DELETE_WORD_FORWARD:
        if a != b:
            return (v[0:a] + v[b:len(v)], a)
        i := a
        while i < len(v) and _is_space(v[i]):
            i += 1
        while i < len(v) and not _is_space(v[i]):
            i += 1
        return (v[0:a] + v[i:len(v)], a)
    _err.dom_error("input_event.apply", "type de saisie non pris en charge « " + str(input_type) + " »")

func input_of(data=null, input_type="insertText", event_type="input"):
    return InputEvent(event_type, {"data": data, "input_type": input_type})
