# ALEX STANDARD LIBRARY — network.smtp
#
# Client SMTP (RFC 5321) pour envoyer des courriels : EHLO et extensions, STARTTLS (RFC 3207) ou TLS implicite
# (SMTPS, port 465), authentification (PLAIN, LOGIN, CRAM-MD5, XOAUTH2), SIZE, 8BITMIME, SMTPUTF8, transparence des
# points (« dot-stuffing »), destinataires refusés.
#
#   c := SmtpClient("smtp.exemple.org", 587)      se connecte, EHLO, STARTTLS si proposé (starttls="auto")
#   c.login("moi", "mot de passe")
#   refusés := c.send_message(message)             network.email.EmailMessage (Bcc compris dans l'enveloppe)
#   c.send("moi@x.org", ["toi@y.org"], octets)     envoi brut
#   c.quit()
#   send_mail(hôte, port, message, utilisateur, mot_de_passe)     tout en un
#
# Sécurité : starttls="auto" chiffre dès que le serveur le propose ; starttls=true l'exige (erreur sinon) ;
# l'authentification est refusée sur un canal en clair sauf allow_plaintext_auth=true. Les octets reçus en clair
# avant la négociation TLS sont rejetés (network.core.start_tls).
#
# Erreurs : SmtpError « smtp : 550 ... » (code de réponse : network.errors.reply_code), NetworkError,
# TimeoutError, TlsError.

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use os as _os
use crypto as _crypto
use network.core as _core
use network.encoding as _enc
use network.utils as _u
use network.email as _email

func _fail(message):
    raise("SmtpError", "smtp : " + message)

class Reply:
    func init(code, lines):
        self.code = code
        self.lines = lines            # textes des lignes (sans le code)

    func text():
        return _s.join("\n", self.lines)

    func ok():
        return self.code >= 200 and self.code < 400

    func str():
        return str(self.code) + " " + self.text()

