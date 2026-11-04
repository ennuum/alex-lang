# ALEX STANDARD LIBRARY — security.random_secure
#
# Nombres aléatoires CRYPTOGRAPHIQUES, tirés de l'entropie du système d'exploitation : getrandom(2) (Linux,
# par FFI) ou /dev/urandom. À utiliser pour les clés, sels, nonces, jetons de session, mots de passe — jamais le
# module random, qui est déterministe.
#
#   use security.random_secure as rs
#   cle := rs.random_bytes(32)                # liste de 32 octets
#   print(rs.token_hex(16))                   # « 9f3c... » (32 caractères)
#   print(rs.token_urlsafe(24))               # base64 URL, sans remplissage
#   print(rs.randbelow(6) + 1, rs.randint(1, 100), rs.choice(["a", "b"]))
#   print(rs.uuid4())                         # UUID version 4
#   print(rs.password(16))                    # au moins une minuscule, majuscule, chiffre et symbole
#   print(rs.source())                        # "getrandom" | "/dev/urandom"
#
# Les tirages bornés sont sans biais (rejet). Erreurs : SecurityError (aucune source d'entropie),
# ArgumentError (bornes, longueur).

from core use len, type
from collections use append
use string as _s
use io as _io
use os as _os
use crypto as _c
use ffi as _ffi
use _native_fd as _f

_state := [null, null, -1]      # [source, fonction getrandom ffi, descripteur /dev/urandom]

func _init():
    if _state[0] != null:
        return
    try:
        lib := _ffi.Library(null)
        if lib.has("getrandom"):
            _state[1] = lib.function("getrandom", ["ptr", "u64", "u32"], "i64")
            _state[0] = "getrandom"
            return
    catch e:
        _state[1] = null
    if _os.exists("/dev/urandom"):
        fd := _f.open_device("/dev/urandom", false)
        if type(fd) == "int" and fd >= 0:
            _state[2] = fd
            _state[0] = "/dev/urandom"
            return
    raise("SecurityError", "random_secure : aucune source d'entropie du système disponible")

func source():
    _init()
    return _state[0]

func random_bytes(n):
    if type(n) != "int" or n < 0:
        raise("ArgumentError", "random_bytes : longueur entière >= 0 attendue")
    if n == 0:
        return []
    _init()
    if _state[0] == "getrandom":
        buf := _ffi.Buffer(n)
        try:
            got := 0
            while got < n:
                r := _state[1].call([buf.address() + got, n - got, 0])
                if r <= 0:
                    raise("SecurityError", "getrandom a échoué")
                got += r
            return buf.read_array("u8", n)
        finally:
            buf.free()
    out := []
    while len(out) < n:
        data := _f.read(_state[2], n - len(out), 1.0)
        if type(data) != "str" or _s.byte_len(data) == 0:
            raise("SecurityError", "lecture de /dev/urandom impossible")
        k := 0
        while k < _s.byte_len(data):
            append(out, _s.byte_at(data, k))
            k += 1
    return out

func token_bytes(n=32):
    return random_bytes(n)

func token_hex(n=32):
    return _c.hex_encode(random_bytes(n))

func token_urlsafe(n=32):
    return _c.base64_encode(random_bytes(n), true)

# Entier uniforme dans [0, n[ (sans biais).
func randbelow(n):
    if type(n) != "int" or n <= 0:
        raise("ArgumentError", "randbelow : n entier > 0 attendu")
    if n == 1:
        return 0
    bits := 0
    m := n - 1
    while m > 0:
        bits += 1
        m = m // 2
    nbytes := (bits + 7) // 8
    mask := 1
    i := 0
    while i < bits:
        mask = mask * 2
        i += 1
    mask -= 1
    while true:
        b := random_bytes(nbytes)
        v := 0
        for x in b:
            v = v * 256 + x
        v = v & mask
        if v < n:
            return v

func randint(a, b):
    if b < a:
        raise("ArgumentError", "randint : b >= a attendu")
    return a + randbelow(b - a + 1)

func choice(seq):
    if len(seq) == 0:
        raise("ArgumentError", "choice : séquence vide")
    return seq[randbelow(len(seq))]

func shuffle(items):
    i := len(items) - 1
    while i > 0:
        j := randbelow(i + 1)
        t := items[i]
        items[i] = items[j]
        items[j] = t
        i -= 1
    return items

func sample(items, k):
    if k > len(items):
        raise("ArgumentError", "sample : k plus grand que la population")
    pool := items[:]
    shuffle(pool)
    return pool[:k]

# Réel uniforme dans [0, 1[ (53 bits).
func random():
    b := random_bytes(7)
    v := 0
    for x in b:
        v = v * 256 + x
    v = v // 8
    return v / 9007199254740992.0

func uuid4():
    b := random_bytes(16)
    b[6] = (b[6] & 15) | 64
    b[8] = (b[8] & 63) | 128
    h := _c.hex_encode(b)
    return _s.substring(h, 0, 8) + "-" + _s.substring(h, 8, 12) + "-" + _s.substring(h, 12, 16) + "-" + _s.substring(h, 16, 20) + "-" + _s.substring(h, 20, 32)

const LOWER := "abcdefghijklmnopqrstuvwxyz"
const UPPER := "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
const DIGITS := "0123456789"
const SYMBOLS := "!#$%&*+-=?@^_~"

# Mot de passe aléatoire ; avec classes=true : au moins un caractère de chaque classe.
func password(length=16, alphabet=null, classes=true):
    if length < 4 and classes:
        raise("ArgumentError", "password : 4 caractères au moins avec classes=true")
    al := alphabet
    if al == null:
        al = LOWER + UPPER + DIGITS + SYMBOLS
    while true:
        out := [str(choice(al)) for i in 0..length]
        if not classes or alphabet != null:
            return _s.join("", out)
        pw := _s.join("", out)
        if _has_any(pw, LOWER) and _has_any(pw, UPPER) and _has_any(pw, DIGITS) and _has_any(pw, SYMBOLS):
            return pw

func _has_any(text, chars):
    for c in text:
        if _s.contains(chars, str(c)):
            return true
    return false

class SecureRandom:
    func bytes(n):
        return random_bytes(n)

    func randbelow(n):
        return randbelow(n)

    func randint(a, b):
        return randint(a, b)

    func random():
        return random()

    func choice(seq):
        return choice(seq)

    func shuffle(items):
        return shuffle(items)
