# ALEX STANDARD LIBRARY — office.xlsx_reader
# Lecture des classeurs Excel (.xlsx, .xlsm, .xltx) : feuilles (valeurs typées, formules, styles, fusions,
# largeurs, volets figés, filtres, liens), chaînes partagées, styles et formats de date, noms définis, images,
# graphiques, métadonnées. Les macros (.xlsm) ne sont ni lues ni exécutées ; le format binaire .xlsb n'est pas
# pris en charge (UnsupportedError).
#
#   use office.xlsx_reader as reader
#   parts := reader.read("ventes.xlsx")
#   ws := parts["sheets"][0]                     # xlsx_sheets.Worksheet
#   ws.to_rows()
#   reader.read_rows("ventes.xlsx", "Feuil1")     # lignes de valeurs d'une feuille (première par défaut)
#
# read(chemin_ou_octets, dates=true, styles=true) -> dict :
#   "sheets" (Worksheet, dans l'ordre du classeur)  "defined_names" (nom -> formule)  "active" (indice)
#   "date1904" (bool)  "metadata" (Metadata)  "package" (core.Package)
#   dates : les nombres au format date deviennent des dicts {year, month, day[, hour, minute, second]}
# read_rows(src, sheet=null, dates=true) -> lignes   sheet_names(src) -> noms
# Erreurs : FormatError, XLSXError, XMLError, ArchiveError, UnsupportedError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.core as core
use office.metadata as metadata
use office.xlsx_cells as xc
use office.xlsx_styles as xs
use office.xlsx_sheets as sheets
use office.xlsx_images as xi
use office.xlsx_charts as xch

class _ReadCtx:
    func init(pkg, part, sst, styles, dates, date1904, keep_styles):
        self.pkg = pkg
        self.part = part
        self.sst = sst
        self.styles = styles
        self.dates = dates
        self.date1904 = date1904
        self.keep_styles = keep_styles

    func shared_string(i):
        if i == null or i < 0 or i >= len(self.sst):
            return ""
        return self.sst[i]

    func style(xf):
        if not self.keep_styles or self.styles == null:
            return null
        return self.styles.style_of(xf)

    func is_date(xf):
        if self.styles == null:
            return false
        return self.styles.is_date_xf(xf)

    func rel_target(rid):
        r := self.pkg.rel(self.part, rid)
        if r == null:
            return null
        return r["target"]

func _si_text(si):
    t := x.first(si, "t")
    runs := x.children(si, "r")
    if len(runs) == 0:
        return x.text(t) if t != null else ""
    out := []
    if t != null:
        append(out, x.text(t))
    for r in runs:
        rt := x.first(r, "t")
        if rt != null:
            append(out, x.text(rt))
    return string.join("", out)

func _shared_strings(pkg, main):
    part := pkg.target(main, core.REL_SHARED_STRINGS)
    out := []
    if part == null or not pkg.has_part(part):
        return out
    root := pkg.read_xml(part)
    for si in x.children(root, "si"):
        append(out, _si_text(si))
    return out

# Décalage du système de dates 1904 (Mac) : 1462 jours.
func _fix_1904(ws):
    for c in ws.cells():
        if u.is_date_dict(c.value):
            s := xc.coerce_number(c.value)
            c.value = u.serial_to_date(to_float(s) + 1462.0)

func _drawing(pkg, sheet_part, ws):
    for r in pkg.rels_of_type(sheet_part, core.REL_DRAWING):
        dpart := pkg.resolve(sheet_part, r["target"])
        if not pkg.has_part(dpart):
            continue
        for item in xi.parse_drawing(pkg.read_xml(dpart)):
            rel := pkg.rel(dpart, item["rid"])
            if rel == null or rel["mode"] == "External":
                continue
            target := pkg.resolve(dpart, rel["target"])
            if not pkg.has_part(target):
                continue
            if item["kind"] == "image":
                try:
                    img := xi.SheetImage(pkg.read_part(target), item["anchor"], item["cx"] if item["cx"] > 0 else null, item["cy"] if item["cy"] > 0 else null, item["description"], item["name"])
                    append(ws.images, img)
                catch e:
                    continue
            else:
                try:
                    ch := xch.parse_chart(pkg.read_xml(target))
                    ch.anchor = item["anchor"]
                    if item["cx"] > 0:
                        ch.width = item["cx"]
                    if item["cy"] > 0:
                        ch.height = item["cy"]
                    append(ws.charts, ch)
                catch e:
                    continue

