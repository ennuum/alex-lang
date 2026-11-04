# ALEX STANDARD LIBRARY — office.document
# Modèle de document NEUTRE (indépendant du format) : titres, paragraphes à segments mis en forme, listes
# (puces / numérotées, imbriquées), tableaux, images, blocs de code, citations, filets, sauts de page. C'est le
# pivot des conversions (DOCX, ODT, HTML, Markdown, texte, PDF : voir conversion) ; il sait lui-même lire et
# écrire Markdown, HTML et texte brut.
#
#   use office.document as document
#   d := document.new("Compte rendu")
#   d.add_heading("Ordre du jour", 1)
#   d.add_paragraph("Réunion du **12 mars** avec [le client](https://example.org).", true)   # Markdown en ligne
#   d.add_list(["Budget", ["Révision", "Validation"], "Planning"])
#   d.add_table([["Poste", "Montant"], ["Matériel", 1200]])
#   d.to_markdown()     d.to_html()     d.text()
#   d2 := document.from_markdown(texte_md)
#
# Run(text, fmt=null) : text bold italic underline strike code color size font link superscript subscript
# Block : kind ("heading" | "paragraph" | "list_item" | "table" | "image" | "code" | "quote" | "hr" | "page_break")
#   runs (segments)  level (titre 1..6, ou niveau de liste 0..)  ordered (liste numérotée)  align  style
#   rows (tableau : lignes de cellules, chaque cellule = liste de Run)  header (1re ligne d'en-tête)
#   image (core.Image) width height (points, facultatifs) alt caption  text (bloc de code) language
#   plain() -> texte du bloc
# Document(title="") : blocks metadata title
#   add_heading(t, level=1)  add_paragraph(t, markdown=false, align=null, style=null)  add_runs(runs, kind="paragraph")
#   add_list_item(t, level=0, ordered=false)  add_list(items, ordered=false)  add_table(lignes, header=true)
#   add_image(image, width=null, height=null, alt="", caption=null)  add_code(t, language="")  add_quote(t)
#   add_hr()  add_page_break()   (t : texte, ou liste de Run ; markdown=true : **gras**, *italique*, `code`,
#   ~~barré~~, [lien](url) interprétés)
#   text()  to_markdown()  to_html(full=true, css=null)  headings()  tables() -> lignes de textes  images()
#   word_count()  outline()
#   to_docx() -> word.WordDocument   to_pdf() -> pdf.PdfDocument   (enregistrer : .save(chemin) sur le résultat,
#   ou conversion.save(document, chemin))
# Fonctions : new(title="")  runs(texte, fmt=null)  parse_inline(md) -> [Run]  runs_text(runs)
#   from_markdown(md) -> Document   from_text(texte) -> Document   from_html(html) -> Document
#   runs_markdown(runs) / runs_html(runs)
#   from_docx(chemin_octets_ou_WordDocument) -> Document   to_docx(d) / to_pdf(d, options=null) (fonctions)
# Erreurs : ValueError, TypeError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.utils as u
use office.core as core
use office.metadata as metadata
use office.html as html
use office.xml as x
use office.word as word
use office.docx_paragraphs as dp
use office.docx_tables as dt
use office.pdf as pdf

const _FMT_KEYS := ["bold", "italic", "underline", "strike", "code", "color", "size", "font", "link", "superscript", "subscript"]

class Run:
    func init(text="", fmt=null):
        self.text = u.to_text(text)
        self.bold = false
        self.italic = false
        self.underline = false
        self.strike = false
        self.code = false
        self.color = null
        self.size = null
        self.font = null
        self.link = null
        self.superscript = false
        self.subscript = false
        if fmt != null:
            self.set(fmt)

    func set(fmt):
        for k in keys(fmt):
            v := fmt[k]
            if k == "bold":
                self.bold = v == true
            elif k == "italic":
                self.italic = v == true
            elif k == "underline":
                self.underline = v == true or (type(v) == "str" and v != "none")
            elif k == "strike":
                self.strike = v == true
            elif k == "code":
                self.code = v == true
            elif k == "color":
                self.color = v
            elif k == "size":
                self.size = v
            elif k == "font":
                self.font = v
            elif k == "link":
                self.link = v
            elif k == "superscript":
                self.superscript = v == true
            elif k == "subscript":
                self.subscript = v == true
        return self

    func fmt():
        return {"bold": self.bold, "italic": self.italic, "underline": self.underline, "strike": self.strike, "code": self.code, "color": self.color, "size": self.size, "font": self.font, "link": self.link, "superscript": self.superscript, "subscript": self.subscript}

    func same_format(o):
        return self.fmt() == o.fmt()

    func is_plain():
        return not self.bold and not self.italic and not self.underline and not self.strike and not self.code and self.color == null and self.size == null and self.font == null and self.link == null and not self.superscript and not self.subscript

class Block:
    func init(kind):
        self.kind = kind
        self.runs = []
        self.level = 0
        self.ordered = false
        self.align = null
        self.style = null
        self.rows = []
        self.header = true
        self.image = null
        self.width = null
        self.height = null
        self.alt = ""
        self.caption = null
        self.text = ""
        self.language = ""

    func plain():
        if self.kind == "code":
            return self.text
        if self.kind == "table":
            lines := []
            for row in self.rows:
                cells := []
                for c in row:
                    append(cells, runs_text(c))
                append(lines, string.join("\t", cells))
            return string.join("\n", lines)
        if self.kind == "image":
            return self.caption if self.caption != null else self.alt
        if self.kind == "hr" or self.kind == "page_break":
            return ""
        return runs_text(self.runs)

func runs_text(rs):
    out := []
    for r in rs:
        append(out, r.text)
    return string.join("", out)

