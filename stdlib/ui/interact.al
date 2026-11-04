# ALEX UI V1.3 — Contrôleur d'interaction pour les widgets modernes (canvas)
#
# Un contrôleur (create) relie un arbre de widgets à la fenêtre : il reçoit les événements bruts
# (handle), reconnaît les gestes (ui.gesture), applique le focus clavier, le survol animé, la capture de
# la souris, le glisser-déposer entre composants, le défilement (molette, barres, clavier), l'édition de
# texte, les curseurs, puis dessine l'arbre avec ses surcouches (draw / render).
#
# Callbacks des widgets (tous facultatifs ; fn(widget, event) sauf mention) :
#   on_click(w)                       clic gauche complet (bouton, case à cocher...) — signature historique
#   on_press, on_release, on_double_click, on_context (clic droit), on_long_press, on_hover, on_hover_end
#   on_wheel(w, ev) -> true pour consommer · on_key(w, ev) -> true pour consommer · on_escape(w)
#   on_drag_start(w, ev) -> false pour annuler · on_drag(w, ev) · on_drag_end(w, session)
#   glisser-déposer : w["draggable"], w["drag_data"], w["drag_type"] ; cible : w["droppable"], w["drop_accept"]
#   (liste de types ou fn(cible, session) -> bool) · on_drag_enter / on_drag_over / on_drag_leave / on_drop(w, session)
# Le temps vient de now(ctl) : set_time(ctl, t) rend les tests déterministes.
from core use type, len, clamp, to_int, is_function
use collections
use os as _os
use _native_ui as _native
use ui.canvas as canvas
use ui.paint as paint
use ui.gesture as gesture
use ui.scroll as scroll
use ui.layout as layout
use ui.widgets.widget as base
use ui.widgets.gfx as gfx
use ui.widgets.theme as _theme
use ui.widgets.button as _button
use ui.widgets.label as _label
use ui.widgets.card as _card
use ui.widgets.checkbox as _checkbox
use ui.widgets.progress as _progress
use ui.widgets.text_input as ti
use ui.widgets.gutter as _gutter
use ui.tween.core as _tw
use ui.tween.animator as _anim
use ui.state.store as _state

const VERSION := "1.3.0"
const HOVER_TIME := 0.14
const PRESS_TIME := 0.07
const DRAG_RETURN_TIME := 0.20
const CARET_PERIOD := 1.0
const CARET_ON := 0.55
const AUTOSCROLL_EDGE := 28.0
const AUTOSCROLL_SPEED := 520.0

func create(root, theme=null, win=null, canvas_obj=null):
    t := theme
    if t == null:
        t = _theme.modern()
    return {"kind": "interact", "root": root, "theme": t, "win": win, "canvas": canvas_obj,
            "g": gesture.create(), "anim": _anim.create(), "fake_now": null,
            "focus": null, "focus_visible": false, "hover": null, "press": null, "press_target": null,
            "release_hit": null, "capture": null, "bar_drag": null, "drag": null, "trap": null,
            "cursor": "arrow", "caret_t": 0.0, "caret_on": true, "dirty": true,
            "px": 0, "py": 0, "mods": 0, "w": root["width"], "h": root["height"], "auto_t": null}

# ---------------------------------------------------------------- temps
func now(ctl):
    if ctl["fake_now"] != null:
        return ctl["fake_now"]
    return _os.monotonic_time()

# Fixe l'horloge du contrôleur (tests) ; null revient à l'horloge réelle.
func set_time(ctl, t):
    ctl["fake_now"] = t
    return t

# ---------------------------------------------------------------- arbre : coordonnées
# Décalage cumulé des scroll_view ancêtres : coordonnées fenêtre = coordonnées de mise en page - décalage.
func content_offset(w):
    ox := 0.0
    oy := 0.0
    p := w["parent"]
    while p != null:
        if p["kind"] == "scroll_view":
            ox += p["scroll_x"]
            oy += p["scroll_y"]
        p = p["parent"]
    return [ox, oy]

# Point fenêtre -> espace du widget (même espace que w["x"], w["y"]).
func to_local(w, x, y):
    o := content_offset(w)
    return [x + o[0], y + o[1]]

# Rectangle du widget en coordonnées fenêtre : [x, y, largeur, hauteur].
func window_rect(w):
    o := content_offset(w)
    return [w["x"] - o[0], w["y"] - o[1], w["width"], w["height"]]

func _is_under(a, b):
    # true si a est b ou un ancêtre de b
    p := b
    while p != null:
        if p["uid"] == a["uid"]:
            return true
        p = p["parent"]
    return false

func _chain_ok(w):
    p := w
    while p != null:
        if not p["visible"] or not p["enabled"]:
            return false
        p = p["parent"]
    return true

