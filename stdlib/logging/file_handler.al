# ALEX STANDARD LIBRARY — logging.file_handler
#
# FileHandler : écrit chaque enregistrement à la fin d'un fichier (mode « a ») ou dans un fichier remis à
# zéro à l'ouverture (mode « w »). Les dossiers manquants sont créés ; delay=true n'ouvre (ne crée) le fichier
# qu'au premier message. Chaque ligne est écrite immédiatement (rien n'est perdu si le programme s'arrête).
#
#   use logging.file_handler as fh
#   h := fh.FileHandler("logs/app.log")
#   h := fh.FileHandler("debug.log", "w", "DEBUG")
#   print(h.path, h.size(), h.lines_written)
#
# Erreurs : LoggingError (mode inconnu) ; une écriture impossible est comptée (errors), sans arrêter le programme.

from core use type
use os as _os
use io as _io
use filesystem as _fs
use logging.logging_errors as _e
from logging.log_handler use Handler

class FileHandler extends Handler:
    func init(path, mode="a", level=0, formatter=null, delay=false):
        if mode != "a" and mode != "w":
            _e.logging_error("FileHandler", "mode \"a\" ou \"w\" attendu (obtenu " + str(mode) + ")")
        super.init(level, formatter)
        self.path = path
        self.mode = mode
        self.lines_written = 0
        self._opened = false
        if not delay:
            self._open()

    func _open():
        if self._opened:
            return
        _fs.ensure_parent(self.path)
        if self.mode == "w" or not _os.exists(self.path):
            _io.write_file(self.path, "")
        self._opened = true

    func emit(text, r):
        self._open()
        _io.append_file(self.path, text + "\n")
        self.lines_written += 1

    func size():
        if not _os.exists(self.path):
            return 0
        return _os.size(self.path)

func file(path, level=0):
    return FileHandler(path, "a", level)
