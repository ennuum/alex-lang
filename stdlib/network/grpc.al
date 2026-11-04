# ALEX STANDARD LIBRARY — network.grpc
#
# Socle de gRPC : HTTP/2 (RFC 9113), compression d'en-têtes HPACK (RFC 7541), encadrement des messages gRPC,
# statuts et métadonnées. Le client est dans network.grpc_client, le serveur dans network.grpc_server ; les
# messages sont en général des Protocol Buffers (network.protobuf).
#
#   HPACK         HpackEncoder / HpackDecoder (table dynamique, codage de Huffman), huffman_encode / huffman_decode
#   HTTP/2        H2Connection(connexion tcp, client) : préface, SETTINGS, flux, contrôle de flux (WINDOW_UPDATE),
#                 PING, GOAWAY, RST_STREAM, CONTINUATION ; H2Stream (en-têtes, données, fin)
#   gRPC          frame_message / unframe_messages (préfixe de 5 octets), statuts (OK, NOT_FOUND...),
#                 GrpcError « [CODE] message », status_of(erreur), encode_timeout / parse_timeout,
#                 métadonnées « -bin » en base64
#
# HTTP/2 en clair (« h2c », connaissance préalable) ou sur TLS avec ALPN « h2 ». Pas de PUSH_PROMISE (désactivé),
# pas de priorités (ignorées).
#
# Erreurs : GrpcError (statut gRPC non nul), ProtocolError (violation HTTP/2 ou HPACK), NetworkError,
# TimeoutError, TlsError.

from core use len, type, to_int
from collections use append, keys, contains_key
use string as _s
use _native_net as _n
use time as _time
use network.encoding as _enc
use network.compression as _z

func _proto(message):
    raise("ProtocolError", "http2 : " + message)

# ---------------------------------------------------------------- statuts gRPC

const OK := 0
const CANCELLED := 1
const UNKNOWN := 2
const INVALID_ARGUMENT := 3
const DEADLINE_EXCEEDED := 4
const NOT_FOUND := 5
const ALREADY_EXISTS := 6
const PERMISSION_DENIED := 7
const RESOURCE_EXHAUSTED := 8
const FAILED_PRECONDITION := 9
const ABORTED := 10
const OUT_OF_RANGE := 11
const UNIMPLEMENTED := 12
const INTERNAL := 13
const UNAVAILABLE := 14
const DATA_LOSS := 15
const UNAUTHENTICATED := 16

const STATUS_NAMES := ["OK", "CANCELLED", "UNKNOWN", "INVALID_ARGUMENT", "DEADLINE_EXCEEDED", "NOT_FOUND", "ALREADY_EXISTS", "PERMISSION_DENIED", "RESOURCE_EXHAUSTED", "FAILED_PRECONDITION", "ABORTED", "OUT_OF_RANGE", "UNIMPLEMENTED", "INTERNAL", "UNAVAILABLE", "DATA_LOSS", "UNAUTHENTICATED"]

func status_name(code):
    if code >= 0 and code < len(STATUS_NAMES):
        return STATUS_NAMES[code]
    return "CODE_" + str(code)

func status_code(name):
    i := 0
    for n in STATUS_NAMES:
        if n == name:
            return i
        i += 1
    return UNKNOWN

# Lève GrpcError « [NOM] message ».
func fail(code, message=""):
    raise("GrpcError", "[" + status_name(code) + "] " + str(message))

# (code, message) d'une GrpcError attrapée (UNKNOWN pour une autre erreur).
func status_of(e):
    if e.type != "GrpcError":
        if e.type == "TimeoutError":
            return (DEADLINE_EXCEEDED, e.message)
        return (UNKNOWN, e.type + " : " + e.message)
    m := e.message
    if _s.starts_with(m, "["):
        k := _s.find(m, "]")
        if k > 0:
            return (status_code(_s.substring(m, 1, k)), _s.trim(_s.substring(m, k + 1, len(m))))
    return (UNKNOWN, m)

# grpc-message : encodage « %XX » des octets hors de l'ASCII imprimable (et de « % »).
func encode_grpc_message(text):
    out := []
    for b in _n.to_bytes(str(text)):
        if b >= 32 and b <= 126 and b != 37:
            append(out, str(_s.chr(b)))
        else:
            append(out, "%" + _enc.hex_encode(_n.from_bytes([b]), true))
    return _s.join("", out)

func decode_grpc_message(text):
    if text == null:
        return ""
    return _enc.to_text(_enc.percent_decode(text))

# Délai gRPC (« 1500m », « 30S »...) depuis des secondes, et inversement.
func encode_timeout(seconds):
    ms := to_int(seconds * 1000.0 + 0.5)
    if ms < 1:
        ms = 1
    if ms < 100000000:
        return str(ms) + "m"
    return str(to_int(seconds + 0.5)) + "S"

