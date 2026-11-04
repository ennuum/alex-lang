use math
from core use len, is_int, is_float, is_bool, is_list, is_tuple
from collections use append

# ALEX STANDARD LIBRARY - array
# Tableaux N-dimensionnels homogènes (style NumPy). Pure ALEX, aucune dépendance native.
# C'est le socle de linalg, stats, numeric et calculus.
#
#   use array
#   a := array.from_list([[1, 2, 3], [4, 5, 6]])      # forme [2, 3]
#   b := array.add(a, 10)                             # broadcasting scalaire
#   c := array.matmul(a, array.transpose(a))          # produit matriciel 2x2
#   print(array.to_string(array.sum(a, 0)))           # [5, 7, 9]
#   print(a.reshape([3, 2]).to_string())              # chaînage par méthodes
#
# REPRÉSENTATION
#   Un tableau est une instance de la classe Array avec deux champs publics :
#     shape : liste d'entiers >= 0 (forme ; [] = scalaire 0-d)
#     data  : liste PLATE des éléments en ordre « ligne-majeur » (C order : le dernier indice varie le plus vite)
#   Les éléments sont des int, des float ou des bool. Les modules linalg/stats/... lisent .shape et .data
#   directement pour la vitesse ; ne les modifiez qu'en gardant len(data) == produit(shape).
#
# CONVENTIONS
#   - Le langage ne surcharge pas les opérateurs : array.add(a, b), array.mul(a, b), ... (ou a.add(b)).
#   - Toutes les fonctions acceptent un Array, une liste imbriquée ou un nombre (conversion par as_array) et
#     renvoient un NOUVEAU tableau (jamais de partage de data) ; seules set et put modifient en place.
#   - Broadcasting comme NumPy : les formes sont alignées par la droite, une dimension 1 se répète.
#   - Axes négatifs acceptés (-1 = dernier). axis=null signifie « tout le tableau, aplati ».
#   - Les indices négatifs sont acceptés par get/set/at/put (comme Python).
#   - Erreurs : ValueError (forme/argument), TypeError (type), IndexError (indice hors bornes),
#     ZeroDivisionError (division entière ou modulo par zéro).
#
# PERFORMANCE
#   ≈ 4 M d'opérations élémentaires par seconde : un matmul 100x100 prend ≈ 0,5 s. Les boucles internes
#   travaillent sur la liste plate sans allocation intermédiaire.

# =====================================================================================================
# Classe Array
# =====================================================================================================

class Array:
    func init(shape, data):
        self.shape = shape
        self.data = data

    func ndim():
        return len(self.shape)

    func size():
        return len(self.data)

    func get(idx):
        return get(self, idx)

    func set(idx, value):
        set(self, idx, value)

    func copy():
        return copy(self)

    func reshape(new_shape):
        return reshape(self, new_shape)

    func transpose():
        return transpose(self)

    func flatten():
        return flatten(self)

    func to_list():
        return to_list(self)

    func to_string():
        return to_string(self)

    func map(f):
        return map(self, f)

    func add(other):
        return add(self, other)

    func sub(other):
        return sub(self, other)

    func mul(other):
        return mul(self, other)

    func div(other):
        return div(self, other)

    func dot(other):
        return dot(self, other)

    func sum(axis=null):
        return sum(self, axis)

    func mean(axis=null):
        return mean(self, axis)

    func min(axis=null):
        return min(self, axis)

    func max(axis=null):
        return max(self, axis)

# =====================================================================================================
# Constantes et utilitaires internes
# =====================================================================================================

const INF := 10.0 ** 400
const NAN := INF - INF

func _is_num(x):
    return is_int(x) or is_float(x)

func _is_elem(x):
    return is_int(x) or is_float(x) or is_bool(x)

func _size_of(shape):
    n := 1
    for d in shape:
        n = n * d
    return n

func _strides_of(shape):
    nd := len(shape)
    st := []
    i := 0
    while i < nd:
        append(st, 0)
        i = i + 1
    acc := 1
    i = nd - 1
    while i >= 0:
        st[i] = acc
        acc = acc * shape[i]
        i = i - 1
    return st

func _filled(n, value):
    out := []
    i := 0
    while i < n:
        append(out, value)
        i = i + 1
    return out

func _copy_list(l):
    out := []
    for x in l:
        append(out, x)
    return out

func _shape_list(shape, who):
    if is_int(shape):
        shape = [shape]
    out := []
    if is_list(shape) or is_tuple(shape):
        for d in shape:
            if not is_int(d) or d < 0:
                raise("ValueError", f"{who} : dimension invalide {d} (entier >= 0 attendu)")
            append(out, d)
        return out
    raise("TypeError", f"{who} : la forme doit être un entier ou une liste d'entiers")

func _norm_axis(axis, nd, who):
    if not is_int(axis):
        raise("TypeError", f"{who} : axe entier attendu")
    ax := axis
    if ax < 0:
        ax = ax + nd
    if ax < 0 or ax >= nd:
        raise("ValueError", f"{who} : axe {axis} hors limites pour un tableau de dimension {nd}")
    return ax

# Découpe en (extérieur, n, intérieur) autour d'un axe : data[(o * n + k) * inner + i].
func _axis_split(shape, axis):
    outer := 1
    i := 0
    while i < axis:
        outer = outer * shape[i]
        i = i + 1
    inner := 1
    i = axis + 1
    while i < len(shape):
        inner = inner * shape[i]
        i = i + 1
    return [outer, shape[axis], inner]

func _drop_axis(shape, axis):
    out := []
    i := 0
    while i < len(shape):
        if i != axis:
            append(out, shape[i])
        i = i + 1
    return out

func _same_shape(s1, s2):
    if len(s1) != len(s2):
        return false
    i := 0
    while i < len(s1):
        if s1[i] != s2[i]:
            return false
        i = i + 1
    return true

