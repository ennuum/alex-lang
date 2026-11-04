# ALEX STANDARD LIBRARY — office.powerpoint
# Présentations PowerPoint (.pptx) : création, lecture, modification — façade de haut niveau au-dessus de
# pptx_reader, pptx_writer, pptx_slides, pptx_shapes, pptx_text, pptx_images, pptx_tables et pptx_charts.
#
#   use office.powerpoint as pp
#   prs := pp.new()                                         # 16:9 ; pp.new(false) : 4:3
#   prs.add_title_slide("Bilan 2026", "Direction financière")
#   prs.add_bullet_slide("Faits marquants", ["Croissance de 12 %", ["Export : +8 %"], "Nouvelle usine"],
#                        "Notes : insister sur l'export.")
#   prs.add_chart_slide("Ventes", "column", ["T1", "T2", "T3", "T4"], [{"name": "2026", "values": [12, 15, 9, 20]}])
#   prs.add_table_slide("Détail", [["Région", "CA"], ["Nord", 120], ["Sud", 95]])
#   prs.add_image_slide("Site", "photo.jpg")
#   s := prs.add_slide("blank")
#   s.add_shape("roundRect", "2cm", "2cm", "8cm", "3cm", "Étape 1", "4472C4")
#   prs.save("bilan.pptx")
#
#   p2 := pp.open("cours.pptx")
#   for s in p2.slides:
#       print(s.title())
#
# CRÉER / OUVRIR  new(widescreen=true)  open(chemin_ou_octets)  read_text(chemin, notes=true)  outline(chemin)
# Presentation    slides width height theme metadata
#   add_slide(layout="title_content") -> Slide   add_title_slide(titre, sous_titre=null)
#   add_section_slide(titre, texte=null)   add_bullet_slide(titre, items, notes=null)
#   add_two_column_slide(titre, gauche, droite)  (listes d'items)   add_image_slide(titre, image, legende=null)
#   add_table_slide(titre, lignes)   add_chart_slide(titre, kind, categories, series)
#   add_text_slide(titre, texte)   remove_slide(index)   move_slide(de, vers)   duplicate_slide(index)
#   slide(index)   count()   set_size(largeur, hauteur)   set_theme(colors=null, major_font=null, minor_font=null)
#   text(notes=true)  replace(ancien, nouveau)  save(chemin)  to_bytes()
# Classes : Slide (pptx_slides) Shape (pptx_shapes) TextFrame (pptx_text) Picture SlideTable SlideChart.
# Erreurs : PPTXError, FormatError, ValueError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.errors as errors
use office.utils as u
use office.metadata as metadata
use office.pptx_slides as sl
use office.pptx_shapes as ps
use office.pptx_text as pt
use office.pptx_images as pimg
use office.pptx_tables as ptb
use office.pptx_charts as pch
use office.pptx_reader as reader
use office.pptx_writer as writer

func Shape(kind="rect", x0=0, y0=0, cx=914400, cy=914400):
    return ps.Shape(kind, x0, y0, cx, cy)

func TextFrame(text=null):
    return pt.TextFrame(text)

