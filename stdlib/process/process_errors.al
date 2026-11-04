# ALEX STANDARD LIBRARY — process.process_errors
#
# Erreurs liées aux processus, et aide au diagnostic :
#   ProcessError          processus absent, code de sortie non nul (check=true), opération impossible
#   ProcessNotFoundError  aucun processus de ce pid (sous-type logique de ProcessError)
#   PermissionError       opération refusée par le système (signal, priorité, limite d'un autre utilisateur)
#   TimeoutError          délai dépassé
#   LimitError            limite de ressource invalide ou refusée
#   IoError               programme introuvable, appel système indisponible
#
#   use process.process_errors as pe
#   try:
#       ...
#   catch e:
#       print(pe.explain(e.type))        # explication en clair
#       if pe.is_process_error(e.type): ...

from core use type

const PROCESS := "ProcessError"
const NOT_FOUND := "ProcessNotFoundError"
const PERMISSION := "PermissionError"
const TIMEOUT := "TimeoutError"
const LIMIT := "LimitError"

func kinds():
    return [PROCESS, NOT_FOUND, PERMISSION, TIMEOUT, LIMIT, "IoError", "ArgumentError"]

func is_process_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

func not_found(fn, pid):
    raise(NOT_FOUND, fn + " : aucun processus " + str(pid))

func permission(fn, what):
    raise(PERMISSION, fn + " : " + what + " refusé par le système (droits insuffisants)")

func need_pid(fn, pid):
    if type(pid) != "int":
        raise("TypeError", fn + " : pid entier attendu (obtenu '" + type(pid) + "')")
    if pid < 0:
        raise("ArgumentError", fn + " : pid négatif " + str(pid))

# Erreur système (errno) -> type d'erreur ALEX.
func from_errno(name):
    if name == "ESRCH":
        return NOT_FOUND
    if name == "EPERM" or name == "EACCES":
        return PERMISSION
    if name == "EINVAL":
        return "ArgumentError"
    if name == "ETIMEDOUT":
        return TIMEOUT
    return PROCESS

func explain(error_type):
    if error_type == NOT_FOUND:
        return "le processus n'existe pas (déjà terminé, ou pid erroné)"
    if error_type == PROCESS:
        return "le processus a échoué ou l'opération demandée n'est pas possible"
    if error_type == PERMISSION:
        return "le système refuse : processus d'un autre utilisateur, ou privilège requis (root, CAP_SYS_NICE...)"
    if error_type == TIMEOUT:
        return "le délai d'attente est dépassé"
    if error_type == LIMIT:
        return "limite de ressource invalide (valeur souple > valeur dure ?) ou hausse refusée"
    if error_type == "IoError":
        return "programme introuvable, tube cassé, ou appel système indisponible sur cette plateforme"
    return "erreur " + str(error_type)
