# ALEX STANDARD LIBRARY — office.odp
# Présentations OpenDocument (.odp, LibreOffice Impress) en lecture et écriture, avec le modèle de présentation
# d'office.powerpoint (Presentation / Slide / Shape / TextFrame / Picture / SlideTable / SlideChart) : titres,
# sous-titres, listes à puces à niveaux, zones de texte mises en forme, formes prédéfinies (rectangle, ellipse,
# flèches, étoiles...), lignes, images, tableaux, graphiques (objets graphiques ODF incorporés), fond de diapositive,
# diapositives masquées, notes du présentateur, métadonnées.
#
#   use office.odp as odp
#   use office.powerpoint as pp
#   prs := pp.new()
#   prs.add_title_slide("Bilan 2026", "Direction financière")
#   prs.add_bullet_slide("Points clés", ["Croissance", ["Export +8 %"], "Nouvelle usine"], "Notes...")
#   odp.save(prs, "bilan.odp")
#
#   p2 := odp.read("bilan.odp")          # -> powerpoint.Presentation
#   p2.save("bilan.pptx")                # conversion ODP -> PPTX
#
# read(chemin_ou_octets) -> powerpoint.Presentation   read_text(src, notes=true) -> str
# write(presentation) -> octets   save(presentation, chemin) -> chemin
# shape_type(kind_pptx) -> draw:type ODF   pptx_kind(draw_type) -> préréglage DrawingML
# Erreurs : ODFError, FormatError, ArchiveError, XMLError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use math
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.odf as odf
use office.powerpoint as pp
use office.pptx_slides as sl
use office.pptx_shapes as ps
use office.pptx_text as pt
use office.pptx_images as pimg
use office.pptx_tables as ptb
use office.pptx_charts as pch

const _SHAPES := {"rect": "rectangle", "roundRect": "round-rectangle", "ellipse": "ellipse", "triangle": "isosceles-triangle", "rtTriangle": "right-triangle", "diamond": "diamond", "parallelogram": "parallelogram", "trapezoid": "trapezoid", "pentagon": "pentagon", "hexagon": "hexagon", "octagon": "octagon", "star4": "star4", "star5": "star5", "star8": "star8", "star12": "star12", "star24": "star24", "rightArrow": "right-arrow", "leftArrow": "left-arrow", "upArrow": "up-arrow", "downArrow": "down-arrow", "leftRightArrow": "left-right-arrow", "upDownArrow": "up-down-arrow", "chevron": "chevron", "homePlate": "pentagon-right", "plus": "cross", "heart": "heart", "cloud": "cloud", "can": "can", "cube": "cube", "donut": "ring", "smileyFace": "smiley", "wedgeRectCallout": "rectangular-callout", "wedgeRoundRectCallout": "round-rectangular-callout", "wedgeEllipseCallout": "round-callout", "flowChartProcess": "flowchart-process", "flowChartDecision": "flowchart-decision", "flowChartTerminator": "flowchart-terminator", "lightningBolt": "lightning", "moon": "moon", "sun": "sun", "frame": "frame", "blockArc": "block-arc", "flowChartAlternateProcess": "flowchart-alternate-process"}

const _LEVEL_SIZES := [28, 24, 20, 18, 18, 18, 18, 18, 18]
const _BULLETS := ["•", "–", "•", "–", "•", "–", "•", "–", "•"]

func shape_type(kind):
    return u.get(_SHAPES, kind, "ooxml-" + kind)

func pptx_kind(draw_type):
    if draw_type == null:
        return "rect"
    if string.starts_with(draw_type, "ooxml-"):
        return _n.str_slice(draw_type, 6, null)
    for k in keys(_SHAPES):
        if _SHAPES[k] == draw_type:
            return k
    return "rect"

func _cm(emu):
    return u.format_number(u.round_to(to_float(emu) / 360000.0, 3)) + "cm"

func _emu(len_text, fallback=0):
    pt_v := odf.to_pt(len_text)
    if pt_v == null:
        return fallback
    return to_int(pt_v * 12700.0 + 0.5)

# ============================================================================================== écriture

