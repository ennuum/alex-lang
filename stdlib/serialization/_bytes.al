# ALEX STANDARD LIBRARY — serialization._bytes (interne)
#
# Octets pour les formats binaires : une suite d'octets est une str d'octets (string.byte_*), comme le rend
# file.read / io.read_file en binaire. Entiers en gros-boutiste, flottants IEEE 754 (via memory.buffer).

from core use len, type
from collections use append
use string as _s
use memory.buffer as _buf

class Binary:
    # Octets à encoder comme binaire (et non comme texte) : data = str d'octets ou liste d'entiers 0..255.
    func init(data):
        if type(data) == "list":
            data = _s.byte_pack(data)
        if type(data) != "str":
            raise("TypeError", "Binary : str d'octets ou liste d'entiers attendue")
        self.data = data

    func size():
        return _s.byte_len(self.data)

    func to_list():
        return _s.byte_unpack(self.data)

    func __eq__(other):
        return isinstance(other, Binary) and other.data == self.data

    func __str__():
        return "Binary(" + str(self.size()) + " octets)"

func u8(n):
    return _s.byte_char(n & 255)

func be(n, width):
    out := []
    i := width - 1
    while i >= 0:
        append(out, (n >> (8 * i)) & 255)
        i -= 1
    return _s.byte_pack(out)

func read_be(data, pos, width, signed=false):
    v := 0
    i := 0
    while i < width:
        v = (v << 8) | _s.byte_at(data, pos + i)
        i += 1
    if signed and width < 8:
        top := 1 << (8 * width - 1)
        if v >= top:
            v = v - (top << 1)
    return v

func f64(x):
    b := _buf.Buffer(8)
    b.write("f64", x * 1.0, 0, true)
    out := b.read_bytes(0, 8)
    b.free()
    return out

func f32(x):
    b := _buf.Buffer(4)
    b.write("f32", x * 1.0, 0, true)
    out := b.read_bytes(0, 4)
    b.free()
    return out

func read_f64(data, pos):
    b := _buf.from_bytes(_s.byte_slice(data, pos, pos + 8))
    v := b.read("f64", 0, true)
    b.free()
    return v

func read_f32(data, pos):
    b := _buf.from_bytes(_s.byte_slice(data, pos, pos + 4))
    v := b.read("f32", 0, true)
    b.free()
    return v

# Entier non signé à longueur variable (LEB128).
func varint(n):
    out := []
    v := n
    while true:
        b := v & 127
        v = v >> 7
        if v == 0:
            append(out, b)
            break
        append(out, b | 128)
    return _s.byte_pack(out)

# [valeur, position suivante].
func read_varint(data, pos):
    v := 0
    shift := 0
    p := pos
    while true:
        b := _s.byte_at(data, p)
        p += 1
        v = v | ((b & 127) << shift)
        if (b & 128) == 0:
            return [v, p]
        shift += 7
        if shift > 63:
            raise("FormatError", "varint trop long")

func zigzag(n):
    if n >= 0:
        return n << 1
    return ((-n) << 1) - 1

func unzigzag(z):
    if (z & 1) == 0:
        return z >> 1
    return -((z + 1) >> 1)

func join(parts):
    return _s.byte_join(parts)

func length(data):
    return _s.byte_len(data)

func slice(data, a, b):
    return _s.byte_slice(data, a, b)

func at(data, i):
    return _s.byte_at(data, i)
