# ALEX STANDARD LIBRARY — web.url.query_params
#
# QueryParams : paramètres de requête ordonnés et à valeurs multiples (équivalent de URLSearchParams). Les noms
# et valeurs sont DÉCODÉS ; to_string() produit la forme application/x-www-form-urlencoded.
#
#   use web.url.query_params as qp
#   p := qp.parse("q=chat+noir&tag=a&tag=b")
#   p.get("q")                    # chat noir
#   p.get_all("tag")              # ["a", "b"]
#   p.get("absent", "défaut")     # défaut
#   p.get_int("page", 1)          # 1
#   p.add("tag", "c")
#   p.set("q", "chien")           # remplace toutes les valeurs de « q »
#   p.remove("tag")
#   p.to_string()                 # q=chien
#   qp.from_data({"a": 1, "b": [2, 3]}).to_string()   # a=1&b=2&b=3
#
# Erreurs : TypeError, ValueError (get_int / get_float sur une valeur non numérique).

from core use len, type, to_int, to_float
from collections use append, keys
use string as _s
use web.url.form_url_encoding as _form

class QueryParams:
    func init(pairs=null):
        self.items_list = []
        if pairs != null:
            for p in pairs:
                append(self.items_list, (_form.value_to_str(p[0]), _form.value_to_str(p[1])))

    # Première valeur du nom, ou fallback.
    func get(name, fallback=null):
        for p in self.items_list:
            if p[0] == name:
                return p[1]
        return fallback

    # Toutes les valeurs du nom, dans l'ordre.
    func get_all(name):
        out := []
        for p in self.items_list:
            if p[0] == name:
                append(out, p[1])
        return out

    # Valeur entière ; fallback si absente ; ValueError si elle n'est pas un entier décimal.
    func get_int(name, fallback=null):
        v := self.get(name)
        if v == null or v == "":
            return fallback
        if not _is_int_text(v):
            raise("ValueError", "QueryParams.get_int : « " + name + " » n'est pas un entier ('" + v + "')")
        return to_int(v)

    func get_float(name, fallback=null):
        v := self.get(name)
        if v == null or v == "":
            return fallback
        try:
            return to_float(v)
        catch e:
            raise("ValueError", "QueryParams.get_float : « " + name + " » n'est pas un nombre ('" + v + "')")

    # Vrai pour « 1 », « true », « yes », « on » ou une valeur vide (« ?debug ») ; fallback si absent.
    func get_bool(name, fallback=false):
        v := self.get(name)
        if v == null:
            return fallback
        l := _s.lower(v)
        return l == "1" or l == "true" or l == "yes" or l == "on" or l == ""

    func has(name):
        for p in self.items_list:
            if p[0] == name:
                return true
        return false

    func add(name, value):
        append(self.items_list, (_form.value_to_str(name), _form.value_to_str(value)))
        return self

    # Remplace toutes les valeurs de name par value (à la place de la première occurrence ; ajouté sinon).
    # Une liste donne plusieurs valeurs.
    func set(name, value):
        n := _form.value_to_str(name)
        values := []
        if type(value) == "list" or type(value) == "tuple":
            for v in value:
                append(values, _form.value_to_str(v))
        else:
            append(values, _form.value_to_str(value))
        out := []
        placed := false
        for p in self.items_list:
            if p[0] == n:
                if not placed:
                    for v in values:
                        append(out, (n, v))
                    placed = true
            else:
                append(out, p)
        if not placed:
            for v in values:
                append(out, (n, v))
        self.items_list = out
        return self

    # Supprime toutes les valeurs du nom (ou seulement celles égales à value).
    func remove(name, value=null):
        out := []
        for p in self.items_list:
            if p[0] == name and (value == null or p[1] == _form.value_to_str(value)):
                continue
            append(out, p)
        self.items_list = out
        return self

    func clear():
        self.items_list = []
        return self

    # Noms distincts, dans l'ordre de première apparition.
    func names():
        out := []
        for p in self.items_list:
            if not (p[0] in out):
                append(out, p[0])
        return out

    # Paires (nom, valeur), dans l'ordre.
    func pairs():
        out := []
        for p in self.items_list:
            append(out, p)
        return out

    # Dict nom -> dernière valeur.
    func to_dict():
        out := {}
        for p in self.items_list:
            out[p[0]] = p[1]
        return out

    # Dict nom -> liste des valeurs.
    func to_multi_dict():
        out := {}
        for p in self.items_list:
            if p[0] in out:
                append(out[p[0]], p[1])
            else:
                out[p[0]] = [p[1]]
        return out

    # Tri stable par nom (comme URLSearchParams.sort) : utile pour une forme canonique.
    func sort():
        indexed := []
        i := 0
        for p in self.items_list:
            append(indexed, (p[0], i, p[1]))
            i += 1
        ordered := _stable_sort(indexed)
        out := []
        for t in ordered:
            append(out, (t[0], t[2]))
        self.items_list = out
        return self

    func copy():
        return QueryParams(self.items_list)

    # Ajoute les paires d'un dict, d'une liste de paires ou d'un autre QueryParams.
    func update(data):
        for p in _form.to_pairs(data):
            append(self.items_list, p)
        return self

    func is_empty():
        return len(self.items_list) == 0

    func size():
        return len(self.items_list)

    func __len__():
        return len(self.items_list)

    func __contains__(name):
        return self.has(name)

    func __getitem__(name):
        v := self.get(name)
        if v == null:
            raise("KeyError", "QueryParams : paramètre absent « " + str(name) + " »")
        return v

    func to_string():
        return _form.encode(self.items_list)

    func __str__():
        return self.to_string()

    func __eq__(other):
        return isinstance(other, QueryParams) and other.items_list == self.items_list

func _is_int_text(v):
    if len(v) == 0:
        return false
    i := 0
    if v[0] == '-' or v[0] == '+':
        i = 1
        if len(v) == 1:
            return false
    while i < len(v):
        if v[i] < '0' or v[i] > '9':
            return false
        i += 1
    return true

# QueryParams depuis une chaîne de requête (« a=1&b=2 », « ? » initial accepté).
func parse(text):
    return QueryParams(_form.decode(text))

# QueryParams depuis un dict (listes = valeurs multiples), une liste de paires ou un QueryParams.
func from_data(data):
    if isinstance(data, QueryParams):
        return data.copy()
    return QueryParams(_form.to_pairs(data))

func _stable_sort(items):
    out := []
    for x in items:
        append(out, x)
    n := len(out)
    i := 1
    while i < n:
        cur := out[i]
        j := i - 1
        while j >= 0 and (out[j][0] > cur[0] or (out[j][0] == cur[0] and out[j][1] > cur[1])):
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = cur
        i += 1
    return out
