# ALEX STANDARD LIBRARY — office.pptx_writer
# Écriture des présentations PowerPoint (.pptx) : presentation.xml, masque et six dispositions (Titre, Titre et
# contenu, Titre seul, En-tête de section, Deux contenus, Vide), thème (couleurs et polices paramétrables), diapositives,
# notes du présentateur (masque des notes), images, tableaux, graphiques avec classeur incorporé, propriétés.
#
#   use office.pptx_writer as writer
#   writer.save(prs, "sortie.pptx")            # prs : powerpoint.Presentation (ou objet de même forme)
#
# Forme attendue de `prs` : slides (pptx_slides.Slide) width height (EMU) theme (dict : "colors" -> liste de 6
#   couleurs d'accentuation, "dark", "light", "major_font", "minor_font", "name") metadata (Metadata).
# Fonctions : build_package(prs) -> core.Package   to_bytes(prs)   save(prs, chemin)   theme_xml(theme) -> texte XML
#   DEFAULT_THEME   LAYOUT_FILES (disposition -> numéro de slideLayout)
# Erreurs : PPTXError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.metadata as metadata
use office.pptx_text as pt
use office.pptx_shapes as ps
use office.pptx_slides as sl

const DEFAULT_THEME := {"name": "ALEX", "colors": ["4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47"], "dark": "000000", "light": "FFFFFF", "dark2": "44546A", "light2": "E7E6E6", "link": "0563C1", "visited": "954F72", "major_font": "Calibri Light", "minor_font": "Calibri"}
const LAYOUT_FILES := {"title": 1, "title_content": 2, "section": 3, "two_content": 4, "title_only": 5, "blank": 6}
const _LAYOUT_DEFS := [["title", "Diapositive de titre", "title"], ["title_content", "Titre et contenu", "obj"], ["section", "En-tête de section", "secHead"], ["two_content", "Deux contenus", "twoObj"], ["title_only", "Titre seul", "titleOnly"], ["blank", "Vide", "blank"]]

func _esc(s):
    return _n.xml_escape(s, true)

