# ALEX STANDARD LIBRARY — office.xlsx_sheets
# Feuilles de calcul : cellules (creuses), lignes, plages, fusions, largeurs de colonnes, hauteurs de lignes,
# volets figés, filtre automatique, liens, mise en page ; sérialisation et lecture de xl/worksheets/sheetN.xml.
#
#   use office.xlsx_sheets as sheets
#   ws := sheets.Worksheet("Ventes")
#   ws.append(["Produit", "Qté", "Prix"])
#   ws.append(["Pommes", 3, 1.5])
#   ws.set("D2", "=B2*C2")                                  # une chaîne commençant par « = » est une formule
#   ws.set("A1", "Produit", {"bold": true})
#   ws.merge("A10:C10")
#   ws.set_column_width("A", 20)
#   ws.freeze("A2")                                          # fige la première ligne
#   ws.get("B2")                                             # 3
#   ws.to_rows()                                             # [["Produit", "Qté", "Prix", null], ...]
#
# Worksheet(name) : name state ("visible" | "hidden" | "veryHidden") tab_color merged col_widths row_heights
#   hidden_cols hidden_rows freeze_cell auto_filter images charts print (dict : orientation "portrait" |
#   "landscape", fit_width, fit_height, paper "A4" | "letter", margins) show_grid
# CELLULES  cell(ref_ou_ligne, col=null) -> Cell (créée au besoin)  find_cell(ref) -> Cell ou null
#   get(ref, défaut=null) -> valeur   set(ref, valeur, style=null) -> Cell   set_formula(ref, f, style=null)
#   set_style(plage, style, merge=true)   clear(plage)   delete_cell(ref)
# LIGNES    append(valeurs, style=null) -> numéro de ligne   write_rows(lignes, start="A1", style=null)
#   rows(values_only=true, min_row=1, max_row=null, min_col=1, max_col=null) -> listes   to_rows()
#   column_values(col, skip_header=false)   range_values("A1:C3") -> lignes   max_row()  max_col()
#   dimension() -> "A1:D20"   cells() -> Cell triées (ligne puis colonne)   is_empty()
#   insert_rows(index, n=1)   delete_rows(index, n=1)  (les formules ne sont pas réécrites)
# DESSIN    add_image(image, anchor="A1", width=null, height=null, description="") -> xlsx_images.SheetImage
#   add_chart(kind, plage_données, anchor="E2", title=null, header=true) -> xlsx_charts.Chart   insert_chart(chart)
# MISE EN FORME  merge(plage)  unmerge(plage)  set_column_width(col, largeur)  set_row_height(ligne, h)
#   auto_fit_columns(min_width=6, max_width=60)  freeze(ref)  set_auto_filter(plage=null)  hide_column(col)
#   hide_row(ligne)  add_hyperlink(ref, url, texte=null)   add_comment(ref, texte)
#   find(valeur) -> [refs]  replace(ancien, nouveau) -> nombre (textes)
# XML       sheet_xml(ws, ctx) -> nœud worksheet   parse_sheet(ws, nœud, rctx)
#   ctx : ctx.sst(texte) -> indice ; ctx.xf(style) -> indice ; ctx.rel(type, cible, externe) -> rId
#   rctx : rctx.shared_string(i) ; rctx.style(xf) ; rctx.is_date(xf) ; rctx.rel_target(rid) ; rctx.dates (bool)
# Erreurs : XLSXError, ValueError (référence invalide), IndexError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.xlsx_cells as xc
use office.xlsx_styles as xs
use office.xlsx_formulas as xf
use office.xlsx_images as xi
use office.xlsx_charts as xch

# Les fonctions TEXT / FIXED des formules utilisent le formateur de nombres des styles.
xf.set_formatter(xs.format_value)

func _col_num(c):
    if type(c) == "int":
        return c
    return u.column_index(c)

