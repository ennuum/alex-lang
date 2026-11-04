# ALEX STANDARD LIBRARY — web.css.backgrounds
#
# Arrière-plans : déclarations background-* (dicts prêts pour StyleRule), couches multiples, image de
# couverture avec voile, motifs en CSS pur (rayures, damier, points, grille) et images adaptées à la densité
# d'écran (image-set).
#
#   use web.css.backgrounds as bg
#   bg.background("#f5f5f5")                               # {"background-color": "#f5f5f5"}
#   bg.cover("img/hero.jpg", "rgb(0 0 0 / 40%)")           # image couvrante assombrie
#   bg.layers([bg.Layer("url(a.png)", "top left", "no-repeat"), bg.Layer("linear-gradient(#fff, #eee)")])
#   bg.stripes("#eee", "#fff", "10px", "45deg")            # repeating-linear-gradient(...)
#   bg.checkerboard("#ccc", "#fff", "16px")
#   bg.image_set({"1x": "logo.png", "2x": "logo@2x.png"})   # image-set(url("logo.png") 1x, url("logo@2x.png") 2x)
#
# Erreurs : CssValueError (taille, répétition ou attachement inconnus).

from core use len, type
from collections use append, keys
use string as _s
use web.css.css_errors as _err
use web.css.value as _value

const REPEATS := ["repeat", "no-repeat", "repeat-x", "repeat-y", "space", "round"]
const ATTACHMENTS := ["scroll", "fixed", "local"]
const BOXES := ["border-box", "padding-box", "content-box", "text"]

func url(path):
    t := str(path)
    if _s.starts_with(t, "url(") or _s.contains(t, "gradient(") or _s.starts_with(t, "image-set("):
        return t
    return "url(" + _value.quote(t) + ")"

# Déclarations background-* ; null : propriété omise.
func background(color=null, image=null, position=null, size=null, repeat=null, attachment=null, clip=null):
    d := {}
    if color != null:
        d["background-color"] = str(color)
    if image != null:
        d["background-image"] = url(image)
    if position != null:
        d["background-position"] = position
    if size != null:
        d["background-size"] = size
    if repeat != null:
        if not (repeat in REPEATS) and not _s.contains(repeat, " "):
            _err.value_error("backgrounds.background", "répétition inconnue « " + str(repeat) + " »")
        d["background-repeat"] = repeat
    if attachment != null:
        if not (attachment in ATTACHMENTS):
            _err.value_error("backgrounds.background", "attachement inconnu « " + str(attachment) + " »")
        d["background-attachment"] = attachment
    if clip != null:
        if not (clip in BOXES):
            _err.value_error("backgrounds.background", "boîte inconnue « " + str(clip) + " »")
        d["background-clip"] = clip
    return d

# Une couche d'arrière-plan (image et ses réglages).
class Layer:
    func init(image, position="center", repeat="no-repeat", size="auto", attachment=null, origin=null, clip=null):
        self.image = url(image)
        self.position = position
        self.repeat = repeat
        self.size = size
        self.attachment = attachment
        self.origin = origin
        self.clip = clip

    func to_css():
        parts := [self.image, self.position + ((" / " + self.size) if self.size != "auto" else ""), self.repeat]
        if self.attachment != null:
            append(parts, self.attachment)
        if self.origin != null:
            append(parts, self.origin)
        if self.clip != null:
            append(parts, self.clip)
        return _s.join(" ", parts)

# Raccourci background à plusieurs couches (la première au-dessus) ; color : couleur de fond finale.
func layers(items, color=null):
    parts := []
    i := 0
    while i < len(items):
        t := items[i].to_css() if isinstance(items[i], Layer) else str(items[i])
        if i == len(items) - 1 and color != null:
            t = t + " " + str(color)
        append(parts, t)
        i += 1
    if len(items) == 0 and color != null:
        append(parts, str(color))
    return {"background": _s.join(", ", parts)}

# Image couvrante ; overlay : couleur translucide superposée (null : aucune).
func cover(image, overlay=null, position="center"):
    img := url(image)
    if overlay != null:
        img = "linear-gradient(" + overlay + ", " + overlay + "), " + img
    return {"background-image": img, "background-size": "cover", "background-position": position, "background-repeat": "no-repeat"}

func contain(image, position="center"):
    return {"background-image": url(image), "background-size": "contain", "background-position": position, "background-repeat": "no-repeat"}

# Texte rempli par un dégradé.
func gradient_text(gradient):
    return {"background-image": gradient, "-webkit-background-clip": "text", "background-clip": "text", "color": "transparent"}

# ---------------------------------------------------------------- motifs

func stripes(color_a, color_b, width="10px", angle="45deg"):
    w := str(width)
    return {"background-image": "repeating-linear-gradient(" + str(angle) + ", " + color_a + " 0 " + w + ", " + color_b + " " + w + " calc(2 * " + w + "))"}

func checkerboard(color_a, color_b, size="20px"):
    s := str(size)
    return {"background-color": color_b, "background-image": "conic-gradient(" + color_a + " 25%, transparent 0 50%, " + color_a + " 0 75%, transparent 0)", "background-size": s + " " + s}

func dots(color, background_color="transparent", spacing="20px", radius="2px"):
    return {"background-color": background_color, "background-image": "radial-gradient(" + color + " " + str(radius) + ", transparent " + str(radius) + ")", "background-size": str(spacing) + " " + str(spacing)}

func grid_lines(color, spacing="24px", thickness="1px"):
    sp := str(spacing)
    t := str(thickness)
    return {"background-image": "linear-gradient(" + color + " " + t + ", transparent " + t + "), linear-gradient(90deg, " + color + " " + t + ", transparent " + t + ")", "background-size": sp + " " + sp}

# image-set() depuis un dict densité -> chemin (« 1x », « 2x ») ou type -> chemin (« image/avif »).
func image_set(sources):
    parts := []
    for k in keys(sources):
        key := str(k)
        if _s.contains(key, "/"):
            append(parts, url(sources[k]) + " type(" + _value.quote(key) + ")")
        else:
            append(parts, url(sources[k]) + " " + key)
    return "image-set(" + _s.join(", ", parts) + ")"
