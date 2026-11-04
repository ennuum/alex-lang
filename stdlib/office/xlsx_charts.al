# ALEX STANDARD LIBRARY — office.xlsx_charts
# Graphiques DrawingML (xl/charts/chartN.xml, aussi utilisés par PowerPoint) : histogrammes (colonnes / barres,
# groupés, empilés, 100 %), courbes, aires, secteurs, anneaux, nuages de points ; titres, légende, titres d'axes,
# étiquettes de données, couleurs ; lecture des graphiques existants.
#
#   use office.xlsx_charts as charts
#   ch := charts.Chart("column", "Ventes 2026")
#   ch.add_series("Feuil1!$B$2:$B$13", "Feuil1!$A$2:$A$13", "Feuil1!$B$1")   # valeurs, catégories, nom
#   ch.anchor = "E2"
#   ch.width = "16cm"
#   ch.y_title = "Montant (€)"
#   ws.charts = ...   (voir excel.Worksheet.add_chart / Workbook)
#
# Chart(kind="column", title=null) : kind ("column" | "bar" | "line" | "area" | "pie" | "doughnut" | "scatter")
#   title  series  anchor ("E2")  width  height (longueurs ; défaut 15 cm × 7,5 cm)  legend ("right" | "bottom" |
#   "top" | "left" | null)  x_title  y_title  stacked (false | true | "percent")  data_labels  smooth (courbes)
#   markers  style  gap_width  hole_size (anneau, %)  y_min  y_max  number_format
#   add_series(values, categories=null, name=null, color=null) -> dict
#     values / categories : référence « Feuille!$A$1:$A$5 » ou liste de valeurs ; name : texte ou référence
#     (pour un nuage de points : categories = valeurs X)
# Fonctions : chart_xml(chart, resolver=null) -> nœud c:chartSpace (resolver(ref) -> liste de valeurs : remplit les
#   caches pour que le graphique s'affiche sans recalcul)   parse_chart(nœud) -> Chart (références et caches)
#   PALETTE : couleurs par défaut des séries (thème Office)
# Erreurs : ValueError (type de graphique inconnu), XLSXError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use string
use office.errors as errors
use office.utils as u
use office.xml as x

const PALETTE := ["4472C4", "ED7D31", "A5A5A5", "FFC000", "5B9BD5", "70AD47", "264478", "9E480E", "636363", "997300", "255E91", "43682B"]
const KINDS := ["column", "bar", "line", "area", "pie", "doughnut", "scatter"]

class Chart:
    func init(kind="column", title=null):
        ok := false
        for k in KINDS:
            if k == kind:
                ok = true
        if not ok:
            raise("ValueError", "type de graphique inconnu : '" + u.to_text(kind) + "' (column, bar, line, area, pie, doughnut, scatter)")
        self.kind = kind
        self.title = title
        self.series = []
        self.anchor = "E2"
        self.width = 5400000
        self.height = 2700000
        self.legend = "right" if kind != "pie" and kind != "doughnut" else "right"
        self.x_title = null
        self.y_title = null
        self.stacked = false
        self.data_labels = false
        self.smooth = false
        self.markers = true
        self.style = null
        self.gap_width = 150
        self.hole_size = 50
        self.y_min = null
        self.y_max = null
        self.number_format = null

    func add_series(values, categories=null, name=null, color=null):
        s := {"values": values, "categories": categories, "name": name, "color": color}
        append(self.series, s)
        return s

    func size_emu():
        return [u.length(self.width), u.length(self.height)]

# ---------------------------------------------------------------------------------------------- écriture

func _v(tag, val):
    return x.el(tag, {"val": u.to_text(val)})

func _rich(text, size=null, bold=null):
    rpr := {"lang": "fr-FR"}
    if size != null:
        rpr["sz"] = str(to_int(size * 100))
    if bold != null:
        rpr["b"] = "1" if bold else "0"
    return x.el("c:tx", null, [x.el("c:rich", null, [x.el("a:bodyPr"), x.el("a:lstStyle"), x.el("a:p", null, [x.el("a:pPr", null, [x.el("a:defRPr", {"sz": rpr["sz"] if contains_key(rpr, "sz") else null, "b": rpr["b"] if contains_key(rpr, "b") else null})]), x.el("a:r", null, [x.el("a:rPr", rpr), x.el("a:t", null, [text])])])])])

