# Régression : substitution des valeurs par défaut (appels positionnels,
# nommés et via module) + widgets/layout du module UI.
from core use type

func check(cond, name):
    if not cond:
        raise("AssertionError", "échec de test")
use ui.paint as paint
use ui.layout as layout
use ui.widgets as widgets

const K := 1.0
func f(a, b=K, c=2):
    return [a, b, c]
r := f(1)
check(r[1] == 1.0, "ok")
check(r[2] == 2, "ok")
r = f(1, 5)
check(r[1] == 5 and r[2] == 2, "ok")
r = f(1, c=9)
check(r[1] == 1.0 and r[2] == 9, "ok")

p := paint.fill({"r":1,"g":2,"b":3,"a":255})
check(p["opacity"] == 1.0, "ok")
check(paint.stroke({"r":1,"g":2,"b":3,"a":255})["width"] == 1.0, "ok")

root := layout.container("root",0,0,900,600)
layout.column(root)
layout.add(root, widgets.button("OK"))
layout.perform(root, 900, 600)
check(root["children"][0]["width"] == 120.0, "ok")
print("DEFAULTS+UI: OK")
