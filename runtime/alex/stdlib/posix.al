from collections use append
from core use len

func _cstr(s: str) -> int:
    p := __str_addr(s)
    n := __load64(p)
    c := __alloc_raw(n + 1)
    __copy(c, p + 8, n)
    __store8(c + n, 0)
    return c

func _from_c(c: int) -> str:
    n := 0
    while __load8(c + n) != 0:
        n += 1
    r := __rt_str_new(n)
    __copy(r + 8, c, n)
    return __as_str(r)

func _errno_text(e: int) -> str:
    if e == 8:
        return "Exec format error"
    if e == 1:
        return "Operation not permitted"
    if e == 3:
        return "No such process"
    if e == 10:
        return "No child processes"
    if e == 16:
        return "Device or resource busy"
    if e == 18:
        return "Invalid cross-device link"
    if e == 22:
        return "Invalid argument"
    if e == 30:
        return "Read-only file system"
    if e == 2:
        return "No such file or directory"
    if e == 13:
        return "Permission denied"
    if e == 17:
        return "File exists"
    if e == 20:
        return "Not a directory"
    if e == 21:
        return "Is a directory"
    if e == 28:
        return "No space left on device"
    if e == 39:
        return "Directory not empty"
    if e == 88:
        return "Socket operation on non-socket"
    if e == 97:
        return "Address family not supported by protocol"
    if e == 100:
        return "Network is down"
    if e == 104:
        return "Connection reset by peer"
    if e == 107:
        return "Transport endpoint is not connected"
    if e == 110:
        return "Connection timed out"
    if e == 111:
        return "Connection refused"
    if e == 113:
        return "No route to host"
    if e == 9:
        return "Bad file descriptor"
    if e == 11:
        return "Resource temporarily unavailable"
    if e == 12:
        return "Cannot allocate memory"
    if e == 14:
        return "Bad address"
    if e == 24:
        return "Too many open files"
    if e == 27:
        return "File too large"
    if e == 32:
        return "Broken pipe"
    if e == 38:
        return "Function not implemented"
    if e == 122:
        return "Disk quota exceeded"
    return "error " + str(e)

# stat : mode du fichier (st_mode), ou -1 s'il n'existe pas.
func _mode(path: str) -> int:
    st := __alloc_raw(144)
    if __syscall(4, _cstr(path), st) != 0:
        return -1
    return __load64(st + 24) & 4294967295

const WNOHANG := 1
const SIGINT := 2
const SIGKILL := 9
const SIGTERM := 15

_status: list[int] := [0]

func _check(r: int, what: str) -> int:
    if r < 0:
        raise("OSError", what + " : " + _errno_text(0 - r))
    return r

# Crée un processus enfant, copie du processus courant : renvoie 0 dans l'enfant, son numéro dans le parent.
# La sortie tamponnée de print est vidée avant (sinon elle serait écrite deux fois).
func fork() -> int:
    __flush()
    return _check(__syscall(57), "fork")

func _cvec(items: list[str]) -> int:
    v := __alloc_raw(8 * (len(items) + 1))
    i := 0
    for s in items:
        __store64(v + 8 * i, _cstr(s))
        i += 1
    __store64(v + 8 * i, 0)
    return v

func _environ() -> list[str]:
    sp := __argv_base()
    p := sp + 8 * (__load64(sp) + 2)
    out: list[str] := []
    while __load64(p) != 0:
        append(out, _from_c(__load64(p)))
        p += 8
    return out

# Remplace le programme courant par path ; argv contient aussi argv[0]. Ne revient qu'en cas d'erreur.
func execv(path: str, argv: list[str]):
    __flush()
    _check(__syscall(59, _cstr(path), _cvec(argv), _cvec(_environ())), "execve('" + path + "')")

func execve(path: str, argv: list[str], env: list[str]):
    __flush()
    _check(__syscall(59, _cstr(path), _cvec(argv), _cvec(env)), "execve('" + path + "')")

# Code de sortie à la manière d'un shell : 0..255, ou 128 + signal.
func _decode(st: int) -> int:
    if (st & 127) == 0:
        return (st >> 8) & 255
    return 128 + (st & 127)

