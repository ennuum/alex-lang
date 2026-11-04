# ALEX STANDARD LIBRARY — physics.spatial
#
# Hachage spatial 3D : une grille uniforme creuse qui indexe des boîtes englobantes (AABB) et répond en temps à peu
# près constant aux requêtes « qui est près de ici ? » (recouvrement de boîte, point, sphère, rayon, paires qui se
# touchent). C'est la phase large de `physics` pour les mondes de nombreux corps, mais il sert aussi à la logique de
# jeu (détection de proximité, ciblage, perception des IA). ALEX pur.
#
#   use physics.spatial as sp
#   h := sp.SpatialHash(2.0)                                  # côté d'une cellule, en mètres
#   h.insert(1, [0, 0, 0], [1, 1, 1])                         # identifiant ENTIER, puis les coins min et max
#   h.insert(2, [0.5, 0.5, 0.5], [2, 2, 2])
#   h.query_aabb([0, 0, 0], [0.6, 0.6, 0.6])                  # [1, 2]
#   h.pairs()                                                 # [[1, 2]]
#   h.update(2, [9, 9, 9], [10, 10, 10])                      # déplace un objet
#   h.query_ray([-5, 0.5, 0.5], [1, 0, 0], 20.0)              # identifiants dont une cellule est traversée par le rayon
#
# CHOIX DE LA CELLULE : de l'ordre de la taille d'un objet typique (trop petite = un objet occupe beaucoup de cellules ;
#   trop grande = beaucoup de faux candidats). `suggest_cell_size(liste_de_boîtes)` donne une valeur raisonnable.
# OBJETS TRÈS GRANDS : un objet qui couvrirait plus de `max_cells` cellules (sol immense, murs longs) est rangé à part
#   et fait partie de chaque requête, ce qui évite d'inscrire des milliers de cellules.
# Les résultats d'une requête sont triés par identifiant croissant : ils sont déterministes.
#
# Erreurs : ValueError (taille de cellule <= 0, identifiant déjà présent ou absent, boîte invalide).

use math
from core use len, to_int
from collections use append, pop, keys

const VERSION := "1.0.0"
const _BIGCELL := 1048576

# Clé entière d'une cellule (ix, iy, iz) : 20 bits par axe, exacte pour |i| < 524288.
func _ckey(ix, iy, iz):
    return ((ix & 1048575) << 40) | ((iy & 1048575) << 20) | (iz & 1048575)

func _cell(x, size):
    return to_int(math.floor(x / size))

