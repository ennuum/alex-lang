# ALEX STANDARD LIBRARY — office.pdf_merge
# Fusion de PDF : concaténation de fichiers entiers ou de plages de pages, signets conservés (et regroupés sous
# un signet par fichier si demandé), liens internes préservés, documents chiffrés acceptés (mot de passe par
# fichier), sortie déchiffrée et compacte. Aussi : entrelacement (recto / verso numérisés séparément).
#
#   use office.pdf_merge as merge
#   merge.merge(["a.pdf", "b.pdf", "c.pdf"], "tout.pdf")
#   merge.merge([{"src": "a.pdf", "pages": "1-3"}, {"src": "b.pdf", "pages": [0, 4]}], "extrait.pdf")
#   merge.merge(["rapport.pdf", "annexes.pdf"], "dossier.pdf", true)     # un signet par fichier
#   merge.interleave("recto.pdf", "verso.pdf", "scan.pdf", true)          # verso numérisé à l'envers
#
# merge(sources, out=null, bookmarks=false, keep_outlines=true, info=null) -> chemin ou octets
#   sources : liste de chemins, octets, PdfFile, ou dicts {"src", "pages" (voir pdf_pages.parse_pages),
#   "password", "title" (titre du signet du fichier)}
# append_pdf(base, autre, out=null)   interleave(a, b, out=null, reverse_b=false)
# Merger : add(src, pages=null, password="", title=null) -> indice de la première page ajoutée  add_blank(size="A4")
#   page_count()  to_bytes(info=null)  save(chemin, info=null)
# Erreurs : PDFError, ValueError, IoError.

from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use io
use os
use office.errors as errors
use office.utils as u
use office.core as core
use office.pdf_reader as pr
use office.pdf_pages as pages

class Merger:
    func init(bookmarks=false, keep_outlines=true):
        self.comp = pages.PageComposer()
        self.bookmarks = bookmarks
        self.keep_outlines = keep_outlines
        self.first_info = null
        self.count = 0

    func add(src, sel=null, password="", title=null):
        doc := src if isinstance(src, pr.PdfFile) else pr.open(src, password)
        if self.first_info == null:
            self.first_info = doc.info()
        idx := pages.parse_pages(sel, doc.page_count())
        start := len(self.comp.pages)
        mapping := {}
        for i in idx:
            j := self.comp.add_page(doc, i)
            if not contains_key(mapping, i):
                mapping[i] = j
        if self.bookmarks:
            t := title
            if t == null:
                t = _stem(src) if type(src) == "str" else "Document " + str(self.count + 1)
                info_title := u.get(doc.info(), "Title", "")
                if title == null and type(src) != "str" and info_title != "":
                    t = info_title
            self.comp.add_bookmark(t, start, 1)
            if self.keep_outlines:
                self.comp.copy_outlines(doc, mapping, 1)
        elif self.keep_outlines:
            self.comp.copy_outlines(doc, mapping, 0)
        self.count = self.count + 1
        return start

    func add_blank(size="A4"):
        wh := core.page_size(size)
        return self.comp.add_blank(wh[0], wh[1])

    func page_count():
        return len(self.comp.pages)

    func to_bytes(info=null):
        inf := info
        if inf == null:
            inf = self.first_info
        return self.comp.to_bytes(inf)

    func save(path, info=null):
        io.write_bytes(path, self.to_bytes(info))
        return path

func _stem(path):
    b := os.basename(path)
    k := -1
    i := 0
    for c in b:
        if str(c) == ".":
            k = i
        i = i + 1
    return u.str_slice(b, 0, k) if k > 0 else b

func merge(sources, out=null, bookmarks=false, keep_outlines=true, info=null):
    if type(sources) != "list" or len(sources) == 0:
        raise("ValueError", "merge : liste de sources non vide attendue")
    m := Merger(bookmarks, keep_outlines)
    for s in sources:
        if type(s) == "dict":
            m.add(s["src"], u.get(s, "pages", null), u.get(s, "password", ""), u.get(s, "title", null))
        else:
            m.add(s)
    data := m.to_bytes(info)
    if out == null:
        return data
    io.write_bytes(out, data)
    return out

func append_pdf(base, other, out=null):
    return merge([base, other], out)

# Entrelace les pages de a et b (a1, b1, a2, b2...). reverse_b : b est pris à l'envers (verso numérisé en sens
# inverse). Les pages en trop de l'un ou l'autre sont ajoutées à la fin.
func interleave(a, b, out=null, reverse_b=false):
    da := a if isinstance(a, pr.PdfFile) else pr.open(a)
    db := b if isinstance(b, pr.PdfFile) else pr.open(b)
    comp := pages.PageComposer()
    na := da.page_count()
    nb := db.page_count()
    k := 0
    while k < na or k < nb:
        if k < na:
            comp.add_page(da, k)
        if k < nb:
            comp.add_page(db, nb - 1 - k if reverse_b else k)
        k = k + 1
    data := comp.to_bytes(da.info())
    if out == null:
        return data
    io.write_bytes(out, data)
    return out
