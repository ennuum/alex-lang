# ALEX STANDARD LIBRARY — thread.thread_priority
#
# Priorité d'ordonnancement d'un FIL (Linux : chaque fil a sa propre valeur nice, -20 la plus haute,
# 19 la plus basse). Un fil règle d'ordinaire SA propre priorité, au début de sa fonction : un fil de calcul
# de fond se met à LOW pour laisser la main à l'interface.
#
#   use thread.thread_priority as tp
#   func travail_de_fond(n):
#       tp.set(tp.LOW)                 # ce fil seulement
#       ...
#   print(tp.get())                    # priorité du fil courant
#   print(tp.get_tid(4321))            # d'un autre fil du processus (tid système)
#   tp.with_priority(tp.IDLE, calcul)  # le temps d'un appel
#
# Niveaux : HIGHEST -15, HIGH -5, NORMAL 0, LOW 10, IDLE 19. Augmenter (valeur plus petite) exige des droits.
# Erreurs : ThreadPriorityError (hors bornes, refus), IoError (plateforme sans ce réglage).

from core use len, type, to_int
use string as _s
use io as _io
use process._libc as _c
use thread.thread_id as _tid

const HIGHEST := -15
const HIGH := -5
const NORMAL := 0
const LOW := 10
const IDLE := 19

const ERROR := "ThreadPriorityError"

func _need(n):
    if type(n) != "int" or n < -20 or n > 19:
        raise(ERROR, "thread_priority : priorité " + str(n) + " hors de -20..19")

# Priorité du fil de tid système donné (dans ce processus).
func get_tid(tid):
    text := null
    try:
        text = _io.read_file("/proc/self/task/" + str(tid) + "/stat")
    catch e:
        raise(ERROR, "thread_priority.get : fil " + str(tid) + " introuvable dans ce processus")
    k := len(text) - 1
    while k >= 0 and text[k] != ')':
        k -= 1
    rest := [x for x in _s.split(_s.trim(_s.substring(text, k + 1, len(text))), " ") if x != ""]
    return to_int(rest[16])

func get():
    t := _tid.os_tid()
    if t == null:
        raise("IoError", "thread_priority.get : identifiant système du fil indisponible")
    return get_tid(t)

func set_tid(tid, nice):
    _need(nice)
    old := get_tid(tid)
    r := _c.call("setpriority", ["i32", "i32", "i32"], "i32", [0, tid, nice], "thread_priority.set")
    if r != 0:
        raise(ERROR, "thread_priority.set : priorité " + str(nice) + " refusée (droits insuffisants ?)")
    return old

# Règle la priorité du fil COURANT ; renvoie l'ancienne.
func set(nice):
    t := _tid.os_tid()
    if t == null:
        raise("IoError", "thread_priority.set : identifiant système du fil indisponible")
    return set_tid(t, nice)

func with_priority(nice, body):
    old := set(nice)
    try:
        return body()
    finally:
        try:
            set(old)
        catch e:
            pass

func name_of(nice):
    if nice <= -10:
        return "highest"
    if nice < 0:
        return "high"
    if nice == 0:
        return "normal"
    if nice < 19:
        return "low"
    return "idle"

func supported():
    return _c.available()
