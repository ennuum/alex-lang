# ALEX STANDARD LIBRARY — iterator._base (interne ; public : iterator)
#
# Protocole commun : une sous-classe d'Iterator appelle super.init() puis redéfinit _fetch(), qui place
# l'élément suivant dans self._item et rend true, ou rend false quand c'est fini. Le reste (has_next,
# next, peek, consommateurs, __getitem__ pour `for`) est fourni ici.
#
# `for x in it` consomme l'itérateur (ALEX appelle it[0], it[1]... : chaque appel rend l'élément SUIVANT,
# l'indice est ignoré) ; une fin de parcours lève IndexError, qui termine la boucle.

from core use len, type
from collections use append
use iterator.iterator_errors as _e

class Iterator:
    func init():
        self._buffered = false
        self._buf = null
        self._done = false
        self._item = null
        self._count = 0

    # À redéfinir : true + self._item, ou false à la fin.
    func _fetch():
        return false

    func has_next():
        if self._buffered:
            return true
        if self._done:
            return false
        if self._fetch():
            self._buffered = true
            self._buf = self._item
            self._item = null
            return true
        self._done = true
        return false

    func next():
        if not self.has_next():
            _e.stop("Iterator.next")
        self._buffered = false
        v := self._buf
        self._buf = null
        self._count += 1
        return v

    # Suivant ou default, sans erreur.
    func next_or(default=null):
        if not self.has_next():
            return default
        return self.next()

    # Élément suivant sans le consommer.
    func peek(default=null):
        if not self.has_next():
            return default
        return self._buf

    # Nombre d'éléments déjà rendus.
    func position():
        return self._count

    func is_exhausted():
        return not self.has_next()

    # ---------------------------------------------------------------- consommateurs
    func to_list():
        out := []
        while self.has_next():
            append(out, self.next())
        return out

    # Au plus n éléments, en liste.
    func take_list(n):
        out := []
        while len(out) < n and self.has_next():
            append(out, self.next())
        return out

    func count():
        n := 0
        while self.has_next():
            self.next()
            n += 1
        return n

    func last(default=null):
        v := default
        while self.has_next():
            v = self.next()
        return v

    # n-ième élément restant (0 = suivant).
    func nth(n, default=null):
        _e.need_non_negative("Iterator.nth", n, "n")
        i := 0
        while self.has_next():
            v := self.next()
            if i == n:
                return v
            i += 1
        return default

    func for_each(f):
        while self.has_next():
            f(self.next())

    func reduce(f, init):
        acc := init
        while self.has_next():
            acc = f(acc, self.next())
        return acc

    func fold(init, f):
        return self.reduce(f, init)

    func sum(start=0):
        acc := start
        while self.has_next():
            acc = acc + self.next()
        return acc

    func product(start=1):
        acc := start
        while self.has_next():
            acc = acc * self.next()
        return acc

    func any(pred=null):
        while self.has_next():
            v := self.next()
            if pred == null:
                if v:
                    return true
            elif pred(v):
                return true
        return false

    func all(pred=null):
        while self.has_next():
            v := self.next()
            if pred == null:
                if not v:
                    return false
            elif not pred(v):
                return false
        return true

    func find(pred, default=null):
        while self.has_next():
            v := self.next()
            if pred(v):
                return v
        return default

    # Position (dans ce qui reste) du premier élément vérifiant pred ; -1 sinon.
    func find_index(pred):
        i := 0
        while self.has_next():
            if pred(self.next()):
                return i
            i += 1
        return -1

    func min(key=null, default=null):
        return self._extreme(key, default, false)

    func max(key=null, default=null):
        return self._extreme(key, default, true)

    func _extreme(key, default, want_max):
        if not self.has_next():
            return default
        best := self.next()
        bk := best
        if key != null:
            bk = key(best)
        while self.has_next():
            v := self.next()
            k := v
            if key != null:
                k = key(v)
            if (want_max and k > bk) or (not want_max and k < bk):
                best = v
                bk = k
        return best

    func join(sep=""):
        out := ""
        first := true
        while self.has_next():
            if not first:
                out += sep
            out += str(self.next())
            first = false
        return out

    # Dict à partir de paires [clé, valeur] (ou d'éléments et d'une fonction key -> clé, valeur = élément).
    func to_dict(key=null):
        d := {}
        while self.has_next():
            v := self.next()
            if key == null:
                d[v[0]] = v[1]
            else:
                d[key(v)] = v
        return d

    # [vrais, faux] selon pred.
    func partition(pred):
        yes := []
        no := []
        while self.has_next():
            v := self.next()
            if pred(v):
                append(yes, v)
            else:
                append(no, v)
        return [yes, no]

    func group_by(key):
        d := {}
        order := []
        while self.has_next():
            v := self.next()
            k := key(v)
            if not (k in d):
                d[k] = []
                append(order, k)
            append(d[k], v)
        return d

    # Égalité élément par élément avec un autre itérable (consomme les deux).
    func equals(other):
        o := from_iterable(other)
        while self.has_next():
            if not o.has_next():
                return false
            if not (self.next() == o.next()):
                return false
        return not o.has_next()

    func __getitem__(i):
        if not self.has_next():
            raise("IndexError", "itérateur épuisé")
        return self.next()

    func __str__():
        return "<itérateur>"

# ---------------------------------------------------------------- sources

class ListIterator extends Iterator:
    func init(items):
        super.init()
        self._items = items
        self._i = 0
        self._n = len(items)

    func _fetch():
        if self._i >= self._n:
            return false
        self._item = self._items[self._i]
        self._i += 1
        return true

    # Éléments restants.
    func remaining():
        n := self._n - self._i
        if self._buffered:
            n += 1
        return n

# Parcourt obj[0], obj[1]... jusqu'à IndexError (protocole séquence d'ALEX).
class IndexIterator extends Iterator:
    func init(obj):
        super.init()
        self._obj = obj
        self._i = 0

    func _fetch():
        try:
            self._item = self._obj[self._i]
        catch IndexError:
            return false
        self._i += 1
        return true

# Appelle f() jusqu'à ce qu'il rende sentinel (comparaison ==) ; sentinel null par défaut.
class FunctionIterator extends Iterator:
    func init(f, sentinel=null):
        super.init()
        _e.need_fn("iterator.from_function", f)
        self._f = f
        self._sentinel = sentinel

    func _fetch():
        v := self._f()
        if type(v) == type(self._sentinel) and v == self._sentinel:
            return false
        self._item = v
        return true

# Adapte n'importe quel itérable : liste, tuple, str (caractères), dict (clés), Iterator, objet doté de
# iterator() ou to_list(), ou indexable par position.
func from_iterable(x, fn="iterator"):
    t := type(x)
    if t == "list":
        return ListIterator(x)
    if t == "tuple" or t == "str":
        out := []
        for v in x:
            append(out, v)
        return ListIterator(out)
    if t == "dict":
        out := []
        for k in x:
            append(out, k)
        return ListIterator(out)
    if t == "instance":
        if isinstance(x, Iterator):
            return x
        try:
            return ListIterator(x.to_list())
        catch AttributeError:
            pass
        return IndexIterator(x)
    if t == "function":
        return FunctionIterator(x)
    _e.invalid(fn, "itérable attendu (obtenu '" + t + "')")
