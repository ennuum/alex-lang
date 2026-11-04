# ALEX STANDARD LIBRARY — web.url.percent_encoding
#
# Encodage « pour cent » des URL (RFC 3986 §2.1, WHATWG URL §1.3) : chaque octet UTF-8 hors de l'ensemble permis
# devient « %XX » (hexadécimal majuscule). Le décodage rend la str UTF-8 d'origine et vérifie que les octets
# obtenus forment de l'UTF-8 valide.
#
# Ensembles d'encodage (du plus permissif au plus strict), comme un navigateur :
#   encode_fragment   contrôles, espace, " < > `
#   encode_query      contrôles, espace, " # < >
#   encode_path       ensemble « query » + ? ` { }
#   encode_userinfo   ensemble « path » + / : ; = @ [ \ ] ^ |
#   encode_component  ensemble « userinfo » + $ % & + ,   (équivalent de encodeURIComponent)
#   encode            strict RFC 3986 : tout sauf les non réservés (A-Z a-z 0-9 - . _ ~) et `safe`
#
#   use web.url.percent_encoding as pe
#   pe.encode("a b/é")              # a%20b%2F%C3%A9
#   pe.encode("a b/é", "/")         # a%20b/%C3%A9
#   pe.encode_path("/a b/?x")       # /a%20b/%3Fx
#   pe.decode("caf%C3%A9+noir")     # café+noir
#   pe.decode("caf%C3%A9+noir", true)   # café noir   (formulaire : « + » est un espace)
#   pe.normalize("%7e%2f")          # ~%2F         (non réservés décodés, hexadécimal en majuscules)
#
# Erreurs : UrlEncodingError (décodage strict : « % » isolé, UTF-8 invalide), TypeError.

from core use len, type
from collections use append
use string as _s
use web.url.url_errors as _err

const HEX_DIGITS := "0123456789ABCDEF"
const UNRESERVED_MARKS := "-._~"
const SUB_DELIMS := "!$&'()*+,;="
const GEN_DELIMS := ":/?#[]@"

# Caractères qu'un segment de chemin peut porter sans encodage (pchar sans « % ») : non réservés, sub-delims, : @
const PCHAR_SAFE := "!$&'()*+,;=:@"
# Caractères permis tels quels dans une requête ou un fragment (RFC 3986 §3.4, §3.5) : pchar, « / », « ? »
const QUERY_SAFE := "!$&'()*+,;=:@/?"

const _FRAGMENT_SET := " \"<>`"
const _QUERY_SET := " \"#<>"
const _PATH_SET := " \"#<>?`{}"
const _USERINFO_SET := " \"#<>?`{}/:;=@[\\]^|"
const _COMPONENT_SET := " \"#<>?`{}/:;=@[\\]^|$%&+,"

func is_alpha_byte(b):
    return (b >= 65 and b <= 90) or (b >= 97 and b <= 122)

func is_digit_byte(b):
    return b >= 48 and b <= 57

func is_hex_byte(b):
    return is_digit_byte(b) or (b >= 65 and b <= 70) or (b >= 97 and b <= 102)

func hex_value(b):
    if b >= 48 and b <= 57:
        return b - 48
    if b >= 65 and b <= 70:
        return b - 55
    if b >= 97 and b <= 102:
        return b - 87
    return -1

# Vrai pour un caractère (char ou str d'un caractère) non réservé : A-Z a-z 0-9 - . _ ~
func is_unreserved(c):
    b := _s.ord(c)
    return _is_unreserved_byte(b)

func _is_unreserved_byte(b):
    return is_alpha_byte(b) or is_digit_byte(b) or b == 45 or b == 46 or b == 95 or b == 126

func is_sub_delim(c):
    return c in SUB_DELIMS

func is_gen_delim(c):
    return c in GEN_DELIMS

func is_reserved(c):
    return is_sub_delim(c) or is_gen_delim(c)

# « %XX » pour un octet (0..255).
func escape_byte(b):
    return "%" + str(HEX_DIGITS[(b >> 4) & 15]) + str(HEX_DIGITS[b & 15])

# ---------------------------------------------------------------- encodage

# Encodage strict : tout octet est encodé, sauf les non réservés et les caractères ASCII de `safe`.
# space_as_plus : l'espace devient « + » (formulaires).
func encode(text, safe="", space_as_plus=false):
    _err.need_str("percent_encoding.encode", "text", text)
    _err.need_str("percent_encoding.encode", "safe", safe)
    out := []
    for b in _s.byte_unpack(text):
        if _is_unreserved_byte(b):
            append(out, _s.byte_char(b))
        elif b == 32 and space_as_plus:
            append(out, "+")
        elif b < 128 and b > 32 and _s.byte_char(b) in safe:
            append(out, _s.byte_char(b))
        else:
            append(out, escape_byte(b))
    return _s.join("", out)

# Encode les octets non ASCII, les contrôles (0x00-0x1F, 0x7F) et les caractères de `chars` ; garde le reste.
# keep_escapes : un « %XX » déjà présent est conservé tel quel (sinon « % » devient « %25 » s'il est dans chars).
func encode_set(text, chars, keep_escapes=true):
    _err.need_str("percent_encoding.encode_set", "text", text)
    bytes := _s.byte_unpack(text)
    n := len(bytes)
    out := []
    i := 0
    while i < n:
        b := bytes[i]
        if b == 37 and keep_escapes and i + 2 < n and is_hex_byte(bytes[i + 1]) and is_hex_byte(bytes[i + 2]):
            append(out, "%")
        elif b < 32 or b >= 127:
            append(out, escape_byte(b))
        elif _s.byte_char(b) in chars:
            append(out, escape_byte(b))
        else:
            append(out, _s.byte_char(b))
        i += 1
    return _s.join("", out)

