# ALEX STANDARD LIBRARY — logging.log_level
#
# Niveaux de journalisation : TRACE 5 < DEBUG 10 < INFO 20 < NOTICE 25 < WARNING 30 < ERROR 40 < CRITICAL 50,
# et OFF 100 (rien). On les désigne par nom (insensible à la casse, « warn » accepté) ou par nombre ; des
# niveaux personnalisés peuvent être ajoutés.
#
#   use logging.log_level as lv
#   print(lv.parse("warning"), lv.name_of(40), lv.parse(25))   # 30 ERROR 25
#   lv.register("AUDIT", 35)
#   print(lv.is_enabled(lv.INFO, "audit"))                     # un message AUDIT passe un seuil INFO
#   print(lv.color(lv.ERROR))                                  # séquence ANSI (rouge)
#
# Erreurs : ValueError (niveau inconnu), TypeError.

from core use type
use string as _s
use logging.logging_errors as _e

const TRACE := 5
const DEBUG := 10
const INFO := 20
const NOTICE := 25
const WARNING := 30
const ERROR := 40
const CRITICAL := 50
const OFF := 100

_names := {5: "TRACE", 10: "DEBUG", 20: "INFO", 25: "NOTICE", 30: "WARNING", 40: "ERROR", 50: "CRITICAL", 100: "OFF"}
_values := {"TRACE": 5, "DEBUG": 10, "INFO": 20, "NOTICE": 25, "WARNING": 30, "WARN": 30, "ERROR": 40,
            "CRITICAL": 50, "FATAL": 50, "OFF": 100}
_colors := {5: "\u001b[90m", 10: "\u001b[36m", 20: "\u001b[32m", 25: "\u001b[34m", 30: "\u001b[33m",
            40: "\u001b[31m", 50: "\u001b[1;31m"}

const RESET := "\u001b[0m"

func parse(level):
    if type(level) == "int":
        return level
    if type(level) != "str":
        raise("TypeError", "log_level.parse : nom ou entier attendu (obtenu '" + type(level) + "')")
    u := _s.upper(_s.trim(level))
    if u in _values:
        return _values[u]
    _e.unknown_level(level)

# Nom du niveau ; pour une valeur non nommée, le nom du niveau inférieur le plus proche (« Level 33 » sinon).
func name_of(value):
    v := parse(value)
    if v in _names:
        return _names[v]
    best := null
    for k in _names:
        if k <= v and (best == null or k > best):
            best = k
    if best == null:
        return "Level " + str(v)
    return _names[best]

func register(name, value):
    if type(value) != "int":
        raise("TypeError", "log_level.register : valeur entière attendue")
    u := _s.upper(name)
    _names[value] = u
    _values[u] = value
    return value

# Un message de niveau level passe-t-il le seuil threshold ?
func is_enabled(threshold, level):
    return parse(level) >= parse(threshold)

func color(value):
    v := parse(value)
    best := null
    for k in _colors:
        if k <= v and (best == null or k > best):
            best = k
    if best == null:
        return ""
    return _colors[best]

func names():
    out := []
    for k in _names:
        out = out + [_names[k]]
    return out

func all_levels():
    return [TRACE, DEBUG, INFO, NOTICE, WARNING, ERROR, CRITICAL]
