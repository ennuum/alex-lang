# ALEX - tests office : OpenDocument (.odt, .ods, .odp) en lecture et écriture.
# Lancer depuis la racine : ./alex run tests/office/test_office_odf.al
from core use len, type
use os
use filesystem as fs
use testing
from testing use assert_eq, assert_true, assert_raises
use office.odf as odf
use office.odt as odt
use office.ods as ods
use office.odp as odp
use office.document as document
use office.excel as excel
use office.powerpoint as pp
use office.archive as zip

_tmp := fs.make_temp_dir("alex_office_odf_")

func p(name):
    return os.join(_tmp, name)

func t_package():
    d := document.from_markdown("# T\n\nx")
    odt.save(d, p("a.odt"))
    a := zip.open(p("a.odt"))
    assert_eq(a.names()[0], "mimetype")
    assert_eq(a.info("mimetype").method, 0)
    assert_true(a.contains("META-INF/manifest.xml"))
    assert_eq(odf.kind(p("a.odt")), "odt")
    assert_eq(odf.to_pt("2.54cm"), 72.0)
    assert_eq(len(odf.text_nodes("a  b")), 3)

testing.test("paquet ODF", t_package)

func t_odt():
    md := "# Titre\n\nUn **gras**, *italique*, `code` et [lien](https://example.org).\n\n## Liste\n\n- a\n  - b\n- c\n\n1. un\n2. deux\n\n| A | B |\n| --- | --- |\n| 1 | 2 |\n\n> citation\n\n```\nx := 1\n    y\n```\n\n---\n\nFin.\n"
    d := document.from_markdown(md)
    odt.save(d, p("t.odt"))
    d2 := odt.read(p("t.odt"))
    assert_eq(d2.to_markdown(), d.to_markdown())
    assert_eq(d2.title, "Titre")
    assert_true(len(odt.read_text(p("t.odt"))) > 20)

testing.test("odt aller-retour", t_odt)

func t_formulas():
    assert_eq(ods.to_openformula("SUM(A1:B2)+Feuil2!C3"), "of:=SUM([.A1:.B2])+[$Feuil2.C3]")
    assert_eq(ods.from_openformula("of:=IF([.A1]>0;\"a;b\";[$'Mon onglet'.$B$2])"), "IF(A1>0,\"a;b\",'Mon onglet'!$B$2)")
    assert_eq(ods.excel_format(ods.data_style_xml("#,##0.00 €", "N1")), "#,##0.00 €")
    assert_eq(ods.excel_format(ods.data_style_xml("dd/mm/yyyy", "N2")), "dd/mm/yyyy")
    assert_eq(ods.excel_format(ods.data_style_xml("0.0%", "N3")), "0.0%")

testing.test("formules et formats ODS", t_formulas)

func t_ods():
    wb := excel.new("Ventes")
    ws := wb.active_sheet()
    ws.append(["Produit", "Qté", "Prix", "Total"], {"bold": true, "fill": "D9E2F3"})
    ws.append(["Pommes", 3, 1.5, "=B2*C2"])
    ws.set("E2", {"year": 2026, "month": 3, "day": 15})
    ws.set("F2", true)
    ws.set("A4", "a  b")
    ws.merge("A6:B6")
    ws.freeze("A2")
    ws.add_comment("B2", "note")
    wb.define_name("Total", "Ventes!$D$2")
    ws2 := wb.add_sheet("Autre")
    ws2.set("A1", "=Ventes!D2*2")
    ods.save(wb, p("v.ods"))
    wb2 := ods.read(p("v.ods"))
    assert_eq(len(wb2.sheets), 2)
    s := wb2.sheet("Ventes")
    assert_eq(s.get("D2"), 4.5)
    assert_eq(s.cell("D2").formula, "B2*C2")
    assert_eq(s.get("E2")["day"], 15)
    assert_eq(s.get("F2"), true)
    assert_eq(s.get("A4"), "a  b")
    assert_eq(s.cell("A1").style["bold"], true)
    assert_eq(s.cell("A1").style["fill"], "D9E2F3")
    assert_eq(s.merged, ["A6:B6"])
    assert_eq(s.freeze_cell, "A2")
    assert_eq(s.cell("B2").comment, "note")
    assert_eq(wb2.defined_names["Total"], "Ventes!$D$2")
    assert_eq(wb2.sheet("Autre").get("A1"), 9)
    assert_eq(ods.read_rows(p("v.ods"))[1][0], "Pommes")

testing.test("ods aller-retour", t_ods)

func t_odp():
    prs := pp.new()
    prs.add_title_slide("Bilan", "Sous-titre")
    prs.add_bullet_slide("Points", ["un", ["deux"], "trois"], "mes notes")
    prs.add_table_slide("Tableau", [["A", "B"], [1, 2]])
    prs.add_chart_slide("Graphique", "column", ["T1", "T2"], [{"name": "S", "values": [1, 2]}])
    s := prs.add_slide("blank")
    s.add_shape("ellipse", "2cm", "2cm", "4cm", "4cm", "Rond", "C00000")
    s.background = "FFF2CC"
    odp.save(prs, p("b.odp"))
    p2 := odp.read(p("b.odp"))
    assert_eq(p2.count(), 5)
    assert_eq(p2.slide(0).title(), "Bilan")
    assert_eq(p2.slide(0).layout, "title")
    assert_eq(p2.slide(1).notes, "mes notes")
    assert_eq(p2.slide(1).texts()[1], "un\ndeux\ntrois")
    assert_eq(p2.slide(2).tables()[0].data(), [["A", "B"], ["1", "2"]])
    ch := p2.slide(3).charts()[0]
    assert_eq(ch.categories, ["T1", "T2"])
    assert_eq(ch.series[0]["values"], [1, 2])
    assert_eq(p2.slide(4).background, "FFF2CC")
    assert_eq(p2.slide(4).shapes[0].kind, "ellipse")

testing.test("odp aller-retour", t_odp)

failed := testing.run()
fs.remove_tree(_tmp)
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) office (ODF) en échec")
print("OFFICE ODF: OK")
