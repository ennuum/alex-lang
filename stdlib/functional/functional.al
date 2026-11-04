# ALEX STANDARD LIBRARY — functional
# Programmation fonctionnelle sur listes, en ALEX pur : map/filter/reduce, zip, découpage, groupement, tri stable,
# combinatoire, combinateurs de fonctions (compose, partial, curry, memoize...) et chaînage fluide (Seq).
#
#   use functional
#   from functional use map, filter, reduce, pipe
#
#   carres := map([1, 2, 3, 4], x => x * x)                     # [1, 4, 9, 16]
#   pairs  := filter(carres, x => x % 2 == 0)                   # [4, 16]
#   somme  := reduce(pairs, (a, b) => a + b, 0)                 # 20
#   r := functional.seq([5, 3, 8, 1]).filter(x => x > 2).map(x => x * 10).sort_by().to_list()   # [30, 50, 80]
#
# CONVENTIONS
#   - Les données viennent EN PREMIER, la fonction ensuite : map(items, f). Cela permet un appel direct et un
#     chaînage lisible ; pour fixer la fonction d'abord, utiliser partial(...) ou la classe Seq.
#   - Calcul IMMÉDIAT (pas de paresse : le langage n'a pas de générateurs). Aucune fonction ne modifie ses arguments :
#     toutes renvoient une nouvelle liste ou un nouveau dict.
#   - `items` peut être une list, un tuple ou une str (une str est lue caractère par caractère, en str de longueur 1).
#   - Le langage n'a ni arguments variadiques ni intervalles utilisables comme valeurs : les combinateurs existent donc
#     par arité (partial / partial2, curry2 / curry3) et range_list(a, b) remplace a..b hors d'un for.
#   - Les fonctions qui utilisent une valeur comme CLÉ DE DICT (group_by, count_by, frequencies, unique, unique_by,
#     memoize, memoize2, from_pairs) exigent des clés hachables : nombres, bool, str, tuples (pas de list ni de dict ;
#     sinon TypeError « non hashable »). Pour regrouper par liste, convertissez-la d'abord (join, tuple...).
#   - Erreurs : TypeError (argument de mauvais type, fonction non appelable), ValueError (valeur illégale : pas nul,
#     taille négative...), IndexError (liste vide pour min_by/max_by sans valeur par défaut).

from core use len, type, is_function, is_callable
from collections use append, keys, contains_key

# --- validation ---------------------------------------------------------------------------------------------

func _need_fn(f, name):
    if not is_callable(f):
        raise("TypeError", name + " : fonction attendue, reçu " + type(f))

# Liste de travail : la liste elle-même (jamais modifiée par ce module), ou copie d'un tuple / d'une str.
func _list(items, name):
    t := type(items)
    if t == "list":
        return items
    if t == "tuple":
        out := []
        for x in items:
            append(out, x)
        return out
    if t == "str":
        out := []
        for c in items:
            append(out, str(c))
        return out
    raise("TypeError", name + " : list, tuple ou str attendu, reçu " + t)

func _need_int(n, name):
    if type(n) != "int":
        raise("TypeError", name + " : entier attendu, reçu " + type(n))

# --- construction -------------------------------------------------------------------------------------------

# Liste des entiers de start (inclus) à stop (exclu), par pas de step (non nul, négatif possible).
func range_list(start, stop, step=1):
    _need_int(start, "range_list")
    _need_int(stop, "range_list")
    _need_int(step, "range_list")
    if step == 0:
        raise("ValueError", "range_list : le pas ne peut pas être nul")
    out := []
    i := start
    if step > 0:
        while i < stop:
            append(out, i)
            i = i + step
    else:
        while i > stop:
            append(out, i)
            i = i + step
    return out

# Liste de n copies de x.
func repeat(x, n):
    _need_int(n, "repeat")
    if n < 0:
        raise("ValueError", "repeat : n doit être >= 0")
    out := []
    i := 0
    while i < n:
        append(out, x)
        i = i + 1
    return out

# [x, f(x), f(f(x)), ...] de n valeurs.
func iterate(f, x, n):
    _need_fn(f, "iterate")
    _need_int(n, "iterate")
    out := []
    cur := x
    i := 0
    while i < n:
        append(out, cur)
        cur = f(cur)
        i = i + 1
    return out

