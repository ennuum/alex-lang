# ALEX - tests office : Word (.docx), Excel (.xlsx, formules), PowerPoint (.pptx).
# Lancer depuis la racine : ./alex run tests/office/test_office_ooxml.al
from core use len, type
use os
use filesystem as fs
use testing
from testing use assert_eq, assert_true, assert_raises, assert_near
use office.word as word
use office.excel as excel
use office.xlsx_formulas as xf
use office.powerpoint as pp

_tmp := fs.make_temp_dir("alex_office_ooxml_")

func p(name):
    return os.join(_tmp, name)

func t_word():
    d := word.new()
    d.add_heading("Rapport", 1)
    para := d.add_paragraph("Texte ")
    para.add_run("gras", {"bold": true})
    d.add_bullet("point")
    d.add_numbered("étape")
    d.add_table([["A", "B"], [1, 2]])
    d.set_footer("Page {PAGE} / {NUMPAGES}", "center")
    d.save(p("r.docx"))
    d2 := word.open(p("r.docx"))
    assert_eq(d2.headings(), [{"level": 1, "text": "Rapport"}])
    assert_eq(d2.tables()[0].data(), [["A", "B"], ["1", "2"]])
    assert_true(d2.paragraphs()[1].runs[1].bold == true)
    assert_eq(d2.replace("Texte", "Contenu"), 1)
    t := word.read_text(p("r.docx"))
    assert_true(len(t) > 10)

testing.test("word", t_word)

func t_formulas():
    assert_eq(xf.evaluate("ROUND(3.14159; 2)"), 3.14)
    assert_eq(xf.evaluate("SOMME(1;2;3)"), 6)
    assert_eq(xf.evaluate("IF(2>1,\"oui\",\"non\")"), "oui")
    assert_eq(xf.shift_formula("A1+$B$1+C$2", 2, 1), "B3+$B$1+D$2")
    assert_eq(xf.evaluate("1/0").code, "#DIV/0!")
    assert_raises(() => xf.parse("SUM(1,"), "FormulaError")

testing.test("formules", t_formulas)

func t_excel():
    wb := excel.new("Ventes")
    ws := wb.active_sheet()
    ws.append(["Produit", "Qté", "Prix", "Total"], {"bold": true})
    ws.append(["Pommes", 3, 1.5, "=B2*C2"])
    ws.append(["Poires", 10, 2.25, "=B3*C3"])
    ws.set("D4", "=SUM(D2:D3)", {"number_format": "#,##0.00"})
    ws.set("E2", {"year": 2026, "month": 3, "day": 15})
    ws.merge("A6:C6")
    ws.freeze("A2")
    wb.calculate()
    assert_eq(ws.get("D4"), 27)
    wb.save(p("v.xlsx"))
    wb2 := excel.open(p("v.xlsx"))
    s := wb2.sheet("Ventes")
    assert_eq(s.get("D4"), 27)
    assert_eq(s.cell("D4").formula, "SUM(D2:D3)")
    assert_eq(s.get("E2")["month"], 3)
    assert_eq(s.merged, ["A6:C6"])
    assert_eq(s.freeze_cell, "A2")
    assert_eq(excel.read_rows(p("v.xlsx"))[1][0], "Pommes")

testing.test("excel", t_excel)

func t_pptx():
    prs := pp.new()
    prs.add_title_slide("Bilan", "Sous-titre")
    prs.add_bullet_slide("Points", ["un", ["deux"], "trois"], "notes")
    prs.add_table_slide("Tableau", [["A", "B"], [1, 2]])
    prs.add_chart_slide("Graphique", "column", ["T1", "T2"], [{"name": "S", "values": [1, 2]}])
    prs.save(p("b.pptx"))
    p2 := pp.open(p("b.pptx"))
    assert_eq(p2.count(), 4)
    assert_eq(p2.slide(0).title(), "Bilan")
    assert_eq(p2.slide(1).notes, "notes")
    assert_eq(len(p2.slide(3).charts()), 1)
    assert_true(len(pp.read_text(p("b.pptx"))) > 20)

testing.test("powerpoint", t_pptx)

failed := testing.run()
fs.remove_tree(_tmp)
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) office (OOXML) en échec")
print("OFFICE OOXML: OK")
