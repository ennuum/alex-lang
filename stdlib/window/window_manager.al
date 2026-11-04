# ALEX STANDARD LIBRARY — window.window_manager
#
# Gestion de PLUSIEURS fenêtres : création, recherche, fenêtre active, boucle d'événements commune (synchrone ou
# async) qui s'arrête quand la dernière fenêtre se ferme, disposition automatique (cascade, mosaïque), et
# sauvegarde / restauration des positions.
#
#   use window.window_manager as wm
#   m := wm.WindowManager()
#   a := m.create("Éditeur", 800, 600)
#   b := m.create("Aperçu", 400, 600)
#   m.tile()                                  # côte à côte dans la zone de travail
#   m.on_close(a, () => m.close_all())        # fermer l'éditeur ferme tout
#   await m.run_async()                       # jusqu'à la fermeture de toutes les fenêtres
#
#   m.save_layout("~/.config/appli/fenetres.json")
#   m.restore_layout("~/.config/appli/fenetres.json")   # par titre de fenêtre
#
# Erreurs : ArgumentError (fenêtre inconnue), IoError.

from core use len, type
from collections use append, contains_key, keys
use asyncio
use os as _os
use json as _json
use file as _file
use window as _w
use window.window_state as _ws
use window.screen as _screen

class WindowManager:
    func init():
        self._windows = []

    func create(title="Alex", width=800, height=600, options=null):
        win := _w.Window(title, width, height, options)
        return self.add(win)

    # Prend en charge une window.Window existante.
    func add(win):
        append(self._windows, win)
        return win

    func remove(win):
        self._windows = [w for w in self._windows if w != win]

    func windows():
        return [w for w in self._windows if w.is_open()]

    func count():
        return len(self.windows())

    # Fenêtres encore actives : ouvertes et, sous headless, dont la file n'est pas vide.
    func active():
        return len([w for w in self.windows() if not w.idle()]) > 0

    func get(handle):
        for w in self._windows:
            if w.handle == handle:
                return w
        raise("ArgumentError", "WindowManager.get : fenêtre inconnue " + str(handle))

    func find(title):
        for w in self.windows():
            if w.title() == title:
                return w
        return null

    # Fenêtre qui a le focus, ou null.
    func focused():
        for w in self.windows():
            if w.focused():
                return w
        return null

    func on_close(win, fn):
        win.on("close", fn)

    func close_all():
        for w in self._windows:
            w.close()

    func minimize_all():
        for w in self.windows():
            w.minimize()

    func restore_all():
        for w in self.windows():
            w.restore()

    # Traite les événements de toutes les fenêtres ; renvoie leur nombre.
    func dispatch_events():
        n := 0
        for w in [x for x in self._windows]:
            if w.is_open():
                n += w.dispatch_events()
        return n

    # Boucle bloquante jusqu'à la fermeture de toutes les fenêtres (frame() à chaque tour).
    func run(frame=null, fps=60):
        for w in self.windows():
            w.show()
        while self.active():
            self.dispatch_events()
            if frame != null:
                frame()
            _os.sleep(1.0 / fps)

    func run_async(frame=null, fps=60):
        for w in self.windows():
            w.show()
        return _run(self, frame, fps)

    # Fenêtres en cascade depuis (x, y), décalées de step pixels.
    func cascade(x=40, y=40, step=32):
        k := 0
        for w in self.windows():
            w.restore()
            w.move(x + k * step, y + k * step)
            k += 1

    # Mosaïque : colonnes égales dans la zone de travail (au plus columns colonnes, puis rangées).
    func tile(columns=null):
        ws := self.windows()
        n := len(ws)
        if n == 0:
            return
        if columns == null:
            columns = n
            if n > 3:
                columns = _ceil_sqrt(n)
        rows := (n + columns - 1) // columns
        s := _screen.current()
        cw := s.work_width // columns
        rh := s.work_height // rows
        k := 0
        for w in ws:
            w.restore()
            w.set_size(cw, rh)
            w.move((k % columns) * cw, (k // columns) * rh)
            k += 1

    # Écrit {titre: géométrie} de chaque fenêtre en JSON.
    func save_layout(path):
        d := {}
        for w in self.windows():
            d[w.title()] = w.snapshot().to_dict()
        p := path
        if len(p) > 0 and p[0] == '~':
            p = _os.home() + _sub(p, 1)
        parent := _os.dirname(p)
        if parent != "" and not _os.exists(parent):
            _os.mkdir_all(parent)
        _file.write_atomic(p, _json.pretty(d))
        return len(keys(d))

    # Applique la géométrie sauvegardée aux fenêtres de même titre ; renvoie leur nombre.
    func restore_layout(path):
        p := path
        if len(p) > 0 and p[0] == '~':
            p = _os.home() + _sub(p, 1)
        if not _os.exists(p):
            return 0
        d := _json.parse(_file.read(p))
        s := _screen.current()
        n := 0
        for w in self.windows():
            t := w.title()
            if contains_key(d, t):
                _ws.from_dict(d[t]).clamp_to(s.work_width, s.work_height).apply(w)
                n += 1
        return n

use string as _str

func _sub(s, start):
    return _str.substring(s, start, len(s))

func _ceil_sqrt(n):
    k := 1
    while k * k < n:
        k += 1
    return k

async func _run(m, frame, fps):
    while m.active():
        m.dispatch_events()
        if frame != null:
            r := frame()
            if asyncio.is_future(r):
                await r
        await asyncio.sleep(1.0 / fps)
    return null

_default := [null]

func default():
    if _default[0] == null:
        _default[0] = WindowManager()
    return _default[0]
