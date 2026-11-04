# ALEX STANDARD LIBRARY — office.presentation
# Présentations, tous formats confondus, autour du modèle d'office.powerpoint (Presentation / Slide / Shape...) :
# ouverture de PPTX, ODP et Markdown ; enregistrement en PPTX, ODP, PDF (rendu vectoriel de chaque diapositive :
# textes, puces, formes, images, tableaux, graphiques), HTML (une image SVG fidèle par diapositive, notes comprises),
# Markdown et texte ; passage document <-> diaporama (un titre = une diapositive).
#
#   use office.presentation as pres
#   p := pres.from_markdown("# Bilan 2026\nDirection financière\n\n## Points clés\n- Croissance\n  - Export\n- Usine")
#   pres.save(p, "bilan.pptx")                     # ou .odp .pdf .html .md .txt
#   pres.convert("cours.odp", "cours.pdf")
#   print(pres.to_markdown(pres.open("cours.pptx")))
#
# OUVRIR      open(src, format=null) -> powerpoint.Presentation  (format : "pptx" "odp" "md" ; null : détecté)
# ENREGISTRER save(p, chemin, format=null, options=null) -> chemin   to_bytes(p, format, options=null)
#             convert(src, dst, options=null) -> dst
# EXPORTS     to_pdf(p, options=null) -> octets ({"notes": false} : page de notes après chaque diapositive)
#             to_html(p, options=null) -> str (SVG par diapositive)  to_svg(diapositive, options=null) -> str
#             to_markdown(p, notes=true)  to_text(p, notes=true)
# DOCUMENTS   from_markdown(md, widescreen=true)  from_document(document.Document, widescreen=true)
#             to_document(p, notes=true) -> document.Document
#             (« # » en tête : diapositive de titre ; « ## » ou « # » : nouvelle diapositive ; « --- » : coupure ;
#             listes -> puces ; tableaux, images, code -> diapositives dédiées si besoin ; « > Notes : ... » -> notes)
# RENDU       render_slide(diapositive) -> {"width", "height", "background", "items"} (primitives en points, origine en
#             haut à gauche : rect ellipse poly line text image link) — utilisé par to_pdf et to_svg
# Erreurs : FormatError, ConversionError, PPTXError, ODFError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use math
use office.errors as errors
use office.utils as u
use office.core as core
use office.html as ohtml
use office.powerpoint as pp
use office.pptx_slides as sl
use office.pptx_shapes as ps
use office.pptx_text as pt
use office.pptx_images as pimg
use office.pptx_tables as ptb
use office.pptx_charts as pch
use office.pdf_writer as pw
use office.odp as odp
use office.document as document

const FORMATS := {"read": ["pptx", "odp", "md"], "write": ["pptx", "odp", "pdf", "html", "md", "txt"]}
const _LEVEL_SIZES := [28.0, 24.0, 20.0, 18.0, 18.0, 18.0, 18.0, 18.0, 18.0]
const _BULLETS := ["•", "–", "•", "–", "•", "–", "•", "–", "•"]
const _ACCENT := "4472C4"
const _COLORS := ["4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47", "264478", "9E480E", "636363", "997300"]

func _pt(emu):
    return to_float(emu) / 12700.0

func format_of(path):
    ext := string.lower(core.extension_of(path))
    if ext == "markdown":
        return "md"
    if ext == "text":
        return "txt"
    if ext == "htm":
        return "html"
    if ext == "potx" or ext == "pptm" or ext == "ppsx":
        return "pptx"
    if ext == "otp":
        return "odp"
    return ext

# ============================================================================================== ouverture

func open(src, format=null):
    f := format
    if f == null and type(src) == "str" and (format_of(src) == "md" or format_of(src) == "txt"):
        f = "md"
    if f == null:
        f = core.detect_format(src)
    if f == "pptx":
        return pp.open(src)
    if f == "odp":
        return odp.read(src)
    if f == "md" or f == "text" or f == "markdown":
        txt := u.decode_text(io.read_bytes(src)) if type(src) == "str" else u.decode_text(src)
        return from_markdown(txt)
    errors.fail(errors.FORMAT, "format de présentation non reconnu (" + u.to_text(f) + ")")

# ============================================================================================== texte

func _ph_type(s):
    if not isinstance(s, ps.Shape) or s.placeholder == null:
        return null
    return u.get(s.placeholder, "type", "body")

func _is_title(s):
    t := _ph_type(s)
    return t == "title" or t == "ctrTitle"

# Défauts de rendu d'une forme de texte : taille, couleur, puces, alignement, ancrage.
func _text_defaults(s, slide):
    t := _ph_type(s)
    d := {"size": 18.0, "color": "000000", "bullets": false, "levels": false, "align": "left", "anchor": "top", "bold": false}
    if t == "ctrTitle":
        d["size"] = 44.0
        d["align"] = "center"
        d["anchor"] = "bottom"
    elif t == "title":
        d["size"] = 40.0 if slide.layout != "section" else 44.0
        d["anchor"] = "middle" if slide.layout != "section" else "bottom"
    elif t == "subTitle":
        d["size"] = 24.0
        d["align"] = "center"
        d["color"] = "595959"
    elif t != null:
        d["bullets"] = slide.layout != "section" and slide.layout != "title"
        d["levels"] = true
        d["color"] = "000000" if slide.layout != "section" else "595959"
    elif isinstance(s, ps.Shape) and s.kind != "textbox":
        d["align"] = "center"
        d["anchor"] = "middle"
        d["color"] = "FFFFFF" if s.fill == null or (s.fill != "none" and _dark(s.fill)) else "000000"
    if isinstance(s, ps.Shape) and s.text != null and s.text.anchor != null:
        d["anchor"] = s.text.anchor
    return d

func _dark(color):
    h := u.color_hex(color)
    r := _hex(_n.str_slice(h, 0, 2))
    g := _hex(_n.str_slice(h, 2, 4))
    b := _hex(_n.str_slice(h, 4, 6))
    return (r * 299 + g * 587 + b * 114) / 1000 < 140

func _hex(s):
    v := 0
    for c in string.lower(s):
        o := string.ord(c)
        d := o - 48 if o <= 57 else o - 87
        v = v * 16 + d
    return v

func _font_of(family, bold, italic):
    fam := "Helvetica"
    if family != null:
        low := string.lower(family)
        if string.contains(low, "courier") or string.contains(low, "mono") or string.contains(low, "consolas"):
            fam = "Courier"
        elif string.contains(low, "times") or string.contains(low, "georgia") or string.contains(low, "serif") and not string.contains(low, "sans"):
            fam = "Times-Roman"
    return pw.resolve_font(fam, bold, italic)

