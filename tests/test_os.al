# =============================================================================
# ALEX - suite de tests du module stdlib/os/os.al
# =============================================================================
# Couvre les 70 fonctions publiques du module :
#   système, arguments, environnement, chemins, système de fichiers,
#   permissions, processus, temps, terminal.
#
# La logique de chemins est testée DEUX fois : avec la sémantique de la
# plateforme courante, et avec la sémantique Windows forcée (les fonctions
# internes _normalize/_basename/... prennent le drapeau `win` en paramètre),
# de sorte que la logique Windows est vérifiée même sous Linux/macOS.
#
# Les tests de processus utilisent des outils POSIX (sh, echo, cat, sleep) et
# sont ignorés sous Windows. Si l'utilisateur est root (uid 0), les tests de
# refus d'accès sont ignorés (root passe outre les permissions).
#
# Lancer DEPUIS LA RACINE DU PROJET (stdlib/ et ./alex sont résolus
# relativement au dossier courant) :
#     ./alex run tests/test_os.al
#
# Code de sortie : 0 si tout passe, 1 sinon (utilisable en CI).
# =============================================================================
use os
use io
use string
use core
use collections

START := os.cwd()

stats := [0, 0, 0]
notes := []
failed_groups := []

func ok():
    stats[0] = stats[0] + 1

func fail(label, detail):
    stats[1] = stats[1] + 1
    __list_append(notes, f"{label} : {detail}")

func check(cond, label):
    if cond:
        ok()
    else:
        fail(label, "condition fausse")

func check_eq(actual, expected, label):
    if actual == expected:
        ok()
    else:
        fail(label, f"obtenu {actual}, attendu {expected}")

func skip(label):
    stats[2] = stats[2] + 1

# Type de l'exception levée par f(...), ou "" si rien n'est levé.
func err1(f, a):
    try:
        f(a)
    catch e:
        return e.type
    return ""

func err2(f, a, b):
    try:
        f(a, b)
    catch e:
        return e.type
    return ""

func err3(f, a, b, c):
    try:
        f(a, b, c)
    catch e:
        return e.type
    return ""

func check_err1(f, a, expected, label):
    check_eq(err1(f, a), expected, label)

func check_err2(f, a, b, expected, label):
    check_eq(err2(f, a, b), expected, label)

func check_err3(f, a, b, c, expected, label):
    check_eq(err3(f, a, b, c), expected, label)

IS_WIN := os.platform() == "windows"
IS_ROOT := os.user_id() == 0
T := os.join(os.tmp_dir(), f"alex_os_test_{os.pid()}")

func p(name):
    return os.join(T, name)

func read(path):
    return io.read_file(path)

func write(path, content):
    io.write_file(path, content)

# ---------------------------------------------------------------------
func t_system():
    check(core.is_str(os.name()) and os.name() != "", "name")
    check(os.platform() == "linux" or os.platform() == "macos" or os.platform() == "windows" or os.platform() == "unknown", "platform")
    check(os.platform() != "unknown", "platform connue")
    a := os.arch()
    check(core.is_str(a) and a != "", "arch")
    check(a != "amd64" and a != "aarch64" and a != "i686", "arch normalisée")
    check(core.is_str(os.version()) and os.version() != "", "version")
    check(core.is_str(os.hostname()) and os.hostname() != "", "hostname")
    u := os.username()
    check(u == null or core.is_str(u), "username")
    if IS_WIN:
        check_eq(os.user_id(), null, "user_id Windows")
        check_eq(os.group_id(), null, "group_id Windows")
    else:
        check(core.is_int(os.user_id()) and os.user_id() >= 0, "user_id")
        check(core.is_int(os.group_id()) and os.group_id() >= 0, "group_id")
    h := os.home()
    check(h == null or os.isdir(h), "home")
    check(os.isdir(os.tmp_dir()), "tmp_dir")
    check(os.isdir(os.cwd()), "cwd")
    check(os.is_absolute(os.cwd()), "cwd absolu")
    check(core.is_int(os.cpu_count()) and os.cpu_count() >= 1, "cpu_count")
    info := os.system_info()
    check(core.is_dict(info), "system_info dict")
    check_eq(info["platform"], os.platform(), "system_info.platform")
    check_eq(info["name"], os.name(), "system_info.name")
    check_eq(info["arch"], os.arch(), "system_info.arch")
    check_eq(info["cpu_count"], os.cpu_count(), "system_info.cpu_count")
    check_eq(info["pid"], os.pid(), "system_info.pid")
    check_eq(info["cwd"], os.cwd(), "system_info.cwd")
    if IS_WIN:
        check_eq(info["path_separator"], "\\", "system_info.path_separator Windows")
    else:
        check_eq(info["path_separator"], "/", "system_info.path_separator")
    tm := info["total_memory"]
    check(tm == null or tm > 0, "system_info.total_memory")

func t_chdir():
    start := os.cwd()
    os.mkdir_all(p("cd/sub"))
    os.chdir(p("cd/sub"))
    check_eq(os.cwd(), os.realpath(p("cd/sub")), "chdir -> cwd")
    os.chdir("..")
    check_eq(os.cwd(), os.realpath(p("cd")), "chdir ..")
    os.chdir(start)
    check_eq(os.cwd(), start, "chdir retour")
    check_err1(os.chdir, p("absent_zz"), "IoError", "chdir absent")
    check_err1(os.chdir, 5, "TypeError", "chdir type")
    check_eq(os.chdir(start), null, "chdir -> null")

# ---------------------------------------------------------------------
func t_args():
    av := os.argv()
    check(core.is_list(av), "argv list")
    check(core.len(av) >= 1, "argv contient au moins le script")
    check(string.ends_with(av[0], "test_os.al"), "argv[0] = script")
    check_eq(os.argc(), core.len(av), "argc == len(argv)")
    ar := os.args()
    check_eq(core.len(ar), core.len(av) - 1, "args = argv sans le script")
    # Bout en bout : un vrai sous-processus ALEX reçoit ses arguments.
    if not IS_WIN:
        write(p("echo_args.al"), "use os\nprint(os.argc())\nprint(os.args())\nprint(os.argv()[0])\n")
        r := os.run(os.absolute("alex"), ["run", p("echo_args.al"), "un", "deux mots", "3"])
        check_eq(r["code"], 0, "alex run : code")
        lines := string.split(r["stdout"], "\n")
        check_eq(lines[0], "4", "alex run : argc")
        check_eq(lines[1], "[un, deux mots, 3]", "alex run : args")
        check_eq(lines[2], p("echo_args.al"), "alex run : argv[0]")

