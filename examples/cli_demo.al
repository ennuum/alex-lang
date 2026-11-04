# Démo argparse + cli : sous-commandes, alias, choix, complétion et page de manuel.
#   alexc run examples/cli_demo.al add a.txt b.txt --mode slow
#   alexc run examples/cli_demo.al completion bash
#   alexc run examples/cli_demo.al man
use cli

func add(args):
    cli.out("ajout de " + str(args["paths"]) + " (mode " + args["mode"] + ")\n")
    return 0

func remove(args):
    cli.out("suppression de " + args["name"] + "\n")
    return 0

app := cli.App("demo", {"description": "Démo de cli/argparse", "version": "%(prog)s 1.0"})
app.option("--verbose", {"action": "count", "help": "plus de détails"})
c := app.command("add", add, {"aliases": ["a"], "help": "Ajoute des fichiers"})
c.argument("paths", {"nargs": "+", "type": "path", "help": "fichiers"})
c.argument("--mode", {"choices": ["fast", "slow"], "default": "fast", "help": "mode (défaut : %(default)s)"})
r := app.command("remove", remove, {"aliases": ["rm"], "help": "Supprime"})
r.argument("name", {"help": "nom"})
app.add_builtins()
app.main()
