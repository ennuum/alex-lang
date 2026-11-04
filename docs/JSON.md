# JSON — `stdlib/json/json.al`

Analyse et sérialisation JSON (RFC 8259) en **ALEX pur** : aucune primitive native (seul `load`/`save` passent par `io`).

```
use json

v := json.parse("{\"nom\": \"Alex\", \"tags\": [1, 2.5, true, null]}")
print(v["tags"][1])             # 2.5
print(json.stringify(v))        # {"nom":"Alex","tags":[1,2.5,true,null]}
print(json.pretty(v))           # indenté de 2 espaces
```

## API

| Appel | Sens |
|---|---|
| `json.parse(texte)` | texte → valeur ALEX ; lève `JSONError` si invalide |
| `json.is_valid(texte)` | `true` si `parse` réussirait |
| `json.stringify(v, indent=null, sort_keys=true)` | valeur → texte ; `indent=n` : `n` espaces par niveau |
| `json.pretty(v, indent=2)` | `stringify` indenté |
| `json.load(chemin)` / `json.save(chemin, v, indent=2)` | lecture / écriture de fichier |

## Types

`null↔null`, `true/false↔bool`, entier↔`int`, nombre avec fraction ou exposant↔`float`, chaîne↔`str`,
tableau↔`list` (un `tuple` s'écrit comme un tableau), objet↔`dict`.

## Erreurs

Toujours `JSONError`. `parse` indique la position : `caractère inattendu 'o' (ligne 2, colonne 3)`.
`stringify` refuse : clés non `str`, `nan`/`inf`, fonctions et instances, profondeur ≥ 100 (détecte aussi les
structures cycliques), `parse` refuse aussi la profondeur ≥ 100.

## Unicode

`\uXXXX` est décodé pour tout Unicode grâce à `string.chr`, paires de substitution UTF-16 comprises
(`\ud83d\ude00` → `😀`) ; `\b` et `\f` sont acceptés. Une moitié de paire isolée est refusée (`JSONError`).
`stringify` échappe les caractères de contrôle : `\n \t \r \b \f`, les autres en `\u00XX`.
Le texte UTF-8 brut est conservé tel quel.

## Limites connues

- `stringify` n'a pas d'option « ASCII seulement ».
- Les dicts itèrent dans l'ordre d'insertion. `stringify` trie les clés par défaut (sortie stable) ; `sort_keys=false` conserve l'ordre d'insertion. `parse` conserve l'ordre du texte.
- `str(float)` du runtime garde 15 chiffres significatifs : l'aller-retour des flottants n'est pas toujours exact.

Tests : `make test-json`. Exemple : `examples/json_demo.al`.
