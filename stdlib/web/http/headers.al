# ALEX STANDARD LIBRARY — web.http.headers
#
# Headers : collection ordonnée d'en-têtes HTTP, insensible à la casse des noms, à valeurs multiples. L'ordre
# d'insertion et l'écriture des noms sont conservés (un mandataire retransmet ce qu'il a reçu) ; chaque nom et
# chaque valeur sont validés à l'ajout (aucun CR/LF : pas d'injection d'en-têtes possible).
#
#   use web.http.headers as hd
#   h := hd.Headers({"Content-Type": "text/html", "X-Ids": ["1", "2"]})
#   h.add("Set-Cookie", "a=1")
#   h.add("Set-Cookie", "b=2")
#   h.get("content-type")             # text/html
#   h.get_all("set-cookie")           # ["a=1", "b=2"]
#   h.get_list("x-ids")               # ["1", "2"]
#   h.set("Content-Length", 42)       # remplace ; les nombres sont convertis
#   h.get_int("content-length")       # 42
#   h.has_token("Connection", "close")
#   h.to_wire()                       # "Content-Type: text/html\r\n..."
#   h.redacted()                      # copie avec Authorization, Cookie... masqués
#
# Erreurs : HttpHeaderError (nom ou valeur invalide), TypeError, ValueError (get_int sur une valeur non entière).

from core use len, type
from collections use append, keys
use string as _s
use web.http.http_errors as _err
use web.http.header_name as _hn
use web.http.header_value as _hv

class Headers:
    # data : dict (une liste = plusieurs valeurs), liste de paires, autre Headers, ou null.
    func init(data=null):
        self.entries = []     # [nom tel qu'écrit, valeur, nom en minuscules]
        if data != null:
            self.update(data)

    func _check(name, value):
        _hn.check(name)
        return _hv.to_text(value, name)

    # Ajoute une valeur (les valeurs existantes du nom sont gardées).
    func add(name, value):
        v := self._check(name, value)
        append(self.entries, [name, v, _s.lower(name)])
        return self

    # Remplace toutes les valeurs du nom (à la place de la première occurrence). Une liste donne plusieurs valeurs ;
    # null supprime l'en-tête.
    func set(name, value):
        if value == null:
            return self.remove(name)
        values := []
        if type(value) == "list" or type(value) == "tuple":
            for v in value:
                append(values, self._check(name, v))
        else:
            append(values, self._check(name, value))
        k := _s.lower(name)
        if len(values) == 1:
            # cas courant : au plus une entrée de ce nom, remplacée sur place (sans recopier la liste)
            found := -1
            n := 0
            i := 0
            for e in self.entries:
                if e[2] == k:
                    n += 1
                    if found < 0:
                        found = i
                i += 1
            if n == 0:
                append(self.entries, [name, values[0], k])
                return self
            if n == 1:
                self.entries[found] = [name, values[0], k]
                return self
        out := []
        placed := false
        for e in self.entries:
            if e[2] == k:
                if not placed:
                    for v in values:
                        append(out, [name, v, k])
                    placed = true
            else:
                append(out, e)
        if not placed:
            for v in values:
                append(out, [name, v, k])
        self.entries = out
        return self

    # Fixe la valeur seulement si le nom est absent.
    func set_default(name, value):
        if not self.has(name):
            self.set(name, value)
        return self

    # Première valeur (ou toutes, combinées par « , » si combine) ; fallback si absent.
    func get(name, fallback=null, combine=false):
        k := _s.lower(name)
        if combine:
            vals := self.get_all(name)
            if len(vals) == 0:
                return fallback
            return _s.join(", ", vals)
        for e in self.entries:
            if e[2] == k:
                return e[1]
        return fallback

    # Dernière valeur (utile quand un mandataire en ajoute une).
    func get_last(name, fallback=null):
        k := _s.lower(name)
        out := fallback
        for e in self.entries:
            if e[2] == k:
                out = e[1]
        return out

    func get_all(name):
        k := _s.lower(name)
        out := []
        for e in self.entries:
            if e[2] == k:
                append(out, e[1])
        return out

    # Éléments de liste de toutes les lignes du nom (« a, b » + « c » -> ["a", "b", "c"]).
    func get_list(name):
        out := []
        for v in self.get_all(name):
            for item in _hv.split_list(v):
                append(out, item)
        return out

    # Valeur entière (décimale, sans signe) ; fallback si absente ; ValueError si invalide.
    func get_int(name, fallback=null):
        v := self.get(name)
        if v == null:
            return fallback
        t := _hv.trim(v)
        if len(t) == 0:
            raise("ValueError", "Headers.get_int : « " + name + " » vide")
        n := 0
        for c in t:
            if c < '0' or c > '9':
                raise("ValueError", "Headers.get_int : « " + name + " » n'est pas un entier ('" + t + "')")
            n = n * 10 + (_s.ord(c) - 48)
        return n

    func has(name):
        k := _s.lower(name)
        for e in self.entries:
            if e[2] == k:
                return true
        return false

    # Vrai si une valeur de liste du nom vaut token (insensible à la casse) : has_token("Connection", "close").
    func has_token(name, token):
        for v in self.get_all(name):
            if _hv.list_contains(v, token):
                return true
        return false

    # Nombre de lignes portant ce nom.
    func count(name):
        return len(self.get_all(name))

    func remove(name):
        k := _s.lower(name)
        out := []
        for e in self.entries:
            if e[2] != k:
                append(out, e)
        self.entries = out
        return self

    func clear():
        self.entries = []
        return self

    # Ajoute le contenu d'un dict, d'une liste de paires ou d'un autre Headers (add, pas set).
    func update(data):
        if isinstance(data, Headers):
            for e in data.entries:
                append(self.entries, [e[0], e[1], e[2]])
            return self
        t := type(data)
        if t == "dict":
            for k in keys(data):
                v := data[k]
                if type(v) == "list" or type(v) == "tuple":
                    for x in v:
                        self.add(k, x)
                elif v != null:
                    self.add(k, v)
            return self
        if t == "list" or t == "tuple":
            for p in data:
                self.add(p[0], p[1])
            return self
        raise("TypeError", "Headers.update : dict, liste de paires ou Headers attendu (obtenu " + t + ")")

    # Remplace (set) chaque nom présent dans data.
    func replace_all(data):
        other := Headers(data)
        for n in other.names():
            self.set(n, other.get_all(n))
        return self

    # Noms distincts (écriture de la première occurrence), dans l'ordre.
    func names():
        out := []
        seen := []
        for e in self.entries:
            k := e[2]
            if not (k in seen):
                append(seen, k)
                append(out, e[0])
        return out

    # Paires (nom, valeur) dans l'ordre.
    func items():
        out := []
        for e in self.entries:
            append(out, (e[0], e[1]))
        return out

    # Dict nom en minuscules -> valeurs combinées par « , » (Set-Cookie : liste).
    func to_dict():
        out := {}
        for n in self.names():
            k := _s.lower(n)
            if _hn.is_combinable(k):
                out[k] = _s.join(", ", self.get_all(n))
            else:
                out[k] = self.get_all(n)
        return out

    func copy():
        h := Headers()
        for e in self.entries:
            append(h.entries, [e[0], e[1], e[2]])
        return h

    # Copie sans les en-têtes saut par saut (et ceux nommés dans Connection) : ce qu'un mandataire retransmet.
    func end_to_end():
        extra := []
        for t in self.get_list("connection"):
            append(extra, _s.lower(t))
        h := Headers()
        for e in self.entries:
            k := e[2]
            if not _hn.is_hop_by_hop(k) and not (k in extra):
                append(h.entries, [e[0], e[1], e[2]])
        return h

    # Copie aux valeurs sensibles masquées (journaux).
    func redacted(mask="***"):
        h := Headers()
        for e in self.entries:
            if _hn.is_sensitive(e[0]):
                append(h.entries, [e[0], mask, e[2]])
            else:
                append(h.entries, [e[0], e[1], e[2]])
        return h

    # Noms canoniques (« content-type » -> « Content-Type »).
    func canonicalize():
        for e in self.entries:
            e[0] = _hn.canonical(e[0])
        return self

    # Lignes d'en-têtes « Nom: valeur\r\n » (sans la ligne vide finale).
    func to_wire():
        out := []
        for e in self.entries:
            append(out, e[0] + ": " + e[1] + "\r\n")
        return _s.join("", out)

    # Taille en octets de la forme filaire.
    func wire_size():
        return _s.byte_len(self.to_wire())

    func size():
        return len(self.entries)

    func is_empty():
        return len(self.entries) == 0

    func __len__():
        return len(self.entries)

    func __contains__(name):
        return self.has(name)

    func __getitem__(name):
        v := self.get(name)
        if v == null:
            raise("KeyError", "Headers : en-tête absent « " + str(name) + " »")
        return v

    func __setitem__(name, value):
        self.set(name, value)

    func __str__():
        return self.to_wire()

    func __eq__(other):
        if not isinstance(other, Headers) or len(other.entries) != len(self.entries):
            return false
        i := 0
        while i < len(self.entries):
            a := self.entries[i]
            b := other.entries[i]
            if a[2] != b[2] or a[1] != b[1]:
                return false
            i += 1
        return true

