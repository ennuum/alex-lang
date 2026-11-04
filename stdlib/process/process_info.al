# ALEX STANDARD LIBRARY — process.process_info
#
# Informations sur les processus de la machine (comme ps / top) : identité, parent, état, commande, mémoire,
# temps processeur, fils, arborescence. Source : /proc (Linux) ; ailleurs, `ps` s'il existe (informations
# réduites). Une information indisponible (processus d'un autre utilisateur, plateforme) vaut null.
#
#   use process.process_info as pinfo
#   me := pinfo.current()
#   print(me.pid, me.name, me.state_name(), pinfo.format_bytes(me.rss))
#   for p in pinfo.find("sshd"):
#       print(p.pid, p.cmdline)
#   print(pinfo.tree(1).render())                     # arborescence à partir de init
#   print(pinfo.cpu_percent(me.pid, 0.2))            # % d'un cœur sur 0,2 s
#
# Erreurs : ProcessError (processus absent pour get), TypeError.

from core use len, type, to_int
from collections use append, keys, contains_key, sort
use string as _s
use os as _os
use _native_fd as _fd
use _native_process as _np
use io as _io

const CLOCK_TICKS := 100   # USER_HZ de Linux (sysconf(_SC_CLK_TCK)) : unité des temps de /proc/<pid>/stat
const PAGE_SIZE := 4096

_states := {"R": "en cours", "S": "en sommeil", "D": "attente disque", "Z": "zombie", "T": "arrêté", "t": "tracé",
            "X": "mort", "I": "inactif", "W": "pagination", "P": "parqué", "K": "réveillable"}

func _read(path):
    try:
        return _io.read_file(path)
    catch e:
        return null

func supported():
    return _os.isdir("/proc/self")

func _is_digits(s):
    if s == "":
        return false
    for c in s:
        if c < '0' or c > '9':
            return false
    return true

func _int_or_null(s):
    try:
        return to_int(_s.trim(s))
    catch e:
        return null

# Valeur « Clé:  valeur kB » de /proc/<pid>/status.
func _status_fields(text):
    out := {}
    if text == null:
        return out
    for line in _s.split(text, "\n"):
        i := _s.find(line, ":")
        if i > 0:
            out[_s.substring(line, 0, i)] = _s.trim(_s.substring(line, i + 1, len(line)))
    return out

func _kb(v):
    if v == null:
        return null
    parts := _s.split(_s.trim(v), " ")
    n := _int_or_null(parts[0])
    if n == null:
        return null
    return n * 1024

class ProcessInfo:
    func init(pid):
        self.pid = pid
        self.ppid = null
        self.name = null
        self.state = null
        self.pgid = null
        self.session = null
        self.tty = null
        self.threads = null
        self.nice = null
        self.uid = null
        self.gid = null
        self.user = null
        self.rss = null           # mémoire résidente (octets)
        self.vms = null           # mémoire virtuelle (octets)
        self.user_time = null     # secondes de processeur en mode utilisateur
        self.system_time = null   # secondes en mode noyau
        self.start_ticks = null   # démarrage, en tics depuis le démarrage de la machine
        self.cmdline = []         # [programme, arguments...] ([] : noyau ou zombie)
        self.exe = null
        self.cwd = null

    func state_name():
        if self.state != null and contains_key(_states, self.state):
            return _states[self.state]
        return "inconnu"

    func cpu_time():
        if self.user_time == null:
            return null
        return self.user_time + self.system_time

    # Date de démarrage (secondes depuis 1970), si la machine la publie.
    func start_time():
        if self.start_ticks == null:
            return null
        bt := boot_time()
        if bt == null:
            return null
        return bt + self.start_ticks / CLOCK_TICKS

    # Âge du processus en secondes.
    func age():
        st := self.start_time()
        if st == null:
            return null
        return _os.time() - st

    func is_running():
        return exists(self.pid)

    func is_zombie():
        return self.state == "Z"

    # Ligne de commande affichable.
    func command():
        if len(self.cmdline) == 0:
            if self.name == null:
                return ""
            return "[" + self.name + "]"
        return _s.join(" ", self.cmdline)

    func children():
        return children(self.pid)

    func parent():
        if self.ppid == null or self.ppid == 0:
            return null
        return get_or_null(self.ppid)

    func to_dict():
        return {"pid": self.pid, "ppid": self.ppid, "name": self.name, "state": self.state, "threads": self.threads,
                "uid": self.uid, "user": self.user, "rss": self.rss, "vms": self.vms, "cpu_time": self.cpu_time(),
                "cmdline": self.cmdline, "exe": self.exe, "cwd": self.cwd}