# Découpe les segments d'un paragraphe en lignes de largeur max `width`.
# segs : [texte, fmt] ; renvoie [[seg_ligne...], ...] où seg_ligne = {"text", "font", "size", "color", "u", "link", "w"}
func _wrap(segs, width):
    lines := []
    cur := []
    cur_w := 0.0
    for sg in segs:
        f := sg[1]
        font := _font_of(f["font"], f["bold"], f["italic"])
        parts := string.split(string.replace(sg[0], "\t", "    "), "\n")
        pi := 0
        for part in parts:
            if pi > 0:
                append(lines, cur)
                cur = []
                cur_w = 0.0
            words := string.split(part, " ")
            wi := 0
            for w in words:
                token := w if wi == 0 else " " + w
                if wi == 0 and len(cur) > 0 and pi == 0:
                    token = w
                tw := pw.text_width(token, font, f["size"])
                if cur_w + tw > width and len(cur) > 0 and string.trim(token) != "":
                    append(lines, cur)
                    cur = []
                    cur_w = 0.0
                    token = w
                    tw = pw.text_width(token, font, f["size"])
                if token != "":
                    if len(cur) > 0 and cur[len(cur) - 1]["font"] == font and cur[len(cur) - 1]["size"] == f["size"] and cur[len(cur) - 1]["color"] == f["color"] and cur[len(cur) - 1]["u"] == f["underline"] and cur[len(cur) - 1]["link"] == f["link"]:
                        last := cur[len(cur) - 1]
                        last["text"] = last["text"] + token
                        last["w"] = last["w"] + tw
                    else:
                        append(cur, {"text": token, "font": font, "size": f["size"], "color": f["color"], "u": f["underline"], "link": f["link"], "w": tw, "family": f["font"], "bold": f["bold"], "italic": f["italic"]})
                    cur_w = cur_w + tw
                wi = wi + 1
            pi = pi + 1
    append(lines, cur)
    return lines

func _line_width(line):
    w := 0.0
    for s in line:
        w = w + s["w"]
    return w

# Mise en page d'un cadre de texte dans box = [x, y, w, h] (points). Renvoie [éléments, hauteur].
func _layout_text(tf, box, d, scale, out):
    pad_l := 7.2
    pad_r := 7.2
    pad_t := 3.6
    pad_b := 3.6
    if tf.margins != null and len(tf.margins) == 4:
        pad_l = to_float(tf.margins[0])
        pad_t = to_float(tf.margins[1])
        pad_r = to_float(tf.margins[2])
        pad_b = to_float(tf.margins[3])
    x0 := box[0] + pad_l
    avail := box[2] - pad_l - pad_r
    blocks := []
    total := 0.0
    numbers := {}
    pi := 0
    for p in tf.paragraphs:
        lvl := p.level if p.level != null else 0
        if lvl > 8:
            lvl = 8
        base_size := to_float(d["size"])
        if d["levels"]:
            base_size = _LEVEL_SIZES[lvl]
        if p.font_size != null:
            base_size = to_float(p.font_size)
        bullet := null
        use_b := d["bullets"]
        if p.bullet == false:
            use_b = false
        elif p.bullet != null:
            use_b = true
        if use_b:
            if p.bullet == "number":
                key := lvl
                numbers[key] = u.get(numbers, key, 0) + 1
                bullet = str(numbers[key]) + "."
            elif p.bullet != null and p.bullet != true and type(p.bullet) == "str":
                bullet = p.bullet
            else:
                bullet = _BULLETS[lvl]
        segs := []
        max_size := base_size * scale
        for r in p.runs:
            sz := (to_float(r.size) if r.size != null else base_size) * scale
            if sz > max_size:
                max_size = sz
            append(segs, [r.text, {"font": r.font, "bold": r.bold == true or (r.bold == null and d["bold"]), "italic": r.italic == true, "underline": r.underline != null and r.underline != false and r.underline != "none", "size": sz, "color": u.color_hex(r.color) if r.color != null else d["color"], "link": r.link}])
        indent := 0.0
        if d["levels"] or use_b:
            indent = to_float(lvl) * 27.0 * scale
        text_x := indent + (max_size * 1.1 if bullet != null else 0.0)
        lines := _wrap(segs, avail - text_x) if len(segs) > 0 else [[]]
        sb := to_float(p.space_before) if p.space_before != null else (max_size * 0.2 if d["levels"] and pi > 0 else 0.0)
        sa := to_float(p.space_after) if p.space_after != null else 0.0
        lead := to_float(p.line_spacing) if p.line_spacing != null else 1.0
        if lead > 5.0:
            lead = lead / max_size
        al := p.align if p.align != null else d["align"]
        append(blocks, {"lines": lines, "size": max_size, "bullet": bullet, "indent": indent, "text_x": text_x, "sb": sb, "sa": sa, "lead": lead, "align": al, "bcolor": segs[0][1]["color"] if len(segs) > 0 else d["color"]})
        for ln in lines:
            lh := max_size
            for sgl in ln:
                if sgl["size"] > lh:
                    lh = sgl["size"]
            total = total + lh * 1.2 * lead
        total = total + sb + sa
        pi = pi + 1
    if out == null:
        return total
    inner_h := box[3] - pad_t - pad_b
    y := box[1] + pad_t
    if d["anchor"] == "middle" or d["anchor"] == "ctr" or d["anchor"] == "center":
        y = box[1] + pad_t + (inner_h - total) / 2.0
    elif d["anchor"] == "bottom" or d["anchor"] == "b":
        y = box[1] + box[3] - pad_b - total
    for b in blocks:
        y = y + b["sb"]
        first := true
        for ln in b["lines"]:
            lh := b["size"]
            for sgl in ln:
                if sgl["size"] > lh:
                    lh = sgl["size"]
            base := y + lh * 0.95 * b["lead"]
            lw := _line_width(ln)
            tx := x0 + b["text_x"]
            room := avail - b["text_x"]
            if b["align"] == "center":
                tx = tx + (room - lw) / 2.0
            elif b["align"] == "right":
                tx = tx + room - lw
            if first and b["bullet"] != null:
                append(out, {"t": "text", "x": x0 + b["indent"], "y": base, "segs": [{"text": b["bullet"], "font": "Helvetica", "size": b["size"], "color": b["bcolor"], "u": false, "link": null, "w": 0.0, "family": null, "bold": false, "italic": false}]})
            if len(ln) > 0:
                append(out, {"t": "text", "x": tx, "y": base, "segs": ln})
                cx := tx
                for sgl in ln:
                    if sgl["link"] != null:
                        append(out, {"t": "link", "x": cx, "y": base - sgl["size"] * 0.8, "w": sgl["w"], "h": sgl["size"], "url": sgl["link"]})
                    cx = cx + sgl["w"]
            y = y + lh * 1.2 * b["lead"]
            first = false
        y = y + b["sa"]
    return total

func _text_items(tf, box, d, out, shrink):
    scale := 1.0
    if shrink:
        need := _layout_text(tf, box, d, 1.0, null)
        while need > box[3] and scale > 0.45:
            scale = scale - 0.05
            need = _layout_text(tf, box, d, scale, null)
    _layout_text(tf, box, d, scale, out)

# ============================================================================================== formes

