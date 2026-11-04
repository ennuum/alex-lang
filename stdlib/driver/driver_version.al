# alex: native
# ALEX STANDARD LIBRARY — driver.driver_version
#
# Versions des pilotes et compatibilité :
#   - Version : « majeur.mineur.correctif[-pré] » (« 1.4 » vaut 1.4.0), comparaison (une pré-version est
#     antérieure à la version finale : 2.0.0-rc1 < 2.0.0) ;
#   - contraintes : « >=1.2 », « <2 », « =1.0.3 », « ^1.2 » (même majeur, >= 1.2), « ~1.2.3 » (même
#     majeur.mineur), « * », et leurs conjonctions séparées par des virgules « >=1.2, <1.8 » ;
#   - API_VERSION : version de l'interface driver.Driver ; un pilote déclare l'intervalle d'API qu'il accepte
#     (api_compatible) ; check_driver vérifie qu'une DriverInfo a une version valide qui satisfait une
#     contrainte (DriverVersionError sinon).
#
#   use driver.driver_version as dv
#   v := dv.parse("1.4.2-rc1")
#   print(v.format(), dv.compare("1.10", "1.9"))          # 1.4.2-rc1 1
#   print(dv.satisfies("1.4.2", "^1.2"))                   # true
#   dv.check_driver(pilote.info(), ">=0.2")
#
# Erreurs : DriverVersionError (version ou contrainte mal formée, incompatibilité).
# Compilable en natif (# alex: native).

from core use len
from collections use append
use string as _s
from driver.driver_info use DriverInfo

const API_VERSION := "1.0.0"

class Version:
    major: int := 0
    minor: int := 0
    patch: int := 0
    pre: str := ""

    func init(major: int, minor: int, patch: int, pre: str):
        self.major = major
        self.minor = minor
        self.patch = patch
        self.pre = pre

    func format() -> str:
        t := str(self.major) + "." + str(self.minor) + "." + str(self.patch)
        if self.pre != "":
            t = t + "-" + self.pre
        return t

    # -1, 0, 1.
    func cmp(o: Version) -> int:
        if self.major != o.major:
            return -1 if self.major < o.major else 1
        if self.minor != o.minor:
            return -1 if self.minor < o.minor else 1
        if self.patch != o.patch:
            return -1 if self.patch < o.patch else 1
        if self.pre == o.pre:
            return 0
        if self.pre == "":
            return 1
        if o.pre == "":
            return -1
        return -1 if self.pre < o.pre else 1

    func is_prerelease() -> bool:
        return self.pre != ""

func _num(t: str, text: str) -> int:
    if len(t) == 0 or len(t) > 9:
        raise("DriverVersionError", "version mal formée : « " + text + " »")
    n := 0
    for ch in t:
        if ch < '0' or ch > '9':
            raise("DriverVersionError", "version mal formée : « " + text + " »")
        n = n * 10 + (_s.ord(ch) - 48)
    return n

func parse(text: str) -> Version:
    t := _s.trim(text)
    if _s.starts_with(t, "v"):
        t = _s.substring(t, 1, len(t))
    pre := ""
    k := _s.find(t, "-")
    if k >= 0:
        pre = _s.substring(t, k + 1, len(t))
        t = _s.substring(t, 0, k)
        if pre == "":
            raise("DriverVersionError", "version mal formée : « " + text + " »")
    parts := _s.split(t, ".")
    if len(parts) < 1 or len(parts) > 3:
        raise("DriverVersionError", "version mal formée : « " + text + " »")
    ma := _num(parts[0], text)
    mi := 0
    pa := 0
    if len(parts) > 1:
        mi = _num(parts[1], text)
    if len(parts) > 2:
        pa = _num(parts[2], text)
    return Version(ma, mi, pa, pre)

func is_valid(text: str) -> bool:
    try:
        parse(text)
        return true
    catch e:
        return false

func compare(a: str, b: str) -> int:
    return parse(a).cmp(parse(b))

func _one(v: Version, c: str) -> bool:
    t := _s.trim(c)
    if t == "*" or t == "":
        return true
    if _s.starts_with(t, ">="):
        return v.cmp(parse(_s.substring(t, 2, len(t)))) >= 0
    if _s.starts_with(t, "<="):
        return v.cmp(parse(_s.substring(t, 2, len(t)))) <= 0
    if _s.starts_with(t, ">"):
        return v.cmp(parse(_s.substring(t, 1, len(t)))) > 0
    if _s.starts_with(t, "<"):
        return v.cmp(parse(_s.substring(t, 1, len(t)))) < 0
    if _s.starts_with(t, "="):
        return v.cmp(parse(_s.substring(t, 1, len(t)))) == 0
    if _s.starts_with(t, "^"):
        b := parse(_s.substring(t, 1, len(t)))
        if v.cmp(b) < 0:
            return false
        if b.major == 0:
            return v.major == 0 and v.minor == b.minor
        return v.major == b.major
    if _s.starts_with(t, "~"):
        b := parse(_s.substring(t, 1, len(t)))
        return v.cmp(b) >= 0 and v.major == b.major and v.minor == b.minor
    return v.cmp(parse(t)) == 0

# Version text satisfait-elle la contrainte (conjonction séparée par des virgules) ?
func satisfies(text: str, constraint: str) -> bool:
    v := parse(text)
    for c in _s.split(constraint, ","):
        if not _one(v, c):
            return false
    return true

# Le cadre (API_VERSION) convient-il à un pilote qui demande requirement ?
func api_compatible(requirement: str) -> bool:
    return satisfies(API_VERSION, requirement)

func check_driver(info: DriverInfo, constraint: str):
    if not is_valid(info.version):
        raise("DriverVersionError", "pilote " + info.name + " : version « " + info.version + " » mal formée")
    if not satisfies(info.version, constraint):
        raise("DriverVersionError", "pilote " + info.name + " " + info.version + " : « " + constraint + " » requis")

# La plus récente des versions (texte), ou "" si la liste est vide.
func latest(versions: list[str]) -> str:
    best := ""
    for v in versions:
        if best == "" or compare(v, best) > 0:
            best = v
    return best