class _Writer:
    func init(pkg, prs):
        self.pkg = pkg
        self.prs = prs
        self.bank = odf.StyleBank()
        self.images = {}
        self.n_img = 0
        self.n_obj = 0
        self.lists = {}

    func list_style(numbered):
        key := "n" if numbered else "b"
        if contains_key(self.lists, key):
            return self.lists[key]
        name := "L" + str(len(keys(self.lists)) + 1)
        levels := []
        k := 1
        while k <= 9:
            props := x.el("style:list-level-properties", {"text:space-before": u.format_number(u.round_to(0.9 * to_float(k - 1), 2)) + "cm", "text:min-label-width": "0.9cm"}, [])
            if numbered:
                append(levels, x.el("text:list-level-style-number", {"text:level": str(k), "style:num-suffix": ".", "style:num-format": "1"}, [props]))
            else:
                append(levels, x.el("text:list-level-style-bullet", {"text:level": str(k), "text:bullet-char": _BULLETS[k - 1]}, [props, x.el("style:text-properties", {"fo:font-family": "OpenSymbol", "style:font-size-rel": "100%"}, [])]))
            k = k + 1
        self.bank.add_node(x.el("text:list-style", {"style:name": name}, levels))
        self.lists[key] = name
        return name

    func span(r, base):
        f := {"bold": r.bold, "italic": r.italic, "underline": r.underline, "strike": r.strike, "color": r.color, "size": r.size, "font": r.font, "highlight": r.highlight, "superscript": r.superscript, "subscript": r.subscript}
        tp := odf.text_props(u.merge(base, _non_null(f)))
        kids := odf.text_nodes(r.text)
        node := null
        if len(keys(tp)) > 0:
            node = x.el("text:span", {"text:style-name": self.bank.add("text", [x.el("style:text-properties", tp, [])])}, kids)
        if r.link != null:
            return [x.el("text:a", {"xlink:href": r.link, "xlink:type": "simple"}, [node] if node != null else kids)]
        if node != null:
            return [node]
        return kids

    func para(p, base, default_align=null):
        pp_props := {}
        al := p.align if p.align != null else default_align
        if al != null:
            pp_props["fo:text-align"] = u.get({"left": "start", "center": "center", "right": "end", "justify": "justify"}, al, "start")
        if p.space_before != null:
            pp_props["fo:margin-top"] = odf.length(p.space_before)
        if p.space_after != null:
            pp_props["fo:margin-bottom"] = odf.length(p.space_after)
        if p.line_spacing != null:
            pp_props["fo:line-height"] = u.format_number(u.round_to(to_float(p.line_spacing) * 100.0, 0)) + "%"
        b2 := base
        if p.font_size != null:
            b2 = u.merge(base, {"size": p.font_size})
        tp := odf.text_props(b2)
        kids := []
        if len(keys(pp_props)) > 0:
            append(kids, x.el("style:paragraph-properties", pp_props, []))
        if len(keys(tp)) > 0:
            append(kids, x.el("style:text-properties", tp, []))
        attrs := {}
        if len(kids) > 0:
            attrs["text:style-name"] = self.bank.add("paragraph", kids)
        out := []
        for r in p.runs:
            for n in self.span(r, {}):
                append(out, n)
        return x.el("text:p", attrs, out)

    # Paragraphes d'un cadre de texte ; bullets : puces par défaut (corps de diapositive).
    func text_children(tf, base, bullets, default_align=null, level_sizes=false):
        out := []
        if tf == null:
            return out
        for p in tf.paragraphs:
            lvl := p.level if p.level != null else 0
            b := u.merge(base, null)
            if level_sizes and not contains_key(b, "size"):
                b["size"] = _LEVEL_SIZES[lvl if lvl < 9 else 8]
            use_bullet := bullets
            numbered := false
            if p.bullet == false:
                use_bullet = false
            elif p.bullet == "number":
                use_bullet = true
                numbered = true
            elif p.bullet != null:
                use_bullet = true
            if not use_bullet:
                append(out, self.para(p, b, default_align))
                continue
            # imbrication text:list > list-item > text:list ... > text:p
            inner := x.el("text:list-item", null, [self.para(p, b, default_align)])
            k := 0
            while k < lvl:
                inner = x.el("text:list-item", null, [x.el("text:list", null, [inner])])
                k = k + 1
            append(out, x.el("text:list", {"text:style-name": self.list_style(numbered)}, [inner]))
        return out

    func graphic_style(fill, line, line_width, dash, extra=null):
        gp := {}
        if fill == "none":
            gp["draw:fill"] = "none"
        elif fill != null:
            gp["draw:fill"] = "solid"
            gp["draw:fill-color"] = "#" + u.color_hex(fill)
        else:
            gp["draw:fill"] = "solid"
            gp["draw:fill-color"] = "#4472C4"
        if line == "none":
            gp["draw:stroke"] = "none"
        elif line != null:
            gp["draw:stroke"] = "dash" if dash != null and dash != "solid" else "solid"
            gp["svg:stroke-color"] = "#" + u.color_hex(line)
        else:
            gp["draw:stroke"] = "solid"
            gp["svg:stroke-color"] = "#2F528F"
        if line_width != null:
            gp["svg:stroke-width"] = odf.length(line_width)
        gp["draw:auto-grow-height"] = "false"
        gp["draw:auto-grow-width"] = "false"
        gp["fo:wrap-option"] = "wrap"
        if extra != null:
            for k in keys(extra):
                gp[k] = extra[k]
        return self.bank.add("graphic", [x.el("style:graphic-properties", gp, [])])

    func image(img):
        key := str(_n.crc32(img.data)) + ":" + str(len(img.data))
        name := u.get(self.images, key, null)
        if name == null:
            self.n_img = self.n_img + 1
            name = "Pictures/image" + str(self.n_img) + "." + (img.format if img.format != "jpeg" else "jpg")
            self.pkg.add_file(name, img.data, img.mime)
            self.images[key] = name
        return name

func _non_null(d):
    out := {}
    for k in keys(d):
        if d[k] != null:
            out[k] = d[k]
    return out

func _geom(s):
    return {"svg:x": _cm(s.x), "svg:y": _cm(s.y), "svg:width": _cm(s.cx), "svg:height": _cm(s.cy)}

func _ph_class(t):
    if t == "title" or t == "ctrTitle":
        return "title"
    if t == "subTitle":
        return "subtitle"
    return "outline"

