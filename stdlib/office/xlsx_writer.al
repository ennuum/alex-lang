# ALEX STANDARD LIBRARY — office.xlsx_writer
# Écriture des classeurs Excel (.xlsx) : workbook.xml, feuilles, chaînes partagées, styles, dessins (images et
# graphiques), noms définis, propriétés. Les formules sont écrites avec leur dernière valeur calculée (voir
# excel.Workbook.calculate) et le classeur demande à Excel un recalcul complet à l'ouverture.
#
#   use office.xlsx_writer as writer
#   writer.save(wb, "sortie.xlsx")            # wb : excel.Workbook (ou objet de même forme)
#   octets := writer.to_bytes(wb)
#
# Forme attendue de `wb` : sheets (Worksheet) defined_names (dict) active (indice) metadata (Metadata).
# Fonctions : build_package(wb) -> core.Package   to_bytes(wb)   save(wb, chemin)
#   resolve_ref(wb, "Feuille!$A$1:$A$5") -> valeurs (à plat ; utilisé pour les caches des graphiques)
#   check_sheet_name(nom) (31 caractères, sans : \ / ? * [ ])
# Erreurs : XLSXError (nom de feuille invalide ou dupliqué, classeur vide...), TypeError.

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

func check_sheet_name(name):
    if type(name) != "str" or name == "":
        errors.fail(errors.XLSX, "nom de feuille vide")
    if len(name) > 31:
        errors.fail(errors.XLSX, "nom de feuille trop long (31 caractères au plus) : '" + name + "'")
    for c in [":", "\\", "/", "?", "*", "[", "]"]:
        if string.contains(name, c):
            errors.fail(errors.XLSX, "caractère interdit '" + c + "' dans le nom de feuille '" + name + "'")
    if string.starts_with(name, "'") or string.ends_with(name, "'"):
        errors.fail(errors.XLSX, "un nom de feuille ne peut ni commencer ni finir par une apostrophe")
    return name

class _Strings:
    func init():
        self.index = {}
        self.items = []
        self.count = 0

    func get(text):
        self.count = self.count + 1
        if contains_key(self.index, text):
            return self.index[text]
        k := len(self.items)
        self.index[text] = k
        append(self.items, text)
        return k

    func to_xml():
        kids := []
        for t in self.items:
            attrs := null
            if string.starts_with(t, " ") or string.ends_with(t, " ") or string.contains(t, "\n") or string.contains(t, "  "):
                attrs = {"xml:space": "preserve"}
            append(kids, x.el("si", null, [x.el("t", attrs, [t])]))
        return x.el("sst", {"xmlns": x.NS["x"], "count": str(self.count), "uniqueCount": str(len(self.items))}, kids)

class _SheetCtx:
    func init(pkg, part, strings, styles):
        self.pkg = pkg
        self.part = part
        self.strings = strings
        self.styles = styles
        self._drawing_rid = null

    func sst(text):
        return self.strings.get(text)

    func xf(style):
        return self.styles.xf_index(style)

    func rel(rel_type, target, external=false):
        return self.pkg.add_rel(self.part, rel_type, target, external)

    func drawing_rid():
        return self._drawing_rid

func resolve_ref(wb, ref):
    sp := u.split_sheet_ref(ref)
    target := null
    for ws in wb.sheets:
        if sp[0] == null or ws.name == sp[0]:
            target = ws
            break
    if target == null:
        return []
    p := u.parse_range(sp[1])
    out := []
    r2 := p["r2"] if p["r2"] < xc.MAX_ROW else target.max_row()
    c2 := p["c2"] if p["c2"] < xc.MAX_COL else target.max_col()
    for row in target.rows(true, p["r1"], r2, p["c1"], c2):
        for v in row:
            append(out, v)
    return out

func _media_name(pkg, shared, image):
    key := str(_n.crc32(image.data, 0)) + ":" + str(len(image.data))
    if contains_key(shared, key):
        return shared[key]
    name := pkg.unique_name("xl/media/image", "." + image.ext)
    pkg.write_part(name, image.data, null, false)
    shared[key] = name
    return name

func _write_drawing(pkg, wb, ws, sheet_part, index, media, chart_counter):
    dpart := "xl/drawings/drawing" + str(index) + ".xml"
    anchors := []
    ident := 2
    resolver := (ref) => resolve_ref(wb, ref)
    for img in ws.images:
        mname := _media_name(pkg, media, img.image)
        rid := pkg.add_rel(dpart, core.REL_IMAGE, pkg.relative(dpart, mname))
        nm := img.name if img.name != null else "Image " + str(ident - 1)
        append(anchors, xi.anchor_xml(ws, img.anchor, img.cx, img.cy, xi.picture_xml(ident, nm, img.description, rid, img.cx, img.cy), img.offset_x, img.offset_y))
        ident = ident + 1
    for ch in ws.charts:
        chart_counter[0] = chart_counter[0] + 1
        cpart := "xl/charts/chart" + str(chart_counter[0]) + ".xml"
        pkg.write_xml(cpart, xch.chart_xml(ch, resolver), core.CT_CHART)
        rid := pkg.add_rel(dpart, core.REL_CHART, pkg.relative(dpart, cpart))
        sz := ch.size_emu()
        append(anchors, xi.anchor_xml(ws, ch.anchor, sz[0], sz[1], xi.chart_frame_xml(ident, "Graphique " + str(chart_counter[0]), rid, sz[0], sz[1])))
        ident = ident + 1
    pkg.write_xml(dpart, xi.drawing_xml(anchors), core.CT_DRAWING)
    return pkg.add_rel(sheet_part, core.REL_DRAWING, pkg.relative(sheet_part, dpart))