class Presentation:
    func init(widescreen=true):
        self.slides = []
        self.width = 12192000 if widescreen else 9144000
        self.height = 6858000
        self.theme = {}
        self.metadata = metadata.new()

    func set_size(width, height):
        self.width = u.length(width)
        self.height = u.length(height)
        for s in self.slides:
            s.width = self.width
            s.height = self.height
        return self

    func set_theme(colors=null, major_font=null, minor_font=null):
        if colors != null:
            self.theme["colors"] = colors
        if major_font != null:
            self.theme["major_font"] = major_font
        if minor_font != null:
            self.theme["minor_font"] = minor_font
        return self

    func count():
        return len(self.slides)

    func slide(index):
        if index < 0 or index >= len(self.slides):
            raise("IndexError", "diapositive " + str(index) + " absente (" + str(len(self.slides)) + ")")
        return self.slides[index]

    func add_slide(layout="title_content"):
        s := sl.Slide(layout, self.width, self.height)
        append(self.slides, s)
        return s

    func add_title_slide(title, subtitle=null):
        s := self.add_slide("title")
        s.add_title(title)
        if subtitle != null:
            s.add_subtitle(subtitle)
        return s

    func add_section_slide(title, text=null):
        s := self.add_slide("section")
        s.add_title(title)
        if text != null:
            s.add_subtitle(text)
        return s

    func add_bullet_slide(title, items, notes=null):
        s := self.add_slide("title_content")
        s.add_title(title)
        s.add_bullets(items)
        s.notes = notes
        return s

    func add_text_slide(title, text):
        s := self.add_slide("title_content")
        s.add_title(title)
        body := s.add_bullets(string.split(u.to_text(text), "\n"))
        for p in body.text.paragraphs:
            p.bullet = false
        return s

    func add_two_column_slide(title, left, right):
        s := self.add_slide("two_content")
        s.add_title(title)
        s.add_bullets(left)
        s.add_bullets(right)
        return s

    func add_image_slide(title, image, caption=null):
        s := self.add_slide("title_only" if title != null else "blank")
        if title != null:
            s.add_title(title)
        b := s.boxes()["body"]
        if caption != null:
            sz := pimg.fit(image, b[2], b[3] - 457200)
            pic := pimg.Picture(image, b[0] + (b[2] - sz[0]) // 2, b[1], sz[0], sz[1])
            s.add(pic)
            cap := s.add_text(caption, b[0], b[1] + sz[1] + 91440, b[2], 400000, {"italic": true, "size": 14, "color": "595959"})
            cap.text.paragraphs[0].align = "center"
        elif title != null:
            sz := pimg.fit(image, b[2], b[3])
            s.add(pimg.Picture(image, b[0] + (b[2] - sz[0]) // 2, b[1] + (b[3] - sz[1]) // 2, sz[0], sz[1]))
        else:
            s.add_image(image)
        return s

    func add_table_slide(title, rows):
        s := self.add_slide("title_only")
        s.add_title(title)
        s.add_table(rows)
        return s

    func add_chart_slide(title, kind, categories, series):
        s := self.add_slide("title_only")
        s.add_title(title)
        s.add_chart(kind, categories, series)
        return s

    func remove_slide(index):
        self.slide(index)
        collections.pop(self.slides, index)

    func move_slide(src, dst):
        s := self.slide(src)
        collections.pop(self.slides, src)
        collections.insert(self.slides, dst, s)

    func duplicate_slide(index):
        src := self.slide(index)
        cp := sl.Slide(src.layout, self.width, self.height)
        for sh in src.shapes:
            append(cp.shapes, sh)
        cp.background = src.background
        cp.notes = src.notes
        collections.insert(self.slides, index + 1, cp)
        return cp

    func text(notes=true):
        blocks := []
        k := 1
        for s in self.slides:
            lines := ["--- Diapositive " + str(k) + " ---"]
            for t in s.texts():
                append(lines, t)
            if notes and s.notes != null:
                append(lines, "[Notes] " + s.notes)
            append(blocks, string.join("\n", lines))
            k = k + 1
        return string.join("\n\n", blocks)

    func replace(old, new_text):
        n := 0
        for s in self.slides:
            n = n + s.replace(old, new_text)
            if s.notes != null and string.contains(s.notes, old):
                n = n + string.count(s.notes, old)
                s.notes = string.replace(s.notes, old, new_text)
        return n

    func save(path):
        return writer.save(self, path)

    func to_bytes():
        return writer.to_bytes(self)

func new(widescreen=true):
    return Presentation(widescreen)

func open(src):
    parts := reader.read(src)
    p := Presentation(true)
    p.width = parts["width"]
    p.height = parts["height"]
    p.slides = parts["slides"]
    p.theme = parts["theme"]
    p.metadata = parts["metadata"]
    return p

func read_text(src, notes=true):
    return reader.read_text(src, notes)

func outline(src):
    return reader.outline(src)
