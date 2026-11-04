# ALEX STANDARD LIBRARY — office.word
# Documents Word (.docx) : création, lecture, modification — façade de haut niveau au-dessus de docx_reader,
# docx_writer, docx_paragraphs, docx_tables, docx_styles et docx_images.
#
#   use office.word as word
#   doc := word.new()
#   doc.add_heading("Rapport annuel", 0)                       # niveau 0 : style Titre
#   doc.add_paragraph("Introduction en ").add_run("gras", {"bold": true})
#   doc.add_bullet("premier point")
#   doc.add_numbered("étape 1")
#   doc.add_table([["Produit", "Qté"], ["Pommes", 3]], header=true)
#   doc.add_image("graphique.png", width="12cm", caption="Figure 1 — Ventes")
#   doc.set_footer("Page {PAGE} sur {NUMPAGES}", "center")
#   doc.save("rapport.docx")
#
#   d := word.open("existant.docx")
#   print(d.text())
#   d.replace("{{client}}", "ACME")
#   d.save("copie.docx")
#
# OUVRIR / CRÉER  new(font="Calibri", size=11, language="fr-FR")  open(chemin_ou_octets)  read_text(chemin)
#                 from_text(texte) (un paragraphe par ligne, lignes vides ignorées)
# AJOUTER         add_heading(texte, level=1)  add_title(t)  add_subtitle(t)
#                 add_paragraph(texte="", style=null, align=null, bold=null, italic=null, size=null, color=null)
#                 add_bullet(texte, level=0)  add_numbered(texte, level=0, restart=false)  add_list(items, ordered=false)
#                 (items : textes et sous-listes imbriquées)  add_table(lignes, header=true, style="TableGrid",
#                 widths=null) -> docx_tables.Table  add_block(Paragraph | Table)  add_image(image, width=null,
#                 height=null, caption=null, align="center")  add_page_break()  add_toc(title="Table des matières",
#                 levels="1-3")  add_quote(texte)  add_code(texte)  add_horizontal_rule()  add_link(texte, url)
# PAGE            set_page(size="A4", landscape=false, margins=null)  (margins : longueur ou dict top/bottom/left/right)
#                 set_header(contenu, align=null)  set_footer(contenu, align=null)  (contenu : texte — {PAGE},
#                 {NUMPAGES}, {DATE} deviennent des champs — ou liste de blocs)  page_numbers(format="{PAGE}")
# LIRE            paragraphs(include_tables=false)  tables()  headings() -> [{"level", "text"}]  images()
#                 text()  word_count()  find(texte) -> paragraphes  outline() (sommaire en texte)
# MODIFIER        replace(ancien, nouveau) -> nombre (corps, tableaux, en-têtes, pieds)  remove(bloc)
#                 insert(index, bloc)  clear()
# ENREGISTRER     save(chemin)  to_bytes()
# Champs publics  body styles section header footer first_header first_footer metadata footnotes comments
#                 update_fields
# Classes réexportées : Paragraph Run Table Cell Row Style InlineImage (voir les modules docx_*).
# Erreurs : DOCXError, FormatError, XMLError, ArchiveError, ValueError, TypeError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.core as core
use office.metadata as metadata
use office.docx_styles as styles
use office.docx_paragraphs as dp
use office.docx_tables as dt
use office.docx_images as dimg
use office.docx_reader as reader
use office.docx_writer as writer

func Paragraph(text="", style=null):
    return dp.Paragraph(text, style)

func Run(text=""):
    return dp.Run(text)

func Table(rows=0, cols=0, style="TableGrid"):
    return dt.Table(rows, cols, style)

func Style(ident, name=null, kind="paragraph"):
    return styles.Style(ident, name, kind)

func InlineImage(image, width=null, height=null, description=""):
    return dimg.InlineImage(image, width, height, description)

func _default_section():
    return {"page_width": 595.3, "page_height": 841.9, "orientation": "portrait", "margin_top": 70.85, "margin_bottom": 70.85, "margin_left": 70.85, "margin_right": 70.85, "margin_header": 35.4, "margin_footer": 35.4, "columns": 1, "title_page": false}

# Texte avec {PAGE} {NUMPAGES} {DATE} -> paragraphe (champs Word).
func _field_paragraph(text, align, style):
    p := dp.Paragraph("", style)
    p.align = align
    rest := text
    while true:
        best := -1
        token := ""
        for t in ["{PAGE}", "{NUMPAGES}", "{DATE}", "{SECTIONPAGES}"]:
            k := string.find(rest, t)
            if k >= 0 and (best < 0 or k < best):
                best = k
                token = t
        if best < 0:
            if rest != "":
                p.add_run(rest)
            break
        if best > 0:
            p.add_run(_n.str_slice(rest, 0, best))
        name := _n.str_slice(token, 1, len(token) - 1)
        if name == "DATE":
            p.add_field("DATE \\@ \"dd/MM/yyyy\"", "")
        else:
            p.add_field(name, "1")
        rest = _n.str_slice(rest, best + len(token), null)
    return p