func _arrow_points(kind, x0, y0, w, h):
    if kind == "rightArrow" or kind == "homePlate" or kind == "chevron":
        if kind == "homePlate":
            return [[x0, y0], [x0 + w - h / 2.0, y0], [x0 + w, y0 + h / 2.0], [x0 + w - h / 2.0, y0 + h], [x0, y0 + h]]
        if kind == "chevron":
            return [[x0, y0], [x0 + w - h / 2.0, y0], [x0 + w, y0 + h / 2.0], [x0 + w - h / 2.0, y0 + h], [x0, y0 + h], [x0 + h / 2.0, y0 + h / 2.0]]
        hw := h / 2.0 if h / 2.0 < w else w * 0.5
        return [[x0, y0 + h * 0.25], [x0 + w - hw, y0 + h * 0.25], [x0 + w - hw, y0], [x0 + w, y0 + h / 2.0], [x0 + w - hw, y0 + h], [x0 + w - hw, y0 + h * 0.75], [x0, y0 + h * 0.75]]
    if kind == "leftArrow":
        hw := h / 2.0 if h / 2.0 < w else w * 0.5
        return [[x0 + w, y0 + h * 0.25], [x0 + hw, y0 + h * 0.25], [x0 + hw, y0], [x0, y0 + h / 2.0], [x0 + hw, y0 + h], [x0 + hw, y0 + h * 0.75], [x0 + w, y0 + h * 0.75]]
    if kind == "upArrow":
        hh := w / 2.0 if w / 2.0 < h else h * 0.5
        return [[x0 + w * 0.25, y0 + h], [x0 + w * 0.25, y0 + hh], [x0, y0 + hh], [x0 + w / 2.0, y0], [x0 + w, y0 + hh], [x0 + w * 0.75, y0 + hh], [x0 + w * 0.75, y0 + h]]
    if kind == "downArrow":
        hh := w / 2.0 if w / 2.0 < h else h * 0.5
        return [[x0 + w * 0.25, y0], [x0 + w * 0.25, y0 + h - hh], [x0, y0 + h - hh], [x0 + w / 2.0, y0 + h], [x0 + w, y0 + h - hh], [x0 + w * 0.75, y0 + h - hh], [x0 + w * 0.75, y0]]
    if kind == "leftRightArrow":
        hw := h / 2.0 if h < w / 2.0 else w * 0.25
        return [[x0, y0 + h / 2.0], [x0 + hw, y0], [x0 + hw, y0 + h * 0.25], [x0 + w - hw, y0 + h * 0.25], [x0 + w - hw, y0], [x0 + w, y0 + h / 2.0], [x0 + w - hw, y0 + h], [x0 + w - hw, y0 + h * 0.75], [x0 + hw, y0 + h * 0.75], [x0 + hw, y0 + h]]
    return null

func _regular(n, x0, y0, w, h, rot0):
    pts := []
    k := 0
    while k < n:
        a := rot0 + 2.0 * math.PI * to_float(k) / to_float(n)
        append(pts, [x0 + w / 2.0 + w / 2.0 * math.cos(a), y0 + h / 2.0 + h / 2.0 * math.sin(a)])
        k = k + 1
    return pts

func _star(n, x0, y0, w, h, inner):
    pts := []
    k := 0
    while k < n * 2:
        a := -math.PI / 2.0 + math.PI * to_float(k) / to_float(n)
        r := 1.0 if k % 2 == 0 else inner
        append(pts, [x0 + w / 2.0 + w / 2.0 * r * math.cos(a), y0 + h / 2.0 + h / 2.0 * r * math.sin(a)])
        k = k + 1
    return pts

func _geometry(kind, x0, y0, w, h):
    if kind == "ellipse" or kind == "donut":
        return {"t": "ellipse", "cx": x0 + w / 2.0, "cy": y0 + h / 2.0, "rx": w / 2.0, "ry": h / 2.0}
    if kind == "roundRect" or kind == "flowChartAlternateProcess" or kind == "wedgeRoundRectCallout":
        r := (w if w < h else h) * 0.1667
        return {"t": "rect", "x": x0, "y": y0, "w": w, "h": h, "r": r}
    if kind == "flowChartTerminator":
        return {"t": "rect", "x": x0, "y": y0, "w": w, "h": h, "r": (w if w < h else h) / 2.0}
    pts := null
    if kind == "triangle":
        pts = [[x0 + w / 2.0, y0], [x0 + w, y0 + h], [x0, y0 + h]]
    elif kind == "rtTriangle":
        pts = [[x0, y0], [x0 + w, y0 + h], [x0, y0 + h]]
    elif kind == "diamond" or kind == "flowChartDecision":
        pts = [[x0 + w / 2.0, y0], [x0 + w, y0 + h / 2.0], [x0 + w / 2.0, y0 + h], [x0, y0 + h / 2.0]]
    elif kind == "parallelogram":
        o := w * 0.25
        pts = [[x0 + o, y0], [x0 + w, y0], [x0 + w - o, y0 + h], [x0, y0 + h]]
    elif kind == "trapezoid":
        o := w * 0.25
        pts = [[x0 + o, y0], [x0 + w - o, y0], [x0 + w, y0 + h], [x0, y0 + h]]
    elif kind == "pentagon":
        pts = _regular(5, x0, y0, w, h, -math.PI / 2.0)
    elif kind == "hexagon":
        pts = _regular(6, x0, y0, w, h, 0.0)
    elif kind == "octagon":
        pts = _regular(8, x0, y0, w, h, math.PI / 8.0)
    elif kind == "star5":
        pts = _star(5, x0, y0, w, h, 0.38)
    elif kind == "star4":
        pts = _star(4, x0, y0, w, h, 0.38)
    elif kind == "star6":
        pts = _star(6, x0, y0, w, h, 0.5)
    elif kind == "star8":
        pts = _star(8, x0, y0, w, h, 0.6)
    elif kind == "star12" or kind == "star24" or kind == "sun":
        pts = _star(12, x0, y0, w, h, 0.7)
    elif kind == "plus":
        a := w / 3.0
        b := h / 3.0
        pts = [[x0 + a, y0], [x0 + 2.0 * a, y0], [x0 + 2.0 * a, y0 + b], [x0 + w, y0 + b], [x0 + w, y0 + 2.0 * b], [x0 + 2.0 * a, y0 + 2.0 * b], [x0 + 2.0 * a, y0 + h], [x0 + a, y0 + h], [x0 + a, y0 + 2.0 * b], [x0, y0 + 2.0 * b], [x0, y0 + b], [x0 + a, y0 + b]]
    else:
        pts = _arrow_points(kind, x0, y0, w, h)
    if pts != null:
        return {"t": "poly", "pts": pts}
    return {"t": "rect", "x": x0, "y": y0, "w": w, "h": h, "r": 0.0}

# ============================================================================================== tableaux

