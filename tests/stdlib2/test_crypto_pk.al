# Tests : clés publiques de TLS 1.3 en ALEX pur — X25519 (crypto.x25519), P-256 / P-384 : ECDH et ECDSA
# (crypto.ec), RSA PKCS#1 v1.5 et PSS (crypto.rsa). Vecteurs des RFC 7748 et 6979, puis vecteurs calculés par
# OpenSSL (tools/gen_crypto_pk_vectors.py -> data/crypto_pk.json) : signatures identiques au bit près
# (ECDSA déterministe, PKCS#1 v1.5, PSS à sel fixé), signatures d'OpenSSL vérifiées, secrets ECDH identiques.
from core use len
use check as t
use io
use os
use json
use crypto
use crypto.x25519 as x25519
use crypto.ec as ec
use crypto.rsa as rsa
use crypto.bigint as bn

func hx(s):
    return crypto.hex_decode(s)

func eh(b):
    return crypto.hex_encode(b)

# ---------------------------------------------------------------- RFC 7748

t.eq(eh(x25519.scalar_mult(hx("a546e36bf0527c9d3b16154b82465edd62144c0ac1fc5a18506a2244ba449ac4"), hx("e6db6867583030db3594c1a424b15f7c726624ec26b3353b10a903a6d0ab1c4c"))), "c3da55379de9c6908e94ea4df28d084f32eccf03491c71f754b4075577a28552", "X25519 RFC 7748 5.2")
alice := hx("77076d0a7318a57d3c16c17251b26645df4c2f87ebc0992ab177fba51db92c2a")
bob := hx("5dab087e624a8a4b79e17f8b83800ee66f3bb1292618b6fd1c2f8b27ff88e0eb")
t.eq(eh(x25519.public_key(alice)), "8520f0098930a754748b7ddcb43ef75a0dbf3a0d26381af4eba4a98eaa9b4e6a", "X25519 RFC 7748 6.1 public Alice")
t.eq(eh(x25519.public_key(bob)), "de9edb7d7b7dc1b4d35b61c2ece435373f8343c85b78674dadfc7e146f882b4f", "X25519 RFC 7748 6.1 public Bob")
t.eq(eh(x25519.shared(alice, x25519.public_key(bob))), "4a5d9d5ba4ce2de1728e3bf480350f25e07e21c947d19e3376f09b3c1e161742", "X25519 RFC 7748 6.1 secret")
t.raises(() => x25519.shared(alice, [0] * 32), "ValueError", "X25519 point d'ordre faible refusé")
t.raises(() => x25519.scalar_mult(alice, [9] * 31), "ValueError", "X25519 taille")

# ---------------------------------------------------------------- RFC 6979 (A.2.5, P-256)

c256 := ec.curve("P-256")
k6979 := ec.private_key(c256, hx("c9afa9d845ba75166b5c215767b1d6934e50c3db36e89b127b8a622b120f6721"))
t.eq(eh(k6979.public_bytes()), "0460fed4ba255a9d31c961eb74c6356d68c049b8923b61fa6ce669622e60f29fb67903fe1008b8bc99a41ae9e95628bc64f2f1b20c2d7e9f5177a3c294d4462299", "P-256 RFC 6979 clé publique")
sg := ec.sign(k6979, crypto.utf8_encode("sample"), "sha256")
t.eq([bn.to_hex(sg[0]), bn.to_hex(sg[1])], ["efd48b2aacb6a8fd1140dd9cd45e81d69d2c877b56aaf991c34d0ea84eaf3716", "f7cb1c942d657c41d436c7a1b6e29f65f3e900dbb9aff4064dc4ab2f843acda8"], "ECDSA RFC 6979 « sample »")
sg = ec.sign(k6979, crypto.utf8_encode("test"), "sha256")
t.eq([bn.to_hex(sg[0]), bn.to_hex(sg[1])], ["f1abb023518351cd71d881567b1ea663ed3efcf6c5132b354f28d3b0b7d38367", "19f4113742a2b14bd25926b49c649155f267e60d3814b4c0cc84250e46f0083"], "ECDSA RFC 6979 « test »")
t.check(ec.verify(k6979.public, crypto.utf8_encode("test"), sg, "sha256"), "ECDSA vérification")
t.check(not ec.verify(k6979.public, crypto.utf8_encode("tesu"), sg, "sha256"), "ECDSA message altéré")
t.check(not ec.verify(k6979.public, crypto.utf8_encode("test"), [sg[0], bn.add(sg[1], [1])], "sha256"), "ECDSA s altéré")
t.check(not ec.verify(k6979.public, crypto.utf8_encode("test"), [[], sg[1]], "sha256"), "ECDSA r nul")
t.check(not ec.verify(k6979.public, crypto.utf8_encode("test"), [sg[0], c256.n], "sha256"), "ECDSA s = n")
der := ec.sig_to_der(sg)
t.eq(ec.sig_from_der(der), sg, "ECDSA DER aller-retour")
t.check(not ec.verify_der(k6979.public, crypto.utf8_encode("test"), der + [0], "sha256"), "ECDSA DER octet en trop")
t.check(not ec.verify_der(k6979.public, crypto.utf8_encode("test"), [48, 6, 2, 1, 0, 2, 1, 1], "sha256"), "ECDSA DER r nul")
t.raises(() => ec.sig_from_der([48, 7, 2, 2, 0, 1, 2, 1, 1]), "ValueError", "ECDSA DER entier non minimal")
pubb := k6979.public_bytes()
bad := pubb + []
bad[64] = bad[64] ^ 1
t.raises(() => ec.public_key(c256, bad), "ValueError", "point hors de la courbe refusé")
t.raises(() => ec.public_key(c256, [2] + pubb[1:33]), "ValueError", "point compressé refusé")
t.raises(() => ec.private_key(c256, bn.to_bytes(c256.n, 32)), "ValueError", "clé privée = n refusée")
t.raises(() => ec.private_key(c256, [0] * 32), "ValueError", "clé privée nulle refusée")