func _title(text, size=14, bold=true):
    return x.el("c:title", null, [_rich(text, size, bold), x.el("c:overlay", {"val": "0"})])

func _is_ref(v):
    return type(v) == "str"

func _cache_values(spec, resolver):
    if spec == null:
        return []
    if type(spec) == "list" or type(spec) == "tuple":
        out := []
        for v in spec:
            append(out, v)
        return out
    if resolver == null:
        return []
    try:
        vals := resolver(spec)
        if vals == null:
            return []
        return vals
    catch e:
        return []

func _all_numeric(vals):
    if len(vals) == 0:
        return false
    for v in vals:
        if v != null and type(v) != "int" and type(v) != "float":
            return false
    return true

func _str_cache(vals):
    kids := [_v("c:ptCount", len(vals))]
    i := 0
    for v in vals:
        if v != null:
            append(kids, x.el("c:pt", {"idx": str(i)}, [x.el("c:v", null, [u.to_text(v) if not u.is_date_dict(v) else u.iso_date(v)])]))
        i = i + 1
    return kids

func _num_cache(vals, fmt):
    kids := [x.el("c:formatCode", null, [fmt if fmt != null else "General"]), _v("c:ptCount", len(vals))]
    i := 0
    for v in vals:
        if type(v) == "int" or type(v) == "float":
            append(kids, x.el("c:pt", {"idx": str(i)}, [x.el("c:v", null, [u.format_number(v)])]))
        elif u.is_date_dict(v):
            append(kids, x.el("c:pt", {"idx": str(i)}, [x.el("c:v", null, [u.format_number(u.date_to_serial(v["year"], v["month"], v["day"]))])]))
        i = i + 1
    return kids

# Données de catégories / valeurs : référence avec cache, ou littéral.
func _data_ref(tag, spec, resolver, numeric, fmt=null):
    vals := _cache_values(spec, resolver)
    use_num := numeric
    if not numeric and _all_numeric(vals):
        use_num = true
    if _is_ref(spec):
        if use_num:
            return x.el(tag, null, [x.el("c:numRef", null, [x.el("c:f", null, [spec]), x.el("c:numCache", null, _num_cache(vals, fmt))])])
        return x.el(tag, null, [x.el("c:strRef", null, [x.el("c:f", null, [spec]), x.el("c:strCache", null, _str_cache(vals))])])
    if use_num:
        return x.el(tag, null, [x.el("c:numLit", null, _num_cache(vals, fmt))])
    return x.el(tag, null, [x.el("c:strLit", null, _str_cache(vals))])

func _series_name(name, resolver):
    if name == null:
        return null
    if _is_ref(name) and string.contains(name, "!"):
        vals := _cache_values(name, resolver)
        return x.el("c:tx", null, [x.el("c:strRef", null, [x.el("c:f", null, [name]), x.el("c:strCache", null, _str_cache(vals if len(vals) > 0 else [""]))])])
    return x.el("c:tx", null, [x.el("c:v", null, [u.to_text(name)])])

func _fill(color):
    return x.el("a:solidFill", null, [x.el("a:srgbClr", {"val": u.color_hex(color)})])

func _sppr(chart, color):
    if chart.kind == "line" or chart.kind == "scatter":
        return x.el("c:spPr", null, [x.el("a:ln", {"w": "28575", "cap": "rnd"}, [_fill(color), x.el("a:round")])])
    return x.el("c:spPr", null, [_fill(color), x.el("a:ln", null, [x.el("a:noFill")])])

func _dlbls(chart):
    pct := chart.kind == "pie" or chart.kind == "doughnut"
    return x.el("c:dLbls", null, [_v("c:showLegendKey", 0), _v("c:showVal", 0 if pct else 1), _v("c:showCatName", 0), _v("c:showSerName", 0), _v("c:showPercent", 1 if pct else 0), _v("c:showBubbleSize", 0)])

