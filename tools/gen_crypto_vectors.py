#!/usr/bin/env python3
"""Génère tests/stdlib2/data/crypto_tls.json : vecteurs de référence pour les primitives TLS d'ALEX
(crypto.aes, crypto.gcm, crypto.poly1305, crypto.hkdf, crypto.bigint, SHA-384 de crypto), calculés par la
bibliothèque Python « cryptography » (OpenSSL) et les entiers de Python. Graine fixe : le fichier est reproductible.

    python3 tools/gen_crypto_vectors.py
"""
import hashlib
import hmac
import json
import os
import random

from cryptography.hazmat.primitives import hashes, poly1305
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM, ChaCha20Poly1305
from cryptography.hazmat.primitives.kdf.hkdf import HKDF

rnd = random.Random(20261107)


def rb(n):
    return bytes(rnd.getrandbits(8) for _ in range(n))


def hx(b):
    return b.hex()


out = {}

out["sha384"] = []
for n in [0, 1, 3, 55, 56, 111, 112, 113, 127, 128, 129, 255, 1000]:
    m = rb(n)
    out["sha384"].append({"msg": hx(m), "digest": hashlib.sha384(m).hexdigest()})

out["hmac"] = []
for algo in ["sha256", "sha384", "sha512"]:
    for kl in [0, 20, 48, 64, 128, 131]:
        k = rb(kl)
        m = rb(rnd.randrange(0, 200))
        out["hmac"].append({"algo": algo, "key": hx(k), "msg": hx(m), "mac": hmac.new(k, m, algo).hexdigest()})

out["hkdf"] = []
for algo, h in [("sha256", hashes.SHA256()), ("sha384", hashes.SHA384())]:
    for _ in range(4):
        ikm = rb(rnd.randrange(1, 80))
        salt = rb(rnd.choice([0, 13, 32, 48, 80]))
        info = rb(rnd.randrange(0, 40))
        length = rnd.choice([1, 16, 32, 42, 48, 100, 255])
        okm = HKDF(algorithm=h, length=length, salt=salt if salt else None, info=info).derive(ikm)
        out["hkdf"].append({"algo": algo, "ikm": hx(ikm), "salt": hx(salt), "info": hx(info), "length": length, "okm": hx(okm)})

out["aes"] = []
for kl in [16, 24, 32]:
    for _ in range(4):
        k = rb(kl)
        p = rb(16)
        e = Cipher(algorithms.AES(k), modes.ECB()).encryptor()
        out["aes"].append({"key": hx(k), "pt": hx(p), "ct": hx(e.update(p) + e.finalize())})

out["gcm"] = []
for kl in [16, 24, 32]:
    for pl in [0, 1, 15, 16, 17, 31, 64, 100, 257]:
        k = rb(kl)
        n = rb(12)
        p = rb(pl)
        a = rb(rnd.choice([0, 1, 13, 16, 20, 40]))
        out["gcm"].append({"key": hx(k), "nonce": hx(n), "pt": hx(p), "aad": hx(a), "sealed": hx(AESGCM(k).encrypt(n, p, a))})

out["chacha"] = []
for pl in [0, 1, 15, 16, 17, 63, 64, 65, 100, 257]:
    k = rb(32)
    n = rb(12)
    p = rb(pl)
    a = rb(rnd.choice([0, 1, 12, 16, 33]))
    out["chacha"].append({"key": hx(k), "nonce": hx(n), "pt": hx(p), "aad": hx(a), "sealed": hx(ChaCha20Poly1305(k).encrypt(n, p, a))})

out["poly1305"] = []
for ml in [0, 1, 15, 16, 17, 32, 33, 64, 100, 131]:
    k = rb(32)
    m = rb(ml)
    out["poly1305"].append({"key": hx(k), "msg": hx(m), "tag": hx(poly1305.Poly1305.generate_tag(k, m))})
# cas limites de la réduction : h proche de 2^130 - 5 (clé s nulle, r maximal, messages de 0xff)
for _ in range(3):
    k = bytes([0xff] * 16) + bytes(16)
    m = bytes([0xff] * rnd.choice([16, 32, 48]))
    out["poly1305"].append({"key": hx(k), "msg": hx(m), "tag": hx(poly1305.Poly1305.generate_tag(k, m))})


def h(n):
    return format(n, "x")


out["bigint"] = []
for bits_a, bits_b in [(1, 1), (25, 26), (26, 26), (52, 27), (64, 64), (200, 100), (512, 511), (1024, 1023), (2048, 1024), (4096, 2048), (4096, 26), (3000, 2999), (777, 300)]:
    for _ in range(2):
        a = rnd.getrandbits(bits_a) | (1 << (bits_a - 1))
        b = rnd.getrandbits(bits_b) | (1 << (bits_b - 1))
        q, r = divmod(a, b)
        out["bigint"].append({"a": h(a), "b": h(b), "add": h(a + b), "mul": h(a * b), "sub": h(abs(a - b)), "q": h(q), "r": h(r)})
# divisions où l'estimation qhat doit être corrigée : diviseurs à limbe de tête 2^25 et dividendes en 0x3ff…
for k in [2, 3, 5, 8]:
    b = (1 << (26 * k - 1)) + rnd.getrandbits(20)
    a = (1 << (26 * (k + 3))) - 1 - rnd.getrandbits(30)
    q, r = divmod(a, b)
    out["bigint"].append({"a": h(a), "b": h(b), "add": h(a + b), "mul": h(a * b), "sub": h(abs(a - b)), "q": h(q), "r": h(r)})

out["modpow"] = []
for bits in [8, 61, 255, 256, 521, 1024, 2048]:
    m = rnd.getrandbits(bits) | 1 | (1 << (bits - 1))
    for eb in [1, 2, 17, bits]:
        base = rnd.getrandbits(bits + 13)
        e = rnd.getrandbits(eb) | (1 << (eb - 1))
        out["modpow"].append({"base": h(base), "e": h(e), "m": h(m), "r": h(pow(base, e, m))})
for m in [2, 1 << 70, 1000, (1 << 127) * 6]:
    base = rnd.getrandbits(100)
    e = rnd.getrandbits(40) | 1
    out["modpow"].append({"base": h(base), "e": h(e), "m": h(m), "r": h(pow(base, e, m))})
out["modpow"].append({"base": h(12345), "e": "0", "m": h(1009), "r": h(1)})

out["modinv"] = []
p256 = 2**256 - 2**224 + 2**192 + 2**96 - 1
n256 = 0xffffffff00000000ffffffffffffffffbce6faada7179e84f3b9cac2fc632551
for m in [p256, n256, 2**255 - 19, 1000003, 2**127 - 1]:
    for _ in range(2):
        a = rnd.randrange(1, m)
        out["modinv"].append({"a": h(a), "m": h(m), "inv": h(pow(a, -1, m))})
# module composé (RSA) : a premier avec m
pq = 0xc5a3b1 * 0xf00d61
out["modinv"].append({"a": h(65537), "m": h(pq), "inv": h(pow(65537, -1, pq))})

dest = os.path.join(os.path.dirname(__file__), "..", "tests", "stdlib2", "data", "crypto_tls.json")
os.makedirs(os.path.dirname(dest), exist_ok=True)
with open(dest, "w") as f:
    json.dump(out, f, indent=0, sort_keys=True)
print(dest, sum(len(v) for v in out.values()), "vecteurs")
