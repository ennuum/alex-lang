# ALEX UI smoke test
use ui

func on_event(event):
    if ui.is_button_event(event):
        print("button:", ui.event_widget(event))

if ui.available():
    window := ui.window("ALEX UI", 720, 420)
    title := ui.label(window, "ALEX LANGUAGE — UI")
    input_box := ui.input_field(window, "", 20, 60, 300, 32)
    button := ui.button(window, "Valider", 20, 110, 120, 36)
    ui.loop(window, on_event)
else:
    print("UI backend indisponible:", ui.backend())
