# ALEX STANDARD LIBRARY — network.pop3
#
# Client POP3 (RFC 1939, extensions RFC 2449 / 2595) : relève de courrier, en clair avec STLS ou en TLS implicite
# (POP3S, port 995). Authentification USER/PASS, APOP ou SASL PLAIN ; STAT, LIST, UIDL, RETR, TOP, DELE, RSET.
#
#   c := Pop3Client("pop.exemple.org", 995)
#   c.login("moi", "secret")
#   n, taille := c.stat()
#   for num in c.uidl() ...                 identifiants persistants (pour ne relever que le nouveau)
#   m := c.retrieve_message(1)              network.email.EmailMessage   (retr(1) : octets bruts)
#   c.delete(1) ; c.quit()                  les suppressions ne sont appliquées qu'au QUIT
#
# Erreurs : Pop3Error « pop3 : -ERR ... », NetworkError, TimeoutError, TlsError.

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use crypto as _crypto
use network.core as _core
use network.encoding as _enc
use network.utils as _u
use network.email as _email

func _fail(message):
    raise("Pop3Error", "pop3 : " + message)

class Pop3Client:
    # ssl : TLS implicite (défaut : port 995) ; starttls : "auto", true ou false (STLS).
    func init(host, port=995, ssl=null, starttls="auto", timeout=30.0, verify=true, ca_file=null, allow_plaintext_auth=false):
        self.host = host
        self.port = port
        if ssl == null:
            ssl = port == 995
        self.ssl = ssl
        self.secure = ssl
        self.timeout = timeout
        self.verify = verify
        self.ca_file = ca_file
        self.allow_plaintext_auth = allow_plaintext_auth
        self.capabilities = null
        self.timestamp = null         # « <...> » de la bannière (APOP)
        self.conn = _core.open_connection(host, port, ssl, timeout, verify, ca_file)
        try:
            self.greeting = self._ok_line("accueil")
            lt := _s.find(self.greeting, "<")
            gt := _s.find(self.greeting, ">")
            if lt >= 0 and gt > lt and _s.contains(_s.substring(self.greeting, lt, gt), "@"):
                self.timestamp = _s.substring(self.greeting, lt, gt + 1)
            if not ssl and starttls != false:
                caps := self.capa()
                if contains_key(caps, "STLS"):
                    self.stls()
                elif starttls == true:
                    _fail("le serveur ne propose pas STLS (exigé)")
        catch e:
            self.conn.close()
            raise(e)

    func _line():
        l := self.conn.read_line(self.timeout, 65536)
        if l == null:
            _fail("connexion fermée par le serveur")
        return l

    func _ok_line(what):
        l := self._line()
        if _s.starts_with(l, "+OK"):
            return _s.trim(_s.substring(l, 3, len(l)))
        _fail(what + " : " + l)

    func _send(line):
        _u.check_single_line(line, "commande POP3")
        self.conn.write(line + "\r\n", self.timeout)

    # Commande à réponse d'une ligne ; rend le texte après « +OK ».
    func command(line):
        self._send(line)
        return self._ok_line(_s.split(line, " ")[0])

    # Lit une réponse sur plusieurs lignes terminée par « . » (points doublés retirés) ; lignes sans fin de ligne.
    func _multiline():
        out := []
        while true:
            l := self._line()
            if l == ".":
                return out
            if _s.starts_with(l, ".."):
                l = _s.substring(l, 1, len(l))
            append(out, l)

    func command_multi(line):
        self._send(line)
        self._ok_line(_s.split(line, " ")[0])
        return self._multiline()

    # Capacités (CAPA) : dict nom -> paramètres.
    func capa():
        caps := {}
        try:
            for l in self.command_multi("CAPA"):
                sp := _s.find(l, " ")
                if sp > 0:
                    caps[_s.upper(_s.substring(l, 0, sp))] = _s.trim(_s.substring(l, sp + 1, len(l)))
                else:
                    caps[_s.upper(l)] = ""
        catch e:
            if e.type != "Pop3Error":
                raise(e)
        self.capabilities = caps
        return caps

    func stls():
        self.command("STLS")
        self.conn = _core.start_tls(self.conn, self.host, self.verify, self.ca_file, null, self.timeout)
        self.secure = true
        self.capa()

    func login(user, password):
        if not self.secure and not self.allow_plaintext_auth:
            if self.timestamp != null:
                return self.apop(user, password)
            _fail("mot de passe refusé sur une connexion non chiffrée (allow_plaintext_auth=true pour forcer)")
        self.command("USER " + user)
        return self.command("PASS " + password)

    # Authentification APOP (empreinte MD5 de l'horodatage de la bannière : le mot de passe ne circule pas).
    func apop(user, password):
        if self.timestamp == null:
            _fail("le serveur ne propose pas APOP")
        digest := _crypto.md5(_n.to_bytes(self.timestamp + password))
        return self.command("APOP " + user + " " + digest)

    # Authentification SASL PLAIN (AUTH, RFC 5034).
    func auth_plain(user, password):
        if not self.secure and not self.allow_plaintext_auth:
            _fail("mot de passe refusé sur une connexion non chiffrée")
        return self.command("AUTH PLAIN " + _enc.base64_encode("\u{0}" + user + "\u{0}" + password))

    # (nombre de messages, taille totale en octets).
    func stat():
        p := _s.split(self.command("STAT"), " ")
        return (to_int(p[0]), to_int(p[1]))

    # dict numéro -> taille.
    func list():
        out := {}
        for l in self.command_multi("LIST"):
            p := _s.split(_s.trim(l), " ")
            if len(p) >= 2:
                out[to_int(p[0])] = to_int(p[1])
        return out

    # dict numéro -> identifiant unique.
    func uidl():
        out := {}
        for l in self.command_multi("UIDL"):
            p := _s.split(_s.trim(l), " ")
            if len(p) >= 2:
                out[to_int(p[0])] = p[1]
        return out

    # Message complet (octets bruts, fins de ligne CRLF).
    func retr(number):
        lines := self.command_multi("RETR " + str(to_int(number)))
        return _s.join("\r\n", lines) + "\r\n"

    func retrieve_message(number):
        return _email.parse(self.retr(number))

    # En-têtes et les `lines` premières lignes du corps.
    func top(number, lines=0):
        out := self.command_multi("TOP " + str(to_int(number)) + " " + str(to_int(lines)))
        return _s.join("\r\n", out) + "\r\n"

    # Marque un message pour suppression (effective au QUIT).
    func delete(number):
        return self.command("DELE " + str(to_int(number)))

    func rset():
        return self.command("RSET")

    func noop():
        return self.command("NOOP")

    func quit():
        r := null
        try:
            r = self.command("QUIT")
        catch e:
            ignored := e
        self.close()
        return r

    func close():
        self.conn.close()

    func __enter__():
        return self

    func __exit__(t, v, tb):
        self.quit()
        return false
