# Faux lecteur / enregistreur portable pour les tests audio (remplace `sh -c "cat > f"` et `cat f`, absents sous
# Windows) : octets bruts, sans conversion.
#   alexc run tests/media/pipe_tool.al -- sink fichier     entrée standard -> fichier
#   alexc run tests/media/pipe_tool.al -- source fichier   fichier -> sortie standard
from core use len
use io
use io.stream as stream
use os

stream.binary_stdio()
a := os.args()
mode := a[len(a) - 2]
path := a[len(a) - 1]
if mode == "sink":
    r := stream.stdin()
    data := []
    while true:
        b := r.read_bytes(65536)
        if len(b) == 0:
            break
        data = data + b
    io.write_bytes(path, data)
else:
    w := stream.stdout()
    w.write_bytes(io.read_bytes(path))
    w.flush()