func _shape_node(wr, s, slide):
    if isinstance(s, pimg.Picture):
        g := _geom(s)
        g["draw:style-name"] = wr.bank.add("graphic", [x.el("style:graphic-properties", {"draw:fill": "none", "draw:stroke": "none"}, [])])
        g["draw:layer"] = "layout"
        fr := x.el("draw:frame", g, [x.el("draw:image", {"xlink:href": wr.image(s.image), "xlink:type": "simple", "xlink:show": "embed", "xlink:actuate": "onLoad"}, [x.el("text:p", null, [])])])
        if s.description != null and s.description != "":
            append(fr["children"], x.el("svg:desc", null, [s.description]))
        return fr
    if isinstance(s, ptb.SlideTable):
        return _table_node(wr, s)
    if isinstance(s, pch.SlideChart):
        wr.n_obj = wr.n_obj + 1
        folder := "Object " + str(wr.n_obj)
        root := odf.chart_xml(s.kind, s.title, s.categories, s.series, {"legend": s.legend, "stacked": s.stacked, "data_labels": s.data_labels, "x_title": s.x_title, "y_title": s.y_title, "width": to_float(s.cx) / 12700.0, "height": to_float(s.cy) / 12700.0})
        wr.pkg.add_object(folder, root)
        g := _geom(s)
        g["draw:layer"] = "layout"
        return x.el("draw:frame", g, [x.el("draw:object", {"xlink:href": "./" + folder, "xlink:type": "simple", "xlink:show": "embed", "xlink:actuate": "onLoad"}, [])])
    if not isinstance(s, ps.Shape):
        return null
    if s.kind == "line":
        gs := wr.graphic_style("none", s.line if s.line != null else "000000", s.line_width, s.dash, _arrows(s))
        x1 := s.x
        y1 := s.y
        x2 := s.x + s.cx
        y2 := s.y + s.cy
        if s.flip_h:
            x1 = s.x + s.cx
            x2 = s.x
        if s.flip_v:
            y1 = s.y + s.cy
            y2 = s.y
        return x.el("draw:line", {"draw:style-name": gs, "draw:layer": "layout", "svg:x1": _cm(x1), "svg:y1": _cm(y1), "svg:x2": _cm(x2), "svg:y2": _cm(y2)}, [])
    # espaces réservés et zones de texte
    is_text := s.kind == "textbox" or s.placeholder != null
    if is_text:
        g := _geom(s)
        cls := null
        base := {}
        bullets := false
        level_sizes := false
        align := null
        if s.placeholder != null:
            t := u.get(s.placeholder, "type", "body")
            cls = _ph_class(t)
            if cls == "title":
                base = {"size": 44 if t == "ctrTitle" else 40}
                if t == "ctrTitle":
                    align = "center"
            elif cls == "subtitle":
                base = {"size": 24, "color": "595959"}
                align = "center"
            else:
                bullets = slide.layout != "section" and slide.layout != "title"
                level_sizes = true
        gp := {"draw:fill": "none" if s.fill == null or s.fill == "none" else "solid", "draw:stroke": "none" if s.line == null or s.line == "none" else "solid", "draw:auto-grow-height": "false", "fo:padding-top": "0.125cm", "fo:padding-bottom": "0.125cm", "fo:padding-left": "0.25cm", "fo:padding-right": "0.25cm"}
        if s.fill != null and s.fill != "none":
            gp["draw:fill-color"] = "#" + u.color_hex(s.fill)
        if s.line != null and s.line != "none":
            gp["svg:stroke-color"] = "#" + u.color_hex(s.line)
        anchor := s.text.anchor if s.text != null and s.text.anchor != null else ("middle" if cls == "title" else "top")
        gp["draw:textarea-vertical-align"] = anchor
        if cls == "title" and slide.layout != "title":
            gp["draw:textarea-vertical-align"] = "middle"
        g["draw:layer"] = "layout"
        if cls != null:
            g["presentation:class"] = cls
            g["presentation:style-name"] = wr.bank.add("presentation", [x.el("style:graphic-properties", gp, [])])
            g["presentation:user-transformed"] = "true"
        else:
            g["draw:style-name"] = wr.bank.add("graphic", [x.el("style:graphic-properties", gp, [])])
        if s.rotation != 0 and s.rotation != null:
            g["draw:transform"] = _rotation(s)
            collections.remove(g, "svg:x")
            collections.remove(g, "svg:y")
        if s.name != null:
            g["draw:name"] = s.name
        box := x.el("draw:text-box", null, wr.text_children(s.text, base, bullets, align, level_sizes))
        return x.el("draw:frame", g, [box])
    # forme prédéfinie
    gs := wr.graphic_style(s.fill, s.line, s.line_width, s.dash, {"draw:textarea-vertical-align": s.text.anchor if s.text != null and s.text.anchor != null else "middle", "draw:shadow": "visible" if s.shadow else "hidden"})
    g := _geom(s)
    g["draw:style-name"] = gs
    g["draw:layer"] = "layout"
    if s.rotation != 0 and s.rotation != null:
        g["draw:transform"] = _rotation(s)
        collections.remove(g, "svg:x")
        collections.remove(g, "svg:y")
    if s.name != null:
        g["draw:name"] = s.name
    kids := wr.text_children(s.text, {"color": "FFFFFF"} if s.fill == null else {}, false, "center")
    eg := {"svg:viewBox": "0 0 21600 21600", "draw:type": shape_type(s.kind)}
    if s.flip_h:
        eg["draw:mirror-horizontal"] = "true"
    if s.flip_v:
        eg["draw:mirror-vertical"] = "true"
    append(kids, x.el("draw:enhanced-geometry", eg, []))
    return x.el("draw:custom-shape", g, kids)

func _rotation(s):
    # rotation autour du centre : ODF tourne autour de l'origine (coin) puis translate
    deg := to_float(s.rotation)
    rad := -deg * 3.141592653589793 / 180.0
    cx := to_float(s.cx) / 360000.0
    cy := to_float(s.cy) / 360000.0
    x0 := to_float(s.x) / 360000.0 + cx / 2.0
    y0 := to_float(s.y) / 360000.0 + cy / 2.0
    # point d'origine après rotation de (-cx/2, -cy/2) autour du centre
    c := _cos(rad)
    sn := _sin(rad)
    ox := x0 + (-cx / 2.0) * c + (-cy / 2.0) * sn
    oy := y0 - (-cx / 2.0) * sn + (-cy / 2.0) * c
    return "rotate (" + u.format_number(u.round_to(rad, 6)) + ") translate (" + u.format_number(u.round_to(ox, 4)) + "cm " + u.format_number(u.round_to(oy, 4)) + "cm)"

func _cos(a):
    return math.cos(a)

func _sin(a):
    return math.sin(a)

func _arrows(s):
    out := {}
    if s.head_arrow != null and s.head_arrow != "none":
        out["draw:marker-start"] = "Arrow"
        out["draw:marker-start-width"] = "0.3cm"
    if s.tail_arrow != null and s.tail_arrow != "none":
        out["draw:marker-end"] = "Arrow"
        out["draw:marker-end-width"] = "0.3cm"
    return out