func _ser_xml(chart, s, i, resolver):
    kids := [_v("c:idx", i), _v("c:order", i)]
    tx := _series_name(s["name"], resolver)
    if tx != null:
        append(kids, tx)
    color := s["color"]
    if color == null:
        color = PALETTE[i % len(PALETTE)]
    pie := chart.kind == "pie" or chart.kind == "doughnut"
    if not pie:
        append(kids, _sppr(chart, color))
    k := chart.kind
    if k == "column" or k == "bar":
        append(kids, _v("c:invertIfNegative", 0))
    if k == "line" or k == "scatter":
        if chart.markers:
            append(kids, x.el("c:marker", null, [_v("c:symbol", "circle"), _v("c:size", 5), x.el("c:spPr", null, [_fill(color)])]))
        else:
            append(kids, x.el("c:marker", null, [_v("c:symbol", "none")]))
    if pie:
        vals := _cache_values(s["values"], resolver)
        j := 0
        while j < len(vals):
            append(kids, x.el("c:dPt", null, [_v("c:idx", j), _v("c:bubble3D", 0), x.el("c:spPr", null, [_fill(PALETTE[j % len(PALETTE)]), x.el("a:ln", {"w": "12700"}, [x.el("a:solidFill", null, [x.el("a:srgbClr", {"val": "FFFFFF"})])])])]))
            j = j + 1
    if k == "scatter":
        if s["categories"] != null:
            append(kids, _data_ref("c:xVal", s["categories"], resolver, false))
        append(kids, _data_ref("c:yVal", s["values"], resolver, true, chart.number_format))
        append(kids, _v("c:smooth", 1 if chart.smooth else 0))
        return x.el("c:ser", null, kids)
    if s["categories"] != null:
        append(kids, _data_ref("c:cat", s["categories"], resolver, false))
    append(kids, _data_ref("c:val", s["values"], resolver, true, chart.number_format))
    if k == "line":
        append(kids, _v("c:smooth", 1 if chart.smooth else 0))
    return x.el("c:ser", null, kids)

func _axis_title(text):
    return x.el("c:title", null, [_rich(text, 10, false), x.el("c:overlay", {"val": "0"})])

func _cat_ax(ident, cross, pos, title, delete=false):
    kids := [_v("c:axId", ident), x.el("c:scaling", null, [_v("c:orientation", "minMax")]), _v("c:delete", 1 if delete else 0), _v("c:axPos", pos)]
    if title != null:
        append(kids, _axis_title(title))
    append(kids, x.el("c:numFmt", {"formatCode": "General", "sourceLinked": "1"}))
    append(kids, _v("c:majorTickMark", "out"))
    append(kids, _v("c:minorTickMark", "none"))
    append(kids, _v("c:tickLblPos", "nextTo"))
    append(kids, _v("c:crossAx", cross))
    append(kids, _v("c:crosses", "autoZero"))
    append(kids, _v("c:auto", 1))
    append(kids, _v("c:lblAlgn", "ctr"))
    append(kids, _v("c:lblOffset", 100))
    append(kids, _v("c:noMultiLvlLbl", 0))
    return x.el("c:catAx", null, kids)

func _val_ax(ident, cross, pos, title, chart, gridlines=true, between=true):
    scaling := [_v("c:orientation", "minMax")]
    if chart.y_max != null:
        append(scaling, _v("c:max", u.format_number(chart.y_max)))
    if chart.y_min != null:
        append(scaling, _v("c:min", u.format_number(chart.y_min)))
    kids := [_v("c:axId", ident), x.el("c:scaling", null, scaling), _v("c:delete", 0), _v("c:axPos", pos)]
    if gridlines:
        append(kids, x.el("c:majorGridlines", null, [x.el("c:spPr", null, [x.el("a:ln", {"w": "9525"}, [x.el("a:solidFill", null, [x.el("a:srgbClr", {"val": "D9D9D9"})])])])]))
    if title != null:
        append(kids, _axis_title(title))
    nf := chart.number_format if chart.number_format != null else ("0%" if chart.stacked == "percent" else "General")
    append(kids, x.el("c:numFmt", {"formatCode": nf, "sourceLinked": "0" if chart.number_format != null or chart.stacked == "percent" else "1"}))
    append(kids, _v("c:majorTickMark", "out"))
    append(kids, _v("c:minorTickMark", "none"))
    append(kids, _v("c:tickLblPos", "nextTo"))
    append(kids, _v("c:crossAx", cross))
    append(kids, _v("c:crosses", "autoZero"))
    append(kids, _v("c:crossBetween", "between" if between else "midCat"))
    return x.el("c:valAx", null, kids)

