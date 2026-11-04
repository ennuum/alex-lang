# =============================================================================
# ALEX - tests d'async/await (tâches, futurs, annulation, délais ; docs/ASYNC.md) :
#   1. appel d'une async func = tâche planifiée, `await` du résultat, await au niveau supérieur ;
#   2. entrelacement coopératif, ordre des délais, concurrence réelle (gather) ;
#   3. exceptions : propagation par await, try/catch autour d'un await, types conservés ;
#   4. annulation : tâche suspendue, nettoyage rattrapable, annulation d'un futur, d'une tâche terminée ;
#   5. délais (timeout) et course (race) ;
#   6. promesses : resolve/reject, premier gagnant, réveil de plusieurs attendants ;
#   7. méthodes async, fermetures, récursion ;
#   8. erreurs : await d'une non-future, auto-attente, interblocage du programme principal ;
#   9. abandon : `abandoned(f)` (attendant annulé, futurs chaînés par timeout/race).
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_async.al
# =============================================================================
use asyncio
from core use len
from collections use append, clear

stats := [0, 0]
notes := []

func check_eq(actual, expected, label):
    if actual == expected:
        stats[0] = stats[0] + 1
    else:
        stats[1] = stats[1] + 1
        append(notes, f"{label} : obtenu {actual}, attendu {expected}")

async func run(name, fn):
    clear(notes)
    before := stats[1]
    await fn()
    if stats[1] > before:
        print(f"  [ÉCHEC]  {name}")
        for n in notes:
            print(f"      {n}")
    else:
        print(f"  [ok]     {name}")

# --- 1. bases ------------------------------------------------------------------
async func double(x):
    return x * 2

async func slow_double(x, delay):
    await asyncio.sleep(delay)
    return x * 2

async func t_bases():
    check_eq(await double(21), 42, "await direct")
    t := double(5)
    check_eq(asyncio.is_task(t), true, "un appel async donne une tâche")
    check_eq(asyncio.done(t), false, "la tâche n'a pas encore tourné")
    check_eq(await t, 10, "await d'une tâche stockée")
    check_eq(asyncio.done(t), true, "terminée après await")
    check_eq(await t, 10, "await d'une tâche déjà terminée")
    check_eq(asyncio.result(t), 10, "result() sans attendre")
    check_eq(await slow_double(4, 0.01), 8, "await avec sleep")
    check_eq(await double(await double(3)), 12, "await imbriqués")
    check_eq(await double(1) + await double(2), 6, "await dans une expression")

# --- 2. entrelacement ----------------------------------------------------------
async func logger(log, name, n):
    for i in 0..n:
        append(log, f"{name}{i}")
        await asyncio.sleep(0)

async func t_entrelacement():
    log := []
    a := logger(log, "a", 3)
    b := logger(log, "b", 3)
    await a
    await b
    check_eq(log, ["a0", "b0", "a1", "b1", "a2", "b2"], "alternance coopérative stricte")

    order := []
    async func after(delay, label):
        await asyncio.sleep(delay)
        append(order, label)
    c := after(0.06, "lent")
    d := after(0.01, "rapide")
    e := after(0.03, "moyen")
    await asyncio.gather([c, d, e])
    check_eq(order, ["rapide", "moyen", "lent"], "ordre des délais")

    body_ran := [false]
    async func marque():
        body_ran[0] = true
    t := marque()
    check_eq(body_ran[0], false, "le corps ne s'exécute pas pendant l'appel")
    await t
    check_eq(body_ran[0], true, "le corps s'exécute au prochain tour")

    start := asyncio.now()
    r := await asyncio.gather([slow_double(1, 0.05), slow_double(2, 0.05), slow_double(3, 0.05)])
    elapsed := asyncio.now() - start
    check_eq(r, [2, 4, 6], "gather : résultats dans l'ordre")
    check_eq(elapsed < 0.12, true, "gather : exécution concurrente")
    check_eq(await asyncio.gather([]), [], "gather vide")

# --- 3. exceptions -------------------------------------------------------------
async func fail(kind):
    await asyncio.sleep(0)
    raise(kind, "boum")