# Attend la fin de l'enfant pid (-1 : n'importe lequel) ; renvoie son numéro (0 avec nohang s'il tourne encore).
# Son code de sortie est ensuite donné par status().
func waitpid(pid: int, nohang: bool = false) -> int:
    st := __alloc_raw(8)
    __store64(st, 0)
    opt := 0
    if nohang:
        opt = WNOHANG
    r := _check(__syscall(61, pid, st, opt, 0), "wait4")
    if r > 0:
        _status[0] = _decode(__load64(st) & 4294967295)
    return r

func wait() -> int:
    return waitpid(-1)

func status() -> int:
    return _status[0]

# Lance path (fork + execve) et renvoie le numéro de l'enfant ; 127 si le programme ne peut être exécuté.
func spawn(path: str, argv: list[str]) -> int:
    pid := fork()
    if pid == 0:
        r := __syscall(59, _cstr(path), _cvec(argv), _cvec(_environ()))
        __write_err(path + " : " + _errno_text(0 - r) + "\n")
        __exit(127)
    return pid

# Lance path et attend sa fin ; renvoie son code de sortie.
func run(path: str, argv: list[str]) -> int:
    pid := spawn(path, argv)
    waitpid(pid)
    return status()

# Tube : [lecture, écriture].
func pipe() -> list[int]:
    fds := __alloc_raw(8)
    _check(__syscall(22, fds), "pipe")
    v := __load64(fds)
    return [v & 4294967295, (v >> 32) & 4294967295]

func dup(fd: int) -> int:
    return _check(__syscall(32, fd), "dup")

func dup2(fd: int, target: int) -> int:
    __flush()
    return _check(__syscall(33, fd, target), "dup2")

func close(fd: int):
    if fd == 1 or fd == 2:
        __flush()
    _check(__syscall(3, fd), "close")

# Ouvre path : mode "r", "w" (création, troncature) ou "a" (ajout) ; renvoie le descripteur.
func open(path: str, mode: str = "r") -> int:
    flags := 0
    if mode == "w":
        flags = 577
    elif mode == "a":
        flags = 1089
    elif mode == "r+":
        flags = 2 # O_RDWR : lecture-écriture sans troncature (écriture à une position quelconque)
    return _check(__syscall(2, _cstr(path), flags, 420), "open('" + path + "')")

# Déplace la position de lecture/écriture de fd : whence 0 = depuis le début, 1 = depuis la position courante,
# 2 = depuis la fin. Renvoie la nouvelle position (octets depuis le début).
func lseek(fd: int, offset: int, whence: int = 0) -> int:
    return _check(__syscall(8, fd, offset, whence), "lseek")

# Lit au plus n octets ("" : fin de fichier).
func read(fd: int, n: int = 4096) -> str:
    buf := __alloc_raw(n)
    r := _check(__syscall(0, fd, buf, n), "read")
    out := __rt_str_new(r)
    __copy(out + 8, buf, r)
    return __as_str(out)

# Passe fd en mode non bloquant (O_NONBLOCK) : read_nb rend aussitôt "" quand rien n'est disponible.
func set_nonblock(fd: int):
    _check(__syscall(72, fd, 4, 2048), "fcntl")

_nb_eof: list[int] := [0]

# Lecture non bloquante : les octets disponibles (au plus n), "" s'il n'y en a pas pour l'instant ou à la fin du
# flux ; eof() distingue ces deux cas. À utiliser sur un descripteur passé par set_nonblock (tube, /dev/events).
func read_nb(fd: int, n: int = 4096) -> str:
    buf := __alloc_raw(n)
    r := __syscall(0, fd, buf, n)
    _nb_eof[0] = 0
    if r == 0:
        _nb_eof[0] = 1
        return ""
    if r < 0:
        if r == -11:
            return ""
        _check(r, "read")
    out := __rt_str_new(r)
    __copy(out + 8, buf, r)
    return __as_str(out)

# Vrai si le dernier read_nb a rencontré la fin du flux (l'autre extrémité est fermée).
func eof() -> bool:
    return _nb_eof[0] == 1

