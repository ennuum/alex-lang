# ALEX STANDARD LIBRARY — os
#
# Architecture
#   os.al          API publique ALEX + logique de haut niveau (chemins,
#                  copie / déplacement / suppression récursifs, normalisation,
#                  conversions de modes, system_info, terminal...).
#   _native_os     primitives qui dépendent RÉELLEMENT de l'OS (runtime natif ALEX :
#                  runtime/alex/native/dyn_nat.al). Backends POSIX et Windows séparés.
#
# Permissions : ce sont celles du système d'exploitation. Aucune sandbox
# artificielle n'est ajoutée par le langage : une opération refusée par l'OS
# lève IoError, une opération permise par l'OS réussit.
#
# Erreurs
#   IoError        l'OS refuse ou ne peut pas faire l'opération.
#   TypeError      argument d'un mauvais type.
#   ArgumentError  argument de bon type mais invalide (pid <= 0, mode hors limites...).
#
# Conventions
#   - Les temps (time, mtime, atime, ctime) sont des float : secondes depuis
#     l'epoch Unix. monotonic_time() est en secondes depuis une origine
#     arbitraire.
#   - Les noms commençant par `_` sont des détails d'implémentation (le
#     langage n'a pas de visibilité privée) : ne pas en dépendre.
#   - Les paramètres optionnels valent `null` par défaut (le langage ne
#     supporte pas d'autres valeurs par défaut).

from core use len, type
use string as _s
use _native_os as _os_native

const _WIN := _os_native.platform() == "windows"

# ---------------------------------------------------------------------
# Outils internes
# ---------------------------------------------------------------------

func _need_str(fn, value, label):
    if type(value) != "str":
        raise("TypeError", "os." + fn + "() : " + label + " doit être une str (obtenu '" + type(value) + "')")

# Appelle f() ; null si elle échoue (utile pour system_info).
func _attempt(f):
    try:
        return f()
    catch e:
        return null

# Caractère d'indice i, en str. (s[i] renvoie un `char`, jamais égal à une str.)
func _ch(s, i):
    return _s.substring(s, i, i + 1)

func _sep(win):
    if win:
        return "\\"
    return "/"

func _is_sep(ch, win):
    if ch == "/":
        return true
    if win and ch == "\\":
        return true
    return false

func _is_letter(ch):
    lo := _s.lower(ch)
    return len(lo) == 1 and lo >= "a" and lo <= "z"

func _ends_with_sep(s, win):
    n := len(s)
    if n == 0:
        return false
    return _is_sep(_ch(s, n - 1), win)

func _rstrip_seps(s, win):
    n := len(s)
    while n > 0 and _is_sep(_ch(s, n - 1), win):
        n -= 1
    return _s.substring(s, 0, n)

func _last_sep(s, win):
    i := len(s) - 1
    while i >= 0:
        if _is_sep(_ch(s, i), win):
            return i
        i -= 1
    return -1

# Sépare un chemin en [racine, reste].
#   POSIX   : "/a/b" -> ["/", "a/b"]   "a/b" -> ["", "a/b"]
#   Windows : "C:\x" -> ["C:\", "x"]  "C:x" -> ["C:", "x"]
#             "\\srv\share\x" -> ["\\srv\share\", "x"]  "\x" -> ["\", "x"]
# `win` est un paramètre (et non la constante _WIN) pour que la logique
# Windows soit testable depuis n'importe quelle plateforme.
func _split_root(p, win):
    n := len(p)
    if not win:
        i := 0
        while i < n and _ch(p, i) == "/":
            i += 1
        if i == 0:
            return ["", p]
        return ["/", _s.substring(p, i, n)]
    if n >= 2 and _is_sep(_ch(p, 0), true) and _is_sep(_ch(p, 1), true):
        j := 2
        while j < n and not _is_sep(_ch(p, j), true):
            j += 1
        if j > 2 and j < n:
            k := j + 1
            while k < n and not _is_sep(_ch(p, k), true):
                k += 1
            if k > j + 1:
                stop := k
                if k < n:
                    stop = k + 1
                return [_s.substring(p, 0, stop), _s.substring(p, stop, n)]
    if n >= 2 and _ch(p, 1) == ":" and _is_letter(_ch(p, 0)):
        if n >= 3 and _is_sep(_ch(p, 2), true):
            return [_s.substring(p, 0, 3), _s.substring(p, 3, n)]
        return [_s.substring(p, 0, 2), _s.substring(p, 2, n)]
    if n >= 1 and _is_sep(_ch(p, 0), true):
        j2 := 1
        while j2 < n and _is_sep(_ch(p, j2), true):
            j2 += 1
        return [_s.substring(p, 0, 1), _s.substring(p, j2, n)]
    return ["", p]

