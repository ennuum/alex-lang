# ALEX UI V1.3 — Défilement : protocole commun, barres, synchronisation, défilement animé
#
# « Protocole de défilement » : tout widget avec scroll_x, scroll_y, content_width, content_height,
# view_w, view_h peut défiler (scroll_view, text_field, text_area). Les fonctions ci-dessous ne
# dépendent que de ces champs : elles servent donc aussi à de futurs widgets.
#   * set / by / to_view : position bornée, rappel on_scroll(w), propagation aux widgets liés ;
#   * link(a, b, axis, mode) : défilement synchronisé (« ratio » = même proportion, « offset » = même
#     décalage en pixels) — par défaut dans les DEUX sens ; les boucles sont impossibles (garde interne) ;
#   * smooth(anim, w, x, y) : défilement animé (ressort/tween V1.2) ; les barres sont des surcouches fines.
from core use type, len, clamp, is_function
use collections
use ui.widgets.widget as base
use ui.paint as paint
use ui.canvas as canvas
use ui.tween.core as _tw
use ui.tween.animator as _anim

const BAR := 6.0          # épaisseur des barres de défilement
const BAR_HOVER := 10.0   # épaisseur quand le pointeur est dessus / pendant le glisser
const BAR_PAD := 2.0
const MIN_THUMB := 28.0
const _BUSY := {"on": false}

func create(x=0.0, y=0.0, width=300.0, height=200.0):
    w := base.create("scroll_view", x, y, width, height)
    w["layout"]["type"] = "column"
    w["layout"]["direction"] = "column"
    w["layout"]["alignment"] = {"horizontal": "stretch", "vertical": "start"}
    w["content_fixed"] = false
    w["view_w"] = width
    w["view_h"] = height
    w["bar_hover"] = ""
    w["background"] = null
    return w

func max_x(w):
    m := w["content_width"] - w["view_w"]
    if m < 0.5:
        return 0.0
    return m + 0.0

func max_y(w):
    m := w["content_height"] - w["view_h"]
    if m < 0.5:
        return 0.0
    return m + 0.0

func ratio_x(w):
    m := max_x(w)
    if m <= 0:
        return 0.0
    return w["scroll_x"] / m

func ratio_y(w):
    m := max_y(w)
    if m <= 0:
        return 0.0
    return w["scroll_y"] / m

# ---- cœur : affectation + propagation ----
func _assign(w, x, y):
    nx := clamp(x, 0.0, max_x(w))
    ny := clamp(y, 0.0, max_y(w))
    if nx == w["scroll_x"] and ny == w["scroll_y"]:
        return false
    w["scroll_x"] = nx
    w["scroll_y"] = ny
    if w["on_scroll"] != null:
        w["on_scroll"](w)
    return true

func _propagate(w, old_x, old_y):
    for ln in w["scroll_links"]:
        t := ln["target"]
        if ln["axis"] == "y" or ln["axis"] == "both":
            if ln["mode"] == "ratio":
                _assign(t, t["scroll_x"], ratio_y(w) * max_y(t))
            else:
                _assign(t, t["scroll_x"], w["scroll_y"])
        if ln["axis"] == "x" or ln["axis"] == "both":
            if ln["mode"] == "ratio":
                _assign(t, ratio_x(w) * max_x(t), t["scroll_y"])
            else:
                _assign(t, w["scroll_x"], t["scroll_y"])

# Positionne le défilement (borné). Retourne true si la position a changé.
func set(w, x, y):
    old_x := w["scroll_x"]
    old_y := w["scroll_y"]
    changed := _assign(w, x, y)
    if changed and not _BUSY["on"]:
        _BUSY["on"] = true
        _propagate(w, old_x, old_y)
        _BUSY["on"] = false
    return changed

func by(w, dx, dy):
    return set(w, w["scroll_x"] + dx, w["scroll_y"] + dy)

