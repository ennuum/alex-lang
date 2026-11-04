# ALEX STANDARD LIBRARY — input.gesture
#
# Reconnaissance de gestes TACTILES à partir des trames de contacts (input.touch / input.multitouch) — ou du
# pointeur d'une fenêtre vu comme un doigt : tap, double tap, appui long, balayage (swipe : direction, vitesse),
# déplacement à un doigt (pan), pincement (pinch : facteur d'échelle), rotation à deux doigts, tap à deux doigts.
# L'horloge peut être fournie (tests déterministes). (Les gestes de SOURIS — clic, double clic, glisser — sont
# dans ui.gesture et mouse.pointer.)
#
#   use input.gesture as gs
#   g := gs.GestureRecognizer()
#   g.on("swipe", (e) => print("balayage", e["direction"], e["velocity"]))
#   g.on("pinch", (e) => zoomer(e["scale"]))
#   for trame in trames:                          # listes de TouchPoint (MultiTouchDecoder.feed)
#       for e in g.feed(trame):                   # gestes reconnus dans cette trame
#           print(e["type"])
#   g.tick()                                      # à appeler régulièrement : appui long sans mouvement
#
# Gestes (dict {"type", "x", "y", "fingers", "time"} + champs propres) : tap, double_tap, two_finger_tap,
# long_press, pan_start / pan / pan_end (dx, dy), swipe (direction, velocity, distance), pinch_start / pinch /
# pinch_end (scale), rotate (angle, degrés).
# Erreurs : TypeError (rappel non fonction).

from core use len, type
from collections use append
use os as _os
use math as _math

