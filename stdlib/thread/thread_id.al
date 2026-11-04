# ALEX STANDARD LIBRARY — thread.thread_id
#
# ThreadId : identité d'un fil d'exécution — numéro ALEX (0 : programme principal), identifiant système
# (tid Linux, visible dans /proc/self/task, top -H, gdb) et jeton natif stable. Comparable et hachable :
# sert de clé de dict pour un état par fil.
#
#   use thread.thread_id as tid
#   me := tid.current()
#   print(me.alex_id, me.os_tid, me.is_main())   # 0 41237 true
#   cles := {me.key(): "état du principal"}
#   print(tid.os_tid())                          # tid système du fil courant
#
# Erreurs : aucune (os_tid vaut null si la plateforme ne l'expose pas).

from core use type
use os as _os
use _native_sync as _s
use concurrency.thread as _ct
use process._libc as _c

func os_tid():
    f := _c.fn("gettid", [], "i32")
    if f != null:
        return f.call([])
    # Sans gettid : le fil principal a pour tid le pid.
    if _ct.is_main():
        return _os.pid()
    return null

class ThreadId:
    func init(alex_id, os_tid, token):
        self.alex_id = alex_id
        self.os_tid = os_tid
        self.token = token

    func is_main():
        return self.alex_id == 0

    # Clé hachable (dict, set).
    func key():
        return self.token

    func hash_code():
        return self.token

    func __eq__(other):
        return isinstance(other, ThreadId) and other.token == self.token

    func __str__():
        return "ThreadId(" + str(self.alex_id) + ", tid " + str(self.os_tid) + ")"

func current():
    return ThreadId(_ct.current_id(), os_tid(), _s.token())

func main_id():
    return 0

func is_main():
    return _ct.is_main()
