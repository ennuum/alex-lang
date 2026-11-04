# ALEX STANDARD LIBRARY — ui.menu V0.5
use _native_ui as _native

func create(window):
    return _native.menu_create(window)

func item(menu, id, text):
    return _native.menu_add_item(menu, id, text)

func attach(window, menu):
    return _native.menu_attach(window, menu)
