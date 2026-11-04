# ALEX STANDARD LIBRARY — synchronization.once
#
# Exécution UNIQUE entre fils : Once.call(fn) exécute fn une seule fois pour l'ensemble des fils qui partagent
# l'objet ; les autres attendent la fin de cette exécution et reçoivent le même résultat (copié). Si fn lève une
# exception, l'exécution compte comme non faite : l'appelant reçoit l'erreur et un appel suivant réessaie.
#
#   use synchronization.once as once
#   init := once.Once()
#   cfg := init.call(charger_configuration)       # dans chaque fil : once.attach(ids).call(charger_configuration)
#
#   l := once.Lazy(calcul_couteux)                  # valeur paresseuse (un seul fil)
#   print(l.get())
#
# Le résultat doit être copiable entre fils (null, bool, nombres, str, list, tuple, dict).
#
# Erreurs : celles de fn ; TimeoutError (call avec délai) ; TypeError (résultat non copiable).

from core use type
use _native_sync as _s
use mutex._common as _c

class Once:
    # ids : [once, valeur] d'un Once créé dans un autre fil (voir share()).
    func init(ids=null):
        if ids != null:
            _c.check_kind("Once", ids[0], "once")
            _c.check_kind("Once", ids[1], "ref")
            self.id = ids[0]
            self._value = ids[1]
        else:
            self.id = _s.once_new()
            self._value = _s.ref_new(null)

    # Identifiants à transmettre à un fil (once.attach(ids)).
    func share():
        return [self.id, self._value]

    func call(fn, timeout=null):
        _c.need_timeout("Once.call", timeout)
        r := _s.once_enter(self.id, timeout)
        if r == -1:
            raise("TimeoutError", "Once.call : l'exécution en cours dans un autre fil n'a pas fini dans le délai")
        if r == 0:
            return _s.ref_load(self._value)
        ok := false
        try:
            v := fn()
            _s.ref_store(self._value, v)
            ok = true
            return v
        finally:
            _s.once_leave(self.id, ok)

    func done():
        return _s.once_state(self.id) == 2

    func running():
        return _s.once_state(self.id) == 1

    func destroy():
        _s.destroy(self.id)
        _s.destroy(self._value)

func attach(ids):
    return Once(ids)

# Valeur calculée au premier get() (dans ce fil), puis gardée.
class Lazy:
    func init(fn):
        self._fn = fn
        self._done = false
        self._value = null

    func get():
        if not self._done:
            f := self._fn
            self._value = f()
            self._done = true
            self._fn = null
        return self._value

    func evaluated():
        return self._done
