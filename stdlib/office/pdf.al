# ALEX STANDARD LIBRARY — office.pdf
# PDF : façade de haut niveau. Création de documents mis en page automatiquement (titres, paragraphes riches avec
# retour à la ligne et justification, listes, tableaux paginés, images, en-têtes et pieds de page, numéros de page,
# signets automatiques, sommaire), lecture, extraction (texte, images, tableaux), fusion, découpage, opérations
# sur les pages, métadonnées.
#
#   use office.pdf as pdf
#   doc := pdf.new()                                        # A4, marges 2 cm, Helvetica 11 pt
#   doc.add_heading("Rapport annuel", 0)
#   doc.add_paragraph("Introduction avec du texte justifié qui se répartit sur plusieurs lignes...", "normal", "justify")
#   doc.add_rich([["Texte ", null], ["en gras", {"bold": true}], [" et un ", null], ["lien", {"link": "https://example.org"}]])
#   doc.add_bullet("premier point")
#   doc.add_table([["Produit", "Qté"], ["Pommes", 3]])
#   doc.add_image("graphique.png", 300)
#   doc.set_footer("Page {page} / {total}")
#   doc.save("rapport.pdf")
#
#   pdf.text("facture.pdf")                                 # texte
#   pdf.tables("releve.pdf")                                # tableaux détectés
#   pdf.merge(["a.pdf", "b.pdf"], "ab.pdf")
#   pdf.split("livre.pdf", "pages/p-{n}.pdf")
#   pdf.rotate("scan.pdf", "scan2.pdf", 90)
#   pdf.metadata("doc.pdf")                                 # {"Title": ..., "Author": ...}
#   pdf.set_metadata("doc.pdf", {"Title": "Nouveau"}, "doc2.pdf")
#
# CRÉATION   new(size="A4", landscape=false, margins=56.7, font="Helvetica", font_size=11) -> PdfDocument
#            from_text(texte, out=null, font="Helvetica", size=11)   from_images(images, out=null, size=null)
#            (size null : une page à la taille de chaque image ; "A4" : images centrées et ajustées)
#            builder() -> pdf_writer.PdfBuilder (dessin libre, voir pdf_writer)
# PdfDocument : styles (dict nom -> style)  add_heading(t, level=1)  add_paragraph(t, style="normal", align=null)
#            add_rich(segments, style="normal", align=null) (segments : [texte, format] ; format : bold italic
#            underline color size font link)  add_bullet(t, level=0)  add_numbered(t, level=0, restart=false)
#            add_list(items, ordered=false)  add_table(lignes, header=true, widths=null, style=null)
#            add_image(image, width=null, height=null, align="center", caption=null)  add_page_break()
#            add_spacer(h)  add_hr()  add_code(t)  add_quote(t)  add_toc(title="Table des matières")
#            set_header(t, align="center")  set_footer(t, align="center") ({page} {total} {title} {date})
#            info (dict)  page_count()  to_bytes()  save(chemin)
#            Styles : normal h1..h6 title subtitle quote code caption list toc ; clés : font size bold italic
#            color space_before space_after leading align indent
# LECTURE    open(src, password="") -> pdf_reader.PdfFile   page_count(src)   info(src) (pages et boîtes)
#            text(src, pages=null, layout=false)   words(src, page)   search(src, motif)   images(src, pages=null)
#            tables(src, pages=null, strategy="auto")   links(src)   fonts(src)   outlines(src)   attachments(src)
#            metadata(src) -> dict   set_metadata(src, dict, out)
# PAGES      merge(sources, out, bookmarks=false)  split(src, modele)  split_ranges(src, plages, modele)
#            extract(src, pages, out=null)  rotate  crop  delete_pages  reorder  reverse  insert_blank  scale_to
#            watermark  stamp_text  number_pages  overlay  (voir pdf_pages / pdf_merge / pdf_split)
# Erreurs : PDFError, UnsupportedError, IoError, ValueError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.core as core
use office.pdf_reader as pr
use office.pdf_writer as pw
use office.pdf_extract as ex
use office.pdf_tables as ptab
use office.pdf_pages as ppages
use office.pdf_merge as pmerge
use office.pdf_split as psplit

