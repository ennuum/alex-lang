# ALEX STANDARD LIBRARY — office.pptx_images
# Images des diapositives (p:pic) : insertion à une position et une taille données (proportions conservées si une
# seule dimension est fournie), recadrage, texte de remplacement, lecture des images existantes.
#
#   use office.pptx_images as pi
#   pic := pi.Picture("photo.jpg", "2cm", "3cm", "12cm")        # largeur 12 cm, hauteur proportionnelle
#   pic.description = "Vue aérienne du site"
#   slide.add(pic)
#
# Picture(image, x=0, y=0, cx=null, cy=null, description="", name=null)
#   image : chemin, octets ou core.Image   champs : image x y cx cy description name crop ([g, h, d, b] en %)
#   link (URL au clic)   move(x, y)   resize(cx=null, cy=null)   bounds()   center_in(largeur, hauteur)
#   to_xml(ctx, ident) (ctx.image_rel(image) -> rId)
# Fonctions : parse_picture(nœud_p:pic, rels, images) -> Picture ou null (images(rid) -> octets)
#   fit(image, largeur_max, hauteur_max) -> [cx, cy] (plus grande taille tenant dans la boîte)
# Formats : png jpeg gif bmp tiff (et svg, affiché par PowerPoint 2016+ seulement).
# Erreurs : FormatError.

from core use len, type, to_int, to_float
from collections use append, contains_key
use string
use office.utils as u
use office.xml as x
use office.core as core
use office.pptx_shapes as ps

class Picture:
    func init(image, x0=0, y0=0, cx=null, cy=null, description="", name=null):
        self.image = core.load_image(image)
        sz := self.image.size_emu(cx, cy)
        self.x = u.length(x0)
        self.y = u.length(y0)
        self.cx = sz[0]
        self.cy = sz[1]
        self.description = description
        self.name = name
        self.crop = null
        self.link = null

    func move(x0, y0):
        self.x = u.length(x0)
        self.y = u.length(y0)
        return self

    func resize(cx=null, cy=null):
        sz := self.image.size_emu(cx, cy)
        self.cx = sz[0]
        self.cy = sz[1]
        return self

    func bounds():
        return [self.x, self.y, self.cx, self.cy]

    func center_in(width, height):
        self.x = (u.length(width) - self.cx) // 2
        self.y = (u.length(height) - self.cy) // 2
        return self

    func to_xml(ctx, ident):
        rid := ctx.image_rel(self.image)
        nm := self.name if self.name != null else "Image " + str(ident)
        cnv_kids := []
        if self.link != null:
            append(cnv_kids, x.el("a:hlinkClick", {"r:id": ctx.link_rel(self.link)}))
        nv := x.el("p:nvPicPr", null, [x.el("p:cNvPr", {"id": str(ident), "name": nm, "descr": self.description if self.description != "" else null}, cnv_kids), x.el("p:cNvPicPr", null, [x.el("a:picLocks", {"noChangeAspect": "1"})]), x.el("p:nvPr")])
        fill := [x.el("a:blip", {"r:embed": rid})]
        if self.crop != null:
            c := self.crop
            append(fill, x.el("a:srcRect", {"l": str(to_int(c[0] * 1000)), "t": str(to_int(c[1] * 1000)), "r": str(to_int(c[2] * 1000)), "b": str(to_int(c[3] * 1000))}))
        append(fill, x.el("a:stretch", null, [x.el("a:fillRect")]))
        sppr := x.el("p:spPr", null, [ps.xfrm_xml(self.x, self.y, self.cx, self.cy), x.el("a:prstGeom", {"prst": "rect"}, [x.el("a:avLst")])])
        return x.el("p:pic", null, [nv, x.el("p:blipFill", null, fill), sppr])

func fit(image, max_w, max_h):
    img := core.load_image(image)
    mw := u.length(max_w)
    mh := u.length(max_h)
    nat := img.size_emu()
    rw := to_float(mw) / to_float(nat[0])
    rh := to_float(mh) / to_float(nat[1])
    r := rw if rw < rh else rh
    return [to_int(to_float(nat[0]) * r), to_int(to_float(nat[1]) * r)]

func parse_picture(el, rels, images):
    blip := x.find(el, "a:blip")
    if blip == null:
        return null
    rid := x.attr(blip, "r:embed", null)
    if rid == null:
        return null
    data := images(rid)
    if data == null:
        return null
    p := null
    try:
        p = Picture(data)
    catch e:
        return null
    sppr := x.first(el, "p:spPr")
    if sppr != null:
        xf := ps.read_xfrm(x.first(sppr, "a:xfrm"))
        p.x = xf[0]
        p.y = xf[1]
        if xf[2] > 0:
            p.cx = xf[2]
        if xf[3] > 0:
            p.cy = xf[3]
    cnv := x.find(el, "p:cNvPr")
    if cnv != null:
        p.name = x.attr(cnv, "name", null)
        p.description = x.attr(cnv, "descr", "")
    return p
