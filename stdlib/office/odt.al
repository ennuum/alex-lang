# ALEX STANDARD LIBRARY — office.odt
# Textes OpenDocument (.odt, LibreOffice Writer) : lecture vers le modèle neutre office.document et écriture depuis
# celui-ci — titres (plan), paragraphes mis en forme (gras, italique, souligné, barré, couleur, taille, police,
# exposant, indice, liens), listes à puces / numérotées imbriquées, tableaux (ligne d'en-tête répétée), images
# incorporées avec légende, blocs de code, citations, filets, sauts de page, métadonnées.
#
#   use office.odt as odt
#   use office.document as document
#   d := document.new("Compte rendu")
#   d.add_heading("Décisions", 1)
#   d.add_paragraph("Le budget est **validé**.", true)
#   odt.save(d, "cr.odt")
#
#   d2 := odt.read("cr.odt")              # -> document.Document
#   print(d2.to_markdown())
#   odt.read_text("cr.odt")               # texte brut
#
# read(chemin_ou_octets) -> document.Document   read_text(src) -> str
# write(document) -> octets   save(document, chemin) -> chemin   (options : {"size": "A4", "landscape": false,
#   "margins": "2cm", "font": "Liberation Serif", "font_size": 12, "page_numbers": true})
# from_markdown(md, chemin=null) / from_html(html, chemin=null) : raccourcis (octets si chemin est null)
# Erreurs : ODFError, FormatError, ArchiveError, XMLError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.odf as odf
use office.document as document

const _HEADING_STYLES := ["Heading_20_1", "Heading_20_2", "Heading_20_3", "Heading_20_4", "Heading_20_5", "Heading_20_6"]
const _MONO := "Liberation Mono"
const _ALIGN_OUT := {"center": "center", "right": "end", "justify": "justify", "start": "start", "end": "end", "both": "justify"}

# ============================================================================================== écriture

func _sty(name, display, family, parent, para_props, text_props, extra=null):
    attrs := {"style:name": name, "style:family": family}
    if display != null:
        attrs["style:display-name"] = display
    if parent != null:
        attrs["style:parent-style-name"] = parent
    if extra != null:
        for k in keys(extra):
            attrs[k] = extra[k]
    kids := []
    if para_props != null:
        append(kids, x.el("style:paragraph-properties", para_props, []))
    if text_props != null:
        append(kids, x.el("style:text-properties", text_props, []))
    return x.el("style:style", attrs, kids)

func _list_style(name, ordered):
    levels := []
    k := 1
    bullets := ["•", "◦", "▪"]
    while k <= 10:
        indent := 0.635 * to_float(k)
        props := x.el("style:list-level-properties", {"text:list-level-position-and-space-mode": "label-alignment"}, [x.el("style:list-level-label-alignment", {"text:label-followed-by": "listtab", "text:list-tab-stop-position": u.format_number(u.round_to(indent, 3)) + "cm", "fo:text-indent": "-0.635cm", "fo:margin-left": u.format_number(u.round_to(indent, 3)) + "cm"}, [])])
        if ordered:
            fmt := ["1", "a", "i"][(k - 1) % 3]
            append(levels, x.el("text:list-level-style-number", {"text:level": str(k), "text:style-name": "Numbering_20_Symbols", "style:num-suffix": ".", "style:num-format": fmt}, [props]))
        else:
            append(levels, x.el("text:list-level-style-bullet", {"text:level": str(k), "text:style-name": "Bullet_20_Symbols", "text:bullet-char": bullets[(k - 1) % 3]}, [props]))
        k = k + 1
    return x.el("text:list-style", {"style:name": name}, levels)