# ---------------------------------------------------------------- hit-test
func _hit(w, x, y, skip):
    if not w["visible"]:
        return null
    if skip != null and w["uid"] == skip["uid"]:
        return null
    inside := x >= w["x"] and x < w["x"] + w["width"] and y >= w["y"] and y < w["y"] + w["height"]
    kids := w["children"]
    if w["kind"] == "scroll_view":
        if not inside:
            return null
        if scroll.hit_bar(w, x, y) != "":
            return w
        cx := x + w["scroll_x"]
        cy := y + w["scroll_y"]
        i := len(kids) - 1
        while i >= 0:
            h := _hit(kids[i], cx, cy, skip)
            if h != null:
                return h
            i -= 1
        return w
    i := len(kids) - 1
    while i >= 0:
        h := _hit(kids[i], x, y, skip)
        if h != null:
            return h
        i -= 1
    if inside:
        return w
    return null

# Widget le plus haut sous le point fenêtre (x, y) ; null si aucun.
func hit_test(ctl, x, y):
    return _hit(ctl["root"], x, y, null)

# ---------------------------------------------------------------- catégories de widgets
func _is_text(w):
    return w["kind"] == "text_field" or w["kind"] == "text_area"

func _has_cb(w):
    for name in ["on_click", "on_press", "on_double_click", "on_context", "on_long_press", "on_hover", "on_hover_end"]:
        if w[name] != null:
            return true
    return w["draggable"] or w["droppable"]

func _hoverable(w):
    k := w["kind"]
    return k == "button" or k == "checkbox" or _is_text(w) or _has_cb(w)

func _hover_target(w):
    p := w
    while p != null:
        if _hoverable(p):
            return p
        p = p["parent"]
    return null

func _bubble(w, name):
    p := w
    while p != null:
        if p[name] != null:
            return p
        p = p["parent"]
    return null

func is_focusable(w):
    if not w["visible"] or not w["enabled"]:
        return false
    f := w["focusable"]
    if f != null:
        return f
    k := w["kind"]
    if k == "button" or k == "checkbox" or _is_text(w):
        return true
    if k == "scroll_view":
        return scroll.max_y(w) > 0 or scroll.max_x(w) > 0
    return false

func _nearest_focusable(w):
    p := w
    while p != null:
        if is_focusable(p):
            return p
        p = p["parent"]
    return null

# ---------------------------------------------------------------- focus clavier
func _collect(w, out, trap_ok):
    if not w["visible"] or not w["enabled"]:
        return null
    if is_focusable(w):
        collections.append(out, w)
    for ch in w["children"]:
        _collect(ch, out, trap_ok)
    return null

func _concat(a, b):
    out := []
    for x in a:
        collections.append(out, x)
    for x in b:
        collections.append(out, x)
    return out

# Widgets focalisables dans l'ordre de tabulation : tab_index > 0 croissant, puis l'ordre de l'arbre.
func focus_list(ctl):
    start := ctl["root"]
    if ctl["trap"] != null:
        start = ctl["trap"]
    items := []
    _collect(start, items, true)
    pos := []
    zero := []
    for w in items:
        if w["tab_index"] > 0:
            i := 0
            while i < len(pos) and pos[i]["tab_index"] <= w["tab_index"]:
                i += 1
            collections.insert(pos, i, w)
        else:
            collections.append(zero, w)
    return _concat(pos, zero)

func _reveal(ctl, w):
    # Fait défiler les scroll_view ancêtres pour montrer w (coordonnées de mise en page).
    p := w["parent"]
    while p != null:
        if p["kind"] == "scroll_view":
            scroll.to_view(p, w["x"] - p["x"], w["y"] - p["y"], w["width"], w["height"], 8.0)
        p = p["parent"]
    return null

# Donne le focus à w (null = aucun). visible : afficher l'anneau de focus (navigation clavier).
func set_focus(ctl, w, visible=false):
    old := ctl["focus"]
    if old != null and w != null and old["uid"] == w["uid"]:
        if ctl["focus_visible"] != visible:
            ctl["focus_visible"] = visible
            ctl["dirty"] = true
        return false
    if old != null:
        base.blur(old)
        old["selecting"] = false
    ctl["focus"] = w
    if w != null:
        base.focus(w)
        _reveal(ctl, w)
    ctl["focus_visible"] = visible and w != null
    ctl["caret_t"] = now(ctl)
    ctl["caret_on"] = true
    ctl["dirty"] = true
    return true

func blur(ctl):
    return set_focus(ctl, null)

