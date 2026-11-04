# ALEX STANDARD LIBRARY — serialization.binary
#
# Format binaire compact d'ALEX (« ALXB ») : autodescriptif, typé, sans perte pour les données simples, les
# octets (Binary) et les instances (via serializer). Plus petit et plus rapide à relire que JSON ; idéal pour
# les caches, l'IPC (ipc.shared_memory, files de messages) et les fichiers d'état.
#
#   use serialization.binary as bin
#   b := bin.dumps({"id": 7, "tags": ["a", "b"], "ok": true, "x": 1.5})   # str d'octets
#   print(bin.loads(b))
#   print(bin.size_of([1, 2, 3]))                  # octets nécessaires
#   bin.dump_file("etat.bin", etat)
#   v := bin.load_file("etat.bin")
#   raw := bin.binary([0, 255, 16])                # charge utile binaire (non texte)
#
# Structure : "ALXB" + version (1 octet) + valeur. Valeur = étiquette (1 octet) + contenu :
#   0 null · 1 false · 2 true · 3 entier (zigzag + varint) · 4 flottant (f64 gros-boutiste)
#   5 texte (longueur varint + UTF-8) · 6 liste (nombre + valeurs) · 7 dict (nombre + paires) · 8 octets
#   9 objet (nom de type + dict de champs)
# Erreurs : FormatError (octets invalides, version inconnue), SerializationError.

from core use len, type
from collections use append
use string as _s
use io as _io
use file as _file
use serialization._bytes as _b
from serialization._bytes use Binary
use serialization.serializer as _ser
use serialization.deserializer as _des
use serialization.serialization_errors as _e

const MAGIC := "ALXB"
const VERSION := 1

func _enc(v, out):
    t := type(v)
    if t == "null":
        append(out, _b.u8(0))
    elif t == "bool":
        if v:
            append(out, _b.u8(2))
        else:
            append(out, _b.u8(1))
    elif t == "int":
        append(out, _b.u8(3))
        append(out, _b.varint(_b.zigzag(v)))
    elif t == "float":
        append(out, _b.u8(4))
        append(out, _b.f64(v))
    elif t == "str":
        append(out, _b.u8(5))
        append(out, _b.varint(_s.byte_len(v)))
        append(out, v)
    elif t == "list":
        append(out, _b.u8(6))
        append(out, _b.varint(len(v)))
        for x in v:
            _enc(x, out)
    elif t == "dict":
        if "__type__" in v:
            append(out, _b.u8(9))
            _enc(v["__type__"], out)
            rest := {}
            for k in v:
                if k != "__type__":
                    rest[k] = v[k]
            _enc(rest, out)
            return
        append(out, _b.u8(7))
        append(out, _b.varint(len(v)))
        for k in v:
            _enc(k, out)
            _enc(v[k], out)
    elif t == "instance" and isinstance(v, Binary):
        append(out, _b.u8(8))
        append(out, _b.varint(v.size()))
        append(out, v.data)
    else:
        _e.cannot_serialize("", "binaire : type '" + t + "' (passer par serializer.to_data)")

# Données simples -> octets.
func encode_data(data):
    out := [MAGIC, _b.u8(VERSION)]
    _enc(data, out)
    return _b.join(out)

class _Reader:
    func init(data):
        self.d = data
        self.p = 0
        self.n = _s.byte_len(data)

    func need(k):
        if self.p + k > self.n:
            _e.bad_format("binaire", "données tronquées (position " + str(self.p) + ")")

    func byte():
        self.need(1)
        v := _s.byte_at(self.d, self.p)
        self.p += 1
        return v

    func varint():
        self.need(1)
        r := _b.read_varint(self.d, self.p)
        self.p = r[1]
        return r[0]

    func take(k):
        self.need(k)
        out := _s.byte_slice(self.d, self.p, self.p + k)
        self.p += k
        return out

func _dec(r):
    tag := r.byte()
    if tag == 0:
        return null
    if tag == 1:
        return false
    if tag == 2:
        return true
    if tag == 3:
        return _b.unzigzag(r.varint())
    if tag == 4:
        r.need(8)
        v := _b.read_f64(r.d, r.p)
        r.p += 8
        return v
    if tag == 5:
        return r.take(r.varint())
    if tag == 6:
        n := r.varint()
        out := []
        i := 0
        while i < n:
            append(out, _dec(r))
            i += 1
        return out
    if tag == 7:
        n := r.varint()
        out := {}
        i := 0
        while i < n:
            k := _dec(r)
            out[k] = _dec(r)
            i += 1
        return out
    if tag == 8:
        return Binary(r.take(r.varint()))
    if tag == 9:
        name := _dec(r)
        fields := _dec(r)
        out := {"__type__": name}
        for k in fields:
            out[k] = fields[k]
        return out
    _e.bad_format("binaire", "étiquette inconnue " + str(tag) + " (position " + str(r.p - 1) + ")")

# Octets -> données simples.
func decode_data(data):
    if type(data) != "str" or _s.byte_len(data) < 5 or _s.byte_slice(data, 0, 4) != MAGIC:
        _e.bad_format("binaire", "en-tête ALXB absent")
    v := _s.byte_at(data, 4)
    if v > VERSION:
        _e.bad_format("binaire", "version " + str(v) + " non prise en charge")
    r := _Reader(data)
    r.p = 5
    out := _dec(r)
    if r.p != r.n:
        _e.bad_format("binaire", str(r.n - r.p) + " octets en trop après la valeur")
    return out

_raw := _ser.Serializer("__type__", false, false, false, 128, ["Binary"])

func dumps(value):
    return encode_data(_raw.to_data(value))

# deserializer : serialization.deserializer.Deserializer pour reconstruire les instances (sinon dicts).
func loads(data, deserializer=null):
    d := decode_data(data)
    if deserializer == null:
        return d
    return deserializer.from_data(d)

func size_of(value):
    return _s.byte_len(dumps(value))

func dump_file(path, value):
    _io.write_bytes(path, _s.byte_unpack(dumps(value)))

func load_file(path, deserializer=null):
    return loads(_s.byte_pack(_io.read_bytes(path)), deserializer)

func is_binary(data):
    return type(data) == "str" and _s.byte_len(data) >= 5 and _s.byte_slice(data, 0, 4) == MAGIC

# Charge utile binaire (octets, et non texte) : str d'octets ou liste d'entiers 0..255.
func binary(data):
    return Binary(data)