# Parcourt une forme avec des pas arbitraires (transposition, diffusion, tranches, inversion).
func _gather(data, shape, strides, base):
    total := _size_of(shape)
    out := []
    if total == 0:
        return out
    nd := len(shape)
    if nd == 0:
        append(out, data[base])
        return out
    idx := _filled(nd, 0)
    pos := base
    k := 0
    while k < total:
        append(out, data[pos])
        d := nd - 1
        while d >= 0:
            idx[d] = idx[d] + 1
            pos = pos + strides[d]
            if idx[d] < shape[d]:
                break
            pos = pos - strides[d] * shape[d]
            idx[d] = 0
            d = d - 1
        k = k + 1
    return out

func _new(shape, data):
    return Array(shape, data)

# Construit un tableau SANS copier ni valider : réservé aux modules frères (linalg, stats, ...) qui
# viennent de fabriquer eux-mêmes `shape` et `data` et ne les réutilisent plus.
func wrap(shape, data):
    return Array(shape, data)

# =====================================================================================================
# Construction
# =====================================================================================================

func _infer_shape(x):
    shape := []
    cur := x
    while is_list(cur):
        append(shape, len(cur))
        if len(cur) == 0:
            break
        cur = cur[0]
    return shape

func _flatten_into(x, depth, shape, out):
    if depth == len(shape):
        if not _is_elem(x):
            raise("TypeError", "from_list : éléments numériques attendus (liste irrégulière ou type invalide)")
        append(out, x)
        return null
    if not is_list(x) or len(x) != shape[depth]:
        raise("ValueError", "from_list : liste imbriquée irrégulière (sous-listes de longueurs différentes)")
    for e in x:
        _flatten_into(e, depth + 1, shape, out)
    return null

# Construit un tableau depuis un nombre ou une liste imbriquée rectangulaire.
func from_list(x):
    if isinstance(x, Array):
        return copy(x)
    if _is_elem(x):
        return _new([], [x])
    if not is_list(x):
        raise("TypeError", "from_list : nombre ou liste imbriquée attendu")
    shape := _infer_shape(x)
    out := []
    _flatten_into(x, 0, shape, out)
    return _new(shape, out)

# Construit un tableau depuis une liste plate et une forme.
func from_flat(data, shape):
    sh := _shape_list(shape, "from_flat")
    if not is_list(data):
        raise("TypeError", "from_flat : liste attendue")
    if len(data) != _size_of(sh):
        raise("ValueError", f"from_flat : {len(data)} éléments pour la forme {sh}")
    for x in data:
        if not _is_elem(x):
            raise("TypeError", "from_flat : éléments numériques attendus")
    return _new(sh, _copy_list(data))

# Conversion tolérante : Array (renvoyé tel quel), nombre ou liste imbriquée.
func as_array(x):
    if isinstance(x, Array):
        return x
    return from_list(x)

func is_array(x):
    return isinstance(x, Array)

func copy(a):
    a = as_array(a)
    return _new(_copy_list(a.shape), _copy_list(a.data))

func full(shape, value):
    sh := _shape_list(shape, "full")
    return _new(sh, _filled(_size_of(sh), value))

func zeros(shape):
    return full(shape, 0.0)

func ones(shape):
    return full(shape, 1.0)

func full_like(a, value):
    a = as_array(a)
    return _new(_copy_list(a.shape), _filled(len(a.data), value))

func zeros_like(a):
    return full_like(a, 0.0)

func ones_like(a):
    return full_like(a, 1.0)

# Valeurs start, start+step, ... strictement avant stop (comme range/numpy.arange). arange(5) -> 0..4.
func arange(start, stop=null, step=1):
    if stop == null:
        stop = start
        start = 0
    if step == 0:
        raise("ValueError", "arange : le pas ne peut pas être nul")
    n := math.ceil((stop - start) / step)
    if n < 0:
        n = 0
    out := []
    i := 0
    while i < n:
        append(out, start + i * step)
        i = i + 1
    return _new([n], out)

# num points régulièrement espacés de start à stop (stop inclus si endpoint).
func linspace(start, stop, num=50, endpoint=true):
    if not is_int(num) or num < 0:
        raise("ValueError", "linspace : num doit être un entier >= 0")
    out := []
    if num == 0:
        return _new([0], out)
    if num == 1:
        append(out, start * 1.0)
        return _new([1], out)
    div_by := num - 1
    if not endpoint:
        div_by = num
    step := (stop - start) / div_by
    i := 0
    while i < num:
        append(out, start + i * step)
        i = i + 1
    if endpoint:
        out[num - 1] = stop * 1.0
    return _new([num], out)

# num points base^start ... base^stop espacés régulièrement en échelle logarithmique.
func logspace(start, stop, num=50, base=10.0):
    ex := linspace(start, stop, num)
    out := []
    for e in ex.data:
        append(out, base ** e)
    return _new([num], out)

# Matrice n x m avec des 1 sur la k-ième diagonale (k > 0 : au-dessus, k < 0 : au-dessous).
func eye(n, m=null, k=0):
    if m == null:
        m = n
    if not is_int(n) or not is_int(m) or n < 0 or m < 0:
        raise("ValueError", "eye : dimensions entières >= 0 attendues")
    out := _filled(n * m, 0.0)
    i := 0
    while i < n:
        j := i + k
        if j >= 0 and j < m:
            out[i * m + j] = 1.0
        i = i + 1
    return _new([n, m], out)

func identity(n):
    return eye(n)

# diag(vecteur) -> matrice diagonale ; diag(matrice) -> vecteur de la k-ième diagonale.
func diag(a, k=0):
    a = as_array(a)
    nd := len(a.shape)
    if nd == 1:
        n := a.shape[0] + abs_int(k)
        out := _filled(n * n, 0.0)
        i := 0
        while i < a.shape[0]:
            r := i
            c := i + k
            if k < 0:
                r = i - k
                c = i
            out[r * n + c] = a.data[i]
            i = i + 1
        return _new([n, n], out)
    if nd == 2:
        rows := a.shape[0]
        cols := a.shape[1]
        out := []
        i := 0
        while i < rows:
            j := i + k
            if j >= 0 and j < cols:
                append(out, a.data[i * cols + j])
            i = i + 1
        return _new([len(out)], out)
    raise("ValueError", "diag : tableau 1-d ou 2-d attendu")

