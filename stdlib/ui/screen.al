# ALEX STANDARD LIBRARY — ui.screen V0.5
use _native_ui as _native

func info():
    return _native.screen_info()

func width():
    return info()["width"]

func height():
    return info()["height"]

func work_width():
    return info()["work_width"]

func work_height():
    return info()["work_height"]
