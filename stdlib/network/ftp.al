# ALEX STANDARD LIBRARY — network.ftp
#
# Client FTP (RFC 959, avec EPSV/EPRT RFC 2428, MLSD/SIZE/MDTM RFC 3659, FTPS RFC 4217) : navigation, listes,
# téléchargements et envois binaires, renommage, suppression, dossiers ; mode passif (défaut) ou actif ; TLS
# explicite (AUTH TLS, port 21) ou implicite (port 990), canal de données chiffré (PROT P).
#
#   f := FtpClient("ftp.exemple.org")            se connecte (tls="explicit" pour FTPS)
#   f.login("moi", "secret")                     sans argument : anonyme
#   f.cwd("/pub") ; print(f.pwd())
#   for e in f.mlsd() ...                        Entry(name, type "file"/"dir", size, modified, facts)
#   octets := f.retrieve("fichier.zip")          f.download("distant", "local") / f.upload("local", "distant")
#   f.store("note.txt", "contenu") ; f.rename("a", "b") ; f.delete("b") ; f.mkd("d") ; f.rmd("d")
#   f.quit()
#
# Le mode passif utilise EPSV, puis PASV ; l'adresse annoncée par PASV est ignorée au profit de l'hôte du canal de
# commande (protection contre le « FTP bounce » et les adresses privées derrière un NAT).
#
# Limite : certains serveurs FTPS exigent que la session TLS du canal de données reprenne celle du canal de
# commande (« session reuse ») ; la reprise de session n'est pas prise en charge.
#
# Erreurs : FtpError « ftp : 550 ... » (code : network.errors.reply_code), NetworkError, TimeoutError, TlsError.

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use io as _io
use time as _time
use network.tcp as _tcp
use network.tls as _tls
use network.core as _core
use network.utils as _u
use network.dns as _dns
use network.encoding as _enc

func _fail(message):
    raise("FtpError", "ftp : " + message)

class Reply:
    func init(code, lines):
        self.code = code
        self.lines = lines

    func text():
        return _s.join("\n", self.lines)

    func str():
        return str(self.code) + " " + self.text()

class Entry:
    func init(name, kind, size, modified, facts):
        self.name = name
        self.type = kind              # "file", "dir", "cdir", "pdir", "link" ou autre
        self.size = size              # octets ou null
        self.modified = modified      # horodatage Unix ou null
        self.facts = facts            # dict des faits MLSD (minuscules)

    func is_dir():
        return self.type == "dir"

    func is_file():
        return self.type == "file"

    func str():
        return self.name

