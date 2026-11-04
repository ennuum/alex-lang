# Test d'intégration X11 (V1.3) : événements réels envoyés par tests/ui/x11_driver — boutons, molette,
# modificateurs, sortie du pointeur, curseurs et fermeture avec confirmation (WM_DELETE_WINDOW).
use ui
use ui.gesture as gesture
use os

win := ui.window("ALEX X11 Gestes", 400, 300, true)
ui.button(win, "Cible", 20, 20, 100, 40)
ui.set_confirm_close(win, true)
ui.show(win)
ui.set_cursor(win, "pointer")
g := gesture.create()
closes := 0
running := true
while running:
    ev := ui.poll(win)
    if ev == null:
        continue
    t := ev["type"]
    if t == "close_request":
        closes += 1
        print("EVT close_request " + str(closes))
        if closes == 2:
            ui.close(win)
            running = false
    elif t == "close":
        running = false
    elif t == "wheel":
        print("EVT wheel " + str(ev["dy"]) + " " + str(ev["dx"]) + " " + str(ev["mods"]))
    elif t == "pointer_leave":
        print("EVT leave")
    elif t == "pointer_down" or t == "pointer_up" or t == "pointer_move":
        for ge in gesture.feed(g, ev, os.monotonic_time()):
            ty := ge["type"]
            if ty == "click" or ty == "double_click" or ty == "context" or ty == "drag_end" or ty == "middle_click":
                print("EVT " + ty + " " + str(ge["x"]) + " " + str(ge["y"]))
    elif t == "key_down":
        print("EVT key " + str(ev["key"]) + " " + str(ev["mods"]) + " " + ev["text"])
print("FIN cursor=" + ui.get_cursor(win))
