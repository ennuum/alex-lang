# ALEX STANDARD LIBRARY — multimedia.video.compositor
#
# Composition d'images vidéo en couches : fond, calques (image, position, opacité, ordre, visibilité),
# incrustation d'image (picture-in-picture), mélange alpha « over », rendu en rgb ou rgba.
#
#   use multimedia.video.compositor as comp
#   c := comp.Compositor(320, 180, [0, 0, 0])
#   fond := c.add("film", image_film)
#   pip := c.add("webcam", image_webcam, 230, 120, 0.8, 10)   # x, y, opacité, ordre
#   c.update("webcam", nouvelle_image)
#   img := c.render()                                           # Image rgb 320x180
#   c.pip("webcam", "bas-droite", 0.25, 8)                       # place un calque en vignette
#
# Erreurs : FormatError (calque inconnu, opacité hors 0..1).

from core use len, to_int
from collections use append, keys
use algorithm.sort as _sort
use multimedia.core.errors as merr
use multimedia.image.image as mi
use multimedia.image.convert as cv
use multimedia.image.resize as rs

class Layer:
    func init(name, image, x=0, y=0, opacity=1.0, z=0):
        self.name = name
        self.image = image
        self.x = x
        self.y = y
        self.opacity = opacity
        self.z = z
        self.visible = true
        self.size = null

class Compositor:
    func init(width, height, background=null, mode="rgb"):
        if width <= 0 or height <= 0:
            merr.fail(merr.FORMAT, "taille de composition invalide")
        self.width = width
        self.height = height
        self.background = background if background != null else [0, 0, 0]
        self.mode = mode
        self.layers = {}
        self._seq = 0

    func add(name, image, x=0, y=0, opacity=1.0, z=null):
        if opacity < 0 or opacity > 1:
            merr.fail(merr.FORMAT, "opacité hors de 0..1")
        if z == null:
            z = self._seq
        self._seq += 1
        l := Layer(name, image, x, y, opacity, z)
        self.layers[name] = l
        return l

    func layer(name):
        if not (name in self.layers):
            merr.fail(merr.FORMAT, "calque inconnu : " + str(name))
        return self.layers[name]

    func update(name, image):
        self.layer(name).image = image

    func move(name, x, y):
        l := self.layer(name)
        l.x = x
        l.y = y

    func set_opacity(name, opacity):
        if opacity < 0 or opacity > 1:
            merr.fail(merr.FORMAT, "opacité hors de 0..1")
        self.layer(name).opacity = opacity

    func show(name, visible=true):
        self.layer(name).visible = visible

    func remove(name):
        self.layer(name)
        out := {}
        for k in keys(self.layers):
            if k != name:
                out[k] = self.layers[k]
        self.layers = out

    # Vignette : calque réduit à `scale` de la largeur de sortie, placé dans un coin avec une marge.
    func pip(name, corner="bas-droite", scale=0.25, margin=8):
        l := self.layer(name)
        w := to_int(self.width * scale)
        s := rs.fit_size(l.image.width, l.image.height, w, self.height, true)
        l.size = s
        l.x = margin if corner == "haut-gauche" or corner == "bas-gauche" else self.width - s[0] - margin
        l.y = margin if corner == "haut-gauche" or corner == "haut-droite" else self.height - s[1] - margin

    func render():
        bg := self.background
        if len(bg) < 3:
            bg = [bg[0], bg[0], bg[0]]
        out := mi.new(self.width, self.height, "rgb", [bg[0], bg[1], bg[2]])
        order := _sort.sorted([self.layers[k] for k in keys(self.layers)], (l) => l.z)
        for l in order:
            if not l.visible or l.opacity == 0:
                continue
            img := l.image
            if l.size != null and (img.width != l.size[0] or img.height != l.size[1]):
                img = rs.resize(img, l.size[0], l.size[1])
            src := cv.to_mode(img, "rgba") if img.mode != "rgba" else img
            if l.opacity < 1.0:
                px := [p for p in src.pixels]
                for i in 0..src.width * src.height:
                    px[4 * i + 3] = to_int(px[4 * i + 3] * l.opacity + 0.5)
                src = mi.Image(src.width, src.height, "rgba", px)
            out.paste(src, l.x, l.y)
        if self.mode == "rgba":
            return cv.to_mode(out, "rgba")
        return out
