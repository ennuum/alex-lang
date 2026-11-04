# ALEX STANDARD LIBRARY — web.browser.navigator
#
# window.navigator : identité du navigateur (user_agent, vendor, platform, languages), état en ligne
# (événements online / offline), capacités (hardware_concurrency, device_memory, max_touch_points,
# cookie_enabled, pdf_viewer_enabled), permissions, presse-papiers, géolocalisation simulée (soumise à la
# permission), send_beacon, vibrate, share (journalisés), et user_agent_data.
#
#   nav := window.navigator
#   nav.user_agent, nav.language, nav.online
#   nav.set_online(false)                       # « offline » sur la fenêtre ; fetch échoue
#   nav.geolocation.set_position(48.85, 2.35)
#   nav.geolocation.get_current_position((pos) => print(pos.coords.latitude), (err) => print(err.message))
#   nav.send_beacon("/stats", "vue")            # true
#   nav.vibrations                              # motifs demandés par vibrate()
#
# Erreurs : (rappels d'erreur) GeolocationPositionError PERMISSION_DENIED, POSITION_UNAVAILABLE.

from core use len, type
from collections use append
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.browser.permissions as _perm
use web.dom.event as _ev
use web.dom.event_target as _et

class Coordinates:
    func init(latitude, longitude, accuracy=10, altitude=null, heading=null, speed=null):
        self.latitude = latitude
        self.longitude = longitude
        self.accuracy = accuracy
        self.altitude = altitude
        self.altitude_accuracy = null
        self.heading = heading
        self.speed = speed

class GeolocationPosition:
    func init(coords, timestamp):
        self.coords = coords
        self.timestamp = timestamp

class GeolocationPositionError:
    func init(code, message):
        self.code = code
        self.message = message

const PERMISSION_DENIED := 1
const POSITION_UNAVAILABLE := 2
const TIMEOUT := 3

class Geolocation:
    func init(navigator):
        self.navigator = navigator
        self.position = null           # Coordinates simulées (null : indisponible)
        self.watchers = []
        self.next_id = 1

    func set_position(latitude, longitude, accuracy=10):
        self.position = Coordinates(latitude, longitude, accuracy)
        for w in self.watchers:
            self._deliver(w[1], w[2])

    func _deliver(success, error):
        nav := self.navigator
        st := nav.permissions_manager.request(nav.origin, "geolocation") if nav.permissions_manager != null else _perm.GRANTED
        loop := nav.loop
        if st != _perm.GRANTED:
            if error != null:
                e := GeolocationPositionError(PERMISSION_DENIED, "User denied Geolocation")
                loop.queue_task(() => error(e))
            return
        if self.position == null:
            if error != null:
                e2 := GeolocationPositionError(POSITION_UNAVAILABLE, "Position unavailable")
                loop.queue_task(() => error(e2))
            return
        pos := GeolocationPosition(self.position, loop.now())
        loop.queue_task(() => success(pos))

    func get_current_position(success, error=null, options=null):
        self._deliver(success, error)

    func watch_position(success, error=null, options=null):
        id := self.next_id
        self.next_id += 1
        append(self.watchers, (id, success, error))
        self._deliver(success, error)
        return id

    func clear_watch(id):
        kept := []
        for w in self.watchers:
            if w[0] != id:
                append(kept, w)
        self.watchers = kept

class Navigator:
    func init(user_agent, loop=null, origin="null", permissions_manager=null, clipboard=null, network=null, window=null):
        self.user_agent = user_agent
        self.app_name = "Netscape"
        self.app_code_name = "Mozilla"
        self.app_version = user_agent[8:len(user_agent)] if len(user_agent) > 8 else user_agent
        self.product = "Gecko"
        self.vendor = "ALEX"
        self.platform = "Linux x86_64"
        self.language = "fr-FR"
        self.languages = ["fr-FR", "fr", "en"]
        self.online = true
        self.cookie_enabled = true
        self.hardware_concurrency = 8
        self.device_memory = 8
        self.max_touch_points = 0
        self.pdf_viewer_enabled = true
        self.webdriver = false
        self.do_not_track = null
        self.loop = loop if loop != null else _tm.default_loop()
        self.origin = origin
        self.permissions_manager = permissions_manager
        self.permissions = _perm.Permissions(permissions_manager, origin, self.loop) if permissions_manager != null else null
        self.clipboard = clipboard
        self.network = network
        self.window = window
        self.geolocation = Geolocation(self)
        self.beacons = []              # (url, données)
        self.beacon_sender = null      # fn(url, données) : envoi réel
        self.vibrations = []
        self.shares = []
        self.user_agent_data = {"brands": [{"brand": "ALEX", "version": "1"}], "mobile": false, "platform": "Linux"}

    func set_online(on):
        if self.online == on:
            return
        self.online = on
        if self.network != null:
            self.network.offline = not on
        if self.window != null:
            _et.dispatch(self.window, _ev.Event("online" if on else "offline"), true)

    # POST sans attendre la réponse (branché par web.browser sur fetch) ; false hors ligne.
    func send_beacon(url, data=null):
        append(self.beacons, (str(url), data))
        if not self.online:
            return false
        if self.beacon_sender != null:
            self.beacon_sender(url, data)
        return true

    func vibrate(pattern):
        append(self.vibrations, pattern)
        return true

    func can_share(data=null):
        return true

    func share(data):
        append(self.shares, data)
        return _tm.resolved(self.loop, null)

    func java_enabled():
        return false
