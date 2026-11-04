# Phase 1 — exceptions, traces de pile, exécutables autonomes, dicts ordonnés, build

Tests : 17 binaires C++, 52 programmes `.al`, `test-trace`, `test-standalone`, `test-dict-order` au vert (dont sous `ALEX_GC_STRESS` / `ALEX_GC_POISON`) ; build sans avertissement.

## Exécutables autonomes (docs/STANDALONE.md)

- `alexc build app.al --standalone [-o app] [--runtime alex-d-une-autre-plateforme]` : un seul fichier
  exécutable = runtime `alex` + bytecode lié de l'application ; aucune stdlib ni source requise à l'exécution.
- Nouveau : `os.exit(code=0)` (codes de sortie des applications).
- `alex` trouve la stdlib hors de la racine du dépôt : `$ALEX_STDLIB`, `./stdlib`, `<bin>/stdlib`,
  `<bin>/../lib/alex/stdlib` (avant : `./stdlib` uniquement).
- Les chemins source enregistrés pour les traces sont relatifs au projet (pas de chemin absolu de la machine
  de construction dans un exécutable distribué).
- Correctif : le compilateur marquait encore ses modules en `VERSION_MINOR` 1, si bien que le fichier source
  était perdu dès qu'un module passait par un `.albc` (cache ou build). Couvert par `make test-trace`.
- Tests : `make test-standalone` (12 vérifications).

## Build incrémental (Makefile)

- Chaque source est compilée **une fois** dans `build/` (objets + dépendances d'en-têtes `-MMD -MP`).
- Les sources du langage et du runtime forment `build/libalex.a` ; chaque exécutable (`alex`, `alex-*`,
  binaires de test C++) = son `main` + `libalex.a`. Avant : chaque binaire recompilait ~45 sources.
- `build/.flags` mémorise `CXX CXXFLAGS` : changer d'options (ex. apparition des en-têtes X11) recompile tout.
  Remarque : `make -n` surestime le travail (il ne peut pas exécuter cette vérification) ; `make` réel ne
  recompile que ce qui a changé.
- `make clean` supprime aussi `build/`. La cible `dist` (compilation croisée) est inchangée.

## Exceptions (docs/RUNTIME.md §7, écarts D4 et D6 résolus)

| Fonctionnalité | Syntaxe / comportement |
|---|---|
| Clauses typées | `catch IndexError as e:` · `catch A, B as e:` · `catch (A, B):` · `catch e:` (générique, en dernier) |
| Correspondance | type exact, sous-type déclaré (`class X extends Y`), ou `Exception` (tout) ; sinon relance |
| `finally` | exécuté sur chemin normal, exception (puis relance), `return` (valeur calculée avant), `break`, `continue` |
| Relance | `raise(e)` relance le **même** objet (type, message, trace conservés) |
| Trace | `e.trace` : liste de `"fichier:ligne, dans fonction"` ; affichée par `alex run` si non capturée |
| `ALEX_NO_TRACE=1` | supprime l'affichage de la trace |

Nouveaux mots : `finally` (mot-clé réservé). Nouvel opcode : `EXC_MATCHES` (ajouté en fin d'énumération).

## Format bytecode

- `VERSION_MINOR` 2 : la `DEBUG_SECTION` porte, par fonction, `source_const` (fichier source) en plus de la
  table offset→ligne, désormais **remplie** par le compilateur (elle était vide). Les fichiers en mineure 1
  restent lisibles (sans fichier source).
- Cache des modules : `metaVersion=4` ; les anciens `.albc` / `.al.meta` sont ignorés et régénérés.

## Tests ajoutés / modifiés

- `tests/lang/test_exceptions.al` — `make test-exceptions` (18 vérifications)
- `tests/lang/run_trace_test.sh` + fixtures — `make test-trace` (dont module importé relu depuis le cache)
- `tests/app/run_standalone_test.sh` + `app.al`/`greet.al` — `make test-standalone`
- `tests/test_bc.cpp` : opcode `EXC_MATCHES`, aller-retour v2/v1, remappage par `mergeModules`, validation
- `tests/test_compiler.cpp` : plusieurs `catch` acceptés, `catch` après clause générique refusé, `finally`

## Dictionnaires ordonnés (D3)

`dict` itère dans l'ordre d'insertion (`rt::OrderedValueMap` : entrées en vecteur + index de hachage,
trous compactés à l'insertion). `json.parse` conserve l'ordre du texte ; `json.stringify` trie toujours par
défaut, `sort_keys=false` garde l'ordre d'insertion. Test : `make test-dict-order`.

## Avertissements de compilation

Build sans avertissement : `requireStr` (ui/string/io) ne prend plus de `std::string` temporaire
(`-Wdangling-reference`), motifs `List`/`Tuple` dans le dump d'AST, et l'indexation d'un `future` lève
désormais `TypeError` (le `switch` ne le traitait pas : rien n'était empilé).