func build_package(wb):
    if len(wb.sheets) == 0:
        errors.fail(errors.XLSX, "un classeur doit contenir au moins une feuille")
    seen := {}
    for ws in wb.sheets:
        check_sheet_name(ws.name)
        low := string.lower(ws.name)
        if contains_key(seen, low):
            errors.fail(errors.XLSX, "nom de feuille dupliqué : '" + ws.name + "'")
        seen[low] = true
    pkg := core.new_package()
    pkg.set_default("rels", core.CT_RELS)
    pkg.set_default("xml", core.CT_XML)
    main := "xl/workbook.xml"
    pkg.add_rel("", core.REL_OFFICE_DOCUMENT, main)
    strings := _Strings()
    reg := xs.StyleRegistry()
    media := {}
    chart_counter := [0]
    sheet_entries := []
    active := wb.active if wb.active != null and wb.active >= 0 and wb.active < len(wb.sheets) else 0
    i := 0
    drawing_index := 0
    for ws in wb.sheets:
        part := "xl/worksheets/sheet" + str(i + 1) + ".xml"
        ctx := _SheetCtx(pkg, part, strings, reg)
        ws.selected = i == active
        if len(ws.images) > 0 or len(ws.charts) > 0:
            drawing_index = drawing_index + 1
            ctx._drawing_rid = _write_drawing(pkg, wb, ws, part, drawing_index, media, chart_counter)
        pkg.write_xml(part, sheets.sheet_xml(ws, ctx), core.CT_XLSX_SHEET)
        rid := pkg.add_rel(main, core.REL_WORKSHEET, "worksheets/sheet" + str(i + 1) + ".xml")
        attrs := {"name": ws.name, "sheetId": str(i + 1)}
        if ws.state != null and ws.state != "visible":
            attrs["state"] = ws.state
        attrs["r:id"] = rid
        append(sheet_entries, x.el("sheet", attrs))
        i = i + 1
    kids := [x.el("fileVersion", {"appName": "xl", "lastEdited": "7", "lowestEdited": "7", "rupBuild": "27425"}), x.el("workbookPr", {"defaultThemeVersion": "166925"}), x.el("bookViews", null, [x.el("workbookView", {"xWindow": "0", "yWindow": "0", "windowWidth": "28800", "windowHeight": "12300", "activeTab": str(active)})]), x.el("sheets", null, sheet_entries)]
    names := []
    for nm in keys(wb.defined_names):
        append(names, x.el("definedName", {"name": nm}, [xc.normalize_formula(wb.defined_names[nm])]))
    # zones de filtre automatique : nom réservé _xlnm._FilterDatabase (exigé par Excel)
    k := 0
    for ws in wb.sheets:
        if ws.auto_filter != null:
            p := u.parse_range(ws.auto_filter)
            append(names, x.el("definedName", {"name": "_xlnm._FilterDatabase", "localSheetId": str(k), "hidden": "1"}, [u.quote_sheet(ws.name) + "!" + u.range_ref(p["r1"], p["c1"], p["r2"], p["c2"], true)]))
        k = k + 1
    if len(names) > 0:
        append(kids, x.el("definedNames", null, names))
    append(kids, x.el("calcPr", {"calcId": "191029", "fullCalcOnLoad": "1"}))
    pkg.write_xml(main, x.el("workbook", {"xmlns": x.NS["x"], "xmlns:r": x.NS["r"]}, kids), core.CT_XLSX_MAIN)
    pkg.write_xml("xl/styles.xml", reg.to_xml(), core.CT_XLSX_STYLES)
    pkg.add_rel(main, core.REL_STYLES, "styles.xml")
    pkg.write_xml("xl/sharedStrings.xml", strings.to_xml(), core.CT_XLSX_SST)
    pkg.add_rel(main, core.REL_SHARED_STRINGS, "sharedStrings.xml")
    m := wb.metadata
    if m == null:
        m = metadata.new()
    mm := m.copy()
    now := u.now_iso()
    if mm.created == "":
        mm.created = now
    if mm.modified == "":
        mm.modified = now
    if mm.application == "":
        mm.application = metadata.GENERATOR
    metadata.apply_package(pkg, mm)
    return pkg

func to_bytes(wb):
    return build_package(wb).to_bytes()

func save(wb, path):
    build_package(wb).save(path)
    return path