class GestureRecognizer:
    func init(tap_time=0.3, tap_slop=12.0, double_tap_time=0.35, long_press_time=0.6, swipe_min_distance=60.0, swipe_min_velocity=300.0, clock=null):
        self.tap_time = tap_time
        self.tap_slop = tap_slop
        self.double_tap_time = double_tap_time
        self.long_press_time = long_press_time
        self.swipe_min_distance = swipe_min_distance
        self.swipe_min_velocity = swipe_min_velocity
        self.clock = clock
        self.touches = {}          # id -> TouchPoint (dernier état)
        self.max_fingers = 0
        self.panning = false
        self.pinching = false
        self.long_fired = false
        self.last_tap = null       # [temps, x, y]
        self.start_pair = null
        self.handlers = {}
        self.gesture_start = null

    func _now():
        if self.clock != null:
            c := self.clock
            return c()
        return _os.monotonic_time()

    func on(gesture_type, fn):
        if type(fn) != "function":
            raise("TypeError", "GestureRecognizer.on : fonction attendue")
        if not (gesture_type in self.handlers):
            self.handlers[gesture_type] = []
        append(self.handlers[gesture_type], fn)
        return self

    func _emit(out, kind, x, y, extra=null):
        e := {"type": kind, "x": x, "y": y, "fingers": len(self.touches), "time": self._now()}
        if extra != null:
            for k in extra:
                e[k] = extra[k]
        append(out, e)
        if kind in self.handlers:
            for fn in self.handlers[kind]:
                fn(e)
        return e

    func _centroid():
        if len(self.touches) == 0:
            return [0.0, 0.0]
        sx := 0.0
        sy := 0.0
        for k in self.touches:
            sx += self.touches[k].x
            sy += self.touches[k].y
        return [sx / len(self.touches), sy / len(self.touches)]

    func _pair():
        ps := [self.touches[k] for k in self.touches]
        if len(ps) < 2:
            return null
        dx := ps[1].x - ps[0].x
        dy := ps[1].y - ps[0].y
        return [_math.sqrt(dx * dx + dy * dy), _math.atan2(dy, dx)]

    # Trame de TouchPoint (états du moment) ; liste des gestes reconnus.
    func feed(points):
        out := []
        ended := []
        for p in points:
            if p.phase == "began":
                if len(self.touches) == 0:
                    self.max_fingers = 0
                    self.long_fired = false
                    self.gesture_start = p.time
                self.touches[p.id] = p
            elif p.phase == "ended" or p.phase == "cancelled":
                append(ended, p)
                self.touches[p.id] = p
            else:
                self.touches[p.id] = p
        n := len([k for k in self.touches if self.touches[k].active()])
        if n > self.max_fingers:
            self.max_fingers = n
        # deux doigts : pincement / rotation
        if n == 2:
            pr := self._pair()
            if self.start_pair == null:
                self.start_pair = pr
            elif pr != null and self.start_pair[0] > 0:
                scale := pr[0] / self.start_pair[0]
                c := self._centroid()
                if not self.pinching and (scale > 1.05 or scale < 0.95):
                    self.pinching = true
                    self._emit(out, "pinch_start", c[0], c[1], {"scale": scale})
                if self.pinching:
                    self._emit(out, "pinch", c[0], c[1], {"scale": scale})
                    ang := (pr[1] - self.start_pair[1]) * 180.0 / _math.PI
                    if ang > 180:
                        ang -= 360
                    if ang < -180:
                        ang += 360
                    if ang > 3 or ang < -3:
                        self._emit(out, "rotate", c[0], c[1], {"angle": ang})
        elif self.pinching and n < 2:
            c := self._centroid()
            self.pinching = false
            self._emit(out, "pinch_end", c[0], c[1])
        # un doigt : déplacement
        if n == 1 and self.max_fingers == 1:
            p := [self.touches[k] for k in self.touches if self.touches[k].active()][0]
            if not self.panning and p.travel() > self.tap_slop:
                self.panning = true
                self._emit(out, "pan_start", p.start_x, p.start_y)
            if self.panning and p.phase == "moved":
                d := p.delta()
                self._emit(out, "pan", p.x, p.y, {"dx": d[0], "dy": d[1], "total_dx": p.x - p.start_x, "total_dy": p.y - p.start_y})
        # fins de contact
        for p in ended:
            del self.touches[p.id]
            if len(self.touches) == 0:
                self._finish(out, p)
        if len(self.touches) < 2:
            self.start_pair = null
        return out

    func _finish(out, p):
        dur := p.time - self.gesture_start
        if self.max_fingers >= 2:
            if not self.pinching and dur <= self.tap_time and p.travel() <= self.tap_slop:
                self._emit(out, "two_finger_tap", p.x, p.y)
        else:
            dist := p.travel()
            vel := 0.0
            if p.duration() > 0:
                vel = dist / p.duration()
            if self.panning:
                self._emit(out, "pan_end", p.x, p.y, {"total_dx": p.x - p.start_x, "total_dy": p.y - p.start_y})
            if dist >= self.swipe_min_distance and vel >= self.swipe_min_velocity:
                dx := p.x - p.start_x
                dy := p.y - p.start_y
                direction := "right"
                if _abs(dx) >= _abs(dy):
                    if dx < 0:
                        direction = "left"
                elif dy < 0:
                    direction = "up"
                else:
                    direction = "down"
                self._emit(out, "swipe", p.x, p.y, {"direction": direction, "velocity": vel, "distance": dist})
            elif not self.long_fired and dur <= self.tap_time and dist <= self.tap_slop:
                self._emit(out, "tap", p.x, p.y)
                if self.last_tap != null and p.time - self.last_tap[0] <= self.double_tap_time and _dist(p.x, p.y, self.last_tap[1], self.last_tap[2]) <= self.tap_slop * 2:
                    self._emit(out, "double_tap", p.x, p.y)
                    self.last_tap = null
                else:
                    self.last_tap = [p.time, p.x, p.y]
        self.panning = false
        self.pinching = false
        self.max_fingers = 0

    # Appui long : à appeler régulièrement (ou après chaque trame) ; gestes émis.
    func tick():
        out := []
        if self.long_fired or len(self.touches) != 1 or self.gesture_start == null:
            return out
        p := [self.touches[k] for k in self.touches][0]
        if self._now() - self.gesture_start >= self.long_press_time and p.travel() <= self.tap_slop and p.active():
            self.long_fired = true
            self._emit(out, "long_press", p.x, p.y)
        return out

func _abs(v):
    if v < 0:
        return -v
    return v

func _dist(x1, y1, x2, y2):
    return _math.sqrt((x1 - x2) * (x1 - x2) + (y1 - y2) * (y1 - y2))
