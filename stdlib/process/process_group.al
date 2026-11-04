# ALEX STANDARD LIBRARY — process.process_group
#
# Groupes de processus :
#   - ProcessGroup : un ensemble de fils lancés et pilotés ENSEMBLE (démarrer, attendre tous / le premier,
#     signaler, arrêter, bilan), chacun dans son propre groupe système pour que les signaux atteignent
#     aussi ses descendants ;
#   - fonctions système : groupe (pgid) et session d'un pid, signal à un groupe entier.
#
#   use process.process_group as pg
#   g := pg.ProcessGroup("workers")
#   g.add("a", "sleep", ["10"])
#   g.add("b", "sh", ["-c", "exit 3"])
#   g.start_all()
#   print(g.wait_any(5.0))                   # ["b", 3] : le premier terminé
#   g.stop_all()                             # TERM puis KILL des restants (et de leurs descendants)
#   print(g.summary())                       # {"a": -15, "b": 3}
#   print(pg.group_of(pid), pg.session_of(pid))
#
# Erreurs : ArgumentError (nom en double / inconnu), ProcessNotFoundError, PermissionError, IoError.

from core use len, type, to_int
from collections use append
use string as _s
use io as _io
use os as _os
use process as _p
use process.process_signal as _sig
use process.process_errors as _e

class _Member:
    func init(name, command):
        self.name = name
        self.command = command
        self.proc = null
        self.code = null
        self.started = null

class ProcessGroup:
    func init(name="groupe"):
        self.name = name
        self._members = []
        self._by_name = {}

    # Ajoute une commande (programme + arguments, ou process.Command).
    func add(name, program, args=null, cwd=null, env=null):
        if name in self._by_name:
            raise("ArgumentError", "ProcessGroup.add : nom '" + name + "' déjà utilisé")
        cmd := program
        if type(program) == "str":
            cmd = _p.Command(program, args)
            if cwd != null:
                cmd.cwd(cwd)
            if env != null:
                cmd.env(env)
        m := _Member(name, cmd)
        append(self._members, m)
        self._by_name[name] = m
        return self

    func _get(name):
        if not (name in self._by_name):
            raise("ArgumentError", "ProcessGroup : membre '" + name + "' inconnu")
        return self._by_name[name]

    func names():
        return [m.name for m in self._members]

    func start(name):
        m := self._get(name)
        if m.proc != null and m.code == null:
            return m.proc.pid()
        m.command.group()
        m.proc = m.command.spawn()
        m.code = null
        m.started = _os.monotonic_time()
        return m.proc.pid()

    func start_all():
        return [self.start(m.name) for m in self._members]

    func _refresh(m):
        if m.proc != null and m.code == null:
            c := m.proc.poll()
            if c != null:
                m.code = c

    func running():
        out := []
        for m in self._members:
            self._refresh(m)
            if m.proc != null and m.code == null:
                append(out, m.name)
        return out

    func pids():
        return {m.name: m.proc.pid() for m in self._members if m.proc != null}

    # Attend tous les membres (au plus timeout secondes au total) ; true si tous ont fini.
    func wait_all(timeout=null, interval=0.02):
        t0 := _os.monotonic_time()
        while len(self.running()) > 0:
            if timeout != null and _os.monotonic_time() - t0 >= timeout:
                return false
            _os.sleep(interval)
        return true

    # Attend le premier membre qui se termine : [nom, code], ou null après timeout.
    func wait_any(timeout=null, interval=0.02):
        t0 := _os.monotonic_time()
        while true:
            live := 0
            for m in self._members:
                if m.proc != null and m.code == null:
                    c := m.proc.poll()
                    if c != null:
                        m.code = c
                        return [m.name, c]
                    live += 1
            if live == 0:
                return null
            if timeout != null and _os.monotonic_time() - t0 >= timeout:
                return null
            _os.sleep(interval)

    # Signal à chaque membre actif, et à ses descendants (group=true).
    func signal_all(sig="TERM"):
        n := 0
        for m in self._members:
            self._refresh(m)
            if m.proc != null and m.code == null:
                m.proc.kill(sig, true)
                n += 1
        return n

    func stop(name, grace=3.0):
        m := self._get(name)
        if m.proc != null and m.code == null:
            m.code = m.proc.stop(grace, true)
        return m.code

    # TERM à tous, attente commune de grace secondes, puis KILL des restants.
    func stop_all(grace=3.0):
        self.signal_all("TERM")
        self.wait_all(grace)
        for m in self._members:
            if m.proc != null and m.code == null:
                m.code = m.proc.stop(0.5, true)
        return self.summary()

    # {nom: code de sortie ou null (en cours / jamais lancé)}.
    func summary():
        out := {}
        for m in self._members:
            self._refresh(m)
            out[m.name] = m.code
        return out

    func all_succeeded():
        for m in self._members:
            self._refresh(m)
            if m.code != 0:
                return false
        return true

    func failed():
        out := []
        for m in self._members:
            self._refresh(m)
            if m.code != null and m.code != 0:
                append(out, m.name)
        return out

    func output(name, stream="stdout"):
        m := self._get(name)
        if m.proc == null:
            return null
        return m.proc.read_all(stream)

    # Libère les handles (après la fin).
    func close():
        for m in self._members:
            if m.proc != null:
                if m.code == null:
                    m.code = m.proc.poll()
                m.proc.close()

    func size():
        return len(self._members)

# ---------------------------------------------------------------- informations système

func _stat_fields(pid):
    text := null
    try:
        text = _io.read_file("/proc/" + str(pid) + "/stat")
    catch e:
        _e.not_found("process_group", pid)
    k := len(text) - 1
    while k >= 0 and text[k] != ')':
        k -= 1
    return [x for x in _s.split(_s.trim(_s.substring(text, k + 1, len(text))), " ") if x != ""]

# Groupe de processus (pgid) de pid.
func group_of(pid=0):
    p := pid
    if p == 0:
        p = _os.pid()
    return to_int(_stat_fields(p)[2])

func session_of(pid=0):
    p := pid
    if p == 0:
        p = _os.pid()
    return to_int(_stat_fields(p)[3])

# pid est-il chef de son groupe ?
func is_group_leader(pid):
    return group_of(pid) == pid

# Pids visibles appartenant au groupe pgid.
func members_of(pgid):
    out := []
    if not _os.isdir("/proc/self"):
        return out
    for n in _os.list_dir("/proc"):
        ok := len(n) > 0
        for c in n:
            if c < '0' or c > '9':
                ok = false
        if ok:
            try:
                if to_int(_stat_fields(to_int(n))[2]) == pgid:
                    append(out, to_int(n))
            catch e:
                pass
    return out

func signal_group(pgid, sig="TERM"):
    _sig.send_group(pgid, sig)
