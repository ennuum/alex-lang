# ALEX STANDARD LIBRARY — network.encoding
#
# Encodages des protocoles Internet : base64 (RFC 4648, standard et « URL »), base32, hexadécimal, pourcentage
# (RFC 3986), quoted-printable (RFC 2045), Punycode (RFC 3492) et noms de domaine internationalisés (IDNA),
# jeux de caractères courants (UTF-8, US-ASCII, ISO-8859-1, ISO-8859-15, Windows-1252, UTF-16).
#
# Données
#   Les fonctions *_encode prennent une str (octets bruts : du texte est encodé en UTF-8 tel quel) ou une
#   list[int] d'octets ; les *_decode rendent une str d'octets bruts (qui est le texte si ce texte était UTF-8).
#   Les variantes *_bytes rendent une list[int].
#
# Erreurs : EncodingError (donnée mal formée), TypeError (argument).
#
# Exemple
#   use network.encoding as enc
#   enc.base64_encode("bonjour")              # "Ym9uam91cg=="
#   enc.base64_decode("Ym9uam91cg==")         # "bonjour"
#   enc.percent_encode("a b/é", "/")          # "a%20b/%C3%A9"
#   enc.qp_encode("café = ok")                # "caf=C3=A9 =3D ok"
#   enc.idna_encode("bücher.example")         # "xn--bcher-kva.example"
#   enc.decode_charset(latin1_octets, "iso-8859-1")

from core use len, type, to_int
from collections use append, contains_key
use string as _s
use _native_net as _n

func _fail(message):
    raise("EncodingError", "encoding : " + message)

func _raw(data, fn):
    t := type(data)
    if t == "str":
        return data
    if t == "list" or t == "tuple":
        return _n.from_bytes(data)
    raise("TypeError", "encoding." + fn + " : str ou liste d'octets attendue (obtenu '" + t + "')")

func _bytes(data, fn):
    if type(data) == "list":
        return data
    return _n.to_bytes(_raw(data, fn))

func _index_table(alphabet):
    d := {}
    i := 0
    for c in alphabet:
        d[c] = i
        i += 1
    return d

const _B64 := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
const _B64URL := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-_"
const _B32 := "ABCDEFGHIJKLMNOPQRSTUVWXYZ234567"
const _HEX := "0123456789abcdef"
const _HEXU := "0123456789ABCDEF"
_B64_IDX := _index_table(_B64)
_B64URL_IDX := _index_table(_B64URL)
_B32_IDX := _index_table(_B32)

# ---------------------------------------------------------------- base64

# base64 d'octets. url=true : alphabet « -_ » ; pad=false : sans « = » final (par défaut : avec, sauf en url).
# line_length : coupe en lignes de cette longueur (« \r\n »), comme dans un courriel (76).
func base64_encode(data, url=false, pad=null, line_length=null):
    b := _bytes(data, "base64_encode")
    alpha := _B64
    if url:
        alpha = _B64URL
    with_pad := not url
    if pad != null:
        with_pad = pad
    out := []
    n := len(b)
    i := 0
    while i + 2 < n:
        v := (b[i] << 16) | (b[i + 1] << 8) | b[i + 2]
        append(out, str(alpha[(v >> 18) & 63]) + str(alpha[(v >> 12) & 63]) + str(alpha[(v >> 6) & 63]) + str(alpha[v & 63]))
        i += 3
    rest := n - i
    if rest == 1:
        v := b[i] << 16
        t := str(alpha[(v >> 18) & 63]) + str(alpha[(v >> 12) & 63])
        if with_pad:
            t += "=="
        append(out, t)
    elif rest == 2:
        v := (b[i] << 16) | (b[i + 1] << 8)
        t := str(alpha[(v >> 18) & 63]) + str(alpha[(v >> 12) & 63]) + str(alpha[(v >> 6) & 63])
        if with_pad:
            t += "="
        append(out, t)
    s := _s.join("", out)
    if line_length != null and line_length > 0 and len(s) > line_length:
        lines := []
        k := 0
        while k < len(s):
            e := k + line_length
            if e > len(s):
                e = len(s)
            append(lines, _s.substring(s, k, e))
            k = e
        return _s.join("\r\n", lines)
    return s

