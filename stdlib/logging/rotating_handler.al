# ALEX STANDARD LIBRARY — logging.rotating_handler
#
# Fichiers de journal à ROTATION : le fichier courant est renommé (app.log -> app.log.1 -> app.log.2 ...) et
# un nouveau commence, pour borner la place occupée.
#   RotatingFileHandler(path, max_bytes, backup_count)      rotation par taille
#   TimedRotatingFileHandler(path, when, backup_count)      rotation par durée : "minute", "hourly", "daily",
#                                                            "weekly" ou un nombre de secondes
#
#   use logging.rotating_handler as rh
#   h := rh.RotatingFileHandler("logs/app.log", 1048576, 5)    # 1 Mio par fichier, 5 anciens gardés
#   t := rh.TimedRotatingFileHandler("logs/jour.log", "daily", 7)
#   print(h.backups(), h.rotations)
#   h.rotate()                                                  # rotation forcée
#
# Les sauvegardes au-delà de backup_count sont supprimées. Erreurs : LoggingError (paramètres invalides).

from core use len, type
from collections use append
use os as _os
use logging.logging_errors as _e
use logging.log_record as _rec
from logging.file_handler use FileHandler

func _shift(path, backup_count):
    if backup_count <= 0:
        if _os.exists(path):
            _os.remove(path)
        return
    oldest := path + "." + str(backup_count)
    if _os.exists(oldest):
        _os.remove(oldest)
    i := backup_count - 1
    while i >= 1:
        p := path + "." + str(i)
        if _os.exists(p):
            _os.move(p, path + "." + str(i + 1))
        i -= 1
    if _os.exists(path):
        _os.move(path, path + ".1")

func _backups(path):
    out := []
    i := 1
    while _os.exists(path + "." + str(i)):
        append(out, path + "." + str(i))
        i += 1
    return out

class RotatingFileHandler extends FileHandler:
    func init(path, max_bytes=10485760, backup_count=5, level=0, formatter=null):
        if type(max_bytes) != "int" or max_bytes < 1:
            _e.logging_error("RotatingFileHandler", "max_bytes >= 1 attendu")
        super.init(path, "a", level, formatter, true)
        self.max_bytes = max_bytes
        self.backup_count = backup_count
        self.rotations = 0

    func rotate():
        _shift(self.path, self.backup_count)
        self._opened = false
        self.rotations += 1

    func emit(text, r):
        line_size := len(text) + 1
        if self.size() > 0 and self.size() + line_size > self.max_bytes:
            self.rotate()
        super.emit(text, r)

    func backups():
        return _backups(self.path)

_periods := {"minute": 60, "hourly": 3600, "daily": 86400, "weekly": 604800}

class TimedRotatingFileHandler extends FileHandler:
    func init(path, when="daily", backup_count=7, level=0, formatter=null):
        p := when
        if type(when) == "str":
            if not (when in _periods):
                _e.logging_error("TimedRotatingFileHandler", "période inconnue '" + when + "' (minute, hourly, daily, weekly, ou secondes)")
            p = _periods[when]
        if type(p) != "int" and type(p) != "float":
            _e.logging_error("TimedRotatingFileHandler", "période invalide")
        super.init(path, "a", level, formatter, true)
        self.period = p
        self.backup_count = backup_count
        self.rotations = 0
        self.next_rollover = self._boundary(_rec.now())

    # Prochaine frontière de période (alignée sur l'époque UTC).
    func _boundary(t):
        return (t // self.period + 1) * self.period

    func rotate():
        _shift(self.path, self.backup_count)
        self._opened = false
        self.rotations += 1

    func emit(text, r):
        if r.time >= self.next_rollover:
            if self.size() > 0:
                self.rotate()
            self.next_rollover = self._boundary(r.time)
        super.emit(text, r)

    func backups():
        return _backups(self.path)