func _table_items(t, out):
    x0 := _pt(t.x)
    y0 := _pt(t.y)
    ncol := t.col_count()
    if ncol == 0:
        return null
    widths := []
    if t.col_widths != null:
        for w in t.col_widths:
            append(widths, _pt(u.length(w)))
    while len(widths) < ncol:
        append(widths, _pt(t.cx) / to_float(ncol))
    nrow := len(t.rows)
    base_h := _pt(t.cy) / to_float(nrow if nrow > 0 else 1)
    y := y0
    ri := 0
    for row in t.rows:
        # hauteur : la plus grande des cellules
        rh := base_h
        if t.row_heights != null and ri < len(t.row_heights):
            rh = _pt(u.length(t.row_heights[ri]))
        defaults := []
        ci := 0
        for cell in row:
            head := ri == 0 and t.header
            d := {"size": to_float(cell.size if cell.size != null else (t.font_size if t.font_size != null else 18)), "color": u.color_hex(cell.color) if cell.color != null else ("FFFFFF" if head else "000000"), "bullets": false, "levels": false, "align": cell.align if cell.align != null else "left", "anchor": cell.valign if cell.valign != null else "top", "bold": cell.bold == true or (cell.bold == null and head)}
            append(defaults, d)
            if ci < len(widths) and cell.text != null:
                need := _layout_text(cell.text, [0.0, 0.0, widths[ci], 1000.0], d, 1.0, null) + 7.2
                if need > rh:
                    rh = need
            ci = ci + 1
        x := x0
        ci = 0
        for cell in row:
            w := widths[ci] if ci < len(widths) else widths[len(widths) - 1]
            span_w := w
            k := 1
            while k < cell.col_span and ci + k < len(widths):
                span_w = span_w + widths[ci + k]
                k = k + 1
            if not cell.merged_h and not cell.merged_v:
                head := ri == 0 and t.header
                fill := cell.fill
                if fill == null:
                    fill = _ACCENT if head else ("CFD5EA" if t.banded and ri % 2 == 1 else "E9EBF5")
                append(out, {"t": "rect", "x": x, "y": y, "w": span_w, "h": rh, "r": 0.0, "fill": u.color_hex(fill), "stroke": "FFFFFF", "lw": 1.0})
                if cell.text != null:
                    _layout_text(cell.text, [x, y, span_w, rh], defaults[ci], 1.0, out)
            x = x + w
            ci = ci + 1
        y = y + rh
        ri = ri + 1

# ============================================================================================== graphiques

func _nice_step(maxv):
    if maxv <= 0.0:
        return 1.0
    raw := maxv / 5.0
    mag := math.pow(10.0, math.floor(math.log10(raw)))
    r := raw / mag
    step := 10.0
    if r <= 1.0:
        step = 1.0
    elif r <= 2.0:
        step = 2.0
    elif r <= 2.5:
        step = 2.5
    elif r <= 5.0:
        step = 5.0
    return step * mag

func _fmt_axis(v):
    if v == to_float(to_int(v)):
        return str(to_int(v))
    return u.format_number(u.round_to(v, 2))

func _num(v):
    t := type(v)
    if t == "int" or t == "float":
        return to_float(v)
    if t == "str":
        n := _n.num_parse(v)
        if n != null:
            return to_float(n)
    return 0.0

func _txt(x0, y0, text, size, color, align="left", bold=false):
    font := pw.resolve_font("Helvetica", bold, false)
    w := pw.text_width(text, font, size)
    xx := x0
    if align == "center":
        xx = x0 - w / 2.0
    elif align == "right":
        xx = x0 - w
    return {"t": "text", "x": xx, "y": y0, "segs": [{"text": text, "font": font, "size": size, "color": color, "u": false, "link": null, "w": w, "family": null, "bold": bold, "italic": false}]}