class Worksheet:
    func init(name="Feuil1"):
        self.name = name
        self.state = "visible"
        self.tab_color = null
        self._cells = {}
        self._max_row = 0
        self._max_col = 0
        self.merged = []
        self.col_widths = {}
        self.row_heights = {}
        self.hidden_cols = {}
        self.hidden_rows = {}
        self.freeze_cell = null
        self.auto_filter = null
        self.images = []
        self.charts = []
        self.print = {}
        self.show_grid = true
        self.selected = false

    # ---------------------------------------------------------- cellules
    func _rc(ref_or_row, col):
        if col != null:
            r := ref_or_row
            c := _col_num(col)
            if type(r) != "int" or r < 1 or r > xc.MAX_ROW or c < 1 or c > xc.MAX_COL:
                raise("ValueError", "cellule hors limites : ligne " + u.to_text(r) + ", colonne " + u.to_text(col))
            return [r, c]
        p := u.parse_cell(ref_or_row)
        if p["row"] == null or p["col"] == null:
            raise("ValueError", "référence de cellule complète attendue : '" + u.to_text(ref_or_row) + "'")
        return [p["row"], p["col"]]

    func cell(ref_or_row, col=null):
        rc := self._rc(ref_or_row, col)
        k := xc.key(rc[0], rc[1])
        if contains_key(self._cells, k):
            return self._cells[k]
        c := xc.Cell(rc[0], rc[1])
        self._cells[k] = c
        if rc[0] > self._max_row:
            self._max_row = rc[0]
        if rc[1] > self._max_col:
            self._max_col = rc[1]
        return c

    func find_cell(ref_or_row, col=null):
        rc := self._rc(ref_or_row, col)
        k := xc.key(rc[0], rc[1])
        if contains_key(self._cells, k):
            return self._cells[k]
        return null

    func get(ref_or_row, col=null, fallback=null):
        c := self.find_cell(ref_or_row, col)
        if c == null or c.value == null:
            return fallback
        return c.value

    func _assign(c, value, style):
        if type(value) == "str" and string.starts_with(value, "=") and len(value) > 1:
            c.formula = xc.normalize_formula(value)
            c.value = null
        else:
            if type(value) == "str" and len(value) > 32767:
                errors.fail(errors.XLSX, "texte de plus de 32 767 caractères dans " + c.ref())
            c.value = value
            c.formula = null
        if style != null:
            c.style = style

    # set(ref, valeur, style) ou set(ligne, colonne, valeur, style) — distingués par le type du premier argument.
    func set(ref, value=null, style=null, extra=null):
        if type(ref) == "int":
            c := self.cell(ref, value)
            self._assign(c, style, extra)
            return c
        c := self.cell(ref)
        self._assign(c, value, style)
        return c

    func set_formula(ref, formula, style=null):
        c := self.cell(ref)
        c.formula = xc.normalize_formula(formula)
        c.value = null
        if style != null:
            c.style = style
        return c

    func delete_cell(ref):
        rc := self._rc(ref, null)
        k := xc.key(rc[0], rc[1])
        if contains_key(self._cells, k):
            collections.remove(self._cells, k)

    func set_style(rng, style, merge_with_existing=true):
        p := u.parse_range(rng)
        r := p["r1"]
        while r <= p["r2"]:
            c := p["c1"]
            while c <= p["c2"]:
                cl := self.cell(r, c)
                if merge_with_existing and cl.style != null:
                    cl.style = u.merge(cl.style, style)
                else:
                    cl.style = style
                c = c + 1
            r = r + 1

    func clear(rng):
        p := u.parse_range(rng)
        for k in keys(self._cells):
            c := self._cells[k]
            if c.row >= p["r1"] and c.row <= p["r2"] and c.col >= p["c1"] and c.col <= p["c2"]:
                c.value = null
                c.formula = null

    # ---------------------------------------------------------- lignes
    func max_row():
        return self._max_row

    func max_col():
        return self._max_col

    func is_empty():
        for k in keys(self._cells):
            if not self._cells[k].is_empty():
                return false
        return true

    func dimension():
        if self._max_row == 0:
            return "A1"
        min_r := self._max_row
        min_c := self._max_col
        for k in keys(self._cells):
            c := self._cells[k]
            if c.row < min_r:
                min_r = c.row
            if c.col < min_c:
                min_c = c.col
        return u.range_ref(min_r, min_c, self._max_row, self._max_col)

    func append(values, style=null):
        r := self._max_row + 1
        c := 1
        for v in values:
            if v != null or style != null:
                cl := self.cell(r, c)
                self._assign(cl, v, style)
            c = c + 1
        if self._max_row < r:
            self._max_row = r
        return r

    func write_rows(rows, start="A1", style=null):
        p := u.parse_cell(start)
        r := p["row"]
        for row in rows:
            c := p["col"]
            for v in row:
                if v != null or style != null:
                    self._assign(self.cell(r, c), v, style)
                c = c + 1
            r = r + 1
        return r - 1

    func cells():
        ks := u.sort(keys(self._cells))
        out := []
        for k in ks:
            append(out, self._cells[k])
        return out

    func rows(values_only=true, min_row=1, max_row=null, min_col=1, max_col=null):
        r2 := max_row if max_row != null else self._max_row
        c2 := max_col if max_col != null else self._max_col
        out := []
        r := min_row
        while r <= r2:
            line := []
            c := min_col
            while c <= c2:
                k := xc.key(r, c)
                cl := self._cells[k] if contains_key(self._cells, k) else null
                if values_only:
                    append(line, cl.value if cl != null else null)
                else:
                    append(line, cl)
                c = c + 1
            append(out, line)
            r = r + 1
        return out

    func to_rows():
        return self.rows(true)

    func range_values(rng):
        p := u.parse_range(rng)
        return self.rows(true, p["r1"], p["r2"] if p["r2"] < xc.MAX_ROW else self._max_row, p["c1"], p["c2"] if p["c2"] < xc.MAX_COL else self._max_col)

    func column_values(col, skip_header=false):
        c := _col_num(col)
        out := []
        r := 2 if skip_header else 1
        while r <= self._max_row:
            k := xc.key(r, c)
            append(out, self._cells[k].value if contains_key(self._cells, k) else null)
            r = r + 1
        return out

    func _shift_rows(index, delta):
        moved := {}
        for k in keys(self._cells):
            c := self._cells[k]
            if c.row >= index:
                c.row = c.row + delta
            if c.row >= 1:
                moved[xc.key(c.row, c.col)] = c
        self._cells = moved
        self._max_row = 0
        for k in keys(self._cells):
            if self._cells[k].row > self._max_row:
                self._max_row = self._cells[k].row

    func insert_rows(index, n=1):
        self._shift_rows(index, n)

    func delete_rows(index, n=1):
        keep := {}
        for k in keys(self._cells):
            c := self._cells[k]
            if c.row < index or c.row >= index + n:
                keep[k] = c
        self._cells = keep
        self._shift_rows(index + n, -n)

    # ---------------------------------------------------------- mise en forme
    func merge(rng):
        p := u.parse_range(rng)
        ref := u.range_ref(p["r1"], p["c1"], p["r2"], p["c2"])
        for m in self.merged:
            if m == ref:
                return ref
        append(self.merged, ref)
        return ref

    func unmerge(rng):
        p := u.parse_range(rng)
        ref := u.range_ref(p["r1"], p["c1"], p["r2"], p["c2"])
        out := []
        for m in self.merged:
            if m != ref:
                append(out, m)
        self.merged = out

    func set_column_width(col, width):
        self.col_widths[_col_num(col)] = to_float(width)

    func set_row_height(row, height):
        self.row_heights[row] = to_float(height)

    func hide_column(col):
        self.hidden_cols[_col_num(col)] = true

    func hide_row(row):
        self.hidden_rows[row] = true

    # Largeur estimée d'après le texte affiché (≈ nombre de caractères + marge).
    func auto_fit_columns(min_width=6, max_width=60):
        widths := {}
        for k in keys(self._cells):
            c := self._cells[k]
            if c.value == null:
                continue
            t := c.display()
            longest := 0
            for line in string.split(t, "\n"):
                if len(line) > longest:
                    longest = len(line)
            w := to_float(longest) * 1.1 + 2.0
            if c.style != null and u.get(c.style, "bold", false) == true:
                w = w * 1.1
            if not contains_key(widths, c.col) or widths[c.col] < w:
                widths[c.col] = w
        for col in keys(widths):
            w := widths[col]
            if w < min_width:
                w = to_float(min_width)
            if w > max_width:
                w = to_float(max_width)
            self.col_widths[col] = u.round_to(w, 2)

    func freeze(ref):
        self.freeze_cell = ref
        return self

    func set_auto_filter(rng=null):
        self.auto_filter = rng if rng != null else self.dimension()
        return self

    func add_hyperlink(ref, url, text=null):
        c := self.cell(ref)
        c.hyperlink = url
        if text != null:
            c.value = text
        elif c.value == null:
            c.value = url
        if c.style == null:
            c.style = {"color": "0563C1", "underline": true}
        return c

    # ---------------------------------------------------------- images et graphiques
    func add_image(image, anchor="A1", width=null, height=null, description=""):
        img := xi.SheetImage(image, anchor, width, height, description)
        append(self.images, img)
        return img

    func insert_chart(chart):
        append(self.charts, chart)
        return chart

    # Graphique à partir d'une plage de données : première colonne = catégories, première ligne = noms des séries
    # (header), une série par colonne suivante. kind : column bar line area pie doughnut scatter.
    func add_chart(kind, data_range, anchor="E2", title=null, header=true):
        p := u.parse_range(data_range)
        q := u.quote_sheet(self.name) + "!"
        ch := xch.Chart(kind, title)
        ch.anchor = anchor
        first := p["r1"] + 1 if header else p["r1"]
        if p["c2"] == p["c1"]:
            ch.add_series(q + u.range_ref(first, p["c1"], p["r2"], p["c1"], true), null, q + u.cell_ref(p["r1"], p["c1"], true, true) if header else null)
        else:
            cats := q + u.range_ref(first, p["c1"], p["r2"], p["c1"], true)
            c := p["c1"] + 1
            while c <= p["c2"]:
                ch.add_series(q + u.range_ref(first, c, p["r2"], c, true), cats, q + u.cell_ref(p["r1"], c, true, true) if header else null)
                c = c + 1
        append(self.charts, ch)
        return ch

    func add_comment(ref, text):
        self.cell(ref).comment = text

    func find(value):
        out := []
        for c in self.cells():
            if c.value == value:
                append(out, c.ref())
        return out

    func replace(old, new_text):
        n := 0
        for k in keys(self._cells):
            c := self._cells[k]
            if type(c.value) == "str" and string.contains(c.value, old):
                n = n + string.count(c.value, old)
                c.value = string.replace(c.value, old, new_text)
        return n

