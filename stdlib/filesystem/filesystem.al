# ALEX STANDARD LIBRARY — filesystem
# Parcours et gestion de l'arborescence de fichiers, en ALEX pur : aucune primitive C++ dédiée.
# S'appuie sur `os` (accès au disque), `path` (motifs glob) et `io`. Le contenu des fichiers relève de `file`.
#
#   use filesystem as fs
#   fs.ensure_dir("build/out")                    # mkdir -p
#   fs.find("src", "*.al", "file")                # tous les .al sous src/ (récursif)
#   fs.glob("src", "**/test_*.al")                # motif avec ** (zéro ou plusieurs dossiers)
#   fs.tree_size("build")                         # octets cumulés des fichiers
#   fs.with_temp_dir((d) => os.join(d, "x"))      # dossier temporaire supprimé à la sortie
#
# INTERROGER (ne lèvent jamais d'erreur : un chemin inaccessible est « faux »)
#   kind_of(p) -> "file" | "dir" | "symlink" | "other" | null (absent)     exists / is_file / is_dir / is_link
#   is_readable / is_writable / is_executable                              same_file(a, b)   is_inside(p, dossier)
# INFORMER (IoError si le chemin n'existe pas)
#   stat(p) -> {path, name, kind, size, mtime, atime, ctime, mode}          is_empty(p)       tree_size(p)
# LISTER (ordre déterministe : entrées triées par nom, parcours en profondeur)
#   list_dir / list_files / list_dirs (full=false : noms ; true : chemins)
#   walk(racine, follow_links=false) -> [[dossier, [sous-dossiers], [autres entrées]], ...]
#   find(racine, pattern=null, kind=null, max_depth=null) -> chemins          glob(racine, motif, kind=null)
# AGIR
#   ensure_dir / ensure_parent / ensure_file / touch   remove(p, missing_ok=false)   remove_tree(p, missing_ok=false)
#   clear_dir(p)    copy(src, dst, overwrite=true)    move(src, dst, overwrite=true)
#   make_temp_dir(prefix, parent)    with_temp_dir(fn, prefix, parent)
#   make_temp_file(prefix, suffix, parent)    with_temp_file(fn, prefix, suffix, parent)
#
# Conventions
#   - Les liens symboliques ne sont jamais suivis par find / glob (segments explicites mis à part) / tree_size /
#     remove_tree / clear_dir ; walk ne les suit que si follow_links est vrai (avec détection de cycles).
#   - `*` et `?` d'un motif glob s'appliquent à un nom ; les fichiers cachés ne sont pas traités à part.
#   - Une erreur d'accès pendant un parcours (dossier illisible) est propagée telle quelle (IoError).
#   - Les noms commençant par `_` sont des détails d'implémentation.
# Erreurs : TypeError (argument non str), ValueError (argument invalide, suppression refusée), IoError (OS).

from core use len, type, to_int
from collections use append, contains_key
use string as _s
use os as _os
use path as _path
use io as _io

const _WIN := _os.platform() == "windows"
const _KINDS := ["file", "dir", "symlink", "other"]

_state := {"temp": 0}

# ---------------------------------------------------------------------
# Outils internes
# ---------------------------------------------------------------------

func _need_str(fn, value, label="le chemin"):
    if type(value) != "str":
        raise("TypeError", "filesystem." + fn + "() : " + label + " doit être une str (obtenu '" + type(value) + "')")

func _present(p):
    return _os.exists(p) or _os.islink(p)

func _need_present(fn, p):
    if not _present(p):
        raise("IoError", "filesystem." + fn + "('" + p + "') : chemin introuvable")

func _contains(items, x):
    for it in items:
        if it == x:
            return true
    return false

func _check_kind(fn, kind):
    if kind == null:
        return null
    if type(kind) != "str" or not _contains(_KINDS, kind):
        raise("ValueError", "filesystem." + fn + "() : kind doit valoir null, \"file\", \"dir\", \"symlink\" ou \"other\"")

func _sep():
    if _WIN:
        return "\\"
    return "/"

# Chemin canonique prêt à être comparé (insensible à la casse sous Windows).
func _canon(p):
    real := _os.realpath(p)
    if _WIN:
        return _s.lower(real)
    return real

