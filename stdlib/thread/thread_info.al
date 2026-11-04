# ALEX STANDARD LIBRARY — thread.thread_info
#
# Informations sur les fils : le fil courant (identifiant Alex, identité système, nom), le nombre de cœurs et de
# fils actifs, et la liste des fils SYSTÈME du processus (Linux : /proc/self/task — état, temps processeur, nom),
# ce qui comprend les fils internes du runtime.
#
#   use thread.thread_info as ti
#   me := ti.current()
#   print(me.id, me.name, me.is_main)        # 0 « principal » true dans le programme principal
#   print(ti.cpu_count(), ti.active_count())
#   for t in ti.os_threads():
#       print(t["tid"], t["name"], t["state"], t["cpu_time"])

from core use len, to_int
from collections use append
use string as _str
use os as _os
use io as _io
use _native_thread as _t
use _native_sync as _s

const CLOCK_TICKS := 100

class ThreadInfo:
    func init(id, name, token, is_main):
        self.id = id              # identifiant Alex (0 : programme principal)
        self.name = name
        self.token = token        # identité du fil système (stable pendant la vie du fil)
        self.is_main = is_main

    func to_string():
        return "ThreadInfo(" + str(self.id) + ", " + self.name + ")"

func current():
    id := _t.current_id()
    name := "principal"
    if id != 0:
        name = _t.name(id)
    return ThreadInfo(id, name, _s.token(), id == 0)

func current_id():
    return _t.current_id()

func is_main():
    return _t.is_main()

func cpu_count():
    return _t.cpu_count()

# Fils Alex lancés et pas encore terminés.
func active_count():
    return _t.active_count()

func _read(path):
    try:
        return _io.read_file(path)
    catch e:
        return null

# Fils système du processus : liste de dict {tid, name, state, cpu_time} (vide hors Linux).
func os_threads():
    out := []
    if not _os.isdir("/proc/self/task"):
        return out
    for n in _os.list_dir("/proc/self/task"):
        stat := _read("/proc/self/task/" + n + "/stat")
        if stat == null:
            continue
        close := -1
        i := len(stat) - 1
        while i >= 0:
            if stat[i] == ')':
                close = i
                break
            i -= 1
        open := _str.find(stat, "(")
        if close < 0 or open < 0:
            continue
        rest := _str.split(_str.trim(_str.substring(stat, close + 1, len(stat))), " ")
        cpu := null
        try:
            cpu = (to_int(rest[11]) + to_int(rest[12])) / CLOCK_TICKS
        catch e:
            cpu = null
        append(out, {"tid": to_int(n), "name": _str.substring(stat, open + 1, close), "state": rest[0], "cpu_time": cpu})
    return out

func os_thread_count():
    return len(os_threads())
