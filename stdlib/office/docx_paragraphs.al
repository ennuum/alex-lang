# ALEX STANDARD LIBRARY — office.docx_paragraphs
# Paragraphes et segments de texte (runs) WordprocessingML : mise en forme des caractères et des paragraphes,
# liens hypertexte, tabulations, sauts, champs (PAGE, NUMPAGES, TOC...), images, listes.
#
#   use office.docx_paragraphs as dp
#   p := dp.Paragraph()
#   p.add_run("Gras ", true)                          # positionnel : bold, italic, underline, strike, size...
#   p.add_run("rouge", {"color": "rouge", "size": 14})  # ou dict de format (pas d'arguments nommés sur les méthodes)
#   p.add_link("le site", "https://example.org")
#   p.align = "justify"
#   p.space_after = 6                                  # points
#   p.text()                                           # "Gras rouge le site"
#
# Run(text="", ...) : text bold italic underline (true ou "double", "dotted"...) strike size (pt) color font
#   highlight superscript subscript caps small_caps style (style de caractère) link (URL ou "#signet")
#   kind : "text" | "tab" | "break" | "image" | "field"   break_type ("line" | "page" | "column")
#   image (docx_images.InlineImage)   field (instruction, ex. "PAGE")
#   Un "\n" dans le texte devient un saut de ligne, un "\t" une tabulation.
#   props() -> dict   copy_format(autre_run)   copy()
# Paragraph(text="", style=null) : runs style align space_before space_after line_spacing indent_left
#   indent_right indent_first keep_next keep_lines page_break_before shading border_bottom tabs bookmark
#   list ({"kind": "bullet"|"number", "level": 0.., "list_id": n}) mark (dict : format de la marque de paragraphe)
#   add_run(text, bold=null, italic=null, underline=null, strike=null, size=null, color=null, font=null,
#           highlight=null, superscript=null, subscript=null, style=null) -> Run
#           (ou add_run(text, {"bold": true, "size": 14, "link": "https://..."}) : dict de format)
#   add_text (alias)  add_link(text, url, ...) -> Run  add_tab()  add_break(kind="line")
#   add_image(image, width=null, height=null, description="") -> Run   add_field(instr, placeholder="")
#   text()  set_text(texte)  is_empty()  heading_level() (Heading1..9 -> 1..9, Title -> 0, sinon null)
#   replace(ancien, nouveau) -> nombre (dans chaque run ; voir aussi templates pour le texte réparti sur plusieurs runs)
#   merge_runs() (fusionne les runs voisins de même format)   props() -> dict   to_xml(ctx)
# Fonctions : parse_paragraph(nœud_w:p, rctx) -> Paragraph    page_break() -> Paragraph
#   rctx (lecture) : rctx.link(rid) -> url ; rctx.image(info) -> core.Image ou null ; rctx.list_kind(numId, ilvl)
#   ctx (écriture) : ctx.link_rel(url) -> rId ; ctx.image_rel(image) -> rId ; ctx.next_shape_id() ;
#   ctx.list_num(kind, list_id) -> numId
# Erreurs : DOCXError, ValueError, TypeError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.docx_styles as styles
use office.docx_images as dimg

const _RUN_FIELDS := ["bold", "italic", "underline", "strike", "size", "color", "font", "highlight", "superscript", "subscript", "caps", "small_caps", "style"]

