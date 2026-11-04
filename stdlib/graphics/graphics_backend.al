# ALEX STANDARD LIBRARY — graphics.graphics_backend
#
# Choix du dorsal de rendu et de présentation. Le rendu lui-même est le pipeline logiciel de graphics ; ce qui
# change d'un dorsal à l'autre est où l'image est présentée et ce qui est disponible sur la machine :
#   « software »  toujours disponible : rendu en mémoire (présentation en mémoire)
#   « headless »  rendu en mémoire + images enregistrées en PPM dans un dossier (serveurs, tests, CI)
#   « window »    fenêtre du paquet ui (si un affichage est disponible)
#   « fbdev »     écran Linux sans serveur graphique (/dev/fb0, graphics.framebuffer.FbDevice)
#   « drm »       détecté seulement (nœuds /dev/dri) : le rendu accéléré passe par gpu_driver dans un noyau Alex,
#                 ce dorsal n'est jamais choisi automatiquement ici et le dit (aucune accélération simulée).
#
#   use graphics.graphics_backend as gbk
#   for b in gbk.backends():
#       print(b.name + " : " + str(b.available()) + " — " + b.reason())
#   b := gbk.select()                  # ALEX_GRAPHICS_BACKEND, sinon le premier disponible de l'ordre préféré
#   ctx := b.context()
#   sc := b.swapchain(320, 240)
#
# Erreurs : BackendUnavailable (dorsal demandé indisponible ou inconnu).

from core use len
from collections use append
use os as _os
use string as _s
use hardware._sys as _sys
use graphics.context as _ctx
use graphics.swapchain as _sc
use graphics.framebuffer as _fb

class Backend:
    func init(name, description):
        self.name = name
        self.description = description

    func available():
        return true

    func reason():
        return "disponible"

    func context():
        if not self.available():
            raise("BackendUnavailable", "dorsal « " + self.name + " » indisponible : " + self.reason())
        return _ctx.Context(self.name)

    func presenter(width, height):
        return _sc.MemoryPresenter()

    func swapchain(width, height, images=2):
        if not self.available():
            raise("BackendUnavailable", "dorsal « " + self.name + " » indisponible : " + self.reason())
        return _sc.Swapchain(width, height, images, self.presenter(width, height))

    func describe():
        st := "disponible" if self.available() else "indisponible (" + self.reason() + ")"
        return self.name + " — " + self.description + " : " + st

class SoftwareBackend extends Backend:
    func init():
        super.init("software", "pipeline logiciel, présentation en mémoire")

class HeadlessBackend extends Backend:
    func init(directory=null):
        super.init("headless", "pipeline logiciel, images PPM numérotées")
        self.directory = directory if directory != null else _os.tmp_dir() + "/alex-graphics"

    func presenter(width, height):
        if not _os.isdir(self.directory):
            _os.mkdir_all(self.directory)
        return _sc.FilePresenter(self.directory + "/frame")

class WindowBackend extends Backend:
    func init():
        super.init("window", "fenêtre du paquet ui")

    func available():
        b := _os.getenv("ALEX_UI_BACKEND")
        if b == "headless":
            return true
        return _os.getenv("DISPLAY") != null or _os.getenv("WAYLAND_DISPLAY") != null

    func reason():
        if self.available():
            return "disponible"
        return "aucun affichage (DISPLAY / WAYLAND_DISPLAY absents)"

class FbdevBackend extends Backend:
    func init(path="/dev/fb0"):
        super.init("fbdev", "écran Linux " + path)
        self.path = path

    func available():
        try:
            _fb.FbDevice(self.path)
            return true
        catch e:
            return false

    func reason():
        try:
            d := _fb.FbDevice(self.path)
            return d.describe()
        catch e:
            return e.message

    func presenter(width, height):
        return _fb.FbPresenter(_fb.FbDevice(self.path))

class DrmBackend extends Backend:
    func init():
        super.init("drm", "cartes /dev/dri (détection seulement)")

    func nodes():
        out := []
        for n in _sys.list("/dev/dri"):
            append(out, "/dev/dri/" + n)
        return out

    func available():
        return false

    func reason():
        n := self.nodes()
        if len(n) == 0:
            return "aucun nœud /dev/dri"
        return str(len(n)) + " nœud(s) " + _s.join(", ", n) + " détecté(s) ; rendu accéléré non fourni par graphics (voir gpu_driver)"

_registry := [SoftwareBackend(), HeadlessBackend(), WindowBackend(), FbdevBackend(), DrmBackend()]

func backends():
    return [b for b in _registry]

func names():
    return [b.name for b in _registry]

func register(backend):
    i := 0
    while i < len(_registry):
        if _registry[i].name == backend.name:
            _registry[i] = backend
            return backend
        i += 1
    append(_registry, backend)
    return backend

func get(name):
    for b in _registry:
        if b.name == name:
            return b
    raise("BackendUnavailable", "dorsal graphique inconnu « " + str(name) + " » (" + _s.join(", ", names()) + ")")

# Dorsal choisi : variable ALEX_GRAPHICS_BACKEND (doit être disponible), sinon le premier disponible de
# preferred, sinon « software ».
func select(preferred=null):
    env := _os.getenv("ALEX_GRAPHICS_BACKEND")
    if env != null and env != "":
        b := get(env)
        if not b.available():
            raise("BackendUnavailable", "ALEX_GRAPHICS_BACKEND=" + env + " : " + b.reason())
        return b
    order := preferred if preferred != null else ["window", "fbdev", "software"]
    for n in order:
        b := get(n)
        if b.available():
            return b
    return get("software")

func report():
    return [b.describe() for b in _registry]
