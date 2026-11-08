# ALEX STANDARD LIBRARY — network.tls
#
# TLS 1.2 / 1.3 (client et serveur) au-dessus de network.socket : la même interface que Socket, donc une
# network.tcp.Connection fonctionne à l'identique (lignes, tailles exactes, tampon) sur un flux chiffré.
#
# Cryptographie : OpenSSL, chargé À L'EXÉCUTION (dlopen de libssl.so.3 / 1.1) — rien n'est lié à la compilation.
# Sans OpenSSL, supported() vaut false et why() dit pourquoi ; le reste du runtime n'est pas touché.
#
# Une seconde implémentation existe : network.tls13, TLS 1.3 écrit en ALEX pur (calcul lourd dans le runtime,
# crypto.accel). Elle prend le relais quand OpenSSL manque (exécutables natifs) ; backend() dit laquelle sert.
# Variable ALEX_TLS : « openssl » (OpenSSL exigé), « alex » (TLS 1.3 en ALEX même si OpenSSL est là), absente :
# OpenSSL s'il est disponible. Limites de l'implémentation ALEX : TLS 1.3 seulement, pas de certificat client ;
# côté client, vérification par crypto.x509.verify_chain (ca_file ou magasin du système, noms, dates ; pas de
# révocation). supported() est vrai dès que le réseau l'est.
#
# Sécurité par défaut
#   - le certificat du serveur ET son nom sont vérifiés (verify=true) contre les autorités du système, ou contre
#     ca_file ; TLS 1.2 minimum ; SNI envoyé. verify=false désactive TOUT contrôle : à réserver aux tests.
#   - sans close_notify, la fin de flux est une erreur (strict_eof=true) : une coupure en cours de route ne passe pas
#     pour une fin normale (attaque par troncature). strict_eof=false l'accepte (HTTP à longueur connue).
#
# Erreurs
#   TlsError       échec TLS : certificat refusé, nom différent, protocole, poignée de main, coupure sans close_notify.
#   NetworkError, TimeoutError, DnsError   voir network.socket.
#   IoError        TLS indisponible (OpenSSL absent) ou plateforme non prise en charge.
#   TypeError / ArgumentError   usage (fichier de clé illisible, handle fermé...).
#
# Exemple (client)
#   use network.tls as tls
#   c := tls.connect("example.org", 443, 5.0, true, null, ["http/1.1"])
#   c.write("HEAD / HTTP/1.1\r\nHost: example.org\r\nConnection: close\r\n\r\n")
#   print(c.read_line(), c.socket.version, c.socket.cipher)
#   c.close()
#
# Exemple (serveur)
#   srv := tls.listen("127.0.0.1", 8443, "cert.pem", "key.pem")
#   conn := srv.accept()
#   conn.write_line("bonjour, chiffré")
#   conn.close()

from core use len, type
from collections use append
use _native_net as _n
use _native_tls as _t
use network.socket as _sk
use network.tcp as _tcp
use network.tls13 as _tls13
use os as _os
use io as _io
use string as _s
use crypto as _c
use crypto.hkdf as _hkdf

func supported():
    return _sk.supported() and (_t.supported() or backend() == "alex")

# Raison de l'indisponibilité (« » si TLS est disponible).
func why():
    if not _sk.supported():
        return "réseau non pris en charge sur cette plateforme"
    if supported():
        return ""
    return _t.why()

# Implémentation utilisée : « openssl » ou « alex » (network.tls13).
func backend():
    choice := _os.getenv("ALEX_TLS")
    if choice == "alex":
        return "alex"
    if choice == "openssl":
        return "openssl"
    return "openssl" if _t.supported() else "alex"

# Version de la bibliothèque OpenSSL utilisée.
func library_version():
    _require_openssl("library_version")
    return _t.version()

# Nombre de sessions TLS ouvertes (diagnostic : une session non fermée reste ouverte jusqu'à la fin du programme).
func open_count():
    return _t.live_count()

# Implémentation des poignées de main serveur (même choix que backend()).
func server_backend():
    return backend()

# Un serveur TLS est-il possible ? (OpenSSL, ou TLS 1.3 en ALEX dès que le réseau est pris en charge)
func server_supported():
    if not _sk.supported():
        return false
    return server_backend() == "alex" or _t.supported()

