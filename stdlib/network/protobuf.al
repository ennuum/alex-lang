# ALEX STANDARD LIBRARY — network.protobuf
#
# Protocol Buffers (format binaire « wire format », proto2 / proto3) : encodage bas niveau, schémas déclarés en
# ALEX ou lus depuis un fichier .proto, conversion entre messages binaires et dict.
#
#   Bas niveau   Writer (varint, zigzag, fixed32/64, float, double, bytes, champs) / Reader (lecture)
#   Schéma       s := parse_proto(texte_proto)              messages, énumérations, services (pour gRPC)
#                s := Schema("paquet") ; s.add_message("Point", [field(1, "x", "int32"), field(2, "y", "int32")])
#   Messages     octets := s.encode("Point", {"x": 3, "y": -4})      d := s.decode("Point", octets)
#
# Types : double float int32 int64 uint32 uint64 sint32 sint64 fixed32 fixed64 sfixed32 sfixed64 bool string bytes,
# énumérations (entier, ou nom avec enums_as_names), messages (dict), repeated (list, « packed » par défaut en
# proto3 et accepté dans les deux formes à la lecture), map<K, V> (dict), oneof.
# Un dict décodé contient les valeurs par défaut des champs absents (0, "", false, [], {}; null pour un message),
# sauf include_defaults=false. Les champs inconnus sont ignorés à la lecture.
#
# Limites : uint64 / fixed64 au-delà de 2^63 - 1 sont lus comme des entiers négatifs (entiers 64 bits signés
# d'ALEX) ; pas de groupes (proto2 obsolète), d'extensions ni de types « Any » interprétés.
#
# Erreurs : ProtobufError (données ou schéma invalides), TypeError.
#
# Exemple
#   use network.protobuf as pb
#   s := pb.parse_proto("syntax = \"proto3\"; message Personne { string nom = 1; int32 age = 2; repeated string tags = 3; }")
#   o := s.encode("Personne", {"nom": "Ada", "age": 36, "tags": ["math"]})
#   print(s.decode("Personne", o))       # {nom: Ada, age: 36, tags: [math]}

from core use len, type, to_int, to_float, to_i32, to_u32
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use io as _io

func _fail(message):
    raise("ProtobufError", "protobuf : " + message)

const WIRE_VARINT := 0
const WIRE_I64 := 1
const WIRE_LEN := 2
const WIRE_SGROUP := 3
const WIRE_EGROUP := 4
const WIRE_I32 := 5

const _MASK57 := 144115188075855871
const _MASK63 := 9223372036854775807
const _MIN64 := -9223372036854775807 - 1

# ---------------------------------------------------------------- écriture

class Writer:
    func init():
        self.buf = []

    func byte(b):
        append(self.buf, b & 255)
        return self

    func raw(data):
        for b in _n.to_bytes(data):
            append(self.buf, b)
        return self

    # Entier en varint (un négatif est écrit sur 10 octets, en complément à deux sur 64 bits).
    func varint(v):
        if v < 0:
            append(self.buf, (v & 127) | 128)
            v = (v >> 7) & _MASK57
        while v >= 128:
            append(self.buf, (v & 127) | 128)
            v = v >> 7
        append(self.buf, v)
        return self

    func zigzag(v):
        return self.varint((v << 1) ^ (v >> 63))

    func fixed32(v):
        x := v & 4294967295
        append(self.buf, x & 255)
        append(self.buf, (x >> 8) & 255)
        append(self.buf, (x >> 16) & 255)
        append(self.buf, (x >> 24) & 255)
        return self

    func fixed64(v):
        lo := v & 4294967295
        hi := (v >> 32) & 4294967295
        self.fixed32(lo)
        self.fixed32(hi)
        return self

    func float32(x):
        return self.fixed32(_n.f32_bits(x))

    func float64(x):
        return self.fixed64(_n.f64_bits(x))

    func tag(number, wire):
        return self.varint((number << 3) | wire)

    # Champ de longueur variable (octets bruts).
    func length_delimited(number, data):
        self.tag(number, WIRE_LEN)
        self.varint(_n.blen(data))
        return self.raw(data)

    func size():
        return len(self.buf)

    # Octets produits (str brute).
    func bytes():
        return _n.from_bytes(self.buf)

# ---------------------------------------------------------------- lecture

