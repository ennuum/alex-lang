# alex: native
# ALEX STANDARD LIBRARY — driver.driver_loader
#
# Chargement des pilotes à la demande, comme modprobe : un pilote est décrit par une fabrique (nom, fonction
# qui crée le pilote, dépendances, version d'API demandée) ; le chargeur
#   - charge un pilote et ses dépendances dans l'ordre (cycle détecté), vérifie la compatibilité de l'API
#     (driver.driver_version) et l'enregistre dans le DriverManager ;
#   - décharge (refusé si un pilote chargé en dépend ; les périphériques liés sont détachés) ;
#   - liste noire, options par pilote, configuration textuelle :
#         load e1000
#         blacklist pilote-bogue
#         option e1000 mtu=1500 debug=1
#   - autoload : pour chaque périphérique sans pilote, charge les fabriques dont la table d'identifiants le
#     reconnaît (le plus précis d'abord), puis lie.
# Dans le noyau Alex, tout est compilé dans l'image : « charger » veut dire instancier et enregistrer.
#
#   use driver.driver_loader as dld
#   ld := dld.DriverLoader(gestionnaire)
#   ld.add(dld.DriverFactory("e1000", creer_e1000, [], "^1.0"))
#   ld.configure("blacklist vieux\noption e1000 mtu=9000")
#   n := ld.autoload()
#   print(ld.option("e1000", "mtu", "1500"), ld.report())
#
# Erreurs : DriverLoadError (fabrique inconnue, liste noire, dépendance circulaire ou manquante, API
# incompatible, déchargement refusé), DriverVersionError.
# Compilable en natif (# alex: native).

from core use len
from collections use append
use string as _s
from driver.driver use Driver
use driver.driver_info as di
from driver.driver_info use HwDevice
use driver.driver_manager as dmg
from driver.driver_manager use DriverManager
use driver.driver_version as dv

class DriverFactory:
    name: str := ""
    make: func() -> Driver
    depends: list[str] := []
    api: str := "*"

    func init(name: str, make: func() -> Driver, depends: list[str], api: str):
        self.name = name
        self.make = make
        self.depends = depends
        self.api = api

class _Option:
    driver: str := ""
    key: str := ""
    value: str := ""

    func init(driver: str, key: str, value: str):
        self.driver = driver
        self.key = key
        self.value = value

