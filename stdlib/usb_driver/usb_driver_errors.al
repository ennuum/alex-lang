# alex: native
# ALEX STANDARD LIBRARY — usb_driver.usb_driver_errors
#
# Erreurs des pilotes USB du noyau et décodage des états de transfert :
#   UsbDriverError   erreur générale            UsbStall     le périphérique a refusé (STALL : requête non
#   UsbTimeout       pas de réponse (CRC/délai)              prise en charge ou point d'accès arrêté)
#   UsbBabble        le périphérique a envoyé plus que prévu UsbProtocolError  descripteur / réponse incohérent
#   - état d'un descripteur de transfert UHCI (actif, STALL, tampon, babble, NAK, CRC/délai, bit stuffing)
#     en texte et en type d'erreur ;
#   - recovery_hint : que faire (CLEAR_FEATURE(HALT), réinitialiser le port, réessayer).
#
#   use usb_driver.usb_driver_errors as ude
#   t := ude.uhci_error_type(etat_td)      # "UsbStall"...
#   print(ude.uhci_status_text(etat_td), ude.recovery_hint(t))
#
# Compilable en natif (# alex: native).

const DRIVER := "UsbDriverError"
const STALL := "UsbStall"
const TIMEOUT := "UsbTimeout"
const BABBLE := "UsbBabble"
const PROTOCOL := "UsbProtocolError"

const TD_ACTIVE := 0x800000
const TD_STALLED := 0x400000
const TD_BUFERR := 0x200000
const TD_BABBLE := 0x100000
const TD_NAK := 0x80000
const TD_CRCTO := 0x40000
const TD_BITSTUFF := 0x20000

func is_usb_driver_error(t: str) -> bool:
    return t == DRIVER or t == STALL or t == TIMEOUT or t == BABBLE or t == PROTOCOL

func _add(t: str, p: str) -> str:
    if t == "":
        return p
    return t + ", " + p

func uhci_status_text(st: int) -> str:
    t := ""
    if st & TD_ACTIVE != 0:
        t = _add(t, "actif")
    if st & TD_STALLED != 0:
        t = _add(t, "STALL")
    if st & TD_BUFERR != 0:
        t = _add(t, "erreur de tampon")
    if st & TD_BABBLE != 0:
        t = _add(t, "babble")
    if st & TD_NAK != 0:
        t = _add(t, "NAK")
    if st & TD_CRCTO != 0:
        t = _add(t, "CRC / délai")
    if st & TD_BITSTUFF != 0:
        t = _add(t, "bit stuffing")
    if t == "":
        return "terminé sans erreur"
    return t

# Type d'erreur d'un TD terminé ("" : pas d'erreur).
func uhci_error_type(st: int) -> str:
    if st & TD_BABBLE != 0:
        return BABBLE
    if st & TD_STALLED != 0 and st & (TD_CRCTO | TD_BITSTUFF | TD_BUFERR) == 0:
        return STALL
    if st & (TD_CRCTO | TD_BITSTUFF) != 0:
        return TIMEOUT
    if st & TD_BUFERR != 0:
        return DRIVER
    return ""

func recovery_hint(t: str) -> str:
    if t == STALL:
        return "envoyer CLEAR_FEATURE(ENDPOINT_HALT) au point d'accès, remettre la bascule de données à 0"
    if t == TIMEOUT:
        return "réessayer ; si cela persiste, réinitialiser le port (câble, alimentation)"
    if t == BABBLE:
        return "réinitialiser le port : le périphérique ne respecte plus la taille de paquet"
    if t == PROTOCOL:
        return "relire les descripteurs ; vérifier la configuration choisie"
    return "réessayer"

func check_td(who: str, st: int):
    t := uhci_error_type(st)
    if t != "":
        raise(t, who + " : " + uhci_status_text(st) + " — " + recovery_hint(t))

func protocol_error(who: str, what: str):
    raise(PROTOCOL, who + " : " + what)
