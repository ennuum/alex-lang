# Bibliothèque scientifique ALEX

Modules 100 % ALEX pur (aucun code natif C++), organisés selon la feuille de route `Les_modules_Alex.docx`.
Chaque module est un fichier `stdlib/<nom>/<nom>.al` : il suffit de le déposer pour que `use <nom>` fonctionne.

## État d'avancement

| Phase | Module | État | Tests |
|---|---|---|---|
| 1 | `math` | livré (exp/sin/cos/tan à ~1 ulp) | `examples/math_test_suite.al` (1573) |
| 1 | `constants` | **livré** | `tests/test_constants.al` (55) |
| 1 | `complex` | **livré** | `tests/test_complex.al` (285) |
| 1 | `units` | **livré** | `tests/test_units.al` (186) |
| 1 | `random` | **livré** | `tests/test_random.al` (97) |
| — | intégration Phase 1 | **livré** | `tests/test_science_integration.al` (25) |
| 2 | `array` | **livré** | `tests/test_array.al` (320) |
| 2 | `linalg` | **livré** | `tests/test_linalg.al` (322) |
| 2 | `stats` | **livré** | `tests/test_stats.al` (388) |
| 2 | `numeric` | **livré** | `tests/test_numeric.al` (299) |
| 2 | `calculus` | **livré** | `tests/test_calculus.al` (200) |
| — | intégration Phase 2 | **livré** | `tests/test_science2_integration.al` (42) |
| 3 | `physics`, `chemistry`, `geometry`, `ode`, `optim` | à faire | |
| 4 | `plot`, `signal`, `image`, `symbolic`, `ml` | à faire | |

Lancer la Phase 1 : `make test-sci` ; la Phase 2 : `make test-sci2` (≈ 3 s) ; ou `./alex run tests/test_<module>.al` depuis la racine du projet.

> Note : `make test-sci` référence `tests/test_complex.al` et `tests/test_random.al`, absents de l'archive `Alex_OOP.zip`
> (les modules `complex` et `random` existent). À restaurer pour que la cible passe de bout en bout.

## Les modules de la Phase 1

### `constants`
Constantes mathématiques (`PI`, `TAU`, `E`, `PHI`, `EULER_GAMMA`, `SQRT2`, `CATALAN`, ...) et physiques en unités SI.
Valeurs **exactes** du SI 2019 (`C`, `H`, `E_CHARGE`, `K_B`, `N_A`, `G0`, `ATM`, `AU`, ...), constantes **dérivées calculées**
(`HBAR`, `R_GAS`, `F_FARADAY`, `SIGMA_SB`, `WIEN_B`, `PARSEC`), valeurs **mesurées** CODATA 2018 (`G`, `EPS0`, `MU0`, `M_E`, `M_P`,
`M_N`, `AMU`, `ALPHA`, `RYDBERG`, `BOHR_RADIUS`, ...). `lookup(nom)` renvoie `[valeur, unité, incertitude relative, description]`
(insensible à la casse), `value(nom)` la valeur seule, `names()` la liste des noms. Les unités de la table sont valides pour `units`.

### `complex`
Complexe = liste `[re, im]`. Fonctions libres : `new`, `from_polar`, `re`, `im`, `add`, `sub`, `mul`, `div` (algorithme de Smith),
`neg`, `conj`, `inv`, `scale`, `abs`, `abs2`, `arg`, `polar`, `exp`, `ln`, `log`, `sqrt`, `pow`, `pow_int`, `nth_roots`,
`roots_of_unity`, `sin/cos/tan`, `sinh/cosh/tanh`, `asin/acos/atan`, `asinh/acosh/atanh`, `sum`, `prod`, `is_close`, `to_string`.
Validé contre `cmath` (erreur relative ≤ 5e-15). Les arguments réels (int/float) sont acceptés partout.

### `units`
Analyse dimensionnelle sur 7 dimensions SI. `convert(v, "km/h", "m/s")`, `convert(100, "degC", "degF")`, expressions composées
(`J/(mol*K)`, `kg m^-1 s^-2`), préfixes SI de `y` à `Y`, ~95 unités (SI, impériales, énergie, pression, angle, volume, ...).
`dimension`, `dimension_name`, `compatible`, `is_unit`, `parse`, `convert_all`, `list_units`. Grandeurs `[valeur SI, dimensions,
unité d'affichage]` : `quantity`, `q_add/q_sub/q_mul/q_div/q_pow/q_scale/q_neg`, `q_to`, `q_in`, `q_cmp`, `q_is_close`, `q_str`.
Les unités à décalage (°C, °F) servent à créer/convertir, pas à l'arithmétique (refusée explicitement).