func base64_decode_bytes(text, url=false):
    if type(text) != "str":
        raise("TypeError", "encoding.base64_decode : str attendue (obtenu '" + type(text) + "')")
    idx := _B64_IDX
    if url:
        idx = _B64URL_IDX
    vals := []
    pad := 0
    for c in text:
        if c == ' ' or c == '\n' or c == '\r' or c == '\t':
            continue
        if c == '=':
            pad += 1
            continue
        if pad > 0:
            _fail("base64 : caractère après le remplissage « = »")
        if not contains_key(idx, c):
            # tolérance : l'autre alphabet est accepté (jetons mixtes rencontrés en pratique)
            if url and contains_key(_B64_IDX, c):
                append(vals, _B64_IDX[c])
                continue
            if not url and contains_key(_B64URL_IDX, c):
                append(vals, _B64URL_IDX[c])
                continue
            _fail("base64 : caractère invalide '" + str(c) + "'")
        append(vals, idx[c])
    if pad > 2 or len(vals) % 4 == 1:
        _fail("base64 : longueur invalide")
    out := []
    n := len(vals)
    i := 0
    while i + 3 < n:
        w := (vals[i] << 18) | (vals[i + 1] << 12) | (vals[i + 2] << 6) | vals[i + 3]
        append(out, (w >> 16) & 255)
        append(out, (w >> 8) & 255)
        append(out, w & 255)
        i += 4
    rest := n - i
    if rest == 2:
        w := (vals[i] << 18) | (vals[i + 1] << 12)
        append(out, (w >> 16) & 255)
    elif rest == 3:
        w := (vals[i] << 18) | (vals[i + 1] << 12) | (vals[i + 2] << 6)
        append(out, (w >> 16) & 255)
        append(out, (w >> 8) & 255)
    return out

# base64 -> octets (str brute). Espaces et fins de ligne ignorés, « = » facultatif.
func base64_decode(text, url=false):
    return _n.from_bytes(base64_decode_bytes(text, url))

func is_base64(text, url=false):
    try:
        base64_decode_bytes(text, url)
        return true
    catch e:
        return false

# ---------------------------------------------------------------- base32 (RFC 4648)

func base32_encode(data, pad=true):
    b := _bytes(data, "base32_encode")
    out := ""
    buffer := 0
    bits := 0
    for x in b:
        buffer = ((buffer << 8) | x) & 65535
        bits += 8
        while bits >= 5:
            out += str(_B32[(buffer >> (bits - 5)) & 31])
            bits -= 5
    if bits > 0:
        out += str(_B32[(buffer << (5 - bits)) & 31])
    if pad:
        while len(out) % 8 != 0:
            out += "="
    return out

func base32_decode(text):
    out := []
    buffer := 0
    bits := 0
    for c in _s.upper(text):
        if c == '=' or c == ' ' or c == '\n' or c == '\r':
            continue
        if not contains_key(_B32_IDX, c):
            _fail("base32 : caractère invalide '" + str(c) + "'")
        buffer = ((buffer << 5) | _B32_IDX[c]) & 65535
        bits += 5
        if bits >= 8:
            append(out, (buffer >> (bits - 8)) & 255)
            bits -= 8
    return _n.from_bytes(out)

# ---------------------------------------------------------------- hexadécimal

func hex_encode(data, upper=false):
    alpha := _HEX
    if upper:
        alpha = _HEXU
    out := []
    for x in _bytes(data, "hex_encode"):
        append(out, str(alpha[x >> 4]) + str(alpha[x & 15]))
    return _s.join("", out)

func _hexval(c):
    if c >= '0' and c <= '9':
        return _s.ord(c) - 48
    if c >= 'a' and c <= 'f':
        return _s.ord(c) - 87
    if c >= 'A' and c <= 'F':
        return _s.ord(c) - 55
    return -1