func _table_node(wr, t):
    g := _geom(t)
    g["draw:layer"] = "layout"
    ncol := t.col_count()
    widths := []
    if t.col_widths != null:
        for w in t.col_widths:
            append(widths, u.length(w))
    tbl := x.el("table:table", {"table:template-name": "default", "table:use-first-row-styles": "true" if t.header else "false", "table:use-banding-rows-styles": "true" if t.banded else "false"}, [])
    c := 0
    while c < ncol:
        w := widths[c] if c < len(widths) else to_int(to_float(t.cx) / to_float(ncol if ncol > 0 else 1))
        cs := wr.bank.add("table-column", [x.el("style:table-column-properties", {"style:column-width": _cm(w)}, [])])
        append(tbl["children"], x.el("table:table-column", {"table:style-name": cs}, []))
        c = c + 1
    ri := 0
    for row in t.rows:
        rh := to_int(to_float(t.cy) / to_float(len(t.rows) if len(t.rows) > 0 else 1))
        if t.row_heights != null and ri < len(t.row_heights):
            rh = u.length(t.row_heights[ri])
        rs := wr.bank.add("table-row", [x.el("style:table-row-properties", {"style:row-height": _cm(rh)}, [])])
        r := x.el("table:table-row", {"table:style-name": rs}, [])
        ci := 0
        for cell in row:
            if cell.merged_h or cell.merged_v:
                append(r["children"], x.el("table:covered-table-cell", null, []))
                ci = ci + 1
                continue
            head := ri == 0 and t.header
            fill := cell.fill
            if fill == null:
                fill = "4472C4" if head else ("CFD5EA" if t.banded and ri % 2 == 1 else "E9EBF5")
            cp := {"fo:background-color": "#" + u.color_hex(fill), "fo:border": "0.5pt solid #FFFFFF", "fo:padding": "0.13cm"}
            if cell.valign != null:
                cp["style:vertical-align"] = "middle" if cell.valign == "middle" or cell.valign == "center" else cell.valign
            cst := wr.bank.add("table-cell", [x.el("style:graphic-properties", {"draw:fill": "solid", "draw:fill-color": "#" + u.color_hex(fill), "draw:textarea-vertical-align": "middle" if cell.valign == "middle" else "top"}, []), x.el("style:paragraph-properties", {"fo:border": "0.5pt solid #FFFFFF"}, [])])
            base := {}
            if head:
                base["bold"] = true
                base["color"] = "FFFFFF"
            if cell.bold != null:
                base["bold"] = cell.bold
            if cell.color != null:
                base["color"] = cell.color
            sz := cell.size if cell.size != null else t.font_size
            base["size"] = sz if sz != null else 18
            if t.font != null:
                base["font"] = t.font
            el := x.el("table:table-cell", {"table:style-name": cst}, wr.text_children(cell.text, base, false, cell.align))
            if cell.col_span > 1:
                el["attrs"]["table:number-columns-spanned"] = str(cell.col_span)
            if cell.row_span > 1:
                el["attrs"]["table:number-rows-spanned"] = str(cell.row_span)
            append(r["children"], el)
            ci = ci + 1
        append(tbl["children"], r)
        ri = ri + 1
    return x.el("draw:frame", g, [tbl])

func _page(wr, s, k):
    dp := {"presentation:background-visible": "true", "presentation:background-objects-visible": "true", "presentation:display-footer": "false", "presentation:display-page-number": "false", "presentation:display-date-time": "false"}
    if s.background != null:
        dp["draw:fill"] = "solid"
        dp["draw:fill-color"] = "#" + u.color_hex(s.background)
        dp["draw:background-size"] = "full"
    if s.hidden:
        dp["presentation:visibility"] = "hidden"
    ds := wr.bank.add("drawing-page", [x.el("style:drawing-page-properties", dp, [])])
    page := x.el("draw:page", {"draw:name": "page" + str(k), "draw:style-name": ds, "draw:master-page-name": "Default", "presentation:presentation-page-layout-name": _layout_name(s.layout)}, [])
    for sh in s.shapes:
        node := _shape_node(wr, sh, s)
        if node != null:
            append(page["children"], node)
    if s.notes != null and s.notes != "":
        ntf := pt.TextFrame()
        ntf.set_text(s.notes)
        nf := x.el("draw:frame", {"presentation:class": "notes", "svg:x": "2cm", "svg:y": "14cm", "svg:width": "17cm", "svg:height": "12cm", "draw:layer": "layout", "presentation:user-transformed": "true", "presentation:style-name": wr.bank.add("presentation", [x.el("style:graphic-properties", {"draw:fill": "none", "draw:stroke": "none"}, [])])}, [x.el("draw:text-box", null, wr.text_children(ntf, {"size": 12}, false))])
        append(page["children"], x.el("presentation:notes", {"draw:style-name": ds}, [x.el("draw:page-thumbnail", {"draw:layer": "layout", "svg:x": "3cm", "svg:y": "2cm", "svg:width": "15cm", "svg:height": "8.5cm", "draw:page-number": str(k), "presentation:class": "page"}, []), nf]))
    return page

func _layout_name(layout):
    return u.get({"title": "AL1T1", "title_content": "AL2T2", "title_only": "AL3T19", "section": "AL1T1", "two_content": "AL4T3", "blank": "AL5T0"}, layout, "AL2T2")

