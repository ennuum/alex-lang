# ALEX STANDARD LIBRARY — database.transaction
#
# Transactions : tout ou rien. Une Transaction ouverte alors qu'une autre est déjà en cours devient un POINT DE
# SAUVEGARDE (SAVEPOINT) : on peut annuler une partie sans tout perdre (transactions imbriquées).
#
#   use database.transaction as tx
#   t := tx.Transaction(conn).begin()
#   conn.execute("UPDATE comptes SET solde = solde - 50 WHERE id = 1")
#   conn.execute("UPDATE comptes SET solde = solde + 50 WHERE id = 2")
#   t.commit()
#
#   tx.run(conn, (c) => virement(c, 1, 2, 50))     # validée si la fonction réussit, annulée (et l'erreur
#                                                  # relancée) sinon
#   with tx.Transaction(conn) as t:                # ATTENTION : sans t.commit() avant la fin du bloc, la
#       ...                                        # transaction est ANNULÉE (with ne connaît pas l'erreur)
#       t.commit()
#
# Erreurs : TransactionError (commit / rollback répétés, transaction déjà terminée).

from core use len, type

_counter := [0]

class Transaction:
    func init(conn):
        self.conn = conn
        self.savepoint = null
        self.state = "new"            # new | active | committed | rolled_back

    func begin():
        if self.state != "new":
            raise("TransactionError", "Transaction.begin : déjà " + self.state)
        if self.conn.in_transaction():
            _counter[0] += 1
            self.savepoint = "alex_sp_" + str(_counter[0])
            self.conn.execute("SAVEPOINT " + self.savepoint)
        else:
            self.conn.begin()
        self.state = "active"
        return self

    func active():
        return self.state == "active"

    func nested():
        return self.savepoint != null

    func _need_active(what):
        if self.state != "active":
            raise("TransactionError", "Transaction." + what + " : transaction " + self.state)

    func commit():
        self._need_active("commit")
        if self.savepoint != null:
            self.conn.execute("RELEASE SAVEPOINT " + self.savepoint)
        else:
            self.conn.commit()
        self.state = "committed"

    func rollback():
        self._need_active("rollback")
        if self.savepoint != null:
            self.conn.execute("ROLLBACK TO SAVEPOINT " + self.savepoint)
            self.conn.execute("RELEASE SAVEPOINT " + self.savepoint)
        else:
            self.conn.rollback()
        self.state = "rolled_back"

    func __enter__():
        if self.state == "new":
            self.begin()
        return self

    func __exit__(a, b, c):
        if self.state == "active":
            self.rollback()

# fn(conn) dans une transaction : validée si fn réussit, sinon annulée et l'erreur relancée.
func run(conn, fn):
    t := Transaction(conn).begin()
    r := null
    try:
        r = fn(conn)
    catch e:
        if t.active():
            t.rollback()
        raise(e.type, e.message)
    if t.active():
        t.commit()
    return r
