# ALEX STANDARD LIBRARY — window.window_errors
#
# Erreurs du système de fenêtres et diagnostics : distinguer « pas d'affichage » (serveur graphique absent,
# session sans écran) de « fenêtre fermée » ou d'un réglage invalide, et proposer la marche à suivre.
#   WindowError        erreur générale de fenêtre
#   DisplayError       aucun affichage disponible (le backend headless reste possible)
#   WindowClosedError  opération sur une fenêtre fermée
#   GeometryError      dimensions / position / géométrie invalides
#
#   use window.window_errors as we
#   print(we.display_available(), we.backend())   # false "none" sur un serveur ; "headless" avec ALEX_UI_BACKEND
#   we.require_display()                           # DisplayError claire (avec la solution) si pas d'écran
#   try:
#       w.set_title("x")
#   catch e:
#       print(we.classify(e))                       # "closed" | "display" | "argument" | "other"
#
# Erreurs : DisplayError, WindowClosedError, GeometryError, WindowError.

from core use len, type
use string as _s
use os as _os
use _native_ui as _ui

const WINDOW := "WindowError"
const DISPLAY := "DisplayError"
const CLOSED := "WindowClosedError"
const GEOMETRY := "GeometryError"

func backend():
    try:
        return _ui.backend()
    catch e:
        return "none"

func display_available():
    try:
        return _ui.available()
    catch e:
        return false

func require_display():
    if not display_available():
        hint := "définir ALEX_UI_BACKEND=headless pour un écran virtuel (tests, serveurs)"
        if _os.get_env("DISPLAY", null) == null and _os.get_env("WAYLAND_DISPLAY", null) == null:
            hint = "aucune variable DISPLAY / WAYLAND_DISPLAY : session sans écran ; " + hint
        raise(DISPLAY, "aucun affichage disponible (backend " + backend() + ") — " + hint)
    return true

# "closed" | "display" | "argument" | "geometry" | "other"
func classify(e):
    m := _s.lower(e.message)
    if e.type == CLOSED or _s.contains(m, "fenêtre fermée"):
        return "closed"
    if e.type == DISPLAY or (e.type == "IoError" and (_s.contains(m, "affichage") or _s.contains(m, "display"))):
        return "display"
    if e.type == GEOMETRY:
        return "geometry"
    if e.type == "ArgumentError" or e.type == "TypeError":
        return "argument"
    return "other"

func closed(win_title=null):
    t := ""
    if win_title != null:
        t = " « " + win_title + " »"
    raise(CLOSED, "fenêtre" + t + " fermée")

func geometry(message):
    raise(GEOMETRY, message)

func explain(e):
    k := classify(e)
    if k == "closed":
        return "La fenêtre a été fermée : vérifier is_open() avant d'agir."
    if k == "display":
        return "Pas d'écran : utiliser ALEX_UI_BACKEND=headless, ou lancer depuis une session graphique."
    if k == "argument":
        return "Réglage invalide : " + e.message
    if k == "geometry":
        return "Géométrie invalide : " + e.message
    return e.type + " : " + e.message