func _chart_items(ch, out):
    x0 := _pt(ch.x)
    y0 := _pt(ch.y)
    w := _pt(ch.cx)
    h := _pt(ch.cy)
    append(out, {"t": "rect", "x": x0, "y": y0, "w": w, "h": h, "r": 0.0, "fill": "FFFFFF", "stroke": null, "lw": 0.0})
    top := y0 + 8.0
    if ch.title != null and ch.title != "":
        append(out, _txt(x0 + w / 2.0, y0 + 22.0, u.to_text(ch.title), 16.0, "404040", "center"))
        top = y0 + 34.0
    series := ch.series
    cats := ch.categories
    n := len(cats)
    kind := ch.kind
    bottom := y0 + h - 8.0
    # légende
    if ch.legend != null and ch.legend != false and ch.legend != "none":
        names := []
        if kind == "pie" or kind == "doughnut":
            for c in cats:
                append(names, u.to_text(c))
        else:
            for s in series:
                append(names, u.to_text(u.get(s, "name", "")))
        total_w := 0.0
        for nm in names:
            total_w = total_w + pw.text_width(nm, "Helvetica", 10.0) + 22.0
        lx := x0 + (w - total_w) / 2.0
        ly := y0 + h - 14.0
        k := 0
        for nm in names:
            col := _series_color(series, k, kind)
            append(out, {"t": "rect", "x": lx, "y": ly - 8.0, "w": 8.0, "h": 8.0, "r": 0.0, "fill": col, "stroke": null, "lw": 0.0})
            append(out, _txt(lx + 11.0, ly, nm, 10.0, "595959"))
            lx = lx + pw.text_width(nm, "Helvetica", 10.0) + 22.0
            k = k + 1
        bottom = y0 + h - 28.0
    if kind == "pie" or kind == "doughnut":
        vals := u.get(series[0], "values", []) if len(series) > 0 else []
        total := 0.0
        for v in vals:
            total = total + _num(v)
        if total <= 0.0:
            return null
        r := ((bottom - top) if (bottom - top) < w else w) / 2.0 - 6.0
        cx := x0 + w / 2.0
        cy := (top + bottom) / 2.0
        a := -math.PI / 2.0
        k := 0
        for v in vals:
            frac := _num(v) / total
            b := a + frac * 2.0 * math.PI
            pts := []
            if kind == "pie":
                append(pts, [cx, cy])
            steps := to_int(frac * 72.0) + 2
            j := 0
            while j <= steps:
                t := a + (b - a) * to_float(j) / to_float(steps)
                append(pts, [cx + r * math.cos(t), cy + r * math.sin(t)])
                j = j + 1
            if kind == "doughnut":
                j = steps
                while j >= 0:
                    t := a + (b - a) * to_float(j) / to_float(steps)
                    append(pts, [cx + r * 0.5 * math.cos(t), cy + r * 0.5 * math.sin(t)])
                    j = j - 1
            append(out, {"t": "poly", "pts": pts, "fill": _COLORS[k % len(_COLORS)], "stroke": "FFFFFF", "lw": 1.0})
            if frac > 0.04:
                mid := (a + b) / 2.0
                rr := r * (0.65 if kind == "pie" else 0.75)
                append(out, _txt(cx + rr * math.cos(mid), cy + rr * math.sin(mid) + 4.0, u.format_number(u.round_to(frac * 100.0, 0)) + " %", 10.0, "FFFFFF", "center", true))
            a = b
            k = k + 1
        return null
    # axes
    stacked := ch.stacked == true
    maxv := 0.0
    minv := 0.0
    if stacked:
        i := 0
        while i < n:
            sp := 0.0
            sn := 0.0
            for s in series:
                vals := u.get(s, "values", [])
                v := _num(vals[i]) if i < len(vals) else 0.0
                if v >= 0.0:
                    sp = sp + v
                else:
                    sn = sn + v
            if sp > maxv:
                maxv = sp
            if sn < minv:
                minv = sn
            i = i + 1
    else:
        for s in series:
            for v in u.get(s, "values", []):
                fv := _num(v)
                if fv > maxv:
                    maxv = fv
                if fv < minv:
                    minv = fv
    xmin := 0.0
    xmax := 0.0
    if kind == "scatter":
        first := true
        for c in cats:
            fv := _num(c)
            if first or fv < xmin:
                xmin = fv
            if first or fv > xmax:
                xmax = fv
            first = false
        if xmax == xmin:
            xmax = xmin + 1.0
    step := _nice_step(maxv - minv if maxv - minv > 0.0 else 1.0)
    vmax := math.ceil(maxv / step) * step
    vmin := math.floor(minv / step) * step
    if vmax == vmin:
        vmax = vmin + step
    horiz := kind == "bar"
    label_w := 0.0
    tick := vmin
    while tick <= vmax + step * 0.01:
        lw := pw.text_width(_fmt_axis(tick), "Helvetica", 9.0)
        if lw > label_w:
            label_w = lw
        tick = tick + step
    cat_w := 0.0
    if horiz:
        for c in cats:
            lw := pw.text_width(u.to_text(c), "Helvetica", 9.0)
            if lw > cat_w:
                cat_w = lw
    px0 := x0 + 10.0 + (cat_w if horiz else label_w) + 6.0
    px1 := x0 + w - 12.0
    py0 := top + 4.0
    py1 := bottom - 16.0
    pw_ := px1 - px0
    ph := py1 - py0
    if pw_ <= 10.0 or ph <= 10.0:
        return null
    # grille et graduations
    tick = vmin
    while tick <= vmax + step * 0.01:
        f := (tick - vmin) / (vmax - vmin)
        if horiz:
            gx := px0 + f * pw_
            append(out, {"t": "line", "x1": gx, "y1": py0, "x2": gx, "y2": py1, "stroke": "D9D9D9", "lw": 0.75})
            append(out, _txt(gx, py1 + 12.0, _fmt_axis(tick), 9.0, "595959", "center"))
        else:
            gy := py1 - f * ph
            append(out, {"t": "line", "x1": px0, "y1": gy, "x2": px1, "y2": gy, "stroke": "D9D9D9", "lw": 0.75})
            append(out, _txt(px0 - 4.0, gy + 3.0, _fmt_axis(tick), 9.0, "595959", "right"))
        tick = tick + step
    zero_f := (0.0 - vmin) / (vmax - vmin)
    if kind == "scatter":
        k := 0
        for s in series:
            col := _series_color(series, k, kind)
            vals := u.get(s, "values", [])
            i := 0
            while i < n and i < len(vals):
                fx := (_num(cats[i]) - xmin) / (xmax - xmin)
                fy := (_num(vals[i]) - vmin) / (vmax - vmin)
                append(out, {"t": "ellipse", "cx": px0 + fx * pw_, "cy": py1 - fy * ph, "rx": 3.0, "ry": 3.0, "fill": col, "stroke": null, "lw": 0.0})
                i = i + 1
            k = k + 1
        return null
    if n == 0:
        return null
    band := (ph if horiz else pw_) / to_float(n)
    i := 0
    while i < n:
        lbl := u.to_text(cats[i])
        if horiz:
            append(out, _txt(px0 - 4.0, py0 + band * (to_float(i) + 0.5) + 3.0, lbl, 9.0, "595959", "right"))
        else:
            append(out, _txt(px0 + band * (to_float(i) + 0.5), py1 + 12.0, lbl, 9.0, "595959", "center"))
        i = i + 1
    ns := len(series)
    if kind == "column" or kind == "bar":
        group := band * 0.7
        bw := group if stacked else group / to_float(ns if ns > 0 else 1)
        i = 0
        while i < n:
            pos := 0.0
            neg := 0.0
            k := 0
            for s in series:
                vals := u.get(s, "values", [])
                v := _num(vals[i]) if i < len(vals) else 0.0
                col := _series_color(series, k, kind)
                f0 := zero_f
                f1 := (v - vmin) / (vmax - vmin)
                if stacked:
                    if v >= 0.0:
                        f0 = (pos - vmin) / (vmax - vmin)
                        pos = pos + v
                        f1 = (pos - vmin) / (vmax - vmin)
                    else:
                        f0 = (neg - vmin) / (vmax - vmin)
                        neg = neg + v
                        f1 = (neg - vmin) / (vmax - vmin)
                lo := f0 if f0 < f1 else f1
                hi := f1 if f1 > f0 else f0
                start := band * to_float(i) + (band - group) / 2.0 + (0.0 if stacked else bw * to_float(k))
                if horiz:
                    append(out, {"t": "rect", "x": px0 + lo * pw_, "y": py0 + start, "w": (hi - lo) * pw_, "h": bw, "r": 0.0, "fill": col, "stroke": null, "lw": 0.0})
                else:
                    append(out, {"t": "rect", "x": px0 + start, "y": py1 - hi * ph, "w": bw, "h": (hi - lo) * ph, "r": 0.0, "fill": col, "stroke": null, "lw": 0.0})
                k = k + 1
            i = i + 1
    else:
        cum := []
        i = 0
        while i < n:
            append(cum, 0.0)
            i = i + 1
        k := 0
        for s in series:
            vals := u.get(s, "values", [])
            col := _series_color(series, k, kind)
            pts := []
            base_pts := []
            i = 0
            while i < n:
                v := _num(vals[i]) if i < len(vals) else 0.0
                b0 := cum[i]
                if stacked:
                    cum[i] = cum[i] + v
                    v = cum[i]
                xx := px0 + band * (to_float(i) + 0.5)
                append(pts, [xx, py1 - (v - vmin) / (vmax - vmin) * ph])
                append(base_pts, [xx, py1 - ((b0 if stacked else 0.0) - vmin) / (vmax - vmin) * ph])
                i = i + 1
            if kind == "area":
                poly := []
                for p in pts:
                    append(poly, p)
                j := len(base_pts) - 1
                while j >= 0:
                    append(poly, base_pts[j])
                    j = j - 1
                append(out, {"t": "poly", "pts": poly, "fill": col, "stroke": null, "lw": 0.0, "opacity": 0.85})
            else:
                j := 0
                while j + 1 < len(pts):
                    append(out, {"t": "line", "x1": pts[j][0], "y1": pts[j][1], "x2": pts[j + 1][0], "y2": pts[j + 1][1], "stroke": col, "lw": 2.25})
                    j = j + 1
                for p in pts:
                    append(out, {"t": "ellipse", "cx": p[0], "cy": p[1], "rx": 3.0, "ry": 3.0, "fill": col, "stroke": null, "lw": 0.0})
            k = k + 1
    # axe principal
    if horiz:
        zx := px0 + zero_f * pw_
        append(out, {"t": "line", "x1": zx, "y1": py0, "x2": zx, "y2": py1, "stroke": "A6A6A6", "lw": 0.75})
    else:
        zy := py1 - zero_f * ph
        append(out, {"t": "line", "x1": px0, "y1": zy, "x2": px1, "y2": zy, "stroke": "A6A6A6", "lw": 0.75})

func _series_color(series, k, kind):
    if kind != "pie" and kind != "doughnut" and k < len(series) and u.get(series[k], "color", null) != null:
        return u.color_hex(series[k]["color"])
    return _COLORS[k % len(_COLORS)]

# ============================================================================================== rendu

