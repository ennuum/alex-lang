# Tests : modules.* (version, dependency, package, package_manager, module, module_loader, abi, plugin).
from core use len, type
from collections use append
use check as t
use os
use io
use filesystem as fs
use modules.version as ver
use modules.dependency as dep
use modules.package as pkg
use modules.package_manager as pm
use modules.module as mod
use modules.module_loader as ml
use modules.abi as abi
use modules.plugin as plg

# ---------------------------------------------------------------- version
v := ver.parse("1.4.2-rc.1+build.7")
t.eq([v.major, v.minor, v.patch, v.pre, v.build], [1, 4, 2, "rc.1", "build.7"], "parse")
t.check(v.is_prerelease(), "is_prerelease")
t.eq(str(v), "1.4.2-rc.1+build.7", "str")
t.eq(ver.compare("1.0.0-rc.1", "1.0.0"), -1, "pré-version < finale")
t.eq(ver.compare("1.0.0-alpha", "1.0.0-alpha.1"), -1, "préfixe plus court")
t.eq(ver.compare("1.0.0-alpha.beta", "1.0.0-beta"), -1, "lexical")
t.eq(ver.compare("1.0.0-2", "1.0.0-10"), -1, "numérique")
t.eq(ver.compare("1.0.0+a", "1.0.0+b"), 0, "build ignoré")
t.check(ver.satisfies("1.4.2", "^1.2"), "caret")
t.check(not ver.satisfies("2.0.0", "^1.2"), "caret majeur")
t.check(ver.satisfies("0.2.5", "^0.2.1") and not ver.satisfies("0.3.0", "^0.2.1"), "caret 0.x")
t.check(not ver.satisfies("0.0.4", "^0.0.3"), "caret 0.0.x")
t.check(ver.satisfies("1.2.9", "~1.2.3") and not ver.satisfies("1.3.0", "~1.2.3"), "tilde")
t.check(not ver.satisfies("2.0.0", ">=1.2 <2.0"), "intervalle")
t.check(ver.satisfies("1.9.0", ">= 1.2 < 2.0"), "intervalle avec espaces")
t.check(ver.satisfies("3.1.0", "^1.0 || ^3.0"), "alternative")
t.check(ver.satisfies("1.7.3", "1.x") and not ver.satisfies("2.0.0", "1.x"), "joker")
t.check(ver.satisfies("5.0.0", "*"), "étoile")
t.check(not ver.satisfies("1.3.0-beta.1", ">=1.2.0"), "pré-version exclue")
t.check(ver.satisfies("1.3.0-beta.2", ">=1.3.0-beta.1"), "pré-version même x.y.z")
t.check(ver.satisfies("1.0.0", "=1.0.0") and not ver.satisfies("1.0.1", "=1.0.0"), "exacte")
t.eq(str(ver.max_satisfying(["1.2.0", "1.9.3", "2.0.0"], "~1.9")), "1.9.3", "max_satisfying")
t.eq(str(ver.min_satisfying(["1.2.0", "1.9.3", "2.0.0"], ">=1.5")), "1.9.3", "min_satisfying")
t.eq(str(ver.parse("1.2.3").bump("minor")), "1.3.0", "bump minor")
t.eq(str(ver.parse("1.2.3-rc.1").bump("pre")), "1.2.3-rc.2", "bump pre")
t.eq(str(ver.parse("1.2.3-rc.1").bump("patch")), "1.2.3", "bump patch d'une pré-version")
t.eq([str(x) for x in ver.sort(["1.10.0", "1.2.0", "1.2.0-rc.1"])], ["1.2.0-rc.1", "1.2.0", "1.10.0"], "sort")
t.check(ver.parse("1.2.3") < ver.parse("1.10.0"), "opérateur <")
t.raises(() => ver.parse("1.2"), "VersionError", "parse strict")
t.raises(() => ver.parse("01.2.3"), "VersionError", "zéro de tête")
t.eq(str(ver.parse_loose("1.2")), "1.2.0", "parse_loose")
t.eq(ver.caret("1.4.2-rc.1"), "^1.4.2", "caret()")