func parse_timeout(text):
    if text == null or len(text) < 2:
        return null
    unit := text[len(text) - 1]
    num := _s.substring(text, 0, len(text) - 1)
    for c in num:
        if c < '0' or c > '9':
            return null
    v := to_int(num) * 1.0
    if unit == 'H':
        return v * 3600.0
    if unit == 'M':
        return v * 60.0
    if unit == 'S':
        return v
    if unit == 'm':
        return v / 1000.0
    if unit == 'u':
        return v / 1000000.0
    if unit == 'n':
        return v / 1000000000.0
    return null

# Métadonnées : dict nom -> valeur ; les noms « -bin » portent des octets (base64 sur le fil).
func metadata_to_headers(md):
    out := []
    if md == null:
        return out
    for k in keys(md):
        name := _s.lower(k)
        v := md[k]
        vals := [v]
        if type(v) == "list":
            vals = v
        for x in vals:
            if _s.ends_with(name, "-bin"):
                append(out, [name, _enc.base64_encode(x, false, false)])
            else:
                sx := str(x)
                if _s.contains(sx, "\n") or _s.contains(sx, "\r"):
                    raise("ArgumentError", "grpc : métadonnée « " + name + " » sur une seule ligne attendue")
                append(out, [name, sx])
    return out

const _RESERVED := [":path", ":method", ":scheme", ":authority", ":status", "content-type", "te", "grpc-timeout", "grpc-encoding", "grpc-accept-encoding", "grpc-status", "grpc-message", "user-agent", "content-length", "grpc-status-details-bin"]

func headers_to_metadata(headers):
    md := {}
    for h in headers:
        name := h[0]
        skip := false
        for r in _RESERVED:
            if r == name:
                skip = true
        if skip:
            continue
        v := h[1]
        if _s.ends_with(name, "-bin"):
            try:
                v = _enc.base64_decode(v)
            catch e:
                continue
        if contains_key(md, name):
            if type(md[name]) == "list":
                append(md[name], v)
            else:
                md[name] = [md[name], v]
        else:
            md[name] = v
    return md

func header_value(headers, name, default=null):
    for h in headers:
        if h[0] == name:
            return h[1]
    return default

# ---------------------------------------------------------------- messages gRPC

# Message préfixé : 1 octet (compressé ?) + longueur sur 4 octets + octets.
func frame_message(data, compressed=false):
    n := _n.blen(data)
    flag := 0
    if compressed:
        flag = 1
    return _n.from_bytes([flag, (n >> 24) & 255, (n >> 16) & 255, (n >> 8) & 255, n & 255]) + data

# Découpe un flux d'octets en messages : (liste de messages, octets restants incomplets). encoding : codage
# annoncé (grpc-encoding) pour les messages marqués compressés.
func unframe_messages(buffer, encoding=null, max_size=4194304):
    out := []
    pos := 0
    total := _n.blen(buffer)
    while total - pos >= 5:
        h := _n.to_bytes(_n.bslice(buffer, pos, pos + 5))
        n := (h[1] << 24) | (h[2] << 16) | (h[3] << 8) | h[4]
        if n > max_size:
            fail(RESOURCE_EXHAUSTED, "message de " + str(n) + " octets (limite " + str(max_size) + ")")
        if total - pos - 5 < n:
            break
        msg := _n.bslice(buffer, pos + 5, pos + 5 + n)
        if h[0] == 1:
            if encoding == null or encoding == "identity":
                fail(INTERNAL, "message compressé sans grpc-encoding")
            if encoding != "gzip" and encoding != "deflate":
                fail(UNIMPLEMENTED, "compression « " + encoding + " » non prise en charge")
            msg = _z.decode(msg, encoding, max_size)
        elif h[0] != 0:
            fail(INTERNAL, "drapeau de compression invalide " + str(h[0]))
        append(out, msg)
        pos += 5 + n
    return (out, _n.bslice(buffer, pos, total))

# ---------------------------------------------------------------- HPACK

