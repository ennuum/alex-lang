# ALEX STANDARD LIBRARY — web.css.positioning
#
# Positionnement : déclarations position / inset / z-index (dicts prêts pour StyleRule), motifs courants
# (centrage absolu, recouvrement, en-tête collant, masquage accessible) et échelle de z-index nommée.
#
#   use web.css.positioning as pos
#   pos.absolute(0, null, null, 0)              # {"position": "absolute", "top": "0", "left": "0"}
#   pos.sticky("0", 10)                         # {"position": "sticky", "top": "0", "z-index": "10"}
#   pos.center_absolute()                       # top/left 50 % + translate(-50%, -50%)
#   pos.cover()                                 # {"position": "absolute", "inset": "0"}
#   pos.visually_hidden()                       # masqué à l'écran, lu par les lecteurs d'écran
#   z := pos.ZScale(["base", "menu", "collant", "modale", "toast"], 10)
#   z.get("modale")                             # 40
#   z.variables()                               # {"--z-base": "0", "--z-menu": "10", ...}
#
# Erreurs : CssValueError (position inconnue, couche de z-index inconnue).

from core use len, type
from collections use append
use string as _s
use web.css.css_errors as _err

const POSITIONS := ["static", "relative", "absolute", "fixed", "sticky"]

func _len(v):
    if type(v) == "int" or type(v) == "float":
        return str(v) + "px" if v != 0 else "0"
    return str(v)

# Déclarations position + côtés (null : côté omis) + z-index éventuel.
func position(kind, top=null, right=null, bottom=null, left=null, z=null):
    if not (kind in POSITIONS):
        _err.value_error("positioning.position", "position inconnue « " + str(kind) + " »")
    d := {"position": kind}
    if top != null:
        d["top"] = _len(top)
    if right != null:
        d["right"] = _len(right)
    if bottom != null:
        d["bottom"] = _len(bottom)
    if left != null:
        d["left"] = _len(left)
    if z != null:
        d["z-index"] = str(z)
    return d

func relative(z=null):
    return position("relative", null, null, null, null, z)

func absolute(top=null, right=null, bottom=null, left=null, z=null):
    return position("absolute", top, right, bottom, left, z)

func fixed(top=null, right=null, bottom=null, left=null, z=null):
    return position("fixed", top, right, bottom, left, z)

func sticky(top="0", z=null):
    return position("sticky", top, null, null, null, z)

func static():
    return {"position": "static"}

# Raccourci inset (1 à 4 valeurs).
func inset(a, b=null, c=null, d=null):
    parts := [_len(a)]
    for x in [b, c, d]:
        if x != null:
            append(parts, _len(x))
    return {"inset": _s.join(" ", parts)}

# Recouvre entièrement le parent positionné.
func cover(fixed_to_viewport=false):
    return {"position": "fixed" if fixed_to_viewport else "absolute", "inset": "0"}

func center_absolute():
    return {"position": "absolute", "top": "50%", "left": "50%", "transform": "translate(-50%, -50%)"}

func center_horizontal_absolute():
    return {"position": "absolute", "left": "50%", "transform": "translateX(-50%)"}

# Coin : "top-left", "top-right", "bottom-left", "bottom-right" ; offset : marge au bord.
func corner(which, offset="0", fixed_to_viewport=false):
    kind := "fixed" if fixed_to_viewport else "absolute"
    o := _len(offset)
    if which == "top-left":
        return position(kind, o, null, null, o)
    if which == "top-right":
        return position(kind, o, o)
    if which == "bottom-left":
        return position(kind, null, null, o, o)
    if which == "bottom-right":
        return position(kind, null, o, o)
    _err.value_error("positioning.corner", "coin inconnu « " + str(which) + " »")

# Masquage accessible (« sr-only ») : invisible mais lu par les technologies d'assistance.
func visually_hidden():
    return {"position": "absolute", "width": "1px", "height": "1px", "padding": "0", "margin": "-1px", "overflow": "hidden", "clip": "rect(0, 0, 0, 0)", "white-space": "nowrap", "border": "0"}

# Annule visually_hidden (élément focalisé : lien d'évitement).
func visually_hidden_focusable():
    return {"position": "static", "width": "auto", "height": "auto", "margin": "0", "overflow": "visible", "clip": "auto", "white-space": "normal"}

func z_index(n):
    return {"z-index": str(n)}

# Nouveau contexte d'empilement sans effet visuel.
func isolate():
    return {"isolation": "isolate"}

func aspect_ratio(w, h=null):
    return {"aspect-ratio": str(w) if h == null else str(w) + " / " + str(h)}

# Échelle nommée de z-index (ordre croissant), pour éviter les « 9999 » dispersés.
class ZScale:
    func init(layers, step=10, start=0):
        self.layers = layers
        self.step = step
        self.start = start

    func get(name):
        i := 0
        while i < len(self.layers):
            if self.layers[i] == name:
                return self.start + i * self.step
            i += 1
        _err.value_error("ZScale.get", "couche inconnue « " + str(name) + " »")

    func above(name, by=1):
        return self.get(name) + by

    func variables(prefix="--z-"):
        out := {}
        for n in self.layers:
            out[prefix + n] = str(self.get(n))
        return out

    func declaration(name):
        return {"z-index": str(self.get(name))}

func default_scale():
    return ZScale(["base", "raised", "dropdown", "sticky", "overlay", "modal", "popover", "toast", "tooltip"], 10)
