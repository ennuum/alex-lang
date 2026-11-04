# ALEX STANDARD LIBRARY — future.shared_future
#
# SharedFuture : un résultat asynchrone calculé UNE fois et partagé par plusieurs consommateurs, qui l'attendent
# chacun quand ils veulent (avant ou après la fin du calcul). Paresseux s'il est créé à partir d'une fonction : le
# calcul démarre au premier get().
#
#   use future.shared_future as sf
#   config := sf.lazy(charger_config_async)          # rien ne démarre encore
#   a := await config.get()                           # démarre, attend
#   b := await config.get()                           # même résultat, sans recalcul
#   print(config.value_or(null))                      # sans attendre : la valeur si elle est prête
#
#   s := sf.SharedFuture(tache)                       # à partir d'un futur existant
#
# Si le calcul échoue, chaque get() relance la même erreur ; reset() permet de recommencer (lazy seulement).
#
# Erreurs : celles du calcul ; InvalidStateError (value() avant la fin).

from core use type
use asyncio

class SharedFuture:
    # source : un futur (ou une tâche), ou une fonction sans argument qui en renvoie un (paresseux).
    func init(source):
        self._fn = null
        self._future = null
        if type(source) == "function":
            self._fn = source
        elif asyncio.is_future(source):
            self._future = source
        else:
            raise("TypeError", "SharedFuture : futur ou fonction attendu")
        self._ok = null
        self._value = null
        self._etype = null
        self._emsg = null

    func started():
        return self._future != null

    func _start():
        if self._future == null:
            f := self._fn
            r := f()
            if not asyncio.is_future(r):
                fut := asyncio.future()
                asyncio.resolve(fut, r)
                r = fut
            self._future = r
        return self._future

    # Futur de la valeur (démarre le calcul si besoin). Plusieurs get() attendent le même calcul.
    func get():
        return _get(self)

    func done():
        return self._ok != null or (self._future != null and asyncio.done(self._future))

    # Valeur si le calcul a réussi (sans attendre) ; InvalidStateError sinon.
    func value():
        if self._ok == true:
            return self._value
        if self._future != null and asyncio.done(self._future) and not asyncio.failed(self._future) and not asyncio.cancelled(self._future):
            return asyncio.result(self._future)
        raise("InvalidStateError", "SharedFuture.value : pas (encore) de valeur")

    func value_or(default):
        try:
            return self.value()
        catch InvalidStateError as e:
            return default

    # Oublie le résultat (calcul paresseux uniquement) : le prochain get() recalcule.
    func reset():
        if self._fn == null:
            raise("InvalidStateError", "SharedFuture.reset : seulement pour un calcul paresseux (lazy)")
        self._future = null
        self._ok = null

async func _get(sf):
    if sf._ok == true:
        return sf._value
    if sf._ok == false:
        raise(sf._etype, sf._emsg)
    f := sf._start()
    try:
        v := await f
        sf._ok = true
        sf._value = v
        return v
    catch e:
        sf._ok = false
        sf._etype = e.type
        sf._emsg = e.message
        raise(e.type, e.message)

func lazy(fn):
    return SharedFuture(fn)

func share(f):
    return SharedFuture(f)
