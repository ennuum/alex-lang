# ALEX STANDARD LIBRARY — event.watcher
#
# Surveiller des fichiers et des dossiers : création, modification, suppression, renommage. Sous Linux, le noyau
# prévient (inotify : immédiat, sans coût) ; ailleurs, ou sur demande, l'arborescence est comparée régulièrement
# (scrutation : dates de modification et tailles).
#
#   use event.watcher as watcher
#   w := watcher.FileWatcher(["config", "data/entrees"], true)       # récursif
#   for e in w.poll(1.0):                                             # attend au plus 1 s
#       print(e["kind"], e["path"])        # created | modified | deleted | moved_from | moved_to
#   w.on((e) => recharger(e["path"]))
#   await w.run(60)                                                   # 60 s de surveillance avec rappels
#   w.close()
#
#   v := watcher.ValueWatcher(() => lire_temperature(), 1.0, (ancienne, nouvelle) => alerte(nouvelle))
#   v.start()
#
# Les événements d'une même seconde peuvent être regroupés ou dédoublonnés selon le système ; un éditeur qui
# enregistre « en remplaçant » produit souvent deleted + created (ou moved_to). backend : "inotify" ou "poll".
#
# Erreurs : IoError (chemin absent, limite d'inotify), ArgumentError.

from core use len, type
from collections use append, contains_key, keys
use os as _os
use asyncio
use _native_fd as _f

func _join(a, b):
    if a == "" or a == ".":
        return b
    return _os.join(a, b)

# Instantané {chemin: [est_dossier, mtime, taille]} d'une arborescence.
func _snapshot(root, recursive, out):
    kind := _f.file_kind(root, true)
    if kind == null:
        return out
    if kind == "dir":
        out[root] = [true, _os.mtime(root), 0]
        for n in _os.list_dir(root):
            p := _join(root, n)
            k := _f.file_kind(p, true)
            if k == "dir":
                if recursive:
                    _snapshot(p, true, out)
                else:
                    out[p] = [true, _os.mtime(p), 0]
            elif k != null:
                try:
                    out[p] = [false, _os.mtime(p), _os.size(p)]
                catch e:
                    out[p] = [false, 0, 0]
    else:
        try:
            out[root] = [false, _os.mtime(root), _os.size(root)]
        catch e:
            out[root] = [false, 0, 0]
    return out

