# ALEX STANDARD LIBRARY — io.stream
#
# Flux de lecture et d'écriture interchangeables : chaîne en mémoire, fichier, descripteur (tube, entrée
# standard), sortie standard / d'erreur, processus fils. Un code écrit pour un Reader marche sur toutes ces
# sources ; copy() relie n'importe quel Reader à n'importe quel Writer.
#
# Reader (lecture tamponnée, en OCTETS ; le texte n'est jamais coupé au milieu d'un caractère UTF-8 par read)
#   read(max)          texte disponible, au plus max octets ; "" : fin du flux
#   read_line()        une ligne sans « \n » / « \r\n » ; null : fin du flux
#   read_until(sep)    tout jusqu'au séparateur (exclu) ; null : fin du flux
#   read_exact(n)      exactement n octets ; IoError si le flux finit avant
#   read_all()         tout le reste ;   lines() : toutes les lignes restantes (list)
#   read_bytes(max)    comme read, en list[int] d'octets
# binary_stdio() : entrée / sorties standard sans conversion de fin de ligne (Windows), pour des octets bruts.
# Writer
#   write(texte) -> octets écrits, write_line(texte), write_bytes(list[int]), flush(), close()
#
# Délais : les lectures acceptent un délai (secondes, null : sans limite) là où la source peut attendre
# (descripteur, processus) : TimeoutError s'il est dépassé ; une chaîne ou un fichier n'attend jamais.
#
# Exemple
#   use io.stream as stream
#   r := stream.from_string("a\nb\nc")
#   print(r.lines())                          # [a, b, c]
#   w := stream.StringWriter()
#   stream.copy(stream.open_file("notes.txt"), w)
#   print(w.value())

from core use len, type
from collections use append
use _native_net as _b
use _native_fd as _f
use _native_cli as _cli
use file as _file

const CHUNK := 65536
const LINE_LIMIT := 1048576

func _min(a, b):
    if a < b:
        return a
    return b

class Reader:
    func init():
        self._buffer = ""
        self._eof = false
        self.closed = false

    # À redéfinir : jusqu'à max octets de la source ("" : fin), ou TimeoutError.
    func _source(max, timeout):
        raise("NotImplementedError", "Reader._source : à redéfinir")

    func _fill(timeout):
        if self._eof:
            return false
        if self.closed:
            raise("IoError", "flux fermé")
        data := self._source(CHUNK, timeout)
        if data == "":
            self._eof = true
            return false
        self._buffer = self._buffer + data
        return true

    func _take(n):
        out := _b.bslice(self._buffer, 0, n)
        self._buffer = _b.bslice(self._buffer, n, _b.blen(self._buffer))
        return out

    func read(max=CHUNK, timeout=null):
        while true:
            n := _b.blen(self._buffer)
            if n > 0:
                k := _min(n, max)
                whole := _b.utf8_prefix(_b.bslice(self._buffer, 0, k))
                if whole > 0:
                    return self._take(whole)
                # max trop petit pour un caractère entier : rendre le premier caractère complet.
                lead := _b.to_bytes(_b.bslice(self._buffer, 0, 1))[0]
                size := 1
                if lead >= 240:
                    size = 4
                elif lead >= 224:
                    size = 3
                elif lead >= 192:
                    size = 2
                if size <= n and _b.utf8_prefix(_b.bslice(self._buffer, 0, size)) == size:
                    return self._take(size)
                if n >= 4:
                    return self._take(k)
            if not self._fill(timeout):
                return self._take(_b.blen(self._buffer))

    func read_bytes(max=CHUNK, timeout=null):
        if _b.blen(self._buffer) == 0:
            self._fill(timeout)
        return _b.to_bytes(self._take(_min(_b.blen(self._buffer), max)))

    func read_exact(n, timeout=null):
        while _b.blen(self._buffer) < n:
            if not self._fill(timeout):
                raise("IoError", "read_exact : fin du flux après " + str(_b.blen(self._buffer)) + " octets sur " + str(n))
        return self._take(n)

    func read_until(sep, timeout=null, limit=LINE_LIMIT):
        if type(sep) != "str" or sep == "":
            raise("ArgumentError", "read_until : séparateur str non vide attendu")
        start := 0
        while true:
            i := _b.bfind(self._buffer, sep, start)
            if i >= 0:
                out := self._take(i)
                self._take(_b.blen(sep))
                return out
            if _b.blen(self._buffer) > limit:
                raise("IoError", "read_until : plus de " + str(limit) + " octets sans séparateur")
            start = _b.blen(self._buffer) - _b.blen(sep) + 1
            if start < 0:
                start = 0
            if not self._fill(timeout):
                if _b.blen(self._buffer) == 0:
                    return null
                return self._take(_b.blen(self._buffer))

    func read_line(timeout=null, limit=LINE_LIMIT):
        line := self.read_until("\n", timeout, limit)
        if line != null and _b.blen(line) > 0 and _b.bfind(line, "\r", _b.blen(line) - 1) >= 0:
            line = _b.bslice(line, 0, _b.blen(line) - 1)
        return line

    func read_all(timeout=null):
        more := true
        while more:
            more = self._fill(timeout)
        return self._take(_b.blen(self._buffer))

    func lines(timeout=null):
        out := []
        line := self.read_line(timeout)
        while line != null:
            append(out, line)
            line = self.read_line(timeout)
        return out

    # Vrai si la fin du flux est atteinte (sans rien attendre de plus que la lecture en cours).
    func at_end():
        return self._eof and _b.blen(self._buffer) == 0

    func close():
        self.closed = true

