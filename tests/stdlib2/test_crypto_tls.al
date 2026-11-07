# Tests : primitives de TLS 1.3 en ALEX pur — SHA-384 (crypto), HMAC, HKDF (crypto.hkdf), AES (crypto.aes),
# AES-GCM (crypto.gcm), Poly1305 et ChaCha20-Poly1305 (crypto.poly1305), grands entiers (crypto.bigint).
# Vecteurs des normes (FIPS 180-4, FIPS 197, RFC 4231, 5869, 8439, cas GCM de McGrew et Viega), puis 175 vecteurs
# aléatoires calculés par OpenSSL et les entiers de Python (tools/gen_crypto_vectors.py -> data/crypto_tls.json).
from core use len
use check as t
use io
use os
use json
use crypto
use crypto.aes as aes
use crypto.gcm as gcm
use crypto.poly1305 as p1305
use crypto.hkdf as hkdf
use crypto.bigint as bn

func hx(s):
    return crypto.hex_decode(s)

func eh(b):
    return crypto.hex_encode(b)

# ---------------------------------------------------------------- vecteurs des normes

t.eq(crypto.sha384("abc"), "cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7", "SHA-384 abc")
t.eq(crypto.sha384(""), "38b060a751ac96384cd9327eb1b1e36a21fdb71114be07434c0cc7bf63f6e1da274edebfe76f65fbd51ad2f14898b95b", "SHA-384 vide")
t.eq(crypto.sha384("abcdefghbcdefghicdefghijdefghijkefghijklfghijklmghijklmnhijklmnoijklmnopjklmnopqklmnopqrlmnopqrsmnopqrstnopqrstu"), "09330c33f71147e83d192fc782cd1b4753111b173b3b05d22fa08086e3b0f712fcc7c71a557e2db966c3e9fa91746039", "SHA-384 deux blocs")
t.eq(crypto.sha512("abc")[0:16], "ddaf35a193617aba", "SHA-512 inchangé")
t.eq(crypto.hmac("sha384", hx("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), "Hi There"), "afd03944d84895626b0825f4ab46907f15f9dadbe4101ec682aa034c7cebc59cfaea9ea9076ede7f4af152e8b2fa9cb6", "HMAC-SHA-384 RFC 4231 cas 1")

prk := hkdf.extract("sha256", hx("000102030405060708090a0b0c"), hx("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"))
t.eq(eh(prk), "077709362c2e32df0ddc3f0dc47bba6390b6c73bb50f9c3122ec844ad7c2b3e5", "HKDF RFC 5869 A.1 PRK")
t.eq(eh(hkdf.expand("sha256", prk, hx("f0f1f2f3f4f5f6f7f8f9"), 42)), "3cb25f25faacd57a90434f64d0362f2a2d2d0a90cf1a5a4c5db02d56ecc4c5bf34007208d5b887185865", "HKDF RFC 5869 A.1 OKM")
t.eq(eh(hkdf.derive("sha256", hx("0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b"), 42)), "8da4e775a563c18f715f802a063c5a31b8a11f5c5ee1879ec3454e5f3c738d2d9d201395faa4b61a96c8", "HKDF RFC 5869 A.3 (sans sel ni info)")
t.raises(() => hkdf.expand("sha256", prk, [], 255 * 32 + 1), "ValueError", "HKDF longueur maximale")
t.raises(() => hkdf.extract("md5", [], []), "ValueError", "HKDF algorithme refusé")

pt := hx("00112233445566778899aabbccddeeff")
t.eq(eh(aes.encrypt_block(aes.key(hx("000102030405060708090a0b0c0d0e0f")), pt)), "69c4e0d86a7b0430d8cdb78070b4c55a", "AES-128 FIPS 197 C.1")
t.eq(eh(aes.encrypt_block(aes.key(hx("000102030405060708090a0b0c0d0e0f1011121314151617")), pt)), "dda97ca4864cdfe06eaf70a0ec0d7191", "AES-192 FIPS 197 C.2")
t.eq(eh(aes.encrypt_block(aes.key(hx("000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f")), pt)), "8ea2b7ca516745bfeafc49904b496089", "AES-256 FIPS 197 C.3")
t.raises(() => aes.key([0] * 15), "ValueError", "AES taille de clé")

g0 := gcm.AesGcm([0] * 16)
t.eq(eh(g0.seal([0] * 12, [])), "58e2fccefa7e3061367f1d57a4e7455a", "GCM cas 1")
t.eq(eh(g0.seal([0] * 12, [0] * 16)), "0388dace60b6a392f328c2b971b2fe78ab6e47d42cec13bdf53a67b21257bddf", "GCM cas 2")
g4 := gcm.AesGcm(hx("feffe9928665731c6d6a8f9467308308"))
p4 := hx("d9313225f88406e5a55909c5aff5269a86a7a9531534f7da2e4c303d8a318a721c3c0c95956809532fcf0e2449a6b525b16aedf5aa0de657ba637b39")
a4 := hx("feedfacedeadbeeffeedfacedeadbeefabaddad2")
n4 := hx("cafebabefacedbaddecaf888")
s4 := g4.seal(n4, p4, a4)
t.eq(eh(s4), "42831ec2217774244b7221b784d0d49ce3aa212f2c02a4e035c17e2329aca12e21d514b25466931c7d8f6a5aac84aa051ba30b396a0aac973d58e0915bc94fbc3221a5db94fae95ae7121a47", "GCM cas 4 (données associées)")
t.eq(g4.open(n4, s4, a4), p4, "GCM ouverture")
for i in [0, 59, len(s4) - 1]:
    alt := s4 + []
    alt[i] = alt[i] ^ 128
    t.raises(() => g4.open(n4, alt, a4), "AuthenticationError", "GCM altération à l'octet " + str(i))
t.raises(() => g4.open(n4, s4, a4 + [0]), "AuthenticationError", "GCM données associées altérées")
t.raises(() => g4.open(hx("cafebabefacedbaddecaf889"), s4, a4), "AuthenticationError", "GCM autre nonce")
t.raises(() => g4.seal([0] * 8, []), "ValueError", "GCM nonce de 8 octets")

t.eq(eh(p1305.mac(hx("85d6be7857556d337f4452fe42d506a80103808afb0db2fd4abff6af4149f51b"), crypto.utf8_encode("Cryptographic Forum Research Group"))), "a8061dc1305136c6c22b8baf0c0127a9", "Poly1305 RFC 8439 2.5.2")
ck := hx("808182838485868788898a8b8c8d8e8f909192939495969798999a9b9c9d9e9f")
cn := hx("070000004041424344454647")
ca := hx("50515253c0c1c2c3c4c5c6c7")
cp := crypto.utf8_encode("Ladies and Gentlemen of the class of '99: If I could offer you only one tip for the future, sunscreen would be it.")
cs := p1305.seal(ck, cn, cp, ca)
t.eq(eh(cs), "d31a8d34648e60db7b86afbc53ef7ec2a4aded51296e08fea9e2b5a736ee62d63dbea45e8ca9671282fafb69da92728b1a71de0a9e060b2905d6a5b67ecd3b3692ddbd7f2d778b8c9803aee328091b58fab324e4fad675945585808b4831d7bc3ff4def08e4b7a9de576d26586cec64b61161ae10b594f09e26a7e902ecbd0600691", "ChaCha20-Poly1305 RFC 8439 2.8.2")
t.eq(p1305.open(ck, cn, cs, ca), cp, "ChaCha20-Poly1305 ouverture")
alt := cs + []
alt[5] = alt[5] ^ 1
t.raises(() => p1305.open(ck, cn, alt, ca), "AuthenticationError", "ChaCha20-Poly1305 altération")
t.raises(() => p1305.open(ck, cn, cs[0:15], ca), "AuthenticationError", "ChaCha20-Poly1305 trop court")

# ---------------------------------------------------------------- vecteurs aléatoires (OpenSSL, Python)

v := json.parse(io.read_file(os.join(os.dirname(os.argv()[0]), "data/crypto_tls.json")))

for x in v["sha384"]:
    t.eq(crypto.hex_encode(crypto.sha384_bytes(hx(x["msg"]))), x["digest"], "SHA-384 " + str(len(x["msg"]) // 2) + " octets")
for x in v["hmac"]:
    t.eq(crypto.hmac(x["algo"], hx(x["key"]), hx(x["msg"])), x["mac"], "HMAC-" + x["algo"] + " clé de " + str(len(x["key"]) // 2))
for x in v["hkdf"]:
    t.eq(eh(hkdf.derive(x["algo"], hx(x["ikm"]), x["length"], hx(x["salt"]), hx(x["info"]))), x["okm"], "HKDF-" + x["algo"] + " " + str(x["length"]))
for x in v["aes"]:
    t.eq(eh(aes.encrypt_block(aes.key(hx(x["key"])), hx(x["pt"]))), x["ct"], "AES-" + str(len(x["key"]) * 4))
for x in v["gcm"]:
    g := gcm.AesGcm(hx(x["key"]))
    s := g.seal(hx(x["nonce"]), hx(x["pt"]), hx(x["aad"]))
    t.eq(eh(s), x["sealed"], "AES-" + str(len(x["key"]) * 4) + "-GCM " + str(len(x["pt"]) // 2) + " octets")
    t.eq(eh(g.open(hx(x["nonce"]), s, hx(x["aad"]))), x["pt"], "AES-GCM ouverture " + str(len(x["pt"]) // 2))
for x in v["chacha"]:
    s := p1305.seal(hx(x["key"]), hx(x["nonce"]), hx(x["pt"]), hx(x["aad"]))
    t.eq(eh(s), x["sealed"], "ChaCha20-Poly1305 " + str(len(x["pt"]) // 2) + " octets")
    t.eq(eh(p1305.open(hx(x["key"]), hx(x["nonce"]), s, hx(x["aad"]))), x["pt"], "ChaCha20-Poly1305 ouverture " + str(len(x["pt"]) // 2))
for x in v["poly1305"]:
    t.eq(eh(p1305.mac(hx(x["key"]), hx(x["msg"]))), x["tag"], "Poly1305 " + str(len(x["msg"]) // 2) + " octets")

for x in v["bigint"]:
    a := bn.from_hex(x["a"])
    b := bn.from_hex(x["b"])
    lab := " (" + str(bn.bit_length(a)) + " / " + str(bn.bit_length(b)) + " bits)"
    t.eq(bn.to_hex(bn.add(a, b)), x["add"], "bigint add" + lab)
    t.eq(bn.to_hex(bn.mul(a, b)), x["mul"], "bigint mul" + lab)
    t.eq(bn.to_hex(bn.sub(a, b) if bn.cmp(a, b) >= 0 else bn.sub(b, a)), x["sub"], "bigint sub" + lab)
    qr := bn.divmod(a, b)
    t.eq([bn.to_hex(qr[0]), bn.to_hex(qr[1])], [x["q"], x["r"]], "bigint divmod" + lab)
    t.eq(bn.from_bytes(bn.to_bytes(a)), a, "bigint octets aller-retour" + lab)
    t.eq(bn.shr(bn.shl(a, 77), 77), a, "bigint décalages" + lab)
for x in v["modpow"]:
    t.eq(bn.to_hex(bn.modpow(bn.from_hex(x["base"]), bn.from_hex(x["e"]), bn.from_hex(x["m"]))), x["r"], "bigint modpow " + str(len(x["m"]) * 4) + " bits, exposant de " + str(len(x["e"]) * 4))
for x in v["modinv"]:
    t.eq(bn.to_hex(bn.modinv(bn.from_hex(x["a"]), bn.from_hex(x["m"]))), x["inv"], "bigint modinv " + str(len(x["m"]) * 4) + " bits")

t.eq(bn.to_bytes(bn.from_int(258), 4), [0, 0, 1, 2], "bigint to_bytes avec longueur")
t.raises(() => bn.to_bytes(bn.from_int(65536), 2), "ValueError", "bigint to_bytes trop court")
t.raises(() => bn.sub(bn.from_int(1), bn.from_int(2)), "ValueError", "bigint soustraction négative")
t.raises(() => bn.divmod(bn.from_int(1), []), "ValueError", "bigint division par zéro")
t.raises(() => bn.modinv(bn.from_int(6), bn.from_int(9)), "ValueError", "bigint pas d'inverse")
t.eq(bn.to_int(bn.from_hex("3fffffffffffffff")), 4611686018427387903, "bigint to_int")
t.eq(bn.from_bytes([0, 0, 0]), [], "bigint zéro")

t.summary("test_crypto_tls")