# Vrai si `inner` est `outer` ou se trouve dessous (deux chemins canoniques de _canon).
func _covers(outer, inner):
    if inner == outer:
        return true
    prefix := outer
    if not _s.ends_with(prefix, _sep()):
        prefix = prefix + _sep()
    return _s.starts_with(inner, prefix)

# Appelle f(p) ; null si elle lève (champ d'un `stat` non disponible, lien cassé...).
func _attempt(f, p):
    try:
        return f(p)
    catch e:
        return null

func _kind_ok(p, want):
    if want == null:
        return true
    return kind_of(p) == want

# Refuse les cibles dont la suppression en masse serait catastrophique. ValueError pour :
#   - un chemin vide, ou dont le DERNIER composant tel qu'écrit est "." ou ".." (`a/.` et `a/..` sont refusés
#     même si `a/.` désigne un dossier ordinaire : ces formes trahissent presque toujours une erreur) ;
#   - la racine du disque ;
#   - tout dossier qui CONTIENT le dossier de travail courant (ou l'est) ou le dossier personnel (ou l'est).
# Un lien symbolique n'est soumis qu'au premier contrôle : on retire le lien, jamais sa cible.
func _refuse_unsafe(fn, p):
    label := "filesystem." + fn + "('" + p + "') : cible refusée ("
    if p == "":
        raise("ValueError", label + "chemin vide)")
    last := _os.basename(p)
    if last == "" or last == "." or last == "..":
        raise("ValueError", label + "'.', '..' ou racine)")
    if _os.islink(p):
        return null
    real := _canon(p)
    if _os.dirname(real) == real or _os.basename(real) == "":
        raise("ValueError", label + "racine du système de fichiers)")
    if _covers(real, _canon(_os.cwd())):
        raise("ValueError", label + "contient le dossier de travail courant)")
    h := _os.home()
    if h != null and _os.exists(h) and _covers(real, _canon(h)):
        raise("ValueError", label + "contient le dossier personnel)")
    return null

# ---------------------------------------------------------------------
# Interroger
# ---------------------------------------------------------------------

# "symlink" (même cassé), "dir", "file", "other" (socket, périphérique...) ou null si le chemin n'existe pas.
func kind_of(p):
    _need_str("kind_of", p)
    if _os.islink(p):
        return "symlink"
    if _os.isdir(p):
        return "dir"
    if _os.isfile(p):
        return "file"
    if _os.exists(p):
        return "other"
    return null

# Suivent les liens symboliques (comme os.exists / os.isfile / os.isdir) ; un lien cassé n'existe pas.
func exists(p):
    _need_str("exists", p)
    return _os.exists(p)

func is_file(p):
    _need_str("is_file", p)
    return _os.isfile(p)

func is_dir(p):
    _need_str("is_dir", p)
    return _os.isdir(p)

# Ne suit PAS le lien : un lien cassé est bien un lien.
func is_link(p):
    _need_str("is_link", p)
    return _os.islink(p)

func is_readable(p):
    _need_str("is_readable", p)
    return _os.access(p, "r")

func is_writable(p):
    _need_str("is_writable", p)
    return _os.access(p, "w")

func is_executable(p):
    _need_str("is_executable", p)
    return _os.access(p, "x")

# Vrai si a et b désignent le même chemin canonique (liens résolus). Faux si l'un des deux n'existe pas.
func same_file(a, b):
    _need_str("same_file", a)
    _need_str("same_file", b)
    if not _os.exists(a) or not _os.exists(b):
        return false
    return _canon(a) == _canon(b)

# Vrai si `p` est STRICTEMENT à l'intérieur de `folder` (chemins canoniques, liens résolus).
func is_inside(p, folder):
    _need_str("is_inside", p)
    _need_str("is_inside", folder, "le dossier")
    real_p := _canon(p)
    real_f := _canon(folder)
    if real_p == real_f:
        return false
    return _covers(real_f, real_p)

# ---------------------------------------------------------------------
# Informer
# ---------------------------------------------------------------------

