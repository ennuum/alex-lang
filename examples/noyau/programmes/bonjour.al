# Programme utilisateur ordinaire : le même exécutable tourne sous Linux et sous Alex OS (anneau 3).
use os
use io
from collections use append
from core use len
print(f"Bonjour de {os.name()} ! arguments : {os.args()}")
mots: list[str] := []
for i in 0..20000:
    append(mots, "mot" + str(i))
print(len(mots), mots[19999])
io.write_file("trace.txt", f"écrit par le processus {os.pid()}\n")
print(io.read_file("trace.txt"))
