# ALEX STANDARD LIBRARY — office.spreadsheet
# Tableurs, tous formats confondus : ouverture et enregistrement de XLSX, ODS, CSV, TSV, JSON, HTML, Markdown,
# texte et PDF autour d'un modèle unique — le classeur d'office.excel (Workbook / Worksheet / Cell : valeurs,
# formules, styles, fusions...). Les formules sont recalculées avant l'export (valeurs à jour partout).
#
#   use office.spreadsheet as sheet
#   wb := sheet.open("ventes.csv")                  # séparateur, encodage et types détectés
#   wb.sheet(0).set("D1", "Total")
#   sheet.save(wb, "ventes.xlsx")                   # ou .ods .csv .tsv .json .html .md .txt .pdf
#   sheet.convert("budget.ods", "budget.xlsx")
#   rows := sheet.read_rows("export.xlsx")          # lignes de la première feuille
#   recs := sheet.read_records("clients.ods")       # [{"nom": ..., "ville": ...}, ...]
#   print(sheet.to_text(wb))                        # tableau aligné pour la console
#
# OUVRIR      open(src, format=null, options=null) -> excel.Workbook
#             format : "xlsx" "xlsm" "ods" "csv" "tsv" "json" "html" (null : détecté). options (CSV / TSV / JSON) :
#             {"delimiter": null, "decimal": ".", "infer": true, "sheet": "Feuil1", "header": true}
#             read_rows(src, sheet=null, format=null)  read_records(src, sheet=null, format=null)
# ENREGISTRER save(wb, chemin, format=null, options=null) -> chemin   to_bytes(wb, format, options=null) -> octets
#             options : {"sheet": nom_ou_indice (CSV/TSV/MD/TXT : feuille exportée, la première par défaut),
#             "delimiter": ",", "dialect": "rfc" | "excel", "orient": "records" | "rows" (JSON), "display": true
#             (valeurs formatées en HTML/MD/TXT/PDF), "landscape": false, "calculate": true}
#             convert(src, dst, options=null) -> dst
# MODÈLE      new(nom="Feuil1")  from_rows(lignes, nom="Feuil1", header=false)  from_records(dicts, nom, columns=null)
#             to_rows(wb, sheet=null, display=false)  to_records(wb, sheet=null)
# EXPORTS     to_csv(wb, sheet=null, delimiter=",", dialect="rfc")  to_tsv(wb, sheet=null)  to_json(wb, sheet=null,
#             orient="records")  to_html(wb, full=true)  to_markdown(wb, sheet=null)  to_text(wb, sheet=null)
#             to_pdf(wb, options=null) -> octets
# FORMATS     FORMATS (lecture / écriture)   format_of(chemin) -> nom de format
# Erreurs : FormatError, ConversionError, XLSXError, ODFError, CSVError, JSONError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use io
use office.errors as errors
use office.utils as u
use office.core as core
use office.excel as excel
use office.ods as ods
use office.csv as ocsv
use office.tsv as otsv
use office.json as ojson
use office.html as ohtml
use office.xlsx_cells as xc
use office.pdf as pdf

const FORMATS := {"read": ["xlsx", "xlsm", "ods", "csv", "tsv", "json", "html"], "write": ["xlsx", "ods", "csv", "tsv", "json", "html", "md", "txt", "pdf"]}

func format_of(path):
    ext := string.lower(core.extension_of(path))
    if ext == "htm":
        return "html"
    if ext == "markdown":
        return "md"
    if ext == "text":
        return "txt"
    if ext == "tab":
        return "tsv"
    if ext == "jsonl" or ext == "ndjson":
        return "json"
    if ext == "xltx" or ext == "xlsm":
        return "xlsx"
    if ext == "ots":
        return "ods"
    return ext

func new(name="Feuil1"):
    return excel.new(name)

func from_rows(rows, name="Feuil1", header=false):
    return excel.from_rows(rows, name, header)

func from_records(records, name="Feuil1", columns=null):
    return excel.from_records(records, name, columns)

