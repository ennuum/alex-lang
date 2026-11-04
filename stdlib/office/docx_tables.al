# ALEX STANDARD LIBRARY — office.docx_tables
# Tableaux WordprocessingML : grille de cellules, fusions horizontales et verticales, largeurs, bordures, trames,
# alignement vertical, ligne d'en-tête répétée, tableaux imbriqués.
#
#   use office.docx_tables as dt
#   t := dt.from_rows([["Produit", "Qté"], ["Pommes", 3], ["Poires", 10]], header=true)
#   t.cell(0, 0).shading = "D9E2F3"
#   t.merge(1, 0, 2, 0)                              # fusion verticale de deux cellules
#   t.widths = ["6cm", "3cm"]
#   t.align = "center"
#
# Cell : paragraphs (Paragraph ou Table imbriquée) width shading valign ("top" | "center" | "bottom") borders
#   (null : style du tableau ; true ; false ; ou couleur) col_span row_span merged (couverte par une fusion)
#   text()  set_text(texte, bold=null, italic=null, align=null, color=null, size=null)  add_paragraph(texte="", style=null)
#   add_table(table)  paragraph() (premier paragraphe)
# Row : cells height (pt) exact_height header (répétée en haut de chaque page) cant_split
# Table(rows=0, cols=0, style="TableGrid") : rows widths (liste de longueurs) width (longueur ou "100%") align
#   borders (null / true / false / couleur) style header_rows autofit
#   cell(r, c)  row(r)  add_row(valeurs=null) -> Row  add_column(valeurs=null, width=null)  row_count()  col_count()
#   merge(r1, c1, r2, c2) -> Cell (cellule d'origine)  data() -> lignes de textes  set_col_width(c, w)
#   style_header(bold=true, shading=null, color=null)  to_xml(ctx, largeur_utile_twips)
# Fonctions : from_rows(lignes, header=true, style="TableGrid", header_bold=true, header_shading=null)
#   parse_table(nœud_w:tbl, rctx) -> Table
# Erreurs : DOCXError, IndexError, ValueError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.errors as errors
use office.utils as u
use office.xml as x
use office.docx_styles as styles
use office.docx_paragraphs as dp

func _twips(v):
    return to_int(u.round_to(u.to_unit(u.length(v, "pt"), "tw"), 0))

class Cell:
    func init(text=null):
        self.paragraphs = [dp.Paragraph()]
        self.width = null
        self.shading = null
        self.valign = null
        self.borders = null
        self.col_span = 1
        self.row_span = 1
        self.merged = false
        self.margin = null
        if text != null:
            self.set_text(text)

    func copy():
        c := Cell()
        c.paragraphs = []
        for p in self.paragraphs:
            append(c.paragraphs, p.copy())
        c.width = self.width
        c.shading = self.shading
        c.valign = self.valign
        c.borders = u.deep_copy(self.borders)
        c.col_span = self.col_span
        c.row_span = self.row_span
        c.merged = self.merged
        c.margin = self.margin
        return c

    func paragraph():
        for p in self.paragraphs:
            if isinstance(p, dp.Paragraph):
                return p
        p := dp.Paragraph()
        append(self.paragraphs, p)
        return p

    func text():
        out := []
        for p in self.paragraphs:
            if isinstance(p, dp.Paragraph):
                append(out, p.text())
            else:
                append(out, p.text())
        return string.join("\n", out)

    func set_text(value, bold=null, italic=null, align=null, color=null, size=null):
        lines := string.split(u.to_text(value), "\n")
        self.paragraphs = []
        for line in lines:
            p := dp.Paragraph()
            if line != "":
                p.add_run(line, bold, italic, null, null, size, color)
            p.align = align
            append(self.paragraphs, p)
        return self

    func add_paragraph(text="", style=null):
        p := dp.Paragraph(text, style)
        if len(self.paragraphs) == 1 and isinstance(self.paragraphs[0], dp.Paragraph) and self.paragraphs[0].is_empty() and self.paragraphs[0].style == null:
            self.paragraphs = [p]
        else:
            append(self.paragraphs, p)
        return p

    func add_table(table):
        append(self.paragraphs, table)
        # une cellule doit se terminer par un paragraphe
        append(self.paragraphs, dp.Paragraph())
        return table

