# ALEX STANDARD LIBRARY — web.url.host
#
# Hôtes d'URL (RFC 3986 §3.2.2, WHATWG URL §3) : nom de domaine, adresse IPv4, adresse IPv6 (entre crochets dans
# l'URL), hôte « opaque » des schémas non spéciaux, hôte vide (file:///).
#
# Analyse comme un navigateur pour les schémas spéciaux : décodage « %XX », minuscules, noms internationalisés
# convertis en ASCII (Punycode, « xn-- »), formes IPv4 abrégées ou hexadécimales normalisées (« 0x7f.1 » ->
# « 127.0.0.1 »), IPv6 compressée selon la RFC 5952 (« 2001:db8:0:0:0:0:0:1 » -> « 2001:db8::1 »).
#
#   use web.url.host as h
#   x := h.parse("Bücher.Example")     # x.kind == "domain", x.text == "xn--bcher-kva.example"
#   h.parse("[2001:DB8::0:1]").serialize()   # [2001:db8::1]
#   h.parse("0x7f.1").text             # 127.0.0.1
#   h.to_unicode("xn--bcher-kva.example")    # bücher.example
#   h.is_ip("::1")                     # true
#
# Erreurs : UrlHostError.

from core use len, type
from collections use append
use string as _s
use web.url.url_errors as _err
use web.url.percent_encoding as _pe

const DOMAIN := "domain"
const IPV4 := "ipv4"
const IPV6 := "ipv6"
const OPAQUE := "opaque"
const EMPTY := "empty"

const _FORBIDDEN_HOST := " #/:<>?@[\\]^|"
const _FORBIDDEN_DOMAIN_EXTRA := "%"

class Host:
    func init(kind, text):
        self.kind = kind      # domain, ipv4, ipv6, opaque, empty
        self.text = text      # forme canonique, sans crochets pour IPv6

    # Forme dans une URL (IPv6 entre crochets).
    func serialize():
        if self.kind == IPV6:
            return "[" + self.text + "]"
        return self.text

    func is_ip():
        return self.kind == IPV4 or self.kind == IPV6

    func is_domain():
        return self.kind == DOMAIN

    func is_empty():
        return self.kind == EMPTY

    # Vrai pour localhost, 127.0.0.0/8 et ::1.
    func is_loopback():
        if self.kind == DOMAIN:
            return self.text == "localhost" or _s.ends_with(self.text, ".localhost")
        if self.kind == IPV4:
            return _s.starts_with(self.text, "127.")
        if self.kind == IPV6:
            return self.text == "::1"
        return false

    # Nom affichable (étiquettes « xn-- » décodées).
    func display():
        if self.kind == DOMAIN:
            return to_unicode(self.text)
        return self.serialize()

    func __str__():
        return self.serialize()

    func __eq__(other):
        return isinstance(other, Host) and other.kind == self.kind and other.text == self.text

# ---------------------------------------------------------------- analyse

# Analyse un hôte tel qu'il apparaît dans une URL. special : schéma spécial (http, https, ws, wss, ftp, file) ;
# sinon l'hôte est « opaque » (seulement encodé).
func parse(text, special=true):
    _err.need_str("host.parse", "text", text)
    if len(text) > 0 and text[0] == '[':
        if text[len(text) - 1] != ']':
            _err.host_error("host.parse", "IPv6 sans « ] » final dans '" + text + "'")
        return Host(IPV6, ipv6_serialize(ipv6_parse(text[1:len(text) - 1])))
    if text == "":
        if special:
            return Host(EMPTY, "")
        return Host(EMPTY, "")
    if not special:
        for c in text:
            if c in _FORBIDDEN_HOST:
                _err.host_error("host.parse", "caractère interdit « " + str(c) + " » dans l'hôte '" + text + "'")
        return Host(OPAQUE, _pe.encode_set(text, ""))
    domain := _pe.decode(text)
    ascii := to_ascii(domain)
    for c in ascii:
        o := _s.ord(c)
        if o <= 32 or o == 127 or c in _FORBIDDEN_HOST or c in _FORBIDDEN_DOMAIN_EXTRA:
            _err.host_error("host.parse", "caractère interdit « " + _printable(c) + " » dans l'hôte '" + text + "'")
    if _ends_in_number(ascii):
        return Host(IPV4, ipv4_serialize(ipv4_parse(ascii)))
    return Host(DOMAIN, ascii)

func _printable(c):
    o := _s.ord(c)
    if o < 32 or o == 127:
        return "U+" + _hex4(o)
    return str(c)

func _hex4(v):
    digits := "0123456789ABCDEF"
    out := ""
    i := 0
    while i < 4:
        out = str(digits[v & 15]) + out
        v = v >> 4
        i += 1
    return out

