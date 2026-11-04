# ALEX STANDARD LIBRARY — graphics.vertex_layout
#
# Formats de sommets typés, comme les décrivent les API graphiques (Vulkan, WebGPU) : chaque attribut a un
# nom, un emplacement (location) et un format de composantes :
#   float32 / float32x2 / float32x3 / float32x4, float16x2 / x4, uint32 / x2 / x3 / x4, sint32...,
#   uint16x2 / x4, unorm16x2 / x4, uint8x4, unorm8x4 (couleurs 0..1 sur un octet), snorm8x4 (normales).
#   - TypedLayout : décalages et pas en OCTETS (alignement facultatif sur 4), conversion vers le format
#     flottant du pipeline logiciel (graphics.buffer.VertexLayout) ;
#   - pack / unpack : sommets entrelacés ↔ octets petit-boutistes (envoi à une vraie carte, fichiers) ;
#   - interleave / deinterleave : tableaux séparés par attribut ↔ données entrelacées ;
#   - parse : description textuelle « position:float32x3, color:unorm8x4, uv:float32x2 ».
#
#   use graphics.vertex_layout as vl
#   lay := vl.parse("position:float32x3, color:unorm8x4")
#   print(lay.stride)                                   # 16 octets
#   octets := lay.pack([[0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0]])   # str binaire
#   print(lay.unpack(octets))                           # [[0.0, 1.0, 0.0, 1.0, 0.0, 0.0, 1.0]]
#   vb := lay.vertex_buffer(lay.unpack(octets))         # graphics.buffer.VertexBuffer
#
# Erreurs : FormatError (format inconnu, données de taille incorrecte), ArgumentError.

from core use len, type, to_int, to_float
from collections use append, contains_key
use string as _s
use math as _math
use _native_net as _n
use graphics.buffer as _gb

# format -> [type de composante, nombre, octets par composante]
const FORMATS := {
    "float32": ["f", 1, 4], "float32x2": ["f", 2, 4], "float32x3": ["f", 3, 4], "float32x4": ["f", 4, 4],
    "float16x2": ["e", 2, 2], "float16x4": ["e", 4, 2],
    "uint32": ["I", 1, 4], "uint32x2": ["I", 2, 4], "uint32x3": ["I", 3, 4], "uint32x4": ["I", 4, 4],
    "sint32": ["i", 1, 4], "sint32x2": ["i", 2, 4], "sint32x3": ["i", 3, 4], "sint32x4": ["i", 4, 4],
    "uint16x2": ["H", 2, 2], "uint16x4": ["H", 4, 2], "unorm16x2": ["H", 2, 2], "unorm16x4": ["H", 4, 2],
    "uint8x4": ["B", 4, 1], "unorm8x4": ["B", 4, 1], "snorm8x4": ["b", 4, 1]
}

func format_info(fmt):
    if not contains_key(FORMATS, fmt):
        raise("FormatError", "format de sommet inconnu « " + str(fmt) + " »")
    return FORMATS[fmt]

func _normalized(fmt):
    return _s.starts_with(fmt, "unorm") or _s.starts_with(fmt, "snorm")

class Attribute:
    func init(name, fmt, location, offset):
        info := format_info(fmt)
        self.name = name
        self.format = fmt
        self.location = location
        self.offset = offset
        self.code = info[0]
        self.components = info[1]
        self.component_bytes = info[2]
        self.bytes = info[1] * info[2]
        self.normalized = _normalized(fmt)

    func describe():
        return str(self.location) + " " + self.name + ":" + self.format + " @" + str(self.offset)

class TypedLayout:
    # attributes : list de [nom, format] ; align : alignement de chaque attribut (4 par défaut, 1 : serré).
    func init(attributes, align=4):
        self.attributes = []
        off := 0
        loc := 0
        for a in attributes:
            at := Attribute(a[0], a[1], loc, off)
            off += at.bytes
            if align > 1 and off % align != 0:
                off += align - off % align
            append(self.attributes, at)
            loc += 1
        self.stride = off
        if align > 1 and self.stride % align != 0:
            self.stride += align - self.stride % align
        self.components = 0
        for at in self.attributes:
            self.components += at.components

    func attribute(name):
        for a in self.attributes:
            if a.name == name:
                return a
        raise("ArgumentError", "TypedLayout : pas d'attribut « " + name + " »")

    func names():
        return [a.name for a in self.attributes]

    func describe():
        return _s.join(", ", [a.name + ":" + a.format for a in self.attributes]) + " (" + str(self.stride) + " octets)"

    # Format flottant du pipeline logiciel.
    func float_layout():
        return _gb.VertexLayout([[a.name, a.components] for a in self.attributes])

    # Sommets (listes de composantes flottantes, dans l'ordre des attributs) -> octets entrelacés.
    func pack(vertices):
        parts := []
        for v in vertices:
            if len(v) != self.components:
                raise("FormatError", "sommet de " + str(len(v)) + " composantes, " + str(self.components) + " attendues")
            used := 0
            k := 0
            for a in self.attributes:
                if a.offset > used:
                    append(parts, _s.byte_pack([0 for i in 0..a.offset - used]))
                    used = a.offset
                c := 0
                while c < a.components:
                    append(parts, _s.byte_pack(_le(_bits(a, _encode(a, v[k])), a.component_bytes)))
                    k += 1
                    c += 1
                used += a.bytes
            if self.stride > used:
                append(parts, _s.byte_pack([0 for i in 0..self.stride - used]))
        return _s.byte_join(parts)

    func unpack(data):
        n := _s.byte_len(data)
        if n % self.stride != 0:
            raise("FormatError", str(n) + " octets : pas un multiple du pas de " + str(self.stride))
        out := []
        base := 0
        while base < n:
            v := []
            for a in self.attributes:
                c := 0
                while c < a.components:
                    o := base + a.offset + c * a.component_bytes
                    raw := 0
                    j := a.component_bytes - 1
                    while j >= 0:
                        raw = (raw << 8) | _s.byte_at(data, o + j)
                        j -= 1
                    append(v, _decode(a, _value(a, raw)))
                    c += 1
            append(out, v)
            base += self.stride
        return out

    # VertexBuffer du pipeline logiciel depuis des sommets (listes de composantes).
    func vertex_buffer(vertices):
        flat := []
        for v in vertices:
            for x in v:
                append(flat, x)
        return _gb.VertexBuffer(self.float_layout(), flat)

    # Tableaux par attribut ({"position": [x, y, z, x, y, z...], ...}) -> sommets.
    func interleave(arrays):
        count := null
        for a in self.attributes:
            if not contains_key(arrays, a.name):
                raise("FormatError", "interleave : tableau « " + a.name + " » manquant")
            arr := arrays[a.name]
            if len(arr) % a.components != 0:
                raise("FormatError", "interleave : « " + a.name + " » n'a pas un multiple de " + str(a.components) + " valeurs")
            c := len(arr) // a.components
            if count == null:
                count = c
            elif c != count:
                raise("FormatError", "interleave : « " + a.name + " » a " + str(c) + " sommets, " + str(count) + " attendus")
        out := []
        i := 0
        while i < count:
            v := []
            for a in self.attributes:
                arr := arrays[a.name]
                k := 0
                while k < a.components:
                    append(v, arr[i * a.components + k])
                    k += 1
            append(out, v)
            i += 1
        return out

    func deinterleave(vertices):
        out := {a.name: [] for a in self.attributes}
        for v in vertices:
            k := 0
            for a in self.attributes:
                c := 0
                while c < a.components:
                    append(out[a.name], v[k])
                    k += 1
                    c += 1
        return out