const DEFAULT_STYLES := {"normal": {"size": 11.0, "space_after": 6.0, "leading": 1.3}, "title": {"size": 26.0, "bold": true, "space_after": 14.0, "leading": 1.15, "color": "1F3864"}, "subtitle": {"size": 15.0, "color": "595959", "space_after": 12.0}, "h1": {"size": 18.0, "bold": true, "space_before": 16.0, "space_after": 8.0, "color": "2F5496", "leading": 1.2}, "h2": {"size": 14.5, "bold": true, "space_before": 12.0, "space_after": 6.0, "color": "2F5496", "leading": 1.2}, "h3": {"size": 12.5, "bold": true, "space_before": 10.0, "space_after": 4.0, "color": "1F3864"}, "h4": {"size": 11.5, "bold": true, "italic": true, "space_before": 8.0, "space_after": 4.0}, "h5": {"size": 11.0, "bold": true, "space_before": 6.0, "space_after": 3.0}, "h6": {"size": 11.0, "italic": true, "space_before": 6.0, "space_after": 3.0}, "quote": {"size": 11.0, "italic": true, "color": "404040", "indent": 28.0, "space_after": 8.0}, "code": {"font": "Courier", "size": 9.5, "space_after": 0.0, "leading": 1.25, "background": "F2F2F2"}, "caption": {"size": 9.0, "italic": true, "color": "44546A", "align": "center", "space_after": 10.0}, "list": {"size": 11.0, "space_after": 3.0, "leading": 1.3}, "toc": {"size": 11.0, "space_after": 2.0}}

func _runs_plain(runs):
    out := []
    for r in runs:
        append(out, u.to_text(r[0]))
    return string.join("", out)

func _fmt_font(base, fmt, st):
    fam := u.get(fmt, "font", u.get(st, "font", base)) if fmt != null else u.get(st, "font", base)
    bold := (u.get(fmt, "bold", null) if fmt != null else null)
    if bold == null:
        bold = u.get(st, "bold", false)
    italic := (u.get(fmt, "italic", null) if fmt != null else null)
    if italic == null:
        italic = u.get(st, "italic", false)
    return pw.resolve_font(fam, bold, italic)

