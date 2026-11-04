use ui
use ui.icon as icon

window := ui.window("ALEX UI V0.7 — Professional Icons", 760, 420, true)

home_button := ui.button(window, "Accueil", 40, 40, 180, 44)
settings_button := ui.button(window, "Paramètres", 40, 100, 180, 44)
search_button := ui.button(window, "Rechercher", 40, 160, 180, 44)

icon.set(home_button, icon.home(20), 20, "left")
icon.set(settings_button, icon.settings(20), 20, "left")
icon.set(search_button, icon.search(20), 20, "left")

label := ui.label(window, "Icônes natives + fichiers image + DPI", 40, 240, 420, 32)

app_icon := icon.star(32)
icon.set_window(window, app_icon, 32)

func on_event(event):
    return null

ui.loop(window, on_event)
