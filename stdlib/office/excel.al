# ALEX STANDARD LIBRARY — office.excel
# Classeurs Excel (.xlsx) : création, lecture, modification, calcul des formules — façade de haut niveau au-dessus
# de xlsx_reader, xlsx_writer, xlsx_sheets, xlsx_cells, xlsx_styles, xlsx_formulas, xlsx_charts et xlsx_images.
#
#   use office.excel as excel
#   wb := excel.new()
#   ws := wb.active_sheet()                                 # « Feuil1 »
#   ws.append(["Produit", "Qté", "Prix", "Total"], {"bold": true, "fill": "D9E2F3"})
#   ws.append(["Pommes", 3, 1.5, "=B2*C2"])
#   ws.append(["Poires", 10, 2.25, "=B3*C3"])
#   ws.set("D4", "=SUM(D2:D3)", {"bold": true, "number_format": "#,##0.00 €"})
#   ws.add_chart("column", "A1:B3", "F2", "Quantités")
#   ws.freeze("A2")
#   wb.calculate()                                          # évalue les formules (fait aussi par save)
#   print(ws.get("D4"))                                     # 27
#   wb.save("ventes.xlsx")
#
#   wb2 := excel.open("ventes.xlsx")
#   for row in wb2.sheet("Feuil1").to_rows():
#       print(row)
#   excel.read_rows("ventes.xlsx")                          # lignes de la première feuille
#   excel.write_rows("export.xlsx", [["a", "b"], [1, 2]], "Données", true)   # en-tête en gras, filtre, volet figé
#
# CLASSEUR      new(sheet_name="Feuil1")  open(chemin_ou_octets, dates=true)  from_rows(lignes, nom="Feuil1")
#               from_records(dicts, nom="Feuil1", columns=null)  read_rows(chemin, feuille=null)  sheet_names(chemin)
#               write_rows(chemin, lignes, nom="Feuil1", header=true)  write_records(chemin, dicts, nom, columns)
# Workbook      sheets defined_names active metadata
#   add_sheet(nom=null, index=null) -> Worksheet  sheet(nom_ou_indice)  has_sheet(nom)  sheet_names()
#   remove_sheet(nom)  rename_sheet(ancien, nouveau)  copy_sheet(nom, nouveau_nom)  move_sheet(nom, index)
#   active_sheet()  set_active(nom_ou_indice)  get(ref)  set(ref, valeur, style=null)  (ref « Feuille!A1 » ou
#   cellule de la feuille active)  define_name(nom, ref)  calculate() -> nombre de formules évaluées
#   evaluate(formule, feuille=null)  save(chemin, calculate=true)  to_bytes(calculate=true)
# Worksheet, Cell, styles, formules : voir xlsx_sheets, xlsx_cells, xlsx_styles, xlsx_formulas.
# Erreurs : XLSXError, FormatError, FormulaError (formule mal écrite au calcul : la cellule reçoit #NAME?).

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.errors as errors
use office.utils as u
use office.metadata as metadata
use office.xlsx_cells as xc
use office.xlsx_styles as xs
use office.xlsx_sheets as sheets
use office.xlsx_formulas as xf
use office.xlsx_charts as xch
use office.xlsx_reader as reader
use office.xlsx_writer as writer

func Worksheet(name="Feuil1"):
    return sheets.Worksheet(name)

func Chart(kind="column", title=null):
    return xch.Chart(kind, title)

class _Resolver:
    func init(wb, sheet):
        self.wb = wb
        self.sheet = sheet

    func _ws(name):
        if name == null:
            return self.sheet
        for ws in self.wb.sheets:
            if ws.name == name or string.lower(ws.name) == string.lower(name):
                return ws
        return null

    func value(name, r, c):
        ws := self._ws(name)
        if ws == null:
            return xc.ErrorValue("#REF!")
        cell := ws.find_cell(r, c)
        if cell == null:
            return null
        if cell.formula != null:
            return self.wb._eval_cell(ws, cell)
        return cell.value

    func bounds(name):
        ws := self._ws(name)
        if ws == null:
            return [0, 0]
        return [ws.max_row(), ws.max_col()]

    func name(n):
        for k in keys(self.wb.defined_names):
            if string.lower(k) == string.lower(n):
                return self.wb.defined_names[k]
        return null

