# ALEX STANDARD LIBRARY — crypto.x25519
# X25519 (RFC 7748) : échange de clés Diffie-Hellman sur Curve25519, échelle de Montgomery en temps constant
# (permutations conditionnelles par masques, aucun branchement ni accès mémoire dépendant du secret). Corps
# 2^255 - 19 en 16 limbes de 16 bits (forme de TweetNaCl).
#
#   use crypto.x25519 as x25519
#   prive := random_secure.random_bytes(32)
#   public := x25519.public_key(prive)             # 32 octets, à envoyer
#   secret := x25519.shared(prive, public_autre)   # 32 octets ; ValueError si le résultat est nul
#
# Octets : listes d'entiers 0..255. Vérifié contre la RFC 7748 (5.2, 6.1) et OpenSSL dans
# tests/stdlib2/test_crypto_pk.al. Erreurs : ValueError (tailles, point d'ordre faible).

from core use len
from collections use append
use string as _s
use crypto.accel as _ax

const _BASE := [9, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
const _A24 := 121665

func _fail(message):
    raise("ValueError", "x25519 : " + message)

func _unpack(b):
    o := [0] * 16
    i := 0
    while i < 16:
        o[i] = b[2 * i] + (b[2 * i + 1] << 8)
        i += 1
    o[15] = o[15] & 32767
    return o

# Retenues : chaque limbe ramené à 16 bits, la retenue du dernier repliée (2^256 = 38 mod p).
func _car(o):
    i := 0
    while i < 16:
        o[i] = o[i] + 65536
        c := o[i] >> 16
        if i < 15:
            o[i + 1] = o[i + 1] + c - 1
        else:
            o[0] = o[0] + 38 * (c - 1)
        o[i] = o[i] - (c << 16)
        i += 1

func _sel(p, q, b):
    m := -b                               # 0 ou tous les bits à 1
    i := 0
    while i < 16:
        t := m & (p[i] ^ q[i])
        p[i] = p[i] ^ t
        q[i] = q[i] ^ t
        i += 1

func _pack(n):
    t := n + []
    _car(t)
    _car(t)
    _car(t)
    j := 0
    while j < 2:
        m := [0] * 16
        m[0] = t[0] - 65517
        i := 1
        while i < 15:
            m[i] = t[i] - 65535 - ((m[i - 1] >> 16) & 1)
            m[i - 1] = m[i - 1] & 65535
            i += 1
        m[15] = t[15] - 32767 - ((m[14] >> 16) & 1)
        b := (m[15] >> 16) & 1
        m[14] = m[14] & 65535
        _sel(t, m, 1 - b)
        j += 1
    out := []
    i := 0
    while i < 16:
        append(out, t[i] & 255)
        append(out, t[i] >> 8)
        i += 1
    return out

func _add(a, b):
    return [a[i] + b[i] for i in _I16]

func _sub(a, b):
    return [a[i] - b[i] for i in _I16]

func _mul(a, b):
    t := [0] * 31
    i := 0
    while i < 16:
        ai := a[i]
        j := 0
        while j < 16:
            t[i + j] = t[i + j] + ai * b[j]
            j += 1
        i += 1
    i = 0
    while i < 15:
        t[i] = t[i] + 38 * t[i + 16]
        i += 1
    o := t[0:16]
    _car(o)
    _car(o)
    return o

func _inv(a):
    c := a + []
    k := 253
    while k >= 0:
        c = _mul(c, c)
        if k != 2 and k != 4:
            c = _mul(c, a)
        k -= 1
    return c

func _range16():
    out := []
    i := 0
    while i < 16:
        append(out, i)
        i += 1
    return out

const _I16 := _range16()

# Multiplication scalaire X25519(k, u) (RFC 7748, 5).
func scalar_mult(k, u):
    if len(k) != 32 or len(u) != 32:
        _fail("scalaire et coordonnée de 32 octets attendus")
    if _ax.has("x25519"):
        return _s.byte_unpack(_ax.native().x25519(_s.byte_pack(k), _s.byte_pack(u)))
    z := k + []
    z[31] = (z[31] & 127) | 64
    z[0] = z[0] & 248
    x := _unpack(u)
    a := [1] + [0] * 15
    b := x + []
    c := [0] * 16
    d := [1] + [0] * 15
    a24 := [_A24] + [0] * 15
    i := 254
    while i >= 0:
        r := (z[i >> 3] >> (i & 7)) & 1
        _sel(a, b, r)
        _sel(c, d, r)
        e := _add(a, c)
        a = _sub(a, c)
        c = _add(b, d)
        b = _sub(b, d)
        d = _mul(e, e)
        f := _mul(a, a)
        a = _mul(c, a)
        c = _mul(b, e)
        e = _add(a, c)
        a = _sub(a, c)
        b = _mul(a, a)
        c = _sub(d, f)
        a = _mul(c, a24)
        a = _add(a, d)
        c = _mul(c, a)
        a = _mul(d, f)
        d = _mul(b, x)
        b = _mul(e, e)
        _sel(a, b, r)
        _sel(c, d, r)
        i -= 1
    return _pack(_mul(a, _inv(c)))

func public_key(private):
    return scalar_mult(private, _BASE)

# Secret partagé ; un résultat nul (point d'ordre faible envoyé par le pair) est refusé (RFC 7748, 6.1).
func shared(private, peer_public):
    s := scalar_mult(private, peer_public)
    acc := 0
    for v in s:
        acc = acc | v
    if acc == 0:
        _fail("secret partagé nul (clé publique du pair invalide)")
    return s
