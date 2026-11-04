# ALEX STANDARD LIBRARY — logging
# Journalisation en ALEX pur (os pour l'horloge, io pour les fichiers).
#
#   use logging
#   logging.info("démarrage")                         # 2026-10-06 21:30:00 INFO     root: démarrage
#   log := logging.get_logger("db")
#   log.warning("lent")                               # ... WARNING  db: lent
#   logging.set_level("DEBUG")                        # niveau du logger racine
#   logging.add_file("app.log")                       # écrit aussi dans un fichier (ajout)
#
# NIVEAUX : DEBUG (10) < INFO (20) < WARNING (30) < ERROR (40) < CRITICAL (50). Un message n'est émis que si son
#   niveau >= celui du logger. Niveau par défaut : INFO. Les niveaux se donnent par nom ("warning" accepté) ou nombre.
# LOGGERS : get_logger(nom) renvoie toujours le même objet pour un nom donné. Un logger sans niveau propre
#   hérite du racine ("root"). Les noms pointés (« app.db ») héritent du parent « app » puis de root.
# HANDLERS : console (print, sur stdout) par défaut ; add_file(path) ajoute un fichier ; add_handler(fn) ajoute une
#   fonction(record_str, record_dict) ; clear_handlers() les retire tous (même la console) ; add_console() la remet.
#   Les handlers sont portés par le logger racine et partagés par tous les loggers.
# FORMAT : chaîne avec {time} {level} {name} {message} ; défaut "{time} {level} {name}: {message}".
#   {level} est justifié à 8 caractères. Heure UTC « AAAA-MM-JJ HH:MM:SS ». set_clock(fn) remplace l'horloge
#   (fn() -> secondes epoch) — utile pour les tests.
# Méthodes d'un logger : debug info warning error critical (message, ...), log(level, message), set_level, get_level,
#   enabled(level). Les fonctions du module (logging.info ...) agissent sur le logger racine.
# Erreurs : ValueError (niveau inconnu), TypeError (arguments invalides).

from core use len, type, to_int
from collections use append, contains_key
use string
use os
use io

const DEBUG := 10
const INFO := 20
const WARNING := 30
const ERROR := 40
const CRITICAL := 50

_state := {"loggers": {}, "handlers": [], "format": "{time} {level} {name}: {message}", "clock": null, "console": true}

func _level_value(level):
    if type(level) == "int":
        return level
    if type(level) != "str":
        raise("TypeError", "logging : niveau attendu (nom ou entier)")
    u := string.upper(level)
    if u == "DEBUG":
        return 10
    if u == "INFO":
        return 20
    if u == "WARNING" or u == "WARN":
        return 30
    if u == "ERROR":
        return 40
    if u == "CRITICAL":
        return 50
    raise("ValueError", "logging : niveau inconnu '" + level + "'")

func _level_name(value):
    if value >= 50:
        return "CRITICAL"
    if value >= 40:
        return "ERROR"
    if value >= 30:
        return "WARNING"
    if value >= 20:
        return "INFO"
    return "DEBUG"

func _pad2(n):
    if n < 10:
        return "0" + str(n)
    return str(n)

