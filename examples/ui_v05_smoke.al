use ui

app := ui.application("ALEX V0.5", 900, 600)
main := app["windows"][0]

menu := ui.menu(main)
ui.menu_item(menu, 1001, "Quitter")
ui.menu_attach(main, menu)

ui.clipboard_set("ALEX UI V0.5")
text := ui.clipboard_get()

ui.notify("ALEX UI", "UI V0.5 active")

info := ui.screen_info()
print(info["width"])
print(info["height"])

ui.show(main)
ui.close(main)
print(text)
