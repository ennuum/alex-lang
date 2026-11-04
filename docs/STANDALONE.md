# Exécutables autonomes

Distribuer une application ALEX = distribuer **un seul fichier**, sans installer ALEX, sa stdlib ni les sources.

```sh
alexc build app.al --standalone            # -> ./app   (app.exe si le runtime est un .exe)
alexc build app.al --standalone -o dist/monoutil
./dist/monoutil arg1 "arg 2"
```

`alexc build` sans `--standalone` produit toujours un `.albc` (bytecode lié, à lancer par `alexc run app.albc`).

## Ce que contient l'exécutable

```
[ binaire alex (le « runtime ») ][ bytecode lié de l'application ][ taille : u64 LE ][ "ALEXAPP1" ]
```

- Le **bytecode** est exactement celui d'un `.albc` : programme + tous les modules importés (projet,
  `alex_packages`, stdlib) + prelude, déjà fusionnés. Rien n'est lu sur disque à l'exécution.
- Au démarrage, `alex` lit les 16 derniers octets de son propre fichier (`/proc/self/exe`,
  `_NSGetExecutablePath`, `GetModuleFileNameW`). S'il y trouve la signature `ALEXAPP1`, il exécute le
  bytecode embarqué ; sinon c'est le CLI `alex` habituel. Coût : une lecture de 16 octets (démarrage d'une
  petite application ≈ 6 ms).
- Une remorque incohérente (fichier tronqué ou modifié) donne `erreur: exécutable autonome corrompu…`, code 1.

## Comportement à l'exécution

| Aspect | Comportement |
|---|---|
| Ligne de commande | entièrement à l'application : `os.argv()` = `[chemin de l'exécutable, args…]`, `os.args()` = les args (aucune commande `alex` n'est interprétée) |
| Code de sortie | 0 en fin normale ; `os.exit(n)` (0..255) ; 1 si exception non rattrapée |
| Exception non rattrapée | trace de pile puis `Type: message` sur stderr (`ALEX_NO_TRACE=1` pour la masquer) |
| Sortie | pas de ligne « -- terminé » (contrairement à `alexc run`) |
| Variables d'environnement | `ALEX_GC`, `ALEX_GC_STRESS`, `ALEX_GC_POISON`, `ALEX_NO_TRACE` restent honorées |

`os.exit(code=0)` termine immédiatement : les sorties sont vidées mais les blocs `finally` en cours ne
s'exécutent pas.

**Chemins dans les traces** : les fichiers situés sous le dossier courant au moment du `build` (la racine du
projet) sont enregistrés en chemin **relatif** (`src/app.al`) ; l'exécutable n'embarque pas les chemins
absolus de la machine de construction. Les fichiers hors du projet (stdlib installée ailleurs) gardent leur
chemin absolu.

## Construire pour une autre plateforme

Le bytecode est portable ; seul le runtime dépend de la plateforme. `--runtime` choisit le binaire `alex` à
utiliser comme base, par exemple un binaire produit par `make dist` :

```sh
make dist PLATFORM=windows-x86_64                         # -> dist/windows-x86_64/alex.exe
alexc build app.al --standalone --runtime dist/windows-x86_64/alex.exe   # -> app.exe
```

Un exécutable autonome peut lui-même servir de `--runtime` : son ancien bytecode est retiré, pas empilé.

## Limites connues

- **macOS arm64** : ajouter des données invalide la signature de code ; re-signer après construction
  (`codesign -s - --force app`). Non testé dans cette version.
- **Windows** : le format (données en fin de PE) est standard, mais n'a pas encore été testé sur une vraie
  machine Windows dans cette version.
- Taille : le runtime complet (~2 Mo, interface graphique comprise) est copié dans chaque application.
- Les bibliothèques chargées par `ffi` (`.so`/`.dll`) ne sont pas embarquées : elles doivent être présentes
  sur la machine cible.
- Le bytecode n'est ni chiffré ni signé : ce n'est pas une protection du code source.

## Recherche de la stdlib (`alexc run` / `alexc build`)

Indépendamment des exécutables autonomes, `alex` cherche désormais la stdlib, dans l'ordre :

1. `$ALEX_STDLIB`
2. `./stdlib` (développement, depuis la racine du dépôt)
3. `<dossier du binaire alex>/stdlib` (distribution portable : `alex` + `stdlib/` côte à côte)
4. `<dossier du binaire alex>/../lib/alex/stdlib` (installation type Unix : `bin/alex`, `lib/alex/stdlib`)

Avant, seul `./stdlib` était essayé : `alex` ne fonctionnait que lancé depuis la racine du dépôt.

## Tests

`make test-standalone` (`tests/app/run_standalone_test.sh`) : 12 vérifications — exécution hors du dépôt
sans stdlib, arguments, `os.exit`, trace et code 1, absence de chemins absolus, reconstruction à partir d'un
exécutable autonome, remorque corrompue, CLI inchangé, recherche de la stdlib.
