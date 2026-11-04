# Backend Win32 du module ui (runtime/alex/native/dyn_w32.al), sous Windows : vraie fenêtre, événements venus du
# système (WM_SIZE, WM_MOVE, WM_SETFOCUS...), rendu par SetDIBitsToDevice, état, fermeture. Lancé par
# tests/windows/suite.al ; ALEX_UI_HOLD=<secondes> garde la fenêtre affichée (contrôle visuel).
use _native_ui as n
use os
from core use len

func wait_for(w, kind, seconds):
    t0 := os.monotonic_time()
    seen := []
    while os.monotonic_time() - t0 < seconds:
        ev := n.window_poll(w)
        if ev == null:
            continue
        seen = seen + [ev["type"]]
        if ev["type"] == kind:
            return ev
    print("événement '" + kind + "' non reçu ; reçus : " + str(seen))
    os.exit(1)

func check(cond, what):
    if not cond:
        print("ÉCHEC : " + what)
        os.exit(1)
    print("ok " + what)

check(n.backend() == "win32", "backend win32 (obtenu " + n.backend() + ")")
sc := n.screen_info()
check(sc["width"] > 0 and sc["work_height"] > 0 and sc["work_height"] <= sc["height"], "écran " + str(sc["width"]) + "x" + str(sc["height"]))
w := n.window_create("ALEX Win32 Test", 420, 260, true)
check(n.dpi(w) >= 96, "dpi " + str(n.dpi(w)))
b := n.button_create(w, "Bouton ALEX", 20, 20, 160, 36)
n.input_create(w, "saisie é ☀", 20, 70, 260, 32)
n.checkbox_create(w, "Case", 20, 116, 160, 28)
n.window_show(w)
wait_for(w, "focus_in", 10.0)
n.window_set_size(w, 500, 300)
ev := wait_for(w, "resize", 10.0)
check(ev["x"] == 500 and ev["y"] == 300, "redimensionnement signalé par WM_SIZE (" + ev["data"] + ")")
n.window_set_position(w, 120, 140)
ev = wait_for(w, "move", 10.0)
inf := n.window_info(w)
check(inf["x"] == 120 and inf["y"] == 140, "position de la zone cliente (" + str(inf["x"]) + "," + str(inf["y"]) + ")")
n.window_set_title(w, "ALEX Win32 Test — titre é")
check(n.window_info(w)["title"] == "ALEX Win32 Test — titre é", "titre UTF-16")
hold := os.getenv("ALEX_UI_HOLD", "")
if hold != "":
    t0 := os.monotonic_time()
    while os.monotonic_time() - t0 < float(hold):
        n.window_poll(w)
n.window_set_state(w, "maximized")
ev = wait_for(w, "state", 10.0)
check(ev["data"] == "maximized", "état maximisé")
n.window_set_state(w, "normal")
wait_for(w, "state", 10.0)
check(n.window_info(w)["state"] == "normal", "état normal")
# clic injecté dans le cœur : le bouton est trouvé par la géométrie du rendu
n.inject_mouse(w, "click", 40, 30, 1, 0)
ev = wait_for(w, "button", 5.0)
check(ev["widget"] == b, "clic sur le bouton")
png := os.join(os.tmp_dir(), "alex_win32_ui.png")
check(n.window_screenshot(w, png) and os.isfile(png), "capture PNG de la fenêtre composée")
os.remove(png)
n.inject_close(w)
wait_for(w, "close", 5.0)
check(not n.window_info(w)["alive"], "fenêtre fermée (WM_CLOSE -> DestroyWindow)")
print("UI WIN32 : OK")