class Run:
    func init(text="", bold=null, italic=null, underline=null, strike=null, size=null, color=null, font=null, highlight=null, superscript=null, subscript=null, style=null):
        if type(text) != "str":
            text = u.to_text(text)
        self.text = text
        self.kind = "text"
        self.bold = bold
        self.italic = italic
        self.underline = underline
        self.strike = strike
        self.size = size
        self.color = color
        self.font = font
        self.highlight = highlight
        self.superscript = superscript
        self.subscript = subscript
        self.caps = null
        self.small_caps = null
        self.style = style
        self.link = null
        self.break_type = null
        self.image = null
        self.field = null

    func props():
        return {"style": self.style, "font": self.font, "bold": self.bold, "italic": self.italic, "caps": self.caps, "small_caps": self.small_caps, "strike": self.strike, "color": self.color, "size": self.size, "highlight": self.highlight, "underline": self.underline, "superscript": self.superscript, "subscript": self.subscript}

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
            elif k == "highlight":
                self.highlight = v
            elif k == "superscript":
                self.superscript = v
            elif k == "subscript":
                self.subscript = v
            elif k == "caps":
                self.caps = v
            elif k == "small_caps":
                self.small_caps = v
            elif k == "style":
                self.style = v
        return self

    func copy_format(other):
        self.set_props(other.props())
        return self

    func copy():
        r := Run(self.text)
        r.copy_format(self)
        r.kind = self.kind
        r.link = self.link
        r.break_type = self.break_type
        r.image = self.image
        r.field = self.field
        return r

    func same_format(other):
        return self.props() == other.props() and self.link == other.link and self.kind == "text" and other.kind == "text"

    func _content(kids):
        if self.kind == "tab":
            append(kids, x.el("w:tab"))
            return null
        if self.kind == "break":
            bt := self.break_type
            if bt == null or bt == "line":
                append(kids, x.el("w:br"))
            else:
                append(kids, x.el("w:br", {"w:type": bt}))
            return null
        buf := ""
        for c in self.text:
            ch := str(c)
            if ch == "\n" or ch == "\t":
                if buf != "":
                    append(kids, _t(buf))
                    buf = ""
                append(kids, x.el("w:br") if ch == "\n" else x.el("w:tab"))
            else:
                buf = buf + ch
        if buf != "":
            append(kids, _t(buf))

    func to_xml(ctx):
        props := self.props()
        if self.link != null and self.style == null:
            props["style"] = "Hyperlink"
        rpr := styles.run_props_xml(props)
        if self.kind == "field":
            # champ complexe : begin / instruction / separate / résultat / end (Word le met à jour)
            out := []
            append(out, _run(rpr, [x.el("w:fldChar", {"w:fldCharType": "begin", "w:dirty": "true"})]))
            append(out, _run(rpr, [x.el("w:instrText", {"xml:space": "preserve"}, [" " + self.field + " "])]))
            append(out, _run(rpr, [x.el("w:fldChar", {"w:fldCharType": "separate"})]))
            res := []
            self._content(res)
            if len(res) > 0:
                append(out, _run(rpr, res))
            append(out, _run(rpr, [x.el("w:fldChar", {"w:fldCharType": "end"})]))
            return out
        kids := []
        if self.kind == "image":
            append(kids, self.image.to_xml(ctx))
        else:
            self._content(kids)
        return [_run(rpr, kids)]

func _run(rpr, content):
    kids := []
    if rpr != null:
        append(kids, rpr)
    for c in content:
        append(kids, c)
    return x.el("w:r", null, kids)

func _t(s):
    if string.starts_with(s, " ") or string.ends_with(s, " ") or string.contains(s, "  "):
        return x.el("w:t", {"xml:space": "preserve"}, [s])
    return x.el("w:t", null, [s])

# ---------------------------------------------------------------------------------------------- Paragraph

