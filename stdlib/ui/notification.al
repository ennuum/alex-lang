# ALEX STANDARD LIBRARY — ui.notification V0.5
use _native_ui as _native

func show(title, message):
    return _native.notify(title, message)

func info(title, message):
    return show(title, message)