func abs_int(x):
    if x < 0:
        return 0 - x
    return x

# Grilles de coordonnées (indexation « xy ») : renvoie [X, Y] de forme [len(y), len(x)].
func meshgrid(x, y):
    x = as_array(x)
    y = as_array(y)
    if len(x.shape) != 1 or len(y.shape) != 1:
        raise("ValueError", "meshgrid : deux vecteurs 1-d attendus")
    nx := x.shape[0]
    ny := y.shape[0]
    xs := []
    ys := []
    j := 0
    while j < ny:
        i := 0
        while i < nx:
            append(xs, x.data[i])
            append(ys, y.data[j])
            i = i + 1
        j = j + 1
    return [_new([ny, nx], xs), _new([ny, nx], ys)]

# =====================================================================================================
# Informations et accès
# =====================================================================================================

func ndim(a):
    return len(as_array(a).shape)

func size(a):
    return len(as_array(a).data)

func shape(a):
    return _copy_list(as_array(a).shape)

func _offset(a, idx, who):
    shp := a.shape
    nd := len(shp)
    if is_int(idx):
        if nd != 1:
            raise("IndexError", f"{who} : {nd} indices requis, 1 fourni")
        i := idx
        if i < 0:
            i = i + shp[0]
        if i < 0 or i >= shp[0]:
            raise("IndexError", f"{who} : indice {idx} hors bornes (taille {shp[0]})")
        return i
    if not is_list(idx) and not is_tuple(idx):
        raise("TypeError", f"{who} : indice entier ou liste d'indices attendu")
    if len(idx) != nd:
        raise("IndexError", f"{who} : {nd} indices requis, {len(idx)} fournis")
    st := _strides_of(shp)
    off := 0
    k := 0
    for raw in idx:
        i := raw
        if not is_int(i):
            raise("TypeError", f"{who} : les indices doivent être des entiers")
        if i < 0:
            i = i + shp[k]
        if i < 0 or i >= shp[k]:
            raise("IndexError", f"{who} : indice {raw} hors bornes pour l'axe {k} (taille {shp[k]})")
        off = off + i * st[k]
        k = k + 1
    return off

# Élément d'indice idx (entier pour un vecteur, liste [i, j, ...] sinon).
func get(a, idx):
    a = as_array(a)
    return a.data[_offset(a, idx, "get")]

# Modifie l'élément EN PLACE.
func set(a, idx, value):
    if not isinstance(a, Array):
        raise("TypeError", "set : Array attendu")
    if not _is_elem(value):
        raise("TypeError", "set : valeur numérique attendue")
    a.data[_offset(a, idx, "set")] = value

# Accès rapide aux matrices 2-d : élément (i, j).
func at(a, i, j):
    a = as_array(a)
    if len(a.shape) != 2:
        raise("ValueError", "at : matrice 2-d attendue")
    rows := a.shape[0]
    cols := a.shape[1]
    ii := i
    jj := j
    if ii < 0:
        ii = ii + rows
    if jj < 0:
        jj = jj + cols
    if ii < 0 or ii >= rows or jj < 0 or jj >= cols:
        raise("IndexError", f"at : ({i}, {j}) hors bornes pour la forme {a.shape}")
    return a.data[ii * cols + jj]

# Modifie l'élément (i, j) d'une matrice EN PLACE.
func put(a, i, j, value):
    if not isinstance(a, Array) or len(a.shape) != 2:
        raise("TypeError", "put : matrice Array 2-d attendue")
    rows := a.shape[0]
    cols := a.shape[1]
    ii := i
    jj := j
    if ii < 0:
        ii = ii + rows
    if jj < 0:
        jj = jj + cols
    if ii < 0 or ii >= rows or jj < 0 or jj >= cols:
        raise("IndexError", f"put : ({i}, {j}) hors bornes pour la forme {a.shape}")
    a.data[ii * cols + jj] = value

# Valeur unique d'un tableau à un seul élément.
func item(a):
    a = as_array(a)
    if len(a.data) != 1:
        raise("ValueError", f"item : {len(a.data)} éléments (1 attendu)")
    return a.data[0]

func _nest(data, shp, depth, off, st):
    if depth == len(shp):
        return data[off]
    out := []
    i := 0
    while i < shp[depth]:
        append(out, _nest(data, shp, depth + 1, off + i * st[depth], st))
        i = i + 1
    return out

# Liste imbriquée (un scalaire pour un tableau 0-d).
func to_list(a):
    a = as_array(a)
    return _nest(a.data, a.shape, 0, 0, _strides_of(a.shape))

# Copie de la liste plate des éléments.
func to_flat_list(a):
    return _copy_list(as_array(a).data)

func to_string(a):
    return f"{to_list(a)}"

# =====================================================================================================
# Manipulation de forme
# =====================================================================================================

# Même données, nouvelle forme (un seul -1 est déduit).
func reshape(a, new_shape):
    a = as_array(a)
    sh := []
    for d in new_shape:
        append(sh, d)
    unknown := -1
    known := 1
    k := 0
    while k < len(sh):
        if sh[k] == -1:
            if unknown != -1:
                raise("ValueError", "reshape : un seul -1 est autorisé")
            unknown = k
        else:
            if not is_int(sh[k]) or sh[k] < 0:
                raise("ValueError", f"reshape : dimension invalide {sh[k]}")
            known = known * sh[k]
        k = k + 1
    n := len(a.data)
    if unknown != -1:
        if known == 0 or n % known != 0:
            raise("ValueError", f"reshape : impossible de remplir la forme {new_shape} avec {n} éléments")
        sh[unknown] = n // known
    if _size_of(sh) != n:
        raise("ValueError", f"reshape : {n} éléments ne rentrent pas dans la forme {sh}")
    return _new(sh, _copy_list(a.data))