class Reader:
    func init(data):
        if type(data) == "list":
            self.buf = data
        else:
            self.buf = _n.to_bytes(data)
        self.pos = 0
        self.end = len(self.buf)

    func eof():
        return self.pos >= self.end

    func byte():
        if self.pos >= self.end:
            _fail("message tronqué")
        b := self.buf[self.pos]
        self.pos += 1
        return b

    func varint():
        v := 0
        shift := 0
        while true:
            b := self.byte()
            if shift == 63:
                if (b & 1) != 0:
                    v = v | _MIN64
                if (b & 128) != 0 or b > 1:
                    _fail("varint trop long")
                return v
            v = v | ((b & 127) << shift)
            if (b & 128) == 0:
                return v
            shift += 7
            if shift > 63:
                _fail("varint trop long")

    func zigzag():
        v := self.varint()
        return ((v >> 1) & _MASK63) ^ (-(v & 1))

    func fixed32():
        if self.pos + 4 > self.end:
            _fail("message tronqué (fixed32)")
        b := self.buf
        p := self.pos
        self.pos += 4
        return b[p] | (b[p + 1] << 8) | (b[p + 2] << 16) | (b[p + 3] << 24)

    func fixed64():
        lo := self.fixed32()
        hi := self.fixed32()
        return lo | (hi << 32)

    func float32():
        return _n.bits_f32(self.fixed32())

    func float64():
        return _n.bits_f64(self.fixed64())

    # Octets d'un champ de longueur variable (list[int]).
    func length_delimited():
        n := self.varint()
        if n < 0 or self.pos + n > self.end:
            _fail("longueur de champ invalide (" + str(n) + ")")
        out := self.buf[self.pos:self.pos + n]
        self.pos += n
        return out

    # (numéro, type de fil) du champ suivant.
    func tag():
        t := self.varint()
        number := (t >> 3) & 536870911
        wire := t & 7
        if number == 0:
            _fail("numéro de champ 0 invalide")
        return (number, wire)

    # Saute la valeur d'un champ de type de fil `wire`.
    func skip(wire):
        if wire == WIRE_VARINT:
            self.varint()
        elif wire == WIRE_I64:
            self.pos += 8
        elif wire == WIRE_LEN:
            self.length_delimited()
        elif wire == WIRE_I32:
            self.pos += 4
        elif wire == WIRE_SGROUP:
            while true:
                t := self.tag()
                if t[1] == WIRE_EGROUP:
                    return
                self.skip(t[1])
        else:
            _fail("type de fil invalide " + str(wire))
        if self.pos > self.end:
            _fail("message tronqué")

# Décode un message brut sans schéma : liste de [numéro, type de fil, valeur] (varint/fixed : entier ;
# longueur variable : octets en str brute). Utile pour inspecter un message inconnu.
func decode_raw(data):
    r := Reader(data)
    out := []
    while not r.eof():
        t := r.tag()
        v := null
        if t[1] == WIRE_VARINT:
            v = r.varint()
        elif t[1] == WIRE_I64:
            v = r.fixed64()
        elif t[1] == WIRE_LEN:
            v = _n.from_bytes(r.length_delimited())
        elif t[1] == WIRE_I32:
            v = r.fixed32()
        else:
            r.skip(t[1])
        append(out, [t[0], t[1], v])
    return out

# ---------------------------------------------------------------- descripteurs

const SCALARS := ["double", "float", "int32", "int64", "uint32", "uint64", "sint32", "sint64", "fixed32", "fixed64", "sfixed32", "sfixed64", "bool", "string", "bytes"]

func is_scalar(t):
    for s in SCALARS:
        if s == t:
            return true
    return false

func _wire_of(t):
    if t == "double" or t == "fixed64" or t == "sfixed64":
        return WIRE_I64
    if t == "float" or t == "fixed32" or t == "sfixed32":
        return WIRE_I32
    if t == "string" or t == "bytes" or t == "message" or t == "map":
        return WIRE_LEN
    return WIRE_VARINT

func _packable(t):
    return t != "string" and t != "bytes" and t != "message" and t != "map"

class Field:
    # type : scalaire, "enum" ou "message" (type_name : nom du message / de l'énumération), ou "map"
    # (map_key, map_value, type_name pour une valeur message / enum).
    func init(number, name, type_, label=null, type_name=null, packed=null, oneof=null, map_key=null, map_value=null, json_name=null):
        if type(number) != "int" or number < 1 or number > 536870911 or (number >= 19000 and number <= 19999):
            _fail("numéro de champ invalide " + str(number) + " pour « " + str(name) + " »")
        self.number = number
        self.name = name
        self.type = type_
        self.label = label            # "repeated", "optional", "required" ou null
        self.type_name = type_name
        self.packed = packed
        self.oneof = oneof
        self.map_key = map_key
        self.map_value = map_value
        self.json_name = json_name
        self.resolved = null          # descripteur du message / de l'énumération (après résolution)

    func repeated():
        return self.label == "repeated"

# Raccourci : field(1, "nom", "string"), field(2, "ids", "int32", true), field(3, "p", "Point") (message ou enum).
func field(number, name, type_, repeated=false, packed=null):
    label := null
    if repeated:
        label = "repeated"
    if is_scalar(type_):
        return Field(number, name, type_, label, null, packed)
    return Field(number, name, "named", label, type_, packed)

