# ALEX STANDARD LIBRARY — office.pptx_charts
# Graphiques des diapositives : données fournies directement (catégories + séries), graphique DrawingML (même moteur
# que xlsx_charts) et classeur Excel incorporé, pour que « Modifier les données » fonctionne dans PowerPoint.
#
#   use office.pptx_charts as pc
#   ch := pc.SlideChart("column", ["T1", "T2", "T3", "T4"], [{"name": "2025", "values": [12, 15, 9, 20]},
#                                                           {"name": "2026", "values": [14, 18, 11, 25]}])
#   ch.title = "Chiffre d'affaires (k€)"
#   ch.move("2cm", "4cm")
#   slide.add(ch)
#
# SlideChart(kind, categories, series, x=0, y=0, cx="16cm", cy="9cm") : kind (voir xlsx_charts.KINDS) categories
#   (liste) series (liste de {"name", "values", "color"}) title x y cx cy legend x_title y_title stacked
#   data_labels number_format name   move(x, y)  resize(cx, cy)  bounds()  chart() -> xlsx_charts.Chart
#   workbook_bytes() -> octets du classeur incorporé   to_xml(ctx, ident) (ctx.chart_rel(nœud_chartSpace, octets) -> rId)
# Fonctions : from_chart(xlsx_charts.Chart) -> SlideChart (graphique relu : caches de valeurs)
#   frame_xml(ident, name, rid, x, y, cx, cy) -> p:graphicFrame
# Erreurs : ValueError (séries de longueurs incohérentes), XLSXError.

from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.utils as u
use office.xml as x
use office.pptx_shapes as ps
use office.xlsx_charts as xch
use office.excel as excel

const _CHART_URI := "http://schemas.openxmlformats.org/drawingml/2006/chart"

class SlideChart:
    func init(kind, categories, series, x0=0, y0=0, cx="16cm", cy="9cm"):
        self.kind = kind
        self.categories = categories if categories != null else []
        self.series = series if series != null else []
        for s in self.series:
            if type(s) != "dict" or not contains_key(s, "values"):
                raise("ValueError", "SlideChart : chaque série est un dict {\"name\", \"values\", \"color\"}")
        self.x = u.length(x0)
        self.y = u.length(y0)
        self.cx = u.length(cx)
        self.cy = u.length(cy)
        self.title = null
        self.legend = "bottom"
        self.x_title = null
        self.y_title = null
        self.stacked = false
        self.data_labels = false
        self.number_format = null
        self.name = null

    func move(x0, y0):
        self.x = u.length(x0)
        self.y = u.length(y0)
        return self

    func resize(cx, cy):
        self.cx = u.length(cx)
        self.cy = u.length(cy)
        return self

    func bounds():
        return [self.x, self.y, self.cx, self.cy]

    func _rows():
        n := len(self.categories)
        for s in self.series:
            if len(s["values"]) > n:
                n = len(s["values"])
        return n

    # Graphique DrawingML référençant le classeur incorporé (Feuil1 : catégories en A, séries en B, C...).
    func chart():
        ch := xch.Chart(self.kind, self.title)
        ch.legend = self.legend
        ch.x_title = self.x_title
        ch.y_title = self.y_title
        ch.stacked = self.stacked
        ch.data_labels = self.data_labels
        ch.number_format = self.number_format
        n := self._rows()
        k := 0
        for s in self.series:
            col := u.column_letter(k + 2)
            cats := null
            if len(self.categories) > 0:
                cats = "Feuil1!$A$2:$A$" + str(n + 1)
            spec := ch.add_series("Feuil1!$" + col + "$2:$" + col + "$" + str(n + 1), cats, "Feuil1!$" + col + "$1", u.get(s, "color", null))
            k = k + 1
        return ch

    func _resolver():
        data := {}
        n := self._rows()
        cats := []
        i := 0
        while i < n:
            append(cats, self.categories[i] if i < len(self.categories) else null)
            i = i + 1
        data["Feuil1!$A$2:$A$" + str(n + 1)] = cats
        k := 0
        for s in self.series:
            col := u.column_letter(k + 2)
            vals := []
            i = 0
            while i < n:
                append(vals, s["values"][i] if i < len(s["values"]) else null)
                i = i + 1
            data["Feuil1!$" + col + "$2:$" + col + "$" + str(n + 1)] = vals
            data["Feuil1!$" + col + "$1"] = [u.get(s, "name", "Série " + str(k + 1))]
            k = k + 1
        return (ref) => data[ref] if contains_key(data, ref) else []

    func workbook_bytes():
        wb := excel.new("Feuil1")
        ws := wb.sheets[0]
        header := [""]
        k := 0
        for s in self.series:
            append(header, u.get(s, "name", "Série " + str(k + 1)))
            k = k + 1
        ws.append(header)
        n := self._rows()
        i := 0
        while i < n:
            row := [self.categories[i] if i < len(self.categories) else null]
            for s in self.series:
                append(row, s["values"][i] if i < len(s["values"]) else null)
            ws.append(row)
            i = i + 1
        return wb.to_bytes(false)

    func to_xml(ctx, ident):
        node := xch.chart_xml(self.chart(), self._resolver())
        rid := ctx.chart_rel(node, self.workbook_bytes())
        nm := self.name if self.name != null else "Graphique " + str(ident)
        return frame_xml(ident, nm, rid, self.x, self.y, self.cx, self.cy)

func frame_xml(ident, name, rid, x0, y0, cx, cy):
    nv := x.el("p:nvGraphicFramePr", null, [x.el("p:cNvPr", {"id": str(ident), "name": name}), x.el("p:cNvGraphicFramePr", null, [x.el("a:graphicFrameLocks", {"noGrp": "1"})]), x.el("p:nvPr")])
    return x.el("p:graphicFrame", null, [nv, ps.xfrm_xml(x0, y0, cx, cy, 0, false, false, "p:xfrm"), x.el("a:graphic", null, [x.el("a:graphicData", {"uri": _CHART_URI}, [x.el("c:chart", {"xmlns:c": x.NS["c"], "xmlns:r": x.NS["r"], "r:id": rid})])])])

# Graphique relu (xlsx_charts.Chart avec caches) -> SlideChart.
func from_chart(ch):
    cats := []
    series := []
    for s in ch.series:
        if len(cats) == 0:
            cats = u.get(s, "cached_categories", [])
            if len(cats) == 0 and type(s["categories"]) == "list":
                cats = s["categories"]
        vals := u.get(s, "cached_values", null)
        if vals == null:
            vals = s["values"] if type(s["values"]) == "list" else []
        nm := u.get(s, "name_text", null)
        if nm == null:
            nm = s["name"]
        append(series, {"name": nm if nm != null else "Série", "values": vals, "color": u.get(s, "color", null)})
    sc := SlideChart(ch.kind, cats, series)
    sc.title = ch.title
    sc.legend = ch.legend
    sc.stacked = ch.stacked
    return sc
