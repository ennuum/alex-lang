# ALEX STANDARD LIBRARY — coroutine.coroutine_handle
#
# CoroutineHandle : une poignée légère sur une coroutine (comme std::coroutine_handle) — identifiant,
# reprise, état, destruction — et un registre des coroutines vivantes, pour les retrouver par identifiant
# (planificateurs, outils de diagnostic).
#
#   use coroutine.coroutine_handle as ch
#   h := ch.CoroutineHandle(ma_coroutine)
#   print(h.id, h.done(), h.state())
#   v := await h.resume()
#   ch.get(h.id)                    # même poignée, depuis ailleurs
#   print(ch.live())                # identifiants des coroutines non terminées
#   await h.destroy()               # ferme la coroutine et la retire du registre
#
# Erreurs : CoroutineError (identifiant inconnu, poignée détruite).

from core use type, len
from collections use append
use asyncio
use coroutine.coroutine as _co
from coroutine.coroutine use Coroutine
use coroutine.coroutine_errors as _e

_registry := {}

class CoroutineHandle:
    func init(co):
        if not isinstance(co, Coroutine):
            raise("TypeError", "CoroutineHandle : Coroutine attendue")
        self.co = co
        self.id = co.id
        self.destroyed = false
        _registry[self.id] = self

    func _need(fn):
        if self.destroyed:
            _e.coroutine_error("CoroutineHandle." + fn, "poignée détruite")

    func resume(value=null):
        self._need("resume")
        return self.co.resume(value)

    func done():
        return self.co.is_finished()

    func state():
        return self.co.state()

    func result():
        return self.co.result

    func name():
        return self.co.name

    # Ferme la coroutine (si besoin) et retire la poignée du registre.
    func destroy():
        if self.destroyed:
            return asyncio.sleep(0)
        self.destroyed = true
        if self.id in _registry:
            del _registry[self.id]
        return self.co.close()

    func __eq__(other):
        return isinstance(other, CoroutineHandle) and other.id == self.id

    func hash_code():
        return self.id

    func __str__():
        return "CoroutineHandle(#" + str(self.id) + ", " + self.state() + ")"

func of(co):
    if co.id in _registry:
        return _registry[co.id]
    return CoroutineHandle(co)

# Coroutine créée et enregistrée.
func spawn(body, args=null, name=null):
    return CoroutineHandle(_co.Coroutine(body, args, name))

func get(id):
    if not (id in _registry):
        _e.coroutine_error("coroutine_handle.get", "aucune coroutine #" + str(id))
    return _registry[id]

func exists(id):
    return id in _registry

func live():
    return [k for k in _registry if not _registry[k].done()]

func all_handles():
    return [_registry[k] for k in _registry]

# Retire du registre les coroutines terminées ; renvoie leur nombre.
func prune():
    gone := [k for k in _registry if _registry[k].done()]
    for k in gone:
        del _registry[k]
    return len(gone)
