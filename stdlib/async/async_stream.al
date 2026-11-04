# ALEX STANDARD LIBRARY — async.async_stream
#
# Flux ASYNCHRONES : une suite de valeurs qui arrivent au fil du temps (messages d'un canal, lignes, mesures
# périodiques...), transformée par des opérateurs paresseux, puis consommée.
#
#   use async.async_stream as st
#   s := st.from_channel(ch).filter((m) => m["niveau"] == "erreur").map((m) => m["texte"]).take(10)
#   for_each_res := await s.for_each((t) => print(t))
#   mesures := await st.interval(0.1, 5).map((i) => lire_capteur()).collect()     # 5 mesures, une par 0,1 s
#   total := await st.from_list([1, 2, 3]).reduce((acc, x) => acc + x, 0)
#   fusion := st.merge([flux_a, flux_b])          # valeurs des deux, dans l'ordre d'arrivée
#   lots := st.from_list(xs).batch(100)           # listes de 100
#
# Un flux se consomme UNE fois. Chaque opérateur renvoie un nouveau flux (rien ne s'exécute avant la
# consommation). next() renvoie un futur de [true, valeur] ou [false, null] à la fin.
#
# Les fonctions passées (map, filter...) peuvent être ordinaires ou async (leur futur est attendu).
#
# Erreurs : une erreur de la source ou d'une fonction traverse le flux jusqu'au consommateur.

from core use len, type
from collections use append
use asyncio
use channel as _ch

# Attend f sans relancer son erreur (elle sera relancée par l'await qui lira le résultat).
async func _settle(f):
    try:
        await f
    catch e:
        return null
    return null

async func _maybe(v):
    if asyncio.is_future(v):
        return await v
    return v

class AsyncStream:
    # pull : fonction sans argument renvoyant un futur de [true, valeur] | [false, null].
    func init(pull):
        self._pull = pull
        self._ended = false

    func next():
        p := self._pull
        return p()

    func map(fn):
        src := self
        async func pull():
            r := await src.next()
            if not r[0]:
                return r
            return [true, await _maybe(fn(r[1]))]
        return AsyncStream(pull)

    func filter(fn):
        src := self
        async func pull():
            while true:
                r := await src.next()
                if not r[0]:
                    return r
                if await _maybe(fn(r[1])):
                    return r
        return AsyncStream(pull)

    # Appelle fn(valeur) au passage, sans modifier le flux.
    func tap(fn):
        src := self
        async func pull():
            r := await src.next()
            if r[0]:
                await _maybe(fn(r[1]))
            return r
        return AsyncStream(pull)

    func take(n):
        src := self
        count := [0]
        async func pull():
            if count[0] >= n:
                return [false, null]
            count[0] += 1
            return await src.next()
        return AsyncStream(pull)

    func skip(n):
        src := self
        skipped := [false]
        async func pull():
            if not skipped[0]:
                skipped[0] = true
                k := 0
                while k < n:
                    r := await src.next()
                    if not r[0]:
                        return r
                    k += 1
            return await src.next()
        return AsyncStream(pull)

    func take_while(fn):
        src := self
        stopped := [false]
        async func pull():
            if stopped[0]:
                return [false, null]
            r := await src.next()
            if not r[0] or not await _maybe(fn(r[1])):
                stopped[0] = true
                return [false, null]
            return r
        return AsyncStream(pull)

    # Listes d'au plus size valeurs (la dernière peut être plus courte).
    func batch(size):
        src := self
        async func pull():
            out := []
            while len(out) < size:
                r := await src.next()
                if not r[0]:
                    break
                append(out, r[1])
            if len(out) == 0:
                return [false, null]
            return [true, out]
        return AsyncStream(pull)

    # (rang, valeur)
    func enumerate():
        src := self
        i := [0]
        async func pull():
            r := await src.next()
            if not r[0]:
                return r
            v := (i[0], r[1])
            i[0] += 1
            return [true, v]
        return AsyncStream(pull)

    # Les valeurs de self, puis celles de other.
    func chain(other):
        src := self
        first_done := [false]
        async func pull():
            if not first_done[0]:
                r := await src.next()
                if r[0]:
                    return r
                first_done[0] = true
            return await other.next()
        return AsyncStream(pull)

    # N'émet une valeur que si `seconds` se sont écoulées depuis la précédente émise (les autres sont ignorées).
    func throttle(seconds):
        src := self
        last := [null]
        async func pull():
            while true:
                r := await src.next()
                if not r[0]:
                    return r
                now := asyncio.now()
                if last[0] == null or now - last[0] >= seconds:
                    last[0] = now
                    return r
        return AsyncStream(pull)

    # ---- consommation (futurs) ----
    func collect():
        return _collect(self)

    func for_each(fn):
        return _for_each(self, fn)

    func reduce(fn, initial):
        return _reduce(self, fn, initial)

    # Première valeur (null si vide).
    func first():
        return _first(self)

    func count():
        return _reduce(self, (acc, x) => acc + 1, 0)

