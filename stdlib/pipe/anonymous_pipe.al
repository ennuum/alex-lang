# ALEX STANDARD LIBRARY — pipe.anonymous_pipe
#
# Tubes anonymes : un canal d'octets à sens unique entre deux bouts (lecture, écriture) d'un même processus, de
# deux fils (concurrency.thread / thread : le bout passe par son numéro de descripteur) ou d'un parent et de son
# fils (process.Command(...).stdin(tube.reader)). Et tubes DUPLEX (deux sens, une paire de sockets locaux).
#
#   use pipe.anonymous_pipe as ap
#   t := ap.AnonymousPipe()
#   t.send("bonjour\n")
#   print(t.receive_line(1.0))             # « bonjour »
#   t.close()
#
#   d := ap.duplex()                       # deux extrémités reliées : d[0], d[1]
#   a := d[0]
#   b := d[1]
#   a.send_line("ping")
#   print(b.read_line(1.0))                # « ping »
#   b.send_line("pong")
#   print(a.read_line(1.0))                # « pong »
#
# Les bouts sont des flux io.stream (read, read_line, read_all, write, write_line...). Pour qu'un lecteur voie
# la fin du flux, TOUS les bouts d'écriture doivent être fermés (y compris la copie gardée par le parent après
# l'avoir donnée à un fils).
#
# Erreurs : IoError (système ; « [EPIPE] » si plus personne ne lit), TimeoutError, ArgumentError.

from core use len, type
use io.pipe as _iop
from io.stream use Reader, Writer
use _native_fd as _f
use _native_net as _n

func supported():
    return _f.supported()

class AnonymousPipe:
    func init():
        p := _iop.Pipe()
        self.reader = p.reader
        self.writer = p.writer

    # [descripteur de lecture, descripteur d'écriture]
    func fds():
        return [self.reader.fd, self.writer.fd]

    # Écrit tout le texte (bloque si le tube est plein, 64 Kio sous Linux, jusqu'à ce qu'on le lise).
    func send(text):
        return self.writer.write(text)

    func send_line(text):
        return self.writer.write_line(text)

    # Jusqu'à max octets ("" : fin du flux, tous les écrivains fermés) ; TimeoutError après timeout secondes.
    func receive(max=65536, timeout=null):
        return self.reader.read(max, timeout)

    # Une ligne sans « \n » ; null : fin du flux.
    func receive_line(timeout=null):
        return self.reader.read_line(timeout)

    # Vrai si des données attendent d'être lues (sans bloquer).
    func readable():
        if not self.reader.closed and len(self.reader._buffer) > 0:
            return true
        if self.reader.closed:
            return false
        r := _f.poll([[self.reader.fd, "r"]], 0)
        return type(r) == "list" and len(r) > 0

    func close_reader():
        self.reader.close()

    # Ferme l'écriture : le lecteur verra la fin du flux.
    func close_writer():
        self.writer.close()

    func close():
        self.reader.close()
        self.writer.close()

    func closed():
        return self.reader.closed and self.writer.closed

# Nouveau tube anonyme.
func create():
    return AnonymousPipe()

# Bouts adoptés à partir de leurs descripteurs (reçus d'un autre fil, ou hérités).
func reader_from_fd(fd):
    return _iop.reader_from_fd(fd)

func writer_from_fd(fd):
    return _iop.writer_from_fd(fd)

# ---------------------------------------------------------------- duplex

func _sock_fail(op, code):
    name := _n.errno_name(code)
    if name == "ETIMEDOUT" or name == "EAGAIN":
        raise("TimeoutError", op + " : délai dépassé")
    raise("IoError", op + " : " + _n.strerror(code) + " [" + name + "]")

class _SockReader extends Reader:
    func init(h):
        super.init()
        self.h = h

    func _source(max, timeout):
        r := _n.recv(self.h, max, timeout)
        if type(r) == "int":
            _sock_fail("lecture du tube duplex", r)
        return r

class _SockWriter extends Writer:
    func init(h, timeout):
        super.init()
        self.h = h
        self.timeout = timeout

    func _sink(data):
        r := _n.send(self.h, data, self.timeout)
        if r < 0:
            _sock_fail("écriture sur le tube duplex", r)

# Une extrémité d'un tube duplex : on lit ce que l'autre écrit, et inversement.
class DuplexEnd:
    func init(h):
        self._h = h
        self.reader = _SockReader(h)
        self.writer = _SockWriter(h, null)
        self.closed = false

    # Descripteur système (pour process.Command(...).stdin(fd) / stdout(fd)).
    func fd():
        return _n.fd(self._h)

    func send(text):
        return self.writer.write(text)

    func send_line(text):
        return self.writer.write_line(text)

    func read(max=65536, timeout=null):
        return self.reader.read(max, timeout)

    func read_line(timeout=null):
        return self.reader.read_line(timeout)

    func read_exact(n, timeout=null):
        return self.reader.read_exact(n, timeout)

    func read_all(timeout=null):
        return self.reader.read_all(timeout)

    # Ferme le sens écriture : l'autre extrémité lit la fin du flux, mais peut encore répondre.
    func close_write():
        _n.shutdown(self._h, "write")

    func close():
        if not self.closed:
            _n.close(self._h)
            self.closed = true
            self.reader.closed = true
            self.writer.closed = true

# Deux extrémités reliées (socketpair local) : (a, b).
func duplex():
    r := _n.socketpair("tcp")
    if type(r) == "int":
        _sock_fail("duplex", r)
    return (DuplexEnd(r[0]), DuplexEnd(r[1]))
