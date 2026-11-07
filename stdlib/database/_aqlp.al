# ALEX STANDARD LIBRARY — database._aqlp (interne)
#
# Pilote du serveur ALEX DB (projet AlexDB : SGBD relationnel écrit en ALEX, langage AQL) : protocole AQLP v1 sur
# network.tcp, écrit en ALEX (fonctionne aussi dans un exécutable natif, sans bibliothèque C). Utilisé par
# database.connection pour les URL alexdb:// :
#
#   alexdb://utilisateur:motdepasse@hote:5442/base?connect_timeout=10&lock_timeout=5
#
# Trame AQLP : u32 grand-boutiste (longueur du corps) puis JSON en UTF-8 ; une requête, puis sa réponse.
# Paramètres : « ? » (liste) et « :nom » (dict) sont compris par le serveur lui-même ; ils ne sont jamais
# insérés dans le texte. Plusieurs instructions séparées par « ; » s'envoient en une seule requête.
#
# Contrat (comme database._sqlite.SqliteConnection) : execute(sql, params) -> [colonnes, lignes, nombre],
# script(sql), last_id(), in_transaction(), close(), tables(), columns(table) ; en plus batch(instructions) :
# une transaction entière (BEGIN ... COMMIT) en un seul aller-retour. Le serveur traite une requête à la fois :
# une transaction envoyée d'un bloc ne croise celle d'aucune autre connexion et ne bute sur aucun verrou.
#
# Verrous : le serveur ne fait pas attendre (LockError, « réessayer ») quand une autre connexion a une
# transaction ouverte sur la table. Hors transaction, l'instruction est réessayée jusqu'à lock_timeout secondes
# (5 par défaut, comme busy_timeout de SQLite) ; dans une transaction, le serveur l'a annulée : l'erreur remonte.
# Erreurs : ConnectionError (réseau, authentification, protocole), IntegrityError (ConstraintError : NOT NULL,
# UNIQUE, clé étrangère, CHECK), TransactionError, QueryError (le reste ; type d'origine entre crochets).

from core use len, type, to_int, to_float
from collections use append
use string as _s
use json as _json
use time as _time
use network.tcp as _tcp

const PROTOCOL := 1
const DEFAULT_PORT := 5442
const MAX_FRAME := 268435456

# ================================================================ URL

# {host, port, user, password, database, timeout, lock_timeout}
func parse_url(url):
    if not _s.starts_with(url, "alexdb://"):
        raise("ConnectionError", "URL ALEX DB attendue (alexdb://...)")
    rest := url[9:len(url)]
    out := {"host": "127.0.0.1", "port": DEFAULT_PORT, "user": "admin", "password": "", "database": "alexdb", "timeout": 10.0, "lock_timeout": 5.0}
    q := _s.find(rest, "?")
    if q >= 0:
        for pair in _s.split(rest[q + 1:len(rest)], "&"):
            eq := _s.find(pair, "=")
            if eq > 0:
                k := _pct(pair[0:eq])
                v := _pct(pair[eq + 1:len(pair)])
                if k == "connect_timeout" or k == "timeout":
                    out["timeout"] = to_float(v)
                elif k == "lock_timeout":
                    out["lock_timeout"] = to_float(v)
                else:
                    raise("ConnectionError", "alexdb : paramètre d'URL inconnu « " + k + " » (connect_timeout, lock_timeout)")
        rest = rest[0:q]
    slash := _s.find(rest, "/")
    if slash >= 0:
        db := rest[slash + 1:len(rest)]
        if db != "":
            out["database"] = _pct(db)
        rest = rest[0:slash]
    at := _last(rest, "@")
    if at >= 0:
        cred := rest[0:at]
        rest = rest[at + 1:len(rest)]
        c := _s.find(cred, ":")
        if c >= 0:
            out["user"] = _pct(cred[0:c])
            out["password"] = _pct(cred[c + 1:len(cred)])
        elif cred != "":
            out["user"] = _pct(cred)
    if _s.starts_with(rest, "["):
        e := _s.find(rest, "]")
        out["host"] = rest[1:e]
        rest = rest[e + 1:len(rest)]
        if _s.starts_with(rest, ":"):
            out["port"] = to_int(rest[1:len(rest)])
    elif rest != "":
        c := _last(rest, ":")
        if c >= 0:
            out["host"] = rest[0:c]
            out["port"] = to_int(rest[c + 1:len(rest)])
        else:
            out["host"] = rest
    return out

