# ALEX STANDARD LIBRARY — coroutine.yield
#
# Le côté CORPS d'une coroutine : suspendre l'exécution en rendant une valeur à celui qui l'a reprise, et
# recevoir ce qu'il renvoie à la reprise suivante. ALEX n'a pas d'instruction `yield` : le corps d'une
# coroutine est une `async func` qui reçoit un Yielder et fait `await y.yield_(valeur)`.
#
#   use coroutine.coroutine as co
#   async func compteur(y, n):
#       i := 0
#       while i < n:
#           recu := await y.yield_(i)        # suspend ; reprend avec la valeur envoyée par resume()
#           if recu == "stop":
#               return "arrêté"
#           i += 1
#       return "fini"
#   c := co.Coroutine(compteur, [3])
#   print(await c.resume())                  # 0
#   print(await c.resume("continue"))        # 1
#   await y.yield_from(autre_coroutine)      # (dans un corps) délègue jusqu'à la fin de l'autre
#   await yield_now()                        # cède la main aux autres tâches sans rien rendre
#
# Erreurs : CoroutineError (yield_ d'une coroutine qui ne s'exécute pas), CoroutineExit (fermeture).

from core use type
use asyncio
use coroutine.coroutine_errors as _e

class Yielder:
    func init(owner):
        self._co = owner
        self.count = 0

    # Suspend la coroutine en rendant value ; renvoie la valeur passée à la reprise suivante.
    func yield_(value=null):
        return self._co._suspend(value)

    # Rend chaque valeur produite par une autre coroutine, puis rend sa valeur finale.
    func yield_from(other):
        return _yield_from(self, other)

    # Nombre de suspensions effectuées.
    func yields():
        return self._co.yields

    func coroutine():
        return self._co

async func _yield_from(y, other):
    sent := null
    v := await other.resume(sent)
    while not other.is_finished():
        sent = await y.yield_(v)
        v = await other.resume(sent)
    return other.result

# Cède la main aux autres tâches (un tour de boucle), sans suspendre la coroutine vis-à-vis de son appelant.
func yield_now():
    return asyncio.sleep(0)

# Valeur spéciale : rendue par yield_, demande au planificateur (coroutine_scheduler) d'attendre seconds.
class Wait:
    func init(seconds):
        if type(seconds) != "int" and type(seconds) != "float":
            raise("TypeError", "Wait : durée en secondes attendue")
        self.seconds = seconds

func wait(seconds):
    return Wait(seconds)
