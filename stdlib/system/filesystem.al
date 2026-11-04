# ALEX STANDARD LIBRARY — system.filesystem
#
# Le module `filesystem` (docs/PURE_MODULES.md) sous le nom system.filesystem — tests (exists, is_file...),
# parcours (list_dir, walk, find, glob), création et suppression (ensure_dir, remove_tree...), copie,
# fichiers et dossiers temporaires — complété des opérations de `os` sur les chemins : mkdir, rmdir, cwd,
# chdir, size, realpath, absolute, permissions, chmod, et de disk_usage(chemin).

use filesystem as _fs


kind_of := _fs.kind_of
exists := _fs.exists
is_file := _fs.is_file
is_dir := _fs.is_dir
is_link := _fs.is_link
is_readable := _fs.is_readable
is_writable := _fs.is_writable
is_executable := _fs.is_executable
same_file := _fs.same_file
is_inside := _fs.is_inside
stat := _fs.stat
is_empty := _fs.is_empty
tree_size := _fs.tree_size
list_dir := _fs.list_dir
list_files := _fs.list_files
list_dirs := _fs.list_dirs
walk := _fs.walk
find := _fs.find
glob := _fs.glob
ensure_dir := _fs.ensure_dir
ensure_parent := _fs.ensure_parent
ensure_file := _fs.ensure_file
touch := _fs.touch
remove := _fs.remove
remove_tree := _fs.remove_tree
clear_dir := _fs.clear_dir
copy := _fs.copy
move := _fs.move
make_temp_dir := _fs.make_temp_dir
with_temp_dir := _fs.with_temp_dir
make_temp_file := _fs.make_temp_file
with_temp_file := _fs.with_temp_file

use os as _os
use _native_os as _osn

mkdir := _os.mkdir
mkdir_all := _os.mkdir_all
rmdir := _os.rmdir
cwd := _os.cwd
chdir := _os.chdir
size := _os.size
realpath := _os.realpath
absolute := _os.absolute
permissions := _os.permissions
chmod := _os.chmod
mtime := _os.mtime

# Espace du système de fichiers qui contient path : {"total", "used", "free", "available"} en octets
# (available : ce qu'un utilisateur ordinaire peut encore écrire).
func disk_usage(path="/"):
    if not _os.exists(path):
        raise("IoError", "disk_usage : '" + str(path) + "' n'existe pas")
    r := _osn.disk_usage(path)
    if r == null:
        raise("IoError", "disk_usage : information indisponible pour '" + str(path) + "'")
    return {"total": r[0], "used": r[0] - r[1], "free": r[1], "available": r[2]}