class Row:
    func copy():
        cells := []
        for c in self.cells:
            append(cells, c.copy())
        r := Row(cells)
        r.height = self.height
        r.exact_height = self.exact_height
        r.header = self.header
        r.cant_split = self.cant_split
        return r

    func init(cells=null):
        self.cells = cells if cells != null else []
        self.height = null
        self.exact_height = false
        self.header = false
        self.cant_split = null

class Table:
    func init(rows=0, cols=0, style="TableGrid"):
        self.rows = []
        self.widths = null
        self.width = null
        self.align = null
        self.borders = null
        self.style = style
        self.autofit = true
        self.indent = null
        r := 0
        while r < rows:
            cells := []
            c := 0
            while c < cols:
                append(cells, Cell())
                c = c + 1
            append(self.rows, Row(cells))
            r = r + 1

    func copy():
        t := Table(0, 0, self.style)
        for r in self.rows:
            append(t.rows, r.copy())
        t.widths = u.deep_copy(self.widths)
        t.width = self.width
        t.align = self.align
        t.borders = u.deep_copy(self.borders)
        t.autofit = self.autofit
        t.indent = self.indent
        return t

    func row_count():
        return len(self.rows)

    func col_count():
        n := 0
        for r in self.rows:
            if len(r.cells) > n:
                n = len(r.cells)
        return n

    func row(r):
        if r < 0 or r >= len(self.rows):
            raise("IndexError", "ligne " + str(r) + " hors du tableau (" + str(len(self.rows)) + " lignes)")
        return self.rows[r]

    func cell(r, c):
        row := self.row(r)
        if c < 0 or c >= len(row.cells):
            raise("IndexError", "colonne " + str(c) + " hors du tableau (" + str(len(row.cells)) + " colonnes)")
        return row.cells[c]

    func add_row(values=null):
        cols := self.col_count()
        cells := []
        if values != null:
            for v in values:
                append(cells, Cell(v))
        while len(cells) < cols:
            append(cells, Cell())
        row := Row(cells)
        append(self.rows, row)
        return row

    func add_column(values=null, width=null):
        i := 0
        for row in self.rows:
            v := null
            if values != null and i < len(values):
                v = values[i]
            append(row.cells, Cell(v))
            i = i + 1
        if self.widths != null:
            append(self.widths, width)

    func set_col_width(c, w):
        n := self.col_count()
        if self.widths == null:
            self.widths = u.repeat(null, n)
        while len(self.widths) < n:
            append(self.widths, null)
        self.widths[c] = w

    func merge(r1, c1, r2, c2):
        if r2 < r1 or c2 < c1:
            raise("ValueError", "merge : coin inférieur droit avant le coin supérieur gauche")
        origin := self.cell(r1, c1)
        self.cell(r2, c2)
        texts := []
        r := r1
        while r <= r2:
            c := c1
            while c <= c2:
                cl := self.cell(r, c)
                if not (r == r1 and c == c1):
                    t := cl.text()
                    if t != "":
                        append(texts, t)
                    cl.merged = true
                    cl.col_span = 1
                    cl.row_span = 1
                c = c + 1
            r = r + 1
        origin.col_span = c2 - c1 + 1
        origin.row_span = r2 - r1 + 1
        if len(texts) > 0:
            for t in texts:
                origin.add_paragraph(t)
        return origin

    func data():
        out := []
        for row in self.rows:
            line := []
            for c in row.cells:
                append(line, "" if c.merged else c.text())
            append(out, line)
        return out

    func text():
        lines := []
        for line in self.data():
            append(lines, string.join("\t", line))
        return string.join("\n", lines)

    func style_header(bold=true, shading=null, color=null):
        if len(self.rows) == 0:
            return self
        self.rows[0].header = true
        for c in self.rows[0].cells:
            if shading != null:
                c.shading = shading
            for p in c.paragraphs:
                if isinstance(p, dp.Paragraph):
                    for r in p.runs:
                        if bold:
                            r.bold = true
                        if color != null:
                            r.color = color
        return self

    # Origine de la fusion couvrant (r, c) : [r0, c0] ; la cellule elle-même si elle n'est pas couverte.
    func _origin(r, c):
        rr := r
        while rr >= 0:
            cc := c
            while cc >= 0:
                cl := self.rows[rr].cells[cc] if cc < len(self.rows[rr].cells) else null
                if cl != null and not cl.merged and rr + cl.row_span - 1 >= r and cc + cl.col_span - 1 >= c:
                    return [rr, cc]
                cc = cc - 1
            rr = rr - 1
        return [r, c]

    func _col_twips(avail):
        n := self.col_count()
        out := []
        if n == 0:
            return out
        fixed := 0
        free := 0
        k := 0
        while k < n:
            w := null
            if self.widths != null and k < len(self.widths):
                w = self.widths[k]
            if w == null:
                free = free + 1
                append(out, null)
            else:
                tw := _twips(w)
                fixed = fixed + tw
                append(out, tw)
            k = k + 1
        total := avail
        if self.width != null and self.width != "100%":
            total = _twips(self.width)
        rest := total - fixed
        if rest < free * 300:
            rest = free * 300
        k = 0
        while k < n:
            if out[k] == null:
                out[k] = rest // free if free > 0 else 0
            k = k + 1
        return out

    func to_xml(ctx, avail=9026):
        cols := self._col_twips(avail)
        pr := []
        if self.style != null:
            append(pr, x.el("w:tblStyle", {"w:val": self.style}))
        if self.width == "100%":
            append(pr, x.el("w:tblW", {"w:w": "5000", "w:type": "pct"}))
        elif self.width != null:
            append(pr, x.el("w:tblW", {"w:w": str(_twips(self.width)), "w:type": "dxa"}))
        else:
            s := 0
            for c in cols:
                s = s + c
            append(pr, x.el("w:tblW", {"w:w": str(s), "w:type": "dxa"}))
        if self.align != null:
            a := string.lower(self.align)
            append(pr, x.el("w:jc", {"w:val": "center" if a == "center" or a == "centre" else ("right" if a == "right" or a == "droite" else "left")}))
        if self.indent != null:
            append(pr, x.el("w:tblInd", {"w:w": str(_twips(self.indent)), "w:type": "dxa"}))
        if self.borders != null:
            append(pr, _borders_xml("w:tblBorders", self.borders, true))
        append(pr, x.el("w:tblLayout", {"w:type": "autofit" if self.autofit else "fixed"}))
        append(pr, x.el("w:tblLook", {"w:val": "04A0", "w:firstRow": "1", "w:lastRow": "0", "w:firstColumn": "1", "w:lastColumn": "0", "w:noHBand": "0", "w:noVBand": "1"}))
        grid := []
        for c in cols:
            append(grid, x.el("w:gridCol", {"w:w": str(c)}))
        kids := [x.el("w:tblPr", null, pr), x.el("w:tblGrid", null, grid)]
        r := 0
        for row in self.rows:
            tr := []
            trpr := []
            if row.cant_split == true:
                append(trpr, x.el("w:cantSplit"))
            if row.height != null:
                append(trpr, x.el("w:trHeight", {"w:val": str(_twips(row.height)), "w:hRule": "exact" if row.exact_height else "atLeast"}))
            if row.header:
                append(trpr, x.el("w:tblHeader"))
            if len(trpr) > 0:
                append(tr, x.el("w:trPr", null, trpr))
            c := 0
            n := len(row.cells)
            while c < n:
                cl := row.cells[c]
                span := 1
                vm := null
                src := cl
                if cl.merged:
                    o := self._origin(r, c)
                    origin := self.rows[o[0]].cells[o[1]]
                    if o[0] == r:
                        # couverte horizontalement : déjà écrite par l'origine (gridSpan)
                        c = c + 1
                        continue
                    # couverte verticalement : cellule « continue » (seulement à la colonne d'origine)
                    if o[1] != c:
                        c = c + 1
                        continue
                    span = origin.col_span
                    vm = "continue"
                    src = origin
                else:
                    span = cl.col_span
                    if cl.row_span > 1:
                        vm = "restart"
                w := 0
                k := 0
                while k < span and c + k < len(cols):
                    w = w + cols[c + k]
                    k = k + 1
                tcpr := [x.el("w:tcW", {"w:w": str(w if cl.width == null else _twips(cl.width)), "w:type": "dxa"})]
                if span > 1:
                    append(tcpr, x.el("w:gridSpan", {"w:val": str(span)}))
                if vm != null:
                    append(tcpr, x.el("w:vMerge", {"w:val": "restart"}) if vm == "restart" else x.el("w:vMerge"))
                if src.borders != null:
                    append(tcpr, _borders_xml("w:tcBorders", src.borders, false))
                if src.shading != null:
                    append(tcpr, x.el("w:shd", {"w:val": "clear", "w:color": "auto", "w:fill": u.color_hex(src.shading)}))
                if src.margin != null:
                    m := str(_twips(src.margin))
                    append(tcpr, x.el("w:tcMar", null, [x.el("w:top", {"w:w": m, "w:type": "dxa"}), x.el("w:left", {"w:w": m, "w:type": "dxa"}), x.el("w:bottom", {"w:w": m, "w:type": "dxa"}), x.el("w:right", {"w:w": m, "w:type": "dxa"})]))
                if src.valign != null:
                    va := string.lower(src.valign)
                    append(tcpr, x.el("w:vAlign", {"w:val": "center" if va == "center" or va == "middle" else ("bottom" if va == "bottom" else "top")}))
                tc := [x.el("w:tcPr", null, tcpr)]
                if vm == "continue":
                    append(tc, x.el("w:p"))
                else:
                    last_is_p := false
                    for p in cl.paragraphs:
                        if isinstance(p, dp.Paragraph):
                            append(tc, p.to_xml(ctx))
                            last_is_p = true
                        else:
                            append(tc, p.to_xml(ctx, w))
                            last_is_p = false
                    if not last_is_p:
                        append(tc, x.el("w:p"))
                append(tr, x.el("w:tc", null, tc))
                c = c + span if not cl.merged else c + 1
            append(kids, x.el("w:tr", null, tr))
            r = r + 1
        return x.el("w:tbl", null, kids)