# ---------------------------------------------------------------- dependency
g := dep.DependencyGraph()
g.add_edge("app", "http")
g.add_edge("http", "net")
g.add_edge("app", "json")
t.eq(g.topological_order(), ["net", "http", "json", "app"], "topological_order")
t.eq(g.find_cycle(), null, "pas de cycle")
t.eq(g.transitive("app"), ["http", "json", "net"], "transitive")
t.eq(g.dependents("net"), ["http"], "dependents")
t.eq(g.levels(), [["net", "json"], ["http"], ["app"]], "levels")
g.add_edge("net", "app")
t.eq(g.find_cycle(), ["app", "http", "net", "app"], "cycle")
t.raises(() => g.topological_order(), "DependencyCycleError", "topological cycle")
t.check(len(g.to_dot()) > 20, "to_dot")
catalog := {"geo": {"1.0.0": {}, "1.2.0": {"math": "^2.0"}}, "math": {"2.0.0": {}, "2.3.1": {}, "3.0.0": {}}}
r := dep.resolve({"geo": "^1.0"}, catalog)
t.eq(str(r["geo"]), "1.2.0", "resolve geo")
t.eq(str(r["math"]), "2.3.1", "resolve transitif")
r2 := dep.resolve({"geo": "^1.0", "math": "~2.0"}, catalog)
t.eq(str(r2["math"]), "2.0.0", "contraintes combinées")
t.raises(() => dep.resolve({"geo": "^1.0", "math": "^3.0"}, catalog), "ResolutionError", "conflit")
t.raises(() => dep.resolve({"nope": "*"}, catalog), "ResolutionError", "introuvable")
d1 := dep.parse_spec("utils@path:../utils")
t.check(d1.is_path() and d1.path() == "../utils", "parse_spec path")
t.eq(dep.parse_spec("geo@^1.0").constraint, "^1.0", "parse_spec contrainte")
t.eq(dep.graph_of(r, catalog).topological_order(), ["math", "geo"], "graph_of")

# ---------------------------------------------------------------- package
toml := "[package]\nname = \"monapp\"   # nom\nversion = \"0.3.1\"\nentry = \"main.al\"\nalex = \">=1.2.0\"\n\n[dependencies]\ngeometrie = \"^1.0\"\nutils = { path = \"../utils\" }\n"
p := pkg.parse(toml)
t.eq([p.name, p.version, p.entry, p.alex], ["monapp", "0.3.1", "main.al", ">=1.2.0"], "parse manifeste")
t.eq(len(p.dependencies), 2, "dépendances")
t.check(p.dependency("utils").is_path(), "dépendance path")
p.add_dependency("json5", "^2.1")
t.eq(p.dependency("json5").constraint, "^2.1", "add_dependency")
t.check(p.remove_dependency("geometrie"), "remove_dependency")
again := pkg.parse(pkg.serialize(p))
t.eq([d.name for d in again.dependencies], ["utils", "json5"], "aller-retour")
t.eq(pkg.validate(again), [], "valide")
bad := pkg.Package("1abc", "x")
t.eq(len(pkg.validate(bad)), 2, "validate erreurs")
t.raises(() => pkg.parse("[dependencies]\n"), "PackageError", "sans [package]")
t.raises(() => pkg.parse("[package]\nname = \"a b\"\nversion = \"1.0.0\"\n"), "PackageError", "nom invalide")
t.check(p.requires_alex("1.3.0"), "requires_alex")
lock := pkg.parse_lock("# x\n\n[[package]]\nname = \"geo\"\nversion = \"1.2.0\"\nsource = \"registry\"\nchecksum = \"sha256:ab\"\n")
t.eq(lock[0]["version"], "1.2.0", "parse_lock")