# ---------------------------------------------------------------------
func t_env():
    K := "ALEX_OS_TEST_VAR"
    os.unsetenv(K)
    check(not os.hasenv(K), "hasenv absente")
    check_eq(os.getenv(K), null, "getenv absente -> null")
    check_eq(os.getenv(K, "def"), "def", "getenv fallback")
    check_eq(os.setenv(K, "valeur"), null, "setenv -> null")
    check(os.hasenv(K), "hasenv présente")
    check_eq(os.getenv(K), "valeur", "getenv")
    check_eq(os.getenv(K, "def"), "valeur", "getenv ignore le fallback")
    os.setenv(K, "")
    check(os.hasenv(K), "hasenv vide = présente")
    check_eq(os.getenv(K), "", "getenv chaîne vide")
    check_eq(os.getenv(K, "def"), "", "getenv vide ignore le fallback")
    os.setenv(K, "é世界")
    check_eq(os.getenv(K), "é世界", "env UTF-8")
    os.setenv(K, "a=b")
    check_eq(os.getenv(K), "a=b", "valeur contenant =")
    e := os.env()
    check(core.is_dict(e), "env dict")
    check_eq(e[K], "a=b", "env contient la variable")
    check_eq(os.unsetenv(K), null, "unsetenv -> null")
    check(not os.hasenv(K), "unsetenv supprime")
    check_eq(os.unsetenv(K), null, "unsetenv idempotent")
    e2 := os.env()
    check(not collections.contains_key(e2, K), "env sans la variable supprimée")
    check_err2(os.setenv, "", "x", "IoError", "setenv nom vide")
    check_err2(os.setenv, "A=B", "x", "IoError", "setenv nom avec =")
    check_err2(os.setenv, K, 5, "TypeError", "setenv valeur non str")
    check_err1(os.getenv, 5, "TypeError", "getenv type")
    check_err1(os.hasenv, null, "TypeError", "hasenv type")
    # héritage par les sous-processus
    if not IS_WIN:
        os.setenv(K, "herite")
        r := os.run("sh", ["-c", "printf %s \"$ALEX_OS_TEST_VAR\""])
        check_eq(r["stdout"], "herite", "env hérité par le fils")
        os.unsetenv(K)
    # legacy
    os.setenv(K, "L")
    check_eq(os.get_env(K), "L", "legacy get_env")
    check_eq(os.get_env("ALEX_OS_ABSENT_ZZ", "d"), "d", "legacy get_env défaut")
    check_eq(os.set_env(K, "M"), null, "legacy set_env")
    check_eq(os.getenv(K), "M", "legacy set_env effet")
    os.unsetenv(K)

# ---------------------------------------------------------------------
# Chemins : sémantique POSIX forcée (win = false)
func t_path_posix():
    check_eq(os._normalize("/a/b/../c", false), "/a/c", "normalize ..")
    check_eq(os._normalize("a//b/./c/", false), "a/b/c", "normalize // . /")
    check_eq(os._normalize("..", false), "..", "normalize ..seul")
    check_eq(os._normalize("a/../..", false), "..", "normalize remonte")
    check_eq(os._normalize("/..", false), "/", "normalize /..")
    check_eq(os._normalize("", false), ".", "normalize vide")
    check_eq(os._normalize(".", false), ".", "normalize .")
    check_eq(os._normalize("a/..", false), ".", "normalize s'annule")
    check_eq(os._normalize("//a", false), "/a", "normalize //a")
    check_eq(os._normalize("../a", false), "../a", "normalize ../a")
    check_eq(os._normalize("/a/b/../../..", false), "/", "normalize au-dessus de la racine")
    check_eq(os._normalize("./a", false), "a", "normalize ./a")
    check_eq(os._normalize("a/b/../../c", false), "c", "normalize double ..")
    check_eq(os._normalize("é/世界/../x", false), "é/x", "normalize UTF-8")

    check_eq(os._basename("/a/b.txt", false), "b.txt", "basename simple")
    check_eq(os._basename("a/b/", false), "b", "basename séparateur final")
    check_eq(os._basename("/", false), "", "basename racine")
    check_eq(os._basename("", false), "", "basename vide")
    check_eq(os._basename("a", false), "a", "basename sans séparateur")
    check_eq(os._basename("a//b//", false), "b", "basename doubles séparateurs")
    check_eq(os._basename("/a/世界.txt", false), "世界.txt", "basename UTF-8")

    check_eq(os._dirname("/a/b", false), "/a", "dirname simple")
    check_eq(os._dirname("a/b/", false), "a", "dirname séparateur final")
    check_eq(os._dirname("/a", false), "/", "dirname /a")
    check_eq(os._dirname("/", false), "/", "dirname racine")
    check_eq(os._dirname("a", false), "", "dirname relatif nu")
    check_eq(os._dirname("", false), "", "dirname vide")
    check_eq(os._dirname("a//b", false), "a", "dirname doubles séparateurs")
    check_eq(os._dirname("/a/b/c/", false), "/a/b", "dirname profond")

    check_eq(os._join_list(["a", "b"], false), "a/b", "join 2")
    check_eq(os._join_list(["a/", "b"], false), "a/b", "join séparateur existant")
    check_eq(os._join_list(["a", "/b"], false), "/b", "join absolu remplace")
    check_eq(os._join_list(["", "b"], false), "b", "join premier vide")
    check_eq(os._join_list(["a", ""], false), "a", "join dernier vide")
    check_eq(os._join_list(["/", "a"], false), "/a", "join racine")
    check_eq(os._join_list(["a", "b", "c"], false), "a/b/c", "join 3")

    check(os._is_absolute("/a", false), "is_absolute /a")
    check(os._is_absolute("//a", false), "is_absolute //a")
    check(not os._is_absolute("a", false), "is_absolute a")
    check(not os._is_absolute("", false), "is_absolute vide")
    check(not os._is_absolute("C:\\x", false), "is_absolute C:\\ n'est pas absolu en POSIX")

