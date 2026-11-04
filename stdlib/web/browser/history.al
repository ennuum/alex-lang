# ALEX STANDARD LIBRARY — web.browser.history
#
# Historique de session d'un onglet (window.history) : entrées (URL, état, titre, document), push_state /
# replace_state (même origine uniquement), back / forward / go ASYNCHRONES (tâche de la boucle) avec
# « popstate » (et « hashchange » quand seul le fragment change) pour les entrées du même document, et
# rechargement du document mémorisé sinon.
#
#   h := window.history
#   h.push_state({"page": 2}, "", "?page=2")       # URL changée sans chargement
#   h.length(), h.state()                          # 2 {"page": 2}
#   h.back()                                       # popstate au prochain tour de boucle
#   loop.run_until_idle()
#   h.state()                                      # null (entrée initiale)
#
# Erreurs : SecurityError (URL d'une autre origine), DataCloneError (état non clonable).

from core use len, type
from collections use append, keys
use web.url.url as _url
use web.browser.browser_errors as _err
use web.dom.event as _ev
use web.dom.event_target as _et
from web.dom.event use Event

class PopStateEvent extends Event:
    func init(state):
        super.init("popstate")
        self.state = state

class HashChangeEvent extends Event:
    func init(old_url, new_url):
        super.init("hashchange")
        self.old_url = old_url
        self.new_url = new_url

class HistoryEntry:
    func init(url, state=null, title="", document=null):
        self.url = url              # Url (web.url)
        self.state = state
        self.title = title
        self.document = document
        self.scroll = (0, 0)

# Copie structurée d'une valeur d'état (types JSON) ; DataCloneError sinon.
func clone_state(v):
    t := type(v)
    if v == null or t == "bool" or t == "int" or t == "float" or t == "str":
        return v
    if t == "list" or t == "tuple":
        out := []
        for x in v:
            append(out, clone_state(x))
        return out
    if t == "dict":
        out := {}
        for k in keys(v):
            out[k] = clone_state(v[k])
        return out
    _err.fail(_err.DATA_CLONE, "history", "valeur d'état non clonable (" + t + ")")

class History:
    # context : onglet (web.browser.browser.Tab) : url, document, window, loop, load_entry(entrée).
    func init(context):
        self.context = context
        self.entries = []
        self.index = -1
        self.scroll_restoration = "auto"

    func _start(url, document):
        self.entries = [HistoryEntry(url, null, "", document)]
        self.index = 0

    func length():
        return len(self.entries)

    func current():
        return self.entries[self.index] if self.index >= 0 else null

    func state():
        e := self.current()
        return e.state if e != null else null

    func _resolve(url):
        cur := self.context.url
        if url == null:
            return cur
        u := _url.parse(str(url), cur)
        if u.origin() != cur.origin():
            _err.security_error("history", "l'URL « " + u.href() + " » n'est pas de la même origine que « " + cur.href() + " »")
        return u

    # Nouvelle entrée pour le document courant (les entrées « en avant » sont abandonnées).
    func push_state(state, title="", url=null):
        u := self._resolve(url)
        s := clone_state(state)
        cur := self.current()
        if cur != null:
            cur.scroll = self.context.scroll_position()
        self.entries = self.entries[0:self.index + 1] + [HistoryEntry(u, s, title, self.context.document)]
        self.index = len(self.entries) - 1
        self.context.set_url(u)

    func replace_state(state, title="", url=null):
        u := self._resolve(url)
        s := clone_state(state)
        e := self.current()
        if e == null:
            self._start(u, self.context.document)
            e = self.current()
        e.url = u
        e.state = s
        e.title = title
        self.context.set_url(u)

    # Nouvelle entrée après une navigation (chargement d'un document).
    func _navigated(url, document, replace=false):
        if self.index < 0:
            self._start(url, document)
            return
        cur := self.current()
        cur.scroll = self.context.scroll_position()
        e := HistoryEntry(url, null, "", document)
        if replace:
            self.entries[self.index] = e
        else:
            self.entries = self.entries[0:self.index + 1] + [e]
            self.index = len(self.entries) - 1

    func back():
        self.go(-1)

    func forward():
        self.go(1)

    # Parcours asynchrone ; go(0) recharge.
    func go(delta=0):
        h := self
        if delta == 0:
            self.context.loop.queue_task(() => h.context.reload())
            return
        target := self.index + delta
        if target < 0 or target >= len(self.entries):
            return
        self.context.loop.queue_task(() => h._traverse(target))

    func _traverse(target):
        if target < 0 or target >= len(self.entries):
            return
        old := self.current()
        new_entry := self.entries[target]
        old.scroll = self.context.scroll_position()
        self.index = target
        if new_entry.document != old.document or new_entry.document == null:
            self.context.load_entry(new_entry)
            return
        old_url := self.context.url
        self.context.set_url(new_entry.url)
        if self.scroll_restoration == "auto":
            self.context.restore_scroll(new_entry.scroll)
        w := self.context.window
        _et.dispatch(w, PopStateEvent(new_entry.state), true)
        if old_url.without_fragment().href() == new_entry.url.without_fragment().href() and old_url.fragment != new_entry.url.fragment:
            _et.dispatch(w, HashChangeEvent(old_url.href(), new_entry.url.href()), true)

    func urls():
        out := []
        for e in self.entries:
            append(out, e.url.href())
        return out