func _styles_xml(o):
    font := u.get(o, "font", "Liberation Serif")
    size := u.format_number(u.get(o, "font_size", 12)) + "pt"
    wh := core.page_size(u.get(o, "size", "A4"), u.get(o, "landscape", false))
    margin := odf.length(odf.to_pt(u.get(o, "margins", "2cm"), 56.7))
    root := odf.document_root("office:document-styles")
    faces := x.el("office:font-face-decls", null, [])
    for f in [font, "Liberation Sans", _MONO]:
        append(faces["children"], x.el("style:font-face", {"style:name": f, "svg:font-family": "'" + f + "'", "style:font-family-generic": "modern" if f == _MONO else ("swiss" if f == "Liberation Sans" else "roman"), "style:font-pitch": "fixed" if f == _MONO else "variable"}, []))
    append(root["children"], faces)
    st := x.el("office:styles", null, [])
    kids := st["children"]
    append(kids, x.el("style:default-style", {"style:family": "paragraph"}, [x.el("style:paragraph-properties", {"style:writing-mode": "page", "style:tab-stop-distance": "1.25cm"}, []), x.el("style:text-properties", {"style:font-name": font, "fo:font-size": size, "fo:language": "fr", "fo:country": "FR", "style:font-size-asian": size, "style:font-size-complex": size}, [])]))
    append(kids, x.el("style:default-style", {"style:family": "table"}, [x.el("style:table-properties", {"table:border-model": "collapsing"}, [])]))
    append(kids, x.el("style:style", {"style:name": "Graphics", "style:family": "graphic"}, [x.el("style:graphic-properties", {"text:anchor-type": "paragraph", "svg:x": "0cm", "svg:y": "0cm", "style:wrap": "none", "style:vertical-pos": "top", "style:vertical-rel": "paragraph", "style:horizontal-pos": "center", "style:horizontal-rel": "paragraph"}, [])]))
    append(kids, x.el("style:default-style", {"style:family": "graphic"}, [x.el("style:graphic-properties", {"draw:stroke": "none", "draw:fill": "none", "style:wrap": "none"}, [])]))
    append(kids, _sty("Standard", null, "paragraph", null, null, null, {"style:class": "text"}))
    append(kids, _sty("Heading", null, "paragraph", "Standard", {"fo:margin-top": "0.423cm", "fo:margin-bottom": "0.212cm", "fo:keep-with-next": "always"}, {"style:font-name": "Liberation Sans", "fo:font-family": "'Liberation Sans'", "fo:font-size": "14pt", "fo:color": "#1F3864"}, {"style:next-style-name": "Text_20_body", "style:class": "text"}))
    sizes := ["20pt", "16pt", "14pt", "13pt", "12pt", "12pt"]
    lvl := 1
    while lvl <= 6:
        tp := {"fo:font-size": sizes[lvl - 1], "fo:font-weight": "bold", "style:font-weight-asian": "bold", "style:font-weight-complex": "bold"}
        if lvl >= 5:
            tp["fo:font-style"] = "italic"
        append(kids, _sty("Heading_20_" + str(lvl), "Heading " + str(lvl), "paragraph", "Heading", null, tp, {"style:next-style-name": "Text_20_body", "style:default-outline-level": str(lvl), "style:class": "text"}))
        lvl = lvl + 1
    append(kids, _sty("Text_20_body", "Text body", "paragraph", "Standard", {"fo:margin-top": "0cm", "fo:margin-bottom": "0.247cm", "fo:line-height": "115%"}, null, {"style:class": "text"}))
    append(kids, _sty("Title", null, "paragraph", "Heading", {"fo:text-align": "center"}, {"fo:font-size": "26pt", "fo:font-weight": "bold"}, {"style:next-style-name": "Subtitle", "style:class": "chapter"}))
    append(kids, _sty("Subtitle", null, "paragraph", "Heading", {"fo:text-align": "center", "fo:margin-top": "0.106cm"}, {"fo:font-size": "16pt", "fo:color": "#595959"}, {"style:class": "chapter"}))
    append(kids, _sty("Quotations", null, "paragraph", "Standard", {"fo:margin-left": "1cm", "fo:margin-right": "1cm", "fo:margin-top": "0cm", "fo:margin-bottom": "0.25cm", "fo:padding-left": "0.2cm", "fo:border-left": "1.5pt solid #A6A6A6"}, {"fo:font-style": "italic", "fo:color": "#404040"}, {"style:class": "html"}))
    append(kids, _sty("Preformatted_20_Text", "Preformatted Text", "paragraph", "Standard", {"fo:margin-top": "0cm", "fo:margin-bottom": "0cm", "fo:background-color": "#F2F2F2"}, {"style:font-name": _MONO, "fo:font-family": "'" + _MONO + "'", "fo:font-size": "9.5pt"}, {"style:class": "html"}))
    append(kids, _sty("Caption", null, "paragraph", "Standard", {"fo:margin-top": "0.106cm", "fo:margin-bottom": "0.212cm", "fo:text-align": "center"}, {"fo:font-size": "10pt", "fo:font-style": "italic", "fo:color": "#44546A"}, {"style:class": "extra"}))
    append(kids, _sty("Figure", null, "paragraph", "Standard", {"fo:text-align": "center", "fo:margin-top": "0.2cm", "fo:margin-bottom": "0.1cm"}, null, {"style:class": "extra"}))
    append(kids, _sty("Table_20_Contents", "Table Contents", "paragraph", "Standard", {"fo:margin-top": "0.05cm", "fo:margin-bottom": "0.05cm"}, null, {"style:class": "extra"}))
    append(kids, _sty("Table_20_Heading", "Table Heading", "paragraph", "Table_20_Contents", null, {"fo:font-weight": "bold", "style:font-weight-asian": "bold", "style:font-weight-complex": "bold"}, {"style:class": "extra"}))
    append(kids, _sty("Horizontal_20_Line", "Horizontal Line", "paragraph", "Standard", {"fo:margin-top": "0cm", "fo:margin-bottom": "0.3cm", "fo:padding": "0cm", "fo:border-bottom": "0.75pt solid #A6A6A6", "fo:border-top": "none", "fo:border-left": "none", "fo:border-right": "none"}, {"fo:font-size": "6pt"}, {"style:next-style-name": "Text_20_body", "style:class": "html"}))
    append(kids, _sty("List_20_Paragraph", "List Paragraph", "paragraph", "Text_20_body", {"fo:margin-bottom": "0.1cm"}, null, {"style:class": "list"}))
    append(kids, _sty("Footer", null, "paragraph", "Standard", {"fo:text-align": "center"}, {"fo:font-size": "9pt", "fo:color": "#595959"}, {"style:class": "extra"}))
    append(kids, _sty("Source_20_Text", "Source Text", "text", null, null, {"style:font-name": _MONO, "fo:font-family": "'" + _MONO + "'"}))
    append(kids, _sty("Internet_20_link", "Internet link", "text", null, null, {"fo:color": "#0563C1", "style:text-underline-style": "solid", "style:text-underline-width": "auto", "style:text-underline-color": "font-color"}))
    append(kids, _sty("Bullet_20_Symbols", "Bullet Symbols", "text", null, null, {"style:font-name": "OpenSymbol"}))
    append(kids, _sty("Numbering_20_Symbols", "Numbering Symbols", "text", null, null, null))
    append(kids, _list_style("Liste_20_puces", false))
    append(kids, _list_style("Liste_20_numeros", true))
    append(root["children"], st)
    pl := x.el("style:page-layout", {"style:name": "pm1"}, [x.el("style:page-layout-properties", {"fo:page-width": odf.length(wh[0]), "fo:page-height": odf.length(wh[1]), "style:print-orientation": "landscape" if u.get(o, "landscape", false) else "portrait", "fo:margin-top": margin, "fo:margin-bottom": margin, "fo:margin-left": margin, "fo:margin-right": margin, "style:writing-mode": "lr-tb"}, []), x.el("style:footer-style", null, [x.el("style:header-footer-properties", {"fo:min-height": "0cm", "fo:margin-top": "0.4cm"}, [])])])
    append(root["children"], x.el("office:automatic-styles", null, [pl]))
    mp := x.el("style:master-page", {"style:name": "Standard", "style:page-layout-name": "pm1"}, [])
    if u.get(o, "page_numbers", true):
        append(mp["children"], x.el("style:footer", null, [x.el("text:p", {"text:style-name": "Footer"}, [x.el("text:page-number", {"text:select-page": "current"}, ["1"]), " / ", x.el("text:page-count", null, ["1"])])]))
    append(root["children"], x.el("office:master-styles", null, [mp]))
    return root

