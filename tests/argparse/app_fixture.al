# Application cli lancée en sous-processus : codes de sortie réels de cli.App.main().
use cli
use argparse
use os

func ok(args):
    cli.out("ok " + str(args["n"]) + "\n")
    return null

func seven(args):
    return 7

func boom(args):
    raise("ValueError", "échec simulé")

func inner(args):
    cli.out("inner\n")
    return 0

app := cli.App("app", {"description": "Appli de test"})
app.option("--verbose", {"action": "store_true"})
c := app.command("ok", ok, {"help": "dit ok"})
c.argument("n", {"type": "int"})
app.command("seven", seven, {"aliases": ["7"]})
app.command("boom", boom)
g := app.command("group", null, {"help": "un groupe"})
g.command("inner", inner)
app.add_builtins()
app.main()