# ---------------------------------------------------------------------------------------------- écriture

func _date_style(cell):
    v := cell.value
    st := cell.style
    if st != null and u.get(st, "number_format", null) != null:
        return st
    has_time := u.get(v, "hour", 0) != 0 or u.get(v, "minute", 0) != 0 or u.get(v, "second", 0) != 0
    return u.merge(st, {"number_format": "yyyy-mm-dd hh:mm:ss" if has_time else "yyyy-mm-dd"})

func _cell_xml(c, ctx):
    attrs := {"r": c.ref()}
    st := c.style
    v := c.value
    kind := xc.value_kind(v)
    if kind == "date":
        st = _date_style(c)
    s := ctx.xf(st)
    if s != 0:
        attrs["s"] = str(s)
    kids := []
    if c.formula != null:
        if c.array_ref != null:
            append(kids, x.el("f", {"t": "array", "ref": c.array_ref}, [c.formula]))
        else:
            append(kids, x.el("f", null, [c.formula]))
        if kind == "number":
            append(kids, x.el("v", null, [u.format_number(v)]))
        elif kind == "date":
            append(kids, x.el("v", null, [u.format_number(xc.coerce_number(v))]))
        elif kind == "text":
            attrs["t"] = "str"
            append(kids, x.el("v", null, [v]))
        elif kind == "bool":
            attrs["t"] = "b"
            append(kids, x.el("v", null, ["1" if v else "0"]))
        elif kind == "error":
            attrs["t"] = "e"
            append(kids, x.el("v", null, [v.code]))
        return x.el("c", attrs, kids)
    if kind == "null":
        return x.el("c", attrs)
    if kind == "number":
        append(kids, x.el("v", null, [u.format_number(v)]))
    elif kind == "date":
        append(kids, x.el("v", null, [u.format_number(xc.coerce_number(v))]))
    elif kind == "text":
        attrs["t"] = "s"
        append(kids, x.el("v", null, [str(ctx.sst(v))]))
    elif kind == "bool":
        attrs["t"] = "b"
        append(kids, x.el("v", null, ["1" if v else "0"]))
    elif kind == "error":
        attrs["t"] = "e"
        append(kids, x.el("v", null, [v.code]))
    return x.el("c", attrs, kids)