# Composantes non vides d'un reste de chemin.
func _split_parts(rest, win):
    text := rest
    if win:
        text = _s.replace(text, "\\", "/")
    parts := []
    for piece in _s.split(text, "/"):
        if piece != "":
            __list_append(parts, piece)
    return parts

func _is_absolute(p, win):
    rr := _split_root(p, win)
    root := rr[0]
    if root == "":
        return false
    if win and len(root) == 2 and _ch(root, 1) == ":":
        return false
    return true

func _is_drive_relative(p, win):
    if not win:
        return false
    rr := _split_root(p, win)
    root := rr[0]
    return len(root) == 2 and _ch(root, 1) == ":"

# Normalisation purement lexicale (aucun accès au disque).
func _normalize(p, win):
    if p == "":
        return "."
    rr := _split_root(p, win)
    root := rr[0]
    if win:
        root = _s.replace(root, "/", "\\")
    anchored := _ends_with_sep(root, win)
    out := []
    for part in _split_parts(rr[1], win):
        if part == ".":
            continue
        if part == "..":
            if len(out) > 0 and out[len(out) - 1] != "..":
                __list_remove_at(out, len(out) - 1)
            elif anchored:
                continue
            else:
                __list_append(out, "..")
        else:
            __list_append(out, part)
    result := root + _s.join(_sep(win), out)
    if result == "":
        return "."
    return result

func _basename(p, win):
    rr := _split_root(p, win)
    rest := _rstrip_seps(rr[1], win)
    i := _last_sep(rest, win)
    if i < 0:
        return rest
    return _s.substring(rest, i + 1, len(rest))

func _dirname(p, win):
    rr := _split_root(p, win)
    root := rr[0]
    rest := _rstrip_seps(rr[1], win)
    i := _last_sep(rest, win)
    if i < 0:
        return root
    head := _rstrip_seps(_s.substring(rest, 0, i), win)
    return root + head

# Indice du point d'extension dans un nom de fichier, ou -1. Un point n'est
# une extension que s'il est précédé d'au moins un caractère qui n'est pas un
# point : ".bashrc" et ".." n'ont pas d'extension ; "a." a l'extension ".".
func _ext_index(base):
    i := len(base) - 1
    while i >= 0 and _ch(base, i) != ".":
        i -= 1
    if i < 0:
        return -1
    j := 0
    while j < i:
        if _ch(base, j) != ".":
            return i
        j += 1
    return -1

func _join_list(parts, win):
    sep := _sep(win)
    result := ""
    for part in parts:
        if type(part) != "str":
            raise("TypeError", "os.join() : chaque segment doit être une str (obtenu '" + type(part) + "')")
        if part == "":
            continue
        if result == "":
            result = part
        elif _is_absolute(part, win) or _is_drive_relative(part, win):
            result = part
        elif _ends_with_sep(result, win):
            result = result + part
        elif win and _ch(result, len(result) - 1) == ":":
            result = result + part
        else:
            result = result + sep + part
    return result

# Notation octale "755" / "0644" / "0o755" -> entier.
func _parse_octal(fn, text):
    s := _s.trim(text)
    if _s.starts_with(s, "0o"):
        s = _s.substring(s, 2, len(s))
    if s == "":
        raise("ArgumentError", "os." + fn + "() : mode octal vide")
    value := 0
    i := 0
    while i < len(s):
        d := _s.find("01234567", _ch(s, i))
        if d < 0:
            raise("ArgumentError", "os." + fn + "() : mode octal invalide '" + text + "'")
        value = value * 8 + d
        i += 1
    return value

# ---------------------------------------------------------------------
# Système
# ---------------------------------------------------------------------

# Nom de l'OS tel que le rapporte le système : "Linux", "Darwin", "Windows".
func name():
    return _os_native.name()

# Identifiant normalisé : "linux", "macos", "windows" ou "unknown".
func platform():
    return _os_native.platform()