# Tab / Maj+Tab : focalise le suivant / précédent (boucle). Retourne false s'il n'y a rien à focaliser.
func focus_next(ctl, reverse=false):
    items := focus_list(ctl)
    n := len(items)
    if n == 0:
        return false
    cur := -1
    i := 0
    while i < n:
        if ctl["focus"] != null and items[i]["uid"] == ctl["focus"]["uid"]:
            cur = i
        i += 1
    nxt := 0
    if cur < 0:
        if reverse:
            nxt = n - 1
    elif reverse:
        nxt = (cur - 1 + n) % n
    else:
        nxt = (cur + 1) % n
    set_focus(ctl, items[nxt], true)
    return true

# Navigation spatiale aux flèches : dir = "left" | "right" | "up" | "down".
func focus_move(ctl, dir):
    cur := ctl["focus"]
    if cur == null:
        return false
    cr := window_rect(cur)
    cx := cr[0] + cr[2] / 2.0
    cy := cr[1] + cr[3] / 2.0
    best := null
    best_score := 0.0
    for w in focus_list(ctl):
        if w["uid"] == cur["uid"]:
            continue
        r := window_rect(w)
        dx := r[0] + r[2] / 2.0 - cx
        dy := r[1] + r[3] / 2.0 - cy
        main := 0.0
        side := 0.0
        if dir == "right":
            main = dx
            side = dy
        elif dir == "left":
            main = 0.0 - dx
            side = dy
        elif dir == "down":
            main = dy
            side = dx
        else:
            main = 0.0 - dy
            side = dx
        if main <= 1.0:
            continue
        if side < 0:
            side = 0.0 - side
        score := main + 2.0 * side
        if best == null or score < best_score:
            best = w
            best_score = score
    if best == null:
        return false
    set_focus(ctl, best, true)
    return true

# Verrouille la navigation clavier dans un sous-arbre (fenêtre modale) ; null relâche.
func set_trap(ctl, w):
    ctl["trap"] = w
    if w != null:
        items := focus_list(ctl)
        if len(items) > 0:
            set_focus(ctl, items[0], true)
    return null

# ---------------------------------------------------------------- animations (survol, appui)
func _animate(ctl, w, prop, value, duration):
    _anim.play(ctl["anim"], _tw.tween(_tw.target_dict(w, prop), value + 0.0, duration, null, "ease_out"))
    ctl["dirty"] = true
    return null

func _set_hover(ctl, target, ev):
    old := ctl["hover"]
    if old == null and target == null:
        return false
    if old != null and target != null and old["uid"] == target["uid"]:
        return false
    if old != null:
        old["hovered"] = false
        _animate(ctl, old, "hover_t", 0.0, HOVER_TIME)
        if old["on_hover_end"] != null:
            old["on_hover_end"](old, ev)
    ctl["hover"] = target
    if target != null:
        target["hovered"] = true
        target["hover_anim"] = true
        _animate(ctl, target, "hover_t", 1.0, HOVER_TIME)
        if target["on_hover"] != null:
            target["on_hover"](target, ev)
    ctl["dirty"] = true
    return true

# ---------------------------------------------------------------- curseur de la souris
func _cursor_for(ctl, hit):
    d := ctl["drag"]
    if d != null and d["active"]:
        if d["over"] != null and not d["accept"]:
            return "not_allowed"
        return "grabbing"
    if ctl["bar_drag"] != null:
        return "arrow"
    if hit == null:
        return "arrow"
    b := _bubble(hit, "cursor")
    if b != null:
        return b["cursor"]
    if _is_text(hit):
        return "text"
    tg := _hover_target(hit)
    if tg == null:
        return "arrow"
    if tg["draggable"] and not (tg["kind"] == "button"):
        return "grab"
    if _is_text(tg):
        return "text"
    return "pointer"

func _apply_cursor(ctl, name):
    if name == ctl["cursor"]:
        return null
    ctl["cursor"] = name
    if ctl["win"] != null:
        _native.window_set_cursor(ctl["win"], name)
    return null

# ---------------------------------------------------------------- activation (clic, Entrée, Espace)
func activate(ctl, w, ev=null):
    if not w["enabled"]:
        return false
    if w["kind"] == "checkbox":
        _checkbox.toggle(w)
    if w["on_click"] != null:
        w["on_click"](w)
    ctl["dirty"] = true
    return true

# ---------------------------------------------------------------- glisser-déposer
func _accepts(target, session):
    a := target["drop_accept"]
    if a == null:
        return true
    if is_function(a):
        return a(target, session) == true
    if type(a) == "list":
        ty := session["type"]
        if ty == null and type(session["payload"]) == "dict" and collections.contains_key(session["payload"], "type"):
            ty = session["payload"]["type"]
        return collections.contains(a, ty)
    return false

func _drop_target_at(ctl, x, y, src):
    h := _hit(ctl["root"], x, y, src)
    p := h
    while p != null:
        if p["droppable"] and not _is_under(src, p):
            return p
        p = p["parent"]
    return null

