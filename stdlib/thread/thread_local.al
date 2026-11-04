# ALEX STANDARD LIBRARY — thread.thread_local
#
# Valeurs PROPRES À CHAQUE FIL. Chaque fil d'Alex a sa propre VM : les variables d'un module y sont déjà propres
# au fil (un module est réimporté dans chaque fil). ThreadLocal rend cette intention explicite et donne en plus une
# valeur initiale fabriquée à la demande, la remise à zéro et l'identité du fil système.
#
#   use thread.thread_local as tl
#   connexion := tl.ThreadLocal(null, ouvrir_connexion)     # factory : appelée au premier get() de chaque fil
#   c := connexion.get()
#   compteur := tl.ThreadLocal(0)
#   compteur.set(compteur.get() + 1)
#
# Attention : les tâches async d'un même fil partagent ses valeurs (elles s'exécutent sur le même fil).

from collections use contains_key, remove
use _native_sync as _s

class ThreadLocal:
    # default : valeur initiale ; factory : fonction sans argument qui la fabrique (prioritaire sur default).
    func init(default=null, factory=null):
        self._default = default
        self._factory = factory
        self._values = {}

    func _key():
        return _s.token()

    func get():
        k := self._key()
        if not contains_key(self._values, k):
            if self._factory != null:
                f := self._factory
                self._values[k] = f()
            else:
                self._values[k] = self._default
        return self._values[k]

    func set(value):
        self._values[self._key()] = value

    # Vrai si ce fil a déjà une valeur (get ou set).
    func has():
        return contains_key(self._values, self._key())

    # Oublie la valeur de ce fil (le prochain get la refabrique).
    func clear():
        k := self._key()
        if contains_key(self._values, k):
            remove(self._values, k)

    # Remplace v par f(v) ; renvoie la nouvelle valeur.
    func update(f):
        v := f(self.get())
        self.set(v)
        return v

func local(default=null, factory=null):
    return ThreadLocal(default, factory)
