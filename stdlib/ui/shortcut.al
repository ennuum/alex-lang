# ALEX STANDARD LIBRARY — ui.shortcut V0.5
use _native_ui as _native

# Modifiers Win32: ALT=1, CTRL=2, SHIFT=4, WIN=8
const ALT := 1
const CTRL := 2
const SHIFT := 4
const WIN := 8

func register(window, id, modifiers, key):
    return _native.shortcut_register(window, id, modifiers, key)

func unregister(window, id):
    return _native.shortcut_unregister(window, id)
