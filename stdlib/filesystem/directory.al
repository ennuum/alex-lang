# ALEX STANDARD LIBRARY — filesystem.directory
#
# Directory : un dossier comme OBJET — contenu, recherche, taille, copie, synchronisation (miroir), et
# comparaison de deux arborescences.
#
#   use filesystem.directory as dirs
#   d := dirs.Directory("projet")
#   print(d.files(), d.subdirs(), d.count())           # entrées directes
#   for p in d.find("*.al"):                           # récursif
#       print(p)
#   print(d.human_size(), d.is_empty())
#   d.copy_to("sauvegarde/projet")                     # copie complète
#   r := d.sync_to("miroir")                           # ne copie que le nouveau / le modifié
#   print(r["copied"], r["deleted"])                   # delete_extra=true : retire ce qui n'existe plus
#   print(dirs.compare("a", "b"))                      # {"only_left", "only_right", "different", "same"}
#
# Erreurs : NotADirectoryError, FileNotFoundError, DirectoryNotEmptyError, IoError.

from core use len, type
from collections use append
use os as _os
use path as _p
use filesystem as _fs
use filesystem.filesystem_errors as _e
use filesystem.metadata as _md
use filesystem.file as _ff

class Directory:
    func init(path):
        if type(path) != "str":
            path = str(path)
        self.path = path

    func exists():
        return _os.isdir(self.path)

    func _need(fn):
        _e.need_dir("Directory." + fn, self.path)

    func create():
        _fs.ensure_dir(self.path)
        return self

    func entries(full=false):
        self._need("entries")
        return _fs.list_dir(self.path, full)

    func files(full=false):
        self._need("files")
        return _fs.list_files(self.path, full)

    func subdirs(full=false):
        self._need("subdirs")
        return _fs.list_dirs(self.path, full)

    func count():
        return len(self.entries())

    func is_empty():
        self._need("is_empty")
        return len(_os.list_dir(self.path)) == 0

    # Chemins (récursifs) dont le nom correspond au motif ; kind : "file", "dir" ou null.
    func find(pattern=null, kind=null, max_depth=null):
        self._need("find")
        return _fs.find(self.path, pattern, kind, max_depth)

    func glob(pattern):
        self._need("glob")
        return _fs.glob(self.path, pattern)

    func walk():
        self._need("walk")
        return _fs.walk(self.path)

    # Taille cumulée des fichiers (octets).
    func size():
        self._need("size")
        return _fs.tree_size(self.path)

    func human_size():
        return _md.format_size(self.size())

    # Fichiers les plus gros : [[chemin, taille], ...].
    func largest(n=10):
        files := [[f, _os.size(f)] for f in self.find(null, "file")]
        i := 1
        while i < len(files):
            v := files[i]
            j := i - 1
            while j >= 0 and files[j][1] < v[1]:
                files[j + 1] = files[j]
                j -= 1
            files[j + 1] = v
            i += 1
        return files[:n]

    func child(name):
        return Directory(_os.join(self.path, name))

    func file_path(name):
        return _os.join(self.path, name)

    func clear():
        self._need("clear")
        _fs.clear_dir(self.path)

    # Supprime ; recursive=false : seulement si vide.
    func remove(recursive=false):
        self._need("remove")
        if recursive:
            _fs.remove_tree(self.path)
        else:
            if not self.is_empty():
                raise(_e.NOT_EMPTY, "Directory.remove : '" + self.path + "' n'est pas vide")
            _os.rmdir(self.path)

    func copy_to(target):
        self._need("copy_to")
        _fs.copy(self.path, target, true)
        return Directory(target)

    # Miroir : copie vers target ce qui manque ou a changé (taille ou date) ; delete_extra : supprime de
    # target ce qui n'existe plus ici. Renvoie {"copied", "skipped", "deleted"}.
    func sync_to(target, delete_extra=false):
        self._need("sync_to")
        _fs.ensure_dir(target)
        copied := []
        skipped := 0
        for f in self.find(null, "file"):
            rel := _p.relative_to(f, self.path)
            dst := _os.join(target, rel)
            if _os.isfile(dst) and _os.size(dst) == _os.size(f) and _os.mtime(dst) >= _os.mtime(f):
                skipped += 1
                continue
            _fs.ensure_parent(dst)
            _fs.copy(f, dst, true)
            append(copied, rel)
        deleted := []
        if delete_extra:
            for f in _fs.find(target, null, "file"):
                rel := _p.relative_to(f, target)
                if not _os.exists(_os.join(self.path, rel)):
                    _os.remove(f)
                    append(deleted, rel)
        return {"copied": copied, "skipped": skipped, "deleted": deleted}

    func __str__():
        return "Directory(" + self.path + ")"

func _rel_files(root):
    out := {}
    for f in _fs.find(root, null, "file"):
        out[_p.relative_to(f, root)] = f
    return out

# Compare deux arborescences : fichiers seulement à gauche / à droite, de contenu différent, identiques.
func compare(left, right):
    _e.need_dir("directory.compare", left)
    _e.need_dir("directory.compare", right)
    a := _rel_files(left)
    b := _rel_files(right)
    only_l := []
    only_r := []
    diff := []
    same := []
    for k in a:
        if not (k in b):
            append(only_l, k)
        elif _ff.same_content(a[k], b[k]):
            append(same, k)
        else:
            append(diff, k)
    for k in b:
        if not (k in a):
            append(only_r, k)
    return {"only_left": only_l, "only_right": only_r, "different": diff, "same": same}

func identical(left, right):
    c := compare(left, right)
    return len(c["only_left"]) == 0 and len(c["only_right"]) == 0 and len(c["different"]) == 0

func directory(path):
    return Directory(path)

func temp(prefix="alex_"):
    return Directory(_fs.make_temp_dir(prefix))