### `random`
xoshiro128** (période 2^128 − 1), arithmétique 32 bits uniquement, séquence validée **bit à bit** contre l'implémentation de
référence. `new`, `seed`, `copy`, `jump`, `spawn`, `next_u32`, `random`, `getrandbits`, `randbelow`, `randint`, `randrange`,
`uniform`, `normal`, `lognormal`, `exponential`, `gamma`, `beta`, `chi_square`, `student_t`, `laplace`, `weibull`, `bernoulli`,
`geometric`, `poisson`, `binomial`, `choice`, `choices`, `shuffle`, `permutation`, `sample`, `weighted_choice`, `monte_carlo`,
`integrate`, `estimate_pi`. Le générateur est toujours le **dernier** paramètre (`null` = générateur global). Non cryptographique.

## Les modules de la Phase 2

Ordre de dépendance : `array` → `linalg` → `stats`, `numeric` → `calculus`. Tous les tests comparent à NumPy / SciPy / SymPy
(générateurs dans `tools/sci/tests/`), sans jamais utiliser le module testé comme référence.

### `array`
Tableaux N-dimensionnels : classe `Array` (`.shape`, `.data` plat en ordre C) avec méthodes (`a.add(b)`, `a.reshape(...)`, `a.sum(0)`).
Construction (`from_list`, `zeros`, `ones`, `full`, `arange`, `linspace`, `logspace`, `eye`, `diag`, `meshgrid`), accès (`get/set/at/put`, indices
négatifs), forme (`reshape` avec -1, `transpose` d'axes, `swapaxes`, `squeeze`, `expand_dims`, `broadcast_to`, `slice_axis` à pas négatif,
`select`, `flip`, `concatenate`, `stack`, `vstack`, `hstack`), opérations avec **broadcasting** NumPy, comparaisons, `where`, `isclose`,
réductions par axe (`sum` compensée de Neumaier, `prod`, `min`, `max`, `mean`, `argmin`, `argmax`, `cumsum`, `cumprod`, `any`, `all`),
`matmul`/`dot`/`outer`/`trace`, tri stable O(n log n) (`sort`, `argsort`, `unique`, `searchsorted`, `diff`).
`array.wrap(shape, data)` construit sans copie (réservé aux modules frères).

### `linalg`
LU à pivot partiel (`lu_factor` → classe `LU` réutilisable : `.solve`, `.det`, `.inv`), `solve`, `det`, `slogdet`, `inv`, `solve_triangular`,
`solve_tridiagonal` (Thomas, O(n)), `cholesky`, `qr` (Householder, réduit/complet), `eigh` (Jacobi), `eigvals`/`eig` (Hessenberg + QR de Francis),
`svd`/`svdvals` (Jacobi unilatérale, précision relative élevée), `rank`, `pinv`, `lstsq`, `cond`, `null_space`, `cg`, `norm`, `expm` (Padé 13),
`matrix_power`, `kron`, `cross`, `tril`/`triu`, `normalize`/`project`/`angle`. Les signes des vecteurs propres/singuliers sont arbitraires.

### `stats`
Descriptives (`mean`, `median`, `mode`, `var`/`std` avec `ddof`, `skew`, `kurtosis`, `quantile` type 7, `iqr`, `mad`, `zscore`, `rankdata`,
`histogram`, `describe`), corrélation (`corr`, `spearman`, `kendall`, `cov_matrix`, `corr_matrix`), fonctions spéciales (`gammainc`, `gammaincc`,
`betainc`), **lois** `norm`, `t`, `chi2`, `f`, `gamma`, `beta`, `expon`, `uniform`, `binom`, `poisson`, `geom` (`_pdf/_pmf`, `_cdf`, `_sf`, `_ppf`),
tests (`ttest_1samp/ind/rel`, `chisquare`, `chi2_contingency`, `f_oneway`, `pearsonr`, `mean_confidence_interval`), régression (`linregress`, `ols`).

### `numeric`
Polynômes (`polyfit` conditionné, `polyval`, `polyder`, `polyint`, `polyadd`, `polymul`, `polyroots` par matrice compagnon), interpolation (`interp`,
`lagrange` barycentrique, `CubicSpline` « not-a-knot »/naturelle/serrée avec dérivées et intégrale), racines (`bisect`, `brentq`, `newton`, `secant`,
`fixed_point` avec Aitken), intégration (`quad` Gauss-Kronrod 15 adaptative avec bornes infinies, `gauss_legendre`, `romberg`, `trapz`, `cumtrapz`,
`simpson`). Les fonctions sont passées par nom ; les paramètres via `args` (voir ci-dessous).