# ---------------------------------------------------------------------------------------------- ouverture

func _detect(src):
    if type(src) == "str":
        f := format_of(src)
        if f == "csv" or f == "tsv" or f == "json" or f == "html" or f == "txt":
            return f if f != "txt" else "tsv"
    k := core.detect_format(src)
    if k == "xlsx" or k == "ods":
        return k
    if k == "html" or k == "json" or k == "csv" or k == "tsv":
        return k
    if k == "text":
        return "csv"
    errors.fail(errors.FORMAT, "format de tableur non reconnu (" + k + ")")

func _text_of(src):
    if type(src) == "str":
        return u.decode_text(io.read_bytes(src))
    return u.decode_text(src)

func _wb_from_rows(rows, name):
    wb := excel.new(name)
    ws := wb.active_sheet()
    for r in rows:
        ws.append(r)
    return wb

func open(src, format=null, options=null):
    o := options if options != null else {}
    f := format if format != null else _detect(src)
    if f == "xlsx" or f == "xlsm":
        return excel.open(src)
    if f == "ods":
        return ods.read(src)
    name := u.get(o, "sheet", "Feuil1")
    if type(name) != "str":
        name = "Feuil1"
    if f == "csv":
        rows := ocsv.parse(_text_of(src), u.get(o, "delimiter", null), u.get(o, "infer", true), u.get(o, "decimal", "."))
        return _wb_from_rows(rows, name)
    if f == "tsv":
        rows := otsv.parse(_text_of(src), u.get(o, "infer", true), u.get(o, "mode", "escape"), u.get(o, "decimal", "."))
        return _wb_from_rows(rows, name)
    if f == "json":
        data := ojson.parse(_text_of(src))
        # objet de tables {"feuille": [...]} -> une feuille par clé
        if type(data) == "dict" and len(keys(data)) > 0 and not contains_key(data, "columns"):
            all_tables := true
            for k in keys(data):
                if type(data[k]) != "list" or (len(data[k]) > 0 and type(data[k][0]) != "dict" and type(data[k][0]) != "list"):
                    all_tables = false
            if all_tables:
                wb := excel.Workbook(null)
                wb.sheets = []
                for k in keys(data):
                    ws := wb.add_sheet(k)
                    for r in ojson.to_rows(data[k]):
                        ws.append(r)
                return wb
        return _wb_from_rows(ojson.to_rows(data), name)
    if f == "html":
        doc := ohtml.parse(_text_of(src))
        tables := ohtml.extract_tables(doc, false)
        if len(tables) == 0:
            errors.fail(errors.CONVERSION, "aucun tableau dans la page HTML")
        wb := excel.Workbook(null)
        wb.sheets = []
        k := 1
        for t in tables:
            ws := wb.add_sheet("Tableau" + str(k))
            for r in ocsv.infer_rows(t):
                ws.append(r)
            k = k + 1
        return wb
    errors.fail(errors.FORMAT, "lecture non prise en charge pour le format « " + u.to_text(f) + " »")

func _ws(wb, sheet):
    if sheet == null:
        return wb.sheets[0]
    return wb.sheet(sheet)

func read_rows(src, sheet=null, format=null):
    return _ws(open(src, format), sheet).to_rows()

func read_records(src, sheet=null, format=null):
    return to_records(open(src, format), sheet)

# ---------------------------------------------------------------------------------------------- modèle -> données

func _cell_display(c):
    if c == null:
        return ""
    if c.value == null:
        return ""
    try:
        return c.display()
    catch e:
        return xc.to_display(c.value)

func to_rows(wb, sheet=null, display=false):
    ws := _ws(wb, sheet)
    if not display:
        return ws.to_rows()
    out := []
    r := 1
    mr := ws.max_row()
    mc := ws.max_col()
    while r <= mr:
        line := []
        c := 1
        while c <= mc:
            append(line, _cell_display(ws.find_cell(r, c)))
            c = c + 1
        append(out, line)
        r = r + 1
    return out