func hex_decode(text):
    t := _s.replace(_s.replace(text, " ", ""), ":", "")
    if len(t) % 2 != 0:
        _fail("hexadécimal : longueur impaire")
    out := []
    i := 0
    while i < len(t):
        h := _hexval(t[i])
        l := _hexval(t[i + 1])
        if h < 0 or l < 0:
            _fail("hexadécimal : caractère invalide près de la position " + str(i))
        append(out, h * 16 + l)
        i += 2
    return _n.from_bytes(out)

# ---------------------------------------------------------------- pourcentage (RFC 3986)

const UNRESERVED := "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"

# Encode chaque octet hors des caractères non réservés et de `safe` en « %XX ». plus=true : espace -> « + ».
func percent_encode(text, safe="", plus=false):
    keep := {}
    for c in UNRESERVED:
        keep[_s.ord(c)] = true
    for c in safe:
        if _s.ord(c) < 128:
            keep[_s.ord(c)] = true
    out := []
    for b in _bytes(text, "percent_encode"):
        if contains_key(keep, b):
            append(out, str(_s.chr(b)))
        elif b == 32 and plus:
            append(out, "+")
        else:
            append(out, "%" + str(_HEXU[b >> 4]) + str(_HEXU[b & 15]))
    return _s.join("", out)

# Décode les « %XX » (un « % » non suivi de deux chiffres hexadécimaux reste tel quel). plus=true : « + » -> espace.
func percent_decode(text, plus=false):
    b := _n.to_bytes(_raw(text, "percent_decode"))
    out := []
    i := 0
    n := len(b)
    while i < n:
        x := b[i]
        if x == 37 and i + 2 < n:
            h := _hexval(_s.chr(b[i + 1]))
            l := _hexval(_s.chr(b[i + 2]))
            if h >= 0 and l >= 0:
                append(out, h * 16 + l)
                i += 3
                continue
        if x == 43 and plus:
            append(out, 32)
        else:
            append(out, x)
        i += 1
    return _n.from_bytes(out)

# ---------------------------------------------------------------- quoted-printable (RFC 2045, RFC 2047 « Q »)

# Encode en quoted-printable : lignes de 76 caractères au plus (coupure douce « = »), fins de ligne du texte
# conservées en « \r\n ». header=true : variante « Q » des mots encodés (espace -> « _ », pas de coupure).
func qp_encode(data, header=false, line_length=76):
    b := _bytes(data, "qp_encode")
    if header:
        out := []
        for x in b:
            if x == 32:
                append(out, "_")
            elif (x >= 48 and x <= 57) or (x >= 65 and x <= 90) or (x >= 97 and x <= 122) or x == 33 or x == 42 or x == 43 or x == 45 or x == 47:
                append(out, str(_s.chr(x)))
            else:
                append(out, "=" + str(_HEXU[x >> 4]) + str(_HEXU[x & 15]))
        return _s.join("", out)
    lines := []
    line := ""
    n := len(b)
    i := 0
    while i < n:
        x := b[i]
        if x == 13 and i + 1 < n and b[i + 1] == 10:
            line = _qp_fix_trailing(line)
            append(lines, line)
            line = ""
            i += 2
            continue
        if x == 10:
            line = _qp_fix_trailing(line)
            append(lines, line)
            line = ""
            i += 1
            continue
        tok := ""
        if (x >= 33 and x <= 126 and x != 61) or x == 32 or x == 9:
            tok = str(_s.chr(x))
        else:
            tok = "=" + str(_HEXU[x >> 4]) + str(_HEXU[x & 15])
        if len(line) + len(tok) > line_length - 1:
            append(lines, line + "=")
            line = ""
        line += tok
        i += 1
    append(lines, _qp_fix_trailing(line))
    return _s.join("\r\n", lines)

# Un espace ou une tabulation en fin de ligne doit être encodé (sinon un relais peut le supprimer).
func _qp_fix_trailing(line):
    if len(line) == 0:
        return line
    last := line[len(line) - 1]
    if last == ' ':
        return _s.substring(line, 0, len(line) - 1) + "=20"
    if last == '\t':
        return _s.substring(line, 0, len(line) - 1) + "=09"
    return line

