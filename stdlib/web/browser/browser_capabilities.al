# ALEX STANDARD LIBRARY — web.browser.browser_capabilities
#
# Profils de navigateurs et d'appareils pour la simulation : User-Agent, fonctionnalités Web prises en
# charge (détection de fonctionnalités), propriétés CSS non gérées (CSS.supports via web.css.supports_query),
# et appareils types (taille d'écran, densité, tactile). Permet de tester une page « comme sur » un ancien
# navigateur ou un mobile.
#
#   use web.browser.browser_capabilities as caps
#   p := caps.profile("safari")
#   p.supports("notifications"), p.supports("web-share")
#   p.css_supports("(display: grid)")                     # true
#   caps.profile("legacy").css_supports("(gap: 1rem)")    # false
#   d := caps.device("iphone-15")
#   d.width, d.height, d.dpr, d.touch                     # 393 852 3 true
#   caps.devices()                                        # noms disponibles
#
# Erreurs : BrowserError (profil ou appareil inconnu).

from core use len, type
from collections use append, keys
use web.browser.browser_errors as _err
use web.css.supports_query as _sq

const ALL_FEATURES := ["fetch", "promises", "abort-controller", "local-storage", "session-storage", "history", "clipboard", "clipboard-read", "notifications", "permissions", "fullscreen", "geolocation", "intersection-observer", "resize-observer", "mutation-observer", "request-animation-frame", "file-reader", "blob", "url", "url-search-params", "form-data", "custom-events", "pointer-events", "web-share", "vibrate", "send-beacon", "visibility", "service-worker", "web-components", "dialog", "popover", "view-transitions", "container-queries", "has-selector", "css-nesting", "web-gpu"]

class Profile:
    func init(name, user_agent, missing_features=null, unsupported_css=null, unsupported_selectors=null, unsupported_values=null):
        self.name = name
        self.user_agent = user_agent
        self.missing = missing_features if missing_features != null else []
        self.engine = _sq.Engine(unsupported_css, unsupported_selectors, unsupported_values)

    func supports(feature):
        return feature in ALL_FEATURES and not (feature in self.missing)

    func features():
        out := []
        for f in ALL_FEATURES:
            if not (f in self.missing):
                append(out, f)
        return out

    # CSS.supports(condition) selon ce profil.
    func css_supports(condition, value=null):
        if value != null:
            return _sq.supports_declaration(condition, value, self.engine)
        return _sq.supports(condition, self.engine)

const _UA_CHROME := "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36"
const _UA_FIREFOX := "Mozilla/5.0 (X11; Linux x86_64; rv:132.0) Gecko/20100101 Firefox/132.0"
const _UA_SAFARI := "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_6) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"
const _UA_MOBILE := "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"
const _UA_ALEX := "Mozilla/5.0 (ALEX; Linux) AlexBrowser/1.0 (simulé)"
const _UA_LEGACY := "Mozilla/5.0 (Windows NT 6.1; Trident/7.0; rv:11.0) like Gecko"

func profile(name="alex"):
    if name == "alex":
        return Profile("alex", _UA_ALEX)
    if name == "chrome":
        return Profile("chrome", _UA_CHROME, ["web-gpu"])
    if name == "firefox":
        return Profile("firefox", _UA_FIREFOX, ["web-share", "vibrate", "clipboard-read", "popover"], null, null, ["text-wrap: pretty"])
    if name == "safari":
        return Profile("safari", _UA_SAFARI, ["vibrate", "web-gpu"], null, null)
    if name == "mobile-safari":
        return Profile("mobile-safari", _UA_MOBILE, ["vibrate", "notifications", "fullscreen", "web-gpu"])
    if name == "legacy":
        return Profile("legacy", _UA_LEGACY, ["fetch", "promises", "abort-controller", "intersection-observer", "resize-observer", "clipboard", "clipboard-read", "notifications", "permissions", "pointer-events", "web-share", "service-worker", "web-components", "dialog", "popover", "view-transitions", "container-queries", "has-selector", "css-nesting", "web-gpu", "url-search-params", "custom-events"], ["gap", "aspect-ratio", "inset", "container-type", "container-name", "translate", "rotate", "scale", "accent-color", "backdrop-filter"], [":has", ":is", ":where", ":focus-visible"], ["grid", "var(", "clamp(", "min(", "max(", "sticky"])
    _err.browser_error("browser_capabilities.profile", "profil inconnu « " + str(name) + " » (alex, chrome, firefox, safari, mobile-safari, legacy)")

func profiles():
    return ["alex", "chrome", "firefox", "safari", "mobile-safari", "legacy"]

class Device:
    func init(name, width, height, dpr=1, touch=false, mobile=false, profile_name="alex"):
        self.name = name
        self.width = width
        self.height = height
        self.dpr = dpr
        self.touch = touch
        self.mobile = mobile
        self.profile_name = profile_name

    func landscape():
        return Device(self.name + " (paysage)", self.height, self.width, self.dpr, self.touch, self.mobile, self.profile_name)

const _DEVICES := {
    "desktop": [1280, 720, 1, false, false, "alex"],
    "desktop-hd": [1920, 1080, 1, false, false, "chrome"],
    "laptop": [1440, 900, 2, false, false, "safari"],
    "iphone-se": [375, 667, 2, true, true, "mobile-safari"],
    "iphone-15": [393, 852, 3, true, true, "mobile-safari"],
    "pixel-8": [412, 915, 2.625, true, true, "chrome"],
    "galaxy-s24": [360, 780, 3, true, true, "chrome"],
    "ipad": [820, 1180, 2, true, true, "mobile-safari"],
    "ipad-pro": [1024, 1366, 2, true, true, "mobile-safari"],
    "4k": [3840, 2160, 2, false, false, "chrome"]
}

func device(name="desktop"):
    if not (name in _DEVICES):
        _err.browser_error("browser_capabilities.device", "appareil inconnu « " + str(name) + " »")
    d := _DEVICES[name]
    return Device(name, d[0], d[1], d[2], d[3], d[4], d[5])

func devices():
    return keys(_DEVICES)
