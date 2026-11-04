# ALEX STANDARD LIBRARY — modules.dependency
#
# Dépendances et graphes de dépendances : ordre de construction (tri topologique), détection de cycles,
# dépendances transitives, et RÉSOLUTION de versions (choisir, pour chaque nom, une version qui satisfait
# toutes les contraintes qui le visent — même stratégie que `alexc pkg` : la plus haute admise).
#
#   use modules.dependency as dep
#   g := dep.DependencyGraph()
#   g.add_edge("app", "http")
#   g.add_edge("http", "net")
#   g.add_edge("app", "json")
#   print(g.topological_order())          # ["net", "http", "json", "app"] : dépendances d'abord
#   print(g.find_cycle())                 # null
#   print(g.transitive("app"))            # ["http", "net", "json"]
#
#   catalogue := {"geo": {"1.0.0": {}, "1.2.0": {"math": "^2.0"}}, "math": {"2.0.0": {}, "2.3.1": {}}}
#   r := dep.resolve({"geo": "^1.0"}, catalogue)
#   print(r["geo"], r["math"])            # 1.2.0 2.3.1
#
# Erreurs : DependencyCycleError (cycle), ResolutionError (contraintes incompatibles, paquet introuvable).

from core use len, type
from collections use append, pop
use string as _s
use modules.version as _v

const CYCLE := "DependencyCycleError"
const RESOLUTION := "ResolutionError"

# Une dépendance déclarée : nom + contrainte (+ source : "registry", "path:../x", "git:...").
class Dependency:
    func init(name, constraint="*", source="registry", optional=false):
        if type(name) != "str" or name == "":
            raise("TypeError", "Dependency : nom (str non vide) attendu")
        self.name = name
        self.constraint = constraint
        self.source = source
        self.optional = optional

    func is_path():
        return _s.starts_with(self.source, "path:")

    func path():
        if not self.is_path():
            return null
        return _s.substring(self.source, 5, len(self.source))

    func accepts(version):
        return _v.satisfies(version, self.constraint)

    func __eq__(other):
        return isinstance(other, Dependency) and other.name == self.name and other.constraint == self.constraint and other.source == self.source

    func __str__():
        if self.is_path():
            return self.name + " (" + self.source + ")"
        return self.name + " " + str(self.constraint)

# "nom", "nom@^1.2", "nom@path:../x" -> Dependency.
func parse_spec(spec):
    i := _s.find(spec, "@")
    if i < 0:
        return Dependency(spec)
    name := _s.substring(spec, 0, i)
    rest := _s.substring(spec, i + 1, len(spec))
    if _s.starts_with(rest, "path:"):
        return Dependency(name, "*", rest)
    return Dependency(name, rest)

