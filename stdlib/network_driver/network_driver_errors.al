# alex: native
# ALEX STANDARD LIBRARY — network_driver.network_driver_errors
#
# Erreurs des pilotes réseau et vérification des trames :
#   NetworkDriverError   erreur générale         LinkDown       lien physique absent
#   RingFull             anneau d'émission plein NoBuffer       plus de tampon de réception
#   FrameError           trame trop courte / longue, FCS (CRC) faux, en-tête incohérent
#   OffloadError         fonction de délestage non prise en charge ou paramètres incohérents
#   - frame_problem : texte du problème d'une trame (ou "") d'après sa longueur, son FCS éventuel, son
#     en-tête VLAN ;
#   - fonctions qui lèvent ces erreurs avec le nom de l'interface.
#
#   use network_driver.network_driver_errors as nde
#   p := nde.frame_problem(addr, n, true)    # true : la trame se termine par son FCS
#   if p != "": nde.frame_error("eth0", p)
#
# Compilable en natif (# alex: native).

use hw
use network_driver.ethernet as eth

const DRIVER := "NetworkDriverError"
const LINK_DOWN := "LinkDown"
const RING_FULL := "RingFull"
const NO_BUFFER := "NoBuffer"
const FRAME := "FrameError"
const OFFLOAD := "OffloadError"

func is_network_driver_error(t: str) -> bool:
    return t == DRIVER or t == LINK_DOWN or t == RING_FULL or t == NO_BUFFER or t == FRAME or t == OFFLOAD

# Problème d'une trame de n octets en addr ("" si elle est correcte) ; with_fcs : les 4 derniers octets sont
# la séquence de contrôle (CRC-32 petit-boutiste).
func frame_problem(addr: int, n: int, with_fcs: bool) -> str:
    fcs := 4 if with_fcs else 0
    if n < eth.HEADER + fcs:
        return "trame de " + str(n) + " octets : en-tête incomplet"
    body := n - fcs
    if body < eth.MIN_FRAME:
        return "trame courte (« runt ») : " + str(body) + " octets < " + str(eth.MIN_FRAME)
    limit := eth.MAX_FRAME
    if eth.type_of(addr) == eth.TYPE_VLAN or eth.read16be(addr + 12) == eth.TYPE_VLAN:
        limit = eth.MAX_FRAME + 4
    if body > limit:
        return "trame trop longue (« giant ») : " + str(body) + " octets > " + str(limit)
    if with_fcs:
        want := eth.crc32_at(addr, body)
        got := hw.peek32(addr + body)
        if want != got:
            return "FCS faux (CRC-32)"
    return ""

func check_frame(iface: str, addr: int, n: int, with_fcs: bool):
    p := frame_problem(addr, n, with_fcs)
    if p != "":
        raise(FRAME, iface + " : " + p)

func link_down(iface: str):
    raise(LINK_DOWN, iface + " : lien absent (câble, partenaire, négociation)")

func ring_full(iface: str, size: int):
    raise(RING_FULL, iface + " : anneau d'émission plein (" + str(size) + " descripteurs)")

func no_buffer(iface: str):
    raise(NO_BUFFER, iface + " : plus de tampon de réception libre")

func offload_error(iface: str, what: str):
    raise(OFFLOAD, iface + " : " + what)