func _le(v, n):
    out := []
    i := 0
    while i < n:
        append(out, (v >> (8 * i)) & 255)
        i += 1
    return out

# Valeur -> motif binaire de la composante.
func _bits(a, x):
    if a.code == "f":
        return _n.f32_bits(x)
    if a.code == "e":
        return f16_bits(x)
    mask := (1 << (8 * a.component_bytes)) - 1
    return x & mask

# Motif binaire -> valeur (signe pour les types signés).
func _value(a, raw):
    if a.code == "f":
        return _n.bits_f32(raw)
    if a.code == "e":
        return bits_f16(raw)
    if a.code == "i" or a.code == "b":
        nb := 8 * a.component_bytes
        if raw >= (1 << (nb - 1)):
            return raw - (1 << nb)
    return raw

# Demi-précision IEEE 754 (arrondi au plus proche, sans infinis pour les grandes valeurs : saturées).
func f16_bits(x):
    if x != x:
        return 0x7E00
    sign := 0
    v := x
    if v < 0.0 or (v == 0.0 and 1.0 / v < 0.0):
        sign = 0x8000
        v = -v
    if v == 0.0:
        return sign
    if v >= 65520.0:
        return sign | 0x7C00
    e := 0
    m := v
    while m >= 2.0:
        m = m / 2.0
        e += 1
    while m < 1.0 and e > -14:
        m = m * 2.0
        e -= 1
    if m < 1.0:
        frac := _round(m * 1024.0)
        return sign | frac
    frac := _round((m - 1.0) * 1024.0)
    if frac == 1024:
        frac = 0
        e += 1
    return sign | ((e + 15) << 10) | frac

func bits_f16(h):
    sign := -1.0 if (h & 0x8000) != 0 else 1.0
    e := (h >> 10) & 31
    f := h & 1023
    if e == 0:
        return sign * f / 1024.0 * _math.pow(2.0, -14.0)
    if e == 31:
        if f != 0:
            return 0.0 / 0.0
        return sign * 1.0e308 * 10.0
    return sign * (1.0 + f / 1024.0) * _math.pow(2.0, e - 15.0)

func _round(x):
    return to_int(_math.floor(x + 0.5))

func _encode(a, x):
    if a.code == "f" or a.code == "e":
        return to_float(x)
    if a.normalized:
        if a.code == "B":
            v := x if x > 0.0 else 0.0
            return _round((v if v < 1.0 else 1.0) * 255.0)
        if a.code == "H":
            v := x if x > 0.0 else 0.0
            return _round((v if v < 1.0 else 1.0) * 65535.0)
        if a.code == "b":
            v := x if x > -1.0 else -1.0
            return _round((v if v < 1.0 else 1.0) * 127.0)
    return to_int(x)

func _decode(a, x):
    if a.code == "f" or a.code == "e":
        return to_float(x)
    if a.normalized:
        if a.code == "B":
            return x / 255.0
        if a.code == "H":
            return x / 65535.0
        if a.code == "b":
            v := x / 127.0
            return v if v > -1.0 else -1.0
    return to_float(x)

# « position:float32x3, color:unorm8x4 »
func parse(text, align=4):
    attrs := []
    for part in _s.split(text, ","):
        t := _s.trim(part)
        if t == "":
            continue
        k := _s.find(t, ":")
        if k <= 0:
            raise("FormatError", "attribut « " + t + " » : nom:format attendu")
        append(attrs, [_s.trim(_s.substring(t, 0, k)), _s.trim(_s.substring(t, k + 1, len(t)))])
    return TypedLayout(attrs, align)

POSITION3 := TypedLayout([["position", "float32x3"]])
POSITION3_COLOR8 := TypedLayout([["position", "float32x3"], ["color", "unorm8x4"]])
POSITION3_NORMAL3_UV2 := TypedLayout([["position", "float32x3"], ["normal", "float32x3"], ["uv", "float32x2"]])
