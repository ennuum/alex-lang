# ALEX STANDARD LIBRARY — signal
#
# Signaux du système (POSIX) : intercepter, ignorer, attendre, envoyer. Ce paquet réunit system.signal (un
# gestionnaire par signal, surveillance, envoi), signal.signal_handler (plusieurs gestionnaires, priorités,
# groupes, arrêt propre) et signal.signal_constants (numéros, actions par défaut, descriptions).
#
#   use signal
#   signal.on("USR1", (nom) => print("reçu", nom))         # un gestionnaire (remplace le précédent)
#   t := signal.add("HUP", relire_config)                  # un gestionnaire de plus (jeton)
#   arret := signal.graceful_shutdown()                     # INT / TERM : arrêt demandé, puis immédiat
#   signal.send(pid, "TERM")
#   print(signal.wait(["USR2"], 5))                         # après signal.watch("USR2")
#   print(signal.describe("WINCH"), signal.number("USR1"))
#
# Erreurs : ArgumentError (signal inconnu ou non interceptable), SignalError, ProcessError (send vers un
# processus absent), ThreadError (interception depuis un fil), InterruptError (interrupt_on, arrêt forcé).

use system.signal as _sig
use signal.signal_handler as _h
use signal.signal_constants as _c

func supported():
    return _sig.supported()

func names():
    return _sig.names()

func number(sig):
    return _sig.number(sig)

func name_of(sig):
    return _sig.name_of(sig)

func describe(sig):
    return _c.describe(sig)

func default_action(sig):
    return _c.default_action(sig)

func is_catchable(sig):
    return _c.is_catchable(sig)

# ---- un gestionnaire par signal (system.signal) ----
func on(sig, handler):
    return _sig.on(sig, handler)

func interrupt_on(sig="INT"):
    return _sig.interrupt_on(sig)

func watch(sig):
    return _sig.watch(sig)

func ignore(sig):
    return _sig.ignore(sig)

func reset(sig):
    return _sig.reset(sig)

func pending(sig):
    return _sig.pending(sig)

func received(sig):
    return _sig.received(sig)

func wait(sigs=null, timeout=null):
    return _sig.wait(sigs, timeout)

func with_handler(sig, handler, fn):
    return _sig.with_handler(sig, handler, fn)

func send(pid, sig="TERM"):
    return _sig.send(pid, sig)

func raise_signal(sig):
    return _sig.raise_signal(sig)

# ---- plusieurs gestionnaires (signal.signal_handler) ----
func add(sig, handler, priority=0):
    return _h.add(sig, handler, priority, false)

func once(sig, handler, priority=0):
    return _h.once(sig, handler, priority)

func remove(token):
    return _h.remove_token(token)

func clear(sig):
    return _h.clear(sig)

func scoped(sig, handler, body):
    return _h.scoped(sig, handler, body)

func group():
    return _h.HandlerGroup()

func flag(sig):
    return _h.flag(sig)

func graceful_shutdown(callback=null, signals=null, force=true):
    return _h.graceful_shutdown(callback, signals, force)
