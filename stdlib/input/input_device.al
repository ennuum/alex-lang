# ALEX STANDARD LIBRARY — input.input_device
#
# Périphériques d'entrée du système (Linux : /proc/bus/input/devices et /dev/input/eventN) : inventaire avec
# leur GENRE déduit des capacités annoncées par le noyau (keyboard, mouse, touchpad, touchscreen, gamepad,
# tablet, other), et lecture de leurs événements en InputEvent unifiés.
#
#   use input.input_device as idev
#   for d in idev.devices():
#       print(d.name, d.kind, d.path, d.vendor_id, d.product_id)
#   m := idev.first("gamepad")                  # DeviceNotFound s'il n'y en a pas
#   r := m.open()                               # DeviceReader (droits sur /dev/input requis)
#   e := r.read(1.0)                            # InputEvent, ou null après 1 s
#   lot := r.read_frame(1.0)                    # événements jusqu'au prochain SYN_REPORT
#   r.close()
#
# Erreurs : DeviceNotFound, HardwareError (ouverture refusée), InputError.

from core use len, type
from collections use append
use string as _s
use hardware._sys as _sys
use hardware._input as _in
use input.input_event as _ev

const KINDS := ["keyboard", "mouse", "touchpad", "touchscreen", "gamepad", "tablet", "other"]

func _bit(words, n):
    return _sys.mask_bit(words, n)

func classify(info):
    ev := info["ev"]
    has_key := (ev >> 1) & 1 == 1
    has_rel := (ev >> 2) & 1 == 1
    has_abs := (ev >> 3) & 1 == 1
    keys := info["key"]
    absb := info["abs"]
    if has_abs and (_bit(keys, 320) or _bit(keys, 321) or _bit(keys, 331)):
        return "tablet"
    if has_key and (_bit(keys, 304) or _bit(keys, 305) or _bit(keys, 315)):
        return "gamepad"
    if has_abs and _bit(keys, 330):
        if _bit(keys, 325) or _bit(keys, 333):
            return "touchpad"
        return "touchscreen"
    if has_abs and (_bit(absb, 53) or _bit(absb, 0)) and not has_key:
        return "touchscreen"
    if has_rel and (info["rel"] & 3) == 3:
        return "mouse"
    if has_key and _bit(keys, 30) and _bit(keys, 28):
        return "keyboard"
    for h in info["handlers"]:
        if _s.starts_with(h, "mouse"):
            return "mouse"
        if h == "kbd" and has_key and _bit(keys, 30):
            return "keyboard"
    return "other"

class InputDevice:
    func init(info):
        self.info = info
        self.name = info["name"]
        self.phys = info["phys"]
        self.path = null
        if len(info["events"]) > 0:
            self.path = info["events"][0]
        self.vendor_id = info["vendor"]
        self.product_id = info["product"]
        self.bus = info["bus"]
        self.kind = classify(info)

    func has_key(code):
        return _bit(self.info["key"], code)

    func has_abs(code):
        return _bit(self.info["abs"], code)

    func is_multitouch():
        return self.has_abs(47) or self.has_abs(53)

    func open():
        if self.path == null:
            raise("InputError", "périphérique « " + self.name + " » sans nœud /dev/input/event")
        return DeviceReader(self.path, self.kind, self.name)

    func to_dict():
        return {"name": self.name, "kind": self.kind, "path": self.path, "vendor": self.vendor_id, "product": self.product_id, "phys": self.phys}

    func __str__():
        return "InputDevice(" + self.name + ", " + self.kind + ", " + str(self.path) + ")"

class DeviceReader:
    func init(path, kind="unknown", name=""):
        self.path = path
        self.kind = kind
        self.name = name
        self.reader = _in.Reader(path, "input_device.open")

    func read_raw(timeout=null):
        return self.reader.read_event(timeout)

    # Prochain InputEvent (les événements ignorés sont sautés), null après timeout.
    func read(timeout=null):
        while true:
            raw := self.reader.read_event(timeout)
            if raw == null:
                return null
            e := _ev.from_evdev(raw, self.kind)
            if e != null:
                return e

    # Événements d'une trame (jusqu'au SYN_REPORT, exclu) ; [] après timeout.
    func read_frame(timeout=null):
        out := []
        while true:
            e := self.read(timeout)
            if e == null:
                return out
            if e.kind == "sync":
                return out
            append(out, e)

    func close():
        self.reader.close()

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.close()

func devices():
    return [InputDevice(d) for d in _sys.input_devices()]

func of_kind(kind):
    return [d for d in devices() if d.kind == kind]

func first(kind):
    ds := of_kind(kind)
    if len(ds) == 0:
        raise("DeviceNotFound", "aucun périphérique d'entrée de genre « " + kind + " »")
    return ds[0]

func find(name_fragment):
    for d in devices():
        if _s.contains(_s.lower(d.name), _s.lower(name_fragment)):
            return d
    return null

func summary():
    counts := {}
    for d in devices():
        if d.kind in counts:
            counts[d.kind] += 1
        else:
            counts[d.kind] = 1
    return counts

func open(path, kind="unknown"):
    return DeviceReader(path, kind)
