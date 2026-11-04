# ALEX « à la Python / C++ » — fonctionnalités de confort

Tests : `make test-pythonic` (`tests/lang/test_pythonic.al`) et `make test-builtins` (`tests/lang/test_builtins.al`).

## Opérateurs et expressions

| Fonctionnalité | Exemple |
|---|---|
| `in` / `not in` (list, tuple, str, dict, instances) | `3 in xs`, `"a" not in s` |
| comparaisons chaînées | `0 < x <= 10` (l'opérande du milieu ne doit pas contenir d'appel) |
| indices négatifs | `xs[-1]`, `s[-2]` |
| tranches `[a:b:c]` | `xs[1:]`, `s[::-1]`, `xs[:-1]` |
| `+` / `*` sur séquences | `[1] + [2]`, `"ab" * 3`, `[0] * n` |
| flottants à exposant | `1e3`, `2.5E-4` |
| déstructuration | `a, b = b, a`, `first, *rest = xs`, `for i, x in enumerate(xs)` |
| `return a, b` (tuple) | `q, r = divmod(7, 2)` |
| chaînes multi-lignes | `"""..."""` et `f"""..."""` |
| ensembles | `{1, 2}`, `{x for x in it}`, `set([..])`, `\| & - ^ <= >=` |
| spread | `f(*xs)`, `[0, *xs]`, `(*a, *b)`, `{**d, "k": 1}` |

## Instructions

`assert cond, "message"` · `del d[k]` / `del xs[i]` · `pass` · `for … else` / `while … else`
(le `else` s'exécute si la boucle finit sans `break`) · `with ressource as r:` (appelle `__enter__`,
puis `__exit__(null, null, null)` dans un `finally`) · décorateurs `@dec` avant un `func`
(`f = dec(f)`, empilables).

## Fonctions

* paramètres variadiques : `func f(a, b = 1, *rest)` — `rest` est une liste. Les arguments nommés ne
  sont pas combinables avec un paramètre variadique.
* méthodes d'extension de types natifs : `extend list:` + `func …` (le receveur est `self`).

## Surcharge d'opérateurs (classes / structs)

`__add__ __sub__ __mul__ __truediv__ __floordiv__ __mod__ __pow__` (+ réfléchies `__radd__` …),
`__and__ __or__ __xor__ __lshift__ __rshift__`, `__eq__` (`!=` en est déduit, ou `__ne__`),
`__lt__ __le__ __gt__ __ge__`, `__neg__ __pos__`, `__contains__`, `__getitem__` (aussi utilisé par
`for` : lever `IndexError` à la fin), `__setitem__`, `__len__` (`len(x)`), `__str__` (`print`, `str`,
f-strings), `__call__`.

## Builtins implicites (sans import)

Le compilateur ajoute `from core use …` / `from builtins use …` pour les noms qu'un module utilisateur
emploie sans les déclarer (une définition locale gagne toujours ; les modules de la stdlib ne sont pas
concernés ; un programme qui n'emploie aucun builtin garde un bytecode identique).

* fonctions : `len type hash all any abs min max sum sorted reversed enumerate zip map filter range round
  divmod pow chr ord int float bool list tuple dict set`
* `list` : `append extend insert pop remove index count sort reverse clear copy`
* `dict` : `keys values items get set pop update setdefault copy clear`
* `str` : `upper lower strip lstrip rstrip split join replace startswith endswith find count capitalize
  title isdigit isalpha isspace zfill ljust rjust center`

Limites connues : les arguments nommés ne sont acceptés que vers une fonction connue statiquement
(`sorted(xs, key=f, reverse=true)` oui, `xs.sort(key=f)` non → `xs.sort(f, true)`) ; pas de
générateurs (`yield`), de `bytes`, ni d'entiers de précision arbitraire ; le compilateur natif
(`alexc build`) refuse `extend`, `*args`, `*`/`**` de spread et `for/while … else`.
