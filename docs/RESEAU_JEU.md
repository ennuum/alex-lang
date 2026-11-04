# Réseau multijoueur : netgame

| Module | Rôle |
|---|---|
| `netgame` | connexion sur UDP : poignée de main, messages fiables ordonnés et non fiables, accusés, RTT, pertes, fragmentation ; transports UDP, boucle locale, liaison simulée |
| `netgame.codec` | sérialisation binaire compacte (entiers variables, réels quantifiés, valeurs étiquetées), copie profonde, somme de contrôle |
| `netgame.snapshot` | instantanés du monde compressés par différence, horloge serveur estimée, interpolation |
| `netgame.prediction` | prédiction côté client, réconciliation lissée, tampon d'entrées serveur |
| `netgame.rollback` | simulation à retour arrière (style GGPO) pour 2 joueurs ou plus |

Tests : `tests/gamedev/test_netgame.al` (13 tests, liaisons simulées reproductibles et UDP réel).
Démo : `./alex run examples/gamedev/net_demo.al` (solo : serveur + vous + un robot, liaison simulée 100 ms / 5 %),
`... net_demo.al serveur 27015` puis `... net_demo.al client 192.168.1.20 27015` sur une autre machine.

## Quel modèle choisir

| Jeu | Modèle | Modules |
|---|---|---|
| tir, action, MMO léger, beaucoup de joueurs | serveur autoritaire : instantanés + interpolation des autres + prédiction de son propre personnage | `snapshot`, `prediction` |
| combat, course, sport à 2-4 joueurs, besoin de précision à l'image | rollback : chacun simule tout, les entrées seules circulent | `rollback` |
| tour par tour, jeu de cartes, lobby, discussion | messages fiables seuls | `netgame` |

## Connexion

```alex
use netgame
srv := netgame.Server(netgame.UdpTransport("0.0.0.0", 27015), 16)      # 16 clients au plus
cli := netgame.Client(netgame.UdpTransport())
cli.connect("monserveur.example", 27015)

# chaque pas réseau, des deux côtés
for e in srv.update():
    if e["type"] == "connect": ...                    # e["client"] : numéro du client
    elif e["type"] == "message": ...                  # e["data"], e["reliable"]
    elif e["type"] == "disconnect": ...               # e["reason"] : "client", "timeout", "server"
srv.send(id, {"t": "bienvenue"}, true)                # fiable et ordonné
srv.broadcast({"t": "explosion", "x": 3}, false)      # non fiable
srv.flush()                                           # paquets réellement envoyés ici
```

- **Paquets** : identifiant de protocole (2 octets), type, clé de connexion (4 octets), numéro, accusé et 32 bits
  d'accusés précédents, puis les messages. Un paquet porte plusieurs messages ; ils sont groupés jusqu'à 1 200
  octets (MTU) pour éviter la fragmentation IP.
