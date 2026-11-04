# ALEX STANDARD LIBRARY — network.imap
#
# Client IMAP4rev1 (RFC 3501, avec IDLE RFC 2177, MOVE RFC 6851, LITERAL+ RFC 7888, UIDPLUS) : boîtes aux lettres,
# recherche, lecture, drapeaux, copie, déplacement, ajout, suppression ; STARTTLS ou TLS implicite (IMAPS, 993).
#
#   c := ImapClient("imap.exemple.org", 993)
#   c.login("moi", "secret")
#   for b in c.list() ...                       Mailbox(name, flags, delimiter) — noms en UTF-7 modifié décodés
#   info := c.select("INBOX")                   {"exists": 12, "uidvalidity": ..., "flags": [...], ...}
#   uids := c.search("UNSEEN SINCE 1-Oct-2026") identifiants UID
#   m := c.fetch_message(uids[0])               network.email.EmailMessage   (fetch(...) : données brutes)
#   c.add_flags(uids, ["\\Seen"]) ; c.move(uids, "Archives") ; c.append("Brouillons", octets, ["\\Draft"])
#   événements := c.idle(30.0)                  attend les nouvelles (EXISTS, EXPUNGE...) au plus 30 s
#   c.logout()
#
# Les identifiants sont des UID par défaut (stables) ; uid=false utilise les numéros de séquence.
#
# Erreurs : ImapError « imap : NO ... » / « imap : BAD ... », NetworkError, TimeoutError, TlsError.

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use network.core as _core
use network.encoding as _enc
use network.utils as _u
use network.email as _email
use network.mime as _mime

func _fail(message):
    raise("ImapError", "imap : " + message)

# ---------------------------------------------------------------- UTF-7 modifié (noms de boîtes, RFC 3501 §5.1.3)

func encode_mailbox(name):
    out := []
    pending := ""
    for c in name:
        o := _s.ord(c)
        if o >= 32 and o <= 126:
            if pending != "":
                append(out, "&" + _mb64(pending) + "-")
                pending = ""
            if c == '&':
                append(out, "&-")
            else:
                append(out, str(c))
        else:
            pending += str(c)
    if pending != "":
        append(out, "&" + _mb64(pending) + "-")
    return _s.join("", out)

func _mb64(text):
    b := _enc.base64_encode(_enc.encode_charset(text, "utf-16be"), false, false)
    return _s.replace(b, "/", ",")

func decode_mailbox(name):
    if not _s.contains(name, "&"):
        return name
    out := []
    i := 0
    n := len(name)
    while i < n:
        c := name[i]
        if c != '&':
            append(out, str(c))
            i += 1
            continue
        j := i + 1
        while j < n and name[j] != '-':
            j += 1
        chunk := _s.substring(name, i + 1, j)
        if chunk == "":
            append(out, "&")
        else:
            try:
                append(out, _enc.decode_charset(_enc.base64_decode(_s.replace(chunk, ",", "/")), "utf-16be"))
            catch e:
                append(out, "&" + chunk + "-")
        i = j + 1
    return _s.join("", out)

# ---------------------------------------------------------------- analyse des réponses

const _LIT := "\u{1}"

