# ALEX STANDARD LIBRARY — web.browser.clipboard
#
# Presse-papiers (navigator.clipboard) : write_text / read_text / write / read, en promesses, soumis aux
# permissions clipboard-write / clipboard-read (et au focus du document) comme dans un navigateur ;
# ClipboardItem (plusieurs représentations par type MIME) ; contenu partagé par tout le navigateur et
# consultable par les tests.
#
#   use web.browser.clipboard as cb
#   data := cb.ClipboardData()                  # contenu partagé (un par navigateur)
#   c := cb.Clipboard(data, permissions, "https://exemple.org", loop)
#   c.write_text("copié").wait()
#   data.text()                                 # copié
#   permissions.grant("https://exemple.org", "clipboard-read")
#   c.read_text().wait()                        # copié
#   c.write([cb.ClipboardItem({"text/html": "<b>x</b>", "text/plain": "x"})]).wait()
#
# Erreurs (rejets) : NotAllowedError (permission refusée, document sans focus), NotFoundError (type absent).

from core use len, type
from collections use append, keys
use web.browser.browser_errors as _err
use web.browser.timers as _tm
use web.browser.blob as _blob
use web.browser.permissions as _perm

class ClipboardItem:
    # items : dict type MIME -> texte ou Blob.
    func init(items, presentation_style="unspecified"):
        self.items = {}
        for k in keys(items):
            v := items[k]
            self.items[k] = v if isinstance(v, _blob.Blob) else _blob.Blob([str(v)], {"type": k})
        self.types = keys(self.items)
        self.presentation_style = presentation_style

    func get_type(mime, loop=null):
        p := _tm.Promise(loop)
        if mime in self.items:
            p.resolve(self.items[mime])
        else:
            p.reject(_err.ErrorValue(_err.NOT_FOUND, "type « " + mime + " » absent"))
        return p

func supports(mime):
    return mime in ["text/plain", "text/html", "image/png", "image/svg+xml"]

# Contenu du presse-papiers (partagé).
class ClipboardData:
    func init():
        self.items = []          # liste de ClipboardItem

    func text():
        for it in self.items:
            if "text/plain" in it.items:
                return it.items["text/plain"].text_now()
        return ""

    func set_text(text):
        self.items = [ClipboardItem({"text/plain": str(text)})]

    func clear():
        self.items = []

class Clipboard:
    # focused : fonction sans argument -> vrai si le document a le focus (null : toujours vrai).
    func init(data, permissions, origin, loop=null, focused=null):
        self.data = data
        self.permissions = permissions
        self.origin = origin
        self.loop = loop if loop != null else _tm.default_loop()
        self.focused = focused

    func _allowed(name):
        if self.focused != null and not self.focused():
            return "le document n'a pas le focus"
        if self.permissions == null:
            return null
        st := self.permissions.request(self.origin, name)
        if st != _perm.GRANTED:
            return "permission « " + name + " » refusée"
        return null

    func _run(name, fn):
        p := _tm.Promise(self.loop)
        why := self._allowed(name)
        if why != null:
            p.reject(_err.ErrorValue(_err.NOT_ALLOWED, why))
            return p
        try:
            p.resolve(fn())
        catch e:
            p.reject(_err.ErrorValue(str(e.type), str(e.message)))
        return p

    func write_text(text):
        d := self.data
        return self._run("clipboard-write", () => d.set_text(text))

    func read_text():
        d := self.data
        return self._run("clipboard-read", () => d.text())

    func write(items):
        d := self.data
        return self._run("clipboard-write", () => _set_items(d, items))

    func read():
        d := self.data
        return self._run("clipboard-read", () => d.items)

func _set_items(d, items):
    d.items = items
    return null