func theme_xml(theme):
    t := u.merge(DEFAULT_THEME, theme)
    c := t["colors"]
    while len(c) < 6:
        append(c, DEFAULT_THEME["colors"][len(c)])
    accents := ""
    k := 0
    while k < 6:
        accents = accents + "<a:accent" + str(k + 1) + "><a:srgbClr val=\"" + u.color_hex(c[k]) + "\"/></a:accent" + str(k + 1) + ">"
        k = k + 1
    mj := _esc(t["major_font"])
    mn := _esc(t["minor_font"])
    return "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<a:theme xmlns:a=\"http://schemas.openxmlformats.org/drawingml/2006/main\" name=\"" + _esc(t["name"]) + "\"><a:themeElements><a:clrScheme name=\"" + _esc(t["name"]) + "\"><a:dk1><a:srgbClr val=\"" + u.color_hex(t["dark"]) + "\"/></a:dk1><a:lt1><a:srgbClr val=\"" + u.color_hex(t["light"]) + "\"/></a:lt1><a:dk2><a:srgbClr val=\"" + u.color_hex(t["dark2"]) + "\"/></a:dk2><a:lt2><a:srgbClr val=\"" + u.color_hex(t["light2"]) + "\"/></a:lt2>" + accents + "<a:hlink><a:srgbClr val=\"" + u.color_hex(t["link"]) + "\"/></a:hlink><a:folHlink><a:srgbClr val=\"" + u.color_hex(t["visited"]) + "\"/></a:folHlink></a:clrScheme><a:fontScheme name=\"" + _esc(t["name"]) + "\"><a:majorFont><a:latin typeface=\"" + mj + "\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:majorFont><a:minorFont><a:latin typeface=\"" + mn + "\"/><a:ea typeface=\"\"/><a:cs typeface=\"\"/></a:minorFont></a:fontScheme><a:fmtScheme name=\"Office\"><a:fillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\"><a:schemeClr val=\"phClr\"><a:lumMod val=\"110000\"/><a:satMod val=\"105000\"/><a:tint val=\"67000\"/></a:schemeClr></a:gs><a:gs pos=\"50000\"><a:schemeClr val=\"phClr\"><a:lumMod val=\"105000\"/><a:satMod val=\"103000\"/><a:tint val=\"73000\"/></a:schemeClr></a:gs><a:gs pos=\"100000\"><a:schemeClr val=\"phClr\"><a:lumMod val=\"105000\"/><a:satMod val=\"109000\"/><a:tint val=\"81000\"/></a:schemeClr></a:gs></a:gsLst><a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill><a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\"><a:schemeClr val=\"phClr\"><a:satMod val=\"103000\"/><a:lumMod val=\"102000\"/><a:tint val=\"94000\"/></a:schemeClr></a:gs><a:gs pos=\"50000\"><a:schemeClr val=\"phClr\"><a:satMod val=\"110000\"/><a:lumMod val=\"100000\"/><a:shade val=\"100000\"/></a:schemeClr></a:gs><a:gs pos=\"100000\"><a:schemeClr val=\"phClr\"><a:lumMod val=\"99000\"/><a:satMod val=\"120000\"/><a:shade val=\"78000\"/></a:schemeClr></a:gs></a:gsLst><a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill></a:fillStyleLst><a:lnStyleLst><a:ln w=\"6350\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln><a:ln w=\"12700\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln><a:ln w=\"19050\" cap=\"flat\" cmpd=\"sng\" algn=\"ctr\"><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:prstDash val=\"solid\"/><a:miter lim=\"800000\"/></a:ln></a:lnStyleLst><a:effectStyleLst><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst/></a:effectStyle><a:effectStyle><a:effectLst><a:outerShdw blurRad=\"57150\" dist=\"19050\" dir=\"5400000\" algn=\"ctr\" rotWithShape=\"0\"><a:srgbClr val=\"000000\"><a:alpha val=\"63000\"/></a:srgbClr></a:outerShdw></a:effectLst></a:effectStyle></a:effectStyleLst><a:bgFillStyleLst><a:solidFill><a:schemeClr val=\"phClr\"/></a:solidFill><a:solidFill><a:schemeClr val=\"phClr\"><a:tint val=\"95000\"/><a:satMod val=\"170000\"/></a:schemeClr></a:solidFill><a:gradFill rotWithShape=\"1\"><a:gsLst><a:gs pos=\"0\"><a:schemeClr val=\"phClr\"><a:tint val=\"93000\"/><a:satMod val=\"150000\"/><a:shade val=\"98000\"/><a:lumMod val=\"102000\"/></a:schemeClr></a:gs><a:gs pos=\"100000\"><a:schemeClr val=\"phClr\"><a:shade val=\"63000\"/><a:satMod val=\"120000\"/></a:schemeClr></a:gs></a:gsLst><a:lin ang=\"5400000\" scaled=\"0\"/></a:gradFill></a:bgFillStyleLst></a:fmtScheme></a:themeElements><a:objectDefaults/><a:extraClrSchemeLst/></a:theme>"

# ---------------------------------------------------------------------------------------------- masque et dispositions

func _ph_shape(ident, name, ph_type, idx, box, extra_text=null):
    attrs := {}
    if ph_type != null:
        attrs["type"] = ph_type
    if idx != null:
        attrs["idx"] = str(idx)
    body_kids := [x.el("a:bodyPr"), x.el("a:lstStyle")]
    paras := extra_text if extra_text != null else [x.el("a:p", null, [x.el("a:endParaRPr", {"lang": "fr-FR"})])]
    for p in paras:
        append(body_kids, p)
    return x.el("p:sp", null, [x.el("p:nvSpPr", null, [x.el("p:cNvPr", {"id": str(ident), "name": name}), x.el("p:cNvSpPr", null, [x.el("a:spLocks", {"noGrp": "1"})]), x.el("p:nvPr", null, [x.el("p:ph", attrs)])]), x.el("p:spPr", null, [ps.xfrm_xml(box[0], box[1], box[2], box[3])]), x.el("p:txBody", null, body_kids)])

func _text_para(text, lvl=null):
    attrs := {"lvl": str(lvl)} if lvl != null and lvl > 0 else null
    kids := []
    if attrs != null:
        append(kids, x.el("a:pPr", attrs))
    append(kids, x.el("a:r", null, [x.el("a:rPr", {"lang": "fr-FR"}), x.el("a:t", null, [text])]))
    return x.el("a:p", null, kids)

