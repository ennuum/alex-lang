# ALEX STANDARD LIBRARY — pipe.pipe_reader
#
# PipeReader : le bout LECTURE d'un tube, avec ce qu'un programme qui consomme un flux attend : délai par
# défaut, parcours ligne à ligne PARESSEUX (`for ligne in r`), lecture jusqu'à un délimiteur, compteurs,
# test de disponibilité sans bloquer.
#
#   use pipe.anonymous_pipe as ap
#   use pipe.pipe_reader as prd
#   t := ap.AnonymousPipe()
#   r := prd.PipeReader(t, 2.0)            # AnonymousPipe, NamedPipe ouvert, DuplexEnd ou io.stream.Reader
#   t.send("a\nb\n")
#   t.close_writer()
#   for ligne in r:                        # lignes jusqu'à la fin du flux
#       print(ligne)
#   print(r.lines_read, r.bytes_read)      # 2 4
#   if r.ready(0.1):                       # données disponibles dans 0,1 s ?
#       print(r.read())
#
# Erreurs : TimeoutError, IoError, PipeClosedError (lecture après close).

from core use len, type
from collections use append
use string as _s
use pipe.pipe_errors as _e
use pipe.pipe_stream as _ps
use _native_reflect as _r

func _reader_of(src):
    # AnonymousPipe : champ reader ; DuplexEnd : objet lui-même (read/read_line) ; Reader : lui-même.
    if _r.is_instance(src) and _r.has_field(src, "reader"):
        return src.reader
    return src

class PipeReader:
    func init(source, timeout=null):
        self._r = _reader_of(source)
        self.timeout = timeout
        self.bytes_read = 0
        self.lines_read = 0
        self._closed = false
        self._eof = false

    func _need():
        if self._closed:
            _e.closed("PipeReader")

    func _count(text):
        if text != null:
            self.bytes_read += _s.byte_len(text)
        return text

    func _t(timeout):
        if timeout == null:
            return self.timeout
        return timeout

    # Jusqu'à max octets ; "" à la fin du flux.
    func read(max=65536, timeout=null):
        self._need()
        v := self._r.read(max, self._t(timeout))
        if v == "":
            self._eof = true
        return self._count(v)

    # Une ligne (sans « \n ») ; null à la fin du flux.
    func read_line(timeout=null):
        self._need()
        v := self._r.read_line(self._t(timeout))
        if v == null:
            self._eof = true
            return null
        self.lines_read += 1
        self.bytes_read += _s.byte_len(v) + 1
        return v

    func read_until(sep, timeout=null):
        self._need()
        v := self._r.read_until(sep, self._t(timeout))
        if v == null:
            self._eof = true
        return self._count(v)

    func read_exact(n, timeout=null):
        self._need()
        return self._count(self._r.read_exact(n, self._t(timeout)))

    func read_all(timeout=null):
        self._need()
        v := self._r.read_all(self._t(timeout))
        self._eof = true
        return self._count(v)

    # Toutes les lignes restantes (liste).
    func lines(timeout=null):
        out := []
        while true:
            l := self.read_line(timeout)
            if l == null:
                return out
            append(out, l)

    # f(ligne) pour chaque ligne jusqu'à la fin ; renvoie le nombre de lignes.
    func each_line(f, timeout=null):
        n := 0
        while true:
            l := self.read_line(timeout)
            if l == null:
                return n
            f(l)
            n += 1

    # Données disponibles d'ici timeout secondes (sans les consommer) ?
    func ready(timeout=0):
        self._need()
        try:
            return len(_ps.poll([self._r], timeout)) > 0
        catch e:
            return true

    func at_end():
        return self._eof

    func close():
        if not self._closed:
            self._closed = true
            try:
                self._r.close()
            catch e:
                pass

    # Parcours `for ligne in lecteur` : une ligne par tour, fin du flux = fin de la boucle.
    func __getitem__(i):
        l := self.read_line()
        if l == null:
            raise("IndexError", "fin du flux")
        return l

func reader(source, timeout=null):
    return PipeReader(source, timeout)
