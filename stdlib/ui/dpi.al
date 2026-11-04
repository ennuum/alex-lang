# ALEX STANDARD LIBRARY — ui.dpi V0.5
use _native_ui as _native

func get(window):
    return _native.dpi(window)

func scale(window):
    return get(window) / 96.0
