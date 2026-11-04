# Programmation fonctionnelle — `stdlib/functional/functional.al`

Outils fonctionnels sur listes en **ALEX pur** (aucune primitive native).

```
use functional
from functional use map, filter, reduce, seq

carres := map([1, 2, 3, 4], x => x * x)                       # [1, 4, 9, 16]
somme  := reduce(filter(carres, x => x % 2 == 0), (a, b) => a + b, 0)   # 20
r := seq([5, 3, 8, 1]).filter(x => x > 2).map(x => x * 10).sort_by().to_list()   # [30, 50, 80]
```

## Conventions

- **Données d'abord**, fonction ensuite : `map(items, f)`. Pour fixer la fonction d'abord : `partial`, `Seq`.
- **Calcul immédiat** (le langage n'a pas de générateurs) ; **aucune entrée n'est modifiée**, chaque fonction renvoie une
  nouvelle liste/dict.
- `items` : `list`, `tuple` ou `str` (lue caractère par caractère, en `str` de longueur 1).
- Pas d'arguments variadiques ni d'intervalles-valeurs dans le langage : combinateurs **par arité** (`partial`/`partial2`,
  `curry2`/`curry3`) et `range_list(a, b)` à la place de `a..b` hors d'un `for`.
- Valeurs utilisées comme **clés de dict** (`group_by`, `count_by`, `frequencies`, `unique`, `unique_by`, `memoize`,
  `memoize2`, `from_pairs`) : hachables seulement (nombres, bool, str, tuples). Une `list` ou un `dict` donne `TypeError`.
- Erreurs : `TypeError` (mauvais type, fonction non appelable), `ValueError` (pas nul, taille < 1...), `IndexError`
  (`min_by`/`max_by` sur liste vide sans valeur par défaut).

## Référence

| Famille | Fonctions |
|---|---|
| Construction | `range_list(start, stop, step=1)`, `repeat(x, n)`, `iterate(f, x, n)` |
| Transformation | `map`, `filter`, `reject`, `flat_map`, `for_each`, `reduce(items, f, init)`, `fold_right`, `scan`, `sum(items, f=null)`, `prod`, `count_if` |
| Paires | `zip`, `zip_with(a, b, f)`, `unzip`, `enumerate(items, start=0)`, `pairwise` |
| Découpage | `take`, `drop`, `take_while`, `drop_while`, `split_at`, `chunk(items, n)`, `window(items, n)` |
| Recherche | `find(items, pred, default=null)`, `find_index`, `any_of`, `all_of`, `none_of`, `partition` |
| Groupement | `group_by`, `count_by`, `frequencies`, `unique`, `unique_by` |
| Tri | `sort_by(items, key=null, reverse=false)` (**stable**, O(n log n)), `sorted`, `min_by`, `max_by` (premier en cas d'égalité) |
| Listes | `reverse`, `concat`, `flatten(items, depth=1)` (`-1` : tout), `interleave`, `intersperse`, `copy_of` |
| Combinatoire | `cross(a, b)`, `combinations(items, k)`, `permutations(items)` |
| Dictionnaires | `map_values`, `filter_dict(d, (k, v) => ...)`, `from_pairs` |
| Fonctions | `compose`, `compose_all`, `pipe(value, fns)`, `pipeline(fns)`, `partial`, `partial2`, `partial_right`, `flip`, `curry2`, `curry3`, `constant`, `negate`, `tap`, `once`, `memoize`, `memoize2` |
| Chaînage | `seq(items)` → `Seq` |

## `Seq`

`seq(items)` copie la liste et renvoie un `Seq`. Les méthodes de transformation (`map`, `filter`, `reject`, `flat_map`,
`take`, `drop`, `take_while`, `drop_while`, `enumerate`, `zip`, `chunk`, `window`, `flatten`, `unique`, `sort_by`, `reverse`,
`concat`, `scan`, `tap`) renvoient un **nouveau** `Seq`. Les méthodes terminales renvoient une valeur : `to_list`, `count`,
`reduce`, `sum`, `find`, `any_of`, `all_of`, `group_by`, `min_by`, `max_by`, `first`, `last`.

## Exemples utiles

```
# mémoïsation d'une fonction récursive (la fonction s'appelle via une boîte)
box := [null]
func fib(n):
    if n < 2:
        return n
    return box[0](n - 1) + box[0](n - 2)
box[0] = functional.memoize(fib)
print(box[0](80))

# tri par plusieurs critères : les tuples ne se comparent pas avec <, mais sort_by est stable :
# trier d'abord par le critère secondaire, puis par le principal
par_nom := functional.sort_by(gens, p => p[0])
par_age_puis_nom := functional.sort_by(par_nom, p => p[1])
```

## Limites

- Pas de paresse : `map` sur 1 million d'éléments en construit la liste entière.
- `sort_by` compare avec `<` : les clés doivent être comparables entre elles (nombres entre eux, str entre eux ; les
  tuples et listes ne sont pas comparables : voir l'astuce du tri en deux passes plus haut).
- `memoize`/`memoize2` ne couvrent que 1 ou 2 arguments, sans éviction du cache.

Tests : `make test-functional`. Exemple : `examples/functional_demo.al`.