class FileWatcher:
    # paths : chemin ou liste de chemins (fichiers ou dossiers) ; recursive : sous-dossiers ; backend : null
    # (inotify si possible), "inotify" ou "poll" ; interval : période de scrutation (secondes).
    func init(paths, recursive=false, backend=null, interval=0.5):
        if type(paths) == "str":
            paths = [paths]
        for p in paths:
            if not _os.exists(p):
                raise("IoError", "FileWatcher : chemin absent '" + p + "'")
        self.paths = paths
        self.recursive = recursive
        self.interval = interval
        self._handlers = []
        self._closed = false
        if backend == null:
            if _f.inotify_supported():
                backend = "inotify"
            else:
                backend = "poll"
        if backend != "inotify" and backend != "poll":
            raise("ArgumentError", "FileWatcher : backend \"inotify\" ou \"poll\" attendu")
        self.backend = backend
        self._wd = {}       # surveillance -> dossier
        self._fd = -1
        self._snap = {}
        self._last_scan = 0.0
        if backend == "inotify":
            self._fd = _f.inotify_init()
            if self._fd < 0:
                raise("IoError", "FileWatcher : inotify indisponible (" + _f.strerror(self._fd) + ")")
            for p in paths:
                self._add_tree(p)
        else:
            self._rescan()

    func _add_watch(path):
        wd := _f.inotify_add(self._fd, path, ["create", "modify", "close_write", "delete", "delete_self", "moved_from", "moved_to", "attrib"])
        if wd < 0:
            raise("IoError", "FileWatcher : surveillance de '" + path + "' impossible : " + _f.strerror(wd))
        self._wd[wd] = path

    func _add_tree(path):
        self._add_watch(path)
        if self.recursive and _f.file_kind(path, true) == "dir":
            for n in _os.list_dir(path):
                p := _join(path, n)
                if _f.file_kind(p, false) == "dir":
                    self._add_tree(p)

    func _rescan():
        snap := {}
        for p in self.paths:
            _snapshot(p, self.recursive, snap)
        old := self._snap
        self._snap = snap
        self._last_scan = _os.monotonic_time()
        events := []
        for p in keys(snap):
            if not contains_key(old, p):
                append(events, {"kind": "created", "path": p, "is_dir": snap[p][0]})
            elif not snap[p][0] and (snap[p][1] != old[p][1] or snap[p][2] != old[p][2]):
                append(events, {"kind": "modified", "path": p, "is_dir": false})
        for p in keys(old):
            if not contains_key(snap, p):
                append(events, {"kind": "deleted", "path": p, "is_dir": old[p][0]})
        return events

    func _translate(raw):
        events := []
        for r in raw:
            base := ""
            if contains_key(self._wd, r[0]):
                base = self._wd[r[0]]
            path := base
            if r[3] != "":
                path = _join(base, r[3])
            names := r[1]
            is_dir := _has(names, "isdir")
            kind := null
            if _has(names, "create"):
                kind = "created"
                if is_dir and self.recursive:
                    self._add_tree(path)
            elif _has(names, "delete") or _has(names, "delete_self"):
                kind = "deleted"
            elif _has(names, "moved_from"):
                kind = "moved_from"
            elif _has(names, "moved_to"):
                kind = "moved_to"
                if is_dir and self.recursive:
                    self._add_tree(path)
            elif _has(names, "modify") or _has(names, "close_write") or _has(names, "attrib"):
                kind = "modified"
            elif _has(names, "overflow"):
                kind = "overflow"
            if kind == null:
                continue
            ev := {"kind": kind, "path": path, "is_dir": is_dir, "cookie": r[2]}
            # « modify » puis « close_write » d'une même écriture : un seul événement.
            if kind == "modified" and len(events) > 0 and events[len(events) - 1]["kind"] == "modified" and events[len(events) - 1]["path"] == path:
                continue
            append(events, ev)
        return events

    # Événements survenus (attend au plus timeout secondes le premier ; 0 : sans attendre).
    func poll(timeout=0):
        if self._closed:
            raise("IoError", "FileWatcher : fermé")
        if self.backend == "inotify":
            raw := _f.inotify_read(self._fd, timeout)
            if type(raw) == "int":
                raise("IoError", "FileWatcher : lecture inotify : " + _f.strerror(raw))
            events := self._translate(raw)
            # regrouper ce qui arrive juste après
            more := _f.inotify_read(self._fd, 0.01)
            while type(more) == "list" and len(more) > 0:
                for e in self._translate(more):
                    append(events, e)
                more = _f.inotify_read(self._fd, 0.01)
            return events
        start := _os.monotonic_time()
        while true:
            events := self._rescan()
            if len(events) > 0:
                return events
            wait := self.interval
            if timeout != null:
                left := timeout - (_os.monotonic_time() - start)
                if left <= 0:
                    return events
                if left < wait:
                    wait = left
            _os.sleep(wait)

    # handler(événement) appelé par dispatch / run.
    func on(handler):
        append(self._handlers, handler)
        return self

    # Récupère les événements (sans attendre) et appelle les gestionnaires ; renvoie leur nombre.
    func dispatch():
        events := self.poll(0)
        for e in events:
            for h in self._handlers:
                h(e)
        return len(events)

    # Futur : surveille pendant duration secondes (null : jusqu'à close), en appelant les gestionnaires, sans
    # bloquer les autres tâches.
    func run(duration=null):
        return _run_watcher(self, duration)

    func close():
        if not self._closed:
            if self._fd >= 0:
                _f.close(self._fd)
            self._closed = true

func _has(lst, x):
    for v in lst:
        if v == x:
            return true
    return false

async func _run_watcher(w, duration):
    start := asyncio.now()
    while not w._closed:
        w.dispatch()
        if duration != null and asyncio.now() - start >= duration:
            return null
        await asyncio.sleep(_min(w.interval, 0.05))

func _min(a, b):
    if a < b:
        return a
    return b

func watch(paths, recursive=false):
    return FileWatcher(paths, recursive)

# Surveille une valeur calculée : fn() toutes les interval secondes ; on_change(ancienne, nouvelle) quand elle
# change (comparaison ==). Tâche async (start / stop).
class ValueWatcher:
    func init(fn, interval, on_change):
        self.fn = fn
        self.interval = interval
        self.on_change = on_change
        self.value = null
        self.changes = 0
        self._task = null
        self._stop = false

    func check():
        f := self.fn
        v := f()
        if v != self.value:
            old := self.value
            self.value = v
            self.changes += 1
            h := self.on_change
            h(old, v)
            return true
        return false

    func start():
        f := self.fn
        self.value = f()
        self._stop = false
        self._task = _run_value(self)
        return self

    func stop():
        self._stop = true
        if self._task != null:
            asyncio.cancel(self._task)

async func _run_value(v):
    while not v._stop:
        await asyncio.sleep(v.interval)
        v.check()
