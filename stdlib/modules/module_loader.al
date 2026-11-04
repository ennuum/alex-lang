# ALEX STANDARD LIBRARY — modules.module_loader
#
# Résolution et chargement STATIQUE des modules, avec les mêmes racines que le compilateur
# (src/ModuleResolver.cpp) : stdlib, projet, dossier du fichier d'entrée et ses parents, alex_packages.
# Permet d'outiller un projet : graphe d'imports, cycles, ordre de compilation, modules inutilisés.
#
#   use modules.module_loader as ml
#   ld := ml.for_entry("src/main.al")
#   print(ld.resolve("collections.hash_map"))     # chemin du fichier, ou null
#   m := ld.load("json")                          # ModuleInfo (modules.module), mis en cache
#   g := ld.import_graph("src/main.al")           # DependencyGraph (modules.dependency) du programme
#   print(g.topological_order())
#   print(ld.missing("src/main.al"))              # imports introuvables
#   print(ml.stdlib_root())
#
# Les modules natifs (_native_*) ne sont pas des fichiers : is_native() les reconnaît, ils sont des feuilles
# du graphe.
# Erreurs : ModuleNotFoundError (load d'un module introuvable), DependencyCycleError, IoError.

from core use len, type
from collections use append
use string as _s
use os as _os
use modules.module as _mod
use modules.dependency as _dep

const NOT_FOUND := "ModuleNotFoundError"

const NATIVE := ["_native_core", "_native_math", "_native_string", "_native_collections", "_native_io",
                 "_native_os", "_native_ui", "_native_process", "_native_net", "_native_tls", "_native_thread",
                 "_native_fd", "_native_signal", "_native_sync", "_native_hwsim", "_native_ffi", "_native_memory",
                 "_native_cli", "_native_gc", "_native_reflect", "_native_asyncio", "_native_office"]

func is_native(name):
    for n in NATIVE:
        if n == name:
            return true
    return false

# Racine de la stdlib, comme le compilateur : $ALEX_STDLIB, ./stdlib, puis à côté de l'exécutable.
func stdlib_root():
    cands := []
    env := _os.getenv("ALEX_STDLIB")
    if env != null and env != "":
        append(cands, env)
    append(cands, "stdlib")
    try:
        exe := _os.executable()
        if exe != null and exe != "":
            d := _os.dirname(exe)
            append(cands, _os.join(d, "stdlib"))
            append(cands, _os.join(_os.join(_os.join(_os.join(d, ".."), "lib"), "alex"), "stdlib"))
    catch e:
        pass
    for c in cands:
        if _os.isfile(_os.join(_os.join(c, "core"), "core.al")):
            return _os.normalize(c)
    return "stdlib"

class ModuleLoader:
    func init(roots=null):
        self.roots = roots
        if self.roots == null:
            self.roots = [stdlib_root(), "."]
        self._cache = {}

    func resolve(name):
        if is_native(name):
            return null
        _mod.need_name("ModuleLoader.resolve", name)
        cands := _mod.relative_candidates(name)
        for r in self.roots:
            for c in cands:
                p := _os.join(r, c)
                if _os.isfile(p):
                    return _os.normalize(p)
        return null

    func exists(name):
        return is_native(name) or self.resolve(name) != null

    func load(name):
        if name in self._cache:
            return self._cache[name]
        p := self.resolve(name)
        if p == null:
            if is_native(name):
                m := _mod.ModuleInfo(name)
                self._cache[name] = m
                return m
            raise(NOT_FOUND, "module '" + name + "' introuvable (racines : " + _s.join(", ", self.roots) + ")")
        m := _mod.from_file(p, name)
        self._cache[name] = m
        return m

    func load_file(path):
        return _mod.from_file(path, _mod.name_from_path(_os.basename(path)))

    # Graphe d'imports transitif depuis un fichier (nœud racine : "<entrée>") ; les modules introuvables
    # sont des feuilles marquées dans missing().
    func import_graph(entry_path):
        g := _dep.DependencyGraph()
        root := self.load_file(entry_path)
        g.add_node("<entrée>")
        queue := []
        for i in root.imports:
            g.add_edge("<entrée>", i)
            append(queue, i)
        seen := {}
        k := 0
        while k < len(queue):
            n := queue[k]
            k += 1
            if n in seen:
                continue
            seen[n] = true
            if is_native(n) or self.resolve(n) == null:
                continue
            for i in self.load(n).imports:
                g.add_edge(n, i)
                if not (i in seen):
                    append(queue, i)
        return g

    # Imports introuvables (ni fichier, ni module natif) dans le programme.
    func missing(entry_path):
        g := self.import_graph(entry_path)
        return [n for n in g.nodes() if n != "<entrée>" and not self.exists(n)]

    # Ordre de compilation (dépendances d'abord, sans les modules natifs).
    func build_order(entry_path):
        return [n for n in self.import_graph(entry_path).topological_order() if n != "<entrée>" and not is_native(n)]

    func cached():
        return [k for k in self._cache]

    func clear_cache():
        self._cache = {}

func entry_roots(entry):
    roots := [stdlib_root(), "."]
    d := _os.dirname(_os.absolute(entry))
    guard := 0
    while d != "" and guard < 64:
        append(roots, d)
        parent := _os.dirname(d)
        if parent == d:
            break
        d = parent
        guard += 1
    append(roots, "alex_packages")
    return roots

# Chargeur avec les racines d'un fichier d'entrée.
func for_entry(entry):
    return ModuleLoader(entry_roots(entry))

func default_loader():
    return ModuleLoader()