func qp_decode_bytes(text, header=false):
    b := _n.to_bytes(_raw(text, "qp_decode"))
    out := []
    n := len(b)
    i := 0
    while i < n:
        x := b[i]
        if x == 61: # « = »
            if i + 1 < n and b[i + 1] == 10:          # coupure douce « =\n »
                i += 2
                continue
            if i + 2 < n and b[i + 1] == 13 and b[i + 2] == 10:
                i += 3
                continue
            if i + 2 < n:
                h := _hexval(_s.chr(b[i + 1]))
                l := _hexval(_s.chr(b[i + 2]))
                if h >= 0 and l >= 0:
                    append(out, h * 16 + l)
                    i += 3
                    continue
            # « = » isolé ou suivi d'espaces avant la fin de ligne : coupure douce tolérée
            j := i + 1
            while j < n and (b[j] == 32 or b[j] == 9):
                j += 1
            if j >= n:
                break
            if b[j] == 13 or b[j] == 10:
                i = j
                if b[i] == 13 and i + 1 < n and b[i + 1] == 10:
                    i += 2
                else:
                    i += 1
                continue
            append(out, x)
            i += 1
            continue
        if header and x == 95:
            append(out, 32)
        else:
            append(out, x)
        i += 1
    return out

func qp_decode(text, header=false):
    return _n.from_bytes(qp_decode_bytes(text, header))

# ---------------------------------------------------------------- Punycode (RFC 3492) et IDNA

const _PC_BASE := 36
const _PC_TMIN := 1
const _PC_TMAX := 26
const _PC_SKEW := 38
const _PC_DAMP := 700
const _PC_INITIAL_BIAS := 72
const _PC_INITIAL_N := 128

