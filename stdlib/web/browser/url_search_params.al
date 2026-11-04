# ALEX STANDARD LIBRARY — web.browser.url_search_params
#
# URLSearchParams (API WHATWG) : paramètres de requête ordonnés et multi-valeurs — construction depuis un
# texte (« ?a=1&b=2 »), un dict ou une liste de paires ; append, delete, get, get_all, has, set, sort,
# to_string (encodage application/x-www-form-urlencoded, espace -> « + »). Lié à un URL (url.search_params),
# chaque modification met à jour url.search.
#
#   use web.browser.url_search_params as usp
#   p := usp.URLSearchParams("?q=chat+noir&page=2")
#   p.get("q")                       # chat noir
#   p.append("tag", "a"); p.append("tag", "b")
#   p.get_all("tag")                 # [a, b]
#   p.set("page", 3)
#   p.delete("tag", "a")
#   p.to_string()                    # q=chat+noir&page=3&tag=b
#   p.size()                         # 3
#
# Erreurs : TypeError (paire mal formée à la construction).

from core use len, type
from collections use append, keys
use string as _s
use web.url.form_url_encoding as _form
use web.browser.browser_errors as _err

func _str(v):
    if v == null:
        return "null"
    if v == true:
        return "true"
    if v == false:
        return "false"
    return str(v)

class URLSearchParams:
    func init(init_value=null):
        self.pairs = []
        self.owner = null            # URL lié (mis à jour à chaque modification)
        if init_value == null:
            return
        t := type(init_value)
        if t == "str":
            for p in _form.decode(init_value):
                append(self.pairs, (p[0], p[1]))
        elif t == "dict":
            for k in keys(init_value):
                append(self.pairs, (_str(k), _str(init_value[k])))
        elif t == "list" or t == "tuple":
            for p in init_value:
                if (type(p) != "list" and type(p) != "tuple") or len(p) != 2:
                    _err.type_error("URLSearchParams", "chaque élément doit être une paire (nom, valeur)")
                append(self.pairs, (_str(p[0]), _str(p[1])))
        elif isinstance(init_value, URLSearchParams):
            for p in init_value.pairs:
                append(self.pairs, p)
        else:
            _err.type_error("URLSearchParams", "texte, dict ou liste de paires attendu")

    func _changed():
        if self.owner != null:
            self.owner._search_params_changed()

    func size():
        return len(self.pairs)

    func __len__():
        return len(self.pairs)

    func append(name, value):
        append(self.pairs, (_str(name), _str(value)))
        self._changed()

    # Retire toutes les paires du nom (ou seulement celles de cette valeur).
    func delete(name, value=null):
        kept := []
        for p in self.pairs:
            if p[0] == name and (value == null or p[1] == _str(value)):
                continue
            append(kept, p)
        self.pairs = kept
        self._changed()

    func get(name):
        for p in self.pairs:
            if p[0] == name:
                return p[1]
        return null

    func get_all(name):
        out := []
        for p in self.pairs:
            if p[0] == name:
                append(out, p[1])
        return out

    func has(name, value=null):
        for p in self.pairs:
            if p[0] == name and (value == null or p[1] == _str(value)):
                return true
        return false

    func __contains__(name):
        return self.has(name)

    # Remplace la première occurrence et retire les suivantes (ou ajoute à la fin).
    func set(name, value):
        out := []
        done := false
        for p in self.pairs:
            if p[0] == name:
                if not done:
                    append(out, (name, _str(value)))
                    done = true
                continue
            append(out, p)
        if not done:
            append(out, (name, _str(value)))
        self.pairs = out
        self._changed()

    # Tri stable par nom.
    func sort():
        out := []
        for p in self.pairs:
            append(out, p)
        i := 1
        while i < len(out):
            cur := out[i]
            j := i - 1
            while j >= 0 and out[j][0] > cur[0]:
                out[j + 1] = out[j]
                j -= 1
            out[j + 1] = cur
            i += 1
        self.pairs = out
        self._changed()

    func keys():
        out := []
        for p in self.pairs:
            append(out, p[0])
        return out

    func values():
        out := []
        for p in self.pairs:
            append(out, p[1])
        return out

    func entries():
        return self.pairs

    func for_each(fn):
        for p in self.pairs:
            fn(p[1], p[0], self)

    func to_dict():
        out := {}
        for p in self.pairs:
            out[p[0]] = p[1]
        return out

    func to_string():
        return _form.encode(self.pairs)

    func __str__():
        return self.to_string()
