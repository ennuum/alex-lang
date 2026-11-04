# alex: native
# ALEX STANDARD LIBRARY — driver.driver_errors
#
# Erreurs des pilotes de périphériques et attente bornée du matériel.
#
# | Type d'erreur        | Quand                                                              |
# |----------------------|--------------------------------------------------------------------|
# | DriverError          | erreur générale du pilote                                          |
# | DeviceNotFound       | le périphérique attendu ne répond pas / est absent                 |
# | DeviceTimeout        | le périphérique n'a pas répondu à temps                            |
# | DeviceBusy           | ressource déjà utilisée (pilote déjà lié, file pleine)             |
# | UnsupportedDevice    | modèle, révision ou mode non pris en charge                        |
# | DeviceIoError        | erreur signalée par le matériel (registre d'état, code d'erreur)   |
#
#   use driver.driver_errors as de
#   if not de.wait_until(() => hw.inb(STATUS) & BSY == 0, 100000):
#       de.timeout("ata", "BSY ne retombe pas")
#   try:
#       ...
#   catch e:
#       if de.is_driver_error(e.type):
#           ...
#
# Compilable en natif (# alex: native).

use hw

const DRIVER_ERROR := "DriverError"
const NOT_FOUND := "DeviceNotFound"
const TIMEOUT := "DeviceTimeout"
const BUSY := "DeviceBusy"
const UNSUPPORTED := "UnsupportedDevice"
const IO_ERROR := "DeviceIoError"

func is_driver_error(kind: str) -> bool:
    return kind == DRIVER_ERROR or kind == NOT_FOUND or kind == TIMEOUT or kind == BUSY or kind == UNSUPPORTED or kind == IO_ERROR

func fail(driver: str, message: str):
    raise(DRIVER_ERROR, driver + " : " + message)

func not_found(driver: str, what: str):
    raise(NOT_FOUND, driver + " : " + what + " introuvable")

func timeout(driver: str, what: str):
    raise(TIMEOUT, driver + " : délai dépassé (" + what + ")")

func busy(driver: str, what: str):
    raise(BUSY, driver + " : " + what + " occupé")

func unsupported(driver: str, what: str):
    raise(UNSUPPORTED, driver + " : " + what + " non pris en charge")

func io_error(driver: str, what: str, status: int):
    raise(IO_ERROR, driver + " : " + what + " (état " + str(status) + ")")

# Répète cond() jusqu'à ce qu'elle soit vraie, au plus tries fois (pause du processeur entre deux essais) ;
# renvoie vrai si la condition a été atteinte.
func wait_until(cond: func() -> bool, tries: int) -> bool:
    i := 0
    while i < tries:
        if cond():
            return true
        hw.pause()
        i += 1
    return false

# Attend que (inb / inl(port) & mask) == value, au plus tries lectures.
func wait_port(port: int, mask: int, value: int, tries: int) -> bool:
    i := 0
    while i < tries:
        if hw.inb(port) & mask == value:
            return true
        hw.pause()
        i += 1
    return false

# Attend que (peek32(addr) & mask) == value (registre MMIO), au plus tries lectures.
func wait_mmio32(addr: int, mask: int, value: int, tries: int) -> bool:
    i := 0
    while i < tries:
        if hw.peek32(addr) & mask == value:
            return true
        hw.pause()
        i += 1
    return false

# Attente active d'environ us microsecondes (lecture du port 0x80 : ~1 µs sur un PC).
func io_delay(us: int):
    i := 0
    while i < us:
        hw.inb(0x80)
        i += 1
