# Script lancé en sous-processus par test_argparse.al : exit_on_error=true (comportement réel).
use argparse
use json

p := argparse.parser(prog="fx", description="Fixture", version="%(prog)s 9.9")
p.add_argument("--n", {"type": "int", "default": 1, "help": "un entier"})
p.add_argument("name", {"nargs": "?", "default": "anon"})
args := p.parse_args()
print(json.stringify(args))
