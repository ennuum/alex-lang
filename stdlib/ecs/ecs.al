# ALEX STANDARD LIBRARY — ecs
#
# Entités / composants / systèmes pour les jeux 2D et 3D. ALEX pur.
#
#   use ecs
#   w := ecs.World()
#   w.add_system("mouvement", move_system, ["position", "vitesse"])      # move_system(world, dt, rows)
#   e := w.create({"position": [0.0, 0.0], "vitesse": [1.0, 0.5]})
#   w.run(1.0 / 60.0)                                                     # exécute les systèmes de la phase "update"
#   print(w.get(e, "position"))
#
#   func move_system(world, dt, rows):
#       for row in rows:                       # row = [entité, composant1, composant2, ...] dans l'ordre demandé
#           p := row[1]
#           v := row[2]
#           p[0] = p[0] + v[0] * dt             # les composants sont des objets modifiables en place
#           p[1] = p[1] + v[1] * dt
#
# MODÈLE
#   Entité   : entier opaque = génération * 16777216 + indice. Un indice libéré est recyclé, mais sa génération
#              augmente : un ancien identifiant ne désigne JAMAIS la nouvelle entité (is_alive(ancien) == false).
#   Composant: valeur quelconque (liste, dict, nombre...) rangée sous un NOM (str) pour chaque entité ; au plus un
#              composant par nom et par entité. Un « tag » est un composant de valeur true (add_tag / has).
#   Système  : fonction fn(world, dt, rows) rattachée à une PHASE ("update" par défaut ; "fixed_update", "render"...
#              sont des noms libres, déclenchés par run(dt, phase)). Les systèmes d'une phase s'exécutent dans l'ordre de
#              `priority` croissante, puis d'enregistrement. rows vaut la liste des entités qui possèdent tous les
#              composants demandés (et aucun des composants exclus), vide si le système n'en demande pas.
#   Commandes différées : defer(fn) / defer_destroy(e) s'exécutent après chaque système, ce qui permet de créer ou
#              détruire des entités pendant qu'on parcourt un résultat de requête.
#   Ressources : valeurs globales nommées (set_resource / resource). Événements : emit(nom, données) / drain(nom).
#   Hiérarchie : set_parent(enfant, parent) ; détruire un parent détruit ses enfants (destroy(e, true)).
#
# Erreurs : ValueError (entité morte, nom invalide...), TypeError.

use math
use json
from core use len, type, is_int
from collections use append, pop, clear, keys

const VERSION := "1.0.0"
const _INDEX_RANGE := 16777216

func _clone(x):
    t := type(x)
    if t == "list":
        out := []
        for v in x:
            append(out, _clone(v))
        return out
    if t == "dict":
        out := {}
        for k in keys(x):
            out[k] = _clone(x[k])
        return out
    return x

