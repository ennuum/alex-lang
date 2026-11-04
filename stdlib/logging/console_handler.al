# ALEX STANDARD LIBRARY — logging.console_handler
#
# ConsoleHandler : écrit sur la sortie standard ou d'erreur, avec couleurs optionnelles. Par défaut, les
# niveaux WARNING et plus vont sur stderr, le reste sur stdout (split=true), comme le veulent les outils en
# ligne de commande (la sortie utile reste propre dans un tube).
#
#   use logging.console_handler as ch
#   h := ch.ConsoleHandler()                       # couleurs si la sortie est un terminal
#   h := ch.ConsoleHandler("INFO", "stderr")       # tout sur stderr
#   h := ch.ConsoleHandler("DEBUG", "stdout", false, false)   # sans couleur, sans répartition
#
# Erreurs : ArgumentError (flux inconnu).

from core use type
use io.stream as _st
use _native_fd as _fd
use logging.log_level as _lv
use logging.log_formatter as _lf
from logging.log_handler use Handler

func is_terminal(stream="stdout"):
    try:
        if stream == "stderr":
            return _fd.isatty(2)
        return _fd.isatty(1)
    catch e:
        return false

class ConsoleHandler extends Handler:
    func init(level=0, stream="stdout", color=null, split=true, formatter=null):
        if stream != "stdout" and stream != "stderr":
            raise("ArgumentError", "ConsoleHandler : flux \"stdout\" ou \"stderr\" attendu")
        c := color
        if c == null:
            c = is_terminal(stream)
        f := formatter
        if f == null:
            if c:
                f = _lf.ColorFormatter()
            else:
                f = _lf.Formatter()
        super.init(level, f)
        self.stream = stream
        self.color = c
        self.split = split and stream == "stdout"
        self._out = _st.stdout()
        self._err = _st.stderr()

    func emit(text, r):
        if self.stream == "stderr" or (self.split and r.level >= _lv.WARNING):
            self._err.write_line(text)
        else:
            self._out.write_line(text)

    func flush():
        try:
            self._out.flush()
            self._err.flush()
        catch e:
            pass

func console(level=0, stream="stdout"):
    return ConsoleHandler(level, stream)
