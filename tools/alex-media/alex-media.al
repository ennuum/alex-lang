# alex-media : outils multimédias en ligne de commande.
#   alex run tools/alex-media/alex-media.al -- <commande> [arguments]
#   commandes : probe, convert, record, benchmark, capabilities
from core use len
use os
use probe.probe as cmd_probe
use convert.convert as cmd_convert
use record.record as cmd_record
use benchmark.benchmark as cmd_bench
use multimedia

a := os.args()
if len(a) == 0 or a[0] == "-h" or a[0] == "--help":
    print("usage : alex-media <probe|convert|record|benchmark|capabilities> [arguments] (--help par commande)")
    os.exit(0)
c := a[0]
rest := [a[k] for k in 1..len(a)]
code := 0
if c == "probe":
    code = cmd_probe.main(rest)
elif c == "convert":
    code = cmd_convert.main(rest)
elif c == "record":
    code = cmd_record.main(rest)
elif c == "benchmark":
    code = cmd_bench.main(rest)
elif c == "capabilities":
    print(multimedia.capabilities())
else:
    print("alex-media : commande inconnue « " + c + " »")
    code = 2
os.exit(code)