class PdfDocument:
    func init(size="A4", landscape=false, margins=56.7, font="Helvetica", font_size=11):
        self.page_size = core.page_size(size, landscape)
        m := margins
        if type(m) != "dict":
            v := u.emu_to_pt(u.length(m, "pt"))
            m = {"top": v, "bottom": v, "left": v, "right": v}
        else:
            mm := {}
            for k in ["top", "bottom", "left", "right"]:
                mm[k] = u.emu_to_pt(u.length(u.get(m, k, 56.7), "pt"))
            m = mm
        self.margins = m
        self.font = font
        self.styles = u.deep_copy(DEFAULT_STYLES)
        self.styles["normal"]["size"] = to_float(font_size)
        self.blocks = []
        self.header = null
        self.footer = null
        self.info = {"Producer": "ALEX Office", "Creator": "ALEX Office"}
        self._list_counter = 0
        self._last_numbered = false
        self._pages = 0

    # ---------------------------------------------------------- ajout
    func _add(b):
        append(self.blocks, b)
        if b["type"] != "list" or b["kind"] != "number":
            self._last_numbered = false
        return b

    func add_heading(text, level=1):
        st := "title" if level == 0 else "h" + str(level if level <= 6 else 6)
        return self._add({"type": "heading", "level": level, "runs": [[u.to_text(text), null]], "style": st, "align": null})

    func add_paragraph(text="", style="normal", align=null):
        return self._add({"type": "paragraph", "runs": [[u.to_text(text), null]], "style": style, "align": align})

    func add_rich(segments, style="normal", align=null):
        runs := []
        for s in segments:
            if type(s) == "str":
                append(runs, [s, null])
            else:
                append(runs, [u.to_text(s[0]), s[1] if len(s) > 1 else null])
        return self._add({"type": "paragraph", "runs": runs, "style": style, "align": align})

    func add_bullet(text, level=0):
        r := text if type(text) == "list" else [[u.to_text(text), null]]
        return self._add({"type": "list", "kind": "bullet", "level": level, "runs": r, "style": "list", "number": 0})

    func add_numbered(text, level=0, restart=false):
        if restart or not self._last_numbered:
            self._list_counter = self._list_counter + 1
        r := text if type(text) == "list" else [[u.to_text(text), null]]
        b := {"type": "list", "kind": "number", "level": level, "runs": r, "style": "list", "list_id": self._list_counter}
        append(self.blocks, b)
        self._last_numbered = true
        return b

    func _items(items, ordered, level, first):
        for it in items:
            if type(it) == "list" or type(it) == "tuple":
                self._items(it, ordered, level + 1, false)
            elif ordered:
                self.add_numbered(u.to_text(it), level, first and level == 0)
                first = false
            else:
                self.add_bullet(u.to_text(it), level)

    func add_list(items, ordered=false):
        self._items(items, ordered, 0, true)

    func add_table(rows, header=true, widths=null, style=null):
        st := u.merge({"header": header, "font": self.font, "size": self.styles["normal"]["size"] - 1.0}, style)
        return self._add({"type": "table", "rows": rows, "widths": widths, "style": st})

    func add_image(image, width=null, height=null, align="center", caption=null):
        return self._add({"type": "image", "image": core.load_image(image), "width": width, "height": height, "align": align, "caption": caption})

    func add_page_break():
        return self._add({"type": "pagebreak"})

    func add_spacer(h):
        return self._add({"type": "spacer", "height": to_float(h)})

    func add_hr():
        return self._add({"type": "hr"})

    func add_code(text):
        return self._add({"type": "code", "text": u.to_text(text), "style": "code"})

    func add_quote(text):
        return self.add_paragraph(text, "quote")

    func add_toc(title="Table des matières"):
        return self._add({"type": "toc", "title": title})

    func set_header(text, align="center"):
        self.header = [text, align]

    func set_footer(text, align="center"):
        self.footer = [text, align]

    # ---------------------------------------------------------- mise en page
    func _st(name):
        base := u.merge({"font": self.font}, self.styles["normal"])
        if name != "normal" and contains_key(self.styles, name):
            return u.merge(base, self.styles[name])
        return base

    func _content_width():
        return self.page_size[0] - self.margins["left"] - self.margins["right"]

    func _new_page(ctx):
        c := ctx["builder"].new_page([self.page_size[0], self.page_size[1]])
        ctx["canvas"] = c
        ctx["y"] = self.page_size[1] - self.margins["top"]
        ctx["page"] = ctx["page"] + 1
        return c

    func _bottom():
        return self.margins["bottom"]

    func _ensure(ctx, h):
        if ctx["y"] - h < self._bottom() and ctx["y"] < self.page_size[1] - self.margins["top"] - 0.5:
            self._new_page(ctx)

    # Découpe des segments en mots mis en forme : [texte, police, taille, couleur, lien, souligné, est_espace]
    func _words(runs, st):
        out := []
        for r in runs:
            fmt := r[1]
            font := _fmt_font(self.font, fmt, st)
            size := to_float(u.get(fmt, "size", st["size"])) if fmt != null else to_float(st["size"])
            color := u.get(fmt, "color", u.get(st, "color", "000000")) if fmt != null else u.get(st, "color", "000000")
            link := u.get(fmt, "link", null) if fmt != null else null
            under := (u.get(fmt, "underline", false) == true) if fmt != null else false
            if link != null and (fmt == null or u.get(fmt, "color", null) == null):
                color = "0563C1"
                under = true
            text := r[0]
            parts := string.split(string.replace(text, "\t", "    "), "\n")
            pi := 0
            for part in parts:
                if pi > 0:
                    append(out, ["\n", font, size, color, link, under, true])
                buf := ""
                for c in part:
                    ch := str(c)
                    if ch == " ":
                        if buf != "":
                            append(out, [buf, font, size, color, link, under, false])
                            buf = ""
                        append(out, [" ", font, size, color, link, under, true])
                    else:
                        buf = buf + ch
                if buf != "":
                    append(out, [buf, font, size, color, link, under, false])
                pi = pi + 1
        return out

    func _lines(words, width):
        lines := []
        cur := []
        w := 0.0
        for wd in words:
            if wd[0] == "\n":
                append(lines, [cur, true])
                cur = []
                w = 0.0
                continue
            ww := pw.text_width(wd[0], wd[1], wd[2])
            if wd[6]:
                if len(cur) == 0:
                    continue
                append(cur, wd)
                w = w + ww
                continue
            if w + ww > width and len(cur) > 0:
                # retire les espaces finaux
                while len(cur) > 0 and cur[len(cur) - 1][6]:
                    collections.pop(cur)
                append(lines, [cur, false])
                cur = []
                w = 0.0
            # mot plus large que la ligne : coupé en morceaux
            if ww > width:
                piece := ""
                for c in wd[0]:
                    if pw.text_width(piece + str(c), wd[1], wd[2]) > width and piece != "":
                        append(lines, [[[piece, wd[1], wd[2], wd[3], wd[4], wd[5], false]], false])
                        piece = ""
                    piece = piece + str(c)
                append(cur, [piece, wd[1], wd[2], wd[3], wd[4], wd[5], false])
                w = pw.text_width(piece, wd[1], wd[2])
                continue
            append(cur, wd)
            w = w + ww
        while len(cur) > 0 and cur[len(cur) - 1][6]:
            collections.pop(cur)
        append(lines, [cur, true])
        return lines

    func _draw_line(ctx, line, x0, width, align, last):
        c := ctx["canvas"]
        words := line[0]
        if len(words) == 0:
            return null
        total := 0.0
        spaces := 0
        maxs := 0.0
        for wd in words:
            total = total + pw.text_width(wd[0], wd[1], wd[2])
            if wd[6]:
                spaces = spaces + 1
            if wd[2] > maxs:
                maxs = wd[2]
        x := to_float(x0)
        extra := 0.0
        if align == "center":
            x = x + (width - total) / 2.0
        elif align == "right":
            x = x + width - total
        elif align == "justify" and not last and spaces > 0:
            extra = (width - total) / to_float(spaces)
        y := ctx["y"] - maxs * 0.8
        for wd in words:
            ww := pw.text_width(wd[0], wd[1], wd[2])
            if wd[6]:
                if wd[5] or wd[4] != null:
                    # soulignement / lien continu sur l'espace
                    if wd[5]:
                        c.set_stroke(wd[3])
                        c.set_line_width(wd[2] * 0.05)
                        c.line(x, y - wd[2] * 0.12, x + ww + extra, y - wd[2] * 0.12)
                    if wd[4] != null and not string.starts_with(wd[4], "#"):
                        c.link(x, y - wd[2] * 0.25, ww + extra, wd[2], wd[4])
                x = x + ww + extra
                continue
            c.rich_line(x, y, [[wd[0], wd[1], wd[2], wd[3]]])
            if wd[5]:
                c.set_stroke(wd[3])
                c.set_line_width(wd[2] * 0.05)
                c.line(x, y - wd[2] * 0.12, x + ww, y - wd[2] * 0.12)
            if wd[4] != null:
                if string.starts_with(wd[4], "#page"):
                    c.link_page(x, y - wd[2] * 0.25, ww, wd[2], to_int(u.parse_number(_n.str_slice(wd[4], 5, null))) - 1)
                elif not string.starts_with(wd[4], "#"):
                    c.link(x, y - wd[2] * 0.25, ww, wd[2], wd[4])
            x = x + ww
        c.set_fill("000000")

    func _paragraph(ctx, runs, st, align, indent=0.0, marker=null, keep_next=false):
        width := self._content_width() - indent - to_float(u.get(st, "indent", 0.0))
        x0 := self.margins["left"] + indent + to_float(u.get(st, "indent", 0.0))
        words := self._words(runs, st)
        lines := self._lines(words, width)
        lead_f := to_float(u.get(st, "leading", 1.3))
        ctx["y"] = ctx["y"] - to_float(u.get(st, "space_before", 0.0)) if ctx["y"] < self.page_size[1] - self.margins["top"] - 0.5 else ctx["y"]
        need_first := to_float(st["size"]) * lead_f * (2.0 if keep_next else 1.0)
        self._ensure(ctx, need_first)
        al := align if align != null else u.get(st, "align", "left")
        k := 0
        for line in lines:
            maxs := to_float(st["size"])
            for wd in line[0]:
                if wd[2] > maxs:
                    maxs = wd[2]
            lh := maxs * lead_f
            self._ensure(ctx, lh)
            if k == 0 and marker != null:
                c := ctx["canvas"]
                mf := pw.resolve_font(self.font)
                c.set_font(mf, st["size"])
                c.text(x0 - 4.0, ctx["y"] - maxs * 0.8, marker, "right")
            self._draw_line(ctx, line, x0, width, al, line[1])
            ctx["y"] = ctx["y"] - lh
            k = k + 1
        ctx["y"] = ctx["y"] - to_float(u.get(st, "space_after", 0.0))

    func _layout(ctx):
        numbers := {}
        for b in self.blocks:
            t := b["type"]
            if t == "heading":
                st := self._st(b["style"])
                if b["level"] >= 1 and b["level"] <= 6:
                    append(ctx["headings"], {"title": _runs_plain(b["runs"]), "page": ctx["page"], "level": b["level"], "top": ctx["y"]})
                self._paragraph(ctx, b["runs"], st, b["align"], 0.0, null, true)
                if b["level"] >= 1 and len(ctx["headings"]) > 0:
                    # page réelle du titre (après un éventuel saut)
                    h := ctx["headings"][len(ctx["headings"]) - 1]
                    h["page"] = ctx["page"]
                    if h["top"] > ctx["y"] + 200.0 and ctx["page"] != h["page"]:
                        h["top"] = self.page_size[1] - self.margins["top"]
            elif t == "paragraph":
                self._paragraph(ctx, b["runs"], self._st(b["style"]), b["align"])
            elif t == "list":
                st := self._st("list")
                indent := 18.0 * to_float(b["level"] + 1)
                marker := "•"
                if b["kind"] == "number":
                    key := str(b["list_id"]) + ":" + str(b["level"])
                    # remise à zéro des niveaux inférieurs
                    numbers[key] = (numbers[key] if contains_key(numbers, key) else 0) + 1
                    lvl := b["level"] + 1
                    while lvl < 9:
                        nk := str(b["list_id"]) + ":" + str(lvl)
                        if contains_key(numbers, nk):
                            collections.remove(numbers, nk)
                        lvl = lvl + 1
                    n := numbers[key]
                    marker = str(n) + "." if b["level"] % 3 == 0 else (str(string.chr(96 + ((n - 1) % 26) + 1)) + "." if b["level"] % 3 == 1 else _roman(n) + ".")
                else:
                    marker = ["•", "–", "·"][b["level"] % 3]
                self._paragraph(ctx, b["runs"], st, null, indent, marker)
            elif t == "table":
                self._table(ctx, b)
            elif t == "image":
                self._image(ctx, b)
            elif t == "pagebreak":
                self._new_page(ctx)
            elif t == "spacer":
                ctx["y"] = ctx["y"] - b["height"]
                if ctx["y"] < self._bottom():
                    self._new_page(ctx)
            elif t == "hr":
                self._ensure(ctx, 12.0)
                c := ctx["canvas"]
                c.set_stroke("A6A6A6")
                c.set_line_width(0.75)
                c.line(self.margins["left"], ctx["y"] - 6.0, self.page_size[0] - self.margins["right"], ctx["y"] - 6.0)
                ctx["y"] = ctx["y"] - 12.0
            elif t == "code":
                self._code(ctx, b)
            elif t == "toc":
                self._toc(ctx, b)

    func _code(ctx, b):
        st := self._st("code")
        lines := string.split(string.replace(b["text"], "\r\n", "\n"), "\n")
        lh := to_float(st["size"]) * to_float(st["leading"])
        font := pw.resolve_font(st["font"])
        width := self._content_width()
        for line in lines:
            parts := pw.wrap_text(line, width - 8.0, font, st["size"]) if line != "" else [""]
            for p in parts:
                self._ensure(ctx, lh)
                c := ctx["canvas"]
                c.set_fill(u.get(st, "background", "F2F2F2"))
                c.rect(self.margins["left"], ctx["y"] - lh, width, lh, true, false)
                c.set_fill("000000")
                c.set_font(font, st["size"])
                c.text(self.margins["left"] + 4.0, ctx["y"] - to_float(st["size"]) * 0.95, string.replace(p, "\t", "    "))
                ctx["y"] = ctx["y"] - lh
        ctx["y"] = ctx["y"] - 6.0

    func _table(ctx, b):
        rows := b["rows"]
        if len(rows) == 0:
            return null
        st := b["style"]
        width := self._content_width()
        widths := ptab._col_widths(rows, b["widths"], width, ptab._style(st))
        heights := ptab.measure(rows, widths, st)
        start := 0
        header := u.get(st, "header", true)
        while start < len(rows):
            avail := ctx["y"] - self._bottom()
            hdr_h := heights[0] if header and start > 0 else 0.0
            end := ptab.fit_rows(heights, avail - hdr_h, start)
            if end == start + 0 or (end == start + 1 and start == 0 and header and len(rows) > 1 and heights[0] + heights[1] > avail):
                if ctx["y"] < self.page_size[1] - self.margins["top"] - 0.5:
                    self._new_page(ctx)
                    continue
                end = start + 1
            h := ptab.draw_table(ctx["canvas"], self.margins["left"], ctx["y"], rows, widths, st, null, start, end, header and start > 0)
            ctx["y"] = ctx["y"] - h
            start = end
            if start < len(rows):
                self._new_page(ctx)
        ctx["y"] = ctx["y"] - 8.0

    func _image(ctx, b):
        im := b["image"]
        width := self._content_width()
        nat_w := to_float(im.width) * 72.0 / to_float(im.dpi_x if im.dpi_x > 0 else 96)
        nat_h := to_float(im.height) * 72.0 / to_float(im.dpi_y if im.dpi_y > 0 else 96)
        w := b["width"]
        h := b["height"]
        if w != null:
            w = u.emu_to_pt(u.length(w, "pt"))
        if h != null:
            h = u.emu_to_pt(u.length(h, "pt"))
        if w == null and h == null:
            w = nat_w
            h = nat_h
        elif w == null:
            w = h * nat_w / nat_h
        elif h == null:
            h = w * nat_h / nat_w
        if w > width:
            h = h * width / w
            w = width
        max_h := self.page_size[1] - self.margins["top"] - self.margins["bottom"]
        if h > max_h:
            w = w * max_h / h
            h = max_h
        cap := u.get(b, "caption", null)
        cap_h := 0.0
        if cap != null:
            cst := self._st("caption")
            cap_h = to_float(cst["size"]) * 1.3 * to_float(len(pw.wrap_text(cap, width, pw.resolve_font(self.font), cst["size"]))) + to_float(cst["space_after"])
        self._ensure(ctx, h + 4.0 + cap_h)
        x0 := self.margins["left"]
        if b["align"] == "center":
            x0 = x0 + (width - w) / 2.0
        elif b["align"] == "right":
            x0 = x0 + width - w
        ctx["canvas"].image(im, x0, ctx["y"] - h, w, h)
        ctx["y"] = ctx["y"] - h - 6.0
        if cap != null:
            self._paragraph(ctx, [[cap, null]], self._st("caption"), null)

    func _toc(ctx, b):
        st := self._st("toc")
        if b["title"] != null and b["title"] != "":
            self._paragraph(ctx, [[b["title"], null]], self._st("h1"), null)
        entries := ctx["toc_entries"]
        width := self._content_width()
        font := pw.resolve_font(self.font)
        for e in entries:
            if e["level"] > 3:
                continue
            indent := 14.0 * to_float(e["level"] - 1)
            lh := to_float(st["size"]) * 1.35
            self._ensure(ctx, lh)
            c := ctx["canvas"]
            c.set_font(font, st["size"])
            y := ctx["y"] - to_float(st["size"]) * 0.9
            title := e["title"]
            num := str(e["page"])
            c.text(self.margins["left"] + indent, y, title)
            c.text(self.margins["left"] + width, y, num, "right")
            tw := pw.text_width(title, font, st["size"])
            nw := pw.text_width(num, font, st["size"])
            dots_start := self.margins["left"] + indent + tw + 4.0
            dots_end := self.margins["left"] + width - nw - 4.0
            dw := pw.text_width(". ", font, st["size"])
            if dots_end > dots_start and dw > 0:
                n := to_int((dots_end - dots_start) / dw)
                c.set_fill("808080")
                c.text(dots_end, y, string.repeat(". ", n if n > 0 else 0), "right")
                c.set_fill("000000")
            c.link_page(self.margins["left"] + indent, y - 3.0, width - indent, lh, e["page"] - 1, e["top"])
            ctx["y"] = ctx["y"] - lh
        ctx["y"] = ctx["y"] - 10.0

    func _hf(builder, total):
        k := 1
        for c in builder.pages:
            for spec in [[self.header, true], [self.footer, false]]:
                hf := spec[0]
                if hf == null:
                    continue
                t := string.replace(string.replace(u.to_text(hf[0]), "{page}", str(k)), "{total}", str(total))
                t = string.replace(t, "{title}", u.to_text(u.get(self.info, "Title", "")))
                t = string.replace(t, "{date}", u.iso_date(u.date_parts(u.now_iso())))
                c.set_font(pw.resolve_font(self.font), 9)
                c.set_fill("595959")
                y := self.page_size[1] - self.margins["top"] / 2.0 if spec[1] else self.margins["bottom"] / 2.0 - 3.0
                al := hf[1]
                x := self.page_size[0] / 2.0
                if al == "left":
                    x = self.margins["left"]
                elif al == "right":
                    x = self.page_size[0] - self.margins["right"]
                c.text(x, y, t, al if al == "center" or al == "right" else "left")
                c.set_fill("000000")
            k = k + 1

    func _render(toc_entries):
        builder := pw.PdfBuilder()
        for k in keys(self.info):
            builder.info[k] = self.info[k]
        ctx := {"builder": builder, "canvas": null, "y": 0.0, "page": 0, "headings": [], "toc_entries": toc_entries}
        self._new_page(ctx)
        self._layout(ctx)
        return [builder, ctx]

    func build():
        has_toc := false
        for b in self.blocks:
            if b["type"] == "toc":
                has_toc = true
        r := self._render([])
        if has_toc:
            # deuxième passe : les numéros de page des titres sont connus
            r = self._render(r[1]["headings"])
            r = self._render(r[1]["headings"])
        builder := r[0]
        for h in r[1]["headings"]:
            builder.add_bookmark(h["title"], h["page"] - 1, h["level"], h["top"])
        self._hf(builder, len(builder.pages))
        self._pages = len(builder.pages)
        return builder

    func page_count():
        if self._pages == 0:
            self.build()
        return self._pages

    func to_bytes():
        return self.build().to_bytes()

    func save(path):
        io.write_bytes(path, self.to_bytes())
        return path

