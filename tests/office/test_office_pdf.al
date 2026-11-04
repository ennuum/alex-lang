# ALEX - tests office : PDF (création mise en page, lecture, extraction, tableaux, pages, fusion, découpage).
# Lancer depuis la racine : ./alex run tests/office/test_office_pdf.al
from core use len, type
use os
use filesystem as fs
use string
use testing
from testing use assert_eq, assert_true, assert_raises
use office.pdf as pdf
use office.pdf_writer as pw

_tmp := fs.make_temp_dir("alex_office_pdf_")

func p(name):
    return os.join(_tmp, name)

func has(s, sub):
    return string.contains(s, sub)

func make(path, pages):
    d := pdf.new()
    d.info["Title"] = "Essai"
    k := 1
    while k <= pages:
        if k > 1:
            d.add_page_break()
        d.add_heading("Chapitre " + str(k), 1)
        d.add_paragraph("Texte de la page " + str(k) + " avec des accents : éàç €.")
        k = k + 1
    d.add_table([["Produit", "Qté"], ["Pommes", "3"], ["Poires", "10"]])
    d.set_footer("Page {page} / {total}")
    d.save(path)
    return path

func t_create_read():
    make(p("a.pdf"), 3)
    assert_eq(pdf.page_count(p("a.pdf")), 3)
    t := pdf.text(p("a.pdf"))
    assert_true(has(t, "Chapitre 2"))
    assert_true(has(t, "éàç €"))
    assert_eq(pdf.metadata(p("a.pdf"))["Title"], "Essai")
    assert_eq(len(pdf.outlines(p("a.pdf"))), 3)
    tabs := pdf.tables(p("a.pdf"), [2])
    assert_true(len(tabs) >= 1)
    assert_eq(tabs[0]["rows"][1], ["Pommes", "3"])
    assert_true(len(pdf.search(p("a.pdf"), "poires")) >= 1)

testing.test("création et lecture", t_create_read)

func t_pages():
    make(p("b.pdf"), 4)
    pdf.rotate(p("b.pdf"), p("r.pdf"), 90, [0])
    assert_eq(pdf.open(p("r.pdf")).page(0).rotation(), 90)
    pdf.delete_pages(p("b.pdf"), p("d.pdf"), [1, 2])
    assert_eq(pdf.page_count(p("d.pdf")), 2)
    pdf.merge([p("b.pdf"), p("d.pdf")], p("m.pdf"), true)
    assert_eq(pdf.page_count(p("m.pdf")), 6)
    parts := pdf.split(p("b.pdf"), os.join(_tmp, "s", "p-{n}.pdf"))
    assert_eq(len(parts), 4)
    assert_eq(pdf.page_count(pdf.extract(p("b.pdf"), "2-3")), 2)
    pdf.watermark(p("b.pdf"), p("w.pdf"), "BROUILLON")
    assert_true(has(pdf.text(p("w.pdf"), [0]), "BROUILLON"))
    pdf.set_metadata(p("b.pdf"), {"Title": "Nouveau"}, p("t.pdf"))
    assert_eq(pdf.metadata(p("t.pdf"))["Title"], "Nouveau")

testing.test("pages, fusion, découpage", t_pages)

func t_canvas():
    b := pw.PdfBuilder()
    c := b.new_page("A5")
    c.set_font("Helvetica-Bold", 14)
    c.text(40, 500, "Bonjour")
    c.set_fill("4472C4")
    c.rect(40, 400, 100, 50, true, false)
    c.link(40, 400, 100, 50, "https://example.org")
    b.save(p("c.pdf"))
    assert_true(has(pdf.text(p("c.pdf")), "Bonjour"))
    assert_eq(pdf.links(p("c.pdf"))[0]["uri"], "https://example.org")
    assert_raises(() => pdf.open([1, 2, 3]), "PDFError")

testing.test("dessin libre", t_canvas)

failed := testing.run()
fs.remove_tree(_tmp)
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) office (PDF) en échec")
print("OFFICE PDF: OK")
