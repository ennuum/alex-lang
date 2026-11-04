# string — `chr`, `ord`, `slice`, fonctions d'octets

Tout travaille en **points de code Unicode** (comme `s[i]` et `core.len`), sauf les fonctions `byte_*` ci-dessous.

| Fonction | Rôle |
|---|---|
| `string.chr(code)` | `char` de point de code `code` (0..1114111, hors substituts 55296..57343), sinon `ValueError`. |
| `string.ord(c)` | Point de code d'un `char` ou d'une `str` d'un seul caractère, sinon `ValueError` / `TypeError`. |
| `string.slice(s, start=null, stop=null, step=1)` | `s[start:stop:step]` à la Python, renvoie une `str`. |

- `chr` renvoie un `char` (comme `s[i]`) : `chr(ord(c)) == c`. Utiliser `str(chr(65))` pour obtenir une `str`.
- `slice` : indices négatifs comptés depuis la fin, bornes hors limites ramenées dans la chaîne (pas d'`IndexError`,
  contrairement à `substring`), `step` négatif parcourt à l'envers (`slice(s, null, null, -1)` renverse), `step == 0` → `ValueError`.

## Octets : données binaires

Pour les protocoles réseau, les fichiers binaires et la cryptographie, une `str` peut contenir des octets
quelconques (y compris 0 et des suites qui ne sont pas de l'UTF-8). Ces fonctions comptent en **octets** et
n'interprètent rien ; elles existent dans la VM et en natif, avec les mêmes résultats.

| Fonction | Rôle |
|---|---|
| `byte_len(s)` | nombre d'octets |
| `byte_at(s, i)` | octet n° `i` (0..255) ; `IndexError` hors limites |
| `byte_slice(s, début, fin)` | octets `[début, fin)`, bornes ramenées dans la chaîne |
| `byte_find(s, sous, début=0)` | position en octets de `sous` à partir de `début`, ou -1 |
| `byte_char(n)` | chaîne d'un octet (`n & 255`) |
| `byte_pack(liste)` | chaîne dont les octets sont les entiers de la liste (chacun `& 255`) |
| `byte_unpack(s)` | liste des octets (entiers 0..255) |
| `byte_join(parties)` | concaténation en une seule allocation (temps linéaire, contrairement à `+` répété) |

Tests : `make test-string` (`tests/test_string_chr_ord_slice.al`) ; fonctions d'octets :
`tests/native/ok_bytes.al` (VM et natif comparés).