class FtpClient:
    # tls : "none", "explicit" (AUTH TLS) ou "implicit" (port 990) ; passive : mode passif ;
    # encoding : jeu de caractères des noms de fichiers sur le serveur.
    func init(host, port=null, timeout=30.0, tls="none", passive=true, verify=true, ca_file=null, encoding="utf-8"):
        self.host = host
        self.tls_mode = tls
        self.port = port
        if port == null:
            self.port = 21
            if tls == "implicit":
                self.port = 990
        self.timeout = timeout
        self.passive = passive
        self.verify = verify
        self.ca_file = ca_file
        self.encoding = encoding
        self.protect_data = false
        self.features = {}
        self.last_reply = null
        self.secure = tls == "implicit"
        self.conn = _core.open_connection(host, self.port, tls == "implicit", timeout, verify, ca_file)
        try:
            self.welcome = self._expect([220], "accueil").text()
            if tls == "explicit":
                self.auth_tls()
        catch e:
            self.conn.close()
            raise(e)

    func read_reply():
        line := self.conn.read_line(self.timeout, 65536)
        if line == null:
            _fail("connexion fermée par le serveur")
        if len(line) < 3:
            _fail("réponse invalide « " + line + " »")
        code := _s.substring(line, 0, 3)
        for c in code:
            if c < '0' or c > '9':
                _fail("réponse invalide « " + line + " »")
        lines := [_s.substring(line, 4, len(line)) if len(line) > 4 else ""]
        if len(line) > 3 and line[3] == '-':
            # réponse multiligne : jusqu'à « code<espace> »
            while true:
                l := self.conn.read_line(self.timeout, 65536)
                if l == null:
                    _fail("connexion fermée au milieu d'une réponse")
                if _s.starts_with(l, code + " ") or l == code:
                    append(lines, _s.substring(l, 4, len(l)) if len(l) > 4 else "")
                    break
                append(lines, l)
        r := Reply(to_int(code), lines)
        self.last_reply = r
        return r

    func _expect(codes, what):
        r := self.read_reply()
        for c in codes:
            if r.code == c:
                return r
        _fail(what + " : " + r.str())

    func send_command(line):
        _u.check_single_line(line, "commande FTP")
        self.conn.write(line + "\r\n", self.timeout)

    # Commande ; rend la réponse (sans contrôle du code).
    func command(line):
        self.send_command(line)
        return self.read_reply()

    # Commande dont la réponse doit être positive (2xx, ou 3xx si allow_intermediate).
    func _ok(line, what=null, allow_intermediate=false):
        r := self.command(line)
        if r.code >= 200 and r.code < 300:
            return r
        if allow_intermediate and r.code >= 300 and r.code < 400:
            return r
        w := what
        if w == null:
            w = _s.split(line, " ")[0]
        _fail(w + " : " + r.str())

    func auth_tls():
        r := self.command("AUTH TLS")
        if r.code != 234:
            _fail("AUTH TLS refusé : " + r.str())
        self.conn = _core.start_tls(self.conn, self.host, self.verify, self.ca_file, null, self.timeout)
        self.secure = true

    # Connexion (anonyme par défaut). Avec TLS, protège aussi le canal de données (PBSZ 0, PROT P).
    func login(user="anonymous", password="anonymous@", account=null):
        r := self.command("USER " + user)
        if r.code == 331:
            r = self.command("PASS " + password)
        if r.code == 332:
            if account == null:
                _fail("le serveur demande un compte (ACCT)")
            r = self.command("ACCT " + account)
        if r.code != 230 and r.code != 202:
            _fail("connexion refusée : " + r.str())
        if self.secure:
            self._ok("PBSZ 0")
            self._ok("PROT P")
            self.protect_data = true
        try:
            self.feat()
        catch e:
            ignored := e
        if contains_key(self.features, "UTF8"):
            try:
                self.command("OPTS UTF8 ON")
            catch e:
                ignored := e
        return r.text()

    # Extensions annoncées (FEAT) : dict nom -> paramètres.
    func feat():
        r := self.command("FEAT")
        self.features = {}
        if r.code != 211:
            return self.features
        i := 0
        for l in r.lines:
            if i > 0 and i < len(r.lines) - 1:
                t := _s.trim(l)
                sp := _s.find(t, " ")
                if sp > 0:
                    self.features[_s.upper(_s.substring(t, 0, sp))] = _s.substring(t, sp + 1, len(t))
                elif t != "":
                    self.features[_s.upper(t)] = ""
            i += 1
        return self.features

    func has_feature(name):
        return contains_key(self.features, _s.upper(name))

    func pwd():
        r := self._ok("PWD")
        t := r.text()
        a := _s.find(t, "\"")
        if a < 0:
            return t
        # « "/a ""b"" c" » : guillemets doublés
        out := []
        i := a + 1
        while i < len(t):
            if t[i] == '"':
                if i + 1 < len(t) and t[i + 1] == '"':
                    append(out, "\"")
                    i += 2
                    continue
                break
            append(out, str(t[i]))
            i += 1
        return _s.join("", out)

    func cwd(path):
        if path == "..":
            return self._ok("CDUP").text()
        return self._ok("CWD " + path).text()

    func cdup():
        return self._ok("CDUP").text()

    func mkd(path):
        return self._ok("MKD " + path).text()

    func rmd(path):
        return self._ok("RMD " + path).text()

    func delete(path):
        return self._ok("DELE " + path).text()

    func rename(src, dst):
        r := self.command("RNFR " + src)
        if r.code != 350:
            _fail("RNFR : " + r.str())
        return self._ok("RNTO " + dst).text()

    # Taille d'un fichier (SIZE, en mode binaire), ou null si le serveur ne la donne pas.
    func size(path):
        self._ok("TYPE I")
        r := self.command("SIZE " + path)
        if r.code != 213:
            return null
        return to_int(_s.trim(r.text()))

    # Date de modification (MDTM) en horodatage Unix (UTC), ou null.
    func mdtm(path):
        r := self.command("MDTM " + path)
        if r.code != 213:
            return null
        return parse_time(_s.trim(r.text()))

    func syst():
        return self._ok("SYST").text()

    func noop():
        return self._ok("NOOP").text()

    func site(args):
        return self._ok("SITE " + args).text()

    # ---------------------------------------------------------------- canal de données

    func _open_data():
        if self.passive:
            r := self.command("EPSV")
            port := null
            host := self.conn.peer_address()[0]
            if r.code == 229:
                t := r.text()
                a := _s.find(t, "(")
                b := _s.find(t, ")")
                if a >= 0 and b > a:
                    inner := _s.substring(t, a + 1, b)
                    parts := _s.split(inner, _s.substring(inner, 0, 1))
                    if len(parts) >= 4 and parts[3] != "":
                        port = to_int(parts[3])
            if port == null:
                r = self.command("PASV")
                if r.code != 227:
                    _fail("mode passif refusé : " + r.str())
                nums := _numbers(r.text())
                if len(nums) < 6:
                    _fail("réponse PASV illisible : " + r.str())
                port = nums[4] * 256 + nums[5]
            return ["passive", _tcp.connect(host, port, self.timeout)]
        # mode actif : on écoute, le serveur se connecte
        local := self.conn.local_address()[0]
        listener := _tcp.listen(local, 0, 1)
        p := listener.port()
        r := null
        if _dns.is_ipv6(local):
            r = self.command("EPRT |2|" + local + "|" + str(p) + "|")
        else:
            r = self.command("EPRT |1|" + local + "|" + str(p) + "|")
            if r.code >= 500:
                r = self.command("PORT " + _s.replace(local, ".", ",") + "," + str(p >> 8) + "," + str(p & 255))
        if r.code != 200:
            listener.close()
            _fail("mode actif refusé : " + r.str())
        return ["active", listener]

    func _data_conn(handle):
        conn := null
        if handle[0] == "active":
            conn = handle[1].accept(self.timeout)
            handle[1].close()
        else:
            conn = handle[1]
        if self.protect_data:
            try:
                # la fin d'un transfert est confirmée par la réponse 226 du canal de commande : une fermeture du canal
                # de données sans close_notify (fréquente chez les serveurs FTP) est acceptée
                ts := _tls.wrap_client(conn.socket, self.host, self.verify, self.ca_file, null, self.timeout, null, null, false)
                conn = _tcp.Connection(ts)
            catch e:
                conn.close()
                raise(e)
        return conn

    # Transfert : commande `line` sur un canal de données ; reader(conn) lit, writer(conn) écrit.
    func _transfer(line, binary, reader=null, writer=null, rest=null):
        if binary:
            self._ok("TYPE I")
        else:
            self._ok("TYPE A")
        handle := self._open_data()
        if rest != null:
            r0 := self.command("REST " + str(rest))
            if r0.code != 350:
                self._close_handle(handle)
                _fail("REST refusé : " + r0.str())
        r := self.command(line)
        if r.code != 125 and r.code != 150:
            self._close_handle(handle)
            _fail(_s.split(line, " ")[0] + " : " + r.str())
        conn := self._data_conn(handle)
        result := null
        try:
            if reader != null:
                result = reader(conn)
            if writer != null:
                result = writer(conn)
        catch e:
            conn.close()
            raise(e)
        if writer != null:
            try:
                conn.socket.shutdown("write")
            catch e:
                ignored := e
        conn.close()
        done := self.read_reply()
        if done.code != 226 and done.code != 250:
            _fail(_s.split(line, " ")[0] + " : " + done.str())
        return result

    func _close_handle(handle):
        try:
            handle[1].close()
        catch e:
            ignored := e

    # Contenu d'un fichier (octets bruts).
    func retrieve(path, offset=null):
        return self._transfer("RETR " + path, true, (c) => c.read_all(self.timeout), null, offset)

    # Télécharge un fichier distant vers un fichier local (en flux) ; rend le nombre d'octets.
    func download(remote, local, resume=false):
        start := null
        if resume and _io.file_exists(local):
            start = _local_size(local)
        else:
            _io.write_bytes(local, [])
        me := self
        return self._transfer("RETR " + remote, true, (c) => _copy_to_file(c, local, start, me.timeout), null, start)

    # Envoie des octets dans un fichier distant (STOR, ou APPE si append=true).
    func store(path, data, append_mode=false):
        cmd := "STOR "
        if append_mode:
            cmd = "APPE "
        raw := _u.raw(data)
        self._transfer(cmd + path, true, null, (c) => c.write(raw, self.timeout))
        return _n.blen(raw)

    # Envoie un fichier local ; rend le nombre d'octets.
    func upload(local, remote=null):
        r := remote
        if r == null:
            k := len(local) - 1
            while k >= 0 and local[k] != '/':
                k -= 1
            r = _s.substring(local, k + 1, len(local))
        me := self
        return self._transfer("STOR " + r, true, null, (c) => _copy_from_file(c, local, me.timeout))

    # Liste brute (LIST) : lignes telles que le serveur les formate.
    func list_lines(path=null):
        line := "LIST"
        if path != null:
            line += " " + path
        raw := self._transfer(line, false, (c) => c.read_all(self.timeout))
        return _u.split_lines(raw)

    # Noms des entrées (NLST).
    func nlst(path=null):
        line := "NLST"
        if path != null:
            line += " " + path
        out := []
        for l in _u.split_lines(self._transfer(line, false, (c) => c.read_all(self.timeout))):
            if l != "":
                append(out, l)
        return out

    # Entrées détaillées (MLSD, faits normalisés) ; sans MLSD, repli sur LIST au format Unix.
    func mlsd(path=null, include_special=false):
        if self.has_feature("MLST") or len(self.features) == 0:
            line := "MLSD"
            if path != null:
                line += " " + path
            try:
                raw := self._transfer(line, false, (c) => c.read_all(self.timeout))
                out := []
                for l in _u.split_lines(raw):
                    e := parse_mlsd_line(l)
                    if e != null and (include_special or (e.type != "cdir" and e.type != "pdir")):
                        append(out, e)
                return out
            catch e:
                if e.type != "FtpError":
                    raise(e)
        out := []
        for l in self.list_lines(path):
            e := parse_list_line(l)
            if e != null:
                append(out, e)
        return out

    # Noms des entrées d'un dossier (MLSD, NLST en repli).
    func listdir(path=null):
        out := []
        for e in self.mlsd(path):
            append(out, e.name)
        return out

    func exists(path):
        r := self.command("SIZE " + path)
        if r.code == 213:
            return true
        r = self.command("MLST " + path)
        return r.code == 250

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