# Hôte sous forme de texte canonique (raccourci de parse(text).serialize()).
func normalize(text, special=true):
    return parse(text, special).serialize()

func is_ipv4(text):
    try:
        if not _ends_in_number(text):
            return false
        ipv4_parse(text)
        return true
    catch e:
        return false

func is_ipv6(text):
    t := text
    if len(t) >= 2 and t[0] == '[' and t[len(t) - 1] == ']':
        t = t[1:len(t) - 1]
    try:
        ipv6_parse(t)
        return true
    catch e:
        return false

func is_ip(text):
    return is_ipv4(text) or is_ipv6(text)

# Nom de domaine valide au sens strict (RFC 1034/1123, après conversion ASCII) : étiquettes de 1 à 63 caractères
# (lettres, chiffres, « - » hors extrémités), 253 caractères au plus.
func is_valid_domain(name):
    ascii := ""
    try:
        ascii = to_ascii(name)
    catch e:
        return false
    if len(ascii) == 0 or len(ascii) > 253:
        return false
    if ascii[len(ascii) - 1] == '.':
        ascii = ascii[0:len(ascii) - 1]
    for label in _s.split(ascii, "."):
        if len(label) == 0 or len(label) > 63:
            return false
        if label[0] == '-' or label[len(label) - 1] == '-':
            return false
        for c in label:
            if not ((c >= 'a' and c <= 'z') or (c >= '0' and c <= '9') or c == '-'):
                return false
    return true

# ---------------------------------------------------------------- IPv4 (WHATWG)

func _ends_in_number(text):
    parts := _s.split(text, ".")
    if len(parts) > 1 and parts[len(parts) - 1] == "":
        parts = parts[0:len(parts) - 1]
    last := parts[len(parts) - 1]
    if last == "":
        return false
    all_digits := true
    for c in last:
        if c < '0' or c > '9':
            all_digits = false
    if all_digits:
        return true
    return _parse_ipv4_number(last) != null

# Valeur d'une partie IPv4 (décimal, « 0x » hexadécimal, « 0 » octal), ou null.
func _parse_ipv4_number(part):
    if part == "":
        return null
    radix := 10
    t := part
    if len(t) >= 2 and t[0] == '0' and (t[1] == 'x' or t[1] == 'X'):
        radix = 16
        t = t[2:len(t)]
    elif len(t) >= 2 and t[0] == '0':
        radix = 8
        t = t[1:len(t)]
    if t == "":
        return 0
    value := 0
    for c in t:
        d := _pe.hex_value(_s.ord(c))
        if d < 0 or d >= radix:
            return null
        value = value * radix + d
        if value > 4294967295:
            return 4294967296
    return value

# Adresse IPv4 en entier 32 bits ; UrlHostError si invalide.
func ipv4_parse(text):
    parts := _s.split(text, ".")
    if len(parts) > 1 and parts[len(parts) - 1] == "":
        parts = parts[0:len(parts) - 1]
    if len(parts) > 4:
        _err.host_error("host.ipv4_parse", "plus de quatre parties dans '" + text + "'")
    nums := []
    for p in parts:
        v := _parse_ipv4_number(p)
        if v == null:
            _err.host_error("host.ipv4_parse", "partie invalide « " + p + " » dans '" + text + "'")
        append(nums, v)
    n := len(nums)
    i := 0
    while i < n - 1:
        if nums[i] > 255:
            _err.host_error("host.ipv4_parse", "partie supérieure à 255 dans '" + text + "'")
        i += 1
    limit := 1
    k := 0
    while k < 5 - n:
        limit = limit * 256
        k += 1
    if nums[n - 1] >= limit:
        _err.host_error("host.ipv4_parse", "dernière partie trop grande dans '" + text + "'")
    value := nums[n - 1]
    i = 0
    while i < n - 1:
        shift := 1
        j := 0
        while j < 3 - i:
            shift = shift * 256
            j += 1
        value = value + nums[i] * shift
        i += 1
    return value

func ipv4_serialize(value):
    return str((value >> 24) & 255) + "." + str((value >> 16) & 255) + "." + str((value >> 8) & 255) + "." + str(value & 255)

# ---------------------------------------------------------------- IPv6 (WHATWG / RFC 4291)