# --- transformation -----------------------------------------------------------------------------------------

func map(items, f):
    _need_fn(f, "map")
    out := []
    for x in _list(items, "map"):
        append(out, f(x))
    return out

func filter(items, pred):
    _need_fn(pred, "filter")
    out := []
    for x in _list(items, "filter"):
        if pred(x):
            append(out, x)
    return out

# Contraire de filter : garde les éléments pour lesquels pred est faux.
func reject(items, pred):
    _need_fn(pred, "reject")
    out := []
    for x in _list(items, "reject"):
        if not pred(x):
            append(out, x)
    return out

# map puis aplatissement d'un niveau : f(x) doit renvoyer une liste ou un tuple.
func flat_map(items, f):
    _need_fn(f, "flat_map")
    out := []
    for x in _list(items, "flat_map"):
        for y in _list(f(x), "flat_map (résultat de f)"):
            append(out, y)
    return out

# Appelle f(x) pour chaque élément (effets de bord) ; renvoie null.
func for_each(items, f):
    _need_fn(f, "for_each")
    for x in _list(items, "for_each"):
        f(x)
    return null

# Repli à gauche : f(f(f(init, x0), x1), x2)...
func reduce(items, f, init):
    _need_fn(f, "reduce")
    acc := init
    for x in _list(items, "reduce"):
        acc = f(acc, x)
    return acc

# Repli à droite : f(x0, f(x1, f(x2, init))).
func fold_right(items, f, init):
    _need_fn(f, "fold_right")
    xs := _list(items, "fold_right")
    acc := init
    i := len(xs) - 1
    while i >= 0:
        acc = f(xs[i], acc)
        i = i - 1
    return acc

# Comme reduce mais garde tous les cumuls (sans init) : scan([1,2,3], +, 0) = [1, 3, 6].
func scan(items, f, init):
    _need_fn(f, "scan")
    out := []
    acc := init
    for x in _list(items, "scan"):
        acc = f(acc, x)
        append(out, acc)
    return out

func sum(items, f=null):
    total := 0
    for x in _list(items, "sum"):
        if f == null:
            total = total + x
        else:
            total = total + f(x)
    return total

func prod(items):
    total := 1
    for x in _list(items, "prod"):
        total = total * x
    return total

func count_if(items, pred):
    _need_fn(pred, "count_if")
    n := 0
    for x in _list(items, "count_if"):
        if pred(x):
            n = n + 1
    return n

# --- paires et indices --------------------------------------------------------------------------------------

# [(a0, b0), (a1, b1), ...] ; s'arrête à la liste la plus courte.
func zip(a, b):
    xs := _list(a, "zip")
    ys := _list(b, "zip")
    n := len(xs)
    if len(ys) < n:
        n = len(ys)
    out := []
    i := 0
    while i < n:
        append(out, (xs[i], ys[i]))
        i = i + 1
    return out

# [f(a0, b0), f(a1, b1), ...]
func zip_with(a, b, f):
    _need_fn(f, "zip_with")
    xs := _list(a, "zip_with")
    ys := _list(b, "zip_with")
    n := len(xs)
    if len(ys) < n:
        n = len(ys)
    out := []
    i := 0
    while i < n:
        append(out, f(xs[i], ys[i]))
        i = i + 1
    return out

# Inverse de zip : [(a, b), ...] -> [[a, ...], [b, ...]].
func unzip(pairs):
    left := []
    right := []
    for p in _list(pairs, "unzip"):
        append(left, p[0])
        append(right, p[1])
    return [left, right]

# [(start, x0), (start + 1, x1), ...]
func enumerate(items, start=0):
    _need_int(start, "enumerate")
    out := []
    i := start
    for x in _list(items, "enumerate"):
        append(out, (i, x))
        i = i + 1
    return out

# [(x0, x1), (x1, x2), ...]
func pairwise(items):
    xs := _list(items, "pairwise")
    out := []
    i := 0
    while i + 1 < len(xs):
        append(out, (xs[i], xs[i + 1]))
        i = i + 1
    return out

