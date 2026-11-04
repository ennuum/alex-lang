# ALEX STANDARD LIBRARY — ui.clipboard V0.5
use _native_ui as _native

func set_text(text):
    return _native.clipboard_set(text)

func get_text():
    return _native.clipboard_get()
