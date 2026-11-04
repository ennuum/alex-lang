# ALEX UI V1.3 — Champ de saisie (text_field) et zone de texte multi-ligne (text_area)
#
# Édition complète : curseur et sélection mesurés sur les glyphes réels (ui.text), sélection à la souris
# (glisser, double-clic = mot, triple-clic = ligne), clavier (flèches, Ctrl+flèches, Début/Fin, PgUp/PgDn,
# Maj pour étendre), presse-papiers (Ctrl+C/X/V), annuler/rétablir (Ctrl+Z / Ctrl+Y), défilement synchronisable
# (protocole ui.scroll). `w["value"]` est la valeur publique : l'écrire (liaison d'état) met l'éditeur à jour.
# Callbacks : on_change(w, valeur), on_submit(w) (Entrée en mono-ligne).
from core use type, len, clamp, to_int
use collections
use ui.widgets.widget as base
use ui.widgets.gfx as gfx
use ui.paint as paint
use ui.canvas as canvas
use ui.text as text
use ui.edit as edit
use ui.scroll as scroll
use ui.clipboard as clip

const PAD_X := 10.0
const PAD_Y := 8.0

func _make(kind, value, placeholder, x, y, width, height, multiline):
    w := base.create(kind, x, y, width, height)
    w["editor"] = edit.create(value, multiline)
    w["value"] = value
    w["placeholder"] = placeholder
    w["multiline"] = multiline
    w["readonly"] = false
    w["caret_visible"] = true
    w["selecting"] = false
    w["view_w"] = width
    w["view_h"] = height
    w["on_change"] = null
    w["on_submit"] = null
    w["_mt"] = null
    w["bar_hover"] = ""
    return w

func create(value="", placeholder="", x=0.0, y=0.0, width=260.0, height=40.0):
    return _make("text_field", value, placeholder, x, y, width, height, false)

func create_area(value="", placeholder="", x=0.0, y=0.0, width=360.0, height=200.0):
    return _make("text_area", value, placeholder, x, y, width, height, true)

# ---- valeur publique <-> éditeur ----
func sync(w):
    ed := w["editor"]
    if w["value"] != ed["text"]:
        edit.set_text(ed, w["value"])
    return ed

func set_text(w, s):
    w["value"] = s
    return sync(w)

func get_text(w):
    return sync(w)["text"]

# ---- métriques / géométrie ----
func line_h(t):
    return text.line_height(t["font_size"])

func metrics(w, t):
    ed := sync(w)
    fs := t["font_size"]
    lh := line_h(t)
    w["view_w"] = w["width"]
    w["view_h"] = w["height"]
    if w["_mt"] == null or w["_mt"] != ed["text"]:
        w["_mt"] = ed["text"]
        mw := 0.0
        if w["multiline"]:
            for ln in text.lines(ed["text"]):
                lw := text.width(ln, fs)
                if lw > mw:
                    mw = lw
        else:
            mw = text.width(ed["text"], fs)
        w["_mw"] = mw
    w["content_width"] = w["_mw"] + 2 * PAD_X + 2.0
    if w["multiline"]:
        w["content_height"] = text.line_count(ed["text"]) * lh + 2 * PAD_Y
    else:
        w["content_height"] = w["height"]
    scroll.set(w, w["scroll_x"], w["scroll_y"])
    return lh

# Origine du texte (coin haut-gauche de la ligne 0) en coordonnées du widget.
func origin_x(w):
    return w["x"] + PAD_X - w["scroll_x"]

func origin_y(w, lh):
    if w["multiline"]:
        return w["y"] + PAD_Y - w["scroll_y"]
    return w["y"] + (w["height"] - lh) * 0.5

# Position du curseur : [x, y_haut] en coordonnées du widget.
func caret_pos(w, t):
    ed := w["editor"]
    lh := line_h(t)
    c := ed["caret"]
    ls := text.line_start(ed["text"], c)
    cx := origin_x(w) + text.prefix_width(text.sub(ed["text"], ls, len(ed["text"])), c - ls, t["font_size"])
    cy := origin_y(w, lh) + text.line_of(ed["text"], c) * lh
    return [cx, cy]

