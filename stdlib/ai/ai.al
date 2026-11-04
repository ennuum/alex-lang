# ALEX STANDARD LIBRARY — ai
#
# Intelligence artificielle de jeu : recherche de chemin (A* sur grille et sur graphe quelconque, Dijkstra, lissage
# par ligne de vue, navmesh 3D), machines à états finis, arbres de comportement et comportements de pilotage (steering). ALEX pur,
# sans dépendance graphique ; les vecteurs sont ceux de math3d (listes [x, y, z]).
#
#   use ai
#   g := ai.grid_from_rows(["..#.", "..#.", "...."])         # '#' = obstacle
#   path := ai.find_path(g, [0, 0], [3, 0])                   # [[0,0],[0,1],[1,2],[2,2],[3,1],[3,0]] ou null
#
#   fsm := ai.StateMachine(owner)
#   fsm.add_state("patrouille", null, patrouille_update)
#   fsm.add_state("poursuite", null, poursuite_update)
#   fsm.add_transition("patrouille", "poursuite", (o) => o.voit_joueur)
#   fsm.start("patrouille")
#   fsm.update(dt)
#
#   tree := ai.Selector([ai.Sequence([ai.Condition(a_faim), ai.Action(manger)]), ai.Action(errer)])
#   tree.tick(contexte, dt)                                    # "success" | "failure" | "running"
#
#   v := ai.arrive(pos, cible, 5.0, 3.0)                       # vitesse désirée
#   vel = ai.steer(vel, v, 20.0, dt)                           # accélération bornée
#
# GRILLES : cases [x, y] entières, 0 <= x < largeur, 0 <= y < hauteur. Coût de case >= 1 (1 = normal) ; un obstacle est
#   infranchissable. Déplacements en 8 directions par défaut (coût sqrt(2) en diagonale), sans « couper les coins » : une
#   diagonale est refusée si l'une des deux cases orthogonales adjacentes est un obstacle.
# NAVMESH 3D : NavMesh(positions, indices, max_slope) ou navmesh_from_mesh(maillage, max_slope) construit un graphe de
#   triangles praticables (faces tournées vers le haut : sens trigonométrique vu de dessus, pente <= max_slope degrés),
#   puis find_path(départ, arrivée, rayon) fait un A* sur les triangles et tend le chemin avec l'algorithme de
#   l'entonnoir : la liste de points [x, y, z] est le plus court chemin sur la surface. Aussi : closest_point,
#   height_at, line_of_sight, random_point, coûts par zone (set_cost) et blocage dynamique (block, block_region).
#   Les étages superposés sont gérés par la hauteur (snap_height) ; l'entonnoir travaille dans le plan XZ.
# LIMITES : le navmesh est construit à partir d'un maillage fourni (pas de voxelisation automatique d'une scène) ;
#   le rayon d'agent est approché en reculant les portes de passage (pas d'érosion exacte des bords) ; pas de
#   liens hors maillage (sauts, échelles) : relier deux navmesh avec graph_search. A* garantit un chemin de coût minimal avec une heuristique admissible (octile, manhattan,
#   euclidienne ou nulle).
#
# Erreurs : ValueError (paramètre invalide), TypeError.

use math
use math3d
from core use len, to_int
use physics.spatial as spatial
from collections use append, pop, keys

const VERSION := "1.1.0"
const SUCCESS := "success"
const FAILURE := "failure"
const RUNNING := "running"

const _SQRT2 := 1.4142135623730951

# =============================================================================
# Tas binaire minimal (clé = priorité), interne
# =============================================================================

class _Heap:
    func init():
        self.keys = []
        self.items = []

    func size():
        return len(self.keys)

    func push(key, item):
        append(self.keys, key)
        append(self.items, item)
        i := len(self.keys) - 1
        while i > 0:
            p := (i - 1) // 2
            if self.keys[p] <= self.keys[i]:
                break
            self._swap(i, p)
            i = p

    func pop_min():
        top := self.items[0]
        last_k := pop(self.keys)
        last_i := pop(self.items)
        n := len(self.keys)
        if n > 0:
            self.keys[0] = last_k
            self.items[0] = last_i
            i := 0
            while true:
                l := 2 * i + 1
                r := l + 1
                m := i
                if l < n and self.keys[l] < self.keys[m]:
                    m = l
                if r < n and self.keys[r] < self.keys[m]:
                    m = r
                if m == i:
                    break
                self._swap(i, m)
                i = m
        return top

    func _swap(a, b):
        tk := self.keys[a]
        self.keys[a] = self.keys[b]
        self.keys[b] = tk
        ti := self.items[a]
        self.items[a] = self.items[b]
        self.items[b] = ti

# =============================================================================
# Grille de navigation
# =============================================================================

class Grid:
    func init(width, height, cost=1.0):
        if width < 1 or height < 1:
            raise("ValueError", "ai.Grid : dimensions >= 1 requises")
        self.width = width
        self.height = height
        self.blocked = []
        self.costs = []
        i := 0
        while i < width * height:
            append(self.blocked, false)
            append(self.costs, cost * 1.0)
            i += 1

    func in_bounds(x, y):
        return x >= 0 and y >= 0 and x < self.width and y < self.height

    func walkable(x, y):
        return self.in_bounds(x, y) and not self.blocked[y * self.width + x]

    func set_blocked(x, y, value=true):
        if not self.in_bounds(x, y):
            raise("ValueError", f"ai.Grid : case hors grille ({x}, {y})")
        self.blocked[y * self.width + x] = value

    func set_cost(x, y, cost):
        if not self.in_bounds(x, y):
            raise("ValueError", f"ai.Grid : case hors grille ({x}, {y})")
        if cost < 1.0:
            raise("ValueError", "ai.Grid.set_cost : un coût de case doit être >= 1")
        self.costs[y * self.width + x] = cost * 1.0

    func cost_at(x, y):
        return self.costs[y * self.width + x]

    func block_rect(x, y, w, h, value=true):
        j := y
        while j < y + h:
            i := x
            while i < x + w:
                if self.in_bounds(i, j):
                    self.blocked[j * self.width + i] = value
                i += 1
            j += 1

    func count_blocked():
        n := 0
        for b in self.blocked:
            if b:
                n += 1
        return n

    func neighbors(x, y, diagonal=true):
        out := []
        dirs := [[1, 0], [-1, 0], [0, 1], [0, -1]]
        for d in dirs:
            if self.walkable(x + d[0], y + d[1]):
                append(out, [x + d[0], y + d[1]])
        if diagonal:
            for d in [[1, 1], [1, -1], [-1, 1], [-1, -1]]:
                nx := x + d[0]
                ny := y + d[1]
                if self.walkable(nx, ny) and self.walkable(x + d[0], y) and self.walkable(x, y + d[1]):
                    append(out, [nx, ny])
        return out