func runs(text, fmt=null):
    if type(text) == "list":
        out := []
        for r in text:
            if isinstance(r, Run):
                append(out, r)
            elif type(r) == "list":
                append(out, Run(r[0], r[1] if len(r) > 1 else null))
            else:
                append(out, Run(u.to_text(r), fmt))
        return out
    if isinstance(text, Run):
        return [text]
    return [Run(u.to_text(text), fmt)]

# ---------------------------------------------------------------------------------------------- Markdown en ligne

func _flush(out, buf, fmt):
    if buf != "":
        append(out, Run(buf, u.merge(fmt, null)))
    return ""

# **gras** __gras__ *italique* _italique_ `code` ~~barré~~ [texte](url) <url> ; \x échappe.
func parse_inline(md, base=null):
    out := []
    cs := u.chars(u.to_text(md))
    n := len(cs)
    i := 0
    buf := ""
    fmt := u.merge(base, null) if base != null else {}
    while i < n:
        c := cs[i]
        if c == "\\" and i + 1 < n:
            buf = buf + cs[i + 1]
            i = i + 2
            continue
        if c == "`":
            j := i + 1
            while j < n and cs[j] != "`":
                j = j + 1
            if j < n:
                buf = _flush(out, buf, fmt)
                code := string.join("", _n.bytes_slice(cs, i + 1, j))
                append(out, Run(code, u.merge(fmt, {"code": true})))
                i = j + 1
                continue
        if (c == "*" or c == "_") and i + 1 < n and cs[i + 1] == c:
            close := _find_seq(cs, i + 2, c + c)
            if close > i + 2:
                buf = _flush(out, buf, fmt)
                inner := string.join("", _n.bytes_slice(cs, i + 2, close))
                for r in parse_inline(inner, u.merge(fmt, {"bold": true})):
                    append(out, r)
                i = close + 2
                continue
        if (c == "*" or c == "_") and i + 1 < n and cs[i + 1] != " ":
            close := _find_seq(cs, i + 1, c)
            if close > i + 1 and (c == "*" or close + 1 >= n or not _is_word(cs[close + 1])):
                buf = _flush(out, buf, fmt)
                inner := string.join("", _n.bytes_slice(cs, i + 1, close))
                for r in parse_inline(inner, u.merge(fmt, {"italic": true})):
                    append(out, r)
                i = close + 1
                continue
        if c == "~" and i + 1 < n and cs[i + 1] == "~":
            close := _find_seq(cs, i + 2, "~~")
            if close > i + 2:
                buf = _flush(out, buf, fmt)
                inner := string.join("", _n.bytes_slice(cs, i + 2, close))
                for r in parse_inline(inner, u.merge(fmt, {"strike": true})):
                    append(out, r)
                i = close + 2
                continue
        if c == "[":
            close := _find_seq(cs, i + 1, "]")
            if close > i and close + 1 < n and cs[close + 1] == "(":
                end := _find_seq(cs, close + 2, ")")
                if end > close:
                    buf = _flush(out, buf, fmt)
                    label := string.join("", _n.bytes_slice(cs, i + 1, close))
                    url := string.trim(string.join("", _n.bytes_slice(cs, close + 2, end)))
                    sp := string.find(url, " ")
                    if sp > 0:
                        url = _n.str_slice(url, 0, sp)
                    for r in parse_inline(label, u.merge(fmt, {"link": url})):
                        append(out, r)
                    i = end + 1
                    continue
        if c == "<":
            close := _find_seq(cs, i + 1, ">")
            if close > i:
                inner := string.join("", _n.bytes_slice(cs, i + 1, close))
                if string.starts_with(inner, "http://") or string.starts_with(inner, "https://") or string.starts_with(inner, "mailto:"):
                    buf = _flush(out, buf, fmt)
                    append(out, Run(inner, u.merge(fmt, {"link": inner})))
                    i = close + 1
                    continue
        buf = buf + c
        i = i + 1
    _flush(out, buf, fmt)
    return out

func _is_word(ch):
    o := string.ord(ch)
    return (o >= 48 and o <= 57) or (o >= 65 and o <= 90) or (o >= 97 and o <= 122) or o > 127

func _find_seq(cs, start, seq):
    m := len(seq)
    i := start
    n := len(cs)
    while i + m <= n:
        ok := true
        k := 0
        while k < m:
            if cs[i + k] != str(seq[k]):
                ok = false
                break
            k = k + 1
        if ok:
            return i
        i = i + 1
    return -1

func _md_escape(t):
    s := t
    for ch in ["\\", "*", "_", "`", "[", "]"]:
        s = string.replace(s, ch, "\\" + ch)
    return s

func runs_markdown(rs):
    out := []
    for r in rs:
        t := r.text
        if t == "":
            continue
        s := ""
        if r.code:
            s = "`" + t + "`"
        else:
            s = _md_escape(t)
            lead := ""
            trail := ""
            while string.starts_with(s, " "):
                lead = lead + " "
                s = _n.str_slice(s, 1, null)
            while string.ends_with(s, " "):
                trail = trail + " "
                s = _n.str_slice(s, 0, len(s) - 1)
            if s != "":
                if r.strike:
                    s = "~~" + s + "~~"
                if r.italic:
                    s = "*" + s + "*"
                if r.bold:
                    s = "**" + s + "**"
            s = lead + s + trail
        if r.link != null:
            s = "[" + s + "](" + r.link + ")"
        append(out, s)
    return string.join("", out)

func runs_html(rs):
    out := []
    for r in rs:
        t := string.replace(html.escape(r.text), "\n", "<br>")
        if r.code:
            t = "<code>" + t + "</code>"
        if r.bold:
            t = "<strong>" + t + "</strong>"
        if r.italic:
            t = "<em>" + t + "</em>"
        if r.underline:
            t = "<u>" + t + "</u>"
        if r.strike:
            t = "<s>" + t + "</s>"
        if r.superscript:
            t = "<sup>" + t + "</sup>"
        if r.subscript:
            t = "<sub>" + t + "</sub>"
        style := []
        if r.color != null:
            append(style, "color:#" + u.color_hex(r.color))
        if r.size != null:
            append(style, "font-size:" + u.format_number(r.size) + "pt")
        if r.font != null:
            append(style, "font-family:'" + string.replace(r.font, "'", "") + "'")
        if len(style) > 0:
            t = "<span style=\"" + string.join(";", style) + "\">" + t + "</span>"
        if r.link != null:
            t = "<a href=\"" + html.escape(r.link, true) + "\">" + t + "</a>"
        append(out, t)
    return string.join("", out)