# Synchronise a et b. axis : "y" | "x" | "both" ; mode : "ratio" | "offset" ; both : dans les deux sens.
func link(a, b, axis="y", mode="ratio", both=true):
    if axis != "x" and axis != "y" and axis != "both":
        raise("ArgumentError", "ui.scroll.link() : axis doit valoir x, y ou both")
    if mode != "ratio" and mode != "offset":
        raise("ArgumentError", "ui.scroll.link() : mode doit valoir ratio ou offset")
    collections.append(a["scroll_links"], {"target": b, "axis": axis, "mode": mode})
    if both:
        collections.append(b["scroll_links"], {"target": a, "axis": axis, "mode": mode})
    return null

func unlink(a, b):
    kept := []
    for ln in a["scroll_links"]:
        if ln["target"]["uid"] != b["uid"]:
            collections.append(kept, ln)
    a["scroll_links"] = kept
    kept2 := []
    for ln in b["scroll_links"]:
        if ln["target"]["uid"] != a["uid"]:
            collections.append(kept2, ln)
    b["scroll_links"] = kept2
    return null

# Fait défiler pour rendre visible le rectangle (x, y, width, height), en coordonnées du CONTENU.
func to_view(w, x, y, width, height, margin=0.0):
    nx := w["scroll_x"]
    ny := w["scroll_y"]
    vw := w["view_w"]
    vh := w["view_h"]
    if x - margin < nx:
        nx = x - margin
    elif x + width + margin > nx + vw:
        nx = x + width + margin - vw
    if y - margin < ny:
        ny = y - margin
    elif y + height + margin > ny + vh:
        ny = y + height + margin - vh
    return set(w, nx, ny)

# ---- défilement animé (V1.2) ----
func _smooth_cb(ev):
    ctx := ev["ctx"]
    w := ctx["w"]
    if ctx["axis"] == "y":
        set(w, w["scroll_x"], ev["value"])
    else:
        set(w, ev["value"], w["scroll_y"])

func smooth(anim, w, x, y, duration=0.25, easing="cubic_out"):
    nx := clamp(x, 0.0, max_x(w))
    ny := clamp(y, 0.0, max_y(w))
    if nx != w["scroll_x"]:
        _anim.play(anim, _tw.tween(_tw.target_fn(_smooth_cb, {"w": w, "axis": "x"}), nx + 0.0, duration, w["scroll_x"] + 0.0, easing), "scroll:" + str(w["uid"]) + ":x")
    if ny != w["scroll_y"]:
        _anim.play(anim, _tw.tween(_tw.target_fn(_smooth_cb, {"w": w, "axis": "y"}), ny + 0.0, duration, w["scroll_y"] + 0.0, easing), "scroll:" + str(w["uid"]) + ":y")
    return null

# ---- contenu d'un scroll_view : boîte englobante des enfants ----
func update_content(w):
    w["view_w"] = w["width"]
    w["view_h"] = w["height"]
    if w["content_fixed"]:
        return null
    cw := 0.0
    ch := 0.0
    pad := w["layout"]["padding"]
    for child in w["children"]:
        if not child["visible"]:
            continue
        r := child["x"] + child["width"] - w["x"] + pad["right"]
        b := child["y"] + child["height"] - w["y"] + pad["bottom"]
        if r > cw:
            cw = r
        if b > ch:
            ch = b
    w["content_width"] = cw
    w["content_height"] = ch
    set(w, w["scroll_x"], w["scroll_y"])
    return null

# ---- barres : géométrie en coordonnées de l'espace du widget (même espace que w["x"], w["y"]) ----
func _show_v(w):
    return max_y(w) > 0

func _show_h(w):
    return max_x(w) > 0

func v_track(w):
    return [w["x"] + w["view_w"] - BAR_HOVER - BAR_PAD, w["y"] + BAR_PAD, BAR_HOVER, w["view_h"] - 2 * BAR_PAD - (BAR_HOVER if _show_h(w) else 0.0)]

func h_track(w):
    return [w["x"] + BAR_PAD, w["y"] + w["view_h"] - BAR_HOVER - BAR_PAD, w["view_w"] - 2 * BAR_PAD - (BAR_HOVER if _show_v(w) else 0.0), BAR_HOVER]