class Workbook:
    func init(sheet_name="Feuil1"):
        self.sheets = []
        self.defined_names = {}
        self.active = 0
        self.metadata = metadata.new()
        self._state = {}
        if sheet_name != null:
            self.add_sheet(sheet_name)

    # ---------------------------------------------------------- feuilles
    func _unique_name(base):
        name := base
        k := 2
        while self.has_sheet(name):
            name = base + " (" + str(k) + ")"
            k = k + 1
        return name

    func add_sheet(name=null, index=null):
        nm := name
        if nm == null:
            nm = self._unique_name("Feuil" + str(len(self.sheets) + 1))
        writer.check_sheet_name(nm)
        if self.has_sheet(nm):
            errors.fail(errors.XLSX, "une feuille '" + nm + "' existe déjà")
        ws := sheets.Worksheet(nm)
        if index == null:
            append(self.sheets, ws)
        else:
            collections.insert(self.sheets, index, ws)
        return ws

    func has_sheet(name):
        for ws in self.sheets:
            if string.lower(ws.name) == string.lower(name):
                return true
        return false

    func sheet(name_or_index):
        if type(name_or_index) == "int":
            if name_or_index < 0 or name_or_index >= len(self.sheets):
                raise("IndexError", "feuille " + str(name_or_index) + " absente (" + str(len(self.sheets)) + " feuilles)")
            return self.sheets[name_or_index]
        for ws in self.sheets:
            if ws.name == name_or_index:
                return ws
        for ws in self.sheets:
            if string.lower(ws.name) == string.lower(name_or_index):
                return ws
        errors.fail(errors.XLSX, "feuille introuvable : '" + u.to_text(name_or_index) + "'")

    func sheet_names():
        out := []
        for ws in self.sheets:
            append(out, ws.name)
        return out

    func _index_of(name):
        i := 0
        for ws in self.sheets:
            if ws.name == name or string.lower(ws.name) == string.lower(name):
                return i
            i = i + 1
        return -1

    func remove_sheet(name):
        i := self._index_of(name)
        if i < 0:
            errors.fail(errors.XLSX, "feuille introuvable : '" + name + "'")
        collections.pop(self.sheets, i)
        if self.active >= len(self.sheets):
            self.active = len(self.sheets) - 1 if len(self.sheets) > 0 else 0

    func rename_sheet(old, new_name):
        ws := self.sheet(old)
        writer.check_sheet_name(new_name)
        if string.lower(old) != string.lower(new_name) and self.has_sheet(new_name):
            errors.fail(errors.XLSX, "une feuille '" + new_name + "' existe déjà")
        ws.name = new_name
        return ws

    func copy_sheet(name, new_name=null):
        src := self.sheet(name)
        dst := self.add_sheet(new_name if new_name != null else self._unique_name(src.name))
        for c in src.cells():
            nc := dst.cell(c.row, c.col)
            nc.value = u.deep_copy(c.value) if not xc.is_error(c.value) else c.value
            nc.formula = c.formula
            nc.style = u.deep_copy(c.style)
            nc.hyperlink = c.hyperlink
        for m in src.merged:
            append(dst.merged, m)
        for k in keys(src.col_widths):
            dst.col_widths[k] = src.col_widths[k]
        for k in keys(src.row_heights):
            dst.row_heights[k] = src.row_heights[k]
        dst.freeze_cell = src.freeze_cell
        dst.auto_filter = src.auto_filter
        return dst

    func move_sheet(name, index):
        i := self._index_of(name)
        if i < 0:
            errors.fail(errors.XLSX, "feuille introuvable : '" + name + "'")
        ws := collections.pop(self.sheets, i)
        collections.insert(self.sheets, index, ws)

    func active_sheet():
        if len(self.sheets) == 0:
            return self.add_sheet()
        if self.active < 0 or self.active >= len(self.sheets):
            self.active = 0
        return self.sheets[self.active]

    func set_active(name_or_index):
        if type(name_or_index) == "int":
            self.sheet(name_or_index)
            self.active = name_or_index
        else:
            i := self._index_of(name_or_index)
            if i < 0:
                errors.fail(errors.XLSX, "feuille introuvable : '" + name_or_index + "'")
            self.active = i

    # ---------------------------------------------------------- cellules
    func _split(ref):
        sp := u.split_sheet_ref(ref)
        ws := self.active_sheet() if sp[0] == null else self.sheet(sp[0])
        return [ws, sp[1]]

    func get(ref, fallback=null):
        p := self._split(ref)
        return p[0].get(p[1], null, fallback)

    func set(ref, value, style=null):
        p := self._split(ref)
        return p[0].set(p[1], value, style)

    func define_name(name, ref):
        self.defined_names[name] = xc.normalize_formula(ref)

    # ---------------------------------------------------------- calcul
    func _eval_cell(ws, cell):
        k := ws.name + "|" + str(xc.key(cell.row, cell.col))
        if contains_key(self._state, k):
            st := self._state[k]
            if st == "busy":
                return xc.ErrorValue("#REF!")
            return cell.value
        self._state[k] = "busy"
        v := null
        try:
            v = xf.evaluate(cell.formula, _Resolver(self, ws), ws.name)
        catch e:
            if e.type == "FormulaError":
                v = xc.ErrorValue("#NAME?")
            else:
                raise(e)
        if v == null:
            v = 0
        cell.value = v
        self._state[k] = "done"
        return v

    # Évalue toutes les formules (dépendances résolues récursivement ; références circulaires -> #REF!).
    func calculate():
        self._state = {}
        n := 0
        for ws in self.sheets:
            for c in ws.cells():
                if c.formula != null:
                    self._eval_cell(ws, c)
                    n = n + 1
        self._state = {}
        return n

    func evaluate(formula, sheet=null):
        ws := self.active_sheet() if sheet == null else self.sheet(sheet)
        self._state = {}
        v := xf.evaluate(formula, _Resolver(self, ws), ws.name)
        self._state = {}
        return v

    # ---------------------------------------------------------- enregistrement
    func save(path, calculate=true):
        if calculate:
            self.calculate()
        return writer.save(self, path)

    func to_bytes(calculate=true):
        if calculate:
            self.calculate()
        return writer.to_bytes(self)