# URL sans le mot de passe (journaux, messages).
func redact(url):
    p := parse_url(url)
    return "alexdb://" + p["user"] + "@" + p["host"] + ":" + str(p["port"]) + "/" + p["database"]

func _last(s, ch):
    i := len(s) - 1
    while i >= 0:
        if s[i:i + 1] == ch:
            return i
        i -= 1
    return -1

func _pct(s):
    if _s.find(s, "%") < 0:
        return s
    parts := []
    i := 0
    n := _s.byte_len(s)
    while i < n:
        b := _s.byte_at(s, i)
        if b == 37 and i + 2 < n:
            append(parts, _s.byte_char(_hexval(_s.byte_at(s, i + 1)) * 16 + _hexval(_s.byte_at(s, i + 2))))
            i += 3
        else:
            append(parts, _s.byte_char(b))
            i += 1
    return _s.byte_join(parts)

func _hexval(b):
    if b >= 48 and b <= 57:
        return b - 48
    if b >= 97 and b <= 102:
        return b - 87
    if b >= 65 and b <= 70:
        return b - 55
    raise("ConnectionError", "URL : séquence % invalide")

# ================================================================ trames

func _frame(msg):
    body := _json.stringify(msg)
    n := _s.byte_len(body)
    return _s.byte_join([_s.byte_char((n >> 24) & 255), _s.byte_char((n >> 16) & 255), _s.byte_char((n >> 8) & 255), _s.byte_char(n & 255), body])

# ================================================================ connexion