class _Writer:
    func init(pkg):
        self.pkg = pkg
        self.bank = odf.StyleBank()
        self.images = {}
        self.n_img = 0
        self.n_table = 0
        self.pending_break = false

    func span_style(r):
        f := {"bold": r.bold, "italic": r.italic, "underline": r.underline, "strike": r.strike, "color": r.color, "size": r.size, "font": r.font, "superscript": r.superscript, "subscript": r.subscript}
        tp := odf.text_props(f)
        if r.code and r.font == null:
            tp["style:font-name"] = _MONO
            tp["fo:font-family"] = "'" + _MONO + "'"
        if len(keys(tp)) == 0:
            return null
        return self.bank.add("text", [x.el("style:text-properties", tp, [])])

    func runs(rs):
        out := []
        for r in rs:
            kids := odf.text_nodes(r.text)
            sn := self.span_style(r)
            node := null
            if sn != null:
                node = x.el("text:span", {"text:style-name": sn}, kids)
            if r.link != null:
                inner := [node] if node != null else kids
                append(out, x.el("text:a", {"xlink:type": "simple", "xlink:href": r.link, "text:style-name": "Internet_20_link", "text:visited-style-name": "Internet_20_link"}, inner))
            elif node != null:
                append(out, node)
            else:
                for k in kids:
                    append(out, k)
        return out

    # Style de paragraphe : parent nommé + alignement / saut de page éventuels
    func para_style(parent, align=null):
        pp := {}
        if align != null and align != "left":
            pp["fo:text-align"] = u.get(_ALIGN_OUT, align, "start")
        if self.pending_break:
            pp["fo:break-before"] = "page"
            self.pending_break = false
        if len(keys(pp)) == 0:
            return parent
        return self.bank.add("paragraph", [x.el("style:paragraph-properties", pp, [])], parent)

    func image(img, width, height, alt):
        key := _n.crc32(img.data)
        name := u.get(self.images, str(key) + ":" + str(len(img.data)), null)
        if name == null:
            self.n_img = self.n_img + 1
            name = "Pictures/image" + str(self.n_img) + "." + (img.format if img.format != "jpeg" else "jpg")
            self.pkg.add_file(name, img.data, img.mime)
            self.images[str(key) + ":" + str(len(img.data))] = name
        size := _image_size(img, width, height)
        gs := self.bank.add("graphic", [x.el("style:graphic-properties", {"style:vertical-pos": "top", "style:vertical-rel": "baseline", "style:horizontal-pos": "center", "style:horizontal-rel": "paragraph", "fo:border": "none", "draw:fill": "none", "style:mirror": "none", "fo:clip": "rect(0cm, 0cm, 0cm, 0cm)"}, [])], "Graphics", null, "fr")
        frame := x.el("draw:frame", {"draw:style-name": gs, "draw:name": "Image" + str(self.n_img), "text:anchor-type": "as-char", "svg:width": odf.length(size[0]), "svg:height": odf.length(size[1]), "draw:z-index": "0"}, [x.el("draw:image", {"xlink:href": name, "xlink:type": "simple", "xlink:show": "embed", "xlink:actuate": "onLoad"}, [])])
        if alt != null and alt != "":
            append(frame["children"], x.el("svg:desc", null, [alt]))
        return frame

