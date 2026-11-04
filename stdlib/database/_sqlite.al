# ALEX STANDARD LIBRARY — database._sqlite (interne)
#
# Pilote SQLite 3 par FFI (libsqlite3, si elle est installée) : ouverture, requêtes préparées, liaison des
# paramètres (? et :nom), lecture des colonnes (entier, réel, texte, NULL), changements, dernier identifiant.
# Les BLOB sont lus comme texte (limite de la FFI : pas de lecture de mémoire C arbitraire).
#
# Erreurs : ConnectionError (bibliothèque absente, ouverture), QueryError, IntegrityError, DatabaseError.

from core use len, type
from collections use append
use string as _s
use ffi
use database.database_errors as _e

const ROW := 100
const DONE := 101

_lib := [null, null]

func _fns():
    if _lib[1] != null:
        return _lib[1]
    lib := null
    for nm in ["sqlite3", "libsqlite3.so.0", "libsqlite3.so", "libsqlite3.dylib"]:
        if lib == null:
            try:
                lib = ffi.Library(nm)
            catch e:
                lib = null
    if lib == null:
        raise("ConnectionError", "SQLite indisponible : bibliothèque libsqlite3 introuvable")
    f := {}
    f["open"] = lib.function("sqlite3_open_v2", ["cstr", "ptr", "i32", "ptr"], "i32")
    f["close"] = lib.function("sqlite3_close_v2", ["ptr"], "i32")
    f["prepare"] = lib.function("sqlite3_prepare_v2", ["ptr", "cstr", "i32", "ptr", "ptr"], "i32")
    f["step"] = lib.function("sqlite3_step", ["ptr"], "i32")
    f["reset"] = lib.function("sqlite3_reset", ["ptr"], "i32")
    f["clear"] = lib.function("sqlite3_clear_bindings", ["ptr"], "i32")
    f["finalize"] = lib.function("sqlite3_finalize", ["ptr"], "i32")
    f["errmsg"] = lib.function("sqlite3_errmsg", ["ptr"], "cstr")
    f["changes"] = lib.function("sqlite3_changes", ["ptr"], "i32")
    f["last_id"] = lib.function("sqlite3_last_insert_rowid", ["ptr"], "i64")
    f["bind_int"] = lib.function("sqlite3_bind_int64", ["ptr", "i32", "i64"], "i32")
    f["bind_double"] = lib.function("sqlite3_bind_double", ["ptr", "i32", "f64"], "i32")
    f["bind_text"] = lib.function("sqlite3_bind_text", ["ptr", "i32", "cstr", "i32", "i64"], "i32")
    f["bind_null"] = lib.function("sqlite3_bind_null", ["ptr", "i32"], "i32")
    f["param_count"] = lib.function("sqlite3_bind_parameter_count", ["ptr"], "i32")
    f["param_name"] = lib.function("sqlite3_bind_parameter_name", ["ptr", "i32"], "cstr")
    f["col_count"] = lib.function("sqlite3_column_count", ["ptr"], "i32")
    f["col_name"] = lib.function("sqlite3_column_name", ["ptr", "i32"], "cstr")
    f["col_type"] = lib.function("sqlite3_column_type", ["ptr", "i32"], "i32")
    f["col_int"] = lib.function("sqlite3_column_int64", ["ptr", "i32"], "i64")
    f["col_double"] = lib.function("sqlite3_column_double", ["ptr", "i32"], "f64")
    f["col_text"] = lib.function("sqlite3_column_text", ["ptr", "i32"], "cstr")
    f["autocommit"] = lib.function("sqlite3_get_autocommit", ["ptr"], "i32")
    f["version"] = lib.function("sqlite3_libversion", [], "cstr")
    _lib[0] = lib
    _lib[1] = f
    return f

func available():
    try:
        _fns()
        return true
    catch e:
        return false

func version():
    return _fns()["version"].call([])

# Découpe un script en instructions (les ; à l'intérieur des chaînes et identifiants sont ignorés).
func split_statements(sql):
    out := []
    start := 0
    i := 0
    n := len(sql)
    q := '\0'
    while i < n:
        c := sql[i]
        if q != '\0':
            if c == q:
                q = '\0'
        elif c == '\'' or c == '"' or c == '`':
            q = c
        elif c == '-' and i + 1 < n and sql[i + 1] == '-':
            while i < n and sql[i] != '\n':
                i += 1
        elif c == ';':
            part := _s.trim(_s.substring(sql, start, i))
            if part != "":
                append(out, part)
            start = i + 1
        i += 1
    last := _s.trim(_s.substring(sql, start, n))
    if last != "":
        append(out, last)
    return out

