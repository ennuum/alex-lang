# ALEX STANDARD LIBRARY — web.browser
#
# Navigateur SIMULÉ, entièrement en ALEX : onglets chargeant des pages (par le réseau simulé, un serveur ALEX
# en processus, ou du HTML fourni), DOM complet (web.dom), boucle d'événements à horloge virtuelle
# (minuteries, micro-tâches, images), fetch, cookies (document.cookie et en-têtes), stockage local et de
# session, historique et location, navigator (permissions, presse-papiers, géolocalisation), notifications,
# plein écran, visibilité, console, profils de navigateurs et d'appareils. Les « scripts » de page sont des
# fonctions ALEX (on_load) : idéal pour tester des sites et des serveurs web.server de bout en bout.
#
#   use web.browser as wb
#   b := wb.Browser()
#   b.route("https://app.test", router)                 # serveur web.server sans réseau
#   tab := b.new_tab(null, "iphone-15")
#   tab.goto("https://app.test/")                       # charge et analyse la page (DOMContentLoaded, load)
#   tab.query("h1").text_content()
#   tab.fill("input[name=q]", "chat")
#   tab.click("button[type=submit]")                    # envoi du formulaire -> nouvelle page
#   tab.wait_for_navigation()
#   tab.url.href(), tab.window.history.length()
#   tab.window.local_storage.set_item("theme", "sombre")
#   tab.console.messages
#   b.run(1000)                                         # avance l'horloge virtuelle d'une seconde
#
# Erreurs : BrowserError (onglet fermé, profil inconnu), TypeError (échec de chargement : réseau, URL).

from core use len, type
from collections use append, keys
use string as _s
use web.url.url as _url
use web.client.http_client as _hc
use web.http.headers as _hhead
use web.dom.document as _ddoc
use web.dom.window as _dwin
use web.dom.events as _devents
use web.dom.event as _ev
use web.dom.event_target as _et
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.browser.console as _console
use web.browser.fetch as _fetch
use web.browser.request as _rq
use web.browser.local_storage as _ls
use web.browser.session_storage as _ss
use web.browser.history as _hist
use web.browser.location as _loc
use web.browser.navigator as _nav
use web.browser.clipboard as _clip
use web.browser.permissions as _perm
use web.browser.notifications as _notif
use web.browser.fullscreen as _fs
use web.browser.visibility as _vis
use web.browser.form_data as _fd
use web.browser.url_search_params as _usp
use web.browser.browser_capabilities as _caps
use web.browser.object_url as _ou

class Browser:
    # profile : nom de profil (web.browser.browser_capabilities) ; virtual_time : horloge virtuelle ;
    # storage_dir : persistance du stockage local ; echo : console recopiée sur la sortie standard.
    func init(profile="alex", virtual_time=true, storage_dir=null, echo=false):
        self.loop = _tm.EventLoop(virtual_time)
        self.profile = _caps.profile(profile)
        self.cookie_jar = _hc.CookieJar()
        self.network = _fetch.Network(self.loop, self.cookie_jar)
        self.storage = _ls.StorageArea(storage_dir)
        self.permissions = _perm.PermissionManager()
        self.clipboard_data = _clip.ClipboardData()
        self.tabs = []
        self.echo = echo
        self.closed = false
        self.subscribed = []           # origines dont les événements storage sont diffusés

    func new_tab(url=null, device="desktop", html=null):
        if self.closed:
            _err.browser_error("Browser.new_tab", "navigateur fermé")
        d := _caps.device(device) if type(device) == "str" else device
        t := Tab(self, d)
        append(self.tabs, t)
        if html != null:
            t.load_html(html, url if url != null else "about:blank")
        elif url != null:
            t.goto(url)
        return t

    func open(url, device="desktop"):
        return self.new_tab(url, device)

    func mock(pattern, handler, method="*"):
        self.network.mock(pattern, handler, method)
        return self

    func route(origin, router):
        self.network.route(origin, router)
        return self

    # Avance l'horloge (virtuelle) de ms millisecondes en exécutant minuteries, tâches et images.
    func run(ms):
        self.loop.advance(ms)
        return self

    func idle(max_ms=60000):
        return self.loop.run_until_idle(max_ms)

    func set_online(on):
        self.network.offline = not on
        for t in self.tabs:
            t.window.navigator.set_online(on)

    func cookies():
        return self.cookie_jar.to_dict()

    func close():
        for t in self.tabs:
            t.close()
        self.closed = true

    func _storage_event(e, source, origin):
        # diffusion aux autres fenêtres du même onglet (et aux autres onglets) de la même origine
        for t in self.tabs:
            if t.closed or t.url.origin() != origin:
                continue
            if source == t.window:
                continue
            ev := _ls.StorageEvent(e.key, e.old_value, e.new_value, t.url.href(), e.storage_area)
            w := t.window
            self.loop.queue_task(() => _et.dispatch(w, ev, true))

