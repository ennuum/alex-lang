# ALEX STANDARD LIBRARY — network.tcp
#
# Connexions TCP avec tampon de lecture (lignes, délimiteurs, tailles exactes), serveurs en écoute.
#
# Lectures
#   read(max)            texte disponible (au plus max octets ; jamais coupé au milieu d'un caractère UTF-8)
#   read_line()          une ligne sans sa fin (« \n » ou « \r\n ») ; null : fin du flux
#   read_until(sep)      tout jusqu'au séparateur (exclu) ; null : fin du flux
#   read_exact(n)        exactement n octets (str brute) ; NetworkError si la connexion se ferme avant
#   read_all()           tout jusqu'à la fermeture par l'autre extrémité
#   read_bytes / read_exact_bytes : mêmes lectures en list[int] d'octets
# Les délais de lecture sont des délais d'INACTIVITÉ : au plus `timeout` secondes sans recevoir de données.
#
# Erreurs : NetworkError, TimeoutError, DnsError (nom d'hôte), voir network.socket.
#
# Exemple
#   use network.tcp as tcp
#   c := tcp.connect("example.org", 80, 5.0)
#   c.write("HEAD / HTTP/1.0\r\nHost: example.org\r\n\r\n")
#   print(c.read_line())
#   c.close()
#
#   srv := tcp.listen("127.0.0.1", 0)       # port choisi par le système : srv.port()
#   conn := srv.accept()
#   conn.write_line("bonjour " + conn.peer_address()[0])
#   conn.close()

from core use len, type
use _native_net as _n
use network.socket as _sk
use network.dns as _dns

const LINE_LIMIT := 1048576

func _min(a, b):
    if a < b:
        return a
    return b

class Connection:
    func init(sock):
        self.socket = sock
        self.buffer = ""    # octets reçus pas encore lus
        self.eof = false

    # Ajoute des octets au tampon ; false si la connexion est fermée par l'autre extrémité.
    func _fill(timeout):
        if self.eof:
            return false
        data := self.socket.recv(65536, timeout)
        if data == "":
            self.eof = true
            return false
        self.buffer = self.buffer + data
        return true

    func _take(n):
        out := _n.bslice(self.buffer, 0, n)
        self.buffer = _n.bslice(self.buffer, n, _n.blen(self.buffer))
        return out

    # Texte disponible, au plus max octets, sans couper de caractère UTF-8 ; "" : fin du flux.
    func read(max=65536, timeout=null):
        while true:
            n := _n.blen(self.buffer)
            if n > 0:
                k := _min(n, max)
                whole := _n.utf8_prefix(_n.bslice(self.buffer, 0, k))
                if whole > 0:
                    return self._take(whole)
                if k < n or n >= 4: # max plus petit qu'un caractère : octets bruts
                    return self._take(k)
            if not self._fill(timeout): # fin du flux : le reste tel quel ("" s'il n'y a plus rien)
                return self._take(_n.blen(self.buffer))

    func read_bytes(max=65536, timeout=null):
        if _n.blen(self.buffer) == 0:
            self._fill(timeout)
        return _n.to_bytes(self._take(_min(_n.blen(self.buffer), max)))

    # Exactement n octets (str brute, sans décodage).
    func read_exact(n, timeout=null):
        while _n.blen(self.buffer) < n:
            if not self._fill(timeout):
                raise("NetworkError", "tcp.read_exact : connexion fermée après " + str(_n.blen(self.buffer)) + " octets sur " + str(n))
        return self._take(n)

    func read_exact_bytes(n, timeout=null):
        return _n.to_bytes(self.read_exact(n, timeout))

    # Données jusqu'au séparateur sep (exclu, consommé) ; à la fin du flux : le reste, ou null s'il est vide.
    func read_until(sep, timeout=null, limit=LINE_LIMIT):
        if type(sep) != "str" or sep == "":
            raise("ArgumentError", "tcp.read_until : séparateur str non vide attendu")
        start := 0
        while true:
            i := _n.bfind(self.buffer, sep, start)
            if i >= 0:
                out := self._take(i)
                self._take(_n.blen(sep))
                return out
            if _n.blen(self.buffer) > limit:
                raise("NetworkError", "tcp.read_until : plus de " + str(limit) + " octets sans séparateur")
            start = _n.blen(self.buffer) - _n.blen(sep) + 1
            if start < 0:
                start = 0
            if not self._fill(timeout):
                if _n.blen(self.buffer) == 0:
                    return null
                return self._take(_n.blen(self.buffer))

    # Une ligne, sans « \n » ni « \r\n » final ; null à la fin du flux.
    func read_line(timeout=null, limit=LINE_LIMIT):
        line := self.read_until("\n", timeout, limit)
        if line != null and _n.blen(line) > 0 and _n.bfind(line, "\r", _n.blen(line) - 1) >= 0:
            line = _n.bslice(line, 0, _n.blen(line) - 1)
        return line

    # Tout jusqu'à la fermeture par l'autre extrémité.
    func read_all(timeout=null):
        more := true
        while more:
            more = self._fill(timeout)
        return self._take(_n.blen(self.buffer))

    # Envoie tout (str) ; renvoie le nombre d'octets.
    func write(data, timeout=null):
        return self.socket.send(data, timeout)

    func write_line(text, timeout=null):
        return self.socket.send(text + "\n", timeout)

    func write_bytes(data, timeout=null):
        return self.socket.send_bytes(data, timeout)

    func set_timeout(t):
        self.socket.set_timeout(t)

    # Désactive (true) l'algorithme de Nagle : petits envois sans délai.
    func set_no_delay(on=true):
        self.socket.set_option("no_delay", on)

    func local_address():
        return self.socket.local_address()

    func peer_address():
        return self.socket.peer_address()

    # Signale la fin de l'envoi (l'autre extrémité lit alors la fin du flux) ; la lecture reste possible.
    func close_write():
        self.socket.shutdown("write")

    func close():
        self.socket.close()

    func is_closed():
        return self.socket.is_closed()