class WordDocument:
    func init(font="Calibri", size=11, language="fr-FR"):
        self.body = []
        self.styles = styles.default_styles(font, size, language)
        self.section = _default_section()
        self.header = []
        self.footer = []
        self.first_header = []
        self.first_footer = []
        self.metadata = metadata.new()
        self.footnotes = []
        self.comments = []
        self.update_fields = false
        self._list_counter = 0
        self._last_numbered = null

    # ---------------------------------------------------------- ajout
    func add_block(b):
        append(self.body, b)
        if not (isinstance(b, dp.Paragraph) and b.list != null and b.list["kind"] == "number"):
            self._last_numbered = null
        return b

    func add_heading(text, level=1):
        if type(level) != "int" or level < 0 or level > 9:
            raise("ValueError", "add_heading : niveau 0..9 attendu")
        style := "Title" if level == 0 else styles.heading_id(level)
        return self.add_block(dp.Paragraph(text, style))

    func add_title(text):
        return self.add_heading(text, 0)

    func add_subtitle(text):
        return self.add_block(dp.Paragraph(text, "Subtitle"))

    # add_paragraph(texte, style, align, bold, italic, size, color) ou add_paragraph(texte, options) avec options un
    # dict mêlant propriétés de paragraphe (style, align, space_before, indent_left...) et de caractère (bold, color...).
    func add_paragraph(text="", style=null, align=null, bold=null, italic=null, size=null, color=null):
        if type(style) == "dict":
            opts := style
            p := dp.Paragraph("", u.get(opts, "style", null))
            p.set_props(opts)
            if text != null and text != "":
                p.add_run(text, opts)
            return self.add_block(p)
        p := dp.Paragraph("", style)
        if text != null and text != "":
            p.add_run(text, bold, italic, null, null, size, color)
        p.align = align
        return self.add_block(p)

    func add_link(text, url):
        p := dp.Paragraph()
        p.add_link(text, url)
        return self.add_block(p)

    func add_bullet(text, level=0):
        p := dp.Paragraph(text)
        p.list = {"kind": "bullet", "level": level, "list_id": 0}
        return self.add_block(p)

    func add_numbered(text, level=0, restart=false):
        if restart or self._last_numbered == null:
            self._list_counter = self._list_counter + 1
        p := dp.Paragraph(text)
        p.list = {"kind": "number", "level": level, "list_id": self._list_counter}
        append(self.body, p)
        self._last_numbered = self._list_counter
        return p

    func _add_items(items, ordered, level, first):
        for it in items:
            if type(it) == "list" or type(it) == "tuple":
                self._add_items(it, ordered, level + 1, false)
            elif ordered:
                self.add_numbered(u.to_text(it), level, first and level == 0)
                first = false
            else:
                self.add_bullet(u.to_text(it), level)

    func add_list(items, ordered=false):
        self._add_items(items, ordered, 0, true)

    func add_table(rows, header=true, style="TableGrid", widths=null, header_shading=null):
        t := dt.from_rows(rows, header, style, header, header_shading)
        if widths != null:
            t.widths = widths
        self.add_block(t)
        return t

    func add_image(image, width=null, height=null, caption=null, align="center", description=""):
        p := dp.Paragraph()
        p.add_image(image, width, height, description)
        p.align = align
        self.add_block(p)
        if caption != null:
            c := dp.Paragraph(caption, "Caption")
            c.align = align
            self.add_block(c)
        return p

    func add_page_break():
        return self.add_block(dp.page_break())

    # Sommaire (champ TOC) : Word le calcule à l'ouverture (update_fields), LibreOffice via Outils > Mettre à jour.
    func add_toc(title="Table des matières", levels="1-3"):
        if title != null and title != "":
            self.add_block(dp.Paragraph(title, "TOCHeading"))
        p := dp.Paragraph()
        p.add_field("TOC \\o \"" + levels + "\" \\h \\z \\u", "Cliquez avec le bouton droit et choisissez « Mettre à jour les champs » pour afficher le sommaire.")
        self.update_fields = true
        return self.add_block(p)

    func add_quote(text):
        return self.add_block(dp.Paragraph(text, "Quote"))

    func add_code(text):
        last := null
        for line in string.split(string.replace(u.to_text(text), "\r\n", "\n"), "\n"):
            p := dp.Paragraph("", "Code")
            if line != "":
                p.add_run(line)
            last = self.add_block(p)
        return last

    func add_horizontal_rule():
        p := dp.Paragraph()
        p.border_bottom = true
        return self.add_block(p)

    # ---------------------------------------------------------- page
    func set_page(size="A4", landscape=false, margins=null):
        wh := core.page_size(size, landscape)
        self.section["page_width"] = wh[0]
        self.section["page_height"] = wh[1]
        self.section["orientation"] = "landscape" if landscape else "portrait"
        if margins != null:
            if type(margins) == "dict":
                for side in ["top", "bottom", "left", "right", "header", "footer"]:
                    if contains_key(margins, side):
                        self.section["margin_" + side] = u.emu_to_pt(u.length(margins[side], "pt"))
            else:
                m := u.emu_to_pt(u.length(margins, "pt"))
                for side in ["top", "bottom", "left", "right"]:
                    self.section["margin_" + side] = m
        return self

    func _hf(content, align, style):
        if type(content) == "list":
            return content
        return [_field_paragraph(u.to_text(content), align, style)]

    func set_header(content, align=null):
        self.header = self._hf(content, align, "Header")
        return self

    func set_footer(content, align=null):
        self.footer = self._hf(content, align, "Footer")
        return self

    func page_numbers(fmt="{PAGE}", align="center"):
        return self.set_footer(fmt, align)

    # ---------------------------------------------------------- lecture
    func paragraphs(include_tables=false):
        out := []
        for b in self.body:
            if isinstance(b, dp.Paragraph):
                append(out, b)
            elif include_tables:
                _table_paragraphs(b, out)
        return out

    func tables():
        out := []
        for b in self.body:
            if isinstance(b, dt.Table):
                append(out, b)
        return out

    func headings():
        out := []
        for p in self.paragraphs():
            lvl := p.heading_level()
            if lvl != null:
                append(out, {"level": lvl, "text": p.text()})
        return out

    func outline():
        lines := []
        for h in self.headings():
            if h["level"] > 0:
                append(lines, string.repeat("  ", h["level"] - 1) + h["text"])
        return string.join("\n", lines)

    func images():
        out := []
        for p in self.paragraphs(true):
            for r in p.runs:
                if r.kind == "image" and r.image != null:
                    append(out, r.image)
        return out

    func text():
        out := []
        for b in self.body:
            append(out, b.text())
        return string.join("\n", out)

    func word_count():
        n := 0
        for w in string.split(string.replace(string.replace(self.text(), "\n", " "), "\t", " "), " "):
            if w != "":
                n = n + 1
        return n

    func find(text):
        out := []
        for p in self.paragraphs(true):
            if string.contains(p.text(), text):
                append(out, p)
        return out

    # ---------------------------------------------------------- modification
    func replace(old, new_text):
        n := 0
        all := []
        for b in [self.body, self.header, self.footer, self.first_header, self.first_footer]:
            for blk in b:
                if isinstance(blk, dp.Paragraph):
                    append(all, blk)
                else:
                    _table_paragraphs(blk, all)
        for p in all:
            k := p.replace(old, new_text)
            if k == 0 and string.contains(p.text(), old):
                # texte réparti sur plusieurs runs : fusion des runs de même format puis nouvel essai
                p.merge_runs()
                k = p.replace(old, new_text)
            n = n + k
        return n

    func remove(block):
        out := []
        found := false
        for b in self.body:
            if not found and _n.same(b, block):
                found = true
            else:
                append(out, b)
        self.body = out
        return found

    func insert(index, block):
        collections.insert(self.body, index, block)
        return block

    func clear():
        self.body = []
        return self

    func save(path):
        return writer.save(self, path)

    func to_bytes():
        return writer.to_bytes(self)

func _table_paragraphs(t, out):
    for row in t.rows:
        for c in row.cells:
            if c.merged:
                continue
            for p in c.paragraphs:
                if isinstance(p, dp.Paragraph):
                    append(out, p)
                else:
                    _table_paragraphs(p, out)

func new(font="Calibri", size=11, language="fr-FR"):
    return WordDocument(font, size, language)

func open(src):
    parts := reader.read(src)
    d := WordDocument()
    d.body = parts["body"]
    d.styles = parts["styles"]
    d.section = parts["section"]
    d.header = parts["header"]
    d.footer = parts["footer"]
    d.first_header = parts["first_header"]
    d.first_footer = parts["first_footer"]
    d.metadata = parts["metadata"]
    d.footnotes = parts["footnotes"]
    d.comments = parts["comments"]
    # les listes relues gardent leur identité (une liste par numId d'origine)
    for p in d.paragraphs(true):
        if p.list != null:
            p.num_id = null
    return d

func read_text(src):
    return reader.read_text(src)

func from_text(text):
    d := WordDocument()
    for line in u.lines(text):
        if string.trim(line) != "":
            d.add_paragraph(line)
    return d
