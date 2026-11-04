# ALEX STANDARD LIBRARY — collections.hash_map
#
# HashMap : table associative à adressage par compartiments, ORDONNÉE par insertion. Contrairement au dict
# natif, elle accepte TOUTE clé, y compris des instances : une instance définissant hash_code() et __eq__ est
# comparée par valeur, sinon par identité. Recherche, insertion et suppression en O(1) en moyenne ;
# redimensionnement automatique (facteur de charge 0,75).
#
#   use collections.hash_map as hm
#   m := hm.HashMap()
#   m.put("a", 1)
#   m["b"] = 2                         # équivalent de put
#   print(m.get("a"), m["b"], m.get("z", 0), m.size())    # 1 2 0 2
#   m.compute("a", (k, v) => v + 10)   # a -> 11
#   m.merge("c", 1, (old, new) => old + new)
#   for k in m.keys():
#       print(k, m[k])
#   m.remove("a")
#
# `for k in m` n'est PAS une itération sur les clés (m[0] cherche la clé 0) : utiliser keys(), values()
# ou items().
#
# Erreurs : KeyError (m[k] / get_or_raise sur clé absente), TypeError (dict comme clé).

from core use len, type
from collections use append
from collections.list use Collection
use collections.collection_errors as _e
use collections._util as _u

const _TOMB := "\u0000<supprimé>"

