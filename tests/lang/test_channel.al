# =============================================================================
# ALEX - tests des canaux (stdlib/channel, docs/CHANNELS.md) :
#   1. canal tamponné : ordre FIFO, try_send/try_recv, taille, capacité ;
#   2. canal sans tampon : rendez-vous, contre-pression d'un tampon plein ;
#   3. équité : récepteurs et émetteurs servis dans l'ordre des appels ;
#   4. fermeture : valeurs restantes lisibles, ChannelClosedError, attendants réveillés ;
#   5. annulation : délai, tâche annulée, émetteur annulé -> aucune valeur perdue ni volée ;
#   6. select : premier cas prêt, blocage, émission, canal fermé, perdants sans effet, balayage, délai ;
#   7. each / drain, tubes de tâches (producteur -> travailleurs -> collecteur) ;
#   8. erreurs d'arguments, interblocage.
#
# Lancer DEPUIS LA RACINE DU PROJET :  ./alex run tests/lang/test_channel.al
# =============================================================================
use asyncio
use channel
from channel use Channel
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

# Type de l'exception levée en attendant `f`, ou "aucune".
async func err_of(f):
    try:
        await f
    catch e:
        return e.type
    return "aucune"

async func snd(ch, v, log):
    await ch.send(v)
    append(log, f"s{v}")

async func rcv(ch, log):
    v := await ch.recv()
    append(log, f"r{v}")
    return v

async func rcv_quiet(ch):
    return await ch.recv()

# --- 1. canal tamponné -----------------------------------------------------------
async func t_tampon():
    ch := Channel(3)
    check_eq(ch.capacity(), 3, "capacité")
    check_eq(ch.size(), 0, "taille initiale")
    await ch.send(1)
    await ch.send(2)
    check_eq(ch.size(), 2, "taille après 2 envois")
    check_eq(await ch.recv(), 1, "FIFO 1")
    check_eq(await ch.recv(), 2, "FIFO 2")
    check_eq(ch.try_recv()[0], false, "try_recv sur canal vide")
    check_eq(ch.try_send(7), true, "try_send avec place")
    r := ch.try_recv()
    check_eq(r[0], true, "try_recv réussi")
    check_eq(r[1], 7, "try_recv valeur")
    check_eq(ch.try_send(1), true, "remplissage 1")
    check_eq(ch.try_send(2), true, "remplissage 2")
    check_eq(ch.try_send(3), true, "remplissage 3")
    check_eq(ch.try_send(4), false, "try_send sur tampon plein")
    check_eq(ch.size(), 3, "taille pleine")
    check_eq(ch.closed(), false, "pas fermé")
    nul := Channel(2)
    await nul.send(null)
    check_eq(await nul.recv(), null, "null est une valeur comme une autre")
    big := Channel(100)
    for i in 0..100:
        await big.send(i)
    ok := true
    for i in 0..100:
        if await big.recv() != i:
            ok = false
    check_eq(ok, true, "100 valeurs dans l'ordre")

# --- 2. rendez-vous et contre-pression -------------------------------------------
async func t_rendezvous():
    ch := Channel()
    log := []
    s := snd(ch, 1, log)
    await asyncio.sleep(0)
    check_eq(asyncio.done(s), false, "sans tampon : l'émetteur attend un récepteur")
    check_eq(len(log), 0, "rien d'émis encore")
    check_eq(await rcv(ch, log), 1, "le récepteur reçoit")
    await s
    check_eq(log, ["r1", "s1"], "ordre de réveil : récepteur puis émetteur")

    ch2 := Channel()
    r := rcv_quiet(ch2)
    await asyncio.sleep(0)
    check_eq(asyncio.done(r), false, "le récepteur attend un émetteur")
    await ch2.send("x")
    check_eq(await r, "x", "émission vers un récepteur en attente")

    # contre-pression : tampon de 2, 4 envois -> les 2 derniers attendent, l'ordre est conservé
    bp := Channel(2)
    log2 := []
    senders := [snd(bp, i, log2) for i in 0..4]
    await asyncio.sleep(0)
    check_eq(bp.size(), 2, "tampon plein")
    check_eq(len(log2), 2, "deux envois passés, deux en attente")
    out := []
    for i in 0..4:
        append(out, await bp.recv())
    check_eq(out, [0, 1, 2, 3], "ordre global conservé avec émetteurs en attente")
    await asyncio.gather(senders)
    check_eq(len(log2), 4, "tous les envois terminés")

# --- 3. équité ---------------------------------------------------------------------
async func t_equite():
    ch := Channel()
    rs := [rcv_quiet(ch) for i in 0..3]
    await asyncio.sleep(0)
    await ch.send("a")
    await ch.send("b")
    await ch.send("c")
    check_eq(await asyncio.gather(rs), ["a", "b", "c"], "récepteurs servis dans l'ordre")

    ch2 := Channel()
    log := []
    ss := [snd(ch2, i, log) for i in 0..3]
    await asyncio.sleep(0)
    got := [await ch2.recv(), await ch2.recv(), await ch2.recv()]
    check_eq(got, [0, 1, 2], "émetteurs servis dans l'ordre")
    await asyncio.gather(ss)

