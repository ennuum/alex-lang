# ALEX STANDARD LIBRARY — office.pdf_tables
# Tableaux et PDF, dans les deux sens :
#   - EXTRACTION : détection des tableaux d'une page, soit par les filets tracés (traits et rectangles : grille de
#     cellules), soit, sans filet, par l'alignement vertical des mots (colonnes séparées par des couloirs blancs) ;
#   - DESSIN : tableau mis en forme sur un pdf_writer.Canvas (en-tête, bordures, trame alternée, retour à la ligne
#     dans les cellules, alignement par colonne), avec découpage sur plusieurs pages.
#
#   use office.pdf_tables as pt
#   for t in pt.extract_tables("releve.pdf", 0):              # page 1
#       print(t["rows"])                                       # [["Date", "Libellé", "Montant"], ...]
#   pt.to_csv(pt.extract_tables("releve.pdf"))                 # tous les tableaux, en CSV
#
#   h := pt.draw_table(canvas, 50, 780, [["Produit", "Qté"], ["Pommes", 3]], [200, 80], {"header_fill": "D9E2F3"})
#
# EXTRACTION extract_tables(src, pages=null, strategy="auto", password="") -> [{"page", "bbox", "rows", "strategy"}]
#            strategy : "lines" (filets) | "text" (alignement) | "auto" (filets si présents, sinon texte)
#            page_tables(page, strategy="auto")   to_csv(tables, delimiter=",") -> str   to_rows(tables) -> lignes
# DESSIN     TableStyle (dict) : font size header (bool, true) header_font header_fill header_color border_color
#            border_width padding zebra (couleur des lignes paires) align (liste par colonne : "left" | "center" |
#            "right" ; défaut : nombres à droite) text_color leading
#            measure(rows, col_widths, style) -> hauteurs de lignes
#            draw_table(canvas, x, top, rows, col_widths=null, style=null, width=null, row_start=0, row_end=null)
#            -> hauteur dessinée
#            fit_rows(hauteurs, disponible, start) -> indice de fin (lignes qui tiennent)
# Erreurs : PDFError.

use _native_office as _n
from core use len, type, to_int, to_float
from collections use append, keys, contains_key
use collections
use string
use office.utils as u
use office.pdf_reader as pr
use office.pdf_writer as pw
use office.pdf_extract as ex

# ============================================================================================== extraction : filets

const _SNAP := 3.0

func _cluster(values, tol):
    vs := u.sort(values)
    out := []
    for v in vs:
        if len(out) > 0 and v - out[len(out) - 1][len(out[len(out) - 1]) - 1] <= tol:
            append(out[len(out) - 1], v)
        else:
            append(out, [v])
    res := []
    for g in out:
        s := 0.0
        for v in g:
            s = s + v
        append(res, s / to_float(len(g)))
    return res

func _segments(page):
    g := ex.graphics(page)
    hs := []
    vs := []
    for l in g["lines"]:
        dx := l[2] - l[0]
        dy := l[3] - l[1]
        adx := dx if dx >= 0 else -dx
        ady := dy if dy >= 0 else -dy
        if ady <= 1.0 and adx > 2.0:
            append(hs, [l[0] if l[0] < l[2] else l[2], l[0] if l[0] > l[2] else l[2], (l[1] + l[3]) / 2.0])
        elif adx <= 1.0 and ady > 2.0:
            append(vs, [l[1] if l[1] < l[3] else l[3], l[1] if l[1] > l[3] else l[3], (l[0] + l[2]) / 2.0])
    for r in g["rects"]:
        w := r[2] - r[0]
        h := r[3] - r[1]
        if h <= 2.0 and w > 2.0:
            append(hs, [r[0], r[2], (r[1] + r[3]) / 2.0])
        elif w <= 2.0 and h > 2.0:
            append(vs, [r[1], r[3], (r[0] + r[2]) / 2.0])
        elif w > 2.0 and h > 2.0:
            append(hs, [r[0], r[2], r[1]])
            append(hs, [r[0], r[2], r[3]])
            append(vs, [r[1], r[3], r[0]])
            append(vs, [r[1], r[3], r[2]])
    return [hs, vs]