func _local_size(path):
    return len(_io.read_bytes(path))

func _copy_to_file(conn, path, start, timeout):
    pos := 0
    if start != null:
        pos = start
    total := 0
    while true:
        d := conn.read(262144, timeout)
        if d == "":
            return total
        _io.write_bytes_at(path, _n.to_bytes(d), pos)
        pos += _n.blen(d)
        total += _n.blen(d)

func _copy_from_file(conn, path, timeout):
    pos := 0
    while true:
        chunk := _io.read_bytes(path, pos, 262144)
        if len(chunk) == 0:
            return pos
        conn.write(_n.from_bytes(chunk), timeout)
        pos += len(chunk)

func _numbers(text):
    out := []
    cur := ""
    for c in text:
        if c >= '0' and c <= '9':
            cur += str(c)
        else:
            if cur != "":
                append(out, to_int(cur))
                cur = ""
    if cur != "":
        append(out, to_int(cur))
    # PASV : les 6 derniers nombres
    if len(out) > 6:
        return out[len(out) - 6:len(out)]
    return out

# Horodatage Unix d'une date FTP « YYYYMMDDHHMMSS[.sss] » (UTC).
func parse_time(text):
    t := text
    dot := _s.find(t, ".")
    if dot >= 0:
        t = _s.substring(t, 0, dot)
    if len(t) < 14:
        return null
    for c in t:
        if c < '0' or c > '9':
            return null
    return _time.days_from_civil(to_int(_s.substring(t, 0, 4)), to_int(_s.substring(t, 4, 6)), to_int(_s.substring(t, 6, 8))) * 86400 + to_int(_s.substring(t, 8, 10)) * 3600 + to_int(_s.substring(t, 10, 12)) * 60 + to_int(_s.substring(t, 12, 14))

