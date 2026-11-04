# ALEX STANDARD LIBRARY — office.conversion
# Conversions entre formats bureautiques, en passant par trois modèles : document (office.document), classeur
# (office.excel.Workbook) et présentation (office.powerpoint.Presentation). Toutes les combinaisons utiles sont
# couvertes, y compris d'une famille à l'autre (tableaux d'un document -> feuilles, classeur -> document,
# document -> diaporama, diaporama -> document, PDF -> texte structuré ou tableaux).
#
#   use office.conversion as conv
#   conv.convert("rapport.docx", "rapport.pdf")
#   conv.convert("notes.md", "notes.odt")
#   conv.convert("budget.xlsx", "budget.ods")
#   conv.convert("cours.pptx", "cours.html")
#   conv.convert("plan.md", "plan.pptx")              # un titre = une diapositive
#   conv.convert("releve.pdf", "releve.xlsx")         # tableaux détectés -> une feuille par tableau
#   obj := conv.load("compte-rendu.odt")              # -> document.Document
#   conv.save(obj, "compte-rendu.docx")
#
# convert(src, dst, options=null) -> dst   (options transmises aux exports : voir document / spreadsheet /
#   presentation ; « format » force le format de sortie, « from » celui d'entrée)
# load(src, format=null, options=null) -> Document | Workbook | Presentation
# save(objet, chemin, format=null, options=null) -> chemin    to_bytes(objet, format, options=null) -> octets
# to_document(objet) / to_spreadsheet(objet) / to_presentation(objet)
# family(format) -> "document" | "spreadsheet" | "presentation" | null    detect(src) -> format
# can_convert(de, vers) -> bool    targets(de) -> formats accessibles    FORMATS
# pdf_to_document(src, options=null) -> Document (titres d'après la taille des caractères, listes, paragraphes)
# pdf_to_workbook(src, options=null) -> Workbook (tableaux détectés)
# Erreurs : ConversionError (combinaison impossible), FormatError, et celles des modules de format.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.core as core
use office.document as document
use office.odt as odt
use office.word as word
use office.excel as excel
use office.spreadsheet as sheet
use office.powerpoint as pp
use office.presentation as pres
use office.pdf_reader as pr
use office.pdf_extract as ex
use office.pdf_tables as ptab

const FORMATS := {"document": ["docx", "odt", "html", "md", "txt", "pdf"], "spreadsheet": ["xlsx", "ods", "csv", "tsv", "json"], "presentation": ["pptx", "odp"]}
const _OUT := {"document": ["docx", "odt", "html", "md", "txt", "pdf", "pptx", "odp", "xlsx", "ods", "csv"], "spreadsheet": ["xlsx", "ods", "csv", "tsv", "json", "html", "md", "txt", "pdf", "docx", "odt", "pptx", "odp"], "presentation": ["pptx", "odp", "pdf", "html", "md", "txt", "docx", "odt", "xlsx", "ods", "csv"]}

func _norm(f):
    t := string.lower(f)
    if string.starts_with(t, "."):
        t = _n.str_slice(t, 1, null)
    m := {"htm": "html", "markdown": "md", "text": "txt", "docm": "docx", "dotx": "docx", "xlsm": "xlsx", "xltx": "xlsx", "pptm": "pptx", "potx": "pptx", "ott": "odt", "ots": "ods", "otp": "odp", "tab": "tsv"}
    return u.get(m, t, t)

func family(fmt):
    f := _norm(fmt)
    if f == "pdf":
        return "document"
    for k in keys(FORMATS):
        for e in FORMATS[k]:
            if e == f:
                return k
    return null

func detect(src):
    if type(src) == "str":
        ext := _norm(core.extension_of(src))
        if ext == "md" or ext == "txt" or ext == "csv" or ext == "tsv" or ext == "json":
            return ext
    k := core.detect_format(src)
    if k == "text":
        return "txt"
    return k

func targets(fmt):
    fam := family(fmt)
    if fam == null:
        return []
    out := []
    for t in _OUT[fam]:
        append(out, t)
    return out

func can_convert(src_fmt, dst_fmt):
    for t in targets(src_fmt):
        if t == _norm(dst_fmt):
            return true
    return false

# ---------------------------------------------------------------------------------------------- chargement

func _text(src):
    if type(src) == "str":
        return u.decode_text(io.read_bytes(src))
    return u.decode_text(src)

