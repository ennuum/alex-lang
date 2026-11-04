# alex: native
# ALEX STANDARD LIBRARY — driver.driver_lifecycle
#
# Cycle de vie des périphériques liés à un pilote, au-dessus de driver.driver_manager :
#
#   détecté --start--> en marche --suspend--> suspendu --resume--> en marche
#      |                  |   \--stop--> arrêté --start--> en marche
#      |                  \--(erreur)--> en échec --restart--> en marche (au plus max_restarts fois)
#      \--remove (de tout état)--> retiré
#
#   - transitions vérifiées (DriverStateError pour une transition interdite) ;
#   - mise en veille : crochets PowerHooks (suspend / resume) fournis par le pilote, facultatifs ;
#   - redémarrage après échec borné, compteur par périphérique ;
#   - historique horodaté par un compteur d'événements (pas d'horloge : utilisable dans le noyau).
#
#   use driver.driver_lifecycle as dl
#   lc := dl.Lifecycle(gestionnaire)
#   lc.start(dev)                    # probe + attach du meilleur pilote
#   lc.suspend(dev) ; lc.resume(dev)
#   lc.fail(dev, "file bloquée")     # signalé par le pilote
#   lc.restart(dev)                  # détache puis relie
#   print(lc.state_name(dev), lc.history_text())
#
# Erreurs : DriverStateError (transition interdite, trop de redémarrages, périphérique inconnu).
# Compilable en natif (# alex: native).

from core use len
from collections use append
use driver.driver_info as di
from driver.driver_info use HwDevice
use driver.driver_manager as dmg
from driver.driver_manager use DriverManager
use driver.device_binding as dbind
from driver.device_binding use Binding

const DETECTED := 0
const RUNNING := 1
const SUSPENDED := 2
const STOPPED := 3
const FAILED := 4
const REMOVED := 5

func name_of(s: int) -> str:
    if s == DETECTED:
        return "détecté"
    if s == RUNNING:
        return "en marche"
    if s == SUSPENDED:
        return "suspendu"
    if s == STOPPED:
        return "arrêté"
    if s == FAILED:
        return "en échec"
    if s == REMOVED:
        return "retiré"
    return "inconnu"

# Transition permise de a vers b ?
func allowed(a: int, b: int) -> bool:
    if b == REMOVED:
        return a != REMOVED
    if a == DETECTED or a == STOPPED:
        return b == RUNNING or b == FAILED
    if a == RUNNING:
        return b == SUSPENDED or b == STOPPED or b == FAILED
    if a == SUSPENDED:
        return b == RUNNING or b == STOPPED or b == FAILED
    if a == FAILED:
        return b == RUNNING or b == STOPPED or b == FAILED
    return false

interface PowerHooks:
    func suspend(dev: HwDevice)
    func resume(dev: HwDevice)

class _Hooks:
    driver: str := ""
    hooks: PowerHooks

    func init(driver: str, hooks: PowerHooks):
        self.driver = driver
        self.hooks = hooks

class DeviceLife:
    device: HwDevice
    state: int := 0
    restarts: int := 0
    last_error: str := ""

    func init(device: HwDevice):
        self.device = device
        self.state = DETECTED
        self.restarts = 0
        self.last_error = ""

