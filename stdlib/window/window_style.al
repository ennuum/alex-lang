# ALEX STANDARD LIBRARY — window.window_style
#
# Styles de fenêtre : un ensemble de réglages appliqués d'un coup (redimensionnable, décorée, toujours devant,
# opacité, tailles minimale et maximale), avec des préréglages usuels.
#
#   use window.window_style as wst
#   wst.DIALOG.apply(fenetre)                     # taille fixe, décorée
#   s := wst.WindowStyle()                        # style par défaut
#   s.topmost = true
#   s.opacity = 0.9
#   s.min_size = (320, 200)
#   s.apply(fenetre)
#
# Préréglages : DEFAULT, DIALOG, TOOL (petite, toujours devant), BORDERLESS (sans bordure), OVERLAY (sans
# bordure, toujours devant, semi-transparente), KIOSK (plein écran sans bordure, fixe).
#
# Erreurs : ArgumentError (opacité hors de 0..1, tailles incohérentes).

from core use type

class WindowStyle:
    func init(resizable=true, decorated=true, topmost=false, opacity=1.0, min_size=null, max_size=null, fullscreen=false):
        self.resizable = resizable
        self.decorated = decorated
        self.topmost = topmost
        self.opacity = opacity
        self.min_size = min_size       # (largeur, hauteur) ou null
        self.max_size = max_size
        self.fullscreen = fullscreen

    func validate():
        if self.opacity < 0 or self.opacity > 1:
            raise("ArgumentError", "WindowStyle : opacité hors de 0..1")
        if self.min_size != null and self.max_size != null:
            if self.max_size[0] < self.min_size[0] or self.max_size[1] < self.min_size[1]:
                raise("ArgumentError", "WindowStyle : taille maximale inférieure à la minimale")
        return self

    func copy():
        return WindowStyle(self.resizable, self.decorated, self.topmost, self.opacity, self.min_size, self.max_size, self.fullscreen)

    # Applique à une window.Window.
    func apply(win):
        self.validate()
        win.set_hints(self.resizable, self.decorated, self.topmost, self.opacity, self.min_size, self.max_size)
        if self.fullscreen:
            win.set_state("fullscreen")
        return win

    func to_dict():
        return {"resizable": self.resizable, "decorated": self.decorated, "topmost": self.topmost,
                "opacity": self.opacity, "min_size": self.min_size, "max_size": self.max_size, "fullscreen": self.fullscreen}

# Style d'une window.Window (lu dans ses informations).
func of(win):
    i := win.info()
    mn := null
    mx := null
    if i["min_width"] > 0 or i["min_height"] > 0:
        mn = (i["min_width"], i["min_height"])
    if i["max_width"] > 0 or i["max_height"] > 0:
        mx = (i["max_width"], i["max_height"])
    return WindowStyle(i["resizable"], i["decorated"], i["topmost"], i["opacity"], mn, mx, i["state"] == "fullscreen")

DEFAULT := WindowStyle()
DIALOG := WindowStyle(false, true, false, 1.0)
TOOL := WindowStyle(true, true, true, 1.0, (160, 100))
BORDERLESS := WindowStyle(true, false, false, 1.0)
OVERLAY := WindowStyle(false, false, true, 0.85)
KIOSK := WindowStyle(false, false, true, 1.0, null, null, true)

func preset(name):
    p := {"default": DEFAULT, "dialog": DIALOG, "tool": TOOL, "borderless": BORDERLESS, "overlay": OVERLAY, "kiosk": KIOSK}
    for k in ["default", "dialog", "tool", "borderless", "overlay", "kiosk"]:
        if k == name:
            return p[k].copy()
    raise("ArgumentError", "window_style.preset : préréglage inconnu '" + str(name) + "'")