func _image_size(img, width, height):
    w := width
    h := height
    if w != null and type(w) == "str":
        w = odf.to_pt(w)
    if h != null and type(h) == "str":
        h = odf.to_pt(h)
    nat_w := to_float(img.width) * 72.0 / to_float(img.dpi_x if img.dpi_x != null and img.dpi_x > 0 else 96)
    nat_h := to_float(img.height) * 72.0 / to_float(img.dpi_y if img.dpi_y != null and img.dpi_y > 0 else 96)
    if nat_w <= 0.0:
        nat_w = 100.0
    if nat_h <= 0.0:
        nat_h = 100.0
    if w == null and h == null:
        w = nat_w
        h = nat_h
        if w > 453.0:
            h = h * 453.0 / w
            w = 453.0
    elif w == null:
        w = nat_w * to_float(h) / nat_h
    elif h == null:
        h = nat_h * to_float(w) / nat_w
    return [to_float(w), to_float(h)]

func _list_node(wr, blocks, i, level):
    # Construit text:list depuis blocks[i] (niveau `level`) ; renvoie [nœud, indice suivant]
    first := blocks[i]
    lst := x.el("text:list", {"text:style-name": "Liste_20_numeros" if first.ordered else "Liste_20_puces"}, [])
    if level > 0:
        lst["attrs"] = {}
    item := null
    k := i
    while k < len(blocks) and blocks[k].kind == "list_item" and blocks[k].level >= level:
        b := blocks[k]
        if b.level == level:
            if b.ordered != first.ordered and level == 0:
                break
            item = x.el("text:list-item", null, [x.el("text:p", {"text:style-name": wr.para_style("List_20_Paragraph")}, wr.runs(b.runs))])
            append(lst["children"], item)
            k = k + 1
        else:
            sub := _list_node(wr, blocks, k, level + 1)
            sub_list := sub[0]
            sub_list["attrs"]["text:style-name"] = "Liste_20_numeros" if blocks[k].ordered else "Liste_20_puces"
            if item == null:
                item = x.el("text:list-item", null, [])
                append(lst["children"], item)
            append(item["children"], sub_list)
            k = sub[1]
    return [lst, k]