func _roman(n):
    vals := [[1000, "m"], [900, "cm"], [500, "d"], [400, "cd"], [100, "c"], [90, "xc"], [50, "l"], [40, "xl"], [10, "x"], [9, "ix"], [5, "v"], [4, "iv"], [1, "i"]]
    out := ""
    k := n
    for v in vals:
        while k >= v[0]:
            out = out + v[1]
            k = k - v[0]
    return out

# ---------------------------------------------------------------------------------------------- création

func new(size="A4", landscape=false, margins=56.7, font="Helvetica", font_size=11):
    return PdfDocument(size, landscape, margins, font, font_size)

func builder():
    return pw.PdfBuilder()

func from_text(text, out=null, font="Helvetica", size=11):
    d := PdfDocument("A4", false, 56.7, font, size)
    d.styles["normal"]["space_after"] = 0.0
    for line in string.split(string.replace(u.to_text(text), "\r\n", "\n"), "\n"):
        if line == "\x0c" or line == "\u000c":
            d.add_page_break()
        else:
            d.add_paragraph(line if line != "" else " ")
    data := d.to_bytes()
    if out == null:
        return data
    io.write_bytes(out, data)
    return out

func from_images(images, out=null, size=null):
    b := pw.PdfBuilder()
    for img in images:
        im := core.load_image(img)
        w := to_float(im.width) * 72.0 / to_float(im.dpi_x if im.dpi_x > 0 else 72)
        h := to_float(im.height) * 72.0 / to_float(im.dpi_y if im.dpi_y > 0 else 72)
        if size == null:
            c := b.new_page([w, h])
            c.image(im, 0, 0, w, h)
        else:
            c := b.new_page(size, w > h)
            mw := c.width - 56.0
            mh := c.height - 56.0
            s := mw / w if mw / w < mh / h else mh / h
            if s > 1.0:
                s = 1.0
            c.image(im, (c.width - w * s) / 2.0, (c.height - h * s) / 2.0, w * s, h * s)
    data := b.to_bytes()
    if out == null:
        return data
    io.write_bytes(out, data)
    return out

