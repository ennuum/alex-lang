use ui

app := ui.window("ALEX UI — Animation V0.6", 900, 560)
box := ui.button(app, "ALEX")
ui.widget_set_position(box, 40, 80)

# Déplacement fluide avec easing.
ui.move(box, 40, 80, 650, 80, 1.0, "cubic_in_out", 60)

# Retour avec effet rebond.
ui.move(box, 650, 80, 40, 220, 1.0, "bounce_out", 60)

# Pulse professionnel.
ui.pulse(box, 120, 36, 180, 48, 0.16, 2, "ease_in_out", 60)

ui.show(app)
ui.run(app)
