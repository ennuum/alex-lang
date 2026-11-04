# Ramasse-miettes câblé à la VM (docs/RUNTIME.md §4) : mémoire bornée, données vivantes préservées.
#
# Lancer depuis la racine :  ./alex run tests/lang/test_gc.al
# Variante de validation (révèle toute racine oubliée) :
#   ALEX_GC_STRESS=3 ALEX_GC_POISON=1 ./alex run tests/lang/test_gc.al
use gc
use asyncio
from core use len
from collections use append, clear, keys

stats := [0, 0]
notes := []
registry := {}

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

func check(cond, label):
    check_eq(cond, true, label)

async func run(name, fn):
    clear(notes)
    before := stats[1]
    await fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [OK]     {name}")

func live():
    return gc.stats()["live"]

# --- 1. la mémoire est bornée ---------------------------------------------------------------------

func churn(n):
    i := 0
    while i < n:
        t := [i, i + 1, [i]]
        d := {"k": t}
        i = i + 1
    return i

async func t_bounded():
    gc.collect()
    base := live()
    before := gc.stats()
    churn(60000)
    after := gc.stats()
    check(after["collections"] > before["collections"], "des collectes ont lieu automatiquement")
    check(after["freed"] - before["freed"] > 100000, "des centaines de milliers d'objets libérés")
    check(after["peak"] < base + 20000, "le pic reste borné (pas 240000 objets)")
    gc.collect()
    check(live() < base + 200, "après collecte, retour proche de la base")

# --- 2. les cycles inaccessibles sont libérés ---------------------------------------------------------

func make_cycles(n):
    i := 0
    while i < n:
        a := []
        b := [a]
        append(a, b)
        d := {"self": null}
        d["self"] = d
        i = i + 1

async func t_cycles():
    gc.collect()
    base := live()
    make_cycles(5000)
    gc.collect()
    check(live() < base + 100, "5000 cycles abandonnés sont libérés")

# --- 3. les données vivantes survivent à des collectes répétées ---------------------------------------

class Box:
    func init(v):
        self.v = v
        self.items = [v, str(v)]

func make_counter():
    n := 0
    func inc():
        n = n + 1
        return n
    return inc

async func t_survival():
    keep := []
    i := 0
    while i < 300:
        append(keep, {"i": i, "t": (i, str(i)), "b": Box(i), "l": [i, [i * 2]]})
        i = i + 1
    c := make_counter()
    c()
    c()
    churn(20000)
    gc.collect()
    gc.collect()
    ok := true
    j := 0
    while j < 300:
        e := keep[j]
        if e["i"] != j or e["t"] != (j, str(j)) or e["b"].v != j or e["b"].items != [j, str(j)] or e["l"] != [j, [j * 2]]:
            ok = false
        j = j + 1
    check(ok, "300 structures imbriquées intactes")
    check_eq(c(), 3, "l'état d'une fermeture survit (cellule capturée)")
    cyc := []
    append(cyc, cyc)
    churn(5000)
    gc.collect()
    check_eq(str(cyc), "[[...]]", "un cycle atteignable survit")

async func t_exceptions():
    caught := null
    try:
        raise("MonType", "message long " + str(12345))
    catch e:
        caught = e
    churn(20000)
    gc.collect()
    check_eq(caught.type, "MonType", "l'exception capturée survit")
    check_eq(caught.message, "message long 12345", "son message aussi")
    r := catcher()
    check_eq(r, "ZeroDivisionError", "exception levée sous pression GC")

func zero():
    return 0

func catcher():
    i := 0
    while i < 3000:
        try:
            x := [i, i]
            y := 1 // zero()
        catch e:
            if i == 2999:
                return e.type
        i = i + 1
    return "rien"

# --- 4. tâches suspendues, minuteurs, promesses ----------------------------------------------------------

async func worker(n, delay):
    data := [n, [n * 2], {"k": n}]
    await asyncio.sleep(delay)
    churn(2000)
    return data[0] + data[1][0] + data[2]["k"]

async func t_tasks():
    ts := []
    i := 0
    while i < 20:
        append(ts, worker(i, 0.001 * (i % 5)))
        i = i + 1
    churn(10000)
    gc.collect()
    total := 0
    for t in ts:
        total = total + await t
    check_eq(total, 760, "somme des résultats de 20 tâches (4 × 190)")

async func t_promise():
    p := asyncio.future()
    async func waiter():
        v := await p
        return [v, "reçu"]
    w := waiter()
    await asyncio.sleep(0.001)
    churn(10000)
    gc.collect()
    asyncio.resolve(p, "valeur")
    r := await w
    check_eq(r, ["valeur", "reçu"], "une tâche suspendue sur une promesse survit")

# --- 5. état global des modules ----------------------------------------------------------------------------

async func t_globals():
    registry["a"] = [1, 2, 3]
    churn(30000)
    gc.collect()
    check_eq(registry["a"], [1, 2, 3], "une globale de ce module survit")
    check_eq(gc.stats()["threshold"] >= 64, true, "le seuil reste cohérent")

# --- 6. pilotage ------------------------------------------------------------------------------------------------

async func t_control():
    check(gc.is_enabled(), "activé par défaut")
    old := gc.disable()
    check(old, "disable() retourne l'état précédent")
    before := gc.stats()["collections"]
    churn(20000)
    check_eq(gc.stats()["collections"], before, "désactivé : aucune collecte automatique")
    gc.collect()
    check_eq(gc.stats()["collections"], before + 1, "collect() fonctionne même désactivé")
    gc.enable()
    check(gc.is_enabled(), "réactivé")
    prev := gc.set_threshold(1000)
    b2 := gc.stats()["collections"]
    churn(5000)
    check(gc.stats()["collections"] > b2, "un petit seuil provoque des collectes")
    gc.set_threshold(prev)
    raises_arg := false
    try:
        gc.set_threshold(0)
    catch e:
        raises_arg = e.type == "ArgumentError"
    check(raises_arg, "seuil invalide refusé")

async func t_stress():
    # collecte toutes les 5 instructions pendant une petite charge : le résultat doit être identique
    gc.set_stress(5)
    d := {}
    i := 0
    while i < 200:
        d[i] = [i, str(i), (i, i + 1)]
        i = i + 1
    s := 0
    for k in keys(d):
        s = s + d[k][0] + len(d[k][1])
    gc.set_stress(0)
    check_eq(s, 20390, "calcul identique sous stress GC")
    check_eq(len(d), 200, "dictionnaire intact")

async func main():
    await run("mémoire bornée", t_bounded)
    await run("cycles libérés", t_cycles)
    await run("données vivantes préservées", t_survival)
    await run("exceptions capturées", t_exceptions)
    await run("tâches suspendues", t_tasks)
    await run("promesse et attendant", t_promise)
    await run("état global", t_globals)
    await run("pilotage (enable/seuil)", t_control)
    await run("stress GC", t_stress)

await main()
print(f"gc : {stats[0]} vérifications OK, {stats[1]} échec(s)")
if stats[1] > 0:
    raise("AssertionError", "test_gc : échecs")