# Grille depuis des lignes de texte : wall (par défaut '#') = obstacle ; un chiffre 2..9 = case de coût égal à ce chiffre.
func grid_from_rows(rows, wall="#"):
    if len(rows) == 0:
        raise("ValueError", "ai.grid_from_rows : aucune ligne")
    h := len(rows)
    w := len(rows[0])
    g := Grid(w, h)
    y := 0
    while y < h:
        if len(rows[y]) != w:
            raise("ValueError", f"ai.grid_from_rows : la ligne {y} n'a pas la largeur {w}")
        x := 0
        while x < w:
            ch := rows[y][x]
            if str(ch) == wall:
                g.set_blocked(x, y)
            elif str(ch) in ["2", "3", "4", "5", "6", "7", "8", "9"]:
                g.set_cost(x, y, to_int(str(ch)) * 1.0)
            x += 1
        y += 1
    return g

func _h(kind, ax, ay, bx, by):
    dx := math.abs(ax - bx)
    dy := math.abs(ay - by)
    if kind == "manhattan":
        return (dx + dy) * 1.0
    if kind == "euclidean":
        return math.sqrt(dx * dx + dy * dy)
    if kind == "zero":
        return 0.0
    mn := dx if dx < dy else dy
    mx := dx if dx > dy else dy
    return (mx - mn) + mn * _SQRT2

# A* sur grille. Renvoie la liste des cases [x, y] de start à goal (inclus), ou null si le but est inaccessible.
# heuristic : "octile" (défaut, adaptée à 8 directions), "manhattan" (4 directions), "euclidean" ou "zero" (Dijkstra).
# max_nodes : abandon (null) après ce nombre de cases développées.
func find_path(grid, start, goal, diagonal=true, heuristic="octile", max_nodes=null):
    if not grid.in_bounds(start[0], start[1]) or not grid.in_bounds(goal[0], goal[1]):
        raise("ValueError", "ai.find_path : départ ou but hors grille")
    if not grid.walkable(start[0], start[1]) or not grid.walkable(goal[0], goal[1]):
        return null
    w := grid.width
    sidx := start[1] * w + start[0]
    gidx := goal[1] * w + goal[0]
    if sidx == gidx:
        return [[start[0], start[1]]]
    n := w * grid.height
    g := []
    came := []
    closed := []
    i := 0
    while i < n:
        append(g, -1.0)
        append(came, -1)
        append(closed, false)
        i += 1
    g[sidx] = 0.0
    open := _Heap()
    open.push(_h(heuristic, start[0], start[1], goal[0], goal[1]), sidx)
    expanded := 0
    while open.size() > 0:
        cur := open.pop_min()
        if closed[cur]:
            continue
        if cur == gidx:
            return _rebuild(came, cur, w)
        closed[cur] = true
        expanded += 1
        if max_nodes != null and expanded > max_nodes:
            return null
        cx := cur % w
        cy := cur // w
        for nb in grid.neighbors(cx, cy, diagonal):
            ni := nb[1] * w + nb[0]
            if closed[ni]:
                continue
            step := _SQRT2 if (nb[0] != cx and nb[1] != cy) else 1.0
            tentative := g[cur] + step * grid.costs[ni]
            if g[ni] < 0.0 or tentative < g[ni]:
                g[ni] = tentative
                came[ni] = cur
                open.push(tentative + _h(heuristic, nb[0], nb[1], goal[0], goal[1]), ni)
    return null