# Adresse IPv6 (sans crochets) en liste de 8 entiers 16 bits ; UrlHostError si invalide.
func ipv6_parse(text):
    fn := "host.ipv6_parse"
    pieces := [0, 0, 0, 0, 0, 0, 0, 0]
    idx := 0
    compress := -1
    n := len(text)
    p := 0
    if n == 0:
        _err.host_error(fn, "adresse IPv6 vide")
    if text[0] == ':':
        if n < 2 or text[1] != ':':
            _err.host_error(fn, "« : » initial isolé dans '" + text + "'")
        p = 2
        idx = 1
        compress = 1
    while p < n:
        if idx == 8:
            _err.host_error(fn, "plus de huit groupes dans '" + text + "'")
        if text[p] == ':':
            if compress != -1:
                _err.host_error(fn, "« :: » répété dans '" + text + "'")
            p += 1
            idx += 1
            compress = idx
            continue
        value := 0
        length := 0
        while length < 4 and p < n and _pe.hex_value(_s.ord(text[p])) >= 0:
            value = value * 16 + _pe.hex_value(_s.ord(text[p]))
            p += 1
            length += 1
        if p < n and text[p] == '.':
            if length == 0:
                _err.host_error(fn, "IPv4 incluse invalide dans '" + text + "'")
            p -= length
            if idx > 6:
                _err.host_error(fn, "IPv4 incluse trop loin dans '" + text + "'")
            seen := 0
            while p < n:
                ipv4_piece := -1
                if seen > 0:
                    if text[p] == '.' and seen < 4:
                        p += 1
                    else:
                        _err.host_error(fn, "IPv4 incluse invalide dans '" + text + "'")
                if p >= n or text[p] < '0' or text[p] > '9':
                    _err.host_error(fn, "IPv4 incluse invalide dans '" + text + "'")
                while p < n and text[p] >= '0' and text[p] <= '9':
                    d := _s.ord(text[p]) - 48
                    if ipv4_piece == -1:
                        ipv4_piece = d
                    elif ipv4_piece == 0:
                        _err.host_error(fn, "zéro initial dans l'IPv4 incluse de '" + text + "'")
                    else:
                        ipv4_piece = ipv4_piece * 10 + d
                    if ipv4_piece > 255:
                        _err.host_error(fn, "IPv4 incluse hors bornes dans '" + text + "'")
                    p += 1
                pieces[idx] = pieces[idx] * 256 + ipv4_piece
                seen += 1
                if seen == 2 or seen == 4:
                    idx += 1
            if seen != 4:
                _err.host_error(fn, "IPv4 incluse incomplète dans '" + text + "'")
            break
        elif p < n and text[p] == ':':
            p += 1
            if p >= n:
                _err.host_error(fn, "« : » final isolé dans '" + text + "'")
        elif p < n:
            _err.host_error(fn, "caractère invalide « " + str(text[p]) + " » dans '" + text + "'")
        pieces[idx] = value
        idx += 1
    if compress != -1:
        swaps := idx - compress
        idx = 7
        while idx != 0 and swaps > 0:
            tmp := pieces[compress + swaps - 1]
            pieces[compress + swaps - 1] = pieces[idx]
            pieces[idx] = tmp
            idx -= 1
            swaps -= 1
    elif idx != 8:
        _err.host_error(fn, "moins de huit groupes sans « :: » dans '" + text + "'")
    return pieces

# Forme canonique RFC 5952 : minuscules, zéros initiaux supprimés, plus longue suite de zéros (>= 2) en « :: ».
func ipv6_serialize(pieces):
    best := -1
    best_len := 1
    i := 0
    while i < 8:
        if pieces[i] == 0:
            j := i
            while j < 8 and pieces[j] == 0:
                j += 1
            if j - i > best_len:
                best = i
                best_len = j - i
            i = j
        else:
            i += 1
    out := ""
    ignore0 := false
    i = 0
    while i < 8:
        if ignore0 and pieces[i] == 0:
            i += 1
            continue
        ignore0 = false
        if best == i:
            if i == 0:
                out = out + "::"
            else:
                out = out + ":"
            ignore0 = true
            i += 1
            continue
        out = out + _hex(pieces[i])
        if i != 7:
            out = out + ":"
        i += 1
    return out

func _hex(v):
    if v == 0:
        return "0"
    digits := "0123456789abcdef"
    out := ""
    while v > 0:
        out = str(digits[v & 15]) + out
        v = v >> 4
    return out

# ---------------------------------------------------------------- Punycode / IDNA (RFC 3492, RFC 5891)

const _BASE := 36
const _TMIN := 1
const _TMAX := 26
const _SKEW := 38
const _DAMP := 700
const _INITIAL_BIAS := 72
const _INITIAL_N := 128

func _adapt(delta, numpoints, first):
    if first:
        delta = delta // _DAMP
    else:
        delta = delta // 2
    delta = delta + delta // numpoints
    k := 0
    while delta > ((_BASE - _TMIN) * _TMAX) // 2:
        delta = delta // (_BASE - _TMIN)
        k += _BASE
    return k + ((_BASE - _TMIN + 1) * delta) // (delta + _SKEW)

