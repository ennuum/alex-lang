# ALEX STANDARD LIBRARY — signal.signal_errors
#
# Erreurs des signaux :
#   SignalError      échec système (sigaction, kill...)
#   InterruptError   levée par un gestionnaire interrupt_on (Ctrl+C), ou un arrêt forcé
#   ArgumentError    signal inconnu, ou non interceptable (KILL, STOP, fautes)
#   ThreadError      interception demandée depuis un fil (seul le programme principal intercepte)
#   ProcessError     envoi vers un processus absent
#   SignalMaskError  déblocage d'un signal qui n'était pas bloqué, masques mal imbriqués
#
#   use signal.signal_errors as se
#   try:
#       travail()
#   catch e:
#       if se.is_interrupt(e):
#           nettoyer()
#       print(se.explain(e.type))

const SIGNAL := "SignalError"
const INTERRUPT := "InterruptError"
const MASK := "SignalMaskError"
const THREAD := "ThreadError"

func kinds():
    return [SIGNAL, INTERRUPT, MASK, THREAD, "ArgumentError", "ProcessError"]

func is_signal_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func is_interrupt(e):
    return e.type == INTERRUPT

func explain(error_type):
    if error_type == INTERRUPT:
        return "interruption demandée (Ctrl+C, ou signal transformé en exception)"
    if error_type == SIGNAL:
        return "le système a refusé l'opération sur le signal"
    if error_type == MASK:
        return "masque de signaux incohérent (déblocage sans blocage préalable, ou ordre d'imbrication)"
    if error_type == THREAD:
        return "seul le programme principal peut intercepter les signaux"
    if error_type == "ArgumentError":
        return "signal inconnu, ou impossible à intercepter (KILL, STOP, SEGV, BUS, FPE, ILL)"
    if error_type == "ProcessError":
        return "le processus visé n'existe pas"
    return "erreur " + str(error_type)

func mask_error(fn, message):
    raise(MASK, fn + " : " + message)
