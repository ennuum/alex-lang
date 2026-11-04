# ALEX STANDARD LIBRARY — ipc.local_socket
#
# Sockets LOCAUX (domaine Unix) : comme TCP, mais entre processus de la même machine, désignés par un chemin
# du système de fichiers (droits d'accès des fichiers) ou par un nom abstrait « @nom » (Linux, sans fichier).
# Plus rapides que TCP en boucle locale, invisibles du réseau.
#
#   use ipc.local_socket as ls
#   serveur := ls.listen("mon-service")         # /tmp/alex-mon-service.sock (ou un chemin, ou « @nom »)
#   # autre processus :
#   c := ls.connect("mon-service", 2.0)
#   c.send_line("ping")
#   # serveur :
#   conn := serveur.accept(5.0)
#   print(conn.read_line(1.0))                  # « ping »
#   conn.send_message("réponse complète")       # message délimité (longueur + octets)
#   conn.close()
#   serveur.close()                             # supprime aussi le fichier du socket
#
# Messages : send_message / receive_message transportent des messages entiers (« <longueur>\n<octets> », comme
# pipe.pipe_stream) ; send_json / receive_json des valeurs JSON.
#
# Erreurs : IpcError (adresse occupée, absente, droits...), TimeoutError, ProtocolError, TypeError.

from core use len, type, to_int
from collections use append
use string as _str
use os as _os
use json as _json
use network.socket as _sk
from io.stream use Reader
use _native_net as _n
use _native_fd as _f

const MAX_MESSAGE := 67108864

# Adresse d'un nom : chemin tel quel (« / » ou « ./ » en tête), nom abstrait « @... », sinon un fichier du
# dossier temporaire « alex-<nom>.sock ».
func address(name):
    if type(name) != "str" or name == "":
        raise("TypeError", "local_socket : nom (str non vide) attendu")
    c := name[0]
    if c == '/' or c == '@' or _str.starts_with(name, "./") or _str.starts_with(name, "../"):
        return name
    return _os.join(_os.tmp_dir(), "alex-" + name + ".sock")

func _wrap(fn, f):
    try:
        return f()
    catch NetworkError as e:
        raise("IpcError", "local_socket." + fn + " : " + e.message)

class _ConnReader extends Reader:
    func init(sock):
        super.init()
        self.sock = sock

    func _source(max, timeout):
        try:
            return self.sock.recv(max, timeout)
        catch NetworkError as e:
            raise("IpcError", "local_socket : " + e.message)

class LocalConnection:
    func init(sock, address):
        self.sock = sock
        self.address = address
        self.reader = _ConnReader(sock)
        self.closed = false

    func fd():
        return _n.fd(self.sock.handle)

    func send(data, timeout=null):
        return _wrap("send", () => self.sock.send(data, timeout))

    func send_line(text, timeout=null):
        return self.send(str(text) + "\n", timeout)

    func read(max=65536, timeout=null):
        return self.reader.read(max, timeout)

    func read_line(timeout=null):
        return self.reader.read_line(timeout)

    func read_exact(n, timeout=null):
        return self.reader.read_exact(n, timeout)

    func read_all(timeout=null):
        return self.reader.read_all(timeout)

    func send_message(data, timeout=null):
        if type(data) != "str":
            raise("TypeError", "LocalConnection.send_message : str attendue")
        return self.send(str(_n.blen(data)) + "\n" + data, timeout)

    # Message suivant ; null : l'autre bout a fermé entre deux messages.
    func receive_message(timeout=null):
        head := self.reader.read_until("\n", timeout, 32)
        if head == null:
            return null
        n := null
        try:
            n = to_int(head)
        catch e:
            raise("ProtocolError", "local_socket : en-tête de message invalide '" + head + "'")
        if n < 0 or n > MAX_MESSAGE:
            raise("ProtocolError", "local_socket : longueur de message " + str(n) + " hors limites")
        if n == 0:
            return ""
        try:
            return self.reader.read_exact(n, timeout)
        catch IoError as e:
            raise("ProtocolError", "local_socket : connexion fermée au milieu d'un message")

    func send_json(value, timeout=null):
        return self.send_message(_json.stringify(value), timeout)

    func receive_json(timeout=null):
        m := self.receive_message(timeout)
        if m == null:
            return null
        return _json.parse(m)

    # Vrai si des données (ou la fermeture) attendent d'être lues.
    func readable(timeout=0):
        if _n.blen(self.reader._buffer) > 0:
            return true
        return len(_sk.wait([self.sock], "read", timeout)) > 0

    # Identité du processus à l'autre bout n'est pas exposée ; adresse locale / distante :
    func peer():
        return self.sock.peer_address()[0]

    func close_write():
        self.sock.shutdown("write")

    func close():
        if not self.closed:
            self.sock.close()
            self.closed = true

