# ALEX UI V0.9 — Widget theme
from core use type
use ui.paint as paint
use ui.canvas as canvas

func modern():
    return {
        "font":"Segoe UI", "font_size":14.0,
        "text": {"r":235,"g":238,"b":245,"a":255},
        "muted": {"r":150,"g":158,"b":172,"a":255},
        "surface": {"r":30,"g":34,"b":42,"a":255},
        "surface_hover": {"r":40,"g":45,"b":56,"a":255},
        "surface_pressed": {"r":24,"g":28,"b":35,"a":255},
        "border": {"r":65,"g":72,"b":86,"a":255},
        "primary": {"r":255,"g":107,"b":0,"a":255},
        "primary_hover": {"r":255,"g":126,"b":32,"a":255},
        "danger": {"r":220,"g":72,"b":72,"a":255},
        "background": {"r":18,"g":20,"b":25,"a":255},
        "selection": {"r":255,"g":107,"b":0,"a":90},
        "scroll_track": {"r":255,"g":255,"b":255,"a":14},
        "scroll_thumb": {"r":255,"g":255,"b":255,"a":70},
        "scroll_thumb_hover": {"r":255,"g":255,"b":255,"a":120},
        "drop_ok": {"r":60,"g":200,"b":120,"a":255},
        "radius":10.0, "control_height":40.0
    }