# Chemins : sémantique Windows forcée (win = true)
func t_path_windows():
    check_eq(os._normalize("C:/a/b/../c", true), "C:\\a\\c", "win normalize /")
    check_eq(os._normalize("C:\\a\\.\\b\\", true), "C:\\a\\b", "win normalize . et final")
    check_eq(os._normalize("C:\\..", true), "C:\\", "win normalize au-dessus de la racine")
    check_eq(os._normalize("C:a\\..\\..", true), "C:..", "win normalize relatif au lecteur")
    check_eq(os._normalize("\\\\srv\\share\\a\\..\\b", true), "\\\\srv\\share\\b", "win normalize UNC")
    check_eq(os._normalize("a/b", true), "a\\b", "win normalize convertit /")
    check_eq(os._normalize("\\a", true), "\\a", "win normalize rooted")
    check_eq(os._normalize("C:\\", true), "C:\\", "win normalize racine")
    check_eq(os._normalize("", true), ".", "win normalize vide")
    check_eq(os._normalize("a\\..", true), ".", "win normalize s'annule")

    check_eq(os._split_root("\\\\srv\\share\\x", true), ["\\\\srv\\share\\", "x"], "win split_root UNC")
    check_eq(os._split_root("C:\\x\\y", true), ["C:\\", "x\\y"], "win split_root lecteur")
    check_eq(os._split_root("C:x", true), ["C:", "x"], "win split_root lecteur relatif")
    check_eq(os._split_root("\\x", true), ["\\", "x"], "win split_root rooted")
    check_eq(os._split_root("x\\y", true), ["", "x\\y"], "win split_root relatif")

    check_eq(os._basename("C:\\a\\b.txt", true), "b.txt", "win basename")
    check_eq(os._basename("C:\\", true), "", "win basename racine")
    check_eq(os._basename("C:b", true), "b", "win basename lecteur relatif")
    check_eq(os._basename("\\\\srv\\share\\", true), "", "win basename UNC racine")
    check_eq(os._basename("a/b\\c", true), "c", "win basename séparateurs mixtes")
    check_eq(os._basename("C:\\a\\b\\", true), "b", "win basename séparateur final")

    check_eq(os._dirname("C:\\a\\b", true), "C:\\a", "win dirname")
    check_eq(os._dirname("C:\\a", true), "C:\\", "win dirname sous la racine")
    check_eq(os._dirname("C:\\", true), "C:\\", "win dirname racine")
    check_eq(os._dirname("a\\b", true), "a", "win dirname relatif")
    check_eq(os._dirname("C:a", true), "C:", "win dirname lecteur relatif")
    check_eq(os._dirname("\\\\srv\\share\\x\\y", true), "\\\\srv\\share\\x", "win dirname UNC")

    check(os._is_absolute("C:\\x", true), "win is_absolute C:\\")
    check(os._is_absolute("C:/x", true), "win is_absolute C:/")
    check(not os._is_absolute("C:x", true), "win is_absolute C:x")
    check(not os._is_absolute("c:", true), "win is_absolute c:")
    check(os._is_absolute("\\x", true), "win is_absolute rooted")
    check(os._is_absolute("\\\\srv\\share", true), "win is_absolute UNC")
    check(not os._is_absolute("x", true), "win is_absolute relatif")

    check_eq(os._join_list(["C:\\a", "b"], true), "C:\\a\\b", "win join")
    check_eq(os._join_list(["C:", "b"], true), "C:b", "win join lecteur nu")
    check_eq(os._join_list(["a", "C:\\b"], true), "C:\\b", "win join absolu remplace")
    check_eq(os._join_list(["a\\", "b"], true), "a\\b", "win join séparateur existant")
    check_eq(os._join_list(["a", "b"], true), "a\\b", "win join relatif")
    check_eq(os._join_list(["a", "D:b"], true), "D:b", "win join lecteur relatif remplace")

# Fonctions publiques (plateforme courante)
func t_path_public():
    check_eq(os.join("a", "b"), os._join_list(["a", "b"], IS_WIN), "join 2 segments")
    check_eq(os.join(["a", "b", "c"]), os._join_list(["a", "b", "c"], IS_WIN), "join liste")
    check_eq(os.join("a", "b", "c", "d", "e"), os._join_list(["a", "b", "c", "d", "e"], IS_WIN), "join 5 segments")
    check_eq(os.join("a", "b", "c", "d", "e", "f", "g", "h"), os._join_list(["a", "b", "c", "d", "e", "f", "g", "h"], IS_WIN), "join 8 segments")
    check_eq(os.join("a", null, "b"), os.join("a", "b"), "join ignore null")
    check_eq(os.join("a", "../b"), os.join("a", "..") + os._sep(IS_WIN) + "b", "join ne normalise pas")
    check_err1(os.join, 5, "TypeError", "join type")
    check_err2(os.join, "a", 5, "TypeError", "join segment type")
    if not IS_WIN:
        check_eq(os.join("a", "b"), "a/b", "join POSIX")
        check_eq(os.basename("/x/y.txt"), "y.txt", "basename public")
        check_eq(os.dirname("/x/y.txt"), "/x", "dirname public")
        check_eq(os.normalize("/x/./y/../z"), "/x/z", "normalize public")
        check(os.is_absolute("/x"), "is_absolute public")
        check(not os.is_absolute("x"), "is_absolute public relatif")
    # extension / stem (indépendants de la plateforme pour ces entrées)
    check_eq(os.extension("a/b.tar.gz"), ".gz", "extension .gz")
    check_eq(os.extension("x"), "", "extension aucune")
    check_eq(os.extension(".bashrc"), "", "extension fichier caché")
    check_eq(os.extension("a.b/c"), "", "extension point dans le dossier")
    check_eq(os.extension("a."), ".", "extension point final")
    check_eq(os.extension(".."), "", "extension ..")
    check_eq(os.extension("file.TXT"), ".TXT", "extension casse conservée")
    check_eq(os.extension(".a.b"), ".b", "extension fichier caché + ext")
    check_eq(os.extension("..a"), "", "extension points initiaux")
    check_eq(os.extension("世界.日本"), ".日本", "extension UTF-8")
    check_eq(os.stem("a/b.tar.gz"), "b.tar", "stem")
    check_eq(os.stem(".bashrc"), ".bashrc", "stem fichier caché")
    check_eq(os.stem("x"), "x", "stem sans extension")
    check_eq(os.stem("a/b/"), "b", "stem séparateur final")
    check_eq(os.stem("a."), "a", "stem point final")
    check_err1(os.basename, 5, "TypeError", "basename type")
    check_err1(os.dirname, null, "TypeError", "dirname type")
    check_err1(os.extension, 5, "TypeError", "extension type")
    check_err1(os.stem, 5, "TypeError", "stem type")
    check_err1(os.normalize, 5, "TypeError", "normalize type")
    check_err1(os.absolute, 5, "TypeError", "absolute type")
    check_err1(os.realpath, 5, "TypeError", "realpath type")
    check_err1(os.is_absolute, 5, "TypeError", "is_absolute type")
    # absolute / realpath
    a := os.absolute("x/../y")
    check(os.is_absolute(a), "absolute est absolu")
    check_eq(a, os.join(os.cwd(), "y"), "absolute résout par rapport au cwd")
    check_eq(os.absolute(os.cwd()), os.cwd(), "absolute idempotent")
    check_eq(os.absolute(""), os.cwd(), "absolute vide = cwd")
    check_eq(os.realpath("."), os.cwd(), "realpath .")
    check_eq(os.realpath(""), os.cwd(), "realpath vide")
    if not IS_WIN:
        check_eq(os.realpath(p("n_existe_pas/x")), os.join(os.realpath(T), "n_existe_pas/x"), "realpath tolère un chemin inexistant")

