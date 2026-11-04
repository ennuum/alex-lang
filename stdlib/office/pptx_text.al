# ALEX STANDARD LIBRARY — office.pptx_text
# Texte DrawingML (a:txBody) des présentations : cadres de texte, paragraphes à niveaux et puces, segments mis en
# forme (gras, italique, souligné, barré, taille, couleur, police, lien), alignement, interligne, marges,
# ajustement automatique, ancrage vertical.
#
#   use office.pptx_text as pt
#   tf := pt.TextFrame()
#   p := tf.add_paragraph("Premier point")
#   p.level = 1
#   p.add_run(" en gras", {"bold": true, "color": "C00000"})
#   tf.anchor = "middle"
#   tf.text()                                       # "Premier point en gras"
#
# TextRun(text="", fmt=null) : text bold italic underline strike size (pt) color font link highlight
#   superscript subscript   props() / set_props(dict)
# TextParagraph(text="", fmt=null) : runs level (0..8) align ("left" "center" "right" "justify") bullet (null :
#   hérité ; false : aucune ; true : puce « • » ; un caractère ; "number" : numérotation 1. 2. 3.) space_before
#   space_after (pt) line_spacing (multiple, ex. 1.2) indent (pt) font_size (taille par défaut du paragraphe)
#   add_run(text, fmt=null) -> TextRun   text()
# TextFrame(text=null) : paragraphs anchor ("top" | "middle" | "bottom") wrap (bool) autofit (null | "shrink" |
#   "resize" | false) margins ([g, h, d, b] en pt) vertical (null | "vert" | "vert270") columns
#   add_paragraph(text="", fmt=null) -> TextParagraph   set_text(texte) (un paragraphe par ligne)   text()
# Fonctions : txbody_xml(tf, tag="p:txBody") -> nœud   parse_txbody(nœud) -> TextFrame   run_props_xml(dict, tag)
#   read_run_props(nœud_a:rPr) -> dict
# Erreurs : ValueError (alignement, ancrage inconnus).

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.utils as u
use office.xml as x

const _RUN_KEYS := ["bold", "italic", "underline", "strike", "size", "color", "font", "link", "highlight", "superscript", "subscript"]

class TextRun:
    func init(text="", fmt=null):
        self.text = u.to_text(text)
        self.bold = null
        self.italic = null
        self.underline = null
        self.strike = null
        self.size = null
        self.color = null
        self.font = null
        self.link = null
        self.highlight = null
        self.superscript = null
        self.subscript = null
        if fmt != null:
            self.set_props(fmt)

    func props():
        return {"bold": self.bold, "italic": self.italic, "underline": self.underline, "strike": self.strike, "size": self.size, "color": self.color, "font": self.font, "link": self.link, "highlight": self.highlight, "superscript": self.superscript, "subscript": self.subscript}

    func set_props(d):
        for k in keys(d):
            v := d[k]
            if k == "bold":
                self.bold = v
            elif k == "italic":
                self.italic = v
            elif k == "underline":
                self.underline = v
            elif k == "strike":
                self.strike = v
            elif k == "size":
                self.size = v
            elif k == "color":
                self.color = v
            elif k == "font":
                self.font = v
            elif k == "link":
                self.link = v
            elif k == "highlight":
                self.highlight = v
            elif k == "superscript":
                self.superscript = v
            elif k == "subscript":
                self.subscript = v
        return self

class TextParagraph:
    func init(text="", fmt=null):
        self.runs = []
        self.level = 0
        self.align = null
        self.bullet = null
        self.space_before = null
        self.space_after = null
        self.line_spacing = null
        self.indent = null
        self.font_size = null
        if text != null and text != "":
            self.add_run(text, fmt)

    func add_run(text, fmt=null):
        r := TextRun(text, fmt)
        append(self.runs, r)
        return r

    func text():
        out := []
        for r in self.runs:
            append(out, r.text)
        return string.join("", out)

    # Copie indépendante (segments compris).
    func copy():
        p := TextParagraph()
        for r in self.runs:
            append(p.runs, TextRun(r.text, r.props()))
        p.level = self.level
        p.align = self.align
        p.bullet = self.bullet
        p.space_before = self.space_before
        p.space_after = self.space_after
        p.line_spacing = self.line_spacing
        p.indent = self.indent
        p.font_size = self.font_size
        return p

