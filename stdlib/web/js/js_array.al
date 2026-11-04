# ALEX STANDARD LIBRARY — web.js.js_array
#
# Tableaux JavaScript : expressions (littéraux, Array.from, tableaux typés, enchaînements map / filter /
# reduce) et sémantique des méthodes Array de JavaScript appliquée aux listes ALEX (indices négatifs de slice
# et at, splice, flat, includes avec NaN, join avec null, tri par défaut LEXICOGRAPHIQUE comme en JS…).
#
#   use web.js.js_array as ja
#   ja.literal([1, "a", null]).to_js()                       # [1, "a", null]
#   ja.from_length(3, "(_, i) => i * 2").to_js()             # Array.from({length: 3}, (_, i) => i * 2)
#   ja.typed("Uint8Array", [1, 2, 255]).to_js()              # new Uint8Array([1, 2, 255])
#   ja.chain("items", [("filter", "(x) => x.actif"), ("map", "(x) => x.nom")]).to_js()   # items.filter(…).map(…)
#   ja.slice([1, 2, 3, 4], -2)                               # [3, 4]
#   ja.splice(l, 1, 2, ["x"])                                # retire 2 éléments à l'indice 1, insère "x"
#   ja.flat([1, [2, [3, [4]]]], 2)                           # [1, 2, 3, [4]]
#   ja.sort_default([10, 9, 1])                              # [1, 10, 9]   (comparaison de textes, comme JS)
#   ja.join([1, null, "b"], "-")                             # 1--b
#
# Erreurs : JsValueError (longueur invalide, type de tableau typé inconnu).

from core use len, type, to_int
from collections use append, pop
use string as _s
use web.js.js_errors as _err
use web.js.js_types as _t
use web.js.js_expression as _e

const TYPED := ["Int8Array", "Uint8Array", "Uint8ClampedArray", "Int16Array", "Uint16Array", "Int32Array", "Uint32Array", "Float32Array", "Float64Array", "BigInt64Array", "BigUint64Array"]

func literal(items=null):
    return _e.array(items)

func _fn(f):
    if type(f) == "str":
        return _e.RawExpr(f, _e.P_ASSIGN)
    return _e.expr(f)

# Array.from({length: n}, fn).
func from_length(n, fn=null):
    args := [_e.object({"length": n})]
    if fn != null:
        append(args, _fn(fn))
    return _e.Call(_e.path("Array.from"), args)

func from_iterable(source, fn=null):
    args := [_e.path(source) if type(source) == "str" else _e.expr(source)]
    if fn != null:
        append(args, _fn(fn))
    return _e.Call(_e.path("Array.from"), args)

func typed(kind, values):
    if not (kind in TYPED):
        _err.value_error("js_array.typed", "tableau typé inconnu « " + str(kind) + " »")
    return _e.New(_e.ident(kind), [_e.expr(values)])

# Enchaînement de méthodes : steps : liste de (méthode, argument texte / Expr / liste d'arguments).
func chain(source, steps):
    e := _e.path(source) if type(source) == "str" else _e.expr(source)
    for st in steps:
        args := []
        if len(st) > 1:
            a := st[1]
            if type(a) == "list":
                for x in a:
                    append(args, _fn(x))
            elif a != null:
                append(args, _fn(a))
        if len(st) > 2:
            append(args, _e.expr(st[2]))
        e = _e.Call(_e.Member(e, st[0]), args)
    return e

# ---------------------------------------------------------------- sémantique JS sur les listes

func _norm(i, n):
    k := to_int(i)
    if k < 0:
        k = n + k
        if k < 0:
            k = 0
    if k > n:
        k = n
    return k

func slice(lst, start=0, end=null):
    n := len(lst)
    a := _norm(start, n)
    b := n if end == null else _norm(end, n)
    out := []
    i := a
    while i < b:
        append(out, lst[i])
        i += 1
    return out

func at(lst, i):
    n := len(lst)
    k := to_int(i)
    if k < 0:
        k = n + k
    if k < 0 or k >= n:
        return _t.UNDEFINED
    return lst[k]

# Modifie lst comme Array.prototype.splice et renvoie les éléments retirés.
func splice(lst, start, delete_count=null, items=null):
    n := len(lst)
    a := _norm(start, n)
    dc := n - a if delete_count == null else to_int(delete_count)
    if dc < 0:
        dc = 0
    if a + dc > n:
        dc = n - a
    removed := []
    i := 0
    while i < dc:
        append(removed, lst[a + i])
        i += 1
    rest := []
    i = a + dc
    while i < n:
        append(rest, lst[i])
        i += 1
    while len(lst) > a:
        pop(lst)
    for x in (items if items != null else []):
        append(lst, x)
    for x in rest:
        append(lst, x)
    return removed

