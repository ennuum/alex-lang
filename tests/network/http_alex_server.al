# Serveur HTTP écrit en Alex, lancé comme processus fils par tests/network/test_http.al : écrit son port, puis
# sert les requêtes jusqu'à /stop.
use network.http as http
use io
from collections use keys

running := [true]
func handler(req):
    if req.path == "/bonjour":
        return http.text("Bonjour " + req.param("nom", "inconnu") + " !\n")
    if req.path == "/json" and req.method == "POST":
        v := req.json()
        v["vu_par_le_serveur"] = true
        return http.json_response(v, 201)
    if req.path == "/form":
        f := req.form()
        return http.text(f["a"] + "|" + f["b"])
    if req.path == "/redirige":
        return http.redirect("/bonjour?nom=redirigé")
    if req.path == "/erreur":
        raise("ValueError", "panne volontaire")
    if req.path == "/vide":
        return null
    if req.path == "/stop":
        running[0] = false
        return "arrêt\n"
    return http.text("introuvable : " + req.path + "\n", 404)

srv := http.Server("127.0.0.1", 0)
print(srv.port())
io.flush() # le parent attend cette ligne : stdout est un tube
while running[0]:
    srv.handle_one(handler)
srv.close()
