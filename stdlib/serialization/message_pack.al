# ALEX STANDARD LIBRARY — serialization.message_pack
#
# MessagePack (msgpack.org) : format binaire standard, lu par la plupart des langages. Encodage/décodage
# conformes à la spécification : nil, booléens, entiers (fixint, 8 à 64 bits signés et non signés), flottants
# (64 bits à l'écriture ; 32 et 64 bits à la lecture), texte (fixstr, str8/16/32), binaire (bin8/16/32 via
# Binary), tableaux, tables (map), et extensions (Ext : type + octets).
#
#   use serialization.message_pack as mp
#   b := mp.packb({"compact": true, "schema": 0})       # str d'octets : 82 a7 compact c3 a6 schema 00
#   print(mp.hex(b))
#   print(mp.unpackb(b))
#   o := mp.dumps(Point(1, 2))                          # instances via serializer (« __type__ »)
#   x := mp.unpackb(mp.packb(mp.binary([1, 2, 3])))      # Binary
#
# Les entiers ALEX sont signés 64 bits : un uint64 > 2^63-1 lu dans un message lève FormatError.
# Erreurs : FormatError (octets invalides ou tronqués), SerializationError (type non représentable).

from core use len, type
from collections use append
use string as _s
use serialization._bytes as _b
from serialization._bytes use Binary
use serialization.serializer as _ser
use serialization.serialization_errors as _e

class Ext:
    func init(code, data):
        self.code = code
        self.data = data

    func __eq__(other):
        return isinstance(other, Ext) and other.code == self.code and other.data == self.data

    func __str__():
        return "Ext(" + str(self.code) + ", " + str(_s.byte_len(self.data)) + " octets)"

func _int(n, out):
    if n >= 0:
        if n < 128:
            append(out, _b.u8(n))
        elif n < 256:
            append(out, _b.u8(204))
            append(out, _b.u8(n))
        elif n < 65536:
            append(out, _b.u8(205))
            append(out, _b.be(n, 2))
        elif n < 4294967296:
            append(out, _b.u8(206))
            append(out, _b.be(n, 4))
        else:
            append(out, _b.u8(207))
            append(out, _b.be(n, 8))
    else:
        if n >= -32:
            append(out, _b.u8(n & 255))
        elif n >= -128:
            append(out, _b.u8(208))
            append(out, _b.u8(n & 255))
        elif n >= -32768:
            append(out, _b.u8(209))
            append(out, _b.be(n & 65535, 2))
        elif n >= -2147483648:
            append(out, _b.u8(210))
            append(out, _b.be(n & 4294967295, 4))
        else:
            append(out, _b.u8(211))
            append(out, _b.be(n, 8))

func _len_head(n, fix_base, fix_max, c8, c16, c32, out):
    if fix_base != null and n <= fix_max:
        append(out, _b.u8(fix_base | n))
    elif c8 != null and n < 256:
        append(out, _b.u8(c8))
        append(out, _b.u8(n))
    elif n < 65536:
        append(out, _b.u8(c16))
        append(out, _b.be(n, 2))
    else:
        append(out, _b.u8(c32))
        append(out, _b.be(n, 4))

func _pack(v, out):
    t := type(v)
    if t == "null":
        append(out, _b.u8(192))
    elif t == "bool":
        if v:
            append(out, _b.u8(195))
        else:
            append(out, _b.u8(194))
    elif t == "int":
        _int(v, out)
    elif t == "float":
        append(out, _b.u8(203))
        append(out, _b.f64(v))
    elif t == "str" or t == "char":
        sv := str(v)
        _len_head(_s.byte_len(sv), 160, 31, 217, 218, 219, out)
        append(out, sv)
    elif t == "list" or t == "tuple":
        n := 0
        for x in v:
            n += 1
        _len_head(n, 144, 15, null, 220, 221, out)
        for x in v:
            _pack(x, out)
    elif t == "dict":
        _len_head(len(v), 128, 15, null, 222, 223, out)
        for k in v:
            _pack(k, out)
            _pack(v[k], out)
    elif t == "instance" and isinstance(v, Binary):
        _len_head(v.size(), null, 0, 196, 197, 198, out)
        append(out, v.data)
    elif t == "instance" and isinstance(v, Ext):
        n := _s.byte_len(v.data)
        fixes := {1: 212, 2: 213, 4: 214, 8: 215, 16: 216}
        if n in fixes:
            append(out, _b.u8(fixes[n]))
        elif n < 256:
            append(out, _b.u8(199))
            append(out, _b.u8(n))
        elif n < 65536:
            append(out, _b.u8(200))
            append(out, _b.be(n, 2))
        else:
            append(out, _b.u8(201))
            append(out, _b.be(n, 4))
        append(out, _b.u8(v.code & 255))
        append(out, v.data)
    else:
        _e.cannot_serialize("", "MessagePack : type '" + t + "' (passer par dumps / serializer)")

