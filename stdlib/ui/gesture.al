# ALEX UI V1.3 — Reconnaissance de gestes (pure : aucune dépendance au rendu ni aux widgets)
#
# Transforme les événements bruts (pointer_move / pointer_down / pointer_up / wheel / pointer_leave) en
# gestes de haut niveau. L'horloge est FOURNIE par l'appelant (`now`, en secondes) : tests déterministes.
#
# Gestes émis (dict, toujours {"type", "x", "y", "mods"} + champs propres) :
#   press / release            bouton enfoncé / relâché   (button, count : rang du clic en cours)
#   click                      clic gauche sans glisser   (count 1, 2, 3, 1... : double/triple-clic)
#   double_click, triple_click émis EN PLUS de click quand count vaut 2 / 3
#   context                    clic droit (au relâchement)     middle_click   clic milieu
#   long_press                 appui maintenu sans bouger (long_press_time), UNE fois ; supprime le clic
#   drag_start / drag_move / drag_end / drag_cancel
#                              seuil `slop` pixels ; drag_move : dx, dy (depuis le geste précédent),
#                              total_dx, total_dy, start_x, start_y, button
#   hover                      déplacement sans bouton    hover_end    le pointeur quitte la fenêtre
#   wheel                      dx, dy (crans ; dy > 0 = vers le haut)
# Un seul bouton est suivi à la fois : les autres sont ignorés jusqu'au relâchement.
from core use type, len
use collections
use math as _math

func create(slop=4.0, double_time=0.4, double_slop=6.0, long_press_time=0.5):
    return {"kind": "gesture", "slop": slop + 0.0, "double_time": double_time + 0.0, "double_slop": double_slop + 0.0,
            "long_press_time": long_press_time + 0.0,
            "pressed": false, "button": 0, "down_x": 0, "down_y": 0, "down_t": 0.0, "mods": 0,
            "dragging": false, "long_fired": false, "x": 0, "y": 0, "last_x": 0, "last_y": 0, "count": 0,
            "last_click_t": -1000000.0, "last_click_x": 0, "last_click_y": 0, "last_click_count": 0}

func _ev(g, kind, x, y, mods):
    return {"type": kind, "x": x, "y": y, "mods": mods}

func _dist(ax, ay, bx, by):
    dx := ax - bx
    dy := ay - by
    return _math.sqrt(dx * dx + dy * dy)

# Rang du clic si l'appui a lieu maintenant (1, 2 ou 3 puis recommence : comme les éditeurs de texte).
func _prospective_count(g, x, y, now):
    if now - g["last_click_t"] <= g["double_time"] and _dist(x, y, g["last_click_x"], g["last_click_y"]) <= g["double_slop"]:
        return g["last_click_count"] % 3 + 1
    return 1

func _drag_ev(g, kind, x, y, mods, dx, dy):
    e := _ev(g, kind, x, y, mods)
    e["dx"] = dx
    e["dy"] = dy
    e["total_dx"] = x - g["down_x"]
    e["total_dy"] = y - g["down_y"]
    e["start_x"] = g["down_x"]
    e["start_y"] = g["down_y"]
    e["button"] = g["button"]
    return e

