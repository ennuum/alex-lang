# ALEX UI V0.8 — Images
from core use type
use _native_ui as _ui_native

func load(path):
    if type(path) != "str":
        raise("TypeError", "ui.image.load() : path doit être une str")
    h := _ui_native.image_load(path)
    if type(h) != "int" or h == 0:
        raise("RuntimeError", "ui.image.load() : impossible de charger l'image")
    return {"handle":h,"path":path}

func destroy(image):
    return _ui_native.image_destroy(image["handle"])

# [largeur, hauteur] d'une image.
func size(image):
    return _ui_native.image_size(image["handle"])

# Nouvelle image : copie de la zone (x, y, l, h) (sprites, atlas, tuiles).
func crop(image, x, y, w, h):
    return {"handle": _ui_native.image_crop(image["handle"], x, y, w, h), "path": image["path"] if "path" in image else null}

# Image depuis des octets RGBA (list d'entiers 0..255, ligne du haut en premier).
func create(width, height, pixels):
    return {"handle": _ui_native.image_create(width, height, pixels), "path": null}
