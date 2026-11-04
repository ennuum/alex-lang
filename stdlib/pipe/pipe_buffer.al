# ALEX STANDARD LIBRARY — pipe.pipe_buffer
#
# PipeBuffer : un tube EN MÉMOIRE, borné, à la sémantique d'un vrai tube (FIFO d'octets, fin de flux quand
# l'écrivain ferme) — pour relier deux parties d'un même programme, tester du code de tube sans descripteur,
# ou absorber la sortie d'un producteur plus rapide que son consommateur.
#
#   use pipe.pipe_buffer as pbuf
#   b := pbuf.PipeBuffer(1024)
#   b.write("ligne 1\nligne 2\n")
#   print(b.read_line())              # « ligne 1 »
#   print(b.available())              # octets en attente
#   b.close_write()
#   print(b.read_all())               # « ligne 2\n » puis "" : fin du flux
#   r := b.reader()                   # io.stream.Reader sur le tampon (read_line, lines, read_until...)
#   w := b.writer()                   # io.stream.Writer
#
# write() n'attend jamais : s'il n'y a pas assez de place, il écrit ce qui tient et renvoie le nombre
# d'octets acceptés (strict=true : CapacityError sans rien écrire). Les longueurs sont en OCTETS (UTF-8).
# Erreurs : PipeClosedError (écriture après close_write), CapacityError, TypeError.

from core use len, type
from collections use append
use string as _s
from io.stream use Reader, Writer
use pipe.pipe_errors as _e

class PipeBuffer:
    func init(capacity=65536):
        if type(capacity) != "int" or capacity < 1:
            raise("ArgumentError", "PipeBuffer : capacité >= 1 octet attendue")
        self.capacity = capacity
        self._data = ""
        self._n = 0
        self._closed = false
        self.total_written = 0
        self.total_read = 0
        self.high_water = 0

    func available():
        return self._n

    func free_space():
        return self.capacity - self._n

    func is_empty():
        return self._n == 0

    func is_full():
        return self._n >= self.capacity

    func is_write_closed():
        return self._closed

    # Fin du flux : écrivain fermé ET plus rien à lire.
    func at_end():
        return self._closed and self._n == 0

    # Écrit ce qui tient ; renvoie le nombre d'octets acceptés.
    func write(text, strict=false):
        if self._closed:
            _e.closed("PipeBuffer.write")
        if type(text) != "str":
            raise("TypeError", "PipeBuffer.write : str attendue (obtenu '" + type(text) + "')")
        n := _s.byte_len(text)
        room := self.capacity - self._n
        if n > room:
            if strict:
                raise("CapacityError", "PipeBuffer.write : " + str(n) + " octets, " + str(room) + " libres")
            # Coupe sur une frontière de caractère UTF-8.
            k := room
            while k > 0 and (_s.byte_at(text, k) & 0xC0) == 0x80:
                k -= 1
            text = _s.byte_slice(text, 0, k)
            n = k
        self._data = self._data + text
        self._n += n
        self.total_written += n
        if self._n > self.high_water:
            self.high_water = self._n
        return n

    func write_line(text=""):
        return self.write(text + "\n")

    func _take(n):
        k := n
        if k > self._n:
            k = self._n
        while k < self._n and k > 0 and (_s.byte_at(self._data, k) & 0xC0) == 0x80:
            k -= 1
        out := _s.byte_slice(self._data, 0, k)
        self._data = _s.byte_slice(self._data, k, self._n)
        self._n -= k
        self.total_read += k
        return out

    # Jusqu'à max octets disponibles ; "" à la fin du flux ; null si vide mais l'écrivain est ouvert.
    func read(max=65536):
        if self._n == 0:
            if self._closed:
                return ""
            return null
        return self._take(max)

    # Une ligne sans « \n » ; null si aucune ligne complète (ou fin du flux et tampon vide).
    func read_line():
        i := _s.byte_find(self._data, "\n", 0)
        if i < 0:
            if self._closed and self._n > 0:
                return self._take(self._n)
            return null
        line := self._take(i + 1)
        line = _s.byte_slice(line, 0, _s.byte_len(line) - 1)
        if _s.ends_with(line, "\r"):
            line = _s.byte_slice(line, 0, _s.byte_len(line) - 1)
        return line

    # Lignes complètes disponibles.
    func read_lines():
        out := []
        while true:
            l := self.read_line()
            if l == null:
                return out
            append(out, l)

    func read_all():
        return self._take(self._n)

    func peek(max=65536):
        k := max
        if k > self._n:
            k = self._n
        return _s.byte_slice(self._data, 0, k)

    func close_write():
        self._closed = true

    func clear():
        self._data = ""
        self._n = 0

    func reader():
        return BufferReader(self)

    func writer():
        return BufferWriter(self)

    func stats():
        return {"capacity": self.capacity, "available": self._n, "written": self.total_written,
                "read": self.total_read, "high_water": self.high_water, "closed": self._closed}

class BufferReader extends Reader:
    func init(buffer):
        super.init()
        self._b = buffer

    func _source(max, timeout):
        v := self._b.read(max)
        if v == null:
            # Écrivain ouvert mais rien à lire : en mémoire, personne ne peut écrire pendant qu'on attend.
            raise(_e.TIMEOUT, "PipeBuffer : aucune donnée disponible (écrivain encore ouvert)")
        return v

class BufferWriter extends Writer:
    func init(buffer):
        super.init()
        self._b = buffer

    func _sink(data):
        return self._b.write(data, true)

    func close():
        self._b.close_write()
