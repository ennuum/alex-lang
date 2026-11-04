# ALEX STANDARD LIBRARY — input.input
#
# Point d'entrée du paquet input : la couche d'entrées unifiée au-dessus des fenêtres (window) et des
# périphériques du noyau (hardware, evdev).
#
# | Module               | Rôle                                                                              |
# |----------------------|-----------------------------------------------------------------------------------|
# | input.input_event    | InputEvent unifié, tables de codes evdev, conversions                             |
# | input.input_device   | inventaire des périphériques (genre déduit des capacités), lecture                |
# | input.input_manager  | sources multiples, état, actions et axes virtuels                                 |
# | input.touch          | contact unique (TouchPoint, TouchTracker, tap)                                    |
# | input.multitouch     | protocole multi-contact B (emplacements, suivi, pincement, rotation)              |
# | input.gamepad        | manettes (boutons, sticks avec zone morte, gâchettes, croix)                      |
# | input.gesture        | gestes tactiles (tap, double tap, appui long, swipe, pan, pinch, rotate)          |
# | input.input_errors   | erreurs et diagnostic d'accès à /dev/input                                        |
#
#   use input.input as inp
#   print(inp.summary())                  # {"keyboard": 1, "mouse": 1, "touchpad": 1}
#   m := inp.manager()
#   print(inp.available("gamepad"))
#
# Erreurs : voir input.input_errors.

from core use len
use input.input_device as _dev
use input.input_manager as _mgr
use input.input_errors as _err

func devices():
    return _dev.devices()

func summary():
    return _dev.summary()

func available(kind=null):
    if kind == null:
        return len(_dev.devices()) > 0
    return len(_dev.of_kind(kind)) > 0

func manager():
    return _mgr.InputManager()

func diagnose():
    return _err.diagnose()

func open(kind):
    return _dev.first(kind).open()