class SmtpClient:
    # host / port : serveur (port 25 relais, 587 soumission avec STARTTLS, 465 TLS implicite).
    # ssl : TLS dès la connexion ; starttls : "auto", true ou false ; local_hostname : nom annoncé par EHLO.
    func init(host, port=587, ssl=null, starttls="auto", timeout=30.0, local_hostname=null, verify=true, ca_file=null, allow_plaintext_auth=false):
        self.host = host
        self.port = port
        if ssl == null:
            ssl = port == 465
        self.ssl = ssl
        self.starttls_mode = starttls
        self.timeout = timeout
        self.local_hostname = local_hostname
        if local_hostname == null:
            self.local_hostname = _local_name()
        self.verify = verify
        self.ca_file = ca_file
        self.allow_plaintext_auth = allow_plaintext_auth
        self.extensions = {}          # nom en majuscules -> paramètres (str)
        self.esmtp = false
        self.greeting = null
        self.authenticated = false
        self.secure = ssl
        self.last_reply = null
        self.conn = _core.open_connection(host, port, ssl, timeout, verify, ca_file)
        try:
            self.greeting = self._expect([220], "accueil")
            self.ehlo()
            if not self.ssl and self.starttls_mode != false:
                if self.has_extension("STARTTLS"):
                    self.starttls()
                elif self.starttls_mode == true:
                    _fail("le serveur ne propose pas STARTTLS (exigé)")
        catch e:
            self.conn.close()
            raise(e)

    # Lit une réponse (éventuellement sur plusieurs lignes « 250-... »).
    func read_reply():
        lines := []
        code := 0
        while true:
            line := self.conn.read_line(self.timeout, 65536)
            if line == null:
                _fail("connexion fermée par le serveur")
            if len(line) < 3:
                _fail("réponse invalide « " + line + " »")
            c := _s.substring(line, 0, 3)
            for ch in c:
                if ch < '0' or ch > '9':
                    _fail("réponse invalide « " + line + " »")
            code = to_int(c)
            append(lines, _s.substring(line, 4, len(line)) if len(line) > 4 else "")
            if len(line) == 3 or line[3] == ' ':
                break
            if line[3] != '-':
                _fail("réponse invalide « " + line + " »")
        r := Reply(code, lines)
        self.last_reply = r
        return r

    func _expect(codes, what):
        r := self.read_reply()
        for c in codes:
            if r.code == c:
                return r
        _fail(what + " : " + str(r.code) + " " + r.text())

    # Envoie une commande (une ligne) et lit la réponse.
    func command(line):
        _u.check_single_line(line, "commande SMTP")
        self.conn.write(line + "\r\n", self.timeout)
        return self.read_reply()

    func ehlo():
        r := self.command("EHLO " + self.local_hostname)
        if r.code != 250:
            r = self.command("HELO " + self.local_hostname)
            if r.code != 250:
                _fail("HELO refusé : " + r.str())
            self.esmtp = false
            self.extensions = {}
            return r
        self.esmtp = true
        self.extensions = {}
        i := 0
        for l in r.lines:
            if i > 0:
                sp := _s.find(l, " ")
                name := l
                params := ""
                if sp > 0:
                    name = _s.substring(l, 0, sp)
                    params = _s.trim(_s.substring(l, sp + 1, len(l)))
                self.extensions[_s.upper(name)] = params
            i += 1
        return r

    func has_extension(name):
        return contains_key(self.extensions, _s.upper(name))

    # Mécanismes d'authentification annoncés (AUTH).
    func auth_mechanisms():
        if not self.has_extension("AUTH"):
            return []
        out := []
        for m in _s.split(self.extensions["AUTH"], " "):
            if m != "":
                append(out, _s.upper(m))
        return out

    # Taille maximale annoncée (SIZE), ou null.
    func max_size():
        if not self.has_extension("SIZE"):
            return null
        v := _s.trim(self.extensions["SIZE"])
        if v == "" or v == "0":
            return null
        return to_int(v)

    func starttls():
        r := self.command("STARTTLS")
        if r.code != 220:
            _fail("STARTTLS refusé : " + r.str())
        self.conn = _core.start_tls(self.conn, self.host, self.verify, self.ca_file, null, self.timeout)
        self.secure = true
        self.ehlo()      # les extensions peuvent changer une fois chiffré

    # Authentification ; mechanism : "PLAIN", "LOGIN", "CRAM-MD5", "XOAUTH2" (password = jeton) ou null (le
    # meilleur proposé).
    func login(user, password, mechanism=null):
        if not self.secure and not self.allow_plaintext_auth:
            _fail("authentification refusée sur une connexion non chiffrée (allow_plaintext_auth=true pour forcer)")
        mechs := self.auth_mechanisms()
        mech := mechanism
        if mech == null:
            for cand in ["CRAM-MD5", "PLAIN", "LOGIN"]:
                if mech == null:
                    for m in mechs:
                        if m == cand:
                            mech = cand
            if mech == null:
                if len(mechs) == 0:
                    _fail("le serveur n'annonce aucune authentification (AUTH)")
                _fail("aucun mécanisme d'authentification commun (proposés : " + _s.join(" ", mechs) + ")")
        mech = _s.upper(mech)
        r := null
        if mech == "PLAIN":
            r = self.command("AUTH PLAIN " + _enc.base64_encode("\u{0}" + user + "\u{0}" + password))
        elif mech == "LOGIN":
            r = self.command("AUTH LOGIN")
            if r.code != 334:
                _fail("AUTH LOGIN : " + r.str())
            r = self.command(_enc.base64_encode(user))
            if r.code != 334:
                _fail("AUTH LOGIN : " + r.str())
            r = self.command(_enc.base64_encode(password))
        elif mech == "CRAM-MD5":
            r = self.command("AUTH CRAM-MD5")
            if r.code != 334:
                _fail("AUTH CRAM-MD5 : " + r.str())
            challenge := _enc.base64_decode(r.text())
            digest := _crypto.hmac("md5", _n.to_bytes(password), _n.to_bytes(challenge))
            r = self.command(_enc.base64_encode(user + " " + digest))
        elif mech == "XOAUTH2":
            r = self.command("AUTH XOAUTH2 " + _enc.base64_encode("user=" + user + "\u{1}auth=Bearer " + password + "\u{1}\u{1}"))
            if r.code == 334:
                r = self.command("")
        else:
            _fail("mécanisme d'authentification non pris en charge « " + mech + " »")
        if r.code != 235:
            _fail("authentification refusée : " + r.str())
        self.authenticated = true
        return r

    # Envoie des octets bruts (message RFC 5322) ; rend le dict des destinataires refusés (adresse -> Reply).
    # Lève SmtpError si l'expéditeur ou TOUS les destinataires sont refusés, ou si DATA échoue.
    func send(sender, recipients, data):
        rcpts := recipients
        if type(recipients) == "str":
            rcpts = [recipients]
        if len(rcpts) == 0:
            _fail("aucun destinataire")
        raw := _u.raw(data)
        params := ""
        size := _n.blen(raw)
        limit := self.max_size()
        if limit != null and size > limit:
            _fail("message de " + str(size) + " octets au-delà de la limite du serveur (" + str(limit) + ")")
        if self.has_extension("SIZE"):
            params += " SIZE=" + str(size)
        eight := false
        for b in _n.to_bytes(raw):
            if b >= 128:
                eight = true
                break
        if eight and self.has_extension("8BITMIME"):
            params += " BODY=8BITMIME"
        utf8 := _needs_utf8(sender) or _any_utf8(rcpts)
        if utf8:
            if not self.has_extension("SMTPUTF8"):
                _fail("adresse non ASCII sans extension SMTPUTF8 du serveur")
            params += " SMTPUTF8"
        r := self.command("MAIL FROM:<" + _addr(sender) + ">" + params)
        if r.code != 250:
            self._reset()
            _fail("expéditeur refusé : " + r.str())
        refused := {}
        accepted := 0
        for rc in rcpts:
            a := _addr(rc)
            rr := self.command("RCPT TO:<" + a + ">")
            if rr.code == 250 or rr.code == 251:
                accepted += 1
            else:
                refused[a] = rr
        if accepted == 0:
            self._reset()
            _fail("tous les destinataires ont été refusés : " + _refused_text(refused))
        r = self.command("DATA")
        if r.code != 354:
            self._reset()
            _fail("DATA refusé : " + r.str())
        self.conn.write(dot_stuff(raw) + ".\r\n", self.timeout)
        r = self.read_reply()
        if r.code != 250:
            _fail("message refusé : " + r.str())
        return refused

    # Envoie un network.email.EmailMessage (enveloppe : From et To + Cc + Bcc).
    func send_message(message, sender=null, recipients=null):
        s := sender
        if s == null:
            if message.sender == null:
                _fail("message sans expéditeur")
            s = message.sender.email
        rc := recipients
        if rc == null:
            rc = message.recipients()
        return self.send(s, rc, message.to_bytes())

    func _reset():
        try:
            self.command("RSET")
        catch e:
            ignored := e

    func noop():
        return self.command("NOOP")

    func rset():
        return self.command("RSET")

    # Vérifie une adresse (VRFY ; souvent désactivé).
    func verify_address(address):
        return self.command("VRFY " + _addr(address))

    func quit():
        try:
            self.command("QUIT")
        catch e:
            ignored := e
        self.close()

    func close():
        self.conn.close()

    func __enter__():
        return self

    func __exit__(t, v, tb):
        self.quit()
        return false

