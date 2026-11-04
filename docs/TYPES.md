# Types graduels (phase 2)

Les annotations sont **facultatives**. Ce qui n'est pas annoté est `any` et se comporte exactement comme
avant ; ce qui est annoté est vérifié à la compilation **et** à l'exécution.

```alex
struct Point:
    x: int := 0
    func init(x: int):
        self.x = x

func find(names: list[str], who: str) -> int?:
    i: int := 0
    for n in names:
        if n == who:
            return i
        i += 1
    return null

const LIMIT: u16 := 1000
handler: func(int) -> bool := (n) => n > 0
```

`alexc check app.al` vérifie un programme (syntaxe, noms, types, modules importés) sans l'exécuter.

## Syntaxe

| Où | Forme |
|---|---|
| Paramètre | `nom: T` ou `nom: T = défaut` |
| Retour | `func f(...) -> T:` |
| Variable / champ | `nom: T := valeur` |
| Constante | `const NOM: T := valeur` |

Types : `any`, `int` (= `i64`), `float` (= `f64`), `f32`, `bool`, `str`, `char`, `byte`, `null`,
`i8 i16 i32 u8 u16 u32 u64`, `list[T]`, `dict[K, V]`, `tuple`, `future`, `func(T1, T2) -> R`, et les noms de
`struct`, `class`, `interface`, `enum` (locaux ou importés). `T?` accepte aussi `null`.

## Règles statiques

- `any` est compatible avec tout, dans les deux sens. **Une variable déclarée sans annotation (`x := …`) est
  `any`** : le code existant n'est jamais contraint. Une constante non annotée prend le type de sa valeur.
- `int` et les entiers dimensionnés sont acceptés là où un `float` est attendu (la valeur reste entière).
- Entiers dimensionnés : un littéral hors bornes est une erreur (`o: u8 := 300`) ; un dimensionné vers un
  plus petit (`i32` → `u8`) est refusé ; un `int` non littéral est accepté et **borné à l'exécution**.
- `T?` n'est pas assignable à `T` ; opérations, accès membre et indexation sur un `T?` sont refusés.
- Sous-classes et classes implémentant une interface sont acceptées pour le type parent.
- `list[A]` est accepté pour `list[B]` si `A` l'est pour `B` (covariance, comme TypeScript).
- Opérateurs : `int + str`, `~float`, comparaison `str < int`, etc. sont refusés quand les deux types sont
  connus — y compris dans du code non annoté (`1 + "a"` en littéral).
- Appels contrôlés : fonctions du module et importées (signatures typées dans le cache `.meta`),
  constructeurs (`init`), méthodes d'une valeur dont la classe est connue.
- Toutes les erreurs sont signalées d'un coup (`TypeCheckError`, une ligne par erreur).

## Entiers dimensionnés

- `u8 + int`, `u8 + u8` → `u8` ; `u8 + i32` est refusé (`convertir explicitement`). `/` donne un `float`.
- Tout résultat arithmétique dimensionné est **borné à l'exécution** : un débordement lève `TypeError`
  (`débordement de u8 : … obtenu int 260 (hors bornes 0..255)`), comme Swift ou Rust en mode debug.
- Arithmétique modulaire **explicite** : `to_i8 to_i16 to_i32 to_u8 to_u16 to_u32 to_u64` (module `core`)
  réduisent modulo 2^n (complément à deux pour les signés) : `to_u8(260) == 4`, `to_i8(200) == -56`.
- Dans la VM, toutes les valeurs restent des `int64` (`u64` est donc limité à 0..2^63-1) ; la représentation
  compacte (1, 2, 4 octets) relève du futur backend natif, pas d'une limite de vérification.

## Vérifications à l'exécution

Le compilateur émet `CHECK_TYPE` à l'entrée d'une fonction (paramètres annotés), à chaque retour (y compris
le `null` implicite de fin de fonction), à la déclaration et à chaque réaffectation d'une variable annotée,
et après chaque opération sur entiers dimensionnés. Les champs annotés d'une `struct`/`class`
(`balance: int := 0`) sont vérifiés à **chaque** `obj.champ = valeur`, même depuis du code non typé ; un champ
non déclaré reste libre.

**Conteneurs : vérification profonde, puis réifiée.** La première fois qu'une liste (ou un dict) traverse une
annotation `list[T]` (`dict[K, V]`), tous ses éléments sont vérifiés, récursivement pour `list[list[int]]`.
La liste est alors **marquée** de son type d'éléments : les traversées suivantes coûtent O(1), et toute
écriture ultérieure (`l[i] = v`, `append`, `insert`, `d[k] = v`, `set`) est contrôlée, d'où qu'elle vienne —
comme les tableaux Java. Conséquence assumée : une liste non typée qui a traversé `list[int]` n'accepte plus
que des `int`. Une liste marquée `int` est acceptée pour `list[float]` (lecture sûre) ; les écritures y
restent contrôlées contre `int`.

Coût mesuré : +20 à 35 % sur un `fib` récursif entièrement annoté, 15 ms pour 18 000 appels récursifs
recevant une liste de 3 000 éléments (marquage amorti), rien sur le code non annoté.

## Bibliothèque standard

Annotée là où le contrat est simple et sans changer les erreurs documentées : `string` (19 fonctions),
`math` (fonctions réelles → `float`, prédicats → `bool`, `gcd`/`lcm`/`is_even`…), `path` (10 fonctions),
`json.stringify`/`pretty` (`-> str`), conversions `core.to_u8…`. Règles suivies :

- conteneurs reçus ou rendus non paramétrés (`list`) : la stdlib ne marque jamais les listes de l'appelant ;
- fonctions polymorphes (`math.isqrt` accepte un `float` entier) ou pouvant rendre `null` (`math.sqrt(-1)`)
  sans type de retour ; fonctions dont le contrat lève une erreur métier sur un mauvais type
  (`json.parse(5)` → `JSONError`) non annotées.

Les appels `module.f(...)` (`use string`) sont vérifiés comme les appels `from module use f`.

## Limites restantes

- Pas d'inférence sur les variables non annotées (choix : compatibilité totale du code existant).
- Pas de génériques utilisateur ni de types union.
- `tuple` et `func(…) -> R` ne sont vérifiés à l'exécution que superficiellement (tuple / fonction) ; les
  `enum` ne le sont pas.

## Tests

`make test-types` : 17 diagnostics statiques attendus (`tests/lang/types_errors_fixture.al`), `alexc check`,
et `tests/lang/test_types.al` (30 vérifications : programmes typés, conteneurs, entiers dimensionnés,
champs, `TypeError` à l'exécution ; aussi sous `ALEX_GC_STRESS`).