# --- découpage ----------------------------------------------------------------------------------------------

# Les n premiers éléments (moins s'il y en a moins).
func take(items, n):
    _need_int(n, "take")
    xs := _list(items, "take")
    out := []
    i := 0
    while i < n and i < len(xs):
        append(out, xs[i])
        i = i + 1
    return out

# Tout sauf les n premiers éléments.
func drop(items, n):
    _need_int(n, "drop")
    xs := _list(items, "drop")
    out := []
    i := 0
    if n > 0:
        i = n
    while i < len(xs):
        append(out, xs[i])
        i = i + 1
    return out

func take_while(items, pred):
    _need_fn(pred, "take_while")
    out := []
    for x in _list(items, "take_while"):
        if not pred(x):
            return out
        append(out, x)
    return out

func drop_while(items, pred):
    _need_fn(pred, "drop_while")
    out := []
    dropping := true
    for x in _list(items, "drop_while"):
        if dropping and pred(x):
            continue
        dropping = false
        append(out, x)
    return out

# [take(items, n), drop(items, n)]
func split_at(items, n):
    return [take(items, n), drop(items, n)]

# Sous-listes consécutives de taille n (la dernière peut être plus courte).
func chunk(items, n):
    _need_int(n, "chunk")
    if n <= 0:
        raise("ValueError", "chunk : n doit être > 0")
    out := []
    cur := []
    for x in _list(items, "chunk"):
        append(cur, x)
        if len(cur) == n:
            append(out, cur)
            cur = []
    if len(cur) > 0:
        append(out, cur)
    return out

# Fenêtres glissantes de taille n : window([1,2,3,4], 2) = [[1,2],[2,3],[3,4]].
func window(items, n):
    _need_int(n, "window")
    if n <= 0:
        raise("ValueError", "window : n doit être > 0")
    xs := _list(items, "window")
    out := []
    i := 0
    while i + n <= len(xs):
        w := []
        j := 0
        while j < n:
            append(w, xs[i + j])
            j = j + 1
        append(out, w)
        i = i + 1
    return out

# --- recherche ----------------------------------------------------------------------------------------------

# Premier élément vérifiant pred, sinon `default`.
func find(items, pred, default=null):
    _need_fn(pred, "find")
    for x in _list(items, "find"):
        if pred(x):
            return x
    return default

# Indice du premier élément vérifiant pred, sinon -1.
func find_index(items, pred):
    _need_fn(pred, "find_index")
    i := 0
    for x in _list(items, "find_index"):
        if pred(x):
            return i
        i = i + 1
    return -1

func any_of(items, pred):
    _need_fn(pred, "any_of")
    for x in _list(items, "any_of"):
        if pred(x):
            return true
    return false

func all_of(items, pred):
    _need_fn(pred, "all_of")
    for x in _list(items, "all_of"):
        if not pred(x):
            return false
    return true

func none_of(items, pred):
    return not any_of(items, pred)

# [éléments vérifiant pred, autres éléments], ordre conservé.
func partition(items, pred):
    _need_fn(pred, "partition")
    yes := []
    no := []
    for x in _list(items, "partition"):
        if pred(x):
            append(yes, x)
        else:
            append(no, x)
    return [yes, no]

# --- groupement ---------------------------------------------------------------------------------------------

# {clé: [éléments]} où clé = key(x). L'ordre relatif des éléments d'un groupe est conservé.
func group_by(items, key):
    _need_fn(key, "group_by")
    groups := {}
    for x in _list(items, "group_by"):
        k := key(x)
        if contains_key(groups, k):
            append(groups[k], x)
        else:
            groups[k] = [x]
    return groups

# {clé: nombre d'éléments}
func count_by(items, key):
    _need_fn(key, "count_by")
    counts := {}
    for x in _list(items, "count_by"):
        k := key(x)
        if contains_key(counts, k):
            counts[k] = counts[k] + 1
        else:
            counts[k] = 1
    return counts

# {valeur: nombre d'occurrences}
func frequencies(items):
    return count_by(items, x => x)

# Sans doublons, premier exemplaire conservé, ordre conservé.
func unique(items):
    return unique_by(items, x => x)

