# ALEX - tests office : modèles neutres (document, tableur, présentation), conversions et gabarits.
# Lancer depuis la racine : ./alex run tests/office/test_office_convert.al
from core use len, type
use io
use os
use string
use filesystem as fs
use testing
from testing use assert_eq, assert_true, assert_raises
use office.document as document
use office.spreadsheet as sheet
use office.presentation as pres
use office.conversion as conv
use office.templates as tpl
use office.word as word
use office.excel as excel
use office.powerpoint as pp
use office.pdf as pdf

_tmp := fs.make_temp_dir("alex_office_conv_")

func p(name):
    return os.join(_tmp, name)

func has(s, sub):
    return string.contains(s, sub)

const MD := "# Rapport\n\nIntro **gras** et *italique*.\n\n## Section\n\n- un\n  - sous\n- deux\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n"

func t_document():
    d := document.from_markdown(MD)
    assert_eq(d.title, "Rapport")
    assert_eq(len(d.headings()), 2)
    assert_eq(d.tables(), [[["A", "B"], ["1", "2"]]])
    assert_eq(document.from_markdown(d.to_markdown()).to_markdown(), d.to_markdown())
    assert_eq(document.from_html(d.to_html()).to_markdown(), d.to_markdown())
    assert_eq(document.from_docx(d.to_docx()).to_markdown(), d.to_markdown())
    rs := document.parse_inline("a **b** [c](u)")
    assert_eq(len(rs), 4)
    assert_true(rs[1].bold)
    assert_eq(rs[3].link, "u")

testing.test("modèle de document", t_document)

func t_conversion_doc():
    io.write_file(p("in.md"), MD)
    for f in ["docx", "odt", "html", "txt", "pdf"]:
        conv.convert(p("in.md"), p("out." + f))
    ref := document.from_markdown(MD).to_markdown()
    assert_eq(conv.load(p("out.docx")).to_markdown(), ref)
    assert_eq(conv.load(p("out.odt")).to_markdown(), ref)
    assert_eq(conv.load(p("out.html")).to_markdown(), ref)
    from_pdf := conv.load(p("out.pdf"))
    assert_eq(from_pdf.headings()[0]["text"], "Rapport")
    assert_eq(from_pdf.tables(), [[["A", "B"], ["1", "2"]]])
    assert_true(conv.can_convert("docx", "pptx"))
    assert_raises(() => conv.convert(p("in.md"), p("out.xyz")), "ConversionError")

testing.test("conversions de documents", t_conversion_doc)

func t_spreadsheet():
    io.write_file(p("v.csv"), "produit;qte;prix\nPommes;3;1,5\nPoires;10;2,25\n")
    wb := sheet.open(p("v.csv"), null, {"decimal": ","})
    wb.sheet(0).set("D1", "total")
    wb.sheet(0).set("D2", "=B2*C2")
    for f in ["xlsx", "ods", "csv", "json", "html", "md", "txt", "pdf"]:
        sheet.save(wb, p("v." + f))
    assert_eq(sheet.read_rows(p("v.xlsx"))[1], ["Pommes", 3, 1.5, 4.5])
    assert_eq(sheet.read_rows(p("v.ods"))[1], ["Pommes", 3, 1.5, 4.5])
    assert_eq(sheet.read_records(p("v.json"))[1]["produit"], "Poires")
    assert_eq(sheet.read_rows(p("v.html"))[2][1], 10)
    assert_true(has(sheet.to_text(wb), "Poires"))
    conv.convert(p("v.xlsx"), p("v.docx"))
    assert_eq(word.open(p("v.docx")).tables()[0].data()[1][0], "Pommes")

testing.test("tableurs", t_spreadsheet)

func t_presentation():
    md := "# Bilan\nSous-titre\n\n## Points\n- un\n  - deux\n\n> Notes : à dire\n\n## Chiffres\n\n| R | CA |\n|---|---|\n| N | 1 |\n"
    prs := pres.from_markdown(md)
    assert_eq(prs.count(), 3)
    assert_eq(prs.slide(0).layout, "title")
    assert_eq(prs.slide(1).notes, "à dire")
    for f in ["pptx", "odp", "pdf", "html", "md", "txt"]:
        pres.save(prs, p("b." + f))
    assert_eq(pres.open(p("b.pptx")).count(), 3)
    assert_eq(pres.open(p("b.odp")).slide(1).title(), "Points")
    assert_eq(pdf.page_count(p("b.pdf")), 3)
    assert_true(has(io.read_file(p("b.html")), "<svg"))
    assert_eq(pres.open(p("b.md")).count(), 3)
    d := pres.to_document(prs)
    assert_eq(d.headings()[0]["text"], "Bilan")

testing.test("présentations", t_presentation)

func t_templates():
    data := {"client": {"nom": "Ada"}, "total": 1234.5, "lignes": [{"p": "A", "q": 1}, {"p": "B", "q": 2}], "vip": true}
    assert_eq(tpl.render("{{client.nom | upper}} {{total | number(1)}}", data), "ADA 1 234,5")
    assert_eq(tpl.render("{{#each lignes}}{{@index1}}{{p}}{{#unless @last}},{{/unless}}{{/each}}", data), "1A,2B")
    assert_eq(tpl.render("{{#if total > 1000 and vip}}oui{{else}}non{{/if}}", data), "oui")
    assert_eq(tpl.render("{{absent | default('x')}}", data), "x")
    assert_eq(tpl.render("<{{v}}>{{{v}}}", {"v": "<b>"}, {"mode": "html"}), "<&lt;b&gt;><b>")
    assert_raises(() => tpl.render("{{#if a}}", {}), "TemplateError")
    assert_raises(() => tpl.render("{{a}}", {}, {"strict": true}), "TemplateError")
    w := word.new()
    para := w.add_paragraph("Client : ")
    para.add_run("{{client", {"bold": true})
    para.add_run(".nom}}", {"bold": true})
    w.add_paragraph("{{#each lignes}}")
    w.add_bullet("{{p}} x{{q}}")
    w.add_paragraph("{{/each}}")
    w.add_table([["P", "Q"], ["{{#each lignes}}{{p}}", "{{q}}{{/each}}"]])
    w.save(p("m.docx"))
    tpl.fill(p("m.docx"), data, p("m_out.docx"))
    t := word.read_text(p("m_out.docx"))
    assert_true(has(t, "Client : Ada"))
    assert_true(has(t, "A x1") and has(t, "B x2"))
    assert_eq(word.open(p("m_out.docx")).tables()[0].data(), [["P", "Q"], ["A", "1"], ["B", "2"]])
    wb := excel.new()
    ws := wb.active_sheet()
    ws.append(["{{#each lignes}}{{p}}", "{{q}}{{/each}}"])
    ws.append(["Total", "=SUM(B1:B1)"])
    wb.save(p("m.xlsx"))
    tpl.fill(p("m.xlsx"), data, p("m_out.xlsx"))
    assert_eq(excel.read_rows(p("m_out.xlsx")), [["A", 1], ["B", 2], ["Total", 3]])
    paths := tpl.fill_many(p("m.docx"), [{"client": {"nom": "X"}, "lignes": []}, {"client": {"nom": "Y"}, "lignes": []}], os.join(_tmp, "out", "lettre-{{client.nom}}.docx"))
    assert_eq(len(paths), 2)
    assert_true(has(word.read_text(paths[1]), "Client : Y"))

testing.test("gabarits", t_templates)

failed := testing.run()
fs.remove_tree(_tmp)
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) office (conversions) en échec")
print("OFFICE CONVERSIONS: OK")
