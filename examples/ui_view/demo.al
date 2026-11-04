# Démonstration de ui.view : la même vue dans le terminal (tui) et dans une fenêtre (gui).
#   ./alex run examples/ui_view/demo.al          (terminal)
#   ./alex run examples/ui_view/demo.al gui      (fenêtre)

from core use len
use os
use tui
use gui
use examples.ui_view.demo_view as d

args := os.args()
if len(args) > 0 and args[0] == "gui":
    gui.run(d.vue, "Démo ui.view", 900, 640)
else:
    tui.run(d.vue, "Démo ui.view")