func _covers(segs, pos, a, b, tol):
    for s in segs:
        d := s[2] - pos
        if (d if d >= 0 else -d) <= tol and s[0] <= a + tol and s[1] >= b - tol:
            return true
    # couverture par plusieurs segments contigus
    parts := []
    for s in segs:
        d := s[2] - pos
        if (d if d >= 0 else -d) <= tol and s[1] >= a - tol and s[0] <= b + tol:
            append(parts, [s[0], s[1]])
    if len(parts) == 0:
        return false
    parts = u.sort(parts, (p) => p[0])
    reach := a
    for p in parts:
        if p[0] > reach + tol:
            return false
        if p[1] > reach:
            reach = p[1]
    return reach >= b - tol

func _lines_tables(page):
    sg := _segments(page)
    hs := sg[0]
    vs := sg[1]
    if len(hs) < 2 or len(vs) < 2:
        return []
    # groupes de segments qui se touchent (union-find simple par itérations)
    segs := []
    for h in hs:
        append(segs, ["h", h])
    for v in vs:
        append(segs, ["v", v])
    n := len(segs)
    group := []
    k := 0
    while k < n:
        append(group, k)
        k = k + 1
    i := 0
    while i < n:
        j := i + 1
        while j < n:
            a := segs[i]
            b := segs[j]
            touch := false
            if a[0] != b[0]:
                h := a[1] if a[0] == "h" else b[1]
                v := b[1] if a[0] == "h" else a[1]
                touch = v[2] >= h[0] - _SNAP and v[2] <= h[1] + _SNAP and h[2] >= v[0] - _SNAP and h[2] <= v[1] + _SNAP
            if touch:
                ra := _root(group, i)
                rb := _root(group, j)
                if ra != rb:
                    group[ra] = rb
            j = j + 1
        i = i + 1
    clusters := {}
    i = 0
    while i < n:
        r := _root(group, i)
        if not contains_key(clusters, r):
            clusters[r] = [[], []]
        if segs[i][0] == "h":
            append(clusters[r][0], segs[i][1])
        else:
            append(clusters[r][1], segs[i][1])
        i = i + 1
    words := ex.words(page)
    out := []
    for key in keys(clusters):
        ch := clusters[key][0]
        cv := clusters[key][1]
        if len(ch) < 2 or len(cv) < 2:
            continue
        ys := []
        for h in ch:
            append(ys, h[2])
        xs := []
        for v in cv:
            append(xs, v[2])
        ys = _cluster(ys, _SNAP)
        xs = _cluster(xs, _SNAP)
        if len(ys) < 2 or len(xs) < 2:
            continue
        rows := []
        r := 0
        while r < len(ys) - 1:
            row := []
            c := 0
            while c < len(xs) - 1:
                append(row, [])
                c = c + 1
            append(rows, row)
            r = r + 1
        for w in words:
            cx := (w["x0"] + w["x1"]) / 2.0
            cy := (w["y0"] + w["y1"]) / 2.0
            if cx < xs[0] or cx > xs[len(xs) - 1] or cy < ys[0] or cy > ys[len(ys) - 1]:
                continue
            ri := 0
            while ri < len(ys) - 2 and cy > ys[ri + 1]:
                ri = ri + 1
            ci := 0
            while ci < len(xs) - 2 and cx > xs[ci + 1]:
                ci = ci + 1
            append(rows[ri][ci], w)
        table := []
        for row in rows:
            line := []
            for cell in row:
                append(line, _cell_text(cell))
            # ligne entièrement vide : ignorée
            empty := true
            for t in line:
                if t != "":
                    empty = false
            if not empty:
                append(table, line)
        if len(table) >= 2 and len(xs) >= 3:
            append(out, {"page": page.index, "bbox": [xs[0], ys[0], xs[len(xs) - 1], ys[len(ys) - 1]], "rows": table, "strategy": "lines"})
    return u.sort(out, (t) => t["bbox"][1])

