use ui

app := ui.window("ALEX UI V0.4", 900, 600)
theme := ui.theme("modern-dark")

button := ui.button(app, "Action", 40, 40, 160, 42)
label := ui.label(app, "ALEX — Modern UI", 40, 100, 300, 36)
input_widget := ui.input_field(app, "Votre nom", 40, 150, 280, 36)

ui.apply_style(button, theme["button"])
ui.apply_style(label, theme["surface"])
ui.apply_style(input_widget, theme["input"])

ui.show(app)
ui.run(app)
