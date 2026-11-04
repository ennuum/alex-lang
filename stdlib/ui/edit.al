# ALEX UI V1.3 — Cœur d'édition de texte (sélection, caret, historique) — données pures
#
# Un éditeur est un dict : {"text","caret","anchor","multiline","pref_x","undo","redo","last_op"}.
# La sélection est [min(caret, anchor), max(caret, anchor)). Aucune dépendance au rendu : le widget
# (ui.widgets.text_input) et le contrôleur (ui.interact) appellent ces fonctions puis redessinent.
# Les indices sont en caractères. Les fonctions d'édition retournent true si le TEXTE a changé.
from core use type, len, clamp, is_function
use collections
use string
use ui.text as _text

const MAX_UNDO := 100

func create(text="", multiline=false):
    return {"kind": "editor", "text": text, "caret": len(text), "anchor": len(text), "multiline": multiline,
            "pref_x": null, "undo": [], "redo": [], "last_op": ""}

func _clamp(ed):
    n := len(ed["text"])
    ed["caret"] = clamp(ed["caret"], 0, n)
    ed["anchor"] = clamp(ed["anchor"], 0, n)

func selection(ed):
    a := ed["anchor"]
    c := ed["caret"]
    if a < c:
        return [a, c]
    return [c, a]

func has_selection(ed):
    return ed["anchor"] != ed["caret"]

func selected_text(ed):
    s := selection(ed)
    return _text.sub(ed["text"], s[0], s[1])

func _snapshot(ed):
    return {"text": ed["text"], "caret": ed["caret"], "anchor": ed["anchor"]}

func _push_undo(ed, op):
    # Les frappes consécutives sont fusionnées en une seule étape d'annulation.
    if op == "type" and ed["last_op"] == "type":
        return null
    collections.append(ed["undo"], _snapshot(ed))
    if len(ed["undo"]) > MAX_UNDO:
        collections.pop(ed["undo"], 0)
    ed["redo"] = []
    ed["last_op"] = op
    return null

func _normalize(ed, s):
    out := string.replace(string.replace(s, "\r\n", "\n"), "\r", "\n")
    if not ed["multiline"]:
        out = string.replace(out, "\n", " ")
    return out

# Remplace la sélection (ou insère au curseur) par s.
func insert(ed, s, op=null):
    s = _normalize(ed, s)
    if s == "" and not has_selection(ed):
        return false
    if op == null:
        op = "paste"
        if len(s) == 1:
            op = "type"
    _push_undo(ed, op)
    sel := selection(ed)
    ed["text"] = _text.sub(ed["text"], 0, sel[0]) + s + _text.sub(ed["text"], sel[1], len(ed["text"]))
    ed["caret"] = sel[0] + len(s)
    ed["anchor"] = ed["caret"]
    ed["pref_x"] = null
    return true

func _delete_range(ed, a, b, op):
    if b <= a:
        return false
    _push_undo(ed, op)
    ed["text"] = _text.sub(ed["text"], 0, a) + _text.sub(ed["text"], b, len(ed["text"]))
    ed["caret"] = a
    ed["anchor"] = a
    ed["pref_x"] = null
    return true

func delete_selection(ed):
    sel := selection(ed)
    return _delete_range(ed, sel[0], sel[1], "delete")

func backspace(ed, word=false):
    if has_selection(ed):
        return delete_selection(ed)
    c := ed["caret"]
    if c == 0:
        return false
    a := c - 1
    if word:
        a = _text.word_start(ed["text"], c)
    return _delete_range(ed, a, c, "delete")

func delete(ed, word=false):
    if has_selection(ed):
        return delete_selection(ed)
    c := ed["caret"]
    n := len(ed["text"])
    if c >= n:
        return false
    b := c + 1
    if word:
        b = _text.word_end(ed["text"], c)
    return _delete_range(ed, c, b, "delete")

func set_caret(ed, i, extend=false):
    ed["caret"] = clamp(i, 0, len(ed["text"]))
    if not extend:
        ed["anchor"] = ed["caret"]
    ed["pref_x"] = null
    ed["last_op"] = ""
    return null