class _Tokens:
    func init(text, literals):
        self.text = text
        self.literals = literals
        self.pos = 0
        self.n = len(text)

    func skip_space():
        while self.pos < self.n and self.text[self.pos] == ' ':
            self.pos += 1

    func at_end():
        self.skip_space()
        return self.pos >= self.n

    # Valeur suivante : str, null (NIL), ou list (parenthèses).
    func value():
        self.skip_space()
        if self.pos >= self.n:
            return null
        c := self.text[self.pos]
        if c == '(':
            self.pos += 1
            out := []
            while true:
                self.skip_space()
                if self.pos >= self.n:
                    _fail("liste non fermée dans une réponse")
                if self.text[self.pos] == ')':
                    self.pos += 1
                    return out
                append(out, self.value())
        if c == '"':
            self.pos += 1
            buf := []
            while self.pos < self.n and self.text[self.pos] != '"':
                ch := self.text[self.pos]
                if ch == '\\' and self.pos + 1 < self.n:
                    self.pos += 1
                    ch = self.text[self.pos]
                append(buf, str(ch))
                self.pos += 1
            self.pos += 1
            return _s.join("", buf)
        if c == '\u{1}':
            e := self.pos + 1
            while self.text[e] != '\u{1}':
                e += 1
            idx := to_int(_s.substring(self.text, self.pos + 1, e))
            self.pos = e + 1
            return self.literals[idx]
        start := self.pos
        depth := 0
        while self.pos < self.n:
            ch := self.text[self.pos]
            if ch == '[':
                depth += 1
            elif ch == ']':
                depth -= 1
            elif depth == 0 and (ch == ' ' or ch == '(' or ch == ')'):
                break
            self.pos += 1
        atom := _s.substring(self.text, start, self.pos)
        if _s.upper(atom) == "NIL":
            return null
        return atom

    func rest():
        self.skip_space()
        return _s.substring(self.text, self.pos, self.n)

# Analyse un texte IMAP (sans littéraux) en valeurs : liste de str / null / list.
func parse_values(text, literals=null):
    t := _Tokens(text, literals)
    out := []
    while not t.at_end():
        append(out, t.value())
    return out

class Response:
    func init(text, literals):
        self.text = text              # ligne complète, littéraux remplacés par des marqueurs
        self.literals = literals      # octets des littéraux
        self.values = null

    func parsed():
        if self.values == null:
            self.values = parse_values(self.text, self.literals)
        return self.values

    # Texte lisible (littéraux réinsérés).
    func plain():
        out := self.text
        i := 0
        for l in self.literals:
            out = _s.replace(out, _LIT + str(i) + _LIT, l)
            i += 1
        return out

class Mailbox:
    func init(name, flags, delimiter):
        self.name = name              # nom décodé (Unicode)
        self.flags = flags            # « \HasNoChildren », « \Sent »...
        self.delimiter = delimiter

    func has_flag(f):
        for x in self.flags:
            if _s.lower(x) == _s.lower(f):
                return true
        return false

    func str():
        return self.name

func _quote(s):
    t := str(s)
    for c in t:
        if c == '\r' or c == '\n' or _s.ord(c) >= 128 or c == '\u{0}':
            return null      # littéral nécessaire
    return "\"" + _s.replace(_s.replace(t, "\\", "\\\\"), "\"", "\\\"") + "\""

# ---------------------------------------------------------------- client

