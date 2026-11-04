# ALEX STANDARD LIBRARY — input.multitouch
#
# Multi-contact (écrans et pavés tactiles) : décodeur du protocole B du noyau Linux — emplacements (ABS_MT_SLOT),
# identifiants de suivi (ABS_MT_TRACKING_ID, -1 = doigt levé), positions et pression par emplacement, trames
# terminées par SYN_REPORT — qui produit pour chaque trame la liste des TouchPoint (phases began / moved /
# stationary / ended). Mesures de groupe : nombre de doigts, barycentre, écartement (pincement : facteur
# d'échelle) et rotation entre deux doigts depuis le début du geste.
#
#   use input.multitouch as mt
#   dec := mt.MultiTouchDecoder()
#   for e in evenements:                    # InputEvent evdev d'un écran tactile
#       trame := dec.feed(e)                # liste de TouchPoint à chaque SYN_REPORT, sinon null
#       if trame != null:
#           print(dec.count(), dec.centroid(), dec.scale(), dec.rotation())
#
# Erreurs : InputError (emplacement hors limites).

from core use len, type
from collections use append
use os as _os
use math as _math
use input.touch as _t

class MultiTouchDecoder:
    func init(max_slots=10):
        self.max_slots = max_slots
        self.slot = 0
        self.slots = {}           # emplacement -> {"id", "x", "y", "pressure"} en cours de construction
        self.points = {}          # identifiant -> TouchPoint actif
        self.ended = []
        self.start_pair = null    # [distance, angle] au début d'un geste à deux doigts
        self.frames = 0

    func _cur():
        if not (self.slot in self.slots):
            self.slots[self.slot] = {"id": null, "x": null, "y": null, "pressure": null, "changed": false}
        return self.slots[self.slot]

    func feed(e):
        if e.kind == "axis":
            n := e.name
            if n == "mt_slot":
                if e.value < 0 or e.value >= self.max_slots:
                    raise("InputError", "multitouch : emplacement " + str(e.value) + " hors limites")
                self.slot = e.value
            elif n == "mt_tracking_id":
                c := self._cur()
                c["id"] = e.value
                c["changed"] = true
            elif n == "mt_position_x":
                c := self._cur()
                c["x"] = e.value
                c["changed"] = true
            elif n == "mt_position_y":
                c := self._cur()
                c["y"] = e.value
                c["changed"] = true
            elif n == "mt_pressure" or n == "mt_touch_major":
                c := self._cur()
                c["pressure"] = e.value
            return null
        if e.kind == "sync":
            return self.commit(e.time)
        return null

    func commit(time=null):
        t := time
        if t == null:
            t = _os.monotonic_time()
        out := []
        for s in self.slots:
            c := self.slots[s]
            key := "s" + str(s)
            if c["id"] != null and c["id"] < 0:
                if key in self.points:
                    p := self.points[key]
                    p.end(t)
                    append(out, p.copy())
                    del self.points[key]
                c["id"] = null
                c["x"] = null
                c["y"] = null
            elif c["id"] != null:
                if not (key in self.points):
                    x := c["x"]
                    y := c["y"]
                    if x == null:
                        x = 0
                    if y == null:
                        y = 0
                    self.points[key] = _t.TouchPoint(c["id"], x, y, c["pressure"], t)
                    append(out, self.points[key].copy())
                else:
                    p := self.points[key]
                    nx := p.x
                    ny := p.y
                    if c["x"] != null:
                        nx = c["x"]
                    if c["y"] != null:
                        ny = c["y"]
                    p.move_to(nx, ny, t, c["pressure"])
                    append(out, p.copy())
            c["changed"] = false
        self.frames += 1
        if self.count() == 2:
            if self.start_pair == null:
                self.start_pair = self._pair()
        else:
            self.start_pair = null
        return out

    func active():
        return [self.points[k] for k in self.points]

    func count():
        return len(self.points)

    func centroid():
        ps := self.active()
        if len(ps) == 0:
            return null
        sx := 0.0
        sy := 0.0
        for p in ps:
            sx += p.x
            sy += p.y
        return [sx / len(ps), sy / len(ps)]

    func _pair():
        ps := self.active()
        if len(ps) < 2:
            return null
        a := ps[0]
        b := ps[1]
        dx := b.x - a.x
        dy := b.y - a.y
        return [_math.sqrt(dx * dx + dy * dy), _math.atan2(dy, dx)]

    # Facteur d'échelle du pincement à deux doigts depuis le début (1.0 sinon).
    func scale():
        if self.start_pair == null or self.start_pair[0] == 0:
            return 1.0
        cur := self._pair()
        if cur == null:
            return 1.0
        return cur[0] / self.start_pair[0]

    # Rotation (degrés) à deux doigts depuis le début.
    func rotation():
        if self.start_pair == null:
            return 0.0
        cur := self._pair()
        if cur == null:
            return 0.0
        d := (cur[1] - self.start_pair[1]) * 180.0 / _math.PI
        while d > 180:
            d -= 360
        while d < -180:
            d += 360
        return d

    func reset():
        self.slot = 0
        self.slots = {}
        self.points = {}
        self.start_pair = null
