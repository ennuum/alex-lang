# ALEX STANDARD LIBRARY — window.screen
#
# L'écran vu par le système de fenêtres : taille, zone de travail (hors barres et docks), densité (DPI) et facteur
# d'échelle ; placement d'une fenêtre (centrer, coin, demi-écran).
#
#   use window.screen as screen
#   s := screen.current()
#   print(s.width, s.height, s.work_width, s.work_height, s.dpi, s.scale)
#   screen.center(fenetre)
#   screen.place(fenetre, "right_half")            # moitié droite de la zone de travail
#   print(s.dp_to_px(16))                          # 16 points « indépendants » en pixels
#
# Erreurs : IoError (pas d'affichage : utiliser ALEX_UI_BACKEND=headless pour un écran virtuel 1920x1080).

from core use type, to_int
use _native_ui as _ui

class Screen:
    func init(width, height, work_width, work_height, dpi):
        self.width = width
        self.height = height
        self.work_width = work_width
        self.work_height = work_height
        self.dpi = dpi
        self.scale = dpi / 96.0

    func size():
        return (self.width, self.height)

    func work_area():
        return (0, 0, self.work_width, self.work_height)

    # Points indépendants de la densité (96 par pouce) -> pixels, et inversement.
    func dp_to_px(dp):
        return to_int(dp * self.scale + 0.5)

    func px_to_dp(px):
        return px / self.scale

    func contains(x, y):
        return x >= 0 and y >= 0 and x < self.width and y < self.height

    func to_dict():
        return {"width": self.width, "height": self.height, "work_width": self.work_width,
                "work_height": self.work_height, "dpi": self.dpi, "scale": self.scale}

func current(win=null):
    i := _ui.screen_info()
    h := 0
    if win != null:
        h = _handle(win)
    d := 96
    try:
        d = _ui.dpi(h)
    catch e:
        d = 96
    return Screen(i["width"], i["height"], i["work_width"], i["work_height"], d)

func _handle(win):
    if type(win) == "int":
        return win
    return win.handle

# Centre la fenêtre dans la zone de travail.
func center(win):
    s := current()
    sz := win.size()
    win.move((s.work_width - sz[0]) // 2, (s.work_height - sz[1]) // 2)
    return win

# Place la fenêtre : center, top_left, top_right, bottom_left, bottom_right, left_half, right_half, top_half,
# bottom_half, maximize (sans changer l'état).
func place(win, where, margin=0):
    s := current()
    W := s.work_width
    H := s.work_height
    sz := win.size()
    w := sz[0]
    h := sz[1]
    if where == "center":
        win.move((W - w) // 2, (H - h) // 2)
    elif where == "top_left":
        win.move(margin, margin)
    elif where == "top_right":
        win.move(W - w - margin, margin)
    elif where == "bottom_left":
        win.move(margin, H - h - margin)
    elif where == "bottom_right":
        win.move(W - w - margin, H - h - margin)
    elif where == "left_half":
        win.set_size(W // 2, H)
        win.move(0, 0)
    elif where == "right_half":
        win.set_size(W - W // 2, H)
        win.move(W // 2, 0)
    elif where == "top_half":
        win.set_size(W, H // 2)
        win.move(0, 0)
    elif where == "bottom_half":
        win.set_size(W, H - H // 2)
        win.move(0, H // 2)
    elif where == "maximize":
        win.set_size(W, H)
        win.move(0, 0)
    else:
        raise("ArgumentError", "screen.place : position inconnue '" + str(where) + "'")
    return win