func _borders_xml(tag, spec, inside):
    sides := ["w:top", "w:left", "w:bottom", "w:right"]
    if inside:
        sides = ["w:top", "w:left", "w:bottom", "w:right", "w:insideH", "w:insideV"]
    kids := []
    for s in sides:
        if spec == false:
            append(kids, x.el(s, {"w:val": "nil"}))
        else:
            col := "auto"
            if type(spec) == "str":
                col = u.color_hex(spec)
            append(kids, x.el(s, {"w:val": "single", "w:sz": "4", "w:space": "0", "w:color": col}))
    return x.el(tag, null, kids)

# Tableau à partir de lignes de valeurs.
func from_rows(rows, header=true, style="TableGrid", header_bold=true, header_shading=null):
    n := 0
    for r in rows:
        if len(r) > n:
            n = len(r)
    t := Table(0, n, style)
    for r in rows:
        cells := []
        for v in r:
            append(cells, Cell(v))
        while len(cells) < n:
            append(cells, Cell())
        append(t.rows, Row(cells))
    if header and len(rows) > 0:
        t.style_header(header_bold, header_shading)
    return t

# ---------------------------------------------------------------------------------------------- lecture

func _twips_pt(v):
    n := _n.num_parse(v)
    if n == null:
        return null
    return to_float(n) / 20.0

