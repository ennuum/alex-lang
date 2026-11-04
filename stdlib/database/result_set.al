# ALEX STANDARD LIBRARY — database.result_set
#
# Résultat d'une requête : noms de colonnes, lignes, nombre de lignes touchées et dernier identifiant inséré.
# Lecture par curseur (fetch_one / fetch_many / fetch_all), par index (rs[0]), par itération (for ligne in rs),
# en dictionnaires, par colonne, ou valeur unique (scalar). Une ligne (Row) s'indexe par position ou par nom.
#
#   rs := conn.execute("SELECT id, nom FROM clients ORDER BY id")
#   print(rs.columns, rs.size())          # [id, nom] 3
#   for ligne in rs:
#       print(ligne["nom"], ligne[0])
#   print(rs.dicts())                     # [{"id": 1, "nom": "Ana"}, ...]
#   print(rs.column("nom"))               # ["Ana", "Bob", ...]
#   print(conn.execute("SELECT COUNT(*) FROM clients").scalar())
#   r := rs.fetch_one()                    # curseur : première ligne, puis la suivante...
#   print(rs.to_table())                   # tableau texte aligné
#
# Erreurs : IndexError (ligne hors limites), KeyError (colonne inconnue), QueryError (scalar sur résultat vide
# avec strict).

from core use len, type
from collections use append
use string as _s

class Row:
    func init(columns, values):
        self.columns = columns
        self.values = values

    func __getitem__(key):
        if type(key) == "int":
            return self.values[key]
        i := self.index_of(key)
        if i < 0:
            raise("KeyError", "colonne inconnue : " + str(key))
        return self.values[i]

    func index_of(name):
        i := 0
        while i < len(self.columns):
            if self.columns[i] == name:
                return i
            i += 1
        i = 0
        while i < len(self.columns):
            if _s.lower(self.columns[i]) == _s.lower(name):
                return i
            i += 1
        return -1

    func get(name, default=null):
        i := self.index_of(name)
        if i < 0:
            return default
        return self.values[i]

    func keys():
        return self.columns[:]

    func to_dict():
        d := {}
        i := 0
        while i < len(self.columns):
            d[self.columns[i]] = self.values[i]
            i += 1
        return d

    func to_list():
        return self.values[:]

    func size():
        return len(self.values)

    func __eq__(other):
        if type(other) == "list":
            return self.values == other
        return false

    func __str__():
        return "Row(" + _s.join(", ", [self.columns[i] + "=" + _show(self.values[i]) for i in 0..len(self.values)]) + ")"

func _show(v):
    if v == null:
        return "NULL"
    if type(v) == "str":
        return "'" + v + "'"
    return str(v)

class ResultSet:
    func init(columns, rows, rowcount=0, lastrowid=null):
        self.columns = columns
        self.rows = rows
        self.rowcount = rowcount
        self.lastrowid = lastrowid
        self.cursor = 0

    func size():
        return len(self.rows)

    func is_empty():
        return len(self.rows) == 0

    func __getitem__(i):
        if i < 0 or i >= len(self.rows):
            raise("IndexError", "ResultSet : ligne " + str(i) + " hors limites (" + str(len(self.rows)) + " lignes)")
        return Row(self.columns, self.rows[i])

    func fetch_one():
        if self.cursor >= len(self.rows):
            return null
        r := Row(self.columns, self.rows[self.cursor])
        self.cursor += 1
        return r

    func fetch_many(n):
        out := []
        while len(out) < n and self.cursor < len(self.rows):
            append(out, Row(self.columns, self.rows[self.cursor]))
            self.cursor += 1
        return out

    func fetch_all():
        out := [Row(self.columns, self.rows[i]) for i in self.cursor..len(self.rows)]
        self.cursor = len(self.rows)
        return out

    func rewind():
        self.cursor = 0
        return self

    func first():
        if len(self.rows) == 0:
            return null
        return Row(self.columns, self.rows[0])

    # Première colonne de la première ligne (null si vide ; QueryError si strict).
    func scalar(strict=false):
        if len(self.rows) == 0 or len(self.columns) == 0:
            if strict:
                raise("QueryError", "scalar : résultat vide")
            return null
        return self.rows[0][0]

    func column(name):
        i := 0
        idx := -1
        while i < len(self.columns):
            if _s.lower(self.columns[i]) == _s.lower(str(name)):
                idx = i
            i += 1
        if type(name) == "int":
            idx = name
        if idx < 0:
            raise("KeyError", "colonne inconnue : " + str(name))
        return [r[idx] for r in self.rows]

    func dicts():
        return [Row(self.columns, r).to_dict() for r in self.rows]

    func tuples():
        return [r[:] for r in self.rows]

    func map(fn):
        return [fn(Row(self.columns, r)) for r in self.rows]

    func to_table(max_width=40):
        cells := [[_cut(c, max_width) for c in self.columns]]
        for r in self.rows:
            append(cells, [_cut(_show_plain(v), max_width) for v in r])
        widths := []
        for c in self.columns:
            append(widths, 0)
        for row in cells:
            i := 0
            while i < len(row):
                if len(row[i]) > widths[i]:
                    widths[i] = len(row[i])
                i += 1
        lines := []
        k := 0
        for row in cells:
            parts := []
            i := 0
            while i < len(row):
                parts = parts + [row[i] + _s.repeat(" ", widths[i] - len(row[i]))]
                i += 1
            append(lines, _s.trim(_s.join(" | ", parts)))
            if k == 0:
                append(lines, _s.join("-+-", [_s.repeat("-", w) for w in widths]))
            k += 1
        return _s.join("\n", lines)

    func __str__():
        return "ResultSet(" + str(len(self.rows)) + " lignes, colonnes " + str(self.columns) + ")"

func _show_plain(v):
    if v == null:
        return "NULL"
    return str(v)

func _cut(s, n):
    if len(s) <= n:
        return s
    return _s.substring(s, 0, n - 1) + "…"