func read(src, dates=true, styles=true):
    if type(src) == "str" and string.ends_with(string.lower(src), ".xlsb"):
        errors.fail(errors.UNSUPPORTED, "le format binaire .xlsb n'est pas pris en charge (enregistrez en .xlsx)")
    pkg := core.open_package(src)
    main := pkg.main_part()
    ct := pkg.content_type(main)
    if ct != null and not string.contains(ct, "spreadsheetml") and not string.contains(ct, "sheet.macroEnabled"):
        errors.fail(errors.FORMAT, "ce paquet n'est pas un classeur Excel (" + ct + ")")
    wb := pkg.read_xml(main)
    date1904 := false
    pr := x.first(wb, "workbookPr")
    if pr != null:
        date1904 = x.attr_bool(pr, "date1904", false)
    sst := _shared_strings(pkg, main)
    st := null
    sp := pkg.target(main, core.REL_STYLES)
    if sp != null and pkg.has_part(sp):
        st = xs.parse(pkg.read_text(sp))
    active := 0
    bv := x.first_path(wb, "bookViews/workbookView")
    if bv != null:
        active = x.attr_int(bv, "activeTab", 0)
    out_sheets := []
    by_name := {}
    sheets_el := x.first(wb, "sheets")
    if sheets_el != null:
        for s in x.children(sheets_el, "sheet"):
            name := x.attr(s, "name", "Feuille")
            ws := sheets.Worksheet(name)
            ws.state = x.attr(s, "state", "visible")
            rid := x.attr(s, "r:id", null)
            rel := pkg.rel(main, rid) if rid != null else null
            if rel == null:
                append(out_sheets, ws)
                continue
            part := pkg.resolve(main, rel["target"])
            if not pkg.has_part(part):
                append(out_sheets, ws)
                continue
            rctx := _ReadCtx(pkg, part, sst, st, dates, date1904, styles)
            sheets.parse_sheet(ws, pkg.read_xml(part), rctx)
            if date1904 and dates:
                _fix_1904(ws)
            _drawing(pkg, part, ws)
            append(out_sheets, ws)
            by_name[name] = ws
    names := {}
    dn := x.first(wb, "definedNames")
    if dn != null:
        for d in x.children(dn, "definedName"):
            nm := x.attr(d, "name", "")
            if string.starts_with(nm, "_xlnm."):
                continue
            names[nm] = x.text(d)
    return {"sheets": out_sheets, "defined_names": names, "active": active, "date1904": date1904, "metadata": metadata.from_package(pkg), "package": pkg}

func sheet_names(src):
    pkg := core.open_package(src)
    wb := pkg.read_xml(pkg.main_part())
    out := []
    sh := x.first(wb, "sheets")
    if sh != null:
        for s in x.children(sh, "sheet"):
            append(out, x.attr(s, "name", ""))
    return out

func read_rows(src, sheet=null, dates=true):
    parts := read(src, dates, false)
    ss := parts["sheets"]
    if len(ss) == 0:
        return []
    if sheet == null:
        return ss[0].to_rows()
    if type(sheet) == "int":
        if sheet < 0 or sheet >= len(ss):
            raise("IndexError", "feuille " + str(sheet) + " absente (" + str(len(ss)) + " feuilles)")
        return ss[sheet].to_rows()
    for ws in ss:
        if ws.name == sheet:
            return ws.to_rows()
    errors.fail(errors.XLSX, "feuille introuvable : '" + u.to_text(sheet) + "'")
