# ALEX STANDARD LIBRARY — office.pptx_tables
# Tableaux des diapositives (graphicFrame / a:tbl) : cellules texte mises en forme, ligne d'en-tête, bandes
# alternées, largeurs de colonnes, hauteurs de lignes, couleurs de fond, fusions, style de tableau du thème.
#
#   use office.pptx_tables as ptb
#   t := ptb.SlideTable([["Produit", "Qté"], ["Pommes", 3], ["Poires", 10]], "2cm", "4cm", "20cm")
#   t.cell(0, 1).fill = "C00000"
#   t.font_size = 16
#   slide.add(t)
#
# SlideTable(lignes, x=0, y=0, cx=null, cy=null) : rows (listes de TableCell) x y cx cy col_widths (longueurs)
#   row_heights header (1re ligne en en-tête : true) banded (lignes alternées : true) first_col style_id
#   font_size (pt) font  name
#   cell(r, c) -> TableCell   data() -> lignes de textes   merge(r1, c1, r2, c2)   row_count()  col_count()
#   to_xml(ctx, ident)
# TableCell(text="") : text (pptx_text.TextFrame) fill (couleur) bold color size align ("left" "center"
#   "right") valign ("top" "middle" "bottom") col_span row_span merged   set_text(t)  text_content()
# Fonctions : parse_table(nœud_graphicFrame, rels) -> SlideTable ou null   MEDIUM_STYLE_2 (identifiant du style
#   « Moyen 2 - Accentuation 1 », celui de PowerPoint par défaut)
# Erreurs : IndexError, ValueError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.utils as u
use office.xml as x
use office.pptx_text as pt
use office.pptx_shapes as ps

const MEDIUM_STYLE_2 := "{5C22544A-7EE6-4342-B048-85BDC9FD1C3A}"
const _TABLE_URI := "http://schemas.openxmlformats.org/drawingml/2006/table"

class TableCell:
    func init(text=""):
        self.text = pt.TextFrame(u.to_text(text) if text != null else "")
        self.fill = null
        self.bold = null
        self.color = null
        self.size = null
        self.align = null
        self.valign = null
        self.col_span = 1
        self.row_span = 1
        self.merged_h = false
        self.merged_v = false

    func set_text(t):
        self.text = pt.TextFrame(u.to_text(t))
        return self

    func text_content():
        return self.text.text()