# ---------------------------------------------------------------------------------------------- Document

class Document:
    func init(title=""):
        self.blocks = []
        self.title = title
        self.metadata = metadata.new({"title": title} if title != "" else null)

    func _runs(text, markdown):
        if markdown and type(text) == "str":
            return parse_inline(text)
        return runs(text)

    func add(block):
        append(self.blocks, block)
        return block

    func add_heading(text, level=1, markdown=false):
        b := Block("heading")
        b.level = level
        b.runs = self._runs(text, markdown)
        return self.add(b)

    func add_paragraph(text="", markdown=false, align=null, style=null):
        b := Block("paragraph")
        b.runs = self._runs(text, markdown)
        b.align = align
        b.style = style
        return self.add(b)

    func add_runs(rs, kind="paragraph"):
        b := Block(kind)
        b.runs = runs(rs)
        return self.add(b)

    func add_list_item(text, level=0, ordered=false, markdown=false):
        b := Block("list_item")
        b.runs = self._runs(text, markdown)
        b.level = level
        b.ordered = ordered
        return self.add(b)

    func _items(items, ordered, level, markdown):
        for it in items:
            if type(it) == "list" or type(it) == "tuple":
                self._items(it, ordered, level + 1, markdown)
            else:
                self.add_list_item(it, level, ordered, markdown)

    func add_list(items, ordered=false, markdown=false):
        self._items(items, ordered, 0, markdown)

    func add_table(rows, header=true):
        b := Block("table")
        for r in rows:
            line := []
            for c in r:
                if type(c) == "list":
                    append(line, runs(c))
                else:
                    append(line, [Run(u.to_text(c) if not u.is_date_dict(c) else u.iso_date(c))])
            append(b.rows, line)
        b.header = header
        return self.add(b)

    func add_image(image, width=null, height=null, alt="", caption=null):
        b := Block("image")
        b.image = core.load_image(image)
        b.width = width
        b.height = height
        b.alt = alt
        b.caption = caption
        return self.add(b)

    func add_code(text, language=""):
        b := Block("code")
        b.text = u.to_text(text)
        b.language = language
        return self.add(b)

    func add_quote(text, markdown=false):
        b := Block("quote")
        b.runs = self._runs(text, markdown)
        return self.add(b)

    func add_hr():
        return self.add(Block("hr"))

    func add_page_break():
        return self.add(Block("page_break"))

    # ---------------------------------------------------------- lecture
    func text():
        out := []
        for b in self.blocks:
            if b.kind == "hr" or b.kind == "page_break":
                continue
            t := b.plain()
            if b.kind == "list_item":
                t = string.repeat("  ", b.level) + ("- " if not b.ordered else "") + t
            append(out, t)
        return string.join("\n", out)

    func headings():
        out := []
        for b in self.blocks:
            if b.kind == "heading":
                append(out, {"level": b.level, "text": b.plain()})
        return out

    func outline():
        lines := []
        for h in self.headings():
            append(lines, string.repeat("  ", (h["level"] - 1) if h["level"] > 0 else 0) + h["text"])
        return string.join("\n", lines)

    func tables():
        out := []
        for b in self.blocks:
            if b.kind == "table":
                rows := []
                for r in b.rows:
                    line := []
                    for c in r:
                        append(line, runs_text(c))
                    append(rows, line)
                append(out, rows)
        return out

    func images():
        out := []
        for b in self.blocks:
            if b.kind == "image":
                append(out, b)
        return out

    func word_count():
        n := 0
        for w in string.split(string.replace(string.replace(self.text(), "\n", " "), "\t", " "), " "):
            if w != "":
                n = n + 1
        return n

    func to_docx():
        return to_docx(self)

    func to_pdf(options=null):
        return to_pdf(self, options)

    # ---------------------------------------------------------- Markdown
    func to_markdown():
        out := []
        counters := {}
        prev := null
        for b in self.blocks:
            k := b.kind
            if prev != null and not (k == "list_item" and prev.kind == "list_item" and (b.level > 0 or prev.ordered == b.ordered)):
                append(out, "")
            if k != "list_item":
                counters = {}
            if k == "heading":
                lvl := b.level if b.level >= 1 else 1
                append(out, string.repeat("#", lvl if lvl <= 6 else 6) + " " + runs_markdown(b.runs))
            elif k == "paragraph":
                append(out, runs_markdown(b.runs))
            elif k == "list_item":
                ind := string.repeat("   " if b.ordered else "  ", b.level)
                if b.ordered:
                    key := b.level
                    counters[key] = (counters[key] if contains_key(counters, key) else 0) + 1
                    for kk in keys(counters):
                        if kk > key:
                            counters[kk] = 0
                    append(out, ind + str(counters[key]) + ". " + runs_markdown(b.runs))
                else:
                    append(out, ind + "- " + runs_markdown(b.runs))
            elif k == "quote":
                for line in string.split(runs_markdown(b.runs), "\n"):
                    append(out, "> " + line)
            elif k == "code":
                append(out, "```" + b.language)
                append(out, b.text)
                append(out, "```")
            elif k == "hr":
                append(out, "---")
            elif k == "page_break":
                append(out, "<div style=\"page-break-after: always\"></div>")
            elif k == "image":
                src := "data:" + b.image.mime + ";base64," + u.base64_encode(b.image.data)
                append(out, "![" + _md_escape(b.alt if b.alt != "" else u.to_text(b.caption)) + "](" + src + ")")
                if b.caption != null:
                    append(out, "")
                    append(out, "*" + _md_escape(b.caption) + "*")
            elif k == "table":
                if len(b.rows) > 0:
                    ncol := 0
                    for r in b.rows:
                        if len(r) > ncol:
                            ncol = len(r)
                    first := true
                    for r in b.rows:
                        cells := []
                        c := 0
                        while c < ncol:
                            cell := runs_markdown(r[c]) if c < len(r) else ""
                            append(cells, string.replace(string.replace(cell, "|", "\\|"), "\n", "<br>"))
                            c = c + 1
                        append(out, "| " + string.join(" | ", cells) + " |")
                        if first:
                            seps := []
                            c = 0
                            while c < ncol:
                                append(seps, "---")
                                c = c + 1
                            append(out, "| " + string.join(" | ", seps) + " |")
                            first = false
            prev = b
        return string.join("\n", out) + "\n"

    # ---------------------------------------------------------- HTML
    func to_html(full=true, css=null):
        out := []
        stack := []
        for b in self.blocks:
            k := b.kind
            if k == "list_item":
                tag := "ol" if b.ordered else "ul"
                while len(stack) > b.level + 1:
                    append(out, "</li></" + collections.pop(stack) + ">")
                if len(stack) == b.level + 1 and stack[len(stack) - 1] != tag:
                    append(out, "</li></" + collections.pop(stack) + ">")
                if len(stack) == b.level + 1:
                    append(out, "</li><li>" + runs_html(b.runs))
                else:
                    while len(stack) < b.level + 1:
                        append(out, "<" + tag + "><li>")
                        append(stack, tag)
                    append(out, runs_html(b.runs))
                continue
            while len(stack) > 0:
                append(out, "</li></" + collections.pop(stack) + ">")
            if k == "heading":
                lvl := b.level if b.level >= 1 and b.level <= 6 else 1
                append(out, "<h" + str(lvl) + ">" + runs_html(b.runs) + "</h" + str(lvl) + ">")
            elif k == "paragraph":
                st := " style=\"text-align:" + b.align + "\"" if b.align != null and b.align != "left" else ""
                append(out, "<p" + st + ">" + runs_html(b.runs) + "</p>")
            elif k == "quote":
                append(out, "<blockquote>" + runs_html(b.runs) + "</blockquote>")
            elif k == "code":
                cls := " class=\"language-" + html.escape(b.language, true) + "\"" if b.language != "" else ""
                append(out, "<pre><code" + cls + ">" + html.escape(b.text) + "</code></pre>")
            elif k == "hr":
                append(out, "<hr>")
            elif k == "page_break":
                append(out, "<div style=\"page-break-after:always\"></div>")
            elif k == "image":
                w := " width=\"" + u.format_number(u.round_to(b.width * 96.0 / 72.0, 0)) + "\"" if b.width != null and type(b.width) != "str" else ""
                img := "<img src=\"data:" + b.image.mime + ";base64," + u.base64_encode(b.image.data) + "\" alt=\"" + html.escape(b.alt, true) + "\"" + w + ">"
                if b.caption != null:
                    append(out, "<figure>" + img + "<figcaption>" + html.escape(b.caption) + "</figcaption></figure>")
                else:
                    append(out, "<p>" + img + "</p>")
            elif k == "table":
                rows := ["<table>"]
                ri := 0
                for r in b.rows:
                    tag := "th" if ri == 0 and b.header else "td"
                    cells := []
                    for c in r:
                        append(cells, "<" + tag + ">" + runs_html(c) + "</" + tag + ">")
                    append(rows, ("<thead>" if ri == 0 and b.header else "") + "<tr>" + string.join("", cells) + "</tr>" + ("</thead><tbody>" if ri == 0 and b.header else ""))
                    ri = ri + 1
                append(rows, "</tbody></table>" if b.header else "</table>")
                append(out, string.join("", rows))
        while len(stack) > 0:
            append(out, "</li></" + collections.pop(stack) + ">")
        body := string.join("\n", out)
        if not full:
            return body
        t := self.title if self.title != "" else self.metadata.title
        return html.document(t if t != "" else "Document", body, css)