# Consomme un événement brut ; retourne la liste des gestes produits (souvent vide ou un seul).
func feed(g, ev, now):
    out := []
    t := ev["type"]
    mods := 0
    if collections.contains_key(ev, "mods"):
        mods = ev["mods"]
    if t == "pointer_down":
        if g["pressed"]:
            return out
        g["pressed"] = true
        g["button"] = ev["button"]
        g["down_x"] = ev["x"]
        g["down_y"] = ev["y"]
        g["down_t"] = now
        g["mods"] = mods
        g["dragging"] = false
        g["long_fired"] = false
        g["x"] = ev["x"]
        g["y"] = ev["y"]
        g["last_x"] = ev["x"]
        g["last_y"] = ev["y"]
        g["count"] = 1
        if ev["button"] == 1:
            g["count"] = _prospective_count(g, ev["x"], ev["y"], now)
        e := _ev(g, "press", ev["x"], ev["y"], mods)
        e["button"] = ev["button"]
        e["count"] = g["count"]
        collections.append(out, e)
    elif t == "pointer_move":
        g["x"] = ev["x"]
        g["y"] = ev["y"]
        if g["pressed"]:
            if not g["dragging"]:
                if _dist(ev["x"], ev["y"], g["down_x"], g["down_y"]) >= g["slop"]:
                    g["dragging"] = true
                    collections.append(out, _drag_ev(g, "drag_start", ev["x"], ev["y"], mods, 0, 0))
                    collections.append(out, _drag_ev(g, "drag_move", ev["x"], ev["y"], mods, ev["x"] - g["down_x"], ev["y"] - g["down_y"]))
                    g["last_x"] = ev["x"]
                    g["last_y"] = ev["y"]
            else:
                collections.append(out, _drag_ev(g, "drag_move", ev["x"], ev["y"], mods, ev["x"] - g["last_x"], ev["y"] - g["last_y"]))
                g["last_x"] = ev["x"]
                g["last_y"] = ev["y"]
        else:
            collections.append(out, _ev(g, "hover", ev["x"], ev["y"], mods))
    elif t == "pointer_up":
        if not g["pressed"] or ev["button"] != g["button"]:
            return out
        g["pressed"] = false
        b := g["button"]
        r := _ev(g, "release", ev["x"], ev["y"], mods)
        r["button"] = b
        if g["dragging"]:
            g["dragging"] = false
            collections.append(out, _drag_ev(g, "drag_end", ev["x"], ev["y"], mods, 0, 0))
            collections.append(out, r)
            return out
        collections.append(out, r)
        if g["long_fired"]:
            g["long_fired"] = false
            return out
        if b == 1:
            c := g["count"]
            g["last_click_t"] = now
            g["last_click_x"] = ev["x"]
            g["last_click_y"] = ev["y"]
            g["last_click_count"] = c
            e := _ev(g, "click", ev["x"], ev["y"], mods)
            e["button"] = 1
            e["count"] = c
            collections.append(out, e)
            if c == 2:
                d := _ev(g, "double_click", ev["x"], ev["y"], mods)
                d["count"] = 2
                collections.append(out, d)
            elif c == 3:
                d := _ev(g, "triple_click", ev["x"], ev["y"], mods)
                d["count"] = 3
                collections.append(out, d)
        elif b == 2:
            e := _ev(g, "context", ev["x"], ev["y"], mods)
            e["button"] = 2
            collections.append(out, e)
        elif b == 3:
            e := _ev(g, "middle_click", ev["x"], ev["y"], mods)
            e["button"] = 3
            collections.append(out, e)
    elif t == "wheel":
        e := _ev(g, "wheel", ev["x"], ev["y"], mods)
        e["dx"] = ev["dx"]
        e["dy"] = ev["dy"]
        collections.append(out, e)
    elif t == "pointer_leave":
        collections.append(out, _ev(g, "hover_end", g["x"], g["y"], mods))
    return out

# À appeler régulièrement (chaque tour de boucle) : déclenche l'appui long.
func tick(g, now):
    out := []
    if g["pressed"] and not g["dragging"] and not g["long_fired"]:
        if now - g["down_t"] >= g["long_press_time"]:
            g["long_fired"] = true
            e := _ev(g, "long_press", g["down_x"], g["down_y"], g["mods"])
            e["button"] = g["button"]
            collections.append(out, e)
    return out

# Abandonne le geste en cours (Échap pendant un glisser, perte de focus...).
func cancel(g):
    out := []
    if g["pressed"] and g["dragging"]:
        out = [_drag_ev(g, "drag_cancel", g["x"], g["y"], g["mods"], 0, 0)]
    g["pressed"] = false
    g["dragging"] = false
    g["long_fired"] = false
    return out

func is_pressed(g):
    return g["pressed"]

func is_dragging(g):
    return g["dragging"]