class ImapClient:
    func init(host, port=993, ssl=null, starttls="auto", timeout=60.0, verify=true, ca_file=null, allow_plaintext_auth=false):
        self.host = host
        self.port = port
        if ssl == null:
            ssl = port == 993
        self.ssl = ssl
        self.secure = ssl
        self.timeout = timeout
        self.verify = verify
        self.ca_file = ca_file
        self.allow_plaintext_auth = allow_plaintext_auth
        self.tag_counter = 0
        self.capabilities = []
        self.state = "nonauth"
        self.selected = null
        self.mailbox_info = {}
        self.untagged = []            # réponses non sollicitées reçues en passant
        self.conn = _core.open_connection(host, port, ssl, timeout, verify, ca_file)
        try:
            g := self._read_response()
            if _s.starts_with(g.text, "* PREAUTH"):
                self.state = "auth"
            elif not _s.starts_with(g.text, "* OK"):
                _fail("accueil inattendu : " + g.plain())
            self.greeting = g.plain()
            self.capability()
            if not ssl and starttls != false:
                if self.has_capability("STARTTLS"):
                    self.starttls()
                elif starttls == true:
                    _fail("le serveur ne propose pas STARTTLS (exigé)")
        catch e:
            self.conn.close()
            raise(e)

    func _read_line():
        l := self.conn.read_line(self.timeout, 1048576)
        if l == null:
            _fail("connexion fermée par le serveur")
        return l

    # Une réponse complète (avec ses littéraux « {n} »).
    func _read_response():
        parts := []
        literals := []
        while true:
            line := self._read_line()
            if _s.ends_with(line, "}"):
                k := len(line) - 1
                while k >= 0 and line[k] != '{':
                    k -= 1
                if k >= 0:
                    num := _s.substring(line, k + 1, len(line) - 1)
                    if _s.ends_with(num, "+"):
                        num = _s.substring(num, 0, len(num) - 1)
                    digits := num != ""
                    for c in num:
                        if c < '0' or c > '9':
                            digits = false
                    if digits:
                        size := to_int(num)
                        append(parts, _s.substring(line, 0, k))
                        append(parts, _LIT + str(len(literals)) + _LIT)
                        append(literals, self.conn.read_exact(size, self.timeout))
                        continue
            append(parts, line)
            return Response(_s.join("", parts), literals)

    func _next_tag():
        self.tag_counter += 1
        t := str(self.tag_counter)
        while len(t) < 4:
            t = "0" + t
        return "A" + t

    func has_capability(name):
        for c in self.capabilities:
            if _s.upper(c) == _s.upper(name):
                return true
        return false

    # Envoie une commande ; args : list de str (atomes déjà formés) ou d'objets à citer (« quote(...) » auto pour
    # les chaînes non ASCII : littéraux). Rend (texte du statut, réponses non étiquetées).
    func command(name, args=null, literal_args=null):
        tag := self._next_tag()
        line := tag + " " + name
        pieces := []
        if args != null:
            for a in args:
                append(pieces, a)
        self._send_with_literals(line, pieces)
        untagged := []
        while true:
            r := self._read_response()
            if _s.starts_with(r.text, tag + " "):
                rest := _s.substring(r.text, len(tag) + 1, len(r.text))
                status := _s.upper(_s.split(rest, " ")[0])
                if status == "OK":
                    self._absorb(untagged, rest)
                    return (r.plain(), untagged)
                _fail(name + " : " + rest)
            if _s.starts_with(r.text, "+"):
                continue
            append(untagged, r)

    # Envoie une ligne de commande dont certains arguments sont des littéraux (octets) : ["lit", données].
    func _send_with_literals(head, pieces):
        buf := head
        for p in pieces:
            if type(p) == "list" and len(p) == 2 and p[0] == "lit":
                data := p[1]
                n := _n.blen(data)
                if self.has_capability("LITERAL+"):
                    self.conn.write(buf + " {" + str(n) + "+}\r\n" + data, self.timeout)
                else:
                    self.conn.write(buf + " {" + str(n) + "}\r\n", self.timeout)
                    cont := self._read_response()
                    if not _s.starts_with(cont.text, "+"):
                        _fail("littéral refusé : " + cont.plain())
                    self.conn.write(data, self.timeout)
                buf = ""
            else:
                _u.check_single_line(str(p), "argument IMAP")
                buf += " " + str(p)
        self.conn.write(buf + "\r\n", self.timeout)

    # Argument chaîne : cité, ou littéral si nécessaire.
    func _arg(s):
        q := _quote(s)
        if q == null:
            return ["lit", str(s)]
        return q

    func _absorb(untagged, tagged_text=null):
        for r in untagged:
            v := r.parsed()
            if len(v) >= 2 and v[0] == "*" and _s.upper(str(v[1])) == "CAPABILITY":
                self.capabilities = []
                for x in v[2:len(v)]:
                    append(self.capabilities, str(x))
            elif len(v) >= 2 and v[0] == "*" and _s.upper(str(v[1])) == "OK":
                self._caps_from_code(r.text)
        if tagged_text != null:
            self._caps_from_code(tagged_text)

    # Capacités annoncées dans un code de réponse « [CAPABILITY ...] ».
    func _caps_from_code(text):
        code := _bracket(text)
        if code == null or not _s.starts_with(_s.upper(code), "CAPABILITY "):
            return
        self.capabilities = []
        for x in _s.split(_s.substring(code, 11, len(code)), " "):
            if x != "":
                append(self.capabilities, x)

    func capability():
        r := self.command("CAPABILITY")
        return self.capabilities

    func starttls():
        self.command("STARTTLS")
        self.conn = _core.start_tls(self.conn, self.host, self.verify, self.ca_file, null, self.timeout)
        self.secure = true
        self.capability()

    func login(user, password):
        if not self.secure and not self.allow_plaintext_auth:
            _fail("mot de passe refusé sur une connexion non chiffrée (allow_plaintext_auth=true pour forcer)")
        if self.has_capability("LOGINDISABLED"):
            return self.authenticate_plain(user, password)
        r := self.command("LOGIN", [self._arg(user), self._arg(password)])
        self.state = "auth"
        if len(self.capabilities) == 0 or not _s.contains(r[0], "CAPABILITY"):
            self.capability()
        return r[0]

    # Authentification SASL PLAIN (ou XOAUTH2 avec un jeton) par AUTHENTICATE.
    func authenticate_plain(user, password, mechanism="PLAIN"):
        payload := ""
        if mechanism == "XOAUTH2":
            payload = _enc.base64_encode("user=" + user + "\u{1}auth=Bearer " + password + "\u{1}\u{1}")
        else:
            payload = _enc.base64_encode("\u{0}" + user + "\u{0}" + password)
        tag := self._next_tag()
        if self.has_capability("SASL-IR"):
            self.conn.write(tag + " AUTHENTICATE " + mechanism + " " + payload + "\r\n", self.timeout)
        else:
            self.conn.write(tag + " AUTHENTICATE " + mechanism + "\r\n", self.timeout)
            cont := self._read_response()
            if not _s.starts_with(cont.text, "+"):
                _fail("AUTHENTICATE : " + cont.plain())
            self.conn.write(payload + "\r\n", self.timeout)
        while true:
            r := self._read_response()
            if _s.starts_with(r.text, tag + " "):
                rest := _s.substring(r.text, len(tag) + 1, len(r.text))
                if _s.starts_with(_s.upper(rest), "OK"):
                    self.state = "auth"
                    self.capability()
                    return rest
                _fail("AUTHENTICATE : " + rest)
            if _s.starts_with(r.text, "+"):
                self.conn.write("\r\n", self.timeout)     # défi d'erreur XOAUTH2 : réponse vide

    func noop():
        r := self.command("NOOP")
        return r[1]

    # Boîtes aux lettres correspondant à `pattern` (« * » : toutes, « % » : un niveau).
    func list(reference="", pattern="*"):
        r := self.command("LIST", [self._arg(reference), self._arg(encode_mailbox(pattern))])
        out := []
        for resp in r[1]:
            v := resp.parsed()
            if len(v) >= 5 and _s.upper(str(v[1])) == "LIST":
                flags := v[2]
                if flags == null:
                    flags = []
                name := v[4]
                if name == null:
                    name = ""
                append(out, Mailbox(decode_mailbox(name), flags, v[3]))
        return out

    func _mailbox_info(untagged):
        info := {"exists": 0, "recent": 0, "flags": [], "permanent_flags": [], "uidvalidity": null, "uidnext": null, "unseen": null, "read_only": false}
        for resp in untagged:
            v := resp.parsed()
            if len(v) < 2 or v[0] != "*":
                continue
            if len(v) >= 3 and type(v[2]) == "str" and _s.upper(v[2]) == "EXISTS":
                info["exists"] = to_int(v[1])
            elif len(v) >= 3 and type(v[2]) == "str" and _s.upper(v[2]) == "RECENT":
                info["recent"] = to_int(v[1])
            elif _s.upper(str(v[1])) == "FLAGS" and len(v) >= 3:
                info["flags"] = v[2]
            elif _s.upper(str(v[1])) == "OK":
                code := _bracket(resp.text)
                if code != null:
                    p := _s.split(code, " ")
                    k := _s.upper(p[0])
                    if k == "UIDVALIDITY":
                        info["uidvalidity"] = to_int(p[1])
                    elif k == "UIDNEXT":
                        info["uidnext"] = to_int(p[1])
                    elif k == "UNSEEN":
                        info["unseen"] = to_int(p[1])
                    elif k == "PERMANENTFLAGS":
                        info["permanent_flags"] = parse_values(_s.substring(code, 15, len(code)))[0]
        return info

    # Sélectionne une boîte ; rend ses informations (exists, recent, flags, uidvalidity, uidnext...).
    func select(mailbox="INBOX", readonly=false):
        cmd := "SELECT"
        if readonly:
            cmd = "EXAMINE"
        r := self.command(cmd, [self._arg(encode_mailbox(mailbox))])
        info := self._mailbox_info(r[1])
        info["read_only"] = readonly or _s.contains(_s.upper(r[0]), "[READ-ONLY]")
        self.selected = mailbox
        self.mailbox_info = info
        self.state = "selected"
        return info

    func examine(mailbox="INBOX"):
        return self.select(mailbox, true)

    func close_mailbox():
        self.command("CLOSE")
        self.selected = null
        self.state = "auth"

    # STATUS d'une boîte : dict (messages, recent, uidnext, uidvalidity, unseen).
    func status(mailbox, items=null):
        it := items
        if it == null:
            it = ["MESSAGES", "RECENT", "UIDNEXT", "UIDVALIDITY", "UNSEEN"]
        r := self.command("STATUS", [self._arg(encode_mailbox(mailbox)), "(" + _s.join(" ", it) + ")"])
        out := {}
        for resp in r[1]:
            v := resp.parsed()
            if len(v) >= 4 and _s.upper(str(v[1])) == "STATUS":
                lst := v[3]
                i := 0
                while i + 1 < len(lst):
                    out[_s.lower(lst[i])] = to_int(lst[i + 1])
                    i += 2
        return out

    # Identifiants des messages qui répondent aux critères IMAP (« ALL », « UNSEEN », « FROM "x" SINCE 1-Oct-2026 »).
    func search(criteria="ALL", uid=true, charset=null):
        args := []
        if charset != null:
            append(args, "CHARSET")
            append(args, charset)
        append(args, criteria)
        cmd := "SEARCH"
        if uid:
            cmd = "UID SEARCH"
        r := self.command(cmd, args)
        out := []
        for resp in r[1]:
            v := resp.parsed()
            if len(v) >= 2 and _s.upper(str(v[1])) == "SEARCH":
                for x in v[2:len(v)]:
                    if type(x) == "str" and x != "" and x[0] >= '0' and x[0] <= '9':
                        append(out, to_int(x))
        return out

    # FETCH : dict identifiant -> dict élément -> valeur (« FLAGS » -> list, « RFC822.SIZE » -> int,
    # « BODY[] » / « RFC822 » -> octets, « ENVELOPE » -> dict, « UID » -> int...). ids : int, liste ou « 1:* ».
    func fetch(ids, items="(UID FLAGS RFC822.SIZE)", uid=true):
        cmd := "FETCH"
        if uid:
            cmd = "UID FETCH"
        r := self.command(cmd, [_id_set(ids), items])
        out := {}
        for resp in r[1]:
            v := resp.parsed()
            if len(v) >= 4 and _s.upper(str(v[2])) == "FETCH" and type(v[3]) == "list":
                data := {}
                lst := v[3]
                i := 0
                while i + 1 < len(lst):
                    k := _s.upper(str(lst[i]))
                    val := lst[i + 1]
                    if k == "UID" or k == "RFC822.SIZE" or k == "MODSEQ":
                        if type(val) == "str":
                            val = to_int(val)
                        elif type(val) == "list" and len(val) > 0:
                            val = to_int(val[0])
                    elif k == "ENVELOPE":
                        val = _envelope(val)
                    elif _s.starts_with(k, "BODY.PEEK"):
                        k = "BODY" + _s.substring(k, 9, len(k))
                    data[k] = val
                    i += 2
                key := to_int(v[1])
                if uid and contains_key(data, "UID"):
                    key = data["UID"]
                out[key] = data
        return out

    # Message complet (octets bruts) ; peek=true ne le marque pas comme lu.
    func fetch_raw(msg_id, uid=true, peek=true):
        item := "BODY[]"
        if peek:
            item = "BODY.PEEK[]"
        r := self.fetch(msg_id, "(" + item + ")", uid)
        for k in keys(r):
            if contains_key(r[k], "BODY[]"):
                return r[k]["BODY[]"]
        _fail("message " + str(msg_id) + " introuvable")

    func fetch_message(msg_id, uid=true, peek=true):
        return _email.parse(self.fetch_raw(msg_id, uid, peek))

    # En-têtes seuls (octets) de plusieurs messages : dict id -> en-têtes.
    func fetch_headers(ids, uid=true):
        r := self.fetch(ids, "(BODY.PEEK[HEADER])", uid)
        out := {}
        for k in keys(r):
            if contains_key(r[k], "BODY[HEADER]"):
                out[k] = r[k]["BODY[HEADER]"]
        return out

    # Modifie les drapeaux : mode "+FLAGS", "-FLAGS" ou "FLAGS" (remplacement).
    func store(ids, mode, flags, uid=true, silent=true):
        cmd := "STORE"
        if uid:
            cmd = "UID STORE"
        m := mode
        if silent:
            m += ".SILENT"
        return self.command(cmd, [_id_set(ids), m, "(" + _s.join(" ", flags) + ")"])

    func add_flags(ids, flags, uid=true):
        return self.store(ids, "+FLAGS", flags, uid)

    func remove_flags(ids, flags, uid=true):
        return self.store(ids, "-FLAGS", flags, uid)

    func copy(ids, mailbox, uid=true):
        cmd := "COPY"
        if uid:
            cmd = "UID COPY"
        return self.command(cmd, [_id_set(ids), self._arg(encode_mailbox(mailbox))])

    # Déplace (MOVE si le serveur le propose, sinon COPY + \Deleted + EXPUNGE).
    func move(ids, mailbox, uid=true):
        if self.has_capability("MOVE"):
            cmd := "MOVE"
            if uid:
                cmd = "UID MOVE"
            return self.command(cmd, [_id_set(ids), self._arg(encode_mailbox(mailbox))])
        self.copy(ids, mailbox, uid)
        self.add_flags(ids, ["\\Deleted"], uid)
        if uid and self.has_capability("UIDPLUS"):
            return self.command("UID EXPUNGE", [_id_set(ids)])
        return self.command("EXPUNGE")

    # Marque supprimés puis efface (expunge=true).
    func delete_messages(ids, uid=true, expunge=true):
        self.add_flags(ids, ["\\Deleted"], uid)
        if expunge:
            return self.expunge()

    func expunge():
        r := self.command("EXPUNGE")
        out := []
        for resp in r[1]:
            v := resp.parsed()
            if len(v) >= 3 and _s.upper(str(v[2])) == "EXPUNGE":
                append(out, to_int(v[1]))
        return out

    # Ajoute un message (octets) à une boîte ; flags : list ; date : horodatage (INTERNALDATE) ou null.
    func append(mailbox, message, flags=null, date=null):
        raw := message
        if not (type(message) == "str"):
            raw = message.to_bytes()
        raw = _u.to_crlf(raw)
        args := [self._arg(encode_mailbox(mailbox))]
        if flags != null:
            append(args, "(" + _s.join(" ", flags) + ")")
        if date != null:
            append(args, "\"" + _internal_date(date) + "\"")
        append(args, ["lit", raw])
        return self.command("APPEND", args)[0]

    func create(mailbox):
        return self.command("CREATE", [self._arg(encode_mailbox(mailbox))])[0]

    func delete_mailbox(mailbox):
        return self.command("DELETE", [self._arg(encode_mailbox(mailbox))])[0]

    func rename(old, new_name):
        return self.command("RENAME", [self._arg(encode_mailbox(old)), self._arg(encode_mailbox(new_name))])[0]

    func subscribe(mailbox):
        return self.command("SUBSCRIBE", [self._arg(encode_mailbox(mailbox))])[0]

    # Attend des notifications (IDLE) au plus `timeout` secondes, ou jusqu'à la première si stop_on_first ;
    # rend la liste des réponses non étiquetées (texte : « 3 EXISTS », « 2 EXPUNGE »...).
    func idle(timeout=60.0, stop_on_first=true):
        if not self.has_capability("IDLE"):
            _fail("le serveur ne propose pas IDLE")
        tag := self._next_tag()
        self.conn.write(tag + " IDLE\r\n", self.timeout)
        cont := self._read_response()
        if not _s.starts_with(cont.text, "+"):
            _fail("IDLE refusé : " + cont.plain())
        events := []
        end := _time.monotonic() + timeout
        while true:
            left := end - _time.monotonic()
            if left <= 0:
                break
            line := null
            try:
                line = self.conn.read_line(left, 65536)
            catch e:
                if e.type == "TimeoutError":
                    break
                raise(e)
            if line == null:
                _fail("connexion fermée pendant IDLE")
            if _s.starts_with(line, "* "):
                append(events, _s.substring(line, 2, len(line)))
                if stop_on_first:
                    break
        self.conn.write("DONE\r\n", self.timeout)
        while true:
            r := self._read_response()
            if _s.starts_with(r.text, tag + " "):
                break
            if _s.starts_with(r.text, "* "):
                append(events, _s.substring(r.text, 2, len(r.text)))
        return events

    func logout():
        try:
            self.command("LOGOUT")
        catch e:
            ignored := e
        self.close()

    func close():
        self.conn.close()

    func __enter__():
        return self

    func __exit__(t, v, tb):
        self.logout()
        return false

