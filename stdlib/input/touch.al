# ALEX STANDARD LIBRARY — input.touch
#
# Contact tactile simple (un doigt, un stylet, ou le pointeur d'une fenêtre traité comme un doigt) :
# TouchPoint (identifiant, position, pression, phase began / moved / stationary / ended / cancelled, origine,
# durée, déplacement) et TouchTracker qui le construit à partir d'événements evdev mono-contact (ABS_X / ABS_Y
# / ABS_PRESSURE / BTN_TOUCH) ou d'événements de fenêtre (pointer_down / move / up), avec détection du TAP.
#
#   use input.touch as touch
#   t := touch.TouchTracker()
#   for e in trame:                              # InputEvent d'un écran tactile (input.input_device)
#       t.feed(e)
#   p := t.commit()                              # TouchPoint à la fin de la trame (SYN_REPORT), ou null
#   if p != null and p.phase == "ended" and t.last_was_tap:
#       ouvrir(p.x, p.y)
#   t2 := touch.TouchTracker()
#   t2.feed_window({"type": "pointer_down", "x": 10, "y": 20})
#
# Erreurs : InputError (événement incohérent).

from core use len, type
from collections use append
use os as _os
use math as _math

const PHASES := ["began", "moved", "stationary", "ended", "cancelled"]

class TouchPoint:
    func init(id, x, y, pressure=null, time=null):
        self.id = id
        self.x = x
        self.y = y
        self.pressure = pressure
        self.phase = "began"
        t := time
        if t == null:
            t = _os.monotonic_time()
        self.start_time = t
        self.time = t
        self.start_x = x
        self.start_y = y
        self.prev_x = x
        self.prev_y = y

    func move_to(x, y, time=null, pressure=null):
        self.prev_x = self.x
        self.prev_y = self.y
        moved := x != self.x or y != self.y
        self.x = x
        self.y = y
        if pressure != null:
            self.pressure = pressure
        if time != null:
            self.time = time
        if moved:
            self.phase = "moved"
        else:
            self.phase = "stationary"
        return self

    func end(time=null, cancelled=false):
        if time != null:
            self.time = time
        if cancelled:
            self.phase = "cancelled"
        else:
            self.phase = "ended"
        return self

    func active():
        return self.phase != "ended" and self.phase != "cancelled"

    func duration():
        return self.time - self.start_time

    func travel():
        dx := self.x - self.start_x
        dy := self.y - self.start_y
        return _math.sqrt(dx * dx + dy * dy)

    func delta():
        return [self.x - self.prev_x, self.y - self.prev_y]

    func copy():
        p := TouchPoint(self.id, self.x, self.y, self.pressure, self.start_time)
        p.phase = self.phase
        p.time = self.time
        p.start_x = self.start_x
        p.start_y = self.start_y
        p.prev_x = self.prev_x
        p.prev_y = self.prev_y
        return p

    func to_dict():
        return {"id": self.id, "x": self.x, "y": self.y, "pressure": self.pressure, "phase": self.phase,
                "duration": self.duration(), "travel": self.travel()}

    func __str__():
        return "TouchPoint(" + str(self.id) + ", " + self.phase + ", " + str(self.x) + ", " + str(self.y) + ")"

class TouchTracker:
    func init(tap_time=0.3, tap_slop=10):
        self.point = null
        self.next_id = 1
        self.tap_time = tap_time
        self.tap_slop = tap_slop
        self.last_was_tap = false
        self._x = null
        self._y = null
        self._pressure = null
        self._down = null      # true / false / null (inchangé)
        self._time = null
        self.clock = null

    func _now():
        if self.clock != null:
            c := self.clock
            return c()
        return _os.monotonic_time()

    # InputEvent evdev (axis x / y / pressure, button touch, sync).
    func feed(e):
        if e.kind == "axis":
            if e.name == "x":
                self._x = e.value
            elif e.name == "y":
                self._y = e.value
            elif e.name == "pressure":
                self._pressure = e.value
        elif e.kind == "button" and (e.name == "touch" or e.name == "left"):
            self._down = e.value != 0
        elif e.kind == "motion":
            self._x = e.x
            self._y = e.y
        self._time = e.time
        if e.kind == "sync":
            return self.commit()
        return null

    func feed_window(ev):
        t := ev["type"]
        if "x" in ev:
            self._x = ev["x"]
            self._y = ev["y"]
        if t == "pointer_down":
            self._down = true
        elif t == "pointer_up":
            self._down = false
        elif t == "pointer_leave" and self.point != null and self.point.active():
            self._down = false
            self._time = self._now()
            p := self.commit()
            if p != null:
                p.phase = "cancelled"
                self.last_was_tap = false
            return p
        self._time = self._now()
        return self.commit()

    # Applique ce qui a été reçu depuis le dernier commit ; TouchPoint (copie) ou null.
    func commit():
        t := self._time
        if t == null:
            t = self._now()
        out := null
        if self._down == true and (self.point == null or not self.point.active()):
            x := self._x
            y := self._y
            if x == null:
                x = 0
                y = 0
            self.point = TouchPoint(self.next_id, x, y, self._pressure, t)
            self.next_id += 1
            self.last_was_tap = false
            out = self.point.copy()
        elif self._down == false and self.point != null and self.point.active():
            if self._x != null:
                self.point.move_to(self._x, self._y, t, self._pressure)
            self.point.end(t)
            self.last_was_tap = self.point.duration() <= self.tap_time and self.point.travel() <= self.tap_slop
            out = self.point.copy()
        elif self.point != null and self.point.active() and self._x != null and (self._x != self.point.x or self._y != self.point.y):
            self.point.move_to(self._x, self._y, t, self._pressure)
            out = self.point.copy()
        self._down = null
        self._time = null
        return out

    func active():
        return self.point != null and self.point.active()
