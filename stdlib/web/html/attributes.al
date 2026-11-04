# ALEX STANDARD LIBRARY — web.html.attributes
#
# Attributes : les attributs d'un élément HTML, dans leur ordre d'ajout, noms comparés sans tenir compte de la
# casse. Les valeurs sont gardées telles quelles (str, bool, nombre, liste de jetons, dict de style) et converties
# au rendu (web.html.attribute_value). Aides pour class, style, data-* et aria-*.
#
#   use web.html.attributes as at
#   a := at.Attributes({"id": "menu", "class": ["nav", "dark"], "hidden": false})
#   a.add_class("open")
#   a.has_class("dark")             # true
#   a.set_style("color", "red")
#   a.set_data("user-id", 42)       # data-user-id="42"
#   a.render()                      #  id="menu" class="nav dark open" style="color: red" data-user-id="42"
#   a.get("hidden")                 # false (présent dans la table, omis au rendu)
#
# Erreurs : HtmlAttributeError (nom invalide), TypeError.

from core use len, type
from collections use append, keys
use string as _s
use web.html.html_errors as _err
use web.html.attribute_value as _av

class Attributes:
    # data : dict, liste de paires, autre Attributes ou null. Les noms ALEX (class_, data_x) sont convertis.
    func init(data=null):
        self.entries = []     # [nom, valeur]
        if data != null:
            self.update(data)

    func _index(name):
        k := _s.lower(name)
        i := 0
        while i < len(self.entries):
            if _s.lower(self.entries[i][0]) == k:
                return i
            i += 1
        return -1

    # Fixe un attribut (remplace la valeur existante, garde sa position). null le supprime.
    func set(name, value):
        n := _av.check_name(_av.html_name(name))
        if value == null:
            return self.remove(n)
        i := self._index(n)
        if i >= 0:
            self.entries[i][1] = value
        else:
            append(self.entries, [n, value])
        return self

    # Valeur brute (telle que fixée), ou fallback.
    func get(name, fallback=null):
        i := self._index(_av.html_name(name))
        if i < 0:
            return fallback
        return self.entries[i][1]

    # Valeur sous forme de texte (rendu), ou fallback si absent ou omis (false / null).
    func get_text(name, fallback=null):
        i := self._index(_av.html_name(name))
        if i < 0:
            return fallback
        t := _av.to_text(self.entries[i][0], self.entries[i][1])
        if t == null:
            return fallback
        return t

    # Présent ET rendu (une valeur false compte comme absente).
    func has(name):
        i := self._index(_av.html_name(name))
        return i >= 0 and self.entries[i][1] != false and self.entries[i][1] != null

    func remove(name):
        i := self._index(_av.html_name(name))
        if i >= 0:
            out := []
            j := 0
            while j < len(self.entries):
                if j != i:
                    append(out, self.entries[j])
                j += 1
            self.entries = out
        return self

    func update(data):
        if isinstance(data, Attributes):
            for e in data.entries:
                self.set(e[0], e[1])
            return self
        t := type(data)
        if t == "dict":
            for k in keys(data):
                self.set(k, data[k])
            return self
        if t == "list" or t == "tuple":
            for p in data:
                self.set(p[0], p[1])
            return self
        raise("TypeError", "Attributes.update : dict, liste de paires ou Attributes attendu (obtenu " + t + ")")

    func names():
        out := []
        for e in self.entries:
            append(out, e[0])
        return out

    # Paires (nom, texte) des attributs rendus (les omis exclus).
    func items():
        out := []
        for e in self.entries:
            t := _av.to_text(e[0], e[1])
            if t != null:
                append(out, (e[0], t))
        return out

    func to_dict():
        out := {}
        for p in self.items():
            out[p[0]] = p[1]
        return out

    func copy():
        a := Attributes()
        for e in self.entries:
            v := e[1]
            if type(v) == "list":
                v = v + []
            append(a.entries, [e[0], v])
        return a

    func clear():
        self.entries = []
        return self

    func size():
        return len(self.items())

    func is_empty():
        return self.size() == 0

    func __len__():
        return self.size()

    func __contains__(name):
        return self.has(name)

    func __getitem__(name):
        v := self.get_text(name)
        if v == null:
            raise("KeyError", "Attributes : attribut absent « " + str(name) + " »")
        return v

    func __setitem__(name, value):
        self.set(name, value)

    # ---------------------------------------------------------------- id, class

    func id():
        return self.get_text("id")

    func classes():
        return _av.split_tokens(self.get_text("class", ""))

    func has_class(name):
        return name in self.classes()

    func add_class(name):
        cs := self.classes()
        for n in _av.split_tokens(name):
            if not (n in cs):
                append(cs, n)
        self.set("class", cs)
        return self

    func remove_class(name):
        drop := _av.split_tokens(name)
        out := []
        for c in self.classes():
            if not (c in drop):
                append(out, c)
        if len(out) == 0:
            self.remove("class")
        else:
            self.set("class", out)
        return self

    # Ajoute ou retire ; on (true / false) force l'état. Renvoie l'état final.
    func toggle_class(name, on=null):
        want := on
        if want == null:
            want = not self.has_class(name)
        if want:
            self.add_class(name)
        else:
            self.remove_class(name)
        return want

    # ---------------------------------------------------------------- style

    func style():
        v := self.get("style")
        if v == null or v == false:
            return {}
        if type(v) == "dict":
            out := {}
            for k in keys(v):
                out[_s.replace(str(k), "_", "-")] = str(v[k])
            return out
        return _av.parse_style(str(v))

    func get_style(prop, fallback=null):
        st := self.style()
        k := _s.lower(_s.replace(prop, "_", "-"))
        if k in st:
            return st[k]
        return fallback

    # Fixe une propriété CSS (null la retire).
    func set_style(prop, value):
        st := self.style()
        k := _s.lower(_s.replace(prop, "_", "-"))
        if value == null:
            if k in st:
                del st[k]
        else:
            st[k] = str(value)
        if len(st) == 0:
            self.remove("style")
        else:
            self.set("style", st)
        return self

    # ---------------------------------------------------------------- data-*, aria-*

    func data(name, fallback=null):
        return self.get_text("data-" + _s.replace(name, "_", "-"), fallback)

    func set_data(name, value):
        return self.set("data-" + _s.replace(name, "_", "-"), value)

    # Tous les data-* : dict nom (sans « data- ») -> texte.
    func dataset():
        out := {}
        for p in self.items():
            if _s.starts_with(_s.lower(p[0]), "data-"):
                out[p[0][5:len(p[0])]] = p[1]
        return out

    func aria(name, fallback=null):
        return self.get_text("aria-" + name, fallback)

    func set_aria(name, value):
        v := value
        if value == true:
            v = "true"
        elif value == false:
            v = "false"
        return self.set("aria-" + name, v)

    # ---------------------------------------------------------------- rendu

    # Attributs rendus, chacun précédé d'une espace. sort : par nom (sortie déterministe).
    func render(sort=false):
        es := self.entries
        if sort:
            es = _sorted_entries(es)
        out := []
        for e in es:
            append(out, _av.render(e[0], e[1]))
        return _s.join("", out)

    func __str__():
        return self.render()

func _sorted_entries(entries):
    out := []
    for e in entries:
        append(out, e)
    i := 1
    while i < len(out):
        cur := out[i]
        j := i - 1
        while j >= 0 and _s.lower(out[j][0]) > _s.lower(cur[0]):
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = cur
        i += 1
    return out

func from_data(data):
    if data == null:
        return Attributes()
    if isinstance(data, Attributes):
        return data.copy()
    return Attributes(data)