# ---------------------------------------------------------------------
func t_fs_basic():
    d := p("fs")
    check_eq(os.mkdir(d), null, "mkdir -> null")
    check(os.exists(d) and os.isdir(d) and not os.isfile(d), "mkdir crée un dossier")
    check_err1(os.mkdir, d, "IoError", "mkdir existant")
    check_err1(os.mkdir, p("fs/a/b"), "IoError", "mkdir sans parent")
    f := p("fs/f.txt")
    write(f, "hello")
    check(os.exists(f) and os.isfile(f) and not os.isdir(f), "fichier : exists/isfile/isdir")
    check(not os.islink(f), "fichier n'est pas un lien")
    check_eq(os.size(f), 5, "size")
    write(f, "héllo")
    check_eq(os.size(f), 6, "size en octets UTF-8")
    write(p("fs/vide"), "")
    check_eq(os.size(p("fs/vide")), 0, "size fichier vide")
    os.remove(p("fs/vide"))
    check_err1(os.size, d, "IoError", "size dossier")
    check_err1(os.size, p("fs/absent"), "IoError", "size absent")
    check(not os.exists(p("fs/absent")), "exists absent")
    check(not os.isfile(p("fs/absent")), "isfile absent")
    check(not os.isdir(p("fs/absent")), "isdir absent")
    check(not os.islink(p("fs/absent")), "islink absent")
    check(not os.isfile(d), "isfile dossier")
    check_err1(os.exists, 5, "TypeError", "exists type")
    check_err1(os.isfile, null, "TypeError", "isfile type")
    check_err1(os.isdir, 5, "TypeError", "isdir type")
    check_err1(os.islink, 5, "TypeError", "islink type")
    # horodatages
    now := os.time()
    mt := os.mtime(f)
    check(core.is_float(mt), "mtime float")
    check(mt > now - 60.0 and mt < now + 60.0, "mtime récent")
    check(core.is_float(os.atime(f)), "atime float")
    check(core.is_float(os.ctime(f)), "ctime float")
    check(os.ctime(f) > now - 60.0 and os.ctime(f) < now + 60.0, "ctime récent")
    check_err1(os.mtime, p("fs/absent"), "IoError", "mtime absent")
    check_err1(os.atime, p("fs/absent"), "IoError", "atime absent")
    check_err1(os.ctime, p("fs/absent"), "IoError", "ctime absent")
    # list_dir trié
    write(p("fs/b.txt"), "b")
    write(p("fs/a.txt"), "a")
    os.mkdir(p("fs/c_dir"))
    check_eq(os.list_dir(d), ["a.txt", "b.txt", "c_dir", "f.txt"], "list_dir trié")
    check_eq(os.list_dir(p("fs/c_dir")), [], "list_dir vide")
    check_err1(os.list_dir, f, "IoError", "list_dir sur un fichier")
    check_err1(os.list_dir, p("fs/absent"), "IoError", "list_dir absent")
    # remove
    check_eq(os.remove(p("fs/b.txt")), null, "remove -> null")
    check(not os.exists(p("fs/b.txt")), "remove supprime")
    check_err1(os.remove, p("fs/b.txt"), "IoError", "remove absent")
    check_err1(os.remove, p("fs/c_dir"), "IoError", "remove refuse un dossier")
    check(os.isdir(p("fs/c_dir")), "remove n'a pas touché le dossier")
    # rmdir
    check_eq(os.rmdir(p("fs/c_dir")), null, "rmdir -> null")
    check(not os.exists(p("fs/c_dir")), "rmdir supprime")
    check_err1(os.rmdir, p("fs/c_dir"), "IoError", "rmdir absent")
    check_err1(os.rmdir, f, "IoError", "rmdir refuse un fichier")
    check_err1(os.rmdir, d, "IoError", "rmdir refuse un dossier non vide")
    check(os.exists(f), "rmdir non vide n'a rien supprimé")

func t_mkdir_all():
    d := p("deep/a/b/c")
    check_eq(os.mkdir_all(d), null, "mkdir_all -> null")
    check(os.isdir(d), "mkdir_all crée toute la chaîne")
    check_eq(os.mkdir_all(d), null, "mkdir_all idempotent")
    check_eq(os.mkdir_all(p("deep/a/b/c/")), null, "mkdir_all séparateur final")
    check_eq(os.mkdir_all(p("deep/x/../y/z")), null, "mkdir_all avec ..")
    check(os.isdir(p("deep/y/z")), "mkdir_all avec .. : résultat")
    write(p("deep/file"), "x")
    check_err1(os.mkdir_all, p("deep/file"), "IoError", "mkdir_all sur un fichier")
    check_err1(os.mkdir_all, p("deep/file/sub"), "IoError", "mkdir_all sous un fichier")
    check_err1(os.mkdir_all, 5, "TypeError", "mkdir_all type")

