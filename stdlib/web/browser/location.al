# ALEX STANDARD LIBRARY — web.browser.location
#
# window.location : URL du document courant en composantes (href, protocol, host, hostname, port, pathname,
# search, hash, origin) ; affecter le fragment fait une navigation dans le document (entrée d'historique et
# « hashchange »), affecter une autre composante ou assign() charge un nouveau document, replace() remplace
# l'entrée d'historique, reload() recharge.
#
#   loc := window.location
#   loc.pathname(), loc.search(), loc.hash()
#   loc.set_hash("#section-2")          # hashchange au prochain tour de boucle
#   loc.assign("/autre-page")           # navigation (chargement par le réseau de l'onglet)
#   loc.replace("/connexion")           # sans entrée d'historique
#   loc.reload()
#
# Erreurs : SyntaxError (URL invalide).

from core use len, type
use string as _s
use web.url.url as _url
use web.browser.browser_errors as _err
use web.browser.history as _hist
use web.dom.event_target as _et

class Location:
    func init(context):
        self.context = context
        self.ancestor_origins = []

    func _u():
        return self.context.url

    func _resolve(value):
        try:
            return _url.parse(str(value), self._u())
        catch e:
            _err.fail(_err.SYNTAX, "location", "URL invalide « " + str(value) + " »")

    func href():
        return self._u().href()

    func to_string():
        return self.href()

    func __str__():
        return self.href()

    func origin():
        return self._u().origin()

    func protocol():
        return self._u().scheme + ":"

    func host():
        h := self._u().host_port()
        return h if h != null else ""

    func hostname():
        h := self._u().host
        return h if h != null else ""

    func port():
        p := self._u().port
        return str(p) if p != null else ""

    func pathname():
        return self._u().path

    func search():
        q := self._u().query
        return ("?" + q) if q != null and q != "" else ""

    func hash():
        f := self._u().fragment
        return ("#" + f) if f != null and f != "" else ""

    func assign(url):
        self.context.navigate(self._resolve(url).href())

    func set_href(url):
        u := self._resolve(url)
        cur := self._u()
        if u.without_fragment().href() == cur.without_fragment().href() and u.fragment != null:
            self._fragment_navigation(u)
            return
        self.context.navigate(u.href())

    func replace(url):
        self.context.navigate(self._resolve(url).href(), true)

    func reload():
        self.context.reload()

    func set_hash(value):
        v := str(value)
        if _s.starts_with(v, "#"):
            v = v[1:len(v)]
        u := self._u().with_fragment(v) if v != "" else self._u().without_fragment()
        self._fragment_navigation(u)

    func _fragment_navigation(u):
        old := self._u()
        if old.href() == u.href():
            return
        h := self.context.window.history
        h.push_state(h.state(), "", u.href())
        doc := self.context.document
        if doc != null:
            doc.target_id = u.fragment
        w := self.context.window
        ev := _hist.HashChangeEvent(old.href(), u.href())
        self.context.loop.queue_task(() => _et.dispatch(w, ev, true))

    func set_search(value):
        v := str(value)
        if _s.starts_with(v, "?"):
            v = v[1:len(v)]
        self.context.navigate(self._u().with_query(v if v != "" else null).href())

    func set_pathname(value):
        self.context.navigate(self._u().with_path(str(value)).href())

    func set_host(value):
        self.context.navigate(self._u().with_host(str(value)).href())

    func set_hostname(value):
        self.context.navigate(self._u().with_host(str(value)).href())

    func set_protocol(value):
        self.context.navigate(self._u().with_scheme(_s.replace(str(value), ":", "")).href())

    func set_port(value):
        v := str(value)
        self.context.navigate(self._u().with_port(v if v != "" else null).href())
