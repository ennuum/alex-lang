# ALEX STANDARD LIBRARY — office.pptx_shapes
# Formes des diapositives (PresentationML / DrawingML) : formes prédéfinies (rectangle, ellipse, flèches, étoiles...),
# zones de texte, espaces réservés (titre, corps), connecteurs (lignes), remplissage, contour, rotation, lien au clic.
#
#   use office.pptx_shapes as ps
#   s := ps.Shape("roundRect", "2cm", "3cm", "8cm", "3cm")
#   s.fill = "4472C4"
#   s.line = "none"
#   s.set_text("Étape 1", {"bold": true, "color": "FFFFFF", "size": 20})
#   slide.add(s)                                         # voir pptx_slides.Slide
#
# Shape(kind="rect", x=0, y=0, cx=914400, cy=914400) : kind (préréglage DrawingML : rect roundRect ellipse triangle
#   rtTriangle diamond parallelogram trapezoid pentagon hexagon octagon star5 star6 rightArrow leftArrow upArrow
#   downArrow leftRightArrow chevron homePlate plus heart cloud can cube donut smileyFace wedgeRectCallout ... ;
#   "textbox" zone de texte sans fond ; "line" connecteur)  x y cx cy (EMU ; longueurs « 2cm » acceptées à la
#   création et par move / resize)  rotation (degrés)  flip_h flip_v  fill (couleur, "none", null = thème)
#   line (couleur, "none", null = thème)  line_width (pt)  dash ("solid" "dash" "dot" "dashDot" "lgDash"...)
#   head_arrow / tail_arrow (connecteur : "triangle" "arrow" "stealth" "oval")  text (pptx_text.TextFrame ou null)
#   placeholder (null ou {"type": "title" | "ctrTitle" | "subTitle" | "body" | "obj" ..., "idx": n})  name  link
#   set_text(texte, fmt=null) -> TextFrame   text_content()   move(x, y)   resize(cx, cy)   bounds() -> [x, y, cx, cy]
# Fonctions : textbox(texte, x, y, cx, cy, fmt=null) -> Shape   line(x1, y1, x2, y2, color="000000", width=1.0)
#   xfrm_xml(x, y, cx, cy, rot=0, flip_h=false, flip_v=false, tag="a:xfrm")   read_xfrm(nœud) -> [x, y, cx, cy, rot]
#   fill_xml(couleur)   line_xml(couleur, largeur, dash)   parse_shape(nœud_p:sp ou p:cxnSp, rels) -> Shape
# Erreurs : ValueError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.utils as u
use office.xml as x
use office.pptx_text as pt

func _emu(v):
    if v == null:
        return 0
    return u.length(v)