func _digit_char(d):
    if d < 26:
        return _s.chr(97 + d)
    return _s.chr(22 + d)

func _char_digit(c):
    o := _s.ord(c)
    if o >= 48 and o <= 57:
        return o - 22
    if o >= 65 and o <= 90:
        return o - 65
    if o >= 97 and o <= 122:
        return o - 97
    return _BASE

# Encode une étiquette Unicode en Punycode (sans le préfixe « xn-- »).
func punycode_encode(label):
    cps := []
    for c in label:
        append(cps, _s.ord(c))
    out := []
    for cp in cps:
        if cp < 128:
            append(out, str(_s.chr(cp)))
    b := len(out)
    h := b
    if b > 0:
        append(out, "-")
    n := _INITIAL_N
    delta := 0
    bias := _INITIAL_BIAS
    total := len(cps)
    while h < total:
        m := 1114112
        for cp in cps:
            if cp >= n and cp < m:
                m = cp
        delta = delta + (m - n) * (h + 1)
        n = m
        for cp in cps:
            if cp < n:
                delta += 1
            if cp == n:
                q := delta
                k := _BASE
                while true:
                    t := _TMIN
                    if k <= bias:
                        t = _TMIN
                    elif k >= bias + _TMAX:
                        t = _TMAX
                    else:
                        t = k - bias
                    if q < t:
                        break
                    append(out, str(_digit_char(t + (q - t) % (_BASE - t))))
                    q = (q - t) // (_BASE - t)
                    k += _BASE
                append(out, str(_digit_char(q)))
                bias = _adapt(delta, h + 1, h == b)
                delta = 0
                h += 1
        delta += 1
        n += 1
    return _s.join("", out)

# Décode une étiquette Punycode (sans « xn-- ») ; UrlHostError si invalide.
func punycode_decode(text):
    fn := "host.punycode_decode"
    out := []
    basic := -1
    i := 0
    while i < len(text):
        if text[i] == '-':
            basic = i
        i += 1
    if basic > 0:
        j := 0
        while j < basic:
            o := _s.ord(text[j])
            if o >= 128:
                _err.host_error(fn, "caractère non ASCII dans '" + text + "'")
            append(out, o)
            j += 1
    n := _INITIAL_N
    bias := _INITIAL_BIAS
    idx := 0
    p := 0
    if basic > 0:
        p = basic + 1
    while p < len(text):
        old := idx
        w := 1
        k := _BASE
        while true:
            if p >= len(text):
                _err.host_error(fn, "Punycode tronqué '" + text + "'")
            d := _char_digit(text[p])
            p += 1
            if d >= _BASE:
                _err.host_error(fn, "chiffre Punycode invalide dans '" + text + "'")
            idx = idx + d * w
            t := _TMIN
            if k <= bias:
                t = _TMIN
            elif k >= bias + _TMAX:
                t = _TMAX
            else:
                t = k - bias
            if d < t:
                break
            w = w * (_BASE - t)
            k += _BASE
        count := len(out) + 1
        bias = _adapt(idx - old, count, old == 0)
        n = n + idx // count
        idx = idx % count
        if n > 1114111:
            _err.host_error(fn, "point de code hors bornes dans '" + text + "'")
        rest := out[idx:len(out)]
        out = out[0:idx]
        append(out, n)
        out = out + rest
        idx += 1
    s := []
    for cp in out:
        append(s, str(_s.chr(cp)))
    return _s.join("", s)

func _is_ascii(text):
    for c in text:
        if _s.ord(c) >= 128:
            return false
    return true

# Nom de domaine en ASCII : minuscules, points idéographiques ramenés à « . », étiquettes non ASCII en « xn--… ».
func to_ascii(domain):
    _err.need_str("host.to_ascii", "domain", domain)
    d := _s.lower(domain)
    d = _s.replace(_s.replace(_s.replace(d, "。", "."), "．", "."), "｡", ".")
    if _is_ascii(d):
        return d
    labels := []
    for label in _s.split(d, "."):
        if _is_ascii(label):
            append(labels, label)
        else:
            append(labels, "xn--" + punycode_encode(label))
    return _s.join(".", labels)

# Nom de domaine affichable : étiquettes « xn--… » décodées (gardées telles quelles si invalides).
func to_unicode(domain):
    labels := []
    for label in _s.split(domain, "."):
        if _s.starts_with(_s.lower(label), "xn--"):
            try:
                append(labels, punycode_decode(label[4:len(label)]))
            catch e:
                append(labels, label)
        else:
            append(labels, label)
    return _s.join(".", labels)