func _styles_doc(prs):
    root := odf.document_root("office:document-styles")
    append(root["children"], x.el("office:font-face-decls", null, [x.el("style:font-face", {"style:name": "Liberation Sans", "svg:font-family": "'Liberation Sans'", "style:font-family-generic": "swiss", "style:font-pitch": "variable"}, []), x.el("style:font-face", {"style:name": "OpenSymbol", "svg:font-family": "OpenSymbol", "style:font-charset": "x-symbol"}, [])]))
    major := u.get(prs.theme, "major_font", "Liberation Sans")
    minor := u.get(prs.theme, "minor_font", "Liberation Sans")
    st := x.el("office:styles", null, [])
    append(st["children"], x.el("draw:marker", {"draw:name": "Arrow", "svg:viewBox": "0 0 20 30", "svg:d": "M10 0l-10 30h20z"}, []))
    append(st["children"], x.el("style:default-style", {"style:family": "graphic"}, [x.el("style:graphic-properties", {"svg:stroke-color": "#3465A4", "draw:fill-color": "#729FCF", "fo:wrap-option": "no-wrap"}, []), x.el("style:paragraph-properties", {"style:text-autospace": "ideograph-alpha", "style:writing-mode": "lr-tb", "style:font-independent-line-spacing": "false"}, []), x.el("style:text-properties", {"style:font-name": minor, "fo:font-family": "'" + minor + "'", "fo:font-size": "18pt", "fo:language": "fr", "fo:country": "FR"}, [])]))
    append(st["children"], x.el("style:style", {"style:name": "standard", "style:family": "graphic"}, [x.el("style:graphic-properties", {"draw:stroke": "solid", "svg:stroke-width": "0cm", "svg:stroke-color": "#3465A4", "draw:fill": "solid", "draw:fill-color": "#729FCF", "fo:padding-top": "0.125cm", "fo:padding-bottom": "0.125cm", "fo:padding-left": "0.25cm", "fo:padding-right": "0.25cm"}, []), x.el("style:text-properties", {"style:font-name": minor, "fo:font-family": "'" + minor + "'", "fo:font-size": "18pt"}, [])]))
    append(root["children"], st)
    w := prs.width
    h := prs.height
    pl := x.el("style:page-layout", {"style:name": "PM1"}, [x.el("style:page-layout-properties", {"fo:margin-top": "0cm", "fo:margin-bottom": "0cm", "fo:margin-left": "0cm", "fo:margin-right": "0cm", "fo:page-width": _cm(w), "fo:page-height": _cm(h), "style:print-orientation": "landscape" if w >= h else "portrait"}, [])])
    auto := x.el("office:automatic-styles", null, [pl])
    append(auto["children"], x.el("style:style", {"style:name": "Mdp1", "style:family": "drawing-page"}, [x.el("style:drawing-page-properties", {"draw:background-size": "full", "draw:fill": "solid", "draw:fill-color": "#FFFFFF"}, [])]))
    append(auto["children"], x.el("style:style", {"style:name": "Default-title", "style:family": "presentation"}, [x.el("style:graphic-properties", {"draw:stroke": "none", "draw:fill": "none", "draw:textarea-vertical-align": "middle"}, []), x.el("style:text-properties", {"style:font-name": major, "fo:font-family": "'" + major + "'", "fo:font-size": "40pt"}, [])]))
    append(auto["children"], x.el("style:style", {"style:name": "Default-subtitle", "style:family": "presentation"}, [x.el("style:graphic-properties", {"draw:stroke": "none", "draw:fill": "none", "draw:textarea-vertical-align": "top"}, []), x.el("style:paragraph-properties", {"fo:text-align": "center"}, []), x.el("style:text-properties", {"fo:font-size": "24pt"}, [])]))
    lvl := 1
    while lvl <= 9:
        tp := {"fo:font-size": str(_LEVEL_SIZES[lvl - 1]) + "pt"}
        append(auto["children"], x.el("style:style", {"style:name": "Default-outline" + str(lvl), "style:family": "presentation", "style:parent-style-name": "Default-outline" + str(lvl - 1)} if lvl > 1 else {"style:name": "Default-outline1", "style:family": "presentation"}, [x.el("style:graphic-properties", {"draw:stroke": "none", "draw:fill": "none"}, []), x.el("style:paragraph-properties", {"fo:margin-top": "0.25cm" if lvl == 1 else "0.2cm", "fo:margin-bottom": "0cm"}, []), x.el("style:text-properties", tp, [])]))
        lvl = lvl + 1
    append(auto["children"], x.el("style:style", {"style:name": "Default-notes", "style:family": "presentation"}, [x.el("style:graphic-properties", {"draw:stroke": "none", "draw:fill": "none"}, []), x.el("style:text-properties", {"fo:font-size": "12pt"}, [])]))
    append(root["children"], auto)
    mp := x.el("style:master-page", {"style:name": "Default", "style:page-layout-name": "PM1", "draw:style-name": "Mdp1"}, [])
    append(root["children"], x.el("office:master-styles", null, [mp]))
    return root

func write(prs):
    pkg := odf.new(odf.MIME_ODP)
    pkg.metadata = prs.metadata
    wr := _Writer(pkg, prs)
    pres := x.el("office:presentation", null, [])
    k := 1
    for s in prs.slides:
        append(pres["children"], _page(wr, s, k))
        k = k + 1
    root := odf.document_root("office:document-content")
    append(root["children"], x.el("office:font-face-decls", null, [x.el("style:font-face", {"style:name": "OpenSymbol", "svg:font-family": "OpenSymbol", "style:font-charset": "x-symbol"}, [])]))
    append(root["children"], x.el("office:automatic-styles", null, wr.bank.nodes()))
    append(root["children"], x.el("office:body", null, [pres]))
    pkg.set_xml("content.xml", root)
    pkg.set_xml("styles.xml", _styles_doc(prs))
    return pkg.to_bytes()

func save(prs, path):
    io.write_bytes(path, write(prs))
    return path

# ============================================================================================== lecture