# Indice de caractère sous le point (px, py) (coordonnées du widget).
func index_from_point(w, t, px, py):
    ed := sync(w)
    lh := line_h(t)
    line := 0
    if w["multiline"]:
        line = to_int((py - origin_y(w, lh)) / lh)
        if py - origin_y(w, lh) < 0:
            line = 0
        total := text.line_count(ed["text"])
        line = clamp(line, 0, total - 1)
    st := text.index_of_line(ed["text"], line)
    en := text.line_end(ed["text"], st)
    return st + text.index_at(text.sub(ed["text"], st, en), px - origin_x(w), t["font_size"])

func ensure_caret_visible(w, t):
    metrics(w, t)
    ed := w["editor"]
    lh := line_h(t)
    c := ed["caret"]
    ls := text.line_start(ed["text"], c)
    cx := PAD_X + text.prefix_width(text.sub(ed["text"], ls, len(ed["text"])), c - ls, t["font_size"])
    cy := PAD_Y + text.line_of(ed["text"], c) * lh
    if not w["multiline"]:
        scroll.to_view(w, cx, 0.0, 1.0, w["height"], PAD_X)
    else:
        scroll.to_view(w, cx, cy - PAD_Y, 1.0, lh + 2 * PAD_Y, PAD_X)
    return null

# ---- interaction pointeur ----
# count : rang du clic (1 simple, 2 mot, 3 ligne) ; extend : Maj enfoncé.
func press(w, t, px, py, count, extend):
    sync(w)
    ed := w["editor"]
    i := index_from_point(w, t, px, py)
    if count == 2:
        edit.select_word(ed, i)
    elif count >= 3:
        edit.select_line(ed, i)
    else:
        edit.set_caret(ed, i, extend)
    w["selecting"] = true
    ensure_caret_visible(w, t)
    return null

func drag_to(w, t, px, py):
    ed := w["editor"]
    # défilement automatique quand le pointeur sort de la zone
    if px < w["x"] + PAD_X:
        scroll.by(w, -12.0, 0.0)
    elif px > w["x"] + w["width"] - PAD_X:
        scroll.by(w, 12.0, 0.0)
    if w["multiline"]:
        if py < w["y"] + PAD_Y:
            scroll.by(w, 0.0, -line_h(t))
        elif py > w["y"] + w["height"] - PAD_Y:
            scroll.by(w, 0.0, line_h(t))
    edit.set_caret(ed, index_from_point(w, t, px, py), true)
    return null

func release(w):
    w["selecting"] = false
    return null

# ---- interaction clavier ----
# Retourne 0 : non géré · 1 : géré · 2 : géré et texte modifié.
func key(w, t, vk, mods, typed):
    ed := sync(w)
    ctrl := mods % 4 >= 2
    alt := mods % 2 == 1
    shift := mods % 8 >= 4
    changed := false
    handled := false
    if ctrl and not alt:
        if vk == 65:
            edit.select_all(ed)
            handled = true
        elif vk == 67 or vk == 45:
            if edit.has_selection(ed):
                clip.set_text(edit.selected_text(ed))
            handled = true
        elif vk == 88:
            if edit.has_selection(ed):
                clip.set_text(edit.selected_text(ed))
                if not w["readonly"]:
                    changed = edit.delete_selection(ed)
            handled = true
        elif vk == 86:
            if not w["readonly"]:
                s := clip.get_text()
                if s != null and s != "":
                    changed = edit.insert(ed, s)
            handled = true
        elif vk == 90 and not shift:
            if not w["readonly"]:
                changed = edit.undo(ed)
            handled = true
        elif vk == 89 or (vk == 90 and shift):
            if not w["readonly"]:
                changed = edit.redo(ed)
            handled = true
    if not handled:
        if vk == 37:
            edit.move(ed, "word_left" if ctrl else "left", shift, t["font_size"])
            handled = true
        elif vk == 39:
            edit.move(ed, "word_right" if ctrl else "right", shift, t["font_size"])
            handled = true
        elif vk == 38:
            edit.move(ed, "up", shift, t["font_size"])
            handled = true
        elif vk == 40:
            edit.move(ed, "down", shift, t["font_size"])
            handled = true
        elif vk == 36:
            edit.move(ed, "doc_start" if ctrl else "home", shift, t["font_size"])
            handled = true
        elif vk == 35:
            edit.move(ed, "doc_end" if ctrl else "end", shift, t["font_size"])
            handled = true
        elif (vk == 33 or vk == 34) and w["multiline"]:
            n := to_int(w["view_h"] / line_h(t)) - 1
            if n < 1:
                n = 1
            i := 0
            while i < n:
                edit.move(ed, "up" if vk == 33 else "down", shift, t["font_size"])
                i += 1
            handled = true
        elif vk == 8:
            if not w["readonly"]:
                changed = edit.backspace(ed, ctrl)
            handled = true
        elif vk == 46:
            if not w["readonly"]:
                changed = edit.delete(ed, ctrl)
            handled = true
        elif vk == 13:
            if w["multiline"]:
                if not w["readonly"]:
                    changed = edit.insert(ed, "\n", "paste")
                handled = true
            elif w["on_submit"] != null:
                w["on_submit"](w)
                handled = true
        elif typed != null and typed != "" and not ctrl and not alt:
            if not w["readonly"]:
                changed = edit.insert(ed, typed)
            handled = true
    if not handled:
        return 0
    w["value"] = ed["text"]
    ensure_caret_visible(w, t)
    if changed and w["on_change"] != null:
        w["on_change"](w, ed["text"])
    if changed:
        return 2
    return 1