func to_records(wb, sheet=null):
    rows := to_rows(wb, sheet)
    if len(rows) == 0:
        return []
    return ojson.rows_to_records(rows)

func _plain_rows(wb, sheet):
    # valeurs exportables en texte : erreurs -> code, dates conservées (sérialisées par csv/json)
    rows := to_rows(wb, sheet)
    for r in rows:
        k := 0
        while k < len(r):
            if xc.is_error(r[k]):
                r[k] = r[k].code
            k = k + 1
    return rows

func to_csv(wb, sheet=null, delimiter=",", dialect="rfc"):
    return ocsv.stringify(_plain_rows(wb, sheet), delimiter, dialect)

func to_tsv(wb, sheet=null):
    return otsv.stringify(_plain_rows(wb, sheet))

func to_json(wb, sheet=null, orient="records", indent=2):
    if sheet == null and len(wb.sheets) > 1:
        out := {}
        for ws in wb.sheets:
            out[ws.name] = ojson.from_rows(_plain_rows(wb, ws.name), orient)
        return ojson.stringify(ojson.to_json_value(out), indent)
    return ojson.stringify(ojson.to_json_value(ojson.from_rows(_plain_rows(wb, sheet), orient)), indent)

func to_rows_of(ws, display):
    out := []
    r := 1
    mr := ws.max_row()
    mc := ws.max_col()
    while r <= mr:
        line := []
        c := 1
        while c <= mc:
            cell := ws.find_cell(r, c)
            if display:
                append(line, _cell_display(cell))
            else:
                append(line, cell.value if cell != null else null)
            c = c + 1
        append(out, line)
        r = r + 1
    return out

func to_html(wb, full=true, display=true):
    parts := []
    for ws in wb.sheets:
        if ws.state != "visible":
            continue
        append(parts, "<h2>" + ohtml.escape(ws.name) + "</h2>")
        rows := to_rows_of(ws, display)
        if len(rows) == 0:
            append(parts, "<p><em>(feuille vide)</em></p>")
        else:
            append(parts, ohtml.table(rows, true))
    body := string.join("\n", parts)
    if not full:
        return body
    t := wb.metadata.title
    return ohtml.document(t if t != "" else "Classeur", body)

func _md_cell(v):
    return string.replace(string.replace(u.to_text(v), "|", "\\|"), "\n", "<br>")

func to_markdown(wb, sheet=null, display=true):
    sheets := wb.sheets if sheet == null else [_ws(wb, sheet)]
    out := []
    for ws in sheets:
        if len(sheets) > 1:
            append(out, "## " + ws.name)
            append(out, "")
        rows := to_rows_of(ws, display)
        if len(rows) == 0:
            append(out, "*(feuille vide)*")
            append(out, "")
            continue
        n := 0
        for r in rows:
            if len(r) > n:
                n = len(r)
        k := 0
        for r in rows:
            cells := []
            c := 0
            while c < n:
                append(cells, _md_cell(r[c]) if c < len(r) else "")
                c = c + 1
            append(out, "| " + string.join(" | ", cells) + " |")
            if k == 0:
                seps := []
                c = 0
                while c < n:
                    v := rows[1][c] if len(rows) > 1 and c < len(rows[1]) else ""
                    num := _n.num_parse(string.replace(string.replace(u.to_text(v), " ", ""), ",", "."))
                    append(seps, "---:" if num != null and u.to_text(v) != "" else "---")
                    c = c + 1
                append(out, "| " + string.join(" | ", seps) + " |")
            k = k + 1
        append(out, "")
    return string.join("\n", out)

func _width(s):
    w := 0
    for line in string.split(s, "\n"):
        if len(line) > w:
            w = len(line)
    return w

