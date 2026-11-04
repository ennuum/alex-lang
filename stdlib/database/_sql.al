# ALEX STANDARD LIBRARY — database._sql (interne)
#
# Moteur SQL embarqué, écrit en ALEX : analyse d'un sous-ensemble courant de SQL et exécution sur des tables en
# mémoire (persistées en JSON par database.connection). Sous-ensemble :
#   CREATE TABLE [IF NOT EXISTS] t (col TYPE [PRIMARY KEY [AUTOINCREMENT]] [NOT NULL] [UNIQUE] [DEFAULT v], ...)
#   CREATE [UNIQUE] INDEX [IF NOT EXISTS] i ON t (cols) · DROP TABLE [IF EXISTS] t · DROP INDEX i
#   INSERT INTO t [(cols)] VALUES (...), (...) · UPDATE t SET c = e, ... [WHERE] · DELETE FROM t [WHERE]
#   SELECT [DISTINCT] * | t.* | expr [AS a], ... [FROM t [AS a] [[INNER|LEFT|CROSS] JOIN u [AS b] ON e]...]
#          [WHERE e] [GROUP BY e, ...] [HAVING e] [ORDER BY e [ASC|DESC], ...] [LIMIT n [OFFSET m]]
#   BEGIN · COMMIT · ROLLBACK · SAVEPOINT s · RELEASE s · ROLLBACK TO s
# Expressions : littéraux, NULL, TRUE/FALSE, colonnes (t.c), paramètres ? et :nom, + - * / % ||, = == != <> <
# <= > >=, AND OR NOT, IS [NOT] NULL, [NOT] LIKE, [NOT] IN (...), [NOT] BETWEEN, CASE WHEN ... END,
# fonctions COUNT(*) COUNT([DISTINCT] e) SUM AVG MIN MAX TOTAL GROUP_CONCAT, LOWER UPPER LENGTH ABS COALESCE
# IFNULL NULLIF ROUND SUBSTR TRIM REPLACE INSTR TYPEOF.
# Logique à trois valeurs : toute comparaison avec NULL vaut NULL (donc fausse dans un WHERE).
#
# Erreurs : QueryError, IntegrityError, TransactionError.

from core use len, type, to_int, to_float
from collections use append, pop
use string as _s
use database.database_errors as _e

const KEYWORDS := ["SELECT", "FROM", "WHERE", "INSERT", "INTO", "VALUES", "UPDATE", "SET", "DELETE", "CREATE",
    "TABLE", "DROP", "IF", "NOT", "EXISTS", "PRIMARY", "KEY", "UNIQUE", "DEFAULT", "NULL", "AND", "OR", "IS",
    "LIKE", "IN", "BETWEEN", "AS", "ORDER", "BY", "ASC", "DESC", "LIMIT", "OFFSET", "GROUP", "HAVING", "DISTINCT",
    "JOIN", "INNER", "LEFT", "OUTER", "CROSS", "ON", "BEGIN", "COMMIT", "ROLLBACK", "TRANSACTION", "SAVEPOINT",
    "RELEASE", "TO", "TRUE", "FALSE", "CASE", "WHEN", "THEN", "ELSE", "END", "INDEX", "AUTOINCREMENT", "ALL"]
const AGGREGATES := ["COUNT", "SUM", "AVG", "MIN", "MAX", "TOTAL", "GROUP_CONCAT"]

# ---------------------------------------------------------------------------------------------------------
# Jetons
# ---------------------------------------------------------------------------------------------------------

func _is_digit(c):
    return c >= '0' and c <= '9'

