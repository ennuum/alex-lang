# {{Nom}}

{{description}}

Projet créé avec `alexc new {{modele}} {{nom}}` (ALEX Studio : *Fichier › Nouveau projet*).

## Démarrer

| Commande | Rôle |
|---|---|
| `alexc run` | lancer l'application (fenêtre) |
| `alexc run -- --terminal` | la même interface dans le terminal |
| `alexc test` | lancer les tests (`tests/`) |
| `alexc fmt` | mettre le code en forme |
| `alexc check src/main.al` | analyse et vérification des types |
| `scripts/construire.ps1` | exécutable Windows `dist/{{nom}}.exe` (icône `assets/icone.ico`, sans console) |
| `scripts/construire.sh` | binaire Linux `dist/{{nom}}` |

`alexc` est le compilateur et la chaîne d'outils d'ALEX. Dans ALEX Studio : Exécuter (F5), Déboguer (F6),
Tests (Ctrl+Maj+T), Projet › Construire le binaire natif.

## Arborescence

```
{{nom}}/
├── alex.toml               manifeste : nom, version, point d'entrée, dossiers de sources, dépendances
├── src/                    code de l'application (racine des modules : sources = ["src"])
│   ├── main.al             point d'entrée : options, démarrage, boucle de l'interface
│   ├── app/
│   │   ├── config.al       identité, taille de la fenêtre, emplacement des données
│   │   └── application.al  état et actions (le « contrôleur »)
│   ├── modeles/            logique métier, sans interface ni fichier
│   │   └── taches.al
│   ├── services/           accès au système : fichiers, réseau…
│   │   └── stockage.al     sauvegarde JSON des tâches
│   └── vues/               interface ui.view (fonctions pures de l'état)
│       ├── principale.al
│       └── composants.al
├── assets/                 ressources : icône de l'application, images…
├── tests/                  tests unitaires (alexc test)
├── docs/                   documentation du projet (ARCHITECTURE.md)
├── scripts/                construction des exécutables de distribution
└── dist/                   exécutables produits (ignoré par git)
```

Les modules se référencent depuis `src/` : `use modeles.taches as taches`, `use vues.composants as composants`,
dans l'application comme dans les tests. Architecture et conventions : [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md).

## Données

Les tâches sont enregistrées après chaque modification dans `%APPDATA%\{{nom}}\taches.json` (Windows) ou
`~/.local/share/{{nom}}/taches.json` (Linux). Voir `src/app/config.al`.
