# Test d'intégration X11 : widgets natifs émulés + événements réels (voir run_x11_test.sh)
use ui

win := ui.window("ALEX X11 Test", 480, 320, true)
btn := ui.button(win, "Valider", 20, 20, 120, 36)
chk := ui.checkbox(win, "Option A", 20, 70, 200, 28)
inp := ui.input_field(win, "", 20, 110, 260, 32)
bar := ui.progress_bar(win, 20, 160, 260, 18)
ui.progress_set_value(bar, 60)
ui.label(win, "Etat", 300, 20, 100, 28)
ui.show(win)

running := true
while running:
    ev := ui.poll(win)
    if ev == null:
        continue
    t := ui.event_type(ev)
    if t == "button":
        print("EVT button", ev["widget"] == btn)
    elif t == "check":
        print("EVT check", ev["widget"] == chk, ui.widget_get_checked(chk))
    elif t == "change":
        print("EVT change", ui.widget_get_text(inp))
    elif t == "key_down" and ev["key"] == 13:
        print("EVT enter")
    elif t == "close":
        running = false

print("FINAL text=" + ui.widget_get_text(inp))
print("FINAL checked", ui.widget_get_checked(chk))
ui.close(win)
