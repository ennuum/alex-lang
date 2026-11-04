# ALEX STANDARD LIBRARY — signal.signal_constants
#
# Table des signaux POSIX : nom, numéro sur la plateforme courante (et sous Linux / macOS), action par défaut,
# interceptable ou non, description en français.
#
#   use signal.signal_constants as sc
#   print(sc.SIGTERM, sc.number("USR1"), sc.describe("WINCH"))
#   print(sc.default_action("CHLD"))         # « ignorer »
#   for s in sc.catchable():  ...
#
# Les constantes SIGxxx valent le numéro de la plateforme où le programme s'exécute (lu dans le runtime), donc
# différent entre Linux et macOS pour USR1, USR2, CHLD, BUS... : utiliser les noms dans le code portable.

from core use type, len
from collections use append, contains_key, keys
use string as _s
use _native_signal as _n

# [nom, numéro Linux x86-64, numéro macOS, action par défaut, interceptable, description]
_table := [
    ["HUP", 1, 1, "terminer", true, "le terminal de contrôle s'est fermé (souvent : recharger la configuration)"],
    ["INT", 2, 2, "terminer", true, "interruption depuis le clavier (Ctrl+C)"],
    ["QUIT", 3, 3, "image mémoire", true, "abandon depuis le clavier (Ctrl+\\)"],
    ["ILL", 4, 4, "image mémoire", false, "instruction illégale"],
    ["TRAP", 5, 5, "image mémoire", true, "point d'arrêt (débogueur)"],
    ["ABRT", 6, 6, "image mémoire", true, "abandon (abort)"],
    ["BUS", 7, 10, "image mémoire", false, "erreur de bus (accès mémoire mal aligné ou hors fichier projeté)"],
    ["FPE", 8, 8, "image mémoire", false, "erreur arithmétique (division entière par zéro)"],
    ["KILL", 9, 9, "terminer", false, "arrêt immédiat, impossible à intercepter"],
    ["USR1", 10, 30, "terminer", true, "signal libre pour l'application"],
    ["SEGV", 11, 11, "image mémoire", false, "accès mémoire invalide"],
    ["USR2", 12, 31, "terminer", true, "second signal libre pour l'application"],
    ["PIPE", 13, 13, "terminer", true, "écriture dans un tube sans lecteur"],
    ["ALRM", 14, 14, "terminer", true, "minuterie (alarm) écoulée"],
    ["TERM", 15, 15, "terminer", true, "demande d'arrêt propre"],
    ["STKFLT", 16, 0, "terminer", true, "erreur de pile du coprocesseur (Linux)"],
    ["CHLD", 17, 20, "ignorer", true, "un processus fils s'est arrêté ou terminé"],
    ["CONT", 18, 19, "reprendre", true, "reprise après un arrêt"],
    ["STOP", 19, 17, "arrêter", false, "arrêt (suspension), impossible à intercepter"],
    ["TSTP", 20, 18, "arrêter", true, "suspension depuis le clavier (Ctrl+Z)"],
    ["TTIN", 21, 21, "arrêter", true, "lecture du terminal par un processus d'arrière-plan"],
    ["TTOU", 22, 22, "arrêter", true, "écriture sur le terminal par un processus d'arrière-plan"],
    ["URG", 23, 16, "ignorer", true, "données urgentes sur un socket"],
    ["XCPU", 24, 24, "image mémoire", true, "limite de temps processeur dépassée"],
    ["XFSZ", 25, 25, "image mémoire", true, "limite de taille de fichier dépassée"],
    ["VTALRM", 26, 26, "terminer", true, "minuterie virtuelle écoulée"],
    ["PROF", 27, 27, "terminer", true, "minuterie de profilage écoulée"],
    ["WINCH", 28, 28, "ignorer", true, "la taille du terminal a changé"],
    ["IO", 29, 23, "terminer", true, "entrée-sortie possible (E/S asynchrones)"],
    ["PWR", 30, 0, "terminer", true, "problème d'alimentation (Linux)"],
    ["SYS", 31, 12, "image mémoire", true, "appel système invalide"]]

func _row(name):
    if type(name) == "int":
        local := _n.name(name)
        if local == null:
            return null
        name = local
    if type(name) != "str":
        raise("TypeError", "signal_constants : nom (str) ou numéro (int) attendu")
    up := _s.upper(name)
    if _s.starts_with(up, "SIG"):
        up = _s.substring(up, 3, len(up))
    for r in _table:
        if r[0] == up:
            return r
    return null

func _need(name):
    r := _row(name)
    if r == null:
        raise("ArgumentError", "signal_constants : signal inconnu '" + str(name) + "'")
    return r

# Numéro sur la plateforme courante (null si le signal n'y existe pas).
func number(name):
    r := _need(name)
    n := _n.number(r[0])
    if n < 0:
        return null
    return n

func linux_number(name):
    return _need(name)[1]

func macos_number(name):
    n := _need(name)[2]
    if n == 0:
        return null
    return n

# Nom court (« TERM ») d'un numéro de la plateforme courante, ou null.
func name_of(num):
    return _n.name(num)

func describe(name):
    return _need(name)[5]

# « terminer », « image mémoire » (terminer avec core dump), « ignorer », « arrêter », « reprendre ».
func default_action(name):
    return _need(name)[3]

# Faux pour KILL, STOP et les fautes (SEGV, BUS, FPE, ILL), que system.signal refuse d'intercepter.
func is_catchable(name):
    return _need(name)[4]

func exists(name):
    r := _row(name)
    return r != null and _n.number(r[0]) >= 0

# Noms connus de la table (ordre des numéros Linux).
func all_names():
    return [r[0] for r in _table]

# Noms interceptables disponibles sur cette plateforme.
func catchable():
    return [r[0] for r in _table if r[4] and _n.number(r[0]) >= 0]

# Signaux habituels d'une demande d'arrêt.
func shutdown_signals():
    return ["INT", "TERM", "HUP"]

# Vrai si le signal termine le processus par défaut.
func terminates(name):
    a := default_action(name)
    return a == "terminer" or a == "image mémoire"

func _local(name):
    n := _n.number(name)
    if n < 0:
        return null
    return n

const SIGHUP := 1
const SIGINT := 2
const SIGQUIT := 3
const SIGILL := 4
const SIGTRAP := 5
const SIGABRT := 6
const SIGFPE := 8
const SIGKILL := 9
const SIGSEGV := 11
const SIGPIPE := 13
const SIGALRM := 14
const SIGTERM := 15

# Numéros qui dépendent de la plateforme (variables, calculées au chargement).
SIGBUS := _local("BUS")
SIGUSR1 := _local("USR1")
SIGUSR2 := _local("USR2")
SIGCHLD := _local("CHLD")
SIGCONT := _local("CONT")
SIGSTOP := _local("STOP")
SIGTSTP := _local("TSTP")
SIGTTIN := _local("TTIN")
SIGTTOU := _local("TTOU")
SIGURG := _local("URG")
SIGXCPU := _local("XCPU")
SIGXFSZ := _local("XFSZ")
SIGVTALRM := _local("VTALRM")
SIGPROF := _local("PROF")
SIGWINCH := _local("WINCH")
SIGIO := _local("IO")
SIGSYS := _local("SYS")