# Table statique (RFC 7541, annexe A) et codes de Huffman (annexe B) : 256 octets, le code EOS à part.
const _STATIC := [[":authority", ""], [":method", "GET"], [":method", "POST"], [":path", "/"], [":path", "/index.html"], [":scheme", "http"], [":scheme", "https"], [":status", "200"], [":status", "204"], [":status", "206"], [":status", "304"], [":status", "400"], [":status", "404"], [":status", "500"], ["accept-charset", ""], ["accept-encoding", "gzip, deflate"], ["accept-language", ""], ["accept-ranges", ""], ["accept", ""], ["access-control-allow-origin", ""], ["age", ""], ["allow", ""], ["authorization", ""], ["cache-control", ""], ["content-disposition", ""], ["content-encoding", ""], ["content-language", ""], ["content-length", ""], ["content-location", ""], ["content-range", ""], ["content-type", ""], ["cookie", ""], ["date", ""], ["etag", ""], ["expect", ""], ["expires", ""], ["from", ""], ["host", ""], ["if-match", ""], ["if-modified-since", ""], ["if-none-match", ""], ["if-range", ""], ["if-unmodified-since", ""], ["last-modified", ""], ["link", ""], ["location", ""], ["max-forwards", ""], ["proxy-authenticate", ""], ["proxy-authorization", ""], ["range", ""], ["referer", ""], ["refresh", ""], ["retry-after", ""], ["server", ""], ["set-cookie", ""], ["strict-transport-security", ""], ["transfer-encoding", ""], ["user-agent", ""], ["vary", ""], ["via", ""], ["www-authenticate", ""]]
const _HUFF_CODES := [8184, 8388568, 268435426, 268435427, 268435428, 268435429, 268435430, 268435431, 268435432, 16777194, 1073741820, 268435433, 268435434, 1073741821, 268435435, 268435436, 268435437, 268435438, 268435439, 268435440, 268435441, 268435442, 1073741822, 268435443, 268435444, 268435445, 268435446, 268435447, 268435448, 268435449, 268435450, 268435451, 20, 1016, 1017, 4090, 8185, 21, 248, 2042, 1018, 1019, 249, 2043, 250, 22, 23, 24, 0, 1, 2, 25, 26, 27, 28, 29, 30, 31, 92, 251, 32764, 32, 4091, 1020, 8186, 33, 93, 94, 95, 96, 97, 98, 99, 100, 101, 102, 103, 104, 105, 106, 107, 108, 109, 110, 111, 112, 113, 114, 252, 115, 253, 8187, 524272, 8188, 16380, 34, 32765, 3, 35, 4, 36, 5, 37, 38, 39, 6, 116, 117, 40, 41, 42, 7, 43, 118, 44, 8, 9, 45, 119, 120, 121, 122, 123, 32766, 2044, 16381, 8189, 268435452, 1048550, 4194258, 1048551, 1048552, 4194259, 4194260, 4194261, 8388569, 4194262, 8388570, 8388571, 8388572, 8388573, 8388574, 16777195, 8388575, 16777196, 16777197, 4194263, 8388576, 16777198, 8388577, 8388578, 8388579, 8388580, 2097116, 4194264, 8388581, 4194265, 8388582, 8388583, 16777199, 4194266, 2097117, 1048553, 4194267, 4194268, 8388584, 8388585, 2097118, 8388586, 4194269, 4194270, 16777200, 2097119, 4194271, 8388587, 8388588, 2097120, 2097121, 4194272, 2097122, 8388589, 4194273, 8388590, 8388591, 1048554, 4194274, 4194275, 4194276, 8388592, 4194277, 4194278, 8388593, 67108832, 67108833, 1048555, 524273, 4194279, 8388594, 4194280, 33554412, 67108834, 67108835, 67108836, 134217694, 134217695, 67108837, 16777201, 33554413, 524274, 2097123, 67108838, 134217696, 134217697, 67108839, 134217698, 16777202, 2097124, 2097125, 67108840, 67108841, 268435453, 134217699, 134217700, 134217701, 1048556, 16777203, 1048557, 2097126, 4194281, 2097127, 2097128, 8388595, 4194282, 4194283, 33554414, 33554415, 16777204, 16777205, 67108842, 8388596, 67108843, 134217702, 67108844, 67108845, 134217703, 134217704, 134217705, 134217706, 134217707, 268435454, 134217708, 134217709, 134217710, 134217711, 134217712, 67108846]
const _HUFF_LENS := [13, 23, 28, 28, 28, 28, 28, 28, 28, 24, 30, 28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 30, 28, 28, 28, 28, 28, 28, 28, 28, 28, 6, 10, 10, 12, 13, 6, 8, 11, 10, 10, 8, 11, 8, 6, 6, 6, 5, 5, 5, 6, 6, 6, 6, 6, 6, 6, 7, 8, 15, 6, 12, 10, 13, 6, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 7, 8, 7, 8, 13, 19, 13, 14, 6, 15, 5, 6, 5, 6, 5, 6, 6, 6, 5, 7, 7, 6, 6, 6, 5, 6, 7, 6, 5, 5, 6, 7, 7, 7, 7, 7, 15, 11, 14, 13, 28, 20, 22, 20, 20, 22, 22, 22, 23, 22, 23, 23, 23, 23, 23, 24, 23, 24, 24, 22, 23, 24, 23, 23, 23, 23, 21, 22, 23, 22, 23, 23, 24, 22, 21, 20, 22, 22, 23, 23, 21, 23, 22, 22, 24, 21, 22, 23, 23, 21, 21, 22, 21, 23, 22, 23, 23, 20, 22, 22, 22, 23, 22, 22, 23, 26, 26, 20, 19, 22, 23, 22, 25, 26, 26, 26, 27, 27, 26, 24, 25, 19, 21, 26, 27, 27, 26, 27, 24, 21, 21, 26, 26, 28, 27, 27, 27, 20, 24, 20, 21, 22, 21, 21, 23, 22, 22, 25, 25, 24, 24, 26, 23, 26, 27, 26, 26, 27, 27, 27, 27, 27, 28, 27, 27, 27, 27, 27, 26]

