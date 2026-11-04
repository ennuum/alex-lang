# ALEX STANDARD LIBRARY — system.signal
#
# Signaux du système (POSIX : Linux, macOS) : réagir à Ctrl+C (INT), à une demande d'arrêt (TERM), au
# redimensionnement du terminal (WINCH), à USR1/USR2... et en envoyer à d'autres processus.
#
# Deux façons d'intercepter un signal :
#   on(nom, gestionnaire)   le gestionnaire (une fonction qui reçoit le nom du signal) s'exécute dans le
#                           programme principal, entre deux instructions, dès que le signal arrive ; s'il lève
#                           une exception, elle part de l'endroit où le programme en était (try/finally
#                           s'appliquent). interrupt_on("INT") : lever InterruptError, comme Python.
#   watch(nom)              rien ne s'exécute : le programme interroge received(nom) ou attend wait(...).
# reset(nom) rend le comportement d'origine (souvent : arrêter le programme), ignore(nom) ne fait plus rien.
#
# Limites : un appel bloquant sans délai (lecture d'un tube, accept...) se termine avant que le gestionnaire
# ne s'exécute (time.sleep, lui, s'interrompt) ; utiliser des délais dans les boucles. Seul le programme
# principal intercepte les signaux (pas les fils de concurrency.thread). KILL et STOP ne s'interceptent pas,
# ni les fautes (SEGV, BUS, FPE, ILL).
#
# Exemple
#   use system.signal as signal
#   arret := [false]
#   signal.on("TERM", (nom) => arret[0] = true)
#   while not arret[0]:
#       servir_une_requete(1.0)
#
# Erreurs : ArgumentError (nom inconnu, signal non interceptable), SignalError (système), InterruptError.

from core use len, type
from collections use append, contains_key
use _native_signal as _n
use os as _os

_handlers := {}

func supported():
    return _n.supported()

# Noms connus (sans « SIG ») : HUP, INT, QUIT, TERM, USR1, USR2, WINCH, CHLD, ALRM, PIPE...
func names():
    return _n.names()

# Numéro du signal (« INT », « SIGINT », « int » ou un numéro).
func number(name):
    if type(name) == "int":
        if _n.name(name) == null:
            raise("ArgumentError", "signal : numéro de signal inconnu " + str(name))
        return name
    if type(name) != "str":
        raise("TypeError", "signal : nom (str) ou numéro (int) de signal attendu")
    n := _n.number(name)
    if n < 0:
        raise("ArgumentError", "signal : signal inconnu '" + name + "'")
    return n

# Nom court (« INT ») d'un signal donné par son nom ou son numéro.
func name_of(sig):
    return _n.name(number(sig))

func _check(op, sig, code):
    if code == -1:
        raise("ArgumentError", "signal." + op + " : le signal " + name_of(sig) + " ne peut pas être intercepté ici")
    if code < 0:
        raise("SignalError", "signal." + op + " : " + _n.strerror(code))

func _main_only(op):
    if not _n.is_main_thread():
        raise("ThreadError", "signal." + op + " : seul le programme principal intercepte les signaux")

# Appelé par la VM (programme principal) quand un signal intercepté par on() arrive.
func _dispatch(num):
    if contains_key(_handlers, num):
        h := _handlers[num]
        h(_n.name(num))

# Exécute handler(nom) à chaque arrivée du signal. Renvoie le gestionnaire précédent (ou null).
func on(sig, handler):
    _main_only("on")
    if type(handler) != "function":
        raise("TypeError", "signal.on : fonction attendue")
    n := number(sig)
    previous := null
    if contains_key(_handlers, n):
        previous = _handlers[n]
    _handlers[n] = handler
    _n.set_dispatcher(_dispatch)
    _check("on", n, _n.intercept(n, true))
    return previous

# Le signal (INT par défaut : Ctrl+C) lève InterruptError dans le programme.
func interrupt_on(sig="INT"):
    return on(sig, _raise_interrupt)

func _raise_interrupt(name):
    raise("InterruptError", "signal " + name + " reçu")

# Intercepte le signal sans gestionnaire : received / wait / pending l'observent.
func watch(sig):
    _main_only("watch")
    n := number(sig)
    if contains_key(_handlers, n):
        _handlers[n] = null
    _check("watch", n, _n.intercept(n, false))

# Le signal n'a plus aucun effet.
func ignore(sig):
    _main_only("ignore")
    n := number(sig)
    _handlers[n] = null
    _check("ignore", n, _n.ignore(n))

# Comportement d'origine (celui d'avant la première interception).
func reset(sig):
    _main_only("reset")
    n := number(sig)
    _handlers[n] = null
    _check("reset", n, _n.reset(n))

# Nombre d'arrivées en attente d'un signal surveillé (watch), sans les consommer.
func pending(sig):
    return _n.pending(number(sig))

# Vrai si le signal surveillé est arrivé depuis la dernière fois (consomme les arrivées).
func received(sig):
    return _n.take(number(sig)) > 0

# Attend l'un des signaux surveillés (liste de noms, ou null : n'importe lequel) ; renvoie son nom, ou null
# après timeout secondes. Les gestionnaires de on() continuent de s'exécuter pendant l'attente.
func wait(sigs=null, timeout=null):
    wanted := null
    if sigs != null:
        if type(sigs) != "list":
            sigs = [sigs]
        wanted = [number(s) for s in sigs]
    started := _os.monotonic_time()
    while true:
        if wanted == null:
            got := _n.take_all()
            if len(got) > 0:
                return _n.name(got[0])
        else:
            for n in wanted:
                if _n.take(n) > 0:
                    return _n.name(n)
        left := null
        if timeout != null:
            left = timeout - (_os.monotonic_time() - started)
            if left <= 0:
                return null
        _n.wait(left)

# Exécute fn() avec handler pour le signal, puis remet le gestionnaire précédent (ou le comportement
# d'origine). Renvoie le résultat de fn().
func with_handler(sig, handler, fn):
    previous := on(sig, handler)
    try:
        return fn()
    finally:
        if previous == null:
            reset(sig)
        else:
            on(sig, previous)

# Envoie le signal au processus pid (TERM par défaut).
func send(pid, sig="TERM"):
    r := _n.send(pid, number(sig))
    if r < 0:
        name := _n.errno_name(r)
        if name == "ESRCH":
            raise("ProcessError", "signal.send : aucun processus " + str(pid))
        raise("SignalError", "signal.send : " + _n.strerror(r) + " [" + name + "]")

# Envoie le signal au programme lui-même.
func raise_signal(sig):
    send(_os.pid(), sig)