class _Reader:
    func init(pkg, idx):
        self.pkg = pkg
        self.idx = idx

    func run_fmt(name):
        return _clean(self.idx.text_fmt("text", name))

    func runs(node, fmt, out):
        for c in node["children"]:
            if type(c) == "str":
                t := _collapse(c)
                if t != "":
                    append(out, [t, fmt])
                continue
            if not x.is_element(c):
                continue
            ln := x.local_name(c["tag"])
            pf := x.prefix(c["tag"])
            if pf == "text" and ln == "s":
                append(out, [string.repeat(" ", x.attr_int(c, "text:c", 1)), fmt])
            elif ln == "tab":
                append(out, ["\t", fmt])
            elif ln == "line-break":
                append(out, ["\n", fmt])
            elif ln == "span":
                self.runs(c, u.merge(fmt, self.run_fmt(x.attr(c, "text:style-name", null))), out)
            elif ln == "a":
                self.runs(c, u.merge(fmt, {"link": x.attr(c, "xlink:href", null)}), out)
            elif ln == "page-number" or ln == "date" or ln == "time" or ln == "title":
                append(out, [x.text(c), fmt])
            elif pf == "draw" or ln == "annotation" or ln == "note" or ln == "bookmark":
                continue
            else:
                self.runs(c, fmt, out)

    func paragraph(p, level, bullet, tf):
        sn := x.attr(p, "text:style-name", null)
        pp_props := self.idx.props("paragraph", sn, "style:paragraph-properties")
        base := _clean(self.idx.text_fmt("paragraph", sn, false)) if sn != null and self.idx.is_auto("paragraph", sn) else {}
        para := tf.add_paragraph("")
        para.level = level
        para.bullet = bullet
        al := u.get(pp_props, "fo:text-align", null)
        if al != null:
            para.align = u.get({"start": "left", "left": "left", "center": "center", "end": "right", "right": "right", "justify": "justify"}, al, null)
        bs := []
        self.runs(p, {}, bs)
        merged := []
        for pair in bs:
            if len(merged) > 0 and merged[len(merged) - 1][1] == pair[1]:
                merged[len(merged) - 1][0] = merged[len(merged) - 1][0] + pair[0]
            else:
                append(merged, [pair[0], pair[1]])
        if len(merged) > 0:
            merged[0][0] = _lstrip(merged[0][0])
            last := merged[len(merged) - 1]
            last[0] = _rstrip(last[0])
        for pair in merged:
            if pair[0] == "":
                continue
            f := u.merge(base, pair[1])
            para.add_run(pair[0], f if len(keys(f)) > 0 else null)
        if len(merged) == 0 and len(keys(base)) > 0 and contains_key(base, "size"):
            para.font_size = base["size"]
        return para

    func list(node, level, tf, list_name):
        lname := x.attr(node, "text:style-name", list_name)
        for item in x.children(node):
            iln := x.local_name(item["tag"])
            if iln != "list-item" and iln != "list-header":
                continue
            for c in x.children(item):
                ln := x.local_name(c["tag"])
                if ln == "p" or ln == "h":
                    bullet := "number" if lname != null and self.idx.list_ordered(lname, level) else (false if iln == "list-header" else null)
                    self.paragraph(c, level, bullet, tf)
                elif ln == "list":
                    self.list(c, level + 1, tf, lname)

    func text_frame(box, bullets_default):
        tf := pt.TextFrame()
        for c in x.children(box):
            ln := x.local_name(c["tag"])
            if ln == "p" or ln == "h":
                self.paragraph(c, 0, false if bullets_default else null, tf)
            elif ln == "list":
                self.list(c, 0, tf, null)
        return tf

    func graphic(name, family="graphic"):
        return self.idx.props(family, name, "style:graphic-properties")

    func image_bytes(fr):
        img := x.first(fr, "draw:image")
        if img == null:
            return null
        href := x.attr(img, "xlink:href", "")
        if string.starts_with(href, "./"):
            href = _n.str_slice(href, 2, null)
        if href == "" or not self.pkg.archive.contains(href):
            return null
        return self.pkg.archive.read(href)

func _collapse(t):
    s := string.replace(string.replace(string.replace(t, "\r", " "), "\n", " "), "\t", " ")
    while string.contains(s, "  "):
        s = string.replace(s, "  ", " ")
    return s

func _lstrip(s):
    t := s
    while string.starts_with(t, " "):
        t = _n.str_slice(t, 1, null)
    return t

func _rstrip(s):
    t := s
    while string.ends_with(t, " "):
        t = _n.str_slice(t, 0, len(t) - 1)
    return t

func _clean(f):
    out := {}
    for k in keys(f):
        if f[k] != null and f[k] != false:
            out[k] = f[k]
    return out

func _xywh(node):
    return [_emu(x.attr(node, "svg:x", "0cm")), _emu(x.attr(node, "svg:y", "0cm")), _emu(x.attr(node, "svg:width", "0cm")), _emu(x.attr(node, "svg:height", "0cm"))]

func _color_of(gp, key):
    v := u.get(gp, key, null)
    if v == null or not string.starts_with(v, "#"):
        return null
    return string.upper(_n.str_slice(v, 1, null))

func _apply_graphic(s, gp):
    if u.get(gp, "draw:fill", "solid") == "none":
        s.fill = "none"
    else:
        c := _color_of(gp, "draw:fill-color")
        if c != null:
            s.fill = c
    if u.get(gp, "draw:stroke", "solid") == "none":
        s.line = "none"
    else:
        c := _color_of(gp, "svg:stroke-color")
        if c != null:
            s.line = c
        w := odf.to_pt(u.get(gp, "svg:stroke-width", null))
        if w != null and w > 0.0:
            s.line_width = u.round_to(w, 2)
        if u.get(gp, "draw:stroke", "solid") == "dash":
            s.dash = "dash"