func render_slide(slide):
    out := []
    W := _pt(slide.width)
    H := _pt(slide.height)
    for s in slide.shapes:
        if isinstance(s, pimg.Picture):
            append(out, {"t": "image", "x": _pt(s.x), "y": _pt(s.y), "w": _pt(s.cx), "h": _pt(s.cy), "img": s.image})
            if s.link != null:
                append(out, {"t": "link", "x": _pt(s.x), "y": _pt(s.y), "w": _pt(s.cx), "h": _pt(s.cy), "url": s.link})
            continue
        if isinstance(s, ptb.SlideTable):
            _table_items(s, out)
            continue
        if isinstance(s, pch.SlideChart):
            _chart_items(s, out)
            continue
        if not isinstance(s, ps.Shape):
            continue
        x0 := _pt(s.x)
        y0 := _pt(s.y)
        w := _pt(s.cx)
        h := _pt(s.cy)
        if s.kind == "line":
            x1 := x0
            y1 := y0
            x2 := x0 + w
            y2 := y0 + h
            if s.flip_h:
                x1 = x0 + w
                x2 = x0
            if s.flip_v:
                y1 = y0 + h
                y2 = y0
            append(out, {"t": "line", "x1": x1, "y1": y1, "x2": x2, "y2": y2, "stroke": u.color_hex(s.line) if s.line != null and s.line != "none" else "000000", "lw": to_float(s.line_width) if s.line_width != null else 1.0, "dash": s.dash})
            continue
        is_text := s.kind == "textbox" or s.placeholder != null
        fill := null
        stroke := null
        if is_text:
            fill = u.color_hex(s.fill) if s.fill != null and s.fill != "none" else null
            stroke = u.color_hex(s.line) if s.line != null and s.line != "none" else null
        else:
            fill = null if s.fill == "none" else (u.color_hex(s.fill) if s.fill != null else _ACCENT)
            stroke = null if s.line == "none" else (u.color_hex(s.line) if s.line != null else "2F528F")
        if fill != null or stroke != null:
            g := _geometry("rect" if is_text else s.kind, x0, y0, w, h)
            g["fill"] = fill
            g["stroke"] = stroke
            g["lw"] = to_float(s.line_width) if s.line_width != null else 1.0
            append(out, g)
        if s.text != null:
            d := _text_defaults(s, slide)
            shrink := s.placeholder != null or (s.text.autofit == "shrink")
            _text_items(s.text, [x0, y0, w, h], d, out, shrink)
        if s.link != null:
            append(out, {"t": "link", "x": x0, "y": y0, "w": w, "h": h, "url": s.link})
    return {"width": W, "height": H, "background": u.color_hex(slide.background) if slide.background != null else "FFFFFF", "items": out}

# ---------------------------------------------------------------------------------------------- PDF

func _pdf_draw(c, r):
    H := r["height"]
    c.set_fill(r["background"])
    c.rect(0, 0, r["width"], H, true, false)
    for it in r["items"]:
        t := it["t"]
        if t == "rect" or t == "ellipse" or t == "poly":
            f := u.get(it, "fill", null)
            s := u.get(it, "stroke", null)
            if f == null and s == null:
                continue
            if f != null:
                c.set_fill(f)
            if s != null:
                c.set_stroke(s)
                c.set_line_width(u.get(it, "lw", 1.0))
            op := u.get(it, "opacity", null)
            if op != null:
                c.save_state()
                c.set_opacity(op)
            if t == "rect":
                if u.get(it, "r", 0.0) > 0.0:
                    c.rounded_rect(it["x"], H - it["y"] - it["h"], it["w"], it["h"], it["r"], f != null, s != null)
                else:
                    c.rect(it["x"], H - it["y"] - it["h"], it["w"], it["h"], f != null, s != null)
            elif t == "ellipse":
                c.ellipse(it["cx"], H - it["cy"], it["rx"], it["ry"], f != null, s != null)
            else:
                pts := []
                for p in it["pts"]:
                    append(pts, [p[0], H - p[1]])
                c.polygon(pts, f != null, s != null)
            if op != null:
                c.restore_state()
        elif t == "line":
            c.set_stroke(it["stroke"])
            c.set_line_width(it["lw"])
            dash := u.get(it, "dash", null)
            if dash != null and dash != "solid":
                c.set_dash([4, 3])
            c.line(it["x1"], H - it["y1"], it["x2"], H - it["y2"])
            if dash != null and dash != "solid":
                c.set_dash(null)
        elif t == "text":
            segs := []
            for sg in it["segs"]:
                append(segs, [sg["text"], sg["font"], sg["size"], sg["color"]])
            c.rich_line(it["x"], H - it["y"], segs)
            cx := it["x"]
            for sg in it["segs"]:
                if sg["u"]:
                    c.set_stroke(sg["color"])
                    c.set_line_width(sg["size"] / 18.0)
                    c.line(cx, H - it["y"] - sg["size"] * 0.12, cx + sg["w"], H - it["y"] - sg["size"] * 0.12)
                cx = cx + sg["w"]
        elif t == "image":
            try:
                c.image(it["img"], it["x"], H - it["y"] - it["h"], it["w"], it["h"])
            catch e:
                c.set_stroke("A6A6A6")
                c.rect(it["x"], H - it["y"] - it["h"], it["w"], it["h"], false, true)
        elif t == "link":
            c.link(it["x"], H - it["y"] - it["h"], it["w"], it["h"], it["url"])

func to_pdf(prs, options=null):
    o := options if options != null else {}
    b := pw.PdfBuilder()
    if prs.metadata.title != "":
        b.info["Title"] = prs.metadata.title
    if prs.metadata.creator != "":
        b.info["Author"] = prs.metadata.creator
    k := 0
    for s in prs.slides:
        if s.hidden and not u.get(o, "hidden", false):
            continue
        r := render_slide(s)
        c := b.new_page([r["width"], r["height"]])
        _pdf_draw(c, r)
        t := s.title()
        b.add_bookmark(t if t != "" else "Diapositive " + str(k + 1), len(b.pages) - 1)
        if u.get(o, "notes", false) and s.notes != null and s.notes != "":
            nc := b.new_page([r["width"], r["height"]])
            nc.set_fill("000000")
            nc.set_font("Helvetica-Bold", 16)
            nc.text(40, r["height"] - 50, "Notes — " + (t if t != "" else "diapositive " + str(k + 1)))
            nc.set_font("Helvetica", 13)
            nc.text_box(40, r["height"] - 75, r["width"] - 80, r["height"] - 110, s.notes)
        k = k + 1
    return b.to_bytes()

# ---------------------------------------------------------------------------------------------- SVG / HTML

func _svg_color(c):
    return "#" + c if c != null else "none"

func _svg_family(sg):
    f := sg["font"]
    if string.starts_with(f, "Courier"):
        return "'Courier New', monospace"
    if string.starts_with(f, "Times"):
        return "'Times New Roman', serif"
    fam := sg["family"]
    if fam != null and fam != "":
        return "'" + string.replace(fam, "'", "") + "', Helvetica, Arial, sans-serif"
    return "Helvetica, Arial, sans-serif"

func _f(v):
    return u.format_number(u.round_to(to_float(v), 2))