# Raison pour laquelle un serveur TLS est impossible (« » sinon).
func server_why():
    if server_supported():
        return ""
    return why()

func _require_server():
    if not _sk.supported():
        raise("IoError", "tls : réseau non pris en charge sur cette plateforme")
    if server_backend() == "openssl" and not _t.supported():
        raise("IoError", "tls : OpenSSL exigé par ALEX_TLS=openssl mais indisponible — " + _t.why())

func _require():
    if not _sk.supported():
        raise("IoError", "tls : réseau non pris en charge sur cette plateforme")
    if backend() == "openssl" and not _t.supported():
        raise("IoError", "tls : indisponible — " + _t.why())

func _require_openssl(what):
    if not _t.supported():
        raise("IoError", "tls : " + what + " demande OpenSSL — " + _t.why())

# Traduit le résultat d'une primitive : valeur utile, ou erreur ALEX (-errno -> NetworkError / TimeoutError,
# liste -> TlsError).
func _check(operation, r):
    if type(r) == "list":
        raise("TlsError", operation + " : " + r[0])
    if _sk.is_error(r):
        _sk.fail(operation, r)
    return r

class TlsSocket:
    # Session TLS sur `sock` (network.socket.Socket connecté) ; handle : session native (usage interne : voir
    # wrap_client / wrap_server).
    func init(sock, handle):
        self.socket = sock
        self.handle = handle
        self.family = sock.family
        self.kind = "tcp"
        self.timeout = null
        self.closed = false
        i := _t.info(handle)
        self.version = i[0]          # « TLSv1.3 »
        self.cipher = i[1]           # « TLS_AES_256_GCM_SHA384 »
        self.alpn = i[2]             # protocole ALPN négocié, ou null
        self.verify_result = i[3]    # 0 : certificat vérifié (X509_V_OK)
        self.session = null          # reprise de session : implémentation ALEX seulement (network.tls13)
        self.resumed = false
        self.peer_subject = i[4]     # sujet du certificat du pair (client : celui du serveur), ou null
        self.peer_issuer = i[5]

    func _h(fn):
        if self.closed:
            raise("ArgumentError", "network.tls." + fn + " : session fermée")
        return self.handle

    func _t(fn, t):
        if t == null:
            return self.timeout
        _sk._check_timeout(fn, t)
        return t

    func set_timeout(t):
        _sk._check_timeout("set_timeout", t)
        self.timeout = t

    # Envoie TOUTES les données (str) ; renvoie le nombre d'octets (voir Socket.send pour le délai).
    func send(data, timeout=null):
        if type(data) != "str":
            raise("TypeError", "network.tls.send : str attendue (obtenu '" + type(data) + "'), voir send_bytes")
        return _check("tls.send", _t.write(self._h("send"), data, self._t("send", timeout)))

    func send_bytes(data, timeout=null):
        return self.send(_n.from_bytes(data), timeout)

    # Jusqu'à max octets déchiffrés ; \"\" : fin du flux (close_notify reçu, ou coupure si strict_eof=false).
    func recv(max=65536, timeout=null):
        return _check("tls.recv", _t.read(self._h("recv"), max, self._t("recv", timeout)))

    func recv_bytes(max=65536, timeout=null):
        return _n.to_bytes(self.recv(max, timeout))

    # Comme recv sans attendre : null si rien n'est disponible.
    func try_recv(max=65536):
        r := _t.read(self._h("try_recv"), max, 0)
        if _sk.is_error(r) and _n.errno_name(r) == "EAGAIN":
            return null
        return _check("tls.recv", r)

    # Octets déjà déchiffrés et disponibles sans toucher au réseau.
    func pending():
        return _t.pending(self._h("pending"))

    # Vrai si le pair a fermé proprement (close_notify reçu).
    func received_close_notify():
        return _t.info(self._h("received_close_notify"))[6]

    func local_address():
        return self.socket.local_address()

    func peer_address():
        return self.socket.peer_address()

    func set_option(name, value):
        self.socket.set_option(name, value)

    # Ferme un sens : \"write\" / \"both\" envoient d'abord close_notify ; la lecture reste possible après \"write\".
    func shutdown(how="both"):
        if how == "write" or how == "both":
            _check("tls.shutdown", _t.shutdown(self._h("shutdown"), self.timeout))
        self.socket.shutdown(how)

    # Envoie close_notify (sans attendre celui du pair), libère la session et ferme le socket.
    func close():
        if not self.closed:
            try:
                _t.shutdown(self.handle, 1.0)
            catch e:
                ignored := e   # la fermeture ne doit pas échouer parce que le pair est déjà parti
            _t.close(self.handle)
            self.closed = true
            self.socket.close()

    func is_closed():
        return self.closed

