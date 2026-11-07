# Tests : DDL du moteur SQL embarqué (memory:) comparé à SQLite (s'il est installé) — clés étrangères dans
# CREATE TABLE, ALTER TABLE (ADD / RENAME / RENAME COLUMN / DROP COLUMN), LIMIT très grand avec OFFSET.
# Le même scénario tourne sur les deux moteurs : ce que l'ORM d'alweb envoie à SQLite doit aussi passer ici.
from core use len
use check as t
use database.database as db

func scenario(url, label):
    c := db.connect(url)
    # clés étrangères : contrainte de table, REFERENCES en ligne, CONSTRAINT nom, actions ON DELETE / UPDATE
    c.executescript("CREATE TABLE comptes (id INTEGER PRIMARY KEY AUTOINCREMENT, nom TEXT NOT NULL UNIQUE); " +
                    "CREATE TABLE articles (id INTEGER PRIMARY KEY AUTOINCREMENT, titre TEXT NOT NULL, auteur_id INTEGER NOT NULL, " +
                    "FOREIGN KEY (auteur_id) REFERENCES comptes (id));")
    c.execute("CREATE TABLE notes (id INTEGER PRIMARY KEY, a INTEGER REFERENCES articles (id) ON DELETE CASCADE ON UPDATE NO ACTION, " +
              "b INTEGER references comptes, CONSTRAINT fk_b FOREIGN KEY (b) REFERENCES comptes (id) ON DELETE SET NULL, " +
              "CONSTRAINT u_ab UNIQUE (a, b))")
    t.check(c.has_table("notes"), label + " clés étrangères acceptées")
    c.execute("INSERT INTO comptes (nom) VALUES ('awa'), ('kofi')")
    c.execute("INSERT INTO articles (titre, auteur_id) VALUES ('un', 1), ('deux', 2), ('trois', 1)")
    t.eq(c.query_one("SELECT a.titre AS t, c.nom AS n FROM articles a JOIN comptes c ON a.auteur_id = c.id WHERE a.id = 2")["n"], "kofi", label + " jointure par la clé")
    c.execute("INSERT INTO notes (id, a, b) VALUES (1, 1, 1)")
    t.raises(() => c.execute("INSERT INTO notes (id, a, b) VALUES (2, 1, 1)"), "IntegrityError", label + " CONSTRAINT UNIQUE")
    t.raises(() => c.execute("CREATE TABLE z (a INT, FOREIGN KEY (a) x)"), "QueryError", label + " REFERENCES manquant")

    # ALTER TABLE ADD COLUMN : lignes existantes complétées par la valeur par défaut
    c.execute("ALTER TABLE comptes ADD COLUMN bio TEXT")
    c.execute("ALTER TABLE comptes ADD actif INTEGER NOT NULL DEFAULT 1")
    t.eq(c.execute("SELECT nom, bio, actif FROM comptes ORDER BY id").rows, [["awa", null, 1], ["kofi", null, 1]], label + " ADD COLUMN")
    c.execute("INSERT INTO comptes (nom, bio) VALUES ('ada', 'x')")
    t.eq(c.scalar("SELECT actif FROM comptes WHERE nom = 'ada'"), 1, label + " défaut d'une colonne ajoutée")
    t.raises(() => c.execute("ALTER TABLE comptes ADD COLUMN bio TEXT"), "QueryError", label + " ADD COLUMN en double")
    t.raises(() => c.execute("ALTER TABLE comptes ADD COLUMN req TEXT NOT NULL"), "QueryError", label + " ADD NOT NULL sans défaut")
    t.raises(() => c.execute("ALTER TABLE comptes ADD COLUMN u TEXT UNIQUE"), "QueryError", label + " ADD UNIQUE")
    c.execute("ALTER TABLE articles ADD COLUMN relu_par INTEGER REFERENCES comptes (id)")
    t.eq(c.scalar("SELECT COUNT(*) FROM articles WHERE relu_par IS NULL"), 3, label + " ADD COLUMN avec REFERENCES")

    # RENAME COLUMN : données, contrainte UNIQUE et index suivent
    c.execute("CREATE INDEX i_titre ON articles (titre)")
    c.execute("ALTER TABLE articles RENAME COLUMN titre TO intitule")
    t.eq(c.execute("SELECT intitule FROM articles ORDER BY id").column("intitule"), ["un", "deux", "trois"], label + " RENAME COLUMN")
    c.execute("ALTER TABLE comptes RENAME nom TO pseudo")
    t.raises(() => c.execute("INSERT INTO comptes (pseudo) VALUES ('awa')"), "IntegrityError", label + " UNIQUE suit le renommage")
    t.raises(() => c.execute("SELECT titre FROM articles"), "QueryError", label + " ancien nom oublié")

    # RENAME TO
    c.execute("ALTER TABLE notes RENAME TO remarques")
    t.check(c.has_table("remarques") and not c.has_table("notes"), label + " RENAME TO")
    t.eq(c.scalar("SELECT COUNT(*) FROM remarques"), 1, label + " données gardées au renommage")
    t.raises(() => c.execute("ALTER TABLE remarques RENAME TO comptes"), "QueryError", label + " RENAME vers une table existante")

    # DROP COLUMN
    c.execute("ALTER TABLE comptes DROP COLUMN bio")
    t.eq(c.execute("SELECT * FROM comptes ORDER BY id").columns, ["id", "pseudo", "actif"], label + " DROP COLUMN")
    t.raises(() => c.execute("ALTER TABLE comptes DROP COLUMN id"), "QueryError", label + " DROP de la clé primaire")
    t.raises(() => c.execute("ALTER TABLE comptes DROP COLUMN pseudo"), "QueryError", label + " DROP d'une colonne UNIQUE")
    t.raises(() => c.execute("ALTER TABLE comptes DROP COLUMN absente"), "QueryError", label + " DROP d'une colonne inconnue")

    # ALTER dans une transaction annulée : la table revient telle qu'avant
    c.execute("BEGIN")
    c.execute("ALTER TABLE comptes ADD COLUMN tmp INTEGER DEFAULT 7")
    c.execute("ALTER TABLE articles RENAME COLUMN intitule TO libelle")
    c.execute("ROLLBACK")
    t.eq(c.execute("SELECT * FROM comptes ORDER BY id").columns, ["id", "pseudo", "actif"], label + " ROLLBACK d'un ADD COLUMN")
    t.eq(c.scalar("SELECT intitule FROM articles WHERE id = 1"), "un", label + " ROLLBACK d'un RENAME COLUMN")

    # LIMIT très grand avec OFFSET (ce qu'écrit l'ORM pour un offset sans limite)
    i := 0
    while i < 25:
        c.execute("INSERT INTO articles (intitule, auteur_id) VALUES (?, 1)", ["n" + str(i)])
        i += 1
    t.eq(len(c.execute("SELECT id FROM articles ORDER BY id LIMIT 9223372036854775807 OFFSET 24").rows), 4, label + " LIMIT max OFFSET")
    t.eq(len(c.execute("SELECT id FROM articles LIMIT -1 OFFSET 26").rows), 2, label + " LIMIT -1 OFFSET")
    t.eq(len(c.execute("SELECT id FROM articles LIMIT 3 OFFSET 26").rows), 2, label + " LIMIT au-delà de la fin")
    t.eq(len(c.execute("SELECT id FROM articles LIMIT 5 OFFSET 100").rows), 0, label + " OFFSET au-delà de la fin")
    c.close()

scenario("memory:", "memory")
if "sqlite" in db.backends():
    scenario("sqlite::memory:", "sqlite")

t.summary("test_database_ddl")