const _EOS_CODE := 1073741823
const _EOS_LEN := 30

_HUFF_DECODE := [null]

func _huff_table():
    if _HUFF_DECODE[0] == null:
        d := {}
        i := 0
        while i < 256:
            d[(_HUFF_LENS[i] << 32) | _HUFF_CODES[i]] = i
            i += 1
        _HUFF_DECODE[0] = d
    return _HUFF_DECODE[0]

# Décodage de Huffman HPACK (list[int] -> str brute) ; ProtocolError si le code est invalide ou mal rembourré.
func huffman_decode(data):
    table := _huff_table()
    out := []
    code := 0
    size := 0
    for b in data:
        bit := 7
        while bit >= 0:
            code = (code << 1) | ((b >> bit) & 1)
            size += 1
            key := (size << 32) | code
            if contains_key(table, key):
                append(out, table[key])
                code = 0
                size = 0
            elif size > 30:
                _proto("HPACK : code de Huffman invalide")
            bit -= 1
    # remplissage : au plus 7 bits, tous à 1 (préfixe du code EOS)
    if size > 7 or code != (1 << size) - 1:
        _proto("HPACK : remplissage de Huffman invalide")
    return _n.from_bytes(out)

func huffman_encode(text):
    out := []
    acc := 0
    nbits := 0
    for b in _n.to_bytes(text):
        acc = (acc << _HUFF_LENS[b]) | _HUFF_CODES[b]
        nbits += _HUFF_LENS[b]
        while nbits >= 8:
            nbits -= 8
            append(out, (acc >> nbits) & 255)
        acc = acc & ((1 << nbits) - 1)
    if nbits > 0:
        append(out, ((acc << (8 - nbits)) | ((1 << (8 - nbits)) - 1)) & 255)
    return out

func _huffman_length(text):
    n := 0
    for b in _n.to_bytes(text):
        n += _HUFF_LENS[b]
    return (n + 7) // 8

func _encode_int(out, value, prefix_bits, first_byte_flags):
    limit := (1 << prefix_bits) - 1
    if value < limit:
        append(out, first_byte_flags | value)
        return
    append(out, first_byte_flags | limit)
    v := value - limit
    while v >= 128:
        append(out, (v & 127) | 128)
        v = v >> 7
    append(out, v)

class _Cursor:
    func init(data):
        self.data = data
        self.pos = 0

    func byte():
        if self.pos >= len(self.data):
            _proto("HPACK : bloc d'en-têtes tronqué")
        b := self.data[self.pos]
        self.pos += 1
        return b

    func integer(prefix_bits, first):
        limit := (1 << prefix_bits) - 1
        v := first & limit
        if v < limit:
            return v
        shift := 0
        while true:
            b := self.byte()
            v += (b & 127) << shift
            shift += 7
            if shift > 28:
                _proto("HPACK : entier trop grand")
            if (b & 128) == 0:
                return v

    func string():
        first := self.byte()
        huff := (first & 128) != 0
        n := self.integer(7, first)
        if self.pos + n > len(self.data):
            _proto("HPACK : chaîne tronquée")
        raw := self.data[self.pos:self.pos + n]
        self.pos += n
        if huff:
            return huffman_decode(raw)
        return _n.from_bytes(raw)

class HpackDecoder:
    func init(max_table_size=4096, max_header_list_size=65536):
        self.dynamic = []         # [nom, valeur], le plus récent en premier
        self.size = 0
        self.max_size = max_table_size
        self.allowed_max = max_table_size
        self.max_list = max_header_list_size

    func _entry(index):
        if index < 1:
            _proto("HPACK : index 0")
        if index <= len(_STATIC):
            return _STATIC[index - 1]
        k := index - len(_STATIC) - 1
        if k >= len(self.dynamic):
            _proto("HPACK : index " + str(index) + " hors de la table")
        return self.dynamic[k]

    func _evict():
        while self.size > self.max_size and len(self.dynamic) > 0:
            last := self.dynamic[len(self.dynamic) - 1]
            self.size -= _n.blen(last[0]) + _n.blen(last[1]) + 32
            self.dynamic = self.dynamic[0:len(self.dynamic) - 1]

    func _add(name, value):
        sz := _n.blen(name) + _n.blen(value) + 32
        if sz > self.max_size:
            self.dynamic = []
            self.size = 0
            return
        self.dynamic = [[name, value]] + self.dynamic
        self.size += sz
        self._evict()

    # Liste de [nom, valeur] d'un bloc d'en-têtes (list[int]).
    func decode(block):
        c := _Cursor(block)
        out := []
        total := 0
        seen_field := false
        while c.pos < len(block):
            b := c.byte()
            name := null
            value := null
            if (b & 128) != 0:                  # champ indexé
                e := self._entry(c.integer(7, b))
                name = e[0]
                value = e[1]
            elif (b & 192) == 64:                # littéral avec indexation
                idx := c.integer(6, b)
                if idx == 0:
                    name = c.string()
                else:
                    name = self._entry(idx)[0]
                value = c.string()
                self._add(name, value)
            elif (b & 224) == 32:                # mise à jour de la taille de la table
                if seen_field:
                    _proto("HPACK : mise à jour de taille après un champ")
                sz := c.integer(5, b)
                if sz > self.allowed_max:
                    _proto("HPACK : taille de table " + str(sz) + " au-delà du maximum annoncé")
                self.max_size = sz
                self._evict()
                continue
            else:                                # littéral sans indexation (0000) / jamais indexé (0001)
                idx := c.integer(4, b)
                if idx == 0:
                    name = c.string()
                else:
                    name = self._entry(idx)[0]
                value = c.string()
            seen_field = true
            total += _n.blen(name) + _n.blen(value) + 32
            if total > self.max_list:
                _proto("HPACK : liste d'en-têtes trop grande")
            append(out, [name, value])
        return out

