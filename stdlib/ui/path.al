# ALEX UI V0.8 — Vector paths
from core use type
use _native_ui as _ui_native

func _h(name, h):
    if type(h) != "int":
        raise("TypeError", "ui.path." + name + "() : handle invalide")

func create():
    h := _ui_native.path_create()
    _h("create", h)
    return {"handle":h}

func move_to(path,x,y):
    _h("move_to", path["handle"])
    return _ui_native.path_move_to(path["handle"],x,y)

func line_to(path,x,y):
    _h("line_to", path["handle"])
    return _ui_native.path_line_to(path["handle"],x,y)

func cubic_to(path,x1,y1,x2,y2,x3,y3):
    _h("cubic_to", path["handle"])
    return _ui_native.path_cubic_to(path["handle"],x1,y1,x2,y2,x3,y3)

func quad_to(path,x1,y1,x2,y2):
    _h("quad_to", path["handle"])
    return _ui_native.path_quad_to(path["handle"],x1,y1,x2,y2)

func close(path):
    _h("close", path["handle"])
    return _ui_native.path_close(path["handle"])

func destroy(path):
    _h("destroy", path["handle"])
    return _ui_native.path_destroy(path["handle"])
