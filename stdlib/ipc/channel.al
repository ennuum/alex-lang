# ALEX STANDARD LIBRARY — ipc.channel
#
# Canaux de VALEURS entre processus : des dict, listes, textes, nombres (JSON) passent d'un processus à l'autre
# sur un socket local, message par message ; et un petit protocole question / réponse avec serveur multi-clients.
#
#   use ipc.channel as ch
#   # serveur
#   srv := ch.serve_on("calcul")
#   srv.handle("somme", (args) => args[0] + args[1])
#   srv.handle("echo", (args) => args)
#   srv.run(10)                                   # répond pendant 10 s (null : jusqu'à srv.stop())
#   # client (autre processus)
#   c := ch.connect("calcul", 2.0)
#   print(c.call("somme", [2, 3]))                # 5
#   c.close()
#
#   # canal brut : send / receive de valeurs
#   a := ch.connect("journal")
#   a.send({"niveau": "info", "texte": "démarré"})
#
# Une erreur levée par une fonction du serveur revient au client sous forme de RemoteError (type et message
# d'origine dans le message). Un client peut enchaîner autant d'appels qu'il veut sur la même connexion.
#
# Erreurs : IpcError, TimeoutError, RemoteError, ProtocolError.

from core use len, type
from collections use append, contains_key, keys
use os as _os
use ipc.local_socket as _ls

# Canal : une connexion, des valeurs JSON dans chaque sens.
class Channel:
    func init(conn):
        self.conn = conn
        self._next_id = 1

    func send(value, timeout=null):
        self.conn.send_json(value, timeout)

    # Valeur suivante ; null si l'autre bout a fermé ; TimeoutError après timeout.
    func receive(timeout=null):
        return self.conn.receive_json(timeout)

    # Appelle la fonction nommée du serveur (ChannelServer) avec args ; renvoie son résultat.
    func call(name, args=null, timeout=null):
        id := self._next_id
        self._next_id += 1
        self.send({"id": id, "call": name, "args": args}, timeout)
        r := self.receive(timeout)
        if r == null:
            raise("IpcError", "ipc.channel.call(" + name + ") : le serveur a fermé la connexion")
        if type(r) != "dict" or not contains_key(r, "id") or r["id"] != id:
            raise("ProtocolError", "ipc.channel.call(" + name + ") : réponse inattendue")
        if contains_key(r, "error"):
            raise("RemoteError", r["error"]["type"] + ": " + r["error"]["message"])
        return r["result"]

    func readable(timeout=0):
        return self.conn.readable(timeout)

    func close():
        self.conn.close()

func connect(name, timeout=null):
    return Channel(_ls.connect(name, timeout))

# Paire de canaux reliés dans le même processus (essais, fils) : (a, b).
func pair():
    p := _ls.pair()
    return (Channel(p[0]), Channel(p[1]))

class ChannelServer:
    func init(name):
        self.listener = _ls.listen(name)
        self.address = self.listener.address
        self._handlers = {}
        self._clients = []
        self._stop = false
        self.calls = 0

    # Associe name à fn(args) -> résultat.
    func handle(name, fn):
        self._handlers[name] = fn
        return self

    func stop():
        self._stop = true

    func _answer(ch, req):
        if type(req) != "dict" or not contains_key(req, "call"):
            ch.send({"id": null, "error": {"type": "ProtocolError", "message": "requête sans champ 'call'"}})
            return
        id := null
        if contains_key(req, "id"):
            id = req["id"]
        name := req["call"]
        if not contains_key(self._handlers, name):
            ch.send({"id": id, "error": {"type": "NameError", "message": "fonction inconnue '" + str(name) + "'"}})
            return
        args := null
        if contains_key(req, "args"):
            args = req["args"]
        self.calls += 1
        try:
            f := self._handlers[name]
            ch.send({"id": id, "result": f(args)})
        catch e:
            ch.send({"id": id, "error": {"type": e.type, "message": e.message}})

    # Un tour : accepte les nouveaux clients, répond aux requêtes prêtes. Renvoie le nombre de requêtes traitées.
    func step(timeout=0.05):
        conns := [self.listener]
        for c in self._clients:
            append(conns, c.conn)
        ready := _ls.wait(conns, timeout)
        done := 0
        for r in ready:
            if r == self.listener:
                append(self._clients, Channel(self.listener.accept(0)))
                continue
            for c in self._clients:
                if c.conn == r:
                    req := null
                    closed := false
                    try:
                        req = c.receive(1.0)
                        closed = req == null
                    catch e:
                        closed = true
                    if closed:
                        c.close()
                        self._clients = [x for x in self._clients if x != c]
                    else:
                        self._answer(c, req)
                        done += 1
                    break
        return done

    # Sert pendant duration secondes (null : jusqu'à stop()).
    func run(duration=null):
        end := null
        if duration != null:
            end = _os.monotonic_time() + duration
        self._stop = false
        while not self._stop:
            if end != null and _os.monotonic_time() >= end:
                break
            self.step(0.05)
        return self.calls

    func clients():
        return len(self._clients)

    func close():
        for c in self._clients:
            c.close()
        self._clients = []
        self.listener.close()

func serve_on(name):
    return ChannelServer(name)