# --- 4. fermeture --------------------------------------------------------------------
async func t_fermeture():
    ch := Channel(2)
    await ch.send(1)
    await ch.send(2)
    check_eq(ch.close(), true, "close")
    check_eq(ch.close(), false, "close répété")
    check_eq(ch.closed(), true, "closed")
    check_eq(await ch.recv(), 1, "valeur restante 1")
    check_eq(await ch.recv(), 2, "valeur restante 2")
    check_eq(await err_of(ch.recv()), "ChannelClosedError", "recv après vidage")
    check_eq(await err_of(ch.send(3)), "ChannelClosedError", "send sur canal fermé")
    got := ""
    try:
        ch.try_send(1)
    catch e:
        got = e.type
    check_eq(got, "ChannelClosedError", "try_send sur canal fermé")
    got = ""
    try:
        ch.try_recv()
    catch e:
        got = e.type
    check_eq(got, "ChannelClosedError", "try_recv fermé et vidé")

    ch2 := Channel()
    t := err_of(ch2.recv())
    ch2.close()
    check_eq(await t, "ChannelClosedError", "récepteur en attente réveillé par close")

    ch3 := Channel()
    p := ch3.send(1)
    ch3.close()
    check_eq(await err_of(p), "ChannelClosedError", "émetteur en attente réveillé par close")
    check_eq(ch3.try_send != null, true, "méthode accessible")

# --- 5. annulation ---------------------------------------------------------------------
async func t_annulation():
    # délai sur recv : la promesse expirée ne vole pas la valeur suivante
    ch := Channel()
    check_eq(await err_of(asyncio.timeout(ch.recv(), 0.01)), "TimeoutError", "recv expiré")
    check_eq(ch.try_send(5), false, "pas de récepteur fantôme après délai")
    r := ch.recv()
    check_eq(ch.try_send(5), true, "le récepteur vivant reçoit")
    check_eq(await r, 5, "valeur livrée au bon récepteur")

    # tâche annulée pendant qu'elle attend recv : la valeur va au récepteur suivant
    ch2 := Channel()
    log := []
    t := rcv(ch2, log)
    await asyncio.sleep(0)
    asyncio.cancel(t)
    await asyncio.sleep(0)
    check_eq(asyncio.cancelled(t), true, "tâche annulée")
    nxt := ch2.recv()
    await ch2.send(9)
    check_eq(await nxt, 9, "valeur non perdue après annulation d'un récepteur")
    check_eq(len(log), 0, "la tâche annulée n'a rien reçu")

    # idem à travers asyncio.timeout (futur chaîné)
    ch3 := Channel()
    w := err_of(asyncio.timeout(ch3.recv(), 5))
    await asyncio.sleep(0)
    asyncio.cancel(w)
    await asyncio.sleep(0)
    check_eq(ch3.try_send(1), false, "annulation à travers timeout : pas de fantôme")
    nxt3 := ch3.recv()
    check_eq(ch3.try_send(2), true, "récepteur vivant")
    check_eq(await nxt3, 2, "valeur livrée")

    # émetteur annulé : sa valeur n'est jamais émise
    ch4 := Channel()
    log4 := []
    s := snd(ch4, 1, log4)
    await asyncio.sleep(0)
    asyncio.cancel(s)
    await asyncio.sleep(0)
    check_eq(ch4.try_recv()[0], false, "émission annulée : rien à recevoir")
    check_eq(ch4.size(), 0, "tampon vide")

    # délai sur un envoi bloqué
    ch5 := Channel(1)
    await ch5.send("a")
    check_eq(await err_of(asyncio.timeout(ch5.send("b"), 0.01)), "TimeoutError", "send expiré")
    check_eq(await ch5.recv(), "a", "valeur du tampon")
    check_eq(ch5.try_recv()[0], false, "la valeur de l'envoi expiré n'est pas apparue")

    # un futur mort dont on a annulé l'attendant se réattend proprement (annulé, pas figé)
    ch6 := Channel()
    p := ch6.recv()
    w6 := err_of(p)
    await asyncio.sleep(0)
    asyncio.cancel(w6)
    await asyncio.sleep(0)
    ch6.try_send(1)
    check_eq(await err_of(p), "CancelledError", "futur abandonné : CancelledError à la réattente")