async func _collect(s):
    out := []
    while true:
        r := await s.next()
        if not r[0]:
            return out
        append(out, r[1])

async func _for_each(s, fn):
    n := 0
    while true:
        r := await s.next()
        if not r[0]:
            return n
        await _maybe(fn(r[1]))
        n += 1

async func _reduce(s, fn, acc):
    while true:
        r := await s.next()
        if not r[0]:
            return acc
        acc = await _maybe(fn(acc, r[1]))

async func _first(s):
    r := await s.next()
    if r[0]:
        return r[1]
    return null

# ---------------------------------------------------------------- sources

func from_list(items):
    data := [x for x in items]
    i := [0]
    async func pull():
        if i[0] >= len(data):
            return [false, null]
        v := data[i[0]]
        i[0] += 1
        return [true, v]
    return AsyncStream(pull)

func range(start, stop, step=1):
    cur := [start]
    async func pull():
        if (step > 0 and cur[0] >= stop) or (step < 0 and cur[0] <= stop):
            return [false, null]
        v := cur[0]
        cur[0] += step
        return [true, v]
    return AsyncStream(pull)

# Valeurs d'un canal (channel.Channel) jusqu'à sa fermeture.
func from_channel(ch):
    async func pull():
        try:
            return [true, await ch.recv()]
        catch ChannelClosedError as e:
            return [false, null]
    return AsyncStream(pull)

# 0, 1, 2... toutes les seconds secondes (count valeurs, null : sans fin).
func interval(seconds, count=null):
    i := [0]
    async func pull():
        if count != null and i[0] >= count:
            return [false, null]
        await asyncio.sleep(seconds)
        v := i[0]
        i[0] += 1
        return [true, v]
    return AsyncStream(pull)

# Flux alimenté par une async func producteur(emit) : `await emit(v)` envoie une valeur ; le flux finit quand le
# producteur se termine (ou relance son erreur). buffer : valeurs d'avance.
func from_producer(producer, buffer=16):
    ch := _ch.Channel(buffer)
    state := [null]
    async func emit(v):
        await ch.send(v)
    async func run():
        try:
            await _maybe(producer(emit))
        catch e:
            state[0] = [e.type, e.message]
        finally:
            ch.close()
    started := [false]
    async func pull():
        if not started[0]:
            started[0] = true
            run()
        try:
            return [true, await ch.recv()]
        catch ChannelClosedError as e:
            if state[0] != null:
                raise(state[0][0], state[0][1])
            return [false, null]
    return AsyncStream(pull)

# Valeurs de plusieurs flux, dans l'ordre d'arrivée ; fini quand tous le sont.
func merge(streams):
    srcs := [s for s in streams]
    pending := [null for s in srcs]
    alive := [true for s in srcs]
    async func pull():
        while true:
            futs := []
            for k in 0..len(srcs):
                if alive[k] and pending[k] == null:
                    pending[k] = srcs[k].next()
                if alive[k]:
                    append(futs, pending[k])
            if len(futs) == 0:
                return [false, null]
            await _settle(asyncio.race(futs))
            for k in 0..len(srcs):
                if alive[k] and pending[k] != null and asyncio.done(pending[k]):
                    f := pending[k]
                    pending[k] = null
                    r := await f
                    if r[0]:
                        return r
                    alive[k] = false
    return AsyncStream(pull)

# (a, b) deux à deux ; fini dès que l'un l'est.
func zip(a, b):
    async func pull():
        ra := await a.next()
        if not ra[0]:
            return ra
        rb := await b.next()
        if not rb[0]:
            return rb
        return [true, (ra[1], rb[1])]
    return AsyncStream(pull)

func empty():
    return from_list([])