func _local_name():
    h := _os.hostname()
    if h == null or h == "":
        return "localhost"
    if not _s.contains(h, "."):
        return "[" + _u.local_ip() + "]"
    return h

func _addr(x):
    if isinstance(x, _email.Address):
        return _u.check_single_line(x.email, "adresse")
    a := _email.parse_address(str(x))
    if a == null:
        _fail("adresse vide")
    if _s.contains(a.email, "<") or _s.contains(a.email, ">"):
        _fail("adresse invalide « " + a.email + " »")
    return _u.check_single_line(a.email, "adresse")

func _needs_utf8(x):
    for c in _addr(x):
        if _s.ord(c) >= 128:
            return true
    return false

func _any_utf8(xs):
    for x in xs:
        if _needs_utf8(x):
            return true
    return false

func _refused_text(refused):
    out := []
    for k in keys(refused):
        append(out, k + " (" + refused[k].str() + ")")
    return _s.join(", ", out)

# Fins de ligne normalisées en CRLF et points de début de ligne doublés (RFC 5321 §4.5.2) ; le résultat se termine
# par CRLF.
func dot_stuff(data):
    t := _u.to_crlf(data)
    if _s.starts_with(t, "."):
        t = "." + t
    t = _s.replace(t, "\r\n.", "\r\n..")
    if not _s.ends_with(t, "\r\n"):
        t += "\r\n"
    return t

# Envoie un message en une fois (connexion, authentification si user est donné, envoi, QUIT).
func send_mail(host, port, message, user=null, password=null, ssl=null, starttls="auto", timeout=30.0, verify=true, ca_file=null):
    c := SmtpClient(host, port, ssl, starttls, timeout, null, verify, ca_file)
    try:
        if user != null:
            c.login(user, password)
        refused := c.send_message(message)
        c.quit()
        return refused
    catch e:
        c.close()
        raise(e)
