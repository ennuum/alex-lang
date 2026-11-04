# ALEX STANDARD LIBRARY — logging.logger
#
# Loggers HIÉRARCHIQUES à la Python, avec gestionnaires par logger, propagation vers les parents, filtres,
# contexte structuré et journalisation des exceptions. (Le module logging, lui, reste l'interface simple
# d'un journal unique ; les deux peuvent coexister.)
#
#   use logging.logger as lg
#   use logging.console_handler as ch
#   use logging.rotating_handler as rh
#   lg.basic_config("INFO")                          # racine : console, niveau INFO
#   log := lg.get_logger("app.db")
#   log.info("connexion à {}", ["db1"])               # arguments substitués
#   log.warning("requête lente", null, {"ms": 812})   # champs structurés (extra)
#   try:
#       requete()
#   catch e:
#       log.exception("échec de la requête", e)        # niveau ERROR + type, message et trace
#   lg.get_logger("app").add_handler(rh.RotatingFileHandler("app.log", 1048576, 3))
#   req := log.bind({"requete": 42})                  # adaptateur : contexte ajouté à chaque message
#   req.info("début")
#   with lg.timed(log, "chargement"):                 # durée journalisée à la sortie du bloc
#       charger()
#
# Niveau effectif : le sien, sinon celui du parent le plus proche (racine : WARNING tant que non configurée).
# propagate=false : les gestionnaires des parents ne reçoivent pas ses messages.
# Erreurs : ValueError (niveau inconnu), LoggingError (gestionnaire invalide).

from core use len, type
from collections use append
use string as _s
use os as _os
use logging.log_level as _lv
use logging.log_record as _rec
use logging.log_handler as _lh
use logging.console_handler as _ch
use logging.logging_errors as _e
use _native_reflect as _r
use collections._util as _u
use logging.log_formatter as _lf
use logging.file_handler as _fh

_loggers := {}

class Logger:
    func init(name, parent=null):
        self.name = name
        self.parent = parent
        self.level = null
        self.handlers = []
        self.filters = []
        self.propagate = true
        self.disabled = false
        self.context = {}

    func set_level(level):
        if level == null:
            self.level = null
        else:
            self.level = _lv.parse(level)
        return self

    func effective_level():
        l := self
        while l != null:
            if l.level != null:
                return l.level
            l = l.parent
        return _lv.WARNING

    func enabled(level):
        return not self.disabled and _lv.parse(level) >= self.effective_level()

    func add_handler(h):
        if _r.method(h, "handle") == null:
            _e.logging_error("Logger.add_handler", "gestionnaire attendu (objet doté de handle)")
        append(self.handlers, h)
        return h

    func remove_handler(h):
        self.handlers = [x for x in self.handlers if not _same(x, h)]

    func clear_handlers():
        self.handlers = []

    func add_filter(f):
        append(self.filters, f)
        return self

    func has_handlers():
        l := self
        while l != null:
            if len(l.handlers) > 0:
                return true
            if not l.propagate:
                return false
            l = l.parent
        return false

    func handle(r):
        for f in self.filters:
            if not f.accepts(r):
                return
        l := self
        while l != null:
            for h in l.handlers:
                h.handle(r)
            if not l.propagate:
                break
            l = l.parent

    func _merge(extra):
        if len(self.context) == 0:
            return extra
        out := {}
        for k in self.context:
            out[k] = self.context[k]
        if extra != null:
            for k in extra:
                out[k] = extra[k]
        return out

    func log(level, msg, args=null, extra=null):
        lv := _lv.parse(level)
        if not self.enabled(lv):
            return
        self.handle(_rec.LogRecord(self.name, lv, msg, args, self._merge(extra)))

    func trace(msg, args=null, extra=null):
        self.log(_lv.TRACE, msg, args, extra)

    func debug(msg, args=null, extra=null):
        self.log(_lv.DEBUG, msg, args, extra)

    func info(msg, args=null, extra=null):
        self.log(_lv.INFO, msg, args, extra)

    func notice(msg, args=null, extra=null):
        self.log(_lv.NOTICE, msg, args, extra)

    func warning(msg, args=null, extra=null):
        self.log(_lv.WARNING, msg, args, extra)

    func error(msg, args=null, extra=null):
        self.log(_lv.ERROR, msg, args, extra)

    func critical(msg, args=null, extra=null):
        self.log(_lv.CRITICAL, msg, args, extra)

    # Niveau ERROR avec l'exception e (type, message, trace).
    func exception(msg, e, extra=null, level="ERROR"):
        lv := _lv.parse(level)
        if not self.enabled(lv):
            return
        self.handle(_rec.from_exception(self.name, lv, msg, e, self._merge(extra)))

    # Logger enfant : get_logger(self.name + "." + suffix).
    func child(suffix):
        if self.name == "root":
            return get_logger(suffix)
        return get_logger(self.name + "." + suffix)

    # Adaptateur qui ajoute context à chaque message.
    func bind(context):
        return LoggerAdapter(self, context)

    func flush():
        for h in self.handlers:
            h.flush()

    func __str__():
        return "<Logger " + self.name + " (" + _lv.name_of(self.effective_level()) + ")>"