func _root(group, i):
    r := i
    while group[r] != r:
        r = group[r]
    return r

# Texte d'une cellule : mots triés par ligne puis par x.
func _cell_text(ws):
    if len(ws) == 0:
        return ""
    srt := u.sort(ws, (w) => to_int(w["y1"] / (w["size"] * 0.6 if w["size"] > 0 else 5.0)) * 100000 + to_int(w["x0"]))
    lines := []
    cur := []
    last_y := null
    for w in srt:
        if last_y != null and w["y1"] - last_y > w["size"] * 0.6:
            append(lines, string.join(" ", cur))
            cur = []
        append(cur, w["text"])
        last_y = w["y1"]
    if len(cur) > 0:
        append(lines, string.join(" ", cur))
    return string.join("\n", lines)

# ============================================================================================== extraction : texte

func _line_cells(line):
    cells := []
    cur := null
    for c in line["chunks"]:
        if cur == null:
            cur = {"x0": c["x"], "x1": c["x1"], "parts": [c["text"]], "size": c["size"]}
            continue
        gap := c["x"] - cur["x1"]
        sp := c["space"] if c["space"] > 0 else c["size"] * 0.25
        if gap > sp * 2.2:
            append(cells, cur)
            cur = {"x0": c["x"], "x1": c["x1"], "parts": [c["text"]], "size": c["size"]}
        else:
            if gap > sp * 0.45:
                append(cur["parts"], " ")
            append(cur["parts"], c["text"])
            cur["x1"] = c["x1"]
    if cur != null:
        append(cells, cur)
    out := []
    for cl in cells:
        t := string.trim(string.join("", cl["parts"]))
        if t != "":
            append(out, {"x0": cl["x0"], "x1": cl["x1"], "text": t, "size": cl["size"]})
    return out

func _text_tables(page):
    ls := ex.lines(page)
    rows := []
    for l in ls:
        append(rows, {"y": l["y"], "cells": _line_cells(l), "size": l["size"]})
    out := []
    i := 0
    n := len(rows)
    while i < n:
        if len(rows[i]["cells"]) < 2:
            i = i + 1
            continue
        # bloc de lignes consécutives à plusieurs cellules, rapprochées verticalement
        j := i
        while j + 1 < n and len(rows[j + 1]["cells"]) >= 2 and rows[j + 1]["y"] - rows[j]["y"] < rows[j]["size"] * 3.0:
            j = j + 1
        if j - i + 1 >= 2:
            block := []
            k := i
            while k <= j:
                append(block, rows[k])
                k = k + 1
            t := _block_table(block)
            if t != null:
                append(out, {"page": page.index, "bbox": t[1], "rows": t[0], "strategy": "text"})
        i = j + 1
    return out

func _block_table(block):
    starts := []
    size := 10.0
    for r in block:
        size = r["size"]
        for c in r["cells"]:
            append(starts, c["x0"])
    cols := _cluster(starts, size * 1.2)
    if len(cols) < 2:
        return null
    # colonnes peu utilisées (< 40 % des lignes) : fusionnées avec la précédente
    counts := u.repeat(0, len(cols))
    for r in block:
        for c in r["cells"]:
            counts[_nearest(cols, c["x0"])] = counts[_nearest(cols, c["x0"])] + 1
    keep := []
    k := 0
    while k < len(cols):
        if to_float(counts[k]) >= to_float(len(block)) * 0.4 or k == 0:
            append(keep, cols[k])
        k = k + 1
    if len(keep) < 2:
        return null
    table := []
    x0 := 100000.0
    x1 := 0.0
    for r in block:
        line := u.repeat("", len(keep))
        for c in r["cells"]:
            ci := _nearest_left(keep, c["x0"], size)
            line[ci] = c["text"] if line[ci] == "" else line[ci] + " " + c["text"]
            if c["x0"] < x0:
                x0 = c["x0"]
            if c["x1"] > x1:
                x1 = c["x1"]
        append(table, line)
    return [table, [x0, block[0]["y"] - block[0]["size"], x1, block[len(block) - 1]["y"]]]