- **Poignée de main** : demande (remplie à 256 octets contre l'amplification), défi du serveur, réponse prouvant la
  réception du défi, acceptation. La clé obtenue est vérifiée dans chaque paquet de données : un tiers qui usurpe
  l'adresse sans voir le trafic est ignoré. Ce n'est pas du chiffrement (voir les limites).
- **Fiable** : renvoyé après RTT + 2 x écart (30 ms au moins) jusqu'à accusé, livré dans l'ordre, morceaux de 1 Kio
  reconstitués. **Non fiable** : jamais en double ; un message fragmenté dont un morceau manque est abandonné.
- **Mesures** : `cli.rtt()`, `srv.rtt(id)`, `connection.loss` (taux de perte lissé), `connection.stats`
  (paquets, octets, renvois, pertes).
- **Délais** : expiration après `timeout` secondes sans paquet (5 par défaut) ; un paquet de maintien part toutes
  les 0,25 s si rien d'autre n'est envoyé. `cli.disconnect()` et `srv.disconnect(id)` préviennent l'autre côté.
- **Transports** : `UdpTransport(hôte, port)`, `LoopbackHub().endpoint(nom)` (en mémoire : tests, solo), et
  `LinkSim(transport, latence, gigue, perte, doublons, graine, horloge)` qui simule une mauvaise liaison
  (reproductible avec `ManualClock`). Pour essayer son jeu dans de mauvaises conditions :
  `netgame.Client(netgame.LinkSim(netgame.UdpTransport(), 0.08, 0.02, 0.05))`.
- `raw=true` (serveur ou client) livre les messages en octets sans décodage ; `send_raw` envoie des octets.

## Instantanés et interpolation

```alex
use netgame.snapshot as snap
schema := snap.Schema([["x", "float", 0.01], ["y", "float", 0.01], ["angle", "angle"], ["hp", "uint"],
                       ["arme", "str"]])
# serveur, à chaque instantané (20 Hz par exemple)
ss.capture(tick, {1: {"x": 3.2, "y": 0.5, "angle": 1.57, "hp": 100, "arme": "arc"}, 2: {...}})
for id in srv.client_ids():
    srv.send(id, ss.encode(id, {"input": derniere_entree[id], "me": etat[id]}))   # non fiable
# serveur, quand le client confirme : ss.ack(id, m["ack"])
# client
r := sc.receive(e["data"])          # [tick, extra] ; null si sa base a été perdue (le suivant arrivera)
cli.send({"ack": sc.ack_tick(), ...})
for id, etat in sc.sample(): ...    # états interpolés, 100 ms dans le passé
```

- Chaque client reçoit la **différence avec le dernier instantané qu'il a confirmé** : champs modifiés seulement,
  écarts quantifiés en entiers variables ; entités nouvelles entières, disparues par leur numéro. Mesuré : 32
  entités mobiles, environ 210 octets par instantané ; 6 ms par pas serveur pour 8 clients.
- Types : `float` (pas de quantification), `angle` (radians, interpolé par le plus court chemin), `int`, `uint`,
  `bool`, `str`, `any`. Le serveur ne garde que 64 instantanés : un client trop en retard repart d'un instantané
  complet.
- Le client estime l'horloge du serveur (décalage lissé, recalé au-delà de 250 ms) et interpole entre les deux
  instantanés qui encadrent `maintenant - delay` ; un instantané perdu élargit simplement l'intervalle.

## Prédiction côté client

```alex
use netgame.prediction as pred
func bouger(s, e, dt):                                # même fonction sur le serveur
    return {"x": s["x"] + e["dx"] * 5.0 * dt, "y": s["y"] + e["dy"] * 5.0 * dt}
p := pred.Predictor(bouger, etat_initial, 1.0 / 60.0, ["x", "y"])
# client, à chaque pas de simulation
p.apply({"dx": dx, "dy": dy})
cli.send({"in": p.pending_inputs(), "ack": sc.ack_tick()})
afficher(p.visual(dt_image))
# instantané reçu : p.reconcile(extra["me"], extra["input"])
# serveur, un InputBuffer par client : buf.receive(m["in"]) ; pour e in buf.pop_all(1) : simuler ; buf.last
```

- Les entrées non confirmées repartent dans chaque paquet (16 au plus) : une perte ne coûte rien.
- À la réception, le client repart de l'état autoritaire et rejoue ses entrées en attente. S'il s'était trompé
  (mur, collision, poussée), l'écart est amorti visuellement (`smooth_rate`), ou téléporté au-delà de `snap`.
  `p.corrections` et `p.last_error` aident à régler la simulation.

## Rollback

```alex
use netgame.rollback as rb
func step(etat, entrees):            # entrees[i] : entrée du joueur i ; DÉTERMINISTE
    ...
s := rb.RollbackSession(2, mon_numero, step, etat0, 2, 8)   # délai d'entrée 2 images, retour arrière 8 au plus
lien := rb.RollbackNet(s, srv_ou_cli)
# chaque image
for e in srv_ou_cli.update(): lien.handle(e)
if not lien.should_wait():
    s.add_local_input(manette())
    s.advance()                       # false : trop d'avance, on attend les autres
lien.send()
srv_ou_cli.flush()
dessiner(s.state)
```

- Les entrées distantes inconnues sont prédites (dernière entrée confirmée répétée). Quand l'entrée réelle arrive
  et diffère, l'état de cette image est rechargé et les images suivantes resimulées. `s.stats` : `rollbacks`,
  `resimulated`, `max_depth`, `stalls`.
- Synchronisation du temps : `should_wait()` fait patienter une image le pair qui a plus de 2 images d'avance.
- Désynchronisation : les sommes de contrôle des images confirmées sont échangées ; `s.desync` indique la première
  image divergente (`checksum_at(f)` pour comparer).
- Déterminisme : entiers ou réels quantifiés, aléa semé et tiré dans `step`, aucun appel à l'heure. L'état est copié
  par `netgame.codec.deep_copy` (listes et dictionnaires) ; pour des objets, fournir `copy` et `checksum`.
- Plus de deux joueurs : l'hôte (`netgame.Server`) relaie les entrées de chacun vers les autres.

## Limites

- Pas de chiffrement ni d'authentification forte : la clé de connexion écarte l'usurpation aveugle, pas un
  attaquant qui lit le trafic. Pour un jeu en ligne public, authentifier les joueurs par un service HTTPS et
  n'accepter que les clés délivrées par lui.
- Pas de traversée de NAT (STUN, relais) : le serveur ou l'hôte doit être joignable (redirection de port).
- Messages non fiables de 255 Kio au plus ; 4 096 morceaux fiables en attente par connexion.
- Interpréteur : prévoir un serveur dédié pour plus de 16 à 32 joueurs (le coût est surtout l'encodage des
  instantanés, proportionnel au nombre d'entités modifiées par client).