class SlideTable:
    func init(rows=null, x0=0, y0=0, cx=null, cy=null):
        self.rows = []
        if rows != null:
            for r in rows:
                line := []
                for v in r:
                    append(line, TableCell(v))
                append(self.rows, line)
        n := self.col_count()
        for line in self.rows:
            while len(line) < n:
                append(line, TableCell(""))
        self.x = u.length(x0)
        self.y = u.length(y0)
        self.cx = u.length(cx) if cx != null else 914400 * 2 * (n if n > 0 else 1)
        self.cy = u.length(cy) if cy != null else 370840 * (len(self.rows) if len(self.rows) > 0 else 1)
        self.col_widths = null
        self.row_heights = null
        self.header = true
        self.banded = true
        self.first_col = false
        self.style_id = MEDIUM_STYLE_2
        self.font_size = null
        self.font = null
        self.name = null

    func row_count():
        return len(self.rows)

    func col_count():
        n := 0
        for r in self.rows:
            if len(r) > n:
                n = len(r)
        return n

    func cell(r, c):
        if r < 0 or r >= len(self.rows) or c < 0 or c >= len(self.rows[r]):
            raise("IndexError", "cellule (" + str(r) + ", " + str(c) + ") hors du tableau")
        return self.rows[r][c]

    func data():
        out := []
        for r in self.rows:
            line := []
            for c in r:
                append(line, "" if c.merged_h or c.merged_v else c.text_content())
            append(out, line)
        return out

    func merge(r1, c1, r2, c2):
        origin := self.cell(r1, c1)
        self.cell(r2, c2)
        origin.col_span = c2 - c1 + 1
        origin.row_span = r2 - r1 + 1
        r := r1
        while r <= r2:
            c := c1
            while c <= c2:
                if not (r == r1 and c == c1):
                    cl := self.rows[r][c]
                    if c > c1:
                        cl.merged_h = true
                    if r > r1:
                        cl.merged_v = true
                c = c + 1
            r = r + 1
        return origin

    func _widths():
        n := self.col_count()
        out := []
        if n == 0:
            return out
        k := 0
        fixed := 0
        free := 0
        while k < n:
            w := null
            if self.col_widths != null and k < len(self.col_widths) and self.col_widths[k] != null:
                w = u.length(self.col_widths[k])
                fixed = fixed + w
            else:
                free = free + 1
            append(out, w)
            k = k + 1
        rest := self.cx - fixed
        k = 0
        while k < n:
            if out[k] == null:
                out[k] = rest // free if free > 0 and rest > 0 else 914400
            k = k + 1
        return out

    func to_xml(ctx, ident):
        widths := self._widths()
        n := len(self.rows)
        grid := []
        for w in widths:
            append(grid, x.el("a:gridCol", {"w": str(w)}))
        trs := []
        r := 0
        for row in self.rows:
            h := 370840
            if self.row_heights != null and r < len(self.row_heights) and self.row_heights[r] != null:
                h = u.length(self.row_heights[r])
            elif self.cy > 0 and n > 0:
                h = self.cy // n
            tcs := []
            for c in row:
                attrs := {}
                if c.col_span > 1:
                    attrs["gridSpan"] = str(c.col_span)
                if c.row_span > 1:
                    attrs["rowSpan"] = str(c.row_span)
                if c.merged_h:
                    attrs["hMerge"] = "1"
                if c.merged_v:
                    attrs["vMerge"] = "1"
                tf := c.text
                for p in tf.paragraphs:
                    if c.align != null and p.align == null:
                        p.align = c.align
                    for run in p.runs:
                        if c.bold != null and run.bold == null:
                            run.bold = c.bold
                        if c.color != null and run.color == null:
                            run.color = c.color
                        sz := c.size if c.size != null else self.font_size
                        if sz != null and run.size == null:
                            run.size = sz
                        if self.font != null and run.font == null:
                            run.font = self.font
                    if p.font_size == null:
                        p.font_size = c.size if c.size != null else self.font_size
                body := pt.txbody_xml(tf, "a:txBody", ctx)
                tcpr_attrs := {}
                if c.valign != null:
                    va := string.lower(c.valign)
                    tcpr_attrs["anchor"] = "t" if va == "top" else ("ctr" if va == "middle" or va == "center" else "b")
                tcpr_kids := []
                if c.fill != null:
                    append(tcpr_kids, ps.fill_xml(c.fill))
                append(tcs, x.el("a:tc", attrs, [body, x.el("a:tcPr", tcpr_attrs, tcpr_kids)]))
            append(trs, x.el("a:tr", {"h": str(h)}, tcs))
            r = r + 1
        tblpr := x.el("a:tblPr", {"firstRow": "1" if self.header else null, "bandRow": "1" if self.banded else null, "firstCol": "1" if self.first_col else null}, [x.el("a:tableStyleId", null, [self.style_id])] if self.style_id != null else [])
        tbl := x.el("a:tbl", null, [tblpr, x.el("a:tblGrid", null, grid)])
        for tr in trs:
            x.append_child(tbl, tr)
        nm := self.name if self.name != null else "Tableau " + str(ident)
        nv := x.el("p:nvGraphicFramePr", null, [x.el("p:cNvPr", {"id": str(ident), "name": nm}), x.el("p:cNvGraphicFramePr", null, [x.el("a:graphicFrameLocks", {"noGrp": "1"})]), x.el("p:nvPr")])
        total_h := 0
        rr := 0
        for row in self.rows:
            if self.row_heights != null and rr < len(self.row_heights) and self.row_heights[rr] != null:
                total_h = total_h + u.length(self.row_heights[rr])
            elif self.cy > 0 and n > 0:
                total_h = total_h + self.cy // n
            else:
                total_h = total_h + 370840
            rr = rr + 1
        tw := 0
        for w in widths:
            tw = tw + w
        return x.el("p:graphicFrame", null, [nv, ps.xfrm_xml(self.x, self.y, tw, total_h, 0, false, false, "p:xfrm"), x.el("a:graphic", null, [x.el("a:graphicData", {"uri": _TABLE_URI}, [tbl])])])

func parse_table(el, rels=null):
    tbl := x.find(el, "a:tbl")
    if tbl == null:
        return null
    t := SlideTable()
    xf := ps.read_xfrm(x.first(el, "p:xfrm"))
    t.x = xf[0]
    t.y = xf[1]
    t.cx = xf[2]
    t.cy = xf[3]
    cnv := x.find(el, "p:cNvPr")
    if cnv != null:
        t.name = x.attr(cnv, "name", null)
    pr := x.first(tbl, "a:tblPr")
    if pr != null:
        t.header = x.attr_bool(pr, "firstRow", false)
        t.banded = x.attr_bool(pr, "bandRow", false)
        t.first_col = x.attr_bool(pr, "firstCol", false)
        sid := x.first(pr, "a:tableStyleId")
        t.style_id = x.text(sid) if sid != null else null
    widths := []
    grid := x.first(tbl, "a:tblGrid")
    if grid != null:
        for g in x.children(grid, "a:gridCol"):
            append(widths, x.attr_int(g, "w", 0))
    t.col_widths = widths
    heights := []
    for tr in x.children(tbl, "a:tr"):
        append(heights, x.attr_int(tr, "h", 0))
        line := []
        for tc in x.children(tr, "a:tc"):
            c := TableCell("")
            c.text = pt.parse_txbody(x.first(tc, "a:txBody"), rels)
            c.col_span = x.attr_int(tc, "gridSpan", 1)
            c.row_span = x.attr_int(tc, "rowSpan", 1)
            c.merged_h = x.attr_bool(tc, "hMerge", false)
            c.merged_v = x.attr_bool(tc, "vMerge", false)
            tcpr := x.first(tc, "a:tcPr")
            if tcpr != null:
                sf := x.first(tcpr, "a:solidFill")
                if sf != null and x.first(sf, "a:srgbClr") != null:
                    c.fill = x.attr(x.first(sf, "a:srgbClr"), "val", null)
            append(line, c)
        append(t.rows, line)
    t.row_heights = heights
    return t
