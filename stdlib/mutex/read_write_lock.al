# ALEX STANDARD LIBRARY — mutex.read_write_lock
#
# Verrou LECTEURS / ÉCRIVAIN entre fils : plusieurs fils lisent en même temps, un seul écrit (et personne ne lit
# pendant ce temps). Équitable pour les écrivains : dès qu'un écrivain attend, les nouveaux lecteurs patientent
# (pas de famine des écritures).
#
#   use mutex.read_write_lock as rw
#   verrou := rw.ReadWriteLock()
#   v := verrou.read(() => cache_lire(cle))         # lecture partagée
#   verrou.write(() => cache_ecrire(cle, val))      # écriture exclusive
#   verrou.write_lock() ; ... ; verrou.downgrade() ; ... ; verrou.read_unlock()   # écrire puis relire
#
# Réentrance : un lecteur peut reprendre la lecture, l'écrivain peut reprendre l'écriture ou lire. Un lecteur
# ne peut PAS passer en écriture (LockError : deux lecteurs qui le tenteraient s'attendraient à jamais) : rendre
# la lecture, puis prendre l'écriture.
#
# Erreurs : LockError, TimeoutError (read / write avec délai), TypeError.

use _native_sync as _s
use mutex._common as _c

class ReadWriteLock:
    func init(id=null):
        if id != null:
            _c.check_kind("ReadWriteLock", id, "rwlock")
            self.id = id
        else:
            self.id = _s.rw_new()

    func read_lock(timeout=null):
        _c.need_timeout("ReadWriteLock.read_lock", timeout)
        return _s.rw_read(self.id, timeout) == 1

    func read_unlock():
        if _s.rw_unlock_read(self.id) != 0:
            raise("LockError", "ReadWriteLock.read_unlock : ce fil ne lit pas")

    func write_lock(timeout=null):
        _c.need_timeout("ReadWriteLock.write_lock", timeout)
        r := _s.rw_write(self.id, timeout)
        if r == -1:
            raise("LockError", "ReadWriteLock.write_lock : ce fil tient le verrou en lecture (passer en écriture interbloquerait)")
        return r == 1

    func write_unlock():
        if _s.rw_unlock_write(self.id) != 0:
            raise("LockError", "ReadWriteLock.write_unlock : ce fil n'écrit pas")

    func try_read_lock():
        return self.read_lock(0)

    func try_write_lock():
        return self.write_lock(0)

    # Écrivain -> lecteur sans laisser passer d'autre écrivain entre les deux.
    func downgrade():
        if _s.rw_downgrade(self.id) != 0:
            raise("LockError", "ReadWriteLock.downgrade : ce fil ne tient pas le verrou en écriture (une seule fois)")

    func read(fn, timeout=null):
        if not self.read_lock(timeout):
            raise("TimeoutError", "ReadWriteLock.read : lecture non obtenue dans le délai")
        try:
            return fn()
        finally:
            self.read_unlock()

    func write(fn, timeout=null):
        if not self.write_lock(timeout):
            raise("TimeoutError", "ReadWriteLock.write : écriture non obtenue dans le délai")
        try:
            return fn()
        finally:
            self.write_unlock()

    func readers():
        return _s.rw_info(self.id)[0]

    func writing():
        return _s.rw_info(self.id)[1] != 0

    func writers_waiting():
        return _s.rw_info(self.id)[2]

    func destroy():
        _s.destroy(self.id)

func attach(id):
    return ReadWriteLock(id)
