# {{nom}} — serveur HTTP.
#   alexc run                       écoute sur http://127.0.0.1:8080
#   curl http://127.0.0.1:8080/api/bonjour?nom=Alex
from core use len, to_int
use os
use io
use network.http as http
use routes

port := 8080
args := os.args()
if len(args) > 0:
    port = to_int(args[0])

func handler(req):
    return routes.traiter(req.method, req.path, req.query)

srv := http.Server("127.0.0.1", port)
print("{{Nom}} écoute sur " + srv.url())
io.flush() # visible tout de suite, même quand la sortie est un tube ou un fichier
srv.serve(handler)
