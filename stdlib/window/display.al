# ALEX STANDARD LIBRARY — window.display
#
# Les écrans physiques branchés (moniteurs) : nom de sortie, fabricant et modèle (EDID), résolution et modes,
# taille physique, densité ; et l'écran logique du système de fenêtres (window.screen).
#
#   use window.display as display
#   for d in display.displays():
#       print(d.name, d.model, d.resolution, d.dpi, d.primary)
#   p := display.primary()                          # Display, ou null s'il n'y a pas d'information
#   print(display.summary())
#
# Les informations viennent de hardware.screen (/sys/class/drm, EDID, xrandr) : elles peuvent manquer dans une
# machine virtuelle ou un conteneur — displays() renvoie alors un écran unique déduit du système de fenêtres.

from core use len, type
from collections use append
use hardware.screen as _hw
use window.screen as _screen

class Display:
    func init(name, manufacturer, model, resolution, modes, width_mm, height_mm, primary, dpi, connected=true):
        self.name = name
        self.manufacturer = manufacturer
        self.model = model
        self.resolution = resolution     # [largeur, hauteur] ou null
        self.modes = modes
        self.width_mm = width_mm
        self.height_mm = height_mm
        self.primary = primary
        self.dpi = dpi
        self.connected = connected

    func diagonal_inches():
        if self.width_mm == null or self.height_mm == null or self.width_mm == 0:
            return null
        diag := _sqrt(self.width_mm * self.width_mm + self.height_mm * self.height_mm)
        return diag / 25.4

    func describe():
        t := self.name
        if self.model != null:
            t = t + " — " + str(self.model)
        if self.resolution != null:
            t = t + " " + str(self.resolution[0]) + "x" + str(self.resolution[1])
        if self.primary:
            t = t + " (principal)"
        return t

use math as _math

func _sqrt(x):
    return _math.sqrt(x)

func _from_hw(s, primary):
    d := null
    try:
        d = s.dpi()
    catch e:
        d = null
    return Display(s.name, s.manufacturer, s.model, s.resolution, s.modes, s.width_mm, s.height_mm, primary, d, s.connected)

func displays():
    out := []
    hw := []
    try:
        hw = _hw.screens()
    catch e:
        hw = []
    p := null
    try:
        p = _hw.primary()
    catch e:
        p = null
    for s in hw:
        append(out, _from_hw(s, p != null and s.name == p.name))
    if len(out) == 0:
        try:
            sc := _screen.current()
            append(out, Display("virtuel", null, null, [sc.width, sc.height], [[sc.width, sc.height]], null, null, true, sc.dpi))
        catch e:
            return out
    return out

func primary():
    for d in displays():
        if d.primary:
            return d
    ds := displays()
    if len(ds) > 0:
        return ds[0]
    return null

func count():
    return len(displays())

func summary():
    return [d.describe() for d in displays()]
