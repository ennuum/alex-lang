# ALEX STANDARD LIBRARY — functional.compose
#
# Composition de fonctions :
#   compose(f, g, h)     x -> f(g(h(x)))       (de droite à gauche, notation mathématique)
#   pipe(f, g, h)        x -> h(g(f(x)))       (de gauche à droite, ordre de lecture)
#   Pipeline             construction pas à pas : Pipeline().then(f).then(g).run(x)
#   juxt(f, g)           x -> [f(x), g(x)]
#   converge(f, [g, h])  x -> f(g(x), h(x))
#   when / unless / if_else / cond    branchements fonctionnels
#   tap(f)               x -> (f(x) ; x)
#   iterate_until(f, pred, x)         applique f jusqu'à pred
#   fix_point(f, x)      applique f jusqu'à stabilité
#
#   use functional.compose as c
#   norm := c.pipe((s) => s.strip(), (s) => s.lower())
#   print(norm("  Bonjour "))                         # "bonjour"
#   moyenne := c.converge((s, n) => s / n, [(xs) => somme(xs), (xs) => len(xs)])
#   signe := c.cond([[(x) => x < 0, (x) => "négatif"], [(x) => x == 0, (x) => "nul"]], (x) => "positif")
#   p := c.Pipeline().then((x) => x + 1).then((x) => x * 2)
#   print(p.run(3), p.size())                         # 8 2
#
# Erreurs : TypeError (fonction attendue), FunctionalError (composition vide quand interdite).

from core use len, type
from collections use append
use functional.functional_errors as _e

func _apply_all(fns, x, reverse):
    v := x
    if reverse:
        i := len(fns) - 1
        while i >= 0:
            v = fns[i](v)
            i -= 1
    else:
        for f in fns:
            v = f(v)
    return v

# compose() sans argument : identité.
func compose(*fns):
    _e.need_fns("compose", fns)
    return (x) => _apply_all(fns, x, true)

func pipe(*fns):
    _e.need_fns("pipe", fns)
    return (x) => _apply_all(fns, x, false)

# Applique tout de suite : pipe_value(x, f, g) = g(f(x)).
func pipe_value(x, *fns):
    _e.need_fns("pipe_value", fns)
    return _apply_all(fns, x, false)

class Pipeline:
    func init(fns=null):
        self._fns = []
        if fns != null:
            for f in fns:
                _e.need_fn("Pipeline", f)
                append(self._fns, f)

    func then(f):
        _e.need_fn("Pipeline.then", f)
        p := Pipeline(self._fns)
        append(p._fns, f)
        return p

    # Étape exécutée pour son effet (journal...) : la valeur passe inchangée.
    func tap(f):
        return self.then(tap(f))

    func run(x):
        return _apply_all(self._fns, x, false)

    func __call__(x):
        return self.run(x)

    func size():
        return len(self._fns)

    func to_function():
        fns := self._fns
        return (x) => _apply_all(fns, x, false)

func juxt(*fns):
    _e.need_fns("juxt", fns)
    return (x) => [f(x) for f in fns]

func converge(f, branches):
    _e.need_fn("converge", f)
    _e.need_fns("converge", branches)
    return (x) => f(*[g(x) for g in branches])

func tap(f):
    _e.need_fn("tap", f)
    func g(x):
        f(x)
        return x
    return g

# pred(x) ? f(x) : x
func when(pred, f):
    return (x) => f(x) if pred(x) else x

func unless(pred, f):
    return (x) => x if pred(x) else f(x)

func if_else(pred, f, g):
    return (x) => f(x) if pred(x) else g(x)

# Première branche [pred, f] dont pred(x) est vrai ; sinon default(x) (ou null).
func cond(branches, default=null):
    func g(x):
        for b in branches:
            if b[0](x):
                return b[1](x)
        if default == null:
            return null
        return default(x)
    return g

# Applique f tant que pred(x) est faux (au plus max_steps fois).
func iterate_until(f, pred, x, max_steps=1000000):
    v := x
    k := 0
    while not pred(v):
        if k >= max_steps:
            _e.invalid("iterate_until", "pas de convergence après " + str(max_steps) + " étapes")
        v = f(v)
        k += 1
    return v

# Applique f jusqu'à ce que f(x) == x.
func fix_point(f, x, max_steps=10000):
    v := x
    k := 0
    while k < max_steps:
        n := f(v)
        if n == v:
            return v
        v = n
        k += 1
    _e.invalid("fix_point", "pas de point fixe après " + str(max_steps) + " étapes")

# Fonction à n arguments -> fonction d'une liste : spread(f)([a, b]) = f(a, b).
func spread(f):
    return (args) => f(*args)

# Inverse : fonction d'une liste -> fonction variadique.
func gather(f):
    return (*args) => f(args)