class HashMap implements Collection:
    func init(entries=null, capacity=16):
        cap := 8
        while cap < capacity:
            cap = cap * 2
        self._buckets = [[] for _i in 0..cap]
        self._keys = []        # ordre d'insertion (cases supprimées : marque + vivant = false)
        self._vals = []
        self._alive = []
        self._hashes = []
        self._n = 0
        self._dead = 0
        if entries != null:
            self.put_all(entries)

    func _find(key, h):
        b := self._buckets[h % len(self._buckets)]
        for slot in b:
            if self._hashes[slot] == h and self._alive[slot] and self._keys[slot] == key:
                return slot
        return -1

    func _hash(key):
        h := _u.hash_of(key)
        if h < 0:
            h = -h
        return h

    func _rehash(cap):
        self._buckets = [[] for _i in 0..cap]
        nk := []
        nv := []
        na := []
        nh := []
        i := 0
        while i < len(self._keys):
            if self._alive[i]:
                slot := len(nk)
                append(nk, self._keys[i])
                append(nv, self._vals[i])
                append(na, true)
                append(nh, self._hashes[i])
                append(self._buckets[self._hashes[i] % cap], slot)
            i += 1
        self._keys = nk
        self._vals = nv
        self._alive = na
        self._hashes = nh
        self._dead = 0

    func size():
        return self._n

    func is_empty():
        return self._n == 0

    # Associe value à key ; renvoie l'ancienne valeur (null si la clé était absente).
    func put(key, value):
        h := self._hash(key)
        slot := self._find(key, h)
        if slot >= 0:
            old := self._vals[slot]
            self._vals[slot] = value
            return old
        if (self._n + 1) * 4 > len(self._buckets) * 3:
            self._rehash(len(self._buckets) * 2)
        slot = len(self._keys)
        append(self._keys, key)
        append(self._vals, value)
        append(self._alive, true)
        append(self._hashes, h)
        append(self._buckets[h % len(self._buckets)], slot)
        self._n += 1
        return null

    # N'ajoute que si la clé est absente ; renvoie la valeur en place.
    func put_if_absent(key, value):
        h := self._hash(key)
        slot := self._find(key, h)
        if slot >= 0:
            return self._vals[slot]
        self.put(key, value)
        return value

    # entries : dict, HashMap, ou liste de paires [clé, valeur].
    func put_all(entries):
        t := type(entries)
        if t == "dict":
            for k in entries:
                self.put(k, entries[k])
        elif isinstance(entries, HashMap):
            for p in entries.items():
                self.put(p[0], p[1])
        else:
            for p in _u.to_list(entries, "HashMap.put_all"):
                self.put(p[0], p[1])

    func get(key, default=null):
        slot := self._find(key, self._hash(key))
        if slot < 0:
            return default
        return self._vals[slot]

    func get_or_raise(key):
        slot := self._find(key, self._hash(key))
        if slot < 0:
            _e.missing_key("HashMap.get", key)
        return self._vals[slot]

    func contains_key(key):
        return self._find(key, self._hash(key)) >= 0

    func contains_value(value):
        i := 0
        while i < len(self._keys):
            if self._alive[i] and self._vals[i] == value:
                return true
            i += 1
        return false

    # Collection.contains : présence de la CLÉ.
    func contains(key):
        return self.contains_key(key)

    # Retire key ; renvoie sa valeur (default si absente).
    func remove(key, default=null):
        h := self._hash(key)
        slot := self._find(key, h)
        if slot < 0:
            return default
        b := self._buckets[h % len(self._buckets)]
        nb := []
        for s in b:
            if s != slot:
                append(nb, s)
        self._buckets[h % len(self._buckets)] = nb
        v := self._vals[slot]
        self._alive[slot] = false
        self._keys[slot] = _TOMB
        self._vals[slot] = null
        self._n -= 1
        self._dead += 1
        if self._dead > 32 and self._dead > self._n:
            self._rehash(len(self._buckets))
        return v

    # f(clé, ancienne valeur ou null) -> nouvelle valeur ; null retire la clé.
    func compute(key, f):
        old := self.get(key)
        v := f(key, old)
        if v == null:
            self.remove(key)
        else:
            self.put(key, v)
        return v

    func compute_if_absent(key, f):
        slot := self._find(key, self._hash(key))
        if slot >= 0:
            return self._vals[slot]
        v := f(key)
        if v != null:
            self.put(key, v)
        return v

    func compute_if_present(key, f):
        slot := self._find(key, self._hash(key))
        if slot < 0:
            return null
        return self.compute(key, f)

    # Absente : put(key, value) ; présente : f(ancienne, value) (null retire la clé).
    func merge(key, value, f):
        slot := self._find(key, self._hash(key))
        if slot < 0:
            self.put(key, value)
            return value
        v := f(self._vals[slot], value)
        if v == null:
            self.remove(key)
        else:
            self._vals[slot] = v
        return v

    func keys():
        out := []
        i := 0
        while i < len(self._keys):
            if self._alive[i]:
                append(out, self._keys[i])
            i += 1
        return out

    func values():
        out := []
        i := 0
        while i < len(self._keys):
            if self._alive[i]:
                append(out, self._vals[i])
            i += 1
        return out

    # Paires [clé, valeur] dans l'ordre d'insertion.
    func items():
        out := []
        i := 0
        while i < len(self._keys):
            if self._alive[i]:
                append(out, [self._keys[i], self._vals[i]])
            i += 1
        return out

    func for_each(f):
        for p in self.items():
            f(p[0], p[1])

    func filter(pred):
        out := HashMap()
        for p in self.items():
            if pred(p[0], p[1]):
                out.put(p[0], p[1])
        return out

    func map_values(f):
        out := HashMap()
        for p in self.items():
            out.put(p[0], f(p[1]))
        return out

    func clear():
        self._buckets = [[] for _i in 0..8]
        self._keys = []
        self._vals = []
        self._alive = []
        self._hashes = []
        self._n = 0
        self._dead = 0

    # Conversion en dict natif (clés hachables seulement).
    func to_dict():
        d := {}
        for p in self.items():
            d[p[0]] = p[1]
        return d

    # Collection.to_list : les paires [clé, valeur].
    func to_list():
        return self.items()

    func copy():
        return HashMap(self.items())

    # Taux de remplissage des compartiments et longueur de la plus longue chaîne (diagnostic).
    func stats():
        longest := 0
        used := 0
        for b in self._buckets:
            if len(b) > 0:
                used += 1
            if len(b) > longest:
                longest = len(b)
        return {"size": self._n, "buckets": len(self._buckets), "used_buckets": used, "longest_chain": longest,
                "load_factor": self._n / len(self._buckets)}

    func __eq__(other):
        if not isinstance(other, HashMap) or other.size() != self._n:
            return false
        for p in self.items():
            if not other.contains_key(p[0]) or not (other.get(p[0]) == p[1]):
                return false
        return true

    func __len__():
        return self._n

    func __contains__(key):
        return self.contains_key(key)

    func __getitem__(key):
        return self.get_or_raise(key)

    func __setitem__(key, value):
        self.put(key, value)

    func __str__():
        parts := []
        for p in self.items():
            append(parts, _u.show(p[0]) + ": " + _u.show(p[1]))
        out := "HashMap{"
        i := 0
        while i < len(parts):
            if i > 0:
                out += ", "
            out += parts[i]
            i += 1
        return out + "}"

func of(*pairs):
    return HashMap(pairs)

func from_dict(d):
    return HashMap(d)

# Regroupe items par key(x) : HashMap clé -> liste.
func group_by(items, key):
    m := HashMap()
    for x in _u.to_list(items, "hash_map.group_by"):
        k := key(x)
        g := m.get(k)
        if g == null:
            g = []
            m.put(k, g)
        append(g, x)
    return m

# Nombre d'occurrences de chaque élément.
func counter(items):
    m := HashMap()
    for x in _u.to_list(items, "hash_map.counter"):
        m.put(x, m.get(x, 0) + 1)
    return m