### `calculus`
Dérivées par différences centrées + extrapolation de Richardson avec erreur estimée (`derivative`, `derivative_err`, `second_derivative`, `derivative_n`),
`gradient`, `jacobian`, `hessian`, `directional_derivative`, `divergence`, `curl`, `laplacian`, intégrales multiples (`dblquad`, `tplquad` à bornes
fonctions des variables extérieures, `line_integral`), `newton_system` / `fsolve` (Newton amorti, jacobienne numérique ou analytique).

### Paramètres des fonctions passées en argument
Une « fonction » passée en argument est une fonction nommée `f(x)` ou `f(x, p)`, **ou une lambda / fermeture** (`x => x * x`, voir
`docs/CLOSURES.md`). `args=p` est transmis comme second argument à une fonction nommée ; avec une fermeture, il est inutile : les
paramètres sont capturés (`make_poly(a, b)` renvoie `x => a * x * x + b`, que l'on passe telle quelle à `numeric.quad`).
Fonctions de plusieurs variables : elles reçoivent une liste `[x1, ..., xn]`.

## Conventions pour écrire un module scientifique

1. **Un fichier = un module** : `stdlib/<nom>/<nom>.al`, nom en minuscules, sans préfixe `alex.` (le préfixe de la feuille de route
   est un espace de noms logique : on écrit `use complex`).
2. **En-tête documenté** : but, exemple d'usage, représentation des données, conventions (branches, erreurs), limites.
3. **Données** : les `struct` et `enum` sont exportables entre fichiers (`from m use Vec` ou `m.Vec(...)`). Les modules de la Phase 1
   (`complex` : `[re, im]`) gardent des listes pour rester compatibles ; les modules de la Phase 2 (`array`, `linalg`...) peuvent
   utiliser des `struct` avec méthodes. Le langage ne surcharge toujours pas les opérateurs (`+`, `*`) : on écrit `a.add(b)`.
4. **Pure** : une fonction renvoie un nouveau résultat et ne modifie pas ses arguments, sauf si son nom/sa doc l'annonce
   (`shuffle`, `seed`).
5. **Erreurs typées** avec `raise("ValueError" | "TypeError" | "ZeroDivisionError" | "IndexError", message en français)`.
6. **Paramètres optionnels par défaut** (`f(a, b=2.0, g=null)`) ; l'argument « générateur / contexte » en dernier.
7. **Précision** : viser 1 ulp là où c'est possible, documenter sinon ; comparer à une référence indépendante (Python/`mpmath`)
   dans les tests, jamais à une valeur obtenue avec le module lui-même.
8. **Tests** dans `tests/test_<module>.al`, un test par comportement + cas limites + cas d'erreur, code de sortie ≠ 0 en échec.
9. **Données générées** (constantes, registres) : script dans `tools/sci/`, sortie jamais éditée à la main.

## Contraintes du langage à connaître (constatées à l'usage)

Levées : ordre des fonctions (hissage, récursion mutuelle), `struct`/`enum` exportés, arguments nommés vers une cible importée
(`random.normal(sigma=2.0, g=g)`). Voir la fin du `README.md`. Restent :

- Pas de `*args`, de `finally`, de compréhension, de tranche `l[a:b]`,
  d'index négatif, de déstructuration (`a, b := ...`), d'échange `a, b = b, a`, de comparaison chaînée.
- Pas de notation exponentielle (`1e-5`) : écrire `0.00001`. Pas de littéral `inf`/`nan` : `INF := 10.0 ** 400`, `NAN := INF - INF`.
- `liste + liste`, `str * int` : TypeError ; utiliser `collections.append` et `string.repeat`.
- `x in d` n'est pas utilisable comme expression ni dans un `if` : tester avec `try/catch` sur `d[k]`.
- Les entiers sont sur 64 bits avec bouclage silencieux (complément à deux) ; `>>` est arithmétique.
- `print` affiche 15 chiffres significatifs : comparer avec une tolérance, pas avec `==`.
- Un nom global ne peut pas être aussi un module importé (`stats := ...` après `use stats` : DuplicateBindingError) ; `:=` ne redéclare pas une variable du même scope.
- Pas de `range` : utiliser `while`. Performance : ≈ 4 M d'opérations simples/s, ≈ 6 µs par appel de fonction élémentaire.