class World:
    func init():
        self._generations = []          # indice -> génération courante
        self._alive = []                # indice -> vivant ?
        self._free = []                 # indices libres
        self._count = 0
        self._stores = {}               # nom de composant -> {entité: valeur}
        self._systems = []              # {"name", "fn", "query", "without", "phase", "priority", "enabled", "order"}
        self._next_order = 0
        self._resources = {}
        self._events = {}
        self._deferred = []
        self._on_add = {}
        self._on_remove = {}
        self._parents = {}              # enfant -> parent
        self._children = {}             # parent -> [enfants]
        self._names = {}                # nom -> entité
        self._entity_names = {}         # entité -> nom
        self._prefabs = {}
        self.frame = 0

    # --- entités ---
    func create(components=null, name=null):
        idx := 0
        if len(self._free) > 0:
            idx = pop(self._free)
            self._alive[idx] = true
        else:
            idx = len(self._generations)
            append(self._generations, 0)
            append(self._alive, true)
        e := self._generations[idx] * _INDEX_RANGE + idx
        self._count += 1
        if name != null:
            self.set_name(e, name)
        if components != null:
            for k in keys(components):
                self.add(e, k, components[k])
        return e

    func is_alive(e):
        if not is_int(e) or e < 0:
            return false
        idx := e % _INDEX_RANGE
        if idx >= len(self._generations):
            return false
        return self._alive[idx] and self._generations[idx] == e // _INDEX_RANGE

    func _need_alive(e, who):
        if not self.is_alive(e):
            raise("ValueError", f"ecs.World.{who} : entité {e} inexistante ou détruite")

    func count():
        return self._count

    # Toutes les entités vivantes, par indice croissant.
    func entities():
        out := []
        idx := 0
        while idx < len(self._generations):
            if self._alive[idx]:
                append(out, self._generations[idx] * _INDEX_RANGE + idx)
            idx += 1
        return out

    # Détruit l'entité et ses composants (observateurs on_remove appelés). recursive = true détruit aussi ses enfants.
    func destroy(e, recursive=true):
        if not self.is_alive(e):
            return false
        if recursive and e in self._children:
            kids := []
            for c in self._children[e]:
                append(kids, c)
            for c in kids:
                self.destroy(c, true)
        names := []
        for cname in keys(self._stores):
            if e in self._stores[cname]:
                append(names, cname)
        for cname in names:
            self.remove(e, cname)
        if e in self._parents:
            self._unlink(e)
        if e in self._children:
            for c in self._children[e]:
                if c in self._parents:
                    del self._parents[c]
            del self._children[e]
        if e in self._entity_names:
            nm := self._entity_names[e]
            del self._entity_names[e]
            if nm in self._names and self._names[nm] == e:
                del self._names[nm]
        idx := e % _INDEX_RANGE
        self._alive[idx] = false
        self._generations[idx] = self._generations[idx] + 1
        append(self._free, idx)
        self._count -= 1
        return true

    func destroy_all():
        for e in self.entities():
            self.destroy(e, false)

    # --- composants ---
    func add(e, name, value=true):
        self._need_alive(e, "add")
        if not (name in self._stores):
            self._stores[name] = {}
        store := self._stores[name]
        existed := e in store
        store[e] = value
        if not existed and name in self._on_add:
            for fn in self._on_add[name]:
                fn(self, e, value)

    # Alias de add (remplace la valeur existante).
    func set(e, name, value):
        self.add(e, name, value)

    func add_tag(e, name):
        self.add(e, name, true)

    func has(e, name):
        if name in self._stores:
            return e in self._stores[name] and self.is_alive(e)
        return false

    func has_all(e, names):
        for n in names:
            if not self.has(e, n):
                return false
        return true

    func has_any(e, names):
        for n in names:
            if self.has(e, n):
                return true
        return false

    # Valeur du composant, ou default s'il est absent.
    func get(e, name, default=null):
        if name in self._stores:
            store := self._stores[name]
            if e in store and self.is_alive(e):
                return store[e]
        return default

    # Retire un composant ; renvoie true s'il existait.
    func remove(e, name):
        if not (name in self._stores):
            return false
        store := self._stores[name]
        if not (e in store):
            return false
        value := store[e]
        if name in self._on_remove:
            for fn in self._on_remove[name]:
                fn(self, e, value)
        del store[e]
        return true

    # Noms des composants de l'entité.
    func components_of(e):
        out := []
        for cname in keys(self._stores):
            if e in self._stores[cname]:
                append(out, cname)
        return out

    # Nombre d'entités possédant ce composant.
    func count_with(name):
        if name in self._stores:
            return len(self._stores[name])
        return 0

    # Appelle fn(world, entité, valeur) quand un composant `name` est ajouté / retiré (y compris à la destruction).
    func on_add(name, fn):
        if not (name in self._on_add):
            self._on_add[name] = []
        append(self._on_add[name], fn)

    func on_remove(name, fn):
        if not (name in self._on_remove):
            self._on_remove[name] = []
        append(self._on_remove[name], fn)

    # --- requêtes ---
    # Lignes [entité, valeur1, valeur2, ...] des entités qui ont TOUS les composants `names` et AUCUN de `without`.
    # Le résultat est une copie : on peut modifier le monde pendant qu'on le parcourt.
    func query(names, without=null):
        rows := []
        if len(names) == 0:
            return rows
        smallest := names[0]
        for n in names:
            if not (n in self._stores):
                return rows
            if len(self._stores[n]) < len(self._stores[smallest]):
                smallest = n
        for e in keys(self._stores[smallest]):
            ok := true
            row := [e]
            for n in names:
                st := self._stores[n]
                if not (e in st):
                    ok = false
                    break
                append(row, st[e])
            if not ok:
                continue
            if without != null:
                for n in without:
                    if n in self._stores and e in self._stores[n]:
                        ok = false
                        break
            if ok:
                append(rows, row)
        return rows

    # Appelle fn(entité, valeur1, ...) via une liste d'arguments : fn reçoit la LIGNE complète [entité, valeurs...].
    func each(names, fn, without=null):
        for row in self.query(names, without):
            fn(row)

    # Première entité portant ce composant (ou null) : pratique pour les singletons (joueur, caméra).
    func first_with(name):
        if name in self._stores:
            for e in keys(self._stores[name]):
                return e
        return null

    # --- noms ---
    func set_name(e, name):
        self._need_alive(e, "set_name")
        if name in self._names and self._names[name] != e:
            raise("ValueError", f"ecs.World.set_name : le nom '{name}' est déjà pris")
        if e in self._entity_names:
            old := self._entity_names[e]
            if old in self._names:
                del self._names[old]
        self._names[name] = e
        self._entity_names[e] = name

    func find_by_name(name):
        if name in self._names:
            return self._names[name]
        return null

    func name_of(e):
        if e in self._entity_names:
            return self._entity_names[e]
        return null

    # --- hiérarchie ---
    func _unlink(child):
        p := self._parents[child]
        if p in self._children:
            kids := self._children[p]
            k := 0
            while k < len(kids):
                if kids[k] == child:
                    pop(kids, k)
                    break
                k += 1
            if len(kids) == 0:
                del self._children[p]
        del self._parents[child]

    # Rattache child à parent (parent = null détache). Les cycles sont refusés.
    func set_parent(child, parent):
        self._need_alive(child, "set_parent")
        if parent != null:
            self._need_alive(parent, "set_parent")
            n := parent
            guard := 0
            while n != null:
                if n == child:
                    raise("ValueError", "ecs.World.set_parent : cycle dans la hiérarchie")
                n = self.parent_of(n)
                guard += 1
                if guard > 100000:
                    break
        if child in self._parents:
            self._unlink(child)
        if parent == null:
            return null
        self._parents[child] = parent
        if not (parent in self._children):
            self._children[parent] = []
        append(self._children[parent], child)

    func parent_of(e):
        if e in self._parents:
            return self._parents[e]
        return null

    func children_of(e):
        out := []
        if e in self._children:
            for c in self._children[e]:
                append(out, c)
        return out

    # L'entité et tous ses descendants (préfixe).
    func descendants(e):
        out := []
        stack := [e]
        while len(stack) > 0:
            cur := pop(stack)
            for c in self.children_of(cur):
                append(out, c)
                append(stack, c)
        return out

    # --- systèmes ---
    # fn(world, dt, rows). query = noms de composants demandés (rows vide si null). without = composants exclus.
    func add_system(name, fn, query=null, phase="update", priority=0, without=null):
        for s in self._systems:
            if s["name"] == name:
                raise("ValueError", f"ecs.World.add_system : le système '{name}' existe déjà")
        append(self._systems, {"name": name, "fn": fn, "query": query, "without": without, "phase": phase, "priority": priority, "enabled": true, "order": self._next_order})
        self._next_order += 1

    func remove_system(name):
        k := 0
        while k < len(self._systems):
            if self._systems[k]["name"] == name:
                pop(self._systems, k)
                return true
            k += 1
        return false

    func enable_system(name, enabled=true):
        for s in self._systems:
            if s["name"] == name:
                s["enabled"] = enabled
                return null
        raise("ValueError", f"ecs.World.enable_system : système '{name}' inconnu")

    # Noms des systèmes de la phase, dans l'ordre d'exécution.
    func system_order(phase="update"):
        out := []
        for s in self._ordered(phase):
            append(out, s["name"])
        return out

    func _ordered(phase):
        sel := []
        for s in self._systems:
            if s["phase"] == phase:
                append(sel, s)
        # tri par insertion stable : priorité puis ordre d'enregistrement
        i := 1
        while i < len(sel):
            cur := sel[i]
            j := i - 1
            while j >= 0 and (sel[j]["priority"] > cur["priority"] or (sel[j]["priority"] == cur["priority"] and sel[j]["order"] > cur["order"])):
                sel[j + 1] = sel[j]
                j -= 1
            sel[j + 1] = cur
            i += 1
        return sel

    # Exécute les systèmes actifs d'une phase. Renvoie le nombre de systèmes exécutés.
    func run(dt, phase="update"):
        ran := 0
        for s in self._ordered(phase):
            if not s["enabled"]:
                continue
            rows := []
            if s["query"] != null:
                rows = self.query(s["query"], s["without"])
            s["fn"](self, dt, rows)
            ran += 1
            self.flush()
        if phase == "update":
            self.frame += 1
        return ran

    # --- commandes différées ---
    func defer(fn):
        append(self._deferred, fn)

    func defer_destroy(e):
        append(self._deferred, (w) => w.destroy(e))

    # Exécute les commandes différées (celles ajoutées pendant le flush sont exécutées aussi).
    func flush():
        guard := 0
        while len(self._deferred) > 0:
            batch := self._deferred
            self._deferred = []
            for fn in batch:
                fn(self)
            guard += 1
            if guard > 10000:
                raise("ValueError", "ecs.World.flush : commandes différées en boucle")

    # --- ressources et événements ---
    func set_resource(name, value):
        self._resources[name] = value

    func resource(name, default=null):
        if name in self._resources:
            return self._resources[name]
        return default

    func has_resource(name):
        return name in self._resources

    func remove_resource(name):
        if name in self._resources:
            del self._resources[name]

    func emit(name, data=null):
        if not (name in self._events):
            self._events[name] = []
        append(self._events[name], data)

    # Événements en attente (sans les consommer).
    func peek(name):
        out := []
        if name in self._events:
            for d in self._events[name]:
                append(out, d)
        return out

    # Événements en attente, qui sont consommés.
    func drain(name):
        if name in self._events:
            out := self._events[name]
            self._events[name] = []
            return out
        return []

    func clear_events():
        self._events = {}

    # --- préfabriqués ---
    # Enregistre un modèle : dict nom de composant -> valeur (copiée à chaque création).
    func register_prefab(name, components):
        self._prefabs[name] = components

    # Crée une entité depuis un préfabriqué ; overrides remplace ou ajoute des composants.
    func spawn(prefab, overrides=null, name=null):
        if not (prefab in self._prefabs):
            raise("ValueError", f"ecs.World.spawn : préfabriqué '{prefab}' inconnu")
        e := self.create(null, name)
        base := self._prefabs[prefab]
        for k in keys(base):
            self.add(e, k, _clone(base[k]))
        if overrides != null:
            for k in keys(overrides):
                self.add(e, k, _clone(overrides[k]))
        return e

    # --- sauvegarde ---
    # Copie profonde de l'état : {"entities": [...], "components": {nom: [[entité, valeur], ...]}, "parents": [[enfant, parent]...]}.
    # Les valeurs doivent être des données simples (nombres, textes, listes, dicts) : le résultat passe par json.stringify.
    func snapshot():
        comps := {}
        for cname in keys(self._stores):
            rows := []
            for e in keys(self._stores[cname]):
                append(rows, [e, _clone(self._stores[cname][e])])
            comps[cname] = rows
        parents := []
        for c in keys(self._parents):
            append(parents, [c, self._parents[c]])
        names := []
        for e in keys(self._entity_names):
            append(names, [e, self._entity_names[e]])
        gens := []
        for g in self._generations:
            append(gens, g)
        return {"entities": self.entities(), "generations": gens, "components": comps, "parents": parents, "names": names}

    # Restaure un état produit par snapshot() (les entités gardent leurs identifiants). Les systèmes, ressources,
    # observateurs et préfabriqués ne sont pas touchés.
    func restore(snap):
        self.destroy_all()
        self._generations = []
        self._alive = []
        self._free = []
        self._count = 0
        self._parents = {}
        self._children = {}
        self._names = {}
        self._entity_names = {}
        top := 0
        saved_gens := []
        if "generations" in snap:
            saved_gens = snap["generations"]
            top = len(saved_gens)
        for e in snap["entities"]:
            idx := e % _INDEX_RANGE
            if idx + 1 > top:
                top = idx + 1
        i := 0
        while i < top:
            g := 0
            if i < len(saved_gens):
                g = saved_gens[i]
            append(self._generations, g)
            append(self._alive, false)
            i += 1
        for e in snap["entities"]:
            idx := e % _INDEX_RANGE
            self._generations[idx] = e // _INDEX_RANGE
            self._alive[idx] = true
            self._count += 1
        i = 0
        while i < top:
            if not self._alive[i]:
                append(self._free, i)
            i += 1
        self._stores = {}
        for cname in keys(snap["components"]):
            self._stores[cname] = {}
            for row in snap["components"][cname]:
                self._stores[cname][row[0]] = _clone(row[1])
        for pr in snap["parents"]:
            self.set_parent(pr[0], pr[1])
        for nm in snap["names"]:
            self.set_name(nm[0], nm[1])

    func to_json():
        return json.stringify(self.snapshot())