# Lit tout jusqu'à la fin de fichier.
# Tout le contenu restant : tampon agrandi par doublement puis une seule chaîne (temps linéaire, même pour un
# fichier de plusieurs Mio lu par petits morceaux).
func read_all(fd: int) -> str:
    cap := 65536
    buf := __alloc_raw(cap)
    used := 0
    while true:
        if used == cap:
            nb := __alloc_raw(cap * 2)
            __copy(nb, buf, used)
            buf = nb
            cap = cap * 2
        r := _check(__syscall(0, fd, buf + used, cap - used), "read")
        if r == 0:
            break
        used += r
    out := __rt_str_new(used)
    __copy(out + 8, buf, used)
    return __as_str(out)

func write(fd: int, s: str) -> int:
    __flush()
    p := __str_addr(s)
    n := __load64(p)
    done := 0
    while done < n:
        r := _check(__syscall(1, fd, p + 8 + done, n - done), "write")
        done += r
    return n

# Noms d'un répertoire (sans . ni ..), lus par getdents64.
func listdir(path: str) -> list[str]:
    fd := _check(__syscall(2, _cstr(path), 65536), "open('" + path + "')")
    buf := __alloc_raw(4096)
    out: list[str] := []
    while true:
        n := __syscall(217, fd, buf, 4096)
        if n <= 0:
            __syscall(3, fd)
            _check(n, "getdents64('" + path + "')")
            return out
        off := 0
        while off < n:
            reclen := __load8(buf + off + 16) + 256 * __load8(buf + off + 17)
            name := _from_c(buf + off + 19)
            if name != "." and name != "..":
                append(out, name)
            off += reclen

func getpid() -> int:
    return __syscall(39)

# Identifiant de l'utilisateur propriétaire du processus (réel) ; geteuid : effectif (droits, setuid).
func getuid() -> int:
    return __syscall(102)

func geteuid() -> int:
    return __syscall(107)

func getgid() -> int:
    return __syscall(104)

func getegid() -> int:
    return __syscall(108)

# Groupes supplémentaires du processus.
func getgroups() -> list[int]:
    n := __syscall(115, 0, 0)
    out: list[int] := []
    if n <= 0:
        return out
    buf := __alloc_raw(4 * n + 4)
    n = _check(__syscall(115, n, buf), "getgroups")
    i := 0
    while i < n:
        append(out, __load32(buf + 4 * i))
        i += 1
    return out

# Changement d'identité (programmes setuid : su, sudo, passwd). -1 : inchangé.
func setuid(uid: int):
    _check(__syscall(105, uid), "setuid")

func setgid(gid: int):
    _check(__syscall(106, gid), "setgid")

func setresuid(r: int, e: int, s: int):
    _check(__syscall(117, r, e, s), "setresuid")

func setresgid(r: int, e: int, s: int):
    _check(__syscall(119, r, e, s), "setresgid")

func seteuid(uid: int):
    setresuid(-1, uid, -1)

func setegid(gid: int):
    setresgid(-1, gid, -1)

# [réel, effectif, sauvegardé].
func getresuid() -> list[int]:
    b := __alloc_raw(12)
    _check(__syscall(118, b, b + 4, b + 8), "getresuid")
    return [__load32(b), __load32(b + 4), __load32(b + 8)]

func setgroups(gs: list[int]):
    buf := __alloc_raw(4 * len(gs) + 4)
    i := 0
    while i < len(gs):
        __store32(buf + 4 * i, gs[i])
        i += 1
    _check(__syscall(116, len(gs), buf), "setgroups")

# Masque des droits à la création des fichiers ; renvoie l'ancien.
func umask(mask: int) -> int:
    return __syscall(95, mask)

# Limites de ressources (RLIMIT_* : 0 CPU, 1 FSIZE, 6 NPROC, 7 NOFILE, 9 AS...) : [souple, dure], -1 = illimitée.
func getrlimit(resource: int) -> list[int]:
    buf := __alloc_raw(16)
    _check(__syscall(97, resource, buf), "getrlimit")
    return [__load64(buf), __load64(buf + 8)]

func setrlimit(resource: int, soft: int, hard: int):
    buf := __alloc_raw(16)
    __store64(buf, soft)
    __store64(buf + 8, hard)
    _check(__syscall(160, resource, buf), "setrlimit")