func map_field(number, name, key_type, value_type):
    vt := value_type
    tn := null
    if not is_scalar(value_type):
        vt = "named"
        tn = value_type
    return Field(number, name, "map", "repeated", tn, false, null, key_type, vt)

class MessageType:
    func init(full_name, fields=null, syntax="proto3"):
        self.full_name = full_name
        k := len(full_name) - 1
        while k >= 0 and full_name[k] != '.':
            k -= 1
        self.name = _s.substring(full_name, k + 1, len(full_name))
        self.syntax = syntax
        self.fields = []
        self.by_number = {}
        self.by_name = {}
        self.oneofs = {}
        if fields != null:
            for f in fields:
                self.add(f)

    func add(f):
        if contains_key(self.by_number, f.number):
            _fail("numéro de champ " + str(f.number) + " répété dans " + self.full_name)
        if contains_key(self.by_name, f.name):
            _fail("champ « " + f.name + " » répété dans " + self.full_name)
        append(self.fields, f)
        self.by_number[f.number] = f
        self.by_name[f.name] = f
        if f.oneof != null:
            if not contains_key(self.oneofs, f.oneof):
                self.oneofs[f.oneof] = []
            append(self.oneofs[f.oneof], f.name)
        return self

class EnumType:
    func init(full_name, values=null):
        self.full_name = full_name
        k := len(full_name) - 1
        while k >= 0 and full_name[k] != '.':
            k -= 1
        self.name = _s.substring(full_name, k + 1, len(full_name))
        self.values = {}          # nom -> numéro
        self.names = {}           # numéro -> nom (le premier déclaré)
        if values != null:
            for k2 in keys(values):
                self.add(k2, values[k2])

    func add(name, number):
        self.values[name] = number
        if not contains_key(self.names, number):
            self.names[number] = name
        return self

    func number_of(v):
        if type(v) == "int":
            return v
        if contains_key(self.values, v):
            return self.values[v]
        _fail("valeur « " + str(v) + " » inconnue dans l'énumération " + self.full_name)

    func name_of(n, default=null):
        if contains_key(self.names, n):
            return self.names[n]
        return default

class MethodType:
    func init(name, input_type, output_type, client_streaming=false, server_streaming=false):
        self.name = name
        self.input_type = input_type
        self.output_type = output_type
        self.client_streaming = client_streaming
        self.server_streaming = server_streaming

    func kind():
        if self.client_streaming and self.server_streaming:
            return "bidi_streaming"
        if self.client_streaming:
            return "client_streaming"
        if self.server_streaming:
            return "server_streaming"
        return "unary"

class ServiceType:
    func init(full_name):
        self.full_name = full_name
        k := len(full_name) - 1
        while k >= 0 and full_name[k] != '.':
            k -= 1
        self.name = _s.substring(full_name, k + 1, len(full_name))
        self.methods = {}

    func add(m):
        self.methods[m.name] = m
        return self

    func method(name):
        if not contains_key(self.methods, name):
            _fail("méthode « " + name + " » inconnue dans le service " + self.full_name)
        return self.methods[name]

    # Chemin gRPC d'une méthode : « /paquet.Service/Méthode ».
    func path(name):
        self.method(name)
        return "/" + self.full_name + "/" + name

# ---------------------------------------------------------------- schéma

