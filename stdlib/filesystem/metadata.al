# ALEX STANDARD LIBRARY — filesystem.metadata
#
# Métadonnées d'un chemin, en un objet : genre (fichier, dossier, lien, tube, socket, périphérique), taille,
# droits, propriétaire, dates (modification, accès, changement d'état), inode et périphérique (identité du
# fichier : deux chemins désignent le même fichier si (device, inode) sont égaux).
#
#   use filesystem.metadata as md
#   m := md.of("rapport.pdf")
#   print(m.kind, m.size, m.human_size())          # file 482113 470.8 Kio
#   print(m.owner(), m.mode_text(), m.age())        # ada rw-r--r-- 3600.2 (secondes depuis la modification)
#   print(m.is_newer_than(md.of("rapport.tex")))
#   l := md.of("lien", false)                       # le lien lui-même (lstat)
#   print(l.is_link, md.same_file("a", "b"))
#
# Erreurs : FileNotFoundError.

from core use len, type, to_int
use os as _os
use _native_fd as _fd
use filesystem.filesystem_errors as _e
use filesystem.permissions as _perm

const _S_IFMT := 61440

func _kind(mode):
    t := mode & _S_IFMT
    if t == 32768:
        return "file"
    if t == 16384:
        return "dir"
    if t == 40960:
        return "link"
    if t == 4096:
        return "fifo"
    if t == 49152:
        return "socket"
    if t == 8192:
        return "char_device"
    if t == 24576:
        return "block_device"
    return "unknown"

class Metadata:
    func init(path, st, follow):
        self.path = path
        self.mode = st[0]
        self.uid = st[1]
        self.gid = st[2]
        self.rdev_major = st[3]
        self.rdev_minor = st[4]
        self.size = st[5]
        self.inode = st[6]
        self.device = st[7] * 256 + st[8]
        self.kind = _kind(st[0])
        self.is_link = self.kind == "link"
        self.followed = follow
        self.mtime = _try(() => _os.mtime(path))
        self.atime = _try(() => _os.atime(path))
        self.ctime = _try(() => _os.ctime(path))

    func is_file():
        return self.kind == "file"

    func is_dir():
        return self.kind == "dir"

    func is_special():
        return self.kind == "fifo" or self.kind == "socket" or self.kind == "char_device" or self.kind == "block_device"

    func permissions():
        return self.mode & 4095

    func mode_text():
        return _perm.to_symbolic(self.mode)

    func owner():
        try:
            return _fd.user_name(self.uid)
        catch e:
            return null

    func group():
        try:
            return _fd.group_name(self.gid)
        catch e:
            return null

    # Secondes écoulées depuis la dernière modification.
    func age():
        if self.mtime == null:
            return null
        return _os.time() - self.mtime

    func is_newer_than(other):
        return self.mtime != null and other.mtime != null and self.mtime > other.mtime

    func identity():
        return [self.device, self.inode]

    func human_size():
        return format_size(self.size)

    func to_dict():
        return {"path": self.path, "kind": self.kind, "size": self.size, "mode": self.permissions(), "uid": self.uid,
                "gid": self.gid, "mtime": self.mtime, "atime": self.atime, "ctime": self.ctime, "inode": self.inode,
                "device": self.device}

    func __str__():
        return self.mode_text() + " " + str(self.owner()) + " " + _pad(self.human_size(), 10) + " " + self.path

func _pad(s, n):
    out := s
    while len(out) < n:
        out = " " + out
    return out

func _try(f):
    try:
        return f()
    catch e:
        return null

# Métadonnées de path ; follow=false : celles du lien lui-même.
func of(path, follow=true):
    st := _fd.stat(path, follow)
    if st == null:
        raise(_e.NOT_FOUND, "metadata.of : '" + str(path) + "' n'existe pas")
    return Metadata(path, st, follow)

func of_or_null(path, follow=true):
    st := _fd.stat(path, follow)
    if st == null:
        return null
    return Metadata(path, st, follow)

func same_file(a, b):
    ma := of_or_null(a)
    mb := of_or_null(b)
    return ma != null and mb != null and ma.identity() == mb.identity()

func kind(path):
    m := of_or_null(path, false)
    if m == null:
        return null
    return m.kind

func format_size(n):
    if n == null:
        return "?"
    units := ["o", "Kio", "Mio", "Gio", "Tio"]
    x := n * 1.0
    u := 0
    while x >= 1024 and u < len(units) - 1:
        x = x / 1024
        u += 1
    if u == 0:
        return str(n) + " o"
    return str(to_int(x * 10 + 0.5) / 10) + " " + units[u]