func _parse_stat(info, text):
    # « pid (nom) état ppid ... » : le nom peut contenir espaces et parenthèses -> dernière « ) ».
    open := _s.find(text, "(")
    close := -1
    i := len(text) - 1
    while i >= 0:
        if text[i] == ')':
            close = i
            break
        i -= 1
    if open < 0 or close < 0:
        return false
    info.name = _s.substring(text, open + 1, close)
    rest := _s.split(_s.trim(_s.substring(text, close + 1, len(text))), " ")
    # rest[0] = état (champ 3), donc champ n = rest[n - 3]
    if len(rest) < 22:
        return false
    info.state = rest[0]
    info.ppid = _int_or_null(rest[1])
    info.pgid = _int_or_null(rest[2])
    info.session = _int_or_null(rest[3])
    info.tty = _int_or_null(rest[4])
    ut := _int_or_null(rest[11])
    stime := _int_or_null(rest[12])
    if ut != null and stime != null:
        info.user_time = ut / CLOCK_TICKS
        info.system_time = stime / CLOCK_TICKS
    info.nice = _int_or_null(rest[16])
    info.threads = _int_or_null(rest[17])
    info.start_ticks = _int_or_null(rest[19])
    info.vms = _int_or_null(rest[20])
    rss := _int_or_null(rest[21])
    if rss != null:
        info.rss = rss * PAGE_SIZE
    return true

func _user_name(uid):
    users := _load_users()
    if contains_key(users, uid):
        return users[uid]
    return null

func _load_users():
    if _users_cache[0] == null:
        m := {}
        text := _read("/etc/passwd")
        if text != null:
            for line in _s.split(text, "\n"):
                f := _s.split(line, ":")
                if len(f) >= 3:
                    u := _int_or_null(f[2])
                    if u != null:
                        m[u] = f[0]
        _users_cache[0] = m
    return _users_cache[0]

_users_cache := [null]

func _from_proc(pid):
    base := "/proc/" + str(pid)
    stat := _read(base + "/stat")
    if stat == null:
        return null
    info := ProcessInfo(pid)
    if not _parse_stat(info, stat):
        return null
    st := _status_fields(_read(base + "/status"))
    if contains_key(st, "Uid"):
        info.uid = _int_or_null(_s.split(_s.replace(st["Uid"], "\t", " "), " ")[0])
        if info.uid != null:
            info.user = _user_name(info.uid)
    if contains_key(st, "Gid"):
        info.gid = _int_or_null(_s.split(_s.replace(st["Gid"], "\t", " "), " ")[0])
    if contains_key(st, "VmRSS"):
        info.rss = _kb(st["VmRSS"])
    if contains_key(st, "Name") and info.name == null:
        info.name = st["Name"]
    cmd := _read(base + "/cmdline")
    if cmd != null and cmd != "":
        parts := _s.split(cmd, "\u0000")
        if len(parts) > 0 and parts[len(parts) - 1] == "":
            parts = [parts[k] for k in 0..(len(parts) - 1)]
        info.cmdline = parts
    info.exe = _fd.readlink(base + "/exe")
    info.cwd = _fd.readlink(base + "/cwd")
    return info

# Repli sans /proc : ps (macOS, BSD).
func _from_ps(pid):
    if not _np.supported():
        return null
    try:
        use_proc := _proc_run("ps", ["-o", "pid=,ppid=,uid=,rss=,vsz=,state=,comm=", "-p", str(pid)])
        if use_proc == null:
            return null
        f := [x for x in _s.split(_s.trim(use_proc), " ") if x != ""]
        if len(f) < 7:
            return null
        info := ProcessInfo(pid)
        info.ppid = _int_or_null(f[1])
        info.uid = _int_or_null(f[2])
        info.rss = _int_or_null(f[3]) * 1024
        info.vms = _int_or_null(f[4]) * 1024
        info.state = str(f[5][0])
        info.name = f[6]
        info.cmdline = [f[6]]
        return info
    catch e:
        return null

use process as _process

func _proc_run(prog, args):
    if _process.which(prog) == null:
        return null
    r := _process.run(prog, args, null, 5)
    if r.code != 0:
        return null
    return r.stdout

# Informations sur pid, ou null s'il n'existe pas.
func get_or_null(pid):
    if type(pid) != "int":
        raise("TypeError", "process_info : pid entier attendu (obtenu '" + type(pid) + "')")
    if supported():
        return _from_proc(pid)
    return _from_ps(pid)

# Informations sur pid ; ProcessError s'il n'existe pas.
func get(pid):
    p := get_or_null(pid)
    if p == null:
        raise("ProcessError", "process_info : aucun processus " + str(pid))
    return p