func _table_node(wr, b):
    wr.n_table = wr.n_table + 1
    name := "Tableau" + str(wr.n_table)
    ncol := 0
    for r in b.rows:
        if len(r) > ncol:
            ncol = len(r)
    tprops := {"style:width": "17cm", "table:align": "margins", "fo:margin-top": "0.1cm", "fo:margin-bottom": "0.3cm"}
    if wr.pending_break:
        tprops["fo:break-before"] = "page"
        wr.pending_break = false
    ts := wr.bank.add("table", [x.el("style:table-properties", tprops, [])], null, null, "Tableau")
    cs := wr.bank.add("table-cell", [x.el("style:table-cell-properties", {"fo:padding": "0.1cm", "fo:border": "0.5pt solid #808080"}, [])])
    hs := wr.bank.add("table-cell", [x.el("style:table-cell-properties", {"fo:padding": "0.1cm", "fo:border": "0.5pt solid #808080", "fo:background-color": "#D9E2F3"}, [])])
    t := x.el("table:table", {"table:name": name, "table:style-name": ts}, [x.el("table:table-column", {"table:number-columns-repeated": str(ncol if ncol > 0 else 1)}, [])])
    ri := 0
    header := null
    for r in b.rows:
        is_head := ri == 0 and b.header
        row := x.el("table:table-row", null, [])
        c := 0
        while c < ncol:
            rs := r[c] if c < len(r) else []
            cell := x.el("table:table-cell", {"table:style-name": hs if is_head else cs, "office:value-type": "string"}, [])
            # un paragraphe par ligne de la cellule
            lines := _split_runs(rs)
            for line in lines:
                append(cell["children"], x.el("text:p", {"text:style-name": "Table_20_Heading" if is_head else "Table_20_Contents"}, wr.runs(line)))
            append(row["children"], cell)
            c = c + 1
        if is_head:
            header = x.el("table:table-header-rows", null, [row])
            append(t["children"], header)
        else:
            append(t["children"], row)
        ri = ri + 1
    return t

# Coupe une liste de segments aux "\n" -> lignes de segments
func _split_runs(rs):
    lines := [[]]
    for r in rs:
        parts := string.split(r.text, "\n")
        k := 0
        for p in parts:
            if k > 0:
                append(lines, [])
            if p != "":
                nr := document.Run(p, r.fmt())
                append(lines[len(lines) - 1], nr)
            k = k + 1
    return lines

func _body(wr, d):
    out := []
    blocks := d.blocks
    i := 0
    while i < len(blocks):
        b := blocks[i]
        k := b.kind
        if k == "heading":
            lvl := b.level
            if lvl <= 0:
                append(out, x.el("text:p", {"text:style-name": wr.para_style("Title", b.align)}, wr.runs(b.runs)))
            else:
                l6 := lvl if lvl <= 6 else 6
                append(out, x.el("text:h", {"text:style-name": wr.para_style(_HEADING_STYLES[l6 - 1], b.align), "text:outline-level": str(l6)}, wr.runs(b.runs)))
        elif k == "paragraph":
            parent := "Subtitle" if b.style == "subtitle" or b.style == "Subtitle" else ("Title" if b.style == "Title" else "Text_20_body")
            append(out, x.el("text:p", {"text:style-name": wr.para_style(parent, b.align)}, wr.runs(b.runs)))
        elif k == "list_item":
            res := _list_node(wr, blocks, i, 0)
            append(out, res[0])
            i = res[1]
            continue
        elif k == "quote":
            append(out, x.el("text:p", {"text:style-name": wr.para_style("Quotations")}, wr.runs(b.runs)))
        elif k == "code":
            first := true
            for line in string.split(string.replace(b.text, "\r\n", "\n"), "\n"):
                st := wr.para_style("Preformatted_20_Text") if first else "Preformatted_20_Text"
                append(out, x.el("text:p", {"text:style-name": st}, odf.text_nodes(line)))
                first = false
        elif k == "hr":
            append(out, x.el("text:p", {"text:style-name": wr.para_style("Horizontal_20_Line")}, []))
        elif k == "page_break":
            wr.pending_break = true
        elif k == "image":
            frame := wr.image(b.image, b.width, b.height, b.alt)
            append(out, x.el("text:p", {"text:style-name": wr.para_style("Figure")}, [frame]))
            if b.caption != null:
                append(out, x.el("text:p", {"text:style-name": "Caption"}, odf.text_nodes(b.caption)))
        elif k == "table":
            append(out, _table_node(wr, b))
        i = i + 1
    if wr.pending_break:
        append(out, x.el("text:p", {"text:style-name": wr.para_style("Text_20_body")}, []))
    return out

func write(d, options=null):
    if not isinstance(d, document.Document):
        raise("TypeError", "odt.write : document.Document attendu")
    o := options if options != null else {}
    pkg := odf.new(odf.MIME_ODT)
    pkg.metadata = d.metadata
    if pkg.metadata.title == "" and d.title != "":
        pkg.metadata.title = d.title
    wr := _Writer(pkg)
    body_kids := _body(wr, d)
    root := odf.document_root("office:document-content")
    append(root["children"], x.el("office:font-face-decls", null, [x.el("style:font-face", {"style:name": _MONO, "svg:font-family": "'" + _MONO + "'", "style:font-family-generic": "modern", "style:font-pitch": "fixed"}, [])]))
    append(root["children"], x.el("office:automatic-styles", null, wr.bank.nodes()))
    text_el := x.el("office:text", null, [x.el("text:sequence-decls", null, [x.el("text:sequence-decl", {"text:display-outline-level": "0", "text:name": "Illustration"}, []), x.el("text:sequence-decl", {"text:display-outline-level": "0", "text:name": "Table"}, [])])])
    for k in body_kids:
        append(text_el["children"], k)
    append(root["children"], x.el("office:body", null, [text_el]))
    pkg.set_xml("content.xml", root)
    pkg.set_xml("styles.xml", _styles_xml(o))
    return pkg.to_bytes()