# ---------------------------------------------------------------- package_manager (lecture locale)
tmp := fs.make_temp_dir()
reg := os.join(tmp, "registry")
os.mkdir_all(os.join(os.join(reg, "geo"), "1.0.0"))
os.mkdir_all(os.join(os.join(reg, "geo"), "1.2.0"))
proj := os.join(tmp, "proj")
os.mkdir_all(os.join(os.join(proj, "alex_packages"), "geo"))
io.write_file(os.join(proj, "alex.toml"), "[package]\nname = \"proj\"\nversion = \"0.1.0\"\n[dependencies]\ngeo = \"^1.0\"\n")
io.write_file(os.join(os.join(os.join(proj, "alex_packages"), "geo"), "alex.toml"), "[package]\nname = \"geo\"\nversion = \"1.0.0\"\n")
io.write_file(os.join(proj, "alex.lock"), "[[package]]\nname = \"geo\"\nversion = \"1.0.0\"\nsource = \"registry\"\nchecksum = \"sha256:x\"\n")
m := pm.PackageManager(proj, reg)
t.eq([x.name for x in m.installed()], ["geo"], "installed")
t.eq(m.installed_version("geo"), "1.0.0", "installed_version")
t.eq(m.registry_versions("geo"), ["1.0.0", "1.2.0"], "registry_versions")
t.eq(m.outdated(), [{"name": "geo", "installed": "1.0.0", "latest": "1.2.0"}], "outdated")
t.eq(m.check_lock(), [], "check_lock")
t.eq(m.registry_packages(), ["geo"], "registry_packages")
fs.remove_tree(tmp)

# ---------------------------------------------------------------- module
mi := mod.from_file("stdlib/collections/hash_map.al", "collections.hash_map")
t.check(_s_contains(mi.doc_title(), "collections.hash_map"), "doc_title")
t.check(mi.depends_on("collections.list"), "imports")
t.eq(mi.exports["class"], ["HashMap"], "exports class")
t.check(mi.has_export("group_by") and mi.has_export("_TOMB"), "exports func/const")
t.eq(mi.import_aliases["_u"], "collections._util", "alias")
t.eq(mi.imported_names["Collection"], "collections.list", "from use")
t.eq(mod.relative_candidates("a.b"), ["a/b.al", "a/b/b.al", "a/b/__init__.al"], "relative_candidates")
t.eq(mod.name_from_path("collections/hash_map.al"), "collections.hash_map", "name_from_path")
t.eq(mod.name_from_path("json/json.al"), "json", "name_from_path paquet")
t.check(not mod.is_valid_name("a..b") and mod.is_valid_name("a_1.b"), "is_valid_name")
src := "# Titre\n# suite\nuse os\nfrom core use len, type\nasync func f(x):\n    return x\nclass K:\n    pass\nx := 3\n"
pm2 := mod.parse(src, "demo")
t.eq(pm2.doc, ["Titre", "suite"], "doc")
t.eq(pm2.exports["func"], ["f"], "async func")
t.eq(pm2.exports["var"], ["x"], "var")

func _s_contains(a, b):
    i := 0
    while i + len(b) <= len(a):
        if a[i:i + len(b)] == b:
            return true
        i += 1
    return false

# ---------------------------------------------------------------- module_loader
ld := ml.ModuleLoader()
t.check(ld.resolve("collections.hash_map") != null, "resolve")
t.eq(ld.resolve("nope.nope"), null, "resolve absent")
t.check(ld.exists("_native_os"), "natif")
t.raises(() => ld.load("nope.nope"), "ModuleNotFoundError", "load absent")
gr := ld.import_graph("tests/stdlib2/test_collections.al")
order := gr.topological_order()
t.check(order[len(order) - 1] == "<entrée>", "graphe : entrée en dernier")
t.eq(ld.missing("tests/stdlib2/test_collections.al"), ["check"], "manquant hors racines")
t.eq(len(ml.for_entry("tests/stdlib2/test_collections.al").missing("tests/stdlib2/test_collections.al")), 0, "aucun manquant avec for_entry")
bo := ld.build_order("tests/stdlib2/test_collections.al")
ci := 0
ui := 0
k := 0
for n in bo:
    if n == "collections.collection_errors":
        ci = k
    if n == "collections.hash_map":
        ui = k
    k += 1