func load(src, format=null, options=null):
    f := _norm(format) if format != null else detect(src)
    if f == "docx":
        return document.from_docx(src)
    if f == "odt":
        return odt.read(src)
    if f == "html":
        return document.from_html(_text(src))
    if f == "md":
        return document.from_markdown(_text(src))
    if f == "txt":
        return document.from_text(_text(src))
    if f == "pdf":
        return pdf_to_document(src, options)
    if f == "xlsx" or f == "ods" or f == "csv" or f == "tsv" or f == "json":
        return sheet.open(src, f, options)
    if f == "pptx" or f == "odp":
        return pres.open(src, f)
    errors.fail(errors.CONVERSION, "format d'entrée non pris en charge : « " + u.to_text(f) + " »")

func _kind(obj):
    if isinstance(obj, document.Document):
        return "document"
    if isinstance(obj, excel.Workbook):
        return "spreadsheet"
    if isinstance(obj, pp.Presentation):
        return "presentation"
    if isinstance(obj, word.WordDocument):
        return "word"
    raise("TypeError", "conversion : Document, Workbook ou Presentation attendu")

# ---------------------------------------------------------------------------------------------- passerelles

func to_document(obj):
    k := _kind(obj)
    if k == "document":
        return obj
    if k == "word":
        return document.from_docx(obj)
    if k == "presentation":
        return pres.to_document(obj)
    # classeur : un titre et un tableau par feuille
    d := document.Document(obj.metadata.title)
    d.metadata = obj.metadata
    for ws in obj.sheets:
        if ws.state != "visible":
            continue
        if len(obj.sheets) > 1:
            d.add_heading(ws.name, 2)
        obj.calculate()
        rows := sheet.to_rows_of(ws, true)
        if len(rows) > 0:
            d.add_table(rows, true)
    return d

func to_spreadsheet(obj):
    k := _kind(obj)
    if k == "spreadsheet":
        return obj
    d := to_document(obj)
    wb := excel.Workbook(null)
    wb.sheets = []
    wb.metadata = d.metadata
    n := 1
    for t in d.tables():
        ws := wb.add_sheet("Tableau" + str(n))
        for r in t:
            line := []
            for v in r:
                append(line, _typed(v))
            ws.append(line)
        if len(t) > 0:
            ws.set_style(u.range_ref(1, 1, 1, len(t[0]) if len(t[0]) > 0 else 1), {"bold": true})
        n = n + 1
    if len(wb.sheets) == 0:
        # pas de tableau : un paragraphe par ligne
        ws := wb.add_sheet("Texte")
        for b in d.blocks:
            t := b.plain()
            if t != "":
                ws.append([t])
    return wb

# Texte de cellule -> nombre si la conversion est sûre (« 1 234,5 », « 12 % » restent du texte sauf forme simple).
func _typed(v):
    if type(v) != "str":
        return v
    t := string.trim(v)
    if t == "":
        return null
    n := _n.num_parse(t)
    if n != null and not (string.starts_with(t, "0") and len(t) > 1 and not string.starts_with(t, "0.")):
        return n
    return v

func to_presentation(obj):
    k := _kind(obj)
    if k == "presentation":
        return obj
    return pres.from_document(to_document(obj))

# ---------------------------------------------------------------------------------------------- enregistrement

func to_bytes(obj, format, options=null):
    f := _norm(format)
    o := options if options != null else {}
    k := _kind(obj)
    if k == "word":
        if f == "docx":
            return obj.to_bytes()
        obj = document.from_docx(obj)
        k = "document"
    if f == "docx" or f == "odt" or f == "md" or f == "txt" or (f == "html" and k == "document") or (f == "pdf" and k == "document"):
        d := to_document(obj)
        if f == "docx":
            return d.to_docx().to_bytes()
        if f == "odt":
            return odt.write(d, o)
        if f == "md":
            if k == "presentation":
                return _n.utf8_encode(pres.to_markdown(obj, u.get(o, "notes", true)))
            if k == "spreadsheet":
                return _n.utf8_encode(sheet.to_markdown(obj))
            return _n.utf8_encode(d.to_markdown())
        if f == "txt":
            if k == "presentation":
                return _n.utf8_encode(pres.to_text(obj, u.get(o, "notes", true)))
            if k == "spreadsheet":
                return _n.utf8_encode(sheet.to_text(obj))
            return _n.utf8_encode(d.text())
        if f == "html":
            return _n.utf8_encode(d.to_html(true, u.get(o, "css", null)))
        if f == "pdf":
            return d.to_pdf(o).to_bytes()
    if f == "xlsx" or f == "ods" or f == "csv" or f == "tsv" or f == "json" or (f == "html" and k == "spreadsheet") or (f == "pdf" and k == "spreadsheet"):
        return sheet.to_bytes(to_spreadsheet(obj), f, o)
    if f == "pptx" or f == "odp" or (f == "html" and k == "presentation") or (f == "pdf" and k == "presentation"):
        return pres.to_bytes(to_presentation(obj), f, o)
    errors.fail(errors.CONVERSION, "conversion vers « " + format + " » non prise en charge")