func _grouping(chart):
    if chart.stacked == "percent":
        return "percentStacked"
    if chart.stacked:
        return "stacked"
    return "clustered" if chart.kind == "column" or chart.kind == "bar" else "standard"

func chart_xml(chart, resolver=null):
    if len(chart.series) == 0:
        errors.fail(errors.XLSX, "graphique sans série")
    k := chart.kind
    sers := []
    i := 0
    for s in chart.series:
        append(sers, _ser_xml(chart, s, i, resolver))
        i = i + 1
    plot := [x.el("c:layout")]
    axes := []
    if k == "column" or k == "bar":
        body := [_v("c:barDir", "col" if k == "column" else "bar"), _v("c:grouping", _grouping(chart)), _v("c:varyColors", 0)]
        for s in sers:
            append(body, s)
        if chart.data_labels:
            append(body, _dlbls(chart))
        append(body, _v("c:gapWidth", chart.gap_width))
        if chart.stacked:
            append(body, _v("c:overlap", 100))
        append(body, _v("c:axId", 500000001))
        append(body, _v("c:axId", 500000002))
        append(plot, x.el("c:barChart", null, body))
        append(axes, _cat_ax(500000001, 500000002, "b" if k == "column" else "l", chart.x_title))
        append(axes, _val_ax(500000002, 500000001, "l" if k == "column" else "b", chart.y_title, chart))
    elif k == "line" or k == "area":
        tag := "c:lineChart" if k == "line" else "c:areaChart"
        body := [_v("c:grouping", _grouping(chart)), _v("c:varyColors", 0)]
        for s in sers:
            append(body, s)
        if chart.data_labels:
            append(body, _dlbls(chart))
        if k == "line":
            append(body, _v("c:marker", 1))
        append(body, _v("c:axId", 500000001))
        append(body, _v("c:axId", 500000002))
        append(plot, x.el(tag, null, body))
        append(axes, _cat_ax(500000001, 500000002, "b", chart.x_title))
        append(axes, _val_ax(500000002, 500000001, "l", chart.y_title, chart, true, k == "line"))
    elif k == "pie" or k == "doughnut":
        tag := "c:pieChart" if k == "pie" else "c:doughnutChart"
        body := [_v("c:varyColors", 1)]
        for s in sers:
            append(body, s)
        if chart.data_labels:
            append(body, _dlbls(chart))
        append(body, _v("c:firstSliceAng", 0))
        if k == "doughnut":
            append(body, _v("c:holeSize", chart.hole_size))
        append(plot, x.el(tag, null, body))
    elif k == "scatter":
        body := [_v("c:scatterStyle", "lineMarker" if chart.markers else "line"), _v("c:varyColors", 0)]
        for s in sers:
            append(body, s)
        if chart.data_labels:
            append(body, _dlbls(chart))
        append(body, _v("c:axId", 500000001))
        append(body, _v("c:axId", 500000002))
        append(plot, x.el("c:scatterChart", null, body))
        append(axes, _val_ax(500000001, 500000002, "b", chart.x_title, chart, false, false))
        append(axes, _val_ax(500000002, 500000001, "l", chart.y_title, chart))
    for a in axes:
        append(plot, a)
    ckids := []
    if chart.title != null:
        append(ckids, _title(chart.title))
        append(ckids, _v("c:autoTitleDeleted", 0))
    else:
        append(ckids, _v("c:autoTitleDeleted", 1))
    append(ckids, x.el("c:plotArea", null, plot))
    if chart.legend != null:
        pos := {"right": "r", "left": "l", "top": "t", "bottom": "b", "r": "r", "l": "l", "t": "t", "b": "b"}
        append(ckids, x.el("c:legend", null, [_v("c:legendPos", pos[chart.legend] if contains_key(pos, chart.legend) else "r"), x.el("c:overlay", {"val": "0"})]))
    append(ckids, _v("c:plotVisOnly", 1))
    append(ckids, _v("c:dispBlanksAs", "gap"))
    kids := [_v("c:date1904", 0), _v("c:lang", "fr-FR"), _v("c:roundedCorners", 0)]
    if chart.style != null:
        append(kids, _v("c:style", chart.style))
    append(kids, x.el("c:chart", null, ckids))
    append(kids, x.el("c:spPr", null, [x.el("a:solidFill", null, [x.el("a:schemeClr", {"val": "bg1"})]), x.el("a:ln", null, [x.el("a:noFill")])]))
    return x.el("c:chartSpace", {"xmlns:c": x.NS["c"], "xmlns:a": x.NS["a"], "xmlns:r": x.NS["r"]}, kids)