func new(title=""):
    return Document(title)

# ---------------------------------------------------------------------------------------------- Markdown -> Document

func _list_marker(line):
    t := line
    ind := 0
    while string.starts_with(t, " "):
        ind = ind + 1
        t = _n.str_slice(t, 1, null)
    while string.starts_with(t, "\t"):
        ind = ind + 4
        t = _n.str_slice(t, 1, null)
    if string.starts_with(t, "- ") or string.starts_with(t, "* ") or string.starts_with(t, "+ "):
        return [ind, false, _n.str_slice(t, 2, null)]
    k := 0
    while k < len(t) and string.ord(t[k]) >= 48 and string.ord(t[k]) <= 57:
        k = k + 1
    if k > 0 and k < len(t) - 1 and (str(t[k]) == "." or str(t[k]) == ")") and str(t[k + 1]) == " ":
        return [ind, true, _n.str_slice(t, k + 2, null)]
    return null

func _split_row(line):
    t := string.trim(line)
    if string.starts_with(t, "|"):
        t = _n.str_slice(t, 1, null)
    if string.ends_with(t, "|") and not string.ends_with(t, "\\|"):
        t = _n.str_slice(t, 0, len(t) - 1)
    cells := []
    buf := ""
    cs := u.chars(t)
    i := 0
    while i < len(cs):
        if cs[i] == "\\" and i + 1 < len(cs) and cs[i + 1] == "|":
            buf = buf + "|"
            i = i + 2
            continue
        if cs[i] == "|":
            append(cells, string.trim(buf))
            buf = ""
        else:
            buf = buf + cs[i]
        i = i + 1
    append(cells, string.trim(buf))
    return cells

