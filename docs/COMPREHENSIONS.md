# Compréhensions de liste et de dictionnaire

Une compréhension est une **expression** qui construit une collection neuve à partir d'un ou plusieurs itérables.

```
squares := [x * x for x in 0..10]                    # [0, 1, 4, ..., 81]
evens   := [x for x in xs if x % 2 == 0]             # filtre
pairs   := [(a, b) for a in 0..3 for b in a..3]      # clauses imbriquées
index   := {name: i for i in 0..len(names)}          # dict ; {clé: valeur for ...}
```

Les clauses peuvent s'écrire sur plusieurs lignes (les délimiteurs ouverts suppriment les fins de ligne) :

```
odds := [
    v * 2
    for v in 0..10
    if v % 2 == 1
]
```

## Grammaire (EBNF)

```
list_literal   = "[" [ expression { "," expression } ] "]"
               | "[" expression comp_clauses "]" ;
dict_literal   = "{" [ entry { "," entry } ] "}"
               | "{" expression ":" expression comp_clauses "}" ;
comp_clauses   = for_clause { for_clause | if_clause } ;
for_clause     = "for" IDENTIFIER "in" range_operand ;
if_clause      = "if" or_expression ;
range_operand  = or_expression [ ".." or_expression ] ;
```

`range_operand` et `if_clause` excluent volontairement la forme `x if c else y` : dans une compréhension, un `if`
après un itérable ouvre un filtre. Pour utiliser une expression conditionnelle dans un itérable ou un filtre,
parenthésez-la. Dans l'**élément** (`[a if a > 0 else 0 for a in xs]`) elle est libre.

## Sémantique

- **Équivalence.** `[e for x in a if c]` se comporte comme
  `res := []` / `for x in a:` / `if c:` / `append(res, e)`. Chaque clause `for` ouvre une boucle, chaque `if`
  filtre ce qui suit, de gauche à droite. Le dict suit la même règle avec `res[k] = v` : une clé répétée
  **écrase** la précédente.
- **Itérables.** Exactement ceux de l'instruction `for` : intervalle `a..b`, liste, tuple, chaîne (un `Char` par
  tour), dict (ses clés). La forme `{k: v for k, v in ...}` n'existe pas : le `for` n'a qu'un identifiant (§18) ;
  utilisez `items(d)` et `p[0]` / `p[1]`.
- **Portée.** La variable d'une clause `for` n'est visible que des clauses suivantes et de l'élément ; elle ne fuit
  pas et masque une variable homonyme englobante. L'itérable d'une clause est évalué **avant** que sa variable
  existe : `[x for x in x]` et `[i for i in i..n]` lisent le `x` / `i` englobant.
- **Évaluation.** Chaque itérable est évalué une fois par entrée dans sa boucle ; le filtre précède l'élément, qui
  n'est pas évalué quand le filtre est faux. Chaque évaluation produit une collection neuve.
- **Fermetures.** Une variable fraîche par tour : `[() => i for i in 0..3]` donne trois fonctions qui
  retournent 0, 1, 2. `self` est disponible dans une méthode.
- **Erreurs.** Une exception levée dans l'itérable, le filtre ou l'élément se propage normalement.
- **Pas d'ensemble ni de générateur** : Alex n'a ni `set` ni générateur ; `{x for x in xs}` est refusé avec un
  message qui renvoie à la forme `{clé: valeur for ...}`.

## Implémentation

| Étape | Fichier | Détail |
|---|---|---|
| AST | `include/alex/ast/Ast.hpp`, `src/Ast.cpp` | `ComprehensionExpr` (`List` ou `Dict`, suite de `CompClause`) ; rendu `ListComp` / `DictComp` |
| Parseur | `src/Parser.cpp` | `parseRangeOperand()` (extrait de `parseConditional()`), `parseComprehensionClauses()` |
| Analyse | `src/Analyzer.cpp` | un scope par clause `for`, itérable analysé avant sa variable |
| Compilation | `src/Compiler.cpp` | `genComprehension` / `genCompClauses` |

La compilation est **en ligne** : le résultat vit dans un local temporaire, l'ajout utilise `LIST_APPEND` et
`SET_INDEX`. Aucun nouvel opcode, aucune fonction synthétique : les `.albc` existants restent valides, `self`
et la capture fonctionnent sans mécanisme supplémentaire, et il n'y a pas de coût d'appel.

L'instruction `for` et les compréhensions partagent `genForLoop` : une seule implémentation de l'itération.
Au passage, `for i in i..n` évalue maintenant ses bornes avant de déclarer `i` (avant : il lisait la variable de
boucle non initialisée). Les slots alloués sont inchangés, donc le bytecode des boucles existantes aussi.

## Tests

`make test-comprehensions` (54 vérifications, `tests/lang/test_comprehensions.al`), plus les cas ajoutés à
`tests/test_parser.cpp` (AST et erreurs de syntaxe) et `tests/test_analyzer.cpp` (portée).

## Limites connues

- Pas de déstructuration dans l'en-tête `for` (ni dans les compréhensions) : à traiter d'abord dans l'instruction
  `for`, puis les compréhensions en hériteront via `genForLoop`.
- Une lambda dont le corps est une compréhension est une fonction comme une autre (nouvelle portée de variables).