func current():
    return get(_os.pid())

func parent():
    return get_or_null(_os.parent_pid())

func exists(pid):
    if supported():
        return _os.isdir("/proc/" + str(pid))
    return _os.process_exists(pid)

# Numéros de tous les processus visibles, triés.
func pids():
    if supported():
        out := []
        for n in _os.list_dir("/proc"):
            if _is_digits(n):
                append(out, to_int(n))
        sort(out)
        return out
    text := _proc_run("ps", ["-A", "-o", "pid="])
    if text == null:
        return []
    out := []
    for line in _s.split(text, "\n"):
        v := _int_or_null(line)
        if v != null:
            append(out, v)
    sort(out)
    return out

# Tous les processus (ceux qui disparaissent pendant la lecture sont ignorés).
func list_processes():
    out := []
    for pid in pids():
        p := get_or_null(pid)
        if p != null:
            append(out, p)
    return out

# Processus dont le nom (ou le premier élément de la commande) vaut name ; contains=true : le contient.
func find(name, contains=false):
    out := []
    for p in list_processes():
        candidates := [p.name]
        if len(p.cmdline) > 0:
            base := p.cmdline[0]
            k := _s.find(base, "/")
            while k >= 0:
                base = _s.substring(base, k + 1, len(base))
                k = _s.find(base, "/")
            append(candidates, base)
        for c in candidates:
            if c == null:
                continue
            if c == name or (contains and _s.contains(c, name)):
                append(out, p)
                break
    return out

func children(pid):
    return [p for p in list_processes() if p.ppid == pid]

# Descendants (fils, petits-fils...) en largeur d'abord.
func descendants(pid):
    all := list_processes()
    by_parent := {}
    for p in all:
        if not contains_key(by_parent, p.ppid):
            by_parent[p.ppid] = []
        append(by_parent[p.ppid], p)
    out := []
    queue := [pid]
    i := 0
    while i < len(queue):
        cur := queue[i]
        i += 1
        if contains_key(by_parent, cur):
            for c in by_parent[cur]:
                append(out, c)
                append(queue, c.pid)
    return out

class ProcessTree:
    func init(info, children):
        self.info = info
        self.children = children

    func size():
        n := 1
        for c in self.children:
            n += c.size()
        return n

    func pids():
        out := [self.info.pid]
        for c in self.children:
            for p in c.pids():
                append(out, p)
        return out

    func render(indent=""):
        lines := [indent + str(self.info.pid) + " " + str(self.info.name)]
        for c in self.children:
            append(lines, c.render(indent + "  "))
        return _s.join("\n", lines)

# Arborescence des processus à partir de pid (null si pid n'existe pas).
func tree(pid):
    all := list_processes()
    by_pid := {}
    by_parent := {}
    for p in all:
        by_pid[p.pid] = p
        if not contains_key(by_parent, p.ppid):
            by_parent[p.ppid] = []
        append(by_parent[p.ppid], p)
    if not contains_key(by_pid, pid):
        return null
    return _build(by_pid[pid], by_parent, 0)

func _build(info, by_parent, depth):
    kids := []
    if depth < 256 and contains_key(by_parent, info.pid):
        for c in by_parent[info.pid]:
            if c.pid != info.pid:
                append(kids, _build(c, by_parent, depth + 1))
    return ProcessTree(info, kids)

# Démarrage de la machine (secondes depuis 1970), d'après /proc/stat.
func boot_time():
    text := _read("/proc/stat")
    if text == null:
        return null
    for line in _s.split(text, "\n"):
        if _s.starts_with(line, "btime "):
            return _int_or_null(_s.substring(line, 6, len(line)))
    return null

# Utilisation du processeur par pid pendant interval secondes, en % d'un cœur (null si indisponible).
func cpu_percent(pid, interval=0.5):
    a := get_or_null(pid)
    if a == null or a.cpu_time() == null:
        return null
    t0 := _os.monotonic_time()
    _os.sleep(interval)
    b := get_or_null(pid)
    if b == null:
        return null
    dt := _os.monotonic_time() - t0
    if dt <= 0:
        return null
    return 100.0 * (b.cpu_time() - a.cpu_time()) / dt

func format_bytes(n):
    if n == null:
        return "?"
    units := ["o", "Kio", "Mio", "Gio", "Tio"]
    v := n * 1.0
    u := 0
    while v >= 1024 and u < len(units) - 1:
        v = v / 1024
        u += 1
    if u == 0:
        return str(n) + " o"
    return str(_round1(v)) + " " + units[u]

func _round1(v):
    return to_int(v * 10 + 0.5) / 10