class Schema:
    func init(package=""):
        self.package = package
        self.messages = {}
        self.enums = {}
        self.services = {}
        self.syntax = "proto3"
        self._resolved = false

    func _qualify(name):
        if self.package == "" or _s.contains(name, "."):
            return name
        return self.package + "." + name

    func add_message(name, fields, syntax=null):
        sx := syntax
        if sx == null:
            sx = self.syntax
        m := MessageType(self._qualify(name), fields, sx)
        self.messages[m.full_name] = m
        self._resolved = false
        return m

    func add_enum(name, values):
        e := EnumType(self._qualify(name), values)
        self.enums[e.full_name] = e
        self._resolved = false
        return e

    func add_service(name, methods=null):
        sv := ServiceType(self._qualify(name))
        if methods != null:
            for m in methods:
                sv.add(m)
        self.services[sv.full_name] = sv
        return sv

    # Ajoute les définitions d'un autre schéma (fichier importé).
    func merge(other):
        for k in keys(other.messages):
            self.messages[k] = other.messages[k]
        for k in keys(other.enums):
            self.enums[k] = other.enums[k]
        for k in keys(other.services):
            self.services[k] = other.services[k]
        self._resolved = false
        return self

    # Message par nom complet (« paquet.Message ») ou court (« Message »).
    func message(name):
        n := name
        if _s.starts_with(n, "."):
            n = _s.substring(n, 1, len(n))
        if contains_key(self.messages, n):
            self.resolve()
            return self.messages[n]
        q := self._qualify(n)
        if contains_key(self.messages, q):
            self.resolve()
            return self.messages[q]
        for k in keys(self.messages):
            if self.messages[k].name == n:
                self.resolve()
                return self.messages[k]
        _fail("message inconnu « " + name + " »")

    func enum_type(name):
        n := name
        if _s.starts_with(n, "."):
            n = _s.substring(n, 1, len(n))
        if contains_key(self.enums, n):
            return self.enums[n]
        if contains_key(self.enums, self._qualify(n)):
            return self.enums[self._qualify(n)]
        for k in keys(self.enums):
            if self.enums[k].name == n:
                return self.enums[k]
        _fail("énumération inconnue « " + name + " »")

    func service(name):
        if contains_key(self.services, name):
            return self.services[name]
        if contains_key(self.services, self._qualify(name)):
            return self.services[self._qualify(name)]
        for k in keys(self.services):
            if self.services[k].name == name:
                return self.services[k]
        _fail("service inconnu « " + name + " »")

    # Résout les noms de types (messages et énumérations) des champs, relativement à la portée de chaque message.
    func resolve():
        if self._resolved:
            return
        self._resolved = true
        for k in keys(self.messages):
            m := self.messages[k]
            for f in m.fields:
                if f.type_name != null:
                    target := self._lookup(f.type_name, m.full_name)
                    if target == null:
                        self._resolved = false
                        _fail("type « " + f.type_name + " » introuvable (champ " + m.full_name + "." + f.name + ")")
                    f.resolved = target
                    if f.type == "named":
                        if isinstance(target, EnumType):
                            f.type = "enum"
                        else:
                            f.type = "message"
                    if f.type == "map" and f.map_value == "named":
                        if isinstance(target, EnumType):
                            f.map_value = "enum"
                        else:
                            f.map_value = "message"

    func _lookup(name, scope):
        if _s.starts_with(name, "."):
            n := _s.substring(name, 1, len(name))
            if contains_key(self.messages, n):
                return self.messages[n]
            if contains_key(self.enums, n):
                return self.enums[n]
            return null
        sc := scope
        while true:
            cand := name
            if sc != "":
                cand = sc + "." + name
            if contains_key(self.messages, cand):
                return self.messages[cand]
            if contains_key(self.enums, cand):
                return self.enums[cand]
            if sc == "":
                return null
            k := len(sc) - 1
            while k >= 0 and sc[k] != '.':
                k -= 1
            if k < 0:
                sc = ""
            else:
                sc = _s.substring(sc, 0, k)

    # Octets d'un message (dict nom de champ -> valeur).
    func encode(message_name, value):
        m := self.message(message_name)
        w := Writer()
        _encode_message(m, value, w, 0)
        return w.bytes()

    # dict d'un message binaire.
    func decode(message_name, data, include_defaults=true, enums_as_names=false):
        m := self.message(message_name)
        return _decode_message(m, Reader(data), include_defaults, enums_as_names, 0)

    # Message par défaut (tous les champs à leur valeur par défaut).
    func default(message_name):
        return self.decode(message_name, "")

# ---------------------------------------------------------------- encodage

func _check_int(v, f):
    if type(v) != "int":
        if type(v) == "bool":
            if v:
                return 1
            return 0
        raise("TypeError", "protobuf : entier attendu pour « " + f.name + " » (obtenu '" + type(v) + "')")
    return v

func _write_scalar(w, t, v, f):
    if t == "double":
        w.float64(to_float(v))
    elif t == "float":
        w.float32(to_float(v))
    elif t == "int32" or t == "int64" or t == "uint64":
        w.varint(_check_int(v, f))
    elif t == "uint32":
        w.varint(_check_int(v, f) & 4294967295)
    elif t == "sint32" or t == "sint64":
        w.zigzag(_check_int(v, f))
    elif t == "fixed32" or t == "sfixed32":
        w.fixed32(_check_int(v, f))
    elif t == "fixed64" or t == "sfixed64":
        w.fixed64(_check_int(v, f))
    elif t == "bool":
        if type(v) != "bool":
            raise("TypeError", "protobuf : booléen attendu pour « " + f.name + " »")
        if v:
            w.varint(1)
        else:
            w.varint(0)
    elif t == "string":
        if type(v) != "str":
            raise("TypeError", "protobuf : str attendue pour « " + f.name + " »")
        if not _n.utf8_valid(v):
            _fail("« " + f.name + " » : string non UTF-8 (utiliser bytes)")
        w.varint(_n.blen(v))
        w.raw(v)
    elif t == "bytes":
        raw := v
        if type(v) == "list":
            raw = _n.from_bytes(v)
        w.varint(_n.blen(raw))
        w.raw(raw)
    else:
        _fail("type scalaire inconnu « " + t + " »")

