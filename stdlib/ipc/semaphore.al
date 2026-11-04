# ALEX STANDARD LIBRARY — ipc.semaphore
#
# Sémaphores NOMMÉS entre processus (POSIX sem_open) : un compteur de jetons partagé par tous les processus qui
# ouvrent le même nom. acquire prend un jeton (attend s'il n'y en a plus), release en rend un. Sert à limiter le
# nombre de processus qui utilisent une ressource en même temps, ou à signaler un événement d'un processus à un
# autre.
#
#   use ipc.semaphore as sem
#   s := sem.NamedSemaphore("imprimante", 2)     # 2 jetons à la création (ignoré si le nom existe déjà)
#   if s.acquire(5.0):                            # au plus 5 s d'attente
#       try:
#           imprimer()
#       finally:
#           s.release()
#   s.with_permit(imprimer)                       # la même chose
#   s.close()
#   sem.unlink("imprimante")
#
# Pour des fils d'un même processus, synchronization.semaphore est plus simple (pas de nom à gérer).
#
# Erreurs : IpcError (système), TimeoutError (with_permit, run avec délai), TypeError.

from core use type
use _native_sync as _s

func _fail(op, code):
    raise("IpcError", op + " : " + _s.strerror(code) + " [" + _s.errno_name(code) + "]")

class NamedSemaphore:
    # mode : "open_or_create" (défaut), "create" (échoue si le nom existe), "open".
    func init(name, value=1, mode="open_or_create"):
        if not _s.supported_ipc():
            raise("IpcError", "ipc.semaphore : non pris en charge sur cette plateforme")
        h := _s.nsem_open(name, mode, value)
        if h < 0:
            _fail("NamedSemaphore('" + name + "')", h)
        self.name = name
        self._h = h
        self.closed = false

    # Prend un jeton ; false si timeout secondes passent sans jeton (0 : ne pas attendre).
    func acquire(timeout=null):
        r := _s.nsem_wait(self._h, timeout)
        if r < 0:
            _fail("NamedSemaphore.acquire", r)
        return r == 1

    func try_acquire():
        return self.acquire(0)

    # Rend n jetons.
    func release(n=1):
        k := 0
        while k < n:
            r := _s.nsem_post(self._h)
            if r < 0:
                _fail("NamedSemaphore.release", r)
            k += 1

    # Jetons disponibles (null si le système ne le dit pas, macOS).
    func value():
        return _s.nsem_value(self._h)

    # fn() avec un jeton (rendu même en cas d'erreur) ; TimeoutError si aucun jeton dans le délai.
    func with_permit(fn, timeout=null):
        if not self.acquire(timeout):
            raise("TimeoutError", "NamedSemaphore '" + self.name + "' : aucun jeton dans le délai")
        try:
            return fn()
        finally:
            self.release()

    func close():
        if not self.closed:
            _s.nsem_close(self._h)
            self.closed = true

    func unlink():
        return unlink(self.name)

# Supprime le nom ; false s'il n'existait pas.
func unlink(name):
    r := _s.nsem_unlink(name)
    if r == 0:
        return true
    if _s.errno_name(r) == "ENOENT":
        return false
    _fail("semaphore.unlink('" + name + "')", r)

func open(name, value=1):
    return NamedSemaphore(name, value, "open_or_create")