# Dictionnaire descriptif. `size` n'est renseignée que pour un fichier régulier ; les champs qu'on ne peut pas
# lire (lien cassé...) valent null. Les temps sont des secondes epoch (float), `mode` les bits de permission.
func stat(p):
    _need_str("stat", p)
    k := kind_of(p)
    if k == null:
        raise("IoError", "filesystem.stat('" + p + "') : chemin introuvable")
    info := {}
    info["path"] = p
    info["name"] = _os.basename(p)
    info["kind"] = k
    if k == "file":
        info["size"] = _os.size(p)
    else:
        info["size"] = null
    info["mtime"] = _attempt(_os.mtime, p)
    info["atime"] = _attempt(_os.atime, p)
    info["ctime"] = _attempt(_os.ctime, p)
    info["mode"] = _attempt(_os.permissions, p)
    return info

# Fichier : taille nulle. Dossier : aucune entrée. Autre : IoError.
func is_empty(p):
    _need_str("is_empty", p)
    if _os.isdir(p):
        return len(_os.list_dir(p)) == 0
    if _os.isfile(p):
        return _os.size(p) == 0
    raise("IoError", "filesystem.is_empty('" + p + "') : ni fichier ni dossier")

# Octets cumulés des fichiers réguliers sous `p` (liens symboliques ignorés, jamais suivis).
func tree_size(p):
    _need_str("tree_size", p)
    _need_present("tree_size", p)
    return _tree_size(p)

func _tree_size(p):
    if _os.islink(p):
        return 0
    if _os.isfile(p):
        return _os.size(p)
    if not _os.isdir(p):
        return 0
    total := 0
    for n in _os.list_dir(p):
        total += _tree_size(_os.join(p, n))
    return total

# ---------------------------------------------------------------------
# Lister
# ---------------------------------------------------------------------

# Entrées d'un dossier, triées par nom. full=true : chemins (join(p, nom)) au lieu des noms.
func list_dir(p, full=false):
    _need_str("list_dir", p)
    names := _os.list_dir(p)
    if not full:
        return names
    out := []
    for n in names:
        append(out, _os.join(p, n))
    return out

func _list_kind(fn, p, want_dir, full):
    _need_str(fn, p)
    out := []
    for n in _os.list_dir(p):
        c := _os.join(p, n)
        ok := false
        if want_dir:
            ok = _os.isdir(c)
        else:
            ok = _os.isfile(c)
        if ok:
            if full:
                append(out, c)
            else:
                append(out, n)
    return out

# Entrées qui sont (ou pointent vers) des fichiers réguliers.
func list_files(p, full=false):
    return _list_kind("list_files", p, false, full)

# Entrées qui sont (ou pointent vers) des dossiers.
func list_dirs(p, full=false):
    return _list_kind("list_dirs", p, true, full)

# Parcours descendant. Retourne une liste de [dossier, sous-dossiers, autres entrées] (noms, pas des chemins), le
# dossier racine en premier. Les liens vers des dossiers sont listés parmi les sous-dossiers mais ne sont
# descendus que si follow_links est vrai ; chaque dossier réel n'est alors visité qu'une fois (pas de cycle).
func walk(root, follow_links=false):
    _need_str("walk", root, "la racine")
    if not _os.isdir(root):
        raise("IoError", "filesystem.walk('" + root + "') : n'est pas un dossier")
    out := []
    _walk_into(root, follow_links, {}, out)
    return out

func _walk_into(dir, follow, seen, out):
    if follow:
        seen[_os.realpath(dir)] = true
    dirs := []
    others := []
    for n in _os.list_dir(dir):
        if _os.isdir(_os.join(dir, n)):
            append(dirs, n)
        else:
            append(others, n)
    append(out, [dir, dirs, others])
    for n in dirs:
        c := _os.join(dir, n)
        if _os.islink(c):
            if not follow:
                continue
            if contains_key(seen, _os.realpath(c)):
                continue
        _walk_into(c, follow, seen, out)