func unique_by(items, key):
    _need_fn(key, "unique_by")
    seen := {}
    out := []
    for x in _list(items, "unique_by"):
        k := key(x)
        if not contains_key(seen, k):
            seen[k] = true
            append(out, x)
    return out

# --- tri ----------------------------------------------------------------------------------------------------

# Tri fusion des indices `idx` selon les clés ks (stable, O(n log n)).
func _msort(idx, ks, reverse):
    n := len(idx)
    if n < 2:
        return idx
    mid := n // 2
    left := []
    right := []
    i := 0
    while i < n:
        if i < mid:
            append(left, idx[i])
        else:
            append(right, idx[i])
        i = i + 1
    left = _msort(left, ks, reverse)
    right = _msort(right, ks, reverse)
    out := []
    a := 0
    b := 0
    while a < len(left) and b < len(right):
        take_right := false
        if reverse:
            take_right = ks[left[a]] < ks[right[b]]
        else:
            take_right = ks[right[b]] < ks[left[a]]
        if take_right:
            append(out, right[b])
            b = b + 1
        else:
            append(out, left[a])
            a = a + 1
    while a < len(left):
        append(out, left[a])
        a = a + 1
    while b < len(right):
        append(out, right[b])
        b = b + 1
    return out

# Nouvelle liste triée, STABLE. key(x) donne la clé de comparaison (par défaut x lui-même) ; reverse=true : décroissant.
func sort_by(items, key=null, reverse=false):
    xs := _list(items, "sort_by")
    ks := []
    idx := []
    i := 0
    for x in xs:
        if key == null:
            append(ks, x)
        else:
            append(ks, key(x))
        append(idx, i)
        i = i + 1
    out := []
    for j in _msort(idx, ks, reverse):
        append(out, xs[j])
    return out

# Tri naturel croissant (alias de sort_by(items)).
func sorted(items):
    return sort_by(items)

# Plus petit élément selon key (le premier en cas d'égalité). Liste vide : `default` s'il est fourni, sinon IndexError.
func min_by(items, key=null, default=null):
    return _extreme(items, key, default, false, "min_by")

func max_by(items, key=null, default=null):
    return _extreme(items, key, default, true, "max_by")

func _extreme(items, key, default, want_max, name):
    xs := _list(items, name)
    if len(xs) == 0:
        if default != null:
            return default
        raise("IndexError", name + " : liste vide")
    best := xs[0]
    best_key := xs[0]
    if key != null:
        best_key = key(xs[0])
    i := 1
    while i < len(xs):
        k := xs[i]
        if key != null:
            k = key(xs[i])
        better := false
        if want_max:
            better = best_key < k
        else:
            better = k < best_key
        if better:
            best = xs[i]
            best_key = k
        i = i + 1
    return best

# --- listes -------------------------------------------------------------------------------------------------

func reverse(items):
    xs := _list(items, "reverse")
    out := []
    i := len(xs) - 1
    while i >= 0:
        append(out, xs[i])
        i = i - 1
    return out

func concat(a, b):
    out := []
    for x in _list(a, "concat"):
        append(out, x)
    for y in _list(b, "concat"):
        append(out, y)
    return out

# Aplatit `depth` niveaux (1 par défaut ; depth < 0 : tous). Seules les list et tuples sont aplaties, pas les str.
func flatten(items, depth=1):
    out := []
    for x in _list(items, "flatten"):
        t := type(x)
        if (t == "list" or t == "tuple") and depth != 0:
            for y in flatten(x, depth - 1):
                append(out, y)
        else:
            append(out, x)
    return out

# a0, b0, a1, b1, ... (le surplus de la liste la plus longue est ajouté à la fin).
func interleave(a, b):
    xs := _list(a, "interleave")
    ys := _list(b, "interleave")
    out := []
    i := 0
    while i < len(xs) or i < len(ys):
        if i < len(xs):
            append(out, xs[i])
        if i < len(ys):
            append(out, ys[i])
        i = i + 1
    return out

# Insère sep entre les éléments.
func intersperse(items, sep):
    out := []
    first := true
    for x in _list(items, "intersperse"):
        if not first:
            append(out, sep)
        append(out, x)
        first = false
    return out