# ---------------------------------------------------------------------------------------------- lecture

func open(src, password=""):
    return pr.open(src, password) if not isinstance(src, pr.PdfFile) else src

func page_count(src, password=""):
    return open(src, password).page_count()

func info(src, password=""):
    return ppages.info(src, password)

func text(src, pages=null, layout=false, password=""):
    return ex.text(src, pages, layout, password)

func words(src, page=0, password=""):
    return ex.words(open(src, password).page(page))

func search(src, pattern, ignore_case=true, password=""):
    return ex.search(src, pattern, ignore_case, password)

func images(src, pages=null, password=""):
    return ex.images(src, pages, password)

func tables(src, pages=null, strategy="auto", password=""):
    return ptab.extract_tables(src, pages, strategy, password)

func links(src, password=""):
    return ex.links(src, password)

func fonts(src, password=""):
    return ex.fonts(src, password)

func outlines(src, password=""):
    return open(src, password).outlines()

func attachments(src, password=""):
    return open(src, password).attachments()

func metadata(src, password=""):
    return open(src, password).info()

func set_metadata(src, values, out, password=""):
    return pw.update_info(open(src, password), values, out)

# ---------------------------------------------------------------------------------------------- pages

func merge(sources, out=null, bookmarks=false):
    return pmerge.merge(sources, out, bookmarks)