func _cols_xml(ws):
    cols := u.sort(_merge_keys(ws.col_widths, ws.hidden_cols))
    if len(cols) == 0:
        return null
    kids := []
    for c in cols:
        a := {"min": str(c), "max": str(c)}
        if contains_key(ws.col_widths, c):
            a["width"] = u.format_number(ws.col_widths[c])
            a["customWidth"] = "1"
        else:
            a["width"] = "8.43"
        if contains_key(ws.hidden_cols, c):
            a["hidden"] = "1"
        append(kids, x.el("col", a))
    return x.el("cols", null, kids)

func _merge_keys(a, b):
    out := []
    for k in keys(a):
        append(out, k)
    for k in keys(b):
        if not contains_key(a, k):
            append(out, k)
    return out

func sheet_xml(ws, ctx):
    kids := []
    pr := []
    if ws.tab_color != null:
        append(pr, x.el("tabColor", {"rgb": "FF" + u.color_hex(ws.tab_color)}))
    pf := u.get(ws.print, "fit_width", null)
    if pf != null or u.get(ws.print, "fit_height", null) != null:
        append(pr, x.el("pageSetUpPr", {"fitToPage": "1"}))
    if len(pr) > 0:
        append(kids, x.el("sheetPr", null, pr))
    append(kids, x.el("dimension", {"ref": ws.dimension()}))
    view := {"workbookViewId": "0"}
    if ws.selected:
        view["tabSelected"] = "1"
    if not ws.show_grid:
        view["showGridLines"] = "0"
    vk := []
    if ws.freeze_cell != null:
        p := u.parse_cell(ws.freeze_cell)
        xs_ := p["col"] - 1
        ys := p["row"] - 1
        if xs_ > 0 or ys > 0:
            pa := {"topLeftCell": u.cell_ref(p["row"], p["col"]), "state": "frozen"}
            if xs_ > 0:
                pa["xSplit"] = str(xs_)
            if ys > 0:
                pa["ySplit"] = str(ys)
            pane := "bottomRight" if xs_ > 0 and ys > 0 else ("topRight" if xs_ > 0 else "bottomLeft")
            pa["activePane"] = pane
            append(vk, x.el("pane", pa))
            append(vk, x.el("selection", {"pane": pane, "activeCell": u.cell_ref(p["row"], p["col"]), "sqref": u.cell_ref(p["row"], p["col"])}))
    append(kids, x.el("sheetViews", null, [x.el("sheetView", view, vk)]))
    append(kids, x.el("sheetFormatPr", {"defaultRowHeight": "15"}))
    cols := _cols_xml(ws)
    if cols != null:
        append(kids, cols)
    # données : cellules groupées par ligne
    by_row := {}
    for k in keys(ws._cells):
        c := ws._cells[k]
        if c.is_empty() and c.style == null:
            continue
        if not contains_key(by_row, c.row):
            by_row[c.row] = []
        append(by_row[c.row], c)
    for r in keys(ws.row_heights):
        if not contains_key(by_row, r):
            by_row[r] = []
    for r in keys(ws.hidden_rows):
        if not contains_key(by_row, r):
            by_row[r] = []
    rows := []
    links := []
    for r in u.sort(keys(by_row)):
        cells := u.sort(by_row[r], (c) => c.col)
        ck := []
        for c in cells:
            append(ck, _cell_xml(c, ctx))
            if c.hyperlink != null:
                append(links, c)
        ra := {"r": str(r)}
        if contains_key(ws.row_heights, r):
            ra["ht"] = u.format_number(ws.row_heights[r])
            ra["customHeight"] = "1"
        if contains_key(ws.hidden_rows, r):
            ra["hidden"] = "1"
        append(rows, x.el("row", ra, ck))
    append(kids, x.el("sheetData", null, rows))
    if ws.auto_filter != null:
        append(kids, x.el("autoFilter", {"ref": ws.auto_filter}))
    if len(ws.merged) > 0:
        mk := []
        for m in ws.merged:
            append(mk, x.el("mergeCell", {"ref": m}))
        append(kids, x.el("mergeCells", {"count": str(len(mk))}, mk))
    if len(links) > 0:
        lk := []
        for c in links:
            if string.starts_with(c.hyperlink, "#"):
                append(lk, x.el("hyperlink", {"ref": c.ref(), "location": _n.str_slice(c.hyperlink, 1, null), "display": u.to_text(c.value)}))
            else:
                rid := ctx.rel("http://schemas.openxmlformats.org/officeDocument/2006/relationships/hyperlink", c.hyperlink, true)
                append(lk, x.el("hyperlink", {"ref": c.ref(), "r:id": rid}))
        append(kids, x.el("hyperlinks", null, lk))
    append(kids, x.el("pageMargins", {"left": "0.7", "right": "0.7", "top": "0.75", "bottom": "0.75", "header": "0.3", "footer": "0.3"}))
    ps := {}
    paper := string.lower(u.to_text(u.get(ws.print, "paper", "")))
    if paper == "a4":
        ps["paperSize"] = "9"
    elif paper == "letter":
        ps["paperSize"] = "1"
    elif paper == "a3":
        ps["paperSize"] = "8"
    if u.get(ws.print, "orientation", null) != null:
        ps["orientation"] = ws.print["orientation"]
    if pf != null:
        ps["fitToWidth"] = str(pf)
    if u.get(ws.print, "fit_height", null) != null:
        ps["fitToHeight"] = str(ws.print["fit_height"])
    if len(keys(ps)) > 0:
        append(kids, x.el("pageSetup", ps))
    d := ctx.drawing_rid()
    if d != null:
        append(kids, x.el("drawing", {"r:id": d}))
    return x.el("worksheet", {"xmlns": x.NS["x"], "xmlns:r": x.NS["r"]}, kids)

