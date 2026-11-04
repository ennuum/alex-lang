# Architecture de {{Nom}}

L'application est découpée en couches ; chacune ne dépend que de celles du dessous.

```
vues/        interface ui.view       → lit l'état, appelle les actions
app/         état et actions          → modifie les modèles, déclenche l'enregistrement
services/    accès au système         → fichiers (stockage.al), réseau, horloge…
modeles/     logique métier           → aucune dépendance à l'interface ni au système
```

## Règles

* **modeles/** : classes et fonctions pures, entièrement testées (`tests/test_taches.al`). Pas d'`use ui.*`,
  pas d'accès aux fichiers.
* **services/** : seul endroit qui touche au système. Écritures atomiques, erreurs remontées en exceptions.
* **app/application.al** : l'unique état de l'application (`etat`) et les actions qui le modifient. Testé sans
  fenêtre (`tests/test_application.al`).
* **vues/** : fonctions qui renvoient des éléments ui.view à partir de l'état ; aucune logique métier. ui.view
  redessine la fenêtre après chaque action.
* **app/config.al** : constantes (nom, version, taille de fenêtre) et emplacements.

## Ajouter une fonctionnalité

1. le comportement dans `modeles/` (et son test) ;
2. l'action correspondante dans `app/application.al` (et son test) ;
3. l'élément d'interface dans `vues/composants.al`, assemblé dans `vues/principale.al`.

## Ressources

`assets/icone.ico` est l'icône de l'exécutable Windows (barre des tâches, explorateur, barre de titre) :
remplacez-la par la vôtre (16, 32, 48 et 256 px). Images et autres ressources vont dans `assets/`.