async func t_exceptions():
    caught := []
    try:
        await fail("ValueError")
    catch e:
        append(caught, e.type)
        append(caught, e.message)
    check_eq(caught, ["ValueError", "boum"], "exception propagée par await")

    t := fail("KeyError")
    try:
        await t
    catch e:
        append(caught, e.type)
    check_eq(asyncio.failed(t), true, "failed() sur tâche échouée")
    check_eq(caught[2], "KeyError", "type conservé")

    async func rattrape():
        try:
            await fail("ValueError")
        catch e:
            return "rattrapé " + e.type
        return "non"
    check_eq(await rattrape(), "rattrapé ValueError", "try/catch autour d'un await dans une tâche")

    async func relais():
        return await fail("IOError")
    got := ""
    try:
        await relais()
    catch e:
        got = e.type
    check_eq(got, "IOError", "propagation à travers deux tâches")

    async func div():
        await asyncio.sleep(0)
        return 1 / 0
    got = ""
    try:
        await div()
    catch e:
        got = e.type
    check_eq(got, "ZeroDivisionError", "erreur runtime dans une tâche")

    a := fail("ValueError")
    b := double(5)
    try:
        await asyncio.gather([b, a])
    catch e:
        got = e.type
    check_eq(got, "ValueError", "gather relance l'échec")
    check_eq(await b, 10, "l'autre tâche a réussi")

# --- 4. annulation -------------------------------------------------------------
async func t_annulation():
    log := []
    async func travail():
        try:
            append(log, "début")
            await asyncio.sleep(10)
            append(log, "jamais")
        catch e:
            append(log, "nettoyage " + e.type)
            raise(e.type, e.message)
    t := travail()
    await asyncio.sleep(0.01)
    check_eq(asyncio.cancel(t), true, "cancel accepté")
    got := ""
    try:
        await t
    catch e:
        got = e.type
    check_eq(got, "CancelledError", "await d'une tâche annulée")
    check_eq(asyncio.cancelled(t), true, "cancelled()")
    check_eq(log, ["début", "nettoyage CancelledError"], "le code de nettoyage s'exécute")

    d := double(1)
    await d
    check_eq(asyncio.cancel(d), false, "cancel d'une tâche terminée")

    async func jamais():
        append(log, "démarré")
        await asyncio.sleep(0)
    clear(log)
    n := jamais()
    asyncio.cancel(n)
    got = ""
    try:
        await n
    catch e:
        got = e.type
    check_eq(got, "CancelledError", "annulée avant de démarrer")
    check_eq(log, [], "le corps n'a jamais tourné")

    p := asyncio.future()
    check_eq(asyncio.cancel(p), true, "annuler une promesse")
    check_eq(asyncio.cancelled(p), true, "promesse annulée")

    async func resiste():
        try:
            await asyncio.sleep(10)
        catch e:
            return "survécu"
    r := resiste()
    await asyncio.sleep(0.01)
    asyncio.cancel(r)
    check_eq(await r, "survécu", "CancelledError rattrapée : la tâche continue")

    async func auto():
        me := [0]
        await asyncio.sleep(0)
        return "fin"
    check_eq(await auto(), "fin", "tâche non annulée")

# --- 5. délais, course ---------------------------------------------------------
async func t_delais():
    got := ""
    slow := slow_double(1, 5)
    try:
        await asyncio.timeout(slow, 0.02)
    catch e:
        got = e.type
    check_eq(got, "TimeoutError", "timeout dépassé")
    await asyncio.sleep(0.01)
    check_eq(asyncio.cancelled(slow), true, "la tâche en retard est annulée")
    check_eq(await asyncio.timeout(slow_double(5, 0.01), 1.0), 10, "timeout non atteint")

    async func echoue():
        await asyncio.sleep(0)
        raise("ValueError", "x")
    got = ""
    try:
        await asyncio.timeout(echoue(), 1.0)
    catch e:
        got = e.type
    check_eq(got, "ValueError", "l'échec traverse timeout")

    w := await asyncio.race([slow_double(1, 0.08), slow_double(2, 0.01), slow_double(3, 0.05)])
    check_eq(w, 4, "race : le plus rapide gagne")

# --- 6. promesses --------------------------------------------------------------
async func t_promesses():
    p := asyncio.future()
    check_eq(asyncio.done(p), false, "promesse en attente")
    async func attend(f):
        return await f
    a := attend(p)
    b := attend(p)
    await asyncio.sleep(0)
    check_eq(asyncio.resolve(p, 99), true, "resolve")
    check_eq(asyncio.resolve(p, 1), false, "le premier gagne")
    check_eq(await a, 99, "attendant 1 réveillé")
    check_eq(await b, 99, "attendant 2 réveillé")
    check_eq(await p, 99, "await d'une promesse résolue")

    q := asyncio.future()
    asyncio.reject(q, "ValueError", "refusé")
    got := ""
    try:
        await q
    catch e:
        got = e.type + ":" + e.message
    check_eq(got, "ValueError:refusé", "reject")

    r := asyncio.future()
    async func producteur():
        await asyncio.sleep(0.01)
        asyncio.resolve(r, "livré")
    producteur()
    check_eq(await r, "livré", "une tâche complète une promesse")

