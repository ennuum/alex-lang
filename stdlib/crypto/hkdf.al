# ALEX STANDARD LIBRARY — crypto.hkdf
# HKDF (RFC 5869) sur HMAC-SHA-256 / SHA-384 / SHA-512 (module crypto), en listes d'octets.
#
#   use crypto.hkdf as hkdf
#   prk := hkdf.extract("sha256", sel, materiau)          # sel null : zéros de la taille de l'empreinte
#   okm := hkdf.expand("sha256", prk, info, 42)           # au plus 255 * taille de l'empreinte
#   okm := hkdf.derive("sha384", materiau, 48, sel, info)  # extract puis expand
#
# Vérifié contre la RFC 5869 (annexe A) et OpenSSL dans tests/stdlib2/test_crypto_tls.al.
# Erreurs : ValueError (algorithme, longueur).

from core use len, type
from collections use append
use crypto as _c

const _SIZES := {"sha256": 32, "sha384": 48, "sha512": 64}

func hash_len(algo):
    if not (algo in _SIZES):
        raise("ValueError", "hkdf : algorithme sha256, sha384 ou sha512 attendu (obtenu " + str(algo) + ")")
    return _SIZES[algo]

func extract(algo, salt, ikm):
    n := hash_len(algo)
    s := salt if salt != null and len(salt) > 0 else [0] * n
    return _c.hmac_bytes(algo, s, ikm)

func expand(algo, prk, info, length):
    n := hash_len(algo)
    if type(length) != "int" or length < 0 or length > 255 * n:
        raise("ValueError", "hkdf : longueur de 0 à " + str(255 * n) + " octets attendue")
    inf := info if info != null else []
    out := []
    t := []
    i := 1
    while len(out) < length:
        t = _c.hmac_bytes(algo, prk, t + inf + [i])
        for b in t:
            if len(out) < length:
                append(out, b)
        i += 1
    return out

func derive(algo, ikm, length, salt=null, info=null):
    return expand(algo, extract(algo, salt, ikm), info, length)