func _drag_leave(ctl, session):
    old := session["over"]
    if old != null:
        old["drop_hover"] = false
        old["drop_reject"] = false
        if session["accept"] and old["on_drag_leave"] != null:
            old["on_drag_leave"](old, session)
    session["over"] = null
    session["accept"] = false
    return null

func _dnd_start(ctl, src, ge):
    if src["on_drag_start"] != null:
        if src["on_drag_start"](src, ge) == false:
            return false
    r := window_rect(src)
    session := {"kind": "dnd", "source": src, "payload": src["drag_data"], "type": src["drag_type"],
                "x": ge["x"], "y": ge["y"], "grab_x": ge["start_x"] - r[0], "grab_y": ge["start_y"] - r[1],
                "origin_x": r[0], "origin_y": r[1], "over": null, "accept": false, "dropped": false,
                "target": null, "active": true, "old_opacity": src["opacity"],
                "ghost": {"x": r[0], "y": r[1], "a": 0.8}}
    src["opacity"] = 0.35
    ctl["drag"] = session
    ctl["dirty"] = true
    return true

func _dnd_move(ctl, ge):
    s := ctl["drag"]
    s["x"] = ge["x"]
    s["y"] = ge["y"]
    s["ghost"]["x"] = ge["x"] - s["grab_x"]
    s["ghost"]["y"] = ge["y"] - s["grab_y"]
    tg := _drop_target_at(ctl, ge["x"], ge["y"], s["source"])
    cur := s["over"]
    if not (tg == null and cur == null) and not (tg != null and cur != null and tg["uid"] == cur["uid"]):
        _drag_leave(ctl, s)
        if tg != null:
            s["over"] = tg
            s["accept"] = _accepts(tg, s)
            if s["accept"]:
                tg["drop_hover"] = true
                if tg["on_drag_enter"] != null:
                    tg["on_drag_enter"](tg, s)
            else:
                tg["drop_reject"] = true
    if s["over"] != null and s["accept"] and s["over"]["on_drag_over"] != null:
        s["over"]["on_drag_over"](s["over"], s)
    ctl["dirty"] = true
    return null

func _dnd_finish(ctl):
    s := ctl["drag"]
    if s == null:
        return null
    s["source"]["opacity"] = s["old_opacity"]
    s["active"] = false
    ctl["drag"] = null
    ctl["dirty"] = true
    return null

func _dnd_ghost_done(ev):
    _dnd_finish(ev["ctx"])

# Termine le glisser : déposé sur une cible acceptante, ou retour animé du fantôme à l'origine.
func _dnd_end(ctl, cancelled):
    s := ctl["drag"]
    if s == null:
        return null
    over := s["over"]
    ok := over != null and s["accept"] and not cancelled
    s["target"] = over
    _drag_leave(ctl, s)
    s["active"] = false
    gh := s["ghost"]
    if ok:
        s["dropped"] = true
        s["source"]["opacity"] = s["old_opacity"]
        if over["on_drop"] != null:
            over["on_drop"](over, s)
        if s["source"]["on_drag_end"] != null:
            s["source"]["on_drag_end"](s["source"], s)
        node := _tw.tween(_tw.target_dict(gh, "a"), 0.0, 0.12, null, "ease_out")
        _tw.callbacks(node, null, null, _dnd_ghost_done, ctl)
        _anim.play(ctl["anim"], node, "ghost")
    else:
        if s["source"]["on_drag_end"] != null:
            s["source"]["on_drag_end"](s["source"], s)
        back := _tw.parallel([
            _tw.tween(_tw.target_dict(gh, "x"), s["origin_x"] + 0.0, DRAG_RETURN_TIME, null, "cubic_out"),
            _tw.tween(_tw.target_dict(gh, "y"), s["origin_y"] + 0.0, DRAG_RETURN_TIME, null, "cubic_out")
        ])
        _tw.callbacks(back, null, null, _dnd_ghost_done, ctl)
        _anim.play(ctl["anim"], back, "ghost")
    ctl["dirty"] = true
    return null

# Annule le glisser-déposer en cours (Échap) : le fantôme revient à sa place.
func cancel_drag(ctl):
    if ctl["drag"] == null or not ctl["drag"]["active"]:
        return false
    gesture.cancel(ctl["g"])
    _dnd_end(ctl, true)
    return true

func is_dragging(ctl):
    return ctl["drag"] != null and ctl["drag"]["active"]

# ---------------------------------------------------------------- molette
func _scrollable_toward(w, dx, dy):
    k := w["kind"]
    if k != "scroll_view" and k != "text_area" and not (k == "text_field" and dx != 0.0):
        return false
    if dy < 0 and w["scroll_y"] > 0:
        return true
    if dy > 0 and w["scroll_y"] < scroll.max_y(w):
        return true
    if dx < 0 and w["scroll_x"] > 0:
        return true
    if dx > 0 and w["scroll_x"] < scroll.max_x(w):
        return true
    return false

