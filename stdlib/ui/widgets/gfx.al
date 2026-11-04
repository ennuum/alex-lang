# ALEX UI V1.3 — Pile de clips et de décalages de dessin (défilement imbriqué)
#
# Le canvas natif n'a qu'UN clip et UNE transformation. Pour que des zones défilantes s'imbriquent
# (scroll_view dans scroll_view, text_area dans scroll_view...), on garde ici la pile : chaque entrée est
# un rectangle de clip en coordonnées ÉCRAN et un décalage de contenu ; apply() ré-applique l'intersection de
# tous les clips puis la translation cumulée. Les widgets dessinent toujours dans LEUR espace de coordonnées
# (celui de leur parent, avant défilement) ; device_x/device_y convertissent vers l'écran.
from core use len
use collections
use ui.canvas as canvas

const _G := {"ox": 0.0, "oy": 0.0, "clips": []}

# À appeler au début de chaque image (remet la pile à zéro).
func begin(c):
    _G["ox"] = 0.0
    _G["oy"] = 0.0
    _G["clips"] = []
    canvas.reset_clip(c)
    canvas.reset_transform(c)

func offset_x():
    return _G["ox"]

func offset_y():
    return _G["oy"]

func depth():
    return len(_G["clips"])

func _apply(c):
    canvas.reset_transform(c)
    canvas.reset_clip(c)
    for r in _G["clips"]:
        canvas.clip_rect(c, r[0], r[1], r[2], r[3])
    canvas.transform(c, {"m11": 1.0, "m12": 0.0, "m21": 0.0, "m22": 1.0, "dx": 0.0 - _G["ox"], "dy": 0.0 - _G["oy"]})

# Clippe sur (x, y, w, h) (espace courant du widget) et décale le contenu de (-sx, -sy).
func push(c, x, y, w, h, sx=0.0, sy=0.0):
    collections.append(_G["clips"], [x - _G["ox"], y - _G["oy"], w, h, sx, sy])
    _G["ox"] = _G["ox"] + sx
    _G["oy"] = _G["oy"] + sy
    _apply(c)

func pop(c):
    n := len(_G["clips"])
    if n == 0:
        return null
    r := _G["clips"][n - 1]
    _G["ox"] = _G["ox"] - r[4]
    _G["oy"] = _G["oy"] - r[5]
    kept := []
    i := 0
    while i < n - 1:
        collections.append(kept, _G["clips"][i])
        i += 1
    _G["clips"] = kept
    _apply(c)
    return null
