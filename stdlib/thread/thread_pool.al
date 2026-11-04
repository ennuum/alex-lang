# ALEX STANDARD LIBRARY — thread.thread_pool
#
# Réserve de fils (ThreadPool) : des fils lancés une fois, qui exécutent ensuite des tâches les unes après les
# autres, en PARALLÈLE sur plusieurs cœurs. submit renvoie un ThreadFuture ; map applique une fonction à une
# liste.
#
#   use thread.thread_pool as tp
#   func carre(x):                          # fonction de PREMIER NIVEAU d'un module
#       return x * x
#   if thread.is_main():                    # le module est réimporté par chaque fil : protéger le programme
#       pool := tp.ThreadPool(4)
#       f := pool.submit(carre, [12])
#       print(f.result())                   # 144
#       print(pool.map(carre, [1, 2, 3]))   # [1, 4, 9]
#       r := await pool.submit(carre, [5]).as_future()     # depuis une tâche async
#       pool.shutdown()
#
# Fonctionnement : chaque fonction soumise a sa propre équipe de fils (au plus `workers`), créée à la demande,
# qui importe le module de la fonction une seule fois puis boucle sur ses tâches. Arguments et résultats sont
# COPIÉS (null, bool, nombres, str, list, tuple, dict), comme pour thread.spawn ; 12 arguments au plus.
#
# Erreurs : l'erreur d'une tâche est relancée par result() (même type, message suffixé du fil) ; TimeoutError
# (result, map avec délai) ; ThreadError (pool arrêté, trop de fils) ; ArgumentError (fonction non de premier
# niveau).

from core use len, type
from collections use append, contains_key, keys
use _native_thread as _t
use asyncio

class ThreadFuture:
    func init(pool, job):
        self._pool = pool
        self.job = job

    # Vrai si la tâche est finie (sans attendre).
    func done():
        self._pool._collect(0)
        return contains_key(self._pool._results, self.job)

    # Résultat de la tâche (attend au plus timeout secondes, TimeoutError sinon) ; relance son erreur.
    func result(timeout=null):
        r := self._pool._wait_for(self.job, timeout)
        if r[0]:
            return r[1]
        raise(r[1], r[2] + " [ThreadPool " + self._pool.name + "]")

    # null si la tâche a réussi ; sinon {"type", "message", "trace"} (attend la fin).
    func exception(timeout=null):
        r := self._pool._wait_for(self.job, timeout)
        if r[0]:
            return null
        return {"type": r[1], "message": r[2], "trace": r[3]}

    # Futur asyncio terminé avec le résultat : `await f.as_future()` n'immobilise pas les autres tâches.
    func as_future():
        return _await_job(self)

async func _await_job(tf):
    pause := 0.0005
    while not tf.done():
        await asyncio.sleep(pause)
        if pause < 0.02:
            pause = pause * 2
    return tf.result(0)

class ThreadPool:
    # workers : fils au plus PAR FONCTION (défaut : nombre de cœurs).
    func init(workers=null, name="pool"):
        if workers == null:
            workers = _t.cpu_count()
        if type(workers) != "int" or workers < 1:
            raise("ArgumentError", "ThreadPool : au moins un fil")
        if not _t.supported():
            raise("ThreadError", "ThreadPool : fils non disponibles sur cette plateforme")
        self.workers = workers
        self.name = name
        self._groups = []          # [fonction, canal des tâches, [ids des fils], tâches soumises]
        self._results_chan = _t.channel(0)
        self._results = {}         # tâche -> [true, valeur] | [false, type, message, trace]
        self._next = 1
        self._closed = false
        self.submitted = 0
        self.completed = 0

    func _group(fn):
        for g in self._groups:
            if g[0] == fn:
                return g
        g := [fn, _t.channel(0), [], 0]
        append(self._groups, g)
        return g

    # Lance fn(*args) sur un fil de la réserve ; renvoie un ThreadFuture.
    func submit(fn, args=null):
        if self._closed:
            raise("ThreadError", "ThreadPool.submit : réserve arrêtée (shutdown)")
        if type(fn) != "function":
            raise("TypeError", "ThreadPool.submit : fonction attendue")
        if args == null:
            args = []
        if type(args) != "list" and type(args) != "tuple":
            raise("TypeError", "ThreadPool.submit : les arguments doivent être une list")
        g := self._group(fn)
        job := self._next
        self._next += 1
        g[3] += 1
        busy := g[3] - len(g[2])
        if len(g[2]) < self.workers and busy > 0:
            id := _t.spawn_service(fn, g[1], self._results_chan, self.name + "-" + str(len(g[2]) + 1))
            if id == -1:
                raise("ThreadError", "ThreadPool : appelé pendant l'import du module dans un fil (protéger par `if thread.is_main():`)")
            if id == -2:
                raise("ThreadError", "ThreadPool : trop de fils en cours (256 au plus)")
            append(g[2], id)
        _t.send(g[1], [job, [a for a in args]], null)
        self.submitted += 1
        return ThreadFuture(self, job)

    func _store(msg):
        if msg[1]:
            self._results[msg[0]] = [true, msg[2]]
        else:
            trace := msg[4]
            if type(trace) != "str":
                trace = str(trace)
            self._results[msg[0]] = [false, msg[2], msg[3], trace]
        self.completed += 1

    # Range les résultats déjà arrivés (attend au plus timeout le premier).
    func _collect(timeout):
        r := _t.recv(self._results_chan, timeout)
        while r[0] == 1:
            self._store(r[1])
            r = _t.recv(self._results_chan, 0)

    func _wait_for(job, timeout):
        if contains_key(self._results, job):
            return self._results[job]
        start := _now()
        while true:
            left := null
            if timeout != null:
                left = timeout - (_now() - start)
                if left <= 0:
                    raise("TimeoutError", "ThreadPool : tâche " + str(job) + " non finie dans le délai")
            r := _t.recv(self._results_chan, left)
            if r[0] == 1:
                self._store(r[1])
                if contains_key(self._results, job):
                    return self._results[job]
            elif r[0] == 2:
                raise("ThreadError", "ThreadPool : canal des résultats fermé")

    # [fn(x) for x in items], en parallèle, dans l'ordre ; relance la première erreur (dans l'ordre des items).
    func map(fn, items, timeout=null):
        futures := [self.submit(fn, [x]) for x in items]
        return [f.result(timeout) for f in futures]

    # Comme map, chaque élément étant la liste des arguments.
    func starmap(fn, arg_lists, timeout=null):
        futures := [self.submit(fn, a) for a in arg_lists]
        return [f.result(timeout) for f in futures]

    # Tâches soumises dont le résultat n'est pas encore arrivé.
    func pending():
        self._collect(0)
        return self.submitted - self.completed

    func threads():
        n := 0
        for g in self._groups:
            n += len(g[2])
        return n

    # Arrête la réserve : plus de submit ; les fils finissent les tâches déjà soumises puis s'arrêtent. wait :
    # attendre leur fin (au plus timeout secondes).
    func shutdown(wait=true, timeout=null):
        if self._closed:
            return
        self._closed = true
        for g in self._groups:
            _t.close(g[1])
        if wait:
            for g in self._groups:
                for id in g[2]:
                    _t.join(id, timeout)
            self._collect(0)

use os as _os

func _now():
    return _os.monotonic_time()

# Exécute fn(pool) avec une réserve neuve, arrêtée ensuite (même en cas d'erreur).
func with_pool(workers, fn):
    p := ThreadPool(workers)
    try:
        return fn(p)
    finally:
        p.shutdown(true)