func t_rmdir_recursive():
    r := p("rm")
    os.mkdir_all(p("rm/a/b"))
    write(p("rm/a/b/f1"), "1")
    write(p("rm/a/f2"), "2")
    write(p("rm/f3"), "3")
    check_err1(os.rmdir, r, "IoError", "rmdir non récursif sur dossier non vide")
    check_eq(os.rmdir(r, true), null, "rmdir récursif -> null")
    check(not os.exists(r), "rmdir récursif supprime tout")
    check_err1(os.rmdir, r, "IoError", "rmdir récursif absent")
    os.mkdir(p("rm_vide"))
    check_eq(os.rmdir(p("rm_vide"), false), null, "rmdir recursive=false sur dossier vide")
    check(not os.exists(p("rm_vide")), "rmdir recursive=false supprime")
    os.mkdir(p("rm_vide2"))
    check_eq(os.rmdir(p("rm_vide2"), true), null, "rmdir récursif sur dossier vide")

func t_symlinks():
    if IS_WIN:
        skip("liens symboliques")
        return null
    os.mkdir_all(p("ln/real_dir"))
    write(p("ln/target.txt"), "data")
    write(p("ln/real_dir/inside"), "in")
    check_eq(os.run("ln", ["-s", "target.txt", p("ln/link_f")])["code"], 0, "création lien fichier")
    check_eq(os.run("ln", ["-s", "real_dir", p("ln/link_d")])["code"], 0, "création lien dossier")
    check_eq(os.run("ln", ["-s", "n_existe_pas", p("ln/broken")])["code"], 0, "création lien cassé")
    check(os.islink(p("ln/link_f")), "islink fichier")
    check(os.islink(p("ln/link_d")), "islink dossier")
    check(os.islink(p("ln/broken")), "islink cassé")
    check(not os.islink(p("ln/target.txt")), "islink sur un fichier normal")
    check(os.isfile(p("ln/link_f")), "isfile suit le lien")
    check(os.isdir(p("ln/link_d")), "isdir suit le lien")
    check(not os.exists(p("ln/broken")), "exists : lien cassé = faux")
    check_eq(os.realpath(p("ln/link_f")), os.realpath(p("ln/target.txt")), "realpath résout le lien")
    check_eq(os.size(p("ln/link_f")), 4, "size suit le lien")
    # remove supprime le LIEN, pas la cible
    os.remove(p("ln/link_f"))
    check(not os.islink(p("ln/link_f")) and os.exists(p("ln/target.txt")), "remove d'un lien épargne la cible")
    os.remove(p("ln/broken"))
    check(not os.islink(p("ln/broken")), "remove d'un lien cassé")
    # rmdir (même récursif) ne suit pas un lien vers un dossier
    check_err1(os.rmdir, p("ln/link_d"), "IoError", "rmdir sur lien dossier")
    check_err2(os.rmdir, p("ln/link_d"), true, "IoError", "rmdir récursif sur lien dossier")
    check(os.exists(p("ln/real_dir/inside")), "rmdir récursif sur lien n'a pas touché la cible")
    # rmdir récursif sur un dossier CONTENANT un lien : le lien est supprimé, pas sa cible
    os.mkdir_all(p("ln/tree"))
    os.run("ln", ["-s", p("ln/real_dir"), p("ln/tree/to_real")])
    os.rmdir(p("ln/tree"), true)
    check(not os.exists(p("ln/tree")), "rmdir récursif avec lien")
    check(os.exists(p("ln/real_dir/inside")), "rmdir récursif : contenu pointé intact")

# ---------------------------------------------------------------------
func t_copy():
    os.mkdir_all(p("cp/src/sub"))
    write(p("cp/src/a.txt"), "A")
    write(p("cp/src/sub/b.txt"), "B")
    write(p("cp/file.txt"), "F")
    # fichier -> nouveau nom
    check_eq(os.copy(p("cp/file.txt"), p("cp/copy.txt")), p("cp/copy.txt"), "copy retourne la destination")
    check_eq(read(p("cp/copy.txt")), "F", "copy fichier")
    check_eq(read(p("cp/file.txt")), "F", "copy conserve la source")
    # écrase
    write(p("cp/copy.txt"), "ancien")
    os.copy(p("cp/file.txt"), p("cp/copy.txt"))
    check_eq(read(p("cp/copy.txt")), "F", "copy écrase")
    # fichier -> dans un dossier existant
    os.mkdir(p("cp/dest"))
    check_eq(os.copy(p("cp/file.txt"), p("cp/dest")), p("cp/dest/file.txt"), "copy dans un dossier : chemin")
    check_eq(read(p("cp/dest/file.txt")), "F", "copy dans un dossier")
    # dossier -> nouveau dossier (récursif)
    check_eq(os.copy(p("cp/src"), p("cp/src2")), p("cp/src2"), "copy dossier : chemin")
    check_eq(read(p("cp/src2/a.txt")), "A", "copy dossier : fichier")
    check_eq(read(p("cp/src2/sub/b.txt")), "B", "copy dossier : sous-dossier")
    check_eq(os.list_dir(p("cp/src2")), ["a.txt", "sub"], "copy dossier : contenu")
    # dossier -> DANS un dossier existant
    os.mkdir(p("cp/into"))
    check_eq(os.copy(p("cp/src"), p("cp/into")), p("cp/into/src"), "copy dossier dans dossier : chemin")
    check_eq(read(p("cp/into/src/sub/b.txt")), "B", "copy dossier dans dossier")
    # fusion : écrase les fichiers existants
    write(p("cp/src2/a.txt"), "ancien")
    os.copy(p("cp/src"), p("cp/src2"))
    check(os.isdir(p("cp/src2/src")), "copy sur dossier existant copie DANS celui-ci")
    # erreurs
    check_err2(os.copy, p("cp/absent"), p("cp/x"), "IoError", "copy source absente")
    check_err2(os.copy, p("cp/src"), p("cp/src/sub/dans_lui_meme"), "IoError", "copy dossier dans lui-même")
    check_err2(os.copy, p("cp/src"), p("cp/src"), "IoError", "copy dossier sur lui-même")
    check_err2(os.copy, p("cp/file.txt"), p("cp/file.txt"), "IoError", "copy fichier sur lui-même")
    check_err2(os.copy, 5, "x", "TypeError", "copy type source")
    check_err2(os.copy, "x", 5, "TypeError", "copy type destination")
    # liens symboliques recréés tels quels
    if not IS_WIN:
        os.mkdir(p("cp/withlink"))
        write(p("cp/withlink/real"), "R")
        os.run("ln", ["-s", "real", p("cp/withlink/lnk")])
        os.copy(p("cp/withlink"), p("cp/withlink2"))
        check(os.islink(p("cp/withlink2/lnk")), "copy conserve les liens symboliques")
        check_eq(read(p("cp/withlink2/lnk")), "R", "copy : lien fonctionnel")
        # recopier à l'intérieur d'une copie existante ne casse rien
        os.copy(p("cp/withlink"), p("cp/withlink2"))
        check(os.islink(p("cp/withlink2/withlink/lnk")), "copy dans une copie existante : lien conservé")

