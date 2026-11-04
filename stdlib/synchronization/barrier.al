# ALEX STANDARD LIBRARY — synchronization.barrier
#
# Barrière entre FILS : chaque participant attend, à wait(), que tous les `parties` participants soient arrivés ;
# puis tous repartent ensemble. Réutilisable (cycles successifs : calcul par étapes).
#
#   use synchronization.barrier as bar
#   b := bar.Barrier(4)
#   # dans chacun des 4 fils (b2 := bar.attach(id)) :
#   for etape in 0..10:
#       calculer(etape)
#       b2.wait()                      # renvoie le rang d'arrivée 0..3 ; le dernier arrivé a parties - 1
#
# Délai : si un participant attend plus que son délai, la barrière est CASSÉE pour tous (BrokenBarrierError
# chez chacun, comme threading.Barrier de Python) ; reset() la remet en service. abort() la casse volontairement
# (par exemple quand un participant échoue, pour ne pas bloquer les autres).
#
# action : fonction appelée par le DERNIER arrivé de chaque cycle, avant que les autres ne repartent... seulement
# dans le fil dont l'objet Barrier a reçu l'action (une fonction ne passe pas d'un fil à l'autre).
#
# Erreurs : BrokenBarrierError, ArgumentError, TypeError.

from core use type
use _native_sync as _s
use mutex._common as _c

class Barrier:
    func init(parties=2, action=null, id=null):
        if id != null:
            _c.check_kind("Barrier", id, "barrier")
            self.id = id
        else:
            if type(parties) != "int" or parties < 1:
                raise("ArgumentError", "Barrier : au moins 1 participant")
            self.id = _s.barrier_new(parties)
        self.action = action

    # Attend les autres ; renvoie le rang d'arrivée (0 .. parties-1).
    func wait(timeout=null):
        _c.need_timeout("Barrier.wait", timeout)
        r := _s.barrier_wait(self.id, timeout)
        if r == -1:
            raise("BrokenBarrierError", "Barrier.wait : délai dépassé, la barrière est cassée")
        if r == -2:
            raise("BrokenBarrierError", "Barrier.wait : la barrière est cassée (abort, reset ou délai d'un autre participant)")
        if self.action != null and r == self.parties() - 1:
            a := self.action
            a()
        return r

    func parties():
        return _s.barrier_info(self.id)[0]

    func waiting():
        return _s.barrier_info(self.id)[1]

    func broken():
        return _s.barrier_info(self.id)[2]

    # Nombre de cycles achevés.
    func generation():
        return _s.barrier_info(self.id)[3]

    func reset():
        _s.barrier_reset(self.id)

    func abort():
        _s.barrier_abort(self.id)

    func destroy():
        _s.destroy(self.id)

func attach(id, action=null):
    return Barrier(1, action, id)
