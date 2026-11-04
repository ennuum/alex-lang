# ALEX STANDARD LIBRARY — web.browser.permissions
#
# Permissions du navigateur simulé : état par origine et par nom (granted, denied, prompt), réponse de
# l'« utilisateur » aux demandes (prompt_answer : valeur fixe ou fonction), journal des demandes, et
# navigator.permissions.query() (promesse de PermissionStatus, événement « change » à chaque modification).
#
#   use web.browser.permissions as pm
#   mgr := pm.PermissionManager()
#   mgr.state("https://exemple.org", "notifications")          # prompt
#   mgr.prompt_answer = "granted"
#   mgr.request("https://exemple.org", "notifications")        # granted (et mémorisé)
#   mgr.deny("https://exemple.org", "geolocation")
#   perms := pm.Permissions(mgr, "https://exemple.org", loop)
#   st := perms.query({"name": "geolocation"}).wait()
#   st.state                                                   # denied
#   st.add_event_listener("change", (e) => print(st.state))
#
# Erreurs (rejet) : TypeError (nom de permission inconnu).

from core use len, type
from collections use append, keys
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.dom.event as _ev
use web.dom.event_target as _et
from web.dom.event_target use EventTarget

const GRANTED := "granted"
const DENIED := "denied"
const PROMPT := "prompt"

const NAMES := ["geolocation", "notifications", "push", "midi", "camera", "microphone", "speaker-selection", "clipboard-read", "clipboard-write", "persistent-storage", "screen-wake-lock", "storage-access", "accelerometer", "gyroscope", "magnetometer", "ambient-light-sensor", "background-sync", "background-fetch", "local-fonts", "window-management", "idle-detection", "display-capture", "fullscreen", "payment-handler", "nfc"]
const DEFAULTS := {"clipboard-write": "granted", "fullscreen": "granted", "background-sync": "granted"}

class PermissionStatus extends EventTarget:
    func init(name, state):
        super.init()
        self.name = name
        self.state = state

class PermissionManager:
    func init(defaults=null):
        self.defaults = defaults if defaults != null else DEFAULTS
        self.states = {}               # « origine|nom » -> état
        self.prompt_answer = DENIED    # réponse simulée de l'utilisateur : état ou fn(origine, nom) -> état
        self.prompts = []              # (origine, nom, réponse) des demandes présentées à l'utilisateur
        self.statuses = []             # (origine, PermissionStatus) à tenir à jour

    func _key(origin, name):
        return str(origin) + "|" + str(name)

    func state(origin, name):
        k := self._key(origin, name)
        if k in self.states:
            return self.states[k]
        if name in self.defaults:
            return self.defaults[name]
        return PROMPT

    func set(origin, name, state):
        if not (state in [GRANTED, DENIED, PROMPT]):
            _err.type_error("PermissionManager.set", "état inconnu « " + str(state) + " »")
        self.states[self._key(origin, name)] = state
        for p in self.statuses:
            if p[0] == origin and p[1].name == name and p[1].state != state:
                p[1].state = state
                _et.dispatch(p[1], _ev.Event("change"), true)

    func grant(origin, name):
        self.set(origin, name, GRANTED)

    func deny(origin, name):
        self.set(origin, name, DENIED)

    func reset(origin, name):
        out := {}
        k := self._key(origin, name)
        for x in keys(self.states):
            if x != k:
                out[x] = self.states[x]
        self.states = out
        for p in self.statuses:
            if p[0] == origin and p[1].name == name:
                p[1].state = self.state(origin, name)

    # Demande (comme Notification.requestPermission) : renvoie l'état final ; « dismissed » laisse « prompt ».
    func request(origin, name):
        s := self.state(origin, name)
        if s != PROMPT:
            return s
        ans := self.prompt_answer
        if type(ans) != "str":
            ans = ans(origin, name)
        append(self.prompts, (origin, name, ans))
        if ans == GRANTED or ans == DENIED:
            self.set(origin, name, ans)
            return ans
        return PROMPT

    func status(origin, name):
        st := PermissionStatus(name, self.state(origin, name))
        append(self.statuses, (origin, st))
        return st

# navigator.permissions pour une origine.
class Permissions:
    func init(manager, origin, loop=null):
        self.manager = manager
        self.origin = origin
        self.loop = loop if loop != null else _tm.default_loop()

    func query(descriptor):
        name := descriptor["name"] if type(descriptor) == "dict" and "name" in descriptor else descriptor
        p := _tm.Promise(self.loop)
        if not (name in NAMES):
            p.reject(_err.ErrorValue(_err.TYPE, "permission inconnue « " + str(name) + " »"))
            return p
        p.resolve(self.manager.status(self.origin, name))
        return p

    func state(name):
        return self.manager.state(self.origin, name)
