# Modules `argparse` et `cli`

Analyse de la ligne de commande en ALEX pur (`stdlib/argparse/`, `stdlib/cli/`) ; seul le backend
`_native_cli` (`exit`, `write_out`, `write_err`, `flush`, `text_mode`) est natif (runtime). `text_mode(false)`
passe les flux standard en binaire sous Windows (`io.stream.binary_stdio()`), sans effet ailleurs.

```
stdlib/argparse/argparse.al    façade : ArgumentParser, parser(), argument(), int_range(), set_language()
              /parser.al       moteur : Parser, groupes, groupes exclusifs, sous-commandes
              /help.al         usage, aide, métavars, coupure de lignes
              /completion.al   Bash · Zsh · PowerShell
              /manpage.al      pages de manuel roff
              /text.al         utilitaires de texte et messages (fr / en)
stdlib/cli/cli.al              App, Command : gestionnaires, codes de sortie, commandes intégrées
```

## Argparse

```alex
use argparse

p := argparse.parser(prog="tool", description="Mon outil", version="%(prog)s 1.0")
p.add_argument(["-v", "--verbose"], {"action": "count", "help": "plus de détails"})
p.add_argument("--level", {"choices": ["debug", "info"], "default": "info"})
p.add_argument("files", {"nargs": "+", "type": "path"})
args := p.parse_args()          # os.args() ; erreur => usage sur stderr, code 2 ; --help => stdout, code 0
```

**Options passées en dict** : ALEX n'accepte les arguments nommés que pour des fonctions résolues
statiquement, pas pour les méthodes. `add_argument(noms, {options})` rejette les clés inconnues
(`ArgparseConfigError`). Les fonctions du module acceptent, elles, les arguments nommés :
`argparse.parser(prog=…)`, `argparse.argument(p, noms, help=…)` (`constant=` pour l'option `"const"`,
`const` étant un mot réservé).

| Option d'`add_argument` | Valeurs |
|---|---|
| `action` | `store` `store_const` `store_true` `store_false` `append` `append_const` `extend` `count` `boolean_optional` `help` `version` |
| `nargs` | absent (1 valeur), entier ≥ 1, `"?"`, `"*"`, `"+"`, `"remainder"` |
| `type` | `"str"` `"int"` `"float"` `"bool"` `"path"` `"file"` `"dir"` ou une fonction `(texte) => valeur` |
| `choices` `default` `const` `required` `help` `metavar` `dest` `env` `hidden` `complete` `version` | comme argparse ; `env` = variable d'environnement de repli ; `complete` = `"file"`, `"dir"`, `"none"` ou liste de mots |

Sous-commandes : `sp := p.add_subparsers({"dest": "cmd"})`, `sub := sp.add_parser("add", {"aliases": ["a"], "help": "…"})`,
imbriquables à volonté. Groupes : `add_argument_group(titre, description)`,
`add_mutually_exclusive_group({"required": true})`. Résultat : un dict ; `parse_args_ex()` renvoie aussi
le chemin de sous-commande ; `parse_known_args()` renvoie `[dict, extras]`.

Syntaxes reconnues : `-x v`, `-xv`, `-x=v`, `--opt v`, `--opt=v`, grappes `-abc`, `-vvv`, abréviations
uniques de `--long` (désactivables : `allow_abbrev`), nombres négatifs, `--`.

Erreurs : `ArgparseError` (message = usage + `prog: erreur: …`, court dans `p.last_error`),
`ArgparseHelp` / `ArgparseVersion` (avec `exit_on_error=false`), `ArgparseConfigError`,
`ArgumentTypeError` (`argparse.fail(msg)` dans une fonction `type`).

### Écarts volontaires par rapport à Python

Comparé à l'argparse de Python 3.12 sur 222 analyses et 10 aides (`tools/argparse/gen_reference.py`) :
`int` strict (`[+-]chiffres`, pas de `1_0`) ; un positionnel `?`/`*` n'est pas consommé à vide avant une
option ; `-- cmd` avant la sous-commande est accepté ; le défaut d'une sous-commande l'emporte sur celui
du parent mais jamais sur une valeur explicitement donnée ; `count` vaut 0 par défaut ; option `*` sans
valeur → `[]` ; métavar des sous-commandes sans alias (`{add,rm}`) ; messages en français
(`argparse.set_language("en")` pour ceux de Python).

## Man et complétion

`p.format_man(section, date, source, manual, auteur)`, `p.man_pages(…)` (une page par commande,
`tool-add.1`) ; `p.completion("bash" | "zsh" | "powershell")`. Via `cli.App.add_builtins()` :
`prog completion bash`, `prog man`, `prog help [commande]`.

Bash et Zsh se chargent par `source <(prog completion bash)` / fichier `_prog` dans `$fpath` ; PowerShell par
`prog completion powershell | Out-String | Invoke-Expression`. Limites : positionnels complétés « en bloc »,
options à plusieurs valeurs complétées sur la première seulement.

## cli

```alex
use cli
func add(args):
    return 0                                      # entier = code de sortie ; null = 0
app := cli.App("tool", {"version": "1.0"})
c := app.command("add", add, {"aliases": ["a"]})
c.argument("paths", {"nargs": "+"})
app.add_builtins()
app.main()                                        # run() puis exit(code)
```
Une exception du gestionnaire → `prog: erreur: …` sur stderr, code 1 (`catch_errors=false` pour la laisser
remonter) ; groupe de commandes sans sous-commande → aide, code 2.

## Tests et validation

`make test-argparse` : 561 vérifications. Bash est exécuté pour de vrai ; Zsh est vérifié par `zsh -n` et
l'enregistrement `compdef` ; les pages passent `groff -ww` ; **PowerShell n'est contrôlé que
structurellement (non exécuté)**. Sous-processus : `ALEX_BIN` désigne le binaire (défaut `./alex`).