class Writer:
    func init():
        self.closed = false

    # À redéfinir : écrit tout data (str).
    func _sink(data):
        raise("NotImplementedError", "Writer._sink : à redéfinir")

    func write(data):
        if self.closed:
            raise("IoError", "flux fermé")
        if type(data) != "str":
            raise("TypeError", "Writer.write : str attendue (obtenu '" + type(data) + "'), voir write_bytes")
        self._sink(data)
        return _b.blen(data)

    func write_line(text=""):
        return self.write(str(text) + "\n")

    func write_bytes(data):
        return self.write(_b.from_bytes(data))

    func flush():
        return null

    func close():
        self.closed = true

# ---------------------------------------------------------------- en mémoire
class StringReader extends Reader:
    func init(text):
        super.init()
        if type(text) != "str":
            raise("TypeError", "StringReader : str attendue")
        self._buffer = text
        self._eof = true

    func _source(max, timeout):
        return ""

class StringWriter extends Writer:
    func init():
        super.init()
        self._parts = []

    func _sink(data):
        append(self._parts, data)

    # Tout ce qui a été écrit.
    func value():
        out := ""
        for p in self._parts:
            out = out + p
        self._parts = [out]
        return out

func from_string(text):
    return StringReader(text)

# ---------------------------------------------------------------- fichiers (module file)
class FileReader extends Reader:
    func init(path):
        super.init()
        self.file = _file.open(path, "rb")

    func _source(max, timeout):
        data := self.file.read(max)
        if type(data) == "list":
            return _b.from_bytes(data)
        return data

    func close():
        if not self.closed:
            self.file.close()
        self.closed = true

class FileWriter extends Writer:
    func init(path, append_to=false):
        super.init()
        mode := "wb"
        if append_to:
            mode = "ab"
        self.file = _file.open(path, mode)

    func _sink(data):
        self.file.write(_b.to_bytes(data))

    func flush():
        self.file.flush()

    func close():
        if not self.closed:
            self.file.close()
        self.closed = true

func open_file(path):
    return FileReader(path)

func create_file(path, append_to=false):
    return FileWriter(path, append_to)

# ---------------------------------------------------------------- descripteurs (tubes, entrée standard)
func _fd_fail(op, code):
    name := _f.errno_name(code)
    if name == "ETIMEDOUT":
        raise("TimeoutError", op + " : délai dépassé")
    raise("IoError", op + " : " + _f.strerror(code) + " [" + name + "]")

class FdReader extends Reader:
    # owned : close() ferme aussi le descripteur.
    func init(fd, owned=false):
        super.init()
        self.fd = fd
        self.owned = owned

    func _source(max, timeout):
        r := _f.read(self.fd, max, timeout)
        if r == null:
            raise("TimeoutError", "lecture du descripteur " + str(self.fd) + " : délai dépassé")
        if type(r) == "int":
            _fd_fail("lecture du descripteur " + str(self.fd), r)
        return r

    func close():
        if not self.closed and self.owned:
            _f.close(self.fd)
        self.closed = true

class FdWriter extends Writer:
    func init(fd, owned=false, timeout=null):
        super.init()
        self.fd = fd
        self.owned = owned
        self.timeout = timeout

    func _sink(data):
        r := _f.write(self.fd, data, self.timeout)
        if r < 0:
            _fd_fail("écriture sur le descripteur " + str(self.fd), r)

    func close():
        if not self.closed and self.owned:
            _f.close(self.fd)
        self.closed = true

# Entrée standard en flux (octets bruts, sans la conversion de input()).
func stdin():
    return FdReader(0)

class _StdWriter extends Writer:
    func init(err):
        super.init()
        self.err = err

    func _sink(data):
        if self.err:
            _cli.write_err(data)
        else:
            _cli.write_out(data)

    func flush():
        _cli.flush()

func stdout():
    return _StdWriter(false)

# Flux standard en binaire (enabled) ou en texte : sous Windows, le mode texte change LF en CR LF à l'écriture
# et CR LF en LF à la lecture ; à désactiver avant d'écrire ou de lire des octets bruts (tube vers un autre
# programme). Sans effet ailleurs. Rend vrai si le mode texte était actif.
func binary_stdio(enabled=true):
    return _cli.text_mode(not enabled)

func stderr():
    return _StdWriter(true)

# ---------------------------------------------------------------- processus fils (module process)
class ProcessReader extends Reader:
    # stream : "stdout" ou "stderr" d'un process.Process lancé avec ce flux en "pipe".
    func init(proc, stream="stdout"):
        super.init()
        self.proc = proc
        self.stream = stream

    func _source(max, timeout):
        data := self.proc.read(self.stream, max, timeout)
        if data == null:
            return ""
        return data

class ProcessWriter extends Writer:
    func init(proc):
        super.init()
        self.proc = proc

    func _sink(data):
        self.proc.write(data)

    func close():
        if not self.closed:
            self.proc.close_stdin()
        self.closed = true

# ---------------------------------------------------------------- outils
# Copie tout reader dans writer ; renvoie le nombre d'octets copiés.
func copy(reader, writer, timeout=null):
    total := 0
    while true:
        chunk := reader.read(CHUNK, timeout)
        if chunk == "":
            writer.flush()
            return total
        total += writer.write(chunk)
