# alex: native
# ALEX STANDARD LIBRARY — driver.device_binding
#
# Lien entre un périphérique (driver_info.HwDevice) et le pilote qui le gère : état (lié, échec, détaché),
# erreur éventuelle, nombre de tentatives. Le DriverManager crée les liens ; un pilote peut retrouver le sien.
#
#   b := Binding(pilote, dev)
#   b.bind()                    # probe puis attach ; capture l'erreur
#   print(b.describe())         # « pci 00:03.0 Intel 82540EM -> e1000 : lié »
#   b.unbind()
#
# Compilable en natif (# alex: native).

use driver.driver as drv
from driver.driver use Driver
use driver.driver_info as di
from driver.driver_info use HwDevice

const UNBOUND := 0
const BOUND := 1
const FAILED := 2
const REJECTED := 3       # probe a répondu non

func state_name(s: int) -> str:
    if s == BOUND:
        return "lié"
    if s == FAILED:
        return "échec"
    if s == REJECTED:
        return "refusé par probe"
    return "non lié"

class Binding:
    driver: Driver
    device: HwDevice
    state: int := 0
    error: str := ""
    error_type: str := ""
    attempts: int := 0

    func init(driver: Driver, device: HwDevice):
        self.driver = driver
        self.device = device
        self.state = UNBOUND
        self.error = ""
        self.error_type = ""
        self.attempts = 0

    func driver_name() -> str:
        return self.driver.info().name

    # probe puis attach ; renvoie vrai si le pilote a pris le périphérique.
    func bind() -> bool:
        self.attempts += 1
        try:
            if not self.driver.probe(self.device):
                self.state = REJECTED
                return false
            self.driver.attach(self.device)
            self.state = BOUND
            self.device.state = "lié"
            self.error = ""
            return true
        catch e:
            self.state = FAILED
            self.error = e.message
            self.error_type = e.type
            self.device.state = "échec"
            return false

    func unbind():
        if self.state == BOUND:
            try:
                self.driver.detach(self.device)
            catch e:
                self.error = e.message
                self.error_type = e.type
            self.device.state = "retiré"
        self.state = UNBOUND

    func bound() -> bool:
        return self.state == BOUND

    func status() -> str:
        if self.state != BOUND:
            return state_name(self.state)
        try:
            return self.driver.status(self.device)
        catch e:
            return "erreur : " + e.message

    func describe() -> str:
        t := self.device.describe() + " -> " + self.driver_name() + " : " + state_name(self.state)
        if self.state == FAILED:
            t = t + " (" + self.error_type + " : " + self.error + ")"
        return t