func _sptree(shapes):
    kids := [x.el("p:nvGrpSpPr", null, [x.el("p:cNvPr", {"id": "1", "name": ""}), x.el("p:cNvGrpSpPr"), x.el("p:nvPr")]), x.el("p:grpSpPr", null, [x.el("a:xfrm", null, [x.el("a:off", {"x": "0", "y": "0"}), x.el("a:ext", {"cx": "0", "cy": "0"}), x.el("a:chOff", {"x": "0", "y": "0"}), x.el("a:chExt", {"cx": "0", "cy": "0"})])])]
    for s in shapes:
        append(kids, s)
    return x.el("p:spTree", null, kids)

func _lvl_ppr(tag, lvl, size, bullet, mar):
    kids := []
    if bullet:
        kids = [x.el("a:lnSpc", null, [x.el("a:spcPct", {"val": "90000"})]), x.el("a:spcBef", null, [x.el("a:spcPts", {"val": "1000" if lvl == 1 else "500"})]), x.el("a:buFont", {"typeface": "Arial", "panose": "020B0604020202020204", "pitchFamily": "34", "charset": "0"}), x.el("a:buChar", {"char": "•"})]
    append(kids, x.el("a:defRPr", {"sz": str(size), "kern": "1200"}, [x.el("a:solidFill", null, [x.el("a:schemeClr", {"val": "tx1"})]), x.el("a:latin", {"typeface": "+mn-lt"}), x.el("a:ea", {"typeface": "+mn-ea"}), x.el("a:cs", {"typeface": "+mn-cs"})]))
    attrs := {"marL": str(mar), "indent": "-228600" if bullet else "0", "algn": "l", "defTabSz": "914400", "rtl": "0", "eaLnBrk": "1", "latinLnBrk": "0", "hangingPunct": "1"}
    return x.el(tag, attrs, kids)

