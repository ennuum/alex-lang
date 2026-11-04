# ALEX STANDARD LIBRARY — office.pptx_slides
# Diapositives : disposition, formes, titre, listes à puces, zones de texte, images, tableaux, graphiques, fond,
# notes du présentateur ; sérialisation (ppt/slides/slideN.xml) et lecture.
#
#   use office.pptx_slides as sl
#   s := sl.Slide("title_content", 12192000, 6858000)
#   s.add_title("Résultats")
#   s.add_bullets(["Hausse de 12 %", ["dont export : 8 %"], "Marge stable"])
#   s.add_image("graph.png", "14cm", "5cm", "10cm")
#   s.notes = "Insister sur l'export."
#
# Slide(layout="title_content", width=12192000, height=6858000) : layout ("title" | "title_content" |
#   "title_only" | "section" | "two_content" | "blank")  shapes  background (couleur)  notes  hidden  width height
#   add(forme) -> forme   remove(forme)   add_title(texte, fmt=null)   add_subtitle(texte, fmt=null)
#   add_bullets(items, fmt=null, box=null) (items : textes et sous-listes ; box = [x, y, cx, cy] facultatif)
#   add_text(texte, x, y, cx, cy, fmt=null)   add_shape(kind, x, y, cx, cy, texte=null, fill=null)
#   add_line(x1, y1, x2, y2, color="000000", width=1.0)   add_image(image, x=null, y=null, cx=null, cy=null)
#   (sans position : centrée dans la zone de contenu, ajustée)   add_table(lignes, x=null, y=null, cx=null, cy=null)
#   add_chart(kind, categories, series, x=null, y=null, cx=null, cy=null, title=null)
#   title() -> texte du titre   texts() -> textes de toutes les formes   text() (tout le texte, une ligne par forme)
#   images()  tables()  charts()  find(texte) -> formes
# Fonctions : layout_boxes(largeur, hauteur) -> dict nom -> [x, y, cx, cy]   slide_xml(slide, ctx) -> nœud p:sld
#   parse_slide(nœud, rctx) -> Slide   LAYOUTS (noms)
# Erreurs : ValueError (disposition inconnue), PPTXError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.pptx_text as pt
use office.pptx_shapes as ps
use office.pptx_images as pimg
use office.pptx_tables as ptb
use office.pptx_charts as pch
use office.xlsx_charts as xch

const LAYOUTS := ["title", "title_content", "title_only", "section", "two_content", "blank"]

# Zones des dispositions (proportions de la diapositive 16:9 de PowerPoint, mises à l'échelle).
func layout_boxes(w, h):
    fx := (v) => to_int(to_float(v) * to_float(w) / 12192000.0)
    fy := (v) => to_int(to_float(v) * to_float(h) / 6858000.0)
    return {"title": [fx(838200), fy(365125), fx(10515600), fy(1325563)], "body": [fx(838200), fy(1825625), fx(10515600), fy(4351338)], "ctr_title": [fx(1524000), fy(1122363), fx(9144000), fy(2387600)], "subtitle": [fx(1524000), fy(3602038), fx(9144000), fy(1655762)], "section_title": [fx(831850), fy(1709738), fx(10515600), fy(2852737)], "section_text": [fx(831850), fy(4589463), fx(10515600), fy(1500187)], "left": [fx(838200), fy(1825625), fx(5181600), fy(4351338)], "right": [fx(6172200), fy(1825625), fx(5181600), fy(4351338)]}

func _is_title_ph(s):
    return isinstance(s, ps.Shape) and s.placeholder != null and (u.get(s.placeholder, "type", "") == "title" or u.get(s.placeholder, "type", "") == "ctrTitle")

