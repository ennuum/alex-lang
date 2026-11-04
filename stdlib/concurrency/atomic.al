# ALEX STANDARD LIBRARY — concurrency.atomic
#
# Valeurs à opérations indivisibles : lire-modifier-écrire en une seule étape (compteur partagé entre tâches,
# drapeau « déjà fait », échange).
#
# Dans la VM, le code s'exécute sur un seul fil et une tâche n'est interrompue qu'à un `await` : chaque méthode
# (qui ne contient aucun `await`) est donc indivisible vis-à-vis des autres tâches. Atomic rend cette garantie
# explicite et donne les opérations classiques (compare_exchange, fetch_add) sous une forme unique ; un
# compteur écrit `x = x + 1` reste correct, mais `v := lire() ; await ... ; écrire(v + 1)` ne l'est pas —
# c'est update() ou un Mutex qu'il faut alors.
#
#   hits := Atomic(0)
#   hits.add(1)                      # renvoie l'ancienne valeur
#   if hits.compare_exchange(10, 0): # remet à zéro si la valeur est 10
#       print("dix")
#
# Le noyau sans OS fournit les vraies instructions atomiques entre cœurs : hw.cas, hw.atomic_add (docs/NATIVE.md).

from core use type

func _need_number(fn, v):
    t := type(v)
    if t != "int" and t != "float":
        raise("TypeError", "Atomic." + fn + " : nombre attendu (obtenu '" + t + "')")

class Atomic:
    func init(value=0):
        self._value = value

    func load():
        return self._value

    func store(value):
        self._value = value

    # Remplace la valeur ; renvoie l'ancienne.
    func exchange(value):
        old := self._value
        self._value = value
        return old

    # Si la valeur vaut expected, la remplace par new et renvoie true ; sinon renvoie false.
    func compare_exchange(expected, new):
        if self._value == expected:
            self._value = new
            return true
        return false

    # Ajoute delta ; renvoie l'ANCIENNE valeur (fetch_add).
    func add(delta=1):
        _need_number("add", delta)
        old := self._value
        self._value = old + delta
        return old

    func sub(delta=1):
        _need_number("sub", delta)
        old := self._value
        self._value = old - delta
        return old

    # +1 / -1 ; renvoient la NOUVELLE valeur.
    func increment():
        self._value = self._value + 1
        return self._value

    func decrement():
        self._value = self._value - 1
        return self._value

    # Remplace la valeur par f(valeur) ; renvoie la nouvelle. f ne doit pas être une fonction async.
    func update(f):
        self._value = f(self._value)
        return self._value

    # Valeur maximale / minimale gardée : renvoie l'ancienne.
    func fetch_max(v):
        old := self._value
        if v > old:
            self._value = v
        return old

    func fetch_min(v):
        old := self._value
        if v < old:
            self._value = v
        return old

class AtomicFlag:
    func init():
        self._set = false

    # Lève le drapeau ; renvoie son état précédent (false : c'est cet appel qui l'a levé).
    func test_and_set():
        old := self._set
        self._set = true
        return old

    func clear():
        self._set = false

    func is_set():
        return self._set