func chown(path: str, uid: int, gid: int):
    _check(__syscall(92, _cstr(path), uid, gid), "chown('" + path + "')")

# Vrai si l'utilisateur RÉEL a les droits mode (4 lecture, 2 écriture, 1 exécution, 0 existence) sur path.
func access(path: str, mode: int) -> bool:
    return __syscall(21, _cstr(path), mode) == 0

# Écho du terminal fd (saisie d'un mot de passe : set_echo(0, false), puis set_echo(0, true)).
func set_echo(fd: int, on: bool):
    t := __alloc_raw(64)
    _check(__syscall(16, fd, 21505, t), "ioctl(TCGETS)")
    lflag := __load32(t + 12)
    if on:
        lflag = lflag | 8
    else:
        lflag = lflag & ~8
    __store32(t + 12, lflag)
    _check(__syscall(16, fd, 21506, t), "ioctl(TCSETS)")

func getppid() -> int:
    return __syscall(110)

# Groupes de processus (travail par lots du shell) : placer un processus dans un groupe, lire un groupe.
func setpgid(pid: int, pgid: int):
    _check(__syscall(109, pid, pgid), "setpgid")

func getpgid(pid: int = 0) -> int:
    return _check(__syscall(121, pid), "getpgid")

func getpgrp() -> int:
    return __syscall(111)

# Sessions : nouvelle session dont l'appelant est le chef (démons : après un fork), session d'un processus.
func setsid() -> int:
    return _check(__syscall(112), "setsid")

func getsid(pid: int = 0) -> int:
    return _check(__syscall(124, pid), "getsid")

# Priorités (valeur nice, -20 le plus prioritaire .. 19 le moins) ; which : PRIO_PROCESS, PRIO_PGRP, PRIO_USER ;
# who : 0 pour l'appelant (son groupe, son utilisateur). Seul root rend un programme plus prioritaire.
const PRIO_PROCESS := 0
const PRIO_PGRP := 1
const PRIO_USER := 2

func getpriority(which: int = 0, who: int = 0) -> int:
    return 20 - _check(__syscall(140, which, who), "getpriority")

func setpriority(prio: int, which: int = 0, who: int = 0):
    _check(__syscall(141, which, who, prio), "setpriority")

# Ajoute inc à la valeur nice de l'appelant ; renvoie la nouvelle valeur.
func nice(inc: int) -> int:
    setpriority(getpriority() + inc)
    return getpriority()

func kill(pid: int, sig: int = 15):
    _check(__syscall(62, pid, sig), "kill")

func chdir(path: str):
    _check(__syscall(80, _cstr(path)), "chdir('" + path + "')")

func _sigaction(sig: int, handler: int):
    act := __alloc_raw(32)
    __zero(act, 32)
    __store64(act, handler)
    _check(__syscall(13, sig, act, 0, 8), "rt_sigaction")

# Ignore le signal sig (un shell ignore SIGINT : Ctrl+C n'arrête que le programme qu'il a lancé).
func ignore_signal(sig: int):
    _sigaction(sig, 1)

# Rétablit l'action par défaut de sig (terminer le processus) ; à faire dans l'enfant avant execve.
func default_signal(sig: int):
    _sigaction(sig, 0)

# Informations sur path : [mode, taille, date de modification (secondes Unix)] ; OSError s'il n'existe pas.
# Type dans mode & 61440 : 16384 répertoire, 32768 fichier, 8192 périphérique caractère, 4096 tube.
# [mode, taille, date de modification, uid, gid].
func stat(path: str) -> list[int]:
    st := __alloc_raw(144)
    _check(__syscall(4, _cstr(path), st), "stat('" + path + "')")
    return [__load64(st + 24) & 4294967295, __load64(st + 48), __load64(st + 88), __load32(st + 28), __load32(st + 32)]

func is_dir(path: str) -> bool:
    return _mode(path) >= 0 and (_mode(path) & 61440) == 16384

# Vrai si fd désigne un terminal (périphérique caractère) : affichage en colonnes, couleurs...
func isatty(fd: int) -> bool:
    st := __alloc_raw(144)
    if __syscall(5, fd, st) != 0:
        return false
    return (__load64(st + 24) & 61440) == 8192