# Architecture normalisée : "x86_64", "arm64", "x86", "arm" (sinon la valeur
# du système en minuscules : "riscv64", "ppc64le"...).
func arch():
    m := _s.lower(_os_native.arch())
    if m == "x86_64" or m == "amd64" or m == "x64":
        return "x86_64"
    if m == "aarch64" or m == "arm64" or m == "arm64e":
        return "arm64"
    if m == "x86" or m == "i386" or m == "i486" or m == "i586" or m == "i686":
        return "x86"
    if m == "arm" or _s.starts_with(m, "armv"):
        return "arm"
    return m

# Version du compilateur / runtime ALEX qui exécute ce programme (SemVer) : "1.2.0" (stable) ou
# "1.2.0-beta.7" (bêta). Voir docs/VERSIONS.md.
func alex_version():
    return _os_native.alex_build()["version"]

# Détails du build : {"version", "full", "base", "major", "minor", "patch", "channel" ("beta" | "stable"),
# "build", "date", "source_id", "commit"}.
func alex_build():
    return _os_native.alex_build()

# Vrai si le runtime satisfait la contrainte (">=1.2.0", "^1.0", "~1.4.2", "=1.2.0", "*") ; comparaison SemVer
# complète (une bêta 1.3.0-beta.2 satisfait ">=1.2" mais pas ">=1.3.0"). ArgumentError si mal formée.
func alex_satisfies(constraint):
    return _os_native.alex_satisfies(constraint)

# Version / release de l'OS ("6.8.0-45-generic", "23.5.0" (Darwin), "10.0.22631").
func version():
    return _os_native.version()

func hostname():
    return _os_native.hostname()

# Nom de l'utilisateur effectif, ou null s'il est indéterminable.
func username():
    return _os_native.username()

# uid / gid effectifs. null sous Windows (pas de notion équivalente).
func user_id():
    return _os_native.user_id()

func group_id():
    return _os_native.group_id()

# Dossier personnel de l'utilisateur, ou null s'il est indéterminable.
func home():
    return _os_native.home()

func tmp_dir():
    return _os_native.tmp_dir()

func cwd():
    return _os_native.cwd()

# Change le répertoire de travail du processus (et de ses futurs fils).
func chdir(path):
    _os_native.chdir(path)
    return null

# Nombre de processeurs logiques utilisables par ce processus (>= 1).
func cpu_count():
    return _os_native.cpu_count()

func pid():
    return _os_native.pid()

func parent_pid():
    return _os_native.parent_pid()

# Dictionnaire récapitulatif. Une information indisponible vaut null.
func system_info():
    info := {}
    info["name"] = _attempt(name)
    info["platform"] = platform()
    info["arch"] = _attempt(arch)
    info["version"] = _attempt(version)
    info["hostname"] = _attempt(hostname)
    info["username"] = _attempt(username)
    info["user_id"] = _attempt(user_id)
    info["group_id"] = _attempt(group_id)
    info["cpu_count"] = _attempt(cpu_count)
    info["total_memory"] = _attempt(_os_native.total_memory)
    info["home"] = _attempt(home)
    info["tmp_dir"] = _attempt(tmp_dir)
    info["cwd"] = _attempt(cwd)
    info["pid"] = pid()
    info["path_separator"] = _sep(_WIN)
    if _WIN:
        info["line_separator"] = "\r\n"
    else:
        info["line_separator"] = "\n"
    return info

# ---------------------------------------------------------------------
# Arguments du programme
#   argv() = [chemin du script, arg1, arg2, ...]   (comme sys.argv)
#   args() = [arg1, arg2, ...]                      (sans le script)
#   argc() = len(argv())
# ---------------------------------------------------------------------

func argv():
    return _os_native.process_args()

func argc():
    return len(_os_native.process_args())

# exit(code=0) : termine le programme immédiatement avec ce code de sortie (0..255).
# Les blocs `finally` en cours ne sont pas exécutés ; les sorties sont vidées.
func exit(code=0):
    _os_native.exit(code)

func args():
    full := _os_native.process_args()
    out := []
    i := 1
    while i < len(full):
        __list_append(out, full[i])
        i += 1
    return out

# ---------------------------------------------------------------------
# Variables d'environnement
# Elles concernent le PROCESSUS ALEX (et ses futurs fils), jamais le shell
# appelant : un processus ne peut pas modifier l'environnement de son parent.
# ---------------------------------------------------------------------

# Valeur de la variable, ou `fallback` (null par défaut) si elle est absente.
func getenv(name_, fallback=null):
    return _os_native.get_env(name_, fallback)

