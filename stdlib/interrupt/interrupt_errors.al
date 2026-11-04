# alex: native
#
# ALEX STANDARD LIBRARY — interrupt.interrupt_errors
#
# Erreurs du paquet interrupt, et décodage lisible des EXCEPTIONS du processeur x86-64 (nom, mnémonique,
# signification du code d'erreur : faute de page — présent, écriture, utilisateur, réservé, instruction —,
# sélecteur fautif d'une protection générale).
#   InterruptError      erreur générale (contrôleur absent, ligne invalide)
#   VectorExhausted     plus de vecteur libre dans la plage demandée
#   InvalidVector       vecteur hors 0..255, ou utilisé dans une plage qui n'est pas la sienne
#   HandlerError        gestionnaire en double, inconnu, ou qui a échoué
#
#   use interrupt.interrupt_errors as ierr
#   print(ierr.exception_name(14), ierr.mnemonic(14))          # faute de page #PF
#   print(ierr.page_fault_text(0x6))                            # « page absente, écriture, mode utilisateur »
#   print(ierr.describe_exception(13, 0x18))                    # « #GP protection générale (sélecteur 0x18, GDT) »
#   ierr.check_vector(300)                                      # InvalidVector
#
# Module du sous-ensemble natif (noyau --freestanding ou VM).

from core use len
from collections use append
use interrupt.interrupt_types as it

const INTERRUPT := "InterruptError"
const EXHAUSTED := "VectorExhausted"
const INVALID := "InvalidVector"
const HANDLER := "HandlerError"

func fail(message: str):
    raise(INTERRUPT, message)

func check_vector(v: int):
    if v < 0 or v > 255:
        raise(INVALID, "vecteur " + str(v) + " hors de 0..255")

func check_irq(irq: int, lines: int):
    if irq < 0 or irq >= lines:
        raise(INTERRUPT, "ligne d'interruption " + str(irq) + " hors de 0.." + str(lines - 1))

func exception_name(v: int) -> str:
    match v:
        0:
            return "division par zéro"
        1:
            return "débogage"
        2:
            return "interruption non masquable"
        3:
            return "point d'arrêt"
        4:
            return "dépassement"
        5:
            return "dépassement de bornes"
        6:
            return "instruction invalide"
        7:
            return "coprocesseur indisponible"
        8:
            return "double faute"
        10:
            return "TSS invalide"
        11:
            return "segment absent"
        12:
            return "faute de pile"
        13:
            return "protection générale"
        14:
            return "faute de page"
        16:
            return "erreur du x87"
        17:
            return "contrôle d'alignement"
        18:
            return "vérification machine"
        19:
            return "erreur SIMD"
        20:
            return "virtualisation"
        21:
            return "protection du flot de contrôle"
        _:
            return "exception " + str(v)

func mnemonic(v: int) -> str:
    match v:
        0:
            return "#DE"
        1:
            return "#DB"
        2:
            return "NMI"
        3:
            return "#BP"
        4:
            return "#OF"
        5:
            return "#BR"
        6:
            return "#UD"
        7:
            return "#NM"
        8:
            return "#DF"
        10:
            return "#TS"
        11:
            return "#NP"
        12:
            return "#SS"
        13:
            return "#GP"
        14:
            return "#PF"
        16:
            return "#MF"
        17:
            return "#AC"
        18:
            return "#MC"
        19:
            return "#XM"
        20:
            return "#VE"
        21:
            return "#CP"
        _:
            return "#" + str(v)

func _join(parts: list[str]) -> str:
    if len(parts) == 0:
        return ""
    out := parts[0]
    i := 1
    while i < len(parts):
        out = out + ", " + parts[i]
        i += 1
    return out

# Code d'erreur d'une faute de page.
func page_fault_text(code: int) -> str:
    parts: list[str] := []
    if (code & 1) != 0:
        append(parts, "violation de protection")
    else:
        append(parts, "page absente")
    if (code & 2) != 0:
        append(parts, "écriture")
    else:
        append(parts, "lecture")
    if (code & 4) != 0:
        append(parts, "mode utilisateur")
    else:
        append(parts, "mode noyau")
    if (code & 8) != 0:
        append(parts, "bit réservé")
    if (code & 16) != 0:
        append(parts, "lecture d'instruction")
    if (code & 32) != 0:
        append(parts, "clé de protection")
    if (code & 64) != 0:
        append(parts, "pile fantôme")
    return _join(parts)

# Code d'erreur « sélecteur » (#GP, #TS, #NP, #SS).
func selector_text(code: int) -> str:
    if code == 0:
        return "sans sélecteur"
    table := "GDT"
    t := (code >> 1) & 3
    if t == 1 or t == 3:
        table = "IDT"
    elif t == 2:
        table = "LDT"
    ext := ""
    if (code & 1) != 0:
        ext = ", externe"
    return "sélecteur 0x" + _hex(code & 0xFFF8) + ", " + table + ext

func _hex(v: int) -> str:
    d := "0123456789abcdef"
    if v == 0:
        return "0"
    out := ""
    x := v
    while x > 0:
        out = str(d[x % 16]) + out
        x = x // 16
    return out

func describe_exception(v: int, code: int) -> str:
    t := mnemonic(v) + " " + exception_name(v)
    if v == 14:
        return t + " (" + page_fault_text(code) + ")"
    if it.has_error_code(v) and v != 8:
        return t + " (" + selector_text(code) + ")"
    return t

func is_interrupt_error(t: str) -> bool:
    return t == INTERRUPT or t == EXHAUSTED or t == INVALID or t == HANDLER