func save(d, path, options=null):
    io.write_bytes(path, write(d, options))
    return path

func from_markdown(md, path=null, options=null):
    data := write(document.from_markdown(md), options)
    if path == null:
        return data
    io.write_bytes(path, data)
    return path

func from_html(h, path=null, options=null):
    data := write(document.from_html(h), options)
    if path == null:
        return data
    io.write_bytes(path, data)
    return path

# ============================================================================================== lecture

class _Reader:
    func init(pkg, idx):
        self.pkg = pkg
        self.idx = idx
        self.doc = document.Document()
        self._code_open = false

    func fmt_of_span(name):
        f := self.idx.text_fmt("text", name)
        return f

    func runs(node, fmt, out):
        for c in node["children"]:
            if type(c) == "str":
                t := odf._collapse(c)
                if t != "":
                    append(out, document.Run(t, _clean_fmt(fmt)))
                continue
            if not x.is_element(c):
                continue
            ln := x.local_name(c["tag"])
            pf := x.prefix(c["tag"])
            if pf == "text" and ln == "s":
                append(out, document.Run(string.repeat(" ", x.attr_int(c, "text:c", 1)), _clean_fmt(fmt)))
            elif ln == "tab":
                append(out, document.Run("\t", _clean_fmt(fmt)))
            elif ln == "line-break":
                append(out, document.Run("\n", _clean_fmt(fmt)))
            elif ln == "span":
                f2 := u.merge(fmt, self.fmt_of_span(x.attr(c, "text:style-name", null)))
                self.runs(c, f2, out)
            elif ln == "a":
                f2 := u.merge(fmt, {"link": x.attr(c, "xlink:href", null)})
                self.runs(c, f2, out)
            elif ln == "note" or ln == "annotation" or ln == "soft-page-break" or ln == "bookmark" or ln == "bookmark-start" or ln == "bookmark-end" or ln == "reference-mark":
                continue
            elif pf == "draw":
                continue
            else:
                self.runs(c, fmt, out)

    func para_runs(p, base):
        out := []
        self.runs(p, base, out)
        return _trim(_merge(out))

    # Images d'un paragraphe (cadres draw:frame, y compris dans une zone de texte avec légende)
    func frames(p):
        found := []
        for fr in x.find_all(p, "draw:frame"):
            img := x.first(fr, "draw:image")
            if img == null:
                continue
            href := x.attr(img, "xlink:href", "")
            if href == "" or string.starts_with(href, "http"):
                continue
            if string.starts_with(href, "./"):
                href = _n.str_slice(href, 2, null)
            data := null
            try:
                data = self.pkg.archive.read(href)
            catch e:
                data = null
            if data == null:
                continue
            w := odf.to_pt(x.attr(fr, "svg:width", null))
            h := odf.to_pt(x.attr(fr, "svg:height", null))
            desc := x.first(fr, "svg:desc")
            title := x.first(fr, "svg:title")
            alt := x.text(desc) if desc != null else (x.text(title) if title != null else x.attr(fr, "draw:name", ""))
            append(found, {"data": data, "width": w, "height": h, "alt": alt, "frame": fr})
        return found

    func block_para(p, kind_hint):
        idx := self.idx
        sn := x.attr(p, "text:style-name", null)
        chain := idx.chain("paragraph", sn)
        names := []
        for c in chain:
            append(names, c)
        pprops := idx.props("paragraph", sn, "style:paragraph-properties")
        brk := u.get(pprops, "fo:break-before", "") == "page"
        # seul le style automatique du paragraphe colore ses segments (pas les styles nommés)
        base := {}
        if sn != null and idx.is_auto("paragraph", sn):
            base = idx.text_fmt("paragraph", sn, false)
        if brk and len(self.doc.blocks) > 0:
            own := idx.get("paragraph", sn)
            own_props := x.first(own, "style:paragraph-properties") if own != null else null
            if own_props != null and x.attr(own_props, "fo:break-before", "") == "page":
                self.doc.add_page_break()
        imgs := self.frames(p)
        caption_from_box := null
        for box in x.find_all(p, "draw:text-box"):
            t := string.trim(odf.node_text(box))
            if t != "":
                caption_from_box = t
        rs := self.para_runs(p, base)
        if len(imgs) > 0 and len(x.find_all(p, "draw:text-box")) > 0:
            rs = []
        for im in imgs:
            try:
                b := self.doc.add_image(im["data"], im["width"], im["height"], im["alt"])
                if caption_from_box != null:
                    b.caption = caption_from_box
            catch e:
                continue
        if kind_hint == "h":
            lvl := x.attr_int(p, "text:outline-level", 1)
            if len(rs) > 0:
                b := self.doc.add_runs(_strip_bold(rs), "heading")
                b.level = lvl
                b.align = _align(pprops)
                if self.doc.title == "" and lvl == 1:
                    self.doc.title = document.runs_text(rs)
            return null
        if len(rs) == 0:
            bb := u.get(pprops, "fo:border-bottom", u.get(pprops, "fo:border", "none"))
            if len(imgs) == 0 and (_has(names, "Horizontal_20_Line") or not string.contains(bb, "none")):
                self.doc.add_hr()
            return null
        if _has(names, "Title"):
            b := self.doc.add_runs(_strip_bold(rs), "heading")
            b.level = 0
            if self.doc.title == "":
                self.doc.title = document.runs_text(rs)
        elif _has(names, "Subtitle"):
            b := self.doc.add_runs(rs)
            b.style = "subtitle"
        elif _has(names, "Quotations") or _has(names, "Quote"):
            self.doc.add_runs(_strip_italic(rs), "quote")
        elif _has(names, "Preformatted_20_Text") or _has(names, "Source_20_Code") or _has(names, "Code"):
            last := self.doc.blocks[len(self.doc.blocks) - 1] if len(self.doc.blocks) > 0 else null
            t := document.runs_text(rs)
            if last != null and last.kind == "code" and self._code_open:
                last.text = last.text + "\n" + t
            else:
                self.doc.add_code(t)
            self._code_open = true
            return null
        elif (_has(names, "Caption") or _has(names, "Illustration") or _has(names, "Figure")) and len(self.doc.blocks) > 0 and self.doc.blocks[len(self.doc.blocks) - 1].kind == "image" and self.doc.blocks[len(self.doc.blocks) - 1].caption == null:
            self.doc.blocks[len(self.doc.blocks) - 1].caption = document.runs_text(rs)
        else:
            outline := 0
            for nm in names:
                s := idx.get("paragraph", nm)
                if s != null and x.attr(s, "style:default-outline-level", null) != null and outline == 0:
                    outline = x.attr_int(s, "style:default-outline-level", 0)
            if outline > 0:
                b := self.doc.add_runs(_strip_bold(rs), "heading")
                b.level = outline
            else:
                b := self.doc.add_runs(rs)
                b.align = _align(pprops)
        self._code_open = false
        return null

    func walk(node, list_level, list_name):
        for c in x.children(node):
            ln := x.local_name(c["tag"])
            pf := x.prefix(c["tag"])
            if pf == "text" and ln == "p":
                self.block_para(c, "p")
            elif pf == "text" and ln == "h":
                self._code_open = false
                self.block_para(c, "h")
            elif pf == "text" and ln == "list":
                self._code_open = false
                lname := x.attr(c, "text:style-name", list_name)
                self.list(c, list_level, lname)
            elif pf == "table" and ln == "table":
                self._code_open = false
                self.table(c)
            elif pf == "text" and (ln == "section" or ln == "index-body"):
                self.walk(c, list_level, list_name)
            elif pf == "text" and (ln == "table-of-content" or ln == "alphabetical-index" or ln == "illustration-index" or ln == "table-index" or ln == "bibliography"):
                continue
            elif pf == "text" and ln == "soft-page-break":
                continue

    func list(node, level, list_name):
        for item in x.children(node):
            iln := x.local_name(item["tag"])
            if iln != "list-item" and iln != "list-header":
                continue
            for c in x.children(item):
                ln := x.local_name(c["tag"])
                if ln == "p" or ln == "h":
                    rs := self.para_runs(c, {})
                    b := self.doc.add_runs(rs, "list_item")
                    b.level = level
                    b.ordered = self.idx.list_ordered(list_name, level) if list_name != null else false
                    for im in self.frames(c):
                        try:
                            self.doc.add_image(im["data"], im["width"], im["height"], im["alt"])
                        catch e:
                            continue
                elif ln == "list":
                    self.list(c, level + 1, x.attr(c, "text:style-name", list_name))
                elif ln == "table":
                    self.table(c)

    func table(t):
        b := document.Block("table")
        has_header := false
        rows := []
        _table_rows(t, rows)
        for r in rows:
            if r["header"]:
                has_header = true
        for r in rows:
            line := []
            for cell in x.children(r["node"]):
                cln := x.local_name(cell["tag"])
                if cln != "table-cell" and cln != "covered-table-cell":
                    continue
                rep := x.attr_int(cell, "table:number-columns-repeated", 1)
                cr := []
                first := true
                for p in x.children(cell):
                    pln := x.local_name(p["tag"])
                    if pln == "p" or pln == "h":
                        if not first:
                            append(cr, document.Run("\n"))
                        for rr in self.para_runs(p, {}):
                            append(cr, rr)
                        first = false
                    elif pln == "list":
                        for it in x.find_all(p, "text:p"):
                            if not first:
                                append(cr, document.Run("\n"))
                            append(cr, document.Run("• " + odf.node_text(it)))
                            first = false
                if cln == "covered-table-cell":
                    cr = []
                cell_runs := _merge(cr)
                k := 0
                if len(cell_runs) == 0 and rep > 64:
                    rep = 1
                while k < rep:
                    append(line, cell_runs)
                    k = k + 1
            while len(line) > 0 and len(line[len(line) - 1]) == 0:
                collections.pop(line)
            append(b.rows, line)
        # colonnes vides finales retirées, lignes complétées
        ncol := 0
        for line in b.rows:
            if len(line) > ncol:
                ncol = len(line)
        for line in b.rows:
            while len(line) < ncol:
                append(line, [])
        if has_header and len(b.rows) > 0:
            for c in b.rows[0]:
                for r in c:
                    r.bold = false
        b.header = has_header
        self.doc.add(b)

