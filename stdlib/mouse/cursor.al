# ALEX STANDARD LIBRARY — mouse.cursor
#
# Forme du curseur de la souris au-dessus d'une fenêtre : flèche, texte, main, sablier, déplacement...
#
#   use mouse.cursor as cursor
#   cursor.set(fenetre, cursor.WAIT)
#   cursor.with_cursor(fenetre, cursor.WAIT, calcul_long)     # rétablit le curseur précédent ensuite
#   print(cursor.get(fenetre), cursor.names())
#
# fenetre : un window.Window (ou tout objet ayant .handle), ou un handle de fenêtre ui.
#
# Erreurs : ArgumentError (nom inconnu), IoError (fenêtre fermée, pas d'affichage).

from core use type
use _native_ui as _ui

const ARROW := "arrow"
const TEXT := "text"
const POINTER := "pointer"
const GRAB := "grab"
const GRABBING := "grabbing"
const MOVE := "move"
const RESIZE_H := "resize_h"
const RESIZE_V := "resize_v"
const WAIT := "wait"
const NOT_ALLOWED := "not_allowed"
const CROSSHAIR := "crosshair"

_ALL := ["arrow", "text", "pointer", "grab", "grabbing", "move", "resize_h", "resize_v", "wait", "not_allowed", "crosshair"]

func names():
    return [n for n in _ALL]

func is_valid(name):
    for n in _ALL:
        if n == name:
            return true
    return false

func _handle(window):
    if type(window) == "int":
        return window
    return window.handle

func set(window, name):
    if not is_valid(name):
        raise("ArgumentError", "cursor.set : curseur inconnu '" + str(name) + "' (" + str(_ALL) + ")")
    _ui.window_set_cursor(_handle(window), name)

func get(window):
    return _ui.window_get_cursor(_handle(window))

func reset(window):
    set(window, ARROW)

# fn() avec le curseur name, puis rétablit le précédent (même en cas d'erreur).
func with_cursor(window, name, fn):
    previous := get(window)
    set(window, name)
    try:
        return fn()
    finally:
        set(window, previous)

# Curseur conseillé pour le bord d'une zone redimensionnable : "left"/"right" -> resize_h, "top"/"bottom" -> resize_v.
func for_edge(edge):
    if edge == "left" or edge == "right":
        return RESIZE_H
    if edge == "top" or edge == "bottom":
        return RESIZE_V
    return ARROW