func _nearest(cols, x0):
    best := 0
    bd := 1000000.0
    k := 0
    for c in cols:
        d := c - x0 if c >= x0 else x0 - c
        if d < bd:
            bd = d
            best = k
        k = k + 1
    return best

func _nearest_left(cols, x0, size):
    best := 0
    k := 0
    for c in cols:
        if c <= x0 + size:
            best = k
        k = k + 1
    return best

func page_tables(page, strategy="auto"):
    if strategy == "lines":
        return _lines_tables(page)
    if strategy == "text":
        return _text_tables(page)
    t := _lines_tables(page)
    if len(t) > 0:
        return t
    return _text_tables(page)

func extract_tables(src, pages=null, strategy="auto", password=""):
    doc := ex.open(src, password)
    out := []
    plist := doc.pages()
    if pages != null:
        plist = []
        for i in (pages if type(pages) == "list" else [pages]):
            append(plist, doc.page(i))
    for p in plist:
        for t in page_tables(p, strategy):
            append(out, t)
    return out

func to_rows(tables):
    out := []
    first := true
    for t in tables:
        if not first:
            append(out, [])
        for r in t["rows"]:
            append(out, r)
        first = false
    return out

func to_csv(tables, delimiter=","):
    lines := []
    for r in to_rows(tables):
        cells := []
        for c in r:
            s := u.to_text(c)
            if string.contains(s, delimiter) or string.contains(s, "\"") or string.contains(s, "\n"):
                s = "\"" + string.replace(s, "\"", "\"\"") + "\""
            append(cells, s)
        append(lines, string.join(delimiter, cells))
    return string.join("\n", lines) + "\n"

# ============================================================================================== dessin

func _style(style):
    base := {"font": "Helvetica", "size": 10.0, "header": true, "header_font": null, "header_fill": "D9E2F3", "header_color": "000000", "border_color": "808080", "border_width": 0.5, "padding": 4.0, "zebra": "F2F2F2", "align": null, "text_color": "000000", "leading": null}
    return u.merge(base, style)

func _cell_lines(text, width, font, size):
    return pw.wrap_text(u.to_text(text), width, font, size)

func _col_widths(rows, col_widths, width, st):
    n := 0
    for r in rows:
        if len(r) > n:
            n = len(r)
    if col_widths != null:
        out := []
        for w in col_widths:
            append(out, to_float(w))
        while len(out) < n:
            append(out, 60.0)
        return out
    # largeur naturelle (ligne la plus longue) et minimale (mot le plus long) de chaque colonne
    font := pw.resolve_font(st["font"])
    bold := pw.resolve_font(st["font"], true)
    nat := u.repeat(20.0, n)
    mins := u.repeat(20.0, n)
    ri := 0
    for r in rows:
        f := bold if ri == 0 and st["header"] else font
        k := 0
        for v in r:
            w := 0.0
            mw := 0.0
            for line in string.split(u.to_text(v), "\n"):
                lw := pw.text_width(line, f, st["size"])
                if lw > w:
                    w = lw
                for word in string.split(line, " "):
                    ww := pw.text_width(word, f, st["size"])
                    if ww > mw:
                        mw = ww
            w = w + st["padding"] * 2.0
            mw = mw + st["padding"] * 2.0
            if w > nat[k]:
                nat[k] = w
            if mw > mins[k]:
                mins[k] = mw
            k = k + 1
        ri = ri + 1
    total := 0.0
    for w in nat:
        total = total + w
    if width == null or total <= width:
        return nat
    tmin := 0.0
    for w in mins:
        tmin = tmin + w
    out := []
    if tmin >= width:
        for w in mins:
            append(out, w * to_float(width) / tmin)
        return out
    extra := to_float(width) - tmin
    slack := total - tmin
    k := 0
    while k < n:
        append(out, mins[k] + (nat[k] - mins[k]) * extra / slack if slack > 0 else mins[k])
        k = k + 1
    return out

