# ALEX UI V0.8 — Render facade
# Backend-neutral rendering commands. Canvas owns the native surface.
use _native_ui as _ui_native

func begin(canvas):
    return _ui_native.canvas_begin(canvas["handle"])

func end(canvas):
    return _ui_native.canvas_end(canvas["handle"])

func clear(canvas, color):
    return _ui_native.canvas_clear(canvas["handle"], color["r"], color["g"], color["b"], color["a"])

func transform(canvas, matrix):
    return _ui_native.canvas_set_transform(canvas["handle"], matrix["m11"], matrix["m12"], matrix["m21"], matrix["m22"], matrix["dx"], matrix["dy"])

func opacity(canvas, value):
    return _ui_native.canvas_set_opacity(canvas["handle"], value)
