# ALEX STANDARD LIBRARY — office.docx_reader
# Lecture des documents Word (.docx, .docm, .dotx) : corps (paragraphes, tableaux, images, liens, listes), styles,
# numérotation, section (format de page, marges, orientation), en-tête et pied de page, notes de bas de page,
# commentaires, métadonnées. Les macros (.docm) ne sont jamais exécutées ni interprétées.
#
#   use office.docx_reader as reader
#   parts := reader.read("rapport.docx")
#   for b in parts["body"]:                          # docx_paragraphs.Paragraph ou docx_tables.Table
#       print(b.text())
#   reader.read_text("rapport.docx")                 # texte brut (paragraphes séparés par des sauts de ligne)
#
# read(chemin_ou_octets) -> dict :
#   "body"        blocs du corps, dans l'ordre
#   "styles"      docx_styles.StyleSheet
#   "section"     {"page_width", "page_height" (pt), "orientation" ("portrait" | "landscape"), "margin_top",
#                  "margin_bottom", "margin_left", "margin_right", "margin_header", "margin_footer" (pt), "columns"}
#   "header" / "footer" / "first_header" / "first_footer"  blocs (listes, éventuellement vides)
#   "footnotes"   [{"id", "text"}]        "comments" [{"id", "author", "date", "text"}]
#   "metadata"    metadata.Metadata       "package" core.Package (pour un accès bas niveau)
# read_text(src, separator="\n") -> str   ·   blocks_text(blocs) -> str (tableaux : cellules tabulées)
# Erreurs : FormatError (pas un document Word), DOCXError, XMLError, ArchiveError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.metadata as metadata
use office.docx_styles as styles
use office.docx_paragraphs as dp
use office.docx_tables as dt

class _ReadCtx:
    func init(pkg, part, numbering):
        self.pkg = pkg
        self.part = part
        self.numbering = numbering
        self._images = {}

    func link(rid):
        r := self.pkg.rel(self.part, rid)
        if r == null:
            return null
        return r["target"]

    func image(info):
        rid := info["rid"]
        if contains_key(self._images, rid):
            return self._images[rid]
        r := self.pkg.rel(self.part, rid)
        img := null
        if r != null and r["mode"] != "External":
            target := self.pkg.resolve(self.part, r["target"])
            if self.pkg.has_part(target):
                try:
                    img = core.load_image(self.pkg.read_part(target))
                catch e:
                    img = null
        self._images[rid] = img
        return img

    func list_kind(num_id, level):
        key := str(num_id)
        if not contains_key(self.numbering, key):
            return null
        levels := self.numbering[key]
        fmt := u.get(levels, str(level), u.get(levels, "0", "decimal"))
        if fmt == "none":
            return null
        if fmt == "bullet":
            return "bullet"
        return "number"

# numId -> {ilvl: numFmt}
func _read_numbering(pkg, main):
    out := {}
    part := pkg.target(main, core.REL_NUMBERING)
    if part == null or not pkg.has_part(part):
        return out
    root := pkg.read_xml(part)
    abstract := {}
    for a in x.children(root, "w:abstractNum"):
        levels := {}
        for lvl in x.children(a, "w:lvl"):
            f := x.first(lvl, "w:numFmt")
            levels[x.attr(lvl, "w:ilvl", "0")] = x.attr(f, "w:val", "decimal") if f != null else "decimal"
        abstract[x.attr(a, "w:abstractNumId", "")] = levels
    for n in x.children(root, "w:num"):
        aid := x.first(n, "w:abstractNumId")
        if aid != null and contains_key(abstract, x.attr(aid, "w:val", "")):
            out[x.attr(n, "w:numId", "")] = abstract[x.attr(aid, "w:val", "")]
    return out

func _blocks(container, rctx, out):
    for c in x.children(container):
        ln := x.local_name(c["tag"])
        if ln == "p":
            append(out, dp.parse_paragraph(c, rctx))
        elif ln == "tbl":
            append(out, dt.parse_table(c, rctx))
        elif ln == "sdt":
            content := x.first(c, "w:sdtContent")
            if content != null:
                _blocks(content, rctx, out)
        elif ln == "customXml" or ln == "ins":
            _blocks(c, rctx, out)
        elif ln == "AlternateContent":
            choice := x.first(c, "mc:Fallback")
            if choice == null:
                choice = x.first(c, "mc:Choice")
            if choice != null:
                _blocks(choice, rctx, out)

func _pt(v):
    if v == null:
        return null
    n := _n.num_parse(v)
    if n == null:
        return null
    return to_float(n) / 20.0

