# VERSIONS — versions du compilateur ALEX (bêta, stable)

Chaque compilation du compilateur `alex` reçoit une version **SemVer 2.0** complète, inscrite dans le binaire et
utilisée partout où la version compte : `alex --version`, bytecode produit, caches de modules, manifestes de
projets, serveur LSP, ALEX Studio, paquets de distribution, programmes ALEX (`os.alex_version()`).

| Canal | Version | Usage |
|---|---|---|
| `beta` (par défaut) | `1.2.0-beta.7` | compilations de développement et préversions : numéro de build croissant |
| `stable` | `1.2.0` | versions publiées (`make release`) |

Forme complète, avec l'empreinte des sources en métadonnée SemVer : `1.2.0-beta.7+3fa9c2d81b0e`. Selon
l'ordre SemVer, une bêta **précède** la version finale : `1.2.0-beta.7 < 1.2.0 < 1.2.1-beta.1`.

## Compiler

```
make                       # canal mémorisé (bêta au départ) : 1.0.0-beta.N, N augmente à chaque compilation
make CHANNEL=stable        # version stable : 1.0.0 ; le canal reste « stable » pour les make suivants
make CHANNEL=beta          # retour au canal bêta
make release               # compilateur stable + suite de tests complète + paquets (dist/)
make version               # version de base et canal courants
make version-bump PART=minor     # VERSION : 1.0.0 -> 1.1.0 (major | minor | patch)
make version-set V=2.0.0
make test-version          # tests de la gestion des versions
```

- **Source de vérité** : le fichier `VERSION` à la racine (`MAJEUR.MINEUR.CORRECTIF`, sans zéro initial).
- **Canal** : `CHANNEL=beta|stable` ; tout autre canal est refusé. Il est mémorisé dans `build/.channel`.
- **À chaque compilation du compilateur** (une source a changé, ou `VERSION`, ou le canal),
  `tools/version.sh gen` régénère `build/generated/alex_build_info.h` :
  - numéro de build suivant : compteur par version et par canal, rangé dans `.alex-build/` (il survit à
    `make clean`), ou valeur imposée par `BUILD_NUMBER` en intégration continue ;
  - date de construction (UTC), ou `SOURCE_DATE_EPOCH` pour un build reproductible ;
  - empreinte SHA-256 (12 caractères) des sources C++, de `VERSION`, du canal et des options de compilation ;
  - commit git s'il y en a un, compilateur C++ utilisé, plateforme.
  Un `make` qui ne recompile rien ne change pas la version.
- Les compteurs bêta repartent à 1 quand `VERSION` change (`1.1.0-beta.1` suit `1.0.0`).

## Consulter la version

```
$ alex --version
alex 1.0.0-beta.6 (bêta)
  canal       beta — version de test, ne pas utiliser en production
  build       6, 2026-10-11T10:55:02Z
  empreinte   459159f8668b
  compilé par g++ (Ubuntu 13.3.0) 13.3.0
  plateforme  linux-x86_64
  bytecode    ALBC 0.4 (lit 0.1 à 0.4)

$ alex version --short          # 1.0.0-beta.6         (--full : avec l'empreinte ; --channel : beta)
$ alex version --json           # objet JSON complet
$ alex version --check ">=1.0"  # code 0 si satisfaite, 1 sinon (scripts, CI)
$ alex version app.albc         # quel compilateur a produit ce bytecode / cet exécutable autonome ?
```

Depuis un programme ALEX :

```
use os
print(os.alex_version())             # "1.0.0-beta.6"
info := os.alex_build()              # {"version", "full", "base", "major", "minor", "patch", "channel", "build", ...}
if not os.alex_satisfies(">=1.1.0"):
    raise("RuntimeError", "ce programme demande ALEX 1.1 ou plus récent")
```

## Bytecode

Le format `.albc` passe en **0.4** : une section `PRODUCER` en fin de fichier nomme le compilateur
(`alex 1.0.0-beta.6+459159f8668b`) et le drapeau `BETA` des en-têtes indique une compilation bêta. Les
exécutables autonomes (`alexc build --standalone`) en héritent.

- Un fichier d'un format **plus récent** que celui que lit le runtime est refusé avec un message clair au lieu
  d'être mal décodé.
