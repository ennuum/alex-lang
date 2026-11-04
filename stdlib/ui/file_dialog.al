# ALEX STANDARD LIBRARY — ui.file_dialog V0.5
use _native_ui as _native

func open(filter="Tous les fichiers\0*.*\0"):
    return _native.file_open(filter)

func save(filter="Tous les fichiers\0*.*\0"):
    return _native.file_save(filter)
