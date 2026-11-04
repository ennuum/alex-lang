# ALEX STANDARD LIBRARY — synchronization
#
# Primitives de synchronisation entre FILS d'exécution réels (thread, concurrency.thread), toutes avec délai :
#
# | Primitive        | Module                         | Pour                                              |
# |------------------|--------------------------------|---------------------------------------------------|
# | Semaphore        | synchronization.semaphore      | limiter le nombre de fils sur une ressource       |
# | Condition        | synchronization.condition      | attendre un changement d'état, verrou pris        |
# | Barrier          | synchronization.barrier        | avancer par étapes, tous ensemble                 |
# | CountDownLatch   | synchronization.latch          | attendre que N choses soient prêtes               |
# | Once, Lazy       | synchronization.once           | initialisation unique                             |
# | Event            | ici                            | signal « c'est arrivé », attendu par plusieurs fils |
# | Mutex...         | mutex                          | exclusion mutuelle                                |
# | AtomicInteger... | atomic                         | compteurs et drapeaux sans verrou                 |
#
#   use synchronization as sync
#   pret := sync.Event()
#   thread.spawn(serveur, [pret.id])          # le fil : sync.attach_event(id).set()
#   pret.wait(5.0)
#
# Chaque objet a un identifiant (.id) à transmettre aux fils, qui le rattachent (attach). Entre processus : ipc.
# Entre tâches async d'un même fil : concurrency.* (verrous coopératifs).

from core use type
use _native_sync as _s
use mutex._common as _c
use synchronization.semaphore as _sem
use synchronization.condition as _cond
use synchronization.barrier as _bar
use synchronization.latch as _latch
use synchronization.once as _once

class Event:
    func init(is_set=false, id=null):
        if id != null:
            _c.check_kind("Event", id, "event")
            self.id = id
        else:
            self.id = _s.event_new(is_set)

    func set():
        _s.event_set(self.id)

    func clear():
        _s.event_clear(self.id)

    func is_set():
        return _s.event_is_set(self.id)

    # Attend que l'événement soit levé ; false si timeout secondes passent avant.
    func wait(timeout=null):
        _c.need_timeout("Event.wait", timeout)
        return _s.event_wait(self.id, timeout) == 1

    # Futur (vrai si levé) pour une tâche async.
    func wait_async(timeout=null):
        return _c.poll_acquire(() => self.is_set(), timeout)

    func destroy():
        _s.destroy(self.id)

func attach_event(id):
    return Event(false, id)

func semaphore(value=1):
    return _sem.Semaphore(value)

func bounded_semaphore(value=1):
    return _sem.BoundedSemaphore(value)

func condition(mutex=null):
    return _cond.Condition(mutex)

func barrier(parties, action=null):
    return _bar.Barrier(parties, action)

func latch(count):
    return _latch.CountDownLatch(count)

func once():
    return _once.Once()

func lazy(fn):
    return _once.Lazy(fn)

func live_objects():
    return _s.live()
