# alex: native
# ALEX STANDARD LIBRARY — driver.driver_registry
#
# Registre des pilotes disponibles : enregistrement, recherche par nom, choix du pilote le plus précis pour un
# périphérique (score de DriverInfo.matches ; à égalité, le premier enregistré), liste des candidats.
#
#   r := DriverRegistry()
#   r.add(Ahci())
#   r.add(AtaPio())
#   d := r.best_for(dev)          # Driver?, celui dont l'identifiant correspond le mieux
#
# Compilable en natif (# alex: native).

from collections use append
from core use len
use driver.driver as drv
from driver.driver use Driver
use driver.driver_info as di
from driver.driver_info use HwDevice

class DriverRegistry:
    drivers: list[Driver] := []

    func init():
        self.drivers = []

    # Ajoute un pilote ; DeviceBusy si un pilote du même nom est déjà enregistré.
    func add(d: Driver):
        n := d.info().name
        for x in self.drivers:
            if x.info().name == n:
                raise("DeviceBusy", "registre : pilote '" + n + "' déjà enregistré")
        append(self.drivers, d)

    func remove(name: str) -> bool:
        keep: list[Driver] := []
        found := false
        for x in self.drivers:
            if x.info().name == name:
                found = true
            else:
                append(keep, x)
        self.drivers = keep
        return found

    func find(name: str) -> Driver?:
        for x in self.drivers:
            if x.info().name == name:
                return x
        return null

    func count() -> int:
        return len(self.drivers)

    func names() -> list[str]:
        out: list[str] := []
        for x in self.drivers:
            append(out, x.info().name)
        return out

    # Pilotes qui reconnaissent dev, du plus précis au moins précis.
    func candidates(dev: HwDevice) -> list[Driver]:
        scored: list[int] := []
        ds: list[Driver] := []
        for x in self.drivers:
            s := x.info().matches(dev)
            if s > 0:
                # insertion triée par score décroissant (stable)
                i := 0
                while i < len(scored) and scored[i] >= s:
                    i += 1
                ns: list[int] := []
                nd: list[Driver] := []
                k := 0
                while k < len(scored):
                    if k == i:
                        append(ns, s)
                        append(nd, x)
                    append(ns, scored[k])
                    append(nd, ds[k])
                    k += 1
                if i == len(scored):
                    append(ns, s)
                    append(nd, x)
                scored = ns
                ds = nd
        return ds

    func best_for(dev: HwDevice) -> Driver?:
        c := self.candidates(dev)
        if len(c) == 0:
            return null
        return c[0]

    func describe() -> str:
        out := ""
        for x in self.drivers:
            out = out + x.info().describe() + "\n"
        return out