func v_thumb(w):
    if not _show_v(w):
        return null
    tr := v_track(w)
    length := tr[3] * w["view_h"] / w["content_height"]
    if length < MIN_THUMB:
        length = MIN_THUMB
    if length > tr[3]:
        length = tr[3]
    pos := tr[1] + ratio_y(w) * (tr[3] - length)
    return [tr[0], pos, tr[2], length]

func h_thumb(w):
    if not _show_h(w):
        return null
    tr := h_track(w)
    length := tr[2] * w["view_w"] / w["content_width"]
    if length < MIN_THUMB:
        length = MIN_THUMB
    if length > tr[2]:
        length = tr[2]
    pos := tr[0] + ratio_x(w) * (tr[2] - length)
    return [pos, tr[1], length, tr[3]]

func _in(r, px, py):
    return px >= r[0] and px < r[0] + r[2] and py >= r[1] and py < r[3] + r[1]

# "v_thumb" | "v_track" | "h_thumb" | "h_track" | "" selon l'élément de barre sous (px, py).
func hit_bar(w, px, py):
    if _show_v(w):
        th := v_thumb(w)
        if _in(th, px, py):
            return "v_thumb"
        if _in(v_track(w), px, py):
            return "v_track"
    if _show_h(w):
        th := h_thumb(w)
        if _in(th, px, py):
            return "h_thumb"
        if _in(h_track(w), px, py):
            return "h_track"
    return ""

# Glisser d'un pouce : nouvelle position de défilement depuis le départ du geste et le déplacement en pixels.
func thumb_scroll(w, axis, start_scroll, delta_px):
    if axis == "y":
        tr := v_track(w)
        th := v_thumb(w)
        room := tr[3] - th[3]
        if room <= 0:
            return start_scroll
        return start_scroll + delta_px * max_y(w) / room
    tr := h_track(w)
    th := h_thumb(w)
    room := tr[2] - th[2]
    if room <= 0:
        return start_scroll
    return start_scroll + delta_px * max_x(w) / room

# Clic sur une piste (hors pouce) : défile d'une page vers le pointeur.
func page_toward(w, axis, px, py):
    if axis == "y":
        th := v_thumb(w)
        if py < th[1]:
            return by(w, 0.0, 0.0 - w["view_h"] * 0.9)
        return by(w, 0.0, w["view_h"] * 0.9)
    th := h_thumb(w)
    if px < th[0]:
        return by(w, 0.0 - w["view_w"] * 0.9, 0.0)
    return by(w, w["view_w"] * 0.9, 0.0)

func draw_bars(c, w, t):
    if _show_v(w):
        tr := v_track(w)
        th := v_thumb(w)
        hot := w["bar_hover"] == "v_thumb" or w["bar_hover"] == "v_track"
        thick := BAR
        if hot:
            thick = BAR_HOVER
            canvas.round_rect(c, tr[0], tr[1], tr[2], tr[3], tr[2] / 2, paint.fill(t["scroll_track"]))
        canvas.round_rect(c, tr[0] + tr[2] - thick - (0.0 if hot else 2.0), th[1], thick, th[3], thick / 2, paint.fill(t["scroll_thumb_hover"] if hot else t["scroll_thumb"]))
    if _show_h(w):
        tr := h_track(w)
        th := h_thumb(w)
        hot := w["bar_hover"] == "h_thumb" or w["bar_hover"] == "h_track"
        thick := BAR
        if hot:
            thick = BAR_HOVER
            canvas.round_rect(c, tr[0], tr[1], tr[2], tr[3], tr[3] / 2, paint.fill(t["scroll_track"]))
        canvas.round_rect(c, th[0], tr[1] + tr[3] - thick - (0.0 if hot else 2.0), th[2], thick, thick / 2, paint.fill(t["scroll_thumb_hover"] if hot else t["scroll_thumb"]))
