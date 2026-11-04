# ALEX STANDARD LIBRARY — office.pdf_split
# Découpage de PDF : une page par fichier, par plages, toutes les N pages, par signets de premier niveau
# (chapitres), par taille maximale approximative ; extraction d'une sélection. Les signets de chaque morceau sont
# conservés, les métadonnées recopiées.
#
#   use office.pdf_split as split
#   split.split_pages("livre.pdf", "sortie/page-{n}.pdf")          # un fichier par page
#   split.split_ranges("livre.pdf", ["1-10", "11-20", "21-"], "sortie/partie-{n}.pdf")
#   split.split_every("livre.pdf", 5, "sortie/lot-{n}.pdf")
#   split.split_bookmarks("livre.pdf", "sortie/{title}.pdf")       # un fichier par chapitre
#   octets := split.extract("livre.pdf", "3,7-9")                  # sans fichier : octets du PDF
#
# Le modèle de nom accepte {n} (numéro du morceau, à partir de 1, complété par des zéros), {first} {last}
# (premières et dernières pages, à partir de 1), {title} (signet, nettoyé pour un nom de fichier), {stem}
# (nom du fichier source sans extension). Les dossiers sont créés au besoin.
#   split_pages(src, modele, password="") -> chemins
#   split_ranges(src, plages, modele, password="") -> chemins
#   split_every(src, n, modele, password="") -> chemins
#   split_bookmarks(src, modele, level=1, password="") -> chemins (pages avant le premier signet : morceau
#       « debut »)
#   split_size(src, max_octets, modele, password="") -> chemins
#   extract(src, pages, out=null, password="") -> chemin ou octets
#   chunks(src, plages) -> [octets] (en mémoire)
# Erreurs : PDFError, ValueError, IoError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use io
use os
use filesystem
use collections
use office.errors as errors
use office.utils as u
use office.pdf_reader as pr
use office.pdf_pages as pages

func _open(src, password):
    if isinstance(src, pr.PdfFile):
        return src
    return pr.open(src, password)

func _stem(src):
    if type(src) != "str":
        return "document"
    b := os.basename(src)
    k := -1
    i := 0
    for c in b:
        if str(c) == ".":
            k = i
        i = i + 1
    return _n.str_slice(b, 0, k) if k > 0 else b

func _safe(name):
    out := []
    for c in name:
        ch := str(c)
        if ch == "/" or ch == "\\" or ch == ":" or ch == "*" or ch == "?" or ch == "\"" or ch == "<" or ch == ">" or ch == "|" or string.ord(c) < 32:
            append(out, "_")
        else:
            append(out, ch)
    t := string.trim(string.join("", out))
    if t == "" or t == "." or t == "..":
        t = "sans-titre"
    return u.str_slice(t, 0, 120)

func _name(pattern, n, total, first, last, title, stem):
    width := len(str(total))
    s := string.replace(pattern, "{n}", u.pad_left(str(n), width, "0"))
    s = string.replace(s, "{first}", str(first + 1))
    s = string.replace(s, "{last}", str(last + 1))
    s = string.replace(s, "{title}", _safe(title))
    s = string.replace(s, "{stem}", stem)
    return s

func _write_part(doc, idx, path):
    comp := pages.PageComposer()
    mapping := {}
    for i in idx:
        mapping[i] = comp.add_page(doc, i)
    comp.copy_outlines(doc, mapping)
    data := comp.to_bytes(doc.info())
    if path == null:
        return data
    filesystem.ensure_parent(path)
    io.write_bytes(path, data)
    return path

func _split(doc, groups, pattern, titles, stem):
    out := []
    k := 0
    for g in groups:
        if len(g) == 0:
            continue
        t := titles[k] if titles != null and k < len(titles) else ""
        path := _name(pattern, k + 1, len(groups), g[0], g[len(g) - 1], t, stem)
        append(out, _write_part(doc, g, path))
        k = k + 1
    return out

func split_pages(src, pattern, password=""):
    doc := _open(src, password)
    groups := []
    for p in doc.pages():
        append(groups, [p.index])
    return _split(doc, groups, pattern, null, _stem(src))

func split_ranges(src, ranges, pattern, password=""):
    doc := _open(src, password)
    groups := []
    for r in ranges:
        append(groups, pages.parse_pages(r, doc.page_count()))
    return _split(doc, groups, pattern, null, _stem(src))

func split_every(src, n, pattern, password=""):
    if type(n) != "int" or n < 1:
        raise("ValueError", "split_every : nombre de pages par morceau >= 1 attendu")
    doc := _open(src, password)
    groups := []
    cur := []
    for p in doc.pages():
        append(cur, p.index)
        if len(cur) == n:
            append(groups, cur)
            cur = []
    if len(cur) > 0:
        append(groups, cur)
    return _split(doc, groups, pattern, null, _stem(src))

func split_bookmarks(src, pattern, level=1, password=""):
    doc := _open(src, password)
    marks := []
    for o in doc.outlines():
        if o["level"] == level and o["page"] >= 0:
            append(marks, o)
    marks = u.sort(marks, (o) => o["page"])
    total := doc.page_count()
    groups := []
    titles := []
    if len(marks) == 0:
        return _split(doc, [pages.parse_pages(null, total)], pattern, [_stem(src)], _stem(src))
    if marks[0]["page"] > 0:
        g := []
        k := 0
        while k < marks[0]["page"]:
            append(g, k)
            k = k + 1
        append(groups, g)
        append(titles, "debut")
    i := 0
    while i < len(marks):
        start := marks[i]["page"]
        end := marks[i + 1]["page"] - 1 if i + 1 < len(marks) else total - 1
        if end >= start:
            g := []
            k := start
            while k <= end:
                append(g, k)
                k = k + 1
            append(groups, g)
            append(titles, marks[i]["title"])
        i = i + 1
    return _split(doc, groups, pattern, titles, _stem(src))

# Morceaux dont la taille estimée (proportion des octets du fichier) reste sous max_bytes ; au moins une page.
func split_size(src, max_bytes, pattern, password=""):
    doc := _open(src, password)
    total := doc.page_count()
    if total == 0:
        return []
    groups := []
    cur := []
    for p in doc.pages():
        append(cur, p.index)
        if len(cur) > 1:
            est := len(_write_part(doc, cur, null))
            if est > max_bytes:
                collections.pop(cur)
                append(groups, cur)
                cur = [p.index]
    if len(cur) > 0:
        append(groups, cur)
    return _split(doc, groups, pattern, null, _stem(src))

func extract(src, sel, out=null, password=""):
    doc := _open(src, password)
    idx := pages.parse_pages(sel, doc.page_count())
    if len(idx) == 0:
        errors.fail(errors.PDF, "aucune page sélectionnée")
    return _write_part(doc, idx, out)

func chunks(src, ranges, password=""):
    doc := _open(src, password)
    out := []
    for r in ranges:
        append(out, _write_part(doc, pages.parse_pages(r, doc.page_count()), null))
    return out
