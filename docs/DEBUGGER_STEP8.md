# Étape 8 — intégration du débogueur dans l’éditeur Alex

Cette étape connecte `stdlib/outils/editeur_app.al` au processus `alex debug fichier.al` via le protocole JSON Lines de l’étape 7. L’interface reste écrite en Alex pur.

## Commandes dans l’éditeur

- **F6** : démarrer le débogueur ; une seconde action F6 continue l’exécution.
- **F9** : pas à pas, entrer dans les appels (`step into`).
- **Maj+F9** : exécuter jusqu’à l’instruction suivante du même niveau (`step over`).
- **Ctrl+F9** : sortir de la fonction courante (`step out`).
- **F2** : ajouter/supprimer un point d’arrêt sur la ligne du curseur.
- **Ctrl+F5** : arrêter le processus de débogage.
- Le panneau **Débogueur** affiche la pile d’appels et les variables locales du frame courant quand le programme est en pause. Le panneau **Sortie** conserve les événements et messages de session.

Les points d’arrêt restent mémorisés dans l’instance de l’éditeur et sont envoyés au démarrage du débogueur ; les changements effectués pendant une session sont envoyés immédiatement. Les événements JSON Lines sont lus de façon incrémentale, y compris lorsque plusieurs événements arrivent dans un même fragment de sortie.

## Validation réalisée

- `./alex check stdlib/outils/editeur_app.al` — OK.
- `./alex check stdlib/outils/editeur.al` — OK.
- `./alex run tests/test_json.al` — 199 vérifications réussies.
- Test d’intégration du processus `alex debug` : pause initiale, ajout d’un point d’arrêt à la ligne 2, reprise jusqu’à la pause ligne 2, reprise et terminaison ; sortie stdout analysable comme JSON Lines.

## Limites actuelles

- La ligne courante est signalée par un marqueur dans la marge, mais l’API de `ui.view.code_editor` ne permet pas encore de déplacer automatiquement le curseur sur cette ligne.
- Les variables sont présentées dans un panneau texte ; l’inspection interactive, l’édition de variables et l’évaluation d’expressions ne sont pas encore disponibles.
- Le bytecode peut ne pas conserver les noms source des variables ; dans ce cas la VM expose des noms génériques tels que `local[0]`.
- Le test d’intégration CLI est automatisé ; l’interaction graphique complète dépend du backend UI et doit aussi être vérifiée manuellement sur les plateformes cibles.