# ---------------------------------------------------------------- vecteurs d'OpenSSL

v := json.parse(io.read_file(os.join(os.dirname(os.argv()[0]), "data/crypto_pk.json")))

for x in v["x25519"]:
    t.eq(eh(x25519.public_key(hx(x["priv"]))), x["pub"], "X25519 clé publique")
    t.eq(eh(x25519.shared(hx(x["priv"]), hx(x["peer"]))), x["shared"], "X25519 secret partagé")

for x in v["ec"]:
    c := ec.curve(x["curve"])
    lab := x["curve"] + "/" + x["hash"]
    k := ec.private_key(c, hx(x["priv"]))
    msg := hx(x["msg"])
    t.eq(eh(k.public_bytes()), x["pub"], lab + " clé publique")
    t.eq(eh(ec.sign_der(k, msg, x["hash"])), x["det_der"], lab + " ECDSA déterministe identique à OpenSSL")
    pub := ec.public_key(c, hx(x["pub"]))
    t.check(ec.verify_der(pub, msg, hx(x["random_der"]), x["hash"]), lab + " signature d'OpenSSL vérifiée")
    t.check(not ec.verify_der(pub, msg + [1], hx(x["random_der"]), x["hash"]), lab + " message altéré refusé")
    t.eq(eh(ec.ecdh(k, ec.public_key(c, hx(x["peer"])))), x["shared"], lab + " ECDH")

for kk in v["rsa"]:
    f := (name) => bn.from_hex(kk[name])
    key := rsa.PrivateKey(f("n"), f("e"), f("d"), f("p"), f("q"), f("dp"), f("dq"), f("qinv"))
    key2 := rsa.PrivateKey(f("n"), f("e"), f("d"), f("p"), f("q"))
    t.check(bn.eq(key2.qinv, key.qinv) and bn.eq(key2.dp, key.dp), "RSA-" + str(kk["bits"]) + " paramètres CRT recalculés")
    pub := rsa.PublicKey(f("n"), f("e"))
    for x in kk["cases"]:
        lab := "RSA-" + str(kk["bits"]) + "/" + x["hash"]
        msg := hx(x["msg"])
        t.eq(eh(rsa.sign_pkcs1(key, msg, x["hash"])), x["pkcs1"], lab + " PKCS#1 v1.5 identique à OpenSSL")
        t.check(rsa.verify_pkcs1(pub, msg, hx(x["pkcs1"]), x["hash"]), lab + " PKCS#1 v1.5 vérifiée")
        t.check(not rsa.verify_pkcs1(pub, msg + [0], hx(x["pkcs1"]), x["hash"]), lab + " PKCS#1 v1.5 message altéré")
        t.eq(eh(rsa.sign_pss(key, msg, x["hash"], null, hx(x["pss_salt"]))), x["pss_fixed"], lab + " PSS à sel fixé identique")
        t.check(rsa.verify_pss(pub, msg, hx(x["pss_openssl"]), x["hash"]), lab + " PSS d'OpenSSL vérifiée")
        alt := hx(x["pss_openssl"])
        alt[10] = alt[10] ^ 4
        t.check(not rsa.verify_pss(pub, msg, alt, x["hash"]), lab + " PSS altérée refusée")
        mine := rsa.sign_pss(key, msg, x["hash"])
        t.check(rsa.verify_pss(pub, msg, mine, x["hash"]) and not (eh(mine) == x["pss_fixed"]), lab + " PSS à sel aléatoire")
    t.raises(() => rsa.PrivateKey(f("n"), f("e"), f("d"), f("p"), bn.add(f("q"), [2])), "ValueError", "RSA p * q != n refusé")

t.summary("test_crypto_pk")