# ---------------------------------------------------------------------------------------------- lecture

func _read_data(el):
    if el == null:
        return [null, []]
    ref := null
    f := x.find(el, "c:f")
    if f != null:
        ref = x.text(f)
    vals := []
    cache := x.find(el, "c:numCache")
    numeric := true
    if cache == null:
        cache = x.find(el, "c:strCache")
        numeric = false
    if cache == null:
        cache = x.find(el, "c:numLit")
        numeric = true
    if cache == null:
        cache = x.find(el, "c:strLit")
        numeric = false
    if cache != null:
        n := x.attr_int(x.first(cache, "c:ptCount"), "val", 0)
        vals = u.repeat(null, n)
        for pt in x.children(cache, "c:pt"):
            idx := x.attr_int(pt, "idx", 0)
            t := x.text(x.first(pt, "c:v"))
            v := u.parse_number(t) if numeric else t
            if idx >= 0 and idx < n:
                vals[idx] = v if v != null else t
    return [ref, vals]

func parse_chart(root):
    plot := x.find(root, "c:plotArea")
    if plot == null:
        errors.fail(errors.XLSX, "graphique sans zone de traçage")
    kind := "column"
    body := null
    for c in x.children(plot):
        ln := x.local_name(c["tag"])
        if ln == "barChart":
            dir := x.attr(x.first(c, "c:barDir"), "val", "col")
            kind = "column" if dir == "col" else "bar"
            body = c
        elif ln == "lineChart" or ln == "line3DChart":
            kind = "line"
            body = c
        elif ln == "areaChart" or ln == "area3DChart":
            kind = "area"
            body = c
        elif ln == "pieChart" or ln == "pie3DChart" or ln == "ofPieChart":
            kind = "pie"
            body = c
        elif ln == "doughnutChart":
            kind = "doughnut"
            body = c
        elif ln == "scatterChart" or ln == "bubbleChart":
            kind = "scatter"
            body = c
        elif ln == "bar3DChart":
            kind = "column"
            body = c
        if body != null:
            break
    ch := Chart(kind, null)
    t := x.first(x.find(root, "c:chart"), "c:title")
    if t != null:
        parts := []
        for e in x.find_all(t, "a:t"):
            append(parts, x.text(e))
        if len(parts) == 0:
            for e in x.find_all(t, "c:v"):
                append(parts, x.text(e))
        ch.title = string.join("", parts)
    if body != null:
        g := x.first(body, "c:grouping")
        if g != null:
            gv := x.attr(g, "val", "")
            if gv == "stacked":
                ch.stacked = true
            elif gv == "percentStacked":
                ch.stacked = "percent"
        for s in x.children(body, "c:ser"):
            name := null
            name_text := null
            tx := x.first(s, "c:tx")
            if tx != null:
                f := x.find(tx, "c:f")
                vv := x.find(tx, "c:v")
                name_text = x.text(vv) if vv != null else null
                if f != null:
                    name = x.text(f)
                else:
                    name = name_text
            cat := _read_data(x.first(s, "c:cat") if kind != "scatter" else x.first(s, "c:xVal"))
            val := _read_data(x.first(s, "c:val") if kind != "scatter" else x.first(s, "c:yVal"))
            spec := ch.add_series(val[0] if val[0] != null else val[1], cat[0] if cat[0] != null else (cat[1] if len(cat[1]) > 0 else null), name)
            spec["cached_values"] = val[1]
            spec["cached_categories"] = cat[1]
            spec["name_text"] = name_text
            col := x.find(x.first(s, "c:spPr"), "a:srgbClr") if x.first(s, "c:spPr") != null else null
            if col != null:
                spec["color"] = x.attr(col, "val", null)
    lg := x.find(root, "c:legend")
    if lg == null:
        ch.legend = null
    else:
        lp := x.attr(x.first(lg, "c:legendPos"), "val", "r")
        ch.legend = {"r": "right", "l": "left", "t": "top", "b": "bottom", "tr": "right"}[lp] if contains_key({"r": 1, "l": 1, "t": 1, "b": 1, "tr": 1}, lp) else "right"
    return ch
