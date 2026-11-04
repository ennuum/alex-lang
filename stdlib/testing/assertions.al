# ALEX STANDARD LIBRARY — testing.assertions
#
# Assertions riches : chaque échec lève AssertionError avec un message qui MONTRE la différence (premier
# élément différent d'une liste, clés manquantes d'un dict, position du premier caractère différent d'un texte).
#
#   use testing.assertions as a
#   a.equal(calcul(), [1, 2, 3])               # « listes différentes à l'indice 2 : 4 != 3 »
#   a.almost_equal(0.1 + 0.2, 0.3)             # tolérance 1e-9 (rel_tol / abs_tol)
#   e := a.raises(() => diviser(1, 0), "ZeroDivisionError", "zéro")   # rend l'exception
#   a.contains(texte, "bonjour")
#   a.dict_contains(reponse, {"ok": true})     # sous-ensemble
#   a.instance_of(objet, "Collection")         # par nom de type (réflexion)
#   a.matches(ligne, "^\\d{4}-\\d{2}")         # expression régulière
#   a.length(xs, 3)
#   a.between(v, 0, 10)
#
# Chaque assertion accepte un dernier argument msg (texte ajouté au message d'échec).
# Erreurs : AssertionError.

from core use len, type
from collections use append
use string as _s
use regex as _re
use _native_reflect as _r
use reflection.type_traits as _tt
use testing.testing_errors as _e

func _show(v):
    if type(v) == "str":
        return "\"" + v + "\""
    return str(v)

func _fail(text, msg):
    if msg != null:
        text = text + " — " + str(msg)
    _e.fail(text)

# Explication de la différence entre a et b (null s'ils sont égaux).
func explain_difference(actual, expected):
    if actual == expected:
        return null
    ta := type(actual)
    tb := type(expected)
    if ta != tb and not ((ta == "int" or ta == "float") and (tb == "int" or tb == "float")):
        return "types différents : " + ta + " " + _show(actual) + " != " + tb + " " + _show(expected)
    if ta == "list":
        i := 0
        while i < len(actual) and i < len(expected):
            if not (actual[i] == expected[i]):
                sub := explain_difference(actual[i], expected[i])
                return "listes différentes à l'indice " + str(i) + " : " + sub
            i += 1
        if len(actual) != len(expected):
            return "longueurs différentes : " + str(len(actual)) + " != " + str(len(expected)) + " (" + _show(actual) + " != " + _show(expected) + ")"
    if ta == "dict":
        missing := [k for k in expected if not (k in actual)]
        extra := [k for k in actual if not (k in expected)]
        if len(missing) > 0:
            return "clés absentes : " + str(missing)
        if len(extra) > 0:
            return "clés en trop : " + str(extra)
        for k in expected:
            if not (actual[k] == expected[k]):
                return "valeurs différentes pour la clé " + _show(k) + " : " + explain_difference(actual[k], expected[k])
    if ta == "str":
        i := 0
        while i < len(actual) and i < len(expected) and actual[i] == expected[i]:
            i += 1
        return "textes différents à la position " + str(i) + " : " + _show(actual) + " != " + _show(expected)
    return _show(actual) + " != " + _show(expected)

func equal(actual, expected, msg=null):
    if not (actual == expected):
        _fail(explain_difference(actual, expected), msg)

func not_equal(a, b, msg=null):
    if a == b:
        _fail(_show(a) + " == " + _show(b) + " (différence attendue)", msg)

func is_true(cond, msg=null):
    if not cond:
        _fail("condition fausse", msg)

func is_false(cond, msg=null):
    if cond:
        _fail("condition vraie (fausse attendue)", msg)

func is_null(v, msg=null):
    if type(v) != "null":
        _fail(_show(v) + " n'est pas null", msg)

func not_null(v, msg=null):
    if type(v) == "null":
        _fail("valeur null", msg)

func _abs(x):
    if x < 0:
        return -x
    return x

func almost_equal(a, b, rel_tol=0.000000001, abs_tol=0.0, msg=null):
    d := _abs(a - b)
    m := _abs(a)
    if _abs(b) > m:
        m = _abs(b)
    if d > rel_tol * m and d > abs_tol:
        _fail(_show(a) + " ≉ " + _show(b) + " (écart " + str(d) + ")", msg)

# Listes de nombres proches élément par élément.
func all_close(xs, ys, tol=0.000001, msg=null):
    length(ys, len(xs), msg)
    i := 0
    while i < len(xs):
        if _abs(xs[i] - ys[i]) > tol:
            _fail("indice " + str(i) + " : " + str(xs[i]) + " ≉ " + str(ys[i]), msg)
        i += 1