# Taille de cellule conseillée : deux fois la plus grande dimension moyenne des boîtes [[min, max], ...], bornée par
# `minimum`. Les boîtes immenses (> 20 fois la médiane) sont ignorées pour ne pas fausser la moyenne.
func suggest_cell_size(boxes, minimum=0.25):
    if len(boxes) == 0:
        return 1.0
    sizes := []
    for b in boxes:
        e := math.max(b[1][0] - b[0][0], math.max(b[1][1] - b[0][1], b[1][2] - b[0][2]))
        append(sizes, e)
    lst := _sorted_copy(sizes)
    med := lst[len(lst) // 2]
    total := 0.0
    cnt := 0
    for e in sizes:
        if e <= med * 20.0 + 0.000001:
            total = total + e
            cnt += 1
    avg := total / math.max(cnt, 1)
    return math.max(avg * 2.0, minimum)

func _sorted_copy(a):
    out := []
    for x in a:
        append(out, x)
    # tri par insertion : les listes sont courtes ; pour les grandes, un tri fusion
    if len(out) > 64:
        return _merge_sort(out)
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

func _merge_sort(a):
    n := len(a)
    if n <= 1:
        return a
    mid := n // 2
    left := _merge_sort(a[0:mid])
    right := _merge_sort(a[mid:n])
    out := []
    i := 0
    j := 0
    while i < len(left) and j < len(right):
        if left[i] <= right[j]:
            append(out, left[i])
            i += 1
        else:
            append(out, right[j])
            j += 1
    while i < len(left):
        append(out, left[i])
        i += 1
    while j < len(right):
        append(out, right[j])
        j += 1
    return out

class SpatialHash:
    func init(cell_size=1.0, max_cells=512):
        if cell_size <= 0:
            raise("ValueError", "physics.spatial.SpatialHash : cell_size > 0 requis")
        self.cell_size = cell_size * 1.0
        self.max_cells = max_cells
        self._cells = {}
        self._bounds = {}
        self._keys = {}
        self._large = {}

    func size():
        return len(keys(self._bounds)) + len(keys(self._large))

    func contains(id):
        return (id in self._bounds) or (id in self._large)

    func clear():
        self._cells = {}
        self._bounds = {}
        self._keys = {}
        self._large = {}

    func bounds_of(id):
        if id in self._bounds:
            return self._bounds[id]
        if id in self._large:
            return self._large[id]
        return null

    # Ajoute l'objet `id` (entier) occupant la boîte [lo, hi].
    func insert(id, lo, hi):
        if self.contains(id):
            raise("ValueError", f"physics.spatial.SpatialHash.insert : identifiant {id} déjà présent")
        if lo[0] > hi[0] or lo[1] > hi[1] or lo[2] > hi[2]:
            raise("ValueError", "physics.spatial.SpatialHash.insert : boîte invalide (min > max)")
        bx := [[lo[0] * 1.0, lo[1] * 1.0, lo[2] * 1.0], [hi[0] * 1.0, hi[1] * 1.0, hi[2] * 1.0]]
        s := self.cell_size
        x0 := _cell(lo[0], s)
        y0 := _cell(lo[1], s)
        z0 := _cell(lo[2], s)
        x1 := _cell(hi[0], s)
        y1 := _cell(hi[1], s)
        z1 := _cell(hi[2], s)
        count := (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1)
        if count > self.max_cells or x1 - x0 >= _BIGCELL or y1 - y0 >= _BIGCELL or z1 - z0 >= _BIGCELL or x0 < -524000 or y0 < -524000 or z0 < -524000 or x1 > 524000 or y1 > 524000 or z1 > 524000:
            self._large[id] = bx
            return null
        self._bounds[id] = bx
        ks := []
        x := x0
        while x <= x1:
            y := y0
            while y <= y1:
                z := z0
                while z <= z1:
                    k := _ckey(x, y, z)
                    append(ks, k)
                    if k in self._cells:
                        append(self._cells[k], id)
                    else:
                        self._cells[k] = [id]
                    z += 1
                y += 1
            x += 1
        self._keys[id] = ks

    func remove(id):
        if id in self._large:
            del self._large[id]
            return true
        if not (id in self._bounds):
            return false
        for k in self._keys[id]:
            lst := self._cells[k]
            j := 0
            while j < len(lst):
                if lst[j] == id:
                    pop(lst, j)
                    break
                j += 1
            if len(lst) == 0:
                del self._cells[k]
        del self._bounds[id]
        del self._keys[id]
        return true

    # Déplace / redimensionne un objet (le crée s'il n'existait pas).
    func update(id, lo, hi):
        self.remove(id)
        self.insert(id, lo, hi)

    # Identifiants dont la boîte recouvre [lo, hi] (bords inclus), triés.
    func query_aabb(lo, hi):
        found := {}
        s := self.cell_size
        x0 := _cell(lo[0], s)
        y0 := _cell(lo[1], s)
        z0 := _cell(lo[2], s)
        x1 := _cell(hi[0], s)
        y1 := _cell(hi[1], s)
        z1 := _cell(hi[2], s)
        if (x1 - x0 + 1) * (y1 - y0 + 1) * (z1 - z0 + 1) > self.max_cells * 8:
            # requête énorme : balayage direct des objets plutôt que des cellules
            for id in keys(self._bounds):
                if _overlap(self._bounds[id], lo, hi):
                    found[id] = true
        else:
            x := x0
            while x <= x1:
                y := y0
                while y <= y1:
                    z := z0
                    while z <= z1:
                        k := _ckey(x, y, z)
                        if k in self._cells:
                            for id in self._cells[k]:
                                if not (id in found) and _overlap(self._bounds[id], lo, hi):
                                    found[id] = true
                        z += 1
                    y += 1
                x += 1
        for id in keys(self._large):
            if _overlap(self._large[id], lo, hi):
                found[id] = true
        return _sorted_copy(keys(found))

    func query_point(p):
        return self.query_aabb(p, p)

    # Candidats pour une sphère : recouvrement de sa boîte englobante, filtré par la distance à la boîte de l'objet.
    func query_sphere(center, radius):
        lo := [center[0] - radius, center[1] - radius, center[2] - radius]
        hi := [center[0] + radius, center[1] + radius, center[2] + radius]
        out := []
        for id in self.query_aabb(lo, hi):
            b := self.bounds_of(id)
            d2 := 0.0
            i := 0
            while i < 3:
                v := center[i]
                if v < b[0][i]:
                    d2 = d2 + (b[0][i] - v) * (b[0][i] - v)
                if v > b[1][i]:
                    d2 = d2 + (v - b[1][i]) * (v - b[1][i])
                i += 1
            if d2 <= radius * radius:
                append(out, id)
        return out

    # Objets dont la boîte est traversée par le rayon (origine, direction, distance max en unités de direction).
    # Parcours de cellules (DDA 3D) ; les boîtes sont ensuite testées exactement (méthode des dalles).
    func query_ray(origin, direction, max_t=1000.0):
        found := {}
        s := self.cell_size
        cx := _cell(origin[0], s)
        cy := _cell(origin[1], s)
        cz := _cell(origin[2], s)
        step := [0, 0, 0]
        tmax := [0.0, 0.0, 0.0]
        tdel := [0.0, 0.0, 0.0]
        cur := [cx, cy, cz]
        i := 0
        while i < 3:
            d := direction[i] * 1.0
            if d > 0.0:
                step[i] = 1
                tdel[i] = s / d
                tmax[i] = ((cur[i] + 1) * s - origin[i]) / d
            else:
                if d < 0.0:
                    step[i] = -1
                    tdel[i] = s / (0.0 - d)
                    tmax[i] = (origin[i] - cur[i] * s) / (0.0 - d)
                else:
                    step[i] = 0
                    tdel[i] = 1000000000000.0
                    tmax[i] = 1000000000000.0
            i += 1
        guard := 0
        t := 0.0
        while t <= max_t and guard < 100000:
            k := _ckey(cur[0], cur[1], cur[2])
            if k in self._cells:
                for id in self._cells[k]:
                    if not (id in found) and _ray_box(origin, direction, self._bounds[id], max_t):
                        found[id] = true
            ax := 0
            if tmax[1] < tmax[ax]:
                ax = 1
            if tmax[2] < tmax[ax]:
                ax = 2
            t = tmax[ax]
            cur[ax] = cur[ax] + step[ax]
            tmax[ax] = tmax[ax] + tdel[ax]
            guard += 1
        for id in keys(self._large):
            if _ray_box(origin, direction, self._large[id], max_t):
                found[id] = true
        return _sorted_copy(keys(found))

    # Toutes les paires [a, b] (a < b) dont les boîtes se recouvrent, triées.
    func pairs():
        seen := {}
        out := []
        for k in keys(self._cells):
            lst := self._cells[k]
            n := len(lst)
            if n < 2:
                continue
            i := 0
            while i < n:
                j := i + 1
                while j < n:
                    a := lst[i]
                    b := lst[j]
                    if a > b:
                        t := a
                        a = b
                        b = t
                    pk := a * 2147483648 + b
                    if not (pk in seen):
                        seen[pk] = true
                        if _overlap2(self._bounds[a], self._bounds[b]):
                            append(out, [a, b])
                    j += 1
                i += 1
        big := keys(self._large)
        for g in big:
            for id in keys(self._bounds):
                a := g
                b := id
                if a > b:
                    a = id
                    b = g
                if _overlap2(self.bounds_of(a), self.bounds_of(b)):
                    append(out, [a, b])
        gi := 0
        while gi < len(big):
            gj := gi + 1
            while gj < len(big):
                a := big[gi]
                b := big[gj]
                if a > b:
                    a = big[gj]
                    b = big[gi]
                if _overlap2(self._large[a], self._large[b]):
                    append(out, [a, b])
                gj += 1
            gi += 1
        return _sort_pairs(out)

func _sort_pairs(prs):
    keyed := []
    for p in prs:
        append(keyed, [p[0] * 2147483648 + p[1], p])
    ks := []
    for it in keyed:
        append(ks, it[0])
    order := _sorted_copy(ks)
    byk := {}
    for it in keyed:
        byk[it[0]] = it[1]
    out := []
    for k in order:
        append(out, byk[k])
    return out

func _overlap(b, lo, hi):
    return b[0][0] <= hi[0] and b[1][0] >= lo[0] and b[0][1] <= hi[1] and b[1][1] >= lo[1] and b[0][2] <= hi[2] and b[1][2] >= lo[2]

func _overlap2(a, b):
    return a[0][0] <= b[1][0] and a[1][0] >= b[0][0] and a[0][1] <= b[1][1] and a[1][1] >= b[0][1] and a[0][2] <= b[1][2] and a[1][2] >= b[0][2]

# Rayon contre boîte alignée (dalles) : vrai si le rayon la touche avant max_t.
func _ray_box(o, d, b, max_t):
    t0 := 0.0
    t1 := max_t
    i := 0
    while i < 3:
        if d[i] == 0.0:
            if o[i] < b[0][i] or o[i] > b[1][i]:
                return false
        else:
            a := (b[0][i] - o[i]) / d[i]
            c := (b[1][i] - o[i]) / d[i]
            if a > c:
                tmp := a
                a = c
                c = tmp
            if a > t0:
                t0 = a
            if c < t1:
                t1 = c
            if t0 > t1:
                return false
        i += 1
    return true
