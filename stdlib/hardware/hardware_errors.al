# ALEX STANDARD LIBRARY — hardware.hardware_errors
#
# Erreurs d'accès au matériel depuis une application, et diagnostic d'un nœud de périphérique :
#   HardwareError          erreur générale
#   HardwareUnavailable    périphérique absent (non branché, pilote non chargé, machine virtuelle)
#   HardwareAccessDenied   droits insuffisants sur /dev ou /sys (groupe, root, capacité)
#   HardwareBusy           périphérique déjà ouvert de façon exclusive par un autre programme
#   ResourceConflict       ressources (ports, mémoire, interruption) revendiquées deux fois
#   BusError               opération de bus impossible (liaison / déliaison de pilote, rescan)
#   - diagnose(chemin) : existe ? type (caractère / bloc / fichier) ? lisible / modifiable ? groupe à
#     rejoindre ? conseil ;
#   - classify(message) : type d'erreur d'après un message système (EACCES, EBUSY, ENODEV, ENOENT...) ;
#   - explain(type) : explication et remède en français.
#
#   use hardware.hardware_errors as he
#   print(he.diagnose("/dev/video0"))     # {"path":..., "exists": false, "advice": "absent : ..."}
#   he.require_access("/dev/ttyUSB0", "rw")
#
# Erreurs : celles ci-dessus.

from core use len
from collections use append, contains_key
use string as _s
use os as _os
use hardware._sys as _sys
use hardware.permissions as _perm

const HARDWARE := "HardwareError"
const UNAVAILABLE := "HardwareUnavailable"
const ACCESS := "HardwareAccessDenied"
const BUSY := "HardwareBusy"
const CONFLICT := "ResourceConflict"
const BUS := "BusError"

func is_hardware_error(t):
    return t == HARDWARE or t == UNAVAILABLE or t == ACCESS or t == BUSY or t == CONFLICT or t == BUS

func classify(message):
    m := _s.lower(message)
    if _s.contains(m, "permission denied") or _s.contains(m, "eacces") or _s.contains(m, "operation not permitted") or _s.contains(m, "eperm"):
        return ACCESS
    if _s.contains(m, "busy") or _s.contains(m, "ebusy"):
        return BUSY
    if _s.contains(m, "no such device") or _s.contains(m, "enodev") or _s.contains(m, "no such file") or _s.contains(m, "enoent") or _s.contains(m, "enxio"):
        return UNAVAILABLE
    if _s.contains(m, "conflict") or _s.contains(m, "already claimed"):
        return CONFLICT
    return HARDWARE

func explain(t):
    if t == UNAVAILABLE:
        return "périphérique absent : vérifier le branchement, que le pilote est chargé (lsmod) et, en machine virtuelle, que le périphérique est transmis"
    if t == ACCESS:
        return "droits insuffisants : rejoindre le groupe du nœud (puis se reconnecter), ou ajouter une règle udev"
    if t == BUSY:
        return "périphérique occupé : un autre programme l'utilise (fuser / lsof sur le nœud)"
    if t == CONFLICT:
        return "conflit de ressources : deux pilotes revendiquent la même zone (voir /proc/iomem, /proc/ioports)"
    if t == BUS:
        return "opération de bus refusée : il faut être root, et le pilote doit accepter le périphérique"
    return "erreur matérielle"

# État d'un nœud : dict path, exists, kind, readable, writable, owner_group, advice.
func diagnose(path):
    out := {"path": path, "exists": false, "kind": null, "readable": false, "writable": false, "group": null, "advice": null}
    if not _sys.exists(path):
        out["advice"] = "absent : " + explain(UNAVAILABLE)
        return out
    out["exists"] = true
    a := _perm.check(path)
    out["kind"] = a.kind
    r := a.rights()
    out["readable"] = _s.contains(r, "r")
    out["writable"] = _s.contains(r, "w")
    out["group"] = a.group_name
    if not out["readable"]:
        g := out["group"]
        out["advice"] = "illisible : " + explain(ACCESS) + (" (groupe « " + str(g) + " »)" if g != null else "")
    return out

# Lève HardwareUnavailable / HardwareAccessDenied si path n'est pas utilisable dans le mode demandé
# (« r », « w », « rw »).
func require_access(path, mode="r"):
    d := diagnose(path)
    if not d["exists"]:
        raise(UNAVAILABLE, path + " : " + explain(UNAVAILABLE))
    if _s.contains(mode, "r") and not d["readable"]:
        raise(ACCESS, path + " : lecture refusée — " + explain(ACCESS))
    if _s.contains(mode, "w") and not d["writable"]:
        raise(ACCESS, path + " : écriture refusée — " + explain(ACCESS))
    return d

# Relance une erreur système avec le type matériel approprié et le chemin.
func wrap(path, e):
    t := classify(e.message)
    raise(t, path + " : " + e.message + " — " + explain(t))