# fn() doit lever ; kind (type) et fragment (texte contenu dans le message) facultatifs. Rend l'exception.
func raises(fn, kind=null, fragment=null, msg=null):
    try:
        fn()
    catch e:
        if kind != null and e.type != kind:
            _fail(kind + " attendue, " + e.type + " levée (" + e.message + ")", msg)
        if fragment != null and not _s.contains(e.message, fragment):
            _fail("message « " + e.message + " » sans « " + fragment + " »", msg)
        return e
    k := "une erreur"
    if kind != null:
        k = kind
    _fail(k + " attendue, aucune levée", msg)

func no_raise(fn, msg=null):
    try:
        return fn()
    catch e:
        _fail("aucune erreur attendue, " + e.type + " levée : " + e.message, msg)

func contains(container, item, msg=null):
    if type(container) == "str":
        if not _s.contains(container, str(item)):
            _fail(_show(container) + " ne contient pas " + _show(item), msg)
        return
    if not (item in container):
        _fail(_show(container) + " ne contient pas " + _show(item), msg)

func not_contains(container, item, msg=null):
    ok := false
    if type(container) == "str":
        ok = not _s.contains(container, str(item))
    else:
        ok = not (item in container)
    if not ok:
        _fail(_show(container) + " contient " + _show(item), msg)

# expected est un sous-ensemble de actual (mêmes valeurs pour ses clés).
func dict_contains(actual, expected, msg=null):
    for k in expected:
        if not (k in actual):
            _fail("clé " + _show(k) + " absente", msg)
        if not (actual[k] == expected[k]):
            _fail("clé " + _show(k) + " : " + _show(actual[k]) + " != " + _show(expected[k]), msg)

# Mêmes éléments, ordre indifférent (multiensembles).
func same_items(a, b, msg=null):
    rest := b[:]
    for x in a:
        found := -1
        i := 0
        while i < len(rest):
            if rest[i] == x:
                found = i
                break
            i += 1
        if found < 0:
            _fail(_show(x) + " en trop (ou en double) dans " + _show(a), msg)
        rest = rest[:found] + rest[found + 1:]
    if len(rest) > 0:
        _fail("éléments manquants : " + _show(rest), msg)

func length(container, n, msg=null):
    if len(container) != n:
        _fail("longueur " + str(len(container)) + " != " + str(n), msg)

func is_empty(container, msg=null):
    length(container, 0, msg)

func greater(a, b, msg=null):
    if not (a > b):
        _fail(_show(a) + " n'est pas > " + _show(b), msg)

func greater_equal(a, b, msg=null):
    if not (a >= b):
        _fail(_show(a) + " n'est pas >= " + _show(b), msg)

func less(a, b, msg=null):
    if not (a < b):
        _fail(_show(a) + " n'est pas < " + _show(b), msg)

func less_equal(a, b, msg=null):
    if not (a <= b):
        _fail(_show(a) + " n'est pas <= " + _show(b), msg)

func between(v, lo, hi, msg=null):
    if v < lo or v > hi:
        _fail(_show(v) + " hors de [" + _show(lo) + ", " + _show(hi) + "]", msg)

func type_is(v, type_name, msg=null):
    if type(v) != type_name:
        _fail("type " + type(v) + " != " + type_name, msg)

# Instance du type (ou de l'interface) nommé(e).
func instance_of(v, type_name, msg=null):
    if not _tt.implements(v, type_name):
        got := type(v)
        if _r.is_instance(v):
            got = _r.display_name(_r.type_name(v))
        _fail(got + " n'est pas un " + type_name, msg)

func matches(text, pattern, msg=null):
    if not _re.test(pattern, text):
        _fail(_show(text) + " ne correspond pas à /" + pattern + "/", msg)

func starts_with(text, prefix, msg=null):
    if not _s.starts_with(text, prefix):
        _fail(_show(text) + " ne commence pas par " + _show(prefix), msg)

func ends_with(text, suffix, msg=null):
    if not _s.ends_with(text, suffix):
        _fail(_show(text) + " ne finit pas par " + _show(suffix), msg)

func all_true(items, pred, msg=null):
    i := 0
    for x in items:
        if not pred(x):
            _fail("élément " + str(i) + " (" + _show(x) + ") refusé par le prédicat", msg)
        i += 1

func fail(msg="échec explicite"):
    _e.fail(msg)