class LocalServer:
    func init(name, backlog=64, mode=null):
        self.address = address(name)
        self.sock = _sk.Socket(1, "tcp")
        if self.address[0] != '@':
            kind := _f.file_kind(self.address, false)
            if kind == "socket":
                # Fichier laissé par un serveur arrêté ? S'il ne répond pas, on le remplace.
                if _probe(self.address):
                    self.sock.close()
                    raise("IpcError", "local_socket.listen : un serveur écoute déjà sur " + self.address + " [EADDRINUSE]")
                _os.remove(self.address)
            elif kind != null:
                self.sock.close()
                raise("IpcError", "local_socket.listen : " + self.address + " existe et n'est pas un socket")
        try:
            self.sock.bind(self.address, 0)
            self.sock.listen(backlog)
        catch NetworkError as e:
            self.sock.close()
            raise("IpcError", "local_socket.listen(" + self.address + ") : " + e.message)
        if mode != null and self.address[0] != '@':
            _os.chmod(self.address, mode)
        self.closed = false

    # Connexion entrante (LocalConnection) ; TimeoutError après timeout secondes.
    func accept(timeout=null):
        r := self.sock.accept(timeout)
        return LocalConnection(r[0], self.address)

    func fd():
        return _n.fd(self.sock.handle)

    # Ferme et supprime le fichier du socket.
    func close():
        if not self.closed:
            self.sock.close()
            self.closed = true
            if self.address[0] != '@' and _f.file_kind(self.address, false) == "socket":
                _os.remove(self.address)

func _probe(addr):
    s := _sk.Socket(1, "tcp")
    try:
        s.connect(addr, 0, 0.2)
        return true
    catch e:
        return false
    finally:
        s.close()

func listen(name, backlog=64, mode=null):
    return LocalServer(name, backlog, mode)

func connect(name, timeout=null):
    addr := address(name)
    s := _sk.Socket(1, "tcp")
    try:
        s.connect(addr, 0, timeout)
    catch NetworkError as e:
        s.close()
        raise("IpcError", "local_socket.connect(" + addr + ") : " + e.message)
    catch TimeoutError as e:
        s.close()
        raise(e.type, e.message)
    return LocalConnection(s, addr)

# Paire de connexions reliées, sans nom (pour un fil ou un fils qui hérite du descripteur) : (a, b).
func pair():
    r := _n.socketpair("tcp")
    if type(r) == "int":
        raise("IpcError", "local_socket.pair : " + _n.strerror(r))
    a := _sk.Socket(1, "tcp", r[0])
    b := _sk.Socket(1, "tcp", r[1])
    return (LocalConnection(a, ""), LocalConnection(b, ""))

func _buffered(c):
    try:
        return _n.blen(c.reader._buffer) > 0
    catch e:
        return false

# Connexions prêtes à lire parmi conns (LocalConnection, ou LocalServer : connexion en attente d'accept).
func wait(conns, timeout=null):
    ready := [c for c in conns if _buffered(c)]
    if len(ready) > 0:
        return ready
    got := _sk.wait([c.sock for c in conns], "read", timeout)
    out := []
    for c in conns:
        for s in got:
            if s.handle == c.sock.handle:
                append(out, c)
                break
    return out
