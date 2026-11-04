# ALEX STANDARD LIBRARY — builtins
#
# Fonctions et méthodes « de base » à la Python, disponibles SANS import dans tout module utilisateur
# (le compilateur ajoute implicitement `from builtins use ...` pour les noms que le module ne déclare pas
# lui-même, voir docs/PYTHONIC.md). Les modules de la stdlib ne reçoivent PAS cette injection.
#
#   fonctions : abs min max sum sorted reversed enumerate zip map filter range round divmod pow
#               chr ord int float bool list tuple dict
#               (len type hash all any viennent de `core`, str/print/isinstance sont des intrinsèques)
#   méthodes  : list  append extend insert pop remove index count sort reverse clear copy
#               dict  keys values items get set pop update setdefault copy clear
#               str   upper lower strip lstrip rstrip split join replace startswith endswith find count
#                     capitalize title isdigit isalpha isspace zfill ljust rjust center

from core use len, type, to_int, to_float, to_bool
use math
use _native_string as _s
use _native_collections as _c

# Copie d'un itérable quelconque (list/tuple/str/dict : opcode LIST_EXTEND ; objet itérable : protocole __getitem__).
func _to_list(xs):
    t := type(xs)
    if t == "list" or t == "tuple" or t == "str" or t == "dict":
        return [*xs]
    out := []
    for x in xs:
        __list_append(out, x)
    return out

# ---------------------------------------------------------------------------
# Tri (fusion stable, O(n log n))
# ---------------------------------------------------------------------------
func _msort(xs, key, rev):
    n := len(xs)
    if n <= 1:
        return [*xs]
    mid := n // 2
    a := _msort(xs[:mid], key, rev)
    b := _msort(xs[mid:], key, rev)
    na := len(a)
    nb := len(b)
    out := []
    i := 0
    j := 0
    while i < na and j < nb:
        take_b := false
        if key == null:
            if rev:
                take_b = a[i] < b[j]
            else:
                take_b = b[j] < a[i]
        else:
            if rev:
                take_b = key(a[i]) < key(b[j])
            else:
                take_b = key(b[j]) < key(a[i])
        if take_b:
            __list_append(out, b[j])
            j += 1
        else:
            __list_append(out, a[i])
            i += 1
    while i < na:
        __list_append(out, a[i])
        i += 1
    while j < nb:
        __list_append(out, b[j])
        j += 1
    return out

func sorted(xs, key=null, reverse=false):
    return _msort(_to_list(xs), key, reverse)

func reversed(xs):
    out := []
    i := len(xs) - 1
    while i >= 0:
        __list_append(out, xs[i])
        i -= 1
    return out

# ---------------------------------------------------------------------------
# Numériques
# ---------------------------------------------------------------------------
func abs(x):
    if x < 0:
        return 0 - x
    return x

func _extreme(args, want_max, name):
    items := args
    if len(args) == 1:
        items = _to_list(args[0])
    if len(items) == 0:
        raise("ValueError", name + "() : séquence vide")
    best := items[0]
    for x in items[1:]:
        if want_max:
            if x > best:
                best = x
        else:
            if x < best:
                best = x
    return best

func min(*args):
    return _extreme(args, false, "min")

func max(*args):
    return _extreme(args, true, "max")

func sum(xs, start=0):
    total := start
    for x in xs:
        total = total + x
    return total

func round(x, ndigits=null):
    if ndigits == null:
        return math.round(x)
    scale := 1.0
    k := 0
    while k < ndigits:
        scale = scale * 10.0
        k += 1
    return math.round(x * scale) / scale

