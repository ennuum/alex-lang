# Tests du backend UI portable en mode headless (ALEX_UI_BACKEND=headless).
# Widgets natifs émulés + moteur d'interaction : clic, clavier, tab, radio, combo, menu, raccourcis, canvas.
from core use type, len
use collections
use ui

func check(cond, name):
    if not cond:
        raise("AssertionError", "ÉCHEC : " + name)
    print("ok  " + name)

# Retourne la liste des types d'événements en attente (sans la fermeture synthétique).
func drain(win):
    out := []
    running := true
    while running:
        ev := ui.poll(win)
        if ev == null:
            running = false
        elif ui.event_type(ev) != "close":
            collections.append(out, ev)
    return out

func find(events, kind):
    for ev in events:
        if ev["type"] == kind:
            return ev
    return null

check(ui.backend() == "headless", "backend = headless")
check(ui.available(), "available()")

win := ui.window("Test", 400, 300, true)
btn := ui.button(win, "OK", 10, 10, 100, 30)
chk := ui.checkbox(win, "Case", 10, 50, 150, 24)
r1 := ui.radio_button(win, "A", 10, 80, 100, 24)
r2 := ui.radio_button(win, "B", 10, 110, 100, 24)
inp := ui.input_field(win, "", 10, 140, 200, 28)
cmb := ui.combo_box(win, "choix", 10, 180, 150, 28)
ui.combo_add_item(cmb, "un")
ui.combo_add_item(cmb, "deux")
ui.combo_add_item(cmb, "trois")
bar := ui.progress_bar(win, 10, 220, 200, 16)
ui.show(win)
drain(win)

# --- bouton
ui.inject_mouse(win, "click", 50, 25)
ev := find(drain(win), "button")
check(ev != null and ev["widget"] == btn, "clic bouton -> événement button")

# --- bouton désactivé : aucun événement
ui.widget_set_enabled(btn, false)
ui.inject_mouse(win, "click", 50, 25)
check(find(drain(win), "button") == null, "bouton désactivé : pas d'événement")
ui.widget_set_enabled(btn, true)

# --- case à cocher
ui.inject_mouse(win, "click", 20, 60)
ev = find(drain(win), "check")
check(ev != null and ui.widget_get_checked(chk), "clic checkbox -> coché")
ui.inject_mouse(win, "click", 20, 60)
drain(win)
check(not ui.widget_get_checked(chk), "second clic -> décoché")

# --- radios exclusifs
ui.inject_mouse(win, "click", 15, 90)
drain(win)
ui.inject_mouse(win, "click", 15, 120)
drain(win)
check(not ui.widget_get_checked(r1) and ui.widget_get_checked(r2), "radios mutuellement exclusifs")

# --- saisie (UTF-8, retour arrière, Delete, Home/End)
ui.inject_mouse(win, "click", 100, 154)
ui.inject_text(win, "Café")
check(ui.widget_get_text(inp) == "Café", "saisie UTF-8")
ui.inject_key(win, 8, 0)
check(ui.widget_get_text(inp) == "Caf", "Backspace retire un caractère UTF-8 entier")
ui.inject_key(win, 36, 0)
ui.inject_text(win, ">")
check(ui.widget_get_text(inp) == ">Caf", "Home puis insertion")
ui.inject_key(win, 35, 0)
ui.inject_text(win, "é!")
check(ui.widget_get_text(inp) == ">Café!", "End puis insertion")
ev = find(drain(win), "change")
check(ev != null and ev["widget"] == inp, "événement change émis")

# --- navigation clavier : Tab ; Entrée sur le bouton
ui.inject_mouse(win, "click", 300, 280)
ui.inject_key(win, 9, 0)
ui.inject_key(win, 13, 0)
check(find(drain(win), "button") != null, "Tab focalise le bouton, Entrée l'active")

# --- combo : ouvrir puis choisir "deux"
ui.inject_mouse(win, "click", 80, 194)
ui.inject_mouse(win, "click", 80, 180 + 28 + 24 + 10)
drain(win)
check(ui.widget_get_text(cmb) == "deux", "combo : sélection par clic")

# --- progression, texte, visibilité
ui.progress_set_value(bar, 60)
bad := false
try:
    ui.progress_set_value(bar, 150)
catch e0:
    bad = true
check(bad, "progress hors 0..100 -> erreur")
ui.widget_set_text(btn, "Nouveau")
check(ui.widget_get_text(btn) == "Nouveau", "widget_set_text / get_text")
ui.widget_set_visible(btn, false)
ui.inject_mouse(win, "click", 50, 25)
check(find(drain(win), "button") == null, "widget invisible : insensible au clic")

# --- raccourcis
ui.shortcut_register(win, 7, 2, 83)
ui.inject_key(win, 83, 2)
ev = find(drain(win), "shortcut")
check(ev != null and ev["widget"] == 7, "raccourci Ctrl+S")

# --- menu
m := ui.menu(win)
ui.menu_item(m, 1001, "Fichier")
ui.menu_item(m, 1002, "Quitter")
ui.menu_attach(win, m)
ui.inject_mouse(win, "click", 5, -20)
drain(win)

# --- pointeur (pour ui.widgets.dispatch)
ui.inject_mouse(win, "move", 120, 200)
ev = find(drain(win), "pointer_move")
check(ev != null and ev["x"] == 120 and ev["y"] == 200, "pointer_move avec coordonnées client")

# --- capture
check(ui.screenshot(win, "/tmp/alex_ui_headless_test.png"), "screenshot PNG")
check(ui.screen_info()["width"] > 0, "screen_info")
check(ui.dpi(win) >= 48, "dpi")

# --- erreurs
failed := false
try:
    ui.widget_set_text(999999, "x")
catch e:
    failed = true
check(failed, "handle widget inconnu -> erreur")

ui.close(win)
print("UI HEADLESS: OK")