# --- combinatoire -------------------------------------------------------------------------------------------

# Produit cartésien : [(a, b) pour a dans xs, b dans ys].
func cross(a, b):
    ys := _list(b, "cross")
    out := []
    for x in _list(a, "cross"):
        for y in ys:
            append(out, (x, y))
    return out

# Toutes les sélections de k éléments, ordre des positions conservé (pas de répétition).
func combinations(items, k):
    _need_int(k, "combinations")
    if k < 0:
        raise("ValueError", "combinations : k doit être >= 0")
    xs := _list(items, "combinations")
    out := []
    _combine(xs, k, 0, [], out)
    return out

func _combine(xs, k, start, cur, out):
    if len(cur) == k:
        append(out, copy_of(cur))
        return null
    i := start
    while i < len(xs):
        append(cur, xs[i])
        _combine(xs, k, i + 1, cur, out)
        __list_remove_at(cur, len(cur) - 1)
        i = i + 1
    return null

# Toutes les permutations (n! listes) dans l'ordre lexicographique des positions.
func permutations(items):
    xs := _list(items, "permutations")
    out := []
    _permute(xs, [], repeat(false, len(xs)), out)
    return out

func _permute(xs, cur, used, out):
    if len(cur) == len(xs):
        append(out, copy_of(cur))
        return null
    i := 0
    while i < len(xs):
        if not used[i]:
            used[i] = true
            append(cur, xs[i])
            _permute(xs, cur, used, out)
            __list_remove_at(cur, len(cur) - 1)
            used[i] = false
        i = i + 1
    return null

func copy_of(items):
    out := []
    for x in items:
        append(out, x)
    return out

# --- dictionnaires ------------------------------------------------------------------------------------------

# Même clés, valeurs f(v).
func map_values(d, f):
    _need_fn(f, "map_values")
    out := {}
    for k in keys(d):
        out[k] = f(d[k])
    return out

# Garde les entrées pour lesquelles pred(clé, valeur) est vrai.
func filter_dict(d, pred):
    _need_fn(pred, "filter_dict")
    out := {}
    for k in keys(d):
        if pred(k, d[k]):
            out[k] = d[k]
    return out

# [(clé, valeur), ...] -> dict (la dernière occurrence d'une clé gagne).
func from_pairs(pairs):
    out := {}
    for p in _list(pairs, "from_pairs"):
        out[p[0]] = p[1]
    return out

# --- combinateurs de fonctions ------------------------------------------------------------------------------

# compose(f, g)(x) = f(g(x))
func compose(f, g):
    _need_fn(f, "compose")
    _need_fn(g, "compose")
    return x => f(g(x))

# compose_all([f, g, h])(x) = f(g(h(x))) ; liste vide : identité.
func compose_all(fns):
    fs := copy_of(_list(fns, "compose_all"))
    for f in fs:
        _need_fn(f, "compose_all")
    func run(x):
        acc := x
        i := len(fs) - 1
        while i >= 0:
            acc = fs[i](acc)
            i = i - 1
        return acc
    return run

# Applique les fonctions de gauche à droite : pipe(3, [f, g]) = g(f(3)).
func pipe(value, fns):
    acc := value
    for f in _list(fns, "pipe"):
        _need_fn(f, "pipe")
        acc = f(acc)
    return acc

# pipeline([f, g]) renvoie la fonction x => g(f(x)).
func pipeline(fns):
    fs := copy_of(_list(fns, "pipeline"))
    for f in fs:
        _need_fn(f, "pipeline")
    return x => pipe(x, fs)

# partial(f, a)(x) = f(a, x)
func partial(f, a):
    _need_fn(f, "partial")
    return x => f(a, x)

# partial2(f, a, b)(x) = f(a, b, x)
func partial2(f, a, b):
    _need_fn(f, "partial2")
    return x => f(a, b, x)

# partial_right(f, b)(x) = f(x, b)
func partial_right(f, b):
    _need_fn(f, "partial_right")
    return x => f(x, b)

# flip(f)(a, b) = f(b, a)
func flip(f):
    _need_fn(f, "flip")
    return (a, b) => f(b, a)