func divmod(a, b):
    return (a // b, a % b)

func pow(base, exponent, modulo=null):
    if modulo == null:
        return base ** exponent
    result := 1
    b := base % modulo
    e := exponent
    while e > 0:
        if e % 2 == 1:
            result = (result * b) % modulo
        b = (b * b) % modulo
        e = e // 2
    return result

func chr(code):
    return _s.chr(code)

func ord(c):
    return _s.ord(c)

# ---------------------------------------------------------------------------
# Conversions / constructeurs
# ---------------------------------------------------------------------------
func int(x):
    return to_int(x)

func float(x):
    return to_float(x)

func bool(x):
    return to_bool(x)

func list(xs=null):
    if xs == null:
        return []
    return _to_list(xs)

func tuple(xs=null):
    if xs == null:
        return (*[],)
    return (*_to_list(xs),)

func dict(pairs=null):
    out := {}
    if pairs == null:
        return out
    if type(pairs) == "dict":
        return {**pairs}
    for p in pairs:
        out[p[0]] = p[1]
    return out

# ---------------------------------------------------------------------------
# Ensembles : set([1, 2]) ou le littéral {1, 2} ; opérateurs | & - ^ <= >= in len for.
# ---------------------------------------------------------------------------
class set:
    func init(items=null):
        self.d = {}
        self.cache = null
        if items != null:
            for x in items:
                self.d[x] = true

    func _keys():
        if self.cache == null:
            self.cache = _c.keys(self.d)
        return self.cache

    func add(x):
        self.d[x] = true
        self.cache = null

    func discard(x):
        if x in self.d:
            del self.d[x]
            self.cache = null

    func remove(x):
        if not (x in self.d):
            raise("KeyError", "remove() : élément absent de l'ensemble")
        del self.d[x]
        self.cache = null

    func pop():
        ks := self._keys()
        if len(ks) == 0:
            raise("KeyError", "pop() sur un ensemble vide")
        v := ks[0]
        del self.d[v]
        self.cache = null
        return v

    func clear():
        self.d = {}
        self.cache = null

    func copy():
        return set(self.d)

    func update(other):
        for x in other:
            self.d[x] = true
        self.cache = null

    func union(other):
        r := set(self.d)
        r.update(other)
        return r

    func intersection(other):
        r := set()
        for x in self.d:
            if x in other:
                r.add(x)
        return r

    func difference(other):
        r := set()
        for x in self.d:
            if not (x in other):
                r.add(x)
        return r

    func symmetric_difference(other):
        r := self.difference(other)
        for x in other:
            if not (x in self.d):
                r.add(x)
        return r

    func issubset(other):
        for x in self.d:
            if not (x in other):
                return false
        return true

    func issuperset(other):
        for x in other:
            if not (x in self.d):
                return false
        return true

    func isdisjoint(other):
        for x in self.d:
            if x in other:
                return false
        return true

    func __contains__(x):
        return x in self.d

    func __len__():
        return len(self.d)

    func __getitem__(i):
        ks := self._keys()
        if i < 0 or i >= len(ks):
            raise("IndexError", "index hors limites")
        return ks[i]

    func __str__():
        if len(self.d) == 0:
            return "set()"
        parts := []
        for x in self._keys():
            __list_append(parts, str(x))
        return "{" + _s.join(", ", parts) + "}"

    func __eq__(o):
        if not isinstance(o, set):
            return false
        return len(self.d) == len(o.d) and self.issubset(o)

    func __or__(o):
        return self.union(o)

    func __and__(o):
        return self.intersection(o)

    func __sub__(o):
        return self.difference(o)

    func __xor__(o):
        return self.symmetric_difference(o)

    func __le__(o):
        return self.issubset(o)

    func __ge__(o):
        return self.issuperset(o)

    func __lt__(o):
        return len(self.d) < len(o.d) and self.issubset(o)

    func __gt__(o):
        return len(self.d) > len(o.d) and self.issuperset(o)

# Cible du littéral {a, b} (nom indépendant de `set`, que le programme peut redéfinir).
func __make_set(items):
    return set(items)

# ---------------------------------------------------------------------------
# Itération
# ---------------------------------------------------------------------------
func range(a, b=null, step=1):
    start := a
    stop := b
    if b == null:
        start = 0
        stop = a
    if step == 0:
        raise("ValueError", "range() : le pas ne peut pas être nul")
    out := []
    i := start
    if step > 0:
        while i < stop:
            __list_append(out, i)
            i += step
    else:
        while i > stop:
            __list_append(out, i)
            i += step
    return out

func enumerate(xs, start=0):
    out := []
    i := start
    for x in xs:
        __list_append(out, (i, x))
        i += 1
    return out

func zip(*seqs):
    if len(seqs) == 0:
        return []
    n := len(seqs[0])
    for s in seqs:
        if len(s) < n:
            n = len(s)
    out := []
    i := 0
    while i < n:
        row := []
        for s in seqs:
            __list_append(row, s[i])
        __list_append(out, (*row,))
        i += 1
    return out

func map(f, xs):
    out := []
    for x in xs:
        __list_append(out, f(x))
    return out

func filter(f, xs):
    out := []
    for x in xs:
        if f == null:
            if x:
                __list_append(out, x)
        elif f(x):
            __list_append(out, x)
    return out

# ---------------------------------------------------------------------------
# Méthodes de list
# ---------------------------------------------------------------------------
extend list:
    func append(x):
        __list_append(self, x)
    func extend(xs):
        for x in _to_list(xs):
            __list_append(self, x)
    func insert(i, x):
        __list_insert(self, i, x)
    func pop(i=null):
        if len(self) == 0:
            raise("IndexError", "pop() sur une liste vide")
        if i == null:
            i = len(self) - 1
        return __list_remove_at(self, i)
    func remove(x):
        i := 0
        n := len(self)
        while i < n:
            if self[i] == x:
                __list_remove_at(self, i)
                return null
            i += 1
        raise("ValueError", "remove() : valeur absente de la liste")
    func index(x):
        i := 0
        n := len(self)
        while i < n:
            if self[i] == x:
                return i
            i += 1
        raise("ValueError", "index() : valeur absente de la liste")
    func count(x):
        c := 0
        for y in self:
            if y == x:
                c += 1
        return c
    func sort(key=null, reverse=false):
        r := _msort([*self], key, reverse)
        i := 0
        n := len(r)
        while i < n:
            self[i] = r[i]
            i += 1
    func reverse():
        r := reversed(self)
        i := 0
        n := len(r)
        while i < n:
            self[i] = r[i]
            i += 1
    func clear():
        __list_clear(self)
    func copy():
        return [*self]

# ---------------------------------------------------------------------------
# Méthodes de dict
# ---------------------------------------------------------------------------
extend dict:
    func keys():
        return _c.keys(self)
    func values():
        return _c.values(self)
    func items():
        return _c.items(self)
    func get(key, default=null):
        if _c.contains_key(self, key):
            return self[key]
        return default
    func set(key, value):
        self[key] = value
    func pop(key, default=null):
        if _c.contains_key(self, key):
            v := self[key]
            del self[key]
            return v
        return default
    func update(other):
        for k in other:
            self[k] = other[k]
    func setdefault(key, default=null):
        if not _c.contains_key(self, key):
            self[key] = default
        return self[key]
    func copy():
        return {**self}
    func clear():
        for k in _c.keys(self):
            del self[k]

# ---------------------------------------------------------------------------
# Méthodes de str
# ---------------------------------------------------------------------------
extend str:
    func upper():
        return _s.upper(self)
    func lower():
        return _s.lower(self)
    func capitalize():
        return _s.capitalize(self)
    func title():
        return _s.title(self)
    func strip():
        return _s.strip(self)
    func lstrip():
        i := 0
        n := len(self)
        while i < n and self[i] in " \t\r\n":
            i += 1
        return _s.slice(self, i, null, 1)
    func rstrip():
        n := len(self)
        while n > 0 and self[n - 1] in " \t\r\n":
            n -= 1
        return _s.slice(self, 0, n, 1)
    func split(sep=null):
        if sep == null:
            out := []
            for part in _s.split(_s.strip(self), " "):
                if len(part) > 0:
                    __list_append(out, part)
            return out
        return _s.split(self, sep)
    func join(values):
        parts := []
        for v in values:
            __list_append(parts, str(v))
        return _s.join(self, parts)
    func replace(old, new):
        return _s.replace(self, old, new)
    func startswith(prefix):
        return _s.starts_with(self, prefix)
    func endswith(suffix):
        return _s.ends_with(self, suffix)
    func find(sub):
        return _s.find(self, sub)
    func count(sub):
        return _s.count(self, sub)
    func isdigit():
        if len(self) == 0:
            return false
        for ch in self:
            if not (ch in "0123456789"):
                return false
        return true
    func isalpha():
        if len(self) == 0:
            return false
        for ch in self:
            o := _s.ord(ch)
            if not ((o >= 65 and o <= 90) or (o >= 97 and o <= 122) or o > 191):
                return false
        return true
    func isspace():
        if len(self) == 0:
            return false
        for ch in self:
            if not (ch in " \t\r\n"):
                return false
        return true
    func zfill(width):
        s := self
        while len(s) < width:
            s = "0" + s
        return s
    func ljust(width, fill=" "):
        s := self
        while len(s) < width:
            s = s + fill
        return s
    func rjust(width, fill=" "):
        s := self
        while len(s) < width:
            s = fill + s
        return s
    func center(width, fill=" "):
        s := self
        left := false
        while len(s) < width:
            if left:
                s = fill + s
            else:
                s = s + fill
            left = not left
        return s