func setenv(name_, value):
    _os_native.set_env(name_, value)
    return null

# Supprimer une variable absente n'est pas une erreur.
func unsetenv(name_):
    _os_native.unset_env(name_)
    return null

# Vrai même si la variable est définie à la chaîne vide.
func hasenv(name_):
    return _os_native.get_env(name_, null) != null

# Copie de tout l'environnement : dict nom -> valeur.
func env():
    d := {}
    for pair in _os_native.env_list():
        d[pair[0]] = pair[1]
    return d

# ---------------------------------------------------------------------
# Chemins (calcul lexical, sauf realpath et absolute qui consultent l'OS)
# Séparateur : "/" (POSIX) ou "\" (Windows, où "/" est aussi accepté en entrée).
# ---------------------------------------------------------------------

# Concatène des segments avec le séparateur de la plateforme :
#   join("a", "b", "c")  ou  join(["a", "b", "c"])   (jusqu'à 8 segments positionnels)
# Un segment vide est ignoré ; un segment absolu remplace tout ce qui précède.
# Aucune normalisation : join("a", "../b") == "a/../b" (voir normalize).
func join(first, second=null, third=null, fourth=null, fifth=null, sixth=null, seventh=null, eighth=null):
    parts := []
    if type(first) == "list" or type(first) == "tuple":
        for item in first:
            __list_append(parts, item)
    else:
        __list_append(parts, first)
    for extra in [second, third, fourth, fifth, sixth, seventh, eighth]:
        if extra != null:
            __list_append(parts, extra)
    return _join_list(parts, _WIN)

# Dernier composant. Les séparateurs finaux sont ignorés : basename("a/b/") == "b".
func basename(path):
    _need_str("basename", path, "le chemin")
    return _basename(path, _WIN)

# Tout sauf le dernier composant ; "" pour un chemin relatif sans séparateur
# (comme os.path.dirname de Python), la racine pour "/x".
func dirname(path):
    _need_str("dirname", path, "le chemin")
    return _dirname(path, _WIN)

# Dernière extension avec son point : extension("a/b.tar.gz") == ".gz".
# "" s'il n'y en a pas (".bashrc" n'a pas d'extension).
func extension(path):
    _need_str("extension", path, "le chemin")
    base := _basename(path, _WIN)
    i := _ext_index(base)
    if i < 0:
        return ""
    return _s.substring(base, i, len(base))

# Nom de fichier sans sa dernière extension : stem("a/b.tar.gz") == "b.tar".
func stem(path):
    _need_str("stem", path, "le chemin")
    base := _basename(path, _WIN)
    i := _ext_index(base)
    if i < 0:
        return base
    return _s.substring(base, 0, i)

# Normalise LEXICALEMENT : retire "." et les séparateurs en double, résout
# "..". Ne touche pas au disque (peut différer de realpath en présence de
# liens symboliques). Retourne "." pour un chemin vide ou qui s'annule.
func normalize(path):
    _need_str("normalize", path, "le chemin")
    return _normalize(path, _WIN)

# Chemin absolu et normalisé, relatif au répertoire de travail courant.
# Ne résout pas les liens symboliques et n'exige pas que le chemin existe.
func absolute(path):
    _need_str("absolute", path, "le chemin")
    return _normalize(_os_native.absolute_path(path), _WIN)

# Chemin canonique : résout les liens symboliques de la partie existante.
# Le chemin n'a pas besoin d'exister en entier.
func realpath(path):
    _need_str("realpath", path, "le chemin")
    return _os_native.real_path(path)

# Absolu = commence par "/" (POSIX) ; "C:\..." ou "\\serveur\partage\..." ou
# "\..." (Windows). "C:x" (relatif au lecteur) n'est pas absolu.
func is_absolute(path):
    _need_str("is_absolute", path, "le chemin")
    return _is_absolute(path, _WIN)

# ---------------------------------------------------------------------
# Système de fichiers : questions
# exists / isfile / isdir / islink ne lèvent jamais d'erreur : un chemin
# inaccessible est simplement "faux". exists / isfile / isdir suivent les
# liens symboliques (un lien cassé n'existe pas) ; islink ne les suit pas.
# ---------------------------------------------------------------------

func exists(path):
    return _os_native.exists(path)

func isfile(path):
    return _os_native.is_file(path)

func isdir(path):
    return _os_native.is_dir(path)