func _master_xml(w, h):
    b := sl.layout_boxes(w, h)
    title := _ph_shape(2, "Espace réservé du titre 1", "title", null, b["title"], [_text_para("Modifiez le style du titre")])
    body := _ph_shape(3, "Espace réservé du texte 2", "body", 1, b["body"], [_text_para("Modifiez les styles du texte du masque"), _text_para("Deuxième niveau", 1), _text_para("Troisième niveau", 2)])
    title_style := x.el("p:titleStyle", null, [x.el("a:lvl1pPr", {"algn": "l", "defTabSz": "914400", "rtl": "0", "eaLnBrk": "1", "latinLnBrk": "0", "hangingPunct": "1"}, [x.el("a:lnSpc", null, [x.el("a:spcPct", {"val": "90000"})]), x.el("a:spcBef", null, [x.el("a:spcPct", {"val": "0"})]), x.el("a:buNone"), x.el("a:defRPr", {"sz": "4400", "kern": "1200"}, [x.el("a:solidFill", null, [x.el("a:schemeClr", {"val": "tx1"})]), x.el("a:latin", {"typeface": "+mj-lt"}), x.el("a:ea", {"typeface": "+mj-ea"}), x.el("a:cs", {"typeface": "+mj-cs"})])])])
    sizes := [2800, 2400, 2000, 1800, 1800, 1800, 1800, 1800, 1800]
    lv := []
    k := 0
    while k < 9:
        append(lv, _lvl_ppr("a:lvl" + str(k + 1) + "pPr", k + 1, sizes[k], true, 228600 + 457200 * k))
        k = k + 1
    body_style := x.el("p:bodyStyle", null, lv)
    olv := [x.el("a:defPPr", null, [x.el("a:defRPr", {"lang": "fr-FR"})])]
    k = 0
    while k < 9:
        append(olv, _lvl_ppr("a:lvl" + str(k + 1) + "pPr", k + 1, 1800, false, 457200 * k))
        k = k + 1
    other_style := x.el("p:otherStyle", null, olv)
    ids := []
    k = 0
    while k < len(_LAYOUT_DEFS):
        append(ids, x.el("p:sldLayoutId", {"id": str(2147483649 + k), "r:id": "rId" + str(k + 1)}))
        k = k + 1
    return x.el("p:sldMaster", {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"]}, [x.el("p:cSld", null, [x.el("p:bg", null, [x.el("p:bgRef", {"idx": "1001"}, [x.el("a:schemeClr", {"val": "bg1"})])]), _sptree([title, body])]), x.el("p:clrMap", {"bg1": "lt1", "tx1": "dk1", "bg2": "lt2", "tx2": "dk2", "accent1": "accent1", "accent2": "accent2", "accent3": "accent3", "accent4": "accent4", "accent5": "accent5", "accent6": "accent6", "hlink": "hlink", "folHlink": "folHlink"}), x.el("p:sldLayoutIdLst", null, ids), x.el("p:txStyles", null, [title_style, body_style, other_style])])

func _layout_xml(key, name, typ, w, h):
    b := sl.layout_boxes(w, h)
    shapes := []
    if key == "title":
        t := _ph_shape(2, "Titre 1", "ctrTitle", null, b["ctr_title"], [x.el("a:p", null, [x.el("a:pPr", {"algn": "ctr"}), x.el("a:r", null, [x.el("a:rPr", {"lang": "fr-FR"}), x.el("a:t", null, ["Modifiez le style du titre"])])])])
        x.first(t, "p:txBody")["children"][0] = x.el("a:bodyPr", {"anchor": "b"})
        x.first(t, "p:txBody")["children"][1] = x.el("a:lstStyle", null, [x.el("a:lvl1pPr", {"algn": "ctr"}, [x.el("a:defRPr", {"sz": "6000"})])])
        append(shapes, t)
        st := _ph_shape(3, "Sous-titre 2", "subTitle", 1, b["subtitle"], [x.el("a:p", null, [x.el("a:pPr", {"marL": "0", "indent": "0", "algn": "ctr"}, [x.el("a:buNone")]), x.el("a:r", null, [x.el("a:rPr", {"lang": "fr-FR"}), x.el("a:t", null, ["Modifiez le style des sous-titres du masque"])])])])
        lst := x.first(st, "p:txBody")["children"]
        lst[1] = x.el("a:lstStyle", null, [x.el("a:lvl1pPr", {"marL": "0", "indent": "0", "algn": "ctr"}, [x.el("a:buNone"), x.el("a:defRPr", {"sz": "2400"})])])
        append(shapes, st)
    elif key == "title_content":
        append(shapes, _ph_shape(2, "Titre 1", "title", null, b["title"]))
        append(shapes, _ph_shape(3, "Espace réservé du contenu 2", null, 1, b["body"]))
    elif key == "section":
        t := _ph_shape(2, "Titre 1", "title", null, b["section_title"])
        x.first(t, "p:txBody")["children"][0] = x.el("a:bodyPr", {"anchor": "b"})
        x.first(t, "p:txBody")["children"][1] = x.el("a:lstStyle", null, [x.el("a:lvl1pPr", null, [x.el("a:defRPr", {"sz": "6000"})])])
        append(shapes, t)
        txt := _ph_shape(3, "Espace réservé du texte 2", "body", 1, b["section_text"])
        x.first(txt, "p:txBody")["children"][1] = x.el("a:lstStyle", null, [x.el("a:lvl1pPr", {"marL": "0", "indent": "0"}, [x.el("a:buNone"), x.el("a:defRPr", {"sz": "2400"}, [x.el("a:solidFill", null, [x.el("a:schemeClr", {"val": "tx1"}, [x.el("a:tint", {"val": "75000"})])])])])])
        append(shapes, txt)
    elif key == "two_content":
        append(shapes, _ph_shape(2, "Titre 1", "title", null, b["title"]))
        append(shapes, _ph_shape(3, "Espace réservé du contenu 2", null, 1, b["left"]))
        append(shapes, _ph_shape(4, "Espace réservé du contenu 3", null, 2, b["right"]))
    elif key == "title_only":
        append(shapes, _ph_shape(2, "Titre 1", "title", null, b["title"]))
    attrs := {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"], "type": typ, "preserve": "1"}
    return x.el("p:sldLayout", attrs, [x.el("p:cSld", {"name": name}, [_sptree(shapes)]), x.el("p:clrMapOvr", null, [x.el("a:masterClrMapping")])])

func _notes_master_xml(w, h):
    nw := 6858000
    nh := 9144000
    img := x.el("p:sp", null, [x.el("p:nvSpPr", null, [x.el("p:cNvPr", {"id": "2", "name": "Espace réservé de l'image des diapositives 1"}), x.el("p:cNvSpPr", null, [x.el("a:spLocks", {"noGrp": "1", "noRot": "1", "noChangeAspect": "1"})]), x.el("p:nvPr", null, [x.el("p:ph", {"type": "sldImg", "idx": "2"})])]), x.el("p:spPr", null, [ps.xfrm_xml(685800, 1143000, 5486400, 3086100), x.el("a:prstGeom", {"prst": "rect"}, [x.el("a:avLst")]), x.el("a:noFill"), x.el("a:ln", {"w": "12700"}, [x.el("a:solidFill", null, [x.el("a:prstClr", {"val": "black"})])])])])
    body := _ph_shape(3, "Espace réservé des notes 2", "body", 3, [685800, 4400550, 5486400, 3600450], [_text_para("Modifiez les styles du texte du masque")])
    lv := []
    k := 0
    while k < 9:
        append(lv, x.el("a:lvl" + str(k + 1) + "pPr", {"marL": str(457200 * k), "algn": "l", "defTabSz": "914400", "rtl": "0", "eaLnBrk": "1", "latinLnBrk": "0", "hangingPunct": "1"}, [x.el("a:defRPr", {"sz": "1200", "kern": "1200"}, [x.el("a:solidFill", null, [x.el("a:schemeClr", {"val": "tx1"})]), x.el("a:latin", {"typeface": "+mn-lt"}), x.el("a:ea", {"typeface": "+mn-ea"}), x.el("a:cs", {"typeface": "+mn-cs"})])]))
        k = k + 1
    return x.el("p:notesMaster", {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"]}, [x.el("p:cSld", null, [x.el("p:bg", null, [x.el("p:bgRef", {"idx": "1001"}, [x.el("a:schemeClr", {"val": "bg1"})])]), _sptree([img, body])]), x.el("p:clrMap", {"bg1": "lt1", "tx1": "dk1", "bg2": "lt2", "tx2": "dk2", "accent1": "accent1", "accent2": "accent2", "accent3": "accent3", "accent4": "accent4", "accent5": "accent5", "accent6": "accent6", "hlink": "hlink", "folHlink": "folHlink"}), x.el("p:notesStyle", null, lv)])

func _notes_slide_xml(text):
    img := x.el("p:sp", null, [x.el("p:nvSpPr", null, [x.el("p:cNvPr", {"id": "2", "name": "Espace réservé de l'image des diapositives 1"}), x.el("p:cNvSpPr", null, [x.el("a:spLocks", {"noGrp": "1", "noRot": "1", "noChangeAspect": "1"})]), x.el("p:nvPr", null, [x.el("p:ph", {"type": "sldImg"})])]), x.el("p:spPr")])
    paras := []
    for line in string.split(string.replace(u.to_text(text), "\r\n", "\n"), "\n"):
        if line == "":
            append(paras, x.el("a:p", null, [x.el("a:endParaRPr", {"lang": "fr-FR"})]))
        else:
            append(paras, x.el("a:p", null, [x.el("a:r", null, [x.el("a:rPr", {"lang": "fr-FR", "dirty": "0"}), x.el("a:t", null, [line])])]))
    body_kids := [x.el("a:bodyPr"), x.el("a:lstStyle")]
    for p in paras:
        append(body_kids, p)
    body := x.el("p:sp", null, [x.el("p:nvSpPr", null, [x.el("p:cNvPr", {"id": "3", "name": "Espace réservé des notes 2"}), x.el("p:cNvSpPr", null, [x.el("a:spLocks", {"noGrp": "1"})]), x.el("p:nvPr", null, [x.el("p:ph", {"type": "body", "idx": "1"})])]), x.el("p:spPr"), x.el("p:txBody", null, body_kids)])
    return x.el("p:notes", {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"]}, [x.el("p:cSld", null, [_sptree([img, body])]), x.el("p:clrMapOvr", null, [x.el("a:masterClrMapping")])])

# ---------------------------------------------------------------------------------------------- contexte d'écriture

class _SlideCtx:
    func init(pkg, part, shared, slide_parts):
        self.pkg = pkg
        self.part = part
        self.shared = shared
        self.slide_parts = slide_parts
        self._links = {}

    func link_rel(url):
        if contains_key(self._links, url):
            return self._links[url]
        rid := self.pkg.add_rel(self.part, core.REL_HYPERLINK, url, true)
        self._links[url] = rid
        return rid

    func slide_link_rel(n):
        if n < 1 or n > len(self.slide_parts):
            errors.fail(errors.PPTX, "lien vers une diapositive inexistante : " + str(n))
        key := "#slide" + str(n)
        if contains_key(self._links, key):
            return self._links[key]
        rid := self.pkg.add_rel(self.part, core.REL_SLIDE, self.pkg.relative(self.part, self.slide_parts[n - 1]))
        self._links[key] = rid
        return rid

    func image_rel(image):
        key := str(_n.crc32(image.data, 0)) + ":" + str(len(image.data))
        media := self.shared["media"]
        name := null
        if contains_key(media, key):
            name = media[key]
        else:
            name = self.pkg.unique_name("ppt/media/image", "." + image.ext)
            self.pkg.write_part(name, image.data, null, false)
            media[key] = name
        lk := self.part + "|" + key
        imgs := self.shared["imgrels"]
        if contains_key(imgs, lk):
            return imgs[lk]
        rid := self.pkg.add_rel(self.part, core.REL_IMAGE, self.pkg.relative(self.part, name))
        imgs[lk] = rid
        return rid

    func chart_rel(node, workbook):
        self.shared["charts"] = self.shared["charts"] + 1
        n := self.shared["charts"]
        cpart := "ppt/charts/chart" + str(n) + ".xml"
        epart := "ppt/embeddings/Microsoft_Excel_Worksheet" + str(n) + ".xlsx"
        self.pkg.write_part(epart, workbook, null, false)
        self.pkg.set_default("xlsx", core.CT_XLSX_PACKAGE)
        erid := self.pkg.add_rel(cpart, core.REL_PACKAGE, self.pkg.relative(cpart, epart))
        x.append_child(node, x.el("c:externalData", {"r:id": erid}, [x.el("c:autoUpdate", {"val": "0"})]))
        self.pkg.write_xml(cpart, node, core.CT_CHART)
        return self.pkg.add_rel(self.part, core.REL_CHART, self.pkg.relative(self.part, cpart))

# ---------------------------------------------------------------------------------------------- paquet

func build_package(prs):
    if len(prs.slides) == 0:
        errors.fail(errors.PPTX, "une présentation doit contenir au moins une diapositive")
    w := prs.width
    h := prs.height
    pkg := core.new_package()
    pkg.set_default("rels", core.CT_RELS)
    pkg.set_default("xml", core.CT_XML)
    main := "ppt/presentation.xml"
    pkg.add_rel("", core.REL_OFFICE_DOCUMENT, main)
    # masque, dispositions, thème
    master := "ppt/slideMasters/slideMaster1.xml"
    k := 0
    for d in _LAYOUT_DEFS:
        lpart := "ppt/slideLayouts/slideLayout" + str(k + 1) + ".xml"
        pkg.add_rel(master, core.REL_SLIDE_LAYOUT, "../slideLayouts/slideLayout" + str(k + 1) + ".xml")
        pkg.write_xml(lpart, _layout_xml(d[0], d[1], d[2], w, h), core.CT_PPTX_LAYOUT)
        pkg.add_rel(lpart, core.REL_SLIDE_MASTER, "../slideMasters/slideMaster1.xml")
        k = k + 1
    pkg.add_rel(master, core.REL_THEME, "../theme/theme1.xml")
    pkg.write_xml(master, _master_xml(w, h), core.CT_PPTX_MASTER)
    pkg.write_text("ppt/theme/theme1.xml", theme_xml(prs.theme), core.CT_THEME)
    master_rid := pkg.add_rel(main, core.REL_SLIDE_MASTER, "slideMasters/slideMaster1.xml")
    has_notes := false
    for s in prs.slides:
        if s.notes != null and s.notes != "":
            has_notes = true
    notes_master_rid := null
    if has_notes:
        nm := "ppt/notesMasters/notesMaster1.xml"
        pkg.write_xml(nm, _notes_master_xml(w, h), core.CT_PPTX_NOTES_MASTER)
        pkg.write_text("ppt/theme/theme2.xml", theme_xml(prs.theme), core.CT_THEME)
        pkg.add_rel(nm, core.REL_THEME, "../theme/theme2.xml")
        notes_master_rid = pkg.add_rel(main, core.REL_NOTES_MASTER, "notesMasters/notesMaster1.xml")
    # diapositives
    slide_parts := []
    i := 0
    while i < len(prs.slides):
        append(slide_parts, "ppt/slides/slide" + str(i + 1) + ".xml")
        i = i + 1
    shared := {"media": {}, "imgrels": {}, "charts": 0}
    ids := []
    i = 0
    for s in prs.slides:
        part := slide_parts[i]
        lay := LAYOUT_FILES[s.layout] if contains_key(LAYOUT_FILES, s.layout) else 2
        pkg.add_rel(part, core.REL_SLIDE_LAYOUT, "../slideLayouts/slideLayout" + str(lay) + ".xml")
        s.width = w
        s.height = h
        ctx := _SlideCtx(pkg, part, shared, slide_parts)
        pkg.write_xml(part, sl.slide_xml(s, ctx), core.CT_PPTX_SLIDE)
        rid := pkg.add_rel(main, core.REL_SLIDE, "slides/slide" + str(i + 1) + ".xml")
        append(ids, x.el("p:sldId", {"id": str(256 + i), "r:id": rid}))
        if s.notes != null and s.notes != "":
            npart := "ppt/notesSlides/notesSlide" + str(i + 1) + ".xml"
            pkg.write_xml(npart, _notes_slide_xml(s.notes), core.CT_PPTX_NOTES)
            pkg.add_rel(npart, core.REL_NOTES_MASTER, "../notesMasters/notesMaster1.xml")
            pkg.add_rel(npart, core.REL_SLIDE, "../slides/slide" + str(i + 1) + ".xml")
            pkg.add_rel(part, core.REL_NOTES_SLIDE, "../notesSlides/notesSlide" + str(i + 1) + ".xml")
        i = i + 1
    # propriétés de présentation
    pkg.write_xml("ppt/presProps.xml", x.el("p:presentationPr", {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"]}), core.CT_PPTX_PRES_PROPS)
    pkg.add_rel(main, core.REL_PRES_PROPS, "presProps.xml")
    pkg.write_xml("ppt/viewProps.xml", x.el("p:viewPr", {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"]}, [x.el("p:normalViewPr", null, [x.el("p:restoredLeft", {"sz": "15620"}), x.el("p:restoredTop", {"sz": "94660"})]), x.el("p:gridSpacing", {"cx": "72008", "cy": "72008"})]), core.CT_PPTX_VIEW_PROPS)
    pkg.add_rel(main, core.REL_VIEW_PROPS, "viewProps.xml")
    pkg.write_xml("ppt/tableStyles.xml", x.el("a:tblStyleLst", {"xmlns:a": x.NS["a"], "def": "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"}), core.CT_PPTX_TABLE_STYLES)
    pkg.add_rel(main, core.REL_TABLE_STYLES, "tableStyles.xml")
    pk := [x.el("p:sldMasterIdLst", null, [x.el("p:sldMasterId", {"id": "2147483648", "r:id": master_rid})])]
    if notes_master_rid != null:
        append(pk, x.el("p:notesMasterIdLst", null, [x.el("p:notesMasterId", {"r:id": notes_master_rid})]))
    append(pk, x.el("p:sldIdLst", null, ids))
    st := "custom"
    if w == 12192000 and h == 6858000:
        st = null
    elif w == 9144000 and h == 6858000:
        st = "screen4x3"
    append(pk, x.el("p:sldSz", {"cx": str(w), "cy": str(h), "type": st}))
    append(pk, x.el("p:notesSz", {"cx": "6858000", "cy": "9144000"}))
    pkg.write_xml(main, x.el("p:presentation", {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"], "saveSubsetFonts": "1"}, pk), core.CT_PPTX_MAIN)
    m := prs.metadata
    if m == null:
        m = metadata.new()
    mm := m.copy()
    now := u.now_iso()
    if mm.created == "":
        mm.created = now
    if mm.modified == "":
        mm.modified = now
    if mm.application == "":
        mm.application = metadata.GENERATOR
    metadata.apply_package(pkg, mm)
    return pkg

func to_bytes(prs):
    return build_package(prs).to_bytes()

func save(prs, path):
    build_package(prs).save(path)
    return path
