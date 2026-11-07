# ALEX STANDARD LIBRARY — database._postgres (interne)
#
# Pilote PostgreSQL écrit en ALEX : protocole frontend/backend v3 sur network.tcp (TLS via network.tls avec
# sslmode=require), authentification SCRAM-SHA-256, md5, mot de passe en clair ou sans mot de passe (trust).
# Utilisé par database.connection pour les URL postgres:// et postgresql:// :
#
#   postgres://utilisateur:motdepasse@hote:5432/base?sslmode=require&connect_timeout=10&application_name=app
#
# Requêtes paramétrées par le protocole étendu (Parse / Bind / Execute) : les paramètres ne sont jamais
# insérés dans le texte SQL. Repères acceptés : « ? » (positionnels), « :nom » (avec un dict) et « $1 » ; les
# « ? » et « :nom » sont convertis en $n hors des chaînes et des identifiants entre guillemets (« :: » reste un
# transtypage PostgreSQL).
#
# Contrat (comme database._sqlite.SqliteConnection) : execute(sql, params) -> [colonnes, lignes, nombre],
# script(sql), last_id(), in_transaction(), close(), tables(), columns(table).
# Types reçus : entiers (int2/4/8, oid), réels (float4/8, numeric), booléens ; le reste en texte (dates, JSON,
# UUID...). Erreurs : ConnectionError, QueryError, IntegrityError (SQLSTATE 23xxx) avec le code SQLSTATE.
# INSERT sans RETURNING : l'identifiant de la ligne (colonne « id ») est lu par un RETURNING ajouté, pour
# last_id() — comme lastrowid en SQLite.

from core use len, type, to_int, to_float
from collections use append, keys
use string as _s
use network.tcp as _tcp
use network.security as _sec
use network.encoding as _enc
use network.tls as _tls

const PROTOCOL := 196608
const DEFAULT_PORT := 5432

# ================================================================ URL

# {host, port, user, password, database, sslmode, timeout, application_name}
func parse_url(url):
    rest := url
    if _s.starts_with(rest, "postgresql://"):
        rest = rest[13:len(rest)]
    elif _s.starts_with(rest, "postgres://"):
        rest = rest[11:len(rest)]
    else:
        raise("ConnectionError", "URL PostgreSQL attendue (postgres://...)")
    out := {"host": "127.0.0.1", "port": DEFAULT_PORT, "user": "postgres", "password": null, "database": null, "sslmode": "prefer", "timeout": 10.0, "application_name": "alex"}
    q := _s.find(rest, "?")
    if q >= 0:
        for pair in _s.split(rest[q + 1:len(rest)], "&"):
            eq := _s.find(pair, "=")
            if eq > 0:
                k := _pct(pair[0:eq])
                v := _pct(pair[eq + 1:len(pair)])
                if k == "sslmode":
                    out["sslmode"] = v
                elif k == "connect_timeout":
                    out["timeout"] = to_float(v)
                elif k == "application_name":
                    out["application_name"] = v
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
    if out["database"] == null:
        out["database"] = out["user"]
    return out

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

# ================================================================ octets

