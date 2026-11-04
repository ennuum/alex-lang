# ALEX UI V0.8 — Gradients
from core use type

func linear(x1, y1, x2, y2, start_color, end_color, opacity=1.0):
    return {"kind":"linear", "x1":x1, "y1":y1, "x2":x2, "y2":y2, "start":start_color, "end":end_color, "opacity":opacity}

func radial(cx, cy, radius, inner_color, outer_color, opacity=1.0):
    return {"kind":"radial", "cx":cx, "cy":cy, "radius":radius, "inner":inner_color, "outer":outer_color, "opacity":opacity}