func t_move():
    os.mkdir_all(p("mv/d/sub"))
    write(p("mv/f.txt"), "F")
    write(p("mv/d/sub/x"), "X")
    # renommage
    check_eq(os.move(p("mv/f.txt"), p("mv/g.txt")), p("mv/g.txt"), "move retourne la destination")
    check(not os.exists(p("mv/f.txt")) and os.exists(p("mv/g.txt")), "move renomme")
    check_eq(read(p("mv/g.txt")), "F", "move conserve le contenu")
    # dans un dossier existant
    os.mkdir(p("mv/target"))
    check_eq(os.move(p("mv/g.txt"), p("mv/target")), p("mv/target/g.txt"), "move dans un dossier : chemin")
    check(os.exists(p("mv/target/g.txt")) and not os.exists(p("mv/g.txt")), "move dans un dossier")
    # dossier
    check_eq(os.move(p("mv/d"), p("mv/d2")), p("mv/d2"), "move dossier")
    check_eq(read(p("mv/d2/sub/x")), "X", "move dossier : contenu")
    check(not os.exists(p("mv/d")), "move dossier : source disparue")
    # dossier dans dossier
    os.mkdir(p("mv/box"))
    os.move(p("mv/d2"), p("mv/box"))
    check_eq(read(p("mv/box/d2/sub/x")), "X", "move dossier dans dossier")
    # écrase un fichier existant
    write(p("mv/one"), "1")
    write(p("mv/two"), "2")
    os.move(p("mv/one"), p("mv/two"))
    check_eq(read(p("mv/two")), "1", "move écrase un fichier")
    # erreurs
    check_err2(os.move, p("mv/absent"), p("mv/y"), "IoError", "move source absente")
    check_err2(os.move, 5, "x", "TypeError", "move type source")
    check_err2(os.move, "x", 5, "TypeError", "move type destination")
    check_err2(os.move, p("mv/box"), p("mv/box/inside"), "IoError", "move dossier dans lui-même")
    check(os.isdir(p("mv/box")), "move refusé : source intacte")

# ---------------------------------------------------------------------
func t_permissions():
    if IS_WIN:
        f := p("perm_win.txt")
        write(f, "x")
        check(core.is_int(os.permissions(f)), "permissions int (Windows)")
        os.chmod(f, 292)
        check(not os.access(f, "w"), "chmod lecture seule (Windows)")
        os.chmod(f, 438)
        check(os.access(f, "w"), "chmod écriture (Windows)")
        return null
    f := p("perm.txt")
    write(f, "x")
    check_eq(os.chmod(f, 420), null, "chmod -> null")
    check_eq(os.permissions(f), 420, "permissions == 0o644 (420)")
    os.chmod(f, "600")
    check_eq(os.permissions(f), 384, "chmod chaîne octale 600")
    os.chmod(f, "0755")
    check_eq(os.permissions(f), 493, "chmod chaîne octale 0755")
    os.chmod(f, "0o640")
    check_eq(os.permissions(f), 416, "chmod chaîne octale 0o640")
    os.chmod(f, 0)
    check_eq(os.permissions(f), 0, "chmod 0")
    os.chmod(f, 420)
    # access : existence, lecture, écriture, exécution
    check(os.access(f), "access existence")
    check(os.access(f, null), "access null")
    check(not os.access(p("absent_zz")), "access absent")
    check(os.access(f, "r"), "access r")
    check(os.access(f, "w"), "access w")
    check(os.access(f, "rw"), "access rw")
    check(not os.access(f, "x"), "access x sans bit x")
    check(not os.access(f, "rwx"), "access rwx sans bit x")
    check(os.access(f, 4), "access entier 4")
    check(os.access(f, 6), "access entier 6")
    check(not os.access(f, 1), "access entier 1")
    os.chmod(f, 493)
    check(os.access(f, "x"), "access x avec bit x")
    check(os.access(f, "rwx"), "access rwx")
    if not IS_ROOT:
        os.chmod(f, 0)
        check(not os.access(f, "r"), "access r refusé")
        check(not os.access(f, "w"), "access w refusé")
        check_err1(io.read_file, f, "IoError", "lecture refusée par l'OS (aucune sandbox, erreur OS)")
        os.chmod(f, 420)
        check_eq(read(f), "x", "lecture à nouveau permise")
    else:
        skip("refus d'accès (root)")
    # dossier
    check(os.access(T, "rwx"), "access dossier temporaire")
    # erreurs
    check_err1(os.permissions, p("absent_zz"), "IoError", "permissions absent")
    check_err2(os.chmod, p("absent_zz"), 420, "IoError", "chmod absent")
    check_err2(os.chmod, f, 4096, "ArgumentError", "chmod mode trop grand")
    check_err2(os.chmod, f, -1, "ArgumentError", "chmod mode négatif")
    check_err2(os.chmod, f, "89", "ArgumentError", "chmod octal invalide")
    check_err2(os.chmod, f, "", "ArgumentError", "chmod octal vide")
    check_err2(os.chmod, f, 1.5, "TypeError", "chmod type")
    check_err2(os.access, f, "z", "ArgumentError", "access lettre invalide")
    check_err2(os.access, f, 8, "ArgumentError", "access entier hors limites")
    check_err2(os.access, f, 1.5, "TypeError", "access type")
    check_err1(os.permissions, 5, "TypeError", "permissions type")

# ---------------------------------------------------------------------
func t_process_info():
    check(core.is_int(os.pid()) and os.pid() > 0, "pid")
    check(core.is_int(os.parent_pid()) and os.parent_pid() > 0, "parent_pid")
    check_eq(os.pid(), os.pid(), "pid stable")
    check(os.process_exists(os.pid()), "process_exists : soi-même")
    check(not os.process_exists(2147483646), "process_exists : pid improbable")
    check(not os.process_exists(0), "process_exists 0")
    check(not os.process_exists(-1), "process_exists négatif")
    check_err1(os.process_exists, "1", "TypeError", "process_exists type")

