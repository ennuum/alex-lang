# =============================================================================
# ALEX - exceptions : catch typés et multiples, finally (normal / exception /
# return / break / continue / imbriqués), relance raise(e) conservant l'objet
# et sa trace de pile, membre e.trace. Voir docs/RUNTIME.md §7.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_exceptions.al
# =============================================================================
from collections use append
use core
use string

failures := []
func check(cond, label):
    if cond:
        print("ok   " + label)
    else:
        print("ÉCHEC " + label)
        append(failures, label)

# 1. catch typés multiples
func classify(k):
    try:
        if k == 0:
            x := [1][5]
        elif k == 1:
            d := {"a": 1}
            y := d["z"]
        elif k == 2:
            raise("MonErreur", "perso")
        else:
            z := 1 // 0
        return "rien"
    catch IndexError as e:
        return "index"
    catch KeyError, MonErreur as e:
        return "clé-ou-perso:" + e.type
    catch e:
        return "autre:" + e.type

check(classify(0) == "index", "catch IndexError")
check(classify(1) == "clé-ou-perso:KeyError", "catch A, B (KeyError)")
check(classify(2) == "clé-ou-perso:MonErreur", "catch A, B (MonErreur)")
check(classify(3) == "autre:ZeroDivisionError", "catch générique")

# 2. clause non correspondante -> propagation, même objet
func inner():
    try:
        x := 1 // 0
    catch (IndexError):
        print("ne doit pas arriver")

r := ""
try:
    inner()
catch ZeroDivisionError as e:
    r = e.type
check(r == "ZeroDivisionError", "propagation si aucune clause")

# 3. catch (A, B) sans liaison et Exception attrape-tout
r = ""
try:
    raise("X", "y")
catch (Exception):
    r = "tout"
check(r == "tout", "Exception attrape tout")

# 4. finally : chemin normal, exception, return, break, continue
log := []
func f_normal():
    try:
        append(log, "t")
    finally:
        append(log, "f")
f_normal()
check(log == ["t", "f"], "finally chemin normal")

log = []
func f_exc():
    try:
        x := 1 // 0
    finally:
        append(log, "f")
try:
    f_exc()
catch e:
    append(log, e.type)
check(log == ["f", "ZeroDivisionError"], "finally puis relance")

log = []
func f_ret():
    try:
        return "v"
    finally:
        append(log, "f")
v := f_ret()
check(v == "v" and log == ["f"], "finally sur return")

func f_ret_value():
    n := 1
    try:
        return n
    finally:
        n = 99
check(f_ret_value() == 1, "valeur du return calculée avant finally")

log = []
for i in 0..5:
    try:
        if i == 1:
            continue
        if i == 3:
            break
        append(log, i)
    finally:
        append(log, "f" + str(i))
check(log == [0, "f0", "f1", 2, "f2", "f3"], "finally sur break/continue")

log = []
func f_catch_finally():
    try:
        raise("A", "a")
    catch A as e:
        append(log, "c")
        return "r"
    finally:
        append(log, "f")
check(f_catch_finally() == "r" and log == ["c", "f"], "catch + finally + return")

log = []
func f_unmatched():
    try:
        raise("B", "b")
    catch A as e:
        append(log, "mauvais")
    finally:
        append(log, "f")
try:
    f_unmatched()
catch B as e:
    append(log, "B")
check(log == ["f", "B"], "clause non correspondante + finally")

# finally imbriqués
log = []
func nested():
    try:
        try:
            return 1
        finally:
            append(log, "in")
    finally:
        append(log, "out")
check(nested() == 1 and log == ["in", "out"], "finally imbriqués sur return")

# 5. raise(e) relance le même objet avec sa trace d'origine
func deep():
    x := [][0]
first := null
again := null
try:
    try:
        deep()
    catch e:
        first = e
        raise(e)
catch e2:
    again = e2
check(again.type == "IndexError", "raise(e) conserve le type")
check(core.len(again.trace) == core.len(first.trace) and core.len(again.trace) >= 2, "raise(e) conserve la trace")
last := again.trace[core.len(again.trace) - 1]
check(string.ends_with(last, ", dans deep"), "e.trace se termine sur la fonction fautive")
check(string.ends_with(again.trace[0], ", dans <module>"), "e.trace commence au module (frames du chargeur masqués)")

if core.len(failures) > 0:
    raise("TestFailure", str(core.len(failures)) + " vérification(s) en échec")
print("test_exceptions : toutes les vérifications passent")
