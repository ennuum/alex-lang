#!/usr/bin/env python3
"""Génère tests/stdlib2/data/crypto_pk.json : vecteurs pour crypto.x25519, crypto.ec (P-256, P-384 : ECDH,
ECDSA RFC 6979) et crypto.rsa (PKCS#1 v1.5, PSS), calculés par la bibliothèque Python « cryptography » (OpenSSL).
Les clés sont tirées au hasard à chaque génération ; le fichier produit est versionné.

    python3 tools/gen_crypto_pk_vectors.py
"""
import hashlib
import json
import os
import random

from cryptography.hazmat.primitives import hashes, serialization
from cryptography.hazmat.primitives.asymmetric import ec, padding, rsa, x25519
from cryptography.hazmat.primitives.asymmetric.utils import decode_dss_signature

rnd = random.Random(1107)


def rb(n):
    return bytes(rnd.getrandbits(8) for _ in range(n))


def h(n):
    return format(n, "x")


HASHES = {"sha256": hashes.SHA256(), "sha384": hashes.SHA384(), "sha512": hashes.SHA512()}
out = {}

# ---------------------------------------------------------------- X25519
out["x25519"] = []
for _ in range(4):
    a = x25519.X25519PrivateKey.generate()
    b = x25519.X25519PrivateKey.generate()
    raw = serialization.Encoding.Raw
    out["x25519"].append({
        "priv": a.private_bytes(raw, serialization.PrivateFormat.Raw, serialization.NoEncryption()).hex(),
        "pub": a.public_key().public_bytes(raw, serialization.PublicFormat.Raw).hex(),
        "peer": b.public_key().public_bytes(raw, serialization.PublicFormat.Raw).hex(),
        "shared": a.exchange(b.public_key()).hex()})

# ---------------------------------------------------------------- ECDSA, ECDH
out["ec"] = []
for name, curve, algo in [("P-256", ec.SECP256R1(), "sha256"), ("P-384", ec.SECP384R1(), "sha384"), ("P-256", ec.SECP256R1(), "sha384")]:
    for _ in range(3):
        k = ec.generate_private_key(curve)
        other = ec.generate_private_key(curve)
        msg = rb(rnd.randrange(0, 100))
        pt = serialization.PublicFormat.UncompressedPoint
        det = k.sign(msg, ec.ECDSA(HASHES[algo], deterministic_signing=True))
        ran = k.sign(msg, ec.ECDSA(HASHES[algo]))
        size = (curve.key_size + 7) // 8
        out["ec"].append({
            "curve": name, "hash": algo, "msg": msg.hex(),
            "priv": k.private_numbers().private_value.to_bytes(size, "big").hex(),
            "pub": k.public_key().public_bytes(serialization.Encoding.X962, pt).hex(),
            "det_der": det.hex(), "random_der": ran.hex(),
            "peer": other.public_key().public_bytes(serialization.Encoding.X962, pt).hex(),
            "shared": k.exchange(ec.ECDH(), other.public_key()).hex()})

# ---------------------------------------------------------------- RSA


def mgf1(algo, seed, n):
    out_ = b""
    c = 0
    while len(out_) < n:
        out_ += hashlib.new(algo, seed + c.to_bytes(4, "big")).digest()
        c += 1
    return out_[:n]


def pss_sign(priv, msg, algo, salt):
    nums = priv.private_numbers()
    n = nums.public_numbers.n
    embits = n.bit_length() - 1
    emlen = (embits + 7) // 8
    mh = hashlib.new(algo, msg).digest()
    hh = hashlib.new(algo, b"\0" * 8 + mh + salt).digest()
    db = b"\0" * (emlen - len(salt) - len(hh) - 2) + b"\1" + salt
    mask = mgf1(algo, hh, emlen - len(hh) - 1)
    masked = bytearray(x ^ y for x, y in zip(db, mask))
    masked[0] &= 0xFF >> (8 * emlen - embits)
    em = bytes(masked) + hh + b"\xbc"
    s = pow(int.from_bytes(em, "big"), nums.d, n)
    return s.to_bytes((n.bit_length() + 7) // 8, "big")


out["rsa"] = []
for bits in [2048, 3072]:
    k = rsa.generate_private_key(public_exponent=65537, key_size=bits)
    nums = k.private_numbers()
    entry = {"bits": bits, "n": h(nums.public_numbers.n), "e": h(nums.public_numbers.e), "d": h(nums.d), "p": h(nums.p),
             "q": h(nums.q), "dp": h(nums.dmp1), "dq": h(nums.dmq1), "qinv": h(nums.iqmp), "cases": []}
    for algo in ["sha256", "sha384"]:
        msg = rb(rnd.randrange(0, 120))
        salt = rb(hashlib.new(algo).digest_size)
        pss = pss_sign(k, msg, algo, salt)
        k.public_key().verify(pss, msg, padding.PSS(mgf=padding.MGF1(HASHES[algo]), salt_length=len(salt)), HASHES[algo])
        entry["cases"].append({
            "hash": algo, "msg": msg.hex(),
            "pkcs1": k.sign(msg, padding.PKCS1v15(), HASHES[algo]).hex(),
            "pss_openssl": k.sign(msg, padding.PSS(mgf=padding.MGF1(HASHES[algo]), salt_length=padding.PSS.DIGEST_LENGTH), HASHES[algo]).hex(),
            "pss_salt": salt.hex(), "pss_fixed": pss.hex()})
    out["rsa"].append(entry)

dest = os.path.join(os.path.dirname(__file__), "..", "tests", "stdlib2", "data", "crypto_pk.json")
os.makedirs(os.path.dirname(dest), exist_ok=True)
with open(dest, "w") as f:
    json.dump(out, f, indent=0, sort_keys=True)
print(dest)