class DependencyGraph:
    func init():
        self._nodes = []
        self._index = {}
        self._out = {}       # nœud -> dépendances (ordre d'ajout)

    func add_node(name):
        if not (name in self._index):
            self._index[name] = len(self._nodes)
            append(self._nodes, name)
            self._out[name] = []
        return name

    # from_node dépend de to_node.
    func add_edge(from_node, to_node):
        self.add_node(from_node)
        self.add_node(to_node)
        for x in self._out[from_node]:
            if x == to_node:
                return
        append(self._out[from_node], to_node)

    func nodes():
        return self._nodes[:]

    func dependencies(name):
        if not (name in self._out):
            return []
        return self._out[name][:]

    # Nœuds qui dépendent directement de name.
    func dependents(name):
        return [n for n in self._nodes if name in self._out[n]]

    func contains(name):
        return name in self._index

    # Premier cycle trouvé [a, b, ..., a], ou null.
    func find_cycle():
        state := {}
        stack := []
        for start in self._nodes:
            if start in state:
                continue
            c := self._dfs_cycle(start, state, stack)
            if c != null:
                return c
        return null

    func _dfs_cycle(n, state, stack):
        state[n] = 1
        append(stack, n)
        for m in self._out[n]:
            if not (m in state):
                c := self._dfs_cycle(m, state, stack)
                if c != null:
                    return c
            elif state[m] == 1:
                k := 0
                while stack[k] != m:
                    k += 1
                return stack[k:] + [m]
        state[n] = 2
        pop(stack)
        return null

    func has_cycle():
        return self.find_cycle() != null

    # Ordre où chaque nœud vient APRÈS ses dépendances ; DependencyCycleError en cas de cycle.
    func topological_order():
        c := self.find_cycle()
        if c != null:
            raise(CYCLE, "cycle de dépendances : " + _s.join(" -> ", c))
        done := {}
        out := []
        for n in self._nodes:
            self._post(n, done, out)
        return out

    func _post(n, done, out):
        if n in done:
            return
        done[n] = true
        for m in self._out[n]:
            self._post(m, done, out)
        append(out, n)

    # Dépendances transitives de name (sans name), en largeur d'abord.
    func transitive(name):
        out := []
        seen := {name: true}
        queue := [name]
        i := 0
        while i < len(queue):
            for m in self.dependencies(queue[i]):
                if not (m in seen):
                    seen[m] = true
                    append(out, m)
                    append(queue, m)
            i += 1
        return out

    # Niveaux de construction : chaque niveau ne dépend que des précédents (parallélisable).
    func levels():
        order := self.topological_order()
        level := {}
        for n in order:
            lv := 0
            for m in self._out[n]:
                if level[m] + 1 > lv:
                    lv = level[m] + 1
            level[n] = lv
        out := []
        for n in order:
            while len(out) <= level[n]:
                append(out, [])
            append(out[level[n]], n)
        return out

    func to_dot(name="dependances"):
        lines := ["digraph " + name + " {"]
        for n in self._nodes:
            for m in self._out[n]:
                append(lines, "  \"" + n + "\" -> \"" + m + "\";")
        append(lines, "}")
        return _s.join("\n", lines)

# ---------------------------------------------------------------- résolution de versions

# requirements : {nom: contrainte} ; catalog : {nom: {version: {dépendance: contrainte}}}.
# Renvoie {nom: Version} : pour chaque paquet, la plus haute version satisfaisant TOUTES les contraintes
# qui le visent (transitivement). Point fixe, installation à plat (une version par nom).
func resolve(requirements, catalog, max_rounds=100):
    chosen := {}
    rounds := 0
    while true:
        rounds += 1
        if rounds > max_rounds:
            raise(RESOLUTION, "résolution : pas de point fixe après " + str(max_rounds) + " tours")
        # Contraintes courantes : racine + dépendances des versions choisies.
        wants := {}
        origin := {}
        for n in requirements:
            wants[n] = [requirements[n]]
            origin[n] = ["projet"]
        for n in chosen:
            deps := catalog[n][str(chosen[n])]
            for d in deps:
                if not (d in wants):
                    wants[d] = []
                    origin[d] = []
                append(wants[d], deps[d])
                append(origin[d], n + " " + str(chosen[n]))
        nxt := {}
        for n in wants:
            if not (n in catalog):
                raise(RESOLUTION, "paquet introuvable : '" + n + "' (demandé par " + _s.join(", ", origin[n]) + ")")
            best := null
            for vtxt in catalog[n]:
                v := _v.parse(vtxt)
                ok := true
                for c in wants[n]:
                    if not _v.satisfies(v, c):
                        ok = false
                        break
                if ok and (best == null or _v.compare(v, best) > 0):
                    best = v
            if best == null:
                parts := []
                k := 0
                while k < len(wants[n]):
                    append(parts, str(wants[n][k]) + " (" + origin[n][k] + ")")
                    k += 1
                raise(RESOLUTION, "aucune version de '" + n + "' ne satisfait : " + _s.join(", ", parts))
            nxt[n] = best
        same := len(nxt) == len(chosen)
        if same:
            for n in nxt:
                if not (n in chosen) or _v.compare(nxt[n], chosen[n]) != 0:
                    same = false
                    break
        chosen = nxt
        if same:
            return chosen

# Graphe des paquets résolus (arêtes paquet -> dépendance).
func graph_of(resolved, catalog):
    g := DependencyGraph()
    for n in resolved:
        g.add_node(n)
        for d in catalog[n][str(resolved[n])]:
            g.add_edge(n, d)
    return g