class TextFrame:
    func init(text=null):
        self.paragraphs = []
        self.anchor = null
        self.wrap = true
        self.autofit = null
        self.margins = null
        self.vertical = null
        self.columns = null
        if text != null:
            self.set_text(text)

    func add_paragraph(text="", fmt=null):
        p := TextParagraph(text, fmt)
        append(self.paragraphs, p)
        return p

    func set_text(text):
        self.paragraphs = []
        for line in string.split(string.replace(u.to_text(text), "\r\n", "\n"), "\n"):
            self.add_paragraph(line)
        return self

    func text():
        out := []
        for p in self.paragraphs:
            append(out, p.text())
        return string.join("\n", out)

# ---------------------------------------------------------------------------------------------- écriture

func _hp(pt):
    return str(to_int(u.round_to(to_float(pt) * 100.0, 0)))

# Propriétés de segment -> a:rPr (ou a:endParaRPr / a:defRPr selon `tag`). link : ctx.link_rel(url) fournit le rId.
func run_props_xml(p, tag="a:rPr", ctx=null):
    attrs := {"lang": "fr-FR"}
    g := (k) => u.get(p, k, null) if p != null else null
    if g("size") != null:
        attrs["sz"] = _hp(g("size"))
    if p != null and contains_key(p, "bold") and p["bold"] != null:
        attrs["b"] = "1" if p["bold"] else "0"
    if p != null and contains_key(p, "italic") and p["italic"] != null:
        attrs["i"] = "1" if p["italic"] else "0"
    un := g("underline")
    if un != null:
        attrs["u"] = "sng" if un == true else ("none" if un == false else un)
    st := g("strike")
    if st != null:
        attrs["strike"] = "sngStrike" if st == true else "noStrike"
    if g("superscript") == true:
        attrs["baseline"] = "30000"
    elif g("subscript") == true:
        attrs["baseline"] = "-25000"
    attrs["dirty"] = "0"
    kids := []
    if g("color") != null:
        append(kids, x.el("a:solidFill", null, [x.el("a:srgbClr", {"val": u.color_hex(g("color"))})]))
    if g("highlight") != null:
        append(kids, x.el("a:highlight", null, [x.el("a:srgbClr", {"val": u.color_hex(g("highlight"))})]))
    if g("font") != null:
        append(kids, x.el("a:latin", {"typeface": g("font")}))
        append(kids, x.el("a:cs", {"typeface": g("font")}))
    if g("link") != null and ctx != null:
        link := g("link")
        if string.starts_with(link, "#slide"):
            append(kids, x.el("a:hlinkClick", {"r:id": ctx.slide_link_rel(to_int(u.parse_number(_n.str_slice(link, 6, null)))), "action": "ppaction://hlinksldjump"}))
        else:
            append(kids, x.el("a:hlinkClick", {"r:id": ctx.link_rel(link)}))
    return x.el(tag, attrs, kids)

func _align(a):
    if a == null:
        return null
    l := string.lower(a)
    if l == "left" or l == "gauche":
        return "l"
    if l == "center" or l == "centre":
        return "ctr"
    if l == "right" or l == "droite":
        return "r"
    if l == "justify" or l == "justifié":
        return "just"
    if l == "distributed":
        return "dist"
    raise("ValueError", "alignement inconnu : '" + a + "' (left, center, right, justify)")