# Toutes les entrées sous `root` (root exclu), en profondeur, triées par nom dans chaque dossier.
#   pattern   : motif glob appliqué au NOM de l'entrée (path.glob_match), null = tout
#   kind      : null, "file", "dir", "symlink" ou "other" (voir kind_of)
#   max_depth : 1 = enfants directs ; null = illimité
func find(root, pattern=null, kind=null, max_depth=null):
    _need_str("find", root, "la racine")
    if pattern != null:
        _need_str("find", pattern, "le motif")
    _check_kind("find", kind)
    if max_depth != null and (type(max_depth) != "int" or max_depth < 1):
        raise("ValueError", "filesystem.find() : max_depth doit valoir null ou un entier >= 1")
    if not _os.isdir(root):
        raise("IoError", "filesystem.find('" + root + "') : n'est pas un dossier")
    out := []
    _find_rec(root, pattern, kind, max_depth, 1, out)
    return out

func _find_rec(dir, pattern, kind, max_depth, depth, out):
    for n in _os.list_dir(dir):
        c := _os.join(dir, n)
        if (pattern == null or _path.glob_match(pattern, n)) and _kind_ok(c, kind):
            append(out, c)
        if (max_depth == null or depth < max_depth) and _os.isdir(c) and not _os.islink(c):
            _find_rec(c, pattern, kind, max_depth, depth + 1, out)

# Motif glob par SEGMENTS séparés par "/" (aussi "\" sous Windows), relatif à `root` :
#   "*.al"            enfants directs dont le nom correspond
#   "src/*/main.al"   un niveau de dossier quelconque entre src et main.al
#   "**/test_*.al"    `**` = zéro ou plusieurs dossiers ; "**" seul = tout ce qui est en dessous
# Les chemins retournés commencent par root. Un segment explicite descend dans les liens vers des dossiers ;
# `**` n'en suit aucun. Résultat sans doublon, ordre déterministe (pas un tri global).
func glob(root, pattern, kind=null):
    _need_str("glob", root, "la racine")
    _need_str("glob", pattern, "le motif")
    _check_kind("glob", kind)
    if not _os.isdir(root):
        raise("IoError", "filesystem.glob('" + root + "') : n'est pas un dossier")
    text := pattern
    if _WIN:
        text = _s.replace(text, "\\", "/")
    segs := []
    for seg in _s.split(text, "/"):
        if seg == "":
            continue
        if seg == "**" and len(segs) > 0 and segs[len(segs) - 1] == "**":
            continue
        append(segs, seg)
    if len(segs) == 0:
        raise("ValueError", "filesystem.glob() : motif vide")
    out := []
    _glob_rec(root, segs, 0, kind, out)
    return out

func _glob_rec(dir, segs, i, kind, out):
    seg := segs[i]
    last := i == len(segs) - 1
    if seg == "**":
        if last:
            _glob_all(dir, kind, out)
            return null
        _glob_rec(dir, segs, i + 1, kind, out)
        for n in _os.list_dir(dir):
            c := _os.join(dir, n)
            if _os.isdir(c) and not _os.islink(c):
                _glob_rec(c, segs, i, kind, out)
        return null
    for n in _os.list_dir(dir):
        if not _path.glob_match(seg, n):
            continue
        c := _os.join(dir, n)
        if last:
            if _kind_ok(c, kind):
                append(out, c)
        elif _os.isdir(c):
            _glob_rec(c, segs, i + 1, kind, out)

func _glob_all(dir, kind, out):
    for n in _os.list_dir(dir):
        c := _os.join(dir, n)
        if _kind_ok(c, kind):
            append(out, c)
        if _os.isdir(c) and not _os.islink(c):
            _glob_all(c, kind, out)

# ---------------------------------------------------------------------
# Agir
# ---------------------------------------------------------------------

# mkdir -p. Ne fait rien si le dossier existe déjà ; IoError si le chemin existe et n'est pas un dossier.
# Retourne `p`.
func ensure_dir(p):
    _need_str("ensure_dir", p)
    _os.mkdir_all(p)
    return p

# Crée le dossier parent de `p` (et ses ancêtres). Utile avant d'écrire un fichier. Retourne `p`.
func ensure_parent(p):
    _need_str("ensure_parent", p)
    parent := _os.dirname(p)
    if parent != "":
        _os.mkdir_all(parent)
    return p