- Un `.albc` produit par un compilateur plus récent que le runtime (même format), ou par une bêta alors que le
  runtime est stable, s'exécute avec un avertissement.
- Les formats 0.1 à 0.3 restent lisibles.

## Caches de modules

Les caches `.albc` / `.al.meta` écrits à côté des modules enregistrent le compilateur qui les a produits
(`compiler=<version complète>`). Toute autre compilation du compilateur (nouveau build, autre canal) les
invalide, et ils sont recompilés à la première utilisation : plus de bytecode périmé après une mise à jour.

## Exigence des projets (`alex.toml`)

```
[package]
name = "monapp"
version = "0.3.0"
alex = ">=1.2.0"        # version minimale du compilateur (syntaxe des contraintes de dépendances)
```

- Vérifiée par `alexc run`, `build`, `check`, `test`, `debug`… (projet du dossier courant) et par `alexc pkg`.
- Comparaison SemVer complète : `1.3.0-beta.2` satisfait `>=1.2.0` mais pas `>=1.3.0`.
- `alexc pkg init` et `alexc new` écrivent `alex = ">=<version courante>"`.
- Dépendances du registre : une version dont le manifeste exige un compilateur plus récent est écartée, la plus
  haute version compatible est retenue, et `alexc pkg add` propose la dernière version utilisable ; si aucune ne
  convient, l'erreur liste les versions trop récentes et leur exigence. Une dépendance locale (`path`)
  incompatible est refusée.

## Distribution

`make package` nomme les archives d'après la version du compilateur (`alex-1.0.0-beta.6-linux-x86_64.tar.gz`) ;
le paquet Debian utilise `1.0.0~beta.6`, que `dpkg` classe avant `1.0.0`. `make dist` (compilation croisée)
régénère aussi les informations de version.

### Windows : installation et PATH

```
make installer-windows        # alex.exe (MinGW) -> dist/alex-1.0.0-beta.7-windows-x86_64.zip  (+ -setup.exe si Inno Setup)
make installer-windows PLATFORM=windows-i686
```

- **`alex-<version>-windows-x86_64-setup.exe`** (Inno Setup, `tools/windows/alex.iss`) : assistant en français / anglais,
  installation pour l'utilisateur courant (sans droits d'administrateur) ou pour tous les utilisateurs (boîte de
  dialogue / `/ALLUSERS`). La tâche **« Ajouter ALEX au PATH »** est cochée par défaut : `<dossier>\bin` est inscrit en
  tête du PATH (utilisateur ou système), sans doublon, valeur `REG_EXPAND_SZ` conservée, applications prévenues
  (`WM_SETTINGCHANGE`) ; la désinstallation le retire. Options : association des fichiers `.al`, raccourcis du menu
  Démarrer (invite de commandes, documentation). Mode silencieux : `setup.exe /VERYSILENT /ALLUSERS`.
- **`alex-<version>-windows-x86_64.zip`** : même contenu sans l'assistant ; `install.cmd` (ou `install.ps1`) fait la
  même installation et la même inscription au PATH (`-AllUsers`, `-InstallDir`, `-NoPath`, `-Associate`, `-Uninstall`).
- Installation : `bin\alex.exe`, `lib\alex\{stdlib,templates}`, `share\doc\alex` — la bibliothèque est trouvée à
  côté de l'exécutable. Le nom des fichiers suit la version du compilateur (bêta ou stable) ; une nouvelle version
  s'installe par-dessus la précédente. Ouvrir un **nouveau** terminal après l'installation, puis `alex --version`.
- Le `setup.exe` se construit avec Inno Setup 6 (`iscc`, ou `wine` ; sous Windows :
  `iscc /DAppVersion=... /DStageDir=... tools\windows\alex.iss`). Sans lui, le zip est produit seul.
- **ALEX Studio** n'est plus livré avec le SDK : c'est un projet séparé, avec son propre installeur
  (`alex-studio-<version>-windows-x86_64-setup.exe`), qui utilise le SDK installé.
- Test : `make test-installer` (assemblage du paquet et contrôles des scripts ; l'exécution réelle demande Windows).

Fichiers : `VERSION`, `tools/version.sh`, `include/alex/Version.hpp`, `src/Version.cpp`,
`tests/test_version.sh`, `tests/test_version.cpp`.
