# Fonctions imbriquées, lambdas et fermetures

Une **fermeture** est une fonction qui garde l'accès aux variables de la fonction qui l'a créée, même
après le retour de celle-ci. ALEX en a deux formes : la `func` déclarée dans une fonction (ou un bloc) et la
**lambda** (fonction anonyme).

## Syntaxe

```
add  := (a, b) => a + b          # paramètres entre parenthèses
sq   := x => x * x               # un seul paramètre, sans parenthèses
k    := func(x) => x + 100       # avec le mot-clé func, sans nom
zero := () => 7                  # aucun paramètre
f    := (x, y = 10) => x + y     # valeurs par défaut, comme pour une func
r    := (x => x * 2)(21)         # appel immédiat
```

- Le corps d'une lambda est **une expression** : c'est la valeur renvoyée. Il s'étend aussi loin que possible
  (`n => "neg" if n < 0 else "pos"`) et s'arrête à `,` ou `)`.
- Une lambda ne contient pas d'instruction (pas d'affectation, pas de `return`). Pour modifier une variable
  englobante, utiliser une `func` imbriquée.
- `(x)` et `(x, y)` gardent leur sens de groupement et de tuple : seul un `=>` après la parenthèse fermante
  en fait une liste de paramètres.
- Une lambda est une **valeur** : chaque évaluation de l'expression crée une nouvelle fermeture
  (`f := x => x ; g := x => x ; f == g` vaut `false`). Elle s'affiche `<function <lambda>>`.

## Sémantique

**Capture par référence.** Une fermeture ne copie pas les variables : elle partage les variables elles-mêmes.

```
func make_counter():
    n := 0
    func inc():
        n = n + 1
        return n
    return inc

a := make_counter()
b := make_counter()
a()  a()                         # a() vaut 2 ; b() vaudra 1 : chaque appel de make_counter() a SON n
```

Deux fermetures qui capturent la même variable la voient changer l'une pour l'autre, et la fonction englobante
voit aussi les écritures des fermetures.

**Une variable par itération.** Une variable de boucle (`for`) ou déclarée dans le corps d'un bloc est
recréée à chaque passage : les fermetures créées dans la boucle gardent chacune la valeur de leur itération.

```
fs := []
for i in 0..3:
    append(fs, () => i * 10)     # fs[0]() = 0, fs[1]() = 10, fs[2]() = 20
```

**Hissage.** Les `func` d'un bloc sont créées en tête de ce bloc : on peut les appeler avant leur déclaration
et elles peuvent se rappeler mutuellement. Une fonction hissée peut capturer une variable déclarée plus bas dans
le bloc ; si elle est appelée **avant** que cette variable soit déclarée, la lecture lève une `NameError`
(« variable utilisée avant sa déclaration ») au lieu de renvoyer `null`.
Une lambda, elle, est une expression : elle ne voit que ce qui est déclaré avant elle.

**Portée.** Une fonction imbriquée est locale à son bloc (comme l'analyseur l'imposait déjà) : deux fonctions
peuvent chacune avoir leur `helper` sans collision. Les variables globales ne sont pas capturées : elles sont
lues et écrites directement.

**`self` et `super`.** Une lambda ou une `func` imbriquée dans une méthode capture `self` ; `super.m()` y fonctionne.

**`catch` et `match`.** L'erreur d'un `catch e:` et les liaisons d'un motif de `match` peuvent être capturées ;
chaque passage garde sa propre valeur. Le nom de l'exception n'est visible que dans le corps du `catch`.

## Écarts et limites à connaître

- Si le nom d'une variable de boucle est capturé, **modifier cette variable dans le corps ne change plus le
  compteur de la boucle** (elle est copiée dans une cellule fraîche à chaque tour). Sans capture, comportement inchangé.
- Dans un bloc, une variable capturée par une `func` hissée et **masquant** une variable englobante de même nom
  n'est visible du code séquentiel qu'à partir de sa déclaration ; avant, c'est la variable englobante qui est lue.
- La détection des variables capturées se fait **par nom** et est volontairement prudente : une variable dont le
  nom apparaît dans une fonction imbriquée est boxée même si elle y est masquée. Cela coûte une indirection,
  jamais une erreur.
- Les fonctions ordinaires (sans fermeture) ne changent pas : leur bytecode est identique à celui d'avant.

## Implémentation

| Étage | Rôle |
|---|---|
| Parseur | trois écritures → un nœud `LambdaExpr` enveloppant un `FunctionDecl` synthétique (`<lambda>`, corps `{ return expr }`) ; `parenthesizedArrowAhead()` distingue `(a, b) =>` d'un groupement |
| Analyseur | une lambda est analysée sur place comme une fonction imbriquée : la capture lexicale est la résolution de noms existante |
| Compilateur | `CaptureScanner` repère par nom les variables référencées dans les fonctions imbriquées ; celles-là sont **boxées** (le slot contient une cellule). `resolveUpvalue` relie une variable libre à la variable du parent (ou, à travers les fonctions intermédiaires, à ses captures). `predeclareBlock` hisse cellules et fonctions en tête de bloc |
| Bytecode | 6 opcodes ajoutés à la fin de l'énumération (les anciens ne changent pas de numéro) |
| VM | `MAKE_CLOSURE` copie le modèle de la fonction (publié sous un nom unique) et lui attache le tuple de cellules ; `CALL` le recopie dans `Frame.closureEnv` |
| GC | `ObjCell` est marquée avec sa valeur ; `closureEnv` d'une fonction est déjà marqué |

### Opcodes

| Opcode | Pile | Effet |
|---|---|---|
| `NEW_CELL a` | `[v] → []` | crée dans le slot `a` une cellule fraîche contenant `v` |
| `NEW_CELL_EMPTY a` | `[] → []` | cellule « non initialisée » (cellules pré-créées en tête de bloc) |
| `CELL_GET` | `[cell] → [v]` | lit ; `NameError` si la cellule n'est pas initialisée |
| `CELL_SET` | `[v, cell] → []` | écrit et marque la cellule initialisée |
| `UPVALUE_CELL a` | `[] → [cell]` | empile la cellule brute n°`a` de la fermeture courante |
| `MAKE_CLOSURE a b` | `[c1..cb] → [fn]` | `a` = constante STRING (nom unique de la fonction), `b` = nombre de captures |

`LOAD_LOCAL` sur un slot boxé empile la cellule brute : c'est ainsi qu'une fermeture reçoit les cellules à capturer.
Les noms uniques ont la forme `nom@ligne:col#n` (préfixés du qualificatif de module) et ne sont jamais des
identifiants valides ; l'affichage (`<function inc>`) et les messages d'arité en retirent le suffixe.

## Tests

`make test-closures` (`tests/lang/test_closures.al`, 58 vérifications), plus les cas lambda de `test-parser`,
`test-analyzer`, `test-compiler` (comportement et bytecode), `test-bc` (opcodes) et `test-gc` (cellules et cycles).