class Lifecycle:
    manager: DriverManager
    lives: list[DeviceLife] := []
    hooks: list[_Hooks] := []
    history: list[str] := []
    events: int := 0
    max_restarts: int := 3

    func init(manager: DriverManager):
        self.manager = manager
        self.lives = []
        self.hooks = []
        self.history = []
        self.events = 0
        self.max_restarts = 3

    func set_power_hooks(driver: str, h: PowerHooks):
        append(self.hooks, _Hooks(driver, h))

    func _life(dev: HwDevice) -> DeviceLife:
        for l in self.lives:
            if l.device.location == dev.location and l.device.bus == dev.bus:
                return l
        l := DeviceLife(dev)
        append(self.lives, l)
        return l

    func state(dev: HwDevice) -> int:
        return self._life(dev).state

    func state_name(dev: HwDevice) -> str:
        return name_of(self.state(dev))

    func _move(l: DeviceLife, to: int, why: str):
        if not allowed(l.state, to):
            raise("DriverStateError", l.device.location + " : " + name_of(l.state) + " -> " + name_of(to) + " interdit")
        self.events += 1
        t := "#" + str(self.events) + " " + l.device.location + " : " + name_of(l.state) + " -> " + name_of(to)
        if why != "":
            t = t + " (" + why + ")"
        append(self.history, t)
        l.state = to

    func _driver(dev: HwDevice) -> str:
        return self.manager.driver_of(dev.location)

    func start(dev: HwDevice) -> bool:
        l := self._life(dev)
        if l.state == RUNNING:
            return true
        if not allowed(l.state, RUNNING):
            raise("DriverStateError", dev.location + " : démarrage impossible depuis « " + name_of(l.state) + " »")
        if self.manager.device(dev.location) == null:
            self.manager.add_device(dev)
        b := self.manager.bind(dev)
        if b != null:
            if b.bound():
                self._move(l, RUNNING, b.driver_name())
                return true
            l.last_error = b.error
            self._move(l, FAILED, b.error_type + " : " + b.error)
            return false
        l.last_error = "aucun pilote"
        self._move(l, FAILED, "aucun pilote")
        return false

    func stop(dev: HwDevice):
        l := self._life(dev)
        self._move(l, STOPPED, "")
        self.manager.unbind(dev)

    func _hooks_of(dev: HwDevice) -> _Hooks?:
        n := self._driver(dev)
        for h in self.hooks:
            if h.driver == n:
                return h
        return null

    func suspend(dev: HwDevice):
        l := self._life(dev)
        if not allowed(l.state, SUSPENDED):
            raise("DriverStateError", dev.location + " : mise en veille impossible depuis « " + name_of(l.state) + " »")
        h := self._hooks_of(dev)
        if h != null:
            try:
                h.hooks.suspend(dev)
            catch e:
                self.fail(dev, "suspend : " + e.message)
                return
        self._move(l, SUSPENDED, "")

    func resume(dev: HwDevice):
        l := self._life(dev)
        if l.state != SUSPENDED:
            raise("DriverStateError", dev.location + " : reprise impossible depuis « " + name_of(l.state) + " »")
        h := self._hooks_of(dev)
        if h != null:
            try:
                h.hooks.resume(dev)
            catch e:
                self.fail(dev, "resume : " + e.message)
                return
        self._move(l, RUNNING, "")

    # Signalé par un pilote (ou après un délai dépassé) : le périphérique passe en échec.
    func fail(dev: HwDevice, why: str):
        l := self._life(dev)
        l.last_error = why
        self._move(l, FAILED, why)

    # Détache et relie ; DriverStateError au-delà de max_restarts.
    func restart(dev: HwDevice) -> bool:
        l := self._life(dev)
        if l.restarts >= self.max_restarts:
            raise("DriverStateError", dev.location + " : " + str(l.restarts) + " redémarrages, abandon (" + l.last_error + ")")
        l.restarts += 1
        self.manager.unbind(dev)
        keep: list[Binding] := []
        for b in self.manager.bindings:
            if b.device.location != dev.location:
                append(keep, b)
        self.manager.bindings = keep
        if l.state == RUNNING or l.state == SUSPENDED:
            self._move(l, STOPPED, "redémarrage")
        if l.state == FAILED:
            self._move(l, STOPPED, "redémarrage " + str(l.restarts))
        return self.start(dev)

    func remove(dev: HwDevice):
        l := self._life(dev)
        if l.state == RUNNING or l.state == SUSPENDED:
            self.manager.unbind(dev)
        self._move(l, REMOVED, "")
        dev.state = "retiré"

    func count(state: int) -> int:
        n := 0
        for l in self.lives:
            if l.state == state:
                n += 1
        return n

    func history_text() -> str:
        out := ""
        for h in self.history:
            out = out + h + "\n"
        return out