# Sockets prêts parmi sockets (TlsSocket) : en lecture, ceux qui ont des données déjà déchiffrées sont prêts tout de
# suite ; sinon on attend le réseau (« prêt » veut dire : octets reçus, un enregistrement partiel peut encore faire
# attendre recv).
func wait(sockets, mode="read", timeout=null):
    ready := []
    if mode == "read":
        for s in sockets:
            if s.pending() > 0:
                append(ready, s)
        if len(ready) > 0:
            return ready
    raws := []
    for s in sockets:
        append(raws, s.socket)
    got := _sk.wait(raws, mode, timeout)
    for s in sockets:
        for g in got:
            if g == s.socket:
                append(ready, s)
    return ready

func _check_bool(fn, name, v):
    if type(v) != "bool":
        raise("TypeError", "network.tls." + fn + " : " + name + " doit être un booléen (obtenu '" + type(v) + "')")

func _check_opt_str(fn, name, v):
    if v != null and type(v) != "str":
        raise("TypeError", "network.tls." + fn + " : " + name + " doit être une str ou null (obtenu '" + type(v) + "')")

func _check_alpn(fn, alpn):
    if alpn == null:
        return
    if type(alpn) != "list":
        raise("TypeError", "network.tls." + fn + " : alpn doit être une liste de str ou null")
    for p in alpn:
        if type(p) != "str" or p == "":
            raise("TypeError", "network.tls." + fn + " : alpn : protocoles str non vides attendus")

# Poignée de main TLS CLIENT sur un socket déjà connecté. hostname : nom du serveur (SNI et vérification du
# certificat) ; une adresse IP est comparée à celles du certificat. En cas d'échec le socket n'est pas fermé.
# session : ts.session d'une connexion précédente au même serveur, pour la reprendre par ticket (implémentation
# ALEX ; ignorée avec OpenSSL, où ts.session reste null).
func wrap_client(sock, hostname=null, verify=true, ca_file=null, alpn=null, timeout=null, cert_file=null, key_file=null, strict_eof=true, session=null):
    _require()
    _check_bool("wrap_client", "verify", verify)
    _check_bool("wrap_client", "strict_eof", strict_eof)
    _check_opt_str("wrap_client", "hostname", hostname)
    _check_opt_str("wrap_client", "ca_file", ca_file)
    _check_opt_str("wrap_client", "cert_file", cert_file)
    _check_opt_str("wrap_client", "key_file", key_file)
    _check_alpn("wrap_client", alpn)
    _sk._check_timeout("wrap_client", timeout)
    if verify and hostname == null:
        raise("ArgumentError", "network.tls.wrap_client : vérifier le certificat exige un nom d'hôte (hostname) ou verify=false")
    if backend() == "alex":
        if cert_file != null or key_file != null:
            raise("ArgumentError", "network.tls.wrap_client : certificat client non pris en charge par l'implémentation ALEX (OpenSSL requis)")
        ts := _tls13.wrap_client(sock, hostname, alpn, timeout, verify, ca_file, session)
        ts.strict_eof = strict_eof
        return ts
    label := "tls.handshake"
    if hostname != null:
        label = "tls.handshake(" + hostname + ")"
    h := _check(label, _t.client(_n.fd(sock._h("wrap_client")), hostname, verify, ca_file, alpn, timeout, cert_file, key_file, strict_eof))
    return TlsSocket(sock, h)