func _table_rows(node, out, header=false):
    for c in x.children(node):
        ln := x.local_name(c["tag"])
        if ln == "table-row":
            rep := x.attr_int(c, "table:number-rows-repeated", 1)
            if rep > 1 and string.trim(odf.node_text(c)) == "":
                rep = 1
            k := 0
            while k < rep and k < 10000:
                append(out, {"node": c, "header": header})
                k = k + 1
        elif ln == "table-header-rows":
            _table_rows(c, out, true)
        elif ln == "table-rows" or ln == "table-row-group":
            _table_rows(c, out, header)

func _has(names, n):
    for v in names:
        if v == n:
            return true
    return false

func _align(pp):
    a := u.get(pp, "fo:text-align", null)
    if a == "center":
        return "center"
    if a == "end" or a == "right":
        return "right"
    if a == "justify":
        return "justify"
    return null

func _clean_fmt(f):
    out := {}
    for k in keys(f):
        v := f[k]
        if v == null or v == false:
            continue
        if k == "font":
            low := string.lower(v)
            if string.contains(low, "mono") or string.contains(low, "courier") or string.contains(low, "consolas") or string.contains(low, "menlo"):
                out["code"] = true
                continue
        if k == "highlight":
            continue
        out[k] = v
    return out

func _merge(rs):
    out := []
    for r in rs:
        if len(out) > 0 and out[len(out) - 1].same_format(r):
            out[len(out) - 1].text = out[len(out) - 1].text + r.text
        else:
            append(out, r)
    return out

