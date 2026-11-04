# ALEX STANDARD LIBRARY — web.browser.local_storage
#
# Stockage Web (window.local_storage) : paires texte -> texte par origine, avec quota (5 Mio par défaut,
# comptés comme en UTF-16), QuotaExceededError, persistance facultative dans un fichier JSON, et événements
# « storage » vers les AUTRES fenêtres de la même origine (StorageEvent : key, old_value, new_value, url).
#
#   use web.browser.local_storage as ls
#   st := ls.Storage("https://exemple.org")
#   st.set_item("theme", "sombre")
#   st.get_item("theme")               # sombre
#   st.length(), st.key(0)             # 1 theme
#   st.remove_item("theme"); st.clear()
#   p := ls.Storage("https://exemple.org", 5 * 1024 * 1024, "/tmp/stockage.json")   # persistant
#   ls.StorageArea()                   # registre des stockages par origine (partagé par un navigateur)
#
# Erreurs : QuotaExceededError (quota dépassé), BrowserError (fichier de persistance illisible).

from core use len, type
from collections use append, keys
use string as _s
use json as _json
use io as _io
use os as _os
use web.browser.browser_errors as _err
use web.dom.event as _ev
use web.dom.event_target as _et
from web.dom.event use Event

const DEFAULT_QUOTA := 5242880

class StorageEvent extends Event:
    func init(key, old_value, new_value, url, storage_area):
        super.init("storage")
        self.key = key
        self.old_value = old_value
        self.new_value = new_value
        self.url = url
        self.storage_area = storage_area

# Taille comptée comme en UTF-16 (unités de code, × 2 octets).
func _units(text):
    n := 0
    for c in text:
        n += 2 if _s.ord(c) > 0xFFFF else 1
    return n

class Storage:
    # quota : en unités UTF-16 × 2 (octets) ; path : fichier JSON de persistance (null : en mémoire).
    func init(origin="null", quota=5242880, path=null, kind="local"):
        self.origin = origin
        self.quota = quota
        self.path = path
        self.kind = kind
        self.items = {}
        self.order = []
        self.listeners = []          # fonctions (StorageEvent, source) : diffusion aux fenêtres
        self.source = null           # fenêtre à l'origine de la modification en cours
        if path != null and _os.exists(path):
            self._load()

    func _load():
        try:
            d := _json.parse(_io.read_file(self.path))
            for k in keys(d):
                self.items[k] = str(d[k])
                append(self.order, k)
        catch e:
            _err.browser_error("Storage", "fichier de stockage illisible « " + str(self.path) + " »")

    func _save():
        if self.path != null:
            _io.write_file(self.path, _json.stringify(self.items, 2, false))

    func used_bytes():
        n := 0
        for k in self.order:
            n += (_units(k) + _units(self.items[k])) * 2
        return n

    func length():
        return len(self.order)

    func __len__():
        return len(self.order)

    func key(i):
        if i < 0 or i >= len(self.order):
            return null
        return self.order[i]

    func get_item(name):
        k := str(name)
        if k in self.items:
            return self.items[k]
        return null

    func __getitem__(name):
        return self.get_item(name)

    func __contains__(name):
        return str(name) in self.items

    func set_item(name, value):
        k := str(name)
        v := str(value) if type(value) != "bool" else ("true" if value else "false")
        old := self.items[k] if k in self.items else null
        if old == v:
            return
        size := self.used_bytes() - ((_units(k) + _units(old)) * 2 if old != null else 0) + (_units(k) + _units(v)) * 2
        if size > self.quota:
            _err.quota_error("Storage.set_item", "quota de " + str(self.quota) + " octets dépassé pour « " + self.origin + " »")
        if old == null:
            append(self.order, k)
        self.items[k] = v
        self._save()
        self._broadcast(k, old, v)

    func remove_item(name):
        k := str(name)
        if not (k in self.items):
            return
        old := self.items[k]
        out := {}
        for x in keys(self.items):
            if x != k:
                out[x] = self.items[x]
        self.items = out
        kept := []
        for x in self.order:
            if x != k:
                append(kept, x)
        self.order = kept
        self._save()
        self._broadcast(k, old, null)

    func clear():
        if len(self.order) == 0:
            return
        self.items = {}
        self.order = []
        self._save()
        self._broadcast(null, null, null)

    func keys():
        return self.order

    func to_dict():
        out := {}
        for k in self.order:
            out[k] = self.items[k]
        return out

    # Diffusion : chaque écouteur reçoit (événement, fenêtre source) et ignore sa propre fenêtre.
    func _broadcast(k, old, new_value):
        for fn in self.listeners:
            fn(StorageEvent(k, old, new_value, "", self), self.source)

    func subscribe(fn):
        append(self.listeners, fn)

    # Vue liée à une fenêtre : les modifications faites par cette vue ne lui sont pas renvoyées.
    func view_for(window):
        return StorageView(self, window)

# Accès à un Storage partagé au nom d'une fenêtre (window.local_storage).
class StorageView:
    func init(storage, window):
        self.storage = storage
        self.window = window

    func _with_source(fn):
        self.storage.source = self.window
        try:
            fn()
        finally:
            self.storage.source = null

    func length():
        return self.storage.length()

    func __len__():
        return self.storage.length()

    func key(i):
        return self.storage.key(i)

    func get_item(name):
        return self.storage.get_item(name)

    func __getitem__(name):
        return self.storage.get_item(name)

    func __contains__(name):
        return name in self.storage

    func set_item(name, value):
        st := self.storage
        self._with_source(() => st.set_item(name, value))

    func remove_item(name):
        st := self.storage
        self._with_source(() => st.remove_item(name))

    func clear():
        st := self.storage
        self._with_source(() => st.clear())

    func keys():
        return self.storage.keys()

    func to_dict():
        return self.storage.to_dict()

# Registre des stockages par origine (un par navigateur) ; directory : persistance sur disque.
class StorageArea:
    func init(directory=null, quota=5242880):
        self.directory = directory
        self.quota = quota
        self.stores = {}

    func _file(origin):
        if self.directory == null:
            return null
        safe := []
        for c in origin:
            if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or (c >= '0' and c <= '9') or c == '.' or c == '-':
                append(safe, str(c))
            else:
                append(safe, "_")
        if not _os.exists(self.directory):
            _os.mkdir_all(self.directory)
        return _os.join(self.directory, _s.join("", safe) + ".json")

    func for_origin(origin):
        if not (origin in self.stores):
            self.stores[origin] = Storage(origin, self.quota, self._file(origin), "local")
        return self.stores[origin]

    func origins():
        return keys(self.stores)

    func clear_all():
        for k in keys(self.stores):
            self.stores[k].clear()
