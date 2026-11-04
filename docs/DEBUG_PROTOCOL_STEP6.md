# Étape 6 — protocole de débogage JSON Lines

Cette étape fournit une couche de protocole testée, destinée à devenir le contrat IPC entre l'IDE et le processus `alex`. Un message JSON occupe une ligne UTF-8. Les commandes prises en charge par le parseur sont :

- `{"command":"continue"}`, `pause`, `stop`
- `{"command":"step","mode":"into|over|out"}`
- `{"command":"breakpoint.add","file":"...","line":12}`
- `{"command":"breakpoint.remove","file":"...","line":12}`

Les événements de sortie sérialisés contiennent `event`, `message`, `file`, `line` et `frames`. Chaque frame expose `function`, `file`, `line` et `locals`; chaque variable expose `name`, `type` et `value` comme chaînes afin de ne jamais exporter directement des pointeurs ou des valeurs `rt::Value` à travers le processus.

## Fichiers

- `include/alex/debug/Protocol.hpp` : échappement JSON, parseur limité aux commandes autorisées et sérialisation des événements.
- `tests/test_debug_protocol.cpp` : tests des commandes valides, refus des modes/commandes invalides et échappement des événements.
- `make test-debug-protocol` : compilation et exécution du test.

## Limite importante

Cette livraison n'ajoute pas encore de commande `alex debug` et ne relie pas le protocole à `DebugSession` ni à `stdlib/outils/editeur_app.al`. Le parseur est volontairement limité au schéma de commande défini ici et n'est pas un parseur JSON général. L'étape suivante consiste à créer le mode CLI `alex debug fichier.al`, exécuter la VM avec le hook, écrire les événements sur stdout, lire les commandes depuis stdin et connecter les boutons de l'éditeur à ce flux.
