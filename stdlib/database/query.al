# ALEX STANDARD LIBRARY — database.query
#
# Construction de requêtes SQL par méthodes chaînées, avec paramètres liés (jamais de valeurs collées dans le
# texte) : SELECT (colonnes, jointures, conditions, groupement, tri, pagination), INSERT, UPDATE, DELETE.
#
#   use database.query as q
#   r := q.select("clients", ["id", "nom"]).where("age >= ?", [18]).where_eq("ville", "Lyon")
#          .order_by("nom").limit(10).offset(20)
#   print(r.sql())        # SELECT id, nom FROM clients WHERE (age >= ?) AND (ville = ?) ORDER BY nom LIMIT 10 OFFSET 20
#   print(r.params())     # [18, "Lyon"]
#   lignes := r.run(conn).dicts()
#   n := q.select("commandes").where_in("statut", ["ouverte", "payée"]).count(conn)
#   q.insert("clients", {"nom": "Ana", "age": 30}).run(conn)
#   q.update("clients").set({"ville": "Paris"}).where_eq("id", 3).run(conn)
#   q.delete("clients").where("age < ?", [0]).run(conn)
#   j := q.select("clients c", ["c.nom", "SUM(o.total) AS total"]).join("commandes o", "o.client_id = c.id", "LEFT")
#          .group_by(["c.nom"]).having("SUM(o.total) > ?", [100])
#
# Les noms (tables, colonnes) sont écrits tels quels : ne jamais y placer une donnée venue de l'utilisateur
# (utiliser connection.quote_identifier). Erreurs : ArgumentError (construction incohérente), et celles de
# l'exécution (QueryError...).

from core use len, type
from collections use append
use string as _s
use database.connection as _c

class Query:
    func init(kind, table):
        self.kind = kind
        self.table = table
        self.cols = ["*"]
        self.joins = []
        self.conds = []
        self.cond_params = []
        self.groups = []
        self.having_sql = null
        self.having_params = []
        self.orders = []
        self.limit_n = null
        self.offset_n = null
        self.is_distinct = false
        self.values = null
        self.rows = []

    func columns(cols):
        self.cols = cols
        return self

    func distinct():
        self.is_distinct = true
        return self

    func join(table, on, kind="INNER"):
        append(self.joins, _s.upper(kind) + " JOIN " + table + " ON " + on)
        return self

    func left_join(table, on):
        return self.join(table, on, "LEFT")

    func where(cond, params=null):
        append(self.conds, cond)
        if params != null:
            if type(params) != "list":
                params = [params]
            self.cond_params = self.cond_params + params
        return self

    func where_eq(col, value):
        if value == null:
            return self.where(col + " IS NULL")
        return self.where(col + " = ?", [value])

    func where_in(col, values):
        if len(values) == 0:
            return self.where("0 = 1")
        return self.where(col + " IN (" + _s.join(", ", ["?" for v in values]) + ")", values)

    func where_between(col, lo, hi):
        return self.where(col + " BETWEEN ? AND ?", [lo, hi])

    func where_like(col, pattern):
        return self.where(col + " LIKE ?", [pattern])

    func group_by(cols):
        if type(cols) == "str":
            cols = [cols]
        self.groups = self.groups + cols
        return self

    func having(cond, params=null):
        self.having_sql = cond
        if params != null:
            self.having_params = params
        return self

    func order_by(col, desc=false):
        if desc:
            append(self.orders, col + " DESC")
        else:
            append(self.orders, col)
        return self

    func limit(n):
        self.limit_n = n
        return self

    func offset(n):
        self.offset_n = n
        return self

    func page(number, size):
        self.limit_n = size
        self.offset_n = (number - 1) * size
        return self

    func set(values):
        if self.kind != "update":
            raise("ArgumentError", "Query.set : réservé à update()")
        self.values = values
        return self

    func _where_sql():
        if len(self.conds) == 0:
            return ""
        if len(self.conds) == 1:
            return " WHERE " + self.conds[0]
        return " WHERE " + _s.join(" AND ", ["(" + c + ")" for c in self.conds])

    func sql():
        k := self.kind
        if k == "select":
            out := "SELECT "
            if self.is_distinct:
                out += "DISTINCT "
            out += _s.join(", ", self.cols) + " FROM " + self.table
            for j in self.joins:
                out += " " + j
            out += self._where_sql()
            if len(self.groups) > 0:
                out += " GROUP BY " + _s.join(", ", self.groups)
            if self.having_sql != null:
                out += " HAVING " + self.having_sql
            if len(self.orders) > 0:
                out += " ORDER BY " + _s.join(", ", self.orders)
            if self.limit_n != null:
                out += " LIMIT " + str(self.limit_n)
            if self.offset_n != null:
                if self.limit_n == null:
                    out += " LIMIT -1"
                out += " OFFSET " + str(self.offset_n)
            return out
        if k == "insert":
            if len(self.rows) == 0:
                raise("ArgumentError", "insert : aucune ligne")
            cols := [c for c in self.rows[0]]
            ph := "(" + _s.join(", ", ["?" for c in cols]) + ")"
            return "INSERT INTO " + self.table + " (" + _s.join(", ", [_c.quote_identifier(c) for c in cols]) + ") VALUES " + _s.join(", ", [ph for r in self.rows])
        if k == "update":
            if self.values == null or len(self.values) == 0:
                raise("ArgumentError", "update : set({...}) attendu")
            return "UPDATE " + self.table + " SET " + _s.join(", ", [_c.quote_identifier(c) + " = ?" for c in self.values]) + self._where_sql()
        if k == "delete":
            return "DELETE FROM " + self.table + self._where_sql()
        raise("ArgumentError", "requête inconnue " + k)

    func params():
        k := self.kind
        if k == "select":
            return self.cond_params + self.having_params
        if k == "insert":
            cols := [c for c in self.rows[0]]
            out := []
            for r in self.rows:
                for c in cols:
                    if not (c in r):
                        raise("ArgumentError", "insert : colonne '" + c + "' absente d'une ligne")
                    append(out, r[c])
            return out
        if k == "update":
            return [self.values[c] for c in self.values] + self.cond_params
        return self.cond_params

    func build():
        return [self.sql(), self.params()]

    func run(conn):
        return conn.execute(self.sql(), self.params())

    func all(conn):
        return self.run(conn).dicts()

    func first(conn):
        saved := self.limit_n
        self.limit_n = 1
        r := self.run(conn).first()
        self.limit_n = saved
        if r == null:
            return null
        return r.to_dict()

    func count(conn):
        q := Query("select", self.table)
        q.joins = self.joins
        q.conds = self.conds
        q.cond_params = self.cond_params
        q.cols = ["COUNT(*)"]
        return q.run(conn).scalar()

    func __str__():
        return self.sql()

func select(table, cols=null):
    q := Query("select", table)
    if cols != null:
        if type(cols) == "str":
            cols = [cols]
        q.cols = cols
    return q

func insert(table, values):
    q := Query("insert", table)
    if type(values) == "list":
        q.rows = values
    else:
        q.rows = [values]
    return q

func update(table):
    return Query("update", table)

func delete(table):
    return Query("delete", table)
