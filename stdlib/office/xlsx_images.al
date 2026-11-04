# ALEX STANDARD LIBRARY — office.xlsx_images
# Images et dessins des feuilles de calcul (SpreadsheetDrawingML, xl/drawings/drawingN.xml) : ancrage sur une
# cellule, taille, construction du dessin commun aux images et aux graphiques, lecture des images existantes.
#
#   use office.xlsx_images as xi
#   img := xi.SheetImage("logo.png", "B2", "4cm")        # largeur imposée, proportions conservées
#   ws.images = ws.images + ...                         # préférez ws.add_image via excel.Workbook / xlsx_sheets
#
# SheetImage(image, anchor="A1", width=null, height=null, description="", name=null)
#   image : chemin, octets ou core.Image   anchor : cellule du coin supérieur gauche   width / height : longueurs
#   champs : image anchor cx cy description name offset_x offset_y (EMU dans la cellule)
# Fonctions :
#   anchor_xml(ws, anchor, cx, cy, contenu, offset_x=0, offset_y=0) -> xdr:twoCellAnchor (fin calculée d'après les
#       largeurs de colonnes et hauteurs de lignes de la feuille)
#   picture_xml(ident, name, description, rid, cx, cy) -> xdr:pic
#   chart_frame_xml(ident, name, rid, cx, cy) -> xdr:graphicFrame (graphique, voir xlsx_charts)
#   drawing_xml(anchors) -> xdr:wsDr
#   parse_drawing(nœud_wsDr) -> [{"kind": "image" | "chart", "rid", "anchor", "cx", "cy", "name", "description"}]
#   col_width_emu(ws, col)   row_height_emu(ws, row)
# Erreurs : FormatError (image non reconnue), XLSXError.

from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core

const _CHART_URI := "http://schemas.openxmlformats.org/drawingml/2006/chart"
const DEFAULT_COL_EMU := 609600
const DEFAULT_ROW_EMU := 190500

class SheetImage:
    func init(image, anchor="A1", width=null, height=null, description="", name=null):
        self.image = core.load_image(image)
        sz := self.image.size_emu(width, height)
        self.cx = sz[0]
        self.cy = sz[1]
        self.anchor = anchor
        self.description = description
        self.name = name
        self.offset_x = 0
        self.offset_y = 0

# Largeur d'une colonne en EMU (largeur Excel en caractères -> pixels à 96 ppp : trunc(w * 7 + 5)).
func col_width_emu(ws, col):
    if ws != null and contains_key(ws.col_widths, col):
        w := ws.col_widths[col]
        px := to_int(w * 7.0 + 5.0)
        return px * 9525
    return DEFAULT_COL_EMU

func row_height_emu(ws, row):
    if ws != null and contains_key(ws.row_heights, row):
        return to_int(ws.row_heights[row] * 12700.0)
    return DEFAULT_ROW_EMU

func _marker(tag, col, col_off, row, row_off):
    return x.el(tag, null, [x.el("xdr:col", null, [str(col - 1)]), x.el("xdr:colOff", null, [str(col_off)]), x.el("xdr:row", null, [str(row - 1)]), x.el("xdr:rowOff", null, [str(row_off)])])

func anchor_xml(ws, anchor, cx, cy, content, offset_x=0, offset_y=0):
    p := u.parse_cell(anchor)
    c := p["col"]
    r := p["row"]
    # position de fin : on parcourt les colonnes / lignes jusqu'à couvrir cx / cy
    rem := cx + offset_x
    ec := c
    while rem >= col_width_emu(ws, ec):
        rem = rem - col_width_emu(ws, ec)
        ec = ec + 1
    end_col_off := rem
    rem = cy + offset_y
    er := r
    while rem >= row_height_emu(ws, er):
        rem = rem - row_height_emu(ws, er)
        er = er + 1
    end_row_off := rem
    return x.el("xdr:twoCellAnchor", {"editAs": "oneCell"}, [_marker("xdr:from", c, offset_x, r, offset_y), _marker("xdr:to", ec, end_col_off, er, end_row_off), content, x.el("xdr:clientData")])

func picture_xml(ident, name, description, rid, cx, cy):
    return x.el("xdr:pic", null, [x.el("xdr:nvPicPr", null, [x.el("xdr:cNvPr", {"id": str(ident), "name": name, "descr": description if description != "" else null}), x.el("xdr:cNvPicPr", null, [x.el("a:picLocks", {"noChangeAspect": "1"})])]), x.el("xdr:blipFill", null, [x.el("a:blip", {"xmlns:r": x.NS["r"], "r:embed": rid}), x.el("a:stretch", null, [x.el("a:fillRect")])]), x.el("xdr:spPr", null, [x.el("a:xfrm", null, [x.el("a:off", {"x": "0", "y": "0"}), x.el("a:ext", {"cx": str(cx), "cy": str(cy)})]), x.el("a:prstGeom", {"prst": "rect"}, [x.el("a:avLst")])])])

func chart_frame_xml(ident, name, rid, cx, cy):
    return x.el("xdr:graphicFrame", {"macro": ""}, [x.el("xdr:nvGraphicFramePr", null, [x.el("xdr:cNvPr", {"id": str(ident), "name": name}), x.el("xdr:cNvGraphicFramePr")]), x.el("xdr:xfrm", null, [x.el("a:off", {"x": "0", "y": "0"}), x.el("a:ext", {"cx": str(cx), "cy": str(cy)})]), x.el("a:graphic", null, [x.el("a:graphicData", {"uri": _CHART_URI}, [x.el("c:chart", {"xmlns:c": x.NS["c"], "xmlns:r": x.NS["r"], "r:id": rid})])])])

func drawing_xml(anchors):
    return x.el("xdr:wsDr", {"xmlns:xdr": x.NS["xdr"], "xmlns:a": x.NS["a"]}, anchors)

func _anchor_ref(a):
    fr := x.first(a, "xdr:from")
    if fr == null:
        return "A1"
    col := to_int(_num(x.text(x.first(fr, "xdr:col")))) + 1
    row := to_int(_num(x.text(x.first(fr, "xdr:row")))) + 1
    return u.cell_ref(row, col)

func _num(t):
    v := u.parse_number(t)
    return v if v != null else 0

func parse_drawing(root):
    out := []
    for a in x.children(root):
        ln := x.local_name(a["tag"])
        if ln != "twoCellAnchor" and ln != "oneCellAnchor" and ln != "absoluteAnchor":
            continue
        ref := _anchor_ref(a)
        cx := 0
        cy := 0
        ext := x.find(a, "a:ext")
        if ext != null:
            cx = x.attr_int(ext, "cx", 0)
            cy = x.attr_int(ext, "cy", 0)
        pic := x.first(a, "xdr:pic")
        if pic != null:
            blip := x.find(pic, "a:blip")
            nv := x.find(pic, "xdr:cNvPr")
            if blip != null:
                append(out, {"kind": "image", "rid": x.attr(blip, "r:embed", null), "anchor": ref, "cx": cx, "cy": cy, "name": x.attr(nv, "name", ""), "description": x.attr(nv, "descr", "")})
            continue
        gf := x.first(a, "xdr:graphicFrame")
        if gf != null:
            ch := x.find(gf, "c:chart")
            nv := x.find(gf, "xdr:cNvPr")
            if ch != null:
                append(out, {"kind": "chart", "rid": x.attr(ch, "r:id", null), "anchor": ref, "cx": cx, "cy": cy, "name": x.attr(nv, "name", ""), "description": ""})
    return out