class Slide:
    func init(layout="title_content", width=12192000, height=6858000):
        ok := false
        for l in LAYOUTS:
            if l == layout:
                ok = true
        if not ok:
            raise("ValueError", "disposition inconnue : '" + u.to_text(layout) + "' (title, title_content, title_only, section, two_content, blank)")
        self.layout = layout
        self.shapes = []
        self.background = null
        self.notes = null
        self.hidden = false
        self.width = width
        self.height = height
        self._body_count = 0

    func boxes():
        return layout_boxes(self.width, self.height)

    func add(shape):
        append(self.shapes, shape)
        return shape

    func remove(shape):
        out := []
        found := false
        for s in self.shapes:
            if not found and _n.same(s, shape):
                found = true
            else:
                append(out, s)
        self.shapes = out
        return found

    func add_title(text, fmt=null):
        b := self.boxes()
        kind := "title"
        box := b["title"]
        if self.layout == "title":
            kind = "ctrTitle"
            box = b["ctr_title"]
        elif self.layout == "section":
            box = b["section_title"]
        s := ps.Shape("rect", box[0], box[1], box[2], box[3])
        s.placeholder = {"type": kind}
        s.set_text(text, fmt)
        return self.add(s)

    func add_subtitle(text, fmt=null):
        b := self.boxes()
        box := b["subtitle"] if self.layout != "section" else b["section_text"]
        s := ps.Shape("rect", box[0], box[1], box[2], box[3])
        s.placeholder = {"type": "subTitle" if self.layout == "title" else "body", "idx": 1}
        s.set_text(text, fmt)
        return self.add(s)

    func _fill_bullets(tf, items, level, fmt):
        for it in items:
            if type(it) == "list" or type(it) == "tuple":
                self._fill_bullets(tf, it, level + 1, fmt)
            else:
                p := tf.add_paragraph(u.to_text(it), fmt)
                p.level = level
        return tf

    func add_bullets(items, fmt=null, box=null):
        b := self.boxes()
        bx := box
        if bx == null:
            if self.layout == "two_content":
                bx = b["left"] if self._body_count == 0 else b["right"]
            else:
                bx = b["body"]
        else:
            bx = [u.length(box[0]), u.length(box[1]), u.length(box[2]), u.length(box[3])]
        s := ps.Shape("rect", bx[0], bx[1], bx[2], bx[3])
        self._body_count = self._body_count + 1
        s.placeholder = {"type": "obj", "idx": self._body_count}
        tf := pt.TextFrame()
        self._fill_bullets(tf, items, 0, fmt)
        s.text = tf
        return self.add(s)

    func add_text(text, x0, y0, cx, cy, fmt=null):
        return self.add(ps.textbox(text, x0, y0, cx, cy, fmt))

    func add_shape(kind, x0, y0, cx, cy, text=null, fill=null):
        s := ps.Shape(kind, x0, y0, cx, cy)
        if text != null:
            s.set_text(text)
        if fill != null:
            s.fill = fill
        return self.add(s)

    func add_line(x1, y1, x2, y2, color="000000", width=1.0):
        return self.add(ps.line(x1, y1, x2, y2, color, width))

    func _content_box():
        b := self.boxes()
        if self.layout == "blank":
            return [to_int(to_float(self.width) * 0.05), to_int(to_float(self.height) * 0.05), to_int(to_float(self.width) * 0.9), to_int(to_float(self.height) * 0.9)]
        return b["body"]

    func add_image(image, x0=null, y0=null, cx=null, cy=null):
        if x0 == null and y0 == null and cx == null and cy == null:
            box := self._content_box()
            sz := pimg.fit(image, box[2], box[3])
            nat := pimg.Picture(image)
            natsz := [nat.cx, nat.cy]
            if natsz[0] <= box[2] and natsz[1] <= box[3]:
                sz = natsz
            p := pimg.Picture(image, box[0] + (box[2] - sz[0]) // 2, box[1] + (box[3] - sz[1]) // 2, sz[0], sz[1])
            return self.add(p)
        return self.add(pimg.Picture(image, x0 if x0 != null else 0, y0 if y0 != null else 0, cx, cy))

    func add_table(rows, x0=null, y0=null, cx=null, cy=null):
        box := self._content_box()
        t := ptb.SlideTable(rows, x0 if x0 != null else box[0], y0 if y0 != null else box[1], cx if cx != null else box[2], cy)
        return self.add(t)

    func add_chart(kind, categories, series, x0=null, y0=null, cx=null, cy=null, title=null):
        box := self._content_box()
        c := pch.SlideChart(kind, categories, series, x0 if x0 != null else box[0], y0 if y0 != null else box[1], cx if cx != null else box[2], cy if cy != null else box[3])
        c.title = title
        return self.add(c)

    # ---------------------------------------------------------- lecture
    func title():
        for s in self.shapes:
            if _is_title_ph(s):
                return s.text_content()
        return ""

    func texts():
        out := []
        for s in self.shapes:
            if isinstance(s, ps.Shape):
                t := s.text_content()
                if t != "":
                    append(out, t)
            elif isinstance(s, ptb.SlideTable):
                for row in s.data():
                    append(out, string.join("\t", row))
        return out

    func text():
        return string.join("\n", self.texts())

    func images():
        out := []
        for s in self.shapes:
            if isinstance(s, pimg.Picture):
                append(out, s)
        return out

    func tables():
        out := []
        for s in self.shapes:
            if isinstance(s, ptb.SlideTable):
                append(out, s)
        return out

    func charts():
        out := []
        for s in self.shapes:
            if isinstance(s, pch.SlideChart):
                append(out, s)
        return out

    func find(text):
        out := []
        for s in self.shapes:
            if isinstance(s, ps.Shape) and string.contains(s.text_content(), text):
                append(out, s)
        return out

    func replace(old, new_text):
        n := 0
        for s in self.shapes:
            frames := []
            if isinstance(s, ps.Shape) and s.text != null:
                append(frames, s.text)
            elif isinstance(s, ptb.SlideTable):
                for row in s.rows:
                    for c in row:
                        append(frames, c.text)
            for tf in frames:
                for p in tf.paragraphs:
                    for r in p.runs:
                        if string.contains(r.text, old):
                            n = n + string.count(r.text, old)
                            r.text = string.replace(r.text, old, new_text)
        return n

# ---------------------------------------------------------------------------------------------- écriture

func slide_xml(slide, ctx):
    tree := [x.el("p:nvGrpSpPr", null, [x.el("p:cNvPr", {"id": "1", "name": ""}), x.el("p:cNvGrpSpPr"), x.el("p:nvPr")]), x.el("p:grpSpPr", null, [x.el("a:xfrm", null, [x.el("a:off", {"x": "0", "y": "0"}), x.el("a:ext", {"cx": "0", "cy": "0"}), x.el("a:chOff", {"x": "0", "y": "0"}), x.el("a:chExt", {"cx": "0", "cy": "0"})])])]
    ident := 2
    for s in slide.shapes:
        append(tree, s.to_xml(ctx, ident))
        ident = ident + 1
    csld := []
    if slide.background != null:
        append(csld, x.el("p:bg", null, [x.el("p:bgPr", null, [ps.fill_xml(slide.background), x.el("a:effectLst")])]))
    append(csld, x.el("p:spTree", null, tree))
    attrs := {"xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"], "xmlns:p": x.NS["p"]}
    if slide.hidden:
        attrs["show"] = "0"
    return x.el("p:sld", attrs, [x.el("p:cSld", null, csld), x.el("p:clrMapOvr", null, [x.el("a:masterClrMapping")])])