func exists(path: str) -> bool:
    return _mode(path) >= 0

func rename(old: str, new: str):
    _check(__syscall(82, _cstr(old), _cstr(new)), "rename('" + old + "', '" + new + "')")

func unlink(path: str):
    _check(__syscall(87, _cstr(path)), "unlink('" + path + "')")

# Change les droits d'un fichier (mode octal, par exemple 0o644 ; sous Alex OS, seul le bit d'écriture 0o200 compte).
func chmod(path: str, mode: int):
    _check(__syscall(90, _cstr(path), mode), "chmod('" + path + "')")

func mkdir(path: str):
    _check(__syscall(83, _cstr(path), 493), "mkdir('" + path + "')")

func rmdir(path: str):
    _check(__syscall(84, _cstr(path)), "rmdir('" + path + "')")

# Attend ms millisecondes (nanosleep).
func sleep_ms(ms: int):
    ts := __alloc_raw(16)
    __store64(ts, ms // 1000)
    __store64(ts + 8, (ms % 1000) * 1000000)
    __syscall(35, ts, 0)

# Secondes Unix (time).
func time() -> int:
    return __syscall(201, 0)

# Millisecondes depuis le démarrage (horloge monotone).
func uptime_ms() -> int:
    ts := __alloc_raw(16)
    __syscall(228, 1, ts)
    return __load64(ts) * 1000 + __load64(ts + 8) // 1000000

# Environnement reçu par le programme (« NOM=valeur »).
func environ() -> list[str]:
    return _environ()

# Champs de uname : 0 système, 1 machine, 2 version, 3 description, 4 architecture.
func uname(field: int) -> str:
    buf := __alloc_raw(390)
    __syscall(63, buf)
    return _from_c(buf + 65 * field)

# Éteint (poweroff) ou redémarre (reboot) la machine : appel reboot de Linux (droits root sous Linux).
func poweroff():
    __flush()
    _check(__syscall(169, 4276215469, 672274793, 1126301404, 0), "reboot")

func reboot():
    __flush()
    _check(__syscall(169, 4276215469, 672274793, 19088743, 0), "reboot")

# Vide les caches de disque en écriture différée vers le support.
func sync():
    __flush()
    _check(__syscall(162), "sync")

# Ajoute un lien dur (newpath) vers un fichier existant (oldpath).
func link(oldpath: str, newpath: str):
    _check(__syscall(86, _cstr(oldpath), _cstr(newpath)), "link")

# Crée un lien symbolique (linkpath) de cible donnée (stockée telle quelle).
func symlink(target: str, linkpath: str):
    _check(__syscall(88, _cstr(target), _cstr(linkpath)), "symlink")

# Cible d'un lien symbolique.
func readlink(path: str) -> str:
    buf := __alloc_raw(4096)
    _check(__syscall(89, _cstr(path), buf, 4096), "readlink")
    return _from_c(buf)

# ---- réseau : sockets IPv4 (AF_INET), adresses en texte « a.b.c.d » ----
# Adresse IPv4 en texte -> entier ; -1 si invalide.
func _ip4(text: str) -> int:
    p := __str_addr(text)
    n := __load64(p)
    v := 0
    part := 0
    digits := 0
    dots := 0
    i := 0
    while i < n:
        c := __load8(p + 8 + i)
        if c == 46:
            if digits == 0 or part > 255:
                return -1
            v = (v << 8) | part
            part = 0
            digits = 0
            dots += 1
        elif c >= 48 and c <= 57:
            part = part * 10 + (c - 48)
            digits += 1
        else:
            return -1
        i += 1
    if dots != 3 or digits == 0 or part > 255:
        return -1
    return (v << 8) | part

func _ip4_text(v: int) -> str:
    return str((v >> 24) & 255) + "." + str((v >> 16) & 255) + "." + str((v >> 8) & 255) + "." + str(v & 255)

# sockaddr_in (16 octets) : famille AF_INET, port et adresse gros-boutistes.
func _sockaddr(ip: str, port: int) -> int:
    a := _ip4(ip)
    if a < 0:
        raise("OSError", "adresse IPv4 invalide : " + ip)
    sa := __alloc_raw(16)
    i := 0
    while i < 16:
        __store8(sa + i, 0)
        i += 1
    __store16(sa, 2)
    __store8(sa + 2, (port >> 8) & 255)
    __store8(sa + 3, port & 255)
    __store8(sa + 4, (a >> 24) & 255)
    __store8(sa + 5, (a >> 16) & 255)
    __store8(sa + 6, (a >> 8) & 255)
    __store8(sa + 7, a & 255)
    return sa

# Crée un socket : "tcp" (flux) ou "udp" (datagrammes) ; renvoie son descripteur.
func socket(kind: str = "tcp") -> int:
    t := 1
    if kind == "udp":
        t = 2
    return _check(__syscall(41, 2, t, 0), "socket")

# Connecte un socket (TCP : ouverture de connexion ; UDP : destinataire par défaut).
func connect(fd: int, ip: str, port: int):
    _check(__syscall(42, fd, _sockaddr(ip, port), 16), "connect " + ip + ":" + str(port))

# Lie un socket UDP à un port local.
func bind(fd: int, port: int):
    _check(__syscall(49, fd, _sockaddr("0.0.0.0", port), 16), "bind " + str(port))

# Envoie une chaîne sur un socket connecté ; renvoie le nombre d'octets.
func send(fd: int, s: str) -> int:
    p := __str_addr(s)
    return _check(__syscall(44, fd, p + 8, __load64(p), 0, 0), "send")

# Envoie un datagramme à ip:port.
func sendto(fd: int, s: str, ip: str, port: int) -> int:
    p := __str_addr(s)
    return _check(__syscall(44, fd, p + 8, __load64(p), 0, _sockaddr(ip, port), 16), "sendto " + ip + ":" + str(port))

# Reçoit au plus n octets ("" : fin de flux).
func recv(fd: int, n: int = 4096) -> str:
    buf := __alloc_raw(n)
    r := _check(__syscall(45, fd, buf, n, 0, 0), "recv")
    out := __rt_str_new(r)
    __copy(out + 8, buf, r)
    return __as_str(out)

# n octets aléatoires du système (getrandom : générateur cryptographique du noyau).
func random_bytes(n: int) -> str:
    out := __rt_str_new(n)
    got := 0
    while got < n:
        r := _check(__syscall(318, out + 8 + got, n - got, 0), "getrandom")
        got += r
    return __as_str(out)

# Met un socket TCP lié (bind) en écoute.
func listen(fd: int, backlog: int = 8):
    _check(__syscall(50, fd, backlog), "listen")

# Attend une connexion entrante ; renvoie le descripteur du socket connecté (adresse du pair : peer).
func accept(fd: int) -> int:
    return _check(__syscall(43, fd, 0, 0), "accept")

# Adresse du pair d'un socket connecté : [adresse, port].
func peer(fd: int) -> list[str]:
    sa := __alloc_raw(16)
    salen := __alloc_raw(8)
    __store64(salen, 16)
    _check(__syscall(52, fd, sa, salen), "getpeername")
    ip := (__load8(sa + 4) << 24) | (__load8(sa + 5) << 16) | (__load8(sa + 6) << 8) | __load8(sa + 7)
    return [_ip4_text(ip), str((__load8(sa + 2) << 8) | __load8(sa + 3))]

# Reçoit un datagramme : [données, adresse de l'expéditeur, port de l'expéditeur].
func recvfrom(fd: int, n: int = 4096) -> list[str]:
    buf := __alloc_raw(n)
    sa := __alloc_raw(16)
    salen := __alloc_raw(8)          # longueur de l'adresse (entrée-sortie), exigée par les systèmes standard
    __store64(salen, 16)
    r := _check(__syscall(45, fd, buf, n, 0, sa, salen), "recvfrom")
    out := __rt_str_new(r)
    __copy(out + 8, buf, r)
    ip := (__load8(sa + 4) << 24) | (__load8(sa + 5) << 16) | (__load8(sa + 6) << 8) | __load8(sa + 7)
    port := (__load8(sa + 2) << 8) | __load8(sa + 3)
    return [__as_str(out), _ip4_text(ip), str(port)]

func exit(code: int = 0):
    __flush()
    __exit(code & 255)
