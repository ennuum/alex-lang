# ALEX STANDARD LIBRARY — hardware.device_manager
#
# Inventaire des périphériques et suivi des branchements : liste par sous-système ou catégorie, recherche,
# regroupement par pilote, et détection des ajouts / retraits (comparaison d'instantanés, en tâche async).
#
#   use hardware.device_manager as dm
#   m := dm.DeviceManager()
#   for d in m.list("input"):
#       print(d.describe())
#   print(m.by_driver())                     # {"virtio_net": [...], ...}
#   m.on("added", (d) => print("branché :", d.describe()))
#   m.on("removed", (d) => print("retiré :", d.describe()))
#   await m.watch(60, 1.0)                    # 60 s, un instantané par seconde
#
# Sous-systèmes suivis par défaut : usb, input, block, net, sound, video4linux, drm, hidraw, tty.

from core use len, type
from collections use append, contains_key, keys
use asyncio
use hardware.device as _dev
use hardware.device_info as _di
use event.event_emitter as _ee

const DEFAULT_SUBSYSTEMS := ["usb", "input", "block", "net", "sound", "video4linux", "drm", "hidraw", "tty"]

class DeviceManager:
    func init(subsystems=null):
        if subsystems == null:
            subsystems = DEFAULT_SUBSYSTEMS
        self.subsystems = subsystems
        self.events = _ee.EventEmitter()
        self._known = {}

    func on(event_type, fn):
        return self.events.on(event_type, fn)

    func list(subsystem):
        return _dev.by_subsystem(subsystem)

    # Tous les périphériques des sous-systèmes suivis.
    func all():
        out := []
        for s in self.subsystems:
            for d in _dev.by_subsystem(s):
                append(out, d)
        return out

    # Périphériques dont la catégorie (hardware.device_info) vaut category.
    func by_category(category):
        return [d for d in self.all() if _di.describe(d).category == category]

    func find(predicate):
        return [d for d in self.all() if predicate(d)]

    func find_by_name(name):
        for d in self.all():
            if d.name == name:
                return d
        return null

    # {pilote: [périphériques]} (pilote « (aucun) » pour ceux sans pilote).
    func by_driver():
        out := {}
        for d in self.all():
            k := d.driver
            if k == null:
                k = "(aucun)"
            if not contains_key(out, k):
                out[k] = []
            append(out[k], d)
        return out

    func _snapshot():
        snap := {}
        for d in self.all():
            snap[d.syspath] = d
        return snap

    # Compare avec l'instantané précédent ; émet "added" / "removed" et renvoie [ajoutés, retirés].
    func refresh():
        snap := self._snapshot()
        added := []
        removed := []
        if len(keys(self._known)) > 0 or self._primed:
            for k in keys(snap):
                if not contains_key(self._known, k):
                    append(added, snap[k])
            for k in keys(self._known):
                if not contains_key(snap, k):
                    append(removed, self._known[k])
        self._known = snap
        self._primed = true
        for d in added:
            self.events.emit("added", d)
        for d in removed:
            self.events.emit("removed", d)
        return [added, removed]

    # Futur : instantanés toutes les interval secondes pendant duration secondes (null : sans fin).
    func watch(duration=null, interval=1.0):
        return _watch(self, duration, interval)

    _primed := false

async func _watch(m, duration, interval):
    m.refresh()
    start := asyncio.now()
    while duration == null or asyncio.now() - start < duration:
        await asyncio.sleep(interval)
        m.refresh()
    return null

func manager(subsystems=null):
    return DeviceManager(subsystems)
