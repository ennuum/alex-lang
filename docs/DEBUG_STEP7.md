# Étape 7 — commande `alex debug`

Cette étape connecte le protocole JSON Lines de l'étape 6 à la VM via `DebugSession`.

## Lancer

```sh
make PLATFORM=linux-x86_64 alex
./alex debug examples/mon_programme.al
```

`stdout` est réservé aux événements JSON Lines. La sortie normale de `print()` et les diagnostics restent sur `stderr`.

## Cycle de contrôle

Le processus s'arrête avant la première instruction et émet un événement `paused` (`message: "ready"`). L'IDE peut alors ajouter des points d'arrêt, puis envoyer une commande par ligne sur `stdin` :

```json
{"command":"breakpoint.add","file":"/chemin/mon_programme.al","line":12}
{"command":"continue"}
```

Commandes prises en charge :

- `continue`
- `step` avec `mode`: `into`, `over` ou `out`
- `pause` (demande une pause à la prochaine instruction; principalement utile pendant l'exécution)
- `stop`
- `breakpoint.add` / `breakpoint.remove` avec `file` et `line`

Événements émis : `paused`, `breakpoint`, `status`, `error`, `terminated`, `stopped`, `exception`.
Un événement `paused` inclut le fichier, la ligne, les frames et les variables locales disponibles. En l'absence de noms locaux dans le bytecode, celles-ci sont nommées `local[0]`, `local[1]`, etc.

## Limites connues

- L'éditeur `stdlib/outils/editeur_app.al` n'est pas encore raccordé à cette commande : l'étape 7 fournit le point d'entrée CLI et le transport.
- La saisie interactive du programme via `input()` partage actuellement `stdin` avec les commandes de débogage; cette combinaison n'est pas prise en charge par ce protocole minimal.
- Le protocole est un parseur de commandes JSON ciblé, pas un parseur JSON général.
- Les objets locaux sont affichés via leur représentation de diagnostic; l'inspection structurée des champs et les noms source des variables nécessitent des métadonnées bytecode supplémentaires.