func to_svg(slide, options=null):
    r := slide if type(slide) == "dict" else render_slide(slide)
    out := ["<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 " + _f(r["width"]) + " " + _f(r["height"]) + "\" role=\"img\">", "<rect width=\"100%\" height=\"100%\" fill=\"#" + r["background"] + "\"/>"]
    for it in r["items"]:
        t := it["t"]
        st := ""
        if t == "rect" or t == "ellipse" or t == "poly":
            f := u.get(it, "fill", null)
            s := u.get(it, "stroke", null)
            st = " fill=\"" + _svg_color(f) + "\" stroke=\"" + _svg_color(s) + "\"" + (" stroke-width=\"" + _f(u.get(it, "lw", 1.0)) + "\"" if s != null else "")
            if u.get(it, "opacity", null) != null:
                st = st + " fill-opacity=\"" + _f(it["opacity"]) + "\""
        if t == "rect":
            rr := u.get(it, "r", 0.0)
            append(out, "<rect x=\"" + _f(it["x"]) + "\" y=\"" + _f(it["y"]) + "\" width=\"" + _f(it["w"]) + "\" height=\"" + _f(it["h"]) + "\"" + (" rx=\"" + _f(rr) + "\"" if rr > 0.0 else "") + st + "/>")
        elif t == "ellipse":
            append(out, "<ellipse cx=\"" + _f(it["cx"]) + "\" cy=\"" + _f(it["cy"]) + "\" rx=\"" + _f(it["rx"]) + "\" ry=\"" + _f(it["ry"]) + "\"" + st + "/>")
        elif t == "poly":
            pts := []
            for p in it["pts"]:
                append(pts, _f(p[0]) + "," + _f(p[1]))
            append(out, "<polygon points=\"" + string.join(" ", pts) + "\"" + st + "/>")
        elif t == "line":
            dash := u.get(it, "dash", null)
            append(out, "<line x1=\"" + _f(it["x1"]) + "\" y1=\"" + _f(it["y1"]) + "\" x2=\"" + _f(it["x2"]) + "\" y2=\"" + _f(it["y2"]) + "\" stroke=\"#" + it["stroke"] + "\" stroke-width=\"" + _f(it["lw"]) + "\"" + (" stroke-dasharray=\"4 3\"" if dash != null and dash != "solid" else "") + "/>")
        elif t == "text":
            spans := []
            for sg in it["segs"]:
                a := " font-family=\"" + ohtml.escape(_svg_family(sg), true) + "\" font-size=\"" + _f(sg["size"]) + "\" fill=\"#" + sg["color"] + "\""
                if sg["bold"]:
                    a = a + " font-weight=\"bold\""
                if sg["italic"]:
                    a = a + " font-style=\"italic\""
                if sg["u"]:
                    a = a + " text-decoration=\"underline\""
                sp := "<tspan" + a + ">" + ohtml.escape(sg["text"]) + "</tspan>"
                if sg["link"] != null:
                    sp = "<a href=\"" + ohtml.escape(sg["link"], true) + "\">" + sp + "</a>"
                append(spans, sp)
            append(out, "<text x=\"" + _f(it["x"]) + "\" y=\"" + _f(it["y"]) + "\" xml:space=\"preserve\">" + string.join("", spans) + "</text>")
        elif t == "image":
            img := it["img"]
            append(out, "<image x=\"" + _f(it["x"]) + "\" y=\"" + _f(it["y"]) + "\" width=\"" + _f(it["w"]) + "\" height=\"" + _f(it["h"]) + "\" preserveAspectRatio=\"none\" href=\"data:" + img.mime + ";base64," + u.base64_encode(img.data) + "\"/>")
    append(out, "</svg>")
    return string.join("\n", out)

const _HTML_CSS := "body{margin:0;background:#2b2b2b;font-family:Helvetica,Arial,sans-serif;color:#eee}main{max-width:1100px;margin:0 auto;padding:24px 16px}h1{font-weight:400;font-size:1.4rem}section.slide{margin:0 0 28px}section.slide svg{display:block;width:100%;height:auto;background:#fff;box-shadow:0 2px 12px rgba(0,0,0,.5)}.num{font-size:.8rem;color:#aaa;margin:6px 0}.notes{background:#3a3a3a;border-left:3px solid #4472C4;padding:8px 12px;margin-top:8px;white-space:pre-wrap;font-size:.9rem}@media print{body{background:#fff}section.slide{page-break-after:always}.notes{color:#000;background:#f2f2f2}}"

func to_html(prs, options=null):
    o := options if options != null else {}
    notes := u.get(o, "notes", true)
    title := prs.metadata.title
    if title == "" and len(prs.slides) > 0:
        title = prs.slides[0].title()
    parts := ["<main>"]
    if title != "":
        append(parts, "<h1>" + ohtml.escape(title) + "</h1>")
    k := 1
    for s in prs.slides:
        if s.hidden and not u.get(o, "hidden", false):
            k = k + 1
            continue
        append(parts, "<section class=\"slide\" id=\"diapositive-" + str(k) + "\" aria-label=\"" + ohtml.escape(s.title() if s.title() != "" else "Diapositive " + str(k), true) + "\">")
        append(parts, to_svg(s))
        append(parts, "<div class=\"num\">" + str(k) + " / " + str(len(prs.slides)) + "</div>")
        if notes and s.notes != null and s.notes != "":
            append(parts, "<div class=\"notes\">" + ohtml.escape(s.notes) + "</div>")
        append(parts, "</section>")
        k = k + 1
    append(parts, "</main>")
    return ohtml.document(title if title != "" else "Présentation", string.join("\n", parts), _HTML_CSS)

# ============================================================================================== documents

func _runs_from_tp(p):
    out := []
    for r in p.runs:
        f := {}
        if r.bold == true:
            f["bold"] = true
        if r.italic == true:
            f["italic"] = true
        if r.underline != null and r.underline != false and r.underline != "none":
            f["underline"] = true
        if r.strike == true:
            f["strike"] = true
        if r.link != null:
            f["link"] = r.link
        if r.font != null:
            low := string.lower(r.font)
            if string.contains(low, "courier") or string.contains(low, "mono") or string.contains(low, "consolas"):
                f["code"] = true
        append(out, document.Run(r.text, f))
    return out

func to_document(prs, notes=true, separators=false):
    d := document.Document(prs.metadata.title)
    d.metadata = prs.metadata
    k := 0
    for s in prs.slides:
        if separators and k > 0:
            d.add_hr()
        title := s.title()
        lvl := 1 if s.layout == "title" or s.layout == "section" else 2
        if title != "":
            d.add_heading(title, lvl)
            if d.title == "":
                d.title = title
        for sh in s.shapes:
            if _is_title(sh):
                continue
            if isinstance(sh, ps.Shape):
                if sh.text == null:
                    continue
                t := _ph_type(sh)
                bullets_default := t != null and t != "subTitle" and s.layout != "section" and s.layout != "title"
                code := true
                for p in sh.text.paragraphs:
                    for r in p.runs:
                        if r.font == null or not (string.contains(string.lower(r.font), "courier") or string.contains(string.lower(r.font), "mono")):
                            code = false
                if code and len(sh.text.paragraphs) > 0 and sh.text.text() != "":
                    d.add_code(sh.text.text())
                    continue
                for p in sh.text.paragraphs:
                    rs := _runs_from_tp(p)
                    if document.runs_text(rs) == "":
                        continue
                    use_b := bullets_default
                    if p.bullet == false:
                        use_b = false
                    elif p.bullet != null:
                        use_b = true
                    if use_b:
                        b := d.add_runs(rs, "list_item")
                        b.level = p.level if p.level != null else 0
                        b.ordered = p.bullet == "number"
                    else:
                        b := d.add_runs(rs)
                        if t == "subTitle":
                            b.style = "subtitle"
                        if p.align == "center" or p.align == "right":
                            b.align = p.align
            elif isinstance(sh, pimg.Picture):
                d.add_image(sh.image, u.round_to(_pt(sh.cx), 1), u.round_to(_pt(sh.cy), 1), sh.description if sh.description != null else "")
            elif isinstance(sh, ptb.SlideTable):
                d.add_table(sh.data(), sh.header)
            elif isinstance(sh, pch.SlideChart):
                rows := [[""]]
                for se in sh.series:
                    append(rows[0], u.to_text(u.get(se, "name", "")))
                i := 0
                for c in sh.categories:
                    line := [u.to_text(c)]
                    for se in sh.series:
                        vals := u.get(se, "values", [])
                        append(line, vals[i] if i < len(vals) else "")
                    append(rows, line)
                    i = i + 1
                if sh.title != null and sh.title != "":
                    d.add_paragraph([document.Run(u.to_text(sh.title), {"bold": true})])
                d.add_table(rows, true)
        if notes and s.notes != null and s.notes != "":
            d.add_quote("Notes : " + s.notes)
        k = k + 1
    return d