class Paragraph:
    func init(text="", style=null):
        self.runs = []
        self.style = style
        self.align = null
        self.space_before = null
        self.space_after = null
        self.line_spacing = null
        self.indent_left = null
        self.indent_right = null
        self.indent_first = null
        self.keep_next = null
        self.keep_lines = null
        self.page_break_before = null
        self.shading = null
        self.border_bottom = null
        self.tabs = null
        self.bookmark = null
        self.list = null
        self.num_id = null
        self.num_level = 0
        self.mark = null
        self.outline_level = null
        if text != null and text != "":
            self.add_run(text)

    # add_run(texte, format) : `format` peut être un dict {"bold": true, "color": "rouge", "link": url...} (les
    # arguments nommés ne sont pas disponibles pour les méthodes en ALEX), ou les valeurs positionnelles.
    func add_run(text="", bold=null, italic=null, underline=null, strike=null, size=null, color=null, font=null, highlight=null, superscript=null, subscript=null, style=null):
        r := null
        if type(bold) == "dict":
            r = Run(text)
            r.set_props(bold)
            if contains_key(bold, "link"):
                r.link = bold["link"]
        else:
            r = Run(text, bold, italic, underline, strike, size, color, font, highlight, superscript, subscript, style)
        append(self.runs, r)
        return r

    func add_text(text, bold=null, italic=null, underline=null, size=null, color=null, font=null):
        return self.add_run(text, bold, italic, underline, null, size, color, font)

    func add_link(text, url, bold=null, italic=null, color=null, size=null):
        r := self.add_run(text, bold, italic, null, null, size, color)
        r.link = url
        return r

    func add_tab():
        r := Run("")
        r.kind = "tab"
        append(self.runs, r)
        return r

    func add_break(kind="line"):
        if kind != "line" and kind != "page" and kind != "column":
            raise("ValueError", "type de saut inconnu : '" + str(kind) + "' (line, page, column)")
        r := Run("")
        r.kind = "break"
        r.break_type = kind
        append(self.runs, r)
        return r

    func add_image(image, width=null, height=null, description="", floating=false, align=null):
        img := image
        if not isinstance(image, dimg.InlineImage):
            img = dimg.InlineImage(image, width, height, description, null, floating, align)
        r := Run("")
        r.kind = "image"
        r.image = img
        append(self.runs, r)
        return r

    # Champ Word (« PAGE », « NUMPAGES », « DATE \@ "dd/MM/yyyy" », « TOC \o "1-3" \h \z \u »...).
    func add_field(instr, placeholder=""):
        r := Run(placeholder)
        r.kind = "field"
        r.field = instr
        append(self.runs, r)
        return r

    func text():
        out := []
        for r in self.runs:
            if r.kind == "text" or r.kind == "field":
                append(out, r.text)
            elif r.kind == "tab":
                append(out, "\t")
            elif r.kind == "break" and (r.break_type == null or r.break_type == "line"):
                append(out, "\n")
        return string.join("", out)

    # Remplace le contenu par un seul run qui garde le format du premier run texte.
    func set_text(value):
        first := null
        for r in self.runs:
            if r.kind == "text":
                first = r
                break
        nr := Run(u.to_text(value))
        if first != null:
            nr.copy_format(first)
        self.runs = [nr]
        return self

    func is_empty():
        for r in self.runs:
            if r.kind == "image" or r.kind == "field":
                return false
            if r.kind == "text" and r.text != "":
                return false
        return true

    func heading_level():
        if self.style == null:
            return null
        s := self.style
        if s == "Title":
            return 0
        if string.starts_with(s, "Heading") and len(s) == 8:
            v := _n.num_parse(_n.str_slice(s, 7, null))
            if v != null:
                return to_int(v)
        if self.outline_level != null and self.outline_level < 9:
            return self.outline_level + 1
        return null

    func replace(old, new_text):
        n := 0
        for r in self.runs:
            if r.kind == "text" and string.contains(r.text, old):
                n = n + string.count(r.text, old)
                r.text = string.replace(r.text, old, new_text)
        return n

    func merge_runs():
        out := []
        for r in self.runs:
            if len(out) > 0 and out[len(out) - 1].same_format(r):
                out[len(out) - 1].text = out[len(out) - 1].text + r.text
            else:
                append(out, r)
        self.runs = out
        return self

    func props():
        return {"style": self.style, "keep_next": self.keep_next, "keep_lines": self.keep_lines, "page_break_before": self.page_break_before, "border_bottom": self.border_bottom, "shading": self.shading, "tabs": self.tabs, "space_before": self.space_before, "space_after": self.space_after, "line_spacing": self.line_spacing, "indent_left": self.indent_left, "indent_right": self.indent_right, "indent_first": self.indent_first, "align": self.align, "outline_level": self.outline_level}

    func set_props(d):
        for k in keys(d):
            v := d[k]
            if k == "style":
                self.style = v
            elif k == "keep_next":
                self.keep_next = v
            elif k == "keep_lines":
                self.keep_lines = v
            elif k == "page_break_before":
                self.page_break_before = v
            elif k == "border_bottom":
                self.border_bottom = v
            elif k == "shading":
                self.shading = v
            elif k == "tabs":
                self.tabs = v
            elif k == "space_before":
                self.space_before = v
            elif k == "space_after":
                self.space_after = v
            elif k == "line_spacing":
                self.line_spacing = v
            elif k == "indent_left":
                self.indent_left = v
            elif k == "indent_right":
                self.indent_right = v
            elif k == "indent_first":
                self.indent_first = v
            elif k == "align":
                self.align = v
            elif k == "outline_level":
                self.outline_level = v
            elif k == "num_id":
                self.num_id = v
            elif k == "num_level":
                self.num_level = v
            elif k == "run":
                self.mark = v
        return self

    # Copie indépendante (segments compris).
    func copy():
        p := Paragraph("", self.style)
        p.set_props(self.props())
        p.list = u.deep_copy(self.list)
        p.num_id = self.num_id
        p.num_level = self.num_level
        p.mark = u.deep_copy(self.mark)
        p.bookmark = self.bookmark
        p.tabs = u.deep_copy(self.tabs)
        for r in self.runs:
            append(p.runs, r.copy())
        return p

    func to_xml(ctx):
        props := self.props()
        if self.list != null:
            props["num_id"] = ctx.list_num(self.list["kind"], u.get(self.list, "list_id", 0))
            props["num_level"] = u.get(self.list, "level", 0)
            if props["style"] == null:
                props["style"] = "ListParagraph"
        elif self.num_id != null:
            props["num_id"] = self.num_id
            props["num_level"] = self.num_level
        kids := []
        ppr := styles.para_props_xml(props, self.mark)
        if ppr != null:
            append(kids, ppr)
        bm_id := null
        if self.bookmark != null:
            bm_id = str(ctx.next_bookmark_id())
            append(kids, x.el("w:bookmarkStart", {"w:id": bm_id, "w:name": self.bookmark}))
        i := 0
        n := len(self.runs)
        while i < n:
            r := self.runs[i]
            if r.link == null:
                for e in r.to_xml(ctx):
                    append(kids, e)
                i = i + 1
                continue
            # runs consécutifs vers le même lien : un seul w:hyperlink
            link := r.link
            group := []
            while i < n and self.runs[i].link == link:
                for e in self.runs[i].to_xml(ctx):
                    append(group, e)
                i = i + 1
            attrs := {}
            if string.starts_with(link, "#"):
                attrs["w:anchor"] = _n.str_slice(link, 1, null)
            else:
                attrs["r:id"] = ctx.link_rel(link)
            attrs["w:history"] = "1"
            append(kids, x.el("w:hyperlink", attrs, group))
        if bm_id != null:
            append(kids, x.el("w:bookmarkEnd", {"w:id": bm_id}))
        return x.el("w:p", null, kids)

