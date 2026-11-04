# ALEX STANDARD LIBRARY — cli
#
# Applications en ligne de commande par-dessus argparse : une commande = un parseur + une
# fonction « gestionnaire » ; run() analyse les arguments, appelle le bon gestionnaire et
# retourne un code de sortie. Sous-commandes imbriquées, alias, aide automatique.
#
#   use cli
#
#   func add(args):
#       print("ajout de", args["paths"])
#       return 0
#
#   app := cli.App("tool", {"description": "Mon outil", "version": "1.0"})
#   app.option("--verbose", {"action": "store_true", "help": "bavard"})   # option globale
#   c := app.command("add", add, {"help": "Ajoute des fichiers", "aliases": ["a"]})
#   c.argument("paths", {"nargs": "+"})
#   app.add_builtins()                 # commandes « help », « completion », « man »
#   cli.exit(app.run())                # run() : os.args() -> gestionnaire -> code
#
# Gestionnaire : fonction(args) où args est le dict d'argparse ; retourne un entier (code
# de sortie) ou null (0). Une exception du gestionnaire est affichée « prog: erreur: … »
# sur stderr avec le code 1 (catch_errors=false pour la laisser remonter).
# Sans sous-commande donnée à un groupe, l'aide du groupe est affichée (code 2).
#
# Fonctions : out(texte) err(texte) exit(code) — sortie standard, erreur, sortie du processus.
#
# Erreurs : celles d'argparse (ArgparseConfigError à la construction).

from core use len, type
from collections use append, contains_key, keys
use _native_cli as _n
use argparse.parser as _p
use argparse.text as _t

func out(text):
    _n.write_out(str(text))
    return null

func err(text):
    _n.write_err(str(text))
    return null

func exit(code=0):
    return _n.exit(code)

# Une commande (ou la racine) : enveloppe d'un parseur.
class Command:
    func init(app, parser, key):
        self.app = app
        self.parser = parser
        self.key = key
        self.children = null

    func argument(names, opts=null):
        return self.parser.add_argument(names, opts)

    # Alias de argument() pour les options globales/locales (lisibilité).
    func option(names, opts=null):
        return self.parser.add_argument(names, opts)

    func group(title, description=null):
        return self.parser.add_argument_group(title, description)

    func mutex(opts=null):
        return self.parser.add_mutually_exclusive_group(opts)

    # Sous-commande de cette commande ; handler peut être null pour un simple groupe.
    # opts : ceux de add_parser (aliases help description epilog usage hidden ...).
    func command(name, handler=null, opts=null):
        if self.children == null:
            self.children = self.parser.add_subparsers({"dest": null, "title": "commandes", "required": false})
        node := self.children.add_parser(name, opts)
        key := self.key + " " + name
        if handler != null:
            self.app.handlers[key] = handler
        return Command(self.app, node, key)

    func set_handler(handler):
        self.app.handlers[self.key] = handler
        return self

class App:
    # opts : ceux d'ArgumentParser, plus "catch_errors" (true) et "show_help_on_empty" (true).
    func init(prog, opts=null):
        popts := {}
        catch_errors := true
        show_help := true
        if opts != null:
            for k in keys(opts):
                if k == "catch_errors":
                    catch_errors = opts[k]
                elif k == "show_help_on_empty":
                    show_help = opts[k]
                else:
                    popts[k] = opts[k]
        self.parser = _p.Parser(prog, popts)
        self.root = Command(self, self.parser, prog)
        self.handlers = {}
        self.catch_errors = catch_errors
        self.show_help = show_help
        self.builtins = false

    func argument(names, opts=null):
        return self.root.argument(names, opts)

    func option(names, opts=null):
        return self.root.option(names, opts)

    func group(title, description=null):
        return self.root.group(title, description)

    func mutex(opts=null):
        return self.root.mutex(opts)

    func command(name, handler=null, opts=null):
        return self.root.command(name, handler, opts)

    # Gestionnaire de la racine (appelé quand aucune sous-commande n'est donnée).
    func set_handler(handler):
        self.handlers[self.root.key] = handler
        return self

    # Commandes intégrées : « help [commande...] », « completion <shell> », « man [section] ».
    func add_builtins():
        if self.builtins:
            return self
        self.builtins = true
        app := self
        func help_cmd(args):
            target := app.parser
            names := args["topic"]
            if names != null:
                for nm in names:
                    if target.sub == null or target.sub.find(nm) == null:
                        raise("ArgparseError", "commande inconnue : " + nm)
                    target = target.sub.find(nm)
            out(target.format_help())
            return 0
        func completion_cmd(args):
            out(app.parser.completion(args["shell"]))
            return 0
        func man_cmd(args):
            out(app.parser.format_man(args["section"]))
            return 0
        h := self.command("help", help_cmd, {"help": "Affiche l'aide d'une commande"})
        h.argument("topic", {"nargs": "*", "help": "commande (et sous-commandes) dont afficher l'aide"})
        c := self.command("completion", completion_cmd, {"help": "Génère un script de complétion"})
        c.argument("shell", {"choices": ["bash", "zsh", "powershell"], "help": "shell cible"})
        m := self.command("man", man_cmd, {"help": "Génère la page de manuel (roff)"})
        m.argument("section", {"nargs": "?", "type": "int", "default": 1, "help": "section du manuel"})
        return self

    # Analyse argv (os.args() par défaut), exécute le gestionnaire, retourne le code de sortie.
    func run(argv=null):
        r := self.parser.parse_args_ex(argv)
        path := r["path"]
        key := self.root.key
        for p in path:
            key = key + " " + p
        if not contains_key(self.handlers, key):
            if self.show_help:
                out(r["parser"].format_help())
            return 2
        handler := self.handlers[key]
        if not self.catch_errors:
            code := handler(r["args"])
            if code == null:
                return 0
            return code
        failure := null
        code2 := null
        try:
            code2 = handler(r["args"])
        catch e:
            failure = e
        if failure != null:
            err(self.parser.prog + ": " + _t.msg("error") + ": " + failure.message + "\n")
            return 1
        if code2 == null:
            return 0
        return code2

    # run() puis sortie du processus avec le code obtenu.
    func main(argv=null):
        exit(self.run(argv))

func app(prog, opts=null):
    return App(prog, opts)
