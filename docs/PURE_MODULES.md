# Modules ALEX purs : `path`, `json`, `csv`, `xml`, `regex`, `testing`, `logging`, `crypto`, `filesystem`, `file`, `time`, `datetime`

Ces douze modules sont écrits **100 % en ALEX** (`stdlib/<module>/<module>.al`) : aucune primitive C++ dédiée.
Ils ne s'appuient que sur `string` (dont `chr` / `ord` / `slice`), `collections`, `core`, et sur `io` / `os`
pour les fichiers et l'horloge (`csv`, `xml`, `logging`, `testing`, `filesystem`, `file`) ; `crypto` n'utilise que `string`. Tests : `make test-stdlib-pure`.

Conventions communes : `s[i]` renvoie un `char` (≠ `str`) donc les modules travaillent sur des listes de `str` d'un
caractère ; positions en points de code Unicode ; erreurs `raise("XxxError", message)` avec position quand c'est utile.

| Module | Rôle | Erreurs | Test |
|---|---|---|---|
| `path` | chemins lexicaux POSIX/Windows : `join normalize dirname basename split stem extension with_extension with_name parts relative_to is_subpath common_prefix is_absolute glob_match` (dernier paramètre `win` : null = plateforme) | `TypeError`, `ValueError` | `tests/test_path.al` |
| `json` | `parse stringify pretty load save`, Unicode complet (`\uXXXX`, paires de substitution) | `JSONError` | `tests/test_json.al` |
| `csv` | RFC 4180 : `parse parse_dict stringify stringify_dict load load_dict save` | `CSVError` | `tests/test_csv.al` |
| `xml` | `parse element find find_all children attr text stringify pretty escape unescape load save is_valid` ; élément = `{"tag","attrs","children"}` | `XMLError` | `tests/test_xml.al` |
| `regex` | moteur à retour arrière : `compile test match_start fullmatch search finditer find_all replace split escape` | `RegexError` | `tests/test_regex.al` |
| `crypto` | `md5 sha1 sha256 sha512` (+ `_bytes`, `hash_hex`), `hmac`, `pbkdf2`, `chacha20` (RFC 8439), `hex_*`, `base64_*` (+ URL-safe), `utf8_*`, `equals` (temps constant) | `ValueError`, `TypeError` | `tests/test_crypto.al` |
| `filesystem` | arborescence : `kind_of stat is_empty tree_size same_file is_inside list_dir list_files list_dirs walk find glob ensure_dir ensure_parent ensure_file touch remove remove_tree clear_dir copy move make_temp_dir with_temp_dir make_temp_file with_temp_file` | `TypeError`, `ValueError`, `IoError` | `tests/test_filesystem.al` |
| `file` | contenu texte et binaire : `read read_or read_lines line_count head tail write append write_lines append_lines read_bytes write_bytes append_bytes write_atomic create delete open with_open` + objet `File` (modes `r w a x` `+` `b` ; `read read_line read_lines seek tell rewind size eof write write_line write_lines truncate flush close`) | `TypeError`, `ValueError`, `IoError` | `tests/test_file.al` |
| `time` | horloges, calendrier grégorien proleptique (toute année), `strftime`/`strptime`, ISO 8601, durées texte, `Stopwatch`/`Deadline`, horloge simulée (voir `docs/TIME_DATETIME.md`) | `ValueError`, `TypeError`, `TimeoutError` | `tests/test_time.al` |
| `datetime` | `Date` `Time` `DateTime` `Duration` `Period` `TimeZone` (heure d'été), arithmétique murale / exacte, jours ouvrés, fériés FR (voir `docs/TIME_DATETIME.md`) | `ValueError`, `TypeError`, `ZeroDivisionError` | `tests/test_datetime.al` |
| `testing` | `test skip before_each after_each run run_tests summary` + `assert_*` | `AssertionError` | `tests/test_testing_logging.al` |
| `logging` | niveaux, loggers hiérarchiques, handlers console / fichier / fonction, format, horloge | `ValueError`, `TypeError` | `tests/test_testing_logging.al` |

## Points d'attention

- **`regex.match_start`** s'appelle ainsi car `match` est un mot-clé d'ALEX. Pas de `(?i)` en ligne : drapeaux via le
  paramètre `flags` (`"i"`, `"m"`, `"s"`). Pas de lookbehind. La casse Unicode couvre latin, grec et cyrillique.
  Le moteur est récursif : éviter les motifs imbriqués ambigus (`(a+)+b`) sur des entrées non fiables. Les répétitions
  simples (`a*`, `[a-z]+`, `.*`) sont itératives et supportent de longs textes.
- **`xml`** n'est pas validant : pas d'espaces de noms, pas de sous-ensemble interne de DOCTYPE. Les attributs sont
  triés à la sérialisation.
- **`csv`** ne convertit aucun type à la lecture (tout est `str`).
- **`path`** est lexical : il ne touche jamais au disque (voir `os` pour `exists`, `list_dir`, `realpath`...).
- **`logging`** écrit l'heure en UTC ; `set_clock` permet des tests déterministes.
- **`testing`** : les tests s'enregistrent avec des fonctions nommées (ou des lambdas à expression unique) ; ALEX n'a pas
  de `func():` anonyme multi-lignes.

## `filesystem` et `file` : ce qu'il faut savoir

- **Répartition** : `filesystem` s'occupe de l'arborescence (lister, chercher, créer, copier, supprimer, fichiers et
  dossiers temporaires) ; `file` du contenu des fichiers, texte et binaire. `os` reste la couche primitive, `path` le
  calcul lexical.
- **Primitives natives ajoutées** (C++, `runtime/native/io/io_native.cpp` et `os_backend_*.cpp`) : `io.read_text`,
  `io.read_line`, `io.read_bytes`, `io.write_bytes`, `io.write_bytes_at`, `io.write_at`, `io.truncate`,
  `io.create_file` (accès à une **position** en octets, création **exclusive**) et `os.set_times` (dates d'accès et de
  modification). Les deux modules ALEX ne sont qu'une couche au-dessus.
- **`filesystem.find` / `walk` / `list_*`** : ordre déterministe (entrées triées par nom, parcours en profondeur).
  Les liens symboliques ne sont jamais descendus par `find`, `tree_size`, `remove_tree` et `clear_dir` ; `walk` ne
  les suit que sur demande (`follow_links`), avec détection des cycles.
- **`filesystem.glob`** : motif par segments (`*`, `?`, `[...]`, `**` = zéro ou plusieurs dossiers). `*` ne traite pas
  les fichiers cachés à part.
- **`remove_tree` / `clear_dir`** sont irréversibles. Ils refusent (`ValueError`) : le chemin vide, tout chemin se
  terminant par `.` ou `..`, la racine du disque, et tout dossier qui **contient** le dossier de travail courant ou le
  dossier personnel. Un lien symbolique est retiré sans toucher à sa cible.
- **Création exclusive** (`io.create_file`, `file.create`, mode `x`, `ensure_file`, `make_temp_file`) : le noyau refuse
  si le chemin existe, y compris un lien symbolique (même cassé) qui n'est jamais suivi. Vérifié avec 30 processus qui
  se disputent le même fichier : un seul réussit. `touch` crée un fichier vide ou met les dates à « maintenant » ;
  `ensure_file` ne modifie jamais un fichier existant.
- **Fichiers et dossiers temporaires** : `make_temp_dir` (`mkdir` atomique, droits 0700) et `make_temp_file` (création
  exclusive, droits 0600), avec `with_temp_dir` / `with_temp_file` qui nettoient même en cas d'erreur. Ils ne
  protègent pas contre un autre processus du même utilisateur qui connaîtrait le nom.
- **`file` texte** : UTF-8 lu et écrit tel quel (aucune conversion à l'écriture). À la lecture par `File`,
  `read_lines`, `head`, `tail` et `line_count`, `\n`, `\r\n` et `\r` sont rendus `\n` ; `file.read(p)` rend les octets
  exacts. **Binaire** : listes d'int 0..255, comme dans `crypto`.
- **`file.File`** : modes `r w a x`, suffixes `+` et `b` dans n'importe quel ordre (`"r+"`, `"wb"`, `"ab+"`...),
  `seek(offset, whence)` / `tell()` / `truncate()`. Il lit **en flux** : rien n'est chargé à l'ouverture, chaque
  opération ouvre le fichier, agit à la position courante, puis le referme. Conséquences : les écritures sont
  immédiates (`flush` ne fait rien) et un fichier modifié par un autre processus est vu tel qu'il est. Les positions
  sont des **octets** ; `read(size)` en texte compte des caractères. Se placer au milieu d'un caractère UTF-8 est
  permis mais produit un caractère orphelin : préférer 0, la fin, ou une valeur rendue par `tell()`.
- **`file.write_atomic`** (texte ou octets) écrit dans un fichier voisin puis le renomme : un lecteur ne voit jamais un
  contenu partiel, et les droits d'un fichier existant sont conservés.
- **Windows** : les primitives (`_wopen` avec `_O_EXCL`, `SetFileTime`) sont écrites mais n'ont pas pu être compilées
  ni exécutées dans l'environnement de développement (Linux) : à valider sur cette plateforme.
- Passer `null` à un paramètre optionnel revient à l'omettre (règle du compilateur : « limite assumée » dans
  `src/Compiler.cpp`). Les fonctions de ces modules n'attribuent donc jamais de sens particulier à un `null` explicite.

## `crypto` : ce qu'il faut savoir avant de l'utiliser

- **Vérifié** contre `hashlib`, `hmac`, `pbkdf2_hmac`, `base64` de Python et la bibliothèque `cryptography` (ChaCha20,
  RFC 8439), y compris aux frontières de bloc du rembourrage (55, 56, 63, 64, 111, 112, 127, 128 octets).
- **Pas de générateur aléatoire sûr** : ALEX n'expose pas d'entropie système, et `random` n'est pas cryptographique.
  Clés, sels et nonces doivent venir d'ailleurs ; ne jamais réutiliser un couple (clé, nonce) avec `chacha20`.
- `chacha20` ne protège pas l'intégrité : chiffrer puis authentifier avec `hmac`, et comparer avec `equals`.
- MD5 et SHA-1 restent là pour la compatibilité ; ne pas s'en servir pour la sécurité.
- Lent (25 à 45 Ko/s ; PBKDF2-SHA256 ≈ 1 s pour 1000 itérations). Pas de protection contre les attaques par canaux
  auxiliaires en dehors de `equals`.
