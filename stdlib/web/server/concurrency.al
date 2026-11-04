# ALEX STANDARD LIBRARY — web.server.concurrency
#
# Modèle d'exécution du serveur : UN fil, une boucle d'événements. Toutes les connexions sont surveillées
# ensemble (network.socket.wait) et lues sans blocage ; une requête n'est traitée que lorsqu'elle est entièrement
# arrivée, si bien qu'un client lent n'immobilise jamais le serveur pendant la RÉCEPTION. Le TRAITEMENT d'une
# requête (le gestionnaire) et l'envoi de sa réponse sont, eux, séquentiels : un gestionnaire long retarde les
# autres — pour des calculs lourds, utiliser un fil (thread) ou une file de travaux.
#
# Équité : à chaque tour, au plus per_connection requêtes par connexion (pipelining) et max_per_tick requêtes au
# total, pour qu'une connexion bavarde ne monopolise pas le serveur.
#
#   use web.server.concurrency as cc
#   loop := cc.EventLoop()
#   prets := loop.wait([ecoute_socket, sock1, sock2], 0.5)     # sockets lisibles
#   pol := cc.Policy(1, 64)
#   pol.order(connexions, tour)                               # ordre de service tournant
#
# Pour utiliser plusieurs cœurs : lancer plusieurs processus serveurs derrière un répartiteur (ou plusieurs ports).

from core use len, type
from collections use append
use network.socket as _sk

class Policy:
    func init(per_connection=1, max_per_tick=64, accept_per_tick=32):
        self.per_connection = per_connection     # requêtes traitées par connexion et par tour
        self.max_per_tick = max_per_tick         # requêtes traitées par tour, toutes connexions
        self.accept_per_tick = accept_per_tick   # connexions acceptées par tour

    # Ordre de service tournant : on commence à la connexion n° (tour mod n).
    func order(connections, tick):
        n := len(connections)
        if n == 0:
            return []
        start := tick % n
        return connections[start:n] + connections[0:start]

class EventLoop:
    func init():
        self.ticks = 0
        self.waits = 0

    # Sockets lisibles parmi sockets (attente au plus timeout secondes ; 0 : simple consultation).
    func wait(sockets, timeout=0.5):
        self.waits += 1
        if len(sockets) == 0:
            return []
        try:
            return _sk.wait(sockets, "read", timeout)
        catch e:
            # un socket fermé entre-temps : on consulte un par un
            out := []
            for s in sockets:
                try:
                    if len(_sk.wait([s], "read", 0)) > 0:
                        append(out, s)
                catch e2:
                    append(out, s)
            return out

    func tick():
        self.ticks += 1
        return self.ticks

func default_policy():
    return Policy()
