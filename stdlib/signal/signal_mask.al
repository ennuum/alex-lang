# ALEX STANDARD LIBRARY — signal.signal_mask
#
# Masques de signaux : RETARDER la prise en compte de signaux pendant une section critique (écriture d'un
# fichier d'état, transaction), puis les traiter à la sortie — comme sigprocmask, au niveau du programme
# ALEX : un signal bloqué n'exécute pas son gestionnaire tout de suite ; il est noté (une fois par signal,
# comme le noyau), puis délivré au déblocage, dans l'ordre d'arrivée.
#
#   use signal.signal_mask as sm
#   signal.on("TERM", arreter)
#   m := sm.SignalMask(["TERM", "INT"])
#   m.block()
#   ecrire_etat()                 # un TERM reçu ici attend
#   m.unblock()                   # ... et arreter() s'exécute maintenant
#   sm.blocked(["INT"], critique) # forme portée : débloque même si critique() lève une erreur
#   print(sm.pending())           # signaux reçus pendant un blocage en cours
#
# Un signal sans gestionnaire (comportement par défaut : souvent l'arrêt) est intercepté pendant le blocage
# puis, au déblocage, rétabli et renvoyé au programme : son effet par défaut se produit à ce moment.
# Les blocages s'imbriquent (compteur par signal). KILL et STOP ne se bloquent pas.
# Erreurs : SignalMaskError (unblock sans block), ArgumentError (signal non interceptable), ThreadError.

from core use len, type
from collections use append, pop
use system.signal as _sig
use signal.signal_constants as _c
use signal.signal_errors as _e

_depth := {}        # numéro -> profondeur de blocage
_saved := {}        # numéro -> gestionnaire d'origine (ou null : comportement par défaut)
_pending := []      # numéros reçus pendant le blocage (sans doublon), ordre d'arrivée

func _defer(name):
    n := _sig.number(name)
    for p in _pending:
        if p == n:
            return
    append(_pending, n)

func _block_one(sig):
    n := _sig.number(sig)
    name := _sig.name_of(n)
    if name == "KILL" or name == "STOP":
        raise("ArgumentError", "signal_mask : " + name + " ne peut pas être bloqué")
    d := 0
    if n in _depth:
        d = _depth[n]
    if d == 0:
        _saved[n] = _sig.on(n, _defer)
    _depth[n] = d + 1

func _unblock_one(sig):
    n := _sig.number(sig)
    if not (n in _depth) or _depth[n] == 0:
        _e.mask_error("signal_mask.unblock", "le signal " + _sig.name_of(n) + " n'est pas bloqué")
    _depth[n] = _depth[n] - 1
    if _depth[n] > 0:
        return
    prev := _saved[n]
    del _saved[n]
    if prev == null:
        _sig.reset(n)
    else:
        _sig.on(n, prev)
    was := false
    keep := []
    for p in _pending:
        if p == n:
            was = true
        else:
            append(keep, p)
    _replace_pending(keep)
    if was:
        if prev == null:
            _sig.raise_signal(n)
        else:
            prev(_sig.name_of(n))

func _replace_pending(items):
    while len(_pending) > 0:
        pop(_pending)
    for x in items:
        append(_pending, x)

func block(sigs):
    for s in _as_list(sigs):
        _block_one(s)

func unblock(sigs):
    for s in _as_list(sigs):
        _unblock_one(s)

func is_blocked(sig):
    n := _sig.number(sig)
    return n in _depth and _depth[n] > 0

# Noms des signaux reçus pendant un blocage en cours.
func pending():
    return [_sig.name_of(n) for n in _pending]

func _as_list(sigs):
    if type(sigs) == "list" or type(sigs) == "tuple":
        return sigs
    return [sigs]

# body() avec sigs bloqués ; déblocage garanti à la sortie (les signaux en attente sont alors délivrés).
func blocked(sigs, body):
    block(sigs)
    try:
        return body()
    finally:
        unblock(sigs)

class SignalMask:
    func init(signals=null):
        self.signals = []
        if signals != null:
            for s in _as_list(signals):
                append(self.signals, _sig.name_of(_sig.number(s)))
        self._active = false

    func add(sig):
        if self._active:
            _e.mask_error("SignalMask.add", "masque actif : débloquer d'abord")
        append(self.signals, _sig.name_of(_sig.number(sig)))
        return self

    func block():
        if self._active:
            _e.mask_error("SignalMask.block", "masque déjà actif")
        block(self.signals)
        self._active = true

    func unblock():
        if not self._active:
            _e.mask_error("SignalMask.unblock", "masque inactif")
        self._active = false
        unblock(self.signals)

    func is_active():
        return self._active

    func contains(sig):
        name := _sig.name_of(_sig.number(sig))
        for s in self.signals:
            if s == name:
                return true
        return false

    # Signaux du masque reçus pendant le blocage.
    func pending():
        return [p for p in pending() if self.contains(p)]

    func run(body):
        self.block()
        try:
            return body()
        finally:
            self.unblock()

    func __enter__():
        self.block()
        return self

    func __exit__(a, b, c):
        self.unblock()

    func __str__():
        state := "inactif"
        if self._active:
            state = "actif"
        return "SignalMask(" + str(self.signals) + ", " + state + ")"

# Masque des signaux d'arrêt usuels (INT, TERM, HUP, QUIT).
func shutdown_mask():
    return SignalMask(["INT", "TERM", "HUP", "QUIT"])