func to_text(wb, sheet=null, display=true):
    sheets := wb.sheets if sheet == null else [_ws(wb, sheet)]
    out := []
    for ws in sheets:
        if len(sheets) > 1:
            append(out, "[" + ws.name + "]")
        rows := to_rows_of(ws, display)
        widths := []
        for r in rows:
            k := 0
            for v in r:
                t := string.replace(u.to_text(v), "\n", " ")
                if k >= len(widths):
                    append(widths, 0)
                if len(t) > widths[k]:
                    widths[k] = len(t) if len(t) < 60 else 60
                k = k + 1
        ri := 0
        for r in rows:
            cells := []
            k := 0
            for v in r:
                t := string.replace(u.to_text(v), "\n", " ")
                if len(t) > 60:
                    t = u.str_slice(t, 0, 59) + "…"
                cell := ws.find_cell(ri + 1, k + 1)
                vt := type(cell.value) if cell != null else "null"
                is_num := vt == "int" or vt == "float"
                append(cells, u.pad_left(t, widths[k]) if is_num else u.pad_right(t, widths[k]))
                k = k + 1
            append(out, _rstrip(string.join("  ", cells)))
            if ri == 0 and len(rows) > 1:
                seps := []
                for w in widths:
                    append(seps, string.repeat("-", w))
                append(out, string.join("  ", seps))
            ri = ri + 1
        append(out, "")
    return string.join("\n", out)

func _rstrip(s):
    t := s
    while string.ends_with(t, " "):
        t = _n.str_slice(t, 0, len(t) - 1)
    return t

# PDF : une section par feuille (titre + tableau paginé, en-tête répété).
func to_pdf(wb, options=null):
    o := options if options != null else {}
    doc := pdf.new(u.get(o, "size", "A4"), u.get(o, "landscape", false), u.get(o, "margins", 42.5), u.get(o, "font", "Helvetica"), u.get(o, "font_size", 10))
    t := wb.metadata.title
    if t != "":
        doc.info["Title"] = t
    doc.set_footer("{page} / {total}")
    first := true
    for ws in wb.sheets:
        if ws.state != "visible":
            continue
        if not first and u.get(o, "page_per_sheet", true):
            doc.add_page_break()
        if len(wb.sheets) > 1 or t != "":
            doc.add_heading(ws.name, 2)
        rows := to_rows_of(ws, u.get(o, "display", true))
        if len(rows) == 0:
            doc.add_paragraph("(feuille vide)")
        else:
            doc.add_table(rows, u.get(o, "header", true))
        first = false
    return doc.to_bytes()

# ---------------------------------------------------------------------------------------------- enregistrement

func to_bytes(wb, format, options=null):
    o := options if options != null else {}
    f := string.lower(format)
    if u.get(o, "calculate", true) and f != "xlsx" and f != "ods":
        wb.calculate()
    sheet := u.get(o, "sheet", null)
    if f == "xlsx" or f == "xlsm":
        return wb.to_bytes(u.get(o, "calculate", true))
    if f == "ods":
        return ods.write(wb, u.get(o, "calculate", true))
    if f == "csv":
        txt := to_csv(wb, sheet, u.get(o, "delimiter", ","), u.get(o, "dialect", "rfc"))
        if u.get(o, "dialect", "rfc") == "excel":
            return u.concat([[239, 187, 191], _n.utf8_encode(txt)])
        return _n.utf8_encode(txt)
    if f == "tsv":
        return _n.utf8_encode(to_tsv(wb, sheet))
    if f == "json":
        return _n.utf8_encode(to_json(wb, sheet, u.get(o, "orient", "records")))
    if f == "html" or f == "htm":
        return _n.utf8_encode(to_html(wb, true, u.get(o, "display", true)))
    if f == "md" or f == "markdown":
        return _n.utf8_encode(to_markdown(wb, sheet, u.get(o, "display", true)))
    if f == "txt" or f == "text":
        return _n.utf8_encode(to_text(wb, sheet, u.get(o, "display", true)))
    if f == "pdf":
        return to_pdf(wb, o)
    errors.fail(errors.CONVERSION, "écriture de tableur non prise en charge pour le format « " + format + " »")

func save(wb, path, format=null, options=null):
    f := format if format != null else format_of(path)
    io.write_bytes(path, to_bytes(wb, f, options))
    return path

func convert(src, dst, options=null):
    wb := open(src, null, options)
    return save(wb, dst, null, options)
