# Canaux — communication entre tâches

Un **canal** (`Channel`) transmet des valeurs d'une tâche à une autre. Il est écrit en ALEX pur
(`stdlib/channel/channel.al`) par-dessus les futurs d'`asyncio` : chaque opération renvoie un futur, que la
boucle complète quand le correspondant arrive.

```
use asyncio
use channel
from channel use Channel

async func produire(ch):
    for i in 1..4:
        await ch.send(i)            # attend si le tampon est plein
    ch.close()

async func main():
    ch := Channel(2)                # tampon de 2 ; Channel() = sans tampon (rendez-vous)
    produire(ch)
    print(await channel.drain(ch))  # [1, 2, 3]

await main()
```

## API

| Appel | Sens |
|---|---|
| `Channel(capacité=0)` | `0` : rendez-vous (l'émetteur attend un récepteur) ; `n` : tampon de `n` valeurs |
| `ch.send(v)` | **futur** terminé quand `v` est accepté (tampon ou récepteur) |
| `ch.recv()` | **futur** valant la prochaine valeur |
| `ch.try_send(v)` | `true` si accepté tout de suite, sinon `false` |
| `ch.try_recv()` | `(true, valeur)` ou `(false, null)` |
| `ch.close()` | ferme ; `false` si déjà fermé |
| `ch.closed()`, `ch.size()`, `ch.capacity()` | inspection (`size` = valeurs dans le tampon) |
| `channel.select(cas)` | premier cas prêt, voir plus bas |
| `channel.each(ch, fn)` | `async func` : `fn(v)` pour chaque valeur jusqu'à la fermeture (attend `fn(v)` si c'est une tâche) |
| `channel.drain(ch)` | `async func` : liste des valeurs jusqu'à la fermeture |

`send` et `recv` sont des fonctions **ordinaires** (pas des `async func`) qui renvoient un futur : l'opération
est enregistrée au moment de l'appel, pas au prochain tour de boucle. `asyncio.timeout(ch.recv(), 1.0)`,
`asyncio.race`, `asyncio.cancel` s'appliquent donc directement.

## Sémantique précise

- **Ordre.** FIFO partout : valeurs, récepteurs en attente, émetteurs en attente. Avec un tampon plein, une valeur
  d'émetteur en attente passe dans le tampon dès qu'une place se libère : l'ordre global est conservé.
- **Pas de cession de la main.** `await ch.send(v)` ne suspend pas si `v` est accepté tout de suite (même règle que
  `await` sur un futur terminé). Un producteur qui n'est jamais bloqué doit appeler `asyncio.sleep(0)` de temps en temps.
- **Fermeture.** Les valeurs déjà dans le tampon restent lisibles. Ensuite `recv()` échoue en `ChannelClosedError`.
  `send()` sur un canal fermé échoue en `ChannelClosedError`. À `close()`, les récepteurs en attente échouent de même,
  et les émetteurs en attente aussi (leur valeur est abandonnée). `try_send`/`try_recv` **lèvent** la même erreur.
- **Aucune valeur perdue ni volée.** Une valeur n'est retirée d'un canal que si la promesse de son correspondant a pu
  être complétée. Une opération expirée (`timeout`), annulée, ou perdante dans un `select` est donc ignorée :
  un récepteur expiré ne prend pas la valeur suivante, un émetteur annulé n'émet jamais.
- **Annulation d'une tâche en attente.** Annuler une tâche qui attend `recv()`/`send()` ne propage pas l'annulation
  au futur (règle d'ASYNC.md). Le canal détecte l'abandon grâce à `asyncio.abandoned(f)` : une entrée dont plus
  personne n'attend le résultat est écartée et son futur annulé. Ne **réattendez pas** un tel futur : il vaut
  `CancelledError`.
- **Limite connue.** Si une valeur vient d'être remise à une tâche et que celle-ci est annulée avant d'avoir repris
  (même tour de boucle), la valeur est perdue : l'annulation passe avant la reprise.

## select

```
r := await channel.select([a, b, [sortie, v]])   # a, b : réception ; [canal, v] : émission
# r = (indice, ok, valeur)
```

- Un cas est un canal (réception) ou une paire `[canal, valeur]` (émission). Résultat : le tuple
  `(indice, ok, valeur)` ; `valeur` est la valeur reçue (`null` pour une émission).
- `ok` vaut `false` si le canal du cas est **fermé** (comme `v, ok := <-ch` en Go) : `select` ne lève pas.
  Un canal fermé est toujours prêt : retirez-le de la liste quand il l'est.
- Si plusieurs cas sont prêts, le **premier de la liste** gagne (déterministe, pas aléatoire). Un seul cas
  s'exécute ; les autres n'ont aucun effet.
- `select` renvoie un futur : `asyncio.timeout(channel.select(...), 0.5)` borne l'attente.
- Les entrées d'un `select` terminé restent mortes dans les canaux perdants jusqu'à un balayage automatique
  (déclenché quand la file d'attente double), si bien qu'un `select` en boucle sur un canal silencieux ne fuit pas.

## Ce qui a changé ailleurs

Une seule primitive a été ajoutée au runtime : `asyncio.abandoned(f)` (voir ASYNC.md). Aucun opcode, aucun
changement de syntaxe, aucune règle d'`asyncio` modifiée.

## Tests

`make test-channel` (90 vérifications, `tests/lang/test_channel.al`) ; les cas d'abandon sont aussi dans
`tests/lang/test_async.al`. Exemple : `examples/channel_demo.al`.

## Hors périmètre (étapes suivantes)

E/S asynchrones, sockets, HTTP : même principe (un futur par opération, complété par la boucle). Ils n'ont pas
besoin des canaux, mais pourront les utiliser (flux de requêtes, files de connexions).