func _is_default(t, v):
    if v == null:
        return true
    if t == "string" or t == "bytes":
        return v == "" or (type(v) == "list" and len(v) == 0)
    if t == "bool":
        return v == false
    if t == "double" or t == "float":
        return v == 0 and _n.f64_bits(to_float(v)) == 0
    return v == 0

func _write_value(w, f, t, resolved, v, depth):
    if t == "message":
        sub := Writer()
        _encode_message(resolved, v, sub, depth + 1)
        w.varint(len(sub.buf))
        for b in sub.buf:
            append(w.buf, b)
    elif t == "enum":
        w.varint(resolved.number_of(v))
    else:
        _write_scalar(w, t, v, f)

func _encode_message(m, value, w, depth):
    if depth > 100:
        _fail("imbrication trop profonde")
    if value == null:
        return
    if type(value) != "dict":
        raise("TypeError", "protobuf : dict attendu pour le message " + m.full_name + " (obtenu '" + type(value) + "')")
    for k in keys(value):
        if not contains_key(m.by_name, k):
            _fail("champ inconnu « " + str(k) + " » pour le message " + m.full_name)
    # un seul champ d'un oneof
    for o in keys(m.oneofs):
        n := 0
        for nm in m.oneofs[o]:
            if contains_key(value, nm) and value[nm] != null:
                n += 1
        if n > 1:
            _fail("plusieurs champs du oneof « " + o + " » dans " + m.full_name)
    for f in m.fields:
        if not contains_key(value, f.name):
            continue
        v := value[f.name]
        if v == null:
            continue
        if f.type == "map":
            if type(v) != "dict":
                raise("TypeError", "protobuf : dict attendu pour la map « " + f.name + " »")
            for key in keys(v):
                entry := Writer()
                entry.tag(1, _wire_of(f.map_key))
                _write_scalar(entry, f.map_key, key, f)
                vt := f.map_value
                entry.tag(2, _wire_of(vt))
                _write_value(entry, f, vt, f.resolved, v[key], depth)
                w.tag(f.number, WIRE_LEN)
                w.varint(len(entry.buf))
                for b in entry.buf:
                    append(w.buf, b)
            continue
        if f.repeated():
            if type(v) != "list" and type(v) != "tuple":
                raise("TypeError", "protobuf : liste attendue pour le champ répété « " + f.name + " »")
            if len(v) == 0:
                continue
            packed := f.packed
            if packed == null:
                packed = m.syntax == "proto3"
            if packed and (_packable(f.type) or f.type == "enum"):
                inner := Writer()
                for x in v:
                    _write_value(inner, f, f.type, f.resolved, x, depth)
                w.tag(f.number, WIRE_LEN)
                w.varint(len(inner.buf))
                for b in inner.buf:
                    append(w.buf, b)
            else:
                for x in v:
                    w.tag(f.number, _wire_of(f.type))
                    _write_value(w, f, f.type, f.resolved, x, depth)
            continue
        explicit := f.label == "optional" or f.oneof != null or m.syntax == "proto2" or f.type == "message"
        if not explicit and f.type != "enum" and _is_default(f.type, v):
            continue
        if not explicit and f.type == "enum" and f.resolved.number_of(v) == 0:
            continue
        w.tag(f.number, _wire_of(f.type))
        _write_value(w, f, f.type, f.resolved, v, depth)

# ---------------------------------------------------------------- décodage

func _default_value(f, include_defaults):
    if f.type == "map":
        return {}
    if f.repeated():
        return []
    if f.type == "message" or f.oneof != null or f.label == "optional":
        return null
    t := f.type
    if t == "string":
        return ""
    if t == "bytes":
        return ""
    if t == "bool":
        return false
    if t == "double" or t == "float":
        return 0.0
    return 0

func _read_scalar(r, t, wire, f):
    if t == "double":
        return r.float64()
    if t == "float":
        return r.float32()
    if t == "int64" or t == "uint64":
        return r.varint()
    if t == "int32":
        return to_i32(r.varint())
    if t == "uint32":
        return r.varint() & 4294967295
    if t == "sint32" or t == "sint64":
        return r.zigzag()
    if t == "fixed32":
        return r.fixed32()
    if t == "sfixed32":
        return to_i32(r.fixed32())
    if t == "fixed64" or t == "sfixed64":
        return r.fixed64()
    if t == "bool":
        return r.varint() != 0
    if t == "string":
        s := _n.from_bytes(r.length_delimited())
        if not _n.utf8_valid(s):
            _fail("« " + f.name + " » : chaîne non UTF-8")
        return s
    if t == "bytes":
        return _n.from_bytes(r.length_delimited())
    _fail("type scalaire inconnu « " + t + " »")