func _section(sect):
    s := {"page_width": 595.3, "page_height": 841.9, "orientation": "portrait", "margin_top": 70.85, "margin_bottom": 70.85, "margin_left": 70.85, "margin_right": 70.85, "margin_header": 35.4, "margin_footer": 35.4, "columns": 1, "title_page": false}
    if sect == null:
        return s
    sz := x.first(sect, "w:pgSz")
    if sz != null:
        w := _pt(x.attr(sz, "w:w", null))
        h := _pt(x.attr(sz, "w:h", null))
        if w != null:
            s["page_width"] = w
        if h != null:
            s["page_height"] = h
        if x.attr(sz, "w:orient", "") == "landscape" or (w != null and h != null and w > h):
            s["orientation"] = "landscape"
    mar := x.first(sect, "w:pgMar")
    if mar != null:
        for pair in [["w:top", "margin_top"], ["w:bottom", "margin_bottom"], ["w:left", "margin_left"], ["w:right", "margin_right"], ["w:header", "margin_header"], ["w:footer", "margin_footer"]]:
            v := _pt(x.attr(mar, pair[0], null))
            if v != null:
                s[pair[1]] = v
    cols := x.first(sect, "w:cols")
    if cols != null:
        s["columns"] = x.attr_int(cols, "w:num", 1)
    s["title_page"] = x.first(sect, "w:titlePg") != null
    return s

func _hf_blocks(pkg, main, sect, kind, which, numbering):
    if sect == null:
        return []
    for ref in x.children(sect, "w:" + kind + "Reference"):
        if x.attr(ref, "w:type", "default") == which:
            r := pkg.rel(main, x.attr(ref, "r:id", ""))
            if r == null:
                return []
            part := pkg.resolve(main, r["target"])
            if not pkg.has_part(part):
                return []
            out := []
            _blocks(pkg.read_xml(part), _ReadCtx(pkg, part, numbering), out)
            return out
    return []

func _notes(pkg, main, rel_type, tag):
    out := []
    part := pkg.target(main, rel_type)
    if part == null or not pkg.has_part(part):
        return out
    root := pkg.read_xml(part)
    for n in x.children(root, tag):
        t := x.attr(n, "w:type", "normal")
        if t != "normal":
            continue
        texts := []
        for p in x.find_all(n, "w:p"):
            parts := []
            for e in x.find_all(p, "w:t"):
                append(parts, x.text(e))
            append(texts, string.join("", parts))
        append(out, {"id": x.attr(n, "w:id", ""), "author": x.attr(n, "w:author", ""), "date": x.attr(n, "w:date", ""), "text": string.trim(string.join("\n", texts))})
    return out

func read(src):
    pkg := core.open_package(src)
    main := pkg.main_part()
    ct := pkg.content_type(main)
    if ct != null and not string.contains(ct, "wordprocessingml"):
        errors.fail(errors.FORMAT, "ce paquet n'est pas un document Word (" + ct + ")")
    numbering := _read_numbering(pkg, main)
    sheet := null
    sp := pkg.target(main, core.REL_STYLES)
    if sp != null and pkg.has_part(sp):
        sheet = styles.parse(pkg.read_text(sp))
    else:
        sheet = styles.default_styles()
    root := pkg.read_xml(main)
    body := x.first(root, "w:body")
    if body == null:
        errors.fail(errors.DOCX, "word/document.xml sans élément w:body")
    rctx := _ReadCtx(pkg, main, numbering)
    blocks := []
    _blocks(body, rctx, blocks)
    sect := x.first(body, "w:sectPr")
    if sect == null:
        # section portée par le dernier paragraphe
        for p in x.find_all(body, "w:sectPr"):
            sect = p
    footnotes := _notes(pkg, main, core.REL_FOOTNOTES, "w:footnote")
    comments := _notes(pkg, main, core.REL_COMMENTS, "w:comment")
    return {"body": blocks, "styles": sheet, "section": _section(sect), "header": _hf_blocks(pkg, main, sect, "header", "default", numbering), "footer": _hf_blocks(pkg, main, sect, "footer", "default", numbering), "first_header": _hf_blocks(pkg, main, sect, "header", "first", numbering), "first_footer": _hf_blocks(pkg, main, sect, "footer", "first", numbering), "footnotes": footnotes, "comments": comments, "metadata": metadata.from_package(pkg), "package": pkg}

func blocks_text(blocks, separator="\n"):
    out := []
    for b in blocks:
        append(out, b.text())
    return string.join(separator, out)

func read_text(src, separator="\n"):
    return blocks_text(read(src)["body"], separator)