func _is_notes(b):
    if b.kind != "quote" and b.kind != "paragraph":
        return false
    t := string.lower(string.trim(b.plain()))
    return string.starts_with(t, "notes :") or string.starts_with(t, "notes:") or string.starts_with(t, "note :") or string.starts_with(t, "note:")

func _strip_notes(t):
    k := string.find(t, ":")
    return string.trim(_n.str_slice(t, k + 1, null)) if k >= 0 else t

func _tp_from_runs(tf, rs, level, bullet):
    p := tf.add_paragraph("")
    p.level = level
    p.bullet = bullet
    for r in rs:
        f := {}
        if r.bold:
            f["bold"] = true
        if r.italic:
            f["italic"] = true
        if r.underline:
            f["underline"] = true
        if r.strike:
            f["strike"] = true
        if r.link != null:
            f["link"] = r.link
        if r.code:
            f["font"] = "Courier New"
        if r.color != null:
            f["color"] = r.color
        p.add_run(r.text, f if len(keys(f)) > 0 else null)
    return p

class _Builder:
    func init(prs):
        self.prs = prs
        self.slide = null
        self.title = ""
        self.tf = null
        self.has_media = false

    func new_slide(title, layout="title_content"):
        s := self.prs.add_slide(layout)
        if title != "" and layout != "blank":
            s.add_title(title)
        self.slide = s
        self.title = title
        self.tf = null
        self.has_media = false
        return s

    func ensure(media=false):
        if self.slide == null:
            self.new_slide("", "title_only" if media else "title_content")
        elif media and (self.tf != null or self.has_media):
            self.new_slide(self.title + " (suite)" if self.title != "" else "", "title_only")
        elif not media and self.has_media:
            self.new_slide(self.title + " (suite)" if self.title != "" else "", "title_content")
        return self.slide

    func body():
        self.ensure(false)
        if self.tf == null:
            if self.slide.layout == "title_only" or self.slide.layout == "blank":
                self.slide.layout = "title_content"
            shape := self.slide.add_bullets([])
            self.tf = shape.text
        return self.tf

func from_document(d, widescreen=true):
    prs := pp.new(widescreen)
    prs.metadata = d.metadata
    bl := _Builder(prs)
    blocks := d.blocks
    i := 0
    n := len(blocks)
    while i < n:
        b := blocks[i]
        k := b.kind
        if k == "heading":
            t := document.runs_text(b.runs)
            nxt := blocks[i + 1] if i + 1 < n else null
            if i == 0 and b.level <= 1:
                s := bl.new_slide(t, "title")
                if nxt != null and nxt.kind == "paragraph" and not _is_notes(nxt):
                    s.add_subtitle(document.runs_text(nxt.runs))
                    i = i + 1
                bl.has_media = true
                i = i + 1
                continue
            if b.level <= 1 and (nxt == null or nxt.kind == "heading"):
                bl.new_slide(t, "section")
                bl.has_media = true
                i = i + 1
                continue
            bl.new_slide(t, "title_only")
        elif _is_notes(b):
            bl.ensure(false)
            note := _strip_notes(b.plain())
            bl.slide.notes = note if bl.slide.notes == null else bl.slide.notes + "\n" + note
        elif k == "paragraph" or k == "quote":
            tf := bl.body()
            p := _tp_from_runs(tf, b.runs, 0, false)
            if k == "quote":
                for r in p.runs:
                    r.italic = true
        elif k == "list_item":
            tf := bl.body()
            _tp_from_runs(tf, b.runs, b.level, "number" if b.ordered else null)
        elif k == "code":
            s := bl.ensure(true)
            box := s.boxes()["body"]
            sh := s.add_text(b.text, box[0], box[1], box[2], box[3], {"font": "Courier New", "size": 14})
            sh.fill = "F2F2F2"
            sh.text.autofit = "shrink"
            bl.has_media = true
        elif k == "table":
            s := bl.ensure(true)
            rows := []
            for r in b.rows:
                line := []
                for c in r:
                    append(line, document.runs_text(c))
                append(rows, line)
            t := s.add_table(rows)
            t.header = b.header
            bl.has_media = true
        elif k == "image":
            s := bl.ensure(true)
            s.add_image(b.image)
            if b.caption != null:
                box := s.boxes()["body"]
                s.add_text(b.caption, box[0], box[1] + box[3] - 457200, box[2], 457200, {"italic": true, "size": 14, "color": "595959"}).text.paragraphs[0].align = "center"
            bl.has_media = true
        elif k == "hr" or k == "page_break":
            # coupure : la suite va sur une nouvelle diapositive (sans titre si aucun titre ne suit)
            if bl.slide != null and i + 1 < n and blocks[i + 1].kind != "heading":
                bl.new_slide("", "title_content")
        i = i + 1
    # diapositives vides retirées (sauf si c'est la seule)
    kept := []
    for s in prs.slides:
        if len(s.shapes) > 0 or len(prs.slides) == 1:
            append(kept, s)
    prs.slides = kept
    return prs

func from_markdown(md, widescreen=true):
    return from_document(document.from_markdown(md), widescreen)

func to_markdown(prs, notes=true):
    return to_document(prs, notes, true).to_markdown()

func to_text(prs, notes=true):
    return prs.text(notes)

# ============================================================================================== enregistrement

func to_bytes(prs, format, options=null):
    f := string.lower(format)
    if f == "pptx":
        return prs.to_bytes()
    if f == "odp":
        return odp.write(prs)
    if f == "pdf":
        return to_pdf(prs, options)
    if f == "html" or f == "htm":
        return _n.utf8_encode(to_html(prs, options))
    if f == "md" or f == "markdown":
        return _n.utf8_encode(to_markdown(prs, u.get(options, "notes", true) if options != null else true))
    if f == "txt" or f == "text":
        return _n.utf8_encode(to_text(prs, u.get(options, "notes", true) if options != null else true))
    errors.fail(errors.CONVERSION, "écriture de présentation non prise en charge pour le format « " + format + " »")

func save(prs, path, format=null, options=null):
    f := format if format != null else format_of(path)
    io.write_bytes(path, to_bytes(prs, f, options))
    return path

func convert(src, dst, options=null):
    return save(open(src), dst, null, options)