class Tab:
    func init(browser, device):
        self.browser = browser
        self.loop = browser.loop
        self.device = device
        self.url = _url.parse("about:blank")
        self.console = _console.Console(browser.echo, () => browser.loop.now())
        self.session = _ss.SessionStorageArea()
        self.history = _hist.History(self)
        self.location = _loc.Location(self)
        self.on_load = []              # fonctions (onglet, document, fenêtre) : « scripts » de page
        self.loads = 0
        self.closed = false
        self.last_html = null
        self.pending = null            # promesse de la navigation en cours
        self.document = null
        self.window = null
        self._install(_ddoc.new_document(), self.url)
        self.history._navigated(self.url, self.document)

    # ------------------------------------------------------------ installation d'un document

    func origin():
        return self.url.origin()

    func _install(doc, u):
        self.url = u
        doc.url = u.href()
        d := self.device
        w := _dwin.Window(doc, d.width, d.height, d.dpr)
        if d.touch:
            w.hover = "none"
            w.pointer = "coarse"
        b := self.browser
        tab := self
        origin := u.origin()
        w.timers = self.loop
        w.console = self.console
        w.performance = {"time_origin": self.loop.now()}
        w.location = self.location
        w.history = self.history
        clip := _clip.Clipboard(b.clipboard_data, b.permissions, origin, self.loop, () => tab.document.has_focus())
        nav := _nav.Navigator(b.profile.user_agent, self.loop, origin, b.permissions, clip, b.network, w)
        nav.max_touch_points = 5 if d.touch else 0
        nav.online = not b.network.offline
        nav.beacon_sender = (url2, data) => _fetch.send_beacon(b.network, url2, data, tab.fetch_context())
        w.navigator = nav
        store := b.storage.for_origin(origin)
        w.local_storage = store.view_for(w)
        if not (origin in b.subscribed):
            append(b.subscribed, origin)
            store.subscribe((e, src) => b._storage_event(e, src, origin))
        w.session_storage = self.session.for_origin(origin).view_for(w)
        w.notifications = _notif.NotificationCenter(b.permissions, origin, self.loop)
        w.fullscreen = _fs.FullscreenManager(doc, w, self.loop)
        w.visibility = _vis.PageVisibility(doc, w)
        doc.mutation_hub.scheduler = (fn) => tab.loop.queue_microtask(fn)
        doc.on_navigate = (href, target) => tab._link(href, target)
        doc.on_submit = (form, submitter) => tab._submit(form, submitter)
        doc.cookie_jar = b.cookie_jar
        self.document = doc
        self.window = w

    func fetch_context():
        return _fetch.FetchContext(self.url, self.browser.cookie_jar, self.url.origin())

    # ------------------------------------------------------------ chargement

    # Charge un document depuis du HTML (url : adresse attribuée au document).
    func load_html(html, url="about:blank", replace=false):
        self._check_open()
        u := _url.parse(str(url)) if type(url) == "str" else url
        old_window := self.window
        if old_window != null and self.loads > 0:
            _et.dispatch(old_window, _ev.Event("pagehide"), true)
            _et.dispatch(old_window, _ev.Event("unload"), true)
        doc := _ddoc.parse_html(str(html), u.href())
        self._install(doc, u)
        self.last_html = str(html)
        if self.loads == 0:
            self.history._start(u, doc)
        else:
            self.history._navigated(u, doc, replace)
        self.loads += 1
        if u.fragment != null:
            doc.target_id = u.fragment
        for fn in self.on_load:
            try:
                fn(self, doc, self.window)
            catch e:
                self.console.error("Erreur de script : " + str(e.type) + " : " + str(e.message))
        doc.finish_loading()
        self.loop.run_microtasks()
        return doc

    # Navigation (asynchrone) : promesse du document chargé.
    func navigate(url, replace=false, init_value=null):
        self._check_open()
        u := _url.parse(str(url), self.url) if self.url.scheme != "about" else _url.parse(str(url))
        p := _tm.Promise(self.loop)
        tab := self
        o := init_value if init_value != null else {}
        if not ("credentials" in o):
            o["credentials"] = "include"
        o["mode"] = "navigate" if not ("mode" in o) else o["mode"]
        req := _fetch.fetch(self.browser.network, u.href(), o, null)
        req.then((resp) => tab._loaded(resp, replace, p), (e) => tab._failed(e, u, p))
        self.pending = p
        return p

    func _loaded(resp, replace, p):
        text := resp.body_text()
        ct := resp.headers.get("content-type")
        html := text
        if ct != null and not _s.contains(_s.lower(ct), "html"):
            html = "<!DOCTYPE html><html><head><title></title></head><body><pre>" + _s.replace(_s.replace(_s.replace(text, "&", "&amp;"), "<", "&lt;"), ">", "&gt;") + "</pre></body></html>"
        doc := self.load_html(html, _url.parse(resp.url), replace)
        doc.http_status = resp.status
        p.resolve(doc)

    func _failed(e, u, p):
        self.console.error("Échec du chargement de " + u.href() + " : " + str(e.message))
        doc := self.load_html("<!DOCTYPE html><title>Erreur</title><h1>Impossible d'atteindre la page</h1><p>" + _s.replace(_s.replace(u.href(), "&", "&amp;"), "<", "&lt;") + "</p>", u)
        doc.http_status = 0
        p.reject(e)

    # Charge une URL et attend le document (échec réseau : TypeError).
    func goto(url, timeout_ms=30000):
        return self.navigate(url).wait(timeout_ms)

    func wait_for_navigation(timeout_ms=30000):
        if self.pending == null:
            return self.document
        p := self.pending
        self.pending = null
        return p.wait(timeout_ms)

    func reload():
        if self.url.scheme == "about" or (self.last_html != null and not (self.url.scheme == "http" or self.url.scheme == "https")):
            return self.load_html(self.last_html if self.last_html != null else "", self.url, true)
        return self.navigate(self.url.href(), true)

    # Retour à une entrée d'historique (document mémorisé, sans nouveau chargement).
    func load_entry(entry):
        doc := entry.document
        if doc == null:
            self.navigate(entry.url.href(), true)
            return
        old := self.window
        _et.dispatch(old, _ev.Event("pagehide"), true)
        self.document = doc
        self.window = doc.default_view
        self.url = entry.url
        doc.url = entry.url.href()
        self.restore_scroll(entry.scroll)
        _et.dispatch(self.window, _vis.PageTransitionEvent("pageshow", true), true)
        _et.dispatch(self.window, _hist.PopStateEvent(entry.state), true)

    func set_url(u):
        self.url = u
        if self.document != null:
            self.document.url = u.href()

    func scroll_position():
        if self.window == null:
            return (0, 0)
        return (self.window.scroll_x, self.window.scroll_y)

    func restore_scroll(pos):
        if self.window != null:
            self.window.scroll_to(pos[0], pos[1])

    func _link(href, target):
        if target == "_blank":
            t := self.browser.new_tab(null, self.device)
            t.session = self.session.clone()
            t.navigate(_url.parse(href, self.url).href())
            return
        u := _url.parse(href, self.url)
        if u.without_fragment().href() == self.url.without_fragment().href() and u.fragment != null:
            self.location.set_href(u.href())
            return
        self.navigate(u.href())

    # Envoi d'un formulaire accepté : GET (paramètres dans l'URL) ou POST (urlencoded ou multipart).
    func _submit(form, submitter):
        method := _s.upper(submitter.get_attribute("formmethod") if submitter != null and submitter.has_attribute("formmethod") else (form.get_attribute("method") if form.has_attribute("method") else "GET"))
        action := submitter.get_attribute("formaction") if submitter != null and submitter.has_attribute("formaction") else form.get_attribute("action")
        target := _url.parse(action if action != null and action != "" else self.url.href(), self.url)
        data := _fd.FormData(form, submitter)
        if method == "DIALOG":
            d := form.closest("dialog")
            if d != null:
                d.remove_attribute("open")
            return
        if method != "POST":
            q := data.to_urlencoded()
            self.navigate(target.with_query(q if q != "" else null).href())
            return
        enctype := _s.lower(form.get_attribute("enctype") if form.has_attribute("enctype") else "application/x-www-form-urlencoded")
        if enctype == "multipart/form-data":
            self.navigate(target.href(), false, {"method": "POST", "body": data})
        else:
            self.navigate(target.href(), false, {"method": "POST", "body": _usp.URLSearchParams(data.to_urlencoded())})

    # fetch() de la page (contexte : origine, cookies).
    func fetch(input, init_value=null):
        return _fetch.fetch(self.browser.network, input, init_value, self.fetch_context())

    # ------------------------------------------------------------ cookies

    func cookie():
        return document_cookie(self.browser.cookie_jar, self.url)

    func set_cookie(text):
        set_document_cookie(self.browser.cookie_jar, self.url, text)

    # ------------------------------------------------------------ interactions pratiques

    func _el(selector):
        e := self.document.query_selector(selector)
        if e == null:
            _err.not_found("Tab", "aucun élément ne correspond à « " + selector + " »")
        return e

    func query(selector):
        return self.document.query_selector(selector)

    func query_all(selector):
        return self.document.query_selector_all(selector).to_list()

    func click(selector):
        r := _devents.click(self._el(selector))
        self.loop.run_microtasks()
        return r

    func type_text(selector, text):
        return _devents.type_text(self._el(selector), text)

    func fill(selector, text):
        return _devents.fill(self._el(selector), text)

    func press(selector, key):
        return _devents.press_key(self._el(selector), key)

    func select_option(selector, value):
        _devents.select_option(self._el(selector), value)

    func text():
        b := self.document.body()
        return b.inner_text() if b != null else ""

    func html():
        return self.document.to_html()

    func title():
        return self.document.title()

    func resize(width, height):
        self.window.resize(width, height)

    func _check_open():
        if self.closed:
            _err.browser_error("Tab", "onglet fermé")

    func close():
        if self.closed:
            return
        if self.window != null:
            _et.dispatch(self.window, _ev.Event("pagehide"), true)
            _et.dispatch(self.window, _ev.Event("unload"), true)
        self.session.close()
        self.closed = true

# ---------------------------------------------------------------- document.cookie

class _SetCookieResponse:
    func init(line):
        self.headers = _hhead.Headers()
        self.headers.add("Set-Cookie", line)

# Valeur de document.cookie (cookies non HttpOnly visibles pour l'URL).
func document_cookie(jar, u):
    if u.scheme != "http" and u.scheme != "https":
        return ""
    parts := []
    for c in jar.matching(u):
        if not c["http_only"]:
            append(parts, c["name"] + "=" + c["value"])
    return _s.join("; ", parts)

# Affectation de document.cookie (« nom=valeur; path=/; max-age=60 ») ; HttpOnly ignoré comme en JS.
func set_document_cookie(jar, u, text):
    if u.scheme != "http" and u.scheme != "https":
        return
    if _s.contains(_s.lower(str(text)), "httponly"):
        return
    jar.store(u, _SetCookieResponse(str(text)))