func _is_sep_row(line):
    t := string.trim(line)
    if not string.contains(t, "-"):
        return false
    for c in t:
        ch := str(c)
        if ch != "|" and ch != "-" and ch != ":" and ch != " ":
            return false
    return true

func from_markdown(md):
    d := Document()
    lines := u.lines(md)
    n := len(lines)
    i := 0
    para := []
    list_indents := []
    while i < n:
        line := lines[i]
        t := string.trim(line)
        if string.starts_with(t, "```") or string.starts_with(t, "~~~"):
            _flush_para(d, para)
            para = []
            fence := _n.str_slice(t, 0, 3)
            lang := string.trim(_n.str_slice(t, 3, null))
            body := []
            i = i + 1
            while i < n and not string.starts_with(string.trim(lines[i]), fence):
                append(body, lines[i])
                i = i + 1
            d.add_code(string.join("\n", body), lang)
            i = i + 1
            continue
        if t == "":
            _flush_para(d, para)
            para = []
            i = i + 1
            continue
        if string.starts_with(t, "#"):
            k := 0
            while k < len(t) and str(t[k]) == "#":
                k = k + 1
            if k <= 6 and (k == len(t) or str(t[k]) == " "):
                _flush_para(d, para)
                para = []
                txt := string.trim(_n.str_slice(t, k, null))
                while string.ends_with(txt, "#"):
                    txt = string.trim(_n.str_slice(txt, 0, len(txt) - 1))
                d.add_heading(parse_inline(txt), k)
                if d.title == "" and k == 1:
                    d.title = runs_text(d.blocks[len(d.blocks) - 1].runs)
                i = i + 1
                continue
        if (t == "---" or t == "***" or t == "___") and len(para) == 0:
            d.add_hr()
            i = i + 1
            continue
        if len(para) > 0 and (string.starts_with(t, "===") or string.starts_with(t, "---")) and _only(t, str(t[0])):
            lvl := 1 if string.starts_with(t, "=") else 2
            d.add_heading(parse_inline(string.join(" ", para)), lvl)
            para = []
            i = i + 1
            continue
        if string.starts_with(t, ">"):
            _flush_para(d, para)
            para = []
            q := []
            while i < n and string.starts_with(string.trim(lines[i]), ">"):
                append(q, string.trim(_n.str_slice(string.trim(lines[i]), 1, null)))
                i = i + 1
            d.add_quote(parse_inline(string.join(" ", q)))
            continue
        if string.starts_with(t, "|") and i + 1 < n and _is_sep_row(lines[i + 1]):
            _flush_para(d, para)
            para = []
            rows := [_split_row(t)]
            i = i + 2
            while i < n and string.contains(lines[i], "|") and string.trim(lines[i]) != "":
                append(rows, _split_row(lines[i]))
                i = i + 1
            b := Block("table")
            for r in rows:
                line_cells := []
                for c in r:
                    append(line_cells, parse_inline(string.replace(c, "<br>", "\n")))
                append(b.rows, line_cells)
            b.header = true
            d.add(b)
            continue
        if string.starts_with(t, "![") and string.contains(t, "](data:"):
            _flush_para(d, para)
            para = []
            p0 := string.find(t, "](data:")
            alt := _n.str_slice(t, 2, p0)
            rest := _n.str_slice(t, p0 + 7, null)
            comma := string.find(rest, ",")
            end := string.find(rest, ")")
            if comma > 0 and end > comma:
                try:
                    d.add_image(u.base64_decode(_n.str_slice(rest, comma + 1, end)), null, null, alt)
                catch e:
                    d.add_paragraph(alt)
            i = i + 1
            continue
        lm := _list_marker(line)
        if lm != null:
            _flush_para(d, para)
            para = []
            ind := lm[0]
            while len(list_indents) > 0 and list_indents[len(list_indents) - 1] > ind:
                collections.pop(list_indents)
            if len(list_indents) == 0 or list_indents[len(list_indents) - 1] < ind:
                append(list_indents, ind)
            txt := lm[2]
            # lignes de continuation
            while i + 1 < n and string.trim(lines[i + 1]) != "" and _list_marker(lines[i + 1]) == null and string.starts_with(lines[i + 1], "  "):
                txt = txt + " " + string.trim(lines[i + 1])
                i = i + 1
            d.add_list_item(parse_inline(txt), len(list_indents) - 1, lm[1])
            i = i + 1
            continue
        list_indents = []
        if string.contains(t, "page-break-after"):
            _flush_para(d, para)
            para = []
            d.add_page_break()
            i = i + 1
            continue
        hard := string.ends_with(line, "  ")
        append(para, t + ("\n" if hard else ""))
        i = i + 1
    _flush_para(d, para)
    return d

func _only(t, ch):
    for c in t:
        if str(c) != ch:
            return false
    return true

func _flush_para(d, para):
    if len(para) == 0:
        return null
    txt := ""
    for p in para:
        if txt != "" and not string.ends_with(txt, "\n"):
            txt = txt + " "
        txt = txt + p
    d.add_paragraph(parse_inline(string.trim(txt)))

func from_text(text):
    d := Document()
    para := []
    for line in u.lines(text):
        if string.trim(line) == "":
            if len(para) > 0:
                d.add_paragraph(string.join("\n", para))
                para = []
        elif line == "\x0c":
            if len(para) > 0:
                d.add_paragraph(string.join("\n", para))
                para = []
            d.add_page_break()
        else:
            append(para, line)
    if len(para) > 0:
        d.add_paragraph(string.join("\n", para))
    return d

# ---------------------------------------------------------------------------------------------- HTML -> Document

