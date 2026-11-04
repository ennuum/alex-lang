# ALEX STANDARD LIBRARY — ui.view.wdata (interne)
#
# Composants de données : list_view, table (colonnes, tri), tree (nœuds dépliables). Seules les lignes visibles
# sont dessinées : des milliers de lignes restent fluides.

from core use len, type, to_int
from collections use append, contains_key, keys
use string as _s
use ui.view.util as _u
use ui.view.wbase as _b
from ui.view.wbase use Widget

# Base des listes : lignes de hauteur s.rh, sélection, défilement, barre, saisie rapide.
class RowsWidget extends Widget:
    func init():
        super.init()
        self.stretch_w = true
        self.stretch_h = true
        self.grow = 1

    func focusable(app, n):
        return true

    func height_for(app, n, lines):
        return lines * app.s.rh + 2 * app.s.lb + self.header_h(app, n)

    func header_h(app, n):
        return 0

    # Hauteur naturelle : le nombre de lignes, entre 3 et preferred.
    func natural_h(app, n, preferred):
        return self.height_for(app, n, _u.clamp(self.count(app, n), 3, preferred))

    # Nombre de lignes, texte d'une ligne (position d'affichage).
    func count(app, n):
        return 0

    func row_text(app, n, pos):
        return ""

    # Position affichée de la sélection, ou -1 ; et sélection à partir d'une position.
    func sel_pos(app, n):
        return -1

    func select_pos(app, n, pos):
        return null

    func activate_pos(app, n, pos):
        return null

    func body(app, n):
        s := app.s
        hh := self.header_h(app, n)
        return [n.x + s.lb, n.y + s.lb + hh, n.w - 2 * s.lb, _u.imax(0, n.h - 2 * s.lb - hh)]

    func visible(app, n):
        return _u.imax(1, self.body(app, n)[3] // app.s.rh)

    func top(app, n):
        total := self.count(app, n)
        vis := self.visible(app, n)
        return _u.clamp(_b.st_get(n.st, "top", 0), 0, _u.imax(0, total - vis))

    func reveal_pos(app, n, pos):
        n.st["top"] = _b.keep_visible(self.top(app, n), pos, self.visible(app, n))

    # Sélection visible à chaque image (sélection changée par le programme).
    func arrange(app, n):
        p := self.sel_pos(app, n)
        last := _b.st_get(n.st, "__last_sel", null)
        if p >= 0 and p != last:
            self.reveal_pos(app, n, p)
        n.st["__last_sel"] = p

    func paint_rows(app, n, paint_row):
        s := app.s
        focused := app.is_focused(n)
        _b.field_box(app, n, focused, "field")
        total := self.count(app, n)
        body := self.body(app, n)
        vis := self.visible(app, n)
        top := self.top(app, n)
        n.st["top"] = top
        bar := total > vis
        rw := body[2] - (s.sbw if bar else 0)
        sel := self.sel_pos(app, n)
        s.push_clip(body[0], body[1], body[2], body[3])
        i := 0
        while i < vis and top + i < total:
            pos := top + i
            y := body[1] + i * s.rh
            role := "text"
            if pos == sel:
                s.fill(body[0], y, rw, s.rh, "selection_focus" if focused else "selection")
                role = "selection_focus_text" if focused else "selection_text"
            elif app.is_hovered(n) and _b.st_get(n.st, "hover_row", -1) == pos and not s.cell:
                s.fill(body[0], y, rw, s.rh, "hover")
            paint_row(pos, body[0], y, rw, role)
            i += 1
        s.pop_clip()
        if bar:
            s.scrollbar(body[0] + body[2] - s.sbw, body[1], body[3], top / total, vis / total)
        if total == 0 and n.get("empty") != null:
            s.text(body[0] + s.px, body[1], _u.fit(s, n.get("empty"), body[2] - 2 * s.px), "muted")

    func key(app, n, ev):
        k := _b.key_of(ev)
        total := self.count(app, n)
        if total == 0:
            return false
        sel := self.sel_pos(app, n)
        if k == "enter":
            if sel >= 0:
                self.activate_pos(app, n, sel)
                return true
            return false
        nxt := _b.list_nav(k, total, sel if sel >= 0 else null, self.visible(app, n))
        if nxt == null:
            t := ev["text"] if ev["type"] == "key" else null
            if t != null and t != "" and t != " " and self.typeahead:
                i := 1
                while i <= total:
                    pos := (sel + i + total) % total
                    if _s.starts_with(_s.lower(self.row_text(app, n, pos)), _s.lower(t)):
                        self.reveal_pos(app, n, pos)
                        self.select_pos(app, n, pos)
                        return true
                    i += 1
            return false
        self.reveal_pos(app, n, nxt)
        if nxt != sel:
            self.select_pos(app, n, nxt)
        return true

    # Position sous (x, y) ; -1 hors des lignes.
    func pos_at(app, n, x, y):
        body := self.body(app, n)
        if y < body[1] or y >= body[1] + body[3]:
            return -1
        pos := self.top(app, n) + (y - body[1]) // app.s.rh
        if pos >= self.count(app, n):
            return -1
        return pos

    func on_bar(app, n, x):
        body := self.body(app, n)
        return self.count(app, n) > self.visible(app, n) and x >= body[0] + body[2] - app.s.sbw

    func mouse(app, n, ev):
        a := ev["action"]
        x := ev["x"]
        y := ev["y"]
        if a == "move":
            p := self.pos_at(app, n, x, y)
            changed := p != _b.st_get(n.st, "hover_row", -1)
            n.st["hover_row"] = p
            return changed and not app.s.cell
        if a == "drag" and _b.st_get(n.st, "bar_drag", false):
            body := self.body(app, n)
            n.st["top"] = _b.vscroll_click(y - body[1], body[3], self.count(app, n), self.visible(app, n))
            return true
        if a == "up":
            n.st["bar_drag"] = false
            return true
        if a != "down":
            return false
        if self.on_bar(app, n, x):
            body := self.body(app, n)
            n.st["bar_drag"] = true
            n.st["top"] = _b.vscroll_click(y - body[1], body[3], self.count(app, n), self.visible(app, n))
            return true
        if self.mouse_extra(app, n, ev):
            return true
        p := self.pos_at(app, n, x, y)
        if p < 0:
            return true
        if p != self.sel_pos(app, n):
            self.select_pos(app, n, p)
        if ev["clicks"] >= 2:
            self.activate_pos(app, n, p)
        return true

    func mouse_extra(app, n, ev):
        return false

    func wheel(app, n, ev):
        total := self.count(app, n)
        vis := self.visible(app, n)
        if total <= vis:
            return false
        n.st["top"] = _u.clamp(self.top(app, n) - ev["dy"] * 3, 0, total - vis)
        return true

# ---------------------------------------------------------------- list_view
class ListView extends RowsWidget:
    func init():
        super.init()
        self.typeahead = true

    func measure(app, n, max_w):
        s := app.s
        w := 0
        for it in n.get("items", []):
            w = _u.imax(w, s.text_width(it))
        return [_u.imin(w + 2 * s.px + s.sbw + 2 * s.lb, max_w), self.natural_h(app, n, 8)]

    func count(app, n):
        return len(n.get("items", []))

    func row_text(app, n, pos):
        return n.get("items", [])[pos]

    func sel_pos(app, n):
        return _b.controlled(n.st, "selected", n.get("selected", 0))

    func select_pos(app, n, pos):
        n.st["selected"] = pos
        app.call(n.get("on_select"), [pos])

    func activate_pos(app, n, pos):
        app.call(n.get("on_activate"), [pos])

    func paint(app, n):
        s := app.s
        items := n.get("items", [])

        func row(pos, x, y, w, role):
            s.text(x + s.px, _b.text_y(app, y, s.rh), _u.fit(s, items[pos], w - 2 * s.px), role)

        self.paint_rows(app, n, row)

    func text_of(n):
        return _s.join("\n", n.get("items", []))

# ---------------------------------------------------------------- table
func _columns(n):
    out := []
    for c in n.get("columns", []):
        if type(c) == "dict":
            d := {"title": str(_b.st_get(c, "title", "")), "width": _b.st_get(c, "width", null), "align": _b.st_get(c, "align", "left")}
            append(out, d)
        else:
            append(out, {"title": str(c), "width": null, "align": "left"})
    return out

func _cell(row, i):
    if type(row) == "list" and i < len(row):
        return row[i]
    if type(row) == "tuple" and i < len(row):
        return row[i]
    return null

class Table extends RowsWidget:
    func init():
        super.init()
        self.typeahead = true

    func header_h(app, n):
        return app.s.rh + app.s.hsep

    func _order(app, n):
        rows := n.get("rows", [])
        col := _b.st_get(n.st, "sort", null)
        if col == null or not n.get("sortable", true):
            return [i for i in 0..len(rows)]
        desc := _b.st_get(n.st, "desc", false)
        cache := _b.st_get(n.st, "__order", null)
        if cache != null and cache[0] == col and cache[1] == desc and cache[2] == rows:
            return cache[3]

        func key(r):
            return _cell(r, col)

        order := _u.sorted_indices(rows, key, desc)
        n.st["__order"] = [col, desc, rows, order]
        return order

    # Largeurs des colonnes pour une largeur intérieure w.
    func _widths(app, n, w):
        s := app.s
        cols := _columns(n)
        rows := n.get("rows", [])
        out := []
        total := 0
        for i in 0..len(cols):
            c := cols[i]
            cw := 0
            if c["width"] != null:
                cw = c["width"] * s.cw + 2 * s.px
            else:
                cw = s.text_width(c["title"], "bold") + s.glyph_width("sort_up") + 2 * s.px
                k := 0
                for r in rows:
                    if k >= 200:
                        break
                    cw = _u.imax(cw, s.text_width(_u.show(_cell(r, i))) + 2 * s.px)
                    k += 1
                cw = _u.imin(cw, 40 * s.cw)
            append(out, cw)
            total += cw
        if len(out) > 0:
            if total < w:
                out[len(out) - 1] += w - total
            elif total > w:
                # réduire les colonnes automatiques, de la dernière à la première
                over := total - w
                i := len(out) - 1
                while i >= 0 and over > 0:
                    if cols[i]["width"] == null:
                        can := out[i] - 4 * s.cw
                        if can > 0:
                            take := _u.imin(can, over)
                            out[i] -= take
                            over -= take
                    i -= 1
        return out

    func measure(app, n, max_w):
        s := app.s
        ws := self._widths(app, n, 0)
        w := 0
        for x in ws:
            w += x
        return [_u.imin(w + s.sbw + 2 * s.lb, max_w), self.natural_h(app, n, 10)]

    func count(app, n):
        return len(n.get("rows", []))

    func row_text(app, n, pos):
        order := self._order(app, n)
        return _u.show(_cell(n.get("rows", [])[order[pos]], 0))

    func sel_pos(app, n):
        sel := _b.controlled(n.st, "selected", n.get("selected", 0))
        order := self._order(app, n)
        i := 0
        for o in order:
            if o == sel:
                return i
            i += 1
        return -1

    func select_pos(app, n, pos):
        idx := self._order(app, n)[pos]
        n.st["selected"] = idx
        app.call(n.get("on_select"), [idx])

    func activate_pos(app, n, pos):
        app.call(n.get("on_activate"), [self._order(app, n)[pos]])

    func paint(app, n):
        s := app.s
        cols := _columns(n)
        rows := n.get("rows", [])
        order := self._order(app, n)
        total := len(rows)
        vis := self.visible(app, n)
        bar := total > vis
        inner := n.w - 2 * s.lb - (s.sbw if bar else 0)
        widths := self._widths(app, n, inner)

        func row(pos, x, y, w, role):
            r := rows[order[pos]]
            cx := x
            i := 0
            for c in cols:
                cw := widths[i]
                txt := _u.fit(s, _u.show(_cell(r, i)), cw - 2 * s.px)
                tx := cx + s.px
                if c["align"] == "right":
                    tx = cx + cw - s.px - s.text_width(txt)
                elif c["align"] == "center":
                    tx = cx + (cw - s.text_width(txt)) // 2
                s.text(tx, _b.text_y(app, y, s.rh), txt, role)
                cx += cw
                i += 1

        self.paint_rows(app, n, row)
        # entête
        hx := n.x + s.lb
        hy := n.y + s.lb
        s.fill(hx, hy, n.w - 2 * s.lb, s.rh, "header")
        sort := _b.st_get(n.st, "sort", null)
        i := 0
        cx := hx
        for c in cols:
            cw := widths[i]
            gl := 0
            if sort == i:
                gl = s.glyph_width("sort_up")
            title := _u.fit(s, c["title"], cw - 2 * s.px - gl)
            ty := _b.text_y(app, hy, s.rh, "bold")
            s.text(cx + s.px, ty, title, "header_text", "bold")
            if sort == i:
                s.glyph(cx + s.px + s.text_width(title, "bold"), ty, "sort_down" if _b.st_get(n.st, "desc", false) else "sort_up", "accent")
            if i > 0 and not s.cell:
                s.vline(cx, hy + 4, s.rh - 8, "border")
            cx += cw
            i += 1
        if s.hsep > 0:
            s.hline(hx, hy + s.rh, n.w - 2 * s.lb, "border")

    func _sort_by(n, col):
        if _b.st_get(n.st, "sort", null) == col:
            if _b.st_get(n.st, "desc", false):
                n.st["sort"] = null
                n.st["desc"] = false
            else:
                n.st["desc"] = true
        else:
            n.st["sort"] = col
            n.st["desc"] = false

    func key(app, n, ev):
        k := _b.key_of(ev)
        ncol := len(n.get("columns", []))
        if n.get("sortable", true) and (k == "s" or k == "S"):
            col := _b.st_get(n.st, "sort", null)
            if k == "S":
                if col != null:
                    n.st["desc"] = not _b.st_get(n.st, "desc", false)
                return true
            if col == null:
                n.st["sort"] = 0
            elif col + 1 < ncol:
                n.st["sort"] = col + 1
            else:
                n.st["sort"] = null
            n.st["desc"] = false
            return true
        return super.key(app, n, ev)

    func mouse_extra(app, n, ev):
        s := app.s
        hy := n.y + s.lb
        if ev["y"] < hy or ev["y"] >= hy + s.rh:
            return false
        if not n.get("sortable", true):
            return true
        total := len(n.get("rows", []))
        bar := total > self.visible(app, n)
        widths := self._widths(app, n, n.w - 2 * s.lb - (s.sbw if bar else 0))
        cx := n.x + s.lb
        i := 0
        for w in widths:
            if ev["x"] >= cx and ev["x"] < cx + w:
                self._sort_by(n, i)
            cx += w
            i += 1
        return true

    func text_of(n):
        return _s.join(" ", [c["title"] for c in _columns(n)])

# ---------------------------------------------------------------- tree
func tree_label(item):
    if type(item) == "dict":
        return str(_b.st_get(item, "label", ""))
    return str(item)

func tree_kids(item):
    if type(item) == "dict":
        k := _b.st_get(item, "children", null)
        if k != null:
            return k
    return []

func tree_id(item, path):
    if type(item) == "dict" and contains_key(item, "id"):
        return str(item["id"])
    return path

class Tree extends RowsWidget:
    func init():
        super.init()
        self.typeahead = true

    # Lignes visibles : [profondeur, nœud, identifiant, a des enfants].
    func rows(app, n):
        if not contains_key(n.st, "expanded"):
            n.st["expanded"] = {}
        out := []
        self._flatten(n.get("nodes", []), 0, "", n.st["expanded"], out)
        return out

    func _flatten(items, depth, prefix, expanded, out):
        i := 0
        for it in items:
            path := prefix + str(i)
            ident := tree_id(it, path)
            kids := tree_kids(it)
            if not contains_key(expanded, ident):
                expanded[ident] = type(it) == "dict" and _b.st_get(it, "expanded", false) == true
            append(out, [depth, it, ident, len(kids) > 0])
            if len(kids) > 0 and expanded[ident]:
                self._flatten(kids, depth + 1, path + "/", expanded, out)
            i += 1

    func measure(app, n, max_w):
        s := app.s
        w := 0
        for r in self.rows(app, n):
            w = _u.imax(w, r[0] * s.indent + s.glyph_width("tri_right") + s.cw + s.text_width(tree_label(r[1])))
        return [_u.imin(w + 2 * s.px + s.sbw + 2 * s.lb, max_w), self.natural_h(app, n, 10)]

    func count(app, n):
        return len(self.rows(app, n))

    func row_text(app, n, pos):
        return tree_label(self.rows(app, n)[pos][1])

    func sel_pos(app, n):
        sel := _b.st_get(n.st, "selected", null)
        rows := self.rows(app, n)
        if sel == null:
            return -1
        i := 0
        for r in rows:
            if r[2] == sel:
                return i
            i += 1
        return -1

    func select_pos(app, n, pos):
        r := self.rows(app, n)[pos]
        n.st["selected"] = r[2]
        app.call(n.get("on_select"), [r[1]])

    func activate_pos(app, n, pos):
        r := self.rows(app, n)[pos]
        if r[3] and n.get("on_activate") == null:
            self._toggle(n, r)
        else:
            app.call(n.get("on_activate"), [r[1]])

    func _toggle(n, r):
        exp := n.st["expanded"]
        exp[r[2]] = not exp[r[2]]

    func paint(app, n):
        s := app.s
        rows := self.rows(app, n)
        exp := n.st["expanded"]

        func row(pos, x, y, w, role):
            r := rows[pos]
            gx := x + s.px + r[0] * s.indent
            ty := _b.text_y(app, y, s.rh)
            if r[3]:
                s.glyph(gx, ty, "tri_down" if exp[r[2]] else "tri_right", "muted" if role == "text" else role)
            lx := gx + s.glyph_width("tri_right") + s.cw
            s.text(lx, ty, _u.fit(s, tree_label(r[1]), x + w - lx), role)

        self.paint_rows(app, n, row)

    func key(app, n, ev):
        k := _b.key_of(ev)
        rows := self.rows(app, n)
        pos := self.sel_pos(app, n)
        if pos >= 0 and (k == "right" or k == "left" or k == "space"):
            r := rows[pos]
            opened := r[3] and n.st["expanded"][r[2]]
            if k == "space":
                if r[3]:
                    self._toggle(n, r)
                return true
            if k == "right":
                if r[3] and not opened:
                    self._toggle(n, r)
                elif r[3] and pos + 1 < len(rows):
                    self.reveal_pos(app, n, pos + 1)
                    self.select_pos(app, n, pos + 1)
                return true
            if r[3] and opened:
                self._toggle(n, r)
                return true
            j := pos - 1
            while j >= 0 and rows[j][0] >= r[0]:
                j -= 1
            if j >= 0:
                self.reveal_pos(app, n, j)
                self.select_pos(app, n, j)
            return true
        return super.key(app, n, ev)

    func mouse_extra(app, n, ev):
        s := app.s
        p := self.pos_at(app, n, ev["x"], ev["y"])
        if p < 0:
            return false
        r := self.rows(app, n)[p]
        body := self.body(app, n)
        gx := body[0] + s.px + r[0] * s.indent
        if r[3] and ev["x"] >= gx and ev["x"] < gx + s.glyph_width("tri_right") + s.cw // 2:
            self._toggle(n, r)
            if p != self.sel_pos(app, n):
                self.select_pos(app, n, p)
            return true
        if r[3] and ev["clicks"] >= 2 and n.get("on_activate") == null:
            self._toggle(n, r)
            return true
        return false

    func text_of(n):
        return _s.join(" ", [tree_label(x) for x in n.get("nodes", [])])