func _wheel(ctl, hit, ge):
    if hit != null:
        b := _bubble(hit, "on_wheel")
        if b != null and b["on_wheel"](b, ge) == true:
            ctl["dirty"] = true
            return true
    step := ti.line_h(ctl["theme"]) * 3.0
    dx := ge["dx"] * step
    dy := 0.0 - ge["dy"] * step
    if ge["mods"] % 8 >= 4:
        dx = dy
        dy = 0.0
        if ge["dx"] != 0.0:
            dx = ge["dx"] * step
    p := hit
    while p != null:
        if _scrollable_toward(p, dx, dy):
            scroll.by(p, dx, dy)
            ctl["dirty"] = true
            return true
        p = p["parent"]
    return false

# ---------------------------------------------------------------- routage des gestes
func _text_local(ctl, w, ge):
    return to_local(w, ge["x"], ge["y"])

func _bar_hover(ctl, hit, ge):
    changed := false
    for w in [ctl["hover"], hit]:
        if w != null and (w["kind"] == "scroll_view" or w["kind"] == "text_area"):
            lp := to_local(w, ge["x"], ge["y"])
            name := ""
            if hit != null and hit["uid"] == w["uid"]:
                name = scroll.hit_bar(w, lp[0], lp[1])
            if w["bar_hover"] != name:
                w["bar_hover"] = name
                changed = true
    if changed:
        ctl["dirty"] = true
    return null

func _on_press(ctl, ge):
    hit := _hit(ctl["root"], ge["x"], ge["y"], null)
    ctl["press"] = hit
    ctl["press_target"] = null
    ctl["release_hit"] = null
    if hit == null:
        if ge["button"] == 1:
            set_focus(ctl, null)
        return null
    if ge["button"] == 1:
        # barres de défilement
        if hit["kind"] == "scroll_view" or hit["kind"] == "text_area":
            lp := to_local(hit, ge["x"], ge["y"])
            bar := scroll.hit_bar(hit, lp[0], lp[1])
            if bar == "v_thumb" or bar == "h_thumb":
                axis := "y"
                start := hit["scroll_y"]
                if bar == "h_thumb":
                    axis = "x"
                    start = hit["scroll_x"]
                ctl["bar_drag"] = {"w": hit, "axis": axis, "start": start, "x0": ge["x"], "y0": ge["y"]}
                hit["bar_hover"] = bar
                ctl["dirty"] = true
                return null
            if bar != "":
                scroll.page_toward(hit, "y" if bar == "v_track" else "x", lp[0], lp[1])
                ctl["dirty"] = true
                return null
        f := _nearest_focusable(hit)
        set_focus(ctl, f, false)
        if f != null and _is_text(f):
            lp := to_local(f, ge["x"], ge["y"])
            ti.press(f, ctl["theme"], lp[0], lp[1], ge["count"], ge["mods"] % 8 >= 4)
            ctl["capture"] = f
            ctl["caret_t"] = now(ctl)
            ctl["caret_on"] = true
        tg := _hover_target(hit)
        if tg != null and tg["enabled"]:
            ctl["press_target"] = tg
            tg["pressed"] = true
            tg["hover_anim"] = true
            _animate(ctl, tg, "press_t", 1.0, PRESS_TIME)
    b := _bubble(hit, "on_press")
    if b != null:
        b["on_press"](b, ge)
    ctl["dirty"] = true
    return null

func _on_release(ctl, ge):
    tg := ctl["press_target"]
    if tg != null:
        tg["pressed"] = false
        _animate(ctl, tg, "press_t", 0.0, HOVER_TIME)
    if ctl["capture"] != null:
        ti.release(ctl["capture"])
        ctl["capture"] = null
    if ctl["bar_drag"] != null:
        ctl["bar_drag"]["w"]["bar_hover"] = ""
        ctl["bar_drag"] = null
    ctl["release_hit"] = _hit(ctl["root"], ge["x"], ge["y"], null)
    if ctl["press"] != null:
        b := _bubble(ctl["press"], "on_release")
        if b != null:
            b["on_release"](b, ge)
    ctl["dirty"] = true
    return null

func _on_click(ctl, ge):
    p := ctl["press"]
    r := ctl["release_hit"]
    if p == null or r == null or p["uid"] != r["uid"]:
        return null
    tg := ctl["press_target"]
    if tg != null:
        activate(ctl, tg, ge)
    return null

