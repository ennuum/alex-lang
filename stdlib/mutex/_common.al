# ALEX STANDARD LIBRARY — mutex._common (interne)

from core use type
use _native_sync as _s
use asyncio

func need_timeout(fn, t):
    if t != null and type(t) != "int" and type(t) != "float":
        raise("TypeError", fn + " : délai nombre ou null attendu")
    if t != null and t < 0:
        raise("ArgumentError", fn + " : délai négatif")

func check_kind(fn, id, kind):
    if type(id) != "int":
        raise("TypeError", fn + " : identifiant (int) attendu")
    k := _s.kind(id)
    if k == null:
        raise("ArgumentError", fn + " : objet " + str(id) + " inconnu ou détruit")
    if k != kind:
        raise("TypeError", fn + " : l'objet " + str(id) + " est un(e) " + k + ", pas un(e) " + kind)

# Acquisition depuis une tâche async : essaie sans bloquer le fil, et cède la main entre deux essais (attente
# croissante de 0,5 ms à 20 ms) pour que les autres tâches avancent. try_fn() -> bool.
async func poll_acquire(try_fn, timeout):
    start := asyncio.now()
    pause := 0.0005
    while true:
        if try_fn():
            return true
        if timeout != null and asyncio.now() - start >= timeout:
            return false
        await asyncio.sleep(pause)
        if pause < 0.02:
            pause = pause * 2