func flatten(a):
    a = as_array(a)
    return _new([len(a.data)], _copy_list(a.data))

func ravel(a):
    return flatten(a)

# Permutation des axes (par défaut : inversion, c'est la transposée d'une matrice).
func transpose(a, axes=null):
    a = as_array(a)
    nd := len(a.shape)
    perm := []
    if axes == null:
        i := nd - 1
        while i >= 0:
            append(perm, i)
            i = i - 1
    else:
        if len(axes) != nd:
            raise("ValueError", "transpose : la permutation doit couvrir tous les axes")
        seen := _filled(nd, false)
        for ax in axes:
            w := _norm_axis(ax, nd, "transpose")
            if seen[w]:
                raise("ValueError", "transpose : axe répété dans la permutation")
            seen[w] = true
            append(perm, w)
    st := _strides_of(a.shape)
    out_shape := []
    src := []
    for ax in perm:
        append(out_shape, a.shape[ax])
        append(src, st[ax])
    return _new(out_shape, _gather(a.data, out_shape, src, 0))

func swapaxes(a, axis1, axis2):
    a = as_array(a)
    nd := len(a.shape)
    x := _norm_axis(axis1, nd, "swapaxes")
    y := _norm_axis(axis2, nd, "swapaxes")
    perm := []
    i := 0
    while i < nd:
        append(perm, i)
        i = i + 1
    perm[x] = y
    perm[y] = x
    return transpose(a, perm)

# Supprime les axes de taille 1.
func squeeze(a):
    a = as_array(a)
    sh := []
    for d in a.shape:
        if d != 1:
            append(sh, d)
    return _new(sh, _copy_list(a.data))

# Insère un axe de taille 1 en position axis.
func expand_dims(a, axis):
    a = as_array(a)
    nd := len(a.shape)
    ax := axis
    if ax < 0:
        ax = ax + nd + 1
    if ax < 0 or ax > nd:
        raise("ValueError", f"expand_dims : axe {axis} hors limites")
    sh := []
    i := 0
    while i < nd:
        if i == ax:
            append(sh, 1)
        append(sh, a.shape[i])
        i = i + 1
    if ax == nd:
        append(sh, 1)
    return _new(sh, _copy_list(a.data))

func _broadcast_shape(s1, s2, who):
    n1 := len(s1)
    n2 := len(s2)
    n := n1
    if n2 > n:
        n = n2
    out := []
    k := 0
    while k < n:
        d1 := 1
        d2 := 1
        if k >= n - n1:
            d1 = s1[k - (n - n1)]
        if k >= n - n2:
            d2 = s2[k - (n - n2)]
        if d1 == d2:
            append(out, d1)
        elif d1 == 1:
            append(out, d2)
        elif d2 == 1:
            append(out, d1)
        else:
            raise("ValueError", f"{who} : formes {s1} et {s2} incompatibles pour le broadcasting")
        k = k + 1
    return out

# Pas de lecture d'un tableau de forme shp lu avec la forme out (0 sur les dimensions diffusées).
func _bstrides(shp, out):
    n := len(out)
    off := n - len(shp)
    st := _strides_of(shp)
    res := _filled(n, 0)
    k := 0
    while k < len(shp):
        if shp[k] != 1:
            res[k + off] = st[k]
        k = k + 1
    return res

# Étend (matérialise) a vers une forme compatible.
func broadcast_to(a, shape):
    a = as_array(a)
    target := _shape_list(shape, "broadcast_to")
    check := _broadcast_shape(a.shape, target, "broadcast_to")
    if not _same_shape(check, target):
        raise("ValueError", f"broadcast_to : {a.shape} ne se diffuse pas vers {target}")
    return _new(target, _gather(a.data, target, _bstrides(a.shape, target), 0))

# Extrait a[start:stop:step] le long d'un axe (indices négatifs acceptés, stop=null : jusqu'à la fin).
func slice_axis(a, axis, start=0, stop=null, step=1):
    a = as_array(a)
    nd := len(a.shape)
    ax := _norm_axis(axis, nd, "slice_axis")
    n := a.shape[ax]
    if step == 0:
        raise("ValueError", "slice_axis : le pas ne peut pas être nul")
    s := start
    e := stop
    if e == null:
        e = n
        if step < 0:
            e = -1 - n
    if s < 0:
        s = s + n
    if e < 0:
        e = e + n
    if step > 0:
        if s < 0:
            s = 0
        if e > n:
            e = n
    else:
        if s >= n:
            s = n - 1
        if e < -1:
            e = -1
    count := 0
    if step > 0 and e > s:
        count = (e - s + step - 1) // step
    if step < 0 and s > e:
        count = (s - e - step - 1) // (0 - step)
    st := _strides_of(a.shape)
    out_shape := _copy_list(a.shape)
    out_shape[ax] = count
    src := _copy_list(st)
    src[ax] = st[ax] * step
    base := 0
    if count > 0:
        base = s * st[ax]
    return _new(out_shape, _gather(a.data, out_shape, src, base))

# Sous-tableau d'indice i selon l'axe (cet axe disparaît) : select(M, 0, i) est la ligne i.
func select(a, axis, index):
    a = as_array(a)
    nd := len(a.shape)
    ax := _norm_axis(axis, nd, "select")
    n := a.shape[ax]
    i := index
    if i < 0:
        i = i + n
    if i < 0 or i >= n:
        raise("IndexError", f"select : indice {index} hors bornes (taille {n})")
    st := _strides_of(a.shape)
    out_shape := _drop_axis(a.shape, ax)
    src := _drop_axis(st, ax)
    return _new(out_shape, _gather(a.data, out_shape, src, i * st[ax]))

func row(a, i):
    return select(a, 0, i)

func col(a, j):
    return select(a, 1, j)

# Bloc de lignes r0..r1-1 et colonnes c0..c1-1 d'une matrice.
func submatrix(a, r0, r1, c0, c1):
    a = as_array(a)
    if len(a.shape) != 2:
        raise("ValueError", "submatrix : matrice 2-d attendue")
    return slice_axis(slice_axis(a, 0, r0, r1), 1, c0, c1)

