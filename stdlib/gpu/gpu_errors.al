# ALEX STANDARD LIBRARY — gpu.gpu_errors
#
# Erreurs du calcul sur carte graphique et diagnostic de l'accès aux cartes :
#   GpuError            erreur générale
#   GpuUnavailable      aucune carte utilisable (nœuds /dev/dri absents ou illisibles)
#   DeviceLost          périphérique perdu (réinitialisation, retrait) : les tampons et files sont invalides
#   OutOfDeviceMemory   mémoire du périphérique épuisée (gpu_memory signale MemoryError, reconnue ici aussi)
#   QueueError          soumission invalide (file fermée, commande inconnue, tampon libéré)
#   FenceTimeout        attente d'une barrière dépassée
#
#   use gpu.gpu_errors as ge
#   print(ge.diagnose())        # {"cards": [...], "render_nodes": [...], "accessible": [...], "advice": ...}
#   try:
#       file.submit(cmds).wait(1.0)
#   catch e:
#       if ge.is_recoverable(e.type):
#           ...                 # recommencer après avoir libéré de la mémoire
#
# Erreurs : celles ci-dessus.

from core use len
from collections use append
use string as _s
use os as _os
use hardware._sys as _sys
use hardware.permissions as _perm

const GPU := "GpuError"
const UNAVAILABLE := "GpuUnavailable"
const DEVICE_LOST := "DeviceLost"
const OUT_OF_MEMORY := "OutOfDeviceMemory"
const QUEUE := "QueueError"
const FENCE_TIMEOUT := "FenceTimeout"

func is_gpu_error(t):
    return t == GPU or t == UNAVAILABLE or t == DEVICE_LOST or t == OUT_OF_MEMORY or t == QUEUE or t == FENCE_TIMEOUT

# Erreurs après lesquelles on peut réessayer sans recréer le périphérique.
func is_recoverable(t):
    return t == OUT_OF_MEMORY or t == "MemoryError" or t == FENCE_TIMEOUT

# Type d'erreur probable d'après un message (pilote, nvidia-smi, journal du noyau).
func classify(message):
    m := _s.lower(message)
    if _s.contains(m, "out of memory") or _s.contains(m, "mémoire du périphérique épuisée"):
        return OUT_OF_MEMORY
    if _s.contains(m, "device lost") or _s.contains(m, "gpu has fallen off") or _s.contains(m, "xid") or _s.contains(m, "ring timeout") or _s.contains(m, "gpu reset"):
        return DEVICE_LOST
    if _s.contains(m, "permission denied") or _s.contains(m, "no devices were found") or _s.contains(m, "couldn't communicate"):
        return UNAVAILABLE
    if _s.contains(m, "timeout"):
        return FENCE_TIMEOUT
    return GPU

func diagnose():
    cards := []
    renders := []
    accessible := []
    d := _sys.p("/dev/dri")
    if _os.isdir(d):
        for n in _os.list_dir(d):
            p := "/dev/dri/" + n
            if _s.starts_with(n, "card"):
                append(cards, p)
            elif _s.starts_with(n, "renderD"):
                append(renders, p)
            else:
                continue
            if _perm.can_read(p) and _perm.can_write(p):
                append(accessible, p)
    nv := _sys.find_tool(["nvidia-smi"]) != null
    advice := null
    if len(cards) + len(renders) == 0:
        advice = "aucune carte /dev/dri : calcul logiciel seulement (gpu.gpu_device.software)"
    elif len(accessible) == 0:
        advice = "nœuds /dev/dri inaccessibles : ajouter l'utilisateur aux groupes « render » et « video »"
    return {"cards": cards, "render_nodes": renders, "accessible": accessible, "nvidia_smi": nv,
            "advice": advice, "ok": len(accessible) > 0}