func select_all(ed):
    ed["anchor"] = 0
    ed["caret"] = len(ed["text"])
    ed["last_op"] = ""
    return null

func select_word(ed, i):
    b := _text.word_bounds(ed["text"], i)
    ed["anchor"] = b[0]
    ed["caret"] = b[1]
    ed["last_op"] = ""
    return null

# Sélectionne la ligne entière (triple-clic) ; sur un champ mono-ligne : tout le texte.
func select_line(ed, i):
    if not ed["multiline"]:
        return select_all(ed)
    a := _text.line_start(ed["text"], i)
    b := _text.line_end(ed["text"], i)
    ed["anchor"] = a
    ed["caret"] = b
    ed["last_op"] = ""
    return null

# Déplacements : left right word_left word_right home end doc_start doc_end up down.
# extend=true : étend la sélection (Maj). size = taille de police (pour up/down, colonne en pixels).
func move(ed, kind, extend=false, size=14.0):
    text := ed["text"]
    n := len(text)
    c := ed["caret"]
    sel := selection(ed)
    target := c
    keep_pref := false
    if kind == "left":
        if has_selection(ed) and not extend:
            target = sel[0]
        else:
            target = c - 1
    elif kind == "right":
        if has_selection(ed) and not extend:
            target = sel[1]
        else:
            target = c + 1
    elif kind == "word_left":
        target = _text.word_start(text, c)
    elif kind == "word_right":
        target = _text.word_end(text, c)
    elif kind == "home":
        target = 0
        if ed["multiline"]:
            target = _text.line_start(text, c)
    elif kind == "end":
        target = n
        if ed["multiline"]:
            target = _text.line_end(text, c)
    elif kind == "doc_start":
        target = 0
    elif kind == "doc_end":
        target = n
    elif kind == "up" or kind == "down":
        if not ed["multiline"]:
            if kind == "up":
                target = 0
            else:
                target = n
        else:
            ls := _text.line_start(text, c)
            if ed["pref_x"] == null:
                ed["pref_x"] = _text.prefix_width(_text.sub(text, ls, n), c - ls, size)
            line := _text.line_of(text, c)
            nl := line - 1
            if kind == "down":
                nl = line + 1
            total := _text.line_count(text)
            if nl < 0:
                target = 0
            elif nl >= total:
                target = n
            else:
                st := _text.index_of_line(text, nl)
                en := _text.line_end(text, st)
                target = st + _text.index_at(_text.sub(text, st, en), ed["pref_x"], size)
            keep_pref = true
    else:
        raise("ArgumentError", "ui.edit.move() : déplacement inconnu '" + str(kind) + "'")
    ed["caret"] = clamp(target, 0, n)
    if not extend:
        ed["anchor"] = ed["caret"]
    if not keep_pref:
        ed["pref_x"] = null
    ed["last_op"] = ""
    return null

func undo(ed):
    if len(ed["undo"]) == 0:
        return false
    collections.append(ed["redo"], _snapshot(ed))
    snap := collections.pop(ed["undo"])
    ed["text"] = snap["text"]
    ed["caret"] = snap["caret"]
    ed["anchor"] = snap["anchor"]
    ed["last_op"] = ""
    ed["pref_x"] = null
    return true

func redo(ed):
    if len(ed["redo"]) == 0:
        return false
    collections.append(ed["undo"], _snapshot(ed))
    snap := collections.pop(ed["redo"])
    ed["text"] = snap["text"]
    ed["caret"] = snap["caret"]
    ed["anchor"] = snap["anchor"]
    ed["last_op"] = ""
    ed["pref_x"] = null
    return true

# Remplace tout le texte (affectation programmatique) : curseur à la fin, historique réinitialisé.
func set_text(ed, text):
    ed["text"] = text
    ed["caret"] = len(text)
    ed["anchor"] = len(text)
    ed["undo"] = []
    ed["redo"] = []
    ed["last_op"] = ""
    ed["pref_x"] = null
    return null
