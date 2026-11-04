# Serveur HTTPS écrit en Alex (http.Server avec certificat), lancé comme processus fils par test_tls.al.
# usage : alex run https_alex_server.al cert.pem key.pem
use network.http as http
use os
use io

args := os.args()
running := [true]
func handler(req):
    if req.path == "/bonjour":
        return http.text("Bonjour " + req.param("nom", "inconnu") + " en TLS !\n")
    if req.path == "/json" and req.method == "POST":
        v := req.json()
        v["tls"] = true
        return http.json_response(v, 201)
    if req.path == "/stop":
        running[0] = false
        return "arrêt\n"
    return http.text("introuvable\n", 404)

srv := http.Server("127.0.0.1", 0, args[0], args[1])
print(srv.port())
io.flush()
while running[0]:
    srv.handle_one(handler)
srv.close()