# Données simples (+ Binary, Ext) -> octets MessagePack.
func packb(value):
    out := []
    _pack(value, out)
    return _b.join(out)

class _R:
    func init(d):
        self.d = d
        self.p = 0
        self.n = _s.byte_len(d)

    func need(k):
        if self.p + k > self.n:
            _e.bad_format("MessagePack", "données tronquées (position " + str(self.p) + ")")

    func u(k):
        self.need(k)
        v := _b.read_be(self.d, self.p, k)
        self.p += k
        return v

    func i(k):
        self.need(k)
        v := _b.read_be(self.d, self.p, k, true)
        self.p += k
        return v

    func take(k):
        self.need(k)
        out := _s.byte_slice(self.d, self.p, self.p + k)
        self.p += k
        return out

func _arr(r, n):
    out := []
    k := 0
    while k < n:
        append(out, _unpack(r))
        k += 1
    return out

func _map(r, n):
    out := {}
    k := 0
    while k < n:
        key := _unpack(r)
        out[key] = _unpack(r)
        k += 1
    return out

func _unpack(r):
    c := r.u(1)
    if c < 128:
        return c
    if c >= 224:
        return c - 256
    if c >= 128 and c <= 143:
        return _map(r, c & 15)
    if c >= 144 and c <= 159:
        return _arr(r, c & 15)
    if c >= 160 and c <= 191:
        return r.take(c & 31)
    if c == 192:
        return null
    if c == 194:
        return false
    if c == 195:
        return true
    if c == 196:
        return Binary(r.take(r.u(1)))
    if c == 197:
        return Binary(r.take(r.u(2)))
    if c == 198:
        return Binary(r.take(r.u(4)))
    if c == 199 or c == 200 or c == 201:
        w := 1
        if c == 200:
            w = 2
        if c == 201:
            w = 4
        n := r.u(w)
        code := r.i(1)
        return Ext(code, r.take(n))
    if c == 202:
        r.need(4)
        v := _b.read_f32(r.d, r.p)
        r.p += 4
        return v
    if c == 203:
        r.need(8)
        v := _b.read_f64(r.d, r.p)
        r.p += 8
        return v
    if c == 204:
        return r.u(1)
    if c == 205:
        return r.u(2)
    if c == 206:
        return r.u(4)
    if c == 207:
        r.need(8)
        if _s.byte_at(r.d, r.p) >= 128:
            _e.bad_format("MessagePack", "uint64 > 2^63-1 non représentable")
        return r.u(8)
    if c == 208:
        return r.i(1)
    if c == 209:
        return r.i(2)
    if c == 210:
        return r.i(4)
    if c == 211:
        return r.i(8)
    if c >= 212 and c <= 216:
        sizes := {212: 1, 213: 2, 214: 4, 215: 8, 216: 16}
        code := r.i(1)
        return Ext(code, r.take(sizes[c]))
    if c == 217:
        return r.take(r.u(1))
    if c == 218:
        return r.take(r.u(2))
    if c == 219:
        return r.take(r.u(4))
    if c == 220:
        return _arr(r, r.u(2))
    if c == 221:
        return _arr(r, r.u(4))
    if c == 222:
        return _map(r, r.u(2))
    if c == 223:
        return _map(r, r.u(4))
    _e.bad_format("MessagePack", "octet de type 0xc1 (réservé) à la position " + str(r.p - 1))

func unpackb(data):
    if type(data) != "str":
        raise("TypeError", "message_pack.unpackb : str d'octets attendue")
    r := _R(data)
    v := _unpack(r)
    if r.p != r.n:
        _e.bad_format("MessagePack", str(r.n - r.p) + " octets en trop")
    return v

# Plusieurs valeurs MessagePack concaténées (flux).
func unpack_stream(data):
    r := _R(data)
    out := []
    while r.p < r.n:
        append(out, _unpack(r))
    return out

_raw := _ser.Serializer("__type__", false, false, false, 128, ["Binary", "Ext"])

func dumps(value):
    return packb(_raw.to_data(value))

func loads(data, deserializer=null):
    d := unpackb(data)
    if deserializer == null:
        return d
    return deserializer.from_data(d)

func hex(data):
    digits := "0123456789abcdef"
    out := []
    for b in _s.byte_unpack(data):
        append(out, str(digits[b // 16]) + str(digits[b % 16]))
    return _s.join(" ", out)

# Charge utile binaire (octets, et non texte) : str d'octets ou liste d'entiers 0..255.
func binary(data):
    return Binary(data)
