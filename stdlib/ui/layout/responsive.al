# Responsive layout: switches between vertical and horizontal flow.
use ui.layout.vbox as _vbox
use ui.layout.hbox as _hbox

func apply(children, width, height, breakpoint=700, gap=8, padding=8, alignment="start"):
    if breakpoint == null:
        breakpoint = 700
    if width < breakpoint:
        return _vbox.apply(children, width, height, gap, padding, alignment)
    return _hbox.apply(children, width, height, gap, padding, alignment)