class Shape:
    func init(kind="rect", x0=0, y0=0, cx=914400, cy=914400):
        self.kind = kind
        self.x = _emu(x0)
        self.y = _emu(y0)
        self.cx = _emu(cx)
        self.cy = _emu(cy)
        self.rotation = 0
        self.flip_h = false
        self.flip_v = false
        self.fill = null
        self.line = null
        self.line_width = null
        self.dash = null
        self.head_arrow = null
        self.tail_arrow = null
        self.text = null
        self.placeholder = null
        self.name = null
        self.link = null
        self.shadow = false

    func set_text(text, fmt=null):
        tf := pt.TextFrame()
        for line in string.split(string.replace(u.to_text(text), "\r\n", "\n"), "\n"):
            tf.add_paragraph(line, fmt)
        self.text = tf
        return tf

    func text_content():
        if self.text == null:
            return ""
        return self.text.text()

    func move(x0, y0):
        self.x = _emu(x0)
        self.y = _emu(y0)
        return self

    func resize(cx, cy):
        self.cx = _emu(cx)
        self.cy = _emu(cy)
        return self

    func bounds():
        return [self.x, self.y, self.cx, self.cy]

    func to_xml(ctx, ident):
        nm := self.name if self.name != null else ("Titre " + str(ident) if self.placeholder != null and string.contains(u.get(self.placeholder, "type", ""), "itle") else ("Connecteur " + str(ident) if self.kind == "line" else ("ZoneTexte " + str(ident) if self.kind == "textbox" else "Forme " + str(ident))))
        cnv := x.el("p:cNvPr", {"id": str(ident), "name": nm}, [x.el("a:hlinkClick", {"r:id": ctx.link_rel(self.link)})] if self.link != null else [])
        if self.kind == "line":
            sp := [x.el("p:nvCxnSpPr", null, [cnv, x.el("p:cNvCxnSpPr"), x.el("p:nvPr")])]
            sppr := [xfrm_xml(self.x, self.y, self.cx, self.cy, self.rotation, self.flip_h, self.flip_v), x.el("a:prstGeom", {"prst": "line"}, [x.el("a:avLst")])]
            append(sppr, line_xml(self.line if self.line != null else "000000", self.line_width if self.line_width != null else 1.0, self.dash, self.head_arrow, self.tail_arrow))
            append(sp, x.el("p:spPr", null, sppr))
            return x.el("p:cxnSp", null, sp)
        nvpr := []
        if self.placeholder != null:
            pa := {}
            t := u.get(self.placeholder, "type", null)
            if t != null and t != "obj":
                pa["type"] = t
            idx := u.get(self.placeholder, "idx", null)
            if idx != null:
                pa["idx"] = str(idx)
            append(nvpr, x.el("p:ph", pa))
        cnvsp := x.el("p:cNvSpPr", {"txBox": "1"} if self.kind == "textbox" else null, [x.el("a:spLocks", {"noGrp": "1"})] if self.placeholder != null else [])
        kids := [x.el("p:nvSpPr", null, [cnv, cnvsp, x.el("p:nvPr", null, nvpr)])]
        sppr := [xfrm_xml(self.x, self.y, self.cx, self.cy, self.rotation, self.flip_h, self.flip_v)]
        if self.placeholder == null:
            prst := "rect" if self.kind == "textbox" else self.kind
            append(sppr, x.el("a:prstGeom", {"prst": prst}, [x.el("a:avLst")]))
            if self.kind == "textbox":
                append(sppr, fill_xml(self.fill if self.fill != null else "none"))
                if self.line != null:
                    append(sppr, line_xml(self.line, self.line_width, self.dash))
            else:
                if self.fill != null:
                    append(sppr, fill_xml(self.fill))
                if self.line != null or self.line_width != null or self.dash != null:
                    append(sppr, line_xml(self.line, self.line_width, self.dash))
        else:
            if self.fill != null:
                append(sppr, fill_xml(self.fill))
            if self.line != null:
                append(sppr, line_xml(self.line, self.line_width, self.dash))
        append(kids, x.el("p:spPr", null, sppr))
        if self.placeholder == null and self.kind != "textbox":
            # style de thème : forme pleine accentuée, texte clair (aspect par défaut de PowerPoint)
            append(kids, x.el("p:style", null, [x.el("a:lnRef", {"idx": "2"}, [x.el("a:schemeClr", {"val": "accent1"}, [x.el("a:shade", {"val": "50000"})])]), x.el("a:fillRef", {"idx": "1"}, [x.el("a:schemeClr", {"val": "accent1"})]), x.el("a:effectRef", {"idx": "0"}, [x.el("a:schemeClr", {"val": "accent1"})]), x.el("a:fontRef", {"idx": "minor"}, [x.el("a:schemeClr", {"val": "lt1"})])]))
        tf := self.text
        if tf == null:
            tf = pt.TextFrame()
            if self.kind != "textbox" and self.placeholder == null:
                tf.anchor = "middle"
        elif self.kind != "textbox" and self.placeholder == null and tf.anchor == null:
            tf.anchor = "middle"
        if self.placeholder == null and self.kind != "textbox":
            for p in tf.paragraphs:
                if p.align == null:
                    p.align = "center"
        append(kids, pt.txbody_xml(tf, "p:txBody", ctx))
        return x.el("p:sp", null, kids)

func textbox(text, x0, y0, cx, cy, fmt=null):
    s := Shape("textbox", x0, y0, cx, cy)
    s.set_text(text, fmt)
    return s

func line(x1, y1, x2, y2, color="000000", width=1.0):
    a := _emu(x1)
    b := _emu(y1)
    c := _emu(x2)
    d := _emu(y2)
    s := Shape("line", a if a < c else c, b if b < d else d, c - a if c > a else a - c, d - b if d > b else b - d)
    s.flip_h = c < a
    s.flip_v = d < b
    s.line = color
    s.line_width = width
    return s

