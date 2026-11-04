# ALEX STANDARD LIBRARY — filesystem.filesystem_errors
#
# Erreurs du système de fichiers, PRÉCISES (les primitives lèvent IoError ; ce module en déduit le cas) :
#   FileNotFoundError     chemin absent
#   FileExistsError       création exclusive d'un chemin qui existe
#   NotADirectoryError    dossier attendu
#   IsADirectoryError     fichier attendu, dossier trouvé
#   PermissionError       droits insuffisants
#   DirectoryNotEmptyError  suppression d'un dossier non vide sans récursion
#   DiskFullError         plus de place (ENOSPC) ou quota
#   IoError               autre erreur système
#
#   use filesystem.filesystem_errors as fe
#   fe.need_file("charger", chemin)            # FileNotFoundError / IsADirectoryError
#   try:
#       ...
#   catch e:
#       print(fe.classify(e), fe.explain(fe.classify(e)))
#   fe.refine(e)                               # relance avec le type précis

from core use len
use string as _s
use os as _os

const NOT_FOUND := "FileNotFoundError"
const EXISTS := "FileExistsError"
const NOT_A_DIRECTORY := "NotADirectoryError"
const IS_A_DIRECTORY := "IsADirectoryError"
const PERMISSION := "PermissionError"
const NOT_EMPTY := "DirectoryNotEmptyError"
const DISK_FULL := "DiskFullError"
const IO := "IoError"

func kinds():
    return [NOT_FOUND, EXISTS, NOT_A_DIRECTORY, IS_A_DIRECTORY, PERMISSION, NOT_EMPTY, DISK_FULL, IO]

func is_filesystem_error(error_type):
    for k in kinds():
        if k == error_type:
            return true
    return false

# Chemin cité dans un message « fonction('chemin') : ... », ou null.
func _quoted_path(msg):
    i := _s.find(msg, "('")
    if i < 0:
        return null
    j := _s.find(_s.substring(msg, i + 2, len(msg)), "')")
    if j < 0:
        return null
    return _s.substring(msg, i + 2, i + 2 + j)

func _from_state(p):
    if p == null:
        return IO
    if _os.isdir(p):
        return IS_A_DIRECTORY
    if not _os.exists(p):
        parent := _os.dirname(p)
        if parent != "" and _os.exists(parent) and not _os.isdir(parent):
            return NOT_A_DIRECTORY
        if parent == "" or _os.exists(parent):
            if parent != "" and not _os.access(parent, "w"):
                return PERMISSION
        return NOT_FOUND
    if not _os.access(p, "r") or not _os.access(p, "w"):
        return PERMISSION
    return IO

# Type précis d'une erreur d'après son message (errno, textes du système) et, si besoin, l'état du chemin
# concerné (path, ou celui cité dans le message).
func classify(e, path=null):
    if e.type != IO:
        return e.type
    m := _s.lower(e.message)
    if _s.contains(m, "enoent") or _s.contains(m, "no such file") or _s.contains(m, "introuvable") or _s.contains(m, "n'existe pas"):
        return NOT_FOUND
    if _s.contains(m, "eexist") or _s.contains(m, "file exists") or _s.contains(m, "existe déjà"):
        return EXISTS
    if _s.contains(m, "enotdir") or _s.contains(m, "not a directory"):
        return NOT_A_DIRECTORY
    if _s.contains(m, "eisdir") or _s.contains(m, "is a directory"):
        return IS_A_DIRECTORY
    if _s.contains(m, "eacces") or _s.contains(m, "eperm") or _s.contains(m, "permission"):
        return PERMISSION
    if _s.contains(m, "enotempty") or _s.contains(m, "not empty"):
        return NOT_EMPTY
    if _s.contains(m, "enospc") or _s.contains(m, "no space") or _s.contains(m, "edquot"):
        return DISK_FULL
    p := path
    if p == null:
        p = _quoted_path(e.message)
    return _from_state(p)

func refine(e):
    t := classify(e)
    if t == e.type:
        raise(e)
    raise(t, e.message)

# Exécute f() en relançant les IoError avec leur type précis.
func precise(f):
    try:
        return f()
    catch IoError as e:
        refine(e)

func explain(error_type):
    if error_type == NOT_FOUND:
        return "le fichier ou le dossier n'existe pas"
    if error_type == EXISTS:
        return "le chemin existe déjà"
    if error_type == NOT_A_DIRECTORY:
        return "un dossier était attendu"
    if error_type == IS_A_DIRECTORY:
        return "un fichier était attendu, c'est un dossier"
    if error_type == PERMISSION:
        return "droits insuffisants (voir filesystem.permissions)"
    if error_type == NOT_EMPTY:
        return "le dossier n'est pas vide (suppression récursive nécessaire)"
    if error_type == DISK_FULL:
        return "plus de place sur le disque (ou quota atteint)"
    return "erreur d'entrée-sortie"

func need_exists(fn, p):
    if not _os.exists(p) and not _os.islink(p):
        raise(NOT_FOUND, fn + " : '" + p + "' n'existe pas")

func need_file(fn, p):
    need_exists(fn, p)
    if _os.isdir(p):
        raise(IS_A_DIRECTORY, fn + " : '" + p + "' est un dossier")

func need_dir(fn, p):
    need_exists(fn, p)
    if not _os.isdir(p):
        raise(NOT_A_DIRECTORY, fn + " : '" + p + "' n'est pas un dossier")

func need_absent(fn, p):
    if _os.exists(p) or _os.islink(p):
        raise(EXISTS, fn + " : '" + p + "' existe déjà")