func _inline_runs(node, fmt, out):
    for c in node["children"]:
        if type(c) == "str":
            t := c
            # espaces HTML repliés
            t = string.replace(string.replace(string.replace(t, "\r", " "), "\n", " "), "\t", " ")
            while string.contains(t, "  "):
                t = string.replace(t, "  ", " ")
            if t != "":
                append(out, Run(t, u.merge(fmt, null)))
            continue
        if not x.is_element(c):
            continue
        tag := c["tag"]
        f2 := u.merge(fmt, null)
        if tag == "b" or tag == "strong":
            f2["bold"] = true
        elif tag == "i" or tag == "em" or tag == "cite":
            f2["italic"] = true
        elif tag == "u" or tag == "ins":
            f2["underline"] = true
        elif tag == "s" or tag == "del" or tag == "strike":
            f2["strike"] = true
        elif tag == "code" or tag == "kbd" or tag == "samp" or tag == "tt":
            f2["code"] = true
        elif tag == "sup":
            f2["superscript"] = true
        elif tag == "sub":
            f2["subscript"] = true
        elif tag == "a":
            href := u.get(c["attrs"], "href", null)
            if href != null:
                f2["link"] = href
        elif tag == "br":
            append(out, Run("\n", u.merge(fmt, null)))
            continue
        elif tag == "img":
            continue
        elif tag == "span" or tag == "font":
            st := u.get(c["attrs"], "style", "")
            col := u.get(c["attrs"], "color", null)
            if string.contains(st, "font-weight:bold") or string.contains(st, "font-weight: bold") or string.contains(st, "font-weight:700"):
                f2["bold"] = true
            if string.contains(st, "font-style:italic") or string.contains(st, "font-style: italic"):
                f2["italic"] = true
            if col != null:
                try:
                    f2["color"] = u.color_hex(col)
                catch e:
                    f2["color"] = null
        _inline_runs(c, f2, out)

func _trim_runs(rs):
    out := []
    for r in rs:
        append(out, r)
    while len(out) > 0 and string.trim(out[0].text) == "" and out[0].text != "\n":
        collections.pop(out, 0)
    if len(out) > 0:
        out[0].text = _lstrip(out[0].text)
    while len(out) > 0 and string.trim(out[len(out) - 1].text) == "":
        collections.pop(out)
    if len(out) > 0:
        last := out[len(out) - 1]
        while string.ends_with(last.text, " "):
            last.text = _n.str_slice(last.text, 0, len(last.text) - 1)
    return out

func _lstrip(s):
    t := s
    while string.starts_with(t, " "):
        t = _n.str_slice(t, 1, null)
    return t

const _BLOCK_TAGS := {"p": true, "div": true, "h1": true, "h2": true, "h3": true, "h4": true, "h5": true, "h6": true, "ul": true, "ol": true, "li": true, "table": true, "pre": true, "blockquote": true, "hr": true, "figure": true, "section": true, "article": true, "header": true, "footer": true, "main": true, "nav": true, "aside": true, "body": true, "html": true, "dl": true, "dt": true, "dd": true, "img": true, "figcaption": true}

func _has_block(node):
    for c in node["children"]:
        if x.is_element(c) and contains_key(_BLOCK_TAGS, c["tag"]):
            return true
    return false

func _html_blocks(node, d, list_level, ordered):
    inline := []
    for c in node["children"]:
        if type(c) == "str" or (x.is_element(c) and not contains_key(_BLOCK_TAGS, c["tag"])):
            append(inline, c)
            continue
        if not x.is_element(c):
            continue
        if len(inline) > 0:
            rs := []
            _inline_runs({"children": inline}, {}, rs)
            rs = _trim_runs(rs)
            if len(rs) > 0:
                d.add_runs(rs)
            inline = []
        tag := c["tag"]
        if tag == "script" or tag == "style" or tag == "head" or tag == "title" or tag == "nav":
            continue
        if len(tag) == 2 and str(tag[0]) == "h" and string.ord(tag[1]) >= 49 and string.ord(tag[1]) <= 54:
            rs := []
            _inline_runs(c, {}, rs)
            b := d.add_runs(_trim_runs(rs), "heading")
            b.level = string.ord(tag[1]) - 48
        elif tag == "p" or tag == "dt" or tag == "dd" or tag == "figcaption":
            if _has_block(c):
                _html_blocks(c, d, list_level, ordered)
            else:
                rs := []
                _inline_runs(c, {}, rs)
                rs = _trim_runs(rs)
                if len(rs) > 0:
                    b := d.add_runs(rs)
                    st := u.get(c["attrs"], "style", "")
                    if string.contains(st, "text-align:center") or string.contains(st, "text-align: center"):
                        b.align = "center"
                    elif string.contains(st, "text-align:right") or string.contains(st, "text-align: right"):
                        b.align = "right"
                    elif string.contains(st, "justify"):
                        b.align = "justify"
                for img in x.find_all(c, "img"):
                    _html_img(img, d)
        elif tag == "ul" or tag == "ol":
            for li in x.children(c, "li"):
                rs := []
                inl := []
                subs := []
                for g in li["children"]:
                    if x.is_element(g) and (g["tag"] == "ul" or g["tag"] == "ol"):
                        append(subs, g)
                    elif x.is_element(g) and g["tag"] == "p":
                        for gg in g["children"]:
                            append(inl, gg)
                    else:
                        append(inl, g)
                _inline_runs({"children": inl}, {}, rs)
                rs = _trim_runs(rs)
                b := d.add_runs(rs, "list_item")
                b.level = list_level
                b.ordered = tag == "ol"
                for s in subs:
                    _html_blocks({"children": [s]}, d, list_level + 1, s["tag"] == "ol")
        elif tag == "pre":
            lang := ""
            code_el := x.find(c, "code")
            if code_el != null:
                for cls in string.split(u.get(code_el["attrs"], "class", ""), " "):
                    if string.starts_with(cls, "language-"):
                        lang = _n.str_slice(cls, 9, null)
            d.add_code(x.text(c), lang)
        elif tag == "blockquote":
            rs := []
            _inline_runs(c, {}, rs)
            d.add_runs(_trim_runs(rs), "quote")
        elif tag == "hr":
            d.add_hr()
        elif tag == "img":
            _html_img(c, d)
        elif tag == "table":
            b := Block("table")
            grids := html.extract_tables({"tag": "#document", "attrs": {}, "children": [c]})
            if len(grids) > 0:
                for row in grids[0]:
                    line := []
                    for cell in row:
                        append(line, [Run(cell)])
                    append(b.rows, line)
            b.header = len(x.find_all(c, "th")) > 0
            d.add(b)
        elif tag == "figure":
            for img in x.find_all(c, "img"):
                cap := x.find(c, "figcaption")
                _html_img(img, d, string.trim(x.text(cap)) if cap != null else null)
        else:
            _html_blocks(c, d, list_level, ordered)
    if len(inline) > 0:
        rs := []
        _inline_runs({"children": inline}, {}, rs)
        rs = _trim_runs(rs)
        if len(rs) > 0:
            d.add_runs(rs)