func _on_drag_start(ctl, ge):
    if ctl["bar_drag"] != null or ctl["capture"] != null or ctl["press"] == null:
        return null
    p := ctl["press"]
    while p != null:
        if p["draggable"] and p["enabled"]:
            if _dnd_start(ctl, p, ge):
                return null
            break
        p = p["parent"]
    b := _bubble(ctl["press"], "on_drag_start")
    if b != null:
        b["on_drag_start"](b, ge)
    return null

func _on_drag_move(ctl, ge):
    bd := ctl["bar_drag"]
    if bd != null:
        w := bd["w"]
        if bd["axis"] == "y":
            v := scroll.thumb_scroll(w, "y", bd["start"], ge["y"] - bd["y0"])
            scroll.set(w, w["scroll_x"], v)
        else:
            v := scroll.thumb_scroll(w, "x", bd["start"], ge["x"] - bd["x0"])
            scroll.set(w, v, w["scroll_y"])
        ctl["dirty"] = true
        return null
    if ctl["capture"] != null:
        w := ctl["capture"]
        lp := to_local(w, ge["x"], ge["y"])
        ti.drag_to(w, ctl["theme"], lp[0], lp[1])
        ctl["caret_t"] = now(ctl)
        ctl["caret_on"] = true
        ctl["dirty"] = true
        return null
    if ctl["drag"] != null and ctl["drag"]["active"]:
        _dnd_move(ctl, ge)
        _apply_cursor(ctl, _cursor_for(ctl, null))
        return null
    if ctl["press"] != null:
        b := _bubble(ctl["press"], "on_drag")
        if b != null:
            b["on_drag"](b, ge)
            ctl["dirty"] = true
    return null

func _on_drag_end(ctl, ge):
    if ctl["drag"] != null and ctl["drag"]["active"]:
        _dnd_end(ctl, false)
    elif ctl["press"] != null:
        b := _bubble(ctl["press"], "on_drag_end")
        if b != null:
            b["on_drag_end"](b, ge)
    return null

func _on_hover(ctl, ge):
    hit := _hit(ctl["root"], ge["x"], ge["y"], null)
    _set_hover(ctl, _hover_target(hit), ge)
    _bar_hover(ctl, hit, ge)
    _apply_cursor(ctl, _cursor_for(ctl, hit))
    return null

func _route(ctl, ge):
    t := ge["type"]
    if t == "press":
        _on_press(ctl, ge)
    elif t == "release":
        _on_release(ctl, ge)
    elif t == "click":
        _on_click(ctl, ge)
    elif t == "double_click":
        h := ctl["release_hit"]
        if h != null:
            b := _bubble(h, "on_double_click")
            if b != null:
                b["on_double_click"](b, ge)
                ctl["dirty"] = true
    elif t == "context":
        h := _hit(ctl["root"], ge["x"], ge["y"], null)
        if h != null:
            b := _bubble(h, "on_context")
            if b != null:
                b["on_context"](b, ge)
                ctl["dirty"] = true
    elif t == "long_press":
        if ctl["press"] != null:
            b := _bubble(ctl["press"], "on_long_press")
            if b != null:
                b["on_long_press"](b, ge)
                ctl["dirty"] = true
    elif t == "drag_start":
        _on_drag_start(ctl, ge)
    elif t == "drag_move":
        _on_drag_move(ctl, ge)
    elif t == "drag_end":
        _on_drag_end(ctl, ge)
    elif t == "drag_cancel":
        if ctl["drag"] != null and ctl["drag"]["active"]:
            _dnd_end(ctl, true)
    elif t == "hover":
        _on_hover(ctl, ge)
    elif t == "hover_end":
        _set_hover(ctl, null, ge)
        _apply_cursor(ctl, "arrow")
    elif t == "wheel":
        _wheel(ctl, _hit(ctl["root"], ge["x"], ge["y"], null), ge)
        _on_hover(ctl, ge)
    return null

# ---------------------------------------------------------------- clavier
func _scroll_key(ctl, w, vk, mods):
    step := ti.line_h(ctl["theme"]) * 2.0
    page := w["view_h"] * 0.9
    if vk == 38:
        scroll.by(w, 0.0, 0.0 - step)
    elif vk == 40:
        scroll.by(w, 0.0, step)
    elif vk == 37:
        scroll.by(w, 0.0 - step, 0.0)
    elif vk == 39:
        scroll.by(w, step, 0.0)
    elif vk == 33:
        scroll.by(w, 0.0, 0.0 - page)
    elif vk == 34:
        scroll.by(w, 0.0, page)
    elif vk == 36:
        scroll.set(w, w["scroll_x"], 0.0)
    elif vk == 35:
        scroll.set(w, w["scroll_x"], scroll.max_y(w))
    else:
        return false
    ctl["dirty"] = true
    return true

