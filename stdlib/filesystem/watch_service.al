# ALEX STANDARD LIBRARY — filesystem.watch_service
#
# WatchService : surveillance de dossiers à la manière de java.nio WatchService — on ENREGISTRE des dossiers
# (avec les genres d'événements voulus et des filtres de noms), puis on récupère des CLÉS portant les
# événements de chaque dossier. Ajoute au FileWatcher d'event.watcher (inotify ou scrutation) : filtres
# glob, regroupement (anti-rebond) des rafales d'événements sur un même fichier, et suivi par enregistrement.
#
#   use filesystem.watch_service as ws
#   s := ws.WatchService()
#   k := s.register("config", ["modified", "created"], ["*.toml"])
#   s.register("data", null, null, true)                  # tous les événements, récursif
#   for key in s.poll(1.0):                                # clés ayant des événements (attente <= 1 s)
#       for e in key.events():
#           print(key.path, e.kind, e.path)                # config modified config/app.toml
#   s.on((e) => recharger(e.path))                         # ou rappels...
#   s.dispatch()                                           # ... appelés pour les événements en attente
#   s.close()
#
# Genres : created, modified, deleted, moved_from, moved_to (null : tous). Un éditeur qui enregistre « en
# remplaçant » peut produire deleted + created : debounce (secondes) les fusionne en un seul « modified ».
# Erreurs : FileNotFoundError (dossier absent), IoError (inotify), ArgumentError (genre inconnu).

from core use len, type
from collections use append
use os as _os
use path as _p
use event.watcher as _w
use filesystem.filesystem_errors as _e

const KINDS := ["created", "modified", "deleted", "moved_from", "moved_to"]

class WatchEvent:
    func init(kind, path, time):
        self.kind = kind
        self.path = path
        self.name = _p.basename(path)
        self.time = time

    func __str__():
        return self.kind + " " + self.path

class WatchKey:
    func init(service, path, kinds, patterns, recursive):
        self.service = service
        self.path = path
        self.kinds = kinds
        self.patterns = patterns
        self.recursive = recursive
        self.valid = true
        self._pending = []

    func _accepts(kind, path):
        if self.kinds != null:
            ok := false
            for k in self.kinds:
                if k == kind:
                    ok = true
            if not ok:
                return false
        if self.patterns != null:
            name := _p.basename(path)
            for pat in self.patterns:
                if _p.glob_match(pat, name):
                    return true
            return false
        return true

    func _owns(path):
        if path == self.path:
            return true
        if not _p.is_subpath(path, self.path):
            return false
        if self.recursive:
            return true
        return _p.dirname(path) == self.path

    # Événements accumulés depuis le dernier appel (puis vidés).
    func events():
        out := self._pending
        self._pending = []
        return out

    func has_events():
        return len(self._pending) > 0

    func cancel():
        self.valid = false
        self.service._remove(self)

class WatchService:
    func init(backend=null, debounce=0.0, interval=0.25):
        self.backend = backend
        self.debounce = debounce
        self.interval = interval
        self._keys = []
        self._watcher = null
        self._handlers = []
        self._closed = false

    func _rebuild():
        if self._watcher != null:
            self._watcher.close()
            self._watcher = null
        if len(self._keys) == 0:
            return
        paths := [k.path for k in self._keys]
        rec := false
        for k in self._keys:
            if k.recursive:
                rec = true
        self._watcher = _w.FileWatcher(paths, rec, self.backend, self.interval)

    # Surveille le dossier path ; renvoie sa WatchKey.
    func register(path, kinds=null, patterns=null, recursive=false):
        if self._closed:
            raise("IoError", "WatchService : service fermé")
        _e.need_dir("WatchService.register", path)
        if kinds != null:
            for k in kinds:
                ok := false
                for x in KINDS:
                    if x == k:
                        ok = true
                if not ok:
                    raise("ArgumentError", "WatchService.register : genre inconnu '" + str(k) + "'")
        key := WatchKey(self, _p.normalize(path), kinds, patterns, recursive)
        append(self._keys, key)
        self._rebuild()
        return key

    func _remove(key):
        self._keys = [k for k in self._keys if not (k.path == key.path and k.kinds == key.kinds)]
        self._rebuild()

    func keys():
        return self._keys[:]

    func _merge(events):
        if self.debounce <= 0 or len(events) < 2:
            return events
        last := {}
        order := []
        for e in events:
            if e.path in last:
                prev := last[e.path]
                if e.time - prev.time <= self.debounce:
                    # Rafale sur le même fichier : un seul événement (création/modification -> modified).
                    k := "modified"
                    if e.kind == "deleted" and prev.kind != "created":
                        k = "deleted"
                    if prev.kind == "created" and e.kind != "deleted":
                        k = "created"
                    last[e.path] = WatchEvent(k, e.path, e.time)
                    continue
            if not (e.path in last):
                append(order, e.path)
            last[e.path] = e
        return [last[p] for p in order]

    # Attend au plus timeout secondes ; renvoie les WatchKey qui ont reçu des événements.
    func poll(timeout=0):
        if self._watcher == null:
            if timeout != null and timeout > 0:
                _os.sleep(timeout)
            return []
        raw := self._watcher.poll(timeout)
        now := _os.monotonic_time()
        evs := self._merge([WatchEvent(r["kind"], _p.normalize(r["path"]), now) for r in raw])
        touched := []
        for e in evs:
            for k in self._keys:
                if k.valid and k._owns(e.path) and k._accepts(e.kind, e.path):
                    append(k._pending, e)
                    found := false
                    for t in touched:
                        if t.path == k.path:
                            found = true
                    if not found:
                        append(touched, k)
        return touched

    # Comme poll, mais attend jusqu'à ce qu'au moins une clé ait des événements (ou timeout).
    func take(timeout=null):
        t0 := _os.monotonic_time()
        while true:
            left := 0.5
            if timeout != null:
                left = timeout - (_os.monotonic_time() - t0)
                if left <= 0:
                    return []
            ks := self.poll(left)
            if len(ks) > 0:
                return ks

    func on(handler):
        append(self._handlers, handler)
        return self

    # Récupère les événements en attente et appelle les gestionnaires ; renvoie leur nombre.
    func dispatch(timeout=0):
        n := 0
        for k in self.poll(timeout):
            for e in k.events():
                for h in self._handlers:
                    h(e)
                n += 1
        return n

    func close():
        self._closed = true
        if self._watcher != null:
            self._watcher.close()
            self._watcher = null

func watch(path, kinds=null, patterns=null, recursive=false):
    s := WatchService()
    s.register(path, kinds, patterns, recursive)
    return s