func _read_cell(tc, rctx):
    cell := Cell()
    cell.paragraphs = []
    pr := x.first(tc, "w:tcPr")
    span := 1
    vm := null
    if pr != null:
        gs := x.first(pr, "w:gridSpan")
        if gs != null:
            span = x.attr_int(gs, "w:val", 1)
        v := x.first(pr, "w:vMerge")
        if v != null:
            vm = x.attr(v, "w:val", "continue")
        shd := x.first(pr, "w:shd")
        if shd != null:
            f := x.attr(shd, "w:fill", "auto")
            if f != "auto":
                cell.shading = string.upper(f)
        va := x.first(pr, "w:vAlign")
        if va != null:
            cell.valign = x.attr(va, "w:val")
        w := x.first(pr, "w:tcW")
        if w != null and x.attr(w, "w:type", "dxa") == "dxa":
            cell.width = _twips_pt(x.attr(w, "w:w", "0"))
    for c in x.children(tc):
        ln := x.local_name(c["tag"])
        if ln == "p":
            append(cell.paragraphs, dp.parse_paragraph(c, rctx))
        elif ln == "tbl":
            append(cell.paragraphs, parse_table(c, rctx))
        elif ln == "sdt":
            content := x.first(c, "w:sdtContent")
            if content != null:
                for p in x.children(content, "w:p"):
                    append(cell.paragraphs, dp.parse_paragraph(p, rctx))
    if len(cell.paragraphs) == 0:
        append(cell.paragraphs, dp.Paragraph())
    return [cell, span, vm]