func flat(lst, depth=1):
    out := []
    for x in lst:
        if (type(x) == "list" or type(x) == "tuple") and depth > 0:
            for y in flat(x, depth - 1):
                append(out, y)
        else:
            append(out, x)
    return out

func flat_map(lst, fn):
    out := []
    i := 0
    for x in lst:
        r := fn(x, i)
        if type(r) == "list" or type(r) == "tuple":
            for y in r:
                append(out, y)
        else:
            append(out, r)
        i += 1
    return out

# SameValueZero : NaN est trouvé (contrairement à indexOf).
func includes(lst, value):
    for x in lst:
        if x == value:
            return true
        if type(x) == "float" and type(value) == "float" and x != x and value != value:
            return true
    return false

func index_of(lst, value, from_index=0):
    i := _norm(from_index, len(lst))
    while i < len(lst):
        if lst[i] == value and type(lst[i]) == type(value):
            return i
        if (type(lst[i]) == "int" or type(lst[i]) == "float") and (type(value) == "int" or type(value) == "float") and lst[i] == value:
            return i
        i += 1
    return -1

func last_index_of(lst, value):
    i := len(lst) - 1
    while i >= 0:
        if lst[i] == value:
            return i
        i -= 1
    return -1

# Texte d'un élément pour join / toString (null et undefined -> "", tableaux imbriqués joints par « , »).
func to_string_js(v):
    if v == null or _t.is_undefined(v):
        return ""
    t := type(v)
    if t == "bool":
        return "true" if v else "false"
    if t == "int" or t == "float":
        return _t.number(v)
    if t == "list" or t == "tuple":
        return join(v, ",")
    if t == "dict":
        return "[object Object]"
    return str(v)

func join(lst, separator=","):
    parts := []
    for x in lst:
        append(parts, to_string_js(x))
    return _s.join(separator, parts)

func fill(lst, value, start=0, end=null):
    n := len(lst)
    a := _norm(start, n)
    b := n if end == null else _norm(end, n)
    i := a
    while i < b:
        lst[i] = value
        i += 1
    return lst

# Tri par défaut de JavaScript : undefined à la fin, autres éléments comparés comme TEXTES (tri stable).
func sort_default(lst):
    defined := []
    undef := []
    for x in lst:
        if _t.is_undefined(x):
            append(undef, x)
        else:
            append(defined, x)
    keys_ := []
    for x in defined:
        append(keys_, to_string_js(x))
    idx := []
    i := 0
    while i < len(defined):
        append(idx, i)
        i += 1
    i = 1
    while i < len(idx):
        cur := idx[i]
        j := i - 1
        while j >= 0 and keys_[idx[j]] > keys_[cur]:
            idx[j + 1] = idx[j]
            j -= 1
        idx[j + 1] = cur
        i += 1
    out := []
    for k in idx:
        append(out, defined[k])
    return out + undef

# Tri numérique (équivalent de sort((a, b) => a - b)).
func sort_numeric(lst):
    out := []
    for x in lst:
        append(out, x)
    i := 1
    while i < len(out):
        cur := out[i]
        j := i - 1
        while j >= 0 and out[j] > cur:
            out[j + 1] = out[j]
            j -= 1
        out[j + 1] = cur
        i += 1
    return out

func find_last(lst, pred):
    i := len(lst) - 1
    while i >= 0:
        if pred(lst[i]):
            return lst[i]
        i -= 1
    return _t.UNDEFINED

func chunk(lst, size):
    if size <= 0:
        _err.value_error("js_array.chunk", "taille de bloc invalide")
    out := []
    i := 0
    while i < len(lst):
        append(out, slice(lst, i, i + size))
        i += size
    return out

# Liste [start, end[ par pas (comme Array.from({length}, (_, i) => start + i * step)).
func range_list(start, end=null, step=1):
    a := 0 if end == null else start
    b := start if end == null else end
    if step == 0:
        _err.value_error("js_array.range_list", "pas nul")
    out := []
    v := a
    while (step > 0 and v < b) or (step < 0 and v > b):
        append(out, v)
        v += step
    return out