func measure(rows, col_widths, style=null):
    st := _style(style)
    lead := st["leading"] if st["leading"] != null else st["size"] * 1.2
    out := []
    r := 0
    for row in rows:
        hdr := r == 0 and st["header"]
        font := pw.resolve_font(st["header_font"] if hdr and st["header_font"] != null else st["font"], hdr and st["header_font"] == null, false)
        maxl := 1
        k := 0
        for v in row:
            w := col_widths[k] if k < len(col_widths) else 60.0
            nl := len(_cell_lines(v, w - st["padding"] * 2.0, font, st["size"]))
            if nl > maxl:
                maxl = nl
            k = k + 1
        append(out, to_float(maxl) * lead + st["padding"] * 2.0)
        r = r + 1
    return out

func fit_rows(heights, available, start):
    used := 0.0
    k := start
    while k < len(heights):
        if used + heights[k] > available and k > start:
            break
        used = used + heights[k]
        k = k + 1
    return k

func _align_for(st, col, value):
    al := st["align"]
    if al != null and col < len(al) and al[col] != null:
        return al[col]
    if u.is_number(value):
        return "right"
    return "left"

func draw_table(canvas, x0, top, rows, col_widths=null, style=null, width=null, row_start=0, row_end=null, repeat_header=false):
    st := _style(style)
    widths := _col_widths(rows, col_widths, width, st)
    heights := measure(rows, widths, st)
    lead := st["leading"] if st["leading"] != null else st["size"] * 1.2
    end := row_end if row_end != null else len(rows)
    order := []
    if repeat_header and row_start > 0 and st["header"] and len(rows) > 0:
        append(order, 0)
    k := row_start
    while k < end:
        append(order, k)
        k = k + 1
    total_w := 0.0
    for w in widths:
        total_w = total_w + w
    y := to_float(top)
    canvas.save_state()
    for ri in order:
        row := rows[ri]
        h := heights[ri]
        hdr := ri == 0 and st["header"]
        if hdr and st["header_fill"] != null:
            canvas.set_fill(st["header_fill"])
            canvas.rect(x0, y - h, total_w, h, true, false)
        elif not hdr and st["zebra"] != null and ri % 2 == 0:
            canvas.set_fill(st["zebra"])
            canvas.rect(x0, y - h, total_w, h, true, false)
        font := pw.resolve_font(st["header_font"] if hdr and st["header_font"] != null else st["font"], hdr and st["header_font"] == null, false)
        canvas.set_font(font, st["size"])
        color := st["header_color"] if hdr else st["text_color"]
        canvas.set_fill(color)
        cx := to_float(x0)
        ci := 0
        for v in row:
            w := widths[ci] if ci < len(widths) else 60.0
            lines := _cell_lines(v, w - st["padding"] * 2.0, font, st["size"])
            al := "left" if hdr else _align_for(st, ci, v)
            m := pw.font_metrics(font)
            ly := y - st["padding"] - to_float(m["ascent"]) * st["size"] / 1000.0
            for line in lines:
                if al == "right":
                    canvas.text(cx + w - st["padding"], ly, line, "right")
                elif al == "center":
                    canvas.text(cx + w / 2.0, ly, line, "center")
                else:
                    canvas.text(cx + st["padding"], ly, line)
                ly = ly - lead
            cx = cx + w
            ci = ci + 1
        y = y - h
    # bordures
    if st["border_color"] != null and st["border_width"] > 0:
        canvas.set_stroke(st["border_color"])
        canvas.set_line_width(st["border_width"])
        yy := to_float(top)
        canvas.line(x0, yy, x0 + total_w, yy)
        for ri in order:
            yy = yy - heights[ri]
            canvas.line(x0, yy, x0 + total_w, yy)
        xx := to_float(x0)
        canvas.line(xx, top, xx, yy)
        for w in widths:
            xx = xx + w
            canvas.line(xx, top, xx, yy)
    canvas.restore_state()
    return to_float(top) - y