func _trim(rs):
    out := []
    for r in rs:
        append(out, r)
    while len(out) > 0 and string.trim(out[0].text) == "" and out[0].text != "\t" and out[0].text != "\n":
        collections.pop(out, 0)
    while len(out) > 0 and string.trim(out[len(out) - 1].text) == "" and out[len(out) - 1].text != "\t":
        collections.pop(out)
    return out

func _strip_bold(rs):
    for r in rs:
        r.bold = false
        r.size = null
        r.color = null
        r.font = null
    return rs

func _strip_italic(rs):
    for r in rs:
        r.italic = false
        r.color = null
    return rs

func read(src):
    pkg := src if isinstance(src, odf.OdfPackage) else odf.open(src)
    root := pkg.content()
    if root == null:
        errors.fail(errors.ODF, "content.xml absent")
    idx := odf.StyleIndex([pkg.styles(), root])
    rd := _Reader(pkg, idx)
    rd.doc.metadata = pkg.metadata
    rd.doc.title = pkg.metadata.title
    body := x.first(root, "office:body")
    txt := x.first(body, "office:text") if body != null else null
    if txt == null:
        errors.fail(errors.ODF, "pas un texte OpenDocument (office:text absent)")
    rd.walk(txt, 0, null)
    return rd.doc

func read_text(src):
    return read(src).text()
