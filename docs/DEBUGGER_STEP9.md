# Étape 9 — navigation source à chaque pause

## Changements

- À la réception d'un événement `paused`, l'éditeur sélectionne automatiquement l'onglet source correspondant au fichier signalé par la VM.
- Le curseur est déplacé au début de la ligne arrêtée et l'éditeur reprend le focus afin que la position source soit immédiatement visible.
- Si le chemin rapporté par le compilateur diffère du chemin de l'onglet, une résolution de secours par nom de fichier n'est utilisée que si ce nom est unique parmi les fichiers ouverts. Cela évite de sélectionner le mauvais fichier lorsque plusieurs dossiers contiennent un fichier du même nom.
- Les marqueurs de ligne courante et les points d'arrêt sont actualisés après la pause.
- Le panneau Débogueur conserve la pile d'appels et les variables locales exposées par l'événement JSON.

## Validation réalisée

```sh
./alex check stdlib/outils/editeur_app.al
./alex check stdlib/outils/editeur.al
make PLATFORM=linux-x86_64 test-debug-protocol
./alex run tests/test_json.al
```

Résultats : les deux fichiers de l'éditeur passent `alex check`, le test du protocole affiche `OK: debug protocol`, et les 199 vérifications JSON réussissent.

Pour le test graphique : ouvrir un fichier `.al`, poser un point d'arrêt (F2), démarrer le débogage (F6), puis vérifier qu'à chaque événement `paused`, l'onglet et le curseur suivent la position source rapportée.

## Limites

- La navigation est au niveau de la ligne ; la VM ne fournit pas encore une colonne source fiable pour placer le curseur au caractère exact.
- Si le bytecode ne conserve pas les noms source, les variables peuvent conserver des noms génériques tels que `local[0]`.
- Les objets complexes ne sont pas modifiables depuis le panneau et l'évaluation d'expressions n'est pas ajoutée à cette étape.
- Les vérifications CLI ne remplacent pas un test graphique sur chaque backend UI.