func _read_value(r, f, t, resolved, wire, inc, names, depth):
    if t == "message":
        sub := Reader(r.length_delimited())
        return _decode_message(resolved, sub, inc, names, depth + 1)
    if t == "enum":
        n := to_i32(r.varint())
        if names:
            return resolved.name_of(n, n)
        return n
    return _read_scalar(r, t, wire, f)

func _decode_message(m, r, inc, names, depth):
    if depth > 100:
        _fail("imbrication trop profonde")
    out := {}
    if inc:
        for f in m.fields:
            if f.oneof == null:
                v := _default_value(f, inc)
                if names and f.type == "enum" and not f.repeated() and v == 0:
                    v = f.resolved.name_of(0, 0)
                out[f.name] = v
    while not r.eof():
        t := r.tag()
        number := t[0]
        wire := t[1]
        if not contains_key(m.by_number, number):
            r.skip(wire)
            continue
        f := m.by_number[number]
        if f.type == "map":
            if wire != WIRE_LEN:
                _fail("map « " + f.name + " » : type de fil invalide")
            er := Reader(r.length_delimited())
            key := _default_value(Field(1, "clé", f.map_key), true)
            val := null
            if f.map_value != "message":
                val = _default_value(Field(2, "valeur", f.map_value), true)
            while not er.eof():
                et := er.tag()
                if et[0] == 1:
                    key = _read_scalar(er, f.map_key, et[1], f)
                elif et[0] == 2:
                    val = _read_value(er, f, f.map_value, f.resolved, et[1], inc, names, depth)
                else:
                    er.skip(et[1])
            if not contains_key(out, f.name) or out[f.name] == null:
                out[f.name] = {}
            out[f.name][key] = val
            continue
        if f.repeated():
            if not contains_key(out, f.name) or out[f.name] == null:
                out[f.name] = []
            if wire == WIRE_LEN and (_packable(f.type) or f.type == "enum"):
                pr := Reader(r.length_delimited())
                while not pr.eof():
                    append(out[f.name], _read_value(pr, f, f.type, f.resolved, _wire_of(f.type), inc, names, depth))
            else:
                append(out[f.name], _read_value(r, f, f.type, f.resolved, wire, inc, names, depth))
            continue
        if wire != _wire_of(f.type) and not (f.type == "enum" and wire == WIRE_VARINT):
            _fail("champ « " + f.name + " » : type de fil " + str(wire) + " inattendu")
        if f.oneof != null:
            for other in m.oneofs[f.oneof]:
                if other != f.name and contains_key(out, other):
                    out = _without(out, other)
        if f.type == "message" and contains_key(out, f.name) and out[f.name] != null:
            # deux occurrences d'un message : fusion (règle protobuf)
            merged := _read_value(r, f, f.type, f.resolved, wire, false, names, depth)
            for k in keys(merged):
                out[f.name][k] = merged[k]
            continue
        out[f.name] = _read_value(r, f, f.type, f.resolved, wire, inc, names, depth)
    return out

func _without(d, key):
    out := {}
    for k in keys(d):
        if k != key:
            out[k] = d[k]
    return out

# ---------------------------------------------------------------- lecture d'un fichier .proto

