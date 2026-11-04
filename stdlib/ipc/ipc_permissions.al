# ALEX STANDARD LIBRARY — ipc.ipc_permissions
#
# Droits d'accès des objets IPC nommés : où ils vivent dans le système de fichiers, qui les possède, quels
# droits ils portent, et les restreindre. Sous Linux :
#   mémoire partagée   /dev/shm/<nom>
#   sémaphore nommé    /dev/shm/sem.<nom>
#   file POSIX         /dev/mqueue/<nom>
#   socket local       chemin du fichier (ipc.local_socket.address) ; nom « @… » : abstrait, sans droits
#
#   use ipc.ipc_permissions as perm
#   p := perm.of("shm", "compteurs")           # Permissions(0600, uid, gid) ou null si absent
#   print(p.to_string(), p.owner_name())       # rw------- ada
#   perm.set_mode("shm", "compteurs", "0640") # ou perm.parse("rw-r-----"), ou l'entier 416
#   print(perm.can_access("mq", "travaux", "rw"))
#   perm.restrict_to_owner("socket", "service")
#
# Erreurs : IpcNotFoundError (objet absent), IpcPermissionError, ArgumentError (genre ou droits invalides).

from core use len, type, to_int
use string as _s
use os as _os
use _native_fd as _fd
use ipc.ipc_errors as _e
use ipc.local_socket as _ls

const KINDS := ["shm", "semaphore", "mq", "socket"]

func _need_kind(kind):
    for k in KINDS:
        if k == kind:
            return
    raise("ArgumentError", "ipc_permissions : genre inconnu '" + str(kind) + "' (shm, semaphore, mq, socket)")

func _strip(name):
    if _s.starts_with(name, "/"):
        return _s.substring(name, 1, len(name))
    return name

# Chemin du fichier qui représente l'objet (null : socket abstrait, ou plateforme sans ces dossiers).
func path_of(kind, name):
    _need_kind(kind)
    if kind == "socket":
        a := _ls.address(name)
        if _s.starts_with(a, "@"):
            return null
        return a
    if _os.platform() != "linux":
        return null
    if kind == "shm":
        return "/dev/shm/" + _strip(name)
    if kind == "semaphore":
        return "/dev/shm/sem." + _strip(name)
    return "/dev/mqueue/" + _strip(name)

func exists(kind, name):
    p := path_of(kind, name)
    return p != null and _os.exists(p)

# "0640", "640", "rw-r-----" -> entier.
func parse(text):
    t := _s.trim(text)
    if len(t) == 9 or len(t) == 10:
        if len(t) == 10:
            t = _s.substring(t, 1, 10)
        sym := 0
        i := 0
        for c in t:
            bit := 1 << (8 - i)
            if c != '-':
                sym = sym | bit
            i += 1
        return sym
    v := 0
    for c in t:
        if c < '0' or c > '7':
            raise("ArgumentError", "ipc_permissions.parse : droits invalides '" + text + "'")
        v = v * 8 + (to_int(str(c)))
    return v

func to_octal(mode):
    d := ""
    v := mode & 4095
    i := 0
    while i < 4:
        d = str(v % 8) + d
        v = v // 8
        i += 1
    return d

func to_symbolic(mode):
    out := ""
    letters := "rwxrwxrwx"
    i := 0
    while i < 9:
        if (mode & (1 << (8 - i))) != 0:
            out += str(letters[i])
        else:
            out += "-"
        i += 1
    return out

class Permissions:
    func init(mode, uid, gid, path):
        self.mode = mode & 4095
        self.uid = uid
        self.gid = gid
        self.path = path

    func to_string():
        return to_symbolic(self.mode)

    func octal():
        return to_octal(self.mode)

    func owner_name():
        try:
            return _fd.user_name(self.uid)
        catch e:
            return null

    func group_name():
        try:
            return _fd.group_name(self.gid)
        catch e:
            return null

    func owned_by_me():
        return self.uid == _os.user_id()

    # Droits ("r", "w", "rw") accordés à l'utilisateur courant ?
    func allows(rights):
        me := _os.user_id()
        if me == 0:
            return true
        shift := 0
        if self.uid == me:
            shift = 6
        elif self.gid == _os.group_id():
            shift = 3
        for c in rights:
            bit := 0
            if c == 'r':
                bit = 4
            elif c == 'w':
                bit = 2
            elif c == 'x':
                bit = 1
            if (self.mode & (bit << shift)) == 0:
                return false
        return true

    func world_accessible():
        return (self.mode & 7) != 0

    func __str__():
        return "Permissions(" + self.octal() + " " + self.to_string() + ", uid " + str(self.uid) + ")"

# Permissions de l'objet, ou null s'il n'existe pas (ou n'a pas de fichier).
func of(kind, name):
    p := path_of(kind, name)
    if p == null:
        return null
    st := _fd.stat(p)
    if st == null:
        return null
    return Permissions(st[0], st[1], st[2], p)

func _need(kind, name, fn):
    p := path_of(kind, name)
    if p == null or not _os.exists(p):
        raise(_e.NOT_FOUND, fn + " : objet " + kind + " '" + name + "' absent (ou sans fichier associé)")
    return p

func set_mode(kind, name, mode):
    p := _need(kind, name, "ipc_permissions.set_mode")
    m := mode
    if type(mode) == "str":
        m = parse(mode)
    try:
        _os.chmod(p, m)
    catch e:
        raise(_e.PERMISSION, "ipc_permissions.set_mode : " + e.message)

func restrict_to_owner(kind, name):
    p := of(kind, name)
    if p == null:
        _need(kind, name, "ipc_permissions.restrict_to_owner")
    keep := p.mode & 448
    if kind == "socket":
        keep = 384
    set_mode(kind, name, keep)

func share_with_group(kind, name, writable=true):
    p := of(kind, name)
    if p == null:
        _need(kind, name, "ipc_permissions.share_with_group")
    m := (p.mode & 448) | 32
    if writable:
        m = m | 16
    set_mode(kind, name, m)

func can_access(kind, name, rights="rw"):
    p := of(kind, name)
    if p == null:
        return false
    return p.allows(rights)