func islink(path):
    return _os_native.is_link(path)

# Taille en octets d'un fichier régulier (IoError pour un dossier).
func size(path):
    return _os_native.size(path)

# Dernière modification du contenu (secondes epoch, float).
func mtime(path):
    return _os_native.mtime(path)

# Dernier accès (peut être désactivé par l'OS : noatime, relatime...).
func atime(path):
    return _os_native.atime(path)

# POSIX : dernier changement de métadonnées (inode). Windows : création.
func ctime(path):
    return _os_native.ctime(path)

# Noms (pas les chemins) des entrées d'un dossier, TRIÉS, sans "." ni "..".
func list_dir(path):
    return _os_native.list_dir(path)

# ---------------------------------------------------------------------
# Système de fichiers : actions
# ---------------------------------------------------------------------

# Fixe les dates d'accès et de modification (secondes epoch, int ou float ; suit les liens symboliques).
#   set_times(path)                  les deux à « maintenant » (comme `touch`)
#   set_times(path, atime, mtime)    chacune est fixée si elle est donnée ; null = inchangée
# Le fichier doit exister (IoError sinon). Selon le système de fichiers, la précision peut être inférieure à la
# nanoseconde, et atime peut être ignorée (noatime).
func set_times(path, atime=null, mtime=null):
    _need_str("set_times", path, "le chemin")
    if atime == null and mtime == null:
        now := _os_native.time()
        _os_native.set_times(path, now, now)
    else:
        _os_native.set_times(path, atime, mtime)
    return null

# Supprime un fichier ou un lien symbolique (le lien, jamais sa cible).
# Refuse les dossiers : voir rmdir.
func remove(path):
    _os_native.remove_file(path)
    return null

# Crée UN dossier ; son parent doit exister, lui-même ne doit pas exister.
func mkdir(path):
    _os_native.make_dir(path)
    return null

# Crée un dossier et tous ses parents manquants (mkdir -p). Ne fait rien si le
# dossier existe déjà ; IoError si le chemin existe et n'est pas un dossier.
func mkdir_all(path):
    _need_str("mkdir_all", path, "le chemin")
    if _os_native.is_dir(path):
        return null
    if _os_native.exists(path):
        raise("IoError", "mkdir_all('" + path + "') : existe déjà et n'est pas un dossier")
    parent := _dirname(path, _WIN)
    if parent != "" and parent != path and not _os_native.is_dir(parent):
        mkdir_all(parent)
    try:
        _os_native.make_dir(path)
    catch e:
        # Un autre processus a pu le créer entre-temps : ce n'est pas une erreur.
        if not _os_native.is_dir(path):
            raise(e.type, e.message)
    return null

# Suppression récursive (sans jamais suivre les liens symboliques).
func _rmtree(path):
    if _os_native.is_link(path):
        raise("IoError", "rmdir('" + path + "') : est un lien symbolique, pas un dossier")
    for entry in _os_native.list_dir(path):
        child := join(path, entry)
        if _os_native.is_dir(child) and not _os_native.is_link(child):
            _rmtree(child)
        else:
            _os_native.remove_file(child)
    _os_native.remove_dir(path)

# Supprime un dossier. Par défaut il doit être VIDE ; rmdir(path, true) supprime
# aussi tout son contenu.
# ATTENTION : la suppression récursive est irréversible.
func rmdir(path, recursive=null):
    _need_str("rmdir", path, "le chemin")
    if recursive:
        _rmtree(path)
    else:
        _os_native.remove_dir(path)
    return null

# Lève IoError si `target` est `src` ou se trouve à l'intérieur de `src`
# (copier un dossier dans lui-même ne terminerait jamais).
func _guard_not_inside(src, target):
    real_src := _os_native.real_path(src)
    real_dst := _os_native.real_path(target)
    if _WIN:
        real_src = _s.lower(real_src)
        real_dst = _s.lower(real_dst)
    prefix := real_src
    if not _ends_with_sep(prefix, _WIN):
        prefix = prefix + _sep(_WIN)
    if real_dst == real_src or _s.starts_with(real_dst, prefix):
        raise("IoError", "copy('" + src + "', '" + target + "') : impossible de copier un dossier dans lui-même")