func t_run():
    if IS_WIN:
        skip("run (outils POSIX)")
        return null
    r := os.run("echo", ["a", "b"])
    check_eq(r["code"], 0, "run : code 0")
    check_eq(r["stdout"], "a b\n", "run : stdout")
    check_eq(r["stderr"], "", "run : stderr vide")
    r2 := os.run("sh", ["-c", "echo out; echo err 1>&2; exit 3"])
    check_eq(r2["code"], 3, "run : code non nul")
    check_eq(r2["stdout"], "out\n", "run : stdout séparé")
    check_eq(r2["stderr"], "err\n", "run : stderr séparé")
    r3 := os.run("cat", [], "entrée\nUTF-8 é")
    check_eq(r3["stdout"], "entrée\nUTF-8 é", "run : input -> stdout")
    check_eq(r3["code"], 0, "run : input code")
    r4 := os.run("true")
    check_eq(r4["code"], 0, "run sans args")
    check_eq(os.run("false")["code"], 1, "run false")
    check_eq(os.run("cat", null, "")["stdout"], "", "run input vide")
    # arguments passés tels quels (pas de shell)
    r5 := os.run("printf", ["%s|", "a b", "$HOME", "*", "x;y"])
    check_eq(r5["stdout"], "a b|$HOME|*|x;y|", "run : aucun shell, arguments intacts")
    # signal : tué
    r6 := os.run("sh", ["-c", "kill -9 $$"])
    check_eq(r6["code"], -9, "run : tué par signal -> -9")
    # gros volumes dans les deux sens (pas d'interblocage)
    big := string.repeat("x", 300000)
    r7 := os.run("cat", [], big)
    check_eq(core.len(r7["stdout"]), 300000, "run : 300 Ko aller-retour sans interblocage")
    r8 := os.run("sh", ["-c", "head -c 400000 /dev/zero | tr '\\0' 'a'; head -c 400000 /dev/zero | tr '\\0' 'b' 1>&2"])
    check_eq(core.len(r8["stdout"]), 400000, "run : 400 Ko stdout")
    check_eq(core.len(r8["stderr"]), 400000, "run : 400 Ko stderr")
    # fils qui ferme son entrée sans la lire : pas de SIGPIPE fatal
    r9 := os.run("true", [], big)
    check_eq(r9["code"], 0, "run : entrée ignorée par le fils")
    # erreurs
    check_err1(os.run, "alex_programme_inexistant_zz", "IoError", "run programme introuvable")
    check_err1(os.run, "", "ArgumentError", "run programme vide")
    check_err1(os.run, 5, "TypeError", "run type programme")
    check_err2(os.run, "echo", "pasuneliste", "TypeError", "run type args")
    check_err2(os.run, "echo", [1, 2], "TypeError", "run args non str")
    check_err3(os.run, "echo", [], 5, "TypeError", "run type input")

func t_execute():
    if IS_WIN:
        check_eq(os.execute("exit 5"), 5, "execute code (Windows)")
        return null
    check_eq(os.execute("exit 5"), 5, "execute code 5")
    check_eq(os.execute("true"), 0, "execute true")
    check_eq(os.execute("false"), 1, "execute false")
    check_eq(os.execute("exit 0"), 0, "execute exit 0")
    check_eq(os.execute("test -d /"), 0, "execute test")
    check_eq(os.execute("kill -9 $$"), -9, "execute tué par signal")
    # le shell interprète : redirection, pipes, variables
    out := p("exec_out.txt")
    check_eq(os.execute("echo bonjour | tr a-z A-Z > '" + out + "'"), 0, "execute pipe + redirection")
    check_eq(read(out), "BONJOUR\n", "execute : effet")
    # ordre d'affichage : stdout du processus vidé avant le fils
    check_err1(os.execute, 5, "TypeError", "execute type")

func t_spawn_wait_kill():
    if IS_WIN:
        skip("spawn/wait/kill (outils POSIX)")
        return null
    pid := os.spawn("sh", ["-c", "exit 7"])
    check(core.is_int(pid) and pid > 0, "spawn retourne un pid")
    check_eq(os.wait(pid), 7, "wait : code de sortie")
    check(not os.process_exists(pid), "process_exists après wait")
    check_err1(os.wait, pid, "IoError", "wait deux fois")
    # timeout
    pid2 := os.spawn("sleep", ["5"])
    check(os.process_exists(pid2), "process_exists : fils vivant")
    t0 := os.monotonic_time()
    check_eq(os.wait(pid2, 0.1), null, "wait timeout -> null")
    el := os.monotonic_time() - t0
    check(el >= 0.09 and el < 2.0, f"wait timeout dure ~0.1 s (obtenu {el})")
    check_eq(os.wait(pid2, 0), null, "wait timeout 0 -> null")
    # kill par défaut : SIGTERM
    check_eq(os.kill(pid2), null, "kill -> null")
    check_eq(os.wait(pid2), -15, "wait : tué par SIGTERM -> -15")
    # kill par nom, par numéro
    pid3 := os.spawn("sleep", ["5"])
    os.kill(pid3, "KILL")
    check_eq(os.wait(pid3), -9, "kill KILL -> -9")
    pid4 := os.spawn("sleep", ["5"])
    os.kill(pid4, "SIGINT")
    check_eq(os.wait(pid4), -2, "kill SIGINT -> -2")
    pid5 := os.spawn("sleep", ["5"])
    os.kill(pid5, 0)
    check(os.process_exists(pid5), "kill signal 0 ne tue pas")
    os.kill(pid5, 9)
    os.wait(pid5)
    check_err2(os.kill, pid5, "TERM", "IoError", "kill processus déjà attendu")
    # spawn avec arguments
    pid6 := os.spawn("sh", ["-c", "exit $0", "9"])
    check_eq(os.wait(pid6, 5), 9, "spawn arguments + wait avec timeout large")
    # erreurs
    check_err1(os.spawn, "alex_programme_inexistant_zz", "IoError", "spawn introuvable")
    check_err1(os.spawn, "", "ArgumentError", "spawn vide")
    check_err1(os.spawn, 5, "TypeError", "spawn type")
    check_err1(os.wait, 0, "ArgumentError", "wait pid 0")
    check_err1(os.wait, -1, "ArgumentError", "wait pid -1 (groupe !)")
    check_err1(os.wait, "1", "TypeError", "wait type")
    check_err2(os.wait, os.pid(), "x", "TypeError", "wait timeout type")
    check_err2(os.wait, os.pid(), -1, "ArgumentError", "wait timeout négatif")
    check_err1(os.kill, 0, "ArgumentError", "kill pid 0 (groupe !)")
    check_err1(os.kill, -1, "ArgumentError", "kill pid -1 (tous les processus !)")
    check_err2(os.kill, os.pid(), "BOGUS", "ArgumentError", "kill signal inconnu")
    check_err2(os.kill, os.pid(), 65, "ArgumentError", "kill numéro hors limites")
    check_err2(os.kill, os.pid(), 1.5, "TypeError", "kill type signal")
    check_err2(os.kill, 2147483646, "TERM", "IoError", "kill processus inexistant")

