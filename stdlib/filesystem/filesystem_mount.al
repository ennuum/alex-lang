# ALEX STANDARD LIBRARY — filesystem.filesystem_mount
#
# Points de montage : quels systèmes de fichiers sont montés, où, avec quel type et quelles options ; sur
# quel montage se trouve un chemin ; espace disque de chacun.
#
#   use filesystem.filesystem_mount as fm
#   for m in fm.mounts():
#       print(m.mount_point, m.fs_type, m.device, m.is_readonly())
#   m := fm.mount_of("/home/ada/notes.txt")       # montage qui contient le chemin
#   print(m.mount_point, m.usage()["available"])
#   print(fm.is_network("/mnt/partage"), fm.is_virtual("/proc"))
#   print(fm.same_mount("/tmp/a", "/home/b"))      # un rename() est-il possible sans copie ?
#
# Source : /proc/self/mounts (Linux) ; ailleurs mounts() rend une liste vide et mount_of un montage « / ».
# Erreurs : FileNotFoundError (chemin absent pour mount_of), IoError (usage indisponible).

from core use len, type
from collections use append
use string as _s
use io as _io
use os as _os
use path as _p
use system.filesystem as _sysfs

const VIRTUAL := ["proc", "sysfs", "devtmpfs", "devpts", "tmpfs", "cgroup", "cgroup2", "securityfs", "debugfs",
                  "tracefs", "pstore", "bpf", "mqueue", "hugetlbfs", "configfs", "fusectl", "autofs", "binfmt_misc",
                  "overlay", "nsfs", "efivarfs", "ramfs", "rpc_pipefs"]
const NETWORK := ["nfs", "nfs4", "cifs", "smb3", "smbfs", "sshfs", "fuse.sshfs", "afs", "9p", "ceph", "glusterfs"]

func _unescape(s):
    # /proc/mounts code les espaces en \040, les tabulations en \011.
    return _s.replace(_s.replace(_s.replace(s, "\\040", " "), "\\011", "\t"), "\\134", "\\")

class Mount:
    func init(device, mount_point, fs_type, options):
        self.device = device
        self.mount_point = mount_point
        self.fs_type = fs_type
        self.options = options

    func has_option(name):
        for o in self.options:
            if o == name or _s.starts_with(o, name + "="):
                return true
        return false

    func is_readonly():
        return self.has_option("ro")

    func is_virtual():
        for v in VIRTUAL:
            if v == self.fs_type:
                return true
        return false

    func is_network():
        for v in NETWORK:
            if v == self.fs_type:
                return true
        return false

    # {"total", "used", "free", "available"} en octets.
    func usage():
        return _sysfs.disk_usage(self.mount_point)

    func __str__():
        return self.device + " on " + self.mount_point + " type " + self.fs_type + " (" + _s.join(",", self.options) + ")"

func parse_mounts(text):
    out := []
    for line in _s.split(text, "\n"):
        f := [x for x in _s.split(_s.trim(line), " ") if x != ""]
        if len(f) < 4:
            continue
        append(out, Mount(_unescape(f[0]), _unescape(f[1]), f[2], _s.split(f[3], ",")))
    return out

func mounts(include_virtual=true):
    text := null
    try:
        text = _io.read_file("/proc/self/mounts")
    catch e:
        return []
    ms := parse_mounts(text)
    if include_virtual:
        return ms
    return [m for m in ms if not m.is_virtual()]

# Montage qui contient path (le point de montage le plus long qui le préfixe).
func mount_of(path):
    if not _os.exists(path):
        raise("FileNotFoundError", "filesystem_mount.mount_of : '" + path + "' n'existe pas")
    real := _os.realpath(path)
    best := null
    for m in mounts():
        mp := m.mount_point
        if real == mp or mp == "/" or _p.is_subpath(real, mp):
            if best == null or len(mp) >= len(best.mount_point):
                best = m
    if best == null:
        return Mount("?", "/", "unknown", [])
    return best

func mount_point_of(path):
    return mount_of(path).mount_point

func is_mount_point(path):
    real := _os.realpath(path)
    for m in mounts():
        if m.mount_point == real:
            return true
    return false

func same_mount(a, b):
    return mount_of(a).mount_point == mount_of(b).mount_point

func is_network(path):
    return mount_of(path).is_network()

func is_virtual(path):
    return mount_of(path).is_virtual()

func is_readonly(path):
    return mount_of(path).is_readonly()

func fs_type(path):
    return mount_of(path).fs_type

# Types de systèmes de fichiers montés (sans doublon).
func fs_types():
    seen := {}
    out := []
    for m in mounts():
        if not (m.fs_type in seen):
            seen[m.fs_type] = true
            append(out, m.fs_type)
    return out
