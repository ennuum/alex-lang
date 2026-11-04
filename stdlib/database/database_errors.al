# ALEX STANDARD LIBRARY — database.database_errors
#
# Types d'erreur du paquet database (inspirés de la DB-API Python) et classement des erreurs SQLite.
#   DatabaseError     erreur générale (base fermée, opération impossible)
#   ConnectionError   ouverture impossible, URL inconnue, connexion fermée
#   QueryError        requête invalide : syntaxe SQL, table / colonne inconnue, paramètre manquant
#   IntegrityError    contrainte violée : PRIMARY KEY, UNIQUE, NOT NULL, type de colonne
#   TransactionError  BEGIN dans une transaction, COMMIT / ROLLBACK sans transaction, point de sauvegarde inconnu
#   PoolError         pool épuisé ou fermé, connexion rendue deux fois
#
#   use database.database_errors as dbe
#   try:
#       conn.execute("INSERT INTO t VALUES (1)")
#   catch IntegrityError as e:
#       print("doublon :", e.message)
#   print(dbe.is_database_error("QueryError"))     # true
#
# Erreurs : celles ci-dessus (levées par les autres modules du paquet).

const DATABASE := "DatabaseError"
const CONNECTION := "ConnectionError"
const QUERY := "QueryError"
const INTEGRITY := "IntegrityError"
const TRANSACTION := "TransactionError"
const POOL := "PoolError"

const ALL := ["DatabaseError", "ConnectionError", "QueryError", "IntegrityError", "TransactionError", "PoolError"]

func is_database_error(error_type):
    return error_type in ALL

func query_error(msg):
    raise(QUERY, msg)

func integrity_error(msg):
    raise(INTEGRITY, msg)

func transaction_error(msg):
    raise(TRANSACTION, msg)

# Type d'erreur ALEX pour un code de retour SQLite (primaire : code & 0xFF).
func from_sqlite_code(code):
    c := code % 256
    if c == 19:
        return INTEGRITY
    if c == 1 or c == 12 or c == 25:
        return QUERY
    if c == 14 or c == 8 or c == 23:
        return CONNECTION
    return DATABASE
