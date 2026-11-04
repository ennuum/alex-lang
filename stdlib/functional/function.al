# ALEX STANDARD LIBRARY — functional.function
#
# Fonctions comme valeurs : introspection (nom, arité) et objet Function enveloppant une fonction pour la
# composer, la décorer et la nommer, tout en restant appelable comme une fonction ordinaire (f(x)).
#
#   use functional.function as fn
#   print(fn.arity(len), fn.name_of(print_line))      # [1, 1]  print_line
#   double := fn.Function((x) => x * 2, "double")
#   inc := fn.Function((x) => x + 1, "inc")
#   f := double.then(inc)                              # inc(double(x))
#   print(f(5), f.name)                                # 11  double>>inc
#   moins := fn.Function((a, b) => a - b)
#   print(moins.flip()(1, 10), moins.partial(10)(3))   # 9 7
#   print(fn.Function((a, b) => a - b).apply([7, 2]))  # 5
#   comptee := fn.Function(calcul).counted()
#   comptee(1)
#   print(comptee.calls)                               # 1
#
# Erreurs : TypeError (fonction attendue), ArgumentError (arité).

from core use len, type
from collections use append
use _native_reflect as _r
use functional.functional_errors as _e

# [min, max] d'arguments acceptés (max très grand : variadique) ; null si inconnu (fonction native).
func arity(f):
    _e.need_fn("function.arity", f)
    return _r.function_arity(f)

# Nom lisible de la fonction (« <lambda> » pour une lambda).
func name_of(f):
    _e.need_fn("function.name_of", f)
    n := _r.function_name(f)
    # Nom qualifié « $mod...::nom », « Type#méthode », « nom@l:c#n » -> partie lisible.
    q := _rfind(n, "::")
    if q >= 0:
        n = _slice(n, q + 2)
    at := _find(n, "@")
    if at == 0:
        return "<lambda>"
    if at > 0:
        n = _slice_to(n, at)
    if n == "<lambda>" or n == "":
        return "<lambda>"
    return _replace_hash(n)

func _find(s, sub):
    i := 0
    while i + len(sub) <= len(s):
        if s[i:i + len(sub)] == sub:
            return i
        i += 1
    return -1

func _rfind(s, sub):
    i := len(s) - len(sub)
    while i >= 0:
        if s[i:i + len(sub)] == sub:
            return i
        i -= 1
    return -1

func _slice(s, a):
    return s[a:]

func _slice_to(s, b):
    return s[:b]

func _replace_hash(n):
    h := _find(n, "#")
    if h < 0:
        return n
    return n[:h] + "." + n[h + 1:]

func is_function(v):
    return type(v) == "function" or isinstance(v, Function)

func identity(x):
    return x

func noop(*args):
    return null

# Fonction qui rend toujours value.
func constant(value):
    return (*args) => value

# f(*args) avec args en liste.
func apply(f, args):
    _e.need_fn("function.apply", f)
    return f(*args)

# Appelle f n fois : f(0), f(1)... ; renvoie la liste des résultats.
func times(n, f):
    out := []
    i := 0
    while i < n:
        append(out, f(i))
        i += 1
    return out

class Function:
    func init(f, name=null):
        if isinstance(f, Function):
            f = f.fn
        _e.need_fn("Function", f)
        self.fn = f
        self.name = name
        if self.name == null:
            self.name = name_of(f)
        self.calls = 0
        self._count = false

    func call(*args):
        if self._count:
            self.calls += 1
        return self.fn(*args)

    func __call__(*args):
        if self._count:
            self.calls += 1
        return self.fn(*args)

    func apply(args):
        return self.call(*args)

    func arity():
        return _r.function_arity(self.fn)

    # self puis g : g(self(x...)).
    func then(g):
        gname := _name(g)
        g = _unwrap(g)
        f := self.fn
        return Function((*args) => g(f(*args)), self.name + ">>" + gname)

    # g puis self : self(g(x...)).
    func compose(g):
        gname := _name(g)
        g = _unwrap(g)
        f := self.fn
        return Function((*args) => f(g(*args)), gname + ">>" + self.name)

    # Fixe les premiers arguments.
    func partial(*first):
        f := self.fn
        return Function((*rest) => f(*first, *rest), self.name)

    # Fixe les derniers arguments.
    func partial_right(*last):
        f := self.fn
        return Function((*rest) => f(*rest, *last), self.name)

    # Inverse les deux premiers arguments.
    func flip():
        f := self.fn
        return Function((a, b, *rest) => f(b, a, *rest), "flip(" + self.name + ")")

    # Négation d'un prédicat.
    func negate():
        f := self.fn
        return Function((*args) => not f(*args), "not(" + self.name + ")")

    # Mémorise les résultats (arguments hachables).
    func memoized():
        f := self.fn
        cache := {}
        func m(*args):
            k := (*args,)
            if k in cache:
                return cache[k]
            v := f(*args)
            cache[k] = v
            return v
        return Function(m, self.name)

    # Variante qui compte ses appels dans .calls.
    func counted():
        g := Function(self.fn, self.name)
        g._count = true
        return g

    func with_name(name):
        return Function(self.fn, name)

    func __str__():
        return "<Function " + self.name + ">"

func _name(g):
    if isinstance(g, Function):
        return g.name
    _e.need_fn("Function", g)
    return name_of(g)

func _unwrap(g):
    if isinstance(g, Function):
        return g.fn
    _e.need_fn("Function", g)
    return g

func wrap(f, name=null):
    return Function(f, name)