# Retourne le tableau le long d'un axe (ou tous les axes si axis=null).
func flip(a, axis=null):
    a = as_array(a)
    nd := len(a.shape)
    if axis == null:
        out := a
        k := 0
        while k < nd:
            out = flip(out, k)
            k = k + 1
        return copy(out)
    ax := _norm_axis(axis, nd, "flip")
    return slice_axis(a, ax, -1, null, -1)

# Colle des tableaux le long d'un axe existant.
func concatenate(arrays, axis=0):
    if len(arrays) == 0:
        raise("ValueError", "concatenate : liste de tableaux vide")
    first := as_array(arrays[0])
    nd := len(first.shape)
    if nd == 0:
        raise("ValueError", "concatenate : les scalaires 0-d ne se concatènent pas")
    ax := _norm_axis(axis, nd, "concatenate")
    items := []
    total_n := 0
    for x in arrays:
        t := as_array(x)
        if len(t.shape) != nd:
            raise("ValueError", "concatenate : tous les tableaux doivent avoir le même nombre de dimensions")
        k := 0
        while k < nd:
            if k != ax and t.shape[k] != first.shape[k]:
                raise("ValueError", f"concatenate : formes incompatibles {first.shape} et {t.shape} (axe {ax})")
            k = k + 1
        total_n = total_n + t.shape[ax]
        append(items, t)
    parts := _axis_split(first.shape, ax)
    outer := parts[0]
    inner := parts[2]
    out := []
    o := 0
    while o < outer:
        for t in items:
            block := t.shape[ax] * inner
            base := o * block
            i := 0
            while i < block:
                append(out, t.data[base + i])
                i = i + 1
        o = o + 1
    out_shape := _copy_list(first.shape)
    out_shape[ax] = total_n
    return _new(out_shape, out)

# Empile des tableaux de même forme le long d'un NOUVEL axe.
func stack(arrays, axis=0):
    if len(arrays) == 0:
        raise("ValueError", "stack : liste de tableaux vide")
    first := as_array(arrays[0])
    nd := len(first.shape) + 1
    ax := axis
    if ax < 0:
        ax = ax + nd
    items := []
    for x in arrays:
        t := as_array(x)
        if not _same_shape(t.shape, first.shape):
            raise("ValueError", f"stack : formes différentes {first.shape} et {t.shape}")
        append(items, expand_dims(t, ax))
    return concatenate(items, ax)

func vstack(arrays):
    items := []
    for x in arrays:
        t := as_array(x)
        if len(t.shape) == 1:
            t = expand_dims(t, 0)
        append(items, t)
    return concatenate(items, 0)

func hstack(arrays):
    items := []
    all_1d := true
    for x in arrays:
        t := as_array(x)
        if len(t.shape) != 1:
            all_1d = false
        append(items, t)
    if all_1d:
        return concatenate(items, 0)
    return concatenate(items, 1)

# =====================================================================================================
# Opérations élément par élément
# =====================================================================================================

# Applique f à chaque élément (f : fonction nommée ou de module, ex. math.sqrt).
func map(a, f):
    a = as_array(a)
    out := []
    for x in a.data:
        append(out, f(x))
    return _new(_copy_list(a.shape), out)

# Applique f(x, y) élément par élément avec broadcasting.
func map2(a, b, f):
    a = as_array(a)
    b = as_array(b)
    na := len(a.data)
    nb := len(b.data)
    out := []
    if _same_shape(a.shape, b.shape):
        i := 0
        while i < na:
            append(out, f(a.data[i], b.data[i]))
            i = i + 1
        return _new(_copy_list(a.shape), out)
    if nb == 1 and len(b.shape) == 0:
        y := b.data[0]
        for x in a.data:
            append(out, f(x, y))
        return _new(_copy_list(a.shape), out)
    if na == 1 and len(a.shape) == 0:
        x := a.data[0]
        for y in b.data:
            append(out, f(x, y))
        return _new(_copy_list(b.shape), out)
    out_shape := _broadcast_shape(a.shape, b.shape, "map2")
    total := _size_of(out_shape)
    if total == 0:
        return _new(out_shape, out)
    sa := _bstrides(a.shape, out_shape)
    sb := _bstrides(b.shape, out_shape)
    nd := len(out_shape)
    idx := _filled(nd, 0)
    ia := 0
    ib := 0
    k := 0
    while k < total:
        append(out, f(a.data[ia], b.data[ib]))
        d := nd - 1
        while d >= 0:
            idx[d] = idx[d] + 1
            ia = ia + sa[d]
            ib = ib + sb[d]
            if idx[d] < out_shape[d]:
                break
            ia = ia - sa[d] * out_shape[d]
            ib = ib - sb[d] * out_shape[d]
            idx[d] = 0
            d = d - 1
        k = k + 1
    return _new(out_shape, out)

func _add(x, y):
    return x + y

func _sub(x, y):
    return x - y

func _mul(x, y):
    return x * y

func _div(x, y):
    if y == 0:
        raise("ZeroDivisionError", "div : division par zéro")
    return x / y

func _floordiv(x, y):
    if y == 0:
        raise("ZeroDivisionError", "floordiv : division par zéro")
    return x // y

func _mod(x, y):
    if y == 0:
        raise("ZeroDivisionError", "mod : modulo par zéro")
    return x % y

func _pow(x, y):
    return x ** y

func _maximum(x, y):
    if y > x:
        return y
    return x

func _minimum(x, y):
    if y < x:
        return y
    return x

func add(a, b):
    return map2(a, b, _add)

func sub(a, b):
    return map2(a, b, _sub)

func mul(a, b):
    return map2(a, b, _mul)

func div(a, b):
    return map2(a, b, _div)

func floordiv(a, b):
    return map2(a, b, _floordiv)

func mod(a, b):
    return map2(a, b, _mod)

func power(a, b):
    return map2(a, b, _pow)

func maximum(a, b):
    return map2(a, b, _maximum)