func _rebuild(came, cur, w):
    out := []
    while cur != -1:
        append(out, [cur % w, cur // w])
        cur = came[cur]
    rev := []
    i := len(out) - 1
    while i >= 0:
        append(rev, out[i])
        i -= 1
    return rev

# Coût d'un chemin (somme des pas, coût de la case d'arrivée, diagonale = sqrt(2) fois).
func path_cost(grid, path):
    total := 0.0
    i := 1
    while i < len(path):
        a := path[i - 1]
        b := path[i]
        step := _SQRT2 if (a[0] != b[0] and a[1] != b[1]) else 1.0
        total += step * grid.cost_at(b[0], b[1])
        i += 1
    return total

# Ligne de vue entre deux cases (parcours de Bresenham, toutes les cases traversées doivent être libres).
func line_of_sight(grid, a, b):
    x0 := a[0]
    y0 := a[1]
    x1 := b[0]
    y1 := b[1]
    dx := math.abs(x1 - x0)
    dy := math.abs(y1 - y0)
    sx := 1 if x0 < x1 else -1
    sy := 1 if y0 < y1 else -1
    err := dx - dy
    while true:
        if not grid.walkable(x0, y0):
            return false
        if x0 == x1 and y0 == y1:
            return true
        e2 := 2 * err
        nx := x0
        ny := y0
        if e2 > -dy:
            err -= dy
            nx = x0 + sx
        if e2 < dx:
            err += dx
            ny = y0 + sy
        # pas diagonal : refuser de couper un coin d'obstacle
        if nx != x0 and ny != y0:
            if not grid.walkable(nx, y0) or not grid.walkable(x0, ny):
                return false
        x0 = nx
        y0 = ny
    return true

# Raccourcit un chemin : ne garde que les points nécessaires pour que chaque segment ait une ligne de vue.
func smooth_path(grid, path):
    if len(path) <= 2:
        return path
    out := [path[0]]
    anchor := 0
    i := 2
    while i < len(path):
        if not line_of_sight(grid, path[anchor], path[i]):
            append(out, path[i - 1])
            anchor = i - 1
        i += 1
    append(out, path[len(path) - 1])
    return out

# Carte des coûts depuis start (Dijkstra) : liste indexée y * largeur + x ; -1.0 = inaccessible.
func distance_map(grid, start, diagonal=true):
    w := grid.width
    dist := []
    i := 0
    while i < w * grid.height:
        append(dist, -1.0)
        i += 1
    if not grid.walkable(start[0], start[1]):
        return dist
    dist[start[1] * w + start[0]] = 0.0
    open := _Heap()
    open.push(0.0, start[1] * w + start[0])
    done := {}
    while open.size() > 0:
        cur := open.pop_min()
        if cur in done:
            continue
        done[cur] = true
        cx := cur % w
        cy := cur // w
        for nb in grid.neighbors(cx, cy, diagonal):
            ni := nb[1] * w + nb[0]
            step := _SQRT2 if (nb[0] != cx and nb[1] != cy) else 1.0
            t := dist[cur] + step * grid.costs[ni]
            if dist[ni] < 0.0 or t < dist[ni]:
                dist[ni] = t
                open.push(t, ni)
    return dist

# Cases accessibles depuis start (liste de [x, y]), au plus max_cost si indiqué.
func reachable(grid, start, max_cost=null, diagonal=true):
    dist := distance_map(grid, start, diagonal)
    out := []
    i := 0
    while i < len(dist):
        if dist[i] >= 0.0 and (max_cost == null or dist[i] <= max_cost):
            append(out, [i % grid.width, i // grid.width])
        i += 1
    return out

# A* générique sur un graphe quelconque (nœuds de n'importe quel type).
#   neighbors(n)   -> liste de voisins
#   cost(a, b)     -> coût de l'arc a -> b (>= 0)
#   heuristic(n)   -> estimation du coût restant jusqu'au but (0 = Dijkstra)
#   key(n)         -> clé hachable (str ou int) identifiant un nœud ; par défaut str(n)
# Renvoie la liste des nœuds de start à goal, ou null.
func graph_search(start, goal, neighbors, cost, heuristic=null, key=null):
    open := _Heap()
    nodes := {}
    g := {}
    came := {}
    done := {}
    ks := _key(key, start)
    kg := _key(key, goal)
    nodes[ks] = start
    g[ks] = 0.0
    open.push(0.0 if heuristic == null else heuristic(start) * 1.0, ks)
    while open.size() > 0:
        k := open.pop_min()
        if k in done:
            continue
        if k == kg:
            path := []
            cur := k
            while true:
                append(path, nodes[cur])
                if not (cur in came):
                    break
                cur = came[cur]
            rev := []
            i := len(path) - 1
            while i >= 0:
                append(rev, path[i])
                i -= 1
            return rev
        done[k] = true
        node := nodes[k]
        for nb in neighbors(node):
            kn := _key(key, nb)
            if kn in done:
                continue
            t := g[k] + cost(node, nb)
            if not (kn in g) or t < g[kn]:
                g[kn] = t
                came[kn] = k
                nodes[kn] = nb
                open.push(t + (0.0 if heuristic == null else heuristic(nb) * 1.0), kn)
    return null

func _key(key, n):
    if key == null:
        return str(n)
    return key(n)

# =============================================================================
# Machine à états finis
# =============================================================================

class StateMachine:
    func init(owner=null):
        self.owner = owner
        self.states = {}
        self.transitions = []
        self.current = null
        self.time_in_state = 0.0
        self.history = []
        self.max_history = 16

    # on_enter(owner, previous), on_update(owner, dt), on_exit(owner, next) : tous facultatifs (null).
    func add_state(name, on_enter=null, on_update=null, on_exit=null):
        self.states[name] = {"enter": on_enter, "update": on_update, "exit": on_exit}

    # Transition de from_state ("*" = n'importe quel état) vers to_state quand condition(owner) est vraie.
    # Les transitions sont testées dans l'ordre de déclaration, la première vraie gagne.
    func add_transition(from_state, to_state, condition):
        if not (to_state in self.states):
            raise("ValueError", f"ai.StateMachine : état inconnu '{to_state}' (déclarer les états d'abord)")
        append(self.transitions, [from_state, to_state, condition])

    func start(name):
        if not (name in self.states):
            raise("ValueError", f"ai.StateMachine : état inconnu '{name}'")
        self.current = null
        self._enter(name, null)

    func _enter(name, previous):
        self.current = name
        self.time_in_state = 0.0
        append(self.history, name)
        if len(self.history) > self.max_history:
            pop(self.history, 0)
        fn := self.states[name]["enter"]
        if fn != null:
            fn(self.owner, previous)

    # Force le changement d'état (appelle on_exit puis on_enter).
    func change(name):
        if not (name in self.states):
            raise("ValueError", f"ai.StateMachine : état inconnu '{name}'")
        prev := self.current
        if prev != null:
            fn := self.states[prev]["exit"]
            if fn != null:
                fn(self.owner, name)
        self._enter(name, prev)

    # Évalue les transitions puis met à jour l'état courant. Renvoie le nom de l'état courant.
    func update(dt):
        if self.current == null:
            raise("ValueError", "ai.StateMachine.update : appeler start() d'abord")
        for t in self.transitions:
            if (t[0] == self.current or t[0] == "*") and t[1] != self.current:
                if t[2](self.owner):
                    self.change(t[1])
                    break
        self.time_in_state += dt
        fn := self.states[self.current]["update"]
        if fn != null:
            fn(self.owner, dt)
        return self.current

    func is_in(name):
        return self.current == name

# =============================================================================
# Arbres de comportement
# =============================================================================

# Chaque nœud a tick(contexte, dt) -> "success" | "failure" | "running" et reset().

class Action:
    func init(fn):
        self.fn = fn

    func tick(ctx, dt):
        return self.fn(ctx, dt)

    func reset():
        return null

# Condition : fn(ctx) booléen -> success / failure.
class Condition:
    func init(fn):
        self.fn = fn

    func tick(ctx, dt):
        return SUCCESS if self.fn(ctx) else FAILURE

    func reset():
        return null

# Séquence avec mémoire : exécute les enfants dans l'ordre, s'arrête au premier échec ; reprend au nœud « running ».
class Sequence:
    func init(children):
        self.children = children
        self.index = 0

    func tick(ctx, dt):
        while self.index < len(self.children):
            r := self.children[self.index].tick(ctx, dt)
            if r == RUNNING:
                return RUNNING
            if r == FAILURE:
                self.reset()
                return FAILURE
            self.index += 1
        self.reset()
        return SUCCESS

    func reset():
        self.index = 0
        for c in self.children:
            c.reset()

# Sélecteur avec mémoire : essaie les enfants dans l'ordre jusqu'au premier succès.
class Selector:
    func init(children):
        self.children = children
        self.index = 0

    func tick(ctx, dt):
        while self.index < len(self.children):
            r := self.children[self.index].tick(ctx, dt)
            if r == RUNNING:
                return RUNNING
            if r == SUCCESS:
                self.reset()
                return SUCCESS
            self.index += 1
        self.reset()
        return FAILURE

    func reset():
        self.index = 0
        for c in self.children:
            c.reset()

class Inverter:
    func init(child):
        self.child = child

    func tick(ctx, dt):
        r := self.child.tick(ctx, dt)
        if r == SUCCESS:
            return FAILURE
        if r == FAILURE:
            return SUCCESS
        return RUNNING

    func reset():
        self.child.reset()

# Renvoie toujours success (sauf « running »).
class Succeeder:
    func init(child):
        self.child = child

    func tick(ctx, dt):
        r := self.child.tick(ctx, dt)
        if r == RUNNING:
            return RUNNING
        return SUCCESS

    func reset():
        self.child.reset()

# Répète l'enfant times fois (null = indéfiniment, renvoie running) tant qu'il réussit ; échoue dès qu'il échoue.
class Repeat:
    func init(child, times=null):
        self.child = child
        self.times = times
        self.count = 0

    func tick(ctx, dt):
        r := self.child.tick(ctx, dt)
        if r == RUNNING:
            return RUNNING
        if r == FAILURE:
            self.reset()
            return FAILURE
        self.count += 1
        if self.times != null and self.count >= self.times:
            self.reset()
            return SUCCESS
        return RUNNING

    func reset():
        self.count = 0
        self.child.reset()

# Attend duration secondes (running) puis réussit.
class Wait:
    func init(duration):
        self.duration = duration * 1.0
        self.elapsed = 0.0

    func tick(ctx, dt):
        self.elapsed += dt
        if self.elapsed >= self.duration:
            self.elapsed = 0.0
            return SUCCESS
        return RUNNING

    func reset():
        self.elapsed = 0.0

# =============================================================================
# Pilotage (steering) : vitesses désirées, vecteurs [x, y, z]
# =============================================================================

func seek(position, target, max_speed):
    d := math3d.vec3_sub(target, position)
    return math3d.vec3_scale(math3d.vec3_normalize(d), max_speed)

func flee(position, threat, max_speed):
    return math3d.vec3_neg(seek(position, threat, max_speed))

# Comme seek, mais ralentit linéairement dans slow_radius autour de la cible (vitesse nulle à la cible).
func arrive(position, target, max_speed, slow_radius):
    d := math3d.vec3_sub(target, position)
    dist := math3d.vec3_length(d)
    if dist < 0.000001:
        return [0.0, 0.0, 0.0]
    speed := max_speed
    if dist < slow_radius:
        speed = max_speed * dist / slow_radius
    return math3d.vec3_scale(d, speed / dist)

# Vise la position future estimée de la cible mobile.
func pursue(position, max_speed, target_position, target_velocity):
    dist := math3d.vec3_distance(position, target_position)
    t := dist / max_speed if max_speed > 0.0 else 0.0
    future := math3d.vec3_madd(target_position, target_velocity, t)
    return seek(position, future, max_speed)

func evade(position, max_speed, threat_position, threat_velocity):
    return math3d.vec3_neg(pursue(position, max_speed, threat_position, threat_velocity))

# Errance : cap courant (radians, dans le plan XZ) modifié de jitter (radians, fourni par l'appelant, par exemple
# un nombre aléatoire dans [-1, 1] fois l'amplitude). Renvoie [nouveau_cap, vitesse_désirée].
func wander(heading, jitter, max_speed):
    h := heading + jitter
    return [h, [math.sin(h) * max_speed, 0.0, -math.cos(h) * max_speed]]

# Répulsion des voisins plus proches que radius : somme de vecteurs d'éloignement pondérés par la proximité.
func separation(position, neighbor_positions, radius):
    out := [0.0, 0.0, 0.0]
    for p in neighbor_positions:
        d := math3d.vec3_sub(position, p)
        dist := math3d.vec3_length(d)
        if dist > 0.000001 and dist < radius:
            out = math3d.vec3_add(out, math3d.vec3_scale(d, (radius - dist) / (radius * dist)))
    return out

# Évite des obstacles sphériques [centre, rayon] devant soi : renvoie une accélération latérale (vecteur nul si la voie
# est libre). look_ahead : distance de détection le long de la vitesse courante.
func avoid_obstacles(position, velocity, obstacles, look_ahead, max_force):
    speed := math3d.vec3_length(velocity)
    if speed < 0.000001:
        return [0.0, 0.0, 0.0]
    dirn := math3d.vec3_scale(velocity, 1.0 / speed)
    best := null
    best_t := look_ahead + 1.0
    for ob in obstacles:
        rel := math3d.vec3_sub(ob[0], position)
        t := math3d.vec3_dot(rel, dirn)
        if t < 0.0 or t > look_ahead:
            continue
        closest := math3d.vec3_madd(position, dirn, t)
        off := math3d.vec3_sub(closest, ob[0])
        if math3d.vec3_length(off) < ob[1] and t < best_t:
            best_t = t
            best = [ob, off]
    if best == null:
        return [0.0, 0.0, 0.0]
    off := best[1]
    if math3d.vec3_length(off) < 0.000001:
        off = math3d.vec3_cross(dirn, [0.0, 1.0, 0.0])
    return math3d.vec3_scale(math3d.vec3_normalize(off), max_force)

# Applique le pilotage : amène velocity vers desired en limitant l'accélération à max_accel (unités / s²).
func steer(velocity, desired, max_accel, dt):
    delta := math3d.vec3_sub(desired, velocity)
    delta = math3d.vec3_clamp_length(delta, max_accel * dt)
    return math3d.vec3_add(velocity, delta)

# =============================================================================
# Navmesh 3D
# =============================================================================

func _v3sub(a, b):
    return [a[0] - b[0], a[1] - b[1], a[2] - b[2]]

func _v3dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]

func _v3cross(a, b):
    return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]

func _v3dist(a, b):
    d := _v3sub(a, b)
    return math.sqrt(_v3dot(d, d))

# Aire signée (doublée) du triangle (a, b, c) dans le plan XZ : > 0 quand c est du côté « gauche » de a -> b.
func _area2(a, b, c):
    return (b[0] - a[0]) * (c[2] - a[2]) - (b[2] - a[2]) * (c[0] - a[0])

func _veq(a, b):
    return (a[0] - b[0]) * (a[0] - b[0]) + (a[1] - b[1]) * (a[1] - b[1]) + (a[2] - b[2]) * (a[2] - b[2]) < 0.0000000001

# Coordonnées barycentriques de p (projeté sur XZ) dans le triangle ; null si dégénéré.
func _bary_xz(p, a, b, c):
    d := (b[2] - c[2]) * (a[0] - c[0]) + (c[0] - b[0]) * (a[2] - c[2])
    if math.abs(d) < 0.000000000001:
        return null
    u := ((b[2] - c[2]) * (p[0] - c[0]) + (c[0] - b[0]) * (p[2] - c[2])) / d
    v := ((c[2] - a[2]) * (p[0] - c[0]) + (a[0] - c[0]) * (p[2] - c[2])) / d
    return [u, v, 1.0 - u - v]

# Point du triangle (a, b, c) le plus proche de p, en 3D (Ericson, « Real-Time Collision Detection »).
func _closest_on_tri(p, a, b, c):
    ab := _v3sub(b, a)
    ac := _v3sub(c, a)
    ap := _v3sub(p, a)
    d1 := _v3dot(ab, ap)
    d2 := _v3dot(ac, ap)
    if d1 <= 0.0 and d2 <= 0.0:
        return a
    bp := _v3sub(p, b)
    d3 := _v3dot(ab, bp)
    d4 := _v3dot(ac, bp)
    if d3 >= 0.0 and d4 <= d3:
        return b
    vc := d1 * d4 - d3 * d2
    if vc <= 0.0 and d1 >= 0.0 and d3 <= 0.0:
        t := d1 / (d1 - d3)
        return [a[0] + ab[0] * t, a[1] + ab[1] * t, a[2] + ab[2] * t]
    cp := _v3sub(p, c)
    d5 := _v3dot(ab, cp)
    d6 := _v3dot(ac, cp)
    if d6 >= 0.0 and d5 <= d6:
        return c
    vb := d5 * d2 - d1 * d6
    if vb <= 0.0 and d2 >= 0.0 and d6 <= 0.0:
        t := d2 / (d2 - d6)
        return [a[0] + ac[0] * t, a[1] + ac[1] * t, a[2] + ac[2] * t]
    va := d3 * d6 - d5 * d4
    if va <= 0.0 and (d4 - d3) >= 0.0 and (d5 - d6) >= 0.0:
        t := (d4 - d3) / ((d4 - d3) + (d5 - d6))
        return [b[0] + (c[0] - b[0]) * t, b[1] + (c[1] - b[1]) * t, b[2] + (c[2] - b[2]) * t]
    den := 1.0 / (va + vb + vc)
    v := vb * den
    w := vc * den
    return [a[0] + ab[0] * v + ac[0] * w, a[1] + ab[1] * v + ac[1] * w, a[2] + ab[2] * v + ac[2] * w]

class NavMesh:
    func init(positions, indices, max_slope=null, weld=0.0001):
        if len(indices) % 3 != 0:
            raise("ValueError", "ai.NavMesh : la liste d'indices doit contenir des triplets")
        self.snap_height = 2.0
        self.vertices = []
        self.triangles = []
        self.centers = []
        self.cost = []
        self.blocked = []
        self.neighbors = []
        self.source_faces = []
        cmin := 0.0
        if max_slope != null:
            cmin = math.cos(math3d.radians(max_slope))
        else:
            cmin = 0.0001
        wmap := {}
        remap := []
        for p in positions:
            kx := to_int(math.floor(p[0] / weld + 0.5))
            ky := to_int(math.floor(p[1] / weld + 0.5))
            kz := to_int(math.floor(p[2] / weld + 0.5))
            key := f"{kx}:{ky}:{kz}"
            if key in wmap:
                append(remap, wmap[key])
            else:
                id := len(self.vertices)
                wmap[key] = id
                append(self.vertices, [p[0] * 1.0, p[1] * 1.0, p[2] * 1.0])
                append(remap, id)
        i := 0
        while i < len(indices):
            a := remap[indices[i]]
            b := remap[indices[i + 1]]
            c := remap[indices[i + 2]]
            if a != b and b != c and a != c:
                va := self.vertices[a]
                vb := self.vertices[b]
                vc := self.vertices[c]
                n := _v3cross(_v3sub(vb, va), _v3sub(vc, va))
                nl := math.sqrt(_v3dot(n, n))
                if nl > 0.000000001 and n[1] / nl >= cmin:
                    append(self.triangles, [a, b, c])
                    append(self.centers, [(va[0] + vb[0] + vc[0]) / 3.0, (va[1] + vb[1] + vc[1]) / 3.0, (va[2] + vb[2] + vc[2]) / 3.0])
                    append(self.cost, 1.0)
                    append(self.blocked, false)
                    append(self.source_faces, i // 3)
            i += 3
        # voisinage par arêtes partagées
        emap := {}
        t := 0
        while t < len(self.triangles):
            append(self.neighbors, [-1, -1, -1])
            t += 1
        t = 0
        while t < len(self.triangles):
            tr := self.triangles[t]
            e := 0
            while e < 3:
                v1 := tr[e]
                v2 := tr[(e + 1) % 3]
                lo := v1
                hi := v2
                if lo > hi:
                    lo = v2
                    hi = v1
                key := lo * 2147483648 + hi
                if key in emap:
                    other := emap[key]
                    if self.neighbors[t][e] == -1 and self.neighbors[other[0]][other[1]] == -1:
                        self.neighbors[t][e] = other[0]
                        self.neighbors[other[0]][other[1]] = t
                else:
                    emap[key] = [t, e]
                e += 1
            t += 1
        # index spatial des triangles
        boxes := []
        for tr in self.triangles:
            va := self.vertices[tr[0]]
            vb := self.vertices[tr[1]]
            vc := self.vertices[tr[2]]
            append(boxes, [[math.min(va[0], math.min(vb[0], vc[0])), math.min(va[1], math.min(vb[1], vc[1])), math.min(va[2], math.min(vb[2], vc[2]))], [math.max(va[0], math.max(vb[0], vc[0])), math.max(va[1], math.max(vb[1], vc[1])), math.max(va[2], math.max(vb[2], vc[2]))]])
        self._boxes = boxes
        self._grid = spatial.SpatialHash(spatial.suggest_cell_size(boxes, 0.5))
        t = 0
        while t < len(boxes):
            self._grid.insert(t, boxes[t][0], boxes[t][1])
            t += 1

    func triangle_count():
        return len(self.triangles)

    func triangle_vertices(t):
        tr := self.triangles[t]
        return [self.vertices[tr[0]], self.vertices[tr[1]], self.vertices[tr[2]]]

    # Coût de traversée d'un triangle (>= 1 ; 1 = normal), pour des zones lentes (boue, eau).
    func set_cost(t, cost):
        if cost < 1.0:
            raise("ValueError", "ai.NavMesh.set_cost : coût >= 1 requis")
        self.cost[t] = cost * 1.0

    # Bloque / débloque un triangle (porte fermée, obstacle posé).
    func block(t, value=true):
        self.blocked[t] = value

    # Bloque (ou débloque) tous les triangles dont le centre est à moins de `radius` (en XZ) de `center`.
    func block_region(center, radius, value=true):
        n := 0
        t := 0
        while t < len(self.centers):
            c := self.centers[t]
            if (c[0] - center[0]) * (c[0] - center[0]) + (c[2] - center[2]) * (c[2] - center[2]) <= radius * radius:
                self.blocked[t] = value
                n += 1
            t += 1
        return n

    # Triangle sous le point p (projection verticale), à snap_height près en hauteur ; -1 si aucun.
    func locate(p):
        best := -1
        bd := BIG_NAV
        for t in self._grid.query_aabb([p[0], p[1] - self.snap_height, p[2]], [p[0], p[1] + self.snap_height, p[2]]):
            tv := self.triangle_vertices(t)
            bc := _bary_xz(p, tv[0], tv[1], tv[2])
            if bc == null or bc[0] < -0.000001 or bc[1] < -0.000001 or bc[2] < -0.000001:
                continue
            y := bc[0] * tv[0][1] + bc[1] * tv[1][1] + bc[2] * tv[2][1]
            dy := math.abs(y - p[1])
            if dy <= self.snap_height and dy < bd:
                bd = dy
                best = t
        return best

    # Hauteur de la surface sous (x, z) près de la hauteur y (null hors du maillage).
    func height_at(x, z, y=0.0):
        t := self.locate([x, y, z])
        if t < 0:
            return null
        tv := self.triangle_vertices(t)
        bc := _bary_xz([x, y, z], tv[0], tv[1], tv[2])
        return bc[0] * tv[0][1] + bc[1] * tv[1][1] + bc[2] * tv[2][1]

    # Point praticable le plus proche de p : {"point", "triangle", "distance"} ou null (maillage vide).
    func closest_point(p):
        if len(self.triangles) == 0:
            return null
        t := self.locate(p)
        if t >= 0:
            tv := self.triangle_vertices(t)
            bc := _bary_xz(p, tv[0], tv[1], tv[2])
            y := bc[0] * tv[0][1] + bc[1] * tv[1][1] + bc[2] * tv[2][1]
            return {"point": [p[0], y, p[2]], "triangle": t, "distance": math.abs(y - p[1])}
        r := self._grid.cell_size
        tries := 0
        while tries < 40:
            best := null
            for c in self._grid.query_sphere(p, r):
                tv := self.triangle_vertices(c)
                q := _closest_on_tri(p, tv[0], tv[1], tv[2])
                d := _v3dist(p, q)
                if best == null or d < best["distance"]:
                    best = {"point": q, "triangle": c, "distance": d}
            if best != null and best["distance"] <= r:
                return best
            r = r * 2.0
            tries += 1
        return null

    # Vrai si le segment a -> b (projeté sur XZ) reste sur le maillage sans traverser de triangle bloqué.
    func line_of_sight(a, b):
        return self.raycast(a, b)["clear"]

    # Parcourt le maillage de a vers b : {"clear": bool, "point": dernier point atteint (sur la surface), "triangle",
    # "max_cost": coût maximal des triangles traversés}.
    func raycast(a, b):
        sp := self.closest_point(a)
        if sp == null:
            return {"clear": false, "point": a, "triangle": -1}
        cur := sp["triangle"]
        p0 := sp["point"]
        entry := -1
        guard := 0
        maxc := 1.0
        while guard < len(self.triangles) + 8:
            maxc = math.max(maxc, self.cost[cur])
            tv := self.triangle_vertices(cur)
            bc := _bary_xz(b, tv[0], tv[1], tv[2])
            if bc != null and bc[0] >= -0.000001 and bc[1] >= -0.000001 and bc[2] >= -0.000001:
                y := bc[0] * tv[0][1] + bc[1] * tv[1][1] + bc[2] * tv[2][1]
                return {"clear": not self.blocked[cur], "point": [b[0], y, b[2]], "triangle": cur, "max_cost": maxc}
            # arête de sortie : celle que le segment p0 -> b traverse avec le plus grand paramètre
            best_e := -1
            best_t := -1.0
            e := 0
            while e < 3:
                if self.neighbors[cur][e] != entry or entry == -1:
                    v1 := tv[e]
                    v2 := tv[(e + 1) % 3]
                    d := (b[0] - p0[0]) * (v2[2] - v1[2]) - (b[2] - p0[2]) * (v2[0] - v1[0])
                    if math.abs(d) > 0.000000000001:
                        t := ((v1[0] - p0[0]) * (v2[2] - v1[2]) - (v1[2] - p0[2]) * (v2[0] - v1[0])) / d
                        u := ((v1[0] - p0[0]) * (b[2] - p0[2]) - (v1[2] - p0[2]) * (b[0] - p0[0])) / d
                        if t >= -0.000001 and u >= -0.000001 and u <= 1.000001 and t > best_t:
                            best_t = t
                            best_e = e
                e += 1
            if best_e < 0:
                return {"clear": false, "point": p0, "triangle": cur, "max_cost": maxc}
            nb := self.neighbors[cur][best_e]
            hit := [p0[0] + (b[0] - p0[0]) * best_t, p0[1], p0[2] + (b[2] - p0[2]) * best_t]
            if nb < 0 or self.blocked[nb] or self.blocked[cur]:
                return {"clear": false, "point": hit, "triangle": cur, "max_cost": maxc}
            p0 = hit
            entry = cur
            cur = nb
            guard += 1
        return {"clear": false, "point": p0, "triangle": cur, "max_cost": maxc}

    # Point aléatoire sur le maillage (pondéré par l'aire) ; rand() renvoie un flottant dans [0, 1).
    func random_point(rand):
        total := 0.0
        areas := []
        t := 0
        while t < len(self.triangles):
            tv := self.triangle_vertices(t)
            c := _v3cross(_v3sub(tv[1], tv[0]), _v3sub(tv[2], tv[0]))
            a := 0.5 * math.sqrt(_v3dot(c, c))
            if self.blocked[t]:
                a = 0.0
            total = total + a
            append(areas, total)
            t += 1
        if total <= 0.0:
            return null
        x := rand() * total
        k := 0
        while k < len(areas) - 1 and areas[k] < x:
            k += 1
        tv := self.triangle_vertices(k)
        r1 := math.sqrt(rand())
        r2 := rand()
        return [tv[0][0] * (1.0 - r1) + tv[1][0] * r1 * (1.0 - r2) + tv[2][0] * r1 * r2, tv[0][1] * (1.0 - r1) + tv[1][1] * r1 * (1.0 - r2) + tv[2][1] * r1 * r2, tv[0][2] * (1.0 - r1) + tv[1][2] * r1 * (1.0 - r2) + tv[2][2] * r1 * r2]

    # Suite de triangles de coût minimal entre deux triangles (A*), ou null.
    func find_triangle_path(t_start, t_goal, goal_point):
        if self.blocked[t_start] or self.blocked[t_goal]:
            return null
        if t_start == t_goal:
            return [t_start]
        open := _Heap()
        gcost := {t_start: 0.0}
        came := {}
        closed := {}
        open.push(_v3dist(self.centers[t_start], goal_point), t_start)
        while open.size() > 0:
            cur := open.pop_min()
            if cur in closed:
                continue
            closed[cur] = true
            if cur == t_goal:
                path := [cur]
                while cur in came:
                    cur = came[cur]
                    append(path, cur)
                out := []
                k := len(path) - 1
                while k >= 0:
                    append(out, path[k])
                    k -= 1
                return out
            for nb in self.neighbors[cur]:
                if nb < 0 or nb in closed or self.blocked[nb]:
                    continue
                step := _v3dist(self.centers[cur], self.centers[nb]) * 0.5 * (self.cost[cur] + self.cost[nb])
                ng := gcost[cur] + step
                if not (nb in gcost) or ng < gcost[nb]:
                    gcost[nb] = ng
                    came[nb] = cur
                    open.push(ng + _v3dist(self.centers[nb], goal_point), nb)
        return null

    # Plus court chemin sur la surface de `start` à `goal` : liste de points [x, y, z], ou null si inaccessible.
    # agent_radius > 0 recule les passages des arêtes pour garder de la marge (approximation).
    func find_path(start, goal, agent_radius=0.0, smooth=true):
        s := self.closest_point(start)
        g := self.closest_point(goal)
        if s == null or g == null:
            return null
        tris := self.find_triangle_path(s["triangle"], g["triangle"], g["point"])
        if tris == null:
            return null
        if len(tris) == 1:
            return [s["point"], g["point"]]
        portals := [[s["point"], s["point"]]]
        k := 0
        while k < len(tris) - 1:
            a := tris[k]
            b := tris[k + 1]
            e := 0
            while e < 3 and self.neighbors[a][e] != b:
                e += 1
            tr := self.triangles[a]
            v1 := self.vertices[tr[e]]
            v2 := self.vertices[tr[(e + 1) % 3]]
            ca := self.centers[a]
            cb := self.centers[b]
            side := _area2(ca, [ca[0] + cb[0] - ca[0], ca[1], ca[2] + cb[2] - ca[2]], v1)
            left := v1
            right := v2
            if side < 0.0:
                left = v2
                right = v1
            if agent_radius > 0.0:
                el := _v3dist(left, right)
                if el > 0.000001:
                    sh := math.min(agent_radius, el * 0.45)
                    dl := [(right[0] - left[0]) / el, (right[1] - left[1]) / el, (right[2] - left[2]) / el]
                    left2 := [left[0] + dl[0] * sh, left[1] + dl[1] * sh, left[2] + dl[2] * sh]
                    right2 := [right[0] - dl[0] * sh, right[1] - dl[1] * sh, right[2] - dl[2] * sh]
                    left = left2
                    right = right2
            append(portals, [left, right])
            k += 1
        append(portals, [g["point"], g["point"]])
        path := _funnel(portals)
        if smooth and agent_radius <= 0.0:
            path = self.smooth_path(path)
        return path

    # Lissage par ligne de vue : supprime les points de passage inutiles quand le segment direct reste sur le maillage
    # (non bloqué, sans zone de coût > 1) et suit la hauteur du terrain à `tolerance` près. L'entonnoir est localement optimal dans le couloir
    # de triangles choisi par l'A* ; ce lissage rattrape les couloirs en escalier des maillages réguliers.
    func smooth_path(path, tolerance=0.15):
        if len(path) <= 2:
            return path
        out := [path[0]]
        i := 0
        while i < len(path) - 1:
            k := len(path) - 1
            while k > i + 1:
                if self._can_skip(path[i], path[k], tolerance):
                    break
                k -= 1
            append(out, path[k])
            i = k
        return out

    func _can_skip(a, b, tol):
        r := self.raycast(a, b)
        if not r["clear"] or r["max_cost"] > 1.0:
            return false
        n := 8
        s := 1
        while s < n:
            u := s * 1.0 / n
            x := a[0] + (b[0] - a[0]) * u
            z := a[2] + (b[2] - a[2]) * u
            y := a[1] + (b[1] - a[1]) * u
            h := self.height_at(x, z, y)
            if h == null or math.abs(h - y) > tol:
                return false
            s += 1
        return true

# Vrai si p et q sont alignés avec l'apex mais de part et d'autre de lui (entonnoir plat de 180° : agent posé sur une
# arête) ; ce n'est pas un croisement des bords.
func _opposite(apex, p, q):
    if math.abs(_area2(apex, p, q)) > 0.000000001:
        return false
    return (p[0] - apex[0]) * (q[0] - apex[0]) + (p[2] - apex[2]) * (q[2] - apex[2]) < 0.0

# Algorithme de l'entonnoir (« simple stupid funnel ») dans le plan XZ sur une suite de portes [gauche, droite].
func _funnel(portals):
    pts := [portals[0][0]]
    apex := portals[0][0]
    left := portals[0][0]
    right := portals[0][1]
    ai_ := 0
    li := 0
    ri := 0
    i := 1
    guard := 0
    limit := len(portals) * len(portals) + 16
    while i < len(portals) and guard < limit:
        guard += 1
        nl := portals[i][0]
        nr := portals[i][1]
        if _area2(apex, right, nr) >= 0.0:
            if _veq(apex, right) or _area2(apex, left, nr) < 0.0 or _opposite(apex, left, nr):
                right = nr
                ri = i
            else:
                append(pts, left)
                apex = left
                ai_ = li
                left = apex
                right = apex
                li = ai_
                ri = ai_
                i = ai_ + 1
                continue
        if _area2(apex, left, nl) <= 0.0:
            if _veq(apex, left) or _area2(apex, right, nl) > 0.0 or _opposite(apex, right, nl):
                left = nl
                li = i
            else:
                append(pts, right)
                apex = right
                ai_ = ri
                left = apex
                right = apex
                li = ai_
                ri = ai_
                i = ai_ + 1
                continue
        i += 1
    last := portals[len(portals) - 1][0]
    if not _veq(pts[len(pts) - 1], last):
        append(pts, last)
    return pts

const BIG_NAV := 1000000000000.0

# Navmesh depuis un maillage de `mesh` (champs positions et indices) ; max_slope en degrés.
func navmesh_from_mesh(m, max_slope=45.0):
    return NavMesh(m.positions, m.indices, max_slope)

# Longueur d'un chemin 3D (liste de points).
func path_length_3d(path):
    total := 0.0
    k := 0
    while k < len(path) - 1:
        total = total + _v3dist(path[k], path[k + 1])
        k += 1
    return total