func _ppr(p):
    attrs := {}
    if p.level != null and p.level > 0:
        attrs["lvl"] = str(p.level)
    al := _align(p.align)
    if al != null:
        attrs["algn"] = al
    kids := []
    if p.indent != null:
        attrs["marL"] = str(u.pt_to_emu(p.indent))
        attrs["indent"] = str(-u.pt_to_emu(18))
    if p.line_spacing != null:
        append(kids, x.el("a:lnSpc", null, [x.el("a:spcPct", {"val": str(to_int(u.round_to(to_float(p.line_spacing) * 100000.0, 0)))})]))
    if p.space_before != null:
        append(kids, x.el("a:spcBef", null, [x.el("a:spcPts", {"val": _hp(p.space_before)})]))
    if p.space_after != null:
        append(kids, x.el("a:spcAft", null, [x.el("a:spcPts", {"val": _hp(p.space_after)})]))
    b := p.bullet
    if b == false:
        append(kids, x.el("a:buNone"))
    elif b == "number":
        if not contains_key(attrs, "marL"):
            attrs["marL"] = str(342900 + 457200 * (p.level if p.level != null else 0))
            attrs["indent"] = "-342900"
        append(kids, x.el("a:buFont", {"typeface": "+mj-lt"}))
        append(kids, x.el("a:buAutoNum", {"type": "arabicPeriod"}))
    elif b == true or type(b) == "str":
        ch := "•" if b == true else b
        if not contains_key(attrs, "marL"):
            attrs["marL"] = str(285750 + 457200 * (p.level if p.level != null else 0))
            attrs["indent"] = "-285750"
        append(kids, x.el("a:buFont", {"typeface": "Arial", "panose": "020B0604020202020204", "pitchFamily": "34", "charset": "0"}))
        append(kids, x.el("a:buChar", {"char": ch}))
    if len(keys(attrs)) == 0 and len(kids) == 0:
        return null
    return x.el("a:pPr", attrs, kids)

func _para_xml(p, ctx):
    kids := []
    pp := _ppr(p)
    if pp != null:
        append(kids, pp)
    for r in p.runs:
        props := r.props()
        if props["size"] == null and p.font_size != null:
            props["size"] = p.font_size
        parts := string.split(r.text, "\n")
        i := 0
        for part in parts:
            if i > 0:
                append(kids, x.el("a:br", null, [run_props_xml(props, "a:rPr", ctx)]))
            if part != "":
                append(kids, x.el("a:r", null, [run_props_xml(props, "a:rPr", ctx), x.el("a:t", null, [part])]))
            i = i + 1
    end := {"size": p.font_size} if p.font_size != null else (p.runs[len(p.runs) - 1].props() if len(p.runs) > 0 else null)
    if end != null:
        e2 := u.merge(end, {"link": null})
        append(kids, run_props_xml(e2, "a:endParaRPr", null))
    else:
        append(kids, x.el("a:endParaRPr", {"lang": "fr-FR", "dirty": "0"}))
    return x.el("a:p", null, kids)

func txbody_xml(tf, tag="p:txBody", ctx=null):
    attrs := {"rtlCol": "0"}
    if not tf.wrap:
        attrs["wrap"] = "none"
    else:
        attrs["wrap"] = "square"
    if tf.margins != null:
        m := tf.margins
        attrs["lIns"] = str(u.pt_to_emu(m[0]))
        attrs["tIns"] = str(u.pt_to_emu(m[1]))
        attrs["rIns"] = str(u.pt_to_emu(m[2]))
        attrs["bIns"] = str(u.pt_to_emu(m[3]))
    if tf.anchor != null:
        a := string.lower(tf.anchor)
        attrs["anchor"] = "t" if a == "top" else ("ctr" if a == "middle" or a == "center" else ("b" if a == "bottom" else a))
    if tf.vertical != null:
        attrs["vert"] = tf.vertical
    if tf.columns != null and tf.columns > 1:
        attrs["numCol"] = str(tf.columns)
    bkids := []
    if tf.autofit == "shrink":
        append(bkids, x.el("a:normAutofit"))
    elif tf.autofit == "resize":
        append(bkids, x.el("a:spAutoFit"))
    elif tf.autofit == false:
        append(bkids, x.el("a:noAutofit"))
    kids := [x.el("a:bodyPr", attrs, bkids), x.el("a:lstStyle")]
    if len(tf.paragraphs) == 0:
        append(kids, x.el("a:p", null, [x.el("a:endParaRPr", {"lang": "fr-FR", "dirty": "0"})]))
    for p in tf.paragraphs:
        append(kids, _para_xml(p, ctx))
    return x.el(tag, null, kids)