# ---------------------------------------------------------------------
func t_time():
    t := os.time()
    check(core.is_float(t), "time float")
    check(t > 1700000000.0, "time après 2023")
    m1 := os.monotonic_time()
    m2 := os.monotonic_time()
    check(core.is_float(m1) and m2 >= m1, "monotonic_time croissant")
    s0 := os.monotonic_time()
    check_eq(os.sleep(0.12), null, "sleep -> null")
    el := os.monotonic_time() - s0
    check(el >= 0.11 and el < 1.5, f"sleep(0.12) dure ~0.12 s (obtenu {el})")
    s1 := os.monotonic_time()
    os.sleep(0)
    check(os.monotonic_time() - s1 < 0.5, "sleep(0) immédiat")
    s2 := os.monotonic_time()
    os.sleep(0.05)
    check(os.monotonic_time() - s2 >= 0.045, "sleep flottant")
    check_err1(os.sleep, -1, "ArgumentError", "sleep négatif")
    check_err1(os.sleep, "1", "TypeError", "sleep type")
    check_err1(os.sleep, null, "TypeError", "sleep null")
    # system_time
    st := os.system_time()
    check(core.is_dict(st), "system_time dict")
    check(st["year"] >= 2024 and st["year"] < 2200, "system_time.year")
    check(st["month"] >= 1 and st["month"] <= 12, "system_time.month")
    check(st["day"] >= 1 and st["day"] <= 31, "system_time.day")
    check(st["hour"] >= 0 and st["hour"] <= 23, "system_time.hour")
    check(st["minute"] >= 0 and st["minute"] <= 59, "system_time.minute")
    check(st["second"] >= 0 and st["second"] <= 61, "system_time.second")
    check(st["microsecond"] >= 0 and st["microsecond"] < 1000000, "system_time.microsecond")
    check(st["weekday"] >= 0 and st["weekday"] <= 6, "system_time.weekday")
    check(st["yearday"] >= 1 and st["yearday"] <= 366, "system_time.yearday")
    check(core.is_int(st["utc_offset"]) and st["utc_offset"] > -86400 and st["utc_offset"] < 86400, "system_time.utc_offset")
    check(core.is_bool(st["is_dst"]), "system_time.is_dst")
    check(core.is_str(st["timezone"]), "system_time.timezone")
    check(core.is_float(st["timestamp"]) and st["timestamp"] >= t, "system_time.timestamp")
    check(st["timestamp"] - t < 5.0, "system_time.timestamp proche de time()")

func t_terminal():
    t := os.terminal()
    check(core.is_dict(t), "terminal dict")
    check(core.is_bool(t["stdin"]) and core.is_bool(t["stdout"]) and core.is_bool(t["stderr"]), "terminal.flux bool")
    check(t["columns"] == null or (core.is_int(t["columns"]) and t["columns"] > 0), "terminal.columns")
    check(t["rows"] == null or (core.is_int(t["rows"]) and t["rows"] > 0), "terminal.rows")
    check(t["term"] == null or core.is_str(t["term"]), "terminal.term")
    check(core.is_bool(t["color"]), "terminal.color")
    if not t["stdout"]:
        check(not t["color"], "terminal.color faux hors terminal")
    # NO_COLOR et TERM=dumb désactivent la couleur
    old_term := os.getenv("TERM")
    old_nc := os.getenv("NO_COLOR")
    os.setenv("NO_COLOR", "1")
    check(not os.terminal()["color"], "terminal.color : NO_COLOR")
    os.unsetenv("NO_COLOR")
    os.setenv("TERM", "dumb")
    check(not os.terminal()["color"], "terminal.color : TERM=dumb")
    check_eq(os.terminal()["term"], "dumb", "terminal.term lit TERM")
    if old_term == null:
        os.unsetenv("TERM")
    else:
        os.setenv("TERM", old_term)
    if old_nc != null:
        os.setenv("NO_COLOR", old_nc)

# ---------------------------------------------------------------------
# Exécution
# ---------------------------------------------------------------------
func run_group(label, f):
    before := stats[1]
    try:
        f()
    catch e:
        stats[1] = stats[1] + 1
        __list_append(notes, f"{label} : exception inattendue {e.type}: {e.message}")
    if stats[1] > before:
        __list_append(failed_groups, label)

# nettoyage éventuel d'une exécution précédente interrompue
if os.exists(T):
    os.rmdir(T, true)
os.mkdir_all(T)

run_group("système", t_system)
run_group("chdir", t_chdir)
run_group("arguments", t_args)
run_group("environnement", t_env)
run_group("chemins POSIX", t_path_posix)
run_group("chemins Windows", t_path_windows)
run_group("chemins publics", t_path_public)
run_group("fichiers", t_fs_basic)
run_group("mkdir_all", t_mkdir_all)
run_group("rmdir récursif", t_rmdir_recursive)
run_group("liens symboliques", t_symlinks)
run_group("copy", t_copy)
run_group("move", t_move)
run_group("permissions", t_permissions)
run_group("infos processus", t_process_info)
run_group("run", t_run)
run_group("execute", t_execute)
run_group("spawn/wait/kill", t_spawn_wait_kill)
run_group("temps", t_time)
run_group("terminal", t_terminal)

os.chdir(START)
os.rmdir(T, true)
check(not os.exists(T), "nettoyage du dossier de test")

total := stats[0] + stats[1]
print("")
print("=== Résultat os ===")
print(f"Vérifications : {stats[0]} réussies, {stats[1]} en échec (sur {total}) ; {stats[2]} ignorée(s)")
if stats[1] > 0:
    for n in notes:
        print("  ECHEC : " + n)
    print(f"Groupes en échec : {failed_groups}")
    raise("AssertionError", f"{stats[1]} vérification(s) en échec")
print("TOUS LES TESTS OS PASSENT")
