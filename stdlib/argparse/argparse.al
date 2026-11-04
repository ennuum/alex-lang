# ALEX STANDARD LIBRARY — argparse
#
# Analyse d'arguments de ligne de commande : options courtes/longues, positionnels,
# sous-commandes imbriquées avec alias, groupes d'options, groupes mutuellement exclusifs,
# nargs (1, N, ?, *, +, remainder), types, choices, défauts/env, aide et usage automatiques,
# pages de manuel (roff) et complétion Bash / Zsh / PowerShell.
#
#   use argparse
#
#   p := argparse.parser(prog="tool", description="Mon outil", version="1.0")
#   p.add_argument(["-v", "--verbose"], {"action": "count", "help": "plus de détails"})
#   p.add_argument("--level", {"choices": ["debug", "info"], "default": "info"})
#   p.add_argument("files", {"nargs": "+", "type": "path", "help": "fichiers à traiter"})
#   args := p.parse_args()                 # os.args() ; erreur => usage sur stderr, code 2
#   print(args["verbose"], args["files"])
#
# Pourquoi un dict d'options ? ALEX ne transmet les arguments NOMMÉS qu'aux fonctions
# résolues statiquement : pas aux méthodes (p.add_argument(x, help=...) est refusé).
# add_argument(noms, {options}) vérifie les clés (une faute de frappe est une erreur).
# Les fonctions du module, elles, acceptent les arguments nommés :
#   argparse.parser(prog=..., ...)    argparse.argument(p, noms, help=..., nargs=..., ...)
#   (le paramètre `constant` de argument() correspond à l'option "const" : `const` est un mot réservé)
#
# Options d'add_argument : action nargs const default type choices required help metavar
#   dest version env hidden complete   (voir docs/ARGPARSE.md pour le détail)
#
# Résultat : un dict {dest: valeur}. parse_args_ex() ajoute le chemin de sous-commande.
# Messages en français ; argparse.set_language("en") pour ceux de Python.
#
# Erreurs : ArgparseError (usage), ArgparseHelp / ArgparseVersion (exit_on_error=false),
#           ArgparseConfigError (parseur mal configuré), ArgumentTypeError (fonction type=).

use argparse.parser as _p
from argparse.parser use Parser
use argparse.text as _t

const VERSION := "1.0.0"
const SUPPRESS := "==SUPPRESS=="

func version():
    return VERSION

# Même classe que argparse.parser.ArgumentParser, pour écrire argparse.ArgumentParser(...).
#   ArgumentParser(prog, {"description": ..., "epilog": ..., "usage": ..., "add_help": ...,
#   "version": ..., "allow_abbrev": ..., "exit_on_error": ..., "width": ...,
#   "show_defaults": ..., "raw_text": ...})
class ArgumentParser extends Parser:
    func argparse_marker():
        return true

# Fabrique à arguments nommés (retourne un ArgumentParser).
func parser(prog=null, description=null, epilog=null, usage=null, add_help=true, version=null, allow_abbrev=true, exit_on_error=true, width=null, show_defaults=false, raw_text=false):
    return ArgumentParser(prog, {"description": description, "epilog": epilog, "usage": usage, "add_help": add_help, "version": version, "allow_abbrev": allow_abbrev, "exit_on_error": exit_on_error, "width": width, "show_defaults": show_defaults, "raw_text": raw_text})

# add_argument avec arguments nommés : argparse.argument(p, "--n", type="int", help="...").
func argument(target, names, action="store", nargs=null, constant=null, default="==UNSET==", type=null, choices=null, required=null, help=null, metavar=null, dest=null, version=null, env=null, hidden=false, complete=null):
    return target.add_argument(names, {"action": action, "nargs": nargs, "const": constant, "default": default, "type": type, "choices": choices, "required": required, "help": help, "metavar": metavar, "dest": dest, "version": version, "env": env, "hidden": hidden, "complete": complete})

# Pour une fonction type= : refuser une valeur avec un message précis.
#   func port(text): ... argparse.fail("port hors de 1..65535")
func fail(message):
    raise("ArgumentTypeError", message)

# type= prêt à l'emploi : entier dans [low, high] (bornes incluses).
func int_range(low, high):
    func check(text):
        if not _t.is_int_text(text):
            raise("ArgumentTypeError", "entier attendu : '" + text + "'")
        v := _t.parse_int(text)
        if v < low or v > high:
            raise("ArgumentTypeError", "valeur hors de [" + str(low) + ", " + str(high) + "] : " + str(v))
        return v
    return check

# type= prêt à l'emploi : nombre dans [low, high].
func float_range(low, high):
    func check(text):
        if not _t.is_float_text(text):
            raise("ArgumentTypeError", "nombre attendu : '" + text + "'")
        v := _t.parse_float(text)
        if v < low or v > high:
            raise("ArgumentTypeError", "valeur hors de [" + str(low) + ", " + str(high) + "] : " + str(v))
        return v
    return check

func set_language(code):
    return _t.set_language(code)

func language():
    return _t.language()