# --- 7. méthodes, fermetures, récursion ------------------------------------------
class Service:
    base := 100
    func init(k):
        self.k = k
    async func calcule(x):
        await asyncio.sleep(0)
        return x * self.k + self.base

async func fib(n):
    if n < 2:
        return n
    a := fib(n - 1)
    b := fib(n - 2)
    return await a + await b

async func t_divers():
    s := Service(3)
    check_eq(await s.calcule(5), 115, "méthode async")
    check_eq(await fib(10), 55, "récursion async")
    mult := 7
    async func fermee(x):
        return x * mult
    check_eq(await fermee(6), 42, "fermeture")
    fs := [double(i) for i in 0..4]
    check_eq(await asyncio.gather(fs), [0, 2, 4, 6], "compréhension de tâches")
    total := 0
    for i in 0..3:
        total = total + await double(i)
    check_eq(total, 6, "await dans une boucle")
    waiters := [attend_val(i) for i in 0..50]
    check_eq(len(await asyncio.gather(waiters)), 50, "50 tâches")

async func attend_val(i):
    await asyncio.sleep(0)
    return i

# --- 8. erreurs ----------------------------------------------------------------
async func t_erreurs():
    got := ""
    try:
        await 42
    catch e:
        got = e.type
    check_eq(got, "TypeError", "await d'un int")

    async func soi():
        return await me_task[0]
    me_task := [0]
    m := soi()
    me_task[0] = m
    got = ""
    try:
        await m
    catch e:
        got = e.type
    check_eq(got, "InvalidStateError", "une tâche ne s'attend pas elle-même")

# --- 9. abandon ----------------------------------------------------------------
async func attend(f):
    await f

async func t_abandon():
    p := asyncio.future()
    check_eq(asyncio.abandoned(p), false, "jamais attendu : pas abandonné")
    t := attend(p)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(p), false, "attendu : pas abandonné")
    asyncio.cancel(t)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(p), true, "son seul attendant est annulé : abandonné")

    # deux attendants : tant qu'il en reste un, pas abandonné
    q := asyncio.future()
    t1 := attend(q)
    t2 := attend(q)
    await asyncio.sleep(0)
    asyncio.cancel(t1)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(q), false, "un attendant reste")
    asyncio.cancel(t2)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(q), true, "plus aucun attendant")

    # réattendu : de nouveau vivant
    r := asyncio.future()
    t3 := attend(r)
    await asyncio.sleep(0)
    asyncio.cancel(t3)
    await asyncio.sleep(0)
    t4 := attend(r)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(r), false, "réattendu : plus abandonné")
    asyncio.resolve(r, 1)
    await t4

    # futurs chaînés : timeout et race
    u := asyncio.future()
    g := asyncio.timeout(u, 5)
    check_eq(asyncio.abandoned(u), false, "chaîné mais jamais attendu")
    t5 := attend(g)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(u), false, "chaîné et attendu")
    asyncio.cancel(t5)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(u), true, "timeout abandonné -> source abandonnée")

    a := asyncio.future()
    b := asyncio.future()
    t6 := attend(asyncio.race([a, b]))
    await asyncio.sleep(0)
    asyncio.cancel(t6)
    await asyncio.sleep(0)
    check_eq(asyncio.abandoned(a) and asyncio.abandoned(b), true, "race abandonnée -> sources abandonnées")

    # un futur terminé n'est jamais « abandonné »
    c := asyncio.future()
    asyncio.resolve(c, 1)
    check_eq(asyncio.abandoned(c), false, "terminé : pas abandonné")

async func main():
    await run("bases", t_bases)
    await run("entrelacement", t_entrelacement)
    await run("exceptions", t_exceptions)
    await run("annulation", t_annulation)
    await run("délais et course", t_delais)
    await run("promesses", t_promesses)
    await run("méthodes, fermetures, récursion", t_divers)
    await run("erreurs", t_erreurs)
    await run("abandon", t_abandon)

await main()

# Interblocage : plus aucune tâche ne peut réveiller le programme principal -> DeadlockError (rattrapable) au
# lieu d'un gel silencieux. Testé au niveau supérieur : c'est la coroutine principale qui reçoit l'erreur.
never := asyncio.future()
dead := ""
try:
    await never
catch e:
    dead = e.type
check_eq(dead, "DeadlockError", "interblocage détecté (programme principal)")

# Un échec jamais attendu ne doit pas disparaître : avertissement sur stderr en fin de programme.
async func perdue():
    raise("ValueError", "perdue")
perdue()
await asyncio.sleep(0.01)

total := stats[0] + stats[1]
print("")
print("=== ASYNC / AWAIT ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS ASYNC PASSENT")