func _pc_adapt(delta, numpoints, first):
    if first:
        delta = delta // _PC_DAMP
    else:
        delta = delta // 2
    delta += delta // numpoints
    k := 0
    while delta > ((_PC_BASE - _PC_TMIN) * _PC_TMAX) // 2:
        delta = delta // (_PC_BASE - _PC_TMIN)
        k += _PC_BASE
    return k + (((_PC_BASE - _PC_TMIN + 1) * delta) // (delta + _PC_SKEW))

func _pc_digit(d):
    if d < 26:
        return str(_s.chr(97 + d))
    return str(_s.chr(22 + d))   # 26..35 -> '0'..'9'

func _pc_value(c):
    o := _s.ord(c)
    if o >= 48 and o <= 57:
        return o - 22
    if o >= 65 and o <= 90:
        return o - 65
    if o >= 97 and o <= 122:
        return o - 97
    return _PC_BASE

# Code Punycode d'un libellé Unicode (sans le préfixe « xn-- »).
func punycode_encode(text):
    cps := []
    for c in text:
        append(cps, _s.ord(c))
    out := ""
    basic := 0
    for cp in cps:
        if cp < 128:
            out += str(_s.chr(cp))
            basic += 1
    h := basic
    if basic > 0:
        out += "-"
    n := _PC_INITIAL_N
    delta := 0
    bias := _PC_INITIAL_BIAS
    total := len(cps)
    while h < total:
        m := 1114112
        for cp in cps:
            if cp >= n and cp < m:
                m = cp
        delta += (m - n) * (h + 1)
        n = m
        for cp in cps:
            if cp < n:
                delta += 1
            if cp == n:
                q := delta
                k := _PC_BASE
                while true:
                    t := k - bias
                    if t < _PC_TMIN:
                        t = _PC_TMIN
                    elif t > _PC_TMAX:
                        t = _PC_TMAX
                    if q < t:
                        break
                    out += _pc_digit(t + (q - t) % (_PC_BASE - t))
                    q = (q - t) // (_PC_BASE - t)
                    k += _PC_BASE
                out += _pc_digit(q)
                bias = _pc_adapt(delta, h + 1, h == basic)
                delta = 0
                h += 1
        delta += 1
        n += 1
    return out

# Libellé Unicode d'un code Punycode (sans « xn-- »).
func punycode_decode(text):
    out := []
    b := -1
    i := 0
    for c in text:
        if c == '-':
            b = i
        i += 1
    if b > 0:
        for c in _s.substring(text, 0, b):
            if _s.ord(c) >= 128:
                _fail("punycode : caractère non ASCII dans la partie de base")
            append(out, _s.ord(c))
    n := _PC_INITIAL_N
    bias := _PC_INITIAL_BIAS
    idx := 0
    pos := 0
    if b > 0:
        pos = b + 1
    elif b == 0:
        pos = 1
    while pos < len(text):
        oldi := idx
        w := 1
        k := _PC_BASE
        while true:
            if pos >= len(text):
                _fail("punycode : code tronqué")
            digit := _pc_value(text[pos])
            pos += 1
            if digit >= _PC_BASE:
                _fail("punycode : chiffre invalide")
            idx += digit * w
            t := k - bias
            if t < _PC_TMIN:
                t = _PC_TMIN
            elif t > _PC_TMAX:
                t = _PC_TMAX
            if digit < t:
                break
            w = w * (_PC_BASE - t)
            k += _PC_BASE
        count := len(out) + 1
        bias = _pc_adapt(idx - oldi, count, oldi == 0)
        n += idx // count
        idx = idx % count
        if n > 1114111:
            _fail("punycode : point de code hors limites")
        nxt := []
        j := 0
        while j < len(out):
            if j == idx:
                append(nxt, n)
            append(nxt, out[j])
            j += 1
        if idx >= len(out):
            append(nxt, n)
        out = nxt
        idx += 1
    parts := []
    for cp in out:
        append(parts, str(_s.chr(cp)))
    return _s.join("", parts)

func _is_ascii(s):
    for c in s:
        if _s.ord(c) >= 128:
            return false
    return true

# Nom de domaine international -> forme ASCII (« bücher.example » -> « xn--bcher-kva.example »).
# Les libellés sont mis en minuscules ; les points idéographiques (。．｡) servent aussi de séparateurs.
func idna_encode(domain):
    if type(domain) != "str":
        raise("TypeError", "encoding.idna_encode : str attendue")
    d := _s.replace(_s.replace(_s.replace(domain, "。", "."), "．", "."), "｡", ".")
    labels := []
    for label in _s.split(d, "."):
        low := _s.lower(label)
        if _is_ascii(low):
            append(labels, low)
        else:
            enc := "xn--" + punycode_encode(low)
            if len(enc) > 63:
                _fail("idna : libellé trop long « " + label + " »")
            append(labels, enc)
    return _s.join(".", labels)

# Forme ASCII -> nom Unicode (les libellés « xn-- » sont décodés).
func idna_decode(domain):
    labels := []
    for label in _s.split(domain, "."):
        if _s.starts_with(_s.lower(label), "xn--"):
            append(labels, punycode_decode(_s.substring(label, 4, len(label))))
        else:
            append(labels, label)
    return _s.join(".", labels)

# ---------------------------------------------------------------- jeux de caractères

# Windows-1252 : octets 0x80..0x9F (les autres coïncident avec ISO-8859-1). 0 : non attribué.
const _CP1252 := [8364, 0, 8218, 402, 8222, 8230, 8224, 8225, 710, 8240, 352, 8249, 338, 0, 381, 0, 0, 8216, 8217, 8220, 8221, 8226, 8211, 8212, 732, 8482, 353, 8250, 339, 0, 382, 376]
# ISO-8859-15 : différences avec ISO-8859-1 [octet, point de code].
const _LATIN9 := [[164, 8364], [166, 352], [168, 353], [180, 381], [184, 382], [188, 338], [189, 339], [190, 376]]

func _utf8_of(cp, out):
    if cp < 128:
        append(out, cp)
    elif cp < 2048:
        append(out, 192 | (cp >> 6))
        append(out, 128 | (cp & 63))
    elif cp < 65536:
        append(out, 224 | (cp >> 12))
        append(out, 128 | ((cp >> 6) & 63))
        append(out, 128 | (cp & 63))
    else:
        append(out, 240 | (cp >> 18))
        append(out, 128 | ((cp >> 12) & 63))
        append(out, 128 | ((cp >> 6) & 63))
        append(out, 128 | (cp & 63))

# Nom normalisé d'un jeu de caractères (« UTF8 », « latin1 »... -> « utf-8 », « iso-8859-1 »), ou le nom en minuscules.
func normalize_charset(name):
    if name == null:
        return "utf-8"
    n := _s.lower(_s.trim(str(name)))
    n = _s.replace(n, "_", "-")
    if n == "utf8" or n == "utf-8":
        return "utf-8"
    if n == "ascii" or n == "us-ascii" or n == "ansi-x3.4-1968" or n == "646":
        return "us-ascii"
    if n == "latin1" or n == "latin-1" or n == "iso8859-1" or n == "iso-8859-1" or n == "l1" or n == "iso-ir-100" or n == "cp819":
        return "iso-8859-1"
    if n == "latin9" or n == "latin-9" or n == "iso8859-15" or n == "iso-8859-15":
        return "iso-8859-15"
    if n == "cp1252" or n == "windows-1252" or n == "win-1252":
        return "windows-1252"
    if n == "utf16" or n == "utf-16":
        return "utf-16"
    if n == "utf-16le" or n == "utf16le":
        return "utf-16le"
    if n == "utf-16be" or n == "utf16be":
        return "utf-16be"
    return n

func is_supported_charset(name):
    c := normalize_charset(name)
    return c == "utf-8" or c == "us-ascii" or c == "iso-8859-1" or c == "iso-8859-15" or c == "windows-1252" or c == "utf-16" or c == "utf-16le" or c == "utf-16be"

# Octets dans le jeu `charset` -> texte (str UTF-8). errors="strict" lève EncodingError sur une séquence invalide,
# "replace" la remplace par U+FFFD.
func decode_charset(data, charset="utf-8", errors="strict"):
    cs := normalize_charset(charset)
    raw := _raw(data, "decode_charset")
    if cs == "utf-8" or cs == "us-ascii":
        if _n.utf8_valid(raw):
            if cs == "us-ascii" and errors == "strict":
                for x in _n.to_bytes(raw):
                    if x >= 128:
                        _fail("us-ascii : octet " + str(x) + " hors de la table")
            return raw
        if errors == "strict":
            _fail(cs + " : séquence invalide")
        return _utf8_repair(_n.to_bytes(raw))
    out := []
    if cs == "iso-8859-1" or cs == "iso-8859-15" or cs == "windows-1252":
        for x in _n.to_bytes(raw):
            cp := x
            if cs == "windows-1252" and x >= 128 and x < 160:
                cp = _CP1252[x - 128]
                if cp == 0:
                    if errors == "strict":
                        _fail("windows-1252 : octet " + str(x) + " non attribué")
                    cp = 65533
            elif cs == "iso-8859-15":
                for pair in _LATIN9:
                    if pair[0] == x:
                        cp = pair[1]
            _utf8_of(cp, out)
        return _n.from_bytes(out)
    if cs == "utf-16" or cs == "utf-16le" or cs == "utf-16be":
        b := _n.to_bytes(raw)
        little := cs == "utf-16le"
        start := 0
        if cs == "utf-16" and len(b) >= 2:
            if b[0] == 255 and b[1] == 254:
                little = true
                start = 2
            elif b[0] == 254 and b[1] == 255:
                start = 2
        if (len(b) - start) % 2 != 0:
            if errors == "strict":
                _fail("utf-16 : nombre impair d'octets")
        i := start
        while i + 1 < len(b):
            u := 0
            if little:
                u = b[i] | (b[i + 1] << 8)
            else:
                u = (b[i] << 8) | b[i + 1]
            i += 2
            if u >= 55296 and u <= 56319 and i + 1 < len(b):
                u2 := 0
                if little:
                    u2 = b[i] | (b[i + 1] << 8)
                else:
                    u2 = (b[i] << 8) | b[i + 1]
                if u2 >= 56320 and u2 <= 57343:
                    i += 2
                    _utf8_of(65536 + ((u - 55296) << 10) + (u2 - 56320), out)
                    continue
            if u >= 55296 and u <= 57343:
                if errors == "strict":
                    _fail("utf-16 : substitut isolé")
                u = 65533
            _utf8_of(u, out)
        return _n.from_bytes(out)
    _fail("jeu de caractères non pris en charge : " + str(charset))

# Texte (UTF-8) -> octets dans `charset` ; un caractère absent de la table lève EncodingError (ou devient « ? »
# avec errors="replace").
func encode_charset(text, charset="utf-8", errors="strict"):
    cs := normalize_charset(charset)
    if cs == "utf-8":
        return text
    out := []
    for c in text:
        cp := _s.ord(c)
        if cs == "us-ascii":
            if cp >= 128:
                if errors == "strict":
                    _fail("us-ascii : caractère U+" + hex_encode(_n.from_bytes([(cp >> 8) & 255, cp & 255]), true) + " hors de la table")
                cp = 63
            append(out, cp)
        elif cs == "iso-8859-1" or cs == "iso-8859-15" or cs == "windows-1252":
            v := -1
            if cs == "iso-8859-15":
                for pair in _LATIN9:
                    if pair[1] == cp:
                        v = pair[0]
                if v < 0 and cp < 256:
                    special := false
                    for pair in _LATIN9:
                        if pair[0] == cp:
                            special = true
                    if not special:
                        v = cp
            elif cs == "windows-1252":
                if cp < 128 or (cp >= 160 and cp < 256):
                    v = cp
                else:
                    k := 0
                    while k < 32:
                        if _CP1252[k] == cp and cp != 0:
                            v = 128 + k
                        k += 1
            elif cp < 256:
                v = cp
            if v < 0:
                if errors == "strict":
                    _fail(cs + " : caractère « " + str(c) + " » hors de la table")
                v = 63
            append(out, v)
        elif cs == "utf-16" or cs == "utf-16le" or cs == "utf-16be":
            little := cs == "utf-16le"
            units := [cp]
            if cp >= 65536:
                v := cp - 65536
                units = [55296 + (v >> 10), 56320 + (v & 1023)]
            for u in units:
                if little:
                    append(out, u & 255)
                    append(out, u >> 8)
                else:
                    append(out, u >> 8)
                    append(out, u & 255)
        else:
            _fail("jeu de caractères non pris en charge : " + str(charset))
    if cs == "utf-16":
        return _n.from_bytes([254, 255]) + _n.from_bytes(out)
    return _n.from_bytes(out)

# Remplace les séquences UTF-8 invalides par U+FFFD.
func _utf8_repair(b):
    out := []
    n := len(b)
    i := 0
    while i < n:
        x := b[i]
        need := -1
        lo := 0
        cp := 0
        if x < 128:
            append(out, x)
            i += 1
            continue
        elif x >= 194 and x <= 223:
            need = 1
            cp = x & 31
            lo = 128
        elif x >= 224 and x <= 239:
            need = 2
            cp = x & 15
            lo = 2048
        elif x >= 240 and x <= 244:
            need = 3
            cp = x & 7
            lo = 65536
        ok := need > 0 and i + need < n
        if ok:
            k := 1
            while k <= need:
                if (b[i + k] & 192) != 128:
                    ok = false
                    break
                cp = (cp << 6) | (b[i + k] & 63)
                k += 1
        if ok and (cp < lo or cp > 1114111 or (cp >= 55296 and cp <= 57343)):
            ok = false
        if ok:
            k := 0
            while k <= need:
                append(out, b[i + k])
                k += 1
            i += need + 1
        else:
            _utf8_of(65533, out)
            i += 1
    return _n.from_bytes(out)

# Texte UTF-8 valide (séquences invalides remplacées par U+FFFD).
func to_text(data):
    raw := _raw(data, "to_text")
    if _n.utf8_valid(raw):
        return raw
    return _utf8_repair(_n.to_bytes(raw))