func minimum(a, b):
    return map2(a, b, _minimum)

func _neg(x):
    return 0 - x

func _square(x):
    return x * x

func _sign(x):
    if x > 0:
        return 1
    if x < 0:
        return -1
    return 0

func neg(a):
    return map(a, _neg)

func abs(a):
    return map(a, math.abs)

func square(a):
    return map(a, _square)

# Racine carrée élément par élément ; NAN pour un élément négatif (comme NumPy).
func _sqrt(x):
    if x < 0:
        return NAN
    return math.sqrt(x)

func _log(x):
    if x < 0:
        return NAN
    if x == 0:
        return 0.0 - INF
    return math.ln(x)

func sqrt(a):
    return map(a, _sqrt)

func exp(a):
    return map(a, math.exp)

# Logarithme népérien ; NAN pour x < 0, -inf pour x = 0.
func log(a):
    return map(a, _log)

func sin(a):
    return map(a, math.sin)

func cos(a):
    return map(a, math.cos)

func tan(a):
    return map(a, math.tan)

func floor(a):
    return map(a, math.floor)

func ceil(a):
    return map(a, math.ceil)

func sign(a):
    return map(a, _sign)

# Arrondi à ndigits décimales (0 par défaut), demi-unités vers l'infini (math.round). Les flottants restent flottants.
func round(a, ndigits=0):
    a = as_array(a)
    scale := 10.0 ** ndigits
    out := []
    for x in a.data:
        if is_float(x) and x == x and x != INF and x != 0.0 - INF:
            append(out, math.round(x * scale) / scale)
        else:
            append(out, x)
    return _new(_copy_list(a.shape), out)

# Borne les valeurs dans [lo, hi].
func clip(a, lo, hi):
    if lo > hi:
        raise("ValueError", "clip : lo > hi")
    return minimum(maximum(a, lo), hi)

func to_float(a):
    a = as_array(a)
    out := []
    for x in a.data:
        append(out, x * 1.0)
    return _new(_copy_list(a.shape), out)

# --- Comparaisons (renvoient des tableaux de bool) ---

func _eq(x, y):
    return x == y

func _ne(x, y):
    return x != y

func _lt(x, y):
    return x < y

func _le(x, y):
    return x <= y

func _gt(x, y):
    return x > y

func _ge(x, y):
    return x >= y

func eq(a, b):
    return map2(a, b, _eq)

func ne(a, b):
    return map2(a, b, _ne)

func lt(a, b):
    return map2(a, b, _lt)

func le(a, b):
    return map2(a, b, _le)

func gt(a, b):
    return map2(a, b, _gt)

func ge(a, b):
    return map2(a, b, _ge)

func _not(x):
    return not x

func logical_not(a):
    return map(a, _not)

# Sélection : cond ? x : y élément par élément, avec broadcasting des trois arguments.
func where(cond, x, y):
    c := as_array(cond)
    xa := as_array(x)
    ya := as_array(y)
    shp := _broadcast_shape(_broadcast_shape(c.shape, xa.shape, "where"), ya.shape, "where")
    cc := broadcast_to(c, shp)
    xx := broadcast_to(xa, shp)
    yy := broadcast_to(ya, shp)
    out := []
    i := 0
    while i < len(cc.data):
        if cc.data[i]:
            append(out, xx.data[i])
        else:
            append(out, yy.data[i])
        i = i + 1
    return _new(shp, out)

func _close(x, y, rtol, atol):
    d := x - y
    if d < 0:
        d = 0 - d
    ay := y
    if ay < 0:
        ay = 0 - ay
    return d <= atol + rtol * ay

# Égalité à tolérance : |a - b| <= atol + rtol * |b|, élément par élément.
func isclose(a, b, rtol=0.00001, atol=0.00000001):
    a = as_array(a)
    b = as_array(b)
    shp := _broadcast_shape(a.shape, b.shape, "isclose")
    aa := broadcast_to(a, shp)
    bb := broadcast_to(b, shp)
    out := []
    i := 0
    while i < len(aa.data):
        append(out, _close(aa.data[i], bb.data[i], rtol, atol))
        i = i + 1
    return _new(shp, out)

func allclose(a, b, rtol=0.00001, atol=0.00000001):
    return all(isclose(a, b, rtol, atol))

# Mêmes formes et mêmes éléments.
func array_equal(a, b):
    a = as_array(a)
    b = as_array(b)
    if not _same_shape(a.shape, b.shape):
        return false
    i := 0
    while i < len(a.data):
        if a.data[i] != b.data[i]:
            return false
        i = i + 1
    return true

# =====================================================================================================
# Réductions
# =====================================================================================================

# mode : 0 somme, 1 produit, 2 minimum, 3 maximum
func _fold_flat(data, mode, who):
    n := len(data)
    if n == 0:
        if mode == 0:
            return 0.0
        if mode == 1:
            return 1.0
        raise("ValueError", f"{who} : réduction d'un tableau vide")
    acc := data[0]
    i := 1
    if mode == 0:
        if is_float(acc):
            # Sommation compensée de Neumaier : erreur indépendante de la taille du tableau.
            s := acc
            c := 0.0
            while i < n:
                x := data[i]
                t := s + x
                ax := x
                if ax < 0:
                    ax = 0 - ax
                as_ := s
                if as_ < 0:
                    as_ = 0 - as_
                if as_ >= ax:
                    c = c + ((s - t) + x)
                else:
                    c = c + ((x - t) + s)
                s = t
                i = i + 1
            return s + c
        while i < n:
            acc = acc + data[i]
            i = i + 1
        return acc
    if mode == 1:
        while i < n:
            acc = acc * data[i]
            i = i + 1
        return acc
    if mode == 2:
        while i < n:
            if data[i] < acc:
                acc = data[i]
            i = i + 1
        return acc
    while i < n:
        if data[i] > acc:
            acc = data[i]
        i = i + 1
    return acc

