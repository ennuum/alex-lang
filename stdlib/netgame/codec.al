# ALEX STANDARD LIBRARY — netgame.codec
#
# Sérialisation binaire compacte pour le réseau de jeu : entiers à longueur variable (LEB128, zigzag pour les
# signés), réels quantifiés (fixed), réels 64 bits exacts, chaînes d'octets, et valeurs quelconques étiquetées
# (null, bool, int, float, str, list, dict) pour les messages.
#
#   use netgame.codec as nc
#   w := nc.Writer()
#   w.uint(42)
#   w.fixed(3.14159, 0.01)            # 314 en zigzag : 2 octets
#   w.value({"t": "chat", "texte": "salut"})
#   r := nc.Reader(w.bytes())
#   r.uint()  r.fixed(0.01)  r.value()
#
# Les données circulent en `str` d'octets (comme network.udp) ; bytes() rend une list[int], data() une str.
# Erreurs : ValueError (paquet tronqué ou invalide).

from core use len, type, to_int
from collections use append, keys
use math
use ffi
use _native_net as _n

_f64 := [null]

func _scratch():
    if _f64[0] == null:
        _f64[0] = ffi.Buffer(8)
    return _f64[0]

func to_str(b):
    if type(b) == "str":
        return b
    return _n.from_bytes(b)

func to_bytes(s):
    if type(s) == "list":
        return s
    return _n.to_bytes(s)

func quantize(v, scale):
    return to_int(math.floor(v / scale + 0.5))

class Writer:
    func init():
        self.b = []

    func u8(v):
        append(self.b, v & 255)

    func u16(v):
        append(self.b, v & 255)
        append(self.b, (v >> 8) & 255)

    func u32(v):
        append(self.b, v & 255)
        append(self.b, (v >> 8) & 255)
        append(self.b, (v >> 16) & 255)
        append(self.b, (v >> 24) & 255)

    # Entier >= 0, 7 bits par octet.
    func uint(v):
        if v < 0:
            raise("ValueError", "netgame.codec : uint négatif (" + str(v) + ")")
        while v >= 128:
            append(self.b, (v & 127) | 128)
            v = v >> 7
        append(self.b, v)

    # Entier signé (zigzag : petits négatifs courts).
    func sint(v):
        if v >= 0:
            self.uint(v * 2)
        else:
            self.uint(-v * 2 - 1)

    func flag(v):
        append(self.b, 1 if v else 0)

    # Réel arrondi au multiple de scale (0.01 : centièmes).
    func fixed(v, scale):
        self.sint(quantize(v, scale))

    func f64(v):
        s := _scratch()
        s.write("f64", v * 1.0)
        for x in s.read_array("u8", 8):
            append(self.b, x)

    # Octets (str ou list[int]) précédés de leur longueur.
    func blob(d):
        b := to_bytes(d)
        self.uint(len(b))
        for x in b:
            append(self.b, x)

    func text(s):
        self.blob(s)

    # Octets bruts sans longueur.
    func raw(d):
        for x in to_bytes(d):
            append(self.b, x)

    # Valeur étiquetée : null, bool, int, float, str, list / tuple, dict.
    func value(v):
        t := type(v)
        if v == null:
            append(self.b, 0)
        elif t == "bool":
            append(self.b, 2 if v else 1)
        elif t == "int":
            append(self.b, 3)
            self.sint(v)
        elif t == "float":
            append(self.b, 4)
            self.f64(v)
        elif t == "str":
            append(self.b, 5)
            self.blob(v)
        elif t == "list" or t == "tuple":
            append(self.b, 6)
            self.uint(len(v))
            for x in v:
                self.value(x)
        elif t == "dict":
            append(self.b, 7)
            ks := keys(v)
            self.uint(len(ks))
            for k in ks:
                self.value(k)
                self.value(v[k])
        else:
            raise("ValueError", "netgame.codec : type non transmissible '" + t + "'")

    func size():
        return len(self.b)

    func bytes():
        return self.b

    func data():
        return _n.from_bytes(self.b)

class Reader:
    func init(data, pos=0):
        self.b = to_bytes(data)
        self.pos = pos

    func _need(n):
        if self.pos + n > len(self.b):
            raise("ValueError", "netgame.codec : paquet tronqué")

    func remaining():
        return len(self.b) - self.pos

    func at_end():
        return self.pos >= len(self.b)

    func u8():
        self._need(1)
        v := self.b[self.pos]
        self.pos += 1
        return v

    func u16():
        self._need(2)
        v := self.b[self.pos] | (self.b[self.pos + 1] << 8)
        self.pos += 2
        return v

    func u32():
        self._need(4)
        p := self.pos
        v := self.b[p] | (self.b[p + 1] << 8) | (self.b[p + 2] << 16) | (self.b[p + 3] << 24)
        self.pos += 4
        return v

    func uint():
        v := 0
        sh := 0
        while true:
            self._need(1)
            c := self.b[self.pos]
            self.pos += 1
            v = v | ((c & 127) << sh)
            if c < 128:
                return v
            sh += 7
            if sh > 63:
                raise("ValueError", "netgame.codec : entier trop long")

    func sint():
        z := self.uint()
        if (z & 1) == 0:
            return z >> 1
        return -(z >> 1) - 1

    func flag():
        return self.u8() != 0

    func fixed(scale):
        return self.sint() * scale

    func f64():
        self._need(8)
        s := _scratch()
        s.write_array("u8", self.b[self.pos:self.pos + 8])
        self.pos += 8
        return s.read("f64")

    func blob_bytes():
        n := self.uint()
        self._need(n)
        r := self.b[self.pos:self.pos + n]
        self.pos += n
        return r

    func blob():
        return _n.from_bytes(self.blob_bytes())

    func text():
        return self.blob()

    func raw(n):
        self._need(n)
        r := self.b[self.pos:self.pos + n]
        self.pos += n
        return r

    func value(depth=0):
        if depth > 64:
            raise("ValueError", "netgame.codec : imbrication trop profonde")
        t := self.u8()
        if t == 0:
            return null
        if t == 1:
            return false
        if t == 2:
            return true
        if t == 3:
            return self.sint()
        if t == 4:
            return self.f64()
        if t == 5:
            return self.blob()
        if t == 6:
            n := self.uint()
            if n > self.remaining():
                raise("ValueError", "netgame.codec : liste invalide")
            out := []
            k := 0
            while k < n:
                append(out, self.value(depth + 1))
                k += 1
            return out
        if t == 7:
            n := self.uint()
            if n > self.remaining():
                raise("ValueError", "netgame.codec : dictionnaire invalide")
            d := {}
            k := 0
            while k < n:
                key := self.value(depth + 1)
                d[key] = self.value(depth + 1)
                k += 1
            return d
        raise("ValueError", "netgame.codec : étiquette inconnue " + str(t))

# Valeur -> octets (list[int]) et retour.
func encode(v):
    w := Writer()
    w.value(v)
    return w.bytes()

func decode(b):
    return Reader(b).value()

# Somme FNV-1a 32 bits d'une valeur (détection de désynchronisation).
func checksum(v):
    h := 2166136261
    for x in encode(v):
        h = ((h ^ x) * 16777619) & 4294967295
    return h

# Copie profonde de listes / dictionnaires (états de simulation).
func deep_copy(v):
    t := type(v)
    if t == "list":
        return [deep_copy(x) for x in v]
    if t == "dict":
        d := {}
        for k in keys(v):
            d[k] = deep_copy(v[k])
        return d
    return v