func new(sheet_name="Feuil1"):
    return Workbook(sheet_name)

func open(src, dates=true):
    parts := reader.read(src, dates, true)
    wb := Workbook(null)
    wb.sheets = parts["sheets"]
    wb.defined_names = parts["defined_names"]
    wb.active = parts["active"]
    wb.metadata = parts["metadata"]
    return wb

func sheet_names(src):
    return reader.sheet_names(src)

func read_rows(src, sheet=null, dates=true):
    return reader.read_rows(src, sheet, dates)

func from_rows(rows, name="Feuil1", header=false):
    wb := Workbook(name)
    ws := wb.sheets[0]
    first := true
    for r in rows:
        ws.append(r, {"bold": true} if header and first else null)
        first = false
    if header and len(rows) > 0:
        ws.freeze("A2")
        ws.set_auto_filter()
    ws.auto_fit_columns()
    return wb

func from_records(records, name="Feuil1", columns=null):
    cols := columns
    if cols == null:
        cols = []
        seen := {}
        for rec in records:
            for k in keys(rec):
                if not contains_key(seen, k):
                    seen[k] = true
                    append(cols, k)
    rows := [cols]
    for rec in records:
        row := []
        for c in cols:
            append(row, u.get(rec, c, null))
        append(rows, row)
    return from_rows(rows, name, true)

func write_rows(path, rows, name="Feuil1", header=true):
    return from_rows(rows, name, header).save(path)

func write_records(path, records, name="Feuil1", columns=null):
    return from_records(records, name, columns).save(path)