func parse_table(node, rctx):
    t := Table(0, 0, null)
    pr := x.first(node, "w:tblPr")
    if pr != null:
        st := x.first(pr, "w:tblStyle")
        if st != null:
            t.style = x.attr(st, "w:val")
        jc := x.first(pr, "w:jc")
        if jc != null:
            t.align = x.attr(jc, "w:val")
        tw := x.first(pr, "w:tblW")
        if tw != null and x.attr(tw, "w:type", "") == "pct" and x.attr(tw, "w:w", "") == "5000":
            t.width = "100%"
    grid := x.first(node, "w:tblGrid")
    widths := []
    if grid != null:
        for g in x.children(grid, "w:gridCol"):
            append(widths, _twips_pt(x.attr(g, "w:w", "0")))
    if len(widths) > 0:
        t.widths = widths
    # grille logique : chaque case (r, c) reçoit une Cell ; les cases couvertes sont marquées merged
    rows_tc := []
    for tr in x.children(node, "w:tr"):
        append(rows_tc, tr)
    for sdt in x.children(node, "w:sdt"):
        content := x.first(sdt, "w:sdtContent")
        if content != null:
            for tr in x.children(content, "w:tr"):
                append(rows_tc, tr)
    origins := {}
    r := 0
    for tr in rows_tc:
        row := Row([])
        trpr := x.first(tr, "w:trPr")
        if trpr != null:
            row.header = x.first(trpr, "w:tblHeader") != null
            h := x.first(trpr, "w:trHeight")
            if h != null:
                row.height = _twips_pt(x.attr(h, "w:val", "0"))
                row.exact_height = x.attr(h, "w:hRule", "") == "exact"
            if x.first(trpr, "w:cantSplit") != null:
                row.cant_split = true
            gb := x.first(trpr, "w:gridBefore")
            if gb != null:
                k := 0
                while k < x.attr_int(gb, "w:val", 0):
                    append(row.cells, Cell())
                    k = k + 1
        col := len(row.cells)
        for tc in x.children(tr, "w:tc"):
            info := _read_cell(tc, rctx)
            cell := info[0]
            span := info[1]
            vm := info[2]
            if vm == "continue" and contains_key(origins, str(col)):
                o := origins[str(col)]
                origin := t.rows[o[0]].cells[o[1]]
                origin.row_span = r - o[0] + 1
                k := 0
                while k < span:
                    cov := Cell()
                    cov.merged = true
                    append(row.cells, cov)
                    k = k + 1
            else:
                cell.col_span = span
                append(row.cells, cell)
                k := 1
                while k < span:
                    cov := Cell()
                    cov.merged = true
                    append(row.cells, cov)
                    k = k + 1
                if vm == "restart":
                    origins[str(col)] = [r, len(row.cells) - span]
                elif contains_key(origins, str(col)):
                    collections.remove(origins, str(col))
            col = col + span
        append(t.rows, row)
        r = r + 1
    # lignes de longueur inégale : complétées
    n := t.col_count()
    for row in t.rows:
        while len(row.cells) < n:
            append(row.cells, Cell())
    return t
