use ui
use ui.canvas as canvas
use ui.paint as paint
use ui.gradient as gradient
use ui.path as path
use ui.shadow as shadow

func rgba(r,g,b,a):
    return {"r":r,"g":g,"b":b,"a":a}

window := ui.window("ALEX Canvas V0.8", 960, 640, true)
c := canvas.create(window)

bg := rgba(18, 18, 24, 255)
white := rgba(255, 255, 255, 255)
muted := rgba(190, 190, 200, 255)
primary_color := rgba(255, 107, 0, 255)
card_color := rgba(42, 42, 52, 255)

canvas.begin(c)
canvas.clear(c, bg)

primary := paint.fill(primary_color)
card := paint.fill(card_color)
outline := paint.stroke(rgba(255,255,255,90), 1.0)

canvas.shadow_round_rect(c, 40, 40, 880, 560, 24, shadow.create(rgba(0,0,0,255), 18, 0, 8, 0.30), card)
canvas.round_rect(c, 70, 90, 280, 140, 20, primary)
canvas.circle(c, 420, 160, 60, primary)
canvas.linear_gradient_rect(c, 540, 90, 330, 140, gradient.linear(540,90,870,230,rgba(255,107,0,255),rgba(255,170,80,255),1.0))
canvas.line(c, 70, 270, 880, 270, outline)
canvas.text(c, "ALEX UI V0.8", 80, 330, paint.fill(white), "Segoe UI", 32.0)
canvas.text(c, "Canvas • 2D Rendering • Direct2D", 80, 375, paint.fill(muted), "Segoe UI", 18.0)

p := path.create()
path.move_to(p, 80, 460)
path.line_to(p, 220, 410)
path.cubic_to(p, 300, 380, 360, 520, 500, 450)
path.close(p)
canvas.path(c, p, primary)
path.destroy(p)

canvas.end(c)
ui.show(window)
ui.run(window)
canvas.destroy(c)
ui.close(window)
