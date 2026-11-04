# ALEX STANDARD LIBRARY — multimedia.video.scaler
#
# Mise à l'échelle des images vidéo vers une taille de sortie fixe, avec gestion des proportions :
#   « stretch »   étire (proportions perdues) ;
#   « fit »       tient dans le cadre, bandes de couleur autour (letterbox / pillarbox) ;
#   « fill »      remplit le cadre, recadre au centre.
# Méthode : « auto » (moyenne pour réduire, bilinéaire pour agrandir), « nearest », « bilinear », « box ».
#
#   use multimedia.video.scaler as vs
#   s := vs.Scaler(320, 180, "fit", [0, 0, 0])
#   petit := s.apply(image_vidéo)              # VideoFrame ou Image
#   print(s.geometry(1920, 1080))              # {"x": 0, "y": 0, "w": 320, "h": 180}

from core use len, type
use multimedia.core.errors as merr
use multimedia.image.image as mi
use multimedia.image.resize as rs
use multimedia.video.frame as vfr

const MODES := ["stretch", "fit", "fill"]

class Scaler:
    func init(width, height, mode="fit", background=null, method="auto"):
        if not (mode in MODES):
            merr.fail(merr.FORMAT, "mode de mise à l'échelle inconnu : " + str(mode))
        if width <= 0 or height <= 0:
            merr.fail(merr.FORMAT, "taille de sortie invalide")
        self.width = width
        self.height = height
        self.mode = mode
        self.background = background if background != null else [0, 0, 0]
        self.method = method

    # Rectangle occupé par l'image dans la sortie.
    func geometry(sw, sh):
        if self.mode == "stretch" or self.mode == "fill":
            return {"x": 0, "y": 0, "w": self.width, "h": self.height}
        s := rs.fit_size(sw, sh, self.width, self.height, true)
        return {"x": (self.width - s[0]) // 2, "y": (self.height - s[1]) // 2, "w": s[0], "h": s[1]}

    func _image(img):
        if img.width == self.width and img.height == self.height:
            return img.copy()
        if self.mode == "stretch":
            return rs.resize(img, self.width, self.height, self.method)
        if self.mode == "fill":
            return rs.cover(img, self.width, self.height)
        g := self.geometry(img.width, img.height)
        inner := rs.resize(img, g["w"], g["h"], self.method)
        bg := self.background
        if img.mode == "rgba" and len(bg) == 3:
            bg = bg + [255]
        if img.mode == "gray":
            bg = [bg[0]]
        out := mi.new(self.width, self.height, img.mode, bg)
        if img.mode == "rgba":
            # copie directe (pas de mélange) : le contenu remplace le fond
            for y in 0..inner.height:
                for x in 0..inner.width:
                    out.set(g["x"] + x, g["y"] + y, inner.get(x, y))
            return out
        return out.paste(inner, g["x"], g["y"])

    func apply(frame):
        if vfr.is_frame(frame):
            return frame.with_image(self._image(frame.image))
        return self._image(frame)