func save(obj, path, format=null, options=null):
    f := format if format != null else _norm(core.extension_of(path))
    io.write_bytes(path, to_bytes(obj, f, options))
    return path

func convert(src, dst, options=null):
    o := options if options != null else {}
    src_fmt := u.get(o, "from", null)
    sf := _norm(src_fmt) if src_fmt != null else detect(src)
    df := _norm(u.get(o, "format", core.extension_of(dst)))
    if sf == "pdf" and (df == "xlsx" or df == "ods" or df == "csv" or df == "tsv" or df == "json"):
        return sheet.save(pdf_to_workbook(src, o), dst, df, o)
    obj := load(src, sf, o)
    return save(obj, dst, df, o)

# ---------------------------------------------------------------------------------------------- PDF

func _mode_size(lines):
    weights := {}
    for l in lines:
        k := str(u.round_to(l["size"], 1))
        weights[k] = u.get(weights, k, 0) + len(l["text"])
    best := "0"
    bw := -1
    for k in keys(weights):
        if weights[k] > bw:
            bw = weights[k]
            best = k
    v := _n.num_parse(best)
    return to_float(v) if v != null else 11.0

func _bullet_of(t):
    for b in ["• ", "◦ ", "▪ ", "- ", "– ", "* ", "· "]:
        if string.starts_with(t, b):
            return [false, string.trim(_n.str_slice(t, len(b), null))]
    k := 0
    while k < len(t) and k < 3 and string.ord(t[k]) >= 48 and string.ord(t[k]) <= 57:
        k = k + 1
    if k > 0 and k + 1 < len(t) and (str(t[k]) == "." or str(t[k]) == ")") and str(t[k + 1]) == " ":
        return [true, string.trim(_n.str_slice(t, k + 2, null))]
    return null

# Texte normalisé (chiffres -> #) pour repérer les en-têtes / pieds de page répétés.
func _sig(t):
    out := []
    for c in t:
        o := string.ord(c)
        append(out, "#" if o >= 48 and o <= 57 else str(c))
    s := string.join("", out)
    while string.contains(s, "##"):
        s = string.replace(s, "##", "#")
    return s

func _is_page_number(sig):
    low := string.lower(string.trim(sig))
    return low == "#" or low == "# / #" or low == "#/#" or low == "page #" or low == "page # / #" or low == "page # sur #" or low == "- # -" or low == "p. #"