# Copie récursive d'un dossier. Les liens symboliques sont recréés tels quels
# (jamais suivis) ; les fichiers existants à destination sont écrasés.
func _copy_tree(src, dst):
    if not _os_native.exists(dst):
        _os_native.make_dir(dst)
    elif not _os_native.is_dir(dst):
        raise("IoError", "copy('" + src + "', '" + dst + "') : la destination existe et n'est pas un dossier")
    for entry in _os_native.list_dir(src):
        from_path := join(src, entry)
        to_path := join(dst, entry)
        if _os_native.is_link(from_path):
            if _os_native.is_link(to_path) or _os_native.is_file(to_path):
                _os_native.remove_file(to_path)
            _os_native.copy_symlink(from_path, to_path)
        elif _os_native.is_dir(from_path):
            _copy_tree(from_path, to_path)
        elif _os_native.is_file(from_path):
            _os_native.copy_file(from_path, to_path)
        else:
            raise("IoError", "copy('" + from_path + "') : type de fichier non supporté (ni fichier, ni dossier, ni lien)")

# Copie un fichier ou un dossier (récursivement). Si `dst` est un dossier
# existant, la copie est faite DANS ce dossier (comme `cp`). Écrase un fichier
# existant. Retourne le chemin réellement écrit.
func copy(src, dst):
    _need_str("copy", src, "la source")
    _need_str("copy", dst, "la destination")
    target := dst
    if _os_native.is_dir(dst):
        target = join(dst, _basename(absolute(src), _WIN))
    if _os_native.is_dir(src):
        _guard_not_inside(src, target)
        _copy_tree(src, target)
    else:
        _os_native.copy_file(src, target)
    return target

# Déplace / renomme. Si `dst` est un dossier existant, la source est déplacée
# DANS ce dossier (comme `mv`). Sur volumes différents, bascule
# automatiquement sur copie puis suppression. Retourne le chemin final.
func move(src, dst):
    _need_str("move", src, "la source")
    _need_str("move", dst, "la destination")
    target := dst
    if _os_native.is_dir(dst):
        target = join(dst, _basename(absolute(src), _WIN))
    if _os_native.rename(src, target):
        return target
    if _os_native.is_link(src):
        if _os_native.is_link(target) or _os_native.is_file(target):
            _os_native.remove_file(target)
        _os_native.copy_symlink(src, target)
        _os_native.remove_file(src)
    elif _os_native.is_dir(src):
        _guard_not_inside(src, target)
        _copy_tree(src, target)
        _rmtree(src)
    else:
        _os_native.copy_file(src, target)
        _os_native.remove_file(src)
    return target

# ---------------------------------------------------------------------
# Permissions (celles de l'OS)
# ---------------------------------------------------------------------

# Bits de permission sous forme d'entier : 0o644 s'écrit 420, 0o755 s'écrit
# 493 (ALEX n'a pas de littéral octal ; chmod accepte aussi "644" / "0o755").
# Windows : valeur approximée (lecture seule ou non ; exécutable selon l'extension).
func permissions(path):
    return _os_native.get_mode(path)

# mode : entier (0..4095) ou chaîne octale ("755", "0644", "0o755").
# Windows : seul le bit d'écriture du propriétaire (0o200) a un effet
# (attribut "lecture seule").
func chmod(path, mode):
    bits := mode
    if type(mode) == "str":
        bits = _parse_octal("chmod", mode)
    _os_native.set_mode(path, bits)
    return null

# L'utilisateur courant peut-il accéder au chemin comme demandé ?
#   mode : null (existence), "r", "w", "x" ou une combinaison ("rw", "rwx"),
#          ou un entier 0..7 (4 = lecture, 2 = écriture, 1 = exécution).
func access(path, mode=null):
    bits := 0
    if type(mode) == "int":
        bits = mode
    elif type(mode) == "str":
        want_r := false
        want_w := false
        want_x := false
        i := 0
        while i < len(mode):
            c := _ch(mode, i)
            if c == "r":
                want_r = true
            elif c == "w":
                want_w = true
            elif c == "x":
                want_x = true
            else:
                raise("ArgumentError", "os.access() : mode invalide '" + mode + "' (attendu : r, w, x)")
            i += 1
        bits = (4 if want_r else 0) + (2 if want_w else 0) + (1 if want_x else 0)
    elif mode != null:
        raise("TypeError", "os.access() : mode doit être null, une str ou un int (obtenu '" + type(mode) + "')")
    return _os_native.access(path, bits)

# ---------------------------------------------------------------------
# Processus
# ---------------------------------------------------------------------