func encode_fragment(text):
    return encode_set(text, _FRAGMENT_SET)

func encode_query(text, special=true):
    if special:
        return encode_set(text, _QUERY_SET + "'")
    return encode_set(text, _QUERY_SET)

func encode_path(text):
    return encode_set(text, _PATH_SET)

func encode_userinfo(text):
    return encode_set(text, _USERINFO_SET)

# Comme encodeURIComponent de JavaScript : seuls A-Z a-z 0-9 - _ . ! ~ * ' ( ) restent tels quels.
func encode_component(text):
    return encode_set(text, _COMPONENT_SET, false)

# Encode un segment de chemin (« / » compris) : la valeur décodée d'un segment devient sa forme dans l'URL.
func encode_segment(text):
    return encode(text, PCHAR_SAFE)

# ---------------------------------------------------------------- décodage

# Décode les « %XX » (et « + » en espace si plus_as_space). strict : « % » non suivi de deux chiffres
# hexadécimaux est une erreur (sinon gardé tel quel) ; le résultat doit être de l'UTF-8 valide.
func decode(text, plus_as_space=false, strict=false):
    _err.need_str("percent_encoding.decode", "text", text)
    if not ("%" in text) and not (plus_as_space and "+" in text):
        return text
    bytes := _s.byte_unpack(text)
    n := len(bytes)
    out := []
    i := 0
    while i < n:
        b := bytes[i]
        if b == 37:
            if i + 2 < n and is_hex_byte(bytes[i + 1]) and is_hex_byte(bytes[i + 2]):
                append(out, hex_value(bytes[i + 1]) * 16 + hex_value(bytes[i + 2]))
                i += 3
                continue
            if strict:
                _err.encoding_error("percent_encoding.decode", "« % » non suivi de deux chiffres hexadécimaux à l'octet " + str(i) + " dans '" + text + "'")
            append(out, b)
        elif b == 43 and plus_as_space:
            append(out, 32)
        else:
            append(out, b)
        i += 1
    if not is_valid_utf8(out):
        if strict:
            _err.encoding_error("percent_encoding.decode", "les octets décodés de '" + text + "' ne sont pas de l'UTF-8 valide")
        return _s.byte_pack(_replace_invalid(out))
    return _s.byte_pack(out)

# Décodage strict (erreur au lieu de tolérance).
func decode_strict(text, plus_as_space=false):
    return decode(text, plus_as_space, true)

# Vrai si text ne contient que des « %XX » bien formés (aucun « % » isolé).
func is_well_formed(text):
    bytes := _s.byte_unpack(text)
    n := len(bytes)
    i := 0
    while i < n:
        if bytes[i] == 37:
            if i + 2 >= n or not is_hex_byte(bytes[i + 1]) or not is_hex_byte(bytes[i + 2]):
                return false
            i += 3
        else:
            i += 1
    return true

# Normalisation RFC 3986 §6.2.2 : hexadécimal en majuscules, octets non réservés décodés (« %7E » -> « ~ »).
func normalize(text):
    bytes := _s.byte_unpack(text)
    n := len(bytes)
    out := []
    i := 0
    while i < n:
        b := bytes[i]
        if b == 37 and i + 2 < n and is_hex_byte(bytes[i + 1]) and is_hex_byte(bytes[i + 2]):
            v := hex_value(bytes[i + 1]) * 16 + hex_value(bytes[i + 2])
            if _is_unreserved_byte(v):
                append(out, _s.byte_char(v))
            else:
                append(out, escape_byte(v))
            i += 3
        else:
            append(out, _s.byte_char(b))
            i += 1
    return _s.join("", out)

# ---------------------------------------------------------------- UTF-8

# Vrai si la liste d'octets est de l'UTF-8 valide (formes les plus courtes, pas de substituts, <= U+10FFFF).
func is_valid_utf8(bytes):
    n := len(bytes)
    i := 0
    while i < n:
        k := _utf8_seq_len(bytes, i, n)
        if k == 0:
            return false
        i += k
    return true

# Longueur de la séquence UTF-8 valide commençant en i, ou 0.
func _utf8_seq_len(bytes, i, n):
    b := bytes[i]
    if b < 128:
        return 1
    need := 0
    lo := 128
    hi := 191
    if b >= 194 and b <= 223:
        need = 1
    elif b >= 224 and b <= 239:
        need = 2
        if b == 224:
            lo = 160
        if b == 237:
            hi = 159
    elif b >= 240 and b <= 244:
        need = 3
        if b == 240:
            lo = 144
        if b == 244:
            hi = 143
    else:
        return 0
    if i + need >= n:
        return 0
    j := 1
    while j <= need:
        c := bytes[i + j]
        if j == 1:
            if c < lo or c > hi:
                return 0
        elif c < 128 or c > 191:
            return 0
        j += 1
    return need + 1

# Remplace chaque séquence invalide par U+FFFD (EF BF BD), comme un navigateur.
func _replace_invalid(bytes):
    out := []
    n := len(bytes)
    i := 0
    while i < n:
        k := _utf8_seq_len(bytes, i, n)
        if k == 0:
            append(out, 239)
            append(out, 191)
            append(out, 189)
            i += 1
        else:
            j := 0
            while j < k:
                append(out, bytes[i + j])
                j += 1
            i += k
    return out
