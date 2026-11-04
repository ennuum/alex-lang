# ALEX UI V0.3 — Layout smoke test
use ui

window := ui.window("ALEX UI V0.3 — Layouts", 800, 500)
label := ui.label(window, "Nom")
button := ui.button(window, "Valider")
window_input := ui.input_field(window)

children := [
    ui.layout_item(label, 220, 30),
    ui.layout_item(window_input, 300, 32, 1),
    ui.layout_item(button, 180, 36)
]

ui.vbox(children, 760, 460, 10, 20, ui.alignment_center())
ui.show(window)
ui.run(window)
