# ALEX STANDARD LIBRARY — process.process_signal
#
# Envoyer des signaux à des PROCESSUS (par pid), avec les gestes usuels : terminer proprement, tuer,
# suspendre, reprendre, interrompre — et attendre la disparition du processus.
#
#   use process.process_signal as psig
#   psig.terminate(pid)                        # TERM
#   if not psig.wait_exit(pid, 2.0):
#       psig.kill(pid)                         # KILL après 2 s
#   psig.shutdown(pid, 3.0)                    # TERM, attente, puis KILL : true si le processus a disparu
#   psig.suspend(pid)                          # STOP
#   psig.resume(pid)                           # CONT
#   psig.send_group(pgid, "HUP")               # tout un groupe (killpg)
#   print(psig.can_signal(pid))                # existe et on a le droit de le signaler
#
# Les noms de signaux sont ceux de signal / system.signal ("TERM", "SIGTERM", ou un numéro).
# Erreurs : ProcessError / ProcessNotFoundError (processus absent), PermissionError, SignalError,
#           ArgumentError (signal inconnu).

from core use type, len
use os as _os
use io as _io
use string as _str
use system.signal as _sig
use process.process_errors as _e
use process._libc as _c

func send(pid, sig="TERM"):
    _e.need_pid("process_signal.send", pid)
    try:
        _sig.send(pid, sig)
    catch e:
        if e.type == "ProcessError":
            _e.not_found("process_signal.send", pid)
        if e.type == "SignalError" and (_contains(e.message, "EPERM") or _contains(e.message, "ermission")):
            _e.permission("process_signal.send", "envoi du signal " + str(sig) + " au pid " + str(pid))
        raise(e)

func _contains(s, sub):
    i := 0
    while i + len(sub) <= len(s):
        if s[i:i + len(sub)] == sub:
            return true
        i += 1
    return false

func terminate(pid):
    send(pid, "TERM")

func kill(pid):
    send(pid, "KILL")

func interrupt(pid):
    send(pid, "INT")

func hangup(pid):
    send(pid, "HUP")

func suspend(pid):
    send(pid, "STOP")

func resume(pid):
    send(pid, "CONT")

func exists(pid):
    return _os.process_exists(pid)

# Vérifie l'existence ET le droit d'envoyer (même utilisateur, ou root), sans rien envoyer.
func can_signal(pid):
    if type(pid) != "int" or pid <= 0 or not _alive(pid):
        return false
    me := _os.user_id()
    if me == 0:
        return true
    try:
        text := _io.read_file("/proc/" + str(pid) + "/status")
        for line in _str.split(text, "\n"):
            if _str.starts_with(line, "Uid:"):
                return _contains(line, "\t" + str(me) + "\t") or _contains(line, " " + str(me) + " ")
    catch e:
        pass
    return true


# Attend que pid disparaisse (au plus timeout secondes) ; true s'il a disparu.
# Pour un FILS de ce programme, préférer Process.wait() : un fils non attendu reste zombie (et existe).
func wait_exit(pid, timeout=null, interval=0.02):
    t0 := _os.monotonic_time()
    while _alive(pid):
        if timeout != null and _os.monotonic_time() - t0 >= timeout:
            return false
        _os.sleep(interval)
    return true

func _alive(pid):
    if not _os.process_exists(pid):
        return false
    # Un zombie n'est plus vivant.
    if _os.isdir("/proc/self"):
        try:
            st := _state_code(pid)
            return st != "Z" and st != "X"
        catch e:
            return false
    return true

func _state_code(pid):
    text := _io.read_file("/proc/" + str(pid) + "/stat")
    k := len(text) - 1
    while k >= 0 and text[k] != ')':
        k -= 1
    return str(text[k + 2])

# TERM, attente de grace secondes, puis KILL ; true si le processus a disparu.
func shutdown(pid, grace=3.0):
    if not _alive(pid):
        return true
    try:
        terminate(pid)
    catch e:
        if e.type == _e.NOT_FOUND:
            return true
        raise(e)
    if wait_exit(pid, grace):
        return true
    try:
        kill(pid)
    catch e2:
        if e2.type == _e.NOT_FOUND:
            return true
        raise(e2)
    return wait_exit(pid, 2.0)

# Signal à tout un groupe de processus (killpg).
func send_group(pgid, sig="TERM"):
    _e.need_pid("process_signal.send_group", pgid)
    n := _sig.number(sig)
    r := _c.call("killpg", ["i32", "i32"], "i32", [pgid, n], "process_signal.send_group")
    if r != 0:
        if not _os.process_exists(pgid):
            _e.not_found("process_signal.send_group", pgid)
        _e.permission("process_signal.send_group", "envoi au groupe " + str(pgid))

func number(sig):
    return _sig.number(sig)

func name_of(sig):
    return _sig.name_of(sig)