# Paragraphe contenant un saut de page.
func page_break():
    p := Paragraph()
    p.add_break("page")
    return p

# ---------------------------------------------------------------------------------------------- lecture

func _sym_char(el):
    c := x.attr(el, "w:char", null)
    if c == null:
        return ""
    v := 0
    b := _n.hex_decode(u.pad_left(c, 4, "0"))
    v = (b[0] << 8) | b[1]
    if v >= 61440:
        v = v - 61440
    if v <= 0:
        return ""
    return str(string.chr(v))

# Lit un w:r et ajoute un ou plusieurs Run à `out`.
func _read_run(r, props, link, rctx, out):
    buf := []
    cur := Run("")
    cur.set_props(props)
    cur.link = link
    for c in x.children(r):
        ln := x.local_name(c["tag"])
        if ln == "t" or ln == "delText":
            if ln == "t":
                append(buf, x.text(c))
        elif ln == "tab" or ln == "ptab":
            append(buf, "\t")
        elif ln == "br" or ln == "cr":
            bt := x.attr(c, "w:type", "textWrapping")
            if bt == "page" or bt == "column":
                if len(buf) > 0:
                    t := Run(string.join("", buf))
                    t.set_props(props)
                    t.link = link
                    append(out, t)
                    buf = []
                b := Run("")
                b.kind = "break"
                b.break_type = bt
                append(out, b)
            else:
                append(buf, "\n")
        elif ln == "noBreakHyphen":
            append(buf, "-")
        elif ln == "sym":
            append(buf, _sym_char(c))
        elif ln == "drawing" or ln == "pict" or ln == "object":
            info := dimg.parse_drawing(c)
            if info != null and info["rid"] != null:
                img := rctx.image(info)
                if img != null:
                    if len(buf) > 0:
                        t := Run(string.join("", buf))
                        t.set_props(props)
                        t.link = link
                        append(out, t)
                        buf = []
                    im := Run("")
                    im.kind = "image"
                    try:
                        cx := info["cx"]
                        cy := info["cy"]
                        im.image = dimg.InlineImage(img, cx if cx > 0 else null, cy if cy > 0 else null, info["description"], info["name"], info["floating"])
                    catch e:
                        im.image = null
                    if im.image != null:
                        append(out, im)
    if len(buf) > 0:
        t := Run(string.join("", buf))
        t.set_props(props)
        t.link = link
        append(out, t)