# Crée un fichier vide s'il n'existe pas (le dossier parent doit exister) ; un fichier existant n'est PAS modifié,
# pas même sa date (voir touch). La création est atomique : si un autre processus crée le fichier entre-temps, il
# est simplement conservé. Retourne `p`.
func ensure_file(p):
    _need_str("ensure_file", p)
    if _os.isdir(p):
        raise("IoError", "filesystem.ensure_file('" + p + "') : est un dossier")
    if not _os.exists(p):
        try:
            _io.create_file(p)
        catch e:
            if not _os.isfile(p):
                raise(e.type, e.message)
    return p

# Comme la commande `touch` : crée le fichier vide s'il n'existe pas (le dossier parent doit exister) ; sinon met
# ses dates de modification et d'accès à « maintenant ». Fonctionne aussi sur un dossier existant. Retourne `p`.
func touch(p):
    _need_str("touch", p)
    created := false
    if not _os.exists(p):
        try:
            _io.create_file(p)
            created = true
        catch e:
            if not _os.exists(p):
                raise(e.type, e.message)
    if not created:
        _os.set_times(p)
    return p

# Supprime un fichier ou un lien symbolique (jamais sa cible). Un dossier est refusé : voir remove_tree.
# Retourne true si quelque chose a été supprimé ; chemin absent : IoError, sauf missing_ok (retourne false).
func remove(p, missing_ok=false):
    _need_str("remove", p)
    if not _present(p):
        if missing_ok:
            return false
        raise("IoError", "filesystem.remove('" + p + "') : chemin introuvable")
    if _os.isdir(p) and not _os.islink(p):
        raise("IoError", "filesystem.remove('" + p + "') : est un dossier (utiliser remove_tree)")
    _os.remove(p)
    return true

# Supprime un fichier, un lien ou un dossier avec tout son contenu. IRRÉVERSIBLE. Refusée (ValueError) pour "",
# les chemins finissant par "." ou "..", la racine du disque, et tout dossier contenant le dossier courant ou le
# dossier personnel. Un lien symbolique est retiré sans toucher à sa cible. Retourne true si quelque chose a été
# supprimé (voir remove pour missing_ok).
func remove_tree(p, missing_ok=false):
    _need_str("remove_tree", p)
    _refuse_unsafe("remove_tree", p)
    if not _present(p):
        if missing_ok:
            return false
        raise("IoError", "filesystem.remove_tree('" + p + "') : chemin introuvable")
    if _os.islink(p) or not _os.isdir(p):
        _os.remove(p)
    else:
        _os.rmdir(p, true)
    return true

# Vide un dossier sans le supprimer (mêmes garde-fous que remove_tree). Retourne le nombre d'entrées retirées.
func clear_dir(p):
    _need_str("clear_dir", p)
    _refuse_unsafe("clear_dir", p)
    if not _os.isdir(p):
        raise("IoError", "filesystem.clear_dir('" + p + "') : n'est pas un dossier")
    removed := 0
    for n in _os.list_dir(p):
        c := _os.join(p, n)
        if _os.isdir(c) and not _os.islink(c):
            _os.rmdir(c, true)
        else:
            _os.remove(c)
        removed += 1
    return removed

# Chemin réellement visé par os.copy / os.move : `dst` lui-même, ou dst/nom-de-src si `dst` est un dossier.
func _target(src, dst):
    if _os.isdir(dst):
        return _os.join(dst, _os.basename(_os.absolute(src)))
    return dst

# Comme os.copy (fichier ou dossier, récursif ; dans `dst` si c'est un dossier existant) mais overwrite=false
# refuse (IoError) d'écraser quoi que ce soit. Retourne le chemin réellement écrit.
func copy(src, dst, overwrite=true):
    _need_str("copy", src, "la source")
    _need_str("copy", dst, "la destination")
    _need_present("copy", src)
    if not overwrite:
        target := _target(src, dst)
        if _present(target):
            raise("IoError", "filesystem.copy('" + src + "', '" + dst + "') : '" + target + "' existe déjà")
    return _os.copy(src, dst)

# Comme os.move (renomme, ou copie puis supprime entre volumes) avec le même garde-fou overwrite.
# Retourne le chemin final.
func move(src, dst, overwrite=true):
    _need_str("move", src, "la source")
    _need_str("move", dst, "la destination")
    _need_present("move", src)
    if not overwrite:
        target := _target(src, dst)
        if _present(target):
            raise("IoError", "filesystem.move('" + src + "', '" + dst + "') : '" + target + "' existe déjà")
    return _os.move(src, dst)