# --- 6. select ----------------------------------------------------------------------------
async func t_select():
    a := Channel(1)
    b := Channel(1)
    await a.send("A")
    await b.send("B")
    s := await channel.select([a, b])
    check_eq(s[0], 0, "premier cas prêt gagne : indice")
    check_eq(s[1], true, "ok")
    check_eq(s[2], "A", "valeur")
    check_eq(b.size(), 1, "le canal perdant n'a rien perdu")

    # blocage puis réveil par le deuxième canal
    c := Channel()
    d := Channel()
    p := channel.select([c, d])
    await asyncio.sleep(0)
    check_eq(asyncio.done(p), false, "select attend")
    await d.send("D")
    r := await p
    check_eq(r[0], 1, "indice du canal servi")
    check_eq(r[2], "D", "valeur du canal servi")
    check_eq(c.try_send(1), false, "le canal perdant ne livre pas à l'entrée morte")

    # perdant tamponné : la valeur reste dans son tampon
    e := Channel()
    f := Channel(1)
    p2 := channel.select([e, f])
    e.try_send("E")
    check_eq((await p2)[2], "E", "premier arrivé")
    check_eq(f.try_send("F"), true, "envoi suivant sur le perdant")
    check_eq(f.size(), 1, "va dans le tampon, pas dans l'entrée morte")

    # cas d'émission
    g := Channel()
    rg := rcv_quiet(g)
    await asyncio.sleep(0)
    se := await channel.select([[g, "envoi"]])
    check_eq(se[0], 0, "émission : indice")
    check_eq(se[1], true, "émission : ok")
    check_eq(await rg, "envoi", "émission reçue")

    h := Channel()
    ph := channel.select([[h, 42]])
    await asyncio.sleep(0)
    check_eq(await h.recv(), 42, "émission en attente prise par un récepteur")
    check_eq((await ph)[1], true, "select d'émission terminé")

    # fermeture : ok == false
    k := Channel()
    k.close()
    sk := await channel.select([Channel(), k])
    check_eq(sk[0], 1, "canal fermé prêt : indice")
    check_eq(sk[1], false, "canal fermé : ok faux")
    m := Channel()
    pm := channel.select([m])
    await asyncio.sleep(0)
    m.close()
    check_eq((await pm)[1], false, "fermeture pendant l'attente")

    # délai
    n := Channel()
    check_eq(await err_of(asyncio.timeout(channel.select([n]), 0.01)), "TimeoutError", "select expiré")
    check_eq(n.try_send(1), false, "pas de fantôme après select expiré")

    # select en boucle sur un canal silencieux : les entrées mortes sont balayées
    data := Channel()
    done := Channel()
    ok := true
    for i in 0..300:
        ps := channel.select([data, done])
        data.try_send(i)
        v := await ps
        if v[0] != 0 or v[2] != i:
            ok = false
    check_eq(ok, true, "300 select consécutifs")
    check_eq(done.recvq.size() < 40, true, "entrées mortes balayées")

# --- 7. each / drain / tubes ----------------------------------------------------------------
async func produire(ch, n):
    for i in 0..n:
        await ch.send(i)
    ch.close()

async func travailleur(entree, sortie, id):
    await channel.each(entree, v => sortie.send(v * 10))

async func t_aides():
    ch := Channel()
    produire(ch, 5)
    check_eq(await channel.drain(ch), [0, 1, 2, 3, 4], "drain")

    ch2 := Channel(2)
    produire(ch2, 4)
    seen := []
    await channel.each(ch2, v => append(seen, v))
    check_eq(seen, [0, 1, 2, 3], "each (fonction ordinaire)")

    ch3 := Channel()
    produire(ch3, 3)
    seen3 := []
    async func noter(v):
        await asyncio.sleep(0)
        append(seen3, v + 100)
    await channel.each(ch3, noter)
    check_eq(seen3, [100, 101, 102], "each (fonction async attendue)")

    # tube : 1 producteur, 3 travailleurs, 1 collecteur
    jobs := Channel(4)
    res := Channel(4)
    produire(jobs, 12)
    ws := [travailleur(jobs, res, i) for i in 0..3]
    collecteur := channel.drain(res)
    await asyncio.gather(ws)
    res.close()
    out := await collecteur
    total := 0
    for v in out:
        total = total + v
    check_eq(len(out), 12, "12 résultats")
    check_eq(total, 660, "somme des résultats (10 * (0+...+11))")

# --- 8. erreurs ---------------------------------------------------------------------------------
async func t_erreurs():
    got := ""
    try:
        Channel(-1)
    catch e:
        got = e.type
    check_eq(got, "ArgumentError", "capacité négative")
    got = ""
    try:
        Channel("x")
    catch e:
        got = e.type
    check_eq(got, "ArgumentError", "capacité non entière")
    got = ""
    try:
        channel.select([])
    catch e:
        got = e.type
    check_eq(got, "ArgumentError", "select vide")
    got = ""
    try:
        channel.select([Channel(), 3])
    catch e:
        got = e.type
    check_eq(got, "ArgumentError", "select : cas invalide")

async func main():
    await run("canal tamponné", t_tampon)
    await run("rendez-vous et contre-pression", t_rendezvous)
    await run("équité", t_equite)
    await run("fermeture", t_fermeture)
    await run("annulation", t_annulation)
    await run("select", t_select)
    await run("each, drain, tubes", t_aides)
    await run("erreurs", t_erreurs)

await main()

# Interblocage : recv sur un canal que plus personne n'alimentera -> DeadlockError (rattrapable).
vide := Channel()
dead := ""
try:
    await vide.recv()
catch e:
    dead = e.type
check_eq(dead, "DeadlockError", "recv sans émetteur possible : interblocage détecté")

total := stats[0] + stats[1]
print("")
print("=== CANAUX ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total})")
if stats[1] > 0:
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS CANAUX PASSENT")