class _Lexer:
    func init(text):
        self.toks = []
        i := 0
        n := len(text)
        line := 1
        while i < n:
            c := text[i]
            if c == '\n':
                line += 1
                i += 1
                continue
            if c == ' ' or c == '\t' or c == '\r':
                i += 1
                continue
            if c == '/' and i + 1 < n and text[i + 1] == '/':
                while i < n and text[i] != '\n':
                    i += 1
                continue
            if c == '/' and i + 1 < n and text[i + 1] == '*':
                i += 2
                while i + 1 < n and not (text[i] == '*' and text[i + 1] == '/'):
                    if text[i] == '\n':
                        line += 1
                    i += 1
                i += 2
                continue
            if c == '"' or c == '\'':
                j := i + 1
                buf := []
                while j < n and text[j] != c:
                    if text[j] == '\\' and j + 1 < n:
                        j += 1
                        e := text[j]
                        if e == 'n':
                            append(buf, "\n")
                        elif e == 't':
                            append(buf, "\t")
                        else:
                            append(buf, str(e))
                    else:
                        append(buf, str(text[j]))
                    j += 1
                append(self.toks, ["str", _s.join("", buf), line])
                i = j + 1
                continue
            if (c >= 'a' and c <= 'z') or (c >= 'A' and c <= 'Z') or c == '_' or c == '.':
                j := i
                while j < n and ((text[j] >= 'a' and text[j] <= 'z') or (text[j] >= 'A' and text[j] <= 'Z') or (text[j] >= '0' and text[j] <= '9') or text[j] == '_' or text[j] == '.'):
                    j += 1
                append(self.toks, ["id", _s.substring(text, i, j), line])
                i = j
                continue
            if (c >= '0' and c <= '9') or c == '-' or c == '+':
                j := i + 1
                while j < n and ((text[j] >= '0' and text[j] <= '9') or (text[j] >= 'a' and text[j] <= 'z') or (text[j] >= 'A' and text[j] <= 'Z') or text[j] == '.' or ((text[j] == '-' or text[j] == '+') and (text[j - 1] == 'e' or text[j - 1] == 'E'))):
                    j += 1
                append(self.toks, ["num", _s.substring(text, i, j), line])
                i = j
                continue
            append(self.toks, ["sym", str(c), line])
            i += 1
        self.pos = 0

    func peek():
        if self.pos < len(self.toks):
            return self.toks[self.pos]
        return ["eof", "", 0]

    func next():
        t := self.peek()
        self.pos += 1
        return t

    func fail(message):
        _fail(".proto ligne " + str(self.peek()[2]) + " : " + message)

    func expect(v):
        t := self.next()
        if t[1] != v:
            self.pos -= 1
            self.fail("« " + v + " » attendu (obtenu « " + t[1] + " »)")
        return t

    func accept(v):
        if self.peek()[1] == v and self.peek()[0] != "str":
            self.pos += 1
            return true
        return false

    func ident():
        t := self.next()
        if t[0] != "id":
            self.pos -= 1
            self.fail("identifiant attendu (obtenu « " + t[1] + " »)")
        return t[1]

    func number():
        t := self.next()
        if t[0] != "num":
            self.pos -= 1
            self.fail("nombre attendu")
        return _parse_int(t[1])

func _parse_int(text):
    t := _s.lower(text)
    neg := false
    if _s.starts_with(t, "-"):
        neg = true
        t = _s.substring(t, 1, len(t))
    elif _s.starts_with(t, "+"):
        t = _s.substring(t, 1, len(t))
    v := 0
    if _s.starts_with(t, "0x"):
        for c in _s.substring(t, 2, len(t)):
            v = v * 16 + _s.find("0123456789abcdef", str(c))
    elif len(t) > 1 and _s.starts_with(t, "0"):
        for c in _s.substring(t, 1, len(t)):
            v = v * 8 + (_s.ord(c) - 48)
    else:
        v = to_int(t)
    if neg:
        return -v
    return v

# Saute une option « [a = b, ...] » ou une valeur d'option (y compris un bloc { ... }).
func _skip_options(lx):
    if lx.accept("["):
        depth := 1
        while depth > 0:
            t := lx.next()
            if t[0] == "eof":
                lx.fail("« ] » manquant")
            if t[1] == "[" and t[0] == "sym":
                depth += 1
            elif t[1] == "]" and t[0] == "sym":
                depth -= 1

func _skip_statement(lx):
    depth := 0
    while true:
        t := lx.next()
        if t[0] == "eof":
            return
        if t[0] == "sym" and t[1] == "{":
            depth += 1
        elif t[0] == "sym" and t[1] == "}":
            depth -= 1
            if depth <= 0:
                if depth == 0:
                    lx.accept(";")
                return
        elif t[0] == "sym" and t[1] == ";" and depth == 0:
            return

# Schéma lu depuis le texte d'un fichier .proto (proto2 ou proto3). imports : dict nom de fichier -> Schema
# (définitions des fichiers importés), facultatif.
func parse_proto(text, imports=null):
    lx := _Lexer(text)
    s := Schema("")
    s.syntax = "proto2"
    while lx.peek()[0] != "eof":
        t := lx.peek()
        if lx.accept(";"):
            continue
        kw := lx.ident()
        if kw == "syntax" or kw == "edition":
            lx.expect("=")
            v := lx.next()[1]
            if v == "proto3":
                s.syntax = "proto3"
            elif v == "proto2":
                s.syntax = "proto2"
            else:
                s.syntax = "proto3"
            lx.expect(";")
        elif kw == "package":
            s.package = lx.ident()
            lx.expect(";")
        elif kw == "import":
            if lx.peek()[1] == "public" or lx.peek()[1] == "weak":
                lx.next()
            f := lx.next()[1]
            lx.expect(";")
            if imports != null and contains_key(imports, f):
                s.merge(imports[f])
        elif kw == "option":
            _skip_statement(lx)
        elif kw == "message":
            _parse_message(lx, s, s.package)
        elif kw == "enum":
            _parse_enum(lx, s, s.package)
        elif kw == "service":
            _parse_service(lx, s)
        elif kw == "extend":
            _skip_statement(lx)
        else:
            lx.pos -= 1
            lx.fail("déclaration inattendue « " + kw + " »")
    s.resolve()
    # types d'entrée / de sortie des méthodes : noms complets
    for k in keys(s.services):
        for mn in keys(s.services[k].methods):
            mt := s.services[k].methods[mn]
            for io_name in ["in", "out"]:
                raw := mt.input_type
                if io_name == "out":
                    raw = mt.output_type
                target := s._lookup(raw, s.package)
                if target == null:
                    _fail("type « " + raw + " » introuvable (méthode " + k + "." + mn + ")")
                if io_name == "in":
                    mt.input_type = target.full_name
                else:
                    mt.output_type = target.full_name
    return s