class AqlpConnection:
    func init(url):
        self.params = parse_url(url)
        self.conn = null
        self.buffer = ""
        self.in_tx = false
        self.last = null
        self.server = null
        self.session = null
        self.retries = 0                 # instructions réessayées après un LockError (statistique)
        p := self.params
        try:
            self.conn = _tcp.connect(p["host"], p["port"], p["timeout"])
        catch e:
            raise("ConnectionError", "alexdb : connexion à " + p["host"] + ":" + str(p["port"]) + " impossible (" + str(e.message) + ")")
        r := self._request({"op": "hello", "protocol": PROTOCOL, "user": p["user"], "password": p["password"], "database": p["database"]}, true)
        self.server = r["server"] if "server" in r else null
        self.session = r["session"] if "session" in r else null

    # ------------------------------------------------------------ échanges

    func _fill(n):
        while _s.byte_len(self.buffer) < n:
            d := self.conn.socket.recv(65536, null)
            if d == "" or d == null:
                self._lost()
                raise("ConnectionError", "alexdb : connexion fermée par le serveur")
            self.buffer = self.buffer + d

    func _read():
        self._fill(4)
        n := (_s.byte_at(self.buffer, 0) << 24) | (_s.byte_at(self.buffer, 1) << 16) | (_s.byte_at(self.buffer, 2) << 8) | _s.byte_at(self.buffer, 3)
        if n < 1 or n > MAX_FRAME:
            self._lost()
            raise("ConnectionError", "alexdb : trame de " + str(n) + " octets reçue (protocole)")
        self._fill(4 + n)
        body := _s.byte_slice(self.buffer, 4, 4 + n)
        self.buffer = _s.byte_slice(self.buffer, 4 + n, _s.byte_len(self.buffer))
        try:
            return _json.parse(body)
        catch e:
            self._lost()
            raise("ConnectionError", "alexdb : réponse illisible (" + str(e.message) + ")")

    func _lost():
        if self.conn != null:
            try:
                self.conn.close()
            catch e:
                ignored := e
        self.conn = null
        self.in_tx = false

    # Réponse {"ok": true, ...} ; une réponse d'erreur est relevée avec un type de database.
    func _request(msg, hello=false):
        if self.conn == null:
            raise("ConnectionError", "alexdb : connexion fermée")
        try:
            self.conn.write(_frame(msg), self.params["timeout"])
        catch e:
            self._lost()
            raise("ConnectionError", "alexdb : envoi impossible (" + str(e.message) + ")")
        r := self._read()
        if type(r) != "dict":
            raise("ConnectionError", "alexdb : réponse non objet")
        if "ok" in r and r["ok"]:
            return r
        er := r["error"] if "error" in r and type(r["error"]) == "dict" else {"type": "ProtocolError", "message": "réponse invalide"}
        kind := str(er["type"]) if "type" in er else "Error"
        text := str(er["message"]) if "message" in er else "erreur"
        if kind == "ProtocolError":
            self._lost()
        prefix := "" if _s.starts_with(text, "ALEX DB") else "ALEX DB : "
        raise(_error_type(kind, hello), prefix + text + " [" + kind + "]")

    # Requête AQL ; réessayée hors transaction tant que le serveur répond LockError (au plus lock_timeout s).
    func _query(sql, params):
        msg := {"op": "query", "aql": sql, "params": params}
        start := _time.monotonic()
        wait := 0.002
        while true:
            try:
                return self._request(msg)
            catch e:
                if not _s.ends_with(str(e.message), "[LockError]") or self.in_tx:
                    if self.in_tx and _s.find(str(e.message), "transaction annulée") >= 0:
                        self.in_tx = false
                    raise(e.type, e.message)
                if _time.monotonic() - start + wait > self.params["lock_timeout"]:
                    raise(e.type, e.message + " (attendu " + str(self.params["lock_timeout"]) + " s)")
            self.retries += 1
            _time.sleep(wait)
            wait = wait * 2.0 if wait < 0.1 else 0.1

    func _track(kind):
        if kind == "begin":
            self.in_tx = true
        elif kind == "commit" or kind == "rollback":
            self.in_tx = false

    # ------------------------------------------------------------ requêtes

    # [colonnes, lignes, nombre de lignes touchées]
    func execute(sql, params):
        r := self._query(sql, params)
        return self._result(r)

    func _result(r):
        kind := r["kind"] if "kind" in r else ""
        if "statements" in r:
            for st in r["statements"]:
                self._track(st["kind"])
                if st["kind"] == "insert" and "last_insert_id" in st and st["last_insert_id"] != null:
                    self.last = st["last_insert_id"]
        else:
            self._track(kind)
            if kind == "insert" and "last_insert_id" in r:
                self.last = r["last_insert_id"]
        cols := r["columns"] if "columns" in r else []
        rows := r["rows"] if "rows" in r else []
        n := r["affected"] if "affected" in r else 0
        if len(cols) == 0:
            return [[], [], n]
        return [cols, rows, n]

    # Script (plusieurs instructions, sans paramètres) ; résultat de la dernière.
    func script(sql):
        return self._result(self._query(sql, null))

    # Transaction d'un seul bloc : [[sql, paramètres (liste ou null)], ...] entre BEGIN et COMMIT, envoyés en une
    # requête ; liste des {"rowcount", "lastrowid"} de chaque instruction. Une erreur annule tout (le serveur
    # fait le ROLLBACK) et est relevée.
    func batch(statements):
        if self.in_tx:
            raise("TransactionError", "alexdb : batch dans une transaction déjà ouverte")
        parts := ["BEGIN"]
        values := []
        for st in statements:
            sql := _s.trim(st[0])
            while _s.ends_with(sql, ";"):
                sql = _s.trim(sql[0:len(sql) - 1])
            ps := st[1] if len(st) > 1 else null
            if ps != null and type(ps) != "list":
                raise("ArgumentError", "alexdb : batch : paramètres en liste attendus (« ? »)")
            append(parts, sql)
            if ps != null:
                values = values + ps
        append(parts, "COMMIT")
        r := self._query(_s.join(";\n", parts), values)
        out := []
        sts := r["statements"] if "statements" in r else []
        i := 1
        while i < len(sts) - 1:
            st := sts[i]
            lid := st["last_insert_id"] if "last_insert_id" in st else null
            if lid != null:
                self.last = lid
            append(out, {"rowcount": st["affected"], "lastrowid": lid})
            i += 1
        self.in_tx = false
        return out

    func last_id():
        return self.last

    func in_transaction():
        return self.in_tx

    func ping():
        return self._request({"op": "ping"})["ok"]

    func tables():
        r := self.execute("SHOW TABLES", null)
        return [x[0] for x in r[1]]

    func columns(t):
        r := self.execute("DESCRIBE " + _quote(t), null)
        return [{"name": x[0], "type": x[1], "primary": x[3] == true, "not_null": x[2] == false, "unique": x[4] == true} for x in r[1]]

    func close():
        if self.conn != null:
            try:
                self.conn.write(_frame({"op": "bye"}), 1.0)
            catch e:
                ignored := e
            self._lost()

func _quote(name):
    return "\"" + _s.replace(name, "\"", "\"\"") + "\""

func _error_type(kind, hello):
    if hello or kind == "ProtocolError":
        return "ConnectionError"
    if kind == "ConstraintError":
        return "IntegrityError"
    if kind == "TransactionError":
        return "TransactionError"
    return "QueryError"