class Statement:
    func init(conn, sql):
        self.conn = conn
        self.sql = sql
        f := _fns()
        out := ffi.Buffer(8)
        rc := f["prepare"].call([conn.db, sql, -1, out.address(), null])
        self.handle = out.read("u64")
        out.free()
        if rc != 0:
            conn.fail(rc, "préparation de « " + sql + " »")
        if self.handle == 0:
            raise("QueryError", "SQLite : instruction vide")
        self.nparams = f["param_count"].call([self.handle])

    func bind(params):
        f := _fns()
        f["reset"].call([self.handle])
        f["clear"].call([self.handle])
        if params == null:
            if self.nparams > 0:
                raise("QueryError", "paramètre 1 manquant")
            return
        i := 1
        while i <= self.nparams:
            v := null
            nm := f["param_name"].call([self.handle, i])
            if type(params) == "dict":
                if nm == null:
                    raise("QueryError", "paramètre positionnel '?' avec des paramètres nommés")
                key := _s.substring(nm, 1, len(nm))
                if not (key in params):
                    raise("QueryError", "paramètre nommé ':" + key + "' manquant")
                v = params[key]
            else:
                if i - 1 >= len(params):
                    raise("QueryError", "paramètre " + str(i) + " manquant")
                v = params[i - 1]
            rc := 0
            t := type(v)
            if v == null:
                rc = f["bind_null"].call([self.handle, i])
            elif t == "bool":
                b := 0
                if v:
                    b = 1
                rc = f["bind_int"].call([self.handle, i, b])
            elif t == "int":
                rc = f["bind_int"].call([self.handle, i, v])
            elif t == "float":
                rc = f["bind_double"].call([self.handle, i, v])
            else:
                rc = f["bind_text"].call([self.handle, i, str(v), -1, -1])
            if rc != 0:
                self.conn.fail(rc, "liaison du paramètre " + str(i))
            i += 1

    # [colonnes, lignes, changements]
    func run(params):
        self.bind(params)
        f := _fns()
        n := f["col_count"].call([self.handle])
        cols := [f["col_name"].call([self.handle, i]) for i in 0..n]
        rows := []
        while true:
            rc := f["step"].call([self.handle])
            if rc == ROW:
                row := []
                i := 0
                while i < n:
                    ct := f["col_type"].call([self.handle, i])
                    if ct == 1:
                        append(row, f["col_int"].call([self.handle, i]))
                    elif ct == 2:
                        append(row, f["col_double"].call([self.handle, i]))
                    elif ct == 5:
                        append(row, null)
                    else:
                        append(row, f["col_text"].call([self.handle, i]))
                    i += 1
                append(rows, row)
            elif rc == DONE:
                break
            else:
                f["reset"].call([self.handle])
                self.conn.fail(rc, "exécution")
        f["reset"].call([self.handle])
        changes := 0
        if n == 0:
            changes = f["changes"].call([self.conn.db])
        else:
            changes = len(rows)
        return [cols, rows, changes]

    func close():
        if self.handle != 0:
            _fns()["finalize"].call([self.handle])
            self.handle = 0

class SqliteConnection:
    func init(path):
        f := _fns()
        out := ffi.Buffer(8)
        # SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI
        rc := f["open"].call([path, out.address(), 0x46, null])
        self.db = out.read("u64")
        out.free()
        if rc != 0:
            msg := "code " + str(rc)
            if self.db != 0:
                msg = f["errmsg"].call([self.db])
                f["close"].call([self.db])
            raise("ConnectionError", "SQLite : ouverture de '" + path + "' impossible : " + msg)
        self.path = path

    func fail(rc, what):
        msg := _fns()["errmsg"].call([self.db])
        raise(_e.from_sqlite_code(rc), "SQLite (" + what + ") : " + msg)

    func prepare(sql):
        return Statement(self, sql)

    func execute(sql, params):
        st := Statement(self, sql)
        try:
            return st.run(params)
        finally:
            st.close()

    func script(sql):
        last := [[], [], 0]
        for part in split_statements(sql):
            last = self.execute(part, null)
        return last

    func last_id():
        return _fns()["last_id"].call([self.db])

    func in_transaction():
        return _fns()["autocommit"].call([self.db]) == 0

    func close():
        if self.db != 0:
            _fns()["close"].call([self.db])
            self.db = 0
