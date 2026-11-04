# ALEX - tests office : socle (utils, compression, archive, xml, core, metadata, csv/tsv/json/html, erreurs).
# Lancer depuis la racine : ./alex run tests/office/test_office_base.al
from core use len, type
use io
use os
use filesystem as fs
use testing
from testing use assert_eq, assert_true, assert_false, assert_raises, assert_near, assert_null
use office.utils as u
use office.errors as errors
use office.compression as z
use office.archive as zip
use office.xml as x
use office.core as core
use office.metadata as meta
use office.csv as ocsv
use office.tsv as otsv
use office.json as oj
use office.html as oh
use office.word as word

_tmp := fs.make_temp_dir("alex_office_base_")

func p(name):
    return os.join(_tmp, name)

func t_utils():
    assert_eq(u.column_letter(1), "A")
    assert_eq(u.column_letter(28), "AB")
    assert_eq(u.column_index("AB"), 28)
    assert_eq(u.parse_cell("$C$7")["row"], 7)
    assert_eq(u.range_ref(1, 1, 3, 2), "A1:B3")
    assert_eq(u.split_sheet_ref("'Feuille 1'!A1"), ["Feuille 1", "A1"])
    assert_eq(u.quote_sheet("Feuille 1"), "'Feuille 1'")
    assert_eq(u.color_hex("rouge"), "FF0000")
    assert_eq(u.color_hex("#abc"), "AABBCC")
    assert_eq(u.length("1in"), 914400)
    assert_eq(u.date_to_serial(2024, 3, 15), 45366)
    assert_eq(u.serial_to_date(45366)["day"], 15)
    assert_eq(u.sort([3, 1, 2]), [1, 2, 3])
    assert_eq(u.sort([{"n": 2}, {"n": 1}], (d) => d["n"])[0]["n"], 1)
    assert_eq(u.utf8_decode(u.utf8_encode("é😀")), "é😀")
    assert_eq(u.cp1252_decode([128]), "€")
    assert_eq(u.decode_text([239, 187, 191, 104, 105]), "hi")
    assert_eq(u.format_number(1.5), "1.5")
    assert_eq(u.parse_number("42"), 42)
    assert_eq(u.base64_decode(u.base64_encode("abc")), u.bytes_of("abc"))

testing.test("utils", t_utils)

func t_compression():
    data := ""
    k := 0
    while k < 200:
        data = data + "texte très répétitif "
        k = k + 1
    for f in ["raw", "zlib", "gzip"]:
        c := z.compress(data, f, 9)
        assert_true(len(c) < len(u.bytes_of(data)) / 5)
        assert_eq(z.decompress_text(c), data)
    assert_eq(z.crc32("123456789"), 3421780262)
    assert_eq(z.detect(z.gzip_compress("x")), "gzip")
    assert_raises(() => z.zlib_decompress([1, 2, 3, 4]), "CompressionError")
    assert_raises(() => z.inflate(z.deflate(data), 10), "CompressionError")

testing.test("compression", t_compression)

func t_archive():
    a := zip.new()
    a.write("mimetype", "text/plain", false)
    a.write_text("dossier/é.txt", "bonjour")
    b := a.to_bytes()
    assert_true(zip.is_zip(b))
    r := zip.from_bytes(b)
    assert_eq(r.names(), ["mimetype", "dossier/é.txt"])
    assert_eq(r.read_text("dossier/é.txt"), "bonjour")
    assert_eq(r.info("mimetype").method, 0)
    r.rename("mimetype", "type")
    r.remove("dossier/é.txt")
    r.save(p("a.zip"))
    assert_eq(zip.open(p("a.zip")).names(), ["type"])
    assert_raises(() => r.read("absent"), "ArchiveError")

testing.test("archive zip", t_archive)

func t_xml():
    root := x.parse("<a xmlns:w=\"urn:w\"><w:p w:val=\"1\">Bon<w:r>jour</w:r></w:p><b/></a>")
    assert_eq(len(x.find_all(root, "w:r")), 1)
    assert_eq(len(x.find_all(root, "r")), 1)
    p0 := x.first(root, "p")
    assert_eq(x.attr(p0, "val"), "1")
    assert_eq(x.attr(p0, "absent", "d"), "d")
    assert_eq(x.text(p0), "Bonjour")
    assert_eq(len(x.children(root)), 2)
    assert_eq(x.stringify(x.el("t", {"a": "<&>", "n": null}, ["x<y"])), "<t a=\"&lt;&amp;&gt;\">x&lt;y</t>")
    assert_raises(() => x.parse("<a><b></a>"), "XMLError")

testing.test("xml", t_xml)

func t_core():
    w := word.new()
    w.add_paragraph("x")
    w.save(p("d.docx"))
    assert_eq(core.detect_format(p("d.docx")), "docx")
    assert_eq(core.extension_of("a/b.TXT"), "txt")
    pkg := core.open_package(p("d.docx"))
    assert_eq(pkg.main_part(), "word/document.xml")
    assert_eq(core.page_size("A4")[0], 595.28)
    m := meta.read(p("d.docx"))
    m.title = "Titre"
    m.custom["Projet"] = "Atlas"
    meta.write(p("d.docx"), m)
    m2 := meta.read(p("d.docx"))
    assert_eq(m2.title, "Titre")
    assert_eq(m2.custom["Projet"], "Atlas")

testing.test("core et métadonnées", t_core)

func t_text_formats():
    assert_eq(ocsv.sniff("a;b;c\n1;2;3\n"), ";")
    assert_eq(ocsv.parse("a;b\n1;2,5", null, true, ","), [["a", "b"], [1, 2.5]])
    assert_eq(ocsv.stringify([["a", "x,y"]]), "a,\"x,y\"\r\n")
    assert_eq(otsv.parse("a\tb\n1\t2\n", true), [["a", "b"], [1, 2]])
    assert_eq(otsv.stringify([["a\tb"]]), "a\\tb\n")
    assert_eq(oj.to_rows([{"a": 1, "b": 2}]), [["a", "b"], [1, 2]])
    assert_eq(oj.flatten({"a": {"b": 1}}), {"a.b": 1})
    assert_eq(oj.get_path({"a": [{"b": 3}]}, "a[0].b"), 3)
    doc := oh.parse("<html><head><title>T</title></head><body><p>Un <b>deux</b></p><table><tr><th>A</th></tr><tr><td>1</td></tr></table></body></html>")
    assert_eq(oh.title(doc), "T")
    assert_eq(oh.extract_tables(doc), [[["A"], ["1"]]])
    assert_true(string_contains(oh.to_text(doc), "Un deux"))

func string_contains(s, sub):
    return u.str_find(s, sub, 0) >= 0

testing.test("csv / tsv / json / html", t_text_formats)

func t_errors():
    assert_raises(() => errors.fail(errors.PDF, "x"), "PDFError")
    assert_true(len(errors.kinds()) >= 10)

testing.test("erreurs", t_errors)

failed := testing.run()
fs.remove_tree(_tmp)
if failed > 0:
    raise("AssertionError", str(failed) + " test(s) office (socle) en échec")
print("OFFICE BASE: OK")