# ---------------------------------------------------------------------------------------------- lecture

func _inline_text(is_el):
    out := []
    for t in x.find_all(is_el, "t"):
        # textes phonétiques (rPh) exclus
        append(out, x.text(t))
    if len(out) == 0:
        return ""
    # retire les doublons dus aux runs phonétiques
    rph := x.find_all(is_el, "rPh")
    if len(rph) == 0:
        return string.join("", out)
    keep := []
    for r in x.children(is_el):
        ln := x.local_name(r["tag"])
        if ln == "t":
            append(keep, x.text(r))
        elif ln == "r":
            t := x.first(r, "t")
            if t != null:
                append(keep, x.text(t))
    return string.join("", keep)

func parse_sheet(ws, root, rctx):
    shared_formulas := {}
    data := x.first(root, "sheetData")
    pending_shared := []
    if data != null:
        row_num := 0
        for row in x.children(data, "row"):
            rr := x.attr_int(row, "r", null)
            row_num = rr if rr != null else row_num + 1
            if x.attr_bool(row, "customHeight", false) or x.has_attr(row, "ht"):
                ht := x.attr_float(row, "ht", null)
                if ht != null and x.attr_bool(row, "customHeight", false):
                    ws.row_heights[row_num] = ht
            if x.attr_bool(row, "hidden", false):
                ws.hidden_rows[row_num] = true
            col_num := 0
            for c in x.children(row, "c"):
                ref := x.attr(c, "r", null)
                r := row_num
                col := col_num + 1
                if ref != null:
                    p := u.parse_cell(ref)
                    r = p["row"]
                    col = p["col"]
                col_num = col
                t := x.attr(c, "t", "n")
                s := x.attr_int(c, "s", 0)
                vel := x.first(c, "v")
                fel := x.first(c, "f")
                raw := x.text(vel) if vel != null else null
                value := null
                if t == "s":
                    if raw != null:
                        value = rctx.shared_string(to_int(_n.num_parse(raw)))
                elif t == "inlineStr":
                    ise := x.first(c, "is")
                    value = _inline_text(ise) if ise != null else ""
                elif t == "str":
                    value = raw if raw != null else ""
                elif t == "b":
                    value = raw == "1" or raw == "true"
                elif t == "e":
                    value = xc.ErrorValue(raw) if raw != null else null
                elif t == "d":
                    value = u.date_parts(raw) if raw != null else null
                else:
                    if raw != null and raw != "":
                        value = _n.num_parse(raw)
                        if value != null and rctx.dates and rctx.is_date(s):
                            try:
                                value = u.serial_to_date(value)
                            catch e:
                                value = value
                style := rctx.style(s)
                if value == null and fel == null and style == null:
                    continue
                cell := ws.cell(r, col)
                cell.value = value
                cell.style = style
                if fel != null:
                    ftext := x.text(fel)
                    ft := x.attr(fel, "t", "normal")
                    if ft == "shared":
                        si := x.attr(fel, "si", "")
                        if ftext != "":
                            shared_formulas[si] = [ftext, r, col]
                            cell.formula = ftext
                        else:
                            append(pending_shared, [cell, si])
                    elif ftext != "":
                        cell.formula = ftext
                        if ft == "array":
                            cell.array_ref = x.attr(fel, "ref", null)
    for item in pending_shared:
        cell := item[0]
        si := item[1]
        if contains_key(shared_formulas, si):
            m := shared_formulas[si]
            try:
                cell.formula = xf.shift_formula(m[0], cell.row - m[1], cell.col - m[2])
            catch e:
                cell.formula = null
    cols := x.first(root, "cols")
    if cols != null:
        for c in x.children(cols, "col"):
            lo := x.attr_int(c, "min", 1)
            hi := x.attr_int(c, "max", lo)
            if hi - lo > 256:
                hi = lo
            k := lo
            while k <= hi:
                if x.attr_bool(c, "customWidth", false) or x.has_attr(c, "width"):
                    w := x.attr_float(c, "width", null)
                    if w != null:
                        ws.col_widths[k] = w
                if x.attr_bool(c, "hidden", false):
                    ws.hidden_cols[k] = true
                k = k + 1
    mc := x.first(root, "mergeCells")
    if mc != null:
        for m in x.children(mc, "mergeCell"):
            append(ws.merged, x.attr(m, "ref", ""))
    af := x.first(root, "autoFilter")
    if af != null:
        ws.auto_filter = x.attr(af, "ref", null)
    sv := x.first_path(root, "sheetViews/sheetView")
    if sv != null:
        ws.show_grid = x.attr_bool(sv, "showGridLines", true)
        ws.selected = x.attr_bool(sv, "tabSelected", false)
        pane := x.first(sv, "pane")
        if pane != null and x.attr(pane, "state", "") == "frozen":
            ws.freeze_cell = x.attr(pane, "topLeftCell", null)
            if ws.freeze_cell == null:
                ws.freeze_cell = u.cell_ref(x.attr_int(pane, "ySplit", 0) + 1, x.attr_int(pane, "xSplit", 0) + 1)
    spr := x.first(root, "sheetPr")
    if spr != null:
        tc := x.first(spr, "tabColor")
        if tc != null and x.attr(tc, "rgb", null) != null:
            rgb := x.attr(tc, "rgb", "")
            ws.tab_color = _n.str_slice(rgb, len(rgb) - 6, null)
    hl := x.first(root, "hyperlinks")
    if hl != null:
        for h in x.children(hl, "hyperlink"):
            ref := x.attr(h, "ref", null)
            if ref == null:
                continue
            target := null
            rid := x.attr(h, "r:id", null)
            if rid != null:
                target = rctx.rel_target(rid)
            elif x.attr(h, "location", null) != null:
                target = "#" + x.attr(h, "location", "")
            if target != null:
                first_ref := string.split(ref, ":")[0]
                ws.cell(first_ref).hyperlink = target
    ps := x.first(root, "pageSetup")
    if ps != null:
        if x.attr(ps, "orientation", null) != null:
            ws.print["orientation"] = x.attr(ps, "orientation")
        pz := x.attr(ps, "paperSize", null)
        if pz == "9":
            ws.print["paper"] = "A4"
        elif pz == "1":
            ws.print["paper"] = "letter"
    return ws