func _full(scope, name):
    if scope == "":
        return name
    return scope + "." + name

func _parse_enum(lx, s, scope):
    name := lx.ident()
    e := EnumType(_full(scope, name))
    lx.expect("{")
    while not lx.accept("}"):
        if lx.accept(";"):
            continue
        id := lx.ident()
        if id == "option" or id == "reserved":
            _skip_statement(lx)
            continue
        lx.expect("=")
        e.add(id, lx.number())
        _skip_options(lx)
        lx.expect(";")
    s.enums[e.full_name] = e

func _parse_field_type(lx):
    t := lx.ident()
    if t == "map":
        lx.expect("<")
        k := lx.ident()
        lx.expect(",")
        v := lx.ident()
        lx.expect(">")
        return ["map", k, v]
    return [t]

func _parse_message(lx, s, scope):
    name := lx.ident()
    full := _full(scope, name)
    m := MessageType(full, null, s.syntax)
    s.messages[full] = m
    lx.expect("{")
    _parse_body(lx, s, m, full, null)

func _parse_body(lx, s, m, full, oneof):
    while not lx.accept("}"):
        if lx.accept(";"):
            continue
        kw := lx.peek()[1]
        if oneof == null and kw == "message":
            lx.next()
            _parse_message(lx, s, full)
            continue
        if oneof == null and kw == "enum":
            lx.next()
            _parse_enum(lx, s, full)
            continue
        if kw == "option" or kw == "reserved" or kw == "extensions" or kw == "extend":
            lx.next()
            _skip_statement(lx)
            continue
        if oneof == null and kw == "oneof":
            lx.next()
            oname := lx.ident()
            lx.expect("{")
            _parse_body(lx, s, m, full, oname)
            continue
        label := null
        if kw == "repeated" or kw == "optional" or kw == "required":
            label = kw
            lx.next()
        ft := _parse_field_type(lx)
        fname := lx.ident()
        lx.expect("=")
        number := lx.number()
        packed := null
        if lx.peek()[1] == "[":
            # options : seul « packed » est interprété
            lx.next()
            while not lx.accept("]"):
                t := lx.next()
                if t[0] == "eof":
                    lx.fail("« ] » manquant")
                if t[1] == "packed":
                    lx.expect("=")
                    packed = lx.next()[1] == "true"
        lx.expect(";")
        f := null
        if ft[0] == "map":
            f = map_field(number, fname, ft[1], ft[2])
        elif is_scalar(ft[0]):
            f = Field(number, fname, ft[0], label, null, packed, oneof)
        else:
            if ft[0] == "group":
                lx.fail("les groupes (proto2) ne sont pas pris en charge")
            f = Field(number, fname, "named", label, ft[0], packed, oneof)
        m.add(f)

func _parse_service(lx, s):
    name := lx.ident()
    sv := ServiceType(_full(s.package, name))
    lx.expect("{")
    while not lx.accept("}"):
        if lx.accept(";"):
            continue
        kw := lx.ident()
        if kw == "option":
            _skip_statement(lx)
            continue
        if kw != "rpc":
            lx.pos -= 1
            lx.fail("« rpc » attendu dans un service")
        mname := lx.ident()
        lx.expect("(")
        cs := false
        if lx.peek()[1] == "stream" and lx.toks[lx.pos + 1][1] != ")":
            lx.next()
            cs = true
        intype := lx.ident()
        lx.expect(")")
        if lx.ident() != "returns":
            lx.fail("« returns » attendu")
        lx.expect("(")
        ss := false
        if lx.peek()[1] == "stream" and lx.toks[lx.pos + 1][1] != ")":
            lx.next()
            ss = true
        outtype := lx.ident()
        lx.expect(")")
        if lx.accept("{"):
            depth := 1
            while depth > 0:
                t := lx.next()
                if t[0] == "eof":
                    lx.fail("« } » manquant")
                if t[0] == "sym" and t[1] == "{":
                    depth += 1
                elif t[0] == "sym" and t[1] == "}":
                    depth -= 1
            lx.accept(";")
        else:
            lx.expect(";")
        sv.add(MethodType(mname, intype, outtype, cs, ss))
    s.services[sv.full_name] = sv

# Schéma d'un fichier .proto.
func load_proto(path, imports=null):
    return parse_proto(_io.read_file(path), imports)