# Date civile (UTC) depuis un nombre de jours depuis 1970-01-01 (algorithme de H. Hinnant).
func _civil(days):
    z := days + 719468
    era := z // 146097
    doe := z - era * 146097
    yoe := (doe - doe // 1460 + doe // 36524 - doe // 146096) // 365
    y := yoe + era * 400
    doy := doe - (365 * yoe + yoe // 4 - yoe // 100)
    mp := (5 * doy + 2) // 153
    d := doy - (153 * mp + 2) // 5 + 1
    m := mp + 3
    if m > 12:
        m = m - 12
    if m <= 2:
        y = y + 1
    return [y, m, d]

# Formate des secondes epoch en "AAAA-MM-JJ HH:MM:SS" (UTC).
func format_time(seconds):
    total := to_int(seconds)
    days := total // 86400
    rem := total - days * 86400
    c := _civil(days)
    h := rem // 3600
    mi := (rem - h * 3600) // 60
    s := rem - h * 3600 - mi * 60
    return str(c[0]) + "-" + _pad2(c[1]) + "-" + _pad2(c[2]) + " " + _pad2(h) + ":" + _pad2(mi) + ":" + _pad2(s)

func _now():
    clock := _state["clock"]
    if clock != null:
        return clock()
    return os.time()

func _emit(name, level, message):
    record := {"time": format_time(_now()), "level": _level_name(level), "levelno": level, "name": name, "message": message}
    line := _state["format"]
    line = string.replace(line, "{time}", record["time"])
    line = string.replace(line, "{level}", record["level"] + string.repeat(" ", 8 - len(record["level"])))
    line = string.replace(line, "{name}", name)
    line = string.replace(line, "{message}", message)
    if _state["console"]:
        print(line)
    for h in _state["handlers"]:
        if type(h) == "str":
            io.append_file(h, line + "\n")
        else:
            h(line, record)

class Logger:
    func init(name, level):
        self.name = name
        self.level = level

    # Niveau effectif : le sien, sinon celui du parent pointé le plus proche, sinon celui du racine.
    func get_level():
        if self.level != null:
            return self.level
        if self.name == "root":
            return 20
        n := self.name
        while true:
            i := _last_dot(n)
            if i < 0:
                break
            n = string.slice(n, 0, i)
            if contains_key(_state["loggers"], n):
                p := _state["loggers"][n]
                if p.level != null:
                    return p.level
        return _state["loggers"]["root"].get_level()

    func set_level(level):
        self.level = _level_value(level)

    func enabled(level):
        return _level_value(level) >= self.get_level()

    func log(level, message):
        v := _level_value(level)
        if v >= self.get_level():
            _emit(self.name, v, str(message))

    func debug(message):
        self.log(10, message)

    func info(message):
        self.log(20, message)

    func warning(message):
        self.log(30, message)

    func error(message):
        self.log(40, message)

    func critical(message):
        self.log(50, message)

func _last_dot(s):
    i := len(s) - 1
    while i >= 0:
        if str(s[i]) == ".":
            return i
        i = i - 1
    return -1

func _ensure_root():
    if not contains_key(_state["loggers"], "root"):
        _state["loggers"]["root"] = Logger("root", 20)

# Logger de nom donné (créé à la première demande).
func get_logger(name="root"):
    if type(name) != "str" or name == "":
        raise("TypeError", "logging.get_logger : nom str non vide attendu")
    _ensure_root()
    if not contains_key(_state["loggers"], name):
        _state["loggers"][name] = Logger(name, null)
    return _state["loggers"][name]

func set_level(level):
    get_logger("root").set_level(level)

func get_level():
    return get_logger("root").get_level()

func debug(message):
    get_logger("root").debug(message)

func info(message):
    get_logger("root").info(message)

func warning(message):
    get_logger("root").warning(message)

func error(message):
    get_logger("root").error(message)

func critical(message):
    get_logger("root").critical(message)

func log(level, message):
    get_logger("root").log(level, message)

# Format des lignes : {time} {level} {name} {message}.
func set_format(fmt):
    if type(fmt) != "str":
        raise("TypeError", "logging.set_format : str attendue")
    _state["format"] = fmt

# Remplace l'horloge : fn() renvoie des secondes epoch ; null rétablit os.time().
func set_clock(fn):
    _state["clock"] = fn

# Ajoute un fichier (ajout en fin) comme destination.
func add_file(path):
    if type(path) != "str":
        raise("TypeError", "logging.add_file : chemin str attendu")
    append(_state["handlers"], path)

# Ajoute une fonction(line, record) ; record = {"time","level","levelno","name","message"}.
func add_handler(fn):
    if type(fn) != "function":
        raise("TypeError", "logging.add_handler : fonction attendue")
    append(_state["handlers"], fn)

# Retire tous les handlers, console comprise.
func clear_handlers():
    _state["handlers"] = []
    _state["console"] = false

func add_console():
    _state["console"] = true

# Rétablit l'état initial (loggers, handlers, format, horloge).
func reset():
    _state["loggers"] = {}
    _state["handlers"] = []
    _state["format"] = "{time} {level} {name}: {message}"
    _state["clock"] = null
    _state["console"] = true
