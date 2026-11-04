# ALEX STANDARD LIBRARY — ipc.ipc_errors
#
# Erreurs de la communication interprocessus :
#   IpcError            échec système (shm_open, mq_open, socket...), plateforme non prise en charge
#   IpcExistsError      création exclusive d'un objet qui existe déjà (mode "create")
#   IpcNotFoundError    ouverture d'un objet absent (mode "open")
#   IpcPermissionError  droits insuffisants sur l'objet
#   MessageError        message mal formé, trop grand, version ou empreinte invalide (ipc.ipc_message)
#   TimeoutError        délai dépassé (réception, sémaphore, connexion)
#   ProtocolError       échange incohérent (réponse sans demande...)
#
#   use ipc.ipc_errors as ie
#   t := ie.from_errno("EEXIST")              # "IpcExistsError"
#   try:
#       ...
#   catch e:
#       if ie.is_ipc_error(e.type):
#           print(ie.explain(e.type))

use string as _s

const IPC := "IpcError"
const EXISTS := "IpcExistsError"
const NOT_FOUND := "IpcNotFoundError"
const PERMISSION := "IpcPermissionError"
const MESSAGE := "MessageError"
const TIMEOUT := "TimeoutError"
const PROTOCOL := "ProtocolError"

func kinds():
    return [IPC, EXISTS, NOT_FOUND, PERMISSION, MESSAGE, TIMEOUT, PROTOCOL]

func is_ipc_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

# Nom errno (EEXIST, ENOENT, EACCES...) -> type d'erreur.
func from_errno(name):
    if name == "EEXIST":
        return EXISTS
    if name == "ENOENT":
        return NOT_FOUND
    if name == "EACCES" or name == "EPERM":
        return PERMISSION
    if name == "ETIMEDOUT" or name == "EAGAIN":
        return TIMEOUT
    if name == "EMSGSIZE":
        return MESSAGE
    return IPC

# Type précis d'après le message d'une IpcError (« ... [EEXIST] »).
func classify(e):
    if e.type != IPC:
        return e.type
    for name in ["EEXIST", "ENOENT", "EACCES", "EPERM", "ETIMEDOUT", "EAGAIN", "EMSGSIZE"]:
        if _s.contains(e.message, name):
            return from_errno(name)
    return IPC

# Relance e avec son type précis.
func refine(e):
    t := classify(e)
    if t == e.type:
        raise(e)
    raise(t, e.message)

func explain(error_type):
    if error_type == EXISTS:
        return "l'objet existe déjà (mode « create » exclusif) : l'ouvrir, ou le supprimer d'abord (unlink)"
    if error_type == NOT_FOUND:
        return "l'objet n'existe pas (mode « open ») : un autre processus doit le créer d'abord"
    if error_type == PERMISSION:
        return "droits insuffisants : objet créé par un autre utilisateur (voir ipc.ipc_permissions)"
    if error_type == MESSAGE:
        return "message invalide : format, taille ou empreinte"
    if error_type == TIMEOUT:
        return "délai dépassé : aucun correspondant n'a répondu"
    if error_type == PROTOCOL:
        return "échange incohérent entre les deux processus"
    return "erreur de communication interprocessus"

func message_error(fn, message):
    raise(MESSAGE, fn + " : " + message)