class HpackEncoder:
    # use_huffman : coder les chaînes en Huffman quand c'est plus court.
    func init(use_huffman=true):
        self.use_huffman = use_huffman
        self.pending_size = null

    func _string(out, s):
        raw := s
        if self.use_huffman and _huffman_length(raw) < _n.blen(raw):
            enc := huffman_encode(raw)
            _encode_int(out, len(enc), 7, 128)
            for x in enc:
                append(out, x)
            return
        _encode_int(out, _n.blen(raw), 7, 0)
        for x in _n.to_bytes(raw):
            append(out, x)

    # Bloc d'en-têtes (list[int]) pour une liste de [nom, valeur] ; les noms doivent être en minuscules.
    # Aucune insertion en table dynamique (encodage sans état, toujours valide) ; les valeurs sensibles
    # (authorization, cookie) sont marquées « jamais indexées ».
    func encode(headers):
        out := []
        if self.pending_size != null:
            _encode_int(out, self.pending_size, 5, 32)
            self.pending_size = null
        for h in headers:
            name := h[0]
            value := str(h[1])
            full := 0
            name_idx := 0
            i := 0
            while i < len(_STATIC):
                if _STATIC[i][0] == name:
                    if name_idx == 0:
                        name_idx = i + 1
                    if _STATIC[i][1] == value:
                        full = i + 1
                        break
                i += 1
            if full > 0:
                _encode_int(out, full, 7, 128)
                continue
            flags := 0
            if name == "authorization" or name == "cookie" or name == "proxy-authorization":
                flags = 16
            _encode_int(out, name_idx, 4, flags)
            if name_idx == 0:
                self._string(out, name)
            self._string(out, value)
        return out

# ---------------------------------------------------------------- HTTP/2

const PREFACE := "PRI * HTTP/2.0\r\n\r\nSM\r\n\r\n"

const DATA := 0
const HEADERS := 1
const PRIORITY := 2
const RST_STREAM := 3
const SETTINGS := 4
const PUSH_PROMISE := 5
const PING := 6
const GOAWAY := 7
const WINDOW_UPDATE := 8
const CONTINUATION := 9

const FLAG_END_STREAM := 1
const FLAG_ACK := 1
const FLAG_END_HEADERS := 4
const FLAG_PADDED := 8
const FLAG_PRIORITY := 32

const SETTINGS_HEADER_TABLE_SIZE := 1
const SETTINGS_ENABLE_PUSH := 2
const SETTINGS_MAX_CONCURRENT_STREAMS := 3
const SETTINGS_INITIAL_WINDOW_SIZE := 4
const SETTINGS_MAX_FRAME_SIZE := 5
const SETTINGS_MAX_HEADER_LIST_SIZE := 6

const ERR_NO_ERROR := 0
const ERR_PROTOCOL := 1
const ERR_INTERNAL := 2
const ERR_FLOW_CONTROL := 3
const ERR_STREAM_CLOSED := 5
const ERR_FRAME_SIZE := 6
const ERR_REFUSED_STREAM := 7
const ERR_CANCEL := 8
const ERR_COMPRESSION := 9

const LOCAL_WINDOW := 4194304
const DEFAULT_WINDOW := 65535

class H2Stream:
    func init(id, send_window):
        self.id = id
        self.headers = null           # premier bloc d'en-têtes reçu
        self.trailers = null          # bloc de fin (gRPC : statut)
        self.data = ""                # données reçues non encore consommées
        self.ended = false            # END_STREAM reçu
        self.sent_end = false
        self.reset_code = null        # RST_STREAM reçu
        self.send_window = send_window
        self.received = 0

    # Prend les données reçues (et les retire du tampon).
    func take_data():
        d := self.data
        self.data = ""
        return d

    func closed():
        return self.reset_code != null or (self.ended and self.sent_end)