func _html_img(img, d, caption=null):
    src := u.get(img["attrs"], "src", "")
    if string.starts_with(src, "data:"):
        comma := string.find(src, ",")
        if comma > 0:
            try:
                d.add_image(u.base64_decode(_n.str_slice(src, comma + 1, null)), null, null, u.get(img["attrs"], "alt", ""), caption)
            catch e:
                return null

func from_html(text):
    root := html.parse(text) if type(text) == "str" else text
    d := Document(html.title(root))
    body := x.find(root, "body")
    _html_blocks(body if body != null else root, d, 0, false)
    return d

# ---------------------------------------------------------------------------------------------- DOCX

const _CODE_FONT := "Consolas"

func _docx_fmt(r):
    f := {}
    if r.bold:
        f["bold"] = true
    if r.italic:
        f["italic"] = true
    if r.underline:
        f["underline"] = true
    if r.strike:
        f["strike"] = true
    if r.color != null:
        f["color"] = r.color
    if r.size != null:
        f["size"] = r.size
    if r.font != null:
        f["font"] = r.font
    elif r.code:
        f["font"] = _CODE_FONT
    if r.superscript:
        f["superscript"] = true
    if r.subscript:
        f["subscript"] = true
    return f

func _docx_runs(p, rs):
    for r in rs:
        if r.link != null:
            lk := p.add_link(r.text, r.link)
            lk.set_props(_docx_fmt(r))
        else:
            p.add_run(r.text, _docx_fmt(r))
    return p

func to_docx(d):
    w := word.new()
    w.metadata = d.metadata
    if d.title != "" and w.metadata.title == "":
        w.metadata.title = d.title
    for b in d.blocks:
        k := b.kind
        if k == "heading":
            lvl := b.level if b.level >= 0 and b.level <= 9 else 1
            p := w.add_heading("", lvl)
            _docx_runs(p, b.runs)
        elif k == "paragraph":
            p := w.add_paragraph("", b.style if b.style != null else null, b.align)
            _docx_runs(p, b.runs)
        elif k == "list_item":
            p := w.add_numbered("", b.level) if b.ordered else w.add_bullet("", b.level)
            _docx_runs(p, b.runs)
        elif k == "quote":
            p := w.add_quote("")
            _docx_runs(p, b.runs)
        elif k == "code":
            w.add_code(b.text)
        elif k == "hr":
            w.add_horizontal_rule()
        elif k == "page_break":
            w.add_page_break()
        elif k == "image":
            wd := b.width
            ht := b.height
            w.add_image(b.image, wd, ht, b.caption, "center", b.alt)
        elif k == "table":
            ncol := 0
            for r in b.rows:
                if len(r) > ncol:
                    ncol = len(r)
            t := dt.Table(0, ncol)
            for r in b.rows:
                cells := []
                for c in r:
                    cell := dt.Cell()
                    _docx_runs(cell.paragraph(), c)
                    append(cells, cell)
                while len(cells) < ncol:
                    append(cells, dt.Cell())
                append(t.rows, dt.Row(cells))
            if b.header and len(b.rows) > 0:
                t.style_header(true, null)
            w.add_block(t)
    return w

func _from_docx_run(r):
    f := {}
    if r.bold == true:
        f["bold"] = true
    if r.italic == true:
        f["italic"] = true
    if r.underline != null and r.underline != false and r.underline != "none":
        f["underline"] = true
    if r.strike == true:
        f["strike"] = true
    if r.color != null and r.color != "auto":
        f["color"] = r.color
    if r.size != null:
        f["size"] = r.size
    if r.font != null:
        if r.font == _CODE_FONT or r.font == "Courier New" or r.font == "Consolas" or r.font == "Courier":
            f["code"] = true
        else:
            f["font"] = r.font
    if r.style == "InlineCode":
        f["code"] = true
    if r.superscript == true:
        f["superscript"] = true
    if r.subscript == true:
        f["subscript"] = true
    if r.link != null:
        f["link"] = r.link
    return f

# Paragraphe Word -> [segments, images, saut_de_page]
func _docx_para_runs(p):
    rs := []
    imgs := []
    brk := false
    for r in p.runs:
        if r.kind == "text" or r.kind == "field":
            t := r.text
            if t != "":
                append(rs, Run(t, _from_docx_run(r)))
        elif r.kind == "tab":
            append(rs, Run("\t", _from_docx_run(r)))
        elif r.kind == "break":
            if r.break_type == "page":
                brk = true
            else:
                append(rs, Run("\n", _from_docx_run(r)))
        elif r.kind == "image" and r.image != null:
            append(imgs, r.image)
    return [_merge_runs(rs), imgs, brk]

func _merge_runs(rs):
    out := []
    for r in rs:
        if len(out) > 0 and out[len(out) - 1].same_format(r):
            out[len(out) - 1].text = out[len(out) - 1].text + r.text
        else:
            append(out, r)
    return out