# Connexion à host (nom ou adresse) : chaque adresse résolue est essayée dans l'ordre jusqu'à la première qui
# répond. timeout : délai de connexion par adresse ; family : 0 (toutes), 4 ou 6.
func connect(host, port, timeout=null, family=0):
    last := null
    for a in _dns.lookup(host, port, family, "tcp"):
        s := _sk.Socket(a.family, "tcp")
        try:
            s.connect(a.host, port, timeout)
            return Connection(s)
        catch e:
            s.close()
            last = e
    raise(last)

class Listener:
    func init(sock):
        self.socket = sock

    # Port réellement attribué (utile avec le port 0).
    func port():
        return self.socket.local_address()[1]

    func address():
        return self.socket.local_address()

    # Prochaine connexion entrante (Connection) ; TimeoutError après timeout secondes.
    func accept(timeout=null):
        r := self.socket.accept(timeout)
        return Connection(r[0])

    func close():
        self.socket.close()

    func is_closed():
        return self.socket.is_closed()

# Serveur TCP en écoute sur host:port ("" : toutes les interfaces IPv4, "::" : IPv6 ; port 0 : choisi par le
# système). reuse_address : redémarrage immédiat sur le même port.
func listen(host="127.0.0.1", port=0, backlog=128, reuse_address=true):
    family := 4
    addr := host
    if host != "" and not _dns.is_ipv4(host):
        if _dns.is_ipv6(host):
            family = 6
        else:
            a := _dns.lookup(host, port, 0, "tcp")[0]
            family = a.family
            addr = a.host
    s := _sk.Socket(family, "tcp")
    try:
        if reuse_address:
            s.set_option("reuse_address", true)
        s.bind(addr, port)
        s.listen(backlog)
    catch e:
        s.close()
        raise(e)
    return Listener(s)

# Sert les connexions une par une : handler(connection) pour chacune (la connexion est fermée ensuite).
# S'arrête après max_connections connexions (null : jamais) ; une erreur du gestionnaire est passée à
# on_error(erreur, connexion) s'il est donné, sinon elle interrompt le service.
func serve(listener, handler, max_connections=null, on_error=null):
    served := 0
    while max_connections == null or served < max_connections:
        conn := listener.accept()
        try:
            handler(conn)
        catch e:
            if on_error == null:
                conn.close()
                raise(e)
            on_error(e, conn)
        conn.close()
        served += 1
    return served