func _read_inline(node, p, link, rctx, state):
    for c in x.children(node):
        ln := x.local_name(c["tag"])
        if ln == "r":
            # champs complexes : on ignore l'instruction, on garde le résultat affiché
            fc := x.first(c, "w:fldChar")
            if fc != null:
                t := x.attr(fc, "w:fldCharType", "")
                if t == "begin":
                    state["in_instr"] = true
                elif t == "separate":
                    state["in_instr"] = false
                elif t == "end":
                    state["in_instr"] = false
                continue
            if state["in_instr"]:
                continue
            props := styles.read_run_props(x.first(c, "w:rPr"))
            _read_run(c, props, link, rctx, p.runs)
        elif ln == "hyperlink":
            url := null
            rid := x.attr(c, "r:id", null)
            if rid != null:
                url = rctx.link(rid)
            anc := x.attr(c, "w:anchor", null)
            if url == null and anc != null:
                url = "#" + anc
            _read_inline(c, p, url, rctx, state)
        elif ln == "ins" or ln == "smartTag" or ln == "customXml" or ln == "fldSimple" or ln == "dir" or ln == "bdo":
            _read_inline(c, p, link, rctx, state)
        elif ln == "sdt":
            content := x.first(c, "w:sdtContent")
            if content != null:
                _read_inline(content, p, link, rctx, state)
        elif ln == "bookmarkStart":
            nm := x.attr(c, "w:name", "")
            if nm != "" and nm != "_GoBack" and p.bookmark == null:
                p.bookmark = nm
        elif ln == "oMath" or ln == "oMathPara":
            t := []
            for m in x.find_all(c, "m:t"):
                append(t, x.text(m))
            if len(t) > 0:
                append(p.runs, Run(string.join("", t)))

func parse_paragraph(node, rctx):
    p := Paragraph()
    pp := styles.read_para_props(x.first(node, "w:pPr"))
    p.set_props(pp)
    if p.num_id != null and p.num_id != 0:
        kind := rctx.list_kind(p.num_id, p.num_level)
        if kind != null:
            p.list = {"kind": kind, "level": p.num_level, "list_id": p.num_id}
    _read_inline(node, p, null, rctx, {"in_instr": false})
    return p