t.check(ci < ui, "ordre de compilation")
t.check(ml.stdlib_root() != "", "stdlib_root")
t.check(len(ml.entry_roots("tests/stdlib2/test_collections.al")) >= 4, "entry_roots")

# ---------------------------------------------------------------- abi
a := abi.ABI("sysv-x86_64")
l := a.layout([["id", "u32"], ["flag", "u8"], ["value", "f64"]])
t.eq([l.size, l.align, l.offset("value")], [16, 8, 8], "layout x86_64")
t.eq(l.total_padding(), 3, "bourrage")
t.eq(abi.ABI("sysv-i386").layout([["a", "u8"], ["b", "f64"]]).offset("b"), 4, "i386 double")
t.eq(abi.ABI("win64").size_of("long"), 4, "win64 long")
t.eq(a.size_of("long"), 8, "sysv long")
t.eq(a.layout([["a", "u8"], ["b", "u32"]], true).size, 5, "packed")
inner := a.layout([["x", "f32"], ["y", "f32"]])
outer := a.layout([["tag", "u8"], ["pos", inner], ["arr", ["u16", 3]]])
t.eq([outer.offset("pos"), outer.offset("arr"), outer.size], [4, 12, 20], "imbriqué + tableau")
t.eq(a.union_layout([["i", "u32"], ["d", "f64"]]).size, 8, "union")
t.eq(abi.mangle_c("f", "win32-x86"), "_f", "mangle_c")
t.eq(a.integer_argument_registers()[0], "rdi", "registres")
t.raises(() => abi.ABI("pdp11"), "ABIError", "ABI inconnue")
t.raises(() => a.size_of("quad"), "ABIError", "type inconnu")
t.check(len(l.describe()) > 30, "describe")
t.check(abi.current().pointer_size == 8, "current")

# ---------------------------------------------------------------- plugin
journal := []
func act_journal(ctx):
    ctx.on("requete", (r) => append(journal, "j:" + r))
    ctx.provide("log", journal)
func act_auth(ctx):
    ctx.on("requete", (r) => append(journal, "a:" + r), 10)
    ctx.on("filtre", (x) => x + 1)
manager := plg.PluginManager({"app": "demo"})
manager.register(plg.SimplePlugin("auth", "2.1.0", ["journal@^1.0"], act_auth))
manager.register(plg.SimplePlugin("journal", "1.0.0", [], act_journal))
t.eq(manager.activation_order(), ["journal", "auth"], "ordre d'activation")
manager.activate_all()
t.eq(manager.active(), ["journal", "auth"], "actifs")
manager.emit("requete", "r1")
t.eq(journal, ["a:r1", "j:r1"], "emit par priorité")
t.eq(manager.pipe("filtre", 1), 2, "pipe")
t.check(manager.service("log") == journal, "service")
manager.deactivate("journal")
t.eq(manager.active(), [], "désactivation en cascade")
t.eq(manager.handler_count("requete"), 0, "hooks retirés")
t.raises(() => manager.service("log"), "PluginError", "service retiré")
t.raises(() => manager.register(plg.SimplePlugin("auth")), "PluginError", "doublon")
m3 := plg.PluginManager()
m3.register(plg.SimplePlugin("x", "1.0.0", ["y@^2.0"]))
m3.register(plg.SimplePlugin("y", "1.5.0"))
t.raises(() => m3.activation_order(), "PluginError", "version incompatible")
func fail_act(ctx):
    raise("IoError", "disque")
m4 := plg.PluginManager()
m4.register(plg.SimplePlugin("f", "1.0.0", [], fail_act))
t.raises(() => m4.activate_all(), "PluginError", "activation en échec")
t.check(not m4.is_active("f"), "non actif après échec")

t.summary("modules")
