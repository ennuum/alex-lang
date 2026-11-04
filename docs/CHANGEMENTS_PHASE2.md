# Phase 2 — types graduels

Détails : `docs/TYPES.md`.

- Syntaxe : `nom: T` (paramètres, variables, champs, constantes), `-> T` (retour), types `T?`, `list[T]`,
  `dict[K, V]`, `func(A) -> R`, entiers dimensionnés `i8…u64`, `f32`. Nouveau lexème `->`.
- `sem::TypeChecker` (src/TypeChecker.cpp) : vérification statique graduelle après l'Analyzer, toutes les
  erreurs d'un coup (`TypeCheckError`). Signatures typées exportées entre modules (`.meta`, `metaVersion=5`).
- Opcode `CHECK_TYPE` : vérification à l'exécution des paramètres, retours et variables annotés.
- `alex check fichier.al` : vérifie sans exécuter.
- `tests/lang/test_runtime.al` : le cas `1 + "a"` passe par une valeur non typée (le littéral est désormais
  refusé à la compilation).

Étape 2 (limites levées) :

- Vérification profonde de `list[T]` / `dict[K, V]` avec marquage des conteneurs (écritures contrôlées,
  coût amorti O(1)).
- Débordements des entiers dimensionnés détectés à l'exécution ; conversions modulo 2^n `core.to_u8…` ;
  mélange de tailles refusé à la compilation.
- Champs annotés vérifiés à chaque affectation (opcode `DECLARE_FIELD_TYPE`).
- Stdlib partiellement annotée (`string`, `math`, `path`, `json.stringify`) ; appels `module.f()` vérifiés.
- Le vérificateur suit maintenant la VM : `list + list`, `str * int`, `str % x` sont refusés (non supportés).
- Tests adaptés là où ils passaient volontairement un littéral de mauvais type à une fonction désormais
  annotée (`test_string_chr_ord_slice.al`, `test_path.al`) : la valeur passe par une fonction non typée.

Tests : 17 binaires C++ (lexer +2, parser +8, bc +1 vérifications), 53 programmes `.al`, `make test-types`,
`test-trace`, `test-standalone`, `test-dict-order` ; build sans avertissement.