# curry2(f)(a)(b) = f(a, b)
func curry2(f):
    _need_fn(f, "curry2")
    return a => (b => f(a, b))

# curry3(f)(a)(b)(c) = f(a, b, c)
func curry3(f):
    _need_fn(f, "curry3")
    return a => (b => (c => f(a, b, c)))

# Fonction qui renvoie toujours x.
func constant(x):
    return _ => x

# Prédicat contraire : negate(p)(x) = not p(x)
func negate(pred):
    _need_fn(pred, "negate")
    return x => not pred(x)

# Appelle f(x) pour ses effets, puis renvoie x (utile dans pipe pour déboguer).
func tap(f):
    _need_fn(f, "tap")
    func run(x):
        f(x)
        return x
    return run

# Fonction à un argument qui n'appelle f qu'à la première fois ; les appels suivants renvoient le même résultat.
func once(f):
    _need_fn(f, "once")
    state := [false, null]
    func run(x):
        if not state[0]:
            state[1] = f(x)
            state[0] = true
        return state[1]
    return run

# Mémoïse une fonction à UN argument (l'argument sert de clé de dict : nombre, str, bool, tuple...).
func memoize(f):
    _need_fn(f, "memoize")
    cache := {}
    func run(x):
        if contains_key(cache, x):
            return cache[x]
        v := f(x)
        cache[x] = v
        return v
    return run

# Comme memoize, pour une fonction à DEUX arguments.
func memoize2(f):
    _need_fn(f, "memoize2")
    cache := {}
    func run(a, b):
        k := (a, b)
        if contains_key(cache, k):
            return cache[k]
        v := f(a, b)
        cache[k] = v
        return v
    return run

# --- chaînage fluide ----------------------------------------------------------------------------------------

# Enveloppe une liste pour chaîner : seq([3, 1, 2]).sort_by().map(x => x * 2).to_list()
# Chaque méthode renvoie un NOUVEAU Seq ; les méthodes terminales (to_list, reduce, sum, first...) renvoient une valeur.
class Seq:
    func init(items):
        self.items = copy_of(_list(items, "seq"))

    func map(f):
        return Seq(map(self.items, f))

    func filter(pred):
        return Seq(filter(self.items, pred))

    func reject(pred):
        return Seq(reject(self.items, pred))

    func flat_map(f):
        return Seq(flat_map(self.items, f))

    func take(n):
        return Seq(take(self.items, n))

    func drop(n):
        return Seq(drop(self.items, n))

    func take_while(pred):
        return Seq(take_while(self.items, pred))

    func drop_while(pred):
        return Seq(drop_while(self.items, pred))

    func enumerate(start=0):
        return Seq(enumerate(self.items, start))

    func zip(other):
        return Seq(zip(self.items, other))

    func chunk(n):
        return Seq(chunk(self.items, n))

    func window(n):
        return Seq(window(self.items, n))

    func flatten(depth=1):
        return Seq(flatten(self.items, depth))

    func unique():
        return Seq(unique(self.items))

    func sort_by(key=null, reverse=false):
        return Seq(sort_by(self.items, key, reverse))

    func reverse():
        return Seq(reverse(self.items))

    func concat(other):
        return Seq(concat(self.items, other))

    func scan(f, init):
        return Seq(scan(self.items, f, init))

    func tap(f):
        for_each(self.items, f)
        return self

    # --- terminales ---
    func to_list():
        return copy_of(self.items)

    func count():
        return len(self.items)

    func reduce(f, init):
        return reduce(self.items, f, init)

    func sum(f=null):
        return sum(self.items, f)

    func find(pred, default=null):
        return find(self.items, pred, default)

    func any_of(pred):
        return any_of(self.items, pred)

    func all_of(pred):
        return all_of(self.items, pred)

    func group_by(key):
        return group_by(self.items, key)

    func min_by(key=null, default=null):
        return min_by(self.items, key, default)

    func max_by(key=null, default=null):
        return max_by(self.items, key, default)

    func first(default=null):
        if len(self.items) == 0:
            return default
        return self.items[0]

    func last(default=null):
        if len(self.items) == 0:
            return default
        return self.items[len(self.items) - 1]

func seq(items):
    return Seq(items)