func _bracket(text):
    a := _s.find(text, "[")
    if a < 0:
        return null
    depth := 0
    i := a
    while i < len(text):
        if text[i] == '[':
            depth += 1
        elif text[i] == ']':
            depth -= 1
            if depth == 0:
                return _s.substring(text, a + 1, i)
        i += 1
    return null

# Ensemble d'identifiants : 5, [1, 2, 9], « 1:* ».
func _id_set(ids):
    if type(ids) == "int":
        return str(ids)
    if type(ids) == "str":
        for c in ids:
            if not ((c >= '0' and c <= '9') or c == ':' or c == ',' or c == '*'):
                _fail("ensemble d'identifiants invalide « " + ids + " »")
        return ids
    parts := []
    for x in ids:
        append(parts, str(to_int(x)))
    if len(parts) == 0:
        _fail("ensemble d'identifiants vide")
    return _s.join(",", parts)

const _MONTHS := ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]

func _internal_date(ts):
    secs := to_int(ts)
    days := secs // 86400
    rem := secs - days * 86400
    ymd := _time.civil_from_days(days)
    d := str(ymd[2])
    if len(d) < 2:
        d = " " + d
    return d + "-" + _MONTHS[ymd[1] - 1] + "-" + str(ymd[0]) + " " + _two(rem // 3600) + ":" + _two((rem % 3600) // 60) + ":" + _two(rem % 60) + " +0000"

func _two(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

# Date de recherche IMAP (« 11-Oct-2026 ») d'un horodatage.
func search_date(ts):
    days := to_int(ts) // 86400
    ymd := _time.civil_from_days(days)
    return str(ymd[2]) + "-" + _MONTHS[ymd[1] - 1] + "-" + str(ymd[0])

func _addresses(v):
    out := []
    if v == null:
        return out
    for a in v:
        if type(a) != "list" or len(a) < 4:
            continue
        if a[2] == null or a[3] == null:
            continue
        name := a[0]
        if name == null:
            name = ""
        append(out, _email.Address(_mime.decode_header(name), a[2] + "@" + a[3]))
    return out

func _envelope(v):
    if type(v) != "list" or len(v) < 10:
        return null
    subj := v[1]
    if subj != null:
        subj = _mime.decode_header(subj)
    return {"date": v[0], "subject": subj, "from": _addresses(v[2]), "sender": _addresses(v[3]), "reply_to": _addresses(v[4]), "to": _addresses(v[5]), "cc": _addresses(v[6]), "bcc": _addresses(v[7]), "in_reply_to": v[8], "message_id": v[9]}