func _is_word(c):
    return (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or _is_digit(c)

func tokenize(sql):
    toks := []
    i := 0
    n := len(sql)
    nparam := 0
    while i < n:
        c := sql[i]
        if c == ' ' or c == '\n' or c == '\t' or c == '\r':
            i += 1
            continue
        if c == '-' and i + 1 < n and sql[i + 1] == '-':
            while i < n and sql[i] != '\n':
                i += 1
            continue
        if c == '\'':
            parts := []
            j := i + 1
            start := j
            closed := false
            while j < n:
                if sql[j] == '\'':
                    if j + 1 < n and sql[j + 1] == '\'':
                        append(parts, _s.substring(sql, start, j + 1))
                        j += 2
                        start = j
                        continue
                    append(parts, _s.substring(sql, start, j))
                    closed = true
                    break
                j += 1
            if not closed:
                _e.query_error("SQL : chaîne non terminée")
            append(toks, ["str", _s.join("", parts)])
            i = j + 1
            continue
        if c == '"' or c == '`' or c == '[':
            close := c
            if c == '[':
                close = ']'
            j := _s.find(_s.substring(sql, i + 1, n), str(close))
            if j < 0:
                _e.query_error("SQL : identifiant entre délimiteurs non terminé")
            append(toks, ["id", _s.substring(sql, i + 1, i + 1 + j)])
            i = i + j + 2
            continue
        if _is_digit(c) or (c == '.' and i + 1 < n and _is_digit(sql[i + 1])):
            j := i
            isf := false
            while j < n and (_is_digit(sql[j]) or sql[j] == '.'):
                if sql[j] == '.':
                    isf = true
                j += 1
            if j < n and (sql[j] == 'e' or sql[j] == 'E'):
                isf = true
                j += 1
                if j < n and (sql[j] == '+' or sql[j] == '-'):
                    j += 1
                while j < n and _is_digit(sql[j]):
                    j += 1
            text := _s.substring(sql, i, j)
            if isf:
                append(toks, ["num", to_float(text)])
            else:
                append(toks, ["num", to_int(text)])
            i = j
            continue
        if _is_word(c):
            j := i
            while j < n and _is_word(sql[j]):
                j += 1
            w := _s.substring(sql, i, j)
            u := _s.upper(w)
            if u in KEYWORDS:
                append(toks, ["kw", u])
            else:
                append(toks, ["id", w])
            i = j
            continue
        if c == '?':
            append(toks, ["param", nparam])
            nparam += 1
            i += 1
            continue
        if (c == ':' or c == '@' or c == '$') and i + 1 < n and _is_word(sql[i + 1]):
            j := i + 1
            while j < n and _is_word(sql[j]):
                j += 1
            append(toks, ["param", _s.substring(sql, i + 1, j)])
            i = j
            continue
        two := ""
        if i + 1 < n:
            two = str(c) + str(sql[i + 1])
        if two == "<=" or two == ">=" or two == "<>" or two == "!=" or two == "==" or two == "||":
            append(toks, ["op", two])
            i += 2
            continue
        if _s.contains("+-*/%=<>(),.;", str(c)):
            append(toks, ["op", str(c)])
            i += 1
            continue
        _e.query_error("SQL : caractère inattendu '" + str(c) + "'")
    append(toks, ["end", null])
    return toks

# ---------------------------------------------------------------------------------------------------------
# Analyse
# ---------------------------------------------------------------------------------------------------------

class SqlParser:
    func init(sql):
        self.sql = sql
        self.toks = tokenize(sql)
        self.i = 0
        self.params = 0

    func peek(k=0):
        j := self.i + k
        if j >= len(self.toks):
            return self.toks[len(self.toks) - 1]
        return self.toks[j]

    func is_kw(w, k=0):
        t := self.peek(k)
        return t[0] == "kw" and t[1] == w

    func is_op(o):
        t := self.peek()
        return t[0] == "op" and t[1] == o

    func next():
        t := self.toks[self.i]
        if self.i < len(self.toks) - 1:
            self.i += 1
        return t

    func accept_kw(w):
        if self.is_kw(w):
            self.next()
            return true
        return false

    func accept_op(o):
        if self.is_op(o):
            self.next()
            return true
        return false

    func fail(msg):
        t := self.peek()
        near := "fin de la requête"
        if t[0] != "end":
            near = "'" + str(t[1]) + "'"
        _e.query_error("SQL : " + msg + " près de " + near)

    func expect_kw(w):
        if not self.accept_kw(w):
            self.fail("attendu " + w)

    func expect_op(o):
        if not self.accept_op(o):
            self.fail("attendu '" + o + "'")

    func ident():
        t := self.peek()
        if t[0] == "id":
            self.next()
            return t[1]
        # quelques mots-clés courants acceptés comme noms
        if t[0] == "kw" and (t[1] == "KEY" or t[1] == "INDEX" or t[1] == "END" or t[1] == "TO"):
            self.next()
            return _s.lower(t[1])
        self.fail("identifiant attendu")

    func statements():
        out := []
        while self.peek()[0] != "end":
            if self.accept_op(";"):
                continue
            append(out, self.statement())
            if not self.accept_op(";") and self.peek()[0] != "end":
                self.fail("fin d'instruction attendue")
        return out

    func statement():
        if self.is_kw("SELECT"):
            return self.select()
        if self.accept_kw("INSERT"):
            return self.insert()
        if self.accept_kw("UPDATE"):
            return self.update()
        if self.accept_kw("DELETE"):
            return self.delete()
        if self.accept_kw("CREATE"):
            return self.create()
        if self.accept_kw("DROP"):
            return self.drop()
        if self.accept_kw("BEGIN"):
            self.accept_kw("TRANSACTION")
            return {"kind": "begin"}
        if self.accept_kw("COMMIT") or (self.is_kw("END") and self.next() != null):
            self.accept_kw("TRANSACTION")
            return {"kind": "commit"}
        if self.accept_kw("ROLLBACK"):
            self.accept_kw("TRANSACTION")
            if self.accept_kw("TO"):
                self.accept_kw("SAVEPOINT")
                return {"kind": "rollback_to", "name": self.ident()}
            return {"kind": "rollback"}
        if self.accept_kw("SAVEPOINT"):
            return {"kind": "savepoint", "name": self.ident()}
        if self.accept_kw("RELEASE"):
            self.accept_kw("SAVEPOINT")
            return {"kind": "release", "name": self.ident()}
        self.fail("instruction SQL inconnue")

    func create():
        unique := self.accept_kw("UNIQUE")
        if self.accept_kw("INDEX"):
            ine := false
            if self.accept_kw("IF"):
                self.expect_kw("NOT")
                self.expect_kw("EXISTS")
                ine = true
            nm := self.ident()
            self.expect_kw("ON")
            tbl := self.ident()
            self.expect_op("(")
            cols := [self.ident()]
            while self.accept_op(","):
                append(cols, self.ident())
            self.expect_op(")")
            return {"kind": "create_index", "name": nm, "table": tbl, "columns": cols, "unique": unique, "if_not_exists": ine}
        self.expect_kw("TABLE")
        ine := false
        if self.accept_kw("IF"):
            self.expect_kw("NOT")
            self.expect_kw("EXISTS")
            ine = true
        nm := self.ident()
        self.expect_op("(")
        cols := []
        uniques := []
        pk := []
        while true:
            if self.accept_kw("PRIMARY"):
                self.expect_kw("KEY")
                self.expect_op("(")
                append(pk, self.ident())
                while self.accept_op(","):
                    append(pk, self.ident())
                self.expect_op(")")
            elif self.accept_kw("UNIQUE"):
                self.expect_op("(")
                u := [self.ident()]
                while self.accept_op(","):
                    append(u, self.ident())
                self.expect_op(")")
                append(uniques, u)
            else:
                append(cols, self.column_def())
            if not self.accept_op(","):
                break
        self.expect_op(")")
        for c in cols:
            if c["name"] in pk:
                c["primary"] = true
                c["not_null"] = true
        if len(pk) > 1:
            append(uniques, pk)
            for c in cols:
                if c["name"] in pk:
                    c["primary"] = false
        return {"kind": "create_table", "name": nm, "columns": cols, "uniques": uniques, "if_not_exists": ine}

    func column_def():
        nm := self.ident()
        ty := ""
        while self.peek()[0] == "id":
            ty = _s.trim(ty + " " + _s.upper(self.next()[1]))
        if self.accept_op("("):
            while not self.accept_op(")"):
                self.next()
        col := {"name": nm, "type": ty, "primary": false, "autoincrement": false, "not_null": false, "unique": false, "default": null, "has_default": false}
        while true:
            if self.accept_kw("PRIMARY"):
                self.expect_kw("KEY")
                col["primary"] = true
                col["not_null"] = true
                if self.accept_kw("ASC") or self.accept_kw("DESC"):
                    col["primary"] = true
                if self.accept_kw("AUTOINCREMENT"):
                    col["autoincrement"] = true
            elif self.accept_kw("NOT"):
                self.expect_kw("NULL")
                col["not_null"] = true
            elif self.accept_kw("NULL"):
                col["not_null"] = false
            elif self.accept_kw("UNIQUE"):
                col["unique"] = true
            elif self.accept_kw("DEFAULT"):
                col["has_default"] = true
                if self.accept_op("("):
                    col["default"] = self.expr()
                    self.expect_op(")")
                else:
                    col["default"] = self.unary()
            else:
                break
        return col

    func drop():
        if self.accept_kw("INDEX"):
            ie := false
            if self.accept_kw("IF"):
                self.expect_kw("EXISTS")
                ie = true
            return {"kind": "drop_index", "name": self.ident(), "if_exists": ie}
        self.expect_kw("TABLE")
        ie := false
        if self.accept_kw("IF"):
            self.expect_kw("EXISTS")
            ie = true
        return {"kind": "drop_table", "name": self.ident(), "if_exists": ie}

    func insert():
        self.expect_kw("INTO")
        tbl := self.ident()
        cols := null
        if self.accept_op("("):
            cols = [self.ident()]
            while self.accept_op(","):
                append(cols, self.ident())
            self.expect_op(")")
        if self.is_kw("SELECT"):
            return {"kind": "insert", "table": tbl, "columns": cols, "rows": null, "select": self.select()}
        self.expect_kw("VALUES")
        rows := []
        while true:
            self.expect_op("(")
            r := [self.expr()]
            while self.accept_op(","):
                append(r, self.expr())
            self.expect_op(")")
            append(rows, r)
            if not self.accept_op(","):
                break
        return {"kind": "insert", "table": tbl, "columns": cols, "rows": rows, "select": null}

    func update():
        tbl := self.ident()
        self.expect_kw("SET")
        sets := []
        while true:
            c := self.ident()
            if not self.accept_op("=") and not self.accept_op("=="):
                self.fail("attendu '='")
            append(sets, [c, self.expr()])
            if not self.accept_op(","):
                break
        w := null
        if self.accept_kw("WHERE"):
            w = self.expr()
        return {"kind": "update", "table": tbl, "sets": sets, "where": w}

    func delete():
        self.expect_kw("FROM")
        tbl := self.ident()
        w := null
        if self.accept_kw("WHERE"):
            w = self.expr()
        return {"kind": "delete", "table": tbl, "where": w}

    func select():
        self.expect_kw("SELECT")
        distinct := self.accept_kw("DISTINCT")
        self.accept_kw("ALL")
        items := []
        while true:
            if self.accept_op("*"):
                append(items, ["star", null])
            elif self.peek()[0] == "id" and self.peek(1)[0] == "op" and self.peek(1)[1] == "." and self.peek(2)[0] == "op" and self.peek(2)[1] == "*":
                t := self.next()[1]
                self.next()
                self.next()
                append(items, ["star", t])
            else:
                e := self.expr()
                alias := null
                if self.accept_kw("AS"):
                    alias = self.ident()
                elif self.peek()[0] == "id":
                    alias = self.next()[1]
                append(items, ["expr", e, alias])
            if not self.accept_op(","):
                break
        q := {"kind": "select", "distinct": distinct, "items": items, "from": [], "where": null, "group": [],
              "having": null, "order": [], "limit": null, "offset": null}
        if self.accept_kw("FROM"):
            append(q["from"], self.table_ref("from", null))
            while true:
                if self.accept_op(","):
                    append(q["from"], self.table_ref("cross", null))
                elif self.is_kw("JOIN") or self.is_kw("INNER") or self.is_kw("LEFT") or self.is_kw("CROSS"):
                    jt := "inner"
                    if self.accept_kw("LEFT"):
                        jt = "left"
                        self.accept_kw("OUTER")
                    elif self.accept_kw("CROSS"):
                        jt = "cross"
                    else:
                        self.accept_kw("INNER")
                    self.expect_kw("JOIN")
                    ref := self.table_ref(jt, null)
                    if jt != "cross":
                        self.expect_kw("ON")
                        ref["on"] = self.expr()
                    append(q["from"], ref)
                else:
                    break
        if self.accept_kw("WHERE"):
            q["where"] = self.expr()
        if self.accept_kw("GROUP"):
            self.expect_kw("BY")
            append(q["group"], self.expr())
            while self.accept_op(","):
                append(q["group"], self.expr())
        if self.accept_kw("HAVING"):
            q["having"] = self.expr()
        if self.accept_kw("ORDER"):
            self.expect_kw("BY")
            while true:
                e := self.expr()
                desc := false
                if self.accept_kw("DESC"):
                    desc = true
                else:
                    self.accept_kw("ASC")
                append(q["order"], [e, desc])
                if not self.accept_op(","):
                    break
        if self.accept_kw("LIMIT"):
            q["limit"] = self.expr()
            if self.accept_kw("OFFSET"):
                q["offset"] = self.expr()
            elif self.accept_op(","):
                q["offset"] = q["limit"]
                q["limit"] = self.expr()
        return q

    func table_ref(join, on):
        nm := self.ident()
        alias := nm
        if self.accept_kw("AS"):
            alias = self.ident()
        elif self.peek()[0] == "id":
            alias = self.next()[1]
        return {"table": nm, "alias": alias, "join": join, "on": on}

    # ---- expressions ----
    func expr():
        return self.or_expr()

    func or_expr():
        a := self.and_expr()
        while self.accept_kw("OR"):
            a = ["bin", "OR", a, self.and_expr()]
        return a

    func and_expr():
        a := self.not_expr()
        while self.accept_kw("AND"):
            a = ["bin", "AND", a, self.not_expr()]
        return a

    func not_expr():
        if self.accept_kw("NOT"):
            return ["un", "NOT", self.not_expr()]
        return self.comparison()

    func comparison():
        a := self.additive()
        while true:
            t := self.peek()
            if t[0] == "op" and (t[1] == "=" or t[1] == "==" or t[1] == "!=" or t[1] == "<>" or t[1] == "<" or t[1] == "<=" or t[1] == ">" or t[1] == ">="):
                self.next()
                op := t[1]
                if op == "==":
                    op = "="
                if op == "!=":
                    op = "<>"
                a = ["bin", op, a, self.additive()]
            elif self.is_kw("IS"):
                self.next()
                neg := self.accept_kw("NOT")
                if self.accept_kw("NULL"):
                    a = ["isnull", a, neg]
                else:
                    b := self.additive()
                    a = ["is", a, b, neg]
            elif self.is_kw("NOT") and (self.is_kw("LIKE", 1) or self.is_kw("IN", 1) or self.is_kw("BETWEEN", 1)):
                self.next()
                a = self.postfix_op(a, true)
            elif self.is_kw("LIKE") or self.is_kw("IN") or self.is_kw("BETWEEN"):
                a = self.postfix_op(a, false)
            else:
                return a

    func postfix_op(a, neg):
        if self.accept_kw("LIKE"):
            return ["like", a, self.additive(), neg]
        if self.accept_kw("IN"):
            self.expect_op("(")
            if self.is_kw("SELECT"):
                sub := self.select()
                self.expect_op(")")
                return ["insel", a, sub, neg]
            items := []
            if not self.is_op(")"):
                append(items, self.expr())
                while self.accept_op(","):
                    append(items, self.expr())
            self.expect_op(")")
            return ["in", a, items, neg]
        self.expect_kw("BETWEEN")
        lo := self.additive()
        self.expect_kw("AND")
        hi := self.additive()
        return ["between", a, lo, hi, neg]

    func additive():
        a := self.multiplicative()
        while self.is_op("+") or self.is_op("-"):
            op := self.next()[1]
            a = ["bin", op, a, self.multiplicative()]
        return a

    func multiplicative():
        a := self.concat()
        while self.is_op("*") or self.is_op("/") or self.is_op("%"):
            op := self.next()[1]
            a = ["bin", op, a, self.concat()]
        return a

    func concat():
        a := self.unary()
        while self.accept_op("||"):
            a = ["bin", "||", a, self.unary()]
        return a

    func unary():
        if self.accept_op("-"):
            return ["un", "-", self.unary()]
        if self.accept_op("+"):
            return self.unary()
        return self.primary()

    func primary():
        t := self.peek()
        k := t[0]
        if k == "num" or k == "str":
            self.next()
            return ["lit", t[1]]
        if k == "param":
            self.next()
            if type(t[1]) == "int":
                self.params += 1
            return ["param", t[1]]
        if k == "kw":
            w := t[1]
            if w == "NULL":
                self.next()
                return ["lit", null]
            if w == "TRUE":
                self.next()
                return ["lit", true]
            if w == "FALSE":
                self.next()
                return ["lit", false]
            if w == "CASE":
                self.next()
                return self.case_expr()
            if w == "EXISTS":
                self.next()
                self.expect_op("(")
                sub := self.select()
                self.expect_op(")")
                return ["exists", sub]
        if self.accept_op("("):
            if self.is_kw("SELECT"):
                sub := self.select()
                self.expect_op(")")
                return ["subq", sub]
            e := self.expr()
            self.expect_op(")")
            return e
        if k == "id":
            self.next()
            if self.accept_op("("):
                fname := _s.upper(t[1])
                if self.accept_op("*"):
                    self.expect_op(")")
                    return ["call", fname, [], false, true]
                distinct := self.accept_kw("DISTINCT")
                args := []
                if not self.is_op(")"):
                    append(args, self.expr())
                    while self.accept_op(","):
                        append(args, self.expr())
                self.expect_op(")")
                return ["call", fname, args, distinct, false]
            if self.accept_op("."):
                return ["col", t[1], self.ident()]
            return ["col", null, t[1]]
        self.fail("expression attendue")

    func case_expr():
        base := null
        if not self.is_kw("WHEN"):
            base = self.expr()
        whens := []
        while self.accept_kw("WHEN"):
            c := self.expr()
            self.expect_kw("THEN")
            append(whens, [c, self.expr()])
        other := null
        if self.accept_kw("ELSE"):
            other = self.expr()
        self.expect_kw("END")
        return ["case", base, whens, other]

func parse(sql):
    p := SqlParser(sql)
    stmts := p.statements()
    return stmts

# Nombre de paramètres positionnels (?) d'un texte SQL.
func count_params(sql):
    n := 0
    for t in tokenize(sql):
        if t[0] == "param" and type(t[1]) == "int":
            n += 1
    return n

# ---------------------------------------------------------------------------------------------------------
# Valeurs
# ---------------------------------------------------------------------------------------------------------

func _num(v):
    t := type(v)
    if t == "bool":
        if v:
            return 1
        return 0
    return v

func _rank(v):
    if v == null:
        return 0
    t := type(v)
    if t == "int" or t == "float" or t == "bool":
        return 1
    if t == "str" or t == "char":
        return 2
    return 3

# Ordre SQLite : NULL < nombres < texte < le reste.
func compare(a, b):
    ra := _rank(a)
    rb := _rank(b)
    if ra != rb:
        if ra < rb:
            return -1
        return 1
    if ra == 0:
        return 0
    x := a
    y := b
    if ra == 1:
        x = _num(a)
        y = _num(b)
    elif ra == 2:
        x = str(a)
        y = str(b)
    else:
        x = str(a)
        y = str(b)
    if x < y:
        return -1
    if x > y:
        return 1
    return 0

func truthy(v):
    if v == null:
        return false
    t := type(v)
    if t == "bool":
        return v
    if t == "int" or t == "float":
        return v != 0
    if t == "str":
        n := _to_number(v)
        if n == null:
            return false
        return n != 0
    return true

func _to_number(s):
    t := _s.trim(s)
    if len(t) == 0:
        return null
    i := 0
    if t[0] == '-' or t[0] == '+':
        i = 1
    dot := false
    digits := 0
    while i < len(t):
        c := t[i]
        if c == '.' and not dot:
            dot = true
        elif _is_digit(c):
            digits += 1
        else:
            return null
        i += 1
    if digits == 0:
        return null
    if dot:
        return to_float(t)
    return to_int(t)

func _arith_val(v):
    if v == null:
        return null
    t := type(v)
    if t == "str":
        n := _to_number(v)
        if n == null:
            return 0
        return n
    return _num(v)

func like(text, pattern):
    return _like(_s.lower(str(text)), _s.lower(str(pattern)), 0, 0)

func _like(s, p, i, j):
    while j < len(p):
        c := p[j]
        if c == '%':
            while j < len(p) and p[j] == '%':
                j += 1
            if j == len(p):
                return true
            k := i
            while k <= len(s):
                if _like(s, p, k, j):
                    return true
                k += 1
            return false
        if i >= len(s):
            return false
        if c != '_' and c != s[i]:
            return false
        i += 1
        j += 1
    return i == len(s)

func value_key(vals):
    parts := []
    for v in vals:
        if v == null:
            append(parts, "n:")
        else:
            t := type(v)
            if t == "int" or t == "float" or t == "bool":
                append(parts, "#:" + str(_num(v)))
            else:
                append(parts, "s:" + str(v))
    return _s.join("\u0001", parts)

# Affinité de type de colonne (règles simplifiées de SQLite).
func coerce(col, v):
    if v == null:
        return null
    ty := col["type"]
    t := type(v)
    if _s.contains(ty, "INT"):
        if t == "bool":
            return _num(v)
        if t == "float" and v == to_int(v):
            return to_int(v)
        if t == "str":
            n := _to_number(v)
            if n != null and type(n) == "int":
                return n
            if col["primary"]:
                _e.integrity_error("colonne " + col["name"] + " : entier attendu (obtenu '" + v + "')")
        return v
    if _s.contains(ty, "REAL") or _s.contains(ty, "FLOA") or _s.contains(ty, "DOUB"):
        if t == "int" or t == "bool":
            return to_float(_num(v))
        if t == "str":
            n := _to_number(v)
            if n != null:
                return to_float(n)
        return v
    if _s.contains(ty, "BOOL"):
        if t == "int":
            return v != 0
        return v
    if _s.contains(ty, "CHAR") or _s.contains(ty, "TEXT") or _s.contains(ty, "CLOB"):
        if t == "int" or t == "float" or t == "char":
            return str(v)
        return v
    return v

# ---------------------------------------------------------------------------------------------------------
# Exécution
# ---------------------------------------------------------------------------------------------------------

class Table:
    func init(name, columns, uniques=null):
        self.name = name
        self.columns = columns
        self.uniques = uniques
        if self.uniques == null:
            self.uniques = []
        self.rows = []
        self.next_id = 1
        self.indexes = {}       # nom -> {"columns": [...], "unique": bool}

    func column_names():
        return [c["name"] for c in self.columns]

    func column(name):
        for c in self.columns:
            if _s.lower(c["name"]) == _s.lower(name):
                return c
        return null

    func rowid_column():
        for c in self.columns:
            if c["primary"] and _s.contains(c["type"], "INT"):
                return c["name"]
        return null

    func to_dict():
        return {"name": self.name, "columns": self.columns, "uniques": self.uniques, "rows": self.rows,
                "next_id": self.next_id, "indexes": self.indexes}

func table_from_dict(d):
    t := Table(d["name"], d["columns"], d["uniques"])
    t.rows = d["rows"]
    t.next_id = d["next_id"]
    if "indexes" in d:
        t.indexes = d["indexes"]
    return t

func _copy_tables(tables):
    out := {}
    for k in tables:
        t := tables[k]
        c := Table(t.name, t.columns, t.uniques)
        c.rows = [_copy_row(r) for r in t.rows]
        c.next_id = t.next_id
        c.indexes = {}
        for i in t.indexes:
            c.indexes[i] = t.indexes[i]
        out[k] = c
    return out

func _copy_row(r):
    o := {}
    for k in r:
        o[k] = r[k]
    return o

class Engine:
    func init():
        self.tables = {}
        self.tx = null            # instantané au BEGIN
        self.savepoints = []      # [nom, instantané]
        self.changes = 0
        self.last_id = null
        self.dirty = false

    func in_transaction():
        return self.tx != null

    func table(name):
        k := _s.lower(name)
        if not (k in self.tables):
            _e.query_error("table inconnue : " + name)
        return self.tables[k]

    func param(p, params):
        key := p[1]
        if type(key) == "int":
            if type(params) == "dict":
                _e.query_error("paramètre positionnel '?' avec des paramètres nommés")
            if params == null or key >= len(params):
                _e.query_error("paramètre " + str(key + 1) + " manquant")
            return params[key]
        if type(params) != "dict" or not (key in params):
            _e.query_error("paramètre nommé ':" + key + "' manquant")
        return params[key]

    # ---- évaluation ----
    func ev(e, env, params, group=null):
        k := e[0]
        if k == "lit":
            return e[1]
        if k == "param":
            return self.param(e, params)
        if k == "col":
            key := e[2]
            if e[1] != null:
                key = e[1] + "." + e[2]
            lk := _s.lower(key)
            if lk in env:
                return env[lk]
            if "$aliases" in env and lk in env["$aliases"]:
                return env["$aliases"][lk]
            _e.query_error("colonne inconnue : " + key)
        if k == "bin":
            op := e[1]
            if op == "AND":
                a := self.ev(e[2], env, params, group)
                if a != null and not truthy(a):
                    return false
                b := self.ev(e[3], env, params, group)
                if b != null and not truthy(b):
                    return false
                if a == null or b == null:
                    return null
                return true
            if op == "OR":
                a := self.ev(e[2], env, params, group)
                if a != null and truthy(a):
                    return true
                b := self.ev(e[3], env, params, group)
                if b != null and truthy(b):
                    return true
                if a == null or b == null:
                    return null
                return false
            a := self.ev(e[2], env, params, group)
            b := self.ev(e[3], env, params, group)
            if a == null or b == null:
                return null
            if op == "||":
                return _text(a) + _text(b)
            if op == "=":
                return compare(a, b) == 0
            if op == "<>":
                return compare(a, b) != 0
            if op == "<":
                return compare(a, b) < 0
            if op == "<=":
                return compare(a, b) <= 0
            if op == ">":
                return compare(a, b) > 0
            if op == ">=":
                return compare(a, b) >= 0
            x := _arith_val(a)
            y := _arith_val(b)
            if op == "+":
                return x + y
            if op == "-":
                return x - y
            if op == "*":
                return x * y
            if op == "/":
                if y == 0:
                    return null
                if type(x) == "int" and type(y) == "int":
                    q := x // y
                    if q < 0 and q * y != x:
                        q += 1
                    return q
                return x / y
            if op == "%":
                if y == 0:
                    return null
                return x % y
            _e.query_error("opérateur inconnu " + op)
        if k == "un":
            v := self.ev(e[2], env, params, group)
            if v == null:
                return null
            if e[1] == "NOT":
                return not truthy(v)
            return -_arith_val(v)
        if k == "isnull":
            v := self.ev(e[1], env, params, group)
            return (v == null) != e[2]
        if k == "is":
            a := self.ev(e[1], env, params, group)
            b := self.ev(e[2], env, params, group)
            same := (a == null and b == null) or (a != null and b != null and compare(a, b) == 0)
            return same != e[3]
        if k == "like":
            a := self.ev(e[1], env, params, group)
            p := self.ev(e[2], env, params, group)
            if a == null or p == null:
                return null
            return like(a, p) != e[3]
        if k == "in" or k == "insel":
            a := self.ev(e[1], env, params, group)
            if a == null:
                return null
            vals := null
            if k == "in":
                vals = [self.ev(x, env, params, group) for x in e[2]]
            else:
                vals = [r[0] for r in self.select(e[2], params, env)[1]]
            found := false
            has_null := false
            for v in vals:
                if v == null:
                    has_null = true
                elif compare(a, v) == 0:
                    found = true
                    break
            if found:
                return not e[3]
            if has_null:
                return null
            return e[3]
        if k == "between":
            a := self.ev(e[1], env, params, group)
            lo := self.ev(e[2], env, params, group)
            hi := self.ev(e[3], env, params, group)
            if a == null or lo == null or hi == null:
                return null
            return (compare(a, lo) >= 0 and compare(a, hi) <= 0) != e[4]
        if k == "case":
            base := null
            if e[1] != null:
                base = self.ev(e[1], env, params, group)
            for w in e[2]:
                c := self.ev(w[0], env, params, group)
                if e[1] != null:
                    if c != null and base != null and compare(base, c) == 0:
                        return self.ev(w[1], env, params, group)
                elif truthy(c):
                    return self.ev(w[1], env, params, group)
            if e[3] != null:
                return self.ev(e[3], env, params, group)
            return null
        if k == "subq":
            r := self.select(e[1], params, env)[1]
            if len(r) == 0:
                return null
            return r[0][0]
        if k == "exists":
            return len(self.select(e[1], params, env)[1]) > 0
        if k == "call":
            return self.call(e, env, params, group)
        _e.query_error("expression inconnue " + str(k))

    func call(e, env, params, group):
        f := e[1]
        if f in AGGREGATES:
            if group == null:
                _e.query_error("fonction d'agrégat " + f + " hors d'une requête groupée")
            if e[4]:
                return len(group)
            vals := []
            for g in group:
                v := self.ev(e[2][0], g, params, null)
                if v != null:
                    append(vals, v)
            if e[3]:
                seen := {}
                uniq := []
                for v in vals:
                    kk := value_key([v])
                    if not (kk in seen):
                        seen[kk] = true
                        append(uniq, v)
                vals = uniq
            if f == "COUNT":
                return len(vals)
            if f == "GROUP_CONCAT":
                sep := ","
                if len(e[2]) > 1:
                    sep = str(self.ev(e[2][1], env, params, null))
                if len(vals) == 0:
                    return null
                return _s.join(sep, [_text(v) for v in vals])
            if len(vals) == 0:
                if f == "TOTAL":
                    return 0.0
                return null
            if f == "MIN" or f == "MAX":
                best := vals[0]
                for v in vals:
                    c := compare(v, best)
                    if (f == "MIN" and c < 0) or (f == "MAX" and c > 0):
                        best = v
                return best
            total := 0
            for v in vals:
                total += _arith_val(v)
            if f == "SUM":
                return total
            if f == "TOTAL":
                return to_float(total)
            return to_float(total) / len(vals)
        args := [self.ev(a, env, params, group) for a in e[2]]
        n := len(args)
        if f == "COALESCE" or f == "IFNULL":
            for a in args:
                if a != null:
                    return a
            return null
        if f == "NULLIF":
            if args[0] != null and args[1] != null and compare(args[0], args[1]) == 0:
                return null
            return args[0]
        if f == "TYPEOF":
            v := args[0]
            if v == null:
                return "null"
            t := type(v)
            if t == "int" or t == "bool":
                return "integer"
            if t == "float":
                return "real"
            return "text"
        if n > 0 and args[0] == null:
            return null
        if f == "LOWER":
            return _s.lower(_text(args[0]))
        if f == "UPPER":
            return _s.upper(_text(args[0]))
        if f == "LENGTH":
            return len(_text(args[0]))
        if f == "ABS":
            v := _arith_val(args[0])
            if v < 0:
                return -v
            return v
        if f == "ROUND":
            d := 0
            if n > 1:
                d = args[1]
            m := 1
            i := 0
            while i < d:
                m *= 10
                i += 1
            v := to_float(_arith_val(args[0])) * m
            r := to_int(v + 0.5)
            if v < 0:
                r = -to_int(-v + 0.5)
            return to_float(r) / m
        if f == "SUBSTR" or f == "SUBSTRING":
            s := _text(args[0])
            start := args[1] - 1
            if start < 0:
                start = 0
            stop := len(s)
            if n > 2:
                stop = start + args[2]
            if stop > len(s):
                stop = len(s)
            if start >= stop:
                return ""
            return _s.substring(s, start, stop)
        if f == "TRIM":
            return _s.trim(_text(args[0]))
        if f == "REPLACE":
            return _s.replace(_text(args[0]), _text(args[1]), _text(args[2]))
        if f == "INSTR":
            return _s.find(_text(args[0]), _text(args[1])) + 1
        _e.query_error("fonction SQL inconnue : " + f)

    # ---- instructions ----
    func execute(stmt, params):
        k := stmt["kind"]
        self.changes = 0
        if k == "select":
            return self.select(stmt, params, null)
        if k == "insert":
            return self.insert(stmt, params)
        if k == "update":
            return self.update(stmt, params)
        if k == "delete":
            return self.delete(stmt, params)
        if k == "create_table":
            return self.create_table(stmt)
        if k == "create_index":
            t := self.table(stmt["table"])
            nm := _s.lower(stmt["name"])
            for kk in self.tables:
                if nm in self.tables[kk].indexes:
                    if stmt["if_not_exists"]:
                        return [[], [], 0]
                    _e.query_error("index déjà existant : " + stmt["name"])
            for c in stmt["columns"]:
                if t.column(c) == null:
                    _e.query_error("colonne inconnue : " + c)
            if stmt["unique"]:
                self.check_unique_set(t, stmt["columns"], t.rows, null)
                append(t.uniques, stmt["columns"])
            t.indexes[nm] = {"columns": stmt["columns"], "unique": stmt["unique"]}
            self.dirty = true
            return [[], [], 0]
        if k == "drop_index":
            nm := _s.lower(stmt["name"])
            for kk in self.tables:
                t := self.tables[kk]
                if nm in t.indexes:
                    ix := t.indexes[nm]
                    if ix["unique"]:
                        t.uniques = [u for u in t.uniques if not (u == ix["columns"])]
                    out := {}
                    for i in t.indexes:
                        if i != nm:
                            out[i] = t.indexes[i]
                    t.indexes = out
                    self.dirty = true
                    return [[], [], 0]
            if stmt["if_exists"]:
                return [[], [], 0]
            _e.query_error("index inconnu : " + stmt["name"])
        if k == "drop_table":
            key := _s.lower(stmt["name"])
            if not (key in self.tables):
                if stmt["if_exists"]:
                    return [[], [], 0]
                _e.query_error("table inconnue : " + stmt["name"])
            out := {}
            for kk in self.tables:
                if kk != key:
                    out[kk] = self.tables[kk]
            self.tables = out
            self.dirty = true
            return [[], [], 0]
        if k == "begin":
            self.begin()
            return [[], [], 0]
        if k == "commit":
            self.commit()
            return [[], [], 0]
        if k == "rollback":
            self.rollback()
            return [[], [], 0]
        if k == "savepoint":
            self.savepoint(stmt["name"])
            return [[], [], 0]
        if k == "release":
            self.release(stmt["name"])
            return [[], [], 0]
        if k == "rollback_to":
            self.rollback_to(stmt["name"])
            return [[], [], 0]
        _e.query_error("instruction non prise en charge : " + k)

    func begin():
        if self.tx != null:
            _e.transaction_error("BEGIN : une transaction est déjà ouverte")
        self.tx = _copy_tables(self.tables)
        self.savepoints = []

    func commit():
        if self.tx == null:
            _e.transaction_error("COMMIT : aucune transaction ouverte")
        self.tx = null
        self.savepoints = []
        self.dirty = true

    func rollback():
        if self.tx == null:
            _e.transaction_error("ROLLBACK : aucune transaction ouverte")
        self.tables = self.tx
        self.tx = null
        self.savepoints = []

    func savepoint(name):
        if self.tx == null:
            self.begin()
            append(self.savepoints, [_s.lower(name), null, true])
            return
        append(self.savepoints, [_s.lower(name), _copy_tables(self.tables), false])

    func _sp_index(name):
        i := len(self.savepoints) - 1
        while i >= 0:
            if self.savepoints[i][0] == _s.lower(name):
                return i
            i -= 1
        _e.transaction_error("point de sauvegarde inconnu : " + name)

    func release(name):
        i := self._sp_index(name)
        implicit := self.savepoints[i][2]
        self.savepoints = self.savepoints[:i]
        if implicit:
            self.commit()

    func rollback_to(name):
        i := self._sp_index(name)
        sp := self.savepoints[i]
        if sp[1] == null:
            self.tables = _copy_tables(self.tx)
        else:
            self.tables = _copy_tables(sp[1])
        self.savepoints = self.savepoints[:i + 1]

    func create_table(stmt):
        key := _s.lower(stmt["name"])
        if key in self.tables:
            if stmt["if_not_exists"]:
                return [[], [], 0]
            _e.query_error("table déjà existante : " + stmt["name"])
        names := {}
        for c in stmt["columns"]:
            if _s.lower(c["name"]) in names:
                _e.query_error("colonne en double : " + c["name"])
            names[_s.lower(c["name"])] = true
        self.tables[key] = Table(stmt["name"], stmt["columns"], stmt["uniques"])
        self.dirty = true
        return [[], [], 0]

    func default_of(col):
        if not col["has_default"]:
            return null
        return self.ev(col["default"], {}, null, null)

    func check_row(t, row, skip):
        for c in t.columns:
            v := row[c["name"]]
            if v == null and c["not_null"]:
                _e.integrity_error("NOT NULL : " + t.name + "." + c["name"])
        for c in t.columns:
            if c["primary"] or c["unique"]:
                self.check_unique_set(t, [c["name"]], [row], skip)
        for u in t.uniques:
            self.check_unique_set(t, u, [row], skip)

    func check_unique_set(t, cols, rows, skip):
        seen := {}
        for r in t.rows:
            if skip != null and _same_row(r, skip):
                continue
            vals := [r[c] for c in cols]
            if null in vals:
                continue
            seen[value_key(vals)] = true
        for r in rows:
            vals := [r[t.column(c)["name"]] for c in cols]
            if null in vals:
                continue
            kk := value_key(vals)
            if kk in seen:
                _e.integrity_error("UNIQUE : " + t.name + "(" + _s.join(", ", cols) + ") = " + _s.join(", ", [str(v) for v in vals]))
            seen[kk] = true

    func insert(stmt, params):
        t := self.table(stmt["table"])
        cols := stmt["columns"]
        if cols == null:
            cols = t.column_names()
        resolved := []
        for c in cols:
            cc := t.column(c)
            if cc == null:
                _e.query_error("colonne inconnue : " + stmt["table"] + "." + c)
            append(resolved, cc)
        rows := []
        if stmt["select"] != null:
            rows = self.select(stmt["select"], params, null)[1]
        else:
            rows = [[self.ev(x, {}, params, null) for x in r] for r in stmt["rows"]]
        rid := t.rowid_column()
        n := 0
        saved_rows := t.rows
        saved_next := t.next_id
        saved_last := self.last_id
        t.rows = saved_rows[:]
        try:
            for vals in rows:
                if len(vals) != len(resolved):
                    _e.query_error("INSERT : " + str(len(vals)) + " valeur(s) pour " + str(len(resolved)) + " colonne(s)")
                row := {}
                for c in t.columns:
                    row[c["name"]] = self.default_of(c)
                i := 0
                while i < len(resolved):
                    row[resolved[i]["name"]] = coerce(resolved[i], vals[i])
                    i += 1
                if rid != null and row[rid] == null:
                    row[rid] = t.next_id
                self.check_row(t, row, null)
                if rid != null:
                    if type(row[rid]) == "int" and row[rid] >= t.next_id:
                        t.next_id = row[rid] + 1
                    self.last_id = row[rid]
                else:
                    self.last_id = t.next_id
                    t.next_id += 1
                append(t.rows, row)
                n += 1
        catch e:
            # instruction atomique : rien n'est inséré si une ligne échoue
            t.rows = saved_rows
            t.next_id = saved_next
            self.last_id = saved_last
            raise(e.type, e.message)
        self.changes = n
        self.dirty = true
        return [[], [], n]

    func env_for(t, alias, row, outer=null):
        env := {}
        if outer != null:
            for k in outer:
                env[k] = outer[k]
        for c in t.columns:
            v := row[c["name"]]
            env[_s.lower(c["name"])] = v
            env[_s.lower(alias) + "." + _s.lower(c["name"])] = v
        return env

    func update(stmt, params):
        t := self.table(stmt["table"])
        for st in stmt["sets"]:
            if t.column(st[0]) == null:
                _e.query_error("colonne inconnue : " + stmt["table"] + "." + st[0])
        n := 0
        new_rows := []
        i := 0
        while i < len(t.rows):
            r := t.rows[i]
            env := self.env_for(t, t.name, r)
            if stmt["where"] == null or truthy(self.ev(stmt["where"], env, params, null)):
                nr := _copy_row(r)
                for st in stmt["sets"]:
                    c := t.column(st[0])
                    nr[c["name"]] = coerce(c, self.ev(st[1], env, params, null))
                append(new_rows, [i, nr])
            i += 1
        # contraintes vérifiées sur l'état final
        saved := t.rows
        trial := saved[:]
        for p in new_rows:
            trial[p[0]] = p[1]
        t.rows = trial
        try:
            for p in new_rows:
                self.check_row(t, p[1], p[1])
        catch e:
            t.rows = saved
            raise(e.type, e.message)
        self.changes = len(new_rows)
        self.dirty = true
        return [[], [], len(new_rows)]

    func delete(stmt, params):
        t := self.table(stmt["table"])
        keep := []
        n := 0
        for r in t.rows:
            if stmt["where"] == null or truthy(self.ev(stmt["where"], self.env_for(t, t.name, r), params, null)):
                n += 1
            else:
                append(keep, r)
        t.rows = keep
        self.changes = n
        self.dirty = true
        return [[], [], n]

    func source_rows(q, params, outer):
        envs := [{}]
        if outer != null:
            envs = [outer]
        aliases := []
        for ref in q["from"]:
            t := self.table(ref["table"])
            append(aliases, [ref["alias"], t])
            nxt := []
            for env in envs:
                matched := false
                for r in t.rows:
                    e2 := self.env_for(t, ref["alias"], r, env)
                    if ref["join"] == "inner" or ref["join"] == "left":
                        if not truthy(self.ev(ref["on"], e2, params, null)):
                            continue
                    append(nxt, e2)
                    matched = true
                if ref["join"] == "left" and not matched:
                    nulls := {}
                    for c in t.columns:
                        nulls[c["name"]] = null
                    append(nxt, self.env_for(t, ref["alias"], nulls, env))
            envs = nxt
        return [envs, aliases]

    func has_agg(e):
        if type(e) != "list":
            return false
        if len(e) > 0 and e[0] == "call" and e[1] in AGGREGATES:
            return true
        if len(e) > 0 and (e[0] == "subq" or e[0] == "exists" or e[0] == "insel"):
            return false
        for x in e:
            if type(x) == "list" and self.has_agg(x):
                return true
        return false

    # [colonnes, lignes, nombre]
    func select(q, params, outer):
        src := self.source_rows(q, params, outer)
        envs := src[0]
        aliases := src[1]
        if q["where"] != null:
            envs = [e for e in envs if truthy(self.ev(q["where"], e, params, null))]
        # colonnes de sortie
        cols := []
        exprs := []
        for it in q["items"]:
            if it[0] == "star":
                for a in aliases:
                    if it[1] == null or _s.lower(it[1]) == _s.lower(a[0]):
                        for c in a[1].columns:
                            append(cols, c["name"])
                            append(exprs, ["col", a[0], c["name"]])
                if it[1] != null and len([a for a in aliases if _s.lower(a[0]) == _s.lower(it[1])]) == 0:
                    _e.query_error("table inconnue dans " + it[1] + ".*")
            else:
                nm := it[2]
                if nm == null:
                    nm = _expr_name(it[1])
                append(cols, nm)
                append(exprs, it[1])
        grouped := len(q["group"]) > 0 or q["having"] != null
        for x in exprs:
            if self.has_agg(x):
                grouped = true
        rows := []
        order_envs := []
        if grouped:
            groups := []
            index := {}
            for e in envs:
                kk := value_key([self.ev(g, e, params, null) for g in q["group"]])
                if not (kk in index):
                    index[kk] = len(groups)
                    append(groups, [])
                append(groups[index[kk]], e)
            if len(groups) == 0 and len(q["group"]) == 0:
                append(groups, [])
            for g in groups:
                rep := {}
                if len(g) > 0:
                    rep = g[0]
                if q["having"] != null and not truthy(self.ev(q["having"], rep, params, g)):
                    continue
                row := [self.ev(x, rep, params, g) for x in exprs]
                append(rows, row)
                append(order_envs, [rep, g])
        else:
            for e in envs:
                append(rows, [self.ev(x, e, params, null) for x in exprs])
                append(order_envs, [e, null])
        if q["distinct"]:
            seen := {}
            r2 := []
            o2 := []
            i := 0
            while i < len(rows):
                kk := value_key(rows[i])
                if not (kk in seen):
                    seen[kk] = true
                    append(r2, rows[i])
                    append(o2, order_envs[i])
                i += 1
            rows = r2
            order_envs = o2
        if len(q["order"]) > 0:
            keyed := []
            i := 0
            while i < len(rows):
                env := _with_aliases(order_envs[i][0], cols, rows[i])
                ks := []
                for ob in q["order"]:
                    e := ob[0]
                    if e[0] == "lit" and type(e[1]) == "int" and e[1] >= 1 and e[1] <= len(cols):
                        append(ks, rows[i][e[1] - 1])
                    else:
                        append(ks, self.ev(e, env, params, order_envs[i][1]))
                append(keyed, [ks, rows[i]])
                i += 1
            keyed = _merge_sort(keyed, q["order"])
            rows = [k[1] for k in keyed]
        off := 0
        if q["offset"] != null:
            off = self.ev(q["offset"], {}, params, null)
        if q["limit"] != null:
            lim := self.ev(q["limit"], {}, params, null)
            if lim < 0:
                rows = rows[off:]
            else:
                rows = rows[off:off + lim]
        elif off > 0:
            rows = rows[off:]
        return [cols, rows, len(rows)]

func _with_aliases(env, cols, row):
    al := {}
    i := 0
    while i < len(cols):
        al[_s.lower(cols[i])] = row[i]
        i += 1
    e := {}
    for k in env:
        e[k] = env[k]
    e["$aliases"] = al
    return e

func _expr_name(e):
    if e[0] == "col":
        return e[2]
    if e[0] == "call":
        if e[4]:
            return e[1] + "(*)"
        return e[1] + "(" + _s.join(", ", [_expr_name(a) for a in e[2]]) + ")"
    if e[0] == "lit":
        if e[1] == null:
            return "NULL"
        if type(e[1]) == "str":
            return "'" + e[1] + "'"
        return _text(e[1])
    if e[0] == "param":
        return "?"
    if e[0] == "bin":
        return _expr_name(e[2]) + " " + e[1] + " " + _expr_name(e[3])
    if e[0] == "un":
        if e[1] == "NOT":
            return "NOT " + _expr_name(e[2])
        return "-" + _expr_name(e[2])
    if e[0] == "isnull":
        if e[2]:
            return _expr_name(e[1]) + " IS NOT NULL"
        return _expr_name(e[1]) + " IS NULL"
    return "expr"

func _text(v):
    if type(v) == "bool":
        if v:
            return "1"
        return "0"
    return str(v)

func _same_row(a, b):
    return _r_same(a, b)

func _r_same(a, b):
    for k in a:
        if not (k in b):
            return false
        x := a[k]
        y := b[k]
        if (x == null) != (y == null):
            return false
        if x != null and compare(x, y) != 0:
            return false
    return true

func _cmp_keys(a, b, order):
    i := 0
    while i < len(order):
        c := compare(a[i], b[i])
        if c != 0:
            if order[i][1]:
                return -c
            return c
        i += 1
    return 0

# Tri stable (fusion).
func _merge_sort(items, order):
    n := len(items)
    if n <= 1:
        return items
    mid := n // 2
    left := _merge_sort(items[:mid], order)
    right := _merge_sort(items[mid:], order)
    out := []
    i := 0
    j := 0
    while i < len(left) and j < len(right):
        if _cmp_keys(right[j][0], left[i][0], order) < 0:
            append(out, right[j])
            j += 1
        else:
            append(out, left[i])
            i += 1
    while i < len(left):
        append(out, left[i])
        i += 1
    while j < len(right):
        append(out, right[j])
        j += 1
    return out

func engine_to_dict(eng):
    tables := {}
    for k in eng.tables:
        tables[k] = eng.tables[k].to_dict()
    return {"format": "alexdb", "version": 1, "tables": tables}

func engine_from_dict(d):
    if type(d) != "dict" or not ("format" in d) or d["format"] != "alexdb":
        raise("ConnectionError", "fichier de base ALEX invalide")
    e := Engine()
    for k in d["tables"]:
        e.tables[k] = table_from_dict(d["tables"][k])
    return e