func _fold(a, axis, mode, who):
    a = as_array(a)
    if axis == null:
        return _fold_flat(a.data, mode, who)
    nd := len(a.shape)
    ax := _norm_axis(axis, nd, who)
    parts := _axis_split(a.shape, ax)
    outer := parts[0]
    n := parts[1]
    inner := parts[2]
    if n == 0 and mode >= 2:
        raise("ValueError", f"{who} : réduction d'un axe vide")
    out := []
    o := 0
    while o < outer:
        i := 0
        while i < inner:
            if n == 0:
                if mode == 0:
                    append(out, 0.0)
                else:
                    append(out, 1.0)
            else:
                base := o * n * inner + i
                acc := a.data[base]
                k := 1
                while k < n:
                    x := a.data[base + k * inner]
                    if mode == 0:
                        acc = acc + x
                    elif mode == 1:
                        acc = acc * x
                    elif mode == 2:
                        if x < acc:
                            acc = x
                    else:
                        if x > acc:
                            acc = x
                    k = k + 1
                append(out, acc)
            i = i + 1
        o = o + 1
    return _new(_drop_axis(a.shape, ax), out)

func sum(a, axis=null):
    return _fold(a, axis, 0, "sum")

func prod(a, axis=null):
    return _fold(a, axis, 1, "prod")

func min(a, axis=null):
    return _fold(a, axis, 2, "min")

func max(a, axis=null):
    return _fold(a, axis, 3, "max")

# Moyenne arithmétique (toujours flottante).
func mean(a, axis=null):
    a = as_array(a)
    if axis == null:
        if len(a.data) == 0:
            raise("ValueError", "mean : moyenne d'un tableau vide")
        return _fold_flat(a.data, 0, "mean") / len(a.data)
    ax := _norm_axis(axis, len(a.shape), "mean")
    n := a.shape[ax]
    if n == 0:
        raise("ValueError", "mean : moyenne d'un axe vide")
    return div(_fold(a, ax, 0, "mean"), n * 1.0)

# Indice du plus petit (mode 0) ou plus grand (mode 1) élément ; première occurrence.
func _arg(a, axis, want_max, who):
    a = as_array(a)
    if axis == null:
        n := len(a.data)
        if n == 0:
            raise("ValueError", f"{who} : tableau vide")
        best := 0
        i := 1
        while i < n:
            if want_max:
                if a.data[i] > a.data[best]:
                    best = i
            else:
                if a.data[i] < a.data[best]:
                    best = i
            i = i + 1
        return best
    ax := _norm_axis(axis, len(a.shape), who)
    parts := _axis_split(a.shape, ax)
    outer := parts[0]
    n := parts[1]
    inner := parts[2]
    if n == 0:
        raise("ValueError", f"{who} : axe vide")
    out := []
    o := 0
    while o < outer:
        i := 0
        while i < inner:
            base := o * n * inner + i
            best := 0
            k := 1
            while k < n:
                x := a.data[base + k * inner]
                b := a.data[base + best * inner]
                if want_max:
                    if x > b:
                        best = k
                else:
                    if x < b:
                        best = k
                k = k + 1
            append(out, best)
            i = i + 1
        o = o + 1
    return _new(_drop_axis(a.shape, ax), out)

func argmin(a, axis=null):
    return _arg(a, axis, false, "argmin")

func argmax(a, axis=null):
    return _arg(a, axis, true, "argmax")

# Somme (mode 0) ou produit (mode 1) cumulés ; axis=null : sur le tableau aplati.
func _cum(a, axis, mode, who):
    a = as_array(a)
    if axis == null:
        out := []
        acc := 0
        i := 0
        while i < len(a.data):
            if i == 0:
                acc = a.data[0]
            elif mode == 0:
                acc = acc + a.data[i]
            else:
                acc = acc * a.data[i]
            append(out, acc)
            i = i + 1
        return _new([len(out)], out)
    ax := _norm_axis(axis, len(a.shape), who)
    parts := _axis_split(a.shape, ax)
    outer := parts[0]
    n := parts[1]
    inner := parts[2]
    out := _copy_list(a.data)
    o := 0
    while o < outer:
        i := 0
        while i < inner:
            base := o * n * inner + i
            k := 1
            while k < n:
                p := base + k * inner
                if mode == 0:
                    out[p] = out[p - inner] + out[p]
                else:
                    out[p] = out[p - inner] * out[p]
                k = k + 1
            i = i + 1
        o = o + 1
    return _new(_copy_list(a.shape), out)

func cumsum(a, axis=null):
    return _cum(a, axis, 0, "cumsum")

func cumprod(a, axis=null):
    return _cum(a, axis, 1, "cumprod")

func _truth(x):
    if x:
        return 1
    return 0

func _to_bool(x):
    return x == 1

# Vrai si au moins un élément est vrai (non nul) ; axis=null : bool, sinon tableau de bool.
func any(a, axis=null):
    t := map(a, _truth)
    if axis == null:
        if len(t.data) == 0:
            return false
        return _fold_flat(t.data, 3, "any") == 1
    return map(_fold(t, axis, 3, "any"), _to_bool)

# Vrai si tous les éléments sont vrais (non nuls).
func all(a, axis=null):
    t := map(a, _truth)
    if axis == null:
        if len(t.data) == 0:
            return true
        return _fold_flat(t.data, 2, "all") == 1
    return map(_fold(t, axis, 2, "all"), _to_bool)

func count_nonzero(a):
    a = as_array(a)
    n := 0
    for x in a.data:
        if x:
            n = n + 1
    return n

# =====================================================================================================
# Algèbre linéaire élémentaire (le reste est dans linalg)
# =====================================================================================================