# ---------------------------------------------------------------------------------------------- lecture

func read_run_props(rpr, rels=null):
    p := {}
    if rpr == null:
        return p
    sz := x.attr_int(rpr, "sz", null)
    if sz != null:
        p["size"] = to_float(sz) / 100.0
    b := x.attr(rpr, "b", null)
    if b != null:
        p["bold"] = b == "1" or b == "true"
    i := x.attr(rpr, "i", null)
    if i != null:
        p["italic"] = i == "1" or i == "true"
    un := x.attr(rpr, "u", null)
    if un != null:
        p["underline"] = false if un == "none" else (true if un == "sng" else un)
    st := x.attr(rpr, "strike", null)
    if st != null:
        p["strike"] = st != "noStrike"
    bl := x.attr_int(rpr, "baseline", 0)
    if bl > 0:
        p["superscript"] = true
    elif bl < 0:
        p["subscript"] = true
    sf := x.first(rpr, "a:solidFill")
    if sf != null:
        c := x.first(sf, "a:srgbClr")
        if c != null:
            p["color"] = string.upper(x.attr(c, "val", "000000"))
    lat := x.first(rpr, "a:latin")
    if lat != null and not string.starts_with(x.attr(lat, "typeface", "+"), "+"):
        p["font"] = x.attr(lat, "typeface")
    hl := x.first(rpr, "a:hlinkClick")
    if hl != null and rels != null:
        rid := x.attr(hl, "r:id", null)
        if rid != null:
            t := rels(rid)
            if t != null:
                p["link"] = t
    return p

func parse_txbody(el, rels=null):
    tf := TextFrame()
    if el == null:
        return tf
    bp := x.first(el, "a:bodyPr")
    if bp != null:
        a := x.attr(bp, "anchor", null)
        if a != null:
            tf.anchor = "top" if a == "t" else ("middle" if a == "ctr" else ("bottom" if a == "b" else a))
        tf.wrap = x.attr(bp, "wrap", "square") != "none"
        if x.first(bp, "a:normAutofit") != null:
            tf.autofit = "shrink"
        elif x.first(bp, "a:spAutoFit") != null:
            tf.autofit = "resize"
        tf.vertical = x.attr(bp, "vert", null)
        if tf.vertical == "horz":
            tf.vertical = null
    for pe in x.children(el, "a:p"):
        p := TextParagraph()
        ppr := x.first(pe, "a:pPr")
        if ppr != null:
            p.level = x.attr_int(ppr, "lvl", 0)
            al := x.attr(ppr, "algn", null)
            if al != null:
                p.align = {"l": "left", "ctr": "center", "r": "right", "just": "justify", "dist": "distributed"}[al] if contains_key({"l": 1, "ctr": 1, "r": 1, "just": 1, "dist": 1}, al) else null
            if x.first(ppr, "a:buNone") != null:
                p.bullet = false
            elif x.first(ppr, "a:buAutoNum") != null:
                p.bullet = "number"
            elif x.first(ppr, "a:buChar") != null:
                p.bullet = x.attr(x.first(ppr, "a:buChar"), "char", "•")
        for c in x.children(pe):
            ln := x.local_name(c["tag"])
            if ln == "r" or ln == "fld":
                t := x.first(c, "a:t")
                r := TextRun(x.text(t) if t != null else "")
                r.set_props(read_run_props(x.first(c, "a:rPr"), rels))
                append(p.runs, r)
            elif ln == "br":
                if len(p.runs) > 0:
                    p.runs[len(p.runs) - 1].text = p.runs[len(p.runs) - 1].text + "\n"
                else:
                    append(p.runs, TextRun("\n"))
        append(tf.paragraphs, p)
    return tf
