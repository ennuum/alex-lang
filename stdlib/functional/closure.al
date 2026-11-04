# ALEX STANDARD LIBRARY — functional.closure
#
# Outils bâtis sur les fermetures (fonctions qui capturent leurs variables par référence) : état privé,
# évaluation paresseuse, appels limités.
#
#   Box(v)                    cellule mutable partageable entre fermetures (get/set/update)
#   Lazy(f)                   valeur calculée au premier get(), puis mémorisée (reset() pour recalculer)
#   counter(start, step)      fonction qui rend start, start+step... à chaque appel
#   accumulator(init, f)      fonction acc(x) -> nouvel état
#   once(f)                   f n'est exécutée qu'au premier appel ; les suivants rendent le même résultat
#   before(n, f) / after(n, f)   f exécutée pendant les n premiers appels / à partir du n-ième
#   toggle(a, b)              alterne a, b, a, b...
#   generator(values)         fonction qui rend la valeur suivante, puis null
#
#   use functional.closure as cl
#   next_id := cl.counter(100)
#   print(next_id(), next_id())            # 100 101
#   cfg := cl.Lazy(() => charger_config())
#   print(cfg.is_evaluated())               # false
#   v := cfg.get()                          # chargé une seule fois
#   init := cl.once(initialiser)
#   init()                                  # exécute
#   init()                                  # ne fait rien (même résultat)
#   somme := cl.accumulator(0, (acc, x) => acc + x)
#   somme(5)
#   print(somme(3))                         # 8
#
# Erreurs : TypeError (fonction attendue).

from core use len, type
use functional.functional_errors as _e

class Box:
    func init(value=null):
        self.value = value

    func get():
        return self.value

    func set(value):
        old := self.value
        self.value = value
        return old

    func update(f):
        self.value = f(self.value)
        return self.value

    func __str__():
        return "Box(" + str(self.value) + ")"

class Lazy:
    func init(f):
        _e.need_fn("Lazy", f)
        self._f = f
        self._done = false
        self._value = null
        self._failed = null

    func get():
        if not self._done:
            self._value = self._f()
            self._done = true
        return self._value

    func is_evaluated():
        return self._done

    # Oublie la valeur : le prochain get() recalcule.
    func reset():
        self._done = false
        self._value = null

    # Valeur si déjà calculée, sinon default (sans déclencher le calcul).
    func peek(default=null):
        if self._done:
            return self._value
        return default

    func map(g):
        src := self
        return Lazy(() => g(src.get()))

    func __call__():
        return self.get()

    func __str__():
        if self._done:
            return "Lazy(" + str(self._value) + ")"
        return "Lazy(<non évaluée>)"

func lazy(f):
    return Lazy(f)

func box(value=null):
    return Box(value)

func counter(start=0, step=1):
    n := start - step
    func next_value():
        n = n + step
        return n
    return next_value

func accumulator(init, f):
    _e.need_fn("accumulator", f)
    state := init
    func acc(x):
        state = f(state, x)
        return state
    return acc

func once(f):
    _e.need_fn("once", f)
    done := false
    result := null
    func g(*args):
        if not done:
            done = true
            result = f(*args)
        return result
    return g

# f est appelée pour les n premiers appels ; ensuite, le dernier résultat est rendu.
func before(n, f):
    _e.need_fn("before", f)
    count := 0
    last := null
    func g(*args):
        if count < n:
            count = count + 1
            last = f(*args)
        return last
    return g

# f n'est appelée qu'à partir du n-ième appel (n >= 1) ; avant, null.
func after(n, f):
    _e.need_fn("after", f)
    count := 0
    func g(*args):
        count = count + 1
        if count >= n:
            return f(*args)
        return null
    return g

func toggle(a, b):
    state := true
    func g():
        v := b
        if state:
            v = a
        state = not state
        return v
    return g

# Rend values[0], values[1]... puis null (source pour iterator.from_function).
func generator(values):
    i := 0
    func next_value():
        if i >= len(values):
            return null
        v := values[i]
        i = i + 1
        return v
    return next_value

# Fonction qui compte ses appels : [g, compteur] où compteur() rend le nombre d'appels.
func counting(f):
    _e.need_fn("counting", f)
    calls := 0
    func g(*args):
        calls = calls + 1
        return f(*args)
    func count():
        return calls
    return [g, count]