# Entrée d'une ligne MLSD « type=file;size=12;modify=20260101120000; nom ».
func parse_mlsd_line(line):
    sp := _s.find(line, " ")
    if sp < 0:
        return null
    facts := {}
    for f in _s.split(_s.substring(line, 0, sp), ";"):
        eq := _s.find(f, "=")
        if eq > 0:
            facts[_s.lower(_s.substring(f, 0, eq))] = _s.substring(f, eq + 1, len(f))
    name := _s.substring(line, sp + 1, len(line))
    kind := "file"
    if contains_key(facts, "type"):
        kind = _s.lower(facts["type"])
        if _s.starts_with(kind, "os.unix=slink") or _s.starts_with(kind, "os.unix=symlink"):
            kind = "link"
    size := null
    if contains_key(facts, "size"):
        size = to_int(facts["size"])
    modified := null
    if contains_key(facts, "modify"):
        modified = parse_time(facts["modify"])
    return Entry(name, kind, size, modified, facts)

const _MONTHS := ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

# Entrée d'une ligne LIST au format Unix (« drwxr-xr-x 2 u g 4096 Oct 11 12:00 nom »), ou null.
func parse_list_line(line):
    parts := []
    for p in _s.split(line, " "):
        if p != "":
            append(parts, p)
    if len(parts) < 9:
        return null
    perm := parts[0]
    kind := "file"
    if _s.starts_with(perm, "d"):
        kind = "dir"
    elif _s.starts_with(perm, "l"):
        kind = "link"
    size := null
    ok := true
    for c in parts[4]:
        if c < '0' or c > '9':
            ok = false
    if ok:
        size = to_int(parts[4])
    # le nom est tout ce qui suit le 8e champ (espaces compris)
    count := 0
    i := 0
    while i < len(line) and count < 8:
        while i < len(line) and line[i] == ' ':
            i += 1
        while i < len(line) and line[i] != ' ':
            i += 1
        count += 1
    while i < len(line) and line[i] == ' ':
        i += 1
    name := _s.substring(line, i, len(line))
    if kind == "link" and _s.contains(name, " -> "):
        name = _s.substring(name, 0, _s.find(name, " -> "))
    return Entry(name, kind, size, null, {"perm": perm, "owner": parts[2], "group": parts[3]})

# Télécharge une URL « ftp://utilisateur:mdp@hôte/chemin » (anonyme sans identifiants).
func fetch_url(url, timeout=30.0):
    i := _s.find(url, "://")
    if i < 0:
        _fail("URL ftp:// attendue")
    rest := _s.substring(url, i + 3, len(url))
    slash := _s.find(rest, "/")
    auth := rest
    path := "/"
    if slash >= 0:
        auth = _s.substring(rest, 0, slash)
        path = _s.substring(rest, slash, len(rest))
    user := "anonymous"
    pw := "anonymous@"
    at := _s.find(auth, "@")
    if at >= 0:
        cred := _s.substring(auth, 0, at)
        auth = _s.substring(auth, at + 1, len(auth))
        c := _s.find(cred, ":")
        if c >= 0:
            user = _enc.percent_decode(_s.substring(cred, 0, c))
            pw = _enc.percent_decode(_s.substring(cred, c + 1, len(cred)))
        else:
            user = _enc.percent_decode(cred)
    hp := _u.split_host_port(auth, 21)
    f := FtpClient(hp[0], hp[1], timeout)
    try:
        f.login(user, pw)
        data := f.retrieve(path)
        f.quit()
        return data
    catch e:
        f.close()
        raise(e)