# Poignée de main TLS SERVEUR sur un socket accepté (certificat : chaîne PEM ; clé : PEM). alpn : protocoles
# acceptés, par ordre de préférence. Avec l'implémentation ALEX (server_backend() == « alex »), rend un
# network.tls13.TlsSocket13 (même interface ; TLS 1.3 seulement ; certificat et clé lus une fois et gardés).
func wrap_server(sock, cert_file, key_file, alpn=null, timeout=null):
    _require_server()
    _check_opt_str("wrap_server", "cert_file", cert_file)
    _check_opt_str("wrap_server", "key_file", key_file)
    if cert_file == null or key_file == null:
        raise("ArgumentError", "network.tls.wrap_server : cert_file et key_file sont requis")
    _check_alpn("wrap_server", alpn)
    _sk._check_timeout("wrap_server", timeout)
    if server_backend() == "alex":
        return _tls13.wrap_server(sock, _tls13.context(cert_file, key_file, alpn), timeout)
    h := _check("tls.handshake(serveur)", _t.server(_n.fd(sock._h("wrap_server")), cert_file, key_file, alpn, timeout))
    return TlsSocket(sock, h)

# Poignée de main serveur OpenSSL SANS ATTENTE : même interface que network.tls13.TlsSocket13 (server_step,
# established, socket), pour une boucle d'événements (web.server). Chaque server_step fait un essai de SSL_accept
# et rend « read » / « write » (socket brut à attendre) ou « done » ; TlsError en cas d'échec.
class OpenSslAccept:
    func init(sock, handle):
        self.socket = sock
        self.handle = handle
        self.result = null

    func server_step(executor=null):
        if self.result != null:
            return "done"
        r := _t.accept_step(self.handle)
        if type(r) == "list" or _sk.is_error(r):
            h := self.handle
            self.handle = null
            try:
                _t.close(h)
            catch e:
                ignored := e
            _check("tls.handshake(serveur)", r)
        if r == 0:
            self.result = TlsSocket(self.socket, self.handle)
            return "done"
        return "read" if r == 1 else "write"

    # TlsSocket une fois la poignée de main terminée.
    func established():
        return self.result

# Poignée de main serveur à mener sans attendre (server_step(executor) jusqu'à « done », puis established()) :
# network.tls13.TlsSocket13 avec l'implémentation ALEX, OpenSslAccept avec OpenSSL ; null si le runtime ne sait
# pas faire avancer OpenSSL pas à pas (wrap_server reste possible).
func start_server(sock, cert_file, key_file, alpn=null):
    _require_server()
    if cert_file == null or key_file == null:
        raise("ArgumentError", "network.tls.start_server : cert_file et key_file sont requis")
    _check_alpn("start_server", alpn)
    if server_backend() == "alex":
        return _tls13.TlsSocket13(sock, _tls13.context(cert_file, key_file, alpn))
    if not _stepwise():
        return null
    # contexte OpenSSL partagé (certificat lu une fois, recréé si les fichiers changent) et clés de tickets
    # communes à tous les processus : la reprise de session fonctionne d'une connexion et d'un ouvrier à l'autre
    st := _ticket_material(cert_file, key_file)
    return OpenSslAccept(sock, _check("tls.handshake(serveur)", _t.server_start(_n.fd(sock._h("start_server")), cert_file, key_file, alpn, st[0], st[1])))

_material := {}

# [empreinte des fichiers, 80 octets de clés de tickets OpenSSL] : clés tirées de la clé privée (ou de
# ALEX_TLS_TICKET_KEY) par HKDF-SHA-256, recalculées quand un fichier change.
func _ticket_material(cert_file, key_file):
    stamp := _tls13._stamp(cert_file, key_file)
    k := cert_file + "\n" + key_file
    if k in _material and _material[k][0] == stamp:
        return _material[k]
    fixed := _os.getenv("ALEX_TLS_TICKET_KEY")
    ikm := _c.utf8_encode(fixed) if fixed != null and fixed != "" else _s.byte_unpack(_io.read_raw(key_file))
    prk := _hkdf.extract("sha256", _c.utf8_encode("alex openssl tickets"), ikm)
    keys := _s.byte_pack(_hkdf.expand("sha256", prk, _c.utf8_encode("ticket keys"), 80))
    r := [stamp if stamp != "" else "?", keys]
    _material[k] = r
    return r