# Produit scalaire (1-d x 1-d) ou matriciel : matvec, vecmat, matmat. Dimensions <= 2.
func matmul(a, b):
    a = as_array(a)
    b = as_array(b)
    na := len(a.shape)
    nb := len(b.shape)
    if na == 0 or nb == 0 or na > 2 or nb > 2:
        raise("ValueError", "matmul : tableaux 1-d ou 2-d attendus")
    if na == 1 and nb == 1:
        if a.shape[0] != b.shape[0]:
            raise("ValueError", f"matmul : longueurs différentes {a.shape[0]} et {b.shape[0]}")
        s := 0
        i := 0
        n := a.shape[0]
        if n > 0:
            s = a.data[0] * b.data[0]
            i = 1
        else:
            s = 0.0
        while i < n:
            s = s + a.data[i] * b.data[i]
            i = i + 1
        return s
    m := 1
    n := a.shape[0]
    if na == 2:
        m = a.shape[0]
        n = a.shape[1]
    p := 1
    nb_rows := b.shape[0]
    if nb == 2:
        p = b.shape[1]
    if n != nb_rows:
        raise("ValueError", f"matmul : formes incompatibles {a.shape} et {b.shape}")
    res := _filled(m * p, 0)
    i := 0
    while i < m:
        rb := i * p
        k := 0
        while k < n:
            aik := a.data[i * n + k]
            bb := k * p
            j := 0
            while j < p:
                res[rb + j] = res[rb + j] + aik * b.data[bb + j]
                j = j + 1
            k = k + 1
        i = i + 1
    if na == 1:
        return _new([p], res)
    if nb == 1:
        return _new([m], res)
    return _new([m, p], res)

func dot(a, b):
    return matmul(a, b)

# Produit extérieur de deux vecteurs : M[i][j] = a[i] * b[j].
func outer(a, b):
    a = as_array(a)
    b = as_array(b)
    if len(a.shape) != 1 or len(b.shape) != 1:
        raise("ValueError", "outer : deux vecteurs 1-d attendus")
    out := []
    for x in a.data:
        for y in b.data:
            append(out, x * y)
    return _new([a.shape[0], b.shape[0]], out)

# Somme des éléments de la k-ième diagonale d'une matrice.
func trace(a, k=0):
    d := diag(a, k)
    return _fold_flat(d.data, 0, "trace")

# =====================================================================================================
# Tri, recherche, différences
# =====================================================================================================

# Permutation qui trie la liste vals (tri fusion STABLE, O(n log n)).
func argsort_list(vals):
    n := len(vals)
    idx := []
    i := 0
    while i < n:
        append(idx, i)
        i = i + 1
    tmp := _copy_list(idx)
    width := 1
    while width < n:
        lo := 0
        while lo < n:
            mid := lo + width
            if mid > n:
                mid = n
            hi := lo + 2 * width
            if hi > n:
                hi = n
            p := lo
            q := mid
            k := lo
            while p < mid and q < hi:
                if vals[idx[q]] < vals[idx[p]]:
                    tmp[k] = idx[q]
                    q = q + 1
                else:
                    tmp[k] = idx[p]
                    p = p + 1
                k = k + 1
            while p < mid:
                tmp[k] = idx[p]
                p = p + 1
                k = k + 1
            while q < hi:
                tmp[k] = idx[q]
                q = q + 1
                k = k + 1
            lo = lo + 2 * width
        swap := idx
        idx = tmp
        tmp = swap
        width = width * 2
    return idx

# Nouvelle liste triée par ordre croissant (la liste d'origine n'est pas modifiée).
func sort_list(vals):
    order := argsort_list(vals)
    out := []
    for i in order:
        append(out, vals[i])
    return out

# Tri le long d'un axe (par défaut le dernier).
func sort(a, axis=-1):
    a = as_array(a)
    nd := len(a.shape)
    if nd == 0:
        return copy(a)
    ax := _norm_axis(axis, nd, "sort")
    parts := _axis_split(a.shape, ax)
    outer := parts[0]
    n := parts[1]
    inner := parts[2]
    out := _copy_list(a.data)
    o := 0
    while o < outer:
        i := 0
        while i < inner:
            base := o * n * inner + i
            line := []
            k := 0
            while k < n:
                append(line, a.data[base + k * inner])
                k = k + 1
            line = sort_list(line)
            k = 0
            while k < n:
                out[base + k * inner] = line[k]
                k = k + 1
            i = i + 1
        o = o + 1
    return _new(_copy_list(a.shape), out)

# Indices qui trieraient le tableau le long d'un axe (stable).
func argsort(a, axis=-1):
    a = as_array(a)
    nd := len(a.shape)
    if nd == 0:
        return _new([], [0])
    ax := _norm_axis(axis, nd, "argsort")
    parts := _axis_split(a.shape, ax)
    outer := parts[0]
    n := parts[1]
    inner := parts[2]
    out := _filled(len(a.data), 0)
    o := 0
    while o < outer:
        i := 0
        while i < inner:
            base := o * n * inner + i
            line := []
            k := 0
            while k < n:
                append(line, a.data[base + k * inner])
                k = k + 1
            order := argsort_list(line)
            k = 0
            while k < n:
                out[base + k * inner] = order[k]
                k = k + 1
            i = i + 1
        o = o + 1
    return _new(_copy_list(a.shape), out)

# Valeurs distinctes triées (tableau 1-d).
func unique(a):
    a = as_array(a)
    s := sort_list(a.data)
    out := []
    for x in s:
        if len(out) == 0 or out[len(out) - 1] != x:
            append(out, x)
    return _new([len(out)], out)

# Indice d'insertion de v dans la LISTE triée l (à gauche : avant les valeurs égales).
func searchsorted(l, v):
    lo := 0
    hi := len(l)
    while lo < hi:
        mid := (lo + hi) // 2
        if l[mid] < v:
            lo = mid + 1
        else:
            hi = mid
    return lo

# Différences successives le long d'un axe : out[k] = a[k+1] - a[k].
func diff(a, axis=-1):
    a = as_array(a)
    nd := len(a.shape)
    if nd == 0:
        raise("ValueError", "diff : tableau d'au moins une dimension attendu")
    ax := _norm_axis(axis, nd, "diff")
    n := a.shape[ax]
    if n == 0:
        return copy(a)
    hi := slice_axis(a, ax, 1, n)
    lo := slice_axis(a, ax, 0, n - 1)
    return sub(hi, lo)