func from_data(data):
    if isinstance(data, Headers):
        return data.copy()
    return Headers(data)

# Analyse des lignes « Nom: valeur » (séparées par CRLF ou LF, sans ligne de départ) ; HttpHeaderError si une
# ligne est mal formée. Les lignes repliées (obs-fold, « continuation » commençant par une espace) sont refusées
# (RFC 9112 §5.2) sauf si allow_obs_fold : elles sont alors jointes par une espace.
func parse_lines(text, allow_obs_fold=false):
    h := Headers()
    for raw in _s.split(_s.replace(text, "\r\n", "\n"), "\n"):
        if raw == "":
            continue
        if raw[0] == ' ' or raw[0] == '\t':
            if not allow_obs_fold or len(h.entries) == 0:
                _err.header_error("headers.parse_lines", "ligne d'en-tête repliée (obs-fold) refusée")
            last := h.entries[len(h.entries) - 1]
            last[1] = last[1] + " " + _hv.trim(raw)
            continue
        p := parse_line(raw)
        append(h.entries, [p[0], p[1], _s.lower(p[0])])
    return h

# Analyse une ligne « Nom: valeur » -> (nom, valeur sans espaces optionnels) ; HttpHeaderError si le nom est vide,
# invalide (espace avant « : » compris, RFC 9112 §5.1) ou si la valeur contient un caractère interdit.
func parse_line(line):
    fn := "headers.parse_line"
    colon := _s.find(line, ":")
    if colon <= 0:
        _err.header_error(fn, "ligne d'en-tête sans « : » ou sans nom '" + _hv.sanitize(line) + "'")
    name := line[0:colon]
    if not _hn.is_valid(name):
        _err.header_error(fn, "nom d'en-tête invalide '" + _hv.sanitize(name) + "'")
    value := _hv.trim(line[colon + 1:len(line)])
    if not _hv.is_valid(value):
        _err.header_error(fn, "caractère interdit dans la valeur de l'en-tête " + name)
    return (name, value)