_step_ok := [null]

# Le runtime a-t-il server_start / accept_step (runtime plus ancien : non) ?
func _stepwise():
    if _step_ok[0] == null:
        ok := false
        try:
            f := _t.accept_step
            ok = f != null
        catch e:
            ok = false
        _step_ok[0] = ok
    return _step_ok[0]

# Connexion TLS à host:port : TCP (chaque adresse résolue est essayée, voir network.tcp.connect) puis poignée de
# main, dans le même délai. server_name : nom présenté (SNI) et vérifié si différent de host.
# Renvoie une network.tcp.Connection ; connexion.socket est le TlsSocket (version, cipher, alpn, peer_subject...).
func connect(host, port=443, timeout=null, verify=true, ca_file=null, alpn=null, family=0, server_name=null, cert_file=null, key_file=null, strict_eof=true, session=null):
    _require()
    _check_bool("connect", "verify", verify)
    _check_bool("connect", "strict_eof", strict_eof)
    _check_opt_str("connect", "ca_file", ca_file)
    _check_opt_str("connect", "server_name", server_name)
    _check_opt_str("connect", "cert_file", cert_file)
    _check_opt_str("connect", "key_file", key_file)
    _check_alpn("connect", alpn)
    name := server_name
    if name == null:
        name = host
    conn := _tcp.connect(host, port, timeout, family)
    try:
        ts := wrap_client(conn.socket, name, verify, ca_file, alpn, timeout, cert_file, key_file, strict_eof, session)
        return _tcp.Connection(ts)
    catch e:
        conn.close()
        raise(e)

class TlsListener:
    # Écouteur TCP dont chaque connexion acceptée passe par la poignée de main serveur.
    func init(listener, cert_file, key_file, alpn, handshake_timeout):
        self.listener = listener
        self.cert_file = cert_file
        self.key_file = key_file
        self.alpn = alpn
        self.handshake_timeout = handshake_timeout
        self.failed = 0    # nombre de poignées de main refusées (client non TLS, protocole, coupure...)

    func port():
        return self.listener.port()

    func address():
        return self.listener.address()

    # Prochaine connexion chiffrée (Connection). Une poignée de main qui échoue lève TlsError (socket fermé) ;
    # le serveur peut continuer avec accept() : voir serve().
    func accept(timeout=null):
        raw := self.listener.socket.accept(timeout)[0]
        try:
            ts := wrap_server(raw, self.cert_file, self.key_file, self.alpn, self.handshake_timeout)
            return _tcp.Connection(ts)
        catch e:
            raw.close()
            self.failed += 1
            raise(e)

    func close():
        self.listener.close()

    func is_closed():
        return self.listener.is_closed()

# Serveur TLS en écoute sur host:port (voir network.tcp.listen). handshake_timeout : temps accordé à chaque client
# pour terminer la poignée de main (un client muet ne bloque pas le serveur plus longtemps).
func listen(host="127.0.0.1", port=0, cert_file=null, key_file=null, alpn=null, backlog=128, reuse_address=true, handshake_timeout=10.0):
    _require_server()
    if cert_file == null or key_file == null:
        raise("ArgumentError", "network.tls.listen : cert_file et key_file sont requis")
    _check_opt_str("listen", "cert_file", cert_file)
    _check_opt_str("listen", "key_file", key_file)
    _check_alpn("listen", alpn)
    for f in [cert_file, key_file]:
        if not _os.exists(f):
            raise("ArgumentError", "network.tls.listen : fichier introuvable « " + f + " »")
    return TlsListener(_tcp.listen(host, port, backlog, reuse_address), cert_file, key_file, alpn, handshake_timeout)

# Sert les connexions une par une comme network.tcp.serve ; en plus, un client dont la poignée de main échoue est
# simplement ignoré (listener.failed le compte) : un scan ou un client non TLS ne fait pas tomber le serveur.
func serve(listener, handler, max_connections=null, on_error=null):
    served := 0
    while max_connections == null or served < max_connections:
        conn := null
        try:
            conn = listener.accept()
        catch e:
            if e.type == "TlsError" or e.type == "NetworkError" or e.type == "TimeoutError":
                continue
            raise(e)
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
