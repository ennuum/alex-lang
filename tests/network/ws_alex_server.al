# Serveur WebSocket écrit en Alex, lancé comme processus fils par tests/network/test_websocket.al.
# usage : alex run ws_alex_server.al [cert.pem key.pem]   (avec certificat : wss://)
# Chemin servi : /chat, sous-protocole « chat ». Messages texte : « stop » arrête le serveur, « close » ferme avec
# 4001, « big » envoie 70 000 octets binaires, « frag » envoie un texte en fragments de 4 octets ; le reste est
# renvoyé précédé de « echo: ». Les messages binaires sont renvoyés tels quels.
use network.websocket as ws
use string as s
use os
use io
from core use len

args := os.args()
srv := null
if len(args) >= 2:
    srv = ws.Server("127.0.0.1", 0, ["chat"], "/chat", null, 1048576, args[0], args[1])
else:
    srv = ws.Server("127.0.0.1", 0, ["chat"], "/chat")
print(srv.port())
io.flush()
running := true
while running:
    c := null
    try:
        c = srv.accept()
    catch e:
        continue
    try:
        while true:
            m := c.receive(10.0)
            if m == null:
                break
            if m.is_text():
                t := m.text()
                if t == "stop":
                    running = false
                    break
                elif t == "close":
                    c.close(4001, "demandé")
                    break
                elif t == "big":
                    c.send_binary(s.repeat("b", 70000))
                elif t == "frag":
                    c.send_text("fragmenté é ✓", 4)
                else:
                    c.send_text("echo:" + t)
            else:
                c.send_binary(m.data)
    catch e:
        io.flush()
    c.close()
srv.close()