func _arg_list(fn, arglist):
    if arglist == null:
        return []
    t := type(arglist)
    if t != "list" and t != "tuple":
        raise("TypeError", "os." + fn + "() : args doit être une list de str (obtenu '" + t + "')")
    return arglist

# Lance `program` SANS shell (recherche dans le PATH) et rend la main
# immédiatement. Les flux standard sont hérités. Retourne le pid.
# Appeler wait(pid) pour récupérer le code de sortie et libérer le processus
# (un fils terminé mais non attendu reste un zombie sous POSIX).
func spawn(program, args=null):
    return _os_native.spawn(program, _arg_list("spawn", args))

# Lance `program` SANS shell, attend sa fin et CAPTURE sa sortie. Retourne
#   {"code": int, "stdout": str, "stderr": str}
# `input` (str, optionnel) est envoyé sur l'entrée standard du fils.
# Un programme introuvable lève IoError ; un code de sortie non nul n'est
# pas une erreur. code < 0 (POSIX) : tué par le signal -code.
func run(program, args=null, input=null):
    return _os_native.run(program, _arg_list("run", args), input)

# Exécute une ligne de commande par le SHELL du système (/bin/sh -c ;
# cmd.exe /c), flux hérités, attend la fin. Retourne le code de sortie.
# Attention : la commande est interprétée par le shell (pas d'échappement
# automatique) — pour passer des arguments sûrs, préférer run / spawn.
func execute(command):
    return _os_native.execute(command)

# Chemin de l'exécutable alex qui exécute le programme (null s'il est inconnu).
func executable():
    return _os_native.get_env("ALEX_EXE", null)

# Attend la fin du processus `pid` (lancé par spawn) et retourne son code de
# sortie. Avec `timeout` (secondes) : null si le délai expire d'abord.
func wait(pid, timeout=null):
    return _os_native.wait(pid, timeout)

# Envoie un signal. `signal` : nom ("TERM" par défaut, "KILL", "INT", "HUP",
# "SIGKILL"...) ou numéro. Windows : tout signal termine le processus de
# force, sauf 0 qui teste seulement l'existence.
func kill(pid, signal=null):
    sig := signal
    if sig == null:
        sig = "TERM"
    _os_native.kill(pid, sig)
    return null

# Vrai si le processus existe (un zombie non attendu compte comme existant).
func process_exists(pid):
    return _os_native.process_exists(pid)

# ---------------------------------------------------------------------
# Temps
# ---------------------------------------------------------------------

# Heure murale : secondes depuis l'epoch Unix (float, précision sub-seconde).
# Peut sauter (NTP, changement d'heure manuel) : pour mesurer une durée,
# utiliser monotonic_time().
func time():
    return _os_native.time()

# Heure locale actuelle décomposée :
#   year, month (1-12), day, hour, minute, second, microsecond,
#   weekday (0 = lundi ... 6 = dimanche), yearday (1-366),
#   utc_offset (secondes à l'est de UTC), is_dst, timezone, timestamp.
func system_time():
    return _os_native.local_time()

# Horloge monotone : ne recule jamais, origine arbitraire (secondes, float).
func monotonic_time():
    return _os_native.monotonic_time()

# Suspend le processus `seconds` secondes (int ou float >= 0).
func sleep(seconds):
    _os_native.sleep(seconds)
    return null

# ---------------------------------------------------------------------
# Terminal
# ---------------------------------------------------------------------

# {"stdin": bool, "stdout": bool, "stderr": bool   (flux reliés à un terminal)
#  "columns": int|null, "rows": int|null           (taille, si connue)
#  "term": str|null                                (variable TERM)
#  "color": bool}                                  (couleurs raisonnables : sortie
#                                                   sur terminal, TERM != "dumb",
#                                                   NO_COLOR absent ou vide)
func terminal():
    t := _os_native.terminal()
    term := _os_native.get_env("TERM", null)
    no_color := _os_native.get_env("NO_COLOR", null)
    t["term"] = term
    t["color"] = t["stdout"] and term != "dumb" and (no_color == null or no_color == "")
    return t

# ---------------------------------------------------------------------
# Noms historiques (conservés pour compatibilité ; préférer getenv, setenv, isdir)
# ---------------------------------------------------------------------

func get_env(name_, fallback=null):
    return getenv(name_, fallback)

func set_env(name_, value):
    return setenv(name_, value)

func is_dir(path):
    return isdir(path)
