# ALEX STANDARD LIBRARY — hardware._input (privé)
#
# Lecture des événements bruts des périphériques d'entrée Linux (/dev/input/eventN, interface evdev) :
# struct input_event de 24 octets (machines 64 bits) = horodatage (2 × 8 octets), type (2), code (2),
# valeur (4, signée), petit-boutiste.

from core use len, type
from collections use append
use _native_fd as _f
use _native_net as _b
use hardware._sys as _sys

const EV_SYN := 0
const EV_KEY := 1
const EV_REL := 2
const EV_ABS := 3
const EVENT_SIZE := 24

class Event:
    func init(time, type_, code, value):
        self.time = time
        self.type = type_
        self.code = code
        self.value = value

func _u(bytes, start, count):
    v := 0
    k := count - 1
    while k >= 0:
        v = v * 256 + bytes[start + k]
        k -= 1
    return v

# Décode un événement à partir de 24 octets (list[int]).
func decode(bytes, offset=0):
    sec := _u(bytes, offset, 8)
    usec := _u(bytes, offset + 8, 8)
    value := _u(bytes, offset + 20, 4)
    if value >= 2147483648:
        value = value - 4294967296
    return Event(sec + usec / 1000000.0, _u(bytes, offset + 16, 2), _u(bytes, offset + 18, 2), value)

# Encode un événement (tests, injection dans un fichier).
func encode(type_, code, value, sec=0, usec=0):
    out := []
    for pair in [[sec, 8], [usec, 8], [type_, 2], [code, 2], [value % 4294967296, 4]]:
        v := pair[0]
        k := 0
        while k < pair[1]:
            append(out, v % 256)
            v = v // 256
            k += 1
    return out

class Reader:
    func init(path, op):
        self.path = path
        fd := _f.open_device(_sys.p(path), false)
        if fd < 0:
            name := _f.errno_name(fd)
            hint := ""
            if name == "EACCES" or name == "EPERM":
                hint = " (droits insuffisants : être root ou membre du groupe « input »)"
            _sys.fail(op, "ouverture de " + path + " impossible : " + _f.strerror(fd) + " [" + name + "]" + hint)
        self.fd = fd
        self._buffer = []
        self.closed = false
        self._eof = false

    # Prochain événement brut, ou null après timeout secondes (null : sans limite) ou en fin de fichier.
    func read_event(timeout=null):
        while len(self._buffer) < EVENT_SIZE:
            if self._eof:
                return null
            data := _f.read(self.fd, 4096, timeout)
            if data == null:
                return null
            if type(data) == "int":
                _sys.fail("lecture de " + self.path, _f.strerror(data))
            if data == "":
                self._eof = true
                return null
            for byte in _b.to_bytes(data):
                append(self._buffer, byte)
        ev := decode(self._buffer, 0)
        self._buffer = [self._buffer[i] for i in EVENT_SIZE..len(self._buffer)]
        return ev

    func close():
        if not self.closed:
            _f.close(self.fd)
        self.closed = true
