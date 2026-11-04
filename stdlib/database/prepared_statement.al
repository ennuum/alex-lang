# ALEX STANDARD LIBRARY — database.prepared_statement
#
# Requête préparée : le texte SQL est analysé (ou compilé par SQLite) UNE fois, puis exécuté autant de fois que
# voulu avec des paramètres différents — plus rapide pour les insertions en série, et sûr : les valeurs ne
# sont jamais collées dans le texte SQL (pas d'injection).
#
#   st := conn.prepare("INSERT INTO mesures (capteur, valeur) VALUES (?, ?)")
#   for m in lot:
#       st.execute([m["id"], m["v"]])
#   print(st.executions, st.param_count())
#   st.execute_many([[1, 2.5], [2, 3.1]])
#   st.close()
#   with conn.prepare("SELECT * FROM t WHERE id = :id") as q:
#       print(q.execute({"id": 3}).first())
#
# Erreurs : QueryError (SQL invalide, paramètre manquant), DatabaseError (instruction fermée), et celles de
# l'exécution (IntegrityError...).

from core use len, type
from collections use append
use database.result_set as _rs
use database._sql as _sql

class PreparedStatement:
    func init(conn, sql):
        self.conn = conn
        self.sql = sql
        self.executions = 0
        self.closed = false
        self._native = null
        self._parsed = null
        conn._check_open()
        if conn.backend == "sqlite":
            self._native = conn._impl.db.prepare(sql)
        else:
            self._parsed = _sql.parse(sql)
            if len(self._parsed) != 1:
                raise("QueryError", "prepare : une seule instruction SQL attendue (" + str(len(self._parsed)) + " trouvées)")

    func param_count():
        if self._native != null:
            return self._native.nparams
        return _sql.count_params(self.sql)

    func execute(params=null):
        if self.closed:
            raise("DatabaseError", "PreparedStatement : instruction fermée")
        self.conn._check_open()
        self.executions += 1
        if self._native != null:
            r := self._native.run(params)
            return self.conn._result(r, self.sql)
        return self.conn._impl.run_parsed(self._parsed, params, self.conn)

    # Exécute pour chaque jeu de paramètres ; total des lignes touchées.
    func execute_many(param_sets):
        total := 0
        for p in param_sets:
            total += self.execute(p).rowcount
        return total

    func close():
        if not self.closed:
            if self._native != null:
                self._native.close()
            self.closed = true

    func __enter__():
        return self

    func __exit__(a, b, c):
        self.close()