# PDF -> document : titres (tailles de police supérieures au corps, classées en niveaux), listes (puces, numéros),
# paragraphes (écart vertical), tableaux à filets, en-têtes / pieds de page répétés et numéros de page retirés,
# sauts de page facultatifs (options {"page_breaks": true}).
func pdf_to_document(src, options=null):
    o := options if options != null else {}
    doc := ex.open(src, u.get(o, "password", ""))
    d := document.Document()
    info := doc.info()
    t0 := u.get(info, "Title", "")
    if type(t0) == "str" and t0 != "":
        d.title = t0
        d.metadata.title = t0
    pages := doc.pages()
    all_lines := []
    all_tables := []
    heights := []
    for pg in pages:
        append(all_lines, ex.lines(pg))
        tb := []
        try:
            tb = ptab.page_tables(pg, "lines")
        catch e:
            tb = []
        append(all_tables, tb)
        append(heights, to_float(pg.height()))
    # en-têtes / pieds répétés
    counts := {}
    pi := 0
    for ls in all_lines:
        seen := {}
        for l in ls:
            y := to_float(l["y"])
            if y < heights[pi] * 0.09 or y > heights[pi] * 0.91:
                k := _sig(string.trim(l["text"]))
                if not contains_key(seen, k):
                    seen[k] = true
                    counts[k] = u.get(counts, k, 0) + 1
        pi = pi + 1
    npages := len(pages)
    flat := []
    for ls in all_lines:
        for l in ls:
            append(flat, l)
    body := _mode_size(flat)
    # niveaux de titres : tailles distinctes au-dessus du corps, de la plus grande à la plus petite
    hsizes := []
    for l in flat:
        sz := u.round_to(to_float(l["size"]), 0)
        if sz >= body * 1.2 and len(string.trim(l["text"])) < 150:
            dup := false
            for h in hsizes:
                if h == sz:
                    dup = true
            if not dup:
                append(hsizes, sz)
    hsizes = u.sort(hsizes, (v) => -v)
    pi = 0
    for ls in all_lines:
        if pi > 0 and u.get(o, "page_breaks", false):
            d.add_page_break()
        tables := all_tables[pi]
        emitted := {}
        para := ""
        prev := null
        for l in ls:
            txt := string.trim(l["text"])
            if txt == "":
                continue
            y := to_float(l["y"])
            if y < heights[pi] * 0.09 or y > heights[pi] * 0.91:
                sg := _sig(txt)
                if _is_page_number(sg) or (npages >= 2 and u.get(counts, sg, 0) >= (npages + 1) // 2 and u.get(counts, sg, 0) >= 2):
                    continue
            # ligne dans un tableau détecté : le tableau est émis à sa place
            in_table := -1
            ti := 0
            for t in tables:
                bb := t["bbox"]
                if y >= to_float(bb[1]) - 2.0 and y <= to_float(bb[3]) + 2.0:
                    in_table = ti
                ti = ti + 1
            if in_table >= 0:
                if para != "":
                    _emit(d, para)
                    para = ""
                if not contains_key(emitted, in_table):
                    emitted[in_table] = true
                    rows := tables[in_table]["rows"]
                    d.add_table(rows, true)
                prev = null
                continue
            sz := to_float(l["size"])
            gap := (y - to_float(prev["y"])) if prev != null else 0.0
            is_head := sz >= body * 1.2 and len(txt) < 150
            bl := _bullet_of(txt)
            new_para := prev == null or gap > to_float(prev["size"]) * 1.6 or gap < 0.0 or is_head or bl != null or (prev != null and to_float(prev["size"]) >= body * 1.2)
            if new_para and para != "":
                _emit(d, para)
                para = ""
            if is_head:
                lvl := 1
                k := 0
                for h in hsizes:
                    if h == u.round_to(sz, 0):
                        lvl = k + 1
                    k = k + 1
                if lvl > 6:
                    lvl = 6
                last := d.blocks[len(d.blocks) - 1] if len(d.blocks) > 0 else null
                if last != null and last.kind == "heading" and last.level == lvl and prev != null and gap <= sz * 1.5 and to_float(prev["size"]) == sz:
                    last.runs = [document.Run(document.runs_text(last.runs) + " " + txt)]
                else:
                    d.add_heading(txt, lvl)
                    if d.title == "" and lvl == 1:
                        d.title = txt
            elif bl != null:
                para = "\u0001" + ("1" if bl[0] else "0") + bl[1]
            else:
                if para != "" and string.ends_with(para, "-") and not string.ends_with(para, " -"):
                    para = _n.str_slice(para, 0, len(para) - 1) + txt
                else:
                    para = txt if para == "" else para + " " + txt
            prev = l
        if para != "":
            _emit(d, para)
        pi = pi + 1
    return d

func _emit(d, para):
    if string.starts_with(para, "\u0001"):
        b := d.add_list_item(_n.str_slice(para, 2, null), 0, _n.str_slice(para, 1, 2) == "1")
        return b
    return d.add_paragraph(para)

func pdf_to_workbook(src, options=null):
    o := options if options != null else {}
    tables := ptab.extract_tables(src, u.get(o, "pages", null), u.get(o, "strategy", "auto"), u.get(o, "password", ""))
    wb := excel.Workbook(null)
    wb.sheets = []
    k := 1
    for t in tables:
        ws := wb.add_sheet("Tableau" + str(k) + " (p" + str(t["page"] + 1) + ")")
        for r in t["rows"]:
            line := []
            for v in r:
                append(line, _typed(v))
            ws.append(line)
        k = k + 1
    if len(wb.sheets) == 0:
        ws := wb.add_sheet("Texte")
        for line in string.split(ex.text(src, null, false, u.get(o, "password", "")), "\n"):
            if string.trim(line) != "":
                ws.append([string.trim(line)])
    return wb