# ---------------------------------------------------------------------------------------------- lecture

func _transform(s, g):
    # g : [off_x, off_y, ext_cx, ext_cy, ch_x, ch_y, ch_cx, ch_cy]
    sx := to_float(g[2]) / to_float(g[6]) if g[6] > 0 else 1.0
    sy := to_float(g[3]) / to_float(g[7]) if g[7] > 0 else 1.0
    s.x = g[0] + to_int(to_float(s.x - g[4]) * sx)
    s.y = g[1] + to_int(to_float(s.y - g[5]) * sy)
    s.cx = to_int(to_float(s.cx) * sx)
    s.cy = to_int(to_float(s.cy) * sy)

func _read_tree(tree, rctx, out, group):
    for c in x.children(tree):
        ln := x.local_name(c["tag"])
        shape := null
        if ln == "sp" or ln == "cxnSp":
            shape = ps.parse_shape(c, rctx.link)
        elif ln == "pic":
            shape = pimg.parse_picture(c, rctx.link, rctx.image)
        elif ln == "graphicFrame":
            gd := x.find(c, "a:graphicData")
            uri := x.attr(gd, "uri", "") if gd != null else ""
            if string.ends_with(uri, "/table"):
                shape = ptb.parse_table(c, rctx.link)
            elif string.ends_with(uri, "/chart"):
                ch := x.find(c, "c:chart")
                if ch != null:
                    chart := rctx.chart(x.attr(ch, "r:id", ""))
                    if chart != null:
                        shape = pch.from_chart(chart)
                        xf := ps.read_xfrm(x.first(c, "p:xfrm"))
                        shape.x = xf[0]
                        shape.y = xf[1]
                        shape.cx = xf[2]
                        shape.cy = xf[3]
        elif ln == "grpSp":
            gpr := x.first(c, "p:grpSpPr")
            xf := x.first(gpr, "a:xfrm") if gpr != null else null
            g := null
            if xf != null:
                off := x.first(xf, "a:off")
                ext := x.first(xf, "a:ext")
                cho := x.first(xf, "a:chOff")
                che := x.first(xf, "a:chExt")
                g = [x.attr_int(off, "x", 0), x.attr_int(off, "y", 0), x.attr_int(ext, "cx", 0), x.attr_int(ext, "cy", 0), x.attr_int(cho, "x", 0), x.attr_int(cho, "y", 0), x.attr_int(che, "cx", 0), x.attr_int(che, "cy", 0)]
            sub := []
            _read_tree(c, rctx, sub, null)
            for s in sub:
                if g != null:
                    _transform(s, g)
                append(out, s)
            continue
        elif ln == "AlternateContent":
            fb := x.first(c, "mc:Fallback")
            if fb != null:
                _read_tree(fb, rctx, out, group)
            continue
        if shape != null:
            if isinstance(shape, ps.Shape) and shape.placeholder != null and shape.cx == 0 and shape.cy == 0:
                box := rctx.placeholder_box(u.get(shape.placeholder, "type", null), u.get(shape.placeholder, "idx", null))
                if box != null:
                    shape.x = box[0]
                    shape.y = box[1]
                    shape.cx = box[2]
                    shape.cy = box[3]
            append(out, shape)

func parse_slide(root, rctx, layout="title_content", width=12192000, height=6858000):
    s := Slide(layout, width, height)
    s.hidden = x.attr(root, "show", "1") == "0"
    csld := x.first(root, "p:cSld")
    if csld == null:
        return s
    bg := x.first(csld, "p:bg")
    if bg != null:
        c := x.find(bg, "a:srgbClr")
        if c != null:
            s.background = x.attr(c, "val", null)
    tree := x.first(csld, "p:spTree")
    if tree != null:
        _read_tree(tree, rctx, s.shapes, null)
    return s
