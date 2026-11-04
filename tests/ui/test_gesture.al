# Tests de ui.gesture : reconnaissance déterministe (horloge fournie), sans fenêtre.
from core use type, len
use collections
use ui.gesture as gesture

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

func kinds(list):
    out := []
    for e in list:
        collections.append(out, e["type"])
    return out

func has(list, kind):
    for e in list:
        if e["type"] == kind:
            return true
    return false

func find(list, kind):
    for e in list:
        if e["type"] == kind:
            return e
    return null

func down(x, y, b=1, m=0):
    return {"type": "pointer_down", "x": x, "y": y, "button": b, "mods": m}
func up(x, y, b=1, m=0):
    return {"type": "pointer_up", "x": x, "y": y, "button": b, "mods": m}
func move(x, y, m=0):
    return {"type": "pointer_move", "x": x, "y": y, "mods": m}

# ---- clic simple ----
g := gesture.create()
r := gesture.feed(g, down(10, 10), 0.0)
check(kinds(r) == ["press"] and r[0]["count"] == 1, "press : count 1")
r = gesture.feed(g, up(10, 10), 0.1)
check(kinds(r) == ["release", "click"] and r[1]["count"] == 1, "release puis click")

# ---- double et triple-clic, cycle ----
r = gesture.feed(g, down(11, 10), 0.3)
check(r[0]["count"] == 2, "press du 2e clic : count prospectif 2 (sélection d'un mot dès l'appui)")
r = gesture.feed(g, up(11, 10), 0.35)
check(has(r, "click") and has(r, "double_click") and not has(r, "triple_click"), "double-clic")
r = gesture.feed(g, down(11, 10), 0.5)
r = gesture.feed(g, up(11, 10), 0.55)
check(has(r, "triple_click") and find(r, "click")["count"] == 3, "triple-clic")
r = gesture.feed(g, down(11, 10), 0.7)
check(r[0]["count"] == 1, "4e clic rapide : le cycle recommence à 1")
gesture.feed(g, up(11, 10), 0.72)

# trop lent / trop loin -> clic simple
r = gesture.feed(g, down(11, 10), 2.0)
gesture.feed(g, up(11, 10), 2.05)
r = gesture.feed(g, down(11, 10), 2.6)
check(r[0]["count"] == 1, "double-clic trop lent : count 1")
gesture.feed(g, up(11, 10), 2.65)
r = gesture.feed(g, down(60, 60), 2.8)
check(r[0]["count"] == 1, "deuxième clic trop loin : count 1")
gesture.feed(g, up(60, 60), 2.85)

# ---- clic droit / milieu ----
g = gesture.create()
gesture.feed(g, down(5, 5, 2), 0.0)
r = gesture.feed(g, up(5, 5, 2), 0.1)
check(has(r, "context") and not has(r, "click"), "clic droit -> context (au relâchement)")
gesture.feed(g, down(5, 5, 3), 0.2)
r = gesture.feed(g, up(5, 5, 3), 0.3)
check(has(r, "middle_click"), "clic milieu")

# ---- un seul bouton suivi ----
g = gesture.create()
gesture.feed(g, down(5, 5, 1), 0.0)
check(len(gesture.feed(g, down(5, 5, 2), 0.05)) == 0, "2e bouton ignoré pendant l'appui")
check(len(gesture.feed(g, up(5, 5, 2), 0.06)) == 0, "relâchement d'un autre bouton ignoré")
r = gesture.feed(g, up(5, 5, 1), 0.1)
check(has(r, "click"), "le bouton suivi produit son clic")

# ---- glisser ----
g = gesture.create(4.0)
gesture.feed(g, down(100, 100), 0.0)
r = gesture.feed(g, move(102, 101), 0.01)
check(len(r) == 0 and not gesture.is_dragging(g), "sous le seuil : pas de glisser")
r = gesture.feed(g, move(110, 100), 0.02)
check(kinds(r) == ["drag_start", "drag_move"], "seuil dépassé : drag_start puis drag_move")
check(r[1]["dx"] == 10 and r[1]["total_dx"] == 10 and r[0]["start_x"] == 100, "premier drag_move : depuis l'appui")
r = gesture.feed(g, move(115, 104), 0.03)
check(kinds(r) == ["drag_move"] and r[0]["dx"] == 5 and r[0]["dy"] == 4 and r[0]["total_dy"] == 4, "drag_move : deltas incrémentaux")
r = gesture.feed(g, up(120, 104), 0.04)
check(kinds(r) == ["drag_end", "release"] and not has(r, "click"), "fin du glisser : pas de clic")
check(not gesture.is_pressed(g), "état réinitialisé")

# glisser annulé
g = gesture.create()
gesture.feed(g, down(0, 0), 0.0)
gesture.feed(g, move(50, 50), 0.01)
r = gesture.cancel(g)
check(kinds(r) == ["drag_cancel"] and not gesture.is_pressed(g), "cancel : drag_cancel")
check(len(gesture.feed(g, up(50, 50), 0.1)) == 0, "relâchement après cancel : ignoré")
check(len(gesture.cancel(g)) == 0, "cancel sans glisser : rien")

# ---- appui long ----
g = gesture.create(4.0, 0.4, 6.0, 0.5)
gesture.feed(g, down(30, 30), 0.0)
check(len(gesture.tick(g, 0.3)) == 0, "tick avant le délai : rien")
r = gesture.tick(g, 0.55)
check(kinds(r) == ["long_press"] and r[0]["x"] == 30, "appui long après 0.5 s")
check(len(gesture.tick(g, 0.9)) == 0, "appui long : une seule fois")
r = gesture.feed(g, up(30, 30), 1.0)
check(has(r, "release") and not has(r, "click"), "après appui long : pas de clic")
gesture.feed(g, down(30, 30), 2.0)
gesture.feed(g, move(60, 60), 2.1)
check(len(gesture.tick(g, 2.9)) == 0, "glisser en cours : pas d'appui long")
gesture.feed(g, up(60, 60), 3.0)

# ---- survol, molette, sortie ----
g = gesture.create()
r = gesture.feed(g, move(7, 8, 4), 0.0)
check(kinds(r) == ["hover"] and r[0]["x"] == 7 and r[0]["mods"] == 4, "hover avec modificateurs")
r = gesture.feed(g, {"type": "wheel", "x": 3, "y": 4, "dx": 0.0, "dy": -2.0, "mods": 2}, 0.0)
check(kinds(r) == ["wheel"] and r[0]["dy"] == -2.0 and r[0]["mods"] == 2, "wheel")
r = gesture.feed(g, {"type": "pointer_leave", "mods": 0}, 0.0)
check(kinds(r) == ["hover_end"], "pointer_leave -> hover_end")
r = gesture.feed(g, {"type": "resize", "x": 1, "y": 2}, 0.0)
check(len(r) == 0, "événement non pointeur : ignoré")
print("UI GESTURE: OK")
