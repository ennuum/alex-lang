# ALEX STANDARD LIBRARY — process.process_handle
#
# ProcessHandle : une poignée UNIFORME sur un processus, qu'il soit un fils de ce programme (process.Process)
# ou un processus quelconque désigné par son pid. Mêmes opérations dans les deux cas : état, attente,
# signaux, informations, code de sortie.
#
#   use process
#   use process.process_handle as ph
#   h := ph.spawn("sleep", ["5"])              # fils
#   print(h.pid(), h.state(), h.is_child())     # 1234 sleeping true
#   h.terminate()
#   print(h.wait(2.0), h.exit_status().describe())   # -15 « tué par le signal TERM (15) »
#   h.close()
#   autre := ph.of_pid(1)                       # processus existant (non fils)
#   print(autre.info().name, autre.is_running())
#
# Pour un processus qui n'est PAS un fils, le code de sortie est inconnu (null) : seul son parent peut
# l'obtenir ; wait() attend sa disparition.
# Erreurs : ProcessNotFoundError, PermissionError, TimeoutError, IoError, ArgumentError.

from core use type
use os as _os
use process as _p
use process.exit_code as _ec
use process.process_info as _pi
use process.process_state as _st
use process.process_signal as _sig
use process.process_errors as _e

class ProcessHandle:
    # Préférer spawn() / of_process() / of_pid().
    func init(pid, child=null):
        self._pid = pid
        self._child = child
        self._code = null
        self._started = _os.monotonic_time()
        self._closed = false

    func pid():
        return self._pid

    func is_child():
        return self._child != null

    # process.Process sous-jacent (null pour un processus non fils).
    func process():
        return self._child

    # Code de sortie s'il est connu, sans bloquer.
    func poll():
        if self._code != null:
            return self._code
        if self._child != null and not self._closed:
            self._code = self._child.poll()
        return self._code

    func is_running():
        if self._child != null:
            if self._closed:
                return false
            return self.poll() == null
        st := _st.of_pid(self._pid)
        return _st.is_alive(st)

    func state():
        if self._child != null:
            c := self.poll()
            if c != null:
                return _st.from_exit_code(c)
            if self._closed:
                return _st.UNKNOWN
        return _st.of_pid(self._pid)

    # Attend la fin ; code de sortie (null : non fils, ou délai expiré).
    func wait(timeout=null):
        if self._child != null:
            if self._code == null and not self._closed:
                self._code = self._child.wait(timeout)
            return self._code
        if not _sig.wait_exit(self._pid, timeout):
            return null
        return null

    # Comme wait, mais TimeoutError si le délai expire.
    func wait_or_raise(timeout):
        r := self.wait(timeout)
        if self.is_running():
            raise(_e.TIMEOUT, "ProcessHandle.wait : pid " + str(self._pid) + " toujours actif après " + str(timeout) + " s")
        return r

    func signal(sig="TERM"):
        if self._child != null and not self._closed:
            if self.poll() != null:
                return
            self._child.kill(sig)
            return
        _sig.send(self._pid, sig)

    func terminate():
        self.signal("TERM")

    func kill():
        self.signal("KILL")

    func suspend():
        self.signal("STOP")

    func resume():
        self.signal("CONT")

    # TERM, attente, puis KILL ; renvoie le code (fils) ou null.
    func stop(grace=3.0):
        if self._child != null and not self._closed:
            if self._code == null:
                self._code = self._child.stop(grace)
            return self._code
        _sig.shutdown(self._pid, grace)
        return null

    func exit_status():
        return _ec.ExitStatus(self.poll())

    # Informations (process_info.ProcessInfo) ; null si le processus a disparu.
    func info():
        return _pi.get_or_null(self._pid)

    # Secondes depuis la création de la poignée (fils) ou l'âge du processus (autre).
    func uptime():
        if self._child != null:
            return _os.monotonic_time() - self._started
        i := self.info()
        if i == null:
            return null
        return i.age()

    func children():
        return [of_pid(c.pid) for c in _pi.children(self._pid)]

    # Libère le handle d'un fils (après wait/stop). Idempotent.
    func close():
        if self._child != null and not self._closed:
            if self._code == null:
                self._code = self._child.poll()
            self._child.close()
        self._closed = true

    func __str__():
        kind := "processus"
        if self._child != null:
            kind = "fils"
        return "ProcessHandle(" + kind + " " + str(self._pid) + ", " + self.state() + ")"

func of_process(proc):
    return ProcessHandle(proc.pid(), proc)

# Poignée sur un processus existant ; ProcessNotFoundError s'il n'existe pas.
func of_pid(pid):
    _e.need_pid("process_handle.of_pid", pid)
    if not _os.process_exists(pid):
        _e.not_found("process_handle.of_pid", pid)
    return ProcessHandle(pid)

func current():
    return ProcessHandle(_os.pid())

func spawn(program, args=null, cwd=null, env=null, stdin="inherit", stdout="inherit", stderr="inherit"):
    return of_process(_p.spawn(program, args, cwd, env, stdin, stdout, stderr))
