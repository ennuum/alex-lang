# ALEX STANDARD LIBRARY — coroutine.generator
#
# Générateurs : produire une suite de valeurs à la demande.
#
#   Generator(next_fn)        SYNCHRONE, sans async : next_fn() rend la valeur suivante, ou generator.STOP.
#                             Une fermeture garde l'état entre deux appels (les variables capturées sont
#                             partagées) ; c'est un iterator.Iterator : `for x in g`, map, filter, take...
#   unfold(seed, step)        step(état) -> [valeur, état suivant] ou null
#   AsyncGenerator(body)      sur une coroutine : le corps (async func) fait `await y.yield_(v)` ; on consomme
#                             avec `await g.next()` ou `await g.to_list()`.
#
#   use coroutine.generator as gen
#   func fibonacci():
#       a := 0
#       b := 1
#       func suivant():
#           v := a
#           a, b = b, a + b
#           return v
#       return gen.Generator(suivant)
#   print(fibonacci().take(10).to_list())         # [0, 1, 1, 2, 3, 5, 8, 13, 21, 34]
#   for x in gen.Generator(lecteur.read_line_or_stop):
#       traiter(x)
#
#   async func lignes(y, chemin):
#       for l in file.read_lines(chemin):
#           await y.yield_(l)
#   g := gen.AsyncGenerator(lignes, ["data.txt"])
#   while not g.exhausted():
#       l := await g.next()                       # StopCoroutine à la fin
#
# Erreurs : StopIteration (next() d'un Generator épuisé), StopCoroutine (AsyncGenerator épuisé), TypeError.

from core use type, len
from collections use append
use asyncio
from iterator._base use Iterator
use iterator as _it
from iterator use Iter
use coroutine.coroutine as _co
use coroutine.coroutine_errors as _e

# Marqueur de fin rendu par next_fn.
class _Stop:
    func init():
        self.tag = "STOP"

STOP := _Stop()

func is_stop(v):
    return isinstance(v, _Stop)

class Generator extends Iter:
    func init(next_fn):
        if type(next_fn) != "function":
            raise("TypeError", "Generator : fonction attendue (obtenu '" + type(next_fn) + "')")
        self._fn = next_fn
        self._stopped = false
        super.init(_GenSource(self))

class _GenSource extends Iterator:
    func init(owner):
        super.init()
        self._owner = owner

    func _fetch():
        if self._owner._stopped:
            return false
        v := self._owner._fn()
        if isinstance(v, _Stop):
            self._owner._stopped = true
            return false
        self._item = v
        return true

func generator(next_fn):
    return Generator(next_fn)

# step(état) -> [valeur, état suivant], ou null pour finir.
func unfold(seed, step):
    return _it.unfold(seed, step)

# Valeurs de items, une par appel, puis STOP (fermeture prête à l'emploi).
func from_list(items):
    i := 0
    func nxt():
        if i >= len(items):
            return STOP
        v := items[i]
        i = i + 1
        return v
    return Generator(nxt)

# Suite infinie start, f(start), f(f(start))...
func iterate(start, f):
    cur := start
    first := true
    func nxt():
        if first:
            first = false
            return cur
        cur = f(cur)
        return cur
    return Generator(nxt)

class AsyncGenerator:
    func init(body, args=null, name=null):
        self.co = _co.Coroutine(body, args, name)
        self._done = false
        self._peeked = false
        self._peek_value = null

    func exhausted():
        return self._done

    # Futur de la valeur suivante ; StopCoroutine quand le corps a terminé.
    func next():
        return _next(self)

    # Futur de la liste de toutes les valeurs restantes.
    func to_list():
        return _to_list(self)

    func close():
        self._done = true
        return self.co.close()

async func _advance(g):
    if g._done:
        raise(_e.STOP, "générateur épuisé")
    v := null
    if g.co.state() == "created":
        v = await g.co.resume()
    else:
        v = await g.co.resume(null)
    if g.co.is_finished():
        g._done = true
        raise(_e.STOP, "générateur épuisé")
    return v

async func _next(g):
    return await _advance(g)

async func _to_list(g):
    out := []
    while true:
        try:
            append(out, await _advance(g))
        catch StopCoroutine:
            return out

# Consomme un AsyncGenerator en appliquant f à chaque valeur ; futur du nombre de valeurs.
async func for_each(g, f):
    n := 0
    while true:
        try:
            f(await _advance(g))
            n += 1
        catch StopCoroutine:
            return n
