# ALEX STANDARD LIBRARY — usb.usb_errors
#
# Erreurs USB et diagnostic : les types d'erreur du paquet usb, la traduction des codes errno renvoyés par
# usbfs (EPIPE = point d'accès bloqué / STALL, ETIMEDOUT, ENODEV = débranché, EACCES = droits, EBUSY =
# interface tenue par un pilote du noyau, EOVERFLOW = paquet trop grand...), la décision « réessayer ? », et
# une règle udev prête à installer pour donner l'accès à un périphérique sans être root.
#   UsbError            erreur générale (paquet usb)
#   UsbAccessError      droits insuffisants sur /dev/bus/usb
#   UsbStall            point d'accès bloqué (STALL) : requête refusée par le périphérique
#   UsbTimeout          délai dépassé
#   UsbDisconnected     périphérique débranché pendant l'opération
#   UsbBusy             interface déjà réclamée (pilote du noyau ou autre programme)
#
#   use usb.usb_errors as uerr
#   f := uerr.from_errno("EPIPE")      # {"type": "UsbStall", "retry": "clear_halt", "explanation": ...}
#   uerr.raise_errno("EACCES", "ouverture de 1-1.2")      # lève UsbAccessError avec la solution
#   print(uerr.udev_rule(0x046d, 0xc52b))                 # SUBSYSTEM=="usb", ATTR{idVendor}=="046d", ...
#
# Erreurs : celles ci-dessus.

from core use len, type
use string as _s

const USB := "UsbError"
const ACCESS := "UsbAccessError"
const STALL := "UsbStall"
const TIMEOUT := "UsbTimeout"
const DISCONNECTED := "UsbDisconnected"
const BUSY := "UsbBusy"

const _TABLE := {
    "EPIPE": ["UsbStall", "clear_halt", "le point d'accès est bloqué (STALL) : la requête a été refusée ; envoyer CLEAR_FEATURE(ENDPOINT_HALT) avant de réessayer"],
    "ETIMEDOUT": ["UsbTimeout", "retry", "le périphérique n'a pas répondu dans le délai"],
    "ENODEV": ["UsbDisconnected", "none", "le périphérique a été débranché"],
    "ESHUTDOWN": ["UsbDisconnected", "none", "le périphérique ou son contrôleur a été arrêté"],
    "EACCES": ["UsbAccessError", "none", "droits insuffisants sur /dev/bus/usb : installer une règle udev (udev_rule) ou exécuter en root"],
    "EPERM": ["UsbAccessError", "none", "opération non permise"],
    "EBUSY": ["UsbBusy", "detach", "interface déjà réclamée : détacher le pilote du noyau (claim(n, true)) ou fermer l'autre programme"],
    "EOVERFLOW": ["UsbError", "none", "le périphérique a envoyé plus de données que le tampon n'en accepte"],
    "EPROTO": ["UsbError", "retry", "erreur de protocole sur le bus (câble, alimentation, interférences)"],
    "EILSEQ": ["UsbError", "retry", "erreur de CRC sur le bus"],
    "ENOENT": ["UsbError", "none", "requête annulée ou point d'accès inexistant"],
    "EINVAL": ["UsbError", "none", "paramètre invalide (point d'accès, longueur, interface non réclamée)"],
    "ENOMEM": ["UsbError", "retry", "mémoire insuffisante pour le transfert"],
    "EAGAIN": ["UsbError", "retry", "ressource temporairement indisponible"]}

func from_errno(name):
    if name in _TABLE:
        t := _TABLE[name]
        return {"errno": name, "type": t[0], "retry": t[1], "explanation": t[2]}
    return {"errno": name, "type": USB, "retry": "none", "explanation": "erreur système " + str(name)}

func raise_errno(name, context="usb"):
    f := from_errno(name)
    raise(f["type"], context + " : " + f["explanation"] + " [" + name + "]")

# Code errno à la fin d'un message (« ... [EPIPE] » ou « (EPIPE ...) »), ou null.
func errno_in(message):
    for k in _TABLE:
        if _s.contains(message, k):
            return k
    return null

func classify(e):
    en := errno_in(e.message)
    if en != null:
        return from_errno(en)
    return {"errno": null, "type": e.type, "retry": "none", "explanation": e.message}

func is_transient(e):
    r := classify(e)["retry"]
    return r == "retry" or r == "clear_halt"

func _hex4(v):
    d := "0123456789abcdef"
    out := ""
    x := v
    i := 0
    while i < 4:
        out = str(d[x % 16]) + out
        x = x // 16
        i += 1
    return out

# Règle udev donnant l'accès au périphérique (fichier /etc/udev/rules.d/50-alex.rules, puis
# « udevadm control --reload-rules && udevadm trigger »).
func udev_rule(vendor, product, group="plugdev", mode="0660"):
    return "SUBSYSTEM==\"usb\", ATTR{idVendor}==\"" + _hex4(vendor) + "\", ATTR{idProduct}==\"" + _hex4(product) + "\", MODE=\"" + mode + "\", GROUP=\"" + group + "\""

func is_usb_error(t):
    return t == USB or t == ACCESS or t == STALL or t == TIMEOUT or t == DISCONNECTED or t == BUSY