# ---- rendu ----
func _line_x(w, t, ed, ln_start, idx):
    return origin_x(w) + text.prefix_width(text.sub(ed["text"], ln_start, len(ed["text"])), idx - ln_start, t["font_size"])

func draw(w, c, t):
    if not w["visible"]:
        return null
    ed := sync(w)
    lh := metrics(w, t)
    fs := t["font_size"]
    x := w["x"]
    y := w["y"]
    focused := w["focused"]
    vs := base.visual_state(w)
    border := base.mix(t["border"], t["muted"], vs[0] * 0.6)
    if focused:
        border = t["primary"]
    bg := t["surface"]
    if not w["enabled"] or w["readonly"]:
        bg = base.mix(t["surface"], t["surface_pressed"], 0.6)
    canvas.round_rect(c, x, y, w["width"], w["height"], t["radius"], paint.fill(bg, w["opacity"]))
    canvas.round_rect(c, x, y, w["width"], w["height"], t["radius"], paint.stroke(border, 1.5 if focused else 1.0, w["opacity"]))
    gfx.push(c, x + 3, y + 3, w["width"] - 6, w["height"] - 6)
    ox := origin_x(w)
    oy := origin_y(w, lh)
    textcol := t["text"]
    if not w["enabled"]:
        textcol = t["muted"]
    lines := text.lines(ed["text"])
    first := 0
    last := len(lines) - 1
    if w["multiline"]:
        first = clamp(to_int(w["scroll_y"] / lh), 0, len(lines) - 1)
        last = clamp(first + to_int(w["view_h"] / lh) + 2, 0, len(lines) - 1)
    # sélection
    if edit.has_selection(ed):
        sel := edit.selection(ed)
        selcol := t["selection"]
        if not focused:
            selcol = {"r": selcol["r"], "g": selcol["g"], "b": selcol["b"], "a": clamp(to_int(selcol["a"] / 2), 10, 255)}
        i := first
        while i <= last:
            ls := text.index_of_line(ed["text"], i)
            le := ls + len(lines[i])
            a := clamp(sel[0], ls, le)
            b := clamp(sel[1], ls, le)
            extend_nl := sel[0] <= le and sel[1] > le
            if b > a or extend_nl:
                x0 := _line_x(w, t, ed, ls, a)
                x1 := _line_x(w, t, ed, ls, b)
                if extend_nl:
                    x1 = x1 + fs * 0.4
                canvas.fill_rect(c, x0, oy + i * lh, x1 - x0, lh, paint.fill(selcol))
            i += 1
    # texte / placeholder
    if ed["text"] == "":
        if w["placeholder"] != "":
            canvas.text(c, w["placeholder"], ox, oy, paint.fill(t["muted"]), t["font"], fs)
    else:
        i := first
        while i <= last:
            if lines[i] != "":
                canvas.text(c, lines[i], ox, oy + i * lh, paint.fill(textcol, w["opacity"]), t["font"], fs)
            i += 1
    # curseur
    if focused and w["caret_visible"] and w["enabled"]:
        cp := caret_pos(w, t)
        canvas.fill_rect(c, cp[0], cp[1], 1.6, lh, paint.fill(textcol))
    gfx.pop(c)
    if w["multiline"]:
        scroll.draw_bars(c, w, t)
    return null
