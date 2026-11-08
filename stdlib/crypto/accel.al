# ALEX STANDARD LIBRARY — crypto.accel
#
# Calculs cryptographiques du runtime (module natif _native_tls, écrits dans le dialecte typé du runtime : entiers
# machine) pour les modules écrits en Alex : X25519, exponentiation et multiplication modulaires, multiplication de
# points P-256 / P-384, AES-GCM, SHA-256 et HMAC-SHA-256. Ils servent dans la VM comme dans les exécutables
# natifs, sans OpenSSL. Chaque primitive est essayée une fois sur un vecteur connu ; si elle manque (runtime plus
# ancien) ou se trompe, has() vaut false et l'appelant calcule en Alex (mêmes résultats, beaucoup plus lent).
#
#   use crypto.accel as ax
#   if ax.has("x25519"): ...                  # « x25519 », « modpow », « mulmod », « ec_mul », « ecdsa_sign »,
#                                             # « aes_gcm », « sha256 »
#   ax.hash("sha256", octets) ; ax.hmac("sha256", cle, octets)   # repli sur le module crypto pour les autres
#   ax.disable()                              # tout en Alex (tests de comparaison) ; aussi ALEX_CRYPTO_ACCEL=0
#
# Octets : listes d'entiers 0..255 pour hash / hmac ; les primitives brutes (ax.native()) prennent des str.

from core use len
use string as _s
use crypto as _c
use _native_tls as _t
use os as _os

_known := {}
_off := [_os.getenv("ALEX_CRYPTO_ACCEL") == "0"]

func _hx(t):
    return _s.byte_pack(_c.hex_decode(t))

func _probe(name):
    if name == "x25519":
        return _t.x25519(_hx("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"), _hx("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c")) == _hx("c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552")
    if name == "modpow":
        return _t.modpow(_hx("03"), _hx("05"), _hx("07")) == _hx("05") and _t.modpow(_hx("0102"), _hx("010001"), _hx("c5d1")) == _hx("95e1")
    if name == "mulmod":
        return _t.mulmod(_hx("03"), _hx("05"), _hx("07")) == _hx("01")
    if name == "ec_mul":
        p := _hx("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff")
        gx := _hx("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296")
        gy := _hx("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
        two := _t.ec_mul(p, _hx("02"), gx, gy)
        return _s.byte_slice(two, 0, 32) == _hx("7cf27b188d034f7e8a52380304b51ac3c08969e277f21b35a60b48fc47669978")
    if name == "ecdsa_sign":
        # RFC 6979, A.2.5 : P-256, SHA-256, message « sample »
        p := _hx("ffffffff00000001000000000000000000000000ffffffffffffffffffffffff")
        n := _hx("ffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551")
        gx := _hx("6b17d1f2e12c4247f8bce6e563a440f277037d812deb33a0f4a13945d898c296")
        gy := _hx("4fe342e2fe1a7f9b8ee7eb4a7c0f9e162bce33576b315ececbb6406837bf51f5")
        k := _hx("a6e3c57dd01abe90086538398355dd4c3b17aa873382b0f24d6129493d8aad60")
        d := _hx("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721")
        e := _hx("af2bdbe1aa9b6ec1e2ade1d694f41fc71a831d0268e9891562113d8a62add1bf")
        return _t.ecdsa_sign(p, n, gx, gy, k, d, e) == _hx("efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8")
    if name == "aes_gcm":
        z := _hx("00000000000000000000000000000000")
        out := _t.aes_gcm(true, z, _s.byte_slice(z, 0, 12), z, "")
        return out == _hx("0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf") and _t.aes_gcm(false, z, _s.byte_slice(z, 0, 12), out, "") == z
    if name == "sha256":
        return _t.digest("sha256", "abc") == _hx("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad") and _t.hmac("sha256", "key", "The quick brown fox jumps over the lazy dog") == _hx("f7bc83f430538424b13298e6aa6fb143ef4d59a14946175997479dbc2d1a3cd8")
    return false

# La primitive name est-elle disponible (et juste) ?
func has(name):
    if _off[0]:
        return false
    if name in _known:
        return _known[name]
    ok := false
    try:
        ok = _probe(name)
    catch e:
        ok = false
    _known[name] = ok
    return ok

# Désactive (ou réactive) les calculs du runtime : tout se fait en Alex.
func disable(off=true):
    _off[0] = off

# Module natif (primitives brutes, sur des str).
func native():
    return _t

func hash(algo, data):
    if algo == "sha256" and has("sha256"):
        return _s.byte_unpack(_t.digest("sha256", _s.byte_pack(data)))
    return _c.hash_bytes(algo, data)

func hmac(algo, key, data):
    if algo == "sha256" and has("sha256"):
        return _s.byte_unpack(_t.hmac("sha256", _s.byte_pack(key), _s.byte_pack(data)))
    return _c.hmac_bytes(algo, key, data)
