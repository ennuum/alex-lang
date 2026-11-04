# ALEX STANDARD LIBRARY — pipe.pipe_writer
#
# PipeWriter : le bout ÉCRITURE d'un tube, avec mise en tampon optionnelle (moins d'appels système pour de
# nombreuses petites écritures), compteurs, et traitement explicite du lecteur parti (EPIPE ; SIGPIPE est
# ignoré dès le premier PipeWriter pour que le processus ne soit pas tué) : erreur
# BrokenPipeError, ou arrêt silencieux si ignore_broken=true (comme un outil Unix qui écrit dans `head`).
#
#   use pipe.anonymous_pipe as ap
#   use pipe.pipe_writer as pwr
#   t := ap.AnonymousPipe()
#   w := pwr.PipeWriter(t, 4096)           # tampon de 4 Kio (0 : écriture immédiate)
#   w.write_line("bonjour")
#   w.write_lines(["a", "b"])
#   w.flush()
#   print(w.bytes_written, w.lines_written)
#   w.close()                              # vide le tampon puis ferme : le lecteur voit la fin du flux
#
# Erreurs : BrokenPipeError (plus de lecteur), PipeClosedError (écriture après close), IoError, TypeError.

from core use len, type
from collections use append
use string as _s
use pipe.pipe_errors as _e
use system.signal as _sig
use _native_reflect as _r

_sigpipe := [false]

# Un écrivain dont le lecteur est parti recevrait SIGPIPE, qui TUE le processus par défaut : on l'ignore
# (une seule fois, depuis le programme principal), comme Python, pour obtenir EPIPE -> BrokenPipeError.
func _ignore_sigpipe():
    if _sigpipe[0]:
        return
    _sigpipe[0] = true
    try:
        _sig.ignore("PIPE")
    catch e:
        pass

func _writer_of(dst):
    if _r.is_instance(dst) and _r.has_field(dst, "writer"):
        return dst.writer
    return dst

class PipeWriter:
    func init(target, buffer_size=0, ignore_broken=false):
        if type(buffer_size) != "int" or buffer_size < 0:
            raise("ArgumentError", "PipeWriter : taille de tampon >= 0 attendue")
        _ignore_sigpipe()
        self._w = _writer_of(target)
        self._target = target
        self.buffer_size = buffer_size
        self.ignore_broken = ignore_broken
        self._pending = []
        self._pending_bytes = 0
        self.bytes_written = 0
        self.lines_written = 0
        self.broken = false
        self._closed = false

    func _need():
        if self._closed:
            _e.closed("PipeWriter.write")

    func _emit(data):
        if self.broken:
            return 0
        try:
            if _r.method(self._w, "write") != null:
                return self._w.write(data)
            return self._w.send(data)
        catch e:
            if _e.is_broken(e):
                self.broken = true
                if self.ignore_broken:
                    return 0
                _e.broken("PipeWriter")
            raise(e)

    func write(text):
        self._need()
        if type(text) != "str":
            raise("TypeError", "PipeWriter.write : str attendue (obtenu '" + type(text) + "')")
        n := _s.byte_len(text)
        self.bytes_written += n
        if self.buffer_size == 0:
            self._emit(text)
            return n
        append(self._pending, text)
        self._pending_bytes += n
        if self._pending_bytes >= self.buffer_size:
            self.flush()
        return n

    func write_line(text=""):
        self.lines_written += 1
        return self.write(text + "\n")

    func write_lines(lines):
        n := 0
        for l in lines:
            n += self.write_line(l)
        return n

    func pending():
        return self._pending_bytes

    func flush():
        if len(self._pending) > 0:
            data := _s.byte_join(self._pending)
            self._pending = []
            self._pending_bytes = 0
            self._emit(data)
        try:
            self._w.flush()
        catch e:
            pass

    func close():
        if self._closed:
            return
        self.flush()
        self._closed = true
        if _r.method(self._target, "close_writer") != null:
            self._target.close_writer()
        else:
            try:
                self._w.close()
            catch e:
                pass

    func is_closed():
        return self._closed

func writer(target, buffer_size=0, ignore_broken=false):
    return PipeWriter(target, buffer_size, ignore_broken)
