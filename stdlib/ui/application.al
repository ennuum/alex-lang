from core use type, len
# ALEX STANDARD LIBRARY — ui.application V0.5
use ui.window as _window

func create(title="ALEX Application", width=900, height=600, resizable=true):
    handle := _window.window(title, width, height, resizable)
    return {"name": title, "windows": [handle]}

func add(app, window_handle):
    if app == null or type(app) != "dict":
        raise("TypeError", "ui.application.add() : application doit être un dict")
    if app["windows"] == null:
        app["windows"] = []
    __list_append(app["windows"], window_handle)
    return window_handle

func windows(app):
    return app["windows"]

func count(app):
    return len(app["windows"])
