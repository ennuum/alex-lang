# ALEX STANDARD LIBRARY — signal.signal_handler
#
# Plusieurs gestionnaires par signal, priorités, gestionnaires à usage unique, groupes que l'on installe et
# désinstalle d'un coup, et arrêt propre en deux temps (premier Ctrl+C : arrêt demandé ; second : immédiat).
#
#   use signal.signal_handler as sh
#   jeton := sh.add("USR1", (nom) => recharger_config())
#   sh.add("USR1", (nom) => journal.info("USR1 reçu"), 10)     # priorité 10 : appelé avant
#   sh.remove(jeton)
#
#   arret := sh.graceful_shutdown((nom) => print("arrêt demandé par", nom))
#   while not arret.requested():
#       travailler()                     # un second signal lève InterruptError
#
#   g := sh.HandlerGroup()
#   g.add("HUP", relire)
#   g.add("TERM", fermer)
#   g.install()   ...   g.uninstall()    # rend l'état précédent
#
# Repose sur system.signal (un seul gestionnaire système par signal) : ce module installe un répartiteur qui
# appelle, dans l'ordre des priorités décroissantes puis d'enregistrement, chaque fonction enregistrée. Quand le
# dernier gestionnaire d'un signal est retiré, le comportement d'origine est rétabli. Une exception levée par un
# gestionnaire interrompt la répartition et part de l'endroit où en était le programme (system.signal).
#
# Seul le programme principal intercepte les signaux (ThreadError depuis un fil).

from core use len, type
from collections use append, contains_key, keys
use collections as _col
use system.signal as _sig
use os as _os

_by_signal := {}      # numéro -> liste de [jeton, priorité, fonction, une_fois]
_tokens := {}         # jeton -> numéro
_next := [1]

func _dispatch(name):
    n := _sig.number(name)
    if not contains_key(_by_signal, n):
        return
    entries := [e for e in _by_signal[n]]
    for e in entries:
        if e[3]:
            remove_token(e[0])
        f := e[2]
        f(name)

func _sorted_insert(lst, entry):
    i := 0
    while i < len(lst) and lst[i][1] >= entry[1]:
        i += 1
    out := []
    k := 0
    while k < i:
        append(out, lst[k])
        k += 1
    append(out, entry)
    while k < len(lst):
        append(out, lst[k])
        k += 1
    return out

# Ajoute handler(nom) pour le signal ; renvoie un jeton (pour remove). priority : plus grand = appelé plus tôt.
func add(sig, handler, priority=0, once=false):
    if type(handler) != "function":
        raise("TypeError", "signal_handler.add : fonction attendue")
    n := _sig.number(sig)
    token := _next[0]
    _next[0] = token + 1
    first := not contains_key(_by_signal, n) or len(_by_signal[n]) == 0
    if not contains_key(_by_signal, n):
        _by_signal[n] = []
    _by_signal[n] = _sorted_insert(_by_signal[n], [token, priority, handler, once])
    _tokens[token] = n
    if first:
        _sig.on(n, _dispatch)
    return token

# Gestionnaire appelé une seule fois (à la prochaine arrivée du signal).
func once(sig, handler, priority=0):
    return add(sig, handler, priority, true)

# Retire le gestionnaire du jeton ; renvoie false s'il n'existait plus.
func remove_token(token):
    if not contains_key(_tokens, token):
        return false
    n := _tokens[token]
    _col.remove(_tokens, token)
    _by_signal[n] = [e for e in _by_signal[n] if e[0] != token]
    if len(_by_signal[n]) == 0:
        _sig.reset(n)
    return true

func remove(token):
    return remove_token(token)

# Retire tous les gestionnaires du signal et rétablit son comportement d'origine.
func clear(sig):
    n := _sig.number(sig)
    if contains_key(_by_signal, n):
        for e in _by_signal[n]:
            if contains_key(_tokens, e[0]):
                _col.remove(_tokens, e[0])
        _by_signal[n] = []
    _sig.reset(n)

# Nombre de gestionnaires enregistrés pour le signal.
func count(sig):
    n := _sig.number(sig)
    if not contains_key(_by_signal, n):
        return 0
    return len(_by_signal[n])

# Exécute body() avec handler installé pour sig, puis le retire (même en cas d'erreur).
func scoped(sig, handler, body):
    t := add(sig, handler)
    try:
        return body()
    finally:
        remove_token(t)

class HandlerGroup:
    func init():
        self._pending = []
        self._tokens = []

    # Ajoute un couple (signal, gestionnaire) ; installé tout de suite si le groupe l'est déjà.
    func add(sig, handler, priority=0):
        append(self._pending, [sig, handler, priority])
        if len(self._tokens) > 0:
            append(self._tokens, add_handler(sig, handler, priority))
        return self

    func install():
        if len(self._tokens) > 0:
            return self
        for p in self._pending:
            append(self._tokens, add_handler(p[0], p[1], p[2]))
        return self

    func uninstall():
        for t in self._tokens:
            remove_token(t)
        self._tokens = []
        return self

    func installed():
        return len(self._tokens) > 0

func add_handler(sig, handler, priority=0):
    return add(sig, handler, priority, false)

# ---------------------------------------------------------------- arrêt propre
class ShutdownRequest:
    func init(signals, callback, force_after):
        self.signals = signals
        self.callback = callback
        self.force_after = force_after
        self.count = 0
        self.signal = null
        self._group = HandlerGroup()

    func requested():
        return self.count > 0

    func _on_signal(name):
        self.count += 1
        self.signal = name
        if self.count == 1:
            if self.callback != null:
                cb := self.callback
                cb(name)
            return
        if self.force_after and self.count >= 2:
            raise("InterruptError", "arrêt immédiat : signal " + name + " reçu " + str(self.count) + " fois")

    # Attend la demande d'arrêt au plus timeout secondes ; renvoie le nom du signal, ou null.
    func wait(timeout=null):
        start := _os.monotonic_time()
        while self.count == 0:
            if timeout != null and _os.monotonic_time() - start >= timeout:
                return null
            _os.sleep(0.02)   # interrompu par l'arrivée d'un signal : son gestionnaire s'exécute
        return self.signal

    func cancel():
        self._group.uninstall()

func _install_shutdown(req):
    for s in req.signals:
        req._group.add(s, (name) => req._on_signal(name), 1000)
    req._group.install()
    return req

# Premier signal parmi signals : requested() devient vrai et callback(nom) est appelé ; le suivant (force=true)
# lève InterruptError (arrêt immédiat, les finally s'exécutent).
func graceful_shutdown(callback=null, signals=null, force=true):
    if signals == null:
        signals = ["INT", "TERM"]
    return _install_shutdown(ShutdownRequest(signals, callback, force))

# Drapeau levé à l'arrivée du signal (consulté par le programme, rien d'autre ne s'exécute).
class SignalFlag:
    func init(sig):
        self.sig = sig
        self.count = 0
        self._token = add(sig, (name) => self._hit())

    func _hit():
        self.count += 1

    func is_set():
        return self.count > 0

    # Lit puis remet à zéro ; renvoie le nombre d'arrivées depuis la dernière fois.
    func take():
        n := self.count
        self.count = 0
        return n

    func close():
        remove_token(self._token)

func flag(sig):
    return SignalFlag(sig)