func _on_key(ctl, ev):
    vk := 0
    if collections.contains_key(ev, "key"):
        vk = ev["key"]
    else:
        vk = ev["widget"]
    mods := 0
    if collections.contains_key(ev, "mods"):
        mods = ev["mods"]
    typed := ""
    if collections.contains_key(ev, "text"):
        typed = ev["text"]
    ctrl := mods % 4 >= 2
    alt := mods % 2 == 1
    shift := mods % 8 >= 4
    w := ctl["focus"]
    if w != null:
        b := _bubble(w, "on_key")
        if b != null and b["on_key"](b, ev) == true:
            ctl["dirty"] = true
            return true
        if w["enabled"]:
            if _is_text(w):
                if not (vk == 9 and not ctrl):
                    r := ti.key(w, ctl["theme"], vk, mods, typed)
                    if r > 0:
                        ctl["caret_t"] = now(ctl)
                        ctl["caret_on"] = true
                        ctl["dirty"] = true
                        return true
            elif w["kind"] == "button":
                if vk == 13 or vk == 32:
                    activate(ctl, w, ev)
                    return true
            elif w["kind"] == "checkbox":
                if vk == 32:
                    activate(ctl, w, ev)
                    return true
            elif w["kind"] == "scroll_view":
                if _scroll_key(ctl, w, vk, mods):
                    return true
    if vk == 9 and not ctrl and not alt:
        focus_next(ctl, shift)
        return true
    if vk == 27:
        if cancel_drag(ctl):
            return true
        if w != null:
            b := _bubble(w, "on_escape")
            if b != null:
                b["on_escape"](b)
                ctl["dirty"] = true
                return true
        return false
    if w != null and not _is_text(w) and w["kind"] != "scroll_view" and not ctrl and not alt:
        if vk == 37:
            return focus_move(ctl, "left")
        if vk == 39:
            return focus_move(ctl, "right")
        if vk == 38:
            return focus_move(ctl, "up")
        if vk == 40:
            return focus_move(ctl, "down")
    return false

func _on_text(ctl, s):
    w := ctl["focus"]
    if w != null and _is_text(w) and w["enabled"]:
        if ti.key(w, ctl["theme"], 0, 0, s) > 0:
            ctl["caret_t"] = now(ctl)
            ctl["caret_on"] = true
            ctl["dirty"] = true
            return true
    return false

# ---------------------------------------------------------------- mise en page / métriques
func _update_metrics(w, t):
    if not w["visible"]:
        return null
    if w["kind"] == "scroll_view":
        scroll.update_content(w)
    elif _is_text(w):
        ti.metrics(w, t)
    for ch in w["children"]:
        _update_metrics(ch, t)
    return null

# Recalcule la mise en page puis les métriques de défilement (à appeler avant hit-test / dessin).
func relayout(ctl):
    layout.perform(ctl["root"], ctl["w"], ctl["h"])
    _update_metrics(ctl["root"], ctl["theme"])
    return null

func take_dirty(ctl):
    d := ctl["dirty"]
    ctl["dirty"] = false
    return d

# ---------------------------------------------------------------- événements bruts
# Traite un événement de ui.poll. Retourne true si un nouveau dessin est nécessaire.
func handle(ctl, ev):
    t := ev["type"]
    if t == "pointer_move" or t == "pointer_down" or t == "pointer_up" or t == "wheel" or t == "pointer_leave":
        if collections.contains_key(ev, "x"):
            ctl["px"] = ev["x"]
            ctl["py"] = ev["y"]
        if collections.contains_key(ev, "mods"):
            ctl["mods"] = ev["mods"]
        for ge in gesture.feed(ctl["g"], ev, now(ctl)):
            _route(ctl, ge)
    elif t == "key_down":
        _on_key(ctl, ev)
    elif t == "text_input":
        _on_text(ctl, ev["data"])
    elif t == "resize":
        ctl["w"] = ev["x"]
        ctl["h"] = ev["y"]
        ctl["root"]["width"] = ev["x"]
        ctl["root"]["height"] = ev["y"]
        if ctl["canvas"] != null:
            canvas.resize(ctl["canvas"])
        ctl["dirty"] = true
    return take_dirty(ctl)

