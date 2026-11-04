# ALEX STANDARD LIBRARY — filesystem.file
#
# Opérations sur des FICHIERS entiers (le contenu ligne à ligne est dans le module file) : copie avec
# politique d'écrasement et vérification, comparaison de contenu, empreintes, sauvegarde avec rotation,
# remplacement sûr, découpage, recherche de doublons.
#
#   use filesystem.file as ff
#   ff.copy("a.db", "sauvegarde/a.db", "if_newer")    # "always" | "never" | "if_newer" | "error"
#   print(ff.same_content("a.txt", "b.txt"))
#   print(ff.checksum("image.iso"))                   # sha256 en hexadécimal
#   ff.backup("config.toml", 3)                       # config.toml.1 .. .3 (rotation)
#   ff.replace("config.toml", nouveau_texte)          # écriture atomique + sauvegarde .bak
#   print(ff.duplicates(["a", "b", "c"]))             # groupes de fichiers au contenu identique
#   ff.split("gros.log", 1048576)                     # gros.log.part1, .part2...
#
# Erreurs : FileNotFoundError, FileExistsError (politique "error"), IsADirectoryError, IoError.

from core use len, type
from collections use append
use os as _os
use io as _io
use file as _file
use crypto as _crypto
use filesystem as _fs
use filesystem.filesystem_errors as _e
use filesystem.metadata as _md

const POLICIES := ["always", "never", "if_newer", "error"]

# Copie src vers dst selon la politique ; renvoie true si une copie a eu lieu.
func copy(src, dst, policy="always", verify=false):
    _e.need_file("file.copy", src)
    ok := false
    for p in POLICIES:
        if p == policy:
            ok = true
    if not ok:
        raise("ArgumentError", "file.copy : politique inconnue '" + str(policy) + "'")
    target := dst
    if _os.isdir(dst):
        target = _os.join(dst, _os.basename(src))
    if _os.exists(target):
        if policy == "never":
            return false
        if policy == "error":
            raise(_e.EXISTS, "file.copy : '" + target + "' existe déjà")
        if policy == "if_newer" and _os.mtime(src) <= _os.mtime(target):
            return false
    _fs.ensure_parent(target)
    _e.precise(() => _fs.copy(src, target, true))
    if verify and not same_content(src, target):
        raise("IoError", "file.copy : la copie de '" + src + "' diffère de l'original")
    return true

func move(src, dst, overwrite=false):
    _e.need_exists("file.move", src)
    if not overwrite and _os.exists(dst) and not _os.isdir(dst):
        raise(_e.EXISTS, "file.move : '" + dst + "' existe déjà")
    _e.precise(() => _fs.move(src, dst, true))

# Même contenu, octet pour octet (tailles comparées d'abord).
func same_content(a, b):
    _e.need_file("file.same_content", a)
    _e.need_file("file.same_content", b)
    if _os.size(a) != _os.size(b):
        return false
    return _io.read_file(a) == _io.read_file(b)

# Empreinte du contenu : "sha256" (défaut), "md5", "sha1", "sha512".
func checksum(path, algo="sha256"):
    _e.need_file("file.checksum", path)
    return _crypto.hash_hex(algo, _io.read_file(path))

func verify_checksum(path, expected, algo="sha256"):
    return checksum(path, algo) == expected

# Rotation : path.N-1 -> path.N, ..., path -> path.1 (copie). Renvoie le chemin de la sauvegarde.
func backup(path, keep=5):
    _e.need_file("file.backup", path)
    if keep < 1:
        raise("ArgumentError", "file.backup : keep >= 1 attendu")
    oldest := path + "." + str(keep)
    if _os.exists(oldest):
        _os.remove(oldest)
    i := keep - 1
    while i >= 1:
        p := path + "." + str(i)
        if _os.exists(p):
            _fs.move(p, path + "." + str(i + 1), true)
        i -= 1
    _fs.copy(path, path + ".1", true)
    return path + ".1"

func backups(path):
    out := []
    i := 1
    while _os.exists(path + "." + str(i)):
        append(out, path + "." + str(i))
        i += 1
    return out

# Remplace le contenu de façon atomique ; keep_backup : ancienne version gardée en path.bak.
func replace(path, text, keep_backup=true):
    if keep_backup and _os.exists(path):
        _fs.copy(path, path + ".bak", true)
    _file.write_atomic(path, text)

# Découpe en morceaux de chunk octets : path.part1, path.part2... ; renvoie leurs chemins.
func split(path, chunk):
    _e.need_file("file.split", path)
    data := _io.read_bytes(path)
    out := []
    i := 0
    k := 1
    while i < len(data):
        part := path + ".part" + str(k)
        _io.write_bytes(part, data[i:i + chunk])
        append(out, part)
        i += chunk
        k += 1
    return out

# Recolle des morceaux dans dst.
func join(parts, dst):
    first := true
    for p in parts:
        b := _io.read_bytes(p)
        if first:
            _io.write_bytes(dst, b)
            first = false
        else:
            _file.append_bytes(dst, b)
    return dst

# Groupes (listes) de fichiers au contenu identique, parmi paths (2 fichiers ou plus par groupe).
func duplicates(paths):
    by_size := {}
    for p in paths:
        if _os.isfile(p):
            s := _os.size(p)
            if not (s in by_size):
                by_size[s] = []
            append(by_size[s], p)
    out := []
    for s in by_size:
        group := by_size[s]
        if len(group) < 2:
            continue
        by_hash := {}
        for p in group:
            h := checksum(p)
            if not (h in by_hash):
                by_hash[h] = []
            append(by_hash[h], p)
        for h in by_hash:
            if len(by_hash[h]) > 1:
                append(out, by_hash[h])
    return out

func size(path):
    _e.need_file("file.size", path)
    return _os.size(path)

func human_size(path):
    return _md.format_size(size(path))

# Vide le fichier (taille 0), en le créant au besoin.
func truncate(path):
    _io.write_file(path, "")

func is_empty(path):
    return size(path) == 0

func extension_of(path):
    b := _os.basename(path)
    i := len(b) - 1
    while i > 0:
        if b[i] == '.':
            return b[i:]
        i -= 1
    return ""
