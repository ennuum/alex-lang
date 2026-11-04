# ALEX STANDARD LIBRARY — filesystem.permissions
#
# Droits des fichiers (POSIX) : lecture, notation symbolique et octale, modifications à la chmod
# (« u+x », « go-w », « a=r »), tests d'accès pour l'utilisateur courant, bits spéciaux.
#
#   use filesystem.permissions as perm
#   p := perm.of("script.sh")
#   print(p.octal(), p.symbolic())             # 0644 rw-r--r--
#   perm.chmod("script.sh", "u+x")             # 0744
#   perm.chmod("secret.txt", "go=")            # retire tout aux autres : 0600
#   perm.chmod("dossier", "0755")
#   print(perm.apply(perm.parse("0644"), "a+x"))   # 493 (0755) : calcul sans toucher au disque
#   print(perm.can_read("f"), perm.can_write("f"), perm.can_execute("f"))
#   print(perm.is_private("~/.ssh/id_ed25519"))   # aucun droit pour groupe et autres
#
# Erreurs : FileNotFoundError, PermissionError, ArgumentError (expression invalide).

from core use len, type, to_int
use string as _s
use os as _os
use _native_fd as _fd
use filesystem.filesystem_errors as _e

const SETUID := 2048
const SETGID := 1024
const STICKY := 512

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

# "0644", "644", "rw-r--r--" -> entier.
func parse(text):
    t := _s.trim(text)
    if len(t) == 9:
        m := 0
        i := 0
        for c in t:
            if c != '-':
                m = m | (1 << (8 - i))
            i += 1
        return m
    v := 0
    for c in t:
        if c < '0' or c > '7':
            raise("ArgumentError", "permissions.parse : droits invalides '" + text + "'")
        v = v * 8 + to_int(str(c))
    return v

func _who_mask(who):
    m := 0
    for c in who:
        if c == 'u':
            m = m | 448
        elif c == 'g':
            m = m | 56
        elif c == 'o':
            m = m | 7
        elif c == 'a':
            m = m | 511
        else:
            raise("ArgumentError", "permissions : destinataire '" + str(c) + "' inconnu (u, g, o, a)")
    if who == "":
        m = 511
    return m

func _rights(r):
    v := 0
    for c in r:
        if c == 'r':
            v = v | 292
        elif c == 'w':
            v = v | 146
        elif c == 'x':
            v = v | 73
        else:
            raise("ArgumentError", "permissions : droit '" + str(c) + "' inconnu (r, w, x)")
    return v

# Applique une expression chmod (« u+x », « go-w,a+r », « 0755 ») à mode ; renvoie le nouveau mode.
func apply(mode, expr):
    t := _s.trim(expr)
    if len(t) > 0 and t[0] >= '0' and t[0] <= '7':
        return (mode & (~4095)) | parse(t)
    m := mode
    for clause in _s.split(t, ","):
        c := _s.trim(clause)
        k := 0
        while k < len(c) and c[k] != '+' and c[k] != '-' and c[k] != '=':
            k += 1
        if k >= len(c):
            raise("ArgumentError", "permissions : opérateur +, - ou = manquant dans '" + c + "'")
        who := _s.substring(c, 0, k)
        op := c[k]
        bits := _rights(_s.substring(c, k + 1, len(c))) & _who_mask(who)
        if op == '+':
            m = m | bits
        elif op == '-':
            m = m & (~bits)
        else:
            m = (m & (~_who_mask(who))) | bits
    return m

class Permissions:
    func init(path, mode, uid, gid):
        self.path = path
        self.mode = mode & 4095
        self.uid = uid
        self.gid = gid

    func octal():
        return to_octal(self.mode)

    func symbolic():
        return to_symbolic(self.mode)

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

    func is_setuid():
        return (self.mode & SETUID) != 0

    func is_setgid():
        return (self.mode & SETGID) != 0

    func is_sticky():
        return (self.mode & STICKY) != 0

    func world_writable():
        return (self.mode & 2) != 0

    func __str__():
        return self.octal() + " " + self.symbolic() + " " + str(self.owner())

func of(path):
    _e.need_exists("permissions.of", path)
    st := _fd.stat(path)
    if st == null:
        raise(_e.NOT_FOUND, "permissions.of : '" + path + "' illisible")
    return Permissions(path, st[0], st[1], st[2])

func mode(path):
    return of(path).mode

# chmod avec expression symbolique ou octale ; renvoie le nouveau mode.
func chmod(path, expr):
    old := of(path).mode
    new := expr
    if type(expr) == "str":
        new = apply(old, expr)
    try:
        _os.chmod(path, new & 4095)
    catch e:
        raise(_e.PERMISSION, "permissions.chmod : " + e.message)
    return new & 4095

func make_executable(path):
    return chmod(path, "u+x")

func make_private(path):
    return chmod(path, "go=")

func make_readonly(path):
    return chmod(path, "a-w")

func can_read(path):
    return _os.access(path, "r")

func can_write(path):
    return _os.access(path, "w")

func can_execute(path):
    return _os.access(path, "x")

# Aucun droit pour le groupe ni les autres.
func is_private(path):
    return (of(path).mode & 63) == 0

func copy_mode(src, dst):
    _os.chmod(dst, of(src).mode)