func from_docx(src):
    w := src if isinstance(src, word.WordDocument) else word.open(src)
    d := Document(w.metadata.title)
    d.metadata = w.metadata
    code := []
    pending_caption := null
    for blk in w.body:
        if isinstance(blk, dt.Table):
            if len(code) > 0:
                d.add_code(string.join("\n", code))
                code = []
            b := Block("table")
            for row in blk.rows:
                line := []
                for cell in row.cells:
                    if cell.merged:
                        append(line, [])
                        continue
                    cr := []
                    first := true
                    for cp in cell.paragraphs:
                        if not isinstance(cp, dp.Paragraph):
                            continue
                        if not first:
                            append(cr, Run("\n"))
                        for r in _docx_para_runs(cp)[0]:
                            append(cr, r)
                        first = false
                    append(line, _merge_runs(cr))
                append(b.rows, line)
            b.header = len(blk.rows) > 0 and (blk.rows[0].header == true or _row_bold(blk.rows[0]))
            if b.header and len(b.rows) > 0:
                for c in b.rows[0]:
                    for r in c:
                        r.bold = false
            d.add(b)
            continue
        if not isinstance(blk, dp.Paragraph):
            continue
        p := blk
        st := p.style
        if st == "Code":
            append(code, p.text())
            continue
        if len(code) > 0:
            d.add_code(string.join("\n", code))
            code = []
        parts := _docx_para_runs(p)
        rs := parts[0]
        if parts[2] or p.page_break_before == true:
            d.add_page_break()
        for im in parts[1]:
            ib := d.add_image(im.image, u.round_to(to_float(im.cx) / 12700.0, 1), u.round_to(to_float(im.cy) / 12700.0, 1), im.description)
        lvl := p.heading_level()
        if lvl != null:
            if len(rs) > 0:
                b := d.add_runs(rs, "heading")
                b.level = lvl
                if lvl <= 1 and d.title == "":
                    d.title = runs_text(rs)
        elif st == "Subtitle":
            if len(rs) > 0:
                b := d.add_runs(rs)
                b.style = "subtitle"
        elif p.list != null:
            b := d.add_runs(rs, "list_item")
            b.level = u.get(p.list, "level", 0)
            b.ordered = u.get(p.list, "kind", "bullet") == "number"
        elif st == "Quote" or st == "IntenseQuote":
            d.add_runs(rs, "quote")
        elif st == "Caption" and len(d.blocks) > 0 and d.blocks[len(d.blocks) - 1].kind == "image" and d.blocks[len(d.blocks) - 1].caption == null:
            d.blocks[len(d.blocks) - 1].caption = runs_text(rs)
        elif len(rs) == 0 and p.border_bottom != null and p.border_bottom != false:
            d.add_hr()
        elif len(rs) > 0:
            b := d.add_runs(rs)
            b.align = p.align
            if st != null and st != "Normal":
                b.style = st
    if len(code) > 0:
        d.add_code(string.join("\n", code))
    return d

func _row_bold(row):
    if len(row.cells) == 0:
        return false
    for c in row.cells:
        for p in c.paragraphs:
            if isinstance(p, dp.Paragraph):
                for r in p.runs:
                    if r.kind == "text" and r.text != "" and r.bold != true:
                        return false
    return true

# ---------------------------------------------------------------------------------------------- PDF

func _pdf_runs(rs):
    out := []
    for r in rs:
        f := {}
        if r.bold:
            f["bold"] = true
        if r.italic:
            f["italic"] = true
        if r.underline:
            f["underline"] = true
        if r.color != null:
            f["color"] = r.color
        if r.size != null:
            f["size"] = r.size
        if r.code:
            f["font"] = "Courier"
        if r.link != null:
            f["link"] = r.link
        append(out, [r.text, f if len(keys(f)) > 0 else null])
    if len(out) == 0:
        append(out, ["", null])
    return out

# options : {"size": "A4", "landscape": false, "margins": 56.7, "font": "Helvetica", "font_size": 11, "toc": false,
#   "footer": "Page {page} / {total}", "header": null}
func to_pdf(d, options=null):
    o := options if options != null else {}
    doc := pdf.new(u.get(o, "size", "A4"), u.get(o, "landscape", false), u.get(o, "margins", 56.7), u.get(o, "font", "Helvetica"), u.get(o, "font_size", 11))
    t := d.title if d.title != "" else d.metadata.title
    if t != "":
        doc.info["Title"] = t
    if d.metadata.creator != "":
        doc.info["Author"] = d.metadata.creator
    if u.get(o, "toc", false):
        doc.add_toc()
    if u.get(o, "header", null) != null:
        doc.set_header(o["header"])
    if u.get(o, "footer", "Page {page} / {total}") != null:
        doc.set_footer(u.get(o, "footer", "Page {page} / {total}"))
    for b in d.blocks:
        k := b.kind
        if k == "heading":
            lvl := b.level if b.level >= 0 else 1
            st := "title" if lvl == 0 else "h" + str(lvl if lvl <= 6 else 6)
            doc._add({"type": "heading", "level": lvl, "runs": _pdf_runs(b.runs), "style": st, "align": b.align})
        elif k == "paragraph":
            st := "subtitle" if b.style == "subtitle" else "normal"
            doc.add_rich(_pdf_runs(b.runs), st, b.align)
        elif k == "list_item":
            if b.ordered:
                doc.add_numbered(_pdf_runs(b.runs), b.level)
            else:
                doc.add_bullet(_pdf_runs(b.runs), b.level)
        elif k == "quote":
            doc.add_rich(_pdf_runs(b.runs), "quote")
        elif k == "code":
            doc.add_code(b.text)
        elif k == "hr":
            doc.add_hr()
        elif k == "page_break":
            doc.add_page_break()
        elif k == "image":
            doc.add_image(b.image, b.width, b.height, "center", b.caption)
        elif k == "table":
            rows := []
            for r in b.rows:
                line := []
                for c in r:
                    append(line, runs_text(c))
                append(rows, line)
            doc.add_table(rows, b.header)
    return doc
