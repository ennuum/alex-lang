# ALEX STANDARD LIBRARY — web.html.tables
#
# Tableaux de données accessibles : <table> avec <caption>, <thead> / <tbody> / <tfoot>, en-têtes <th scope>,
# construits depuis des listes de lignes ou des enregistrements (dict), avec mise en forme des cellules ; et
# lecture inverse d'un tableau HTML en lignes (extraction de données d'une page).
#
#   use web.html.tables as tb
#   t := tb.from_rows([["Ville", "Habitants"], ["Paris", 2133111], ["Lyon", 522250]], "Villes", true)
#   gens := [{"nom": "Zoé", "age": 31}, {"nom": "Léo", "age": 27}]
#   t2 := tb.from_records(gens, ["nom", "age"], {"nom": "Nom", "age": "Âge"})
#   t3 := tb.from_records(gens, null, null, {"age": (v) => str(v) + " ans"}, "Équipe", true)   # 1re colonne en <th scope=row>
#   tb.to_rows(t)            # [["Ville", "Habitants"], ["Paris", "2133111"], ["Lyon", "522250"]]
#   tb.to_records(t)         # [{"Ville": "Paris", "Habitants": "2133111"}, …]
#
# Une cellule peut être une valeur (texte échappé), un nœud, ou un dict {"content": …, "colspan": 2, …}.
# Erreurs : HtmlError (lignes de longueurs incohérentes en mode strict), TypeError.

from core use len, type
from collections use append, keys
use string as _s
use web.html.html_errors as _err
use web.html.element as _el
use web.html.element_factory as _f

func _cell(tag, value, attributes=null):
    if type(value) == "dict" and "content" in value:
        attrs := {}
        for k in keys(value):
            if k != "content":
                attrs[k] = value[k]
        return _el.Element(tag, _f.merge_attributes(attrs, attributes), value["content"])
    if value == null:
        return _el.Element(tag, attributes)
    if type(value) == "int" or type(value) == "float":
        return _el.Element(tag, attributes, str(value))
    return _el.Element(tag, attributes, value)

func td(value=null, attributes=null):
    return _cell("td", value, attributes)

# En-tête ; scope : « col », « row », « colgroup », « rowgroup ».
func th(value=null, scope="col", attributes=null):
    return _cell("th", value, _f.merge_attributes({"scope": scope}, attributes))

func tr(cells, header=false, row_header=false):
    r := _el.Element("tr")
    i := 0
    for c in cells:
        if header:
            r.append(th(c, "col"))
        elif row_header and i == 0:
            r.append(th(c, "row"))
        else:
            r.append(td(c))
        i += 1
    return r

func caption(content):
    return _el.Element("caption", null, content)

# <colgroup> : liste de largeurs (str CSS) ou de dict d'attributs.
func colgroup(columns):
    cg := _el.Element("colgroup")
    for c in columns:
        if type(c) == "dict":
            cg.append(_el.Element("col", c))
        elif c == null:
            cg.append(_el.Element("col"))
        else:
            cg.append(_el.Element("col", {"style": "width: " + str(c)}))
    return cg

# Tableau complet. headers : liste des en-têtes de colonnes (ou null) ; rows : lignes de cellules ; footer : ligne de
# pied ; row_headers : première cellule de chaque ligne en <th scope="row">.
func table(rows, headers=null, caption_text=null, footer=null, row_headers=false, attributes=null):
    t := _el.Element("table", attributes)
    if caption_text != null:
        t.append(caption(caption_text))
    if headers != null:
        t.append(_el.Element("thead", null, [tr(headers, true)]))
    body := _el.Element("tbody")
    for r in rows:
        body.append(tr(r, false, row_headers))
    t.append(body)
    if footer != null:
        t.append(_el.Element("tfoot", null, [tr(footer, false, row_headers)]))
    return t

# Depuis une liste de lignes ; header_row : la première ligne donne les en-têtes.
func from_rows(rows, caption_text=null, header_row=true, row_headers=false, strict=false, attributes=null):
    if len(rows) == 0:
        return table([], null, caption_text, null, row_headers, attributes)
    if strict:
        width := len(rows[0])
        for r in rows:
            if len(r) != width:
                _err.html_error("tables.from_rows", "ligne de " + str(len(r)) + " cellules, " + str(width) + " attendues")
    if header_row:
        return table(rows[1:len(rows)], rows[0], caption_text, null, row_headers, attributes)
    return table(rows, null, caption_text, null, row_headers, attributes)

# Depuis des enregistrements (dict). columns : clés à afficher (null : celles du premier enregistrement) ;
# labels : dict clé -> en-tête ; formatters : dict clé -> fonction(valeur) -> contenu.
func from_records(records, columns=null, labels=null, formatters=null, caption_text=null, row_headers=false, attributes=null):
    cols := columns
    if cols == null:
        cols = keys(records[0]) if len(records) > 0 else []
    heads := []
    for c in cols:
        if labels != null and c in labels:
            append(heads, labels[c])
        else:
            append(heads, str(c))
    rows := []
    for rec in records:
        row := []
        for c in cols:
            v := rec[c] if c in rec else null
            if formatters != null and c in formatters:
                v = formatters[c](v)
            append(row, v)
        append(rows, row)
    return table(rows, heads, caption_text, null, row_headers, attributes)

# Lignes de texte d'un tableau HTML (thead, tbody, tfoot et lignes directes, dans l'ordre ; colspan répété).
func to_rows(table_element, expand_colspan=false):
    out := []
    for r in table_element.find_all("tr"):
        if r.closest("table") != table_element:
            continue
        row := []
        for c in r.elements():
            if c.tag == "td" or c.tag == "th":
                text := _s.trim(c.text_content())
                append(row, text)
                if expand_colspan:
                    span := c.get("colspan")
                    if span != null:
                        k := 1
                        while k < _int(span):
                            append(row, text)
                            k += 1
        append(out, row)
    return out

func _int(text):
    n := 0
    for c in text:
        if c < '0' or c > '9':
            return 1
        n = n * 10 + (_s.ord(c) - 48)
    return n if n > 0 else 1

# Enregistrements (dict) : la première ligne (ou l'en-tête thead) donne les clés.
func to_records(table_element):
    rows := to_rows(table_element)
    if len(rows) == 0:
        return []
    heads := rows[0]
    out := []
    i := 1
    while i < len(rows):
        rec := {}
        j := 0
        while j < len(heads):
            rec[heads[j]] = rows[i][j] if j < len(rows[i]) else null
            j += 1
        append(out, rec)
        i += 1
    return out

# Tous les tableaux d'un arbre convertis en lignes.
func extract_all(node):
    out := []
    for t in node.find_all("table"):
        append(out, to_rows(t))
    return out