func _i32(n):
    v := n if n >= 0 else n + 4294967296
    return _s.byte_pack([(v // 16777216) % 256, (v // 65536) % 256, (v // 256) % 256, v % 256])

func _i16(n):
    return _s.byte_pack([(n // 256) % 256, n % 256])

func _r32(s, i):
    v := _s.byte_at(s, i) * 16777216 + _s.byte_at(s, i + 1) * 65536 + _s.byte_at(s, i + 2) * 256 + _s.byte_at(s, i + 3)
    return v - 4294967296 if v >= 2147483648 else v

func _r16(s, i):
    return _s.byte_at(s, i) * 256 + _s.byte_at(s, i + 1)

func _cstr(s):
    return s + "\x00"

# Chaîne terminée par 0 à partir de i : [texte, position suivante].
func _read_cstr(s, i):
    j := _s.byte_find(s, "\x00", i)
    if j < 0:
        raise("ConnectionError", "postgres : message mal formé")
    return [_s.byte_slice(s, i, j), j + 1]

func _message(kind, body):
    return kind + _i32(_s.byte_len(body) + 4) + body

func _xor(a, b):
    x := _s.byte_unpack(a)
    y := _s.byte_unpack(b)
    out := []
    i := 0
    while i < len(x):
        v := x[i] + y[i] - 2 * _band(x[i], y[i])
        append(out, v)
        i += 1
    return _s.byte_pack(out)

func _band(a, b):
    r := 0
    bit := 1
    x := a
    y := b
    while x > 0 and y > 0:
        if x % 2 == 1 and y % 2 == 1:
            r += bit
        x = x // 2
        y = y // 2
        bit = bit * 2
    return r

# ================================================================ connexion

const OID_BOOL := 16
const INT_OIDS := [20, 21, 23, 26]
const FLOAT_OIDS := [700, 701, 1700]

class PgConnection:
    func init(url):
        self.params = parse_url(url)
        self.conn = null
        self.buffer = ""
        self.status = "I"                # I : hors transaction ; T : en transaction ; E : transaction en échec
        self.server = {}
        self.last = null
        self.notices = []
        self._connect()

    func _connect():
        p := self.params
        try:
            self.conn = _tcp.connect(p["host"], p["port"], p["timeout"])
        catch e:
            raise("ConnectionError", "postgres : connexion à " + p["host"] + ":" + str(p["port"]) + " impossible (" + str(e.message) + ")")
        if p["sslmode"] == "require" or p["sslmode"] == "verify-full":
            self._start_tls()
        body := _i32(PROTOCOL) + _cstr("user") + _cstr(p["user"]) + _cstr("database") + _cstr(p["database"]) + _cstr("client_encoding") + _cstr("UTF8") + _cstr("application_name") + _cstr(p["application_name"]) + "\x00"
        self._send(_i32(_s.byte_len(body) + 4) + body)
        self._authenticate()
        while true:
            m := self._read()
            if m[0] == "S":
                kv := _read_cstr(m[1], 0)
                self.server[kv[0]] = _read_cstr(m[1], kv[1])[0]
            elif m[0] == "K":
                continue
            elif m[0] == "Z":
                self.status = _s.byte_slice(m[1], 0, 1)
                return
            elif m[0] == "E":
                self._raise_error(m[1], false)
            elif m[0] == "N":
                continue

    func _start_tls():
        self._send(_i32(8) + _i32(80877103))
        r := self.conn.read_exact(1, self.params["timeout"])
        if r != "S":
            raise("ConnectionError", "postgres : le serveur refuse TLS (sslmode=" + self.params["sslmode"] + ")")
        secured := null
        try:
            secured = _tls.wrap_client(self.conn.socket, self.params["host"], self.params["sslmode"] == "verify-full", null, null, self.params["timeout"])
        catch e:
            raise("ConnectionError", "postgres : négociation TLS impossible (" + str(e.message) + ")")
        self.conn = _tcp.Connection(secured)

    func _authenticate():
        p := self.params
        while true:
            m := self._read()
            if m[0] == "E":
                self._raise_error(m[1], false)
            if m[0] != "R":
                raise("ConnectionError", "postgres : réponse d'authentification inattendue « " + m[0] + " »")
            code := _r32(m[1], 0)
            if code == 0:
                return
            if code == 3:
                self._send(_message("p", _cstr(self._password())))
            elif code == 5:
                salt := _s.byte_slice(m[1], 4, 8)
                inner := _sec.digest_hex(self._password() + p["user"], "md5")
                self._send(_message("p", _cstr("md5" + _sec.digest_hex(inner + salt, "md5"))))
            elif code == 10:
                mechs := []
                i := 4
                while i < _s.byte_len(m[1]) and _s.byte_at(m[1], i) != 0:
                    r := _read_cstr(m[1], i)
                    append(mechs, r[0])
                    i = r[1]
                if not ("SCRAM-SHA-256" in mechs):
                    raise("ConnectionError", "postgres : mécanismes SASL non pris en charge : " + _s.join(", ", mechs))
                self._scram()
                return
            else:
                raise("ConnectionError", "postgres : méthode d'authentification non prise en charge (" + str(code) + ")")

    func _password():
        if self.params["password"] == null:
            raise("ConnectionError", "postgres : mot de passe requis par le serveur pour « " + self.params["user"] + " »")
        return self.params["password"]

    # SCRAM-SHA-256 (RFC 5802 / 7677), sans liaison de canal.
    func _scram():
        nonce := _sec.random_token(18)
        first_bare := "n=,r=" + nonce
        first := "n,," + first_bare
        self._send(_message("p", _cstr("SCRAM-SHA-256") + _i32(_s.byte_len(first)) + first))
        m := self._read()
        if m[0] == "E":
            self._raise_error(m[1], false)
        if m[0] != "R" or _r32(m[1], 0) != 11:
            raise("ConnectionError", "postgres : SCRAM, message serveur inattendu")
        server_first := _s.byte_slice(m[1], 4, _s.byte_len(m[1]))
        attrs := _scram_attrs(server_first)
        if not _s.starts_with(attrs["r"], nonce):
            raise("ConnectionError", "postgres : SCRAM, nonce du serveur invalide")
        salt := _enc.base64_decode(attrs["s"])
        iterations := to_int(attrs["i"])
        salted := _sec.pbkdf2(self._password(), salt, iterations, 32, "sha256")
        client_key := _sec.hmac(salted, "Client Key", "sha256")
        stored_key := _sec.digest(client_key, "sha256")
        final_bare := "c=biws,r=" + attrs["r"]
        auth_message := first_bare + "," + server_first + "," + final_bare
        signature := _sec.hmac(stored_key, auth_message, "sha256")
        proof := _enc.base64_encode(_xor(client_key, signature))
        final := final_bare + ",p=" + proof
        self._send(_message("p", final))
        m2 := self._read()
        if m2[0] == "E":
            self._raise_error(m2[1], false)
        if m2[0] != "R" or _r32(m2[1], 0) != 12:
            raise("ConnectionError", "postgres : SCRAM, réponse finale inattendue")
        server_final := _scram_attrs(_s.byte_slice(m2[1], 4, _s.byte_len(m2[1])))
        server_key := _sec.hmac(salted, "Server Key", "sha256")
        expected := _enc.base64_encode(_sec.hmac(server_key, auth_message, "sha256"))
        if not ("v" in server_final) or not _sec.constant_time_equals(server_final["v"], expected):
            raise("ConnectionError", "postgres : SCRAM, signature du serveur invalide")
        m3 := self._read()
        if m3[0] == "E":
            self._raise_error(m3[1], false)
        if m3[0] != "R" or _r32(m3[1], 0) != 0:
            raise("ConnectionError", "postgres : SCRAM, authentification non confirmée")

    # ------------------------------------------------------------ échanges

    func _send(data):
        self.conn.write(data, self.params["timeout"])

    func _fill(n):
        while _s.byte_len(self.buffer) < n:
            d := self.conn.socket.recv(65536, null)
            if d == "" or d == null:
                raise("ConnectionError", "postgres : connexion fermée par le serveur")
            self.buffer = self.buffer + d

    # [type, corps]
    func _read():
        self._fill(5)
        kind := _s.byte_slice(self.buffer, 0, 1)
        n := _r32(self.buffer, 1)
        self._fill(1 + n)
        body := _s.byte_slice(self.buffer, 5, 1 + n)
        self.buffer = _s.byte_slice(self.buffer, 1 + n, _s.byte_len(self.buffer))
        return [kind, body]

    func _raise_error(body, recover=true):
        f := {}
        i := 0
        n := _s.byte_len(body)
        while i < n and _s.byte_at(body, i) != 0:
            code := _s.byte_slice(body, i, i + 1)
            r := _read_cstr(body, i + 1)
            f[code] = r[0]
            i = r[1]
        if recover:
            self._until_ready()
        state := f["C"] if "C" in f else "XX000"
        msg := (f["M"] if "M" in f else "erreur") + (" (" + f["D"] + ")" if "D" in f else "") + " [SQLSTATE " + state + "]"
        if _s.starts_with(state, "23"):
            raise("IntegrityError", msg)
        if _s.starts_with(state, "28") or _s.starts_with(state, "08") or _s.starts_with(state, "3D"):
            raise("ConnectionError", "postgres : " + msg)
        raise("QueryError", msg)

    func _until_ready():
        while true:
            m := self._read()
            if m[0] == "Z":
                self.status = _s.byte_slice(m[1], 0, 1)
                return

    # ------------------------------------------------------------ requêtes

    # [colonnes, lignes, nombre de lignes touchées]
    func execute(sql, params):
        converted := convert_placeholders(sql, params)
        text := converted[0]
        values := converted[1]
        returning_added := false
        if _is_plain_insert(text):
            text = text + " RETURNING *"
            returning_added = true
        body := _cstr("") + _cstr(text) + _i16(0)
        msgs := [_message("P", body)]
        bind := _cstr("") + _cstr("") + _i16(0) + _i16(len(values))
        for v in values:
            enc := _encode(v)
            if enc == null:
                bind = bind + _i32(-1)
            else:
                bind = bind + _i32(_s.byte_len(enc)) + enc
        bind = bind + _i16(0)
        append(msgs, _message("B", bind))
        append(msgs, _message("D", "P" + _cstr("")))
        append(msgs, _message("E", _cstr("") + _i32(0)))
        append(msgs, _message("S", ""))
        self._send(_s.byte_join(msgs))
        cols := []
        oids := []
        rows := []
        count := 0
        error := null
        while true:
            m := self._read()
            k := m[0]
            if k == "T":
                d := _row_description(m[1])
                cols = d[0]
                oids = d[1]
            elif k == "D":
                append(rows, _data_row(m[1], oids))
            elif k == "C":
                count = _command_count(_read_cstr(m[1], 0)[0])
            elif k == "E":
                if error == null:
                    error = m[1]
            elif k == "Z":
                self.status = _s.byte_slice(m[1], 0, 1)
                break
        if error != null:
            self._raise_error(error, false)
        if returning_added:
            self.last = null
            if len(rows) > 0:
                i := 0
                while i < len(cols):
                    if cols[i] == "id":
                        self.last = rows[len(rows) - 1][i]
                    i += 1
            return [[], [], count]
        return [cols, rows, count]

    # Script (protocole simple, plusieurs instructions, sans paramètres) ; résultat de la dernière.
    func script(sql):
        self._send(_message("Q", _cstr(sql)))
        last := [[], [], 0]
        cols := []
        oids := []
        rows := []
        error := null
        while true:
            m := self._read()
            k := m[0]
            if k == "T":
                d := _row_description(m[1])
                cols = d[0]
                oids = d[1]
                rows = []
            elif k == "D":
                append(rows, _data_row(m[1], oids))
            elif k == "C":
                last = [cols, rows, _command_count(_read_cstr(m[1], 0)[0])]
                cols = []
                rows = []
            elif k == "E":
                if error == null:
                    error = m[1]
            elif k == "Z":
                self.status = _s.byte_slice(m[1], 0, 1)
                break
        if error != null:
            self._raise_error(error, false)
        return last

    func last_id():
        return self.last

    func in_transaction():
        return self.status == "T" or self.status == "E"

    func tables():
        r := self.execute("SELECT tablename FROM pg_tables WHERE schemaname = current_schema() ORDER BY tablename", null)
        return [x[0] for x in r[1]]

    func columns(t):
        r := self.execute("SELECT c.column_name, upper(c.data_type), c.is_nullable, COALESCE((SELECT true FROM information_schema.table_constraints tc JOIN information_schema.key_column_usage k ON k.constraint_name = tc.constraint_name WHERE tc.table_name = c.table_name AND tc.constraint_type = 'PRIMARY KEY' AND k.column_name = c.column_name LIMIT 1), false) FROM information_schema.columns c WHERE c.table_schema = current_schema() AND c.table_name = $1 ORDER BY c.ordinal_position", [t])
        if len(r[1]) == 0:
            raise("QueryError", "table inconnue : " + t)
        return [{"name": x[0], "type": x[1], "primary": x[3] == true, "not_null": x[2] == "NO", "unique": false} for x in r[1]]

    func close():
        if self.conn != null:
            try:
                self._send(_message("X", ""))
            catch e:
                ignored := e
            self.conn.close()
            self.conn = null

# ================================================================ conversions

func _encode(v):
    if v == null:
        return null
    t := type(v)
    if t == "bool":
        return "true" if v else "false"
    if t == "int" or t == "float":
        return str(v)
    if t == "str":
        return v
    return str(v)

func _row_description(body):
    n := _r16(body, 0)
    i := 2
    names := []
    oids := []
    k := 0
    while k < n:
        r := _read_cstr(body, i)
        append(names, r[0])
        i = r[1]
        append(oids, _r32(body, i + 6))
        i += 18
        k += 1
    return [names, oids]

func _data_row(body, oids):
    n := _r16(body, 0)
    i := 2
    out := []
    k := 0
    while k < n:
        size := _r32(body, i)
        i += 4
        if size < 0:
            append(out, null)
        else:
            raw := _s.byte_slice(body, i, i + size)
            i += size
            append(out, _decode(raw, oids[k] if k < len(oids) else 0))
        k += 1
    return out

func _decode(raw, oid):
    if oid == OID_BOOL:
        return raw == "t"
    if oid in INT_OIDS:
        return to_int(raw)
    if oid in FLOAT_OIDS:
        if raw == "NaN" or raw == "Infinity" or raw == "-Infinity":
            return raw
        return to_float(raw)
    return raw

func _command_count(tag):
    parts := _s.split(tag, " ")
    if len(parts) >= 2:
        last := parts[len(parts) - 1]
        ok := len(last) > 0
        for ch in last:
            if str(ch) < "0" or str(ch) > "9":
                ok = false
        if ok:
            return to_int(last)
    return 0

func _is_plain_insert(sql):
    u := _s.upper(_s.trim(sql))
    return _s.starts_with(u, "INSERT") and _s.find(u, "RETURNING") < 0

# « ? » et « :nom » -> $n hors des chaînes '...', des identifiants "..." et des commentaires ; [texte, valeurs].
func convert_placeholders(sql, params):
    if params == null:
        return [sql, []]
    named := type(params) == "dict"
    out := []
    values := []
    names := {}
    i := 0
    n := len(sql)
    while i < n:
        c := sql[i:i + 1]
        if c == "'" or c == "\"":
            j := i + 1
            while j < n:
                if sql[j:j + 1] == c:
                    if j + 1 < n and sql[j + 1:j + 2] == c:
                        j += 2
                        continue
                    break
                j += 1
            append(out, sql[i:j + 1])
            i = j + 1
            continue
        if c == "-" and i + 1 < n and sql[i + 1:i + 2] == "-":
            j := _s.find(sql[i:n], "\n")
            j = n if j < 0 else i + j
            append(out, sql[i:j])
            i = j
            continue
        if c == "?" and not named:
            append(values, params[len(values)] if len(values) < len(params) else _missing())
            append(out, "$" + str(len(values)))
            i += 1
            continue
        if c == ":" and named and i + 1 < n and _ident_start(sql[i + 1:i + 2]) and not (i > 0 and sql[i - 1:i] == ":"):
            j := i + 1
            while j < n and _ident(sql[j:j + 1]):
                j += 1
            name := sql[i + 1:j]
            if not (name in params):
                raise("QueryError", "paramètre nommé manquant : " + name)
            if not (name in names):
                append(values, params[name])
                names[name] = len(values)
            append(out, "$" + str(names[name]))
            i = j
            continue
        append(out, c)
        i += 1
    if not named and type(params) == "list" and _s.find(sql, "?") < 0 and len(params) > 0:
        return [sql, params]                # repères $1... déjà présents
    return [_s.join("", out), values]

func _missing():
    raise("QueryError", "paramètres insuffisants pour la requête")

func _ident_start(c):
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"

func _ident(c):
    return _ident_start(c) or (c >= "0" and c <= "9")

# « r=...,s=...,i=4096 » -> {r, s, i}
func _scram_attrs(text):
    out := {}
    for part in _s.split(text, ","):
        if len(part) >= 2 and part[1:2] == "=":
            out[part[0:1]] = part[2:len(part)]
    return out