func _rotation_of(node):
    tr := x.attr(node, "draw:transform", null)
    if tr == null:
        return null
    k := string.find(tr, "rotate")
    if k < 0:
        return null
    a := string.find(tr, "(")
    b := string.find(tr, ")")
    if a < 0 or b < a:
        return null
    rad := _n.num_parse(string.trim(_n.str_slice(tr, a + 1, b)))
    if rad == null:
        return null
    deg := -to_float(rad) * 180.0 / 3.141592653589793
    while deg < 0.0:
        deg = deg + 360.0
    # position : translate (x y) = coin d'origine tourné -> on recalcule le coin non tourné
    t2 := string.find(tr, "translate")
    pos := null
    if t2 >= 0:
        rest := _n.str_slice(tr, t2, null)
        a2 := string.find(rest, "(")
        b2 := string.find(rest, ")")
        parts := string.split(string.trim(_n.str_slice(rest, a2 + 1, b2)), " ")
        vals := []
        for p in parts:
            if string.trim(p) != "":
                append(vals, _emu(p))
        if len(vals) >= 2:
            pos = vals
    return [u.round_to(deg, 2), pos, to_float(rad)]

func _read_shape(rd, node, slide, out):
    ln := x.local_name(node["tag"])
    if ln == "g":
        for c in x.children(node):
            _read_shape(rd, c, slide, out)
        return null
    if ln == "frame":
        g := _xywh(node)
        cls := x.attr(node, "presentation:class", null)
        img := x.first(node, "draw:image")
        obj := x.first(node, "draw:object")
        tbl := x.first(node, "table:table")
        box := x.first(node, "draw:text-box")
        if obj != null:
            href := x.attr(obj, "xlink:href", "")
            if string.starts_with(href, "./"):
                href = _n.str_slice(href, 2, null)
            part := href + "/content.xml"
            if rd.pkg.archive.contains(part):
                try:
                    ch := odf.read_chart(x.parse(rd.pkg.archive.read_text(part)))
                    if ch != null:
                        sc := pch.SlideChart(ch["kind"], ch["categories"], ch["series"], g[0], g[1], g[2], g[3])
                        sc.title = ch["title"]
                        sc.stacked = ch["stacked"]
                        sc.legend = ch["legend"] if ch["legend"] != false else null
                        append(out, sc)
                        return null
                catch e:
                    errors.ignore(e)
            # repli : image de remplacement
            data := rd.image_bytes(node)
            if data != null:
                try:
                    append(out, pimg.Picture(data, g[0], g[1], g[2], g[3]))
                catch e:
                    errors.ignore(e)
            return null
        if tbl != null:
            append(out, _read_table(rd, tbl, g))
            return null
        if img != null and box == null:
            data := rd.image_bytes(node)
            if data != null:
                try:
                    p := pimg.Picture(data, g[0], g[1], g[2], g[3])
                    d := x.first(node, "svg:desc")
                    if d != null:
                        p.description = x.text(d)
                    p.name = x.attr(node, "draw:name", null)
                    append(out, p)
                catch e:
                    errors.ignore(e)
            return null
        if box != null:
            if cls == "page" or cls == "header" or cls == "footer" or cls == "date-time" or cls == "page-number":
                return null
            s := ps.Shape("textbox", g[0], g[1], g[2], g[3])
            if cls == "title":
                s.placeholder = {"type": "ctrTitle" if slide.layout == "title" else "title"}
            elif cls == "subtitle":
                s.placeholder = {"type": "subTitle", "idx": 1}
            elif cls == "outline" or cls == "text":
                s.placeholder = {"type": "body" if cls == "text" else "obj", "idx": len(out) + 1}
            if cls != null:
                s.kind = "rect"
            s.text = rd.text_frame(box, cls == "title" or cls == "subtitle" or cls == null)
            gp := rd.graphic(x.attr(node, "presentation:style-name", x.attr(node, "draw:style-name", null)), "presentation" if cls != null else "graphic")
            if cls == null:
                _apply_graphic(s, gp)
                if s.fill == null or s.fill == "4472C4":
                    if u.get(gp, "draw:fill", "none") == "none" or not contains_key(gp, "draw:fill"):
                        s.fill = null
                if not contains_key(gp, "draw:stroke") or u.get(gp, "draw:stroke", "none") == "none":
                    s.line = null
            va := u.get(gp, "draw:textarea-vertical-align", null)
            if va != null and va != "top":
                s.text.anchor = va
            s.name = x.attr(node, "draw:name", null)
            rot := _rotation_of(node)
            if rot != null:
                s.rotation = rot[0]
            append(out, s)
            # images dans le cadre de texte (cadres imbriqués)
            for fr in x.find_all(box, "draw:frame"):
                _read_shape(rd, fr, slide, out)
        return null
    if ln == "custom-shape" or ln == "rect" or ln == "ellipse" or ln == "circle" or ln == "polygon" or ln == "path" or ln == "regular-polygon":
        g := _xywh(node)
        kind := "rect"
        if ln == "custom-shape":
            eg := x.first(node, "draw:enhanced-geometry")
            kind = pptx_kind(x.attr(eg, "draw:type", "rectangle") if eg != null else "rectangle")
        elif ln == "ellipse" or ln == "circle":
            kind = "ellipse"
        s := ps.Shape(kind, g[0], g[1], g[2], g[3])
        gp := rd.graphic(x.attr(node, "draw:style-name", null))
        _apply_graphic(s, gp)
        tf := rd.text_frame(node, true)
        if len(tf.paragraphs) > 0 and tf.text() != "":
            s.text = tf
        rot := _rotation_of(node)
        if rot != null:
            s.rotation = rot[0]
        s.name = x.attr(node, "draw:name", null)
        append(out, s)
        return null
    if ln == "line" or ln == "connector":
        x1 := _emu(x.attr(node, "svg:x1", "0cm"))
        y1 := _emu(x.attr(node, "svg:y1", "0cm"))
        x2 := _emu(x.attr(node, "svg:x2", "0cm"))
        y2 := _emu(x.attr(node, "svg:y2", "0cm"))
        s := ps.line(x1, y1, x2, y2)
        gp := rd.graphic(x.attr(node, "draw:style-name", null))
        c := _color_of(gp, "svg:stroke-color")
        if c != null:
            s.line = c
        w := odf.to_pt(u.get(gp, "svg:stroke-width", null))
        if w != null and w > 0.0:
            s.line_width = u.round_to(w, 2)
        if u.get(gp, "draw:marker-end", null) != null:
            s.tail_arrow = "triangle"
        if u.get(gp, "draw:marker-start", null) != null:
            s.head_arrow = "triangle"
        append(out, s)
        return null
    return null

