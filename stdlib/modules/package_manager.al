# ALEX STANDARD LIBRARY — modules.package_manager
#
# Gestion des paquets d'un projet depuis un programme ALEX :
#   - lecture locale (sans rien exécuter) : paquets installés dans alex_packages/, verrou alex.lock,
#     contenu du registre local ($ALEX_REGISTRY, ~/.alex/registry), vérification « installé = verrouillé » ;
#   - opérations qui modifient le projet déléguées à la commande officielle `alexc pkg` (même résolution,
#     mêmes empreintes SHA-256) : init, add, remove, install, update, publish, verify.
#
#   use modules.package_manager as pm
#   m := pm.PackageManager(".")
#   for p in m.installed():
#       print(p.name, p.version)
#   print(m.registry_versions("geometrie"))       # ["1.0.0", "1.2.0"]
#   print(m.outdated())                           # [{"name", "installed", "latest"}]
#   r := m.add("geometrie", "^1.0")               # exécute `alexc pkg add geometrie ^1.0`
#   print(r["ok"], r["output"])
#
# Erreurs : PackageError (projet sans alex.toml, commande en échec avec check=true), IoError.

from core use len, type
from collections use append
use string as _s
use os as _os
use process as _proc
use modules.package as _pkg
use modules.version as _v

const ERROR := "PackageError"

func default_registry():
    r := _os.getenv("ALEX_REGISTRY")
    if r != null and r != "":
        return r
    h := _os.getenv("HOME")
    if h != null and h != "":
        return _os.join(_os.join(h, ".alex"), "registry")
    return ".alex_registry"

# Exécutable alex à utiliser : $ALEX, sinon celui qui exécute ce programme, sinon « alex » du PATH.
func alex_executable():
    e := _os.getenv("ALEX")
    if e != null and e != "":
        return e
    try:
        x := _os.executable()
        if x != null and x != "" and _s.contains(_os.basename(x), "alex"):
            return x
    catch err:
        pass
    return "alex"

class PackageManager:
    func init(project_dir=".", registry=null):
        self.project_dir = project_dir
        self.registry = registry
        if self.registry == null:
            self.registry = default_registry()

    func manifest_path():
        return _os.join(self.project_dir, "alex.toml")

    func lock_path():
        return _os.join(self.project_dir, "alex.lock")

    func packages_dir():
        return _os.join(self.project_dir, "alex_packages")

    func has_manifest():
        return _os.isfile(self.manifest_path())

    func manifest():
        if not self.has_manifest():
            raise(ERROR, "aucun alex.toml dans " + self.project_dir + " (lancez `alexc pkg init`)")
        return _pkg.load(self.manifest_path())

    func lock():
        return _pkg.load_lock(self.lock_path())

    # Paquets présents dans alex_packages/ (Package lus depuis leur alex.toml).
    func installed():
        out := []
        d := self.packages_dir()
        if not _os.isdir(d):
            return out
        for name in _sorted(_os.list_dir(d)):
            m := _os.join(_os.join(d, name), "alex.toml")
            if _os.isfile(m):
                try:
                    append(out, _pkg.load(m))
                catch e:
                    pass
        return out

    func installed_version(name):
        for p in self.installed():
            if p.name == name:
                return p.version
        return null

    # Versions publiées dans le registre local, triées.
    func registry_versions(name):
        d := _os.join(self.registry, name)
        if not _os.isdir(d):
            return []
        vs := [v for v in _os.list_dir(d) if _v.is_valid(v)]
        return [str(v) for v in _v.sort(vs)]

    func registry_packages():
        if not _os.isdir(self.registry):
            return []
        return _sorted([n for n in _os.list_dir(self.registry) if _os.isdir(_os.join(self.registry, n))])

    # Dépendances directes installées dans une version inférieure à la plus haute admise.
    func outdated():
        out := []
        for d in self.manifest().dependencies:
            if d.is_path():
                continue
            cur := self.installed_version(d.name)
            best := _v.max_satisfying(self.registry_versions(d.name), d.constraint)
            if best != null and (cur == null or _v.compare(cur, best) < 0):
                append(out, {"name": d.name, "installed": cur, "latest": str(best)})
        return out

    # Écarts entre alex.lock et alex_packages/ : liste de messages ([] : conforme).
    func check_lock():
        out := []
        lk := self.lock()
        names := {}
        for e in lk:
            names[e["name"]] = true
            v := self.installed_version(e["name"])
            if v == null:
                append(out, e["name"] + " : dans alex.lock mais non installé")
            elif v != e["version"]:
                append(out, e["name"] + " : installé " + v + ", verrouillé " + e["version"])
        for p in self.installed():
            if not (p.name in names):
                append(out, p.name + " : installé mais absent de alex.lock")
        return out

    # ------------------------------------------------------------ commandes `alexc pkg`

    # {"ok", "code", "output"} ; check=true : PackageError si la commande échoue.
    func run(args, check=false, timeout=120):
        full := ["pkg"] + args
        env := null
        if self.registry != null:
            env = {"ALEX_REGISTRY": self.registry}
        r := _proc.run(alex_executable(), full, null, timeout, self.project_dir, env)
        res := {"ok": r.code == 0, "code": r.code, "output": r.stdout + r.stderr}
        if check and r.code != 0:
            raise(ERROR, "alexc pkg " + _s.join(" ", args) + " : " + _s.trim(res["output"]))
        return res

    func init_project(name, check=false):
        return self.run(["init", name], check)

    func add(name, spec="", check=false):
        if spec == "":
            return self.run(["add", name], check)
        return self.run(["add", name, spec], check)

    func remove(name, check=false):
        return self.run(["remove", name], check)

    func install(locked=false, check=false):
        if locked:
            return self.run(["install", "--locked"], check)
        return self.run(["install"], check)

    func update(names=null, check=false):
        a := ["update"]
        if names != null:
            a = a + names
        return self.run(a, check)

    func publish(check=false):
        return self.run(["publish"], check)

    func verify(check=false):
        return self.run(["verify"], check)

func _sorted(xs):
    out := xs[:]
    i := 1
    while i < len(out):
        v := out[i]
        j := i - 1
        while j >= 0 and out[j] > v:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = v
        i += 1
    return out
