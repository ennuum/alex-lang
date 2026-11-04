# Application pilotée par tests/window/run_x11_window.sh sous Xvfb (sans gestionnaire de fenêtres) : vérifie
# les déplacements, états émulés, focus et événements clavier réels (pressions ET relâchements X).
from core use len
from collections use append
use asyncio
use window
use keyboard.key as key

w := window.Window("ALEX Window Test", 320, 200)
log := []
w.on("key", (k) => append(log, k.key + ":" + k.action))
w.on("move", (ev) => append(log, "move"))
w.on("focus_in", (ev) => append(log, "focus"))
w.show()
await asyncio.sleep(0.2)
w.dispatch_events()
w.move(150, 100)
await asyncio.sleep(0.2)
w.dispatch_events()
print("POS " + str(w.position()))
w.maximize()
await asyncio.sleep(0.2)
w.dispatch_events()
print("MAX " + w.state() + " " + str(w.size()))
w.restore()
await asyncio.sleep(0.2)
w.dispatch_events()
print("RESTORE " + w.state() + " " + str(w.size()))
w.focus()
await asyncio.sleep(0.2)
w.dispatch_events()
print("FOCUSED " + str(w.focused()))
async func until_closed():
    while w.is_open():
        w.dispatch_events()
        await asyncio.sleep(0.01)
await until_closed()
print("LOG " + str(log))
print("PRESSED " + str(w.keyboard.pressed()))