# ---------------------------------------------------------------- tick (appui long, clignotement, animations)
func update(ctl):
    n := now(ctl)
    for ge in gesture.tick(ctl["g"], n):
        _route(ctl, ge)
    f := ctl["focus"]
    if f != null and _is_text(f):
        on := (n - ctl["caret_t"]) % CARET_PERIOD < CARET_ON
        if on != ctl["caret_on"]:
            ctl["caret_on"] = on
            ctl["dirty"] = true
    # défilement automatique pendant un glisser près des bords d'une zone défilante
    d := ctl["drag"]
    if d != null and d["active"]:
        if ctl["auto_t"] == null:
            ctl["auto_t"] = n
        dt := n - ctl["auto_t"]
        ctl["auto_t"] = n
        p := _hit(ctl["root"], d["x"], d["y"], d["source"])
        while p != null:
            if p["kind"] == "scroll_view":
                r := window_rect(p)
                if d["y"] < r[1] + AUTOSCROLL_EDGE:
                    scroll.by(p, 0.0, 0.0 - AUTOSCROLL_SPEED * dt)
                    ctl["dirty"] = true
                    break
                if d["y"] > r[1] + r[3] - AUTOSCROLL_EDGE:
                    scroll.by(p, 0.0, AUTOSCROLL_SPEED * dt)
                    ctl["dirty"] = true
                    break
            p = p["parent"]
    else:
        ctl["auto_t"] = null
    if _anim.is_active(ctl["anim"]):
        if ctl["fake_now"] == null:
            _anim.update(ctl["anim"])
        ctl["dirty"] = true
    return take_dirty(ctl)

# ---------------------------------------------------------------- dessin
func _draw_node(c, w, t):
    if not w["visible"]:
        return null
    k := w["kind"]
    if k == "scroll_view":
        if w["background"] != null:
            canvas.round_rect(c, w["x"], w["y"], w["width"], w["height"], t["radius"], paint.fill(w["background"], w["opacity"]))
        gfx.push(c, w["x"], w["y"], w["width"], w["height"], w["scroll_x"], w["scroll_y"])
        for ch in w["children"]:
            _draw_node(c, ch, t)
        gfx.pop(c)
        scroll.draw_bars(c, w, t)
        return null
    if k == "button":
        _button.draw(w, c, t)
    elif k == "label":
        _label.draw(w, c, t)
    elif k == "card":
        _card.draw(w, c, t)
    elif k == "checkbox":
        _checkbox.draw(w, c, t)
    elif k == "progress":
        _progress.draw(w, c, t)
    elif k == "text_field" or k == "text_area":
        ti.draw(w, c, t)
    elif k == "gutter":
        _gutter.draw(w, c, t)
    for ch in w["children"]:
        _draw_node(c, ch, t)
    return null

func _draw_overlays(ctl, c, t):
    # surbrillance des cibles de dépôt
    d := ctl["drag"]
    if d != null and d["over"] != null:
        r := window_rect(d["over"])
        col := t["drop_ok"]
        if not d["accept"]:
            col = t["danger"]
        canvas.round_rect(c, r[0], r[1], r[2], r[3], t["radius"], paint.fill({"r": col["r"], "g": col["g"], "b": col["b"], "a": 28}))
        canvas.round_rect(c, r[0], r[1], r[2], r[3], t["radius"], paint.stroke(col, 2.0))
    # anneau de focus (navigation clavier)
    f := ctl["focus"]
    if f != null and ctl["focus_visible"] and f["visible"] and not _is_text(f):
        r := window_rect(f)
        canvas.round_rect(c, r[0] - 3, r[1] - 3, r[2] + 6, r[3] + 6, t["radius"] + 3, paint.stroke(t["primary"], 2.0))
    # fantôme du glisser-déposer
    if d != null:
        g := d["ghost"]
        src := d["source"]
        canvas.set_opacity(c, clamp(g["a"], 0.0, 1.0))
        canvas.transform(c, {"m11": 1.0, "m12": 0.0, "m21": 0.0, "m22": 1.0, "dx": g["x"] - src["x"], "dy": g["y"] - src["y"]})
        _draw_node(c, src, t)
        canvas.reset_transform(c)
        canvas.set_opacity(c, 1.0)
    return null

# Dessine l'arbre complet (clips et défilements imbriqués inclus) puis les surcouches. Appelle begin/end.
func draw(ctl, c=null, clear=true):
    cv := c
    if cv == null:
        cv = ctl["canvas"]
    t := ctl["theme"]
    canvas.begin(cv)
    if clear:
        canvas.clear(cv, t["background"])
    gfx.begin(cv)
    f := ctl["focus"]
    for w in [f]:
        if w != null and _is_text(w):
            w["caret_visible"] = ctl["caret_on"]
    _draw_node(cv, ctl["root"], t)
    _draw_overlays(ctl, cv, t)
    canvas.end(cv)
    return null

# ---------------------------------------------------------------- intégration ui.state.run
# render(store, ctl) : mise en page + dessin.
func render(store, ctl):
    relayout(ctl)
    draw(ctl)
    return null

# handler(ev, store, ctl) : événements -> contrôleur ; invalide le store si un re-rendu est nécessaire.
func handler(ev, store, ctl):
    if handle(ctl, ev):
        _state.invalidate(store)
    return null

# tick(store, ctl) : à enregistrer avec state.on_tick ; retourne true pour demander un re-rendu.
func tick(store, ctl):
    return update(ctl)
