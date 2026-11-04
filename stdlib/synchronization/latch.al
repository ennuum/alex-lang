# ALEX STANDARD LIBRARY — synchronization.latch
#
# Loquet à compte à rebours (CountDownLatch) entre FILS : wait() bloque jusqu'à ce que le compteur atteigne 0 ;
# count_down() le diminue. À usage unique (contrairement à Barrier) : une fois ouvert, il le reste.
#
#   use synchronization.latch as latch
#   prets := latch.CountDownLatch(3)
#   # chacun des 3 fils de service, une fois initialisé :  latch.attach(id).count_down()
#   if not prets.wait(10.0):
#       raise("TimeoutError", "les services n'ont pas démarré")
#
# Erreurs : ArgumentError, TypeError.

from core use type
use _native_sync as _s
use mutex._common as _c

class CountDownLatch:
    func init(count=1, id=null):
        if id != null:
            _c.check_kind("CountDownLatch", id, "latch")
            self.id = id
        else:
            if type(count) != "int" or count < 0:
                raise("ArgumentError", "CountDownLatch : compte >= 0 attendu")
            self.id = _s.latch_new(count)

    # Diminue le compte de n (sans descendre sous 0) ; renvoie le compte restant.
    func count_down(n=1):
        return _s.latch_count_down(self.id, n)

    func count():
        return _s.latch_count(self.id)

    # Attend que le compte soit nul ; false si timeout secondes passent avant.
    func wait(timeout=null):
        _c.need_timeout("CountDownLatch.wait", timeout)
        return _s.latch_wait(self.id, timeout) == 1

    func try_wait():
        return self.count() == 0

    func destroy():
        _s.destroy(self.id)

func attach(id):
    return CountDownLatch(0, id)
