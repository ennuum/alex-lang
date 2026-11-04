# ALEX STANDARD LIBRARY — office.docx_images
# Images des documents Word : images en ligne (wp:inline) et ancrées (wp:anchor, lues ; écrites en ligne ou
# flottantes), avec la DrawingML commune (a:graphic / pic:pic).
#
#   use office.docx_images as dimg
#   img := dimg.InlineImage(core.load_image("logo.png"), "4cm")      # largeur imposée, proportions conservées
#   par.add_image(img)                                               # voir docx_paragraphs.Paragraph
#
# InlineImage(image, width=null, height=null, description="", name=null, floating=false, align=null)
#   image : core.Image (ou chemin / octets : chargés par core.load_image)
#   width / height : longueurs (EMU ou « 5cm », « 2in »...) ; absentes : taille naturelle, limitée à max_width
#   floating : image ancrée (habillage carré) alignée à `align` ("left" | "center" | "right")
#   champs : image cx cy description name floating align rid (identifiant de relation, à l'écriture / lecture)
#   to_xml(ctx) -> nœud w:drawing (ctx.image_rel(image) -> rId, ctx.next_shape_id() -> entier)
# Fonctions : drawing_xml(rid, cx, cy, ident, name, description, floating=false, align=null)
#   parse_drawing(nœud_w:drawing) -> {"rid", "cx", "cy", "description", "name", "floating"} ou null
#   SUPPORTED : formats acceptés par Word (png jpeg gif bmp tiff)   MAX_WIDTH : 6 pouces (largeur utile par défaut)
# Erreurs : DOCXError (format d'image non accepté par Word), FormatError.

from core use len, type, to_int, to_float
from collections use append, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core

const SUPPORTED := ["png", "jpeg", "gif", "bmp", "tiff"]
const MAX_WIDTH := 5486400
const _PIC_URI := "http://schemas.openxmlformats.org/drawingml/2006/picture"

class InlineImage:
    func init(image, width=null, height=null, description="", name=null, floating=false, align=null):
        img := core.load_image(image)
        ok := false
        for f in SUPPORTED:
            if img.format == f:
                ok = true
        if not ok:
            errors.fail(errors.DOCX, "format d'image non pris en charge par Word : " + img.format + " (png, jpeg, gif, bmp, tiff)")
        self.image = img
        size := img.size_emu(width, height)
        if width == null and height == null and size[0] > MAX_WIDTH:
            size = img.size_emu(MAX_WIDTH, null)
        self.cx = size[0]
        self.cy = size[1]
        self.description = description
        self.name = name
        self.floating = floating
        self.align = align
        self.rid = null

    func to_xml(ctx):
        rid := ctx.image_rel(self.image)
        self.rid = rid
        ident := ctx.next_shape_id()
        nm := self.name
        if nm == null:
            nm = "Image " + str(ident)
        return drawing_xml(rid, self.cx, self.cy, ident, nm, self.description, self.floating, self.align)

func _graphic(rid, cx, cy, ident, name):
    pic := x.el("pic:pic", {"xmlns:pic": x.NS["pic"]}, [x.el("pic:nvPicPr", null, [x.el("pic:cNvPr", {"id": str(ident), "name": name}), x.el("pic:cNvPicPr", null, [x.el("a:picLocks", {"noChangeAspect": "1", "noChangeArrowheads": "1"})])]), x.el("pic:blipFill", null, [x.el("a:blip", {"r:embed": rid}), x.el("a:stretch", null, [x.el("a:fillRect")])]), x.el("pic:spPr", {"bwMode": "auto"}, [x.el("a:xfrm", null, [x.el("a:off", {"x": "0", "y": "0"}), x.el("a:ext", {"cx": str(cx), "cy": str(cy)})]), x.el("a:prstGeom", {"prst": "rect"}, [x.el("a:avLst")])])])
    return x.el("a:graphic", {"xmlns:a": x.NS["a"]}, [x.el("a:graphicData", {"uri": _PIC_URI}, [pic])])

func drawing_xml(rid, cx, cy, ident, name, description="", floating=false, align=null):
    doc_pr := x.el("wp:docPr", {"id": str(ident), "name": name, "descr": description if description != "" else null})
    frame := x.el("wp:cNvGraphicFramePr", null, [x.el("a:graphicFrameLocks", {"xmlns:a": x.NS["a"], "noChangeAspect": "1"})])
    if not floating:
        inline := x.el("wp:inline", {"distT": "0", "distB": "0", "distL": "0", "distR": "0"}, [x.el("wp:extent", {"cx": str(cx), "cy": str(cy)}), x.el("wp:effectExtent", {"l": "0", "t": "0", "r": "0", "b": "0"}), doc_pr, frame, _graphic(rid, cx, cy, ident, name)])
        return x.el("w:drawing", null, [inline])
    a := align
    if a == null:
        a = "center"
    al := string.lower(a)
    if al != "left" and al != "center" and al != "right":
        raise("ValueError", "alignement d'image flottante : left, center ou right")
    anchor := x.el("wp:anchor", {"distT": "0", "distB": "0", "distL": "114300", "distR": "114300", "simplePos": "0", "relativeHeight": str(251658240 + ident), "behindDoc": "0", "locked": "0", "layoutInCell": "1", "allowOverlap": "1"}, [x.el("wp:simplePos", {"x": "0", "y": "0"}), x.el("wp:positionH", {"relativeFrom": "column"}, [x.el("wp:align", null, [al])]), x.el("wp:positionV", {"relativeFrom": "paragraph"}, [x.el("wp:posOffset", null, ["0"])]), x.el("wp:extent", {"cx": str(cx), "cy": str(cy)}), x.el("wp:effectExtent", {"l": "0", "t": "0", "r": "0", "b": "0"}), x.el("wp:wrapSquare", {"wrapText": "bothSides"}), doc_pr, frame, _graphic(rid, cx, cy, ident, name)])
    return x.el("w:drawing", null, [anchor])

# Informations d'une image d'un w:drawing (ou d'un w:pict VML ancien : rid seulement) ; null si ce n'est pas une image.
func parse_drawing(node):
    holder := x.first(node, "wp:inline")
    floating := false
    if holder == null:
        holder = x.first(node, "wp:anchor")
        floating = true
    if holder == null:
        im := x.find(node, "v:imagedata")
        if im != null:
            return {"rid": x.attr(im, "r:id", null), "cx": 0, "cy": 0, "description": x.attr(im, "o:title", ""), "name": "", "floating": false}
        return null
    blip := x.find(holder, "a:blip")
    if blip == null:
        return null
    ext := x.first(holder, "wp:extent")
    dp := x.first(holder, "wp:docPr")
    return {"rid": x.attr(blip, "r:embed", x.attr(blip, "r:link", null)), "cx": x.attr_int(ext, "cx", 0), "cy": x.attr_int(ext, "cy", 0), "description": x.attr(dp, "descr", ""), "name": x.attr(dp, "name", ""), "floating": floating}
