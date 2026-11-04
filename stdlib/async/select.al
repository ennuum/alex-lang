# ALEX STANDARD LIBRARY — async.select
#
# Attendre le PREMIER prêt parmi plusieurs opérations de natures différentes : réception ou envoi sur un canal
# (channel.Channel), fin d'un futur ou d'une tâche, délai ; avec une branche par défaut si rien n'est prêt.
#
#   use async.select as sel
#   r := await sel.select([sel.recv(commandes), sel.recv(arret), sel.future(tache), sel.after(5.0)])
#   match r[0]:
#       0: traiter(r[1])
#       1: arreter()
#       2: print("tâche finie :", r[1])
#       3: print("rien depuis 5 s")
#   r := await sel.select([sel.recv(ch)], true)  # default : (-1, null) tout de suite si rien n'est prêt
#
# Résultat : (indice du cas, valeur) — valeur reçue, résultat du futur, null pour un envoi ou un délai. Un canal
# FERMÉ donne (indice, null) pour une réception (vérifier ch.closed()). Un futur qui échoue relance son erreur.
#
# Garanties : un seul cas s'exécute ; les opérations de canal qui n'ont pas gagné n'ont aucun effet (s'appuie sur
# channel.select). Si un cas de canal et un futur se terminent au même tour, le canal l'emporte (sa valeur n'est
# jamais perdue).
#
# Erreurs : celles des futurs ; ArgumentError (cas invalide, liste vide).

from core use len, type
from collections use append
use asyncio
use channel as _ch

async func _settle(f):
    try:
        await f
    catch e:
        return null
    return null

func recv(ch):
    return ["recv", ch, null]

func send(ch, value):
    return ["send", ch, value]

func future(f):
    return ["future", f, null]

func after(seconds):
    return ["after", seconds, null]

func _check(cases):
    if type(cases) != "list" or len(cases) == 0:
        raise("ArgumentError", "select : liste de cas non vide attendue")
    for c in cases:
        if type(c) != "list" or len(c) != 3 or (c[0] != "recv" and c[0] != "send" and c[0] != "future" and c[0] != "after"):
            raise("ArgumentError", "select : cas invalide (utiliser recv, send, future, after)")

func select(cases, default=false):
    _check(cases)
    return _select(cases, default)

async func _select(cases, default):
    chan_idx := []
    chan_cases := []
    for i in 0..len(cases):
        c := cases[i]
        if c[0] == "recv":
            append(chan_idx, i)
            append(chan_cases, c[1])
        elif c[0] == "send":
            append(chan_idx, i)
            append(chan_cases, [c[1], c[2]])
    # Prêt tout de suite ? (futurs terminés, puis canaux sans attente)
    for i in 0..len(cases):
        c := cases[i]
        if c[0] == "future" and asyncio.done(c[1]):
            return (i, await c[1])
    chan_sel := null
    if len(chan_cases) > 0:
        chan_sel = _ch.select(chan_cases)
        if asyncio.done(chan_sel):
            r := await chan_sel
            return (chan_idx[r[0]], r[2])
    if default:
        if chan_sel != null:
            asyncio.cancel(chan_sel)
        return (-1, null)
    racers := []
    timers := []
    if chan_sel != null:
        append(racers, chan_sel)
    for i in 0..len(cases):
        c := cases[i]
        if c[0] == "future":
            append(racers, c[1])
        elif c[0] == "after":
            t := asyncio.sleep(c[1])
            append(timers, [i, t])
            append(racers, t)
    await _settle(asyncio.race(racers))
    if chan_sel != null and asyncio.done(chan_sel) and not asyncio.cancelled(chan_sel):
        for t in timers:
            asyncio.cancel(t[1])
        r := await chan_sel
        return (chan_idx[r[0]], r[2])
    if chan_sel != null:
        asyncio.cancel(chan_sel)
    for t in timers:
        if not asyncio.done(t[1]):
            asyncio.cancel(t[1])
    for i in 0..len(cases):
        c := cases[i]
        if c[0] == "future" and asyncio.done(c[1]):
            return (i, await c[1])
        if c[0] == "after":
            for t in timers:
                if t[0] == i and asyncio.done(t[1]) and not asyncio.cancelled(t[1]):
                    return (i, null)
    raise("InvalidStateError", "select : aucun cas terminé")