func _read_table(rd, tbl, g):
    grid := []
    for row in x.find_all(tbl, "table:table-row"):
        line := []
        for cell in x.children(row):
            cln := x.local_name(cell["tag"])
            if cln != "table-cell" and cln != "covered-table-cell":
                continue
            append(line, [cln, cell])
        append(grid, line)
    rows := []
    for line in grid:
        r := []
        for pair in line:
            append(r, "" if pair[0] == "covered-table-cell" else _cell_plain(pair[1]))
        append(rows, r)
    t := ptb.SlideTable(rows, g[0], g[1], g[2], g[3])
    t.header = x.attr(tbl, "table:use-first-row-styles", "false") == "true"
    t.banded = x.attr(tbl, "table:use-banding-rows-styles", "false") == "true"
    ri := 0
    for line in grid:
        ci := 0
        for pair in line:
            cell := pair[1]
            if pair[0] == "table-cell" and ri < len(t.rows) and ci < len(t.rows[ri]):
                tc := t.rows[ri][ci]
                tf := rd.text_frame(cell, true)
                if len(tf.paragraphs) > 0:
                    tc.text = tf
                cst := x.attr(cell, "table:style-name", null)
                gp := rd.graphic(cst, "table-cell")
                col := _color_of(gp, "draw:fill-color")
                if col == null:
                    cp := rd.idx.props("table-cell", cst, "style:table-cell-properties")
                    col = _color_of(cp, "fo:background-color")
                if col != null:
                    tc.fill = col
                cs := x.attr_int(cell, "table:number-columns-spanned", 1)
                rsn := x.attr_int(cell, "table:number-rows-spanned", 1)
                if cs > 1 or rsn > 1:
                    t.merge(ri, ci, ri + rsn - 1, ci + cs - 1)
            ci = ci + 1
        ri = ri + 1
    return t

func _cell_plain(cell):
    parts := []
    for p in x.find_all(cell, "text:p"):
        append(parts, odf.node_text(p))
    return string.join("\n", parts)

func _guess_layout(shapes):
    has_title := false
    has_sub := false
    bodies := 0
    for s in shapes:
        if isinstance(s, ps.Shape) and s.placeholder != null:
            t := u.get(s.placeholder, "type", "")
            if t == "title" or t == "ctrTitle":
                has_title = true
            elif t == "subTitle":
                has_sub = true
            else:
                bodies = bodies + 1
    if has_title and has_sub:
        return "title"
    if has_title and bodies >= 2:
        return "two_content"
    if has_title and bodies == 1:
        return "title_content"
    if has_title:
        return "title_only"
    return "blank"

func read(src):
    pkg := src if isinstance(src, odf.OdfPackage) else odf.open(src)
    root := pkg.content()
    if root == null:
        errors.fail(errors.ODF, "content.xml absent")
    body := x.first(root, "office:body")
    pres := x.first(body, "office:presentation") if body != null else null
    if pres == null:
        pres = x.first(body, "office:drawing") if body != null else null
    if pres == null:
        errors.fail(errors.ODF, "pas une présentation OpenDocument (office:presentation absent)")
    styles := pkg.styles()
    idx := odf.StyleIndex([styles, root])
    rd := _Reader(pkg, idx)
    prs := pp.new()
    prs.metadata = pkg.metadata
    # taille de page : mise en page du masque
    for name in keys(idx.page_layouts):
        plp := x.first(idx.page_layouts[name], "style:page-layout-properties")
        if plp != null and x.attr(plp, "fo:page-width", null) != null:
            prs.width = _emu(x.attr(plp, "fo:page-width", null), prs.width)
            prs.height = _emu(x.attr(plp, "fo:page-height", null), prs.height)
            break
    for page in x.children(pres, "draw:page"):
        shapes := []
        for c in x.children(page):
            if x.local_name(c["tag"]) == "notes" or x.local_name(c["tag"]) == "forms":
                continue
            _read_shape(rd, c, sl.Slide("blank", prs.width, prs.height), shapes)
        layout := _guess_layout(shapes)
        s := sl.Slide(layout, prs.width, prs.height)
        for sh in shapes:
            if isinstance(sh, ps.Shape) and sh.placeholder != null and layout == "title" and u.get(sh.placeholder, "type", "") == "title":
                sh.placeholder["type"] = "ctrTitle"
            append(s.shapes, sh)
        dp := idx.props("drawing-page", x.attr(page, "draw:style-name", null), "style:drawing-page-properties")
        if u.get(dp, "draw:fill", "none") == "solid":
            bg := _color_of(dp, "draw:fill-color")
            if bg != null:
                s.background = bg
        if u.get(dp, "presentation:visibility", "visible") == "hidden":
            s.hidden = true
        notes := x.first(page, "presentation:notes")
        if notes != null:
            for fr in x.children(notes, "draw:frame"):
                if x.attr(fr, "presentation:class", "") == "notes":
                    parts := []
                    for p in x.find_all(fr, "text:p"):
                        append(parts, odf.node_text(p))
                    t := string.trim(string.join("\n", parts))
                    if t != "":
                        s.notes = t
        append(prs.slides, s)
    return prs

func read_text(src, notes=true):
    return read(src).text(notes)