class DriverLoader:
    manager: DriverManager
    factories: list[DriverFactory] := []
    loaded: list[str] := []
    blacklist: list[str] := []
    options: list[_Option] := []
    log: list[str] := []

    func init(manager: DriverManager):
        self.manager = manager
        self.factories = []
        self.loaded = []
        self.blacklist = []
        self.options = []
        self.log = []

    func add(f: DriverFactory):
        for x in self.factories:
            if x.name == f.name:
                raise("DriverLoadError", "fabrique « " + f.name + " » déjà déclarée")
        append(self.factories, f)

    func factory(name: str) -> DriverFactory:
        for f in self.factories:
            if f.name == name:
                return f
        raise("DriverLoadError", "pilote « " + name + " » inconnu")

    func _in(xs: list[str], n: str) -> bool:
        for x in xs:
            if x == n:
                return true
        return false

    func is_loaded(name: str) -> bool:
        return self._in(self.loaded, name)

    func is_blacklisted(name: str) -> bool:
        return self._in(self.blacklist, name)

    func ban(name: str):
        if not self.is_blacklisted(name):
            append(self.blacklist, name)

    func set_option(driver: str, key: str, value: str):
        for o in self.options:
            if o.driver == driver and o.key == key:
                o.value = value
                return
        append(self.options, _Option(driver, key, value))

    func option(driver: str, key: str, fallback: str) -> str:
        for o in self.options:
            if o.driver == driver and o.key == key:
                return o.value
        return fallback

    # Ordre de chargement (dépendances d'abord) ; DriverLoadError pour un cycle.
    func order(name: str) -> list[str]:
        out: list[str] := []
        visiting: list[str] := []
        self._visit(name, out, visiting)
        return out

    func _visit(name: str, out: list[str], visiting: list[str]):
        if self._in(out, name):
            return
        if self._in(visiting, name):
            raise("DriverLoadError", "dépendance circulaire autour de « " + name + " »")
        append(visiting, name)
        f := self.factory(name)
        for d in f.depends:
            self._visit(d, out, visiting)
        append(out, name)

    # Charge name et ses dépendances ; renvoie le nombre de pilotes nouvellement chargés.
    func load(name: str) -> int:
        n := 0
        for x in self.order(name):
            if self.is_loaded(x):
                continue
            if self.is_blacklisted(x):
                raise("DriverLoadError", "pilote « " + x + " » sur liste noire" + ("" if x == name else " (dépendance de « " + name + " »)"))
            f := self.factory(x)
            if not dv.api_compatible(f.api):
                raise("DriverLoadError", "pilote « " + x + " » demande l'API " + f.api + ", cadre " + dv.API_VERSION)
            mk := f.make
            d := mk()
            if not dv.is_valid(d.info().version):
                raise("DriverLoadError", "pilote « " + x + " » : version « " + d.info().version + " » mal formée")
            self.manager.register(d)
            append(self.loaded, x)
            append(self.log, "chargé " + x + " " + d.info().version)
            n += 1
        return n

    # Pilotes chargés qui dépendent de name.
    func dependents(name: str) -> list[str]:
        out: list[str] := []
        for x in self.loaded:
            f := self.factory(x)
            for d in f.depends:
                if d == name:
                    append(out, x)
        return out

    func unload(name: str):
        if not self.is_loaded(name):
            raise("DriverLoadError", "pilote « " + name + " » non chargé")
        deps := self.dependents(name)
        if len(deps) > 0:
            raise("DriverLoadError", "« " + name + " » utilisé par " + _s.join(", ", deps))
        for b in self.manager.bindings:
            if b.bound() and b.driver_name() == name:
                b.unbind()
        self.manager.registry.remove(name)
        keep: list[str] := []
        for x in self.loaded:
            if x != name:
                append(keep, x)
        self.loaded = keep
        append(self.log, "déchargé " + name)

    # Lignes « load nom », « blacklist nom », « option nom clé=valeur ... » ; # commentaires.
    func configure(text: str) -> int:
        n := 0
        for line in _s.split(text, "\n"):
            t := _s.trim(line)
            if t == "" or _s.starts_with(t, "#"):
                continue
            words: list[str] := []
            for w in _s.split(t, " "):
                if w != "":
                    append(words, w)
            if len(words) < 2:
                raise("DriverLoadError", "configuration : ligne « " + t + " » incomplète")
            cmd := words[0]
            if cmd == "load":
                self.load(words[1])
            elif cmd == "blacklist":
                self.ban(words[1])
            elif cmd == "option":
                i := 2
                while i < len(words):
                    k := _s.find(words[i], "=")
                    if k <= 0:
                        raise("DriverLoadError", "option « " + words[i] + " » : clé=valeur attendu")
                    self.set_option(words[1], _s.substring(words[i], 0, k), _s.substring(words[i], k + 1, len(words[i])))
                    i += 1
            else:
                raise("DriverLoadError", "configuration : commande « " + cmd + " » inconnue (load, blacklist, option)")
            n += 1
        return n

    # Charge les pilotes qui reconnaissent les périphériques sans pilote, puis lie ; renvoie le nombre de
    # liaisons réussies.
    func autoload() -> int:
        for h in self.manager.unclaimed():
            best := ""
            best_score := 0
            for f in self.factories:
                if self.is_loaded(f.name) or self.is_blacklisted(f.name):
                    continue
                mk := f.make
                s := mk().info().matches(h)
                if s > best_score:
                    best_score = s
                    best = f.name
            if best != "":
                try:
                    self.load(best)
                catch e:
                    append(self.log, "autoload " + best + " : " + e.message)
        return self.manager.bind_all()

    func report() -> str:
        out := "chargés : " + _s.join(", ", self.loaded)
        if len(self.blacklist) > 0:
            out = out + " ; liste noire : " + _s.join(", ", self.blacklist)
        return out