func _same(a, b):
    return _u.same(a, b)

class LoggerAdapter:
    func init(logger, context):
        self.logger = logger
        self.context = context

    func _merge(extra):
        out := {}
        for k in self.context:
            out[k] = self.context[k]
        if extra != null:
            for k in extra:
                out[k] = extra[k]
        return out

    func log(level, msg, args=null, extra=null):
        self.logger.log(level, msg, args, self._merge(extra))

    func debug(msg, args=null, extra=null):
        self.log(_lv.DEBUG, msg, args, extra)

    func info(msg, args=null, extra=null):
        self.log(_lv.INFO, msg, args, extra)

    func warning(msg, args=null, extra=null):
        self.log(_lv.WARNING, msg, args, extra)

    func error(msg, args=null, extra=null):
        self.log(_lv.ERROR, msg, args, extra)

    func critical(msg, args=null, extra=null):
        self.log(_lv.CRITICAL, msg, args, extra)

    func exception(msg, e, extra=null):
        self.logger.exception(msg, e, self._merge(extra))

    func bind(more):
        return LoggerAdapter(self.logger, self._merge(more))

func root():
    if not ("root" in _loggers):
        _loggers["root"] = Logger("root")
    return _loggers["root"]

func _parent_of(name):
    i := len(name) - 1
    while i >= 0:
        if name[i] == '.':
            return get_logger(_s.substring(name, 0, i))
        i -= 1
    return root()

func get_logger(name="root"):
    if name == "" or name == "root":
        return root()
    if name in _loggers:
        return _loggers[name]
    l := Logger(name, _parent_of(name))
    _loggers[name] = l
    return l

func loggers():
    return [k for k in _loggers]

# Configuration rapide de la racine : niveau, console, fichier éventuel, format.
func basic_config(level="INFO", fmt=null, file=null, stream="stdout", force=false):
    r := root()
    if len(r.handlers) > 0 and not force:
        r.set_level(level)
        return r
    r.clear_handlers()
    r.set_level(level)
    f := null
    if fmt != null:
        f = _lf.Formatter(fmt)
    r.add_handler(_ch.ConsoleHandler(0, stream, null, true, f))
    if file != null:
        r.add_handler(_fh.FileHandler(file, "a", 0, f))
    return r

# Retire gestionnaires et niveaux de tous les loggers (tests).
func reset():
    for k in [x for x in _loggers]:
        del _loggers[k]

func disable(level="CRITICAL"):
    root().set_level(_lv.parse(level) + 1)

class _Timed:
    func init(logger, label, level):
        self.logger = logger
        self.label = label
        self.level = level
        self.t0 = 0

    func __enter__():
        self.t0 = _os.monotonic_time()
        return self

    func __exit__(a, b, c):
        ms := (_os.monotonic_time() - self.t0) * 1000.0
        self.logger.log(self.level, "{} : {} ms", [self.label, _round(ms)], {"duration_ms": _round(ms)})

func _round(x):
    return (x * 10 + 0.5) // 1 / 10

# `with timed(log, "étape"):` journalise la durée du bloc.
func timed(logger, label, level="DEBUG"):
    return _Timed(logger, label, level)