func split(src, pattern, password=""):
    return psplit.split_pages(src, pattern, password)

func split_ranges(src, ranges, pattern, password=""):
    return psplit.split_ranges(src, ranges, pattern, password)

func extract(src, pages, out=null, password=""):
    return psplit.extract(src, pages, out, password)

func rotate(src, out, degrees, pages=null):
    return ppages.rotate(src, out, degrees, pages)

func crop(src, out, box, pages=null, margins=false):
    return ppages.crop(src, out, box, pages, margins)

func delete_pages(src, out, pages):
    return ppages.delete_pages(src, out, pages)

func reorder(src, out, order):
    return ppages.reorder(src, out, order)

func reverse(src, out):
    return ppages.reverse(src, out)

func insert_blank(src, out, after, size=null):
    return ppages.insert_blank(src, out, after, size)

func scale_to(src, out, size="A4", landscape=false):
    return ppages.scale_to(src, out, size, landscape)

func watermark(src, out, text, opacity=0.15, color="808080"):
    return ppages.watermark(src, out, text, opacity, color)

func stamp_text(src, out, text, x0, y0, size=12, color="000000", pages=null):
    return ppages.stamp_text(src, out, text, x0, y0, size, color, pages)

func number_pages(src, out, fmt="{page} / {total}", position="bottom-center"):
    return ppages.number_pages(src, out, fmt, position)

func overlay(src, out, overlay_src, overlay_page=0, pages=null, under=false):
    return ppages.overlay(src, out, overlay_src, overlay_page, pages, under)