class H2Connection:
    # conn : network.tcp.Connection (TCP ou TLS) ; is_client : rôle.
    func init(conn, is_client):
        self.conn = conn
        self.is_client = is_client
        self.encoder = HpackEncoder()
        self.decoder = HpackDecoder()
        self.streams = {}
        self.next_id = 1
        if not is_client:
            self.next_id = 2
        self.peer_settings = {SETTINGS_HEADER_TABLE_SIZE: 4096, SETTINGS_ENABLE_PUSH: 1, SETTINGS_INITIAL_WINDOW_SIZE: DEFAULT_WINDOW, SETTINGS_MAX_FRAME_SIZE: 16384, SETTINGS_MAX_CONCURRENT_STREAMS: 1000000}
        self.send_window = DEFAULT_WINDOW       # fenêtre d'envoi de la connexion
        self.recv_unacked = 0
        self.goaway = null                       # [dernier flux, code, message] reçu
        self.settings_acked = false
        self.closed = false
        self.new_streams = []                    # serveur : flux ouverts par le client, pas encore traités
        self.last_peer_stream = 0
        self.header_block = null                 # [flux, octets, drapeaux] d'un bloc en cours (CONTINUATION)
        self.pings = []
        self.timeout = 30.0

    # Démarre la connexion : préface (client), SETTINGS des deux côtés.
    func start(timeout=10.0):
        if self.is_client:
            self.conn.write(PREFACE, timeout)
        else:
            p := self.conn.read_exact(_n.blen(PREFACE), timeout)
            if p != PREFACE:
                _proto("préface HTTP/2 invalide (client HTTP/1 ?)")
        self._send_settings()
        # agrandit la fenêtre de réception de la connexion
        self._write_frame(WINDOW_UPDATE, 0, 0, _u32(LOCAL_WINDOW - DEFAULT_WINDOW))

    func _send_settings():
        payload := _setting(SETTINGS_ENABLE_PUSH, 0) + _setting(SETTINGS_INITIAL_WINDOW_SIZE, LOCAL_WINDOW) + _setting(SETTINGS_MAX_HEADER_LIST_SIZE, 65536)
        if not self.is_client:
            payload = payload + _setting(SETTINGS_MAX_CONCURRENT_STREAMS, 100)
        self._write_frame(SETTINGS, 0, 0, payload)

    func _write_frame(ftype, flags, stream_id, payload):
        n := _n.blen(payload)
        head := _n.from_bytes([(n >> 16) & 255, (n >> 8) & 255, n & 255, ftype, flags, (stream_id >> 24) & 127, (stream_id >> 16) & 255, (stream_id >> 8) & 255, stream_id & 255])
        self.conn.write(head + payload, self.timeout)

    func stream(id):
        if not contains_key(self.streams, id):
            self.streams[id] = H2Stream(id, self.peer_settings[SETTINGS_INITIAL_WINDOW_SIZE])
        return self.streams[id]

    # Nouveau flux (client) : identifiant impair suivant.
    func new_stream():
        if self.goaway != null:
            fail(UNAVAILABLE, "le serveur a fermé la connexion (GOAWAY)")
        id := self.next_id
        self.next_id += 2
        return self.stream(id)

    # Envoie un bloc d'en-têtes (CONTINUATION au besoin).
    func send_headers(stream_id, headers, end_stream=false):
        block := _n.from_bytes(self.encoder.encode(headers))
        max := self.peer_settings[SETTINGS_MAX_FRAME_SIZE]
        flags := 0
        if end_stream:
            flags = FLAG_END_STREAM
            self.stream(stream_id).sent_end = true
        total := _n.blen(block)
        if total <= max:
            self._write_frame(HEADERS, flags | FLAG_END_HEADERS, stream_id, block)
            return
        self._write_frame(HEADERS, flags, stream_id, _n.bslice(block, 0, max))
        pos := max
        while pos < total:
            end := pos + max
            f := 0
            if end >= total:
                end = total
                f = FLAG_END_HEADERS
            self._write_frame(CONTINUATION, f, stream_id, _n.bslice(block, pos, end))
            pos = end

    # Envoie des données en respectant les fenêtres de contrôle de flux (attend les WINDOW_UPDATE).
    func send_data(stream_id, data, end_stream=false, timeout=null):
        st := self.stream(stream_id)
        total := _n.blen(data)
        pos := 0
        deadline := null
        if timeout != null:
            deadline = _time.monotonic() + timeout
        while pos < total or (total == 0 and end_stream and not st.sent_end):
            if total == 0:
                self._write_frame(DATA, FLAG_END_STREAM, stream_id, "")
                st.sent_end = true
                return
            allowed := total - pos
            mf := self.peer_settings[SETTINGS_MAX_FRAME_SIZE]
            if allowed > mf:
                allowed = mf
            if allowed > self.send_window:
                allowed = self.send_window
            if allowed > st.send_window:
                allowed = st.send_window
            if allowed <= 0:
                left := null
                if deadline != null:
                    left = deadline - _time.monotonic()
                    if left <= 0:
                        raise("TimeoutError", "http2 : fenêtre d'envoi fermée trop longtemps")
                self.read_frame(left)
                if st.reset_code != null:
                    fail(CANCELLED, "flux annulé par le pair (RST_STREAM " + str(st.reset_code) + ")")
                continue
            chunk := _n.bslice(data, pos, pos + allowed)
            pos += allowed
            flags := 0
            if pos >= total and end_stream:
                flags = FLAG_END_STREAM
                st.sent_end = true
            self.send_window -= allowed
            st.send_window -= allowed
            self._write_frame(DATA, flags, stream_id, chunk)

    func reset_stream(stream_id, code=ERR_CANCEL):
        self._write_frame(RST_STREAM, 0, stream_id, _u32(code))
        st := self.stream(stream_id)
        st.reset_code = code

    func ping(timeout=5.0):
        opaque := _n.random_bytes(8)
        self._write_frame(PING, 0, 0, opaque)
        start := _time.monotonic()
        while true:
            for p in self.pings:
                if p == opaque:
                    return _time.monotonic() - start
            left := timeout - (_time.monotonic() - start)
            if left <= 0:
                raise("TimeoutError", "http2 : pas de réponse au PING")
            self.read_frame(left)

    func send_goaway(code=ERR_NO_ERROR, message=""):
        try:
            self._write_frame(GOAWAY, 0, 0, _u32(self.last_peer_stream) + _u32(code) + message)
        catch e:
            ignored := e

    func close():
        if not self.closed:
            self.send_goaway()
            self.closed = true
            self.conn.close()

    # Lit et traite une trame. Rend le type de la trame lue.
    func read_frame(timeout=null):
        head := self.conn.read_exact(9, timeout)
        h := _n.to_bytes(head)
        length := (h[0] << 16) | (h[1] << 8) | h[2]
        ftype := h[3]
        flags := h[4]
        sid := ((h[5] & 127) << 24) | (h[6] << 16) | (h[7] << 8) | h[8]
        if length > LOCAL_WINDOW or length > 16777215:
            self._connection_error(ERR_FRAME_SIZE, "trame trop grande")
        payload := ""
        if length > 0:
            payload = self.conn.read_exact(length, timeout)
        if self.header_block != null and ftype != CONTINUATION:
            self._connection_error(ERR_PROTOCOL, "CONTINUATION attendue")
        if ftype == DATA:
            self._on_data(sid, flags, payload)
        elif ftype == HEADERS:
            self._on_headers(sid, flags, payload)
        elif ftype == CONTINUATION:
            if self.header_block == null or self.header_block[0] != sid:
                self._connection_error(ERR_PROTOCOL, "CONTINUATION inattendue")
            self.header_block[1] = self.header_block[1] + payload
            if (flags & FLAG_END_HEADERS) != 0:
                hb := self.header_block
                self.header_block = null
                self._headers_complete(hb[0], hb[2], hb[1])
        elif ftype == SETTINGS:
            self._on_settings(sid, flags, payload)
        elif ftype == WINDOW_UPDATE:
            if length != 4:
                self._connection_error(ERR_FRAME_SIZE, "WINDOW_UPDATE de taille invalide")
            b := _n.to_bytes(payload)
            inc := ((b[0] & 127) << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
            if inc == 0:
                if sid == 0:
                    self._connection_error(ERR_PROTOCOL, "WINDOW_UPDATE nul")
                self.reset_stream(sid, ERR_PROTOCOL)
            elif sid == 0:
                self.send_window += inc
                if self.send_window > 2147483647:
                    self._connection_error(ERR_FLOW_CONTROL, "fenêtre de connexion trop grande")
            else:
                st := self.stream(sid)
                st.send_window += inc
        elif ftype == PING:
            if length != 8:
                self._connection_error(ERR_FRAME_SIZE, "PING de taille invalide")
            if (flags & FLAG_ACK) != 0:
                append(self.pings, payload)
            else:
                self._write_frame(PING, FLAG_ACK, 0, payload)
        elif ftype == RST_STREAM:
            b := _n.to_bytes(payload)
            if len(b) != 4:
                self._connection_error(ERR_FRAME_SIZE, "RST_STREAM de taille invalide")
            st := self.stream(sid)
            st.reset_code = (b[0] << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
        elif ftype == GOAWAY:
            b := _n.to_bytes(payload)
            last := ((b[0] & 127) << 24) | (b[1] << 16) | (b[2] << 8) | b[3]
            code := (b[4] << 24) | (b[5] << 16) | (b[6] << 8) | b[7]
            self.goaway = [last, code, _n.bslice(payload, 8, _n.blen(payload))]
        elif ftype == PUSH_PROMISE:
            self._connection_error(ERR_PROTOCOL, "PUSH_PROMISE alors que le push est désactivé")
        # PRIORITY et types inconnus : ignorés
        return ftype

    func _connection_error(code, message):
        self.send_goaway(code, message)
        self.closed = true
        try:
            self.conn.close()
        catch e:
            ignored := e
        _proto(message)

    func _strip_padding(flags, payload):
        if (flags & FLAG_PADDED) == 0:
            return payload
        if _n.blen(payload) < 1:
            self._connection_error(ERR_PROTOCOL, "remplissage invalide")
        pad := _n.to_bytes(_n.bslice(payload, 0, 1))[0]
        if pad >= _n.blen(payload):
            self._connection_error(ERR_PROTOCOL, "remplissage trop long")
        return _n.bslice(payload, 1, _n.blen(payload) - pad)

    func _on_data(sid, flags, payload):
        if sid == 0:
            self._connection_error(ERR_PROTOCOL, "DATA sur le flux 0")
        n := _n.blen(payload)
        st := self.stream(sid)
        data := self._strip_padding(flags, payload)
        st.data = st.data + data
        st.received += n
        if (flags & FLAG_END_STREAM) != 0:
            st.ended = true
        # rend aussitôt le crédit consommé (connexion et flux) ; si le pair a déjà fermé la connexion, les
        # trames déjà reçues restent lisibles : l'échec de cet envoi n'est pas une erreur
        if n > 0:
            try:
                self._write_frame(WINDOW_UPDATE, 0, 0, _u32(n))
                if not st.ended:
                    self._write_frame(WINDOW_UPDATE, 0, sid, _u32(n))
            catch e:
                if e.type != "NetworkError" and e.type != "TlsError":
                    raise(e)

    func _on_headers(sid, flags, payload):
        if sid == 0:
            self._connection_error(ERR_PROTOCOL, "HEADERS sur le flux 0")
        p := self._strip_padding(flags, payload)
        if (flags & FLAG_PRIORITY) != 0:
            p = _n.bslice(p, 5, _n.blen(p))
        if (flags & FLAG_END_HEADERS) == 0:
            self.header_block = [sid, p, flags]
            return
        self._headers_complete(sid, flags, p)

    func _headers_complete(sid, flags, block):
        hs := null
        try:
            hs = self.decoder.decode(_n.to_bytes(block))
        catch e:
            self._connection_error(ERR_COMPRESSION, e.message)
        is_new := not contains_key(self.streams, sid)
        st := self.stream(sid)
        if not self.is_client and is_new:
            if sid % 2 == 0 or sid <= self.last_peer_stream:
                self._connection_error(ERR_PROTOCOL, "identifiant de flux client invalide " + str(sid))
            self.last_peer_stream = sid
            append(self.new_streams, st)
        if st.headers == null:
            st.headers = hs
        else:
            st.trailers = hs
        if (flags & FLAG_END_STREAM) != 0:
            st.ended = true

    func _on_settings(sid, flags, payload):
        if sid != 0:
            self._connection_error(ERR_PROTOCOL, "SETTINGS sur un flux")
        if (flags & FLAG_ACK) != 0:
            self.settings_acked = true
            return
        b := _n.to_bytes(payload)
        if len(b) % 6 != 0:
            self._connection_error(ERR_FRAME_SIZE, "SETTINGS de taille invalide")
        i := 0
        while i < len(b):
            ident := (b[i] << 8) | b[i + 1]
            value := (b[i + 2] << 24) | (b[i + 3] << 16) | (b[i + 4] << 8) | b[i + 5]
            if ident == SETTINGS_INITIAL_WINDOW_SIZE:
                if value > 2147483647:
                    self._connection_error(ERR_FLOW_CONTROL, "fenêtre initiale trop grande")
                delta := value - self.peer_settings[SETTINGS_INITIAL_WINDOW_SIZE]
                for k in keys(self.streams):
                    self.streams[k].send_window += delta
            elif ident == SETTINGS_MAX_FRAME_SIZE:
                if value < 16384 or value > 16777215:
                    self._connection_error(ERR_PROTOCOL, "taille de trame maximale invalide")
            elif ident == SETTINGS_HEADER_TABLE_SIZE:
                self.encoder.pending_size = null   # encodeur sans table dynamique : rien à faire
            self.peer_settings[ident] = value
            i += 6
        self._write_frame(SETTINGS, FLAG_ACK, 0, "")

    # Lit des trames jusqu'à ce que cond() soit vraie (ou délai / fermeture).
    func wait_until(cond, timeout=null):
        deadline := null
        if timeout != null:
            deadline = _time.monotonic() + timeout
        while not cond():
            left := null
            if deadline != null:
                left = deadline - _time.monotonic()
                if left <= 0:
                    raise("TimeoutError", "http2 : délai dépassé")
            self.read_frame(left)

func _u32(v):
    return _n.from_bytes([(v >> 24) & 255, (v >> 16) & 255, (v >> 8) & 255, v & 255])

func _setting(ident, value):
    return _n.from_bytes([(ident >> 8) & 255, ident & 255]) + _u32(value)