func xfrm_xml(x0, y0, cx, cy, rot=0, flip_h=false, flip_v=false, tag="a:xfrm"):
    attrs := {}
    if rot != null and rot != 0:
        attrs["rot"] = str(to_int(u.round_to(to_float(rot) * 60000.0, 0)))
    if flip_h:
        attrs["flipH"] = "1"
    if flip_v:
        attrs["flipV"] = "1"
    return x.el(tag, attrs, [x.el("a:off", {"x": str(to_int(x0)), "y": str(to_int(y0))}), x.el("a:ext", {"cx": str(to_int(cx)), "cy": str(to_int(cy))})])

func fill_xml(color):
    if color == "none" or color == false:
        return x.el("a:noFill")
    return x.el("a:solidFill", null, [x.el("a:srgbClr", {"val": u.color_hex(color)})])

func line_xml(color, width=null, dash=null, head=null, tail=null):
    attrs := {}
    if width != null:
        attrs["w"] = str(u.pt_to_emu(width))
    kids := []
    if color == "none" or color == false:
        append(kids, x.el("a:noFill"))
    elif color != null:
        append(kids, x.el("a:solidFill", null, [x.el("a:srgbClr", {"val": u.color_hex(color)})]))
    if dash != null:
        append(kids, x.el("a:prstDash", {"val": dash}))
    if head != null:
        append(kids, x.el("a:headEnd", {"type": head}))
    if tail != null:
        append(kids, x.el("a:tailEnd", {"type": tail}))
    return x.el("a:ln", attrs, kids)

func read_xfrm(el):
    if el == null:
        return [0, 0, 0, 0, 0]
    off := x.first(el, "a:off")
    ext := x.first(el, "a:ext")
    return [x.attr_int(off, "x", 0), x.attr_int(off, "y", 0), x.attr_int(ext, "cx", 0), x.attr_int(ext, "cy", 0), to_float(x.attr_int(el, "rot", 0)) / 60000.0]

func _color_of(el):
    if el == null:
        return null
    sf := x.first(el, "a:solidFill")
    if sf != null:
        c := x.first(sf, "a:srgbClr")
        if c != null:
            return string.upper(x.attr(c, "val", "000000"))
        return null
    if x.first(el, "a:noFill") != null:
        return "none"
    return null

func parse_shape(el, rels=null):
    ln := x.local_name(el["tag"])
    s := Shape("rect")
    nv := x.first(el, "p:nvSpPr") if ln == "sp" else x.first(el, "p:nvCxnSpPr")
    if nv != null:
        cnv := x.first(nv, "p:cNvPr")
        s.name = x.attr(cnv, "name", null)
        hl := x.first(cnv, "a:hlinkClick")
        if hl != null and rels != null:
            s.link = rels(x.attr(hl, "r:id", ""))
        csp := x.first(nv, "p:cNvSpPr")
        if csp != null and x.attr_bool(csp, "txBox", false):
            s.kind = "textbox"
        nvpr := x.first(nv, "p:nvPr")
        ph := x.first(nvpr, "p:ph") if nvpr != null else null
        if ph != null:
            s.placeholder = {"type": x.attr(ph, "type", "obj"), "idx": x.attr_int(ph, "idx", null)}
    sppr := x.first(el, "p:spPr")
    if sppr != null:
        xf := read_xfrm(x.first(sppr, "a:xfrm"))
        s.x = xf[0]
        s.y = xf[1]
        s.cx = xf[2]
        s.cy = xf[3]
        s.rotation = xf[4]
        xe := x.first(sppr, "a:xfrm")
        if xe != null:
            s.flip_h = x.attr_bool(xe, "flipH", false)
            s.flip_v = x.attr_bool(xe, "flipV", false)
        geom := x.first(sppr, "a:prstGeom")
        if geom != null and s.kind != "textbox":
            s.kind = x.attr(geom, "prst", "rect")
        elif x.first(sppr, "a:custGeom") != null and s.kind != "textbox":
            s.kind = "custom"
        s.fill = _color_of(sppr)
        lne := x.first(sppr, "a:ln")
        if lne != null:
            s.line = _color_of(lne)
            w := x.attr_int(lne, "w", null)
            if w != null:
                s.line_width = u.emu_to_pt(w)
            pd := x.first(lne, "a:prstDash")
            if pd != null:
                s.dash = x.attr(pd, "val", null)
    if ln == "cxnSp":
        s.kind = "line"
    tb := x.first(el, "p:txBody")
    if tb != null:
        s.text = pt.parse_txbody(tb, rels)
    return s
