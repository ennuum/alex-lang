# {{nom}} — outil en ligne de commande.
#   alexc run -- saluer Alex
#   alexc run -- compter fichier.txt
#   alexc run -- --help
#   alexc build --standalone main.al -o {{nom}}     (exécutable autonome)
use argparse
use commandes

p := argparse.parser(prog="{{nom}}", description="{{Nom}} : exemple d'outil.", version="0.1.0")
p.add_argument(["-v", "--verbose"], {"action": "store_true", "help": "affiche les détails"})
sub := p.add_subparsers({"dest": "commande", "required": true})
c := sub.add_parser("compter", {"help": "compte lignes, mots et caractères"})
c.add_argument("fichiers", {"nargs": "+", "help": "fichiers à analyser"})
s := sub.add_parser("saluer", {"help": "affiche un salut"})
s.add_argument("nom", {"nargs": "?", "default": "monde"})
args := p.parse_args()
commandes.executer(args)