# ---------------------------------------------------------------------
# Dossiers temporaires
# ---------------------------------------------------------------------

# Crée un dossier neuf et vide : <parent>/<prefix><pid>_<horodatage>_<n>. La création est atomique (mkdir
# échoue si le nom existe : on réessaie avec un autre) donc deux processus n'obtiennent jamais le même dossier.
# parent = null : os.tmp_dir(). Droits 0700 quand l'OS les gère. Retourne le chemin ; à supprimer avec
# remove_tree (ou utiliser with_temp_dir).
func make_temp_dir(prefix="alex_", parent=null):
    _need_str("make_temp_dir", prefix, "le préfixe")
    base := parent
    if base == null:
        base = _os.tmp_dir()
    _need_str("make_temp_dir", base, "le dossier parent")
    attempts := 0
    while attempts < 100:
        _state["temp"] = _state["temp"] + 1
        name := prefix + str(_os.pid()) + "_" + str(to_int(_os.time() * 1000000)) + "_" + str(_state["temp"])
        candidate := _os.join(base, name)
        try:
            _os.mkdir(candidate)
        catch e:
            if _present(candidate):
                attempts += 1
                continue
            raise(e.type, e.message)
        _attempt_chmod(candidate)
        return candidate
    raise("IoError", "filesystem.make_temp_dir() : aucun nom libre trouvé sous '" + base + "'")

func _attempt_chmod(p):
    try:
        _os.chmod(p, 448)
    catch e:
        return false
    return true

func _cleanup_quiet(p):
    try:
        remove_tree(p, true)
    catch e:
        return false
    return true

# Crée un dossier temporaire, appelle fn(dossier) puis le supprime, que fn réussisse ou lève (l'exception est
# alors relancée à l'identique). Retourne la valeur de fn.
func with_temp_dir(fn, prefix="alex_", parent=null):
    d := make_temp_dir(prefix, parent)
    result := null
    try:
        result = fn(d)
    catch e:
        _cleanup_quiet(d)
        raise(e.type, e.message)
    remove_tree(d, true)
    return result

# Crée un fichier neuf et vide : <parent>/<prefix><pid>_<horodatage>_<n><suffix>. La création est EXCLUSIVE et
# atomique (le noyau refuse si le nom existe, un autre nom est alors essayé) : jamais de collision avec un autre
# processus ni suivi d'un lien symbolique posé à l'avance. parent = null : os.tmp_dir(). Droits 0600 quand l'OS les
# gère. Retourne le chemin ; à supprimer avec remove (ou utiliser with_temp_file).
func make_temp_file(prefix="alex_", suffix="", parent=null):
    _need_str("make_temp_file", prefix, "le préfixe")
    _need_str("make_temp_file", suffix, "le suffixe")
    base := parent
    if base == null:
        base = _os.tmp_dir()
    _need_str("make_temp_file", base, "le dossier parent")
    attempts := 0
    while attempts < 100:
        _state["temp"] = _state["temp"] + 1
        name := prefix + str(_os.pid()) + "_" + str(to_int(_os.time() * 1000000)) + "_" + str(_state["temp"]) + suffix
        candidate := _os.join(base, name)
        try:
            _io.create_file(candidate)
        catch e:
            if _present(candidate):
                attempts += 1
                continue
            raise(e.type, e.message)
        _attempt_chmod_private(candidate)
        return candidate
    raise("IoError", "filesystem.make_temp_file() : aucun nom libre trouvé sous '" + base + "'")

func _attempt_chmod_private(p):
    try:
        _os.chmod(p, 384)
    catch e:
        return false
    return true

# Crée un fichier temporaire, appelle fn(chemin) puis le supprime, que fn réussisse ou lève (l'exception est alors
# relancée à l'identique). Retourne la valeur de fn.
func with_temp_file(fn, prefix="alex_", suffix="", parent=null):
    p := make_temp_file(prefix, suffix, parent)
    result := null
    try:
        result = fn(p)
    catch e:
        remove(p, true)
        raise(e.type, e.message)
    remove(p, true)
    return result

